"""test_codex_probe_package.py — Structural and content assertions for the
Codex client-probe overlay.

Tests assert on committed file TEXT (no execution of `codex plugin
marketplace add` / `codex plugin add` — that is the later live dispatch's
job, not this test suite's). They confirm:

  - .codex-plugin/plugin.json: name, version, description, skills: "./skills/",
    mcpServers: "./.mcp.json", a full required `interface` block, NO `hooks`
    field (codex-cli's own bundled `validate_plugin.py` rejects that key
    outright — see PluginJsonTests docstring), and that every path-shaped
    field is relative and begins with "./" (codex-cli's own
    plugin-json-spec.md: "Path values should be relative and begin with ./").
  - .agents/plugins/marketplace.json: one local plugin entry whose
    source.path begins with "./" (Codex's real marketplace schema nests
    source under {source, path}, unlike Claude Code's flat "source" string —
    see PluginJsonTests docstring for how this was established).
  - hooks.json (plugin ROOT, auto-discovered — not hooks/hooks.json; moved
    there in fix round 1 because the manifest field the earlier draft
    declared is rejected by codex-cli's own validator): wrapper "hooks" key,
    PreToolUse event, Write|Edit matcher, command invokes
    kinglet-client-probe hook subcommand via the wrapper script (not the
    binary directly), relative path (no fabricated ${PLUGIN_ROOT} token —
    see runbook.md "Open question 1").
  - .mcp.json: "mcpServers" wrapper key (Codex's real schema, unlike Claude
    Code's flat file), relative command path, "mcp" subcommand present,
    `default_tools_approval_mode: "prompt"` on the server entry (the brief's
    explicit MCP approval-policy requirement).
  - runbook.md: CLI install/uninstall commands, twelve case IDs, four prompt
    texts, PreToolUse exit-2 deny note, build-time copy instruction, the
    ${PLUGIN_ROOT} open question, and the documented (not guessed)
    cachebuster update mechanism.
  - hook wrapper shell script: strict mode, reads stdin, calls probe hook
    subcommand, parses decision field, exits 2 on deny, exits 0 on allow,
    no absolute user paths, no bash 4 constructs, no GNU-only flags.
"""
from __future__ import annotations

import json
import os
import re
import unittest
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
_PKG = _REPO_ROOT / "spikes" / "platform" / "clients" / "codex"

# ---------------------------------------------------------------------------
# Read files at import time so every test class gets the same bytes.
#
# If any of these files is missing, `_read` raises FileNotFoundError
# immediately at MODULE IMPORT time (not per-test). unittest then reports
# the whole module as a single collection error rather than 66 individual
# failures — but that error's traceback names the exact missing path (it is
# `_read`'s own `(_PKG / rel)` argument), so the missing file is still
# identifiable, just via one failure instead of many. This is a deliberate
# trade — Step 2 of the brief ("run tests and verify missing manifests")
# exercised exactly this collection-error shape when the package did not
# exist yet, and it named the first missing file in its traceback.
# ---------------------------------------------------------------------------
def _read(rel: str) -> str:
    return (_PKG / rel).read_text(encoding="utf-8")


PLUGIN_JSON_TEXT = _read(".codex-plugin/plugin.json")
MARKETPLACE_JSON_TEXT = _read(".agents/plugins/marketplace.json")
HOOKS_JSON_TEXT = _read("hooks.json")
MCP_JSON_TEXT = _read(".mcp.json")
RUNBOOK_TEXT = _read("runbook.md")
HOOK_WRAPPER_TEXT = _read("hooks/pre-mutation-hook.sh")

PLUGIN_JSON = json.loads(PLUGIN_JSON_TEXT)
MARKETPLACE_JSON = json.loads(MARKETPLACE_JSON_TEXT)
HOOKS_JSON = json.loads(HOOKS_JSON_TEXT)
MCP_JSON = json.loads(MCP_JSON_TEXT)


# ---------------------------------------------------------------------------
# plugin.json tests
# ---------------------------------------------------------------------------

