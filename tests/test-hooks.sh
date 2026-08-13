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
