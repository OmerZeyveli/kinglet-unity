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

import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import tempfile
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
        # Parse frontmatter: text between first and second '---' delimiters.
        parts = SKILL_MD.split("---")
        # parts[0] is '', parts[1] is the frontmatter block, parts[2]+ is body
        frontmatter = parts[1] if len(parts) > 1 else ""
        desc_line = ""
        for line in frontmatter.splitlines():
            if line.strip().startswith("description:"):
                desc_line = line
                break
        self.assertNotEqual(desc_line, "", "description: line must be present in frontmatter")
        self.assertNotIn("SKILL.md", desc_line)


class SkillStepsTests(unittest.TestCase):
    def test_reads_project_version_file(self):
        self.assertIn("ProjectSettings/ProjectVersion.txt", SKILL_MD)

    def test_reads_project_marker_file(self):
        self.assertIn(".kinglet-probe/project-marker.txt", SKILL_MD)

    def test_calls_exec_subcommand(self):
        self.assertIn("kinglet-client-probe", SKILL_MD)
        # 'exec' as a subcommand: must appear as 'exec --project', not just as substring
        self.assertIn("exec --project", SKILL_MD)

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

    def test_hook_policy_states_overlay_exit_code_contract(self):
        # The policy must document that overlays are responsible for translating
        # the JSON 'decision' field into a non-zero exit (per cases-v1.json contract).
        self.assertIn("overlay_contract", HOOK_JSON_TEXT)
        contract = HOOK_JSON.get("overlay_contract", {})
        # Must mention that the binary exits 0 and overlays must handle deny translation
        exit_text = contract.get("exit_code", "")
        self.assertIn("exits 0", exit_text)
        self.assertIn("non-zero", exit_text)


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
        # The server's args must explicitly include the 'mcp' subcommand string.
        servers = MCP_JSON.get("mcpServers", {})
        self.assertTrue(len(servers) > 0, "mcpServers must be non-empty")
        for server_name, server_cfg in servers.items():
            args = server_cfg.get("args", [])
            self.assertIn("mcp", args, f"server {server_name!r} args must contain 'mcp' subcommand")


# ---------------------------------------------------------------------------
# create-project.sh tests
# ---------------------------------------------------------------------------

