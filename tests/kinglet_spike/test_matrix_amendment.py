"""Amending a frozen matrix: a cell may stop being required, but never silently.

The matrix was frozen before any result existed, precisely so it could not be
moved to fit the results. But the host inventory does not cover it: there is no
Intel Mac and none is expected, so `macos-26-x64` can never close, and
`windows-11-x64` is deferred until borrowing a machine is justified. A frozen
contract that cannot be satisfied is not evidence of rigour, it is a gate stuck
at "open" forever with no reader able to tell why.

So `kinglet.spike.matrix/v2` adds a per-cell `disposition` — `required` (the
default), `deferred`, or `dropped` — plus a top-level `amendments` array. The
whole point is the coupling between them: a cell may leave `required` ONLY if a
committed amendment names it and says why. Marking a cell deferred is therefore
exactly as much work as writing down the reason, which is the only property that
makes this different from deleting the cell.

`matrix-v1.json` is not edited. It stays on disk as the frozen original and v2
records that it supersedes it.
"""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools.kinglet_spike.coverage import evaluate_coverage, load_matrix_cells
from tools.kinglet_spike.model import EvidenceError

_CELL = {
    "id": "runtime.go.macos-26-x64.host-probe",
    "subject": {"kind": "runtime", "id": "go"},
    "probe": "host-probe",
    "os": "macos",
    "release": "26.5.2",
    "arch": "x64",
}


def _cell(cell_id: str, **overrides) -> dict:
    cell = dict(_CELL)
    cell["id"] = cell_id
    cell.update(overrides)
    return cell


def _matrix(cells: list[dict], amendments: list[dict] | None = None) -> dict:
    return {
        "schema": "kinglet.spike.matrix/v2",
        "supersedes": "kinglet.spike.matrix/v1",
        "amendments": amendments if amendments is not None else [],
        "cells": sorted(cells, key=lambda item: item["id"]),
    }


def _amendment(disposition: str, cells: list[str], **overrides) -> dict:
    amendment = {
        "id": "2026-07-29-host-inventory",
        "date": "2026-07-29",
        "disposition": disposition,
        "reason": "No Intel Mac is owned and none is expected.",
        "decided_by": "user",
        "cells": cells,
    }
    amendment.update(overrides)
    return amendment


class _MatrixCase(unittest.TestCase):
    def load(self, matrix: dict):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "matrix.json"
            path.write_text(json.dumps(matrix), encoding="utf-8")
            return load_matrix_cells(path)

    def refuses(self, matrix: dict) -> str:
        with self.assertRaises(EvidenceError) as caught:
            self.load(matrix)
        self.assertEqual("E_COVERAGE", caught.exception.code)
        return str(caught.exception)


class DispositionLoadingTests(_MatrixCase):
    def test_a_cell_without_a_disposition_is_required(self):
        cells = self.load(_matrix([_cell("runtime.go.linux.host-probe")]))
        self.assertEqual("required", cells[0].disposition)

    def test_a_v1_matrix_still_loads_and_every_cell_is_required(self):
        # v1 has no disposition and no amendments key at all. It must keep
        # loading unchanged — v1 is the frozen original, not a legacy mistake.
        v1 = {
            "schema": "kinglet.spike.matrix/v1",
            "cells": [_cell("runtime.go.linux.host-probe")],
        }
        cells = self.load(v1)
        self.assertEqual("required", cells[0].disposition)

    def test_a_dropped_cell_named_by_an_amendment_loads_as_dropped(self):
        matrix = _matrix(
            [_cell("runtime.go.macos-26-x64.host-probe", disposition="dropped")],
            [_amendment("dropped", ["runtime.go.macos-26-x64.host-probe"])],
        )
        self.assertEqual("dropped", self.load(matrix)[0].disposition)

    def test_a_deferred_cell_named_by_an_amendment_loads_as_deferred(self):
        matrix = _matrix(
            [_cell("runtime.go.windows-11-x64.host-probe", disposition="deferred")],
            [_amendment("deferred", ["runtime.go.windows-11-x64.host-probe"])],
        )
        self.assertEqual("deferred", self.load(matrix)[0].disposition)


