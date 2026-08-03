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

# The legacy fixture carries Plain.cs, which matches none of the four scanned symbols — the
# common case on a real project. `set -e` + `pipefail` + a grep that exits 1 on no-match killed
# the generator outright on such a file: rc 1, zero lines of document. install.sh calls the
# generator with 2>/dev/null, so the field symptom was one warning and no CLAUDE.md.
#
# Capture rc separately from the output: `$(...)` inside `set -e` would abort this test file.
GEN_RC=0
OUT_LEGACY="$(bash "$GEN" "$TMP/legacy" 2>/dev/null)" || GEN_RC=$?
assert_eq "$GEN_RC" "0" "generator survives a .cs file matching none of the scanned symbols"
assert_has "$OUT_LEGACY" "Scanned \`Assets/\` (vendored subtrees excluded), 3 first-party C# file(s)" \
    "the non-matching file is still counted in CS_FILE_COUNT"

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

# ── Case 2: urp fixture — VContainer in manifest AND source, UniTask manifest-only ──
#
# This case previously asserted only "Architecture stack" is present and "do not bind" is
# absent, against a fixture with zero .cs files. CS_FILE_COUNT was 0, emit_stack_verdict
# returned at the greenfield early exit, and the output was byte-identical to Case 3's. The
# manifest was never consulted: manifest_has(), present(), the `manifest-only` third state and
# the "binds in full" branch all had zero coverage. Deleting the body of present() and
# returning a constant would not have turned this suite red.
#
# The fixture now carries GameLifetimeScope.cs. Assert the rendered rows, the way Case 1 does.
echo ""
echo "--- Case: stack present in the manifest and in source ---"
bash "$MK" "$TMP/urp" --variant urp >/dev/null
OUT_URP="$(bash "$GEN" "$TMP/urp" 2>/dev/null)"
assert_has "$OUT_URP" "Architecture stack" "urp project emits the stack section"
assert_lacks "$OUT_URP" "do not bind" "urp project does not disapply the architecture rules"
assert_lacks "$OUT_URP" "recommended for this new project" "urp project is not treated as greenfield"

assert_has "$OUT_URP" "| VContainer | yes (1 file(s)) |" \
    "manifest + first-party use renders as yes with the file count"
assert_has "$OUT_URP" "| UniTask | manifest-only (0 file(s)) |" \
    "declared-but-unused renders as the manifest-only third state"
assert_has "$OUT_URP" "| MessagePipe | no (0 file(s)) |" \
    "neither declared nor used renders as no"
assert_has "$OUT_URP" '`.claude/rules/architecture.md` **binds in full.**' \
    "VContainer in use makes architecture.md bind in full"

# Finding 4: manifest-only UniTask used to fall into the else arm asserting that neither
# UniTask nor StartCoroutine appears — contradicting the table row printed just above it.
assert_has "$OUT_URP" "UniTask is declared in \`Packages/manifest.json\` but used in no first-party file," \
    "manifest-only UniTask gets its own async arm"
assert_lacks "$OUT_URP" "Neither UniTask nor" \
    "manifest-only UniTask is never described as absent"

# ── Case 2b: architecture in the manifest only — the third state, end to end ──
# VContainer declared, used nowhere. The generator must take no side AND say what binds
# meanwhile, rather than leaving the reader between two documents that defer to each other.
echo ""
echo "--- Case: architecture declared but unused ---"
cp -R "$TMP/urp" "$TMP/manifest-only"
rm -f "$TMP/manifest-only/Assets/Scripts/GameLifetimeScope.cs"
cat > "$TMP/manifest-only/Assets/Scripts/Plain.cs" <<'CS'
using UnityEngine;
public class Plain : MonoBehaviour { private void Update() { } }
CS
OUT_MO="$(bash "$GEN" "$TMP/manifest-only" 2>/dev/null)"
assert_has "$OUT_MO" "| VContainer | manifest-only (0 file(s)) |" \
    "declared-but-unused VContainer renders as manifest-only"
assert_has "$OUT_MO" "**This generator takes no side.**" "manifest-only architecture takes no side"
assert_has "$OUT_MO" "**held in abeyance**" \
    "manifest-only says what happens to the MVS/DI sections meanwhile"
assert_has "$OUT_MO" "\`serialization.md\` **bind**" \
    "manifest-only names the architecture-agnostic rules that bind meanwhile"

