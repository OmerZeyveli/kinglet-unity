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

# "<n> verbatim, <m> modified" — the phrase both files use.
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
assert_eq "$(printf '%s' "$DC_BAD" | grep -c . || true)" "0" \
  "every provenance count quoted in prose matches provenance.tsv"

# If the phrasing in either file changes, the greps above stop matching and this test passes while
# checking nothing — the vacuity failure this repository has shipped before. So assert the greps
# still find something to check.
DC_FOUND=$(grep -hoE '[0-9]+ verbatim, [0-9]+ modified' "$REPO_DIR/CREDITS.md" "$REPO_DIR/README.md" 2>/dev/null | grep -c . || true)
assert_eq "$([ "$DC_FOUND" -ge 2 ] && echo enough || echo "only-$DC_FOUND")" "enough" \
  "both prose files still state the split in the form this test can read"
