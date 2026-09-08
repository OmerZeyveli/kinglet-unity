#!/usr/bin/env bash
# ============================================================================
# test-codex-shim.sh — guards scripts/codex-hook-shim.sh
#
# SELF-CONTAINED: defines its own helpers and sets `set -euo pipefail`, so
# `bash tests/test-codex-shim.sh` is a valid way to run it. (A runner-provided
# file run standalone exits 0 having asserted nothing; this one does not.)
#
# ----------------------------------------------------------------------------
# WHAT IS BEING GUARDED
#
# Codex fires Kinglet's hooks and Claude Code's matchers match, but Codex's file
# tool is `apply_patch` and its `tool_input` carries one key — `command`, a patch
# envelope — where the hooks read `file_path` / `content` / `new_string` /
# `old_string`. Eight of the nine tool-event hooks therefore match, run, and do
# nothing. `scripts/codex-hook-shim.sh` normalises the envelope into the shape
# the hooks already read.
#
# ----------------------------------------------------------------------------
# THE MEASUREMENT DISCIPLINE, WHICH IS THE POINT OF THIS FILE
#
# Every hook is measured against ITS OWN paired controls, never against a
# sibling's result. Four runs per hook:
#
#   control  — a Claude-shaped payload, straight into the hook. This is what
#              "acting" MEANS for this hook. If it does not act, the case is
#              vacuous and the file fails LOUDLY rather than scoring the rest.
#              A control lacking its trigger is reported, not scored.
#   raw      — the real Codex payload, straight into the hook. Records whether
#              the shim is still load-bearing for this hook.
#   shim     — the real Codex payload, through the shim. Must act like `control`.
#   negative — a Codex payload WITHOUT the trigger, through the shim. Must NOT
#              act. Without this, "the shim blocks everything" passes every
#              positive assertion in the file.
#
# `track-edits` is why the criterion is not a byte count: it writes no output in
# either direction and its only observable is a state file. Task 2's review
# established that a byte-count comparison misclassifies it as working.
# ============================================================================

set -euo pipefail

TESTS_RUN=0
TESTS_FAILED=0

# `PASS:` / `FAIL:` and not a tick, because the runner tallies THOSE TOKENS out of
# each file's output and a tick is invisible to it. Self-contained siblings
# (tests/test-templates.sh, tests/test-rule-applicability.sh) use this spelling
# for the same reason. A file that reports in its own vocabulary still turns the
# suite red when it exits non-zero — the runner adds a failure for any file that
# "exited N without reporting a failure" — but its assertions never reach the
# `Total:` line, and Total is the number a reader compares between runs. Written
# in ticks first, every assertion in this file moved that total by zero.
#
# NO COUNT IS WRITTEN IN THAT SENTENCE, AND THAT IS THE REPAIR. It read "this
# file's 100 assertions" until 2026-08-17, in the present possessive, against a
# file that emits half again as many now — a pinned reading of a live quantity,
# wearing the grammar of a live one. The argument needs the fact that the total
# did not move, not the size of what failed to move it. Deleting the numeral is
# the only fix that cannot go stale a second time; where a figure here is
# genuinely pinned, date it and put the verb in the past, as the census
# paragraph in tests/test-bash32-compat.sh does.
pass() { TESTS_RUN=$((TESTS_RUN + 1)); printf '  PASS: %s\n' "$1"; }
fail() {
  TESTS_RUN=$((TESTS_RUN + 1)); TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '  FAIL: %s\n' "$1"
}
assert_eq() {
  if [ "$1" = "$2" ]; then pass "$3"; else
    fail "$3"; printf '      expected: %s\n      actual:   %s\n' "$1" "$2"
  fi
}

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/.." && pwd)"
SHIM="$ROOT/scripts/codex-hook-shim.sh"
HOOKS="$ROOT/.claude/hooks"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kinglet-codex-shim-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PROJ="$WORK/proj"
STATE="$WORK/state"
mkdir -p "$PROJ/Assets/Scripts" "$PROJ/Assets/Scenes" "$STATE"

# Hooks must not reach the repository's own state directory, and no kill switch
# may be inherited from the caller's environment — either would make every
# assertion below vacuous in a way that reads as green.
export UNITY_HOOK_STATE_DIR="$STATE"
unset DISABLE_UNITY_HOOKS UNITY_HOOK_MODE UNITY_HOOK_PROFILE 2>/dev/null || true

echo "--- codex shim: it exists and is executable ---"
assert_eq "yes" "$([ -f "$SHIM" ] && echo yes || echo no)" "scripts/codex-hook-shim.sh exists"
assert_eq "yes" "$([ -x "$SHIM" ] && echo yes || echo no)" "scripts/codex-hook-shim.sh is executable"

# --- FIRST, BECAUSE EVERY LATER ASSERTION DEPENDS ON IT BEING TRUE -----------
#
# Descriptor 9 is a dup of the caller's stderr, and killing the watchdog subshell
# does NOT kill the `sleep` it is blocked in. If that orphan inherits descriptor
# 9 it holds the CALLER'S pipe open, so a caller reading the shim through a pipe
# — which is how Codex reads it, and how almost every assertion below captures it
# — waits the full watchdog period on EVERY invocation, allow or refuse.
#
# This sits at the top because the failure is not localised: it makes the whole
# file take minutes and be killed by a harness timeout, which reports "timed out"
# rather than naming the defect. One second here says what is wrong.
SPEED_HOOK="$WORK/speed-hook.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SPEED_HOOK"; chmod +x "$SPEED_HOOK"
SPEED_PAYLOAD='{"tool_name":"apply_patch","cwd":"/proj","tool_input":{"command":"*** Begin Patch\n*** Add File: Assets/X.cs\n+class X {}\n*** End Patch"}}'
SPEED_START=$(date +%s)
SPEED_OUT="$(printf '%s' "$SPEED_PAYLOAD" | bash "$SHIM" --hook "$SPEED_HOOK" --timeout 12 2>&1)" || true
SPEED_END=$(date +%s)
SPEED_ELAPSED=$((SPEED_END - SPEED_START))
assert_eq "yes" "$([ "$SPEED_ELAPSED" -lt 6 ] && echo yes || echo no)" \
  "the shim releases the caller's pipe when the hook exits (${SPEED_ELAPSED}s under a 12s watchdog), rather than when its own killer expires"
assert_eq "" "$SPEED_OUT" "an allowed call writes nothing at all"

# ============================================================================
# 1. FAIL-CLOSED
#
# Codex's measured block contract: exit 2 with at least one byte on stderr, or
# exit 0 with a `decision:block` JSON object carrying a non-empty reason.
# EVERYTHING else — exit 2 in silence, exit 1 with a message, plain text on
# stdout, malformed JSON, an empty reason — allows the call and logs nothing
# anywhere, not even under RUST_LOG=debug.
#
# So the ordinary bash death is the dangerous one: under `set -e`, or on an
# unbound variable, a script exits non-zero but NOT 2, which Codex reads as an
# unlogged allow. A shim that dies on a malformed envelope fails OPEN, silently,
# forever. These assertions are the ones that catch that.
#
# THE CRITERION IS BOTH HALVES: exit 2 AND non-empty stderr. Asserting the exit
# code alone would pass a silent refusal, which is an allow.
# ============================================================================
echo "--- codex shim: it fails closed on every unreadable payload ---"

refuses() { # $1 label, $2 payload, rest: args
  local label="$1"; shift
  local payload="$1"; shift
  local err rc
  err="$(printf '%s' "$payload" | bash "$SHIM" "$@" 2>&1 >/dev/null)" && rc=0 || rc=$?
  if [ "$rc" -eq 2 ] && [ -n "$err" ]; then
    pass "refused (exit 2 + stderr): $label"
  else
    fail "did NOT fail closed: $label (exit $rc, ${#err} bytes on stderr)"
    printf '      under Codex this shape ALLOWS the call and reports nothing.\n'
  fi
}

PATCH_OK='{"tool_name":"apply_patch","cwd":"/proj","tool_input":{"command":"*** Begin Patch\n*** Add File: Assets/X.cs\n+class X {}\n*** End Patch"}}'

refuses "empty stdin"                    ''                                                                        --hook block-scene-edit
refuses "not JSON at all"                'this is not json {{{'                                                    --hook block-scene-edit
refuses "truncated JSON"                 '{"tool_name":"apply_patch","tool_inp'                                    --hook block-scene-edit
refuses "JSON array, not an object"      '[1,2,3]'                                                                 --hook block-scene-edit
refuses "JSON null"                      'null'                                                                    --hook block-scene-edit
refuses "apply_patch with no envelope"   '{"tool_name":"apply_patch","cwd":"/p","tool_input":{"command":"rm -rf /"}}' --hook block-scene-edit
refuses "apply_patch with no command"    '{"tool_name":"apply_patch","cwd":"/p","tool_input":{}}'                  --hook block-scene-edit
refuses "envelope naming no file"        '{"tool_name":"apply_patch","cwd":"/p","tool_input":{"command":"*** Begin Patch\n+stray\n*** End Patch"}}' --hook block-scene-edit
refuses "tool_input is a string"         '{"tool_name":"apply_patch","cwd":"/p","tool_input":"oops"}'              --hook block-scene-edit
refuses "no --hook named"                "$PATCH_OK"
refuses "--hook names a missing file"    "$PATCH_OK"                                                               --hook no-such-hook-anywhere
refuses "--hook with no value"           "$PATCH_OK"                                                               --hook
refuses "an unknown flag"                "$PATCH_OK"                                                               --hook block-scene-edit --bogus-flag
refuses "a non-numeric --timeout"        "$PATCH_OK"                                                               --hook block-scene-edit --timeout later

