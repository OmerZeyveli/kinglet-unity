#!/usr/bin/env bash
# ============================================================================
# gateguard.sh — BLOCKING HOOK (strict profile)
# Three-stage fact-forcing gate for C# edits: DENY -> FORCE -> ALLOW
#
#   Stage 1 (DENY):  Block first Edit/Write on a C# file. Force investigation.
#   Stage 2 (FORCE): Emit Unity-specific fact demands (callers, GUID refs,
#                    FormerlySerializedAs plan, instruction quote, asmdef).
#   Stage 3 (ALLOW): Second attempt on same file proceeds (presumes the agent
#                    read the deny message and gathered facts).
#
# Also enforces Read-before-Edit and the MVS counterpart heuristic.
# ============================================================================
# Trigger: PreToolUse on Edit|Write|MultiEdit
# Exit:    2 = block, 0 = allow
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="strict"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only gate C# files
case "$FILE_PATH" in
    *.cs) ;;
    *) exit 0 ;;
esac

BASENAME=$(basename "$FILE_PATH" .cs)
DIR=$(dirname "$FILE_PATH")

# --- State tracking: per-file fact-gate progress ---
FACTS_DENIED_FILE="${UNITY_HOOK_STATE_DIR}/gateguard-facts-denied.txt"
FACTS_PASSED_FILE="${UNITY_HOOK_STATE_DIR}/gateguard-facts-passed.txt"
touch "$FACTS_DENIED_FILE" "$FACTS_PASSED_FILE"

# Detect Write (new file) vs Edit (existing) vs MultiEdit
IS_WRITE="false"
if [ "$TOOL_NAME" = "Write" ]; then
    # Write creates new file OR overwrites; treat as new-file gate if file doesn't exist yet
    if [ ! -f "$FILE_PATH" ]; then
        IS_WRITE="true"
    fi
fi

# --- Guard 1: Read-before-Edit (skip for brand-new Write of non-existent file) ---
if [ "$IS_WRITE" = "false" ]; then
    if ! unity_was_read "$FILE_PATH"; then
        unity_track_warning "gateguard" "unread: $FILE_PATH"
        echo "" >&2
        echo "  GateGuard — STAGE 1: You must Read this file before editing." >&2
        echo "  File: $FILE_PATH" >&2
        echo "" >&2
        echo "  The file may contain state, invariants, or attributes you will" >&2
        echo "  destroy with a blind edit." >&2
        unity_hook_block "GateGuard: Read $FILE_PATH before editing."
    fi
fi

# --- Guard 2: Fact-gate (first edit per file emits fact demands) ---
if ! grep -qxF "$FILE_PATH" "$FACTS_PASSED_FILE" 2>/dev/null; then
    # Has this file been denied once already?
    if grep -qxF "$FILE_PATH" "$FACTS_DENIED_FILE" 2>/dev/null; then
        # Second attempt — mark as passed and allow through
        echo "$FILE_PATH" >> "$FACTS_PASSED_FILE"
    else
        # First attempt — DENY and demand facts
        echo "$FILE_PATH" >> "$FACTS_DENIED_FILE"
        unity_track_warning "gateguard" "fact-demand: $FILE_PATH"

        # Classify file to tailor the fact demand
        ROLE=""
        case "$BASENAME" in
            *View)   ROLE="View (MVS)" ;;
            *System) ROLE="System (MVS)" ;;
            *Model)  ROLE="Model (MVS)" ;;
            *Config|*Definition|*Data) ROLE="ScriptableObject" ;;
            *Controller|*Manager|*Handler) ROLE="Behaviour" ;;
        esac

        echo "" >&2
        echo "  GateGuard — STAGE 2 (FACT DEMAND)" >&2
        if [ "$IS_WRITE" = "true" ]; then
            echo "  New file: $FILE_PATH" >&2
            [ -n "$ROLE" ] && echo "  Inferred role: $ROLE" >&2
            echo "" >&2
            echo "  Before creating this file, present these facts:" >&2
            echo "" >&2
            echo "  1. Name the file(s) and line(s) that will reference this new type." >&2
            echo "  2. Confirm no existing type serves the same purpose." >&2
            echo "     Run: grep -rn 'class ${BASENAME}' Assets/" >&2
            echo "  3. Identify the asmdef this file belongs to." >&2
            echo "     Run: find $(dirname "$DIR") -name '*.asmdef' | head -5" >&2
            echo "  4. If it's a System, confirm its VContainer registration plan." >&2
            echo "     If it's a MonoBehaviour, confirm the scene/prefab that will host it." >&2
            echo "  5. Quote the user's current instruction verbatim." >&2
        else
            echo "  File: $FILE_PATH" >&2
            [ -n "$ROLE" ] && echo "  Inferred role: $ROLE" >&2
            echo "" >&2
            echo "  Before editing, present these facts:" >&2
            echo "" >&2
            echo "  1. List files that reference this type (callers, consumers)." >&2
            echo "     Run: grep -rn '${BASENAME}' Assets/ --include='*.cs'" >&2
            echo "  2. List scene/prefab references via GUID from the .meta file." >&2
            echo "     Run: GUID=\$(grep 'guid:' ${FILE_PATH}.meta | awk '{print \$2}')" >&2
            echo "          grep -rln \"\$GUID\" Assets/ --include='*.unity' --include='*.prefab'" >&2
            echo "  3. If renaming ANY [SerializeField] field, state the" >&2
            echo "     [FormerlySerializedAs(\"oldName\")] plan. Without it, every" >&2
            echo "     configured instance silently resets to default." >&2
            echo "  4. If changing public API, list the callers that will need updates." >&2
            echo "  5. Quote the user's current instruction verbatim." >&2
        fi
        echo "" >&2
        echo "  After presenting these facts, retry the same edit — it will pass." >&2
        echo "" >&2
        unity_hook_block "GateGuard: present facts above, then retry the edit."
    fi
fi

# --- Guard 3: MVS counterpart heuristic (advisory, does not block) ---
check_counterpart() {
    local suffix="$1"
    local role="$2"
    local base="${BASENAME%View}"
    base="${base%System}"
    base="${base%Model}"
    local counterpart_name="${base}${suffix}"

    for search_dir in "$DIR" "$(dirname "$DIR")"; do
        local candidate
        candidate=$(find "$search_dir" -name "${counterpart_name}.cs" -maxdepth 3 2>/dev/null | head -1)
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            if ! unity_was_read "$candidate"; then
                echo "  SUGGESTION: Consider reading the ${role} first: ${candidate}" >&2
            fi
            return
        fi
    done
}

case "$BASENAME" in
    *View)
        check_counterpart "Model" "Model"
        check_counterpart "System" "System"
        ;;
    *System)
        check_counterpart "Model" "Model"
        ;;
esac

exit 0
