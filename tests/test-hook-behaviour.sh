#!/usr/bin/env bash
# ============================================================================
# test-hook-behaviour.sh — one positive behavioural probe per REGISTERED hook.
#
# WHY THIS FILE EXISTS. Three hooks — warn-filename.sh, warn-platform-defines.sh and
# warn-serialization.sh — were registered in .claude/settings.json and executed by ZERO tests.
# warn-serialization.sh is the hook .claude/rules/serialization.md opens its silent-data-loss case
# with, and the one .claude/settings.local.json.template names as the reason `minimal` is a safety
# setting rather than a speed setting: guarded by name in three shipped places and by behaviour in
# none. The first of the three anyone actually ran turned out to be broken — warn-filename.sh died
# rc=1 with zero bytes on an ordinary Edit fragment, against its own `# Exit: 0 always` header. A
# 1-of-1 defect rate on the unmeasured set is the argument for measuring the rest.
#
# WHAT IT ASSERTS, per hook, for every hook settings.json registers:
#
#   1. IT ACTS.  Given input it is supposed to respond to, it produces the response — and the
#      response is measured in BYTES, not in exit status alone. A hook that exits 2 while writing
#      nothing has blocked a tool call without telling anyone why.
#   2. ITS KILL SWITCH KILLS IT.  With DISABLE_UNITY_HOOKS=1, and again with its own
#      DISABLE_HOOK_<NAME>=1, the same input produces zero bytes and exit 0. Both halves matter:
#      a switch that silences the message but still exits 2 has disabled the explanation and kept
#      the block.
#
# THE ACTING BYTE COUNT IS PRINTED BESIDE EVERY ZERO, and that is the point of the message format
# rather than decoration. A probe whose passing condition is silence is worthless without its
# non-silent baseline: if the payload stops triggering the hook, "0 bytes with the switch on" keeps
# passing forever over a hook that now emits nothing in either state. Measured on
# warn-serialization.sh: pristine 381 B / 0 B / 0 B; with `source _lib.sh` disabled, 381 B / 381 B /
# 381 B — the hook survives that mutation, the SWITCH is what is lost, and only the two zeros move.
#
# THE HOOK LIST IS DERIVED FROM settings.json AND IS NOT HAND-MAINTAINED. A hand-maintained list is
# an assertion that decays in silence: one wave retired 19 surfaces and extended the relevant hand
# list by zero while the guard stayed green throughout. A registered hook with no probe FAILS here
# by name, so adding a hook and adding its probe are the same commit.
#
# THE COVERAGE CHECK IS EXECUTION-KEYED, NOT NAME-KEYED, and it has to be: this file necessarily
# contains every hook's name in its own payload table, so any derivation that greps the tree for a
# hook name would match itself and report full coverage over an empty probe set. A hook counts as
# covered only when a probe actually RAN and wrote a record line — text in this file cannot produce
# one.
#
# IDIOM: RUNNER-PROVIDED. This file uses the runner's assert_eq / assert_file_exists and $REPO_DIR
# and defines none of them. `bash tests/test-hook-behaviour.sh` standalone therefore EXITS 0 HAVING
# ASSERTED NOTHING — the helpers are undefined and $REPO_DIR is empty. Run it through
# `bash tests/run-tests.sh` and read its section; a standalone run reports a pass in both
# directions and proves nothing about either.
# ============================================================================

HOOKS_DIR="${REPO_DIR}/.claude/hooks"
SETTINGS_JSON="${REPO_DIR}/.claude/settings.json"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kinglet-hook-behaviour.XXXXXX")"
PROBE_RECORD="${WORK_DIR}/probe-record.tsv"
: > "$PROBE_RECORD"
RUN_SEQ=0

# --- The registered set, derived from settings.json ------------------------
#
# Every event, every matcher block, every command. `sed` reduces `.claude/hooks/foo.sh` to `foo`.
# `sort -u` because one hook may be registered under more than one event.
REGISTERED_HOOKS="$(jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command' "$SETTINGS_JSON" 2>/dev/null \
    | sed -e 's#.*/##' -e 's#\.sh$##' | sort -u)"
