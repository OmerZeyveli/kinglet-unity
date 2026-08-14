#!/usr/bin/env bash
# ============================================================================
# test-hooks.sh — Tests for individual hook scripts
# Feeds mock JSON payloads to hooks and verifies exit codes and output.
# ============================================================================

HOOKS_DIR="${REPO_DIR}/.claude/hooks"

# --- Helper: run a hook with a JSON payload ---
run_hook() {
    local hook_script="$1"
    local json_payload="$2"
    local extra_env="${3:-}"

    local exit_code=0
    if [ -n "$extra_env" ]; then
        OUTPUT=$(echo "$json_payload" | env $extra_env bash "$HOOKS_DIR/$hook_script" 2>&1) || exit_code=$?
    else
        OUTPUT=$(echo "$json_payload" | bash "$HOOKS_DIR/$hook_script" 2>&1) || exit_code=$?
    fi
    echo "$exit_code|$OUTPUT"
}

# --- block-scene-edit.sh ---

# Should block .unity file edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scenes/Main.unity","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "block-scene-edit.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "2" "$EXIT_CODE" "block-scene-edit blocks .unity files"

# Should block .prefab file edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Prefabs/Player.prefab","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "block-scene-edit.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "2" "$EXIT_CODE" "block-scene-edit blocks .prefab files"

# Should allow .cs file edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scripts/Player.cs","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "block-scene-edit.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "0" "$EXIT_CODE" "block-scene-edit allows .cs files"

# --- block-meta-edit.sh ---

# Should block .meta file edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scripts/Player.cs.meta","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "block-meta-edit.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "2" "$EXIT_CODE" "block-meta-edit blocks .meta files"

# Should allow non-.meta file edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scripts/Player.cs","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "block-meta-edit.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "0" "$EXIT_CODE" "block-meta-edit allows .cs files"

# --- guard-project-config.sh ---

# Should block .editorconfig edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":".editorconfig","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "guard-project-config.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "2" "$EXIT_CODE" "guard-project-config blocks .editorconfig"

# Should block .ruleset edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/custom.ruleset","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "guard-project-config.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "2" "$EXIT_CODE" "guard-project-config blocks .ruleset files"

