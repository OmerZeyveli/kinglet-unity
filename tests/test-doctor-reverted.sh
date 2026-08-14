#!/usr/bin/env bash
# ============================================================================
# test-doctor-reverted.sh — the doctor stops repeating a claim the receipt cannot support.
#
# THE DEFECT. scripts/studio-doctor.sh classified a `user-modified` receipt row by the COLUMN ALONE
# and never compared any bytes. A `user-modified` row means "a past install found your edit and kept
# it" — it is a record of what a run once saw, and nothing in it can express that the user has since
# put the file back. So a file byte-identical to the toolkit's own copy was reported under
# `N file(s) modified since install` for the life of the project. Measured 2026-08-14 on a
# --variant urp fixture, install → edit → install → revert to the toolkit's exact bytes:
# `WARN 1 file(s) modified since install` about a file with no difference from the shipped one.
#
# WHY THE ROW'S CHECKSUM CANNOT ANSWER IT, which is what makes a second reference necessary rather
# than merely convenient. The row records the file AS EDITED, so before a reinstall the recorded sha
# is the edited sha and the disk no longer matches; after a reinstall the row records the REVERTED
# bytes and the disk matches again. Both states are the same state, and neither comparison mentions
# the toolkit. Only the shipped copy discriminates — which the doctor has only when --toolkit-dir
# names a checkout, and an installed project has no second copy of the payload at all.
#
# SO THE FIX HAS TWO HALVES AND BOTH ARE ASSERTED HERE: with a checkout, the file is reported as
# reverted; without one, the run SAYS the column alone decided, rather than repeating the claim.
#
# WHAT THIS FILE ASSERTS
#   1  the fixture reaches the state           row is `user-modified`, bytes are the toolkit's
#   2  no checkout                             still `modified`, plus the boundary-of-evidence lines
#   3  --toolkit-dir                           reported as reverted, and NOT as modified
#   4  auto-detect from a checkout             the same, with no flag passed
#   5  the `.claude/scripts/` reference root   resolves here too — the other of install.sh's two
#   6  a LIVE edit, with a checkout            still modified: the anti-"everything is reverted" arm
#   7  the summary line, on every run above    Task 3's `/unity-doctor` contract survives the change
#   8  --toolkit-dir's own argument handling   a missing value and a non-checkout both exit 2
#
# WHAT THIS FILE CANNOT SEE
#   * install.sh's side of the same comparison. tests/test-install-ownership.sh states R…R4 own it,
#     and the two implementations are separate code in separate files — nothing here would notice
#     them disagreeing about a file, only that each is self-consistent.
#   * One reverted file per state. Several at once, and any interaction with the unreadable-origin
#     bucket, are untested.
#   * Project-root rows (.mcp.json, MCP-SETUP.md, CLAUDE.md.generated). No install.sh writer emits a
#     `user-modified` row for any of them, so no fixture can put one in front of this classifier.
#   * The auto-detected default is exercised only in the direction that finds a checkout. The
#     direction that must find NOTHING — an installed project, where `dirname $0`/.. is
#     <project>/.claude — is covered implicitly by assertion 2 running the project's own copy, and
#     would go red there as a false "reverted" rather than by name.
#   * Anything about Claude Code. This drives a shell script against a synthetic project.
# ============================================================================
# Self-contained: own `set -euo pipefail`, own pass/fail, REPO from BASH_SOURCE. The runner's
# assert_* helpers are deliberately not used — the runner does `set +e` before sourcing, so an
# undefined helper prints to stderr and contributes no failing token, and this file would report
# green on the defect it exists to catch.
set -euo pipefail

# ${BASH_SOURCE[0]}, not $0: the runner does `( source "$test_file" )`, and inside a sourced file $0
# is the *sourcing* shell's $0.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'PASS: %s\n' "$1"; }

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

REL='.claude/rules/pc-console.md'
SCRIPT_REL='.claude/scripts/detect-pipeline.sh'
SCRIPT_SRC="$REPO/scripts/detect-pipeline.sh"

sha_of() {
  [ -f "$1" ] || return 0
  sha256sum "$1" | cut -d' ' -f1
}

install_into() {
  local d="$1"
  local rc=0
  KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
    bash "$REPO/install.sh" --project-dir "$d" --yes >/dev/null 2>&1 </dev/null || rc=$?
  return 0
}

# doctor <which> <project-dir> [extra args…] — run a doctor and print its output, colours stripped.
# `which` is `project` for the copy install.sh placed at .claude/scripts/ (no checkout above it, so
# nothing to auto-detect) or `checkout` for the repo's own, which does auto-detect. Running the
# wrong one is the difference between assertions 2 and 4, so it is named at every call site.
doctor() {
  local which="$1" d="$2"
  shift 2
  local exe rc=0
  if [ "$which" = project ]; then exe="$d/.claude/scripts/studio-doctor.sh"; else exe="$REPO/scripts/studio-doctor.sh"; fi
  bash "$exe" --project-dir "$d" "$@" 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g' || rc=$?
  return 0
}

