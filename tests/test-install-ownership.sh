#!/usr/bin/env bash
# ============================================================================
# test-install-ownership.sh — a receipt row is a claim of OWNERSHIP, not a log of this run's writes.
#
# uninstall.sh removes only receipt-listed paths. That is deliberate: a previous version deleted by
# filename and would happily remove a file it had never installed. It makes the receipt the single
# statement of what the toolkit is allowed to take away — and it makes a missing row permanent
# debris, and a wrong row a deletion of the user's work.
#
# $RECEIPT_TMP is rebuilt from scratch on every install. So a row written INSIDE a create branch is
# a log of this run, and it disappears on the second run: the branch is skipped, the rebuilt receipt
# no longer mentions the file, and uninstall.sh leaves it behind. Two installs produce the same
# files and a different ownership record, and the second record is the wrong one.
#
# This file asserts the property across four states. THE DIRECTION THAT MATTERS IS FAIL-CLOSED:
# unknown provenance means no row, means uninstall leaves the file alone. States C and D exist to
# prove that direction specifically, and D is the one that is easy to get wrong, because the file
# was the installer's a moment ago.
#
#   A  fresh install                                  row present, uninstall removes the file
#   B  second install, file untouched                 row present, uninstall removes the file
#   C  the user's own file, present before install 1  NO row,      uninstall leaves the file
#   D  install, the user edits it, install again      NO row,      uninstall leaves the file
#
# Both project-root files the installer writes are covered — MCP-SETUP.md and .mcp.json. They are
# one class and the fix is one shape, so a state that passes for one and not the other is a real
# finding rather than an inconsistency to paper over.
#
# States E and F are the THIRD project-root file, and it is the one the states above were structurally
# unable to see: Packages/manifest.json.bak, written by --with-mcp / --with-input-system before the
# manifest is edited. The installer deletes that backup when git already tracks the manifest — git is
# then the backup — and KEEPS it, announced, when git does not. What it never did was record it, so
# uninstall.sh could never remove it: permanent debris in exactly the projects least able to
# `git checkout` it away.
#
#   E  --with-mcp, the project not under git       backup kept,    row present, uninstall removes it
#   F  --with-mcp, the manifest tracked by git     backup deleted, NO row,      nothing to remove
#
# E's second install is not decoration. `add_manifest_dependency` returns early once the package is
# in the manifest, so run 2 never reaches the branch that makes the backup — while the backup is
# still sitting on disk. A row written on authorship therefore vanishes on run 2 and the file becomes
# permanent debris again, one run later. Measured on this fixture before the fix. It is the same
# defect states A–D close for the other two files, and it is why the row is a statement of ownership
# here too rather than a log of the run that happened to create the file.
#
# E3 is the fail-closed direction for this file: a Packages/manifest.json.bak the USER wrote, and a
# plain install that never asks for a manifest edit at all. No row, and uninstall leaves it.
#
# State G is the other side of the same column. A–D are about whether the row is WRITTEN; G is about
# whether it is READ. A `.claude/` file the user edited gets a `user-modified` row carrying its
# EDITED checksum — deliberately, so the next install still recognises it — and uninstall.sh's
# classifier compared that checksum, found it matching, and deleted the user's file under
# "unchanged since install". G asserts all three directions, and the third is what stops the fix
# from becoming "never delete anything":
#
#   G  the user's edit survives `uninstall.sh --yes`, is reported under `keep ... you modified`,
#      and IS removed by `uninstall.sh --purge` — while an untouched toolkit file beside it still
#      goes.
#
# State H is the third loop in install.sh. A–D and G are about `.claude/` payload files and the two
# project-root files; H is about `.claude/scripts/*`, which a SECOND write loop puts there — one
# that tested nothing before 2026-08-12, so a run announced `keeping yours: .claude/scripts/...` and
# overwrote the file in the same output.
#
#   H  the user's edit survives a REINSTALL, gets a `user-modified` row carrying its edited bytes,
#      appears in the run's `keeping yours` list and nowhere else — while a stale, untouched
#      sibling is still replaced with the bytes this toolkit ships.
#
# States I–I5 are the FOURTH project-root file, CLAUDE.md.generated, and they are the first here
# whose subject has no shipped copy to compare against — it is generated per project, so only the
# previous receipt and the knowledge that this run wrote it can answer for it. J is not a new file:
# it is E's file, asserting that a single run passing BOTH --with-* flags produces exactly one row.
# Their own header sits above the states; this list is the index.
#
#   I   the `separate` branch writes it          row present, uninstall removes it
#   I2  the same, installed twice                row present, uninstall removes it
#   I3  the user's own, branch never runs        NO row,      uninstall leaves it
#   I4  ours, then a run that never touches it   row present, uninstall removes it
#   I5  the user edits ours, then such a run     NO row,      uninstall leaves it
#   J   both --with-* flags, one run             exactly ONE Packages/manifest.json.bak row
#
# States K–K3 ask the other question entirely. Everything above asks whether the RECEIPT is right;
# K–K3 ask whether the FILE IS STILL THERE. Two writers put bytes on disk before anything asked whose
# they were, and once Tasks 2 and 2b gave both paths receipt rows, the runs began announcing
# `keeping yours` about files they destroyed in the same output. Their own header sits above them.
#
#   K   ours, the user fills in the FILL: markers, install again   bytes survive, NO row
#   K2  the user's own file, first install ever, twice             bytes survive, NO row
#   K3  ours, the user edits the backup, a second --with-* flag    bytes survive, manifest unedited
#
# WHAT THIS FILE CANNOT SEE
#   * Named paths, not an enumeration. A–D assert MCP-SETUP.md and .mcp.json; E, F and J assert
#     Packages/manifest.json.bak; I–I5 assert CLAUDE.md.generated. A FIFTH unrecorded project-root
#     write would be invisible here by construction, because nothing in this file walks the project
#     and asks what appeared — every assertion names its path in advance. Catching that class needs
#     a guard whose oracle is the filesystem before and after a run, which is a different test from
#     this one.
#   * State G edits three payload files — Markdown, a hook, settings.json — because ONE was not
#     enough: with a single .md file here, a classifier mutated to protect only `.md` passed this
#     whole file with zero failures while deleting a user's edited hook and settings.json. What it
#     still does not cover: `.claude/scripts/*`, which a different loop in install.sh writes — state
#     H covers what the INSTALLER does to those, and nothing here covers what UNINSTALL does to an
#     edited one; a file whose MODE the user changed rather than its bytes (the receipt records mode
#     and nothing reads it); and any payload file whose content is binary. What the INSTALLER does
#     to a `.claude/` payload file across upgrades is tests/test-install.sh's and
#     tests/test-install-prune.sh's ground, not this file's.
#   * Every state but J installs against the default (urp) fixture; J is the only one that builds a
#     `--variant builtin` project, and the only one that passes `--with-input-system`. A–D, G, H and
#     I–I5 pass no flag but `--yes`, and no fixture here is a git repository except F's, so every
#     branch that turns on `git -C "$PROJECT_DIR"` takes its no-git side everywhere else. `--purge`
#     is exercised in state G and nowhere else; `--dry-run` and `--keep-local` nowhere at all.
#   * E and F use --with-mcp rather than --with-input-system because the urp fixture already carries
#     com.unity.inputsystem, so that flag returns early and writes no backup. J is the state where
#     both callers do reach the backup branch, and it asserts the ROW CARDINALITY only. What is
#     still unmeasured there: the second `cp` overwrites the first backup, so the surviving .bak is
#     the manifest as it stood after the first edit rather than before the run — measured by hand
#     2026-08-13, asserted nowhere. Also unmeasured: a user's own Packages/manifest.json.bak on a run
#     that DOES pass a --with-* flag, where install.sh's `cp` overwrites it before anything asks
#     whose it was. E3 covers only the other half of that case — the plain install, which never
#     reaches the `cp`.
#   * Of the malformed receipts a mangled origin column can produce, only ONE shape is asserted
#     (G.5: a trailing space). A fifth column and a CRLF line ending take the same catch-all branch
#     by construction, but they are reasoned about, not measured, here.
#   * Why uninstall.sh did what it did. This reads the filesystem before and after, so "the file
#     survived" and "the file survived because uninstall crashed" look identical — which is why
#     every install and uninstall below asserts its exit status separately.
#   * The `$4 == "toolkit"` conjunct in owned_by_installer's awk. Delete it, keep `$2 == have`, and
#     every state here stays green. That is not a coverage gap this file could close: install.sh
#     emits no non-`toolkit` row for either path, so no fixture can produce a receipt where the
#     conjunct changes the answer. It is defence against inputs that do not exist yet — a
#     hand-edited receipt, and the project-root rows Task 2 adds — so it is unfalsifiable by
#     construction rather than merely untested. Read the mutation record accordingly: three of the
#     four fail-open weakenings of that awk are caught here, and this is the fourth.
#   * Anything about behaviour inside Claude Code. This proves the installer's bookkeeping on a
#     synthetic project, and nothing more.
# ============================================================================
# Self-contained: own set -euo pipefail, own pass/fail, REPO from BASH_SOURCE. The runner's
# assert_* helpers are deliberately NOT used — the runner does `set +e` before sourcing, so an
# undefined helper prints to stderr and contributes no FAIL: token, and this file would report
# green on the defect it exists to catch.
set -euo pipefail

# ${BASH_SOURCE[0]}, not $0: the runner does `( source "$test_file" )`, and inside a sourced file $0
# is the *sourcing* shell's $0.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

# PASS/FAIL, not ok/FAIL: run-tests.sh aggregates by grepping each file's output for those tokens.
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'PASS: %s\n' "$1"; }

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# ── own_row: the one accessor every assertion below goes through ─────────────
# own_row <receipt-path> <project-relative-path> — prints the receipt row for that path, or nothing.
#
# Matches field 1 exactly rather than grepping for the path as a substring. `.mcp.json` appears
# inside .claude/scripts/studio-doctor.sh's own row as a substring of nothing, but `MCP-SETUP.md`
# is a substring of no other row only by luck, and a checksum column is 64 hex characters in which
# any short needle can appear. Field equality is the claim; substring presence is not.
own_row() {
  [ -f "$1" ] || return 0
  awk -F'\t' -v want="$2" '$1 == want { print }' "$1"
}

receipt_of() { printf '%s' "$1/.claude/state/install-receipt.tsv"; }

# A missing file hashes to the empty string. It used to take the whole test down instead:
# `sha256sum` exits 1 on a missing path, `set -o pipefail` promotes that through the `| cut`, and
# `set -e` then kills the file at the assignment — with no message, mid-state, every later assertion
# gone, and an exit status indistinguishable from an ordinary red.
#
# Measured 2026-08-12 while mutation-proving state H. Mutating install.sh's scripts loop to keep
# every file made install 1 write no scripts at all; H.4 then hashed a path that did not exist and
# this line ended the run there. H.4 and H.5 printed nothing, and the file reported exactly the one
# unrelated failure it had already collected — the anti-"keep everything" guard reading as absent
# rather than as red. A probe that dies is a probe that reports nothing.
sha_of() {
  [ -f "$1" ] || return 0
  sha256sum "$1" | cut -d' ' -f1
}

# ── Fixture / invocation helpers ─────────────────────────────────────────────
new_fixture() {
  local d="$SCRATCH/$1"
  bash "$REPO/tests/fixtures/mkproject.sh" "$d" >/dev/null
  printf '%s' "$d"
}

# KINGLET_USER_SETTINGS is pointed at a path that does not exist so the Superpowers provider
# detection takes the same branch on every machine. stdin is /dev/null so no read -rp can block if
# a branch is ever added that forgets to check --yes.
run_install() {
  local d="$1" label="$2" rc=0
  KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
    bash "$REPO/install.sh" --project-dir "$d" --yes >/dev/null 2>&1 </dev/null || rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$label: install.sh exited 0"
  else
    fail "$label: install.sh exited $rc — every assertion after this one describes a half-installed project"
  fi
}

# --no-backup, because uninstall.sh's default is to `cp -r .claude/` to .claude.backup.<ts>/ at the
# project root. That is correct behaviour and irrelevant here; skipping it keeps the fixture's file
# list readable. It changes nothing about which files are removed.
run_uninstall() {
  local d="$1" label="$2" rc=0
  bash "$REPO/uninstall.sh" --project-dir "$d" --yes --no-backup >/dev/null 2>&1 </dev/null || rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$label: uninstall.sh exited 0"
  else
    fail "$label: uninstall.sh exited $rc — 'the file survived' below may mean the uninstaller died, not that it declined"
  fi
}

# ── Assertions ───────────────────────────────────────────────────────────────
# A row must be present, say `toolkit`, and carry the checksum the file actually has. The third
# part is not decoration: uninstall.sh removes a listed file only while its recorded sha still
# matches, so a row with a stale checksum is a row that removes nothing.
assert_owned() {
  local d="$1" rel="$2" label="$3" row origin recorded actual
  row="$(own_row "$(receipt_of "$d")" "$rel")"
  if [ -z "$row" ]; then
    fail "$label: no receipt row for $rel — uninstall.sh will leave it behind forever"
    return
  fi
  origin="$(awk -F'\t' 'NR == 1 { print $4 }' <<< "$row")"
  recorded="$(awk -F'\t' 'NR == 1 { print $2 }' <<< "$row")"
  actual="$(sha_of "$d/$rel")"
  if [ "$origin" = toolkit ]; then
    pass "$label: $rel is recorded as toolkit-owned"
  else
    fail "$label: $rel is recorded with origin '$origin', not 'toolkit'"
  fi
  if [ "$recorded" = "$actual" ]; then
    pass "$label: $rel's recorded checksum matches the file on disk"
  else
    fail "$label: $rel's receipt row records $recorded but the file hashes $actual — uninstall.sh would decline to remove it"
  fi
}

assert_not_owned() {
  local d="$1" rel="$2" label="$3" row
  row="$(own_row "$(receipt_of "$d")" "$rel")"
  if [ -z "$row" ]; then
    pass "$label: no receipt row for $rel — the installer does not claim a file it does not own"
  else
    fail "$label: the receipt claims $rel — uninstall.sh would delete the user's file. Row: $row"
  fi
}

assert_gone() {
  local d="$1" rel="$2" label="$3"
  if [ -e "$d/$rel" ]; then
    fail "$label: uninstall.sh left $rel behind"
  else
    pass "$label: uninstall.sh removed $rel"
  fi
}

# Presence is not enough — the user's bytes must be the bytes that survive.
assert_kept() {
  local d="$1" rel="$2" want="$3" label="$4" have
  if [ ! -e "$d/$rel" ]; then
    fail "$label: uninstall.sh deleted $rel, which the user wrote"
    return
  fi
  have="$(sha_of "$d/$rel")"
  if [ "$have" = "$want" ]; then
    pass "$label: $rel survived uninstall with the user's bytes intact"
  else
    fail "$label: $rel survived uninstall but its contents changed ($want -> $have)"
  fi
}

