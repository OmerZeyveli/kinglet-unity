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

# Hooks plus the two root installer scripts, for the early-exit-reader check below. scripts/ and
# tests/ were already swept for this shape (Task 9) and are confined to short per-line/bounded-string
# checks (a single asmdef field, one line of a .cs file) where a pipe buffer is never in play.
# .claude/hooks/*.sh and install.sh/uninstall.sh are different in kind: those scripts routinely
# receive an entire file's new_string, an entire Bash command, or an entire receipt's worth of
# modified-file paths as one variable — exactly the size a generated PlayerControls.cs, a multi-line
# Bash invocation, or a real project's edited-file list produces — so the same shape there is a live
# fail-open bug, not a reviewed-safe one.
PIPE_CHECK_DIRS=(
    "$REPO_DIR"/.claude/hooks
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
# before draining stdin. Scoped to .claude/hooks/*.sh plus install.sh/uninstall.sh: those scripts
# receive whole-file/whole-command/whole-receipt content, unlike the bounded per-line checks
# already reviewed in scripts/ and tests/ under Task 9. `-q` on its own, or
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
    "hooks and install/uninstall avoid piping into grep -q (early-exit reader can SIGPIPE its writer under pipefail on large content)"
