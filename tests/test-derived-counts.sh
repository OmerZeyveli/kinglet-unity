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
# ECU's own footprint — a PER-ORIGIN count, and a different number from the repo-wide split above.
#
# CREDITS.md's relationship table read "101 files" on 2026-08-11 while provenance.tsv held 99
# origin=ecu rows and README.md, four sections away, correctly said 99. Two of the repo's own
# provenance documents disagreed with each other and with the manifest, and every guard in this
# suite was green: the block above only reads the repo-wide verbatim/modified split, which was
# correct the whole time.
#
# CREDITS.md warns in prose that per-origin counts belong in the sections and the manifest, never in
# the repo-wide sentence. That warning is why the two numbers are distinguishable at all — and it is
# also why this block exists, because a warning is not a guard, which is the lesson the header of
# this file already records once.
#
# ROUND 1: this block shipped reading ONE phrasing per file, and the phrasing it did not read was the
# one that was wrong. README.md:184 said "71 of 101 ECU-origin files now `modified`" thirteen lines
# below its own correct "99 files from ECU", and the per-file vacuity check was satisfied by the
# correct occurrence. That is verbatim the failure this file's header records at :37-41 — one correct
# occurrence and one stale occurrence in a different phrasing, guard calls it clean — reproduced by
# the commit that cites it.
#
# Two changes came out of that:
#
#   1. EVERY phrasing the covered files actually use is read, and each (file, phrasing) pair carries
#      its own floor. A per-FILE floor cannot see a phrasing going unread, because another phrasing
#      in the same file keeps the file's count above 1. A per-pair floor turns "someone reworded the
#      sentence" from silent narrowing into a failure that names the file and the phrasing.
#
#   2. Every match runs against the file with newlines collapsed to spaces. `71 of 101` sat at the
#      end of README.md:184 and `ECU-origin files now \`modified\`` began :185, so NO line-oriented
#      grep could have read it at any point. Measured 2026-08-11 on the pre-fix file:
#        $ grep -oE '[0-9]+ of [0-9]+ ECU-origin files' README.md      -> no match
#        $ tr '\n' ' ' < README.md | tr -s ' ' | grep -oE '...'        -> 71 of 101 ECU-origin files
#      This is the second line-wrap false-negative found in this wave; the first was a stale licence
#      claim in .claude/NOTICE.md that a plain grep -F reported as removed.
echo "--- derived counts: ECU footprint ---"

DCF_ECU_FILES=$(awk -F'\t' '$0 !~ /^#/ && $1 != "path" && $2 == "ecu"' "$REPO_DIR/provenance.tsv" | grep -c . || true)
DCF_ECU_VERBATIM=$(awk -F'\t' '$0 !~ /^#/ && $1 != "path" && $2 == "ecu" && $6 == "verbatim"' "$REPO_DIR/provenance.tsv" | grep -c . || true)
DCF_ECU_MODIFIED=$(awk -F'\t' '$0 !~ /^#/ && $1 != "path" && $2 == "ecu" && $6 == "modified"' "$REPO_DIR/provenance.tsv" | grep -c . || true)

# The three phrasings, and which file carries each. Field 3 is the expected value the first captured
# number must equal; field 4 the second, or `-` when the phrasing carries only one number.
#
#   CREDITS.md   "99 files; 25 of them still byte-identical"         total, verbatim
#   README.md    "99 files from ECU"                                 total
#   README.md    "74 of 99 ECU-origin files now `modified`"          modified, total
#
# A phrasing this table does not list is still unread — that is the standing residual, and the reason
# the pairs carry floors is so that shrinking the covered set is loud even though growing it is not.
DCF_CLAIMS="CREDITS.md	[0-9]+ files; [0-9]+ of them still byte-identical	$DCF_ECU_FILES	$DCF_ECU_VERBATIM
README.md	[0-9]+ files from ECU	$DCF_ECU_FILES	-
README.md	[0-9]+ of [0-9]+ ECU-origin files now .modified.	$DCF_ECU_MODIFIED	$DCF_ECU_FILES"

