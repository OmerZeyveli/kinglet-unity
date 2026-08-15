#!/usr/bin/env bash
# ============================================================================
# test-skill-discovery.sh — a skill Claude Code cannot see is not a skill.
#
# Until 2026-08-03 all 39 skills lived at .claude/skills/<category>/<name>/SKILL.md,
# inherited from everything-claude-unity. Claude Code discovers skills at
# .claude/skills/<name>/SKILL.md and nowhere else — one level, no categories.
# Measured, not assumed: two probe skills were installed in an empty project,
# one flat and one nested, and a headless session was asked to list its own
# available skills.
#
#   .claude/skills/flatprobe/SKILL.md            -> listed
#   .claude/skills/category/nestedprobe/SKILL.md -> not listed
#
# So for the toolkit's whole life, every skill it shipped was unreachable. An
# eight-hour Endless-Evolution session on 2026-08-02 invoked zero of them; that
# read as the model declining to use them, and it was not — there was nothing
# registered to decline.
#
# This test exists because the failure is silent in both directions. Nesting a
# skill produces no error, no warning, and no missing file — the tree looks
# tidier, the suite stays green, and the skill simply never loads again.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
assert_eq() {
  TESTS_RUN=$((TESTS_RUN+1))
  if [ "$1" = "$2" ]; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"
  else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (expected '$2', got '$1')"; fi
}

cd "$PROJECT_ROOT"

# --- 1. Every skill sits at the one depth Claude Code scans ----------------
# find -mindepth 3 relative to .claude/skills means <category>/<name>/SKILL.md
# or deeper. Anything it returns is invisible to the Skill tool.
TOO_DEEP=$(find .claude/skills -mindepth 3 -name SKILL.md 2>/dev/null || true)
if [ -n "$TOO_DEEP" ]; then
  echo "--- SKILL.md files Claude Code will not discover ---"
  echo "$TOO_DEEP"
  echo "--- move each to .claude/skills/<name>/SKILL.md ---"
fi
assert_eq "$(printf '%s' "$TOO_DEEP" | grep -c . || true)" "0" "no SKILL.md is nested below .claude/skills/<name>/"

# --- 2. Nothing else lives under .claude/skills/ ---------------------------
# A stray directory with no SKILL.md is either a half-finished skill or a
# category dir growing back. Both are worth seeing.
EMPTY_DIRS=""
for d in .claude/skills/*/; do
  [ -e "${d}SKILL.md" ] || EMPTY_DIRS="${EMPTY_DIRS}${d}
"
done
if [ -n "$EMPTY_DIRS" ]; then
  echo "--- directories under .claude/skills/ with no SKILL.md ---"; printf '%s' "$EMPTY_DIRS"
fi
assert_eq "$(printf '%s' "$EMPTY_DIRS" | grep -c . || true)" "0" "every directory under .claude/skills/ holds a SKILL.md"

# --- 3. name: matches the directory ---------------------------------------
# The directory is what the Skill tool is invoked by. A name: that disagrees
# with it makes every reference to the skill — in an agent, a command, a doc —
# point at something that does not answer.
MISMATCH=""
for d in .claude/skills/*/; do
  [ -e "${d}SKILL.md" ] || continue
  DIR_NAME="$(basename "$d")"
  FM_NAME="$(awk -F': *' '/^name:/{gsub(/"/,"",$2); print $2; exit}' "${d}SKILL.md")"
  [ "$DIR_NAME" = "$FM_NAME" ] || MISMATCH="${MISMATCH}${DIR_NAME} declares name: ${FM_NAME}
"
done
if [ -n "$MISMATCH" ]; then
  echo "--- skills whose name: disagrees with their directory ---"; printf '%s' "$MISMATCH"
fi
assert_eq "$(printf '%s' "$MISMATCH" | grep -c . || true)" "0" "every skill's name: matches its directory"

