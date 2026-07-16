#!/usr/bin/env bash
#
# cloud-nine-unity — installer
#
# Installs the toolkit into a Unity project: agents, commands, skills, hooks, rules, templates,
# settings, and a generated CLAUDE.md. One repo, one script, no prerequisites beyond Unity itself.
#
# Usage:
#   ./install.sh [--project-dir <path>] [--with-mcp] [--yes] [--dry-run]
#
#   --project-dir <path>  Target Unity project root (default: current directory)
#   --with-mcp            Also add the CoplayDev Unity MCP package to Packages/manifest.json
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

usage() { sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_VERSION="$(cat "$SCRIPT_DIR/.claude/VERSION" 2>/dev/null || echo unknown)"

MCP_PKG_NAME="com.coplaydev.unity-mcp"
MCP_PKG_URL="https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main"

RECEIPT_REL=".claude/state/install-receipt.tsv"

# ── Args ─────────────────────────────────────────────────────────────────────
PROJECT_DIR="$(pwd)"
WITH_MCP=0; ASSUME_YES=0; DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    # Validate before shift 2: under `set -u`, `shift 2` on a trailing flag kills the script
    # before any error message can print.
    --project-dir) [ $# -ge 2 ] || die "--project-dir requires a path"; PROJECT_DIR="$2"; shift 2 ;;
    --with-mcp)    WITH_MCP=1; shift ;;
    --yes|-y)      ASSUME_YES=1; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    -h|--help)     usage ;;
    *)             die "Unknown argument: $1 (use --help)" ;;
  esac
done

PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || die "Project directory not found"
CLAUDE_DIR="$PROJECT_DIR/.claude"
RECEIPT="$PROJECT_DIR/$RECEIPT_REL"

printf '%s\n' "${BOLD}cloud-nine-unity ${TOOLKIT_VERSION}${NC} — installer"
info "Project: $PROJECT_DIR"
[ "$DRY_RUN" -eq 1 ] && warn "Dry run — nothing will be written."

# ── Step 1: Validate Unity project ───────────────────────────────────────────
[ -d "$PROJECT_DIR/Assets" ] || die "No Assets/ directory — this does not look like a Unity project."
[ -d "$PROJECT_DIR/ProjectSettings" ] || die "No ProjectSettings/ directory — this does not look like a Unity project."
[ -d "$SCRIPT_DIR/.claude" ] || die "Payload not found at $SCRIPT_DIR/.claude — run install.sh from the cloud-nine-unity repo root."
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
    info "Existing cloud-nine-unity install found (version $PREV) — upgrading to $TOOLKIT_VERSION."
    info "Files you modified will be reported and kept; untouched files are replaced."
    ;;
  foreign)
    warn "$CLAUDE_DIR exists but has no install receipt."
    warn "cloud-nine-unity did not create it, so it will not be removed or merged blindly."
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

sha_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# On upgrade, find files the user edited so we can leave them alone.
MODIFIED_FILES=""
if [ "$MODE" = ours ]; then
  while IFS=$'\t' read -r rel recorded _mode _origin; do
    case "$rel" in ''|\#*) continue ;; esac
    [ -f "$PROJECT_DIR/$rel" ] || continue
    actual=$(sha_of "$PROJECT_DIR/$rel")
    [ "$actual" = "$recorded" ] || MODIFIED_FILES="${MODIFIED_FILES}${rel}"$'\n'
  done < <(grep -v '^#' "$RECEIPT" 2>/dev/null | tail -n +2 || true)
  MOD_COUNT=$(printf '%s' "$MODIFIED_FILES" | grep -c . || true)
  if [ "$MOD_COUNT" -gt 0 ]; then
    warn "$MOD_COUNT installed file(s) have local edits — keeping yours:"
    printf '%s' "$MODIFIED_FILES" | while IFS= read -r m; do [ -n "$m" ] && printf '       %s\n' "$m"; done
  fi
fi

is_modified() { printf '%s' "$MODIFIED_FILES" | grep -qxF "$1"; }

if [ "$DRY_RUN" -eq 1 ]; then
  printf '\n%s\n' "${BOLD}Would install:${NC}"
  printf '  %s files into %s\n' "$PAYLOAD_COUNT" "$CLAUDE_DIR"
  printf '  scripts/ and tests/ into .claude/\n'
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
  elif grep -q 'cloud-nine-unity:generated:begin' "$PROJECT_DIR/CLAUDE.md" 2>/dev/null; then
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
  [ -n "$BACKUP_DIR" ] && printf '  backup: %s\n' "$(basename "$BACKUP_DIR")"
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

