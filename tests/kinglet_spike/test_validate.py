import tempfile
import unittest
from pathlib import Path

from tools.kinglet_spike.load import load_record
from tools.kinglet_spike.redact import redact_artifact
from tools.kinglet_spike.validate import validate_record
from tests.kinglet_spike.support import valid_record, write_record


class ValidateRecordTests(unittest.TestCase):
    def _diagnostics(self, value: dict, artifact: bool = True):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        if artifact:
            path = (
                root / "publish/artifacts/runtime/python"
                / "20260723T120000Z-runtime-python-windows11-x64-01/result.json"
            )
            path.parent.mkdir(parents=True)
            path.write_bytes(b'{"ok":true}\n')
        record = load_record(write_record(root, value))
        return validate_record(record, root / "publish")

    def test_valid_record_has_no_diagnostics(self):
        self.assertEqual((), self._diagnostics(valid_record()))

    def test_rejects_absolute_and_parent_paths(self):
        absolute = valid_record("/Users/alice/result.json")
        traversal = valid_record("../result.json")
        self.assertEqual("E_PATH", self._diagnostics(absolute, artifact=False)[0].code)
        self.assertEqual("E_PATH", self._diagnostics(traversal, artifact=False)[0].code)

    def test_rejects_symlink_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target.json"
            target.write_bytes(b'{"ok":true}\n')
            link = root / "publish/artifacts/link.json"
            link.parent.mkdir(parents=True)
            link.symlink_to(target)
            record = load_record(
                write_record(root, valid_record("artifacts/link.json"))
            )
            self.assertEqual(
                "E_SYMLINK", validate_record(record, root / "publish")[0].code
            )

    def test_missing_required_artifact_is_not_a_pass(self):
        diagnostics = self._diagnostics(valid_record(), artifact=False)
        self.assertEqual("E_PATH", diagnostics[0].code)

    def test_rejects_artifact_outside_artifacts_namespace(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / "publish/reports/result.json"
            artifact.parent.mkdir(parents=True)
            artifact.write_bytes(b'{"ok":true}\n')
            record = load_record(
                write_record(root, valid_record("reports/result.json"))
            )
            self.assertEqual(
                "E_PATH",
                validate_record(record, root / "publish")[0].code,
            )

    def test_rejects_binary_artifact_media_type(self):
        value = valid_record()
        value["artifacts"][0]["media_type"] = "image/png"
        self.assertEqual("E_ENUM", self._diagnostics(value)[0].code)

    def test_rejects_unsafe_identity(self):
        value = valid_record()
        value["subject"]["id"] = "../python"
        self.assertEqual("E_FIELD", self._diagnostics(value)[0].code)

    def test_pass_requires_artifact_checksum_and_all_assertions(self):
        value = valid_record()
        value["artifacts"][0]["sha256"] = "0" * 64
        value["assertions"][0]["status"] = "fail"
        codes = {item.code for item in self._diagnostics(value)}
        self.assertEqual({"E_ASSERTION", "E_CHECKSUM"}, codes)

    def test_pass_requires_native_environment(self):
        value = valid_record()
        value["environment"]["native"] = False
        self.assertEqual("E_ASSERTION", self._diagnostics(value)[0].code)

    def test_pass_requires_version_toolchain_command_and_source(self):
        value = valid_record()
        value["subject"]["version"] = ""
        value["environment"]["toolchain"] = []
        value["command"] = []
        value["sources"] = []
        diagnostics = self._diagnostics(value)
        self.assertEqual(
            {"subject.version", "environment.toolchain", "command", "sources"},
            {item.location for item in diagnostics if item.code == "E_FIELD"},
        )

    def test_rejects_raw_prompt_and_sensitive_command(self):
        value = valid_record()
        value["prompt"] = {"id": "client-discovery-01", "sha256": "a" * 64, "raw": "secret"}
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(Exception, "E_FIELD.*prompt.raw"):
                load_record(write_record(Path(directory), value))

        value = valid_record()
        value["command"] = ["tool", "--token", "ghp_123456789012345678901234567890123456"]
        self.assertEqual("E_SECRET", self._diagnostics(value)[0].code)

    def test_rejects_windows_user_path_in_record_strings(self):
        value = valid_record()
        value["command"] = ["tool", r"C:\Users\alice\project"]
        self.assertEqual("E_PATH", self._diagnostics(value)[0].code)

    def test_pass_requires_five_cold_start_samples(self):
        value = valid_record()
        value["measurements"][0]["samples"] = [12, 11, 13, 12]
        self.assertEqual("E_REPETITION", self._diagnostics(value)[0].code)

    def test_redactor_replaces_declared_root_and_rejects_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "raw.json"
            target = root / "publish.json"
            source.write_text('{"path":"C:\\\\Users\\\\probe\\\\project"}', encoding="utf-8")
            digest = redact_artifact(
                source, target, "application/json", ("C:\\Users\\probe",)
            )
            self.assertIn("<redacted-root>", target.read_text(encoding="utf-8"))
            self.assertEqual(64, len(digest))
            with self.assertRaisesRegex(Exception, "E_ENUM"):
                redact_artifact(source, root / "image.png", "image/png", ())

    def test_redactor_rejects_undeclared_windows_user_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "raw.json"
            source.write_text(
                '{"path":"C:\\\\Users\\\\alice\\\\project"}',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(Exception, "E_PATH"):
                redact_artifact(
                    source,
                    root / "publish.json",
                    "application/json",
                    (),
                )

    def test_redactor_rejects_symlink_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source_target = root / "source-target.json"
            source_target.write_text('{"ok":true}', encoding="utf-8")
            source = root / "raw.json"
            source.symlink_to(source_target)
            with self.assertRaisesRegex(Exception, "E_SYMLINK"):
                redact_artifact(
                    source,
                    root / "publish.json",
                    "application/json",
                    (),
                )
