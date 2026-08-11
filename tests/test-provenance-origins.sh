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
while IFS= read -r dead_f; do
  [ -n "$dead_f" ] || continue
  case "$dead_f" in
    .claude/NOTICE.md) continue ;;  # a licence record; its /unity-workflow mention is history
  esac
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
  if grep -qxF -- "$dead_s" <<< "$dead_scan"; then
    pass "the dead-name scan reaches its sentinel: $dead_s"
  else
    fail "the dead-name scan no longer reaches $dead_s — the glob covering it changed shape, and that file has carried a dead name before"
  fi
done <<'DEAD_SENTINELS'
.claude/skills/using-kinglet/SKILL.md
scripts/studio-doctor.sh
scripts/generate-claude-md.sh
docs/SKILL-CATALOG.md
README.md
DEAD_SENTINELS

[ "$FAILURES" -eq 0 ] || exit 1
printf 'all provenance-origin assertions passed\n'
