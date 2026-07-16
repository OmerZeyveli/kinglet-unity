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
        if [ "$VERBOSE" = "--verbose" ]; then
            echo -e "  ${GREEN}PASS${NC} $message"
        fi
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
        if [ "$VERBOSE" = "--verbose" ]; then
            echo -e "  ${GREEN}PASS${NC} $message (exit $actual_code)"
        fi
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
        if [ "$VERBOSE" = "--verbose" ]; then
            echo -e "  ${GREEN}PASS${NC} $message"
        fi
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
        if [ "$VERBOSE" = "--verbose" ]; then
            echo -e "  ${GREEN}PASS${NC} $message"
        fi
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
        if [ "$VERBOSE" = "--verbose" ]; then
            echo -e "  ${GREEN}PASS${NC} $message"
        fi
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
        if [ "$VERBOSE" = "--verbose" ]; then
            echo -e "  ${GREEN}PASS${NC} $message"
        fi
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

# --- Runner ---

echo ""
echo -e "${CYAN}everything-claude-unity test suite${NC}"
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
    source "$test_file"
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
