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
#
# The optional trailing `\\?` is the alias-bypass spelling: `\rm -rf Library/` and
# `\rm Assets/Player.cs.meta` really do run rm, and without it the backslash sat between the
# command start and the verb and every pattern below missed them. Measured before it was added:
# `\rm -rf Library/`, `\rm Assets/Player.cs.meta`, `\mv` of a .meta, `\find` and
# `\git reset --hard` were all permitted. It is the same defect the find route's tokeniser had
# (see find_exec_commands), in the other arm.
CMD_PREFIX='((sudo|doas|env|nice|nohup|exec|command|time|xargs)([[:space:]]+[A-Za-z0-9_=./{}-]+)*[[:space:]]+)?'
CMD_START="(^[[:space:]]*|[;&|]+[[:space:]]*|[({][[:space:]]*)${CMD_PREFIX}\\\\?"
SAME_CMD='[^;&|]*'

# Unity directory wipes
if grep -qE "${CMD_START}rm[[:space:]]+-[rRf]+[[:space:]]+${SAME_CMD}(Library|Temp|Logs|obj|Build|Builds)/" <<< "$COMMAND"; then
    DANGER_KIND="unity-dir-wipe"
    DANGER_MSG="Deleting Library/Temp/Logs/obj/Build triggers a full Unity reimport (minutes to hours) and can corrupt GUIDs if done while editor is open."
fi

# .meta deletion/mass-rename.
#
# TWO SHAPES, TWO DISCRIMINATORS, AND THEY POINT OPPOSITE WAYS. This is the part to understand
# before editing anything below.
#
# The DIRECT shape (`rm Assets/Player.cs.meta`) names the file as the verb's own argument.
# Anything at all can name a path — `cat`, `git log`, `stat` — so there is no allowlist of
# harmless commands to write here, and a denylist of destructive verbs is the correct tool. It
# is incomplete by construction and always will be; adding a verb is a one-line change.
#
# The FIND shape (`find Assets -name '*.meta' -exec X {} \;`) is the opposite. `find` supplies
# the paths and X does the work, so the question is not "is X on a list of dangerous things"
# but "is X something that cannot hurt these files". That set is small, closed and knowable;
# the dangerous set is every binary on the machine.
#
# We learned that the expensive way. Before this wave the pattern was `(rm|find)…\.meta` —
# indiscriminate, which is why `find Assets -name "*.meta" | wc -l` (a COUNT) was blocked as a
# deletion, and also why every destructive verb was covered for free. Requiring an action
# restored the counts and dropped every unlisted verb with them. The denylist was then written
# out by hand three times: rm; then mv after review; then unlink/shred/truncate/rename/prename/
# mmv after re-review — and a mechanical sweep still found 49 misses out of 58 binaries. The
# decisive one was `perl-rename`/`file-rename`: the SAME tool as `prename`, under its other two
# standard names, missed by the same left-boundary mechanism the comment above it explained.
# A hand-written denylist of harmful verbs was wrong every single time it was written.
#
# So the find shape is inverted: keep the action requirement — that is what lets a count and a
# bare `-print` through, and it must not change — but once there IS an exec'd command,
# classify UNLESS that command is on a small allowlist of read-only ones.
#
# The failure direction flips with it. An unlisted read-only command now costs one first-attempt
# block on a two-stage gate; under the old shape an unlisted destructive command silently broke
# every asset reference in the project. The plan is explicit that this is the cheaper direction.

META_DEL_MSG=".meta files hold GUIDs — deleting them silently breaks every reference (scenes, prefabs, ScriptableObjects, AssetReferences)."
META_MV_MSG="Renaming .meta files without their asset sibling orphans references. Unity will not recover from this automatically."

# --- the direct shape: a denylist, by ruling ---------------------------------------------
# Incomplete by construction. These are the verbs known today; `unlink Assets/Player.cs.meta`
# passed until this line was widened, and `unlink` is literally what the classification is named
# after. The find shape below no longer needs a list like this one.
DIRECT_DEL='(rm|unlink|shred|truncate)'
DIRECT_MV='(mv|rename|prename|perl-rename|file-rename|mmv)'

if grep -qE "${CMD_START}${DIRECT_DEL}[[:space:]]+${SAME_CMD}\.meta" <<< "$COMMAND"; then
    DANGER_KIND="meta-deletion"
    DANGER_MSG="$META_DEL_MSG"
