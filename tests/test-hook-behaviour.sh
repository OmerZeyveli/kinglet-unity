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
#   1. IT ACTS.  Given input it is supposed to respond to, it produces THE response — asserted on a
#      distinctive needle from the hook's own message, not merely on a non-empty stream. Bytes and
#      exit status are each too weak alone: a hook that exits 2 while writing nothing has blocked a
#      tool call without saying why, and a hook whose message has been gutted still writes bytes if
#      any `echo` survives. MEASURED: replacing warn-serialization.sh's entire [FormerlySerializedAs]
#      warning with an unrelated stderr write left the byte-only version of this file at 62 pass /
#      0 fail — over the very hook whose missing behavioural coverage is this file's stated reason
#      for existing.
#
#      The needles ARE a hand-maintained list, deliberately. The kind of list this repository has
#      been burned by decays SILENTLY, because adding a thing to the tree and adding it to the list
#      are different commits. This one decays LOUDLY: change a hook's message and its needle reds at
#      once, so message and needle move together. The hook LIST is what must never be hand-kept, and
#      it is not. An EMPTY needle would restore the silent kind — `grep -qF -- ""` matches anything,
#      so `assert_contains` with an empty needle passes over any output at all, and `select_probe`'s
#      `*)` branch forces a new hook to gain a probe branch but cannot force that branch to carry a
#      needle. Measured, before the floor below existed: clearing one hook's needle left this file at
#      74 pass / 0 fail, logging `PASS ... (needle: )`. The per-hook floor in the loop closes it.
#
#      WHAT THE NEEDLE CANNOT SEE, stated because the sentences above claim less than they look
#      like they claim: it is matched against stdout, stderr and the named state file as ONE
#      haystack, so it cannot tell a printed message from a written one, nor the right stream from
#      the wrong one. Three measured consequences, none of which this file detects — a track-edits
#      that echoes the path to stderr instead of recording it (state file never created); a
#      session-brief that stops stripping frontmatter (4213 B, frontmatter emitted); and a
#      session-brief whose awk is redirected to stderr (byte-identical 3993 B, stdout 0 B), which
#      for a SessionStart hook means nothing reaches the session and its whole purpose is dead.
#      Widening PROBE_BYTES to separate the streams is a design change, not a needle change, and is
#      deliberately not made here.
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
#   NEEDLE     — a distinctive fragment of the hook's OWN message, matched literally against the
#                acting run. See bullet 1 above for why non-empty output is not enough.
#   PROBE_ENV  — extra environment the payload needs
#   PROBE_SETUP— shell run against the probe's fresh state dir before the hook, for hooks whose
#                trigger is pre-existing state rather than the payload
#
# WHICH PAYLOADS HAD TO BE INVENTED is itself the measurement, so it is stated under a criterion:
# a payload counts as PRE-EXISTING when some test file other than this one already RAN that hook on
# an input that drives it into its acting branch. Being named by a test file is not enough, and the
# gap is wider than one file: `/usr/bin/grep -rn -F` over tests/, excluding this file, finds the
# three warn-* hooks SIX times across FOUR files — tests/test-hooks.sh (three, all in comments),
# tests/test-derived-counts.sh (one comment), tests/test-install-ownership.sh (a path fixture) and
# tests/test-install-prune.sh (live code, as CUT_HOOK/KEPT_HOOK string literals compared against an
# install listing). NONE of the six executes a hook, which is what makes "executed by zero tests"
# true; an earlier draft of this paragraph said "inside a comment block", which is true of
# tests/test-hooks.sh and false of the tree.
#
#   pre-existing (8) — block-scene-edit, block-meta-edit, guard-project-config, track-edits and
#                      session-brief in tests/test-hooks.sh (session-brief's block there already
#                      runs this exact three-state probe, non-silent baseline included, and
#                      tests/test-surface-references.sh runs it too); block-legacy-input in
#                      tests/test-block-legacy-input.sh; bash-gate in
#                      tests/test-bash-gate-precision.sh (tbg_run_fresh, full PreToolUse envelopes
#                      over a 331-record corpus) and tests/test-hook-large-payload.sh; session-save
#                      in tests/test-state.sh Test 4 against a seeded session-start-time, and in
#                      tests/test-hook-advisory-exit.sh against a Stop envelope.
#   invented (3)     — warn-filename, warn-platform-defines, warn-serialization. Nothing had ever
#                      fed these three an input that makes them do their job.
#   half (1)         — session-restore. tests/test-state.sh Test 5 runs it with NO session file and
#                      asserts exit 0, which is the negative direction only: the hook returns at its
#                      `[ ! -f "$UNITY_SESSION_FILE" ]` guard without reaching anything. The
#                      positive fixture below is new.
#
# So: 3 invented outright, 4 counting session-restore's positive fixture. An earlier draft of this
# paragraph claimed 8 of 12 by counting every hook whose payload was retyped here rather than every
# hook that lacked one — four of those eight already had working payloads elsewhere in tests/, and
# the inflated figure was the headline number the task reported.
select_probe() {
    PAYLOAD=''
    KIND='advisory'
    STATE_FILE=''
    NEEDLE=''
    PROBE_ENV=''
    PROBE_SETUP=''
    case "$1" in
        block-scene-edit)
            KIND='block'
            PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scenes/Main.unity","old_string":"a","new_string":"b"}}'
            # The block's OWN reason (its $MSG, via unity_hook_block), not the static tool menu
            # printed above it. `manage_scene` was the needle until 2026-08-14 and it lives in that
            # menu, so replacing the reason with a placeholder left this file fully green.
            NEEDLE='Direct editing of scene/prefab files corrupts serialized references.'
            ;;
        block-meta-edit)
            KIND='block'
            PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scripts/Player.cs.meta","old_string":"a","new_string":"b"}}'
            NEEDLE='files contain GUIDs that Unity uses to track assets'
            ;;
        block-legacy-input)
            KIND='block'
            # Absolute path under Assets/: the third-party and Editor/Tests exemptions are anchored
            # under Assets/, so a bare relative name would take a different branch.
            PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"/p/Assets/Scripts/A.cs","new_string":"if (Input.GetKey(k)) {}\n"}}'
            # Names the API it found, so a message gutted to a bare 'blocked' reds here.
            NEEDLE='Legacy Input Manager API: Input.GetKey'
            ;;
        guard-project-config)
            KIND='block'
            PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":".editorconfig","old_string":"a","new_string":"b"}}'
            NEEDLE='defines code quality standards for the project'
            ;;
        bash-gate)
            KIND='block'
            # First attempt at a destructive command is denied; the second proceeds. Each probe gets
            # a fresh state dir, so this is always a first attempt.
            PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"rm -rf Library/"}}'
            # The classification, not just the word BLOCKED: this gate's whole value is telling the
            # caller WHICH danger it matched.
            NEEDLE='Classification: unity-dir-wipe'
            ;;
        warn-serialization)
            PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/P.cs","old_string":"[SerializeField] private float _speed;","new_string":"[SerializeField] private float _moveSpeed;"}}'
            # Names the renamed field AND the attribute. This is the hook the whole task exists for.
            NEEDLE="Serialized field '_speed' was renamed without [FormerlySerializedAs]"
            ;;
        warn-filename)
            # The class name and the file name must disagree, and the content must carry a `class`
            # keyword. An Edit fragment with `: MonoBehaviour` and no `class` keyword is the input
            # that used to kill this hook outright — see its own comment at CLASS_NAME.
            PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"Assets/Player.cs","new_string":"public sealed class Enemy : MonoBehaviour { }\n"}}'
            # Both names, so a warning that fires with an empty CLASS_NAME cannot pass.
            NEEDLE="File name 'Player.cs' does not match class name 'Enemy'"
            ;;
        warn-platform-defines)
            # Absolute path under Assets/, for the same reason block-legacy-input's probe is:
            # this hook gained a third-party skip anchored as */Assets/Extensions/* on
            # 2026-08-15, and a relative `Assets/A.cs` exercises a path shape Claude Code never
            # sends. The acting probe has to travel the branch a real payload travels.
            PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"/p/Assets/Scripts/A.cs","new_string":"#if UNITY_PS5\nX();\n#endif\n"}}'
            NEEDLE='Platform-specific code without #else fallback'
            ;;
        track-edits)
            # Writes nothing to stdout or stderr; its whole observable is the edits file.
            STATE_FILE='session-edits.txt'
            PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scripts/Probe.cs"}}'
            # The path it was asked to record, so recording the WRONG path reds. It does NOT prove
            # the path reached the edits file: the haystack includes stdout and stderr, so a
            # track-edits that echoed the path instead of recording it would pass. Measured.
            NEEDLE='Assets/Scripts/Probe.cs'
            ;;
        session-restore)
            # Triggered by pre-existing state, not by its payload. saved_at is generated at run time
            # because the hook drops any session older than UNITY_SESSION_TTL_HOURS (default 4) —
            # a fixed timestamp in this file would start passing vacuously the day it went stale.
            PAYLOAD='{}'
            PROBE_SETUP='jq -n --arg s "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '"'"'{saved_at:$s,branch:"probe-branch",workflow_phase:"Execute",modified_files:["Assets/Scripts/Probe.cs"],last_command:"/unity-test",plan:{description:"probe plan",steps:[{name:"step one",status:"done"}]},verification:{last_iteration:"1"},agent_context:{last_agent:"unity-coder"}}'"'"' > "${UNITY_HOOK_STATE_DIR}/session.json"'
            # Reads a value out of the fixture, so a brief that prints a template with no data reds.
            NEEDLE='Previous branch: probe-branch'
            ;;
        session-brief)
            # Prints the using-kinglet skill body, so it needs to be told where the project is.
            PAYLOAD='{}'
            PROBE_ENV="CLAUDE_PROJECT_DIR=${REPO_DIR}"
            # The skill's own heading. NOT proof that the frontmatter was stripped: the needle is
            # matched against the whole haystack, so a hook that emitted the frontmatter too would
            # still contain this. See the header's `WHAT THE NEEDLE CANNOT SEE`.
            NEEDLE='# Using Kinglet'
            ;;
        session-save)
            STATE_FILE='session.json'
            PAYLOAD='{}'
            # Written into the session file it produces; proves the schema, not just a file.
            NEEDLE='"schema_version"'
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

    # The same three sources as the byte count, as text, so the needle is matched against exactly
    # what was measured. `cat` of a missing state file would be noise, hence the guard.
    PROBE_TEXT="$(cat "${dir}/stdout" "${dir}/stderr" 2>/dev/null || true)"
    if [ -n "${STATE_FILE}" ] && [ -f "${dir}/state/${STATE_FILE}" ]; then
        PROBE_TEXT="${PROBE_TEXT}
