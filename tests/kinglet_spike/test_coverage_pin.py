"""test_coverage_pin.py — The committed cell state is data, and it is pinned here.

Why this file exists
--------------------
Every other test in this suite is derived: it recomputes what it asserts from
the observations, the matrix, or the records. That is usually the right shape,
and it is exactly why a whole class of regression walked straight through it.

The proof: exempt `kinglet.client-probe.observations/v1` from validate.py's
"a pass must carry sources" rule. Nothing about the derivation changes, so the
entire suite stays GREEN — while `client.claude-code...path-semantics` flips
state and `gate 0C:claude-code` silently drops a cell from its open list. The
committed `coverage.json` / `coverage.md` were checked by nothing at all, so
they could also drift from reality indefinitely.

So this file asserts the two things no derived test can:

  1. PINNED_CELLS — the state of every cell in the frozen matrix, as literal
     data. Any change to which cells are open or closed, by ANY mechanism
     (a relaxed validator, an edited record, a changed PROBE_GROUPS row, a new
     matrix cell), fails here with the cell id and the transition spelled out.
  2. The committed reports are byte-identical to a fresh evaluation, so a stale
     `coverage.json` cannot outlive the evidence it claims to summarise.

Updating the pin is a deliberate act. When a cell legitimately changes state,
edit PINNED_CELLS in the same commit as the evidence that moved it, and the diff
shows a reviewer precisely which cell opened or closed and why.
"""
from __future__ import annotations

import unittest
from pathlib import Path

from tools.kinglet_spike.cli import gate_is_closed, gate_open_items
from tools.kinglet_spike.coverage import evaluate_coverage
from tools.kinglet_spike.report import (
    load_published_records,
    render_json,
    render_markdown,
)

REPO = Path(__file__).resolve().parents[2]
MATRIX = REPO / "spikes/platform/contracts/matrix-v2.json"
MATRIX_NAME = "spikes/platform/contracts/matrix-v2.json"
REPORTS = REPO / "docs/research/platform-spike/reports"


# Every cell that is NOT `required`, pinned as literal data.
#
# This is the pin that matters most in this file. A cell state changes because
# evidence changed -- visible, reviewable. A DISPOSITION changes because someone
# edited the matrix, and the effect is that a gate stops waiting for a host:
# `gate 0R` gets quieter and closer to closing without one new observation. The
# amendment mechanism forces a written reason into the matrix; this forces the
# consequence into a diff a reviewer reads.
#
# The complement is asserted too, so ADDING a deferred cell fails here just as
# loudly as removing one.
PINNED_NON_REQUIRED: tuple[tuple[str, str], ...] = (
    ("client.antigravity.windows-11-x64.capability-suite", "deferred"),
    ("client.claude-code.windows-11-x64.capability-suite", "deferred"),
    ("client.codex.windows-11-x64.capability-suite", "deferred"),
    ("client.copilot-cli.windows-11-x64.capability-suite", "deferred"),
    ("client.copilot-vscode.windows-11-x64.capability-suite", "deferred"),
    ("client.cursor.windows-11-x64.capability-suite", "deferred"),
    ("runtime.dotnet.macos-26-x64.host-probe", "dropped"),
    ("runtime.dotnet.windows-11-x64.host-probe", "deferred"),
    ("runtime.go.macos-26-x64.host-probe", "dropped"),
    ("runtime.go.windows-11-x64.host-probe", "deferred"),
    ("runtime.python.macos-26-x64.host-probe", "dropped"),
    ("runtime.python.windows-11-x64.host-probe", "deferred"),
    ("runtime.rust.macos-26-x64.host-probe", "dropped"),
    ("runtime.rust.windows-11-x64.host-probe", "deferred"),
    ("unity.editor-resolution.windows-11-x64.mismatched-editor", "deferred"),
    ("unity.execution.windows-11-x64.cancellation", "deferred"),
    ("unity.execution.windows-11-x64.orphan-cleanup", "deferred"),
    ("unity.filesystem-only.windows-11-x64.route", "deferred"),
    ("unity.isolated-headless.windows-11-x64.route", "deferred"),
    ("unity.live-editor-mcp.windows-11-x64.bridge-not-ready", "deferred"),
    ("unity.live-editor-mcp.windows-11-x64.route", "deferred"),
    ("unity.same-project-headless.windows-11-x64.collision-refusal", "deferred"),
    ("unity.same-project-headless.windows-11-x64.route", "deferred"),
)

# A cell is "closed" only in state `pass`; every other state leaves it open.
CLOSED_STATE = "pass"

