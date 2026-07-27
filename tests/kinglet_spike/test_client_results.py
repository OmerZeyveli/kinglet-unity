"""test_client_results.py — Behavioral contract tests for client probe validation.

Tests the three core invariants of validate_client_observations:
  1. Native/pass requires at least one live artifact (E_ASSERTION).
  2. inconclusive status may not carry a grade (E_ENUM).
  3. All 12 case IDs must appear exactly once (E_COVERAGE).
"""
import unittest

from tools.kinglet_spike.client_results import validate_client_observations
from tools.kinglet_spike.model import EvidenceError
from tests.kinglet_spike.client_support import CASES, valid_observations


class ClientResultTests(unittest.TestCase):
    def test_native_pass_requires_live_artifact(self):
        value = valid_observations()
        value["cases"][0].update({"grade": "Native", "status": "pass", "artifact_paths": []})
        with self.assertRaisesRegex(EvidenceError, "E_ASSERTION"):
            validate_client_observations(value, CASES)

    def test_inconclusive_cannot_be_promoted(self):
        value = valid_observations()
        value["cases"][0].update({"grade": "Native", "status": "inconclusive"})
        with self.assertRaisesRegex(EvidenceError, "E_ENUM"):
            validate_client_observations(value, CASES)

    def test_all_case_ids_are_required_once(self):
        value = valid_observations()
        value["cases"].pop()
        with self.assertRaisesRegex(EvidenceError, "E_COVERAGE"):
            validate_client_observations(value, CASES)
