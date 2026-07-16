#!/usr/bin/env bash
#
# check-provenance.sh — validate provenance.tsv against the working tree.
#
# The manifest is the evidence behind CREDITS.md, so it has to stay true. This checks it
# bidirectionally: no ghosts (rows without files) and no orphans (files without rows). One-way
# checking is what lets a manifest quietly rot.
#
# Usage:
#   ./scripts/check-provenance.sh [--online]
#
#   --online   Additionally re-fetch upstream and verify every status=verbatim row still matches
#              its recorded upstream_sha256. Requires git and network.
#
# Exits non-zero on any inconsistency.
#
set -euo pipefail

usage() { sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi
pass() { printf '%s\n' "${GREEN}pass${NC} $*"; }
fail() { printf '%s\n' "${RED}FAIL${NC} $*" >&2; FAILED=$((FAILED + 1)); }
warn() { printf '%s\n' "${YELLOW}warn${NC} $*"; }

ONLINE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --online) ONLINE=1; shift ;;
    -h|--help) usage ;;
    *) printf 'Unknown argument: %s (use --help)\n' "$1" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
MANIFEST=provenance.tsv
FAILED=0

[ -f "$MANIFEST" ] || { printf '%s\n' "${RED}err${NC} $MANIFEST not found" >&2; exit 1; }

printf '%s\n' "${BOLD}provenance check${NC} — $REPO_ROOT"

# Rows, minus comments and the column header.
rows()  { grep -v '^#' "$MANIFEST" | tail -n +2; }
paths() { rows | cut -f1; }

# ── 1. No duplicate rows ─────────────────────────────────────────────────────
DUPES=$(paths | sort | uniq -d)
if [ -n "$DUPES" ]; then
  while IFS= read -r p; do fail "duplicate row: $p"; done <<< "$DUPES"
else
  pass "no duplicate rows"
fi

# ── 2. No ghosts — every row points at a real file ───────────────────────────
GHOSTS=0
while IFS= read -r p; do
  [ -f "$p" ] || { fail "ghost row (file missing): $p"; GHOSTS=$((GHOSTS + 1)); }
done < <(paths)
[ "$GHOSTS" -eq 0 ] && pass "no ghost rows ($(paths | wc -l | tr -d ' ') rows resolve to files)"

# ── 3. No orphans — every tracked file has a row ─────────────────────────────
ORPHANS=0
TMP_PATHS=$(mktemp); paths | sort > "$TMP_PATHS"
trap 'rm -f "$TMP_PATHS"' EXIT
while IFS= read -r f; do
  # The manifest describes itself and its own tooling loosely; skip nothing — every file gets a row.
  grep -qxF "$f" "$TMP_PATHS" || { fail "orphan file (no row): $f"; ORPHANS=$((ORPHANS + 1)); }
done < <(git ls-files | sort)
[ "$ORPHANS" -eq 0 ] && pass "no orphan files ($(git ls-files | wc -l | tr -d ' ') tracked files covered)"

# ── 4. Field sanity ──────────────────────────────────────────────────────────
BADFIELD=0
while IFS=$'\t' read -r path origin _uver _upath _usha status _note; do
  case "$origin" in ecu|donchitos|original) ;; *) fail "bad origin '$origin': $path"; BADFIELD=$((BADFIELD + 1)) ;; esac
  case "$status" in verbatim|modified|original) ;; *) fail "bad status '$status': $path"; BADFIELD=$((BADFIELD + 1)) ;; esac
  # An 'original' file cannot have an upstream, and a vendored file must have one.
  if [ "$origin" = original ] && [ "$status" != original ]; then
    fail "origin=original must have status=original: $path"; BADFIELD=$((BADFIELD + 1))
  fi
  if [ "$origin" != original ] && [ "$status" = original ]; then
    fail "vendored file cannot have status=original: $path"; BADFIELD=$((BADFIELD + 1))
  fi
done < <(rows)
[ "$BADFIELD" -eq 0 ] && pass "field values sane (origin, status, and their agreement)"