DCF_BAD=""
DCF_VACUOUS=""
while IFS=$'\t' read -r dcf_rel dcf_pat dcf_want1 dcf_want2; do
  [ -n "$dcf_rel" ] || continue
  if [ ! -f "$REPO_DIR/$dcf_rel" ]; then
    DCF_VACUOUS="${DCF_VACUOUS}${dcf_rel} is not present, so its '${dcf_pat}' claim was never checked"$'\n'
    continue
  fi

  # tr drains its input; neither reader here can exit early.
  dcf_flat="$(tr '\n' ' ' < "$REPO_DIR/$dcf_rel" | tr -s ' ')"
  dcf_hits=0
  while IFS= read -r dcf_claim; do
    [ -n "$dcf_claim" ] || continue
    dcf_hits=$((dcf_hits + 1))
    # Numbers in order of appearance, whatever the phrasing puts around them.
    dcf_got1=$(printf '%s' "$dcf_claim" | grep -oE '[0-9]+' | sed -n 1p)
    dcf_got2=$(printf '%s' "$dcf_claim" | grep -oE '[0-9]+' | sed -n 2p)
    if [ "$dcf_got1" != "$dcf_want1" ] || { [ "$dcf_want2" != "-" ] && [ "$dcf_got2" != "$dcf_want2" ]; }; then
      DCF_BAD="${DCF_BAD}${dcf_rel} claims '${dcf_claim}' — provenance.tsv gives ${dcf_want1}"$([ "$dcf_want2" != "-" ] && printf ' and %s' "$dcf_want2")$'\n'
    fi
  done <<< "$(grep -oE "$dcf_pat" <<< "$dcf_flat" || true)"

  if [ "$dcf_hits" -lt 1 ]; then
    DCF_VACUOUS="${DCF_VACUOUS}${dcf_rel} no longer states its '${dcf_pat}' claim in a form this guard can read"$'\n'
  fi
done <<< "$DCF_CLAIMS"

if [ -n "$DCF_BAD" ]; then
  printf '%s' "$DCF_BAD"
fi
assert_eq "0" "$(printf '%s' "$DCF_BAD" | grep -c . || true)" \
  "every ECU footprint quoted in prose matches provenance.tsv ($DCF_ECU_FILES files, $DCF_ECU_VERBATIM verbatim, $DCF_ECU_MODIFIED modified)"

if [ -n "$DCF_VACUOUS" ]; then
  printf '%s' "$DCF_VACUOUS"
fi
assert_eq "0" "$(printf '%s' "$DCF_VACUOUS" | grep -c . || true)" \
  "every ECU-footprint phrasing this guard covers is still present in the file that carries it"

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

# Two separate preconditions, asserted separately. Round 1 ORed them into one `skip_test`, which
# meant a deleted skill file and an unreachable blob produced the same silent green — and a shallow
# clone silenced the guard entirely. Demonstrated by the round-2 review: in a `git clone --depth 1`
# the block printed SKIP, the figure was then set to `99 of ECU's 69` in BOTH quoting files, the
# suite stayed green and `check-provenance.sh` still printed `provenance OK`.
#
# Ruling taken: FAIL, do not skip. A shallow checkout is not a supported environment anywhere else in
# this suite — tests/test-surface-references.sh runs `git ls-files`, the baseline regenerator runs
# `git ls-tree` against an anchor commit — and a guard that turns itself off in an unusual state is
# one that goes quiet exactly when nobody is watching.
assert_file_exists "$DCE_SKILL" \
  "the skill whose ECU survival is being derived exists"

DCE_HAVE_BLOB="yes"
[ -n "$DCE_ORIGINAL" ] || DCE_HAVE_BLOB="no (unreachable: ${DCE_ANCHOR}:${DCE_UPSTREAM_PATH} — shallow clone or rewritten history)"
assert_eq "yes" "$DCE_HAVE_BLOB" \
  "the vendored ECU original is readable at ${DCE_ANCHOR}, so the figure can be derived at all"

