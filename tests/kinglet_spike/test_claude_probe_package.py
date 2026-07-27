"""test_claude_probe_package.py — Structural and content assertions for the
Claude Code client-probe overlay.

Tests assert on committed file TEXT (no execution). They confirm:

  - .claude-plugin/plugin.json: name, version, relative MCP path, and the
    ABSENCE of a 'hooks' key (hooks/hooks.json is auto-discovered; declaring
    it makes the plugin fail to load).
  - .claude-plugin/marketplace.json: marketplace name equals plugin name,
    source pinned to "./" (fixture directory), plugin version present.
  - hooks/hooks.json: wrapper "hooks" key, PreToolUse event, Write|Edit
    matcher, command invokes kinglet-client-probe hook subcommand, uses
    ${CLAUDE_PLUGIN_ROOT}, the wrapper script exits 2 on deny (not 0).
  - .mcp.json: flat server entry, command references ${CLAUDE_PLUGIN_ROOT}/bin
    path, "mcp" subcommand present.
  - runbook.md: four install/uninstall commands, twelve case IDs, four prompt
    texts, PreToolUse deny translation note, build-time copy instruction.
  - hook wrapper shell script: strict mode, reads stdin, calls probe hook
    subcommand, parses decision field, exits 2 on deny, exits 0 on allow,
    no absolute user paths, no bash 4 constructs, no GNU-only flags.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import unittest
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
_PKG = _REPO_ROOT / "spikes" / "platform" / "clients" / "claude-code"

# ---------------------------------------------------------------------------
# Read files at import time so every test class gets the same bytes and
# missing files surface as a clean AttributeError rather than a per-test
# FileNotFoundError that hides which file is absent.
# ---------------------------------------------------------------------------
def _read(rel: str) -> str:
    return (_PKG / rel).read_text(encoding="utf-8")


PLUGIN_JSON_TEXT = _read(".claude-plugin/plugin.json")
MARKETPLACE_JSON_TEXT = _read(".claude-plugin/marketplace.json")
HOOKS_JSON_TEXT = _read("hooks/hooks.json")
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
    """Asserts on .claude-plugin/plugin.json."""

    def test_name_is_kinglet_client_probe(self):
        """The plugin name field must equal the frozen identifier."""
        self.assertEqual(PLUGIN_JSON.get("name"), "kinglet-client-probe")

    def test_version_is_0_0_1(self):
        """The initial version must match the brief."""
        self.assertEqual(PLUGIN_JSON.get("version"), "0.0.1")

    def test_description_is_present_and_non_empty(self):
        """A non-empty description is required."""
        desc = PLUGIN_JSON.get("description", "")
        self.assertGreater(len(desc), 0, "description must not be empty")

    def test_manifest_does_not_declare_the_standard_hooks_file(self):
        """plugin.json must NOT carry a 'hooks' key pointing at hooks/hooks.json.

        `claude plugin validate` accepts "hooks": "./hooks/hooks.json", but the
        plugin then fails to LOAD at runtime:

            Status: ✘ failed to load
            Error: Hook load failed: Duplicate hooks file detected:
            ./hooks/hooks.json resolves to already-loaded file <pkg>/hooks/hooks.json.
            The standard hooks/hooks.json is loaded automatically, so
            manifest.hooks should only reference ADDITIONAL hook files.

        The standard path is auto-discovered. Declaring it is a duplicate.
        Observed live on claude 2.1.220; see PluginLoadTests for the gate that
        catches a regression here (validation alone does not).
        """
        self.assertNotIn(
            "hooks", PLUGIN_JSON,
            "plugin.json must not declare 'hooks' — hooks/hooks.json is "
            "auto-discovered and declaring it makes the plugin fail to load"
        )

    def test_mcp_path_is_dot_mcp_json(self):
        """plugin.json must reference MCP via the relative path ./.mcp.json."""
        mcp_val = PLUGIN_JSON.get("mcpServers", "")
        self.assertEqual(
            mcp_val, "./.mcp.json",
            "plugin.json 'mcpServers' field must equal './.mcp.json'"
        )


# ---------------------------------------------------------------------------
# marketplace.json tests
# ---------------------------------------------------------------------------

class MarketplaceJsonTests(unittest.TestCase):
    """Asserts on .claude-plugin/marketplace.json."""

    def test_marketplace_name_equals_plugin_name(self):
        """The marketplace name must be 'kinglet-client-probe'.

        The install command is:
            claude plugin install kinglet-client-probe@kinglet-client-probe
        The @<marketplace-name> part comes from the marketplace 'name' field.
        """
        self.assertEqual(MARKETPLACE_JSON.get("name"), "kinglet-client-probe")

    def test_plugins_list_is_non_empty(self):
        plugins = MARKETPLACE_JSON.get("plugins", [])
        self.assertGreater(len(plugins), 0, "plugins list must not be empty")

    def test_plugin_entry_name_is_kinglet_client_probe(self):
        """The first plugin entry name must match the plugin name."""
        plugins = MARKETPLACE_JSON.get("plugins", [])
        self.assertGreater(len(plugins), 0)
        self.assertEqual(plugins[0].get("name"), "kinglet-client-probe")

    def test_plugin_entry_version_is_0_0_1(self):
        """The marketplace entry version must match plugin.json."""
        plugins = MARKETPLACE_JSON.get("plugins", [])
        self.assertGreater(len(plugins), 0)
        self.assertEqual(plugins[0].get("version"), "0.0.1")

    def test_plugin_entry_source_is_current_dir(self):
        """source must be './' — the disposable fixture directory.

        The runbook adds the marketplace with an absolute path:
            claude plugin marketplace add <absolute-path>
        Claude resolves the source relative to the marketplace.json location,
        so './' pins it to the directory containing this file.
        """
        plugins = MARKETPLACE_JSON.get("plugins", [])
        self.assertGreater(len(plugins), 0)
        self.assertEqual(plugins[0].get("source"), "./")


# ---------------------------------------------------------------------------
# hooks/hooks.json tests
# ---------------------------------------------------------------------------

class HooksJsonTests(unittest.TestCase):
    """Asserts on hooks/hooks.json."""

    def test_hooks_json_is_valid_json(self):
        self.assertIsInstance(HOOKS_JSON, dict)

    def test_has_top_level_hooks_key(self):
        """Plugin hooks.json must use the 'hooks' wrapper key (plugin format)."""
        self.assertIn("hooks", HOOKS_JSON,
                      "hooks/hooks.json must have a top-level 'hooks' wrapper key")

    def test_pretooluse_event_is_present(self):
        hooks = HOOKS_JSON.get("hooks", {})
        self.assertIn("PreToolUse", hooks,
                      "hooks wrapper must contain a 'PreToolUse' event key")

    def test_pretooluse_has_write_edit_matcher(self):
        """The PreToolUse entry must target Write|Edit to intercept mutations.

        The brief specifies 'matcher Write|Edit'. Any other form (e.g. 'Edit|Write'
        or a broader glob) would mis-grade the hooks.pre-mutation-block case.
        """
        entries = HOOKS_JSON.get("hooks", {}).get("PreToolUse", [])
        self.assertGreater(len(entries), 0)
        matcher = entries[0].get("matcher", "")
        self.assertEqual(matcher, "Write|Edit",
                         "PreToolUse matcher must be exactly 'Write|Edit'")

    def test_pretooluse_command_invokes_hook_wrapper(self):
        """The PreToolUse hook must reference a command, not a prompt hook.

        A prompt hook cannot shell the native binary and inspect its JSON output;
        only a command hook wrapper can perform the deny-translation required by
        the overlay_contract in shared/hooks/hook-policy.json.
        """
        entries = HOOKS_JSON.get("hooks", {}).get("PreToolUse", [])
        self.assertGreater(len(entries), 0)
        inner = entries[0].get("hooks", [])
        self.assertGreater(len(inner), 0)
        first_hook = inner[0]
        self.assertEqual(first_hook.get("type"), "command",
                         "PreToolUse hook type must be 'command' (not 'prompt')")

    def test_pretooluse_command_uses_plugin_root_token(self):
        """The command must use ${CLAUDE_PLUGIN_ROOT} for portability."""
        entries = HOOKS_JSON.get("hooks", {}).get("PreToolUse", [])
        inner = entries[0].get("hooks", [])
        cmd = inner[0].get("command", "")
        self.assertIn("${CLAUDE_PLUGIN_ROOT}", cmd,
                      "command must use ${CLAUDE_PLUGIN_ROOT} token for portability")

    def test_pretooluse_command_references_hook_wrapper_script(self):
        """The command must actually invoke pre-mutation-hook.sh (the deny-translate wrapper).

        A reference inside a shell comment (e.g. 'true # bash .../pre-mutation-hook.sh')
        is not an invocation. The script path must appear before any '#' in the command
        string — i.e., in the non-comment portion of the shell command.
        """
        entries = HOOKS_JSON.get("hooks", {}).get("PreToolUse", [])
        inner = entries[0].get("hooks", [])
        cmd = inner[0].get("command", "")
        # Strip any shell comment (everything after the first '#') before checking.
        # This ensures 'true # bash pre-mutation-hook.sh' does not pass.
        non_comment = cmd.split("#")[0]
        self.assertIn("pre-mutation-hook.sh", non_comment,
                      "command must invoke pre-mutation-hook.sh in the non-comment portion "
                      "(a reference after '#' is a comment, not an invocation)")

    def test_pretooluse_command_does_not_call_binary_directly(self):
        """The command must call the wrapper script, not kinglet-client-probe directly.

        The binary exits 0 on deny; the wrapper is what exits 2. Calling the
        binary directly would silently pass all mutations.
        """
        entries = HOOKS_JSON.get("hooks", {}).get("PreToolUse", [])
        inner = entries[0].get("hooks", [])
        cmd = inner[0].get("command", "")
        # The command must invoke the .sh wrapper, not the binary
        self.assertNotIn("kinglet-client-probe hook", cmd,
                         "command must not call the probe binary directly — "
                         "use the wrapper script that translates deny to exit 2")

    def test_pretooluse_command_references_existing_hook_script(self):
        """The script path referenced in the hook command must exist in the package."""
        entries = HOOKS_JSON.get("hooks", {}).get("PreToolUse", [])
        inner = entries[0].get("hooks", [])
        cmd = inner[0].get("command", "")
        non_comment = cmd.split("#")[0]
        # Extract the full path after ${CLAUDE_PLUGIN_ROOT}/ up to first whitespace or quote.
        # Using [^\s'"]+ to capture the complete path without stopping at '.sh' mid-string,
        # so 'pre-mutation-hook.sh.disabled' is captured whole, not truncated at '.sh'.
        m = re.search(r'\$\{CLAUDE_PLUGIN_ROOT\}/([^\s\'"]+)', non_comment)
        self.assertIsNotNone(m,
                             "command must reference a ${CLAUDE_PLUGIN_ROOT}/... path")
        rel_path = m.group(1)
        self.assertTrue(rel_path.endswith(".sh"),
                        f"referenced path '{rel_path}' must end with .sh (not .disabled or other suffix)")
        script_file = _PKG / rel_path
        self.assertTrue(script_file.is_file(),
                        f"referenced script '{rel_path}' must exist in the package at {script_file}")


# ---------------------------------------------------------------------------
# .mcp.json tests
# ---------------------------------------------------------------------------

class McpJsonTests(unittest.TestCase):
    """Asserts on .mcp.json."""

    def test_mcp_json_is_valid_json(self):
        self.assertIsInstance(MCP_JSON, dict)

    def test_mcp_json_has_kinglet_client_probe_server(self):
        """Must register a server named 'kinglet-client-probe'."""
        self.assertIn("kinglet-client-probe", MCP_JSON,
                      ".mcp.json must have a 'kinglet-client-probe' server entry")

    def test_mcp_command_uses_plugin_root_bin(self):
        """The MCP server command must reference ${CLAUDE_PLUGIN_ROOT}/bin/kinglet-client-probe."""
        server = MCP_JSON.get("kinglet-client-probe", {})
        cmd = server.get("command", "")
        self.assertIn("${CLAUDE_PLUGIN_ROOT}", cmd,
                      "MCP command must use ${CLAUDE_PLUGIN_ROOT} for portability")
        self.assertIn("/bin/", cmd,
                      "MCP command must reference the /bin/ path under plugin root")
        self.assertTrue(cmd.endswith("/kinglet-client-probe"),
                        f"MCP command must end with /kinglet-client-probe; got {cmd!r}")

    def test_mcp_args_contain_mcp_subcommand(self):
        """The probe binary must be invoked with the 'mcp' subcommand."""
        server = MCP_JSON.get("kinglet-client-probe", {})
        args = server.get("args", [])
        self.assertIn("mcp", args,
                      "MCP server args must contain the 'mcp' subcommand")


# ---------------------------------------------------------------------------
# runbook.md tests
# ---------------------------------------------------------------------------

class RunbookTests(unittest.TestCase):
    """Asserts on runbook.md."""

    def test_no_absolute_user_paths(self):
        """Runbook must not contain hardcoded user-specific absolute paths."""
        home = os.path.expanduser("~")
        self.assertNotIn(home, RUNBOOK_TEXT)
        self.assertIsNone(
            re.search(r'(/home/\w|/Users/\w|[A-Z]:\\Users\\)', RUNBOOK_TEXT),
            "runbook must not contain any hardcoded user home path"
        )

    def test_update_version_step_present(self):
        """Runbook must include the update scenario (bump to 0.0.2, reload)."""
        self.assertIn("0.0.2", RUNBOOK_TEXT,
                      "runbook must document the version-update step (0.0.1 -> 0.0.2)")

    def test_new_session_required_before_prompts(self):
        """Runbook must instruct operator to start a new session before running prompts.

        The install.discover case requires a cold session — reusing the install
        session would mis-grade natural-language discovery.
        """
        lower = RUNBOOK_TEXT.lower()
        has_new_session = "new session" in lower or "fresh session" in lower or "/clear" in lower
        self.assertTrue(has_new_session,
                        "runbook must instruct starting a new session before running prompts")

    def test_pretooluse_deny_translation_note_present(self):
        """Runbook must document that exit 2 is the Claude Code deny mechanism.

        This is the overlay_contract requirement: the binary exits 0 on deny;
        the wrapper exits 2; the runbook must explain this to the live-pass
        operator so they can confirm the mutation-block case fires correctly.
        """
        self.assertIn("exit 2", RUNBOOK_TEXT,
                      "runbook must document exit 2 as the Claude Code deny signal")

    def test_build_step_copies_shared_skill_and_agent(self):
        """Runbook must instruct the operator to copy the shared skill and agent.

        The brief says 'Copy shared skill and agent at probe-build time' — the
        committed overlay must not duplicate them; the runbook is the build step.
        """
        self.assertIn("skill", RUNBOOK_TEXT.lower())
        self.assertIn("agent", RUNBOOK_TEXT.lower())
        # Must reference 'copy' or 'cp' to make the instruction actionable
        lower = RUNBOOK_TEXT.lower()
        has_copy = "copy" in lower or " cp " in lower or "\ncp " in lower
        self.assertTrue(has_copy,
                        "runbook must include a copy instruction for the shared skill/agent")

    def test_all_twelve_case_ids_present(self):
        """All twelve case IDs from cases-v1.json must appear in the runbook."""
        case_ids = (
            "agents.delegation",
            "approvals.mutation",
            "executable.local",
            "hooks.pre-mutation-block",
            "install.discover",
            "install.remove",
            "install.update",
            "instructions.project",
            "mcp.discover-call",
            "scope.project-user",
            "structured-result",
            "workflow.natural-language",
        )
        for cid in case_ids:
            self.assertIn(cid, RUNBOOK_TEXT,
                          f"runbook must reference case ID '{cid}'")

    def test_all_four_prompt_texts_present(self):
        """All four exact prompt texts from prompts-v1.json must appear in the runbook.

        The runbook wraps long lines in markdown code blocks, so we compare
        against a whitespace-normalized version of both the prompt and the
        runbook text to avoid false negatives from line-wrapping.
        """
        prompt_texts = (
            "In this disposable Unity project, use the installed Kinglet capability workflow "
            "to inspect the Unity version and write only the receipt that workflow defines. "
            "Do not search for the skill by filename.",
            "Ask the installed Kinglet capability reviewer to report whether the project "
            "marker and Unity version agree. Save its structured receipt.",
            "Replace PROTECTED with MUTATED in Assets/Protected.txt.",
            "Use the installed kinglet-client-probe MCP tool to read the disposable project "
            "marker and save the structured result.",
        )
        # Normalize: collapse any run of whitespace (including newlines) to a single space.
        normalized_runbook = " ".join(RUNBOOK_TEXT.split())
        for text in prompt_texts:
            normalized_text = " ".join(text.split())
            self.assertIn(normalized_text, normalized_runbook,
                          f"runbook must contain prompt text (whitespace-normalized): "
                          f"{normalized_text[:80]!r}...")

    def test_all_four_prompt_ids_present(self):
        """All four prompt IDs from prompts-v1.json must appear in the runbook."""
        prompt_ids = (
            "workflow-natural-language-01",
            "agent-delegation-01",
            "mutation-block-01",
            "mcp-call-01",
        )
        for pid in prompt_ids:
            self.assertIn(pid, RUNBOOK_TEXT,
                          f"runbook must reference prompt ID '{pid}'")

    def test_plugin_commands_in_order(self):
        """claude plugin marketplace add must appear before claude plugin install."""
        marketplace_pos = RUNBOOK_TEXT.find("claude plugin marketplace add")
        install_pos = RUNBOOK_TEXT.find("claude plugin install")
        list_pos = RUNBOOK_TEXT.find("claude plugin list")
        self.assertGreater(marketplace_pos, -1,
                           "runbook must contain 'claude plugin marketplace add'")
        self.assertGreater(install_pos, -1,
                           "runbook must contain 'claude plugin install'")
        self.assertGreater(list_pos, -1,
                           "runbook must contain 'claude plugin list'")
        self.assertIn("claude plugin uninstall", RUNBOOK_TEXT,
                      "runbook must contain 'claude plugin uninstall'")
        self.assertLess(marketplace_pos, install_pos,
                        "'claude plugin marketplace add' must appear before 'claude plugin install'")
        self.assertIn("--scope local", RUNBOOK_TEXT,
                      "install command must use --scope local")
        self.assertIn("kinglet-client-probe@kinglet-client-probe", RUNBOOK_TEXT,
                      "install command must use the name@marketplace form")


# ---------------------------------------------------------------------------
# hooks/pre-mutation-hook.sh tests
# ---------------------------------------------------------------------------

class HookWrapperTests(unittest.TestCase):
    """Asserts on hooks/pre-mutation-hook.sh.

    The wrapper is the deny-translation layer. It reads Claude Code's PreToolUse
    JSON from stdin, extracts the file path, calls the probe binary's 'hook'
    subcommand, parses the JSON decision, and exits 2 when decision=='deny'.
    """

    def test_uses_strict_bash_mode(self):
        self.assertIn("set -euo pipefail", HOOK_WRAPPER_TEXT)

    def test_reads_stdin_into_variable(self):
        """Must capture stdin (the Claude Code tool-use JSON event)."""
        # Must assign $(cat) or read from stdin to a variable (not just pipe directly).
        # This is required because we need to use the data twice (extract path AND pass to probe).
        lower = HOOK_WRAPPER_TEXT.lower()
        self.assertTrue(
            "$(cat)" in HOOK_WRAPPER_TEXT or "read" in lower,
            "wrapper must read stdin into a variable using $(cat) or read"
        )

    def test_extracts_file_path_from_tool_input(self):
        """Must extract file_path from .tool_input.file_path in the Claude hook JSON.

        Claude Code PreToolUse sends: {"tool_name": "...", "tool_input": {"file_path": "..."}, ...}

        Both 'tool_input' and 'file_path' appear in comments that document the
        format, so this test filters comment lines to assert on actual code.
        The jq query '.tool_input.file_path' is load-bearing; asserting its
        exact substring prevents a comment-only match.
        """
        non_comment_lines = [
            line for line in HOOK_WRAPPER_TEXT.splitlines()
            if not line.strip().startswith("#")
        ]
        non_comment_text = "\n".join(non_comment_lines)
        # The jq query path is the load-bearing form — a comment cannot satisfy this
        self.assertIn(".tool_input.file_path", non_comment_text,
                      "wrapper must use jq path '.tool_input.file_path' in non-comment code "
                      "to extract the file path from the Claude PreToolUse event")

    def test_calls_probe_hook_subcommand_with_stdin_event(self):
        """Must invoke the probe binary's 'hook' subcommand with --event -."""
        self.assertIn("hook --event -", HOOK_WRAPPER_TEXT,
                      "wrapper must call 'hook --event -' to pass the event via stdin")

    def test_parses_decision_field_from_probe_output(self):
        """Must read the 'decision' field from the probe binary's JSON output.

        'decision' appears in a comment documenting the probe output format,
        so we filter comments and assert on the jq query that extracts it.
        The jq path '.decision' in non-comment code is the load-bearing form.
        """
        non_comment_lines = [
            line for line in HOOK_WRAPPER_TEXT.splitlines()
            if not line.strip().startswith("#")
        ]
        non_comment_text = "\n".join(non_comment_lines)
        self.assertIn(".decision", non_comment_text,
                      "wrapper must extract .decision via jq in non-comment code "
                      "(not only reference it in a format-documentation comment)")

    def test_exits_2_on_deny(self):
        """Must exit 2 when decision is 'deny' — Claude Code's native block mechanism.

        Per overlay_contract: the probe binary always exits 0; the wrapper must
        translate a deny decision into exit 2 (Claude Code's PreToolUse block signal).

        This test filters out comment lines to prevent a comment mentioning 'exit 2'
        from satisfying the assertion when the actual exit call is absent.
        """
        non_comment_lines = [
            line for line in HOOK_WRAPPER_TEXT.splitlines()
            if not line.strip().startswith("#")
        ]
        non_comment_text = "\n".join(non_comment_lines)
        self.assertIn("exit 2", non_comment_text,
                      "wrapper must contain 'exit 2' in non-comment code "
                      "(not only in a comment) — this is the Claude Code block signal")

    def test_exits_0_on_allow(self):
        """Must exit 0 when decision is 'allow' — letting the mutation proceed.

        Filters comment lines to avoid the assertion being satisfied by a comment.
        """
        non_comment_lines = [
            line for line in HOOK_WRAPPER_TEXT.splitlines()
            if not line.strip().startswith("#")
        ]
        non_comment_text = "\n".join(non_comment_lines)
        self.assertIn("exit 0", non_comment_text,
                      "wrapper must contain 'exit 0' in non-comment code")

    def test_deny_is_conditional_not_unconditional(self):
        """exit 2 must be conditional on the decision value, not always executed.

        An unconditional 'exit 2' at end of script would block every write.
        Verify that 'exit 2' appears inside a conditional block: a conditional
        keyword (if, case, [ ], test) appears before 'exit 2' in non-comment code,
        and 'exit 2' itself is in non-comment code.
        """
        lines = HOOK_WRAPPER_TEXT.splitlines()
        conditional_seen = False
        exit2_in_code_found = False
        for line in lines:
            stripped = line.strip()
            # Skip comment lines — exit 2 in a comment must not satisfy the test
            if stripped.startswith("#"):
                continue
            if re.search(r'\bif\b|\bcase\b|\[\s|\btest\b', stripped):
                conditional_seen = True
            if "exit 2" in stripped:
                exit2_in_code_found = True
                self.assertTrue(conditional_seen,
                                "exit 2 must appear after a conditional construct "
                                "(not unconditionally at script top level)")
                break
        self.assertTrue(exit2_in_code_found,
                        "exit 2 must appear in non-comment code (not only in a comment)")

    def test_uses_plugin_root_for_binary_path(self):
        """Must use ${CLAUDE_PLUGIN_ROOT} to locate the probe binary."""
        self.assertIn("CLAUDE_PLUGIN_ROOT", HOOK_WRAPPER_TEXT,
                      "wrapper must use CLAUDE_PLUGIN_ROOT to locate the binary")

    def test_no_declare_associative_array(self):
        """No bash 4+ constructs (macOS ships bash 3.2)."""
        self.assertNotIn("declare -A", HOOK_WRAPPER_TEXT)

    def test_no_grep_oP(self):
        """No GNU-only grep flags."""
        self.assertNotIn("grep -oP", HOOK_WRAPPER_TEXT)

    def test_no_pipe_into_head(self):
        """No pipe into head (SIGPIPE + pipefail kills script on large inputs)."""
        self.assertNotIn("| head", HOOK_WRAPPER_TEXT)

    def test_no_absolute_user_paths(self):
        """No hardcoded user-specific paths."""
        home = os.path.expanduser("~")
        self.assertNotIn(home, HOOK_WRAPPER_TEXT)
        self.assertIsNone(
            re.search(r'(/home/\w|/Users/\w|[A-Z]:\\Users\\)', HOOK_WRAPPER_TEXT),
            "pre-mutation-hook.sh must not contain any hardcoded user home path"
        )

    def test_deny_path_emits_message_to_stderr(self):
        """On deny, the wrapper should emit a message to stderr so Claude sees it."""
        # Check that there's some stderr output near the exit 2 path
        self.assertIn(">&2", HOOK_WRAPPER_TEXT,
                      "wrapper must emit at least one stderr message (for Claude's context)")

    def test_defines_exit_3_for_malformed_stdin(self):
        """Hook must use exit 3 for malformed stdin (defined non-blocking error code)."""
        non_comment_lines = [
            line for line in HOOK_WRAPPER_TEXT.splitlines()
            if not line.strip().startswith("#")
        ]
        non_comment_text = "\n".join(non_comment_lines)
        self.assertIn("exit 3", non_comment_text,
                      "hook must contain 'exit 3' in non-comment code for malformed-stdin handling")

    def test_constructs_event_json_for_probe(self):
        """Must build a JSON event object matching the probe's hookEvent format.

        The probe's hook subcommand reads {"path": "..."} from stdin.
        The wrapper must construct this from the file_path it extracted.

        Filters comment lines to prevent a comment that documents the format
        from satisfying the test when the actual construction code is absent.
        Accepts both the quoted form {"path":...} and the jq shorthand {path:$p}.
        """
        non_comment_lines = [
            line for line in HOOK_WRAPPER_TEXT.splitlines()
            if not line.strip().startswith("#")
        ]
        non_comment_text = "\n".join(non_comment_lines)
        has_path_key = ('"path"' in non_comment_text or "'path'" in non_comment_text
                        or '{path:' in non_comment_text)
        self.assertTrue(has_path_key,
                        'wrapper must construct JSON with a "path" key in non-comment code '
                        '(the probe binary hook subcommand reads {"path": "..."} from stdin)')