# ── State A: fresh install ───────────────────────────────────────────────────
A="$(new_fixture state-a)"
run_install "$A" "A"
assert_owned "$A" 'MCP-SETUP.md' "A (fresh install)"
assert_owned "$A" '.mcp.json'    "A (fresh install)"
run_uninstall "$A" "A"
assert_gone "$A" 'MCP-SETUP.md' "A (fresh install)"
assert_gone "$A" '.mcp.json'    "A (fresh install)"

# ── State B: second install, neither file touched ────────────────────────────
# The defect. Run 1 creates the files and records them; run 2 skips both create branches, so a row
# written inside a create branch is never re-emitted and the rebuilt receipt disowns two files that
# are sitting right there, unchanged, exactly as the installer wrote them.
B="$(new_fixture state-b)"
run_install "$B" "B install 1"
run_install "$B" "B install 2"
assert_owned "$B" 'MCP-SETUP.md' "B (second install)"
assert_owned "$B" '.mcp.json'    "B (second install)"
run_uninstall "$B" "B"
assert_gone "$B" 'MCP-SETUP.md' "B (second install)"
assert_gone "$B" '.mcp.json'    "B (second install)"

# ── State B2: a second install by a DIFFERENT toolkit version ────────────────
# States A–D all install the same toolkit twice, so the file on disk is always byte-for-byte the
# toolkit's current copy and "is this ours?" can be answered by that comparison alone. The real
# second install is an UPGRADE, and neither of these two files is ever overwritten once it exists —
# so after upgrading, the project holds the PREVIOUS version's bytes and that comparison fails.
# Only the previous receipt can answer then.
#
# Without this state the receipt half of the ownership test is dead code that nothing here executes:
# delete it and A–D stay green while every real upgrade silently stops owning both files, which is
# the defect this whole file exists to close, one version apart.
#
# The "previous version" is a scratch toolkit: the payload and scripts as they stand, plus an
# MCP-SETUP.md with an extra line and an install.sh whose .mcp.json points at a different port.
# That is the whole of what makes a version different from the perspective of these two files.
OLD="$SCRATCH/old-toolkit"
mkdir -p "$OLD"
cp -R "$REPO/.claude" "$OLD/.claude"
cp -R "$REPO/scripts" "$OLD/scripts"
cp "$REPO/install.sh" "$OLD/install.sh"
cp "$REPO/MCP-SETUP.md" "$OLD/MCP-SETUP.md"
printf '\n<!-- shipped by the previous toolkit version -->\n' >> "$OLD/MCP-SETUP.md"
sed -i.bak 's|localhost:8080/mcp|localhost:8081/mcp|g' "$OLD/install.sh" && rm -f "$OLD/install.sh.bak"

B2="$(new_fixture state-b2)"
B2_RC=0
KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
  bash "$OLD/install.sh" --project-dir "$B2" --yes >/dev/null 2>&1 </dev/null || B2_RC=$?
if [ "$B2_RC" -eq 0 ]; then
  pass "B2 install 1 (previous version): install.sh exited 0"
else
  fail "B2 install 1 (previous version): install.sh exited $B2_RC"
fi
# Sanity: the scratch toolkit really did ship different bytes. Without this the state could quietly
# degenerate into a repeat of B — two identical installs — and still report green.
if [ "$(sha_of "$B2/MCP-SETUP.md")" = "$(sha_of "$REPO/MCP-SETUP.md")" ]; then
  fail "B2: the scratch toolkit installed the CURRENT MCP-SETUP.md — this state is a duplicate of B and proves nothing about the receipt half of the ownership test"
else
  pass "B2: the previous version installed different bytes than the current toolkit ships"
fi

run_install "$B2" "B2 install 2 (current version)"
assert_owned "$B2" 'MCP-SETUP.md' "B2 (upgrade)"
assert_owned "$B2" '.mcp.json'    "B2 (upgrade)"
run_uninstall "$B2" "B2"
assert_gone "$B2" 'MCP-SETUP.md' "B2 (upgrade)"
assert_gone "$B2" '.mcp.json'    "B2 (upgrade)"

# ── State C: the user's own files, present before install 1 ──────────────────
# Two shapes of user-owned .mcp.json, because install.sh branches on the file's CONTENT and the two
# branches fail differently:
#
#   has-entry  — the file already names a UnityMCP server, so the installer says "left alone". This
#                is the branch where a naive ownership test ("it mentions UnityMCP, so it is ours")
#                deletes the user's config, and it is why the test below is a checksum comparison
#                and not a grep.
#   no-entry   — no UnityMCP server, so the installer prints the block and rewrites nothing.
#
# Two installs, not one: acceptance criterion 4 is "after ANY number of installs", and the failure
# being guarded is one that only appears on the second run.
for c_shape in has-entry no-entry; do
  C="$(new_fixture "state-c-$c_shape")"
  printf '# My own notes about the MCP bridge\n\nDo not delete this.\n' > "$C/MCP-SETUP.md"
  if [ "$c_shape" = has-entry ]; then
    printf '{"mcpServers":{"UnityMCP":{"type":"http","url":"http://localhost:7777/mcp"}}}\n' > "$C/.mcp.json"
  else
    printf '{"mcpServers":{"mine":{"type":"http","url":"http://localhost:9999/mcp"}}}\n' > "$C/.mcp.json"
  fi
  C_MD_SHA="$(sha_of "$C/MCP-SETUP.md")"
  C_JSON_SHA="$(sha_of "$C/.mcp.json")"

  run_install "$C" "C/$c_shape install 1"
  assert_not_owned "$C" 'MCP-SETUP.md' "C/$c_shape (after install 1)"
  assert_not_owned "$C" '.mcp.json'    "C/$c_shape (after install 1)"

  run_install "$C" "C/$c_shape install 2"
  assert_not_owned "$C" 'MCP-SETUP.md' "C/$c_shape (after install 2)"
  assert_not_owned "$C" '.mcp.json'    "C/$c_shape (after install 2)"

  run_uninstall "$C" "C/$c_shape"
  assert_kept "$C" 'MCP-SETUP.md' "$C_MD_SHA"   "C/$c_shape"
  assert_kept "$C" '.mcp.json'    "$C_JSON_SHA" "C/$c_shape"
done

# ── State D: the installer's file, then the user edits it ────────────────────
# The hard one. After install 1 the previous receipt records both files as `toolkit`, so an
# ownership test that reads only "was it in the last receipt?" renews the claim and uninstall.sh
# deletes an edited file. The row must be renewed only while the file still carries the checksum
# that receipt recorded.
#
# THE THIRD INSTALL IS NOT REDUNDANT. After install 2 there is no row to carry forward, so installs
# 3..n are answered by the toolkit-copy comparison alone. Asserting only install 2 would leave the
# steady state untested — and "no row" is the state this whole file's defect produces by accident,
# so a D that is right for the wrong reason is indistinguishable from a D that is right.
D="$(new_fixture state-d)"
run_install "$D" "D install 1"
assert_owned "$D" 'MCP-SETUP.md' "D (before the user's edit)"
assert_owned "$D" '.mcp.json'    "D (before the user's edit)"

printf '\nMy own note appended by hand.\n' >> "$D/MCP-SETUP.md"
# Still names UnityMCP, so install.sh takes its "already has an entry — left alone" branch. The
# edit is a different port, which is precisely what a user changes here.
printf '{"mcpServers":{"UnityMCP":{"type":"http","url":"http://localhost:8123/mcp"}}}\n' > "$D/.mcp.json"
D_MD_SHA="$(sha_of "$D/MCP-SETUP.md")"
D_JSON_SHA="$(sha_of "$D/.mcp.json")"

run_install "$D" "D install 2"
assert_not_owned "$D" 'MCP-SETUP.md' "D (edited, then reinstalled)"
assert_not_owned "$D" '.mcp.json'    "D (edited, then reinstalled)"

run_install "$D" "D install 3"
assert_not_owned "$D" 'MCP-SETUP.md' "D (edited, then reinstalled twice)"
assert_not_owned "$D" '.mcp.json'    "D (edited, then reinstalled twice)"

run_uninstall "$D" "D"
assert_kept "$D" 'MCP-SETUP.md' "$D_MD_SHA"   "D"
assert_kept "$D" '.mcp.json'    "$D_JSON_SHA" "D"

# ── States E and F: the manifest backup ──────────────────────────────────────
# One file, two branches, and WHICH BRANCH A FIXTURE TAKES IS ASSERTED RATHER THAN ASSUMED. The
# branch turns on `git -C "$PROJECT_DIR" ls-files --error-unmatch Packages/manifest.json`, which
# consults the whole parent chain — so a scratch directory that happens to sit inside somebody's
# repository silently sends E down F's path, deletes the backup, and E's every assertion then passes
# for the wrong reason on a file that is not there. The two branches print different lines and each
# state below checks for its own, so a fixture in the wrong shape goes red instead of green.
#
# The paths are derived from one string each, not written twice: a row whose path disagrees with the
# file it claims by one character is a row uninstall.sh silently declines to act on, which is
# indistinguishable from no row at all.
MANIFEST_REL='Packages/manifest.json'
MANIFEST_BAK_REL="$MANIFEST_REL.bak"

# The flag-passing sibling of run_install, capturing output the way run_uninstall_flags does — the
# announcement is the only evidence of which branch ran, and it is not on the filesystem.
INSTALL_OUT=''
run_install_flags() {
  local d="$1" label="$2"; shift 2
  local rc=0 out
  out="$(KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
        bash "$REPO/install.sh" --project-dir "$d" --yes "$@" </dev/null 2>&1 \
        | sed $'s/\x1b\\[[0-9;]*m//g')" || rc=$?
  INSTALL_OUT="$out"
  if [ "$rc" -eq 0 ]; then
    pass "$label: install.sh exited 0"
  else
    fail "$label: install.sh exited $rc — every assertion after this one describes a half-installed project"
    printf '%s\n' "$out"
  fi
}

# ── State E: --with-mcp on a project git does not track ──────────────────────
E="$(new_fixture state-e)"
if git -C "$E" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "E: the fixture is inside a git work tree — install.sh will delete the backup instead of keeping it, and every E assertion below would be testing F's branch"
else
  pass "E: the fixture is not under git, so install.sh must keep the backup it makes"
fi
E_MANIFEST_BEFORE="$(sha_of "$E/$MANIFEST_REL")"

run_install_flags "$E" "E install 1" --with-mcp
if grep -qF -- '(backup: manifest.json.bak)' <<< "$INSTALL_OUT"; then
  pass "E: the run announced the backup it kept — this is the branch that keeps the file"
else
  fail "E: the run never announced '(backup: manifest.json.bak)' — it took the git branch, or never edited the manifest at all, and E is asserting against a branch that did not run"
fi

if [ -f "$E/$MANIFEST_BAK_REL" ]; then
  pass "E: $MANIFEST_BAK_REL is on disk after the install"
else
  fail "E: $MANIFEST_BAK_REL is not on disk — there is nothing here for a receipt row to own, and the assertions below prove nothing"
fi
# A backup that is not the pre-edit manifest is not a backup. Asserted because E's whole premise is
# that this file is worth keeping, and because it pins which `cp` the surviving bytes came from.
if [ "$(sha_of "$E/$MANIFEST_BAK_REL")" = "$E_MANIFEST_BEFORE" ]; then
  pass "E: the backup carries the manifest's bytes as they stood before the run edited it"
else
  fail "E: the backup does not match the pre-run manifest — it is a copy of something else"
fi

assert_owned "$E" "$MANIFEST_BAK_REL" "E (--with-mcp, no git)"

# E's second install, and it is the whole point of the state. Run 2 passes NO flag, so
# add_manifest_dependency is never called and the branch that makes the backup is never reached —
# while the backup from run 1 is still sitting there. A row written where the file is created
# disappears here, and the file goes back to being permanent debris.
run_install "$E" "E install 2 (plain, no flags — the backup branch never runs)"
assert_owned "$E" "$MANIFEST_BAK_REL" "E (after a second install that never touches the manifest)"

E_MANIFEST_AFTER="$(sha_of "$E/$MANIFEST_REL")"
run_uninstall "$E" "E"
assert_gone "$E" "$MANIFEST_BAK_REL" "E (--with-mcp, no git)"
# The file the backup was a copy OF is the user's, and a row for `.bak` that reached one character
# too far would take it. Nothing in the receipt should ever claim the manifest itself.
assert_kept "$E" "$MANIFEST_REL" "$E_MANIFEST_AFTER" "E (the manifest itself)"
assert_not_owned "$E" "$MANIFEST_REL" "E (the manifest itself)"

# ── State E3: a backup the USER wrote ────────────────────────────────────────
# The fail-closed direction, and the one where a mistake destroys something the installer never
# made. A plain install never calls add_manifest_dependency at all, so nothing this run knows can
# distinguish this file from one of ours except the previous receipt — which has no row for it.
E3="$(new_fixture state-e-userbak)"
printf '{\n  "dependencies": {\n    "my.own.hand.rolled.backup": "1.0.0"\n  }\n}\n' > "$E3/$MANIFEST_BAK_REL"
E3_SHA="$(sha_of "$E3/$MANIFEST_BAK_REL")"
run_install "$E3" "E3 install 1"
assert_not_owned "$E3" "$MANIFEST_BAK_REL" "E3 (the user's own backup, after install 1)"
run_install "$E3" "E3 install 2"
assert_not_owned "$E3" "$MANIFEST_BAK_REL" "E3 (the user's own backup, after install 2)"
run_uninstall "$E3" "E3"
assert_kept "$E3" "$MANIFEST_BAK_REL" "$E3_SHA" "E3"

# ── State F: --with-mcp with the manifest tracked by git ─────────────────────
# git is the backup, so the installer deletes its own copy and there is nothing to own. F is the
# anti-"record everything" direction: a fix that writes the row unconditionally puts a path in the
# receipt that does not exist, and uninstall.sh's `already gone` counter absorbs it silently.
F="$(new_fixture state-f)"
git -C "$F" -c init.defaultBranch=main init -q >/dev/null 2>&1 || true
# -f, so a global core.excludesFile cannot decide whether this state runs. The precondition is
# asserted immediately below either way.
git -C "$F" add -f "$MANIFEST_REL" >/dev/null 2>&1 || true
if git -C "$F" ls-files --error-unmatch "$MANIFEST_REL" >/dev/null 2>&1; then
  pass "F: git tracks $MANIFEST_REL, so install.sh must delete its backup rather than keep it"
else
  fail "F: git does not track $MANIFEST_REL — the fixture never reaches the branch F exists to test, and everything below passes vacuously"
fi

run_install_flags "$F" "F install" --with-mcp
if grep -qF -- 'To undo: git checkout Packages/manifest.json' <<< "$INSTALL_OUT"; then
  pass "F: the run took the git branch — it points at git rather than at a backup file"
else
  fail "F: the run never printed the git-checkout undo line — it did not take the branch F exists to test"
fi
if grep -qF -- '(backup: manifest.json.bak)' <<< "$INSTALL_OUT"; then
  fail "F: the run announced a kept backup — it took E's branch despite git tracking the manifest"
