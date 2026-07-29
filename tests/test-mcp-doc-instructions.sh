#!/usr/bin/env bash
# ============================================================================
# test-mcp-doc-instructions.sh — no instruction in .claude/ sends a reader
# back to the file Claude Code never reads MCP config from.
#
# Task 2 moved MCP server configuration to .mcp.json at the project root,
# because Claude Code silently ignores an mcpServers key inside settings.json.
# Task 8 found two stale instructions still pointing at the dead location:
#   .claude/commands/unity-doctor.md:19  — fixed by this same commit
#   docs/GETTING-STARTED.md:173          — fixed by this same commit, but is
#       NOT scanned here: it lives under docs/, and this guard is deliberately
#       scoped to .claude/ — see the scope note below.
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
# The pattern below is deliberately not just `grep mcpServers`: it looks for
# `settings.json` and `mcp` (case-insensitive) on the SAME LINE, so it catches
# any future phrasing of "look for MCP config in settings.json" — not only
# today's exact wording — while leaving alone the many .claude/ files that
# mention "MCP" or "settings.json" separately for unrelated reasons (hook
# registration lives in settings.json; dozens of agents/commands mention MCP
# tools with no connection to settings.json at all). The exclusion character
# class is periods, not backticks or whitespace: "mcpServers.unityMCP.url"
# itself contains periods, so the scan only needs to bridge the handful of
# punctuation-free characters between "settings.json" and the word "mcp" on
# the same line, not the whole rest of the sentence.
# ============================================================================

set +e
TMDI_HITS=$(cd "$REPO_DIR" && git grep -niE 'settings\.json[^.]*mcp|mcp[^.]*settings\.json' -- .claude/)
TMDI_RC=$?
set -e

# git grep exits 1 on "no match" (the success case here). Exit codes >= 2
# (bad pathspec, corrupt index) must not be silently read as "clean".
if [ "$TMDI_RC" -gt 1 ]; then
    echo "--- git grep exited $TMDI_RC, expected 0 or 1 ---"
    echo "$TMDI_HITS"
    echo "--- end git grep output ---"
fi
assert_eq "0" "$([ "$TMDI_RC" -le 1 ] && echo 0 || echo "$TMDI_RC")" \
    "the settings.json/mcp scan's git grep exited 0 or 1, not an error code"

if [ -n "$TMDI_HITS" ]; then
    echo "--- offending line(s) in .claude/ still point at settings.json for MCP config ---"
    echo "$TMDI_HITS"
    echo "--- end offenders ---"
fi
assert_eq "" "$TMDI_HITS" \
    "no line under .claude/ tells a reader to find MCP config in settings.json"

# --- Guard: the pattern still binds (proves it isn't accidentally matching
# nothing forevermore). Reconstruct the exact string the old unity-doctor.md
# line used to carry and confirm the pattern would catch it if it came back.
TMDI_CANARY='Check `.claude/settings.json` -> `mcpServers.unityMCP.url`'
if printf '%s\n' "$TMDI_CANARY" | grep -niE 'settings\.json[^.]*mcp|mcp[^.]*settings\.json' > /dev/null; then
    TMDI_CANARY_CAUGHT="caught"
else
    TMDI_CANARY_CAUGHT="missed"
fi
assert_eq "caught" "$TMDI_CANARY_CAUGHT" \
    "the pattern still catches the exact stale instruction that was just fixed"

# --- Positive control: the fixed instruction now names the real location ---
TMDI_DOCTOR_LINE=$(grep -n "mcpServers.unityMCP.url" "${REPO_DIR}/.claude/commands/unity-doctor.md" || true)
assert_contains "$TMDI_DOCTOR_LINE" ".mcp.json" \
    "unity-doctor.md's MCP connectivity check now names .mcp.json, not settings.json"
