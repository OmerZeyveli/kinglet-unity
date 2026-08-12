#!/usr/bin/env bash
# Self-contained: defines its own helpers, safe to run standalone.
#
# A surface that ships into a user's Unity project can only cite what that user has. Eight section
# markers across three shipped skills abbreviated a citation to a repository-only document — the
# numbers resolve, against docs/research/pioneer/field-notes.md, which is tracked and does not ship —
# and eight backticked paths named files install.sh does not copy, one of them a rule instructing the
# reader to inspect a test and report a regression.
set -euo pipefail

# ${BASH_SOURCE[0]}, not $0: the runner does `( source "$test_file" )`, and inside a sourced file $0
# is the *sourcing* shell's $0.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

# PASS/FAIL, not ok/FAIL: run-tests.sh aggregates by grepping each file's output for those tokens.
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'PASS: %s\n' "$1"; }

# The installed payload, derived the way install.sh derives it — not hardcoded. install.sh's
# PAYLOAD_FILES assignment takes every file under .claude/ except state/, and its `for group in
# scripts` copy loop copies scripts/*.sh into .claude/scripts/ with exactly one exclusion,
# check-provenance.sh. A hardcoded list goes stale the first time the payload changes.
#
# Cited by anchor, not by line. This comment read `install.sh:175` and `:379-390` and the second half
# rotted three commits later inside the wave that wrote it: a 29-line insertion higher up in
# install.sh moved the copy loop down by 29, and `:379-390` came to rest on licence prose about
# NOTICE.md, which still reads as a plausible thing for this comment to be pointing at. The ledger
# had listed this exact citation as rot-prone and "measured true today" — a line number cannot be
# made durable by checking it. An anchor survives an insertion; find them with:
#   grep -n 'PAYLOAD_FILES=\|for group in scripts' install.sh
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

# The floors above are lower bounds, so a derivation that *over*-includes clears them silently — and
# over-inclusion is the dangerous direction, because every extra PAYLOAD entry is a path rule 2 stops
# flagging. These two are properties, not counts: an exact count goes stale the first time the payload
# changes, which is the failure mode this repository has recorded three times.
STATE_LEAK="$(printf '%s\n' "$PAYLOAD" | grep -c '^\.claude/state/' || true)"
if [ "$STATE_LEAK" -eq 0 ]; then
  pass "payload carries no .claude/state/ path (PAYLOAD_FILES' one exclusion in install.sh)"
else
  fail "payload derivation included $STATE_LEAK .claude/state/ path(s) — install.sh excludes them, so citations to state/ files have silently stopped being caught"
fi

SCRIPTS_COUNT="$(printf '%s\n' "$PAYLOAD" | grep -c '^\.claude/scripts/' || true)"
if [ "$SCRIPTS_COUNT" -ge 1 ]; then
  pass "payload carries $SCRIPTS_COUNT .claude/scripts/ entries (floor 1)"
else
  fail "payload derivation produced no .claude/scripts/ entries — the scripts/*.sh loop has stopped matching; the count then falls to 76 and still clears the floor of 70"
fi

# 1. No numbered section marker in any shipped .md. The one exception is NOTICE.md's own §3, which
# names a section of the file it appears in and therefore resolves. §3[^0-9] so that a future §30 is
# caught. The rule is §[0-9], so the §Heading cross-references in state-machine and save-system are
# outside it by construction: they name headings in architecture.md and unity-specifics.md, both of
# which ship, so they resolve for an installed reader and must not be flagged.
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
  pass "no shipped surface carries a §N section marker (NOTICE.md's own §3 excepted)"
else
  fail "$sec_bad_n shipped citation(s) carry a §N marker that resolves to nothing:"
  printf '%s\n' "$sec_bad" | sed 's/^/       /'
fi

# 2. No backticked token that names a real file in this repository and is absent from the payload.
#
# Resolving against the repository tree is what keeps this from firing on user-project paths:
# `docs/features/<slug>/design.md` names no file here, so it is never flagged, while
# `tests/test-no-mobile.sh` names one and does not ship.
#
# The escape is a URL, in the same file, whose own text ends with the cited path. File-scoped, not
# block-scoped: NOTICE.md is one document, and a reader who meets "linked at the top of this file"
# scrolls up and finds the link. Block-scoped would force a URL into NOTICE.md:140's table header,
# `| How `provenance.tsv` records it |`, which names the manifest rather than pointing at it.
# Matching the URL's *text* is what stops it being a loophole: a URL clears a token only when the
# URL's own text ends with that token's path, so a file's other links — however many it carries —
# leave every citation they do not name still flagged. Stated as a property on purpose: a count of a
# file's URLs, or a named example, is a number this wave's own edits move.
#
# Three tokens are allowed. Each is a name collision the measurement turned up, not a citation of a
# repository-only artifact. If this list grows, rule 2 is wrong — re-examine it, do not append.
#   CLAUDE.md  the user's own file, generated by /unity-init; cited in 26 shipped files, correctly
#   LICENSE    in NOTICE.md this is always an upstream's licence ("everything-claude-unity's
#              `LICENSE`"); a root LICENSE here caused the match
#   VERSION    NOTICE.md:41 lists .claude/VERSION, which ships; a root VERSION here caused the match
CITATION_ALLOW="CLAUDE.md LICENSE VERSION"

