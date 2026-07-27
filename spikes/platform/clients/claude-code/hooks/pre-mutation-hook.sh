#!/usr/bin/env bash
# pre-mutation-hook.sh — PreToolUse deny-translation wrapper.
#
# Claude Code invokes this script before every Write or Edit tool call.
# It reads the tool-use JSON event from stdin, extracts the target file path,
# delegates the allow/deny decision to the native kinglet-client-probe binary,
# and translates a "deny" decision into exit 2 — Claude Code's block signal.
#
# The probe binary always exits 0 (even on deny). This wrapper is the
# overlay_contract translation layer required by hook-policy.json.
#
# Exit:
#   0 — allow the mutation (decision=="allow")
#   2 — block the mutation (decision=="deny")
#
# Input (stdin): Claude Code PreToolUse JSON event
#   {"tool_name": "Write"|"Edit", "tool_input": {"file_path": "..."}, ...}
#
# Probe hook input (stdin to the binary):
#   {"path": "<file_path>"}
#
# Probe hook output (stdout from the binary):
#   {"decision": "allow"|"deny", "target": "...", "reason": "..."}

set -euo pipefail

# ---------------------------------------------------------------------------
# Locate the native binary via CLAUDE_PLUGIN_ROOT
# ---------------------------------------------------------------------------
PROBE_BIN="${CLAUDE_PLUGIN_ROOT}/bin/kinglet-client-probe"

if [ ! -x "$PROBE_BIN" ]; then
    echo "pre-mutation-hook: binary not found or not executable: $PROBE_BIN" >&2
    exit 0
fi

# ---------------------------------------------------------------------------
# Read the Claude Code tool-use event from stdin
# ---------------------------------------------------------------------------
TOOL_EVENT="$(cat)"

# ---------------------------------------------------------------------------
# Extract the target file path from tool_input.file_path
# ---------------------------------------------------------------------------
FILE_PATH="$(printf '%s' "$TOOL_EVENT" | jq -r '.tool_input.file_path // empty')"

if [ -z "$FILE_PATH" ]; then
    # No file_path in this event — allow and continue
    exit 0
fi

# ---------------------------------------------------------------------------
# Construct the probe hook event JSON and invoke the binary
# ---------------------------------------------------------------------------
PROBE_EVENT="$(printf '{"path":"%s"}' "$FILE_PATH")"

PROBE_OUTPUT="$(printf '%s' "$PROBE_EVENT" | "$PROBE_BIN" hook --event -)"

# ---------------------------------------------------------------------------
# Parse the decision field
# ---------------------------------------------------------------------------
DECISION="$(printf '%s' "$PROBE_OUTPUT" | jq -r '.decision // "allow"')"
REASON="$(printf '%s' "$PROBE_OUTPUT" | jq -r '.reason // ""')"

# ---------------------------------------------------------------------------
# Translate deny → exit 2 (Claude Code PreToolUse block signal)
# ---------------------------------------------------------------------------
if [ "$DECISION" = "deny" ]; then
    printf '{"hookSpecificOutput":{"permissionDecision":"deny"},"systemMessage":"Kinglet hook blocked write to %s: %s"}\n' \
        "$FILE_PATH" "$REASON" >&2
    exit 2
fi

exit 0
