#!/usr/bin/env bash
# ============================================================================
# test-workflow-plan-input.sh — plan adoption, and the fork the plan carries.
#
# The subject has not changed: a written plan handed over as a path must be
# adopted rather than re-interviewed, its acceptance criteria carried
# **verbatim**, and a named-but-unreadable path must stop the run. What moved
# is where that capability lives. It was `/unity-workflow` Phase 1a; it is now
# `.claude/skills/unity-planning/SKILL.md`, because plan-writing became a skill
# so the execution fork sits on every route into execution rather than only on
# the one route that ran a command. Every assertion below therefore points at
# the skill, with its substance unchanged.
#
# One assertion could not be retargeted literally. The command declared its
# plan-path input as `args: feature-description-or-plan-path`; a skill has no
# `args:` key at all, and its `description:` is the entire selection mechanism.
# So the frontmatter assertion now checks that the description names a written
# spec as a legitimate starting point — the same claim ("a plan already written
# is a first-class input, not only a free-text feature description") made at
# the surface a selector actually reads.
#
# This is frontmatter and prose, so what a bash test can prove is narrow: that
# the contract is stated, that the search order is written down, and that the
# verbatim rule is present. Whether the model actually adopts a plan handed to
# it is prompt behaviour and no assertion here claims to cover it.
#
# IDIOM — self-contained. This file defines its own assertion helpers and
# counters and sets its own `set -euo pipefail`, so `bash
# tests/test-workflow-plan-input.sh` is a valid way to run it. Keep it that
# way: reaching for the runner's `assert_contains` or `$REPO_DIR` in here
# would leave the file passing under the runner and dying on an unbound
# variable when run standalone.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLANNING="$PROJECT_ROOT/.claude/skills/unity-planning/SKILL.md"
SDI="$PROJECT_ROOT/.claude/skills/subagent-driven-implementation/SKILL.md"

TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
assert_has() {
    TESTS_RUN=$((TESTS_RUN+1))
    if grep -qF -- "$2" <<< "$1"; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"
    else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (missing '$2')"; fi
}
assert_lacks() {
    TESTS_RUN=$((TESTS_RUN+1))
    if grep -qF -- "$2" <<< "$1"; then TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (found '$2')"
    else TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"; fi
}
assert_exists() {
    TESTS_RUN=$((TESTS_RUN+1))
    if [ -f "$1" ]; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $2"
    else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $2 (no file at $1)"; fi
}

echo ""
echo "=== Workflow Plan-Input Tests ==="
echo ""

# A missing file must surface as one named failure, not as a bare `cat:` on
# stderr followed by every content assertion failing for a reason none of them
# states. `|| true` keeps the reads from aborting this file before the
# assertions below get to say what is actually wrong.
assert_exists "$PLANNING" "unity-planning exists — plan adoption has a home"

BODY="$(cat "$PLANNING" 2>/dev/null || true)"
# The first description: inside the first --- block. Several payload files
# carry a second description: in example output in the body; keying off the
# frontmatter fence is what keeps this honest.
FRONT="$(awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f' "$PLANNING" 2>/dev/null || true)"

assert_has "$FRONT" "written spec" "description names a written spec as a legitimate input"
assert_has "$BODY" "docs/features/" "the search order names the features plan location"
assert_has "$BODY" "docs/superpowers/plans/" "the search order names the provider plan location"
assert_has "$BODY" "docs/design/" "the search order names the design-doc location"
assert_has "$BODY" "verbatim" "acceptance criteria are carried verbatim"
assert_has "$BODY" "Hard stop" "an unreadable named plan is a hard stop"

# The plan artifact carries its own handoff, so a fresh session given only the plan
# path is routed without reading any table. This is what closes the ledger-resume route.
assert_has "$BODY" "REQUIRED SUB-SKILL" "the plan template carries the required-sub-skill line"
assert_has "$BODY" "subagent-driven-implementation" "the handoff names the subagent branch"
assert_has "$BODY" ".claude/skills/unity-execution/SKILL.md" "the handoff names the inline branch by path"

# The fork lives here, and it does not reopen a decision the ledger already records.
assert_has "$BODY" "If the ledger already records a mode, do not ask" \
    "a recorded execution mode is not reopened"

# Spec D8: design, plan and ledger are three files in one directory, so the loop that
# writes the third has to say where it goes.
SDI_BODY="$(cat "$SDI" 2>/dev/null || true)"
SDI_FRONT="$(awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f' "$SDI" 2>/dev/null || true)"
assert_has "$SDI_BODY" "docs/features/<slug>/ledger.md" "the ledger has an address beside the plan"
assert_lacks "$SDI_FRONT" "/unity-workflow" \
    "the selection description does not route through a command"

echo ""
echo "=== Workflow Plan-Input: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed ==="
[ "$TESTS_FAILED" -eq 0 ]