# ── 5. Mobile has not crept back in ──────────────────────────────────────────
# provenance-skip.tsv records what we deliberately left behind. A re-vendor that quietly reinstates
# a skipped path would otherwise pass every check above.
if [ -f provenance-skip.tsv ]; then
  CREPT=0; ENFORCED=0
  while IFS=$'\t' read -r skip_path _up rule _reason; do
    case "$skip_path" in ''|\#*) continue ;; esac
    # Only rule=absent is a prohibition. rule=ours-wins means the path exists on purpose with our
    # content — flagging it would be conflating "we didn't vendor theirs" with "nothing may live here".
    [ "$rule" = absent ] || continue
    ENFORCED=$((ENFORCED + 1))
    if [ -e "$skip_path" ]; then fail "skipped path reappeared: $skip_path"; CREPT=$((CREPT + 1)); fi
  done < <(grep -v '^#' provenance-skip.tsv)
  [ "$CREPT" -eq 0 ] && pass "no prohibited path present ($ENFORCED rule=absent entries enforced)"

  # rule=ours-wins paths must exist AND be marked origin=original — otherwise we silently vendored
  # upstream's copy over our own.
  MISCLAIM=0
  while IFS=$'\t' read -r skip_path _up rule _reason; do
    case "$skip_path" in ''|\#*) continue ;; esac
    [ "$rule" = ours-wins ] || continue
    [ -e "$skip_path" ] || continue   # e.g. .claude/VERSION before it is written
    if ! grep -qP "^$(printf '%s' "$skip_path" | sed 's/[.[\*^$]/\\&/g')\toriginal\t" "$MANIFEST"; then
      fail "rule=ours-wins but not marked origin=original: $skip_path"; MISCLAIM=$((MISCLAIM + 1))
    fi
  done < <(grep -v '^#' provenance-skip.tsv)
  [ "$MISCLAIM" -eq 0 ] && pass "every rule=ours-wins path is ours, not vendored"
else
  warn "provenance-skip.tsv not found — skip-list not enforced"
fi

# ── 6. --online: verbatim rows still match upstream ──────────────────────────
if [ "$ONLINE" -eq 1 ]; then
  ECU_COMMIT=$(grep -m1 '^# ecu=' "$MANIFEST" | sed -n 's/.*(\([0-9a-f]\{40\}\)).*/\1/p')
  if [ -z "$ECU_COMMIT" ]; then
    warn "could not read the pinned ECU commit from $MANIFEST header — skipping --online"
  else
    TMP_ECU=$(mktemp -d); trap 'rm -f "$TMP_PATHS"; rm -rf "$TMP_ECU"' EXIT
    printf 'fetching ECU %s …\n' "${ECU_COMMIT:0:7}"
    git clone --quiet https://github.com/XeldarAlz/everything-claude-unity.git "$TMP_ECU" 2>/dev/null
    git -C "$TMP_ECU" checkout --quiet "$ECU_COMMIT"
    DRIFT=0
    while IFS=$'\t' read -r path origin _uver upath usha status _note; do
      [ "$origin" = ecu ] || continue
      [ "$status" = verbatim ] || continue
      [ -f "$TMP_ECU/$upath" ] || { fail "upstream path gone: $upath"; DRIFT=$((DRIFT + 1)); continue; }
      actual=$(sha256sum "$TMP_ECU/$upath" | cut -d' ' -f1)
      [ "$actual" = "$usha" ] || { fail "recorded upstream_sha256 wrong: $path"; DRIFT=$((DRIFT + 1)); continue; }
      cmp -s "$TMP_ECU/$upath" "$path" || { fail "status=verbatim but differs from upstream: $path"; DRIFT=$((DRIFT + 1)); }
    done < <(rows)
    [ "$DRIFT" -eq 0 ] && pass "every status=verbatim row matches upstream at ${ECU_COMMIT:0:7}"
  fi
fi

printf '\n'
if [ "$FAILED" -gt 0 ]; then
  printf '%s\n' "${RED}${BOLD}provenance check FAILED${NC} — $FAILED problem(s)"
  exit 1
fi
printf '%s\n' "${GREEN}${BOLD}provenance OK${NC}"
