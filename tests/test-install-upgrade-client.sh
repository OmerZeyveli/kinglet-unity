#!/usr/bin/env bash
# ============================================================================
# test-install-upgrade-client.sh — installing one client over the other must
# leave a tree that is internally consistent, not merely a tree that got
# written to.
#
# THE DEFECT THIS EXISTS FOR, MEASURED BEFORE IT WAS FIXED — 2026-08-16, and
# the figures are pinned to that tree (one row per skill, one per command, plus
# three). `install.sh --client codex` appends its receipt rows OUTSIDE
# `.claude/` — the skill symlinks, the converted command skills, `AGENTS.md`,
# `.codex/hooks.json`, `.codex/config.toml` — and every one of those appends
# sits inside the `if [ "$CLIENT" = codex ]` branch. The receipt is rebuilt from
# scratch on every run. So `install.sh --project-dir X` with no `--client` at
# all — the DEFAULT invocation, i.e. an ordinary upgrade — took those rows
# 28 -> 0 while leaving all 28 paths on disk. Step 3's orphan prune could not
# reach them either: it filters the previous receipt to `^\.claude/`. Result,
# reproduced on a fixture: 28 files with no reader that owns them, `uninstall.sh`
# (which is receipt-driven by design) removing 71 of 99 and reporting success,
# and `studio-doctor.sh` reporting `PASS Install intact: 71 file(s) verified
# against the receipt` / `8 passed · 1 warning(s) · 0 failure(s)`. Nothing was
# red anywhere. The assertions below are derived from the tree, not from these
# numbers — they are here as the reason, not as the reference.
#
# WHY THIS IS A FIXTURE AND NOT AN ASSERTION ON A FRESH INSTALL. Every guard in
# this suite runs against a tree this repository builds from nothing. The tree
# that actually breaks is the one a user already has, produced by one
# invocation and then updated by a different one, and no fresh-install check
# ever constructs that state. This repository has already paid for that once:
# a wave removed 15 hook files, every guard and every task review passed, and
# updating a real project left 15 registrations pointing at files that no
# longer existed. `.claude/skills/subagent-driven-implementation/SKILL.md`
# states the rule this file is the instance of — "assert the RESULTING TREE is
# internally consistent, not merely that files were written."
#
# THE TWO DIRECTIONS ARE BOTH TESTED, because they fail for different reasons.
# codex-over-claude re-runs the whole Codex branch and rewrites every row, so
# it is the arm that would catch a row the branch stopped emitting.
# claude-over-codex runs none of it, so it is the arm that catches the
# carry-forward being dropped — which is the direction that was broken.
#
# "NO FILE ON DISK WITHOUT A ROW" IS TRUE OF THE CLEAN PATH AND MUST NOT BE
# TIGHTENED INTO A UNIVERSAL. A `--client codex` run over a user-edited
# `.codex/hooks.json` leaves the file on disk and writes NO row — "not ours, no
# claim", which is the installer's documented rule and the reason `uninstall.sh`
# never removes a file it did not install.
#
# THAT PARAGRAPH NAMED `AGENTS.md` FIRST UNTIL 2026-08-17, AND IT IS NO LONGER
# TRUE OF THAT FILE. Arms 6 and 7 are the ones that introduce the state, and they
# assert the rule as it now stands rather than the invariant: a user-edited
# `AGENTS.md` that a PREVIOUS RUN WROTE keeps a row, `user-modified`, carrying
# its edited checksum — because the installer's own Codex Next step 2 tells the
# user to edit that file, and a file that leaves the receipt when they do is a
# file this toolkit stops knowing about. An `AGENTS.md` no run of ours ever wrote
# still gets no row, and arm 7 asserts that direction in the same fixture set.
#
# Self-contained: defines its own helpers and sets `set -euo pipefail`, so
# `bash tests/test-install-upgrade-client.sh` is a valid way to run it.
# ============================================================================
set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

echo "--- install: upgrading across clients ---"

# `PASS:` AND NOT `ok`, AND THAT IS NOT A COSMETIC CHOICE. `tests/run-tests.sh` aggregates `Total`
# by grepping each file's output for `(^|[[:space:]])PASS(:|[[:space:]])`. This file first shipped
# printing `ok`, which made it one of only two files in the suite contributing **nothing** to that
# number — and `ok` is the exact token the runner's own header names as the cause of the 1443 -> 1
# undercount it documents and fixed on 2026-08-14. A hard failure was still caught (`set -e` -> the
# runner's "exited N without reporting a failure" backstop), so the exposure was narrow: a version of
# this file that ran zero assertions and exited 0 would move `Total` by exactly nothing, which is the
# shape this repository calls the worst one it has. Its three sibling Codex tests all print `PASS:`.
TIUC_PASS=0
TIUC_FAIL=0
tiuc_eq() {   # expected actual message
  if [ "$1" = "$2" ]; then
    TIUC_PASS=$((TIUC_PASS + 1))
    printf 'PASS: %s\n' "$3"
  else
    TIUC_FAIL=$((TIUC_FAIL + 1))
    printf 'FAIL: %s\n       expected: %s\n       actual:   %s\n' "$3" "$1" "$2"
  fi
}

TIUC_ROOT=$(mktemp -d)
# ONE mktemp ROOT, REMOVED AS ONE NAMED PATH. No glob delete anywhere near
# /tmp: other agents' and other tests' fixtures live there, and a `rm -rf
# /tmp/kinglet-*` in a suite that runs concurrently with anything else is a
# data-loss bug with a green test in front of it.
trap 'rm -rf "$TIUC_ROOT"' EXIT

# Every path a Codex install owns that is NOT under .claude/. Derived from the
# tree rather than listed, so a Codex layer that grows a new artefact is
# covered the day it lands instead of the day someone remembers this file.
tiuc_codex_paths() {   # $1 = project dir
  ( cd "$1" 2>/dev/null || return 0
    find AGENTS.md .agents .codex -mindepth 0 \( -type f -o -type l \) 2>/dev/null | sort )
}

# Every path the receipt claims, one per line, comments and header dropped.
tiuc_receipt_paths() {   # $1 = project dir
  awk -F'\t' '/^#/ {next} $1 == "path" {next} NF >= 1 && $1 != "" {print $1}' \
    "$1/.claude/state/install-receipt.tsv" 2>/dev/null | sort
}

# The checksum column of one receipt row, by path. `-v` and an exact `==`, not a
# regex, so a path that is a prefix of another cannot match the wrong row.
tiuc_receipt_sha() {   # $1 = project dir, $2 = path
  awk -F'\t' -v want="$2" '/^#/ {next} $1 == want { print $2; exit }' \
    "$1/.claude/state/install-receipt.tsv" 2>/dev/null
}

# A missing file hashes to the empty string, and the `[ -f ]` guard is what makes
# that true rather than fatal. `sha256sum` exits 1 on a missing path, `pipefail`
# promotes that through the `| cut`, and at an assignment site `set -e` ends this
# file with no message, mid-arm, every later assertion unrun — which reads as
# absent rather than as red. Measured 2026-08-17 while mutation-proving arm 6: a
# mutant that made the installer claim an edited AGENTS.md as `toolkit` got it
# DELETED by the uninstaller, and the arm that exists to catch exactly that died
# at the next hash instead of reporting it. A probe that dies is a probe that
# reports nothing; the identical lesson is recorded in
# tests/test-install-ownership.sh's own `sha_of`.
tiuc_sha() {   # $1 = file
  [ -f "$1" ] || return 0
  sha256sum "$1" 2>/dev/null | cut -d' ' -f1
}

# tiuc_agents_line <project> — the dry run's one claim about AGENTS.md, by exact
# first-field match INSIDE the `Would install:` block. `AGENTS.md` is a prefix of
# nothing here, but field equality is the claim and substring presence is not.
#
# THE BLOCK SCOPE IS NOT TIDINESS — it was measured. A dry run against a project
# whose AGENTS.md has local edits prints that path, indented and alone, under the
# upgrade scan's `keeping yours:` list, which runs BEFORE this block. An unscoped
# first-field match reads that list entry as the claim and gets a bare path with
# no verdict in it, so the assertion fails against a correct installer — the
# false-red half of the same mistake the claim line itself used to make.
tiuc_agents_line() {   # $1 = project dir
  bash "$REPO_DIR/install.sh" --project-dir "$1" --client codex --yes --dry-run 2>&1 \
    | sed $'s/\x1b\\[[0-9;]*m//g' \
    | awk '/^Would install:/ { inblock = 1; next } inblock && $1 == "AGENTS.md" { print; exit }'
}

# ─────────────────────────────────────────────────────────────────────────────
# Arm 1 — codex first, then the DEFAULT (claude) invocation over it.
# ─────────────────────────────────────────────────────────────────────────────
P1="$TIUC_ROOT/codex-then-claude"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P1" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$P1" --client codex --yes >/dev/null 2>&1

TIUC_BEFORE=$(tiuc_codex_paths "$P1" | grep -c . || true)
# THE FLOOR, AND IT IS NOT DECORATION. Every assertion below is a set
# comparison, and two empty sets are equal. If the Codex install silently
# stopped producing a layer — a rename, a failed converter, a skipped branch —
# the consistency checks would all pass over nothing at all and this file would
# report green while testing the empty tree. 25 is the floor rather than the
# exact figure (16 bridged skills + 9 converted commands + AGENTS.md + two
# .codex files = 28 today) so that adding a skill does not red this line; what
# it cannot survive is the layer disappearing.
if [ "$TIUC_BEFORE" -ge 25 ]; then TIUC_FLOOR=ok; else TIUC_FLOOR="only $TIUC_BEFORE Codex-layer path(s) after --client codex"; fi
tiuc_eq "ok" "$TIUC_FLOOR" \
  "the Codex install produced a layer to be consistent ABOUT — without this floor every set comparison below is satisfied by two empty sets"

