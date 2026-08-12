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
# WHAT THIS FILE CANNOT SEE
#   * Only the two project-root files named above, in states A–D. A third unrecorded write at the
#     project root — Packages/manifest.json.bak is the known one — is invisible here by construction.
#   * State G edits three payload files — Markdown, a hook, settings.json — because ONE was not
#     enough: with a single .md file here, a classifier mutated to protect only `.md` passed this
#     whole file with zero failures while deleting a user's edited hook and settings.json. What it
#     still does not cover: `.claude/scripts/*`, which a different loop in install.sh writes; a
#     file whose MODE the user changed rather than its bytes (the receipt records mode and nothing
#     reads it); and any payload file whose content is binary. What the INSTALLER does to a
#     `.claude/` file across upgrades is tests/test-install.sh's and tests/test-install-prune.sh's
#     ground, not this file's.
#   * Only `--yes` installs against the default (urp) fixture. --with-mcp, --with-input-system,
#     --dry-run and --keep-local are not exercised, and the fixture is NOT a git repository, so
#     every branch that turns on `git -C "$PROJECT_DIR"` takes its no-git side. `--purge` is
#     exercised in state G and nowhere else.
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
.claude/hooks/auto-learn.sh
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

[ "$FAILURES" -eq 0 ] || exit 1
printf 'all install-ownership assertions passed\n'
