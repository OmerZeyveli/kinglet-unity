#!/usr/bin/env bash
# ============================================================================
# test-templates.sh — Validates C# code templates
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
assert_eq() { TESTS_RUN=$((TESTS_RUN+1)); if [ "$1" = "$2" ]; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"; else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (expected '$2', got '$1')"; fi; }

echo ""
echo "=== Template Validation Tests ==="
echo ""

# ── Test 1: All templates have balanced braces ────────────────────────────
echo "--- Test: balanced braces ---"
BRACE_FAIL=0
for file in "$PROJECT_ROOT/templates/"*.cs.template; do
    OPEN=$(grep -o '{' "$file" | wc -l | tr -d ' ')
    CLOSE=$(grep -o '}' "$file" | wc -l | tr -d ' ')
    if [ "$OPEN" != "$CLOSE" ]; then
        echo "  UNBALANCED: $(basename "$file") (open: $OPEN, close: $CLOSE)"
        BRACE_FAIL=$((BRACE_FAIL + 1))
    fi
done
assert_eq "$BRACE_FAIL" "0" "all templates have balanced braces"

# ── Test 2: C# templates contain namespace or using ───────────────────────
echo ""
echo "--- Test: templates have C# structure ---"
STRUCT_FAIL=0
for file in "$PROJECT_ROOT/templates/"*.cs.template; do
    if ! grep -qE '(namespace|using )' "$file"; then
        echo "  MISSING STRUCTURE: $(basename "$file") (no namespace or using statement)"
        STRUCT_FAIL=$((STRUCT_FAIL + 1))
    fi
done
assert_eq "$STRUCT_FAIL" "0" "all C# templates have namespace or using statements"

# ── Test 3: Templates are non-empty ───────────────────────────────────────
echo ""
echo "--- Test: templates are non-empty ---"
EMPTY_FAIL=0
for file in "$PROJECT_ROOT/templates/"*.template; do
    SIZE=$(wc -c < "$file" | tr -d ' ')
    if [ "$SIZE" -lt 10 ]; then
        echo "  EMPTY: $(basename "$file") ($SIZE bytes)"
        EMPTY_FAIL=$((EMPTY_FAIL + 1))
    fi
done
assert_eq "$EMPTY_FAIL" "0" "all templates are non-empty"

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo "=== Template Tests: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed ==="
echo ""

exit "$TESTS_FAILED"
