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

  # THIRD PHRASING, added 2026-08-13, and the reason it exists is that it was the half of an edit
  # that did not land. CREDITS.md states the split twice in one sentence: once as "17/64 split",
  # which the loop above reads, and once as "counts 17 `verbatim` and 64 `modified` rows", which
  # NEITHER of the two loops above could see — the backticks and the "and" put it outside both
  # patterns. The cut wave moved the first and left the second reading 25 and 76, so the sentence
  # contradicted itself across a single clause boundary while this guard reported clean.
  #
  # That is verbatim the recurrence this file's own header records at :9-13 ("a fix wave corrected
  # it to 30/71, and that wave's own NEXT commit ... made it 29/72 without re-deriving the prose"),
  # and the same shape as the round-1 finding recorded in the ECU-footprint block at :113-118: one
  # correct occurrence and one stale occurrence in a DIFFERENT phrasing, guard calls it clean.
  #
  # The sentence is the one that tells the reader the number is derived and hands them the command
  # to derive it, which makes a stale number there worse than anywhere else in the file.
  while IFS= read -r claim; do
    [ -n "$claim" ] || continue
    claimed_v=$(printf '%s' "$claim" | grep -oE '[0-9]+' | sed -n 1p)
    claimed_m=$(printf '%s' "$claim" | grep -oE '[0-9]+' | sed -n 2p)
    if [ "$claimed_v" != "$DC_VERBATIM" ] || [ "$claimed_m" != "$DC_MODIFIED" ]; then
      DC_BAD="${DC_BAD}${rel} claims 'counts ${claimed_v} verbatim and ${claimed_m} modified' — provenance.tsv has ${DC_VERBATIM} and ${DC_MODIFIED}"$'\n'
    fi
  done <<< "$(grep -oE 'counts [0-9]+ .verbatim. and [0-9]+ .modified.' "$REPO_DIR/$rel" || true)"
done <<< "$DC_QUOTING_FILES"

# A PER-PAIR floor for the phrasing added above, separate from the per-file floor below.
#
# The per-file check that follows is satisfied for CREDITS.md by its "17/64 split" occurrence alone,
# so it cannot see this third phrasing being reworded out of reach — which is precisely how the
# phrasing came to be unguarded in the first place. Only CREDITS.md carries it, so the pair is
# named rather than looped.
DC_PAIR_VACUOUS=""
if [ -f "$REPO_DIR/CREDITS.md" ]; then
  dc_pair_hits=$(grep -ocE 'counts [0-9]+ .verbatim. and [0-9]+ .modified.' "$REPO_DIR/CREDITS.md" 2>/dev/null || true)
  [ -n "$dc_pair_hits" ] || dc_pair_hits=0
  if [ "$dc_pair_hits" -lt 1 ]; then
    DC_PAIR_VACUOUS="CREDITS.md no longer states 'counts N verbatim and M modified' in a form this guard can read"$'\n'
  fi
fi
if [ -n "$DC_PAIR_VACUOUS" ]; then
  printf '%s' "$DC_PAIR_VACUOUS"
fi
assert_eq "0" "$(printf '%s' "$DC_PAIR_VACUOUS" | grep -c . || true)" \
  "CREDITS.md still states the split in the second, prose phrasing this guard reads"

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

# ============================================================================
# Hooks and installed scripts — the other half of the payload, and the half that had no block here
# at all until 2026-08-13.
#
# The 2026-08-03 cut applied "does it do something the model cannot do unaided?" to agents, commands
# and skills; hooks and scripts/ were out of scope and every one survived. When the criterion was
# applied to them on 2026-08-13, 15 of 27 hooks and 5 of 10 installed scripts left in one commit —
# and `grep -c hook tests/test-derived-counts.sh` returned 0 the morning of that commit, so seven
# quoted numbers across three shipped documents would have gone wrong simultaneously with the suite
# green. That is verbatim the failure the surface-pool block above was written for after the
# 2026-08-10 wave, one payload directory to the left.
#
# THE REGISTRATION IDENTITY IS THE POINT OF THIS BLOCK, not the prose counts.
#
# A hook file on disk that no `settings.json` entry names never runs, and Claude Code reports
# nothing — it is not an error, it is silence, exactly like a nested skill. A `settings.json` entry
# naming a file that is not there is the same silence from the other side. Both are invisible to
# every other guard in this suite, and the second one is what a cut of this size produces if a
# registration is missed. So the identity is asserted as a SET, both directions, by name: a count
# comparison would pass on a tree where one hook was deleted and an unrelated one double-registered.
echo "--- derived counts: hooks and installed scripts ---"

