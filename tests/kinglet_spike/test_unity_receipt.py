import json
import unittest
from pathlib import Path

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.model import Environment
from tools.kinglet_spike.unity.model import (
    CONTRACT_RULES,
    CONTRACT_SCHEMA,
    EXECUTING_ROUTES,
    LEGACY_RECEIPT_SCHEMAS,
    PROJECT_ID,
    RECEIPT_SCHEMA,
    RECEIPT_SCHEMA_V1,
    RECEIPT_SCHEMA_V2,
    ROUTES,
    STATUS_VALUES,
)
from tools.kinglet_spike.unity.receipt import (
    receipt_to_evidence,
    unity_receipt_from_dict,
    validate_unity_receipt,
)
from tests.kinglet_spike.unity_support import (
    legacy_receipt,
    load,
    passing_receipt,
    receipt,
)

ROUTES_CONTRACT_PATH = Path("spikes/platform/unity/contracts/routes-v1.json")
PUBLISHED_ISOLATED_RECEIPT = Path(
    "docs/research/platform-spike/artifacts/unity/"
    "20260728T132858Z-unity-probe-isolated-headless-linux-ubuntu-24-04-4-lts-x64-01/"
    "isolated-headless-receipt.json"
)


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
        # v2 became the CURRENT schema; an unsupported one is a version this
        # tree has never defined, not merely a different one.
        value["schema"] = "kinglet.unity-probe.receipt/v3"
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

    # --- fix round 1: an executing route that ran nothing must not validate
    #     clean, and must not convert to a passing EvidenceRecord (CRITICAL 1) ---

    def test_executing_route_default_not_run_receipt_is_rejected(self):
        for route in EXECUTING_ROUTES:
            with self.subTest(route=route):
                codes = {item.code for item in validate_unity_receipt(load(receipt(route)))}
                self.assertIn("E_ASSERTION", codes)

    def test_executing_route_default_not_run_receipt_converts_to_fail(self):
        from tools.kinglet_spike.model import Environment

        environment = Environment(
            os="linux", release="ubuntu-24.04.4-lts", arch="x64",
            native=True, toolchain=("unity=6000.3.18f1",),
        )
        for route in EXECUTING_ROUTES:
            with self.subTest(route=route):
                record = receipt_to_evidence(load(receipt(route)), environment)
                self.assertEqual("fail", record.status)
                self.assertFalse(all(a.status == "pass" for a in record.assertions))

    def test_collision_refused_exempts_not_run_from_the_executing_route_check(self):
        # A refusal never launched Unity at all -- not-run is the honest
        # value there, and this must not collide with the new "executing
        # routes must not report compile.status=not-run" rule above.
        value = receipt("same-project-headless")
        value["collision_refused"] = True
        self.assertEqual((), validate_unity_receipt(load(value)))

    # --- fix round 1: compile.status claims must be backed by errors (IMPORTANT 1) ---

    def test_compile_pass_with_errors_is_rejected(self):
        value = passing_receipt("isolated-headless")
        value["compile"]["errors"] = 5
        codes = {item.code for item in validate_unity_receipt(load(value))}
        self.assertIn("E_ASSERTION", codes)

    def test_compile_fail_with_zero_errors_is_rejected(self):
        value = receipt("isolated-headless")
        value["compile"] = {"status": "fail", "errors": 0}
        codes = {item.code for item in validate_unity_receipt(load(value))}
        self.assertIn("E_ASSERTION", codes)

    # --- fix round 1: tests.status=pass with skipped>0, or without a
    #     passing compile, is rejected (IMPORTANT 2) ---

    def test_tests_pass_with_nonzero_skipped_is_rejected(self):
        value = passing_receipt("isolated-headless")
        value["tests"]["skipped"] = 99
        codes = {item.code for item in validate_unity_receipt(load(value))}
        self.assertIn("E_ASSERTION", codes)

    def test_tests_pass_with_compile_not_run_is_rejected(self):
        value = receipt("isolated-headless")
        value["tests"] = {"status": "pass", "passed": 1, "failed": 0, "skipped": 0}
        codes = {item.code for item in validate_unity_receipt(load(value))}
        self.assertIn("E_ASSERTION", codes)

    def test_tests_pass_with_compile_fail_is_rejected(self):
        value = receipt("isolated-headless")
        value["compile"] = {"status": "fail", "errors": 1}
        value["tests"] = {"status": "pass", "passed": 1, "failed": 0, "skipped": 0}
        codes = {item.code for item in validate_unity_receipt(load(value))}
        self.assertIn("E_ASSERTION", codes)

    # --- fix round 1: live-editor-mcp cannot claim a passing test run
    #     without ready=true (IMPORTANT 3) ---

    def test_live_editor_mcp_tests_pass_without_ready_is_rejected(self):
        value = passing_receipt("live-editor-mcp")
        value["ready"] = False
        codes = {item.code for item in validate_unity_receipt(load(value))}
        self.assertIn("E_ASSERTION", codes)

    # --- fix round 1: the frozen constants must match the frozen JSON contract
    #     they are supposed to mirror (IMPORTANT 4) ---

    def test_frozen_constants_match_routes_contract_json(self):
        contract = json.loads(ROUTES_CONTRACT_PATH.read_text(encoding="utf-8"))
        self.assertEqual(RECEIPT_SCHEMA, contract["receipt_schema"])
        self.assertEqual(PROJECT_ID, contract["project_id"])
        self.assertEqual(ROUTES, frozenset(contract["routes"]))
        self.assertEqual(EXECUTING_ROUTES, frozenset(contract["executing_routes"]))
        self.assertEqual(STATUS_VALUES, frozenset(contract["compile_statuses"]))
        self.assertEqual(STATUS_VALUES, frozenset(contract["test_statuses"]))

    # --- FINAL whole-branch review, MINOR: routes-v1.json's `schema` and
    #     `notes` were the only fields nothing read. MEASURED: deleting all
    #     seven frozen rules -- including "refuse silent project upgrade" --
    #     left the whole suite green.

    def test_the_contract_declares_the_schema_the_code_expects(self):
        contract = json.loads(ROUTES_CONTRACT_PATH.read_text(encoding="utf-8"))
        self.assertEqual(CONTRACT_SCHEMA, contract["schema"])

    def test_every_frozen_rule_is_still_stated_in_the_contract(self):
        contract = json.loads(ROUTES_CONTRACT_PATH.read_text(encoding="utf-8"))
        notes = contract["notes"]
        self.assertEqual(
            len(CONTRACT_RULES),
            len(notes),
            "the contract gained or lost a rule; CONTRACT_RULES must move with it",
        )
        for index, (phrase, _enforcer) in enumerate(CONTRACT_RULES):
            with self.subTest(rule=phrase):
                matching = [note for note in notes if phrase in note]
                self.assertEqual(
                    1,
                    len(matching),
                    f"rule {index} ({phrase!r}) is stated {len(matching)} times",
                )

    def test_every_frozen_rule_names_a_module_that_still_exists(self):
        # A rule bound only to prose is bound to nothing. Each rule names the
        # module responsible for it, and "refuse silent project upgrade" is
        # the reason this matters: the contract itself says that rule is
        # editor.py's, and that responsibility "is not lost between tasks".
        import importlib

        for phrase, enforcer in CONTRACT_RULES:
            with self.subTest(rule=phrase):
                module = importlib.import_module(
                    f"tools.kinglet_spike.unity.{enforcer}"
                )
                self.assertTrue(hasattr(module, "__file__"))

    def test_the_project_upgrade_rule_has_a_live_enforcement_point(self):
        # Named specifically because it is the one rule with no receipt field
        # to carry it, which is exactly why the contract note exists.
        from tools.kinglet_spike.unity import editor

        self.assertTrue(callable(editor.verify_project_editor))

    def test_the_probe_contract_written_into_records_is_the_same_string(self):
        # results.PROBE_CONTRACT is stamped into `probe.contract` on every
        # published record. It was a THIRD unbound copy of the receipt schema,
        # so an edit to the contract would have made published provenance name
        # a contract nothing else in the tree answers to.
        from tools.kinglet_spike.unity.results import PROBE_CONTRACT

        contract = json.loads(ROUTES_CONTRACT_PATH.read_text(encoding="utf-8"))
        self.assertEqual(RECEIPT_SCHEMA, PROBE_CONTRACT)
        self.assertEqual(contract["receipt_schema"], PROBE_CONTRACT)

    def test_the_host_probe_timeout_is_the_same_budget_the_route_uses(self):
        # host_probes.FULL_TIMEOUT_SECONDS is the value that actually times the
        # real host probe. It duplicated routes.HEADLESS_TIMEOUT_SECONDS, so
        # editing a contract phase updated the bound twin and silently left the
        # one that governs the run.
        from tools.kinglet_spike.unity import host_probes, routes

        contract = json.loads(ROUTES_CONTRACT_PATH.read_text(encoding="utf-8"))
        expected = float(sum(
            contract["timings_seconds"][phase]
            for phase in routes.HEADLESS_TIMEOUT_PHASES
        ))
        self.assertEqual(expected, routes.HEADLESS_TIMEOUT_SECONDS)
        self.assertEqual(routes.HEADLESS_TIMEOUT_SECONDS, host_probes.FULL_TIMEOUT_SECONDS)

    def test_routes_contract_json_has_the_briefed_timings(self):
        contract = json.loads(ROUTES_CONTRACT_PATH.read_text(encoding="utf-8"))
        self.assertEqual(
            {
                "editor_startup": 300,
                "import_compile_ready": 300,
                "mcp_server_startup": 60,
                "mcp_editor_ready": 300,
                "edit_mode_tests": 180,
                "cancellation_cleanup": 15,
            },
            contract["timings_seconds"],
        )

    # --- fix round 1: a Windows drive-relative artifact path must not pass
    #     as a safe relative path (MINOR 2) ---

    def test_windows_drive_relative_artifact_path_is_rejected(self):
        value = receipt("filesystem")
        value["artifacts"] = ["C:foo.txt"]
        codes = {item.code for item in validate_unity_receipt(load(value))}
        self.assertIn("E_PATH", codes)