class PluginJsonTests(unittest.TestCase):
    """Asserts on .codex-plugin/plugin.json.

    codex-cli 0.145.0 ships its own plugin-creator skill with a field guide
    (`plugin-json-spec.md`) documenting this shape, AND a bundled validator
    script (`~/.codex/skills/.system/plugin-creator/scripts/
    validate_plugin.py`) that enforces it. That validator's `allowed_keys`
    set for the top-level manifest is exactly: id, name, version,
    description, skills, apps, mcpServers, interface, author, homepage,
    repository, license, keywords — `hooks` is NOT in that set, and
    `validate_manifest_shape` rejects any key outside it with
    "plugin.json field `<key>` is not accepted by plugin validation". It
    also requires a full `interface` object (displayName, shortDescription,
    longDescription, developerName, category, capabilities, and either
    defaultPrompt or default_prompt), rejected in fix round 1 with
    "plugin.json field `interface` must be an object" when that block was
    absent. Round 1 ran `validate_plugin.py` against the committed package
    directly (see the fix report in task-5-report.md for the transcript) —
    this is not inferred from Claude Code's schema, and no shared manifest
    format grants Codex a pass.
    """

    def test_name_is_kinglet_client_probe(self):
        self.assertEqual(PLUGIN_JSON.get("name"), "kinglet-client-probe")

    def test_version_is_0_0_1(self):
        """The initial version must match the brief (and Claude Code's, for
        cross-client comparability of the version-update case)."""
        self.assertEqual(PLUGIN_JSON.get("version"), "0.0.1")

    def test_description_matches_the_committed_manifest_text(self):
        """description must be the actual committed sentence, not a
        placeholder — bound to real content rather than a bare length check,
        so a one-character stub can no longer satisfy this test."""
        desc = PLUGIN_JSON.get("description", "")
        self.assertIn("Kinglet client-probe overlay for Codex", desc)
        self.assertIn("PreToolUse hook blocking", desc)

    def test_skills_path_is_dot_skills_dir(self):
        """plugin.json must declare skills: './skills/' per codex-cli's own spec."""
        self.assertEqual(PLUGIN_JSON.get("skills"), "./skills/")

    def test_mcp_path_is_dot_mcp_json(self):
        """plugin.json must reference MCP via the relative path ./.mcp.json."""
        self.assertEqual(PLUGIN_JSON.get("mcpServers"), "./.mcp.json")

    def test_manifest_does_not_declare_a_hooks_field(self):
        """plugin.json must NOT carry a 'hooks' key.

        codex-cli's own bundled validator (`validate_plugin.py`) does not
        accept `hooks` as a top-level manifest field at all — declaring it
        fails validation outright ("plugin.json field `hooks` is not
        accepted by plugin validation"), confirmed by running the validator
        against an earlier draft of this manifest in fix round 1. Real
        installed plugins observed on the probe host that ship a top-level
        hooks.json (e.g. figma) do NOT declare a 'hooks' field either —
        auto-discovery picks up the plugin-root hooks.json with no manifest
        reference at all, which is why the committed hooks.json lives at
        the plugin root, not nested under hooks/.
        """
        self.assertNotIn(
            "hooks", PLUGIN_JSON,
            "plugin.json must not declare 'hooks' — codex-cli's own "
            "validate_plugin.py rejects that key, and hooks.json at the "
            "plugin root is auto-discovered without one"
        )

    def test_all_path_shaped_fields_are_relative_and_begin_with_dot_slash(self):
        """Every path-shaped manifest field must start with './'.

        codex-cli's own plugin-json-spec.md: 'Path values should be relative
        and begin with ./'. The binary's own diagnostic strings independently
        confirm this rule is enforced at runtime: '<path> must start with
        `./` relative to plugin root'.
        """
        for field in ("skills", "mcpServers"):
            value = PLUGIN_JSON.get(field)
            self.assertIsNotNone(value, f"plugin.json must declare '{field}'")
            self.assertTrue(
                value.startswith("./"),
                f"plugin.json field '{field}' must be relative and begin with "
                f"'./'; got {value!r}"
            )

    def test_interface_block_has_all_required_fields(self):
        """codex-cli's validate_plugin.py requires interface.{displayName,
        shortDescription, longDescription, developerName, category} as
        non-empty strings, interface.capabilities as a non-empty array of
        strings, and either defaultPrompt or default_prompt present."""
        interface = PLUGIN_JSON.get("interface")
        self.assertIsInstance(interface, dict, "plugin.json field 'interface' must be an object")
        for field in ("displayName", "shortDescription", "longDescription",
                      "developerName", "category"):
            value = interface.get(field)
            self.assertIsInstance(value, str, f"interface.{field} must be a string")
            self.assertGreater(len(value.strip()), 0, f"interface.{field} must be non-empty")
        capabilities = interface.get("capabilities")
        self.assertIsInstance(capabilities, list)
        self.assertGreater(len(capabilities), 0)
        self.assertTrue(all(isinstance(c, str) and c.strip() for c in capabilities))
        self.assertTrue(
            "defaultPrompt" in interface or "default_prompt" in interface,
            "interface must declare defaultPrompt or default_prompt"
        )

    def test_no_absolute_paths_anywhere_in_manifest(self):
        """No field in plugin.json may contain an absolute filesystem path."""
        self.assertNotIn("/home/", PLUGIN_JSON_TEXT)
        self.assertNotIn("/Users/", PLUGIN_JSON_TEXT)
        self.assertIsNone(re.search(r'"[A-Za-z]:\\\\', PLUGIN_JSON_TEXT))


@unittest.skipUnless(
    (Path.home() / ".codex" / "skills" / ".system" / "plugin-creator"
     / "scripts" / "validate_plugin.py").is_file(),
    "codex-cli's bundled plugin-creator validator is not present on this host — skip",
)
class PluginValidatorTests(unittest.TestCase):
    """Gate: codex-cli's OWN bundled `validate_plugin.py` must pass against
    the committed package.

    There is no `codex plugin validate` CLI subcommand. This script,
    shipped inside codex-cli 0.145.0's own `plugin-creator` skill, is the
    closest thing the tested build offers to a manifest-ingestion check, and
    it independently confirmed the CRITICAL-1 finding from fix round 1
    (plugin.json's `hooks` field and missing `interface` block). It never
    calls the `codex` CLI itself, registers a marketplace, or touches a
    config root, so it stays in scope for a headless dispatch.
    """

    def test_validate_plugin_passes(self):
        import subprocess
        script = str(
            Path.home() / ".codex" / "skills" / ".system" / "plugin-creator"
            / "scripts" / "validate_plugin.py"
        )
        result = subprocess.run(
            ["python3", script, str(_PKG)],
            capture_output=True, text=True,
        )
        self.assertEqual(
            result.returncode, 0,
            f"validate_plugin.py failed:\nstdout={result.stdout!r}\nstderr={result.stderr!r}"
        )
        self.assertIn("Plugin validation passed", result.stdout)