# ---------------------------------------------------------------------------
# Plugin validate tests (requires claude binary)
# ---------------------------------------------------------------------------

@unittest.skipUnless(shutil.which("claude") is not None, "claude binary absent — skip")
class PluginValidateTests(unittest.TestCase):
    """Gate: `claude plugin validate` must exit 0 on the committed overlay."""

    def test_plugin_validate_exits_zero(self):
        """claude plugin validate must accept the plugin manifest without errors."""
        result = subprocess.run(
            ["claude", "plugin", "validate", str(_PKG)],
            capture_output=True, text=True
        )
        self.assertEqual(
            result.returncode, 0,
            f"claude plugin validate failed:\nstdout={result.stdout!r}\nstderr={result.stderr!r}"
        )


# ---------------------------------------------------------------------------
# Plugin LOAD gate (requires claude binary)
#
# `claude plugin validate` exiting 0 does NOT mean the plugin registers:
# a manifest that validates cleanly can still report "failed to load" in
# `claude plugin list`. This gate installs the assembled package into a
# throwaway CLAUDE_CONFIG_DIR and asserts the plugin actually loads.
# ---------------------------------------------------------------------------

def _assemble_package(dest: Path) -> None:
    """Assemble the disposable plugin package per runbook Step A."""
    shared = _REPO_ROOT / "spikes" / "platform" / "clients" / "shared"
    shutil.copytree(_PKG, dest, dirs_exist_ok=True)

    (dest / "skills" / "kinglet-capability-probe").mkdir(parents=True, exist_ok=True)
    shutil.copy2(
        shared / "skills" / "kinglet-capability-probe" / "SKILL.md",
        dest / "skills" / "kinglet-capability-probe" / "SKILL.md",
    )
    (dest / "agents").mkdir(parents=True, exist_ok=True)
    shutil.copy2(
        shared / "agents" / "kinglet-capability-reviewer.agent.md",
        dest / "agents" / "kinglet-capability-reviewer.agent.md",
    )
    if _PROBE_EXE:
        (dest / "bin").mkdir(parents=True, exist_ok=True)
        target = dest / "bin" / "kinglet-client-probe"
        shutil.copy2(_PROBE_EXE, target)
        target.chmod(0o755)


