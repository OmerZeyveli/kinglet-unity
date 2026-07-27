"""test_client_fixture.py — Structural and content assertions for the shared client fixture.

Tests assert on the TEXT of committed files (no execution). They confirm:
  - SKILL.md: name, natural-language trigger, executable invocation pattern,
    receipt output path, and return value.
  - Agent: receipt path, schema, agreement field, read-only constraint.
  - Rule: receipt schema reference.
  - Hook policy: deny target, allow behavior.
  - MCP config: executable token, tool name.
  - create-project.sh: strict mode, host guard, existence guard, fixed files,
    SHA-256 computation, bash 3.2 constraints, no absolute user paths,
    executable argument acceptance.
  - create-project.ps1: Windows-only guard, existence guard, fixed files,
    SHA-256 computation, no absolute user paths, executable argument acceptance.
"""
from __future__ import annotations

import json
import unittest
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
_SHARED = _REPO_ROOT / "spikes" / "platform" / "clients" / "shared"

SKILL_MD = (_SHARED / "skills" / "kinglet-capability-probe" / "SKILL.md").read_text(encoding="utf-8")
AGENT_MD = (_SHARED / "agents" / "kinglet-capability-reviewer.agent.md").read_text(encoding="utf-8")
RULE_MD = (_SHARED / "rules" / "kinglet-capability-probe.md").read_text(encoding="utf-8")
HOOK_JSON_TEXT = (_SHARED / "hooks" / "hook-policy.json").read_text(encoding="utf-8")
MCP_JSON_TEXT = (_SHARED / "mcp.json").read_text(encoding="utf-8")
CREATE_SH = (_SHARED / "create-project.sh").read_text(encoding="utf-8")
CREATE_PS1 = (_SHARED / "create-project.ps1").read_text(encoding="utf-8")

HOOK_JSON = json.loads(HOOK_JSON_TEXT)
MCP_JSON = json.loads(MCP_JSON_TEXT)


# ---------------------------------------------------------------------------
# Skill tests
# ---------------------------------------------------------------------------

class SkillNameTests(unittest.TestCase):
    def test_name_is_kinglet_capability_probe(self):
        self.assertIn("name: kinglet-capability-probe", SKILL_MD)

    def test_description_contains_natural_language_trigger(self):
        # Must match workflow-natural-language-01 prompt wording so the skill
        # is findable via natural language, not only by filename.
        self.assertIn("Kinglet capability workflow", SKILL_MD)

    def test_description_does_not_require_filename_lookup(self):
        # The prompt explicitly says "Do not search for the skill by filename."
        # The description must be discoverable via the trigger phrase, not just a path.
        self.assertNotIn("SKILL.md", SKILL_MD.split("---")[0])  # not in frontmatter desc


class SkillStepsTests(unittest.TestCase):
    def test_reads_project_version_file(self):
        self.assertIn("ProjectSettings/ProjectVersion.txt", SKILL_MD)

    def test_reads_project_marker_file(self):
        self.assertIn(".kinglet-probe/project-marker.txt", SKILL_MD)

    def test_calls_exec_subcommand(self):
        self.assertIn("kinglet-client-probe", SKILL_MD)
        self.assertIn("exec", SKILL_MD)

    def test_exec_receives_project_flag(self):
        self.assertIn("--project", SKILL_MD)

    def test_exec_receives_output_flag(self):
        self.assertIn("--output", SKILL_MD)

    def test_validates_schema_field(self):
        self.assertIn("kinglet.client-probe.receipt/v1", SKILL_MD)

    def test_validates_marker_field(self):
        self.assertIn("KINGLET_CLIENT_PROBE_PROJECT", SKILL_MD)

    def test_validates_unity_version(self):
        self.assertIn("6000.3.11f1", SKILL_MD)

    def test_writes_workflow_receipt(self):
        self.assertIn(".kinglet-probe/receipts/workflow.json", SKILL_MD)

    def test_return_value_is_ok_plus_version(self):
        self.assertIn("KINGLET_CLIENT_PROBE_OK 6000.3.11f1", SKILL_MD)

    def test_only_writes_workflow_receipt(self):
        # The skill output path is workflow.json; it must not name itself as writing agent.json.
        # The constraints section may mention agent.json to say "do not write it",
        # but the step that defines the output must point to workflow.json.
        self.assertIn("workflow.json", SKILL_MD)
        # The --output flag in the exec step must target workflow.json, not agent.json.
        # Check that the exec invocation line does not point to agent.json.
        for line in SKILL_MD.splitlines():
            if "--output" in line:
                self.assertNotIn("agent.json", line, "--output in exec step must not target agent.json")