# --- 4. description: is present and non-empty ------------------------------
# Description is the entire selection mechanism. There is no glob matching and
# no always-apply (see test-no-mobile.sh section 5) — if the description does
# not say when to load the skill, nothing will ever load it.
NO_DESC=""
for d in .claude/skills/*/; do
  [ -e "${d}SKILL.md" ] || continue
  DESC="$(awk -F': *' '/^description:/{print substr($0, index($0,":")+2); exit}' "${d}SKILL.md")"
  [ -n "${DESC//[[:space:]\"]/}" ] || NO_DESC="${NO_DESC}$(basename "$d")
"
done
if [ -n "$NO_DESC" ]; then
  echo "--- skills with no description ---"; printf '%s' "$NO_DESC"
fi
assert_eq "$(printf '%s' "$NO_DESC" | grep -c . || true)" "0" "every skill has a non-empty description"

# --- 5. Skills named by agents and commands exist --------------------------
# Discovery is necessary, not sufficient: an agent still has to name the skill
# it should load. A reference to a skill that does not exist is worse than no
# reference — the agent reports having consulted guidance it never found.
#
# Matches a literal .claude/skills/<name> path in an agent or command. It is
# deliberately narrow: a prose sentence mentioning "the input-system skill" is
# not a reference this can verify.
#
# Placeholders are skipped. Commands that *write* skills document their output
# path as .claude/skills/[name]/ or .claude/skills/learned-<domain>-patterns/,
# which are templates, not references — a name carrying [ ] < > or a trailing
# hyphen is one of those. Without this the check fires on correct files, and a
# check that cries wolf gets deleted rather than fixed.
BAD_REFS=""
while IFS= read -r NAME; do
  [ -n "$NAME" ] || continue
  case "$NAME" in
    *[\[\]\<\>\*]* | *- ) continue ;;
  esac
  [ -d ".claude/skills/${NAME}" ] || BAD_REFS="${BAD_REFS}${NAME}
"
done <<< "$(
  grep -rhoE '\.claude/skills/[A-Za-z0-9<[][A-Za-z0-9<>_.-]*' .claude/agents .claude/commands 2>/dev/null \
    | sed 's|.*/||' | sort -u || true
)"
if [ -n "$BAD_REFS" ]; then
  echo "--- agent/command references to skills that do not exist ---"; printf '%s' "$BAD_REFS"
fi
assert_eq "$(printf '%s' "$BAD_REFS" | grep -c . || true)" "0" "every skill named by an agent or command exists"

# --- 6. Skills named by OTHER SKILLS exist ---------------------------------
# Section 5 covers agents and commands. Nothing covered skill -> skill until
# 2026-08-11, and that is the direction the process chain is built out of:
# unity-brainstorming names unity-planning, unity-planning names both branches
# of the fork, unity-execution names its predecessors and the standard it is
# measured against. Six citing skills, 13 references, 8 distinct targets, all by
# path — derived 2026-08-15. DO NOT TRUST THOSE THREE NUMBERS; they moved once
# already (they read "nine references, six distinct targets" and were a wave
# stale), and the floor below is what has to be re-sized when they move again:
#
#   grep -rhoE '\.claude/skills/[A-Za-z0-9<[][A-Za-z0-9<>_.-]*/[A-Za-z0-9<[][A-Za-z0-9<>_.-]*\.md' \
#     .claude/skills | sort -u | grep -vc '[][<>*]'
#
# Measured during the 2026-08-10 wave: three surfaces named each other by path
# BEFORE the targets existed, across three tasks, and nothing in the suite went
# red at any point. test-skill-discovery.sh scanned .claude/agents and
# .claude/commands only; test-surface-references.sh scans skill bodies only for
# /unity-* COMMAND tokens. Had the later tasks not landed, the toolkit would
# have shipped green with a user-facing chain whose next step resolved to
# nothing — the same silent-load failure this file exists for, in the one
# direction it did not look.
#
# The FILE is tested, not the directory: these references promise a document to
# read, and a directory that survives its SKILL.md is section 2's business.
#
# Same placeholder skip as section 5, and it matches the same character class
# deliberately — a pattern that could not match `.claude/skills/[name]/x.md` at
# all would make this `case` look like dead code to the next reader, who would
# delete it, at which point the guard starts crying wolf on a correct file.
S2S_REFS="$(
  grep -rhoE '\.claude/skills/[A-Za-z0-9<[][A-Za-z0-9<>_.-]*/[A-Za-z0-9<[][A-Za-z0-9<>_.-]*\.md' \
    .claude/skills 2>/dev/null | sort -u || true
)"
S2S_DANGLING=""
S2S_CHECKED=0
S2S_READ=""
while IFS= read -r REF; do
  [ -n "$REF" ] || continue
  case "$REF" in
    *[\[\]\<\>\*]* ) continue ;;
  esac
  # Incremented AFTER the skip, so the floor and the sentinels below describe
  # the set actually inspected. Counting before the skip is how a guard keeps
  # its numbers green while a `case` entry quietly removes a file from view.
  S2S_CHECKED=$((S2S_CHECKED + 1))
  S2S_READ="${S2S_READ}${REF}