# ---------------------------------------------------------------------------
# marketplace.json tests
# ---------------------------------------------------------------------------

class MarketplaceJsonTests(unittest.TestCase):
    """Asserts on .agents/plugins/marketplace.json.

    Codex's real marketplace schema (read directly from codex-cli's own
    plugin-creator skill spec and from installed marketplace files on the
    probe host) nests the source under a {source, path} object with a
    policy block — structurally different from Claude Code's flat
    "source": "./" string, by design (the plan's architecture rule: no
    shared manifest format grants another client a pass).
    """

    def test_marketplace_name_equals_plugin_name(self):
        """The marketplace name must be 'kinglet-client-probe'.

        The install command is:
            codex plugin add kinglet-client-probe@kinglet-client-probe
        The @<marketplace-name> part comes from the marketplace 'name' field.
        """
        self.assertEqual(MARKETPLACE_JSON.get("name"), "kinglet-client-probe")

    def test_plugins_list_is_non_empty(self):
        plugins = MARKETPLACE_JSON.get("plugins", [])
        self.assertGreater(len(plugins), 0, "plugins list must not be empty")

    def test_plugin_entry_name_is_kinglet_client_probe(self):
        plugins = MARKETPLACE_JSON.get("plugins", [])
        self.assertGreater(len(plugins), 0)
        self.assertEqual(plugins[0].get("name"), "kinglet-client-probe")

    def test_plugin_entry_source_is_an_object_with_local_source(self):
        """Codex's marketplace entry 'source' is an OBJECT, not a bare string.

        {"source": "local", "path": "./..."} — this shape was read directly
        off real marketplace.json files shipped with codex-cli (e.g. the
        openai-curated marketplace's linear/atlassian-rovo/gmail entries all
        use {"source": "local", "path": "./plugins/<name>"}).
        """
        plugins = MARKETPLACE_JSON.get("plugins", [])
        self.assertGreater(len(plugins), 0)
        source = plugins[0].get("source")
        self.assertIsInstance(source, dict,
                              "marketplace plugin entry 'source' must be an object")
        self.assertEqual(source.get("source"), "local")

    def test_plugin_entry_source_path_begins_with_dot_slash(self):
        """source.path must begin with './' — the brief's exact requirement."""
        plugins = MARKETPLACE_JSON.get("plugins", [])
        self.assertGreater(len(plugins), 0)
        path = plugins[0].get("source", {}).get("path", "")
        self.assertTrue(
            path.startswith("./"),
            f"marketplace plugin entry source.path must begin with './'; got {path!r}"
        )

    def test_plugin_entry_has_policy_block(self):
        """Codex's real marketplace entries always carry a policy block
        (installation + authentication) — omitting it is inconsistent with
        every observed real entry."""
        plugins = MARKETPLACE_JSON.get("plugins", [])
        policy = plugins[0].get("policy", {})
        self.assertIn("installation", policy)
        self.assertIn("authentication", policy)

    def test_plugin_entry_has_category(self):
        plugins = MARKETPLACE_JSON.get("plugins", [])
        self.assertIn("category", plugins[0])

    def test_no_absolute_paths_anywhere_in_manifest(self):
        self.assertNotIn("/home/", MARKETPLACE_JSON_TEXT)
        self.assertNotIn("/Users/", MARKETPLACE_JSON_TEXT)


# ---------------------------------------------------------------------------
# hooks.json tests (plugin ROOT — see PluginJsonTests docstring for why)
# ---------------------------------------------------------------------------

