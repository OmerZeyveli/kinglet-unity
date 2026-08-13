#!/usr/bin/env bash
# ============================================================================
# run-tests.sh — Test runner for everything-claude-unity
# Runs all test-*.sh files in this directory and reports results.
# No external dependencies — plain bash with built-in assertion helpers.
#
# Usage: bash tests/run-tests.sh [--verbose]
#
# WHAT THE TOTAL COUNTS, AND WHAT IT DOES NOT.
#
# Results are aggregated by grepping each file's output for PASS/FAIL/SKIP tokens (see the subshell
# note further down for why they cannot be shared variables), and `Total` is simply their sum — not a
# count of tests that exist.
#
# THE PYTHON BLINDNESS, AND HOW IT WAS CLOSED (2026-08-14).
#
# The Python suites reached through test-kinglet-build.sh and test-kinglet-spike.sh used to
# contribute **nothing to Total when they passed**: `unittest -v` prints `ok`, not `PASS`. Measured
# 2026-08-14 on this tree — `Ran 135 tests` and `Ran 1308 tests`, 1443 results across the two files,
# contributing exactly **1** to Total, and that 1 was test-kinglet-spike.sh's own decorative
# `PASS:` echo. test-kinglet-build.sh emitted no PASS token at all, so a suite of 135 was worth 0.
#
# That was recorded here as "only ever in the safe direction". It is not, and the reason is this
# file's own subject: a suite that discovers NOTHING prints `Ran 0 tests` and `OK`, exits 0, and
# under the old arithmetic was indistinguishable from a suite of 1443 that passed. A guard that is
# green because it scanned nothing is the worst shape in this repository, and the runner was
# reporting one.
#
# So a file whose output carries unittest's own summary is now tallied from that summary:
#
#   `Ran N test(s) in …`     — N is the authoritative result count. NOT a count of `... ok` lines:
#                              measured, a test that writes to stdout mangles its own outcome line
#                              (1282 `... ok` + 22 `skipped` against `Ran 1308`), so line-counting
#                              undercounts by however many tests happen to print.
#   `OK (skipped=S)` /       — the outcome line supplies the polarity. failures/errors/unexpected
#   `FAILED (failures=F, …)`   successes go to Failed, skipped to Skipped, the remainder to Passed.
#   `Ran 0 tests`            — a python suite that discovered nothing FAILS, by name.
#   `Ran N` with no outcome  — a suite cut off mid-run FAILS, by name.
#
# unittest also prints one `FAIL: <test>` detail header per failing test, which the generic token
# grep above already counts. That overlap is subtracted, so a python failure is counted once.
#
# THE SAME-COMMIT OBLIGATION THIS BLOCK CARRIES. The previous version of this header ended: "Left
# as-is deliberately rather than 'fixed' by also counting `ok`: the totals are quoted in CLAUDE.md
# and in several reports, and changing the arithmetic would silently invalidate every one of them.
# If you do change it, update those in the same commit." That obligation was discharged when this
# change landed: `/usr/bin/grep -rn 'Total:' CLAUDE.md README.md docs/*.md` finds no quoted suite
# total, CLAUDE.md's testing section says in so many words that file and assertion counts drift and
# must not be hardcoded there, and no test asserts a total. The obligation stands for the next
# person who changes this arithmetic: re-run that sweep, and update whatever it finds in the same
# commit. Do not answer it by writing a number down here — CLAUDE.md forbids exactly that, because a
# hardcoded expected total is itself a claim that goes stale.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
VERBOSE="${1:-}"

