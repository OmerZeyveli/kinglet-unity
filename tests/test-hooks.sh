#!/usr/bin/env bash
# ============================================================================
# test-hooks.sh — Tests for individual hook scripts
# Feeds mock JSON payloads to hooks and verifies exit codes and output.
# ============================================================================

HOOKS_DIR="${REPO_DIR}/.claude/hooks"

# --- Helper: run a hook with a JSON payload ---
run_hook() {
    local hook_script="$1"
    local json_payload="$2"
    local extra_env="${3:-}"

    local exit_code=0
    if [ -n "$extra_env" ]; then
        OUTPUT=$(echo "$json_payload" | env $extra_env bash "$HOOKS_DIR/$hook_script" 2>&1) || exit_code=$?
    else
        OUTPUT=$(echo "$json_payload" | bash "$HOOKS_DIR/$hook_script" 2>&1) || exit_code=$?
    fi
    echo "$exit_code|$OUTPUT"
}

# --- block-scene-edit.sh ---

# Should block .unity file edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scenes/Main.unity","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "block-scene-edit.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "2" "$EXIT_CODE" "block-scene-edit blocks .unity files"

# Should block .prefab file edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Prefabs/Player.prefab","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "block-scene-edit.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "2" "$EXIT_CODE" "block-scene-edit blocks .prefab files"

# Should allow .cs file edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scripts/Player.cs","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "block-scene-edit.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "0" "$EXIT_CODE" "block-scene-edit allows .cs files"

# --- block-meta-edit.sh ---

# Should block .meta file edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scripts/Player.cs.meta","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "block-meta-edit.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "2" "$EXIT_CODE" "block-meta-edit blocks .meta files"

# Should allow non-.meta file edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scripts/Player.cs","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "block-meta-edit.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "0" "$EXIT_CODE" "block-meta-edit allows .cs files"

# --- guard-project-config.sh ---

# Should block .editorconfig edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":".editorconfig","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "guard-project-config.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "2" "$EXIT_CODE" "guard-project-config blocks .editorconfig"

# Should block .ruleset edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/custom.ruleset","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "guard-project-config.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "2" "$EXIT_CODE" "guard-project-config blocks .ruleset files"