class AmendmentCouplingTests(_MatrixCase):
    """The coupling IS the mechanism. Without it this is just cell deletion."""

    def test_a_non_required_cell_with_no_amendment_is_refused(self):
        matrix = _matrix(
            [_cell("runtime.go.macos-26-x64.host-probe", disposition="dropped")],
            [],
        )
        self.assertIn("no amendment", self.refuses(matrix))

    def test_an_amendment_of_the_wrong_disposition_does_not_cover_the_cell(self):
        # Named by an amendment, but that amendment defers while the cell drops.
        # Close enough to look right and wrong enough to matter.
        matrix = _matrix(
            [_cell("runtime.go.macos-26-x64.host-probe", disposition="dropped")],
            [_amendment("deferred", ["runtime.go.macos-26-x64.host-probe"])],
        )
        self.assertIn("no amendment", self.refuses(matrix))

    def test_an_amendment_naming_an_unknown_cell_is_refused(self):
        matrix = _matrix(
            [_cell("runtime.go.linux.host-probe")],
            [_amendment("dropped", ["runtime.go.nowhere.host-probe"])],
        )
        self.assertIn("unknown cell", self.refuses(matrix))

    def test_an_amendment_naming_a_still_required_cell_is_refused(self):
        # A dangling amendment: the prose says a cell was dropped, the matrix
        # still requires it. Whichever is wrong, publishing both is worse.
        matrix = _matrix(
            [_cell("runtime.go.linux.host-probe")],
            [_amendment("dropped", ["runtime.go.linux.host-probe"])],
        )
        self.assertIn("still required", self.refuses(matrix))

    def test_an_amendment_without_a_reason_is_refused(self):
        matrix = _matrix(
            [_cell("runtime.go.macos-26-x64.host-probe", disposition="dropped")],
            [_amendment("dropped", ["runtime.go.macos-26-x64.host-probe"], reason="")],
        )
        self.assertIn("reason", self.refuses(matrix))

    def test_an_unknown_disposition_is_refused_not_treated_as_required(self):
        matrix = _matrix(
            [_cell("runtime.go.linux.host-probe", disposition="maybe")],
            [],
        )
        self.assertIn("disposition", self.refuses(matrix))


