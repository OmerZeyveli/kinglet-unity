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
# measured against. Nine references, six distinct targets, all by path.
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
# The floor is a FLOOR, not a count: six distinct targets exist today and five
# is below that on purpose. It is calibrated against the cheapest narrowing —
# restricting the sweep to a single skill directory yields at most four, so any
# such edit trips it. Dropping legitimately below five means the chain has been
# rewired, which is a deliberate change and should have to say so here.
S2S_FLOOR_STATE="ok"
[ "$S2S_CHECKED" -ge 5 ] || S2S_FLOOR_STATE="only ${S2S_CHECKED} skill->skill references inspected"
assert_eq "$S2S_FLOOR_STATE" "ok" "the skill->skill sweep still reads the chain, rather than passing on an empty set"

# The sentinels are the fork itself: the two branches unity-planning chooses
# between, and unity-planning, which both of its neighbours name. If the sweep
# above stops seeing these, it has stopped seeing the thing it was written for.
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
.claude/skills/unity-planning/SKILL.md
.claude/skills/unity-execution/SKILL.md
.claude/skills/subagent-driven-implementation/SKILL.md
S2S_SENTINELS

# --- Summary ---------------------------------------------------------------
echo ""
echo "test-skill-discovery: $TESTS_PASSED/$TESTS_RUN passed"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
