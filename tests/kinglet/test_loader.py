import json
from dataclasses import FrozenInstanceError
from pathlib import Path
import shutil
import tempfile
import unittest

from tools.kinglet_build.errors import BuildError
from tools.kinglet_build.loader import load_graph
from tools.kinglet_build.model import (
    CanonicalGraph,
    CanonicalUnit,
    Provenance,
    SupportDeclaration,
)


FIXTURES = Path(__file__).parent / "fixtures"


class LoaderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name) / "repository"
        shutil.copytree(FIXTURES / "valid-minimal", self.root)

    def copy_fixture(self, name: str) -> Path:
        root = Path(self.temporary_directory.name) / name
        shutil.copytree(FIXTURES / "valid-minimal", root)
        return root

    def descriptor(self, root: Path | None = None) -> Path:
        repository_root = root if root is not None else self.root
        return (
            repository_root / "src" / "roles" / "unity-scout" / "role.json"
        )

    def read_descriptor(self, root: Path | None = None) -> dict[str, object]:
        return json.loads(self.descriptor(root).read_text(encoding="utf-8"))

    def write_descriptor(
        self, descriptor: dict[str, object], root: Path | None = None
    ) -> None:
        self.descriptor(root).write_text(
            json.dumps(descriptor, indent=2) + "\n",
            encoding="utf-8",
        )

    def assert_build_error(self, code: str, root: Path | None = None) -> BuildError:
        with self.assertRaises(BuildError) as raised:
            load_graph(root if root is not None else self.root)
        self.assertEqual(code, raised.exception.code)
        self.assertEqual(
            f"{raised.exception.source}:{raised.exception.field}: "
            f"[{raised.exception.code}] {raised.exception.detail}",
            str(raised.exception),
        )
        return raised.exception

    def test_loads_valid_fixture_as_one_canonical_unit(self) -> None:
        graph = load_graph(self.root)

        self.assertEqual({"role.unity-scout"}, set(graph.units))
        unit = graph.units["role.unity-scout"]
        self.assertIsInstance(unit, CanonicalUnit)
        self.assertEqual("role", unit.kind)
        self.assertEqual(("filesystem.read", "unity.read"), unit.capabilities)
        self.assertEqual(
            self.root
            / "src"
            / "roles"
            / "unity-scout"
            / "instructions.md",
            unit.content_path,
        )

    def test_rejects_unknown_descriptor_field(self) -> None:
        invalid = FIXTURES / "invalid-unknown" / "src" / "roles" / "unity-scout"
        shutil.copy2(invalid / "role.json", self.descriptor())

        error = self.assert_build_error("unknown-field")

        self.assertEqual("mystery_field", error.field)

    def test_rejects_missing_markdown_body(self) -> None:
        (self.descriptor().parent / "instructions.md").unlink()

        self.assert_build_error("missing-content")

    def test_rejects_duplicate_ids(self) -> None:
        duplicate = self.root / "src" / "roles" / "other-scout"
        shutil.copytree(self.descriptor().parent, duplicate)

        self.assert_build_error("duplicate-id")

    def test_rejects_invalid_support_state(self) -> None:
        descriptor = self.read_descriptor()
        support = descriptor["support"]
        self.assertIsInstance(support, dict)
        support["codex"]["state"] = "partial"
        self.write_descriptor(descriptor)

        error = self.assert_build_error("invalid-support")

        self.assertEqual("support.codex.state", error.field)

    def test_rejects_unhashable_support_states_with_stable_diagnostic(self) -> None:
        for index, state in enumerate(([], {})):
            with self.subTest(state=state):
                root = self.copy_fixture(f"support-state-{index}")
                descriptor = self.read_descriptor(root)
                descriptor["support"]["codex"]["state"] = state
                self.write_descriptor(descriptor, root)

                error = self.assert_build_error("invalid-support", root)

                self.assertEqual("support.codex.state", error.field)

    def test_exception_support_requires_non_null_metadata(self) -> None:
        for index, field in enumerate(("reason", "owner", "test")):
            for mode in ("missing", "null"):
                with self.subTest(field=field, mode=mode):
                    root = self.copy_fixture(f"exception-{index}-{mode}")
                    descriptor = self.read_descriptor(root)
                    declaration = descriptor["support"]["codex"]
                    declaration.update(
                        {
                            "state": "exception",
                            "reason": "Reduced behavior is documented.",
                            "owner": "kinglet-maintainers",
                            "test": "tests.kinglet.test_loader",
                        }
                    )
                    if mode == "missing":
                        del declaration[field]
                    else:
                        declaration[field] = None
                    self.write_descriptor(descriptor, root)

                    error = self.assert_build_error("invalid-support", root)

                    self.assertEqual(f"support.codex.{field}", error.field)

    def test_rejects_missing_required_client_support(self) -> None:
        descriptor = self.read_descriptor()
        support = descriptor["support"]
        self.assertIsInstance(support, dict)
        del support["codex"]
        self.write_descriptor(descriptor)

        error = self.assert_build_error("missing-support")

        self.assertEqual("support.codex", error.field)

    def test_rejects_symlinked_descriptor_and_body(self) -> None:
        for index, relative_path in enumerate(
            (
                Path("src/roles/unity-scout/role.json"),
                Path("src/roles/unity-scout/instructions.md"),
            )
        ):
            with self.subTest(path=relative_path):
                root = self.copy_fixture(f"symlink-{index}")
                source = root / relative_path
                target = source.with_name(f"{source.name}.target")
                source.rename(target)
                source.symlink_to(target)

                error = self.assert_build_error("symlink-input", root)

                self.assertEqual(source, error.source)

    def test_rejects_non_utf8_descriptor_and_body(self) -> None:
        for index, relative_path in enumerate(
            (
                Path("src/roles/unity-scout/role.json"),
                Path("src/roles/unity-scout/instructions.md"),
            )
        ):
            with self.subTest(path=relative_path):
                root = self.copy_fixture(f"invalid-utf8-{index}")
                source = root / relative_path
                source.write_bytes(b"\xff")

                error = self.assert_build_error("invalid-utf8", root)

                self.assertEqual(source, error.source)

    def test_rejects_non_integer_schema_versions(self) -> None:
        for index, value in enumerate((True, "1", 1.0)):
            with self.subTest(value=value):
                root = self.copy_fixture(f"schema-{index}")
                descriptor = self.read_descriptor(root)
                descriptor["schema_version"] = value
                self.write_descriptor(descriptor, root)

                error = self.assert_build_error("invalid-schema-version", root)

                self.assertEqual("schema_version", error.field)

    def test_rejects_invalid_canonical_ids(self) -> None:
        invalid_ids = (
            "role.Unity-scout",
            "role.unity_scout",
            "workflow.unity-scout",
        )
        for index, unit_id in enumerate(invalid_ids):
            with self.subTest(unit_id=unit_id):
                root = self.copy_fixture(f"id-{index}")
                descriptor = self.read_descriptor(root)
                descriptor["id"] = unit_id
                self.write_descriptor(descriptor, root)

                error = self.assert_build_error("invalid-id", root)

                self.assertEqual("id", error.field)

    def test_loaded_graph_and_public_models_are_immutable(self) -> None:
        graph = load_graph(self.root)
        unit = graph.units["role.unity-scout"]
        declaration = unit.support["codex"]
        provenance = unit.provenance

        for value in (graph, unit, declaration, provenance):
            with self.subTest(model=type(value).__name__):
                self.assertTrue(value.__dataclass_params__.frozen)
        for model in (
            BuildError,
            CanonicalGraph,
            CanonicalUnit,
            SupportDeclaration,
            Provenance,
        ):
            with self.subTest(public_model=model.__name__):
                self.assertTrue(model.__dataclass_params__.frozen)

        with self.assertRaises(FrozenInstanceError):
            graph.root = Path("elsewhere")
        with self.assertRaises(TypeError):
            graph.units["role.other"] = unit
        with self.assertRaises(TypeError):
            unit.support["other"] = declaration
        with self.assertRaises(TypeError):
            unit.attributes["reasoning_tier"] = "deep"
        with self.assertRaises(TypeError):
            graph.support_policy["schema_version"] = 2

    def test_loads_exact_canonical_catalogs(self) -> None:
        graph = load_graph(self.root)

        self.assertEqual(
            frozenset(
                {
                    "delegate",
                    "filesystem.read",
                    "filesystem.write",
                    "shell",
                    "unity.read",
                    "unity.write",
                    "web",
                }
            ),
            graph.capabilities,
        )
        self.assertEqual(("claude", "codex"), graph.support_policy["required_clients"])
        self.assertEqual(
            ("supported", "unsupported", "exception"),
            graph.support_policy["states"],
        )
        self.assertEqual(
            ("reason", "owner", "test"),
            graph.support_policy["exception_requires"],
        )
        releases = graph.support_policy["releases"]
        self.assertEqual(
            {
                "linux": "supported",
                "macos": "supported",
                "windows": "unsupported",
            },
            dict(releases["3.0.0"]),
        )
        self.assertEqual((), graph.routes)

    def test_descriptor_discovery_order_is_deterministic(self) -> None:
        role_directory = self.descriptor().parent
        for slug in ("zeta-scout", "alpha-scout"):
            destination = role_directory.parent / slug
            shutil.copytree(role_directory, destination)
            descriptor_path = destination / "role.json"
            descriptor = json.loads(descriptor_path.read_text(encoding="utf-8"))
            descriptor["id"] = f"role.{slug}"
            descriptor_path.write_text(
                json.dumps(descriptor, indent=2) + "\n",
                encoding="utf-8",
            )

        first = load_graph(self.root)
        second = load_graph(self.root)

        expected = ("role.alpha-scout", "role.unity-scout", "role.zeta-scout")
        self.assertEqual(expected, tuple(first.units))
        self.assertEqual(tuple(first.units), tuple(second.units))


if __name__ == "__main__":
    unittest.main()
