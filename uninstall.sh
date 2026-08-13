#!/usr/bin/env bash
#
# Kinglet Pioneer — uninstaller
#
# Removes what install.sh owns, and nothing else. Every removal is checked against the install
# receipt: a file goes only if the receipt marks it ours AND it still carries the checksum we
# recorded. A file the receipt marks yours stays, whatever its checksum says, unless --purge.
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

printf '%s\n' "${BOLD}Kinglet Pioneer — uninstaller${NC}"
info "Project: $PROJECT_DIR"

[ -d "$CLAUDE_DIR" ] || die "No .claude/ directory in $PROJECT_DIR — nothing to remove."

if [ ! -f "$RECEIPT" ]; then
  err "No install receipt at ${RECEIPT#"$PROJECT_DIR"/}."
  err ""
  err "Kinglet did not install this .claude/ — or it was installed by someone else and"
  err "reached you through git, which does not carry the receipt (it is machine-local by design:"
  err "it records what was written to THIS filesystem)."
  err ""
  err "Refusing to guess which files are ours. Remove .claude/ by hand if you are sure."
  exit 1
fi

# A missing file hashes to the empty string. Same helper, same reasoning, same day as install.sh's:
# the old body was safe only because the one caller below checks `[ ! -f "$abs" ]` first, so the
# contract "existence is the caller's problem" was enforced nowhere. sha256sum exits 1 on a missing
# path and pipefail promotes it through the `| cut`.
#
# The direction is fail-closed either way: an empty checksum never equals a recorded one, so the row
# lands in MODIFIED and the file is KEPT rather than removed.
sha_of() {
  [ -f "$1" ] || return 0
  sha256sum "$1" | cut -d' ' -f1
}

# ── Classify every receipted file before touching anything ───────────────────
# TWO TESTS, NOT ONE, because two different questions are being asked of one row.
#
# `user-modified` means a previous install found your edit and kept it — and recorded the file AS
# EDITED, deliberately, so that the NEXT install still recognises it as yours. (Without that, the
# edit survived exactly one upgrade and the second silently overwrote it; commit c2d27f1f,
# 2026-08-03.) So the checksum on a `user-modified` row is the checksum of YOUR file, and comparing
# against it always matched — which is how a plain `uninstall.sh --yes` came to count an edited file
# under "unchanged since install" and delete it. Measured on a fixture and reproduced twice
# independently before this was written.
#
# The sha test is right for `toolkit` rows and only for them: there it separates "we installed it and
# nobody touched it" from "we installed it and someone did" — an edit made AFTER the last install,
# which is the only kind that row can express.
#
# The origin column had been written in three places and read in one (install.sh's own upgrade
# scan). This is the second reader.
#
# AN ORIGIN WE CANNOT READ IS KEPT, NOT DELETED. `case` with an explicit catch-all, rather than an
# if/elif that lets anything unrecognised fall through to the sha test: a row carrying a trailing
# space, a CRLF line ending, or a fifth column is no longer byte-equal to `user-modified`, and under
# a fall-through it would be deleted — the exact data loss this block was written to stop, arriving
# through a typo instead of through a design decision. A file whose provenance cannot be read is not
# ours to delete.
#
# Failing closed costs nothing real here. `git show 5e0bf23:install.sh` — the commit that introduced
# the receipt at all — already writes four columns ending in `toolkit`, so no three-column legacy
# receipt has ever existed and no shipped receipt has ever carried an origin outside these two
# values. The catch-all defends against a hand-edited or transport-mangled receipt, and its cost is
# a file left on disk and reported, which the user can delete, instead of a file deleted, which they
# cannot undelete.
TO_REMOVE=""; MODIFIED=""; ALREADY_GONE=0
while IFS=$'\t' read -r rel recorded _mode origin; do
  case "$rel" in ''|\#*|path) continue ;; esac
  abs="$PROJECT_DIR/$rel"
  if [ ! -f "$abs" ]; then ALREADY_GONE=$((ALREADY_GONE + 1)); continue; fi
  case "$origin" in
    user-modified)
      MODIFIED="${MODIFIED}${rel}"$'\n'
      ;;
    toolkit)
      if [ "$(sha_of "$abs")" = "$recorded" ]; then
        TO_REMOVE="${TO_REMOVE}${rel}"$'\n'
      else
        MODIFIED="${MODIFIED}${rel}"$'\n'
      fi
      ;;
    *)
      MODIFIED="${MODIFIED}${rel}"$'\n'
      ;;
  esac
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
# CLAUDE.md.generated is NOT in this list, and naming it is the whole point of the parenthesis. It
# used to be absent from the receipt entirely, so it survived every uninstall and the line was
# accidentally right about it; once install.sh started claiming it, a plain uninstall began removing
# it while this line still read as a promise covering the whole CLAUDE.md family. The promise is
# narrowed rather than turned into an outcome claim: an edited one is reported under "keep N file(s)
# you modified" in the plan above and stays, so "it is removed" would be false in that direction.
printf 'Left alone: CLAUDE.md (not CLAUDE.md.generated), docs/, and anything you wrote.\n'
exit 0