bash "$REPO_DIR/install.sh" --project-dir "$P1" --yes >/dev/null 2>&1

TIUC_DISK=$(tiuc_codex_paths "$P1")
TIUC_ROWS=$(tiuc_receipt_paths "$P1")
TIUC_UNOWNED=$(comm -23 <(printf '%s\n' "$TIUC_DISK") <(printf '%s\n' "$TIUC_ROWS") | grep -c . || true)
tiuc_eq "0" "$TIUC_UNOWNED" \
  "after --client claude over --client codex, no Codex-layer file on disk is left without a receipt row (each one uninstall.sh can no longer remove)"

TIUC_AFTER=$(printf '%s\n' "$TIUC_DISK" | grep -c . || true)
tiuc_eq "$TIUC_BEFORE" "$TIUC_AFTER" \
  "…and none of them was deleted either — the default client removes nothing Codex reads, which is the mirror of the promise --client codex makes"

# The other direction of the same consistency question: a row for a path that
# is not there. Checked over the WHOLE receipt, not only the Codex rows,
# because a carry-forward that copied rows blindly would fail exactly here.
TIUC_GHOST=0
while IFS= read -r tiuc_r; do
  [ -n "$tiuc_r" ] || continue
  # `-e || -L`, never `-f`: the 16 skill rows are symlinks to DIRECTORIES, and
  # `-f` follows the link and then asks "is the target a regular file", which
  # is false for every one of them. That exact spelling is what made
  # studio-doctor.sh fail every correct Codex install.
  [ -e "$P1/$tiuc_r" ] || [ -L "$P1/$tiuc_r" ] || TIUC_GHOST=$((TIUC_GHOST + 1))
done <<< "$TIUC_ROWS"
tiuc_eq "0" "$TIUC_GHOST" \
  "…and every row in the resulting receipt names a path that is actually there"

# The consequence, run rather than argued: the receipt is only worth anything
# if the uninstaller can act on it.
bash "$REPO_DIR/uninstall.sh" --project-dir "$P1" --yes >/dev/null 2>&1
TIUC_LEFT=$(tiuc_codex_paths "$P1" | grep -c . || true)
tiuc_eq "0" "$TIUC_LEFT" \
  "uninstall.sh removes the Codex layer after that upgrade — before the carry-forward existed it left every one of those paths behind, permanently"

# ─────────────────────────────────────────────────────────────────────────────
# Arm 2 — claude first, then codex over it. This arm re-runs the whole Codex
# branch, so it is the one that would catch a row the branch stopped emitting.
# ─────────────────────────────────────────────────────────────────────────────
P2="$TIUC_ROOT/claude-then-codex"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P2" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$P2" --yes >/dev/null 2>&1
TIUC_P2_FIRST=$(tiuc_codex_paths "$P2" | grep -c . || true)
tiuc_eq "0" "$TIUC_P2_FIRST" \
  "a plain install writes no Codex layer at all — the arm below is genuinely an upgrade and not a second identical run"

bash "$REPO_DIR/install.sh" --project-dir "$P2" --client codex --yes >/dev/null 2>&1
TIUC_P2_DISK=$(tiuc_codex_paths "$P2")
TIUC_P2_ROWS=$(tiuc_receipt_paths "$P2")
TIUC_P2_UNOWNED=$(comm -23 <(printf '%s\n' "$TIUC_P2_DISK") <(printf '%s\n' "$TIUC_P2_ROWS") | grep -c . || true)
tiuc_eq "0" "$TIUC_P2_UNOWNED" \
  "adding the Codex layer to an existing Claude Code install leaves every one of its files owned by a row"

TIUC_P2_N=$(printf '%s\n' "$TIUC_P2_DISK" | grep -c . || true)
if [ "$TIUC_P2_N" -ge 25 ]; then TIUC_P2_FLOOR=ok; else TIUC_P2_FLOOR="only $TIUC_P2_N Codex-layer path(s)"; fi
tiuc_eq "ok" "$TIUC_P2_FLOOR" \
  "…over a layer that actually exists, so that comparison is not two empty sets either"

# ─────────────────────────────────────────────────────────────────────────────
# Arm 3 — the carried row is VERBATIM, and a user edit between the two installs
# is what makes that observable.
#
# WHY THIS ARM EXISTS, AND WHY THE TWO ABOVE COULD NOT REPLACE IT. Step 8e's
# longest paragraph rejects one specific alternative: re-deriving the carried
# checksum from disk instead of copying the previous receipt's. A reviewer
# isolated exactly that design as a mutation — re-derive for regular files only,
# leaving symlink rows alone — and arms 1 and 2 passed it **8/8**. They cannot
# do otherwise: neither edits a Codex-layer file between the installs, so
# verbatim and re-derived produce byte-identical receipts, and every assertion
# up to here compares *path sets*, which no checksum can move.
#
# WHAT THE REJECTED DESIGN COSTS A USER, measured rather than argued: with the
# carried shas re-derived, `uninstall.sh` reports `remove 99 file(s) — unchanged
# since install` and **deletes the user's edited files**. That is the exact data
# loss `uninstall.sh`'s two-test classifier exists to prevent — a `toolkit` row
# whose recorded sha equals the file on disk reads as "we installed it and
# nobody touched it".
#
# So this arm asserts the property directly (each row still carries the PRE-edit
# checksum) and then asserts its consequence (every edit survives the uninstall).
# Either one alone reddens the mutation; both are here because the first says
# *what* is wrong and the second says *what it costs*.
#
# IT EDITS THE WHOLE CARRIED SET, NOT ONE FILE, AND THAT IS THE SECOND LESSON.
# The first version of this arm picked the first row matching `^\.agents/`. A
# re-derivation scoped to `AGENTS.md` and `.codex/*` — the rows OUTSIDE that
# prefix — then passed it 16/16 while `uninstall.sh` reported `remove 99 file(s)
# — unchanged since install` and **deleted a user-edited `AGENTS.md`**: the very
# file the installer's own Codex Next step 2 instructs the user to edit. A guard
# that walks one prefix certifies one prefix. The argument it protects is about
# every carried row, so the set is derived from the receipt — every non-symlink
# row `codex_layer_path` selects — and the floor below requires it to span more
# than one top-level prefix, so narrowing the selector back cannot go quiet.
# ─────────────────────────────────────────────────────────────────────────────
P3="$TIUC_ROOT/codex-then-edit-then-claude"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P3" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$P3" --client codex --yes >/dev/null 2>&1

# EVERY non-symlink Codex-layer row, derived from the receipt. Non-symlink
# because `sha_of` on a symlink-to-directory is the empty string, so those rows
# cannot show a re-derivation either way — they are covered by arm 1, whose
# `uninstall.sh removes the Codex layer` assertion a symlink-scoped
# re-derivation reddens. The selector is the same allowlist install.sh and
# studio-doctor.sh share, spelled as an awk condition because awk has no `case`.
TIUC_E_ROWS="$(awk -F'\t' '
  /^#/ { next }
  $1 == "path" { next }
  $3 == "symlink" { next }
  $1 == "AGENTS.md" || $1 ~ /^\.agents\/skills\// || $1 ~ /^\.codex\// || $1 == ".claude/state/codex-trust.tsv" { print $1 }
' "$P3/.claude/state/install-receipt.tsv" 2>/dev/null)"

TIUC_E_N=$(printf '%s\n' "$TIUC_E_ROWS" | grep -c . || true)
# THE TWO FLOORS, AND THE SECOND IS THE ONE THIS ARM WAS REWRITTEN FOR. A count
# alone cannot see the set collapse onto a single prefix — nine converted skills
# satisfy "at least three" while covering exactly the ground the broken version
# already covered. Counting DISTINCT first path segments is what makes
# "more than one prefix" an assertion rather than a hope.
TIUC_E_PREFIXES=$(printf '%s\n' "$TIUC_E_ROWS" | awk -F/ 'NF { print $1 }' | sort -u | grep -c . || true)
if [ "$TIUC_E_N" -ge 3 ]; then TIUC_E_OK=yes; else TIUC_E_OK="only $TIUC_E_N non-symlink Codex-layer row(s)"; fi
tiuc_eq "yes" "$TIUC_E_OK" \
  "the receipt carries non-symlink Codex-layer rows to edit — without them every assertion in this arm is about nothing"
if [ "$TIUC_E_PREFIXES" -ge 2 ]; then TIUC_E_SPREAD=yes; else TIUC_E_SPREAD="all $TIUC_E_N row(s) share one prefix"; fi
tiuc_eq "yes" "$TIUC_E_SPREAD" \
  "…and they span more than one top-level prefix ($TIUC_E_PREFIXES), so a re-derivation scoped to any single prefix cannot hide inside this arm"

# Snapshot every recorded checksum, then edit every file. A trailing newline is
# enough to move a sha and cannot invalidate JSON, TOML or Markdown — these are
# real project files and the point is the checksum, not the content.
TIUC_E_SNAP=""
TIUC_E_UNMOVED=0
while IFS= read -r tiuc_e; do
  [ -n "$tiuc_e" ] || continue
  tiuc_e_before="$(tiuc_receipt_sha "$P3" "$tiuc_e")"
  printf '\n' >> "$P3/$tiuc_e"
  # THE PER-ROW FLOOR. If an append silently did nothing the recorded and on-disk
  # checksums stay equal, and "the row was not re-derived" is then true for the
  # wrong reason — in BOTH arms of the mutation, which is what makes it useless.
  if [ "$tiuc_e_before" = "$(tiuc_sha "$P3/$tiuc_e")" ]; then
    TIUC_E_UNMOVED=$((TIUC_E_UNMOVED + 1))
  fi
  TIUC_E_SNAP="${TIUC_E_SNAP}${tiuc_e}	${tiuc_e_before}"$'\n'
done <<< "$TIUC_E_ROWS"
tiuc_eq "0" "$TIUC_E_UNMOVED" \
  "every edit actually changed its file's checksum, so 'the row was not re-derived' is a claim with two distinguishable answers for each of them"

