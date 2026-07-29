#!/usr/bin/env bash
# ============================================================================
# test-input-system-check.sh — the mandated input package must be checked for.
#
# unity-specifics.md makes the New Input System non-negotiable and a hook
# blocks the legacy API. A project without com.unity.inputsystem therefore
# cannot compile the first script written under its own rules — and a compile
# error also aborts Unity's -executeMethod, so Editor automation stops too.
# ============================================================================

TIS_MOCK="/tmp/kinglet-input-check-$$"
mkdir -p "${TIS_MOCK}/Assets" "${TIS_MOCK}/ProjectSettings" "${TIS_MOCK}/Packages"
printf 'm_EditorVersion: 6000.3.18f1\nm_EditorVersionWithRevision: 6000.3.18f1 (abcdef123456)\n' \
    > "${TIS_MOCK}/ProjectSettings/ProjectVersion.txt"
printf '{\n  "dependencies": {\n    "com.unity.ugui": "1.0.0"\n  }\n}\n' \
    > "${TIS_MOCK}/Packages/manifest.json"

TIS_OUT=$(bash "${REPO_DIR}/install.sh" --project-dir "$TIS_MOCK" 2>&1 || true)
assert_contains "$TIS_OUT" "com.unity.inputsystem" \
    "install warns when the mandated input package is absent"

# Present: no warning, because a warning nobody needs is a warning nobody reads.
rm -rf "${TIS_MOCK}/.claude"
printf '{\n  "dependencies": {\n    "com.unity.inputsystem": "1.18.0"\n  }\n}\n' \
    > "${TIS_MOCK}/Packages/manifest.json"
TIS_OUT2=$(bash "${REPO_DIR}/install.sh" --project-dir "$TIS_MOCK" 2>&1 || true)
assert_not_contains "$TIS_OUT2" "com.unity.inputsystem is missing" \
    "install stays quiet when the input package is already present"

rm -rf "$TIS_MOCK"