else
  pass "F: the run announced no kept backup"
fi

if [ -e "$F/$MANIFEST_BAK_REL" ]; then
  fail "F: the installer left $MANIFEST_BAK_REL on disk even though git tracks the manifest"
else
  pass "F: the installer removed its own backup — git is the backup"
fi
assert_not_owned "$F" "$MANIFEST_BAK_REL" "F (git-tracked manifest)"

F_MANIFEST_AFTER="$(sha_of "$F/$MANIFEST_REL")"
run_uninstall "$F" "F"
assert_kept "$F" "$MANIFEST_REL" "$F_MANIFEST_AFTER" "F (the manifest itself)"
if [ -e "$F/$MANIFEST_BAK_REL" ]; then
  fail "F: $MANIFEST_BAK_REL exists after uninstall — something created it that should not have"
else
  pass "F: no $MANIFEST_BAK_REL after uninstall either — nothing was there and nothing appeared"
fi

# ── State G: uninstall.sh reads the origin column ────────────────────────────
# Data loss in shipped software, reproduced on this fixture before the fix: install, edit a payload
# file, install again, `uninstall.sh --yes` — and the edit is gone, counted under `remove N file(s)
# — unchanged since install`.
#
# It is unchanged only in the sense that it still matches the receipt, and it matches the receipt
# because install.sh recorded it AS EDITED. That record is correct and must not change: it is what
# makes the edit survive the NEXT install rather than exactly one of them (commit c2d27f1f,
# 2026-08-03). Two consumers need different things from one row, and the origin column is how the
# row tells them apart — install.sh has read it since c2d27f1f; uninstall.sh had never read it.
#
# THE THIRD DIRECTION IS NOT OPTIONAL. "Never delete anything" satisfies the first two and is a
# worse uninstaller than the one that ate the file, because it fails in the direction nobody looks.
# So `--purge` must still take the edited file, and — asserted separately below, because an
# origin-blind "keep everything" would pass the purge check too — the untouched `toolkit` files
# beside it must still be removed by the plain run.
#
# THREE EDITED FILES, THREE PAYLOAD CLASSES, AND THAT IS NOT REDUNDANCY. With one Markdown file
# here, a classifier mutated to protect only `.md` — `[ "${rel%.md}" != "$rel" ]` — passed this
# entire file with zero failures while shipping real data loss: install.sh writes `user-modified`
# rows for hooks and settings.json on any real project, and that mutation deletes both. The
# classifier reads a string column, so nothing about a file's TYPE should reach its decision; the
# only way to assert that is to vary the type and watch the answer not change.
G_UNTOUCHED='.claude/rules/architecture.md'
G_UNTOUCHED2='.claude/hooks/bash-gate.sh'
# Newline-separated, not an array: bash 3.2 is the floor and `declare -A` is out.
G_EDITED='.claude/rules/pc-console.md
.claude/hooks/warn-filename.sh
.claude/settings.json'
G_EDITED_COUNT=3

# A type-appropriate edit, because a fixture that is not what it claims to be proves nothing. The
# JSON file stays valid JSON; the shell file stays a runnable script. Both are edits a user really
# makes — install.sh's own comment calls settings.json "the most-edited file in the payload".
g_edit_file() {
  local abs="$1" tmp
  case "$abs" in
    *.json)
      tmp="$(mktemp)"
      awk 'NR == 1 { print; print "  \"_userNote\": \"widened by hand\","; next } { print }' "$abs" > "$tmp"
      mv "$tmp" "$abs"
      ;;
    *.md) printf '\n<!-- a line the user added by hand -->\n' >> "$abs" ;;
    *)    printf '\n# a line the user added by hand\n'        >> "$abs" ;;
  esac
}

# Sets G_DIR; writes each edited file's post-edit checksum to $G_SHAS as `rel<TAB>sha`. A function
# rather than a copy, because the plain run and the --purge run must start from the same state or
# the pair proves nothing about the flag.
G_DIR=''; G_SHAS="$SCRATCH/g-shas.tsv"
g_sha() { awk -F'\t' -v want="$1" '$1 == want { print $2 }' "$G_SHAS"; }
g_setup() {
  local label="$2" rel
  G_DIR="$(new_fixture "$1")"
  run_install "$G_DIR" "$label install 1"
  : > "$G_SHAS"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    g_edit_file "$G_DIR/$rel"
    printf '%s\t%s\n' "$rel" "$(sha_of "$G_DIR/$rel")" >> "$G_SHAS"
  done <<< "$G_EDITED"
  run_install "$G_DIR" "$label install 2"
}

# The precondition, asserted rather than assumed: install 2 must have written a `user-modified` row
# carrying the EDITED checksum. If it ever records the pristine sha instead, the classifier's sha
# test would start catching this file by itself and every assertion below would pass while proving
# nothing about the origin column.
assert_user_modified_row() {
  local d="$1" rel="$2" want_sha="$3" label="$4" row origin recorded
  row="$(own_row "$(receipt_of "$d")" "$rel")"
  if [ -z "$row" ]; then
    fail "$label: no receipt row for $rel after the edit — uninstall.sh cannot classify what it is not told about"
    return
  fi
  origin="$(awk -F'\t' 'NR == 1 { print $4 }' <<< "$row")"
  recorded="$(awk -F'\t' 'NR == 1 { print $2 }' <<< "$row")"
  if [ "$origin" = user-modified ]; then
    pass "$label: $rel is recorded as user-modified"
  else
    fail "$label: $rel is recorded with origin '$origin', not 'user-modified'"
  fi
  if [ "$recorded" = "$want_sha" ]; then
    pass "$label: the row carries the EDITED checksum — which is exactly why a sha-only classifier calls the file unchanged"
  else
    fail "$label: the row records $recorded, not the edited file's $want_sha — install.sh's record changed, and state G no longer tests what it was written to test"
  fi
}

# Data rows only: the header line `path<TAB>sha256...` is not a row, and uninstall.sh skips it.
receipt_rows() {
  local n
  n=$(grep -vc '^#' "$(receipt_of "$1")" || true)
  printf '%s' "$((n - 1))"
}

# Captured with the ANSI escapes stripped. uninstall.sh only colours when stdout is a tty and this
# capture is not one, so today the sed changes nothing — it is there so that a future change to
# that guard cannot turn these assertions silently green-or-red on an invisible byte.
UNINSTALL_OUT=''
run_uninstall_flags() {
  local d="$1" label="$2"; shift 2
  local rc=0 out
  out="$(bash "$REPO/uninstall.sh" --project-dir "$d" --yes --no-backup "$@" </dev/null 2>&1 \
        | sed $'s/\x1b\\[[0-9;]*m//g')" || rc=$?
  UNINSTALL_OUT="$out"
  if [ "$rc" -eq 0 ]; then
    pass "$label: uninstall.sh exited 0"
  else
    fail "$label: uninstall.sh exited $rc — the file outcomes below may describe a crash rather than a decision"
    printf '%s\n' "$out"
  fi
}

# G.1 / G.2 — plain `uninstall.sh --yes`.
g_setup state-g-plain "G plain"
G_PLAIN="$G_DIR"
while IFS= read -r g_rel; do
  [ -n "$g_rel" ] || continue
  assert_user_modified_row "$G_PLAIN" "$g_rel" "$(g_sha "$g_rel")" "G (precondition)"
done <<< "$G_EDITED"
G_ROWS="$(receipt_rows "$G_PLAIN")"

run_uninstall_flags "$G_PLAIN" "G plain"
while IFS= read -r g_rel; do
  [ -n "$g_rel" ] || continue
  assert_kept "$G_PLAIN" "$g_rel" "$(g_sha "$g_rel")" "G (plain --yes)"
  if grep -qF -- "$g_rel" <<< "$UNINSTALL_OUT"; then
    pass "G (plain --yes): the plan names $g_rel among the files it is keeping"
  else
    fail "G (plain --yes): the plan never names $g_rel — it is counted under 'unchanged since install', not under 'you modified'"
  fi
done <<< "$G_EDITED"

G_KEEP_LINE="$(awk '/file\(s\) you modified/ { print; exit }' <<< "$UNINSTALL_OUT")"
if [ -n "$G_KEEP_LINE" ]; then
  pass "G (plain --yes): the plan reports a keep-modified line — '$(printf '%s' "$G_KEEP_LINE" | sed 's/^ *//')'"
else
  fail "G (plain --yes): the 'keep N file(s) you modified' branch never fired"
fi

# The count is the guard against the fix becoming "keep everything": the edited files move out of
# the remove bucket and every other receipted file stays in it.
G_REMOVE_COUNT="$(awk '/unchanged since install/ { print $2; exit }' <<< "$UNINSTALL_OUT")"
if [ "${G_REMOVE_COUNT:-}" = "$((G_ROWS - G_EDITED_COUNT))" ]; then
  pass "G (plain --yes): removed $G_REMOVE_COUNT of $G_ROWS receipted files — exactly the $G_EDITED_COUNT edited ones held back"
else
  fail "G (plain --yes): the plan says '$G_REMOVE_COUNT' unchanged of $G_ROWS receipted files; expected $((G_ROWS - G_EDITED_COUNT)). Any other number means the classifier stopped removing what it should, or stopped keeping what it must"
fi

# G.3 — the untouched siblings, one Markdown and one shell. An uninstaller that keeps everything is
# as broken as one that deletes the user's work, and it fails in the direction nobody checks.
assert_gone "$G_PLAIN" "$G_UNTOUCHED"  "G (plain --yes, untouched toolkit .md)"
assert_gone "$G_PLAIN" "$G_UNTOUCHED2" "G (plain --yes, untouched toolkit .sh)"

# G.4 — `--purge` still takes them, THROUGH THE MODIFIED BUCKET.
#
# "The file is gone" is not enough on its own: --purge removes TO_REMOVE and MODIFIED both, so a
# classifier that never put the file in MODIFIED would satisfy it too — and did, before the fix.
# The plan line and the `Purged N` line are the only evidence of which bucket did the removing, and
# both are already in UNINSTALL_OUT.
g_setup state-g-purge "G purge"
G_PURGE="$G_DIR"
while IFS= read -r g_rel; do
  [ -n "$g_rel" ] || continue
  assert_user_modified_row "$G_PURGE" "$g_rel" "$(g_sha "$g_rel")" "G purge (precondition)"
done <<< "$G_EDITED"

run_uninstall_flags "$G_PURGE" "G purge" --purge
while IFS= read -r g_rel; do
  [ -n "$g_rel" ] || continue
  assert_gone "$G_PURGE" "$g_rel" "G (--purge)"
done <<< "$G_EDITED"
assert_gone "$G_PURGE" "$G_UNTOUCHED"  "G (--purge, untouched toolkit .md)"
assert_gone "$G_PURGE" "$G_UNTOUCHED2" "G (--purge, untouched toolkit .sh)"

G_PURGE_LINE="$(awk -v n="$G_EDITED_COUNT" '$0 ~ ("remove +" n " file\\(s\\) you modified \\(--purge\\)") { print; exit }' <<< "$UNINSTALL_OUT")"
if [ -n "$G_PURGE_LINE" ]; then
  pass "G (--purge): the plan removes the $G_EDITED_COUNT file(s) as MODIFIED, not as unchanged — '$(printf '%s' "$G_PURGE_LINE" | sed 's/^ *//')'"
else
  fail "G (--purge): no 'remove $G_EDITED_COUNT file(s) you modified (--purge)' line — the files were removed, but through the unchanged-since-install bucket, which is the defect wearing a passing test"
fi
if grep -qF -- "Purged $G_EDITED_COUNT modified file(s)." <<< "$UNINSTALL_OUT"; then
  pass "G (--purge): the run reports 'Purged $G_EDITED_COUNT modified file(s).' — the purge branch is what executed the removal"
else
  fail "G (--purge): the purge branch never reported; the removals came from somewhere else"
fi

# ── G.5: an origin we cannot read must fail CLOSED ───────────────────────────
# A `user-modified` marker that is not byte-exact — a trailing space, a fifth column, a CRLF line
# ending — is not `user-modified` to `[ "$origin" = ... ]`. Under an if/elif it falls through to the
# sha test, matches (the row records the file as edited), and the user's file is deleted: the same
# data loss as the original defect, arriving through a typo rather than a design decision.
#
# The receipt has never had a shape like this — `git show 5e0bf23:install.sh`, the commit that
# introduced the receipt at all, already writes four columns ending in `toolkit` — so no real
# project is held back by the catch-all. This asserts the direction, not a live case: unknown
# provenance is not ours to delete.
#
# The row is mangled by hand here because install.sh cannot produce it, which is exactly the point.
G_ODD="$(new_fixture state-g-oddorigin)"
run_install "$G_ODD" "G odd-origin install"
G_ODD_REL='.claude/rules/pc-console.md'
G_ODD_SHA="$(sha_of "$G_ODD/$G_ODD_REL")"
G_ODD_RECEIPT="$(receipt_of "$G_ODD")"
# Field 4 becomes "user-modified " — one trailing space, nothing else. awk rebuilds only the line it
# assigns into, so comment lines and the header pass through byte-for-byte.
G_ODD_TMP="$SCRATCH/odd-receipt.tsv"
awk -F'\t' -v OFS='\t' -v want="$G_ODD_REL" \
  '$1 == want { $4 = "user-modified " } { print }' "$G_ODD_RECEIPT" > "$G_ODD_TMP"
mv "$G_ODD_TMP" "$G_ODD_RECEIPT"
if [ -n "$(awk -F'\t' -v want="$G_ODD_REL" '$1 == want && $4 == "user-modified " { print }' "$G_ODD_RECEIPT")" ]; then
  pass "G odd-origin: the receipt row now carries an unreadable origin ('user-modified ' with a trailing space)"
else
  fail "G odd-origin: the receipt rewrite did not take — the assertion below would pass for the wrong reason"
fi

run_uninstall_flags "$G_ODD" "G odd-origin"
assert_kept "$G_ODD" "$G_ODD_REL" "$G_ODD_SHA" "G (unreadable origin)"
assert_gone "$G_ODD" "$G_UNTOUCHED2" "G (unreadable origin, a well-formed toolkit row beside it)"

