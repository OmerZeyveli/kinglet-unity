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
# .claude/state/install-receipt.tsv records every file the toolkit owns, with its checksum, so
# uninstall removes exactly what is ours and leaves everything else alone — files you edited, files
# you wrote, and a .gitignore you already had. One this installer CREATED is ours until you edit it.
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

# ── Work this run was asked for and did not do ───────────────────────────────
# ONE ACCUMULATOR, ONE EMITTER, AND THE REASON IS THAT MANY BRANCHES CAN ABANDON WORK AND EXACTLY
# ONE OF THEM USED TO REACH THE USER'S SUMMARY. `Installation complete.` and exit 0 are true
# of every one of them — the payload lands, the receipt is written — so the only trace of an
# abandoned --with-* flag, an ungenerated CLAUDE.md, an unwritten .gitignore or a hook that will
# never fire was a warn line up to five hundred lines above the green banner, in output nobody
# scrolls back through and no caller can act on. `MANIFEST_DECLINED` was this mechanism for one of
# them; this is the same mechanism with the rest routed through it.
#
# THERE ARE FEWER RECORDING POINTS THAN THERE ARE BRANCHES, and every collapse is one outcome reached
# more than one way: each `add_manifest_dependency` site fires for either --with-* flag, and
# CLAUDE.md's `skipped` is reached four ways that differ only in which warn line printed.
#
# NO COUNT IS WRITTEN HERE, and that is this comment's own rule applied to itself — the number went
# stale at the emitter within one round of being written down, in the file that forbids quoting it.
# Exclude comments when you derive it, or the derivation counts the very line you are reading. It
# did, for the length of one measurement:
#
#   awk '!/^[[:space:]]*#/ && /note_not_done "/ { n++ } END { print n + 0 }' install.sh
#
# THE CONTRACT THIS BLOCK MAKES GOOD ON IS WRITTEN DOWN, in MCP-SETUP.md § "What install.sh's exit
# status means" — the one document of the three candidates that installs into a project. It says
# exit 0 means the run reached its end and reported what it did, and that everything asked for and
# not done is listed HERE. A new abandonment site that only warns falsifies that sentence, so a new
# site is a `note_not_done` call and not just a `warn`.
#
# WHAT DOES NOT BELONG HERE: a file kept because YOU edited it. The payload landed, the file is on
# disk, and its contents are your own choice — that is the `keeping yours` report a few steps up,
# not work the installer abandoned. A keep enters this list only where it leaves a SECOND artifact
# absent or inert (a kept settings.json leaves this version's hooks on disk and unregistered) or
# where nobody chose anything (a receipt origin this installer cannot read).
#
# ONE LINE PER ENTRY. A site that needs a remedy sentence puts it on the same line: the block is read
# once, at the end of a run, by someone deciding what to do next, and an entry split across lines
# stops being countable by eye.
NOT_DONE=""
note_not_done() { NOT_DONE="${NOT_DONE}$1"$'\n'; }
# `if`, not `[ -n "$NOT_DONE" ] || return`: a false test as a function's last command is a `set -e`
# kill at the CALL SITE, and one of the two call sites is the abort path, where the run is supposed
# to end 0. `while read` over a here-string rather than a pipe — the loop drains its input either
# way, so there is no SIGPIPE hazard, but a here-string keeps the body out of a subshell.
#
# NOT REACHED ON A DRY RUN. Step 4's unreadable-origin scan runs before the `Would install:` block
# and can call note_not_done there, but that block exits 0 without calling this — deliberately: a
# dry run does not abandon work, it announces what a real run would do, and it has its own line for
# that same state. Nothing else accumulates before the dry-run exit.
print_not_done() {
  if [ -n "$NOT_DONE" ]; then
    printf '\n%s\n' "${BOLD}${YELLOW}Not done:${NC}"
    while IFS= read -r nd_line; do
      if [ -n "$nd_line" ]; then printf '  %s\n' "$nd_line"; fi
    done <<< "$NOT_DONE"
  fi
}

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
MANIFEST="$PROJECT_DIR/Packages/manifest.json"
# ONE detector, shared with scripts/generate-claude-md.sh. This block used to be two unconditional
# greps with HDRP last, so HDRP won; the generator used if/elif with URP first, so URP won. A
# project carrying both packages got HDRP here and URP in its own generated CLAUDE.md from a single
# install. See scripts/detect-pipeline.sh's header for what package presence can and cannot tell
# you — in particular that it does NOT read ProjectSettings/GraphicsSettings.asset, so none of these
# four answers is a statement about which pipeline is ACTIVE.
#
# install.sh runs BEFORE the payload is installed, so the detector is reached at $SCRIPT_DIR/scripts/
# and never at $PROJECT_DIR/.claude/scripts/. `bash "$path"`, matching how $GEN is invoked further
# down, so a lost exec bit in a checkout cannot break it.
#
# `|| die`, not a bare RENDER_PIPELINE_ID="$(...)": under `set -e` a bare assignment from a failing
# command substitution kills the installer with NO message. The status lands here at Step 2 — after
# the Unity-project gate and before anything is written or backed up — so a failure exits with the
# project untouched and no receipt to reconcile. Measured on a mutated copy, not reasoned about.
RENDER_PIPELINE_ID="$(bash "$SCRIPT_DIR/scripts/detect-pipeline.sh" "$PROJECT_DIR")" \
  || die "Render-pipeline detection failed — $SCRIPT_DIR/scripts/detect-pipeline.sh did not run."
case "$RENDER_PIPELINE_ID" in
  builtin)  RENDER_PIPELINE="Built-in" ;;
  urp)      RENDER_PIPELINE="URP" ;;
  hdrp)     RENDER_PIPELINE="HDRP" ;;
  # Named as its own state rather than silently picking a winner — which is the whole defect this
  # shared detector closes. The parenthetical is not decoration: the manifest cannot say which of
  # the two renders, and a confident "URP" here would be the wrong answer half the time.
  urp+hdrp) RENDER_PIPELINE="URP + HDRP (both packages present — active pipeline undetermined)" ;;
  # Unreachable while the detector emits the four tokens above. It reports the token instead of
  # defaulting to "Built-in", because a confident wrong answer is the failure mode this whole block
  # exists to remove.
  *)        RENDER_PIPELINE="undetermined (detector said '$RENDER_PIPELINE_ID')" ;;
esac
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
      # THE MOST COMPLETE ABANDONMENT THIS SCRIPT HAS, AND IT EXITED 0 WITH ONE WORD OF PROSE.
      # Nothing is installed, no receipt is written, and `install.sh --yes && start_unity` proceeds
      # as though a toolkit were there. The status stays 0 — it is the user's own answer to a
      # question this run asked, not a failure — so the block is what carries it, and this is the
      # only site that emits the block anywhere but the summary. It is also the only site the guard
      # in tests/test-install-not-done.sh cannot reach: the prompt above is skipped entirely unless
      # stdin is a tty, so reaching this arm needs a pty rather than a fixture.
      *) info "Aborted."
         note_not_done "the whole installation — you chose to abort at the existing $CLAUDE_DIR prompt, so nothing was written and no receipt exists."
         print_not_done
         exit 0 ;;
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
  # THE ORIGIN COLUMN IS TRIMMED BEFORE IT IS COMPARED, and the trim is not cosmetic. `$4 ==
  # "toolkit"` is byte equality, so a row carrying one trailing space — or a CRLF line ending, which
  # puts a \r in field 4 of the last column — is not `toolkit` and the file is not re-claimed. It is
  # then never claimed again by any later run either, because every run reads the receipt it wrote
  # last time: uninstall.sh removes only listed paths, so the file is permanent debris. That costs a
  # root file its ownership FOREVER on a byte a user cannot see.
  #
  # THE OTHER DIRECTION IS THE ONE THAT MUST NOT MOVE, and trimming is what keeps it still. A
  # mangled `user-modified ` trims to `user-modified`, which is still not `toolkit`, so it is still
  # not claimed and uninstall.sh still leaves the user's file alone — the direction G.5 in
  # tests/test-install-ownership.sh holds for the classifier, held here for the writer. Anything
  # that is neither value after trimming — an empty column, a fifth value, a truncated row — is
  # still not claimed. Unknown provenance is not ours, and the cost of that is a file left on disk,
  # which the user can delete; the cost of the other answer is a file deleted, which they cannot
  # undelete. States N and N2 assert both directions across an upgrade, which is the only shape
  # where this awk is the whole decision (the reference-copy arm above answers otherwise).
  #
  # WHICH READERS OF THIS COLUMN TRIM, AND WHICH DO NOT. There are four, and the sentence above is
  # about ONE of them, so it is stated here for the column rather than left to be read off whichever
  # reader you happened to open. This paragraph shipped for one round saying "a CRLF line ending" is
  # handled without saying handled BY WHOM, and the next three tasks to open this file would have
  # read it as a property of the receipt format:
  #
  #   install.sh, this awk                       — TRIMS. Deciding whether to re-claim a file.
  #   install.sh, the MODIFIED_FILES loop below  — TRIMS. Deciding whether to overwrite the user's
  #                                                edit. This is the reader where being wrong costs
  #                                                work that cannot be recovered, and it was the
  #                                                untrimmed one until 2026-08-14: `user-modified `,
  #                                                ` user-modified` and a CRLF receipt each silently
  #                                                destroyed the edit and rewrote the row `toolkit`.
  #   uninstall.sh's classifier                  — DOES NOT TRIM. It is fail-closed by a different
  #                                                mechanism: a `case` whose `*)` keeps the file. So
  #                                                a mangled `user-modified` is safe there, but a
  #                                                mangled `toolkit ` on an UNEDITED file is
  #                                                classified as yours and never removed — this
  #                                                defect's mirror image, unfixed, on that side.
  #   scripts/studio-doctor.sh                   — DOES NOT TRIM. Same `case` shape; reports an
  #                                                unreadable origin on its own line rather than
  #                                                counting it verified. Diagnostic only, writes
  #                                                nothing, so it cannot destroy anything. Its
  #                                                `user-modified` arm now makes the same
  #                                                reference-copy comparison the MODIFIED_FILES loop
  #                                                below does, so the two cannot disagree about
  #                                                whether a file has been put back — but only when
  #                                                --toolkit-dir gives it a checkout to compare
  #                                                against, which an installed project has not got.
  #
  # Keep this list in step with the file if you add a reader, and do not shorten it to "the origin
  # column is trimmed" — that sentence is true of two readers and false of four.
  awk -F'\t' -v want="$rel" -v have="$have" '
    $1 == want && $2 == have {
      origin = $4
      sub(/^[[:space:]]+/, "", origin)
      sub(/[[:space:]]+$/, "", origin)
      if (origin == "toolkit") { found = 1 }
    }
    END { exit !found }' "$RECEIPT"
}

