#!/usr/bin/env bash
# Self-contained: defines its own helpers, safe to run standalone.
set -euo pipefail

# ${BASH_SOURCE[0]}, not $0: the runner does `( source "$test_file" )`, and inside a sourced file $0
# is the *sourcing* shell's $0. It happens to resolve correctly today only because run-tests.sh also
# lives in tests/ — source this file from anywhere else and $REPO becomes the wrong directory. Every
# other self-contained file here (test-templates.sh, test-rule-applicability.sh, test-no-mobile.sh)
# uses BASH_SOURCE for this reason.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

# PASS/FAIL, not ok/FAIL: run-tests.sh aggregates by grepping each file's output for those tokens.
# Printing `ok:` made this the one bash file here whose passing assertions were invisible in the
# runner's Total — green in the safe direction, but a file that contributes 0 to the count is
# indistinguishable from a file that did not run, which is a failure mode this suite has had.
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'PASS: %s\n' "$1"; }

# 1. The checker must accept origin=superpowers.
haystack="$(cat "$REPO/scripts/check-provenance.sh")"
if grep -qF -- 'ecu|donchitos|superpowers|original' <<< "$haystack"; then
  pass "check-provenance.sh accepts origin=superpowers"
else
  fail "check-provenance.sh does not accept origin=superpowers (D10)"
fi

# 2. A superpowers row must obey the vendored rule: it cannot be status=original.
# The rule's real enforcement is check-provenance.sh itself running in the suite; this only asserts
# the rule is still here and still phrased so it covers every non-original origin.
if grep -qF -- 'vendored file cannot have status=original' <<< "$haystack"; then
  pass "the vendored/status agreement rule is present and covers superpowers"
else
  fail "no vendored-status agreement rule found"
fi

# 3. Both deliberate refusals must be recorded in the skip manifest, as ENFORCED rows.
# The paths are repo-relative, which is the only form check-provenance.sh can enforce: it runs
# `[ -e "$skip_path" ]` from the repo root. An upstream-relative path here would be a record of a
# refusal, not a prohibition, and would never fire if the surface came back. The upstream path is
# carried in the reason column instead.
#
# Read the rows the checker actually loops over, not the raw file: it feeds its loop from
# `grep -v '^#' provenance-skip.tsv` and enforces only `rule=absent`. Grepping the whole file for a
# substring stays green when a row is commented out or its rule is flipped to ours-wins — the row
# would still be *present* and no longer be a prohibition, which is precisely the state this guard
# exists to detect. Matching field 1 exactly and requiring field 3 to be `absent` mirrors the
# enforcement instead of approximating it.
skip_rows="$(grep -v '^#' "$REPO/provenance-skip.tsv" || true)"
for needle in '.claude/skills/using-git-worktrees/' '.claude/skills/unity-brainstorming/visual-companion.md'; do
  if awk -F'\t' -v want="$needle" '$1 == want && $3 == "absent" { found = 1 } END { exit !found }' <<< "$skip_rows"; then
    pass "refusal enforced as rule=absent: $needle"
  else
    fail "no enforced rule=absent row in provenance-skip.tsv for: $needle (commented out, rule changed, or path edited)"
  fi
done

# 4. The manifest pins the Superpowers version its rows claim.
# This constant is a copy of provenance.tsv's header. A legitimate 6.2.0 -> 6.3.0 bump is one of the
# two ways it can fail, so the message says so rather than implying the pin was vandalised.
manifest="$(cat "$REPO/provenance.tsv")"
if grep -qF -- 'superpowers=6.2.0 (3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9)' <<< "$manifest"; then
  pass "provenance.tsv pins superpowers 6.2.0 at its tag commit"
else
  fail "provenance.tsv does not pin superpowers 6.2.0 at 3dcbd5c — either the pin was lost, or the upstream was legitimately bumped and this constant needs updating to match provenance.tsv"
fi