# test-state.sh sources this file as `run-tests.sh --source-only` to borrow the assertion helpers.
# That flag was never implemented — $1 was read as VERBOSE and the runner ran the whole suite again,
# from inside the test it had just started. Infinite mutual recursion.
#
# It went unnoticed because of the sourcing bug below: the runner died in the first test file, so it
# never reached test-state.sh to trigger this. Fixing that one exposed this one.
SOURCE_ONLY=0
if [ "$VERBOSE" = "--source-only" ]; then SOURCE_ONLY=1; VERBOSE=""; fi

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Counters ---
PASS=0
FAIL=0
SKIP=0
# Python results are folded into PASS/FAIL/SKIP above so `Total` is honest, and counted here as well
# so the summary can say how many of them there were. Reporting both is the granularity: 1443 and 1
# were the same number to this runner until 2026-08-14.
PY_RESULTS=0
PY_SUITES=0
CURRENT_TEST_FILE=""

# --- Assertion Helpers ---

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="${3:-assert_eq}"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC} $message"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC} $message"
        echo -e "       expected: ${CYAN}${expected}${NC}"
        echo -e "       actual:   ${CYAN}${actual}${NC}"
    fi
}

assert_exit_code() {
    local expected_code="$1"
    shift
    local message="${*: -1}"
    local cmd_args=("${@:1:$#-1}")

    local actual_code=0
    "${cmd_args[@]}" > /dev/null 2>&1 || actual_code=$?

    if [ "$expected_code" -eq "$actual_code" ]; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC} $message (exit $actual_code)"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC} $message"
        echo -e "       expected exit: ${CYAN}${expected_code}${NC}"
        echo -e "       actual exit:   ${CYAN}${actual_code}${NC}"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-assert_contains}"
    # `grep -qF` exits the instant it finds a match, without reading the rest of its input.
    # Piping into it (`echo "$haystack" | grep -qF ...`) makes `echo` the write end of a real
    # pipe: on a haystack bigger than one pipe-buffer write, grep can close its read end while
    # echo is still writing, and echo dies of SIGPIPE (128+13=141). This runner sources every
    # test file under `set -euo pipefail` (inherited into the sourcing subshell), so pipefail
    # reports THAT failure as the pipeline's exit status — even though grep already found the
    # needle. Two concurrent full suite runs create enough scheduling pressure (CPU contention
    # from every other test file's subprocesses) for this race to land inside these two
    # assertions specifically, which is what made receipt lines near the front of a ~20KB
    # haystack fail unpredictably while later ones passed: it was never the receipt's content.
    # A here-string has no such race — bash writes it to a temp file before grep ever runs, so
    # there is no live writer for grep's early exit to signal.
    if grep -qF -- "$needle" <<< "$haystack"; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC} $message"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC} $message"
        echo -e "       needle:   ${CYAN}${needle}${NC}"
        echo -e "       not found in output"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-assert_not_contains}"
    # See assert_contains above — same SIGPIPE-under-pipefail hazard, same here-string fix.
    if ! grep -qF -- "$needle" <<< "$haystack"; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC} $message"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC} $message"
        echo -e "       needle:   ${CYAN}${needle}${NC}"
        echo -e "       was unexpectedly found in output"
    fi
}

assert_file_exists() {
    local path="$1"
    local message="${2:-file exists: $path}"
    if [ -e "$path" ]; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC} $message"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC} $message"
        echo -e "       path does not exist: ${CYAN}${path}${NC}"
    fi
}

assert_file_executable() {
    local path="$1"
    local message="${2:-file executable: $path}"
    if [ -x "$path" ]; then
        PASS=$((PASS + 1))
        echo -e "  ${GREEN}PASS${NC} $message"
    else
        FAIL=$((FAIL + 1))
        echo -e "  ${RED}FAIL${NC} $message"
        echo -e "       not executable: ${CYAN}${path}${NC}"
    fi
}

skip_test() {
    local message="$1"
    SKIP=$((SKIP + 1))
    echo -e "  ${YELLOW}SKIP${NC} $message"
}

# --- Export helpers for sourced test files ---
export -f assert_eq assert_exit_code assert_contains assert_not_contains assert_file_exists assert_file_executable skip_test
export REPO_DIR VERBOSE