class HooksJsonTests(unittest.TestCase):
    """Asserts on the plugin-root hooks.json.

    Moved from hooks/hooks.json to the plugin root in fix round 1: codex-cli's
    own validate_plugin.py rejects a 'hooks' field in plugin.json, and the
    real installed plugins observed on the probe host (figma) auto-discover
    a root-level hooks.json with no manifest reference at all.
    """

    def test_hooks_json_is_valid_json(self):
        self.assertIsInstance(HOOKS_JSON, dict)

    def test_hooks_json_lives_at_plugin_root(self):
        """hooks.json must be discoverable at the plugin root, not nested,
        since plugin.json declares no 'hooks' field to point at it."""
        self.assertTrue(
            (_PKG / "hooks.json").is_file(),
            "hooks.json must exist at the plugin root for auto-discovery"
        )

    def test_has_top_level_hooks_key(self):
        self.assertIn("hooks", HOOKS_JSON,
                      "hooks.json must have a top-level 'hooks' wrapper key")

    def test_pretooluse_event_is_present(self):
        """PreToolUse is a confirmed real codex-cli 0.145.0 hook event — its
        name appears in the binary's own diagnostic strings ('PreToolUse
        hook exited with code 2 but did not write a blocking reason to
        stderr'), not assumed by analogy with Claude Code."""
        hooks = HOOKS_JSON.get("hooks", {})
        self.assertIn("PreToolUse", hooks,
                      "hooks wrapper must contain a 'PreToolUse' event key")

    def test_pretooluse_has_write_edit_matcher(self):
        """Matcher 'Write|Edit' mirrors the tool-name vocabulary observed in a
        real installed Codex plugin's hooks.json on the probe host (figma
        uses the identical matcher spelling for its own PostToolUse hook).
        This is an open question for the live pass — see runbook.md."""
        entries = HOOKS_JSON.get("hooks", {}).get("PreToolUse", [])
        self.assertGreater(len(entries), 0)
        matcher = entries[0].get("matcher", "")
        self.assertEqual(matcher, "Write|Edit",
                         "PreToolUse matcher must be exactly 'Write|Edit'")

    def test_pretooluse_command_type_is_command(self):
        entries = HOOKS_JSON.get("hooks", {}).get("PreToolUse", [])
        inner = entries[0].get("hooks", [])
        self.assertGreater(len(inner), 0)
        self.assertEqual(inner[0].get("type"), "command",
                         "PreToolUse hook type must be 'command'")

    def test_pretooluse_command_is_relative_path_not_a_fabricated_token(self):
        """The command must be a bare relative path — no ${PLUGIN_ROOT} (or
        any other) token was found documented anywhere in codex-cli 0.145.0.
        Fabricating one would contradict the explicit instruction not to
        invent a token name; see runbook.md 'Open question 1'."""
        entries = HOOKS_JSON.get("hooks", {}).get("PreToolUse", [])
        inner = entries[0].get("hooks", [])
        cmd = inner[0].get("command", "")
        self.assertTrue(cmd.startswith("./"),
                        f"hook command must be a relative path beginning with './'; got {cmd!r}")
        self.assertNotIn("${", cmd,
                         "hook command must not reference any ${...} token — "
                         "none is documented in the tested codex-cli build")

    def test_pretooluse_command_references_hook_wrapper_script(self):
        entries = HOOKS_JSON.get("hooks", {}).get("PreToolUse", [])
        inner = entries[0].get("hooks", [])
        cmd = inner[0].get("command", "")
        self.assertIn("pre-mutation-hook.sh", cmd)

    def test_pretooluse_command_does_not_call_binary_directly(self):
        """The command must call the wrapper script, not kinglet-client-probe
        directly — the binary exits 0 on deny; the wrapper is what exits 2."""
        entries = HOOKS_JSON.get("hooks", {}).get("PreToolUse", [])
        inner = entries[0].get("hooks", [])
        cmd = inner[0].get("command", "")
        self.assertNotIn("kinglet-client-probe hook", cmd)

    def test_pretooluse_command_references_existing_hook_script(self):
        """Regression guard: `cmd.lstrip("./")` strips a CHARACTER SET, not a
        prefix — it would mangle a path like './.probe/x.sh' into
        'probe/x.sh' and turn a real existence check into a confusing
        false failure. Use a literal prefix strip instead."""
        entries = HOOKS_JSON.get("hooks", {}).get("PreToolUse", [])
        inner = entries[0].get("hooks", [])
        cmd = inner[0].get("command", "")
        self.assertTrue(cmd.startswith("./"), f"command must start with './'; got {cmd!r}")
        rel_path = cmd[2:]
        self.assertTrue(rel_path.endswith(".sh"))
        script_file = _PKG / rel_path
        self.assertTrue(script_file.is_file(),
                        f"referenced script must exist at {script_file}")


# ---------------------------------------------------------------------------
# .mcp.json tests
# ---------------------------------------------------------------------------

class McpJsonTests(unittest.TestCase):
    """Asserts on .mcp.json.

    Codex's real .mcp.json files (figma, github, openai-developers — all
    observed on the probe host under the codex-cli's own plugin cache) wrap
    server entries under a top-level "mcpServers" key. Claude Code's
    committed .mcp.json is flat (no wrapper key) — a real, confirmed schema
    difference between the two clients, not an oversight.
    """

    def test_mcp_json_is_valid_json(self):
        self.assertIsInstance(MCP_JSON, dict)

    def test_has_top_level_mcpservers_key(self):
        self.assertIn("mcpServers", MCP_JSON,
                      ".mcp.json must have a top-level 'mcpServers' wrapper key "
                      "(Codex's real schema, confirmed against installed plugins)")

    def test_mcp_json_has_kinglet_client_probe_server(self):
        servers = MCP_JSON.get("mcpServers", {})
        self.assertIn("kinglet-client-probe", servers)

    def test_mcp_command_is_relative_path_not_a_fabricated_token(self):
        server = MCP_JSON.get("mcpServers", {}).get("kinglet-client-probe", {})
        cmd = server.get("command", "")
        self.assertTrue(cmd.startswith("./"),
                        f"MCP command must be a relative path beginning with './'; got {cmd!r}")
        self.assertNotIn("${", cmd,
                         "MCP command must not reference any ${...} token — "
                         "none is documented in the tested codex-cli build")
        self.assertIn("/bin/", cmd)
        self.assertTrue(cmd.endswith("/kinglet-client-probe"),
                        f"MCP command must end with /kinglet-client-probe; got {cmd!r}")

    def test_mcp_args_contain_mcp_subcommand(self):
        server = MCP_JSON.get("mcpServers", {}).get("kinglet-client-probe", {})
        args = server.get("args", [])
        self.assertIn("mcp", args)

    def test_mcp_cwd_is_dot(self):
        """Real Codex .mcp.json entries that use a relative command carry an
        explicit "cwd": "." (openai-developers, observed on the probe host).
        Without it, the relative command path's resolution base is
        undocumented for this tested build."""
        server = MCP_JSON.get("mcpServers", {}).get("kinglet-client-probe", {})
        self.assertEqual(server.get("cwd"), ".")

    def test_default_tools_approval_mode_is_prompt(self):
        """The brief's Interfaces line requires 'plugin-scoped MCP approval
        policy' and Step 3 requires approval mode 'prompt', never 'approve'.
        codex-cli 0.145.0's own RawMcpServerConfig struct (confirmed via
        `strings` over the native binary) carries a
        `default_tools_approval_mode` field per server entry, with value
        alphabet prompt|writes|approve."""
        server = MCP_JSON.get("mcpServers", {}).get("kinglet-client-probe", {})
        self.assertEqual(server.get("default_tools_approval_mode"), "prompt")

    def test_default_tools_approval_mode_is_never_approve(self):
        """Belt-and-suspenders: assert the forbidden value is not merely
        absent but explicitly not present anywhere in the server entry,
        since 'approve' would auto-approve every tool call unattended."""
        server = MCP_JSON.get("mcpServers", {}).get("kinglet-client-probe", {})
        self.assertNotEqual(server.get("default_tools_approval_mode"), "approve")