# has <haystack> <needle> — substring test with no pipe. `grep -qF` exits the instant it matches
# without draining stdin, so a pipe into it takes SIGPIPE on the writer, pipefail promotes 141, and
# `set -e` kills the file. A here-string is a redirection: there is no writer process to signal.
has() { grep -qF -- "$2" <<< "$1"; }

# doctor_block <output> <header substring> — the 7-space-indented paths print_first_5 emits under a
# header. Which list a path lands in is the claim; a substring test over the whole output cannot see
# it, because the path is present either way.
doctor_block() {
  awk -v needle="$2" '
    index($0, needle) { inb = 1; next }
    inb && /^       / { print; next }
    inb { inb = 0 }
  ' <<< "$1"
}
MOD_HDR='file(s) modified since install'
REV_HDR='file(s) recorded as yours are byte-identical'

# Every run has to reach the end. `/unity-doctor` (.claude/commands/unity-doctor.md) reads the exit
# contract off the SUMMARY LINE and not off the exit status, because the FAIL count moves between
# cases and a missing summary does not — so "summary present ⇒ every check ran" is the property the
# command body rests on, and any new code in the receipt loop can break it by aborting.
assert_finished() {
  if has "$1" 'passed ·'; then
    pass "$2: the run reached its summary line, so every check after the receipt block ran"
  else
    fail "$2: no summary line — the run aborted part-way through, and /unity-doctor reads that as an incomplete health check"
  fi
}

# ── The fixture: a file the user edited and then put back ────────────────────
PROJ="$SCRATCH/reverted"
bash "$REPO/tests/fixtures/mkproject.sh" "$PROJ" --variant urp >/dev/null
install_into "$PROJ"
printf '\n<!-- the user edited this -->\n' >> "$PROJ/$REL"
install_into "$PROJ"
cp "$REPO/$REL" "$PROJ/$REL"

RECEIPT="$PROJ/.claude/state/install-receipt.tsv"
ROW_ORIGIN="$(awk -F'\t' -v w="$REL" '$1 == w { print $4; exit }' "$RECEIPT")"
TOOLKIT_SHA="$(sha_of "$REPO/$REL")"
if [ "$ROW_ORIGIN" = user-modified ]; then
  pass "1: the row still says 'user-modified' — the state the doctor has to read correctly"
else
  fail "1: the row's origin is '$ROW_ORIGIN', so this fixture is not in the state under test and nothing below means anything"
fi
if [ -n "$TOOLKIT_SHA" ] && [ "$(sha_of "$PROJ/$REL")" = "$TOOLKIT_SHA" ]; then
  pass "1: …while the file on disk is byte-for-byte the toolkit's copy"
else
  fail "1: the file on disk is not the toolkit's copy — the revert did not take, and the states below are testing an edited file"
fi

# ── 2: no checkout to compare against, and the run says so ───────────────────
OUT_BARE="$(doctor project "$PROJ")"
assert_finished "$OUT_BARE" "2"
if has "$OUT_BARE" "WARN 1 $MOD_HDR"; then
  pass "2: with no checkout the file is still counted as modified — the fail-closed direction, since nothing was proved"
else
  fail "2: the count under the modified header is not 1 — an unprovable row was moved out of that list on no evidence"
fi
if has "$OUT_BARE" "WARN      1 of those carry a 'user-modified' row with no shipped copy to compare against,"; then
  pass "2: …and the run states how many of that count the origin column alone decided"
else
  fail "2: the run reports a modified count without saying that part of it rests on the origin column alone — the claim this task exists to stop it repeating"
fi
if has "$OUT_BARE" 'a file you have PUT BACK reads'; then
  pass "2: …and names the consequence, so the reader knows what the number cannot distinguish"
else
  fail "2: the boundary-of-evidence line does not say what the column cannot tell apart"
fi
if has "$OUT_BARE" '--toolkit-dir <kinglet-unity checkout>'; then
  pass "2: …and offers the flag that would settle it"
else
  fail "2: the run says the comparison was not made and does not say how to make it"
fi

# ── 3: with a checkout, the file is reverted and not modified ────────────────
OUT_TK="$(doctor project "$PROJ" --toolkit-dir "$REPO")"
assert_finished "$OUT_TK" "3"
if has "$OUT_TK" "WARN 1 $REV_HDR"; then
  pass "3: with a checkout the file is reported as reverted, counted on its own line"
else
  fail "3: no reverted line — the doctor still has no way to say a file was put back, which is the whole change"
fi
if grep -qxF -- "       $REL" <<< "$(doctor_block "$OUT_TK" "$REV_HDR")"; then
  pass "3: …and the reverted block NAMES the file rather than only counting it"
else
  fail "3: the reverted count does not name the file, so the user cannot act on it"
fi
if grep -qxF -- "       $REL" <<< "$(doctor_block "$OUT_TK" "$MOD_HDR")"; then
  fail "3: the file is ALSO listed as modified — one file in two buckets, and the modified sentence is false about it"
else
  pass "3: …and it is no longer listed as modified, so the two buckets are exclusive"
