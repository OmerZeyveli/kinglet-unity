from contextlib import redirect_stderr, redirect_stdout
import importlib
import importlib.util
from io import StringIO
import json
from pathlib import Path, PurePosixPath
import shutil
import tempfile
import unittest
from unittest import mock

from tools.kinglet_build.renderers import RenderedFile


REPOSITORY_ROOT = Path(__file__).parents[2]
FIXTURES = Path(__file__).parent / "fixtures"


class FakeRenderer:
    def __init__(self, client: str, calls: list[str] | None = None) -> None:
        self.client = client
        self.calls = calls

    def render(self, graph, profile) -> tuple[RenderedFile, ...]:
        if self.calls is not None:
            self.calls.append(self.client)
        return (
            RenderedFile(
                path=PurePosixPath("artifact.md"),
                content=f"{self.client}\r\n".encode(),
                source_ids=("role.unity-scout",),
            ),
        )


class CliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name) / "repository"
        shutil.copytree(FIXTURES / "valid-minimal", self.root)
        shutil.copytree(REPOSITORY_ROOT / "adapters", self.root / "adapters")

    def cli(self):
        specification = importlib.util.find_spec("tools.kinglet_build.cli")
        self.assertIsNotNone(
            specification,
            "tools.kinglet_build.cli must implement the public command contract",
        )
        return importlib.import_module("tools.kinglet_build.cli")

    def invoke(self, argv: list[str]) -> tuple[int, str, str]:
        cli = self.cli()
        stdout = StringIO()
        stderr = StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            exit_code = cli.main(argv, repository_root=self.root)
        return exit_code, stdout.getvalue(), stderr.getvalue()

    def test_validate_reports_stable_summary_to_stdout(self) -> None:
        exit_code, stdout, stderr = self.invoke(["validate"])

        self.assertEqual(0, exit_code)
        self.assertEqual(
            "Validated 4 canonical units, 0 routes, 2 adapters.\n",
            stdout,
        )
        self.assertEqual("", stderr)

    def test_schema_or_graph_error_exits_two_and_uses_stderr(self) -> None:
        catalog = self.root / "src" / "catalog" / "routing.json"
        data = json.loads(catalog.read_text(encoding="utf-8"))
        data["schema_version"] = 2
        catalog.write_text(json.dumps(data) + "\n", encoding="utf-8")

        exit_code, stdout, stderr = self.invoke(["validate"])

        self.assertEqual(2, exit_code)
        self.assertEqual("", stdout)
        self.assertIn("[invalid-schema-version]", stderr)
        self.assertTrue(stderr.startswith("validation error: "))

    def test_empty_registry_builds_no_products_and_reports_zero_files(self) -> None:
        cli = self.cli()
        with mock.patch.object(cli, "renderer_registry", return_value={}):
            exit_code, stdout, stderr = self.invoke(["build", "--all"])

        self.assertEqual(0, exit_code)
        self.assertEqual("Built 0 rendered files.\n", stdout)
        self.assertEqual("", stderr)
        for relative in (
            ".claude",
            "packages/claude",
            "packages/codex-project",
            "plugins/kinglet-unity",
        ):
            self.assertFalse((self.root / relative).exists())

    def test_build_all_loads_once_renders_in_client_order_and_writes_four_roots(self) -> None:
        cli = self.cli()
        calls: list[str] = []
        destinations: list[Path] = []
        registry = {
            "codex": FakeRenderer("codex", calls),
            "claude": FakeRenderer("claude", calls),
        }

        def record_write(files, destination, *, check):
            self.assertFalse(check)
            self.assertEqual(1, len(files))
            destinations.append(destination)
            return cli.WriteResult(changed=(), stale=())

        with (
            mock.patch.object(cli, "renderer_registry", return_value=registry),
            mock.patch.object(cli, "load_graph", wraps=cli.load_graph) as load_graph,
            mock.patch.object(
                cli,
                "load_adapter_profiles",
                wraps=cli.load_adapter_profiles,
            ) as load_profiles,
            mock.patch.object(
                cli,
                "validate_graph",
                wraps=cli.validate_graph,
            ) as validate_graph,
            mock.patch.object(cli, "write_product", side_effect=record_write),
        ):
            exit_code, stdout, stderr = self.invoke(["build", "--all"])

        self.assertEqual(0, exit_code)
        self.assertEqual(["claude", "codex"], calls)
        self.assertEqual(1, load_graph.call_count)
        self.assertEqual(1, load_profiles.call_count)
        self.assertEqual(1, validate_graph.call_count)
        self.assertEqual(
            {
                self.root / ".claude",
                self.root / "packages" / "claude",
                self.root / "packages" / "codex-project",
                self.root / "plugins" / "kinglet-unity",
            },
            set(destinations),
        )
        self.assertEqual("Built 2 rendered files.\n", stdout)
        self.assertEqual("", stderr)

    def test_check_clean_exits_zero_without_modifying_products(self) -> None:
        cli = self.cli()
        registry = {"claude": FakeRenderer("claude")}
        with mock.patch.object(cli, "renderer_registry", return_value=registry):
            built = self.invoke(["build", "--claude"])
            package_artifact = self.root / "packages" / "claude" / "artifact.md"
            before = package_artifact.stat().st_mtime_ns
            checked = self.invoke(["build", "--claude", "--check"])

        self.assertEqual((0, "Built 1 rendered file.\n", ""), built)
        self.assertEqual((0, "Checked 1 rendered file.\n", ""), checked)
        self.assertEqual(before, package_artifact.stat().st_mtime_ns)

    def test_generated_drift_in_check_exits_three(self) -> None:
        cli = self.cli()
        registry = {"claude": FakeRenderer("claude")}
        with mock.patch.object(cli, "renderer_registry", return_value=registry):
            self.invoke(["build", "--claude"])
            artifact = self.root / "packages" / "claude" / "artifact.md"
            artifact.write_bytes(b"drift\n")
            exit_code, stdout, stderr = self.invoke(
                ["build", "--claude", "--check"]
            )

        self.assertEqual(3, exit_code)
        self.assertEqual("Checked 1 rendered file.\n", stdout)
        self.assertEqual(
            "generated drift: packages/claude/artifact.md (changed)\n",
            stderr,
        )
        self.assertEqual(b"drift\n", artifact.read_bytes())

    def test_usage_errors_exit_sixty_four_and_use_stderr(self) -> None:
        cases = (
            [],
            ["validate", "--all"],
            ["build"],
            ["build", "--all", "--claude"],
            ["build", "--codex", "extra"],
        )
        for argv in cases:
            with self.subTest(argv=argv):
                exit_code, stdout, stderr = self.invoke(list(argv))
                self.assertEqual(64, exit_code)
                self.assertEqual("", stdout)
                self.assertTrue(stderr.startswith("usage error: "))

    def test_unexpected_io_error_exits_seventy_four(self) -> None:
        cli = self.cli()
        with mock.patch.object(
            cli,
            "load_graph",
            side_effect=OSError(5, "simulated I/O failure"),
        ):
            exit_code, stdout, stderr = self.invoke(["validate"])

        self.assertEqual(74, exit_code)
        self.assertEqual("", stdout)
        self.assertEqual(
            "I/O error: [Errno 5] simulated I/O failure\n",
            stderr,
        )


if __name__ == "__main__":
    unittest.main()
