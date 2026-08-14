#!/usr/bin/env bash
# ============================================================================
# test-asmdef-coverage.sh — scripts/validate-asmdefs.sh understands `.asmref`
#
# WHAT THIS GUARDS, AND WHY IT DID NOT EXIST BEFORE.
#
# A Unity `.asmref` file adds its enclosing folder subtree to an assembly defined somewhere else.
# Unity treats that subtree as covered; until 2026-08-14 validate-asmdefs.sh counted every file in it
# as uncovered, because the whole toolkit had never heard of the extension — `grep -rn asmref` over
# scripts/ and .claude/ returned nothing at all. Measured on a real shipping project with 12 .asmdef
# and 29 .asmref: **21 warnings naming 800 files, every one false.**
#
# That defect survived every prior suite run for exactly one reason: no fixture in this repository
# contained an `.asmref`, so there was no input on which a correct and an incorrect implementation
# could differ. This file plus the `asmref` variant of tests/fixtures/mkproject.sh are the missing
# input. Neither is worth anything without the other.
#
# THE TWO NUMBERS BELOW ARE PROPERTIES OF THE FIXTURE, NOT OF THE TREE, so pinning them here is not
# the hardcoded-count failure CLAUDE.md warns about — mkproject.sh's `asmref` arm writes exactly
# these files and its comment block says so. They are:
#
#   2  uncovered with .asmref support   — Assets/Loose/Uncovered.cs (under no assembly file at all)
#                                         and Assets/World LevelExtra/Sibling.cs (a sibling whose
#                                         name has a covered directory's name as a prefix)
#   6  uncovered without it             — the same 2 plus the 4 the .asmref files cover
#
# THE CONTROL IS THE POINT. Test 7 rebuilds the fixture with every `.asmref` deleted and requires 6.
# A coverage count that falls to 0 because the *sweep* broke is indistinguishable from one that falls
# because the *fix* worked — this repository's own EE measurement went 800 -> 0 and both stories fit.
# The control separates them: a dead sweep reports 0 on the stripped fixture too, and 0 != 6.
#
# SELF-CONTAINED IDIOM. Own helpers, own `set -euo pipefail`, no use of the runner's assert_* or
# $REPO_DIR. `bash tests/test-asmdef-coverage.sh` is a valid way to run it and really does assert.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"
VALIDATOR="$REPO/scripts/validate-asmdefs.sh"
MK="$REPO/tests/fixtures/mkproject.sh"