path_bad=""
path_count=0
tokens_seen=0
while IFS= read -r md; do
  [ -n "$md" ] || continue
  rel="${md#"$REPO"/}"
  urls="$(grep -oE 'https?://[^ )>]+' "$md" || true)"
  # `grep -n`, so every reported citation carries a line. Without it the message named a file and a
  # token and nothing else: a hit in a 900-line skill or in NOTICE.md sends the maintainer straight
  # back to `grep`, and a token cited twice in one file collapsed to a single report with no way to
  # tell which occurrence was meant. Rule 1's message has given file, line and text since it was
  # written; this is that shape.
  #
  # Deduped on the (line, token) PAIR, not on the token, which is what un-collapses the second case.
  # `awk '!seen[$0]++'` rather than `sort -u` so the report comes out in line order rather than
  # lexicographic — `:10` before `:9` is a needless stumble in a list a human reads top to bottom.
  # A token cannot contain a colon (the character class excludes it), so `%%:` / `#*:` split the
  # pair unambiguously. Every stage here drains its input — no `head`, no `grep -q` — so there is no
  # SIGPIPE for pipefail to turn into a failure.
  toks="$(grep -noE '`[A-Za-z0-9_][A-Za-z0-9_./-]*`' "$md" | tr -d '`' | awk '!seen[$0]++' || true)"
  while IFS= read -r ln_tok; do
    [ -n "$ln_tok" ] || continue
    ln="${ln_tok%%:*}"
    t="${ln_tok#*:}"
    [ -n "$t" ] || continue
    tokens_seen=$((tokens_seen + 1))
    # Only tokens that name a real file here can dangle in a user's project.
    [ -f "$REPO/$t" ] || continue
    case " $CITATION_ALLOW " in *" $t "*) continue ;; esac
    case "$t" in
      .claude/*) p="$t" ;;
      scripts/*) p=".claude/$t" ;;
      *)         p="" ;;
    esac
    # Here-string, never a pipe: grep -q exits on first match without draining stdin, and under
    # pipefail that SIGPIPEs the writer.
    if [ -n "$p" ] && grep -qxF -- "$p" <<< "$PAYLOAD"; then continue; fi
    esc="$(printf '%s' "$t" | sed 's/[.[\*^$]/\\&/g')"
    if [ -n "$urls" ] && grep -qE -- "/${esc}\$" <<< "$urls"; then continue; fi
    path_bad="$path_bad       $rel:$ln: $t"$'\n'
    path_count=$((path_count + 1))
  done <<< "$toks"
done <<< "$SHIPPED_MD"

if [ "$tokens_seen" -ge 200 ]; then
  pass "guard examined $tokens_seen backticked tokens (floor 200)"
else
  fail "guard examined only $tokens_seen backticked tokens — expected at least 200; the token expression has stopped matching"
fi

if [ "$path_count" -eq 0 ]; then
  pass "no shipped surface cites a repository path the installed payload does not carry"
else
  fail "$path_count shipped citation(s) name a file install.sh does not copy:"
  printf '%s' "$path_bad"
  # The remedy is not obvious from the failure, and the obvious guess is the wrong one. A maintainer
  # who hits this on a legitimate citation deletes it, because nothing here says the citation can be
  # kept. It can: rule 2's escape is a URL, in the same file, whose own text ends with the cited
  # path. Printed with the failure rather than left in the comment above, because a comment in a test
  # file is not read by the person reading the test's output.
  printf '       Three ways out, in the order to consider them:\n'
  printf '         1. LINK IT, if the citation is legitimate and the reader needs the file. A URL\n'
  printf '            elsewhere in the SAME file whose own text ends with the cited path clears it —\n'
  printf '            e.g. a repository URL ending /tests/test-no-mobile.sh clears the token\n'
  printf '            tests/test-no-mobile.sh in that file. Only the URL naming that path clears it.\n'
  printf '         2. REWORD IT, if the reader does not need the file — describe what it does instead\n'
  printf '            of naming a path an installed project has no copy of.\n'
  printf '         3. SHIP IT, if the file genuinely belongs in the payload — add it under .claude/,\n'
  printf '            with a provenance.tsv row, and the citation resolves on its own.\n'
  printf '       Do NOT add the token to CITATION_ALLOW: that list is for name collisions, not for\n'
  printf '       citations, and a citation added to it stops being checked in every file at once.\n'
fi

[ "$FAILURES" -eq 0 ] || exit 1
printf 'all shipped-citation assertions passed\n'
