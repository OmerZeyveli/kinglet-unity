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
# WHAT THIS FILE CANNOT SEE
#   * Only the two project-root files named above. A third unrecorded write at the project root —
#     Packages/manifest.json.bak is the known one — is invisible here by construction.
#   * Nothing under .claude/. The payload loop already writes `toolkit` / `user-modified` rows and
#     is covered by tests/test-install.sh and tests/test-install-prune.sh.
#   * Only `--yes` installs against the default (urp) fixture. --with-mcp, --with-input-system,
#     --dry-run, --purge and --keep-local are not exercised, and the fixture is NOT a git
#     repository, so every branch that turns on `git -C "$PROJECT_DIR"` takes its no-git side.
#   * Why uninstall.sh did what it did. This reads the filesystem before and after, so "the file
#     survived" and "the file survived because uninstall crashed" look identical — which is why
#     every install and uninstall below asserts its exit status separately.
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
sha_of()     { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

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

[ "$FAILURES" -eq 0 ] || exit 1
printf 'all install-ownership assertions passed\n'
