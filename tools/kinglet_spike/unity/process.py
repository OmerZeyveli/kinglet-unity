"""process.py -- Native process-tree containment for Unity execution probes.

The problem, measured rather than assumed
-----------------------------------------
On this host, a real `Unity -batchmode -runTests` invocation exited CLEANLY
(code 0) and left two `dotnet exec .../DotNetSdkRoslyn/VBCSCompiler.dll`
processes alive with **PPID = 1**, while no `Editor/Unity` process remained at
all. One of them outlived the run by more than ten minutes; a later run added
another. Plan 00U's global constraint -- "cancellation, timeout, crash, and
success must leave no Unity, MCP helper, or child process and no live lease
owned by that route" -- is therefore violated by a plain batchmode invocation,
on the SUCCESS path, before anything goes wrong.

Two obvious strategies are ruled out by that measurement:

1. **"After Unity exits, kill Unity's children."** There are none. Unity's
   children are reparented to init the moment Unity exits, so a tree walked
   after the fact is empty and reports success while the leak stands. The tree
   must be captured or contained BEFORE the run, not reconstructed afterwards.

2. **"Kill any VBCSCompiler."** The Roslyn compiler server is shared and
   pipe-named (`-pipename:...`); the instance you find may belong to another
   run, or to the user's own GUI Editor, whose work you would destroy. Nothing
   in this module matches a process by name, path or command line -- see
   `test_a_shared_compiler_server_in_another_group_is_never_touched`.

The mechanism
-------------
POSIX: launch with `start_new_session=True`. That calls `setsid()` in the child
between fork and exec, making the child a session leader AND a process-group
leader with `pgid == pid`. Process-group membership is inherited by every
descendant and, crucially, **survives reparenting**: an orphan whose PPID has
become 1 still carries the original pgid, so `killpg(pgid, ...)` reaches it.
That was verified directly against the fixture tree (see
`test_group_membership_survives_reparenting_to_init`) -- it is the single
property that makes cleanup possible at all.

Windows: process groups do not work this way, so containment is a Job Object
created with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` and every launched process
assigned to it. Job membership is likewise inherited and survives reparenting.
See `_WindowsJobApi` for what is and is not verified there.

Identity, and why there is nothing to guess
-------------------------------------------
Task 3 burned four review rounds deriving process facts from lossy strings.
This module never parses a command line. The kernel itself maintains group/job
membership, and it is the kernel that matches on signal delivery, so `killpg`
cannot hit an unrelated process by accident -- provided the pgid still means
what we think it means. It does, for one specific reason: `pgid == leader pid`,
and a pid cannot be recycled while its process is an **unreaped zombie**. So
this module deliberately does not reap the leader until after the group is
empty (`_reap_leader` runs last in `cancel`, pinned by
`test_leader_is_reaped_only_after_the_group_is_empty`), and `ManagedProcess.
wait()` peeks at the exit status with `os.waitid(..., WNOWAIT)` -- which
reports the exit code WITHOUT consuming the zombie -- instead of `Popen.wait`,
which would reap it and free the number.

The direction of every ambiguous case
-------------------------------------
The asymmetry here is not the one ownership.py faced. Failing to kill leaks a
process: bad, and detectable. Killing the wrong process destroys unrelated
work: worse, and silent. So:

* **Cleanup never depends on enumeration.** `signal_all` names only the group
  or job, which the kernel resolves exactly. It is safe even when we cannot
  see a single pid.
* **Enumeration produces EVIDENCE, and refuses to guess.** `descendants()`
  raises `E_UNITY_PROCESS_UNKNOWN` when the process table cannot be read or a
  row cannot be parsed. It never returns `()` for "I could not look" -- that is
  precisely the shape of Task 3's central defect, where the unresolvable case
  fell through to the permissive answer by construction. An empty tuple from
  this module always means "proven empty".
* A `cancel()` that cannot prove the group is empty still signals it, then
  raises rather than reporting a clean receipt.
"""
from __future__ import annotations

import os
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence

from ..model import EvidenceError

# How long a hard SIGKILL / TerminateJobObject is given to take effect after
# the caller's own soft deadline has already elapsed. Not a caller knob:
# `cancel(deadline_seconds)` is the budget for the polite phase, and this is
# the fixed, small allowance the kernel needs to finish an impolite one.
HARD_GRACE_SECONDS: float = 5.0

