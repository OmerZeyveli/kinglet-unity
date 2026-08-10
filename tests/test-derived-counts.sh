#!/usr/bin/env bash
# ============================================================================
# test-derived-counts.sh — a number quoted in prose must match what it is derived from.
#
# CREDITS.md and README.md quote the provenance split (how many tracked files are verbatim, how
# many modified, how many original). It is derived from provenance.tsv by a command CREDITS.md
# documents inline, and it moves whenever any row's `status` changes — which is most commits.
#
# It has gone stale three times in two days:
#   1. It read 34/67 while the manifest said 30/71, and shipped that way for four days.
#   2. A fix wave corrected it to 30/71, and that wave's own NEXT commit — flipping one file to
#      `modified` — made it 29/72 without re-deriving the prose.
#   3. The original-row count read 425 while the manifest said 434.
#
# After (2) the file gained a paragraph telling the reader to re-derive it before quoting it.
# It went stale again anyway, because a warning is not a guard: nothing failed, so nothing said so.
# That is the point of this file. The remedy for a number that drifts is an assertion, not a note
# asking people to be careful.
#
# Runner-provided: uses the runner's assert_eq and $REPO_DIR, defines neither, sets no `-e`, and
# contains no `exit`. Run it through tests/run-tests.sh and read this section; standalone it exits 0
# having asserted nothing.
# ============================================================================

echo "--- derived counts ---"

# The same derivation CREDITS.md documents. Counted here rather than trusted from anywhere.
DC_VERBATIM=$(awk -F'\t' '$0 !~ /^#/ && $1 != "path" && $6 == "verbatim"' "$REPO_DIR/provenance.tsv" | grep -c . || true)
DC_MODIFIED=$(awk -F'\t' '$0 !~ /^#/ && $1 != "path" && $6 == "modified"' "$REPO_DIR/provenance.tsv" | grep -c . || true)
DC_ORIGINAL=$(awk -F'\t' '$0 !~ /^#/ && $1 != "path" && $6 == "original"' "$REPO_DIR/provenance.tsv" | grep -c . || true)

# Every prose file that quotes the split. Adding a fourth quoting file without adding it here
# recreates the gap, so the list is short and explicit rather than a glob.
DC_QUOTING_FILES="CREDITS.md
README.md"

# Two phrasings quote the same split: "<n> verbatim, <m> modified" (both files' tables) and
# "<n>/<m> split" (CREDITS.md's prose). Finding 1 of the 2026-08-03 second-pass review was a stale
# number in the SECOND form sitting beside a guard that only read the first — the file had one
# correct comma-form occurrence and one stale slash-form occurrence, and the guard called it clean.
# Checking both forms, per file, is what stops that recurring.
DC_BAD=""
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  [ -f "$REPO_DIR/$rel" ] || continue

  while IFS= read -r claim; do
    [ -n "$claim" ] || continue
    claimed_v=$(printf '%s' "$claim" | awk '{print $1}')
    claimed_m=$(printf '%s' "$claim" | awk '{print $3}')
    if [ "$claimed_v" != "$DC_VERBATIM" ] || [ "$claimed_m" != "$DC_MODIFIED" ]; then
      DC_BAD="${DC_BAD}${rel} claims ${claimed_v} verbatim, ${claimed_m} modified — provenance.tsv has ${DC_VERBATIM} and ${DC_MODIFIED}"$'\n'
    fi
  done <<< "$(grep -oE '[0-9]+ verbatim, [0-9]+ modified' "$REPO_DIR/$rel" || true)"

  while IFS= read -r claim; do
    [ -n "$claim" ] || continue
    claimed_v=$(printf '%s' "$claim" | awk -F'/' '{print $1}')
    claimed_m=$(printf '%s' "$claim" | awk -F'/' '{print $2}' | awk '{print $1}')
    if [ "$claimed_v" != "$DC_VERBATIM" ] || [ "$claimed_m" != "$DC_MODIFIED" ]; then
      DC_BAD="${DC_BAD}${rel} claims ${claimed_v}/${claimed_m} split — provenance.tsv has ${DC_VERBATIM}/${DC_MODIFIED}"$'\n'
    fi
  done <<< "$(grep -oE '[0-9]+/[0-9]+ split' "$REPO_DIR/$rel" || true)"
done <<< "$DC_QUOTING_FILES"

# The original-row count is deliberately NOT quoted in prose any more, and so is not checked here.
# It moves on every commit that adds a tracked file — this guard's own commit shifted it from 434 to
# 435 and the guard caught itself — while telling a reader nothing they would act on. A number that
# drifts constantly and carries no signal is better removed than asserted. The verbatim/modified
# split stays: it only moves when a status flips, and it says something real about how much of the
# vendored layer survives unedited.
if [ -n "$DC_BAD" ]; then
  printf '%s' "$DC_BAD"
fi
assert_eq "0" "$(printf '%s' "$DC_BAD" | grep -c . || true)" \
  "every provenance count quoted in prose matches provenance.tsv"