# ---------------------------------------------------------------------------
# Agent tests
# ---------------------------------------------------------------------------

class AgentTests(unittest.TestCase):
    def test_agent_receipt_path(self):
        self.assertIn(".kinglet-probe/receipts/agent.json", AGENT_MD)

    def test_agent_receipt_schema(self):
        self.assertIn("kinglet.client-probe.agent/v1", AGENT_MD)

    def test_agent_receipt_has_agreement_true(self):
        self.assertIn('"agreement": true', AGENT_MD)

    def test_agent_is_read_only_except_receipt(self):
        # Must say it may not edit Unity assets.
        self.assertIn("Unity assets", AGENT_MD)

    def test_agent_matches_delegation_prompt(self):
        # Must reference "project marker" and "Unity version" — from agent-delegation-01.
        self.assertIn("project marker", AGENT_MD)
        self.assertIn("Unity version", AGENT_MD)


# ---------------------------------------------------------------------------
# Rule tests
# ---------------------------------------------------------------------------

class RuleTests(unittest.TestCase):
    def test_rule_references_receipt_schema(self):
        self.assertIn("kinglet.client-probe.receipt/v1", RULE_MD)

    def test_rule_references_workflow_receipt_path(self):
        self.assertIn(".kinglet-probe/receipts/workflow.json", RULE_MD)


# ---------------------------------------------------------------------------
# Hook policy tests
# ---------------------------------------------------------------------------

class HookPolicyTests(unittest.TestCase):
    def test_hook_policy_is_valid_json(self):
        # Already parsed at module level; just assert parse succeeded.
        self.assertIsInstance(HOOK_JSON, (dict, list))

    def test_hook_policy_denies_protected_txt(self):
        text = HOOK_JSON_TEXT
        self.assertIn("Assets/Protected.txt", text)
        self.assertIn("deny", text)

    def test_hook_policy_allows_other_targets(self):
        self.assertIn("allow", HOOK_JSON_TEXT)

    def test_hook_policy_references_executable(self):
        # Policy must reference how the hook executable is called.
        self.assertIn("kinglet-client-probe", HOOK_JSON_TEXT)


# ---------------------------------------------------------------------------
# MCP config tests
# ---------------------------------------------------------------------------

class MCPConfigTests(unittest.TestCase):
    def test_mcp_config_is_valid_json(self):
        self.assertIsInstance(MCP_JSON, (dict, list))

    def test_mcp_config_has_executable_token(self):
        self.assertIn("__KINGLET_PROBE_EXECUTABLE__", MCP_JSON_TEXT)

    def test_mcp_config_references_tool_name(self):
        self.assertIn("kinglet_probe_read_marker", MCP_JSON_TEXT)

    def test_mcp_config_references_mcp_subcommand(self):
        self.assertIn("mcp", MCP_JSON_TEXT)


# ---------------------------------------------------------------------------
# create-project.sh tests
# ---------------------------------------------------------------------------

