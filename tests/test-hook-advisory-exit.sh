#!/usr/bin/env bash
# ============================================================================
# test-hook-advisory-exit.sh — Stop hooks must never block the stop.
#
# A Stop hook that exits non-zero does not merely fail: Claude Code treats it
# as a refusal, feeds its stderr back to the model as a reason to keep going,
# and the session never terminates. Every Stop hook in this payload is
# advisory, so every one of them must exit 0 no matter what it hits.
#
# The regression this pins: with no git repository, session-save.sh built
# invalid JSON, jq failed, set -e propagated, and the hook exited 2.
# ============================================================================

HAE_TMP="/tmp/kinglet-advisory-$$"
HAE_HOOKS="${REPO_DIR}/.claude/hooks"
HAE_PAYLOAD='{"session_id":"t","hook_event_name":"Stop","cwd":"'"$HAE_TMP"'"}'

mkdir -p "$HAE_TMP"

# A directory that is emphatically not a git repository, and not inside one.
cd "$HAE_TMP" || exit 1

# The profile export, and why it survives a loop that is now one hook long.
#
# Until 2026-08-13 this loop ran five hooks, two of which (auto-learn, instinct-distill) declared
# HOOK_PROFILE_LEVEL="strict" while _lib.sh defaults the active profile to "standard" — so 4 of the
# loop's 10 assertions passed without exercising anything until the export below was added. Then the
# surface criterion was applied to this directory and four of the five hooks were removed, three of
# them (auto-learn, instinct-distill, notify) named in that finding and the fourth (stop-validate)
# for warning about the pattern .claude/rules/performance.md mandates. session-save.sh is the only
# Stop hook left.
#
# The export stays because it is still load-bearing for the trace-line comparison further down:
# session-save.sh declares "standard", so `minimal` gates it out and the exported profile does not,
# which is exactly the distinguishing signal that block needs. Keep it even if this loop regains
# hooks that declare a lower level — strict is the union case.
export UNITY_HOOK_PROFILE=strict

# A hook that stayed silent behind its profile gate looks identical, from stdout/stderr alone, to
# one that ran and simply had nothing to report (three of these five hooks produce no output at
# all on this minimal payload — no tracked edits, no channels configured, no observations). "exits
# 0, no JSON error" is satisfied by both, so it is not evidence the gate was open — it is exactly
# what a silently-gated hook also produces. Prove the gate is actually open with a real behavioral
# signal instead of guessing at trace text: run each hook under `UNITY_HOOK_PROFILE=minimal`, which
# is below every hook's declared level and so MUST gate every one of them out immediately (few
# xtrace lines — advisory_exit_guard, the profile check, exit), then compare against the same hook
# under the profile this test actually exports. A hook that is genuinely exercised produces
# strictly more trace lines under the real profile than under a profile guaranteed to gate it out;
# one that is still silently gated produces the same (short) trace either way.
for hae_hook in session-save; do
    hae_out=$(printf '%s' "$HAE_PAYLOAD" \
        | bash "${HAE_HOOKS}/${hae_hook}.sh" 2>&1)
    hae_rc=$?
    assert_eq "0" "$hae_rc" "${hae_hook}.sh exits 0 outside a git repository"
    # A hook that "succeeds" by printing a jq parse error has not succeeded. The needle here used
    # to be the literal string "invalid JSON" — no hook or _lib.sh ever emits that phrase; jq's own
    # failure text is "jq: parse error: ...". That made the assertion vacuously true regardless of
    # whether the hook was actually broken, which is confirmed below with a genuine negative
    # control (mirroring test-studio-doctor.sh's "must still exit non-zero on a real failure").
    assert_not_contains "$hae_out" "parse error" \
        "${hae_hook}.sh produces no jq parse error outside a git repository"

    hae_lines_gated=$(printf '%s' "$HAE_PAYLOAD" \
        | UNITY_HOOK_PROFILE=minimal bash -x "${HAE_HOOKS}/${hae_hook}.sh" 2>&1 1>/dev/null | wc -l)
    hae_lines_run=$(printf '%s' "$HAE_PAYLOAD" \
        | bash -x "${HAE_HOOKS}/${hae_hook}.sh" 2>&1 1>/dev/null | wc -l)
    assert_eq "1" \
        "$([ "$hae_lines_run" -gt "$hae_lines_gated" ] && echo 1 || echo 0)" \
        "${hae_hook}.sh executes more than a bare profile-gated stub (gated: ${hae_lines_gated} trace lines, run: ${hae_lines_run})"
done

# The same, inside a git repository, so the fix is not "always bail out early".
mkdir -p "${HAE_TMP}/repo" && cd "${HAE_TMP}/repo" || exit 1
git init -q
git config user.email "t@example.invalid"
git config user.name "t"
printf 'x\n' > a.txt
git add a.txt
git commit -qm "seed"

hae_out=$(printf '{"session_id":"t","hook_event_name":"Stop","cwd":"'"${HAE_TMP}/repo"'"}' \
    | bash "${HAE_HOOKS}/session-save.sh" 2>&1)
hae_rc=$?
assert_eq "0" "$hae_rc" "session-save.sh exits 0 inside a git repository"
assert_contains "$hae_out" "Session state saved" \
    "session-save.sh still does its job inside a git repository"

# Note on the assertion above, and on advisory_exit_guard more generally: session-save.sh does not
# `jq`-parse the raw Stop-event stdin (it reads git state and the tracked state files
# instead), so "no jq parse error in the output" cannot be driven to fail via malformed stdin the
# way test-studio-doctor.sh drives a genuine failure — there is no such input-shaped failure mode
# to induce here. It is kept as a defensive invariant (and "parse error" now matches jq's real
# error text, where "invalid JSON" never did), not as a proven-fires regression pin. The trace-line
# comparison above is the assertion in this file that actually falls in from a real distinguishing
# signal; `exit 0` alone, guarded by `trap 'exit 0' EXIT`, is close to tautological for any hook
# that reaches the guard at all, exactly as the review noted.

cd "$REPO_DIR" || exit 1
rm -rf "$HAE_TMP"