# --- The wrapped hook itself misbehaving. ---
#
# Each of these is a status Codex reads as an ALLOW. The shim converts them.
BROKEN="$WORK/broken"; mkdir -p "$BROKEN"
printf '#!/usr/bin/env bash\nexit 1\n'                                  > "$BROKEN/exit1.sh"
printf '#!/usr/bin/env bash\nexit 2\n'                                  > "$BROKEN/exit2silent.sh"
printf '#!/usr/bin/env bash\nexit 127\n'                                > "$BROKEN/exit127.sh"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho "$NOPE_UNSET"\n'   > "$BROKEN/unbound.sh"
printf '#!/usr/bin/env bash\nsleep 45\n'                                > "$BROKEN/hang.sh"
chmod +x "$BROKEN"/*.sh

# Codex's OTHER legal block protocol: a JSON object on stdout with
# decision:block, exit status 0. No Kinglet hook uses it, but a wrapper that
# collected it as advisory text would convert a future hook's block into an allow
# with a note attached. The empty-reason arm matters too: Codex measurably
# ignores that shape and says nothing, so forwarding it would be a silent allow.
printf '#!/usr/bin/env bash\nprintf %%s %s\n' \
  "'{\"decision\":\"block\",\"reason\":\"probe refuses via JSON\"}'" > "$BROKEN/jsonblock.sh"
printf '#!/usr/bin/env bash\nprintf %%s %s\n' \
  "'{\"decision\":\"block\",\"reason\":\"\"}'" > "$BROKEN/jsonblockempty.sh"
chmod +x "$BROKEN/jsonblock.sh" "$BROKEN/jsonblockempty.sh"

refuses "a wrapped hook that exits 1"                "$PATCH_OK" --hook "$BROKEN/exit1.sh"
refuses "a wrapped hook blocking via decision:block JSON" "$PATCH_OK" --hook "$BROKEN/jsonblock.sh"
refuses "a decision:block with an EMPTY reason"      "$PATCH_OK" --hook "$BROKEN/jsonblockempty.sh"
refuses "a wrapped hook that exits 2 in SILENCE"     "$PATCH_OK" --hook "$BROKEN/exit2silent.sh"
refuses "a wrapped hook that exits 127"              "$PATCH_OK" --hook "$BROKEN/exit127.sh"
refuses "a wrapped hook killed by set -u"            "$PATCH_OK" --hook "$BROKEN/unbound.sh"

# The watchdog. Kinglet's timeouts are declared in MILLISECONDS in
# settings.json and Codex reads that field as SECONDS, so an unconverted 3000
# is a fifty-minute ceiling. This shim does not own that file, so it carries its
# own — and expiry must REFUSE, because a gate that did not finish has approved
# nothing.
HANG_START=$(date +%s)
refuses "a wrapped hook that hangs (watchdog)"       "$PATCH_OK" --hook "$BROKEN/hang.sh" --timeout 2
HANG_END=$(date +%s)
HANG_ELAPSED=$((HANG_END - HANG_START))
assert_eq "yes" "$([ "$HANG_ELAPSED" -lt 30 ] && echo yes || echo no)" \
  "the watchdog cut a 45s hook short (elapsed ${HANG_ELAPSED}s, ceiling 2s) rather than waiting it out"

# jq absent. Every Kinglet hook needs jq, so a tree without it has no gate under
# either client — but the shim must still refuse rather than wave the call through.
NOJQ="$WORK/nojq"; mkdir -p "$NOJQ"
for nj in bash cat mktemp awk basename sleep rm dirname; do
  nj_p="$(command -v "$nj" 2>/dev/null || true)"
  [ -n "$nj_p" ] && ln -sf "$nj_p" "$NOJQ/$nj"
done
if [ -x "$NOJQ/bash" ]; then
  nojq_err="$(printf '%s' "$PATCH_OK" \
    | env -i PATH="$NOJQ" UNITY_HOOK_STATE_DIR="$STATE" "$NOJQ/bash" "$SHIM" --hook block-scene-edit 2>&1 >/dev/null)" \
    && nojq_rc=0 || nojq_rc=$?
  if [ "$nojq_rc" -eq 2 ] && [ -n "$nojq_err" ]; then
    pass "refused (exit 2 + stderr): jq missing from PATH"
  else
    fail "did NOT fail closed with jq missing (exit $nojq_rc, ${#nojq_err} bytes)"
  fi
else
  fail "could not build a jq-free PATH to probe with — the jq-missing case went unmeasured"
fi

# ============================================================================
# 2. PER-HOOK, WITH PAIRED CONTROLS
# ============================================================================

# run_direct / run_shim record three observables: exit code, output bytes
# (stdout+stderr together — the blockers write stderr, the advisory route writes
# stdout), and lines added to the edit-tracking state file. The third is what
# makes track-edits measurable at all.
RC=0; BYTES=0; DELTA=0; OUT=""

# THE FOUR RUNS MUST BE INDEPENDENT, AND ONE HOOK MAKES THAT AN ACTIVE STEP.
# bash-gate.sh is deliberately not idempotent: it blocks the FIRST attempt at a
# command it cannot classify, records the command's hash in bash-gate-denied.txt,
# and ALLOWS the byte-identical retry — that is its documented contract, not a
# defect. Left alone, the control run would block and the three runs after it
# would sail through, and the file would report the shim as broken for the one
# hook that never needed it. Nothing else in the state directory is cleared:
# session-edits.txt is track-edits' only observable and the delta below is what
# measures it.
reset_run_state() { rm -f "$STATE/bash-gate-denied.txt" 2>/dev/null || true; }

edit_lines() {
  if [ -f "$STATE/session-edits.txt" ]; then wc -l < "$STATE/session-edits.txt"; else echo 0; fi
}

observe() { # "$@" = command to run, payload on $PAYLOAD_FILE
  local before after
  reset_run_state
  before=$(edit_lines)
  OUT="$("$@" < "$PAYLOAD_FILE" 2>&1)" && RC=0 || RC=$?
  BYTES=${#OUT}
  after=$(edit_lines)
  DELTA=$((after - before))
}

# "Acted" is the criterion codex-facts.md used: a non-zero exit, ANY output, or
# ANY state written. A hook that does all three acted; a hook that does none did
# not.
acted() { if [ "$RC" -ne 0 ] || [ "$BYTES" -gt 0 ] || [ "$DELTA" -gt 0 ]; then echo yes; else echo no; fi; }

PAYLOAD_FILE="$WORK/payload.json"
write_payload() { printf '%s' "$1" > "$PAYLOAD_FILE"; }

# One hook case. Arguments:
#   1 hook name
#   2 claude-shaped trigger payload   (control)
#   3 codex apply_patch trigger       (raw + shim)
#   4 codex apply_patch NON-trigger   (negative)
#   5 expected exit code when acting  (2 = blocks, 0 = advisory)
#   6 "loadbearing" | "survives"      — is the raw hook inert on a Codex payload?
check_hook() {
  local name="$1" claude_p="$2" codex_p="$3" codex_neg="$4" want_rc="$5" raw_kind="$6"
  local hook="$HOOKS/$name.sh"
  local c_rc c_bytes c_delta c_acted
  local r_acted
  local s_rc s_bytes s_delta s_acted s_out
  local n_acted

  echo "--- codex shim: $name ---"

  # -- control: does the hook act at all, on the shape Claude Code sends? --
  write_payload "$claude_p"; observe bash "$hook"
  c_rc=$RC; c_bytes=$BYTES; c_delta=$DELTA; c_acted="$(acted)"

  # ANTI-VACUITY, FIRST. A control that does not act cannot score anything, and
  # reporting it as a hook that "works under Codex" is the misclassification this
  # discipline exists to prevent. Fail loudly here instead.
  if [ "$c_acted" != "yes" ]; then
    fail "$name: the Claude-shaped CONTROL did not act (exit $c_rc, $c_bytes bytes, $c_delta state lines) — this case is VACUOUS and scores nothing"
    printf 'CODEX-SHIM-PROBE %s control=VACUOUS raw=- shim=- negative=-\n' "$name"
    return 0
  fi
  assert_eq "$want_rc" "$c_rc" "$name: control acts as expected on a Claude-shaped payload (exit $c_rc, $c_bytes bytes, $c_delta state lines)"

  # -- raw: the real Codex payload, straight in. --
  write_payload "$codex_p"; observe bash "$hook"
  r_acted="$(acted)"
  if [ "$raw_kind" = "loadbearing" ]; then
    assert_eq "no" "$r_acted" "$name: is still INERT on a raw Codex payload — the shim is load-bearing for it"
  else
    assert_eq "yes" "$r_acted" "$name: reads Codex's payload unaided (exit $RC, $BYTES bytes) — it never needed the shim"
  fi

  # -- shim: the same Codex payload, normalised. --
  write_payload "$codex_p"; observe bash "$SHIM" --hook "$hook"
  s_rc=$RC; s_bytes=$BYTES; s_delta=$DELTA; s_acted="$(acted)"; s_out="$OUT"
  assert_eq "yes" "$s_acted" "$name: ACTS through the shim on a real Codex apply_patch payload"
  assert_eq "$want_rc" "$s_rc" "$name: exits $want_rc through the shim, matching its own control"

  # A blocker must carry a reason: exit 2 with no bytes is a silent ALLOW.
  if [ "$want_rc" = "2" ]; then
    assert_eq "yes" "$([ "$s_bytes" -gt 0 ] && echo yes || echo no)" \
      "$name: writes a reason with its refusal ($s_bytes bytes) — a silent exit 2 would be an allow"
  fi

  # -- negative: same route, trigger removed. --
  write_payload "$codex_neg"; observe bash "$SHIM" --hook "$hook"
  n_acted="$(acted)"
  assert_eq "no" "$n_acted" \
    "$name: does NOT act through the shim when the trigger is absent (exit $RC, $BYTES bytes, $DELTA state lines)"

  printf 'CODEX-SHIM-PROBE %s control=rc%s/%sB/%sL raw=%s shim=rc%s/%sB/%sL negative=%s\n' \
    "$name" "$c_rc" "$c_bytes" "$c_delta" "$r_acted" "$s_rc" "$s_bytes" "$s_delta" "$n_acted"
}

CWD="$PROJ"

# --- block-scene-edit: direct edits to .unity / .prefab corrupt references ---
check_hook block-scene-edit \
  "{\"tool_name\":\"Edit\",\"cwd\":\"$CWD\",\"tool_input\":{\"file_path\":\"$CWD/Assets/Scenes/Main.unity\",\"old_string\":\"  m_Name: Main\",\"new_string\":\"  m_Name: Controlled\"}}" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Update File: Assets/Scenes/Main.unity\n@@\n-  m_Name: Main\n+  m_Name: Controlled\n*** End Patch\"}}" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Update File: Assets/Scripts/Harmless.txt\n@@\n-a\n+b\n*** End Patch\"}}" \
  2 loadbearing

# --- block-meta-edit: .meta files carry the GUIDs every reference resolves through ---
check_hook block-meta-edit \
  "{\"tool_name\":\"Edit\",\"cwd\":\"$CWD\",\"tool_input\":{\"file_path\":\"$CWD/Assets/Scripts/Player.cs.meta\",\"old_string\":\"guid: aaa\",\"new_string\":\"guid: bbb\"}}" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Update File: Assets/Scripts/Player.cs.meta\n@@\n-guid: aaa\n+guid: bbb\n*** End Patch\"}}" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Update File: Assets/Scripts/Player.cs\n@@\n-int a;\n+int b;\n*** End Patch\"}}" \
  2 loadbearing

# --- block-legacy-input: the legacy Input API is forbidden by unity-specifics.md ---
check_hook block-legacy-input \
  "{\"tool_name\":\"Write\",\"cwd\":\"$CWD\",\"tool_input\":{\"file_path\":\"$CWD/Assets/Scripts/Player.cs\",\"content\":\"using UnityEngine;\npublic class Player : MonoBehaviour { void Update() { if (Input.GetKey(KeyCode.W)) { } } }\"}}" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: Assets/Scripts/Player.cs\n+using UnityEngine;\n+public class Player : MonoBehaviour { void Update() { if (Input.GetKey(KeyCode.W)) { } } }\n*** End Patch\"}}" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: Assets/Scripts/Player.cs\n+using UnityEngine;\n+public class Player : MonoBehaviour { void Update() { } }\n*** End Patch\"}}" \
  2 loadbearing

# --- guard-project-config: weakening the analyzer rules instead of fixing the code ---
check_hook guard-project-config \
  "{\"tool_name\":\"Edit\",\"cwd\":\"$CWD\",\"tool_input\":{\"file_path\":\"$CWD/.editorconfig\",\"old_string\":\"x\",\"new_string\":\"y\"}}" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Update File: .editorconfig\n@@\n-x\n+y\n*** End Patch\"}}" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Update File: Assets/Scripts/Ok.cs\n@@\n-int a;\n+int b;\n*** End Patch\"}}" \
  2 loadbearing

# --- warn-serialization: a renamed [SerializeField] without [FormerlySerializedAs] ---
check_hook warn-serialization \
  "{\"tool_name\":\"Edit\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"file_path\":\"$CWD/Assets/Scripts/P.cs\",\"old_string\":\"[SerializeField] private float _speed = 1f;\",\"new_string\":\"[SerializeField] private float _moveSpeed = 1f;\"}}" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Update File: Assets/Scripts/P.cs\n@@\n-[SerializeField] private float _speed = 1f;\n+[SerializeField] private float _moveSpeed = 1f;\n*** End Patch\"}}" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Update File: Assets/Scripts/P.cs\n@@\n-[SerializeField] private float _speed = 1f;\n+[FormerlySerializedAs(\\\"_speed\\\")]\n+[SerializeField] private float _moveSpeed = 1f;\n*** End Patch\"}}" \
  0 loadbearing

# --- warn-filename: Unity requires the file name to match the type it declares ---
#
# The trigger needs the `: MonoBehaviour` base, not merely a mismatched name: the
# hook warns only for Unity components, because only those must match their file
# name to be attachable. A plain `class Bar` in Foo.cs is legal C# and the hook
# correctly says nothing about it — the first trigger written here omitted the
# base type, the control did not act, and the anti-vacuity branch above refused
# to score the case rather than reporting the shim as working.
check_hook warn-filename \
  "{\"tool_name\":\"Write\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"file_path\":\"$CWD/Assets/Scripts/Foo.cs\",\"content\":\"public sealed class Bar : MonoBehaviour { }\"}}" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: Assets/Scripts/Foo.cs\n+public sealed class Bar : MonoBehaviour { }\n*** End Patch\"}}" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: Assets/Scripts/Foo.cs\n+public sealed class Foo : MonoBehaviour { }\n*** End Patch\"}}" \
  0 loadbearing

# --- warn-platform-defines: platform code with no #else is silently absent elsewhere ---
check_hook warn-platform-defines \
  "{\"tool_name\":\"Write\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"file_path\":\"$CWD/Assets/Scripts/Plat.cs\",\"content\":\"#if UNITY_ANDROID\nvoid A() { }\n#endif\"}}" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: Assets/Scripts/Plat.cs\n+#if UNITY_ANDROID\n+void A() { }\n+#endif\n*** End Patch\"}}" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: Assets/Scripts/Plat.cs\n+#if UNITY_ANDROID\n+void A() { }\n+#else\n+void B() { }\n+#endif\n*** End Patch\"}}" \
  0 loadbearing

# --- track-edits: writes no output in either direction; its state file is the observable ---
#
# Its negative control cannot be "an edit with no trigger", because ANY file is
# its trigger. It is a payload carrying no file at all — a shell call — which is
# the discriminator that shows the state line comes from the edit rather than
# from the shim having run.
check_hook track-edits \
  "{\"tool_name\":\"Write\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"file_path\":\"$CWD/Assets/Scripts/Tracked.cs\",\"content\":\"class Tracked {}\"}}" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: Assets/Scripts/Tracked.cs\n+class Tracked {}\n*** End Patch\"}}" \
  "{\"tool_name\":\"Bash\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"command\":\"ls -la\"}}" \
  0 loadbearing

# --- bash-gate: the one hook that already reads Codex's payload, because
#     `command` is the single key Codex supplies. Its row asserts the OPPOSITE
#     of the other eight, which is what shows this harness is not simply
#     reporting "inert" for everything it is handed. Its route through the shim
#     is passthrough, and the assertion is that passthrough does not break it.
BASH_BLOCK="{\"tool_name\":\"Bash\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"rm -f $CWD/Assets/Scripts/Player.cs.meta\"}}"
BASH_OK="{\"tool_name\":\"Bash\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"ls -la $CWD/Assets\"}}"
check_hook bash-gate "$BASH_BLOCK" "$BASH_BLOCK" "$BASH_OK" 2 survives

# ============================================================================
# 3. THE ADVISORY ROUTE
#
# The three warn-* hooks exit 0 and write to stderr. Under Claude Code that is
# surfaced. Under Codex the stderr of a hook that exits 0 is DISCARDED, and so is
# plain text on stdout — stdout is read as JSON only. The one measured route to
# the model is a JSON object carrying `hookSpecificOutput.additionalContext`.
#
# Without this, the advisory hooks would fire, act, and still tell nobody — the
# same defect as the payload problem, one layer further along.
# ============================================================================
echo "--- codex shim: advisory output reaches the model as additionalContext ---"

write_payload "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: Assets/Scripts/Plat.cs\n+#if UNITY_ANDROID\n+void A() { }\n+#endif\n*** End Patch\"}}"
ADV_OUT="$(bash "$SHIM" --hook warn-platform-defines < "$PAYLOAD_FILE" 2>/dev/null)" || true
ADV_CTX="$(printf '%s' "$ADV_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"
ADV_EVENT="$(printf '%s' "$ADV_OUT" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null || true)"

assert_eq "yes" "$([ -n "$ADV_CTX" ] && echo yes || echo no)" \
  "an advisory hook's warning is emitted as hookSpecificOutput.additionalContext JSON on stdout"
assert_eq "PostToolUse" "$ADV_EVENT" \
  "the emitted hookEventName is the event from the payload, not a hardcoded guess"
if grep -qF -- "WARNING" <<< "$ADV_CTX"; then
  pass "the delivered context carries the hook's own warning text"
else
  fail "the delivered context does not carry the hook's warning text"
fi

# A blocker's refusal must NOT be downgraded into advisory context — that would
# convert a block into an allow with a note.
write_payload "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Update File: Assets/Scenes/Main.unity\n@@\n-a\n+b\n*** End Patch\"}}"
BLK_STDOUT="$(bash "$SHIM" --hook block-scene-edit < "$PAYLOAD_FILE" 2>/dev/null)" && BLK_RC=0 || BLK_RC=$?
assert_eq "2" "$BLK_RC" "a refusal stays a refusal (exit 2), not an advisory note"
assert_eq "" "$BLK_STDOUT" "a refusal writes nothing to stdout — its reason goes to stderr, which Codex forwards verbatim"

# ============================================================================
# 4. MULTI-FILE ENVELOPES
#
# One apply_patch envelope can carry several files. A shim that inspects only
# the first is a gate with a hole, and the hole is invisible: the allowed file is
# the one nobody looked at.
# ============================================================================
echo "--- codex shim: every file in a multi-file envelope is checked ---"

write_payload "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: Assets/Scripts/Fine.cs\n+class Fine {}\n*** Update File: Assets/Scenes/Main.unity\n@@\n-a\n+b\n*** End Patch\"}}"
MULTI_ERR="$(bash "$SHIM" --hook block-scene-edit < "$PAYLOAD_FILE" 2>&1 >/dev/null)" && MULTI_RC=0 || MULTI_RC=$?
assert_eq "2" "$MULTI_RC" "a scene edit hiding behind an innocent first file in the same envelope is still blocked"
if grep -qF -- "Main.unity" <<< "$MULTI_ERR"; then
  pass "the refusal names the offending file, not the innocent one"
else
  fail "the refusal does not name Main.unity"
fi

# A rename must be checked at BOTH ends: `*** Move to:` can carry a forbidden
# destination behind a permitted source.
write_payload "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Update File: Assets/Scripts/A.txt\n*** Move to: Assets/Scripts/A.cs.meta\n@@\n-a\n+b\n*** End Patch\"}}"
MOVE_RC=0; bash "$SHIM" --hook block-meta-edit < "$PAYLOAD_FILE" >/dev/null 2>&1 || MOVE_RC=$?
assert_eq "2" "$MOVE_RC" "a rename whose DESTINATION is a .meta file is blocked (both ends of a move are checked)"

# ============================================================================
# 5. PATHS ARE MADE ABSOLUTE AGAINST THE PAYLOAD'S OWN cwd
#
# Not cosmetic. block-legacy-input.sh and warn-platform-defines.sh anchor their
# third-party skips on a leading path segment — `*/Assets/Extensions/*`,
# `*/Library/PackageCache/*` — and both record in their own comments that Claude
# Code sends absolute paths. Handed Codex's relative `Add File:` path, those
# anchors decide differently, so a vendored file would be gated and a first-party
# one might not be.
# ============================================================================
echo "--- codex shim: relative patch paths are resolved against cwd ---"

VEND="$WORK/vendored"; mkdir -p "$VEND"
write_payload "{\"tool_name\":\"apply_patch\",\"cwd\":\"$VEND\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: Assets/Extensions/Feel/Legacy.cs\n+using UnityEngine;\n+public class Legacy { void U() { if (Input.GetKey(KeyCode.W)) {} } }\n*** End Patch\"}}"
VEND_RC=0; bash "$SHIM" --hook block-legacy-input < "$PAYLOAD_FILE" >/dev/null 2>&1 || VEND_RC=$?
assert_eq "0" "$VEND_RC" \
  "a vendored Assets/Extensions/ file is still skipped — the */Assets/Extensions/* anchor needs a leading segment, so the cwd join is what preserves it"

write_payload "{\"tool_name\":\"apply_patch\",\"cwd\":\"$VEND\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: Assets/Scripts/First.cs\n+using UnityEngine;\n+public class First { void U() { if (Input.GetKey(KeyCode.W)) {} } }\n*** End Patch\"}}"
FIRST_RC=0; bash "$SHIM" --hook block-legacy-input < "$PAYLOAD_FILE" >/dev/null 2>&1 || FIRST_RC=$?
assert_eq "2" "$FIRST_RC" "a first-party Assets/Scripts/ file with the same violation IS blocked"

# --- THE ADVERSARIAL DIRECTION, which the two rows above do not cover --------
#
# Joining a path without NORMALISING it let a patch walk out of an exempted
# directory and back into a gated one while still matching the exemption:
# `Assets/Extensions/../Scripts/Player.cs` carries the literal
# `/Assets/Extensions/` that block-legacy-input.sh skips as vendored, and lands
# on a first-party file. Measured before the fix: rc 0, 0 bytes, against a
# baseline of rc 2. A model can produce that form without trying.
#
# The vendored row above is the control that stops this being "normalise until
# everything blocks": it must still be skipped.
for dotdot in \
  "Assets/Extensions/../Scripts/Player.cs" \
  "Assets/Editor/../Scripts/Player.cs" \
  "Assets/Tests/../Scripts/Player.cs" \
  "Library/PackageCache/../../Assets/Scripts/Player.cs" \
  "./Assets/Scripts/./Player.cs" ; do
  write_payload "{\"tool_name\":\"apply_patch\",\"cwd\":\"$VEND\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: $dotdot\n+using UnityEngine;\n+public class P { void U() { if (Input.GetKey(KeyCode.W)) {} } }\n*** End Patch\"}}"
  DD_RC=0; bash "$SHIM" --hook block-legacy-input < "$PAYLOAD_FILE" >/dev/null 2>&1 || DD_RC=$?
  assert_eq "2" "$DD_RC" "a path walking through an exempted directory is still gated: $dotdot"
done

# --- A DIRECTIVE THE PARSER DOES NOT KNOW IS REFUSED, NOT DROPPED -----------
#
# The refusal used to key on "zero files understood" rather than "every line
# understood", so a malformed header BEHIND one valid file parsed to a single
# innocent payload and returned 0 — while the same malformed header alone was
# refused. The allowed file is then the one nobody looked at, which is the exact
# hazard §4 was written against for the multi-file case.
echo "--- codex shim: an unrecognised patch directive is refused ---"

refuses "a malformed header hiding behind a valid file" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: Assets/Scripts/Fine.cs\n+class Fine {}\n*** Update File:Assets/Scenes/Main.unity\n@@\n-a\n+b\n*** End Patch\"}}" \
  --hook block-scene-edit
refuses "an entirely unknown *** directive alongside a valid file" \
  "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: Assets/Scripts/Fine.cs\n+class Fine {}\n*** Rename File: Assets/Scenes/Main.unity\n*** End Patch\"}}" \
  --hook block-scene-edit

# The control: the same envelope WITHOUT the unknown directive must be allowed,
# or this pair proves only that the shim refuses everything.
write_payload "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Add File: Assets/Scripts/Fine.cs\n+class Fine {}\n*** End Patch\"}}"
KNOWN_RC=0; bash "$SHIM" --hook block-scene-edit < "$PAYLOAD_FILE" >/dev/null 2>&1 || KNOWN_RC=$?
assert_eq "0" "$KNOWN_RC" "the same envelope with only known directives is allowed — the refusals above are about the unknown one"

# --- TRAILING WHITESPACE ON A HEADER ----------------------------------------
#
# The hooks match on suffix globs, and `*.unity ` is not `*.unity`. One trailing
# space took a scene edit from rc 2 to rc 0. Whether Codex's own parser trims it
# is unmeasured; the shim closes the divergence either way, because every
# normalisation difference between the two parsers is a bypass.
echo "--- codex shim: trailing whitespace on a header does not defeat the suffix globs ---"

for pad in " " "  " "\t"; do
  write_payload "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Update File: Assets/Scenes/Main.unity$pad\n@@\n-a\n+b\n*** End Patch\"}}"
  PAD_RC=0; bash "$SHIM" --hook block-scene-edit < "$PAYLOAD_FILE" >/dev/null 2>&1 || PAD_RC=$?
  assert_eq "2" "$PAD_RC" "a scene header padded with [$pad] is still blocked"
done

# ============================================================================
# 6. THE KILL SWITCHES STILL REACH THE HOOK THROUGH THE SHIM
#
# `DISABLE_UNITY_HOOKS=1` and `UNITY_HOOK_MODE=warn` are Kinglet's documented
# escape hatches. A wrapper that swallowed them would leave a user with no way
# out of a gate — and `warn` is the switch a user reaches for precisely when a
# gate is wrong.
# ============================================================================
echo "--- codex shim: the kill switches survive the wrapper ---"

write_payload "{\"tool_name\":\"apply_patch\",\"cwd\":\"$CWD\",\"hook_event_name\":\"PreToolUse\",\"tool_input\":{\"command\":\"*** Begin Patch\n*** Update File: Assets/Scenes/Main.unity\n@@\n-a\n+b\n*** End Patch\"}}"

KS_RC=0; DISABLE_UNITY_HOOKS=1 bash "$SHIM" --hook block-scene-edit < "$PAYLOAD_FILE" >/dev/null 2>&1 || KS_RC=$?
assert_eq "0" "$KS_RC" "DISABLE_UNITY_HOOKS=1 reaches the hook through the shim"

KS2_RC=0; DISABLE_HOOK_BLOCK_SCENE_EDIT=1 bash "$SHIM" --hook block-scene-edit < "$PAYLOAD_FILE" >/dev/null 2>&1 || KS2_RC=$?
assert_eq "0" "$KS2_RC" "DISABLE_HOOK_BLOCK_SCENE_EDIT=1 reaches the hook through the shim"

KS3_RC=0; UNITY_HOOK_MODE=warn bash "$SHIM" --hook block-scene-edit < "$PAYLOAD_FILE" >/dev/null 2>&1 || KS3_RC=$?
assert_eq "0" "$KS3_RC" "UNITY_HOOK_MODE=warn downgrades the block through the shim"

# Under Codex a hook that exits 0 has its stderr discarded, so `warn` mode is
# "block downgraded to NOTHING" unless the text is re-emitted as JSON. The shim
# routes it through additionalContext, which is the measured delivery route.
KS3_OUT="$(UNITY_HOOK_MODE=warn bash "$SHIM" --hook block-scene-edit < "$PAYLOAD_FILE" 2>/dev/null || true)"
KS3_CTX="$(printf '%s' "$KS3_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"
if grep -qF -- "downgraded" <<< "$KS3_CTX"; then
  pass "the downgraded warning is delivered as additionalContext rather than discarded"
else
  fail "UNITY_HOOK_MODE=warn text was swallowed — under Codex that is a block downgraded to nothing"
fi

# ============================================================================
# 7. CONFIG MODE — THE TIMEOUT UNIT
#
# `.claude/settings.json` declares timeouts in MILLISECONDS. Codex's field is
# `timeoutSec` and the unit is SECONDS — measured, not read off the field name.
# The external-agent importer copies the number across untouched, so 3000 / 5000
# / 2000 become 50, 83 and 33 MINUTES. A hung hook that should die in three
# seconds holds the turn for fifty.
#
# Every number is DERIVED from settings.json here. Writing the expected seconds
# down would be a hardcoded count in the guard against hardcoded counts.
# ============================================================================
echo "--- codex shim: --emit-config converts millisecond timeouts to seconds ---"

CFG="$WORK/hooks.json"
bash "$SHIM" --emit-config --project-dir "$ROOT" > "$CFG" 2>"$WORK/cfg.err" && CFG_RC=0 || CFG_RC=$?
assert_eq "0" "$CFG_RC" "--emit-config succeeds against this repository"

if [ "$CFG_RC" -eq 0 ]; then
  assert_eq "yes" "$(jq -e 'has("hooks")' "$CFG" >/dev/null 2>&1 && echo yes || echo no)" \
    "the emitted config has the top-level \"hooks\" wrapper Codex requires (a bare event map is rejected)"

  # --- The budget, derived from the settings file rather than asserted from a table. ---
  #
  # The shim's OWN ceiling is the budget settings.json declares; Codex's is that
  # plus one, so the shim always reports first. Both sides derived.
  WANT_BUDGET="$(jq -r '[.hooks | to_entries[] | select(.key == "PreToolUse" or .key == "PostToolUse") | .value[] | .hooks[] | ((.timeout + 999) / 1000 | floor)] | sort | join(",")' "$ROOT/.claude/settings.json")"
  GOT_SHIM_T="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | select(.command | test("codex-hook-shim\\.sh")) | (.command | capture("--timeout (?<t>[0-9]+)") | .t | tonumber)] | sort | join(",")' "$CFG")"
  assert_eq "$WANT_BUDGET" "$GOT_SHIM_T" \
    "the shim's own ceiling is exactly the budget settings.json declares, converted ms -> s"

  WANT_CODEX_T="$(jq -r '[.hooks | to_entries[] | select(.key == "PreToolUse" or .key == "PostToolUse") | .value[] | .hooks[] | (((.timeout + 999) / 1000 | floor) + 1)] | sort | join(",")' "$ROOT/.claude/settings.json")"
  GOT_CODEX_T="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | select(.command | test("codex-hook-shim\\.sh")) | .timeout] | sort | join(",")' "$CFG")"
  assert_eq "$WANT_CODEX_T" "$GOT_CODEX_T" \
    "Codex's ceiling for a wrapped hook is the budget plus one second of margin"

  # Session hooks are unwrapped, so their timeout is the bare conversion.
  WANT_SESSION_T="$(jq -r '[.hooks | to_entries[] | select(.key != "PreToolUse" and .key != "PostToolUse") | .value[] | .hooks[] | ((.timeout + 999) / 1000 | floor)] | sort | join(",")' "$ROOT/.claude/settings.json")"
  GOT_SESSION_T="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | select(.command | test("codex-hook-shim\\.sh") | not) | .timeout] | sort | join(",")' "$CFG")"
  assert_eq "$WANT_SESSION_T" "$GOT_SESSION_T" \
    "an unwrapped session hook carries the bare ms -> s conversion, with no margin"

  # --- THE ORDERING INVARIANT, which is the whole point of having two ceilings. ---
  #
  # The first version of this generator emitted the bare conversion and passed no
  # --timeout at all, leaving the shim on its 15 s default under a 2-5 s Codex
  # ceiling: the shim's watchdog could never fire, so every hook that outran the
  # budget was killed from OUTSIDE by Codex — the signal path, which was a silent
  # allow. Two ceilings that are not ordered are one ceiling and a decoration.
  ORDER_BAD="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[]
                       | select(.command | test("codex-hook-shim\\.sh"))
                       | select((.command | capture("--timeout (?<t>[0-9]+)") | .t | tonumber) >= .timeout)] | length' "$CFG")"
  assert_eq "0" "$ORDER_BAD" \
    "every wrapped hook's own ceiling is strictly below Codex's, so the shim refuses before Codex gives up"

  WRAPPED_WITH_T="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | select(.command | test("codex-hook-shim\\.sh")) | select(.command | test("--timeout [0-9]+"))] | length' "$CFG")"
  WRAPPED_N="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | select(.command | test("codex-hook-shim\\.sh"))] | length' "$CFG")"
  assert_eq "$WRAPPED_N" "$WRAPPED_WITH_T" \
    "every wrapped entry passes an explicit --timeout ($WRAPPED_WITH_T of $WRAPPED_N) — without it the shim runs on its default and can never fire first"
  assert_eq "yes" "$([ "$WRAPPED_N" -ge 1 ] && echo yes || echo no)" \
    "there were wrapped entries to check ($WRAPPED_N) — zero would pass the ordering assertion vacuously"

  # The floor that makes the comparison mean something: an empty settings file
  # would make both sides the empty string and the assertion above green.
  N_ENTRIES="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[]] | length' "$CFG")"
  assert_eq "yes" "$([ "$N_ENTRIES" -ge 1 ] && echo yes || echo no)" \
    "the emitted config actually carries hook entries ($N_ENTRIES) — an empty one would pass the comparison above vacuously"

  # No emitted timeout may still be a millisecond value. 60 s is longer than any
  # hook Kinglet ships and shorter than the smallest unconverted value (2000).
  BIG="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | select(.timeout > 60)] | length' "$CFG")"
  assert_eq "0" "$BIG" "no emitted timeout is still a millisecond value ($BIG over 60s)"

  # Registration identity: every hook in settings.json appears in the emitted
  # config, and nothing else does.
  WANT_HOOKS="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | .command | sub(".*/"; "")] | sort | unique | join(",")' "$ROOT/.claude/settings.json")"
  GOT_HOOKS="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | .command | sub(" --timeout [0-9]+$"; "") | sub("^.*/"; "") | sub("'\''$"; "")] | sort | unique | join(",")' "$CFG")"
  assert_eq "$WANT_HOOKS" "$GOT_HOOKS" "the emitted config registers exactly the hooks settings.json registers"

  # Tool events go through the shim; session events do not — a Stop hook has no
  # tool_input to normalise and nothing to refuse.
  SHIMMED="$(jq -r '[.hooks | to_entries[] | select(.key == "PreToolUse" or .key == "PostToolUse") | .value[] | .hooks[] | select(.command | contains("codex-hook-shim.sh"))] | length' "$CFG")"
  TOOL_TOTAL="$(jq -r '[.hooks | to_entries[] | select(.key == "PreToolUse" or .key == "PostToolUse") | .value[] | .hooks[]] | length' "$CFG")"
  assert_eq "$TOOL_TOTAL" "$SHIMMED" "every tool-event hook is registered through the shim ($SHIMMED of $TOOL_TOTAL)"
  assert_eq "yes" "$([ "$TOOL_TOTAL" -ge 1 ] && echo yes || echo no)" \
    "there were tool-event hooks to route ($TOOL_TOTAL) — zero would pass the identity above vacuously"

  SESSION_SHIMMED="$(jq -r '[.hooks | to_entries[] | select(.key != "PreToolUse" and .key != "PostToolUse") | .value[] | .hooks[] | select(.command | contains("codex-hook-shim.sh"))] | length' "$CFG")"
  assert_eq "0" "$SESSION_SHIMMED" "no session-lifecycle hook is wrapped — it has no tool payload to normalise"