# ---------------------------------------------------------------------------
# runbook.md tests
# ---------------------------------------------------------------------------

class RunbookTests(unittest.TestCase):
    """Asserts on runbook.md."""

    def test_no_absolute_user_paths(self):
        home = os.path.expanduser("~")
        self.assertNotIn(home, RUNBOOK_TEXT)
        self.assertIsNone(
            re.search(r'(/home/\w|/Users/\w|[A-Z]:\\Users\\)', RUNBOOK_TEXT),
            "runbook must not contain any hardcoded user home path"
        )

    def test_update_version_step_present(self):
        self.assertIn("0.0.2", RUNBOOK_TEXT,
                      "runbook must document the version-update step (0.0.1 -> 0.0.2)")

    def test_new_session_required_before_prompts(self):
        lower = RUNBOOK_TEXT.lower()
        has_new_session = "new session" in lower or "fresh session" in lower
        self.assertTrue(has_new_session,
                        "runbook must instruct starting a new session before running prompts")

    def test_exit_2_deny_note_present(self):
        """Runbook must document exit 2 as Codex's PreToolUse block signal,
        confirmed from the codex-cli binary's own diagnostic strings."""
        lower = RUNBOOK_TEXT.lower()
        self.assertTrue(
            "exit 2" in lower or "exit code 2" in lower,
            "runbook must document exit 2 as the Codex deny signal"
        )
        self.assertIn("blocking reason to stderr", RUNBOOK_TEXT,
                      "runbook must cite the codex-cli diagnostic string confirming "
                      "the exit-2/stderr contract")

    def test_plugin_root_token_open_question_documented(self):
        """The absence of a documented ${PLUGIN_ROOT} token must be recorded,
        not silently worked around."""
        self.assertIn("PLUGIN_ROOT", RUNBOOK_TEXT)
        lower = RUNBOOK_TEXT.lower()
        self.assertTrue(
            "not found" in lower or "no documented" in lower,
            "runbook must record that no ${PLUGIN_ROOT}-equivalent token was found"
        )

    def test_plugin_update_command_open_question_documented(self):
        """codex-cli 0.145.0 has no `codex plugin update` subcommand — this
        must be recorded so the live pass knows to observe, not assume."""
        self.assertIn("no `update` verb", RUNBOOK_TEXT)

    def test_build_step_copies_shared_skill_and_agent(self):
        """Bound to the actual `cp` invocations, not a bare substring match —
        a runbook that merely mentions the words 'skill'/'agent'/'copy' in
        prose would previously satisfy this test without giving an operator
        anything runnable."""
        self.assertIn(
            "cp spikes/platform/clients/shared/skills/kinglet-capability-probe/SKILL.md",
            RUNBOOK_TEXT,
            "runbook must contain the literal cp command for the shared skill"
        )
        self.assertIn(
            "cp spikes/platform/clients/shared/agents/kinglet-capability-reviewer.agent.md",
            RUNBOOK_TEXT,
            "runbook must contain the literal cp command for the shared agent"
        )

    def test_all_twelve_case_ids_present(self):
        from tests.kinglet_spike.client_support import CASE_IDS
        for cid in CASE_IDS:
            self.assertIn(cid, RUNBOOK_TEXT,
                          f"runbook must reference case ID '{cid}'")

    def test_all_four_prompt_texts_present(self):
        """All four exact prompt texts from prompts-v1.json must appear in
        the runbook, whitespace-normalized to survive markdown line-wrapping."""
        contracts = _REPO_ROOT / "spikes" / "platform" / "clients" / "contracts" / "prompts-v1.json"
        prompts = json.loads(contracts.read_text(encoding="utf-8"))["prompts"]
        normalized_runbook = " ".join(RUNBOOK_TEXT.split())
        for prompt in prompts:
            normalized_text = " ".join(prompt["text"].split())
            self.assertIn(normalized_text, normalized_runbook,
                          f"runbook must contain prompt text (whitespace-normalized): "
                          f"{normalized_text[:80]!r}...")

    def test_all_four_prompt_ids_present(self):
        contracts = _REPO_ROOT / "spikes" / "platform" / "clients" / "contracts" / "prompts-v1.json"
        prompts = json.loads(contracts.read_text(encoding="utf-8"))["prompts"]
        for prompt in prompts:
            prompt_id = prompt["id"]
            self.assertIn(prompt_id, RUNBOOK_TEXT,
                          f"runbook must reference prompt ID '{prompt_id}'")

    def test_plugin_commands_in_order(self):
        """codex plugin marketplace add must appear before codex plugin add."""
        marketplace_pos = RUNBOOK_TEXT.find("codex plugin marketplace add")
        install_pos = RUNBOOK_TEXT.find("codex plugin add")
        list_pos = RUNBOOK_TEXT.find("codex plugin list")
        self.assertGreater(marketplace_pos, -1,
                           "runbook must contain 'codex plugin marketplace add'")
        self.assertGreater(install_pos, -1,
                           "runbook must contain 'codex plugin add'")
        self.assertGreater(list_pos, -1,
                           "runbook must contain 'codex plugin list'")
        self.assertIn("codex plugin remove", RUNBOOK_TEXT,
                      "runbook must contain 'codex plugin remove'")
        self.assertLess(marketplace_pos, install_pos,
                        "'codex plugin marketplace add' must appear before 'codex plugin add'")
        self.assertIn("kinglet-client-probe@kinglet-client-probe", RUNBOOK_TEXT,
                      "install command must use the name@marketplace form")

    def test_mcp_approval_mode_documented(self):
        """The brief's Step 3 MCP approval-policy requirement must be
        recorded in the runbook, not just in the manifest."""
        self.assertIn("default_tools_approval_mode", RUNBOOK_TEXT)
        self.assertIn("prompt", RUNBOOK_TEXT)
        self.assertIn("Never `approve`", RUNBOOK_TEXT,
                      "runbook must record 'prompt, never approve'")

    def test_validate_plugin_py_documented(self):
        """codex-cli 0.145.0 has no `codex plugin validate`, but it ships
        `validate_plugin.py` inside its own plugin-creator skill — the
        runbook must point the operator at it, since it is the closest
        thing the tested build offers to a manifest correctness check."""
        self.assertIn("validate_plugin.py", RUNBOOK_TEXT)
        self.assertIn("codex plugin validate", RUNBOOK_TEXT)

    def test_cachebuster_update_mechanism_documented(self):
        """Fix round 1: the update step must use the documented cachebuster
        loop (installing-and-updating.md), not a numeric version bump
        presented as the only path."""
        self.assertIn("cachebuster", RUNBOOK_TEXT.lower())
        self.assertIn("update_plugin_cachebuster.py", RUNBOOK_TEXT)
        self.assertIn(
            "Do not keep incrementing numeric version components",
            RUNBOOK_TEXT,
            "runbook must cite the reference's own policy statement verbatim"
        )

    def test_cli_not_gui_deviation_documented(self):
        """The human ruling — the CLI binds, not the Plugins Directory GUI —
        must be recorded in the runbook, mirroring how Claude Code's runbook
        records its own deviations."""
        lower = RUNBOOK_TEXT.lower()
        self.assertIn("deviation", lower)
        self.assertIn("0.145.0", RUNBOOK_TEXT)


