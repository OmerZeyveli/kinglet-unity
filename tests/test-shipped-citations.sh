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

# 0. Coverage floors. A guard that silently stops reading its subject reports green forever. They
# were derived with headroom from the tree on 2026-08-11, which held 44 shipped .md files and 85
# payload entries; scripts/detect-pipeline.sh made the second of those 86 and this line went a wave
# without noticing. Do not read either count off it — both pass lines below print what the tree holds
# on the run in front of you. Raise a floor when the tree grows; never lower one to make a run pass.
#
# THE PAYLOAD FLOOR MOVED DOWN ON 2026-08-13, from 70 to 55, and that is the one edit the paragraph
# above forbids — so it needs its reason on the record. The surface criterion was applied to
# `.claude/hooks/` and `scripts/` for the first time and removed 15 hooks and 4 scripts by a decision
# recorded in provenance-skip.tsv, which `scripts/check-provenance.sh` enforces path by path. The
# tree shrank from 86 payload entries to 67 because it was CUT, not because a derivation broke, and
# the new floor keeps the same proportional headroom the old one had. A floor lowered to match a
# shrinkage nothing authorised would be the failure this comment warns about; this one is pinned to a
# skip list a second guard reads.
if [ "$MD_COUNT" -ge 35 ]; then
  pass "guard scanned $MD_COUNT shipped .md files (floor 35)"
else
  fail "guard scanned only $MD_COUNT shipped .md files — expected at least 35; it has stopped reading its subject"
fi

PAYLOAD_COUNT="$(printf '%s\n' "$PAYLOAD" | grep -c . || true)"
if [ "$PAYLOAD_COUNT" -ge 55 ]; then
  pass "payload derivation produced $PAYLOAD_COUNT entries (floor 55)"
else
  fail "payload derivation produced only $PAYLOAD_COUNT entries — expected at least 55; install.sh's layout has changed or the derivation is broken"
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
  fail "payload derivation produced no .claude/scripts/ entries — the scripts/*.sh loop has stopped matching; the count then falls to 61 and still clears the floor of 55"
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
  # lexicographic — line 10 before line 9 is a needless stumble in a list a human reads top to bottom.
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

# 3. Every `.claude/scripts/<name>.sh` a shipped surface names must be a script install.sh copies.
#
# RULE 2 CANNOT SEE THESE, and the reason is structural rather than an oversight. Its first test is
# `[ -f "$REPO/$t" ]` — only a token naming a real file in THIS repository can dangle in a user's —
# and `.claude/scripts/` does not exist in this repository at all: install.sh builds it by copying
# the repo-root `scripts/`. So every `.claude/scripts/...` token falls out of rule 2 at that line
# and is never examined. A surface naming `.claude/scripts/studio-doctar.sh` resolves to nothing in
# every installed project and rule 2 reports green. That is the same shape as the citation defect
# rule 2 exists for, one directory over.
#
# Matched on the path form and only on it. `scripts/<name>.sh` (the repository form) is rule 2's:
# it maps that to `.claude/<token>` and checks the payload, which is the right answer for a token
# that names a real file here. This rule is for the form a shipped surface should actually use,
# which names no file here and so reaches nothing today.
SC_TOKENS=""
SC_TOKENS_N=0
while IFS= read -r md; do
  [ -n "$md" ] || continue
  rel="${md#"$REPO"/}"
  hits="$(grep -noE '\.claude/scripts/[A-Za-z0-9_.-]+\.sh' "$md" || true)"
  while IFS= read -r ln_tok; do
    [ -n "$ln_tok" ] || continue
    SC_TOKENS="${SC_TOKENS}${rel}:${ln_tok}"$'\n'
    SC_TOKENS_N=$((SC_TOKENS_N + 1))
  done <<< "$hits"
done <<< "$SHIPPED_MD"

# A coverage floor, for the reason rule 0 gives two rules up: an all-clear over an empty token set is
# indistinguishable from an all-clear over a real one. The live count is printed rather than assumed,
# so a reader never has to trust this comment. The reverse-direction assertion below would also
# redden if every reference vanished at once — but not if the token EXPRESSION broke while the
# references stayed, which is what this catches.
#
# THE FLOOR IS THE NUMBER OF DISTINCT SCRIPTS NAMED, NOT THE NUMBER OF MENTIONS, and that criterion
# is the whole of the value. Rule 0 says raise a floor when the tree grows and never lower one to
# make a run pass; this floor was raised 4 -> 8 on 2026-08-14 under exactly that instruction, and the
# raise was measured wrong twice over:
#
#   * it buys NO detection. The failure it names — a broken token expression — yields 0, which trips
#     any floor at all, including the old 4. Nothing detectable at 8 is undetectable at 5.
#   * it creates a FALSE POSITIVE, and a likely one. The live count is 9 across 6 distinct scripts:
#     `unity-fixer` names detect-missing-refs.sh on two consecutive lines, `unity-review` names
#     validate-serialization.sh on two consecutive lines, and `/unity-init` names
#     generate-claude-md.sh twice. Consolidating any two of those duplicate pairs — an edit that
#     removes no wiring and leaves every script still named — drops the count to 7 and reds this
#     assertion with a message whose two disjuncts are both false.
#
# So the floor is 6: one reference per distinct installed script that a shipped surface names. Below
# 6 a script really has stopped being named, which is a finding. Between 6 and 9 the tree has lost
# redundancy, which is not. Re-derive both numbers rather than trusting them:
#
#   grep -rhoE '\.claude/scripts/[A-Za-z0-9_.-]+\.sh' .claude --include='*.md' | sort | uniq -c
#
if [ "$SC_TOKENS_N" -ge 6 ]; then
  pass "guard examined $SC_TOKENS_N .claude/scripts/ path reference(s) in shipped surfaces (floor 6 — one per distinct installed script named)"
