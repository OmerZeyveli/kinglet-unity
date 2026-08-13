#!/usr/bin/env bash
# ============================================================================
# test-bash-gate-precision.sh — the gate must classify commands, not text.
#
# A false block costs more than a missed one: it argues with the developer
# every day, and that is what gets a gate disabled. Measured case — a command
# that wrote nothing was classified projectsettings-write because the path
# appeared inside a JSON argument.
# ============================================================================

TBG_HOOK="${REPO_DIR}/.claude/hooks/bash-gate.sh"

# bash-gate.sh remembers a denied command's hash so an identical retry passes. That state
# lives in UNITY_HOOK_STATE_DIR, which defaults to the real repo's .claude/state — shared
# with every real Bash call this session makes. Without isolating it here, this test would
# both pollute that real state and become order-dependent: a "must still block" assertion
# would silently flip to "allowed" the moment its hash was ever recorded once, by this test
# or by real prior use. Give every run of this file a throwaway state directory instead.
TBG_STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bash-gate-precision-test.XXXXXX")"
trap 'rm -rf "$TBG_STATE_DIR"' EXIT

tbg_run() {
    printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s}}' \
        "$(printf '%s' "$1" | jq -Rs .)" \
        | UNITY_HOOK_STATE_DIR="$TBG_STATE_DIR" bash "$TBG_HOOK" > /dev/null 2>&1
    printf '%s' "$?"
}

# Must still block — these really do write.
assert_eq "2" "$(tbg_run 'echo hi > ProjectSettings/ProjectSettings.asset')" \
    "still blocks a real redirect into ProjectSettings"
assert_eq "2" "$(tbg_run 'rm -f Assets/Player.cs.meta')" \
    "still blocks a real .meta deletion"

# Must not block — the path is data, not a target.
assert_eq "0" "$(tbg_run 'grep -n ProjectSettings/ProjectSettings.asset notes.txt')" \
    "does not block a grep that merely names ProjectSettings"
assert_eq "0" "$(tbg_run 'echo "see ProjectSettings/ProjectSettings.asset for details"')" \
    "does not block an echo that merely mentions the path"
assert_eq "0" "$(tbg_run 'git log -- Assets/Player.cs.meta')" \
    "does not block reading history of a .meta file"

# --- Additional assertions, added while implementing the fix -----------------------------
# The three assertions above, as literally given in the brief, do not actually trip the
# unmodified classifier: none of them contain a bare "rm"/">"/"mv"/"cp" substring anywhere
# on the line, so the permissive `.*` in the original pattern never gets a foothold. The two
# cases below are faithful reproductions of the measured defect — a verb-shaped substring
# and the ProjectSettings path genuinely co-occurring on one line with no target relationship
# between them — confirmed to false-block on the original pattern and confirmed fixed by the
# command-position anchor.
assert_eq "0" "$(tbg_run 'curl -s https://api.example.com/report -d "{\"reason\": \"cp shows drift\", \"target\":\"ProjectSettings/ProjectSettings.asset\"}"')" \
    "does not block a JSON argument that merely contains the word cp and the path as data"
assert_eq "0" "$(tbg_run 'echo build > build.log; grep ProjectSettings/ProjectSettings.asset build.log')" \
    "does not block an unrelated grep chained after a redirect to a different file"

# --- Round-1 review finding: the command-start anchor was too narrow --------------------
# A prior version of this fix anchored a destructive verb only to literal string-start or
# right after ;/&&/||/|. That is narrower than where a real shell actually starts a command:
# leading whitespace, a sudo/env-style prefix, and an opening ( or { are all ordinary, and a
# verb reached through xargs is a real command position for the process xargs execs even
# though it is not the lexical first word of the line. All four were measured to slip through
# as false negatives (RC=0 where the command really does destroy something) before CMD_START
# was broadened to account for them.
assert_eq "2" "$(tbg_run '  rm -rf Library/')" \
    "still blocks rm -rf Library/ with leading whitespace"
assert_eq "2" "$(tbg_run 'sudo rm -rf Library/')" \
    "still blocks rm -rf Library/ behind a sudo prefix"
assert_eq "2" "$(tbg_run '(rm -rf Library/)')" \
    "still blocks rm -rf Library/ inside a subshell"
assert_eq "2" "$(tbg_run 'echo x | xargs -I{} rm -f Assets/Player.cs.meta')" \
    "still blocks a .meta deletion reached through xargs"

# ============================================================================================
# 2026-08-13 — the O1 probes, both directions for every row.
#
# WHY THIS FILE DID NOT CATCH THEM. Everything above is one shape: a PATH appearing as data
# rather than as a target (ProjectSettings/…, *.meta). That is the family that was fixed when
# this file was written, and it is the only family this file ever sent a payload for. The five
# patterns that leaked were about a VERB — `git reset --hard`, `git clean`, `git push --force`,
# destructive SQL, a PlayerPrefs wipe — and not one of them had ever been fed a command here,
# in either direction. The file was not weak on its subject; its subject was narrower than the
# hook. A guard's silence is only as wide as what it read.
#
# WHY EVERY ROW IS ASSERTED TWICE. An assertion that only proves the prose passes is also
# satisfied by a gate that blocks nothing whatsoever — deleting the pattern, or the whole
# hook, would leave it green. The paired "still blocks" assertion is what makes the fix
# provable rather than merely plausible, because an anchor that is slightly wrong turns a
# false positive into a false negative and that is the more expensive direction.
#
# Every command below is a distinct string on purpose: bash-gate is a two-stage gate keyed on
# a hash of the whole command, so re-using a string that an earlier assertion already tripped
# would make the second one pass by memory rather than by classification.
# ============================================================================================

# --- O1 row 1: prose about the hard reset ---------------------------------------------------
assert_eq "0" "$(tbg_run 'echo "never run git reset --hard here"')" \
    "does not block an echo warning against the hard reset"
assert_eq "2" "$(tbg_run 'git reset --hard HEAD~1')" \
    "still blocks the hard reset itself"
assert_eq "2" "$(tbg_run 'cd Assets && git reset --hard')" \
    "still blocks the hard reset after a control operator"
assert_eq "2" "$(tbg_run 'git -C /repo reset --hard')" \
    "still blocks the hard reset behind a git -C option"
assert_eq "2" "$(tbg_run 'git --git-dir=/r/.git clean -fdx')" \
    "still blocks git clean behind a --git-dir option"
assert_eq "2" "$(tbg_run 'git --no-pager -c core.pager=cat reset --hard')" \
    "still blocks the hard reset behind stacked git global options"

# --- O1 row 2: a commit message quoting it --------------------------------------------------
# The repository's own plans carry a standing instruction to write commit messages to a file
# and use `git commit -F`, because of this. `git` is in real command position here, which is
# why the anchor must not put a permissive gap between `git` and its subcommand.
assert_eq "0" "$(tbg_run 'git commit -m "docs: warn about git reset --hard"')" \
    "does not block a commit message that quotes the hard reset"
assert_eq "0" "$(tbg_run 'git commit -m "chore: describe git clean -fdx in the runbook"')" \
    "does not block a commit message that quotes git clean"
assert_eq "2" "$(tbg_run 'git clean -fdx')" \
    "still blocks git clean itself"
assert_eq "0" "$(tbg_run 'echo "never git push --force to main"')" \
    "does not block an echo warning against a force push"
assert_eq "2" "$(tbg_run 'git push --force origin main')" \
    "still blocks a force push to a protected branch"
assert_eq "2" "$(tbg_run 'git push -f origin spike/x')" \
    "still blocks a short-flag force push"

# --- O1 row 3: a grep for the prefs-wipe API ------------------------------------------------
# `PlayerPrefs.DeleteAll` is a C# member expression. No shell command position exists for it,
# so every Bash command containing it was text about the wipe; the acts that do erase
# preferences from a shell are the two below.
assert_eq "0" "$(tbg_run 'grep -rn PlayerPrefs.DeleteAll Assets/')" \
    "does not block a grep for the prefs-wipe API"
assert_eq "0" "$(tbg_run 'git commit -m "fix: stop calling PlayerPrefs.DeleteAll on load"')" \
    "does not block a commit message naming the prefs-wipe API"
assert_eq "2" "$(tbg_run 'defaults delete unity.Acme.Game')" \
    "still blocks the macOS defaults delete of a unity domain"
assert_eq "2" "$(tbg_run 'rm -rf ~/.config/unity3d/Acme/Game')" \
    "still blocks deleting the Linux unity3d prefs directory"

# --- O1 row 3b: destructive SQL -------------------------------------------------------------
# Anchoring SQL to a command position would have switched this classification off entirely —
# `psql -c "DROP TABLE x"` never has the SQL in command position. What separates the act from
# the text is that a database client is named too.
assert_eq "0" "$(tbg_run 'grep -rn "DROP TABLE" migrations/')" \
    "does not block a grep for destructive SQL"
assert_eq "2" "$(tbg_run 'psql -c "DROP TABLE users"')" \
    "still blocks destructive SQL passed to a client"
assert_eq "2" "$(tbg_run 'sqlite3 save.db "drop database main"')" \
    "still blocks destructive SQL passed to sqlite3"

# --- O1 row 4: a find that counts rather than deletes ---------------------------------------
# `find` is a search verb: on its own it prints paths and changes nothing. It was in the same
# alternation as `rm`, so every find naming .meta was classified a deletion.
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" | wc -l')" \
    "does not block a find that counts .meta files"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -newer Assets/Player.cs -print')" \
    "does not block a find that lists .meta files"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -delete')" \
    "still blocks find -delete on .meta files"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec rm {} \;')" \
    "still blocks find -exec rm on .meta files"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -print0 | xargs -0 rm')" \
    "still blocks find piped into xargs rm on .meta files"