bash "$REPO_DIR/install.sh" --project-dir "$P3" --yes >/dev/null 2>&1

TIUC_E_DRIFT=""
while IFS=$'\t' read -r tiuc_e tiuc_e_before; do
  [ -n "$tiuc_e" ] || continue
  tiuc_e_now="$(tiuc_receipt_sha "$P3" "$tiuc_e")"
  if [ "$tiuc_e_now" != "$tiuc_e_before" ]; then TIUC_E_DRIFT="${TIUC_E_DRIFT}${tiuc_e} "; fi
done <<< "$TIUC_E_SNAP"
tiuc_eq "" "$TIUC_E_DRIFT" \
  "every carried row keeps the checksum the Codex run recorded — re-deriving any of them from disk would newly claim a file the user edited"

bash "$REPO_DIR/uninstall.sh" --project-dir "$P3" --yes >/dev/null 2>&1
TIUC_E_LOST=""
while IFS=$'\t' read -r tiuc_e _tiuc_e_before; do
  [ -n "$tiuc_e" ] || continue
  [ -f "$P3/$tiuc_e" ] || TIUC_E_LOST="${TIUC_E_LOST}${tiuc_e} "
done <<< "$TIUC_E_SNAP"
tiuc_eq "" "$TIUC_E_LOST" \
  "…and uninstall.sh therefore leaves every edited file alone, which is what those checksums are FOR"

# ─────────────────────────────────────────────────────────────────────────────
# Arm 4 — a Codex-layer path that is GONE. The row is dropped, and the drop is
# said out loud by both halves that own it.
#
# THE LOOP THIS CLOSES, MEASURED. `studio-doctor.sh` correctly reports a missing
# receipted file and tells the user to re-run the installer. Following that
# remedy with the DEFAULT client used to drop the row silently and hand back a
# green doctor with the file still missing — a remedy that CONCEALS the state,
# which is worse than the branch's original defect (a remedy that reproduced it),
# because that one at least kept complaining.
#
# Dropping the row is still the right behaviour: a row for a path that is not
# there is a ghost, and keeping it would give a user who deliberately removed the
# Codex layer a doctor that fails forever with no TARGETED way to clear it —
# `uninstall.sh` then `install.sh` does clear one, using only shipped commands,
# but there is no per-layer flag, so the cure is tearing the whole toolkit down.
# What must not be silent is the drop. Both sentences are asserted here because
# either alone leaves the loop open at the other end.
#
# THE PATH IS CHOSEN SO THAT NO CONSTANT CAN SATISFY THE ASSERTION, and the first
# version of this arm failed exactly that test. It deleted `.codex/hooks.json`
# and grepped the whole run output for that literal — while `install.sh`'s
# `note_not_done` carried the same literal in a fixed sentence, so the predicate
# was true whatever had been dropped. Suppressing the per-path `printf`
# altogether left this file 16/16 green. Two changes close it: the arm deletes a
# converted skill, whose path appears in no constant anywhere in `install.sh`,
# and it reads the indented block under `GONE from disk:` rather than the whole
# run. Either alone would do; both are here because this is the second time a
# hollow assertion has shipped on this branch.
# ─────────────────────────────────────────────────────────────────────────────
P4="$TIUC_ROOT/codex-then-missing"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P4" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$P4" --client codex --yes >/dev/null 2>&1

# Derived, not named: the first converted command skill in the receipt. A
# converted skill is a Codex-layer regular file whose path `install.sh` never
# writes as a literal.
TIUC_GONE_REL="$(awk -F'\t' '
  /^#/ { next }
  $1 == "path" { next }
  $3 == "symlink" { next }
  $1 ~ /^\.agents\/skills\// { print $1; exit }
' "$P4/.claude/state/install-receipt.tsv" 2>/dev/null)"
if [ -n "$TIUC_GONE_REL" ] && ! grep -qF -- "$TIUC_GONE_REL" "$REPO_DIR/install.sh"; then TIUC_GONE_OK=yes; else TIUC_GONE_OK="no unnamed candidate (got '$TIUC_GONE_REL')"; fi
tiuc_eq "yes" "$TIUC_GONE_OK" \
  "the path this arm deletes appears in no literal inside install.sh, so an assertion that finds it in the output cannot be satisfied by a constant"
rm -f "$P4/$TIUC_GONE_REL"

TIUC_DOC="$(bash "$REPO_DIR/scripts/studio-doctor.sh" --project-dir "$P4" 2>&1 || true)"
# Here-string, never a pipe: `grep -q` exits at the first match without draining
# stdin, and under `set -euo pipefail` that SIGPIPEs the writer.
if grep -qF -- 'missing — re-run install.sh --client codex' <<< "$TIUC_DOC"; then TIUC_DOC_R=named; else TIUC_DOC_R=bare; fi
tiuc_eq "named" "$TIUC_DOC_R" \
  "the doctor's remedy for a missing Codex-layer path names --client codex — a bare 're-run install.sh' steers the user into the drop below"

TIUC_INS="$(bash "$REPO_DIR/install.sh" --project-dir "$P4" --yes 2>&1 || true)"
# BLOCK-SCOPED. The paths are printed indented under the `GONE from disk:` warn
# line and the block ends at the next unindented line, so `awk` takes exactly
# that region — nothing elsewhere in the run can satisfy this by accident. awk
# drains its input, so there is no early-exit reader to SIGPIPE anything.
TIUC_GONE_BLOCK="$(awk '
  /GONE from disk:/ { inblock = 1; next }
  inblock && /^       [^ ]/ { print; next }
  inblock { inblock = 0 }
' <<< "$TIUC_INS" | sed 's/^ *//')"
if grep -qxF -- "$TIUC_GONE_REL" <<< "$TIUC_GONE_BLOCK"; then TIUC_INS_NAMED=yes; else TIUC_INS_NAMED=no; fi
tiuc_eq "yes" "$TIUC_INS_NAMED" \
  "…and when the default client then drops that row, the GONE-from-disk block names the path it dropped rather than only counting what it kept"

if grep -qF -- '--client codex' <<< "$TIUC_INS"; then TIUC_INS_FIX=yes; else TIUC_INS_FIX=no; fi
tiuc_eq "yes" "$TIUC_INS_FIX" \
  "…and points at the invocation that would restore it"

TIUC_P4_GHOST=0
while IFS= read -r tiuc_r; do
  [ -n "$tiuc_r" ] || continue
  [ -e "$P4/$tiuc_r" ] || [ -L "$P4/$tiuc_r" ] || TIUC_P4_GHOST=$((TIUC_P4_GHOST + 1))
done <<< "$(tiuc_receipt_paths "$P4")"
tiuc_eq "0" "$TIUC_P4_GHOST" \
  "…and the row really is dropped rather than carried as a ghost, so the receipt still describes the disk"

# ─────────────────────────────────────────────────────────────────────────────
# Arm 5 — the classifier that chooses between the two remedies, in both
# directions, plus the thing that keeps its two copies from drifting.
#
# WHY BOTH DIRECTIONS. The doctor's Codex-layer test shipped as
# `grep -vE '^\.claude/'` under a comment claiming it was "the criterion Step 8e
# uses, spelled the same way". It was neither.
#
#   FALSE POSITIVE — `.mcp.json` and `MCP-SETUP.md` are receipted, outside
#   `.claude/`, and written by a PLAIN install. Deleting one on a project that
#   had never had a Codex layer produced `re-run install.sh --client codex` and
#   three false explanatory lines; a user who followed that remedy got
#   `AGENTS.md`, `.agents/` and `.codex/` created in a project that had asked
#   for neither.
#
#   FALSE NEGATIVE — `.claude/state/codex-trust.tsv` is written only by the
#   Codex arm and lives under `.claude/`, so the one row where the concealing
#   remedy genuinely applies got the bare form.
#
# A one-directional guard would have passed the shipped bug in whichever
# direction it did not test, which is how the bug got there.
# ─────────────────────────────────────────────────────────────────────────────
P5="$TIUC_ROOT/claude-only-missing-mcp"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P5" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$P5" --yes >/dev/null 2>&1
if [ -f "$P5/.mcp.json" ]; then TIUC_P5_PRE=present; else TIUC_P5_PRE=absent; fi
tiuc_eq "present" "$TIUC_P5_PRE" \
  "the plain install wrote .mcp.json — a receipted path outside .claude/ that a plain install restores, which is what makes the next assertion a test"
rm -f "$P5/.mcp.json"
TIUC_P5_DOC="$(bash "$REPO_DIR/scripts/studio-doctor.sh" --project-dir "$P5" 2>&1 || true)"
if grep -qF -- 'missing — re-run install.sh --client codex' <<< "$TIUC_P5_DOC"; then TIUC_P5_R=codex; else TIUC_P5_R=bare; fi
tiuc_eq "bare" "$TIUC_P5_R" \
  "a missing .mcp.json on a Claude-Code-only project gets the BARE remedy — telling that user to re-run with --client codex converts their project to a two-client install to restore one documentation file"
if grep -qF -- 'written only by --client codex' <<< "$TIUC_P5_DOC"; then TIUC_P5_E=claimed; else TIUC_P5_E=silent; fi
tiuc_eq "silent" "$TIUC_P5_E" \
  "…and the explanatory lines that go with that remedy are not printed either, since every one of them would be false here"

# The false negative, on the row the two halves must agree about most: the trust
# receipt is Codex-only AND under `.claude/`, so a prefix rule gets it wrong
# whichever prefix it picks.
P6="$TIUC_ROOT/codex-missing-trust-receipt"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P6" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$P6" --client codex --yes >/dev/null 2>&1
# `--codex-trust` is never run by this suite (it writes the user's home), so the
# trust receipt is synthesised here exactly as that path would record it: a file
# and a matching row. The classifier is what is under test, not the grant.
printf 'stub\n' > "$P6/.claude/state/codex-trust.tsv"
printf '.claude/state/codex-trust.tsv\t%s\t644\ttoolkit\n' \
  "$(tiuc_sha "$P6/.claude/state/codex-trust.tsv")" >> "$P6/.claude/state/install-receipt.tsv"
