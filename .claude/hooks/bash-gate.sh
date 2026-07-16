#!/usr/bin/env bash
# ============================================================================
# bash-gate.sh — BLOCKING HOOK (standard profile)
# Destructive Bash gate for Unity projects. First attempt at a destructive
# command is DENIED with an impact list and rollback-plan demand. Second
# attempt proceeds (agent has acknowledged the consequences).
#
# Unity-specific danger patterns (more consequential than in general projects):
#   - rm -rf Library/|Temp/|Logs/|obj/|Build/  -> triggers full reimport,
#                                                  risks GUID corruption
#   - Mass .meta deletion or rename            -> breaks all asset references
#   - Edits to Packages/manifest.json removal   -> silent dependency loss
#   - Edits to ProjectSettings/ wipe            -> render pipeline / input
#                                                  system / quality resets
#   - git reset --hard | git clean -fdx          -> discards Unity-generated
#                                                  artifacts + local work
#   - git push --force to main/master           -> rewrites shared history
#   - PlayerPrefs CLI wipes                     -> loses user save data
# ============================================================================
# Trigger: PreToolUse on Bash
# Exit:    2 = block, 0 = allow
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
    exit 0
fi

BASH_GATE_DENIED="${UNITY_HOOK_STATE_DIR}/bash-gate-denied.txt"
touch "$BASH_GATE_DENIED"

# --- Classify danger ---
DANGER_KIND=""
DANGER_MSG=""

# Unity directory wipes
if echo "$COMMAND" | grep -qE 'rm\s+-[rRf]+\s+.*(Library|Temp|Logs|obj|Build|Builds)/'; then
    DANGER_KIND="unity-dir-wipe"
    DANGER_MSG="Deleting Library/Temp/Logs/obj/Build triggers a full Unity reimport (minutes to hours) and can corrupt GUIDs if done while editor is open."
fi

# .meta deletion/mass-rename
if echo "$COMMAND" | grep -qE '(rm|find).*\.meta'; then
    DANGER_KIND="meta-deletion"
    DANGER_MSG=".meta files hold GUIDs — deleting them silently breaks every reference (scenes, prefabs, ScriptableObjects, AssetReferences)."
fi
if echo "$COMMAND" | grep -qE '(mv|rename).*\.meta'; then
    DANGER_KIND="meta-rename"
    DANGER_MSG="Renaming .meta files without their asset sibling orphans references. Unity will not recover from this automatically."
fi

# ProjectSettings direct mutation
if echo "$COMMAND" | grep -qE '(rm|>|mv|cp)\s+.*ProjectSettings/[A-Za-z]+\.asset'; then
    DANGER_KIND="projectsettings-write"
    DANGER_MSG="Direct mutation of ProjectSettings/*.asset resets render pipeline / input system / tags / quality layers."
fi

# Packages/manifest mutation outside of unity-mcp
if echo "$COMMAND" | grep -qE '(rm|>|truncate).*Packages/(manifest|packages-lock)\.json'; then
    DANGER_KIND="manifest-wipe"
    DANGER_MSG="Rewriting Packages/manifest.json outside unity-mcp drops package entries with no prompt — compiler errors cascade on next reimport."
fi

# git destructive ops
if echo "$COMMAND" | grep -qE 'git\s+reset\s+--hard'; then
    DANGER_KIND="git-reset-hard"
    DANGER_MSG="git reset --hard discards uncommitted edits AND Unity-generated cached artifacts (.asset cache files). Cannot be undone."
fi
if echo "$COMMAND" | grep -qE 'git\s+clean\s+-[fFdDxX]+'; then
    DANGER_KIND="git-clean"
    DANGER_MSG="git clean -fdx deletes untracked files including Library/, potentially .meta files, and local-only assets the team may have asked you to keep."
fi
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--force(\s|$)|git\s+push\s+.*-f(\s|$)'; then
    if echo "$COMMAND" | grep -qE '\b(main|master|develop|release)\b'; then
        DANGER_KIND="git-force-push-protected"
        DANGER_MSG="Force-pushing to a protected branch rewrites shared history — every teammate's local copy becomes inconsistent."
    else
        DANGER_KIND="git-force-push"
        DANGER_MSG="Force push rewrites remote history. If anyone else has pulled this branch, they will need to reset."
    fi