# Hooks on disk. `_lib.sh` is a sourced library, not a hook — it is the one file in this directory
# that settings.json must NOT name, and CLAUDE.md says so. It is also why a naive
# `grep -l HOOK_PROFILE_LEVEL=` overcounts: _lib.sh defines the constant it reads.
DCK_DISK=$(ls -1 "$REPO_DIR"/.claude/hooks/*.sh 2>/dev/null | sed 's|.*/||' | grep -vx '_lib.sh' | sort)
DCK_HOOKS=$(printf '%s\n' "$DCK_DISK" | grep -c . || true)

# Hooks registered in settings.json. Read with grep+sed rather than a JSON parser: this suite has no
# python/jq dependency anywhere else, and the shape here is one `"command": ".claude/hooks/x.sh"` per
# line. A malformed settings.json shows up as a set mismatch below, which is louder than a parse
# error swallowed by `|| true`.
DCK_REG=$(grep -oE '\.claude/hooks/[a-z0-9-]+\.sh' "$REPO_DIR/.claude/settings.json" 2>/dev/null \
          | sed 's|.claude/hooks/||' | sort -u)
DCK_REGISTERED=$(printf '%s\n' "$DCK_REG" | grep -c . || true)

# Blocking hooks — those that can actually stop a tool call. Derived from the call, not from a
# comment: `unity_hook_block` is _lib.sh's only exit-2 path, and a hook that stops using it stops
# blocking. The trailing space keeps the definition inside _lib.sh from matching its own callers.
DCK_BLOCKING=$(grep -l 'unity_hook_block ' "$REPO_DIR"/.claude/hooks/*.sh 2>/dev/null \
               | sed 's|.*/||' | grep -vx '_lib.sh' | grep -c . || true)

# Profile tiers, cumulative, as `_lib.sh` computes them: a hook runs when its declared level is <=
# the active profile, and a hook that declares no level always runs. session-brief.sh is the only
# one in the second class and it is deliberate, so `minimal` is "declared minimal, plus undeclared".
DCK_MINIMAL=0
DCK_STANDARD=0
DCK_STRICT=0
while IFS= read -r dck_h; do
  [ -n "$dck_h" ] || continue
  dck_lvl=$(grep -m1 '^HOOK_PROFILE_LEVEL=' "$REPO_DIR/.claude/hooks/$dck_h" 2>/dev/null \
            | sed 's/^HOOK_PROFILE_LEVEL="\(.*\)".*/\1/')
  case "$dck_lvl" in
    ''|minimal) DCK_MINIMAL=$((DCK_MINIMAL + 1)) ;;
    standard)   DCK_STANDARD=$((DCK_STANDARD + 1)) ;;
    strict)     DCK_STRICT=$((DCK_STRICT + 1)) ;;
  esac
done <<< "$DCK_DISK"
DCK_STANDARD=$((DCK_MINIMAL + DCK_STANDARD))
DCK_STRICT=$((DCK_STANDARD + DCK_STRICT))
DCK_DROPPED_MINIMAL=$((DCK_HOOKS - DCK_MINIMAL))

# The SET a `minimal` profile drops, by name, derived from the hook files.
#
# A count cannot carry this. `docs/HOOK-REFERENCE.md` told a user that `minimal` meant "maximum
# speed, minimal interference" while it silently switched off `bash-gate` -- the gate on destructive
# Bash commands, and one of only two hooks the 2026-08-13 surface criterion kept on merit -- and
# `warn-serialization`, whose absence is the silent-data-loss case serialization.md opens with. Three
# shipped documents described that profile by its intent instead of its effect, and each named a
# different, wrong subset (5, 4, and one that implied session-brief was dropped when it survives).
#
# So the document now LISTS the set inside a marked region, and this compares the two as sets. A
# hook whose declared level changes moves it between the lists and fails here by name.
DCK_DROPPED_DERIVED=$(
  while IFS= read -r dck_h; do
    [ -n "$dck_h" ] || continue
    dck_l=$(grep -m1 '^HOOK_PROFILE_LEVEL=' "$REPO_DIR/.claude/hooks/$dck_h" 2>/dev/null \
            | sed 's/^HOOK_PROFILE_LEVEL="\(.*\)".*/\1/')
    case "$dck_l" in
      ''|minimal) ;;
      *) printf '%s\n' "${dck_h%.sh}" ;;
    esac
  done <<< "$DCK_DISK" | sort
)