# The gate whose open list the reviewer's mutation silently shortened.
PINNED_GATE = "0C:claude-code"
PINNED_GATE_IS_CLOSED = False
PINNED_GATE_OPEN_CELLS = (
    "client.claude-code.linux-ubuntu-24-04-x64.local-executable",
    "client.claude-code.linux-ubuntu-24-04-x64.mcp-discovery",
    "client.claude-code.macos-26-arm64.local-executable",
    "client.claude-code.macos-26-arm64.mcp-discovery",
    "client.claude-code.macos-26-arm64.path-semantics",
    # windows-11-x64.capability-suite is DEFERRED as of the 2026-07-29 amendment,
    # so it no longer holds this gate open and no longer appears here. It is still
    # in the coverage report, annotated, which is where "not covered" is recorded.
)

# The state of every matrix cell as committed. Literal on purpose.
PINNED_CELLS: tuple[tuple[str, str], ...] = (
    ("client.antigravity.linux-ubuntu-24-04-x64.local-executable", "missing"),
    ("client.antigravity.linux-ubuntu-24-04-x64.mcp-discovery", "missing"),
    ("client.antigravity.linux-ubuntu-24-04-x64.path-semantics", "missing"),
    ("client.antigravity.macos-26-arm64.local-executable", "missing"),
    ("client.antigravity.macos-26-arm64.mcp-discovery", "missing"),
    ("client.antigravity.macos-26-arm64.path-semantics", "missing"),
    ("client.antigravity.windows-11-x64.capability-suite", "missing"),
    ("client.claude-code.linux-ubuntu-24-04-x64.local-executable", "fail"),
    ("client.claude-code.linux-ubuntu-24-04-x64.mcp-discovery", "fail"),
    ("client.claude-code.linux-ubuntu-24-04-x64.path-semantics", "pass"),
    ("client.claude-code.macos-26-arm64.local-executable", "missing"),
    ("client.claude-code.macos-26-arm64.mcp-discovery", "missing"),
    ("client.claude-code.macos-26-arm64.path-semantics", "missing"),
    ("client.claude-code.windows-11-x64.capability-suite", "missing"),
    ("client.codex.linux-ubuntu-24-04-x64.local-executable", "pass"),
    ("client.codex.linux-ubuntu-24-04-x64.mcp-discovery", "fail"),
    ("client.codex.linux-ubuntu-24-04-x64.path-semantics", "fail"),
    ("client.codex.macos-26-arm64.local-executable", "missing"),
    ("client.codex.macos-26-arm64.mcp-discovery", "missing"),
    ("client.codex.macos-26-arm64.path-semantics", "missing"),
    ("client.codex.windows-11-x64.capability-suite", "missing"),
    ("client.copilot-cli.linux-ubuntu-24-04-x64.local-executable", "missing"),
    ("client.copilot-cli.linux-ubuntu-24-04-x64.mcp-discovery", "missing"),
    ("client.copilot-cli.linux-ubuntu-24-04-x64.path-semantics", "missing"),
    ("client.copilot-cli.macos-26-arm64.local-executable", "missing"),
    ("client.copilot-cli.macos-26-arm64.mcp-discovery", "missing"),
    ("client.copilot-cli.macos-26-arm64.path-semantics", "missing"),
    ("client.copilot-cli.windows-11-x64.capability-suite", "missing"),
    ("client.copilot-vscode.linux-ubuntu-24-04-x64.local-executable", "missing"),
    ("client.copilot-vscode.linux-ubuntu-24-04-x64.mcp-discovery", "missing"),
    ("client.copilot-vscode.linux-ubuntu-24-04-x64.path-semantics", "missing"),
    ("client.copilot-vscode.macos-26-arm64.local-executable", "missing"),
    ("client.copilot-vscode.macos-26-arm64.mcp-discovery", "missing"),
    ("client.copilot-vscode.macos-26-arm64.path-semantics", "missing"),
    ("client.copilot-vscode.windows-11-x64.capability-suite", "missing"),
    ("client.cursor.linux-ubuntu-24-04-x64.local-executable", "missing"),
    ("client.cursor.linux-ubuntu-24-04-x64.mcp-discovery", "missing"),
    ("client.cursor.linux-ubuntu-24-04-x64.path-semantics", "missing"),
    ("client.cursor.macos-26-arm64.local-executable", "missing"),
    ("client.cursor.macos-26-arm64.mcp-discovery", "missing"),
    ("client.cursor.macos-26-arm64.path-semantics", "missing"),
    ("client.cursor.windows-11-x64.capability-suite", "missing"),
    ("runtime.dotnet.linux-ubuntu-24-04-x64.host-probe", "pass"),
    ("runtime.dotnet.macos-26-arm64.host-probe", "missing"),
    ("runtime.dotnet.macos-26-x64.host-probe", "missing"),
    # Windows 10 22H2 x64 native pass, run 20260728T170051Z. See
    # docs/research/platform-spike/HOST-PASS-HANDOFF.md §9.
    ("runtime.dotnet.windows-10-x64.host-probe", "pass"),
    ("runtime.dotnet.windows-11-x64.host-probe", "missing"),
    ("runtime.go.linux-ubuntu-24-04-x64.host-probe", "pass"),
    ("runtime.go.macos-26-arm64.host-probe", "missing"),
    ("runtime.go.macos-26-x64.host-probe", "missing"),
    ("runtime.go.windows-10-x64.host-probe", "pass"),
    ("runtime.go.windows-11-x64.host-probe", "missing"),
    ("runtime.python.linux-ubuntu-24-04-x64.host-probe", "pass"),
    ("runtime.python.macos-26-arm64.host-probe", "missing"),
    ("runtime.python.macos-26-x64.host-probe", "missing"),
    # FAIL, deliberately pinned as such: the probe uses POSIX-only os.killpg, so
    # three process assertions cannot pass on Windows. A probe omission, not a
    # Python limitation — see HOST-PASS-HANDOFF.md §9 before reading anything
    # into it. Flipping this to "pass" requires a Windows process-tree
    # implementation and a rerun, never a rubric edit.
    ("runtime.python.windows-10-x64.host-probe", "fail"),
    ("runtime.python.windows-11-x64.host-probe", "missing"),
    ("runtime.rust.linux-ubuntu-24-04-x64.host-probe", "pass"),
    ("runtime.rust.macos-26-arm64.host-probe", "missing"),
    ("runtime.rust.macos-26-x64.host-probe", "missing"),
    ("runtime.rust.windows-10-x64.host-probe", "pass"),
    ("runtime.rust.windows-11-x64.host-probe", "missing"),
    ("unity.editor-resolution.linux-ubuntu-24-04-x64.mismatched-editor", "pass"),
    ("unity.editor-resolution.macos-26-arm64.mismatched-editor", "missing"),
    ("unity.editor-resolution.windows-11-x64.mismatched-editor", "missing"),
    ("unity.execution.linux-ubuntu-24-04-x64.cancellation", "pass"),
    ("unity.execution.linux-ubuntu-24-04-x64.orphan-cleanup", "pass"),
    ("unity.execution.macos-26-arm64.cancellation", "missing"),
    ("unity.execution.macos-26-arm64.orphan-cleanup", "missing"),
    ("unity.execution.windows-11-x64.cancellation", "missing"),
    ("unity.execution.windows-11-x64.orphan-cleanup", "missing"),
    ("unity.filesystem-only.linux-ubuntu-24-04-x64.route", "pass"),
    ("unity.filesystem-only.macos-26-arm64.route", "missing"),
    ("unity.filesystem-only.windows-11-x64.route", "missing"),
    ("unity.isolated-headless.linux-ubuntu-24-04-x64.route", "pass"),
    ("unity.isolated-headless.macos-26-arm64.route", "missing"),
    ("unity.isolated-headless.windows-11-x64.route", "missing"),
    ("unity.live-editor-mcp.linux-ubuntu-24-04-x64.bridge-not-ready", "pass"),
    ("unity.live-editor-mcp.linux-ubuntu-24-04-x64.route", "inconclusive"),
    ("unity.live-editor-mcp.macos-26-arm64.bridge-not-ready", "missing"),
    ("unity.live-editor-mcp.macos-26-arm64.route", "missing"),
    ("unity.live-editor-mcp.windows-11-x64.bridge-not-ready", "missing"),
    ("unity.live-editor-mcp.windows-11-x64.route", "missing"),
    ("unity.same-project-headless.linux-ubuntu-24-04-x64.collision-refusal", "pass"),
    ("unity.same-project-headless.linux-ubuntu-24-04-x64.route", "pass"),
    ("unity.same-project-headless.macos-26-arm64.collision-refusal", "missing"),
    ("unity.same-project-headless.macos-26-arm64.route", "missing"),
    ("unity.same-project-headless.windows-11-x64.collision-refusal", "missing"),
    ("unity.same-project-headless.windows-11-x64.route", "missing"),
)


