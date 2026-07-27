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
MATRIX = REPO / "spikes/platform/contracts/matrix-v1.json"
MATRIX_NAME = "spikes/platform/contracts/matrix-v1.json"
REPORTS = REPO / "docs/research/platform-spike/reports"

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
    "client.claude-code.windows-11-x64.capability-suite",
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
    ("client.codex.linux-ubuntu-24-04-x64.local-executable", "missing"),
    ("client.codex.linux-ubuntu-24-04-x64.mcp-discovery", "missing"),
    ("client.codex.linux-ubuntu-24-04-x64.path-semantics", "missing"),
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
    ("runtime.dotnet.windows-10-x64.host-probe", "missing"),
    ("runtime.dotnet.windows-11-x64.host-probe", "missing"),
    ("runtime.go.linux-ubuntu-24-04-x64.host-probe", "pass"),
    ("runtime.go.macos-26-arm64.host-probe", "missing"),
    ("runtime.go.macos-26-x64.host-probe", "missing"),
    ("runtime.go.windows-10-x64.host-probe", "missing"),
    ("runtime.go.windows-11-x64.host-probe", "missing"),
    ("runtime.python.linux-ubuntu-24-04-x64.host-probe", "pass"),
    ("runtime.python.macos-26-arm64.host-probe", "missing"),
    ("runtime.python.macos-26-x64.host-probe", "missing"),
    ("runtime.python.windows-10-x64.host-probe", "missing"),
    ("runtime.python.windows-11-x64.host-probe", "missing"),
    ("runtime.rust.linux-ubuntu-24-04-x64.host-probe", "pass"),
    ("runtime.rust.macos-26-arm64.host-probe", "missing"),
    ("runtime.rust.macos-26-x64.host-probe", "missing"),
    ("runtime.rust.windows-10-x64.host-probe", "missing"),
    ("runtime.rust.windows-11-x64.host-probe", "missing"),
    ("unity.editor-resolution.linux-ubuntu-24-04-x64.mismatched-editor", "missing"),
    ("unity.editor-resolution.macos-26-arm64.mismatched-editor", "missing"),
    ("unity.editor-resolution.windows-11-x64.mismatched-editor", "missing"),
    ("unity.execution.linux-ubuntu-24-04-x64.cancellation", "missing"),
    ("unity.execution.linux-ubuntu-24-04-x64.orphan-cleanup", "missing"),
    ("unity.execution.macos-26-arm64.cancellation", "missing"),
    ("unity.execution.macos-26-arm64.orphan-cleanup", "missing"),
    ("unity.execution.windows-11-x64.cancellation", "missing"),
    ("unity.execution.windows-11-x64.orphan-cleanup", "missing"),
    ("unity.filesystem-only.linux-ubuntu-24-04-x64.route", "missing"),
    ("unity.filesystem-only.macos-26-arm64.route", "missing"),
    ("unity.filesystem-only.windows-11-x64.route", "missing"),
    ("unity.isolated-headless.linux-ubuntu-24-04-x64.route", "missing"),
    ("unity.isolated-headless.macos-26-arm64.route", "missing"),
    ("unity.isolated-headless.windows-11-x64.route", "missing"),
    ("unity.live-editor-mcp.linux-ubuntu-24-04-x64.bridge-not-ready", "missing"),
    ("unity.live-editor-mcp.linux-ubuntu-24-04-x64.route", "missing"),
    ("unity.live-editor-mcp.macos-26-arm64.bridge-not-ready", "missing"),
    ("unity.live-editor-mcp.macos-26-arm64.route", "missing"),
    ("unity.live-editor-mcp.windows-11-x64.bridge-not-ready", "missing"),
    ("unity.live-editor-mcp.windows-11-x64.route", "missing"),
    ("unity.same-project-headless.linux-ubuntu-24-04-x64.collision-refusal", "missing"),
    ("unity.same-project-headless.linux-ubuntu-24-04-x64.route", "missing"),
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
