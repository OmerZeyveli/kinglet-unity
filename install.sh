#!/usr/bin/env bash
#
# Kinglet Pioneer — installer
#
# Installs the toolkit into a Unity project: agents, commands, skills, hooks, rules, templates,
# settings, and a generated CLAUDE.md. One repo, one script, no prerequisites beyond Unity itself.
#
# Usage:
#   ./install.sh [--project-dir <path>] [--with-mcp] [--with-input-system] [--yes] [--dry-run]
#
#   --project-dir <path>  Target Unity project root (default: current directory)
#   --with-mcp            Also add the CoplayDev Unity MCP package to Packages/manifest.json
#   --with-input-system   Also add Unity's New Input System package to Packages/manifest.json
#   --yes                 Non-interactive; take the safe default at every prompt
#   --dry-run             Report what would happen; write nothing
#   -h, --help            Show this help
#
# Every file written is recorded in .claude/state/install-receipt.tsv with its checksum, so
# uninstall can remove exactly what we installed and leave everything else — including files you
# edited — alone.
#
set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi
info() { printf '%s\n' "${BLUE}==>${NC} $*"; }
ok()   { printf '%s\n' "${GREEN} ok${NC}  $*"; }
warn() { printf '%s\n' "${YELLOW}warn${NC} $*"; }
err()  { printf '%s\n' "${RED}err ${NC} $*" >&2; }
die()  { err "$*"; exit 1; }

usage() { sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_VERSION="$(cat "$SCRIPT_DIR/.claude/VERSION" 2>/dev/null || echo unknown)"

MCP_PKG_NAME="com.coplaydev.unity-mcp"
# Pinned to v10.1.0's commit (see .claude/UPSTREAM), not #main — which version a user got used to
# depend on the day they ran --with-mcp.
#
# It must be a FULL 40-character SHA or a tag. UPM rejects a short hash outright:
#   "Could not clone. Make sure [<ref>] is a valid branch name, tag or full commit hash"
#
# The previous value here, `a4c2d0a84573`, was neither. It was read off the Unity package cache
# directory `Library/PackageCache/com.coplaydev.unity-mcp@a4c2d0a84573` and recorded as a commit.
# That suffix is Unity's own content hash, not a git revision — the same cache directory appears
# with that identical suffix after resolving from this pin, and registry packages that have no git
# repository at all carry one too (`com.unity.2d.animation@6e14714a57c6`). GitHub returns
# "No commit found for SHA" for it. So --with-mcp could never have worked, and did not, until it
# was run end to end on 2026-07-30.
MCP_PKG_URL="https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#c14de1e6dc01ab42d2bb358730cff954bce0ce6b"

# unity-specifics.md makes the New Input System non-negotiable and block-legacy-input.sh blocks
# `Input.*` outright. Without the package a compliant script fails to compile — and a compile
# error also aborts Unity's -executeMethod, so Editor automation stops too (smoke-pass.md §6c).
# It is a first-party Unity registry package, so a version pin (not a git URL) is all it needs.
# Pinned to 1.18.0 — the version measured in a real, working Unity 6 project (URP, 1073 C# files,
# Unity 6000.0.68f1) per docs/research/pioneer/smoke-pass.md §9. It is the only version of this
# package this toolkit has been observed alongside in a working Unity 6 project.
INPUT_SYSTEM_PKG_NAME="com.unity.inputsystem"
INPUT_SYSTEM_PKG_VERSION="1.18.0"

RECEIPT_REL=".claude/state/install-receipt.tsv"

# ── Args ─────────────────────────────────────────────────────────────────────
PROJECT_DIR="$(pwd)"
WITH_MCP=0; WITH_INPUT_SYSTEM=0; ASSUME_YES=0; DRY_RUN=0
PROVIDER_CHOICE=""
# Overridable so the test suite can point at a fixture instead of the real home
# directory. install.sh reads nothing else from $HOME; this read is the first,
# it is read-only, and its absence is benign.
CLAUDE_USER_SETTINGS="${KINGLET_USER_SETTINGS:-$HOME/.claude/settings.json}"
while [ $# -gt 0 ]; do
  case "$1" in
    # Validate before shift 2: under `set -u`, `shift 2` on a trailing flag kills the script
    # before any error message can print.
    --project-dir)      [ $# -ge 2 ] || die "--project-dir requires a path"; PROJECT_DIR="$2"; shift 2 ;;
    --with-mcp)          WITH_MCP=1; shift ;;
    --with-input-system) WITH_INPUT_SYSTEM=1; shift ;;
    --yes|-y)            ASSUME_YES=1; shift ;;
    --dry-run)           DRY_RUN=1; shift ;;
    -h|--help)           usage ;;
    *)                   die "Unknown argument: $1 (use --help)" ;;
  esac
done

PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || die "Project directory not found"
CLAUDE_DIR="$PROJECT_DIR/.claude"
RECEIPT="$PROJECT_DIR/$RECEIPT_REL"

printf '%s\n' "${BOLD}Kinglet Pioneer ${TOOLKIT_VERSION}${NC} — installer"
info "Project: $PROJECT_DIR"
[ "$DRY_RUN" -eq 1 ] && warn "Dry run — nothing will be written."

# ── Step 1: Validate Unity project ───────────────────────────────────────────
[ -d "$PROJECT_DIR/Assets" ] || die "No Assets/ directory — this does not look like a Unity project."
[ -d "$PROJECT_DIR/ProjectSettings" ] || die "No ProjectSettings/ directory — this does not look like a Unity project."
[ -d "$SCRIPT_DIR/.claude" ] || die "Payload not found at $SCRIPT_DIR/.claude — run install.sh from the kinglet-unity repo root."
ok "Unity project detected."

# ── Step 2: Scan project ─────────────────────────────────────────────────────
UNITY_VERSION="unknown"
# awk on the file rather than `grep | head -1` — see the note in scripts/generate-claude-md.sh.
[ -f "$PROJECT_DIR/ProjectSettings/ProjectVersion.txt" ] && \
  UNITY_VERSION=$(awk '/^m_EditorVersion:/ {print $2; exit}' "$PROJECT_DIR/ProjectSettings/ProjectVersion.txt")
[ -n "$UNITY_VERSION" ] || UNITY_VERSION="unknown"
RENDER_PIPELINE="Built-in"
MANIFEST="$PROJECT_DIR/Packages/manifest.json"
if [ -f "$MANIFEST" ]; then
  grep -q 'com.unity.render-pipelines.universal' "$MANIFEST" && RENDER_PIPELINE="URP"
  grep -q 'com.unity.render-pipelines.high-definition' "$MANIFEST" && RENDER_PIPELINE="HDRP"
fi
ok "Unity $UNITY_VERSION · $RENDER_PIPELINE"

HAS_INPUT_SYSTEM=0
if [ -f "$MANIFEST" ] && grep -q "$INPUT_SYSTEM_PKG_NAME" "$MANIFEST"; then
  HAS_INPUT_SYSTEM=1
fi
if [ "$HAS_INPUT_SYSTEM" -eq 1 ]; then
  ok "$INPUT_SYSTEM_PKG_NAME already in manifest.json."
else
  # Unconditional — unlike --with-mcp this is not an optional integration, it is what the toolkit's
  # own rules require to compile. A warning that only fires with a flag nobody knows to pass is a
  # warning nobody reads.
  warn "$INPUT_SYSTEM_PKG_NAME is missing. unity-specifics.md makes the New Input System"
  warn "non-negotiable and blocks legacy Input.* — without the package, the first script written"
  warn "under this toolkit's own rules will fail to compile."
  warn "Re-run with --with-input-system to add it, or add it to Packages/manifest.json yourself."
fi

# ── Step 3: Decide how to handle an existing .claude/ ────────────────────────
# Three cases, and the receipt is what tells them apart:
#   fresh          — no .claude/ at all
#   ours           — .claude/ + a receipt we wrote: a genuine upgrade, so we can be precise
#   foreign        — .claude/ but no receipt (a teammate's git clone, or a hand-rolled setup).
#                    We did not write it, so we do not get to assume it is ours to replace.
MODE=fresh
if [ -d "$CLAUDE_DIR" ]; then
  if [ -f "$RECEIPT" ]; then MODE=ours; else MODE=foreign; fi
fi

BACKUP_DIR=""
case "$MODE" in
  fresh)   ok "No existing .claude/ — clean install." ;;
  ours)
    PREV=$(grep -m1 '^# toolkit-version:' "$RECEIPT" 2>/dev/null | sed 's/.*: //' || echo unknown)
    info "Existing Kinglet install found (version $PREV) — upgrading to $TOOLKIT_VERSION."
    info "Files you modified will be reported and kept; untouched files are replaced."
    ;;
  foreign)
    warn "$CLAUDE_DIR exists but has no install receipt."
    warn "Kinglet did not create it, so it will not be removed or merged blindly."
    if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
      REPLY_CHOICE=1
      info "Non-interactive — backing up the existing .claude/ and installing fresh."
    else
      printf '\n  1) Back up %s and install fresh  (safe default)\n' ".claude/"
      printf '  2) Abort\n\n'
      read -rp "  Choose [1/2]: " REPLY_CHOICE
    fi
    case "${REPLY_CHOICE:-2}" in
      1) BACKUP_DIR="$PROJECT_DIR/.claude.backup.$(date +%Y%m%d%H%M%S)" ;;
      *) info "Aborted."; exit 0 ;;
    esac
    ;;
esac

# ── Step 4: Work out what we are about to write ──────────────────────────────
# Enumerated at runtime. The old installer kept hand-synced arrays of filenames in three separate
# scripts; a payload this size makes that a liability, and `find` cannot drift.
PAYLOAD_FILES=$(cd "$SCRIPT_DIR/.claude" && find . -type f ! -path './state/*' | sed 's|^\./||' | sort)
PAYLOAD_COUNT=$(printf '%s\n' "$PAYLOAD_FILES" | grep -c . || true)
info "Payload: $PAYLOAD_COUNT files"

