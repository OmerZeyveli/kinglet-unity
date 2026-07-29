#!/usr/bin/env bash
# ============================================================================
# test-mcp-doc-instructions.sh — no instruction in .claude/ OR in the
# repository's own documentation sends a reader back to the file Claude Code
# never reads MCP config from.
#
# Round 3 (2026-07-29, controller sweep after Task 8) found the SAME stale
# claim in six places outside .claude/: CLAUDE.md, CREDITS.md, README.md,
# docs/ARCHITECTURE.md, docs/GETTING-STARTED.md (two spots, one of which
# the sweep itself missed — see the widening note below), and MERGE-NOTES.md.
# All six are fixed in the same commit that widens this guard past .claude/.
# See the "Round 3" section near the end of this file for the widened scan,
# its exclusion list, and why MERGE-NOTES.md is handled separately from it.
#
# Task 2 moved MCP server configuration to .mcp.json at the project root,
# because Claude Code silently ignores an mcpServers key inside settings.json.
# Task 8 round 1 found two stale instructions pointing at the dead location:
#   .claude/commands/unity-doctor.md:19  — fixed, same commit as this test.
#   docs/GETTING-STARTED.md:173          — fixed, same commit, but is NOT
#       scanned here: it lives under docs/, and this guard is deliberately
#       scoped to .claude/ — see the scope note below.
# Round 2 (reviewer finding) found a THIRD, in .claude/NOTICE.md:23 — fixed in
# the same commit that widened this test. It read across a line break ("...is
# **not** included here." / "`settings.json` merely points at it..."), which
# the original same-line-only pattern below could not see. That is why the
# scan is now per-FILE with folded whitespace instead of per-LINE — see the
# widening note further down.
#
# Two OTHER references to settings.json + MCP are legitimate and must survive
# any future sweep:
#   scripts/studio-doctor.sh:85 (comment) and MCP-SETUP.md:120 (prose) both
#   EXPLAIN why settings.json is a last-resort / broken fallback — history,
#   not instruction. Neither file lives under .claude/, so this guard's scope
#   already excludes both without needing a named exclusion list. That is not
#   an accident: it is why the guard is scoped to .claude/ rather than the
#   whole repo. A repo-wide version of this same idea would have to carry an
#   exclusion list (naming those two files, by path, with the reason above);
#   scoping to .claude/ makes that unnecessary today. If either explanatory
#   file is ever moved under .claude/, or a NEW explanatory comment about this
#   history is added inside .claude/, it WILL trip this guard — at which point
#   it needs a real by-path exclusion, not a rewrite of the pattern.
#
# --- What the pattern matches, and the widening from round 1 to round 2 ---
#
# Round 1 matched `settings.json` and `mcp` (case-insensitive) on the SAME
# LINE only. That missed .claude/NOTICE.md:23, whose sentence break put
# "settings.json" one line below the "MCP" it referred to. A test that can
# only see same-line references is blind to any reference split across a line
# break — that was a real limitation, not a bug in the regex, and it let a
# genuine instance through.
#
# Round 2 widens the scan to work PER FILE instead of per line: each tracked
# file under .claude/ has its newlines folded to spaces (`tr '\n' ' '`), then
# the same idea — `settings.json` and `mcp` within a bounded distance of each
# other, case-insensitive — is applied to the whole folded file via a bounded
# regex interval (`.{0,120}` either direction) instead of a same-line
# character class. Folding first, rather than trying to match across a
# literal newline, keeps the pattern itself simple (no multiline-mode grep
# flags to get subtly wrong) and keeps the distance bound meaningful in
# characters rather than "lines," which vary wildly in length across prose.
# 120 was picked by measuring the actual distance in NOTICE.md's real
# instance (~94 characters from the nearest "mcp" substring to
# "settings.json") and rounding up for margin, not by guessing.
#
# This still catches the same-line case from round 1 (distance 0 satisfies
# `.{0,120}` trivially) — verified below by the same canary string round 1
# used — so nothing already covered was lost by the widening.
#
# What remains a genuine, stated limitation: two references to settings.json
# and mcp that are BOTH real but separated by more than ~120 characters in
# the same file (e.g. one in an opening paragraph, an explanation many
# paragraphs later) will still slip past this guard. That shape has not been
# seen in this repo in either round of this task; if it appears, the bound
# needs to grow or the approach needs to change again. This comment exists so
# the next person reads a green run as "no same-file, nearby reference
# survives" — not as "the class of defect is closed."
# ============================================================================

