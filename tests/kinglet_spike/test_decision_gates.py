"""00D Task 1 — the downstream gate semantics, frozen and tested.

What this exists to prevent: work unlocking on prose. Every downstream spec in
the platform plan is supposed to be released by a NAMED prerequisite, and the
only way that survives contact with a long project is if the prerequisite is
machine-readable and something refuses to evaluate it loosely.

Three properties are load-bearing and each has a test that fails when it is lost:

* **An open client gate must not block 0D.** 0C is deliberately not the door to
  product work; four of the six clients have never been probed and are expected
  to stay open for a long time. If they blocked 0D the project would be gated on
  work it decided not to do.
* **0R and 0U must block 0D.** They are the whole point of the spike.
* **A passing coverage cell is not a runtime decision.** 0R closes only when the
  ADR is `accepted`; a generated score, or an ADR still `proposed`, is not
  approval. This is the one place where measured evidence is deliberately
  insufficient on its own.

The evaluators are pure: they take mappings and return values, and read no file.
A rules file that the evaluator loads at call time is a rules file that can be
edited to unlock work without a diff anyone reviews.
"""
from __future__ import annotations

import json
import unittest
from pathlib import Path

from tools.kinglet_spike.decision import (
    CLOSE_0D_ALLOW_OPEN_PREFIXES,
    CLOSE_0D_REQUIRED,
    GATE_IDS,
    UNLOCK_RULES,
    can_close_0d,
    evaluate_unlocks,
    gate_status,
    runtime_gate_state,
)

REPO = Path(__file__).resolve().parents[2]
RULES_FILE = REPO / "spikes/platform/decision/gate-rules-v1.json"


def closed_required_gates() -> dict[str, str]:
    """Every gate 0D needs, closed; the four unprobed clients inconclusive."""
    return {
        "0A": "closed",
        "0R": "closed",
        "0C:claude-code": "closed",
        "0C:codex": "closed",
        "0C:cursor": "inconclusive",
        "0C:copilot-cli": "inconclusive",
        "0C:copilot-vscode": "inconclusive",
        "0C:antigravity": "inconclusive",
        "0U": "closed",
        "0D": "open",
    }


class DecisionGateTests(unittest.TestCase):
    def test_open_client_does_not_block_0d(self):
        gates = closed_required_gates()
        gates["0C:antigravity"] = "inconclusive"
        self.assertTrue(can_close_0d(gates))
        self.assertFalse(evaluate_unlocks(gates)["adapter:antigravity-spec"])

    def test_runtime_or_unity_blocks_0d(self):
        for gate in ("0R", "0U"):
            gates = closed_required_gates()
            gates[gate] = "open"
            with self.subTest(gate=gate):
                self.assertFalse(can_close_0d(gates))

    def test_the_harness_gate_blocks_0d_too(self):
        # 0A is in the prerequisite list and is easy to drop when writing the
        # "0R and 0U" rule from memory.
        gates = closed_required_gates()
        gates["0A"] = "open"
        self.assertFalse(can_close_0d(gates))

    def test_a_gate_missing_from_the_mapping_does_not_count_as_closed(self):
        gates = closed_required_gates()
        del gates["0U"]
        self.assertFalse(can_close_0d(gates))

    def test_runtime_requires_approved_adr(self):
        self.assertEqual("open", runtime_gate_state("pass", "proposed"))

    def test_runtime_closes_only_on_pass_plus_accepted(self):
        self.assertEqual("closed", runtime_gate_state("pass", "accepted"))
        # Evidence without approval, and approval without evidence, are both open.
        self.assertEqual("open", runtime_gate_state("fail", "accepted"))
        self.assertEqual("open", runtime_gate_state("missing", "accepted"))
        self.assertEqual("open", runtime_gate_state("pass", "rejected"))