REGISTERED_COUNT="$(printf '%s\n' "$REGISTERED_HOOKS" | grep -c '[^[:space:]]' || true)"

# --- Anti-vacuity floor ----------------------------------------------------
#
# Everything below iterates over REGISTERED_HOOKS. If that derivation ever returns nothing — a
# renamed key, a jq that is not installed, a settings.json that stops parsing — the loop runs zero
# times, asserts nothing, and this file reports a serene green. The floor is not a hardcoded count
# (CLAUDE.md forbids those, and it would go stale the next time a hook is added or cut): it is the
# tree's own hook population, which moves with the tree. `_lib.sh` is excluded because it is the
# shared library and not a hook — the same exclusion _lib.sh's own header documents.
PRESENT_COUNT="$(find "$HOOKS_DIR" -maxdepth 1 -type f -name '*.sh' ! -name '_lib.sh' | grep -c . || true)"
assert_eq "$PRESENT_COUNT" "$REGISTERED_COUNT" \
    "settings.json registers every hook file present in .claude/hooks (${PRESENT_COUNT} present)"

# --- The payload table -----------------------------------------------------
#
# One branch per registered hook. A `case` rather than an associative array: macOS ships bash 3.2
# and `declare -A` does not exist there.
#
# Globals rather than return values, for the same reason (no namerefs in 3.2):
#   PAYLOAD    — the hook's stdin, a real Claude Code tool-call envelope
#   KIND       — block (exits 2 and explains) | advisory (exits 0 and explains)
#   STATE_FILE — set when the hook's observable effect is a state-file write rather than output.
#                Only the NAMED file is measured, so a hook that also touches unrelated bookkeeping
#                (session-restore.sh writes session-start-time on every run) does not register as
#                "acting" when the thing it was supposed to do did not happen.
#   PROBE_ENV  — extra environment the payload needs
#   PROBE_SETUP— shell run against the probe's fresh state dir before the hook, for hooks whose
#                trigger is pre-existing state rather than the payload
#
# WHICH PAYLOADS HAD TO BE INVENTED is itself the measurement. block-scene-edit, block-meta-edit,
# guard-project-config and block-legacy-input already had payloads in tests/test-hooks.sh and
# tests/test-block-legacy-input.sh; theirs are modelled on those. Every other payload here — the
# three warn-* hooks, bash-gate, track-edits, and all three session hooks — was written from the
# hook's source for the first time, because nothing had ever fed these hooks an input that makes
# them do their job.
select_probe() {
    PAYLOAD=''
    KIND='advisory'
    STATE_FILE=''
    PROBE_ENV=''
    PROBE_SETUP=''
    case "$1" in
        block-scene-edit)
            KIND='block'
            PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scenes/Main.unity","old_string":"a","new_string":"b"}}'
            ;;
        block-meta-edit)
            KIND='block'
            PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scripts/Player.cs.meta","old_string":"a","new_string":"b"}}'
            ;;
        block-legacy-input)
            KIND='block'
            # Absolute path under Assets/: the third-party and Editor/Tests exemptions are anchored
            # under Assets/, so a bare relative name would take a different branch.
            PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"/p/Assets/Scripts/A.cs","new_string":"if (Input.GetKey(k)) {}\n"}}'
            ;;
        guard-project-config)
            KIND='block'
            PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":".editorconfig","old_string":"a","new_string":"b"}}'
            ;;
        bash-gate)
            KIND='block'
            # First attempt at a destructive command is denied; the second proceeds. Each probe gets
            # a fresh state dir, so this is always a first attempt.
            PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"rm -rf Library/"}}'
            ;;
        warn-serialization)
            PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/P.cs","old_string":"[SerializeField] private float _speed;","new_string":"[SerializeField] private float _moveSpeed;"}}'
            ;;
        warn-filename)
            # The class name and the file name must disagree, and the content must carry a `class`
            # keyword. An Edit fragment with `: MonoBehaviour` and no `class` keyword is the input
            # that used to kill this hook outright — see its own comment at CLASS_NAME.
            PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"Assets/Player.cs","new_string":"public sealed class Enemy : MonoBehaviour { }\n"}}'
            ;;
        warn-platform-defines)
            PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"Assets/A.cs","new_string":"#if UNITY_PS5\nX();\n#endif\n"}}'
            ;;
        track-edits)
            # Writes nothing to stdout or stderr; its whole observable is the edits file.
            STATE_FILE='session-edits.txt'
            PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scripts/Probe.cs"}}'
            ;;
        session-restore)
            # Triggered by pre-existing state, not by its payload. saved_at is generated at run time
            # because the hook drops any session older than UNITY_SESSION_TTL_HOURS (default 4) —
            # a fixed timestamp in this file would start passing vacuously the day it went stale.
            PAYLOAD='{}'
            PROBE_SETUP='jq -n --arg s "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '"'"'{saved_at:$s,branch:"probe-branch",workflow_phase:"Execute",modified_files:["Assets/Scripts/Probe.cs"],last_command:"/unity-test",plan:{description:"probe plan",steps:[{name:"step one",status:"done"}]},verification:{last_iteration:"1"},agent_context:{last_agent:"unity-coder"}}'"'"' > "${UNITY_HOOK_STATE_DIR}/session.json"'
            ;;
        session-brief)
            # Prints the using-kinglet skill body, so it needs to be told where the project is.
            PAYLOAD='{}'
            PROBE_ENV="CLAUDE_PROJECT_DIR=${REPO_DIR}"
            ;;
        session-save)
            STATE_FILE='session.json'
            PAYLOAD='{}'
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

