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
# ONE THING IS REVERSED OUTSIDE THE PROJECT, and only if the install put it there. `install.sh
# --client codex --codex-trust` appends Codex hook-trust tables to your $CODEX_HOME/config.toml.
# This removes exactly those tables — identified by the keys recorded at install time, each of
# which names this project's own hooks.json — after copying that file. Nothing else in your home
# is read or written, and the Plan below names the file before you confirm.
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

usage() { sed -n '3,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

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
#
# THE EXISTENCE TEST IS `-e` OR `-L`, NOT `-f`, AND THE ROWS THAT NEEDED THAT ARE THE CODEX SKILL
# ROOT'S. `.agents/skills/<name>` is a symlink to a DIRECTORY, and `-f` follows the link and then
# asks "is the target a regular file", which is false. Under the old test every one of those rows
# counted as `already gone`, so the whole skill bridge survived every uninstall while the run
# reported success — a file left behind by a check that could not see it. `-L` is the second
# disjunct rather than a replacement because `-e` is false through a DANGLING link, and a dangling
# link of ours is exactly what we most want to remove.
#
# A row whose path is now a directory falls through to the classifier and is KEPT: `sha_of` returns
# the empty string for it, no recorded checksum equals that, so it lands in MODIFIED. Fail-closed,
# by the same mechanism as everything else here.
TO_REMOVE=""; MODIFIED=""; ALREADY_GONE=0
while IFS=$'\t' read -r rel recorded mode origin; do
  case "$rel" in ''|\#*|path) continue ;; esac
  abs="$PROJECT_DIR/$rel"
  if [ ! -e "$abs" ] && [ ! -L "$abs" ]; then ALREADY_GONE=$((ALREADY_GONE + 1)); continue; fi
  case "$origin" in
    user-modified)
      MODIFIED="${MODIFIED}${rel}"$'\n'
      ;;
    toolkit)
      # TWO PROOFS OF OWNERSHIP FOR TWO KINDS OF FILE, chosen by the mode column, which until this
      # row existed was written by three writers and read by none.
      #
      # A symlink has no sha256 — `sha_of` returns the empty string for one pointing at a directory
      # — so the checksum test can only ever answer "modified" for it, and the file would be kept
      # forever. What install.sh actually recorded for these rows is the LINK TARGET, and that is
      # the right thing to check: the link is ours while it still points where we pointed it, and
      # the moment someone repoints it, it is theirs.
      if [ "$mode" = symlink ]; then
        if [ -L "$abs" ] && [ "$(readlink "$abs")" = "$recorded" ]; then
          TO_REMOVE="${TO_REMOVE}${rel}"$'\n'
        else
          MODIFIED="${MODIFIED}${rel}"$'\n'
        fi
      elif [ "$(sha_of "$abs")" = "$recorded" ]; then
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

# ── The one thing this uninstaller reverses that is not a file of ours ───────
#
# `install.sh --client codex --codex-trust` appends one `[hooks.state."<key>"]` table per hook to
# the user's `$CODEX_HOME/config.toml`. That file is OUTSIDE the project and it is the user's own —
# it carries their model settings, their approval policy, their trust decisions about every other
# repository — so it can never be a receipt row, because every receipt row means "this path is ours
# to delete". What is ours is the TABLES, and they are recorded as data in a file that is ours:
# .claude/state/codex-trust.tsv, which carries its own ordinary row and is removed with the rest.
#
# READ BEFORE ANYTHING IS DELETED, and announced in the Plan below, because a user about to approve
# an uninstall is owed the fact that something outside their project will be edited.
TRUST_REC="$CLAUDE_DIR/state/codex-trust.tsv"
TRUST_CFG=""; TRUST_MARK=""; TRUST_KEY_COUNT=0
if [ -f "$TRUST_REC" ]; then
  TRUST_CFG=$(awk -F': ' '/^# config: /{sub(/^# config: /, ""); print; exit}' "$TRUST_REC")
  TRUST_MARK=$(awk '/^# marker: /{sub(/^# marker: /, ""); print; exit}' "$TRUST_REC")
  # Absent in a record written before this field existed, and `yes` is the right reading of an
  # absent value: it means "do not strip", which leaves the file as the removal pass produced it.
  TRUST_HAD_NL=$(awk '/^# original-trailing-newline: /{sub(/^# original-trailing-newline: /, ""); print; exit}' "$TRUST_REC")
  [ -n "$TRUST_HAD_NL" ] || TRUST_HAD_NL=yes
  TRUST_KEY_COUNT=$(awk -F'\t' 'NR>1 && !/^#/ && NF>=1 && $1 != "key" && $1 != "" {n++} END {print n+0}' "$TRUST_REC")
