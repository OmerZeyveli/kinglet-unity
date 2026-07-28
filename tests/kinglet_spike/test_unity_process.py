"""test_unity_process.py -- Containment of a native process tree that orphans itself.

The measured fact these tests exist for (taken on this host, from a real
`Unity -batchmode -runTests` invocation): after a CLEAN exit, code 0, two
`dotnet exec .../DotNetSdkRoslyn/VBCSCompiler.dll` processes were still alive
with PPID = 1, while no `Editor/Unity` process remained. One survived more than
ten minutes. The plan's global constraint says cancellation, timeout, crash and
success must each leave no Unity, MCP helper or child process behind -- so a
plain batchmode invocation violates it today.

Two strategies are therefore ruled out before any test is written, and both are
pinned here as executable tests rather than as prose:

* "After Unity exits, walk its children and kill them" -- `test_orphan_is_no
  _longer_in_the_launchers_tree` shows there is nothing left to walk.
* "Kill any VBCSCompiler" -- the Roslyn compiler server is shared and
  pipe-named; it may belong to the user's own GUI Editor. Nothing in this
  module ever matches a process by name. Identity comes from the kernel's own
  process-group membership, established BEFORE the run.

Real processes are used wherever the property under test is a kernel property
(reparenting, group inheritance, signal delivery). Injectable seams cover the
rest, so Windows job-object logic and enumeration failures are exercised from
this Linux host.
"""
from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.unity import process as process_module
from tools.kinglet_spike.unity.process import (
    CleanupResult,
    ManagedProcess,
    PosixGroupContainment,
    ProcessSnapshot,
    WindowsJobContainment,
    _linux_pgid_table,
    _parse_job_pid_list,
    _parse_ps_pgid_table,
    assert_clean,
    default_pid_is_live,
)

FIXTURE_MODULE = "tests.kinglet_spike.fixtures.process_tree"
REPO = Path(__file__).resolve().parents[2]


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _wait_until(predicate, timeout: float = 10.0, interval: float = 0.02) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return predicate()


