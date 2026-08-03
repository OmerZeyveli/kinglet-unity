#!/usr/bin/env bash
# ============================================================================
# test-workflow-plan-input.sh — /unity-workflow must accept a written plan as
# input, not only a free-text feature description.
#
# This is frontmatter and prose, so what a bash test can prove is narrow: that
# the contract is stated, that the search order is written down, and that the
# verbatim rule is present. Whether the model actually adopts a plan handed to
# it is prompt behaviour and no assertion here claims to cover it.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WF="$PROJECT_ROOT/.claude/commands/unity-workflow.md"

TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
assert_has() {
    TESTS_RUN=$((TESTS_RUN+1))
    if grep -qF -- "$2" <<< "$1"; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"
    else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (missing '$2')"; fi
}

echo ""
echo "=== Workflow Plan-Input Tests ==="
echo ""

BODY="$(cat "$WF")"
# The first description:/args: inside the first --- block. Three command files
# carry a second description: in example output in the body; keying off the
# frontmatter fence is what keeps this honest.
FRONT="$(awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f' "$WF")"

assert_has "$FRONT" "args: feature-description-or-plan-path" "frontmatter accepts a plan path"
assert_has "$BODY" "docs/features/" "Phase 1 names the features plan location"
assert_has "$BODY" "docs/superpowers/plans/" "Phase 1 names the provider plan location"
assert_has "$BODY" "docs/design/" "Phase 1 names the design-doc location"
assert_has "$BODY" "verbatim" "acceptance criteria are carried verbatim"
assert_has "$BODY" "Hard stop" "an unreadable named plan is a hard stop"

echo ""
echo "=== Workflow Plan-Input: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed ==="
[ "$TESTS_FAILED" -eq 0 ]
