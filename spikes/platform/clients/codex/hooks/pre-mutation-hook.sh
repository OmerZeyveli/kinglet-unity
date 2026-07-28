#!/usr/bin/env bash
# pre-mutation-hook.sh — PreToolUse deny-translation wrapper for Codex.
#
# Codex invokes this script before a matched tool call (matcher "Write|Edit"
# in the plugin-root hooks.json — auto-discovered; see the manifest note
# below). It reads the tool-use JSON event from stdin, extracts
# the target file path, delegates the allow/deny decision to the native
# kinglet-client-probe binary, and translates a "deny" decision into exit 2 —
# the block signal codex-cli 0.145.0 documents for PreToolUse hooks (verified
# in the binary's own diagnostic strings: "PreToolUse hook exited with code 2
# but did not write a blocking reason to stderr" — i.e. exit 2 blocks, and the
# reason must go to stderr, exactly like Claude Code's contract).
#
# The probe binary always exits 0 (even on deny). This wrapper is the
# overlay_contract translation layer required by hook-policy.json.
#
# ---------------------------------------------------------------------------
# Locating the probe binary — NO documented Codex plugin-root token
#
# Unlike Claude Code's ${CLAUDE_PLUGIN_ROOT}, codex-cli 0.145.0 does not
# expose a plugin-root environment variable to hook commands. This was
# checked directly against the tested build on the probe host:
#   - the plugin-creator skill's own plugin-json-spec.md documents relative
#     paths ("Path values should be relative and begin with ./") with no
#     substitution token;
#   - every real installed/cached plugin's hooks.json on the probe host
#     (figma, replayio) invokes its script as a bare relative path, e.g.
#     "./scripts/post_write_figma_parity_check.sh" — no token, no env var;
#   - the codex-cli binary itself contains no CODEX_PLUGIN_ROOT string (only
#     CLAUDE_PLUGIN_ROOT / CLAUDE_PLUGIN_DATA appear, inside an unrelated
#     managed-config schema for enterprise MDM interop with Claude Code).
#
# So this wrapper locates the probe binary relative to ITS OWN path
# (BASH_SOURCE) rather than trusting an env var that may not exist. This is
# strictly more portable than assuming a token, and matches how the packaged
# executable must be found regardless of what cwd Codex launches the hook
# command with. Step 4 (live pass) must still confirm this resolves inside
# the installed plugin cache, not the source checkout — see runbook.md.
#
# Exit:
#   0 — allow the mutation (decision=="allow" or harness unavailable)
#   1 — harness error (binary missing/non-executable, or jq absent)
#   2 — block the mutation (decision=="deny")
#   3 — malformed stdin (JSON parse failure; non-blocking)
#
# Input (stdin): Codex PreToolUse JSON event
#   {"tool_name": "Write"|"Edit", "tool_input": {"file_path": "..."}, ...}
#
# Probe hook input (stdin to the binary):
#   {"path": "<relative-file_path>"}
#
# Probe hook output (stdout from the binary):
#   {"decision": "allow"|"deny", "target": "...", "reason": "..."}

set -euo pipefail

# ---------------------------------------------------------------------------
# Dependency check — jq is required
# ---------------------------------------------------------------------------
if ! command -v jq > /dev/null 2>&1; then
    echo "pre-mutation-hook: jq not found — install jq and retry" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Locate the native binary relative to this script's own directory
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE_BIN="${SCRIPT_DIR}/../bin/kinglet-client-probe"

if [ ! -x "$PROBE_BIN" ]; then
    echo "pre-mutation-hook: binary not found or not executable: $PROBE_BIN" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Read the Codex tool-use event from stdin
# ---------------------------------------------------------------------------
TOOL_EVENT="$(cat)"

# ---------------------------------------------------------------------------
# Validate stdin is parseable JSON (guard against malformed events)
# ---------------------------------------------------------------------------
if ! printf '%s' "$TOOL_EVENT" | jq . > /dev/null 2>&1; then
    echo "pre-mutation-hook: malformed JSON on stdin — allowing by default" >&2
    exit 3
fi

# ---------------------------------------------------------------------------
# Extract the target file path from tool_input.file_path
# ---------------------------------------------------------------------------
FILE_PATH="$(printf '%s' "$TOOL_EVENT" | jq -r '.tool_input.file_path // empty')"

if [ -z "$FILE_PATH" ]; then
    # No file_path in this event — allow and continue
    exit 0
fi

# ---------------------------------------------------------------------------
# Relativize the path against the project root (or event cwd fallback)
#
# No CODEX_PROJECT_DIR-equivalent environment variable was found in the
# tested build (checked against the full CODEX_* string table in the
# codex-cli binary — see runbook.md). This wrapper therefore relies only on
# the event's own "cwd" field, matching what Codex's hook payload documents
# for tool-use events, so this must be treated as an open question for the
# live pass to confirm or refute.
#
# If the path is absolute and outside the known project root, allow without
# consulting the binary (we only protect files within this project).
# ---------------------------------------------------------------------------
proj=""
if CWD_FIELD="$(printf '%s' "$TOOL_EVENT" | jq -r '.cwd // empty')" && [ -n "$CWD_FIELD" ]; then
    proj="${CWD_FIELD%/}"
fi

case "$FILE_PATH" in
    /*)
        # Absolute path: strip project root prefix if known.
        if [ -n "$proj" ]; then
            case "$FILE_PATH" in
                "$proj"/*)
                    FILE_PATH="${FILE_PATH#"$proj"/}"
                    ;;
                *)
                    # Absolute path outside project root — allow.
                    exit 0
                    ;;
            esac
        fi
        ;;
    *)
        # Relative path: pass through unchanged to the probe.
        ;;
esac

# ---------------------------------------------------------------------------
# Construct the probe hook event JSON and invoke the binary
# jq -cn --arg p "$FILE_PATH" produces correctly escaped JSON for any path,
# including paths with backslashes or double-quote characters.
# ---------------------------------------------------------------------------
PROBE_EVENT="$(jq -cn --arg p "$FILE_PATH" '{path:$p}')"

PROBE_OUTPUT="$(printf '%s' "$PROBE_EVENT" | "$PROBE_BIN" hook --event -)"

# ---------------------------------------------------------------------------
# Parse the decision field
# ---------------------------------------------------------------------------
DECISION="$(printf '%s' "$PROBE_OUTPUT" | jq -r '.decision // "allow"')"
REASON="$(printf '%s' "$PROBE_OUTPUT" | jq -r '.reason // ""')"

# ---------------------------------------------------------------------------
# Translate deny → exit 2 (Codex PreToolUse block signal)
# ---------------------------------------------------------------------------
if [ "$DECISION" = "deny" ]; then
    # Exit 2 IS the block signal; codex-cli's own diagnostics say a PreToolUse
    # hook that exits 2 without writing a blocking reason to stderr is treated
    # as a malformed block, so the reason MUST go to stderr here.
    printf 'Kinglet hook blocked write to %s: %s\n' "$FILE_PATH" "$REASON" >&2
    exit 2
fi

exit 0
