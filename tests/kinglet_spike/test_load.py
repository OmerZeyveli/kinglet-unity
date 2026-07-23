import tempfile
import unittest
from pathlib import Path

from tools.kinglet_spike.load import load_record
from tools.kinglet_spike.model import EvidenceError
from tests.kinglet_spike.support import valid_record, write_record


class LoadRecordTests(unittest.TestCase):
    def test_loads_v1_into_frozen_types(self):
        with tempfile.TemporaryDirectory() as directory:
            record = load_record(write_record(Path(directory), valid_record()))
        self.assertEqual("python", record.subject.id)
        self.assertEqual(("python=3.14.6", "pyinstaller=6.21.0"), record.environment.toolchain)
        self.assertEqual((12, 11, 13, 12, 11), record.measurements[0].samples)

    def test_rejects_unknown_nested_field(self):
        value = valid_record()
        value["subject"]["preference"] = "favorite"
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(EvidenceError, "E_FIELD.*subject.preference"):
                load_record(write_record(Path(directory), value))

    def test_rejects_wrong_schema(self):
        value = valid_record()
        value["schema"] = "kinglet.spike.evidence/v2"
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(EvidenceError, "E_SCHEMA"):
                load_record(write_record(Path(directory), value))