# ── State H: the scripts loop respects a user edit ───────────────────────────
# install.sh has TWO write loops and they disagreed about what a user edit means. The payload loop
# tests `is_modified` before writing, keeps the file, and records a `user-modified` row carrying the
# file's current bytes. The `for group in scripts` loop beside it did neither: `cp` was
# unconditional and the row said `toolkit` regardless. One run therefore printed
#
#   warn 1 installed file(s) have local edits — keeping yours:
#          .claude/scripts/studio-doctor.sh
#   ok   Installed N file(s).
#
# N is the whole payload; the count is not what the transcript is about, and a literal one here read
# as current long after it stopped being so. It read `85` until 2026-08-13 — a real figure from the
# day it was measured, and stale by one the moment scripts/detect-pipeline.sh joined the group loop.
#
# and replaced the file with the shipped bytes in the same output. MODIFIED_FILES is computed from
# the receipt BEFORE either loop runs, so the warning was accurate about what the installer knew and
# false about what it then did. That is worse than silent data loss: the user is told the file is
# safe in the breath that destroys it.
#
# States A–D and G are about the receipt; H is about the WRITE. It is the only state here that
# asserts anything about `.claude/scripts/*`, which the file header listed as a known blind spot.
#
# H.4 IS THE ANTI-"KEEP EVERYTHING" DIRECTION, AND IT NEEDS A STALE FILE TO BE WORTH ANYTHING. If
# the untouched sibling already carried the bytes the current toolkit ships, "it still holds the
# shipped bytes" would pass for a loop that wrote nothing at all — the assertion would be satisfied
# by the previous run. So H installs a PREVIOUS toolkit first, one whose validate-asmdefs.sh
# carries an extra line, and requires the current run to replace it. A fix that keeps everything
# leaves the old bytes there and goes red.
#
# H.5 guards the arithmetic rather than a number: a kept script must increment KEPT and not WRITTEN,
# or the summary line reports a write the run did not make — the same class of false claim.
#
# TWO EDITED SCRIPTS AND TWO STALE SIBLINGS, AND THE SECOND OF EACH IS NOT REDUNDANCY. With one
# edited script here, two different broken fixes passed this whole file with zero failures — measured
# 2026-08-12, 114 PASS / 0 FAIL each:
#
#   * keyed on the NAME  — `[ "$b" = studio-doctor.sh ]`, the gap this comment used to merely declare;
#   * keyed on the COUNT — keep the first edited script and overwrite the rest, which nobody declared.
#
# One file cannot tell "keeps the user's edits" from "keeps THIS file" or from "keeps ONE file". Two
# can tell all three apart, and it is the same move state G made by varying the file TYPE: the loop
# reads a set-membership test, so nothing about a file's name or its ordinal should reach its
# decision, and the only way to assert that is to vary them and watch the answer not change.
#
# WHAT STATE H CANNOT SEE
#   * Two of the scripts install.sh ships, in one arrangement. How many it ships is not written
#     here on purpose — the shipped set is `scripts/*.sh` less `check-provenance.sh`, so derive it
#     (`ls scripts/*.sh | grep -vc check-provenance`). This line carried the number until
#     2026-08-13: it said "nine" from the day Task 1 wrote it, Task 5's detect-pipeline.sh made that
#     ten without revisiting the sentence, and nothing in the suite watches a script count, so the
#     next script to join will do it again. A fix keyed on the two names together, or on "the first
#     two", is not distinguishable here from a correct one.
#   * The `keeping yours` list is compared against the `user-modified` rows the receipt ends up
#     with. Those two sets can legitimately differ when a file the user edited was DROPPED from the
#     payload — install.sh announces it and writes no row, by design. This fixture installs the same
#     payload twice, so it produces no such file, and the equality is exact only for that reason.
#   * Nothing about uninstall. H stops at the end of install 2.
# Newline-separated, not arrays: bash 3.2 is the floor. Written pre-sorted, because every set
# comparison below goes through `sort` and a mis-sorted literal would fail for the wrong reason.
#
# The four names below moved on 2026-08-13: analyze-build-size.sh and validate-architecture.sh were
# removed when the surface criterion was applied to scripts/, so this fixture now uses
# detect-pipeline.sh and validate-asmdefs.sh. H_UNTOUCHED must stay clear of the two scripts
# install.sh EXECUTES from its own directory (detect-pipeline.sh and generate-claude-md.sh), because
# the previous-version fixture appends a line to every H_UNTOUCHED file in $OLDH/scripts/ before
# running $OLDH/install.sh. H_EDITED is edited in the PROJECT copy, which install.sh never runs, so
# it carries no such constraint.
H_EDITED='.claude/scripts/detect-pipeline.sh
.claude/scripts/studio-doctor.sh'
H_EDITED_COUNT=2
H_UNTOUCHED='.claude/scripts/validate-asmdefs.sh
.claude/scripts/validate-serialization.sh'

# The "previous version": the payload and scripts as they stand, with the untouched siblings each
# carrying an extra line. That is the whole of what makes a version different from this loop's
# perspective — and it is what lets H.4 tell a loop that overwrites from one that does nothing.
OLDH="$SCRATCH/old-toolkit-h"
mkdir -p "$OLDH"
cp -R "$REPO/.claude" "$OLDH/.claude"
cp -R "$REPO/scripts" "$OLDH/scripts"
cp "$REPO/install.sh" "$OLDH/install.sh"
cp "$REPO/MCP-SETUP.md" "$OLDH/MCP-SETUP.md"
while IFS= read -r h_rel; do
  [ -n "$h_rel" ] || continue
  printf '\n# shipped by the previous toolkit version\n' >> "$OLDH/scripts/$(basename "$h_rel")"
done <<< "$H_UNTOUCHED"

H="$(new_fixture state-h)"
H_RC1=0
KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
  bash "$OLDH/install.sh" --project-dir "$H" --yes >/dev/null 2>&1 </dev/null || H_RC1=$?
if [ "$H_RC1" -eq 0 ]; then
  pass "H install 1 (previous version): install.sh exited 0"
else
  fail "H install 1 (previous version): install.sh exited $H_RC1"
fi

# Sanity: the stale siblings really are stale. Without this, H.4 could pass because the two versions
# shipped identical bytes, which would make the anti-"keep everything" guard unfalsifiable.
while IFS= read -r h_rel; do
  [ -n "$h_rel" ] || continue
  if [ "$(sha_of "$H/$h_rel")" = "$(sha_of "$REPO/scripts/$(basename "$h_rel")")" ]; then
    fail "H: the previous version installed the CURRENT $h_rel — H.4 cannot distinguish a loop that overwrites from one that does nothing"
  else
    pass "H: the previous version installed different bytes for $h_rel"
  fi
done <<< "$H_UNTOUCHED"

# The user's edits. A comment line each, so the scripts still run — a fixture that is not what it
# claims to be proves nothing. Different text per file, so no two edited scripts can hash alike and
# an assertion cannot pass by comparing the wrong pair.
while IFS= read -r h_rel; do
  [ -n "$h_rel" ] || continue
  printf '\n# a line the user added by hand to %s\n' "$(basename "$h_rel")" >> "$H/$h_rel"
done <<< "$H_EDITED"

# Every .claude file as it stands immediately before install 2 — the baseline "what was actually
# kept" is measured against, and the source of every expected checksum below. Taken AFTER the edits,
# because the user's bytes are the bytes that must survive. state/ is excluded: install.sh rewrites
# the receipt there on every run by design.
H_PRE="$SCRATCH/h-pre.tsv"
( cd "$H" && find .claude -type f ! -path '.claude/state/*' | sort | xargs sha256sum ) > "$H_PRE"
h_pre_sha() { awk -v want="$1" '$2 == want { print $1 }' "$H_PRE"; }

H_RC2=0
H_OUT="$(KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
  bash "$REPO/install.sh" --project-dir "$H" --yes </dev/null 2>&1 \
  | sed $'s/\x1b\\[[0-9;]*m//g')" || H_RC2=$?
if [ "$H_RC2" -eq 0 ]; then
  pass "H install 2 (current version): install.sh exited 0"
else
  fail "H install 2 (current version): install.sh exited $H_RC2 — every assertion below describes a half-installed project"
  printf '%s\n' "$H_OUT"
fi

# H.1 — the bytes. Every edited script, not one of them: a fix that keeps the first and overwrites
# the rest is indistinguishable from a correct one when only one file is asserted.
while IFS= read -r h_rel; do
  [ -n "$h_rel" ] || continue
  h_want="$(h_pre_sha "$h_rel")"
  h_have="$(sha_of "$H/$h_rel")"
  if [ "$h_have" = "$h_want" ]; then
    pass "H.1: the reinstall kept the user's bytes in $h_rel"
  else
    fail "H.1: the reinstall overwrote $h_rel after announcing it under 'keeping yours' — data loss, contradicted by the same run's own output ($h_want -> $h_have)"
  fi
done <<< "$H_EDITED"

# H.2 — the rows. Reuses state G's precondition assertion: origin `user-modified`, checksum the
# EDITED one, so the next install still recognises the file as the user's.
while IFS= read -r h_rel; do
  [ -n "$h_rel" ] || continue
  assert_user_modified_row "$H" "$h_rel" "$(h_pre_sha "$h_rel")" "H.2"
done <<< "$H_EDITED"

# H.3 — the announcement and the writes agree.
#
# The list is printed with seven leading spaces by install.sh's warn block; `ok`/`warn` lines carry
# one. Anchoring on the exact indent keeps the following ok-line out of the block, and the count
# cross-check below fires if that formatting ever drifts, rather than letting a silently empty list
# pass every assertion that reads it.
h_announced() {
  awk '
    /installed file\(s\) have local edits/ { inblock = 1; next }
    inblock && /^       [^ ]/ { sub(/^ +/, ""); print; next }
    inblock { exit }
  ' <<< "$H_OUT"
}
H_ANNOUNCED="$(h_announced | sort)"
H_ANNOUNCED_COUNT="$(printf '%s' "$H_ANNOUNCED" | grep -c . || true)"
H_WARN_COUNT="$(sed -n 's/^warn \([0-9][0-9]*\) installed file(s) have local edits.*/\1/p' <<< "$H_OUT" | sort -u)"
if [ "$H_ANNOUNCED_COUNT" = "${H_WARN_COUNT:-0}" ] && [ "$H_ANNOUNCED_COUNT" -gt 0 ]; then
  pass "H.3: the run announced $H_ANNOUNCED_COUNT kept file(s), matching its own warn count"
else
  fail "H.3: parsed $H_ANNOUNCED_COUNT announced path(s) against a warn line claiming '${H_WARN_COUNT:-<none>}' — the list below is not being read, and every H.3 assertion is vacuous"
fi

while IFS= read -r h_rel; do
  [ -n "$h_rel" ] || continue
  h_want="$(h_pre_sha "$h_rel")"
  h_have="$(sha_of "$H/$h_rel")"
  if [ -z "$h_want" ]; then
    fail "H.3: the run announced $h_rel as kept, but no such file existed before the run"
  elif [ "$h_have" = "$h_want" ]; then
    pass "H.3: $h_rel was announced as kept and its bytes are unchanged"
  else
    fail "H.3: $h_rel was announced under 'keeping yours' and then rewritten ($h_want -> $h_have)"
  fi
done <<< "$H_ANNOUNCED"

# The announced set must be exactly the set edited — neither short (a file kept silently) nor long
# (a file announced and then written). Checked against the literal list as well as against the
# receipt, because the two failures those catch are different: this one catches an announcement that
# lost a file, the next catches a record that disagrees with the announcement.
H_EDITED_SORTED="$(sort <<< "$H_EDITED")"
if [ "$H_ANNOUNCED" = "$H_EDITED_SORTED" ]; then
  pass "H.3: the run announced exactly the $H_EDITED_COUNT script(s) the user edited"
else
  fail "H.3: announced [$(printf '%s' "$H_ANNOUNCED" | tr '\n' ' ')] against $H_EDITED_COUNT edited script(s) [$(printf '%s' "$H_EDITED_SORTED" | tr '\n' ' ')]"
fi

H_UM_ROWS="$(awk -F'\t' '$4 == "user-modified" { print $1 }' "$(receipt_of "$H")" | sort)"
if [ "$H_UM_ROWS" = "$H_ANNOUNCED" ]; then
  pass "H.3: the receipt's user-modified rows are exactly the paths the run announced as kept"
else
  fail "H.3: announced [$(printf '%s' "$H_ANNOUNCED" | tr '\n' ' ')] but recorded user-modified [$(printf '%s' "$H_UM_ROWS" | tr '\n' ' ')] — the run's claim and its record disagree"
fi

# H.4 — the untouched siblings are still overwritten, and still recorded toolkit.
#
# Presence is asserted separately from content, because the two fail for different reasons and one
# of them is a loop that stopped writing entirely rather than one that wrote the wrong bytes.
while IFS= read -r h_rel; do
  [ -n "$h_rel" ] || continue
  h_shipped="$(sha_of "$REPO/scripts/$(basename "$h_rel")")"
  if [ -f "$H/$h_rel" ]; then
    pass "H.4: $h_rel is on disk after the reinstall"
  else
    fail "H.4: $h_rel is not on disk — the scripts loop wrote nothing at all"
  fi
  if [ -n "$h_shipped" ] && [ "$(sha_of "$H/$h_rel")" = "$h_shipped" ]; then
    pass "H.4: the untouched $h_rel was replaced with the bytes this toolkit ships"
  else
    fail "H.4: $h_rel still carries the previous version's bytes — the loop stopped writing files nobody edited, which is an installer that does not install"
  fi
  assert_owned "$H" "$h_rel" "H.4 (untouched sibling)"
done <<< "$H_UNTOUCHED"

# H.5 — kept is counted as kept. `Installed N file(s), kept M of yours.` drops the second clause
# when M is 0, so an absent clause reads as 0. Both numbers are checked against things derived from
# the receipt rather than written down here.
H_WRITTEN="$(sed -n 's/.*Installed \([0-9][0-9]*\) file(s).*/\1/p' <<< "$H_OUT" | sort -u)"
H_KEPT="$(sed -n 's/.*Installed [0-9][0-9]* file(s), kept \([0-9][0-9]*\) of yours.*/\1/p' <<< "$H_OUT" | sort -u)"
H_KEPT="${H_KEPT:-0}"
H_UM_COUNT="$(printf '%s' "$H_UM_ROWS" | grep -c . || true)"
H_CLAUDE_ROWS="$(awk -F'\t' '$1 ~ /^\.claude\// { n++ } END { print n + 0 }' "$(receipt_of "$H")")"
if [ "$H_KEPT" = "$H_UM_COUNT" ]; then
  pass "H.5: the summary reports $H_KEPT kept, matching the $H_UM_COUNT user-modified row(s) it wrote"
else
  fail "H.5: the summary reports $H_KEPT kept against $H_UM_COUNT user-modified row(s) — a kept file counted as written, or the reverse"
fi
# Against the fixture too, not only against the receipt: the pair above agrees with itself when the
# loop keeps one of two edited files and records one row, which is exactly the cardinality-keyed
# failure this state was widened to catch.
if [ "$H_KEPT" = "$H_EDITED_COUNT" ]; then
  pass "H.5: the summary reports all $H_EDITED_COUNT edited script(s) as kept"
else
  fail "H.5: the summary reports $H_KEPT kept against $H_EDITED_COUNT edited script(s) — the loop kept some of them and wrote the rest"
fi
if [ -n "$H_WRITTEN" ] && [ "$((H_WRITTEN + H_KEPT))" = "$H_CLAUDE_ROWS" ]; then
  pass "H.5: written $H_WRITTEN + kept $H_KEPT = $H_CLAUDE_ROWS .claude rows — every path is accounted for exactly once"
