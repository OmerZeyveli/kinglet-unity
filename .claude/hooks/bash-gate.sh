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

# A destructive verb only counts where a command can actually start: the beginning of the
# line, or right after a control operator (;, &&, ||, |). Without this anchor, "rm" or "cp"
# matches anywhere those letters occur in unrelated text (inside "notes.txt", inside a JSON
# value, inside another word entirely) and the permissive `.*` that used to follow let any
# amount of intervening text pair a verb with a path it never touched.
#
# A real shell tolerates more than bare start-of-line at a command position, and the first
# cut of this anchor was measured to be too narrow — four genuinely destructive commands
# (leading whitespace, a `sudo`/`env` prefix, a `(` subshell, and a verb reached through
# `xargs`) slipped through as false negatives. CMD_START now also allows:
#   - leading whitespace at the start of the line (common in indented blocks/heredocs)
#   - an opening `(` or `{` (subshell / brace group)
#   - a `sudo`/`env`/`doas`/`nice`/`nohup`/`exec`/`command`/`time` prefix and its own flags
#   - an `xargs` prefix and its own flags — xargs execs its trailing arguments as a command,
#     so a verb reached through it IS in command position for the process that actually runs,
#     even though it is not lexically the first word of the shell line. Deliberately covered
#     here rather than left as a silent gap: the whole point of this fix is a gate that does
#     what its classification claims, and "we don't check xargs" would be exactly that kind
#     of silent gap.
#
# CMD_START also bounds the gap between the verb and its path to `[^;&|]*` — text within the
# same command segment, not across a `;`/`&&`/`||`/`|` into an unrelated command that merely
# happens to mention the path later on the same line.
CMD_PREFIX='((sudo|doas|env|nice|nohup|exec|command|time|xargs)([[:space:]]+[A-Za-z0-9_=./{}-]+)*[[:space:]]+)?'
CMD_START="(^[[:space:]]*|[;&|]+[[:space:]]*|[({][[:space:]]*)${CMD_PREFIX}"
SAME_CMD='[^;&|]*'

# Unity directory wipes
if grep -qE "${CMD_START}rm[[:space:]]+-[rRf]+[[:space:]]+${SAME_CMD}(Library|Temp|Logs|obj|Build|Builds)/" <<< "$COMMAND"; then
    DANGER_KIND="unity-dir-wipe"
    DANGER_MSG="Deleting Library/Temp/Logs/obj/Build triggers a full Unity reimport (minutes to hours) and can corrupt GUIDs if done while editor is open."
fi

# .meta deletion/mass-rename — verb must start a command; path must be its argument.
#
# `rm` and `find` were one alternation here, and that made every `find` naming `.meta` a
# deletion. `find` is a search verb: on its own it prints paths and changes nothing.
# Measured 2026-08-13 — `find Assets -name "*.meta" | wc -l`, a count, was classified
# meta-deletion and blocked. Command position was never the problem for this pattern; the
# verb was. `find` deletes only through an action, so require one: -delete, -exec/-execdir/-ok
# rm, or a pipe into xargs rm. The action is looked for anywhere in the command rather than
# inside SAME_CMD, because `find … | xargs rm` puts it in the *next* segment by construction.
DELETE_ACTION='(-delete([[:space:]]|$)|-(exec|execdir|ok)[[:space:]]+rm|xargs[^;&|]*[[:space:]]rm([[:space:]]|$))'

if grep -qE "${CMD_START}rm[[:space:]]+${SAME_CMD}\.meta" <<< "$COMMAND"; then
    DANGER_KIND="meta-deletion"
    DANGER_MSG=".meta files hold GUIDs — deleting them silently breaks every reference (scenes, prefabs, ScriptableObjects, AssetReferences)."
fi
if grep -qE "${CMD_START}find[[:space:]]+${SAME_CMD}\.meta" <<< "$COMMAND" \
    && grep -qE "$DELETE_ACTION" <<< "$COMMAND"; then
    DANGER_KIND="meta-deletion"
    DANGER_MSG=".meta files hold GUIDs — deleting them silently breaks every reference (scenes, prefabs, ScriptableObjects, AssetReferences)."
fi
if grep -qE "${CMD_START}(mv|rename)[[:space:]]+${SAME_CMD}\.meta" <<< "$COMMAND"; then
    DANGER_KIND="meta-rename"
    DANGER_MSG="Renaming .meta files without their asset sibling orphans references. Unity will not recover from this automatically."
fi

# ProjectSettings direct mutation.
# `rm`/`mv`/`cp` are commands — anchor them to a command position. `>`/`>>` is a redirect
# operator, not a command word, so it cannot be anchored the same way; instead its target
# must follow immediately (only whitespace, no permissive gap at all), which is exactly how
# a shell redirect actually reads its destination.
if grep -qE "${CMD_START}(rm|mv|cp)[[:space:]]+${SAME_CMD}ProjectSettings/[A-Za-z]+\.asset" <<< "$COMMAND" \
    || grep -qE '>{1,2}[[:space:]]*ProjectSettings/[A-Za-z]+\.asset' <<< "$COMMAND"; then
    DANGER_KIND="projectsettings-write"
    DANGER_MSG="Direct mutation of ProjectSettings/*.asset resets render pipeline / input system / tags / quality layers."
fi

# Packages/manifest mutation outside of unity-mcp — same split: command verbs anchored,
# redirect target immediate.
if grep -qE "${CMD_START}(rm|mv|truncate)[[:space:]]+${SAME_CMD}Packages/(manifest|packages-lock)\.json" <<< "$COMMAND" \
    || grep -qE '>{1,2}[[:space:]]*Packages/(manifest|packages-lock)\.json' <<< "$COMMAND"; then
    DANGER_KIND="manifest-wipe"
    DANGER_MSG="Rewriting Packages/manifest.json outside unity-mcp drops package entries with no prompt — compiler errors cascade on next reimport."