fi

# DB/SQL destructive ops (occasionally used in tooling)
if echo "$COMMAND" | grep -qiE '\b(drop\s+table|truncate\s+table|drop\s+database)\b'; then
    DANGER_KIND="db-destructive"
    DANGER_MSG="Schema-level destructive SQL. Data loss is immediate and irreversible."
fi

# PlayerPrefs wipes
if echo "$COMMAND" | grep -qE 'defaults\s+delete.*unity|PlayerPrefs\.DeleteAll'; then
    DANGER_KIND="playerprefs-wipe"
    DANGER_MSG="Wipes persistent user data (saves, settings). Use targeted DeleteKey unless you specifically intend a full reset."
fi

# If no danger detected, allow silently
if [ -z "$DANGER_KIND" ]; then
    exit 0
fi

# --- Two-stage gate: first attempt denied, second attempt allowed ---
# Key: danger-kind + hash of command (so different commands don't share state)
CMD_HASH=$(echo "$COMMAND" | shasum | awk '{print $1}' | cut -c1-12)
KEY="${DANGER_KIND}:${CMD_HASH}"

if grep -qxF "$KEY" "$BASH_GATE_DENIED" 2>/dev/null; then
    # Second attempt — allow
    exit 0
fi

# First attempt — deny and demand facts
echo "$KEY" >> "$BASH_GATE_DENIED"
unity_track_warning "bash-gate" "$DANGER_KIND"

echo "" >&2
echo "  BashGate — DESTRUCTIVE COMMAND (first attempt blocked)" >&2
echo "  Classification: $DANGER_KIND" >&2
echo "  Command: $COMMAND" >&2
echo "" >&2
echo "  Risk: $DANGER_MSG" >&2
echo "" >&2
echo "  Before retrying, present these facts:" >&2
echo "" >&2
echo "  1. Enumerate exactly what this command will modify or delete." >&2
case "$DANGER_KIND" in
    unity-dir-wipe)
        echo "     - Confirm Unity editor is closed (otherwise reimport may race)." >&2
        echo "     - Note the expected reimport duration." >&2
        ;;
    meta-deletion|meta-rename)
        echo "     - List the asset files these .meta files belong to." >&2
        echo "     - Confirm the sibling assets are being handled identically." >&2
        ;;
    projectsettings-write)
        echo "     - Identify the exact setting being changed." >&2
        echo "     - Confirm unity-mcp tools cannot achieve this instead" >&2
        echo "       (manage_build, manage_physics, manage_graphics)." >&2
        ;;
    manifest-wipe)
        echo "     - List packages that will be removed." >&2
        echo "     - Confirm unity-mcp manage_packages is not the right tool." >&2
        ;;
    git-reset-hard|git-clean)
        echo "     - Run 'git status' first and quote the files at risk." >&2
        echo "     - Confirm no uncommitted Unity work (scenes/prefabs) would be lost." >&2
        ;;
    git-force-push-protected)
        echo "     - This is a SHARED branch. Do not proceed without explicit user approval." >&2
        echo "     - Ask the user directly before retrying." >&2
        ;;
    git-force-push)
        echo "     - Confirm no teammate has pulled this branch." >&2
        ;;
    db-destructive)
        echo "     - Confirm a backup exists and name its location." >&2
        ;;
    playerprefs-wipe)
        echo "     - Confirm this is not production user data." >&2
        ;;
esac
echo "  2. Write a one-line rollback procedure (even if the answer is" >&2
echo "     'restore from git' or 'Unity will reimport')." >&2
echo "  3. Quote the user's instruction that motivates this destructive op." >&2
echo "" >&2
echo "  After presenting these facts, retry the same command — it will pass." >&2
echo "" >&2
unity_hook_block "BashGate: present facts above for '$DANGER_KIND', then retry."