# ── 5. The ECU pin keeps its own header line ─────────────────────────────────────────────────────
# What --online depends on is a property of provenance.tsv, not of check-provenance.sh: the `# ecu=`
# header line must carry exactly ONE 40-hex pin. The manifest's own header states the rule in prose
# — "Keep that pin on its own line" — because the checker's extraction is greedy (`.*` before the
# parenthesis, so the *last* parenthesis on the line wins) and is correct only while that holds.
# Adding the Superpowers pin is what made it a live risk: a second 40-hex parenthesis here sends
# --online to clone ECU and check out a SHA that is not in that clone, where git errors and the
# script dies under set -e. Hard breakage, but nothing in the suite runs --online, so it stays
# invisible until someone does.
#
# THIS FILE KEEPS NO COPY OF THE CHECKER'S CODE, AND EXECUTES NOTHING IT CONTAINS. Earlier rounds
# asserted the same thing by holding the checker's extraction expression as a string and running it.
# Three of the four defects found in this guard were defects of that copy, not of the invariant:
# a copy nothing pinned, then two copies where editing one alone kept every assertion green, then
# the discovery that `grep -F` with a multi-line pattern is an OR over its lines — so appending one
# line inside the pinned here-doc silently changed what the assertion ran while the pin stayed
# green. A copy of the subject, living inside the test, is what all three have in common. Asserting
# the invariant directly removes the category rather than adding a fifth layer of pin.
#
# Two independent assertions, 5b and 5c, both driven off one single-sourced key. The regression this
# guards trips 5b on its shape regardless of what value it carries, and 5c on its value regardless
# of how many there are — so no one edit here can hide it.
#
# What that trades away, stated plainly: if check-provenance.sh alone stopped reading this header
# key, --online would `warn` and skip, and the data assertions would be describing a header nothing
# reads. 5a is the link that covers it — a pin on the seven characters of the key, single-sourced
# with the probe below so the two cannot disagree, and never executed.
ecu_key='^# ecu='

# 5a. The checker still reads the ECU pin from the same header key this file probes.
if grep -qF -- "$ecu_key" <<< "$haystack"; then
  pass "check-provenance.sh reads the ECU pin from provenance.tsv's '$ecu_key' line"
else
  fail "check-provenance.sh no longer looks for a '$ecu_key' line — --online would warn and skip, and the two assertions below would be describing a header nothing reads"
fi

# 5b. Exactly one 40-hex pin on that line. `grep -m1` matches the checker's own selection, so if a
# second `# ecu=` line is ever added both read the same one.
#
# A here-string feeds the loop, never a pipe: a `while read` is a reader that can stop early, and
# under `set -euo pipefail` the writer's SIGPIPE becomes 141 becomes a dead file. Running the loop
# in this shell rather than a subshell is also what lets the counters survive it.
ecu_header="$(grep -m1 -- "$ecu_key" "$REPO/provenance.tsv" || true)"
ecu_pin_count=0
ecu_pin=''
while IFS= read -r token; do
  [ -n "$token" ] || continue
  ecu_pin_count=$((ecu_pin_count + 1))
  # Last one wins — the same one the checker's greedy `.*` would take, so 5c judges the value
  # --online would actually use.
  ecu_pin="${token#\(}"; ecu_pin="${ecu_pin%\)}"
done <<< "$(grep -o -- '([0-9a-f]\{40\})' <<< "$ecu_header" || true)"

# Every message below names the key it actually read, rather than assuming it read '^# ecu='. If the
# key is ever edited into something that selects a different line, the output says so instead of
# reporting a true-sounding sentence about a line it never looked at.
if [ "$ecu_pin_count" -eq 1 ]; then
  pass "provenance.tsv's '$ecu_key' line carries exactly one 40-hex pin"
elif [ "$ecu_pin_count" -eq 0 ]; then
  fail "no '$ecu_key' line in provenance.tsv carries a 40-hex pin — --online would warn and skip its verbatim check entirely"
else
  fail "provenance.tsv's '$ecu_key' line carries $ecu_pin_count 40-hex pins — --online takes the last and would clone ECU to check out another upstream's SHA. Give the new pin its own header line"
fi

# 5c. And that pin is ECU's.
if [ "$ecu_pin" = 'bb28ccbd40b065b0958b02df0c03fb91c4fb7c5b' ]; then
  pass "--online still resolves the ECU commit, not another upstream's"
elif [ -z "$ecu_pin" ]; then
  fail "no 40-hex pin to read on provenance.tsv's '$ecu_key' line — see the failure above it"
else
  fail "the pin on provenance.tsv's '$ecu_key' line is '$ecu_pin', not ECU's — either another upstream's pin moved onto that line, in which case --online would clone ECU and check that SHA out, or ECU was legitimately bumped and this constant needs updating to match provenance.tsv"
fi