fi
if has "$OUT_TK" 'Until the next install.sh run rewrites those rows'; then
  pass "3: …and the run says what is still true: the row is stale until the next install"
else
  fail "3: the reverted block does not say the project is still cut off from updates until the next install — a finding with no consequence attached"
fi

# ── 4: a checkout's own doctor needs no flag ─────────────────────────────────
OUT_AUTO="$(doctor checkout "$PROJ")"
assert_finished "$OUT_AUTO" "4"
if has "$OUT_AUTO" "WARN 1 $REV_HDR"; then
  pass "4: run from a checkout, the doctor defaults --toolkit-dir to that checkout"
else
  fail "4: the checkout's own doctor did not find its own payload — the default derived from the script's location does not resolve"
fi

# ── 5: the OTHER reference root, which a single-arm mapping would miss ───────
# `.claude/scripts/<name>` is installed from the repo-root `scripts/<name>`; there is no
# `.claude/scripts/` in the checkout. A mapping that looked only under `<checkout>/.claude/` would
# find no reference for any script, report every reverted one as still modified, and pass 3 and 4.
SPROJ="$SCRATCH/reverted-script"
bash "$REPO/tests/fixtures/mkproject.sh" "$SPROJ" --variant urp >/dev/null
install_into "$SPROJ"
if [ -f "$SPROJ/$SCRIPT_REL" ]; then
  printf '\n# the user edited this script\n' >> "$SPROJ/$SCRIPT_REL"
  install_into "$SPROJ"
  cp "$SCRIPT_SRC" "$SPROJ/$SCRIPT_REL"
  OUT_S="$(doctor project "$SPROJ" --toolkit-dir "$REPO")"
  assert_finished "$OUT_S" "5"
  if grep -qxF -- "       $SCRIPT_REL" <<< "$(doctor_block "$OUT_S" "$REV_HDR")"; then
    pass "5: a reverted .claude/scripts/ file is recognised too — the second reference root resolves"
  else
    fail "5: the reverted block does not name $SCRIPT_REL — no reference copy was found for a .claude/scripts/ path, so every script reads as permanently modified"
  fi
else
  fail "5: the payload did not install $SCRIPT_REL — this state has nothing to edit"
fi

# ── 6: a LIVE edit, with a checkout, is still modified ───────────────────────
# The anti-"call everything reverted" arm. Without it, a comparison that always matched would pass
# every assertion above.
EPROJ="$SCRATCH/still-edited"
bash "$REPO/tests/fixtures/mkproject.sh" "$EPROJ" --variant urp >/dev/null
install_into "$EPROJ"
printf '\n<!-- still being edited -->\n' >> "$EPROJ/$REL"
install_into "$EPROJ"
OUT_E="$(doctor project "$EPROJ" --toolkit-dir "$REPO")"
assert_finished "$OUT_E" "6"
if grep -qxF -- "       $REL" <<< "$(doctor_block "$OUT_E" "$MOD_HDR")"; then
  pass "6: a file the user is still editing is reported as modified even with a checkout to compare against"
else
  fail "6: a live edit was not reported as modified — the comparison matches files that still carry the user's work, and the diagnostic now hides the one file they changed"
fi
if has "$OUT_E" "$REV_HDR"; then
  fail "6: a live edit was reported as reverted"
else
  pass "6: …and is not reported as reverted"
fi
# With a checkout present, nothing was decided by the column alone, so the boundary lines must not
# print — an unconditional hedge is as useless as an unconditional claim.
if has "$OUT_E" 'no shipped copy to compare against'; then
  fail "6: the run still says the origin column alone decided, on a run where the bytes were compared"
else
  pass "6: …and the run does not claim the column alone decided, because it did not"
fi

# ── 8: --toolkit-dir's own argument handling ─────────────────────────────────
# Validated BEFORE `shift 2`: `shift 2` with one argument left fails under `set -u` before any error
# message can print, and the user gets a silent exit 1.
ARG_RC=0
ARG_OUT="$(bash "$REPO/scripts/studio-doctor.sh" --toolkit-dir 2>&1)" || ARG_RC=$?
if [ "$ARG_RC" -eq 2 ] && has "$ARG_OUT" 'requires a path'; then
  pass "8: --toolkit-dir with no value exits 2 with a message, rather than dying silently in shift"
else
  fail "8: --toolkit-dir with no value exited $ARG_RC saying '$ARG_OUT'"
fi
NOTK_RC=0
NOTK_OUT="$(bash "$REPO/scripts/studio-doctor.sh" --project-dir "$PROJ" --toolkit-dir "$SCRATCH" 2>&1)" || NOTK_RC=$?
if [ "$NOTK_RC" -eq 2 ] && has "$NOTK_OUT" 'Not a kinglet-unity checkout'; then
  pass "8: a --toolkit-dir that is not a checkout is refused loudly, not accepted as one supplying no reference for anything"
else
  fail "8: a non-checkout --toolkit-dir exited $NOTK_RC saying '$NOTK_OUT' — a flag that appears to work and changes nothing"
fi

[ "$FAILURES" -eq 0 ] || exit 1
printf 'all doctor-reverted assertions passed\n'