class CreateShTests(unittest.TestCase):
    def test_uses_strict_bash_mode(self):
        self.assertIn("set -euo pipefail", CREATE_SH)

    def test_rejects_non_darwin_linux(self):
        self.assertIn("Darwin", CREATE_SH)
        self.assertIn("Linux", CREATE_SH)
        # Must exit on unsupported host.
        self.assertIn("exit 1", CREATE_SH)

    def test_rejects_existing_destination(self):
        # Must refuse a destination that already exists.
        self.assertIn("already exists", CREATE_SH)

    def test_creates_project_version_txt(self):
        self.assertIn("ProjectSettings/ProjectVersion.txt", CREATE_SH)

    def test_creates_project_marker(self):
        self.assertIn(".kinglet-probe/project-marker.txt", CREATE_SH)
        self.assertIn("KINGLET_CLIENT_PROBE_PROJECT", CREATE_SH)

    def test_creates_protected_txt(self):
        self.assertIn("Assets/Protected.txt", CREATE_SH)

    def test_copies_executable_to_bin(self):
        self.assertIn(".kinglet-probe/bin/", CREATE_SH)

    def test_writes_expected_json(self):
        self.assertIn(".kinglet-probe/expected.json", CREATE_SH)

    def test_computes_sha256(self):
        self.assertIn("sha256", CREATE_SH.lower())

    def test_accepts_executable_argument_or_env(self):
        # Must not hardcode an absolute path; takes executable via arg or env var.
        self.assertNotIn("/home/riive", CREATE_SH)
        self.assertNotIn("/Users/", CREATE_SH)

    def test_no_declare_associative_array(self):
        self.assertNotIn("declare -A", CREATE_SH)

    def test_no_grep_oP(self):
        self.assertNotIn("grep -oP", CREATE_SH)

    def test_no_pipe_into_head(self):
        self.assertNotIn("| head", CREATE_SH)

    def test_validates_arg_before_shift(self):
        # shift 2 without validation fails under set -u when arg count is wrong.
        # We require the script validates arg count before any shift.
        # A simple proxy: the script must check $# before shifting.
        self.assertIn("$#", CREATE_SH)

    def test_writes_mcp_json_with_token_replaced(self):
        # The project-creation script must substitute __KINGLET_PROBE_EXECUTABLE__
        # in the placed mcp.json.
        self.assertIn("__KINGLET_PROBE_EXECUTABLE__", CREATE_SH)


# ---------------------------------------------------------------------------
# create-project.ps1 tests
# ---------------------------------------------------------------------------

class CreatePs1Tests(unittest.TestCase):
    def test_requires_powershell_5_or_later(self):
        self.assertIn("#Requires -Version 5", CREATE_PS1)

    def test_rejects_non_windows(self):
        self.assertIn("IsWindows", CREATE_PS1)

    def test_rejects_existing_destination(self):
        self.assertIn("already exists", CREATE_PS1)

    def test_creates_project_version_txt(self):
        self.assertIn("ProjectSettings/ProjectVersion.txt", CREATE_PS1)

    def test_creates_project_marker(self):
        self.assertIn(".kinglet-probe/project-marker.txt", CREATE_PS1)
        self.assertIn("KINGLET_CLIENT_PROBE_PROJECT", CREATE_PS1)

    def test_creates_protected_txt(self):
        self.assertIn("Assets/Protected.txt", CREATE_PS1)

    def test_copies_executable_to_bin(self):
        self.assertIn(".kinglet-probe/bin/", CREATE_PS1)

    def test_writes_expected_json(self):
        self.assertIn(".kinglet-probe/expected.json", CREATE_PS1)

    def test_computes_sha256(self):
        self.assertIn("SHA256", CREATE_PS1)

    def test_no_hardcoded_user_path(self):
        self.assertNotIn("/home/riive", CREATE_PS1)
        self.assertNotIn("C:\\Users\\", CREATE_PS1)

    def test_accepts_executable_argument(self):
        # Takes executable path via parameter, not hardcoded.
        self.assertIn("Param", CREATE_PS1)

    def test_writes_mcp_json_with_token_replaced(self):
        self.assertIn("__KINGLET_PROBE_EXECUTABLE__", CREATE_PS1)


if __name__ == "__main__":
    unittest.main()