# ── 6. The two sequencer commands are gone, and nothing shipped still names them ─────────────────
# D7: a command that only sequences other surfaces is a second definition of the chain. The chain
# now lives in unity-brainstorming -> unity-planning -> subagent-driven-implementation | unity-execution,
# so /unity-workflow and /unity-feature were deleted 2026-08-10.
#
# Two assertions per command, and they answer different questions: the file is gone (deletion
# happened) and the skip manifest forbids it (deletion is enforced). Only the second survives a
# future contributor recreating the file, because check-provenance.sh is what reads the manifest.
#
# The rule=absent row is matched by exact field, not by substring anywhere in the file — the same
# form assertion 3 uses, and for the same reason: a commented-out row or a rule flipped to
# ours-wins is still *present* as a substring while no longer being a prohibition.
for gone in ".claude/commands/unity-workflow.md" ".claude/commands/unity-feature.md"; do
  if [ -e "$REPO/$gone" ]; then
    fail "deleted sequencer command has returned: $gone"
  else
    pass "absent: $gone"
  fi
  if awk -F'\t' -v want="$gone" '$1 == want && $3 == "absent" { found = 1 } END { exit !found }' <<< "$skip_rows"; then
    pass "enforced rule=absent row present: $gone"
  else
    fail "no enforced rule=absent row in provenance-skip.tsv for: $gone (missing, commented out, or rule changed)"
  fi
done

# No file that describes the toolkit as it stands today may name a surface that does not exist.
#
# Three dead names, not two. `deep-interview` was renamed to unity-brainstorming on 2026-08-10 and
# left seven live references behind, two of them in scripts/ — and a backticked name inside a
# Markdown table is invisible to tests/test-skill-discovery.sh (path-form references only) and to
# tests/test-surface-references.sh (bare-name *skill* references in payload). Neither would have
# gone red. This assertion is the one that reads the tree.
#
# What is scanned, and why these globs:
#   .claude/*   the shipped payload — a dangling name here becomes a project instruction
#   scripts/*   generate-claude-md.sh EMITS surface names into every installed CLAUDE.md, and
#               studio-doctor.sh names them in its advice. `scripts/generate-claude-md.sh` alone
#               was the first draft of this glob, and it is exactly why studio-doctor.sh:275
#               belonged to no task's file list.
#   :(glob)docs/*.md and README.md — the current-state documentation. The `:(glob)` magic is
#               load-bearing: a bare `docs/*.md` pathspec matches slashes too (measured: 53 files
#               vs 6), which would drag in docs/research/ and docs/superpowers/. Those are
#               RECORDS of what was measured and planned on a date, and their mentions must
#               survive. MERGE-NOTES.md, CREDITS.md and .claude/NOTICE.md are records for the
#               same reason and are outside these globs / skipped below.
#
# The skip is one file and stays one file. Wanting to add a second is the signal that a sentence
# needs rewriting into the past tense, not that the guard needs loosening.
dead_scan="$(git -C "$REPO" ls-files '.claude/*' 'scripts/*' ':(glob)docs/*.md' 'README.md')"

# The needles are matched BARE, without a leading slash.
#
# Round 1 matched the two commands as `/unity-workflow` and `/unity-feature` and only the skill
# bare. Measured against that version: bare `unity-workflow` appended to using-kinglet, and bare
# `unity-feature` appended to GETTING-STARTED.md, both passed the whole suite. The deleted
# command's own frontmatter key was `name: unity-workflow`, and "the unity-workflow pipeline" is
# the natural way a future writer names it in prose — so the slash form is the ONE form the guard
# could afford to miss, and it was the only form it matched. Task 4's lesson, one shape over.
#
# The trade: a future surface named `unity-feature-flags` would trip this. That is the correct
# outcome and not a false positive — these two names are retired, and `provenance-skip.tsv`
# forbids their paths. Reusing either name is the thing being prevented.
dead_needles='unity-workflow
unity-feature
deep-interview'