rm -f "$P6/.claude/state/codex-trust.tsv"
TIUC_P6_DOC="$(bash "$REPO_DIR/scripts/studio-doctor.sh" --project-dir "$P6" 2>&1 || true)"
if grep -qF -- 'missing — re-run install.sh --client codex' <<< "$TIUC_P6_DOC"; then TIUC_P6_R=codex; else TIUC_P6_R=bare; fi
tiuc_eq "codex" "$TIUC_P6_R" \
  "a missing .claude/state/codex-trust.tsv gets the --client codex remedy even though it is under .claude/ — a prefix rule gets this row wrong whichever prefix it picks"

# THE TWO COPIES, HELD TOGETHER. install.sh is not in the payload, so the
# shipped script cannot source it and there is no file both can read. What there
# is instead is this comparison: extract the marked region from each and require
# them to be character-for-character equal. Change one, change the other, or the
# suite goes red — which is the difference between a copy and a duplicate.
tiuc_criterion() {   # $1 = file
  awk '/kinglet:codex-layer-criterion:begin/ { f = 1; next }
       /kinglet:codex-layer-criterion:end/   { f = 0 }
       f' "$1"
}
TIUC_CRIT_A="$(tiuc_criterion "$REPO_DIR/install.sh")"
TIUC_CRIT_B="$(tiuc_criterion "$REPO_DIR/scripts/studio-doctor.sh")"
# THE FLOOR FIRST: two empty strings are equal. If a marker is renamed or
# deleted, both extractions go empty and the comparison below passes over
# nothing — the exact vacuity this repository names as its worst shape.
TIUC_CRIT_N=$(printf '%s\n' "$TIUC_CRIT_A" | grep -c . || true)
if [ "$TIUC_CRIT_N" -ge 4 ] && grep -qF -- 'codex_layer_path' <<< "$TIUC_CRIT_A"; then TIUC_CRIT_OK=yes; else TIUC_CRIT_OK="extraction returned $TIUC_CRIT_N line(s)"; fi
tiuc_eq "yes" "$TIUC_CRIT_OK" \
  "the criterion markers still delimit a real function in install.sh — a renamed marker would make the equality below compare two empty strings"
tiuc_eq "$TIUC_CRIT_A" "$TIUC_CRIT_B" \
  "install.sh and scripts/studio-doctor.sh carry the SAME codex_layer_path, character for character — the shipped script cannot source the installer, so this comparison is what stops the two spellings drifting apart again"

# ─────────────────────────────────────────────────────────────────────────────
# THE PREDICATE ITSELF, IN BOTH DIRECTIONS. Every arm above asserts that a Codex
# path is INCLUDED. None asserted that a non-Codex path is EXCLUDED, and the gap
# was measured rather than argued: a shadow `codex_layer_path() { return 0; }`
# left this file at 24/24 green. A guard that only exercises one direction of a
# predicate is half a guard — and the untested half is the dangerous one, because
# a criterion that is too WIDE tells a Claude-only user to install a Codex layer
# they never asked for, which is the exact defect round 2 of Task 12 shipped and
# had to withdraw.
#
# It runs the EXTRACTED REGION, not a re-spelling of it: `eval` inside a subshell
# so the definition cannot leak into this file's own scope, and so a change to
# install.sh's real function is what this arm reads. A table with a hardcoded
# copy of the criterion would agree with itself forever.
#
# WHAT THIS ARM CANNOT SEE, measured 2026-08-17 rather than reasoned about. It
# reads the REGION, so a shadow appended AFTER the end marker — the shape that
# started this whole thread — is invisible to it. Both halves were run:
#
#   shadow in scripts/studio-doctor.sh -> 2 red here, the two behavioural arms
#   shadow in install.sh               -> fully GREEN here; 38 red across the full
#                                         suite, distributed 33 / 3 / 1 / 1 across
#                                         test-install-ownership.sh,
#                                         test-studio-doctor.sh, test-install-prune.sh
#                                         and test-doctor-reverted.sh
#
# THE FIRST WRITE-UP OF THIS HAD 38 RIGHT AND THE FILES WRONG. Its harvest matched
# only `  FAIL `, the runner's helper shape; a self-contained test file prints
# `FAIL: `, and 33 of the 38 are in one. It saw 4 and named the two files those 4
# were in. `tests/run-tests.sh` counts both shapes — a harvest that counts one
# reports a subset as the whole and gives no sign of it.
#
# Nothing ships silently either way, and the three guards have three different
# blind spots: the byte comparison catches a textual edit and no shadow, the
# behavioural arms catch the doctor's runtime and not the installer's, and this
# arm catches what the criterion ANSWERS and no shadow at all. Stated here so the
# next reader does not read one green as three.
TIUC_PRED_BAD=""
TIUC_PRED_IN=0
TIUC_PRED_OUT=0
tiuc_pred() {   # $1 = project-relative path, $2 = expected rc (0 = Codex-layer)
  local rc=0
  ( eval "$TIUC_CRIT_A"; codex_layer_path "$1" ) || rc=$?
  if [ "$2" = "0" ]; then TIUC_PRED_IN=$((TIUC_PRED_IN + 1)); else TIUC_PRED_OUT=$((TIUC_PRED_OUT + 1)); fi
  [ "$rc" = "$2" ] || TIUC_PRED_BAD="${TIUC_PRED_BAD}${1} -> rc ${rc}, expected ${2}"$'\n'
}
# Codex-layer: every shape the installer's Codex arm writes.
tiuc_pred 'AGENTS.md'                             0
tiuc_pred '.agents/skills/addressables'           0
tiuc_pred '.agents/skills/unity-doctor/SKILL.md'  0
tiuc_pred '.codex/hooks.json'                     0
tiuc_pred '.codex/config.toml'                    0
tiuc_pred '.claude/state/codex-trust.tsv'         0
# NOT Codex-layer: a plain install writes every one of these, and a criterion
# that claims any of them sends a Claude-only user to `--client codex`.
tiuc_pred '.claude/settings.json'                 1
tiuc_pred '.claude/skills/addressables/SKILL.md'  1
tiuc_pred '.claude/state/install-receipt.tsv'     1
tiuc_pred 'CLAUDE.md'                             1
tiuc_pred '.mcp.json'                             1
tiuc_pred 'MCP-SETUP.md'                          1
# `.agents/` is not the criterion; `.agents/skills/*` is. A prefix rule gets this
# one wrong, and it is the row that tells the two spellings apart.
tiuc_pred '.agents/notes.md'                      1

# THE FLOOR, AND IT IS TWO-SIDED ON PURPOSE. An empty table makes `TIUC_PRED_BAD`
# empty and the assertion below green; a table that kept only its positive half
# would restore exactly the gap this arm exists to close, and a single total
# cannot see that happen.
if [ "$TIUC_PRED_IN" -ge 3 ] && [ "$TIUC_PRED_OUT" -ge 3 ]; then TIUC_PRED_FLOOR=ok
else TIUC_PRED_FLOOR="probed $TIUC_PRED_IN included and $TIUC_PRED_OUT excluded path(s); both halves need at least 3"; fi
tiuc_eq "ok" "$TIUC_PRED_FLOOR" \
  "the predicate table carries members on BOTH sides ($TIUC_PRED_IN in, $TIUC_PRED_OUT out) — a table that lost its excluded half would pass this arm having tested one direction again"

if [ -n "$TIUC_PRED_BAD" ]; then printf '%s' "$TIUC_PRED_BAD" | sed 's|^|       |'; fi
tiuc_eq "" "$TIUC_PRED_BAD" \
  "install.sh's codex_layer_path answers correctly in BOTH directions — every Codex-layer shape included AND every plain-install path excluded"

# ─────────────────────────────────────────────────────────────────────────────
# Arm 6 — the edit the installer ASKS FOR, and the freeze it used to cause.
#
# THE DEFECT, MEASURED ON THIS FIXTURE BEFORE THE FIX. `install.sh --client
# codex` generates AGENTS.md with nine FILL: markers and its own Next step 2
# tells the user to fill them in. Doing that made the file permanently frozen:
# run 2 said "keeping yours, untouched" and dropped the receipt row, run 3 could
# no longer list it under local edits (the list is built from the receipt),
# `studio-doctor.sh` reported 98 files verified and never named it, and
# `uninstall.sh` removed 98 and left it behind without reporting it. CLAUDE.md
# has had a marked-region merge for this since the beginning; AGENTS.md had none,
# so the moment the user did what the installer instructed, no reinstall, upgrade
# or fix ever updated that document again — including the Project Facts and the
# /name translation rule a Codex session depends on.
#
# WHY IT IS A FIXTURE AND NOT AN ASSERTION ON A FRESH INSTALL — this file's own
# header, and it applies twice over here: the broken tree is one a user builds by
# following instructions, and no fresh-install check ever constructs it.
#
# THE ORDER OF THE ASSERTIONS IS THE ORDER THE DAMAGE HAPPENS IN: the run's own
# claim first (so a later green cannot come from a branch that never ran), then
# the user's bytes, then the generated half, then the receipt, then the two
# readers that were silent, then the uninstaller.
# ─────────────────────────────────────────────────────────────────────────────
P7="$TIUC_ROOT/codex-then-fill-markers"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P7" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$P7" --client codex --yes >/dev/null 2>&1

# Everything between the markers, which is the half the installer owns.
tiuc_region() {   # $1 = file
  awk '/kinglet:generated:begin/ { f = 1; next }
       /kinglet:generated:end/   { f = 0 }
       f' "$1" 2>/dev/null
}

