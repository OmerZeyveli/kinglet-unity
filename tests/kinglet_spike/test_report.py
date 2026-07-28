import unittest

from tools.kinglet_spike.model import (
    AssertionResult,
    CoverageCell,
    Environment,
    EvidenceRecord,
    Probe,
    Subject,
)
from tools.kinglet_spike.report import _known_artefact_lines, render_markdown


def _unity_record(run_id: str, status: str, started: str, ended: str) -> EvidenceRecord:
    return EvidenceRecord(
        schema="kinglet.spike.evidence/v1",
        run_id=run_id,
        subject=Subject(kind="unity", id="execution", version="6000.3.18f1"),
        probe=Probe(id="filesystem-only", contract="c"),
        environment=Environment(
            os="linux", release="ubuntu-24.04.4-lts", arch="x64",
            native=True, toolchain=("host=x",),
        ),
        started_at=started,
        ended_at=ended,
        status=status,
        command=("x",),
        artifacts=(),
        assertions=(AssertionResult(id="a", status="pass", detail="d"),),
        measurements=(),
        sources=(),
        prompt=None,
    )


class KnownArtefactDisclosureTests(unittest.TestCase):
    """The reader-facing note about defects the published records still carry."""

    def test_an_inconclusive_record_with_a_zero_span_is_disclosed_too(self):
        # Filtering to `pass` reported 8 of 9: the `live-editor-mcp` record is
        # `inconclusive` and carries the SAME zero-length span, so it was
        # missing from both the count and the list -- and the section would
        # have retired itself while a defective record was still published.
        records = (
            _unity_record("run-pass", "pass", "2026-07-28T00:00:00Z", "2026-07-28T00:00:00Z"),
            _unity_record("run-open", "inconclusive", "2026-07-28T00:00:00Z", "2026-07-28T00:00:00Z"),
        )
        lines = _known_artefact_lines(records)
        body = "\n".join(lines)
        self.assertIn("2 records report", body)
        self.assertIn("- `run-pass`", body)
        self.assertIn("- `run-open`", body)

    def test_the_section_retires_itself_when_no_record_carries_the_defect(self):
        records = (
            _unity_record("run-fixed", "pass", "2026-07-28T00:00:00Z", "2026-07-28T00:00:22Z"),
            _unity_record("run-open", "inconclusive", "2026-07-28T00:00:00Z", "2026-07-28T00:00:05Z"),
        )
        self.assertEqual(_known_artefact_lines(records), [])



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
