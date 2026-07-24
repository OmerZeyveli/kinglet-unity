import unittest

from tools.kinglet_spike.coverage import choose_state


class CoverageTests(unittest.TestCase):
    def test_only_valid_pass_satisfies_cell(self):
        self.assertEqual("pass", choose_state(["pass"]))
        self.assertEqual("fail", choose_state(["pass", "fail"]))
        self.assertEqual("invalid", choose_state(["pass", "invalid"]))

    def test_non_pass_states_remain_distinct(self):
        self.assertEqual("missing", choose_state([]))
        self.assertEqual("unavailable", choose_state(["unavailable"]))
        self.assertEqual("inconclusive", choose_state(["inconclusive"]))

    def test_retry_order_does_not_hide_failed_history(self):
        self.assertEqual("pass", choose_state(["fail", "pass"]))
        self.assertEqual("pass", choose_state(["inconclusive", "pass"]))