# THE FLOOR. If install 1 stopped emitting the pair, every marker assertion below
# would be satisfied by a file with no region at all — the vacuity this file
# already carries two other floors against.
TIUC_M7="$(awk '/kinglet:generated:begin/ { b++ } /kinglet:generated:end/ { e++ } END { print (b + 0) "," (e + 0) }' "$P7/AGENTS.md" 2>/dev/null || echo 0,0)"
tiuc_eq "1,1" "$TIUC_M7" \
  "install 1 wrote an AGENTS.md carrying exactly one marker pair — without it there is no region to refresh and every assertion in this arm is about nothing"
TIUC_FILL7="$(awk '/FILL:/ { n++ } END { print n + 0 }' "$P7/AGENTS.md" 2>/dev/null || echo 0)"
if [ "$TIUC_FILL7" -gt 0 ]; then TIUC_FILL7_OK=yes; else TIUC_FILL7_OK="no FILL: markers in the generated file"; fi
tiuc_eq "yes" "$TIUC_FILL7_OK" \
  "…and it carries the FILL: markers Next step 2 tells the user to fill in, so the edit below is the one the installer asks for and not an invented one"

# The instructed edit, plus a section of the user's own below the region — the
# two shapes of prose an AGENTS.md acquires once a human has opened it.
python3 - "$P7/AGENTS.md" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
text = text.replace('# [FILL: Game Title] — Project Guide', '# Kingdom of Wire — Project Guide')
text = re.sub(r'<!-- FILL:[^>]*-->', 'FILLED-BY-THE-USER', text)
text += '\n## My Own Notes\n\nSENTINEL-AGENTS-PROSE\n'
open(path, 'w').write(text)
PY
TIUC_FILL7_AFTER="$(awk '/FILL:/ { n++ } END { print n + 0 }' "$P7/AGENTS.md" 2>/dev/null || echo 0)"
tiuc_eq "0" "$TIUC_FILL7_AFTER" \
  "the edit really filled every FILL: marker — otherwise 'the markers did not come back' below is true for the wrong reason"

# THE PROJECT MOVES ON BETWEEN THE TWO INSTALLS, AND WITHOUT THAT HALF THIS ARM
# CANNOT SEE A MERGE THAT DID NOTHING. On an unchanged project a refresh writes
# back the region install 1 already wrote, so 'the region equals a fresh
# generate' is satisfied by a merge that ran, by a merge that no-opped, and by a
# branch that declined the file entirely. One more first-party C# file moves the
# detected-stack table, which is exactly the kind of fact this document exists to
# keep current — and it is what makes the two assertions below distinguish a
# refresh from a file that was simply left alone.
TIUC_REGION_BEFORE="$(tiuc_region "$P7/AGENTS.md" | sha256sum | cut -d' ' -f1)"
mkdir -p "$P7/Assets/Scripts"
printf 'using VContainer;\npublic sealed class SentinelSystem { }\n' > "$P7/Assets/Scripts/SentinelSystem.cs"

# WHAT THE REGION DOES NOT COVER, ASSERTED SO THE PROSE CANNOT DRIFT FROM IT.
# The merge maintains the project-facts block and nothing else: the /name
# translation, the hooks-and-trust paragraph and the rest of the Codex sections
# are emitted OUTSIDE the pair by the full generate only, so they stay as install
# 1 wrote them once the user has edited the file. Three documents now state that
# residual — install.sh § 8d.1, CLAUDE.md's criterion, README.md — and the reason
# it is asserted here rather than trusted is that all three would silently become
# wrong the day someone widens the region. This is the assertion that reddens.
TIUC_SCOPE_IN=$(tiuc_region "$P7/AGENTS.md" | grep -c 'Project Facts' || true)
TIUC_SCOPE_OUT=$(tiuc_region "$P7/AGENTS.md" | grep -c 'is Claude Code' || true)
if [ "$TIUC_SCOPE_IN" -ge 1 ] && [ "$TIUC_SCOPE_OUT" -eq 0 ] \
   && grep -qF -- 'is Claude Code' "$P7/AGENTS.md"; then TIUC_SCOPE=facts-only; else TIUC_SCOPE="in=$TIUC_SCOPE_IN out=$TIUC_SCOPE_OUT"; fi
tiuc_eq "facts-only" "$TIUC_SCOPE" \
  "the marked region holds the project facts and NOT the /name translation, which is in the file and outside the pair — the residual three documents now state in prose, asserted here so widening the region reddens instead of silently falsifying them"

# The mode the merged file carries. 640 rather than the default, so the assertion
# distinguishes 'preserved' from 'whatever this host's umask produces' — under
# umask 0002 a dropped restore yields 664 and under 0022 it yields 644, and both
# differ from 640. It must also be OWNER-WRITABLE: a read-only target is refused
# before the merge, which is a different arm and is asserted in 7e.
chmod 640 "$P7/AGENTS.md"

TIUC_OUT7="$(bash "$REPO_DIR/install.sh" --project-dir "$P7" --client codex --yes 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g')"

# THE BRANCH FLOOR, FIRST. A branch that declines everything would satisfy the
# byte assertions below outright, because their whole content is that the user's
# prose is still there.
if grep -qF -- 'Refreshed the generated section of AGENTS.md' <<< "$TIUC_OUT7"; then TIUC_R7=refreshed; else TIUC_R7=other; fi
tiuc_eq "refreshed" "$TIUC_R7" \
  "the second install refreshed AGENTS.md in place rather than declining it — a branch that kept every edited file would pass every byte assertion below without merging anything"

if grep -qF -- 'SENTINEL-AGENTS-PROSE' "$P7/AGENTS.md"; then TIUC_S7=kept; else TIUC_S7=lost; fi
tiuc_eq "kept" "$TIUC_S7" \
  "the user's own section below the region survived the refresh"
TIUC_FILL7_BACK="$(awk '/FILL:/ { n++ } END { print n + 0 }' "$P7/AGENTS.md" 2>/dev/null || echo 0)"
tiuc_eq "0" "$TIUC_FILL7_BACK" \
  "…and the FILL: markers did not come back, so the vision half the user filled in is what is on disk"

# THE GENERATED HALF IS CURRENT, AND THIS IS THE ASSERTION THAT READS THE CLIENT.
# The region is client-conditional — it names the Skill tool for Claude Code and
# says to read the SKILL.md for Codex, which has no skill tool — so a refresh
# that forgot to pass the client would write the wrong client's sentence into the
# one document Codex injects whole, on every re-install. Comparing against a
# fresh generate for the same project catches that AND a region left stale.
bash "$REPO_DIR/scripts/generate-claude-md.sh" --facts-only --client codex "$P7" > "$TIUC_ROOT/facts7.txt" 2>/dev/null
tiuc_region "$P7/AGENTS.md" > "$TIUC_ROOT/region7.txt"
TIUC_REGION_N=$(grep -c . < "$TIUC_ROOT/region7.txt" || true)
if [ "$TIUC_REGION_N" -ge 10 ]; then TIUC_REGION_FLOOR=ok; else TIUC_REGION_FLOOR="extracted $TIUC_REGION_N line(s)"; fi
tiuc_eq "ok" "$TIUC_REGION_FLOOR" \
  "the extraction found a real region in the refreshed AGENTS.md — two empty files compare equal, which is how this comparison would go quiet"
if cmp -s "$TIUC_ROOT/region7.txt" "$TIUC_ROOT/facts7.txt"; then TIUC_REGION_EQ=same; else TIUC_REGION_EQ=different; fi
tiuc_eq "same" "$TIUC_REGION_EQ" \
  "the refreshed region is byte-for-byte what a fresh generate produces for this project and this client — a refresh that dropped the client would put Claude Code's skill-loading sentence into the document Codex injects"
if [ "$TIUC_REGION_BEFORE" = "$(sha256sum < "$TIUC_ROOT/region7.txt" | cut -d' ' -f1)" ]; then TIUC_REGION_MOVED=no; else TIUC_REGION_MOVED=yes; fi
tiuc_eq "yes" "$TIUC_REGION_MOVED" \
  "…and it MOVED: the project gained a C# file between the two installs and the merged region followed it, so a merge that quietly did nothing cannot satisfy the comparison above"

# THE MODE, WHICH THE MERGE WRITES THROUGH A NEW FILE AND A RENAME. Without a
# restore the target's permissions become the umask's answer to a question nobody
# asked — measured under umask 0002, that moved 600 to 664 (wider) and 666 to 664
# (narrower), in both directions and by accident. 640 is chosen because no umask
# on this host produces it, so 'preserved' and 'whatever the umask gives' are
# distinguishable answers rather than the same number.
tiuc_eq "640" "$(stat -c '%a' "$P7/AGENTS.md" 2>/dev/null || echo unknown)" \
  "the refresh left the file's mode exactly as the user had it — a merge that renames a temp file over the target silently re-permissions it, in whichever direction the umask happens to point"

# THE ROW, AND ITS ORIGIN IS THE WHOLE POINT. A 'toolkit' row here would be a
# claim uninstall.sh acts on, and it would delete the prose the installer told
# the user to write.
TIUC_ROW7="$(awk -F'\t' '/^#/ { next } $1 == "AGENTS.md" { print $4; exit }' "$P7/.claude/state/install-receipt.tsv" 2>/dev/null)"
tiuc_eq "user-modified" "$TIUC_ROW7" \
  "the refreshed AGENTS.md keeps a receipt row and it says user-modified — before this fix the row vanished, and a file with no row is one uninstall.sh, studio-doctor.sh and the next install can all no longer see"
TIUC_SHA7="$(tiuc_receipt_sha "$P7" 'AGENTS.md')"
tiuc_eq "$(tiuc_sha "$P7/AGENTS.md")" "$TIUC_SHA7" \
  "…carrying the checksum of the merged file, so the next run recognises it as the same edited file rather than as a stranger"