# Ship the provenance rows for the files we just installed. NOTICE.md cites this, and a licence
# notice you cannot check against anything is just a claim.
if [ -f "$SCRIPT_DIR/provenance.tsv" ]; then
  {
    printf '# Provenance for the files installed under .claude/ — the evidence behind NOTICE.md.\n'
    printf '# The full manifest (tests, docs, repo tooling) lives in the cloud-nine-unity repo.\n'
    # awk reads the file directly and exits after the line it wants. `grep ... | head -1` would
    # SIGPIPE the grep when head closes the pipe, and pipefail turns that into a 141 that set -e
    # acts on — the installer would die here having written half a payload.
    awk '/^# ecu=/ {print; exit}' "$SCRIPT_DIR/provenance.tsv"
    awk '!/^#/ {print; exit}' "$SCRIPT_DIR/provenance.tsv"
    grep -v '^#' "$SCRIPT_DIR/provenance.tsv" | tail -n +2 | grep '^\.claude/' || true
  } > "$CLAUDE_DIR/provenance.tsv"
  printf '.claude/provenance.tsv\t%s\t644\ttoolkit\n' "$(sha_of "$CLAUDE_DIR/provenance.tsv")" >> "$RECEIPT_TMP"
  WRITTEN=$((WRITTEN + 1))
fi