# The marked region in the document. awk, not sed -n '/a/,/b/p' piped anywhere: nothing downstream
# can exit early, and the markers are matched as whole fixed strings.
DCK_DROPPED_DOC=$(
  awk '
    /kinglet:minimal-drops:begin/ { inblock = 1; next }
    /kinglet:minimal-drops:end/   { inblock = 0 }
    inblock && /^- `/            { line = $0; sub(/^- `/, "", line); sub(/`.*$/, "", line); print line }
  ' "$REPO_DIR/docs/HOOK-REFERENCE.md" 2>/dev/null | sort
)

# Scripts. install.sh writes `scripts/*.sh` into `.claude/scripts/` and skips exactly one file,
# check-provenance.sh, because it validates THIS repository. The two numbers therefore always differ
# by one, and both are quoted in docs/GETTING-STARTED.md, so both are derived here. The skip is read
# out of install.sh rather than hardcoded: if that line ever names a second file, this derivation
# follows it instead of silently disagreeing.
#
# Counted as DISTINCT NAMES, not as matching lines. install.sh carries the same skip twice — once in
# the NEW_PATHS enumeration and once in the write loop, and its own comment says the two must stay in
# step — so a line count says 2 for a tree that skips one file. Round 1 of this block asserted the
# line count and went red on a correct tree.
DCK_SKIP_NAMES=$(grep -oE '\[ "\$b" = "[^"]+" \] && continue' "$REPO_DIR/install.sh" 2>/dev/null \
                 | sed 's/.*= "//; s/" \].*//' | sort -u)
DCK_SKIPPED=$(printf '%s\n' "$DCK_SKIP_NAMES" | grep -c . || true)
DCK_REPO_SCRIPTS=$(ls -1 "$REPO_DIR"/scripts/*.sh 2>/dev/null | grep -c . || true)
DCK_INSTALLED_SCRIPTS=$((DCK_REPO_SCRIPTS - DCK_SKIPPED))

# The derivation has to be able to fail, for the same reason the surface-pool block says so: run
# against a tree with no payload, every number above is 0, and 0 == 0 is a green suite that read
# nothing. Asserted before anything is compared against them.
DCK_DERIVATION="ok"
[ "$DCK_HOOKS"         -ge 1 ] || DCK_DERIVATION="no hooks found under \$REPO_DIR/.claude/hooks"
[ "$DCK_REGISTERED"    -ge 1 ] || DCK_DERIVATION="no hook registrations found in \$REPO_DIR/.claude/settings.json"
[ "$DCK_REPO_SCRIPTS"  -ge 1 ] || DCK_DERIVATION="no scripts found under \$REPO_DIR/scripts"
[ "$DCK_SKIPPED"       -eq 1 ] || DCK_DERIVATION="install.sh no longer skips exactly one script (skips: $(printf '%s' "$DCK_SKIP_NAMES" | tr '\n' ' ')) — the installed-script derivation is guessing"
assert_eq "ok" "$DCK_DERIVATION" \
  "the hook and script counts are derived from a tree that actually has hooks and scripts in it"

# --- The registration identity, both directions, by name. ---
DCK_UNREGISTERED=$(comm -23 <(printf '%s\n' "$DCK_DISK") <(printf '%s\n' "$DCK_REG"))
DCK_MISSING=$(comm -13 <(printf '%s\n' "$DCK_DISK") <(printf '%s\n' "$DCK_REG"))

if [ -n "$DCK_UNREGISTERED" ]; then
  printf '%s\n' "$DCK_UNREGISTERED" | sed 's|^|     on disk but named by no settings.json entry — it never runs: |'
fi
assert_eq "0" "$(printf '%s' "$DCK_UNREGISTERED" | grep -c . || true)" \
  "every hook file on disk is registered in settings.json ($DCK_HOOKS hooks)"

if [ -n "$DCK_MISSING" ]; then
  printf '%s\n' "$DCK_MISSING" | sed 's|^|     registered in settings.json but absent from .claude/hooks/ — Claude Code reports nothing: |'
fi
assert_eq "0" "$(printf '%s' "$DCK_MISSING" | grep -c . || true)" \
  "every hook registered in settings.json exists on disk ($DCK_REGISTERED registrations)"

# --- The minimal-profile dropped set, both directions, by name. ---
#
# The derivation must not be vacuous: if the marked region disappears or the awk stops matching,
# DCK_DROPPED_DOC is empty, and an empty list would otherwise be reported as "nothing undocumented"
# in one direction while the other direction carries the whole failure. Asserted non-empty first.
assert_eq "yes" "$([ -n "$DCK_DROPPED_DOC" ] && echo yes || echo no)" \
  "docs/HOOK-REFERENCE.md still carries a readable kinglet:minimal-drops region"

DCK_DROP_UNDOC=$(comm -23 <(printf '%s\n' "$DCK_DROPPED_DERIVED") <(printf '%s\n' "$DCK_DROPPED_DOC"))
DCK_DROP_PHANTOM=$(comm -13 <(printf '%s\n' "$DCK_DROPPED_DERIVED") <(printf '%s\n' "$DCK_DROPPED_DOC"))

if [ -n "$DCK_DROP_UNDOC" ]; then
  printf '%s\n' "$DCK_DROP_UNDOC" | sed 's|^|     minimal switches this hook off and HOOK-REFERENCE.md does not say so: |'
fi
assert_eq "0" "$(printf '%s' "$DCK_DROP_UNDOC" | grep -c . || true)" \
  "every hook the minimal profile drops is listed in docs/HOOK-REFERENCE.md ($DCK_DROPPED_MINIMAL dropped)"

if [ -n "$DCK_DROP_PHANTOM" ]; then
  printf '%s\n' "$DCK_DROP_PHANTOM" | sed 's|^|     HOOK-REFERENCE.md says minimal drops this and it does not: |'
fi
assert_eq "0" "$(printf '%s' "$DCK_DROP_PHANTOM" | grep -c . || true)" \
  "docs/HOOK-REFERENCE.md lists no hook the minimal profile actually keeps"

# --- The minimal-KEEPS complement, as a set. ---
#
# The drops list and the keeps list are complements, and a hand-written complement drifts
# independently of the thing it complements: a hook can be missing from BOTH lists and each list, read
# alone, still looks coherent.
DCK_KEEPS_DERIVED=$(
  while IFS= read -r dck_h; do
    [ -n "$dck_h" ] || continue
    dck_l=$(grep -m1 '^HOOK_PROFILE_LEVEL=' "$REPO_DIR/.claude/hooks/$dck_h" 2>/dev/null \
            | sed 's/^HOOK_PROFILE_LEVEL="\(.*\)".*/\1/')
    case "$dck_l" in ''|minimal) printf '%s\n' "${dck_h%.sh}" ;; esac
  done <<< "$DCK_DISK" | sort
)
DCK_KEEPS_DOC=$(
  awk '
    /kinglet:minimal-keeps:begin/ { inblock = 1; next }
    /kinglet:minimal-keeps:end/   { inblock = 0 }
    inblock && /^- `/ { l = $0; sub(/^- `/, "", l); sub(/`.*$/, "", l); print l }
  ' "$REPO_DIR/docs/HOOK-REFERENCE.md" 2>/dev/null | sort
)
assert_eq "yes" "$([ -n "$DCK_KEEPS_DOC" ] && echo yes || echo no)" \
  "docs/HOOK-REFERENCE.md still carries a readable kinglet:minimal-keeps region"
assert_eq "$DCK_KEEPS_DERIVED" "$DCK_KEEPS_DOC" \
  "the documented minimal-keeps list is exactly the hooks minimal keeps"

# ============================================================================
# THE FOUR HAND-WRITTEN RESTATEMENTS OF HOOK MEMBERSHIP.
#
# The set assertions above cover ONE marked region of ONE file. Four other places restated the same
# membership by hand, each proved silent when wrong:
#
#   1. docs/HOOK-REFERENCE.md's twelve per-hook `- **Profile:** X` lines — flipping one made the file
#      contradict its own marked region eleven lines above, suite green.
#   2. docs/HOOK-REFERENCE.md's Summary Table profile column — the same value a third time.
#   3. that table's Event and Matcher columns — correct against settings.json, asserted by nothing.
#   4. docs/ARCHITECTURE.md's Hook Summary table — all three again, in a second file.
#
# (4) was DELETED rather than guarded: it duplicated this document wholesale, and ARCHITECTURE.md's
# own paragraph argues that two documents listing one set by hand is how the list goes stale in one of
# them. The file was contradicting itself twenty lines apart. The remaining three are guarded here,
# because a per-hook reference page that does not state each hook's profile is not a reference page.
#
# Profile label convention: a hook that declares no HOOK_PROFILE_LEVEL runs under every profile, and
# the documents call that `always`. session-brief is the only one, and both places used to call it
# `minimal` — true only in the sense that minimal is the lowest profile that runs it, which is not
# what the column means anywhere else in the table.
echo "--- derived counts: hook membership restated by hand ---"

# hook -> declared level (or `always`), from the files.
DCK_LEVELS=$(
  while IFS= read -r dck_h; do
    [ -n "$dck_h" ] || continue
    dck_l=$(grep -m1 '^HOOK_PROFILE_LEVEL=' "$REPO_DIR/.claude/hooks/$dck_h" 2>/dev/null \
            | sed 's/^HOOK_PROFILE_LEVEL="\(.*\)".*/\1/')
    printf '%s\t%s\n' "${dck_h%.sh}" "${dck_l:-always}"
  done <<< "$DCK_DISK" | sort
)

# hook -> event, matcher, from settings.json. `(all)` is how the documents spell an empty matcher.
DCK_REG_TRIPLES=$(
  awk '
    /"[A-Za-z]+": \[/ && !/"hooks": \[/ { l=$0; sub(/^[^"]*"/,"",l); sub(/".*/,"",l); ev=l; matcher=""; next }
    /"matcher":/ { l=$0; sub(/^[^:]*:[[:space:]]*"/,"",l); sub(/".*/,"",l); matcher=l; next }
    /"command":[[:space:]]*"\.claude\/hooks\// {
        l=$0; sub(/^.*\.claude\/hooks\//,"",l); sub(/\.sh".*/,"",l)
        print l "\t" ev "\t" (matcher == "" ? "(all)" : matcher)
    }
  ' "$REPO_DIR/.claude/settings.json" 2>/dev/null | sort
)

# 1. The per-hook `- **Profile:** X` lines. Only the first word is compared: session-brief's carries a
#    parenthetical explaining why it is `always`, and that prose is not the claim.
DCK_PERHOOK_DOC=$(
  awk '
    /^#### / { h = $2; next }
    /^- \*\*Profile:\*\*/ && h != "" {
        l = $0; sub(/^- \*\*Profile:\*\*[[:space:]]*/, "", l); split(l, a, " "); print h "\t" a[1]; h = ""
    }
  ' "$REPO_DIR/docs/HOOK-REFERENCE.md" 2>/dev/null | sort
)
assert_eq "yes" "$([ -n "$DCK_PERHOOK_DOC" ] && echo yes || echo no)" \
  "docs/HOOK-REFERENCE.md still has readable per-hook Profile lines"
assert_eq "$DCK_LEVELS" "$DCK_PERHOOK_DOC" \
  "every per-hook Profile line matches the level its hook file declares"

# 2 and 3. The Summary Table: `| hook | Event | Matcher | Profile | Type | Purpose |`.
#
#    NOT `awk -F'|'`. Markdown escapes the matcher's alternation as `Edit\|Write`, and with `|` as
#    the field separator awk splits INSIDE that cell before any unescaping can run — the matcher
#    column comes out as `Edit\` and every subsequent column shifts left by one, so the profile
#    column is read out of the matcher's position. Round 1 of this block did exactly that and failed
#    against a correct document, printing two lines that looked identical because the first row
#    (`bash-gate`, matcher `Bash`, no escape) was the only one that survived the split intact.
#
#    So: protect the escaped pipes with a byte that cannot occur in the source, split on the real
#    separators, then restore.
DCK_TABLE_DOC=$(
  awk '
    /^\| [a-z0-9-]+ \| (PreToolUse|PostToolUse|PreCompact|SessionStart|Stop) \|/ {
        line = $0
        gsub(/\\\|/, "\001", line)
        split(line, f, "|")
        h=f[2]; ev=f[3]; ma=f[4]; pr=f[5]
        gsub(/^[ \t]+|[ \t]+$/, "", h); gsub(/^[ \t]+|[ \t]+$/, "", ev)
        gsub(/^[ \t]+|[ \t]+$/, "", ma); gsub(/^[ \t]+|[ \t]+$/, "", pr)
        gsub(/\001/, "|", ma)
        print h "\t" ev "\t" ma "\t" pr
    }
  ' "$REPO_DIR/docs/HOOK-REFERENCE.md" 2>/dev/null | sort
)
assert_eq "yes" "$([ -n "$DCK_TABLE_DOC" ] && echo yes || echo no)" \
  "docs/HOOK-REFERENCE.md still has a readable hook Summary Table"

# The expected table, joined from the two derivations rather than typed.
DCK_TABLE_DERIVED=$(
  while IFS="$(printf '\t')" read -r dck_h dck_ev dck_ma; do
    [ -n "$dck_h" ] || continue
    dck_pr=$(printf '%s\n' "$DCK_LEVELS" | awk -F'\t' -v k="$dck_h" '$1 == k { print $2 }')
    printf '%s\t%s\t%s\t%s\n' "$dck_h" "$dck_ev" "$dck_ma" "$dck_pr"
  done <<< "$DCK_REG_TRIPLES" | sort
)
assert_eq "$DCK_TABLE_DERIVED" "$DCK_TABLE_DOC" \
  "the Summary Table's event, matcher and profile columns match settings.json and the hook files"

# --- The quoted numbers. Same table shape, same flattening, same per-pair floors as above. ---
#
# NOTE ON THE TWO `of the` PATTERNS. `runs N of the M` (the minimal row) and `drops N of the M`
# (the cost paragraph) describe the SAME profile from opposite sides and must stay lexically
# disjoint. Round 1 of this block used a bare `[0-9]+ of the [0-9]+ hooks`, which matched the
# `drops 8 of the 12 hooks` sentence and reported the tree as having 4 where the doc said 8 -- a
# guard failing on a correct document because two of its own patterns overlapped. If either
# sentence is reworded, keep the leading verb.
#
# docs/ARCHITECTURE.md   "hooks/ 12 registered shell scripts"          total
# docs/ARCHITECTURE.md   "All 12 registered hooks source"              total
# docs/ARCHITECTURE.md   "minimal (4 cumulative"                       minimal tier
# docs/ARCHITECTURE.md   "standard (12 cumulative)"                    standard tier
# docs/ARCHITECTURE.md   "strict (12 cumulative"                       strict tier
# docs/GETTING-STARTED.md "hooks/ 12 hooks + _lib.sh"                  total
# docs/GETTING-STARTED.md "5 of them blocking"                         blocking
# docs/GETTING-STARTED.md "repo has 6 scripts; an installed project has 5"  repo, installed
# docs/HOOK-REFERENCE.md  "includes 12 hooks"                          total
# docs/HOOK-REFERENCE.md  "standard profile 12 hooks"                  standard tier
DCK_CLAIMS="docs/ARCHITECTURE.md	hooks/ [0-9]+ registered shell scripts	$DCK_HOOKS	-
docs/ARCHITECTURE.md	All [0-9]+ registered hooks source	$DCK_HOOKS	-
docs/ARCHITECTURE.md	.minimal. \([0-9]+ cumulative	$DCK_MINIMAL	-
docs/ARCHITECTURE.md	.standard. \([0-9]+ cumulative\)	$DCK_STANDARD	-
docs/ARCHITECTURE.md	.strict. \([0-9]+ cumulative	$DCK_STRICT	-
docs/GETTING-STARTED.md	hooks/ [0-9]+ hooks [+] _lib.sh	$DCK_HOOKS	-
docs/GETTING-STARTED.md	[0-9]+ of them blocking	$DCK_BLOCKING	-
docs/GETTING-STARTED.md	repo has [0-9]+ scripts; an installed project has [0-9]+	$DCK_REPO_SCRIPTS	$DCK_INSTALLED_SCRIPTS
docs/HOOK-REFERENCE.md	includes [0-9]+ hooks	$DCK_HOOKS	-
docs/HOOK-REFERENCE.md	runs [0-9]+ of the [0-9]+	$DCK_MINIMAL	$DCK_HOOKS
docs/HOOK-REFERENCE.md	all [0-9]+ hooks run	$DCK_STANDARD	-
docs/HOOK-REFERENCE.md	same [0-9]+ hooks as	$DCK_STRICT	-
docs/HOOK-REFERENCE.md	drops [0-9]+ of the [0-9]+	$DCK_DROPPED_MINIMAL	$DCK_HOOKS
docs/ARCHITECTURE.md	drops [0-9]+ of the [0-9]+	$DCK_DROPPED_MINIMAL	$DCK_HOOKS
.claude/settings.local.json.template	drops [0-9]+ of the [0-9]+	$DCK_DROPPED_MINIMAL	$DCK_HOOKS"

DCK_BAD=""
DCK_VACUOUS=""
while IFS=$'\t' read -r dck_rel dck_pat dck_want1 dck_want2; do
  [ -n "$dck_rel" ] || continue
  if [ ! -f "$REPO_DIR/$dck_rel" ]; then
    DCK_VACUOUS="${DCK_VACUOUS}${dck_rel} is not present, so its '${dck_pat}' claim was never checked"$'\n'
    continue
  fi

  # tr drains its input; neither reader here can exit early.
  dck_flat="$(tr '\n' ' ' < "$REPO_DIR/$dck_rel" | tr -s ' ')"
  dck_hits=0
  while IFS= read -r dck_claim; do
    [ -n "$dck_claim" ] || continue
    dck_hits=$((dck_hits + 1))
    dck_got1=$(printf '%s' "$dck_claim" | grep -oE '[0-9]+' | sed -n 1p)
    dck_got2=$(printf '%s' "$dck_claim" | grep -oE '[0-9]+' | sed -n 2p)
    if [ "$dck_got1" != "$dck_want1" ] || { [ "$dck_want2" != "-" ] && [ "$dck_got2" != "$dck_want2" ]; }; then
      DCK_BAD="${DCK_BAD}${dck_rel} claims '${dck_claim}' — the tree has ${dck_want1}"$([ "$dck_want2" != "-" ] && printf ' and %s' "$dck_want2")$'\n'
    fi
  done <<< "$(grep -oE "$dck_pat" <<< "$dck_flat" || true)"

  if [ "$dck_hits" -lt 1 ]; then
    DCK_VACUOUS="${DCK_VACUOUS}${dck_rel} no longer states its '${dck_pat}' claim in a form this guard can read"$'\n'
  fi
done <<< "$DCK_CLAIMS"

if [ -n "$DCK_BAD" ]; then
  printf '%s' "$DCK_BAD"
  printf '     %s\n' "Re-derive with: ls .claude/hooks/*.sh | grep -v _lib | wc -l ; ls scripts/*.sh | wc -l"
fi
assert_eq "0" "$(printf '%s' "$DCK_BAD" | grep -c . || true)" \
  "every hook and script count quoted in prose matches the tree ($DCK_HOOKS hooks, $DCK_BLOCKING blocking, tiers $DCK_MINIMAL/$DCK_STANDARD/$DCK_STRICT, $DCK_REPO_SCRIPTS repo scripts, $DCK_INSTALLED_SCRIPTS installed)"

if [ -n "$DCK_VACUOUS" ]; then
  printf '%s' "$DCK_VACUOUS"
fi
assert_eq "0" "$(printf '%s' "$DCK_VACUOUS" | grep -c . || true)" \
  "every hook-count phrasing this guard covers is still present in the file that carries it"

# What this block cannot see, stated rather than assumed:
#
#   - Whether a registered hook is registered on the RIGHT event. `validate-commit.sh` was removed in
#     this same wave for being PostToolUse when its whole job needed PreToolUse, and both the set
#     identity above and any count would have called that tree clean. Nothing in this suite reads a
#     hook's intended event, because nothing writes it down in a machine-readable form.
#   - Whether a hook does anything. The seven strict-gated hooks removed on 2026-08-13 were
#     registered, present, and dead; the profile tiers above would have counted them happily.
#   - Any count quoted in a phrasing not in the table. That is the standing residual the per-pair
#     floors exist to make loud when it shrinks — growing the covered set is still manual.
#   - MERGE-NOTES.md's hook counts, deliberately. They are dated statements about what a PAST wave
#     shipped ("32 surfaces: ... 27 registered hooks"), and a guard that forbids recording a former
#     state stops this repository writing its own history — the ruling field note 81 already made and
#     tests/test-mcp-naming.sh already applies to docs/research/.
