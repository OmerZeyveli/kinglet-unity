import tempfile
import unittest
from pathlib import Path

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.publish import publish_record
from tests.kinglet_spike.support import valid_record, write_record


class PublishTests(unittest.TestCase):
    def test_rejects_symlinked_committed_evidence_ancestor(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            outside = root / "outside"
            outside.mkdir()
            (root / "docs").symlink_to(outside, target_is_directory=True)
            raw_root = root / ".kinglet/local/spikes/run-01"
            artifact = (
                raw_root / "publish/artifacts/runtime/python"
                / "20260723T120000Z-runtime-python-windows11-x64-01/result.json"
            )
            artifact.parent.mkdir(parents=True)
            artifact.write_bytes(b'{"ok":true}\n')
            raw = write_record(raw_root, valid_record())
            with self.assertRaisesRegex(EvidenceError, "E_SYMLINK"):
                publish_record(raw, root)

    def test_rejects_record_outside_local_spike_root(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw_root = root / "outside"
            artifact = (
                raw_root / "publish/artifacts/runtime/python"
                / "20260723T120000Z-runtime-python-windows11-x64-01/result.json"
            )
            artifact.parent.mkdir(parents=True)
            artifact.write_bytes(b'{"ok":true}\n')
            raw = write_record(raw_root, valid_record())
            with self.assertRaisesRegex(EvidenceError, "E_PATH"):
                publish_record(raw, root)

    def test_publishes_canonical_json_once(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw_root = root / ".kinglet/local/spikes/run-01"
            artifact = (
                raw_root / "publish/artifacts/runtime/python"
                / "20260723T120000Z-runtime-python-windows11-x64-01/result.json"
            )
            artifact.parent.mkdir(parents=True)
            artifact.write_bytes(b'{"ok":true}\n')
            raw = write_record(raw_root, valid_record())
            target = publish_record(raw, root)
            self.assertTrue(target.is_file())
            published_artifact = (
                root / "docs/research/platform-spike/artifacts/runtime/python"
                / "20260723T120000Z-runtime-python-windows11-x64-01/result.json"
            )
            self.assertEqual(b'{"ok":true}\n', published_artifact.read_bytes())
            self.assertTrue(target.read_text(encoding="utf-8").endswith("\n"))
            with self.assertRaisesRegex(EvidenceError, "E_IMMUTABLE"):
                publish_record(raw, root)
