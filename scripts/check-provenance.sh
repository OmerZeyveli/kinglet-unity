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
#
# THE INDEX IS PROVED READABLE FIRST. This loop's entire input is `git ls-files`, and the check is an
# ABSENCE check, so "no orphans" and "no files" produce the same green. Measured 2026-08-14 on a
# `git archive HEAD | tar -x` extraction — this repository's documented probe method, which has no
# index — this script printed:
#
#     fatal: not a git repository (or any of the parent directories): .git
#     pass no orphan files (0 tracked files covered)
#     ...
#     provenance OK                                              rc=0
#
# `provenance OK` over a repository whose files were never enumerated. The `0` was even in the
# message. CLAUDE.md's own account of what this script is for — "no rows without files, no files
# without rows ... that is what keeps a removed surface from silently returning" — was half true:
# the ghosts direction reads the manifest and held, the orphans direction read nothing.
#
# A floor rather than an equality, because the tracked count moves on most commits. It is compared
# against the manifest's own row count, which is the one number that must track it: the two are
# equal today by construction (every tracked file has a row), so requiring the index to be at least
# half the manifest catches an empty or truncated listing without pinning either number.
TRACKED_LIST=$(mktemp); TMP_PATHS=$(mktemp)
trap 'rm -f "$TMP_PATHS" "$TRACKED_LIST"' EXIT
paths | sort > "$TMP_PATHS"
TRACKED_RC=0
git ls-files 2>/dev/null | sort > "$TRACKED_LIST" || TRACKED_RC=$?
TRACKED_N=$(grep -c . "$TRACKED_LIST" || true)
ROWS_N=$(grep -c . "$TMP_PATHS" || true)
if [ "$TRACKED_RC" -ne 0 ] || [ "$TRACKED_N" -lt $((ROWS_N / 2)) ] || [ "$TRACKED_N" -eq 0 ]; then
  fail "git listed $TRACKED_N tracked file(s) against $ROWS_N manifest rows — the orphan check below read nothing, and its silence would certify a tree it never opened"
else
  pass "the tracked-file index is readable ($TRACKED_N file(s)), so the orphan check below means something"
fi

ORPHANS=0
while IFS= read -r f; do
  # The manifest describes itself and its own tooling loosely; skip nothing — every file gets a row.
  grep -qxF "$f" "$TMP_PATHS" || { fail "orphan file (no row): $f"; ORPHANS=$((ORPHANS + 1)); }
done < "$TRACKED_LIST"
[ "$ORPHANS" -eq 0 ] && pass "no orphan files ($TRACKED_N tracked files covered)"

# ── 4. status=verbatim must actually be verbatim ─────────────────────────────
# Offline, using the upstream_sha256 already recorded in the row. This check did not exist at first,
# and the manifest rotted immediately: a mobile sweep edited 38 vendored files and left every one of
# them marked `verbatim`, while this script reported "provenance OK". Deferring the comparison to
# --online made the everyday check unable to catch the everyday mistake.
LIED=0
while IFS=$'\t' read -r path origin _uver _upath usha status _note; do
  [ "$status" = verbatim ] || continue
  [ "$origin" != original ] || continue
  [ -f "$path" ] || continue
  [ -n "$usha" ] && [ "$usha" != "-" ] || continue
  actual=$(sha256sum "$path" 2>/dev/null | cut -d' ' -f1)
  if [ "$actual" != "$usha" ]; then
    fail "status=verbatim but the file differs from its recorded upstream: $path"
    LIED=$((LIED + 1))
  fi
done < <(rows)
if [ "$LIED" -eq 0 ]; then
  pass "every status=verbatim file matches its recorded upstream_sha256"
else
  printf '     %s\n' "Set status=modified and say why in the note column."
fi

# ── 5. Field sanity ──────────────────────────────────────────────────────────
BADFIELD=0
while IFS=$'\t' read -r path origin _uver _upath _usha status _note; do
  case "$origin" in ecu|donchitos|superpowers|original) ;; *) fail "bad origin '$origin': $path"; BADFIELD=$((BADFIELD + 1)) ;; esac
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
    # -E, not -P: PCRE mode is a GNU extension and BSD/macOS grep has no -P at all. The tab between
    # fields is a literal tab character ($'\t'), not the "\t" escape — POSIX ERE has no such escape
    # and only GNU grep accepts it as an extension.
    ours_wins_pattern="^$(printf '%s' "$skip_path" | sed 's/[.[\*^$]/\\&/g')"$'\t'"original"$'\t'
    if ! grep -qE -- "$ours_wins_pattern" "$MANIFEST"; then
      fail "rule=ours-wins but not marked origin=original: $skip_path"; MISCLAIM=$((MISCLAIM + 1))
    fi
  done < <(grep -v '^#' provenance-skip.tsv)
  [ "$MISCLAIM" -eq 0 ] && pass "every rule=ours-wins path is ours, not vendored"
else
  warn "provenance-skip.tsv not found — skip-list not enforced"
fi

# ── 6. --online: verbatim rows still match upstream ──────────────────────────
if [ "$ONLINE" -eq 1 ]; then
  # `|| true` is load-bearing. With the `# ecu=` header line ABSENT, grep exits 1, pipefail makes the
  # pipeline exit 1, and `set -e` kills the script on the assignment itself — so the warn branch two
  # lines down, which exists precisely for that case, was unreachable. Measured 2026-08-11 against a
  # manifest with that one line stripped: the script died after "every rule=ours-wins path is ours",
  # printing neither "skipping --online" (0 occurrences) nor its own summary line, and exited 1 with
  # no explanation of what was wrong. The MALFORMED-pin case never had this problem — grep matches,
  # sed prints nothing, rc is 0, and the warn printed correctly — which is why it read as covered.
  ECU_COMMIT=$(grep -m1 '^# ecu=' "$MANIFEST" | sed -n 's/.*(\([0-9a-f]\{40\}\)).*/\1/p' || true)
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