TMDI_TRACKED=$(cd "$REPO_DIR" && git ls-files -- .claude/)
TMDI_HITS=""
while IFS= read -r tmdi_relpath; do
    [ -z "$tmdi_relpath" ] && continue
    tmdi_abspath="${REPO_DIR}/${tmdi_relpath}"
    [ -f "$tmdi_abspath" ] || continue
    tmdi_match=$(tr '\n' ' ' < "$tmdi_abspath" \
        | grep -ioE 'settings\.json.{0,120}mcp|mcp.{0,120}settings\.json' || true)
    if [ -n "$tmdi_match" ]; then
        TMDI_HITS="${TMDI_HITS}${tmdi_relpath}: ${tmdi_match}
"
    fi
done <<< "$TMDI_TRACKED"

if [ -n "$TMDI_HITS" ]; then
    echo "--- offending file(s) in .claude/ still tie settings.json to MCP config ---"
    echo "$TMDI_HITS"
    echo "--- end offenders ---"
fi
assert_eq "" "$TMDI_HITS" \
    "no file under .claude/ ties settings.json to MCP config within ~120 characters"

# --- Guard: the pattern still binds (proves it isn't accidentally matching
# nothing forevermore). Two canaries: the round-1 same-line wording, and the
# round-2 cross-line wording that NOTICE.md actually carried.
TMDI_CANARY_SAMELINE='Check `.claude/settings.json` -> `mcpServers.unityMCP.url`'
TMDI_CANARY_CROSSLINE='The Unity MCP bridge is not included here.
`settings.json` merely points at it on localhost.'

TMDI_SAMELINE_CAUGHT="missed"
if printf '%s' "$TMDI_CANARY_SAMELINE" | tr '\n' ' ' \
        | grep -ioE 'settings\.json.{0,120}mcp|mcp.{0,120}settings\.json' > /dev/null; then
    TMDI_SAMELINE_CAUGHT="caught"
fi
assert_eq "caught" "$TMDI_SAMELINE_CAUGHT" \
    "the pattern still catches the round-1 same-line stale instruction"

TMDI_CROSSLINE_CAUGHT="missed"
if printf '%s' "$TMDI_CANARY_CROSSLINE" | tr '\n' ' ' \
        | grep -ioE 'settings\.json.{0,120}mcp|mcp.{0,120}settings\.json' > /dev/null; then
    TMDI_CROSSLINE_CAUGHT="caught"
fi
assert_eq "caught" "$TMDI_CROSSLINE_CAUGHT" \
    "the pattern now catches a reference split across a line break, like NOTICE.md's was"

# --- Positive controls: the fixed instructions now name the real location ---
TMDI_DOCTOR_LINE=$(grep -n "mcpServers.unityMCP.url" "${REPO_DIR}/.claude/commands/unity-doctor.md" || true)
assert_contains "$TMDI_DOCTOR_LINE" ".mcp.json" \
    "unity-doctor.md's MCP connectivity check now names .mcp.json, not settings.json"

TMDI_NOTICE=$(cat "${REPO_DIR}/.claude/NOTICE.md")
assert_contains "$TMDI_NOTICE" "\`.mcp.json\` merely points at it" \
    "NOTICE.md's MCP-bridge sentence now names .mcp.json, not settings.json"