class IsolationManifestIsMandatoryTests(unittest.TestCase):
    """`isolated-headless` may not claim isolation it cannot show.

    Before this, a `same-project-headless` receipt and an `isolated-headless`
    receipt were byte-identical apart from the `route` label: the runtime
    check in `isolation.assert_isolated` was real, and the PUBLISHED evidence
    encoded none of it. The receipt now cites the isolation manifest, and the
    citation is required by the schema rather than by convention.

    The eight already-published records were produced under v1 and are
    immutable, so v1 stays READABLE as legacy -- it is not upgraded, and it is
    not publishable as new evidence either.
    """

    def _isolated(self) -> dict:
        value = passing_receipt("isolated-headless")
        self.assertEqual(RECEIPT_SCHEMA_V2, value["schema"])
        return value

    # --- v2 requires the citation ---

    def test_v2_isolated_receipt_without_a_manifest_citation_refuses(self):
        value = self._isolated()
        del value["isolation_manifest"]
        diagnostics = validate_unity_receipt(load(value))
        # The CODE as well as the location: "there is no citation" and "the
        # citation is an unsafe path" are different failures, and a missing
        # citation reported as a path problem is a rule stated by accident.
        self.assertEqual(
            [("E_ASSERTION", "isolation_manifest")],
            [(item.code, item.location) for item in diagnostics],
        )
        self.assertIn("must cite the isolation manifest", diagnostics[0].message)

    def test_v2_isolated_receipt_with_an_empty_citation_refuses(self):
        value = self._isolated()
        value["isolation_manifest"] = ""
        diagnostics = validate_unity_receipt(load(value))
        self.assertEqual(
            [("E_ASSERTION", "isolation_manifest")],
            [(item.code, item.location) for item in diagnostics],
        )

    def test_v2_isolated_receipt_with_a_null_citation_refuses(self):
        value = self._isolated()
        value["isolation_manifest"] = None
        diagnostics = validate_unity_receipt(load(value))
        self.assertEqual(
            [("E_ASSERTION", "isolation_manifest")],
            [(item.code, item.location) for item in diagnostics],
        )

    def test_a_citation_absent_from_artifacts_refuses(self):
        # A field that is merely PRESENT is worth nothing: the cited path must
        # be one of the artifacts published beside the receipt, or a reader has
        # nothing to fetch.
        value = self._isolated()
        value["artifacts"] = [
            path for path in value["artifacts"]
            if path != value["isolation_manifest"]
        ]
        self.assertIn(
            "isolation_manifest",
            [item.location for item in validate_unity_receipt(load(value))],
        )

    def test_an_escaping_citation_refuses(self):
        value = self._isolated()
        value["isolation_manifest"] = "../elsewhere/manifest.json"
        value["artifacts"] = [value["isolation_manifest"]]
        codes = {item.code for item in validate_unity_receipt(load(value))}
        self.assertIn("E_PATH", codes)

    def test_another_route_must_not_carry_an_isolation_claim(self):
        for route in ("filesystem", "same-project-headless", "live-editor-mcp"):
            value = passing_receipt(route)
            value["isolation_manifest"] = "artifacts/unity/manifest.json"
            value["artifacts"] = [value["isolation_manifest"]]
            with self.subTest(route=route):
                self.assertIn(
                    "isolation_manifest",
                    [item.location for item in validate_unity_receipt(load(value))],
                )

    def test_a_legitimate_isolated_receipt_still_validates(self):
        self.assertEqual((), validate_unity_receipt(load(self._isolated())))

    # --- v1 is legacy: readable, never upgraded, never republished ---

    def test_v1_receipt_may_not_carry_the_new_field(self):
        value = legacy_receipt("isolated-headless")
        value["isolation_manifest"] = "artifacts/unity/manifest.json"
        with self.assertRaises(EvidenceError) as caught:
            unity_receipt_from_dict(value)
        self.assertEqual("E_FIELD", caught.exception.code)

    def test_v1_receipt_is_not_silently_upgraded(self):
        parsed = load(legacy_receipt("isolated-headless"))
        self.assertEqual(RECEIPT_SCHEMA_V1, parsed.schema)
        self.assertIsNone(parsed.isolation_manifest)

    def test_an_existing_v1_isolated_receipt_still_validates(self):
        value = legacy_receipt("isolated-headless")
        value["compile"] = {"status": "pass", "errors": 0}
        value["tests"] = {"status": "pass", "passed": 1, "failed": 0, "skipped": 0}
        value["artifacts"] = [
            "artifacts/unity/isolated-headless-summary.json",
            "artifacts/unity/isolated-headless-manifest.json",
        ]
        self.assertEqual((), validate_unity_receipt(load(value)))

    def test_the_published_isolated_receipt_still_parses_and_validates(self):
        # The real committed artifact, through the real reader. This is the
        # "accept the existing records" half of the transition, measured
        # against the bytes rather than against a fixture shaped like them.
        published = json.loads(PUBLISHED_ISOLATED_RECEIPT.read_text(encoding="utf-8"))
        parsed = unity_receipt_from_dict(published)
        self.assertEqual(RECEIPT_SCHEMA_V1, parsed.schema)
        self.assertEqual((), validate_unity_receipt(parsed))

    def test_a_legacy_receipt_cannot_back_a_new_published_record(self):
        # Readable is not publishable. Nothing in the committed tree was made
        # this way, so this closes the downgrade route -- emitting v1 to dodge
        # the manifest requirement -- without touching what is already on disk.
        environment = Environment(
            os="linux", release="ubuntu-24.04", arch="x64",
            native=True, toolchain="test",
        )
        value = legacy_receipt("isolated-headless")
        value["compile"] = {"status": "pass", "errors": 0}
        value["tests"] = {"status": "pass", "passed": 1, "failed": 0, "skipped": 0}
        record = receipt_to_evidence(load(value), environment)
        self.assertEqual("fail", record.status)
        contract = [item for item in record.assertions if item.id == "contract"][0]
        self.assertEqual("fail", contract.status)
        self.assertIn(RECEIPT_SCHEMA_V1, contract.detail)

    # --- the schema constants and the frozen contract move together ---

    def test_the_current_schema_is_v2_and_v1_is_the_only_legacy_one(self):
        self.assertEqual(RECEIPT_SCHEMA_V2, RECEIPT_SCHEMA)
        self.assertEqual(frozenset((RECEIPT_SCHEMA_V1,)), LEGACY_RECEIPT_SCHEMAS)
        self.assertNotIn(RECEIPT_SCHEMA, LEGACY_RECEIPT_SCHEMAS)

    def test_the_contract_states_both_the_current_and_the_legacy_schema(self):
        contract = json.loads(ROUTES_CONTRACT_PATH.read_text(encoding="utf-8"))
        self.assertEqual(RECEIPT_SCHEMA, contract["receipt_schema"])
        self.assertEqual(
            LEGACY_RECEIPT_SCHEMAS, frozenset(contract["legacy_receipt_schemas"])
        )

    def test_no_producer_module_can_spell_the_legacy_schema(self):
        # The downgrade hole restated as a producer property: a route that
        # wanted to dodge the manifest requirement would emit v1. The modules
        # that BUILD receipts may not name that string at all; only the two
        # modules that must still READ it may.
        from tools.kinglet_spike.unity import host_probes, mcp
        from tools.kinglet_spike.unity import routes as routes_module

        for module in (routes_module, host_probes, mcp):
            with self.subTest(module=module.__name__):
                source = Path(module.__file__).read_text(encoding="utf-8")
                self.assertNotIn(RECEIPT_SCHEMA_V1, source)


if __name__ == "__main__":
    unittest.main()