# The third install: the run that used to be silent, and the one that proves the
# refresh reproduces itself instead of growing the file.
TIUC_BEFORE7="$(tiuc_sha "$P7/AGENTS.md")"
TIUC_OUT7B="$(bash "$REPO_DIR/install.sh" --project-dir "$P7" --client codex --yes 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g')"
tiuc_eq "$TIUC_BEFORE7" "$(tiuc_sha "$P7/AGENTS.md")" \
  "a third install left AGENTS.md byte-for-byte identical — the merge reproduces the region rather than adding to it once per run"
# BLOCK-SCOPED, not a whole-output grep: the paths are printed indented under the
# local-edits warn line, and every other line naming this file would satisfy a
# loose search. This is the reader that went silent from run 3 on.
TIUC_EDIT_BLOCK="$(awk '
  /installed file\(s\) have local edits/ { inblock = 1; next }
  inblock && /^       [^ ]/ { print; next }
  inblock { inblock = 0 }
' <<< "$TIUC_OUT7B" | sed 's/^ *//')"
if grep -qxF -- 'AGENTS.md' <<< "$TIUC_EDIT_BLOCK"; then TIUC_LISTED7=named; else TIUC_LISTED7=silent; fi
tiuc_eq "named" "$TIUC_LISTED7" \
  "the third install lists AGENTS.md under the files it is keeping for you — the run that was silent about it before, because that list is built from the receipt row the previous run had thrown away"

# The doctor: the second reader that never mentioned the file.
TIUC_DOC7="$(bash "$REPO_DIR/scripts/studio-doctor.sh" --project-dir "$P7" 2>&1 || true)"
if grep -qF -- 'AGENTS.md' <<< "$TIUC_DOC7"; then TIUC_DOC7_R=named; else TIUC_DOC7_R=silent; fi
tiuc_eq "named" "$TIUC_DOC7_R" \
  "studio-doctor.sh names AGENTS.md — a frozen entry document used to sit outside its verified set entirely, so the health check called the project intact while the file it injects whole was unreachable to every later run"

# THE DRY RUN'S REFRESH VERDICT, ON THE ONE PROJECT THAT IS IN THAT STATE, AND IT
# IS THE VERDICT THIS TASK ADDED. Asserted here rather than in arm 7 because arm
# 7's fixtures are all files the installer declines — none of them can reach the
# refresh line at all. Without this, a dry run that announced a decline over a
# file the real run refreshes — the S3b defect, one file over — left the whole
# suite green: measured, and it is why this assertion exists rather than being
# implied by the block's own comment about the parser contract.
TIUC_DRY7="$(tiuc_agents_line "$P7")"
if grep -qF -- 'refresh the generated section only' <<< "$TIUC_DRY7"; then TIUC_DRY7_R=refresh; else TIUC_DRY7_R="$TIUC_DRY7"; fi
tiuc_eq "refresh" "$TIUC_DRY7_R" \
  "the dry run announces a refresh for the project whose AGENTS.md the real run refreshes — the announcement and the act are computed from one predicate, and a decline announced here would promise to leave alone a file about to be rewritten"

# The tree, as a set: nothing on disk without a row, nothing in the receipt
# without a path.
TIUC_DISK7=$(tiuc_codex_paths "$P7")
TIUC_ROWS7=$(tiuc_receipt_paths "$P7")
# THE FLOOR THE PAIR BELOW NEEDS. Both are `== 0` verdicts and an empty
# derivation satisfies each of them — docs/ANTI-VACUITY.md's C4 names exactly this
# shape. Arm 1 guards its analogue the same way and this arm had no counterpart.
TIUC_DISK7_N=$(printf '%s\n' "$TIUC_DISK7" | grep -c . || true)
if [ "$TIUC_DISK7_N" -ge 25 ]; then TIUC_DISK7_FLOOR=ok; else TIUC_DISK7_FLOOR="only $TIUC_DISK7_N Codex-layer path(s) on disk"; fi
tiuc_eq "ok" "$TIUC_DISK7_FLOOR" \
  "there is a Codex layer on disk to be consistent ABOUT after the edit and two more installs — the two set comparisons below are both satisfied by an empty derivation"
TIUC_UNOWNED7=$(comm -23 <(printf '%s\n' "$TIUC_DISK7") <(printf '%s\n' "$TIUC_ROWS7") | grep -c . || true)
tiuc_eq "0" "$TIUC_UNOWNED7" \
  "after the edit and two more installs, no Codex-layer file on disk is left without a receipt row"
TIUC_GHOST7=0
while IFS= read -r tiuc_r7; do
  [ -n "$tiuc_r7" ] || continue
  [ -e "$P7/$tiuc_r7" ] || [ -L "$P7/$tiuc_r7" ] || TIUC_GHOST7=$((TIUC_GHOST7 + 1))
done <<< "$TIUC_ROWS7"
tiuc_eq "0" "$TIUC_GHOST7" \
  "…and every row in that receipt names a path that is actually there"

# The uninstaller, which is where a wrong row costs the user their work.
TIUC_KEEP7="$(tiuc_sha "$P7/AGENTS.md")"
TIUC_UNINST7="$(bash "$REPO_DIR/uninstall.sh" --project-dir "$P7" --yes --no-backup 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g')"
if [ -f "$P7/AGENTS.md" ]; then TIUC_ALIVE7=present; else TIUC_ALIVE7=deleted; fi
tiuc_eq "present" "$TIUC_ALIVE7" \
  "uninstall.sh left the edited AGENTS.md on disk — the row is user-modified, and that is the origin its classifier must never delete"
tiuc_eq "$TIUC_KEEP7" "$(tiuc_sha "$P7/AGENTS.md")" \
  "…with the user's bytes unchanged"
TIUC_KEPT_BLOCK="$(awk '
  /keep .*file\(s\) you modified/ { inblock = 1; next }
  inblock && /^ *[^ ]/ { print; next }
  inblock { inblock = 0 }
' <<< "$TIUC_UNINST7" | sed 's/^ *//')"
if grep -qxF -- 'AGENTS.md' <<< "$TIUC_KEPT_BLOCK"; then TIUC_UNI7=named; else TIUC_UNI7=silent; fi
tiuc_eq "named" "$TIUC_UNI7" \
  "…and said so, under the files it kept because you modified them, rather than leaving it behind unreported"
TIUC_LEFT7=$(tiuc_codex_paths "$P7" | grep -c . || true)
tiuc_eq "1" "$TIUC_LEFT7" \
  "…while the rest of the Codex layer is gone — the uninstaller still removes what it owns, and exactly what it owns"

# ─────────────────────────────────────────────────────────────────────────────
# Arm 7 — the states of an AGENTS.md the installer does not simply rewrite, and
# the dry run that has to describe each of them before the real run acts.
#
# DERIVE THE COUNT FROM THE `# 7x —` HEADERS RATHER THAN READING ONE HERE. This
# opened "the four states" and there were four; two more arrived in the same wave
# and the sentence did not, which is the shape this repository keeps paying for.
#
# WHY THE DRY RUN IS HALF OF EVERY ROW. The line here read
# 'AGENTS.md — the Codex entry document (generated…)' unconditionally, so against
# a project whose AGENTS.md the real run declines, the dry run promised to
# generate one. That is the defect state S3b in tests/test-install-ownership.sh
# guards one file over, and this file's installer has already paid for it twice:
# an announcement computed from a copy of the write's condition is a second
# definition, and a second definition drifts.
#
# THE STATES, AND WHAT SEPARATES THEM. Ownership alone cannot answer here —
# 'not ours' covers a file we wrote and the user then edited, one we wrote and the
# user then damaged, one we wrote and the user then REPLACED, and one we never
# wrote at all, and those want different outcomes. Two tests separate them and
# each has an arm that fails without it: whether a previous receipt carried the
# PATH (7b — a hand-written AGENTS.md with a well-formed pair fails only that
# test, and an earlier draft told its owner their markers were malformed, a
# diagnosis false of the file in front of them), and whether the FILE still
# carries the marker pair we wrote (7f — the path test alone let --purge delete a
# file the same run had just called 'not ours, keeping yours').
# ─────────────────────────────────────────────────────────────────────────────
# `tiuc_agents_line` is defined with the other helpers at the top of this file,
# because arm 6 calls it too and a definition here would be reached only after
# that call had already failed.

# 7a — a user's own AGENTS.md, no markers, no install has ever run here.
P8="$TIUC_ROOT/agents-not-ours-plain"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P8" >/dev/null 2>&1
printf '# My own AGENTS file\n\nNOT-KINGLETS-FILE\n' > "$P8/AGENTS.md"
TIUC_SHA8="$(tiuc_sha "$P8/AGENTS.md")"
TIUC_DRY8="$(tiuc_agents_line "$P8")"
if grep -qF -- 'would keep yours' <<< "$TIUC_DRY8"; then TIUC_DRY8_R=decline; else TIUC_DRY8_R="$TIUC_DRY8"; fi
tiuc_eq "decline" "$TIUC_DRY8_R" \
  "7a: the dry run says it would keep a user's own AGENTS.md rather than promising to generate one over it"
bash "$REPO_DIR/install.sh" --project-dir "$P8" --client codex --yes >/dev/null 2>&1
tiuc_eq "$TIUC_SHA8" "$(tiuc_sha "$P8/AGENTS.md")" \
  "7a: …and the real run left it byte-for-byte alone"
tiuc_eq "" "$(tiuc_receipt_sha "$P8" 'AGENTS.md')" \
  "7a: …and claimed no row for it, so uninstall.sh --purge can never reach a file no run of ours wrote"