$(cat "${dir}/state/${STATE_FILE}" 2>/dev/null || true)"
    fi
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

    # THE NEEDLE FLOOR, and it is the same instrument as the anti-vacuity floor above.
    #
    # `assert_contains` ends in `grep -qF -- "$needle" <<< "$haystack"`, and `grep -qF -- ""`
    # matches ANY input. So a probe branch that forgets its needle does not fail — it passes over
    # every possible output, forever, printing `(needle: )` in a line that reads like a pass.
    # Measured on this file with one needle cleared: 74 pass / 0 fail.
    #
    # `select_probe`'s `*)` branch makes adding a hook require adding a probe BRANCH; nothing in it
    # requires that branch to carry a needle. Without this check the file's defence holds for
    # CHANGING an existing message and fails for ADDING a new hook — the silent-decay shape, in the
    # file whose header argues against it.
    NEEDLE_STATE="present"
    [ -n "$NEEDLE" ] || NEEDLE_STATE="EMPTY"
    assert_eq "present" "$NEEDLE_STATE" \
        "probe for '${HOOK}' carries a non-empty needle (an empty one matches any output at all)"

    # Same derivation _lib.sh uses: basename, uppercased, hyphens to underscores.
    OWN_SWITCH="DISABLE_HOOK_$(printf '%s' "$HOOK" | tr '[:lower:]-' '[:upper:]_')"

    run_probe "$HOOK" ''
    ACT_BYTES="$PROBE_BYTES"
    ACT_RC="$PROBE_RC"
    ACT_TEXT="$PROBE_TEXT"

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

    # ...and responds with ITS OWN message. The byte count above cannot tell the hook's warning
    # from any surviving echo; this can. assert_contains uses a here-string, so there is no
    # early-exiting reader on the write end of a pipe.
    assert_contains "$ACT_TEXT" "$NEEDLE" \
        "${HOOK} emits its own message, not merely output (needle: ${NEEDLE})"

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

    # The execution record. Written only by a probe that ran — it is what the coverage assertion
    # below counts, and it is DELETED with $WORK_DIR at the end of this file. The durable interface
    # for any later task is the `HOOK-PROBE ...` line printed to stdout on the next line, which the
    # runner captures into the suite log.
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$HOOK" "$KIND" "$ACT_BYTES" "$ACT_RC" "$OFF_ALL_BYTES" "$OFF_OWN_BYTES" >> "$PROBE_RECORD"
    echo "  HOOK-PROBE ${HOOK} kind=${KIND} act=${ACT_BYTES}B rc=${ACT_RC} off_all=${OFF_ALL_BYTES}B off_own=${OFF_OWN_BYTES}B"
