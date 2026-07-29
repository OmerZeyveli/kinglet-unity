"""00D — downstream gate semantics.

What releases work, stated once and evaluated the same way everywhere.

The evaluators here are **pure**: they take mappings and return values, and they
read no file. That is deliberate. An evaluator that loads its rules at call time
can be unlocked by editing a file, and the edit looks like configuration rather
than like changing what the project claims to have proved. The rules live in
`spikes/platform/decision/gate-rules-v1.json` so downstream tooling can read
them, and `test_decision_gates.py` pins the file and this module to each other so
neither can drift.

Two asymmetries are the point of the whole module:

* **An open client gate does not block 0D.** Four of six clients have never been
  probed and are expected to stay open for a long time; 0C is not the door to
  product work. What an open client gate DOES block is that client's own adapter
  spec, and nothing else.
* **A passing coverage cell does not close 0R.** The runtime gate additionally
  requires the ADR to be `accepted`. A generated score is not approval — it is
  the one place in this project where measured evidence is deliberately not
  sufficient on its own.
"""
from __future__ import annotations

from types import MappingProxyType
from typing import Mapping

CLIENTS = (
    "claude-code",
    "codex",
    "cursor",
    "copilot-cli",
    "copilot-vscode",
    "antigravity",
)

# Order is part of the contract: gate-rules-v1.json lists these in this order and
# a test compares the two sequences, not their sets.
GATE_IDS = (
    "0A",
    "0R",
    *(f"0C:{client}" for client in CLIENTS),
    "0U",
    "0D",
)

CLOSED = "closed"

# What each downstream target waits on. `windowsCellsPassed` is a SEPARATE input
# rather than a gate because 0U closing says the matrix's required unity cells
# passed — and after the 2026-07-29 amendment every windows-11 unity cell is
# deferred, so 0U can close with no Windows Unity evidence whatsoever. Reading a
# global 0U pass as Windows coverage would unlock a Windows reference slice on
# Linux and macOS observations.
UNLOCK_RULES: Mapping[str, Mapping[str, object]] = MappingProxyType(
    {
        "canonical-foundation-spec": MappingProxyType({"gates": ["0R"]}),
        **{
            f"adapter:{client}-spec": MappingProxyType(
                {"gates": [f"0C:{client}"]}
            )
            for client in CLIENTS
        },
        "unity-execution-spec": MappingProxyType({"gates": ["0U"]}),
        "windows-reference-slice": MappingProxyType(
            {
                "gates": ["0R", "0C:claude-code", "0C:codex"],
                "windowsCellsPassed": True,
            }
        ),
        "platform-plan-rewrite": MappingProxyType({"gates": ["0D"]}),
    }
)

# 0D closes on the harness, the runtime and the Unity evidence. Client gates may
# be open; nothing else may.
CLOSE_0D_REQUIRED = ("0A", "0R", "0U")
CLOSE_0D_ALLOW_OPEN_PREFIXES = ("0C:",)


def runtime_gate_state(coverage_state: str, adr_status: str) -> str:
    """0R's state from its coverage state and the runtime ADR's status.

    Both are required. Evidence without an accepted decision is an unmade
    decision, and an accepted ADR without passing evidence is a decision resting
    on nothing — each is `open`, and for opposite reasons.
    """
    if coverage_state == "pass" and adr_status == "accepted":
        return CLOSED
    return "open"


def gate_status(gates: Mapping[str, str], gate_id: str) -> tuple[str, str]:
    """(state, reason) for one gate.

    An id that is not a gate raises rather than reporting `open`. "Open" for a
    typo reads as a real gate nobody has reached yet, and nobody ever reaches it.
    """
    if gate_id not in GATE_IDS:
        raise KeyError(f"unknown gate id: {gate_id!r}")
    state = gates.get(gate_id)
    if state is None:
        # Absent is not closed. A caller that forgot to evaluate a gate must not
        # be handed the permissive answer.
        return ("open", "missing")
    if state == CLOSED:
        return (CLOSED, "")
    return ("open", state)


def _is_closed(gates: Mapping[str, str], gate_id: str) -> bool:
    return gate_status(gates, gate_id)[0] == CLOSED


def can_close_0d(gates: Mapping[str, str]) -> bool:
    """May 0D close, given the state of every other gate?"""
    if not all(_is_closed(gates, gate_id) for gate_id in CLOSE_0D_REQUIRED):
        return False
    # Stated as a rule rather than as "ignore everything else": a gate added
    # later that is neither required nor an allowed-open client would otherwise
    # be silently exempt from a check nobody remembered to extend.
    for gate_id in GATE_IDS:
        if gate_id in CLOSE_0D_REQUIRED or gate_id == "0D":
            continue
        if _is_closed(gates, gate_id):
            continue
        if not gate_id.startswith(CLOSE_0D_ALLOW_OPEN_PREFIXES):
            return False
    return True


def evaluate_unlocks(
    gates: Mapping[str, str], windows_cells_passed: bool = False
) -> Mapping[str, bool]:
    """Which downstream targets are released, keyed by target, in sorted order.

    The result answers EVERY declared target. A target that dropped out of the
    result would be read as False by a caller using `.get`, which is a target
    nothing gates any more wearing the appearance of one that is still waiting.
    """
    answers: dict[str, bool] = {}
    for target in sorted(UNLOCK_RULES):
        rule = UNLOCK_RULES[target]
        released = all(
            _is_closed(gates, gate_id) for gate_id in rule["gates"]
        )
        if rule.get("windowsCellsPassed") and not windows_cells_passed:
            released = False
        answers[target] = released
    return MappingProxyType(answers)
