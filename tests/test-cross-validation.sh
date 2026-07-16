#!/usr/bin/env bash
# ============================================================================
# test-cross-validation.sh — Cross-validates settings.json against hook files
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
assert_eq() { TESTS_RUN=$((TESTS_RUN+1)); if [ "$1" = "$2" ]; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"; else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (expected '$2', got '$1')"; fi; }

echo ""
echo "=== Cross-Validation Tests ==="
echo ""

# ── Test 1: Every hook in settings.json exists on disk ────────────────────
echo "--- Test: settings.json hook references exist ---"
MISSING=0
for hook_path in $(jq -r '.. | .command? // empty' "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null | sort -u); do
    if [ ! -f "$PROJECT_ROOT/$hook_path" ]; then
        echo "  MISSING: $hook_path"
        MISSING=$((MISSING + 1))
    fi
done
assert_eq "$MISSING" "0" "all hook paths in settings.json exist on disk"

# ── Test 2: Every .sh in hooks/ (except _lib.sh) is in settings.json ─────
echo ""
echo "--- Test: hook files are referenced in settings.json ---"
UNREFERENCED=0
SETTINGS_CONTENT=$(cat "$PROJECT_ROOT/.claude/settings.json")
for hook_file in "$PROJECT_ROOT/.claude/hooks/"*.sh; do
    basename=$(basename "$hook_file")
    if [ "$basename" = "_lib.sh" ]; then continue; fi
    if ! echo "$SETTINGS_CONTENT" | grep -q "$basename"; then
        echo "  UNREFERENCED: $basename"
        UNREFERENCED=$((UNREFERENCED + 1))
    fi
done
assert_eq "$UNREFERENCED" "0" "all hook scripts are referenced in settings.json"

# ── Test 3: All hook scripts are executable ───────────────────────────────
echo ""
echo "--- Test: hook scripts are executable ---"
NON_EXEC=0
for hook_file in "$PROJECT_ROOT/.claude/hooks/"*.sh; do
    if [ ! -x "$hook_file" ]; then
        echo "  NOT EXECUTABLE: $(basename "$hook_file")"
        NON_EXEC=$((NON_EXEC + 1))
    fi
done
assert_eq "$NON_EXEC" "0" "all hook scripts are executable"

# ── Test 4: Agent frontmatter has required fields ─────────────────────────
echo ""
echo "--- Test: agent frontmatter completeness ---"
AGENT_FAIL=0
for file in "$PROJECT_ROOT/.claude/agents/"*.md; do
    YAML=$(sed -n '2,/^---$/p' "$file" | sed '$d')
    for field in "name:" "description:" "model:" "tools:"; do
        if ! echo "$YAML" | grep -q "$field"; then
            echo "  MISSING: $(basename "$file") lacks $field"
            AGENT_FAIL=$((AGENT_FAIL + 1))
        fi
    done
done
assert_eq "$AGENT_FAIL" "0" "all agents have required frontmatter fields"

# ── Test 5: Haiku agents are read-only ────────────────────────────────────
echo ""
echo "--- Test: haiku agents are read-only ---"
HAIKU_FAIL=0
for file in "$PROJECT_ROOT/.claude/agents/"*.md; do
    YAML=$(sed -n '2,/^---$/p' "$file" | sed '$d')
    MODEL=$(echo "$YAML" | grep "^model:" | awk '{print $2}')
    if [ "$MODEL" = "haiku" ]; then
        TOOLS=$(echo "$YAML" | grep "^tools:" | sed 's/^tools: *//')
        for forbidden in "Write" "Edit" "Bash"; do
            if echo "$TOOLS" | grep -qw "$forbidden"; then
                echo "  VIOLATION: $(basename "$file") (haiku) has $forbidden tool"
                HAIKU_FAIL=$((HAIKU_FAIL + 1))
            fi
        done
    fi
done
assert_eq "$HAIKU_FAIL" "0" "haiku agents have no write/edit/bash tools"

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo "=== Cross-Validation: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed ==="
echo ""

exit "$TESTS_FAILED"