# Validation scripts and the test suite ship alongside the payload.
for group in scripts tests; do
  [ -d "$SCRIPT_DIR/$group" ] || continue
  mkdir -p "$CLAUDE_DIR/$group"
  for f in "$SCRIPT_DIR/$group"/*.sh; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    cp "$f" "$CLAUDE_DIR/$group/$b"
    chmod +x "$CLAUDE_DIR/$group/$b"
    printf '.claude/%s/%s\t%s\t%s\ttoolkit\n' "$group" "$b" "$(sha_of "$CLAUDE_DIR/$group/$b")" "755" >> "$RECEIPT_TMP"
    WRITTEN=$((WRITTEN + 1))
  done
done
ok "Installed $WRITTEN file(s)$([ "$KEPT" -gt 0 ] && printf ', kept %s of yours' "$KEPT")."

# ── Step 6: CLAUDE.md ────────────────────────────────────────────────────────
# The installer owns the destination; the generator only writes to stdout. Upstream had both
# writing the same path, which corrupted fresh files and destroyed existing ones.
CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"
GEN="$SCRIPT_DIR/scripts/generate-claude-md.sh"
if [ -f "$GEN" ]; then
  TMP_MD=$(mktemp)
  if [ ! -f "$CLAUDE_MD" ]; then
    if bash "$GEN" "$PROJECT_DIR" > "$TMP_MD" 2>/dev/null; then
      mv "$TMP_MD" "$CLAUDE_MD"; ok "Generated CLAUDE.md"
    else
      rm -f "$TMP_MD"; warn "CLAUDE.md generation failed — skipped."
    fi
  elif grep -q 'cloud-nine-unity:generated:begin' "$CLAUDE_MD"; then
    # Refresh only the fenced block; everything the user wrote stays byte-for-byte.
    if bash "$GEN" --facts-only "$PROJECT_DIR" > "$TMP_MD" 2>/dev/null; then
      awk -v factsfile="$TMP_MD" '
        /cloud-nine-unity:generated:begin/ { print; print ""; print "## Project Facts (auto-detected)"; print ""; while ((getline l < factsfile) > 0) print l; skip=1; next }
        /cloud-nine-unity:generated:end/   { print ""; print; skip=0; next }
        !skip { print }
      ' "$CLAUDE_MD" > "$TMP_MD.merged" && mv "$TMP_MD.merged" "$CLAUDE_MD"
      rm -f "$TMP_MD"
      ok "Refreshed the generated section of CLAUDE.md (your prose untouched)"
    else
      rm -f "$TMP_MD"; warn "CLAUDE.md refresh failed — left as-is."
    fi
  else
    if bash "$GEN" "$PROJECT_DIR" > "$TMP_MD" 2>/dev/null; then
      mv "$TMP_MD" "$PROJECT_DIR/CLAUDE.md.generated"
      warn "CLAUDE.md exists and has no generated markers — wrote CLAUDE.md.generated instead."
      warn "Yours was not touched. Merge by hand, or add the markers to let us refresh in place."
    else
      rm -f "$TMP_MD"; warn "CLAUDE.md generation failed — skipped."
    fi
  fi
fi

# ── Step 7: .gitignore ───────────────────────────────────────────────────────
GITIGNORE="$PROJECT_DIR/.gitignore"
[ -f "$GITIGNORE" ] || { : > "$GITIGNORE"; info "Created .gitignore"; }
ADDED=0
add_ignore() { grep -qxF "$1" "$GITIGNORE" 2>/dev/null || { printf '%s\n' "$1" >> "$GITIGNORE"; ADDED=$((ADDED + 1)); }; }
if [ "$ADDED" -eq 0 ]; then printf '\n# Claude Code local settings and session state\n' >> "$GITIGNORE"; fi
add_ignore '.claude/settings.local.json'
add_ignore '.claude/state/*'
add_ignore '!.claude/state/.gitkeep'
[ "$ADDED" -gt 0 ] && ok "Updated .gitignore ($ADDED entries)"

# ── Step 8: Optional — CoplayDev MCP package ─────────────────────────────────
if [ "$WITH_MCP" -eq 1 ]; then
  if [ ! -f "$MANIFEST" ]; then
    warn "No Packages/manifest.json — skipping --with-mcp."
  elif grep -q "$MCP_PKG_NAME" "$MANIFEST"; then
    ok "$MCP_PKG_NAME already in manifest.json."
  else
    # Surgical insert. The old installer round-tripped the JSON through a re-indenting dump, which
    # reformatted the user's whole manifest to add one line.
    cp "$MANIFEST" "$MANIFEST.bak"
    if sed -i.tmp "s|\"dependencies\"[[:space:]]*:[[:space:]]*{|\"dependencies\": {\n    \"$MCP_PKG_NAME\": \"$MCP_PKG_URL\",|" "$MANIFEST" 2>/dev/null && grep -q "$MCP_PKG_NAME" "$MANIFEST"; then
      rm -f "$MANIFEST.tmp"
      ok "Added $MCP_PKG_NAME to manifest.json (backup: manifest.json.bak)"
    else
      mv "$MANIFEST.bak" "$MANIFEST"; rm -f "$MANIFEST.tmp"
      warn "Could not edit manifest.json safely — add this under \"dependencies\" yourself:"
      warn "    \"$MCP_PKG_NAME\": \"$MCP_PKG_URL\""
    fi
  fi
fi

# ── Step 9: Write the receipt ────────────────────────────────────────────────
{
  printf '# cloud-nine-unity install receipt\n'
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
# library that is not itself a hook. 26 files, 25 hooks.
count_hooks() { grep -oE '\.claude/hooks/[a-z_-]+\.sh' "$CLAUDE_DIR/settings.json" 2>/dev/null | sort -u | wc -l | tr -d ' '; }
printf '\n%s\n' "${BOLD}${GREEN}Installation complete.${NC}"
printf '  %sAgents%s    %s\n'   "$CYAN" "$NC" "$(count_in agents '*.md')"
printf '  %sCommands%s  %s\n'   "$CYAN" "$NC" "$(count_in commands '*.md')"
printf '  %sSkills%s    %s\n'   "$CYAN" "$NC" "$(count_in skills 'SKILL.md')"
printf '  %sHooks%s     %s\n'   "$CYAN" "$NC" "$(count_hooks)"
printf '  %sRules%s     %s\n'   "$CYAN" "$NC" "$(count_in rules '*.md')"
printf '  %sTemplates%s %s\n'   "$CYAN" "$NC" "$(count_in templates '*.md')"
cat <<EOF

Next steps:
  1. Install the Unity MCP bridge — see MCP-SETUP.md (Window > MCP for Unity > Auto-Setup).
  2. Fill in the FILL: markers in CLAUDE.md — genre, pillars, vision, scope.
  3. Run 'claude' in your project and try /brainstorm, or /unity-audit for a health check.
  4. Health check any time: ./scripts/studio-doctor.sh --project-dir "$PROJECT_DIR"
EOF
exit 0
