#!/usr/bin/env bash
#
# Kinglet Pioneer — studio-doctor
#
# Health check for an installed toolkit and the environment it needs: Python/uv, the MCP bridge,
# settings.json wiring, and the integrity of the install itself.
#
# It verifies the install against .claude/state/install-receipt.tsv rather than looking for
# filenames it expects. That means it reports what actually happened — files gone missing, files you
# edited, files nobody installed — instead of just "present / not present".
#
# Usage:
#   ./scripts/studio-doctor.sh [--project-dir /path/to/UnityProject]
#
# Exits 1 if any check FAILs, 0 otherwise. (This used to always exit 0, which made it useless in CI.)
#
set -euo pipefail

if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi
PASS_C=0; WARN_C=0; FAIL_C=0
pass() { printf '%s\n' "${GREEN}PASS${NC} $*"; PASS_C=$((PASS_C + 1)); }
warn() { printf '%s\n' "${YELLOW}WARN${NC} $*"; WARN_C=$((WARN_C + 1)); }
fail() { printf '%s\n' "${RED}FAIL${NC} $*"; FAIL_C=$((FAIL_C + 1)); }

usage() { sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

PROJECT_DIR="$(pwd)"
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) [ $# -ge 2 ] || { printf 'err: --project-dir requires a path\n' >&2; exit 2; }
                   PROJECT_DIR="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *)             printf 'Unknown argument: %s (use --help)\n' "$1" >&2; exit 2 ;;
  esac
done
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || { printf 'Project directory not found.\n' >&2; exit 2; }
CLAUDE_DIR="$PROJECT_DIR/.claude"
RECEIPT="$CLAUDE_DIR/state/install-receipt.tsv"

printf '%s\n' "${BOLD}Kinglet Pioneer — studio-doctor${NC}"
printf 'Project: %s\n' "$PROJECT_DIR"
if [ -f "$CLAUDE_DIR/VERSION" ]; then
  VER=$(cat "$CLAUDE_DIR/VERSION")
  ECU_VER=$(sed -n 's/^ecu=//p' "$CLAUDE_DIR/UPSTREAM" 2>/dev/null || echo '?')
  printf 'Installed: Kinglet Pioneer %s (vendored ECU %s)\n' "$VER" "$ECU_VER"
fi
printf '\n'

# ── Environment: Python 3.10+ ────────────────────────────────────────────────
PY=""
command -v python3 >/dev/null 2>&1 && PY=python3
[ -z "$PY" ] && command -v python >/dev/null 2>&1 && PY=python
if [ -z "$PY" ]; then
  warn "Python not found. The MCP bridge needs Python 3.10+."
elif "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then
  pass "Python $("$PY" -c 'import sys; print("%d.%d"%sys.version_info[:2])') (3.10+ required)"
else
  warn "Python $("$PY" -c 'import sys; print("%d.%d"%sys.version_info[:2])' 2>/dev/null) is too old — the MCP bridge needs 3.10+."
fi

# ── Environment: uv ──────────────────────────────────────────────────────────
if command -v uv >/dev/null 2>&1; then
  pass "uv present ($(uv --version 2>/dev/null | head -1))"
else
  warn "uv not found — the MCP bridge runs under it. See https://docs.astral.sh/uv/"
fi

# ── MCP bridge reachable — and actually an MCP bridge ────────────────────────
#
# This used to be `curl -fsS http://localhost:8080/mcp` and passed on ANY HTTP response. On a machine
# where 8080 happened to be an unrelated nginx, it cheerfully reported "MCP bridge responding" at a
# web server that has never heard of Unity. That is the same defect as testing settings.json with a
# bare `grep unityMCP`: it proves something answered, not that the right thing answered.
#
# So: read the endpoint from the project's own config rather than hardcoding a port, then speak
# JSON-RPC and require an MCP-shaped reply.
read_mcp_url() {
  local f url=""
  # settings.local.json wins — that is where a machine-local port override belongs. .mcp.json is
  # where install.sh actually writes the server config (Task 2 moved it there because Claude Code
  # never read mcpServers out of settings.json); settings.json is kept as a last-resort fallback
  # for older installs that still have it there.
  for f in "$CLAUDE_DIR/settings.local.json" "$PROJECT_DIR/.mcp.json" "$CLAUDE_DIR/settings.json"; do
    [ -f "$f" ] || continue
    if command -v jq >/dev/null 2>&1; then
      url=$(jq -r '.mcpServers.unityMCP.url // empty' "$f" 2>/dev/null || true)
    elif [ -n "$PY" ]; then
      url=$("$PY" -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("mcpServers",{}).get("unityMCP",{}).get("url",""))
except Exception: pass' "$f" 2>/dev/null || true)
    fi
    if [ -n "$url" ]; then
      printf '%s' "$url"
      return 0
    fi
  done
  # Nothing matched. This must return 0: the caller does `MCP_URL=$(read_mcp_url)` under `set -e`,
  # and a bare fall-through here would return the exit status of the last `[ -n "$url" ] && { ... }`
  # — false — which kills the whole script two checks in and reports success on a project it never
  # examined the rest of. Returning 1 is a real failure; "no URL configured" is not one, it is a
  # WARN the caller already prints.
  return 0
}

MCP_URL=$(read_mcp_url)
if [ -z "$MCP_URL" ]; then
  warn "No mcpServers.unityMCP.url in settings — skipped the bridge check."
elif ! command -v curl >/dev/null 2>&1; then
  warn "curl not found — skipped the bridge check."
else
  # A real MCP server answers initialize with a JSON-RPC result naming itself. Streamable HTTP wants
  # both content types in Accept.
  MCP_REQ='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"studio-doctor","version":"1"}}}'
  MCP_RESP=$(curl -sS --max-time 5 -X POST "$MCP_URL" \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/json, text/event-stream' \
      -d "$MCP_REQ" 2>/dev/null || true)
  if [ -z "$MCP_RESP" ]; then
    warn "Nothing answered at $MCP_URL — open Unity and start the bridge (Window > MCP for Unity)."
  elif grep -q '"jsonrpc"' <<< "$MCP_RESP"; then
    SRV=$(printf '%s' "$MCP_RESP" | sed -n 's/.*"serverInfo"[^{]*{[^}]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    pass "MCP bridge answered at $MCP_URL${SRV:+ (${SRV})}"
  else
    # Something is listening, but it is not an MCP server. Say so — do not call it a bridge.
    fail "$MCP_URL is serving something that is NOT an MCP server."
    printf '     %s\n' "first bytes: $(printf '%s' "$MCP_RESP" | tr -d '\n' | cut -c1-70)"
    printf '     %s\n' "Another service holds that port. Point unityMCP at a free one in .claude/settings.local.json."
  fi
fi

# ── .mcp.json wiring (parsed, not grepped) ───────────────────────────────────
# This used to check .claude/settings.json — that was correct before Task 2, which moved the
# mcpServers key to .mcp.json at the project root because Claude Code never read it out of
# settings.json. Left pointed at settings.json, this check would FAIL every healthy install, since
# a correct install no longer puts mcpServers there at all. Check the file install.sh actually
# writes. The old check was also `grep -q unityMCP`, which passes on the word appearing in a
# comment or an unrelated key — the user can edit this file, so it gets a real parse.
MCP_JSON="$PROJECT_DIR/.mcp.json"
SETTINGS="$CLAUDE_DIR/settings.json"
if [ ! -f "$MCP_JSON" ]; then
  fail "No .mcp.json at project root — run install.sh."
else
  MCP_CONFIGURED=""
  if command -v jq >/dev/null 2>&1; then
    MCP_CONFIGURED=$(jq -r '.mcpServers.unityMCP.url // empty' "$MCP_JSON" 2>/dev/null || true)
  elif [ -n "$PY" ]; then
    MCP_CONFIGURED=$("$PY" -c 'import json,sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get("mcpServers", {}).get("unityMCP", {}).get("url", ""))
except Exception:
    pass' "$MCP_JSON" 2>/dev/null || true)
  fi
  if [ -n "$MCP_CONFIGURED" ]; then
    # Say which file actually wins. Reporting .mcp.json's URL while the probe above used a
    # different one from settings.local.json is two lines contradicting each other about the same
    # fact — the reader has to guess which is live.
    if [ -n "$MCP_URL" ] && [ "$MCP_URL" != "$MCP_CONFIGURED" ]; then
      pass ".mcp.json: unityMCP → $MCP_CONFIGURED (overridden by settings.local.json → $MCP_URL)"
    else
      pass ".mcp.json: mcpServers.unityMCP → $MCP_CONFIGURED"
    fi
  elif command -v jq >/dev/null 2>&1 || [ -n "$PY" ]; then
    fail ".mcp.json has no mcpServers.unityMCP.url — MCP tools will not work."
  else
    warn "Neither jq nor python available — could not parse .mcp.json."
  fi
fi

# ── New Input System package ─────────────────────────────────────────────────
# unity-specifics.md makes it non-negotiable and block-legacy-input.sh blocks the legacy API, but
# neither one checks that com.unity.inputsystem is actually installed. A project missing it cannot
# compile the first script written under its own rules, and that compile error also aborts Unity's
# -executeMethod, so Editor automation stops too (smoke-pass.md §6c). install.sh warns about this at
# install time; this lets an already-installed project find out without reinstalling.
INPUT_SYSTEM_PKG_NAME="com.unity.inputsystem"
MANIFEST="$PROJECT_DIR/Packages/manifest.json"
if [ ! -f "$MANIFEST" ]; then
  warn "No Packages/manifest.json — could not check for $INPUT_SYSTEM_PKG_NAME."
elif grep -q "$INPUT_SYSTEM_PKG_NAME" "$MANIFEST"; then
  pass "$INPUT_SYSTEM_PKG_NAME present in manifest.json"
else
  warn "$INPUT_SYSTEM_PKG_NAME is missing. unity-specifics.md makes the New Input System"
  warn "     non-negotiable and blocks legacy Input.* — the first script written under this"
  warn "     toolkit's own rules will fail to compile without it."
  warn "     Re-run install.sh --with-input-system to add it, or add it to manifest.json yourself."
fi

# ── Install integrity, against the receipt ───────────────────────────────────
if [ ! -d "$CLAUDE_DIR" ]; then
  fail "No .claude/ directory — run install.sh --project-dir \"$PROJECT_DIR\"."
elif [ ! -f "$RECEIPT" ]; then
  warn "No install receipt. .claude/ exists but Kinglet did not write it here"
  warn "     (a teammate's git clone will look like this — the receipt is machine-local)."
else
  VERIFIED=0; MODIFIED=0; MISSING=0
  MODIFIED_LIST=""; MISSING_LIST=""
  while IFS=$'\t' read -r rel recorded _mode _origin; do
    case "$rel" in ''|\#*|path) continue ;; esac
    abs="$PROJECT_DIR/$rel"
    if [ ! -f "$abs" ]; then
      MISSING=$((MISSING + 1)); MISSING_LIST="${MISSING_LIST}${rel}"$'\n'
    elif [ "$(sha256sum "$abs" 2>/dev/null | cut -d' ' -f1)" = "$recorded" ]; then
      VERIFIED=$((VERIFIED + 1))
    else
      MODIFIED=$((MODIFIED + 1)); MODIFIED_LIST="${MODIFIED_LIST}${rel}"$'\n'
    fi
  done < <(grep -v '^#' "$RECEIPT")

  if [ "$MISSING" -eq 0 ]; then
    pass "Install intact: $VERIFIED file(s) verified against the receipt"
  else
    fail "$MISSING receipted file(s) missing — re-run install.sh"
    printf '%s' "$MISSING_LIST" | head -5 | while IFS= read -r m; do [ -n "$m" ] && printf '       %s\n' "$m"; done
  fi
  if [ "$MODIFIED" -gt 0 ]; then
    # Not a failure. Editing the toolkit in place is legitimate; you just want to know you did,
    # because re-install will keep these and upstream fixes will not reach them.
    warn "$MODIFIED file(s) modified since install — install.sh will keep your versions:"
    printf '%s' "$MODIFIED_LIST" | head -5 | while IFS= read -r m; do [ -n "$m" ] && printf '       %s\n' "$m"; done
  fi
fi

# ── Payload sanity ───────────────────────────────────────────────────────────
if [ -d "$CLAUDE_DIR" ]; then
  A=$(find "$CLAUDE_DIR/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  C=$(find "$CLAUDE_DIR/commands" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  S=$(find "$CLAUDE_DIR/skills" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
  R=$(find "$CLAUDE_DIR/rules" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  printf 'INFO agents=%s commands=%s skills=%s rules=%s\n' "$A" "$C" "$S" "$R"
  [ -f "$CLAUDE_DIR/NOTICE.md" ] && pass "NOTICE.md present (third-party licenses travel with the copy)" \
                                 || fail "NOTICE.md missing — the vendored MIT notices must ship with .claude/"
  # Every hook settings.json references must exist, or the hook silently never fires.
  if [ -f "$SETTINGS" ]; then
    BROKEN=0
    for h in $(grep -oE '\.claude/hooks/[a-z_-]+\.sh' "$SETTINGS" 2>/dev/null | sort -u); do
      [ -f "$PROJECT_DIR/$h" ] || { fail "settings.json references a missing hook: $h"; BROKEN=$((BROKEN + 1)); }
    done
    [ "$BROKEN" -eq 0 ] && pass "All hooks referenced by settings.json exist"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
printf '\n%s\n' "${BOLD}$PASS_C passed · $WARN_C warning(s) · $FAIL_C failure(s)${NC}"
[ "$FAIL_C" -gt 0 ] && exit 1
exit 0