fi

printf '\n%s\n' "${BOLD}Plan${NC}"
printf '  remove   %s file(s) — unchanged since install\n' "$REMOVE_COUNT"
if [ -n "$TRUST_CFG" ] && [ "$TRUST_KEY_COUNT" -gt 0 ]; then
  if [ -f "$TRUST_CFG" ]; then
    printf '  %sedit     %s — OUTSIDE THIS PROJECT: remove %s Codex hook-trust table(s)%s\n' \
      "$YELLOW" "$TRUST_CFG" "$TRUST_KEY_COUNT" "$NC"
  else
    printf '  skip     %s is gone — %s Codex hook-trust table(s) already unreachable\n' \
      "$TRUST_CFG" "$TRUST_KEY_COUNT"
  fi
fi
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

# ── Reverse the home write, before the record that describes it is deleted ───
#
# EXACTLY THE TABLES THIS PROJECT'S INSTALL ADDED, identified by the keys recorded at install time —
# and every one of those keys embeds the absolute path of THIS project's .codex/hooks.json, so a
# hook-trust table belonging to another repository cannot match one of them. The marker comment goes
# with them.
#
# The user's file is copied first, for the same reason install.sh copied it: it is outside the
# project, so `git checkout` is not a route back for them.
if [ -n "$TRUST_CFG" ] && [ "$TRUST_KEY_COUNT" -gt 0 ] && [ -f "$TRUST_CFG" ] && [ ! -w "$TRUST_CFG" ]; then
  # THE SAME REFUSAL install.sh MAKES, IN THE OTHER DIRECTION. A config the user has made read-only
  # is a decision, and the right response to it is to say what is left behind rather than to find a
  # way around it. Reported rather than merely skipped: the tables become inert the moment the
  # hooks.json they name is removed below, and the user is owed the sentence that says so.
  err "$TRUST_CFG is not writable — its $TRUST_KEY_COUNT hook-trust table(s) were NOT removed."
  err "They name this project's .codex/hooks.json, which this run removes, so they are inert;"
  err "make that file writable and delete the [hooks.state.\"...\"] tables naming $PROJECT_DIR."