def _fresh_cells():
    return evaluate_coverage(load_published_records(REPO), MATRIX)


class CoveragePinTests(unittest.TestCase):
    def setUp(self):
        self.cells = _fresh_cells()
        self.evaluated = {cell.id: cell.state for cell in self.cells}
        self.pinned = dict(PINNED_CELLS)
        self.assertEqual(
            len(PINNED_CELLS),
            len(self.pinned),
            "PINNED_CELLS lists a cell id twice",
        )

    def test_the_pin_covers_exactly_the_matrix(self):
        self.assertEqual(
            sorted(set(self.evaluated) - set(self.pinned)),
            [],
            "the matrix defines cells this pin does not name, so their state "
            "could change unobserved",
        )
        self.assertEqual(
            sorted(set(self.pinned) - set(self.evaluated)),
            [],
            "the pin names cells the matrix no longer defines",
        )

    def test_no_cell_changed_state(self):
        shared = sorted(set(self.pinned) & set(self.evaluated))
        transitions = [
            f"{cell_id}: pinned {self.pinned[cell_id]!r}, "
            f"evaluated {self.evaluated[cell_id]!r}"
            for cell_id in shared
            if self.pinned[cell_id] != self.evaluated[cell_id]
        ]
        self.assertEqual(
            [],
            transitions,
            "a coverage cell changed state without the pin being updated; if "
            "this is intentional, edit PINNED_CELLS in the same commit as the "
            "evidence that moved it:\n  " + "\n  ".join(transitions),
        )

    def test_no_cell_silently_opened_or_closed(self):
        # Narrower and louder than the state pin: this is the transition that
        # decides whether a gate passes, so it is named on its own.
        flips = []
        for cell_id in sorted(set(self.pinned) & set(self.evaluated)):
            was_closed = self.pinned[cell_id] == CLOSED_STATE
            is_closed = self.evaluated[cell_id] == CLOSED_STATE
            if was_closed != is_closed:
                direction = "closed -> open" if was_closed else "open -> closed"
                flips.append(f"{cell_id}: {direction}")
        self.assertEqual([], flips, "cells changed open/closed state: " + "; ".join(flips))

    def test_committed_coverage_json_matches_a_fresh_evaluation(self):
        self.assertEqual(
            render_json(self.cells, MATRIX_NAME),
            (REPORTS / "coverage.json").read_text(encoding="utf-8"),
            "coverage.json has drifted from the evidence on disk; re-run "
            "`python3 -m tools.kinglet_spike report --matrix "
            f"{MATRIX_NAME}`",
        )

    def test_committed_coverage_md_matches_a_fresh_evaluation(self):
        self.assertEqual(
            render_markdown(self.cells),
            (REPORTS / "coverage.md").read_text(encoding="utf-8"),
            "coverage.md has drifted from the evidence on disk; re-run "
            "`python3 -m tools.kinglet_spike report --matrix "
            f"{MATRIX_NAME}`",
        )