done

# --- warn-filename's line-46 gate, in the silence direction -----------------
#
# Added 2026-08-15, with the change that rewrote that gate's `(class|struct|interface)\s+NAME\b`
# in POSIX classes — `\s` and `\b` are GNU extensions and .claude/UPSTREAM plans a macOS host
# pass, which is the standard block-legacy-input.sh states at its own LEGACY pattern.
#
# THE LOOP ABOVE CANNOT SEE THIS LINE. Its probe is `class Enemy` in `Player.cs`, chosen so the
# names DISAGREE — which is precisely the input that line 46 must not match. Every assertion in
# this file about warn-filename is about what it says when it warns; nothing asserted that a
# correctly-named file makes it say nothing, so the gate could have been deleted outright and the
# file would have stayed green. That gate is the hook: a file whose class matches its name is the
# overwhelmingly common case, and a hook that warns on all of them is a hook you switch off.
#
# The four `must warn` arms are not decoration either. `[^[:alnum:]_]` replaces a zero-width `\b`
# with a consumed character, and the two ways to get that wrong both END IN SILENCE — drop the
# class and `Player` matches inside `PlayerController`; drop the `_` from it and `Player` matches
# inside `Player_2`. In both cases line 46 swallows a real mismatch and the hook returns 0.
WF_HOOK='warn-filename'

