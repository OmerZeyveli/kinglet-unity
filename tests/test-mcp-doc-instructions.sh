#!/usr/bin/env bash
# ============================================================================
# test-mcp-doc-instructions.sh — no instruction in .claude/ sends a reader
# back to the file Claude Code never reads MCP config from.
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
