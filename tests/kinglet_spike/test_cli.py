import subprocess
import sys
import unittest
from io import StringIO
from pathlib import Path
from unittest.mock import patch

from tools.kinglet_spike.cli import gate_open_items, main

REPO = Path(__file__).resolve().parents[2]

# A gate that is genuinely open in this repo: the Claude Code client probe ran on
# Linux only, so its macOS and Windows cells are missing.
OPEN_GATE = "0C:claude-code"


class CliTests(unittest.TestCase):
    def test_validate_returns_two_for_invalid_evidence(self):
        with patch("tools.kinglet_spike.cli.validate_path", side_effect=ValueError("bad")):
            self.assertEqual(2, main(["validate", "record.json"]))

    def test_gate_returns_one_for_open_cells(self):
        with patch("tools.kinglet_spike.cli.gate_is_closed", return_value=False):
            self.assertEqual(1, main(["gate", "0A"]))


class GateReportingTests(unittest.TestCase):
    """A gate that exits 1 in silence forces the operator to reconstruct the open
    cells out-of-band from coverage.json. Name them on stderr instead."""

    def test_failing_gate_names_the_open_cells_on_stderr(self):
        stderr = StringIO()
        with patch("sys.stderr", stderr):
            status = main(["gate", OPEN_GATE, "--repo-root", str(REPO)])
        self.assertEqual(1, status)
        printed = stderr.getvalue()
        for cell_id in gate_open_items(OPEN_GATE, REPO):
            self.assertIn(cell_id, printed)
        self.assertIn("client.claude-code.", printed)

    def test_gate_open_items_reports_missing_0a_files(self):
        items = gate_open_items("0A", REPO / "does-not-exist")
        self.assertTrue(items)
        self.assertTrue(all(item.startswith("missing file") for item in items))

    def test_closed_gate_prints_nothing(self):
        stderr = StringIO()
        with patch("sys.stderr", stderr):
            status = main(["gate", "0A", "--repo-root", str(REPO)])
        self.assertEqual(0, status)
        self.assertEqual("", stderr.getvalue())


class CliModuleEntryPointTests(unittest.TestCase):
    """`python3 -m tools.kinglet_spike.cli` must behave like
    `python3 -m tools.kinglet_spike`. Without a __main__ guard in cli.py the
    module form parses nothing, evaluates nothing, and exits 0 — a gate
    invocation that always reports success."""

    def _run(self, module: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, "-m", module, "gate", OPEN_GATE, "--repo-root", "."],
            cwd=REPO,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_cli_module_form_fails_an_open_gate(self):
        result = self._run("tools.kinglet_spike.cli")
        self.assertNotEqual(
            0,
            result.returncode,
            "python3 -m tools.kinglet_spike.cli reported an OPEN gate as success",
        )
        self.assertEqual(1, result.returncode)

    def test_both_module_forms_agree(self):
        package = self._run("tools.kinglet_spike")
        module = self._run("tools.kinglet_spike.cli")
        self.assertEqual(package.returncode, module.returncode)
        self.assertEqual(package.stderr, module.stderr)


if __name__ == "__main__":
    unittest.main()
