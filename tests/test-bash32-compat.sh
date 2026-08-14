#!/usr/bin/env bash
# Regression gate for scripts that run under macOS's system Bash 3.2.
#
# This used to scan only .claude/hooks/*.sh. install.sh also copies scripts/ into the user's
# .claude/ verbatim (see the "for group in scripts" loop), and shipped surfaces invoke scripts from
# there by name — so that directory is exactly as much "payload that must run on bash 3.2" as the
# hooks are. A sweep of only hooks/
# reads as though it covers the class of shipped scripts while covering one directory of it; five
# files under scripts/ used `declare -A` and this gate never saw them.
#
# Widened to every shipped shell script, and to the whole bash-4 convention (not just associative
# arrays): `grep -oP`/`grep -qP` need GNU PCRE support that BSD/macOS grep does not have at all;
# `${var,,}`/`${var^^}` case conversion, `mapfile`/`readarray`, and the `&>>` append-both-streams
# redirection are all bash-4-only syntax that is a hard parse failure under bash 3.2.

set -euo pipefail

SHIPPED_SCRIPT_DIRS=(
    "$REPO_DIR"/.claude/hooks
    "$REPO_DIR"/scripts
    "$REPO_DIR"/tests
)

# install.sh and uninstall.sh sit at the repo root, not inside any of the directories above, so no
# directory sweep ever saw them. They are the two most-run shell scripts in the product and both are
# required to work under macOS bash 3.2 same as everything else here — omitting them was the same
# "a check running over a set that is not the whole reality" shape this file's header already
# describes for scripts/ and tests/, one level up. See Finding 5 in the 2026-08-03 whole-branch
# review: install.sh:197 shipped exactly the early-exit-reader bug below, unseen, because this file
# never looked at install.sh at all.
ROOT_SCRIPTS=(
    "$REPO_DIR"/install.sh
    "$REPO_DIR"/uninstall.sh
)

# The early-exit-reader scope. This is a DIRECTORY list on purpose: the file set is derived by the
# glob in shipped_scripts() below, so a script added to a covered directory is covered the day it
# lands and no list here can go stale.
#
# scripts/ WAS EXCLUDED, AND THE GROUND IT WAS EXCLUDED ON WAS WRONG. That ground read: "scripts/
# and tests/ were already swept for this shape (Task 9) and are confined to short
# per-line/bounded-string checks (a single asmdef field, one line of a .cs file) where a pipe buffer
# is never in play." Two things about it did not survive being re-run on 2026-08-14:
#
#   * The premise was about SIZE, and size is not what decides. Measured, at 1 KB / 50 KB / 120 KB /
#     400 KB: `echo "$V" | grep -qw NEEDLE` where $V is ONE LINE never fires at any size, because
#     grep cannot decide a line until it has all of it and therefore drains its input; the SAME
#     bytes newline-separated fail open from ~50 KB up, reporting a match that is present as absent.
#     So `scripts/validate-asmdefs.sh`'s reference check — the "single asmdef field" the old ground
#     names as its accepted exception — is safe because of a `tr '\n' ' '` one line above it, not
#     because the field is small. Delete that `tr` and the line is a live fail-open bug. A ground
#     that names the wrong reason cannot be re-derived by the next reader.
#   * It was written before the current set of scripts existed. The surface-criterion cut removed
#     four of them and `scripts/generate-claude-md.sh` grew the `| head -1` this widening now
#     catches: on a project whose .asmdef makes sed emit more than one pipe buffer, that line took
#     SIGPIPE, pipefail promoted 141, `set -e` killed the generator, and install.sh — which calls it
#     inside `if ... 2>/dev/null` — wrote NO CLAUDE.md and printed no diagnostic. Measured
#     2026-08-14: 80 KB of sed output → exit 141, zero bytes of document; 413 B → exit 0.
#
# scripts/ is installed payload — install.sh copies it into the user's `.claude/scripts/` — so it is
# exactly as much "must not fail open in the field" as .claude/hooks/ is, which is the argument this
# file's own header already makes one level up for the bash-4 sweep.
#
# tests/ STAYS OUT, and that is a decision rather than an oversight. It is not shipped: nothing
# under tests/ is copied into a user's project, so a fail-open there costs a wrong local answer, not
# a wrong answer on a machine nobody is watching. The runner's own two assertion helpers were the
# one instance that mattered and they were fixed to here-strings; tests/test-assert-helpers-under-load.sh
# guards that specific regression under real concurrency, which is stronger evidence than a text
# sweep. Re-derive what is left rather than trusting this sentence:
#   /usr/bin/grep -nE '([^|]|^)\|[[:space:]]*grep([[:space:]]+-[A-Za-z]*q[A-Za-z]*)' tests/*.sh
PIPE_CHECK_DIRS=(
    "$REPO_DIR"/.claude/hooks
    "$REPO_DIR"/scripts
)
PIPE_CHECK_FILES=(
    "$REPO_DIR"/install.sh
    "$REPO_DIR"/uninstall.sh
)