else
  fail "H.5: written '${H_WRITTEN:-<unparsed>}' + kept $H_KEPT does not equal the $H_CLAUDE_ROWS .claude receipt rows — a file was counted twice or not at all"
fi

# ── States I…I5: CLAUDE.md.generated ─────────────────────────────────────────
# The fourth project-root file, and the one states A–F were structurally unable to see: every
# assertion above names its path in advance, and nothing here walks the project asking what
# appeared. It is written by ONE of the four paths through install.sh's CLAUDE.md block — the one
# taken when the user already has a CLAUDE.md of their own with no generated markers — announced
# by `wrote CLAUDE.md.generated instead`, pointed at by the "Next steps" summary, and until
# 2026-08-13 recorded by nothing. uninstall.sh removes only receipt-listed paths, so it was
# permanent debris in exactly the projects that already had a CLAUDE.md worth not overwriting.
#
# WHICH BRANCH EACH FIXTURE TAKES IS ASSERTED, NOT ASSUMED, for the reason E and F assert theirs:
# the four paths differ only in the content of a file the fixture sets up, and a fixture that drifts
# into the wrong one turns every assertion below it green against a branch that never ran.
#
# THIS FILE HAS NO SHIPPED COPY. MCP-SETUP.md and .mcp.json are compared against the toolkit's own
# bytes; CLAUDE.md.generated is generated per project from that project's Unity version, packages
# and provider, so install.sh passes '' as the reference and owned_by_installer's first arm is
# skipped by construction. Two things answer for it instead, and the states below are split so that
# each one is exercised alone:
#
#   I    fresh install, the `separate` branch          row present, uninstall removes it
#   I2   the same, installed twice                     row present, uninstall removes it
#   I3   the user's own file, the branch never runs    NO row,      uninstall leaves it
#   I4   ours, then a run that does NOT touch it       row present, uninstall removes it
#   I5   the user edits ours, then such a run          NO row,      uninstall leaves it
#
# I4 is B's shape for this file and it is the only state here that reaches the receipt half of the
# ownership test alone: install 1 takes `separate` with no previous receipt to consult, so run 1 is
# answered by the branch and nothing else, and a second install taking `separate` again is answered
# by the branch again. Only a run that leaves the file alone — the user took the block's own advice
# and added the markers to their CLAUDE.md, so every later run takes `refreshed` — can ask the
# receipt. Delete the receipt half and I4 is the state that goes red.
#
# I5 is D's shape: the row is renewed only while the file still carries the checksum the receipt
# recorded. The user filling in the FILL: markers is not a hypothetical edit here — it is step 2 of
# the summary this installer prints.
#
# WHAT THESE STATES CANNOT SEE
#   * The writing arm meeting a file it does not own. I3 fixes its fixture in the two shapes where
#     that arm never runs at all, because until 2026-08-13 the `mv` overwrote whatever was at the
#     path before any ownership question was asked — so in the third shape the row that follows
#     correctly claimed a file that was by then byte-for-byte ours, and no assertion here could tell
#     it from an ordinary fresh write. The arm asks first now; states K and K2 are that third shape.
#   * The generator's own output. Every state below treats it as opaque bytes; that it is
#     deterministic for a fixed project is relied on by I2 (which expects the same checksum twice)
#     and asserted nowhere.
#   * A generation FAILURE on run 2, where the block prints `CLAUDE.md generation failed — skipped.`
#     and leaves run 1's file in place. That path reaches the same receipt half I4 covers, by a
#     different route, and is not built here.
CLAUDE_GEN_REL='CLAUDE.md.generated'
SEPARATE_NEEDLE='wrote CLAUDE.md.generated instead'
MARKED_CLAUDE_MD='# My Own Game

SENTINEL-USER-PROSE-I

<!-- kinglet:generated:begin -->
<!-- kinglet:generated:end -->'

assert_separate_branch() {
  local label="$1"
  if grep -qF -- "$SEPARATE_NEEDLE" <<< "$INSTALL_OUT"; then
    pass "$label: the run took the branch that writes $CLAUDE_GEN_REL"
  else
    fail "$label: the run never announced '$SEPARATE_NEEDLE' — it took one of the other three CLAUDE.md paths, and every assertion below it is about a file this run did not write"
  fi
}

assert_not_separate_branch() {
  local label="$1"
  if grep -qF -- "$SEPARATE_NEEDLE" <<< "$INSTALL_OUT"; then
    fail "$label: the run announced '$SEPARATE_NEEDLE' — it wrote over the user's own $CLAUDE_GEN_REL, so this state is no longer testing a file the installer did not write"
  else
    pass "$label: the run did not take the branch that writes $CLAUDE_GEN_REL"
  fi
}

# ── State I: the user's own marker-less CLAUDE.md, one install ───────────────
I="$(new_fixture state-i)"
printf '# My Own Game\n\nSENTINEL-USER-PROSE-I\n' > "$I/CLAUDE.md"
I_MD_SHA="$(sha_of "$I/CLAUDE.md")"
run_install_flags "$I" "I install 1"
assert_separate_branch "I (fresh install)"
if [ -f "$I/$CLAUDE_GEN_REL" ]; then
  pass "I: $CLAUDE_GEN_REL is on disk after the install"
else
  fail "I: $CLAUDE_GEN_REL is not on disk — there is nothing here for a receipt row to own"
fi
assert_owned "$I" "$CLAUDE_GEN_REL" "I (fresh install)"
# The user's own CLAUDE.md is the file this whole branch exists to protect, and a row that reached
# one dot-suffix too far would take it.
assert_not_owned "$I" 'CLAUDE.md' "I (the user's own CLAUDE.md)"
run_uninstall "$I" "I"
assert_gone "$I" "$CLAUDE_GEN_REL" "I (fresh install)"
assert_kept "$I" 'CLAUDE.md' "$I_MD_SHA" "I (the user's own CLAUDE.md)"

# ── State I2: the same, installed twice ──────────────────────────────────────
I2="$(new_fixture state-i2)"
printf '# My Own Game\n\nSENTINEL-USER-PROSE-I\n' > "$I2/CLAUDE.md"
I2_MD_SHA="$(sha_of "$I2/CLAUDE.md")"
run_install_flags "$I2" "I2 install 1"
assert_separate_branch "I2 (install 1)"
run_install_flags "$I2" "I2 install 2"
assert_separate_branch "I2 (install 2)"
assert_owned "$I2" "$CLAUDE_GEN_REL" "I2 (second install)"
run_uninstall "$I2" "I2"
assert_gone "$I2" "$CLAUDE_GEN_REL" "I2 (second install)"
assert_kept "$I2" 'CLAUDE.md' "$I2_MD_SHA" "I2 (the user's own CLAUDE.md)"

# ── State I3: a CLAUDE.md.generated the USER wrote ───────────────────────────
# The fail-closed direction, and the one where a mistake deletes something the installer never made.
# Two shapes, because the branch must not run in either and it is skipped for two different reasons:
#
#   absent   — no CLAUDE.md at all, so the installer writes CLAUDE.md and never looks at .generated
#   markers  — a CLAUDE.md carrying the markers, so the installer refreshes it in place
#
# In both, nothing this run knows can distinguish the user's file from one of ours except the
# previous receipt, which has no row for it. Two installs each, because "no row" is also what the
# unfixed installer produces, and a state that is right for the wrong reason on run 1 is
# indistinguishable from one that is right.
for i3_shape in absent markers; do
  I3="$(new_fixture "state-i3-$i3_shape")"
  if [ "$i3_shape" = absent ]; then
    rm -f "$I3/CLAUDE.md"
  else
    printf '%s\n' "$MARKED_CLAUDE_MD" > "$I3/CLAUDE.md"
  fi
  printf 'My own notes, in a file I named myself. SENTINEL-I3-MINE\n' > "$I3/$CLAUDE_GEN_REL"
  I3_SHA="$(sha_of "$I3/$CLAUDE_GEN_REL")"

  run_install_flags "$I3" "I3/$i3_shape install 1"
  assert_not_separate_branch "I3/$i3_shape (install 1)"
  assert_not_owned "$I3" "$CLAUDE_GEN_REL" "I3/$i3_shape (after install 1)"

  run_install_flags "$I3" "I3/$i3_shape install 2"
  assert_not_separate_branch "I3/$i3_shape (install 2)"
  assert_not_owned "$I3" "$CLAUDE_GEN_REL" "I3/$i3_shape (after install 2)"

  run_uninstall "$I3" "I3/$i3_shape"
  assert_kept "$I3" "$CLAUDE_GEN_REL" "$I3_SHA" "I3/$i3_shape"
done

# ── State I4: ours, then a run that never touches it ─────────────────────────
# The user does exactly what install.sh told them to — "add the markers to let us refresh in place"
# — so run 2 takes `refreshed` and the file run 1 wrote is not touched by anything. The branch
# cannot answer for it; only the previous receipt can.
I4="$(new_fixture state-i4)"
printf '# My Own Game\n\nSENTINEL-USER-PROSE-I\n' > "$I4/CLAUDE.md"
run_install_flags "$I4" "I4 install 1"
assert_separate_branch "I4 (install 1)"
assert_owned "$I4" "$CLAUDE_GEN_REL" "I4 (after install 1)"
I4_GEN_SHA="$(sha_of "$I4/$CLAUDE_GEN_REL")"
printf '%s\n' "$MARKED_CLAUDE_MD" > "$I4/CLAUDE.md"

run_install_flags "$I4" "I4 install 2"
assert_not_separate_branch "I4 (install 2 refreshes CLAUDE.md in place)"
if [ "$(sha_of "$I4/$CLAUDE_GEN_REL")" = "$I4_GEN_SHA" ]; then
  pass "I4: install 2 left $CLAUDE_GEN_REL byte-for-byte as install 1 wrote it"
else
  fail "I4: install 2 rewrote $CLAUDE_GEN_REL — the state's premise is that nothing touched it, and the receipt half of the ownership test is not what answered here"
fi
assert_owned "$I4" "$CLAUDE_GEN_REL" "I4 (a run that never touched the file)"
run_uninstall "$I4" "I4"
assert_gone "$I4" "$CLAUDE_GEN_REL" "I4 (a run that never touched the file)"

# ── State I5: the user edits ours, then such a run ───────────────────────────
# Filling in the FILL: markers is step 2 of the summary this installer prints. After install 1 the
# receipt records the file as `toolkit`, so an ownership test that reads only "was it in the last
# receipt?" renews the claim and uninstall.sh deletes the work the installer asked for.
I5="$(new_fixture state-i5)"
printf '# My Own Game\n\nSENTINEL-USER-PROSE-I\n' > "$I5/CLAUDE.md"
run_install_flags "$I5" "I5 install 1"
assert_separate_branch "I5 (install 1)"
assert_owned "$I5" "$CLAUDE_GEN_REL" "I5 (before the user's edit)"
printf '\nI filled these in by hand. SENTINEL-I5-MY-WORK\n' >> "$I5/$CLAUDE_GEN_REL"
I5_SHA="$(sha_of "$I5/$CLAUDE_GEN_REL")"
printf '%s\n' "$MARKED_CLAUDE_MD" > "$I5/CLAUDE.md"

run_install_flags "$I5" "I5 install 2"
assert_not_separate_branch "I5 (install 2 refreshes CLAUDE.md in place)"
assert_not_owned "$I5" "$CLAUDE_GEN_REL" "I5 (edited, then reinstalled)"
run_install_flags "$I5" "I5 install 3"
assert_not_owned "$I5" "$CLAUDE_GEN_REL" "I5 (edited, then reinstalled twice)"
run_uninstall "$I5" "I5"
assert_kept "$I5" "$CLAUDE_GEN_REL" "$I5_SHA" "I5"

# ── State J: both --with-* flags in one run, one backup, one row ─────────────
# Not a new file — this is E's file and Task 2's placement decision, asserted. install.sh calls
# add_manifest_dependency once per --with-* flag, and BOTH can reach the branch that keeps the
# backup in a single run against a project missing both packages. The row is therefore written once,
# after both callers, rather than inside the branch. Moving it back inside is the tidying refactor a
# later reader makes, and nothing measured the consequence: two rows for one path, disagreeing on
# the checksum, at which point uninstall.sh classifies them separately, prints `keep 1 file(s) you
# modified` naming the file, and removes it in the same run. Measured on a scratch copy 2026-08-13.
#
# Nothing else in this file passes --with-input-system, and nothing else uses the builtin variant:
# the urp fixture already carries com.unity.inputsystem, so that flag returns early there and only
# one caller ever reaches the backup.
new_fixture_variant() {
  local d="$SCRATCH/$1"
  bash "$REPO/tests/fixtures/mkproject.sh" "$d" --variant "$2" >/dev/null
  printf '%s' "$d"
}

J="$(new_fixture_variant state-j builtin)"
if git -C "$J" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "J: the fixture is inside a git work tree — install.sh would delete the backup instead of keeping it, and 'exactly one row' would hold because there are none"
else
  pass "J: the fixture is not under git, so install.sh must keep the backup it makes"
fi
# Both packages absent is the precondition. With either already present its caller returns early,
# only one reaches the backup branch, and the cardinality below is one for a reason that has nothing
# to do with where the row is written.
# `if`, not `cmd && var=1`: a false test makes the whole AND-list exit 1, and as a top-level command
# under `set -e` that ends the file rather than setting the variable to 0 it already holds.
J_PRE_MCP=0; J_PRE_INPUT=0
if grep -qF -- 'com.coplaydev.unity-mcp' "$J/$MANIFEST_REL"; then J_PRE_MCP=1; fi
if grep -qF -- 'com.unity.inputsystem' "$J/$MANIFEST_REL"; then J_PRE_INPUT=1; fi
if [ "$J_PRE_MCP" -eq 0 ] && [ "$J_PRE_INPUT" -eq 0 ]; then
  pass "J: the fixture's manifest carries neither package, so both callers reach the backup branch"
else
  fail "J: the fixture's manifest already carries one of the two packages (mcp=$J_PRE_MCP inputsystem=$J_PRE_INPUT) — one caller returns early and this state proves nothing about two"
fi

run_install_flags "$J" "J install" --with-mcp --with-input-system
# Two announcements, one per caller. Counted rather than matched, because one is what the state is
# trying to tell apart from two — and `grep -c` on no match exits 1, which under `set -e` would end
# the file here rather than report.
J_ANNOUNCED="$(grep -cF -- '(backup: manifest.json.bak)' <<< "$INSTALL_OUT" || true)"
if [ "$J_ANNOUNCED" = "2" ]; then
  pass "J: both callers reached the branch that keeps the backup (2 announcements)"
else
  fail "J: the run announced a kept backup $J_ANNOUNCED time(s), not 2 — only one caller reached the keep branch, so one row would be correct here for the wrong reason"
fi
if [ -f "$J/$MANIFEST_BAK_REL" ]; then
  pass "J: $MANIFEST_BAK_REL is on disk after the run"
else
  fail "J: $MANIFEST_BAK_REL is not on disk — nothing here for a row to claim"