# Every .claude path this run will own, in receipt form. Built here rather than derived twice,
# because the dry run and the real run must answer the same question: what belongs afterwards?
# Keep this in step with the two write loops below (the payload loop and the `for group in scripts`
# loop) — a path written but missing here would be deleted as an orphan the run after it appears.
# There is one group and it is `scripts`. This line read "the scripts/tests groups" until 2026-08-12,
# naming a tests/ write that has never existed — the same defect as the dry-run summary's old
# "scripts/ and tests/ into .claude/" line, which was fixed while this one was left standing.
NEW_PATHS=$(
  printf '%s\n' "$PAYLOAD_FILES" | sed 's|^|.claude/|'
  for group in scripts; do
    [ -d "$SCRIPT_DIR/$group" ] || continue
    for f in "$SCRIPT_DIR/$group"/*.sh; do
      [ -f "$f" ] || continue
      b=$(basename "$f")
      [ "$b" = "check-provenance.sh" ] && continue
      printf '.claude/%s/%s\n' "$group" "$b"
    done
  done
)
NEW_PATHS=$(printf '%s\n' "$NEW_PATHS" | sort -u)

# The dry run reported the payload as a file count and the scripts group as a bare name — two lines
# in two different units, so a reader could not add them up and get the number of files this run
# writes. Counted off NEW_PATHS rather than re-walking scripts/, so it cannot disagree with the
# enumeration the real run and the receipt are both built from.
SCRIPTS_COUNT=$(printf '%s\n' "$NEW_PATHS" | grep -c '^\.claude/scripts/' || true)

# A missing file hashes to the empty string, and the guard lives HERE rather than at each call site.
#
# The old body was `sha256sum "$1" 2>/dev/null | cut -d' ' -f1`, which is safe only for as long as
# every caller happens to check existence first. They all do today — owned_by_installer returns
# early, the upgrade scan `continue`s, and both write loops hash a file they just wrote or just
# proved present — so this changes no behaviour now. It is the asymmetry that is the defect: the
# helper's contract was "the caller has already checked", enforced nowhere.
#
# Two different failures were one edit away. Under `set -euo pipefail` sha256sum exits 1 on a
# missing path, pipefail promotes that through the `| cut`, and at an ASSIGNMENT site set -e kills
# the installer with no message. At the four receipt-row sites the substitution sits inside a printf
# argument, where set -e does not reach, so the same miss instead writes a row with an EMPTY
# checksum — a receipt that uninstall.sh will silently decline to act on, which is worse. Measured
# in tests/test-install-ownership.sh, where the identical helper took the whole test file down
# mid-state and the assertions after it read as absent rather than red.
sha_of() {
  [ -f "$1" ] || return 0
  sha256sum "$1" | cut -d' ' -f1
}

# ── Ownership, not authorship ────────────────────────────────────────────────
# A receipt row says "this file is ours to remove", not "this run wrote it". Those were the same
# sentence while the project-root rows were written inside their create branches, and they part
# company on the second install: the branch is skipped, $RECEIPT_TMP is rebuilt from scratch, and
# the rebuilt receipt disowns a file the installer put there. uninstall.sh — which removes only
# receipt-listed paths, deliberately, because a previous version deleted by filename — then leaves
# it behind forever. Two installs, the same files, a different ownership record, and the second
# record is the wrong one.
#
# THE TEST MUST FAIL CLOSED. Claiming a file we do not own means uninstall.sh deletes the user's
# work, which is the whole reason the uninstaller is receipt-driven. So ownership is proved, never
# assumed, by one of two checksum comparisons, and a file that satisfies neither gets no row:
#
#   1. it is byte-for-byte the copy this toolkit ships, or
#   2. a previous run recorded it as `toolkit` AND it still carries that run's checksum.
#
# The second half of (2) is what makes "the user edits a file we installed" come out right. The row
# is there and says `toolkit`; the bytes have moved; we do not renew the claim. Reading presence in
# the old receipt alone would renew it, and uninstall.sh would delete an edited file.
#
# No `user-modified` row is written for these two, and that is a decision rather than an omission.
#
# It was once forced by a defect elsewhere: uninstall.sh's classifier compared the recorded checksum
# and never read the origin column, so a `user-modified` row — which records the file AS EDITED —
# matched on sha and was deleted by a plain `uninstall.sh --yes`. Measured 2026-08-12 on
# .claude/rules/pc-console.md, and FIXED the same day: the classifier now branches on origin first,
# and tests/test-install-ownership.sh's state G holds all three directions of it.
#
# The decision survives the fix, for a reason that was always the better one. A `user-modified` row
# is still a claim of ownership, and `--purge` acts on every claim. State C's MCP-SETUP.md — one the
# user wrote before any install ever ran — is not ours to purge, and nothing at this call site can
# tell that file apart from one of ours the user rewrote. No row, no claim.
#
# $RECEIPT still holds the PREVIOUS run's receipt at every call site below. Four statements could
# have changed that and none does: Step 9 is the only writer, the payload enumeration excludes
# state/, the orphan sweep skips .claude/state/*, and `mv "$CLAUDE_DIR" "$BACKUP_DIR"` in Step 5
# moves the whole directory away — but only in `foreign` mode, which is DEFINED by the receipt
# being absent, so the `[ -f "$RECEIPT" ]` guard below is already false there and fails closed.
owned_by_installer() {
  # $1 project-relative path; $2 the toolkit's copy of it ('' when there is none on disk).
  local rel="$1" ref="${2:-}" abs have
  abs="$PROJECT_DIR/$rel"
  [ -f "$abs" ] || return 1
  have=$(sha_of "$abs")
  if [ -n "$ref" ] && [ -f "$ref" ] && [ "$have" = "$(sha_of "$ref")" ]; then
    return 0
  fi
  [ -f "$RECEIPT" ] || return 1
  awk -F'\t' -v want="$rel" -v have="$have" '
    $1 == want && $2 == have && $4 == "toolkit" { found = 1 }
    END { exit !found }' "$RECEIPT"
}

# On upgrade, find files the user edited so we can leave them alone.
MODIFIED_FILES=""
if [ "$MODE" = ours ]; then
  while IFS=$'\t' read -r rel recorded _mode origin; do
    case "$rel" in ''|\#*) continue ;; esac
    [ -f "$PROJECT_DIR/$rel" ] || continue
    # `user-modified` is sticky. When a previous run kept your edit, it recorded the file as it then
    # stood — so on the next run the checksum matches the receipt and a sha-only test concludes the
    # file is untouched and overwrites it. Your edit survived exactly one upgrade and then vanished,
    # silently. Measured twice on the same file in one day. The origin column was already written
    # for this; it was just never read.
    if [ "$origin" = user-modified ]; then
      MODIFIED_FILES="${MODIFIED_FILES}${rel}"$'\n'
      continue
    fi
    actual=$(sha_of "$PROJECT_DIR/$rel")
    [ "$actual" = "$recorded" ] || MODIFIED_FILES="${MODIFIED_FILES}${rel}"$'\n'
  done < <(grep -v '^#' "$RECEIPT" 2>/dev/null | tail -n +2 || true)
  MOD_COUNT=$(printf '%s' "$MODIFIED_FILES" | grep -c . || true)
  if [ "$MOD_COUNT" -gt 0 ]; then
    warn "$MOD_COUNT installed file(s) have local edits — keeping yours:"
    printf '%s' "$MODIFIED_FILES" | while IFS= read -r m; do [ -n "$m" ] && printf '       %s\n' "$m"; done
  fi
fi

is_modified() { grep -qxF -- "$1" <<< "$MODIFIED_FILES"; }

# Surfaces the previous install owns and this payload no longer contains.
#
# The installer used to only ever add. The 2026-08-03 surface cut removed 74 files, and installing
# over an older install left every one of them on disk and selectable — 114 orphans against a real
# project — so the cut was invisible in the only place it matters. An upgrade that leaves a deleted
# agent reachable is worse than no upgrade: the model still sees it.
#
# Anything the user edited is never removed. A file whose checksum drifted is theirs, whatever the
# payload now says, and deleting it is the failure mode this installer just finished fixing on the
# other side.
ORPHANS=""; ORPHANS_KEPT=""
if [ "$MODE" = ours ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    case "$rel" in .claude/state/*) continue ;; esac
    [ -e "$PROJECT_DIR/$rel" ] || continue
    if is_modified "$rel"; then
      ORPHANS_KEPT="${ORPHANS_KEPT}${rel}"$'\n'
    else
      ORPHANS="${ORPHANS}${rel}"$'\n'
    fi
  done < <(comm -23 \
      <(grep -v '^#' "$RECEIPT" 2>/dev/null | tail -n +2 | cut -f1 | grep '^\.claude/' | sort -u) \
      <(printf '%s\n' "$NEW_PATHS"))
fi
ORPHAN_COUNT=$(printf '%s' "$ORPHANS" | grep -c . || true)
ORPHAN_KEPT_COUNT=$(printf '%s' "$ORPHANS_KEPT" | grep -c . || true)

# ── Step 3b: The decisions the dry run and the real run must not compute twice ───────────────────
#
# Everything below is ANNOUNCED by the `Would install:` block a few lines down and ACTED ON by
# Steps 7 and 8, hundreds of lines later. It lives here, above both, for the reason this block has
# already paid for twice — once on the CLAUDE.md branch, once on MCP-SETUP.md: an announcement
# computed from a COPY of the write's condition is a second definition of that condition, and a
# second definition drifts. Call the predicate; never restate it.

# ── The .gitignore decision ──────────────────────────────────────────────────
# Ask git what it already ignores rather than grepping for our exact lines. A project that ignores
# `/.claude/` wholesale — a perfectly sensible choice, and one real projects make — is already
# covered, and appending our entries to it is just noise in someone else's file.
#
# TWO KINDS, NOT ONE LIST, AND MERGING THEM WOULD BE A BUG. `WANT_IGNORED` holds concrete PROBE
# PATHS to hand to `git check-ignore`, which needs a path and can never be handed a negation.
# `GITIGNORE_ENTRIES` holds the PATTERNS actually appended. The correspondence is 3 → 4, not 1:1:
# `.claude/state/session.json` is the probe for both `.claude/state/*` and the negation
# `!.claude/state/.gitkeep`. Both counts are DERIVED wherever they are used rather than written into
# a sentence — the sentence that used to sit here said "three" for a whole wave after a fourth
# pattern was added below it.
GITIGNORE="$PROJECT_DIR/.gitignore"
WANT_IGNORED='.claude/settings.local.json
.claude/state/session.json
.claude.backup.20260101120000/'
# uninstall.sh writes its backup to .claude.backup.<timestamp>/ at the project root. Without the
# last entry, every uninstall leaves an untracked directory that dirties `git status` in the user's
# own repo.
GITIGNORE_ENTRIES='.claude/settings.local.json
.claude/state/*
!.claude/state/.gitkeep
.claude.backup.*/'
GITIGNORE_ENTRY_COUNT=$(printf '%s\n' "$GITIGNORE_ENTRIES" | grep -c . || true)

already_ignored() {
  git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
  git -C "$PROJECT_DIR" check-ignore -q "$1" 2>/dev/null
}

# THE DECISION IS TWO-STAGE, and an announcement built on the first stage alone is wrong in every
# project git does not track — which is the shape of every second install in such a project.
#
#   Stage 1  `already_ignored` per probe path. OUTSIDE a work tree it cannot answer and returns 1
#            for everything, so this stage says "needed" on every run of a non-git project and can
#            never be the thing that declines there.
#   Stage 2  the per-entry `grep -qxF` that used to live inside `add_ignore`. This is what actually
#            declines on that second install: all four literals are already lines in the file from
#            install 1, nothing is appended, and the run prints "already has our entries".
#
# Prints a verdict word on the first line, then the entries an append would add, in order:
#   covered   a .gitignore exists and git ignores every probe path — Step 7 leaves the file alone
#   present   the block runs, and every entry is already a line in the file — nothing is appended
#   append    the lines that follow are exactly what Step 7 appends, in the order it appends them
gitignore_plan() {
  local p e needed=0 missing=''
  # Stage 1 can only decline when there is a file to leave alone — the real run's guard is
  # `NEEDED -eq 0` AND `-f "$GITIGNORE"` — so with no file the probes cannot change the outcome.
  if [ -f "$GITIGNORE" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      already_ignored "$p" || needed=1
    done <<< "$WANT_IGNORED"
    if [ "$needed" -eq 0 ]; then printf 'covered\n'; return 0; fi
  fi
  # Stage 2. `grep` reads a FILE ARGUMENT, not a pipe, so `-q`'s exit-on-first-match cannot SIGPIPE
  # a writer under `set -euo pipefail`. A missing file makes grep exit 2, which is "not present" —
  # the create path's correct answer, and the reason no `-f` test is needed here.
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    grep -qxF -- "$e" "$GITIGNORE" 2>/dev/null || missing="${missing}${e}"$'\n'
  done <<< "$GITIGNORE_ENTRIES"
  if [ -z "$missing" ]; then printf 'present\n'; return 0; fi
  printf 'append\n%s' "$missing"
}

# ── The Packages/manifest.json decisions ─────────────────────────────────────
# Derived from $MANIFEST rather than written out again, so the receipt row, the announcement, and
# the file they both name cannot disagree. A row whose path is one character off is a row
# uninstall.sh silently declines to act on, which on disk is indistinguishable from no row at all.
MANIFEST_BAK_REL="${MANIFEST#"$PROJECT_DIR"/}.bak"

# Would a --with-* flag passed to THIS run still have an edit to make? `add_manifest_dependency`
# returns early when there is no manifest or the package is already in it, and an early return
# copies nothing — so neither the edit nor the backup happens.
manifest_edit_pending() {
  [ -f "$MANIFEST" ] || return 1
  if [ "$WITH_MCP" -eq 1 ] && ! grep -q "$MCP_PKG_NAME" "$MANIFEST" 2>/dev/null; then return 0; fi
  if [ "$WITH_INPUT_SYSTEM" -eq 1 ] && [ "$HAS_INPUT_SYSTEM" -eq 0 ]; then return 0; fi
  return 1
}

# D11's decline, asked the way `add_manifest_dependency` asks it. A Packages/manifest.json.bak that
# exists and is not ours abandons THE WHOLE FLAG rather than overwriting the user's file — so the
# manifest edit does not happen either, and an announcement that promised it would be wrong in the
# direction that destroys trust. `MANIFEST_BAK_KEPT`'s disjunct is deliberately absent here: it
# answers "this run already made the copy", and at dry-run time no run has.
manifest_bak_is_foreign() {
  [ -e "$MANIFEST.bak" ] || return 1
  if owned_by_installer "$MANIFEST_BAK_REL" ''; then return 1; fi
  return 0
}

# Would THIS run create Packages/manifest.json.bak and keep it? FIVE conditions gate that file in
# `add_manifest_dependency`, and FOUR of them are answerable from here:
#
#   1. a manifest exists                        — asked, inside manifest_edit_pending
#   2. some flag still has an edit to make      — asked, manifest_edit_pending
#   3. it is not D11's decline                  — asked, manifest_bak_is_foreign
#   4. the surgical `sed` insert SUCCEEDED      — NOT ASKABLE HERE. The failure arm runs
#                                                 `mv "$MANIFEST.bak" "$MANIFEST"` and leaves no
#                                                 backup behind, and the only way to know in advance
#                                                 is to rehearse the edit on a temp copy. The
#                                                 announcement NAMES this condition instead of
#                                                 pretending to have evaluated it.
#   5. git does not track Packages/manifest.json — asked. When git tracks it, git IS the backup and
#                                                 the .bak is deleted straight after the edit.
manifest_bak_would_be_kept() {
  manifest_edit_pending || return 1
  if manifest_bak_is_foreign; then return 1; fi
  if git -C "$PROJECT_DIR" ls-files --error-unmatch Packages/manifest.json >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

if [ "$DRY_RUN" -eq 1 ]; then
  printf '\n%s\n' "${BOLD}Would install:${NC}"
  printf '  %s files into %s\n' "$PAYLOAD_COUNT" "$CLAUDE_DIR"
  printf '  %s files from scripts/ into %s/scripts\n' "$SCRIPTS_COUNT" "$CLAUDE_DIR"
  if [ "$ORPHAN_COUNT" -gt 0 ]; then
    printf '  remove %s file(s) this payload no longer ships:\n' "$ORPHAN_COUNT"
    printf '%s' "$ORPHANS" | while IFS= read -r o; do [ -n "$o" ] && printf '       %s\n' "$o"; done
  fi
  [ "$ORPHAN_KEPT_COUNT" -gt 0 ] && printf '  keep %s removed-from-payload file(s) you edited\n' "$ORPHAN_KEPT_COUNT"
  # MODIFIED_FILES is always set; KEPT/MOD_COUNT are not defined until Step 5 and would be an
  # unbound-variable death under `set -u`.
  DRY_MOD=$(printf '%s' "$MODIFIED_FILES" | grep -c . || true)
  [ "$DRY_MOD" -gt 0 ] && printf '  keep %s file(s) you modified\n' "$DRY_MOD"

  # Report the CLAUDE.md branch we would actually take. This said "CLAUDE.md (generated)"
  # unconditionally, which is a lie in the one case that matters: against a project that already has
  # a CLAUDE.md, the real install writes CLAUDE.md.generated and leaves theirs alone. A dry run that
  # misreports the only step capable of destroying work is worse than having no dry run.
  if [ ! -f "$PROJECT_DIR/CLAUDE.md" ]; then
    printf '  CLAUDE.md (new — generated)\n'
  elif grep -q 'kinglet:generated:begin' "$PROJECT_DIR/CLAUDE.md" 2>/dev/null; then
    printf '  CLAUDE.md — refresh the generated section only; your prose untouched\n'
  else
    # TWO FILES, TWO FATES, AND THIS ARM USED TO NAME ONE AND DESCRIBE THE OTHER:
    #
    #   CLAUDE.md.generated — yours exists and has no markers, so it is NOT touched
    #
    # "yours", "has no markers" and "NOT touched" are all true of CLAUDE.md. The file the line NAMES
    # is the one this arm CREATES. So the dry run promised to leave alone the only path it was about
    # to write, on the branch a user reaches by already having a CLAUDE.md of their own — which is
    # exactly the reader who is checking whether their file is safe.
    #
    # Split, so each path gets its own sentence and the guard can read one claim per line.
    printf '  CLAUDE.md — yours has no generated markers, so it is NOT touched\n'
    # THE SAME PREDICATE THE REAL RUN USES, called rather than restated: an announcement computed
    # from a copy of the write's condition is a second definition that drifts, which is the failure
    # this whole block has already paid for twice. owned_by_installer is defined above this point,
    # $RECEIPT still holds the previous run's receipt here, and the arguments match the real run's
    # call — '' for the reference copy, because this file is generated per project and has none.
    if [ -e "$PROJECT_DIR/CLAUDE.md.generated" ] && ! owned_by_installer 'CLAUDE.md.generated' ''; then
      printf '  CLAUDE.md.generated exists and is not ours — would leave alone, and generate nothing\n'
    else
      printf '  CLAUDE.md.generated — generated beside your own CLAUDE.md, for you to merge by hand\n'
    fi
  fi

  # THE SAME PLAN STEP 7 ACTS ON, called rather than restated. The line here was unconditional and
  # named two of the four entries: it promised an edit on every run, including the two runs that
  # make none, and under-described the one run that does.
  #
  # THE DECLINE WORDING IS A CONTRACT WITH tests/test-install-dryrun.sh'S PARSER, NOT FREE PROSE.
  # That file reads a line whose first field is a path as a PROMISE unless the line carries one of
  # the phrases it recognises. `already covered` and `no change` are both in that set; the real
  # run's own "already has our entries" is deliberately NOT, because the bias is toward a loud false
  # red rather than a silent false green. Both declines below therefore carry the recognised
  # spelling and say WHICH of the two mechanisms declined in the prose after it.
  DRY_GITIGNORE_PLAN="$(gitignore_plan)"
  case "${DRY_GITIGNORE_PLAN%%$'\n'*}" in
    covered)
      printf '  .gitignore — git already ignores every path we would add, so it is already covered — no change\n' ;;
    present)
      printf '  .gitignore — all %s of our entries are already lines in it, so it is already covered — no change\n' \
        "$GITIGNORE_ENTRY_COUNT" ;;
    *)
      # ONE LINE, WITH THE ENTRIES ON IT RATHER THAN INDENTED UNDER IT. An entry per line would give
      # each entry a first field of its own and mint claims about paths nothing writes.
      DRY_GITIGNORE_ADD="${DRY_GITIGNORE_PLAN#*$'\n'}"
      DRY_GITIGNORE_N=$(printf '%s\n' "$DRY_GITIGNORE_ADD" | grep -c . || true)
      # awk drains its input to the end, so this pipeline cannot SIGPIPE the writer.
      DRY_GITIGNORE_LIST="$(printf '%s\n' "$DRY_GITIGNORE_ADD" \
        | awk 'NF { if (n++) printf ", "; printf "%s", $0 } END { printf "\n" }')"
      if [ -f "$GITIGNORE" ]; then
        printf '  .gitignore — append %s entries: %s\n' "$DRY_GITIGNORE_N" "$DRY_GITIGNORE_LIST"
      else
        printf '  .gitignore (new) — create it, with %s entries: %s\n' "$DRY_GITIGNORE_N" "$DRY_GITIGNORE_LIST"
      fi ;;
  esac

  # ── Packages/manifest.json, its backup, and the flags ──────────────────────
  # LEAD WITH THE PATH. These lines used to begin `--with-mcp:` / `--with-input-system:`, so their
  # first field was a FLAG NAME. A reader scanning the block for the files a run touches — and
  # tests/test-install-dryrun.sh's parser, which reads the first field — saw no claim about
  # Packages/manifest.json at all, while the real run edited it in place at the project root.
  #
  # The third arm is D11's decline, and it is new. A Packages/manifest.json.bak that is not ours
  # abandons the flag rather than overwriting it, so the edit this block used to promise
  # unconditionally does not happen.
  if [ "$WITH_MCP" -eq 1 ]; then
    if [ ! -f "$MANIFEST" ]; then
      printf '  Packages/manifest.json — none in this project, so --with-mcp would skip\n'
    elif grep -q "$MCP_PKG_NAME" "$MANIFEST" 2>/dev/null; then
      printf '  Packages/manifest.json — %s already present, so --with-mcp would skip\n' "$MCP_PKG_NAME"
    elif manifest_bak_is_foreign; then
      printf '  Packages/manifest.json — %s is not ours, so --with-mcp is declined and the manifest would be left alone\n' \
        "$MANIFEST_BAK_REL"
    else
      printf '  Packages/manifest.json — add %s to "dependencies" (--with-mcp)\n' "$MCP_PKG_NAME"
    fi
  fi
  if [ "$WITH_INPUT_SYSTEM" -eq 1 ]; then
    if [ ! -f "$MANIFEST" ]; then
      printf '  Packages/manifest.json — none in this project, so --with-input-system would skip\n'
    elif [ "$HAS_INPUT_SYSTEM" -eq 1 ]; then
      printf '  Packages/manifest.json — %s already present, so --with-input-system would skip\n' \
        "$INPUT_SYSTEM_PKG_NAME"
    elif manifest_bak_is_foreign; then
      printf '  Packages/manifest.json — %s is not ours, so --with-input-system is declined and the manifest would be left alone\n' \
        "$MANIFEST_BAK_REL"
    else
      printf '  Packages/manifest.json — add %s to "dependencies" (--with-input-system)\n' \
        "$INPUT_SYSTEM_PKG_NAME"
    fi
  fi

  # OUTSIDE THE FLAGS, NOT JUST OUTSIDE THE BRANCHES — Step 8's receipt row already states this
  # placement rule in those words, and the announcement was never given the same treatment. On every
  # install after the first the user passes no --with-* flag, so the branch that MAKES this file
  # does not run, while the file sits on disk and the receipt goes on claiming it. An announcement
  # inside `if [ "$WITH_MCP" -eq 1 ]` is silent on exactly the path every user is on after install 1.
  #
  # TWO STATES, TWO VERDICTS, AND THEY ARE NOT INTERCHANGEABLE:
  #   this run would create it   → a PROMISE. The real run writes that path.
  #   an earlier run created it  → a DECLINE. This run re-claims it in the receipt and does not
  #                                touch a byte of it, so promising it would be an announcement with
  #                                no write — the other direction of the same defect.
  # `owned_by_installer` is the disjunct that can answer on a flagless run, and it is the same call
  # Step 8's row makes, with the same '' reference argument: this file is a copy of the user's own
  # manifest, so the toolkit ships no reference copy to compare it against.
  if manifest_bak_would_be_kept; then
    # THE ONE CONDITION THIS CANNOT EVALUATE IS NAMED RATHER THAN ASSUMED AWAY — see
    # manifest_bak_would_be_kept's fourth condition. "if the edit succeeds" is a smaller claim than
    # the run can break.
    printf '  %s — kept as the pre-edit backup if the edit succeeds, and recorded as ours to remove\n' \
      "$MANIFEST_BAK_REL"
  elif owned_by_installer "$MANIFEST_BAK_REL" ''; then
    printf '  %s — the backup an earlier run kept; still ours and still claimed, contents NOT touched\n' \
      "$MANIFEST_BAK_REL"
  fi
  [ -n "$BACKUP_DIR" ] && printf '  backup: %s\n' "$(basename "$BACKUP_DIR")"
  if [ ! -f "$PROJECT_DIR/.mcp.json" ]; then
    printf '  .mcp.json (new — UnityMCP -> http://localhost:8080/mcp)\n'
  elif grep -Eq '"(unityMCP|UnityMCP)"' "$PROJECT_DIR/.mcp.json" 2>/dev/null; then
    printf '  .mcp.json already has a unityMCP/UnityMCP entry — would leave alone\n'
  else
    printf '  .mcp.json exists without unityMCP/UnityMCP — would print the block, not rewrite\n'
  fi

  # Report the MCP-SETUP.md branch too, and for the reason directly above: Step 8c copies it into the
  # project root, records it in the receipt as toolkit-owned, and this block said nothing about it —
  # so the dry run silently under-described a write landing outside .claude/, where a user is least
  # expecting one. That step exists because the summary once pointed at a file the installer never
  # installed; the install half was fixed and the consent half was left open.
  #
  # The copy is conditional — it never overwrites an existing file — so an unconditional line here
  # would promise a file the real run skips: this block's own bug in mirror image. The condition is
  # the same one Step 8c tests, read against $PROJECT_DIR the way the CLAUDE.md branch above does
  # ($MCP_SETUP_MD is not defined until the real-run path, which we never reach here).
  #
  # The skip branch says "already exists", not "yours exists", and speaks only of *contents*. Both
  # narrowings are load-bearing, and the wording above earns neither:
  #   - This branch has no discriminator for who wrote the file. On a re-run the file present is the
  #     toolkit's, written by the previous run, so "yours" is false in the installer's own upgrade
  #     path. The CLAUDE.md branch may say "yours" because :274's marker test has already proved the
  #     file is not ours; .mcp.json, which has no such test either, correctly claims nothing.
  #   - "contents", because that is the whole of what this branch can vouch for. It cannot speak to
  #     ownership: Step 8c decides that by comparing the file on disk against the toolkit's copy and
  #     against the previous receipt's checksum, and doing either here would be a second copy of
  #     that decision living in the announcement — the drift this file has already paid for twice.
  #     (Until 2026-08-12 this bullet said ownership was unknowable because the row was written only
  #     on create, so an upgrade dropped it and uninstall.sh left the file behind. That defect is
  #     closed; see owned_by_installer. The line still does not reach into ownership, now because it
  #     should not rather than because it cannot.)
  if [ -f "$SCRIPT_DIR/MCP-SETUP.md" ]; then
    if [ ! -f "$PROJECT_DIR/MCP-SETUP.md" ]; then
      printf '  MCP-SETUP.md (new — the MCP bridge setup guide)\n'
    else
      printf '  MCP-SETUP.md already exists — its contents are NOT touched\n'
    fi
  fi
  printf '\nDry run complete — nothing written.\n'
  exit 0
