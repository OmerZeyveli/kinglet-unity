#!/usr/bin/env bash
# ============================================================================
# test-mcp-naming.sh — no shipped file names an MCP server install.sh does not write.
#
# All seven MCP-driving agents declared `tools: mcp__unityMCP__*`. The server
# CoplayDev's Auto-Setup actually registers is `UnityMCP` — capital U — so the
# glob matched nothing and every one of the seven was silently MCP-less.
# `install.sh` and every agent now spell it `UnityMCP`; this guard makes sure
# they cannot drift apart again.
#
# SHIPPED_SERVER is derived from install.sh's own heredoc, never hardcoded —
# the defect this guards against was two files disagreeing about one string,
# and a hardcoded expectation here would just be a third file to go stale.
# The second assertion exists because the derivation can silently break: if
# install.sh's heredoc is ever reformatted so the awk stops matching,
# SHIPPED_SERVER goes empty and the first assertion would pass against every
# agent while checking nothing.
# ============================================================================

echo "--- mcp naming ---"

# The server name install.sh writes into a fresh .mcp.json. Derived, never typed: the whole defect
# this guards was two files disagreeing about one string.
SHIPPED_SERVER=$(awk -F'"' '/^ *"[A-Za-z]*MCP": \{/ {print $2; exit}' "$REPO_DIR/install.sh")

# Scope is the whole shipped payload, not just agent frontmatter.
#
# The first version of this guard read only `tools:` lines in .claude/agents/*.md. It passed while
# .claude/hooks/build-analyze.sh — a registered PostToolUse hook — still matched
# *mcp__unityMCP__manage_build* and had therefore stopped recognising builds entirely. That is the
# same shape this repository has now found seven times: a check running over a set that is not the
# whole reality, and reporting clean.
#
# adapters/ and tests/kinglet/ are excluded on purpose: they belong to the platform-spike's own role
# schema, which is a different data model that ships into no project. They are named here so the
# exclusion is a decision rather than an oversight.
BAD=$(
  for f in $(cd "$REPO_DIR" && git ls-files '.claude/*' 'scripts/*' install.sh uninstall.sh); do
    [ -f "$REPO_DIR/$f" ] || continue
    awk -v file="$f" -v want="$SHIPPED_SERVER" '
      {
        line = $0
        while (match(line, /mcp__[A-Za-z0-9_]+__/)) {
          tok = substr(line, RSTART + 5, RLENGTH - 7)
          if (tok != want) print file "\t" tok
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' "$REPO_DIR/$f"
  done | sort -u
)

if [ -n "$BAD" ]; then
  printf '%s\n' "$BAD" | while IFS="$(printf '\t')" read -r src tok; do
    printf '%s declares mcp__%s__ but install.sh writes %s\n' "${src#$REPO_DIR/}" "$tok" "$SHIPPED_SERVER"
  done
fi
assert_eq "$(printf '%s' "$BAD" | grep -c . || true)" "0" \
  "no shipped file names an MCP server install.sh does not write"

assert_eq "$([ -n "$SHIPPED_SERVER" ] && echo found || echo missing)" "found" \
  "install.sh's .mcp.json heredoc still declares a server name this test can read"