# 7b — the same, but the user's file carries a well-formed marker pair. Ownership
# says 'not ours' and the markers say 'refreshable', and only the absence of a
# previous row tells them apart.
P9="$TIUC_ROOT/agents-not-ours-marked"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P9" >/dev/null 2>&1
printf '# My own AGENTS file\n\n<!-- kinglet:generated:begin -->\nmine, not yours\n<!-- kinglet:generated:end -->\n\nNOT-KINGLETS-FILE\n' > "$P9/AGENTS.md"
TIUC_SHA9="$(tiuc_sha "$P9/AGENTS.md")"
TIUC_DRY9="$(tiuc_agents_line "$P9")"
if grep -qF -- 'would keep yours' <<< "$TIUC_DRY9"; then TIUC_DRY9_R=decline; else TIUC_DRY9_R="$TIUC_DRY9"; fi
tiuc_eq "decline" "$TIUC_DRY9_R" \
  "7b: the dry run says it would keep this one too — the marker pair is the one thing that could make an announcement read it as refreshable, and it must not"
TIUC_OUT9="$(bash "$REPO_DIR/install.sh" --project-dir "$P9" --client codex --yes 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g')"
tiuc_eq "$TIUC_SHA9" "$(tiuc_sha "$P9/AGENTS.md")" \
  "7b: a file we have never written is kept whatever is inside it — a well-formed pair in it is not permission to merge into it"
tiuc_eq "" "$(tiuc_receipt_sha "$P9" 'AGENTS.md')" \
  "7b: …and it gets no row either"
if grep -qF -- 'do not form exactly one begin/end pair' <<< "$TIUC_OUT9"; then TIUC_DIAG9=wrong; else TIUC_DIAG9=none; fi
tiuc_eq "none" "$TIUC_DIAG9" \
  "7b: …and the run does not tell its owner their markers are malformed, which is false of a file whose pair is well formed"

# 7c — ours, and then the user damages the pair. The decline arm, with the
# diagnosis that names which half is wrong.
P10="$TIUC_ROOT/agents-ours-then-broken"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P10" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$P10" --client codex --yes >/dev/null 2>&1
python3 - "$P10/AGENTS.md" <<'PY'
import sys
path = sys.argv[1]
lines = [l for l in open(path).read().split('\n') if 'kinglet:generated:end' not in l]
open(path, 'w').write('\n'.join(lines) + '\nSENTINEL-BROKEN-PAIR\n')
PY
TIUC_SHA10="$(tiuc_sha "$P10/AGENTS.md")"
TIUC_DRY10="$(tiuc_agents_line "$P10")"
if grep -qF -- 'NOT touched' <<< "$TIUC_DRY10"; then TIUC_DRY10_R=decline; else TIUC_DRY10_R="$TIUC_DRY10"; fi
tiuc_eq "decline" "$TIUC_DRY10_R" \
  "7c: the dry run declines a damaged marker pair instead of promising a refresh the real run will not perform"
TIUC_OUT10="$(bash "$REPO_DIR/install.sh" --project-dir "$P10" --client codex --yes 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g')"
tiuc_eq "$TIUC_SHA10" "$(tiuc_sha "$P10/AGENTS.md")" \
  "7c: the real run left every byte of the damaged file alone — the merge against an unbounded pair is what deletes the rest of a user's file"
if grep -qF -- 'begin marker has no closing' <<< "$TIUC_OUT10"; then TIUC_DIAG10=named; else TIUC_DIAG10=vague; fi
tiuc_eq "named" "$TIUC_DIAG10" \
  "7c: …and said which half of the pair is missing, so the reader can check the sentence against their own file"
if grep -qF -- 'install.sh --client codex' <<< "$TIUC_OUT10"; then TIUC_FIX10=named; else TIUC_FIX10=bare; fi
tiuc_eq "named" "$TIUC_FIX10" \
  "7c: …and pointed at the invocation that writes this file, since a bare re-run of the default client never touches AGENTS.md"
tiuc_eq "user-modified" "$(awk -F'\t' '/^#/ { next } $1 == "AGENTS.md" { print $4; exit }' "$P10/.claude/state/install-receipt.tsv" 2>/dev/null)" \
  "7c: …and the declined file keeps a row, so the one file carrying a fault the user must repair is not also the one file nothing reports"

# 7d — ours and untouched, the anti-'decline everything' control. A predicate
# mutated to keep every file passes 7a, 7b and 7c outright, because their whole
# content is that nothing happened.
P11="$TIUC_ROOT/agents-ours-untouched"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P11" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$P11" --client codex --yes >/dev/null 2>&1
TIUC_DRY11="$(tiuc_agents_line "$P11")"
if grep -qF -- 'the Codex entry document (generated' <<< "$TIUC_DRY11"; then TIUC_DRY11_R=generated; else TIUC_DRY11_R="$TIUC_DRY11"; fi
tiuc_eq "generated" "$TIUC_DRY11_R" \
  "7d: the dry run promises to generate over an AGENTS.md that is ours and untouched — the fourth verdict, and the one an all-declines announcement would lose"
TIUC_OUT11="$(bash "$REPO_DIR/install.sh" --project-dir "$P11" --client codex --yes 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g')"
if grep -qF -- 'Generated AGENTS.md' <<< "$TIUC_OUT11"; then TIUC_R11=written; else TIUC_R11=other; fi
tiuc_eq "written" "$TIUC_R11" \
  "7d: an untouched AGENTS.md of ours is still rewritten whole on the next install — an installer that declined everything would pass every other row in this arm"
tiuc_eq "toolkit" "$(awk -F'\t' '/^#/ { next } $1 == "AGENTS.md" { print $4; exit }' "$P11/.claude/state/install-receipt.tsv" 2>/dev/null)" \
  "7d: …and its row still says toolkit, so uninstall.sh removes a document nobody has edited"

# 7e — the read-only entry document, which is the normal state of every unopened
# file on a Perforce-managed Unity project.
#
# THE DEFECT THIS ARM EXISTS FOR, MEASURED UNDER A PTY. `mv` onto a file with no
# write bit ASKS before overwriting, and exits 1 when the answer is no; the
# installer's own --yes does not reach it. The first version of the merge ignored
# that status, so a declined rename produced 'ok Refreshed the generated section
# of AGENTS.md (your prose untouched)', Next step 2 repeating it, a user-modified
# receipt row carrying the sha of the UNREFRESHED file, and rc 0. The commit
# before it had aborted the whole install instead — a loud failure replaced by a
# quiet false success, which this branch rates as the worse of the two.
#
# NO PTY IS NEEDED TO ASSERT THE FIX, and that is the point of fixing it by
# refusing rather than by handling mv's status alone: the refusal is decided
# before anything is written, so it is observable on a plain non-interactive run.
# What a pty would add is the reproduction of the OLD failure, which needs the
# prompt; that measurement lives in the merge function's header.
P12="$TIUC_ROOT/agents-read-only"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P12" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$P12" --client codex --yes >/dev/null 2>&1
python3 - "$P12/AGENTS.md" <<'PY'
import re, sys
path = sys.argv[1]
text = re.sub(r'<!-- FILL:[^>]*-->', 'FILLED-BY-THE-USER', open(path).read())
open(path, 'w').write(text + '\n## My Own Notes\n\nSENTINEL-READONLY\n')
PY
mkdir -p "$P12/Assets/Scripts"
printf 'using VContainer;\npublic sealed class ReadOnlyProbe { }\n' > "$P12/Assets/Scripts/ReadOnlyProbe.cs"
chmod 444 "$P12/AGENTS.md"
TIUC_SHA12="$(tiuc_sha "$P12/AGENTS.md")"
TIUC_RC12=0
TIUC_OUT12="$(bash "$REPO_DIR/install.sh" --project-dir "$P12" --client codex --yes 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g')" || TIUC_RC12=$?
tiuc_eq "$TIUC_SHA12" "$(tiuc_sha "$P12/AGENTS.md")" \
  "7e: a read-only AGENTS.md is not modified — the merge refuses before it writes anything rather than renaming a temp file over a file the user's VCS is holding closed"
if grep -qF -- 'Refreshed the generated section of AGENTS.md' <<< "$TIUC_OUT12"; then TIUC_CLAIM12=claimed; else TIUC_CLAIM12=none; fi
tiuc_eq "none" "$TIUC_CLAIM12" \
  "7e: …and the run does NOT claim it refreshed it, which is the whole finding: a merge that reports success over a file it never touched is worse than one that fails"
if grep -qF -- 'AGENTS.md is read-only' <<< "$TIUC_OUT12"; then TIUC_WHY12=named; else TIUC_WHY12=vague; fi
tiuc_eq "named" "$TIUC_WHY12" \
  "7e: …and says why, naming the file's mode rather than reporting a generic failure the user cannot act on"
TIUC_ND12="$(awk '/^Not done:/ { inblock = 1; next } inblock && /^Next steps:/ { inblock = 0 } inblock' <<< "$TIUC_OUT12")"
if grep -qF -- 'AGENTS.md' <<< "$TIUC_ND12"; then TIUC_ND12_R=listed; else TIUC_ND12_R=absent; fi
tiuc_eq "listed" "$TIUC_ND12_R" \
  "7e: …and records it under 'Not done:', which is the contract MCP-SETUP.md states for work this installer was asked for and did not do"
tiuc_eq "0" "$TIUC_RC12" \
  "7e: …while the run still exits 0 — the payload landed and the run reported what it skipped, which is that contract's other half"
tiuc_eq "user-modified" "$(awk -F'\t' '/^#/ { next } $1 == "AGENTS.md" { print $4; exit }' "$P12/.claude/state/install-receipt.tsv" 2>/dev/null)" \
  "7e: …and the row still describes the file that is actually on disk, rather than recording a merge that did not happen"
tiuc_eq "$TIUC_SHA12" "$(tiuc_receipt_sha "$P12" 'AGENTS.md')" \
  "7e: …with the checksum of the unrefreshed file, so the next run recognises it instead of reading a stale claim"