# Review finding: the first cut of the find clause asked for a DELETION verb only, so the find
# route to a mass RENAME went from blocked to allowed while this file's own header and
# docs/HOOK-REFERENCE.md both promised "mass .meta deletion or rename". The verb is also matched
# as a token rather than after a space, because three of these four do not put a space there.
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec mv {} /tmp \;')" \
    "still blocks the find route to a mass .meta rename"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec /bin/rm {} \;')" \
    "still blocks find -exec with a path-prefixed rm"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec git rm {} \;')" \
    "still blocks find -exec git rm"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec sh -c "rm \$1" _ {} \;')" \
    "still blocks find -exec through a shell wrapper"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec stat {} \;')" \
    "does not block find -exec with a read-only command"

# ============================================================================================
# The find route is decided by an ALLOWLIST of read-only commands, not a denylist of harmful
# ones — and these assertions are what hold that shape in place.
#
# The denylist was written out by hand three times and was wrong every time: `rm`; then `mv`
# after review; then unlink/shred/truncate/rename/prename/mmv after re-review — and a mechanical
# sweep still found 49 misses in 58 binaries. The decisive miss was `perl-rename`, the SAME tool
# as `prename` under another standard name, missed by the same left-boundary mechanism the
# hook's comment had just finished explaining.
#
# `gzip` is the probe verb below on purpose: it appeared on no denylist this task ever wrote,
# it destroys a .meta file completely, and nothing about it is exotic.
# ============================================================================================

# The verbs that were on the denylist must still block — now for a different reason.
for tbg_verb in rm unlink shred truncate mv rename prename mmv; do
    assert_eq "2" "$(tbg_run "find Assets -name '*.meta' -exec $tbg_verb {} \\;")" \
        "still blocks find -exec $tbg_verb"
done

# The aliases and verbs no denylist had. Each was blocked at be2a582, allowed under the denylist.
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec perl-rename s/meta/bak/ {} \;')" \
    "blocks find -exec perl-rename — the alias that proved a denylist cannot be finished"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec file-rename s/meta/bak/ {} \;')" \
    "blocks find -exec file-rename, the same tool under its third name"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec gzip {} \;')" \
    "blocks find -exec gzip, which no denylist this task wrote contained"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec dd if=/dev/null of={} \;')" \
    "blocks find -exec dd"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec sed -i s/guid/x/ {} \;')" \
    "blocks find -exec sed, which rewrites in place and is deliberately not allowlisted"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec python3 wipe.py {} \;')" \
    "blocks find -exec python3 — an interpreter is not a read-only command"

# Every route to an exec'd command, on a verb the denylist never had.
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -execdir gzip {} \;')" \
    "blocks the -execdir route"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -ok gzip {} \;')" \
    "blocks the -ok route"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec gzip {} +')" \
    "blocks the -exec {} + route"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -print0 | xargs -0 gzip')" \
    "blocks the xargs -0 route"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" | xargs -I{} gzip {}')" \
    "blocks the xargs -I route, whose placeholder must not be read as the command"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec /usr/bin/gzip {} \;')" \
    "blocks a path-prefixed command"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec env gzip {} \;')" \
    "blocks a command behind an env prefix"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec sh -c "gzip \$1" _ {} \;')" \
    "blocks a command behind a shell wrapper, because sh is not read-only"

# The allowlist itself. These must pass, and O1 probe 4 depends on the first two.
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec stat {} \;')" \
    "does not block find -exec stat"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec grep -l guid {} \;')" \
    "does not block find -exec grep, which reads the GUIDs it names"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec /usr/bin/grep -l guid {} \;')" \
    "does not block a path-prefixed read-only command"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec md5sum {} \;')" \
    "does not block find -exec md5sum"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec basename {} \;')" \
    "does not block find -exec basename"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -print0 | xargs -0 grep -l guid')" \
    "does not block a read-only command reached through xargs"

# The inversion's own dividend: these two were declared-and-accepted false positives under the
# denylist, because a destructive verb NAMED as an argument tripped it. The exec'd command is
# `grep`, so they are now correct passes rather than tolerated ones.
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec grep -l rm {} \;')" \
    "does not block a grep whose PATTERN is a destructive verb"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec grep -l mv {} \;')" \
    "does not block a grep searching for the other one"

# --- the direct shape stays a denylist, by ruling -------------------------------------------
# You cannot allowlist every harmless command that might name a .meta path, so this arm needs
# verbs and is incomplete by construction. These five passed until this round; all five are
# pre-existing gaps (identical at be2a582), not regressions from this task.
assert_eq "2" "$(tbg_run 'unlink Assets/Player.cs.meta')" \
    "blocks a direct unlink — the verb the classification is named after"
assert_eq "2" "$(tbg_run 'shred -u Assets/Player.cs.meta')" \
    "blocks a direct shred"
assert_eq "2" "$(tbg_run 'truncate -s 0 Assets/Player.cs.meta')" \
    "blocks a direct truncate"
assert_eq "2" "$(tbg_run 'perl-rename s/meta/bak/ Assets/Player.cs.meta')" \
    "blocks a direct perl-rename"