STATE_FILE=''
PROBE_ENV=''
PROBE_SETUP=''

wf_probe() {  # $1 = declaration text — sets PROBE_BYTES / PROBE_RC / PROBE_TEXT
    PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"/p/Assets/Scripts/Player.cs","new_string":"'"$1"'\n"}}'
    run_probe "$WF_HOOK" ''
}

# The non-silent baseline for the zeros below.
wf_probe 'public sealed class Enemy : MonoBehaviour { }'
WF_BASE_BYTES="$PROBE_BYTES"
WF_BASE_VERDICT="silent"
[ "$WF_BASE_BYTES" -gt 0 ] && WF_BASE_VERDICT="warns"
assert_eq "warns" "$WF_BASE_VERDICT" \
    "${WF_HOOK} baseline: a real name mismatch still warns (${WF_BASE_BYTES} B)"

# Silence: the gate matched, so the hook has nothing to say. All three keywords, because they are
# one alternation and an untested branch can be dropped without any assertion moving.
#
# EVERY PAYLOAD OPENS WITH A HELPER TYPE, AND THAT IS THE WHOLE DESIGN OF THIS GROUP. The bare
# `class Player : MonoBehaviour` is silent for TWO independent reasons — line 46 matches, and if
# it did not, the fallback would extract `Player` and compare it to `Player` — so it discriminates
# nothing. Measured: with line 46's pattern mutated so it cannot match at all, a probe built from
# bare declarations stayed at 105 pass / 0 fail, a full green over a deleted gate, which is the
# defect this block was added to close reproduced inside the block itself. A leading
# `class Helper : MonoBehaviour` separates the two: line 46 still matches the file's own type
# wherever it sits, and the fallback — which takes the FIRST `class|struct` token — would report
# `Helper`. That shape is ordinary C#, and it is why warn-filename's 0 warnings over 1417 real
# files is the correct answer rather than a silent one.
for WF_DECL in \
    'public sealed class Helper : MonoBehaviour { }\npublic sealed class Player : MonoBehaviour { }' \
    'public sealed class Helper : MonoBehaviour { }\npublic readonly struct Player { }' \
    'public sealed class Helper : MonoBehaviour { }\npublic interface Player { }'
