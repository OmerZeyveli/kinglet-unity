import json
import os
import tempfile
import unittest
from unittest import mock
from pathlib import Path

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.publish import _copy_exclusive, publish_record
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

    def test_rejects_unsafe_dynamic_destination_components(self):
        unsafe_values = ("../escape", "/escape", "escape\\child", ".")
        for field in ("subject.id", "run_id"):
            for unsafe_value in unsafe_values:
                with self.subTest(field=field, value=unsafe_value), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    value = valid_record()
                    if field == "subject.id":
                        value["subject"]["id"] = unsafe_value
                    else:
                        value["run_id"] = unsafe_value
                    raw = self._raw_record(root, value)

                    with self.assertRaisesRegex(EvidenceError, "E_PATH"):
                        publish_record(raw, root)

                    self.assertFalse((root / "docs/research/platform-spike").exists())

    def test_rejects_nested_raw_record_layout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            nested = root / ".kinglet/local/spikes/run-01/nested"
            artifact = nested / "publish/artifacts/runtime/python/result.json"
            artifact.parent.mkdir(parents=True)
            artifact.write_bytes(b'{"ok":true}\n')
            raw = write_record(nested, valid_record("artifacts/runtime/python/result.json"))

            with self.assertRaisesRegex(EvidenceError, "E_PATH"):
                publish_record(raw, root)

    def test_rejects_artifact_destination_parent_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            outside = root / "outside"
            outside.mkdir()
            platform_root = root / "docs/research/platform-spike"
            platform_root.mkdir(parents=True)
            try:
                (platform_root / "artifacts").symlink_to(outside, target_is_directory=True)
            except (NotImplementedError, OSError) as error:
                self.skipTest(f"symlinks unavailable: {error}")
            raw = self._raw_record(root)

            with self.assertRaisesRegex(EvidenceError, "E_SYMLINK"):
                publish_record(raw, root)

            self.assertEqual((), tuple(outside.iterdir()))

    def test_rejects_evidence_destination_parent_symlink_before_artifact_write(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            outside = root / "outside"
            outside.mkdir()
            platform_root = root / "docs/research/platform-spike"
            platform_root.mkdir(parents=True)
            try:
                (platform_root / "evidence").symlink_to(outside, target_is_directory=True)
            except (NotImplementedError, OSError) as error:
                self.skipTest(f"symlinks unavailable: {error}")
            raw = self._raw_record(root)

            with self.assertRaisesRegex(EvidenceError, "E_SYMLINK"):
                publish_record(raw, root)

            self.assertFalse((platform_root / "artifacts").exists())
            self.assertEqual((), tuple(outside.iterdir()))

    def test_copy_rejects_symlink_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.json"
            replacement = root / "replacement.json"
            replacement.write_bytes(b'{"ok":true}\n')
            try:
                source.symlink_to(replacement)
            except (NotImplementedError, OSError) as error:
                self.skipTest(f"symlinks unavailable: {error}")
            destination = root / "destination.json"

            with self.assertRaisesRegex(EvidenceError, "E_SYMLINK"):
                _copy_exclusive(source, destination, "0" * 64)

            self.assertFalse(destination.exists())

    def test_copy_rejects_source_replaced_by_symlink_before_open(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.json"
            source.write_bytes(b'{"ok":true}\n')
            replacement = root / "replacement.json"
            replacement.write_bytes(b'{"attacker":true}\n')
            try:
                probe = root / "symlink-probe"
                probe.symlink_to(replacement)
                probe.unlink()
            except (NotImplementedError, OSError) as error:
                self.skipTest(f"symlinks unavailable: {error}")
            destination = root / "destination.json"
            real_open = os.open

            def replace_source(path, flags, mode=0o777, *, dir_fd=None):
                if Path(path) == source and not flags & os.O_WRONLY:
                    source.unlink()
                    source.symlink_to(replacement)
                if dir_fd is None:
                    return real_open(path, flags, mode)
                return real_open(path, flags, mode, dir_fd=dir_fd)

            with mock.patch("tools.kinglet_spike.publish.os.open", side_effect=replace_source):
                with self.assertRaisesRegex(EvidenceError, "E_SYMLINK"):
                    _copy_exclusive(source, destination, "0" * 64)

            self.assertFalse(destination.exists())

    def test_copy_keeps_creation_in_verified_parent_after_parent_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.json"
            source.write_bytes(b'{"ok":true}\n')
            committed_root = root / "docs/research/platform-spike"
            destination = committed_root / "artifacts/result.json"
            outside = root / "outside"
            outside.mkdir()
            verified_parent = destination.parent
            verified_parent.mkdir(parents=True)
            displaced_parent = committed_root / "displaced-artifacts"
            real_open = os.open
            replaced = False

            def replace_parent(path, flags, mode=0o777, *, dir_fd=None):
                nonlocal replaced
                if (
                    not replaced
                    and flags & os.O_CREAT
                    and Path(path).name == destination.name
                ):
                    replaced = True
                    verified_parent.rename(displaced_parent)
                    verified_parent.symlink_to(outside, target_is_directory=True)
                if dir_fd is None:
                    return real_open(path, flags, mode)
                return real_open(path, flags, mode, dir_fd=dir_fd)

            with mock.patch("tools.kinglet_spike.publish.os.open", side_effect=replace_parent):
                _copy_exclusive(
                    source,
                    destination,
                    "e5f1eb4d806641698a35efe20e098efd20d7d57a9b90ee69079d5bb650920726",
                    repo_root=root,
                    committed_root=committed_root,
                )

            self.assertTrue(replaced)
            self.assertEqual((), tuple(outside.iterdir()))
            self.assertEqual(b'{"ok":true}\n', (displaced_parent / "result.json").read_bytes())

    def test_record_fsync_failure_removes_only_incomplete_record(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = self._raw_record(root)
            fsync_calls = 0
            real_fsync = os.fsync

            def fail_record_fsync(descriptor):
                nonlocal fsync_calls
                fsync_calls += 1
                if fsync_calls == 2:
                    raise OSError("record fsync failed")
                return real_fsync(descriptor)

            with mock.patch("tools.kinglet_spike.publish.os.fsync", side_effect=fail_record_fsync):
                with self.assertRaisesRegex(OSError, "record fsync failed"):
                    publish_record(raw, root)

            artifact = root / "docs/research/platform-spike/artifacts/runtime/python/20260723T120000Z-runtime-python-windows11-x64-01/result.json"
            record = root / "docs/research/platform-spike/evidence/runtime/python/20260723T120000Z-runtime-python-windows11-x64-01.json"
            self.assertEqual(b'{"ok":true}\n', artifact.read_bytes())
            self.assertFalse(record.exists())
