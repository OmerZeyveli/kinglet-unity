#!/usr/bin/env bash
# ============================================================================
# test-citations-resolve.sh — a `file:line` citation in a live surface must resolve at HEAD.
#
# WHAT WENT WRONG. This repository cites itself constantly: a test comment points at the install.sh
# line it is about, a document points at the assertion that guards it. Nothing ever checked that any
# of those pointers still landed where the prose said. Swept on 2026-08-14, seventeen live pointers
# had rotted — six heredoc introducers that a `--help` insertion pushed down by one to thirteen
# lines, three copies of `tests/test-no-mobile.sh:96` that had come to rest on a comment about
# SIGPIPE, two `provenance.tsv:71` that had come to rest on a different row's checksum, one
# `provenance.tsv:555` past the end of a 551-line file, and two that had landed on a BLANK LINE.
#
# THE ENUMERATION IS THE HARD PART, NOT THE RESOLUTION. The obvious pattern —
# `[A-Za-z0-9_./-]+\.(sh|md|tsv|json):[0-9]+` — cannot see a bare `:NNN` self-citation, cannot see a
# range, and cannot see an extension outside its list. Each of those blind spots hid a real rotted
# pointer, and two sweeps in a row declared themselves complete before a third shape turned up a
# tenth. So this guard runs THREE differently-shaped sweeps and unions them, and the union is the
# thing to preserve if any one of them is ever tightened.
#
# LIVE POINTERS ONLY. About half the `file:line` citations in this tree quote the rot AS THE FINDING
# — "this comment read `install.sh:175` and `:379-390` and the second half rotted three commits
# later". Renumbering those falsifies a record. The rule (ruling R12) is: a citation used as a
# POINTER must resolve at HEAD; a citation inside a narrative about a PAST state is exempt, named
# below, one row per site with its reason. The list is short and explicit on purpose — a `skip` that
# takes a pattern is a hole, and this repository has already paid for one.
#
# WHAT THIS CANNOT SEE, and it is not a small list:
#
#   * A RENAME BREAKS A CONTENT ANCHOR AS SILENTLY AS AN INSERTION BREAKS A NUMBER. This resolves
#     line numbers. It does not read what is AT the line, beyond requiring it to be non-blank, so a
#     citation that has slid onto a different but plausible line still passes. Two of the seventeen
#     found by hand were exactly that — a citation resting on a section banner, and one resting on
#     an unrelated comment that read as a plausible target. The durable repair for those is to cite
#     by anchor and drop the number, which is what most of the repairs did.
#   * IT CANNOT SEE A CITATION IT DOES NOT ENUMERATE. A fourth shape exists somewhere.
#   * IT READS THE LIVE SURFACES ONLY. `docs/superpowers/` and `docs/research/` are dated records of
#     what was measured on a day; their citations are pinned to that day by construction and
#     renumbering them would be the falsification this guard exists to prevent.
#   * IT CANNOT TELL A POINTER FROM A NARRATIVE. That judgement is the exemption table, written by
#     hand, and a wrong row silences a real pointer. Each row carries its reason so the next reader
#     can re-judge it rather than inherit it.
# ============================================================================

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

FAILURES=0
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'PASS: %s\n' "$1"; }

# --- The live surfaces. Derived from the index, minus the two record trees and the spike trees. ---
#
# `git ls-files` and not `find`: an untracked scratch file is not a surface, and the index is the
# same oracle every other guard in this suite uses.
LIVE_FILES="$(git ls-files \
  'tests/*.sh' 'scripts/*.sh' 'install.sh' 'uninstall.sh' \
  '.claude/*' 'docs/*.md' '*.md' 'provenance.tsv' 'provenance-skip.tsv' 2>/dev/null \
  | grep -vE '^docs/(superpowers|research)/' | sort -u || true)"
LIVE_N="$(printf '%s\n' "$LIVE_FILES" | grep -c . || true)"

# Anti-vacuity, before anything is compared. A sweep over an empty file set finds no bad citation and
# reports a clean tree, which is the shape this repository calls its worst.
if [ "$LIVE_N" -ge 30 ]; then
  pass "citation sweep read $LIVE_N live surface file(s) (floor 30)"
else
  fail "citation sweep read only $LIVE_N live surface file(s) — expected at least 30; a pathspec has stopped matching and every clean result below is worthless"
fi