# --- Run one hook in one switch state --------------------------------------
#
# Sets PROBE_RC and PROBE_BYTES. The payload goes in by REDIRECTION, not through a pipe: a hook that
# never reads stdin (the three session hooks do not) would leave a pipe writer with no reader, and
# this repository has paid for SIGPIPE-under-pipefail more than once. A file redirect has no writer
# to signal.
#
# PROBE_BYTES is stdout + stderr, plus the named state file when the hook has one. That makes one
# number comparable across an advisory hook that explains itself on stderr and a bookkeeping hook
# whose entire job is a file append — and "zero bytes" means the same thing for both.
run_probe() {
    local hook="$1" switch_env="$2"
    local dir="${WORK_DIR}/${hook}-${RUN_SEQ}"
    RUN_SEQ=$((RUN_SEQ + 1))
    mkdir -p "${dir}/state"

    if [ -n "${PROBE_SETUP}" ]; then
        ( UNITY_HOOK_STATE_DIR="${dir}/state" ; eval "${PROBE_SETUP}" ) >/dev/null 2>&1 || true
    fi

    printf '%s' "$PAYLOAD" > "${dir}/payload.json"

    PROBE_RC=0
    env UNITY_HOOK_STATE_DIR="${dir}/state" ${PROBE_ENV} ${switch_env} \
        bash "${HOOKS_DIR}/${hook}.sh" \
        < "${dir}/payload.json" > "${dir}/stdout" 2> "${dir}/stderr" || PROBE_RC=$?

    local out_bytes state_bytes
    out_bytes=$(( $(wc -c < "${dir}/stdout") + $(wc -c < "${dir}/stderr") ))
    state_bytes=0
    if [ -n "${STATE_FILE}" ] && [ -f "${dir}/state/${STATE_FILE}" ]; then
        state_bytes=$(wc -c < "${dir}/state/${STATE_FILE}")
    fi
    PROBE_BYTES=$(( out_bytes + state_bytes ))
}

# --- The per-hook loop -----------------------------------------------------

