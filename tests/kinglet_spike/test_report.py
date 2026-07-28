import unittest

from tools.kinglet_spike.model import (
    Artifact,
    AssertionResult,
    CoverageCell,
    Environment,
    EvidenceRecord,
    Probe,
    Subject,
)
from tools.kinglet_spike.report import (
    _known_artefact_lines,
    _shared_artifact_lines,
    render_markdown,
)


def _unity_record(
    run_id: str,
    status: str,
    started: str,
    ended: str,
    *,
    probe_id: str = "filesystem-only",
    artifacts: tuple = (),
) -> EvidenceRecord:
    return EvidenceRecord(
        schema="kinglet.spike.evidence/v1",
        run_id=run_id,
        subject=Subject(kind="unity", id="execution", version="6000.3.18f1"),
        probe=Probe(id=probe_id, contract="c"),
        environment=Environment(
            os="linux", release="ubuntu-24.04.4-lts", arch="x64",
            native=True, toolchain=("host=x",),
        ),
        started_at=started,
        ended_at=ended,
        status=status,
        command=("x",),
        artifacts=artifacts,
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



class ArtifactHonestyTests(unittest.TestCase):
    """FINAL whole-branch review: the report claimed more evidence than exists."""

    @staticmethod
    def _artifact(digest: str) -> Artifact:
        return Artifact(path=f"artifacts/{digest}.json", sha256=digest,
                        media_type="application/json", required=True)

    def test_a_record_with_no_artifact_is_named_not_covered_by_a_blanket_claim(self):
        # ":44-46" said "every record regardless of the verdict" was verified
        # against its artifact -- while `live-editor-mcp` has `artifacts: []`.
        records = (
            _unity_record("run-with", "pass", "T0", "T0",
                          artifacts=(self._artifact("a" * 64),)),
            _unity_record("run-without", "inconclusive", "T0", "T0"),
        )
        body = "\n".join(_known_artefact_lines(records))
        self.assertIn("That is not every record", body)
        self.assertIn("- `run-without`", body)
        self.assertNotIn("for every record regardless of the verdict", body)

    def test_the_blanket_claim_returns_when_every_record_has_an_artifact(self):
        # Otherwise the correction would be an unconditional hedge.
        records = (
            _unity_record("run-a", "pass", "T0", "T0",
                          artifacts=(self._artifact("a" * 64),)),
            _unity_record("run-b", "pass", "T0", "T0",
                          artifacts=(self._artifact("b" * 64),)),
        )
        body = "\n".join(_known_artefact_lines(records))
        self.assertIn("for every record regardless of the verdict", body)
        self.assertNotIn("That is not every record", body)

    def test_the_duration_note_does_not_cite_values_it_cannot_support(self):
        # ":51-54" cited three `wall_seconds` values; only two are distinct
        # measurements and two of the three are `duration_seconds`.
        records = (_unity_record("run-a", "pass", "T0", "T0"),)
        body = "\n".join(_known_artefact_lines(records))
        for value in ("14.216", "18.197", "22.151"):
            self.assertNotIn(value, body)
        self.assertIn("Some — not all —", body)

    def test_two_cells_closed_by_one_artifact_are_disclosed_in_the_matrix(self):
        digest = "c" * 64
        records = (
            _unity_record("run-cancel", "pass", "T0", "T1",
                          probe_id="cancellation",
                          artifacts=(self._artifact(digest),)),
            _unity_record("run-orphan", "pass", "T0", "T1",
                          probe_id="orphan-cleanup",
                          artifacts=(self._artifact(digest),)),
        )
        body = "\n".join(_shared_artifact_lines(records))
        self.assertIn("Cells that share one artifact", body)
        self.assertIn("`cancellation` and `orphan-cleanup`", body)

    def test_the_shared_artifact_note_reaches_the_rendered_matrix_section(self):
        # The disclosure is worthless if it is computed and never emitted, so
        # this drives the real renderer: deleting the call from
        # render_unity_markdown must fail here.
        from tools.kinglet_spike.report import render_unity_markdown

        digest = "d" * 64
        records = (
            _unity_record("run-cancel", "pass", "T0", "T1",
                          probe_id="cancellation",
                          artifacts=(self._artifact(digest),)),
            _unity_record("run-orphan", "pass", "T0", "T1",
                          probe_id="orphan-cleanup",
                          artifacts=(self._artifact(digest),)),
        )
        body = render_unity_markdown((), records)
        self.assertIn("Cells that share one artifact", body)
        self.assertIn("`cancellation` and `orphan-cleanup`", body)

    def test_distinct_artifacts_produce_no_shared_artifact_section(self):
        records = (
            _unity_record("run-a", "pass", "T0", "T1", probe_id="cancellation",
                          artifacts=(self._artifact("a" * 64),)),
            _unity_record("run-b", "pass", "T0", "T1", probe_id="orphan-cleanup",
                          artifacts=(self._artifact("b" * 64),)),
        )
        self.assertEqual([], _shared_artifact_lines(records))


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