fi
# The count is extracted and compared as a number. A needle like '1 row' also matches '11 rows'.
J_ROWS="$(awk -F'\t' -v want="$MANIFEST_BAK_REL" '$1 == want { n++ } END { print n + 0 }' "$(receipt_of "$J")")"
if [ "$J_ROWS" = "1" ]; then
  pass "J: the receipt carries exactly one $MANIFEST_BAK_REL row"
else
  fail "J: the receipt carries $J_ROWS rows for $MANIFEST_BAK_REL — one path claimed more than once, and uninstall.sh reads them as separate files"
fi
# Cardinality alone would be satisfied by one STALE row. The surviving row must describe the file
# that survived.
assert_owned "$J" "$MANIFEST_BAK_REL" "J (both flags in one run)"

# ── States K…K3: the two writers that overwrite without asking ───────────────
# Spec D11, acceptance criterion 14, and criterion 13's third clause as it is actually written.
#
# Every state above asks whether the RECEIPT is right. These ask whether the FILE is still there.
# install.sh had two writers that put bytes on disk before anything asked whose they were:
#
#   mv "$TMP_MD" "$PROJECT_DIR/CLAUDE.md.generated"   # the separate-file branch
#   cp "$MANIFEST" "$MANIFEST.bak"                     # add_manifest_dependency, per --with-* flag
#
# I3 and E3 are the fail-closed states for these two files, and both are structurally blind to this:
# I3 fixes its fixture in the two shapes where the writing arm never runs at all, and E3 uses a plain
# install that never calls add_manifest_dependency. Neither ever lets the writer meet a file it does
# not own. K–K3 do exactly that, on the three paths the spec reproduces.
#
# THE AGGRAVATING HALF IS THIS WAVE'S OWN. Before Tasks 2 and 2b there were no receipt rows for these
# paths, so the upgrade scan never named them. With the rows in place both appear in MODIFIED_FILES,
# and the run printed `keeping yours:` naming a file it destroyed four lines later. That is why each
# state below asserts the OUTPUT as well as the bytes: a silent overwrite is data loss, and an
# overwrite announced as a keep is data loss the user was told did not happen.
#
#   K   ours, the user fills in the FILL: markers, install again   bytes survive, NO row
#   K2  the user's own file, first install ever, twice             bytes survive, NO row
#   K3  ours, the user edits the backup, a second --with-* flag    bytes survive, manifest unedited
#
# K2 is also criterion 13's third clause AS WRITTEN — a marker-less CLAUDE.md and a user-authored
# CLAUDE.md.generated, across two installs, the file getting no row and surviving. Task 2b could only
# assert the narrowed reading (I3's two shapes) because on this fixture the user's file was destroyed
# before ownership was ever asked.
#
# EACH STATE ASSERTS THE ANTI-"NEVER WRITE ANYTHING" DIRECTION IN ITS OWN BODY, because a decline
# that is too wide passes every bytes-survive assertion here by refusing to install. K's install 1
# writes and records the file; K3's install 1 edits the manifest and keeps its backup; and K2 and K3
# each end by clearing the user's file out of the way and re-running, which is the remedy the decline
# messages promise — so the promise is measured rather than printed.
#
# WHAT THESE STATES CANNOT SEE
#   * The dry run. `install.sh --dry-run` prints `CLAUDE.md.generated — yours exists and has no
#     markers, so it is NOT touched`, which D11 names as the third surface saying the opposite of what
#     happens. Nothing here runs --dry-run; that line is still wrong in the case where the installer
#     legitimately writes the file, and closing it is the dry-run guard's job, not this file's.
#   * Any third writer. Like every state above, these name their paths in advance.
#   * uninstall.sh's treatment of a file the user wrote at a path the installer would have used is
#     asserted only via the receipt (`assert_not_owned` then `assert_kept`); nothing here inspects
#     uninstall.sh's own reasoning.
#   * assert_keeping_yours_is_true is a CONDITIONAL, so it passes vacuously when the run makes no
#     claim at all. That is correct — K2's first install has no previous receipt to drive the scan —
#     but it means a change that stopped the upgrade scan naming these paths would go unnoticed here.
#     What guards that is the receipt row itself, asserted by I, I4, E and J: no row, no entry in
#     MODIFIED_FILES, and those states go red first.
#   * WHY a run declined. The needles prove the decline was announced, not that the ownership test
#     produced it. A writer hard-wired never to write satisfies every bytes assertion here, which is
#     what the anti-"never write anything" halves in each state body are for.

KEPT_GEN_NEEDLE='CLAUDE.md.generated exists and is not ours'
NOT_TOUCHED_NEEDLE='Yours was not touched.'

# The paths the upgrade scan listed under `keeping yours:`, one per line. Parsed rather than matched
# as a substring: the claim is about a specific path, and `grep -F CLAUDE.md.generated` on the whole
# output also matches the write announcement and the Next-steps summary.
#
# The block is `warn N installed file(s) have local edits — keeping yours:` followed by one path per
# line at seven spaces of indent, so the terminator is the first line that is not indented that way.
kept_list() {
  awk '
    /keeping yours:/            { grab = 1; next }
    grab && /^       [^ ]/      { sub(/^       /, ""); print; next }
    grab                        { grab = 0 }
  ' <<< "$INSTALL_OUT"
}

# Criterion 14, verbatim: "no run claims `keeping yours` about a file it overwrote". The claim is not
# itself the defect — once the writer declines, the file really is kept and saying so is the honest
# thing. It is the claim TOGETHER WITH the overwrite that D8 called worse than silent data loss. So
# this is a conditional, and the branch that matters prints which way it went.
assert_keeping_yours_is_true() {
  local d="$1" rel="$2" want="$3" label="$4" claimed=0 have
  if grep -qxF -- "$rel" <<< "$(kept_list)"; then claimed=1; fi
  have="$(sha_of "$d/$rel")"
  if [ "$claimed" -eq 0 ]; then
    pass "$label: the run made no 'keeping yours' claim about $rel"
  elif [ "$have" = "$want" ]; then
    pass "$label: the run listed $rel under 'keeping yours' and the file still carries those bytes"
  else
    fail "$label: the run listed $rel under 'keeping yours' and overwrote it in the same run ($want -> $have)"
  fi
}

# Presence plus bytes, on a live project rather than after an uninstall — assert_kept is the
# post-uninstall sibling of this one.
assert_survived() {
  local d="$1" rel="$2" want="$3" label="$4" have
  if [ ! -e "$d/$rel" ]; then
    fail "$label: the installer deleted $rel, which the user wrote"
    return
  fi
  have="$(sha_of "$d/$rel")"
  if [ "$have" = "$want" ]; then
    pass "$label: $rel still carries the user's bytes after the run"
  else
    fail "$label: the installer overwrote $rel — the user's bytes are gone ($want -> $have)"
  fi
}

assert_declined_gen() {
  local label="$1"
  if grep -qF -- "$KEPT_GEN_NEEDLE" <<< "$INSTALL_OUT"; then
    pass "$label: the run announced that it kept the user's $CLAUDE_GEN_REL"
  else
    fail "$label: the run never announced '$KEPT_GEN_NEEDLE' — it did not reach the decline, so a surviving file below is surviving for some other reason"
  fi
  if grep -qF -- "$NOT_TOUCHED_NEEDLE" <<< "$INSTALL_OUT"; then
    fail "$label: the run printed '$NOT_TOUCHED_NEEDLE', which belongs to the announcement of a write it did not make"
  else
    pass "$label: the run did not print '$NOT_TOUCHED_NEEDLE'"
  fi
}

# ── State K: ours, then the user does what the summary told them to ──────────
# Step 2 of install.sh's own Next-steps summary is "Fill in the FILL: markers in
# CLAUDE.md.generated". Before D11 the edit survived zero reinstalls: the `mv` ran again, the nine
# markers came back, and the run said `keeping yours: CLAUDE.md.generated` in the same output.
#
# I5 is this state's sibling and reaches "no row" by a different route: there the user adds the
# markers to CLAUDE.md so run 2 takes `refreshed` and the writer never executes. Here CLAUDE.md stays
# marker-less, so run 2 enters the writing arm and has to decline inside it.
K="$(new_fixture state-k)"
printf '# My Own Game\n\nSENTINEL-USER-PROSE-K\n' > "$K/CLAUDE.md"
K_MD_SHA="$(sha_of "$K/CLAUDE.md")"
run_install_flags "$K" "K install 1"
# Anti-"never write anything", half 1: the installer must still produce and claim its own file.
assert_separate_branch "K (install 1)"
assert_owned "$K" "$CLAUDE_GEN_REL" "K (install 1, the file is ours)"
# The FILL: markers are the installer's own instruction, so their presence is the premise of the edit
# below rather than a detail of the generator.
# `awk`, not `grep -c`: on a missing file grep prints nothing and exits 2, and the `-gt` below then
# gets an empty string, which is a `[: integer expression expected` on stderr rather than an
# assertion — the shape sha_of's own comment warns about, one helper over.
K_MARKERS_BEFORE="$(awk '/FILL:/ { n++ } END { print n + 0 }' "$K/$CLAUDE_GEN_REL" 2>/dev/null || echo 0)"
if [ "$K_MARKERS_BEFORE" -gt 0 ]; then
  pass "K: install 1's $CLAUDE_GEN_REL carries the FILL: markers the summary tells the user to fill in"
else
  fail "K: install 1's $CLAUDE_GEN_REL carries no FILL: markers — the edit below is not the one the installer asks for"
fi
# THE EDIT IS THE STATE'S PREMISE AND MUST NOT BE THE STATE'S DEATH. Guarded, because under a
# "never write anything" regression install 1 leaves nothing here: `sed -i` on a missing path exits
# 2, `set -e` ends the FILE at this line, and K2 and K3 — 38 assertions, including both
# anti-"never write anything" halves — never run. Measured 2026-08-13 with the CLAUDE.md.generated
# guard mutated to `if true` (always decline). That is this file's own sha_of hazard one helper
# over: "A probe that dies is a probe that reports nothing."
#
# `printf >>` is inside the guard too, and not for symmetry: on a missing path it CREATES the file,
# and every assertion below would then be measuring bytes this test wrote rather than the
# installer's.
if [ -f "$K/$CLAUDE_GEN_REL" ]; then
  sed -i 's/FILL:/FILLED-IN-BY-HAND:/g' "$K/$CLAUDE_GEN_REL"
  printf '\nSENTINEL-K-MY-WORK\n' >> "$K/$CLAUDE_GEN_REL"
  pass "K: the user's edit was applied to the file install 1 wrote"
else
  fail "K: install 1 left no $CLAUDE_GEN_REL to edit — K's premise is absent, and every assertion below describes a file that was never there"
fi
K_SHA="$(sha_of "$K/$CLAUDE_GEN_REL")"

run_install_flags "$K" "K install 2"
assert_survived "$K" "$CLAUDE_GEN_REL" "$K_SHA" "K (install 2)"
assert_not_separate_branch "K (install 2)"
assert_declined_gen "K (install 2)"
assert_keeping_yours_is_true "$K" "$CLAUDE_GEN_REL" "$K_SHA" "K (install 2)"
# The markers must not be back. Counted and compared as a number rather than matched: the count is
# what the user lost, and a needle like '9 markers' would also match '19'.
K_MARKERS_AFTER="$(awk '/FILL:/ { n++ } END { print n + 0 }' "$K/$CLAUDE_GEN_REL" 2>/dev/null || echo 0)"
if [ "$K_MARKERS_AFTER" -eq 0 ]; then
  pass "K: install 2 did not put the FILL: markers back — the user's filled-in file is what is on disk"
else
  fail "K: install 2 restored $K_MARKERS_AFTER FILL: marker(s) — the edit the installer asked for was overwritten"
fi
assert_not_owned "$K" "$CLAUDE_GEN_REL" "K (edited, then a run that entered the writing arm)"
run_uninstall "$K" "K"
assert_kept "$K" "$CLAUDE_GEN_REL" "$K_SHA" "K"
assert_kept "$K" 'CLAUDE.md' "$K_MD_SHA" "K (the user's own CLAUDE.md)"

# ── State K2: a CLAUDE.md.generated the user wrote, before any install ever ──
# Criterion 13's third clause as written, and the harshest shape of the defect: there is no previous
# receipt to consult, nothing on disk that is ours, and the run destroyed the file and then recorded
# it as `toolkit` — so the next uninstall would have removed what was left.
#
# Two installs, because "no row" is also what the unfixed installer produced on run 1 for the wrong
# reason: it had overwritten the file with our own bytes and had no receipt to match them against.
K2="$(new_fixture state-k2)"
printf '# My Own Game\n\nSENTINEL-USER-PROSE-K2\n' > "$K2/CLAUDE.md"
K2_MD_SHA="$(sha_of "$K2/CLAUDE.md")"
printf 'My own notes, in a file I named myself. SENTINEL-K2-MINE\n' > "$K2/$CLAUDE_GEN_REL"
K2_SHA="$(sha_of "$K2/$CLAUDE_GEN_REL")"

run_install_flags "$K2" "K2 install 1"
assert_survived "$K2" "$CLAUDE_GEN_REL" "$K2_SHA" "K2 (first install ever)"
assert_not_separate_branch "K2 (install 1)"
assert_declined_gen "K2 (install 1)"
assert_not_owned "$K2" "$CLAUDE_GEN_REL" "K2 (after install 1)"

run_install_flags "$K2" "K2 install 2"
assert_survived "$K2" "$CLAUDE_GEN_REL" "$K2_SHA" "K2 (second install)"
assert_declined_gen "K2 (install 2)"
assert_keeping_yours_is_true "$K2" "$CLAUDE_GEN_REL" "$K2_SHA" "K2 (install 2)"
assert_not_owned "$K2" "$CLAUDE_GEN_REL" "K2 (after install 2)"

# Anti-"never write anything", and the decline message's own promise: "rename or delete it and
# re-run". Measured, because an installer that can never write this file again after seeing a
# stranger at that path passes every assertion above.
rm -f "$K2/$CLAUDE_GEN_REL"
run_install_flags "$K2" "K2 install 3"
assert_separate_branch "K2 (install 3, the user's file removed)"
assert_owned "$K2" "$CLAUDE_GEN_REL" "K2 (install 3, the path is free again)"
run_uninstall "$K2" "K2"
assert_gone "$K2" "$CLAUDE_GEN_REL" "K2 (install 3's file is ours)"
assert_kept "$K2" 'CLAUDE.md' "$K2_MD_SHA" "K2 (the user's own CLAUDE.md)"

# ── State K3: the manifest backup, and the flag that must decline with it ────
# D11 answers this file differently from CLAUDE.md.generated, deliberately and asymmetrically: the
# installer declines THE MANIFEST EDIT ITSELF for that flag. A backup exists to make a risky edit
# recoverable, so making the edit while skipping the backup keeps the risk and drops the mitigation.
#
# The builtin variant carries neither package, so both --with-* flags have work to do. E and J use
# one run; this state needs two, because the file in the way has to be there before the second `cp`.
K3="$(new_fixture_variant state-k3 builtin)"
if git -C "$K3" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "K3: the fixture is inside a git work tree — install.sh deletes the backup instead of keeping it, and there would be no file here for the user to edit"
else
  pass "K3: the fixture is not under git, so install.sh must keep the backup it makes"
