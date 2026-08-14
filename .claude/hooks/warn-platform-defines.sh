#!/usr/bin/env bash
# ============================================================================
# warn-platform-defines.sh — WARNING HOOK
# Checks for #if UNITY_PS5 / UNITY_GAMECORE / UNITY_STANDALONE_* etc. without #else fallback.
# Code inside platform defines is silently excluded on other platforms,
# which can cause missing functionality or compilation errors.
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

# Third-party code is not ours to fix — the same list, and the same reasoning, as
# block-legacy-input.sh's: a hook that fires on files you must never edit trains you to ignore
# the hook. This hook shipped without it and its sibling shipped with it.
#
# MEASURED, and this is the whole ground for the clause: on a shipping project of 1417 C# files
# this hook fired 4 times, and all four were under Assets/Extensions/Feel/ — a vendored asset.
# Every fire it has ever been observed to produce was noise.
#
# ANCHORED UNDER Assets/ AND MATCHED AGAINST AN ABSOLUTE PATH, both deliberately.
# `*/Assets/Extensions/*` needs a leading path segment, which is what Claude Code sends; a
# relative `Assets/Extensions/…` does not match it. The anchoring is what stops a checkout kept
# in an ordinary ~/Projects/Plugins/ directory from switching the hook off for the whole
# project — the defect block-legacy-input.sh's Editor/Tests skips were re-anchored for on
# 2026-08-13.
#
# THE LAST TWO ENTRIES WERE NOT ANCHORED AND ARE NOW GONE, in this hook and in the sibling the list
# came from, on 2026-08-15. They were recorded here as a KNOWN HOLE on the day the list was copied,
# on the ground that fixing one hook of a pair leaves the pair disagreeing about what the same list
# means; fixing both is what closes it, and this is that.
#
# `*/Packages/*` and `*/Library/*` are siblings of Assets/ at the project root, and this hook is
# handed a path with no idea where that root is — so a checkout kept under ~/Projects/Packages/ or
# ~/dev/Library/ silenced it for every file in that project, with no error. ~/Library/ is a standard
# location on macOS (iCloud Drive is ~/Library/Mobile Documents/) and .claude/UPSTREAM plans a macOS
# host pass. Measured 2026-08-15 on this hook, `#if UNITY_PS5` with no `#else`:
#
#   /home/dev/MyGame/Assets/Scripts/Player.cs                   443 B   warned, correct
#   /home/dev/Projects/Packages/Game/Assets/Scripts/Player.cs     0 B   SILENT, wrong
#   /home/dev/Library/MyGame/Assets/Scripts/Player.cs             0 B   SILENT, wrong
#
# THE ANCHOR THAT REPLACES THEM IS `/Assets/` ITSELF, and the two cases it cannot decide from the
# path alone are decided the same way in both hooks. block-legacy-input.sh carries the full
# reasoning; the rulings are: a package that ships its own Assets/ folder under <root>/Packages/ is
# treated as FIRST-PARTY and warned about, because it is indistinguishable from a checkout kept under
# a directory called Packages and a dead gate is worse than a noisy one; a path with NO /Assets/
# segment is SKIPPED, because Unity compiles first-party code out of Assets/. The second is a
# widening — /home/dev/MyGame/Tools/Gen.cs warned before (431 B) and is silent now.
# `*/Library/PackageCache/*` stays as an explicit skip because two generated segments in sequence
# really are anchored, and that is the half of the package case that can be separated.
case "$FILE_PATH" in
    # Vendored trees inside the project's own asset tree, anchored by the Assets/ segment.
    */Assets/Extensions/*|*/Assets/Plugins/*|*/Assets/ThirdParty/*|*/Assets/PlayerPrefsEditor/*)
        exit 0 ;;
    # Unity's package cache — before the first-party branch, so a cached package carrying its own
    # Assets/ folder is skipped rather than warned about.
    */Library/PackageCache/*)
        exit 0 ;;
    # First-party shape — fall through to the check. The relative form is here so a project-relative
    # payload keeps the check rather than losing it; Claude Code sends absolute paths.
    Assets/*|*/Assets/*) ;;
    # No Assets/ segment: package code, Library/, or outside the asset tree entirely.
    *)
        exit 0 ;;
esac

CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty')

if [ -z "$CONTENT" ]; then
    exit 0
fi

# Platform-specific defines to check
PLATFORM_DEFINES="UNITY_ANDROID|UNITY_IOS|UNITY_WEBGL|UNITY_STANDALONE_WIN|UNITY_STANDALONE_OSX|UNITY_STANDALONE_LINUX|UNITY_PS4|UNITY_PS5|UNITY_XBOXONE|UNITY_GAMECORE|UNITY_SWITCH"

# Check for platform defines without else
#
# [[:space:]] rather than \s at all four sites below — three greps and the sed. `\s` is a GNU
# extension in BOTH tools, and .claude/UPSTREAM plans a macOS host pass where each is BSD; the
# standard is stated at block-legacy-input.sh's LEGACY pattern. `[[:space:]]` is what GNU
# matches, so the counts and the extracted define list are unchanged.
if grep -qE "#if[[:space:]]+($PLATFORM_DEFINES)" <<< "$CONTENT"; then
    # Count #if UNITY_PLATFORM and #else occurrences
    IF_COUNT=$(echo "$CONTENT" | grep -cE "#if[[:space:]]+($PLATFORM_DEFINES)" || true)
    ELSE_COUNT=$(echo "$CONTENT" | grep -cE "#else|#elif" || true)

    if [ "$IF_COUNT" -gt "$ELSE_COUNT" ]; then
        DEFINES_USED=$(echo "$CONTENT" | grep -oE "#if[[:space:]]+($PLATFORM_DEFINES)" | sed 's/#if[[:space:]]*//' | sort -u | tr '\n' ', ' | sed 's/,$//')
        echo "WARNING: Platform-specific code without #else fallback." >&2
        echo "" >&2
        echo "  File: $FILE_PATH" >&2
        echo "  Defines: $DEFINES_USED" >&2
        echo "" >&2
        echo "  Code inside platform defines is silently excluded on other platforms." >&2
        echo "  Consider adding #else with a fallback or #error for unsupported platforms:" >&2
        echo "" >&2
        echo "    #if UNITY_PS5" >&2
        echo "        // PS5 implementation" >&2
        echo "    #elif UNITY_GAMECORE" >&2
        echo "        // Xbox implementation" >&2
        echo "    #else" >&2
        echo "        // Standalone / other platforms" >&2
        echo "    #endif" >&2
    fi
fi

exit 0
