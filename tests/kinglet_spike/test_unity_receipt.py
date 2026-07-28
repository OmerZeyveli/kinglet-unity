import unittest

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.unity.model import EXECUTING_ROUTES, ROUTES
from tools.kinglet_spike.unity.receipt import (
    receipt_to_evidence,
    unity_receipt_from_dict,
    validate_unity_receipt,
)
from tests.kinglet_spike.unity_support import load, passing_receipt, receipt


class UnityReceiptTests(unittest.TestCase):
    def test_filesystem_must_not_claim_compile_or_editor_ready(self):
        value = receipt("filesystem")
        value["compile"] = {"status": "pass", "errors": 0}
        value["ready"] = True
        self.assertEqual(
            {"E_ASSERTION"},
            {item.code for item in validate_unity_receipt(load(value))},
        )

    def test_executing_routes_require_one_passing_test(self):
        for route in ("live-editor-mcp", "same-project-headless", "isolated-headless"):
            value = receipt(route)
            value["compile"] = {"status": "pass", "errors": 0}
            value["tests"] = {"status": "pass", "passed": 0, "failed": 0, "skipped": 0}
            with self.subTest(route=route):
                self.assertTrue(validate_unity_receipt(load(value)))

    def test_pass_never_has_lease_or_descendants(self):
        value = passing_receipt("same-project-headless")
        value["active_lease"] = True
        value["descendant_pids"] = [1234]
        self.assertEqual(2, len(validate_unity_receipt(load(value))))

    # --- additional coverage: structural parsing (unity_receipt_from_dict) ---

    def test_unknown_top_level_field_is_rejected(self):
        value = receipt("filesystem")
        value["extra_field"] = True
        with self.assertRaises(EvidenceError) as ctx:
            unity_receipt_from_dict(value)
        self.assertEqual("E_FIELD", ctx.exception.code)

    def test_unknown_route_is_rejected(self):
        value = receipt("filesystem")
        value["route"] = "same-project-gui"
        with self.assertRaises(EvidenceError) as ctx:
            unity_receipt_from_dict(value)
        self.assertEqual("E_ENUM", ctx.exception.code)

    def test_wrong_schema_is_rejected(self):
        value = receipt("filesystem")
        value["schema"] = "kinglet.unity-probe.receipt/v2"
        with self.assertRaises(EvidenceError) as ctx:
            unity_receipt_from_dict(value)
        self.assertEqual("E_SCHEMA", ctx.exception.code)

    def test_unknown_compile_status_is_rejected(self):
        value = receipt("filesystem")
        value["compile"] = {"status": "running", "errors": 0}
        with self.assertRaises(EvidenceError) as ctx:
            unity_receipt_from_dict(value)
        self.assertEqual("E_ENUM", ctx.exception.code)

    def test_wrong_type_field_is_rejected(self):
        value = receipt("filesystem")
        value["active_lease"] = "false"
        with self.assertRaises(EvidenceError) as ctx:
            unity_receipt_from_dict(value)
        self.assertEqual("E_FIELD", ctx.exception.code)

    def test_all_frozen_routes_parse_cleanly(self):
        for route in ROUTES:
            with self.subTest(route=route):
                parsed = load(receipt(route))
                self.assertEqual(route, parsed.route)

    # --- semantic validation: ready is exclusive to live-editor-mcp ---

    def test_ready_true_rejected_on_non_live_editor_routes(self):
        for route in EXECUTING_ROUTES - {"live-editor-mcp"}:
            value = passing_receipt(route)
            value["ready"] = True
            with self.subTest(route=route):
                codes = {item.code for item in validate_unity_receipt(load(value))}
                self.assertIn("E_ASSERTION", codes)

    def test_live_editor_mcp_pass_with_ready_true_is_clean(self):
        value = passing_receipt("live-editor-mcp")
        self.assertEqual((), validate_unity_receipt(load(value)))

    # --- semantic validation: collision_refused is a refusal, not a run ---

    def test_collision_refused_outside_same_project_headless_is_rejected(self):
        value = receipt("isolated-headless")
        value["collision_refused"] = True
        codes = {item.code for item in validate_unity_receipt(load(value))}
        self.assertIn("E_ASSERTION", codes)

    def test_collision_refused_with_a_completed_run_is_rejected(self):
        value = passing_receipt("same-project-headless")
        value["collision_refused"] = True
        codes = {item.code for item in validate_unity_receipt(load(value))}
        self.assertIn("E_ASSERTION", codes)

    def test_collision_refused_alone_is_clean(self):
        value = receipt("same-project-headless")
        value["collision_refused"] = True
        self.assertEqual((), validate_unity_receipt(load(value)))

    # --- semantic validation: a clean filesystem receipt has no diagnostics ---

    def test_clean_filesystem_receipt_is_valid(self):
        self.assertEqual((), validate_unity_receipt(load(receipt("filesystem"))))

    def test_clean_passing_headless_receipts_are_valid(self):
        for route in ("same-project-headless", "isolated-headless"):
            with self.subTest(route=route):
                self.assertEqual((), validate_unity_receipt(load(passing_receipt(route))))

    # --- receipt_to_evidence ---

    def test_receipt_to_evidence_reflects_contract_pass(self):
        from tools.kinglet_spike.model import Environment

        environment = Environment(
            os="linux",
            release="ubuntu-24.04.4-lts",
            arch="x64",
            native=True,
            toolchain=("unity=6000.3.18f1",),
        )
        record = receipt_to_evidence(load(passing_receipt("isolated-headless")), environment)
        self.assertEqual("pass", record.status)
        self.assertEqual("unity", record.subject.kind)
        self.assertEqual("isolated-headless", record.probe.id)
        self.assertTrue(all(a.status == "pass" for a in record.assertions))

    def test_receipt_to_evidence_reflects_contract_violation(self):
        from tools.kinglet_spike.model import Environment

        environment = Environment(
            os="linux",
            release="ubuntu-24.04.4-lts",
            arch="x64",
            native=True,
            toolchain=("unity=6000.3.18f1",),
        )
        value = receipt("filesystem")
        value["compile"] = {"status": "pass", "errors": 0}
        record = receipt_to_evidence(load(value), environment)
        self.assertEqual("fail", record.status)


if __name__ == "__main__":
    unittest.main()