fi

# ── Step 5: Install ──────────────────────────────────────────────────────────
if [ -n "$BACKUP_DIR" ]; then
  mv "$CLAUDE_DIR" "$BACKUP_DIR"
  ok "Backed up existing .claude/ → $(basename "$BACKUP_DIR")"
fi

WRITTEN=0; KEPT=0
RECEIPT_TMP=$(mktemp)
# The canonical .mcp.json, written once at Step 8b and read twice: the create branch copies it out,
# and owned_by_installer compares against it. A second copy of that JSON — one to write, one to
# compare — is a second definition that drifts, which is the failure this whole change is about.
# Created here, beside RECEIPT_TMP, so both are set before the trap that removes them.
MCP_JSON_REF=$(mktemp)
trap 'rm -f "$RECEIPT_TMP" "$MCP_JSON_REF"' EXIT

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  src="$SCRIPT_DIR/.claude/$rel"
  dest="$CLAUDE_DIR/$rel"
  if is_modified ".claude/$rel"; then
    KEPT=$((KEPT + 1))
    # Record the file as it now stands so the next run still recognises it.
    printf '.claude/%s\t%s\t%s\tuser-modified\n' "$rel" "$(sha_of "$dest")" "$(stat -c '%a' "$dest" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
    continue
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  WRITTEN=$((WRITTEN + 1))
  printf '.claude/%s\t%s\t%s\ttoolkit\n' "$rel" "$(sha_of "$dest")" "$(stat -c '%a' "$dest" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
