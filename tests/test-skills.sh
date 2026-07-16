#!/usr/bin/env bash
# ============================================================================
# test-skills.sh — Validates skill frontmatter and content quality
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
assert_eq() { TESTS_RUN=$((TESTS_RUN+1)); if [ "$1" = "$2" ]; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"; else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (expected '$2', got '$1')"; fi; }

echo ""
echo "=== Skill Validation Tests ==="
echo ""

SKILL_COUNT=0
FRONTMATTER_FAIL=0
EXAMPLE_WARN=0
ANTI_WARN=0

for file in $(find "$PROJECT_ROOT/.claude/skills" -name "SKILL.md" 2>/dev/null); do
    SKILL_COUNT=$((SKILL_COUNT + 1))
    REL_PATH="${file#$PROJECT_ROOT/}"

    # Check frontmatter
    YAML=$(sed -n '2,/^---$/p' "$file" | sed '$d')
    if ! echo "$YAML" | grep -q "name:"; then
        echo "  FAIL: $REL_PATH missing name: in frontmatter"
        FRONTMATTER_FAIL=$((FRONTMATTER_FAIL + 1))
    fi
    if ! echo "$YAML" | grep -q "description:"; then
        echo "  FAIL: $REL_PATH missing description: in frontmatter"
        FRONTMATTER_FAIL=$((FRONTMATTER_FAIL + 1))
    fi

    # Check for code examples (advisory)
    EXAMPLE_COUNT=$(grep -c '```' "$file" 2>/dev/null || true)
    if [ "$EXAMPLE_COUNT" -lt 2 ]; then
        EXAMPLE_WARN=$((EXAMPLE_WARN + 1))
    fi

    # Check for anti-pattern guidance (advisory)
    ANTI_COUNT=$(grep -ciE '(common mistake|do not|avoid|never |bad |wrong )' "$file" 2>/dev/null || true)
    if [ "$ANTI_COUNT" -eq 0 ]; then
        ANTI_WARN=$((ANTI_WARN + 1))
    fi
done

echo "--- Test: skill frontmatter ---"
assert_eq "$FRONTMATTER_FAIL" "0" "all skills have required frontmatter (name, description)"

echo ""
echo "--- Info: skill quality ---"
echo "  Total skills: $SKILL_COUNT"
echo "  Skills with code examples: $((SKILL_COUNT - EXAMPLE_WARN))/$SKILL_COUNT"
echo "  Skills with anti-pattern guidance: $((SKILL_COUNT - ANTI_WARN))/$SKILL_COUNT"

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo "=== Skill Tests: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed ==="
echo ""

exit "$TESTS_FAILED"
