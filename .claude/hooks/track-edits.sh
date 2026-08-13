#!/usr/bin/env bash
# ============================================================================
# track-edits.sh — TRACKING HOOK (standard profile)
# Records files that have been edited during this session.
#
# ONE reader, and it is the reason this hook survives: session-save.sh, which turns the list into
# the `modified_files` field of the session state that session-restore.sh reads back next session.
# This header listed stop-validate.sh and cost-tracker.sh as readers too; both were removed by the
# 2026-08-13 surface criterion. If session-save.sh ever goes, this hook goes with it — a tracker
# whose only consumer is gone writes a file nothing opens, which is exactly the closed loop that
# criterion removed seven hooks for.
# ============================================================================
# Trigger: PostToolUse on Edit|Write
# Exit: 0 always (tracking only)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -n "$FILE_PATH" ]; then
    unity_track_edit "$FILE_PATH"
fi

exit 0