# ---------------------------------------------------------------------------
# hooks/pre-mutation-hook.sh tests
# ---------------------------------------------------------------------------

class HookWrapperTests(unittest.TestCase):
    """Asserts on hooks/pre-mutation-hook.sh."""

    def test_uses_strict_bash_mode(self):
        self.assertIn("set -euo pipefail", HOOK_WRAPPER_TEXT)

    def test_reads_stdin_into_variable(self):
        """Bound to the actual assignment, not a bare substring search for
        'read' — that previously matched inside unrelated words like
        'already', which would pass even if stdin capture were deleted."""
        self.assertIn(
            'TOOL_EVENT="$(cat)"', HOOK_WRAPPER_TEXT,
            "wrapper must capture stdin into TOOL_EVENT via $(cat)"
        )

    def test_extracts_file_path_from_tool_input(self):
        non_comment_lines = [
            line for line in HOOK_WRAPPER_TEXT.splitlines()
            if not line.strip().startswith("#")
        ]
        non_comment_text = "\n".join(non_comment_lines)
        self.assertIn(".tool_input.file_path", non_comment_text,
                      "wrapper must use jq path '.tool_input.file_path' in non-comment code")

    def test_calls_probe_hook_subcommand_with_stdin_event(self):
        self.assertIn("hook --event -", HOOK_WRAPPER_TEXT,
                      "wrapper must call 'hook --event -' to pass the event via stdin")

    def test_parses_decision_field_from_probe_output(self):
        non_comment_lines = [
            line for line in HOOK_WRAPPER_TEXT.splitlines()
            if not line.strip().startswith("#")
        ]
        non_comment_text = "\n".join(non_comment_lines)
        self.assertIn(".decision", non_comment_text,
                      "wrapper must extract .decision via jq in non-comment code")

    def test_exits_2_on_deny(self):
        non_comment_lines = [
            line for line in HOOK_WRAPPER_TEXT.splitlines()
            if not line.strip().startswith("#")
        ]
        non_comment_text = "\n".join(non_comment_lines)
        self.assertIn("exit 2", non_comment_text,
                      "wrapper must contain 'exit 2' in non-comment code")

    def test_exits_0_on_allow(self):
        non_comment_lines = [
            line for line in HOOK_WRAPPER_TEXT.splitlines()
            if not line.strip().startswith("#")
        ]
        non_comment_text = "\n".join(non_comment_lines)
        self.assertIn("exit 0", non_comment_text,
                      "wrapper must contain 'exit 0' in non-comment code")

    def test_deny_is_conditional_not_unconditional(self):
        lines = HOOK_WRAPPER_TEXT.splitlines()
        conditional_seen = False
        exit2_in_code_found = False
        for line in lines:
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            if re.search(r'\bif\b|\bcase\b|\[\s|\btest\b', stripped):
                conditional_seen = True
            if "exit 2" in stripped:
                exit2_in_code_found = True
                self.assertTrue(conditional_seen,
                                "exit 2 must appear after a conditional construct")
                break
        self.assertTrue(exit2_in_code_found,
                        "exit 2 must appear in non-comment code")

    def test_does_not_reference_a_fabricated_plugin_root_env_var(self):
        """The wrapper's actual CODE (not its explanatory comments) must NOT
        use ${CLAUDE_PLUGIN_ROOT} or a guessed ${CODEX_PLUGIN_ROOT} — neither
        is documented for codex-cli 0.145.0. It self-locates via BASH_SOURCE
        instead. Comments MAY mention CLAUDE_PLUGIN_ROOT to explain why it is
        avoided; that is documentation, not usage."""
        non_comment_lines = [
            line for line in HOOK_WRAPPER_TEXT.splitlines()
            if not line.strip().startswith("#")
        ]
        non_comment_text = "\n".join(non_comment_lines)
        self.assertNotIn("CLAUDE_PLUGIN_ROOT", non_comment_text)
        self.assertNotIn("CODEX_PLUGIN_ROOT", non_comment_text)
        self.assertIn("BASH_SOURCE", non_comment_text,
                      "wrapper must self-locate via BASH_SOURCE, "
                      "not an unconfirmed plugin-root token")

    def test_no_declare_associative_array(self):
        self.assertNotIn("declare -A", HOOK_WRAPPER_TEXT)

    def test_no_grep_oP(self):
        self.assertNotIn("grep -oP", HOOK_WRAPPER_TEXT)

    def test_no_pipe_into_head(self):
        self.assertNotIn("| head", HOOK_WRAPPER_TEXT)

    def test_no_absolute_user_paths(self):
        home = os.path.expanduser("~")
        self.assertNotIn(home, HOOK_WRAPPER_TEXT)
        self.assertIsNone(
            re.search(r'(/home/\w|/Users/\w|[A-Z]:\\Users\\)', HOOK_WRAPPER_TEXT),
            "pre-mutation-hook.sh must not contain any hardcoded user home path"
        )

    def test_deny_path_emits_message_to_stderr(self):
        self.assertIn(">&2", HOOK_WRAPPER_TEXT,
                      "wrapper must emit at least one stderr message")

    def test_defines_exit_3_for_malformed_stdin(self):
        non_comment_lines = [
            line for line in HOOK_WRAPPER_TEXT.splitlines()
            if not line.strip().startswith("#")
        ]
        non_comment_text = "\n".join(non_comment_lines)
        self.assertIn("exit 3", non_comment_text,
                      "hook must contain 'exit 3' in non-comment code for malformed-stdin handling")

    def test_constructs_event_json_for_probe(self):
        non_comment_lines = [
            line for line in HOOK_WRAPPER_TEXT.splitlines()
            if not line.strip().startswith("#")
        ]
        non_comment_text = "\n".join(non_comment_lines)
        has_path_key = ('"path"' in non_comment_text or "'path'" in non_comment_text
                        or '{path:' in non_comment_text)
        self.assertTrue(has_path_key,
                        'wrapper must construct JSON with a "path" key in non-comment code')

    def test_is_executable(self):
        script = _PKG / "hooks" / "pre-mutation-hook.sh"
        self.assertTrue(os.access(script, os.X_OK),
                        "hooks/pre-mutation-hook.sh must be executable (chmod +x)")


