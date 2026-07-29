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
