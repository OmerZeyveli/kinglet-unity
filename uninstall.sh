#!/usr/bin/env bash
#
# cloud-nine-unity — uninstaller
#
# Removes what install.sh wrote, and nothing else. Every removal is checked against the install
# receipt: a file is deleted only if its checksum still matches what we recorded writing. If you
# edited it, or it was never ours, it stays.
#
# Usage:
#   ./uninstall.sh [--project-dir <path>] [--yes] [--purge] [--keep-local] [--no-backup]
#
#   --project-dir <path>  Target Unity project root (default: current directory)
#   --yes, -y             Skip the confirmation prompt
#   --purge               Also remove files you modified (default: keep and report them)
#   --keep-local          Preserve .claude/settings.local.json
#   --no-backup           Skip the backup of .claude/ before removal
#   -h, --help            Show this help
#
# Without a receipt this refuses to run. The previous version deleted by filename with no
# provenance check, so it would happily delete a file it had never installed — and then print
# "ECU is untouched", which was an assertion rather than something it enforced.
#
set -euo pipefail

if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi
info() { printf '%s\n' "${BLUE}==>${NC} $*"; }
ok()   { printf '%s\n' "${GREEN} ok${NC}  $*"; }
warn() { printf '%s\n' "${YELLOW}warn${NC} $*"; }
err()  { printf '%s\n' "${RED}err ${NC} $*" >&2; }
die()  { err "$*"; exit 1; }

usage() { sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

PROJECT_DIR="$(pwd)"
ASSUME_YES=0; PURGE=0; KEEP_LOCAL=0; NO_BACKUP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) [ $# -ge 2 ] || die "--project-dir requires a path"; PROJECT_DIR="$2"; shift 2 ;;
    --yes|-y)      ASSUME_YES=1; shift ;;
    --purge)       PURGE=1; shift ;;
    --keep-local)  KEEP_LOCAL=1; shift ;;
    --no-backup)   NO_BACKUP=1; shift ;;
    -h|--help)     usage ;;
    *)             die "Unknown argument: $1 (use --help)" ;;
  esac
done

PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || die "Project directory not found"
CLAUDE_DIR="$PROJECT_DIR/.claude"
RECEIPT="$CLAUDE_DIR/state/install-receipt.tsv"

printf '%s\n' "${BOLD}cloud-nine-unity — uninstaller${NC}"
info "Project: $PROJECT_DIR"

[ -d "$CLAUDE_DIR" ] || die "No .claude/ directory in $PROJECT_DIR — nothing to remove."

if [ ! -f "$RECEIPT" ]; then
  err "No install receipt at ${RECEIPT#"$PROJECT_DIR"/}."
  err ""
  err "cloud-nine-unity did not install this .claude/ — or it was installed by someone else and"
  err "reached you through git, which does not carry the receipt (it is machine-local by design:"
  err "it records what was written to THIS filesystem)."
  err ""
  err "Refusing to guess which files are ours. Remove .claude/ by hand if you are sure."
  exit 1
fi

sha_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# ── Classify every receipted file before touching anything ───────────────────
TO_REMOVE=""; MODIFIED=""; ALREADY_GONE=0
while IFS=$'\t' read -r rel recorded _mode _origin; do
  case "$rel" in ''|\#*|path) continue ;; esac
  abs="$PROJECT_DIR/$rel"
  if [ ! -f "$abs" ]; then ALREADY_GONE=$((ALREADY_GONE + 1)); continue; fi
  if [ "$(sha_of "$abs")" = "$recorded" ]; then
    TO_REMOVE="${TO_REMOVE}${rel}"$'\n'
  else
    MODIFIED="${MODIFIED}${rel}"$'\n'
  fi
done < <(grep -v '^#' "$RECEIPT")

REMOVE_COUNT=$(printf '%s' "$TO_REMOVE" | grep -c . || true)
MOD_COUNT=$(printf '%s' "$MODIFIED" | grep -c . || true)

