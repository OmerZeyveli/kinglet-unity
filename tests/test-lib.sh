#!/usr/bin/env bash
# ============================================================================
# test-lib.sh — Tests for .claude/hooks/_lib.sh
# Tests profile gating, kill switches, shared utilities, and state paths.
#
# _lib.sh uses BASH_SOURCE[1] to detect the calling hook's filename,
# so we must create real temporary hook scripts (not bash -c) to test it.
# ============================================================================

HOOKS_DIR="${REPO_DIR}/.claude/hooks"
TEST_TMP="/tmp/unity-test-lib-$$"
mkdir -p "$TEST_TMP"

# --- Helper: create a minimal test hook and run it ---
# $1 = profile level, $2 = extra env vars (space-separated VAR=VAL), $3 = body after source
run_test_hook() {
    local profile="$1"
    local env_vars="$2"
    local body="${3:-echo reached}"

    local hook_file="${TEST_TMP}/test-hook-$$.sh"
    cat > "$hook_file" << HOOKEOF
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="${HOOKS_DIR}"
HOOK_PROFILE_LEVEL="${profile}"
source "\${SCRIPT_DIR}/_lib.sh"
${body}
HOOKEOF
    chmod +x "$hook_file"

    local exit_code=0
    local output=""
    if [ -n "$env_vars" ]; then
        output=$(env $env_vars bash "$hook_file" < /dev/null 2>&1) || exit_code=$?
    else
        output=$(bash "$hook_file" < /dev/null 2>&1) || exit_code=$?
    fi
    rm -f "$hook_file"
    echo "${exit_code}|${output}"
}

# --- Profile Gating Tests ---

# Strict hook skipped under minimal profile
RESULT=$(run_test_hook "strict" "UNITY_HOOK_PROFILE=minimal")
EXIT_CODE="${RESULT%%|*}"
OUTPUT="${RESULT#*|}"
assert_eq "0" "$EXIT_CODE" "strict hook skipped under minimal profile (exit 0)"
assert_not_contains "$OUTPUT" "reached" "strict hook does not reach body under minimal profile"

# Minimal hook runs under minimal profile
RESULT=$(run_test_hook "minimal" "UNITY_HOOK_PROFILE=minimal")
EXIT_CODE="${RESULT%%|*}"
OUTPUT="${RESULT#*|}"
assert_eq "0" "$EXIT_CODE" "minimal hook runs under minimal profile"
assert_contains "$OUTPUT" "reached" "minimal hook reaches body under minimal profile"

# Standard hook runs under strict profile
RESULT=$(run_test_hook "standard" "UNITY_HOOK_PROFILE=strict")
EXIT_CODE="${RESULT%%|*}"
OUTPUT="${RESULT#*|}"
assert_contains "$OUTPUT" "reached" "standard hook runs under strict profile"

# Standard hook runs under standard profile (same level)
RESULT=$(run_test_hook "standard" "UNITY_HOOK_PROFILE=standard")
EXIT_CODE="${RESULT%%|*}"
OUTPUT="${RESULT#*|}"
assert_contains "$OUTPUT" "reached" "standard hook runs under standard profile"

# Strict hook runs under strict profile
RESULT=$(run_test_hook "strict" "UNITY_HOOK_PROFILE=strict")
EXIT_CODE="${RESULT%%|*}"
OUTPUT="${RESULT#*|}"
assert_contains "$OUTPUT" "reached" "strict hook runs under strict profile"

# Unknown profile defaults to standard (level 2), so standard hooks run
RESULT=$(run_test_hook "standard" "UNITY_HOOK_PROFILE=unknown")
EXIT_CODE="${RESULT%%|*}"
OUTPUT="${RESULT#*|}"
assert_contains "$OUTPUT" "reached" "unknown profile defaults to standard"

# --- Kill Switch Tests ---

# Global kill switch
RESULT=$(run_test_hook "minimal" "DISABLE_UNITY_HOOKS=1")
EXIT_CODE="${RESULT%%|*}"
OUTPUT="${RESULT#*|}"
assert_eq "0" "$EXIT_CODE" "global kill switch exits 0"
assert_not_contains "$OUTPUT" "reached" "global kill switch prevents execution"

# --- State Directory Tests ---

assert_file_exists "/tmp/unity-claude-hooks" "state directory exists after sourcing _lib.sh"

# --- unity_hook_block Tests ---

# unity_hook_block exits 2 in normal mode
RESULT=$(run_test_hook "minimal" "" 'unity_hook_block "test block message"')
EXIT_CODE="${RESULT%%|*}"
OUTPUT="${RESULT#*|}"
assert_eq "2" "$EXIT_CODE" "unity_hook_block exits 2 in normal mode"
assert_contains "$OUTPUT" "BLOCKED" "unity_hook_block outputs BLOCKED"

# unity_hook_block exits 0 in warn mode
RESULT=$(run_test_hook "minimal" "UNITY_HOOK_MODE=warn" 'unity_hook_block "test warn message"')
EXIT_CODE="${RESULT%%|*}"
OUTPUT="${RESULT#*|}"
assert_eq "0" "$EXIT_CODE" "unity_hook_block exits 0 in warn mode"
assert_contains "$OUTPUT" "WARNING" "unity_hook_block warn mode outputs WARNING"

# --- Cleanup ---
rm -rf "$TEST_TMP"
