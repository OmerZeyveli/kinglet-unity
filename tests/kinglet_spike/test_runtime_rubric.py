"""Tests for the frozen runtime-selection rubric and scoring logic (Task 6).

These tests are written BEFORE any candidate results exist, which is the whole
point: the rubric and tie-break threshold are locked against gaming.
"""
from pathlib import Path
import unittest

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.runtime_contract import (
    load_rubric,
    requires_tie_review,
    score_candidate,
)

# The nine rubric hard-gate IDs — must match rubric-v1.json exactly.
_ALL_NINE_GATES: dict[str, bool] = {
    "no-user-runtime-required": True,
    "host-probe-all-cases-all-hosts": True,
    "long-running-process-management": True,
    "no-orphans-after-any-exit": True,
    "reproducible-signed-artifact": True,
    "license-compatible-and-recorded": True,
    "no-secrets-no-absolute-paths": True,
    "windows-native": True,
    "no-blocking-platform-limitation": True,
}


class RuntimeRubricTests(unittest.TestCase):
    # --- Frozen tests (must not change) ---

    def test_weights_total_one_hundred(self):
        rubric = load_rubric(Path("spikes/platform/runtime/rubric-v1.json"))
        self.assertEqual(100, sum(rubric.weights.values()))

    def test_failed_hard_gate_is_not_scored(self):
        gates = {"windows-native": False}
        result = score_candidate(gates, {})
        self.assertEqual("disqualified", result.state)

    def test_three_points_or_less_requires_tie_review(self):
        self.assertTrue(requires_tie_review(88, 85))
        self.assertFalse(requires_tie_review(88, 84))

    # --- FIX 1: open/missing gate enforcement ---

    def test_all_nine_gates_true_returns_scored(self):
        """All nine rubric gates present and True → state='scored'."""
        result = score_candidate(_ALL_NINE_GATES, {})
        self.assertEqual("scored", result.state)

    def test_subset_of_gates_all_true_returns_disqualified(self):
        """Only some gates present (rest missing) → disqualified even if present ones are True."""
        partial = {"windows-native": True, "no-user-runtime-required": True}
        result = score_candidate(partial, {})
        self.assertEqual("disqualified", result.state)
        # The missing gates should appear in failed_gates
        self.assertIn("host-probe-all-cases-all-hosts", result.failed_gates)

    def test_empty_gates_returns_disqualified(self):
        """No gates supplied → all are open → disqualified."""
        result = score_candidate({}, {})
        self.assertEqual("disqualified", result.state)
        self.assertEqual(9, len(result.failed_gates))

    # --- FIX 2: strict rubric load ---

    def test_scoring_with_valid_rubric_computes_nonzero_total(self):
        """Weighted total is derived from rubric weights, not silently zero."""
        category_scores = {
            "process-and-filesystem-reliability": 4,
            "cross-platform-packaging-and-lifecycle": 3,
            "testability-and-maintainability": 5,
            "supply-chain-and-security": 4,
            "existing-python-foundation-reuse-or-migration-cost": 3,
            "startup-time-memory-and-artifact-size": 4,
        }
        result = score_candidate(_ALL_NINE_GATES, category_scores)
        self.assertEqual("scored", result.state)
        # With all weights applied to non-zero bands the total must be > 0.
        self.assertGreater(result.weighted_total, 0)

    def test_rubric_load_failure_raises_evidence_error(self):
        """load_rubric raises EvidenceError (not returns None) for a missing file."""
        with self.assertRaises(EvidenceError):
            load_rubric(Path("spikes/platform/runtime/nonexistent-rubric.json"))

    # --- FIX 3: requires_tie_review symmetry and abs() ---

    def test_requires_tie_review_is_symmetric(self):
        """(70,80) and (80,70) must produce the same result."""
        self.assertEqual(requires_tie_review(70, 80), requires_tie_review(80, 70))

    def test_ten_point_gap_is_not_a_tie(self):
        """A 10-point gap (abs) must return False regardless of argument order."""
        self.assertFalse(requires_tie_review(70, 80))
        self.assertFalse(requires_tie_review(80, 70))
