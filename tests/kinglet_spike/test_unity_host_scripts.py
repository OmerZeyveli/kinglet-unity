"""Task 8 -- the native host entry point and the observations -> evidence layer.

Two things are under test here and they are tested differently.

`spikes/platform/unity/run-host.sh` is tested by RUNNING IT. Every case below
is a refusal, and each one is arranged so that the act it forbids cannot happen
even if the guard is deleted: the `--unity` path handed in is never an
executable Unity, and `--repo-root` points at a directory with no pinned
fixture, so a script that reached its Python body would die there rather than
launch an Editor. A refusal test that could perform the act it forbids is not a
test, it is a loaded gun.

`tools/kinglet_spike/unity/results.py` and the pure helpers in
`host_probes.py` are tested directly, because they are where a dishonest
document would have to get through. The probes that launch Unity are NOT
exercised here -- they need a real Editor, and a stubbed Unity would prove only
that the stub behaves.
"""
from __future__ import annotations

import json
import os
import subprocess
import unittest
from pathlib import Path

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.unity import host_probes
from tools.kinglet_spike.unity.results import (
    OBSERVATIONS_SCHEMA,
    PROBES,
    to_evidence_records,
    validate_unity_observations,
)

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "spikes/platform/unity/run-host.sh"


def run_script(arguments, *, env=None, cwd=None):
    environment = dict(os.environ)
    environment.pop("WSL_DISTRO_NAME", None)
    environment.pop("WSLENV", None)
    if env:
        environment.update(env)
    return subprocess.run(
        ["bash", str(SCRIPT), *arguments],
        capture_output=True,
        text=True,
        cwd=str(cwd or REPO),
        env=environment,
        timeout=120,
    )


def observation_document(**overrides):
    document = {
        "schema": OBSERVATIONS_SCHEMA,
        "unity_version": "6000.3.18f1",
        "unity_revision": "5ebeb53e4c07",
        "environment": {
            "os": "linux",
            "release": "ubuntu-24.04.4-lts",
            "arch": "x64",
            "native": True,
            "toolchain": ["host=Pop!_OS 24.04 LTS", "kernel=7.0.11"],
        },
        "probes": [
            {
                "id": "filesystem-only",
                "unobserved": False,
                "command": ["python3", "-m", "tools.kinglet_spike.unity", "filesystem"],
                "assertions": [
                    {"id": "receipt-valid", "status": "pass", "detail": "ok"},
                ],
                "artifact_paths": [],
            },
        ],
    }
    document.update(overrides)
    return document