# If the phrasing in a file changes, the greps above stop matching THAT FILE and this test passes
# while checking nothing for it — the vacuity failure finding 8 of the 2026-08-03 second-pass review
# found here: a combined threshold across both files let README.md lose its occurrence entirely while
# CREDITS.md's second occurrence kept the combined count above the bar. Count per file, and require
# every file this guard claims to cover to still state the split in a form it can read.
DC_VACUOUS=""
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  [ -f "$REPO_DIR/$rel" ] || continue
  dc_file_found=$(grep -hocE '[0-9]+ verbatim, [0-9]+ modified|[0-9]+/[0-9]+ split' "$REPO_DIR/$rel" 2>/dev/null || true)
  [ -n "$dc_file_found" ] || dc_file_found=0
  if [ "$dc_file_found" -lt 1 ]; then
    DC_VACUOUS="${DC_VACUOUS}${rel} states the split in no form this guard can read"$'\n'
  fi
done <<< "$DC_QUOTING_FILES"
if [ -n "$DC_VACUOUS" ]; then
  printf '%s' "$DC_VACUOUS"
fi
assert_eq "0" "$(printf '%s' "$DC_VACUOUS" | grep -c . || true)" \
  "every prose file this guard covers still states the split in a form it can read"

# ============================================================================
# The second derived number in this repository: how much of ECU survives in `unity-brainstorming`.
#
# `provenance.tsv:71` rules `origin=ecu` for a file that was rewritten on 2026-08-10, and its stated
# reason is a quantity — "32 of ECU's 69 substantive lines surviving verbatim, which is what
# origin=ecu rests on". MERGE-NOTES.md repeats the figure.
#
# The note column was collapsed in that same change on the argument that "a number in free text is a
# number nothing checks" — the row's previous note claimed a five-row table the file had had two rows
# of since `e994779`. Writing a NEW unchecked number while making that argument is the same defect
# with a fresh date on it, which is why this block exists: the figure is re-derived from the vendored
# original and compared against every place that quotes it.
#
# Derivation: for each substantive line of ECU 1.5.0's file (non-blank, and not a `---` frontmatter
# fence, which is punctuation rather than content), does that exact line still appear in the current
# skill? One awk pass rather than a grep per line — 69 subprocesses inside a test that runs on every
# commit is a cost with no benefit.
echo "--- derived counts: ECU survival in unity-brainstorming ---"

DCE_SKILL="$REPO_DIR/.claude/skills/unity-brainstorming/SKILL.md"
# The commit that vendored ECU v1.5.0 verbatim. Not the upstream pin in provenance.tsv's header —
# that names ECU's own repository, which is only reachable with --online. This is ours.
DCE_ANCHOR="45eada9"
DCE_UPSTREAM_PATH=".claude/skills/core/deep-interview/SKILL.md"

DCE_ORIGINAL="$(git -C "$REPO_DIR" show "${DCE_ANCHOR}:${DCE_UPSTREAM_PATH}" 2>/dev/null || true)"

if [ -z "$DCE_ORIGINAL" ] || [ ! -f "$DCE_SKILL" ]; then
  # A shallow clone has no $DCE_ANCHOR and cannot derive anything. Skipping is honest and visible in
  # the runner's output; failing would red the suite for a checkout depth rather than for a defect.
  skip_test "ECU survival not derivable here (no blob ${DCE_ANCHOR}:${DCE_UPSTREAM_PATH} — shallow clone?)"
else
  DCE_DERIVED="$(printf '%s\n' "$DCE_ORIGINAL" | awk '
    NR == FNR { if ($0 ~ /[^[:space:]]/) cur[$0] = 1; next }
    $0 ~ /[^[:space:]]/ && $0 != "---" { total++; if ($0 in cur) kept++ }
    END { printf "%d of ECU'"'"'s %d substantive lines", kept + 0, total + 0 }
  ' "$DCE_SKILL" -)"

  # Every file that quotes it. A file added to this list without the phrase fails the vacuity check
  # below rather than passing silently — the finding-8 shape this file already carries once.
  DCE_QUOTING_FILES="provenance.tsv
MERGE-NOTES.md"

  DCE_BAD=""
  DCE_VACUOUS=""
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -f "$REPO_DIR/$rel" ] || continue
    dce_found=0
    while IFS= read -r claim; do
      [ -n "$claim" ] || continue
      dce_found=$((dce_found + 1))
      if [ "$claim" != "$DCE_DERIVED" ]; then
        DCE_BAD="${DCE_BAD}${rel} claims '${claim}' — derivation says '${DCE_DERIVED}'"$'\n'
      fi
    done <<< "$(grep -oE "[0-9]+ of ECU's [0-9]+ substantive lines" "$REPO_DIR/$rel" || true)"
    if [ "$dce_found" -lt 1 ]; then
      DCE_VACUOUS="${DCE_VACUOUS}${rel} states the ECU survival in no form this guard can read"$'\n'
    fi
  done <<< "$DCE_QUOTING_FILES"

  if [ -n "$DCE_BAD" ]; then
    printf '%s' "$DCE_BAD"
    printf '     %s\n' "Re-derive it, then update every file above in the same commit."
  fi
  assert_eq "0" "$(printf '%s' "$DCE_BAD" | grep -c . || true)" \
    "every quoted ECU-survival figure matches the line-by-line derivation ($DCE_DERIVED)"

  if [ -n "$DCE_VACUOUS" ]; then
    printf '%s' "$DCE_VACUOUS"
  fi
  assert_eq "0" "$(printf '%s' "$DCE_VACUOUS" | grep -c . || true)" \
    "every file this guard covers still states the ECU survival in a form it can read"
fi
