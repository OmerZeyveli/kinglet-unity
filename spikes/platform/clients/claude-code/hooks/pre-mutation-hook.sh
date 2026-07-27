#!/usr/bin/env bash
# pre-mutation-hook.sh — PreToolUse deny-translation wrapper.
#
# Claude Code invokes this script before every Write or Edit tool call.
# It reads the tool-use JSON event from stdin, extracts the target file path,
# relativizes it against CLAUDE_PROJECT_DIR (Claude Code sets this for hooks),
# delegates the allow/deny decision to the native kinglet-client-probe binary,
# and translates a "deny" decision into exit 2 — Claude Code's block signal.
#
# The probe binary always exits 0 (even on deny). This wrapper is the
# overlay_contract translation layer required by hook-policy.json.
#
# Exit:
#   0 — allow the mutation (decision=="allow" or harness unavailable)
#   1 — harness error (binary missing/non-executable, or jq absent)
#   2 — block the mutation (decision=="deny")
#   3 — malformed stdin (JSON parse failure; non-blocking)
#
# Input (stdin): Claude Code PreToolUse JSON event
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
# Locate the native binary via CLAUDE_PLUGIN_ROOT
# ---------------------------------------------------------------------------
PROBE_BIN="${CLAUDE_PLUGIN_ROOT}/bin/kinglet-client-probe"

if [ ! -x "$PROBE_BIN" ]; then
    echo "pre-mutation-hook: binary not found or not executable: $PROBE_BIN" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Read the Claude Code tool-use event from stdin
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
# Relativize the path against CLAUDE_PROJECT_DIR (or event cwd fallback)
#
# Claude Code passes absolute paths in tool_input.file_path. The native probe
# binary compares against "Assets/Protected.txt" (relative). We must strip the
# project root prefix before forwarding to the binary.
#
# Relative paths are passed through unchanged — they are already in the form
# the probe binary expects. We only strip prefixes from absolute paths.
#
# If the path is absolute and outside the project root, allow without consulting
# the binary (we only protect files within this project).
# ---------------------------------------------------------------------------
proj=""
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    proj="${CLAUDE_PROJECT_DIR%/}"
elif CWD_FIELD="$(printf '%s' "$TOOL_EVENT" | jq -r '.cwd // empty')" && [ -n "$CWD_FIELD" ]; then
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
# Translate deny → exit 2 (Claude Code PreToolUse block signal)
# ---------------------------------------------------------------------------
if [ "$DECISION" = "deny" ]; then
    # Exit 2 IS the block signal; Claude Code feeds stderr back to the model as
    # the reason. Emit plain prose, not JSON: the structured
    # hookSpecificOutput/permissionDecision form belongs to the exit-0 stdout
    # protocol. Mixing the two was observed live to surface as
    # "PreToolUse:Edit hook error: {...raw json...}" — the block still worked,
    # but the reason read as a malfunction rather than a policy decision.
    printf 'Kinglet hook blocked write to %s: %s\n' "$FILE_PATH" "$REASON" >&2
    exit 2
fi

exit 0