do
    wf_probe "$WF_DECL"
    assert_eq "0B rc0" "${PROBE_BYTES}B rc${PROBE_RC}" \
        "${WF_HOOK} says nothing about '${WF_DECL}' in Player.cs (baseline ${WF_BASE_BYTES} B)"
done

# Noise it must still make: the consumed boundary has to end the name, on both kinds of character
# that continue a C# identifier.
for WF_DECL in \
    'public sealed class PlayerController : MonoBehaviour { }' \
    'public sealed class Player_2 : MonoBehaviour { }'
do
    wf_probe "$WF_DECL"
    WF_VERDICT="silent"
    [ "$PROBE_BYTES" -gt 0 ] && WF_VERDICT="warns"
    assert_eq "warns" "$WF_VERDICT" \
        "${WF_HOOK} still warns on '${WF_DECL}' in Player.cs — the boundary ends the name (${PROBE_BYTES} B)"
done

# --- warn-platform-defines's third-party skip, probed as a PAIR -------------
#
# Added 2026-08-15 with the skip itself. On a shipping project of 1417 C# files this hook fired
# 4 times and all four were under Assets/Extensions/Feel/ — a vendored asset nobody may edit. It
# now carries the same skip list block-legacy-input.sh has always had.
#
# WHY A PAIR, AND WHY NEITHER HALF SHIPS ALONE. "The Extensions path produced nothing" is
# satisfied by a hook that produces nothing for ANY input — by deleting the hook, by breaking
# its pattern, by an `exit 0` on line 1. It is the passing-by-silence shape this file's header
# is about, and the skip is precisely a change that makes a hook go quiet, so a one-sided probe
# would certify the fix and the accident identically. The first-party arm is the non-silent
# baseline, its byte count is printed beside every zero, and the two are asserted in the same
# block so removing one is a visible deletion rather than a quiet weakening.
#
# The loop's own probe already proves the hook responds and carries its message. What is new
# here is that the response depends on the PATH, which no assertion in this file could see.
TP_HOOK='warn-platform-defines'
TP_BODY='#if UNITY_PS5\nSetup();\n#endif\n'

STATE_FILE=''
PROBE_ENV=''
PROBE_SETUP=''

tp_probe() {  # $1 = absolute file path — sets PROBE_BYTES / PROBE_RC / PROBE_TEXT
    PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"'"$1"'","new_string":"'"$TP_BODY"'"}}'
    run_probe "$TP_HOOK" ''
}

# a) The baseline. First-party code with the same body must still warn — and with the hook's own
#    message, so a surviving stray echo cannot stand in for it.
tp_probe '/p/Assets/Scripts/Boot.cs'
TP_BASE_BYTES="$PROBE_BYTES"
TP_BASE_VERDICT="silent"
[ "$TP_BASE_BYTES" -gt 0 ] && TP_BASE_VERDICT="warns"
assert_eq "warns" "$TP_BASE_VERDICT" \
    "${TP_HOOK} still warns on first-party code after the third-party skip (${TP_BASE_BYTES} B)"
