"""test_client_results.py — Behavioral contract tests for client probe validation.

Tests the three core invariants of validate_client_observations:
  1. Native/pass requires at least one live artifact (E_ASSERTION).
  2. inconclusive status may not carry a grade (E_ENUM).
  3. All 12 case IDs must appear exactly once (E_COVERAGE).

Plus the run_id contract: two hosts running the same client must produce
distinct run_ids, or the second one is unpublishable (E_IMMUTABLE).
"""
import unittest

from tools.kinglet_spike.client_results import (
    to_evidence,
    validate_client_observations,
)
from tools.kinglet_spike.model import Environment, EvidenceError
from tools.kinglet_spike.validate import SAFE_COMPONENT
from tests.kinglet_spike.client_support import CASES, valid_observations


def _environment(os_name: str, release: str, arch: str) -> Environment:
    return Environment(
        os=os_name,
        release=release,
        arch=arch,
        native=True,
        toolchain=("claude=2.1.206",),
    )


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


class ClientRunIdTests(unittest.TestCase):
    """publish.py keys evidence on evidence/<kind>/<id>/<run_id>.json and raises
    E_IMMUTABLE on collision. A run_id derived from the subject alone therefore
    makes the second host record for a client unpublishable."""

    def setUp(self):
        self.observations = validate_client_observations(valid_observations(), CASES)

    def test_run_id_distinguishes_hosts_of_the_same_client(self):
        linux = to_evidence(self.observations, _environment("linux", "ubuntu-24.04", "x64"))
        macos = to_evidence(self.observations, _environment("macos", "26.0", "arm64"))
        windows = to_evidence(self.observations, _environment("windows", "11-24H2", "x64"))
        ids = {linux.run_id, macos.run_id, windows.run_id}
        self.assertEqual(
            3,
            len(ids),
            f"three hosts of the same client collided on run_id: {sorted(ids)}",
        )

    def test_run_id_is_environment_qualified(self):
        record = to_evidence(self.observations, _environment("macos", "26.0", "arm64"))
        self.assertNotEqual(record.run_id, "client-probe-claudecode")
        for component in ("macos", "26.0", "arm64"):
            self.assertIn(
                component,
                record.run_id,
                f"run_id {record.run_id!r} does not carry the environment component "
                f"{component!r}",
            )

    def test_run_id_is_a_safe_publication_component(self):
        # publish.py rejects a run_id that is not SAFE_COMPONENT, so slugification
        # of the environment fields is load-bearing.
        record = to_evidence(
            self.observations,
            _environment("linux", "Ubuntu 24.04.4 LTS", "x86_64"),
        )
        self.assertRegex(record.run_id, SAFE_COMPONENT)
