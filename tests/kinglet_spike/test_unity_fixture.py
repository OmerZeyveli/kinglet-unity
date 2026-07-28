"""test_unity_fixture.py — Structural and content assertions for the pinned Unity fixture.

Task 2 of the 00U plan freezes a minimal, disposable Unity project under
spikes/platform/unity/fixture/ plus the MCP package lock at
spikes/platform/unity/mcp.lock.json. Nothing here launches Unity — these are
committed-text assertions only, in the same spirit as test_client_fixture.py.

Version-pin note: the plan's literal text says "Unity Editor 6000.3.11f1
exactly". That literal is RELAXED by standing user ruling (see
spikes/platform/unity/contracts/routes-v1.json's unity_version note): any
well-formed Unity 6000.x line is acceptable, but the fixture must record
the EXACT version (and revision hash) it was actually created with. This
fixture was produced by real `-createProject` batchmode on Unity
6000.3.18f1 (5ebeb53e4c07); that is what these tests pin, not 6000.3.11f1.

Covers:
  - ProjectVersion.txt: exact m_EditorVersion / m_EditorVersionWithRevision,
    and that both fields satisfy the shape-only Unity-version regex the
    receipt parser (tools/kinglet_spike/unity/receipt.py) already binds.
  - Packages/manifest.json: valid JSON, exact MCP package URL/tag, and
    presence of com.unity.test-framework.
  - mcp.lock.json: valid JSON, package name/version, exact upstream tag and
    commit, MIT license, and the CLI/resources list (instances,
    get_editor_state, read_console, run_tests). Cross-checked against the
    manifest's own #v9.7.1 URL fragment so the two locks cannot drift.
  - Both .asmdef files: name, rootNamespace, includePlatforms, references,
    optionalUnityReferences.
  - KingletSpikeProbe.cs: ProjectId constant bound to the frozen
    PROJECT_ID from tools.kinglet_spike.unity.model, the fixture receipt
    schema string, and that the probe touches no network API and no
    absolute/outside-project file path.
  - KingletSpikeTests.cs: exactly one [Test] method, and it asserts against
    Probe.ProjectId (not a copy of the literal).
  - .meta completeness: every asset under Assets/ has exactly one sibling
    .meta file, no orphan .meta, and every guid in the fixture tree is
    unique.
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

from tools.kinglet_spike.unity.model import PROJECT_ID
from tools.kinglet_spike.unity.receipt import _UNITY_VERSION_RE

_REPO_ROOT = Path(__file__).resolve().parents[2]
_FIXTURE = _REPO_ROOT / "spikes" / "platform" / "unity" / "fixture"
_LOCK_PATH = _REPO_ROOT / "spikes" / "platform" / "unity" / "mcp.lock.json"

_EXPECTED_EDITOR_VERSION = "6000.3.18f1"
_EXPECTED_EDITOR_REVISION = "5ebeb53e4c07"

_PROJECT_VERSION_TEXT = (_FIXTURE / "ProjectSettings" / "ProjectVersion.txt").read_text(encoding="utf-8")
_MANIFEST_TEXT = (_FIXTURE / "Packages" / "manifest.json").read_text(encoding="utf-8")
_MANIFEST = json.loads(_MANIFEST_TEXT)
_LOCK_TEXT = _LOCK_PATH.read_text(encoding="utf-8")
_LOCK = json.loads(_LOCK_TEXT)

_EDITOR_ASMDEF_PATH = _FIXTURE / "Assets" / "KingletSpike" / "Editor" / "KingletSpike.Editor.asmdef"
_TESTS_ASMDEF_PATH = _FIXTURE / "Assets" / "KingletSpike" / "Tests" / "Editor" / "KingletSpike.Tests.asmdef"
_EDITOR_ASMDEF = json.loads(_EDITOR_ASMDEF_PATH.read_text(encoding="utf-8"))
_TESTS_ASMDEF = json.loads(_TESTS_ASMDEF_PATH.read_text(encoding="utf-8"))

_PROBE_CS_PATH = _FIXTURE / "Assets" / "KingletSpike" / "Editor" / "KingletSpikeProbe.cs"
_TESTS_CS_PATH = _FIXTURE / "Assets" / "KingletSpike" / "Tests" / "Editor" / "KingletSpikeTests.cs"
_PROBE_CS = _PROBE_CS_PATH.read_text(encoding="utf-8")
_TESTS_CS = _TESTS_CS_PATH.read_text(encoding="utf-8")

_FIXTURE_RECEIPT_SCHEMA = "kinglet.unity-fixture/v1"

_GUID_RE = re.compile(r"^guid: ([0-9a-f]{32})$", re.MULTILINE)


# ---------------------------------------------------------------------------
# ProjectVersion.txt
# ---------------------------------------------------------------------------

class ProjectVersionTests(unittest.TestCase):
    def test_exact_editor_version_line(self):
        self.assertIn(f"m_EditorVersion: {_EXPECTED_EDITOR_VERSION}", _PROJECT_VERSION_TEXT)

    def test_exact_editor_version_with_revision_line(self):
        self.assertIn(
            f"m_EditorVersionWithRevision: {_EXPECTED_EDITOR_VERSION} ({_EXPECTED_EDITOR_REVISION})",
            _PROJECT_VERSION_TEXT,
        )

    def test_two_lines_only(self):
        # A one-line ProjectVersion.txt hid a real bug elsewhere in this repo
        # (per CLAUDE.md) -- Unity always writes both fields.
        lines = [line for line in _PROJECT_VERSION_TEXT.splitlines() if line.strip()]
        self.assertEqual(2, len(lines))

    def test_editor_version_matches_shape_only_regex(self):
        # Binds this fixture to the same shape rule the receipt parser enforces,
        # so the two cannot silently diverge.
        self.assertRegex(_EXPECTED_EDITOR_VERSION, _UNITY_VERSION_RE.pattern)
        m = re.search(r"^m_EditorVersion: (\S+)$", _PROJECT_VERSION_TEXT, re.MULTILINE)
        self.assertIsNotNone(m)
        self.assertTrue(_UNITY_VERSION_RE.match(m.group(1)))

    def test_not_the_relaxed_literal_pin(self):
        # Documents the deviation from the plan's literal text explicitly,
        # rather than leaving it implicit in what the file happens to say.
        self.assertNotEqual("6000.3.11f1", _EXPECTED_EDITOR_VERSION)


# ---------------------------------------------------------------------------
# Packages/manifest.json
# ---------------------------------------------------------------------------

class ManifestTests(unittest.TestCase):
    def test_manifest_is_valid_json_object(self):
        self.assertIsInstance(_MANIFEST, dict)

    def test_manifest_pins_exact_mcp_package_url(self):
        deps = _MANIFEST.get("dependencies", {})
        self.assertEqual(
            "https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#v9.7.1",
            deps.get("com.coplaydev.unity-mcp"),
        )

    def test_manifest_pins_test_framework(self):
        deps = _MANIFEST.get("dependencies", {})
        self.assertIn("com.unity.test-framework", deps)


# ---------------------------------------------------------------------------
# mcp.lock.json
# ---------------------------------------------------------------------------

class McpLockTests(unittest.TestCase):
    def test_lock_is_valid_json_object(self):
        self.assertIsInstance(_LOCK, dict)

    def test_package_name_and_version(self):
        package = _LOCK.get("package", {})
        self.assertEqual("com.coplaydev.unity-mcp", package.get("name"))
        self.assertEqual("9.7.1", package.get("version"))

    def test_package_url_matches_manifest(self):
        # The lock and the manifest must never drift against each other.
        package = _LOCK.get("package", {})
        deps = _MANIFEST.get("dependencies", {})
        self.assertEqual(deps.get("com.coplaydev.unity-mcp"), package.get("package_url"))

    def test_exact_upstream_tag(self):
        upstream = _LOCK.get("upstream", {})
        self.assertEqual("v9.7.1", upstream.get("tag"))

    def test_tag_matches_manifest_url_fragment(self):
        upstream = _LOCK.get("upstream", {})
        deps = _MANIFEST.get("dependencies", {})
        url = deps.get("com.coplaydev.unity-mcp", "")
        self.assertTrue(url.endswith("#" + upstream.get("tag", "\0")))

    def test_exact_upstream_commit(self):
        # git ls-remote https://github.com/CoplayDev/unity-mcp.git v9.7.1 peeled
        # to this commit (annotated tag dereference) at the time this fixture
        # was written.
        upstream = _LOCK.get("upstream", {})
        self.assertEqual("78ee5418415953b79c358bfe6355fcc3fde7912b", upstream.get("commit"))
        self.assertRegex(upstream.get("commit", ""), r"^[0-9a-f]{40}$")

    def test_mit_license(self):
        upstream = _LOCK.get("upstream", {})
        self.assertEqual("MIT", upstream.get("license"))

    def test_server_project_version(self):
        server = _LOCK.get("server", {})
        self.assertEqual("9.7.1", server.get("project_version"))

    def test_cli_resources_are_exactly_the_four_used(self):
        self.assertEqual(
            ["instances", "get_editor_state", "read_console", "run_tests"],
            _LOCK.get("cli_resources"),
        )


# ---------------------------------------------------------------------------
# .asmdef files
# ---------------------------------------------------------------------------

class AsmdefTests(unittest.TestCase):
    def test_editor_asmdef_shape(self):
        self.assertEqual("KingletSpike.Editor", _EDITOR_ASMDEF.get("name"))
        self.assertEqual("KingletSpike", _EDITOR_ASMDEF.get("rootNamespace"))
        self.assertEqual(["Editor"], _EDITOR_ASMDEF.get("includePlatforms"))
        # The Editor assembly must not reference the Tests assembly -- that
        # direction would make production code depend on test code.
        self.assertNotIn("references", _EDITOR_ASMDEF)

    def test_tests_asmdef_shape(self):
        self.assertEqual("KingletSpike.Tests", _TESTS_ASMDEF.get("name"))
        self.assertEqual("KingletSpike.Tests", _TESTS_ASMDEF.get("rootNamespace"))
        self.assertEqual(["Editor"], _TESTS_ASMDEF.get("includePlatforms"))
        self.assertEqual(["KingletSpike.Editor"], _TESTS_ASMDEF.get("references"))
        self.assertEqual(["TestAssemblies"], _TESTS_ASMDEF.get("optionalUnityReferences"))


# ---------------------------------------------------------------------------
# KingletSpikeProbe.cs
# ---------------------------------------------------------------------------

class ProbeCsTests(unittest.TestCase):
    def test_project_id_matches_frozen_contract(self):
        # Binds Task 2's fixture to Task 1's frozen PROJECT_ID -- if either
        # changes without the other, this fails instead of silently drifting.
        self.assertIn(f'ProjectId = "{PROJECT_ID}";', _PROBE_CS)

    def test_fixture_receipt_schema_is_distinct_from_the_route_receipt_schema(self):
        # kinglet.unity-fixture/v1 marks "this fixture booted", which is a
        # different claim from kinglet.unity-probe.receipt/v1 (a route run).
        from tools.kinglet_spike.unity.model import RECEIPT_SCHEMA as ROUTE_RECEIPT_SCHEMA
        self.assertIn(f'\\"schema\\":\\"{_FIXTURE_RECEIPT_SCHEMA}\\"', _PROBE_CS)
        self.assertNotEqual(ROUTE_RECEIPT_SCHEMA, _FIXTURE_RECEIPT_SCHEMA)

    def test_write_receipt_menu_item_present(self):
        self.assertIn('[MenuItem("Kinglet Spike/Write Receipt")]', _PROBE_CS)
        self.assertIn("public static void WriteReceipt()", _PROBE_CS)

    def test_exit_without_saving_menu_item_present(self):
        self.assertIn('[MenuItem("Kinglet Spike/Exit Without Saving")]', _PROBE_CS)

    def test_receipt_path_is_relative_under_library(self):
        self.assertIn('Path.Combine("Library", "KingletSpike")', _PROBE_CS)

    def test_no_network_api(self):
        forbidden = (
            "System.Net", "UnityWebRequest", "WebClient", "HttpClient",
            "Socket(", "TcpClient", "UdpClient",
        )
        for token in forbidden:
            with self.subTest(token=token):
                self.assertNotIn(token, _PROBE_CS)

    def test_no_process_launch(self):
        self.assertNotIn("Process.Start", _PROBE_CS)
        self.assertNotIn("System.Diagnostics", _PROBE_CS)

    def test_no_absolute_or_outside_project_path_literal(self):
        # Every string literal that looks like a filesystem path must be
        # relative. This catches an accidental "/tmp/..." or "C:\..." literal
        # sneaking into the probe.
        self.assertIsNone(re.search(r'"(/[A-Za-z]|[A-Za-z]:\\\\)', _PROBE_CS))

    def test_file_io_confined_to_env_supplied_or_relative_paths(self):
        # File.WriteAllText / File.ReadAllText calls must target either the
        # relative Library/KingletSpike receipt path or a path that came from
        # an environment variable (KINGLET_MCP_PREFS_BACKUP), never a literal
        # absolute path.
        for match in re.finditer(r"File\.(WriteAllText|ReadAllText)\(([^,)]+)", _PROBE_CS):
            arg = match.group(2).strip()
            allowed = arg == "backupPath" or "Path.Combine" in arg
            self.assertTrue(allowed, f"unexpected file-IO argument: {arg!r}")


# ---------------------------------------------------------------------------
# KingletSpikeTests.cs
# ---------------------------------------------------------------------------

class TestsCsTests(unittest.TestCase):
    def test_exactly_one_test_attribute(self):
        self.assertEqual(1, _TESTS_CS.count("[Test]"))

    def test_asserts_against_probe_project_id_not_a_literal_copy(self):
        self.assertIn("Probe.ProjectId", _TESTS_CS)
        # The test method body itself must reference the symbol, not a
        # hardcoded duplicate string that could silently drift from Probe.cs.
        method_start = _TESTS_CS.index("public void ProjectMarkerMatchesPinnedFixture")
        method_body = _TESTS_CS[method_start:]
        self.assertIn("Probe.ProjectId", method_body)

    def test_uses_nunit(self):
        self.assertIn("using NUnit.Framework;", _TESTS_CS)


# ---------------------------------------------------------------------------
# .meta completeness
# ---------------------------------------------------------------------------

class MetaCompletenessTests(unittest.TestCase):
    def _asset_paths(self):
        assets_root = _FIXTURE / "Assets"
        paths = []
        for path in assets_root.rglob("*"):
            if path.suffix == ".meta":
                continue
            paths.append(path)
        return paths

    def _meta_paths(self):
        assets_root = _FIXTURE / "Assets"
        return [p for p in assets_root.rglob("*.meta")]

    def test_every_asset_has_exactly_one_meta_sibling(self):
        for asset in self._asset_paths():
            meta = asset.parent / (asset.name + ".meta")
            with self.subTest(asset=str(asset.relative_to(_FIXTURE))):
                self.assertTrue(meta.is_file(), f"missing .meta for {asset}")

    def test_no_orphan_meta_files(self):
        for meta in self._meta_paths():
            asset = meta.parent / meta.name[: -len(".meta")]
            with self.subTest(meta=str(meta.relative_to(_FIXTURE))):
                self.assertTrue(asset.exists(), f"orphan .meta with no asset: {meta}")

    def test_all_guids_unique(self):
        guids = []
        for meta in self._meta_paths():
            text = meta.read_text(encoding="utf-8")
            match = _GUID_RE.search(text)
            self.assertIsNotNone(match, f"{meta} has no guid line")
            guids.append(match.group(1))
        self.assertEqual(len(guids), len(set(guids)), "duplicate guid found in fixture .meta files")

    def test_all_guids_well_formed(self):
        for meta in self._meta_paths():
            text = meta.read_text(encoding="utf-8")
            match = _GUID_RE.search(text)
            self.assertIsNotNone(match)
            self.assertRegex(match.group(1), r"^[0-9a-f]{32}$")


if __name__ == "__main__":
    unittest.main()