# 7f — ours once, then replaced WHOLESALE by the user's own marker-less file. The
# receipt still names the path, so 'did a run of ours write this path' says yes
# while not one byte of ours is left. The row is withheld on the marker pair, and
# this arm is why that second test exists: with the path test alone, --purge
# deleted a file the same run had just called 'not ours — keeping yours'.
P13="$TIUC_ROOT/agents-ours-then-replaced"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P13" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$P13" --client codex --yes >/dev/null 2>&1
if [ -n "$(tiuc_receipt_sha "$P13" 'AGENTS.md')" ]; then TIUC_PRE13=claimed; else TIUC_PRE13=unclaimed; fi
tiuc_eq "claimed" "$TIUC_PRE13" \
  "7f: install 1 claimed the path, so the receipt really does say yes to 'did we ever write here' and this arm is not vacuous"
printf '# My own entry document\n\nNO-KINGLET-MARKERS-AT-ALL\n' > "$P13/AGENTS.md"
TIUC_SHA13="$(tiuc_sha "$P13/AGENTS.md")"
TIUC_OUT13="$(bash "$REPO_DIR/install.sh" --project-dir "$P13" --client codex --yes 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g')"
if grep -qF -- 'keeping yours, untouched' <<< "$TIUC_OUT13"; then TIUC_SAY13=kept; else TIUC_SAY13=other; fi
tiuc_eq "kept" "$TIUC_SAY13" \
  "7f: the run says it is keeping the user's file untouched"
tiuc_eq "" "$(tiuc_receipt_sha "$P13" 'AGENTS.md')" \
  "7f: …and claims no row while saying it — a row here would be the false-reassurance pair this installer already records at its unreadable-origins block, with --purge acting on a file the sentence just disowned"
bash "$REPO_DIR/uninstall.sh" --project-dir "$P13" --yes --purge --no-backup >/dev/null 2>&1
if [ -f "$P13/AGENTS.md" ]; then TIUC_PURGE13=present; else TIUC_PURGE13=deleted; fi
tiuc_eq "present" "$TIUC_PURGE13" \
  "7f: …so even --purge leaves it, which is what 'not ours' has to mean at the one call site that can delete a file the user wrote"
tiuc_eq "$TIUC_SHA13" "$(tiuc_sha "$P13/AGENTS.md")" \
  "7f: …byte-for-byte"

# 7g — read-only and UNEDITED, which is the other half of 7e and a different code
# path. Perforce keeps every submitted, unopened file at 0444, so this is a
# project where the user has changed nothing at all: ownership says the file is
# ours, the whole-file write arm runs, and its `mv` lands on a read-only target.
# Measured under a pty before the guard: `mv` asked, the declined prompt exited 1,
# and because that `mv` is a bare command `set -e` ended the install — payload on
# disk, receipt written for what it had, rc 1. The merge arm had just been taught
# to refuse the identical condition, so the two arms answered it in opposite ways.
P14="$TIUC_ROOT/agents-read-only-unedited"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P14" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$P14" --client codex --yes >/dev/null 2>&1
chmod 444 "$P14/AGENTS.md"
TIUC_SHA14="$(tiuc_sha "$P14/AGENTS.md")"
TIUC_RC14=0
TIUC_OUT14="$(bash "$REPO_DIR/install.sh" --project-dir "$P14" --client codex --yes 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g')" || TIUC_RC14=$?
tiuc_eq "0" "$TIUC_RC14" \
  "7g: an install over a read-only, unedited AGENTS.md finishes — a bare mv onto that file aborted the whole run once the prompt was declined, with the payload already written"
tiuc_eq "444" "$(stat -c '%a' "$P14/AGENTS.md" 2>/dev/null || echo unknown)" \
  "7g: …and the file's mode is untouched, which is the observable half on a non-interactive host: the write arm ends in chmod 644, so a guard that let it run would clear the VCS's read-only bit"
if grep -qF -- 'AGENTS.md is read-only' <<< "$TIUC_OUT14"; then TIUC_WHY14=named; else TIUC_WHY14=silent; fi
tiuc_eq "named" "$TIUC_WHY14" \
  "7g: …and the run says which file and why rather than skipping it quietly"
tiuc_eq "$TIUC_SHA14" "$(tiuc_sha "$P14/AGENTS.md")" \
  "7g: …with its bytes as they were"

# ─────────────────────────────────────────────────────────────────────────────
# Arm 8 — merge_marked_region's own status contract, run from the extracted
# function rather than from a re-spelling of it.
#
# WHY IT IS NOT REACHED BY AN INSTALL. Two of the three outcomes are: the merge
# succeeds (every arm above), and the target is not writable (7e). The third —
# the RENAME fails — needs a condition no install fixture can produce from the
# outside: a read-only parent directory, a full filesystem, or, the shape this
# was found through, `mv`'s interactive overwrite prompt being declined on a tty.
# Deleting the `if mv …; then` test and letting the function fall through to
# `return 0` left this whole file GREEN before this arm existed, which is exactly
# the state the original defect shipped in: a merge that reports success over a
# file it never touched, with a receipt row recording the checksum of the file as
# it was before.
#
# It `eval`s the region inside a subshell, the same device arm 5 uses for the
# criterion: the definition cannot leak into this file's scope, and a change to
# install.sh's real function is what runs.
tiuc_merge_fn() {
  awk '/kinglet:merge-marked-region:begin/ { f = 1; next }
       /kinglet:merge-marked-region:end/   { f = 0 }
       f' "$REPO_DIR/install.sh"
}
TIUC_MERGE_SRC="$(tiuc_merge_fn)"
TIUC_MERGE_N=$(printf '%s\n' "$TIUC_MERGE_SRC" | grep -c . || true)
if [ "$TIUC_MERGE_N" -ge 8 ] && grep -qF -- 'merge_marked_region()' <<< "$TIUC_MERGE_SRC"; then TIUC_MERGE_OK=yes; else TIUC_MERGE_OK="extraction returned $TIUC_MERGE_N line(s)"; fi
tiuc_eq "yes" "$TIUC_MERGE_OK" \
  "the merge-function markers still delimit a real function — a renamed marker would make every call below run against an empty definition, and an empty eval reds nothing on its own"

TIUC_M8="$TIUC_ROOT/merge-contract"
mkdir -p "$TIUC_M8/dir"
tiuc_m8_reset() {   # rebuild a target with one well-formed pair and a facts file
  # `rm` FIRST, not a bare `>`. The previous case leaves the target at 0444 and a
  # redirection onto a file with no write bit is `Permission denied` — which under
  # this file's `set -euo pipefail` ends the run mid-arm with every later
  # assertion unreported, the failure shape this suite calls worse than a red.
  rm -f "$TIUC_M8/dir/target.md"
  printf 'above\n<!-- kinglet:generated:begin -->\nOLD-REGION\n<!-- kinglet:generated:end -->\nbelow\n' > "$TIUC_M8/dir/target.md"
  printf 'NEW-REGION\n' > "$TIUC_M8/facts.txt"
  chmod 640 "$TIUC_M8/dir/target.md"
}

# rc 0 — the ordinary path, and the control that keeps the two failure rows from
# passing over a function that always refuses.
tiuc_m8_reset
TIUC_M8_RC=0
( eval "$TIUC_MERGE_SRC"; merge_marked_region "$TIUC_M8/dir/target.md" "$TIUC_M8/facts.txt" ) || TIUC_M8_RC=$?
tiuc_eq "0" "$TIUC_M8_RC" \
  "8: a writable target with a well-formed pair merges and returns 0 — the control, without which a function that refused everything would pass both rows below"
if grep -qF -- 'NEW-REGION' "$TIUC_M8/dir/target.md" && ! grep -qF -- 'OLD-REGION' "$TIUC_M8/dir/target.md" \
   && grep -qF -- 'below' "$TIUC_M8/dir/target.md"; then TIUC_M8_BODY=merged; else TIUC_M8_BODY=wrong; fi
tiuc_eq "merged" "$TIUC_M8_BODY" \
  "8: …with the region replaced and the text outside the pair still there"

# rc 2 — not writable. Asserted here as well as end-to-end in 7e, because this is
# where the STATUS is visible rather than the sentence it produces.
tiuc_m8_reset
chmod 444 "$TIUC_M8/dir/target.md"
TIUC_M8_SHA="$(tiuc_sha "$TIUC_M8/dir/target.md")"
TIUC_M8_RC2=0
( eval "$TIUC_MERGE_SRC"; merge_marked_region "$TIUC_M8/dir/target.md" "$TIUC_M8/facts.txt" ) || TIUC_M8_RC2=$?
tiuc_eq "2" "$TIUC_M8_RC2" \
  "8: a read-only target returns 2 — its own status, so the caller can say 'read-only' instead of a generic failure the user cannot act on"
tiuc_eq "$TIUC_M8_SHA" "$(tiuc_sha "$TIUC_M8/dir/target.md")" \
  "8: …and nothing was written to it"

# rc 1 — the rename fails. A read-only PARENT is the portable, tty-free way to
# produce that: awk still writes its temp beside the facts file, so only the `mv`
# fails, which is the one line this arm exists for.
tiuc_m8_reset
chmod 555 "$TIUC_M8/dir"
TIUC_M8_SHA3="$(tiuc_sha "$TIUC_M8/dir/target.md")"
TIUC_M8_RC3=0
( eval "$TIUC_MERGE_SRC"; merge_marked_region "$TIUC_M8/dir/target.md" "$TIUC_M8/facts.txt" ) 2>/dev/null || TIUC_M8_RC3=$?
tiuc_eq "1" "$TIUC_M8_RC3" \
  "8: a rename that fails returns 1 rather than 0 — the status the first version of this function ignored, which is how a declined overwrite came to be reported as a successful refresh"
tiuc_eq "$TIUC_M8_SHA3" "$(tiuc_sha "$TIUC_M8/dir/target.md")" \
  "8: …and the target still holds the bytes it had, so the caller's decline is about a file that really was left alone"
# Restored immediately: the EXIT trap removes this root as one named path, and a
# 555 directory inside it would defeat that.
chmod 755 "$TIUC_M8/dir"

printf '  %s passed, %s failed\n' "$TIUC_PASS" "$TIUC_FAIL"
[ "$TIUC_FAIL" -eq 0 ]
