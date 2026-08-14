#!/usr/bin/env bash
# ============================================================================
# test-no-mobile.sh — Kinglet Pioneer is PC/console only. Prove it.
#
# This toolkit vendors everything-claude-unity, which targeted mobile devs. The
# mobile content was removed rather than disabled. Without this test, the next
# upstream sync silently reinstates it — the strip is a one-time edit, but the
# constraint is permanent.
#
# The original rationale here — "the mobile skill shipped alwaysApply:true with
# globs ["**/*.cs"], so it loaded on every C# file" — is wrong, and the record
# should say so. Probes on 2026-07-30 and 2026-08-03 found nothing in Claude
# Code reads either key; both are Cursor rule conventions that arrived with the
# vendored frontmatter. The mobile skill was never auto-loading anything.
#
# Deleting it was still right, and this test still earns its keep: mobile
# guidance in a PC/console toolkit is wrong guidance whether it loads by itself
# or a model picks it off the shelf. Only the mechanism was misdescribed.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
assert_eq() { TESTS_RUN=$((TESTS_RUN+1)); if [ "$1" = "$2" ]; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"; else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (expected '$2', got '$1')"; fi; }
assert_absent() {
  TESTS_RUN=$((TESTS_RUN+1))
  if [ ! -e "$PROJECT_ROOT/$1" ]; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $2"
  else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $2 — $1 exists"; fi
}

cd "$PROJECT_ROOT"

# --- 1. Deleted mobile payload stays deleted -------------------------------
# Both layouts. Upstream keeps skills at skills/<category>/<name>/; we flattened to
# skills/<name>/ on 2026-08-03 because Claude Code only discovers the flat form. A
# re-vendor could reinstate mobile at either path, so both stay asserted absent.
assert_absent ".claude/skills/platform/mobile/SKILL.md" "mobile skill absent (upstream path)"
assert_absent ".claude/skills/mobile"                   "mobile skill absent (flat path)"
assert_absent ".claude/skills/platform"                 "platform/ category absent (mobile was its only entry)"
assert_absent ".claude/skills/genre/hyper-casual"       "hyper-casual genre absent (upstream path)"
assert_absent ".claude/skills/hyper-casual"             "hyper-casual genre absent (flat path)"
assert_absent ".claude/skills/genre/endless-runner"     "endless-runner genre absent (upstream path)"
assert_absent ".claude/skills/endless-runner"           "endless-runner genre absent (flat path)"
assert_absent "examples/CLAUDE.md.hyper-casual"         "hyper-casual example absent"
assert_absent "examples/CLAUDE.md.mobile-casual"        "mobile-casual example absent"

# --- 2. Counts hold --------------------------------------------------------
assert_eq "$(find examples -type f | wc -l | tr -d ' ')" "4" "4 examples (6 upstream - 2 mobile)"

# --- 3. No mobile-only guidance in the payload -----------------------------
# Terms that have no legitimate PC/console use. Bare "mobile" is NOT listed: a
# deliberate contrast ("the mobile habit of defaulting to half buys little
# here") is useful teaching, not a leak.
#
# Acronyms are matched case-SENSITIVELY with word boundaries. Case-insensitive
# 'ASTC' matches the "astC" inside castCount and _lastCheckpointPosition —
# exactly the blind-matching trap this file is meant to catch.
MOBILE_CS='\b(ASTC|TBDR)\b'
MOBILE_CI='hyper-casual|endless-runner|platform/mobile|tile-based GPU|thermal throttl|AdaptivePerformance|safe[ -]area|virtual joystick|tap-to-move|EnhancedTouch|Touchscreen'

# provenance-skip.tsv documents what we removed, so it names these terms by design.
ALLOWLIST='provenance-skip.tsv|tests/test-no-mobile.sh|MERGE-NOTES.md|docs/SKILL-CATALOG.md|.claude/rules/pc-console.md'

SCAN_DIRS=(.claude/ docs/ scripts/ examples/ templates/)

