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
# exit codes the same payload got from the hook at 546870f (r3), 06883cc (r4), 3fd22dc (r5) and
# c050743 (task 2b), in that order. A payload an earlier version BLOCKED and this one PERMITS is
# a regression by definition, and it may only be recorded as `X` with a written reason. That is
# the mechanism that makes the r3 -> r4 -> r5 pattern impossible to repeat by accident.
#
# THE COLUMN GAINED ITS FOURTH DIGIT IN TASK 2C, and adding a version is how it keeps working: a
# frozen column that stops being extended stops being history. The three records whose fourth
# digit is the FIRST block anywhere in their history are the three task 2b closed that nothing
# before it had ever blocked — `-exec sort -'o' {} {}`, a command substitution in the find's own
# path, and a backtick inside an otherwise read-only clause. Without that digit those three
# would look, to every later round, like payloads no version ever objected to, which is exactly
# the evidence a later round needs in order not to reopen them.
#
# WHAT THIS CANNOT SEE, stated plainly because a check's silence is only as wide as what it
# read: it freezes the PAST. It catches re-opening an old hole and says exactly nothing about a
# new one. Nothing here would have caught the round-5 Critical before it was written, because no
# earlier version had ever been sent a quoted awk program either.
#
# AND IT ONLY CATCHES THE MUTANTS ITS AUTHOR IMAGINED — which is why the payload list was not
# written by imagining them. Every deliberate branch in `find_exec_tokens`,
# `find_exec_commands` and `find_exec_is_read_only` was mutated one at a time, 50 in all, and
# the corpus was run against each. Fifteen branches turned out to be branches nothing here
# measured; the sharpest was `*/xargs`, which the hook handles deliberately in two places and
# whose deletion left this file entirely green while
# `find … -print0 | /usr/bin/xargs -0 sed -i s/a/b/` went from blocked to permitted and
# destroyed three real .meta files. Payloads for those fifteen are in the list below and each
# names the branch it exists for.
#
# Two of the fifty have NO payload, and that is a finding rather than an omission: the
# double-quote backslash escape (`\"` inside `"…"`) and the newline-to-space substitution inside
# a quoted run change the token's VALUE, and no arm's decision depends on the difference.
#
# BUT THE REASON FIRST WRITTEN HERE WAS WRONG, AND THE CORRECTION MATTERS MORE THAN THE
# CONCLUSION. It said "removing either only ever lengthens a token, which can add a block and
# never remove one". That is true of the gentle mutation (leave a stray backslash in the value)
# and FALSE of the one that matters: delete the whole backslash branch inside `"…"` and the `"`
# in `\"` is no longer consumed, so it CLOSES the quoted run. Quote parity flips for the rest of
# the line. On `-exec sed "pat\" ; " -i {} \;` that really does end the clause before `-i` is
# collected — the verdict is still a block, but because the parse now ends `unterminated-quote`,
# not because the token got longer. Conclusion unchanged, mechanism different, and a reason that
# is wrong about the mechanism is a reason that will be trusted somewhere it does not hold.
#
# AND "46 OF 49 BRANCHES ARE MEASURED" IS REALLY "46 OF 49 CHOSEN MUTATIONS ARE MEASURED". A
# branch can red under one mutation and not another: making `prevbrace` never set — so find's
# `+` can never terminate a clause — runs this file 442/0, and no hole could be constructed for
# it, because every path it changes is conservative. The sweep measures the mutations someone
# wrote, which is a weaker claim than the one the numbers look like.
#
# To repeat the sweep: mutate one branch, run this corpus, and record how many assertions go
# red. A branch with zero is a branch this file does not measure — and mutate it more than one
# way, because a single-site mutation of a branch that appears twice is a no-op. That happened
# twice in this file's own tooling: once on the route-tracking branch, and once on the clause's
# argument reset, where removing EITHER `args=()` alone is masked by the other.
#
# HOW TO REGENERATE THE `hist` COLUMN (it is data, not derivation — the permanent test runs
# inside a `git archive` scratch copy and cannot shell out to git):
#
#   for rev in 546870f 06883cc 3fd22dc c050743; do
#       git show "$rev:.claude/hooks/bash-gate.sh" > "/tmp/gate-$rev.sh"
#   done
#   # `_lib.sh` differs across those revisions in its COMMENTS ONLY — strip comments and blank
#   # lines from any two copies and they are identical — so one copy beside each gate is enough.
#   # Then, for each payload below, send it to each of the four with a FRESH
#   # UNITY_HOOK_STATE_DIR (see tbg_run_fresh) and record the four exit codes in that order.
#   # Adding a version APPENDS a digit; it never rewrites one. If a regeneration changes an
#   # existing digit, the payload or the extraction moved, not history.
#
# RECORD FORMAT — two lines each, so a payload never has to be escaped or quoted:
#   line 1:  <expected-rc> <hist> <exempt> <one-line reason>
#   line 2:  the payload, verbatim, leading whitespace significant
# `exempt` is one of THREE values, and the distinction is the guard, not decoration:
#   `-`  nothing to explain — this version agrees with every earlier one, or blocks where they did
#   `X`  a VERIFIED FALSE POSITIVE: an earlier version blocked it and it cannot write. Each one
#        was executed against real .meta files by the round-1 reviewer; 42 of 42 left byte length
#        and cksum identical.
#   `H`  a KNOWN LIVE HOLE: an earlier version blocked it, it really can write, and this version
#        permits it anyway. These are inherited, they are recorded rather than hidden, and THEIR
#        NUMBER IS ASSERTED BELOW so one cannot be added by typing a note.
#
# The brief's property is "except payloads recorded as VERIFIED FALSE POSITIVES". A single flag
# plus any non-empty string does not express that: it accepts "this is a known live hole" as a
# monotonic waiver, which would let a future round downgrade a real block to a permit and stay
# green — the exact mechanism this column exists to prevent. Two of the three `H` records below
# were executed and do destroy files (`awk -f`: 127 B -> 40 B on all three; `sed --in-pl`: all
# three rewritten), which is why they may not sit under the same marker as the other 42.
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
2 2222 - still blocks a real redirect into ProjectSettings
echo hi > ProjectSettings/ProjectSettings.asset
2 2222 - still blocks a real .meta deletion
rm -f Assets/Player.cs.meta
0 0000 - does not block a grep that merely names ProjectSettings
grep -n ProjectSettings/ProjectSettings.asset notes.txt
0 0000 - does not block an echo that merely mentions the path
echo "see ProjectSettings/ProjectSettings.asset for details"
0 0000 - does not block reading history of a .meta file
git log -- Assets/Player.cs.meta
0 0000 - does not block a JSON argument that merely contains the word cp and the path as data
curl -s https://api.example.com/report -d "{\"reason\": \"cp shows drift\", \"target\":\"ProjectSettings/ProjectSettings.asset\"}"
0 0000 - does not block an unrelated grep chained after a redirect to a different file
echo build > build.log; grep ProjectSettings/ProjectSettings.asset build.log
2 2222 - still blocks rm -rf Library/ with leading whitespace
  rm -rf Library/
