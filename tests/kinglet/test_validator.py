import json
from dataclasses import replace
from pathlib import Path
import shutil
import tempfile
import unittest

from tools.kinglet_build.errors import BuildError
from tools.kinglet_build.loader import load_graph
from tools.kinglet_build.model import CanonicalGraph, CanonicalUnit
from tools.kinglet_build.validator import validate_graph


FIXTURES = Path(__file__).parent / "fixtures"


class ValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name) / "repository"
        shutil.copytree(FIXTURES / "valid-minimal", self.root)
        self.graph = load_graph(self.root)

    def replace_unit(
        self,
        unit_id: str,
        **changes: object,
    ) -> CanonicalGraph:
        units = dict(self.graph.units)
        units[unit_id] = replace(units[unit_id], **changes)
        return replace(self.graph, units=units)

    def replace_attributes(
        self,
        unit_id: str,
        **changes: object,
    ) -> CanonicalGraph:
        attributes = dict(self.graph.units[unit_id].attributes)
        attributes.update(changes)
        return self.replace_unit(unit_id, attributes=attributes)

    def add_unit(self, unit: CanonicalUnit) -> CanonicalGraph:
        units = dict(self.graph.units)
        units[unit.id] = unit
        return replace(self.graph, units=units)

    def assert_build_error(
        self,
        graph: CanonicalGraph,
        code: str,
        field: str,
        detail: str,
    ) -> BuildError:
        with self.assertRaises(BuildError) as raised:
            validate_graph(graph)
        error = raised.exception
        self.assertEqual(code, error.code)
        self.assertEqual(field, error.field)
        self.assertEqual(detail, error.detail)
        self.assertEqual(
            f"{error.source}:{field}: [{code}] {detail}",
            str(error),
        )
        return error

    def test_accepts_valid_fixture(self) -> None:
        validate_graph(self.graph)

    def test_rejects_unsupported_catalog_schema_versions(self) -> None:
        for catalog_name in (
            "capabilities.json",
            "routing.json",
            "support-policy.json",
        ):
            with self.subTest(catalog=catalog_name):
                root = Path(self.temporary_directory.name) / catalog_name
                shutil.copytree(FIXTURES / "valid-minimal", root)
                catalog = root / "src" / "catalog" / catalog_name
                data = json.loads(catalog.read_text(encoding="utf-8"))
                data["schema_version"] = 2
                catalog.write_text(
                    json.dumps(data, indent=2) + "\n",
                    encoding="utf-8",
                )

                graph = load_graph(root)

                error = self.assert_build_error(
                    graph,
                    "invalid-schema-version",
                    "schema_version",
                    "catalog schema version must be 1",
                )
                self.assertEqual(catalog, error.source)

    def test_rejects_unsupported_unit_schema_versions(self) -> None:
        graph = self.replace_unit("role.unity-scout", schema_version=2)

        self.assert_build_error(
            graph,
            "invalid-schema-version",
            "schema_version",
            "canonical unit schema version must be 1",
        )

    def test_rejects_invalid_unit_ids_before_kinds(self) -> None:
        graph = self.replace_unit(
            "role.unity-scout",
            id="role.Unity-scout",
            kind="workflow",
        )

        self.assert_build_error(
            graph,
            "invalid-id",
            "id",
            "ID must match canonical ID syntax and its graph key",
        )

    def test_rejects_unit_kinds_that_do_not_match_their_ids(self) -> None:
        graph = self.replace_unit("role.unity-scout", kind="workflow")

        self.assert_build_error(
            graph,
            "invalid-kind",
            "kind",
            "unit kind must match the namespace in role.unity-scout",
        )

    def test_unit_field_errors_point_to_their_json_descriptors(self) -> None:
        cases = (
            (
                self.replace_unit("role.unity-scout", schema_version=2),
                "invalid-schema-version",
                "schema_version",
                "canonical unit schema version must be 1",
                self.root / "src" / "roles" / "unity-scout" / "role.json",
            ),
            (
                self.replace_unit("role.unity-scout", kind="workflow"),
                "invalid-kind",
                "kind",
                "unit kind must match the namespace in role.unity-scout",
                self.root / "src" / "roles" / "unity-scout" / "role.json",
            ),
            (
                self.replace_attributes("workflow.unity-audit", stages=()),
                "invalid-workflow",
                "stages",
                "workflow requires at least one stage item",
                self.root
                / "src"
                / "workflows"
                / "unity-audit"
                / "workflow.json",
            ),
        )
        for graph, code, field, detail, expected_source in cases:
            with self.subTest(field=field, source=expected_source):
                error = self.assert_build_error(graph, code, field, detail)

                self.assertEqual(expected_source, error.source)

    def test_rejects_unknown_capabilities(self) -> None:
        graph = self.replace_unit(
            "role.unity-scout",
            capabilities=("unity.teleport",),
        )

        self.assert_build_error(
            graph,
            "unknown-capability",
            "capabilities",
            "capability 'unity.teleport' is not declared in capabilities.json",
        )

    def test_rejects_unresolved_requires_references(self) -> None:
        graph = self.replace_unit(
            "role.unity-scout",
            requires=("knowledge.missing",),
        )

        self.assert_build_error(
            graph,
            "unresolved-reference",
            "requires",
            "reference 'knowledge.missing' does not resolve to a canonical unit",
        )

    def test_rejects_unresolved_workflow_references(self) -> None:
        for field, missing_id in (
            ("roles", "role.missing"),
            ("rules", "rule.missing"),
            ("knowledge", "knowledge.missing"),
        ):
            with self.subTest(field=field):
                graph = self.replace_attributes(
                    "workflow.unity-audit",
                    **{field: (missing_id,)},
                )

                self.assert_build_error(
                    graph,
                    "unresolved-reference",
                    field,
                    f"reference '{missing_id}' does not resolve to a canonical unit",
                )

    def test_rejects_non_iterable_workflow_references_without_type_error(self) -> None:
        graph = self.replace_attributes("workflow.unity-audit", roles=7)

        error = self.assert_build_error(
            graph,
            "invalid-workflow",
            "roles",
            "workflow reference IDs must be a tuple of strings",
        )

        self.assertNotIsInstance(error.__cause__, TypeError)

    def test_sorts_reference_ids_before_reporting_an_error(self) -> None:
        graph = self.replace_unit(
            "role.unity-scout",
            requires=("template.z-missing", "hook.a-missing"),
        )

        self.assert_build_error(
            graph,
            "unresolved-reference",
            "requires",
            "reference 'hook.a-missing' does not resolve to a canonical unit",
        )

    def test_sorts_reference_ids_globally_across_workflow_fields(self) -> None:
        cases = (
            (
                {
                    "requires": ("template.z-missing",),
                    "roles": ("role.y-missing",),
                    "rules": ("rule.x-missing",),
                    "knowledge": ("knowledge.a-missing",),
                },
                "knowledge",
                "knowledge.a-missing",
            ),
            (
                {
                    "requires": ("missing.shared",),
                    "roles": ("missing.shared",),
                    "rules": ("missing.shared",),
                    "knowledge": ("missing.shared",),
                },
                "knowledge",
                "missing.shared",
            ),
        )
        workflow = self.graph.units["workflow.unity-audit"]
        for changes, expected_field, expected_id in cases:
            with self.subTest(changes=changes):
                attributes = dict(workflow.attributes)
                for field in ("roles", "rules", "knowledge"):
                    attributes[field] = changes[field]
                units = dict(self.graph.units)
                units[workflow.id] = replace(
                    workflow,
                    requires=changes["requires"],
                    attributes=attributes,
                )
                graph = replace(self.graph, units=units)

                self.assert_build_error(
                    graph,
                    "unresolved-reference",
                    expected_field,
                    f"reference '{expected_id}' does not resolve to a canonical unit",
                )

    def test_rejects_references_to_the_wrong_unit_kind(self) -> None:
        graph = self.replace_attributes(
            "workflow.unity-audit",
            roles=("knowledge.serialization",),
        )

        self.assert_build_error(
            graph,
            "invalid-reference-kind",
            "roles",
            "reference 'knowledge.serialization' must resolve to kind role, not knowledge",
        )

    def test_exception_support_requires_reason_owner_and_named_test(self) -> None:
        unit = self.graph.units["role.unity-scout"]
        for field in ("reason", "owner", "test"):
            with self.subTest(field=field):
                metadata = {
                    "reason": "Reduced behavior is documented.",
                    "owner": "kinglet-maintainers",
                    "test": "tests.kinglet.test_validator",
                }
                metadata[field] = None
                declaration = replace(
                    unit.support["codex"],
                    state="exception",
                    **metadata,
                )
                support = dict(unit.support)
                support["codex"] = declaration
                graph = self.replace_unit("role.unity-scout", support=support)

                self.assert_build_error(
                    graph,
                    "invalid-support",
                    f"support.codex.{field}",
                    f"exception support requires a non-empty {field}",
                )

    def test_supported_units_reject_exception_only_fields(self) -> None:
        unit = self.graph.units["role.unity-scout"]
        for field in ("reason", "owner", "test"):
            with self.subTest(field=field):
                declaration = replace(
                    unit.support["codex"],
                    **{field: "This metadata is not valid for supported."},
                )
                support = dict(unit.support)
                support["codex"] = declaration
                graph = self.replace_unit("role.unity-scout", support=support)

                self.assert_build_error(
                    graph,
                    "invalid-support",
                    f"support.codex.{field}",
                    f"supported support may not declare exception-only {field}",
                )

    def test_unsupported_units_allow_a_visible_reason(self) -> None:
        unit = self.graph.units["role.unity-scout"]
        declaration = replace(
            unit.support["codex"],
            state="unsupported",
            reason="This client cannot provide the required behavior.",
        )
        support = dict(unit.support)
        support["codex"] = declaration
        graph = self.replace_unit("role.unity-scout", support=support)

        validate_graph(graph)

    def test_unsupported_units_reject_a_blank_reason(self) -> None:
        unit = self.graph.units["role.unity-scout"]
        declaration = replace(
            unit.support["codex"],
            state="unsupported",
            reason="  ",
        )
        support = dict(unit.support)
        support["codex"] = declaration
        graph = self.replace_unit("role.unity-scout", support=support)

        self.assert_build_error(
            graph,
            "invalid-support",
            "support.codex.reason",
            "unsupported support reason must be non-empty when declared",
        )

    def test_unsupported_units_reject_owner_and_test(self) -> None:
        unit = self.graph.units["role.unity-scout"]
        for field in ("owner", "test"):
            with self.subTest(field=field):
                declaration = replace(
                    unit.support["codex"],
                    state="unsupported",
                    **{field: "exception-only-metadata"},
                )
                support = dict(unit.support)
                support["codex"] = declaration
                graph = self.replace_unit("role.unity-scout", support=support)

                self.assert_build_error(
                    graph,
                    "invalid-support",
                    f"support.codex.{field}",
                    f"unsupported support may not declare exception-only {field}",
                )

    def test_rejects_mutating_workflows_without_a_write_capability(self) -> None:
        graph = self.replace_attributes("workflow.unity-audit", mutation=True)

        self.assert_build_error(
            graph,
            "invalid-workflow",
            "mutation",
            "mutating workflow requires filesystem.write or unity.write",
        )

    def test_workflows_require_stages_artifacts_and_evidence(self) -> None:
        for field in ("stages", "artifacts", "evidence"):
            with self.subTest(field=field):
                graph = self.replace_attributes(
                    "workflow.unity-audit",
                    **{field: ()},
                )

                self.assert_build_error(
                    graph,
                    "invalid-workflow",
                    field,
                    f"workflow requires at least one {field[:-1] if field.endswith('s') else field} item",
                )

    def test_rejects_forbidden_requires_cycles(self) -> None:
        graph = self.replace_unit(
            "knowledge.serialization",
            requires=("role.unity-scout",),
        )

        self.assert_build_error(
            graph,
            "dependency-cycle",
            "requires",
            "requires cycle: knowledge.serialization -> role.unity-scout -> knowledge.serialization",
        )

    def test_rejects_duplicate_generated_path_claims(self) -> None:
        workflow = self.graph.units["workflow.unity-audit"]
        duplicate = replace(
            workflow,
            id="workflow.zeta-audit",
            content_path=workflow.content_path.with_name("duplicate-instructions.md"),
        )
        graph = self.add_unit(duplicate)

        self.assert_build_error(
            graph,
            "duplicate-generated-path",
            "public_name",
            "workflow.zeta-audit duplicates public name 'unity-audit' already claimed by workflow.unity-audit",
        )

    def test_validation_phase_order_is_deterministic(self) -> None:
        role = self.graph.units["role.unity-scout"]
        declaration = replace(
            role.support["codex"],
            reason="Invalid exception-only metadata.",
        )
        support = dict(role.support)
        support["codex"] = declaration
        graph = self.replace_unit(
            "role.unity-scout",
            capabilities=("unity.teleport",),
            requires=("knowledge.missing",),
            support=support,
        )

        self.assert_build_error(
            graph,
            "unknown-capability",
            "capabilities",
            "capability 'unity.teleport' is not declared in capabilities.json",
        )


if __name__ == "__main__":
    unittest.main()
