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
# $1 is the command name; $2 is that command's OWN argument tokens, already dequoted and
# TAB-joined by find_exec_commands, bounded by its clause. TAB rather than space, because
# find_exec_commands now respects quoting: `awk '/a/ && /b/ {print > F}'` is ONE argument, and
# re-splitting it on spaces here would hand these arms back the quote-blind token stream the
# whole tokeniser exists to replace.
FIND_TOK_SEP=$'\t'
# The command name find_exec_commands emits when it could not parse the command's quoting at
# all. No real command is spelled this way, and the consumer below compares against it exactly
# rather than trying to classify it — an unparseable command is not an unlisted one, and the
# two get different sentences.
FIND_TOK_UNPARSEABLE='!!unparseable!!'
find_exec_is_read_only() {
    local _cmd="$1" _args="${2:-}" _tok _skip=0
    local IFS="$FIND_TOK_SEP"
    case "$_cmd" in
        grep|egrep|fgrep|rg|ag|ack|stat|file|wc|cksum|md5sum|sha1sum|sha256sum|sha512sum|\
        b2sum|shasum|cat|head|tail|less|more|od|xxd|strings|nl|ls|basename|dirname|realpath|\
        readlink|echo|printf|true|false|test|'['|diff|cmp|uniq|cut|tr|comm|column|jq|du|\
        identify|date)
            return 0 ;;
    esac

    # --- second stage: read-only in the form you meet them, destructive in one other one ----
    # A table of four arms, deliberately not a mechanism. Each names the shape that writes.
    #
    # THE FLAG IS READ AS A POSITION, NOT AS A SHAPE IN A WIDE HAYSTACK. The first cut of this
    # table regexed the whole raw command string with a right boundary of `([[:space:]]|=|\.|$)`,
    # and shell quoting walked straight past it: `sed -i''` — the canonical cross-platform
    # spelling, and the one someone writes HERE because a macOS host pass is planned — was
    # permitted, along with `-ibak`, `-i~`, `"-i"` and `gawk -i inplace`. Five of them were
    # verified against real files: they rewrite every .meta they are handed. Round 3 blocked all
    # of them, because its allowlist had no second stage at all.
    #
    # That is this round's own defect class one level up: a token classified by its shape
    # instead of by the position it occupies — thrown away by a function that was already
    # holding the tokenised argument list. Deciding from the command's own arguments closes it
    # and four false positives with it (`grep -i` or `xargs -i` later on the line, a shell
    # redirect after the clause, find's own `-o`, and `git -C`), and it removes a
    # clauses × command-length cost that was measurable at 500 exec groups.
    #
    # The negative condition is preserved, so there is still no vouching direction: an arm asks
    # whether a write flag is present among ITS OWN arguments, and a spelling this table has not
    # thought of costs one first-attempt block on a read, never a pass on a write.
    case "$_cmd" in
        sed|gsed|yq|sort|openssl|awk|gawk|mawk|git) ;;
        *) return 1 ;;
    esac
    set -f
    # shellcheck disable=SC2086 -- deliberate word splitting over an already-tokenised list
    set -- $_args
    set +f
    while [ "$#" -gt 0 ]; do
        _tok="$1"; shift
        if [ "$_skip" = "1" ]; then _skip=0; continue; fi
        case "$_cmd" in
            sed|gsed|yq)
                # -i, -i.bak, -ibak, -i~, -i'' and -'i' (both now dequote to exactly -i),
                # bundles like -ni, and the long spellings. A `case` glob is anchored at both
                # ends, which is why find's own -iname can never reach this and an attached
                # suffix can never escape it.
                case "$_tok" in
                    -i|-i[!-]*|-[A-Za-z]*i|--in-place|--in-place=*|--inplace|--inplace=*)
                        return 1 ;;
                esac ;;
            sort|openssl)
                case "$_tok" in
                    -o|-o[!-]*|-[A-Za-z]*o|--output|--output=*) return 1 ;;
                esac ;;
            awk|gawk|mawk)
                # `-i inplace` is gawk's in-place extension; any -i loads a library that can
                # write, so all of them count. A redirect or system() inside the program is the
                # other write form.
                case "$_tok" in
                    -i|-i[!-]*|--include|--include=*) return 1 ;;
                    *'>'*|*'system('*) return 1 ;;
                esac ;;
            git)
                case "$_tok" in
                    -C|-c|--git-dir|--work-tree|--namespace|--exec-path|--config-env)
                        _skip=1 ;;                 # a global option with a separate argument
                    -*) ;;
                    log|blame|ls-files|check-ignore|show|diff|status|cat-file|grep) return 0 ;;
                    *) return 1 ;;                 # any other subcommand
                esac ;;
        esac
    done
    case "$_cmd" in
        git) return 1 ;;                           # no subcommand reached at all
        *) return 0 ;;
    esac
}