"
  [ -f "$REF" ] || S2S_DANGLING="${S2S_DANGLING}${REF}
"
done <<< "$S2S_REFS"
if [ -n "$S2S_DANGLING" ]; then
  echo "--- skill references to files that do not exist ---"; printf '%s' "$S2S_DANGLING"
fi
assert_eq "$(printf '%s' "$S2S_DANGLING" | grep -c . || true)" "0" "every skill named by path inside another skill exists"

# Anti-vacuity, two mechanisms, because they fail differently — a floor cannot
# see a sweep that still returns files but no longer the right ones.
#
# The floor is a FLOOR, not a count: eight distinct targets exist today and
# seven is one below that on purpose. Two calibrations, and it has to clear both:
#
#   1. THE CHEAPEST NARROWING. Restricting the sweep to a single skill directory
#      yields at most FOUR distinct targets (unity-execution's, measured
#      2026-08-15; unity-planning 3, unity-brainstorming 2, the other three 1
#      each), so any such edit trips a floor anywhere above four.
#   2. ONE STEP OF SLACK, AND EXACTLY ONE. Losing one target leaves 7 and stays
#      green; losing two leaves 6 and reds. Dropping legitimately below seven
#      means the chain has been rewired, which is a deliberate change and should
#      have to say so here.
#
# IT WAS 5 UNTIL 2026-08-15 AND CALIBRATION 2 HAD SILENTLY FAILED. The floor was
# written against a subject of six; the 2026-08-14 wave added two path-form
# references (systematic-debugging -> unity-mcp-patterns, urp-pipeline ->
# systematic-debugging) and moved the subject to eight without touching the
# number. Measured by removing targets one at a time from a copy of the tree, in
# order of least load-bearing first:
#
#   targets   floor 5 (old)   floor 7 (now)
#      8        PASS            PASS
#      7        PASS            PASS
#      6        PASS            FAIL
#      5        PASS            FAIL
#      4        FAIL            FAIL
#
# So THREE targets could be removed green, in the guard docs/ANTI-VACUITY.md
# cites as its worked example of sizing a threshold against the cheapest
# plausible narrowing. Calibration 1 never broke — four is below both numbers —
# which is why nothing went red while the flagship example was inverted.
S2S_FLOOR_STATE="ok"
[ "$S2S_CHECKED" -ge 7 ] || S2S_FLOOR_STATE="only ${S2S_CHECKED} skill->skill references inspected"
assert_eq "$S2S_FLOOR_STATE" "ok" "the skill->skill sweep still reads the chain, rather than passing on an empty set"

# The sentinels are the chain itself: its entry point, the skill both of its
# neighbours name, and the two branches that skill forks between. If the sweep
# above stops seeing these, it has stopped seeing the thing it was written for.
#
# unity-brainstorming was NOT in this list until 2026-08-11 — the fork was
# guarded and the door into it was not. It is where a user arrives and where
# unity-planning sends a caller back to when no design exists, so a sweep that
# stopped reaching it would break the chain at its only entrance while the three
# sentinels below still reported "seen".
#
# These strings appear in this test file, and that is safe by construction
# rather than by luck: the sweep reads .claude/skills only, so a copy living in
# tests/ can never satisfy its own needle.
while IFS= read -r SENTINEL; do
  [ -n "$SENTINEL" ] || continue
  S2S_SEEN="missing"
  grep -qxF -- "$SENTINEL" <<< "$S2S_READ" && S2S_SEEN="seen"
  assert_eq "$S2S_SEEN" "seen" "the skill->skill sweep still reaches: $SENTINEL"