elif [ -n "$TRUST_CFG" ] && [ "$TRUST_KEY_COUNT" -gt 0 ] && [ -f "$TRUST_CFG" ]; then
  TRUST_KEYS=$(mktemp)
  awk -F'\t' 'NR>1 && !/^#/ && $1 != "key" && $1 != "" {print $1}' "$TRUST_REC" > "$TRUST_KEYS"
  TRUST_TMP=$(mktemp)
  TRUST_BAK="$TRUST_CFG.kinglet-uninstall.$(date +%Y%m%d%H%M%S)"
  # `cat >` RATHER THAN `mv`, FOR THE REASON install.sh's TWIN CARRIES IN FULL: `mv` from `mktemp`
  # replaces the inode and takes 0600 with it, so an uninstall silently re-moded a 644 home config
  # to 600 — measured. Rewriting the existing inode preserves mode and ownership by construction,
  # and the backup one line up is what covers the atomicity it gives up.
  if cp "$TRUST_CFG" "$TRUST_BAK" 2>/dev/null \
     && awk -v keyfile="$TRUST_KEYS" -v mark="$TRUST_MARK" '
          BEGIN { while ((getline k < keyfile) > 0) { drop["[hooks.state.\"" k "\"]"] = 1 } }
          {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (mark != "" && line == mark) { next }
            if (line in drop) { inblock = 1; next }
            if (inblock && line ~ /^\[/) { inblock = 0 }
            if (inblock) { next }
            print
          }
        ' "$TRUST_CFG" > "$TRUST_TMP" \
     && cat "$TRUST_TMP" > "$TRUST_CFG"; then
    # THE LAST BYTE, GIVEN BACK. The install had to add a newline before appending its block, or the
    # marker would have landed on the end of the user's last line — so a config that arrived without
    # a trailing newline left with one. The removal pass alone therefore returns a file one byte
    # longer than the one that was given, which is exactly as much of an unannounced change as the
    # file mode was. `head -c` on a FILE ARGUMENT, so nothing pipes into an early-exit reader; the
    # inode is rewritten rather than replaced, for the mode reason above.
    if [ "$TRUST_HAD_NL" = "no" ] && [ -s "$TRUST_CFG" ] && [ -z "$(tail -c1 "$TRUST_CFG")" ]; then
      TRUST_SZ=$(wc -c < "$TRUST_CFG" | tr -d ' ')
      if head -c "$((TRUST_SZ - 1))" "$TRUST_CFG" > "$TRUST_TMP"; then
        cat "$TRUST_TMP" > "$TRUST_CFG"
      fi
    fi
    ok "Removed $TRUST_KEY_COUNT hook-trust table(s) from $TRUST_CFG"
    ok "Its backup: $TRUST_BAK"
    # Bounded, on the same rule and for the same reason as install.sh's: nothing else reaps these,
    # and an uninstall-reinstall cycle would otherwise leave one copy per cycle in the user's home
    # forever. Newest three of OUR uninstall pattern; install's backups are left alone, because they
    # are the copy that predates everything this run just undid.
    TRUST_REAP=$(mktemp)
    for tb in "$TRUST_CFG".kinglet-uninstall.*; do
      if [ -f "$tb" ]; then printf '%s\n' "$tb" >> "$TRUST_REAP"; fi
    done
    TRUST_REAPED=0
    while IFS= read -r tb; do
      [ -n "$tb" ] || continue
      rm -f "$tb" && TRUST_REAPED=$((TRUST_REAPED + 1))
    done <<< "$(sort -r "$TRUST_REAP" 2>/dev/null | awk 'NR > 3' || true)"
    rm -f "$TRUST_REAP"
    [ "$TRUST_REAPED" -eq 0 ] || info "Reaped $TRUST_REAPED older uninstall backup(s); the newest 3 are kept."
  else
    err "Could not edit $TRUST_CFG — its hook-trust tables are still there."
    err "They name this project's .codex/hooks.json, which is about to be removed, so they are inert;"
    err "delete the [hooks.state.\"...\"] tables naming $PROJECT_DIR by hand if you want them gone."
  fi
  rm -f "$TRUST_KEYS" "$TRUST_TMP"
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
# THE CODEX LAYOUT'S TWO DIRECTORIES, ON THE SAME RULE AND FOR A SHARPER REASON. `.agents/skills/`
# emptied of its entries is still a skill ROOT: Codex reads it, finds nothing, and reports nothing —
# so an empty one is indistinguishable from a working one from inside a session. `.codex/` emptied
# is milder but is equally not something the user asked to keep. Both are pruned only when empty,
# so a `.codex/config.toml` the user wrote themselves — which gets no receipt row and is never
# removed above — keeps its directory.
#
# ONE `find` PASS IS NOT ENOUGH, AND THAT IS A PROPERTY OF `-exec … +` RATHER THAN OF THE LAYOUT.
# The batching form defers every `rmdir` to the end of the walk, so `-empty` is evaluated against
# the tree as it stood BEFORE any removal: `.agents/` still holds `skills/` at that moment and is
# therefore not empty, and one pass leaves it standing. Measured — `.agents/` survived a complete
# uninstall, which is worse than it sounds, because an empty `.agents/skills/` is still a skill root
# Codex reads and finds nothing in, and reports nothing about. The layout is three levels deep at
# `.agents/skills/<command>/`, so it takes three passes; the loop runs until a pass changes nothing
# rather than counting them, and is bounded so a pathological tree cannot spin.
for cdx in "$PROJECT_DIR/.agents" "$PROJECT_DIR/.codex"; do
  cdx_pass=0
  while [ -d "$cdx" ] && [ "$cdx_pass" -lt 8 ]; do
    cdx_before=$(find "$cdx" -type d 2>/dev/null | wc -l | tr -d ' ')
    find "$cdx" -depth -type d -empty -exec rmdir {} + 2>/dev/null || true
    [ -d "$cdx" ] || break
    cdx_after=$(find "$cdx" -type d 2>/dev/null | wc -l | tr -d ' ')
    if [ "$cdx_before" = "$cdx_after" ]; then break; fi
    cdx_pass=$((cdx_pass + 1))
  done
done

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
