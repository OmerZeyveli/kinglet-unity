#!/usr/bin/env bash
# ============================================================================
# test-hook-large-payload.sh — blocking hooks must not fail OPEN on real-sized files.
#
# Every blocking hook tested content with `echo "$VAR" | grep -qE ...` under
# `set -euo pipefail`. `grep -q` exits the instant it matches, without draining
# stdin. `echo` then takes SIGPIPE and exits 141; under pipefail the pipeline
# reports failure, the surrounding `if` reads false, and the hook allows exactly
# what it exists to block.
#
# Measured thresholds (Linux pipe buffer, ~64KB) were 36-60KB for
# block-legacy-input.sh and bash-gate.sh — and macOS's pipe buffer is 16KB, so
# the threshold is lower there. A generated PlayerControls.cs (mandated by this
# toolkit) is routinely over 100KB. Feed both hooks a payload over that size and
# assert they still block. If this test is run against the pre-fix hooks (the
# echo|grep -q shape), it fails — that failure is the point.
# ============================================================================

set -euo pipefail

BLI_HOOK="${REPO_DIR}/.claude/hooks/block-legacy-input.sh"
BG_HOOK="${REPO_DIR}/.claude/hooks/bash-gate.sh"

# Isolate bash-gate's two-stage deny/allow state so this run cannot be affected
# by, or pollute, real repo state (see test-bash-gate-precision.sh for the same
# concern).
THLP_STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hook-large-payload-test.XXXXXX")"
trap 'rm -rf "$THLP_STATE_DIR"' EXIT

# --- Build a >100KB C# file that legitimately uses legacy Input, padded with
# realistic filler (this is what a generated PlayerControls.cs-sized file looks
# like: mostly boilerplate, with the violation buried in the middle). ---
build_large_cs_payload() {
    local filler violation
    filler=""
    local line_no=0
    while [ "${#filler}" -lt 100000 ]; do
        line_no=$((line_no + 1))
        filler="${filler}    // padding line ${line_no} — generated boilerplate, not a violation
"
    done
    violation='    private void Update() {
        if (Input.GetKeyDown(KeyCode.F1)) { ChangeForm(); }
    }
'
    printf 'using UnityEngine;\npublic class Player : MonoBehaviour {\n%s\n%s\n%s\n}\n' \
        "$filler" "$violation" "$filler"
}

LARGE_CS_PAYLOAD="$(build_large_cs_payload)"
LARGE_CS_SIZE="${#LARGE_CS_PAYLOAD}"

bli_verdict() {
    local out rc
    set +e
    out=$(printf '{"tool_input":{"file_path":%s,"new_string":%s}}' \
          "$(printf '%s' "/proj/Assets/Scripts/Player.cs" | jq -Rs .)" \
          "$(printf '%s' "$1" | jq -Rs .)" \
          | bash "$BLI_HOOK" 2>/dev/null)
    rc=$?
    set -e
    printf '%s' "$rc"
}

assert_eq "1" "$([ "$LARGE_CS_SIZE" -gt 100000 ] && echo 1 || echo 0)" \
    "large C# payload is actually over 100KB (${LARGE_CS_SIZE} bytes) — the test proves nothing otherwise"

assert_eq "2" "$(bli_verdict "$LARGE_CS_PAYLOAD")" \
    "block-legacy-input.sh still blocks Input.GetKeyDown in a >100KB file (${LARGE_CS_SIZE} bytes)"

# --- Build a >100KB destructive Bash command: a real `rm -rf Library/` on its
# own line at the FRONT, followed by a huge number of trailing lines (this is
# what a scripted multi-line cleanup step followed by routine logging looks
# like — the reviewer's own repro was a "2000-line command").
#
# The lines matter, not just the size: grep matches per-line, and with NO
# newlines at all (one giant single-line command) grep must read to the very
# end just to find where that one line terminates, regardless of where the
# pattern sits inside it — so a single-line payload never reproduces the bug
# no matter how large. Real newline-separated lines let grep find the match
# and stop after the SHORT first line, while >100KB of unwritten trailing
# lines are still queued behind it — that gap is what turns "grep exits early"
# into "echo gets SIGPIPE while pipefail is watching."
build_large_bash_payload() {
    local lines line_no line
    lines="rm -rf Library/"
    line_no=0
    while [ "${#lines}" -lt 100000 ]; do
        line_no=$((line_no + 1))
        line="echo trailing step ${line_no}: routine, non-destructive logging"
        lines="${lines}
${line}"
    done
    printf '%s' "$lines"
}

LARGE_BASH_PAYLOAD="$(build_large_bash_payload)"
LARGE_BASH_SIZE="${#LARGE_BASH_PAYLOAD}"

bg_verdict() {
    local out rc
    set +e
    out=$(printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" \
          | UNITY_HOOK_STATE_DIR="$THLP_STATE_DIR" bash "$BG_HOOK" 2>/dev/null)
    rc=$?
    set -e
    printf '%s' "$rc"
}

assert_eq "1" "$([ "$LARGE_BASH_SIZE" -gt 100000 ] && echo 1 || echo 0)" \
    "large bash command is actually over 100KB (${LARGE_BASH_SIZE} bytes) — the test proves nothing otherwise"

assert_eq "2" "$(bg_verdict "$LARGE_BASH_PAYLOAD")" \
    "bash-gate.sh still blocks 'rm -rf Library/' inside a >100KB command (${LARGE_BASH_SIZE} bytes)"

echo ""
echo "test-hook-large-payload: hook exit codes above are the assertions — see PASS/FAIL count in overall summary"