# ---------------------------------------------------------------------------
# Hook wrapper behavioral tests (require the compiled probe binary; run the
# script directly with `bash` — this does NOT invoke `codex` at all, so it is
# in scope for a headless dispatch that must not run `codex plugin
# marketplace add` / `codex plugin add`)
# ---------------------------------------------------------------------------

def _derive_probe_exe_path_for_hook_tests() -> str:
    import platform as _platform
    import subprocess as _subprocess
    sys_name = _platform.system().lower()
    machine = _platform.machine().lower()
    if machine in ("x86_64", "amd64"):
        goarch = "amd64"
    elif machine in ("aarch64", "arm64"):
        goarch = "arm64"
    else:
        goarch = "amd64"
    dist = _REPO_ROOT / "spikes" / "platform" / "clients" / "probe-host" / "dist"
    p = dist / f"{sys_name}-{goarch}" / "kinglet-client-probe"
    return str(p) if p.is_file() else ""


_PROBE_EXE = _derive_probe_exe_path_for_hook_tests()


def _probe_skip_or_error() -> str:
    if _PROBE_EXE:
        return ""
    if os.environ.get("KINGLET_REQUIRE_PROBE") == "1":
        raise RuntimeError(
            "KINGLET_REQUIRE_PROBE=1 but probe binary not built — "
            "run: bash spikes/platform/clients/probe-host/build.sh"
        )
    return "probe binary not built — skip behavioral hook tests"


