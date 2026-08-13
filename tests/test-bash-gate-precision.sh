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