# --- 3a. The scan has something to scan, and the patterns still bind --------
#
# Sections 3, 4 and 5 are `grep -r … 2>/dev/null || true` over roots. Every one of them reports the
# same clean result when the roots are GONE as when they are clean: grep's error goes to /dev/null,
# the `|| true` swallows the exit status, HITS is empty, and `assert_eq 0 0` passes. Measured
# 2026-08-14 against a copy of this repository with `.claude/agents`, `.claude/commands`,
# `.claude/hooks`, `.claude/rules` and `.claude/skills` emptied: this file reported **13 passed, 0
# failed** — a full green over a payload that no longer existed. Section 1's `assert_absent` calls
# are what made that green plausible: on an empty tree they are all trivially true.
#
# Two mechanisms, because they fail differently. The roots check catches a tree that emptied or a
# path that was renamed; the canaries catch the other direction — roots still full of files, but a
# pattern that no longer matches anything, which no file count can see. The canary strings are the
# real removed terms, run through the real patterns.
#
# WHAT THE CANARIES CANNOT SEE, measured rather than assumed: each one exercises ONE alternative of
# an alternation. Breaking `hyper-casual` inside MOBILE_CI leaves all three canaries green, because
# the case-insensitive canary matches on `safe area`. They prove the pattern still binds at all —
# which is the no-op direction this block exists for — not that every alternative in it still binds.
# Covering all eleven would mean a canary per alternative and a list that has to be kept in step
# with the pattern by hand, which is the shape this file's own history argues against.
#
# PER SOURCE, NOT PER UNION — and that is the whole of what changed here on 2026-08-14.
#
# The roots check above USED TO BE `SCAN_FILES=$(find "${SCAN_DIRS[@]}" -type f | wc -l)` followed
# by `[ "$SCAN_FILES" -ge 1 ]`. One number over five roots. `docs/` alone holds 186 files, so that
# floor cleared with every one of `.claude/agents`, `.claude/commands`, `.claude/hooks`,
# `.claude/rules` and `.claude/skills` emptied — MEASURED 2026-08-14 in a clone with ZERO files
# under `.claude/`: **17 passed, 0 failed, rc 0**, byte-identical in verdict to a healthy tree.
# `assert_absent`'s nine calls in section 1 are all trivially true on an empty tree, which is what
# made that green look plausible. See docs/ANTI-VACUITY.md: a floor over a summed multi-source
# subject cannot detect one source dying, however tight the number — 1 or 60, the union floor sees
# `docs/` and stops.
#
# THE SOURCE SET IS DERIVED, NOT LISTED. Every scan root, plus every immediate subdirectory of
# `.claude/` — because `.claude/` is a container whose children die independently, and it is those
# children that hold the payload. A subdirectory added to `.claude/` becomes a source the day it
# lands, with nobody editing a list here. `.claude/state/` is IN the set deliberately: it is tracked
# through `.gitkeep`, so it is non-empty in every fresh clone, and if that file goes the directory
# disappears from every checkout — which is a change someone should have to make on purpose.
#
# `{ find …; } | wc -l`, with find's non-zero status swallowed INSIDE the braces. A missing root
# makes find exit 1, pipefail promotes it, and at a bare assignment site `set -e` ends the file —
# measured while writing the previous version of this block: with one root renamed, this file died
# here silently after section 1 and reported no failure of its own. The very check written to catch
# an absent root was killed by the absent root.
SCAN_SOURCES=$( { printf '%s\n' "${SCAN_DIRS[@]}"
                  find .claude -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true
                } | sed 's#/*$##' | sort -u )
SCAN_SOURCE_N=$(printf '%s\n' "$SCAN_SOURCES" | grep -c . || true)

SCAN_STATE="ok"
SCAN_CENSUS=""
SCAN_DEAD=""
SCAN_FILES=0
while IFS= read -r SCAN_D; do
  [ -n "$SCAN_D" ] || continue
  if [ ! -d "$SCAN_D" ]; then
    SCAN_STATE="scan source $SCAN_D does not exist, so every sweep below silently read nothing from it"
    continue
  fi
  SCAN_N=$( { find "$SCAN_D" -type f 2>/dev/null || true; } | wc -l | tr -d ' ')
  SCAN_CENSUS="${SCAN_CENSUS}${SCAN_D}=${SCAN_N} "
  SCAN_FILES=$((SCAN_FILES + SCAN_N))
  # ACCUMULATED, not overwritten. A sentinel that is reassigned reports only the LAST dead source,
  # and on a fully emptied payload that named `.claude/state` — the least interesting of the seven —
  # while the six that matter went unmentioned. The census beside it carries the numbers either way;
  # this carries the names.
  [ "$SCAN_N" -ge 1 ] || SCAN_DEAD="${SCAN_DEAD}${SCAN_D} "
done <<< "$SCAN_SOURCES"
[ -z "$SCAN_DEAD" ] || SCAN_STATE="scan source(s) holding no files at all: ${SCAN_DEAD}— every sweep below read nothing from them while the remaining sources kept this check green"

# THE FLOOR ON THE CENSUS ITSELF, one level up, and it is not decoration: if SCAN_SOURCES ever
# resolves to nothing the loop above runs zero times, SCAN_STATE stays "ok", and the per-source
# check reports a serene green over no sources at all — the same defect it was just written to
# close. `${#SCAN_DIRS[@]}` is a property of this file, not of the tree, so an emptied tree cannot
# move it: the census must carry at least one row per declared root. It moves with the array, so it
# cannot go stale either.
[ "$SCAN_SOURCE_N" -ge "${#SCAN_DIRS[@]}" ] || SCAN_STATE="the source derivation produced $SCAN_SOURCE_N source(s) for ${#SCAN_DIRS[@]} declared scan root(s) — the per-source check below has no sources to check"