done <<< "$PAYLOAD_FILES"

mkdir -p "$CLAUDE_DIR/state"
chmod +x "$CLAUDE_DIR/hooks/"*.sh 2>/dev/null || true

# The per-file provenance manifest is NOT shipped into user projects. It used to be, as
# .claude/provenance.tsv — 30 KB of maintenance evidence that nothing in a game project reads.
# Its actual job is to make a future ECU bump diffable rather than archaeological, and that bump
# happens in the kinglet-unity repository, not in the project the toolkit was installed into.
#
# It also rotted twice in two days once installed: the copy went stale the moment the toolkit's own
# manifest changed, and both times a reader believed it. A stale attribution manifest is worse than
# a link to a live one.
#
# The MIT obligation is unaffected and still met. The licence requires the copyright and permission
# notices to travel with the copies, which they do — .claude/NOTICE.md ships, carries both upstream
# licence texts in full, and points at the manifest in the repository for the per-file detail.

# Validation scripts ship alongside the payload. The test suite does not.
#
# check-provenance.sh was excluded first, with this reasoning: it validates the toolkit's own
# manifest, which is not shipped, so installing it would put a check in every project that can only
# ever report `err provenance.tsv not found` and exit 1 — and a permanently failing check trains
# people to ignore checks, which costs more than the script is worth.
#
# Measured 2026-08-04: that argument was applied to one script and not to the class it describes.
# Running the shipped suite in a real installed project gives **143 failures out of 229 assertions**,
# and it always has. Two independent causes:
#
#   1. run-tests.sh computes REPO_DIR as the parent of tests/. In this repository that is the repo
#      root; in an installed project it is `.claude/`, so every path is off by one level and the
#      tests look for `.claude/.claude/hooks/...`.
#   2. A large share of the test files reference install.sh, provenance.tsv, tests/fixtures/,
#      migration/baseline-inventory.json or tools.kinglet_build — none of which ship. Those cannot
#      pass in a project whatever REPO_DIR says.
#
#      Derive that share; do not trust a number written here. This sentence carried a hardcoded pair,
#      "twelve of the twenty-eight", and was wrong at both ends on both later measurements: 15 of 30
#      at 076464b and 16 of 31 on 2026-08-12. The set is the claim, so the commands are the claim:
#        grep -lE 'install\.sh|provenance\.tsv|tests/fixtures/|migration/baseline-inventory\.json|tools\.kinglet_build' tests/test-*.sh | wc -l
#        ls tests/test-*.sh | wc -l
#
# The suite validates the toolkit, not the project. What a user actually needs is
# scripts/studio-doctor.sh, which does ship, runs correctly against an installed layout, and checks
# the things that matter there: the install verified against its receipt, every hook named by
# settings.json present, the MCP bridge configured, the Input System package present.
#
# So: scripts/ ships, tests/ does not. An installed project that already has .claude/tests/ from an
# earlier version gets it removed by the payload-prune above, which is the behaviour that exists for
# exactly this.
# This loop is the payload loop's twin and must stay its twin. It did not: the payload loop tested
# is_modified before writing, and this one's `cp` was unconditional with a `toolkit` row regardless.
# So a user who edited .claude/scripts/studio-doctor.sh got, in ONE run:
#
#   warn 1 installed file(s) have local edits — keeping yours:
#          .claude/scripts/studio-doctor.sh
#   ok   Installed 85 file(s).
#
# and the edit was gone. MODIFIED_FILES is computed at Step 4, before either loop runs, so the
# warning was accurate about what the installer knew and false about what it then did — the one
# failure worse than silent data loss, because the user is told the file is safe in the same breath.
# Measured on a fixture 2026-08-12; tests/test-install-ownership.sh's state H holds all four
# directions of it, including the one that stops the fix becoming "keep everything".
#
# The path form is load-bearing and is not a coincidence: MODIFIED_FILES is built from receipt
# field 1, these rows are written as `.claude/scripts/<name>`, and is_modified matches whole lines
# (`grep -qxF`). Change either form and the test below silently never matches — a no-op that reads
# as a fix.
for group in scripts; do
  [ -d "$SCRIPT_DIR/$group" ] || continue
  mkdir -p "$CLAUDE_DIR/$group"
  for f in "$SCRIPT_DIR/$group"/*.sh; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    [ "$b" = "check-provenance.sh" ] && continue
    dest="$CLAUDE_DIR/$group/$b"
    if is_modified ".claude/$group/$b"; then
      # Kept, so counted as kept: WRITTEN and KEPT both appear in the summary line, and a kept file
      # counted as written is a write the run did not make. Recorded as the file now stands, so the
      # NEXT install still recognises it — the same reason the payload loop records the edited sha.
      KEPT=$((KEPT + 1))
      printf '.claude/%s/%s\t%s\t%s\tuser-modified\n' "$group" "$b" "$(sha_of "$dest")" "$(stat -c '%a' "$dest" 2>/dev/null || echo 755)" >> "$RECEIPT_TMP"
      continue
    fi
    cp "$f" "$dest"
    chmod +x "$dest"
    printf '.claude/%s/%s\t%s\t%s\ttoolkit\n' "$group" "$b" "$(sha_of "$dest")" "755" >> "$RECEIPT_TMP"
    WRITTEN=$((WRITTEN + 1))
  done
done

# Remove what the previous install owned and this payload dropped. Computed before any write, so a
# path this run creates can never appear here. Files the user edited were filtered out already.
REMOVED=0
if [ "$ORPHAN_COUNT" -gt 0 ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    rm -f "$PROJECT_DIR/$rel" && REMOVED=$((REMOVED + 1))
  done <<< "$ORPHANS"
  # Skill directories are one level deep, but not always a single file — subagent-driven-implementation
  # ships four sibling prompt templates alongside SKILL.md. Either way, once every file this run
  # tracked is gone the directory is an empty shell that still reads as a skill to anyone listing the
  # tree.
  find "$CLAUDE_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true
  ok "Removed $REMOVED file(s) no longer in the payload."
fi
if [ "$ORPHAN_KEPT_COUNT" -gt 0 ]; then
  warn "$ORPHAN_KEPT_COUNT file(s) dropped from the payload have your edits — left in place:"
  printf '%s' "$ORPHANS_KEPT" | while IFS= read -r o; do [ -n "$o" ] && printf '       %s\n' "$o"; done
fi

# A kept settings.json is the one file whose staleness is silent and total.
#
# settings.json is the most-edited file in the payload — it is where you disable a plugin or widen a
# permission — so on any real project it is "yours" and we keep it, correctly. But it is also the
# only place a hook is registered. A payload that ships a NEW hook therefore lands the script on disk
# and registers nothing: the hook never fires, and nothing reports that. Measured on a real project,
# where the hook carrying the whole process chain arrived unregistered and silent.
#
# Merging someone's JSON is not something an installer should do unasked, so this reports instead.
if is_modified ".claude/settings.json" && [ -f "$CLAUDE_DIR/settings.json" ]; then
  UNREG=""
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    grep -qF -- "$h" "$CLAUDE_DIR/settings.json" || UNREG="${UNREG}${h}"$'\n'
  done < <(grep -oE '\.claude/hooks/[a-z_-]+\.sh' "$SCRIPT_DIR/.claude/settings.json" | sort -u)
  UNREG_COUNT=$(printf '%s' "$UNREG" | grep -c . || true)
  if [ "$UNREG_COUNT" -gt 0 ]; then
    warn "Your settings.json was kept, so $UNREG_COUNT hook(s) this version ships are NOT registered:"
    printf '%s' "$UNREG" | while IFS= read -r h; do [ -n "$h" ] && printf '       %s\n' "$h"; done
    warn "They are on disk but will never fire. Add them to \"hooks\" in .claude/settings.json,"
    warn "or diff yours against $SCRIPT_DIR/.claude/settings.json."
  fi
fi

ok "Installed $WRITTEN file(s)$([ "$KEPT" -gt 0 ] && printf ', kept %s of yours' "$KEPT")."

# ── Step 6: CLAUDE.md ────────────────────────────────────────────────────────
# The installer owns the destination; the generator only writes to stdout. Upstream had both
# writing the same path, which corrupted fresh files and destroyed existing ones.
CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"

# ── Process provider — detect, propose, never assume ────────────────────────
# The platform design requires that Kinglet propose a detected provider and the
# user approve it, and that Kinglet never copy, disable, or shadow it. Detection
# is read-only and re-run on every install: if the provider is uninstalled later,
# the next refresh drops the sentence, which is the correct behaviour.
#
# What that reasoning did NOT cover: a refresh where nothing changed except the
# tty. PROVIDER_CHOICE was set only on the interactive branch, so `--yes` or a
# pipe took "the safe default (no declaration)" even for a provider that is still
# installed and that the user already approved. emit_provider_verdict lives inside
# the marked region, so the --facts-only refresh regenerated that region without
# the sentence and deleted it. studio-doctor.sh tells the user to "Re-run
# install.sh to refresh the declaration" — in CI or with --yes, that revoked it.
#
# So read the existing declaration first. Same parse shape as studio-doctor.sh's
# staleness check, deliberately: one grammar for one section, not two.
EXISTING_PROVIDER=""
if [ -f "$CLAUDE_MD" ] && grep -q '^### Process provider' "$CLAUDE_MD"; then
  EXISTING_PROVIDER=$(awk '/^### Process provider/{f=1} f && /owned by/{
      if (match($0, /`[^`]+`/)) print substr($0, RSTART+1, RLENGTH-2); exit }' "$CLAUDE_MD")
fi

if [ -f "$CLAUDE_USER_SETTINGS" ] \
   && grep -q '"superpowers@claude-plugins-official"[[:space:]]*:[[:space:]]*true' "$CLAUDE_USER_SETTINGS"; then
  if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
    if [ "$EXISTING_PROVIDER" = superpowers ]; then
      # Approved before, still installed, nothing to re-decide. Carrying it
      # forward is the conservative act here; dropping it is the change.
      PROVIDER_CHOICE="superpowers"
      info "Superpowers detected and already declared in CLAUDE.md — declaration carried forward."
    else
      # The safe default is no declaration: it changes nothing about how the
      # project behaves today.
      info "Superpowers detected; --yes takes the safe default (no provider declaration)."
    fi
  elif [ "$EXISTING_PROVIDER" = superpowers ]; then
    echo "  Superpowers is installed and this project already declares it as its"
    echo "  discovery and planning provider."
    read -rp "  Keep the declaration? [Y/n]: " REPLY_PROVIDER
    case "$REPLY_PROVIDER" in [nN]*) ;; *) PROVIDER_CHOICE="superpowers" ;; esac
  else
    echo "  Superpowers is installed for your user account."
    echo "  Kinglet can record it as this project's discovery and planning provider."
    echo "  This writes one sentence into CLAUDE.md. It does not modify Superpowers"
    echo "  or your global settings."
    read -rp "  Record it? [y/N]: " REPLY_PROVIDER
    case "$REPLY_PROVIDER" in [yY]*) PROVIDER_CHOICE="superpowers" ;; esac
  fi
fi

# Array, not the bare `${PROVIDER_CHOICE:+--provider "$PROVIDER_CHOICE"}` idiom: unquoted
# that is subject to word splitting, and under `set -u` in bash 3.2 an empty array needs
# the `+` guard below or expansion itself errors when PROVIDER_CHOICE was never set.
GEN_ARGS=()
[ -n "$PROVIDER_CHOICE" ] && GEN_ARGS+=(--provider "$PROVIDER_CHOICE")

GEN="$SCRIPT_DIR/scripts/generate-claude-md.sh"
# Tracks which branch below actually ran, so the "Next steps" summary can name the file it really
# touched instead of assuming CLAUDE.md was (re)written. See defect 9: the installer already knows
# this — it just wasn't asked.
CLAUDE_MD_BRANCH="skipped"
if [ -f "$GEN" ]; then
  TMP_MD=$(mktemp)
  if [ ! -f "$CLAUDE_MD" ]; then
    if bash "$GEN" ${GEN_ARGS[@]+"${GEN_ARGS[@]}"} "$PROJECT_DIR" > "$TMP_MD" 2>/dev/null; then
      mv "$TMP_MD" "$CLAUDE_MD"; ok "Generated CLAUDE.md"
      CLAUDE_MD_BRANCH="new"
    else
      rm -f "$TMP_MD"; warn "CLAUDE.md generation failed — skipped."
    fi
  elif grep -q 'kinglet:generated:begin' "$CLAUDE_MD"; then
    # Refresh only the fenced block; everything the user wrote stays byte-for-byte.
    if bash "$GEN" --facts-only ${GEN_ARGS[@]+"${GEN_ARGS[@]}"} "$PROJECT_DIR" > "$TMP_MD" 2>/dev/null; then
      # The generator owns every byte between the markers, heading included. This used to print the
      # "## Project Facts" heading here as well, from the era when --facts-only emitted only the
      # table. That was corrected in generate-claude-md.sh — on one side. The result was a second,
      # empty heading appearing on every refresh, compounding once per install; a real project was
      # found carrying two. Two producers for one region is the bug the generator's own comment
      # warns about, so this side prints nothing of its own.
      awk -v factsfile="$TMP_MD" '
        /kinglet:generated:begin/ { print; while ((getline l < factsfile) > 0) print l; skip=1; next }
        /kinglet:generated:end/   { print ""; print; skip=0; next }
        !skip { print }
      ' "$CLAUDE_MD" > "$TMP_MD.merged" && mv "$TMP_MD.merged" "$CLAUDE_MD"
      rm -f "$TMP_MD"
      ok "Refreshed the generated section of CLAUDE.md (your prose untouched)"
      CLAUDE_MD_BRANCH="refreshed"
    else
      rm -f "$TMP_MD"; warn "CLAUDE.md refresh failed — left as-is."
    fi
  else
    # ASK BEFORE WRITING. The `mv` below used to be unconditional, and this is the arm where that
    # cost the user work — twice over, on two different fixtures:
    #
    #   * The installer's own summary says "Fill in the FILL: markers in CLAUDE.md.generated". A user
    #     who does that and reinstalls got the nine unfilled markers back. The edit survived ZERO
    #     reinstalls, and once Task 2b gave the file a receipt row, run 2 printed
    #     `keeping yours: CLAUDE.md.generated` four lines before destroying it.
    #   * A user who wrote their own CLAUDE.md.generated and had never run this installer lost it on
    #     the first install ever — and the row below then recorded the replacement as `toolkit`, so
    #     uninstall.sh would take what was left.
    #
    # The condition is a disjunction, not `owned_by_installer` alone: that helper opens with
    # `[ -f "$abs" ] || return 1`, so on the ordinary case — nothing at that path yet — it correctly
    # answers "not ours" and a bare call would decline every fresh install. Absence is the case where
    # there is nothing to lose.
    #
    # `-e`, not `-f`: a directory or a symlink at that path is not ours to clobber either, and `mv`
    # onto a directory moves the file INSIDE it rather than replacing it.
    #
    # There is no reference copy to pass — this file is generated per project from that project's
    # Unity version, packages and provider — so the ref argument is '' and owned_by_installer's first
    # arm is skipped by construction. What answers is the previous receipt, and it is a checksum
    # comparison, so the file we wrote last run is ours and the same file after the user edits it is
    # not. See the row below for the rest of that reasoning.
    if [ -e "$PROJECT_DIR/CLAUDE.md.generated" ] && ! owned_by_installer 'CLAUDE.md.generated' ''; then
      rm -f "$TMP_MD"
      warn "CLAUDE.md.generated exists and is not ours — keeping yours, untouched."
      warn "No generated file was produced this run. Rename or delete CLAUDE.md.generated and"
      warn "re-run to get one."
      # NOT `separate`. That value is the row predicate's first disjunct, and setting it here would
      # write a receipt row claiming a file this branch just refused to write — the same defect
      # pointing the other way, with uninstall.sh deleting the user's file instead of the installer.
      # It also drives the Next-steps summary, which would otherwise send the user to FILL: markers
      # in a file that does not contain any.
      CLAUDE_MD_BRANCH="kept-yours"
    elif bash "$GEN" ${GEN_ARGS[@]+"${GEN_ARGS[@]}"} "$PROJECT_DIR" > "$TMP_MD" 2>/dev/null; then
      mv "$TMP_MD" "$PROJECT_DIR/CLAUDE.md.generated"
      warn "CLAUDE.md exists and has no generated markers — wrote CLAUDE.md.generated instead."
      warn "Yours was not touched. Merge by hand, or add the markers to let us refresh in place."
      CLAUDE_MD_BRANCH="separate"
    else
      rm -f "$TMP_MD"; warn "CLAUDE.md generation failed — skipped."
    fi
  fi
fi

# CLAUDE.md.generated is the second file this installer creates, keeps, announces — and, until
# 2026-08-13, never recorded. Same defect as Packages/manifest.json.bak one step earlier, on the
# project root where the user sees it: written by the `separate` branch above, pointed at by the
# "Next steps" summary, and absent from every receipt, so uninstall.sh — which removes only what the
# receipt lists — could never take it away. Permanent debris in exactly the projects that already had
# a CLAUDE.md of their own and where the installer politely declined to overwrite it.
#
# OUTSIDE THE BRANCH, for the reason the manifest-backup row is outside the flags. Exactly one of
# the block's arms writes this file, and a project leaves that arm for good the moment the user
# takes the block's own advice and adds the markers to their CLAUDE.md: every run from then on takes
# `refreshed`, the file run 1 wrote is still sitting on disk, and a row written where the file is
# created would vanish on run 2 and never come back.
#
# THERE IS NO REFERENCE COPY, so the ref argument is '' and owned_by_installer's first arm — compare
# against the toolkit's shipped copy — is skipped by construction. This file has no shipped copy: it
# is generated per project from that project's Unity version, packages and provider. What answers
# for it instead is the pair below, and both halves were measured on a fixture 2026-08-13:
#
#   `separate` — this run generated the file and moved it into place. The only thing that can speak
#                for install 1, where there is no previous receipt to consult (`arms=branch`).
#   the receipt — the only thing that can speak for a run that did not touch the file at all
#                (`arms=receipt` on a second install taking `refreshed`), and it is a checksum
#                comparison, so a CLAUDE.md.generated the user has since edited stops being ours and
#                is left alone (`arms=none`), exactly as an edited MCP-SETUP.md is.
#
# It fails closed on the case that matters: a CLAUDE.md.generated the user wrote satisfies neither
# half, gets no row, and uninstall.sh never touches it.
#
# Until 2026-08-13 that held only where the writing arm never ran — a project whose CLAUDE.md is
# absent or already carries the markers. Where it DID run, the `mv` had already replaced the user's
# file with our bytes before anything asked whose it was, and this row then correctly claimed a file
# that was byte-for-byte ours. The arm asks first now (see the disjunction above it), so the two
# halves below answer for a file that is still the one whose ownership is in question.
#
# The mode is read off the file rather than written down as 644: `mv` from mktemp carries 0600
# across, so this row records 600 where .mcp.json's records 644, and a hardcoded 644 here would be a
# receipt that disagrees with its own file. (Nothing reads the column today; that is not a reason to
# write something false into it.)
if [ "$CLAUDE_MD_BRANCH" = separate ] || owned_by_installer 'CLAUDE.md.generated' ''; then
  printf 'CLAUDE.md.generated\t%s\t%s\ttoolkit\n' \
    "$(sha_of "$PROJECT_DIR/CLAUDE.md.generated")" \
    "$(stat -c '%a' "$PROJECT_DIR/CLAUDE.md.generated" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
fi

# ── Step 7: .gitignore ───────────────────────────────────────────────────────
#
# The DECISION is `gitignore_plan`'s, made once in Step 3b and already announced by the dry run.
# What is left here is acting on it. `add_ignore`'s per-entry `grep -qxF` moved INTO the plan rather
# than staying here, because it was stage 2 of the decision rather than a detail of the write —
# leaving it here would have left the announcement free to disagree with the file, which is the
# whole of the defect this replaces.
GITIGNORE_PLAN="$(gitignore_plan)"
case "${GITIGNORE_PLAN%%$'\n'*}" in
  covered)
    ok ".gitignore already covers .claude/ local state — left alone." ;;
  present)
    # NOTHING IS WRITTEN ON THIS BRANCH, INCLUDING THE TRAILING NEWLINE. The previous shape reached
    # the `printf '\n'` below before discovering it had nothing to append, so a .gitignore that held
    # all four entries and did not end in a newline got one byte appended under the banner
    # "already has our entries" — a write announced as a no-change.
    ok ".gitignore already has our entries." ;;
  append)
    [ -f "$GITIGNORE" ] || { : > "$GITIGNORE"; info "Created .gitignore"; }
    # Only append a newline first if the file does not already end with one; otherwise our header
    # lands on the end of their last line.
    [ -s "$GITIGNORE" ] && [ -n "$(tail -c1 "$GITIGNORE")" ] && printf '\n' >> "$GITIGNORE"
    printf '\n# Claude Code local settings and session state\n' >> "$GITIGNORE"
    ADDED=0
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      printf '%s\n' "$e" >> "$GITIGNORE"
      ADDED=$((ADDED + 1))
    done <<< "${GITIGNORE_PLAN#*$'\n'}"
    ok "Updated .gitignore ($ADDED entries)" ;;
  *)
    warn "gitignore_plan returned an unrecognised verdict — .gitignore left alone." ;;
esac

# ── Step 8: Optional — manifest.json package additions ───────────────────────
# One helper for every "--with-X adds a package to Packages/manifest.json" flag, so --with-mcp and
# --with-input-system share the same surgical insert, the same backup behaviour, and the same
# "could not edit safely" fallback rather than two hand-maintained copies drifting apart.
#
# $MANIFEST_BAK_REL is defined in Step 3b, not here: the dry-run block announces this file and had
# to be able to name it. One definition, derived from $MANIFEST, so the receipt row, the
# announcement and the file they both name cannot disagree.
MANIFEST_BAK_KEPT=0
# Newline-terminated, one flag per line, in the idiom MODIFIED_FILES and ORPHANS already use here.
# Set unconditionally so the summary's `[ -n ... ]` test is not an unbound-variable death under
# `set -u` on the ordinary run that passes no --with-* flag at all.
MANIFEST_DECLINED=""
add_manifest_dependency() {
  local pkg_name="$1" pkg_value="$2" flag_name="$3"
  if [ ! -f "$MANIFEST" ]; then
    warn "No Packages/manifest.json — skipping $flag_name."
    return
  fi
  if grep -q "$pkg_name" "$MANIFEST"; then
    ok "$pkg_name already in manifest.json."
    return
  fi
  # ASK BEFORE WRITING, and decline THE EDIT — not just the backup. The `cp` below used to be
  # unconditional: --with-mcp on a project missing both packages keeps a backup, the user edits it,
  # and --with-input-system in a later run overwrote it while the same run printed
  # `keeping yours: Packages/manifest.json.bak`.
  #
  # THE ASYMMETRY WITH CLAUDE.md.generated IS DELIBERATE. There the installer keeps the user's file
  # and proceeds; here it abandons the flag. A backup exists to make a risky edit recoverable, so
  # making the edit while skipping the backup keeps the risk and drops the mitigation — and this
  # project is by definition not under git, which is the only reason the backup is kept at all, so
  # there is no second copy to fall back on. Writing the backup under another name was rejected: it
  # trades one destroyed file for unbounded debris, and each such file needs a receipt row of its own.
  #
  # THREE DISJUNCTS, and the middle one is this run's own knowledge. `owned_by_installer` consults
  # the PREVIOUS receipt, which cannot know about a backup THIS run just made — so on a single
  # `--with-mcp --with-input-system` run against a project missing both packages, the second caller
  # would find the first caller's backup, fail to recognise it, and decline. That is state J's shape,
  # and MANIFEST_BAK_KEPT is what the row below already uses to answer it.
  #
  # RETURNS ZERO, AND RECORDS THE DECLINE FOR THE SUMMARY. Two separate decisions; the second exists
  # because the first, alone, let a run end green about work it did not do.
  #
  # The status: the callers are `[ "$WITH_MCP" -eq 1 ] && add_manifest_dependency ...` — AND-lists in
  # which the function is the command after the final `&&`, so `set -e` DOES apply to it. Measured on
  # a scratch copy 2026-08-13: a `return 1` here exits the installer at the call site with status 1,
  # before Step 8b, Step 8c and Step 9 — so the project keeps 85 installed files and NO RECEIPT, and
  # uninstall.sh, which removes only receipt-listed paths, can then never clean any of it up. That is
  # a worse failure than the one this guard closes.
  #
  # This path is also a member of an existing family. Three other outcomes already mean "the flag did
  # not happen": no manifest, package already present, and `Could not edit manifest.json safely` —
  # which prints the same "add this under \"dependencies\" yourself" block this one does. All three
  # return zero and let the run exit zero, because install.sh's status answers "did the installation
  # happen", and it did: the payload is written, the receipt is written, uninstall.sh works. Making
  # one of four such outcomes non-zero would leave the status meaning different things on different
  # flag failures, which is a new inconsistency in place of the one being fixed.
  #
  # What the status genuinely cannot carry, the summary must. MANIFEST_DECLINED is global on purpose
  # — the function is called once per flag — and drives a `Not done:` block beside the green banner,
  # the same mechanism CLAUDE_MD_BRANCH uses one writer over: set where the decision is made, read
  # where the run speaks to the user. Without it the only trace of an abandoned flag was four warn
  # lines a dozen lines above `Installation complete.` and an exit status of 0.
  if [ -e "$MANIFEST.bak" ] && [ "$MANIFEST_BAK_KEPT" -ne 1 ] && ! owned_by_installer "$MANIFEST_BAK_REL" ''; then
    warn "$MANIFEST_BAK_REL exists and is not ours — declining $flag_name rather than overwriting it."
    warn "That file is the backup this edit needs to stay undoable. Move it aside and re-run with"
    warn "$flag_name, or add this under \"dependencies\" yourself:"
    warn "    \"$pkg_name\": \"$pkg_value\""
    MANIFEST_DECLINED="${MANIFEST_DECLINED}${flag_name}"$'\n'
    return 0
  fi
  # Surgical insert. The old installer round-tripped the JSON through a re-indenting dump, which
  # reformatted the user's whole manifest to add one line.
  cp "$MANIFEST" "$MANIFEST.bak"
  if sed -i.tmp "s|\"dependencies\"[[:space:]]*:[[:space:]]*{|\"dependencies\": {\n    \"$pkg_name\": \"$pkg_value\",|" "$MANIFEST" 2>/dev/null && grep -q "$pkg_name" "$MANIFEST"; then
    rm -f "$MANIFEST.tmp"
    # If git already tracks the manifest, git IS the backup — keeping a .bak just drops untracked
    # debris into someone's repo for no benefit.
    if git -C "$PROJECT_DIR" ls-files --error-unmatch Packages/manifest.json >/dev/null 2>&1; then
      rm -f "$MANIFEST.bak"
      ok "Added $pkg_name to manifest.json"
      # Naming only manifest.json here would be half the truth: the next time Unity opens the
      # project it resolves the package and writes packages-lock.json too, which is also tracked.
      # Reverting one and not the other leaves the lock referencing a package the manifest no
      # longer asks for.
      if git -C "$PROJECT_DIR" ls-files --error-unmatch Packages/packages-lock.json >/dev/null 2>&1; then
        info "To undo: git checkout Packages/manifest.json Packages/packages-lock.json"
        info "  (Unity writes the lock file when it next resolves packages.)"
      else
        info "To undo: git checkout Packages/manifest.json"
      fi
    else
      # KEPT, so ours. Recorded once, after both callers have run, rather than here: --with-mcp and
      # --with-input-system can both reach this line in one run, and the second `cp` above has
      # already overwritten the first's backup. Two rows for one path would then disagree on the
      # checksum, and uninstall.sh would report the stale one under "you modified" while removing
      # the file under the fresh one.
      MANIFEST_BAK_KEPT=1
      ok "Added $pkg_name to manifest.json (backup: manifest.json.bak)"
    fi
  else
    mv "$MANIFEST.bak" "$MANIFEST"; rm -f "$MANIFEST.tmp"
    warn "Could not edit manifest.json safely — add this under \"dependencies\" yourself:"
    warn "    \"$pkg_name\": \"$pkg_value\""
  fi
}

[ "$WITH_MCP" -eq 1 ] && add_manifest_dependency "$MCP_PKG_NAME" "$MCP_PKG_URL" "--with-mcp"
[ "$WITH_INPUT_SYSTEM" -eq 1 ] && add_manifest_dependency "$INPUT_SYSTEM_PKG_NAME" "$INPUT_SYSTEM_PKG_VERSION" "--with-input-system"

# A backup we keep is a file we own. Without this row uninstall.sh — which removes only what the
# receipt lists — could never take it away, so manifest.json.bak was permanent debris in exactly the
# projects least able to `git checkout` it back: the ones not under git, which is the only condition
# under which it is kept at all.
#
# OUTSIDE THE FLAGS, NOT JUST OUTSIDE THE BRANCHES, and for the reason owned_by_installer exists.
# `add_manifest_dependency` returns early once the package is already in the manifest, and a run
# passing no --with-* flag never calls it — so on every install after the first, the branch that
# makes the backup does not execute while the backup sits on disk untouched. A row written where the
# file is created vanishes on run 2 and the debris comes straight back. Measured on a fixture:
# --with-mcp, then a plain install, and the .bak is still there.
#
# Two disjuncts, and neither is redundant. The first is knowledge: this run made the copy and chose
# to keep it. The second is the previous receipt, which is the only thing that can answer for a file
# no branch in this run touched — and it is a checksum comparison, so a backup the user has since
# edited stops being ours and is left alone, exactly as an edited MCP-SETUP.md is.
#
# It fails closed on the case that matters: a Packages/manifest.json.bak the user wrote themselves
# satisfies neither disjunct, gets no row, and uninstall.sh never touches it. Until 2026-08-13 the
# `cp` above could still overwrite such a file before anything asked whose it was, at which point
# this row correctly claimed bytes that were ours; the helper asks first now and declines the flag
# outright, so the disjuncts below answer for the file whose ownership is actually in question.
if [ "$MANIFEST_BAK_KEPT" -eq 1 ] || owned_by_installer "$MANIFEST_BAK_REL" ''; then
  printf '%s\t%s\t%s\ttoolkit\n' \
    "$MANIFEST_BAK_REL" \
    "$(sha_of "$PROJECT_DIR/$MANIFEST_BAK_REL")" \
    "$(stat -c '%a' "$PROJECT_DIR/$MANIFEST_BAK_REL" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
fi

# ── Step 8b: .mcp.json — the file Claude Code actually reads MCP servers from ──
# Project-scoped MCP servers live in .mcp.json at the project root, not in .claude/settings.json.
# Claude Code silently ignores an mcpServers key there, so writing it was the whole defect: the
# unity-* agents had no tools to call. See MCP-SETUP.md for the approval step this still requires.
MCP_JSON="$PROJECT_DIR/.mcp.json"
cat > "$MCP_JSON_REF" <<'MCPJSON'
{
  "mcpServers": {
    "UnityMCP": {
      "type": "http",
      "url": "http://localhost:8080/mcp"
    }
  }
}
MCPJSON
if [ ! -f "$MCP_JSON" ]; then
  # `cat > ` rather than `cp`, so the file is created under the caller's umask the way the heredoc
  # that used to sit here did. `cp` would carry mktemp's 0600 across and contradict the 644 the
  # receipt row records.
  cat "$MCP_JSON_REF" > "$MCP_JSON"
  ok "Wrote .mcp.json (UnityMCP → http://localhost:8080/mcp)"
elif grep -Eq '"(unityMCP|UnityMCP)"' "$MCP_JSON" 2>/dev/null; then
  ok ".mcp.json already has a unityMCP/UnityMCP entry — left alone."
else
  warn ".mcp.json exists without a UnityMCP entry — not rewriting it. Add this under \"mcpServers\":"
  warn ''
  warn '    "UnityMCP": {'
  warn '      "type": "http",'
  warn '      "url": "http://localhost:8080/mcp"'
  warn '    }'
fi
# Outside the branches on purpose — see owned_by_installer. The "already has a UnityMCP entry" arm
# above is exactly where the two cases are indistinguishable by inspection: our own file from the
# previous run, and a user's file that happens to name the same server. Only the checksum tells
# them apart, so only the checksum decides.
if owned_by_installer '.mcp.json' "$MCP_JSON_REF"; then
  printf '.mcp.json\t%s\t644\ttoolkit\n' "$(sha_of "$MCP_JSON")" >> "$RECEIPT_TMP"
fi

# ── Step 8c: MCP-SETUP.md — the setup guide the "Next steps" summary points at ──
# It used to point a freshly installed project at MCP-SETUP.md while never installing it: the
# payload is .claude/** only, so the file was absent from every project this toolkit set up. Copied
# alongside CLAUDE.md (project root, never overwritten if the user already has one) so the pointer
# in the summary below actually resolves.
MCP_SETUP_MD="$PROJECT_DIR/MCP-SETUP.md"
if [ -f "$SCRIPT_DIR/MCP-SETUP.md" ] && [ ! -f "$MCP_SETUP_MD" ]; then
  cp "$SCRIPT_DIR/MCP-SETUP.md" "$MCP_SETUP_MD"
  ok "Installed MCP-SETUP.md"
fi
# Same shape as .mcp.json's row above, and for the same reason: the row states what we own at the
# end of the run, not what this run happened to write.
if owned_by_installer 'MCP-SETUP.md' "$SCRIPT_DIR/MCP-SETUP.md"; then
  printf 'MCP-SETUP.md\t%s\t644\ttoolkit\n' "$(sha_of "$MCP_SETUP_MD")" >> "$RECEIPT_TMP"
fi

# ── Step 9: Write the receipt ────────────────────────────────────────────────
{
  printf '# kinglet install receipt\n'
  printf '# edition: pioneer\n'
  printf '# Written by install.sh. uninstall.sh removes only what is listed here, and only if the\n'
  printf '# checksum still matches — so anything you edited or added is left alone.\n'
  printf '# toolkit-version: %s\n' "$TOOLKIT_VERSION"
  printf '# installed-at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ -n "$BACKUP_DIR" ] && printf '# backup-dir: %s\n' "$(basename "$BACKUP_DIR")"
  printf 'path\tsha256\tmode\torigin\n'
  sort -t$'\t' -k1,1 "$RECEIPT_TMP"
} > "$RECEIPT"
RECEIPT_ROWS=$(grep -vc '^#' "$RECEIPT" || true)
ok "Receipt written: $RECEIPT_REL ($((RECEIPT_ROWS - 1)) files)"

# ── Summary ──────────────────────────────────────────────────────────────────
# Counted, never hardcoded. Upstream's summary claimed 22 hooks / 22 commands / 41 skills while
# shipping 25 / 27 / 42, because the numbers were typed into an echo.
count_in() { find "$CLAUDE_DIR/$1" -name "$2" 2>/dev/null | wc -l | tr -d ' '; }
# Hooks are counted from settings.json, not from *.sh on disk: hooks/ also holds _lib.sh, a sourced
# library that is not itself a hook, so the file count and the hook count are never the same number.
count_hooks() { grep -oE '\.claude/hooks/[a-z_-]+\.sh' "$CLAUDE_DIR/settings.json" 2>/dev/null | sort -u | wc -l | tr -d ' '; }
printf '\n%s\n' "${BOLD}${GREEN}Installation complete.${NC}"
printf '  %sAgents%s    %s\n'   "$CYAN" "$NC" "$(count_in agents '*.md')"
printf '  %sCommands%s  %s\n'   "$CYAN" "$NC" "$(count_in commands '*.md')"
printf '  %sSkills%s    %s\n'   "$CYAN" "$NC" "$(count_in skills 'SKILL.md')"
printf '  %sHooks%s     %s\n'   "$CYAN" "$NC" "$(count_hooks)"
printf '  %sRules%s     %s\n'   "$CYAN" "$NC" "$(count_in rules '*.md')"
# The CLAUDE.md step names whichever file this run actually wrote to — not a fixed string. See
# defect 9: telling the user to edit CLAUDE.md in the run where CLAUDE.md.generated was written
# instead sends them to markers that live in a file the message never mentioned.
case "$CLAUDE_MD_BRANCH" in
  new)
    CLAUDE_MD_STEP='Fill in the FILL: markers in CLAUDE.md — genre, pillars, vision, scope.'
    ;;
  separate)
    CLAUDE_MD_STEP='Fill in the FILL: markers in CLAUDE.md.generated, then merge what you want into your own CLAUDE.md.'
    ;;
  refreshed)
    CLAUDE_MD_STEP='CLAUDE.md already had its generated section refreshed — your own prose was left untouched.'
    ;;
  # The decline. Sending the user to "the FILL: markers in CLAUDE.md.generated" here would point at a
  # file this run deliberately did not write, whose contents are the user's own and contain no
  # markers — defect 9's failure with the files swapped.
  kept-yours)
    CLAUDE_MD_STEP='Your own CLAUDE.md.generated was kept — no generated file was produced. Rename or delete it and re-run to get one.'
    ;;
  *)
    CLAUDE_MD_STEP='CLAUDE.md generation was skipped — see the warning above.'
    ;;
esac
# Work this run was asked for and did not do. `Installation complete.` is true — the payload landed,
# the receipt is written — but on its own it read as "everything you asked for happened", and a
# declined --with-* flag left no trace down here at all: four warn lines a dozen lines up, above the
# green banner, and an exit status of 0. This block is the manifest side of what the `kept-yours`
# arm below does for CLAUDE.md.generated, so the two writers' declines end the run the same way.
#
# `while read` over a here-string rather than a pipe: the loop drains its input, so there is no
# SIGPIPE hazard either way, but a here-string keeps the body out of a subshell. `if`, not
# `[ -n "$f" ] && printf`, because a false test as a loop body's last command is a `set -e` kill.
if [ -n "$MANIFEST_DECLINED" ]; then
  printf '\n%s\n' "${BOLD}${YELLOW}Not done:${NC}"
  while IFS= read -r f; do
    if [ -n "$f" ]; then
      printf '  %s — declined: %s is not ours to overwrite.\n' "$f" "$MANIFEST_BAK_REL"
    fi
  done <<< "$MANIFEST_DECLINED"
  printf '  Move that file aside and re-run with the flag, or add the package to\n'
  printf '  Packages/manifest.json by hand. The manifest was not edited.\n'
fi
cat <<EOF

Next steps:
  1. Install the Unity MCP bridge — see MCP-SETUP.md (Window > MCP for Unity > Auto-Setup).
  2. $CLAUDE_MD_STEP
  3. Run 'claude' in your project and try /unity-init, or /unity-doctor for a health check.
  4. Health check any time: ./.claude/scripts/studio-doctor.sh --project-dir "$PROJECT_DIR"
EOF
exit 0