class RunHostScriptSafety(unittest.TestCase):
    """The script exists, is bash, and refuses before it can do harm."""

    def test_the_script_exists_and_parses_as_bash(self):
        self.assertTrue(SCRIPT.is_file(), "run-host.sh is missing")
        parsed = subprocess.run(
            ["bash", "-n", str(SCRIPT)], capture_output=True, text=True
        )
        self.assertEqual(parsed.returncode, 0, parsed.stderr)

    def test_an_explicit_unity_path_is_required(self):
        result = run_script([])
        self.assertEqual(result.returncode, 2)
        self.assertIn("--unity is required", result.stderr)
        self.assertIn("never searches", result.stderr)

    def test_unity_without_an_operand_reports_instead_of_shifting_into_set_u(self):
        # `shift 2` on a one-element argv fails under `set -u` BEFORE any error
        # message can print, and the operator gets a silent exit 1. The message
        # is the assertion.
        result = run_script(["--unity"])
        self.assertEqual(result.returncode, 2)
        self.assertIn("--unity requires a path", result.stderr)

    def test_run_id_without_an_operand_reports_too(self):
        result = run_script(["--unity", "/nonexistent/Unity", "--run-id"])
        self.assertEqual(result.returncode, 2)
        self.assertIn("--run-id requires a value", result.stderr)

    def test_an_unknown_argument_is_refused(self):
        result = run_script(["--unity", "/nonexistent/Unity", "--yolo"])
        self.assertEqual(result.returncode, 2)
        self.assertIn("unknown argument", result.stderr)

    def test_a_non_executable_editor_is_refused(self):
        result = run_script(["--unity", str(REPO / "README.md")])
        self.assertEqual(result.returncode, 2)
        self.assertIn("not an executable Unity Editor", result.stderr)

    def test_wsl_is_refused_by_environment(self):
        # --repo-root is a directory with no pinned fixture, so a build of this
        # script with the WSL guard deleted still refuses one line later and
        # still creates nothing. Killing the mutant is not worth a test that
        # can start a run.
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            result = run_script(
                ["--unity", "/bin/true", "--repo-root", temporary],
                env={"WSL_DISTRO_NAME": "Ubuntu"},
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn("WSL", result.stderr)

    def test_wslenv_alone_is_also_refused(self):
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            result = run_script(
                ["--unity", "/bin/true", "--repo-root", temporary],
                env={"WSLENV": "PATH/l"},
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn("WSL", result.stderr)

    def test_a_repo_root_without_the_pinned_fixture_is_refused(self):
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            result = run_script(
                ["--unity", "/bin/true", "--repo-root", temporary]
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("pinned fixture missing", result.stderr)

    def test_an_existing_raw_run_directory_is_refused(self):
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "spikes/platform/unity/fixture").mkdir(parents=True)
            existing = root / ".kinglet/local/spikes/reused"
            existing.mkdir(parents=True)
            result = run_script(
                ["--unity", "/bin/true", "--repo-root", str(root),
                 "--run-id", "reused"]
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("already exists", result.stderr)

    # --- FINAL whole-branch review, IMPORTANT 6 (second half): RUN_ID was
    #     unvalidated, and it is concatenated into RAW_ROOT, which becomes the
    #     SWEEP'S WORKSPACE ARGUMENT.

    def test_a_traversing_run_id_is_refused_before_it_reaches_the_sweep(self):
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "spikes/platform/unity/fixture").mkdir(parents=True)
            for bad in ("../../..", "a/b", ".", "..", ".hidden", "a b", "a$(id)"):
                result = run_script(
                    ["--unity", "/bin/true", "--repo-root", str(root),
                     "--run-id", bad]
                )
                self.assertEqual(result.returncode, 2, bad)
                self.assertIn("--run-id", result.stderr, bad)
            # And the guard must not have become a refuse-everything rule.
            self.assertFalse(
                (root / ".kinglet").exists(),
                "a refused run must create no raw root at all",
            )

    def test_an_ordinary_run_id_is_still_accepted(self):
        # Otherwise "refuses everything" would look like a working guard. This
        # gets PAST the run-id check and dies at the next one.
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "spikes/platform/unity/fixture").mkdir(parents=True)
            existing = root / ".kinglet/local/spikes/2026-07-28T00_00_00Z-host"
            existing.mkdir(parents=True)
            result = run_script(
                ["--unity", "/bin/true", "--repo-root", str(root),
                 "--run-id", "2026-07-28T00_00_00Z-host"]
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("already exists", result.stderr)

    def _run_with_stub_sweep(self, sweep_body):
        """Drive the REAL cleanup trap with a sweep that cannot kill anything.

        `run-host.sh` resolves its sweep from its own directory, so a copy of
        the script beside a stub `sweep-workspace.sh` exercises the trap end
        to end while the stub does nothing but exit. That is deliberate: the
        subject here is what the trap does with the sweep's EXIT STATUS, and a
        test of that must not be able to signal a process.

        The real repository root is used because a temporary one has no
        `tools/kinglet_spike`, so the run would die at import and never create
        the workspace the trap keys on.
        """
        import shutil
        import tempfile

        run_id = f"t8-sweepstatus-{os.getpid()}-{abs(hash(sweep_body)) % 10000}"
        raw_root = REPO / ".kinglet/local/spikes" / run_id
        if raw_root.exists():
            shutil.rmtree(raw_root)
        temporary = tempfile.mkdtemp()
        try:
            stub_dir = Path(temporary)
            shutil.copy2(SCRIPT, stub_dir / "run-host.sh")
            (stub_dir / "sweep-workspace.sh").write_text(
                sweep_body, encoding="utf-8"
            )
            return subprocess.run(
                ["bash", str(stub_dir / "run-host.sh"),
                 "--unity", "/bin/true", "--repo-root", str(REPO),
                 "--run-id", run_id],
                capture_output=True, text=True, timeout=300,
                cwd=str(REPO),
            )
        finally:
            shutil.rmtree(temporary, ignore_errors=True)
            if raw_root.exists():
                shutil.rmtree(raw_root)

    def test_the_cleanup_trap_does_not_discard_the_sweeps_refusal(self):
        # The refusal used to be thrown away by `|| true`: the sweep exited 2
        # -- an unusable workspace, or a process table it could not read --
        # and the operator saw nothing at all while the host may still have
        # been running Unity from this run.
        result = self._run_with_stub_sweep(
            '#!/usr/bin/env bash\necho "stub: refusing" >&2\nexit 2\n'
        )
        self.assertIn("THE SWEEP REFUSED", result.stderr)
        self.assertNotEqual(0, result.returncode)

    def test_a_sweep_that_succeeds_reports_no_refusal(self):
        # The pair that makes the assertion above mean something: a guard that
        # always shouted would satisfy it.
        result = self._run_with_stub_sweep("#!/usr/bin/env bash\nexit 0\n")
        self.assertNotIn("THE SWEEP REFUSED", result.stderr)

    def test_the_trap_actually_sweeps_when_the_run_fails(self):
        """End to end: a FAILING run must still sweep its workspace.

        This replaces an `assertIn("sweep-workspace.sh", text)` that a COMMENT
        satisfied -- mutating only the trap's invocation line left the comment
        naming the script, and the assertion passed over a script that swept
        nothing. Prose cannot satisfy this one: a real process has to die.

        The run is arranged to fail immediately: `--unity /bin/true` reports no
        version, so `host_probes.run()` creates the raw workspace and then
        refuses at `verify_project_editor` before anything launches. That is the
        interesting case, because the trap exists precisely for runs that never
        reach their own cleanup.

        It uses the REAL repository root -- a temporary one has no
        `tools/kinglet_spike` package, so the run would die at import and never
        create the workspace this is asserting about. Nothing starts Unity, and
        the raw directory is removed in the finally.
        """
        import shutil
        import signal
        import tempfile
        import time

        run_id = f"t8-trapcase-{os.getpid()}"
        raw_root = REPO / ".kinglet/local/spikes" / run_id
        if raw_root.exists():
            shutil.rmtree(raw_root)
        try:
            root = REPO
            workspace = raw_root / "workspace"

            # Named for the workspace the run is about to create. The directory
            # does not exist yet and does not need to: the sweep matches argv.
            victim = subprocess.Popen(
                ["bash", "-c", f'exec -a "Unity -projectPath {workspace}" sleep 300'],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            try:
                time.sleep(1)
                self.assertIsNone(victim.poll(), "the victim died before the run")

                result = run_script(
                    ["--unity", "/bin/true", "--repo-root", str(root),
                     "--run-id", run_id]
                )
                self.assertNotEqual(result.returncode, 0,
                                    "the run was supposed to fail")
                self.assertTrue(workspace.is_dir(),
                                "the workspace was never created, so this "
                                "proves nothing about the trap")
                victim.wait(timeout=30)
                self.assertIsNotNone(
                    victim.poll(),
                    "the cleanup trap did not sweep the run's workspace",
                )
            finally:
                try:
                    os.killpg(os.getpgid(victim.pid), signal.SIGKILL)
                except (ProcessLookupError, PermissionError, OSError):
                    pass
                try:
                    victim.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    pass
        finally:
            if raw_root.exists():
                shutil.rmtree(raw_root)

    def test_the_script_never_evaluates_the_editor_path(self):
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn("eval ", text)
        self.assertIn('python3 -m tools.kinglet_spike.unity.host_probes "$REPO_ROOT" "$UNITY"', text)


class SweepBehaviour(unittest.TestCase):
    """The sweep is tested by KILLING REAL PROCESSES, not by reading the script.

    The previous version of this asserted `assertIn("AssetImportWorker", text)`
    against the whole script, which a COMMENT satisfies -- and did: mutating
    only the two comment lines took `grep -c AssetImportWorker` to zero while
    every executable line stood, and the assertion still passed. Nothing here
    can be satisfied by prose.

    The three processes below are the three cases that matter, and each is a
    different kind of failure if it goes wrong:

      workspace victim   -- the Editor and its AssetImportWorkers, whose argv
                            carries -projectPath. Must die.
      owned-pgid victim  -- VBCSCompiler and UnityPackageManager, which carry
                            NO project path at all and are therefore invisible
                            to a workspace sweep. Must die, and only the pgid
                            record can reach them.
      bystander          -- a process merely NAMED like an orphan class, in no
                            workspace and no owned group: the operator's own
                            Editor on another project. Must LIVE. The old
                            host-wide `grep -F UnityShaderCompiler` killed it.
    """

    SWEEP = REPO / "spikes/platform/unity/sweep-workspace.sh"

    def setUp(self):
        import tempfile

        self._temporary = tempfile.TemporaryDirectory()
        self.workspace = Path(self._temporary.name) / "workspace"
        self.workspace.mkdir()
        self.pgid_file = Path(self._temporary.name) / "owned-pgids.txt"
        self.spawned = []

    def tearDown(self):
        import signal

        for handle in self.spawned:
            try:
                os.killpg(os.getpgid(handle.pid), signal.SIGKILL)
            except (ProcessLookupError, PermissionError, OSError):
                pass
            try:
                handle.wait(timeout=10)
            except subprocess.TimeoutExpired:
                pass
        self._temporary.cleanup()

    def _spawn(self, command):
        handle = subprocess.Popen(
            ["bash", "-c", command],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,       # child is a session leader: pgid == pid
        )
        self.spawned.append(handle)
        return handle

    @staticmethod
    def _alive(handle) -> bool:
        return handle.poll() is None

    # ---- NEW 1: the argument guard, driven DIRECTLY ---------------------
    #
    # `--check` runs the guard and exits before the process table is even
    # listed. These cases are driven through it deliberately: the act this
    # guard forbids is selecting PID 1, and a test that had to launch a real
    # sweep to prove the refusal would be a test that can perform it.

    def _check(self, *arguments):
        return subprocess.run(
            ["bash", str(self.SWEEP), "--check", *arguments],
            capture_output=True, text=True, timeout=60,
        )

    def test_the_sweep_requires_a_workspace(self):
        result = subprocess.run(
            ["bash", str(self.SWEEP)], capture_output=True, text=True, timeout=60
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("workspace directory is required", result.stderr)

    def test_the_filesystem_root_is_refused(self):
        # MEASURED against the previous version: a kill-neutered copy run as
        # `sweep-workspace.sh /` selected 237 processes including PID 1.
        result = self._check("/")
        self.assertEqual(result.returncode, 2)
        self.assertIn("filesystem root", result.stderr)

    def test_a_relative_path_is_refused(self):
        result = self._check(".")
        self.assertEqual(result.returncode, 2)
        self.assertIn("absolute path", result.stderr)

    def test_a_path_with_dotdot_is_refused(self):
        result = self._check("/tmp/../")
        self.assertEqual(result.returncode, 2)
        self.assertIn("'..'", result.stderr)

    def test_a_shallow_path_is_refused(self):
        for shallow in ("/home", "/usr", "/tmp"):
            if not Path(shallow).is_dir():
                continue
            result = self._check(shallow)
            self.assertEqual(result.returncode, 2, shallow)
            self.assertIn("too shallow", result.stderr)

    def test_the_home_directory_is_refused(self):
        home = os.environ.get("HOME")
        if not home or not Path(home).is_dir():
            self.skipTest("no HOME on this host")
        result = self._check(home)
        # Refused either as too shallow or as being the home directory; both
        # are refusals, and which one fires is not the point.
        self.assertEqual(result.returncode, 2)

    def test_a_directory_containing_the_repository_is_refused(self):
        """The refusal is the assertion; which guard fires depends on the checkout path.

        sweep-workspace.sh refuses for two reasons, checked in order: the path is too
        shallow to be a run directory (fewer than 3 components), or it contains this
        repository. Which one fires for REPO.parent therefore depends on how deep the
        checkout happens to sit.

        This test used to assert "repository" outright. In the main checkout
        (/home/riive/Documents/Github/kinglet-unity) that holds. In a git worktree under
        /tmp it does not — depth 2 trips the shallow guard first — so the test failed
        deterministically in every worktree while passing standalone, and read as a flake.

        That mattered more than a wrong assertion usually does: this repository's own
        review process verifies guards by reintroducing a defect in a scratch worktree and
        watching the suite fail. A test that always fails there trains the reader to skim
        past failures in exactly the run where they are the signal.

        So: assert the refusal, and assert the reason is one the script documents.
        """
        for target in (str(REPO), str(REPO.parent)):
            with self.subTest(target=target):
                result = self._check(target)
                self.assertEqual(result.returncode, 2)
                self.assertTrue(
                    "repository" in result.stderr or "too shallow" in result.stderr,
                    f"refused for an undocumented reason: {result.stderr!r}",
                )

    def test_a_nonexistent_directory_is_refused(self):
        result = self._check("/nonexistent/deep/workspace")
        self.assertEqual(result.returncode, 2)
        self.assertIn("not an existing directory", result.stderr)

    def test_a_path_containing_a_newline_is_refused(self):
        """MEASURED: `/tmp/<LF>zz` was ACCEPTED by the previous guard.

        `DEPTH="$(printf … | awk …)"` emitted one line per record, so a
        two-line path produced a two-line "number", `[ "2|0" -lt 3 ]` failed
        with "integer expression expected", and because that sits inside an
        `if` condition `set -e` never saw it. Execution fell through and the
        depth rule was skipped entirely -- ambiguity resolving to sweeping.

        Driven through `--check`, which exits before `ps` is ever called.
        """
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            weird = Path(temporary) / "a\nb"
            weird.mkdir()
            result = self._check(str(weird))
            self.assertEqual(result.returncode, 2)
            self.assertIn("newline", result.stderr)

    def test_a_path_containing_a_tab_or_carriage_return_is_refused(self):
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            for name in ("a\tb", "a\rb"):
                weird = Path(temporary) / name
                weird.mkdir()
                result = self._check(str(weird))
                self.assertEqual(result.returncode, 2, name)
                self.assertIn("newline", result.stderr)

    def test_a_workspace_with_spaces_is_still_accepted(self):
        # The newline rule must not become a refuse-everything rule. Spelling
        # the control characters with `$(printf ...)` did exactly that --
        # command substitution strips trailing newlines, so the pattern
        # collapsed to `*""*` and matched every path, including this one.
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            spaced = Path(temporary) / "with space" / "ws"
            spaced.mkdir(parents=True)
            result = self._check(str(spaced))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("ok ", result.stdout)

    def test_a_trailing_slash_is_still_accepted(self):
        result = self._check(str(self.workspace) + "/")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_real_run_directory_is_accepted(self):
        # Otherwise "refuses everything" would look like a working guard.
        result = self._check(str(self.workspace))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ok ", result.stdout)

    def test_the_guard_is_wired_into_the_real_sweep_not_only_check(self):
        # A full invocation, no --check. The path is refused for a reason that
        # is harmless even if the guard were deleted: nothing on the host can
        # have /nonexistent/deep/workspace in its argv.
        result = subprocess.run(
            ["bash", str(self.SWEEP), "/nonexistent/deep/workspace"],
            capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("not an existing directory", result.stderr)

    # ---- the sweep's authority model, against real processes -------------

    def test_it_kills_only_what_it_owns(self):
        """Six real processes; two must die and four must live.

        Each survivor is a defect that was actually demonstrated:

          sibling         `<ws>2/proj` swept as `<ws>/proj` by a match with
                          no RIGHT boundary -- the `/x/proj` vs `/x/proj2` case.
          mirror          `/mnt/backup<ws>/proj` swept because the match had
                          no LEFT boundary -- the same class, reflected.
          recycled pgid   an unrelated daemon whose pgid happened to be in the
                          owned file was killed on bare pgid equality.
          bystander       a process merely NAMED like an orphan class, killed
                          by the original host-wide name match.
        """
        import time

        victim_argv = f"Unity -projectPath {self.workspace}/proj"
        workspace_victim = self._spawn(f'exec -a "{victim_argv}" sleep 300')

        # Sibling directory whose name merely STARTS with the workspace name.
        sibling_argv = f"Unity -projectPath {self.workspace}2/proj"
        sibling = self._spawn(f'exec -a "{sibling_argv}" sleep 300')

        # A path that merely ENDS WITH the workspace path -- the mirror of the
        # sibling case. Reachable via a bind mount, a container or chroot
        # mirror (/mnt/host<abs>), or a backup tree. Right-side anchoring alone
        # selected and killed this one.
        mirror_argv = f"Unity -projectPath /mnt/backup{self.workspace}/proj"
        mirror = self._spawn(f'exec -a "{mirror_argv}" sleep 300')

        # No workspace path anywhere in its argv -- exactly like VBCSCompiler.
        owned_victim = self._spawn("exec -a VBCSCompiler sleep 300")
        # Same owned group, but nothing about it says Unity: a recycled PGID.
        recycled = self._spawn("exec -a innocent-daemon sleep 300")
        self.pgid_file.write_text(
            f"{owned_victim.pid}\n{recycled.pid}\n", encoding="utf-8"
        )

        # Named like an orphan class, in no workspace and no owned group.
        bystander = self._spawn("exec -a UnityShaderCompiler sleep 300")

        time.sleep(1)
        for handle in (workspace_victim, sibling, mirror, owned_victim,
                       recycled, bystander):
            self.assertTrue(self._alive(handle), "a process died before the sweep")

        result = subprocess.run(
            ["bash", str(self.SWEEP), str(self.workspace), str(self.pgid_file)],
            capture_output=True, text=True, timeout=120,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

        workspace_victim.wait(timeout=30)
        owned_victim.wait(timeout=30)
        self.assertFalse(self._alive(workspace_victim), "workspace process survived")
        self.assertFalse(self._alive(owned_victim),
                         "a process reachable ONLY by owned pgid survived")
        self.assertTrue(self._alive(sibling),
                        "the sweep killed a SIBLING directory's process; the "
                        "workspace match is unanchored on the right")
        self.assertTrue(self._alive(mirror),
                        "the sweep killed a process whose path merely ENDS "
                        "WITH the workspace; the match has no left boundary")
        self.assertTrue(self._alive(recycled),
                        "the sweep killed an unrelated process on bare pgid "
                        "equality; a recycled PGID must resolve to sparing")
        self.assertTrue(self._alive(bystander),
                        "the sweep killed a process it does not own")

        self.assertIn("workspace", result.stdout)
        self.assertIn("owned-pgid", result.stdout)
        for spared in (sibling, mirror, recycled, bystander):
            self.assertNotIn(str(spared.pid), result.stdout)

    def test_a_backslash_in_the_workspace_does_not_silently_disarm_the_sweep(self):
        """FINAL whole-branch review, IMPORTANT 6.

        `awk -v ws="$WS"` runs ESCAPE PROCESSING over the value. VERIFIED on
        this host: `-v ws='/tmp/a\\t1/ws'` yields length 11, not 12. A
        backslash is a legal filename character and the argument guard does
        not refuse it, so the selector was comparing against a DIFFERENT
        string than the one that was validated: it matched nothing, the sweep
        found no targets, and it exited 0 -- reporting a clean host over a
        live Editor.

        This is the whole defect, so it is asserted by KILLING: a victim
        naming a backslash workspace must die. Against the `-v` spelling it
        survives and the sweep still exits 0, which is the silent failure.

        Nothing in THIS process's own command line names the workspace, so the
        test runner cannot select itself -- that has happened on this plan.
        """
        import time

        backslash_ws = Path(self._temporary.name) / "ws\\x"
        backslash_ws.mkdir()

        victim_argv = f"Unity -projectPath {backslash_ws}/proj"
        victim = self._spawn(f'exec -a "{victim_argv}" sleep 300')
        # The same anchoring rules must still hold for a backslash path.
        sibling_argv = f"Unity -projectPath {backslash_ws}2/proj"
        sibling = self._spawn(f'exec -a "{sibling_argv}" sleep 300')

        time.sleep(1)
        self.assertTrue(self._alive(victim))
        self.assertTrue(self._alive(sibling))

        result = subprocess.run(
            ["bash", str(self.SWEEP), str(backslash_ws)],
            capture_output=True, text=True, timeout=120,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        victim.wait(timeout=30)
        self.assertFalse(
            self._alive(victim),
            "the sweep reported success without selecting a process in its own "
            "workspace; the workspace string was mangled before the comparison",
        )
        self.assertTrue(self._alive(sibling), "anchoring must still hold")

    def test_without_a_pgid_file_the_owned_class_is_out_of_reach(self):
        # States the reason the pgid record exists at all: a workspace-only
        # sweep provably cannot see VBCSCompiler or UnityPackageManager.
        owned_victim = self._spawn("exec -a UnityPackageManager sleep 300")
        import time

        time.sleep(1)
        result = subprocess.run(
            ["bash", str(self.SWEEP), str(self.workspace)],
            capture_output=True, text=True, timeout=120,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self._alive(owned_victim))
        self.assertEqual(result.stdout.strip(), "")


class ObservationValidation(unittest.TestCase):
    """A document cannot claim more than its own assertions support."""

    def test_a_valid_document_round_trips(self):
        observations = validate_unity_observations(observation_document())
        self.assertEqual(observations.unity_version, "6000.3.18f1")
        self.assertEqual(observations.probes[0].id, "filesystem-only")

    def test_an_unknown_root_field_is_refused(self):
        document = observation_document()
        document["extra"] = 1
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_FIELD")

    def test_a_probe_id_outside_the_frozen_matrix_is_refused(self):
        document = observation_document()
        document["probes"][0]["id"] = "filesystem"      # the ROUTE name, not the cell
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_COVERAGE")

    def test_every_frozen_probe_id_is_accepted(self):
        for probe_id in PROBES:
            document = observation_document()
            document["probes"][0]["id"] = probe_id
            validate_unity_observations(document)

    def test_a_duplicate_probe_is_refused(self):
        document = observation_document()
        document["probes"].append(dict(document["probes"][0]))
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_COVERAGE")

    def test_an_observed_probe_must_assert_something(self):
        document = observation_document()
        document["probes"][0]["assertions"] = []
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_ASSERTION")

    def test_an_unobserved_probe_must_carry_a_reason(self):
        document = observation_document(probes=[
            {"id": "live-editor-mcp", "unobserved": True},
        ])
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_FIELD")
        self.assertIn("why it is open", caught.exception.detail)

    def test_an_unobserved_probe_may_not_also_assert(self):
        document = observation_document(probes=[
            {
                "id": "live-editor-mcp",
                "unobserved": True,
                "reason": "blocked",
                "assertions": [{"id": "x", "status": "pass", "detail": "d"}],
            },
        ])
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_ASSERTION")

    def test_an_observed_probe_may_not_carry_a_reason(self):
        document = observation_document()
        document["probes"][0]["reason"] = "sneaking an excuse into a pass"
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_FIELD")

    def test_an_empty_toolchain_is_refused(self):
        document = observation_document()
        document["environment"]["toolchain"] = []
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_FIELD")
        self.assertIn("real host", caught.exception.detail)

    def test_a_half_recorded_span_is_refused(self):
        document = observation_document()
        document["probes"][0]["started_at"] = "2026-07-28T13:28:00Z"
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_TIME")

    def test_a_span_that_ends_before_it_starts_is_refused(self):
        document = observation_document()
        document["probes"][0]["started_at"] = "2026-07-28T13:29:00Z"
        document["probes"][0]["ended_at"] = "2026-07-28T13:28:00Z"
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_TIME")

    def test_an_assertion_status_outside_pass_fail_is_refused(self):
        document = observation_document()
        document["probes"][0]["assertions"][0]["status"] = "inconclusive"
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_ENUM")


class RecordConversion(unittest.TestCase):
    """The record's status is derived, never declared."""

    def test_a_probe_whose_assertions_all_pass_becomes_a_pass_record(self):
        records = to_evidence_records(
            validate_unity_observations(observation_document()),
            now="2026-07-28T00:00:00Z",
        )
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0].status, "pass")

    def test_one_failing_assertion_drops_the_record_off_pass(self):
        document = observation_document()
        document["probes"][0]["assertions"].append(
            {"id": "tests-pass", "status": "fail", "detail": "status=not-run"}
        )
        records = to_evidence_records(
            validate_unity_observations(document), now="2026-07-28T00:00:00Z"
        )
        self.assertEqual(records[0].status, "fail")

    def test_an_unobserved_probe_becomes_inconclusive_carrying_its_reason(self):
        document = observation_document(probes=[
            {"id": "live-editor-mcp", "unobserved": True, "reason": "bridge never registered"},
        ])
        records = to_evidence_records(
            validate_unity_observations(document), now="2026-07-28T00:00:00Z"
        )
        self.assertEqual(records[0].status, "inconclusive")
        self.assertEqual(records[0].assertions[0].status, "fail")
        self.assertIn("bridge never registered", records[0].assertions[0].detail)

    def test_the_record_targets_the_matrix_subject_not_the_project_id(self):
        # This is the whole reason results.py exists: coverage matches on
        # subject.id, and every unity cell carries "execution".
        records = to_evidence_records(
            validate_unity_observations(observation_document()),
            now="2026-07-28T00:00:00Z",
        )
        self.assertEqual(records[0].subject.kind, "unity")
        self.assertEqual(records[0].subject.id, "execution")
        self.assertEqual(records[0].probe.id, "filesystem-only")

    def test_the_subject_version_carries_the_exact_version_and_revision(self):
        records = to_evidence_records(
            validate_unity_observations(observation_document()),
            now="2026-07-28T00:00:00Z",
        )
        self.assertEqual(records[0].subject.version, "6000.3.18f1 (5ebeb53e4c07)")

    def test_every_record_carries_subject_provenance_sources(self):
        records = to_evidence_records(
            validate_unity_observations(observation_document()),
            now="2026-07-28T00:00:00Z",
        )
        self.assertTrue(records[0].sources)
        self.assertTrue(all(source.url.startswith("https://") for source in records[0].sources))

    def test_a_recorded_span_survives_into_the_record(self):
        document = observation_document()
        document["probes"][0]["started_at"] = "2026-07-28T13:28:00Z"
        document["probes"][0]["ended_at"] = "2026-07-28T13:28:22Z"
        records = to_evidence_records(
            validate_unity_observations(document), now="2026-07-28T14:00:00Z"
        )
        self.assertEqual(records[0].started_at, "2026-07-28T13:28:00Z")
        self.assertEqual(records[0].ended_at, "2026-07-28T13:28:22Z")

    def test_a_probe_with_no_span_falls_back_to_one_instant(self):
        records = to_evidence_records(
            validate_unity_observations(observation_document()),
            now="2026-07-28T14:00:00Z",
        )
        self.assertEqual(records[0].started_at, records[0].ended_at)

    def test_run_ids_are_qualified_by_probe_and_environment(self):
        document = observation_document()
        document["probes"].append({
            "id": "same-project-headless",
            "unobserved": False,
            "command": ["unity"],
            "assertions": [{"id": "a", "status": "pass", "detail": "d"}],
            "artifact_paths": [],
        })
        records = to_evidence_records(
            validate_unity_observations(document), now="2026-07-28T00:00:00Z"
        )
        identifiers = {record.run_id for record in records}
        self.assertEqual(len(identifiers), 2)
        for record in records:
            self.assertIn(record.probe.id, record.run_id)
            self.assertIn("linux", record.run_id)
            self.assertIn("x64", record.run_id)


class HostCensusHelpers(unittest.TestCase):
    """The measured traps, encoded as tests."""

    def test_a_shell_quoting_every_class_name_is_filtered_before_the_census(self):
        # MEASURED on this host: a leftover
        # `bash -c '... pgrep -af "Editor/Unity|VBCSCompiler|..." ...'`
        # reported one survivor of EACH class when the true answer was zero.
        shell_row = (
            "923560 4158 923560 /bin/bash -c pgrep -af "
            "Editor/Unity|VBCSCompiler|UnityPackageManager|AssetImportWorker"
        )
        real_row = (
            "1020229 1 1018591 dotnet exec "
            "/opt/Unity/Editor/Data/DotNetSdkRoslyn/VBCSCompiler.dll -pipename:x"
        )
        # The raw census cannot tell them apart -- that is the whole point of
        # filtering first.
        self.assertEqual(host_probes.orphan_census((shell_row,))["VBCSCompiler"], 1)

        kept = host_probes.filter_process_rows([shell_row, real_row])
        self.assertEqual(kept, (real_row,))
        census = host_probes.orphan_census(kept)
        self.assertEqual(census["VBCSCompiler"], 1)
        self.assertEqual(census["EditorUnity"], 0)

    def test_filtering_keeps_a_real_editor_row(self):
        editor_row = (
            "1000166 1 1000166 /opt/Unity/Hub/Editor/6000.3.18f1/Editor/Unity "
            "-projectPath /w -logFile /w.log"
        )
        kept = host_probes.filter_process_rows([editor_row])
        self.assertEqual(kept, (editor_row,))
        self.assertEqual(host_probes.orphan_census(kept)["EditorUnity"], 1)

    def test_process_rows_filters_by_argv0_not_by_the_whole_line(self):
        self.assertIn("bash", host_probes.NON_UNITY_ARGV0)
        self.assertIn("pgrep", host_probes.NON_UNITY_ARGV0)
        self.assertIn("python3", host_probes.NON_UNITY_ARGV0)

    def test_the_asset_import_worker_class_is_matched_on_its_name_flag(self):
        # Its argv0 is a bare `Unity`, so "Editor/Unity" provably misses it.
        classes = dict(host_probes.ORPHAN_CLASSES)
        self.assertEqual(classes["AssetImportWorker"], "-name AssetImportWorker")
        row = (
            "1001855 1 1001855 Unity -adb2 -batchMode -noUpm "
            "-name AssetImportWorker0 -projectPath /w -logFile Logs/a.log"
        )
        census = host_probes.orphan_census((row,))
        self.assertEqual(census["AssetImportWorker"], 1)
        self.assertEqual(census["EditorUnity"], 0)

    def test_the_package_manager_server_carries_no_project_path(self):
        # Which is why the census is host-wide: a scope filter reports zero for
        # exactly the classes that leak.
        row = (
            "1016780 1016768 1016768 /opt/Unity/Editor/Data/Resources/"
            "PackageManager/Server/UnityPackageManager server -s 1016768 "
            "--ipc-path /tmp/Unity-Upm-1016768.sock -l 2"
        )
        self.assertNotIn("-projectPath", row)
        self.assertEqual(host_probes.orphan_census((row,))["UnityPackageManager"], 1)

    def test_the_log_version_reader_returns_the_pair_unity_itself_printed(self):
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / "editor.log"
            log.write_text(
                "Unity Editor version:    6000.3.18f1 (5ebeb53e4c07)\n"
                "Branch: 6000.3/staging\n",
                encoding="utf-8",
            )
            self.assertEqual(
                host_probes._log_version(log), ("6000.3.18f1", "5ebeb53e4c07")
            )

    def test_the_log_version_reader_reports_nothing_when_it_cannot_read(self):
        self.assertEqual(host_probes._log_version(Path("/nonexistent.log")), ("", ""))

    def test_the_revision_reader_rejects_a_non_hex_url_component(self):
        # MEASURED: `/download_unity/open-jdk/...` sits in the same position as
        # the revision, and reading it produced two "revisions" for one install.
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            editor_dir = root / "6000.3.18f1" / "Editor"
            editor_dir.mkdir(parents=True)
            editor = editor_dir / "Unity"
            editor.write_text("", encoding="utf-8")
            (root / "6000.3.18f1" / "modules.json").write_text(json.dumps([
                {"url": "https://d.unity3d.com/download_unity/5ebeb53e4c07/a.pkg"},
                {"url": "https://d.unity3d.com/download_unity/open-jdk/b.zip"},
            ]), encoding="utf-8")
            self.assertEqual(
                host_probes._editor_revision(editor, "6000.3.18f1"), "5ebeb53e4c07"
            )

    def test_the_revision_reader_refuses_rather_than_guessing(self):
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            editor_dir = Path(temporary) / "6000.3.18f1" / "Editor"
            editor_dir.mkdir(parents=True)
            editor = editor_dir / "Unity"
            editor.write_text("", encoding="utf-8")
            with self.assertRaises(EvidenceError) as caught:
                host_probes._editor_revision(editor, "6000.3.18f1")
            self.assertEqual(caught.exception.code, "E_UNITY_VERSION")

    def test_the_environment_records_the_matrix_key_and_the_real_host(self):
        environment = host_probes.host_environment()
        self.assertIn(environment["os"], ("linux", "macos"))
        self.assertTrue(environment["native"])
        self.assertTrue(environment["toolchain"])
        self.assertTrue(any("host=" in item for item in environment["toolchain"]))

    def test_a_receipts_route_relative_artifact_names_resolve_to_published_paths(self):
        # A receipt names its artifacts route-relative
        # (`artifacts/unity/same-project-headless-summary.json`). Published, the
        # layout is `artifacts/unity/<run-id>/<name>`, and the collision cell
        # renames the file on the way in -- so the reference went nowhere.
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            staging = host_probes.Staging(Path(temporary), ("/nowhere",), "stamp")
            receipt = {
                "route": "same-project-headless",
                "artifacts": ["artifacts/unity/same-project-headless-summary.json"],
            }
            resolved = staging.resolve_receipt_artifacts(
                "RUN-01", receipt,
                {"same-project-headless-summary.json": "collision-refusal-summary.json"},
            )
            self.assertEqual(
                resolved["artifacts"],
                ["artifacts/unity/RUN-01/collision-refusal-summary.json"],
            )
            # The original is not mutated, and unmapped names keep their own.
            self.assertEqual(
                receipt["artifacts"],
                ["artifacts/unity/same-project-headless-summary.json"],
            )
            self.assertEqual(
                staging.resolve_receipt_artifacts("RUN-01", receipt, {})["artifacts"],
                ["artifacts/unity/RUN-01/same-project-headless-summary.json"],
            )

    def test_the_isolation_manifest_citation_is_republished_too(self):
        # `isolation_manifest` is an artifact citation as well as a field, and
        # it is the MANDATORY one. Leaving it route-relative publishes an
        # isolated-headless receipt whose proof points at a path that exists
        # nowhere under the record -- the dangling reference this rewrite
        # exists to prevent, on the one field where it matters most.
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            staging = host_probes.Staging(Path(temporary), ("/nowhere",), "stamp")
            receipt = {
                "route": "isolated-headless",
                "artifacts": [
                    "artifacts/unity/isolated-headless-summary.json",
                    "artifacts/unity/isolated-headless-manifest.json",
                ],
                "isolation_manifest": "artifacts/unity/isolated-headless-manifest.json",
            }
            resolved = staging.resolve_receipt_artifacts("RUN-07", receipt, {})
            self.assertEqual(
                "artifacts/unity/RUN-07/isolated-headless-manifest.json",
                resolved["isolation_manifest"],
            )
            # And it still names something the artifact list carries, which is
            # what validate_unity_receipt requires of it.
            self.assertIn(resolved["isolation_manifest"], resolved["artifacts"])
            self.assertEqual(
                "artifacts/unity/isolated-headless-manifest.json",
                receipt["isolation_manifest"],
            )

    def test_the_publish_root_is_where_a_citation_resolves(self):
        # The root `verify_cited_isolation_manifest` is handed: joining a
        # published artifact path onto it must reach the staged file.
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            staging = host_probes.Staging(Path(temporary), ("/nowhere",), "stamp")
            staging.write_json("isolated-headless", "RUN-07", "probe.json", {"a": 1},
                               Path(temporary) / "raw")
            published = staging.for_probe("isolated-headless")[0]["path"]
            self.assertTrue(
                (staging.publish_root("isolated-headless") / published).is_file()
            )

    def test_the_recording_factory_writes_the_group_it_created(self):
        # This record is the ONLY thing that lets the outer trap reach
        # VBCSCompiler and UnityPackageManager without a host-wide name match.
        import tempfile

        class _Fake:
            pgid = 4242

        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "owned-pgids.txt"
            host_probes.record_owned_pgid(_Fake.pgid, path)
            host_probes.record_owned_pgid(99, path)
            self.assertEqual(path.read_text(encoding="utf-8"), "4242\n99\n")

    def test_recording_a_group_without_a_file_is_a_no_op_not_a_crash(self):
        host_probes.record_owned_pgid(1, None)

    def test_the_live_editor_mcp_reason_names_the_defect_not_the_run(self):
        reason = host_probes.LIVE_EDITOR_MCP_REASON
        self.assertIn("EditorPrefs", reason)
        self.assertIn("not worked around", reason)


class SweepDelegatesToTheOneAuthorityModel(unittest.TestCase):
    """FINAL whole-branch review, CRITICAL 1.

    `_sweep_project_processes` was the PRE-FIX sweep, preserved intact in the
    production probe runner:

        if str(project) in parts[3] or "UnityShaderCompiler" in parts[3]

    -- unanchored on both ends, plus a host-wide name match that `sweep-
    workspace.sh` states may never authorise a kill, ending in SIGKILL.

    These tests do not run a sweep. They drive the delegation through an
    injected runner and drive the script's own guard through `--check`, which
    validates and exits without listing or signalling anything. A refusal test
    that could signal a process is not a test.
    """

    class _Runner:
        def __init__(self, returncode=0, stdout="", stderr=""):
            self.returncode = returncode
            self.stdout = stdout
            self.stderr = stderr
            self.calls = []

        def __call__(self, argv, **kwargs):
            self.calls.append((list(argv), kwargs))
            return subprocess.CompletedProcess(
                argv, self.returncode, self.stdout, self.stderr
            )

    def test_the_sweep_script_it_calls_actually_exists(self):
        self.assertTrue(
            host_probes.SWEEP_SCRIPT.is_file(),
            f"the shared authority model must be at {host_probes.SWEEP_SCRIPT}",
        )

    def test_it_calls_sweep_workspace_with_the_workspace_and_the_owned_pgids(self):
        runner = self._Runner(stdout="swept 4242 4242 owned-pgid\n")
        swept = host_probes._sweep_project_processes(
            Path("/ws/run/workspace/main"),
            Path("/ws/run/owned-pgids.txt"),
            runner=runner,
        )
        self.assertEqual(1, len(runner.calls))
        argv, _kwargs = runner.calls[0]
        self.assertEqual(
            [
                "bash",
                str(host_probes.SWEEP_SCRIPT),
                "/ws/run/workspace/main",
                "/ws/run/owned-pgids.txt",
            ],
            argv,
        )
        self.assertEqual(("swept 4242 4242 owned-pgid",), swept)

    def test_a_refusal_is_raised_not_reported_as_a_clean_host(self):
        runner = self._Runner(returncode=2, stderr="workspace is too shallow")
        with self.assertRaises(host_probes.SweepRefused) as caught:
            host_probes._sweep_project_processes(
                Path("/x"), None, runner=runner
            )
        self.assertIn("too shallow", str(caught.exception))

    def test_the_module_defines_no_second_selection_rule(self):
        # Checked against the COMPILED function, not the file text, so a
        # comment cannot satisfy it. The sweep must not read the process table
        # itself and must not signal: its only names are the delegation.
        names = set(host_probes._sweep_project_processes.__code__.co_names)
        self.assertIn("SWEEP_SCRIPT", names)
        for forbidden in ("process_rows", "kill", "killpg", "SIGKILL", "SIGTERM"):
            self.assertNotIn(
                forbidden,
                names,
                f"the sweep must not reference {forbidden}; selection and "
                "signalling belong to sweep-workspace.sh alone",
            )

    def test_the_scripts_own_guard_refuses_a_workspace_that_is_a_prefix_sibling(self):
        # The defect this replaces: workspace `<ws>/main` selected
        # `<ws>/main-backup`. Driven through the real script, `--check` only,
        # so nothing can be signalled: the sibling must not be equal to the
        # workspace after the script canonicalises it.
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "a" / "b" / "c"
            main = root / "main"
            sibling = root / "main-backup"
            main.mkdir(parents=True)
            sibling.mkdir(parents=True)
            result = subprocess.run(
                ["bash", str(host_probes.SWEEP_SCRIPT), "--check", str(main)],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(f"ok {os.path.realpath(main)}", result.stdout.strip())
            self.assertNotIn("main-backup", result.stdout)

    def test_the_scripts_own_guard_refuses_the_filesystem_root(self):
        result = subprocess.run(
            ["bash", str(host_probes.SWEEP_SCRIPT), "--check", "/"],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(2, result.returncode)


if __name__ == "__main__":
    unittest.main()