# ============================================================================================
# THE TOKENISER HAS A QUOTE MODEL. Read this before changing either function below.
#
# Rounds 3, 4 and 5 of this hook each closed one hole in the find route and opened another, and
# all three were the same defect one level down: `find_exec_commands` split the raw command
# string on whitespace with NO model of quoting, and every round repaired a consequence
# downstream of that instead of the cause.
#
#   -exec awk '/guid/ && /:/ {print > FILENAME}' {} \;   emitted `awk` with args ` /guid/`
#   -exec sed -E 's/(a | b)/x/' -i {} \;                 emitted `sed` with args ` -E s/(a`
#
# In the first the `>` never reached the awk arm; in the second the `-i` never reached the sed
# arm. Both were permitted at round 5 and both were verified against real files: the awk payload
# truncated 3 of 3 `.meta` files from 119 B to 39 B, the `system("rm ")` twin deleted all three,
# and the sed payload rewrote the guid line of all three. A ` && ` inside a quoted awk program is
# not a shell operator, and word splitting cannot tell the difference.
#
# So the split now respects quoting: a single- or double-quoted run is ONE token and its
# contents are inert — no operator inside it ends a clause, no `xargs` inside it introduces a
# command, no `;` inside it is find's terminator.
#
# WHAT THE MODEL DOES NOT HANDLE, and the direction each one fails:
#   - command substitution `$(…)` and backticks, and ANSI-C / locale quoting `$'…'` `$"…"`:
#     a command or a flag can hide inside them and the scanner would mis-bound the clause. All
#     of them mark the parse UNPARSEABLE, which BLOCKS. It costs a first-attempt block on a
#     read that uses `$(pwd)`; that is the cheaper direction and it is asserted both ways.
#   - an unterminated quote: same, UNPARSEABLE, blocks.
#   - ordinary variable expansion (`$FLAG`, `${FLAG}`): NOT modelled and NOT flagged. A
#     variable that expands to `-i` is a hole, unchanged from every previous version. Flagging
#     it would block every `grep "$PAT"`, and the gate has never modelled expansion.
#   - a literal TAB inside a quoted argument: the arms re-split on TAB, so such an argument
#     becomes two. That only ever produces MORE tokens for a write flag to match, which blocks.
#
# WHY awk. The scan has to look at every character, and bash cannot afford that: measured on
# this host (bash 5.2, en_US.UTF-8) a single `${x#\\}` costs 503 ms on a 122 880-character
# token and 49 125 ms on a 1 048 576-character one, which is the mechanism behind round 5's
# 172-second worst case. The same scan in `LC_ALL=C awk` costs 30 ms and 229 ms. `awk` is
# already a hard dependency of this file (the two-stage gate's hash uses it). `LC_ALL=C` is
# safe here because every character the scanner tests is ASCII and no UTF-8 continuation byte
# can collide with one.
# ============================================================================================

