import json
import os
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import patch

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.unity.ownership import (
    ProjectOwner,
    _parse_posix_process_table,
    _parse_windows_process_table,
    _posix_process_table,
    _tokenize_command_line,
    _unity_lockfile_present,
    _windows_process_table,
    assert_headless_safe,
    detect_gui_owner,
    find_owning_process,
    resolve_lock_owner,
)


def _unity_process(pid: int, project_path: str) -> tuple:
    editor = "/home/user/Unity/Hub/Editor/6000.3.18f1/Editor/Unity"
    return (pid, f"{editor} -projectPath {project_path} -logFile -")


class FindOwningProcessTests(unittest.TestCase):
    def test_matching_project_path_is_owned(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [_unity_process(4242, str(project))]
            owner = find_owning_process(table, project)
            self.assertIsNotNone(owner)
            self.assertTrue(owner.confirmed)
            self.assertEqual(4242, owner.pid)
            self.assertEqual("process", owner.source)

    def test_similarly_prefixed_sibling_path_does_not_match(self):
        # The whole point of canonicalized-path equality over substring
        # matching: "proj" must not match a process reporting "proj-other".
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            sibling = Path(tmp) / "proj-other"
            sibling.mkdir()
            table = [_unity_process(4242, str(sibling))]
            self.assertIsNone(find_owning_process(table, project))

    def test_symlink_alias_canonicalizes_to_owned_project(self):
        with TemporaryDirectory() as tmp:
            real_project = Path(tmp) / "real-proj"
            real_project.mkdir()
            alias = Path(tmp) / "alias-proj"
            os.symlink(real_project, alias, target_is_directory=True)

            # Process reports the symlink path; caller requests the real path.
            table = [_unity_process(9001, str(alias))]
            owner = find_owning_process(table, real_project)
            self.assertIsNotNone(owner)
            self.assertTrue(owner.confirmed)

            # And the reverse: process reports the real path, caller
            # requests through the symlink.
            table_reversed = [_unity_process(9002, str(real_project))]
            owner_reversed = find_owning_process(table_reversed, alias)
            self.assertIsNotNone(owner_reversed)
            self.assertTrue(owner_reversed.confirmed)

    def test_self_match_trap_ignores_non_unity_argv0(self):
        # Observed live on this host: a loose substring match on the
        # command line finds this very controller's own shell command
        # (which can legitimately contain the text "Editor/Unity"), or an
        # unrelated grep/ps invocation. Only an exact argv[0] basename of
        # "Unity"/"Unity.exe" counts as a candidate Editor.
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [
                (555, f"/bin/bash -c grep -af 'Editor/Unity' -projectPath {project}"),
                (556, f"python3 my_controller.py -projectPath {project}"),
            ]
            self.assertIsNone(find_owning_process(table, project))

    def test_orphaned_compiler_helper_is_not_an_owner(self):
        # Observed live: two `dotnet exec .../DotNetSdkRoslyn/VBCSCompiler.dll`
        # processes survived a clean Unity batchmode exit, reparented to
        # init (PPID=1). argv[0] basename is "dotnet", never "Unity" --
        # this must never be mistaken for a live Editor.
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [
                (
                    777,
                    "/usr/share/dotnet/dotnet exec "
                    "/home/user/.local/share/unity3d/DotNetSdkRoslyn/VBCSCompiler.dll "
                    f"-projectPath {project}",
                ),
            ]
            self.assertIsNone(find_owning_process(table, project))

    def test_process_with_no_projectpath_argument_is_ignored(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [(1, "/opt/Unity/Editor/Unity -batchmode -quit")]
            self.assertIsNone(find_owning_process(table, project))

    # --- CRITICAL 1 fix: a space in the project path must not defeat the match ---

    def test_space_in_project_path_still_matches(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "My Project"
            project.mkdir()
            table = [_unity_process(4242, str(project))]
            owner = find_owning_process(table, project)
            self.assertIsNotNone(owner)
            self.assertTrue(owner.confirmed)

    def test_space_in_project_path_distinguishes_a_true_sibling(self):
        # The rejoin must stop at the next project's own -projectPath, not
        # swallow it -- a live Editor on a DIFFERENT space-containing
        # sibling project must still not match.
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "My Project"
            project.mkdir()
            other = Path(tmp) / "My Project 2"
            other.mkdir()
            table = [_unity_process(4242, str(other))]
            self.assertIsNone(find_owning_process(table, project))

    def test_windows_quoted_space_in_project_path_matches(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "My Project"
            project.mkdir()
            command = (
                '"C:\\Program Files\\Unity\\Editor\\Unity.exe" '
                f'-projectPath "{project}" -logFile -'
            )
            owner = find_owning_process([(1, command)], project, windows=True)
            self.assertIsNotNone(owner)
            self.assertTrue(owner.confirmed)

    # --- IMPORTANT 2 fix: a discriminating test for the argv0 guard ---

    def test_argv0_containing_unity_but_not_equal_is_not_a_match(self):
        # UnityShaderCompiler and unityhub are real Unity-shipped binaries
        # whose path contains "Unity" but are not the Editor. Mutating
        # _is_unity_editor_argv0 to `"Unity" in token` must make this fail.
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [
                (10, f"/opt/Unity/Editor/Data/Tools/UnityShaderCompiler -projectPath {project}"),
                (11, f"/usr/bin/unityhub -projectPath {project}"),
            ]
            self.assertIsNone(find_owning_process(table, project))

    # --- IMPORTANT 3 fix: a discriminating test for path equality ---

    def test_prefix_without_separator_does_not_match(self):
        # "proj2" starts with "proj" as a bare string -- a startswith()
        # comparison (in either direction) would incorrectly match this.
        # Only whole-path equality may pass.
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            sibling = Path(tmp) / "proj2"
            sibling.mkdir()
            table = [_unity_process(4242, str(sibling))]
            self.assertIsNone(find_owning_process(table, project))


class ResolveLockOwnerTests(unittest.TestCase):
    def test_stale_lock_with_no_corroborating_process_is_unconfirmed(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            owner = resolve_lock_owner(
                (), project, lockfile_exists=True, instance_pid=None
            )
            self.assertIsNotNone(owner)
            self.assertFalse(owner.confirmed)
            self.assertEqual("lockfile", owner.source)

    def test_instance_pid_matching_live_unity_process_is_confirmed(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            # The pid is live and is a genuine Unity Editor process, but its
            # -projectPath could not be parsed directly (e.g. a truncated
            # ps line) -- EditorInstance.json's pid still corroborates it.
            table = [(1234, "/opt/Unity/Editor/Unity -batchmode")]
            owner = resolve_lock_owner(
                table, project, lockfile_exists=True, instance_pid=1234
            )
            self.assertIsNotNone(owner)
            self.assertTrue(owner.confirmed)
            self.assertEqual("lockfile+process", owner.source)

    def test_instance_pid_not_live_stays_unconfirmed(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [(9999, "/usr/share/dotnet/dotnet exec VBCSCompiler.dll")]
            owner = resolve_lock_owner(
                table, project, lockfile_exists=False, instance_pid=4242
            )
            self.assertIsNotNone(owner)
            self.assertFalse(owner.confirmed)

    def test_no_lock_artifacts_and_no_process_is_safe(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            owner = resolve_lock_owner(
                (), project, lockfile_exists=False, instance_pid=None
            )
            self.assertIsNone(owner)


class DetectGuiOwnerAndAssertHeadlessSafeTests(unittest.TestCase):
    def test_live_process_match_confirms_owner_and_refuses_headless(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [_unity_process(321, str(project))]

            owner = detect_gui_owner(project, process_table_provider=lambda: table)
            self.assertIsInstance(owner, ProjectOwner)
            self.assertTrue(owner.confirmed)

            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=lambda: table)
            self.assertEqual("E_UNITY_OWNED", ctx.exception.code)

    def test_stale_real_lockfile_refuses_headless_as_unknown(self):
        # Real temp lock files on disk, per the brief -- not just the pure
        # resolve_lock_owner() path.
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            (project / "Temp").mkdir(parents=True)
            (project / "Temp" / "UnityLockfile").write_text("", encoding="utf-8")

            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=lambda: ())
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_stale_real_editor_instance_json_refuses_headless_as_unknown(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            (project / "Library").mkdir(parents=True)
            instance = {
                "process_id": 5150,
                "version": "6000.3.18f1",
                "app_path": "/opt/Unity/Editor/Unity",
            }
            (project / "Library" / "EditorInstance.json").write_text(
                json.dumps(instance), encoding="utf-8"
            )

            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=lambda: ())
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_editor_instance_json_pid_alive_confirms_ownership(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            (project / "Library").mkdir(parents=True)
            instance = {"process_id": 6161, "version": "6000.3.18f1"}
            (project / "Library" / "EditorInstance.json").write_text(
                json.dumps(instance), encoding="utf-8"
            )
            table = [(6161, "/opt/Unity/Editor/Unity -batchmode")]

            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=lambda: table)
            self.assertEqual("E_UNITY_OWNED", ctx.exception.code)

    def test_no_owner_and_no_lock_is_headless_safe(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            # Must not raise.
            self.assertIsNone(
                assert_headless_safe(project, process_table_provider=lambda: ())
            )

    def test_sibling_project_with_owner_elsewhere_is_headless_safe(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            sibling = Path(tmp) / "proj-sibling"
            sibling.mkdir()
            table = [_unity_process(4242, str(sibling))]
            self.assertIsNone(
                assert_headless_safe(project, process_table_provider=lambda: table)
            )

    def test_owned_error_message_does_not_overclaim_gui(self):
        # M5: the detector cannot distinguish a GUI Editor from a
        # concurrent headless run holding the same lock/process signals --
        # the raised message must not assert "GUI" specifically.
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [_unity_process(1, str(project))]
            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=lambda: table)
            self.assertNotIn("GUI", str(ctx.exception))


class TokenizeCommandLineTests(unittest.TestCase):
    def test_posix_split_is_plain_whitespace_no_shell_semantics(self):
        tokens = _tokenize_command_line(
            "/opt/Unity/Editor/Unity -projectPath /home/u/My Project -logFile -",
            windows=False,
        )
        self.assertEqual(
            ["/opt/Unity/Editor/Unity", "-projectPath", "/home/u/My", "Project",
             "-logFile", "-"],
            tokens,
        )

    def test_windows_quoted_token_with_space_is_one_token(self):
        tokens = _tokenize_command_line(
            '"C:\\Unity\\Editor\\Unity.exe" -projectPath "C:\\proj\\My Game" -logFile -',
            windows=True,
        )
        self.assertEqual(
            ["C:\\Unity\\Editor\\Unity.exe", "-projectPath", "C:\\proj\\My Game",
             "-logFile", "-"],
            tokens,
        )

    def test_windows_backslashes_are_never_treated_as_escapes(self):
        # This is the exact corruption CRITICAL 1 reported against shlex's
        # POSIX-mode escape handling: a bare backslash-separated Windows
        # path must survive tokenization unchanged.
        tokens = _tokenize_command_line(
            "C:\\Unity\\Editor\\Unity.exe -projectPath C:\\proj\\game", windows=True
        )
        self.assertEqual(
            ["C:\\Unity\\Editor\\Unity.exe", "-projectPath", "C:\\proj\\game"],
            tokens,
        )


class ParsePosixProcessTableTests(unittest.TestCase):
    def test_parses_pid_and_command(self):
        stdout = "  1234 /opt/Unity/Editor/Unity -batchmode\n  5678 /bin/bash\n"
        table = _parse_posix_process_table(stdout)
        self.assertEqual(
            ((1234, "/opt/Unity/Editor/Unity -batchmode"), (5678, "/bin/bash")),
            table,
        )

    def test_blank_lines_and_bad_pids_are_skipped(self):
        stdout = "\n   \nnot-a-pid something\n42 ok\n"
        self.assertEqual(((42, "ok"),), _parse_posix_process_table(stdout))


class ParseWindowsProcessTableTests(unittest.TestCase):
    def test_parses_pid_tab_commandline_lines(self):
        stdout = (
            "1234\tC:\\Unity\\Editor\\Unity.exe -projectPath C:\\proj\\game\n"
            "5678\tC:\\Windows\\explorer.exe\n"
        )
        table = _parse_windows_process_table(stdout)
        self.assertEqual(
            (
                (1234, "C:\\Unity\\Editor\\Unity.exe -projectPath C:\\proj\\game"),
                (5678, "C:\\Windows\\explorer.exe"),
            ),
            table,
        )

    def test_lines_without_a_tab_are_skipped(self):
        self.assertEqual((), _parse_windows_process_table("no tab on this line\n"))


class UnityLockfilePresentTests(unittest.TestCase):
    def test_missing_file_is_false(self):
        with TemporaryDirectory() as tmp:
            self.assertFalse(_unity_lockfile_present(Path(tmp)))

    def test_existing_file_is_true(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "Temp").mkdir()
            (project / "Temp" / "UnityLockfile").write_text("", encoding="utf-8")
            self.assertTrue(_unity_lockfile_present(project))

    def test_unreadable_temp_dir_reads_as_present_not_absent(self):
        # Path.exists() swallows every OSError, including a permission
        # error, and reports it identically to "file genuinely absent".
        # An unreadable Temp/ must be treated as a signal, not silent safety.
        with TemporaryDirectory() as tmp:
            project = Path(tmp)
            with patch(
                "tools.kinglet_spike.unity.ownership.Path.stat",
                side_effect=PermissionError("denied"),
            ):
                self.assertTrue(_unity_lockfile_present(project))


class ProcessTableProviderFailureTests(unittest.TestCase):
    # IMPORTANT 4: a provider that cannot obtain a listing must raise
    # E_UNITY_OWNER_UNKNOWN, never silently return an empty table that
    # detect_gui_owner/assert_headless_safe would then read as "safe".

    def test_posix_provider_raises_on_oserror(self):
        with patch(
            "tools.kinglet_spike.unity.ownership.subprocess.run",
            side_effect=OSError("no ps"),
        ):
            with self.assertRaises(EvidenceError) as ctx:
                _posix_process_table()
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_posix_provider_raises_on_timeout(self):
        with patch(
            "tools.kinglet_spike.unity.ownership.subprocess.run",
            side_effect=subprocess.TimeoutExpired(cmd="ps", timeout=10),
        ):
            with self.assertRaises(EvidenceError) as ctx:
                _posix_process_table()
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_posix_provider_raises_on_nonzero_exit(self):
        fake_result = SimpleNamespace(returncode=1, stdout="", stderr="permission denied")
        with patch(
            "tools.kinglet_spike.unity.ownership.subprocess.run",
            return_value=fake_result,
        ):
            with self.assertRaises(EvidenceError) as ctx:
                _posix_process_table()
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_windows_provider_raises_on_oserror(self):
        with patch(
            "tools.kinglet_spike.unity.ownership.subprocess.run",
            side_effect=OSError("no powershell"),
        ):
            with self.assertRaises(EvidenceError) as ctx:
                _windows_process_table()
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_windows_provider_raises_on_nonzero_exit(self):
        fake_result = SimpleNamespace(returncode=1, stdout="", stderr="access denied")
        with patch(
            "tools.kinglet_spike.unity.ownership.subprocess.run",
            return_value=fake_result,
        ):
            with self.assertRaises(EvidenceError) as ctx:
                _windows_process_table()
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_assert_headless_safe_propagates_provider_failure_rather_than_safe(self):
        def _boom():
            raise EvidenceError("E_UNITY_OWNER_UNKNOWN", "cannot list processes")

        with TemporaryDirectory() as tmp:
            project = Path(tmp)
            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=_boom)
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)


if __name__ == "__main__":
    unittest.main()
