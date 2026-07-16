#!/usr/bin/env bash
#
# cloud-nine-unity — studio-doctor
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

printf '%s\n' "${BOLD}cloud-nine-unity — studio-doctor${NC}"
printf 'Project: %s\n' "$PROJECT_DIR"
if [ -f "$CLAUDE_DIR/VERSION" ]; then
  VER=$(cat "$CLAUDE_DIR/VERSION")
  ECU_VER=$(sed -n 's/^ecu=//p' "$CLAUDE_DIR/UPSTREAM" 2>/dev/null || echo '?')
  printf 'Installed: cloud-nine-unity %s (vendored ECU %s)\n' "$VER" "$ECU_VER"
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
  # settings.local.json wins — that is where a machine-local port override belongs.
  for f in "$CLAUDE_DIR/settings.local.json" "$CLAUDE_DIR/settings.json"; do
    [ -f "$f" ] || continue
    if command -v jq >/dev/null 2>&1; then
      url=$(jq -r '.mcpServers.unityMCP.url // empty' "$f" 2>/dev/null || true)
    elif [ -n "$PY" ]; then
      url=$("$PY" -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("mcpServers",{}).get("unityMCP",{}).get("url",""))
except Exception: pass' "$f" 2>/dev/null || true)
    fi
    [ -n "$url" ] && { printf '%s' "$url"; return; }
  done
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
  elif printf '%s' "$MCP_RESP" | grep -q '"jsonrpc"'; then
    SRV=$(printf '%s' "$MCP_RESP" | sed -n 's/.*"serverInfo"[^{]*{[^}]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    pass "MCP bridge answered at $MCP_URL${SRV:+ (${SRV})}"
  else
    # Something is listening, but it is not an MCP server. Say so — do not call it a bridge.
    fail "$MCP_URL is serving something that is NOT an MCP server."
    printf '     %s\n' "first bytes: $(printf '%s' "$MCP_RESP" | tr -d '\n' | cut -c1-70)"
    printf '     %s\n' "Another service holds that port. Point unityMCP at a free one in .claude/settings.local.json."
  fi
fi

# ── settings.json wiring (parsed, not grepped) ───────────────────────────────
# The old check was `grep -q unityMCP`, which passes on the word appearing in a comment or an
# unrelated key. The user can edit this file, so it gets a real parse.
SETTINGS="$CLAUDE_DIR/settings.json"
if [ ! -f "$SETTINGS" ]; then
  fail "No .claude/settings.json — run install.sh."
else
  MCP_CONFIGURED=""
  if command -v jq >/dev/null 2>&1; then
    MCP_CONFIGURED=$(jq -r '.mcpServers.unityMCP.url // empty' "$SETTINGS" 2>/dev/null || true)
  elif [ -n "$PY" ]; then
    MCP_CONFIGURED=$("$PY" -c 'import json,sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get("mcpServers", {}).get("unityMCP", {}).get("url", ""))
except Exception:
    pass' "$SETTINGS" 2>/dev/null || true)
  fi
  if [ -n "$MCP_CONFIGURED" ]; then
    pass "settings.json: mcpServers.unityMCP → $MCP_CONFIGURED"
  elif command -v jq >/dev/null 2>&1 || [ -n "$PY" ]; then
    fail "settings.json has no mcpServers.unityMCP.url — MCP tools will not work."
  else
    warn "Neither jq nor python available — could not parse settings.json."
  fi
fi

# ── Install integrity, against the receipt ───────────────────────────────────
if [ ! -d "$CLAUDE_DIR" ]; then
  fail "No .claude/ directory — run install.sh --project-dir \"$PROJECT_DIR\"."
elif [ ! -f "$RECEIPT" ]; then
  warn "No install receipt. .claude/ exists but cloud-nine-unity did not write it here"
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
