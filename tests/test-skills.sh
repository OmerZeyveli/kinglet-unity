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

while IFS= read -r file; do
    SKILL_COUNT=$((SKILL_COUNT + 1))
    REL_PATH="${file#"$PROJECT_ROOT"/}"

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
done < <(find "$PROJECT_ROOT/.claude/skills" -name "SKILL.md" 2>/dev/null)

echo "--- Test: skill frontmatter ---"
# ANTI-VACUITY FIRST, because without it the assertion below is green over nothing.
#
# The `find` above sends its errors to /dev/null. Rename `.claude/skills/`, move the payload, or run
# this file against a tree where that directory does not exist, and find prints nothing, SKILL_COUNT
# stays 0, FRONTMATTER_FAIL stays 0, `assert_eq 0 0` PASSES and the file exits 0. Measured
# 2026-08-14 against a copy of this repository with `.claude/skills/` emptied: `1 passed, 0 failed`,
# exit 0 — byte-identical in verdict to a healthy run, on a payload with no skills in it at all.
# This file's single assertion was the whole of its output, so that green covered its entire subject.
#
# A FLOOR, not an exact count: this file is a quality report over whatever skills exist, and pinning
# the number here would duplicate what tests/test-derived-counts.sh already derives and guards, in a
# second place that could disagree with it.
SKILLS_FLOOR="ok"
[ "$SKILL_COUNT" -ge 1 ] || SKILLS_FLOOR="find returned no SKILL.md under $PROJECT_ROOT/.claude/skills — the assertion below read nothing"
assert_eq "$SKILLS_FLOOR" "ok" "the skill walk found skills to check, rather than reporting a clean sweep of an empty set"
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