fi
K3_MCP_PKG='com.coplaydev.unity-mcp'
K3_INPUT_PKG='com.unity.inputsystem'

run_install_flags "$K3" "K3 install 1" --with-mcp
# Anti-"never write anything", half 1: the flag works when nothing is in the way.
if grep -qF -- "$K3_MCP_PKG" "$K3/$MANIFEST_REL"; then
  pass "K3: install 1 added $K3_MCP_PKG to the manifest"
else
  fail "K3: install 1 did not add $K3_MCP_PKG — the flag did no work, and the backup below is not the one this state is about"
fi
assert_owned "$K3" "$MANIFEST_BAK_REL" "K3 (install 1, the backup is ours)"
# Guarded for K's reason, in the direction this file is exposed to: `>>` on a missing path CREATES
# it, so under a regression where install 1 makes no backup the state would go on to measure a file
# the TEST wrote — and the `mv` further down would then be moving the test's own bytes.
if [ -f "$K3/$MANIFEST_BAK_REL" ]; then
  printf '\n// SENTINEL-K3-MY-EDIT-TO-THE-BACKUP\n' >> "$K3/$MANIFEST_BAK_REL"
  pass "K3: the user's edit was applied to the backup install 1 kept"
else
  fail "K3: install 1 kept no $MANIFEST_BAK_REL to edit — K3's premise is absent, and every assertion below describes a file that was never there"
fi
K3_SHA="$(sha_of "$K3/$MANIFEST_BAK_REL")"
K3_MANIFEST_SHA="$(sha_of "$K3/$MANIFEST_REL")"

run_install_flags "$K3" "K3 install 2" --with-input-system
assert_survived "$K3" "$MANIFEST_BAK_REL" "$K3_SHA" "K3 (install 2)"
assert_keeping_yours_is_true "$K3" "$MANIFEST_BAK_REL" "$K3_SHA" "K3 (install 2)"
if grep -qF -- "declining --with-input-system" <<< "$INSTALL_OUT"; then
  pass "K3: the run announced that it declined --with-input-system"
else
  fail "K3: the run never announced a declined --with-input-system — a surviving backup below is surviving for some other reason"
fi
# The asymmetry, asserted. Declining only the `cp` would leave the manifest edited with no backup.
if grep -qF -- "$K3_INPUT_PKG" "$K3/$MANIFEST_REL"; then
  fail "K3: the manifest carries $K3_INPUT_PKG — the edit went ahead without the backup that makes it undoable, which is the half D11 rejects"
else
  pass "K3: the manifest does not carry $K3_INPUT_PKG — the edit was declined along with its backup"
fi
if [ "$(sha_of "$K3/$MANIFEST_REL")" = "$K3_MANIFEST_SHA" ]; then
  pass "K3: the manifest is byte-for-byte as install 1 left it"
else
  fail "K3: the manifest changed during the declined run — something edited it besides the flag"
fi
assert_not_owned "$K3" "$MANIFEST_BAK_REL" "K3 (the user's backup, after install 2)"

# Anti-"never write anything", half 2, and the decline message's promise: move the file aside and the
# flag proceeds.
K3_MINE="$MANIFEST_BAK_REL.mine"
# Same guard, third instance: `mv` on a missing source exits 1 and `set -e` would end the file here,
# taking install 3 — this state's whole anti-"never write anything" half — with it.
if [ -e "$K3/$MANIFEST_BAK_REL" ]; then
  mv "$K3/$MANIFEST_BAK_REL" "$K3/$K3_MINE"
  pass "K3: the user's backup was moved aside, so nothing is in the flag's way any more"
else
  fail "K3: there is no $MANIFEST_BAK_REL to move aside — install 3 below cannot show that moving it lets the flag proceed"
fi
run_install_flags "$K3" "K3 install 3" --with-input-system
if grep -qF -- "$K3_INPUT_PKG" "$K3/$MANIFEST_REL"; then
  pass "K3: install 3 added $K3_INPUT_PKG once the user's backup was moved aside"
else
  fail "K3: install 3 still did not add $K3_INPUT_PKG — the decline is permanent, and moving the file aside does not do what the message says it does"
fi
assert_owned "$K3" "$MANIFEST_BAK_REL" "K3 (install 3, a backup that is ours again)"
run_uninstall "$K3" "K3"
assert_gone "$K3" "$MANIFEST_BAK_REL" "K3 (install 3's backup is ours)"
assert_kept "$K3" "$K3_MINE" "$K3_SHA" "K3 (the user's backup, moved aside)"

# ── States L…O2: the receipt has to exist before anything that can abort ─────
#
# Everything above asks whether a row is right. These ask whether the receipt EXISTS AT ALL, which
# is the one failure in this file that cannot be undone by re-running anything.
#
# install.sh writes $RECEIPT at Step 9, after Steps 5–8c. Every one of those steps can die under
# `set -euo pipefail`, and one of them dies on an input a user can produce by accident: a dangling
# symlink at Packages/manifest.json.bak. `[ -e ]` is false through a dangling link, so the D11
# decline does not fire; `cp "$MANIFEST" "$MANIFEST.bak"` then reports `not writing through dangling
# symlink` and `set -e` ends the run — with the whole payload on disk and NO receipt. uninstall.sh
# refuses to run without one ("Refusing to guess which files are ours"), so the project is stuck
# with an install nothing can remove. Measured on the tree before this state existed: rc=1, the
# receipt directory created and empty.
#
#   L   dangling symlink at the .bak path, --with-mcp   a receipt exists, covering what was written;
#                                                       uninstall cleans the project; the user's
#                                                       symlink is not touched
#   M   the installer CREATES .gitignore                row present, survives a second install,
#                                                       uninstall removes it
#   M2  a .gitignore the user already had               NO row, uninstall leaves it and their line
#   M3  ours, then the user edits it                    NO row, uninstall leaves it
#   N   an unreadable origin column, across an upgrade  the row is re-claimed, not dropped
#   N2  an unreadable `user-modified `, same recipe     NOT re-claimed — the trim opens no hole
#   O   a foreign .claude/ (no receipt)                 still backed up, still not merged, and the
#                                                       foreign file is not claimed
#   O2  a run that aborts having installed NOTHING      NO receipt — this did not become "always
#                                                       write a receipt"
#
# WHAT THESE CANNOT SEE
#   * L asserts one abort site. It is the one a user reaches without doing anything unusual, but
#     Steps 5–8c contain many commands and this file exercises exactly one of their failures. The
#     property is structural (the trap covers every abort after it is armed); the evidence here is
#     one instance of it.
#   * O2 aborts immediately after the trap is armed, so it proves the empty-$RECEIPT_TMP guard and
#     nothing about an abort partway through the payload loop.
#   * Nothing here reads install.sh. A rewrite that made the receipt correct by writing it twice, or
#     early enough to change what owned_by_installer reads, would pass every assertion below.
#   * N and N2 mangle the origin column by hand, because install.sh cannot produce either shape.
#     They assert a direction, not a live case — the same standing as G.5.

new_fixture_variant() {
  local d="$SCRATCH/$1"
  bash "$REPO/tests/fixtures/mkproject.sh" "$d" --variant "$2" >/dev/null
  printf '%s' "$d"
}

# ── State L: a dangling symlink where the manifest backup goes ───────────────
L="$(new_fixture_variant state-l urp)"
# The fixture must actually carry a manifest, or --with-mcp returns early and this state exercises
# nothing. Asserted rather than assumed — a state that builds its own premise measures itself.
if [ -f "$L/$MANIFEST_REL" ]; then
  pass "L: the fixture has a $MANIFEST_REL for --with-mcp to edit"
else
  fail "L: the fixture has no $MANIFEST_REL — --with-mcp returns early and every L assertion below is vacuous"
fi
ln -s /nonexistent "$L/$MANIFEST_BAK_REL"
if [ -L "$L/$MANIFEST_BAK_REL" ] && [ ! -e "$L/$MANIFEST_BAK_REL" ]; then
  pass "L: $MANIFEST_BAK_REL is a dangling symlink — [ -e ] is false through it, which is what defeats the decline"
else
  fail "L: $MANIFEST_BAK_REL is not a dangling symlink — the abort this state is about does not happen"
fi
# NOT run_install_flags: this run is EXPECTED to exit non-zero today, and a helper that fails the
# state on a non-zero status would report the defect as a red in the wrong place. The status is
# recorded and reported; what is asserted is the receipt.
L_RC=0
L_OUT="$(KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
      bash "$REPO/install.sh" --project-dir "$L" --with-mcp --yes </dev/null 2>&1 \
      | sed $'s/\x1b\\[[0-9;]*m//g')" || L_RC=$?
L_RECEIPT="$(receipt_of "$L")"
# The payload landed. Without this the receipt assertion below could pass on a run that installed
# nothing at all, which is a different (and fine) outcome.
# `|| true` on the pipeline, not decoration: `find` on a missing directory exits 1, `pipefail`
# promotes that past `wc`, and at an ASSIGNMENT `set -e` would end this file here — mid-state, with
# every assertion below reading as absent rather than red.
L_ON_DISK="$(find "$L/.claude" -type f ! -path '*/state/*' 2>/dev/null | wc -l | tr -d ' ' || true)"
if [ "$L_ON_DISK" -gt 0 ]; then
  pass "L: the run wrote $L_ON_DISK file(s) under .claude/ before it stopped (exit $L_RC)"
else
  fail "L: nothing was installed under .claude/, so this state says nothing about a receipt for an interrupted install"
fi
if [ -f "$L_RECEIPT" ]; then
  pass "L: a receipt exists after the run stopped at the manifest backup"
else
  fail "L: no receipt after the run stopped — uninstall.sh refuses to touch a project it cannot prove is ours, so those $L_ON_DISK file(s) are permanent"
fi
L_ROWS="$(awk -F'\t' '$1 ~ /^\.claude\// { n++ } END { print n + 0 }' "$L_RECEIPT" 2>/dev/null || printf '0')"
if [ "$L_ROWS" -eq "$L_ON_DISK" ]; then
  pass "L: the receipt claims all $L_ON_DISK installed .claude/ file(s)"
else
  fail "L: the receipt claims $L_ROWS .claude/ file(s) but $L_ON_DISK are on disk — the difference is what uninstall.sh leaves behind"
fi
run_uninstall "$L" "L"
# FILES, not the directory. An ordinary uninstall leaves empty directories behind too — uninstall.sh
# prunes with `find ... -depth -type d -empty -exec rmdir {} +`, and the `+` batches every path into
# one rmdir call, so a parent is attempted before its children are gone. Measured on a plain
# install/uninstall of the default fixture: .claude/ and .claude/skills/ survive, holding nothing.
# That is uninstall.sh's, not this task's, and asserting on the directory here would red on it.
L_LEFT="$(find "$L/.claude" -type f 2>/dev/null | wc -l | tr -d ' ' || true)"
if [ "$L_LEFT" -eq 0 ]; then
  pass "L: uninstall.sh removed every file the interrupted run installed"
else
  fail "L: $L_LEFT file(s) from the interrupted run survived the uninstall"
fi
# The user's own file — a broken symlink is still theirs — is not ours to remove or repair.
if [ -L "$L/$MANIFEST_BAK_REL" ]; then
  pass "L: the user's dangling symlink is untouched"
else
  fail "L: the user's dangling symlink at $MANIFEST_BAK_REL was removed or replaced"
fi

# ── State M: a .gitignore the installer created ──────────────────────────────
# `bare` has no .gitignore, which is the only variant that reaches the create branch. The default
# fixture ships an empty one, so every other state in this file takes the append path and none of
# them can see this.
GITIGNORE_REL='.gitignore'
M="$(new_fixture_variant state-m bare)"
if [ -e "$M/$GITIGNORE_REL" ]; then
  fail "M: the bare fixture already has a $GITIGNORE_REL — the installer will append rather than create, and this state tests the wrong branch"
else
  pass "M: the bare fixture has no $GITIGNORE_REL, so the installer must create one"
fi
run_install "$M" "M install 1"
if [ -f "$M/$GITIGNORE_REL" ]; then
  pass "M: the installer created $GITIGNORE_REL"
else
  fail "M: the installer did not create $GITIGNORE_REL — nothing below is about a file that exists"
fi
assert_owned "$M" "$GITIGNORE_REL" "M (the installer created it)"
# Ownership, not authorship: run 2 appends nothing, so a row written where the file is CREATED
# disappears here and the file becomes permanent debris one run later.
run_install "$M" "M install 2"
assert_owned "$M" "$GITIGNORE_REL" "M (second install, nothing appended)"
run_uninstall "$M" "M"
assert_gone "$M" "$GITIGNORE_REL" "M (a file only we ever wrote)"

# ── State M2: a .gitignore the user already had ──────────────────────────────
# The installer appends to it. Appending is not authorship, and claiming it would let
# uninstall.sh delete a file the user wrote — the fail-closed direction C and D hold for the two
# project-root files.
M2="$(new_fixture_variant state-m2 bare)"
printf '# my own ignores\n/Builds/\n' > "$M2/$GITIGNORE_REL"
M2_MARKER='/Builds/'
run_install "$M2" "M2 install"
if grep -qxF -- '.claude/settings.local.json' "$M2/$GITIGNORE_REL"; then
  pass "M2: the installer appended its entries to the user's $GITIGNORE_REL"
else
  fail "M2: the installer appended nothing — this state is not exercising the append branch"
fi
assert_not_owned "$M2" "$GITIGNORE_REL" "M2 (a $GITIGNORE_REL the user wrote)"
run_uninstall "$M2" "M2"
if [ -f "$M2/$GITIGNORE_REL" ] && grep -qxF -- "$M2_MARKER" "$M2/$GITIGNORE_REL"; then
  pass "M2: the user's $GITIGNORE_REL survived uninstall with their own entry intact"
else
  fail "M2: the user's $GITIGNORE_REL did not survive uninstall with their own entry intact"
fi

# ── State M3: ours, then the user edits it ───────────────────────────────────
M3="$(new_fixture_variant state-m3 bare)"
run_install "$M3" "M3 install 1"
printf '/MyLocalScratch/\n' >> "$M3/$GITIGNORE_REL"
M3_MARKER='/MyLocalScratch/'
run_install "$M3" "M3 install 2"
assert_not_owned "$M3" "$GITIGNORE_REL" "M3 (ours until the user edited it)"
run_uninstall "$M3" "M3"
if [ -f "$M3/$GITIGNORE_REL" ] && grep -qxF -- "$M3_MARKER" "$M3/$GITIGNORE_REL"; then
  pass "M3: the edited $GITIGNORE_REL survived uninstall with the user's line intact"
else
  fail "M3: the edited $GITIGNORE_REL did not survive uninstall with the user's line intact"
fi

