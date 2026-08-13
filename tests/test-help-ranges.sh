#!/usr/bin/env bash
# ============================================================================
# test-help-ranges.sh — every script that prints its `--help` by slicing its OWN header comment
# slices a whole help text: nothing from the code below it, and nothing cut off mid-paragraph.
#
# WHY THIS FILE EXISTS.
#
# Six shipped or repo-root scripts build usage() the same way — a fixed line range of the file's own
# header, run through sed to strip the leading `# `. The range is two literals in the source, and
# nothing about editing the header updates them. On 2026-08-13 scripts/generate-claude-md.sh ended
# its slice at line 17, which is the FIRST line of an eight-line paragraph, so the shipped `--help`
# stopped at "…had this script write" and the sentence never finished. It had been that way for as
# long as the paragraph had been there. `grep -rln 'usage()\|--help' tests/*.sh` returned nothing:
# no test in the suite had ever rendered a `--help` at all, so the whole class was unguarded.
#
# generate-claude-md.sh is one of the scripts install.sh copies into $PROJECT_DIR/.claude/scripts/,
# so the truncated sentence reached users.
#
# ── WHAT IS ASSERTED, PER FILE ───────────────────────────────────────────────
#
#   1. RENDERS ITS OWN SLICE. `bash <file> --help` exits 0 and its stdout is byte-identical to
#      re-running the recorded range through the recorded sed, and that text is non-empty. This is
#      what makes the three static checks below claims about the SHIPPED OUTPUT rather than about
#      two numbers nobody proved were the ones in play. A file that grew a second usage path, or
#      printed a banner first, fails here.
#
#   2. THE SLICE IS ALL COMMENT. Every line in [A,B] begins with `#`. This is the over-run
#      direction: a B that reaches past the header emits `set -euo pipefail` — or worse, a line of
#      the arg parser — as help text.
#
#   3. LINE B+1 IS NOT PROSE. The under-run direction, and the one that shipped. See the predicate
#      below.
#
#   4. LINE A-1 IS NOT PROSE. The same predicate at the other boundary: a slice that STARTS
#      mid-paragraph is the same defect run backwards, and costs one more awk call to rule out.
#
# ── THE PREDICATE: WHAT "IS NOT CODE" MEANS, TESTABLY ────────────────────────
#
# "Line B+1 is not code" is too weak to be worth asserting — it passes on a prose comment, which is
# the entire defect. What has to be ruled out is that line B+1 CONTINUES the help text. So a
# boundary line is acceptable when it is one of:
#
#   * outside the comment block  — it does not begin with `#`, so the header ended at B and the
#                                  help is complete by construction (this is studio-doctor.sh and
#                                  uninstall.sh, whose B+1 is `set -euo pipefail`);
#   * past end of file           — the same thing at the end of a file;
#   * a separator comment        — it begins with `#` and carries NO alphanumeric character after
#                                  it: a bare `#`, or a `# ======` rule.
#
# and unacceptable when it begins with `#` and has an alphanumeric character after it — because
# that is a sentence, and a sentence at B+1 is a sentence the user does not get to read.
#
# WHY THAT DISCRIMINATES. The two acceptable comment shapes carry no letters and no digits; a
# continuation of English prose cannot avoid carrying both. It is not a predicate that passes on
# everything: run against the tree as it stood before this file's sibling fix, five of the six files
# pass and generate-claude-md.sh's line 18 (`# $PROJECT_DIR/CLAUDE.md itself while ALSO logging…`)
# is rejected, which is exactly the one defect present.
#
# WHAT THE PREDICATE GETS WRONG. A section-heading rule — `# ── WHAT THIS DOES NOT DO ──────` —
# carries letters, so it reads as prose. If a future script's help ends immediately before one of
# those with no blank `#` between, this file fails on a help text that is arguably fine. That is
# deliberate: the repo's own headers already put a bare `#` before every section rule, so the fix is
# to end the slice on that line, and a looser predicate ("a line with three or more consecutive rule
# characters is a separator") would start accepting prose that happens to contain `———`. A guard
# that is wrong toward strictness is repairable; one that is wrong toward permissiveness is the
# thing this file replaced.
#
# ── HOW THE FILE SET IS DERIVED, AND WHAT THE DERIVATION CANNOT SEE ──────────
#
# NOT a hardcoded list — a list of six goes stale the day a seventh script is added, which is this
# wave's own recurring defect. Every tracked `*.sh` is read, and a file joins the set when a line of
# it slices the file itself with a LITERAL range. A and B come out of that same line, so they are
# never transcribed here either.
#
# The derivation is run twice with two independently spelled needles, and set equality between them
# is asserted:
#
#   COARSE — the line names `sed -n` and the file's own path variable, in any form.
#   FINE   — the same line also carries a literal `A,Bp` range, which is what makes it checkable.
#
# COARSE minus FINE is a self-slicing usage() this file CANNOT check — a computed range, say
# `sed -n "${START},${END}p"` — and it fails loudly rather than being dropped on the floor. That is
# also what stops the whole file from degrading into a green no-op if the fine needle stops
# matching: the count is asserted non-zero, and both spellings would have to break together.
#
# It cannot see:
#   * A `--help` BUILT ANY OTHER WAY. Eight other tracked scripts advertise one and none of them is
#     checked here: the seven `scripts/*.sh` outside this set (analyze-build-size, detect-missing-refs
#     and the five validate-*) and spikes/platform/unity/run-host.sh all emit a heredoc. A heredoc
#     cannot truncate the way this construct does — the text is not addressed by line number — so
#     they are out of scope rather than missed. But "the suite checks every --help" is NOT what this
#     file proves; it checks the six whose help is a line range, which is the six that can rot.
#   * A SLICE OF SOME OTHER FILE. The needle requires the script to slice ITSELF.
#   * ANYTHING UNTRACKED. The walk is `git ls-files`, so a script written but never `git add`ed is
#     outside it — the same window check-provenance.sh's orphan check has, and it closes on staging.
#   * WHETHER THE HELP IS TRUE. That the text is whole says nothing about whether it documents the
#     flags the script actually parses. Untouched here.
#   * A RANGE THAT STOPS ONE BLANK-COMMENT LINE SHORT. Measured: uninstall.sh at `3,21` instead of
#     `3,22` passes every assertion, because line 22 is a bare `#` and a bare `#` is a legal place
#     to stop. All that costs is a trailing blank line in the help. It is not the defect — nothing
#     is cut off — and catching it would mean asserting a house style rather than a contract.
#
# One consequence of walking the whole tree: this file must not match its own needle. The mentions
# of the construct in the comments above are spelled with a backslash before the dollar so that the
# literal two-character sequence the coarse needle looks for never appears beside `sed -n` on one
# line. If that slips, the failure is loud (this file has no `--help`, so assertion 1 reddens
# immediately) rather than silent.
#
# Self-contained: own `set -euo pipefail`, own pass/fail, REPO from BASH_SOURCE. The runner's
# assert_* helpers are deliberately NOT used — the runner does `set +e` before sourcing, so an
# undefined helper writes to stderr and contributes no FAIL token, and the file would report green
# on the very defect it exists to catch.
# ============================================================================

