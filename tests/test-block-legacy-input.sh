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

# ============================================================================
# 2026-08-13 — the gate must block the act and permit the prose.
#
# `Input\.` had no left boundary, so it matched inside any identifier ending in
# "Input". The assertion above about `_playerInput` passed for the wrong reason:
# it never names a legacy METHOD, so the pattern could not have fired on it
# whatever the boundary. A wrapper that does — MyInput.GetKey, XRInput.GetAxis —
# was blocked, and those are the files a real project is full of.
#
# Both directions for each, because a boundary that is slightly wrong turns a
# false positive into a false negative, and a gate that stops blocking the act is
# worse than one that blocks prose. rules/unity-specifics.md states in bold that
# this API is BLOCKED by hooks; the "still blocks" half is what keeps that true.
# ============================================================================

WRAPPED='using UnityEngine;
public class P : MonoBehaviour { void Update(){ if (MyInput.GetKeyDown(KeyCode.A)) {} } }'
assert_eq "$(verdict /proj/Assets/Scripts/P.cs "$WRAPPED")" "0" "does not block MyInput.GetKeyDown — a wrapper, not the legacy API"
assert_eq "$(verdict /proj/Assets/Scripts/X.cs 'void U(){ var v = XRInput.GetAxis("Move"); }')" "0" "does not block XRInput.GetAxis"
assert_eq "$(verdict /proj/Assets/Scripts/S.cs 'void U(){ if (SteamInput.GetButton(0)) {} }')" "0" "does not block SteamInput.GetButton"

# Editor and test folders. Editor/ is Unity's own semantics — a folder of that
# name at any depth compiles into the Editor assembly and ships in no player
# build. Tests/ is convention, and is the weaker of the two: Unity excludes test
# ASSEMBLIES, not folders named Tests. Both are exempt because this hook's scope
# is first-party RUNTIME code, which is what its header and HOOK-REFERENCE.md say.
LEGACY_CALL='void U(){ if (Input.GetKeyDown(KeyCode.F9)) {} }'
assert_eq "$(verdict /proj/Assets/Editor/BuildTool.cs "$LEGACY_CALL")" "0" "does not block editor-only tooling under Editor/"
assert_eq "$(verdict /proj/Assets/Scripts/Editor/Win.cs "$LEGACY_CALL")" "0" "does not block a nested Editor/ folder"
assert_eq "$(verdict /proj/Assets/A/B/Editor/Deep.cs "$LEGACY_CALL")" "0" "does not block an Editor/ folder nested several levels down"
assert_eq "$(verdict /proj/Assets/Tests/PlayMode/InputTests.cs "$LEGACY_CALL")" "0" "does not block test code under Tests/"
assert_eq "$(verdict /proj/Assets/Scripts/Tests/EditMode/T.cs "$LEGACY_CALL")" "0" "does not block a nested Tests/ folder"

# The skip is anchored under Assets/, and these three are why. FILE_PATH is absolute, so an
# unanchored */Tests/* matched every runtime file in a checkout that happens to live under a
# directory named Tests — an ordinary place to keep one. Measured before the anchor: all three
# went from blocked to allowed, which switches this gate off for a whole project at once.
# The bug is about what precedes Assets/, so a corrected relative path would not have caught it.
assert_eq "$(verdict /home/dev/Tests/MyGame/Assets/Scripts/Player.cs "$LEGACY_CALL")" "2" "still blocks when the CHECKOUT sits under a directory named Tests"
assert_eq "$(verdict /home/dev/Editor/MyGame/Assets/Scripts/Player.cs "$LEGACY_CALL")" "2" "still blocks when the checkout sits under a directory named Editor"
assert_eq "$(verdict /Users/dev/Projects/Tests/Game/Assets/Scripts/Enemy.cs "$LEGACY_CALL")" "2" "still blocks a Tests directory anywhere above the project root"

# The skip is a path SEGMENT, not a substring: EditorTools/ is runtime code.
assert_eq "$(verdict /proj/Assets/Scripts/EditorTools/Live.cs "$LEGACY_CALL")" "2" "still blocks EditorTools/ — a segment named Editor is not a prefix of one"
assert_eq "$(verdict /proj/Assets/Scripts/Q.cs 'void U(){ var v = UnityEngine.Input.GetAxis("Horizontal"); }')" "2" "still blocks the fully-qualified UnityEngine.Input.GetAxis"
MIXED='void U(){ var a = MyInput.GetKey(KeyCode.A); var b = Input.GetAxis("Horizontal"); }'
assert_eq "$(verdict /proj/Assets/Scripts/M.cs "$MIXED")" "2" "still blocks a real call sharing a file with a wrapper call"

# The report names the API, not the character the boundary had to consume.
found_of() {  # $1 = file path, $2 = content — prints the reported API list
  local out
  set +e
  out=$(printf '{"tool_input":{"file_path":%s,"new_string":%s}}' \
        "$(printf '%s' "$1" | jq -Rs .)" "$(printf '%s' "$2" | jq -Rs .)" \
        | bash "$HOOK" 2>&1 >/dev/null | grep 'Legacy Input Manager API:')
  set -e
  printf '%s' "${out##*API: }"
}
assert_eq "$(found_of /proj/Assets/Scripts/M2.cs "$MIXED")" "Input.GetAxis " "reports the API alone, and only the call that is really it"

# --- the claim the rules make must stay true -------------------------------
assert_eq "$(grep -c 'block-legacy-input.sh' "$PROJECT_ROOT/.claude/settings.json" || true)" "1" "hook is wired into settings.json"

echo ""
echo "test-block-legacy-input: $TESTS_PASSED/$TESTS_RUN passed"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
