import json
import tempfile
import unittest
from pathlib import Path

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.publish import publish_record
from tests.kinglet_spike.support import valid_record, write_record


class PublishTests(unittest.TestCase):
    def _raw_record(self, root: Path, value: dict | None = None) -> Path:
        raw_root = root / ".kinglet/local/spikes/run-01"
        artifact = (
            raw_root / "publish/artifacts/runtime/python"
            / "20260723T120000Z-runtime-python-windows11-x64-01/result.json"
        )
        artifact.parent.mkdir(parents=True)
        artifact.write_bytes(b'{"ok":true}\n')
        return write_record(raw_root, valid_record() if value is None else value)

    def test_publishes_canonical_json_once(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = self._raw_record(root)

            target = publish_record(raw, root)

            self.assertTrue(target.is_file())
            published_artifact = (
                root / "docs/research/platform-spike/artifacts/runtime/python"
                / "20260723T120000Z-runtime-python-windows11-x64-01/result.json"
            )
            self.assertEqual(b'{"ok":true}\n', published_artifact.read_bytes())
            self.assertTrue(target.read_text(encoding="utf-8").endswith("\n"))
            self.assertEqual(
                json.loads(target.read_text(encoding="utf-8"))["run_id"],
                "20260723T120000Z-runtime-python-windows11-x64-01",
            )
            with self.assertRaisesRegex(EvidenceError, "E_IMMUTABLE"):
                publish_record(raw, root)

    def test_rejects_invalid_evidence_before_creating_publish_targets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            value = valid_record()
            value["artifacts"][0]["sha256"] = "0" * 64
            raw = self._raw_record(root, value)

            with self.assertRaisesRegex(EvidenceError, "E_CHECKSUM"):
                publish_record(raw, root)

            self.assertFalse((root / "docs/research/platform-spike").exists())