set -euo pipefail

# ${BASH_SOURCE[0]}, not $0: the runner does `( source "$test_file" )`, and inside a sourced file $0
# is the *sourcing* shell's $0.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'PASS: %s\n' "$1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kinglet-help-ranges.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

TAB="$(printf '\t')"

# The quoted-dollar-zero literal the needle looks for, assembled here so that it never sits on the
# same source line as the other half of the needle — which this very comment got wrong on its first
# draft, and the sweep caught its own explanation.
SELF_REF='"'"\$0"'"'

# ── Derivation ───────────────────────────────────────────────────────────────
# git ls-files feeds a `while` that reads to EOF, and awk reads each file by name. No pipeline here
# has a reader that can stop early, so there is no SIGPIPE to turn into a failure under pipefail.
derive() {
  # $1 = "coarse" (any self-slice) or "fine" (self-slice with a literal range)
  # No `cd` — git is pointed at the repo with -C and awk is handed an absolute path, so this
  # function cannot move the caller's working directory out from under the assertions below.
  local mode="$1" f
  git -C "$REPO" ls-files '*.sh' | while IFS= read -r f; do
    [ -f "$REPO/$f" ] || continue
    awk -v F="$f" -v SELF="$SELF_REF" -v MODE="$mode" '
      index($0, SELF) == 0 { next }
      index($0, "sed -n") == 0 { next }
      {
        if (MODE == "coarse") { print F; next }
      }
      match($0, /[0-9]+,[0-9]+p/) {
        # RLENGTH - 1 drops the trailing p, leaving exactly "A,B". Taken by offset out of the
        # matched span rather than by stripping the text around it: the surrounding text is the rest
        # of a shell one-liner and every attempt to describe it in a regex is a guess about quoting.
        spec = substr($0, RSTART, RLENGTH - 1)
        split(spec, ab, ",")
        printf "%s\t%s\t%s\t%s\n", F, ab[1], ab[2], FNR
      }
    ' "$REPO/$f"
  done
}

derive coarse | LC_ALL=C sort -u > "$WORK/coarse"
derive fine   > "$WORK/fine"
cut -f1 "$WORK/fine" | LC_ALL=C sort -u > "$WORK/fine-files"

FINE_COUNT=$(awk 'END {print NR+0}' "$WORK/fine")
COARSE_COUNT=$(awk 'END {print NR+0}' "$WORK/coarse")

# ── Discovery integrity ──────────────────────────────────────────────────────
# A guard whose file set can silently become empty is worse than no guard: it reports the same green
# as a clean tree. This is the runner's own discovery check applied one level down.
if [ "$FINE_COUNT" -gt 0 ]; then
  pass "found $FINE_COUNT self-slicing usage() range(s) across $(awk 'END {print NR+0}' "$WORK/fine-files") tracked script(s)"
else
  fail "no self-slicing usage() ranges found in any tracked *.sh. Either every one was removed, or the needle stopped matching and this file is now a no-op that reports green. Check the construct in scripts/generate-claude-md.sh."
