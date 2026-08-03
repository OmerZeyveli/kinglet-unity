#!/usr/bin/env bash
# ============================================================================
# test-rule-applicability.sh — the generated CLAUDE.md must state which rules
# bind, based on what the project actually contains, and must never assert a
# stack it did not detect.
#
# Why this exists: measured in Endless-Evolution/Assets on 2026-08-03 —
# VContainer 0 files, MessagePipe 0, UniTask 1, against 130 using
# StartCoroutine, while .claude/rules/architecture.md mandates the first three.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GEN="$PROJECT_ROOT/scripts/generate-claude-md.sh"
MK="$PROJECT_ROOT/tests/fixtures/mkproject.sh"
TMP="${TMPDIR:-/tmp}/kinglet-rule-applicability.$$"
trap 'rm -rf "$TMP"' EXIT

TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
assert_eq() {
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$1" = "$2" ]; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"
    else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (expected '$2', got '$1')"; fi
}
# grep -qF on a here-string, never on a pipe: grep -q exits on first match without
# draining stdin, and under pipefail that SIGPIPEs the writer. See CLAUDE.md.
assert_has() {
    TESTS_RUN=$((TESTS_RUN+1))
    if grep -qF -- "$2" <<< "$1"; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"
    else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (missing '$2')"; fi
}
assert_lacks() {
    TESTS_RUN=$((TESTS_RUN+1))
    if grep -qF -- "$2" <<< "$1"; then TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (unexpectedly found '$2')"
    else TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"; fi
}

echo ""
echo "=== Rule Applicability Tests ==="
echo ""

# ── Case 1: legacy project — the stack is absent and code exists ───────────
echo "--- Case: stack absent, first-party code present ---"
bash "$MK" "$TMP/legacy" --variant legacy >/dev/null
OUT_LEGACY="$(bash "$GEN" "$TMP/legacy" 2>/dev/null)"
assert_has "$OUT_LEGACY" "Architecture stack" "legacy project emits the stack section"
assert_has "$OUT_LEGACY" "do not bind" "legacy project says the architecture rules do not bind"
assert_has "$OUT_LEGACY" "architecture.md" "legacy project names the rule file it is disapplying"
assert_lacks "$OUT_LEGACY" "recommended for this new project" "legacy project is not treated as greenfield"

# The vendored file under Assets/Extensions/ references VContainer and UniTask. If the
# scan counted it, VC_REFS would be 1 and this row would read "yes (1 file(s))".
#
# Match the whole rendered row, not a loose two-word phrase. An earlier draft of this
# plan asserted the absence of "VContainer yes", which the emitted format — pipe, space,
# value — can never contain, so it passed whether or not detection was broken. This
# assertion is the only guard on the vendored-file trap in the fixture; it has to be able
# to fail.
assert_has "$OUT_LEGACY" "| VContainer | no (0 file(s)) |" \
    "vendored code does not count as the project using the stack"
assert_has "$OUT_LEGACY" "| UniTask | no (0 file(s)) |" \
    "vendored UniTask reference does not count either"

# ── Case 2: urp fixture — VContainer and UniTask are in the manifest ───────
echo ""
echo "--- Case: stack present in the manifest ---"
bash "$MK" "$TMP/urp" --variant urp >/dev/null
OUT_URP="$(bash "$GEN" "$TMP/urp" 2>/dev/null)"
assert_has "$OUT_URP" "Architecture stack" "urp project emits the stack section"
assert_lacks "$OUT_URP" "do not bind" "urp project does not disapply the architecture rules"

# ── Case 3: bare fixture — no scripts at all ──────────────────────────────
echo ""
echo "--- Case: greenfield ---"
bash "$MK" "$TMP/bare" --variant bare >/dev/null
OUT_BARE="$(bash "$GEN" "$TMP/bare" 2>/dev/null)"
assert_has "$OUT_BARE" "recommended for this new project" "greenfield says recommended, not detected"
assert_lacks "$OUT_BARE" "do not bind" "greenfield does not disapply anything"

# ── Case 4: --facts-only and full generation agree inside the markers ──────
# This is the regression fixed in 89c661c. The new section lives inside the
# marked region, so it is exactly the kind of content that can drift again.
echo ""
echo "--- Case: --facts-only matches the marked region byte for byte ---"
FACTS="$(bash "$GEN" --facts-only "$TMP/legacy" 2>/dev/null)"
REGION="$(bash "$GEN" "$TMP/legacy" 2>/dev/null \
    | awk '/kinglet:generated:begin/{f=1;next} /kinglet:generated:end/{f=0} f')"
assert_eq "$FACTS" "$REGION" "--facts-only equals the marked region of a full generation"

# ── Case 5: stdout/stderr contract ────────────────────────────────────────
echo ""
echo "--- Case: log lines never contaminate the document ---"
ERRTXT="$(bash "$GEN" "$TMP/legacy" 2>&1 >/dev/null)"
assert_has "$ERRTXT" "[INFO]" "info lines go to stderr"
assert_lacks "$OUT_LEGACY" "[INFO]" "info lines are absent from stdout"

echo ""
echo "=== Rule Applicability: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed ==="
[ "$TESTS_FAILED" -eq 0 ]
