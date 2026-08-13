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
# The second assertion exists because the derivation can break: if install.sh's heredoc is ever
# reformatted so the awk stops matching, SHIPPED_SERVER goes empty and the first assertion fails
# loudly against every real `mcp__...__` token in the scan (empty `want` matches nothing, so
# `tok != want` is true everywhere) — not silently. That failure is real but its message is noise: a
# wall of "declares mcp__X__ but install.sh writes " with no server name, for every file in scope,
# which reads like every agent drifted at once rather than like the derivation broke. The second
# assertion exists to name the actual cause directly instead of leaving it to be inferred from that
# noise.
# ============================================================================

echo "--- mcp naming ---"

# The server name install.sh writes into a fresh .mcp.json. Derived, never typed: the whole defect
# this guards was two files disagreeing about one string.
SHIPPED_SERVER=$(awk -F'"' '/^ *"[A-Za-z]*MCP": \{/ {print $2; exit}' "$REPO_DIR/install.sh")

# ── The scan must have scanned something ─────────────────────────────────────
#
# THE MEASUREMENT THIS BLOCK EXISTS FOR. With a violation planted in
# .claude/agents/unity-coder.md (`tools: …, mcp__unityMCP__manage_scene`), this file reported:
#
#   with a git index      1 PASS, 1 FAIL   ← the violation, caught
#   without a git index    2 PASS, 0 FAIL   ← a HIGHER pass count, on the same violation
#
# The file list below comes from `git ls-files`. With no index, git writes `fatal: not a git
# repository` to stderr, the substitution yields nothing, `for f in` iterates zero times, `BAD` is
# empty, and both assertions pass. Two green results over a payload nobody opened, reported as a
# cleaner run than the one that found the bug. That is not a hypothetical configuration: `git
# archive HEAD | tar -x` into a scratch directory is this repository's documented probe method, and
# it produces exactly that state.
#
# The rc is captured rather than promoted, and the list is counted. An unreadable index is a named
# failure; a list that is merely SHORT is a floor failure. Measured 2026-08-14, the pathspecs list
# 82 tracked paths: `.claude/*` 62, `scripts/*` 8, `docs/*` (less research/ and superpowers/) 6, and
# the six named root files. The floor is 40 — below `.claude/*` alone, so no plausible surface
# removal trips it, and above every other root combined, so a pathspec typo that drops `.claude/*`
# (the root carrying the agents whose `tools:` lines are the original defect) does.
TMN_LIST="$(mktemp "${TMPDIR:-/tmp}/kinglet-mcp-naming.XXXXXX")"
TMN_ERR="$(mktemp "${TMPDIR:-/tmp}/kinglet-mcp-naming-err.XXXXXX")"
TMN_RC=0
( cd "$REPO_DIR" && git ls-files '.claude/*' 'scripts/*' 'docs/*' install.sh uninstall.sh \
      CLAUDE.md CONTRIBUTING.md README.md MCP-SETUP.md \
      ':!docs/research/*' ':!docs/superpowers/*' ) > "$TMN_LIST" 2>"$TMN_ERR" || TMN_RC=$?
TMN_COUNT=$(awk 'END {print NR+0}' "$TMN_LIST")

TMN_SCAN_STATE="ok"
if [ "$TMN_RC" -ne 0 ]; then
  TMN_SCAN_STATE="git could not list the shipped payload (exit $TMN_RC): $(tr '\n' ' ' < "$TMN_ERR")"
elif [ "$TMN_COUNT" -lt 40 ]; then
  TMN_SCAN_STATE="only $TMN_COUNT tracked path(s) matched the pathspecs below, which is fewer than this payload can have — the scan is reading a fraction of the tree it certifies"
fi
assert_eq "ok" "$TMN_SCAN_STATE" \
  "the scan below has a payload to read — an empty file list must not certify the same green as a clean one"
rm -f "$TMN_ERR"

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
# Match where the name is USED, not where it is mentioned.
#
# The first version of this guard matched the string anywhere in a file's content. It caught the
# incident being documented: a skill citing the two casings to explain what went wrong tripped a
# guard about casing. Field note §81 has already ruled on this whole class — "a guard this easy to
# step around while blocking legitimate writes is mis-specified, not strict; it should match on the
# resolved target" — and notes that any substring match over text will fire on quotation.
#
# So: in Markdown only the frontmatter `tools:` line is load-bearing, because that is a permission
# grant. Prose naming the string is documentation and this repository must stay able to write its
# own history. In shell, every line except a comment is load-bearing, because a case pattern or a
# comparison against the wrong name silently stops matching — which is exactly how
# .claude/hooks/build-analyze.sh stopped recognising builds.
#
# docs/ is in scope: docs/AGENT-GUIDE.md ships copy-paste `tools:` templates and
# docs/GETTING-STARTED.md ships a .mcp.json snippet — the two files most likely to REINTRODUCE
# the defect were the two the first version of this guard could not see. docs/research/ and
# docs/superpowers/ are excluded: they are dated records of what was true when written, and a
# guard that forbids describing a past state stops the repository writing its own history
# (field note 81).
#
# adapters/ and tests/kinglet/ are excluded: they are the platform spike's own role schema, a
# different data model that ships into no project. Named here so the exclusion is a decision.
BAD=$(
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$REPO_DIR/$f" ] || continue
    case "$f" in
      *.md) SCAN_MODE=toolsline ;;
      *)    SCAN_MODE=noncomment ;;
    esac
    awk -v file="$f" -v want="$SHIPPED_SERVER" -v mode="$SCAN_MODE" '
      /^---/ { fm++ }
      {
        # A `tools:` line is a use wherever it appears: in frontmatter it is a permission grant,
        # and inside a fenced block it is a template someone copies into one. docs/AGENT-GUIDE.md
        # ships two of the latter. Prose naming the tool inline stays exempt — that is a mention.
        if (mode == "toolsline" && $0 !~ /^[[:space:]]*tools:/) next
        if (mode == "noncomment"  && $0 ~ /^[[:space:]]*#/) next
        line = $0
        while (match(line, /mcp__[A-Za-z0-9_]+__/)) {
          tok = substr(line, RSTART + 5, RLENGTH - 7)
          if (tok != want) print file "\t" tok
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' "$REPO_DIR/$f"
  done < "$TMN_LIST" | sort -u
)
rm -f "$TMN_LIST"

if [ -n "$BAD" ]; then
  printf '%s\n' "$BAD" | while IFS="$(printf '\t')" read -r src tok; do
    printf '%s declares mcp__%s__ but install.sh writes %s\n' "${src#$REPO_DIR/}" "$tok" "$SHIPPED_SERVER"
  done
fi
assert_eq "0" "$(printf '%s' "$BAD" | grep -c . || true)" \
  "no shipped file names an MCP server install.sh does not write"

assert_eq "found" "$([ -n "$SHIPPED_SERVER" ] && echo found || echo missing)" \
  "install.sh's .mcp.json heredoc still declares a server name this test can read"
