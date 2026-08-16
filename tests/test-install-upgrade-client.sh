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
#   shadow in scripts/studio-doctor.sh -> 24/26 here, the two behavioural arms red
#   shadow in install.sh               -> 26/26 GREEN here; 38 red across the full
#                                         suite, in test-install-prune.sh and
#                                         test-studio-doctor.sh
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

printf '  %s passed, %s failed\n' "$TIUC_PASS" "$TIUC_FAIL"
[ "$TIUC_FAIL" -eq 0 ]
