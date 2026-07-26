"""Tests for the frozen runtime-selection rubric and scoring logic (Task 6).

These tests are written BEFORE any candidate results exist, which is the whole
point: the rubric and tie-break threshold are locked against gaming.
"""
from pathlib import Path
import unittest

from tools.kinglet_spike.runtime_contract import (
    load_rubric,
    requires_tie_review,
    score_candidate,
)


class RuntimeRubricTests(unittest.TestCase):
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