for HOOK in $REGISTERED_HOOKS; do
    [ -n "$HOOK" ] || continue

    assert_file_exists "${HOOKS_DIR}/${HOOK}.sh" \
        "registered hook ${HOOK}.sh exists on disk"

    if ! select_probe "$HOOK"; then
        # Not assert_eq on a name — this is the branch that makes adding a hook and adding its
        # probe the same commit.
        assert_eq "probe defined" "NO PROBE" \
            "registered hook '${HOOK}' has a behavioural probe in tests/test-hook-behaviour.sh"
        continue
    fi

    # Same derivation _lib.sh uses: basename, uppercased, hyphens to underscores.
    OWN_SWITCH="DISABLE_HOOK_$(printf '%s' "$HOOK" | tr '[:lower:]-' '[:upper:]_')"

    run_probe "$HOOK" ''
    ACT_BYTES="$PROBE_BYTES"
    ACT_RC="$PROBE_RC"

    run_probe "$HOOK" 'DISABLE_UNITY_HOOKS=1'
    OFF_ALL_BYTES="$PROBE_BYTES"
    OFF_ALL_RC="$PROBE_RC"

    run_probe "$HOOK" "${OWN_SWITCH}=1"
    OFF_OWN_BYTES="$PROBE_BYTES"
    OFF_OWN_RC="$PROBE_RC"

    if [ "$KIND" = "block" ]; then EXPECT_RC=2; else EXPECT_RC=0; fi

    # 1. It acts — measured in bytes, so an exit code with no explanation cannot pass.
    ACT_VERDICT="silent"
    [ "$ACT_BYTES" -gt 0 ] && ACT_VERDICT="responds"
    assert_eq "responds" "$ACT_VERDICT" \
        "${HOOK} responds to its trigger payload (${ACT_BYTES} B, ${KIND})"

    # 2. It responds the way its kind promises.
    assert_eq "$EXPECT_RC" "$ACT_RC" \
        "${HOOK} exits ${EXPECT_RC} on its trigger payload (${KIND})"

    # 3/4. Both kill switches. Bytes AND exit status in one assertion: a switch that silences the
    # message while still exiting 2 has removed the explanation and kept the block. The acting
    # baseline is printed beside each zero so a probe that has quietly stopped triggering cannot
    # keep passing on silence alone.
    assert_eq "0B rc0" "${OFF_ALL_BYTES}B rc${OFF_ALL_RC}" \
        "${HOOK} fully silenced by DISABLE_UNITY_HOOKS=1 (acting baseline ${ACT_BYTES} B)"

    assert_eq "0B rc0" "${OFF_OWN_BYTES}B rc${OFF_OWN_RC}" \
        "${HOOK} fully silenced by ${OWN_SWITCH}=1 (acting baseline ${ACT_BYTES} B)"

    # The execution record. Written only by a probe that ran; Task 2 reads these lines.
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$HOOK" "$KIND" "$ACT_BYTES" "$ACT_RC" "$OFF_ALL_BYTES" "$OFF_OWN_BYTES" >> "$PROBE_RECORD"
    echo "  HOOK-PROBE ${HOOK} kind=${KIND} act=${ACT_BYTES}B rc=${ACT_RC} off_all=${OFF_ALL_BYTES}B off_own=${OFF_OWN_BYTES}B"
done

# --- Coverage, keyed on execution ------------------------------------------
#
# PROBED_COUNT counts record lines, and a record line is written only after a probe has actually run
# three times against a real hook. No amount of text in this file can add one, which is the property
# a name-keyed derivation cannot have when the file it scans is the file that lists the names.
PROBED_COUNT="$(awk 'END { print NR + 0 }' "$PROBE_RECORD")"
assert_eq "$REGISTERED_COUNT" "$PROBED_COUNT" \
    "every registered hook was probed by execution (${REGISTERED_COUNT} registered, ${PROBED_COUNT} probed)"

rm -rf "$WORK_DIR"