class UnlockTests(unittest.TestCase):
    def test_each_client_unlock_depends_only_on_its_own_gate(self):
        # Cross-wiring here would make one probed client release another's
        # adapter spec, which is precisely the claim 0C exists to make per client.
        for client in ("claude-code", "codex", "cursor"):
            gates = closed_required_gates()
            for other in ("claude-code", "codex", "cursor", "copilot-cli",
                          "copilot-vscode", "antigravity"):
                gates[f"0C:{other}"] = "open"
            gates[f"0C:{client}"] = "closed"
            unlocks = evaluate_unlocks(gates)
            with self.subTest(client=client):
                self.assertTrue(unlocks[f"adapter:{client}-spec"])
                for other in ("claude-code", "codex", "cursor"):
                    if other != client:
                        self.assertFalse(unlocks[f"adapter:{other}-spec"])

    def test_canonical_foundation_follows_runtime_alone(self):
        gates = closed_required_gates()
        gates["0U"] = "open"
        self.assertTrue(evaluate_unlocks(gates)["canonical-foundation-spec"])
        gates["0R"] = "open"
        self.assertFalse(evaluate_unlocks(gates)["canonical-foundation-spec"])

    def test_unity_execution_spec_follows_unity_alone(self):
        gates = closed_required_gates()
        gates["0R"] = "open"
        self.assertTrue(evaluate_unlocks(gates)["unity-execution-spec"])
        gates["0U"] = "open"
        self.assertFalse(evaluate_unlocks(gates)["unity-execution-spec"])

    def test_windows_slice_has_four_independent_inputs(self):
        gates = closed_required_gates()
        gates["0C:codex"] = "open"
        unlocks = evaluate_unlocks(gates, windows_cells_passed=True)
        self.assertFalse(unlocks["windows-reference-slice"])

    def test_windows_slice_needs_named_windows_evidence_not_a_global_unity_pass(self):
        # 0U closed means the matrix's REQUIRED unity cells passed. After the
        # 2026-07-29 amendment every windows-11 unity cell is deferred, so 0U can
        # close with no Windows Unity evidence at all. The slice must not read a
        # global 0U pass as Windows coverage.
        gates = closed_required_gates()
        self.assertFalse(
            evaluate_unlocks(gates, windows_cells_passed=False)[
                "windows-reference-slice"
            ]
        )
        self.assertTrue(
            evaluate_unlocks(gates, windows_cells_passed=True)[
                "windows-reference-slice"
            ]
        )

    def test_platform_plan_rewrite_follows_0d(self):
        gates = closed_required_gates()
        self.assertFalse(evaluate_unlocks(gates)["platform-plan-rewrite"])
        gates["0D"] = "closed"
        self.assertTrue(evaluate_unlocks(gates)["platform-plan-rewrite"])

    def test_every_declared_unlock_is_answered(self):
        # A target that silently vanishes from the result is a target nothing
        # gates any more, and a KeyError at the call site is a better outcome
        # than a missing key read as False.
        unlocks = evaluate_unlocks(closed_required_gates())
        self.assertEqual(set(UNLOCK_RULES), set(unlocks))

    def test_the_result_is_immutable(self):
        unlocks = evaluate_unlocks(closed_required_gates())
        with self.assertRaises(TypeError):
            unlocks["platform-plan-rewrite"] = True


class GateStatusTests(unittest.TestCase):
    def test_an_absent_gate_is_open_because_it_is_missing(self):
        state, reason = gate_status({}, "0R")
        self.assertEqual("open", state)
        self.assertEqual("missing", reason)

    def test_an_unknown_gate_id_is_refused_rather_than_reported_open(self):
        # "open" for a typo'd gate id is a silent lie: it reads as a real gate
        # that has not been reached, and nobody ever reaches it.
        with self.assertRaises(KeyError):
            gate_status(closed_required_gates(), "0Z")

    def test_a_known_closed_gate_reports_closed(self):
        state, reason = gate_status(closed_required_gates(), "0R")
        self.assertEqual("closed", state)
        self.assertEqual("", reason)


class CommittedRulesMatchTheCodeTests(unittest.TestCase):
    """The JSON is the contract; the module is the implementation. Both, or drift.

    Keeping the rules only in Python means nothing downstream can read them;
    keeping them only in JSON means the evaluator parses a file at call time,
    which is the "edit the file, unlock the work" hole. So they are kept in both
    and pinned to each other here.
    """

    def setUp(self):
        self.rules = json.loads(RULES_FILE.read_text(encoding="utf-8"))

    def test_schema_is_the_frozen_one(self):
        self.assertEqual("kinglet.spike.gate-rules/v1", self.rules["schema"])

    def test_the_file_lists_exactly_the_ten_gate_ids(self):
        self.assertEqual(list(GATE_IDS), self.rules["gates"])
        self.assertEqual(10, len(GATE_IDS))

    def test_the_file_declares_the_same_unlocks_as_the_module(self):
        self.assertEqual(
            {
                target: dict(rule)
                for target, rule in sorted(UNLOCK_RULES.items())
            },
            self.rules["unlocks"],
        )

    def test_the_file_declares_the_same_0d_rule_as_the_module(self):
        # Two assertions, and both are needed. The literal pins the FILE, so
        # regenerating it after a module edit fails here. The module comparison
        # pins the DRIFT, so editing the module and not regenerating fails here
        # too. Checking only the literal — which is what this test did first —
        # names the module in its title and never reads it.
        self.assertEqual(
            {
                "all": list(CLOSE_0D_REQUIRED),
                "allowOpenPrefixes": list(CLOSE_0D_ALLOW_OPEN_PREFIXES),
            },
            self.rules["close0D"],
        )
        self.assertEqual(
            {"all": ["0A", "0R", "0U"], "allowOpenPrefixes": ["0C:"]},
            self.rules["close0D"],
        )


if __name__ == "__main__":
    unittest.main()