# ============================================================================
# Round 3 — widen past .claude/ to the repository's own documentation.
#
# The .claude/ scan above is unchanged: it is the payload a user's project
# receives, and the reasoning above it still holds. This section is a
# SEPARATE scan over root-level and docs/ Markdown, because a controller
# sweep after Task 8 found the identical stale claim ("settings.json holds
# MCP config") in six places no .claude/-scoped guard could ever see.
#
# --- Scope: every tracked root-level *.md, plus every tracked docs/**/*.md ---
#
# This is deliberately a moving target, not a fixed file list: a new doc added
# under docs/ tomorrow is in scope automatically. Only paths named below are
# excluded, each for a stated reason — a new file is never exempt by default.
#
# --- Excluded, by exact path/prefix, each because it EXPLAINS the mistake
# rather than repeating it (deleting the words would delete the evidence) ---
#
#   MCP-SETUP.md                        — the whole document's job is to record
#                                          why settings.json is the WRONG place;
#                                          the brief names lines 5, 101, 120
#                                          specifically, but the surrounding
#                                          prose repeats the same juxtaposition
#                                          deliberately, so the exclusion is the
#                                          whole file, not three lines.
#   docs/research/pioneer/smoke-pass.md — the investigative record of the exact
#                                          finding that motivated this whole
#                                          guard (Task 8's origin).
#   docs/superpowers/plans/*            — frozen plan documents; historical
#                                          record of what was planned, not a
#                                          claim about current behavior.
#   docs/superpowers/specs/*            — frozen spec documents; same reasoning.
#
# MERGE-NOTES.md is tracked docs but is EXCLUDED from this proximity scan and
# checked separately below (see "MERGE-NOTES.md" section) — it is a historical
# build record whose OTHER entries legitimately place "settings.json" and
# "mcp" near each other while describing what was true when it was written
# (e.g. "Part 1 did not ship a settings.json ... We ship .claude/settings.json
# now"). A same-file proximity match cannot distinguish past tense from
# present tense; a human already made that call for this file (the same
# treatment MERGE-NOTES.md's own repo-name entry received during the product
# rename, tense-fixing "was originally ... later renamed" rather than
# rewriting the history) and it is not something a regex should re-decide.
#
# scripts/studio-doctor.sh's explanatory comment needs no exclusion entry:
# it is a .sh file, not a root *.md or docs/**/*.md, so this scan's scope
# never reaches it — the same reason it never needed one in the .claude/-only
# scan above.
#
# --- What this does NOT solve, stated plainly ---
#
# This is a proximity heuristic, not a grammar checker. It cannot tell "X used
# to be true" from "X is true" within a single juxtaposition — that is exactly
# why MERGE-NOTES.md needed a human call instead of being folded into this
# scan. If a future doc mixes historical and current claims about
# settings.json/MCP the way MERGE-NOTES.md does, it will need the same
# judgment call and the same kind of narrow, line-anchored check below instead
# of being added to this proximity scan.

tmdi3_is_excluded() {
    case "$1" in
        MCP-SETUP.md) return 0 ;;
        MERGE-NOTES.md) return 0 ;;
        docs/research/pioneer/smoke-pass.md) return 0 ;;
        docs/superpowers/plans/*) return 0 ;;
        docs/superpowers/specs/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Classifier self-check: proves the exclusion list is a named allowlist of
# exceptions, not a stand-in for "skip everything" — including a check that a
# BRAND NEW, never-seen doc path is still classified as in-scope.
TMDI3_CLASSIFY_FAILURES=""
for tmdi3_case in \
    "MCP-SETUP.md:excluded" \
    "MERGE-NOTES.md:excluded" \
    "docs/research/pioneer/smoke-pass.md:excluded" \
    "docs/superpowers/plans/2026-07-22-kinglet-01-identity-foundation.md:excluded" \
    "docs/superpowers/specs/2026-07-22-kinglet-for-unity-design.md:excluded" \
    "CLAUDE.md:included" \
    "README.md:included" \
    "docs/ARCHITECTURE.md:included" \
    "docs/some-brand-new-doc-nobody-has-written-yet.md:included" \
; do
    tmdi3_path="${tmdi3_case%%:*}"
    tmdi3_expected="${tmdi3_case##*:}"
    if tmdi3_is_excluded "$tmdi3_path"; then
        tmdi3_actual="excluded"
    else
        tmdi3_actual="included"
    fi
    if [ "$tmdi3_actual" != "$tmdi3_expected" ]; then
        TMDI3_CLASSIFY_FAILURES="${TMDI3_CLASSIFY_FAILURES}${tmdi3_path}: expected ${tmdi3_expected}, got ${tmdi3_actual}
"
    fi
done
assert_eq "" "$TMDI3_CLASSIFY_FAILURES" \
    "the exclusion classifier only exempts the named paths -- a brand-new doc is scanned by default"

# --- The scan itself: root *.md (non-recursive) + every docs/**/*.md ---
TMDI3_ROOT_MD=$(cd "$REPO_DIR" && git ls-files -- '*.md' | grep -v '/' || true)
TMDI3_DOCS_MD=$(cd "$REPO_DIR" && git ls-files -- 'docs/' | grep '\.md$' || true)
TMDI3_TRACKED=$(printf '%s\n%s\n' "$TMDI3_ROOT_MD" "$TMDI3_DOCS_MD")

