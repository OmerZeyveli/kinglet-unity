#!/usr/bin/env bash
# ============================================================================
# quality-gate.sh — WARNING HOOK (standard profile)
# Lightweight post-edit quality check for common Unity C# pitfalls.
# Runs after every Edit/Write on C# files and warns about:
#   - GetComponent/FindObjectOfType in Update/FixedUpdate/LateUpdate
#   - Uncached Camera.main
#   - LINQ in gameplay code (outside Editor/)
#   - tag == "string" instead of CompareTag
#   - Null-conditional (?.) on UnityEngine.Object types
#   - Debug.Log without conditional compilation
# ============================================================================
# Trigger: PostToolUse on Edit|Write
# Exit: 0 always (warning only, via stderr)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check C# files
case "$FILE_PATH" in
    *.cs) ;;
    *) exit 0 ;;
esac

# Skip Editor code — different performance requirements
case "$FILE_PATH" in
    */Editor/*|*/editor/*) exit 0 ;;
esac

# Get the content being written/edited
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty')

if [ -z "$CONTENT" ]; then
    exit 0
fi

WARNINGS=""

# --- Check for GetComponent/FindObjectOfType in Update methods ---
# Look for Update-family method signatures in the content
if grep -qE 'void\s+(Update|FixedUpdate|LateUpdate)\s*\(' <<< "$CONTENT"; then
    if grep -qE '(GetComponent|TryGetComponent|FindObjectOfType|FindObjectsOfType|Camera\.main)\b' <<< "$CONTENT"; then
        WARNINGS="${WARNINGS}  - GetComponent/FindObjectOfType/Camera.main detected near Update method. Cache in Awake().\n"
        unity_track_warning "quality-gate" "GetComponent/FindObjectOfType/Camera.main in Update method"
    fi
fi

# --- Check for LINQ usage in gameplay code ---
if grep -qE '\.(Where|Select|Any|All|First|Last|Count|OrderBy|GroupBy|Aggregate|ToList|ToArray|ToDictionary)\s*\(' <<< "$CONTENT"; then
    # Exclude test files
    case "$FILE_PATH" in
        *Tests*|*Test*|*test*) ;;
        *)
            WARNINGS="${WARNINGS}  - LINQ detected in gameplay code. Use manual loops to avoid GC allocations.\n"
            unity_track_warning "quality-gate" "LINQ in gameplay code"
            ;;
    esac
fi

# --- Check for tag == "string" instead of CompareTag ---
if grep -qE '\.tag\s*==\s*"' <<< "$CONTENT"; then
    WARNINGS="${WARNINGS}  - Use CompareTag(\"tag\") instead of .tag == \"tag\" to avoid string allocation.\n"
    unity_track_warning "quality-gate" "tag == string instead of CompareTag"
fi

# --- Check for null-conditional on potential Unity objects ---
if grep -qE '\?\.(enabled|transform|gameObject|name|tag|GetComponent)' <<< "$CONTENT"; then
    WARNINGS="${WARNINGS}  - Null-conditional (?.) on Unity object bypasses destroyed-object detection. Use explicit null check.\n"
    unity_track_warning "quality-gate" "Null-conditional on Unity object"
fi

# --- Check for Debug.Log without conditional ---
if grep -qE 'Debug\.(Log|LogWarning|LogError)\s*\(' <<< "$CONTENT"; then
    if ! grep -qE '#if\s+(UNITY_EDITOR|DEBUG|DEVELOPMENT_BUILD)' <<< "$CONTENT"; then
        if ! grep -qE '\[Conditional\s*\(' <<< "$CONTENT"; then
            WARNINGS="${WARNINGS}  - Debug.Log in production code. Wrap with #if UNITY_EDITOR or use [Conditional(\"UNITY_EDITOR\")] wrapper.\n"
            unity_track_warning "quality-gate" "Debug.Log without conditional compilation"
        fi
    fi
fi

# --- Check for new WaitForSeconds in methods (likely in Update or repeated calls) ---
if grep -qE 'new\s+WaitForSeconds\s*\(' <<< "$CONTENT"; then
    WARNINGS="${WARNINGS}  - new WaitForSeconds() allocates each call. Cache as a field or use UniTask.Delay.\n"
    unity_track_warning "quality-gate" "new WaitForSeconds allocation"
fi

# --- Check for SendMessage/BroadcastMessage ---
if grep -qE '(SendMessage|BroadcastMessage)\s*\(' <<< "$CONTENT"; then
    WARNINGS="${WARNINGS}  - SendMessage/BroadcastMessage uses reflection. Use direct references or MessagePipe.\n"
    unity_track_warning "quality-gate" "SendMessage/BroadcastMessage reflection call"
fi

if [ -n "$WARNINGS" ]; then
    echo "" >&2
    echo "QUALITY: Potential issues in $FILE_PATH:" >&2
    echo -e "$WARNINGS" >&2
fi

exit 0
