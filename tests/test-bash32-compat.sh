#!/usr/bin/env bash
# Regression gate for scripts that run under macOS's system Bash 3.2.
#
# This used to scan only .claude/hooks/*.sh. install.sh also copies scripts/ and tests/ into the
# user's .claude/ verbatim (see the "for group in scripts tests" loop), and
# .claude/commands/unity-build.md invokes analyze-build-size.sh by name — so those two directories
# are exactly as much "payload that must run on bash 3.2" as the hooks are. A sweep of only hooks/
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

shipped_scripts() {
    local dir
    for dir in "${SHIPPED_SCRIPT_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        for f in "$dir"/*.sh; do
            [ -f "$f" ] || continue
            printf '%s\n' "$f"
        done
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
grep_shipped() {
    local self
    self="$(basename "${BASH_SOURCE[0]}")"
    shipped_scripts | while IFS= read -r f; do
        [ "$(basename "$f")" = "$self" ] && continue
        if grep -n "$@" "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | grep -q .; then
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
