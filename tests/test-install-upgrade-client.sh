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
# `AGENTS.md` or `.codex/hooks.json` leaves the file on disk and writes NO row —
# "not ours, no claim", which is the installer's documented rule and the reason
# `uninstall.sh` never removes a file it did not install. Every arm below starts
# from a tree this suite built, so that state does not arise here; a future arm
# that introduces it should assert the rule, not the invariant.
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

tiuc_sha() {   # $1 = file
  sha256sum "$1" 2>/dev/null | cut -d' ' -f1
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
# So this arm asserts the property directly (the row still carries the PRE-edit
# checksum) and then asserts its consequence (the edit survives the uninstall).
# Either one alone reddens the mutation; both are here because the first says
# *what* is wrong and the second says *what it costs*.
# ─────────────────────────────────────────────────────────────────────────────
P3="$TIUC_ROOT/codex-then-edit-then-claude"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P3" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$P3" --client codex --yes >/dev/null 2>&1

# A REGULAR FILE, DERIVED FROM THE RECEIPT RATHER THAN NAMED. The mutation this
# arm exists for is scoped to regular files precisely because `sha_of` on a
# symlink-to-directory returns the empty string, so a symlink row cannot show the
# difference. Picking the first non-`symlink` Codex-layer row keeps the arm
# pointed at a file that can, without hardcoding which command happens to sort
# first.
TIUC_E_REL="$(awk -F'\t' '
  /^#/ { next }
  $1 == "path" { next }
  $1 ~ /^\.claude\// { next }
  $3 == "symlink" { next }
  $1 ~ /^\.agents\// { print $1; exit }
' "$P3/.claude/state/install-receipt.tsv" 2>/dev/null)"

if [ -n "$TIUC_E_REL" ] && [ -f "$P3/$TIUC_E_REL" ]; then TIUC_E_OK=yes; else TIUC_E_OK="no candidate row (got '$TIUC_E_REL')"; fi
tiuc_eq "yes" "$TIUC_E_OK" \
  "the receipt carries a non-symlink Codex-layer row pointing at a real file — without one, every assertion in this arm is about nothing"

TIUC_E_BEFORE="$(tiuc_receipt_sha "$P3" "$TIUC_E_REL")"
printf 'a line the user added\n' >> "$P3/$TIUC_E_REL"
TIUC_E_ONDISK="$(tiuc_sha "$P3/$TIUC_E_REL")"

# THE FLOOR THAT STOPS THE NEXT ASSERTION COMPARING A VALUE TO ITSELF. If the
# append silently did nothing — a read-only path, a mode this fixture does not
# produce — the recorded and on-disk checksums stay equal and "the row still
# carries the pre-edit sha" is true for the wrong reason, in both arms of the
# mutation.
if [ -n "$TIUC_E_BEFORE" ] && [ "$TIUC_E_BEFORE" != "$TIUC_E_ONDISK" ]; then TIUC_E_DIFF=yes; else TIUC_E_DIFF=no; fi
tiuc_eq "yes" "$TIUC_E_DIFF" \
  "the edit actually changed the file's checksum, so 'the row was not re-derived' is a claim with two distinguishable answers"

bash "$REPO_DIR/install.sh" --project-dir "$P3" --yes >/dev/null 2>&1

tiuc_eq "$TIUC_E_BEFORE" "$(tiuc_receipt_sha "$P3" "$TIUC_E_REL")" \
  "the carried row keeps the checksum the Codex run recorded — re-deriving it from disk would newly claim a file the user edited"

bash "$REPO_DIR/uninstall.sh" --project-dir "$P3" --yes >/dev/null 2>&1
if [ -f "$P3/$TIUC_E_REL" ]; then TIUC_E_SURVIVED=present; else TIUC_E_SURVIVED=deleted; fi
tiuc_eq "present" "$TIUC_E_SURVIVED" \
  "…and uninstall.sh therefore leaves the edited file alone, which is what that checksum is FOR"

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
# Codex layer a doctor that fails forever with no way to clear it. What must not
# be silent is the drop. Both sentences are asserted here because either alone
# leaves the loop open at the other end.
# ─────────────────────────────────────────────────────────────────────────────
P4="$TIUC_ROOT/codex-then-missing"
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$P4" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$P4" --client codex --yes >/dev/null 2>&1
rm -f "$P4/.codex/hooks.json"

TIUC_DOC="$(bash "$REPO_DIR/scripts/studio-doctor.sh" --project-dir "$P4" 2>&1 || true)"
# Here-string, never a pipe: `grep -q` exits at the first match without draining
# stdin, and under `set -euo pipefail` that SIGPIPEs the writer.
if grep -qF -- 'missing — re-run install.sh --client codex' <<< "$TIUC_DOC"; then TIUC_DOC_R=named; else TIUC_DOC_R=bare; fi
tiuc_eq "named" "$TIUC_DOC_R" \
  "the doctor's remedy for a missing Codex-layer path names --client codex — a bare 're-run install.sh' steers the user into the drop below"

TIUC_INS="$(bash "$REPO_DIR/install.sh" --project-dir "$P4" --yes 2>&1 || true)"
if grep -qF -- '.codex/hooks.json' <<< "$TIUC_INS"; then TIUC_INS_NAMED=yes; else TIUC_INS_NAMED=no; fi
tiuc_eq "yes" "$TIUC_INS_NAMED" \
  "…and when the default client then drops that row, the run names the path it dropped rather than only counting what it kept"

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

printf '  %s passed, %s failed\n' "$TIUC_PASS" "$TIUC_FAIL"
[ "$TIUC_FAIL" -eq 0 ]
