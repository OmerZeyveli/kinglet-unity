#!/usr/bin/env bash
# ============================================================================
# run-tests.sh — Test runner for everything-claude-unity
# Runs all test-*.sh files in this directory and reports results.
# No external dependencies — plain bash with built-in assertion helpers.
#
# Usage: bash tests/run-tests.sh [--verbose]
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
VERBOSE="${1:-}"

# test-state.sh sources this file as `run-tests.sh --source-only` to borrow the assertion helpers.
# That flag was never implemented — $1 was read as VERBOSE and the runner ran the whole suite again,
# from inside the test it had just started. Infinite mutual recursion.
#
# It went unnoticed because of the sourcing bug below: the runner died in the first test file, so it
# never reached test-state.sh to trigger this. Fixing that one exposed this one.
SOURCE_ONLY=0
if [ "$VERBOSE" = "--source-only" ]; then SOURCE_ONLY=1; VERBOSE=""; fi

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Counters ---
PASS=0
FAIL=0
SKIP=0
CURRENT_TEST_FILE=""

# --- Assertion Helpers ---

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="${3:-assert_eq}"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC} $message"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC} $message"
        echo -e "       expected: ${CYAN}${expected}${NC}"
        echo -e "       actual:   ${CYAN}${actual}${NC}"
    fi
}

assert_exit_code() {
    local expected_code="$1"
    shift
    local message="${*: -1}"
    local cmd_args=("${@:1:$#-1}")

    local actual_code=0
    "${cmd_args[@]}" > /dev/null 2>&1 || actual_code=$?

    if [ "$expected_code" -eq "$actual_code" ]; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC} $message (exit $actual_code)"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC} $message"
        echo -e "       expected exit: ${CYAN}${expected_code}${NC}"
        echo -e "       actual exit:   ${CYAN}${actual_code}${NC}"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-assert_contains}"
    if echo "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC} $message"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC} $message"
        echo -e "       needle:   ${CYAN}${needle}${NC}"
        echo -e "       not found in output"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-assert_not_contains}"
    if ! echo "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC} $message"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC} $message"
        echo -e "       needle:   ${CYAN}${needle}${NC}"
        echo -e "       was unexpectedly found in output"
    fi
}

assert_file_exists() {
    local path="$1"
    local message="${2:-file exists: $path}"
    if [ -e "$path" ]; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC} $message"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC} $message"
        echo -e "       path does not exist: ${CYAN}${path}${NC}"
    fi
}

assert_file_executable() {
    local path="$1"
    local message="${2:-file executable: $path}"
    if [ -x "$path" ]; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC} $message"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC} $message"
        echo -e "       not executable: ${CYAN}${path}${NC}"
    fi
}

skip_test() {
    local message="$1"
    SKIP=$((SKIP + 1))
    echo -e "  ${YELLOW}SKIP${NC} $message"
}

# --- Export helpers for sourced test files ---
export -f assert_eq assert_exit_code assert_contains assert_not_contains assert_file_exists assert_file_executable skip_test
export REPO_DIR VERBOSE

# Helpers are defined; that is all a --source-only caller wants. Returning here is what stops the
# mutual recursion described above.
if [ "$SOURCE_ONLY" -eq 1 ]; then
    return 0 2>/dev/null || exit 0
fi

# --- Runner ---

echo ""
echo -e "${CYAN}cloud-nine-unity test suite${NC}"
echo "========================================"
echo ""

test_files=("$SCRIPT_DIR"/test-*.sh)
if [ ${#test_files[@]} -eq 0 ]; then
    echo "No test files found."
    exit 0
fi

for test_file in "${test_files[@]}"; do
    if [ ! -f "$test_file" ]; then
        continue
    fi
    CURRENT_TEST_FILE="$(basename "$test_file")"
    echo -e "${CYAN}--- ${CURRENT_TEST_FILE} ---${NC}"

    # Each file runs in a SUBSHELL, not sourced into this one.
    #
    # This used to be a bare `source "$test_file"`. Several test files end with `exit 0` — and in a
    # sourced file, exit terminates the PARENT. So the runner died inside whichever file came first
    # alphabetically (test-cross-validation.sh) and 7 of the 8 files never ran, while the suite
    # printed "5 passed, 0 failed" and exited 0. It looked green because it had barely started.
    # test-install.sh was among the files that never ran, which is how a CLAUDE.md-destroying bug
    # shipped.
    #
    # Files carry their own PASS:/FAIL: output and some define their own counters, so results are
    # aggregated from the output rather than shared variables — a subshell cannot write ours back.
    # </dev/null: hooks read their JSON payload from stdin, so a test that runs one without
    # redirecting would sit there forever. A test suite must never be able to block.
    set +e
    # shellcheck source=/dev/null
    test_output=$( ( source "$test_file" ) 2>&1 </dev/null )
    test_rc=$?
    set -e
    echo "$test_output"

    # Strip ANSI first. The helpers print "${GREEN}PASS${NC}", so the character before PASS is the
    # 'm' ending the escape sequence, not whitespace — matching on raw output silently undercounts
    # every colourised result while still looking like it worked.
    test_plain=$(echo "$test_output" | sed 's/\x1b\[[0-9;]*m//g')
    file_pass=$(echo "$test_plain" | grep -cE '(^|[[:space:]])PASS(:|[[:space:]])' || true)
    file_fail=$(echo "$test_plain" | grep -cE '(^|[[:space:]])FAIL(:|[[:space:]])' || true)
    file_skip=$(echo "$test_plain" | grep -cE '(^|[[:space:]])SKIP(:|[[:space:]])' || true)
    PASS=$((PASS + file_pass))
    FAIL=$((FAIL + file_fail))
    SKIP=$((SKIP + file_skip))

    # A file that dies without reporting a failure would otherwise vanish from the tally.
    if [ "$test_rc" -ne 0 ] && [ "$file_fail" -eq 0 ]; then
        echo -e "  ${RED}FAIL${NC} ${CURRENT_TEST_FILE} exited ${test_rc} without reporting a failure"
        FAIL=$((FAIL + 1))
    fi
    echo ""
done

# --- Summary ---
TOTAL=$((PASS + FAIL + SKIP))
echo "========================================"
echo -e "Total: ${TOTAL}  ${GREEN}Passed: ${PASS}${NC}  ${RED}Failed: ${FAIL}${NC}  ${YELLOW}Skipped: ${SKIP}${NC}"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

exit 0
