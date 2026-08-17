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

# Rules and repo-level templates. Both are quoted as counts in README.md. `docs/ARCHITECTURE.md`
# called `.claude/rules/*` hand-maintained until 2026-08-14 — wrongly from the moment this line
# existed, since the derivation and the sentence denying it landed in one commit. That file now says
# the derivation exists and that no row below reads ITS copy of the count, which is the true residual:
# the rules rows name README.md and docs/GETTING-STARTED.md only. `templates/` is the repo-root C#
# scaffold directory, not `.claude/templates/`, which does not exist; README.md says so in the same
# row it quotes the number.
DCS_RULES=$(ls -1 "$REPO_DIR"/.claude/rules/*.md 2>/dev/null | grep -c . || true)
DCS_TEMPLATES=$(ls -1 "$REPO_DIR"/templates/* 2>/dev/null | grep -c . || true)

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
  # and the same shape as the round-1 finding recorded in the ECU-footprint block at :163-168: one
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
# correct occurrence. That is verbatim the failure this file's header records at :44-48 — one correct
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
#      end of README.md:184 and `ECU-origin files now \`modified\`` began README.md:185 — both
#      2026-08-11 line numbers into the PRE-FIX file, kept as history — so NO line-oriented
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
DCF_MULTISITE=""
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
      # NOT `"$([ … ] && printf …)"` — the shape the DCK block forty lines down documents and fixes.
      # For rows whose second column is `-` that AND-list short-circuits, the command substitution
      # exits 1, and an assignment site is one of the two places `set -e` reaches that people expect
      # it not to. Inert under the runner (which does `set +e` before sourcing) and reachable only on
      # the failure path — both harness accidents, not a design. Brought across on 2026-08-14: the
      # commit that copied MULTISITE into this block had copied the hazard's neighbour without the
      # neighbour's fix.
      dcf_extra=""
      [ "$dcf_want2" = "-" ] || dcf_extra=" and $dcf_want2"
      DCF_BAD="${DCF_BAD}${dcf_rel} claims '${dcf_claim}' — provenance.tsv gives ${dcf_want1}${dcf_extra}"$'\n'
    fi
  done <<< "$(grep -oE "$dcf_pat" <<< "$dcf_flat" || true)"

  if [ "$dcf_hits" -lt 1 ]; then
    DCF_VACUOUS="${DCF_VACUOUS}${dcf_rel} no longer states its '${dcf_pat}' claim in a form this guard can read"$'\n'
  elif [ "$dcf_hits" -gt 1 ]; then
    # See the DCK_MULTISITE block for the finding this enforces (ledger 203). Applied to every
    # claims table in this file, not only the one whose row happened to violate it.
    DCF_MULTISITE="${DCF_MULTISITE}${dcf_rel}'s '${dcf_pat}' row matches ${dcf_hits} sites — its vacuity check is a union over them. Split it into one row per site, with lexically disjoint patterns."$'\n'
  fi
done <<< "$DCF_CLAIMS"

if [ -n "$DCF_MULTISITE" ]; then
  printf '%s' "$DCF_MULTISITE"
fi
assert_eq "0" "$(printf '%s' "$DCF_MULTISITE" | grep -c . || true)" \
  "every ECU-footprint claim row matches exactly one site, so no row's vacuity check is a union over sites"

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
# `provenance.tsv:54` — the `.claude/skills/unity-brainstorming/SKILL.md` row, which is what to grep
# for; it was cited as line 71 until 2026-08-14, by which point line 71 held a different file's
# checksum —
# rules `origin=ecu` for a file that was rewritten on 2026-08-10, and its stated
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
# CLAUDE.md IS IN THE TABLE BELOW SINCE 2026-08-17, AND THE GROUND IT WAS EXCLUDED ON WAS FALSE
# ABOUT THE FILE IT EXCLUDED. The exclusion read: *"its ruling is that the repo guide states the
# criterion and never the count ('Derive it, never quote it'), so there is nothing here to check —
# a file that quotes no number cannot quote a stale one."* The premise is right and the conclusion
# does not follow from it, because `CLAUDE.md` does not obey its own ruling: it quotes the agent
# count **twice, in the present tense** — *"The N agents shipped today"* and *"All N current
# agents"*. Both are correct today. That is what makes this a guard gap rather than a stale figure,
# and it is why the GROUND mattered more than the sites: an exclusion justified by a property the
# excluded file does not have is worse than a disclosed gap, because it tells the next reader not
# to look.
#
# A THIRD NUMERAL IN THAT FILE IS PINNED AND MUST STAY PINNED, and it is why both patterns below are
# narrow rather than one loose `[0-9]+ agents`. `CLAUDE.md`'s history paragraph reads *"(8 agents,
# 9 commands, 5 templates)"* of the Donchitos design/production layer that was CUT on 2026-08-03.
# Its 8 is a dead figure that happens to equal the live one today; re-deriving it would rewrite a
# record of what was removed. The two patterns below match the present-tense sentences and not that
# one — and the block's own multisite check is what will red if a rewording makes either of them
# ambiguous, rather than a comment promising they are not.
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
# :163-183 above and not repeated here by hand. (Both self-citations in this file pointed at line 113
# until 2026-08-14, by which point line 113 was the paragraph about the original-row count — a
# self-citation rots exactly like any other, and no sweep shaped like a path saw either of these.)
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
docs/SKILL-CATALOG.md	Current Skills \([0-9]+, flat\)	$DCS_SKILLS	-
docs/GETTING-STARTED.md	agents/ [0-9]+ specialized sub-agents	$DCS_AGENTS	-
docs/GETTING-STARTED.md	commands/ [0-9]+ slash commands	$DCS_COMMANDS	-
docs/GETTING-STARTED.md	skills/ [0-9]+ knowledge modules	$DCS_SKILLS	-
docs/GETTING-STARTED.md	rules/ [0-9]+ always-loaded coding standards	$DCS_RULES	-
README.md	\*\*Rules\*\* [|] [0-9]+	$DCS_RULES	-
README.md	\*\*Templates\*\* [|] [0-9]+	$DCS_TEMPLATES	-
CLAUDE.md	The [0-9]+ agents shipped today	$DCS_AGENTS	-
CLAUDE.md	All [0-9]+ current agents	$DCS_AGENTS	-
docs/AGENT-GUIDE.md	All [0-9]+ Agents at a Glance	$DCS_AGENTS	-
CONTRIBUTING.md	All [0-9]+ shipping agents	$DCS_AGENTS	-"

# COVERAGE HERE IS PHRASE-KEYED, NOT FILE-KEYED, AND "CLAUDE.md IS NOW IN THE TABLE" DOES NOT MEAN
# WHAT IT SOUNDS LIKE. A row watches one sentence. A brand-new wrong figure in a file this block
# already reads ships silently: measured, inserting `Kinglet currently ships 99 agents.` into
# `CLAUDE.md` leaves this file green and `tests/test-surface-references.sh` green too. That is not a
# defect in any row — it is the shape of the mechanism, and it is written here because the next
# maintainer reading a file name in the table above will otherwise assume the file is covered.
# A file-level backstop (*"this file carries N numerals beside a surface noun; M of them have
# rows"*) is a real design with a real cost and it is not this block's to bolt on.
#
# EVERY PATTERN IN EVERY CLAIMS TABLE ABOVE IS DIGIT-ONLY, AND A WORD NUMERAL IS THEREFORE INVISIBLE
# TO ALL OF THEM. That is a property of the guard, not of the tree. Three consecutive review rounds
# swept this class with digit-only expressions and each one read its own zero as coverage;
# `CONTRIBUTING.md`'s agent count read *"All eight shipping agents"* until 2026-08-17 — live,
# correct, and unreachable by any row above.
#
# THE PER-INSTANCE REMEDY WAS "CONVERT IT AND ADD A ROW", AND IT WAS NOT ENOUGH. Written here in
# round 1, applied to `CONTRIBUTING.md`, and NOT applied to that same round's own sweep over
# `docs/research/codex-client/*` — where an independent derivation then found eight further live
# figures, four of them word numerals, and falsified five at once with the full suite reading
# `Failed: 0`. A remedy that has to be remembered at every site is a remedy that will be forgotten
# at one. So the word-numeral block at the foot of this file **makes the class reachable** — it
# normalises words to digits in its own flattener, so an ordinary `[0-9]+` row can guard a figure
# spelled *twelve*. That is the whole of what it does.
#
# **IT DOES NOT CLOSE THE CLASS, AND THE FIRST VERSION OF THIS PARAGRAPH SAID IT DID** — three lines
# under the paragraph above explaining that coverage here is phrase-keyed, which is the reason it
# cannot. What shipped is a hand-maintained table of rows, not a sweep: a *new* word-numeral live
# figure in a file the block already reads is not caught, measured with a word numeral rather than a
# digit (`Kinglet currently ships twelve agents and ninety-nine skills.` into `CLAUDE.md` leaves this
# file and `tests/test-surface-references.sh` both green), and an independent derivation found four
# further live members after the block shipped, falsified together with the full suite unchanged.
#
# **The honest statement is a method, not a closure**, and `docs/research/codex-client/README.md`'s
# instruments section already carries it: *any coverage claim over a directory must name the
# instruments that produced it*. Reaching a class is not sweeping it. Convert-and-add is still fine
# where it is natural; it is no longer the only option; and neither it nor this block is an answer to
# *"is this class swept"* — only a file-level backstop would be, and that is the design named above
# as not this block's to bolt on.

DCS_BAD=""
DCS_VACUOUS=""
DCS_MULTISITE=""
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
  elif [ "$dcs_hits" -gt 1 ]; then
    # See the DCK_MULTISITE block for the finding this enforces (ledger 203). Applied to every
    # claims table in this file, not only the one whose row happened to violate it.
    DCS_MULTISITE="${DCS_MULTISITE}${dcs_rel}'s '${dcs_pat}' row matches ${dcs_hits} sites — its vacuity check is a union over them. Split it into one row per site, with lexically disjoint patterns."$'\n'
  fi
done <<< "$DCS_CLAIMS"

if [ -n "$DCS_MULTISITE" ]; then
  printf '%s' "$DCS_MULTISITE"
fi
assert_eq "0" "$(printf '%s' "$DCS_MULTISITE" | grep -c . || true)" \
  "every surface-count claim row matches exactly one site, so no row's vacuity check is a union over sites"

if [ -n "$DCS_BAD" ]; then
  printf '%s' "$DCS_BAD"
  printf '     %s\n' "Re-derive with: ls .claude/agents/*.md | wc -l ; ls .claude/commands/*.md | wc -l ; ls .claude/skills/*/SKILL.md | wc -l ; ls .claude/rules/*.md | wc -l ; ls templates/* | wc -l"
fi
assert_eq "0" "$(printf '%s' "$DCS_BAD" | grep -c . || true)" \
  "every surface count quoted in prose matches the tree ($DCS_AGENTS agents, $DCS_COMMANDS commands, $DCS_SKILLS skills, $DCS_TOTAL total, $DCS_RULES rules, $DCS_TEMPLATES templates)"

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
# applied to them on 2026-08-13, 15 of 27 hooks and 5 of 10 installed scripts left in one commit, of
# which one script (detect-missing-refs.sh) was restored two rounds later, leaving 4 —
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
# Files in the directory INCLUDING _lib.sh. README.md quotes both numbers in one row and derives one
# from the other in prose ("N files on disk — _lib.sh is a shared library, not a hook"), so the row
# was internally consistent and wrong in both halves for a day: 27/28 against a tree of 12/13.
# Falsifying it further, to 999 registered / 777 files, left the whole suite green.
DCK_HOOK_FILES=$(ls -1 "$REPO_DIR"/.claude/hooks/*.sh 2>/dev/null | grep -c . || true)

# How many hooks get the kill switches by sourcing _lib.sh. The complement carries them inline;
# tests/test-hooks.sh asserts that every hook does one or the other, and this is the number three
# shipped documents quote in a sentence that read "All hooks source a shared library" until
# 2026-08-14 — false since the ECU vendor commit, and contradicted by two of those documents' own
# text a hundred lines away.
#
# Matched on the SOURCE STATEMENT, not on the string `_lib.sh`: every one of those documents now
# explains the exception in prose, and `session-brief.sh`'s own header names the library four times
# while sourcing it never.
DCK_LIB_SOURCERS=$(
  while IFS= read -r dck_h; do
    [ -n "$dck_h" ] || continue
    # HERE-STRING, NOT A PIPE. `grep -q` exits the instant it matches without draining stdin, and
    # every hook sources the library on line 6 — so awk is still writing when grep closes the read
    # end, dies of SIGPIPE, and pipefail turns 141 into a failed AND-list. Measured with the pipe
    # form: this returned 10 for a tree where 11 hooks source it, the one miscount landing on
    # whichever file was long enough to still be writing. A silent undercount inside a guard whose
    # job is to catch a wrong count.
    dck_code="$(awk '!/^[[:space:]]*#/' "$REPO_DIR/.claude/hooks/$dck_h")"
    grep -qE 'source[[:space:]]+"?\$\{?SCRIPT_DIR\}?/_lib\.sh"?' <<< "$dck_code" && printf 'x\n'
  done <<< "$DCK_DISK" | grep -c . || true
)

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
  # `|| true` is load-bearing, not decoration. session-brief.sh declares no HOOK_PROFILE_LEVEL, so
  # this grep exits 1; pipefail promotes that through the sed, and at an ASSIGNMENT site `set -e`
  # kills the file. Measured 2026-08-13 with errexit on: it died here having printed its section
  # header and 0 of the 14 hook assertions, and NOTHING WENT RED — the runner does `set +e` before
  # sourcing, so the suite total silently drops by 14 and no guard watches the total. That is the
  # same shape as the pre-compact.sh defect this wave cut a hook for, inside the guard the wave is
  # building. All four sites in this file carry it.
  dck_lvl=$(grep -m1 '^HOOK_PROFILE_LEVEL=' "$REPO_DIR/.claude/hooks/$dck_h" 2>/dev/null \
            | sed 's/^HOOK_PROFILE_LEVEL="\(.*\)".*/\1/' || true)
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
    # `|| true`: see the note at the first of these four sites — a hook that declares no level makes
    # this grep exit 1, and under errexit that kills the file silently.
    dck_l=$(grep -m1 '^HOOK_PROFILE_LEVEL=' "$REPO_DIR/.claude/hooks/$dck_h" 2>/dev/null \
            | sed 's/^HOOK_PROFILE_LEVEL="\(.*\)".*/\1/' || true)
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

# Scripts. install.sh writes `scripts/*.sh` into `.claude/scripts/` minus a short skip list — files
# that measure THIS repository and have nothing to do in an installed project. It was
# check-provenance.sh alone until 2026-08-15, when codex-probe.sh joined it. Both numbers are quoted
# in docs/GETTING-STARTED.md, so both are derived here. The skip list is read out of install.sh
# rather than hardcoded, which is what let the second name land without this derivation silently
# disagreeing — the difference between the two counts is whatever install.sh skips, not a fixed 1.
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

# How many installed scripts are named, by INSTALLED path, from a shipped surface. Same question
# tests/test-shipped-citations.sh rule 3 asks and for the same reason; derived a second time here
# because a NUMBER is quoted in prose and this block is where quoted numbers are held to the tree.
#
# The two derivations are deliberately not identical, and today they agree at 6 anyway: this one
# recurses over ALL of .claude/, the sibling reads only the shipped *.md surfaces. They diverge the
# day a hook or a settings file names a script that no agent, command or skill does — at which point
# this number is the larger of the two and the prose it guards carries the more optimistic reading.
# Stated here rather than discovered later.
DCK_NAMED_SCRIPTS=0
for dck_s in "$REPO_DIR"/scripts/*.sh; do
  [ -f "$dck_s" ] || continue
  dck_b="$(basename "$dck_s")"
  case " $DCK_SKIP_NAMES " in *" $dck_b "*) continue ;; esac
  if grep -rqF -- ".claude/scripts/$dck_b" "$REPO_DIR/.claude"; then
    DCK_NAMED_SCRIPTS=$((DCK_NAMED_SCRIPTS + 1))
  fi
done

# The derivation has to be able to fail, for the same reason the surface-pool block says so: run
# against a tree with no payload, every number above is 0, and 0 == 0 is a green suite that read
# nothing. Asserted before anything is compared against them.
DCK_DERIVATION="ok"
[ "$DCK_HOOKS"         -ge 1 ] || DCK_DERIVATION="no hooks found under \$REPO_DIR/.claude/hooks"
[ "$DCK_REGISTERED"    -ge 1 ] || DCK_DERIVATION="no hook registrations found in \$REPO_DIR/.claude/settings.json"
[ "$DCK_REPO_SCRIPTS"  -ge 1 ] || DCK_DERIVATION="no scripts found under \$REPO_DIR/scripts"
# A floor, not an equality. `-eq 1` was right while exactly one script was skipped and was itself
# the thing that went red when the second one was added correctly — the count of skips is not the
# invariant, the extraction having found any at all is. Zero means the pattern stopped matching and
# every number below is then wrong in the direction that reads as green.
[ "$DCK_SKIPPED"       -ge 1 ] || DCK_DERIVATION="install.sh's script-skip pattern matched nothing — the installed-script derivation is guessing"
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
    # `|| true`: see the note at the first of these four sites — a hook that declares no level makes
    # this grep exit 1, and under errexit that kills the file silently.
    dck_l=$(grep -m1 '^HOOK_PROFILE_LEVEL=' "$REPO_DIR/.claude/hooks/$dck_h" 2>/dev/null \
            | sed 's/^HOOK_PROFILE_LEVEL="\(.*\)".*/\1/' || true)
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
    # `|| true`: see the note at the first of these four sites — a hook that declares no level makes
    # this grep exit 1, and under errexit that kills the file silently.
    dck_l=$(grep -m1 '^HOOK_PROFILE_LEVEL=' "$REPO_DIR/.claude/hooks/$dck_h" 2>/dev/null \
            | sed 's/^HOOK_PROFILE_LEVEL="\(.*\)".*/\1/' || true)
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
#    AND THE ROW MATCH IS PADDING-TOLERANT, which is the difference between a guard and a nuisance.
#    Round 2 of this block required exactly single-space padding — `| bash-gate | PreToolUse |` — so
#    re-spacing one row to `|  bash-gate  |  PreToolUse  |`, which is what a markdown formatter does
#    on save, made this assertion RED ON A SEMANTICALLY CORRECT DOCUMENT. It errs safe and the
#    diagnostic is readable, but that is not the point: a guard that fires when nothing is wrong is
#    disabled by the next person who touches the table, and every assertion behind it goes quiet at
#    once. The row is recognised on structure, and every cell is trimmed before it is compared.
DCK_TABLE_DOC=$(
  awk '
    /^\|[[:space:]]*[a-z0-9-]+[[:space:]]*\|[[:space:]]*(PreToolUse|PostToolUse|PreCompact|SessionStart|Stop)[[:space:]]*\|/ {
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

# 4. docs/ARCHITECTURE.md's Tracking Files table names hooks as the WRITERS of state files.
#
# That is a different fact from profile membership — which is why that file is allowed to state it
# while stating no profile, event or matcher by name — but it is still a hand-written hook fact, and
# it went stale in exactly the predicted way: the 2026-08-13 cut removed four of the writers it named
# and the table had to be hand-edited, with nothing to catch it if that edit had been missed.
#
# Asserted narrowly and on purpose: every hook NAMED there must exist. The converse (every hook that
# writes state appears in the table) is deliberately not asserted — the table documents the state
# files worth knowing about, not every write, so completeness there is an editorial call rather than
# a derivable fact. Saying so, because a check's silence is only as wide as what it read.
DCK_TRACKING_NAMED=$(
  awk '
    /^### Tracking Files/ { intable = 1; next }
    intable && /^###/     { intable = 0 }
    intable && /^\|/ {
        n = split($0, f, "|")
        if (n >= 4) {
            w = f[4]
            gsub(/^[ \t]+|[ \t]+$/, "", w)
            # BACKTICKS OPTIONAL, and that is the whole repair. Requiring them meant a
            # de-backticked writer cell simply left the set this loop builds — measured by Task 10:
            # repoint the session-edits.txt row writer cell at a lowercase, de-backticked,
            # NONEXISTENT hook and
            # both assertions below stayed green. Until 2026-08-14 the session-warnings.txt row read
            # `Various hooks`, which fell out of this set by failing `[a-z0-9-]+\.sh` — so a
            # category word in the writer column was invisible here while three of its members were
            # deleted. It names `bash-gate.sh` now, its one real writer, and is read like the rest.
            if (w ~ /^`?[a-z0-9-]+\.sh`?$/) { gsub(/`/, "", w); print w }
        }
    }
  ' "$REPO_DIR/docs/ARCHITECTURE.md" 2>/dev/null | sort -u
)
assert_eq "yes" "$([ -n "$DCK_TRACKING_NAMED" ] && echo yes || echo no)" \
  "docs/ARCHITECTURE.md still has a readable Tracking Files writer column"

DCK_TRACKING_GONE=""
while IFS= read -r dck_w; do
  [ -n "$dck_w" ] || continue
  if [ ! -f "$REPO_DIR/.claude/hooks/$dck_w" ]; then
    DCK_TRACKING_GONE="${DCK_TRACKING_GONE}${dck_w}"$'\n'
  fi
done <<< "$DCK_TRACKING_NAMED"

if [ -n "$DCK_TRACKING_GONE" ]; then
  # printf '%s', not '%s\n': DCK_TRACKING_GONE is accumulated with a trailing newline per entry, so
  # adding one more prints a blank diagnostic line. The assertion counts with `grep -c .` and was
  # correct either way; the stray line was noise in the failure output, which is the part a reader
  # acts on.
  printf '%s' "$DCK_TRACKING_GONE" | sed 's|^|     ARCHITECTURE.md names this hook as a state-file writer and it does not exist: |'
fi
assert_eq "0" "$(printf '%s' "$DCK_TRACKING_GONE" | grep -c . || true)" \
  "every hook docs/ARCHITECTURE.md names as a state-file writer exists"

# --- The quoted numbers. Same table shape, same flattening, same per-pair floors as above. ---
#
# NOTE ON THE TWO `of the` PATTERNS. `runs N of the M` (the minimal row) and `drops N of the M`
# (the cost paragraph) describe the SAME profile from opposite sides and must stay lexically
# disjoint. Round 1 of this block used a bare `[0-9]+ of the [0-9]+ hooks`, which matched the
# `drops 8 of the 12 hooks` sentence and reported the tree as having 4 where the doc said 8 -- a
# guard failing on a correct document because two of its own patterns overlapped. If either
# sentence is reworded, keep the leading verb.
#
# AND WHY docs/HOOK-REFERENCE.md HAS TWO `drops` ROWS RATHER THAN ONE — ledger 203, fixed here.
#
# That file states the cost of `minimal` in two places: `It drops N of the M hooks, and bash-gate is
# one of them.` under `### What minimal actually costs`, and `which drops N of the M hooks — every
# hook declaring standard` in the `strict` paragraph. ONE row covered both. The value check was
# fine — it runs on every match — but the VACUITY check is `hits < 1`, a union over the two sites:
# either sentence could lose its digits entirely and the row stayed green on its sibling.
#
# MEASURED 2026-08-14, before this split. Reverting the second sentence to its exact pre-fix
# spelled-out wording — "which drops the four warning and session hooks that declare `standard`",
# no digits at all — left this file at **32 pass / 0 fail**. The same edit applied to the first
# sentence instead: **32 pass / 0 fail**. The control, `drops 3 of the 12`: **31 pass / 1 fail**.
# So the digit was genuinely checked and the SENTENCE was not, in both directions — the defect the
# previous wave fixed was reintroducible verbatim without reddening anything.
#
# This is the same finding at a third granularity. 2026-08-03 (finding 8) found it ACROSS FILES: a
# combined threshold let README.md lose its occurrence while CREDITS.md's kept the total up; the
# remedy was to count per file. `DC_PAIR_VACUOUS` above found it ACROSS PHRASINGS within one file
# and gave CREDITS.md's third phrasing its own named check. This is ACROSS SITES within one
# phrasing. Each time the union got smaller and each time it was still a union — which is why the
# rule is now enforced mechanically below rather than applied by hand a fourth time.
#
# The two patterns are lexically disjoint by their leading words (`It drops` / `which drops`), the
# same discipline the `runs`/`drops` note above already requires. Derive the exposure rather than
# trusting this paragraph:
#
#   awk -F'\t' 'NF >= 3 { print $1 "\t" $2 }' tests/test-derived-counts.sh   # then count the
#   matches of each pattern in the flattened file it names; every row must match exactly one site.
#
# NO VALUES IN THIS KEY. It is a reading aid for the table below, and a reading aid that
# transcribes the numbers the table DERIVES is a second, unguarded copy of every one of them --
# which is exactly what it became: two lines read `8`/`6` against a tree of 10/8/8, edited on
# one line and left on the next, correct assertions under a wrong key. `N` and `M` stand for
# the first and second captured numbers; the derivation is in the row.
# docs/ARCHITECTURE.md   "hooks/ N registered shell scripts"          total
# docs/ARCHITECTURE.md   "Of the N registered hooks, N source"       total, _lib.sh sourcers
# README.md              "**Hooks** | N registered"                   total
# README.md              "(N blocking"                                 blocking
# README.md              "N files on disk"                            files incl. _lib.sh
# docs/HOOK-REFERENCE.md "N of the N hooks source a shared library"  sourcers, total (two phrasings)
# docs/ARCHITECTURE.md   "N of the N get them by sourcing"           sourcers, total
# docs/ARCHITECTURE.md   "minimal (N cumulative"                       minimal tier
# docs/ARCHITECTURE.md   "standard (N cumulative)"                    standard tier
# docs/ARCHITECTURE.md   "strict (N cumulative"                       strict tier
# docs/GETTING-STARTED.md "hooks/ N hooks + _lib.sh"                  total
# docs/GETTING-STARTED.md "N of them blocking"                         blocking
# docs/GETTING-STARTED.md "repo has N scripts; an installed project has N" repo, installed
# docs/GETTING-STARTED.md "N of the N installed scripts are named"        named, installed
# docs/HOOK-REFERENCE.md  "includes N hooks"                          total
# docs/HOOK-REFERENCE.md  "standard profile N hooks"                  standard tier
DCK_CLAIMS="docs/ARCHITECTURE.md	hooks/ [0-9]+ registered shell scripts	$DCK_HOOKS	-
docs/ARCHITECTURE.md	Of the [0-9]+ registered hooks, [0-9]+ source	$DCK_HOOKS	$DCK_LIB_SOURCERS
docs/ARCHITECTURE.md	.minimal. \([0-9]+ cumulative	$DCK_MINIMAL	-
docs/ARCHITECTURE.md	.standard. \([0-9]+ cumulative\)	$DCK_STANDARD	-
docs/ARCHITECTURE.md	.strict. \([0-9]+ cumulative	$DCK_STRICT	-
docs/GETTING-STARTED.md	hooks/ [0-9]+ hooks [+] _lib.sh	$DCK_HOOKS	-
docs/GETTING-STARTED.md	[0-9]+ of them blocking	$DCK_BLOCKING	-
docs/GETTING-STARTED.md	repo has [0-9]+ scripts; an installed project has [0-9]+	$DCK_REPO_SCRIPTS	$DCK_INSTALLED_SCRIPTS
docs/GETTING-STARTED.md	[0-9]+ of the [0-9]+ installed scripts are named	$DCK_NAMED_SCRIPTS	$DCK_INSTALLED_SCRIPTS
README.md	\*\*Hooks\*\* [|] [0-9]+ registered	$DCK_HOOKS	-
README.md	\([0-9]+ blocking	$DCK_BLOCKING	-
README.md	[0-9]+ files on disk	$DCK_HOOK_FILES	-
docs/HOOK-REFERENCE.md	[0-9]+ of the [0-9]+ hooks source a shared library	$DCK_LIB_SOURCERS	$DCK_HOOKS
docs/HOOK-REFERENCE.md	[0-9]+ of the [0-9]+ hooks source .\.claude/hooks/_lib\.sh.	$DCK_LIB_SOURCERS	$DCK_HOOKS
docs/ARCHITECTURE.md	[0-9]+ of the [0-9]+ get them by sourcing	$DCK_LIB_SOURCERS	$DCK_HOOKS
docs/HOOK-REFERENCE.md	includes [0-9]+ hooks	$DCK_HOOKS	-
docs/HOOK-REFERENCE.md	runs [0-9]+ of the [0-9]+	$DCK_MINIMAL	$DCK_HOOKS
docs/HOOK-REFERENCE.md	all [0-9]+ hooks run	$DCK_STANDARD	-
docs/HOOK-REFERENCE.md	same [0-9]+ hooks as	$DCK_STRICT	-
docs/HOOK-REFERENCE.md	It drops [0-9]+ of the [0-9]+ hooks, and	$DCK_DROPPED_MINIMAL	$DCK_HOOKS
docs/HOOK-REFERENCE.md	which drops [0-9]+ of the [0-9]+ hooks	$DCK_DROPPED_MINIMAL	$DCK_HOOKS
docs/ARCHITECTURE.md	drops [0-9]+ of the [0-9]+	$DCK_DROPPED_MINIMAL	$DCK_HOOKS
.claude/settings.local.json.template	drops [0-9]+ of the [0-9]+	$DCK_DROPPED_MINIMAL	$DCK_HOOKS"

DCK_BAD=""
DCK_VACUOUS=""
DCK_MULTISITE=""
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
      # NOT `"$([ … ] && printf …)"`. For the claim rows whose second column is `-` that AND-list
      # short-circuits, the command substitution exits 1, and an assignment site is one of the two
      # places `set -e` reaches that people expect it not to. Inert under the runner (which does
      # `set +e` before sourcing this runner-provided file) and reachable only on the failure path —
      # both harness accidents, not a design.
      dck_extra=""
      [ "$dck_want2" = "-" ] || dck_extra=" and $dck_want2"
      DCK_BAD="${DCK_BAD}${dck_rel} claims '${dck_claim}' — the tree has ${dck_want1}${dck_extra}"$'\n'
    fi
  done <<< "$(grep -oE "$dck_pat" <<< "$dck_flat" || true)"

  if [ "$dck_hits" -lt 1 ]; then
    DCK_VACUOUS="${DCK_VACUOUS}${dck_rel} no longer states its '${dck_pat}' claim in a form this guard can read"$'\n'
  elif [ "$dck_hits" -gt 1 ]; then
    # LEDGER 203 AS A CLASS, not as an instance. A row matching N sites has a vacuity check that is
    # a union over them: N-1 of them can be reworded out of reach and the row stays green on the
    # last one. Splitting the one row that violated it fixes today; this fails the NEXT one, which
    # is the difference between a fix and a rule. Measured 2026-08-14 across all 43 claim rows in
    # this file: 42 matched exactly one site, one matched two.
    DCK_MULTISITE="${DCK_MULTISITE}${dck_rel}'s '${dck_pat}' row matches ${dck_hits} sites — its vacuity check is a union over them, so any ${dck_hits}-1 of them can be reworded out of reach unnoticed. Split it into one row per site, with lexically disjoint patterns."$'\n'
  fi
done <<< "$DCK_CLAIMS"

if [ -n "$DCK_MULTISITE" ]; then
  printf '%s' "$DCK_MULTISITE"
fi
assert_eq "0" "$(printf '%s' "$DCK_MULTISITE" | grep -c . || true)" \
  "every hook-count claim row matches exactly one site, so no row's vacuity check is a union over sites"

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

# ============================================================================
# THE FOUR PROSE CLAIMS ABOUT NAMED HOOKS THAT NO GUARD READ.
#
# `docs/ARCHITECTURE.md` states, outside every count and every table this file already reads: which
# events have registrations, which state-file paths `_lib.sh` still defines, which of them
# `session-restore.sh` clears, and how the session TTL is configured. All four were TRUE and all four
# were proved SILENT when falsified — the file states no profile, event or matcher per hook, so the
# narrowed sentence that licenses it holds, and these fall outside it in a direction nothing covered.
#
# The ruling taken here is guard, not delete. Deleting them would leave the only written account of
# why `_lib.sh` still carries paths for hooks that no longer exist.
#
# WHAT THIS BLOCK CANNOT SEE: it reads NAMES, not behaviour. `session-restore.sh` naming
# `UNITY_COST_FILE` in an `rm -f` is not proof the file is removed, and a rename that changes both
# the hook and this document together passes. It closes the direction that actually failed — a
# document naming a hook, an event or a variable the tree no longer has.
echo "--- derived counts: hook facts stated as prose ---"

# 1. The Event Types table is the set of events with registrations, in both directions.
#    `PreCompact` had a row here for a day after its last registration was cut, twelve lines above a
#    paragraph saying there was none. Adjacent, not contradictory, and invisible to every guard.
DCE_EVENTS_REG=$(printf '%s\n' "$DCK_REG_TRIPLES" | awk -F'\t' '{ print $2 }' | sort -u | grep -v '^$' || true)
DCE_EVENTS_DOC=$(
  awk '
    /^### Event Types/ { intable = 1; next }
    intable && /^###/  { intable = 0 }
    intable && /^\|[[:space:]]*[A-Za-z]+[[:space:]]*\|/ {
        split($0, f, "|"); e = f[2]
        gsub(/^[ \t]+|[ \t]+$/, "", e)
        if (e != "Event" && e !~ /^-+$/) { print e }
    }
  ' "$REPO_DIR/docs/ARCHITECTURE.md" 2>/dev/null | sort -u
)
assert_eq "yes" "$([ -n "$DCE_EVENTS_DOC" ] && echo yes || echo no)" \
  "docs/ARCHITECTURE.md still has a readable Event Types table"
assert_eq "$DCE_EVENTS_REG" "$DCE_EVENTS_DOC" \
  "the Event Types table is exactly the events .claude/settings.json registers"

# 2. The two negatives that table's neighbouring paragraph asserts, derived rather than trusted.
DCE_NEG=""
printf '%s\n' "$DCE_EVENTS_REG" | grep -qxF 'PreCompact' && DCE_NEG="${DCE_NEG}a PreCompact registration exists; docs/ARCHITECTURE.md says none is left"$'\n'
printf '%s\n' "$DCK_REG_TRIPLES" | awk -F'\t' '$2 == "PostToolUse" && $3 == "Bash"' | grep -q . && DCE_NEG="${DCE_NEG}a PostToolUse-on-Bash registration exists; docs/ARCHITECTURE.md says none is left"$'\n'
if [ -n "$DCE_NEG" ]; then printf '%s' "$DCE_NEG"; fi
assert_eq "0" "$(printf '%s' "$DCE_NEG" | grep -c . || true)" \
  "no PreCompact and no PostToolUse-on-Bash registration, as docs/ARCHITECTURE.md states"

# 3. The state-file paths ARCHITECTURE.md says _lib.sh still defines for removed hooks, and the three
#    session-restore.sh still clears. Read as names, from the files, in the direction that failed.
DCE_ORPHAN_PATHS="gateguard-reads.txt
session-cost.jsonl
learnings.jsonl
notify-event.json"
DCE_MISSING=""
while IFS= read -r dce_f; do
  [ -n "$dce_f" ] || continue
  grep -qF -- "$dce_f" "$REPO_DIR/.claude/hooks/_lib.sh" \
    || DCE_MISSING="${DCE_MISSING}_lib.sh no longer defines a path for $dce_f, and docs/ARCHITECTURE.md says it does"$'\n'
done <<< "$DCE_ORPHAN_PATHS"
for dce_v in UNITY_READS_FILE UNITY_COST_FILE UNITY_LEARNING_FILE; do
  grep -qF -- "$dce_v" "$REPO_DIR/.claude/hooks/session-restore.sh" \
    || DCE_MISSING="${DCE_MISSING}session-restore.sh no longer names $dce_v, and docs/ARCHITECTURE.md says it clears it"$'\n'
done
for dce_v in UNITY_SESSION_TTL_HOURS saved_at; do
  grep -qF -- "$dce_v" "$REPO_DIR/.claude/hooks/session-restore.sh" \
    || DCE_MISSING="${DCE_MISSING}session-restore.sh no longer names $dce_v, and docs/ARCHITECTURE.md's Session TTL section says it does"$'\n'
done
if [ -n "$DCE_MISSING" ]; then printf '%s' "$DCE_MISSING"; fi
assert_eq "0" "$(printf '%s' "$DCE_MISSING" | grep -c . || true)" \
  "every hook variable and state path docs/ARCHITECTURE.md names in prose is still in the tree"

# ============================================================================
# docs/ANTI-VACUITY.md's bash-4 census — the one LIVE figure in a document otherwise made of pinned
# past measurements, and the number this repository has now watched rot three times.
#
#   `40` / `62`                 until 2026-08-15
#   `13 + 7 + 42 + 1 + 1 = 64`  until 2026-08-16
#
# Both were found by a completion sweep, in no diff, by nobody's review — which is the whole reason
# a guard replaces the warning. Shape 1 of that document is worked on `tests/test-bash32-compat.sh`'s
# five sources, so the census is a property of the tree and moves whenever a `.sh` file is added to
# `.claude/hooks/`, `scripts/` or `tests/`. Three tasks of the 2026-08-15 Codex wave each added one,
# which is why the figure written at the start of that wave was wrong by construction before it ended.
#
# TWO TRAPS, both of which produced an earlier mis-statement and both of which this block encodes
# rather than restates:
#
#   * `tests/*.sh` is NOT `tests/test-*.sh`. It counts `run-tests.sh`, so the tests figure is one
#     ABOVE the suite's file count. Reading the wrong glob is how the number went wrong before.
#   * The early-exit-reader scope is a DIFFERENT union — `.claude/hooks`, `scripts`, `install.sh`,
#     `uninstall.sh`, without `tests` — and the document quotes both totals in one sentence.
#
# The derivation below is the same one `tests/test-bash32-compat.sh` performs on itself; this block
# is deliberately NOT a comparison against that file's output, because sourcing it here would make
# both sides move together — F4 in the document being guarded. Two independent derivations of one
# quantity is the shape, and the second derivation is the sentence a human wrote.
echo "--- derived counts: the bash-4 census in docs/ANTI-VACUITY.md ---"

DCV_DOC="docs/ANTI-VACUITY.md"
DCV_HOOKS=$(ls -1 "$REPO_DIR"/.claude/hooks/*.sh 2>/dev/null | grep -c . || true)
DCV_SCRIPTS=$(ls -1 "$REPO_DIR"/scripts/*.sh 2>/dev/null | grep -c . || true)
DCV_TESTS=$(ls -1 "$REPO_DIR"/tests/*.sh 2>/dev/null | grep -c . || true)
DCV_TOTAL=$((DCV_HOOKS + DCV_SCRIPTS + DCV_TESTS + 2))
DCV_PIPE=$((DCV_HOOKS + DCV_SCRIPTS + 2))

# The derivation has to be able to fail, for the same reason the surface-pool block above says so:
# run against a tree whose payload has moved and every count is 0, and 0 compared with 0 is a green
# suite that inspected nothing. Asserted before anything is compared against it.
DCV_DERIVATION="ok"
[ "$DCV_HOOKS"   -ge 1 ] || DCV_DERIVATION="no .sh files under \$REPO_DIR/.claude/hooks"
[ "$DCV_SCRIPTS" -ge 1 ] || DCV_DERIVATION="no .sh files under \$REPO_DIR/scripts"
[ "$DCV_TESTS"   -ge 1 ] || DCV_DERIVATION="no .sh files under \$REPO_DIR/tests"
[ -f "$REPO_DIR/install.sh" ]   || DCV_DERIVATION="install.sh is not at the repository root, so the census's fourth source is not 1"
[ -f "$REPO_DIR/uninstall.sh" ] || DCV_DERIVATION="uninstall.sh is not at the repository root, so the census's fifth source is not 1"
assert_eq "ok" "$DCV_DERIVATION" \
  "the bash-4 census is derived from a tree that actually has shell scripts in it"

# Every site in the document that carries a number from that census, each with its own pattern, and
# each pattern matching exactly one site. Fields: relative path, extended-regex pattern, then the
# expected 1st, 2nd and 3rd number in the match (`-` where the match carries fewer).
#
# MATCHED AGAINST THE FILE FLATTENED — the sum sentence wraps mid-expression and the quoted census
# wraps between `SHIPPED:scripts=` and the rest, so a line-oriented reader sees neither. That is the
# same wrap that hid these numbers from three readers.
DCV_CLAIMS="$DCV_DOC	[0-9]+ [+] [0-9]+ [+] [0-9]+ [+] 1 [+] 1 = [0-9]+	$DCV_HOOKS	$DCV_SCRIPTS	$DCV_TESTS
$DCV_DOC	SHIPPED:[.]claude/hooks=[0-9]+ SHIPPED:scripts=[0-9]+ SHIPPED:tests=[0-9]+	$DCV_HOOKS	$DCV_SCRIPTS	$DCV_TESTS
$DCV_DOC	\([0-9]+ shipped, [0-9]+ in the early-exit-reader scope\)	$DCV_TOTAL	$DCV_PIPE	-
$DCV_DOC	.tests. \([0-9]+\) [|] [0-9]+ [|] [0-9]+	$DCV_TESTS	$((DCV_TOTAL - DCV_TESTS))	$((DCV_TOTAL - DCV_TESTS + 1))
$DCV_DOC	.[.]claude/hooks. \([0-9]+\) [|] [0-9]+ [|] [0-9]+	$DCV_HOOKS	$((DCV_TOTAL - DCV_HOOKS))	$((DCV_TOTAL - DCV_HOOKS + 1))
$DCV_DOC	.scripts. \([0-9]+\) [|] [0-9]+ [|] [0-9]+	$DCV_SCRIPTS	$((DCV_TOTAL - DCV_SCRIPTS))	$((DCV_TOTAL - DCV_SCRIPTS + 1))
$DCV_DOC	uninstall[.]sh. \([0-9]+\) [|] [0-9]+ [|] [0-9]+	1	$((DCV_TOTAL - 1))	$DCV_TOTAL"

# The sum sentence states the total too. It is checked separately rather than as a fourth field,
# because the pattern above already spends its three fields on the three moving sources and a reader
# fixing a red needs to be told which half disagrees.
DCV_SUM_WANT="$DCV_HOOKS + $DCV_SCRIPTS + $DCV_TESTS + 1 + 1 = $DCV_TOTAL"

DCV_BAD=""
DCV_VACUOUS=""
DCV_MULTISITE=""
while IFS=$'\t' read -r dcv_rel dcv_pat dcv_w1 dcv_w2 dcv_w3; do
  [ -n "$dcv_rel" ] || continue
  if [ ! -f "$REPO_DIR/$dcv_rel" ]; then
    DCV_VACUOUS="${DCV_VACUOUS}${dcv_rel} is not present, so its '${dcv_pat}' claim was never checked"$'\n'
    continue
  fi
  # tr drains its input; neither reader here can exit early.
  dcv_flat="$(tr '\n' ' ' < "$REPO_DIR/$dcv_rel" | tr -s ' ')"
  dcv_hits=0
  while IFS= read -r dcv_claim; do
    [ -n "$dcv_claim" ] || continue
    dcv_hits=$((dcv_hits + 1))
    dcv_g1=$(printf '%s' "$dcv_claim" | grep -oE '[0-9]+' | sed -n 1p)
    dcv_g2=$(printf '%s' "$dcv_claim" | grep -oE '[0-9]+' | sed -n 2p)
    dcv_g3=$(printf '%s' "$dcv_claim" | grep -oE '[0-9]+' | sed -n 3p)
    if [ "$dcv_g1" != "$dcv_w1" ] \
      || { [ "$dcv_w2" != "-" ] && [ "$dcv_g2" != "$dcv_w2" ]; } \
      || { [ "$dcv_w3" != "-" ] && [ "$dcv_g3" != "$dcv_w3" ]; }; then
      DCV_BAD="${DCV_BAD}${dcv_rel} states '${dcv_claim}' — the tree derives ${dcv_w1}/${dcv_w2}/${dcv_w3}"$'\n'
    fi
  done <<< "$(grep -oE "$dcv_pat" <<< "$dcv_flat" || true)"

  if [ "$dcv_hits" -lt 1 ]; then
    DCV_VACUOUS="${DCV_VACUOUS}${dcv_rel} no longer states its '${dcv_pat}' claim in a form this guard can read"$'\n'
  elif [ "$dcv_hits" -gt 1 ]; then
    DCV_MULTISITE="${DCV_MULTISITE}${dcv_rel}'s '${dcv_pat}' row matches ${dcv_hits} sites — its vacuity check is a union over them. Split it into one row per site, with lexically disjoint patterns."$'\n'
  fi
done <<< "$DCV_CLAIMS"

if [ -n "$DCV_MULTISITE" ]; then
  printf '%s' "$DCV_MULTISITE"
fi
assert_eq "0" "$(printf '%s' "$DCV_MULTISITE" | grep -c . || true)" \
  "every bash-4 census claim row matches exactly one site in $DCV_DOC"

if [ -n "$DCV_BAD" ]; then
  printf '%s' "$DCV_BAD"
  printf '     %s\n' "Re-derive with: printf '%s + %s + %s + 1 + 1 = %s\\n' \"\$(ls .claude/hooks/*.sh | wc -l)\" \"\$(ls scripts/*.sh | wc -l)\" \"\$(ls tests/*.sh | wc -l)\" \"\$(( \$(ls .claude/hooks/*.sh | wc -l) + \$(ls scripts/*.sh | wc -l) + \$(ls tests/*.sh | wc -l) + 2 ))\""
  printf '     %s\n' "tests/*.sh is NOT tests/test-*.sh — it counts run-tests.sh. Do not 'fix' this by editing a pinned historical figure elsewhere in that document."
fi
assert_eq "0" "$(printf '%s' "$DCV_BAD" | grep -c . || true)" \
  "every bash-4 census number in $DCV_DOC matches the tree ($DCV_SUM_WANT, $DCV_PIPE in the early-exit-reader scope)"

if [ -n "$DCV_VACUOUS" ]; then
  printf '%s' "$DCV_VACUOUS"
fi
assert_eq "0" "$(printf '%s' "$DCV_VACUOUS" | grep -c . || true)" \
  "every bash-4 census phrasing this guard covers is still present in $DCV_DOC"

# The sum sentence, as one string rather than as three separate numbers. A document that kept the
# five sources right and mis-added them would satisfy every row above.
DCV_SUM_SEEN=$(tr '\n' ' ' < "$REPO_DIR/$DCV_DOC" | tr -s ' ' | grep -oE '[0-9]+ [+] [0-9]+ [+] [0-9]+ [+] 1 [+] 1 = [0-9]+' | sed -n 1p || true)
assert_eq "$DCV_SUM_WANT" "$DCV_SUM_SEEN" \
  "$DCV_DOC's bash-4 census sums its own five sources correctly"

# ============================================================================
# TREE-SIZE FIGURES, AND THE EDGE OF THIS FILE'S OWN SCANNED SET
#
# THE BOUNDARY THIS BLOCK EXTENDS IS **DERIVED BELOW, NOT LISTED HERE**, and that is a correction
# rather than a style choice. The first version of this header enumerated the paths the blocks above
# check — *"README.md, CLAUDE.md, MERGE-NOTES.md, CREDITS.md, .claude/NOTICE.md, two SKILL.md files
# and four under docs/. Twelve paths, all `.md`."* Re-review found it wrong four ways in one
# sentence: `CLAUDE.md` is excluded by this file's own line 385 (*"CLAUDE.md is deliberately NOT in
# the table below"*), `.claude/NOTICE.md` appears in no claim row at all, the enumeration sums to
# eleven while the sentence says twelve, and `DCE_QUOTING_FILES` — 940 lines above — already checks a
# (That first clause has since inverted: `CLAUDE.md` was brought INTO the surface-pool table on
# 2026-08-17, because the ground it was excluded on turned out to be false about it. The re-review's
# point stands unchanged — the census was wrong four ways — and this parenthesis is here so a reader
# checking the clause against today's tree does not read the correction as a fifth error.)
# numeral in `provenance.tsv` and in **this very file**, neither of them `.md`. A hand-written census
# of a scanned set, written by the same commit as the widening it describes, inside the block whose
# entire subject is figures that go stale unwatched. It is replaced by `DCT_ABOVE`, which reads the
# region above this block out of this file and is therefore incapable of the same rot.
#
# The finding the block exists for is unchanged: the whole-branch review of 2026-08-16 found that
# **every numeral defect on the branch sat outside the set whose numerals are checked** — and that
# the figures inside it were all correct. The guard was not weak; its EDGE was where the defects
# lived. Four of them were tree-size figures the branch's own file
# additions falsified, and the attribution is exact: 3 files added to `scripts/`, 7 to `docs/`,
# 3 to `tests/`, and each stale number off by precisely that.
#
# | site | stated | derived |
# |---|---|---|
# | docs/ANTI-VACUITY.md — five roots summing to N (`docs` D, `scripts` S) | 273 / 189 / 8 | 283 / 196 / 11 |
# | docs/ANTI-VACUITY.md — `tests/` holds N `.sh` files                    | 42            | 45            |
# | tests/test-provenance-origins.sh — `scripts/` holds N now              | 8             | 11            |
# | tests/test-no-mobile.sh — `docs/` holds N tracked today                | 189           | 196           |
#
# THREE OF THE FOUR SITES TELL THE READER TO DERIVE IT, IN THE SAME SENTENCE, and one of them —
# test-provenance-origins.sh — is a paragraph *about* that very figure having gone stale once
# before, ending "Derive both, never transcribe". It went stale again by the same mechanism, one
# wave later. That is the argument for this block: an instruction to derive is executed by nobody,
# and the repository has now watched the same request fail on the same number twice.
#
# THIS BLOCK SCANS SHELL SOURCES AND `install.sh`. Two consequences:
#
#   * The flattener strips a leading `#` per line before joining, because most of these figures
#     live in shell COMMENT BLOCKS wrapped across lines. Without that, a sentence spanning two
#     comment lines reads as `… holds 11 # now …` and no pattern matches it. `awk` drains its
#     input and `tr` drains its input, so nothing here can SIGPIPE a writer under pipefail.
#   * `scripts/` appears here under TWO different derivations and both are live: `git ls-files
#     'scripts/*'` is 11 (all tracked files) and `ls scripts/*.sh` is 10. The bash-4 census block
#     above uses the second. One directory, two correct numbers, and reading the wrong glob is how
#     one of them went wrong before — which is why each row below names the derivation it wants.
#
# WHAT THIS DOES NOT COVER, STATED AS A RESIDUAL RATHER THAN LEFT TO BE DISCOVERED — and stated
# PRECISELY, because the first version of this paragraph said `docs/research/codex-client/*` was out
# of scope on the ground that its figures are "**overwhelmingly** per-run measurements … so they are
# pinned history and must not be re-derived". *Overwhelmingly* was doing load-bearing work it could
# not do: it is true of most of that directory and false of some, and under it hid a SECOND,
# UNGUARDED COPY of the very command-body line count this block guards in `install.sh`. A hedge
# adverb is not a scope
# statement. So:
#
#   * THE RULE IS NOW WRITTEN, 2026-08-17, and it lives with its subject:
#     `docs/research/codex-client/README.md` § *Live and pinned*. Three clauses — **L1** the figure
#     is computable from this repository's tracked files alone, **L2** the sentence asserts it of the
#     present tree (a probe name, a `<replica>`, `codex-cli 0.145.0` or *"measured <date>"* pins it;
#     *"re-derived <date>"* does not), **L3** writing a re-derived value in would leave the
#     surrounding sentence true. Every figure it selected is a sentence that already tells the
#     reader to derive rather than trust it; the rows are split between `DCT_CLAIMS` below and
#     `DCW_CLAIMS` at the foot of this file, by alphabet rather than by subject. **The size of the
#     selection is not written here.** Derive it — the criterion document carries the same command:
#
#       awk '/^DC[TW]_CLAIMS="/{f=1} f{print} f&&/"$/{f=0}' tests/test-derived-counts.sh \
#         | cut -f1 | grep '^docs/research/codex-client/' | sort | uniq -c
#
#     The first version of this bullet did write it — *"eleven distinct figures across fourteen
#     rows"* — and it was an unguarded live figure describing the guard, wrong within a day, in the
#     block whose subject is unguarded live figures. It also said the hook total appears at TWO
#     sites in `codex-facts.md`; it appears at three, and the third is in a different section, which
#     is how a per-section reading produced a whole-file claim.
#   * What remains uncovered there is the per-run measurement class — figures counted against probe
#     transcripts that are gitignored, which cannot be re-derived from this tree at all and must not
#     be edited to match it. That is now an EXCLUSION UNDER A WRITTEN CRITERION rather than a hedge,
#     and the criterion's own worked traps (a run measurement whose value coincides with a tree
#     count; a `0 == 0` row that would need a floor of its own) are listed beside it.
#   * `docs/ANTI-VACUITY.md`'s `## The floor set` Today column needs the same rule and **still has
#     no owner** — that document rules it must be re-derived whole from one gating suite log, and
#     nothing has scheduled that pass. Named here as well as there, because a residual recorded only
#     in the document it afflicts is recorded where the reader already trusts the document.
#   * It does not cover every numeral in the shell files it reads — only the rows named below.
#
# The four figures it covers in `docs/ANTI-VACUITY.md` are in that file's `### Shape 1`
# worked-example bullets — the two beginning "`tests/test-no-mobile.sh` — `SCAN_FILES >= 1`" and
# "`tests/test-bash32-compat.sh` — `SS_ALL_N > 0`" — and NOT in `### Shape 2`. Both this comment and
# the document's own paragraph said Shape 2 for one commit.
#
# CITED BY CONSTRUCT, NOT BY LINE, AND THE FIRST VERSION OF THIS SENTENCE PROVED WHY IN ONE COMMIT.
# It read "Shape 1 spans lines 111-219 and the figures are at 193-207, while Shape 2 begins at 220".
# All three were true when written and all three were falsified by the SAME COMMIT, which added seven
# lines to that document above them — so the sentence immediately before "which is the reason to
# derive it once and write it down" was itself a transcription that its own change invalidated.
# `docs/ARCHITECTURE.md` already carries the rule as *"cite by anchor, not by distance"*, and nothing
# mechanical catches this: `tests/test-citations-resolve.sh` reads `path:line` citations and these
# carried no path prefix. Anchors do not move when a paragraph above them grows.
echo "--- derived counts: tree-size figures outside the .md documents ---"

DCT_CLAIM_ROOT=$(git -C "$REPO_DIR" ls-files .claude 2>/dev/null | grep -c . || true)
DCT_DOCS=$(git -C "$REPO_DIR" ls-files docs 2>/dev/null | grep -c . || true)
DCT_SCRIPTS=$(git -C "$REPO_DIR" ls-files 'scripts/*' 2>/dev/null | grep -c . || true)
DCT_EXAMPLES=$(git -C "$REPO_DIR" ls-files examples 2>/dev/null | grep -c . || true)
DCT_TEMPLATES=$(git -C "$REPO_DIR" ls-files templates 2>/dev/null | grep -c . || true)
DCT_ROOTS=$((DCT_CLAIM_ROOT + DCT_DOCS + DCT_SCRIPTS + DCT_EXAMPLES + DCT_TEMPLATES))
DCT_TESTS_SH=$(ls -1 "$REPO_DIR"/tests/*.sh 2>/dev/null | grep -c . || true)
# `wc -l`, NOT `grep -c ''`, AND THE REASON IS THAT THE FAILURE MESSAGE BELOW TELLS THE READER TO
# RE-DERIVE WITH `wc -l`. The two agree today only because every `.claude/commands/*.md` ends
# in a newline; one file without a trailing newline and `grep -c ''` counts the final partial line
# while `wc -l` does not, so the guard and its own printed remedy would disagree about the number
# and the reader following the remedy would "fix" a correct figure. A guard whose repair instruction
# computes a different quantity than the guard is a trap with a green suite in front of it.
# `|| true`, AND IT IS THE STRUCTURAL TWIN OF `DCW_AGENTS_LINES` AT THE FOOT OF THIS FILE. Both take
# a fallible substitution and back it with `[ -n "$V" ] || V=0` on the next line — which handles the
# empty STRING and not the non-zero EXIT STATUS, so the backstop reads as safety and is not. An
# unmatched glob makes `cat` exit 1 and `pipefail` carries it to the assignment. Inert here (errexit
# is off in this file) and live in any file that sets `-euo pipefail`.
#
# It was missed by the pass that fixed the other three because that pass **enumerated the block, not
# the shape**. Re-derived by shape 2026-08-17 — every `[ "$VAR" -op N ] || SENTINEL=` floor in the
# tracked tree, each floor's variable resolved to its assignment **and one level of dataflow past
# it** — the class is five, all in this file: this one, `DCK_DISK`, `DCK_REG`, `DCK_SKIP_NAMES` and
# `DCT_SKIPPED_NAMES`. `DCK_REG`'s omission is deliberate and says so at its own site; the other
# three are unexamined and are named here rather than swept in silently.
DCT_CMD_LINES=$(cat "$REPO_DIR"/.claude/commands/*.md 2>/dev/null | wc -l | tr -d ' ' || true)
[ -n "$DCT_CMD_LINES" ] || DCT_CMD_LINES=0
DCT_SKILL_DIRS=$(find "$REPO_DIR/.claude/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -c . || true)
DCT_PIPE_SWEEP=$(git -C "$REPO_DIR" ls-files -- .claude/ scripts/ install.sh uninstall.sh 2>/dev/null | grep -c . || true)
# A TRANSCRIBED COPY OF THE PATHSPEC `tests/test-mcp-naming.sh` SWEEPS — and transcribed is the
# operative word. This comment claimed the two "cannot drift into deriving two different sets"
# because the pathspec is reproduced character for character; a mutation refuted it in one edit.
# Deleting `'docs/*'` from that file's real `git ls-files` call leaves BOTH files fully green while
# it sweeps 79 paths and no `docs/` at all: the guard holds its own copy, so the copies drift
# independently and the numeral check goes on comparing this copy's answer with the prose beside the
# other. What is actually guarded is the NUMBER IN THE COMMENT, which is what the class of defects
# this block exists for is made of; the pathspec's own correctness is guarded by that file's floor
# and by nothing here. Keeping the copy is still right — deriving it by parsing the other file's
# source would couple two things that must be able to disagree — but the reason has to be stated at
# the size it actually has. Its `docs/*` element excludes research/ and superpowers/, which is why a
# bare `git ls-files docs` is the wrong number here.
DCT_MCPN_CLAUDE=$(git -C "$REPO_DIR" ls-files '.claude/*' 2>/dev/null | grep -c . || true)
DCT_MCPN_DOCS=$(git -C "$REPO_DIR" ls-files 'docs/*' ':!docs/research/*' ':!docs/superpowers/*' 2>/dev/null | grep -c . || true)
DCT_MCPN_TOTAL=$(git -C "$REPO_DIR" ls-files '.claude/*' 'scripts/*' 'docs/*' install.sh uninstall.sh \
                   CLAUDE.md CONTRIBUTING.md README.md MCP-SETUP.md \
                   ':!docs/research/*' ':!docs/superpowers/*' 2>/dev/null | grep -c . || true)
# `tests/test-shipped-citations.sh`'s payload, by its own `payload_paths()` rule: everything tracked
# under `.claude/` except `state/`, plus `scripts/*.sh` less the names install.sh skips. The skip
# list is READ OUT OF install.sh rather than written here, for the same reason the hooks block above
# reads it — it changed twice on this branch, and a transcribed copy of it is what made the figure
# this guards go stale in the first place.
DCT_SKIPPED_NAMES=$(grep -oE '\[ "\$b" = "[^"]+" \] && continue' "$REPO_DIR/install.sh" 2>/dev/null \
                    | sed 's/.*= "//; s/" \].*//' | sort -u)
DCT_PAY_CLAUDE=$(git -C "$REPO_DIR" ls-files '.claude/*' 2>/dev/null | grep -cv '^\.claude/state/' || true)
DCT_PAY_SCRIPTS=0
for dct_s in "$REPO_DIR"/scripts/*.sh; do
  [ -f "$dct_s" ] || continue
  dct_b=$(basename "$dct_s")
  if grep -qxF -- "$dct_b" <<< "$DCT_SKIPPED_NAMES"; then continue; fi
  DCT_PAY_SCRIPTS=$((DCT_PAY_SCRIPTS + 1))
done
DCT_PAY_TOTAL=$((DCT_PAY_CLAUDE + DCT_PAY_SCRIPTS))
DCT_PAY_MD=$(git -C "$REPO_DIR" ls-files '.claude/*' 2>/dev/null | grep -v '^\.claude/state/' | grep -c '\.md$' || true)
DCT_PAY_NONMD=$((DCT_PAY_TOTAL - DCT_PAY_MD))
# `tests/test-bash32-compat.sh` QUOTES ITS OWN RUNTIME CENSUS in prose, and those two numbers are
# live. They are the same two `docs/ANTI-VACUITY.md` quotes and the DCV block above guards — but
# that block's rows are keyed to `docs/ANTI-VACUITY.md`, so the second copy is covered by nothing.
#
# `DCT_HOOKS_SH` SAT HERE UNTIL 2026-08-17 AND WAS READ BY NO ROW. It was derived, floor-checked,
# and never compared against anything: a floor whose subject nothing consumes bounds a set no
# assertion depends on, which is a third kind of vacuity and the one hardest to see, because the
# floor itself is green and correct. The hooks half of that census is guarded — by `DCV_HOOKS`, in
# the block above, keyed to `docs/ANTI-VACUITY.md`, which is the file that quotes it. Deleted rather
# than given a row, because the row would have duplicated a live guard instead of closing a gap.
DCT_SCRIPTS_SH=$(ls -1 "$REPO_DIR"/scripts/*.sh 2>/dev/null | grep -c . || true)

# THE STRANDED-MACHINERY FIGURES IN `findings.md`, selected by that directory's live-vs-pinned
# criterion (`docs/research/codex-client/README.md` § *Live and pinned*). Each is stated twice
# there — once as a shell command with its answer in a trailing comment, once in the table beside
# it — and each states it of THIS tree, in the present tense, with the command that re-derives it.
#
# `codex-facts.md` states the hook total twice, and each time it partitions it — 4 `PostToolUse`,
# and the remaining 3 that are not tool events. All three numerals are live, so all three are
# derived here rather than only the total: guarding the total and leaving the partition unguarded
# is how a row comes to be internally inconsistent and green, which this file has recorded twice.
# `DCK_REG_TRIPLES` is `hook<TAB>event<TAB>matcher`, derived from `settings.json` in the DCK block
# above; `sort -u` on the hook name so a doubly-registered hook counts once.
DCT_CF_POST=$(printf '%s\n' "$DCK_REG_TRIPLES" | awk -F'\t' '$2 == "PostToolUse" { print $1 }' | sort -u | grep -c . || true)
DCT_CF_NONTOOL=$(printf '%s\n' "$DCK_REG_TRIPLES" | awk -F'\t' '$2 != "PreToolUse" && $2 != "PostToolUse" && $1 != "" { print $1 }' | sort -u | grep -c . || true)
DCT_CATALOG=$(git -C "$REPO_DIR" ls-files 'src/catalog/*' 2>/dev/null | grep -c . || true)
DCT_KBUILD_PY=$(git -C "$REPO_DIR" ls-files 'tools/kinglet_build/*.py' 2>/dev/null | grep -c . || true)
DCT_ADAPTERS=$(git -C "$REPO_DIR" ls-files 'adapters/*/profile.json' 2>/dev/null | grep -c . || true)

# THE SELF-CONTAINED TEST FILES — the blast radius two documents now quote, derived here so the
# quote moves with the tree. A test file is self-contained iff it executes a `set` enabling errexit
# at its own top level; the runner does `set +e` before sourcing, so this partition decides which
# files a `$(…)`-in-a-failure-message or an unguarded fallible substitution can kill outright.
# The figure entered the tree on 2026-08-17 as prose and nothing could reach it: mutated by two at
# every site, `test-derived-counts.sh`, `test-shipped-citations.sh`, `test-citations-resolve.sh`,
# `test-mcp-citations.sh` and `check-provenance.sh` all stayed green. No numeral is written into
# this comment, per the standing rule stated at `DCT_DECLARED`'s open residual (cited by construct,
# not by distance): no live figure in this file's prose.
#
# NO DCT_DERIVATION FLOOR, AND THAT IS DELIBERATE RATHER THAN AN OMISSION — the same standing
# as `DCT_ROOTS` and `DCT_MCPN_CLAUDE`, which are also read by rows and floored by none. A floor
# guards a derivation whose emptiness would let an assertion pass; this one's emptiness cannot,
# because the claim rows below compare it against a written numeral, so a derivation that collapsed
# to zero reds by name against the document. Adding a floor would also silently move the per-source
# count this block publishes into `docs/ANTI-VACUITY.md`'s floor-set row — which is the figure the
# round that wrote this comment was dispatched to correct, having gone stale exactly this way.
#
# THE SENTENCE ABOVE IS SPELLED WITHOUT THE FLOOR'S OWN SYNTAX ON PURPOSE. The block publishes its
# per-source count as `grep -cE '\|\| DCT_DERIVATION='` over this file, so a comment that writes the
# floor literally IS a source as far as that command can tell. The first draft of this paragraph did
# exactly that and moved the published count by one — a numeral falsified by the prose explaining why
# it should not be falsified, inside the round dispatched to correct that same numeral. Caught by
# re-deriving after the edit rather than before it.
#
# `awk` reads each file directly and `grep -c` drains its input, so nothing here can exit early on a
# writer. Long-form `set -o errexit` is matched too: zero occurrences today, and a criterion that
# only reads one spelling is how this repository's counts have gone wrong before.
DCT_SELFC=$(for dct_tf in "$REPO_DIR"/tests/test-*.sh; do
              awk '/^[[:space:]]*set[[:space:]]+(-[a-z]*e|-o[[:space:]]+errexit)/ { print FILENAME; exit }' "$dct_tf"
            done 2>/dev/null | grep -c . || true)

# THE DERIVATION HAS TO BE ABLE TO FAIL. Run outside a git checkout, every `git ls-files` is empty,
# five zeros sum to zero, and zero compared with zero is a green suite that inspected nothing —
# which is also exactly what a bad pathspec produces. Asserted before anything is compared.
DCT_DERIVATION="ok"
[ "$DCT_CLAIM_ROOT" -ge 1 ] || DCT_DERIVATION="git ls-files .claude is empty — not a checkout, or the pathspec stopped matching"
[ "$DCT_DOCS"       -ge 1 ] || DCT_DERIVATION="git ls-files docs is empty"
[ "$DCT_SCRIPTS"    -ge 1 ] || DCT_DERIVATION="git ls-files 'scripts/*' is empty"
[ "$DCT_EXAMPLES"   -ge 1 ] || DCT_DERIVATION="git ls-files examples is empty"
[ "$DCT_TEMPLATES"  -ge 1 ] || DCT_DERIVATION="git ls-files templates is empty"
[ "$DCT_TESTS_SH"   -ge 1 ] || DCT_DERIVATION="no .sh files under \$REPO_DIR/tests"
[ "$DCT_CMD_LINES"  -ge 1 ] || DCT_DERIVATION="\$REPO_DIR/.claude/commands/*.md is empty, so the line count is not a subject"
[ "$DCT_SKILL_DIRS" -ge 1 ] || DCT_DERIVATION="no skill directories under \$REPO_DIR/.claude/skills"
[ "$DCT_PIPE_SWEEP" -ge 1 ] || DCT_DERIVATION="the pipeline-detector sweep pathspec matches nothing"
[ "$DCT_MCPN_TOTAL" -ge 1 ] || DCT_DERIVATION="the mcp-naming pathspec matches nothing"
[ "$DCT_MCPN_DOCS"  -ge 1 ] || DCT_DERIVATION="the mcp-naming docs/* element (less research and superpowers) matches nothing"
[ "$DCT_PAY_CLAUDE" -ge 1 ] || DCT_DERIVATION="the payload derivation found nothing under .claude/"
[ "$DCT_PAY_SCRIPTS" -ge 1 ] || DCT_DERIVATION="the payload derivation ships no scripts/*.sh — the skip list read out of install.sh may match everything"
[ "$DCT_PAY_MD"     -ge 1 ] || DCT_DERIVATION="the payload derivation found no .md under .claude/"
[ "$DCT_SCRIPTS_SH" -ge 1 ] || DCT_DERIVATION="no .sh files under \$REPO_DIR/scripts"
[ "$DCT_CF_POST"    -ge 1 ] || DCT_DERIVATION="no PostToolUse registrations found in .claude/settings.json"
[ "$DCT_CF_NONTOOL" -ge 1 ] || DCT_DERIVATION="no non-tool-event registrations found in .claude/settings.json"
[ "$DCT_CATALOG"    -ge 1 ] || DCT_DERIVATION="git ls-files 'src/catalog/*' is empty"
[ "$DCT_KBUILD_PY"  -ge 1 ] || DCT_DERIVATION="git ls-files 'tools/kinglet_build/*.py' is empty"
[ "$DCT_ADAPTERS"   -ge 1 ] || DCT_DERIVATION="git ls-files 'adapters/*/profile.json' is empty"
# The skip list is read, not written, so an install.sh whose spelling moved must fail loudly here
# rather than silently shipping a payload figure derived from an empty skip list.
DCT_SKIP_N=$(printf '%s' "$DCT_SKIPPED_NAMES" | grep -c . || true)
[ "$DCT_SKIP_N"     -ge 1 ] || DCT_DERIVATION="install.sh's script-skip pattern matched nothing, so the payload total is derived from a skip list of zero names"
assert_eq "ok" "$DCT_DERIVATION" \
  "the tree-size figures are derived from a tree that actually has files in it"

# path <TAB> extended-regex pattern <TAB> comma-separated expected numbers, in the order the match
# carries them. One row per SITE — the multisite check below refuses a pattern that matches two,
# because a vacuity check over a union cannot see one of them disappear.
DCT_CLAIMS="docs/ANTI-VACUITY.md	five roots summing to [*][*][0-9]+[*][*] tracked files today [(].[.]claude. [0-9]+, .docs. [0-9]+, .scripts. [0-9]+, .examples. [0-9]+, .templates. [0-9]+	$DCT_ROOTS,$DCT_CLAIM_ROOT,$DCT_DOCS,$DCT_SCRIPTS,$DCT_EXAMPLES,$DCT_TEMPLATES
docs/ANTI-VACUITY.md	.docs/. alone holds [*][*][0-9]+[*][*]	$DCT_DOCS
docs/ANTI-VACUITY.md	.tests/. holds [*][*][0-9]+[*][*] ..sh. files	$DCT_TESTS_SH
tests/test-provenance-origins.sh	and holds [0-9]+ now	$DCT_SCRIPTS
tests/test-no-mobile.sh	holds [0-9]+ tracked today	$DCT_DOCS
install.sh	so [0-9]+ lines of Unity diagnostics	$DCT_CMD_LINES
tests/test-mcp-naming.sh	[Tt]he pathspecs list [0-9]+ tracked paths: .[.]claude/[*]. [0-9]+, .scripts/[*]. [0-9]+, .docs/[*]. [(]less research/ and superpowers/[)] [0-9]+	$DCT_MCPN_TOTAL,$DCT_MCPN_CLAUDE,$DCT_SCRIPTS,$DCT_MCPN_DOCS
tests/test-pipeline-detector.sh	[0-9]+ tracked paths is nowhere near ARG_MAX	$DCT_PIPE_SWEEP
tests/test-mcp-doc-instructions.sh	against [0-9]+ tracked paths under .[.]claude/. today	$DCT_MCPN_CLAUDE
docs/research/codex-client/findings.md	[(][0-9]+ lines of Unity diagnostics	$DCT_CMD_LINES
docs/research/codex-client/findings.md	command bodies are [*][*][0-9]+[*][*] lines	$DCT_CMD_LINES
docs/research/codex-client/findings.md	while .[.]claude/skills/. holds [*][*][0-9]+[*][*]	$DCT_SKILL_DIRS
docs/research/codex-client/findings.md	where .[.]claude/skills/. holds [0-9]+	$DCT_SKILL_DIRS
tests/test-shipped-citations.sh	The payload has [0-9]+ entries, [0-9]+ Markdown	$DCT_PAY_TOTAL,$DCT_PAY_MD
tests/test-shipped-citations.sh	and [0-9]+ not; this is one of the [0-9]+[.] Applying the same criterion to the other [0-9]+	$DCT_PAY_NONMD,$DCT_PAY_NONMD,$((DCT_PAY_NONMD - 1))
tests/test-bash32-compat.sh	SHIPPED:tests=[0-9]+ SHIPPED:scripts=[0-9]+	$DCT_TESTS_SH,$DCT_SCRIPTS_SH
docs/research/codex-client/findings.md	Kinglet ships [0-9]+ hooks	$DCK_HOOKS
docs/research/codex-client/findings.md	all [0-9]+ registered in .[.]claude/settings.json.	$DCK_REGISTERED
docs/research/codex-client/findings.md	Kinglet ships [0-9]+ skills	$DCS_SKILLS
docs/research/codex-client/findings.md	Kinglet ships [0-9]+ rules	$DCS_RULES
docs/research/codex-client/findings.md	Kinglet ships [0-9]+ commands	$DCS_COMMANDS
docs/research/codex-client/findings.md	Kinglet ships [0-9]+ agents	$DCS_AGENTS
docs/research/codex-client/findings.md	ls src/catalog [|] wc -l # [0-9]+	$DCT_CATALOG
docs/research/codex-client/findings.md	kinglet_build -name .[*][.]py. [|] wc -l # [0-9]+	$DCT_KBUILD_PY
docs/research/codex-client/findings.md	ls adapters/[*]/profile.json [|] wc -l # [0-9]+	$DCT_ADAPTERS
docs/research/codex-client/findings.md	.src/catalog/. [|] [*][*][0-9]+[*][*] files	$DCT_CATALOG
docs/research/codex-client/findings.md	[*][*][0-9]+[*][*] Python modules	$DCT_KBUILD_PY
docs/research/codex-client/findings.md	profile.json. [|] [*][*][0-9]+[*][*] files	$DCT_ADAPTERS
docs/research/codex-client/codex-facts.md	[0-9]+ of Kinglet.s [0-9]+ hooks are .PostToolUse.	$DCT_CF_POST,$DCK_HOOKS
docs/research/codex-client/codex-facts.md	remaining [0-9]+ of Kinglet.s [0-9]+ hooks	$DCT_CF_NONTOOL,$DCK_HOOKS
docs/ANTI-VACUITY.md	live in the [0-9]+ self-contained test files	$DCT_SELFC
provenance.tsv	live in the [0-9]+ self-contained test files	$DCT_SELFC"

# THE WIDENING IS ASSERTED AGAINST A DERIVED BOUNDARY, NOT AGAINST A WRITTEN ONE.
#
# `DCT_ABOVE` is every path-shaped literal appearing in this file BEFORE this block — deliberately
# OVER-INCLUSIVE: it collects paths merely mentioned in a comment as well as paths whose numerals are
# genuinely checked. Over-inclusion is the safe direction. The claim below is that this block's
# scanned set contains a path that does not appear above it AT ALL, which is strictly stronger than
# "a path no block above checks", and it cannot be inflated by a mention. If a later edit narrows
# this table back to documents already handled above, that difference empties and this reds.
#
# This replaces a hand-written census that was wrong four ways on the day it shipped. The lesson is
# in the header; the mechanism is here. `sed` and `sort` both drain their input.
DCT_SCANNED=$(cut -f1 <<< "$DCT_CLAIMS" | sort -u)
# ONE ANCHOR MATCH, TAKEN INSIDE awk, AND NOT WITH `head`. `grep -n … | cut -d: -f1` returns one line
# per match, and a second line matching this header — a maintainer cross-referencing the block by its
# name is enough — makes `stop` a multi-line string. `awk -v stop=` then compares `NR` against a
# non-numeric strnum AS STRINGS, and the region silently extends past the block: measured, the
# extraction swallows the claims table itself and every scanned path stops looking new. It reddens
# today by the arithmetic of the line numbers rather than by design, which is not a property to keep.
# `| head -1` is the obvious repair and it is REFUSED: under `set -euo pipefail` a reader that exits
# on line 1 SIGPIPEs its writer, `pipefail` turns 141 into a failure, and it hides on small inputs
# and fires on large ones — this repository has been bitten by that twice, once through `grep -q`.
# awk takes the first match and keeps reading, so nothing can exit early on anyone.
DCT_BLOCK_LINE=$(awk '/^# TREE-SIZE FIGURES, AND THE EDGE/ && !seen { print NR; seen = 1 }' \
                 "$REPO_DIR/tests/test-derived-counts.sh")
# `^REPO_DIR/`, NOT `^\$REPO_DIR/`, AND THE DIFFERENCE IS THE WHOLE POINT OF THE NORMALISATION.
# The `grep -oE` above has no `$` in its character class, so nothing it emits can ever begin with
# one: a source line reading `"$REPO_DIR/install.sh"` is extracted as `REPO_DIR/install.sh`. The
# previous spelling stripped a prefix that could not occur, so it was DEAD CODE — evidenced, not
# inferred: `DCT_ABOVE` held `REPO_DIR/uninstall.sh`, `REPO_DIR/provenance.tsv` and seven more with
# the prefix intact. A path mentioned ONLY as `"$REPO_DIR/…"` would fail to match its bare form, be
# counted NEW, and INFLATE the widening claim — the unsafe direction for an assertion whose only
# virtue is being conservative.
#
# THE REASON IT WAS HARMLESS IS NOT THE ONE THIS COMMENT GAVE. It said *"each of those paths also
# appears in bare form somewhere above"*, and that is false for **2 of the 9** — measured by
# counting occurrences rather than lines, because a prefixed occurrence sits on a line that also
# contains the bare substring and a line-keyed count reads every one of the nine as bare:
#
#   .claude/hooks/_lib.sh              1 occurrence,  1 prefixed,  0 bare
#   .claude/hooks/session-restore.sh   2 occurrences, 2 prefixed,  0 bare
#
# The other seven do appear bare. What actually made it harmless is that neither of those two is in
# `DCT_SCANNED`, so neither could be counted NEW whatever `DCT_ABOVE` held — a property of the
# scanned set, not of the spellings above. The corrected spelling makes the question moot in both
# directions, which is why it stays.
DCT_ABOVE=$(awk -v stop="${DCT_BLOCK_LINE:-0}" 'NR < stop' "$REPO_DIR/tests/test-derived-counts.sh" \
            | grep -oE '[A-Za-z0-9_./-]+\.(md|tsv|sh)' \
            | sed 's|^REPO_DIR/||' | sort -u)
DCT_NEW=$(comm -23 <(printf '%s\n' "$DCT_SCANNED") <(printf '%s\n' "$DCT_ABOVE"))
DCT_NEW_N=$(printf '%s' "$DCT_NEW" | grep -c . || true)

# The derivation's own floor, before it is used as an oracle: an anchor that stopped matching gives
# `stop=0`, `DCT_ABOVE` empty, and then EVERY scanned path looks new — a green assertion over a
# reader that read nothing.
DCT_ABOVE_N=$(printf '%s' "$DCT_ABOVE" | grep -c . || true)
if [ -n "$DCT_BLOCK_LINE" ] && [ "$DCT_ABOVE_N" -ge 10 ]; then DCT_ABOVE_OK=1; else DCT_ABOVE_OK=0; fi
assert_eq "1" "$DCT_ABOVE_OK" \
  "the region above this block was actually read ($DCT_ABOVE_N path literals) — an anchor that stopped matching would make every path below look new and this assertion vacuous"

DCT_HAS_INSTALL="no"
grep -qxF -- "install.sh" <<< "$DCT_SCANNED" && DCT_HAS_INSTALL="yes"
assert_eq "yes" "$DCT_HAS_INSTALL" \
  "the tree-size guard CHECKS A NUMBER IN install.sh — every block above reads that file only for its skip list, so a user-facing derived count sat there unchecked and stayed wrong through the wave that corrected its source"
if [ "$DCT_NEW_N" -ge 1 ]; then DCT_WIDE=1; else DCT_WIDE=0; fi
if [ "$DCT_WIDE" -ne 1 ]; then
  printf '     %s\n' "every path this block scans is already named above it — the widening has been narrowed away"
fi
assert_eq "1" "$DCT_WIDE" \
  "…and it reaches $DCT_NEW_N path(s) this file does not mention anywhere above this block, so the widening is real rather than a restatement of what was already covered"

# ROW DELETION USED TO BE SILENT. IT IS NOT ANY MORE, AND THAT IS THIS BLOCK'S REAL GUARD.
#
# The previous version asserted only that the scanned set still REACHED `tests/` and
# `docs/research/`. That was already a repair of a plain count — but it was half-hollow, and a
# mutation found the other half: `DCT_HAS_TESTS` was satisfied by `tests/test-provenance-origins.sh`
# and `tests/test-no-mobile.sh`, both of which were rows before the widening. So deleting ALL THREE
# newly added `tests/*.sh` rows — including `tests/test-mcp-doc-instructions.sh`, the row that closes
# the coverage hole this block was written for — left the file 49/49 GREEN. Exactly the defect fixed
# for `docs/research/` one round earlier, surviving in the region next to it, because a region test
# that any one member satisfies cannot see the other members leave.
#
# THE SOURCE SET IS DECLARED **AND** DERIVED, which is `tests/test-no-mobile.sh`'s own grammar and is
# here for the same reason: the declared half is what closes DELETION. `DCT_DECLARED` names every
# file this block is expected to cover **and how many rows it is expected to carry**; the same pair
# is derived from the claims table. They must match IN BOTH DIRECTIONS.
#
# THE COUNT IS THERE BECAUSE THE FILE-LEVEL VERSION WAS HALF A GUARD, AND IT WAS HALF A GUARD IN THE
# COMMIT THAT WROTE THIS PARAGRAPH CLAIMING OTHERWISE. `DCT_SCANNED` was `cut -f1 | sort -u`, so a
# file with more than one row stayed in the derived set after one of its rows was deleted, and the
# comparison could not see the deletion at all. Measured on the tree at the time: `findings.md` had
# four rows, `docs/ANTI-VACUITY.md` three, `tests/test-shipped-citations.sh` two — **nine rows whose
# individual deletion left the suite fully green, including the row the same commit had just added
# to close deletion.** The honest limit statement that version replaced was true for exactly those
# nine. Keying on `path<TAB>count` closes it: deleting one row of sixteen moves the derived count to
# fifteen against a declaration of sixteen and reds by name.
#
# A DECLARED COUNT IS NOT A QUOTED COUNT. Every warning in this repository about writing a number
# down applies to numbers nothing compares; this one is compared, mechanically, in both directions,
# on every run, and its only job is to disagree. Adding or removing a row is the deliberate two-line
# act it should be.
#
# A DECLARED LIST IS A HAND-MAINTAINED LIST, AND THE DISTINCTION FROM THE CENSUS THIS BLOCK'S HEADER
# THREW OUT IS NOT COSMETIC. That census DESCRIBED something derivable, was never compared against
# it, and was wrong four ways on the day it shipped. This list is compared, mechanically, every run,
# in both directions — its only job is to disagree. A hand-written list that is checked is a
# declaration; one that is not is a rumour.
#
# ── AN OPEN RESIDUAL, NAMED HERE SO IT IS INHERITED RATHER THAN REDISCOVERED ──
#
# **THIS FILE IS NOT IN THE LIST, AND THIS FILE QUOTES FIGURES.** `DCT_DECLARED` names every path
# this block covers and `tests/test-derived-counts.sh` is not one of them, so the guard whose subject is stale
# numerals does not scan its own prose. That is not hypothetical: two comment blocks in this file
# carried `982` as the value of `cat .claude/commands/*.md | wc -l`, in the present tense and
# undated, while `DCT_CLAIMS`'s `install.sh` row was correctly guarding `1023`. (Cited by construct,
# not by direction and distance — the first version of this sentence said "three hundred lines
# below" and that table is 99 lines *above*. `docs/ARCHITECTURE.md` states the rule as *"cite by
# anchor, not by distance"*, and `tests/test-citations-resolve.sh` cannot catch a prose distance:
# it reads `file:line` forms.) The figure moved three
# times across one wave (919 → 982 → 1010 → 1023); every guarded site followed it and both
# unguarded sites here did not, through two review sweeps that were keyed on the guarded sites.
# Repaired 2026-08-16 by DELETING the numerals rather than re-transcribing them — the surviving
# sentences make the same point without a value, which is the only repair that cannot go stale again.
#
# **DECIDED 2026-08-17, by Task 13, which this paragraph named as the owner: this file does NOT
# scan itself, and the residual is closed by removing its subject rather than by adding a row.**
#
# The reasoning, so the decision is reviewable rather than merely recorded. A claim row over this
# file would have to match a numeral in this file's own prose — and every reader of `DCT_CLAIMS` is
# also a line of this file, so the row's pattern is itself a candidate match for the row's pattern.
# `DCT_ABOVE` already shows how sharp that edge is: it must stop at a line number derived from an
# anchor in this same file, and the comment above it records what happened when a second line
# matched that anchor. A guard that has to reason about its own text to avoid matching itself is
# strictly harder to keep correct than the defect it would catch.
#
# What actually made the residual dangerous was not the absence of a row — it was that this file
# carried live figures in prose AT ALL. The 2026-08-16 repair deleted those numerals instead of
# re-transcribing them, and the standing rule that replaces the row is: **no live figure is written
# into this file's prose.** Where one is genuinely needed, it goes in a `printf` beside the
# assertion that derives it, where it is regenerated every run and cannot go stale. The one class
# this rule does not cover is a DECLARED count like `DCT_DECLARED`'s own right-hand column, which is
# compared in both directions on every run and is therefore not a quoted figure at all.
#
# A reader who disagrees should reopen it as its own task with a mutation battery, not add a row.
DCT_DECLARED="docs/ANTI-VACUITY.md	4
docs/research/codex-client/codex-facts.md	2
docs/research/codex-client/findings.md	16
install.sh	1
provenance.tsv	1
tests/test-bash32-compat.sh	1
tests/test-mcp-doc-instructions.sh	1
tests/test-mcp-naming.sh	1
tests/test-no-mobile.sh	1
tests/test-pipeline-detector.sh	1
tests/test-provenance-origins.sh	1
tests/test-shipped-citations.sh	2"

# `sort` and `uniq` both drain; nothing on either side of these pipes can exit early.
DCT_SCANNED_COUNTS=$(cut -f1 <<< "$DCT_CLAIMS" | sort | uniq -c | awk '{ printf "%s\t%s\n", $2, $1 }' | sort)
DCT_DECLARED_COUNTS=$(printf '%s\n' "$DCT_DECLARED" | grep -v '^$' | sort)

DCT_UNDECLARED=$(comm -23 <(printf '%s\n' "$DCT_SCANNED_COUNTS") <(printf '%s\n' "$DCT_DECLARED_COUNTS"))
DCT_UNSCANNED=$(comm -13 <(printf '%s\n' "$DCT_SCANNED_COUNTS") <(printf '%s\n' "$DCT_DECLARED_COUNTS"))
if [ -n "$DCT_UNDECLARED" ]; then
  printf '%s\n' "$DCT_UNDECLARED" | sed 's|^|     scanned rows not matching the declaration (path<TAB>rows — update DCT_DECLARED in this commit): |'
fi
if [ -n "$DCT_UNSCANNED" ]; then
  printf '%s\n' "$DCT_UNSCANNED" | sed 's|^|     declared but NO LONGER SCANNED at that row count — a claim row was deleted and took its own guard with it: |'
fi
assert_eq "" "$DCT_UNDECLARED" \
  "every file this block scans is declared, at the row count it actually carries — a row added without declaring it is a guard nobody agreed to maintain"
assert_eq "" "$DCT_UNSCANNED" \
  "every declared file is still scanned at its declared row count — this is the assertion that makes DELETING a claim row loud, and it is keyed on rows rather than files because the file-level version could not see one row of four leave"

DCT_BAD=""
DCT_VACUOUS=""
DCT_MULTISITE=""
while IFS=$'\t' read -r dct_rel dct_pat dct_want; do
  [ -n "$dct_rel" ] || continue
  if [ ! -f "$REPO_DIR/$dct_rel" ]; then
    DCT_VACUOUS="${DCT_VACUOUS}${dct_rel} is not present, so its '${dct_pat}' claim was never checked"$'\n'
    continue
  fi
  # Strip one leading comment marker per line, then join. awk and tr both drain their input.
  dct_flat="$(awk '{ sub(/^[[:space:]]*#[[:space:]]?/, ""); printf "%s ", $0 }' "$REPO_DIR/$dct_rel" | tr -s ' ')"
  dct_hits=0
  while IFS= read -r dct_claim; do
    [ -n "$dct_claim" ] || continue
    dct_hits=$((dct_hits + 1))
    dct_seen=$(grep -oE '[0-9]+' <<< "$dct_claim" | tr '\n' ',' | sed 's/,$//')
    if [ "$dct_seen" != "$dct_want" ]; then
      DCT_BAD="${DCT_BAD}${dct_rel} states '${dct_claim}' — the tree derives ${dct_want}"$'\n'
    fi
  done <<< "$(grep -oE "$dct_pat" <<< "$dct_flat" || true)"

  if [ "$dct_hits" -lt 1 ]; then
    DCT_VACUOUS="${DCT_VACUOUS}${dct_rel} no longer states its '${dct_pat}' claim in a form this guard can read"$'\n'
  elif [ "$dct_hits" -gt 1 ]; then
    DCT_MULTISITE="${DCT_MULTISITE}${dct_rel}'s '${dct_pat}' row matches ${dct_hits} sites — its vacuity check is a union over them. Split it into one row per site, with lexically disjoint patterns."$'\n'
  fi
done <<< "$DCT_CLAIMS"

if [ -n "$DCT_MULTISITE" ]; then
  printf '%s' "$DCT_MULTISITE"
fi
assert_eq "0" "$(printf '%s' "$DCT_MULTISITE" | grep -c . || true)" \
  "every tree-size claim row matches exactly one site in its file"

if [ -n "$DCT_BAD" ]; then
  printf '%s' "$DCT_BAD"
  printf '     %s\n' "Re-derive with: for d in .claude docs scripts examples templates; do git ls-files \"\$d\" | wc -l; done ; ls tests/*.sh | wc -l ; cat .claude/commands/*.md | wc -l"
  printf '     %s\n' "scripts/ here is ALL tracked files (git ls-files 'scripts/*'), not scripts/*.sh — the bash-4 census block above uses the other one."
  printf '     %s\n' "Do not 'fix' this by editing a pinned historical reading (271, 273, 187, 189, 40, 42, 919) kept beside the live figure."
fi
assert_eq "0" "$(printf '%s' "$DCT_BAD" | grep -c . || true)" \
  "every tree-size figure outside the .md documents matches the tree (roots $DCT_ROOTS = $DCT_CLAIM_ROOT+$DCT_DOCS+$DCT_SCRIPTS+$DCT_EXAMPLES+$DCT_TEMPLATES, tests/*.sh $DCT_TESTS_SH, command body lines $DCT_CMD_LINES)"

if [ -n "$DCT_VACUOUS" ]; then
  printf '%s' "$DCT_VACUOUS"
fi
assert_eq "0" "$(printf '%s' "$DCT_VACUOUS" | grep -c . || true)" \
  "every tree-size phrasing this guard covers is still present in the file that carries it"

# ============================================================================
# WORD-NUMERAL FIGURES — the class every claims table above is blind to BY CONSTRUCTION
#
# Every pattern in every table above is written with `[0-9]+`, and every value check harvests
# `grep -oE '[0-9]+'` from the match. A figure spelled *twelve* therefore produces no digits, cannot
# match, and cannot be compared: it is invisible to this file end to end, and invisible in a way
# that reports coverage rather than a gap, because the row that would have caught it was never
# written.
#
# THIS BLOCK EXISTS BECAUSE THE OMISSION WAS MEASURED, IN THE SWEEP WRITTEN TO PREVENT IT. The
# 2026-08-17 live-vs-pinned pass over `docs/research/codex-client/*` named the word-numeral arm as
# the instrument three earlier rounds had never run — and then ran it on `CONTRIBUTING.md` and not
# on its own subject. An independent derivation found eight further live figures there, four of
# them word numerals, and falsified five at once with the **full suite still reading Failed: 0**.
# The remedy round 1 wrote down was *"convert it and add a row"*. That is a remedy per instance;
# this one costs a flattener instead and applies wherever a row is written.
#
# **IT IS NOT A REMEDY FOR THE CLASS, AND THIS LINE SAID IT WAS.** The sentence read *"this is the
# remedy for the class"* until 2026-08-17 — asserting, 1320 lines below the paragraph in this same
# file that withdraws exactly that claim, the thing that paragraph withdraws. What this block is, is
# a hand-maintained table plus a normaliser: it makes the class **reachable** by an ordinary `[0-9]+`
# row, and reaching is not sweeping. Measured after it shipped: a new word-numeral figure inserted
# into a file this table already reads is not caught, and an independent derivation found four more
# live members. See the withdrawal at the surface-pool block for the full statement; a claim that
# survives one screen away from its own retraction is how this repository loses arguments to itself.
#
# THE FLATTENER IS THIS BLOCK'S OWN, AND THAT IS THE WHOLE RISK CONTROL. Normalising word numerals
# in the shared flatten would change the text every table above matches against, so a stray `one of
# the` becoming `1 of the` could give an existing row a second site and red a correct document.
# Here the normalisation is applied only to the text THIS table reads, so no row above can be
# affected by it; and this table's own multisite check is what catches a normalisation that creates
# a second match for one of its rows.
#
# `one` IS DELIBERATELY NOT NORMALISED. It is the word numeral with by far the highest rate of
# non-numeric use in English prose (`one of`, `the one that`, `no one`), so mapping it would
# manufacture digits everywhere and make every pattern here ambiguous. No figure this block guards
# needs it. If one ever does, spell that figure as a digit in its own document instead.
#
# Both `awk` passes drain their input and `tr` drains its input, so nothing here can SIGPIPE a
# writer under `set -euo pipefail`. Token-wise substitution, not `sed` with `\b`: BSD `sed` has no
# `\b`, and this repository is kept macOS-clean.
echo "--- derived counts: figures spelled as words ---"

dcw_flat() {
  awk '{ sub(/^[[:space:]]*#[[:space:]]?/, ""); printf "%s ", $0 }' "$1" | tr -s ' ' | awk '
    BEGIN {
      n = split("two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty", w, " ")
      for (i = 1; i <= n; i++) map[w[i]] = i + 1
    }
    {
      for (i = 1; i <= NF; i++) {
        t = $i; core = t; gsub(/[^A-Za-z]/, "", core); lc = tolower(core)
        if (lc in map) { sub(core, map[lc], t) }
        printf "%s ", t
      }
    }
  '
}

# Derivations this block needs and no block above has. Each is one command, and each names the
# exclusion it encodes rather than leaving it to be inferred.
#   spine rules  — `.claude/rules/` less pc-console.md, which the rules themselves and CLAUDE.md
#                  both describe as an addendum ON TOP OF the spine rather than a member of it
#   advisory     — the `warn-*` hooks: exit 0, write to stderr, block nothing
#   arg commands — commands whose frontmatter declares `args:`
#   events       — distinct event keys in settings.json
#   matchers     — distinct non-empty tool-name matchers, and the entries they cover
DCW_SPINE=$(ls -1 "$REPO_DIR"/.claude/rules/*.md 2>/dev/null | grep -vc 'pc-console' || true)
DCW_NONNEG=$(ls -1 "$REPO_DIR"/.claude/rules/*.md 2>/dev/null | grep -v 'pc-console' | tr '\n' '\0' \
             | xargs -0 grep -hcE '^#+ .*(NON-NEGOTIABLE|CRITICAL)' 2>/dev/null | awk '{s+=$1} END{print s+0}' || true)
DCW_ADVISORY=$(ls -1 "$REPO_DIR"/.claude/hooks/warn-*.sh 2>/dev/null | grep -c . || true)
DCW_ARGCMDS=$(grep -lE '^args:' "$REPO_DIR"/.claude/commands/*.md 2>/dev/null | grep -c . || true)
DCW_EVENTS=$(printf '%s\n' "$DCK_REG_TRIPLES" | awk -F'\t' '$2 != "" { print $2 }' | sort -u | grep -c . || true)
DCW_MATCHERS=$(printf '%s\n' "$DCK_REG_TRIPLES" \
               | awk -F'\t' '($2 == "PreToolUse" || $2 == "PostToolUse") && $3 != "(all)" { print $3 }' \
               | sort -u | grep -c . || true)
DCW_MATCHED=$(printf '%s\n' "$DCK_REG_TRIPLES" \
              | awk -F'\t' '($2 == "PreToolUse" || $2 == "PostToolUse") && $3 != "(all)" { print $1 "\t" $2 }' \
              | grep -c . || true)
DCW_NOARG=$((DCS_COMMANDS - DCW_ARGCMDS))
#
# FOUR MORE, ADDED 2026-08-17 FOR FIGURES NO ARM OF THAT DAY'S SWEEP COULD REACH. Arms A and B narrow
# by a noun list and arm C by a command shape, so all three select a SPAN — and a span is not a
# sentence. None of them can see a SECOND numeral sharing a sentence with an already-selected one,
# which is how `README.md`'s `Five of the eight agents` kept an unguarded partition beside a total
# the same commit guarded at the same site. The blind spot is written up where the criterion lives;
# these are its four measured members.
#
#   narrow   — agents whose `tools:` omits at least one MUTATING capability. `Agent` is deliberately
#              not in the list: every narrowed agent also lacks it, so counting it would make the
#              figure 6 and the prose says 5. The definition lives in two places now, here and in the
#              sentence it guards, and that is the cost of guarding a figure the tree does not yield
#              on its own — a red here means the definition and the prose have parted, which is a
#              red worth having.
#   tmo      — Codex reads Kinglet's millisecond `timeout` as SECONDS, so the shipped values become
#              minutes. Integer division, matching the prose's own rounding (2000 -> 33, 5000 -> 83).
#              `grep`/`sort`/`awk` rather than `jq`: this file has no JSON-parser dependency, which
#              its hook block states three hundred lines up.
#   skillref — every ``Skill`` tool reference in `.claude/agents/`. `grep -o` then `grep -c .`, so
#              two on one line count as two; a per-file `grep -c` would count that line once.
DCW_NARROW=0
for dcw_a in "$REPO_DIR"/.claude/agents/*.md; do
  [ -f "$dcw_a" ] || continue
  dcw_tools="$(grep -m1 '^tools:' "$dcw_a" || true)"
  for dcw_cap in Write Edit Bash; do
    if ! grep -qE "(^|[ ,])${dcw_cap}([ ,]|$)" <<< "$dcw_tools"; then
      DCW_NARROW=$((DCW_NARROW + 1)); break
    fi
  done
done
# `|| true` ON THE ASSIGNMENT, NOT INSIDE THE PIPELINE. `grep` exits 1 when it matches nothing, and
# under `set -euo pipefail` that status becomes the substitution's, then the assignment's, and at an
# assignment site `set -e` kills the file. The repair is right and costs nothing.
#
# **THE CONSEQUENCE THIS COMMENT RECORDED IS WITHDRAWN.** It read *"kills the file — 49 passes, 0
# failures, every assertion below unrun … it reds as an exit code instead of as this floor's
# sentence"*. Measured under the gate instead: with the key broken, the full suite reads
# `Total: 3959  Passed: 3954  Failed: 2`, both failures from this file, the first of them **this
# floor's own sentence**, the last assertion of the block PASSes, and there is no
# *"exited N without reporting a failure"* line. Nothing is unrun.
#
# **What it was measured under was a harness, not the gate.** `tests/run-tests.sh:341` does `set +e`
# before `( source "$test_file" )`, and this file is runner-provided and sets no `-e` of its own:
# `$-` inside it during a real suite run is **`huB`** — measured by injecting an `echo "[$-]"` and
# reading it out of the log. The 49/0/rc-127 figure reproduces only with errexit live inside the
# subshell (`$-` = `ehmtuBc`), which is what the measuring harness did and what the runner does not.
#
# **So the hazard is real and its blast radius is elsewhere: the 29 self-contained test files that
# set `-euo pipefail` themselves.** Here it is inert, which two comments in this same file already
# said — see the `dck_lvl` paragraph (*"the runner does `set +e` before sourcing"*) and the
# `dck_extra` one (*"Inert under the runner"*). The round that wrote 49/0 asserted the opposite of a
# comment 1250 lines above it, in the same file.
#
# **The pair is the lesson.** This is the second instrument in two rounds whose semantics differed
# from its subject's: first a harvest that counted one of the suite's two FAIL token shapes, then a
# harness that kept errexit alive where the gate turns it off. **An instrument that differs from its
# subject in one flag produces a number that is true of nothing that ships** — and the number looks
# exactly like a measurement, because it is one.
DCW_TMOS="$(grep -oE '"timeout"[[:space:]]*:[[:space:]]*[0-9]+' "$REPO_DIR/.claude/settings.json" 2>/dev/null \
            | grep -oE '[0-9]+$' | sort -n)" || true
DCW_TMO_MIN=$(( $(printf '%s\n' "$DCW_TMOS" | awk 'NR==1 { print $1 + 0 }') / 60 ))
DCW_TMO_MAX=$(( $(printf '%s\n' "$DCW_TMOS" | awk 'END { print $1 + 0 }') / 60 ))
DCW_SKILLREF=$(grep -o '`Skill` tool' "$REPO_DIR"/.claude/agents/*.md 2>/dev/null | grep -c . || true)
DCW_AGENTS_LINES=$(wc -l < "$REPO_DIR/AGENTS.md" 2>/dev/null | tr -d ' ' || true)
[ -n "$DCW_AGENTS_LINES" ] || DCW_AGENTS_LINES=0

# THE DERIVATION HAS TO BE ABLE TO FAIL, and it has to be able to fail PER SOURCE — a single total
# would clear while any one source died. **The number of sources is not written here**: it read
# `Eight` while the block carried ten, then still `Eight` while it carried fourteen, and the same
# commit that widened it to fourteen wrote `14 sources` into `docs/ANTI-VACUITY.md`'s floor-set row,
# so the file and the document disagreed about one quantity. Derive it:
#
#   grep -cE '\|\| DCW_DERIVATION=' tests/test-derived-counts.sh
DCW_DERIVATION="ok"
[ "$DCW_SPINE"        -ge 1 ] || DCW_DERIVATION="no spine rules under \$REPO_DIR/.claude/rules (less pc-console.md)"
[ "$DCW_NONNEG"       -ge 1 ] || DCW_DERIVATION="no NON-NEGOTIABLE/CRITICAL headings in the spine rules"
[ "$DCW_ADVISORY"     -ge 1 ] || DCW_DERIVATION="no warn-* hooks under \$REPO_DIR/.claude/hooks"
[ "$DCW_ARGCMDS"      -ge 1 ] || DCW_DERIVATION="no command declares args: in its frontmatter"
[ "$DCW_NOARG"        -ge 1 ] || DCW_DERIVATION="every command declares args:, so the complement is empty and its row cannot be a claim"
[ "$DCW_EVENTS"       -ge 1 ] || DCW_DERIVATION="settings.json yields no event names"
[ "$DCW_MATCHERS"     -ge 1 ] || DCW_DERIVATION="settings.json yields no tool-name matchers"
[ "$DCW_MATCHED"      -ge 1 ] || DCW_DERIVATION="no hook entry sits under a tool-name matcher"
[ "$DCW_AGENTS_LINES" -ge 1 ] || DCW_DERIVATION="AGENTS.md is absent or empty"
[ "$DCW_NARROW"      -ge 1 ] || DCW_DERIVATION="no agent narrows its tools — the tools: frontmatter may have moved"
[ "$DCW_TMO_MIN"     -ge 1 ] || DCW_DERIVATION="no timeout: key in .claude/settings.json, so the minute figures are not derived"
[ "$DCW_TMO_MAX"     -ge 1 ] || DCW_DERIVATION="the settings timeout maximum is under a minute once read as seconds"
# NO BACKTICKS IN A FLOOR'S MESSAGE. This line read "no `Skill` tool reference…" for one commit:
# inside double quotes those are COMMAND SUBSTITUTION, so the moment the floor fires bash runs
# `Skill`. Found by mutating the derivation this floor guards, which is the only probe that reaches
# a failure-only-evaluated string.
#
# **WHAT IT ACTUALLY DOES HERE, measured under the gate rather than under the harness that first
# reported it.** Errexit is off in this file (see the withdrawal above), so bash does not die. It
# prints `Skill: command not found` to the suite log, and the floor fires with the word deleted from
# its own message:
#
#     expected: ok
#     actual:   no  tool reference under .claude/agents/
#
# A mangled diagnostic and a spurious error line, not a truncation. The earlier claim — *"killed the
# whole file … 49 passes, 0 failures, every DCW assertion below never ran … a single-file run reads
# as green"* — is **withdrawn**; it was true only with errexit live, which is the 29 self-contained
# test files and not this one. Under `set -e` it does exit 127 at this line, which is why the repair
# stays: the shape is wrong on its own terms wherever it is written.
[ "$DCW_SKILLREF"    -ge 1 ] || DCW_DERIVATION="no Skill-tool reference under .claude/agents/"
[ "$DCS_AGENTS"       -ge 1 ] || DCW_DERIVATION="no agents (shared with the surface-pool block)"
assert_eq "ok" "$DCW_DERIVATION" \
  "the word-numeral figures are derived from a tree that actually has surfaces in it"

# THE INSTRUMENT'S OWN POSITIVE CONTROL, and it is not ceremony. If the normaliser stops working,
# every row below stops matching and the vacuity check reds — but it would red saying a document was
# reworded, which sends the next reader to the documents instead of to the flattener. This asserts
# the normaliser directly, so a broken one says so in its own words.
#
# IT CALLS `dcw_flat`. The first version of this probe carried its OWN COPY of the awk and asserted
# against that — measured: disabling the substitution inside `dcw_flat` left this assertion GREEN and
# reddened only the phrasing check, which is exactly the failure the probe existed to prevent, in the
# probe. A guard that hardcodes the mechanism on both sides tests nothing; this file's own
# `tests/test-codex-shim.sh` neighbour states the same rule about extracting a signal from the shim
# rather than writing it in the test. `**twelve**` is in the fixture on purpose: emphasis around the
# word is the spelling these documents actually use, so the probe covers the case rather than the
# bare one.
DCW_PROBE_SRC="$(mktemp "${TMPDIR:-/tmp}/dcw-probe.XXXXXX")"
printf '# twelve entries and **sixteen** skills\n' > "$DCW_PROBE_SRC"
DCW_PROBE="$(dcw_flat "$DCW_PROBE_SRC" | sed 's/ *$//')"
rm -f "$DCW_PROBE_SRC"
assert_eq "12 entries and **16** skills" "$DCW_PROBE" \
  "the word-numeral normaliser converts words to digits, through emphasis and through a comment marker — every row below is vacuous if it does not"

# path <TAB> extended-regex pattern (matched against the NORMALISED flattened file) <TAB> expected
# numbers in the order the match carries them. One row per SITE.
DCW_CLAIMS="CLAUDE.md	the [0-9]+ spine rules, .settings.json.	$DCW_SPINE
CLAUDE.md	the [0-9]+ spine rules bind	$DCW_SPINE
README.md	[0-9]+ of the [0-9]+ agents narrow their own tools	$DCW_NARROW,$DCS_AGENTS
docs/research/codex-client/findings.md	The [0-9]+ spine rules carry [*][*][0-9]+[*][*]	$DCW_SPINE,$DCW_NONNEG
docs/research/codex-client/findings.md	all [0-9]+ command strings	$DCK_REGISTERED
docs/research/codex-client/findings.md	its [0-9]+ entries	$DCK_REGISTERED
docs/research/codex-client/findings.md	the [0-9]+ entries, their matchers	$DCK_REGISTERED
docs/research/codex-client/findings.md	the same [0-9]+ hooks with no guard	$DCK_HOOKS
docs/research/codex-client/findings.md	the same [0-9]+ hooks, needing its own	$DCK_HOOKS
docs/research/codex-client/findings.md	[0-9]+ of Kinglet.s hooks are advisory	$DCW_ADVISORY
docs/research/codex-client/findings.md	the [0-9]+ .warn-[*]. hooks	$DCW_ADVISORY
docs/research/codex-client/findings.md	Every one of the [0-9]+ entries in .[.]claude/settings.json.	$DCK_REGISTERED
docs/research/codex-client/findings.md	none of the [0-9]+ command names	$DCS_COMMANDS
docs/research/codex-client/findings.md	.AGENTS.md., tracked, [0-9]+ lines	$DCW_AGENTS_LINES
docs/research/codex-client/findings.md	would get Kinglet.s [0-9]+ skills	$DCS_SKILLS
docs/research/codex-client/findings.md	gets Kinglet.s [0-9]+ skills too	$DCS_SKILLS
docs/research/codex-client/findings.md	Kinglet.s [0-9]+ argument-taking commands all carry	$DCW_ARGCMDS
docs/research/codex-client/findings.md	the [0-9]+ that carry no .[$]. token	$DCW_NOARG
docs/research/codex-client/findings.md	blocks the other [0-9]+	$DCW_ARGCMDS
docs/research/codex-client/findings.md	Could Kinglet.s [0-9]+ be expressed	$DCS_AGENTS
docs/research/codex-client/findings.md	hook timeouts of [0-9]+ to [0-9]+ minutes	$DCW_TMO_MIN,$DCW_TMO_MAX
docs/research/codex-client/findings.md	[0-9]+-to-[0-9]+-minute	$DCW_TMO_MIN,$DCW_TMO_MAX
docs/research/codex-client/findings.md	The [0-9]+ skill-tool references	$DCW_SKILLREF
docs/research/codex-client/findings.md	All [0-9]+ are in .[.]claude/agents/.	$DCW_SKILLREF
docs/research/codex-client/findings.md	Kinglet.s [0-9]+ rules can ship as pointers	$DCS_RULES
docs/research/codex-client/codex-facts.md	Kinglet.s [0-9]+ argument-taking commands	$DCW_ARGCMDS
docs/research/codex-client/codex-facts.md	All [0-9]+ of the events Kinglet registers	$DCW_EVENTS
docs/research/codex-client/codex-facts.md	ships exactly [0-9]+ tool-name matchers	$DCW_MATCHERS
docs/research/codex-client/codex-facts.md	covering [0-9]+ of its [0-9]+ hook entries	$DCW_MATCHED,$DCK_REGISTERED
docs/research/codex-client/codex-facts.md	Kinglet.s [0-9]+ advisory hooks	$DCW_ADVISORY
docs/research/codex-client/codex-facts.md	All [0-9]+ .[.]claude/agents/[*][.]md.	$DCS_AGENTS
docs/research/codex-client/codex-facts.md	[0-9]+ binding spine rules plus .pc-console.md.	$DCW_SPINE
.claude/commands/unity-doctor.md	whose [0-9]+ binding spine rules	$DCW_SPINE"

# Declared path<TAB>rowcount, compared in BOTH directions — the same repair the tree-size block
# needed, built in from the start rather than after a mutation found it.
DCW_DECLARED=".claude/commands/unity-doctor.md	1
CLAUDE.md	2
README.md	1
docs/research/codex-client/codex-facts.md	7
docs/research/codex-client/findings.md	22"
DCW_SCANNED_COUNTS=$(cut -f1 <<< "$DCW_CLAIMS" | sort | uniq -c | awk '{ printf "%s\t%s\n", $2, $1 }' | sort)
DCW_DECLARED_COUNTS=$(printf '%s\n' "$DCW_DECLARED" | grep -v '^$' | sort)
DCW_UNDECLARED=$(comm -23 <(printf '%s\n' "$DCW_SCANNED_COUNTS") <(printf '%s\n' "$DCW_DECLARED_COUNTS"))
DCW_UNSCANNED=$(comm -13 <(printf '%s\n' "$DCW_SCANNED_COUNTS") <(printf '%s\n' "$DCW_DECLARED_COUNTS"))
if [ -n "$DCW_UNDECLARED" ]; then
  printf '%s\n' "$DCW_UNDECLARED" | sed 's|^|     scanned rows not matching the declaration: |'
fi
if [ -n "$DCW_UNSCANNED" ]; then
  printf '%s\n' "$DCW_UNSCANNED" | sed 's|^|     declared but NO LONGER SCANNED at that row count: |'
fi
assert_eq "" "$DCW_UNDECLARED" \
  "every file this block scans is declared, at the row count it actually carries"
assert_eq "" "$DCW_UNSCANNED" \
  "every declared file is still scanned at its declared row count — deleting a word-numeral row is loud"

DCW_BAD=""
DCW_VACUOUS=""
DCW_MULTISITE=""
while IFS=$'\t' read -r dcw_rel dcw_pat dcw_want; do
  [ -n "$dcw_rel" ] || continue
  if [ ! -f "$REPO_DIR/$dcw_rel" ]; then
    DCW_VACUOUS="${DCW_VACUOUS}${dcw_rel} is not present, so its '${dcw_pat}' claim was never checked"$'\n'
    continue
  fi
  dcw_text="$(dcw_flat "$REPO_DIR/$dcw_rel")"
  dcw_hits=0
  while IFS= read -r dcw_claim; do
    [ -n "$dcw_claim" ] || continue
    dcw_hits=$((dcw_hits + 1))
    dcw_seen=$(grep -oE '[0-9]+' <<< "$dcw_claim" | tr '\n' ',' | sed 's/,$//')
    if [ "$dcw_seen" != "$dcw_want" ]; then
      DCW_BAD="${DCW_BAD}${dcw_rel} states '${dcw_claim}' — the tree derives ${dcw_want}"$'\n'
    fi
  done <<< "$(grep -oE "$dcw_pat" <<< "$dcw_text" || true)"

  if [ "$dcw_hits" -lt 1 ]; then
    DCW_VACUOUS="${DCW_VACUOUS}${dcw_rel} no longer states its '${dcw_pat}' claim in a form this guard can read"$'\n'
  elif [ "$dcw_hits" -gt 1 ]; then
    DCW_MULTISITE="${DCW_MULTISITE}${dcw_rel}'s '${dcw_pat}' row matches ${dcw_hits} sites — its vacuity check is a union over them. Split it into one row per site, with lexically disjoint patterns."$'\n'
  fi
done <<< "$DCW_CLAIMS"

if [ -n "$DCW_MULTISITE" ]; then
  printf '%s' "$DCW_MULTISITE"
fi
assert_eq "0" "$(printf '%s' "$DCW_MULTISITE" | grep -c . || true)" \
  "every word-numeral claim row matches exactly one site in its file"

if [ -n "$DCW_BAD" ]; then
  printf '%s' "$DCW_BAD"
  printf '     %s\n' "These are compared against the NORMALISED text, so 'twelve' reads as 12. Re-derive with:"
  printf '     %s\n' "  ls .claude/rules/*.md | grep -v pc-console | wc -l ; ls .claude/hooks/warn-*.sh | wc -l"
  printf '     %s\n' "  grep -lE '^args:' .claude/commands/*.md | wc -l ; wc -l < AGENTS.md"
fi
assert_eq "0" "$(printf '%s' "$DCW_BAD" | grep -c . || true)" \
  "every figure spelled as a word matches the tree ($DCW_SPINE spine rules, $DCW_NONNEG non-negotiable sections, $DCW_ADVISORY advisory hooks, $DCW_ARGCMDS arg-taking commands, $DCW_EVENTS events, $DCW_MATCHERS matchers over $DCW_MATCHED entries, AGENTS.md $DCW_AGENTS_LINES lines)"

if [ -n "$DCW_VACUOUS" ]; then
  printf '%s' "$DCW_VACUOUS"
fi
assert_eq "0" "$(printf '%s' "$DCW_VACUOUS" | grep -c . || true)" \
  "every word-numeral phrasing this guard covers is still present in the file that carries it"