fi

# --- CEILING DIVISION, AGAINST A TREE THAT CAN TELL CEIL FROM FLOOR ----------
#
# Every timeout Kinglet ships is a multiple of 1000, so ceil and floor AGREE at
# 3/5/2 and the assertions above cannot distinguish them — a mutation from
# `(ms + 999) / 1000` to `ms / 1000` survived the whole suite. The divergence
# exists only sub-second, and `findings.md` names ceiling division as a
# deliberate safety property: Codex's schema accepts `minimum: 0`, and a timeout
# of 0 kills every hook instantly. So the property is exercised here against a
# SYNTHETIC settings file carrying values no shipped tree has.
echo "--- codex shim: ceiling division, where ceil and floor actually differ ---"

CEILDIR="$WORK/ceil"
mkdir -p "$CEILDIR/.claude/hooks"
cp "$HOOKS/block-meta-edit.sh" "$HOOKS/_lib.sh" "$CEILDIR/.claude/hooks/"
cat > "$CEILDIR/.claude/settings.json" <<'CEILEOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": ".claude/hooks/block-meta-edit.sh", "timeout": 500 },
          { "type": "command", "command": ".claude/hooks/block-meta-edit.sh", "timeout": 1500 },
          { "type": "command", "command": ".claude/hooks/block-meta-edit.sh", "timeout": 1 }
        ] }
    ]
  }
}
CEILEOF

