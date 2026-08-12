#!/usr/bin/env bash
# Self-contained: defines its own helpers, safe to run standalone.
#
# A surface that ships into a user's Unity project can only cite what that user has. Eight citations
# in four shipped skills once pointed at `sourced-incidents.md` — a document that was never deleted
# because it never existed — and seven paths named files install.sh does not copy, one of them a
# rule instructing the reader to inspect a test and report a regression.
set -euo pipefail

# ${BASH_SOURCE[0]}, not $0: the runner does `( source "$test_file" )`, and inside a sourced file $0
# is the *sourcing* shell's $0.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

# PASS/FAIL, not ok/FAIL: run-tests.sh aggregates by grepping each file's output for those tokens.
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'PASS: %s\n' "$1"; }

# The installed payload, derived the way install.sh derives it — not hardcoded. install.sh:175 takes
# every file under .claude/ except state/, and :379-390 copies scripts/*.sh into .claude/scripts/
# with exactly one exclusion. A hardcoded list goes stale the first time the payload changes.
payload_paths() {
  ( cd "$REPO/.claude" && find . -type f ! -path './state/*' | sed 's|^\./|.claude/|' )
  for f in "$REPO"/scripts/*.sh; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    # `[ x = y ] && continue` as the last command in a loop body exits 1 under set -e. Use if/then.
    if [ "$b" = "check-provenance.sh" ]; then continue; fi
    printf '.claude/scripts/%s\n' "$b"
  done
}
PAYLOAD="$(payload_paths)"

# Every Markdown file that ships.
SHIPPED_MD="$(find "$REPO/.claude" -name '*.md' | sort)"
MD_COUNT="$(printf '%s\n' "$SHIPPED_MD" | grep -c . || true)"

# 0. Coverage floors. A guard that silently stops reading its subject reports green forever. These
# are derived-with-headroom from the tree on 2026-08-11: 44 shipped .md files, 85 payload entries.
# Raise them when the tree grows; never lower one to make a run pass.
if [ "$MD_COUNT" -ge 35 ]; then
  pass "guard scanned $MD_COUNT shipped .md files (floor 35)"
else
  fail "guard scanned only $MD_COUNT shipped .md files — expected at least 35; it has stopped reading its subject"
fi

PAYLOAD_COUNT="$(printf '%s\n' "$PAYLOAD" | grep -c . || true)"
if [ "$PAYLOAD_COUNT" -ge 70 ]; then
  pass "payload derivation produced $PAYLOAD_COUNT entries (floor 70)"
else
  fail "payload derivation produced only $PAYLOAD_COUNT entries — expected at least 70; install.sh's layout has changed or the derivation is broken"
fi

# 1. No section marker in any shipped .md. The one exception is NOTICE.md's own §3, which names a
# section of the file it appears in and therefore resolves. §3[^0-9] so that a future §30 is caught.
sec_hits=""
while IFS= read -r md; do
  [ -n "$md" ] || continue
  m="$(grep -n '§[0-9]' "$md" || true)"
  [ -n "$m" ] || continue
  sec_hits="$sec_hits$(printf '%s\n' "$m" | sed "s|^|${md#"$REPO"/}:|")"$'\n'
done <<< "$SHIPPED_MD"

sec_bad="$(printf '%s' "$sec_hits" | grep -v '^\.claude/NOTICE\.md:[0-9][0-9]*:.*§3[^0-9]' || true)"
sec_bad_n="$(printf '%s' "$sec_bad" | grep -c . || true)"

if [ "$sec_bad_n" -eq 0 ]; then
  pass "no shipped surface carries a § section marker (NOTICE.md's own §3 excepted)"
else
  fail "$sec_bad_n shipped citation(s) carry a § marker that resolves to nothing:"
  printf '%s' "$sec_bad" | sed 's/^/       /'
fi

[ "$FAILURES" -eq 0 ] || exit 1
printf 'all shipped-citation assertions passed\n'