done <<'S2S_SENTINELS'
.claude/skills/unity-brainstorming/SKILL.md
.claude/skills/unity-planning/SKILL.md
.claude/skills/unity-execution/SKILL.md
.claude/skills/subagent-driven-implementation/SKILL.md
S2S_SENTINELS

# --- 7. The frontmatter is a well-formed BLOCK, not two lines ---------------
#
# Sections 3 and 4 read a `name:` line and a `description:` line. That is all they read, so until
# 2026-08-14 the CLOSING `---` fence was unguarded across every skill, and so was everything else
# inside the block. Measured on this tree, all three of these left the suite green:
#
#   * deleting the closing `---`          — the frontmatter never terminates, so the whole document
#                                            is frontmatter to a YAML parser;
#   * adding a third key (`alwaysApply: true`)
#                                          — CLAUDE.md says the frontmatter is `name` and
#                                            `description`, "nothing else"; test-no-mobile.sh catches
#                                            those two specific inert Cursor keys by name, at the
#                                            assertion reading "no skill carries alwaysApply or
#                                            globs", and nothing catches any OTHER third key;
#   * moving the opening `---` off line 1  — a document that begins with anything else has no
#                                            frontmatter at all, and `name:`/`description:` sitting
#                                            in the body still satisfied sections 3 and 4.
#
# So the block is parsed as a block: opens on line 1, closes on a later bare `---`, and between them
# every non-blank line is `name:` or `description:`, once each. That is CLAUDE.md's rule, asserted
# rather than requested.
#
# WHAT THIS CANNOT SEE. It is a line-shape check, not a YAML parser. A description whose VALUE is
# malformed YAML (an unbalanced quote, a stray `:` in an unquoted scalar) has the right key on the
# right line and passes here — the value's own validity is not asserted anywhere in this suite, and
# saying so is cheaper than implying otherwise. It also says nothing about whether the description
# is any GOOD, which is the entire selection mechanism and remains unguardable by a shell test.
FM_BAD=""
FM_CHECKED=0
for d in .claude/skills/*/; do
  [ -e "${d}SKILL.md" ] || continue
  FM_CHECKED=$((FM_CHECKED + 1))
  FM_VERDICT="$(awk '
    NR == 1 { if ($0 != "---") { print "does not open with --- on line 1 (line 1 is: " $0 ")"; exit } ; next }
    !closed && /^---[[:space:]]*$/ { closed = NR; next }
    !closed {
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 ~ /^name:/)        { n++; next }
      if ($0 ~ /^description:/) { desc++; next }
      other = other " " $0
    }
    END {
      if (NR == 0) { print "is empty"; exit }
      if (!closed) { print "has no closing --- fence, so the whole file reads as frontmatter"; exit }
      if (n != 1)    { print "has " n+0 " name: line(s) in its frontmatter, not exactly 1"; exit }
      if (desc != 1) { print "has " desc+0 " description: line(s) in its frontmatter, not exactly 1"; exit }
      if (other != "") { print "carries frontmatter beyond name and description:" other; exit }
    }
  ' "${d}SKILL.md")"
  [ -z "$FM_VERDICT" ] || FM_BAD="${FM_BAD}$(basename "$d") ${FM_VERDICT}
"
done
if [ -n "$FM_BAD" ]; then
  echo "--- skills whose frontmatter block is not name + description between two --- fences ---"
  printf '%s' "$FM_BAD"
fi
assert_eq "$(printf '%s' "$FM_BAD" | grep -c . || true)" "0" "every skill's frontmatter opens on line 1, closes on a --- fence, and carries exactly name: and description:"

# The same anti-vacuity the sections above lack: this loop reports zero problems over zero skills.
#
# TWO assertions, not one, and the second is here because the FIRST was measured insufficient while
# this block was being written. `FM_CHECKED = FM_DIRS` is satisfied by `0 = 0`: with
# `.claude/skills/` emptied, `ls -d` errors, `grep -c .` returns 0, the loop body never runs, and
# the equality passes — the exact "green because it scanned nothing" shape this whole change exists
# to remove, reintroduced inside the fix for it. A floor is what makes the equality mean something.
FM_DIRS=$(ls -d .claude/skills/*/ 2>/dev/null | grep -c . || true)
FM_FLOOR_STATE="ok"
[ "$FM_DIRS" -ge 1 ] || FM_FLOOR_STATE="no skill directories found under .claude/skills/ at all"
assert_eq "$FM_FLOOR_STATE" "ok" "there are skills to check — an empty .claude/skills/ must not read as a clean one"
assert_eq "$FM_CHECKED" "$FM_DIRS" "the frontmatter check read every skill directory ($FM_DIRS), rather than passing on a set that went empty"

