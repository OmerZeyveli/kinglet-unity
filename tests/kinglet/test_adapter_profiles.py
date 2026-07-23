import json
from collections.abc import Mapping
from dataclasses import FrozenInstanceError
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile
from typing import get_type_hints
import unittest

from tools.kinglet_build.errors import BuildError
from tools.kinglet_build.loader import load_adapter_profiles
from tools.kinglet_build.model import AdapterProfile, CanonicalGraph
from tools.kinglet_build.renderers import (
    RenderedFile,
    Renderer,
    renderer_registry,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
LOGICAL_CAPABILITIES = {
    "delegate",
    "filesystem.read",
    "filesystem.write",
    "shell",
    "unity.read",
    "unity.write",
    "web",
}
REASONING_TIERS = {"fast", "balanced", "deep"}


class AdapterProfileTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name) / "repository"
        (self.root / "src" / "catalog").mkdir(parents=True)
        shutil.copy2(
            REPOSITORY_ROOT / "src" / "catalog" / "capabilities.json",
            self.root / "src" / "catalog" / "capabilities.json",
        )
        shutil.copytree(REPOSITORY_ROOT / "adapters", self.root / "adapters")

    def profile_path(self, client: str) -> Path:
        return self.root / "adapters" / client / "profile.json"

    def read_profile(self, client: str) -> dict[str, object]:
        return json.loads(self.profile_path(client).read_text(encoding="utf-8"))

    def write_profile(self, client: str, profile: dict[str, object]) -> None:
        self.profile_path(client).write_text(
            json.dumps(profile, indent=2) + "\n",
            encoding="utf-8",
        )

    def assert_profile_error(self, code: str) -> BuildError:
        with self.assertRaises(BuildError) as raised:
            load_adapter_profiles(self.root)
        self.assertEqual(code, raised.exception.code)
        self.assertEqual(
            f"{raised.exception.source}:{raised.exception.field}: "
            f"[{raised.exception.code}] {raised.exception.detail}",
            str(raised.exception),
        )
        return raised.exception

    def test_loads_complete_client_native_profiles(self) -> None:
        profiles = load_adapter_profiles(REPOSITORY_ROOT)

        self.assertEqual({"claude", "codex"}, set(profiles))
        for client, profile in profiles.items():
            with self.subTest(client=client):
                self.assertIsInstance(profile, AdapterProfile)
                self.assertEqual(client, profile.client)
                self.assertEqual("standard", profile.default_agent_profile)
                self.assertEqual({"standard", "frontier"}, set(profile.agent_profiles))
                self.assertEqual(LOGICAL_CAPABILITIES, set(profile.capabilities))
                for name in ("standard", "frontier"):
                    self.assertEqual(
                        REASONING_TIERS,
                        set(profile.agent_profiles[name]),
                    )

    def test_standard_and_frontier_model_mappings_are_exact(self) -> None:
        profiles = load_adapter_profiles(REPOSITORY_ROOT)
        claude = profiles["claude"].agent_profiles
        codex = profiles["codex"].agent_profiles

        self.assertEqual({"model": "haiku"}, dict(claude["standard"]["fast"]))
        self.assertEqual({"model": "sonnet"}, dict(claude["standard"]["balanced"]))
        self.assertEqual({"model": "opus"}, dict(claude["standard"]["deep"]))
        self.assertEqual(claude["standard"]["fast"], claude["frontier"]["fast"])
        self.assertEqual(
            claude["standard"]["balanced"],
            claude["frontier"]["balanced"],
        )
        self.assertEqual("fable", claude["frontier"]["deep"]["model"])

        self.assertEqual(
            {"model": "gpt-5.6-luna", "reasoning_effort": "medium"},
            dict(codex["standard"]["fast"]),
        )
        self.assertEqual(
            {"model": "gpt-5.6-terra", "reasoning_effort": "medium"},
            dict(codex["standard"]["balanced"]),
        )
        self.assertEqual(
            {"model": "gpt-5.6-sol", "reasoning_effort": "high"},
            dict(codex["standard"]["deep"]),
        )
        self.assertEqual(codex["standard"]["fast"], codex["frontier"]["fast"])
        self.assertEqual(
            codex["standard"]["balanced"],
            codex["frontier"]["balanced"],
        )
        self.assertEqual("gpt-5.6-sol", codex["frontier"]["deep"]["model"])
        self.assertEqual("max", codex["frontier"]["deep"]["reasoning_effort"])
        self.assertEqual(
            ("reasoning.mode.pro",),
            codex["frontier"]["deep"]["requires_native_capabilities"],
        )

    def test_profiles_use_client_native_capability_surfaces(self) -> None:
        profiles = load_adapter_profiles(REPOSITORY_ROOT)

        self.assertEqual(
            {
                "filesystem.read": ("Read", "Glob", "Grep"),
                "filesystem.write": ("Write", "Edit"),
                "shell": ("Bash",),
                "delegate": ("Agent",),
                "unity.read": ("mcp__unityMCP__*",),
                "unity.write": ("mcp__unityMCP__*",),
                "web": ("WebSearch", "WebFetch"),
            },
            dict(profiles["claude"].capabilities),
        )
        self.assertEqual(
            {
                "filesystem.read": ("sandboxed-command",),
                "filesystem.write": ("sandboxed-command",),
                "shell": ("sandboxed-command",),
                "delegate": ("agent-delegation",),
                "unity.read": ("mcp-for-unity@10.1.0",),
                "unity.write": ("mcp-for-unity@10.1.0",),
                "web": ("web-access",),
            },
            dict(profiles["codex"].capabilities),
        )

    def test_output_roots_name_all_four_products_without_overlap(self) -> None:
        profiles = load_adapter_profiles(REPOSITORY_ROOT)

        self.assertEqual(
            {
                "package": PurePosixPath("packages/claude"),
                "compatibility": PurePosixPath(".claude"),
            },
            dict(profiles["claude"].output_roots),
        )
        self.assertEqual(
            {
                "plugin": PurePosixPath("plugins/kinglet-unity"),
                "project": PurePosixPath("packages/codex-project"),
            },
            dict(profiles["codex"].output_roots),
        )

    def test_linter_low_effort_candidate_is_non_shipping_metadata(self) -> None:
        codex = self.read_profile("codex")
        metadata = codex["metadata"]
        self.assertIsInstance(metadata, dict)
        candidates = metadata["evaluation_candidates"]

        self.assertEqual(
            [
                {
                    "role": "unity-linter",
                    "model": "gpt-5.6-luna",
                    "reasoning_effort": "low",
                    "shipping": False,
                    "adoption_gate": (
                        "plan-06-equal-correctness-evidence-and-improved-efficiency"
                    ),
                }
            ],
            candidates,
        )
        self.assertNotIn("unity-scout", json.dumps(candidates))
        profiles = load_adapter_profiles(self.root)
        self.assertEqual(
            "medium",
            profiles["codex"].agent_profiles["standard"]["fast"][
                "reasoning_effort"
            ],
        )

    def test_profile_models_and_nested_mappings_are_immutable(self) -> None:
        profiles = load_adapter_profiles(REPOSITORY_ROOT)
        profile = profiles["codex"]

        self.assertTrue(profile.__dataclass_params__.frozen)
        with self.assertRaises(FrozenInstanceError):
            profile.client = "other"
        with self.assertRaises(TypeError):
            profiles["codex"] = profile
        with self.assertRaises(TypeError):
            profile.agent_profiles["standard"] = {}
        with self.assertRaises(TypeError):
            profile.agent_profiles["standard"]["fast"]["model"] = "other"
        with self.assertRaises(TypeError):
            profile.capabilities["shell"] = ("other",)
        with self.assertRaises(TypeError):
            profile.output_roots["plugin"] = PurePosixPath("other")

    def test_rejects_missing_and_extra_adapter_clients(self) -> None:
        shutil.rmtree(self.root / "adapters" / "codex")
        self.assert_profile_error("missing-adapter")

        shutil.copytree(
            REPOSITORY_ROOT / "adapters" / "codex",
            self.root / "adapters" / "codex",
        )
        extra = self.read_profile("codex")
        extra["client"] = "gemini"
        extra_path = self.root / "adapters" / "gemini"
        extra_path.mkdir()
        (extra_path / "profile.json").write_text(
            json.dumps(extra, indent=2) + "\n",
            encoding="utf-8",
        )
        self.assert_profile_error("extra-adapter")

    def test_rejects_non_standard_default_and_undeclared_model_defaults(self) -> None:
        claude = self.read_profile("claude")
        claude["default_agent_profile"] = "frontier"
        self.write_profile("claude", claude)
        self.assert_profile_error("invalid-agent-profile")

        claude = json.loads(
            (REPOSITORY_ROOT / "adapters" / "claude" / "profile.json").read_text(
                encoding="utf-8"
            )
        )
        claude["global_default_model"] = "opus"
        self.write_profile("claude", claude)
        error = self.assert_profile_error("unknown-field")
        self.assertEqual("global_default_model", error.field)

    def test_rejects_unknown_profile_names_and_tier_sets(self) -> None:
        cases = (
            (
                "unknown-profile",
                lambda profiles: profiles.update(
                    {"preview": profiles["standard"]}
                ),
            ),
            ("missing-tier", lambda profiles: profiles["standard"].pop("fast")),
            (
                "extra-tier",
                lambda profiles: profiles["standard"].update(
                    {"extreme": profiles["standard"]["deep"]}
                ),
            ),
        )
        for name, mutate in cases:
            with self.subTest(name=name):
                claude = self.read_profile("claude")
                mutate(claude["agent_profiles"])
                self.write_profile("claude", claude)
                self.assert_profile_error("invalid-agent-profile")
                shutil.copy2(
                    REPOSITORY_ROOT / "adapters" / "claude" / "profile.json",
                    self.profile_path("claude"),
                )

    def test_rejects_missing_and_unknown_logical_capabilities(self) -> None:
        for name, mutate in (
            ("missing", lambda capabilities: capabilities.pop("web")),
            ("unknown", lambda capabilities: capabilities.update({"unity.teleport": ["x"]})),
        ):
            with self.subTest(name=name):
                claude = self.read_profile("claude")
                mutate(claude["capabilities"])
                self.write_profile("claude", claude)
                self.assert_profile_error("unknown-capability")
                shutil.copy2(
                    REPOSITORY_ROOT / "adapters" / "claude" / "profile.json",
                    self.profile_path("claude"),
                )

    def test_rejects_frontier_fast_or_balanced_drift(self) -> None:
        for tier in ("fast", "balanced"):
            with self.subTest(tier=tier):
                claude = self.read_profile("claude")
                claude["agent_profiles"]["frontier"][tier]["model"] = "other"
                self.write_profile("claude", claude)
                error = self.assert_profile_error("invalid-frontier")
                self.assertEqual(f"agent_profiles.frontier.{tier}", error.field)
                shutil.copy2(
                    REPOSITORY_ROOT / "adapters" / "claude" / "profile.json",
                    self.profile_path("claude"),
                )

    def test_rejects_frontier_deep_mapping_that_violates_native_contract(self) -> None:
        mutations = (
            ("claude-model", "claude", "model", "other"),
            ("codex-model", "codex", "model", "other"),
            ("codex-effort", "codex", "reasoning_effort", "high"),
            ("codex-pro", "codex", "requires_native_capabilities", []),
        )
        for name, client, field, value in mutations:
            with self.subTest(name=name):
                profile = self.read_profile(client)
                profile["agent_profiles"]["frontier"]["deep"][field] = value
                self.write_profile(client, profile)
                error = self.assert_profile_error("invalid-frontier")
                self.assertEqual("agent_profiles.frontier.deep", error.field)
                shutil.copy2(
                    REPOSITORY_ROOT / "adapters" / client / "profile.json",
                    self.profile_path(client),
                )

    def test_rejects_frontier_tampering_even_when_both_profile_copies_match(
        self,
    ) -> None:
        cases = (
            ("claude-model", "claude", "model", "other"),
            ("claude-capability", "claude", "requires_native_capabilities", []),
            ("codex-model", "codex", "model", "other"),
            ("codex-effort", "codex", "reasoning_effort", "high"),
            ("codex-capability", "codex", "requires_native_capabilities", []),
        )
        for name, client, field, value in cases:
            with self.subTest(name=name):
                profile = self.read_profile(client)
                profile["agent_profiles"]["frontier"]["deep"][field] = value
                profile["metadata"]["frontier_deep_contract"][field] = value
                self.write_profile(client, profile)

                error = self.assert_profile_error("invalid-frontier")

                self.assertEqual("metadata.frontier_deep_contract", error.field)
                shutil.copy2(
                    REPOSITORY_ROOT / "adapters" / client / "profile.json",
                    self.profile_path(client),
                )

    def test_rejects_direct_native_config_schema_tampering_at_its_field(
        self,
    ) -> None:
        codex = self.read_profile("codex")
        codex["metadata"]["native_config_schema"]["reasoning_effort"][
            "allowed_values"
        ].append("ultra")
        self.write_profile("codex", codex)

        error = self.assert_profile_error("invalid-native-config")

        self.assertEqual("metadata.native_config_schema", error.field)
        self.assertEqual(
            "native configuration schema failed independent authority validation",
            error.detail,
        )

    def test_maintainer_command_recomputes_both_authority_fingerprints(
        self,
    ) -> None:
        command = REPOSITORY_ROOT / "scripts" / "recompute-adapter-authorities.py"
        self.assertTrue(command.is_file(), "maintainer recomputation command is required")
        self.assertTrue(command.stat().st_mode & 0o111, "maintainer command must be executable")

        completed = subprocess.run(
            [sys.executable, str(command)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        fingerprints = json.loads(completed.stdout)
        import tools.kinglet_build.validator as validator

        self.assertEqual("", completed.stderr)
        self.assertEqual(
            {"frontier_deep_contract", "native_config_schema"},
            set(fingerprints["claude"]),
        )
        self.assertEqual(
            {"frontier_deep_contract", "native_config_schema"},
            set(fingerprints["codex"]),
        )
        self.assertEqual(validator._ADAPTER_AUTHORITY_SHA256, fingerprints)

    def test_rejects_client_inappropriate_reasoning_effort_presence(self) -> None:
        claude = self.read_profile("claude")
        claude["agent_profiles"]["standard"]["fast"][
            "reasoning_effort"
        ] = "medium"
        self.write_profile("claude", claude)
        error = self.assert_profile_error("invalid-native-config")
        self.assertEqual(
            "agent_profiles.standard.fast.reasoning_effort",
            error.field,
        )

        shutil.copy2(
            REPOSITORY_ROOT / "adapters" / "claude" / "profile.json",
            self.profile_path("claude"),
        )
        codex = self.read_profile("codex")
        del codex["agent_profiles"]["standard"]["fast"]["reasoning_effort"]
        self.write_profile("codex", codex)
        error = self.assert_profile_error("invalid-native-config")
        self.assertEqual(
            "agent_profiles.standard.fast.reasoning_effort",
            error.field,
        )

    def test_rejects_unknown_codex_reasoning_effort(self) -> None:
        codex = self.read_profile("codex")
        codex["agent_profiles"]["standard"]["fast"][
            "reasoning_effort"
        ] = "ultra"
        self.write_profile("codex", codex)

        error = self.assert_profile_error("invalid-native-config")

        self.assertEqual(
            "agent_profiles.standard.fast.reasoning_effort",
            error.field,
        )

    def test_rejects_client_inappropriate_native_capability_placement(self) -> None:
        claude = self.read_profile("claude")
        claude["agent_profiles"]["standard"]["fast"][
            "requires_native_capabilities"
        ] = ["model.fable.available"]
        self.write_profile("claude", claude)

        error = self.assert_profile_error("invalid-native-config")

        self.assertEqual(
            "agent_profiles.standard.fast.requires_native_capabilities",
            error.field,
        )

    def test_rejects_invalid_native_capability_shape_stably(self) -> None:
        codex = self.read_profile("codex")
        codex["agent_profiles"]["standard"]["deep"][
            "requires_native_capabilities"
        ] = "reasoning.mode.pro"
        self.write_profile("codex", codex)

        error = self.assert_profile_error("invalid-native-capability")

        self.assertEqual(
            "agent_profiles.standard.deep.requires_native_capabilities",
            error.field,
        )

    def test_rejects_max_effort_without_native_capability(self) -> None:
        codex = self.read_profile("codex")
        codex["agent_profiles"]["standard"]["deep"]["reasoning_effort"] = "max"
        self.write_profile("codex", codex)

        error = self.assert_profile_error("invalid-native-capability")

        self.assertEqual("agent_profiles.standard.deep", error.field)

    def test_rejects_prompt_text_fields_instead_of_emulating_native_pro(self) -> None:
        codex = self.read_profile("codex")
        codex["agent_profiles"]["frontier"]["deep"]["prompt_text"] = (
            "Emulate Pro by thinking harder."
        )
        self.write_profile("codex", codex)

        error = self.assert_profile_error("unknown-field")

        self.assertEqual("agent_profiles.frontier.deep.prompt_text", error.field)

    def test_rejects_unsafe_and_overlapping_output_roots(self) -> None:
        cases = (
            ("absolute", "claude", "/tmp/kinglet"),
            ("parent", "claude", "packages/../escape"),
            ("same-client-overlap", "claude", "packages/claude/nested"),
            ("cross-client-overlap", "codex", "packages/claude/nested"),
        )
        for name, client, path in cases:
            with self.subTest(name=name):
                profile = self.read_profile(client)
                if name == "same-client-overlap":
                    profile["output_roots"]["compatibility"] = path
                else:
                    first_root = next(iter(profile["output_roots"]))
                    profile["output_roots"][first_root] = path
                self.write_profile(client, profile)
                expected = (
                    "overlapping-output-root"
                    if name.endswith("overlap")
                    else "invalid-output-root"
                )
                self.assert_profile_error(expected)
                shutil.copy2(
                    REPOSITORY_ROOT / "adapters" / client / "profile.json",
                    self.profile_path(client),
                )

    def test_canonical_and_production_sources_contain_no_native_model_facts(self) -> None:
        forbidden = (
            "hai" + "ku",
            "son" + "net",
            "op" + "us",
            "fa" + "ble",
            "gpt-5.6" + "-",
            "reasoning.mode." + "pro",
        )
        offenders: list[str] = []
        for root_name in ("src", "tools"):
            for source in sorted((REPOSITORY_ROOT / root_name).rglob("*")):
                if not source.is_file() or "__pycache__" in source.parts:
                    continue
                try:
                    text = source.read_text(encoding="utf-8")
                except UnicodeDecodeError:
                    continue
                if any(term in text.casefold() for term in forbidden):
                    offenders.append(source.relative_to(REPOSITORY_ROOT).as_posix())

        self.assertEqual([], offenders)

    def test_active_sources_contain_no_deprecated_codex_mapping(self) -> None:
        deprecated = "gpt-5.3" + "-codex"
        excluded_roots = {".git", ".superpowers", "docs", "migration"}
        offenders: list[str] = []
        for source in sorted(REPOSITORY_ROOT.rglob("*")):
            relative = source.relative_to(REPOSITORY_ROOT)
            if (
                not source.is_file()
                or relative.parts[0] in excluded_roots
                or "__pycache__" in relative.parts
            ):
                continue
            try:
                text = source.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            if deprecated in text:
                offenders.append(relative.as_posix())

        self.assertEqual([], offenders)

    def test_loader_exposes_no_main_session_model_selector(self) -> None:
        import tools.kinglet_build.loader as loader

        forbidden_api_names = {
            "set_active_model",
            "set_default_model",
            "set_global_model",
            "set_main_model",
            "set_session_model",
        }
        self.assertTrue(forbidden_api_names.isdisjoint(dir(loader)))


class RendererContractTests(unittest.TestCase):
    def test_registry_is_empty_until_content_renderers_are_added(self) -> None:
        self.assertEqual({}, renderer_registry())
        self.assertTrue(hasattr(Renderer, "render"))
        annotations = get_type_hints(Renderer.render)
        self.assertIs(annotations["graph"], CanonicalGraph)
        self.assertIs(annotations["profile"], AdapterProfile)
        self.assertEqual(
            Mapping[str, tuple[RenderedFile, ...]],
            annotations["return"],
        )

    def test_rendered_file_is_frozen_and_accepts_safe_relative_paths(self) -> None:
        rendered = RenderedFile(
            path=PurePosixPath("agents/unity-scout.md"),
            content=b"body\n",
            source_ids=("role.unity-scout",),
        )

        self.assertTrue(rendered.__dataclass_params__.frozen)
        with self.assertRaises(FrozenInstanceError):
            rendered.content = b"other"

    def test_rendered_file_rejects_absolute_and_parent_paths(self) -> None:
        for path in (
            PurePosixPath("/agents/unity-scout.md"),
            PurePosixPath("agents/../escape.md"),
        ):
            with self.subTest(path=path):
                with self.assertRaises(ValueError):
                    RenderedFile(path=path, content=b"", source_ids=())

    def test_rendered_file_rejects_paths_without_a_file_component(self) -> None:
        for path in (PurePosixPath(), PurePosixPath(".")):
            with self.subTest(path=path):
                with self.assertRaises(ValueError):
                    RenderedFile(path=path, content=b"", source_ids=())


if __name__ == "__main__":
    unittest.main()