# Should block .csproj with NoWarn changes
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assembly.csproj","old_string":"foo","new_string":"<NoWarn>CS0168</NoWarn>"}}'
RESULT=$(run_hook "guard-project-config.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "2" "$EXIT_CODE" "guard-project-config blocks .csproj NoWarn edits"

# Should allow .csproj without analyzer changes
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assembly.csproj","old_string":"foo","new_string":"<TargetFramework>net6.0</TargetFramework>"}}'
RESULT=$(run_hook "guard-project-config.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "0" "$EXIT_CODE" "guard-project-config allows .csproj non-analyzer edits"

# Should allow normal C# file edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scripts/Player.cs","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "guard-project-config.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "0" "$EXIT_CODE" "guard-project-config allows .cs files"

# --- track-edits.sh ---

TEMP_STATE="/tmp/unity-claude-hooks"

# Should exit 0 and track the edit
rm -f "${TEMP_STATE}/session-edits.txt"
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scripts/Player.cs","old_string":"a","new_string":"b"}}'
RESULT=$(run_hook "track-edits.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "0" "$EXIT_CODE" "track-edits exits 0"

# track-reads.sh, cost-tracker.sh and notify.sh were asserted here until 2026-08-13 and are gone:
# the first two declared HOOK_PROFILE_LEVEL="strict" while nothing sets UNITY_HOOK_PROFILE, so their
# assertions were measuring the profile gate rather than the hook, and notify.sh was opt-in behind
# UNITY_NOTIFY_ENABLED. Their absence is enforced by provenance-skip.tsv, not by this file.
#
# What this file cannot see, and never could: whether a hook is registered on the right event, or
# registered at all. tests/test-derived-counts.sh owns that set identity.

# ============================================================================
# THE KILL SWITCH REACHES EVERY HOOK -- derived from the directory, not from a list.
#
# `DISABLE_UNITY_HOOKS=1` is sold as "bypass ALL hooks" in five shipped places. It was false for
# fifteen months: `session-brief.sh` sourced nothing, so it honoured neither switch, and it is the
# hook that injects the whole `using-kinglet` skill into every session -- the most likely reason
# anyone sets the variable. Nothing here or anywhere else noticed, because every guard read the
# hooks that DO source `_lib.sh`.
#
# There are exactly two legal mechanisms and this asserts the union, per hook, by name:
#   (a) source `_lib.sh`, which checks both switches; or
#   (b) check both switches inline.
# A new hook that does neither is named in the failure, which is the shape the original defect had.
#
# MATCHED ON CODE, NOT ON THE NAME. Comment lines are stripped before the match, and the inline arm
# requires the parameter-expansion form rather than the bare word. `session-brief.sh`'s own header
# now explains the switches at length, so a needle of `DISABLE_UNITY_HOOKS` alone would be satisfied
# by prose describing a check that had been deleted -- a probe whose subject can satisfy it by
# talking about itself.
KS_BAD=""
KS_SEEN=0
#
# `[ -f ]` before anything else, and it is not defensive noise: `nullglob` is unset here, so an empty
# or renamed hooks directory leaves the literal `*.sh` in the loop variable. Measured with the
# directory emptied, WITHOUT this line: KS_SEEN read 1, the anti-vacuity assertion below passed, and
# the guard reported a hook named `*.sh` honouring nothing. The class was still caught, by the wrong
# assertion, with a nonsense name -- which is the failure mode the anti-vacuity check exists to make
# legible.
for ks_h in "$HOOKS_DIR"/*.sh; do
    [ -f "$ks_h" ] || continue
    ks_b="$(basename "$ks_h")"
    [ "$ks_b" = "_lib.sh" ] && continue
    KS_SEEN=$((KS_SEEN + 1))
    ks_code=$(awk '!/^[[:space:]]*#/' "$ks_h")
    ks_lib=no; ks_global=no; ks_perhook=no
    grep -qE 'source[[:space:]]+"?\$\{?SCRIPT_DIR\}?/_lib\.sh"?' <<< "$ks_code" && ks_lib=yes
    grep -qF 'DISABLE_UNITY_HOOKS:-' <<< "$ks_code" && ks_global=yes
    grep -qF 'DISABLE_HOOK_' <<< "$ks_code" && ks_perhook=yes
    if [ "$ks_lib" = yes ]; then
        continue
    fi
    if [ "$ks_global" = yes ] && [ "$ks_perhook" = yes ]; then
        continue
    fi
    KS_BAD="${KS_BAD}${ks_b} (sources _lib.sh: $ks_lib, inline global: $ks_global, inline per-hook: $ks_perhook)"$'\n'
done

# Anti-vacuity first: run this against a tree with no hooks and the loop body never executes, so
# KS_BAD is empty and the assertion below passes having read nothing.
assert_eq "yes" "$([ "$KS_SEEN" -ge 1 ] && echo yes || echo no)" \
    "the kill-switch sweep found hook files to read ($KS_SEEN)"

if [ -n "$KS_BAD" ]; then
    printf '%s' "$KS_BAD" | sed 's|^|     honours neither kill switch by either mechanism: |'
fi
assert_eq "0" "$(printf '%s' "$KS_BAD" | grep -c . || true)" \
    "every hook honours DISABLE_UNITY_HOOKS and DISABLE_HOOK_<NAME>, by _lib.sh or inline"

# And the one hook with the inline copy, behaviourally -- because the structural check above cannot
# tell a working check from a misspelled one. `session-brief.sh` prints unconditionally when the
# skill file exists, so the baseline is non-empty and the probe is not measuring silence twice.
KS_BASE=$(CLAUDE_PROJECT_DIR="$REPO_DIR" bash "$HOOKS_DIR/session-brief.sh" 2>&1 | grep -c . || true)
KS_OFF_ALL=$(CLAUDE_PROJECT_DIR="$REPO_DIR" DISABLE_UNITY_HOOKS=1 bash "$HOOKS_DIR/session-brief.sh" 2>&1 | grep -c . || true)
KS_OFF_ONE=$(CLAUDE_PROJECT_DIR="$REPO_DIR" DISABLE_HOOK_SESSION_BRIEF=1 bash "$HOOKS_DIR/session-brief.sh" 2>&1 | grep -c . || true)

assert_eq "yes" "$([ "$KS_BASE" -ge 1 ] && echo yes || echo no)" \
    "session-brief prints the brief with no switch set ($KS_BASE lines) — the probe below is not comparing silence with silence"
assert_eq "0" "$KS_OFF_ALL" "DISABLE_UNITY_HOOKS=1 silences session-brief"
assert_eq "0" "$KS_OFF_ONE" "DISABLE_HOOK_SESSION_BRIEF=1 silences session-brief"
