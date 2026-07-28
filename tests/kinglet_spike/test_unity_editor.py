import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.unity.editor import (
    EditorIdentity,
    read_project_version,
    verify_editor,
)

PROJECT_VERSION_TEXT = (
    "m_EditorVersion: 6000.3.18f1\n"
    "m_EditorVersionWithRevision: 6000.3.18f1 (5ebeb53e4c07)\n"
)


def _write_project_version(root: Path, text: str = PROJECT_VERSION_TEXT) -> Path:
    settings = root / "ProjectSettings"
    settings.mkdir(parents=True, exist_ok=True)
    version_path = settings / "ProjectVersion.txt"
    version_path.write_text(text, encoding="utf-8")
    return root


class ReadProjectVersionTests(unittest.TestCase):
    def test_reads_m_editor_version_not_with_revision(self):
        with TemporaryDirectory() as tmp:
            project = _write_project_version(Path(tmp))
            self.assertEqual("6000.3.18f1", read_project_version(project))

    def test_two_line_file_ignores_second_line(self):
        # Ground truth: Unity always writes both lines, and a one-line
        # fixture missing the revision line hid a real bug in this repo
        # before. Assert the reader still returns the bare version even
        # when a revision-qualified second line is present.
        with TemporaryDirectory() as tmp:
            project = _write_project_version(
                Path(tmp),
                "m_EditorVersion: 2022.3.62f3\n"
                "m_EditorVersionWithRevision: 2022.3.62f3 (deadbeef1234)\n",
            )
            self.assertEqual("2022.3.62f3", read_project_version(project))

    def test_missing_file_raises_e_field(self):
        with TemporaryDirectory() as tmp:
            with self.assertRaises(EvidenceError) as ctx:
                read_project_version(Path(tmp))
            self.assertEqual("E_FIELD", ctx.exception.code)

    def test_missing_editor_version_line_raises_e_field(self):
        with TemporaryDirectory() as tmp:
            project = _write_project_version(Path(tmp), "m_SomeOtherField: 1\n")
            with self.assertRaises(EvidenceError) as ctx:
                read_project_version(project)
            self.assertEqual("E_FIELD", ctx.exception.code)

    def test_malformed_version_shape_raises_e_field(self):
        with TemporaryDirectory() as tmp:
            project = _write_project_version(Path(tmp), "m_EditorVersion: not-a-version\n")
            with self.assertRaises(EvidenceError) as ctx:
                read_project_version(project)
            self.assertEqual("E_FIELD", ctx.exception.code)


class VerifyEditorTests(unittest.TestCase):
    def test_exact_match_returns_editor_identity(self):
        identity = verify_editor(
            Path("/fake/Unity"),
            "6000.3.18f1",
            run_version_flag=lambda editor: "6000.3.18f1\n",
        )
        self.assertEqual(
            EditorIdentity(editor_path="/fake/Unity", version="6000.3.18f1"),
            identity,
        )

    def test_mismatched_version_raises_e_unity_version(self):
        with self.assertRaises(EvidenceError) as ctx:
            verify_editor(
                Path("/fake/Unity"),
                "6000.3.12f1",
                run_version_flag=lambda editor: "6000.3.18f1\n",
            )
        self.assertEqual("E_UNITY_VERSION", ctx.exception.code)

    def test_close_but_not_exact_patch_mismatch_still_refuses(self):
        # verify_editor must never treat "close" as good enough -- only
        # exact equality passes.
        with self.assertRaises(EvidenceError) as ctx:
            verify_editor(
                Path("/fake/Unity"),
                "6000.3.11f1",
                run_version_flag=lambda editor: "6000.3.11f2\n",
            )
        self.assertEqual("E_UNITY_VERSION", ctx.exception.code)

    def test_never_falls_back_to_closest_installed_version(self):
        # A caller might hand verify_editor several installed versions on a
        # multi-editor host (this host has 2022.3.62f3, 6000.0.68f1,
        # 6000.3.18f1); it must reject every one that isn't an exact match,
        # never silently pick the "closest".
        installed = ("2022.3.62f3", "6000.0.68f1", "6000.3.18f1")
        required = "6000.3.11f1"
        for reported in installed:
            with self.subTest(reported=reported):
                with self.assertRaises(EvidenceError) as ctx:
                    verify_editor(
                        Path("/fake/Unity"),
                        required,
                        run_version_flag=lambda editor, r=reported: f"{r}\n",
                    )
                self.assertEqual("E_UNITY_VERSION", ctx.exception.code)

    def test_empty_stdout_raises_e_unity_version_not_a_pass(self):
        with self.assertRaises(EvidenceError) as ctx:
            verify_editor(
                Path("/fake/Unity"),
                "6000.3.18f1",
                run_version_flag=lambda editor: "",
            )
        self.assertEqual("E_UNITY_VERSION", ctx.exception.code)

    def test_unexecutable_editor_raises_e_field(self):
        def _raise(editor: Path) -> str:
            raise EvidenceError("E_FIELD", "cannot execute editor")

        with self.assertRaises(EvidenceError) as ctx:
            verify_editor(Path("/fake/Unity"), "6000.3.18f1", run_version_flag=_raise)
        self.assertEqual("E_FIELD", ctx.exception.code)


if __name__ == "__main__":
    unittest.main()