fi

# ── Coarse == fine ───────────────────────────────────────────────────────────
# Set equality in both directions. A coarse-only file self-slices with a range this file cannot read
# (a computed one), and would otherwise be dropped silently.
UNCHECKABLE="$(LC_ALL=C comm -23 "$WORK/coarse" "$WORK/fine-files" || true)"
if [ -z "$UNCHECKABLE" ] && [ "$COARSE_COUNT" -gt 0 ]; then
  pass "every self-slicing script carries a literal line range, so every one of them is checked below"
else
  if [ "$COARSE_COUNT" -eq 0 ]; then
    fail "the coarse needle matched nothing while the fine needle matched $FINE_COUNT. Both spellings look for a script slicing its own header; if the coarse one is empty the derivation is broken, not the tree."
  else
    fail "these scripts slice their own header with a range this file cannot read (a computed range, not two literals), so nothing below checks them: $(printf '%s' "$UNCHECKABLE" | tr '\n' ' ')"
  fi
fi

# ── The predicate, as a function ─────────────────────────────────────────────
# Prints one of: outside | eof | separator | prose
boundary_kind() {
  awk -v n="$2" '
    NR == n {
      if ($0 !~ /^#/) { print "outside"; exit }
      rest = substr($0, 2)
      if (rest ~ /[A-Za-z0-9]/) { print "prose" } else { print "separator" }
      exit
    }
    END { if (NR < n) print "eof" }
  ' "$1"
}

# The token above is what the assertions branch on; this is only how it reads in the message.
kind_phrase() {
  case "$1" in
    outside)   printf 'not a comment at all, so the header ends there' ;;
    eof)       printf 'past the end of the file' ;;
    separator) printf 'a separator comment' ;;
    *)         printf '%s' "$1" ;;
  esac
}

# ── Per-file assertions ──────────────────────────────────────────────────────
while IFS="$TAB" read -r rel a b lineno; do
  [ -n "${rel:-}" ] || continue
  src="$REPO/$rel"

  # 1. The rendered --help IS the recorded slice, and is not empty.
  sed -n "${a},${b}p" "$src" | sed 's/^# \{0,1\}//' > "$WORK/expected"
  rc=0
  bash "$src" --help > "$WORK/rendered" 2> "$WORK/rendered.err" < /dev/null || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "$rel --help exited $rc. Every other assertion for this file is about text it did not print."
  elif [ ! -s "$WORK/expected" ]; then
    fail "$rel:$lineno slices lines $a,$b and that range is empty — the script advertises a --help that says nothing."
  elif cmp -s "$WORK/expected" "$WORK/rendered"; then
    pass "$rel --help is exactly its own lines $a-$b ($(awk 'END {print NR+0}' "$WORK/rendered") line(s))"
  else
    fail "$rel --help does not match its own lines $a,$b run through the same sed. Something else prints too, or a second usage path won. First difference: $( { diff "$WORK/expected" "$WORK/rendered" || true; } | awk 'NR<=4' | tr '\n' ' ')"
  fi

  # 2. Over-run: the slice must not reach into code.
  noncomment="$(awk -v a="$a" -v b="$b" 'NR>=a && NR<=b && $0 !~ /^#/ {printf "%d ", NR}' "$src")"
  if [ -z "$noncomment" ]; then
    pass "$rel lines $a-$b are all header comment — the help carries no code"
  else
    fail "$rel:$lineno slices lines $a,$b, and these lines in that range are not comments: $noncomment. The help text is printing the script's own code."
  fi

  # 3. Under-run: line B+1 must not continue the help.
  kind_after="$(boundary_kind "$src" "$((b + 1))")"
  case "$kind_after" in
    outside|eof|separator)
      pass "$rel ends its help at line $b, and line $((b + 1)) is $(kind_phrase "$kind_after") — nothing is cut off the end"
      ;;
    *)
      fail "$rel:$lineno ends its help at line $b, but line $((b + 1)) is prose that continues it, so --help stops mid-thought: $(awk -v n="$((b + 1))" 'NR==n {print; exit}' "$src")"
      ;;
  esac

  # 4. The same at the opening boundary.
  if [ "$a" -le 1 ]; then
    pass "$rel starts its help at line $a, the top of the file"
  else
    kind_before="$(boundary_kind "$src" "$((a - 1))")"
    case "$kind_before" in
      outside|eof|separator)
        pass "$rel starts its help at line $a, and line $((a - 1)) is $(kind_phrase "$kind_before") — nothing is cut off the front"
        ;;
      *)
        fail "$rel:$lineno starts its help at line $a, but line $((a - 1)) is prose that belongs to the same paragraph, so --help starts mid-thought: $(awk -v n="$((a - 1))" 'NR==n {print; exit}' "$src")"
        ;;
    esac
  fi
done < "$WORK/fine"

if [ "$FAILURES" -eq 0 ]; then
  echo "all help-range assertions passed"
else
  echo "help-range assertions with problems: $FAILURES"
  exit 1
fi
