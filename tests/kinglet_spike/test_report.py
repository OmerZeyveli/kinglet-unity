import unittest

from tools.kinglet_spike.model import CoverageCell
from tools.kinglet_spike.report import render_markdown


class ReportTests(unittest.TestCase):
    def test_markdown_is_sorted_and_byte_stable(self):
        cells = [
            CoverageCell("z.cell", "missing", ()),
            CoverageCell("a.cell", "pass", ("run-a",)),
        ]
        expected = (
            "# Kinglet Platform Spike Coverage\n\n"
            "| Cell | State | Runs |\n| --- | --- | --- |\n"
            "| `a.cell` | pass | `run-a` |\n"
            "| `z.cell` | missing | — |\n"
        )
        self.assertEqual(expected, render_markdown(cells))
        self.assertEqual(expected, render_markdown(reversed(cells)))