dead_scanned=0
dead_payload=0
dead_scripts=0
dead_docs=0
dead_readme=0
dead_read=''
while IFS= read -r dead_f; do
  [ -n "$dead_f" ] || continue
  # The skip list is EMPTY, and that is a deliberate state rather than an oversight.
  #
  # It held one entry — `.claude/NOTICE.md`, excused because its §3 named `/unity-workflow` as the
  # command whose dispatch loop the credit compared itself against. Task 7 rewrote that section on
  # 2026-08-11 for the licence facts, and the sentence went with it; the ECU rename history that
  # replaced it lives in CREDITS.md, which is outside these globs. So the excuse expired, and an
  # excuse that outlives its reason is a hole in a shipped file that nobody is looking at. NOTICE.md
  # is now scanned like the rest of the payload and carries a sentinel below.
  #
  # Re-adding an entry here is the wrong repair for a dead name in prose: rewrite the sentence into
  # the past tense, or move the history to a file these globs do not reach.
  dead_scanned=$((dead_scanned + 1))
  # Per-glob tallies, for the floors below. Counted here rather than by re-running ls-files per
  # glob, so the numbers describe the set actually inspected and cannot drift from it.
  case "$dead_f" in
    .claude/*) dead_payload=$((dead_payload + 1)) ;;
    scripts/*) dead_scripts=$((dead_scripts + 1)) ;;
    README.md) dead_readme=$((dead_readme + 1)) ;;
    docs/*)    dead_docs=$((dead_docs + 1)) ;;
  esac
  dead_body="$(cat "$REPO/$dead_f")"
  # The set the sentinels are judged against: files whose bytes this loop actually read. Built
  # here, after the skip `case` and after the `cat`, so it cannot describe a file that was
  # skipped. See the sentinel block for what judging the raw ls-files output instead cost.
  dead_read="${dead_read}${dead_f}"$'\n'
  while IFS= read -r dead_n; do
    [ -n "$dead_n" ] || continue
    # Here-strings, never pipes: `grep -q` exits on first match without draining stdin, and under
    # `set -euo pipefail` the writer's SIGPIPE becomes 141 becomes a dead script — on large inputs
    # only, so it passes in test and breaks in the field.
    if grep -qF -- "$dead_n" <<< "$dead_body"; then
      fail "names retired surface '$dead_n': $dead_f"
    fi
  done <<< "$dead_needles"
done <<< "$dead_scan"

# Anti-vacuity, per glob and by sentinel — NOT as one total.
#
# Round 1 asserted a single floor of 60 over 94 files. `.claude/*` alone contributes 76 of those,
# so the floor was a test of that one glob wearing the costume of a test of all four. Measured by
# deleting one pathspec at a time and planting a dead name behind it:
#
#   pathspec dropped          files scanned   old floor   planted name                 result
#   scripts/*                 83              passes      deep-interview in doctor     UNDETECTED
#   :(glob)docs/*.md README   87              passes      /unity-workflow in README    UNDETECTED
#   .claude/*                 18              fires       —                            caught
#
# Three of the four could break without collapsing the total. Worse, `scripts/*` is the glob the
# comment above singles out as the reason `scripts/studio-doctor.sh:275` belonged to no task's
# file list — the floor did not protect the one failure it was written next to.
#
# Two mechanisms, because they fail differently. The floors catch a glob that empties; the
# sentinels catch a glob that still returns files but no longer returns the RIGHT ones, which no
# count can see. Each sentinel is a file that has actually carried a dead name.
#
# BOTH are judged against `$dead_read` — the paths the loop above actually read — and never against
# `$dead_scan`, the raw `git ls-files` output. Round 1 grepped the raw output, and the difference is
# not academic: a file `continue`d past by the skip `case` still appears in `ls-files`, so it kept
# passing its own sentinel while nothing ever opened it. Measured on that version — add one entry to
# the skip `case`, plant `/unity-workflow` in `.claude/skills/using-kinglet/SKILL.md`, and the guard
# exits 0 with 93 files scanned and all five sentinels green. The sentinels were checking a set that
# did not reflect the skipping they exist to police.
#
# That is also the likely edit rather than an exotic one. The comment above says "the skip is one
# file and stays one file", which is a request; the next contributor who meets an awkward file will
# reach for that `case` first, and a request is not a guard.
dead_floor_bad=""
[ "$dead_payload" -ge 60 ] || dead_floor_bad="${dead_floor_bad}.claude/* scanned $dead_payload files (expected >= 60)"$'\n'
[ "$dead_scripts" -ge 8 ]  || dead_floor_bad="${dead_floor_bad}scripts/* scanned $dead_scripts files (expected >= 8)"$'\n'
[ "$dead_docs"    -ge 4 ]  || dead_floor_bad="${dead_floor_bad}docs/*.md scanned $dead_docs files (expected >= 4)"$'\n'
[ "$dead_readme"  -eq 1 ]  || dead_floor_bad="${dead_floor_bad}README.md scanned $dead_readme times (expected exactly 1)"$'\n'

if [ -z "$dead_floor_bad" ]; then
  pass "every glob in the dead-name scan returned a plausible number of files ($dead_payload payload, $dead_scripts scripts, $dead_docs docs, $dead_readme readme; $dead_scanned total)"
else
  printf '%s' "$dead_floor_bad"
  fail "a pathspec in the dead-name scan broke — every 'clean' result above is worthless for the files it stopped reaching"
fi

while IFS= read -r dead_s; do
  [ -n "$dead_s" ] || continue
  if grep -qxF -- "$dead_s" <<< "$dead_read"; then
    pass "the dead-name scan read its sentinel: $dead_s"
  else
    fail "the dead-name scan never read $dead_s — a glob changed shape or the skip list grew, and that file has carried a dead name before"
  fi
done <<'DEAD_SENTINELS'
.claude/skills/using-kinglet/SKILL.md
.claude/NOTICE.md
scripts/studio-doctor.sh
scripts/generate-claude-md.sh
docs/SKILL-CATALOG.md
README.md
DEAD_SENTINELS

# ── 7. Superpowers: adaptation is a licence obligation, and the shipped notice discharges it ─────
# D10. Until 2026-08-10 Superpowers was an influence: the chain design and two skill names were
# taken, the wording was not, and both credit documents said so and reproduced no licence text. This
# wave adapted three surfaces at the expression level, which makes every one of those sentences
# false — in `.claude/NOTICE.md`, which is INSTALLED INTO EVERY USER PROJECT. A stale attribution
# claim in that file is a defect this repo has already shipped once and fixed once.
#
# Nothing else can catch this. `scripts/check-provenance.sh` never reads the free-text `note`
# column, and its two checksum comparisons both filter on `status=verbatim` — the `--online` loop
# additionally on `origin=ecu`. Every adapted surface here is `status=modified`, so no code path in
# this repository verifies the Superpowers pin, the adapted rows, or one word of what the credit
# documents say about them. Measured 2026-08-11:
#
#   $ awk -F'\t' '$2=="superpowers" && $6=="verbatim" {c++} END {print c+0}' provenance.tsv
#   0
#
# THE LIST IS DERIVED FROM THE MANIFEST, NEVER TYPED HERE. A hardcoded list of three paths would go
# green on the day a fourth surface is adapted and left out of the notice, which is the exact failure
# this block exists to prevent.

# 7a. Derive (our path, their path) from provenance.tsv, by BOTH routes a Superpowers adaptation is
# recorded — and they are different routes, not one route with an exception:
#
#   origin=superpowers            the file's whole lineage is Superpowers; upstream_path is column 4
#   the note clause               the file has TWO upstreams and the schema has one origin column, so
#                                 D10 ruled the origin stays with the first and the second is
#                                 recorded in the note. `unity-brainstorming` is origin=ecu — 32 of
#                                 ECU's 69 substantive lines survive — and its Superpowers lineage is
#                                 visible ONLY here. An origin-column-only derivation finds two of
#                                 the three surfaces and reports success.
#
# The clause is matched in its canonical form, `adapted from Superpowers <version> skills/<x>/SKILL.md`,
# which is what pins the upstream path. That deliberately does not match
# `subagent-driven-implementation`'s note ("architecture adopted from Superpowers'
# subagent-driven-development, wording original") — architecture is not expression, that row stays
# origin=original, and it is credited in the documents' influence paragraph rather than the
# obligation table.
sp_pairs="$(awk -F'\t' '
  $0 ~ /^#/ { next }
  $1 == "path" { next }
  {
    ours = ""; theirs = ""
    if ($2 == "superpowers") { ours = $1; theirs = $4 }
    else if (match($7, /adapted from Superpowers [0-9]+\.[0-9]+\.[0-9]+ skills\/[A-Za-z0-9_.-]+\/SKILL\.md/)) {
      ours = $1
      theirs = substr($7, RSTART, RLENGTH)
      sub(/^adapted from Superpowers [0-9]+\.[0-9]+\.[0-9]+ /, "", theirs)
    }
    if (ours != "") { print ours "\t" theirs }
  }' "$REPO/provenance.tsv" | sort -u)"
sp_ours="$(awk -F'\t' 'NF { print $1 }' <<< "$sp_pairs" | sort -u)"
sp_count=$(grep -c . <<< "$sp_pairs" || true)

# 7b. One sentinel per derivation route, because the two fail independently and a count cannot tell
# them apart. Drop the note-clause branch and `sp_count` falls 3 -> 2 while every remaining assertion
# stays green and `unity-brainstorming` quietly leaves the notice. Each sentinel names the surface
# that route alone can see. If a surface here is deliberately retired, this fails and the removal is
# a decision someone makes on purpose — which is the point.
if [ "$sp_count" -ge 3 ]; then
  pass "the manifest yields $sp_count Superpowers-adapted surfaces"
else
  fail "the manifest yields only $sp_count Superpowers-adapted surfaces — a derivation route broke, and every 'matches the manifest' result below is worthless for the surfaces it stopped finding"
fi
while IFS=$'\t' read -r sp_sentinel sp_route; do
  [ -n "$sp_sentinel" ] || continue
  if grep -qxF -- "$sp_sentinel" <<< "$sp_ours"; then
    pass "the $sp_route route still finds $sp_sentinel"
  else
    fail "the $sp_route route no longer finds $sp_sentinel — that route is broken, or the surface was retired without updating this guard"
  fi
done <<'SP_SENTINELS'
.claude/skills/unity-planning/SKILL.md	origin-column
.claude/skills/unity-brainstorming/SKILL.md	note-clause
SP_SENTINELS

# 7c. Both credit documents must carry exactly that set — no surface missing, nothing claimed that
# the manifest does not support.
#
# `.claude/NOTICE.md` is the one that ships; `CREDITS.md` is the repository's record and states the
# same list at more detail. Checking both is what stops them drifting apart, which is how the
# situation this block corrects arose in the first place.
#
# Anchored BY POSITION, not by what a line looks like: the section is everything between its `## `
# heading and the next `## `, and the obligation table is everything between `### Adapted surfaces`
# and the next `### `. A grep over the whole file would be satisfied by a path mentioned anywhere —
# including the influence paragraph, whose whole point is that those surfaces are NOT part of the
# obligation.
#
# The anchors below write the literal dot as `[.]`, not `\.`. awk's `-v` expands escape sequences in
# the VALUE before the regex ever sees it, so `\.` arrives as a bare `.` — a warning on stderr and a
# pattern that matches any character. Measured 2026-08-11:
#   awk: warning: escape sequence `\.' treated as plain `.'
sp_license_expected="$(cat <<'SP_LICENSE_TEXT'
MIT License

Copyright (c) 2025 Jesse Vincent

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
SP_LICENSE_TEXT
)"

while IFS=$'\t' read -r sp_file sp_anchor; do
  [ -n "$sp_file" ] || continue

  sp_sec="$(awk -v pat="$sp_anchor" '$0 ~ pat { inb = 1; next } inb && /^## / { exit } inb { print }' "$REPO/$sp_file")"
  if [ -z "$sp_sec" ]; then
    fail "no Superpowers section in $sp_file at '$sp_anchor' — it was renamed, renumbered or deleted, and nothing below this line was checked for that file"
    continue
  fi
  pass "found the Superpowers section in $sp_file"

  sp_tbl="$(awk '/^### Adapted surfaces$/ { inb = 1; next } inb && /^### / { exit } inb { print }' <<< "$sp_sec")"
  sp_named="$(grep -o -- '\.claude/skills/[a-z0-9-]*/SKILL\.md' <<< "$sp_tbl" | sort -u || true)"

  # Whole-block compare, never `grep -F` with a multi-line pattern: that is an OR over its lines, so
  # a set missing one member would still match on the others and report agreement.
  if [ "$sp_named" = "$sp_ours" ]; then
    pass "$sp_file names exactly the Superpowers-adapted surfaces the manifest records"
  else
    printf '     manifest:\n%s\n     %s:\n%s\n' "$sp_ours" "$sp_file" "$sp_named"
    fail "$sp_file's 'Adapted surfaces' table disagrees with provenance.tsv — the document is wrong, not the manifest"
  fi

  # Pairing, not merely membership. A table that names all three of our files while attributing one
  # of them to the wrong upstream skill passes the set check above and is still a false attribution.
  while IFS=$'\t' read -r sp_o sp_t; do
    [ -n "$sp_o" ] || continue
    sp_paired=0
    while IFS= read -r sp_row; do
      case "$sp_row" in
        *"$sp_o"*) case "$sp_row" in *"$sp_t"*) sp_paired=1 ;; esac ;;
      esac
    done <<< "$sp_tbl"
    if [ "$sp_paired" -eq 1 ]; then
      pass "$sp_file attributes $sp_o to $sp_t"
    else
      fail "$sp_file does not attribute $sp_o to $sp_t on one row — the manifest pairs them"
    fi
  done <<< "$sp_pairs"

  # The obligation itself. Extracted from the section, so another upstream's MIT block elsewhere in
  # the same file cannot satisfy it — `.claude/NOTICE.md` already carries two, and a file-wide grep
  # for "Permission is hereby granted" passes on it TODAY, before Superpowers' text is added at all.
  # Measured 2026-08-11 against the pre-rewrite file: that needle passed while the notice reproduced
  # no Superpowers licence text whatsoever.
  sp_lic="$(awk '/^```$/ { inb = !inb; if (!inb) exit; next } inb { print }' <<< "$sp_sec")"
  if [ "$sp_lic" = "$sp_license_expected" ]; then
    pass "$sp_file reproduces Superpowers' MIT licence text with its copyright line"
  else
    fail "$sp_file's Superpowers section does not reproduce the MIT licence text character-for-character (missing, truncated, or the copyright line edited)"
  fi
