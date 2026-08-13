#!/usr/bin/env bash
# ============================================================================
# block-legacy-input.sh — BLOCKING HOOK
# Blocks the legacy Input Manager API (Input.GetKey / GetAxis / GetButton /
# mousePosition / touches) in first-party runtime code.
#
# rules/unity-specifics.md has said "Legacy Input.GetKey/Input.GetAxis is
# BLOCKED by hooks" since before this toolkit existed. No such hook existed —
# not here, not in everything-claude-unity v1.5.0. Three rule files asserted a
# guarantee that nothing enforced. This is that hook.
#
# The New Input System is mandatory because legacy input cannot see gamepad
# rebinding, device switching, or action maps — the things pc-console.md
# requires and console cert expects.
# ============================================================================
# Trigger: PreToolUse on Edit|Write
# Exit: 2 = block, 0 = allow
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="minimal"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty')

case "$FILE_PATH" in
    *.cs) ;;
    *) exit 0 ;;
esac
[ -n "$NEW_CONTENT" ] || exit 0

# Third-party code is not ours to fix. A real project can carry hundreds of
# vendored files that use legacy input (Feel/MoreMountains alone ships 16), and
# a hook that fires on them blocks edits you must never make anyway — it trains
# you to ignore the hook.
case "$FILE_PATH" in
    */Assets/Extensions/*|*/Assets/Plugins/*|*/Assets/ThirdParty/*|*/Assets/PlayerPrefsEditor/*|*/Packages/*|*/Library/*)
        exit 0 ;;
esac

# Editor and test code is not runtime code, which is the scope this hook's header claims and
# the scope HOOK-REFERENCE.md documents. The two entries are not equally solid and the
# difference is worth knowing before either is widened:
#
#   Editor/  — Unity's own semantics. A folder named Editor at any depth compiles into the
#              Editor assembly and is excluded from every player build, so legacy input there
#              cannot ship. guard-editor-runtime.sh (removed 2026-08-13) skipped the same
#              paths for the same reason.
#   Tests/   — convention only. Unity excludes TEST ASSEMBLIES from builds, not folders
#              called Tests; a Tests/ folder with no test asmdef compiles into the runtime
#              assembly and does ship. This entry trades a real hole for a false-positive
#              class, and it is the one to revisit first if a legacy-input call is ever found
#              shipping from a path this hook waved through.
case "$FILE_PATH" in
    Editor/*|*/Editor/*|Tests/*|*/Tests/*)
        exit 0 ;;
esac

# LEGACY_API is the call itself; LEGACY is the call in a position where it IS that call.
# Without a left boundary, `Input\.` matched inside any identifier ending in "Input" —
# MyInput.GetKey, XRInput.GetAxis, SteamInput.GetButton, a project's own GameInput facade —
# none of which are the legacy Input Manager. The boundary is written as an explicit
# character class rather than \b: \b is a GNU extension and .claude/UPSTREAM plans a macOS
# host pass, where grep is BSD. `UnityEngine.Input.GetKey` still matches, because `.` is not
# a word character and so is a boundary.
LEGACY_API='Input\.(GetKey|GetKeyDown|GetKeyUp|GetAxis|GetAxisRaw|GetButton|GetButtonDown|GetButtonUp|GetMouseButton|GetMouseButtonDown|GetMouseButtonUp|mousePosition|mouseScrollDelta|touches|touchCount|GetTouch|anyKey|anyKeyDown)'
LEGACY='(^|[^A-Za-z0-9_])'"$LEGACY_API"

grep -qE "$LEGACY" <<< "$NEW_CONTENT" || exit 0

# A correctly-authored dual path is not a violation — it is the fix. Code that
# guards its legacy branch behind ENABLE_LEGACY_INPUT_MANAGER (and reads the new
# system under ENABLE_INPUT_SYSTEM) works on both, which is exactly what you want
# in editor-only tooling that must survive either project setting.
if grep -qE '#if\s+(ENABLE_LEGACY_INPUT_MANAGER|UNITY_EDITOR)' <<< "$NEW_CONTENT" \
   && grep -qE 'ENABLE_INPUT_SYSTEM' <<< "$NEW_CONTENT"; then
    exit 0
fi

# Two greps: the first finds the calls in a real call position, the second strips the
# boundary character the first had to consume so the report reads `Input.GetKey`, not
# `(Input.GetKey`. Neither exits early — `grep -o` must read to the end to print every
# match — so this pipeline cannot SIGPIPE its writer under pipefail.
FOUND=$(echo "$NEW_CONTENT" | grep -oE "$LEGACY" | grep -oE "$LEGACY_API" | sort -u | tr '\n' ' ')

echo "" >&2
echo "  File: $FILE_PATH" >&2
echo "  Legacy Input Manager API: $FOUND" >&2
echo "" >&2
echo "  The New Input System is mandatory (rules/unity-specifics.md). Legacy input cannot" >&2
echo "  do rebinding, device switching, or action maps — all of which pc-console.md requires." >&2
echo "" >&2
echo "  Instead:" >&2
echo "    - Read input in an InputView via generated PlayerControls (see the input-system skill)" >&2
echo "    - Systems take SetMoveInput(Vector2) / Jump() — they never learn the device" >&2
echo "" >&2
echo "  Genuinely need both (editor-only tooling)? Guard each branch:" >&2
echo "    #if ENABLE_INPUT_SYSTEM" >&2
echo "        if (Keyboard.current.f9Key.wasPressedThisFrame) ..." >&2
echo "    #endif" >&2
echo "    #if ENABLE_LEGACY_INPUT_MANAGER" >&2
echo "        if (Input.GetKeyDown(KeyCode.F9)) ..." >&2
echo "    #endif" >&2
unity_hook_block "Legacy Input Manager API in first-party runtime code: $FOUND"
