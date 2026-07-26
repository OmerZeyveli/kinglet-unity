import unittest

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.runtime_contract import REQUIRED_ASSERTIONS, validate_host_result


def valid_result() -> dict:
    return {
        "schema": "kinglet.host-probe.result/v1",
        "candidate": {"id": "fake", "version": "1.0.0"},
        "status": "pass",
        "errors": [],
        "assertions": [{"id": item, "status": "pass"} for item in REQUIRED_ASSERTIONS],
        "descendant_pids": [],
        "active_lease": False,
    }


class RuntimeContractTests(unittest.TestCase):
    def test_accepts_complete_pass(self):
        self.assertEqual("pass", validate_host_result(valid_result()).status)

    def test_rejects_missing_assertion(self):
        value = valid_result()
        value["assertions"].pop()
        with self.assertRaisesRegex(EvidenceError, "E_ASSERTION"):
            validate_host_result(value)

    def test_rejects_pass_with_descendant_or_lease(self):
        for field, value in (("descendant_pids", [4123]), ("active_lease", True)):
            result = valid_result()
            result[field] = value
            with self.subTest(field=field):
                with self.assertRaisesRegex(EvidenceError, "E_ASSERTION"):
                    validate_host_result(result)