# The tokeniser's own protocol: TWO lines per token — a header `<flags> <bytelen> <basename>`
# and then the token's dequoted value on its own line. flags is two characters: `q` if the
# token contained a quoted run (else `-`), `b` if it contained a backslash escape (else `-`).
# The basename is computed in awk and capped at 64 characters so that bash never has to run a
# `${x##*/}` over a megabyte-long token — that expansion is the pathological operation above.
# A header of `!!` is the unparseable marker and its value line is the reason.
#
# TWO MODES, ONE SCANNER. `mode=meta` answers a single question — does any token in this
# command, ONCE DEQUOTED, name .meta files — and prints `1` or `0` and nothing else. It exists
# so the route decision below can ask the parser instead of asking a regex about the raw string
# (see THE ROUTE IS DECIDED FROM TOKENS, below). It is a mode rather than a second function
# because a second function would be a second quote model, and this file has already paid for
# having two ideas about the same string.
find_exec_tokens() {
    printf '%s' "$1" | LC_ALL=C awk -v mode="${2:-}" '
        # Does this dequoted value name .meta files? `.meta` outright, or `.meta` with glob
        # metacharacters standing inside it — `*.m*eta` is what `"*.m"*"eta"` dequotes to, and
        # it is a real glob that really does match Player.cs.meta. The cheap containment test
        # runs first because it is the spelling almost every real command uses.
        #
        # THE METACHARACTER SET IS `* ? [ ] \`, AND THE FIRST CUT OF THIS FUNCTION TESTED `*?`.
        # That was not a near-miss, it was five destructive spellings, and the review that found
        # them executed every one against real files while this function returned 0:
        #
        #   -name "*.\meta"      the scanner deliberately PRESERVES a backslash before an
        #   -name (single-quoted) ordinary character (`else { tok = tok BS d }`), bash preserves
        #   -name "*.\m\e\t\a"   it, and find gives it to fnmatch, which consumes it as an
        #   -name (bracket forms) escape. So the two halves of this file disagreed about what a
        #                        backslash means. A one-character bracket class is a literal too.
        #
        # `*.me\ta` UNQUOTED was already caught, because bash consumes that backslash before the
        # gate ever sees it. Its quoted twins are one character away and were not among the
        # twelve spellings first measured here — a round closing the spellings it imagined, which
        # is the pattern that put an earlier task at its five-round cap.
        #
        # EACH METACHARACTER GETS THE TREATMENT ITS SEMANTICS DESERVE, and getting that wrong is
        # how `?` was nearly missed a second time:
        #   `*` matches zero or more, so DELETING it is the right over-approximation.
        #   `\` is an escape, so deleting it leaves the literal it protected.
        #   `?` matches EXACTLY ONE character, so deleting it turns `*.m?ta` into `.mta` and
        #       loses a real match. It becomes a one-character WILDCARD instead.
        #   a bracket expression also matches exactly one character, whatever is inside it, so
        #       the whole thing becomes the same wildcard. One rule covers `[t]`, `[tT]`,
        #       `[a-z]`, `[!x]` and the `]`-first form `[]t]`.
        # The final test is one regex over a five-character window in which each position is
        # either its own literal or that wildcard.
        #
        # EVERY PATTERN IS A DYNAMIC STRING, NOT A REGEX LITERAL, and that is portability rather
        # than style: `"[][*?" BS "]"` compiles to a class ending `\]`, an escaped bracket, so
        # the class never closes — gawk and mawk both die at runtime with `invalid regexp` while
        # busybox awk accepts it, which is the worst way to find out. The backslash is matched by
        # an alternation outside any bracket expression instead. Verified byte-identical output
        # on 26 token values under gawk, gawk --posix, gawk --traditional, mawk and busybox awk.
        # (In THIS hook that failure is not a hole, it is the gate switching off: the scan is the
        # first thing every Bash call runs, so an awk that dies means exit 3 — silently — on every
        # command. Four of five awks; the one that accepts it is the one nobody develops on.)
        #
        # THE WINDOW ACCEPTS ALL FIVE POSITIONS WILDCARD, AND THAT IS A FALSE POSITIVE THIS FILE
        # OWNS RATHER THAN HIDES. `METARE` reads each position as literal-or-wildcard, so five
        # adjacent one-character globs match with no literal surviving. Measured, both new at
        # `20aa2b7` and 0 at every earlier version, both executed against a tree containing a real
        # .meta file that neither touched:
        #
        #   find logs -name '*.log' -exec sed -i 's/[abc][def][ghi][jkl][mno]/x/' {} \;   -> 2
        #   find src -name '?????' -exec sed -i s/a/b/ {} \;                              -> 2
        #
        # The first is a genuine false positive: five bracket expressions inside a SED SCRIPT, on
        # a find over *.log. The second is a defensible over-approximation — `?????` really can
        # match a file named `.meta` — but the pair produces an odd asymmetry worth knowing
        # before trusting either: **`-name '?????'` blocks while `-name '*'`, which matches every
        # .meta file there is, is a disclosed permit.** Both are corpus records.
        #
        # THE OBVIOUS TIGHTENING IS REFUSED, AND HERE IS ITS COST. Requiring at least one
        # surviving literal in the window closes the sed-script case and costs `?????`, which is
        # a glob that genuinely matches. Every spelling the metacharacter fix exists for keeps at
        # least one literal (`*.me[t]a` -> `.meWa`, `*.m[a-z]ta` -> `.mWta`), so the rule would
        # not cost those — but it trades a block on a read for a permit on a write, which is the
        # direction this whole file refuses. The false positive costs one first-attempt block and
        # a retry; it is left, deliberately, and written down instead.
        function meta_ref(v,   s) {
            if (index(v, ".meta") > 0) return 1
            if (v !~ GLOBCH) return 0
            s = v
            gsub(STRIP, "", s)
            if (index(s, ".meta") > 0) return 1
            if (s !~ ONECH) return 0
            gsub(BRACKET, WILD, s)
            gsub(QMARK, WILD, s)
            return (s ~ METARE)
        }
        function emit(   L, c) {
            if (!started) return
            if (mode == "meta") {
                if (meta_ref(tok)) hit = 1
                tok = ""; started = 0; q = 0; b = 0
                return
            }
            L = length(tok)
            if (L <= 512) { c = tok; sub(/^.*\//, "", c) } else { c = substr(tok, 1, 64) }
            print (q ? "q" : "-") (b ? "b" : "-") " " L " " substr(c, 1, 64)
            print tok
            tok = ""; started = 0; q = 0; b = 0
        }
        BEGIN { SQ = "\047"; DQ = "\042"; BS = "\\"; st = 0; tok = ""; started = 0
                q = 0; b = 0; bad = ""; hit = 0
                WILD    = sprintf("%c", 1)
                GLOBCH  = "[][*?]|" BS BS
                STRIP   = "[*]|" BS BS
                ONECH   = "[][?]"
                QMARK   = "[?]"
                BRACKET = "\\[[!^]?\\]?[^]]*\\]"
                METARE  = "[." WILD "][m" WILD "][e" WILD "][t" WILD "][a" WILD "]" }
        {
            line = $0; n = length(line); i = 1; cont = 0
            while (i <= n) {
                c = substr(line, i, 1)
                if (st == 0) {
                    if (c == BS) {
                        if (i == n) { cont = 1; break }      # backslash-newline: line splice
                        tok = tok substr(line, i + 1, 1); started = 1; b = 1; i += 2; continue
                    }
                    if (c == SQ) { st = 1; started = 1; q = 1; i++; continue }
                    if (c == DQ) { st = 2; started = 1; q = 1; i++; continue }
                    if (c == " " || c == "\t") { emit(); i++; continue }
                } else if (st == 1) {                        # inside single quotes: all inert
                    if (c == SQ) { st = 0; i++; continue }
                    tok = tok c; i++; continue
                } else {                                     # inside double quotes
                    if (c == BS) {
                        if (i == n) break                    # backslash-newline: line splice
                        d = substr(line, i + 1, 1)
                        if (d == DQ || d == BS || d == "$" || d == "`") { tok = tok d; b = 1 }
                        else { tok = tok BS d }
                        i += 2; continue
                    }
                    if (c == DQ) { st = 0; i++; continue }
                }
                if (c == "$" && i < n) {
                    d = substr(line, i + 1, 1)
                    if (d == "(" || d == SQ || d == DQ) bad = "substitution-or-ansi-c-quoting"
                }
                if (c == "`") bad = "backtick-command-substitution"
                tok = tok c; started = 1; i++
            }
            if (st == 0) { if (!cont) emit() } else { tok = tok " " }
        }
        END {
            # meta mode answers before the unparseable machinery, and it deliberately does NOT
            # treat an unparseable command as a .meta reference. Every construct that sets
            # `bad` — `$(...)`, a backtick, `$'\''...'\''` — appears in ordinary commands that
            # have nothing to do with Assets/, and routing on it would send every one of them
            # into a classification that ends in a block. Unparseable still blocks, but only
            # once the route has been established on a token that really does name .meta.
            if (mode == "meta") {
                if (started && meta_ref(tok)) hit = 1   # a token left pending by an open quote
                print (hit ? "1" : "0")
                exit
            }
            if (st != 0) bad = "unterminated-quote"
            else emit()
            if (bad != "") { print "!! 0 !!"; print bad }
        }
    '
}

# find_exec_commands — prints, one per line, `<command><TAB><its own argument tokens, TAB-joined>`
# for every command that find's -exec/-execdir/-ok(dir) or a pipeline's xargs would actually run.
# The positions are decided in bash; only the split is delegated (see above). "The word after the
# introducer" is a position, and the regex attempts to express that position are what kept
# missing verbs.
#
# The argument list is bounded by the command's own CLAUSE: find's terminator, an UNQUOTED shell
# operator, or the next -exec/xargs introducer. That bound is what keeps `grep -i` after a pipe,
# a `2>/dev/null` after the terminator, and an unrelated later `git status` out of the decision
# about the command that actually touches the .meta files.
#
# TWO TERMINATOR RULES, BECAUSE THERE ARE TWO PARSERS. On the find route the terminator is
# whatever find sees after the shell has removed quoting, so `\;`, `';'` and `";"` all terminate
# — verified: `-exec sed -e ';' -i {} \;` makes find stop at that `;`, report `unknown predicate
# -i`, exit 1 and write nothing. `+` is different: GNU find only reads it as the terminator when
# the PRECEDING argument was `{}`, which is why `-exec sort -u '+' -o {} {} \;` really does hand
# sort an `-o {}` — verified, sort ran and only failed because `+` was not a readable file. On
# the xargs route there is no find, so only a genuinely unquoted operator ends the clause.
#
# EVERY BUG THIS FUNCTION HAS HAD IS THE SAME BUG: a token classified by its shape rather than
# by its position, so the real command was stepped over. Four of them, kept here because the
# fifth will look just as reasonable:
#   - `';'*|'\'*` skipped ANY token starting with a backslash, meaning to skip find's `\;`
#     terminator. `\rm`, `\mv`, `\gzip` are the standard alias-bypass spelling and were
#     therefore invisible — on the find route, on the verb this classification is named after.
#   - an xargs option's ARGUMENT was read as the command: `xargs -n 1 grep` reported
#     "runs '1'", `xargs -d "\n" grep` reported "runs '\n'". Only options whose argument is
#     mandatory and separate are skipped; `-i`/`-e`/`-l` take an OPTIONAL attached one, so
#     skipping their next word would step over the command in `xargs -i rm {}`.
#   - a write flag decided by regexing the whole raw command string, so `sed -i''` walked past
#     the pattern's right boundary. Fixed by reading the exec'd command's own arguments.
#   - and the one this rewrite is for: an operator inside a quoted program read as a clause end.

# find_exec_flush — emit the pending command and its collected arguments, and re-arm.
#
# THE ARGUMENT LIST IS AN ARRAY, NOT A STRING, AND THAT IS A COST FIX RATHER THAN A STYLE ONE.
# It used to accumulate with `args="$args$SEP$tok"`, which copies the whole accumulator on every
# append and is therefore O(n^2) in the number of arguments in ONE clause. Measured on this host
# against `find … -exec grep -l <N args> {} \;`, end to end through the hook:
#
#     N =  2 000    2 052 ms        N = 16 000     80 975 ms
#     N =  8 000   32 605 ms        N = 20 000    >10 minutes
#
# Length was never the variable that mattered here — 8 000 arguments is only 248 KB, a fifth of
# the 1 MB single token this file's cost assertion used to be built from, and it cost sixteen
# times as much. An array append is O(1) and one `printf` over the array is O(n); the same
# payloads now cost 245 ms and 1 231 ms (see the cost block in tests/test-bash-gate-precision.sh).
#
# find_exec_trusted_path — can this gate place the path this token names?
#
# TRUE for a bare name (no `/` at all) and for the exact strings `/bin/<basename>` and
# `/usr/bin/<basename>`. FALSE for everything else, and false means "the table cannot speak for
# this", which costs a block on a read and never a pass on a write.
#
# COMPARED WHOLE, NOT AS A `/usr/bin/*` PREFIX GLOB. `/usr/bin/../../tmp/evil/grep` matches that
# glob, is not in /usr/bin at all, and destroyed 3 of 3 real .meta files when it was executed.
#
# DELIBERATELY NOT TRUSTED: /usr/local/bin and /opt/homebrew/bin, where a macOS host keeps gsed,
# gawk, yq and rg. Both are user-writable on the very platform this toolkit plans to support
# next, and the cost of leaving them out is one first-attempt block on a read that spells such a
# tool with its full path. A bare `gsed` is unaffected; only the path-qualified spelling pays.
#
# `command -v` was the third option considered and it is the wrong one: it resolves through PATH,
# which is attacker-controlled in exactly the scenario this defends against. (A second reason
# offered for it — that a shell function can shadow the binary, so `command -v grep` prints
# `grep` — is real in a profile-initialised interactive shell and NOT real in the `bash -c` this
# hook runs under. The PATH reason is the one that stands on its own. Note also that the
# surviving bare-name arm still resolves through that same PATH; what this function buys is that
# a caller cannot name an arbitrary path OUTRIGHT, not that PATH is trustworthy.)
find_exec_trusted_path() {
    case "$1" in
        */*) [ "$1" = "/bin/$2" ] || [ "$1" = "/usr/bin/$2" ] ;;
        *)   return 0 ;;
    esac
}

# Bash is dynamically scoped, so this reads find_exec_commands' locals directly. That is the
# reason it is a separate function at all: the same six lines appeared at five flush sites and
# one of them is easy to get wrong.
find_exec_flush() {
    printf '%s' "$pend"
    # `"${args[@]}"` on an EMPTY array is an unbound-variable error under `set -u` in bash before
    # 4.4, and macOS ships 3.2. `${#args[@]}` on the same empty array is safe in every version,
    # so the count test is the portable guard and the hazard sits inside it. The empty case is
    # real, not theoretical: `-exec gzip \;` and `| xargs -0 gzip` both reach here with no
    # arguments at all, and both must still emit their command so it can be classified.
    #
    # NOT EXECUTED ON BASH 3.2 — this host runs 5.2 and no 3.2 is installed, so `local -a`,
    # `args+=()` and `${#args[@]}` under `set -u` are reasoned here rather than measured. All
    # three predate 3.2 (array append arrived in 3.1) and tests/test-bash32-compat.sh passes,
    # but the real assertion waits for the planned macOS host pass.
    if [ "${#args[@]}" -gt 0 ]; then
        printf '\t%s' "${args[@]}"
    fi
    printf '\n'
    pend=""
    # BOTH resets matter and NEITHER can be tested alone. The other one is in
    # find_exec_commands' want-branch, where a new command is armed. Remove either and nothing
    # changes, because the other still clears the list; remove BOTH and clause 1's arguments
    # survive into clause 2, so `-exec git log {} \; -exec git rm {} \;` finds `log` among
    # `git rm`'s own arguments and the git arm VOUCHES for the second clause — the one direction
    # this file says cannot exist. A single-site mutation of this branch reports a meaningless
    # zero, which is the same masking that hid the route-tracking branch from its own sweep.
    args=()
    route=""
    prevbrace=0
}

find_exec_commands() {
    local flags len cand tok cmd want=0 pend="" route="" skipnext=0 prevbrace=0 toks
    local -a args
    args=()
    # An `||`, because a failed tokenisation under `set -e` would otherwise kill the hook and
    # fail it OPEN. Unparseable is a block, whichever way the parse failed.
    toks="$(find_exec_tokens "$1")" || toks="!! 0 !!
tokeniser-failed"
    # A here-string, not a pipe: nothing downstream may exit early and SIGPIPE the writer.
    while IFS=' ' read -r flags len cand; do
        IFS= read -r tok || tok=""
        if [ "$flags" = "!!" ]; then
            printf '%s\t%s\n' "$FIND_TOK_UNPARSEABLE" "$tok"
            continue
        fi
        if [ "$skipnext" = "1" ]; then skipnext=0; prevbrace=0; continue; fi
        if [ -n "$pend" ]; then
            # Collecting the pending command's own arguments.
            if [ "$route" = "find" ]; then
                if [ "$tok" = ";" ] || { [ "$tok" = "+" ] && [ "$prevbrace" = "1" ]; }; then
                    find_exec_flush; continue
                fi
            fi
            if [ "$flags" = "--" ]; then
                case "$tok" in
                    ';'|'|'|'||'|'&&'|'&')
                        find_exec_flush; continue ;;
                    # A redirection is the shell's, not the command's. SKIPPED rather than
                    # treated as a clause end, because the shell strips it wherever it sits:
                    # `xargs -0 sed 2>/dev/null -i s/a/b/` really does run `sed -i`.
                    # `&` followed by two `>` is deliberately absent from this exact list: it
                    # is bash-4-only syntax and tests/test-bash32-compat.sh greps every shipped
                    # script for that literal three-character sequence, so writing it here
                    # would fail the compat guard on a string this file never executes. It is
                    # still handled — by the attached-operand arm below, which skips the
                    # operator token and leaves the filename as a harmless argument.
                    '>'|'>>'|'<'|'<<'|'<<<'|'&>'|'>&'|[0-9]'>'|[0-9]'>>'|[0-9]'<'|[0-9]'>&')
                        skipnext=1; prevbrace=0; continue ;;
                    '>'*|'<'*|'&>'*|[0-9]'>'*|[0-9]'<'*)
                        prevbrace=0; continue ;;
                esac
            fi
            case "$flags" in
                q*) ;;                                 # a quoted run never introduces anything
                *)  case "$tok" in
                        -exec|-execdir|-ok|-okdir)
                            find_exec_flush; want=1; route="find"; continue ;;
                        # AN INTRODUCER THAT IS ITSELF A PROGRAM NEEDS THE SAME IDENTITY TEST AS
                        # A COMMAND. `-exec` and friends are find's own predicates and run
                        # nothing; `xargs` IS a program, and admitting `./evil/xargs` as an
                        # introducer means admitting it by basename — the exact defect the
                        # allowlist arm below exists to close, one position over. Executed:
                        # `find Assets -name '*.meta' -print0 | ./evil/xargs -0 grep -l guid`
                        # destroyed all three .meta files, 119 B -> 6 B, at every version
                        # including this file's first cut, while the gate classified the
                        # perfectly innocent `grep` that ./evil/xargs never ran.
                        # So an untrusted path-qualified xargs is armed as a COMMAND instead,
                        # which puts it in front of the read-only list, where no entry has a `/`.
                        xargs|*/xargs)
                            if find_exec_trusted_path "$tok" "$cand"; then
                                find_exec_flush; want=1; route="xargs"; continue
                            fi
                            find_exec_flush
                            pend="$tok"; args=(); want=0; route="xargs"; prevbrace=0; continue ;;
                    esac ;;
            esac
            args+=("$tok")
            if [ "$tok" = "{}" ]; then prevbrace=1; else prevbrace=0; fi
            continue
        fi
        if [ "$want" = "1" ]; then
            case "$tok" in
                -a|-E|-I|-d|-L|-n|-P|-s|--arg-file|--delimiter|--max-args|--max-chars|--max-procs)
                    skipnext=1                     # an xargs option and its separate argument
                    continue ;;
                -*|*=*|'{}'*|';'|'+') continue ;;
            esac
            cmd="$cand"                            # /usr/bin/rm -> rm, computed in awk
            # THE ALLOWLIST VOUCHES FOR A NAME, SO THE NAME HAS TO BE ONE IT CAN VOUCH FOR.
            # `grep` on the read-only list means "the grep I expect". Reducing every path to
            # its basename handed that vouching to anything whose LAST PATH COMPONENT happened
            # to spell an allowlisted name, wherever it came from. Executed, not reasoned: a
            # real program at ./evil/grep that rewrites its arguments, run as
            # `find Assets -name '*.meta' -exec ./evil/grep -l guid {} \;`, destroyed all three
            # .meta files (119 B -> 6 B) with this gate returning 0. /tmp/evil/grep is the same.
            #
            # So a path-qualified command keeps its PATH as its name unless the directory is one
            # the table can actually speak for, and no allowlist entry contains a `/`, so the
            # full path falls through to the unlisted arm and blocks. The message then names the
            # path the user actually wrote, which is the true statement.
            #
            # THE TRUSTED SET IS /bin AND /usr/bin, COMPARED WHOLE. `/usr/bin/grep` is a
            # spelling careful people write on purpose — this repository's own guide mandates
            # it, and 56 such spellings are in its tracked tree — so rejecting every `/` would
            # charge a block for following the house style. The rule itself, the trusted set and
            # the reason `command -v` was refused all live on find_exec_trusted_path above; this
            # is its first of two call sites, and the other is the xargs introducer, which is a
            # program and needs the same question asked of it.
            if ! find_exec_trusted_path "$tok" "$cand"; then
                cmd="$tok"
            fi
            case "$cmd" in
                # The same prefix vocabulary CMD_START uses: these run the NEXT word.
                env|sudo|doas|nice|nohup|command|time|exec|'') continue ;;
            esac
            pend="$cmd"
            args=()
            want=0
            prevbrace=0
            continue
        fi
        case "$flags" in
            q*) continue ;;
        esac
        case "$tok" in
            -exec|-execdir|-ok|-okdir) want=1; route="find" ;;
            # THE IDLE SITE IS THE ONE THE PIPELINE ROUTE ACTUALLY USES, and it is where the
            # measured damage was: `… -print0 | ./evil/xargs -0 grep -l guid` reaches here, not
            # the in-args site. Both sites carry the identity test, and BOTH are needed —
            # changing one alone is the single-site no-op this file has already been bitten by
            # twice (route tracking, and the paired args=() reset).
            xargs|*/xargs)
                if find_exec_trusted_path "$tok" "$cand"; then
                    want=1; route="xargs"
                else
                    pend="$tok"; args=(); want=0; route="xargs"; prevbrace=0
                fi ;;
        esac
    done <<< "$toks"
    # A clause that runs to the end of the line has no terminator to flush it. An `if`, not an
    # AND-list: under `set -e` a trailing `[ -n "$x" ] && printf` fails the function when the
    # test is false.
    if [ -n "$pend" ]; then
        find_exec_flush
    fi
    return 0
}

