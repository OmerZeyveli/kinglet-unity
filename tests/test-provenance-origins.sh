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

# ── Assertions 5a and 5 share ONE copy of the extraction expression ──────────────────────────────
# The expression check-provenance.sh uses to read the ECU commit appears exactly once in this file:
# the here-doc immediately below. 5a pins that string to the checker; 5 *executes that same string*.
#
# It used to appear twice — once pinned, once transcribed and run — and nothing tied the two
# together. Editing only the transcribed one (say, to take the first parenthesis where the checker's
# greedy `.*` takes the last) left all seven assertions green while the checker's real behaviour had
# diverged. That is the identical defect 5a exists to catch, one level in: a copy that nothing pins
# is a comment about its subject. One copy is the fix; there is no "live expression" left to edit
# on its own.
ecu_expr="$(cat <<'EXPR'
ECU_COMMIT=$(grep -m1 '^# ecu=' "$MANIFEST" | sed -n 's/.*(\([0-9a-f]\{40\}\)).*/\1/p')
EXPR
)"

# 5a. The one copy must still be what the checker actually runs.
if grep -qF -- "$ecu_expr" <<< "$haystack"; then
  pass "check-provenance.sh extracts the ECU commit with the expression this file runs"
else
  fail "check-provenance.sh no longer contains the extraction expression this file runs — re-sync the here-doc above, then re-check what --online actually extracts"
fi

# 5. Adding the superpowers pin must not have stolen --online's ECU commit.
# check-provenance.sh --online extracts the ECU commit with a greedy `.*` before the parenthesis, so
# a second 40-hex parenthesis on the `# ecu=` line wins. --online would then clone ECU and try to
# check out a SHA that is not in that clone: `git checkout` errors and the script dies under set -e.
# Hard breakage, not silently-wrong verification — but nothing in the suite runs --online, so it is
# still invisible until someone does. The pin lives on its own line for this reason; this asserts
# the reason still holds.
#
# Run through `bash -c`, not `eval`. Either way a string is being executed as code, so the choice is
# about blast radius: a separate interpreter cannot set shell options, clobber a variable, or take
# this sourced file down with it when the expression dies under `set -e`. `eval` runs in *this*
# shell and can do all three, and the last one would undo Minor 3 — the diagnostic below is the
# whole point of the assertion, so nothing may kill the file before it prints.
#
# The probe sets the same options the checker runs under, so it fails the same way the checker
# would. `|| true` and the empty branch, not a bare assignment: if the `# ecu=` line is renamed or
# removed, grep -m1 exits 1, pipefail propagates, and without the guard the assignment would kill
# this subshell before the diagnostic prints. check-provenance.sh:153 handles the same case rather
# than dying; so does this.
ecu_probe="$(cat <<EXEC
set -euo pipefail
$ecu_expr
printf '%s' "\$ECU_COMMIT"
EXEC
)"
ecu_commit="$(MANIFEST="$REPO/provenance.tsv" bash -c "$ecu_probe")" || true
if [ -z "$ecu_commit" ]; then
  fail "no ECU commit could be read from provenance.tsv's '# ecu=' line — --online would skip silently"
elif [ "$ecu_commit" = "bb28ccbd40b065b0958b02df0c03fb91c4fb7c5b" ]; then
  pass "--online still resolves the ECU commit, not another upstream's"
else
  fail "--online would clone ECU and check out '$ecu_commit' — either a second upstream pin moved onto the '# ecu=' line, or ECU was legitimately bumped and this constant needs updating to match provenance.tsv"
fi

[ "$FAILURES" -eq 0 ] || exit 1
printf 'all provenance-origin assertions passed\n'