CEILCFG="$WORK/ceil.json"
bash "$SHIM" --emit-config --project-dir "$CEILDIR" > "$CEILCFG" 2>/dev/null && CEIL_RC=0 || CEIL_RC=$?
assert_eq "0" "$CEIL_RC" "--emit-config succeeds against a settings file with sub-second timeouts"

if [ "$CEIL_RC" -eq 0 ]; then
  # 500ms -> 1 (floor would give 0), 1500ms -> 2 (floor would give 1), 1ms -> 1 (floor: 0).
  CEIL_GOT="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | (.command | capture("--timeout (?<t>[0-9]+)") | .t | tonumber)] | sort | join(",")' "$CEILCFG")"
  assert_eq "1,1,2" "$CEIL_GOT" \
    "sub-second budgets round UP (500ms->1s, 1500ms->2s, 1ms->1s); floor division would emit 0,0,1"

  CEIL_ZERO="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | select((.command | capture("--timeout (?<t>[0-9]+)") | .t | tonumber) == 0)] | length' "$CEILCFG")"
  assert_eq "0" "$CEIL_ZERO" \
    "no budget rounds to a 0-second ceiling — Codex accepts 0 and it would kill every hook instantly"
fi

# ============================================================================
# 7b. THE FAIL-CLOSED GUARD ITSELF
#
# Every `refuses` shape above routes through `shim_block`, which exits 2
# deliberately. NONE of them constructs an UNEXPECTED internal death, so the EXIT
# trap — the file's own "defence 2", the thing that converts a stray non-zero
# status into a refusal — had no assertion behind it, and deleting it left the
# suite green. With it gone and a death injected, the shim exits 1 with no
# BLOCKED line: Codex's measured "exit 1 with a message" silent-allow class.
#
# So the guard is exercised the only way it can be: against a COPY of the shim
# with a real fault injected, which is what a future edit to the trap would have
# to survive.
# ============================================================================
echo "--- codex shim: the EXIT guard converts an unexpected internal death ---"