done <<'SP_SECTIONS'
.claude/NOTICE.md	^## 3[.] Superpowers
CREDITS.md	^## 4[.] Superpowers
SP_SECTIONS

# 7d. The superseded claims must be gone from everything that describes the toolkit as it stands —
# including provenance.tsv's own `note` column, which repeated them and which check-provenance.sh
# never reads.
#
# Matched against the file with newlines collapsed to spaces. `.claude/NOTICE.md` wrapped "What was
# not taken is the / text" across a line break, so a plain `grep -F` for that sentence reported the
# claim ABSENT while it was on screen — measured 2026-08-11 on the pre-rewrite file. A guard that
# reads a stale claim as removed is worse than no guard.
#
# The dated history of these claims is deliberately kept in both documents, phrased so it does not
# reproduce the sentences themselves. Historical plans and specs under docs/ are records of what was
# believed on a date and are correctly out of this sweep.
sp_stale='influence, not a license obligation
What was not taken is the text
not a license obligation
no license text reproduced
0.120
0.183
0.156'
sp_stale_files='.claude/NOTICE.md
CREDITS.md
provenance.tsv'

while IFS= read -r sp_f; do
  [ -n "$sp_f" ] || continue
  # tr drains its input; no reader here can exit early.
  sp_flat="$(tr '\n' ' ' < "$REPO/$sp_f" | tr -s ' ')"
  sp_dirty=0
  while IFS= read -r sp_n; do
    [ -n "$sp_n" ] || continue
    case "$sp_flat" in
      *"$sp_n"*) fail "$sp_f still carries a claim the 2026-08-10 adaptation made false: '$sp_n'"; sp_dirty=1 ;;
    esac
  done <<< "$sp_stale"
  [ "$sp_dirty" -eq 0 ] && pass "$sp_f carries none of the superseded influence-only claims"
done <<< "$sp_stale_files"

# 7e. The pinned licence text above is a copy, and this is the one place it can be checked against
# the real upstream. `.research/` is gitignored, so it is present in a working clone and absent in a
# fresh one — which is why 7c compares against the pin rather than the file. When the file IS there,
# say so either way rather than skipping silently: a line that appears only on success is
# indistinguishable from a check that never ran.
sp_upstream_license="$REPO/.research/superpowers/LICENSE"
if [ -f "$sp_upstream_license" ]; then
  if [ "$(cat "$sp_upstream_license")" = "$sp_license_expected" ]; then
    pass "the pinned MIT text matches .research/superpowers/LICENSE byte-for-byte"
  else
    fail "the pinned MIT text differs from .research/superpowers/LICENSE — the upstream notice changed, or the pin was mistyped"
  fi
else
  printf 'note: %s\n' ".research/superpowers/LICENSE is absent (gitignored working copy), so the pinned MIT text was not cross-checked against upstream this run"
fi

[ "$FAILURES" -eq 0 ] || exit 1
printf 'all provenance-origin assertions passed\n'