shipped_scripts() {
    local selection="${1:-SHIPPED_SCRIPT_DIRS}"
    local dir f
    local -a dirs
    local -a files
    case "$selection" in
        PIPE_CHECK_DIRS) dirs=("${PIPE_CHECK_DIRS[@]}"); files=("${PIPE_CHECK_FILES[@]}") ;;
        *) dirs=("${SHIPPED_SCRIPT_DIRS[@]}"); files=("${ROOT_SCRIPTS[@]}") ;;
    esac
    for dir in "${dirs[@]}"; do
        [ -d "$dir" ] || continue
        for f in "$dir"/*.sh; do
            [ -f "$f" ] || continue
            printf '%s\n' "$f"
        done
    done
    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        printf '%s\n' "$f"
    done
}

# Reports every shipped script (except this guard itself) that matches the given grep arguments on
# a non-comment line. Two things would otherwise self-defeat a substring/regex sweep like this one:
#
#   1. This file's own detection patterns are the literal strings being searched for (e.g. '-oP',
#      '&>>') — without excluding itself, the guard fails permanently by finding its own source.
#   2. generate-claude-md.sh documents several of these constructs by name in comments explaining
#      why it doesn't use them (line 102-104 for declare -A, line 147 for grep -oP) — a substring
#      match with no comment awareness flags prose about the bug as the bug itself.
#
# Comment-line exclusion is deliberately simple (a line whose first non-blank character is '#');
# it does not need to catch trailing inline comments because none of the constructs checked here
# appear in one.
#
# NOT `grep -n "$@" "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -q .` — that was this guard's
# own first draft, and it is the exact trap this file exists to close. `grep -q` exits the instant
# it matches, without draining the rest of its input; on a shipped script large enough and with
# enough real matches that the middle `grep -v`'s filtered output exceeds one pipe buffer before
# the final `grep -q` reads its first line, the middle `grep -v` gets SIGPIPE'd (its own write end
# closes early) and *its* exit status — not the final grep's — is what `pipefail` reports, because
# pipefail returns the rightmost command that exited non-zero, and the final `grep -q` exiting 0
# doesn't stop pipefail from finding the SIGPIPE'd middle command. That reports a genuinely present
# violation as absent. Every shipped script is comfortably under that threshold today (the largest
# is 398 lines), which is exactly why it would have shipped invisibly and bitten the first script
# to grow past it.
#
# Fixed by removing the multi-stage pipe entirely: `grep -n "$@" "$f"` is captured once via command
# substitution (which fully drains its writer — no early-exiting reader, same reason a here-string
# is safe), then comment-filtering and match-detection happen in a plain bash loop reading that
# already-captured text via a here-string. Nothing here reads from a live process that can close
# its end while another process is still writing.
grep_shipped() {
    local self
    self="$(basename "${BASH_SOURCE[0]}")"
    local f matches line content trimmed hit
    shipped_scripts SHIPPED_SCRIPT_DIRS | while IFS= read -r f; do
        [ "$(basename "$f")" = "$self" ] && continue
        matches=$(grep -n "$@" "$f" 2>/dev/null || true)
        [ -z "$matches" ] && continue
        hit=0
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            content="${line#*:}"                                  # strip grep -n's "NNN:" prefix
            trimmed="${content#"${content%%[![:space:]]*}"}"       # strip leading whitespace
            case "$trimmed" in
                '#'*) continue ;;
            esac
            hit=1
            break
        done <<< "$matches"
        if [ "$hit" -eq 1 ]; then
            printf '%s\n' "$f"
        fi
    done
}

# Same comment-aware sweep as grep_shipped, restricted to .claude/hooks/*.sh plus install.sh and
# uninstall.sh (see PIPE_CHECK_DIRS/PIPE_CHECK_FILES above for why the scope differs from scripts/
# and tests/).
grep_pipe_check() {
    local self
    self="$(basename "${BASH_SOURCE[0]}")"
    local f matches line content trimmed hit
    shipped_scripts PIPE_CHECK_DIRS | while IFS= read -r f; do
        [ "$(basename "$f")" = "$self" ] && continue
        matches=$(grep -n "$@" "$f" 2>/dev/null || true)
        [ -z "$matches" ] && continue
        hit=0
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            content="${line#*:}"
            trimmed="${content#"${content%%[![:space:]]*}"}"
            case "$trimmed" in
                '#'*) continue ;;
            esac
            hit=1
            break
        done <<< "$matches"
        if [ "$hit" -eq 1 ]; then
            printf '%s\n' "$f"
        fi
    done
}

BASH4_ASSOCIATIVE_ARRAYS=$(grep_shipped -E '(^|[[:space:]])declare[[:space:]]+-A([[:space:]]|$)')

assert_eq \
    "" \
    "$BASH4_ASSOCIATIVE_ARRAYS" \
    "shipped scripts avoid Bash 4 associative arrays (declare -A)"

# grep's PCRE flag can appear as -P on its own or combined with -o/-q in either order (-oP, -Po,
# -qP, -Pq). Matched as fixed strings rather than one clever regex: each variant is unambiguous on
# its own, and a single alternation big enough to catch all of them stops being obviously correct.
BASH4_GREP_PCRE=$(grep_shipped -F -e '-oP' -e '-Po' -e '-qP' -e '-Pq')

assert_eq \
    "" \
    "$BASH4_GREP_PCRE" \
    "shipped scripts avoid grep -oP/-qP (GNU-only PCRE mode, absent from BSD/macOS grep)"

BASH4_CASE_CONVERSION=$(grep_shipped -E '\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(,,|\^\^)')

assert_eq \
    "" \
    "$BASH4_CASE_CONVERSION" \
    "shipped scripts avoid \${var,,}/\${var^^} case conversion"

BASH4_MAPFILE=$(grep_shipped -E '(^|[[:space:]])(mapfile|readarray)([[:space:]]|$)')

assert_eq \
    "" \
    "$BASH4_MAPFILE" \
    "shipped scripts avoid mapfile/readarray"

BASH4_APPEND_BOTH_STREAMS=$(grep_shipped -F -- '&>>')

assert_eq \
    "" \
    "$BASH4_APPEND_BOTH_STREAMS" \
    "shipped scripts avoid &>> (bash-4-only append-both-streams redirection)"

# Not bash-4-vs-3.2 — this is the pipefail early-exit-reader shape (see
# tests/test-hook-large-payload.sh and the file header above). `echo "$VAR" |
# grep -q...` fails open the instant $VAR is large enough that grep exits
# before draining stdin. Scoped to PIPE_CHECK_DIRS + PIPE_CHECK_FILES — see the ruling at their
# declaration for why scripts/ is now in and tests/ is still out. `-q` on its own, or
# combined with a case/fixed/extended flag in either order (-qE/-Eq, -qi/-iq,
# -qF/-Fq, -qx/-xq, -qiE, -qxF, ...), all count.
#
# `([^|]|^)\|` (a single pipe not preceded by another pipe) rather than a bare `\|` — a bare
# pattern also matches the second `|` of a `||` logical-OR continuation (e.g.
# `... \n    || grep -qE '...' <<< "$VAR"; then`), which is not a pipeline at all and already
# uses the safe here-string form.
PIPE_GREP_Q=$(grep_pipe_check -E '([^|]|^)\|[[:space:]]*grep([[:space:]]+-[A-Za-z]*q[A-Za-z]*)\b')

assert_eq \
    "" \
    "$PIPE_GREP_Q" \
    "hooks, scripts and install/uninstall avoid piping into grep -q (early-exit reader can SIGPIPE its writer under pipefail on large content)"

# THE SAME SHAPE WITH THE OTHER READER, and the one this sweep did not have when
# scripts/generate-claude-md.sh shipped `sed -n '…' "$asmdef" | head -1` as a bare assignment.
# `grep -q` is the subtle instance of the trap; `head` is the one the repo's own guidance names
# first, and until 2026-08-14 nothing in the suite looked for it anywhere. Its consequence is worse,
# not better: `grep -q` sits in an `if` condition, where `set -e` is suspended and a fired trap only
# flips the answer, while `| head` in a bare `X=$(…)` assignment kills the script outright.
#
# WHY ` | head` AND NOT `\|[[:space:]]*head` — whitespace is REQUIRED on both sides of the pipe.
# .claude/hooks/bash-gate.sh carries `…|cat|head|tail|less|…` as a `case` alternation of read-only
# command names. That is not a pipeline at all, it is not a comment (so the comment filter below
# does not drop it), and the looser needle matches it — a permanent red on a correct file. Requiring
# a space on each side separates the two with no exception in the tree today.
#
# WHAT THAT COSTS: `foo |head -1` and `foo| head -1` are legal shell and this needle misses both.
# That is a known hole, chosen over a guard that cannot go green. If it ever matters the repair is a
# style rule, not a cleverer regex.
PIPE_HEAD=$(grep_pipe_check -E '[[:space:]]\|[[:space:]]+head([[:space:]]|$)')

assert_eq \
    "" \
    "$PIPE_HEAD" \
    "hooks, scripts and install/uninstall avoid piping into head (it exits on line N and SIGPIPEs its writer; in a bare assignment under set -e that ends the script)"