class DispositionPinTests(unittest.TestCase):
    """Which cells stopped being required, pinned.

    A silent flip to `deferred` is the one change that makes a gate look better
    without any new evidence, and every other test in the suite recomputes from
    the matrix, so all of them would stay green.
    """

    def setUp(self):
        self.cells = evaluate_coverage(load_published_records(REPO), MATRIX)

    def test_the_non_required_cells_are_exactly_the_pinned_set(self):
        actual = tuple(
            sorted(
                (cell.id, cell.disposition)
                for cell in self.cells
                if cell.disposition != "required"
            )
        )
        self.assertEqual(
            PINNED_NON_REQUIRED,
            actual,
            "the set of cells excused from their gate changed; gained "
            f"{sorted(set(actual) - set(PINNED_NON_REQUIRED))}, lost "
            f"{sorted(set(PINNED_NON_REQUIRED) - set(actual))}",
        )

    def test_every_other_cell_is_still_required(self):
        excused = {cell_id for cell_id, _ in PINNED_NON_REQUIRED}
        for cell in self.cells:
            if cell.id not in excused:
                self.assertEqual(
                    "required", cell.disposition, f"{cell.id} was quietly excused"
                )


class GateOpenItemPinTests(unittest.TestCase):
    """The gate's own answer, pinned — not just the cells it reads.

    gate_is_closed and gate_open_items each re-derive from coverage, so a cell
    quietly closing shortens the open list with no test noticing. Pinning the
    list makes the disappearance itself the failure.
    """

    def test_gate_closure_is_pinned(self):
        self.assertEqual(
            PINNED_GATE_IS_CLOSED,
            gate_is_closed(PINNED_GATE, REPO),
            f"gate {PINNED_GATE} changed closure state",
        )

    def test_gate_open_cells_are_pinned(self):
        reported = tuple(
            line.split()[1] for line in gate_open_items(PINNED_GATE, REPO)
        )
        self.assertEqual(
            PINNED_GATE_OPEN_CELLS,
            reported,
            f"gate {PINNED_GATE} no longer reports the same open cells; "
            f"gained {sorted(set(reported) - set(PINNED_GATE_OPEN_CELLS))}, "
            f"lost {sorted(set(PINNED_GATE_OPEN_CELLS) - set(reported))}",
        )


if __name__ == "__main__":
    unittest.main()
