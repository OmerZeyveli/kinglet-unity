#!/usr/bin/env bash
#
# cloud-nine-unity — studio-doctor
#
# Health check for the overlay + its dependencies. Like ECU's /unity-doctor, but for the
# cloud-nine-unity layer: verifies Python/uv, the MCP bridge, that ECU is present, and that the
# overlay's files are installed. Reports PASS/WARN/FAIL per check; exits 0 (advisory).
#
# Usage:
#   ./scripts/studio-doctor.sh --project-dir /path/to/UnityProject
#
set -euo pipefail

if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi
PASS_C=0; WARN_C=0; FAIL_C=0
pass() { printf '%s\n' "${GREEN}PASS${NC} $*"; PASS_C=$((PASS_C+1)); }
warn() { printf '%s\n' "${YELLOW}WARN${NC} $*"; WARN_C=$((WARN_C+1)); }
fail() { printf '%s\n' "${RED}FAIL${NC} $*"; FAIL_C=$((FAIL_C+1)); }

AGENTS="game-designer systems-designer level-designer narrative-director writer world-builder creative-director technical-director"
COMMANDS="brainstorm design-review map-systems design-system sprint-plan scope-check milestone-review estimate retrospective"
RULES="pc-console"
TEMPLATES="game-design-document architecture-decision-record sprint-plan game-concept systems-index"

PROJECT_DIR="$(pwd)"
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) PROJECT_DIR="${2:-}"; shift 2 ;;
    -h|--help)     sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || { printf 'Project directory not found.\n' >&2; exit 2; }
CLAUDE_DIR="$PROJECT_DIR/.claude"

printf '%s\n' "${BOLD}cloud-nine-unity — studio-doctor${NC}"
printf 'Project: %s\n\n' "$PROJECT_DIR"

# ── Environment: Python 3.10+ ────────────────────────────────────────────────
PY=""
command -v python3 >/dev/null 2>&1 && PY=python3
[ -z "$PY" ] && command -v python >/dev/null 2>&1 && PY=python
if [ -n "$PY" ]; then
  if "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then
    pass "Python $($PY -c 'import platform;print(platform.python_version())') (>= 3.10)"
  else
    warn "Python found but < 3.10 ($($PY --version 2>&1)) — the Unity MCP server needs 3.10+."
  fi
else
  warn "Python not found — the Unity MCP server needs Python 3.10+ (see MCP-SETUP.md)."
fi

# ── Environment: uv ──────────────────────────────────────────────────────────
if command -v uv >/dev/null 2>&1; then
  pass "uv present ($(uv --version 2>&1 | head -n1))"
else
  warn "uv not found — the MCP server runs under uv (https://docs.astral.sh/uv/)."
fi

# ── MCP bridge reachable on :8080 (soft) ─────────────────────────────────────
if command -v curl >/dev/null 2>&1; then
  if curl -s -o /dev/null --max-time 3 http://localhost:8080/mcp 2>/dev/null; then
    pass "MCP bridge reachable at http://localhost:8080/mcp"
  else
    warn "MCP bridge not reachable at :8080 — open Unity and Window > MCP for Unity > Start Bridge."
  fi
else
  warn "curl not available — skipping MCP reachability check."
fi

# ── ECU present ──────────────────────────────────────────────────────────────
if [ -f "$CLAUDE_DIR/rules/architecture.md" ] && [ -f "$CLAUDE_DIR/skills/core/unity-mcp-patterns/SKILL.md" ]; then
  pass "ECU detected in .claude/ (base layer present)."
else
  fail "ECU not detected — install everything-claude-unity first (overlay requires it)."
fi

# ── settings.json MCP entry ──────────────────────────────────────────────────
if [ -f "$CLAUDE_DIR/settings.json" ] && grep -q 'unityMCP' "$CLAUDE_DIR/settings.json"; then
  pass "settings.json has the 'unityMCP' MCP entry."
else
  warn "No 'unityMCP' entry in .claude/settings.json (ECU usually provides it; see MCP-SETUP.md)."
fi

# ── Overlay files present ────────────────────────────────────────────────────
check_group() {  # $1 = label, $2 = subdir, $3 = names
  local label="$1" sub="$2" names="$3" present=0 total=0 miss=""
  for n in $names; do
    total=$((total+1))
    if [ -f "$CLAUDE_DIR/$sub/$n.md" ]; then present=$((present+1)); else miss="$miss $n"; fi
  done
  if [ "$present" -eq "$total" ]; then
    pass "$label: $present/$total installed."
  elif [ "$present" -eq 0 ]; then
    fail "$label: 0/$total installed — run install.sh."
  else
    warn "$label: $present/$total installed (missing:$miss)."
  fi
}
check_group "Overlay agents"    "agents"    "$AGENTS"
check_group "Overlay commands"  "commands"  "$COMMANDS"
check_group "Overlay rules"     "rules"     "$RULES"
check_group "Overlay templates" "templates" "$TEMPLATES"

# ── Summary ──────────────────────────────────────────────────────────────────
printf '\n%s\n' "${BOLD}Summary:${NC} ${GREEN}$PASS_C pass${NC}  ${YELLOW}$WARN_C warn${NC}  ${RED}$FAIL_C fail${NC}"
[ "$FAIL_C" -gt 0 ] && printf '%s\n' "Resolve FAIL items first (usually: install ECU, then run install.sh)."
exit 0
