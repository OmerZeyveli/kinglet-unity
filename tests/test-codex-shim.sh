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
# in ticks first, this file's 100 assertions moved that total by zero.
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

  # Ceiling division, derived from the settings file rather than asserted from a table.
  WANT_SECS="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | ((.timeout + 999) / 1000 | floor)] | sort | join(",")' "$ROOT/.claude/settings.json")"
  GOT_SECS="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | .timeout] | sort | join(",")' "$CFG")"
  assert_eq "$WANT_SECS" "$GOT_SECS" "every emitted timeout is its settings.json value converted ms -> s"

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
  GOT_HOOKS="$(jq -r '[.hooks | to_entries[] | .value[] | .hooks[] | .command | sub("^.*/"; "") | sub("'\''$"; "")] | sort | unique | join(",")' "$CFG")"
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

echo ""
printf 'test-codex-shim: %s assertions, %s failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
exit 0