2 2222 - still blocks rm -rf Library/ behind a sudo prefix
sudo rm -rf Library/
2 2222 - still blocks rm -rf Library/ inside a subshell
(rm -rf Library/)
2 2222 - still blocks a .meta deletion reached through xargs
echo x | xargs -I{} rm -f Assets/Player.cs.meta
0 0000 - does not block an echo warning against the hard reset
echo "never run git reset --hard here"
2 2222 - still blocks the hard reset itself
git reset --hard HEAD~1
2 2222 - still blocks the hard reset after a control operator
cd Assets && git reset --hard
2 2222 - still blocks the hard reset behind a git -C option
git -C /repo reset --hard
2 2222 - still blocks git clean behind a --git-dir option
git --git-dir=/r/.git clean -fdx
2 2222 - still blocks the hard reset behind stacked git global options
git --no-pager -c core.pager=cat reset --hard
0 0000 - does not block a commit message that quotes the hard reset
git commit -m "docs: warn about git reset --hard"
0 0000 - does not block a commit message that quotes git clean
git commit -m "chore: describe git clean -fdx in the runbook"
2 2222 - still blocks git clean itself
git clean -fdx
0 0000 - does not block an echo warning against a force push
echo "never git push --force to main"
2 2222 - still blocks a force push to a protected branch
git push --force origin main
2 2222 - still blocks a short-flag force push
git push -f origin spike/x
0 0000 - does not block a grep for the prefs-wipe API
grep -rn PlayerPrefs.DeleteAll Assets/
0 0000 - does not block a commit message naming the prefs-wipe API
git commit -m "fix: stop calling PlayerPrefs.DeleteAll on load"
2 2222 - still blocks the macOS defaults delete of a unity domain
defaults delete unity.Acme.Game
2 2222 - still blocks deleting the Linux unity3d prefs directory
rm -rf ~/.config/unity3d/Acme/Game
0 0000 - does not block a grep for destructive SQL
grep -rn "DROP TABLE" migrations/
2 2222 - still blocks destructive SQL passed to a client
psql -c "DROP TABLE users"
2 2222 - still blocks destructive SQL passed to sqlite3
sqlite3 save.db "drop database main"
0 0000 - does not block a find that counts .meta files
find Assets -name "*.meta" | wc -l
0 0000 - does not block a find that lists .meta files
find Assets -name "*.meta" -newer Assets/Player.cs -print
2 2222 - still blocks find -delete on .meta files
find Assets -name "*.meta" -delete
2 2222 - still blocks find -exec rm on .meta files
find Assets -name "*.meta" -exec rm {} \;
2 2222 - still blocks find piped into xargs rm on .meta files
find Assets -name "*.meta" -print0 | xargs -0 rm
2 2222 - still blocks the find route to a mass .meta rename
find Assets -name "*.meta" -exec mv {} /tmp \;
2 2222 - still blocks find -exec with a path-prefixed rm
find Assets -name "*.meta" -exec /bin/rm {} \;
2 2222 - still blocks find -exec git rm
find Assets -name "*.meta" -exec git rm {} \;
2 2222 - still blocks find -exec through a shell wrapper
find Assets -name "*.meta" -exec sh -c "rm \$1" _ {} \;
0 0000 - does not block find -exec with a read-only command
find Assets -name "*.meta" -exec stat {} \;
2 2222 - still blocks find -exec rm
find Assets -name '*.meta' -exec rm {} \;
2 2222 - still blocks find -exec unlink
find Assets -name '*.meta' -exec unlink {} \;
2 2222 - still blocks find -exec shred
find Assets -name '*.meta' -exec shred {} \;
2 2222 - still blocks find -exec truncate
find Assets -name '*.meta' -exec truncate {} \;
2 2222 - still blocks find -exec mv
find Assets -name '*.meta' -exec mv {} \;
2 2222 - still blocks find -exec rename
find Assets -name '*.meta' -exec rename {} \;
2 2222 - still blocks find -exec prename
find Assets -name '*.meta' -exec prename {} \;
2 2222 - still blocks find -exec mmv
find Assets -name '*.meta' -exec mmv {} \;
2 2222 - blocks find -exec perl-rename — the alias that proved a denylist cannot be finished
find Assets -name "*.meta" -exec perl-rename s/meta/bak/ {} \;
2 2222 - blocks find -exec file-rename, the same tool under its third name
find Assets -name "*.meta" -exec file-rename s/meta/bak/ {} \;
2 2222 - blocks find -exec gzip, which no denylist this task wrote contained
find Assets -name "*.meta" -exec gzip {} \;
2 2222 - blocks find -exec dd
find Assets -name "*.meta" -exec dd if=/dev/null of={} \;
2 2222 - blocks find -exec sed, which rewrites in place and is deliberately not allowlisted
find Assets -name "*.meta" -exec sed -i s/guid/x/ {} \;
2 2222 - blocks find -exec python3 — an interpreter is not a read-only command
find Assets -name "*.meta" -exec python3 wipe.py {} \;
2 2222 - blocks the -execdir route
find Assets -name "*.meta" -execdir gzip {} \;
2 2222 - blocks the -ok route
find Assets -name "*.meta" -ok gzip {} \;
2 2222 - blocks the -exec {} + route
find Assets -name "*.meta" -exec gzip {} +
2 2222 - blocks the xargs -0 route
find Assets -name "*.meta" -print0 | xargs -0 gzip
2 2222 - blocks the xargs -I route, whose placeholder must not be read as the command
find Assets -name "*.meta" | xargs -I{} gzip {}
2 2222 - blocks a path-prefixed command
find Assets -name "*.meta" -exec /usr/bin/gzip {} \;
2 2222 - blocks a command behind an env prefix
find Assets -name "*.meta" -exec env gzip {} \;
2 2222 - blocks a command behind a shell wrapper, because sh is not read-only
find Assets -name "*.meta" -exec sh -c "gzip \$1" _ {} \;
0 0000 - does not block find -exec grep, which reads the GUIDs it names
find Assets -name "*.meta" -exec grep -l guid {} \;
0 0000 - does not block a path-prefixed read-only command
find Assets -name "*.meta" -exec /usr/bin/grep -l guid {} \;
0 0000 - does not block find -exec md5sum
find Assets -name "*.meta" -exec md5sum {} \;
0 0000 - does not block find -exec basename
find Assets -name "*.meta" -exec basename {} \;
0 0000 - does not block a read-only command reached through xargs
find Assets -name "*.meta" -print0 | xargs -0 grep -l guid
0 0000 - does not block a grep whose PATTERN is a destructive verb
find Assets -name "*.meta" -exec grep -l rm {} \;
0 0000 - does not block a grep searching for the other one
find Assets -name "*.meta" -exec grep -l mv {} \;
2 2222 - blocks a direct unlink — the verb the classification is named after
unlink Assets/Player.cs.meta
2 2222 - blocks a direct shred
shred -u Assets/Player.cs.meta
2 2222 - blocks a direct truncate
truncate -s 0 Assets/Player.cs.meta
2 2222 - blocks a direct perl-rename
perl-rename s/meta/bak/ Assets/Player.cs.meta
2 2222 - blocks a direct mmv
mmv "Assets/*.cs.meta" "Assets/#1.bak"
0 0000 - does not block reading a .meta file
cat Assets/Player.cs.meta
2 2222 - still blocks a direct .meta rename
mv Assets/Player.cs.meta Assets/Enemy.cs.meta
0 0000 - does not block reading the history of a renamed .meta file
git log --follow -- Assets/Player.cs.meta
2 2222 - still blocks a redirect over Packages/manifest.json
echo {} > Packages/manifest.json
2 2222 - still blocks deleting Packages/manifest.json
rm -f Packages/manifest.json
0 0000 - does not block reading Packages/manifest.json
jq .dependencies Packages/manifest.json
2 2222 - still blocks a Library/Temp wipe
rm -rf Library/ Temp/
0 0000 - does not block prose about wiping Library/
echo "delete Library/ only when the editor is closed"
0 0000 - does not block measuring the directories a wipe would remove
du -sh Library/ Temp/ Logs/
2 2222 - still blocks copying over a ProjectSettings asset
cp /tmp/staged.asset ProjectSettings/ProjectSettings.asset
2 2222 - still blocks deleting a ProjectSettings asset
rm -f ProjectSettings/QualitySettings.asset
2 0222 - blocks find -exec on a backslash-escaped rm
find Assets -name "*.meta" -exec \rm {} \;
2 0222 - blocks xargs on a backslash-escaped rm
find Assets -name "*.meta" -print0 | xargs -0 \rm
2 0222 - blocks a backslash-escaped verb that was never on any denylist
find Assets -name "*.meta" -exec \gzip {} \;
2 0222 - blocks a backslash-escaped perl-rename
find Assets -name "*.meta" -exec \perl-rename s/meta/bak/ {} \;
2 0222 - blocks a backslash-escaped xargs — the INTRODUCER hides behind one too
find Assets -name "*.meta" | \xargs -0 rm
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec \grep -l guid {} \;
0 0000 - does not block a backslash-escaped xargs running a read-only command
find Assets -name "*.meta" -print0 | \xargs -0 \grep -l guid
2 2222 - blocks a find whose terminator is quoted rather than escaped
find Assets -name '*.meta' -exec rm {} ';'
0 0000 - does not block the read-only twin of the quoted-terminator form
find Assets -name '*.meta' -exec grep -c guid {} ';'
2 0222 - blocks a backslash-escaped direct .meta deletion
\rm Assets/Enemy.cs.meta
2 0222 - blocks a backslash-escaped Library wipe
\rm -rf Library/
2 0222 - blocks a backslash-escaped direct .meta rename
\mv Assets/A.cs.meta Assets/B.cs.meta
2 0222 - blocks a backslash-escaped hard reset
\git reset --hard HEAD~2
2 0222 - blocks a backslash-escaped find -delete
\find Assets -name "*.meta" -delete
0 0000 - does not block prose that quotes the alias-bypass spelling
echo "use \rm to bypass the alias, but not in this repo"
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -print0 | xargs -0 -n 1 grep -l guid
2 2222 - still blocks the destructive twin of that same xargs form
find Assets -name "*.meta" -print0 | xargs -0 -n 1 gzip
2 2222 - still blocks xargs -i rm, whose next word IS the command
find Assets -name "*.meta" | xargs -i rm {}
2 2222 - still blocks xargs -I with a separate replacement string
find Assets -name "*.meta" | xargs -I {} rm {}
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec du -h {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec b2sum {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec sha512sum {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec identify {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec [ -s {} ] \;
2 0222 - blocks find -exec touch, which rewrites mtime and triggers a reimport
find Assets -name "*.meta" -exec touch {} \;
2 0222 - blocks sort -o, which is the documented in-place rewrite
find Assets -name "*.meta" -exec sort -o {} {} \;
0 0000 - does not block a sort with no output flag
find Assets -name "*.meta" -exec sort {} \;
2 2222 - blocks dos2unix, which converts in place unless told otherwise
find Assets -name "*.meta" -exec dos2unix {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec openssl dgst -sha256 {} \;
2 2222 - blocks openssl when it is given an output file
find Assets -name "*.meta" -exec openssl rand -out {} 32 \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec sed -n /guid/p {} \;
2 2222 - blocks sed -i with a backup suffix attached
find Assets -name "*.meta" -exec sed -i.bak s/guid/x/ {} \;
2 2222 - blocks the long spelling of sed's in-place flag
find Assets -name "*.meta" -exec sed --in-place s/guid/x/ {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -iname "*.meta" -exec sed -n 1p {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec git log --oneline {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec git blame -L 1,2 {} \;
2 2222 - still blocks git mv, which is not on the read-only subcommand list
find Assets -name "*.meta" -exec git mv {} /tmp/bak \;
2 2222 - does not let an unrelated git log later on the line vouch for git rm
find Assets -name "*.meta" -exec git rm --cached {} \; && git log --oneline
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec awk /guid/ {} \;
2 2222 - blocks an awk program containing a redirect
find Assets -name "*.meta" -exec awk "{print > \"o.txt\"}" {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -exec yq .guid {} \;
2 2222 - blocks yq -i, which writes the file back
find Assets -name "*.meta" -exec yq -i .guid=1 {} \;
2 2022 - blocks sed -i'' — the cross-platform spelling, quoted away to nothing
find Assets -name '*.meta' -exec sed -i'' -e s/guid/x/ {} \;
2 2022 - blocks sed -i with an empty double-quoted suffix
find Assets -name "*.meta" -exec sed -i"" s/guid/x/ {} \;
2 2022 - blocks sed when the flag itself is quoted
find Assets -name "*.meta" -exec sed "-i" s/guid/x/ {} \;
2 2022 - blocks sed -ibak, whose suffix is attached with no separator at all
find Assets -name "*.meta" -exec sed -ibak s/guid/x/ {} \;
2 2022 - blocks sed -i~, whose suffix is not a word character
find Assets -name "*.meta" -exec sed -i~ s/guid/x/ {} \;
2 2022 - blocks sed -i with a quoted suffix
find Assets -name '*.meta' -exec sed -i'.bak' s/guid/x/ {} \;
2 2022 - blocks the same spelling under the GNU-on-macOS name
find Assets -name '*.meta' -exec gsed -i'' s/guid/x/ {} \;
2 2022 - blocks the same spelling for yq
find Assets -name '*.meta' -exec yq -i'' .guid=1 {} \;
2 2022 - blocks gawk -i inplace, where the flag and its value are a separate pair
find Assets -name "*.meta" -exec gawk -i inplace "{print}" {} \;
2 2022 - blocks awk -i inplace under the unprefixed name
find Assets -name "*.meta" -exec awk -i inplace "{print $0}" {} \;
2 0022 - blocks sort with its output file attached to the flag
find Assets -name "*.meta" -exec sort -o{} {} \;
0 2200 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets -name "*.meta" -exec sed -n /guid/p {} \; | grep -i guid
0 2200 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets -name "*.meta" -print0 | xargs -0 -i sed -n 1p {}
0 2200 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets -name "*.meta" -exec awk "{print}" {} \; > /tmp/o.txt
0 2200 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets -name "*.meta" -exec awk "{print}" {} \; 2>/dev/null
0 0200 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets \( -name "*.meta" -o -name "*.asset" \) -exec sort {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -ipath "*/Art/*.meta" -exec sed -n 1p {} \;
0 0000 - does not read find's -not as an output flag
find Assets -not -name "*.cs" -name "*.meta" -exec sort {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name "*.meta" -print0 -follow -exec sed -n 1p {} \;
0 2200 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets -name "*.meta" -exec git -C /repo log --oneline {} \;
0 2200 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets -name "*.meta" -exec git --git-dir=/r/.git log {} \;
2 2222 - still blocks git rm reached past a global option
find Assets -name "*.meta" -exec git -C /repo rm {} \;
2 2222 - blocks sed -i when the flag comes after the expression
find Assets -name "*.meta" -exec sed -e s/a/b/ -i {} \;
2 0222 - blocks sort -o when another flag comes first
find Assets -name "*.meta" -exec sort -u -o {} {} \;
2 2222 - blocks the long spelling of yq's in-place flag
find Assets -name "*.meta" -exec yq --inplace .guid=1 {} \;
2 2022 - blocks gawk's long spelling of the in-place include
find Assets -name "*.meta" -exec gawk --include=inplace "{print}" {} \;
2 2222 - blocks the second clause when the first one is read-only
find Assets -name "*.meta" -exec grep -l guid {} \; -exec gzip -9 {} \;
2 2222 - blocks the first clause when the second one is read-only
find Assets -name "*.meta" -exec gzip -1 {} \; -exec grep -l guid {} \;
2 2222 - does not let a git status ahead of the find vouch for the git rm inside it
git status && find Assets -name "*.meta" -exec git rm {} \;
2 2222 - the gate must still classify this, and its message is asserted above
find Assets -name "*.meta" -exec \mv {} /tmp/bak \;
2 2222 - the gate must still classify this, and its message is asserted above
find Assets -name "*.meta" -exec pandoc {} \;
2 2222 - the gate must still classify this, and its message is asserted above
find Assets -name "*.meta" -exec pandoc -t plain {} \;
2 2222 - the gate must still classify this, and its message is asserted above
find Assets -name "*.meta" -exec pandoc -t html {} \;
2 2222 - the gate must still classify this, and its message is asserted above
find Assets/Art -name "*.meta" -delete
2 2222 - the gate must still classify this, and its message is asserted above
find Assets/Art -name "*.meta" -newer x -delete
2 2202 - an operator inside a quoted awk program is not a clause end — verified: truncated 3 of 3 real .meta files 119 B to 39 B
find Assets -name '*.meta' -exec awk '/guid/ && /:/ {print > FILENAME}' {} \;
2 2202 - the same shape calling system(rm) — verified: deleted all 3 real .meta files
find Assets -name '*.meta' -exec awk '/guid/ && /:/ {system("rm " FILENAME)}' {} \;
2 2202 - a quoted semicolon inside an awk program is not find's terminator
find Assets -name '*.meta' -exec awk '{ x=1 ; print > FILENAME }' {} \;
2 2202 - a quoted double-pipe inside an awk program is not a shell operator
find Assets -name '*.meta' -exec awk '/a/ || /b/ {print > FILENAME}' {} \;
2 2202 - a quoted single-ampersand-pair inside an awk program, with a subscript
find Assets -name '*.meta' -exec awk '!seen[$0]++ && /guid/ {print > FILENAME}' {} \;
2 2202 - the same, reached past gawk's -v assignment
find Assets -name '*.meta' -exec gawk -v x=1 'x && /guid/ {print > FILENAME}' {} \;
2 2202 - a quoted single pipe inside a sed expression must not hide the -i that follows
find Assets -name '*.meta' -exec sed -E 's/(a | b)/x/' -i {} \;
2 2202 - the same sed shape, verified: rewrote the guid line of 3 of 3 real .meta files
find Assets -name '*.meta' -exec sed -E 's/guid: | zzz/X/' -i {} \;
0 2200 X find stops at the first bare-value ; argument: measured rc=1, "unknown predicate -i", 0 of 3 real files written
find Assets -name '*.meta' -exec sed -e ';' -i {} \;
2 0202 - find's '+' terminator needs a preceding {} — verified: sort really receives -o {} here
find Assets -name '*.meta' -exec sort -u '+' -o {} {} \;
2 2202 - the same quoted-operator hole reached through xargs rather than -exec
find Assets -name '*.meta' -print0 | xargs -0 awk '/guid/ && /:/ {print > FILENAME}'
2 2202 - the same quoted-operator hole reached through -execdir
find Assets -name '*.meta' -execdir awk '/guid/ && /:/ {print > FILENAME}' {} \;
2 2002 - an interior quote inside the flag itself — sed -'i'
find Assets -name '*.meta' -exec sed -'i' s/guid/x/ {} \;
2 2002 - an interior quote around the dash — sed "-"i
find Assets -name '*.meta' -exec sed "-"i s/guid/x/ {} \;
2 2002 - an interior quote inside the long spelling — sed --in-'place'
find Assets -name '*.meta' -exec sed --in-'place' s/guid/x/ {} \;
2 2002 - an interior quote in gawk's in-place flag
find Assets -name '*.meta' -exec gawk -'i' inplace '{print}' {} \;
2 0002 - an interior quote in sort's output flag
find Assets -name '*.meta' -exec sort -'o' {} {} \;
0 0020 X r5 dequoted per token, so a word inside a quoted pattern was read as an introducer
find Assets -name '*.meta' -exec grep -l 'xargs gzip' {} \;
0 0020 X r5 dequoted per token, so a word inside a quoted pattern was read as an introducer
find Assets -name '*.meta' -exec grep -l 'xargs' gzip {} \;
2 2222 - in-place flag before a separate -e expression, plus-terminated
find Assets -name '*.meta' -exec sed -i -e s/guid/x/ {} +
2 2222 - the flag is the last token before the terminator
find Assets -name '*.meta' -exec sed -e s/guid/x/ {} -i \;
2 2222 - the long spelling with an attached backup suffix
find Assets -name '*.meta' -exec sed --in-place=.bak s/guid/x/ {} \;
2 2222 - perl -i is an in-place rewrite and perl is not read-only anyway
find Assets -name '*.meta' -exec perl -i.bak -pe s/guid/x/ {} \;
2 2222 - ed edits in place and is on no list
find Assets -name '*.meta' -exec ed -s {} \;
2 2222 - the -execdir route to sed -i
find Assets -name '*.meta' -execdir sed -i s/guid/x/ {} \;
2 2222 - the -ok route to sed -i
find Assets -name '*.meta' -ok sed -i s/guid/x/ {} \;
2 2222 - the -okdir route to sed -i
find Assets -name '*.meta' -okdir sed -i s/guid/x/ {} \;
2 2222 - the xargs route to sed -i
find Assets -name '*.meta' -print0 | xargs -0 sed -i s/guid/x/
2 2022 - the xargs route to the quoted-away cross-platform spelling
find Assets -name '*.meta' -print0 | xargs -0 sed -i'' s/guid/x/
2 2022 - the xargs route to gawk's in-place extension
find Assets -name '*.meta' -print0 | xargs -0 gawk -i inplace '{print}'
2 0222 - the xargs route to sort's output flag
find Assets -name '*.meta' -print0 | xargs -0 sort -o out.txt
2 2022 - gawk -i inplace, plus-terminated
find Assets -name '*.meta' -exec gawk -i inplace "{print}" {} +
2 0222 - sort's output flag after the placeholder
find Assets -name '*.meta' -exec sort {} -o {} \;
2 2022 - yq's in-place flag with a double-quoted suffix
find Assets -name '*.meta' -exec yq -i".bak" .guid=1 {} \;
2 2222 - sed's in-place flag bundled with -n
find Assets -name '*.meta' -exec sed -ni s/guid/x/ {} \;
2 2222 - sed's in-place flag as a separate token after -n
find Assets -name '*.meta' -exec sed -n -i s/guid/x/ {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec awk '/guid/{print FILENAME}' {} \;
0 0000 - FP: sort -c only checks order — r3 had no second stage and blocked every sort
find Assets -name '*.meta' -exec sort -c {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec git log --oneline -- {} \;
0 0000 - a quoted command name still resolves to the command
find Assets -name '*.meta' -exec 'grep' -l guid {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec git blame -- {} \;
0 2200 X r4 decided the write flag by regexing the whole line; r5 positional read closed this on purpose
find Assets -name '*.meta' -exec git --no-pager show HEAD -- {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec sed -n "1,5p" {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec sed --quiet -e '/guid/p' {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec yq ".guid" {} \;
0 0000 - FP: sort -u writes nothing — r3 blocked every sort
find Assets -name '*.meta' -exec sort -u {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec openssl dgst -md5 -hex {} \;
0 0000 - a shell-operator character inside a quoted grep pattern is data
find Assets -name '*.meta' -exec grep -l 'a|b' {} \;
0 0000 - a quoted semicolon inside a grep pattern is data
find Assets -name '*.meta' -exec grep -l ';' {} \;
0 0000 - a quoted double-ampersand inside a grep pattern is data
find Assets -name '*.meta' -exec grep -l '&&' {} \;
0 0000 - a quoted in-place flag inside a grep pattern is data
find Assets -name '*.meta' -exec grep -l '-i' {} \;
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec sed -n '/&&/p' {} \;
2 2202 - a quoted double-ampersand must not end sed's clause and hide the -i after it
find Assets -name '*.meta' -exec sed -n '&&' -i {} \;
2 2222 - two clauses, plus-terminated first, destructive second
find Assets -name '*.meta' -exec grep -l guid {} + -exec gzip {} \;
2 2222 - a parenthesised find expression with a destructive exec
find Assets \( -name '*.meta' \) -exec gzip {} \;
2 2222 - a destructive exec with a trailing shell redirect
find Assets -name '*.meta' -exec gzip {} \; > /tmp/o.txt
2 2222 - two chained xargs stages, the second one destructive
find Assets -name '*.meta' | xargs grep -l guid | xargs sed -i s/a/b/
2 0222 - an escaped prefix in front of an escaped verb
find Assets -name '*.meta' -exec \env \rm {} \;
2 2220 - basename vouching, closed: the shell reads ./\grep as ./grep, which was permitted at all four earlier versions - a path this gate cannot place is now the command's own name, and no allowlist entry contains a slash
find Assets -name '*.meta' -exec ./\grep -l guid {} \;
0 2000 H KNOWN HOLE, inherited: an awk program in a -f file can write and no arm models it
find Assets -name '*.meta' -exec awk -f script.awk {} \;
0 2000 H KNOWN HOLE, inherited: an awk write through a pipe to an external command is not modelled
find Assets -name '*.meta' -exec awk '{print | "tee " FILENAME}' {} \;
0 2000 H KNOWN HOLE, inherited: GNU long-option abbreviation; a wider glob would false-positive on yq --input-format
find Assets -name '*.meta' -exec sed --in-pl s/guid/x/ {} \;
2 2222 - KNOWN FALSE POSITIVE: cp is decided by argument position, which this gate does not parse
find Assets -name '*.meta' -exec cp {} /tmp/backup/ \;
2 2222 - KNOWN FALSE POSITIVE: rsync, same reason as cp
find Assets -name '*.meta' -exec rsync {} /tmp/backup/ \;
2 0002 - NEW FALSE POSITIVE: command substitution makes the token stream unparseable, so it blocks
find "$(pwd)/Assets" -name '*.meta' -exec grep -l guid {} \;
0 0000 - command substitution inside single quotes is inert and must not trip the unparseable arm
find Assets -name '*.meta' -exec grep -l '$(rm -rf /)' {} \;
2 2222 - a command hidden behind command substitution blocks as unparseable
find Assets -name '*.meta' -exec $(echo sed) -i {} \;
2 2222 - a command hidden behind backticks blocks as unparseable
find Assets -name '*.meta' -exec `echo sed` -i {} \;
2 2002 - ANSI-C quoting is not decoded, so it blocks as unparseable
find Assets -name '*.meta' -exec sed $'-i' s/guid/x/ {} \;
2 2002 - an unterminated quote blocks rather than being parsed on a guess
find Assets -name '*.meta' -exec sed -e 's/guid/x/ {} \;
2 2202 - a quoted semicolon on the xargs route is an argument, not a clause end
find Assets -name '*.meta' -print0 | xargs -0 sed -e ';' -i
0 2220 X the ledgered round-4 residual: a shell redirect on an xargs pipeline is not awk s own argument
find Assets -name '*.meta' -print0 | xargs -0 awk '{print}' 2>/dev/null
2 2222 - a redirect must be skipped, not treated as a clause end that hides the -i after it
find Assets -name '*.meta' -print0 | xargs -0 sed 2>/dev/null -i s/a/b/
0 2000 X r3 had no second stage, so it blocked every sed/awk/git/sort/openssl/yq; r4 closed this on purpose
find Assets -name '*.meta' -exec sed -n 1p {} \; 2>/dev/null
2 2222 - a stderr redirect after the terminator does not excuse the in-place flag before it
find Assets -name '*.meta' -exec sed -i s/guid/x/ {} \; 2>/dev/null
0 2220 X the tokeniser keeps a quoted argument whole, so git's -c value is one token and the subcommand is still reached; every earlier version split it on the space and read B as the subcommand
find Assets -name '*.meta' -exec git -c 'user.name=A B' log --oneline {} \;
0 2020 X a literal in-place flag inside a quoted sed expression is data; the arms re-split on the tokeniser's TAB, so it stays one argument instead of becoming a flag
find Assets -name '*.meta' -exec sed -n -e 's/a/b -i/p' {} \;
2 2222 - a bare redirect and its operand belong to the shell, so skipping them must not end the clause and hide the flag after it
find Assets -name '*.meta' -print0 | xargs -0 sed > /tmp/o.txt -i s/a/b/
0 2220 X a bare redirect and its operand are the shell's, not awk's; every earlier version read the > as awk's own write form
find Assets -name '*.meta' -print0 | xargs -0 awk '{print}' > /tmp/o.txt
0 2220 X the appending spelling of the same shell redirect, same reason
find Assets -name '*.meta' -print0 | xargs -0 awk '{print}' >> /tmp/o.txt
2 2222 - a PATH-QUALIFIED xargs is still an introducer: deleting the */xargs arm left the whole corpus green while this payload went 2 to 0 and destroyed 3 of 3 real files
find Assets -name '*.meta' -print0 | /usr/bin/xargs -0 sed -i s/a/b/
0 0000 - its read-only twin, so the path-qualified arm cannot be satisfied by blocking every absolute path
find Assets -name '*.meta' -print0 | /usr/bin/xargs -0 grep -l guid
2 2222 - a path-qualified xargs reached through -exec rather than through a pipe
find Assets -name '*.meta' -exec /usr/bin/xargs -0 gzip {} \;
2 0002 - a backtick in an otherwise read-only clause: without the detection the substitution decides what runs and the gate never sees it
find Assets -name '*.meta' -exec grep -l `echo guid` {} \;
2 2202 - a backslash-escaped semicolon on the xargs route is an argument, not a shell operator; without the backslash flag the clause ends and the -i after it is lost
find Assets -name '*.meta' -print0 | xargs -0 sed \; -i s/a/b/
0 0200 X an unquoted operator really does end the clause, so a later -o is not sort's; r4 regexed the whole line and blocked it
find Assets -name '*.meta' -print0 | xargs -0 sort {} && echo -o
0 0220 X a redirect's operand is a filename, not an argument: skipping the operand is what keeps this -o out of sort's own arguments
find Assets -name '*.meta' -print0 | xargs -0 sort > -o {} {}
2 2222 - a second -exec with the first clause's terminator missing: the in-args introducer arm is the only thing that flushes here
find Assets -name '*.meta' -exec grep -l guid -exec gzip {} \;
2 2222 - a second bare xargs with no operator between, so the in-args arm rather than the idle arm has to catch it
find Assets -name '*.meta' -print0 | xargs -0 grep -l guid xargs -0 gzip
2 2222 - the same shape with the second xargs path-qualified, which is a different pattern in the same arm
find Assets -name '*.meta' -print0 | xargs -0 grep -l guid /usr/bin/xargs -0 gzip
0 0000 - a read-only command behind an env prefix: the prefix vocabulary must step over env rather than reporting it as the command
find Assets -name '*.meta' -exec env grep -l guid {} \;
0 0020 X a quoted introducer-shaped word in idle position introduces nothing; r5 dequoted it and read the next word as the command
find Assets -name '*.meta' -o -name 'xargs' gzip -exec grep -l guid {} \;
2 2222 - git reached with no arguments at all, which is the one path to the git arm's final refusal
find Assets -name '*.meta' -print0 | xargs -0 git
2 2222 - a clause's arguments must not survive into the next one: with both args=() sites removed the first clause's read-only git log vouches for the second clause's git rm
find Assets -name '*.meta' -exec git log {} \; -exec git rm {} \;
2 0000 - route class: a glob split by quoting - "*.m"*"eta" dequotes to *.m*eta, and find globs it; rewrote the guid line of 3 of 3 real .meta files at every earlier version
find Assets -name "*.m"*"eta" -exec sed -i s/guid/XXXX/ {} \;
2 0000 - route class: the closing quote moved one character left - '*.met'a dequotes to *.meta; rewrote 3 of 3 real files
find Assets -name '*.met'a -exec sed -i s/guid/XXXX/ {} \;
2 0000 - route class: the quote closes after .m instead - '*.m'eta dequotes to *.meta; rewrote 3 of 3 real files
find Assets -name '*.m'eta -exec sed -i s/guid/XXXX/ {} \;
2 0000 - route class: only the tail is quoted - *.me"ta" dequotes to *.meta; rewrote 3 of 3 real files
find Assets -name *.me"ta" -exec sed -i s/guid/XXXX/ {} \;
2 0000 - route class: the quote closes right after the dot - '*.'meta dequotes to *.meta; rewrote 3 of 3 real files
find Assets -name '*.'meta -exec sed -i s/guid/XXXX/ {} \;
2 0000 - route class: two adjacent double-quoted runs with nothing between them; rewrote 3 of 3 real files
find Assets -name "*.me""ta" -exec sed -i s/guid/XXXX/ {} \;
2 0000 - route class: two adjacent single-quoted runs; rewrote 3 of 3 real files
find Assets -name '*.m''eta' -exec sed -i s/guid/XXXX/ {} \;
2 0000 - route class with no quotes at all: a backslash escape splits the literal, *.me\ta dequotes to *.meta; rewrote 3 of 3 real files
find Assets -name *.me\ta -exec sed -i s/guid/XXXX/ {} \;
2 0000 - route class on -path rather than -name, so the fix cannot be a rule about the word -name; rewrote 3 of 3 real files
find Assets -path '*.met'a -exec sed -i s/guid/XXXX/ {} \;
2 0000 - route class on a bare path argument with no glob at all - find's starting point is the split literal; rewrote 3 of 3 real files
find Assets/'Player.cs.met'a -exec sed -i s/guid/XXXX/ {} \;
2 0000 - route class reaching the xargs arm instead of -exec, so the fix is upstream of both; rewrote 3 of 3 real files
find Assets -name '*.met'a -print0 | xargs -0 sed -i s/guid/XXXX/
2 0000 - route class on find's own deletion flag: executed, it left the directory with no .meta files at all
find Assets -name '*.met'a -delete
0 0000 - the read twin of the split spelling: routing on a dequoted token must not turn an allowlisted read into a block
find Assets -name '*.met'a -exec grep -l guid {} \;
0 0000 - the count twin of the split spelling: a find with no exec'd command classifies nothing, however the glob is spelled
find Assets -name "*.m"*"eta" | wc -l
2 0000 - no find anywhere: the shell globs the .meta files and xargs runs sed -i over them; rewrote 3 of 3 real files at every earlier version
ls Assets/*.meta | xargs sed -i s/guid/XXXX/
2 0000 - the payload that decided against a cheap raw-string pre-filter: no find, no literal xargs, no literal .meta, and it rewrote 3 of 3 real files
ls Assets/*.me\ta | x\args sed -i s/guid/XXXX/
0 0000 - the read twin with no find: the allowlist still decides, so a glob into xargs grep stays permitted
ls Assets/*.meta | xargs grep -l guid
2 0000 - the old precondition bounded the .meta reference to find's own pipeline segment, so a .meta named after a pipe reached nothing; rewrote 3 of 3 real files
find Assets | grep .meta | xargs sed -i s/guid/XXXX/
0 0000 - a glob into a counter, with no find and no exec'd command: still permitted
ls Assets/*.meta | wc -l
2 0000 - a shell glob into xargs gzip, no find: executed, it replaced all three .meta files with .meta.gz
printf '%s\n' Assets/*.meta | xargs gzip
0 0000 - the deletion arm still asks for a find: without that requirement this read of a .meta file would report a deletion nothing is doing
grep -- -delete Assets/Player.cs.meta
2 0000 - basename vouching: a real program at ./evil/grep that rewrites its arguments destroyed all three .meta files, 119 B to 6 B, with every earlier version returning 0
find Assets -name '*.meta' -exec ./evil/grep -l guid {} \;
2 0000 - basename vouching from an absolute path outside the trusted directories: same program, same 119 B to 6 B
find Assets -name '*.meta' -exec /tmp/evil/grep -l guid {} \;
0 0000 - the trusted spelling stays permitted: /usr/bin/grep is what this repository's own guide mandates, and rejecting every slash would charge a block for following it
find Assets -name '*.meta' -exec /usr/bin/grep -l guid {} \;
0 0000 - the other trusted directory, compared whole rather than as a prefix
find Assets -name '*.meta' -exec /bin/cat {} \;
2 0000 - the measured cost of the trusted set: /usr/local/bin is user-writable on the macOS host this toolkit plans to support, so a read spelled with that path pays one first-attempt block
find Assets -name '*.meta' -exec /usr/local/bin/rg -l guid {} \;
2 0000 - why the trusted directories are compared whole and not as a /usr/bin/* glob: this path matches that glob, is not in /usr/bin at all, and destroyed 3 of 3 real files
find Assets -name '*.meta' -exec /usr/bin/../../tmp/evil/grep -l guid {} \;
2 0000 - the same identity question on the xargs route rather than -exec: destroyed 3 of 3 real files
find Assets -name '*.meta' -print0 | xargs -0 ./evil/grep -l guid
2 0000 - a bare relative path with no directory component of its own: nothing named ./grep existed, and a name the table cannot place still costs a block on a read rather than a pass on a write
find Assets -name '*.meta' -exec ./grep -l guid {} \;
0 0000 - a trusted env still steps over itself to the command it runs, so the prefix vocabulary keeps working when it is spelled with a path
find Assets -name '*.meta' -exec /usr/bin/env grep -l guid {} \;
2 0000 - an untrusted env is not the env prefix: ./evil/env destroyed 3 of 3 real files, and skipping it because its last path component spells env is the same defect one word over
find Assets -name '*.meta' -exec ./evil/env grep -l guid {} \;
2 2000 - the identity question reaches the second stage too: ./evil/sed with only read-only flags destroyed 3 of 3 real files
find Assets -name '*.meta' -exec ./evil/sed -n 1p {} \;
0 2000 X verified false positive: r3 blocked every sed outright; /usr/bin/sed -n 1p is the trusted path with no write flag and it left byte length and crc identical on 3 of 3 real files
find Assets -name '*.meta' -exec /usr/bin/sed -n 1p {} \;
2 2222 - a trusted directory vouches for the name only, never for the flags: /usr/bin/sed -i rewrote 3 of 3 real files and must still block
find Assets -name '*.meta' -exec /usr/bin/sed -i s/guid/XXXX/ {} \;
0 0000 - a path-qualified introducer and a path-qualified allowlisted command in one line, both trusted, both still permitted
find Assets -name '*.meta' -print0 | /usr/bin/xargs -0 /usr/bin/grep -l guid
0 0000 - LIVE HOLE, recorded not closed: a quoted run may not introduce a command (task 2b's ruling, which fixed a measured false positive), so -'e'xec dequotes to -exec for find and to nothing for this gate; executed, it rewrote 3 of 3 real .meta files
find Assets -name '*.meta' -'e'xec sed -i s/guid/XXXX/ {} \;
0 0020 H LIVE HOLE, inherited: r5 blocked this and task 2b permitted it on purpose, because the same guard is what stops a quoted 'xargs' inside a grep pattern from introducing; executed, it rewrote 3 of 3 real .meta files
find Assets -name '*.meta' -print0 | 'xargs' -0 sed -i s/guid/XXXX/
0 0000 - LIVE HOLE: the direct shape is a raw-regex denylist and the same split-literal class walks past it; executed, it deleted one of three real .meta files
rm -f Assets/'Player.cs.met'a
0 0000 - LIVE HOLE: the route reads what a token SAYS after dequoting, not what it will MATCH after globbing, and *.me* says nothing about .meta; executed, it rewrote 3 of 3 real .meta files
find Assets -name '*.me*' -exec sed -i s/guid/XXXX/ {} \;
0 0000 - LIVE HOLE, the widest spelling of the one above: nothing here models the filesystem, so a glob that names no extension at all routes nowhere; executed, it rewrote 3 of 3 real .meta files
find Assets -name '*' -exec sed -i s/guid/XXXX/ {} \;
2 0000 - the route decision reads the token an unterminated quote left pending, not only the tokens that closed: without that the only .meta reference on the line is invisible and the whole command routes nowhere
find Assets -exec sed -i s/guid/XXXX/ {} \; -name '*.meta
2 0000 - metacharacter set: a backslash inside double quotes survives the scanner, bash keeps it and find's fnmatch eats it as an escape; executed, it left no .meta files at all
find Assets -name "*.\meta" -delete
2 0000 - metacharacter set: the same escape inside single quotes, one character further in; executed, it left no .meta files at all
find Assets -name '*.m\eta' -delete
2 0000 - metacharacter set: every letter of the extension escaped; executed, it left no .meta files at all
find Assets -name "*.\m\e\t\a" -delete
2 0000 - metacharacter set: a one-character bracket class is a literal, and this spelling says .meta with a metacharacter standing inside it - the exact phrase the first cut of meta_ref claimed to test; executed, it left no .meta files at all
find Assets -name '*.me[t]a' -delete
2 0000 - metacharacter set, the rewriting twin of the backslash form; rewrote 3 of 3 real files
find Assets -name "*.\meta" -exec sed -i s/guid/XXXX/ {} \;
2 0000 - metacharacter set, the rewriting twin of the bracket form; rewrote 3 of 3 real files
find Assets -name '*.me[t]a' -exec sed -i s/guid/XXXX/ {} \;
2 0000 - metacharacter set on the xargs arm, so the fix is not a rule about -exec; rewrote 3 of 3 real files
find Assets -name '*.me[t]a' -print0 | xargs -0 sed -i s/guid/XXXX/
2 0000 - metacharacter set on -path with the bracket over the first letter; rewrote 3 of 3 real files
find Assets -path '*.[m]eta' -exec sed -i s/guid/XXXX/ {} \;
2 0000 - a bracket RANGE, which a first-member reduction would miss and a one-character wildcard catches; rewrote 3 of 3 real files
find Assets -name '*.m[a-z]ta' -exec sed -i s/guid/XXXX/ {} \;
2 0000 - a bracket with two members, same reason; rewrote 3 of 3 real files
find Assets -name "*.me[tT]a" -exec sed -i s/guid/XXXX/ {} \;
2 0000 - the question mark matches EXACTLY one character, so deleting it the way a star is deleted loses this match; rewrote 3 of 3 real files
find Assets -name '*.m?ta' -exec sed -i s/guid/XXXX/ {} \;
2 0000 - a bracket whose first member is a literal close-bracket, which the naive bracket regex ends early on; rewrote 3 of 3 real files
find Assets -name '*.me[]t]a' -exec sed -i s/guid/XXXX/ {} \;
2 0000 - the same bracket class with no find at all, so both round-1 findings meet in one payload; rewrote 3 of 3 real files
ls Assets/*.me[t]a | xargs sed -i s/guid/XXXX/
0 0000 - the read twin of the bracket spelling: widening what counts as a .meta reference must not turn an allowlisted read into a block
find Assets -name '*.me[t]a' -exec grep -l guid {} \;
0 0000 - the count twin of the backslash spelling
find Assets -name "*.\meta" | wc -l
0 0000 - the over-widening guard: a bracket glob that does NOT name .meta must still not route, or the wildcard rule has swallowed every glob on the machine
find docs -name '*.m[dk]' -exec sed -i s/a/b/ {} \;
0 0000 - the same guard without a bracket: a write to .md files is not this gate's business
find docs -name '*.md' -exec sed -i s/a/b/ {} \;
2 0000 - an introducer that is itself a program: ./evil/xargs was admitted purely because its last path component spells xargs, and it destroyed all three .meta files, 119 B to 6 B, while the gate classified the grep it never ran
find Assets -name '*.meta' -print0 | ./evil/xargs -0 grep -l guid
2 0000 - the same with a different innocent-looking trailing command, so the record is about the introducer and not about grep; destroyed all three, 119 B to 6 B
find Assets -name '*.meta' -print0 | ./evil/xargs -0 stat
2 0000 - the same from an absolute path outside the trusted directories; destroyed all three, 119 B to 6 B
find Assets -name '*.meta' -print0 | /tmp/evil/xargs -0 grep -l guid
2 2222 - the discriminator that says where the hole was NOT: reached through -exec rather than a pipe, an untrusted xargs has always blocked, because xargs is not on the read-only list; only the pipeline site was open
find Assets -name '*.meta' -exec ./evil/xargs -0 grep -l guid {} \;
0 0000 - LIVE HOLE, deliberate: the route scan ignores the unparseable marker, because routing on it would send every command containing a dollar-paren into a classification that ends in a block; the cost of that choice is this ANSI-C spelling, which rewrote 3 of 3 real files
find Assets -name $'*.\155eta' -exec sed -i s/guid/XXXX/ {} \;
0 0000 - LIVE HOLE, same choice, command-substitution spelling; rewrote 3 of 3 real files
find Assets -name "*.$(printf m)eta" -exec sed -i s/guid/XXXX/ {} \;
0 0000 - LIVE HOLE, same choice, backtick spelling; rewrote 3 of 3 real files
find Assets -name "*.`printf m`eta" -exec sed -i s/guid/XXXX/ {} \;
2 0000 - the metacharacter pre-test's own discriminator: no star anywhere, so admitting a backslash to the slow path is the only thing that routes this - every other backslash payload here also carries a star and is caught by the star alone
find Assets -name "Player.cs.\meta" -exec sed -i s/guid/XXXX/ {} \;
2 0000 - the same for a bracket class with no star: rewrote 3 of 3 real files
find Assets -name 'Player.cs.me[t]a' -exec sed -i s/guid/XXXX/ {} \;
2 0000 - the same for a lone question mark with no star: rewrote 3 of 3 real files
find Assets -name 'Player.cs.m?ta' -exec sed -i s/guid/XXXX/ {} \;
2 0000 - the IN-ARGS introducer site's own discriminator: an untrusted path-qualified xargs appearing while another command is pending must be classified, not allowed to introduce a read-only stat that then vouches for the clause. Not destructive as written - grep never runs it - but it is the only payload that separates the two introducer sites, and removing the identity test at that site alone was a silent no-op until it existed
find Assets -name '*.meta' -print0 | xargs -0 grep -l guid ./evil/xargs -0 stat
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
tbg_fp=0
tbg_holes=0
tbg_hist2=0
tbg_unexplained=""
tbg_reasonless=""
tbg_badflag=""
while read -r tbg_exp tbg_hist tbg_ex tbg_note; do
    IFS= read -r tbg_payload || break
    case "$tbg_exp" in ''|'#'*) continue ;; esac
    tbg_ran=$((tbg_ran + 1))
    if [ "$tbg_exp" = "2" ]; then tbg_blocks=$((tbg_blocks + 1)); else tbg_permits=$((tbg_permits + 1)); fi

    # The monotonic property, checked as data rather than as a second probe: a payload any
    # earlier version blocked may not be permitted here without an `X` and a written reason.
    case "$tbg_ex" in
        '-') ;;
        X) tbg_fp=$((tbg_fp + 1)) ;;
        H) tbg_holes=$((tbg_holes + 1)) ;;
        *) tbg_badflag="${tbg_badflag}${tbg_ex} ${tbg_payload}
" ;;
    esac
    case "$tbg_hist" in
        *2*)
            tbg_hist2=$((tbg_hist2 + 1))
            if [ "$tbg_exp" = "2" ]; then
                tbg_protected=$((tbg_protected + 1))
            else
                case "$tbg_ex" in
                    X|H) [ -n "$tbg_note" ] || tbg_reasonless="${tbg_reasonless}${tbg_payload}
" ;;
                    *) tbg_unexplained="${tbg_unexplained}${tbg_payload}
" ;;
                esac
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
assert_eq "" "$tbg_badflag" \
    "every exemption flag is one of - (none), X (verified false positive) or H (known live hole)"

# THE ONE HARDCODED NUMBER IN THIS FILE, AND IT IS HARDCODED ON PURPOSE.
# `H` says "this payload really can write and we permit it anyway". Four such records exist, all
# inherited, all named in the corpus above:
#     -exec awk -f script.awk {} \;              an awk program in a -f file
#     -exec awk '{print | "tee " FILENAME}' {} \;  an awk write through a pipe
#     -exec sed --in-pl s/guid/x/ {} \;           GNU long-option abbreviation
#     | 'xargs' -0 sed -i s/guid/XXXX/            a QUOTED introducer (task 2c added this record)
# Everywhere else this repository forbids writing a count down, because a derived count goes stale.
# This one is not derived from the tree — it is a CEILING on a category that must only ever shrink,
# and a ceiling that moves silently is not a ceiling. Adding a fifth live hole must cost an edit
# here, with a reviewer looking at the diff.
#
# THE FOURTH ONE WAS ALWAYS THERE; WHAT TASK 2C ADDED WAS THE RECORD. r5 blocked that payload and
# task 2b permitted it deliberately, because the guard that refuses a quoted introducer is the
# same guard that stops a quoted `xargs` inside a grep pattern from introducing a command — 2b's
# corpus recorded the read that guard protects and never the write it lets through. Executed
# against real .meta files it rewrites 3 of 3. Task 2c did not close it: reversing another task's
# measured false-positive trade is a third judgement and this one's brief delegated two. The
# ceiling going up is the correct signal for a hole that was open and unrecorded — the number
# tracks what is WRITTEN DOWN, and writing one down is the only way the next round inherits an
# anchor instead of a rediscovery.
#
# Four more live holes are recorded in the corpus above WITHOUT an `H`, and the distinction is
# not a downgrade: `H` means "an earlier version of this hook blocked it", and those four
# (`-'e'xec`, `rm -f Assets/'Player.cs.met'a`, `-name '*.me*'`, `-name '*'`) were permitted at
# every version including r3, so there is no divergence for either ceiling to measure. Their
# reason column says LIVE HOLE in words. Marking them `H` would make this number mean something
# other than what the line above it says it means.
assert_eq "4" "$tbg_holes" \
    "the number of payloads recorded as known live holes has not grown"
# And the same ceiling on `X`, for the reason the round-1 review gave: marking a live hole `H`
# now reds the count above, but a future round could still downgrade a real block to a permit by
# calling it a VERIFIED false positive instead. That lie is only caught by the verdict assertion
# while the hook still blocks — so the moment someone changes the hook to permit it as well, the
# lie goes green. Both counts are therefore ceilings on the same thing: divergence from what an
# earlier version of this hook blocked. Any new divergence, whatever it is labelled, costs an
# edit here in front of a reviewer. Neither number is derived from the tree, so neither can go
# stale on its own; both move only when someone means them to.
#
# 45 IS THE SAME NUMBER TASK 2B ASSERTED AND IT IS NOT THE SAME 45, which is the one thing a
# ceiling cannot tell you. Task 2c removed one — `-exec ./\grep -l guid {} \;`, which was
# exempt because a path this gate could not place was vouched for by its last component, and is
# now a block — and added one, `-exec /usr/bin/sed -n 1p {} \;`, which r3 blocked because r3
# blocked every sed and which was executed against real .meta files without changing a byte. A
# compensating pair is invisible here for the same structural reason a two-sided rewrite of the
# hist column is invisible to the count below: a total says nothing about composition. That is
# recorded rather than papered over with a third count, which would have the same limit one
# level up.
assert_eq "45" "$tbg_fp" \
    "the number of payloads recorded as verified false positives has not grown"

# AND THE FROZEN HISTORY ITSELF, WHICH THE TWO CEILINGS ABOVE DO NOT GUARD.
#
# Everything monotonic here is derived from the `hist` column, and until this assertion existed
# the column was unguarded. Rewrite one protected record's hist from `202` to `000` and its
# expected verdict from `2` to `0`, then change the hook to permit it, and every corpus
# assertion, both ceilings, the unexplained/reasonless/badflag lists and all four non-emptiness
# assertions stay green. Deleting the record outright has the identical signature. The property
# was resting on a column nothing counted.
#
# WHY THIS COUNT AND NOT `tbg_protected`. Either reds on a hist rewrite and on a record
# deletion, so both close the reported evasion. This one is a property of the frozen column
# ALONE, and that makes it strictly wider: erasing the history behind an EXEMPTION — an `X`
# record whose hist goes `200` -> `000`, expected still 0, marker and reason untouched — reds
# here and is invisible to `tbg_protected`, because that record was never protected. An
# exemption whose historical evidence has been deleted is an exemption nobody can check.
#
# It is a fixed number for the same reason the two ceilings are: it is not derived from the
# tree, so it cannot go stale on its own, and moving it costs an edit in front of a reviewer.
#
# IT MOVED IN TASK 2C, FROM 211 TO 219, AND EVERY PART OF THAT IS DELIBERATE, so the arithmetic
# is written out rather than asserted and forgotten. 211 + 3 + 5 = 219.
#
#   +3   the column's new FOURTH digit: three payloads that no version before task 2b had ever
#        blocked now carry a block in their history (`-exec sort -'o' {} {}`, a command
#        substitution in the find's own path, a backtick in an otherwise read-only clause).
#   +5   new records an earlier version did block: `./evil/sed -n 1p`, `/usr/bin/sed -n 1p`,
#        `/usr/bin/sed -i`, the quoted-introducer record under the `H` ceiling above, and — from
#        round 1 of review — `-exec ./evil/xargs -0 grep -l guid {} \;`, which EVERY version has
#        blocked. That last one is a discriminator rather than a fix: it says where the
#        introducer hole was NOT, because only the PIPELINE site was ever open.
#
# The other 64 of the 69 records task 2c adds are `0000` — a hole that was open at every version
# is what a task that closes a hole is supposed to add.
#
# The record count moved 256 -> 325 across the same change, and that number is deliberately NOT
# asserted: it is the one figure here that a legitimate addition moves every time, so a ceiling
# on it would be edited on every commit and would stop being read. The three counts above are
# ceilings on DIVERGENCE, which is the thing that must only ever shrink.
assert_eq "219" "$tbg_hist2" \
    "the frozen hist column still records 219 payloads that an earlier hook version blocked"

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

# --- the route scan failing is a HIT, and the corpus cannot see that -------------------------
# The route decision runs the tokeniser in `meta` mode, and its `||` arm decides what happens
# when that scan cannot run at all. No payload can exercise it: the scan fails on the ENVIRONMENT
# (no awk, a broken awk), not on anything a command string can say. So it is asserted here, by
# putting an awk that exits non-zero at the front of PATH.
#
# WHAT IS MEASURED, AND WHAT THIS ASSERTION DOES NOT CLAIM. With that stub in place the hook
# exits 3. **Exit 3 IS NOT A BLOCK.** `_lib.sh` and docs/HOOK-REFERENCE.md both fix 2 as the
# blocking code, so 3 is a hook ERROR and the tool call proceeds — the destructive payload runs.
# Nor is it loud: the full capture on this host is rc=3, stdout 0 bytes, stderr 0 bytes. The
# first version of this assertion was labelled "a destructive .meta command is not permitted",
# which claims a safety property this gate does not have, and the label is now what it measures.
#
# It does that on EVERY command now, where task 2b's version did it only on commands it
# classified, because the scan is what became universal. The dying happens further down, at the
# two-stage gate's own `awk` in CMD_HASH, and that line is inherited and untouched here.
#
# The branch is still worth asserting, because the alternative is measurably worse: with the
# fallback flipped to `0` the same destructive payload exits **0**, which is an explicit PERMIT
# that the harness acts on, rather than an error it reports. Measured, all three, on this host:
# task 2b exits 3 / this version exits 3 / the flipped fallback exits 0. Silent-error versus
# silent-permit is a real difference and it is the only one this assertion holds.
tbg_no_awk() { # tbg_no_awk <payload> -> the hook's exit code with a failing awk on PATH
    local _sd _rc _stub
    _stub="$(mktemp -d "${TMPDIR:-/tmp}/bash-gate-noawk.XXXXXX")"
    printf '#!/bin/sh\nexit 3\n' > "$_stub/awk"
    chmod +x "$_stub/awk"
    _sd="$(mktemp -d "${TMPDIR:-/tmp}/bash-gate-noawk-state.XXXXXX")"
    printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s}}' \
        "$(printf '%s' "$1" | jq -Rs .)" \
        | PATH="$_stub:$PATH" UNITY_HOOK_STATE_DIR="$_sd" bash "$TBG_HOOK" > /dev/null 2>&1
    _rc=$?
    rm -rf "$_sd" "$_stub"
    printf '%s' "$_rc"
}
assert_eq "non-zero" \
    "$(_r="$(tbg_no_awk 'find Assets -name "*.meta" -exec sed -i s/guid/x/ {} \;')"; \
       [ "$_r" != "0" ] && echo non-zero || echo "exit 0 - the gate returned a PERMIT")" \
    "the route scan failing exits non-zero rather than returning a permit (this is NOT a block)"

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
# The splice's OWN evidence, which the two assertions above do not provide: both of those parse
# identically with or without the splice, because the backslash sits between whole tokens. This
# one needs it — the token `-i` is itself split by the line break, and without the splice it
# arrives as `-` and `i` and the in-place flag is never seen. Measured: 2 here, 0 with the splice
# removed, 2 at r3, 0 at r4 and r5.
assert_eq "2" "$(tbg_run_fresh 'find Assets -name "*.meta" -exec sed -\
i s/guid/x/ {} \;')" \
    "still blocks a write flag that a backslash-newline splits in half"

# ============================================================================================
# THE COST, IN EVERY DIMENSION THAT MOVES IT — NOT ONLY THE ONE THAT WAS OPTIMISED.
#
# This hook runs on EVERY Bash tool call, so its worst case is a user-visible hang. Rounds 4 and
# 5 both shipped one and neither had a cost assertion. The first version of THIS block had one,
# and it was wrong in the way this whole task is about: it varied a single dimension — total
# length, as one enormous quoted token — which is the dimension the awk tokeniser fixed. A
# command line a QUARTER that size, differing only in the number of arguments, blew straight
# through the same ceiling:
#
#     8 000 args in one clause   (248 KB)    32 605 ms      <- ceiling was 10 000 ms
#    16 000 args in one clause   (496 KB)    80 975 ms
#    20 000 args in one clause   (620 KB)   > 10 minutes
#
# Attribution, measured by timing the two functions separately on the 8 000-arg payload: the awk
# scan cost 114 ms and the bash loop cost 19 612 ms. The tokeniser was never the problem. It was
# `args="$args$SEP$tok"` — O(n^2) in arguments per clause — and it is now an array append plus
# one printf (see find_exec_flush). A cutoff was the other option the brief offers; making the
# accumulation linear is strictly better and it is what shipped.
#
# So the guard now varies THREE dimensions, because a guard that varies one is a guard that
# confirms the idea its author already had:
#
#                                          r3        r4         r5      here
#   D1  1 MB in a single quoted token     831     48 964    162 951     2 961
#   D2  16 384 args in one clause           -          -          -     1 401   (was > 10 min)
#   D3  500 -exec clauses                 272        590        289       472
#
# ONE CEILING, 10 000 ms, for all three. Deliberately loose: this repository documents its suite
# going flaky under CPU contention — the same commit measured 195 700 ms and 389 425 ms for the
# whole suite — and a tight wall-clock guard is the kind that gets deleted the first time CI is
# busy. 10 000 ms is >3x above the worst of the three and >4x below the cheapest version this
# check exists to catch.
#
# WHAT IT STILL DOES NOT VARY, said plainly: the PRODUCT of D2 and D3 (many clauses each with
# many arguments), and the number of unparseable markers. Measured once by hand at 200 clauses x
# 100 args: 1 060 ms, i.e. it behaves as the sum rather than the product. Nothing asserts that.
# The round-2 review re-measured that product at 5-8x this size, including a 4.2 MB line of 256
# clauses x one 16 KB quoted token, and found the same: cost stays linear at roughly 75-90 us
# per token in every shape it could construct.
#
# AND THE CEILING IS STILL EXCEEDABLE — the character of that changed rather than the fact. The
# first version of this block was broken at 248 KB by a shape-dependent blowup. The smallest
# input that now exceeds 10 000 ms is 1.4 MB / 131 072 tokens at 11 737 ms, the law is linear in
# every shape anyone has constructed, and every point asserted below has about 6x headroom. A
# guard that a 1.4 MB command line can trip is a different object from one a 248 KB command line
# could trip, and the difference is that this one has no cliff to fall off.
# ============================================================================================

# Built by doubling — `s="$s $tok"` in a loop is the same O(n^2) this block is about, and a test
# that takes a minute to build its own payload teaches the wrong lesson.
tbg_dbl() { # tbg_dbl <seed> <times>
    local _s="$1" _n="$2"
    while [ "$_n" -gt 0 ]; do _s="$_s$_s"; _n=$(( _n - 1 )); done
    printf '%s' "$_s"
}
tbg_cost() { # tbg_cost <payload> <expected-rc> <label>
    local _t0 _t1 _rc _ms
    _t0=$(( $(date +%s%N) / 1000000 ))
    _rc="$(tbg_run_fresh "$1")"
    _t1=$(( $(date +%s%N) / 1000000 ))
    _ms=$(( _t1 - _t0 ))
    assert_eq "$2" "$_rc" "$3 — the verdict, so the timing cannot pass by the hook doing nothing"
    assert_eq "under" "$([ "$_ms" -lt 10000 ] && echo under || echo "over: ${_ms} ms")" \
        "$3 — under 10 000 ms end to end"
}

# D1 — total length, as one quoted token. 2^20 characters.
tbg_d1="$(LC_ALL=C printf '%*s' 1048576 '' | LC_ALL=C tr ' ' 'a')"
tbg_cost "find Assets -name '*.meta' -exec grep -l '$tbg_d1' {} \\;" "0" \
    "D1: a 1 MB quote-leading command line"
unset tbg_d1

# D2 — argument count in ONE clause. 2^14 = 16 384 arguments, 180 KB.
tbg_d2="$(tbg_dbl ' aaaaaaaaaa' 14)"
tbg_cost "find Assets -name '*.meta' -exec grep -l$tbg_d2 {} \\;" "0" \
    "D2: 16 384 arguments in one clause"
# and the destructive twin, so the flag is still found after 16 384 arguments
tbg_cost "find Assets -name '*.meta' -exec sed$tbg_d2 -i {} \\;" "2" \
    "D2: an in-place flag after 16 384 arguments"
unset tbg_d2

# D3 — clause count. 2^9 = 512 clauses.
tbg_d3="$(tbg_dbl ' -exec grep -l guid {} \;' 9)"
tbg_cost "find Assets -name '*.meta'$tbg_d3" "0" \
    "D3: 512 read-only -exec clauses"
unset tbg_d3

# D4 — THE DIMENSION TASK 2C INTRODUCED, and the one every payload above is blind to.
#
# D1..D3 all name .meta, so all three measure the route AFTER it has fired. The route scan now
# runs on EVERY Bash call, including the overwhelming majority that this gate has nothing to say
# about, and until this block existed nothing here measured that at all — a cost guard that
# varies only the dimensions the previous author was thinking about is the exact shape the
# header above warns against, and this file had just reproduced it.
#
# Measured on this host, end to end: a 1 MB command with no .meta in it cost 567 ms at task 2b
# and 1 088 ms here. The same 10 000 ms ceiling, and the verdict assertion is `0` — a permit,
# which is the point: the expensive path must end in the gate saying nothing.
tbg_d4="$(LC_ALL=C printf '%*s' 1048576 '' | LC_ALL=C tr ' ' 'a')"
tbg_cost "echo $tbg_d4" "0" \
    "D4: a 1 MB command the gate has nothing to say about"
unset tbg_d4
# and the same shape as many tokens rather than one, since the scan is per character but the
# route decision is per token
tbg_d4b="$(tbg_dbl ' bbbbbbbbbb' 14)"
tbg_cost "echo$tbg_d4b" "0" \
    "D4: 16 384 tokens the gate has nothing to say about"
unset tbg_d4b