fi
if grep -qE "${CMD_START}${DIRECT_MV}[[:space:]]+${SAME_CMD}\.meta" <<< "$COMMAND"; then
    DANGER_KIND="meta-rename"
    DANGER_MSG="$META_MV_MSG"
fi

# --- the find shape: an allowlist of read-only commands ------------------------------------
# Commands that cannot modify the files find hands them. Deliberately NOT here: any
# general-purpose interpreter (`sh`, `bash`, `python3`, `perl`, `ruby`) — they can write, and a
# wrapper is exactly how a destructive verb hides. Extending this list is safe in a way that
# extending a denylist never was: the worst a missing entry does is block a read.
#
# Membership means "cannot modify the files find hands it", and that is a stronger claim than
# "is usually harmless". Two members failed it and are gone: `touch`, whose entire job is to
# mutate mtime — which is a Unity reimport trigger — and `sort`, whose `sort -o {} {}` is the
# documented in-place rewrite. `dos2unix` was proposed for this list and refused for the same
# reason: its man page says old-file mode "overwrite[s] output to it. The program defaults to
# run in this mode", so `-exec dos2unix {} \;` rewrites every .meta file it is handed.
#
# $1 is the command name, $2 the token straight after it, $3 the whole command line.
find_exec_is_read_only() {
    case "$1" in
        grep|egrep|fgrep|rg|ag|ack|stat|file|wc|cksum|md5sum|sha1sum|sha256sum|sha512sum|\
        b2sum|shasum|cat|head|tail|less|more|od|xxd|strings|nl|ls|basename|dirname|realpath|\
        readlink|echo|printf|true|false|test|'['|diff|cmp|uniq|cut|tr|comm|column|jq|du|\
        identify|date)
            return 0 ;;
    esac

    # --- second stage: read-only in the form you meet them, destructive in one other one ----
    # A table of four arms, deliberately not a mechanism. Each names the shape that writes,
    # and each reads the haystack in which BEING WRONG BLOCKS RATHER THAN PERMITS:
    #   - the flag arms read the WHOLE command line ($3), because a wider haystack finds `-i`
    #     more easily, so a miss costs one first-attempt block on a read;
    #   - `git` reads ONLY the token straight after it ($2), because a wider haystack would let
    #     an unrelated `git status` later on the line vouch for an earlier `git rm`.
    # The cost of the wide haystack, accepted: an unrelated `grep -i` or find's own `-o`
    # elsewhere on the line makes the read form block once. `openssl` joins `sort` rather than
    # the flat list because it is the same shape — `-out FILE` writes a named file.
    case "$1" in
        sed|gsed|yq)
            if grep -qE '(^|[[:space:]])(-[A-Za-z]*i([[:space:]]|=|\.|$)|--in-?place)' <<< "$3"; then
                return 1
            fi
            return 0 ;;
        sort|openssl)
            if grep -qE '(^|[[:space:]])(-[A-Za-z]*o([[:space:]]|=|$)|--output|-out([[:space:]]|=|$))' <<< "$3"; then
                return 1
            fi
            return 0 ;;
        awk|gawk|mawk)
            if grep -qE '(>|system[[:space:]]*\()' <<< "$3"; then
                return 1
            fi
            return 0 ;;
        git)
            case "$2" in
                log|blame|ls-files|check-ignore|show|diff|status|cat-file|grep) return 0 ;;
            esac
            return 1 ;;
    esac
    return 1
}