INJDIR="$WORK/inject"; mkdir -p "$INJDIR"
INJ="$INJDIR/codex-hook-shim.sh"
# The fault is placed after the traps are installed and before the payload is
# read, so it is exactly an "unexpected death mid-run" and nothing else.
awk '
  { print }
  /^PAYLOAD="\$\(cat\)"/ && !done { print "printf %s \"$KINGLET_DELIBERATELY_UNBOUND_FAULT\""; done = 1 }
' "$SHIM" > "$INJ"
chmod +x "$INJ"

INJ_APPLIED="$(/usr/bin/grep -c 'KINGLET_DELIBERATELY_UNBOUND_FAULT' "$INJ" || true)"
assert_eq "1" "$INJ_APPLIED" \
  "the injected-fault copy really carries the fault (0 would make the assertion below vacuous)"

inj_err="$(printf '%s' "$PATCH_OK" | bash "$INJ" --hook "$HOOKS/block-meta-edit.sh" 2>&1 >/dev/null)" && inj_rc=0 || inj_rc=$?
if [ "$inj_rc" -eq 2 ] && [ -n "$inj_err" ]; then
  pass "an unexpected internal death is converted to a refusal (exit 2 + ${#inj_err} bytes) rather than an exit-1 silent allow"
else
  fail "an unexpected internal death did NOT become a refusal (exit $inj_rc, ${#inj_err} bytes) — the EXIT guard is not doing its job"