# A FLOOR WHOSE REFERENCE THE MUTATION ALSO MOVES IS NOT A FLOOR — measured on the line above, on
# its first mutation run. `SCAN_DIRS=()` drives `${#SCAN_DIRS[@]}` to 0, so `-ge 0` is trivially
# true; SCAN_SOURCES still holds the six `.claude/` subdirectories the `find` contributes, so every
# per-source check passes; and sections 3, 4 and 5 then sweep NO ROOTS AT ALL. Result: **17 pass /
# 0 fail**, a full green over a sweep with nothing in its scope, from the block written to stop
# exactly that. The array is the scope of the real `grep -r` calls below, so it gets its own
# absolute floor rather than a relative one. docs/ANTI-VACUITY.md records this as rule F4.
[ "${#SCAN_DIRS[@]}" -ge 1 ] || SCAN_STATE="SCAN_DIRS is empty, so sections 3, 4 and 5 sweep no roots at all and every clean result below is worthless"
assert_eq "$SCAN_STATE" "ok" "every mobile-sweep source has files in it — $SCAN_CENSUS(total $SCAN_FILES) — an emptied payload must not read as a clean one"

# `ASTC 6x6`, not `ASTC_6x6`: `_` is a word character, so `\bASTC\b` does NOT match inside
# `ASTC_6x6` — measured while writing this canary, which is the canary earning its keep on its first
# run. The pattern is deliberately boundary-anchored (its own comment above says why), and a canary
# that used the underscored spelling would have asserted the pattern was broken when it was not.
CANARY_CS=$(printf 'texture format ASTC 6x6 for mobile\n' | grep -cE "$MOBILE_CS" || true)
assert_eq "$CANARY_CS" "1" "the case-sensitive acronym pattern still matches a real mobile-only term"
CANARY_CI=$(printf 'respect the safe area inset\n' | grep -ciE "$MOBILE_CI" || true)
assert_eq "$CANARY_CI" "1" "the case-insensitive mobile-term pattern still matches a real mobile-only term"
CANARY_NEG=$(printf 'the raycast hit castCount and _lastCheckpointPosition\n' | grep -cE "$MOBILE_CS" || true)
assert_eq "$CANARY_NEG" "0" "…and still does not fire on the substrings this file's own comment names as the blind-matching trap"

HITS=$( { grep -rnE "$MOBILE_CS" "${SCAN_DIRS[@]}" 2>/dev/null || true
          grep -rniE "$MOBILE_CI" "${SCAN_DIRS[@]}" 2>/dev/null || true
        } | grep -vE "$ALLOWLIST" | sort -u || true)
if [ -n "$HITS" ]; then
  echo "--- mobile-only terms found in payload ---"; echo "$HITS"
fi
assert_eq "$(printf '%s' "$HITS" | grep -c . || true)" "0" "no mobile-only guidance in payload"

# --- 4. The harmful inversions stay fixed ----------------------------------
# Upstream told PC/console devs never to use compute shaders or VFX Graph,
# because they are unavailable on mobile GPUs. On our platforms they are fine,
# and this was the single most damaging thing in the vendored tree.
BANNED=$(grep -rniE "never use compute shaders|don't use VFX Graph|do not use VFX Graph|compute shaders.*(not (available|supported))|VFX Graph.*(not (available|supported))" \
         .claude/ 2>/dev/null | grep -viE 'pc-console\.md' || true)
if [ -n "$BANNED" ]; then
  echo "--- compute shader / VFX Graph prohibitions found ---"; echo "$BANNED"
fi
assert_eq "$(printf '%s' "$BANNED" | grep -c . || true)" "0" "nothing forbids compute shaders or VFX Graph"

# --- 5. No skill carries the two inert Cursor keys -------------------------
# The mobile skill's damage was attributed to alwaysApply:true + globs **/*.cs.
# That story cannot be right in Claude Code: a 2026-07-30 probe found nothing
# reads alwaysApply, and a 2026-08-03 probe found nothing reads globs either —
# both are Cursor rule conventions that rode in with the vendored frontmatter.
# They are stripped from all 39 skills. The assertion is that they stay gone:
# a key that looks like a safety control but controls nothing is worse than no
# key, because it is read as a guarantee. Real always-on guidance goes in
# .claude/rules/, which CLAUDE.md loads for every session.
INERT=$(grep -rl '^alwaysApply:\|^globs:' .claude/skills/ 2>/dev/null || true)
if [ -n "$INERT" ]; then
  echo "--- skills carrying inert Cursor frontmatter keys ---"; echo "$INERT"
fi
assert_eq "$(printf '%s' "$INERT" | grep -c . || true)" "0" "no skill carries alwaysApply or globs"

# --- Summary ---------------------------------------------------------------
echo ""
echo "test-no-mobile: $TESTS_PASSED/$TESTS_RUN passed"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