# --- The exemption table: citations inside a narrative about a past state (ruling R12). ---
#
# Two TAB-separated fields: the citing file, and a fixed needle that must appear on the citing LINE.
# Line-scoped, not file-scoped, so exempting one sentence does not exempt the file's live pointers.
EXEMPT="tests/test-shipped-citations.sh	This comment read \`install.sh:175\` and \`:379-390\`
tests/test-shipped-citations.sh	install.sh moved the copy loop down by 29, and \`:379-390\` came to rest
tests/test-studio-doctor.sh	install.sh:327 was dry-run commentary about .mcp.json
tests/test-provenance-origins.sh	was the first draft of this glob, and it is exactly why studio-doctor.sh:275
tests/test-provenance-origins.sh	comment above singles out as the reason \`scripts/studio-doctor.sh:275\`
tests/test-bash32-compat.sh	review: install.sh:197 shipped exactly the early-exit-reader bug
tests/test-derived-counts.sh	README.md:184 said \"71 of 101 ECU-origin files
tests/test-derived-counts.sh	end of README.md:184 and
tests/test-surface-references.sh	sitting at \`unity-brainstorming/SKILL.md:183\` under a new title
tests/test-surface-references.sh	\`unity-brainstorming/SKILL.md:113\` ended
tests/test-mcp-doc-instructions.sh	.claude/commands/unity-doctor.md:19  — fixed, same commit as this test
tests/test-mcp-doc-instructions.sh	docs/GETTING-STARTED.md:173          — fixed, same commit, but is NOT
tests/test-mcp-doc-instructions.sh	Round 2 (reviewer finding) found a THIRD, in .claude/NOTICE.md:23
tests/test-mcp-doc-instructions.sh	LINE only. That missed .claude/NOTICE.md:23
.claude/skills/subagent-driven-implementation/SKILL.md	method or the symbol — \`SkinRulesSpec.ClampsAtZero\`, not \`SkinRulesSpec.cs:410-423\`
.claude/skills/unity-planning/SKILL.md	\`Existing.cs:123-145\`. This template shipped the range form
tests/test-workflow-plan-input.sh	— a LINE RANGE — which is the citation form
provenance.tsv	unity-workflow.md:23-52
MERGE-NOTES.md	2026-07-30-kinglet-pioneer-wave-1b2-make-it-findable.md:70"

is_exempt() { # $1=file $2=line-number
  local f="$1" n="$2" line
  line="$(awk -v k="$n" 'NR == k { print; exit }' "$f")"
  local ef en
  while IFS=$'\t' read -r ef en; do
    [ -n "$ef" ] || continue
    [ "$ef" = "$f" ] || continue
    case "$line" in *"$en"*) return 0 ;; esac
  done <<< "$EXEMPT"
  return 1
}

# --- The three sweeps. Each emits `citing-file:citing-line:token`. ---
#
# Shape A is the token form the plan named. Shape B is a BARE self-citation, `:NNN` or `:NNN-NNN`,
# not preceded by a path character — invisible to A, and two of the rotted pointers had this shape.
# Shape C is extension-agnostic and range-aware, and it is the one that found the eleventh: a
# `.cs` line range inside a skill's own plan template. The extension must START with a letter, which
# is what keeps `127.0.0.1:8080` out.
sweep() { xargs -a /dev/stdin /usr/bin/grep -nHoE "$1" 2>/dev/null || true; }

SH_A='[A-Za-z0-9_./-]+\.(sh|md|tsv|json):[0-9]+(-[0-9]+)?'
SH_B='(^|[^A-Za-z0-9_./-]):[0-9]+(-[0-9]+)?'
SH_C='[A-Za-z0-9_./-]+\.[A-Za-z][A-Za-z0-9]*:[0-9]+(-[0-9]+)?'

FILELIST="$(mktemp "${TMPDIR:-/tmp}/kinglet-cite-files.XXXXXX")"
printf '%s\n' "$LIVE_FILES" > "$FILELIST"

HITS_A="$(sweep "$SH_A" < "$FILELIST")"
HITS_B="$(sweep "$SH_B" < "$FILELIST")"
HITS_C="$(sweep "$SH_C" < "$FILELIST")"
rm -f "$FILELIST"

N_A="$(printf '%s\n' "$HITS_A" | grep -c . || true)"
N_B="$(printf '%s\n' "$HITS_B" | grep -c . || true)"
N_C="$(printf '%s\n' "$HITS_C" | grep -c . || true)"

# Each sweep must find something. A regex that silently stops matching is the failure this whole file
# is about, one level up, and a union hides it: two live sweeps carry a dead one to a green result.
SWEEP_BAD=""
[ "$N_A" -ge 1 ] || SWEEP_BAD="${SWEEP_BAD}shape A (path.ext:NNN) matched nothing"$'\n'
[ "$N_B" -ge 1 ] || SWEEP_BAD="${SWEEP_BAD}shape B (bare :NNN) matched nothing"$'\n'
[ "$N_C" -ge 1 ] || SWEEP_BAD="${SWEEP_BAD}shape C (generic path.ext:NNN-NNN) matched nothing"$'\n'
if [ -n "$SWEEP_BAD" ]; then printf '%s' "$SWEEP_BAD"; fi
if [ -z "$SWEEP_BAD" ]; then
  pass "all three citation shapes matched (A=$N_A, B=$N_B, C=$N_C raw hits before exemptions)"
else
  fail "a citation sweep shape stopped matching — the union is now narrower than this guard claims"
fi

# --- Resolve. ---
BAD=""
CHECKED=0

resolve_target() { # $1 = token path; prints a repo-relative path or nothing
  local t="$1"
  if [ -f "$REPO/$t" ]; then printf '%s\n' "$t"; return 0; fi
  case "$t" in
    */*) return 1 ;;
  esac
  local m
  m="$(git ls-files | grep -E "(^|/)$(printf '%s' "$t" | sed 's/[.[\*^$]/\\&/g')\$" || true)"
  [ "$(printf '%s\n' "$m" | grep -c . || true)" = "1" ] || return 1
  printf '%s\n' "$m"
}

check_one() { # $1 = citing file, $2 = citing line, $3 = target path (may be empty = self), $4 = target line
  local cf="$1" cl="$2" tp="$3" tl="$4" resolved lines content
  CHECKED=$((CHECKED + 1))
  if [ -z "$tp" ]; then
    resolved="$cf"
  else
    resolved="$(resolve_target "$tp" || true)"
    if [ -z "$resolved" ]; then
      BAD="${BAD}${cf}:${cl} cites ${tp}:${tl} — no such file in this repository"$'\n'
      return 0
    fi
  fi
  lines="$(awk 'END { print NR }' "$REPO/$resolved")"
  if [ "$tl" -gt "$lines" ] || [ "$tl" -lt 1 ]; then
    BAD="${BAD}${cf}:${cl} cites ${resolved}:${tl} — that file has ${lines} lines"$'\n'
    return 0
  fi
  content="$(awk -v k="$tl" 'NR == k { print; exit }' "$REPO/$resolved")"
  if [ -z "$(printf '%s' "$content" | tr -d '[:space:]')" ]; then
    BAD="${BAD}${cf}:${cl} cites ${resolved}:${tl} — that line is blank"$'\n'
  fi
}

# Shapes A and C carry a path; shape B is a self-citation. Deduped on the whole `file:line:token`
# triple, so one line citing two different targets is checked twice and one target cited twice on
# one line is checked once.
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  cf="${hit%%:*}"; rest="${hit#*:}"; cl="${rest%%:*}"; tok="${rest#*:}"
  is_exempt "$cf" "$cl" && continue
  tp="${tok%:*}"; tl="${tok##*:}"; tl="${tl%%-*}"
  check_one "$cf" "$cl" "$tp" "$tl"
done <<< "$(printf '%s\n%s\n' "$HITS_A" "$HITS_C" | grep -v '^$' | awk '!seen[$0]++')"

while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  cf="${hit%%:*}"; rest="${hit#*:}"; cl="${rest%%:*}"; tok="${rest#*:}"
  is_exempt "$cf" "$cl" && continue
  # The match carries its leading delimiter (`\``, a space, a line start). Strip to the digits.
  tl="$(printf '%s' "$tok" | tr -dc '0-9-')"; tl="${tl%%-*}"
  [ -n "$tl" ] || continue
  check_one "$cf" "$cl" "" "$tl"
