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

for hae_hook in session-save auto-learn instinct-distill notify stop-validate; do
    hae_out=$(printf '%s' "$HAE_PAYLOAD" \
        | bash "${HAE_HOOKS}/${hae_hook}.sh" 2>&1)
    hae_rc=$?
    assert_eq "0" "$hae_rc" "${hae_hook}.sh exits 0 outside a git repository"
    # A hook that "succeeds" by printing a jq parse error has not succeeded.
    assert_not_contains "$hae_out" "invalid JSON" \
        "${hae_hook}.sh produces no jq parse error outside a git repository"
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

cd "$REPO_DIR" || exit 1
rm -rf "$HAE_TMP"
