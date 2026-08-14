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
#
# THE LIST USED TO END `|*/Packages/*|*/Library/*`, AND THOSE TWO SWITCHED THE GATE OFF FOR WHOLE
# PROJECTS. Same shape as the 2026-08-13 */Tests/* and */Editor/* defect fixed below, reached by a
# different route: the four Assets/-prefixed entries are anchored by that segment, but Packages/ and
# Library/ are SIBLINGS of Assets/ at the project root and this hook is handed an absolute path with
# no idea where that root is. Measured 2026-08-15, all with an unguarded Input.GetKeyDown:
#
#   /home/dev/MyGame/Assets/Scripts/Player.cs                   rc=2  794 B   blocked, correct
#   /home/dev/Projects/Packages/Game/Assets/Scripts/Player.cs   rc=0    0 B   ALLOWED, wrong
#   /home/dev/Library/MyGame/Assets/Scripts/Player.cs           rc=0    0 B   ALLOWED, wrong
#
# ~/Library/ is a standard location on macOS — iCloud Drive lives at ~/Library/Mobile Documents/ —
# and .claude/UPSTREAM plans a macOS host pass, so the second row is not a contrived path.
#
# THE ANCHOR THAT REPLACES THEM IS `/Assets/` ITSELF. In a Unity project every first-party runtime
# file has that segment and package content under <root>/Packages/ and <root>/Library/PackageCache/
# does not, so keying on its PRESENCE classifies all five measured rows correctly where keying on the
# ABSENCE of two unanchored names classified two of them backwards.
#
# TWO CASES THE ANCHOR CANNOT DECIDE FROM THE PATH ALONE. Both are decided here on purpose, because
# leaving either undecided is what produced this finding:
#
#   1. A PACKAGE THAT SHIPS ITS OWN Assets/ FOLDER — <root>/Packages/com.foo/Assets/X.cs — IS TREATED
#      AS FIRST-PARTY AND IS BLOCKED. It is character-for-character the same shape as a checkout kept
#      under a directory named Packages (*/Packages/<anything>/Assets/*), so no pattern can separate
#      them without knowing the project root. The two errors are not equally bad: blocking a rare
#      vendored file is noise the author can see and switch off per-hook, while allowing a whole
#      project is a gate that is silently dead. So the tie is broken towards acting.
#      The Library/PackageCache/ half of the same case IS separable and is skipped below.
#   2. A PATH WITH NO /Assets/ SEGMENT AT ALL — <root>/Packages/com.foo/Runtime/X.cs,
#      <root>/Library/**, a build script beside the project — IS SKIPPED. Unity compiles first-party
#      runtime code out of Assets/, and "first-party runtime code" is the scope this file's header
#      and HOOK-REFERENCE.md both claim. This is a widening: /home/dev/MyGame/Tools/Gen.cs blocked
#      before (rc=2, 782 B) and is skipped now.
#
# `Assets/*` sits beside `*/Assets/*` so a project-relative payload keeps the gate rather than losing
# it. Claude Code sends absolute paths, so it should never be reached; if it is, the fail-safe
# direction for THIS clause is to act, since the failure being repaired here is a silent skip.
case "$FILE_PATH" in
    # Vendored trees inside the project's own asset tree, anchored by the Assets/ segment.
    */Assets/Extensions/*|*/Assets/Plugins/*|*/Assets/ThirdParty/*|*/Assets/PlayerPrefsEditor/*)
        exit 0 ;;
    # Unity's package cache. TWO generated segments in sequence, which is what makes this one
    # genuinely anchored where a bare */Library/* was not: `Library/PackageCache` is created by
    # Unity inside a project and nothing keeps a checkout above it (macOS's own ~/Library has no
    # PackageCache child; Unity's global cache is ~/Library/Unity/cache). Listed before the
    # first-party branch so a cached package carrying its own Assets/ folder is still skipped.
    */Library/PackageCache/*)
        exit 0 ;;
    # First-party shape — fall through to the gate.
    Assets/*|*/Assets/*) ;;
    # No Assets/ segment: package code, Library/, or outside the asset tree entirely. See 2 above.
    *)
        exit 0 ;;
esac

# Editor and test code is not runtime code, which is the scope this hook's header claims and
# the scope HOOK-REFERENCE.md documents.
#
# What makes the exemption sound is the ASSEMBLY, not the folder name, and this toolkit ships
# the layout that ties the two together. .claude/skills/assembly-definitions/SKILL.md requires
# editor-only code to live in a separate Editor assembly and spells out the mechanism —
# `"includePlatforms": ["Editor"]`, described there as "this assembly is excluded from builds
# entirely" — and its Recommended Structure puts test code under `Assets/Tests/EditMode` and
# `Assets/Tests/PlayMode` with test asmdefs. The folder name is a proxy for the asmdef, and it
# is exactly as good as the project's adherence to that structure; a `Tests/` folder with no
# test asmdef compiles into the runtime assembly and ships.
#
# ANCHORED UNDER Assets/, and that is the whole point of the pattern rather than a detail.
# FILE_PATH is absolute. Unanchored, `*/Tests/*` matched
# `/home/dev/Tests/MyGame/Assets/Scripts/Player.cs` — a checkout kept in an ordinary
# `~/Projects/Tests/` directory — and switched this gate off for EVERY runtime file in that
# project. Measured 2026-08-13, all three of `/home/dev/Tests/…`, `/home/dev/Editor/…` and
# `/Users/dev/Projects/Tests/…` went from blocked to allowed. The third-party skip above was
# already anchored this way; these two now match it.
case "$FILE_PATH" in
    */Assets/Editor/*|*/Assets/*/Editor/*|*/Assets/Tests/*|*/Assets/*/Tests/*)
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
#
# `\s` was here, one line below the comment above that forbids GNU-only atoms — the standard
# stated and then broken in the same file. [[:space:]] is what GNU `\s` matches, and BSD grep
# has it too.
if grep -qE '#if[[:space:]]+(ENABLE_LEGACY_INPUT_MANAGER|UNITY_EDITOR)' <<< "$NEW_CONTENT" \
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
