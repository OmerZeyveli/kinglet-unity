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

# Re-review finding: restoring `mv` restored one verb out of a family. Before this task ANY find
# naming .meta was classified — indiscriminate, which blocked a count, and which also covered every
# destructive verb for free. Requiring an action gave back the counts and dropped the verbs with
# them. All six below were measured at be2a582 as blocked and had become allowed; each is an act
# this task broke, not a shape nobody had thought of.
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec rename .meta .meta.bak {} \;')" \
    "still blocks find -exec rename — the canonical mass-rename tool"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec prename s/meta/bak/ {} \;')" \
    "still blocks find -exec prename, which the left boundary makes a separate token"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec mmv {} "#1.bak" \;')" \
    "still blocks find -exec mmv — literally mass-move"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec unlink {} \;')" \
    "still blocks find -exec unlink — literally deletion"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec shred -u {} \;')" \
    "still blocks find -exec shred"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -exec truncate -s 0 {} \;')" \
    "still blocks find -exec truncate, which destroys the GUID in place"
assert_eq "2" "$(tbg_run 'find Assets -name "*.meta" -print0 | xargs -0 mmv')" \
    "still blocks a mass rename reached through xargs"
assert_eq "0" "$(tbg_run 'find Assets -name "*.meta" -exec grep -l guid {} \;')" \
    "does not block find -exec grep, which reads the GUIDs it names"

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
