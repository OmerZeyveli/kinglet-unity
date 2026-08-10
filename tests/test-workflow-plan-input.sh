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
# way. Reaching for the runner's `assert_contains` or `$REPO_DIR` in here
# breaks it in both directions, measured rather than reasoned — a scratch copy
# of this file with one borrowed `assert_contains` deliberately failing:
#
#   $ bash mixed.sh                      # standalone
#   PASS: own helper still works
#   mixed.sh: line 9: assert_contains: command not found
#   rc=127                               # errexit kills it; the tail never runs
#
#   $ source tests/run-tests.sh --source-only
#   $ set +e; out=$( ( source mixed.sh ) 2>&1 </dev/null ); rc=$?
#   PASS: own helper still works
#   FAIL borrowed helper, deliberately failing
#   reached the tail: TESTS_FAILED=0
#   rc=0                                 # this file's own summary says green
#
# The borrowed helper increments PASS/FAIL rather than the counters below —
# subshell copies of the runner's, which the runner discards when the subshell
# exits, so the increment reaches nothing at all. The file's own
# `[ "$TESTS_FAILED" -eq 0 ]` therefore exits 0 while an assertion has failed,
# and only the runner's grep for FAIL tokens in the captured output catches it.
# `$REPO_DIR` fails the other way: unset under this file's own `set -u` it is
# fatal on expansion —
#
#   $ bash -c 'set -euo pipefail; body="$(cat "$REPO_DIR/x" 2>/dev/null || true)"; echo reached'
#   bash: line 1: REPO_DIR: unbound variable
#   rc=1
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLANNING="$PROJECT_ROOT/.claude/skills/unity-planning/SKILL.md"
SDI="$PROJECT_ROOT/.claude/skills/subagent-driven-implementation/SKILL.md"
UE="$PROJECT_ROOT/.claude/skills/unity-execution/SKILL.md"

TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
assert_has() {
    TESTS_RUN=$((TESTS_RUN+1))
    if grep -qF -- "$2" <<< "$1"; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"
    else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (missing '$2')"; fi
}
# grep -F treats a multi-line pattern as ALTERNATIVES, not as one block, so
# assert_has on a three-line string passes when any single line survives. The
# handoff is fixed text and D8 asks a guard to test the same string the template
# writes, so it is compared whole, character for character.
assert_same() {
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$1" = "$2" ]; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"
    else
        TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3"
        echo "  expected: |$1|"
        echo "  actual:   |$2|"
    fi
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

# `description:` is the entire selection mechanism, so the plan-path input has to be
# declared THERE or the skill is not selected for it. Handed a bare plan path,
# subagent-driven-implementation's own description ("a written plan needs to be executed")
# is the better textual match, and the skill whose first section is "Adopt an existing
# plan first" never gets the job. A written spec is not an already-written plan; this
# assertion is about the latter.
assert_has "$FRONT" "plan path" "description declares a plan path as a first-class input"

# The five adoption assertions are anchored to the section that must contain them.
# Unanchored against the whole file, "docs/features/" is satisfied by the save location
# in section 4 and "verbatim" by the Global Constraints template — so the search order
# could be deleted outright with both still green.
ADOPT="$(awk '/^## 1\. Adopt an existing plan first/{f=1;next} f && /^## /{exit} f' "$PLANNING" 2>/dev/null || true)"
assert_has "$ADOPT" "docs/features/" "the search order names the features plan location"
assert_has "$ADOPT" "docs/superpowers/plans/" "the search order names the provider plan location"
assert_has "$ADOPT" "docs/design/" "the search order names the design-doc location"
assert_has "$ADOPT" "verbatim" "acceptance criteria are carried verbatim"
assert_has "$ADOPT" "Hard stop" "an unreadable named plan is a hard stop"

# The plan artifact carries its own handoff, so a fresh session given only the plan
# path is routed without reading any table. This is what closes the ledger-resume route.
#
# Compared whole rather than by token. `REQUIRED SUB-SKILL` alone is 17 characters of a
# 3-line block: measured on a scratch copy, replacing the rest of the line with "blah
# blah whatever" stayed green, and deleting the two lines that name the two branches
# stayed green. The skill tells the planner this text is fixed and guarded; that claim
# has to be true.
HANDOFF_EXPECTED='**For agentic workers:** REQUIRED SUB-SKILL — execute this plan task by task with
`subagent-driven-implementation` (recommended) or `unity-execution` (inline). Do not
implement directly from this file.'
HANDOFF_ACTUAL="$(awk '/^\*\*For agentic workers:\*\*/{f=1} f{print} f && /implement directly from this file\.$/{exit}' "$PLANNING" 2>/dev/null || true)"
assert_same "$HANDOFF_EXPECTED" "$HANDOFF_ACTUAL" \
    "the plan template's handoff is the fixed text, character for character"

# Both branches named by path, symmetrically. The inline branch was asserted by path from
# the start and the subagent branch only by bare name, so the whole fork block could lose
# its path reference to one of the two and stay green.
assert_has "$BODY" ".claude/skills/subagent-driven-implementation/SKILL.md" \
    "the fork names the subagent branch by path"
assert_has "$BODY" ".claude/skills/unity-execution/SKILL.md" \
    "the fork names the inline branch by path"

# The document header, which is what "include this line under the title" refers to.
assert_has "$BODY" "# [Feature Name] Implementation Plan" "the plan template has a title line"
assert_has "$BODY" "**Goal:**" "the plan template states a one-sentence goal"
assert_has "$BODY" "**Architecture:**" "the plan template states the approach"
assert_has "$BODY" "**Tech Stack:**" "the plan template states its dependencies"
assert_has "$BODY" "## Global Constraints" "the plan template carries the spec's project-wide values once"

# Two of the writing-plans rules that a rewrite would drop first.
assert_has "$BODY" '"Similar to Task N" — repeat the code' \
    "repeat-the-code survives, because a fresh implementer reads exactly one task"
assert_has "$BODY" "Type consistency" "the self-review checks names across tasks"

# The fork lives here, and it does not reopen a decision the ledger already records.
assert_has "$BODY" "If the ledger already records a mode, do not ask" \
    "a recorded execution mode is not reopened"

# ...and something must WRITE the mode, or "do not ask" reads a field nobody produces and
# asks every time. Both branches of the fork create the ledger line; assert all three ends
# of that contract, not just the reader.
assert_has "$BODY" "**Execution mode:**" "unity-planning tells the chosen branch to record the mode"

# The three Unity additions — the whole of this skill's cut-criterion defence, and the part
# with no upstream to restore it from. Each needle carries body rather than a heading: a
# rewrite that keeps three bold sentences and drops every reason would otherwise pass.
assert_has "$BODY" "is an operator step, and it is part of the task's deliverable" \
    "an asset an agent cannot create is a stated deliverable"
assert_has "$BODY" '.claude/rules/performance.md` already makes them mandatory' \
    "operator steps are sourced to the rule that already requires them"
assert_has "$BODY" "two agents driving it over MCP corrupt that shared" \
    "one implementer per Editor, with the asset-database reason intact"
assert_has "$BODY" "no csproj entry until Unity notices it" \
    "a new runtime .cs is created through Unity"

# Spec D8: design, plan and ledger are three files in one directory, so the loop that
# writes the third has to say where it goes — and write the mode into it.
SDI_BODY="$(cat "$SDI" 2>/dev/null || true)"
SDI_FRONT="$(awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f' "$SDI" 2>/dev/null || true)"
assert_has "$SDI_BODY" "docs/features/<slug>/ledger.md" "the ledger has an address beside the plan"
assert_has "$SDI_BODY" "**Execution mode:** subagent-driven" \
    "the subagent branch writes the mode a resuming controller reads"
assert_lacks "$SDI_FRONT" "/unity-workflow" \
    "the selection description does not route through a command"

UE_BODY="$(cat "$UE" 2>/dev/null || true)"
assert_has "$UE_BODY" "**Execution mode:** inline" \
    "the inline branch writes the mode too — it is the branch with no other ledger"

echo ""
echo "=== Workflow Plan-Input: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed ==="
[ "$TESTS_FAILED" -eq 0 ]
