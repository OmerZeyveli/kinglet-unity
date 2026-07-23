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
        windows_absolute = valid_record("C:\\Users\\alice\\result.json")
        traversal = valid_record("../result.json")
        self.assertEqual("E_PATH", self._diagnostics(absolute, artifact=False)[0].code)
        self.assertIn("unsafe", self._diagnostics(windows_absolute, artifact=False)[0].message)
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

    def test_pass_requires_artifact_checksum_and_all_assertions(self):
        value = valid_record()
        value["artifacts"][0]["sha256"] = "0" * 64
        value["assertions"][0]["status"] = "fail"
        codes = {item.code for item in self._diagnostics(value)}
        self.assertEqual({"E_ASSERTION", "E_CHECKSUM"}, codes)

    def test_rejects_raw_prompt_and_sensitive_command(self):
        value = valid_record()
        value["prompt"] = {"id": "client-discovery-01", "sha256": "a" * 64, "raw": "secret"}
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(Exception, "E_FIELD.*prompt.raw"):
                load_record(write_record(Path(directory), value))

        value = valid_record()
        value["command"] = ["tool", "--token", "ghp_123456789012345678901234567890123456"]
        self.assertEqual("E_SECRET", self._diagnostics(value)[0].code)

        value = valid_record()
        value["command"] = ["tool", "--account", "alice@example.test"]
        self.assertEqual("E_SECRET", self._diagnostics(value)[0].code)

    def test_pass_requires_five_cold_start_samples(self):
        value = valid_record()
        value["measurements"][0]["samples"] = [12, 11, 13, 12]
        self.assertEqual("E_REPETITION", self._diagnostics(value)[0].code)

    def test_pass_requires_a_cold_start_measurement(self):
        value = valid_record()
        value["measurements"] = []
        self.assertEqual("E_REPETITION", self._diagnostics(value)[0].code)

    def test_redactor_preserves_urls_while_rejecting_absolute_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "raw.txt"
            source.write_text("https://example.test/probe\n", encoding="utf-8")
            target = root / "publish.txt"
            redact_artifact(source, target, "text/plain", ())
            self.assertEqual("https://example.test/probe\n", target.read_text(encoding="utf-8"))

    def test_redactor_replaces_declared_root_and_rejects_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "raw.json"
            target = root / "publish.json"
            source.write_text('{"path":"C:\\\\Users\\\\probe\\\\project"}', encoding="utf-8")
            digest = redact_artifact(
                source, target, "application/json", ("C:\\\\Users\\\\probe",)
            )
            self.assertIn("<redacted-root>", target.read_text(encoding="utf-8"))
            self.assertEqual(64, len(digest))
            with self.assertRaisesRegex(Exception, "E_ENUM"):
                redact_artifact(source, root / "image.png", "image/png", ())