_PROBE_SKIP_REASON = _probe_skip_or_error()


@unittest.skipIf(_PROBE_SKIP_REASON, _PROBE_SKIP_REASON)
class HookWrapperBehavioralTests(unittest.TestCase):
    """Execute the hook script against the real binary to verify behavior.

    This runs `bash hooks/pre-mutation-hook.sh` directly — it never invokes
    the `codex` CLI, registers a marketplace, or installs a plugin, so it
    stays inside the Steps 1-3 scope boundary.
    """

    def _run_hook(self, stdin_json):
        import subprocess
        import tempfile
        import shutil as _shutil
        script = str(_PKG / "hooks" / "pre-mutation-hook.sh")
        tmpdir = tempfile.mkdtemp()
        try:
            bin_dir = os.path.join(tmpdir, "hooks", "..", "bin")
            os.makedirs(bin_dir)
            hooks_dir = os.path.join(tmpdir, "hooks")
            os.makedirs(hooks_dir, exist_ok=True)
            dest_script = os.path.join(hooks_dir, "pre-mutation-hook.sh")
            _shutil.copy2(script, dest_script)
            os.chmod(dest_script, 0o755)
            dest_bin = os.path.join(tmpdir, "bin", "kinglet-client-probe")
            _shutil.copy2(_PROBE_EXE, dest_bin)
            os.chmod(dest_bin, 0o755)
            result = subprocess.run(
                ["bash", dest_script],
                input=stdin_json, capture_output=True, text=True,
            )
        finally:
            _shutil.rmtree(tmpdir, ignore_errors=True)
        return result

    def test_deny_relative_path(self):
        event = '{"tool_name":"Write","tool_input":{"file_path":"Assets/Protected.txt"}}'
        r = self._run_hook(event)
        self.assertEqual(r.returncode, 2,
                         f"expected exit 2 for relative protected path; got {r.returncode}\nstderr={r.stderr!r}")

    def test_allow_unprotected_path(self):
        event = '{"tool_name":"Write","tool_input":{"file_path":"Assets/Safe.txt"}}'
        r = self._run_hook(event)
        self.assertEqual(r.returncode, 0,
                         f"expected exit 0 for unprotected path; got {r.returncode}\nstderr={r.stderr!r}")

    def test_deny_absolute_path_under_cwd_field(self):
        """Absolute path relativized via the event's own 'cwd' field."""
        import tempfile
        with tempfile.TemporaryDirectory() as proj:
            file_path = os.path.join(proj, "Assets", "Protected.txt")
            event = (
                '{"tool_name":"Write",'
                '"tool_input":{"file_path":"' + file_path.replace('\\', '\\\\') + '"},'
                '"cwd":"' + proj + '"}'
            )
            r = self._run_hook(event)
            self.assertEqual(r.returncode, 2,
                             f"expected exit 2 for absolute protected path via cwd; "
                             f"got {r.returncode}\nstderr={r.stderr!r}")

    def test_malformed_stdin_exits_3(self):
        r = self._run_hook("this is not json {{{")
        self.assertEqual(r.returncode, 3,
                         f"malformed stdin must exit 3; got {r.returncode}\nstderr={r.stderr!r}")

    def test_missing_binary_exits_nonzero(self):
        import subprocess
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            hooks_dir = os.path.join(tmpdir, "hooks")
            os.makedirs(hooks_dir)
            import shutil as _shutil
            script = str(_PKG / "hooks" / "pre-mutation-hook.sh")
            dest_script = os.path.join(hooks_dir, "pre-mutation-hook.sh")
            _shutil.copy2(script, dest_script)
            os.chmod(dest_script, 0o755)
            # Do NOT create bin/ — binary absent
            event = '{"tool_name":"Write","tool_input":{"file_path":"Assets/Protected.txt"}}'
            r = subprocess.run(
                ["bash", dest_script],
                input=event, capture_output=True, text=True,
            )
        self.assertEqual(r.returncode, 1,
                         f"missing binary must exit 1; got {r.returncode}\nstderr={r.stderr!r}")

    def test_path_with_double_quote_does_not_crash(self):
        event = '{"tool_name":"Write","tool_input":{"file_path":"Assets/\\"quote\\".txt"}}'
        r = self._run_hook(event)
        self.assertEqual(r.returncode, 0,
                         f"double-quote in non-protected path must exit 0; "
                         f"got {r.returncode}\nstderr={r.stderr!r}")


if __name__ == "__main__":
    unittest.main()
