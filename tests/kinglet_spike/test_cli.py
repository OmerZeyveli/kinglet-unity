import unittest
from unittest.mock import patch

from tools.kinglet_spike.cli import main


class CliTests(unittest.TestCase):
    def test_validate_returns_two_for_invalid_evidence(self):
        with patch("tools.kinglet_spike.cli.validate_path", side_effect=ValueError("bad")):
            self.assertEqual(2, main(["validate", "record.json"]))

    def test_gate_returns_one_for_open_cells(self):
        with patch("tools.kinglet_spike.cli.gate_is_closed", return_value=False):
            self.assertEqual(1, main(["gate", "0A"]))
