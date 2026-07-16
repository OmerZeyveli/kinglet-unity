#!/usr/bin/env bash
# ============================================================================
# session-save.sh — STOP HOOK
# Saves session state when the agent stops so subsequent conversations can
# resume context. Captures branch, modified files, workflow phase, and
# recent commits.
# ============================================================================
# Trigger: Stop
# Exit: 0 always (advisory)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

# Gather git state
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
RECENT_COMMITS=$(git log --oneline -3 2>/dev/null | jq -Rs 'split("\n") | map(select(length > 0))' || echo '[]')

# Gather modified files from session tracking
MODIFIED_FILES="[]"
if [ -f "$UNITY_EDITS_FILE" ]; then
    MODIFIED_FILES=$(sort -u "$UNITY_EDITS_FILE" | jq -Rs 'split("\n") | map(select(length > 0))')
fi

# Detect workflow phase from pre-compact state if available
WORKFLOW_PHASE=""
PRECOMPACT="${UNITY_HOOK_STATE_DIR}/precompact-state.md"
if [ -f "$PRECOMPACT" ]; then
    WORKFLOW_PHASE=$(grep -oE '(Clarify|Plan|Execute|Verify)' "$PRECOMPACT" 2>/dev/null | tail -1 || true)
fi

# Calculate session duration
SESSION_DURATION=""
if [ -f "${UNITY_HOOK_STATE_DIR}/session-start-time" ]; then
    START_TIME=$(cat "${UNITY_HOOK_STATE_DIR}/session-start-time")
    NOW=$(date +%s)
    DURATION=$((NOW - START_TIME))
    MINUTES=$((DURATION / 60))
    SECONDS=$((DURATION % 60))
    SESSION_DURATION="${MINUTES}m ${SECONDS}s"
fi

# Count tool calls from cost tracking
TOOL_CALLS=0
if [ -f "$UNITY_COST_FILE" ]; then
    TOOL_CALLS=$(wc -l < "$UNITY_COST_FILE" | tr -d ' ')
fi

# Gather verification state if available
VERIFICATION="{}"
if [ -f "${UNITY_HOOK_STATE_DIR}/verify-state.json" ]; then
    VERIFICATION=$(cat "${UNITY_HOOK_STATE_DIR}/verify-state.json" 2>/dev/null || echo '{}')
fi

# Gather plan state if available
PLAN="{}"
if [ -f "${UNITY_HOOK_STATE_DIR}/plan-state.json" ]; then
    PLAN=$(cat "${UNITY_HOOK_STATE_DIR}/plan-state.json" 2>/dev/null || echo '{}')
fi

# Gather agent context if available
AGENT_CONTEXT="{}"
if [ -f "${UNITY_HOOK_STATE_DIR}/agent-context.json" ]; then
    AGENT_CONTEXT=$(cat "${UNITY_HOOK_STATE_DIR}/agent-context.json" 2>/dev/null || echo '{}')
fi

# Gather warnings summary
WARNINGS_COUNT=0
if [ -f "$UNITY_WARNINGS_FILE" ]; then
    WARNINGS_COUNT=$(wc -l < "$UNITY_WARNINGS_FILE" | tr -d ' ')
fi

# Write session state with structured schema
jq -n \
    --argjson schema_version 1 \
    --arg branch "$CURRENT_BRANCH" \
    --arg phase "$WORKFLOW_PHASE" \
    --argjson modified "$MODIFIED_FILES" \
    --argjson commits "$RECENT_COMMITS" \
    --arg duration "$SESSION_DURATION" \
    --arg tool_calls "$TOOL_CALLS" \
    --arg warnings "$WARNINGS_COUNT" \
    --arg saved_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --argjson plan "$PLAN" \
    --argjson verification "$VERIFICATION" \
    --argjson agent_context "$AGENT_CONTEXT" \
    '{
        schema_version: $schema_version,
        branch: $branch,
        workflow_phase: $phase,
        modified_files: $modified,
        recent_commits: $commits,
        session_duration: $duration,
        tool_calls: ($tool_calls | tonumber),
        warnings_count: ($warnings | tonumber),
        saved_at: $saved_at,
        plan: $plan,
        verification: $verification,
        agent_context: $agent_context
    }' > "$UNITY_SESSION_FILE"

echo "" >&2
echo "Session state saved." >&2
if [ -n "$SESSION_DURATION" ]; then
    echo "  Duration: $SESSION_DURATION | Tool calls: $TOOL_CALLS | Files modified: $(echo "$MODIFIED_FILES" | jq 'length')" >&2
fi

exit 0
