#!/usr/bin/env bash
# ============================================================================
# test-block-legacy-input.sh
#
# rules/unity-specifics.md has always said "Legacy Input.GetKey/Input.GetAxis is
# BLOCKED by hooks". Nothing enforced it — not here, not in ECU v1.5.0. Three
# rule files asserted a guarantee that did not exist. block-legacy-input.sh is
# that hook; this is what keeps the claim honest.
#
# The two allow-cases are not politeness. Both were predicted from a real
# project before the hook was written, and a hook that fails either is worse
# than no hook: it fires on code you must not touch, and you learn to ignore it.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="$PROJECT_ROOT/.claude/hooks/block-legacy-input.sh"

TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
assert_eq() { TESTS_RUN=$((TESTS_RUN+1)); if [ "$1" = "$2" ]; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"; else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (expected '$2', got '$1')"; fi; }

# Feed the hook a payload shaped like Claude Code's, return its exit code.
verdict() {  # $1 = file path, $2 = file content
  local out rc
  set +e
  out=$(printf '{"tool_input":{"file_path":%s,"new_string":%s}}' \
        "$(printf '%s' "$1" | jq -Rs .)" "$(printf '%s' "$2" | jq -Rs .)" \
        | bash "$HOOK" 2>/dev/null)
  rc=$?
  set -e
  printf '%s' "$rc"
}

assert_eq "$([ -f "$HOOK" ] && echo yes || echo no)" "yes" "block-legacy-input.sh exists"
assert_eq "$([ -x "$HOOK" ] && echo yes || echo no)" "yes" "block-legacy-input.sh is executable"

# --- it must fire on the real thing ----------------------------------------
VIOLATION='using UnityEngine;
public class Player : MonoBehaviour {
    private void Update() {
        if (Input.GetKeyDown(KeyCode.F1)) ChangeForm();
    }
}'
assert_eq "$(verdict /proj/Assets/Player/Scripts/Player.cs "$VIOLATION")" "2" "blocks unguarded Input.GetKeyDown in first-party code"

for api in 'Input.GetAxis("Horizontal")' 'Input.GetButtonDown("Jump")' 'Input.mousePosition' 'Input.touchCount'; do
  assert_eq "$(verdict /proj/Assets/Scripts/A.cs "void Update(){ var x = $api; }")" "2" "blocks $api"
done

# --- and it must NOT fire on these -----------------------------------------
# A correct dual path. Endless-Evolution's PerfProbe.cs is written exactly like
# this: it is the right answer for editor tooling that must survive either
# project input setting, and a grep-only hook blocks it.
DUAL='#if UNITY_EDITOR
using UnityEngine;
static bool F9Pressed() {
#if ENABLE_INPUT_SYSTEM
    var kb = UnityEngine.InputSystem.Keyboard.current;
    if (kb != null && kb.f9Key.wasPressedThisFrame) return true;
#endif
#if ENABLE_LEGACY_INPUT_MANAGER
    if (Input.GetKeyDown(KeyCode.F9)) return true;
#endif
    return false;
}
#endif'
assert_eq "$(verdict /proj/Assets/Core/Debug/PerfProbe.cs "$DUAL")" "0" "allows a correctly-guarded ENABLE_INPUT_SYSTEM/ENABLE_LEGACY dual path"

# Vendored code. Feel/MoreMountains alone ships 16 files using legacy input into
# Assets/Extensions/. They must never be edited, so blocking them teaches you to
# ignore the hook.
for p in /proj/Assets/Extensions/Feel/MMInput.cs /proj/Assets/Plugins/Thing/X.cs /proj/Assets/PlayerPrefsEditor/Y.cs; do
  assert_eq "$(verdict "$p" "void U(){ if(Input.GetKey(KeyCode.A)) {} }")" "0" "ignores vendored code: ${p#/proj/Assets/}"
done

# Clean code and non-C# files.
assert_eq "$(verdict /proj/Assets/Scripts/Clean.cs 'void Update(){ _controls.Player.Move.ReadValue<Vector2>(); }')" "0" "allows New Input System code"
assert_eq "$(verdict /proj/Assets/Scripts/notes.md 'Input.GetKey is banned')" "0" "ignores non-C# files"
# `_playerInput` / `inputAction` must not trip a naive /Input\./ match.
assert_eq "$(verdict /proj/Assets/Scripts/View.cs 'private PlayerInput _playerInput; void A(){ _playerInput.enabled = true; }')" "0" "does not false-positive on PlayerInput members"

# --- the claim the rules make must stay true -------------------------------
assert_eq "$(grep -c 'block-legacy-input.sh' "$PROJECT_ROOT/.claude/settings.json" || true)" "1" "hook is wired into settings.json"

echo ""
echo "test-block-legacy-input: $TESTS_PASSED/$TESTS_RUN passed"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