class CreateShTests(unittest.TestCase):
    def test_uses_strict_bash_mode(self):
        self.assertIn("set -euo pipefail", CREATE_SH)

    def test_rejects_non_darwin_linux(self):
        self.assertIn("Darwin", CREATE_SH)
        self.assertIn("Linux", CREATE_SH)
        # Verify exit 1 appears within the OS guard case block (not just anywhere).
        in_case = False
        has_exit_in_case = False
        for line in CREATE_SH.splitlines():
            stripped = line.strip()
            if stripped.startswith("case") and "host" in stripped:
                in_case = True
            if in_case and stripped == "esac":
                in_case = False
            if in_case and stripped == "exit 1":
                has_exit_in_case = True
        self.assertTrue(has_exit_in_case, "exit 1 must appear inside the OS-guard case block")

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
        # Must invoke sha256sum or shasum as a shell command, not just reference it
        # in a comment.  Assert that at least one invocation line (not a comment line)
        # contains the checksum command.
        found = False
        for line in CREATE_SH.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            if "sha256sum" in stripped or "shasum -a 256" in stripped:
                found = True
                break
        self.assertTrue(found,
                        "a non-comment line of create-project.sh must invoke "
                        "sha256sum or 'shasum -a 256'")

    def test_accepts_executable_argument_or_env(self):
        # Positive: the script must accept an explicit positional argument for the
        # executable and must fall back to the KINGLET_PROBE_EXECUTABLE env var.
        self.assertIn("KINGLET_PROBE_EXECUTABLE", CREATE_SH,
                      "script must reference KINGLET_PROBE_EXECUTABLE env var as fallback")
        # The positional arg branch must exist (second positional argument handling).
        self.assertIn('probe_exe="$1"', CREATE_SH,
                      "script must accept the executable path as a positional argument")

        # Negative: must not hardcode an absolute user home path.
        home = os.path.expanduser("~")
        self.assertNotIn(home, CREATE_SH)
        # Also check for any /home/<word>, /Users/<word>, or Windows C:\Users\<word> pattern.
        self.assertIsNone(
            re.search(r'(/home/\w|/Users/\w|[A-Z]:\\Users\\)', CREATE_SH),
            "create-project.sh must not contain any hardcoded user home path"
        )

    def test_no_declare_associative_array(self):
        self.assertNotIn("declare -A", CREATE_SH)

    def test_no_grep_oP(self):
        self.assertNotIn("grep -oP", CREATE_SH)

    def test_no_pipe_into_head(self):
        self.assertNotIn("| head", CREATE_SH)

    def test_validates_arg_before_shift(self):
        # Verify arg count check ($#) appears before any 'shift' in the script.
        lines = CREATE_SH.splitlines()
        check_line = None
        shift_line = None
        for i, line in enumerate(lines):
            stripped = line.strip()
            if check_line is None and "$#" in stripped:
                check_line = i
            if shift_line is None and stripped.startswith("shift") and "$#" not in stripped:
                shift_line = i
        self.assertIsNotNone(check_line, "$# check must appear in the script")
        self.assertIsNotNone(shift_line, "'shift' must appear in the script")
        self.assertLess(check_line, shift_line, "$# check must appear before first 'shift'")

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
        # Assert Copy-Item actually targets .kinglet-probe\bin\
        self.assertIn("Copy-Item", CREATE_PS1)
        self.assertIn(r".kinglet-probe\bin", CREATE_PS1)

    def test_writes_expected_json(self):
        self.assertIn(".kinglet-probe/expected.json", CREATE_PS1)

    def test_computes_sha256(self):
        self.assertIn("SHA256", CREATE_PS1)

    def test_no_hardcoded_user_path(self):
        home = os.path.expanduser("~")
        self.assertNotIn(home, CREATE_PS1)
        # Also check for any /home/<word>, /Users/<word>, or Windows C:\Users\<word> pattern.
        self.assertIsNone(
            re.search(r'(/home/\w|/Users/\w|[A-Z]:\\Users\\)', CREATE_PS1),
            "create-project.ps1 must not contain any hardcoded user home path"
        )

    def test_accepts_executable_argument(self):
        # Takes executable path via parameter, not hardcoded.
        self.assertIn("Param", CREATE_PS1)

    def test_writes_mcp_json_with_token_replaced(self):
        self.assertIn("__KINGLET_PROBE_EXECUTABLE__", CREATE_PS1)

    def test_no_bom_emitting_utf8_encoding(self):
        # [System.Text.Encoding]::UTF8 emits BOM (EF BB BF) because .NET's
        # Encoding.UTF8 has emitBOM: true. Must use UTF8Encoding($false) instead.
        self.assertNotIn("[System.Text.Encoding]::UTF8", CREATE_PS1)

    def test_json_escapes_backslash_in_mcp_path(self):
        # The substituted exe path is a JSON string value.  Windows paths always
        # contain '\', so without escaping the generated mcp.json is always invalid
        # JSON (F1 regression).  Assert that the script escapes backslash before
        # substitution.  We look for .Replace('\\', '\\\\') — the PowerShell
        # String.Replace call that doubles each backslash character.
        # Note: in this Python source, the four-backslash literal '\\\\' represents
        # the two-character sequence \\ that must appear in the ps1 file as \\\\
        # (four backslashes), which String.Replace interprets as "replace \ with \\".
        self.assertIn(r"Replace('\', '\\')", CREATE_PS1,
                      "create-project.ps1 must JSON-escape backslash in the exe path "
                      "before substituting into mcp.json")


# ---------------------------------------------------------------------------
# create-project.sh behavioral tests (POSIX only)
# ---------------------------------------------------------------------------