# Anything under .claude/ the receipt never mentioned belongs to the user, not us.
RECEIPTED=$(mktemp); trap 'rm -f "$RECEIPTED"' EXIT
grep -v '^#' "$RECEIPT" | tail -n +2 | cut -f1 | sort > "$RECEIPTED"
FOREIGN_COUNT=0
while IFS= read -r f; do
  rel="${f#"$PROJECT_DIR"/}"
  case "$rel" in .claude/state/*) continue ;; esac
  grep -qxF "$rel" "$RECEIPTED" || FOREIGN_COUNT=$((FOREIGN_COUNT + 1))
done < <(find "$CLAUDE_DIR" -type f)

printf '\n%s\n' "${BOLD}Plan${NC}"
printf '  remove   %s file(s) — unchanged since install\n' "$REMOVE_COUNT"
if [ "$MOD_COUNT" -gt 0 ]; then
  if [ "$PURGE" -eq 1 ]; then
    printf '  %sremove   %s file(s) you modified (--purge)%s\n' "$YELLOW" "$MOD_COUNT" "$NC"
  else
    printf '  %skeep     %s file(s) you modified%s\n' "$GREEN" "$MOD_COUNT" "$NC"
    printf '%s' "$MODIFIED" | while IFS= read -r m; do [ -n "$m" ] && printf '             %s\n' "$m"; done
  fi
fi
[ "$FOREIGN_COUNT" -gt 0 ] && printf '  %skeep     %s file(s) we never installed%s\n' "$GREEN" "$FOREIGN_COUNT" "$NC"
[ "$ALREADY_GONE" -gt 0 ] && printf '  skip     %s file(s) already gone\n' "$ALREADY_GONE"
printf '\n'

if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
  read -rp "  Continue? [y/N] " REPLY
  case "$REPLY" in y|Y|yes|Yes) ;; *) info "Aborted."; exit 0 ;; esac
fi

# ── Backup ───────────────────────────────────────────────────────────────────
if [ "$NO_BACKUP" -eq 0 ]; then
  BACKUP_DIR="$PROJECT_DIR/.claude.backup.$(date +%Y%m%d%H%M%S)"
  cp -r "$CLAUDE_DIR" "$BACKUP_DIR"
  ok "Backup: $(basename "$BACKUP_DIR")/"
fi

SAVED_LOCAL=""
if [ "$KEEP_LOCAL" -eq 1 ] && [ -f "$CLAUDE_DIR/settings.local.json" ]; then
  SAVED_LOCAL="$PROJECT_DIR/.claude-settings-local.json.saved"
  cp "$CLAUDE_DIR/settings.local.json" "$SAVED_LOCAL"
fi

# ── Remove ───────────────────────────────────────────────────────────────────
REMOVED=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  rm -f "$PROJECT_DIR/$rel"; REMOVED=$((REMOVED + 1))
done <<< "$TO_REMOVE"

if [ "$PURGE" -eq 1 ] && [ "$MOD_COUNT" -gt 0 ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    rm -f "$PROJECT_DIR/$rel"; REMOVED=$((REMOVED + 1))
  done <<< "$MODIFIED"
  warn "Purged $MOD_COUNT modified file(s)."
fi
ok "Removed $REMOVED file(s)."

rm -f "$RECEIPT"
# Prune directories that went empty, deepest first. A directory still holding a user's file
# survives on its own — rmdir refuses a non-empty dir, so no special-casing is needed.
find "$CLAUDE_DIR" -depth -type d -empty -exec rmdir {} + 2>/dev/null || true

if [ -d "$CLAUDE_DIR" ]; then
  LEFT=$(find "$CLAUDE_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
  info ".claude/ kept — $LEFT file(s) there are not ours to remove."
else
  ok ".claude/ removed entirely."
fi
[ -n "$SAVED_LOCAL" ] && ok "Preserved settings.local.json → $(basename "$SAVED_LOCAL")"

printf '\n%s\n' "${BOLD}${GREEN}Uninstalled.${NC}"
printf 'Left alone: CLAUDE.md, docs/, and anything you wrote.\n'
exit 0