def _read_report(path: Path, timeout: float = 15.0) -> dict:
    if not _wait_until(path.exists, timeout=timeout):
        raise AssertionError(f"fixture never wrote its report at {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def _impossible_pid() -> int:
    """A pid number the kernel cannot have allocated, so no reuse race."""
    try:
        limit = int(Path("/proc/sys/kernel/pid_max").read_text().strip())
    except (OSError, ValueError):
        limit = 1 << 22
    return limit + 1


def _ppid_of(pid: int) -> int:
    raw = Path(f"/proc/{pid}/stat").read_bytes()
    return int(raw[raw.rindex(b")") + 2:].split()[1])


class _RealTreeCase(unittest.TestCase):
    """Base for tests that launch the real fixture tree and must never leak it."""

    def setUp(self) -> None:
        self._tmp = TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.workdir = Path(self._tmp.name)
        self.report = self.workdir / "tree.json"
        self._launched: list[ManagedProcess] = []

    def tearDown(self) -> None:
        # Belt and braces: even a failing test must not leave the 30-second
        # sleepers behind for the rest of the suite.
        for managed in self._launched:
            try:
                managed.cancel(2.0)
            except Exception:  # pragma: no cover - defensive cleanup only
                pass

    def launch(self, mode: str) -> ManagedProcess:
        managed = ManagedProcess.start(
            [sys.executable, "-m", FIXTURE_MODULE, mode, "--report", str(self.report)],
            cwd=REPO,
            env={**os.environ, "PYTHONPATH": str(REPO)},
            stdout_path=self.workdir / "stdout.log",
            stderr_path=self.workdir / "stderr.log",
        )
        self._launched.append(managed)
        return managed


@unittest.skipUnless(sys.platform.startswith("linux"), "real /proc tree assertions")
class RealProcessTreeTests(_RealTreeCase):
    def test_descendants_reports_the_live_child(self):
        managed = self.launch("parent")
        report = _read_report(self.report)
        child = report["child_pid"]
        self.assertTrue(
            _wait_until(lambda: child in managed.descendants()),
            f"child {child} never appeared in {managed.descendants()}",
        )
        self.assertNotIn(managed.pid, managed.descendants())

    def test_cancellation_leaves_no_descendant_and_no_survivor(self):
        managed = self.launch("parent")
        report = _read_report(self.report)
        child = report["child_pid"]
        self.assertTrue(_wait_until(lambda: child in managed.descendants()))

        result = managed.cancel(5.0)

        self.assertEqual((), result.survivors)
        self.assertEqual((), managed.descendants())
        self.assertFalse(_pid_alive(child))
        assert_clean(result)

    def test_timeout_outcome_leaves_no_descendant(self):
        managed = self.launch("parent")
        _read_report(self.report)
        # The fixture sleeps 30s; a short wait must report "still running".
        self.assertIsNone(managed.wait(0.5))
        result = managed.cancel(5.0)
        self.assertEqual((), result.survivors)
        self.assertEqual((), managed.descendants())

    def test_orphan_is_no_longer_in_the_launchers_tree(self):
        """The measured Unity shape: clean exit, live orphan, empty tree.

        This is the executable form of why "kill the exited process's
        children" cannot work. By the time the launcher's exit is observed,
        the survivor's parent is init.
        """
        managed = self.launch("orphan")
        report = _read_report(self.report)
        child = report["child_pid"]

        self.assertEqual(0, managed.wait(15.0), "orphan mode must exit cleanly")
        self.assertTrue(_pid_alive(child), "the fixture's orphan must outlive it")
        self.assertTrue(_wait_until(lambda: _ppid_of(child) == 1))
        self.assertEqual(1, _ppid_of(child))

        managed.cancel(5.0)
        self.assertFalse(_pid_alive(child))

    def test_clean_exit_still_requires_cleanup_and_then_reports_clean(self):
        managed = self.launch("orphan")
        report = _read_report(self.report)
        child = report["child_pid"]
        self.assertEqual(0, managed.wait(15.0))

        # Before cleanup the constraint is VIOLATED, and descendants() says so.
        self.assertIn(child, managed.descendants())

        result = managed.cancel(5.0)
        self.assertEqual((), result.survivors)
        self.assertEqual(0, result.exit_code)
        self.assertEqual((), managed.descendants())

    def test_group_membership_survives_reparenting_to_init(self):
        """The containment mechanism itself, stated as a property.

        The orphan's PPID becomes 1, but its process-group id stays equal to
        the session leader we launched. That is why signalling the GROUP works
        where signalling a tree does not.
        """
        managed = self.launch("orphan")
        report = _read_report(self.report)
        child = report["child_pid"]
        self.assertEqual(0, managed.wait(15.0))
        self.assertTrue(_wait_until(lambda: _ppid_of(child) == 1))
        self.assertEqual(managed.pgid, os.getpgid(child))
        managed.cancel(5.0)

    def test_launch_is_in_its_own_session_not_the_test_runners_group(self):
        managed = self.launch("parent")
        self.addCleanup(managed.cancel, 5.0)
        self.assertNotEqual(os.getpgrp(), managed.pgid)
        self.assertEqual(managed.pid, managed.pgid)

    def test_output_goes_to_files_and_never_to_a_pipe(self):
        """Unity's batchmode log is large enough to deadlock a pipe reader."""
        stdout_path = self.workdir / "out.log"
        managed = ManagedProcess.start(
            [sys.executable, "-c", "print('hello-from-child')"],
            cwd=REPO,
            env=dict(os.environ),
            stdout_path=stdout_path,
            stderr_path=self.workdir / "err.log",
        )
        self.addCleanup(managed.cancel, 5.0)
        self.assertEqual(0, managed.wait(15.0))
        managed.cancel(5.0)
        self.assertIn("hello-from-child", stdout_path.read_text(encoding="utf-8"))
        self.assertIsNone(managed.handle.stdout)
        self.assertIsNone(managed.handle.stderr)

    def test_context_manager_cleans_up_when_the_body_raises(self):
        report = self.report
        child_holder: list[int] = []
        with self.assertRaises(RuntimeError):
            with ManagedProcess.start(
                [sys.executable, "-m", FIXTURE_MODULE, "parent", "--report", str(report)],
                cwd=REPO,
                env={**os.environ, "PYTHONPATH": str(REPO)},
                stdout_path=self.workdir / "o.log",
                stderr_path=self.workdir / "e.log",
            ) as managed:
                child_holder.append(_read_report(report)["child_pid"])
                self.assertTrue(_wait_until(lambda: child_holder[0] in managed.descendants()))
                raise RuntimeError("boom")
        self.assertFalse(_pid_alive(child_holder[0]))

    def test_cancel_is_idempotent(self):
        managed = self.launch("parent")
        _read_report(self.report)
        first = managed.cancel(5.0)
        second = managed.cancel(5.0)
        self.assertEqual((), first.survivors)
        self.assertEqual((), second.survivors)
        self.assertEqual(first.exit_code, second.exit_code)

    def test_cwd_and_env_reach_the_child(self):
        target = self.workdir / "sub"
        target.mkdir()
        out = self.workdir / "cwdenv.log"
        managed = ManagedProcess.start(
            [sys.executable, "-c", "import os;print(os.getcwd());print(os.environ['KINGLET_PROBE'])"],
            cwd=target,
            env={**os.environ, "KINGLET_PROBE": "sentinel-value"},
            stdout_path=out,
            stderr_path=self.workdir / "cwdenv.err",
        )
        self.addCleanup(managed.cancel, 5.0)
        self.assertEqual(0, managed.wait(15.0))
        managed.cancel(5.0)
        text = out.read_text(encoding="utf-8")
        self.assertIn(str(target.resolve()), text)
        self.assertIn("sentinel-value", text)


# ---------------------------------------------------------------------------
# Seam-driven tests: every branch below runs on any host.
# ---------------------------------------------------------------------------

class _FakeHandle:
    """Minimal Popen stand-in that records the ORDER of calls made to it."""

    stdout = None
    stderr = None

    def __init__(self, pid: int, calls: list[str], exit_code: int | None = 0):
        self.pid = pid
        self.returncode: int | None = None
        self._exit_code = exit_code
        self._calls = calls

    def poll(self):
        return self.returncode

    def wait(self, timeout=None):
        self._calls.append("wait")
        self.returncode = self._exit_code
        return self._exit_code

    def kill(self):
        self._calls.append("handle-kill")


class _FakeContainment:
    """Scripted containment: members die after N signals, or never."""

    def __init__(self, members, dies_after: int | None = 1):
        self._members = tuple(members)
        self._dies_after = dies_after
        self.signals: list[bool] = []
        self.closed = False

    def live_members(self):
        if self._dies_after is not None and len(self.signals) >= self._dies_after:
            return ()
        return self._members

    def signal_all(self, hard: bool) -> None:
        self.signals.append(hard)

    def close(self) -> None:
        self.closed = True


def _managed_with(containment, calls=None, pid=4242, exit_code=0):
    calls = calls if calls is not None else []
    handle = _FakeHandle(pid, calls, exit_code=exit_code)
    return ManagedProcess(
        handle=handle,
        pgid=pid,
        containment=containment,
        sleeper=lambda _seconds: None,
        clock=_StepClock(),
    ), handle, calls


class _StepClock:
    """Monotonic clock that advances 1s per read, so deadlines always expire."""

    def __init__(self):
        self._now = 0.0

    def __call__(self) -> float:
        self._now += 1.0
        return self._now


class LaunchRefusalTests(unittest.TestCase):
    def test_refuses_when_the_child_shares_our_own_process_group(self):
        """A failed start_new_session would make killpg suicide."""
        with self.assertRaises(EvidenceError) as ctx:
            process_module._verify_containment_pgid(pgid=os.getpgrp(), pid=os.getpgrp())
        self.assertEqual("E_UNITY_PROCESS_UNSAFE", ctx.exception.code)

    def test_refuses_a_non_positive_process_group(self):
        # pid == pgid here on purpose: with pgid 0 or -1 the leader-identity
        # and own-group checks both pass, so ONLY the non-positive guard can
        # refuse. killpg(0) signals this controller's own group and killpg(-1)
        # broadcasts to every process the user owns.
        for bad in (0, -1):
            with self.subTest(pgid=bad):
                with self.assertRaises(EvidenceError) as ctx:
                    process_module._verify_containment_pgid(pgid=bad, pid=bad)
                self.assertEqual("E_UNITY_PROCESS_UNSAFE", ctx.exception.code)
                self.assertIn("non-positive", ctx.exception.detail)

    def test_refuses_when_the_group_leader_is_not_the_launched_process(self):
        own = os.getpgrp()
        stray = own + 1 if own + 1 != own else own + 2
        with self.assertRaises(EvidenceError) as ctx:
            process_module._verify_containment_pgid(pgid=stray, pid=stray + 100)
        self.assertEqual("E_UNITY_PROCESS_UNSAFE", ctx.exception.code)

    def test_accepts_a_leader_owned_group_distinct_from_ours(self):
        own = os.getpgrp()
        candidate = own + 1000
        process_module._verify_containment_pgid(pgid=candidate, pid=candidate)


class CancelSemanticsTests(unittest.TestCase):
    def test_soft_signal_first_then_no_escalation_when_the_group_dies(self):
        containment = _FakeContainment([7], dies_after=1)
        managed, _handle, _calls = _managed_with(containment)
        result = managed.cancel(5.0)
        self.assertEqual([False], containment.signals)
        self.assertFalse(result.escalated)
        self.assertEqual((), result.survivors)

    def test_escalates_to_a_hard_kill_when_the_group_ignores_the_soft_signal(self):
        containment = _FakeContainment([7], dies_after=2)
        managed, _handle, _calls = _managed_with(containment)
        result = managed.cancel(1.0)
        self.assertEqual([False, True], containment.signals)
        self.assertTrue(result.escalated)
        self.assertEqual((), result.survivors)

    def test_survivors_are_reported_and_assert_clean_raises(self):
        containment = _FakeContainment([7, 9], dies_after=None)
        managed, _handle, _calls = _managed_with(containment)
        result = managed.cancel(1.0)
        self.assertEqual((7, 9), result.survivors)
        with self.assertRaises(EvidenceError) as ctx:
            assert_clean(result)
        self.assertEqual("E_UNITY_PROCESS_LEAK", ctx.exception.code)
        self.assertIn("7", ctx.exception.detail)

    def test_assert_clean_passes_for_an_empty_result(self):
        assert_clean(CleanupResult(signalled=True, escalated=False, survivors=(), exit_code=0))

    def test_leader_is_reaped_only_after_the_group_is_empty(self):
        """PID-reuse safety: pgid == leader pid, so reaping the leader frees
        the very number we signal. The zombie leader is what pins it."""
        calls: list[str] = []

        class _RecordingContainment(_FakeContainment):
            def signal_all(self, hard: bool) -> None:
                calls.append("signal")
                super().signal_all(hard)

        recording = _RecordingContainment([7], dies_after=1)
        managed, _handle, _ = _managed_with(recording, calls=calls)
        managed.cancel(5.0)
        self.assertEqual(["signal", "wait"], calls)
        self.assertLess(calls.index("signal"), calls.index("wait"))

    def test_containment_is_closed_after_cancel(self):
        containment = _FakeContainment([], dies_after=1)
        managed, _handle, _calls = _managed_with(containment)
        managed.cancel(5.0)
        self.assertTrue(containment.closed)

    def test_descendants_excludes_the_leader_itself(self):
        containment = _FakeContainment([4242, 7, 9], dies_after=None)
        managed, _handle, _calls = _managed_with(containment, pid=4242)
        self.assertEqual((7, 9), managed.descendants())


class EnumerationAmbiguityTests(unittest.TestCase):
    def test_unenumerable_group_raises_rather_than_reporting_zero(self):
        """'I could not look' must never render as 'nothing is there'."""

        def _broken():
            raise EvidenceError("E_UNITY_PROCESS_UNKNOWN", "no process table")

        containment = PosixGroupContainment(
            pgid=9999,
            group_table_provider=_broken,
            signaller=lambda pgid, sig: None,
        )
        with self.assertRaises(EvidenceError) as ctx:
            containment.live_members()
        self.assertEqual("E_UNITY_PROCESS_UNKNOWN", ctx.exception.code)

    def test_cancel_still_signals_when_enumeration_is_impossible(self):
        """Cleanup does not depend on enumeration -- the kernel matches the
        group. Enumeration only produces EVIDENCE."""
        sent: list[int] = []

        def _broken():
            raise EvidenceError("E_UNITY_PROCESS_UNKNOWN", "no process table")

        containment = PosixGroupContainment(
            pgid=9999,
            group_table_provider=_broken,
            signaller=lambda pgid, sig: sent.append(sig),
        )
        managed, _handle, _calls = _managed_with(containment, pid=9999)
        with self.assertRaises(EvidenceError) as ctx:
            managed.cancel(1.0)
        self.assertEqual("E_UNITY_PROCESS_UNKNOWN", ctx.exception.code)
        self.assertEqual([signal.SIGTERM, signal.SIGKILL], sent)


class PosixGroupContainmentTests(unittest.TestCase):
    def _containment(self, table, sent=None):
        sent = sent if sent is not None else []
        return PosixGroupContainment(
            pgid=500,
            group_table_provider=lambda: table,
            signaller=lambda pgid, sig: sent.append((pgid, sig)),
        ), sent

    def test_live_members_selects_only_our_group(self):
        table = (
            ProcessSnapshot(pid=500, pgid=500),
            ProcessSnapshot(pid=501, pgid=500),
            ProcessSnapshot(pid=777, pgid=777),
        )
        containment, _sent = self._containment(table)
        self.assertEqual((500, 501), containment.live_members())

    def test_a_shared_compiler_server_in_another_group_is_never_touched(self):
        """A VBCSCompiler belonging to the user's GUI Editor is in ITS group."""
        table = (
            ProcessSnapshot(pid=500, pgid=500),
            ProcessSnapshot(pid=31337, pgid=1234),  # someone else's compiler server
        )
        containment, sent = self._containment(table)
        self.assertEqual((500,), containment.live_members())
        containment.signal_all(hard=False)
        self.assertEqual([(500, signal.SIGTERM)], sent)

    def test_signal_all_escalates_to_sigkill(self):
        containment, sent = self._containment(())
        containment.signal_all(hard=True)
        self.assertEqual([(500, signal.SIGKILL)], sent)

    def test_a_vanished_group_is_not_an_error(self):
        def _gone(pgid, sig):
            raise ProcessLookupError()

        containment = PosixGroupContainment(
            pgid=500, group_table_provider=lambda: (), signaller=_gone
        )
        containment.signal_all(hard=False)  # must not raise

    def test_a_permission_denied_signal_is_surfaced_not_swallowed(self):
        def _denied(pgid, sig):
            raise PermissionError("nope")

        containment = PosixGroupContainment(
            pgid=500, group_table_provider=lambda: (), signaller=_denied
        )
        with self.assertRaises(EvidenceError) as ctx:
            containment.signal_all(hard=False)
        self.assertEqual("E_UNITY_PROCESS_UNKNOWN", ctx.exception.code)


class LinuxProcTableTests(unittest.TestCase):
    def test_real_proc_table_contains_this_process_with_its_real_pgid(self):
        """Driven through the REAL reader, not a fabricated table."""
        if not sys.platform.startswith("linux"):
            self.skipTest("linux-only source")
        table = _linux_pgid_table()
        self.assertIsNotNone(table)
        found = [entry for entry in table if entry.pid == os.getpid()]
        self.assertEqual(1, len(found))
        self.assertEqual(os.getpgrp(), found[0].pgid)

    def test_a_real_zombie_is_excluded_from_the_table(self):
        """The bug this exclusion was added for, reproduced against /proc.

        `cancel()` leaves the leader unreaped on purpose so its pid (== the
        pgid we signal) cannot be recycled. Before this exclusion that zombie
        counted as a member of its own group, so every real cancellation
        reported its own leader as a survivor.
        """
        if not sys.platform.startswith("linux"):
            self.skipTest("linux-only source")
        zombie = subprocess.Popen([sys.executable, "-c", "pass"])
        try:
            self.assertTrue(_wait_until(
                lambda: Path(f"/proc/{zombie.pid}/stat").read_bytes()
                .rsplit(b")", 1)[1].split()[0] == b"Z"
            ))
            table = _linux_pgid_table()
            self.assertNotIn(zombie.pid, [entry.pid for entry in table])
            # ...and it really is still in /proc, so this is an exclusion,
            # not the process having disappeared.
            self.assertTrue(Path(f"/proc/{zombie.pid}").exists())
        finally:
            zombie.wait()

    def test_comm_containing_spaces_and_parens_is_parsed_from_the_last_paren(self):
        # /proc/<pid>/stat field 2 is the comm in parentheses and may contain
        # both spaces and ')'. Splitting on whitespace, or on the FIRST ')',
        # misreads every subsequent field -- including pgrp.
        raw = b"1234 (weird ) name) S 1 4321 4321 0 -1 4194560 0 0\n"
        self.assertEqual(4321, process_module._parse_proc_stat_pgid(raw))

    def test_a_stat_line_without_a_closing_paren_is_ambiguous_not_zero(self):
        with self.assertRaises(EvidenceError) as ctx:
            process_module._parse_proc_stat_pgid(b"1234 (unterminated S 1 4321\n")
        self.assertEqual("E_UNITY_PROCESS_UNKNOWN", ctx.exception.code)

    def test_a_stat_line_with_too_few_fields_is_ambiguous_not_zero(self):
        with self.assertRaises(EvidenceError) as ctx:
            process_module._parse_proc_stat_pgid(b"1234 (sh) S 1\n")
        self.assertEqual("E_UNITY_PROCESS_UNKNOWN", ctx.exception.code)


class PsTableTests(unittest.TestCase):
    """`ps -Ao pid=,pgid=,stat=` is the macOS fallback source.

    ownership.py had to stop parsing ps because a COMMAND LINE is a lossy,
    space-joined rendering of argv. That objection does not carry over: two of
    these columns are integers and the third is a state code, so there is no
    string to recover and nothing to guess.
    """

    def test_columns_parse_exactly(self):
        stdout = "  501   500 S\n  502   500 Ss+\n 9999  9999 R\n"
        self.assertEqual(
            (
                ProcessSnapshot(pid=501, pgid=500),
                ProcessSnapshot(pid=502, pgid=500),
                ProcessSnapshot(pid=9999, pgid=9999),
            ),
            _parse_ps_pgid_table(stdout),
        )

    def test_a_zombie_row_is_not_a_live_member(self):
        stdout = "  501   500 S\n  502   500 Z\n"
        self.assertEqual(
            (ProcessSnapshot(pid=501, pgid=500),), _parse_ps_pgid_table(stdout)
        )

    def test_an_unparseable_line_fails_closed(self):
        """Skipping a line could hide the very survivor we are looking for."""
        with self.assertRaises(EvidenceError) as ctx:
            _parse_ps_pgid_table("  501   500 S\nnot a row here\n")
        self.assertEqual("E_UNITY_PROCESS_UNKNOWN", ctx.exception.code)

    def test_a_short_row_fails_closed(self):
        with self.assertRaises(EvidenceError) as ctx:
            _parse_ps_pgid_table("  501   500\n")
        self.assertEqual("E_UNITY_PROCESS_UNKNOWN", ctx.exception.code)

    def test_empty_output_fails_closed(self):
        with self.assertRaises(EvidenceError) as ctx:
            _parse_ps_pgid_table("\n  \n")
        self.assertEqual("E_UNITY_PROCESS_UNKNOWN", ctx.exception.code)

    def test_the_real_ps_reader_sees_this_process(self):
        """Driven through the REAL `ps` invocation, not a fabricated string."""
        table = process_module._ps_pgid_table()
        self.assertIn(
            ProcessSnapshot(pid=os.getpid(), pgid=os.getpgrp()), table
        )


class _FakeJobApi:
    """Stand-in for the Win32 job-object calls, so the LOGIC runs on Linux."""

    def __init__(self, pids=(), fail_assign=False):
        self.pids = list(pids)
        self.terminated = False
        self.closed = False
        self.assigned: list[int] = []
        self.kill_on_close = False
        self._fail_assign = fail_assign

    def create_job(self):
        self.kill_on_close = True
        return 1234  # opaque handle value

    def assign(self, handle, pid):
        if self._fail_assign:
            raise EvidenceError("E_UNITY_PROCESS_UNSAFE", "assign failed")
        self.assigned.append(pid)

    def list_pids(self, handle):
        if self.terminated:
            return ()
        return tuple(self.pids)

    def terminate(self, handle):
        self.terminated = True

    def close(self, handle):
        self.closed = True


class WindowsJobContainmentTests(unittest.TestCase):
    """Windows containment is a Job Object with kill-on-close, not a group.

    Windows has no process groups in the POSIX sense and no `-projectPath`-
    style tree to walk either, so the equivalent guarantee comes from
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE. The ctypes plumbing cannot run here;
    the decision logic can and does.
    """

    def test_live_members_come_from_the_job_not_from_a_name_match(self):
        api = _FakeJobApi(pids=(11, 12))
        containment = WindowsJobContainment(handle=1234, api=api)
        self.assertEqual((11, 12), containment.live_members())

    def test_signal_all_terminates_the_whole_job(self):
        api = _FakeJobApi(pids=(11, 12))
        containment = WindowsJobContainment(handle=1234, api=api)
        containment.signal_all(hard=False)
        self.assertTrue(api.terminated)
        self.assertEqual((), containment.live_members())

    def test_close_releases_the_handle_so_kill_on_close_fires(self):
        api = _FakeJobApi()
        containment = WindowsJobContainment(handle=1234, api=api)
        containment.close()
        self.assertTrue(api.closed)

    def test_cancel_over_a_job_leaves_no_members(self):
        api = _FakeJobApi(pids=(11,))
        containment = WindowsJobContainment(handle=1234, api=api)
        managed, _handle, _calls = _managed_with(containment)
        result = managed.cancel(5.0)
        self.assertEqual((), result.survivors)
        self.assertTrue(api.closed)

    def test_job_pid_list_buffer_parses_exactly(self):
        # JOBOBJECT_BASIC_PROCESS_ID_LIST: ULONG_PTR count-assigned,
        # ULONG_PTR count-returned, then count-returned ULONG_PTR pids.
        payload = (3).to_bytes(8, "little") + (2).to_bytes(8, "little")
        payload += (11).to_bytes(8, "little") + (12).to_bytes(8, "little")
        payload += (0).to_bytes(8, "little")  # unused slot must be ignored
        self.assertEqual((11, 12), _parse_job_pid_list(payload, pointer_size=8))

    def test_job_pid_list_buffer_truncated_is_ambiguous(self):
        payload = (3).to_bytes(8, "little") + (3).to_bytes(8, "little")
        payload += (11).to_bytes(8, "little")
        with self.assertRaises(EvidenceError) as ctx:
            _parse_job_pid_list(payload, pointer_size=8)
        self.assertEqual("E_UNITY_PROCESS_UNKNOWN", ctx.exception.code)


class NonReapingWaitTests(unittest.TestCase):
    def test_a_pid_that_is_not_our_child_never_reads_as_a_clean_exit(self):
        """waitid raises ChildProcessError for a pid we did not spawn.

        Returning 0 there would manufacture 'exited cleanly' out of 'I have no
        idea', which is the receipt lie this plan exists to prevent. None means
        'no exit observed', and the caller cancels and re-checks.
        """
        self.assertIsNone(process_module._posix_peek_exit(
            _impossible_pid(), 0.0, clock=lambda: 0.0, sleeper=lambda _s: None,
        ))

    def test_wait_does_not_reap_so_the_pgid_stays_pinned(self):
        """The pid-reuse guarantee, checked rather than asserted in prose."""
        if not sys.platform.startswith("linux"):
            self.skipTest("linux-only /proc assertions")
        with TemporaryDirectory() as tmp:
            work = Path(tmp)
            managed = ManagedProcess.start(
                [sys.executable, "-c", "pass"],
                cwd=REPO, env=dict(os.environ),
                stdout_path=work / "o.log", stderr_path=work / "e.log",
            )
            self.assertEqual(0, managed.wait(15.0))
            # Still present as a zombie: the pid number cannot be reused,
            # and the pid IS the pgid we are about to signal.
            state = (Path(f"/proc/{managed.pid}/stat").read_bytes()
                     .rsplit(b")", 1)[1].split()[0])
            self.assertEqual(b"Z", state)
            managed.cancel(5.0)
            self.assertFalse(Path(f"/proc/{managed.pid}").exists()
                             and _pid_alive(managed.pid))


class PidLivenessTests(unittest.TestCase):
    def test_own_pid_is_live(self):
        self.assertIs(True, default_pid_is_live(os.getpid()))

    def test_a_definitely_absent_pid_is_not_live(self):
        # Driven through the real os.kill(pid, 0) seam. A pid above the
        # host's pid_max cannot exist, so this cannot race pid reuse.
        self.assertIs(False, default_pid_is_live(_impossible_pid()))

    def test_an_unknowable_pid_reports_none(self):
        def _weird(_pid, _sig):
            raise OSError(999, "unknowable")

        self.assertIsNone(default_pid_is_live(1, killer=_weird))


if __name__ == "__main__":
    unittest.main()