fi

# ============================================================================
# 7c. SIGNALS
#
# Measured on the first version of this shim: killed by SIGTERM/INT/HUP/PIPE it
# exited 143/130/129/141 with ZERO bytes on stderr, which `codex-facts.md`
# records as an unlogged allow. The EXIT trap was running the whole time — the
# mechanism is that bash runs it inside the redirection context of the command
# it interrupted, and then RE-RAISES the signal, so both the message and the
# `exit 2` were discarded.
#
# It is reachable by what the generator itself emits: Codex enforces `timeoutSec`
# and kills the shim from outside. A user's Ctrl-C is SIGINT; a closed terminal
# is SIGHUP.
#
# The control below is what makes the signal rows mean something: the same shim
# and the same never-finishing hook, stopped by its OWN watchdog, must also
# refuse. If the control failed, the signal rows would be measuring a shim that
# cannot refuse at all.
# ============================================================================
echo "--- codex shim: a signal lands on a refusal, not a silent allow ---"

SIGHOOK="$WORK/sig-hook.sh"
printf '#!/usr/bin/env bash\nsleep 45\n' > "$SIGHOOK"; chmod +x "$SIGHOOK"

# THE SIGHUP RED SEEN TWICE ON THIS BRANCH IS AN ARTIFACT OF HOW THE SUITE WAS
# LAUNCHED, NOT OF LOAD — AND THAT IS THE THIRD CAUSE THIS PARAGRAPH HAS NAMED.
# **DO NOT RUN THIS SUITE UNDER `nohup`.**
#
# The sightings are kept below because a red here is read against this comment, and
# because the two wrong causes are the reason the right one took three rounds.
#
#   2026-08-16, inside a full-suite run: `FAIL: SIGHUP did NOT refuse (exit 0, 0 bytes)`.
#   2026-08-17, a reviewer's first full-suite run: the same line, character for character.
#
# Both were attributed to CPU contention — the second explicitly to *external* load
# from an unrelated process tree, with "the cheapest next experiment" named as this
# loop body under generated load. That experiment was never the one to run.
#
# THE MECHANISM, MEASURED 2026-08-17 AND DETERMINISTIC IN BOTH DIRECTIONS. `nohup`
# sets SIGHUP to `SIG_IGN`, and an IGNORED disposition — unlike a trapped one — is
# inherited across `fork` and `exec` into every descendant, however deep. So the
# shim's process cannot be killed by the signal this loop sends it, `wait` reaps a
# process that exited 0, and the assertion reds on a completely healthy tree:
#
#   foreground   `bash -c 'bash -c "trap -p SIGHUP"'`  →  (empty: default disposition)
#   under nohup  the same command                      →  `trap -- '' SIGHUP`
#   foreground   a grandchild that HUPs itself         →  `Hangup`, rc 129
#   under nohup  the same grandchild                   →  rc 7, it survives
#
#   `bash tests/test-codex-shim.sh` in the foreground   →  0 of 3 runs red
#   `nohup bash tests/test-codex-shim.sh`               →  3 of 3 red, and every time
#                                                          it is SIGHUP alone while
#                                                          TERM, INT and PIPE pass
#
# THAT LAST COLUMN IS WHY THE SHAPE LOOKED LIKE A FLAKE. Three sibling rows staying
# green is exactly what a genuine intermittent single-signal regression would look
# like — and it is also what a launcher that ignores exactly one signal produces,
# every single time. The two are indistinguishable from the log alone, and the
# distinguishing observation costs one command: `trap -p SIGHUP`.
#
# WHAT SURVIVES FROM THE LOAD HYPOTHESIS, because a superseded measurement is not a
# false one. The probe that ran this loop body with the signal as a parameter read
# 0 of 25 per signal on a quiet host and 0 of 12 per signal in three concurrent
# instances — SIGHUP 0 of 61. All four arms read zero, so it had no positive control
# and refuted nothing; it is now also consistent with the cause above, since none of
# those runs was launched under `nohup`. It is NOT the killer-subshell race fixed in
# scripts/codex-hook-shim.sh on 2026-08-16 either — that one has a different
# signature (`payload.N.json: No such file or directory`) and a different assertion.
# And one mechanism was eliminated rather than assumed: `$!` under `set -m` still
# names the LAST process of the pipeline on this host (measured both ways), so the
# kill lands on the shim and not on a long-gone `printf`.
#
# IF YOU MEET THIS RED: check the disposition first (`trap -p SIGHUP` inside the
# harness, and `cat /proc/self/status | grep SigIgn`). If it is ignored, the finding
# is about your launcher. Only a red with SIGHUP at its default disposition is a
# claim about this shim, and that one belongs in the ledger with its conditions.
#
# `set -m` IS LOAD-BEARING AND THE SIGINT ROW IS WHY. POSIX requires a
# non-interactive shell to start an ASYNC job with SIGINT and SIGQUIT set to
# SIG_IGN, and bash cannot trap a signal that was ignored on entry — so without
# job control the shim never sees a SIGINT at all and this row measured the
# harness rather than the shim. Read out of /proc/self/status for a child of an
# async job on this host: SigIgn=0x6 (INT+QUIT) without `set -m`, SigIgn=0x0
# with it. Codex spawns hooks as ordinary children with default dispositions,
# which is the `set -m` column. Job-control chatter goes to the subshell's own
# stderr, not the shim's capture file.
for sig in TERM INT HUP PIPE; do
  sig_err="$WORK/sig.$sig.err"
  : > "$sig_err"
  (
    set -m
    printf '%s' "$PATCH_OK" | bash "$SHIM" --hook "$SIGHOOK" --timeout 60 >/dev/null 2>"$sig_err" &
    sig_pid=$!
    sleep 1
    kill -"$sig" "$sig_pid" 2>/dev/null || true
    wait "$sig_pid"
  ) >/dev/null 2>/dev/null && sig_rc=0 || sig_rc=$?
  if [ "$sig_rc" -eq 2 ] && [ -s "$sig_err" ]; then
    pass "SIG$sig lands on a refusal (exit 2 + $(wc -c < "$sig_err") bytes)"
  else
    fail "SIG$sig did NOT refuse (exit $sig_rc, $(wc -c < "$sig_err") bytes) — under Codex that permits the call and reports nothing"
  fi
done

# The control. Same shim, same never-finishing hook, stopped by its own watchdog.
refuses "the control for the signal rows: the same hook stopped by the watchdog" \
  "$PATCH_OK" --hook "$SIGHOOK" --timeout 1

# ============================================================================
# 7d. THE BUDGET BOUNDS THE WHOLE INVOCATION, NOT JUST EACH HOOK RUN
#
# The first version bounded only the wrapped hook, once per file. Two phases
# were left unbounded, and BOTH ran past Codex's ceiling with every individual
# step comfortably inside its budget — so the "the shim always reports first"
# claim was false for each:
#
#   * the jq normalisation is superlinear in added lines — measured 2 000 lines
#     0.07 s, 8 000 0.34 s, 20 000 2.05 s, 40 000 8.38 s, all under `--timeout 3`
#     and all returning 0;
#   * the loop spawns the hook once per FILE — 200 files through
#     block-legacy-input took 4.24 s against an emitted Codex ceiling of 4 s.
#
# A signal cannot rescue either: bash defers a trapped signal until the current
# foreground command finishes, so SIGTERM delivered 1.0 s into a 40 000-line
# parse was answered at 8.55 s.
#
# Each row below is paired with an UNDER-budget control, because "it refuses"
# is worthless without "and it still allows the ordinary case".
# ============================================================================
echo "--- codex shim: the budget bounds the parse and the whole file loop ---"

big_envelope() { # $1 = added lines
  python3 -c "
import json, sys
n = int(sys.argv[1])
lines = ['*** Begin Patch', '*** Add File: Assets/Scripts/Big.cs'] + ['+// l %d' % i for i in range(n)] + ['*** End Patch']
print(json.dumps({'tool_name': 'apply_patch', 'cwd': '/proj', 'hook_event_name': 'PreToolUse',
                  'tool_input': {'command': '\n'.join(lines)}}))" "$1"
}
many_files() { # $1 = file count
  python3 -c "
import json, sys
n = int(sys.argv[1]); lines = ['*** Begin Patch']
for i in range(n):
    lines += ['*** Add File: Assets/Scripts/F%d.cs' % i, '+class F%d {}' % i]
lines.append('*** End Patch')
print(json.dumps({'tool_name': 'apply_patch', 'cwd': '/proj', 'hook_event_name': 'PreToolUse',
                  'tool_input': {'command': '\n'.join(lines)}}))" "$1"
}