fi

# git destructive ops
#
# These three matched their verb ANYWHERE in the command string, which is why the gate
# blocked the discussion of a destructive command as readily as the command. Measured
# 2026-08-13: `echo "never run git reset --hard here"` and
# `git commit -m "docs: warn about git reset --hard"` were both blocked. Anchor them to a
# command position with the same CMD_START this file already uses for its verb patterns.
#
# Deliberately NOT using the permissive SAME_CMD gap between `git` and its subcommand: the
# commit-message case has `git` in real command position, so `git${SAME_CMD}reset` would
# match `git commit -m "… about git reset --hard"` and re-open the exact defect. The words
# allowed between them are flag-shaped only.
#
# `git -C <dir>` and `git -c key=value` are the two option forms that legitimately sit
# before a subcommand. Allowing them closes a false negative (`git -C /repo reset --hard`
# was permitted) without re-opening the prose one — prose reaching `reset --hard` has
# ordinary words in that gap, not flags.
GIT_OPTS='([[:space:]]+-[cC][[:space:]]*[^[:space:];&|]+)*'

if grep -qE "${CMD_START}git${GIT_OPTS}[[:space:]]+reset[[:space:]]+--hard" <<< "$COMMAND"; then
    DANGER_KIND="git-reset-hard"
    DANGER_MSG="git reset --hard discards uncommitted edits AND Unity-generated cached artifacts (.asset cache files). Cannot be undone."
fi
if grep -qE "${CMD_START}git${GIT_OPTS}[[:space:]]+clean[[:space:]]+-[fFdDxX]+" <<< "$COMMAND"; then
    DANGER_KIND="git-clean"
    DANGER_MSG="git clean -fdx deletes untracked files including Library/, potentially .meta files, and local-only assets the team may have asked you to keep."
fi
if grep -qE "${CMD_START}git${GIT_OPTS}[[:space:]]+push${SAME_CMD}(--force|-f)([[:space:]]|$)" <<< "$COMMAND"; then
    if grep -qE '\b(main|master|develop|release)\b' <<< "$COMMAND"; then
        DANGER_KIND="git-force-push-protected"
        DANGER_MSG="Force-pushing to a protected branch rewrites shared history — every teammate's local copy becomes inconsistent."
    else
        DANGER_KIND="git-force-push"
        DANGER_MSG="Force push rewrites remote history. If anyone else has pulled this branch, they will need to reset."
    fi
fi

# DB/SQL destructive ops (occasionally used in tooling)
#
# CMD_START is the wrong anchor here and applying it would have been worse than leaving the
# pattern alone: SQL is never in shell command position. Every real invocation passes it as
# an argument (`psql -c "DROP TABLE users"`) or on stdin, so anchoring the SQL to a command
# position would have silently turned this classification off — a false negative dressed up
# as a fix, which is the specific trap this change is guarded against.
#
# What separates the act from the text about it is the client. Require a database client to
# be named somewhere in the command as well. Two independent greps rather than one pattern:
# the command may be multi-line (a heredoc into psql puts the client and the SQL on
# different lines), and grep is line-oriented, so a single regex would only match when both
# halves sit on one line.
SQL_CLIENT='(^|[^A-Za-z0-9_.-])(psql|mysql|mysqladmin|mariadb|sqlite3|sqlcmd|cockroach|clickhouse-client|duckdb)([^A-Za-z0-9_-]|$)'

if grep -qiE '(drop[[:space:]]+table|truncate[[:space:]]+table|drop[[:space:]]+database)' <<< "$COMMAND" \
    && grep -qE "$SQL_CLIENT" <<< "$COMMAND"; then
    DANGER_KIND="db-destructive"
    DANGER_MSG="Schema-level destructive SQL. Data loss is immediate and irreversible."
fi

# PlayerPrefs wipes
#
# `PlayerPrefs.DeleteAll` was matched anywhere in the command and has been removed, because
# it is a C# member expression and not a shell command: there is no command position it can
# occupy, so every Bash command containing it is text ABOUT the wipe — a grep for it, an
# echo, a commit message. Measured 2026-08-13: `grep -rn 'PlayerPrefs.DeleteAll' Assets/`
# was blocked as a data wipe, and so was the probe script written to reproduce that, on the
# strength of the string appearing in a heredoc. Nothing was ever blocked from actually
# erasing preferences by this alternative, so nothing is lost by dropping it.
#
# What replaces it is the two shapes that do erase them from a shell, both anchored:
#   - macOS: `defaults delete <domain>` where the domain names unity
#   - Linux: an `rm` under ~/.config/unity3d/<Company>/<Product>/prefs, which is where
#     PlayerPrefs live on the only host .claude/UPSTREAM claims this toolkit ships for
# (Windows keeps them in the registry; `reg delete` is not covered.)
if grep -qE "${CMD_START}defaults[[:space:]]+delete${SAME_CMD}[Uu]nity" <<< "$COMMAND" \
    || grep -qE "${CMD_START}rm[[:space:]]+${SAME_CMD}unity3d" <<< "$COMMAND"; then
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
echo "  After presenting these facts, retry with the BYTE-IDENTICAL command — including" >&2
echo "  every other line of this same invocation — and it will pass." >&2
echo "  Recorded key: $KEY" >&2
echo "  (This is derived from the whole command string. Reformatting anything — even" >&2
echo "  unrelated lines, quoting, or whitespace — produces a different key and will be" >&2
echo "  blocked again as a new command.)" >&2
echo "" >&2
unity_hook_block "BashGate: present facts above for '$DANGER_KIND', then retry byte-identically (key: $KEY)."
