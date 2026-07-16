#!/usr/bin/env bash
# ============================================================================
# instinct-capture.sh — TRACKING HOOK (strict profile)
# PostToolUse hook that captures lightweight observations for the instinct
# system. Runs on every tool use but must stay <50ms.
#
# Observation format (JSONL, one per line):
#   {
#     "ts": "2026-04-24T12:34:56Z",
#     "project": "<12-char git-remote hash>",
#     "tool": "Edit|Write|Bash|Read|...",
#     "file": "Assets/Scripts/Player.cs",   # empty if not file-scoped
#     "suffix": ".cs",                        # derived
#     "path_tag": "view|system|model|sobject|mono|editor|test|other",
#     "warning_count": 0                      # hook warnings at time of capture
#   }
#
# Observations are distilled at Stop by instinct-distill.sh into instincts.
# ============================================================================
# Trigger: PostToolUse (all tools)
# Exit:    0 always
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="strict"
source "${SCRIPT_DIR}/_lib.sh"

mkdir -p "$UNITY_INSTINCTS_DIR"

INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Skip if no tool (malformed) or a no-op tool we don't care about
case "$TOOL" in
    ""|TodoWrite|TaskCreate|TaskUpdate|TaskList|TaskGet) exit 0 ;;
esac

SUFFIX=""
PATH_TAG="other"
if [ -n "$FILE" ]; then
    SUFFIX=".${FILE##*.}"
    # If no extension present, ${FILE##*.} equals $FILE; clear SUFFIX then.
    if [ "$SUFFIX" = ".$FILE" ]; then SUFFIX=""; fi

    # Classify Unity path role
    case "$FILE" in
        */Editor/*)                                PATH_TAG="editor" ;;
        */Tests/*|*/Test/*)                        PATH_TAG="test" ;;
        *View.cs)                                  PATH_TAG="view" ;;
        *System.cs|*Service.cs)                    PATH_TAG="system" ;;
        *Model.cs)                                 PATH_TAG="model" ;;
        *Config.cs|*Definition.cs|*Data.cs)        PATH_TAG="sobject" ;;
        *Controller.cs|*Manager.cs|*Handler.cs|*Behaviour.cs) PATH_TAG="mono" ;;
        *.cs)                                      PATH_TAG="cs-other" ;;
        *.unity)                                   PATH_TAG="scene" ;;
        *.prefab)                                  PATH_TAG="prefab" ;;
        *.asset|*.mat|*.anim|*.controller)         PATH_TAG="unity-asset" ;;
        *.meta)                                    PATH_TAG="meta" ;;
        *.asmdef)                                  PATH_TAG="asmdef" ;;
    esac
fi

# Warning count at time of capture (lets us see whether this tool-use raised flags)
WARN_COUNT=0
if [ -f "$UNITY_WARNINGS_FILE" ]; then
    WARN_COUNT=$(wc -l < "$UNITY_WARNINGS_FILE" | tr -d ' ')
fi

PROJECT_HASH="$(unity_project_hash)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Emit observation (jq builds a valid line atomically)
jq -cn \
    --arg ts "$TS" \
    --arg project "$PROJECT_HASH" \
    --arg tool "$TOOL" \
    --arg file "$FILE" \
    --arg suffix "$SUFFIX" \
    --arg path_tag "$PATH_TAG" \
    --argjson warning_count "$WARN_COUNT" \
    '{ts:$ts, project:$project, tool:$tool, file:$file, suffix:$suffix, path_tag:$path_tag, warning_count:$warning_count}' \
    >> "$UNITY_OBSERVATIONS_FILE"

exit 0