# ── State N: an origin column we cannot read, across an upgrade ──────────────
# $OLD is B2's scratch "previous version": the same payload with a different MCP-SETUP.md. That
# difference is what makes the receipt the ONLY thing that can answer for the file — the shipped
# reference copy no longer matches, so owned_by_installer's first arm is out of play and its awk is
# the whole decision. Give that awk a row whose origin column carries one trailing space and the
# `$4 == "toolkit"` test is byte-unequal: the file is never re-claimed, by this run or any later
# one, and uninstall.sh can never remove it.
N="$(new_fixture state-n)"
N_RC=0
KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
  bash "$OLD/install.sh" --project-dir "$N" --yes >/dev/null 2>&1 </dev/null || N_RC=$?
if [ "$N_RC" -eq 0 ]; then
  pass "N install 1 (previous version): install.sh exited 0"
else
  fail "N install 1 (previous version): install.sh exited $N_RC"
fi
if [ "$(sha_of "$N/MCP-SETUP.md")" = "$(sha_of "$REPO/MCP-SETUP.md")" ]; then
  fail "N: the scratch toolkit installed the CURRENT MCP-SETUP.md — owned_by_installer's reference-copy arm answers and its awk is never reached, so this state proves nothing"
else
  pass "N: the previous version installed different bytes, so only the receipt can answer for MCP-SETUP.md"
fi
N_RECEIPT="$(receipt_of "$N")"
N_TMP="$SCRATCH/n-receipt.tsv"
awk -F'\t' -v OFS='\t' '$1 == "MCP-SETUP.md" { $4 = "toolkit " } { print }' "$N_RECEIPT" > "$N_TMP"
mv "$N_TMP" "$N_RECEIPT"
if [ -n "$(awk -F'\t' '$1 == "MCP-SETUP.md" && $4 == "toolkit " { print }' "$N_RECEIPT")" ]; then
  pass "N: the row now carries an unreadable origin ('toolkit' with a trailing space)"
else
  fail "N: the receipt rewrite did not take — the assertion below would pass for the wrong reason"
fi
run_install "$N" "N install 2 (current version)"
assert_owned "$N" 'MCP-SETUP.md' "N (upgrade across an unreadable origin column)"
run_uninstall "$N" "N"
assert_gone "$N" 'MCP-SETUP.md' "N (upgrade across an unreadable origin column)"

# ── State N2: the other direction of the same trim ───────────────────────────
# `user-modified ` must not become `toolkit`. If it does, the next uninstall deletes a file a
# previous run recorded as the user's — which is the data loss G.5 exists to stop, arriving through
# this fix instead of through the classifier.
N2="$(new_fixture state-n2)"
N2_RC=0
KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
  bash "$OLD/install.sh" --project-dir "$N2" --yes >/dev/null 2>&1 </dev/null || N2_RC=$?
if [ "$N2_RC" -eq 0 ]; then
  pass "N2 install 1 (previous version): install.sh exited 0"
else
  fail "N2 install 1 (previous version): install.sh exited $N2_RC"
fi
N2_RECEIPT="$(receipt_of "$N2")"
N2_SHA="$(sha_of "$N2/MCP-SETUP.md")"
N2_TMP="$SCRATCH/n2-receipt.tsv"
awk -F'\t' -v OFS='\t' '$1 == "MCP-SETUP.md" { $4 = "user-modified " } { print }' "$N2_RECEIPT" > "$N2_TMP"
mv "$N2_TMP" "$N2_RECEIPT"
if [ -n "$(awk -F'\t' '$1 == "MCP-SETUP.md" && $4 == "user-modified " { print }' "$N2_RECEIPT")" ]; then
  pass "N2: the row now carries 'user-modified' with a trailing space"
else
  fail "N2: the receipt rewrite did not take — the assertion below would pass for the wrong reason"
fi
run_install "$N2" "N2 install 2 (current version)"
assert_not_owned "$N2" 'MCP-SETUP.md' "N2 (a mangled user-modified row is still the user's)"
run_uninstall "$N2" "N2"
assert_kept "$N2" 'MCP-SETUP.md' "$N2_SHA" "N2 (a mangled user-modified row is still the user's)"

# ── State O: a foreign .claude/ is still foreign ─────────────────────────────
# MODE is decided by the receipt's ABSENCE, and this task makes an interrupted run write one. That
# is correct — such a run really did install the payload — but it is one edit away from "always
# write a receipt", which would turn somebody else's .claude/ into ours.
O="$(new_fixture state-o)"
mkdir -p "$O/.claude/agents"
printf 'a teammate wrote this, and Kinglet never did\n' > "$O/.claude/agents/teammate.md"
O_FOREIGN_REL='.claude/agents/teammate.md'
O_FOREIGN_SHA="$(sha_of "$O/$O_FOREIGN_REL")"
if [ ! -f "$(receipt_of "$O")" ]; then
  pass "O: the fixture has a .claude/ and no receipt — the definition of foreign mode"
else
  fail "O: the fixture already has a receipt, so this state is an upgrade rather than a foreign install"
fi
run_install_flags "$O" "O install"
if grep -qF -- 'Backed up existing .claude/' <<< "$INSTALL_OUT"; then
  pass "O: the run backed the foreign .claude/ up instead of merging into it"
else
  fail "O: the run did not announce a backup — a foreign .claude/ was treated as ours"
fi
O_BACKUP="$(find "$O" -maxdepth 1 -type d -name '.claude.backup.*' | sed -n '1p')"
if [ -n "$O_BACKUP" ] && [ "$(sha_of "$O_BACKUP/agents/teammate.md")" = "$O_FOREIGN_SHA" ]; then
  pass "O: the teammate's file is in the backup, byte-for-byte"
else
  fail "O: the teammate's file is not in a .claude.backup.*/ directory — it was destroyed rather than moved aside"
fi
assert_not_owned "$O" "$O_FOREIGN_REL" "O (a file the toolkit never installed)"

# ── State O2: a run that installs nothing writes no receipt ──────────────────
# The mutation this task is one edit from: flush the receipt unconditionally, and a run that died
# before writing a byte leaves a receipt behind — which reclassifies a foreign or absent .claude/
# as ours on the next run. Injected by CONTENT, at the line that arms the trap, so the probe does
# not rot against a line number.
O2_KIT="$SCRATCH/o2-toolkit"
mkdir -p "$O2_KIT"
cp -R "$REPO/.claude" "$O2_KIT/.claude"
cp -R "$REPO/scripts" "$O2_KIT/scripts"
cp "$REPO/MCP-SETUP.md" "$O2_KIT/MCP-SETUP.md"
O2_MARK='injected abort: armed the trap, installed nothing'
awk -v ins="die \"$O2_MARK\"" '
  { print }
  /^trap / && !done { print ins; done = 1 }
' "$REPO/install.sh" > "$O2_KIT/install.sh"
if grep -qF -- "$O2_MARK" "$O2_KIT/install.sh"; then
  pass "O2: the abort was injected into a scratch copy of install.sh"
else
  fail "O2: nothing was injected — install.sh no longer has a line beginning 'trap ', and the run below is an ordinary install"
fi
O2="$(new_fixture state-o2)"
O2_RC=0
KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
  bash "$O2_KIT/install.sh" --project-dir "$O2" --yes >/dev/null 2>&1 </dev/null || O2_RC=$?
if [ "$O2_RC" -ne 0 ]; then
  pass "O2: the injected run exited $O2_RC"
else
  fail "O2: the injected run exited 0 — the injected die never executed and nothing below is about an aborted run"
fi
if [ -f "$(receipt_of "$O2")" ]; then
  fail "O2: a run that installed nothing left a receipt — a foreign or absent .claude/ would be read as ours on the next run"
else
  pass "O2: a run that installed nothing left no receipt"
fi

# ── States P1…P5: the origin column has four readers, and this is the one ────
# ── whose being wrong costs the user's work ──────────────────────────────────
#
# N and N2 fixed the trim in owned_by_installer, which decides whether to RE-CLAIM a file. This is
# the other install-side reader — the MODIFIED_FILES loop that decides whether to OVERWRITE the
# user's edit — and it was left byte-exact. The two failures are not symmetric: owned_by_installer
# getting it wrong leaves a file on disk, which the user can delete; this one getting it wrong
# destroys an edit, which they cannot get back.
#
# Everything reaching that test has already survived `read -r … origin` with `IFS=$'\t'`, and TAB is
# the only IFS whitespace there — so `read` strips a leading tab and nothing else. Measured
# 2026-08-14 on the tree before this fix, install → edit → install → mangle → install:
#
#   trailing space   `user-modified `         edit DESTROYED, no `keeping yours`, row → `toolkit`
#   leading space    ` user-modified`         edit DESTROYED, ditto
#   CRLF receipt     `user-modified` + \r     edit DESTROYED, ditto
#   fifth column     `user-modified` + TAB…   edit DESTROYED, ditto
#   leading tab      TAB + `user-modified`    edit survived — by accident; `read` ate the tab
#
# THE NEGATIVE DIRECTION IS P4 AND IT IS THE POINT OF THE PAIR. The fix must be a whitespace trim
# followed by EXACT equality, never a prefix or substring match. A fifth column is not a
# `user-modified` row with decoration; it is a row whose provenance cannot be read. So P1–P3 and P5
# assert the edit survives WITHOUT the unreadable-origin report (the trim accepted the value), and
# P4 asserts it survives WITH that report (the trim declined it, and the `*)` branch kept the file).
# A greedy trim would make P4 silent and go red there — which is why both halves are asserted on the
# run's output and not on the file alone.
#
# WHAT P CANNOT SEE
#   * One payload file, one mangling per state. A receipt with several mangled rows at once, and any
#     interaction with the `.claude/scripts/` loop, are untested.
#   * uninstall.sh and scripts/studio-doctor.sh read this column too and do NOT trim. Their
#     fail-closed mechanism is a `case` catch-all instead, and nothing here exercises either. The
#     uninstall-side mirror of this defect — a mangled `toolkit ` on an UNEDITED file, classified as
#     the user's and therefore never removed — is unasserted anywhere.
#   * The trim is asserted through install.sh's OUTPUT and the file's bytes. Nothing here reads the
#     parameter expansion, so a rewrite that trimmed by some other means would pass.

# p_setup <name> <field-4 value> [post-filter] — install, edit a payload file, install again so the
# row is a genuine `user-modified` one carrying the EDITED checksum, then mangle only that column.
# That checksum is the whole point: it is the shape a sha-only fall-through misreads as "untouched".
P_REL='.claude/rules/pc-console.md'
P_DIR=''; P_WANT=''; P_OUT=''
p_setup() {
  local name="$1" v="$2" post="${3:-cat}"
  local d="$SCRATCH/$name" f rc=0 rcpt row
  bash "$REPO/tests/fixtures/mkproject.sh" "$d" >/dev/null
  KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
    bash "$REPO/install.sh" --project-dir "$d" --yes >/dev/null 2>&1 </dev/null || rc=$?
  P_DIR="$d"; P_WANT=''; P_OUT=''
  f="$d/$P_REL"
  if [ ! -f "$f" ]; then
    fail "$name: the payload did not install $P_REL — this state cannot mangle a row for a file that is not there"
    return 0
  fi
  printf '\n<!-- the user edited this -->\n' >> "$f"
  P_WANT="$(sha_of "$f")"
  KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
    bash "$REPO/install.sh" --project-dir "$d" --yes >/dev/null 2>&1 </dev/null || rc=$?
  rcpt="$(receipt_of "$d")"
  row="$(own_row "$rcpt" "$P_REL")"
  if [ "$(awk -F'\t' 'NR == 1 { print $4 }' <<< "$row")" = user-modified ] \
     && [ "$(awk -F'\t' 'NR == 1 { print $2 }' <<< "$row")" = "$P_WANT" ]; then
    pass "$name: the control row is 'user-modified' and carries the edited checksum"
  else
    fail "$name: the control row is not a user-modified row carrying the edited checksum — the mangling below would decorate the wrong thing. Row: $row"
  fi
  awk -F'\t' -v OFS='\t' -v want="$P_REL" -v v="$v" '$1 == want { $4 = v } { print }' "$rcpt" \
    | $post > "$SCRATCH/$name-receipt.tsv"
  mv "$SCRATCH/$name-receipt.tsv" "$rcpt"
  P_OUT="$(KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
        bash "$REPO/install.sh" --project-dir "$d" --yes </dev/null 2>&1 \
        | sed $'s/\x1b\\[[0-9;]*m//g')" || rc=$?
  return 0
}

# p_assert <name> <expect-unreadable-report: yes|no>
p_assert() {
  local name="$1" want_report="$2" have
  have="$(sha_of "$P_DIR/$P_REL")"
  if [ -n "$P_WANT" ] && [ "$have" = "$P_WANT" ]; then
    pass "$name: the user's edit survived the install"
  else
    fail "$name: the user's edit was destroyed — the origin column was not read, the sha test concluded the file was untouched, and the payload loop overwrote it"
  fi
  if grep -qF -- 'keeping yours' <<< "$P_OUT"; then
    pass "$name: the run said it was keeping the user's file"
  else
    fail "$name: the run kept nothing and said nothing — the user is not told a file of theirs was at stake"
  fi
  # The discriminator. `no` means the TRIM accepted the value; `yes` means the trim declined it and
  # the catch-all kept the file. Both outcomes leave the edit intact, and only this line separates
  # them — which is what makes a too-greedy trim detectable at all.
  if grep -qF -- 'origin this installer cannot read' <<< "$P_OUT"; then
    if [ "$want_report" = yes ]; then
      pass "$name: reported as unreadable, so the trim declined it rather than accepting it"
    else
      fail "$name: reported as unreadable — surrounding whitespace should have been trimmed and the value accepted"
    fi
  else
    if [ "$want_report" = no ]; then
      pass "$name: not reported as unreadable — the trim accepted the value"
    else
      fail "$name: a malformed origin was accepted as 'user-modified' — the trim is matching more than surrounding whitespace"
    fi
  fi
}

p_setup state-p1 'user-modified '
p_assert "P1 (trailing space)" no

p_setup state-p2 ' user-modified'
p_assert "P2 (leading space)" no

# Every line gets a \r, not just the row under test — that is what a receipt saved by a Windows
# editor actually looks like, and it is why this is a whole-file filter rather than a field value.
p_setup state-p3 'user-modified' "sed s/\$/$(printf '\r')/"
p_assert "P3 (CRLF receipt)" no

p_setup state-p4 "user-modified$(printf '\t')deadbeef"
p_assert "P4 (a fifth column)" yes

# P5 passed before the fix too, and the reason is worth an assertion rather than a green line: the
# tab is IFS whitespace to the loop's `read`, so it is gone before the comparison. Asserted so that
# a future change to that IFS cannot move this shape into the broken set unnoticed.
p_setup state-p5 "$(printf '\t')user-modified"
p_assert "P5 (leading tab)" no

[ "$FAILURES" -eq 0 ] || exit 1
printf 'all install-ownership assertions passed\n'