# Poll interval while waiting for a group to drain. Small enough that a fast
# exit is not padded by a whole tick, large enough not to spin a core.
POLL_INTERVAL_SECONDS: float = 0.02


@dataclass(frozen=True)
class ProcessSnapshot:
    """One row of the process table: a pid and the group it belongs to.

    Deliberately carries NO command line. Nothing in this module decides
    anything from a process's name or arguments.
    """

    pid: int
    pgid: int


@dataclass(frozen=True)
class CleanupResult:
    signalled: bool
    escalated: bool
    survivors: tuple[int, ...]
    exit_code: int | None


def assert_clean(result: CleanupResult) -> None:
    """Raise E_UNITY_PROCESS_LEAK unless cleanup proved zero survivors.

    Separate from `cancel()` on purpose: a caller assembling a receipt needs
    the survivor pids to record (the contract's `descendant_pids` field), and
    an exception carrying them in its message only is harder to use than a
    value. The receipt rule -- clean on every outcome -- is enforced here.
    """
    if result.survivors:
        listed = ", ".join(str(pid) for pid in result.survivors)
        raise EvidenceError(
            "E_UNITY_PROCESS_LEAK",
            f"{len(result.survivors)} process(es) survived cleanup: {listed}",
        )


# ---------------------------------------------------------------------------
# Exact process-table sources. Numbers only -- nothing lossy to re-split.
# ---------------------------------------------------------------------------

def _parse_proc_stat_fields(raw: bytes) -> tuple[str, int]:
    """State (field 3) and pgrp (field 5) of a Linux /proc/<pid>/stat record.

    Field 2 is the executable's comm wrapped in parentheses and it may contain
    spaces AND parentheses -- `(weird ) name)` is a legal value. Splitting the
    line on whitespace, or on the FIRST ')', shifts every later field and
    yields a plausible-looking but wrong pgid, which would silently exclude a
    real survivor from the group. The documented way to read this file is to
    scan to the LAST ')' and parse from there, which is what this does.

    The state is read for one specific reason, found by running this against a
    real tree rather than by reasoning about it: the leader we deliberately
    leave UNREAPED (see the module docstring on pid pinning) is a zombie, and a
    zombie is still listed in /proc and still carries its pgid. Counting it as
    a group member made `cancel()` report its own leader as a survivor and
    spin out the whole grace period every single time. A zombie is not a
    running process -- it holds no memory, no files and no Unity project -- so
    it is excluded here, at the source, where every consumer gets it right.
    """
    end = raw.rfind(b")")
    if end == -1:
        raise EvidenceError(
            "E_UNITY_PROCESS_UNKNOWN",
            "/proc stat record has no closing paren; cannot locate pgrp",
        )
    fields = raw[end + 1:].split()
    # After comm: state(3) ppid(4) pgrp(5) -> indices 0, 1, 2 here.
    if len(fields) < 3:
        raise EvidenceError(
            "E_UNITY_PROCESS_UNKNOWN",
            "/proc stat record ends before the pgrp field",
        )
    try:
        state = fields[0].decode("ascii")
    except UnicodeDecodeError as error:
        raise EvidenceError(
            "E_UNITY_PROCESS_UNKNOWN", f"/proc stat state is not ascii: {error}"
        ) from error
    try:
        return state, int(fields[2])
    except ValueError as error:
        raise EvidenceError(
            "E_UNITY_PROCESS_UNKNOWN", f"/proc stat pgrp is not an integer: {error}"
        ) from error


def _parse_proc_stat_pgid(raw: bytes) -> int:
    return _parse_proc_stat_fields(raw)[1]


def _linux_pgid_table() -> tuple[ProcessSnapshot, ...] | None:
    """Every readable pid and its pgid, from /proc -- the exact Linux source.

    Returns None (never an empty tuple) when /proc itself cannot be listed, so
    the caller can tell "couldn't look" from "nothing running" and fall back to
    `ps`. A per-pid read that fails because the process has already exited is
    skipped: a process that is gone is not a survivor. Any OTHER per-pid error
    is raised, because silently dropping a pid we were not allowed to read is
    exactly how a live survivor becomes invisible.
    """
    try:
        names = os.listdir("/proc")
    except OSError:
        return None
    rows: list[ProcessSnapshot] = []
    for name in names:
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            raw = Path(f"/proc/{pid}/stat").read_bytes()
        except (FileNotFoundError, ProcessLookupError):
            continue  # exited between listdir and read
        except OSError as error:
            raise EvidenceError(
                "E_UNITY_PROCESS_UNKNOWN",
                f"cannot read /proc/{pid}/stat: {error}",
            ) from error
        state, pgid = _parse_proc_stat_fields(raw)
        if state == "Z":
            continue  # exited, awaiting reaping -- not a running process
        rows.append(ProcessSnapshot(pid=pid, pgid=pgid))
    return tuple(rows)