assert_eq "2" "$(tbg_run 'mmv "Assets/*.cs.meta" "Assets/#1.bak"')" \
    "blocks a direct mmv"
assert_eq "0" "$(tbg_run 'cat Assets/Player.cs.meta')" \
    "does not block reading a .meta file"

# --- classifications with no probe at all before this task ----------------------------------
# meta-rename and manifest-wipe had zero assertions here, and unity-dir-wipe had three blocking
# probes and no prose probe. Both halves of each, because a classification nothing sends a
# payload for is exactly how the five leaking patterns stayed invisible in the first place.
assert_eq "2" "$(tbg_run 'mv Assets/Player.cs.meta Assets/Enemy.cs.meta')" \
    "still blocks a direct .meta rename"
assert_eq "0" "$(tbg_run 'git log --follow -- Assets/Player.cs.meta')" \
    "does not block reading the history of a renamed .meta file"
assert_eq "2" "$(tbg_run 'echo {} > Packages/manifest.json')" \
    "still blocks a redirect over Packages/manifest.json"
assert_eq "2" "$(tbg_run 'rm -f Packages/manifest.json')" \
    "still blocks deleting Packages/manifest.json"
assert_eq "0" "$(tbg_run 'jq .dependencies Packages/manifest.json')" \
    "does not block reading Packages/manifest.json"
assert_eq "2" "$(tbg_run 'rm -rf Library/ Temp/')" \
    "still blocks a Library/Temp wipe"
assert_eq "0" "$(tbg_run 'echo "delete Library/ only when the editor is closed"')" \
    "does not block prose about wiping Library/"
assert_eq "0" "$(tbg_run 'du -sh Library/ Temp/ Logs/')" \
    "does not block measuring the directories a wipe would remove"

# --- O1 rows 5 and 6: block-projectsettings.sh was removed in this wave ----------------------
# Its true positive was `git add ProjectSettings/…`, which stages a file and mutates nothing;
# its false positive was any sentence containing that phrase, and `git add -A` — the command
# that actually stages the directory — was permitted throughout. Both are permitted now, by
# ruling. What must not change is that the ACT of writing that directory is still gated here,
# so these two assertions stand in for the removed hook's only defensible half.
assert_eq "2" "$(tbg_run 'cp /tmp/staged.asset ProjectSettings/ProjectSettings.asset')" \
    "still blocks copying over a ProjectSettings asset"
assert_eq "2" "$(tbg_run 'rm -f ProjectSettings/QualitySettings.asset')" \
    "still blocks deleting a ProjectSettings asset"

# ============================================================================================
# 2026-08-13 round 4 — THE VERB-EXTRACTION BOUNDARY IS ITS OWN FAILURE CLASS.
#
# Three separate misses now, all the same shape: a token classified by what it LOOKS like
# rather than by the position it occupies, so the real command was stepped over.
#
#   1. `prename` — the left boundary of a regex excluded `-`, so `rename` did not match inside
#      it. Missed in a comment that explained the mechanism.
#   2. `\rm` — the want-branch skip list carried a `'\'*` arm meaning to skip find's `\;`
#      terminator, and it skipped EVERY token starting with a backslash. `\rm` is the standard
#      alias-bypass spelling; the fix that removed a family of false negatives introduced one
#      on the verb the classification is named after. `-exec \mv {} /tmp \;` still blocked but
#      reported "runs 'tmp'" — having skipped `\mv` and `{}`, it landed on the next word.
#   3. `xargs -n 1 grep` — the option's ARGUMENT was read as the command, reported "runs '1'".
#
# Every payload below is asserted in both directions, because each of these fixes could be
# made by blocking more, and a gate that blocks everything satisfies the block half alone.
# ============================================================================================

# tbg_stderr — the message, not the exit code. Two of round 4's findings are sentences: the
# gate said "'git' is not a read-only command" (false for `git log` — the gate knows its own
# list, not the command) and demanded a rollback plan for what may be a read.
tbg_stderr() {
    printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s}}' \
        "$(printf '%s' "$1" | jq -Rs .)" \
        | UNITY_HOOK_STATE_DIR="$TBG_STATE_DIR" bash "$TBG_HOOK" 2>&1 >/dev/null || true
}

# --- the alias-bypass spelling, every route ---------------------------------------------
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec \rm {} \;')" \
    "blocks find -exec on a backslash-escaped rm"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -print0 | xargs -0 \rm')" \
    "blocks xargs on a backslash-escaped rm"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec \gzip {} \;')" \
    "blocks a backslash-escaped verb that was never on any denylist"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec \perl-rename s/meta/bak/ {} \;')" \
    "blocks a backslash-escaped perl-rename"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" | \xargs -0 rm')" \
    "blocks a backslash-escaped xargs — the INTRODUCER hides behind one too"

# The other direction, and it is the one that proves the fix is not "block any backslash":
# a read-only command keeps passing when it is written the alias-bypass way.
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec \grep -l guid {} \;')" \
    "does not block a backslash-escaped read-only command"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -print0 | \xargs -0 \grep -l guid')" \
    "does not block a backslash-escaped xargs running a read-only command"

# The message must name the verb, not the word after the one it skipped.
assert_contains "$(tbg_stderr 'find Assets -name "*.meta" -exec \mv {} /tmp/bak \;')" \
    "runs 'mv'" \
    "names the escaped verb rather than the argument after it"

# find's terminator is still skipped — in full, rather than by its first character.
assert_eq "2" "$(tbg_run "find Assets -name '*.meta' -exec rm {} ';'")" \
    "blocks a find whose terminator is quoted rather than escaped"
assert_eq "0" "$(tbg_run "find Assets -name '*.meta' -exec grep -c guid {} ';'")" \
    "does not block the read-only twin of the quoted-terminator form"

# --- the same class in CMD_START, for the direct arm ------------------------------------
# `\rm Assets/Player.cs.meta` really runs rm. The backslash sat between the command start and
# the verb, and every anchored pattern in the file missed it.
assert_eq "2" "$(tbg_run '\rm Assets/Enemy.cs.meta')" \
    "blocks a backslash-escaped direct .meta deletion"
assert_eq "2" "$(tbg_run '\rm -rf Library/')" \
    "blocks a backslash-escaped Library wipe"
assert_eq "2" "$(tbg_run '\mv Assets/A.cs.meta Assets/B.cs.meta')" \
    "blocks a backslash-escaped direct .meta rename"
assert_eq "2" "$(tbg_run '\git reset --hard HEAD~2')" \
    "blocks a backslash-escaped hard reset"
assert_eq "2" "$(tbg_run '\find Assets -name "*.meta" -delete')" \
    "blocks a backslash-escaped find -delete"
assert_eq "0" "$(tbg_run 'echo "use \rm to bypass the alias, but not in this repo"')" \
    "does not block prose that quotes the alias-bypass spelling"

# --- an option's argument is not the command --------------------------------------------
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -print0 | xargs -0 -n 1 grep -l guid')" \
    "does not block a read-only xargs whose option takes a separate argument"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -print0 | xargs -0 -n 1 gzip')" \
    "still blocks the destructive twin of that same xargs form"
# -i/-e/-l take an OPTIONAL ATTACHED argument, so skipping their next word would step over the
# command. These two are why the skip list names only the mandatory-separate options.
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" | xargs -i rm {}')" \
    "still blocks xargs -i rm, whose next word IS the command"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" | xargs -I {} rm {}')" \
    "still blocks xargs -I with a separate replacement string"

# ============================================================================================
# The allowlist means "cannot modify the files find hands it", not "usually harmless".
# Two members failed that test and are gone; a third was proposed and refused.
# ============================================================================================
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec du -h {} \;')" \
    "does not block find -exec du"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec b2sum {} \;')" \
    "does not block find -exec b2sum"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec sha512sum {} \;')" \
    "does not block find -exec sha512sum"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec identify {} \;')" \
    "does not block find -exec identify"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec [ -s {} ] \;')" \
    "does not block find -exec with the test builtin spelled as a bracket"

# touch mutates mtime, which is a Unity reimport trigger; sort -o is the documented in-place
# rewrite; dos2unix defaults to old-file mode, which overwrites what it is given. None of the
# three can sit on a list whose membership claims the file cannot be modified.
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec touch {} \;')" \
    "blocks find -exec touch, which rewrites mtime and triggers a reimport"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec sort -o {} {} \;')" \
    "blocks sort -o, which is the documented in-place rewrite"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec sort {} \;')" \
    "does not block a sort with no output flag"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec dos2unix {} \;')" \
    "blocks dos2unix, which converts in place unless told otherwise"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec openssl dgst -sha256 {} \;')" \
    "does not block an openssl digest"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec openssl rand -out {} 32 \;')" \
    "blocks openssl when it is given an output file"

# ============================================================================================
# Four commands are read-only in the form you meet them and destructive in one other form.
# The write flag is decided from the command's OWN argument tokens, bounded by its clause —
# not by regexing the whole command line, which is what let ten quoted and attached spellings
# through (see the positional block at the end of this file).
# ============================================================================================
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec sed -n /guid/p {} \;')" \
    "does not block a sed that only prints"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec sed -i.bak s/guid/x/ {} \;')" \
    "blocks sed -i with a backup suffix attached"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec sed --in-place s/guid/x/ {} \;')" \
    "blocks the long spelling of sed's in-place flag"
assert_eq "0" "$(tbg_run 'find Assets -iname "*.meta" -exec sed -n 1p {} \;')" \
    "does not read find's own -iname as sed's -i"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec git log --oneline {} \;')" \
    "does not block git log — the sentence it used to print about it was false"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec git blame -L 1,2 {} \;')" \
    "does not block git blame"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec git mv {} /tmp/bak \;')" \
    "still blocks git mv, which is not on the read-only subcommand list"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec git rm --cached {} \; && git log --oneline')" \
    "does not let an unrelated git log later on the line vouch for git rm"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec awk /guid/ {} \;')" \
    "does not block an awk that only matches"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec awk "{print > \"o.txt\"}" {} \;')" \
    "blocks an awk program containing a redirect"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec yq .guid {} \;')" \
    "does not block a yq query"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec yq -i .guid=1 {} \;')" \
    "blocks yq -i, which writes the file back"

# ============================================================================================
# The message is a claim about the gate, and the demand is proportionate to what it knows.
# ============================================================================================
assert_contains "$(tbg_stderr 'find Assets -name "*.meta" -exec pandoc {} \;')" \
    "is not on this gate's read-only list" \
    "says the command is not on the gate's list, not that it is not read-only"
assert_contains "$(tbg_stderr 'find Assets -name "*.meta" -exec pandoc -t plain {} \;')" \
    "UNRECOGNISED COMMAND OVER .meta FILES" \
    "does not call an unrecognised command destructive"
assert_contains "$(tbg_stderr 'find Assets -name "*.meta" -exec pandoc -t html {} \;')" \
    "do not manufacture a rollback plan for a read" \
    "offers the one-line answer when the command may be a read"
# The classifications that DO know the act is destructive keep the full demand.
assert_contains "$(tbg_stderr 'find Assets/Art -name "*.meta" -delete')" \
    "DESTRUCTIVE COMMAND" \
    "still calls find -delete destructive, because there the verb is find's own flag"
assert_contains "$(tbg_stderr 'find Assets/Art -name "*.meta" -newer x -delete')" \
    "Write a one-line rollback procedure" \
    "still demands a rollback plan for a deletion"

# ============================================================================================
# 2026-08-13 round 5 — THE FLAG IS A POSITION TOO.
#
# The first cut of the second stage above decided `-i` by regexing the WHOLE RAW COMMAND with
# a right boundary of `([[:space:]]|=|\.|$)`. Shell quoting and attached suffixes walk past
# that boundary, so ten spellings that rewrite every .meta file they are handed were permitted
# — including `sed -i''`, which is the canonical cross-platform spelling and the one someone
# writes in THIS repository, because a macOS host pass is planned. Five were verified against
# real files with GNU sed 4.9 and gawk 5.2.1. Round 3 blocked all ten, because its allowlist
# had no second stage at all; the fix for one false-positive class opened a false-negative one.
#
# It is the same defect as the backslash and the xargs argument, one level up: a token judged
# by its SHAPE in a wide haystack instead of by the POSITION it occupies — while the function
# next door was already holding the tokenised argument list.
#
# SO THESE ASSERT THE CLASS, NOT THE TEN SPELLINGS. Ten spellings is the shape that has been
# wrong five times in this task. What is asserted is that the flag is found when it is an
# ARGUMENT OF THE EXEC'D COMMAND — bare, attached, quoted away to nothing, or a separate pair —
# and not found when the same characters belong to something else on the line.
# ============================================================================================

# --- a token that IS the flag, however it is spelled ----------------------------------------
assert_eq "2" "$(tbg_run "find Assets -name '*.meta' -exec sed -i'' -e s/guid/x/ {} \\;")" \
    "blocks sed -i'' — the cross-platform spelling, quoted away to nothing"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec sed -i"" s/guid/x/ {} \;')" \
    "blocks sed -i with an empty double-quoted suffix"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec sed "-i" s/guid/x/ {} \;')" \
    "blocks sed when the flag itself is quoted"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec sed -ibak s/guid/x/ {} \;')" \
    "blocks sed -ibak, whose suffix is attached with no separator at all"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec sed -i~ s/guid/x/ {} \;')" \
    "blocks sed -i~, whose suffix is not a word character"
assert_eq "2" "$(tbg_run "find Assets -name '*.meta' -exec sed -i'.bak' s/guid/x/ {} \\;")" \
    "blocks sed -i with a quoted suffix"
assert_eq "2" "$(tbg_run "find Assets -name '*.meta' -exec gsed -i'' s/guid/x/ {} \\;")" \
    "blocks the same spelling under the GNU-on-macOS name"
assert_eq "2" "$(tbg_run "find Assets -name '*.meta' -exec yq -i'' .guid=1 {} \\;")" \
    "blocks the same spelling for yq"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec gawk -i inplace "{print}" {} \;')" \
    "blocks gawk -i inplace, where the flag and its value are a separate pair"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec awk -i inplace "{print $0}" {} \;')" \
    "blocks awk -i inplace under the unprefixed name"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec sort -o{} {} \;')" \
    "blocks sort with its output file attached to the flag"

# --- the same characters, belonging to something else on the line ---------------------------
# Each of these was blocked by the whole-line regex. The exec'd command's own arguments contain
# no write flag, and that is the only thing that decides now.
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec sed -n /guid/p {} \; | grep -i guid')" \
    "does not read a later grep -i as sed's in-place flag"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -print0 | xargs -0 -i sed -n 1p {}')" \
    "does not read xargs' own -i as sed's in-place flag"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec awk "{print}" {} \; > /tmp/o.txt')" \
    "does not read a shell redirect after the clause as awk's"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec awk "{print}" {} \; 2>/dev/null')" \
    "does not read a stderr redirect after the clause as awk's"
assert_eq "0" "$(tbg_run 'find Assets \( -name "*.meta" -o -name "*.asset" \) -exec sort {} \;')" \
    "does not read find's own -o as sort's output flag"
assert_eq "0" "$(tbg_run 'find Assets -ipath "*/Art/*.meta" -exec sed -n 1p {} \;')" \
    "does not read find's -ipath as sed's in-place flag"
assert_eq "0" "$(tbg_run 'find Assets -not -name "*.cs" -name "*.meta" -exec sort {} \;')" \
    "does not read find's -not as an output flag"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -print0 -follow -exec sed -n 1p {} \;')" \
    "does not read find's -follow or -print0 as a write flag"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec git -C /repo log --oneline {} \;')" \
    "does not lose git's subcommand behind a global option with its own argument"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec git --git-dir=/r/.git log {} \;')" \
    "does not lose git's subcommand behind an attached global option"

# Skipping a global option's argument must not become a way to hide the subcommand behind it,
# and a write flag counts wherever it sits among the command's own arguments — not only first.
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec git -C /repo rm {} \;')" \
    "still blocks git rm reached past a global option"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec sed -e s/a/b/ -i {} \;')" \
    "blocks sed -i when the flag comes after the expression"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec sort -u -o {} {} \;')" \
    "blocks sort -o when another flag comes first"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec yq --inplace .guid=1 {} \;')" \
    "blocks the long spelling of yq's in-place flag"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec gawk --include=inplace "{print}" {} \;')" \
    "blocks gawk's long spelling of the in-place include"

# --- the clause boundary must not become a vouching direction -------------------------------
# The bound is what keeps an unrelated command out of the decision. It must not also let one
# clause speak for another: the reader stops at the FIRST command that is not read-only,
# whichever end of the line it sits at.
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec grep -l guid {} \; -exec gzip -9 {} \;')" \
    "blocks the second clause when the first one is read-only"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec gzip -1 {} \; -exec grep -l guid {} \;')" \
    "blocks the first clause when the second one is read-only"
assert_eq "2" "$(tbg_run 'git status && find Assets -name "*.meta" -exec git rm {} \;')" \
    "does not let a git status ahead of the find vouch for the git rm inside it"

# ============================================================================================
# 2026-08-14 task 2b — THE TOKENISER HAS A QUOTE MODEL, AND THIS CORPUS IS WHAT HOLDS IT.
#
# Rounds 3, 4 and 5 of this hook each closed one hole in the find route and opened another, and
# every round's own probes passed. What caught each hole was a reader who had a DIFFERENT idea.
# Round 5's implementer wrote the sentence: "A test built from the same idea as the code
# confirms the idea, not the behaviour."
#
# A corpus cannot have a different idea on its own. It can be checked against HISTORY, which is
# a different idea by construction — so every record below carries a frozen `hist` column: the
# exit codes the same payload got from the hook at 546870f (r3), 06883cc (r4) and 3fd22dc (r5),
# in that order. A payload an earlier version BLOCKED and this one PERMITS is a regression by
# definition, and it may only be recorded as `X` with a written reason. That is the mechanism
# that makes the r3 -> r4 -> r5 pattern impossible to repeat by accident.
#
# WHAT THIS CANNOT SEE, stated plainly because a check's silence is only as wide as what it
# read: it freezes the PAST. It catches re-opening an old hole and says exactly nothing about a
# new one. Nothing here would have caught the round-5 Critical before it was written, because no
# earlier version had ever been sent a quoted awk program either.
#
# HOW TO REGENERATE THE `hist` COLUMN (it is data, not derivation — the permanent test runs
# inside a `git archive` scratch copy and cannot shell out to git):
#
#   for rev in 546870f 06883cc 3fd22dc; do
#       git show "$rev:.claude/hooks/bash-gate.sh" > "/tmp/gate-$rev.sh"
#   done
#   # then, for each payload below, send it to each of the three with a FRESH
#   # UNITY_HOOK_STATE_DIR (see tbg_run_fresh) and record the three exit codes in that order.
#
# RECORD FORMAT — two lines each, so a payload never has to be escaped or quoted:
#   line 1:  <expected-rc> <hist> <exempt> <one-line reason>
#   line 2:  the payload, verbatim, leading whitespace significant
# `exempt` is `-`, or `X` when this version permits something an earlier version blocked.
# ============================================================================================

# A FRESH STATE DIR PER PROBE. The corpus deliberately repeats payloads that assertions above
# have already sent, and bash-gate is a two-stage gate keyed on a hash of the whole command:
# reusing $TBG_STATE_DIR here would make the second send pass by MEMORY rather than by
# classification, which is the exact failure this file's own header warns about.
tbg_run_fresh() {
    local _sd _rc
    _sd="$(mktemp -d "${TMPDIR:-/tmp}/bash-gate-corpus.XXXXXX")"
    printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s}}' \
        "$(printf '%s' "$1" | jq -Rs .)" \
        | UNITY_HOOK_STATE_DIR="$_sd" bash "$TBG_HOOK" > /dev/null 2>&1
    _rc=$?
    rm -rf "$_sd"
    printf '%s' "$_rc"
}

tbg_corpus() {
    cat <<'TBG_CORPUS'
2 222 - still blocks a real redirect into ProjectSettings
echo hi > ProjectSettings/ProjectSettings.asset
2 222 - still blocks a real .meta deletion
rm -f Assets/Player.cs.meta
0 000 - does not block a grep that merely names ProjectSettings
grep -n ProjectSettings/ProjectSettings.asset notes.txt
0 000 - does not block an echo that merely mentions the path
echo "see ProjectSettings/ProjectSettings.asset for details"
0 000 - does not block reading history of a .meta file
git log -- Assets/Player.cs.meta
0 000 - does not block a JSON argument that merely contains the word cp and the path as data
curl -s https://api.example.com/report -d "{\"reason\": \"cp shows drift\", \"target\":\"ProjectSettings/ProjectSettings.asset\"}"
0 000 - does not block an unrelated grep chained after a redirect to a different file
echo build > build.log; grep ProjectSettings/ProjectSettings.asset build.log
2 222 - still blocks rm -rf Library/ with leading whitespace
  rm -rf Library/
2 222 - still blocks rm -rf Library/ behind a sudo prefix
sudo rm -rf Library/
2 222 - still blocks rm -rf Library/ inside a subshell
(rm -rf Library/)
2 222 - still blocks a .meta deletion reached through xargs
echo x | xargs -I{} rm -f Assets/Player.cs.meta
0 000 - does not block an echo warning against the hard reset
echo "never run git reset --hard here"
2 222 - still blocks the hard reset itself
git reset --hard HEAD~1
2 222 - still blocks the hard reset after a control operator
cd Assets && git reset --hard
2 222 - still blocks the hard reset behind a git -C option
git -C /repo reset --hard
2 222 - still blocks git clean behind a --git-dir option
git --git-dir=/r/.git clean -fdx
2 222 - still blocks the hard reset behind stacked git global options
git --no-pager -c core.pager=cat reset --hard
0 000 - does not block a commit message that quotes the hard reset
git commit -m "docs: warn about git reset --hard"
0 000 - does not block a commit message that quotes git clean
git commit -m "chore: describe git clean -fdx in the runbook"
2 222 - still blocks git clean itself
git clean -fdx
0 000 - does not block an echo warning against a force push
echo "never git push --force to main"
2 222 - still blocks a force push to a protected branch
git push --force origin main
2 222 - still blocks a short-flag force push
git push -f origin spike/x
0 000 - does not block a grep for the prefs-wipe API
grep -rn PlayerPrefs.DeleteAll Assets/
0 000 - does not block a commit message naming the prefs-wipe API
git commit -m "fix: stop calling PlayerPrefs.DeleteAll on load"
2 222 - still blocks the macOS defaults delete of a unity domain
defaults delete unity.Acme.Game
2 222 - still blocks deleting the Linux unity3d prefs directory
rm -rf ~/.config/unity3d/Acme/Game
0 000 - does not block a grep for destructive SQL
grep -rn "DROP TABLE" migrations/
2 222 - still blocks destructive SQL passed to a client
psql -c "DROP TABLE users"
2 222 - still blocks destructive SQL passed to sqlite3
sqlite3 save.db "drop database main"
0 000 - does not block a find that counts .meta files
find Assets -name "*.meta" | wc -l
0 000 - does not block a find that lists .meta files
find Assets -name "*.meta" -newer Assets/Player.cs -print
2 222 - still blocks find -delete on .meta files
find Assets -name "*.meta" -delete
2 222 - still blocks find -exec rm on .meta files
find Assets -name "*.meta" -exec rm {} \;
2 222 - still blocks find piped into xargs rm on .meta files
find Assets -name "*.meta" -print0 | xargs -0 rm
2 222 - still blocks the find route to a mass .meta rename
find Assets -name "*.meta" -exec mv {} /tmp \;
2 222 - still blocks find -exec with a path-prefixed rm
find Assets -name "*.meta" -exec /bin/rm {} \;
2 222 - still blocks find -exec git rm
find Assets -name "*.meta" -exec git rm {} \;
2 222 - still blocks find -exec through a shell wrapper
find Assets -name "*.meta" -exec sh -c "rm \$1" _ {} \;
0 000 - does not block find -exec with a read-only command
find Assets -name "*.meta" -exec stat {} \;
2 222 - still blocks find -exec rm
find Assets -name '*.meta' -exec rm {} \;
2 222 - still blocks find -exec unlink
find Assets -name '*.meta' -exec unlink {} \;
2 222 - still blocks find -exec shred
find Assets -name '*.meta' -exec shred {} \;
2 222 - still blocks find -exec truncate
find Assets -name '*.meta' -exec truncate {} \;
2 222 - still blocks find -exec mv
find Assets -name '*.meta' -exec mv {} \;
2 222 - still blocks find -exec rename
find Assets -name '*.meta' -exec rename {} \;
2 222 - still blocks find -exec prename
find Assets -name '*.meta' -exec prename {} \;
2 222 - still blocks find -exec mmv
find Assets -name '*.meta' -exec mmv {} \;
2 222 - blocks find -exec perl-rename — the alias that proved a denylist cannot be finished
find Assets -name "*.meta" -exec perl-rename s/meta/bak/ {} \;
2 222 - blocks find -exec file-rename, the same tool under its third name
find Assets -name "*.meta" -exec file-rename s/meta/bak/ {} \;
2 222 - blocks find -exec gzip, which no denylist this task wrote contained
find Assets -name "*.meta" -exec gzip {} \;
2 222 - blocks find -exec dd
find Assets -name "*.meta" -exec dd if=/dev/null of={} \;
2 222 - blocks find -exec sed, which rewrites in place and is deliberately not allowlisted
find Assets -name "*.meta" -exec sed -i s/guid/x/ {} \;
2 222 - blocks find -exec python3 — an interpreter is not a read-only command
find Assets -name "*.meta" -exec python3 wipe.py {} \;
2 222 - blocks the -execdir route
find Assets -name "*.meta" -execdir gzip {} \;
2 222 - blocks the -ok route
find Assets -name "*.meta" -ok gzip {} \;
2 222 - blocks the -exec {} + route
find Assets -name "*.meta" -exec gzip {} +
2 222 - blocks the xargs -0 route
find Assets -name "*.meta" -print0 | xargs -0 gzip
2 222 - blocks the xargs -I route, whose placeholder must not be read as the command
find Assets -name "*.meta" | xargs -I{} gzip {}
2 222 - blocks a path-prefixed command
find Assets -name "*.meta" -exec /usr/bin/gzip {} \;
2 222 - blocks a command behind an env prefix
find Assets -name "*.meta" -exec env gzip {} \;
2 222 - blocks a command behind a shell wrapper, because sh is not read-only
find Assets -name "*.meta" -exec sh -c "gzip \$1" _ {} \;
0 000 - does not block find -exec grep, which reads the GUIDs it names
find Assets -name "*.meta" -exec grep -l guid {} \;
0 000 - does not block a path-prefixed read-only command
find Assets -name "*.meta" -exec /usr/bin/grep -l guid {} \;
0 000 - does not block find -exec md5sum
find Assets -name "*.meta" -exec md5sum {} \;
0 000 - does not block find -exec basename
find Assets -name "*.meta" -exec basename {} \;
0 000 - does not block a read-only command reached through xargs
find Assets -name "*.meta" -print0 | xargs -0 grep -l guid
0 000 - does not block a grep whose PATTERN is a destructive verb
find Assets -name "*.meta" -exec grep -l rm {} \;
0 000 - does not block a grep searching for the other one
find Assets -name "*.meta" -exec grep -l mv {} \;
2 222 - blocks a direct unlink — the verb the classification is named after
unlink Assets/Player.cs.meta
2 222 - blocks a direct shred
shred -u Assets/Player.cs.meta
2 222 - blocks a direct truncate
truncate -s 0 Assets/Player.cs.meta
2 222 - blocks a direct perl-rename
perl-rename s/meta/bak/ Assets/Player.cs.meta
2 222 - blocks a direct mmv
mmv "Assets/*.cs.meta" "Assets/#1.bak"
0 000 - does not block reading a .meta file
cat Assets/Player.cs.meta
2 222 - still blocks a direct .meta rename
mv Assets/Player.cs.meta Assets/Enemy.cs.meta
0 000 - does not block reading the history of a renamed .meta file
git log --follow -- Assets/Player.cs.meta
2 222 - still blocks a redirect over Packages/manifest.json
echo {} > Packages/manifest.json
2 222 - still blocks deleting Packages/manifest.json
rm -f Packages/manifest.json
0 000 - does not block reading Packages/manifest.json
jq .dependencies Packages/manifest.json
2 222 - still blocks a Library/Temp wipe
rm -rf Library/ Temp/
0 000 - does not block prose about wiping Library/
echo "delete Library/ only when the editor is closed"
0 000 - does not block measuring the directories a wipe would remove
du -sh Library/ Temp/ Logs/
2 222 - still blocks copying over a ProjectSettings asset
cp /tmp/staged.asset ProjectSettings/ProjectSettings.asset
2 222 - still blocks deleting a ProjectSettings asset
rm -f ProjectSettings/QualitySettings.asset
2 022 - blocks find -exec on a backslash-escaped rm
find Assets -name "*.meta" -exec \rm {} \;
2 022 - blocks xargs on a backslash-escaped rm
find Assets -name "*.meta" -print0 | xargs -0 \rm
2 022 - blocks a backslash-escaped verb that was never on any denylist
find Assets -name "*.meta" -exec \gzip {} \;
2 022 - blocks a backslash-escaped perl-rename
find Assets -name "*.meta" -exec \perl-rename s/meta/bak/ {} \;
2 022 - blocks a backslash-escaped xargs — the INTRODUCER hides behind one too
find Assets -name "*.meta" | \xargs -0 rm
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec \grep -l guid {} \;
0 000 - does not block a backslash-escaped xargs running a read-only command
find Assets -name "*.meta" -print0 | \xargs -0 \grep -l guid
2 222 - blocks a find whose terminator is quoted rather than escaped
find Assets -name '*.meta' -exec rm {} ';'
0 000 - does not block the read-only twin of the quoted-terminator form
find Assets -name '*.meta' -exec grep -c guid {} ';'
2 022 - blocks a backslash-escaped direct .meta deletion
\rm Assets/Enemy.cs.meta
2 022 - blocks a backslash-escaped Library wipe
\rm -rf Library/
2 022 - blocks a backslash-escaped direct .meta rename
\mv Assets/A.cs.meta Assets/B.cs.meta
2 022 - blocks a backslash-escaped hard reset
\git reset --hard HEAD~2
2 022 - blocks a backslash-escaped find -delete
\find Assets -name "*.meta" -delete
0 000 - does not block prose that quotes the alias-bypass spelling
echo "use \rm to bypass the alias, but not in this repo"
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -print0 | xargs -0 -n 1 grep -l guid
2 222 - still blocks the destructive twin of that same xargs form
find Assets -name "*.meta" -print0 | xargs -0 -n 1 gzip
2 222 - still blocks xargs -i rm, whose next word IS the command
find Assets -name "*.meta" | xargs -i rm {}
2 222 - still blocks xargs -I with a separate replacement string
find Assets -name "*.meta" | xargs -I {} rm {}
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec du -h {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec b2sum {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec sha512sum {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec identify {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec [ -s {} ] \;
2 022 - blocks find -exec touch, which rewrites mtime and triggers a reimport
find Assets -name "*.meta" -exec touch {} \;
2 022 - blocks sort -o, which is the documented in-place rewrite
find Assets -name "*.meta" -exec sort -o {} {} \;
0 000 - does not block a sort with no output flag
find Assets -name "*.meta" -exec sort {} \;
2 222 - blocks dos2unix, which converts in place unless told otherwise
find Assets -name "*.meta" -exec dos2unix {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec openssl dgst -sha256 {} \;
2 222 - blocks openssl when it is given an output file
find Assets -name "*.meta" -exec openssl rand -out {} 32 \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec sed -n /guid/p {} \;
2 222 - blocks sed -i with a backup suffix attached
find Assets -name "*.meta" -exec sed -i.bak s/guid/x/ {} \;
2 222 - blocks the long spelling of sed's in-place flag
find Assets -name "*.meta" -exec sed --in-place s/guid/x/ {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -iname "*.meta" -exec sed -n 1p {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec git log --oneline {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec git blame -L 1,2 {} \;
2 222 - still blocks git mv, which is not on the read-only subcommand list
find Assets -name "*.meta" -exec git mv {} /tmp/bak \;
2 222 - does not let an unrelated git log later on the line vouch for git rm
find Assets -name "*.meta" -exec git rm --cached {} \; && git log --oneline
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec awk /guid/ {} \;
2 222 - blocks an awk program containing a redirect
find Assets -name "*.meta" -exec awk "{print > \"o.txt\"}" {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec yq .guid {} \;
2 222 - blocks yq -i, which writes the file back
find Assets -name "*.meta" -exec yq -i .guid=1 {} \;
2 202 - blocks sed -i'' — the cross-platform spelling, quoted away to nothing
find Assets -name '*.meta' -exec sed -i'' -e s/guid/x/ {} \;
2 202 - blocks sed -i with an empty double-quoted suffix
find Assets -name "*.meta" -exec sed -i"" s/guid/x/ {} \;
2 202 - blocks sed when the flag itself is quoted
find Assets -name "*.meta" -exec sed "-i" s/guid/x/ {} \;
2 202 - blocks sed -ibak, whose suffix is attached with no separator at all
find Assets -name "*.meta" -exec sed -ibak s/guid/x/ {} \;
2 202 - blocks sed -i~, whose suffix is not a word character
find Assets -name "*.meta" -exec sed -i~ s/guid/x/ {} \;
2 202 - blocks sed -i with a quoted suffix
find Assets -name '*.meta' -exec sed -i'.bak' s/guid/x/ {} \;
2 202 - blocks the same spelling under the GNU-on-macOS name
find Assets -name '*.meta' -exec gsed -i'' s/guid/x/ {} \;
2 202 - blocks the same spelling for yq
find Assets -name '*.meta' -exec yq -i'' .guid=1 {} \;
2 202 - blocks gawk -i inplace, where the flag and its value are a separate pair
find Assets -name "*.meta" -exec gawk -i inplace "{print}" {} \;
2 202 - blocks awk -i inplace under the unprefixed name
find Assets -name "*.meta" -exec awk -i inplace "{print $0}" {} \;
2 002 - blocks sort with its output file attached to the flag
find Assets -name "*.meta" -exec sort -o{} {} \;
0 220 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets -name "*.meta" -exec sed -n /guid/p {} \; | grep -i guid
0 220 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets -name "*.meta" -print0 | xargs -0 -i sed -n 1p {}
0 220 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets -name "*.meta" -exec awk "{print}" {} \; > /tmp/o.txt
0 220 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets -name "*.meta" -exec awk "{print}" {} \; 2>/dev/null
0 020 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets \( -name "*.meta" -o -name "*.asset" \) -exec sort {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -ipath "*/Art/*.meta" -exec sed -n 1p {} \;
0 000 - does not read find's -not as an output flag
find Assets -not -name "*.cs" -name "*.meta" -exec sort {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -print0 -follow -exec sed -n 1p {} \;
0 220 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets -name "*.meta" -exec git -C /repo log --oneline {} \;
0 220 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets -name "*.meta" -exec git --git-dir=/r/.git log {} \;
2 222 - still blocks git rm reached past a global option
find Assets -name "*.meta" -exec git -C /repo rm {} \;
2 222 - blocks sed -i when the flag comes after the expression
find Assets -name "*.meta" -exec sed -e s/a/b/ -i {} \;
2 022 - blocks sort -o when another flag comes first
find Assets -name "*.meta" -exec sort -u -o {} {} \;
2 222 - blocks the long spelling of yq's in-place flag
find Assets -name "*.meta" -exec yq --inplace .guid=1 {} \;
2 202 - blocks gawk's long spelling of the in-place include
find Assets -name "*.meta" -exec gawk --include=inplace "{print}" {} \;
2 222 - blocks the second clause when the first one is read-only
find Assets -name "*.meta" -exec grep -l guid {} \; -exec gzip -9 {} \;
2 222 - blocks the first clause when the second one is read-only
find Assets -name "*.meta" -exec gzip -1 {} \; -exec grep -l guid {} \;
2 222 - does not let a git status ahead of the find vouch for the git rm inside it
git status && find Assets -name "*.meta" -exec git rm {} \;
2 222 - the gate must still classify this, and its message is asserted above
find Assets -name "*.meta" -exec \mv {} /tmp/bak \;
2 222 - the gate must still classify this, and its message is asserted above
find Assets -name "*.meta" -exec pandoc {} \;
2 222 - the gate must still classify this, and its message is asserted above
find Assets -name "*.meta" -exec pandoc -t plain {} \;
2 222 - the gate must still classify this, and its message is asserted above
find Assets -name "*.meta" -exec pandoc -t html {} \;
2 222 - the gate must still classify this, and its message is asserted above
find Assets/Art -name "*.meta" -delete
2 222 - the gate must still classify this, and its message is asserted above
find Assets/Art -name "*.meta" -newer x -delete
2 220 - an operator inside a quoted awk program is not a clause end — verified: truncated 3 of 3 real .meta files 119 B to 39 B
find Assets -name '*.meta' -exec awk '/guid/ && /:/ {print > FILENAME}' {} \;
2 220 - the same shape calling system(rm) — verified: deleted all 3 real .meta files
find Assets -name '*.meta' -exec awk '/guid/ && /:/ {system("rm " FILENAME)}' {} \;
2 220 - a quoted semicolon inside an awk program is not find's terminator
find Assets -name '*.meta' -exec awk '{ x=1 ; print > FILENAME }' {} \;
2 220 - a quoted double-pipe inside an awk program is not a shell operator
find Assets -name '*.meta' -exec awk '/a/ || /b/ {print > FILENAME}' {} \;
2 220 - a quoted single-ampersand-pair inside an awk program, with a subscript
find Assets -name '*.meta' -exec awk '!seen[$0]++ && /guid/ {print > FILENAME}' {} \;
2 220 - the same, reached past gawk's -v assignment
find Assets -name '*.meta' -exec gawk -v x=1 'x && /guid/ {print > FILENAME}' {} \;
2 220 - a quoted single pipe inside a sed expression must not hide the -i that follows
find Assets -name '*.meta' -exec sed -E 's/(a | b)/x/' -i {} \;
2 220 - the same sed shape, verified: rewrote the guid line of 3 of 3 real .meta files
find Assets -name '*.meta' -exec sed -E 's/guid: | zzz/X/' -i {} \;
0 220 X find stops at the first bare-value ; argument: measured rc=1, "unknown predicate -i", 0 of 3 real files written
find Assets -name '*.meta' -exec sed -e ';' -i {} \;
2 020 - find's '+' terminator needs a preceding {} — verified: sort really receives -o {} here
find Assets -name '*.meta' -exec sort -u '+' -o {} {} \;
2 220 - the same quoted-operator hole reached through xargs rather than -exec
find Assets -name '*.meta' -print0 | xargs -0 awk '/guid/ && /:/ {print > FILENAME}'
2 220 - the same quoted-operator hole reached through -execdir
find Assets -name '*.meta' -execdir awk '/guid/ && /:/ {print > FILENAME}' {} \;
2 200 - an interior quote inside the flag itself — sed -'i'
find Assets -name '*.meta' -exec sed -'i' s/guid/x/ {} \;
2 200 - an interior quote around the dash — sed "-"i
find Assets -name '*.meta' -exec sed "-"i s/guid/x/ {} \;
2 200 - an interior quote inside the long spelling — sed --in-'place'
find Assets -name '*.meta' -exec sed --in-'place' s/guid/x/ {} \;
2 200 - an interior quote in gawk's in-place flag
find Assets -name '*.meta' -exec gawk -'i' inplace '{print}' {} \;
2 000 - an interior quote in sort's output flag
find Assets -name '*.meta' -exec sort -'o' {} {} \;
0 002 X r5 dequoted per token, so a word inside a quoted pattern was read as an introducer
find Assets -name '*.meta' -exec grep -l 'xargs gzip' {} \;
0 002 X r5 dequoted per token, so a word inside a quoted pattern was read as an introducer
find Assets -name '*.meta' -exec grep -l 'xargs' gzip {} \;
2 222 - in-place flag before a separate -e expression, plus-terminated
find Assets -name '*.meta' -exec sed -i -e s/guid/x/ {} +
2 222 - the flag is the last token before the terminator
find Assets -name '*.meta' -exec sed -e s/guid/x/ {} -i \;
2 222 - the long spelling with an attached backup suffix
find Assets -name '*.meta' -exec sed --in-place=.bak s/guid/x/ {} \;
2 222 - perl -i is an in-place rewrite and perl is not read-only anyway
find Assets -name '*.meta' -exec perl -i.bak -pe s/guid/x/ {} \;
2 222 - ed edits in place and is on no list
find Assets -name '*.meta' -exec ed -s {} \;
2 222 - the -execdir route to sed -i
find Assets -name '*.meta' -execdir sed -i s/guid/x/ {} \;
2 222 - the -ok route to sed -i
find Assets -name '*.meta' -ok sed -i s/guid/x/ {} \;
2 222 - the -okdir route to sed -i
find Assets -name '*.meta' -okdir sed -i s/guid/x/ {} \;
2 222 - the xargs route to sed -i
find Assets -name '*.meta' -print0 | xargs -0 sed -i s/guid/x/
2 202 - the xargs route to the quoted-away cross-platform spelling
find Assets -name '*.meta' -print0 | xargs -0 sed -i'' s/guid/x/
2 202 - the xargs route to gawk's in-place extension
find Assets -name '*.meta' -print0 | xargs -0 gawk -i inplace '{print}'
2 022 - the xargs route to sort's output flag
find Assets -name '*.meta' -print0 | xargs -0 sort -o out.txt
2 202 - gawk -i inplace, plus-terminated
find Assets -name '*.meta' -exec gawk -i inplace "{print}" {} +
2 022 - sort's output flag after the placeholder
find Assets -name '*.meta' -exec sort {} -o {} \;
2 202 - yq's in-place flag with a double-quoted suffix
find Assets -name '*.meta' -exec yq -i".bak" .guid=1 {} \;
2 222 - sed's in-place flag bundled with -n
find Assets -name '*.meta' -exec sed -ni s/guid/x/ {} \;
2 222 - sed's in-place flag as a separate token after -n
find Assets -name '*.meta' -exec sed -n -i s/guid/x/ {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec awk '/guid/{print FILENAME}' {} \;
0 000 - FP: sort -c only checks order — r3 had no second stage and blocked every sort
find Assets -name '*.meta' -exec sort -c {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec git log --oneline -- {} \;
0 000 - a quoted command name still resolves to the command
find Assets -name '*.meta' -exec 'grep' -l guid {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec git blame -- {} \;
0 220 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets -name '*.meta' -exec git --no-pager show HEAD -- {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec sed -n "1,5p" {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec sed --quiet -e '/guid/p' {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec yq ".guid" {} \;
0 000 - FP: sort -u writes nothing — r3 blocked every sort
find Assets -name '*.meta' -exec sort -u {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec openssl dgst -md5 -hex {} \;
0 000 - a shell-operator character inside a quoted grep pattern is data
find Assets -name '*.meta' -exec grep -l 'a|b' {} \;
0 000 - a quoted semicolon inside a grep pattern is data
find Assets -name '*.meta' -exec grep -l ';' {} \;
0 000 - a quoted double-ampersand inside a grep pattern is data
find Assets -name '*.meta' -exec grep -l '&&' {} \;
0 000 - a quoted in-place flag inside a grep pattern is data
find Assets -name '*.meta' -exec grep -l '-i' {} \;
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec sed -n '/&&/p' {} \;
2 220 - a quoted double-ampersand must not end sed's clause and hide the -i after it
find Assets -name '*.meta' -exec sed -n '&&' -i {} \;
2 222 - two clauses, plus-terminated first, destructive second
find Assets -name '*.meta' -exec grep -l guid {} + -exec gzip {} \;
2 222 - a parenthesised find expression with a destructive exec
find Assets \( -name '*.meta' \) -exec gzip {} \;
2 222 - a destructive exec with a trailing shell redirect
find Assets -name '*.meta' -exec gzip {} \; > /tmp/o.txt
2 222 - two chained xargs stages, the second one destructive
find Assets -name '*.meta' | xargs grep -l guid | xargs sed -i s/a/b/
2 022 - an escaped prefix in front of an escaped verb
find Assets -name '*.meta' -exec \env \rm {} \;
0 222 X the shell reads ./\grep as ./grep, and ./grep with no backslash is permitted at r3, r4 and r5 too - measured
find Assets -name '*.meta' -exec ./\grep -l guid {} \;
0 200 X KNOWN HOLE, inherited: an awk program in a -f file can write and no arm models it
find Assets -name '*.meta' -exec awk -f script.awk {} \;
0 200 X KNOWN HOLE, inherited: an awk write through a pipe to an external command is not modelled
find Assets -name '*.meta' -exec awk '{print | "tee " FILENAME}' {} \;
0 200 X KNOWN HOLE, inherited: GNU long-option abbreviation; a wider glob would false-positive on yq --input-format
find Assets -name '*.meta' -exec sed --in-pl s/guid/x/ {} \;
2 222 - KNOWN FALSE POSITIVE: cp is decided by argument position, which this gate does not parse
find Assets -name '*.meta' -exec cp {} /tmp/backup/ \;
2 222 - KNOWN FALSE POSITIVE: rsync, same reason as cp
find Assets -name '*.meta' -exec rsync {} /tmp/backup/ \;
2 000 - NEW FALSE POSITIVE: command substitution makes the token stream unparseable, so it blocks
find "$(pwd)/Assets" -name '*.meta' -exec grep -l guid {} \;
0 000 - command substitution inside single quotes is inert and must not trip the unparseable arm
find Assets -name '*.meta' -exec grep -l '$(rm -rf /)' {} \;
2 222 - a command hidden behind command substitution blocks as unparseable
find Assets -name '*.meta' -exec $(echo sed) -i {} \;
2 222 - a command hidden behind backticks blocks as unparseable
find Assets -name '*.meta' -exec `echo sed` -i {} \;
2 200 - ANSI-C quoting is not decoded, so it blocks as unparseable
find Assets -name '*.meta' -exec sed $'-i' s/guid/x/ {} \;
2 200 - an unterminated quote blocks rather than being parsed on a guess
find Assets -name '*.meta' -exec sed -e 's/guid/x/ {} \;
2 220 - a quoted semicolon on the xargs route is an argument, not a clause end
find Assets -name '*.meta' -print0 | xargs -0 sed -e ';' -i
0 222 X the ledgered round-4 residual: a shell redirect on an xargs pipeline is not awk s own argument
find Assets -name '*.meta' -print0 | xargs -0 awk '{print}' 2>/dev/null
2 222 - a redirect must be skipped, not treated as a clause end that hides the -i after it
find Assets -name '*.meta' -print0 | xargs -0 sed 2>/dev/null -i s/a/b/
0 200 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec sed -n 1p {} \; 2>/dev/null
2 222 - a stderr redirect after the terminator does not excuse the in-place flag before it
find Assets -name '*.meta' -exec sed -i s/guid/x/ {} \; 2>/dev/null
0 222 X the tokeniser keeps a quoted argument whole, so git's -c value is one token and the subcommand is still reached; every earlier version split it on the space and read B as the subcommand
find Assets -name '*.meta' -exec git -c 'user.name=A B' log --oneline {} \;
0 202 X a literal in-place flag inside a quoted sed expression is data; the arms re-split on the tokeniser's TAB, so it stays one argument instead of becoming a flag
find Assets -name '*.meta' -exec sed -n -e 's/a/b -i/p' {} \;
2 222 - a bare redirect and its operand belong to the shell, so skipping them must not end the clause and hide the flag after it
find Assets -name '*.meta' -print0 | xargs -0 sed > /tmp/o.txt -i s/a/b/
0 222 X a bare redirect and its operand are the shell's, not awk's; every earlier version read the > as awk's own write form
find Assets -name '*.meta' -print0 | xargs -0 awk '{print}' > /tmp/o.txt
0 222 X the appending spelling of the same shell redirect, same reason
find Assets -name '*.meta' -print0 | xargs -0 awk '{print}' >> /tmp/o.txt
TBG_CORPUS
}

# --- the corpus runs, one assertion per payload ---------------------------------------------
# One assertion per payload on purpose rather than one aggregate: a mutation that reddens an
# aggregate has isolated nothing, and the whole point of this block is being able to say WHICH
# payloads a change moved.
tbg_ran=0
tbg_blocks=0
tbg_permits=0
tbg_protected=0
tbg_unexplained=""
tbg_reasonless=""
while read -r tbg_exp tbg_hist tbg_ex tbg_note; do
    IFS= read -r tbg_payload || break
    case "$tbg_exp" in ''|'#'*) continue ;; esac
    tbg_ran=$((tbg_ran + 1))
    if [ "$tbg_exp" = "2" ]; then tbg_blocks=$((tbg_blocks + 1)); else tbg_permits=$((tbg_permits + 1)); fi

    # The monotonic property, checked as data rather than as a second probe: a payload any
    # earlier version blocked may not be permitted here without an `X` and a written reason.
    case "$tbg_hist" in
        *2*)
            if [ "$tbg_exp" = "2" ]; then
                tbg_protected=$((tbg_protected + 1))
            elif [ "$tbg_ex" != "X" ]; then
                tbg_unexplained="${tbg_unexplained}${tbg_payload}
"
            elif [ -z "$tbg_note" ]; then
                tbg_reasonless="${tbg_reasonless}${tbg_payload}
"
            fi
            ;;
    esac

    assert_eq "$tbg_exp" "$(tbg_run_fresh "$tbg_payload")" "corpus [hist $tbg_hist]: $tbg_note"
done <<< "$(tbg_corpus)"

# --- the corpus's own integrity, so it cannot pass by being empty ---------------------------
# This repository's worst guard shape is one that is green because it scanned nothing. Emptying
# the payload list above must FAIL here, not report a green zero — and so must deleting only
# the blocking half, or only the permitting half, or every historically-blocked payload.
assert_eq "yes" "$([ "$tbg_ran" -gt 0 ] && echo yes || echo "no: the corpus ran $tbg_ran payloads")" \
    "the corpus is not empty"
assert_eq "yes" "$([ "$tbg_blocks" -gt 0 ] && echo yes || echo "no: $tbg_blocks payloads expect a block")" \
    "the corpus still contains payloads that must be blocked"
assert_eq "yes" "$([ "$tbg_permits" -gt 0 ] && echo yes || echo "no: $tbg_permits payloads expect a pass")" \
    "the corpus still contains payloads that must be permitted"
assert_eq "yes" "$([ "$tbg_protected" -gt 0 ] && echo yes || echo "no: $tbg_protected payloads are monotonically protected")" \
    "the corpus still contains payloads an earlier hook version blocked and this one must too"
assert_eq "" "$tbg_unexplained" \
    "no payload an earlier version blocked is permitted here without a recorded exemption"
assert_eq "" "$tbg_reasonless" \
    "every recorded exemption carries a reason"

# --- the quote model's own direct evidence --------------------------------------------------
# The corpus checks verdicts. These two check the tokeniser's output shape, which is where the
# defect actually lived: a quoted run must arrive as ONE argument, not as five.
assert_contains "$(tbg_stderr "find Assets -name '*.meta' -exec pandoc '/a/ && /b/ {print > X}' {} \\;")" \
    "is not on this gate's read-only list" \
    "a quoted program does not end the clause it sits in"
# The unparseable marker is emitted after the tokens, so it is the verdict only when every
# command ahead of it was read-only — which is exactly the case where the gate would otherwise
# have to guess at a clause boundary. When a non-read-only command is present too, that
# command's name wins the message, and both still block.
assert_contains "$(tbg_stderr 'find "$(pwd)/Assets" -name "*.meta" -exec grep -c guid {} \;')" \
    "could not parse this command's quoting" \
    "says it could not parse rather than guessing at a clause boundary"
assert_contains "$(tbg_stderr 'find "$(pwd)/Assets" -name "*.meta" -exec grep -n guid {} \;')" \
    "substitution-or-ansi-c-quoting" \
    "names which construct it could not parse"

# --- a command spanning lines, which the corpus block cannot carry --------------------------
# A backslash-continued line is the ordinary way a long find gets formatted, so the tokeniser
# splices it rather than declaring it unparseable. Both directions, because splicing wrongly
# would either block every multi-line read or hide a write flag on the next line.
assert_eq "0" "$(tbg_run_fresh 'find Assets -name "*.meta" \
    -exec grep -l guid {} \;')" \
    "does not block a read-only find split across lines with a backslash"
assert_eq "2" "$(tbg_run_fresh 'find Assets -name "*.meta" \
    -exec sed -i s/guid/x/ {} \;')" \
    "still blocks a write whose flag is on the continued line"
assert_eq "2" "$(tbg_run_fresh 'find Assets -name "*.meta" -exec awk "{ print > FILENAME
}" {} \;')" \
    "still blocks a quoted program whose newline is inside the quotes"

# ============================================================================================
# THE COST, WITH A BOUND THAT IS ASSERTED RATHER THAN HOPED FOR.
#
# This hook runs on EVERY Bash tool call, so its worst case is a user-visible hang. Round 4 and
# round 5 both shipped one, and neither had a cost assertion. Measured on this host (bash 5.2,
# en_US.UTF-8, gawk 5.2.1) with a 1 048 576-character quote-leading token on the .meta find
# route, one run each:
#
#     r3 546870f   1 144 ms
#     r4 06883cc  44 632 ms
#     r5 3fd22dc 123 504 ms      <- a PreToolUse hook this slow reads as a frozen session
#     here        1 976 ms
#
# The bound below is 10 000 ms: five times the measurement, and more than four times BELOW the
# cheaper of the two versions it exists to catch. It is deliberately loose, because this
# repository already documents its suite going flaky under CPU contention and a tight
# wall-clock guard is the kind that gets deleted the first time CI is busy. A loose guard that
# survives is worth more than a tight one that does not.
# ============================================================================================
tbg_big="$(LC_ALL=C printf '%*s' 1048576 '' | LC_ALL=C tr ' ' 'a')"
tbg_t0=$(( $(date +%s%N) / 1000000 ))
tbg_bigrc="$(tbg_run_fresh "find Assets -name '*.meta' -exec grep -l '$tbg_big' {} \\;")"
tbg_t1=$(( $(date +%s%N) / 1000000 ))
tbg_elapsed=$(( tbg_t1 - tbg_t0 ))
assert_eq "0" "$tbg_bigrc" \
    "a megabyte-long quoted grep pattern is still a read"
assert_eq "under" "$([ "$tbg_elapsed" -lt 10000 ] && echo under || echo "over: ${tbg_elapsed} ms")" \
    "a 1 MB quote-leading command line costs under 10 000 ms end to end"
unset tbg_big
