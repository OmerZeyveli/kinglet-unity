#!/usr/bin/env bash
# ============================================================================
# test-assert-helpers-under-load.sh — assert_contains/assert_not_contains must
# not false-negative on a present needle under scheduling pressure.
#
# The bug this guards: assert_contains and assert_not_contains (defined in
# run-tests.sh) used `echo "$haystack" | grep -qF "$needle"`. `grep -qF` exits
# the instant it finds a match, without draining the rest of its input. Piping
# into it makes `echo` the write end of a real pipe — and a haystack bigger
# than one pipe write (the real install receipt is ~20KB) is not written
# atomically. If grep finds its match and closes its read end before echo's
# write() calls finish, echo dies of SIGPIPE (exit 141).
#
# This runner sources every test file under `set -euo pipefail`, inherited
# from run-tests.sh into the sourcing subshell (a `(...)` subshell forks, it
# does not re-parse a fresh non-pipefail environment). So that SIGPIPE'd echo
# made the *pipeline's* exit status non-zero under pipefail — and assert_contains
# read that as "needle not found," even though grep already found it.
#
# This is why running the concurrent reproduction
# ( bash tests/run-tests.sh & bash tests/run-tests.sh & wait ) flaked on
# test-pioneer-identity.sh's receipt assertions specifically, in a different
# pattern every time: it was never the receipt's content (install.sh writes it
# correctly every time — see task-7-report.md for the raw bytes captured mid-
# investigation), and it was never a shared scratch path (each test's mktemp
# directory is unique). It was scheduling pressure from the OTHER concurrent
# run's subprocesses (this suite's own sha256sum/find/git/python calls)
# perturbing the echo/grep race inside this helper, wherever it happened to
# land that run.
#
# The fix (see run-tests.sh) replaces the pipe with a here-string
# (`grep -qF -- "$needle" <<< "$haystack"`). Bash implements `<<<` by writing
# the expanded word to a temp file before grep ever starts reading, so there
# is no live writer process for grep's early exit to signal — no pipe, no
# SIGPIPE, no race.
#
# This test reproduces the race directly (many concurrent subshells racing
# grep against a large haystack with an early match, which is exactly what
# fails intermittently pre-fix and never fails post-fix) rather than relying
# on the outer concurrent-suite reproduction, which is itself only
# probabilistic. See task-7-report.md, Step 3, for why a probabilistic outer
# reproduction is not a sufficient regression test on its own.
# ============================================================================

TAAL_NEEDLE="# kinglet install receipt"

# Shape the haystack like the real install receipt that exposed this: the
# needle near the front, ~20KB total, many trailing rows after it. A haystack
# this size is what makes a single `echo` write non-atomic on Linux (writes
# larger than PIPE_BUF, traditionally 4096 bytes, are not guaranteed atomic
# even though the pipe's buffer capacity is larger).
TAAL_HAYSTACK=$(
    printf '%s\n' "$TAAL_NEEDLE"
    printf '# edition: pioneer\n'
    printf '# toolkit-version: 3.0.0-pioneer.1\n'
    TAAL_ROW=1
    while [ "$TAAL_ROW" -le 400 ]; do
        printf '.claude/agents/file%03d.md\t%064d\t664\ttoolkit\n' "$TAAL_ROW" "$TAAL_ROW"
        TAAL_ROW=$((TAAL_ROW + 1))
    done
)

TAAL_TMP=$(mktemp -d "${TMPDIR:-/tmp}/kinglet-assert-race.XXXXXX")

