#!/usr/bin/env bash
# ============================================================================
# test-state.sh — Tests for structured state management (WS1)
# Tests state directory resolution, session.json schema, TTL, and helpers.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/run-tests.sh" --source-only 2>/dev/null || true

# Helpers from run-tests.sh should be available; if not, define minimal versions
if ! type assert_eq &>/dev/null 2>&1; then
    TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
    assert_eq() { TESTS_RUN=$((TESTS_RUN+1)); if [ "$1" = "$2" ]; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"; else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (expected '$2', got '$1')"; fi; }
    assert_contains() { TESTS_RUN=$((TESTS_RUN+1)); if echo "$1" | grep -qF "$2"; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"; else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (expected to contain '$2')"; fi; }
    assert_file_exists() { TESTS_RUN=$((TESTS_RUN+1)); if [ -f "$1" ]; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $2"; else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $2 (file not found: $1)"; fi; }
fi

LIB_PATH="${SCRIPT_DIR}/../.claude/hooks/_lib.sh"

echo ""
echo "=== State Management Tests ==="
echo ""

# ── Test 1: _lib.sh defines state dir variables ──────────────────────────
echo "--- Test: _lib.sh state directory variables ---"

# Source _lib.sh in a subshell with a hook context
OUTPUT=$(HOOK_PROFILE_LEVEL="minimal" BASH_SOURCE[1]="test-state.sh" bash -c '
    source "'"$LIB_PATH"'" 2>/dev/null
    echo "STATE_DIR=$UNITY_HOOK_STATE_DIR"
    echo "SESSION=$UNITY_SESSION_FILE"
    echo "READS=$UNITY_READS_FILE"
    echo "EDITS=$UNITY_EDITS_FILE"
    echo "COST=$UNITY_COST_FILE"
    echo "LEARN=$UNITY_LEARNING_FILE"
    echo "WARNINGS=$UNITY_WARNINGS_FILE"
    echo "NOTIFY=$UNITY_NOTIFY_EVENT_FILE"
' 2>/dev/null || echo "SOURCING_FAILED")

assert_contains "$OUTPUT" "SESSION=" "session file variable is defined"
assert_contains "$OUTPUT" "session.json" "session file uses new name (session.json)"
assert_contains "$OUTPUT" "WARNINGS=" "warnings file variable is defined"
assert_contains "$OUTPUT" "NOTIFY=" "notify event file variable is defined"
assert_contains "$OUTPUT" "learnings.jsonl" "learnings file in state dir"

# ── Test 2: State dir resolves to .claude/state/ in git repo ─────────────
echo ""
echo "--- Test: state dir resolves to .claude/state/ ---"

# Get the project root
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -d "$PROJECT_ROOT/.claude/state" ]; then
    # When run from within the project, it should resolve to .claude/state/
    RESOLVED_DIR=$(cd "$PROJECT_ROOT" && HOOK_PROFILE_LEVEL="minimal" BASH_SOURCE[1]="test-state.sh" bash -c '
        source ".claude/hooks/_lib.sh" 2>/dev/null
        echo "$UNITY_HOOK_STATE_DIR"
    ' 2>/dev/null)
    assert_contains "$RESOLVED_DIR" ".claude/state" "state dir resolves to .claude/state/ in project"
else
    echo "SKIP: .claude/state/ directory not found (not in project context)"
fi

# ── Test 3: State dir falls back to /tmp outside git repo ────────────────
echo ""
echo "--- Test: state dir fallback to /tmp ---"

FALLBACK_DIR=$(cd /tmp && HOOK_PROFILE_LEVEL="minimal" BASH_SOURCE[1]="test-state.sh" bash -c '
    source "'"$LIB_PATH"'" 2>/dev/null
    echo "$UNITY_HOOK_STATE_DIR"
' 2>/dev/null)

assert_contains "$FALLBACK_DIR" "/tmp" "state dir falls back to /tmp outside git repo"

# ── Test 4: session-save.sh produces valid JSON with schema_version ──────
echo ""
echo "--- Test: session-save produces valid schema ---"

SAVE_HOOK="${SCRIPT_DIR}/../.claude/hooks/session-save.sh"
if [ -f "$SAVE_HOOK" ]; then
    # Create a temp state dir and run session-save
    TEST_STATE_DIR=$(mktemp -d)
    mkdir -p "$TEST_STATE_DIR"
    echo "$(date +%s)" > "$TEST_STATE_DIR/session-start-time"

    # Run session-save with mock state dir
    (
        cd "$PROJECT_ROOT"
        export UNITY_HOOK_STATE_DIR="$TEST_STATE_DIR"
        export UNITY_SESSION_FILE="$TEST_STATE_DIR/session.json"
        export UNITY_EDITS_FILE="$TEST_STATE_DIR/session-edits.txt"
        export UNITY_COST_FILE="$TEST_STATE_DIR/session-cost.jsonl"
        export UNITY_WARNINGS_FILE="$TEST_STATE_DIR/session-warnings.txt"
        export UNITY_HOOK_PROFILE="standard"
        export DISABLE_UNITY_HOOKS=""
        bash "$SAVE_HOOK" 2>/dev/null
    )

    if [ -f "$TEST_STATE_DIR/session.json" ]; then
        # Validate JSON
        if jq . "$TEST_STATE_DIR/session.json" > /dev/null 2>&1; then
            assert_eq "1" "1" "session-save produces valid JSON"
        else
            assert_eq "0" "1" "session-save produces valid JSON"
        fi

        # Check schema_version
        SCHEMA_VER=$(jq -r '.schema_version' "$TEST_STATE_DIR/session.json" 2>/dev/null)
        assert_eq "$SCHEMA_VER" "1" "session.json has schema_version 1"

        # Check saved_at exists
        SAVED_AT=$(jq -r '.saved_at' "$TEST_STATE_DIR/session.json" 2>/dev/null)
        if [ -n "$SAVED_AT" ] && [ "$SAVED_AT" != "null" ]; then
            assert_eq "1" "1" "session.json has saved_at timestamp"
        else
            assert_eq "0" "1" "session.json has saved_at timestamp"
        fi

        # Check plan and verification fields exist
        HAS_PLAN=$(jq 'has("plan")' "$TEST_STATE_DIR/session.json" 2>/dev/null)
        assert_eq "$HAS_PLAN" "true" "session.json has plan field"

        HAS_VERIFY=$(jq 'has("verification")' "$TEST_STATE_DIR/session.json" 2>/dev/null)
        assert_eq "$HAS_VERIFY" "true" "session.json has verification field"

        HAS_AGENT=$(jq 'has("agent_context")' "$TEST_STATE_DIR/session.json" 2>/dev/null)
        assert_eq "$HAS_AGENT" "true" "session.json has agent_context field"
    else
        assert_eq "0" "1" "session-save creates session.json file"
    fi

    rm -rf "$TEST_STATE_DIR"
else
    echo "SKIP: session-save.sh not found"
fi

# ── Test 5: session-restore handles missing session file gracefully ──────
echo ""
echo "--- Test: session-restore handles missing file ---"

RESTORE_HOOK="${SCRIPT_DIR}/../.claude/hooks/session-restore.sh"
if [ -f "$RESTORE_HOOK" ]; then
    TEST_STATE_DIR=$(mktemp -d)
    (
        cd "$PROJECT_ROOT"
        export UNITY_HOOK_STATE_DIR="$TEST_STATE_DIR"
        export UNITY_SESSION_FILE="$TEST_STATE_DIR/session.json"
        export UNITY_READS_FILE="$TEST_STATE_DIR/gateguard-reads.txt"
        export UNITY_EDITS_FILE="$TEST_STATE_DIR/session-edits.txt"
        export UNITY_COST_FILE="$TEST_STATE_DIR/session-cost.jsonl"
        export UNITY_LEARNING_FILE="$TEST_STATE_DIR/learnings.jsonl"
        export UNITY_WARNINGS_FILE="$TEST_STATE_DIR/session-warnings.txt"
        export UNITY_HOOK_PROFILE="standard"
        export DISABLE_UNITY_HOOKS=""
        bash "$RESTORE_HOOK" 2>/dev/null
        echo "EXIT_CODE=$?"
    ) | grep -q "EXIT_CODE=0" && assert_eq "1" "1" "session-restore exits 0 with no session file" || assert_eq "0" "1" "session-restore exits 0 with no session file"

    rm -rf "$TEST_STATE_DIR"
else
    echo "SKIP: session-restore.sh not found"
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo "=== State Tests: ${TESTS_PASSED:-0} passed, ${TESTS_FAILED:-0} failed ==="
echo ""

exit "${TESTS_FAILED:-0}"
