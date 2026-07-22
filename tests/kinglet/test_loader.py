import json
from pathlib import Path
import shutil
import tempfile
import unittest

from tools.kinglet_build.errors import BuildError
from tools.kinglet_build.loader import load_graph
from tools.kinglet_build.model import CanonicalUnit


FIXTURES = Path(__file__).parent / "fixtures"


class LoaderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name) / "repository"
        shutil.copytree(FIXTURES / "valid-minimal", self.root)

    def descriptor(self) -> Path:
        return self.root / "src" / "roles" / "unity-scout" / "role.json"

    def read_descriptor(self) -> dict[str, object]:
        return json.loads(self.descriptor().read_text(encoding="utf-8"))

    def write_descriptor(self, descriptor: dict[str, object]) -> None:
        self.descriptor().write_text(
            json.dumps(descriptor, indent=2) + "\n",
            encoding="utf-8",
        )

    def assert_build_error(self, code: str) -> BuildError:
        with self.assertRaises(BuildError) as raised:
            load_graph(self.root)
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

    def test_rejects_missing_required_client_support(self) -> None:
        descriptor = self.read_descriptor()
        support = descriptor["support"]
        self.assertIsInstance(support, dict)
        del support["codex"]
        self.write_descriptor(descriptor)

        error = self.assert_build_error("missing-support")

        self.assertEqual("support.codex", error.field)


if __name__ == "__main__":
    unittest.main()