# The race is a genuine OS scheduling race: a lone writer and reader on mostly
# idle cores usually complete the pipe write in one uninterrupted syscall, and
# the bug never shows. It needs the same thing the concurrent reproduction
# supplies — enough OTHER CPU-bound work that the kernel actually preempts the
# writer mid-copy. Rather than depend on the rest of the suite happening to be
# running (which is what made the outer reproduction only probabilistic — see
# task-7-report.md), this test generates that pressure itself: nproc*3 busy
# loops, which reliably reproduced the false-negative on this change's
# development machine (an 8-core box) at ~15-20% per call pre-fix, 0% post-fix.
TAAL_NPROC=$(command -v nproc >/dev/null 2>&1 && nproc || echo 4)
TAAL_STRESS_PIDS=()
TAAL_S=1
while [ "$TAAL_S" -le $((TAAL_NPROC * 3)) ]; do
    ( while :; do :; done ) &
    TAAL_STRESS_PIDS+=("$!")
    TAAL_S=$((TAAL_S + 1))
done
TAAL_STOP_STRESS() {
    for TAAL_P in "${TAAL_STRESS_PIDS[@]}"; do
        kill "$TAAL_P" 2>/dev/null || true
    done
}
trap TAAL_STOP_STRESS EXIT

# 300 concurrent calls to the REAL assert_contains, each racing grep against
# the same large haystack while the stress loops above are eating every core.
# Pre-fix this reliably produces multiple false FAILs (dozens per 300 on this
# change's 8-core development machine); post-fix, none, ever.
# `wait` takes explicit PIDs here, not "wait" bare — the stress loops above
# are also background jobs, and a bare `wait` would block on THEM forever
# since they never exit on their own.
TAAL_CHECK_PIDS=()
TAAL_I=1
while [ "$TAAL_I" -le 300 ]; do
    ( assert_contains "$TAAL_HAYSTACK" "$TAAL_NEEDLE" "race-check-$TAAL_I" ) \
        > "${TAAL_TMP}/${TAAL_I}.out" 2>&1 &
    TAAL_CHECK_PIDS+=("$!")
    TAAL_I=$((TAAL_I + 1))
done
wait "${TAAL_CHECK_PIDS[@]}" 2>/dev/null || true

TAAL_FALSE_FAILS=$(grep -l 'FAIL' "${TAAL_TMP}"/*.out 2>/dev/null | wc -l | tr -d ' '; true)
if [ "$TAAL_FALSE_FAILS" -gt 0 ]; then
    echo "--- false-negative assert_contains calls under concurrency ($TAAL_FALSE_FAILS / 300) ---"
    grep -l 'FAIL' "${TAAL_TMP}"/*.out | head -5 | while IFS= read -r f; do
        echo "  $(basename "$f"):"; sed 's/^/    /' "$f"
    done
    echo "--- end (showing at most 5) ---"
fi
assert_eq "0" "$TAAL_FALSE_FAILS" \
    "assert_contains does not false-negative on a present needle under 300-way concurrent scheduling pressure"

# Same race, same fix, for assert_not_contains — this time the needle is
# ABSENT, so the correct result is "not found" on every one of the 300 calls.
TAAL_ABSENT_NEEDLE="# this needle is not in the haystack"
rm -rf "${TAAL_TMP:?}"/*
TAAL_CHECK_PIDS=()
TAAL_I=1
while [ "$TAAL_I" -le 300 ]; do
    ( assert_not_contains "$TAAL_HAYSTACK" "$TAAL_ABSENT_NEEDLE" "absence-race-check-$TAAL_I" ) \
        > "${TAAL_TMP}/${TAAL_I}.out" 2>&1 &
    TAAL_CHECK_PIDS+=("$!")
    TAAL_I=$((TAAL_I + 1))
done
wait "${TAAL_CHECK_PIDS[@]}" 2>/dev/null || true

TAAL_FALSE_POSITIVES=$(grep -l 'FAIL' "${TAAL_TMP}"/*.out 2>/dev/null | wc -l | tr -d ' '; true)
assert_eq "0" "$TAAL_FALSE_POSITIVES" \
    "assert_not_contains agrees across 300 concurrent calls (sanity: the helper itself, not just the fix, is deterministic)"

TAAL_STOP_STRESS
trap - EXIT
rm -rf "$TAAL_TMP"
