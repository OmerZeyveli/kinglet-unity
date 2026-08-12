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
# Keep this in step with the two write loops below (the payload loop and the scripts/tests groups)
# — a path written but missing here would be deleted as an orphan the run after it appears.
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

sha_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

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

if [ "$DRY_RUN" -eq 1 ]; then
  printf '\n%s\n' "${BOLD}Would install:${NC}"
  printf '  %s files into %s\n' "$PAYLOAD_COUNT" "$CLAUDE_DIR"
  printf '  scripts/ into .claude/\n'
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
    printf '  CLAUDE.md.generated — yours exists and has no markers, so it is NOT touched\n'
  fi

  printf '  .gitignore — add .claude/settings.local.json and .claude/state/*\n'
  if [ "$WITH_MCP" -eq 1 ]; then
    if [ ! -f "$MANIFEST" ]; then
      printf '  --with-mcp: no Packages/manifest.json — would skip\n'
    elif grep -q "$MCP_PKG_NAME" "$MANIFEST" 2>/dev/null; then
      printf '  --with-mcp: %s already present — would skip\n' "$MCP_PKG_NAME"
    else
      printf '  --with-mcp: add %s to Packages/manifest.json\n' "$MCP_PKG_NAME"
    fi
  fi
  if [ "$WITH_INPUT_SYSTEM" -eq 1 ]; then
    if [ ! -f "$MANIFEST" ]; then
      printf '  --with-input-system: no Packages/manifest.json — would skip\n'
    elif [ "$HAS_INPUT_SYSTEM" -eq 1 ]; then
      printf '  --with-input-system: %s already present — would skip\n' "$INPUT_SYSTEM_PKG_NAME"
    else
      printf '  --with-input-system: add %s to Packages/manifest.json\n' "$INPUT_SYSTEM_PKG_NAME"
    fi
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
  # The copy is conditional — it never overwrites a file the user already has — so an unconditional
  # line here would promise a file the real run skips: this block's own bug in mirror image. The
  # condition is the same one Step 8c tests, read against $PROJECT_DIR the way the CLAUDE.md branch
  # above does ($MCP_SETUP_MD is not defined until the real-run path, which we never reach here).
  if [ -f "$SCRIPT_DIR/MCP-SETUP.md" ]; then
    if [ ! -f "$PROJECT_DIR/MCP-SETUP.md" ]; then
      printf '  MCP-SETUP.md (new — the MCP bridge setup guide)\n'
    else
      printf '  MCP-SETUP.md — yours exists, so it is NOT touched\n'
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
trap 'rm -f "$RECEIPT_TMP"' EXIT

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
#   2. Twelve of the twenty-eight test files reference install.sh, provenance.tsv, tests/fixtures/,
#      migration/baseline-inventory.json or tools.kinglet_build — none of which ship. Those cannot
#      pass in a project whatever REPO_DIR says.
#
# The suite validates the toolkit, not the project. What a user actually needs is
# scripts/studio-doctor.sh, which does ship, runs correctly against an installed layout, and checks
# the things that matter there: the install verified against its receipt, every hook named by
# settings.json present, the MCP bridge configured, the Input System package present.
#
# So: scripts/ ships, tests/ does not. An installed project that already has .claude/tests/ from an
# earlier version gets it removed by the payload-prune above, which is the behaviour that exists for
# exactly this.
for group in scripts; do
  [ -d "$SCRIPT_DIR/$group" ] || continue
  mkdir -p "$CLAUDE_DIR/$group"
  for f in "$SCRIPT_DIR/$group"/*.sh; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    [ "$b" = "check-provenance.sh" ] && continue
    cp "$f" "$CLAUDE_DIR/$group/$b"
    chmod +x "$CLAUDE_DIR/$group/$b"
    printf '.claude/%s/%s\t%s\t%s\ttoolkit\n' "$group" "$b" "$(sha_of "$CLAUDE_DIR/$group/$b")" "755" >> "$RECEIPT_TMP"
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
    if bash "$GEN" ${GEN_ARGS[@]+"${GEN_ARGS[@]}"} "$PROJECT_DIR" > "$TMP_MD" 2>/dev/null; then
      mv "$TMP_MD" "$PROJECT_DIR/CLAUDE.md.generated"
      warn "CLAUDE.md exists and has no generated markers — wrote CLAUDE.md.generated instead."
      warn "Yours was not touched. Merge by hand, or add the markers to let us refresh in place."
      CLAUDE_MD_BRANCH="separate"
    else
      rm -f "$TMP_MD"; warn "CLAUDE.md generation failed — skipped."
    fi
  fi
fi

# ── Step 7: .gitignore ───────────────────────────────────────────────────────
#
# Ask git what it already ignores rather than grepping for our exact lines. A project that ignores
# `/.claude/` wholesale — a perfectly sensible choice, and one real projects make — is already
# covered, and appending our three entries to it is just noise in someone else's file.
GITIGNORE="$PROJECT_DIR/.gitignore"
WANT_IGNORED='.claude/settings.local.json
.claude/state/session.json
.claude.backup.20260101120000/'

already_ignored() {
  git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
  git -C "$PROJECT_DIR" check-ignore -q "$1" 2>/dev/null
}

NEEDED=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  already_ignored "$p" || NEEDED=1
done <<< "$WANT_IGNORED"

if [ "$NEEDED" -eq 0 ] && [ -f "$GITIGNORE" ]; then
  ok ".gitignore already covers .claude/ local state — left alone."
else
  [ -f "$GITIGNORE" ] || { : > "$GITIGNORE"; info "Created .gitignore"; }
  # Only append a newline first if the file does not already end with one; otherwise our header
  # lands on the end of their last line.
  [ -s "$GITIGNORE" ] && [ -n "$(tail -c1 "$GITIGNORE")" ] && printf '\n' >> "$GITIGNORE"
  ADDED=0
  add_ignore() {
    grep -qxF "$1" "$GITIGNORE" 2>/dev/null && return
    [ "$ADDED" -eq 0 ] && printf '\n# Claude Code local settings and session state\n' >> "$GITIGNORE"
    printf '%s\n' "$1" >> "$GITIGNORE"; ADDED=$((ADDED + 1))
  }
  add_ignore '.claude/settings.local.json'
  add_ignore '.claude/state/*'
  add_ignore '!.claude/state/.gitkeep'
  # uninstall.sh writes its backup to .claude.backup.<timestamp>/ at the project root. Without this,
  # every uninstall leaves an untracked directory that dirties `git status` in the user's own repo.
  add_ignore '.claude.backup.*/'
  [ "$ADDED" -gt 0 ] && ok "Updated .gitignore ($ADDED entries)" || ok ".gitignore already has our entries."