# find_exec_commands — prints, one per line, `<command><TAB><the token after it>` for every
# command that find's -exec/-execdir/-ok(dir) or a pipeline's xargs would actually run.
# Tokenised in bash rather than matched with a regex, because "the word after the introducer"
# is a position, and the regex attempts to express that position are what kept missing verbs.
#
# EVERY BUG THIS FUNCTION HAS HAD IS THE SAME BUG: a token classified by its shape rather than
# by its position, so the real command was stepped over. Three of them, kept here because the
# fourth will look just as reasonable:
#   - `';'*|'\'*` skipped ANY token starting with a backslash, meaning to skip find's `\;`
#     terminator. `\rm`, `\mv`, `\gzip` are the standard alias-bypass spelling and were
#     therefore invisible — on the find route, on the verb this classification is named after.
#     `-exec \mv {} /tmp \;` still blocked, but reported "runs 'tmp'": having skipped `\mv`
#     and `{}` it landed on the next word. The terminator is now matched in full, and the
#     backslash is stripped from every token before anything looks at it, which also fixes
#     `| \xargs -0 rm` — a stripped `\xargs` is an introducer again.
#   - an xargs option's ARGUMENT was read as the command: `xargs -n 1 grep` reported
#     "runs '1'", `xargs -d "\n" grep` reported "runs '\n'". Only options whose argument is
#     mandatory and separate are skipped; `-i`/`-e`/`-l` take an OPTIONAL attached one, so
#     skipping their next word would step over the command in `xargs -i rm {}`.
#   - the same class in `CMD_START` above, for the direct arm.
find_exec_commands() {
    local tok cmd want=0
    # `set -f` matters: the command line being tokenised contains globs (`*.meta` is the whole
    # point), and unquoted word splitting would otherwise expand them against the real cwd.
    set -f
    # shellcheck disable=SC2086 -- deliberate word splitting; this IS the tokeniser
    set -- $1
    set +f
    # `while`/`shift` rather than `for`, so that $1 is the token after the current one and the
    # command's own next word is available without a second pass.
    while [ "$#" -gt 0 ]; do
        tok="$1"; shift
        tok="${tok#\\}"                            # \rm -> rm, \xargs -> xargs, \; -> ;
        if [ "$want" = "1" ]; then
            case "$tok" in
                -a|-E|-I|-d|-L|-n|-P|-s|--arg-file|--delimiter|--max-args|--max-chars|--max-procs)
                    shift || true                  # an xargs option and its separate argument
                    continue ;;
                -*|*=*|'{}'*|';'|'+') continue ;;
            esac
            cmd="${tok##*/}"                       # /usr/bin/rm -> rm
            cmd="${cmd%\'}"; cmd="${cmd#\'}"       # 'rm -> rm
            cmd="${cmd%\"}"; cmd="${cmd#\"}"
            case "$cmd" in
                # The same prefix vocabulary CMD_START uses: these run the NEXT word.
                env|sudo|doas|nice|nohup|command|time|exec|'') continue ;;
            esac
            printf '%s\t%s\n' "$cmd" "${1:-}"
            want=0
            continue
        fi
        case "$tok" in
            -exec|-execdir|-ok|-okdir|xargs|*/xargs) want=1 ;;
        esac
    done
    return 0
}