TESTS_PASSED=0; TESTS_FAILED=0
pass() { TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $1"; }
fail() { TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $1"; }
skip() { echo "SKIP: $1"; }

# Here-string, never `echo "$hay" | grep -q`. grep -q exits on first match without draining stdin;
# with a live writer upstream that becomes SIGPIPE, pipefail promotes 141, and a needle that IS
# present is reported absent. This repository has three implementers' worth of history on that one.
contains() { grep -qF -- "$2" <<< "$1"; }

assert_contains() {
    if contains "$1" "$2"; then pass "$3"; else fail "$3 — needle absent: $2"; fi
}
assert_absent() {
    if contains "$1" "$2"; then fail "$3 — needle present but should not be: $2"; else pass "$3"; fi
}
assert_eq() {
    if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$1', got '$2')"; fi
}

echo ""
echo "=== validate-asmdefs.sh: .asmref coverage ==="
echo ""

if ! command -v jq >/dev/null 2>&1; then
    skip "jq is not installed; validate-asmdefs.sh cannot run and neither can this file"
    echo ""
    echo "=== asmref coverage: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed ==="
    exit 0
fi

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# ── Build the fixture ─────────────────────────────────────────────────────
PROJ="$SCRATCH/asmref-project"
mk_rc=0
bash "$MK" "$PROJ" --variant asmref >/dev/null 2>"$SCRATCH/mk.err" || mk_rc=$?
if [ "$mk_rc" -ne 0 ] || [ ! -d "$PROJ/Assets" ] || [ ! -d "$PROJ/ProjectSettings" ]; then
    fail "mkproject.sh --variant asmref exited $mk_rc without producing a project; every assertion below would describe a directory that was never built: $(tr '\n' ' ' < "$SCRATCH/mk.err")"
    echo ""
    echo "=== asmref coverage: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed ==="
    exit 1
fi

# The validator locates the project by walking up from $PWD, so it must be run from inside one.
run_validator() {
    ( cd "$1" && bash "$VALIDATOR" 2>&1 )
}

# Pull the uncovered file count out of the report. Both wordings are read, because "0" is printed as
# prose ("All C# files are covered …") and not as a number — a parser that only knew the numeric line
# would silently yield the empty string on a clean project and compare equal to nothing.
uncovered_count_of() {
    awk '
        /file\(s\) without assembly definition or reference coverage/ { print $1; found = 1 }
        /All C# files are covered by an assembly definition or reference/ { print 0; found = 1 }
        END { if (!found) print "NO-COUNT-LINE" }
    ' <<< "$1"
}

OUT="$(run_validator "$PROJ")"

# ── Test 0: floors, before anything reads $OUT ────────────────────────────
# C2(g). Four of the assertions below are `assert_absent`, whose passing condition is silence, and
# silence is exactly what an empty $OUT produces. This is the floor under them: the validator ran and
# said something. (Tests 2 and 5 are positive assertions over the same string and would also red on
# an empty one — stated here as a floor rather than left as a side effect, because a later edit that
# turned those into absence checks would remove the protection without touching this line.)
assert_contains "$OUT" "=== Assembly Definition Validation ===" \
    "the validator produced a report at all — the floor under every assert_absent below"

# ── Test 1: the fixture really contains both reference forms ──────────────
# Asserted against the fixture rather than assumed, because every assertion below is only as good as
# the input. A fixture that silently stopped writing .asmref files would make tests 2-6 vacuous.
ASMREF_N=$(/usr/bin/find "$PROJ/Assets" -name '*.asmref' | wc -l | tr -d ' ')
assert_eq "4" "$ASMREF_N" "fixture writes 4 .asmref files"
# `|| true` on the assignment, not inside the pipeline. grep exits 1 when it matches nothing, and
# under `set -euo pipefail` that kills the file — which is what happened the first time this floor
# was exercised: a fixture stripped of its .asmref files fired the floor above and then aborted the
# run, so 18 further assertions vanished and only the one FAIL was ever printed. The floor must be
# able to red without taking the rest of the file with it. `wc -l` drains its input fully, so there
# is no early-exit reader here.
NAME_FORM=$(/usr/bin/grep -rl --include='*.asmref' -- '"reference":"Game\.' "$PROJ/Assets" | wc -l | tr -d ' ') || true
GUID_FORM=$(/usr/bin/grep -rl --include='*.asmref' -- '"reference":"GUID:' "$PROJ/Assets" | wc -l | tr -d ' ') || true
assert_eq "2" "$NAME_FORM" "fixture carries the name form of .asmref (both forms occur in the wild)"
assert_eq "2" "$GUID_FORM" "fixture carries the GUID form of .asmref"

# ── Test 2: the script counts the references it found ─────────────────────
assert_contains "$OUT" "Found 4 assembly reference(s)." "validator reports the .asmref files it found"

# ── Test 3: name-form and GUID-form subtrees are covered ──────────────────
# LevelThing.cs sits under a name-form .asmref, VendorThing.cs under a GUID-form one. Before
# 2026-08-14 both were reported uncovered. The GUID case is the one that needs the .meta lookup: the
# guid lives in Gameplay.asmdef.meta, never inside the .asmdef.
assert_absent "$OUT" "coverage: Assets/World Level/LevelThing.cs" \
    "a subtree claimed by a name-form .asmref is covered"
assert_absent "$OUT" "coverage: Assets/Extras/DNA Forms/VendorThing.cs" \
    "a subtree claimed by a GUID-form .asmref is covered (guid resolved through the .asmdef.meta)"

# ── Test 4: paths containing spaces survive ───────────────────────────────
# "World Level" and "DNA Forms" are transcribed from the real project. An unquoted
# `for f in $(find …)` splits each into two nonexistent paths — that broke a probe while this finding
# was being gathered. Test 3 above already depends on both, so a splitting implementation cannot
# reach here green; this asserts the discriminating half directly.
assert_contains "$OUT" "Assets/World LevelExtra/Sibling.cs" \
    "a space-bearing path is reported whole, not split into fragments"

# ── Test 5: real uncovered files are still reported ───────────────────────
# The true positives. Suppressing the false warnings by suppressing the check would take these with
# them, and that is the failure mode this pair exists to catch.
assert_contains "$OUT" "No .asmdef/.asmref coverage: Assets/Loose/Uncovered.cs" \
    "a file under no assembly file at all is still reported uncovered"
assert_contains "$OUT" "No .asmdef/.asmref coverage: Assets/World LevelExtra/Sibling.cs" \
    "a sibling directory whose name merely has a covered directory's name as a prefix is not treated as covered"
assert_eq "2" "$(uncovered_count_of "$OUT")" "exactly the 2 genuinely uncovered files are counted"

# ── Test 6: an unresolvable reference is reported, in both forms ──────────
# Reported once, by path, rather than being silently skipped — and rather than being re-reported once
# per C# file underneath, which on the measured project would have restored hundreds of warnings from
# a single broken third-party .asmref. The subtree still counts as covered; the reference is what is
# broken and it is named on its own line.
assert_contains "$OUT" "Unresolvable .asmref: Assets/Dangling/Broken.asmref" \
    "an unresolvable GUID-form reference is reported by path"
assert_contains "$OUT" "Unresolvable .asmref: Assets/DanglingName/BrokenName.asmref" \
    "an unresolvable name-form reference is reported by path"
assert_absent "$OUT" "coverage: Assets/Dangling/Orphan.cs" \
    "a dangling .asmref still claims its subtree, so the one defect is reported once and not once per file"

# AND THE OTHER DIRECTION, WHICH IS THE ONE THAT NEARLY GOT AWAY. Because a dangling .asmref still
# grants coverage (see above), *every* coverage assertion in tests 3 and 6 stays green over a
# resolver that always fails — measured: stubbing the GUID lookup to match nothing left this file at
# 18 pass / 0 fail. Coverage is simply not evidence that a reference resolved. The warning total is:
# 2 unresolvable + 2 uncovered and nothing else, so a resolver that starts failing on either form
# pushes it to 5. That identity is what makes tests 3 and 6 mean what their names say.
WARN_N=$(awk -F: '/^  Warnings /{ gsub(/[^0-9]/, "", $2); print $2 }' <<< "$OUT")
assert_eq "4" "$WARN_N" \
    "exactly 4 warnings — 2 unresolvable references plus 2 uncovered files, and nothing else"
assert_absent "$OUT" "Unresolvable .asmref: Assets/Extras/Vendor.asmref" \
    "a GUID reference that DOES resolve is not reported unresolvable"
assert_absent "$OUT" "Unresolvable .asmref: Assets/World Level/Game.Gameplay.asmref" \
    "a name reference that DOES resolve is not reported unresolvable"

# ── Test 7: the control — strip the .asmref files and the 4 come back ─────
# DISCOVERY INTEGRITY. Everything above is consistent with a sweep that reads nothing: a validator
# that never opened a single .cs file would satisfy every `assert_absent` in tests 3 and 6, and the
# EE measurement this change is built on went 800 -> 0, a shape that a dead sweep produces exactly as
# well as a correct one. This control removes only the .asmref files and requires the count to climb
# back to 6 — the pre-fix answer, measured against the pre-fix script on this same fixture. A dead
# sweep reports 0 here and goes red; a fix that grants coverage to everything reports 0 too.
STRIPPED="$SCRATCH/asmref-stripped"
bash "$MK" "$STRIPPED" --variant asmref >/dev/null 2>&1
/usr/bin/find "$STRIPPED/Assets" -name '*.asmref' -delete
STRIP_N=$(/usr/bin/find "$STRIPPED/Assets" -name '*.asmref' | wc -l | tr -d ' ')
assert_eq "0" "$STRIP_N" "control fixture has had every .asmref removed"
OUT_STRIPPED="$(run_validator "$STRIPPED")"
assert_eq "6" "$(uncovered_count_of "$OUT_STRIPPED")" \
    "without the .asmref files the same tree reports 6 uncovered — so the drop to 2 is the fix, not a sweep that stopped reading"
assert_contains "$OUT_STRIPPED" "Found 0 assembly reference(s)." \
    "the control run sees no references, which is what makes its 6 the pre-fix answer"

# ── Test 8: warnings do not turn into a failing exit ──────────────────────
# The script's documented contract: errors exit 1, warnings exit 0. Both fixtures produce warnings
# and no errors.
set +e
( cd "$PROJ" && bash "$VALIDATOR" >/dev/null 2>&1 ); PROJ_RC=$?
set -e
assert_eq "0" "$PROJ_RC" "a project with warnings and no errors still exits 0"

echo ""
echo "=== asmref coverage: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed ==="
echo ""

[ "$TESTS_FAILED" -eq 0 ]
