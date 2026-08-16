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
# Self-contained: defines its own helpers and sets `set -euo pipefail`, so
# `bash tests/test-install-upgrade-client.sh` is a valid way to run it.
# ============================================================================
set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

echo "--- install: upgrading across clients ---"

TIUC_PASS=0
TIUC_FAIL=0
tiuc_eq() {   # expected actual message
  if [ "$1" = "$2" ]; then
    TIUC_PASS=$((TIUC_PASS + 1))
    printf '  ok   %s\n' "$3"
  else
    TIUC_FAIL=$((TIUC_FAIL + 1))
    printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$3" "$1" "$2"
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

printf '  %s passed, %s failed\n' "$TIUC_PASS" "$TIUC_FAIL"
[ "$TIUC_FAIL" -eq 0 ]