if [ -n "$DCE_ORIGINAL" ] && [ -f "$DCE_SKILL" ]; then
  DCE_DERIVED="$(printf '%s\n' "$DCE_ORIGINAL" | awk '
    NR == FNR { if ($0 ~ /[^[:space:]]/) cur[$0] = 1; next }
    $0 ~ /[^[:space:]]/ && $0 != "---" { total++; if ($0 in cur) kept++ }
    END { printf "%d of ECU'"'"'s %d substantive lines", kept + 0, total + 0 }
  ' "$DCE_SKILL" -)"

  # Every file that quotes the figure — INCLUDING THIS ONE. Round 1 quoted it in the header comment
  # above and left itself off the list, so the guard did not check itself: the one file guaranteed to
  # be read by anyone debugging the number was the one file allowed to state it wrongly. A file added
  # here without the phrase fails the vacuity check below rather than passing silently — the
  # finding-8 shape this file already carries once.
  #
  # Note the header comment is the ONLY place in this file allowed to state the figure. Do not quote
  # it again in prose here, not even historically: this guard cannot tell a stale claim from a
  # correct record of an older one, and a comment saying "round 1 said N" would go red the day N
  # legitimately changes.
  DCE_QUOTING_FILES="provenance.tsv
MERGE-NOTES.md
tests/test-derived-counts.sh"

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

# ============================================================================
# The surface pool — agents, commands and skills, counted in the tree.
#
# The 2026-08-10 process-chain wave changed the pool's COMPOSITION without changing its TOTAL: two
# commands were deleted and two skills added. Nothing in this repository watched a composition, so
# four numbers went wrong simultaneously and eight consecutive task reviews passed over them —
# README.md's "What's in the box" table (commands and skills), and docs/ARCHITECTURE.md's component
# tree (the same two). All four were correct at the branch point and wrong from the first task
# onward. A fifth and sixth, docs/ARCHITECTURE.md's two prose skill counts, had been stale since the
# wave before that.
#
# The excuse that let them rot is worth recording, because it was written down in the file it
# protected: docs/ARCHITECTURE.md carried a parenthetical saying "Nothing enforces these exact
# numbers in text — cross-check … if they look stale." That is the same shape this file's own header
# already answers at :16 — a warning is not a guard — reproduced four sections lower. Both the
# parenthetical and the numbers are fixed; this block is why the fix stays fixed.
#
# CLAUDE.md is deliberately NOT in the table below. Its ruling is that the repo guide states the
# criterion and never the count ("Derive it, never quote it"), so there is nothing here to check —
# a file that quotes no number cannot quote a stale one. Adding it would mean adding a number to it
# first, which is the opposite of the fix.
echo "--- derived counts: the surface pool ---"

# One `ls` per surface class, `grep -c .` to count — it drains its input, so no early-exit reader is
# on the right-hand side of these pipes. Skills are counted as SKILL.md files exactly one level deep,
# which is the only depth Claude Code discovers; a nested skill is test-skill-discovery.sh §1's
# business, not this file's, and would show up here as a shortfall rather than as a wrong number.
DCS_AGENTS=$(ls -1 "$REPO_DIR"/.claude/agents/*.md 2>/dev/null | grep -c . || true)
DCS_COMMANDS=$(ls -1 "$REPO_DIR"/.claude/commands/*.md 2>/dev/null | grep -c . || true)
DCS_SKILLS=$(ls -1 "$REPO_DIR"/.claude/skills/*/SKILL.md 2>/dev/null | grep -c . || true)
DCS_TOTAL=$((DCS_AGENTS + DCS_COMMANDS + DCS_SKILLS))

# The derivation itself has to be able to fail. Run from the wrong directory, or against a tree where
# the payload has moved, every count above is 0 — and 0 compared against 0 is a green suite that
# inspected nothing. Asserted before anything is compared to them.
DCS_DERIVATION="ok"
[ "$DCS_AGENTS"   -ge 1 ] || DCS_DERIVATION="no agents found under \$REPO_DIR/.claude/agents"
[ "$DCS_COMMANDS" -ge 1 ] || DCS_DERIVATION="no commands found under \$REPO_DIR/.claude/commands"
[ "$DCS_SKILLS"   -ge 1 ] || DCS_DERIVATION="no skills found under \$REPO_DIR/.claude/skills"
assert_eq "ok" "$DCS_DERIVATION" \
  "the surface counts are derived from a tree that actually has surfaces in it"

# Every phrasing, in every file that quotes one, each with its own floor. A per-FILE floor cannot see
# a single phrasing going unread — README.md would keep three table rows matching while its pool
# sentence was reworded into invisibility — which is finding 1 of this wave's round 1, recorded at
# :113-125 above and not repeated here by hand.
#
# Field 3 is the value the first captured number must equal; field 4 the second, or `-` for the
# single-number phrasings, which is all of these.
#
# MATCHED AGAINST THE FILE FLATTENED, and here that is load-bearing for four of the eleven pairs
# rather than a precaution. Measured 2026-08-11 on the corrected files:
#
#   $ grep -oE 'agents/ [0-9]+ agent definitions' docs/ARCHITECTURE.md          -> no match
#   $ grep -oE '[0-9]+-surface pool' README.md                                  -> no match
#
# The tree block writes `agents/             8 agent definitions`, so the words are separated by a
# run of spaces that only `tr -s ' '` collapses; and README.md's pool sentence wraps mid-phrase.
# The wrap has a second sting: it wraps inside a BLOCKQUOTE, so flattening leaves the `>`
# continuation marker standing between the two words —
#
#   $ tr '\n' ' ' < README.md | tr -s ' ' | grep -oE '.{18}[0-9]+-surface.{12}'
#    code is whose, a 33-surface > pool cut
#
# — which is why that one pattern tolerates an optional `> ` and the others do not. A rewrap at a
# different point in the phrase would not match, and that is deliberate: it fails the floor below by
# name instead of quietly checking nothing.
DCS_CLAIMS="README.md	\*\*Agents\*\* [|] [0-9]+	$DCS_AGENTS	-
README.md	\*\*Commands\*\* [|] [0-9]+	$DCS_COMMANDS	-
README.md	\*\*Skills\*\* [|] [0-9]+	$DCS_SKILLS	-
README.md	[0-9]+-surface (> )?pool	$DCS_TOTAL	-
docs/ARCHITECTURE.md	agents/ [0-9]+ agent definitions	$DCS_AGENTS	-
docs/ARCHITECTURE.md	commands/ [0-9]+ user-invocable slash commands	$DCS_COMMANDS	-
docs/ARCHITECTURE.md	skills/ [0-9]+ knowledge modules	$DCS_SKILLS	-
docs/ARCHITECTURE.md	[0-9]+ in total, flat	$DCS_SKILLS	-
docs/ARCHITECTURE.md	stripped from every skill . all [0-9]+ of them	$DCS_SKILLS	-
docs/ARCHITECTURE.md	[0-9]+ agents total	$DCS_AGENTS	-
docs/SKILL-CATALOG.md	[0-9]+ skills, one directory each	$DCS_SKILLS	-
docs/SKILL-CATALOG.md	Current Skills \([0-9]+, flat\)	$DCS_SKILLS	-"

DCS_BAD=""
DCS_VACUOUS=""
while IFS=$'\t' read -r dcs_rel dcs_pat dcs_want1 dcs_want2; do
  [ -n "$dcs_rel" ] || continue
  if [ ! -f "$REPO_DIR/$dcs_rel" ]; then
    DCS_VACUOUS="${DCS_VACUOUS}${dcs_rel} is not present, so its '${dcs_pat}' claim was never checked"$'\n'
    continue
  fi

  # tr drains its input; neither reader here can exit early.
  dcs_flat="$(tr '\n' ' ' < "$REPO_DIR/$dcs_rel" | tr -s ' ')"
  dcs_hits=0
  while IFS= read -r dcs_claim; do
    [ -n "$dcs_claim" ] || continue
    dcs_hits=$((dcs_hits + 1))
    dcs_got1=$(printf '%s' "$dcs_claim" | grep -oE '[0-9]+' | sed -n 1p)
    dcs_got2=$(printf '%s' "$dcs_claim" | grep -oE '[0-9]+' | sed -n 2p)
    if [ "$dcs_got1" != "$dcs_want1" ] || { [ "$dcs_want2" != "-" ] && [ "$dcs_got2" != "$dcs_want2" ]; }; then
      DCS_BAD="${DCS_BAD}${dcs_rel} claims '${dcs_claim}' — the tree has ${dcs_want1}"$'\n'
    fi
  done <<< "$(grep -oE "$dcs_pat" <<< "$dcs_flat" || true)"

  if [ "$dcs_hits" -lt 1 ]; then
    DCS_VACUOUS="${DCS_VACUOUS}${dcs_rel} no longer states its '${dcs_pat}' claim in a form this guard can read"$'\n'
  fi
done <<< "$DCS_CLAIMS"

if [ -n "$DCS_BAD" ]; then
  printf '%s' "$DCS_BAD"
  printf '     %s\n' "Re-derive with: ls .claude/agents/*.md | wc -l ; ls .claude/commands/*.md | wc -l ; ls .claude/skills/*/SKILL.md | wc -l"
fi
assert_eq "0" "$(printf '%s' "$DCS_BAD" | grep -c . || true)" \
  "every surface count quoted in prose matches the tree ($DCS_AGENTS agents, $DCS_COMMANDS commands, $DCS_SKILLS skills, $DCS_TOTAL total)"

if [ -n "$DCS_VACUOUS" ]; then
  printf '%s' "$DCS_VACUOUS"
fi
assert_eq "0" "$(printf '%s' "$DCS_VACUOUS" | grep -c . || true)" \
  "every surface-count phrasing this guard covers is still present in the file that carries it"