if command -v python3 >/dev/null 2>&1; then
  NOOP="$WORK/noop-hook.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$NOOP"; chmod +x "$NOOP"

  # --- the parse ---
  BIG_START=$(date +%s)
  big_err="$(big_envelope 40000 | bash "$SHIM" --hook "$NOOP" --timeout 2 2>&1 >/dev/null)" && big_rc=0 || big_rc=$?
  BIG_ELAPSED=$(( $(date +%s) - BIG_START ))
  if [ "$big_rc" -eq 2 ] && [ -n "$big_err" ]; then
    pass "an envelope too large to parse inside the budget is refused (${BIG_ELAPSED}s, ${#big_err} bytes)"
  else
    fail "a 40000-line envelope was NOT refused (exit $big_rc, ${#big_err} bytes, ${BIG_ELAPSED}s) — unbounded, it parsed for 8.4s under a 3s budget and returned 0"
  fi
  # THE THRESHOLD MUST DISCRIMINATE, AND 8 DID NOT. Refusing is not enough: with
  # the parse unbounded the loop's budget check refuses anyway, just SIX SECONDS
  # LATE — long after Codex stopped waiting, which is a silent allow. Measured
  # at this envelope size and budget: bounded 2.12 s, unbounded 8.34 s. Written
  # as `-le 8` first, whole-second arithmetic rounded 8.34 down and the mutation
  # survived. 5 separates them with room for a loaded machine.
  assert_eq "yes" "$([ "$BIG_ELAPSED" -le 5 ] && echo yes || echo no)" \
    "and it refuses NEAR the budget (${BIG_ELAPSED}s, budget 2s), rather than after the parse finally finishes"

  # Control: an envelope that parses comfortably inside the budget is allowed.
  small_out="$(big_envelope 2000 | bash "$SHIM" --hook "$NOOP" --timeout 10 2>&1 >/dev/null)" && small_rc=0 || small_rc=$?
  assert_eq "0" "$small_rc" "a 2000-line envelope is still allowed — the bound is a budget, not a size limit"
  assert_eq "" "$small_out" "and it says nothing on the allowed path"

  # --- the loop ---
  MANY_START=$(date +%s)
  many_err="$(many_files 400 | bash "$SHIM" --hook "$NOOP" --timeout 2 2>&1 >/dev/null)" && many_rc=0 || many_rc=$?
  MANY_ELAPSED=$(( $(date +%s) - MANY_START ))
  if [ "$many_rc" -eq 2 ] && [ -n "$many_err" ]; then
    pass "an envelope with more files than fit in the budget is refused (${MANY_ELAPSED}s, ${#many_err} bytes)"
  else
    fail "a 400-file envelope was NOT refused (exit $many_rc, ${#many_err} bytes, ${MANY_ELAPSED}s) — the budget is per hook run, not per invocation"
  fi
  assert_eq "yes" "$([ "$MANY_ELAPSED" -le 8 ] && echo yes || echo no)" \
    "and it refuses near the budget (${MANY_ELAPSED}s) rather than running the whole envelope out"

  # The refusal must say how far it got: "refused" with no count is undiagnosable.
  if grep -qF -- "of 400 file(s)" <<< "$many_err"; then
    pass "the refusal names how many of the envelope's files were checked"
  else
    fail "the refusal does not name how far it got: $many_err"
  fi

  # Control: a handful of files is well inside the budget.
  few_out="$(many_files 5 | bash "$SHIM" --hook "$NOOP" --timeout 10 2>&1 >/dev/null)" && few_rc=0 || few_rc=$?
  assert_eq "0" "$few_rc" "a 5-file envelope is still allowed"
  assert_eq "" "$few_out" "and it says nothing on the allowed path"

  # --- EACH HOOK RUN GETS WHAT IS LEFT, NOT THE WHOLE BUDGET AGAIN -----------
  #
  # The budget check before each file is not sufficient on its own: it can pass
  # with a fraction of a second left, and if the run that follows is then handed
  # the FULL budget the invocation overshoots by almost a whole budget. Two
  # files against a 2 s hook under a 3 s budget separates the two cleanly —
  # measured, remaining-budget 3.07 s and refused, full-budget-each 4.06 s and
  # ALLOWED, against an emitted Codex ceiling of 4 s.
  SLOW2="$WORK/slow2-hook.sh"
  printf '#!/usr/bin/env bash\nsleep 2\nexit 0\n' > "$SLOW2"; chmod +x "$SLOW2"
  R3_START=$(date +%s)
  r3_err="$(many_files 2 | bash "$SHIM" --hook "$SLOW2" --timeout 3 2>&1 >/dev/null)" && r3_rc=0 || r3_rc=$?
  R3_ELAPSED=$(( $(date +%s) - R3_START ))
  if [ "$r3_rc" -eq 2 ] && [ -n "$r3_err" ]; then
    pass "a second file cannot restart the budget: two 2s hooks under a 3s budget are refused (${R3_ELAPSED}s)"
  else
    fail "two 2s hooks under a 3s budget were NOT refused (exit $r3_rc, ${R3_ELAPSED}s) — each run is getting the full budget again, so the invocation overshoots"
  fi
  assert_eq "yes" "$([ "$R3_ELAPSED" -le 3 ] && echo yes || echo no)" \
    "and the invocation stops inside its budget (${R3_ELAPSED}s of 3s), not one budget per file"

  # --- A BUDGET ALREADY SPENT MUST NOT MAKE THE NEXT STEP UNBOUNDED ----------
  #
  # `shim_left_ms` returns 0 for "expired" and -1 for "no budget set", and
  # `shim_watch` arms no watchdog only for -1. Those were once the same number:
  # 0 meant BOTH "expired" and "unbounded", so once the budget was gone the next
  # step ran with no ceiling at all.
  #
  # The shape that exposes it is a payload delivered slowly enough to consume the
  # budget before parsing begins — nothing inside the shim is slow here, the
  # clock simply ran out first. Measured with the overloaded sentinel: refusal at
  # 12.4 s under a 3 s budget, the gap being an unbounded parse of a large
  # envelope. Fixed: 4.1 s, which is when stdin closes.
  SLOW_RAW="$WORK/slow-payload.json"
  big_envelope 40000 > "$SLOW_RAW"
  SLOW_START=$(date +%s)
  slow_err="$( { sleep 4; cat "$SLOW_RAW"; } | bash "$SHIM" --hook "$NOOP" --timeout 3 2>&1 >/dev/null )" && slow_rc=0 || slow_rc=$?
  SLOW_ELAPSED=$(( $(date +%s) - SLOW_START ))
  if [ "$slow_rc" -eq 2 ] && [ -n "$slow_err" ]; then
    pass "a budget spent before parsing begins is refused (${SLOW_ELAPSED}s, ${#slow_err} bytes)"
  else
    fail "a budget spent before parsing was NOT refused (exit $slow_rc, ${SLOW_ELAPSED}s)"
  fi
  # 4.1s fixed versus 12.4s with the sentinel overloaded; 8 separates them with
  # room, and the assertion is about the PARSE being bounded, not about stdin.
  assert_eq "yes" "$([ "$SLOW_ELAPSED" -le 8 ] && echo yes || echo no)" \
    "and it refuses when the clock runs out (${SLOW_ELAPSED}s), not after an unbounded parse of the envelope"

  # --- THE VERDICT MUST NOT DEPEND ON WHERE THE START FELL IN A SECOND -------
  #
  # `date +%s` truncates, so the recorded start could be up to a second early and
  # the effective budget was `(N-1, N]` rather than N. Measured on a 1.2 s
  # workload under a declared 2 s budget: allowed 22 of 24 runs, refused 2 of 24
  # — the same input, two verdicts. `track-edits` is the only shipped 2 s hook,
  # so it was reachable with what Kinglet ships.
  #
  # A 1.5 s workload under a 2 s budget is the sharpest probe available: with
  # truncation it is refused whenever the start falls in the second half of a
  # second, i.e. about half the time, so six runs make a regression practically
  # certain to show. The margin is deliberate and stated rather than incidental:
  # 0.5 s of headroom against a budget the clock can no longer shorten.
  # SAMPLING THIS PROPERTY DOES NOT GUARD IT, AND THAT IS WHY THE PROBE BELOW
  # LOOKS AT RESOLUTION INSTEAD. The truncation only bites when a second boundary
  # falls inside the shim's own startup — a window of a few tens of milliseconds,
  # so a few percent of runs. Six repetitions of a 1.5 s workload therefore catch
  # a reverted clock only about a fifth of the time, and a mutation to whole
  # seconds SURVIVED exactly that assertion. The repetitions are kept, cheaply,
  # because "same input, same verdict" is the user-facing property; the guard is
  # the resolution probe.
  DET_HOOK="$WORK/det-hook.sh"
  printf '#!/usr/bin/env bash\nsleep 1.5\nexit 0\n' > "$DET_HOOK"; chmod +x "$DET_HOOK"
  DET_ALLOWED=0; DET_REFUSED=0
  for det_i in 1 2 3; do
    if many_files 1 | bash "$SHIM" --hook "$DET_HOOK" --timeout 2 >/dev/null 2>&1; then
      DET_ALLOWED=$((DET_ALLOWED + 1))
    else
      DET_REFUSED=$((DET_REFUSED + 1))
    fi
  done
  assert_eq "3" "$DET_ALLOWED" \
    "a 1.5s workload under a 2s budget is allowed every time ($DET_ALLOWED allowed, $DET_REFUSED refused)"

  # THE RESOLUTION ITSELF, PROBED THROUGH BEHAVIOUR RATHER THAN THE SOURCE.
  #
  # Three files against a 0.4 s hook under a 1 s budget: the third run is killed
  # by the watchdog with a fraction of a second left, and the refusal reports how
  # much. With a millisecond clock that number is ~143 and is not a multiple of
  # 1000. With a whole-second clock the message does not appear at all — the
  # budget goes 1000 -> 0 with nothing in between, so the pre-run check refuses
  # first and no watchdog kill ever happens. Either way the observable differs
  # deterministically, which sampling the verdict did not.
  if case "$(date +%N 2>/dev/null)" in ''|*[!0-9]*) false ;; *) true ;; esac; then
    RES_HOOK="$WORK/res-hook.sh"
    printf '#!/usr/bin/env bash\nsleep 0.4\nexit 0\n' > "$RES_HOOK"; chmod +x "$RES_HOOK"
    res_err="$(many_files 3 | bash "$SHIM" --hook "$RES_HOOK" --timeout 1 2>&1 >/dev/null)" || true
    res_ms="$(awk 'match($0, /with [0-9]+ms/) { print substr($0, RSTART + 5, RLENGTH - 7); exit }' <<< "$res_err")"
    if [ -n "$res_ms" ] && [ "$((res_ms % 1000))" -ne 0 ]; then
      pass "the invocation clock has sub-second resolution (${res_ms}ms left when the watchdog fired)"
    else
      fail "the invocation clock looks like whole seconds (reported '${res_ms:-no watchdog kill at all}') — the effective budget becomes (N-1, N] and the same input gets two verdicts"
    fi
  else
    printf '  SKIP: this host has no sub-second `date +%%N`, so the millisecond clock cannot be probed; the shim falls back to whole seconds there by design\n'
  fi