# Helpers are defined; that is all a --source-only caller wants. Returning here is what stops the
# mutual recursion described above.
if [ "$SOURCE_ONLY" -eq 1 ]; then
    return 0 2>/dev/null || exit 0
fi

# --- Runner ---

echo ""
echo -e "${CYAN}Kinglet Pioneer test suite${NC}"
echo "========================================"
echo ""

# DISCOVERY IS CHECKED, NOT ASSUMED.
#
# `nullglob` is off by default, so an unmatched glob leaves the PATTERN ITSELF in the array as one
# literal string. `${#test_files[@]}` was therefore 1 and never 0 — which made the `-eq 0` guard
# below, and its "No test files found." message, unreachable code from the day they were written.
# The `[ ! -f "$test_file" ]` check inside the loop then skipped the literal, and the runner printed
# a green zero. Measured 2026-08-11 with a copy of this file alone in an otherwise empty directory:
#
#   $ ls -1 /tmp/emptyrun/tests/
#   run-tests.sh
#   $ bash /tmp/emptyrun/tests/run-tests.sh; echo "RC=$?"
#   Kinglet Pioneer test suite
#   ========================================
#   ========================================
#   Total: 0  Passed: 0  Failed: 0  Skipped: 0
#   ========================================
#   RC=0
#
# That is strictly worse than the sourcing bug documented in the loop below — that one at least ran
# one file. CLAUDE.md's remedy for it ("confirm the number of `--- test-*.sh ---` headers equals
# `ls tests/test-*.sh | wc -l`") is an instruction to a human, executed by nothing. It is executed
# here now.
#
# `shopt -p nullglob` EXITS 1 when the option is off, so the obvious save-and-restore —
# `_prev="$(shopt -p nullglob)"` — dies on its own first line under `set -e`, before printing
# anything. Measured, and the reason for the `|| true`:
#
#   $ bash -c 'set -euo pipefail; prev="$(shopt -p nullglob)"; echo "saved: $prev"'; echo "RC=$?"
#   RC=1                                     # no output at all
#   $ bash -c 'set -euo pipefail; prev="$(shopt -p nullglob || true)"; echo "saved: [$prev]"'
#   saved: [shopt -u nullglob]
#
# Restored rather than left on, because every test file is sourced into a subshell that inherits
# this shell's shopt settings and none of them was written against nullglob.
_prev_nullglob="$(shopt -p nullglob || true)"
shopt -s nullglob
test_files=("$SCRIPT_DIR"/test-*.sh)
eval "$_prev_nullglob"

# Counted a second time by a different mechanism. The glob and `find` agreeing proves discovery
# happened; RAN below proves the files were actually executed, which is the number that matters and
# the one no glob can report.
DISCOVERED=$(find "$SCRIPT_DIR" -maxdepth 1 -type f -name 'test-*.sh' | grep -c . || true)
RAN=0

if [ "${#test_files[@]}" -eq 0 ] || [ "$DISCOVERED" -eq 0 ]; then
    echo -e "${RED}No test files found${NC} — ${SCRIPT_DIR}/test-*.sh matched nothing."
    echo "A suite that discovers nothing must not report success."
    exit 1
fi
if [ "${#test_files[@]}" -ne "$DISCOVERED" ]; then
    echo -e "${RED}Test discovery is inconsistent${NC} — glob found ${#test_files[@]}, find found ${DISCOVERED}."
    exit 1
fi