assert_contains "$PROBE_TEXT" 'Platform-specific code without #else fallback' \
    "${TP_HOOK} first-party baseline is the hook's own warning, not stray output"

# b) The skip. Every segment of the list, not just the measured one: a skip list is a union and
#    an untested alternative can be dropped without any assertion moving.
for TP_PATH in \
    /p/Assets/Extensions/Feel/MMTools/Core/MMHelpers/MMDebug.cs \
    /p/Assets/Plugins/Vendor/Thing.cs \
    /p/Assets/ThirdParty/Vendor/Thing.cs \
    /p/Assets/PlayerPrefsEditor/Editor/Prefs.cs \
    /p/Packages/com.vendor.thing/Runtime/Thing.cs \
    /p/Library/PackageCache/com.vendor.thing/Thing.cs
do
    tp_probe "$TP_PATH"
    assert_eq "0B rc0" "${PROBE_BYTES}B rc${PROBE_RC}" \
        "${TP_HOOK} passes over ${TP_PATH#/p/} (first-party baseline ${TP_BASE_BYTES} B)"
done

# c) The four Assets/-anchored entries are ANCHORED, and this is what keeps them so. FILE_PATH is
#    absolute, so an unanchored `*/Plugins/*` would match a checkout kept in an ordinary
#    ~/Projects/Plugins/ directory and switch the hook off for every file in that project at
#    once. block-legacy-input.sh's Editor/Tests skips were re-anchored for exactly this on
#    2026-08-13; the four `*/Assets/…/*` entries inherit the anchoring and now inherit the guard.
for TP_PATH in \
    /home/dev/Plugins/MyGame/Assets/Scripts/Boot.cs \
    /home/dev/Extensions/MyGame/Assets/Scripts/Boot.cs \
    /home/dev/ThirdParty/MyGame/Assets/Scripts/Boot.cs
do
    tp_probe "$TP_PATH"
    TP_ANCHOR_VERDICT="silent"
    [ "$PROBE_BYTES" -gt 0 ] && TP_ANCHOR_VERDICT="warns"
    assert_eq "warns" "$TP_ANCHOR_VERDICT" \
        "${TP_HOOK} still warns when the CHECKOUT sits under ${TP_PATH} (${PROBE_BYTES} B)"
done

# d) A KNOWN HOLE, RECORDED RATHER THAN HIDDEN — the corpus convention in
#    tests/test-bash-gate-precision.sh, applied here.
#
#    `*/Packages/*` and `*/Library/*` are the two entries of the list that are NOT anchored under
#    Assets/, and they cannot be: in a real project those are siblings of Assets/ at the project
#    root, and the hook is given a path with no idea where that root is. The consequence is
#    measured and it is the 2026-08-13 defect still live: a checkout kept in ~/Projects/Packages/
#    or ~/dev/Library/ switches the hook off for every file in it.
#
#    THIS IS INHERITED, NOT INTRODUCED. block-legacy-input.sh has shipped the identical two
#    entries since it was written, and the identical hole: measured on the same paths, it exits 0
#    on a plain `Input.GetKeyDown` under /Users/dev/Projects/Packages/Game/Assets/Scripts/ and
#    under /home/dev/Library/MyGame/Assets/Scripts/, while blocking correctly under
#    /home/dev/Plugins/MyGame/Assets/Scripts/. Copying the list copied the hole, and asserting
#    the current answer is what makes closing it a deliberate edit to this block rather than a
#    silent behaviour change.
for TP_PATH in \
    /Users/dev/Projects/Packages/Game/Assets/Scripts/Boot.cs \
    /home/dev/Library/MyGame/Assets/Scripts/Boot.cs
do
    tp_probe "$TP_PATH"
    assert_eq "0B rc0" "${PROBE_BYTES}B rc${PROBE_RC}" \
        "KNOWN HOLE (inherited): a checkout under ${TP_PATH%%/Assets/*} silences ${TP_HOOK} (baseline ${TP_BASE_BYTES} B)"
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