# ============================================================================================
# THE ROUTE IS DECIDED FROM TOKENS, NOT FROM A REGEX OVER THE RAW STRING.
#
# This line used to read `grep -qE "${CMD_START}find[[:space:]]+${SAME_CMD}\.meta"`, and it was
# the same defect the tokeniser above exists to fix, one level UP: the decision about WHICH
# commands get parsed was itself taken by a quote-blind regex, so a name split across quotes
# never reached the parser that would have resolved it. Measured at r3 (546870f), r4 (06883cc),
# r5 (3fd22dc) and task 2b (c050743) — all four permitted, all three verified to rewrite the
# guid line of all three real .meta files they were handed:
#
#     find Assets -name "*.m"*"eta" -exec sed -i s/a/b/ {} \;      dequotes to *.m*eta
#     find Assets -name '*.met'a   -exec sed -i s/a/b/ {} \;      dequotes to *.meta
#     ls Assets/*.meta | xargs sed -i s/a/b/                       no `find` anywhere
#
# THE CLASS, not those spellings: **a glob whose literal text is split by quoting**. There are
# unboundedly many spellings of it — `'*.m'eta`, `*.me"ta"`, `"*.me""ta"`, `'*.m''eta'`,
# `*.me\ta`, `'*.'meta`, and the same trick on `-path` or on a bare path argument — and each one
# dequotes to a glob that matches every .meta file in the tree. Widening the regex to catch them
# would have been the fourth iteration of chasing spellings that this file's history is made of.
#
# So the question moved to where the answer already lives: `find_exec_tokens ... meta` asks the
# quote model whether any DEQUOTED token names .meta files. `"*.m"*"eta"` becomes `*.m*eta`,
# `'*.met'a` becomes `*.meta`, and both answer yes.
#
# THE `find` REQUIREMENT IS GONE TOO, and that is a second hole rather than a side effect. The
# old precondition demanded the word `find`, but `find_exec_commands` has always understood the
# xargs route as well, so `ls Assets/*.meta | xargs sed -i` reached nothing that could classify
# it. `SAME_CMD`'s `[^;&|]*` bound went with it: it required the .meta reference and the word
# `find` to sit in the same pipeline segment, so `find Assets | grep .meta | xargs sed -i` was
# permitted too.
#
# WHAT THIS COSTS, measured rather than assumed, end to end through the hook on this host:
#
#                                        task 2b   pre-filter   here
#   ordinary short command                 33 ms      33 ms     36 ms
#   an ordinary read naming Assets/        41 ms      39 ms     35 ms
#   a read-only find over .meta            38 ms      41 ms     40 ms
#   a 128 KB command with no .meta in it   87 ms      88 ms    145 ms
#   a 1 MB command with no .meta in it    567 ms     552 ms   1 088 ms
#
# The scan is one extra `LC_ALL=C awk` pass over the command on EVERY Bash call. On the commands
# anyone actually types it is inside the run-to-run noise; the whole cost sits in command lines
# measured in megabytes, where it stays about 9x under this file's asserted 10 000 ms ceiling.
#
# THE PRE-FILTER COLUMN IS THE OPTION THAT WAS REJECTED, and it was rejected on a measurement
# rather than on taste. Putting a cheap raw-string test — "does it mention find, xargs or
# Assets/?" — in front of the scan saves ~520 ms on a 1 MB command and nothing at all on a
# short one, and it buys back a hole of exactly the kind being closed here, because a raw-string
# test is quote-blind by construction. Executed against real files:
#
#     ls Packages/*.me\ta | x\args sed -i s/guid/XXXX/
#
# rewrites all three .meta files it is handed. It contains no `find`, no literal `xargs`
# (`x\args` runs xargs), no `Assets/` and no literal `.meta` — so the pre-filter rejects it and
# the scan never runs. Measured: 0 with the pre-filter, 2 without it. A second quote-blind
# precondition in front of the one being removed is not worth 520 ms on a command line nobody
# types.
#
# WHAT IT DOES NOT CLOSE, all four executed against real .meta files and all four destructive:
#   - a token that names .meta files without spelling them — `-name '*.me*'`, `-name '*'`. The
#     route tracks what a token SAYS after dequoting, not what it will MATCH after globbing, and
#     nothing here models the filesystem.
#   - a variable that expands to the glob. Unchanged from every version; see the quote model's
#     header.
#   - a QUOTED INTRODUCER. `-'e'xec` and `| 'xargs' -0` reach the shell and find as `-exec` and
#     `xargs`, and find_exec_commands refuses to read a token carrying a quote run as an
#     introducer — task 2b's deliberate trade, which is what stops a quoted `xargs` inside a
#     grep pattern from introducing a command. This is the same defect class as the one above,
#     one word over, and closing it is a judgement this task was not given. It is recorded in
#     tests/test-bash-gate-precision.sh with a payload and an `H` marker rather than left in a
#     report nobody reads next time.
#
#     ITS CONSEQUENCE WIDENED WHEN find_exec_trusted_path WAS ADDED, and that is the sentence
#     this bullet was missing. A quote ANYWHERE in the introducer token means the token is never
#     read as an introducer at all — so the identity test below is never consulted, and the
#     three spellings that defeat it are ordinary-looking. Executed, all three destroyed 3 of 3
#     real .meta files, 119 B -> 6 B, and all three are 0 at every version including this one:
#
#         | ./evil/'xargs' -0 grep -l guid          (a quote inside the path)
#         | './evil/xargs' -0 grep -l guid          (the whole path single-quoted)
#         | "./evil/xargs" -0 grep -l guid          (the whole path double-quoted)
#
#     while the unquoted `| ./evil/xargs -0 grep -l guid` blocks. So the quoting trade does not
#     merely leave a hole beside the identity check — it is a way around the identity check, and
#     quoting a path is a thing people do for no reason at all. The class stays deferred, for
#     the reason above; the reason is now stated against what it actually costs.
#   - the DIRECT shape (`rm 'Assets/Player.cs.met'a`). That arm is a raw-regex denylist over
#     command position and the split-literal class walks past it exactly as it did here.
#     Executed, it deleted one of three real .meta files. Fixing it means tokenising command
#     position too, which is a bigger change than either judgement this task was given.
#
# A FAILED SCAN COUNTS AS A HIT. An `||`, because a bare assignment from a failing command
# substitution is fatal under `set -e` and would take the hook down before it classified
# anything; the value it falls back to is the one that keeps parsing rather than the one that
# stops. The tokeniser then fails again inside find_exec_commands and the command is classified
# unparseable, which blocks.
#
# AND THIS WIDENS AN INHERITED FAILURE, WHICH IS SAID HERE RATHER THAN LEFT TO BE FOUND. With a
# deliberately broken `awk` on PATH this file exits 3, and **3 is not a block** — `unity_hook_block`
# below exits 2, HOOK-REFERENCE.md says the same, so 3 is a hook error and the tool call proceeds.
# It is not a loud one either: measured here as rc=3 with **0 bytes on stdout and 0 on stderr**.
# Task 2b's version did that only on the commands it classified; this one does it on EVERY
# command, because the scan is what became universal. The dying is not here: it is further down
# at the two-stage gate's own `awk` in CMD_HASH, a line this task did not touch, where `set -e`
# reaches a bare assignment. Measured on this host: task 2b exits 3 on a destructive .meta
# payload and 0 on `echo hello`; this version exits 3 on both; flipping the fallback above to
# `0` exits 0 on both — an explicit PERMIT the harness acts on rather than an error it reports,
# which is the only difference the `||` above actually buys. That difference is real and it is
# worth having; a block it is not. The assertion holding it is in
# tests/test-bash-gate-precision.sh with the same caveat above it, and no corpus payload can
# reach it — the scan fails on the environment, not on anything a command string can say.
# ============================================================================================
META_ROUTE="$(find_exec_tokens "$COMMAND" meta)" || META_ROUTE="1"
if [ "$META_ROUTE" = "1" ]; then
    # `-delete` is find's own flag, so this arm still asks for a `find`. Without that the arm
    # fires on any command that merely carries the word next to a .meta path — `grep -- -delete
    # Assets/x.meta` is a read — and it would report a deletion that nothing is doing.
    if grep -qE "${CMD_START}find[[:space:]]" <<< "$COMMAND" \
       && grep -qE '(^|[^A-Za-z0-9_-])-delete([[:space:]]|$)' <<< "$COMMAND"; then
        # find's own flag. Unambiguous, so the precise message is free here.
        DANGER_KIND="meta-deletion"
        DANGER_MSG="$META_DEL_MSG"
    else
        META_EXEC=""
        META_UNPARSEABLE=""
        # A here-string, not a pipe: `break` in a piped `while` would leave the writer to die
        # of SIGPIPE, which under pipefail + set -e kills the hook and fails it OPEN.
        while IFS=$'\t' read -r _mc _margs; do
            [ -n "$_mc" ] || continue
            if [ "$_mc" = "$FIND_TOK_UNPARSEABLE" ]; then
                META_UNPARSEABLE="${_margs:-unknown}"
                META_EXEC="(unparsed)"
                break
            fi
            if ! find_exec_is_read_only "$_mc" "${_margs:-}"; then
                META_EXEC="$_mc"
                break
            fi
        done <<< "$(find_exec_commands "$COMMAND")"
        if [ -n "$META_UNPARSEABLE" ]; then
            # The gate could not tokenise this command, so it does not know WHICH command runs
            # over the .meta files. Unparseable is treated as unrecognised, never as safe: the
            # only alternative is to guess at a clause boundary, and guessing wrong in this
            # direction is what let a quoted awk program truncate every .meta file it touched.
            DANGER_KIND="meta-mutation"
            DANGER_MSG="This gate could not parse this command's quoting (${META_UNPARSEABLE}), so it cannot tell which command runs over these .meta files. .meta files hold the GUIDs every scene, prefab and ScriptableObject reference resolves through — a command that rewrites them breaks those references silently, so an unparseable one is treated as unrecognised rather than as safe."
        elif [ -n "$META_EXEC" ]; then
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
            #
            # "This command runs", not "This find runs". The route no longer requires a `find`
            # — `ls Assets/*.meta | xargs sed -i` reaches here now — and a sentence that names a
            # program the user did not write is the same kind of false confidence as a category
            # the gate cannot establish.
            DANGER_KIND="meta-mutation"
            DANGER_MSG="This command runs '${META_EXEC}' over .meta files, and '${META_EXEC}' is not on this gate's read-only list. .meta files hold the GUIDs every scene, prefab and ScriptableObject reference resolves through — deleting, renaming or rewriting them breaks those references silently."
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
    if [ -n "${META_UNPARSEABLE:-}" ]; then
        echo "  This gate could not parse this command's quoting (${META_UNPARSEABLE}), so it" >&2
        echo "  cannot tell which command runs over these files. Before retrying:" >&2
    else
        echo "  This gate does not know what '${META_EXEC}' does — only that it is not on the" >&2
        echo "  read-only list. Before retrying:" >&2
    fi
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
    if [ -n "${META_UNPARSEABLE:-}" ]; then
        unity_hook_block "BashGate: this command's quoting could not be parsed (${META_UNPARSEABLE}); say whether it reads or writes these .meta files, then retry byte-identically (key: $KEY)."
    fi
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