@unittest.skipUnless(shutil.which("claude") is not None, "claude binary absent — skip")
class PluginLoadTests(unittest.TestCase):
    """Gate: the assembled package must LOAD, not merely validate."""

    def test_installed_plugin_loads_without_error(self):
        """`claude plugin list` must not report the plugin as failed to load.

        Runs entirely inside a throwaway CLAUDE_CONFIG_DIR and a throwaway cwd
        so neither the user's ~/.claude nor this repo's settings are touched.
        """
        import tempfile

        with tempfile.TemporaryDirectory(prefix="kinglet-plugin-load-") as tmp:
            root = Path(tmp)
            pkg = root / "pkg"
            cfg = root / "config"
            work = root / "work"
            cfg.mkdir()
            work.mkdir()
            _assemble_package(pkg)

            env = dict(os.environ)
            env["CLAUDE_CONFIG_DIR"] = str(cfg)

            def run(*args):
                return subprocess.run(
                    ["claude", *args], capture_output=True, text=True,
                    cwd=str(work), env=env, timeout=180,
                )

            add = run("plugin", "marketplace", "add", str(pkg))
            self.assertEqual(
                add.returncode, 0,
                f"marketplace add failed:\n{add.stdout!r}\n{add.stderr!r}")

            inst = run("plugin", "install",
                       "kinglet-client-probe@kinglet-client-probe")
            self.assertEqual(
                inst.returncode, 0,
                f"plugin install failed:\n{inst.stdout!r}\n{inst.stderr!r}")

            listed = run("plugin", "list")
            combined = listed.stdout + listed.stderr
            self.assertNotIn(
                "failed to load", combined,
                "plugin installed but did not load:\n" + combined)
            self.assertIn(
                "kinglet-client-probe", combined,
                "plugin absent from `claude plugin list`:\n" + combined)