def _derive_probe_exe_path() -> str:
    """Return the dist/<goos>-<goarch>/kinglet-client-probe path for this host.

    Mirrors the logic in spikes/platform/clients/probe-host/build.sh, which uses
    ``go env GOHOSTOS`` / ``go env GOHOSTARCH``.  We replicate it in Python using
    ``platform.system()`` and ``platform.machine()`` so behavioural tests skip
    correctly on macOS as well as Linux when the binary has not been built.
    """
    sys_name = platform.system().lower()   # 'linux', 'darwin', 'windows'
    machine = platform.machine().lower()   # 'x86_64', 'aarch64', 'arm64', ...
    # Normalise machine → GOARCH
    if machine in ("x86_64", "amd64"):
        goarch = "amd64"
    elif machine in ("aarch64", "arm64"):
        goarch = "arm64"
    else:
        goarch = "amd64"
    # GOOS is platform.system().lower() for darwin and linux; go uses 'darwin' not 'macos'
    goos = sys_name  # 'linux' or 'darwin' on POSIX
    dist_dir = _SHARED.parent / "probe-host" / "dist" / f"{goos}-{goarch}"
    return str(dist_dir / "kinglet-client-probe")


_PROBE_EXE_PATH = _derive_probe_exe_path()


@unittest.skipUnless(sys.platform != "win32", "behavioral tests require POSIX")
class CreateShBehavioralTests(unittest.TestCase):
    _SCRIPT = str(_SHARED / "create-project.sh")
    _PROBE_EXE = _PROBE_EXE_PATH

    def test_no_args_exits_nonzero_with_stderr(self):
        """Running with no arguments must exit non-zero with the script's own usage error.

        This distinguishes the explicit argument guard from a 'set -u' unbound-variable
        crash: the script must emit its own 'missing required argument' message before
        any shift is attempted, so the failure is intentional, not accidental.
        """
        result = subprocess.run(
            ["bash", self._SCRIPT],
            capture_output=True, text=True
        )
        self.assertNotEqual(result.returncode, 0,
                            "script must exit non-zero when called with no arguments")
        # Must be the script's own error, not a bash 'unbound variable' crash.
        self.assertIn("missing required argument", result.stderr,
                      "stderr must contain the script's own usage/error message, "
                      "not an 'unbound variable' crash from set -u")

    def test_existing_destination_refused(self):
        """Running against an existing destination must exit non-zero."""
        with tempfile.TemporaryDirectory() as tmpdir:
            result = subprocess.run(
                ["bash", self._SCRIPT, tmpdir],
                capture_output=True, text=True
            )
            self.assertNotEqual(result.returncode, 0,
                                "script must refuse an already-existing destination")
            self.assertTrue(result.stderr.strip(),
                            "script must emit an error message on stderr when destination exists")

    @unittest.skipUnless(
        os.path.isfile(_PROBE_EXE_PATH),
        "probe binary not built — skip"
    )
    def test_successful_run_with_space_in_path(self):
        """Script must create exactly the declared file set; path with space must work."""
        probe_exe = self._PROBE_EXE
        with tempfile.TemporaryDirectory() as tmpdir:
            dest = os.path.join(tmpdir, "probe project with spaces")
            result = subprocess.run(
                ["bash", self._SCRIPT, dest, probe_exe],
                capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0,
                             f"script failed: stderr={result.stderr!r}")

            expected_rel = {
                "ProjectSettings/ProjectVersion.txt",
                "Assets/Protected.txt",
                ".kinglet-probe/project-marker.txt",
                ".kinglet-probe/bin/kinglet-client-probe",
                ".kinglet-probe/expected.json",
                ".kinglet-probe/mcp.json",
            }
            for rel in expected_rel:
                path = os.path.join(dest, rel)
                self.assertTrue(os.path.isfile(path), f"expected file not created: {rel}")

            # Assert the file set is *exclusive*: no extra files were created.
            # This guards against scripts accidentally copying credentials or profiles.
            actual_rel = set()
            for dirpath, _dirnames, filenames in os.walk(dest):
                for fname in filenames:
                    abs_path = os.path.join(dirpath, fname)
                    rel = os.path.relpath(abs_path, dest).replace(os.sep, "/")
                    actual_rel.add(rel)
            self.assertEqual(actual_rel, expected_rel,
                             f"unexpected files in project tree: {actual_rel - expected_rel!r}")

            # Verify sha256 in expected.json matches the copied binary
            with open(os.path.join(dest, ".kinglet-probe", "expected.json"), encoding="utf-8") as f:
                expected_data = json.load(f)
            recorded_sha = expected_data.get("sha256", "")

            bin_path = os.path.join(dest, ".kinglet-probe", "bin", "kinglet-client-probe")
            with open(bin_path, "rb") as f:
                actual_sha = hashlib.sha256(f.read()).hexdigest()

            self.assertEqual(recorded_sha, actual_sha,
                             "sha256 in expected.json must match actual copied binary")

    @unittest.skipUnless(
        os.path.isfile(_PROBE_EXE_PATH),
        "probe binary not built — skip"
    )
    def test_ampersand_in_destination_path(self):
        """Destination path containing '&' must not corrupt the mcp.json token substitution (M7 regression)."""
        probe_exe = self._PROBE_EXE
        with tempfile.TemporaryDirectory() as tmpdir:
            dest = os.path.join(tmpdir, "a&b")
            result = subprocess.run(
                ["bash", self._SCRIPT, dest, probe_exe],
                capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0,
                             f"script failed with & in path: stderr={result.stderr!r}")

            with open(os.path.join(dest, ".kinglet-probe", "mcp.json"), encoding="utf-8") as f:
                mcp_data = json.load(f)
            servers = mcp_data.get("mcpServers", {})
            for server_cfg in servers.values():
                cmd = server_cfg.get("command", "")
                self.assertNotIn("__KINGLET_PROBE_EXECUTABLE__", cmd,
                                 "token must be replaced in mcp.json command")
                self.assertIn("&", cmd,
                              "& in path must be preserved literally in mcp.json command")

    @unittest.skipUnless(
        os.path.isfile(_PROBE_EXE_PATH),
        "probe binary not built — skip"
    )
    def test_backslash_in_destination_path_produces_valid_json(self):
        """Destination path containing a backslash must produce valid JSON in mcp.json.

        On POSIX a literal backslash in a directory name is unusual but valid.
        The substituted executable path is derived from the destination, so a
        backslash in the destination propagates into the JSON string value.
        Without JSON-layer escaping (\ → \\) the generated mcp.json is invalid
        JSON (F1 regression).  The test verifies mcp.json parses and that the
        parsed command equals the real absolute path character-for-character.
        """
        probe_exe = self._PROBE_EXE
        with tempfile.TemporaryDirectory() as tmpdir:
            # Place the project inside a directory whose name contains a backslash.
            # The resulting abs_bin_path will be <tmpdir>/back\slash/proj/...
            bk_dir = os.path.join(tmpdir, r"back\slash")
            os.makedirs(bk_dir)
            dest = os.path.join(bk_dir, "proj")
            result = subprocess.run(
                ["bash", self._SCRIPT, dest, probe_exe],
                capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0,
                             f"script failed with backslash in destination path: "
                             f"stderr={result.stderr!r}")

            # mcp.json must be valid JSON — json.loads raises on invalid escape.
            mcp_path = os.path.join(dest, ".kinglet-probe", "mcp.json")
            with open(mcp_path, encoding="utf-8") as f:
                mcp_raw = f.read()
            try:
                mcp_data = json.loads(mcp_raw)
            except json.JSONDecodeError as exc:
                self.fail(f"mcp.json is not valid JSON: {exc}\ncontent: {mcp_raw!r}")

            # The parsed command value must equal the real absolute path character-for-character.
            expected_cmd = os.path.join(dest, ".kinglet-probe", "bin", "kinglet-client-probe")
            servers = mcp_data.get("mcpServers", {})
            for server_cfg in servers.values():
                cmd = server_cfg.get("command", "")
                self.assertEqual(cmd, expected_cmd,
                                 "parsed command in mcp.json must equal the real absolute path")


if __name__ == "__main__":
    unittest.main()