def _parse_ps_pgid_table(stdout: str) -> tuple[ProcessSnapshot, ...]:
    """Parse `ps -Ao pid=,pgid=,stat=` output into exact snapshots.

    ownership.py had to stop parsing `ps` because a command LINE is a lossy,
    space-joined rendering of argv that cannot be re-split. That objection does
    not apply here: both columns are integers, so there is no string to
    recover and no ambiguity to resolve. Fail closed anyway -- an unparseable
    row raises rather than being skipped, because the row skipped could be the
    survivor being hunted, and empty output means the reader is broken (this
    process is always in the table), not that the machine is idle.
    """
    rows: list[ProcessSnapshot] = []
    for line in stdout.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        parts = stripped.split()
        if len(parts) != 3 or not all(part.lstrip("-").isdigit() for part in parts[:2]):
            raise EvidenceError(
                "E_UNITY_PROCESS_UNKNOWN",
                f"unparseable ps row, refusing to skip it: {line!r}",
            )
        if parts[2].startswith("Z"):
            continue  # zombie -- see _parse_proc_stat_fields
        rows.append(ProcessSnapshot(pid=int(parts[0]), pgid=int(parts[1])))
    if not rows:
        raise EvidenceError(
            "E_UNITY_PROCESS_UNKNOWN",
            "ps returned no process rows; the reader, not the machine, is wrong",
        )
    return tuple(rows)


