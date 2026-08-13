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
# THE EXTRACTION IS PROVED BEFORE ITS SILENCE IS BELIEVED.
#
# This test's entire input is one `jq` invocation with `2>/dev/null`. When jq is absent, or the
# filter stops matching because settings.json changes shape, the substitution yields nothing, the
# loop iterates zero times, MISSING stays 0 and the assertion PASSES. Nothing in this repository
# guarded that: `/usr/bin/grep -rl 'command -v jq' tests/` returned 0 while eight test files call jq.
#
# Measured 2026-08-14, with a dangling registration ADDED to settings.json (an existing
# `session-brief.sh` command prefixed with `.claude/hooks/gateguard.sh; bash `, so the violation is
# isolated to this jq-fed sweep and removes nothing the grep-fed Test 2 would notice):
#
#   assertion                                        jq working   jq shimmed to exit 127
#   all hook paths in settings.json exist on disk     FAIL         PASS  ← vacuous
#   all hook scripts are referenced in settings.json  PASS         PASS
#   file total                                        4/1, rc=1    5/0, rc=0
#
# A HIGHER pass count and a clean exit, on a settings.json registering a hook that does not exist.
# The SHAPE of the violation matters and is worth recording: a REPLACEMENT (a live registration
# swapped for a dead one) is visible from both directions, so Test 2 reds either way and the file
# measures 4/1 with jq broken as well. Only an ADDED dangling registration isolates this sweep — and
# that is the shape an upgrade across the surface cut actually produces.
#
# The floor is 8 against 12 registrations today — below any plausible hook removal, far enough above
# zero that a missing jq, a filter that stops matching, or a settings.json rewritten into a shape
# this filter cannot walk is caught rather than read as a clean bill of health.
HOOK_PATHS=$(jq -r '.. | .command? // empty' "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null | sort -u || true)
HOOK_PATHS_N=$(printf '%s' "$HOOK_PATHS" | grep -c . || true)
EXTRACTION="ok"
if ! command -v jq > /dev/null 2>&1; then
    EXTRACTION="jq is not installed, so the hook registrations were never read"
elif [ "$HOOK_PATHS_N" -lt 8 ]; then
    EXTRACTION="jq extracted $HOOK_PATHS_N command(s) from .claude/settings.json, fewer than it registers"
fi
assert_eq "$EXTRACTION" "ok" "the hook registrations were actually extracted — an empty extraction must not certify the same green as a clean settings.json"

MISSING=0
while IFS= read -r hook_path; do
    [ -n "$hook_path" ] || continue
    if [ ! -f "$PROJECT_ROOT/$hook_path" ]; then
        echo "  MISSING: $hook_path"
        MISSING=$((MISSING + 1))
    fi
done <<< "$HOOK_PATHS"
assert_eq "$MISSING" "0" "all hook paths in settings.json exist on disk"

# ── Test 2: Every .sh in hooks/ (except _lib.sh) is in settings.json ─────
echo ""
echo "--- Test: hook files are referenced in settings.json ---"
UNREFERENCED=0
SETTINGS_CONTENT=$(cat "$PROJECT_ROOT/.claude/settings.json")
for hook_file in "$PROJECT_ROOT/.claude/hooks/"*.sh; do
    basename=$(basename "$hook_file")
    if [ "$basename" = "_lib.sh" ]; then continue; fi
    # SETTINGS_CONTENT is the whole settings.json — big enough in principle to exceed
    # PIPE_BUF, so this must not go through a pipe (see tests/run-tests.sh assert_contains).
    if ! grep -q "$basename" <<< "$SETTINGS_CONTENT"; then
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
