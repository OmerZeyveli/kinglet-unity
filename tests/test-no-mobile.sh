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
assert_eq "4" "$(find examples -type f | wc -l | tr -d ' ')" "4 examples (6 upstream - 2 mobile)"

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
HITS=$( { grep -rnE "$MOBILE_CS" "${SCAN_DIRS[@]}" 2>/dev/null || true
          grep -rniE "$MOBILE_CI" "${SCAN_DIRS[@]}" 2>/dev/null || true
        } | grep -vE "$ALLOWLIST" | sort -u || true)
if [ -n "$HITS" ]; then
  echo "--- mobile-only terms found in payload ---"; echo "$HITS"
fi
assert_eq "0" "$(printf '%s' "$HITS" | grep -c . || true)" "no mobile-only guidance in payload"

# --- 4. The harmful inversions stay fixed ----------------------------------
# Upstream told PC/console devs never to use compute shaders or VFX Graph,
# because they are unavailable on mobile GPUs. On our platforms they are fine,
# and this was the single most damaging thing in the vendored tree.
BANNED=$(grep -rniE "never use compute shaders|don't use VFX Graph|do not use VFX Graph|compute shaders.*(not (available|supported))|VFX Graph.*(not (available|supported))" \
         .claude/ 2>/dev/null | grep -viE 'pc-console\.md' || true)
if [ -n "$BANNED" ]; then
  echo "--- compute shader / VFX Graph prohibitions found ---"; echo "$BANNED"
fi
assert_eq "0" "$(printf '%s' "$BANNED" | grep -c . || true)" "nothing forbids compute shaders or VFX Graph"

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
assert_eq "0" "$(printf '%s' "$INERT" | grep -c . || true)" "no skill carries alwaysApply or globs"

# --- Summary ---------------------------------------------------------------
echo ""
echo "test-no-mobile: $TESTS_PASSED/$TESTS_RUN passed"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