fi

# ── Step 8: Optional — manifest.json package additions ───────────────────────
# One helper for every "--with-X adds a package to Packages/manifest.json" flag, so --with-mcp and
# --with-input-system share the same surgical insert, the same backup behaviour, and the same
# "could not edit safely" fallback rather than two hand-maintained copies drifting apart.
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

# ── Step 8b: .mcp.json — the file Claude Code actually reads MCP servers from ──
# Project-scoped MCP servers live in .mcp.json at the project root, not in .claude/settings.json.
# Claude Code silently ignores an mcpServers key there, so writing it was the whole defect: the
# unity-* agents had no tools to call. See MCP-SETUP.md for the approval step this still requires.
MCP_JSON="$PROJECT_DIR/.mcp.json"
MCP_JSON_RECEIPT_LINE=""
if [ ! -f "$MCP_JSON" ]; then
  cat > "$MCP_JSON" <<'MCPJSON'
{
  "mcpServers": {
    "UnityMCP": {
      "type": "http",
      "url": "http://localhost:8080/mcp"
    }
  }
}
MCPJSON
  ok "Wrote .mcp.json (UnityMCP → http://localhost:8080/mcp)"
  MCP_JSON_RECEIPT_LINE=$(printf '.mcp.json\t%s\t644\ttoolkit' "$(sha_of "$MCP_JSON")")
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
[ -n "$MCP_JSON_RECEIPT_LINE" ] && printf '%s\n' "$MCP_JSON_RECEIPT_LINE" >> "$RECEIPT_TMP"

# ── Step 8c: MCP-SETUP.md — the setup guide the "Next steps" summary points at ──
# It used to point a freshly installed project at MCP-SETUP.md while never installing it: the
# payload is .claude/** only, so the file was absent from every project this toolkit set up. Copied
# alongside CLAUDE.md (project root, never overwritten if the user already has one) so the pointer
# in the summary below actually resolves.
MCP_SETUP_MD="$PROJECT_DIR/MCP-SETUP.md"
if [ -f "$SCRIPT_DIR/MCP-SETUP.md" ] && [ ! -f "$MCP_SETUP_MD" ]; then
  cp "$SCRIPT_DIR/MCP-SETUP.md" "$MCP_SETUP_MD"
  ok "Installed MCP-SETUP.md"
  printf '%s\n' "$(printf 'MCP-SETUP.md\t%s\t644\ttoolkit' "$(sha_of "$MCP_SETUP_MD")")" >> "$RECEIPT_TMP"
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
  *)
    CLAUDE_MD_STEP='CLAUDE.md generation was skipped — see the warning above.'
    ;;
esac
cat <<EOF

Next steps:
  1. Install the Unity MCP bridge — see MCP-SETUP.md (Window > MCP for Unity > Auto-Setup).
  2. $CLAUDE_MD_STEP
  3. Run 'claude' in your project and try /unity-init, or /unity-doctor for a health check.
  4. Health check any time: ./.claude/scripts/studio-doctor.sh --project-dir "$PROJECT_DIR"
EOF
exit 0
