import json
import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.unity.ownership import (
    ProjectOwner,
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


if __name__ == "__main__":
    unittest.main()