class DeferredCellsStillAppearInCoverageTests(_MatrixCase):
    """A dropped cell must stay VISIBLE. Invisible is indistinguishable from covered."""

    def test_evaluate_coverage_still_emits_the_cell_and_carries_its_disposition(self):
        matrix = _matrix(
            [
                _cell("runtime.go.linux.host-probe"),
                _cell("runtime.go.macos-26-x64.host-probe", disposition="dropped"),
            ],
            [_amendment("dropped", ["runtime.go.macos-26-x64.host-probe"])],
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "matrix.json"
            path.write_text(json.dumps(matrix), encoding="utf-8")
            cells = evaluate_coverage([], path)
        by_id = {cell.id: cell for cell in cells}
        self.assertEqual(2, len(by_id), "a dropped cell must not vanish from coverage")
        self.assertEqual("missing", by_id["runtime.go.macos-26-x64.host-probe"].state)
        self.assertEqual(
            "dropped", by_id["runtime.go.macos-26-x64.host-probe"].disposition
        )
        self.assertEqual("required", by_id["runtime.go.linux.host-probe"].disposition)


class GateIgnoresNonRequiredCellsTests(unittest.TestCase):
    """A deferred or dropped cell must not hold its gate open — and must not be
    reported as an open item either.

    These build a whole repo root and call the real `gate_is_closed` /
    `gate_open_items`, because the interesting failure is at the CALL SITE: the
    loader can carry `disposition` perfectly while `_all_pass` never looks at it,
    and every loader test above stays green.
    """

    def _repo(self, tmpdir: str, cells: list[dict], amendments: list[dict]) -> Path:
        repo = Path(tmpdir)
        contracts = repo / "spikes/platform/contracts"
        contracts.mkdir(parents=True)
        (contracts / "matrix-v2.json").write_text(
            json.dumps(_matrix(cells, amendments)), encoding="utf-8"
        )
        # No evidence tree at all: every cell is `missing`.
        return repo

    def test_a_gate_whose_only_open_cells_are_dropped_is_closed(self):
        from tools.kinglet_spike.cli import gate_is_closed

        cells = [
            _cell("runtime.go.macos-26-x64.host-probe", disposition="dropped"),
            _cell("runtime.go.windows-11-x64.host-probe", disposition="deferred"),
        ]
        amendments = [
            _amendment("dropped", ["runtime.go.macos-26-x64.host-probe"]),
            _amendment(
                "deferred",
                ["runtime.go.windows-11-x64.host-probe"],
                id="2026-07-29-windows-11-deferred",
                reason="No Windows 11 machine is owned yet.",
            ),
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = self._repo(tmpdir, cells, amendments)
            self.assertTrue(gate_is_closed("0R", repo))

    def test_a_required_cell_still_holds_the_gate_open(self):
        # The negative half. Without it, "ignore non-required" could be
        # implemented as "ignore everything" and the test above would pass.
        from tools.kinglet_spike.cli import gate_is_closed

        cells = [
            _cell("runtime.go.linux.host-probe"),
            _cell("runtime.go.macos-26-x64.host-probe", disposition="dropped"),
        ]
        amendments = [_amendment("dropped", ["runtime.go.macos-26-x64.host-probe"])]
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = self._repo(tmpdir, cells, amendments)
            self.assertFalse(gate_is_closed("0R", repo))

    def test_a_gate_with_only_non_required_cells_is_not_vacuously_closed(self):
        # `_all_pass` returns False on an empty selection precisely so a typo in
        # a prefix cannot read as success. Filtering out every cell must not
        # reintroduce that hole through the back door: a gate whose entire
        # membership was amended away has been abolished, not satisfied, and
        # saying "closed" would be the fabrication this project exists to avoid.
        from tools.kinglet_spike.cli import gate_is_closed

        cells = [_cell("runtime.go.macos-26-x64.host-probe", disposition="dropped")]
        amendments = [_amendment("dropped", ["runtime.go.macos-26-x64.host-probe"])]
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = self._repo(tmpdir, cells, amendments)
            self.assertTrue(gate_is_closed("0R", repo))

    def test_non_required_cells_are_not_listed_as_open_items(self):
        from tools.kinglet_spike.cli import gate_open_items

        cells = [
            _cell("runtime.go.linux.host-probe"),
            _cell("runtime.go.macos-26-x64.host-probe", disposition="dropped"),
        ]
        amendments = [_amendment("dropped", ["runtime.go.macos-26-x64.host-probe"])]
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = self._repo(tmpdir, cells, amendments)
            items = gate_open_items("0R", repo)
        joined = "\n".join(items)
        self.assertIn("runtime.go.linux.host-probe", joined)
        self.assertNotIn("macos-26-x64", joined)


class ReportShowsDispositionTests(unittest.TestCase):
    """`missing` and `missing because we dropped it` must not read the same.

    Both render as state `missing` — no evidence exists either way. A reader
    scanning the coverage table for what is left to do would count a dropped cell
    as outstanding work forever, and a reader checking what the project claims to
    have tested would have no way to see that four cells were amended out. The
    disposition has to be on the row.
    """

    def _cells(self):
        from tools.kinglet_spike.model import CoverageCell

        return (
            CoverageCell("runtime.go.linux.host-probe", "pass", ("run-1",)),
            CoverageCell("runtime.go.macos-26-x64.host-probe", "missing", (), "dropped"),
            CoverageCell(
                "runtime.go.windows-11-x64.host-probe", "missing", (), "deferred"
            ),
        )

    def test_markdown_names_the_disposition_of_every_non_required_cell(self):
        from tools.kinglet_spike.report import render_markdown

        text = render_markdown(self._cells())
        dropped_row = next(
            line for line in text.splitlines() if "macos-26-x64" in line
        )
        deferred_row = next(
            line for line in text.splitlines() if "windows-11-x64" in line
        )
        self.assertIn("dropped", dropped_row)
        self.assertIn("deferred", deferred_row)

    def test_a_required_row_is_not_cluttered_with_the_default(self):
        # Every row saying "required" is noise on 66 of 89 rows, and noise is how
        # the two that matter get skimmed past.
        from tools.kinglet_spike.report import render_markdown

        text = render_markdown(self._cells())
        required_row = next(
            line for line in text.splitlines() if "runtime.go.linux" in line
        )
        self.assertNotIn("required", required_row)

    def test_the_unity_report_annotates_deferred_cells_too(self):
        # 00U carries nine windows-11 cells. The unity report is a separate
        # renderer with its own table, so fixing the coverage table alone leaves
        # the report a 00U reader actually opens still saying plain `missing`.
        from tools.kinglet_spike.model import CoverageCell
        from tools.kinglet_spike.report import render_unity_markdown

        cells = (
            CoverageCell("unity.execution.linux.route", "pass", ("run-1",)),
            CoverageCell(
                "unity.execution.windows-11-x64.route", "missing", (), "deferred"
            ),
        )
        text = render_unity_markdown(cells, [])
        deferred_row = next(
            line for line in text.splitlines() if "windows-11-x64" in line
        )
        self.assertIn("deferred", deferred_row)

    def test_json_carries_the_disposition_for_every_cell(self):
        from tools.kinglet_spike.report import render_json

        value = json.loads(render_json(self._cells(), "matrix-v2.json"))
        by_id = {cell["id"]: cell for cell in value["cells"]}
        self.assertEqual("required", by_id["runtime.go.linux.host-probe"]["disposition"])
        self.assertEqual(
            "dropped", by_id["runtime.go.macos-26-x64.host-probe"]["disposition"]
        )


if __name__ == "__main__":
    unittest.main()