# --- 8. The red-flag sections have BODIES ----------------------------------
#
# tests/test-surface-references.sh asserts that the three skills `using-kinglet` names each CARRY a
# `## The thought that means you are about to…` heading. That is existence-only, and for
# `systematic-debugging` and `verification-before-completion` it is their ONLY coverage in the whole
# suite: measured 2026-08-14, deleting every table row under both headings and leaving the headings
# in place left the suite entirely green. `using-kinglet` is injected at session start and tells the
# model to go and READ those sections; a heading over nothing satisfies the pointer and teaches
# nothing.
#
# Asserted as a FLOOR on three-column data rows, not as a count and not as fixed text. The rows are
# measured rationalizations and the set grows — a count would red on every honest addition, and
# pinning the text would red on a reword, which is the shape field note 81 rules against. Two is
# calibrated the way section 6's floor is: the smallest of the three sections carries two rows today,
# so any gutting to one or zero trips it while any legitimate edit does not.
#
# WHAT THIS CANNOT SEE. Row COUNT is not row VALUE: two rows of nonsense pass. It cannot tell a
# rewritten row from an original one, and it does not check that the Source column cites anything
# real — that is the claim the rows make and nothing in a shell test can settle it. It also reads
# only the three skills `using-kinglet` names; a fourth skill growing a red-flag section is outside
# it, deliberately, because the promise being kept is `using-kinglet`'s.
RF_BODY_BAD=""
RF_BODY_CHECKED=0
while IFS= read -r RF_NAME; do
  [ -n "$RF_NAME" ] || continue
  RF_FILE=".claude/skills/${RF_NAME}/SKILL.md"
  if [ ! -f "$RF_FILE" ]; then
    RF_BODY_BAD="${RF_BODY_BAD}${RF_NAME}: no SKILL.md
"
    continue
  fi
  RF_BODY_CHECKED=$((RF_BODY_CHECKED + 1))
  # A data row: a table line inside the section that is neither the header row nor the `|---|` rule.
  # `seen_head` skips the first table line, which is the column header.
  RF_ROWS=$(awk '
    /^## The thought that means you are about to/ { inrf = 1; next }
    inrf && /^#{1,3} /                            { exit }
    inrf && /^\|/ {
      if ($0 ~ /^\|[[:space:]-]*\|[[:space:]-]*\|[[:space:]-]*\|?[[:space:]]*$/) next
      if (!seen_head) { seen_head = 1; next }
      rows++
    }
    END { print rows + 0 }
  ' "$RF_FILE")
  [ "$RF_ROWS" -ge 2 ] || RF_BODY_BAD="${RF_BODY_BAD}${RF_NAME}: its red-flag section has ${RF_ROWS} data row(s), and using-kinglet sends every session there to read them
"
done <<'RF_BODY_SKILLS'
unity-brainstorming
systematic-debugging
verification-before-completion
RF_BODY_SKILLS
if [ -n "$RF_BODY_BAD" ]; then
  echo "--- red-flag sections that are a heading over nothing ---"; printf '%s' "$RF_BODY_BAD"
fi
assert_eq "$(printf '%s' "$RF_BODY_BAD" | grep -c . || true)" "0" "every red-flag section using-kinglet points at carries rows, not just a heading"
assert_eq "$RF_BODY_CHECKED" "3" "all three red-flag skills were opened and read, rather than the loop passing on a set that went empty"

# --- Summary ---------------------------------------------------------------
echo ""
echo "test-skill-discovery: $TESTS_PASSED/$TESTS_RUN passed"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