# Should block .csproj with NoWarn changes
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assembly.csproj","old_string":"foo","new_string":"<NoWarn>CS0168</NoWarn>"}}'
RESULT=$(run_hook "guard-project-config.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "2" "$EXIT_CODE" "guard-project-config blocks .csproj NoWarn edits"

# Should allow .csproj without analyzer changes
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assembly.csproj","old_string":"foo","new_string":"<TargetFramework>net6.0</TargetFramework>"}}'
RESULT=$(run_hook "guard-project-config.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "0" "$EXIT_CODE" "guard-project-config allows .csproj non-analyzer edits"

# Should allow normal C# file edits
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scripts/Player.cs","old_string":"foo","new_string":"bar"}}'
RESULT=$(run_hook "guard-project-config.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "0" "$EXIT_CODE" "guard-project-config allows .cs files"

# --- track-edits.sh ---

TEMP_STATE="/tmp/unity-claude-hooks"

# Should exit 0 and track the edit
rm -f "${TEMP_STATE}/session-edits.txt"
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scripts/Player.cs","old_string":"a","new_string":"b"}}'
RESULT=$(run_hook "track-edits.sh" "$PAYLOAD")
EXIT_CODE="${RESULT%%|*}"
assert_eq "0" "$EXIT_CODE" "track-edits exits 0"

# track-reads.sh, cost-tracker.sh and notify.sh were asserted here until 2026-08-13 and are gone:
# the first two declared HOOK_PROFILE_LEVEL="strict" while nothing sets UNITY_HOOK_PROFILE, so their
# assertions were measuring the profile gate rather than the hook, and notify.sh was opt-in behind
# UNITY_NOTIFY_ENABLED. Their absence is enforced by provenance-skip.tsv, not by this file.
#
# What this file cannot see, and never could: whether a hook is registered on the right event, or
# registered at all. tests/test-derived-counts.sh owns that set identity.

# ============================================================================
# THE KILL SWITCH REACHES EVERY HOOK -- derived from the directory, not from a list.
#
# `DISABLE_UNITY_HOOKS=1` is sold as "bypass ALL hooks" in five shipped places. It was false for
# fifteen months: `session-brief.sh` sourced nothing, so it honoured neither switch, and it is the
# hook that injects the whole `using-kinglet` skill into every session -- the most likely reason
# anyone sets the variable. Nothing here or anywhere else noticed, because every guard read the
# hooks that DO source `_lib.sh`.
#
# There are exactly two legal mechanisms and this asserts the union, per hook, by name:
#   (a) source `_lib.sh`, which checks both switches; or
#   (b) check both switches inline.
# A new hook that does neither is named in the failure, which is the shape the original defect had.
#
# MATCHED ON CODE, NOT ON THE NAME. Comment lines are stripped before the match, and the inline arm
# requires the parameter-expansion form rather than the bare word. `session-brief.sh`'s own header
# now explains the switches at length, so a needle of `DISABLE_UNITY_HOOKS` alone would be satisfied
# by prose describing a check that had been deleted -- a probe whose subject can satisfy it by
# talking about itself.
#
# AND THE STRUCTURAL SWEEP ALONE WAS COVERED BACKWARDS, WHICH IS WHY THERE ARE TWO BEHAVIOURAL
# PROBES BELOW. Its first version proved the mechanism with ONE user -- `session-brief.sh`, the
# inline one -- and took the eleven `_lib.sh` sourcers on faith, because seeing a `source` line was
# enough to `continue`. Measured: delete both `if` blocks from `_lib.sh`'s kill-switch section and
# `block-meta-edit.sh` still BLOCKS, rc=2, with `DISABLE_UNITY_HOOKS=1` set -- and this file stayed
# fully green, including the assertion by name. Eleven of twelve hooks were vouched for by a check
# that could not see the thing they all depend on.
#
# The needles are also satisfiable by EXCESS. A hook honouring neither switch but carrying both
# strings as inert code -- `MSG="ignores ${DISABLE_UNITY_HOOKS:-} and DISABLE_HOOK_ZZ entirely"` --
# passed the structural sweep while running to completion with the switch set. Stripping comments
# anticipates the prose version of that; it does not anticipate the dead-code version, which is what
# a half-finished copy-paste produces.
#
# So the structural sweep is now a FIRST FILTER, and the load is carried by:
#   * one behavioural probe of a `_lib.sh` sourcer, which is what makes the eleven mean anything; and
#   * a SET identity between the hooks that do not source `_lib.sh` and the hooks this file probes
#     behaviourally. A new inline hook reds here until someone writes its probe, which is the only
#     way an inline copy of the switch logic can be held to the behaviour rather than to a string.
#
# WHAT THE CLASSIFIER STILL CANNOT SEE, and the set identity above now depends on it. It matches the
# `source` STATEMENT, not whether that statement RUNS. Wrap a hook's source line in a never-true
# conditional and it is still classified as a sourcer: it stays out of the inline-derived set, so
# nothing probes it, and it is not the hook probe 1 uses, so nothing else covers it either.
# MEASURED ON `warn-filename.sh` with `if [ "1" = "2" ]; then source …; fi`, against a payload that
# actually triggers it -- `Assets/Player.cs` carrying `public class Enemy : MonoBehaviour`:
#
#                  no switch     DISABLE_UNITY_HOOKS=1   DISABLE_HOOK_WARN_FILENAME=1
#     pristine     rc=0, 296 B   rc=0, 0 B               rc=0, 0 B
#     mutant       rc=0, 296 B   rc=0, 296 B             rc=0, 296 B
#
# THE HOOK IS NOT LOST. IT STILL WARNS. WHAT IS LOST IS THE SWITCH: a user who sets
# `DISABLE_UNITY_HOOKS=1` gets hook output anyway, which is the direction that matters. This comment
# recorded the exact opposite until 2026-08-14 -- "rc=0 and ZERO BYTES of output" in all three
# states, therefore "WHAT IS LOST IS THE HOOK, NOT THE SWITCH" -- and the inference built on it fell
# with it. A switch-shaped probe DOES catch this: against a non-silent baseline the mutant fails to
# go silent.
#
# THE ZERO-BYTES READING CAN ONLY HAVE COME FROM A PAYLOAD THAT PRODUCED NO OUTPUT ON THE PRISTINE
# HOOK EITHER -- comparing silence with silence, which is the error this file warns against twice,
# committed in the paragraph explaining why the error is unavoidable. The rule that pays for it: A
# PROBE WHOSE PASSING CONDITION IS SILENCE MUST FIRST PROVE ITS OWN BASELINE IS NOT SILENT.
#
# ============================================================================
# WHERE PER-HOOK COVERAGE LIVES, AND HOW TO RE-DERIVE IT WITHOUT ASKING THIS FILE
#
# Probe 1 below is the acting-then-silenced proof for ONE hook. The per-hook positive for the rest
# is not in this file and is not meant to be: `tests/test-hook-behaviour.sh` runs a three-state
# probe -- acts / `DISABLE_UNITY_HOOKS=1` / `DISABLE_HOOK_<NAME>=1` -- against every hook
# `.claude/settings.json` registers, matches each acting run against a needle from that hook's own
# message, and prints the acting byte count beside both zeros. It asserts its own completeness at
# `every registered hook was probed by execution`. Deleting that file is not silent either: it
# carries a `provenance.tsv` row, and a row without a file fails `scripts/check-provenance.sh`.
#
# THIS PARAGRAPH USED TO RECORD A DIFFERENT MEASUREMENT, WITH A RECIPE THAT INVERTED ITSELF. It
# said TWO HOOKS ARE NAMED BY NO TEST FILE AT ALL -- `warn-platform-defines.sh` and
# `warn-serialization.sh` -- and printed this, telling the reader to trust the command over the
# comment:
#
#     for h in .claude/hooks/*.sh; do b=$(basename "$h"); [ "$b" = _lib.sh ] && continue
#       grep -lq "$b" tests/*.sh 2>/dev/null || echo "$b"; done
#
# THE RECIPE GREPS `tests/` FOR HOOK NAMES, AND THIS FILE IS UNDER `tests/` AND NAMES THEM. Writing
# the finding down is precisely what the command matches, so the command was switched off by the act
# of recording its result. Measured 2026-08-15 at that exact wording, under /usr/bin/grep 3.11 and
# under the interactive ugrep 7.5.0 alike: it prints NOTHING. Drop this file and
# `tests/test-hook-behaviour.sh` from its scope and the same command prints THREE --
# `block-meta-edit.sh`, `guard-project-config.sh`, `warn-serialization.sh` -- so the sentence was
# also wrong about which hooks when it was written. A derivation whose scope includes the file
# recording its result is not a derivation.
#
# THE REPLACEMENT KEYS ON EXECUTION AND EXCLUDES NOTHING. There is no path to exclude, because the
# evidence is a line only a probe that RAN can emit; an exclusion keyed on the recording's own name
# would just move the defect down one level, and on this host it would not even work -- `grep -r`
# prints `path` under ugrep where GNU prints `./path`, so a `^\./` exclusion excludes nothing and
# inflates the count instead of erroring. Nothing this comment says can add or remove a
# `HOOK-PROBE` record. Strip ANSI first: the runner colours its headers.
#
#     bash tests/run-tests.sh 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g' > /tmp/suite.log
#     awk '$1 == "HOOK-PROBE" { print $2 }' /tmp/suite.log | sort -u          > /tmp/probed
#     jq -r '.hooks|to_entries[]|.value[]|.hooks[].command' .claude/settings.json \
#       | sed -e 's#.*/##' -e 's#\.sh$##' | sort -u                           > /tmp/registered
#     comm -13 /tmp/probed /tmp/registered      # registered, never executed by a probe
#
# `$1 ==` rather than a substring match: the emitted record opens its first field with the token and
# nothing else in a suite log does -- an assertion message that mentions it is preceded by the
# runner's own marker and cannot become field 1. Verified on the green suite of 2026-08-15: 12
# occurrences of the token in the whole log, all 12 in field 1, `comm` empty.
#
# THE REGISTERED SET COMES FROM `settings.json`, NOT FROM A HAND LIST, and the third set --
# `.claude/hooks/*.sh` less `_lib.sh` -- must agree with it. That identity is asserted in
# `tests/test-hook-behaviour.sh` rather than duplicated here, so a hook that exists on disk and is
# registered nowhere reds there instead of passing unnoticed in both files. All three sets were 12
# on 2026-08-15; derive them, do not quote this line.
# ============================================================================
KS_BAD=""
KS_SEEN=0
#
# `[ -f ]` before anything else, and it is not defensive noise: `nullglob` is unset here, so an empty
# or renamed hooks directory leaves the literal `*.sh` in the loop variable. Measured with the
# directory emptied, WITHOUT this line: KS_SEEN read 1, the anti-vacuity assertion below passed, and
# the guard reported a hook named `*.sh` honouring nothing. The class was still caught, by the wrong
# assertion, with a nonsense name -- which is the failure mode the anti-vacuity check exists to make
# legible.
for ks_h in "$HOOKS_DIR"/*.sh; do
    [ -f "$ks_h" ] || continue
    ks_b="$(basename "$ks_h")"
    [ "$ks_b" = "_lib.sh" ] && continue
    KS_SEEN=$((KS_SEEN + 1))
    ks_code=$(awk '!/^[[:space:]]*#/' "$ks_h")
    ks_lib=no; ks_global=no; ks_perhook=no
    grep -qE 'source[[:space:]]+"?\$\{?SCRIPT_DIR\}?/_lib\.sh"?' <<< "$ks_code" && ks_lib=yes
    grep -qF 'DISABLE_UNITY_HOOKS:-' <<< "$ks_code" && ks_global=yes
    grep -qF 'DISABLE_HOOK_' <<< "$ks_code" && ks_perhook=yes
    if [ "$ks_lib" = yes ]; then
        continue
    fi
    if [ "$ks_global" = yes ] && [ "$ks_perhook" = yes ]; then
        continue
    fi
    KS_BAD="${KS_BAD}${ks_b} (sources _lib.sh: $ks_lib, inline global: $ks_global, inline per-hook: $ks_perhook)"$'\n'
done

# Anti-vacuity first: run this against a tree with no hooks and the loop body never executes, so
# KS_BAD is empty and the assertion below passes having read nothing.
assert_eq "yes" "$([ "$KS_SEEN" -ge 1 ] && echo yes || echo no)" \
    "the kill-switch sweep found hook files to read ($KS_SEEN)"

if [ -n "$KS_BAD" ]; then
    printf '%s' "$KS_BAD" | sed 's|^|     honours neither kill switch by either mechanism: |'
fi
assert_eq "0" "$(printf '%s' "$KS_BAD" | grep -c . || true)" \
    "every hook honours DISABLE_UNITY_HOOKS and DISABLE_HOOK_<NAME>, by _lib.sh or inline"

# --- Behavioural probe 1: a `_lib.sh` SOURCER. ---
#
# This is the one that makes the structural `continue` above mean anything. `block-meta-edit.sh` is
# the representative: it blocks on a payload this file already uses, so the baseline is rc=2 and the
# probe is not comparing two silences. With the switch set it must reach exit 0.
KS_META_PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"Assets/Scripts/Player.cs.meta","old_string":"a","new_string":"b"}}'
KS_META_BASE="$(run_hook "block-meta-edit.sh" "$KS_META_PAYLOAD")"
KS_META_OFF="$(run_hook "block-meta-edit.sh" "$KS_META_PAYLOAD" "DISABLE_UNITY_HOOKS=1")"
KS_META_ONE="$(run_hook "block-meta-edit.sh" "$KS_META_PAYLOAD" "DISABLE_HOOK_BLOCK_META_EDIT=1")"
assert_eq "2" "${KS_META_BASE%%|*}" \
    "block-meta-edit blocks with no switch set — the two probes below are not measuring an inert hook"
assert_eq "0" "${KS_META_OFF%%|*}" \
    "DISABLE_UNITY_HOOKS=1 reaches a _lib.sh sourcer (block-meta-edit stops blocking)"
assert_eq "0" "${KS_META_ONE%%|*}" \
    "DISABLE_HOOK_BLOCK_META_EDIT=1 reaches a _lib.sh sourcer"

# --- Behavioural probe 2: every hook that does NOT source `_lib.sh`, as a set. ---
#
# The inline arm cannot be trusted to a string match, so each non-sourcer must be probed by name in
# this file, and the two sets are compared. Adding an inline hook without a probe reds here.
KS_INLINE_DERIVED="$(
  for ks_h in "$HOOKS_DIR"/*.sh; do
    [ -f "$ks_h" ] || continue
    ks_b="$(basename "$ks_h")"
    [ "$ks_b" = "_lib.sh" ] && continue
    ks_code="$(awk '!/^[[:space:]]*#/' "$ks_h")"
    grep -qE 'source[[:space:]]+"?\$\{?SCRIPT_DIR\}?/_lib\.sh"?' <<< "$ks_code" || printf '%s\n' "${ks_b%.sh}"
  done | sort
)"
KS_INLINE_PROBED="session-brief"
assert_eq "$KS_INLINE_DERIVED" "$KS_INLINE_PROBED" \
    "every hook that does not source _lib.sh is probed behaviourally below, and no other"

# `session-brief.sh` prints unconditionally when the skill file exists, so the baseline is non-empty
# and the probe is not measuring silence twice.
KS_BASE=$(CLAUDE_PROJECT_DIR="$REPO_DIR" bash "$HOOKS_DIR/session-brief.sh" 2>&1 | grep -c . || true)
KS_OFF_ALL=$(CLAUDE_PROJECT_DIR="$REPO_DIR" DISABLE_UNITY_HOOKS=1 bash "$HOOKS_DIR/session-brief.sh" 2>&1 | grep -c . || true)
KS_OFF_ONE=$(CLAUDE_PROJECT_DIR="$REPO_DIR" DISABLE_HOOK_SESSION_BRIEF=1 bash "$HOOKS_DIR/session-brief.sh" 2>&1 | grep -c . || true)

assert_eq "yes" "$([ "$KS_BASE" -ge 1 ] && echo yes || echo no)" \
    "session-brief prints the brief with no switch set ($KS_BASE lines) — the probe below is not comparing silence with silence"
assert_eq "0" "$KS_OFF_ALL" "DISABLE_UNITY_HOOKS=1 silences session-brief"
assert_eq "0" "$KS_OFF_ONE" "DISABLE_HOOK_SESSION_BRIEF=1 silences session-brief"