for test_file in "${test_files[@]}"; do
    if [ ! -f "$test_file" ]; then
        # A backstop, not the primary check: the two entries the glob can hold that are not regular
        # files — a directory and a symlink named test-*.sh — are both counted by the glob and not by
        # `find -type f`, so the consistency check above rejects them first. Measured with a
        # directory named test-notafile.sh: "Test discovery is inconsistent — glob found 2, find
        # found 1", RC=1, before the loop starts. This branch exists so that a future edit which
        # relaxes that check cannot restore the silent `continue` it replaced.
        echo -e "  ${RED}FAIL${NC} $(basename "$test_file") matched the glob but is not a regular file"
        FAIL=$((FAIL + 1))
        continue
    fi
    RAN=$((RAN + 1))
    CURRENT_TEST_FILE="$(basename "$test_file")"
    echo -e "${CYAN}--- ${CURRENT_TEST_FILE} ---${NC}"

    # Each file runs in a SUBSHELL, not sourced into this one.
    #
    # This used to be a bare `source "$test_file"`. Several test files end with `exit 0` — and in a
    # sourced file, exit terminates the PARENT. So the runner died inside whichever file came first
    # alphabetically (test-cross-validation.sh) and 7 of the 8 files never ran, while the suite
    # printed "5 passed, 0 failed" and exited 0. It looked green because it had barely started.
    # test-install.sh was among the files that never ran, which is how a CLAUDE.md-destroying bug
    # shipped.
    #
    # Files carry their own PASS:/FAIL: output and some define their own counters, so results are
    # aggregated from the output rather than shared variables — a subshell cannot write ours back.
    # </dev/null: hooks read their JSON payload from stdin, so a test that runs one without
    # redirecting would sit there forever. A test suite must never be able to block.
    set +e
    # shellcheck source=/dev/null
    test_output=$( ( source "$test_file" ) 2>&1 </dev/null )
    test_rc=$?
    set -e
    echo "$test_output"

    # Strip ANSI first. The helpers print "${GREEN}PASS${NC}", so the character before PASS is the
    # 'm' ending the escape sequence, not whitespace — matching on raw output silently undercounts
    # every colourised result while still looking like it worked.
    test_plain=$(echo "$test_output" | sed 's/\x1b\[[0-9;]*m//g')
    file_pass=$(echo "$test_plain" | grep -cE '(^|[[:space:]])PASS(:|[[:space:]])' || true)
    file_fail=$(echo "$test_plain" | grep -cE '(^|[[:space:]])FAIL(:|[[:space:]])' || true)
    file_skip=$(echo "$test_plain" | grep -cE '(^|[[:space:]])SKIP(:|[[:space:]])' || true)

    # --- unittest's own vocabulary, read in ONE awk pass ---------------------
    #
    # One pass, a here-string, and no reader that can stop early: `grep -q`/`head` on the write end
    # of a pipe is the SIGPIPE-under-pipefail trap this repository documents at length, and this
    # block runs with `set -e` back on.
    #
    # `skipped=`/`failures=`/`errors=`/`unexpected successes=` are read ONLY off a line beginning
    # `OK` or `FAILED`, never from anywhere in the output — a test whose own message contains
    # `failures=3` must not be able to move the tally.
    py_stats=$(awk '
        /^Ran [0-9]+ tests? in / { ran += $2; suites++ }
        /^(OK|FAILED)/ {
            outcomes++
            if (match($0, /skipped=[0-9]+/))              sk += substr($0, RSTART + 8,  RLENGTH - 8)
            if (match($0, /failures=[0-9]+/))             fl += substr($0, RSTART + 9,  RLENGTH - 9)
            if (match($0, /errors=[0-9]+/))               er += substr($0, RSTART + 7,  RLENGTH - 7)
            if (match($0, /unexpected successes=[0-9]+/)) us += substr($0, RSTART + 21, RLENGTH - 21)
        }
        /^FAIL: / { detail++ }
        END { printf "%d %d %d %d %d %d %d %d\n", ran+0, suites+0, outcomes+0, sk+0, fl+0, er+0, us+0, detail+0 }
    ' <<< "$test_plain")
    read -r py_ran py_suites py_outcomes py_skip py_fail py_err py_unexp py_detail <<< "$py_stats"

    if [ "$py_suites" -gt 0 ] || [ "$py_outcomes" -gt 0 ]; then
        py_bad=$((py_fail + py_err + py_unexp))
        if [ "$py_ran" -eq 0 ]; then
            # The defect this whole block exists for, one level down: a discovery pattern that stops
            # matching, a renamed test directory, an import error that empties the suite. `OK` over
            # zero tests is the same green as `OK` over 1308.
            echo -e "  ${RED}FAIL${NC} ${CURRENT_TEST_FILE} ran a python suite that discovered 0 tests — a suite that found nothing must not report success"
            # file_fail, not FAIL: the backstop below fires when a file exits non-zero having
            # reported no failure, and `NO TESTS RAN` exits 5. Reporting through file_fail means
            # this cause is named once instead of twice.
            file_fail=$((file_fail + 1))
        elif [ "$py_outcomes" -eq 0 ]; then
            echo -e "  ${RED}FAIL${NC} ${CURRENT_TEST_FILE} started a python suite (${py_ran} test(s)) that never printed an OK/FAILED outcome — it was cut off, so its results mean nothing"
            file_fail=$((file_fail + 1))
        else
            # unittest prints one `FAIL: <test>` detail header per failing test and the generic grep
            # above already counted those. Subtract the overlap so a python failure is counted once,
            # and never below zero — a shell `FAIL:` line in the same file is the caller's, not
            # unittest's, and must survive.
            py_overlap=$py_detail
            [ "$py_overlap" -le "$file_fail" ] || py_overlap=$file_fail
            [ "$py_overlap" -le "$py_bad" ]    || py_overlap=$py_bad
            file_fail=$((file_fail - py_overlap))
            file_pass=$((file_pass + py_ran - py_skip - py_bad))
            file_fail=$((file_fail + py_bad))
            file_skip=$((file_skip + py_skip))
            PY_RESULTS=$((PY_RESULTS + py_ran))
            PY_SUITES=$((PY_SUITES + py_suites))
            echo -e "  ${CYAN}python${NC} ${py_ran} result(s) from ${py_suites} unittest run(s) in ${CURRENT_TEST_FILE}"
        fi
    fi

    PASS=$((PASS + file_pass))
    FAIL=$((FAIL + file_fail))
    SKIP=$((SKIP + file_skip))

    # A file that dies without reporting a failure would otherwise vanish from the tally.
    if [ "$test_rc" -ne 0 ] && [ "$file_fail" -eq 0 ]; then
        echo -e "  ${RED}FAIL${NC} ${CURRENT_TEST_FILE} exited ${test_rc} without reporting a failure"
        FAIL=$((FAIL + 1))
    fi
    echo ""
done

# --- Summary ---

# The header count CLAUDE.md asks a human to eyeball, executed. Nothing in the loop above can reach
# it today — the pre-loop consistency check already rejects every glob entry that would be skipped —
# and that is the point: it is the assertion that a future `continue` in this loop has to get past.
# A file that is discovered but never reaches its section shows up here as a named shortfall rather
# than as a smaller Total that nobody has a baseline for.
if [ "$RAN" -ne "$DISCOVERED" ]; then
    echo -e "  ${RED}FAIL${NC} ran ${RAN} test files but ${DISCOVERED} match ${SCRIPT_DIR}/test-*.sh"
    FAIL=$((FAIL + 1))
fi

TOTAL=$((PASS + FAIL + SKIP))
echo "========================================"
echo -e "Total: ${TOTAL}  ${GREEN}Passed: ${PASS}${NC}  ${RED}Failed: ${FAIL}${NC}  ${YELLOW}Skipped: ${SKIP}${NC}"
# Named separately, not because Total excludes them — it includes them now — but because a reader who
# only sees Total move cannot tell a python suite that shrank from a shell assertion that was deleted.
# Derived from the run, never written down: CLAUDE.md forbids a hardcoded expected count here.
echo -e "  of which ${CYAN}${PY_RESULTS}${NC} result(s) came from ${PY_SUITES} python suite(s)"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

exit 0