else
  fail "python3 unavailable — the budget bounds went unmeasured"
fi

# A signal must not be able to turn an ALLOW into a refusal either: the killer
# subshell inherits this script's traps, and the happy path kills it on purpose.
# Without a `trap -` reset inside it, that kill ran the signal handler in the
# subshell and put a spurious BLOCKED line on the real stderr of a call the hook
# had just allowed — descriptor 9 is not stderr, so the subshell's own
# `2>/dev/null` would not have hidden it.
FASTHOOK="$WORK/fast-hook.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FASTHOOK"; chmod +x "$FASTHOOK"
fast_err="$(printf '%s' "$PATCH_OK" | bash "$SHIM" --hook "$FASTHOOK" --timeout 5 2>&1 >/dev/null)" && fast_rc=0 || fast_rc=$?
assert_eq "0" "$fast_rc" "an allowed call still exits 0 with the watchdog armed"
assert_eq "" "$fast_err" "an allowed call writes nothing to stderr — the watchdog's killer emits no spurious refusal"

# ── The killer is killed with a signal that CANNOT run a trap ──────────────
#
# The `trap -` reset the block above describes is the intended defence, and it is
# not sufficient, because IT IS NOT ATOMIC WITH THE FORK. A subshell resets the
# SIGNAL traps at fork but INHERITS the EXIT trap, and `wait "$sw_pid"` returns in
# microseconds when the wrapped hook is fast — so the parent's kill can land
# before the subshell has executed its first builtin. The inherited EXIT trap then
# runs shim_guard -> shim_cleanup -> `rm -rf` of the temp directory THE PARENT IS
# STILL FILLING, and the parent fails on its next payload write with
# `payload.N.json: No such file or directory`. That is the intermittent red this
# suite carried, in the assertion "the refusal does not name how far it got":
# three independent readers reproduced it and called it a flake.
#
# SIGKILL cannot run a trap, so the window closes rather than being made harmless.
# The assertion has two halves because the structural one alone would be satisfied
# by any signal name someone believed was untrappable.
#
# THE SIGNAL IS DERIVED FROM THE SHIM, NOT WRITTEN DOWN HERE. A guard that
# hardcodes `KILL` on both sides tests nothing about the file it guards.
SW_KILL_SIG="$(awk 'match($0, /kill -[A-Z0-9]+ "\$sw_killer"/) {
    s = substr($0, RSTART + 6, RLENGTH - 6)
    sub(/ .*$/, "", s)
    print s
    exit
  }' "$SHIM")"
assert_eq "yes" "$([ -n "$SW_KILL_SIG" ] && echo yes || echo no)" \
  "the shim's kill of the watchdog killer was located — an extraction that matches nothing makes every assertion below it vacuous"

# THE BEHAVIOURAL HALF, WITH ITS POSITIVE CONTROL ASSERTED RATHER THAN ASSUMED.
# A subshell installs an EXIT trap, announces that it has, and blocks; the signal
# is sent only after the announcement, so there is NO RACE here — this measures
# what the signal does to an already-installed trap, which is the property the fix
# rests on. That matters because the obvious rig for this defect (fork, kill
# immediately, count trap entries) reads ZERO IN BOTH ARMS unless the kill beats
# the subshell's first instruction: measured at 11/50, 4/50 and 29/50 at zero
# delay and 0/50 with 10 ms inserted. A probe with no live positive control cannot
# detect the event it tests for, so the TERM arm below is an assertion and not a
# comment.
sw_trap_probe() {
  # $1 = signal name. Echoes `ran` if the subshell's EXIT trap fired, `silent` if not.
  sw_pd="$WORK/sigprobe.$1.$$"
  rm -rf "$sw_pd"; mkdir -p "$sw_pd"
  ( trap 'printf x > "'"$sw_pd"'/ran"' EXIT; printf r > "$sw_pd/ready"; sleep 0.3 ) &
  sw_pp=$!
  sw_pn=0
  while [ ! -f "$sw_pd/ready" ] && [ "$sw_pn" -lt 300 ]; do sleep 0.01; sw_pn=$((sw_pn + 1)); done
  kill "-$1" "$sw_pp" >/dev/null 2>&1 || true
  wait "$sw_pp" >/dev/null 2>&1 || true
  if [ -f "$sw_pd/ran" ]; then printf 'ran\n'; else printf 'silent\n'; fi
  rm -rf "$sw_pd"
}
assert_eq "ran" "$(sw_trap_probe TERM)" \
  "the probe is live: SIGTERM DOES run an inherited EXIT trap on this host — the positive control, without which the next assertion is green over a broken instrument"
assert_eq "silent" "$(sw_trap_probe "$SW_KILL_SIG")" \
  "…and the signal the shim actually sends its watchdog killer (-$SW_KILL_SIG) cannot run that trap, so the killer can never reach shim_cleanup and delete the parent's temp directory"

# The pipe-release property is asserted at the top of this file, where it can
# name itself before a regression makes everything else slow. See the note there
# for why the capture must go through a pipe: written as `>/dev/null 2>&1` it
# gives the orphaned `sleep` nothing to hold open, and the mutation that removes
# `9>&-` survives it at 0 s either way.

# ============================================================================
# 8. CLAUDE CODE IS UNTOUCHED
#
# The whole reason this is a shim rather than twelve edits: `.claude/hooks/*.sh`
# is a shipped Claude Code surface. The suite's other files assert its behaviour;
# what is asserted HERE is that this wave did not quietly reach into it.
# ============================================================================
echo "--- codex shim: the Claude Code hook surface is untouched ---"

if /usr/bin/grep -rlF -- "codex" "$HOOKS" >/dev/null 2>&1; then
  fail "a file under .claude/hooks/ mentions codex — the shim was supposed to keep that surface unchanged"
else
  pass "no file under .claude/hooks/ mentions codex — the Claude Code surface carries no Codex-specific branch"
fi

# The shim must live outside .claude/hooks/, or every hook-enumerating guard in
# the suite counts it as a 13th hook that settings.json does not register.
assert_eq "no" "$([ -f "$HOOKS/codex-hook-shim.sh" ] && echo yes || echo no)" \
  "the shim is not inside .claude/hooks/ (it would be read as an unregistered hook)"

# ============================================================================
# 9. WHATEVER install.sh SKIPS, IT SKIPS IN BOTH HALVES
#
# This header read "THE SHIM DOES NOT SHIP INTO A CLAUDE CODE PROJECT, AND BOTH
# HALVES OF THE SKIP ARE HELD" until 2026-08-16. The first clause is now false —
# the Codex ship list put codex-hook-shim.sh into the payload, because the
# .codex/hooks.json it generates carries an absolute path to it and a shim outside
# the project is a hook command Codex silently allows. The assertions below never
# named the shim: they derive the skip list from install.sh and hold whatever is
# in it, so they were correct through that change and only the header stated the
# opposite of the world. Kept as a header about the invariant rather than about
# one file's membership, which is the property that made it rot.
#
# install.sh names each skipped script TWICE — once in the NEW_PATHS enumeration
# and once in the write loop — and its own comment says the two must stay in
# step. Nothing held them together: tests/test-derived-counts.sh extracts the
# names with `sort -u`, deliberately counting DISTINCT NAMES rather than matching
# lines, so ONE of the two lines is enough to keep every count green. Measured:
# removing the write-loop half alone left that file green and landed
# `.claude/scripts/codex-hook-shim.sh` in a real fixture install; removing the
# enumeration half alone was equally green.
#
# This is a structural gap that predates this wave, but this wave added a third
# name to it, and "skipped in both" was established by reading rather than by a
# guard. Asserted here per name, in both directions.
echo "--- codex shim: install.sh skips it in BOTH the enumeration and the write loop ---"

SC_INSTALL="$ROOT/install.sh"
assert_eq "yes" "$([ -f "$SC_INSTALL" ] && echo yes || echo no)" "install.sh is readable"

# Derived from install.sh, not hardcoded: whatever it skips, it must skip twice.
SC_SKIP_NAMES="$(/usr/bin/grep -oE '\[ "\$b" = "[^"]+" \] && continue' "$SC_INSTALL" \
                 | sed 's/.*= "//; s/" \].*//' | sort -u)"
SC_SKIP_N="$(printf '%s\n' "$SC_SKIP_NAMES" | /usr/bin/grep -c . || true)"
assert_eq "yes" "$([ "$SC_SKIP_N" -ge 1 ] && echo yes || echo no)" \
  "install.sh's script-skip pattern matched something ($SC_SKIP_N names) — zero would make the loop below vacuous"

SC_HALF=""
while IFS= read -r sc_name; do
  [ -n "$sc_name" ] || continue
  sc_count="$(/usr/bin/grep -cF -- "[ \"\$b\" = \"$sc_name\" ] && continue" "$SC_INSTALL" || true)"
  [ "$sc_count" -ge 2 ] || SC_HALF="${SC_HALF}${sc_name} (appears ${sc_count}x, needs 2)"$'\n'
done <<< "$SC_SKIP_NAMES"

if [ -n "$SC_HALF" ]; then
  printf '%s' "$SC_HALF" | sed 's|^|     skipped in only one of install.sh'"'"'s two loops: |'
fi
assert_eq "0" "$(printf '%s' "$SC_HALF" | /usr/bin/grep -c . || true)" \
  "every skipped script is skipped in BOTH install.sh loops — one half alone still installs the file"

# And the behavioural half: the shim must not appear in what a dry run announces.
SC_DRY="$(bash "$SC_INSTALL" --project-dir "$PROJ" --dry-run 2>&1 || true)"
if grep -qF -- "codex-hook-shim" <<< "$SC_DRY"; then
  fail "install.sh --dry-run names codex-hook-shim.sh — it is a Codex-layer artifact and does not belong in a Claude Code project"
else
  pass "install.sh --dry-run does not name codex-hook-shim.sh"
fi

echo ""
printf 'test-codex-shim: %s assertions, %s failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
exit 0