if grep -qE "${CMD_START}find[[:space:]]+${SAME_CMD}\.meta" <<< "$COMMAND"; then
    if grep -qE '(^|[^A-Za-z0-9_-])-delete([[:space:]]|$)' <<< "$COMMAND"; then
        # find's own flag. Unambiguous, so the precise message is free here.
        DANGER_KIND="meta-deletion"
        DANGER_MSG="$META_DEL_MSG"
    else
        META_EXEC=""
        # A here-string, not a pipe: `break` in a piped `while` would leave the writer to die
        # of SIGPIPE, which under pipefail + set -e kills the hook and fails it OPEN.
        while IFS=$'\t' read -r _mc _mnext; do
            [ -n "$_mc" ] || continue
            if ! find_exec_is_read_only "$_mc" "${_mnext:-}" "$COMMAND"; then
                META_EXEC="$_mc"
                break
            fi
        done <<< "$(find_exec_commands "$COMMAND")"
        if [ -n "$META_EXEC" ]; then
            # ONE classification, and the message names the command rather than guessing its
            # category. Once the decision stops depending on knowing the verb, a message that
            # says "deleting" or "renaming" would be asserting knowledge the gate no longer
            # has — and a category list kept only for wording would rot exactly as the denylist
            # did, but silently, because a wrong sentence is less visible than a missed block.
            #
            # For the same reason the sentence says "not on this gate's read-only list" rather
            # than "not a read-only command". The second is a claim about the command and the
            # gate cannot make it: for `git log` it is simply false. The first is a claim about
            # the gate, which is the only thing it actually knows.
            DANGER_KIND="meta-mutation"
            DANGER_MSG="This find runs '${META_EXEC}' over .meta files, and '${META_EXEC}' is not on this gate's read-only list. .meta files hold the GUIDs every scene, prefab and ScriptableObject reference resolves through — deleting, renaming or rewriting them breaks those references silently."
        fi
    fi
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
# git's global options legitimately sit between `git` and its subcommand. Allowing them
# closes false negatives (`git -C /repo reset --hard` and `git --git-dir=/r/.git clean -fdx`
# were both permitted, the second found in review) without re-opening the prose one: every
# alternative below is flag-shaped, and prose reaching `reset --hard` has ordinary words in
# that gap rather than a leading dash. Enumerated rather than written as a catch-all `-\S+`,
# because a catch-all would also swallow a subcommand's own arguments and walk the match
# forward into unrelated text.
GIT_OPT='(-[cC][[:space:]]*[^[:space:];&|]+|--(git-dir|work-tree|namespace|exec-path|config-env)[= ][^[:space:];&|]+|--(no-pager|paginate|bare|literal-pathspecs|no-replace-objects))'
GIT_OPTS='([[:space:]]+'"${GIT_OPT}"')*'

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
#
# THIS IS A CLOSED ALLOWLIST and it narrows differently from what it replaced, rather than
# strictly less. Anything issuing destructive SQL through something not named below now
# passes: measured, `python3 -c "cur.execute('DROP TABLE users')"` and
# `bq query 'DROP TABLE ds.t'` both went from blocked to allowed. Adding names does not close
# the class — any language runtime can open a connection — so the real alternative is a
# different discriminator (require the SQL to sit inside a quoted argument), which is a design
# change and not a list. Recorded rather than papered over with four more names.
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
#
# Two gaps, both measured 2026-08-13, both named here rather than left to be rediscovered:
#   - Windows keeps them in the registry; `reg delete` is not covered at all.
#   - The macOS plist is the same act by a different route, and neither arm above sees it.
#     `rm -f ~/Library/Preferences/unity.Acme.Game.plist` does return 2 — but as
#     `unity-dir-wipe`, because every macOS preferences path contains `Library/`, so the
#     developer is told the wipe "triggers a full Unity reimport" when it erases their saves.
#     A BARE `rm` of the same path returns 0: `unity-dir-wipe` requires an `-[rRf]` flag.
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
# meta-mutation is the one classification that does NOT assert the command is destructive —
# it fires because the command is unrecognised, which is a fact about this gate's list. A
# header reading DESTRUCTIVE and a demand for a rollback plan would be asking the developer to
# justify what may well be a read, and ceremony demanded for a harmless command is exactly the
# training this hook is meant to avoid: it teaches that the way past a guard is to produce the
# words it wants.
if [ "$DANGER_KIND" = "meta-mutation" ]; then
    echo "  BashGate — UNRECOGNISED COMMAND OVER .meta FILES (first attempt blocked)" >&2
else
    echo "  BashGate — DESTRUCTIVE COMMAND (first attempt blocked)" >&2
fi
echo "  Classification: $DANGER_KIND" >&2
echo "  Command: $COMMAND" >&2
echo "" >&2
echo "  Risk: $DANGER_MSG" >&2
echo "" >&2
if [ "$DANGER_KIND" = "meta-mutation" ]; then
    echo "  This gate does not know what '${META_EXEC}' does — only that it is not on the" >&2
    echo "  read-only list. Before retrying:" >&2
    echo "" >&2
    echo "  - If it only READS these files, say so in one line and retry. That is the whole" >&2
    echo "    answer; do not manufacture a rollback plan for a read." >&2
    echo "  - If it WRITES them, name the asset files these .meta files belong to, confirm the" >&2
    echo "    siblings are handled identically, and give a one-line rollback." >&2
    echo "" >&2
    echo "  After answering, retry with the BYTE-IDENTICAL command — including every other" >&2
    echo "  line of this same invocation — and it will pass." >&2
    echo "  Recorded key: $KEY" >&2
    echo "  (This is derived from the whole command string. Reformatting anything — even" >&2
    echo "  unrelated lines, quoting, or whitespace — produces a different key and will be" >&2
    echo "  blocked again as a new command.)" >&2
    echo "" >&2
    unity_hook_block "BashGate: say whether '${META_EXEC}' reads or writes these .meta files, then retry byte-identically (key: $KEY)."
fi
echo "  Before retrying, present these facts:" >&2
echo "" >&2
echo "  1. Enumerate exactly what this command will modify or delete." >&2
case "$DANGER_KIND" in
    unity-dir-wipe)
        echo "     - Confirm Unity editor is closed (otherwise reimport may race)." >&2
        echo "     - Note the expected reimport duration." >&2
        ;;
    meta-deletion|meta-rename)
        # meta-mutation is deliberately NOT here: it exits above with its own, shorter demand.
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