# ── Case 3: bare fixture — no scripts at all ──────────────────────────────
echo ""
echo "--- Case: greenfield ---"
bash "$MK" "$TMP/bare" --variant bare >/dev/null
OUT_BARE="$(bash "$GEN" "$TMP/bare" 2>/dev/null)"
assert_has "$OUT_BARE" "recommended for this new project" "greenfield says recommended, not detected"
assert_lacks "$OUT_BARE" "do not bind" "greenfield does not disapply anything"
assert_has "$OUT_BARE" "there is no \`Packages/manifest.json\` to" \
    "greenfield with no manifest says so rather than claiming a blank slate"

# ── Case 3b: greenfield with a manifest that already declares the stack ────
# Finding 5a: "nothing is detected and nothing is contradicted" was an overclaim. The manifest
# is read long before this point, and a project declaring VContainer is not a blank slate.
echo ""
echo "--- Case: greenfield with declarations in the manifest ---"
cp -R "$TMP/urp" "$TMP/greenfield-declared"
rm -f "$TMP/greenfield-declared/Assets/Scripts/GameLifetimeScope.cs"
OUT_GFD="$(bash "$GEN" "$TMP/greenfield-declared" 2>/dev/null)"
assert_has "$OUT_GFD" "recommended for this new project" "still greenfield with no code"
assert_has "$OUT_GFD" "already declares **VContainer, UniTask**" \
    "greenfield names what the manifest already declares"
# The needle stops at "nothing is" on purpose: the emitted text wraps between "is" and
# "contradicted", so the full sentence as one string can never match and the assertion could
# never fail. That is the exact defect this review wave was called to fix.
assert_lacks "$OUT_GFD" "nothing is detected and nothing is" \
    "greenfield with declarations does not claim a blank slate"

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

# ── Case 6: the static tail does not contradict the detected section ───────
# The Engineering Stance block is emitted once, outside the markers, and never
# refreshed. If it asserts the stack unconditionally it will permanently
# contradict the section Task 1 emits.
echo ""
echo "--- Case: static Engineering Stance defers to detection ---"
assert_lacks "$OUT_LEGACY" "Model-View-System (MVS) with **VContainer**" \
    "Engineering Stance does not assert the stack unconditionally"
assert_has "$OUT_LEGACY" "Architecture stack — detected, not assumed" \
    "Engineering Stance points at the detected section"

# ── Case 7: provider declaration ──────────────────────────────────────────
echo ""
echo "--- Case: provider declaration ---"
OUT_PROV="$(bash "$GEN" --provider superpowers "$TMP/legacy" 2>/dev/null)"
assert_has "$OUT_PROV" "owned by \`superpowers\`" "declared provider is named"
assert_has "$OUT_PROV" "/unity-interview" "the surface that yields is named"
assert_lacks "$OUT_LEGACY" "owned by" "no provider flag means no sentence"

# The sentence lives inside the markers, so a --facts-only refresh must carry it.
FACTS_PROV="$(bash "$GEN" --facts-only --provider superpowers "$TMP/legacy" 2>/dev/null)"
assert_has "$FACTS_PROV" "owned by \`superpowers\`" "--facts-only carries the provider sentence"

# ── Case 8: UniTask named AND coroutines used — neither side wins ─────────
#
# Found by running the shipped generator against a real 492-file project: ONE file named
# UniTask (a documentation spec that mentions the word in an assertion string) against 38
# genuinely using StartCoroutine, and the output declared the no-coroutines rule BINDING —
# the opposite of what that code does. The branch tested UT_PRESENT alone and never
# consulted COROUTINE_FILES. No fixture had both signals at once, so five reviews and a
# green suite all missed it.
echo ""
echo "--- Case: UniTask named and coroutines used — takes no side ---"
bash "$MK" "$TMP/async-mixed" --variant async-mixed >/dev/null
OUT_AM="$(bash "$GEN" "$TMP/async-mixed" 2>/dev/null)"
assert_has "$OUT_AM" "| UniTask | yes (1 file(s)) |" \
    "the lone UniTask reference is still counted and shown"
assert_has "$OUT_AM" "Mixed: 1 file(s) name UniTask and 2 use \`StartCoroutine\`." \
    "both signals are reported with their counts"
assert_has "$OUT_AM" "**This generator takes no side** on the \"No Coroutines" \
    "neither side is declared the winner"
assert_lacks "$OUT_AM" "\`unity-specifics.md\` **binds.**" \
    "one reference does not make the no-coroutines rule bind"
assert_lacks "$OUT_AM" "UniTask is not in use" \
    "and it is not declared absent either"

echo ""
echo "=== Rule Applicability: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed ==="
[ "$TESTS_FAILED" -eq 0 ]
