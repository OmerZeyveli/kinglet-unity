#!/usr/bin/env bash
# ============================================================================
# warn-filename.sh — WARNING HOOK
# Checks that C# file name matches the primary class/struct name.
# Unity requires MonoBehaviour/ScriptableObject file name == class name,
# otherwise the script cannot be attached to GameObjects.
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

# Get the expected class name from file name (without path and extension)
FILENAME=$(basename "$FILE_PATH" .cs)

# Skip test files, editor scripts, and generated files
case "$FILENAME" in
    *Tests|*Test|*.g|*.generated|AssemblyInfo) exit 0 ;;
esac

# Read the file content (from the new_string for Edit, or content for Write)
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty')

if [ -z "$CONTENT" ]; then
    # For Edit, we might need to check the full file — skip if we can't
    exit 0
fi

# Check if the file contains a class/struct matching the filename
# Look for: public/internal/sealed class/struct FileName
#
# POSIX classes, not \s and \b. block-legacy-input.sh states the standard at its own LEGACY
# pattern — "\b is a GNU extension and .claude/UPSTREAM plans a macOS host pass, where grep is
# BSD" — and writes an explicit character class instead. This file used \s and \b anyway, and
# THIS LINE is the one that costs the most if the standard is right: it is the hook's real gate
# (does the file define any type named like the file), so a pattern that stops matching sends
# every call to `exit 0` below and the hook WARNS NOTHING, SILENTLY. It does not error. Not
# measured on BSD — there is no macOS host here — so this is a consistency fix against a written
# standard, not a repair of observed breakage.
#
# \s -> [[:space:]] and \w -> [[:alnum:]_] are exact equivalents of what GNU grep matches.
# \b is a zero-width assertion with no POSIX spelling, so it becomes a CONSUMED boundary
# character class — the same instrument block-legacy-input.sh uses, spelled [^[:alnum:]_] rather
# than its [^A-Za-z0-9_] so that the three replacements agree with each other (\b is exactly a
# transition at the complement of \w). For every C# identifier the two spellings are identical.
#
# $FILENAME is still interpolated raw, and a file whose name carries a regex metacharacter still
# misbehaves — `Foo(1).cs` builds a pattern that matches `class Foo1`, `Foo(.cs` builds an
# invalid one that grep rejects with rc 2 and the `if` reads as "no match". That is a
# PRE-EXISTING defect, deliberately not fixed here: escaping it changes behaviour, and this
# change's whole justification is that it changes none. A C# type name cannot contain a regex
# metacharacter, so the only reachable cases are filenames that could never match a type name
# anyway.
if grep -qE "(class|struct|interface)[[:space:]]+${FILENAME}([^[:alnum:]_]|\$)" <<< "$CONTENT"; then
    exit 0
fi

# Check if there's any MonoBehaviour or ScriptableObject subclass
if grep -qE ':[[:space:]]*(MonoBehaviour|ScriptableObject|NetworkBehaviour|StateMachineBehaviour)' <<< "$CONTENT"; then
    # There IS a Unity component but the name doesn't match.
    # awk (not head) picks the first match — head would stop reading before
    # grep finished writing the rest, risking SIGPIPE on a large file.
    #
    # `|| true` is load-bearing, and the header above is the contract it restores.
    # The guard on the line before proves ONE pattern (`: MonoBehaviour`) and this
    # line runs a DIFFERENT one (`(class|struct)[[:space:]]+[[:alnum:]_]+`), so the match the guard
    # established says nothing about whether this grep matches. An Edit fragment
    # like `    : MonoBehaviour, IDamageable` satisfies the guard and carries no
    # `class` keyword at all: grep exits 1, pipefail propagates it past awk, and
    # because the substitution is the ENTIRE right-hand side of an assignment the
    # assignment carries that status — so `set -e` killed the script here, rc=1
    # with zero bytes written, against a header that promises `Exit: 0 always`.
    # (`set -e` does not reach INTO a command substitution without
    # `inherit_errexit`; what kills it is the assignment's own status.)
    #
    # Same shape and same repair as the four `find … | wc -l` sites in
    # scripts/studio-doctor.sh. The two sibling hooks that look identical do NOT
    # need it, for the reason uninstall.sh does not: warn-platform-defines.sh and
    # block-legacy-input.sh each re-run the very pattern their guard just proved
    # matched, so their grep cannot come back empty.
    #
    # This silences no real failure: an empty CLASS_NAME is the "cannot tell"
    # answer, and the `[ -n "$CLASS_NAME" ]` guard below was already written to
    # print nothing and fall through to `exit 0` when it gets one.
    CLASS_NAME=$(grep -oE '(class|struct)[[:space:]]+[[:alnum:]_]+' <<< "$CONTENT" | awk 'NR==1{print $2}' || true)
    if [ -n "$CLASS_NAME" ] && [ "$CLASS_NAME" != "$FILENAME" ]; then
        echo "WARNING: File name '$FILENAME.cs' does not match class name '$CLASS_NAME'." >&2
        echo "" >&2
        echo "  File: $FILE_PATH" >&2
        echo "" >&2
        echo "  Unity requires MonoBehaviour/ScriptableObject file name to match" >&2
        echo "  the class name. This script won't be attachable to GameObjects." >&2
        echo "" >&2
        echo "  Fix: Rename the file to '$CLASS_NAME.cs' or rename the class to '$FILENAME'." >&2
    fi
fi

exit 0