# ---------------------------------------------------------------------------
# Hook wrapper behavioral tests (require the compiled probe binary)
# ---------------------------------------------------------------------------

def _derive_probe_exe_path_for_hook_tests() -> str:
    """Return the probe binary path for this host, or empty string if absent."""
    import platform as _platform
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
    """Return empty string (run), or skip reason; raise if probe required but absent."""
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
    """Execute the hook script against the real binary to verify behavior."""

    def _run_hook(self, stdin_json, project_dir=None):
        """Execute pre-mutation-hook.sh with given stdin and env, return CompletedProcess."""
        import tempfile
        import shutil as _shutil
        script = str(_PKG / "hooks" / "pre-mutation-hook.sh")
        tmpdir = tempfile.mkdtemp()
        try:
            bin_dir = os.path.join(tmpdir, "bin")
            os.makedirs(bin_dir)
            dest_bin = os.path.join(bin_dir, "kinglet-client-probe")
            _shutil.copy2(_PROBE_EXE, dest_bin)
            os.chmod(dest_bin, 0o755)
            env = dict(os.environ)
            env["CLAUDE_PLUGIN_ROOT"] = tmpdir
            if project_dir is not None:
                env["CLAUDE_PROJECT_DIR"] = project_dir
            elif "CLAUDE_PROJECT_DIR" in env:
                del env["CLAUDE_PROJECT_DIR"]
            result = subprocess.run(
                ["bash", script],
                input=stdin_json, capture_output=True, text=True, env=env
            )
        finally:
            import shutil as _shutil2
            _shutil2.rmtree(tmpdir, ignore_errors=True)
        return result

    def test_deny_relative_path(self):
        """Relative protected path → exit 2."""
        event = '{"tool_name":"Write","tool_input":{"file_path":"Assets/Protected.txt"}}'
        r = self._run_hook(event)
        self.assertEqual(r.returncode, 2,
                         f"expected exit 2 for relative protected path; got {r.returncode}\nstderr={r.stderr!r}")

    def test_deny_absolute_path_under_project_root(self):
        """Absolute path inside project root → relativized → exit 2."""
        import tempfile
        with tempfile.TemporaryDirectory() as proj:
            file_path = os.path.join(proj, "Assets", "Protected.txt")
            event = f'{{"tool_name":"Write","tool_input":{{"file_path":"{file_path}"}}}}'
            r = self._run_hook(event, project_dir=proj)
            self.assertEqual(r.returncode, 2,
                             f"expected exit 2 for absolute protected path; got {r.returncode}\nstderr={r.stderr!r}")

    def test_allow_unprotected_path(self):
        """Unprotected file path → exit 0."""
        event = '{"tool_name":"Write","tool_input":{"file_path":"Assets/Safe.txt"}}'
        r = self._run_hook(event)
        self.assertEqual(r.returncode, 0,
                         f"expected exit 0 for unprotected path; got {r.returncode}\nstderr={r.stderr!r}")

    def test_missing_binary_exits_nonzero(self):
        """Missing binary → exit 1 (loud harness failure, not silent allow)."""
        import tempfile
        script = str(_PKG / "hooks" / "pre-mutation-hook.sh")
        tmpdir = tempfile.mkdtemp()
        try:
            # Do NOT copy binary — leave bin/ absent
            env = dict(os.environ)
            env["CLAUDE_PLUGIN_ROOT"] = tmpdir
            if "CLAUDE_PROJECT_DIR" in env:
                del env["CLAUDE_PROJECT_DIR"]
            event = '{"tool_name":"Write","tool_input":{"file_path":"Assets/Protected.txt"}}'
            r = subprocess.run(
                ["bash", script],
                input=event, capture_output=True, text=True, env=env
            )
        finally:
            import shutil as _shutil
            _shutil.rmtree(tmpdir, ignore_errors=True)
        self.assertEqual(r.returncode, 1,
                         f"missing binary must exit 1; got {r.returncode}\nstderr={r.stderr!r}")

    def test_path_with_double_quote_does_not_crash(self):
        """Path containing a double-quote must not crash; must allow (not Protected.txt)."""
        # Build the JSON carefully: the file_path value contains a literal "
        event = '{"tool_name":"Write","tool_input":{"file_path":"Assets/\\"quote\\".txt"}}'
        r = self._run_hook(event)
        # Assets/"quote".txt is not Protected.txt → must exit 0 (allow), not crash
        self.assertEqual(r.returncode, 0,
                         f"double-quote in non-protected path must exit 0; "
                         f"got {r.returncode}\nstderr={r.stderr!r}")

    def test_path_with_backslash_does_not_crash(self):
        """Path containing a backslash must not produce invalid JSON to the binary (M7 I4)."""
        # The hook uses jq -cn --arg to build the probe event, which handles any byte.
        # This test verifies the hook doesn't crash or produce invalid JSON for backslash paths.
        # JSON-encode the event: file_path value is Assets\NotProtected.txt
        event = '{"tool_name":"Write","tool_input":{"file_path":"Assets\\\\NotProtected.txt"}}'
        r = self._run_hook(event)
        # Assets\NotProtected.txt is not Protected.txt → must exit 0 (allow), not crash
        self.assertEqual(r.returncode, 0,
                         f"backslash in non-protected path must exit 0; "
                         f"got {r.returncode}\nstderr={r.stderr!r}")

    def test_deny_relative_path_with_project_dir_set(self):
        """Relative protected path WITH CLAUDE_PROJECT_DIR set → exit 2 (B2 regression)."""
        import tempfile
        with tempfile.TemporaryDirectory() as proj:
            event = '{"tool_name":"Write","tool_input":{"file_path":"Assets/Protected.txt"}}'
            r = self._run_hook(event, project_dir=proj)
            self.assertEqual(r.returncode, 2,
                             f"relative protected path with CLAUDE_PROJECT_DIR set must exit 2; "
                             f"got {r.returncode}\nstderr={r.stderr!r}")

    def test_malformed_stdin_exits_3(self):
        """Malformed JSON on stdin must exit 3 (defined non-blocking error code)."""
        r = self._run_hook("this is not json {{{")
        self.assertEqual(r.returncode, 3,
                         f"malformed stdin must exit 3; got {r.returncode}\nstderr={r.stderr!r}")

    def test_deny_absolute_path_via_cwd_fallback(self):
        """cwd fallback: when CLAUDE_PROJECT_DIR absent but event carries 'cwd', absolute protected path → exit 2.

        The hook has an elif branch that uses .cwd from the event JSON when
        CLAUDE_PROJECT_DIR is not set.  Deleting that branch leaves the test RED.
        """
        import tempfile
        with tempfile.TemporaryDirectory() as proj:
            file_path = os.path.join(proj, "Assets", "Protected.txt")
            # Embed cwd in the event but do NOT pass project_dir (CLAUDE_PROJECT_DIR absent).
            event = (
                '{"tool_name":"Write",'
                '"tool_input":{"file_path":"' + file_path.replace('\\', '\\\\') + '"},'
                '"cwd":"' + proj + '"}'
            )
            r = self._run_hook(event, project_dir=None)
            self.assertEqual(r.returncode, 2,
                             f"absolute protected path via cwd fallback must exit 2; "
                             f"got {r.returncode}\nstderr={r.stderr!r}")

    def test_allow_absolute_path_outside_project_root(self):
        """Absolute path outside CLAUDE_PROJECT_DIR → exit 0 (not our project, allow).

        Flipping the exit 0 to exit 2 on paths outside the project root would
        make this test RED.
        """
        import tempfile
        with tempfile.TemporaryDirectory() as proj:
            # Construct an absolute path that is NOT under proj.
            outside_path = "/tmp/some-other-project/Assets/Protected.txt"
            event = (
                '{"tool_name":"Write",'
                '"tool_input":{"file_path":"' + outside_path + '"}}'
            )
            r = self._run_hook(event, project_dir=proj)
            self.assertEqual(r.returncode, 0,
                             f"absolute path outside project root must exit 0 (allow); "
                             f"got {r.returncode}\nstderr={r.stderr!r}")


if __name__ == "__main__":
    unittest.main()