done <<< "$(printf '%s\n' "$HITS_B" | grep -v '^$' | awk '!seen[$0]++')"

if [ "$CHECKED" -ge 10 ]; then
  pass "resolved $CHECKED live citation(s) against the tree (floor 10)"
else
  fail "resolved only $CHECKED live citation(s) — expected at least 10; either the sweeps or the exemption table has swallowed the subject"
fi

if [ -n "$BAD" ]; then
  printf '%s' "$BAD" | sed 's|^|     |'
  fail "$(printf '%s' "$BAD" | grep -c . || true) live citation(s) no longer resolve — fix the pointer, or cite by anchor and drop the number"
else
  pass "every live file:line citation resolves to a real, non-blank line"
fi

# --- Every exemption row must still match something. ---
#
# An exemption whose needle no longer appears is a hole with no subject: the sentence was reworded or
# deleted, and the row now silences nothing while reading as if it does. That is how a skip list
# grows past its reason.
ORPHANED=""
while IFS=$'\t' read -r ef en; do
  [ -n "$ef" ] || continue
  if [ ! -f "$REPO/$ef" ]; then
    ORPHANED="${ORPHANED}${ef} (file is gone)"$'\n'
  elif ! grep -qF -- "$en" "$REPO/$ef"; then
    ORPHANED="${ORPHANED}${ef}: ${en}"$'\n'
  fi
done <<< "$EXEMPT"
if [ -n "$ORPHANED" ]; then printf '%s' "$ORPHANED" | sed 's|^|     |'; fi
if [ -z "$ORPHANED" ]; then
  pass "every historical-citation exemption still names text that exists"
else
  fail "$(printf '%s' "$ORPHANED" | grep -c . || true) exemption row(s) match nothing — delete them rather than leaving a hole with no subject"
fi

if [ "$FAILURES" -gt 0 ]; then
  printf '%s\n' "citation resolution: $FAILURES failure(s)"
  exit 1
fi
exit 0