else
  fail "guard examined only $SC_TOKENS_N .claude/scripts/ path reference(s) — expected at least 6, one per distinct installed script a shipped surface names; either the wiring has been removed or the token expression has stopped matching"
fi

# A token cannot contain a colon (the character class excludes it), so `##*:` recovers it from the
# `file:line:token` triple unambiguously.
sc_bad=""
sc_bad_n=0
SC_NAMED=""
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  t="${entry##*:}"
  if grep -qxF -- "$t" <<< "$PAYLOAD"; then
    SC_NAMED="${SC_NAMED}${t}"$'\n'
    continue
  fi
  sc_bad="$sc_bad       $entry"$'\n'
  sc_bad_n=$((sc_bad_n + 1))
done <<< "$SC_TOKENS"

if [ "$sc_bad_n" -eq 0 ]; then
  pass "every .claude/scripts/ path a shipped surface names is a script install.sh copies"
else
  fail "$sc_bad_n shipped surface citation(s) name a .claude/scripts/ path no install has:"
  printf '%s' "$sc_bad"
  printf '       install.sh copies scripts/*.sh into .claude/scripts/ with one exclusion,\n'
  printf '       check-provenance.sh. A path here that is not in that set resolves to nothing in\n'
  printf '       every installed project, however well it reads in the repository.\n'
fi

# The other direction: a script that ships and that no shipped surface names is reachable only by a
# user who goes looking. Asserted as a SUBSET rather than as a count, so that wiring one more script
# up can never redden this, and unwiring one always does. A name may be REMOVED from the pending
# list; adding one is undoing work this list exists to finish.
#
#   The list is EMPTY as of 2026-08-14 and that is its finished state, not a gap. Its one entry was
#   generate-claude-md.sh, waiting on Task 7 of the 2026-08-13 surface-criterion wave to name it
#   from `/unity-init`; that landed, so the entry was deleted and the assertion below now reads
#   every installed script as named. An empty list is not an invitation to refill it — see the next
#   paragraph and the failure message further down: naming or cutting are the two answers.
#
# AN EXEMPTION THAT IS SATISFIED IS STALE, AND STALE HERE MEANS PERMANENTLY RELAXED. The list is
# consulted only for scripts already found unreferenced, so the moment the pending script IS named
# the entry stops doing anything — and then keeps not doing anything while the reference it was
# waiting for can be removed again with no red, forever. Measured before this check existed: entry
# present with the reference added → green; entry present with the reference removed → also green.
# They differ by a reference and agree on the result, which is the definition of a guard that has
# stopped guarding. So a satisfied entry is a FAILURE with the remedy in its message: delete the
# line. That makes retiring the exemption the only way forward rather than an optional tidy-up.
SC_REACH_PENDING=""

SC_UNREF=""
SC_INSTALLED_N=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$p" in .claude/scripts/*) ;; *) continue ;; esac
  SC_INSTALLED_N=$((SC_INSTALLED_N + 1))
  if grep -qxF -- "$p" <<< "$SC_NAMED"; then continue; fi
  SC_UNREF="${SC_UNREF}${p##*/}"$'\n'
done <<< "$PAYLOAD"

sc_unref_bad=""
while IFS= read -r b; do
  [ -n "$b" ] || continue
  case " $SC_REACH_PENDING " in *" $b "*) continue ;; esac
  sc_unref_bad="$sc_unref_bad $b"
done <<< "$SC_UNREF"

SC_NAMED_N="$(printf '%s\n' "$SC_NAMED" | sort -u | grep -c . || true)"
SC_PENDING_N="$(printf '%s\n' $SC_REACH_PENDING | grep -c . || true)"

sc_stale_pending=""
for b in $SC_REACH_PENDING; do
  if grep -qxF -- ".claude/scripts/$b" <<< "$SC_NAMED"; then
    sc_stale_pending="$sc_stale_pending $b"
  fi
done

if [ -z "$sc_stale_pending" ]; then
  pass "no name on the reachability pending list is already named by a shipped surface"
else
  fail "SC_REACH_PENDING still exempts script(s) that are now named:$sc_stale_pending"
  printf '       The exemption has been satisfied, so it exempts nothing and guards nothing — and\n'
  printf '       while it sits there the reference it was waiting for can be removed again with no\n'
  printf '       failure. Delete the name from SC_REACH_PENDING in this file. That is the whole fix.\n'
fi

if [ -z "$sc_unref_bad" ]; then
  pass "$SC_NAMED_N of $SC_INSTALLED_N installed scripts are named by a shipped surface, bar $SC_PENDING_N on the recorded pending list"
else
  fail "installed script(s) named by no agent, command or skill and not on the pending list:$sc_unref_bad"
  printf '       %s of %s installed scripts are currently named by a shipped surface.\n' "$SC_NAMED_N" "$SC_INSTALLED_N"
  printf '       A script nothing names is reachable only by a user who goes looking for it. Either\n'
  printf '       name it from the surface whose job it belongs to, or cut it — those are the two\n'
  printf '       answers the surface criterion admits. Do not add it to SC_REACH_PENDING.\n'
fi

[ "$FAILURES" -eq 0 ] || exit 1
printf 'all shipped-citation assertions passed\n'