def _ps_pgid_table() -> tuple[ProcessSnapshot, ...]:
    try:
        result = subprocess.run(
            ["ps", "-Ao", "pid=,pgid=,stat="],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except OSError as error:
        raise EvidenceError(
            "E_UNITY_PROCESS_UNKNOWN", f"cannot execute ps: {error}"
        ) from error
    if result.returncode != 0:
        raise EvidenceError(
            "E_UNITY_PROCESS_UNKNOWN",
            f"ps exited {result.returncode}: {result.stderr.strip()!r}",
        )
    return _parse_ps_pgid_table(result.stdout)


def default_group_table() -> tuple[ProcessSnapshot, ...]:
    """The real process table: /proc where it exists, `ps` otherwise (macOS)."""
    if sys.platform.startswith("linux"):
        table = _linux_pgid_table()
        if table is not None:
            return table
    return _ps_pgid_table()


def default_pid_is_live(pid: int, *, killer: Callable[[int, int], None] = os.kill):
    """True / False / None -- and None genuinely means "could not tell".

    Shared with lease.py, which must never steal a lease from a process it
    could not prove dead. `killer` is injectable so the unknowable branch is
    reachable from a test rather than asserted as source text.
    """
    try:
        killer(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # exists, owned by someone else
    except OSError:
        return None
    return True


# ---------------------------------------------------------------------------
# Containment strategies
# ---------------------------------------------------------------------------

class PosixGroupContainment:
    """Containment by process group. The group is the identity."""

    def __init__(
        self,
        pgid: int,
        *,
        group_table_provider: Callable[[], Sequence[ProcessSnapshot]] = default_group_table,
        signaller: Callable[[int, int], None] = os.killpg,
    ) -> None:
        self.pgid = pgid
        self._table = group_table_provider
        self._signaller = signaller

    def live_members(self) -> tuple[int, ...]:
        return tuple(row.pid for row in self._table() if row.pgid == self.pgid)

    def signal_all(self, hard: bool) -> None:
        sig = signal.SIGKILL if hard else signal.SIGTERM
        try:
            self._signaller(self.pgid, sig)
        except ProcessLookupError:
            return  # the whole group is already gone; that is success
        except PermissionError as error:
            # We are not allowed to signal a group we created. Never treat
            # that as "cleaned up" -- it is the leak case, loudly.
            raise EvidenceError(
                "E_UNITY_PROCESS_UNKNOWN",
                f"not permitted to signal process group {self.pgid}: {error}",
            ) from error
        except OSError as error:
            raise EvidenceError(
                "E_UNITY_PROCESS_UNKNOWN",
                f"cannot signal process group {self.pgid}: {error}",
            ) from error

    def close(self) -> None:
        return None


def _parse_job_pid_list(buffer: bytes, *, pointer_size: int) -> tuple[int, ...]:
    """Pure decoder for JOBOBJECT_BASIC_PROCESS_ID_LIST.

    Layout: NumberOfAssignedProcesses (ULONG_PTR), NumberOfProcessIdsInList
    (ULONG_PTR), then that many ULONG_PTR pids. Extracted from the ctypes call
    for the same reason ownership.py extracted `_parse_procargs2`: the decode
    is where a mistake hides, and it must be testable from a host that has no
    Win32 at all. A buffer that does not actually contain the pids it claims is
    ambiguity, not an empty job.
    """
    header = 2 * pointer_size
    if len(buffer) < header:
        raise EvidenceError(
            "E_UNITY_PROCESS_UNKNOWN", "job pid-list buffer is shorter than its header"
        )
    returned = int.from_bytes(buffer[pointer_size:header], "little")
    end = header + returned * pointer_size
    if len(buffer) < end:
        raise EvidenceError(
            "E_UNITY_PROCESS_UNKNOWN",
            f"job pid-list claims {returned} pids but the buffer holds fewer",
        )
    return tuple(
        int.from_bytes(buffer[offset:offset + pointer_size], "little")
        for offset in range(header, end, pointer_size)
    )


class WindowsJobContainment:
    """Containment by Job Object, for the user's Windows host.

    Windows has no POSIX process groups, and `CREATE_NEW_PROCESS_GROUP` only
    scopes console control events -- it is not a kill scope. A Job Object with
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE is the real equivalent: membership is
    inherited by descendants, survives reparenting, and closing the last handle
    kills whatever remains even if this process itself dies unexpectedly.

    The Win32 calls live behind `api` so every decision below runs on Linux.
    What Linux CANNOT verify, and what therefore needs one manual pass on the
    Windows host, is recorded in `_default_windows_job_api`.
    """

    def __init__(self, *, handle, api) -> None:
        self._handle = handle
        self._api = api

    def live_members(self) -> tuple[int, ...]:
        return tuple(self._api.list_pids(self._handle))

    def signal_all(self, hard: bool) -> None:
        # A job has no polite signal. TerminateJobObject is the only primitive
        # that reaches every member, so soft and hard are the same call; the
        # soft/hard distinction is preserved in CleanupResult for the receipt.
        self._api.terminate(self._handle)

    def close(self) -> None:
        self._api.close(self._handle)


def _default_windows_job_api():  # pragma: no cover - requires Win32
    """Real Job Object calls.

    NOT exercised on this Linux host. Two things need one manual pass on the
    Windows box before any Windows cell may be claimed:

    * that `AssignProcessToJobObject` succeeds against a Unity process (it
      fails if the process is already in a job that forbids nesting -- some CI
      agents and Windows Terminal do this), and
    * the assignment race: `subprocess.Popen` gives no suspended-start handle,
      so a grandchild spawned in the microseconds between CreateProcess and
      AssignProcessToJobObject escapes the job. Unity takes seconds to reach
      the point where it spawns a compiler server, so this is believed
      harmless in practice, but "believed" is not "measured".
    """
    import ctypes
    from ctypes import wintypes

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    JobObjectExtendedLimitInformation = 9
    JobObjectBasicProcessIdList = 3
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000

    class _JOBOBJECT_BASIC_LIMIT_INFORMATION(ctypes.Structure):
        _fields_ = [
            ("PerProcessUserTimeLimit", ctypes.c_int64),
            ("PerJobUserTimeLimit", ctypes.c_int64),
            ("LimitFlags", wintypes.DWORD),
            ("MinimumWorkingSetSize", ctypes.c_size_t),
            ("MaximumWorkingSetSize", ctypes.c_size_t),
            ("ActiveProcessLimit", wintypes.DWORD),
            ("Affinity", ctypes.POINTER(ctypes.c_ulong)),
            ("PriorityClass", wintypes.DWORD),
            ("SchedulingClass", wintypes.DWORD),
        ]

    class _IO_COUNTERS(ctypes.Structure):
        _fields_ = [(name, ctypes.c_uint64) for name in (
            "ReadOperationCount", "WriteOperationCount", "OtherOperationCount",
            "ReadTransferCount", "WriteTransferCount", "OtherTransferCount",
        )]

    class _JOBOBJECT_EXTENDED_LIMIT_INFORMATION(ctypes.Structure):
        _fields_ = [
            ("BasicLimitInformation", _JOBOBJECT_BASIC_LIMIT_INFORMATION),
            ("IoInfo", _IO_COUNTERS),
            ("ProcessMemoryLimit", ctypes.c_size_t),
            ("JobMemoryLimit", ctypes.c_size_t),
            ("PeakProcessMemoryUsed", ctypes.c_size_t),
            ("PeakJobMemoryUsed", ctypes.c_size_t),
        ]

    class _Api:
        def create_job(self):
            handle = kernel32.CreateJobObjectW(None, None)
            if not handle:
                raise EvidenceError(
                    "E_UNITY_PROCESS_UNSAFE",
                    f"CreateJobObjectW failed: {ctypes.get_last_error()}",
                )
            info = _JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
            info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            if not kernel32.SetInformationJobObject(
                handle, JobObjectExtendedLimitInformation,
                ctypes.byref(info), ctypes.sizeof(info),
            ):
                raise EvidenceError(
                    "E_UNITY_PROCESS_UNSAFE",
                    f"SetInformationJobObject failed: {ctypes.get_last_error()}",
                )
            return handle

        def assign(self, handle, pid):
            PROCESS_SET_QUOTA, PROCESS_TERMINATE = 0x0100, 0x0001
            proc = kernel32.OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, False, pid)
            if not proc:
                raise EvidenceError(
                    "E_UNITY_PROCESS_UNSAFE",
                    f"OpenProcess({pid}) failed: {ctypes.get_last_error()}",
                )
            try:
                if not kernel32.AssignProcessToJobObject(handle, proc):
                    raise EvidenceError(
                        "E_UNITY_PROCESS_UNSAFE",
                        f"AssignProcessToJobObject failed: {ctypes.get_last_error()}",
                    )
            finally:
                kernel32.CloseHandle(proc)

        def list_pids(self, handle):
            size = 2 * ctypes.sizeof(ctypes.c_size_t) + 1024 * ctypes.sizeof(ctypes.c_size_t)
            buffer = ctypes.create_string_buffer(size)
            if not kernel32.QueryInformationJobObject(
                handle, JobObjectBasicProcessIdList, buffer, size, None
            ):
                raise EvidenceError(
                    "E_UNITY_PROCESS_UNKNOWN",
                    f"QueryInformationJobObject failed: {ctypes.get_last_error()}",
                )
            return _parse_job_pid_list(
                buffer.raw, pointer_size=ctypes.sizeof(ctypes.c_size_t)
            )

        def terminate(self, handle):
            kernel32.TerminateJobObject(handle, 1)

        def close(self, handle):
            kernel32.CloseHandle(handle)

    return _Api()


# ---------------------------------------------------------------------------
# Launch-time containment checks
# ---------------------------------------------------------------------------

def _verify_containment_pgid(*, pgid: int, pid: int) -> None:
    """Refuse to manage a process whose containment was not actually established.

    Three ways `start_new_session=True` could leave us holding a group we must
    not signal, each fatal in a different way:

    * `pgid <= 0` -- `killpg(0, ...)` signals the CALLER's group and
      `killpg(-1, ...)` is broadcast-to-everything. Both are catastrophic.
    * `pgid == our own group` -- setsid did not take effect; cleanup would
      terminate this controller and, on a developer machine, its whole shell.
    * `pgid != pid` -- the child is not the group leader, so the group predates
      our launch and contains processes we did not create and may not kill.
    """
    if pgid <= 0:
        raise EvidenceError(
            "E_UNITY_PROCESS_UNSAFE",
            f"refusing to manage a non-positive process group ({pgid}): "
            "signalling it would reach this process or every process",
        )
    if pgid == os.getpgrp():
        raise EvidenceError(
            "E_UNITY_PROCESS_UNSAFE",
            f"launched process shares this controller's process group ({pgid}); "
            "session isolation did not take effect, so cleanup would be suicide",
        )
    if pgid != pid:
        raise EvidenceError(
            "E_UNITY_PROCESS_UNSAFE",
            f"launched process {pid} is not the leader of group {pgid}; "
            "the group contains processes this run did not create",
        )


def _read_pgid(pid: int) -> int:
    """The child's pgid from the OS, falling back to the setsid invariant.

    Prefer the kernel's answer. If the child exited before we could ask, the
    `setsid()` guarantee still holds -- it runs in the child before exec, so
    `pgid == pid` unconditionally -- and `_verify_containment_pgid` re-checks
    the result either way, so the fallback cannot widen what we will signal.
    """
    try:
        return os.getpgid(pid)
    except (ProcessLookupError, PermissionError, OSError):
        return pid


def _exit_code_from_waitid(info) -> int:
    if info.si_code == os.CLD_EXITED:
        return info.si_status
    return -info.si_status


def _posix_peek_exit(
    pid: int,
    timeout_seconds: float,
    *,
    clock: Callable[[], float],
    sleeper: Callable[[float], None],
) -> int | None:
    """Exit code of `pid`, or None if still running -- WITHOUT reaping it.

    `Popen.wait()` reaps, which frees the pid, which is the same number as our
    pgid. Between that and cleanup, the kernel could hand the number to an
    unrelated process and `killpg` would hit a stranger. `WNOWAIT` leaves the
    zombie in place, so the number stays pinned to us until `cancel()` reaps it
    on purpose, after the group is already empty.
    """
    deadline = clock() + timeout_seconds
    while True:
        try:
            info = os.waitid(os.P_PID, pid, os.WEXITED | os.WNOWAIT | os.WNOHANG)
        except ChildProcessError:
            return None  # not our child, or already reaped elsewhere
        if info is not None:
            return _exit_code_from_waitid(info)
        if clock() >= deadline:
            return None
        sleeper(POLL_INTERVAL_SECONDS)


class ManagedProcess:
    """A launched process plus proof of what its containment did or did not leave."""

    def __init__(
        self,
        *,
        handle,
        pgid: int,
        containment,
        clock: Callable[[], float] = None,
        sleeper: Callable[[float], None] = None,
        waiter: Callable[[float], "int | None"] = None,
    ) -> None:
        self.handle = handle
        self.pgid = pgid
        self._containment = containment
        self._clock = clock or time.monotonic
        self._sleeper = sleeper or time.sleep
        self._waiter = waiter
        self._result: CleanupResult | None = None
        self._closers: list[Callable[[], None]] = []

    @property
    def pid(self) -> int:
        return self.handle.pid

    # -- launch -----------------------------------------------------------

    @classmethod
    def start(
        cls,
        argv: Sequence[str],
        *,
        cwd,
        env,
        stdout_path,
        stderr_path,
        spawner: Callable[..., object] = None,
        containment_factory: Callable[..., object] = None,
        clock: Callable[[], float] = None,
        sleeper: Callable[[float], None] = None,
    ) -> "ManagedProcess":
        """Launch `argv` inside a fresh containment, with output on real files.

        stdout/stderr go to files, never to pipes. A Unity batchmode log runs
        to megabytes; a pipe whose reader is busy waiting for the process to
        exit fills its buffer and both sides block forever. Files cannot
        deadlock, and they are also the artifact the receipt wants anyway.
        """
        stdout_path = Path(stdout_path)
        stderr_path = Path(stderr_path)
        stdout_path.parent.mkdir(parents=True, exist_ok=True)
        stderr_path.parent.mkdir(parents=True, exist_ok=True)
        out = open(stdout_path, "wb")
        err = open(stderr_path, "wb")

        windows = os.name == "nt"
        job = None
        api = None
        try:
            if windows and containment_factory is None:  # pragma: no cover - Win32
                api = _default_windows_job_api()
                job = api.create_job()

            spawn = spawner or subprocess.Popen
            kwargs = dict(
                cwd=str(cwd),
                env=dict(env),
                stdin=subprocess.DEVNULL,
                stdout=out,
                stderr=err,
            )
            if not windows:
                kwargs["start_new_session"] = True
            handle = spawn(list(argv), **kwargs)
        except BaseException:
            out.close()
            err.close()
            if job is not None and api is not None:  # pragma: no cover - Win32
                api.close(job)
            raise

        try:
            if containment_factory is not None:
                containment = containment_factory(handle)
                pgid = getattr(containment, "pgid", handle.pid)
            elif windows:  # pragma: no cover - Win32
                api.assign(job, handle.pid)
                containment = WindowsJobContainment(handle=job, api=api)
                pgid = handle.pid
            else:
                pgid = _read_pgid(handle.pid)
                _verify_containment_pgid(pgid=pgid, pid=handle.pid)
                containment = PosixGroupContainment(pgid)
        except BaseException:
            # Containment could not be established -- do not leave the process
            # running unmanaged. Kill what we can reach directly and re-raise.
            try:
                handle.kill()
            except Exception:
                pass
            out.close()
            err.close()
            raise

        managed = cls(
            handle=handle, pgid=pgid, containment=containment,
            clock=clock, sleeper=sleeper,
        )
        managed._closers.extend((out.close, err.close))
        return managed

    # -- observation ------------------------------------------------------

    def group_members(self) -> tuple[int, ...]:
        """Every live pid the containment holds, including the leader."""
        return tuple(self._containment.live_members())

    def descendants(self) -> tuple[int, ...]:
        """Live contained pids other than the process we launched.

        Raises E_UNITY_PROCESS_UNKNOWN when the table cannot be read. An empty
        tuple from this method always means "proven empty".
        """
        return tuple(pid for pid in self.group_members() if pid != self.pid)

    def wait(self, timeout_seconds: float) -> int | None:
        """Exit code, or None if still running after `timeout_seconds`.

        Does not reap on POSIX -- see `_posix_peek_exit` for why that matters.
        """
        if self._waiter is not None:
            return self._waiter(timeout_seconds)
        if hasattr(os, "waitid") and os.name != "nt":
            return _posix_peek_exit(
                self.handle.pid, timeout_seconds,
                clock=self._clock, sleeper=self._sleeper,
            )
        try:  # pragma: no cover - Windows path
            return self.handle.wait(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            return None

    # -- cleanup ----------------------------------------------------------

    def _live_or_none(self) -> tuple[int, ...] | None:
        """Live members, or None meaning "could not tell" -- never a false ()."""
        try:
            return self.group_members()
        except EvidenceError:
            return None

    def _drain(self, deadline_seconds: float) -> tuple[int, ...] | None:
        end = self._clock() + deadline_seconds
        while self._clock() < end:
            live = self._live_or_none()
            if live == ():
                return ()
            self._sleeper(POLL_INTERVAL_SECONDS)
        return self._live_or_none()

    def cancel(self, deadline_seconds: float) -> CleanupResult:
        """Terminate the whole containment, then prove nothing survived.

        Idempotent: a second call returns the first call's result rather than
        signalling a group whose pid may since have been recycled.
        """
        if self._result is not None:
            return self._result

        signalled = False
        escalated = False

        live = self._live_or_none()
        if live != ():
            self._containment.signal_all(hard=False)
            signalled = True
            live = self._drain(deadline_seconds)

        if live != ():
            self._containment.signal_all(hard=True)
            signalled = True
            escalated = True
            live = self._drain(HARD_GRACE_SECONDS)

        try:
            self._containment.close()
        finally:
            for close in self._closers:
                try:
                    close()
                except Exception:  # pragma: no cover - defensive
                    pass
            self._closers.clear()

        if live is None:
            # Signalled, but unable to prove the outcome. Refuse to mint a
            # clean-looking result out of an unreadable process table.
            raise EvidenceError(
                "E_UNITY_PROCESS_UNKNOWN",
                f"process group {self.pgid} was signalled but its members "
                "could not be enumerated; cleanliness is unproven",
            )

        # Reap LAST: until now the leader's zombie is what pins the pid, and
        # the pid is the pgid we have been signalling.
        exit_code = self._reap_leader()
        self._result = CleanupResult(
            signalled=signalled, escalated=escalated,
            survivors=tuple(live), exit_code=exit_code,
        )
        return self._result

    def _reap_leader(self) -> int | None:
        code = self.handle.poll()
        if code is None:
            code = self.handle.wait()
        return code

    # -- context manager --------------------------------------------------

    def __enter__(self) -> "ManagedProcess":
        return self

    def __exit__(self, exc_type, exc, tb) -> bool:
        result = self.cancel(HARD_GRACE_SECONDS)
        if exc_type is None:
            # Only assert cleanliness when nothing else is already failing --
            # raising here would otherwise mask the caller's real exception.
            assert_clean(result)
        return False