TMDI3_HITS=""
while IFS= read -r tmdi3_relpath; do
    [ -z "$tmdi3_relpath" ] && continue
    tmdi3_is_excluded "$tmdi3_relpath" && continue
    tmdi3_abspath="${REPO_DIR}/${tmdi3_relpath}"
    [ -f "$tmdi3_abspath" ] || continue
    tmdi3_match=$(tr '\n' ' ' < "$tmdi3_abspath" \
        | grep -ioE 'settings\.json.{0,120}mcp|mcp.{0,120}settings\.json' || true)
    if [ -n "$tmdi3_match" ]; then
        TMDI3_HITS="${TMDI3_HITS}${tmdi3_relpath}: ${tmdi3_match}
"
    fi
done <<< "$TMDI3_TRACKED"

if [ -n "$TMDI3_HITS" ]; then
    echo "--- offending repository doc(s) still tie settings.json to MCP config ---"
    echo "$TMDI3_HITS"
    echo "--- end offenders ---"
fi
assert_eq "" "$TMDI3_HITS" \
    "no non-excluded repository doc ties settings.json to MCP config within ~120 characters"

# --- Positive controls: the six corrected locations now name .mcp.json ---
TMDI3_CLAUDE_MD=$(cat "${REPO_DIR}/CLAUDE.md")
assert_contains "$TMDI3_CLAUDE_MD" "\`.mcp.json\` points at it on \`localhost:8080\`" \
    "CLAUDE.md's unity-mcp bullet now names .mcp.json, not settings.json"

TMDI3_CREDITS_MD=$(cat "${REPO_DIR}/CREDITS.md")
assert_contains "$TMDI3_CREDITS_MD" "Our \`.mcp.json\` points at it on \`http://localhost:8080/mcp\`" \
    "CREDITS.md's MCP bridge paragraph now names .mcp.json, not settings.json"

TMDI3_README_MD=$(cat "${REPO_DIR}/README.md")
assert_contains "$TMDI3_README_MD" "preconfigured in \`.mcp.json\`" \
    "README.md's One MCP bullet now names .mcp.json, not settings.json"

TMDI3_ARCH_MD=$(cat "${REPO_DIR}/docs/ARCHITECTURE.md")
assert_not_contains "$TMDI3_ARCH_MD" "settings.json      Configuration: permissions, MCP servers" \
    "docs/ARCHITECTURE.md's component tree no longer credits settings.json with MCP servers"

TMDI3_GETTING_STARTED_MD=$(cat "${REPO_DIR}/docs/GETTING-STARTED.md")
assert_not_contains "$TMDI3_GETTING_STARTED_MD" "settings.json    Permissions, MCP server config" \
    "docs/GETTING-STARTED.md's directory tree no longer credits settings.json with MCP server config"
assert_contains "$TMDI3_GETTING_STARTED_MD" "The \`.mcp.json\` is already configured to connect" \
    "docs/GETTING-STARTED.md's setup step 4 now names .mcp.json, not settings.json"

# --- MERGE-NOTES.md: the judgment call. Not scanned by the proximity check
# above (see the exclusion rationale). Checked narrowly instead: the specific
# table row is anchored by stable surrounding text (the package name), then
# asserted to have the tense-honest wording and NOT the flatly-present-tense
# stale wording it used to carry. Its other entries (Part 1/Part 2 history)
# are untouched and are not re-checked here -- they were never wrong.
TMDI3_MERGE_ROW=$(grep "com.coplaydev.unity-mcp" "${REPO_DIR}/MERGE-NOTES.md" | grep "not vendored" || true)
assert_contains "$TMDI3_MERGE_ROW" "used to point at it on localhost" \
    "MERGE-NOTES.md's unity-mcp row now states the settings.json claim in the past tense"
assert_contains "$TMDI3_MERGE_ROW" "\`.mcp.json\`" \
    "MERGE-NOTES.md's unity-mcp row now names where MCP config actually lives"
assert_not_contains "$TMDI3_MERGE_ROW" "\`settings.json\` points at it on localhost." \
    "MERGE-NOTES.md's unity-mcp row no longer states the stale claim as a present-tense fact"