# On upgrade, find files the user edited so we can leave them alone.
#
# THREE LISTS, AND THE SPLIT IS NOT COSMETIC. `MODIFIED_FILES` is the UNION and it is what
# `is_modified` reads, so every path this run declines to overwrite has to be in it. `EDITED_FILES`
# and `UNREADABLE_ORIGINS` partition that union by WHY, and they are what the run PRINTS.
#
# One list for both was wrong in the direction that matters: an unedited payload file whose receipt
# row carries an unreadable origin was reported under `installed file(s) have local edits — keeping
# yours` and named again two lines later under the unreadable block. Printed twice, counted once in
# a number describing two different situations, and `have local edits` is simply false about a file
# nobody edited. Measured 2026-08-14 on a --variant urp fixture with an unedited
# .claude/rules/pc-console.md and its origin column mangled to `toolkit<TAB>deadbeef`.
#
# The comment below this one already argued that "kept-because-yours and kept-because-unreadable are
# different futures, and a single count would describe neither" — and then the count described both.
#
# A FOURTH LIST, AND IT IS A SUBTRACTION FROM THE UNION RATHER THAN A PARTITION OF IT.
# `RECLAIMED_FILES` names files whose row says `user-modified` and whose bytes are now byte-for-byte
# the copy this toolkit ships — the user put the file back. They are deliberately NOT in
# MODIFIED_FILES: the whole point is that the payload loop writes them again and records them
# `toolkit`, so the sticky flag stops surviving its own reason. See the arm below.
MODIFIED_FILES=""
EDITED_FILES=""
UNREADABLE_ORIGINS=""
RECLAIMED_FILES=""
if [ "$MODE" = ours ]; then
  while IFS=$'\t' read -r rel recorded _mode origin; do
    case "$rel" in ''|\#*) continue ;; esac
    [ -f "$PROJECT_DIR/$rel" ] || continue
    # `user-modified` is sticky. When a previous run kept your edit, it recorded the file as it then
    # stood — so on the next run the checksum matches the receipt and a sha-only test concludes the
    # file is untouched and overwrites it. Your edit survived exactly one upgrade and then vanished,
    # silently. Measured twice on the same file in one day. The origin column was already written
    # for this; it was just never read.
    #
    # TRIMMED, AND THIS IS THE READER WHERE GETTING IT WRONG COSTS THE USER'S WORK. `[ "$origin" =
    # user-modified ]` is byte equality, and everything that reaches it has already survived a `read`
    # that strips only IFS whitespace — which here is the TAB, not the space. So a receipt whose
    # origin column carries one trailing space, or one leading space, or a `\r` from a Windows editor
    # saving the file with CRLF endings, is not `user-modified` to that test. Measured 2026-08-14 on
    # a --variant urp fixture, install → edit .claude/rules/pc-console.md → install: with any of
    # those three bytes present the edit is GONE, no `keeping yours` line is printed, and the row is
    # rewritten as a clean `toolkit`. The one shape that already survived is a LEADING TAB, and it
    # survived by accident rather than by care — `read` strips it as IFS whitespace before this test
    # ever sees it. All four are asserted in tests/test-install-ownership.sh's state P.
    #
    # THE TRIM IS NARROW ON PURPOSE: surrounding whitespace only, then exact equality. It must not
    # become a prefix or substring match. A row carrying a genuine fifth column reaches this loop as
    # `user-modified<TAB>deadbeef` — the tab is INTERNAL, so `read` does not strip it — and that is a
    # row whose provenance we cannot read, not a `user-modified` row with decoration. State P4
    # asserts it takes the `*)` branch below and not this one.
    #
    # Pure parameter expansion rather than a `sed`/`tr` per row: this loop runs once per receipt row,
    # and bash 3.2 has to parse it, so no `${x//…}` with a class and no `$'…'` inside the pattern.
    origin_clean="${origin#"${origin%%[![:space:]]*}"}"
    origin_clean="${origin_clean%"${origin_clean##*[![:space:]]}"}"
    # A `case` with an explicit catch-all, which is the grammar uninstall.sh's classifier and
    # scripts/studio-doctor.sh both already use. The if/else this replaces let anything unrecognised
    # fall THROUGH to the sha test, and on a mangled row the sha still matches — the row records the
    # edited file — so the fall-through concluded "untouched" and the payload loop overwrote it. A
    # file whose provenance we cannot read is not ours to overwrite, so it is kept and SAID ALOUD on
    # its own line: kept-because-yours and kept-because-unreadable are different futures, and a
    # single count would describe neither.
    case "$origin_clean" in
      user-modified)
        # STICKY UNTIL THE BYTES COME BACK — AND THE COMPARISON IS AGAINST THE TOOLKIT'S COPY, NOT
        # THE RECORDED SHA. Once a run keeps your edit it records the file AS EDITED, and the arm
        # above reads that row on every later run. Nothing ever took the flag off, so reverting the
        # file — `git checkout`, an undo, pasting the shipped text back — left it permanently yours:
        # measured 2026-08-14 on a --variant urp fixture, install → edit → install → revert to the
        # toolkit's exact bytes → install, and the run still printed `1 installed file(s) have local
        # edits — keeping yours` about a file with no local edits, rewriting the row `user-modified`
        # with the TOOLKIT'S OWN checksum in it. The cost is not the wrong sentence: this version's
        # copy of that file never lands again, so every later fix to it silently skips the project.
        # A second fixture that never touched the file received the bump in the same run.
        #
        # THIS IS NOT THE COMPARISON THAT FAILED IN c2d27f1f. That one tested the file against its
        # RECORDED sha, which for a `user-modified` row is the sha of the edited file — so it matched
        # while the edit was still in place, concluded "untouched", and the payload loop destroyed
        # the edit on the next run. An EDITED file never equals the toolkit's bytes, so the test here
        # cannot answer yes while the work is still there. The two directions are asserted together
        # in tests/test-install-ownership.sh's states R…R3, and the second is the regression check:
        # edit, then three consecutive installs, and the edit survives all three.
        #
        # WHICH FILES HAVE A REFERENCE COPY, AND WHY THE MAPPING IS TWO ARMS AND NOT ONE. Step 5's
        # payload loop takes `.claude/<rel>` from `$SCRIPT_DIR/.claude/<rel>`; the scripts loop takes
        # `.claude/scripts/<name>` from the repo-root `$SCRIPT_DIR/scripts/<name>`, because there is
        # no `.claude/scripts/` in this repository at all. Collapsing them to one arm makes every
        # scripts row look referenceless and the flag stays stuck there for a reason that reads as
        # deliberate.
        #
        # EVERYTHING ELSE KEEPS THE FLAG, and that is the fail-closed direction. A row with no
        # reference copy on disk — a retired surface this payload no longer ships, or a project-root
        # path — cannot be proved reverted, so it is not. Note that no writer in this file emits a
        # `user-modified` row for a project-root path (.mcp.json, MCP-SETUP.md, CLAUDE.md.generated,
        # .gitignore and the manifest backup are all written `toolkit` or not at all), so the only
        # way one reaches this arm is a hand-edited receipt — where declining to act is the whole
        # policy. MCP-SETUP.md does ship a static copy at $SCRIPT_DIR/MCP-SETUP.md and is still not
        # given a reference here: adding one would be a behaviour with no producer.
        ref=''
        case "$rel" in
          .claude/scripts/*) ref="$SCRIPT_DIR/scripts/${rel#.claude/scripts/}" ;;
          .claude/*)         ref="$SCRIPT_DIR/.claude/${rel#.claude/}" ;;
        esac
        if [ -n "$ref" ] && [ -f "$ref" ] \
           && [ "$(sha_of "$PROJECT_DIR/$rel")" = "$(sha_of "$ref")" ]; then
          RECLAIMED_FILES="${RECLAIMED_FILES}${rel}"$'\n'
          continue
        fi
        MODIFIED_FILES="${MODIFIED_FILES}${rel}"$'\n'
        EDITED_FILES="${EDITED_FILES}${rel}"$'\n'
        continue
        ;;
      toolkit)
        ;;
      *)
        UNREADABLE_ORIGINS="${UNREADABLE_ORIGINS}${rel}"$'\n'
        MODIFIED_FILES="${MODIFIED_FILES}${rel}"$'\n'
        continue
        ;;
    esac
    actual=$(sha_of "$PROJECT_DIR/$rel")
    if [ "$actual" != "$recorded" ]; then
      MODIFIED_FILES="${MODIFIED_FILES}${rel}"$'\n'
      EDITED_FILES="${EDITED_FILES}${rel}"$'\n'
    fi
  done < <(grep -v '^#' "$RECEIPT" 2>/dev/null | tail -n +2 || true)
  # EDITED_FILES, not MODIFIED_FILES — see the three-list note above. `have local edits` has to be
  # true of every path under it.
  MOD_COUNT=$(printf '%s' "$EDITED_FILES" | grep -c . || true)
  if [ "$MOD_COUNT" -gt 0 ]; then
    warn "$MOD_COUNT installed file(s) have local edits — keeping yours:"
    printf '%s' "$EDITED_FILES" | while IFS= read -r m; do [ -n "$m" ] && printf '       %s\n' "$m"; done
  fi
  # SAID ALOUD, because the previous run said the opposite about the same file. A user who has seen
  # `keeping yours: .claude/rules/pc-console.md` on every install since they edited it, and who then
  # put the file back, is owed the sentence that closes that thread — otherwise the line simply stops
  # appearing and the kept-count silently drops by one. `info`, not `warn`: nothing here needs
  # attention and nothing was abandoned, so this is deliberately NOT a `note_not_done` entry either
  # (see that block's "what does not belong here").
  RECLAIMED_COUNT=$(printf '%s' "$RECLAIMED_FILES" | grep -c . || true)
  if [ "$RECLAIMED_COUNT" -gt 0 ]; then
    info "$RECLAIMED_COUNT file(s) you had edited are back to this version's bytes — no longer kept as yours:"
    printf '%s' "$RECLAIMED_FILES" | while IFS= read -r r; do
      if [ -n "$r" ]; then printf '       %s\n' "$r"; fi
    done
    info "This version's copies land again, and future updates to them will reach this project."
  fi
  # `if`, not `[ -n "$u" ] && printf`, inside the loop body: a false test as a loop body's last
  # command is a `set -e` kill, and this block is new enough not to inherit the older idiom's luck.
  UNREADABLE_COUNT=$(printf '%s' "$UNREADABLE_ORIGINS" | grep -c . || true)
  if [ "$UNREADABLE_COUNT" -gt 0 ]; then
    warn "$UNREADABLE_COUNT receipt row(s) carry an origin this installer cannot read — keeping those files:"
    printf '%s' "$UNREADABLE_ORIGINS" | while IFS= read -r u; do
      if [ -n "$u" ]; then printf '       %s\n' "$u"; fi
    done
    # THIS SENTENCE USED TO END `so they are neither replaced nor claimed`, AND THE SECOND HALF WAS
    # FALSE. The file is kept, which puts it in MODIFIED_FILES, which sends the payload loop down its
    # `user-modified` arm — and that arm writes a receipt row. This file's own header says what such a
    # row means: "a `user-modified` row is still a claim of ownership, and `--purge` acts on every
    # claim." Measured 2026-08-14: after the run printed `nor claimed`, `uninstall.sh --yes --purge`
    # REMOVED the file. A sentence that tells the user a file is unclaimed, immediately before
    # claiming it, is the false-reassurance half of a defect rather than a report of one.
    #
    # WRITING NO ROW AT ALL WAS THE OTHER CANDIDATE AND IT IS MEASURABLY WORSE. A kept file with no
    # row is invisible to the NEXT run's loop above — nothing puts it in MODIFIED_FILES, so the
    # payload loop overwrites it. Measured on the same fixture by deleting the row and re-running:
    # the file was replaced, with no `keeping yours` line and no unreadable-origin line. That is the
    # data-loss path this task closed, delayed by one run and made silent. So the row stays and the
    # sentence changes.
    #
    # THE TEST THE WORDING HAS TO PASS is whether a reader who has just read it predicts what
    # `--purge` does. Both halves are therefore stated, and both are asserted in state Q.
    warn "Their provenance cannot be established, so they are kept rather than replaced — and"
    warn "recorded as yours. Plain 'uninstall.sh' will leave them; 'uninstall.sh --purge' removes them."
    # IN THE BLOCK, WHERE `keeping yours` DELIBERATELY IS NOT. The distinction is who decided: an
    # edited file is kept because the user edited it, and the file on disk is the one they want. Here
    # nobody decided anything — the origin column is unreadable — so what is on disk may be this
    # version's copy or a stale one, and the run cannot say which. That is the installer failing to
    # deliver a payload file, not honouring a choice.
    note_not_done "$UNREADABLE_COUNT installed file(s) listed above were NOT replaced with this version's copies — their receipt origin cannot be read, so they were kept and recorded as yours. Fix the origin column in $RECEIPT_REL, or delete those rows and re-install, to get this version's copies."
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

# ── The CLAUDE.md marker-pair decision ───────────────────────────────────────
# WHICH CLAUDE.md BRANCH A RUN TAKES USED TO BE `grep -q kinglet:generated:begin`, IN TWO PLACES —
# the dry run's announcement and Step 6's write — and both asked only whether the OPENING marker
# exists. A file carrying a begin and no end satisfied that test, so the refresh arm ran its awk
# merge against a region it could not close.
#
# What that costs is not a warning. The merge sets `skip` at the begin line and clears it ONLY at
# the end line, so with no end line every remaining line of the user's file is dropped — and the
# result is begin-only, so the NEXT run amputates the (now shorter) file again and reports success
# again. Measured on a urp fixture at this commit: 122 lines / 4839 bytes -> 80 lines / 2746 bytes,
# destroying five of the user's own sections, and byte-identical over runs 2, 3 and 4. The run
# printed `ok Refreshed the generated section of CLAUDE.md (your prose untouched)`, which is the
# half a user actually reads.
#
# The end-before-begin file is the same defect with a different silhouette and it is the reason the
# fix is not "clear skip at EOF": there the merge clears `skip` at the end marker, prints the OLD
# region as if it were prose, then sets `skip` at the begin marker and drops everything after it.
# Measured on the same fixture: 123 lines / 4870 bytes -> 134 lines / 4385 bytes. It GREW by eleven
# lines while losing four of the user's sections, which is why nothing here measures damage by size.
#
# SO THE PREDICATE ANSWERS FOR THE PAIR, NOT FOR THE OPENING MARKER, and a pair this function cannot
# certify is one the installer declines to merge — the same posture it already takes toward a file
# it does not own. Repair is deliberately not attempted: a file whose structure we cannot parse is a
# file whose region boundary we would be guessing at, and the guess is applied to the user's prose.
#
# EXACTLY ONE OF EACH, IN ORDER. Two begin markers is not a harmless duplicate: the merge dumps the
# facts block at each one and drops everything between the second and the next end. Fail closed.
#
# `awk` over the file, not `grep | ...`: nothing here may pipe into a reader that can exit early.
#
# IT ALWAYS EXITS 0 AND ALWAYS PRINTS A TOKEN. This comment claimed for one round that without the
# `-r` guard an unreadable CLAUDE.md would kill the run at `X="$(claude_md_marker_state …)"`, after
# the payload had landed, leaving the trap to write an INCOMPLETE receipt. THAT IS FALSE, AND IT WAS
# FALSE FOR TWO INDEPENDENT REASONS, BOTH MEASURED against a `chmod 000` CLAUDE.md with the guard and
# the `|| out=""` fallback both removed: rc **0**, the run completed, the receipt was written, and it
# still declined — via the generic `do not form exactly one begin/end pair` message, because the
# empty token satisfies the `!= none` test at the call site.
#
#   * `printf` is this function's LAST command, so the function's status is printf's, whatever awk
#     did before it; and
#   * bash CLEARS `-e` in the subshell it spawns for a command substitution unless `inherit_errexit`
#     is on, so the failing assignment inside this function would not have ended the function even
#     if printf were not last. Derive that this file sets no such option with the comments EXCLUDED —
#     `awk '!/^[[:space:]]*#/ && /shopt/' install.sh` — because the naive `grep -n shopt` now matches
#     the two lines you are reading and answers its own question wrongly.
#
# THE DEATH IS REAL IN EXACTLY TWO SHAPES, and they are worth naming because either could arrive by
# an edit that looks like tidying. Both measured, rc=2, against the same chmod 000 fixture: a rewrite
# that makes the failing ASSIGNMENT the function's last command (drop the trailing `printf` and let
# `out=` fall out of the end), and this exact printf-last shape under `shopt -s inherit_errexit`.
#
# So the guard stays for what it actually buys, which is not survival: the correct `it exists but
# could not be read` / `Make CLAUDE.md readable` pair instead of a marker diagnosis about a file
# nobody could open, and immunity to the second shape above if this file ever gains inherit_errexit.
# `unreadable` is a real state, not a fallback: it declines, like every other state this function
# cannot certify.
claude_md_marker_state() {
  local out
  [ -f "$1" ] || { printf 'absent\n'; return 0; }
  [ -r "$1" ] || { printf 'unreadable\n'; return 0; }
  out="$(awk '
    /kinglet:generated:begin/ { b++; if (bl == 0) bl = NR }
    /kinglet:generated:end/   { e++; if (el == 0) el = NR }
    END {
      if (b + 0 == 0 && e + 0 == 0)                    { print "none" }
      else if (b + 0 == 1 && e + 0 == 1 && bl < el)    { print "wellformed" }
      else if (e + 0 == 0)                             { print "malformed-no-end" }
      else if (b + 0 == 0)                             { print "malformed-no-begin" }
      else if (b + 0 == 1 && e + 0 == 1 && bl == el)   { print "malformed-same-line" }
      else if (b + 0 == 1 && e + 0 == 1)               { print "malformed-order" }
      else                                             { print "malformed-count" }
    }
  ' "$1" 2>/dev/null)" || out=""
  [ -n "$out" ] || out="unreadable"
  printf '%s\n' "$out"
}

# The user-facing half, kept beside the predicate so a new state cannot get a token and no sentence.
# One clause, no trailing punctuation: all three call sites embed it mid-sentence.
#
# `malformed-same-line` HAS ITS OWN TOKEN BECAUSE IT HAD THE WRONG SENTENCE. One line carrying both
# markers fails `bl < el` and used to fall through to `malformed-order`, which told the user their
# end marker came before their begin marker — a statement about ordering that is not true of a single
# line, on a file where the remedy sentence was nevertheless right. The action was never in question;
# the diagnosis was, and a diagnosis a reader can check against their own file is the point of having
# one at all.
claude_md_marker_problem() {
  case "$1" in
    malformed-no-end)     printf 'its kinglet:generated:begin marker has no closing :end marker' ;;
    malformed-no-begin)   printf 'its kinglet:generated:end marker has no opening :begin marker' ;;
    malformed-same-line)  printf 'its kinglet:generated:begin and :end markers are on the same line' ;;
    malformed-order)      printf 'its kinglet:generated:end marker comes before its :begin marker' ;;
    unreadable)           printf 'it exists but could not be read' ;;
    *)                    printf 'its kinglet:generated markers do not form exactly one begin/end pair' ;;
  esac
}

# And the remedy, which is NOT the same sentence for every declined state — "repair the marker pair"
# is wrong advice for a file the installer could not open. A whole sentence, naming the file: the
# `Next steps` summary embeds it with no context around it.
claude_md_marker_remedy() {
  case "$1" in
    unreadable) printf 'Make CLAUDE.md readable and re-run install.sh.' ;;
    *)          printf 'Repair the kinglet:generated marker pair in CLAUDE.md — one :begin line, one :end line after it — then re-run install.sh.' ;;
  esac
}

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
#
# THE PLAN IS COMPUTED TWICE — once by the dry-run block, once by Step 7 — AND THE TWO AGREE ONLY
# BECAUSE NOTHING BETWEEN THEM TOUCHES ITS INPUTS. Those inputs are exactly two: the contents of
# $GITIGNORE, and git's ignore rules for $PROJECT_DIR. Steps 4–6 write only under $CLAUDE_DIR, plus
# CLAUDE.md and CLAUDE.md.generated at the root, and install.sh runs no git command that mutates an
# index or a config. True at the time of writing and asserted NOWHERE — if a future step gains a
# write to .gitignore, or runs `git add`/`git config` on the project, Step 7's recomputation will
# silently disagree with what the dry run already announced. The fix then is to call gitignore_plan
# ONCE, here, and pass the result down; it is two calls today only because the dry run exits before
# Step 7 ever runs and a single call would be dead weight on that path.
#
# A NEWLINE HELD IN A VARIABLE, so no `$'…'` appears inside a parameter-expansion pattern below.
# bash 3.2's parser cannot be exercised from this host, a planned macOS pass has to survive it, and
# `"$NL"` inside the pattern is unambiguous in every bash. Cheap insurance.
#
# THIS COMMENT USED TO CITE scripts/studio-doctor.sh AS PRECEDENT for `${VAR%%$'\n'*}` — "it uses it
# twice" — and read as though the spelling were inherited and only this file were opting out. It was
# not inherited. Both of that file's sites were written by 6a2793e on 2026-08-12, and this comment by
# 82dc293 the next morning, so the precedent cited was thirteen hours old and the wave's own. There is
# no such precedent now: studio-doctor.sh holds an `NL` of its own and both files spell it the same
# way. If you are about to add a third site, check for the old spelling rather than assuming:
#   grep -rn "%%\$'" --include='*.sh' .
NL=$'\n'
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
  # MODIFIED_FILES / EDITED_FILES / UNREADABLE_ORIGINS are always set; KEPT/MOD_COUNT are not defined
  # until Step 5 and would be an unbound-variable death under `set -u`.
  #
  # COUNTED OFF EDITED_FILES, NOT THE UNION, for the reason the real run's line is: `you modified` has
  # to be true of every file in the number. The union includes the unreadable-origin bucket, which is
  # kept for a different reason and gets its own line here too — an announcement that folded them
  # together would be the dry run restating a claim the real run had just stopped making, which is
  # exactly the drift this block exists to prevent.
  #
  # NEITHER LINE CARRIES A PATH, so neither mints a claim in tests/test-install-dryrun.sh's parser:
  # that parser reads the first field, and `keep` has neither a dot nor a slash, so it classifies as
  # prose rather than as a promise about a path.
  DRY_MOD=$(printf '%s' "$EDITED_FILES" | grep -c . || true)
  [ "$DRY_MOD" -gt 0 ] && printf '  keep %s file(s) you modified\n' "$DRY_MOD"
  DRY_UNREADABLE=$(printf '%s' "$UNREADABLE_ORIGINS" | grep -c . || true)
  [ "$DRY_UNREADABLE" -gt 0 ] && \
    printf '  keep %s file(s) whose receipt origin cannot be read — kept, and recorded as yours\n' \
      "$DRY_UNREADABLE"

  # Report the CLAUDE.md branch we would actually take. This said "CLAUDE.md (generated)"
  # unconditionally, which is a lie in the one case that matters: against a project that already has
  # a CLAUDE.md, the real install writes CLAUDE.md.generated and leaves theirs alone. A dry run that
  # misreports the only step capable of destroying work is worse than having no dry run.
  #
  # THE MALFORMED ARM IS HERE FOR THAT SENTENCE AND NOT FOR SYMMETRY. Both arms above used to be one
  # `grep -q ...begin`, so a begin-only CLAUDE.md was announced as `refresh the generated section
  # only; your prose untouched` by the dry run and then amputated by the real run — the dry run
  # promising exactly the thing the real run destroyed, on the only step that can destroy work.
  # `claude_md_marker_state` is called, not restated, for the reason this block's header gives.
  DRY_MARKER_STATE="$(claude_md_marker_state "$PROJECT_DIR/CLAUDE.md")"
  if [ "$DRY_MARKER_STATE" = absent ]; then
    printf '  CLAUDE.md (new — generated)\n'
  elif [ "$DRY_MARKER_STATE" = wellformed ]; then
    printf '  CLAUDE.md — refresh the generated section only; your prose untouched\n'
  elif [ "$DRY_MARKER_STATE" != none ]; then
    # ONE LINE, ONE PATH. This arm writes nothing at all — not CLAUDE.md, not CLAUDE.md.generated —
    # so it names neither of the other two paths. `NOT touched` is one of the decline phrases
    # tests/test-install-dryrun.sh recognises; a rewording that leaves that list reads as a PROMISE
    # of a write this arm does not make.
    printf '  CLAUDE.md — %s, so it is NOT touched and nothing is generated\n' \
      "$(claude_md_marker_problem "$DRY_MARKER_STATE")"
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
  # NOT A BARE ASSIGNMENT — see Step 7's call site, which carries the measurement. A death here
  # would be harmless (nothing is written on this path), but the two readers are kept identical on
  # purpose, and an idiom that is safe in only one of the two places it appears is one edit from
  # being moved to the other.
  DRY_GITIGNORE_RC=0
  DRY_GITIGNORE_PLAN="$(gitignore_plan)" || DRY_GITIGNORE_RC=$?
  [ "$DRY_GITIGNORE_RC" -eq 0 ] || DRY_GITIGNORE_PLAN="failed with status $DRY_GITIGNORE_RC"
  case "${DRY_GITIGNORE_PLAN%%"$NL"*}" in
    covered)
      printf '  .gitignore — git already ignores every path we would add, so it is already covered — no change\n' ;;
    present)
      printf '  .gitignore — all %s of our entries are already lines in it, so it is already covered — no change\n' \
        "$GITIGNORE_ENTRY_COUNT" ;;
    append)
      # ONE LINE, WITH THE ENTRIES ON IT RATHER THAN INDENTED UNDER IT. An entry per line would give
      # each entry a first field of its own and mint claims about paths nothing writes.
      DRY_GITIGNORE_ADD="${DRY_GITIGNORE_PLAN#*"$NL"}"
      DRY_GITIGNORE_N=$(printf '%s\n' "$DRY_GITIGNORE_ADD" | grep -c . || true)
      # awk drains its input to the end, so this pipeline cannot SIGPIPE the writer.
      DRY_GITIGNORE_LIST="$(printf '%s\n' "$DRY_GITIGNORE_ADD" \
        | awk 'NF { if (n++) printf ", "; printf "%s", $0 } END { printf "\n" }')"
      if [ -f "$GITIGNORE" ]; then
        printf '  .gitignore — append %s entries: %s\n' "$DRY_GITIGNORE_N" "$DRY_GITIGNORE_LIST"
      else
        printf '  .gitignore (new) — create it, with %s entries: %s\n' "$DRY_GITIGNORE_N" "$DRY_GITIGNORE_LIST"
      fi ;;
    *)
      # THE SAME FALLBACK STEP 7 TAKES, IN THE SAME SHAPE, and that symmetry is the point: the whole
      # premise of one shared plan is that the two readers cannot diverge. Without an explicit
      # `append)` above, an unrecognised verdict fell into the append branch here and announced
      # `append 0 entries:` while Step 7 warned and wrote nothing — a promise with no write, in the
      # one file built to make that impossible.
      #
      # A DECLINE, AND THE ACTIVE VOICE IS LOAD-BEARING: tests/test-install-dryrun.sh's `declre`
      # carries `would leave alone`, not `would be left alone`. The passive is a substring miss and
      # classifies as a PROMISE.
      printf '  .gitignore — its plan could not be computed — would leave alone\n' ;;
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
  #
  # `would leave alone`, NOT `would be left alone`. tests/test-install-dryrun.sh's `declre` matches
  # the ACTIVE phrase as a substring; the passive misses it and classifies the line as a PROMISE —
  # and since D11's decline writes nothing at all, that is a red on a correct installer. The passive
  # shipped here for one round and the fixture below now guards the wording.
  #
  # BOTH LINES CARRY THE SAME HEDGE, and the symmetry is the fix rather than the decoration. The
  # surgical `sed` insert can fail — a manifest with no "dependencies" key matches nothing — and its
  # failure arm runs `mv "$MANIFEST.bak" "$MANIFEST"`, leaving the manifest UNCHANGED and NO backup.
  # Both files are equally absent from that outcome, so hedging the derived file and stating the
  # primary one flat read as though the edit were certain and only its by-product conditional.
  if [ "$WITH_MCP" -eq 1 ]; then
    if [ ! -f "$MANIFEST" ]; then
      printf '  Packages/manifest.json — none in this project, so --with-mcp would skip\n'
    elif grep -q "$MCP_PKG_NAME" "$MANIFEST" 2>/dev/null; then
      printf '  Packages/manifest.json — %s already present, so --with-mcp would skip\n' "$MCP_PKG_NAME"
    elif manifest_bak_is_foreign; then
      printf '  Packages/manifest.json — %s is not ours, so --with-mcp is declined — would leave alone\n' \
        "$MANIFEST_BAK_REL"
    else
      printf '  Packages/manifest.json — add %s to "dependencies", if the edit succeeds (--with-mcp)\n' \
        "$MCP_PKG_NAME"
    fi
  fi
  if [ "$WITH_INPUT_SYSTEM" -eq 1 ]; then
    if [ ! -f "$MANIFEST" ]; then
      printf '  Packages/manifest.json — none in this project, so --with-input-system would skip\n'
    elif [ "$HAS_INPUT_SYSTEM" -eq 1 ]; then
      printf '  Packages/manifest.json — %s already present, so --with-input-system would skip\n' \
        "$INPUT_SYSTEM_PKG_NAME"
    elif manifest_bak_is_foreign; then
      printf '  Packages/manifest.json — %s is not ours, so --with-input-system is declined — would leave alone\n' \
        "$MANIFEST_BAK_REL"
    else
      printf '  Packages/manifest.json — add %s to "dependencies", if the edit succeeds (--with-input-system)\n' \
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

# ── The receipt, and why it is committed by a trap and not only at the end ────
#
# THE RECEIPT IS THE ONLY THING THAT MAKES AN INSTALL REVERSIBLE. uninstall.sh removes only the
# paths it lists, deliberately — a previous version deleted by filename and would remove files it
# had never installed. So a project with the payload on disk and NO receipt is a project the
# uninstaller refuses to touch ("Refusing to guess which files are ours"), permanently, and the only
# repair is by hand.
#
# EVERY STEP BETWEEN THE FIRST `cp` AND STEP 9 CAN END THE RUN. `set -euo pipefail` turns any
# unhandled non-zero status into an exit, and this file already carries two measurements of exactly
# that — a `return 3` injected into gitignore_plan (see Step 7) and a `return 1` injected into
# add_manifest_dependency (see its header) — both of which ended the run after the payload was
# written and before the receipt was. Neither is hypothetical: `cp "$MANIFEST" "$MANIFEST.bak"` in
# add_manifest_dependency dies on a DANGLING SYMLINK at Packages/manifest.json.bak, which a user can
# leave there by accident. `[ -e ]` is false through a dangling link, so the decline above it does
# not fire; cp reports `not writing through dangling symlink`; the run ends rc=1 with the whole
# payload installed and nothing to remove it. Measured on the tree this change lands on: 67 files
# under .claude/, an empty .claude/state/, and uninstall.sh exiting 1.
#
# SO THE COMMIT POINT MOVES TO THE TRAP RATHER THAN EARLIER IN THE FILE. Writing $RECEIPT early and
# rewriting it at the end was rejected: owned_by_installer reads $RECEIPT, and four call sites below
# depend on it still holding the PREVIOUS run's receipt (the comment above that function enumerates
# the four statements that keep it so). An early write would silently change what every one of those
# reads. The trap fires after all of them, so on the ordinary path nothing about this file's
# behaviour changes at all — Step 9 writes the receipt and sets RECEIPT_WRITTEN, and the trap then
# has nothing to do.
#
# WHAT THE PARTIAL RECEIPT CONTAINS IS WHAT IS ON DISK, not a guess. Every writer below appends its
# row to $RECEIPT_TMP immediately after the write it describes, so the rows present at any moment
# are the rows for the files written up to that moment. The one comment line naming the outcome is a
# `#` line, which every reader of this format already skips.
#
# AND IT IS NOT "ALWAYS WRITE A RECEIPT". `[ -s "$RECEIPT_TMP" ]` is load-bearing: MODE is decided
# by the receipt's ABSENCE, so a run that died having written nothing must leave nothing, or a
# foreign .claude/ — someone else's, arriving through a git clone — is read as ours on the next run.
# State O2 in tests/test-install-ownership.sh injects a die at this very line and asserts no receipt
# appears.
RECEIPT_WRITTEN=0
write_receipt() {
  local note="${1:-}"
  # The payload loop creates .claude/state a few lines down, so on an abort inside that loop the
  # directory does not exist yet and the redirect below would fail.
  mkdir -p "$(dirname "$RECEIPT")" 2>/dev/null || return 1
  {
    printf '# kinglet install receipt\n'
    printf '# edition: pioneer\n'
    printf '# Written by install.sh. uninstall.sh removes only what is listed here, and only if the\n'
    printf '# checksum still matches — so anything you edited or added is left alone.\n'
    printf '# toolkit-version: %s\n' "$TOOLKIT_VERSION"
    printf '# installed-at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    [ -n "$BACKUP_DIR" ] && printf '# backup-dir: %s\n' "$(basename "$BACKUP_DIR")"
    [ -n "$note" ] && printf '# %s\n' "$note"
    printf 'path\tsha256\tmode\torigin\n'
    sort -t$'\t' -k1,1 "$RECEIPT_TMP"
  } > "$RECEIPT" || return 1
  RECEIPT_WRITTEN=1
  return 0
}

# `local rc=$?` FIRST, and nothing before it: the right-hand side is expanded before `local` runs,
# so this captures the status that triggered the trap. An EXIT trap that does not itself call `exit`
# leaves that status alone, which is why the interrupted run still reports the failure it had.
#
# `if write_receipt ...` rather than a bare call, because `set -e` is suspended inside a condition —
# a failed write here must not kill the shell a second time from inside its own exit handler.
receipt_rescue() {
  local rc=$?
  if [ "$RECEIPT_WRITTEN" -eq 0 ] && [ -s "$RECEIPT_TMP" ]; then
    if write_receipt "INCOMPLETE: install.sh exited $rc before it finished. The rows below cover what was written up to that point."; then
      err "This install did not finish (exit $rc). $RECEIPT_REL was written for what it had"
      err "already installed, so ./uninstall.sh can still remove it. Fix the cause and re-run."
    else
      err "This install did not finish (exit $rc) and $RECEIPT_REL could not be written."
      err "Remove .claude/ by hand if you want the project back as it was."
    fi
  fi
  rm -f "$RECEIPT_TMP" "$MCP_JSON_REF"
}
trap receipt_rescue EXIT

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
#   ok   Installed N file(s).
#
# N is the whole payload — the point is that the kept file is inside it. It read `85` until
# 2026-08-13, a real figure from the day it was measured and stale by one the moment
# scripts/detect-pipeline.sh joined the group loop, at which point it read as a current transcript of
# a run that no longer happens. `bash install.sh --project-dir <fixture> --yes` prints the live one.
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
  # THE ABANDONED WORK HERE IS THE REMOVAL, NOT THE FILE — which is why this is in the block while
  # `keeping yours` is not. Keeping the edited bytes is right; what did not happen is the retirement
  # this payload asked for, and the comment on the ORPHANS scan above states the cost in the words
  # that matter: "An upgrade that leaves a deleted agent reachable is worse than no upgrade: the
  # model still sees it."
  note_not_done "$ORPHAN_KEPT_COUNT retired surface(s) listed above were NOT removed — this payload no longer ships them, but you edited them, so they stay on disk and stay selectable by the model. Delete them yourself once you have salvaged the edits."
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
    # THE KEPT FILE IS NOT THE ABANDONED WORK; THE REGISTRATION IS. settings.json itself landed and
    # is the user's, exactly as the ownership rule intends — but a second artifact, the hook scripts
    # this version ships, is on disk and inert, and no amount of reading settings.json tells you so.
    # That is the boundary this block draws between a keep that belongs here and one that does not.
    note_not_done "$UNREG_COUNT hook(s) listed above are installed but NOT registered — your .claude/settings.json was kept, and it is the only place a hook is registered, so they will never fire. Add them to \"hooks\" there, or diff yours against $SCRIPT_DIR/.claude/settings.json."
  fi

  # THE OTHER DIRECTION, WHICH A PAYLOAD THAT SHRANK CREATES AND NOTHING ASKED.
  #
  # The scan above asks one question — "we ship this hook, is it registered?" — and a payload that
  # only ever GREW is fully described by it. The 2026-08-03 and 2026-08-13 cuts made the reverse
  # question real: "your file registers this, is it still there?" Step 5's prune deletes a retired
  # hook's script because it is ours and untouched, while the entry naming it lives in the
  # settings.json this run just kept, so the entry survives the removal and points at nothing.
  # Claude Code does not report a hook command it cannot find. That is the same silence an
  # unregistered hook on disk gets, arriving from the opposite side, and it does not self-heal: the
  # kept file is kept again on every subsequent run. Measured on an upgrade across the 2026-08-13
  # cut — 27 registrations in the kept file over 12 hooks on disk, 15 of them naming deleted files,
  # with `Hooks 27` printed under `Installation complete.`
  #
  # EXISTENCE ON DISK, NOT ABSENCE FROM THE PAYLOAD, is the test. It is the condition that actually
  # costs something, it needs no second file to be read, and it also catches a registration typed by
  # hand at a path that never existed — which the payload comparison would call correct.
  #
  # WARN, DO NOT EDIT. The file was kept because it is the user's, and an installer that silently
  # rewrites the file it has just finished reporting as preserved is a worse defect than this one.
  # Which entry, under which matcher, under which event is a JSON-shaped question besides, and the
  # comment above already rules that merging someone's JSON unasked is not an installer's business.
  DEAD_REG=""
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    [ -f "$PROJECT_DIR/$h" ] || DEAD_REG="${DEAD_REG}${h}"$'\n'
  done < <(grep -oE '\.claude/hooks/[a-z_-]+\.sh' "$CLAUDE_DIR/settings.json" | sort -u)
  DEAD_REG_COUNT=$(printf '%s' "$DEAD_REG" | grep -c . || true)
  if [ "$DEAD_REG_COUNT" -gt 0 ]; then
    warn "Your settings.json was kept, so $DEAD_REG_COUNT hook registration(s) name files that are not there:"
    printf '%s' "$DEAD_REG" | while IFS= read -r h; do [ -n "$h" ] && printf '       %s\n' "$h"; done
    warn "This version does not ship them. Remove their entries from \"hooks\" in .claude/settings.json,"
    warn "or diff yours against $SCRIPT_DIR/.claude/settings.json."
    # SAME BOUNDARY AS THE BLOCK ABOVE, READ FROM THE OTHER END. What was abandoned is not the kept
    # file — that is the user's and landing it is correct — but the RETIREMENT this payload asked
    # for, which finished on disk and stopped at the registration. The `ORPHAN_KEPT` note a few
    # steps up states the same thing about a retired surface's file; this states it about a retired
    # surface's last remaining reference.
    note_not_done "$DEAD_REG_COUNT hook registration(s) listed above were NOT removed — your .claude/settings.json was kept, this version no longer ships those hooks, and the entries naming them outlived the files. Delete them from \"hooks\" there, or diff yours against $SCRIPT_DIR/.claude/settings.json."
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
# The same predicate the dry run announced from, called rather than restated — see Step 3b. It is
# read ONCE, here, and every arm below keys off the token: two calls could disagree only if
# something between them rewrote the file, and the arms are what rewrite the file.
CLAUDE_MD_MARKER_STATE="$(claude_md_marker_state "$CLAUDE_MD")"
if [ -f "$GEN" ]; then
  TMP_MD=$(mktemp)
  if [ "$CLAUDE_MD_MARKER_STATE" = absent ]; then
    if bash "$GEN" ${GEN_ARGS[@]+"${GEN_ARGS[@]}"} "$PROJECT_DIR" > "$TMP_MD" 2>/dev/null; then
      mv "$TMP_MD" "$CLAUDE_MD"; ok "Generated CLAUDE.md"
      CLAUDE_MD_BRANCH="new"
    else
      rm -f "$TMP_MD"; warn "CLAUDE.md generation failed — skipped."
    fi
  elif [ "$CLAUDE_MD_MARKER_STATE" = wellformed ]; then
    # Refresh only the fenced block; everything the user wrote stays byte-for-byte.
    #
    # THE CONDITION IS THE PAIR, NOT THE OPENING MARKER. `grep -q ...begin` stood here and let a file
    # with no closing marker into this arm, where the awk below silently deleted every line under the
    # region and then said `your prose untouched`. Step 3b's predicate holds the reasoning and the
    # measurements; the malformed arm below is where such a file goes now.
    if bash "$GEN" --facts-only ${GEN_ARGS[@]+"${GEN_ARGS[@]}"} "$PROJECT_DIR" > "$TMP_MD" 2>/dev/null; then
      # The generator owns every byte between the markers, heading included. This used to print the
      # "## Project Facts" heading here as well, from the era when --facts-only emitted only the
      # table. That was corrected in generate-claude-md.sh — on one side. The result was a second,
      # empty heading appearing on every refresh, compounding once per install; a real project was
      # found carrying two. Two producers for one region is the bug the generator's own comment
      # warns about, so this side prints nothing of its own.
      #
      # THE `end` RULE USED TO OPEN `print ""` AND THAT WAS THE SAME BUG, ONE BLANK LINE WIDE. The
      # generator's emit_marked_region already ends in a blank line, and the fresh-file arm writes
      # begin + that region + end with nothing added — so the refresh arm emitted the region one line
      # LONGER than the arm it is supposed to reproduce. Measured on a urp fixture: 54 region lines on
      # install 1, 55 from install 2 on, `cmp`-clean between runs 2/3 and 3/4 and prose outside
      # byte-identical, so it was bounded rather than compounding. It was still a byte of the user's
      # file that no run asked to change, and the first /unity-init after a refresh install normalised
      # it away as a one-line `git diff` nobody requested. The rule now prints the end marker alone.
      awk -v factsfile="$TMP_MD" '
        /kinglet:generated:begin/ { print; while ((getline l < factsfile) > 0) print l; skip=1; next }
        /kinglet:generated:end/   { print; skip=0; next }
        !skip { print }
      ' "$CLAUDE_MD" > "$TMP_MD.merged" && mv "$TMP_MD.merged" "$CLAUDE_MD"
      rm -f "$TMP_MD"
      ok "Refreshed the generated section of CLAUDE.md (your prose untouched)"
      CLAUDE_MD_BRANCH="refreshed"
    else
      rm -f "$TMP_MD"; warn "CLAUDE.md refresh failed — left as-is."
    fi
  elif [ "$CLAUDE_MD_MARKER_STATE" != none ]; then
    # DECLINE, DO NOT REPAIR. This file has kinglet:generated markers, so it is not the marker-less
    # case below; and it does not have a pair this installer can bound, so it is not the refresh case
    # above.
    #
    # THE REPAIR THAT LOOKS OBVIOUS IS "CLEAR `skip` AT EOF", AND IT HAS TWO READINGS. BOTH WERE
    # BUILT AND RUN; NEITHER IS A REPAIR.
    #
    #   * Literally — `END { skip = 0 }` — it is a NO-OP. awk's END block runs after the last line,
    #     so there is nothing left for the flag to gate. Measured: the begin-only file still
    #     amputates to 80 lines / 2746 bytes and the swapped file still walks 84f3ba1d -> 1c804997,
    #     shas identical to the unrepaired installer. It fixes zero states, not one.
    #   * Effectively — buffer the skipped lines and flush them at END when no end marker ever
    #     arrived — it does save the user's prose, in BOTH malformed states. What it does instead is
    #     promote the old region into that prose and re-emit the facts block on every run: begin-only
    #     goes 124 -> 176 -> 228 lines with `## Project Facts` headings at 10 -> 11 -> 12, swapped
    #     goes 125 -> 178 -> 231. It never converges, it never repairs the pair that caused it, and
    #     it goes on printing `your prose untouched` while doing it.
    #
    # So the ground for declining is not "the repair still destroys work" — the second reading does
    # not. It is that the repair is NON-CONVERGENT and permanently reinterprets toolkit-owned bytes
    # as the user's prose: content this installer wrote inside its own markers becomes content it
    # must never touch again, growing once per install, with the malformed pair still there.
    # Declining leaves the file exactly as the user left it and names the one edit that ends the
    # state.
    #
    # NOTHING IS WRITTEN — not CLAUDE.md, not CLAUDE.md.generated. The second is deliberate: this
    # user's file already carries markers, so the beside-yours remedy ("paste the kinglet:generated
    # markers into your CLAUDE.md") is advice that would give them a second stray marker. The remedy
    # here is to repair the pair, and that is what the entry says.
    rm -f "$TMP_MD"
    warn "CLAUDE.md — $(claude_md_marker_problem "$CLAUDE_MD_MARKER_STATE"), so it was NOT touched."
    warn "Nothing was merged into it and nothing was generated beside it."
    warn "$(claude_md_marker_remedy "$CLAUDE_MD_MARKER_STATE")"
    CLAUDE_MD_BRANCH="malformed"
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
else
  # THE SUMMARY'S `*)` ARM ALREADY SAID "see the warning above" ON THIS PATH, AND THERE WAS NO
  # WARNING ABOVE. Measured on a scratch toolkit with the generator removed: the only line in the
  # whole run mentioning CLAUDE.md was `2. CLAUDE.md generation was skipped — see the warning
  # above.` — a summary pointing at output that was never printed, on the one path where the file
  # the toolkit's entire configuration lives in does not exist at all.
  warn "$GEN not found — CLAUDE.md was not generated."
fi

# ONE RECORDING POINT FOR FOUR BRANCHES, KEYED ON THE VALUE THEY ALREADY SET. `skipped` is reached
# four ways — the generator is absent, or it failed on the fresh-file arm, the refresh arm or the
# beside-yours arm — and each of those printed its own warn line naming which. Restating that here
# would be a second copy of a decision made above, so the entry points at the warning instead and
# the `else` branch above exists to guarantee there is one.
#
# `separate` IS HERE, AND THIS COMMENT ARGUED THE OPPOSITE FOR ONE ROUND. It read: "that arm writes
# CLAUDE.md.generated, announces it, and the Next-steps line names it. Work done differently is not
# work abandoned." Two things are wrong with that.
#
# THE FIRST IS THAT IT INVENTS A CRITERION TO ESCAPE THE STATED ONE. The criterion in this file's own
# header is "absent or INERT", and CLAUDE.md.generated on this branch is inert in exactly the sense an
# unregistered hook is: on disk, doing nothing, until the user acts. Claude Code reads CLAUDE.md.
# Until the block is merged into it, not one line of the toolkit's configuration applies — measured on
# a urp fixture whose CLAUDE.md is the user's own: rc=0, no block, and `grep -c kinglet:generated
# CLAUDE.md` is 0. A caller running the snippet MCP-SETUP.md prints got a clean pass on that project.
#
# THE SECOND IS THAT IT IS NOT A KEEP AT ALL. The header's exemption is for a file kept because the
# user edited it; here the installer WROTE a file, to a path the user must act on. And every project
# that already has a CLAUDE.md takes this branch, which is most projects that are not new.
#
# THE ALTERNATIVE WAS TO NAME `separate` IN MCP-SETUP.md AS A SECOND STATED EXCEPTION beside
# --dry-run, and it was rejected: an exception at the one outcome a scripted caller most needs to
# hear about is a contract nobody can script against. This entry is also SELF-CLEARING — the moment
# the user takes its advice and adds the markers, the branch becomes `refreshed` and the entry stops —
# which is the shape a recurring entry has to have to be worth printing.
#
# `malformed` IS HERE ON EXACTLY THE STATED CRITERION AND NOT ON A NEW ONE. The refresh this run was
# asked for did not happen and no second artifact was written in its place, so the toolkit's project
# facts are ABSENT from the only file Claude Code reads — the header's first clause, not the
# edited-file exemption, which does not apply because the user chose nothing here: an unclosed marker
# pair is what a half-finished hand-merge or a bad conflict resolution leaves behind. It is
# self-clearing in the same way `separate` is: repair the pair and the next run is `refreshed`.
case "$CLAUDE_MD_BRANCH" in
  skipped)
    note_not_done "CLAUDE.md — not generated, so this project has no toolkit configuration file and the FILL: markers never landed. The warn line above says which of the four ways it failed; re-run install.sh once that is fixed."
    ;;
  kept-yours)
    note_not_done "CLAUDE.md.generated — yours was kept untouched, so no generated file was produced this run. Rename or delete it and re-run to get one."
    ;;
  separate)
    note_not_done "CLAUDE.md — yours has no generated markers, so the toolkit's configuration went to CLAUDE.md.generated beside it. Claude Code reads CLAUDE.md: none of it applies until you merge that block in, or paste the kinglet:generated markers into your CLAUDE.md and re-run to have it refreshed in place."
    ;;
  malformed)
    note_not_done "CLAUDE.md — $(claude_md_marker_problem "$CLAUDE_MD_MARKER_STATE"), so the generated block was NOT refreshed and your file was left exactly as it was. $(claude_md_marker_remedy "$CLAUDE_MD_MARKER_STATE")"
    ;;
esac

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
#
# NOT A BARE ASSIGNMENT, AND THE HAZARD IS THE ONE add_manifest_dependency'S CALL SITE ALREADY
# CARRIES SIX LINES ABOUT. Under `set -euo pipefail` a command substitution's exit status IS the
# assignment's, so a non-zero return from gitignore_plan would kill the installer at THIS line —
# which is AFTER the payload is written and BEFORE the receipt is. Measured on a scratch copy by
# injecting a `return 3`: exit 3, `ok Installed N file(s).`, `ok Generated CLAUDE.md`, and NO
# RECEIPT — the whole payload in a project uninstall.sh removes nothing from, because it removes
# only what a receipt lists. Every path through gitignore_plan returns 0 today; capturing the status
# makes that an invariant the installer SURVIVES the loss of rather than one it silently DEPENDS ON,
# and the `*)` arm below turns the loss into a warning and a skipped .gitignore instead of a dead run.
#
# GITIGNORE_CREATED IS THE ONLY THING THAT CAN ANSWER "IS THIS FILE OURS?" ON THE RUN THAT MAKES IT,
# and the row below is written on ownership rather than on that flag alone — see its own comment.
GITIGNORE_CREATED=0
GITIGNORE_PLAN_RC=0
GITIGNORE_PLAN="$(gitignore_plan)" || GITIGNORE_PLAN_RC=$?
[ "$GITIGNORE_PLAN_RC" -eq 0 ] || GITIGNORE_PLAN="failed with status $GITIGNORE_PLAN_RC"
case "${GITIGNORE_PLAN%%"$NL"*}" in
  covered)
    ok ".gitignore already covers .claude/ local state — left alone." ;;
  present)
    # NOTHING IS WRITTEN ON THIS BRANCH, INCLUDING THE TRAILING NEWLINE. The previous shape reached
    # the `printf '\n'` below before discovering it had nothing to append, so a .gitignore that held
    # all four entries and did not end in a newline got one byte appended under the banner
    # "already has our entries" — a write announced as a no-change.
    ok ".gitignore already has our entries." ;;
  append)
    [ -f "$GITIGNORE" ] || { : > "$GITIGNORE"; GITIGNORE_CREATED=1; info "Created .gitignore"; }
    # Only append a newline first if the file does not already end with one; otherwise our header
    # lands on the end of their last line.
    [ -s "$GITIGNORE" ] && [ -n "$(tail -c1 "$GITIGNORE")" ] && printf '\n' >> "$GITIGNORE"
    printf '\n# Claude Code local settings and session state\n' >> "$GITIGNORE"
    ADDED=0
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      printf '%s\n' "$e" >> "$GITIGNORE"
      ADDED=$((ADDED + 1))
    done <<< "${GITIGNORE_PLAN#*"$NL"}"
    ok "Updated .gitignore ($ADDED entries)" ;;
  *)
    # The dry run's `*)` arm announces this same outcome as a decline, so the two readers still
    # agree on the branch neither of them can reach today.
    warn "gitignore_plan gave an unusable verdict (${GITIGNORE_PLAN%%"$NL"*}) — .gitignore left alone, and the install continues." ;;
esac
# THE CONSEQUENCE, NAMED. The warn above says what the installer did (nothing) and not what that
# costs, and the cost is specific: these are the paths that leak local state into someone's commits.
# The entries are listed from $GITIGNORE_ENTRIES rather than written out, so this line cannot drift
# from the set Step 7 would have appended — the drift this whole plan/act split exists to prevent.
#
# INSIDE AN `if`, NOT AS A FIFTH `case` ARM: the `*)` arm above is the fallback, and a second `*)`
# is not a thing. Reading $GITIGNORE_PLAN once more here is reading the same variable the case just
# read, not recomputing the plan.
case "${GITIGNORE_PLAN%%"$NL"*}" in
  covered|present|append) ;;
  *)
    # awk drains its input to the end, so this pipeline cannot SIGPIPE the writer.
    note_not_done ".gitignore — its plan could not be computed, so nothing was written to it and these are NOT ignored: $(printf '%s\n' "$GITIGNORE_ENTRIES" | awk 'NF { if (n++) printf ", "; printf "%s", $0 } END { printf "\n" }'). Add them by hand, or your local settings and session state land in your commits."
    ;;
esac

# A .gitignore THIS INSTALLER CREATED is a file we own. One the user already had is not, whatever we
# appended to it — appending is not authorship, and claiming their file would let uninstall.sh delete
# it. That asymmetry is the whole of the decision, and `GITIGNORE_CREATED` is the only thing that can
# see it: after the write, a created file and an appended-to one are both just a .gitignore with our
# four entries in it, and nothing on disk tells them apart.
#
# Without a row the created file was permanent debris. It is the fourth member of a family this file
# has now closed three times — Packages/manifest.json.bak, CLAUDE.md.generated, MCP-SETUP.md — and
# the one the `find`-snapshot oracle of the previous wave structurally could not see, because on
# every fixture but `bare` the path already exists before the run and a path snapshot shows no new
# file.
#
# OWNERSHIP, NOT AUTHORSHIP, so the disjunction rather than the flag alone. Run 1 creates the file;
# run 2's plan is `present` (all four entries are already lines) and appends nothing, so a row
# written only where the file is created would vanish on run 2 and the debris would come straight
# back one run later. That is state B's defect, and states M and M3 hold both halves.
#
# THERE IS NO REFERENCE COPY — the file is the user's project's, not a payload file — so the ref
# argument is '' and owned_by_installer's first arm is skipped by construction. What answers is the
# previous receipt, and it is a checksum comparison: the moment the user adds a line of their own,
# the file stops being ours and is left alone (state M3). The cost of that is our four entries
# staying in a file we no longer claim, which is the same trade an edited MCP-SETUP.md already makes.
#
# The mode is read off the file rather than written as 644: `: > "$GITIGNORE"` creates under the
# caller's umask, and a hardcoded value here would be a receipt that disagrees with its own file.
if [ -f "$GITIGNORE" ] \
   && { [ "$GITIGNORE_CREATED" -eq 1 ] || owned_by_installer '.gitignore' ''; }; then
  printf '.gitignore\t%s\t%s\ttoolkit\n' \
    "$(sha_of "$GITIGNORE")" \
    "$(stat -c '%a' "$GITIGNORE" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
fi

# ── Step 8: Optional — manifest.json package additions ───────────────────────
# One helper for every "--with-X adds a package to Packages/manifest.json" flag, so --with-mcp and
# --with-input-system share the same surgical insert, the same backup behaviour, and the same
# "could not edit safely" fallback rather than two hand-maintained copies drifting apart.
#
# $MANIFEST_BAK_REL is defined in Step 3b, not here: the dry-run block announces this file and had
# to be able to name it. One definition, derived from $MANIFEST, so the receipt row, the
# announcement and the file they both name cannot disagree.
MANIFEST_BAK_KEPT=0
# MANIFEST_DECLINED USED TO BE DECLARED HERE, one flag per line, read by a `Not done:` block at the
# bottom of the file that knew about this function and nothing else. It is now `$NOT_DONE` at the top
# — same idiom, same "set where the decision is made, read where the run speaks to the user", every
# other abandonment site as well. All three abandonment outcomes in this function record through it, and the fourth
# outcome (the package is already there) is not an abandonment: the manifest ends the run in the
# state the flag asked for.
add_manifest_dependency() {
  local pkg_name="$1" pkg_value="$2" flag_name="$3"
  if [ ! -f "$MANIFEST" ]; then
    warn "No Packages/manifest.json — skipping $flag_name."
    note_not_done "$flag_name — skipped: this project has no Packages/manifest.json, so $pkg_name was not added. Open the project in Unity once to create the manifest, then re-run with $flag_name."
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
  # before Step 8b, Step 8c and Step 9 — so the project keeps the whole payload and NO RECEIPT, and
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
  # What the status genuinely cannot carry, the summary must. `note_not_done` appends to the global
  # $NOT_DONE — this function is called once per flag, so two flags can record two lines — and that
  # drives the `Not done:` block beside the green banner: set where the decision is made, read where
  # the run speaks to the user. Without it the only trace of an abandoned flag was four warn lines a
  # dozen lines above `Installation complete.` and an exit status of 0. The mechanism was
  # MANIFEST_DECLINED, private to this function; it is now the shared one every site uses, and
  # the exit contract in MCP-SETUP.md is what says out loud that the block is complete.
  if [ -e "$MANIFEST.bak" ] && [ "$MANIFEST_BAK_KEPT" -ne 1 ] && ! owned_by_installer "$MANIFEST_BAK_REL" ''; then
    warn "$MANIFEST_BAK_REL exists and is not ours — declining $flag_name rather than overwriting it."
    warn "That file is the backup this edit needs to stay undoable. Move it aside and re-run with"
    warn "$flag_name, or add this under \"dependencies\" yourself:"
    warn "    \"$pkg_name\": \"$pkg_value\""
    note_not_done "$flag_name — declined: $MANIFEST_BAK_REL is not ours to overwrite, so the manifest was not edited. Move that file aside and re-run with $flag_name, or add \"$pkg_name\": \"$pkg_value\" under \"dependencies\" by hand."
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
    # THE FLAG MUST NOT OUTLIVE THE FILE IT NAMES. The `mv` above has just consumed the backup, and
    # this function is called once per --with-* flag: on a two-flag run where the first caller
    # succeeded and kept its backup, MANIFEST_BAK_KEPT is already 1 when the second caller reaches
    # this arm and deletes the file. The row below then fires on a path that is gone, and because
    # `sha_of` sits inside a `printf` ARGUMENT — where `set -e` does not reach — the miss does not
    # kill the run: it writes a row with an EMPTY checksum, which uninstall.sh silently declines to
    # act on. A row that removes nothing is indistinguishable on disk from no row at all, and worse
    # than one, because it reads as coverage.
    MANIFEST_BAK_KEPT=0
    warn "Could not edit manifest.json safely — add this under \"dependencies\" yourself:"
    warn "    \"$pkg_name\": \"$pkg_value\""
    # THE THIRD MEMBER OF THE FAMILY THE COMMENT ABOVE ENUMERATES, and until now the only one of the
    # four with no trace in the summary at all. The surgical `sed` matches nothing in a manifest with
    # no "dependencies" key — a real shape, and the one the plan reproduced — and the failure arm
    # restores the original, so the run ends with the manifest byte-identical and the flag silently
    # gone. `$MANIFEST_BAK_REL` is not offered as a remedy here: the `mv` above has just consumed it.
    note_not_done "$flag_name — the manifest could not be edited safely, so it is unchanged and $pkg_name was not added. Add \"$pkg_name\": \"$pkg_value\" under \"dependencies\" in Packages/manifest.json yourself."
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
#
# THE `-f` IS THE BELT TO THAT BRACES. `owned_by_installer` already opens with an existence test, so
# it guards only the first disjunct — this run's own knowledge, which the failure arm above can
# invalidate between the flag being set and this line being reached. Two independent conditions have
# to be wrong before an empty-checksum row can be written now, and the two are in different
# functions.
if [ -f "$PROJECT_DIR/$MANIFEST_BAK_REL" ] \
   && { [ "$MANIFEST_BAK_KEPT" -eq 1 ] || owned_by_installer "$MANIFEST_BAK_REL" ''; }; then
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
  # NOT A `keeping yours` KEEP. Nothing of ours is on disk at that path to keep — the file is
  # entirely the user's, and what is missing is the server entry every unity-* agent's
  # mcp__UnityMCP__* tools resolve through. Without it those agents load with tools that cannot be
  # called, which is silent at install time and looks like a broken bridge later.
  note_not_done ".mcp.json — yours has no UnityMCP entry and was not rewritten, so the unity-* agents have no MCP server to reach. Add the \"UnityMCP\" block printed above under \"mcpServers\"."
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
# THE ONLY KEEP IN THIS FILE THAT SAID NOTHING AT ALL. Every other one reports: `keeping yours` lists
# the payload files, the CLAUDE.md.generated arm warns twice, .mcp.json prints the block it did not
# write. This branch printed no line in the entire run, while the "Next steps" summary below went on
# pointing at MCP-SETUP.md — which now resolves to the user's file, and which is where this
# installer's exit contract is written down.
#
# A REPORT, NOT A `Not done:` ENTRY, and the boundary is the one $NOT_DONE's header states. The file
# at that path is the user's own — either they wrote it or they edited ours — and keeping it is the
# ownership rule working, not work abandoned. It belongs in the same class as `keeping yours`, which
# is reported and counted and stays out of the block.
#
# `owned_by_installer` is CALLED rather than restated; it is the same predicate, with the same
# reference copy, that the row below decides ownership with. On the ordinary re-install it answers
# yes and this branch is silent, which is the point: the warning fires where the toolkit's guide is
# genuinely not the file on disk.
elif [ -f "$SCRIPT_DIR/MCP-SETUP.md" ] && ! owned_by_installer 'MCP-SETUP.md' "$SCRIPT_DIR/MCP-SETUP.md"; then
  warn "MCP-SETUP.md at the project root is not ours — keeping yours, untouched."
  warn "This version's bridge-setup guide was not installed, and the 'Next steps' pointer below"
  warn "resolves to your file. Compare it against $SCRIPT_DIR/MCP-SETUP.md if the bridge misbehaves."
fi
# Same shape as .mcp.json's row above, and for the same reason: the row states what we own at the
# end of the run, not what this run happened to write.
if owned_by_installer 'MCP-SETUP.md' "$SCRIPT_DIR/MCP-SETUP.md"; then
  printf 'MCP-SETUP.md\t%s\t644\ttoolkit\n' "$(sha_of "$MCP_SETUP_MD")" >> "$RECEIPT_TMP"
fi

# ── Step 9: Write the receipt ────────────────────────────────────────────────
# The body moved to write_receipt beside the trap that arms it (Step 5). Two copies of this heredoc
# — one for the ordinary path, one for the interrupted one — would be two definitions of the receipt
# format, and the difference between them would only ever show up in a project that already had the
# worse problem. RECEIPT_WRITTEN is set inside the function, so the trap knows there is nothing left
# to do.
write_receipt || die "Could not write $RECEIPT_REL — the payload is installed and unremovable; remove .claude/ by hand."
RECEIPT_ROWS=$(grep -vc '^#' "$RECEIPT" || true)
ok "Receipt written: $RECEIPT_REL ($((RECEIPT_ROWS - 1)) files)"

# ── Summary ──────────────────────────────────────────────────────────────────
# Counted, never hardcoded. Upstream's summary claimed 22 hooks / 22 commands / 41 skills while
# shipping 25 / 27 / 42, because the numbers were typed into an echo.
count_in() { find "$CLAUDE_DIR/$1" -name "$2" 2>/dev/null | wc -l | tr -d ' '; }
# Hooks are counted from settings.json, not from *.sh on disk: hooks/ also holds _lib.sh, a sourced
# library that is not itself a hook, so the file count and the hook count are never the same number.
# That still holds below — the sweep is settings.json's registrations, and _lib.sh is never one of
# them — but a registration is now only counted once the file it names exists.
#
# THE NUMBER USED TO BE A COUNT OF REGISTRATIONS AND NOTHING ELSE, and after an upgrade across a
# payload that shrank it printed the pre-cut figure over a tree that no longer held those files:
# `Hooks 27` with 12 on disk, measured. It is the user's file, correctly kept, so the stale entries
# are still there and no re-run clears them.
#
# BOTH NUMBERS, NOT THE SMALLER ONE. Reporting only what will fire is the honest half of the answer
# and it is also the quiet one: `Hooks 12` agrees with a healthy tree, so the summary — the last
# thing printed, and on a long upgrade the only thing read — would look identical to a project with
# nothing wrong while fifteen entries in the user's file still named deleted scripts. That is the
# same defect as the one being repaired, one digit to the left. The parenthetical appears only when
# something is dead, so an ordinary install still prints a bare number and the warning block above
# is what the reader is being pointed back at.
count_hooks() {
  local registered
  local live
  local dead
  local ch_h
  registered=$(grep -oE '\.claude/hooks/[a-z_-]+\.sh' "$CLAUDE_DIR/settings.json" 2>/dev/null | sort -u || true)
  live=0
  dead=0
  # A settings.json that is missing or registers nothing yields one empty line here, which the
  # `continue` drops — so both counters stay 0 and the bare `0` the old one-liner printed is
  # preserved. `<<<` and not a pipe: the loop drains either way, but a here-string keeps the
  # counters out of a subshell, where they would be incremented and then thrown away.
  while IFS= read -r ch_h; do
    [ -n "$ch_h" ] || continue
    if [ -f "$PROJECT_DIR/$ch_h" ]; then live=$((live + 1)); else dead=$((dead + 1)); fi
  done <<< "$registered"
  if [ "$dead" -gt 0 ]; then
    printf '%s (%s registered, %s dead)\n' "$live" "$((live + dead))" "$dead"
  else
    printf '%s\n' "$live"
  fi
}
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
  # The other decline, and the reason it does not fall through to `*)`. That arm sends the reader to
  # "the warning above" for a run whose warning is three lines long and names a repair; more to the
  # point, `refreshed`'s line — "your own prose was left untouched" — is what this branch printed
  # before the decline existed, on runs that had just deleted the prose.
  malformed)
    CLAUDE_MD_STEP="$(claude_md_marker_remedy "$CLAUDE_MD_MARKER_STATE") Nothing was written to it this run."
    ;;
  *)
    CLAUDE_MD_STEP='CLAUDE.md generation was skipped — see the warning above.'
    ;;
esac
# Work this run was asked for and did not do. `Installation complete.` is true — the payload landed,
# the receipt is written — but on its own it read as "everything you asked for happened", and every
# abandonment left its only trace as warn lines up to five hundred lines above the green banner.
#
# THE BLOCK IS NOW THE `Not done:` CONTRACT MCP-SETUP.md STATES, not the manifest's private summary.
# The sites record into $NOT_DONE; this prints them. Derive their number where the accumulator is
# defined, and it writes no number down either. This sentence read "Twelve sites" for one round while
# the file's own header said eleven and forbade quoting the figure — in the place a reader tracing
# the mechanism arrives FIRST, which is how a stale count gets believed. The
# CLAUDE.md side is one of the sites now rather than the exception it used to be — it still ALSO
# rewrites `Next steps: 2.` in place, so a kept-yours or `separate` run says it twice, in the two
# places a reader looks.
#
# BEFORE `Next steps:`, DELIBERATELY. What a user does next depends on what did not happen, and a
# block printed after the numbered list reads as a footnote to it.
print_not_done
cat <<EOF

Next steps:
  1. Install the Unity MCP bridge — see MCP-SETUP.md (Window > MCP for Unity > Auto-Setup).
  2. $CLAUDE_MD_STEP
  3. Run 'claude' in your project and try /unity-init, or /unity-doctor for a health check.
  4. Health check any time: ./.claude/scripts/studio-doctor.sh --project-dir "$PROJECT_DIR"
EOF
exit 0
