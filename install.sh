#!/usr/bin/env bash
#
# cloud-nine-unity — overlay installer
#
# Applies the cloud-nine-unity overlay on top of an existing everything-claude-unity (ECU)
# install in a Unity project. Copies overlay agents/commands/rules/templates NEXT TO ECU's
# under <project>/.claude/ — it warns and skips on any clash and never overwrites.
#
# Usage:
#   ./install.sh --project-dir /path/to/UnityProject [--with-mcp]
#
#   --project-dir <path>  Target Unity project root (default: current directory)
#   --with-mcp            Also add the CoplayDev Unity MCP package to Packages/manifest.json
#   -h, --help            Show this help
#
set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi
info()  { printf '%s\n' "${BLUE}==>${NC} $*"; }
ok()    { printf '%s\n' "${GREEN} ok${NC}  $*"; }
warn()  { printf '%s\n' "${YELLOW}warn${NC} $*"; }
err()   { printf '%s\n' "${RED}err ${NC} $*" >&2; }
die()   { err "$*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OVERLAY_DIR="$SCRIPT_DIR/overlay"

# ── Payload manifest (keep in sync with uninstall.sh / studio-doctor.sh) ──────
AGENTS="game-designer systems-designer level-designer narrative-director writer world-builder creative-director technical-director"
COMMANDS="brainstorm design-review map-systems design-system sprint-plan scope-check milestone-review estimate retrospective"
RULES="pc-console"
TEMPLATES="game-design-document architecture-decision-record sprint-plan game-concept systems-index"

ECU_REPO="https://github.com/XeldarAlz/everything-claude-unity"
MCP_PKG_NAME="com.coplaydev.unity-mcp"
MCP_PKG_URL="https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main"

# ── Args ─────────────────────────────────────────────────────────────────────
PROJECT_DIR="$(pwd)"
WITH_MCP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) PROJECT_DIR="${2:-}"; shift 2 ;;
    --with-mcp)    WITH_MCP=1; shift ;;
    -h|--help)     sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             die "Unknown argument: $1 (use --help)" ;;
  esac
done

[ -n "$PROJECT_DIR" ] || die "--project-dir requires a path"
[ -d "$OVERLAY_DIR" ] || die "Overlay payload not found at $OVERLAY_DIR — run install.sh from the cloud-nine-unity repo root."
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || die "Project directory not found: $PROJECT_DIR"

printf '%s\n' "${BOLD}cloud-nine-unity — overlay installer${NC}"
info "Project: $PROJECT_DIR"

# ── Step 1: Validate Unity project ───────────────────────────────────────────
[ -d "$PROJECT_DIR/Assets" ] || die "No Assets/ directory — this does not look like a Unity project."
[ -d "$PROJECT_DIR/ProjectSettings" ] || die "No ProjectSettings/ directory — this does not look like a Unity project."
ok "Unity project detected."

# ── Step 2: Verify ECU is installed ──────────────────────────────────────────
CLAUDE_DIR="$PROJECT_DIR/.claude"
ECU_MARKER_RULE="$CLAUDE_DIR/rules/architecture.md"
ECU_MARKER_SKILL="$CLAUDE_DIR/skills/core/unity-mcp-patterns/SKILL.md"
if [ ! -f "$ECU_MARKER_RULE" ] || [ ! -f "$ECU_MARKER_SKILL" ]; then
  err "everything-claude-unity (ECU) was not found in this project."
  err "cloud-nine-unity is an OVERLAY — install ECU first, then re-run this."
  err "Expected (ECU v1.5.0 layout):"
  err "    $ECU_MARKER_RULE"
  err "    $ECU_MARKER_SKILL"
  err ""
  err "Install ECU from: $ECU_REPO"
  err "    git clone $ECU_REPO"
  err "    cd everything-claude-unity && ./install.sh --project-dir \"$PROJECT_DIR\""
  exit 1
fi
ok "ECU detected (tested against ECU v1.5.0)."

# ── Step 3: Copy overlay payload (no overwrite) ──────────────────────────────
COPIED=0; SKIPPED=0
copy_one() {  # $1 = src file, $2 = dest file
  local src="$1" dest="$2"
  [ -f "$src" ] || { warn "missing in payload: $src"; return; }
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ]; then
    warn "exists, skipping (no overwrite): ${dest#$PROJECT_DIR/}"
    SKIPPED=$((SKIPPED+1))
  else
    cp "$src" "$dest"
    ok "installed: ${dest#$PROJECT_DIR/}"
    COPIED=$((COPIED+1))
  fi
}

info "Installing agents…"
for n in $AGENTS;    do copy_one "$OVERLAY_DIR/agents/$n.md"    "$CLAUDE_DIR/agents/$n.md";    done
info "Installing commands…"
for n in $COMMANDS;  do copy_one "$OVERLAY_DIR/commands/$n.md"  "$CLAUDE_DIR/commands/$n.md";  done
info "Installing rules…"
for n in $RULES;     do copy_one "$OVERLAY_DIR/rules/$n.md"     "$CLAUDE_DIR/rules/$n.md";     done
info "Installing templates…"
for n in $TEMPLATES; do copy_one "$OVERLAY_DIR/templates/$n.md" "$CLAUDE_DIR/templates/$n.md"; done

# ── Step 4: Verify MCP config (do NOT overwrite settings.json) ────────────────
SETTINGS="$CLAUDE_DIR/settings.json"
if [ -f "$SETTINGS" ]; then
  if grep -q 'unityMCP' "$SETTINGS"; then
    ok "MCP server 'unityMCP' is configured in settings.json."
  else
    warn "settings.json has no 'unityMCP' entry. ECU normally provides it."
    warn "Add it under \"mcpServers\" (see MCP-SETUP.md): { \"unityMCP\": { \"url\": \"http://localhost:8080/mcp\" } }"
  fi
else
  warn "No .claude/settings.json found (ECU usually creates it). See MCP-SETUP.md."
fi

# ── Step 5: Optional — add CoplayDev MCP package to manifest.json ─────────────
if [ "$WITH_MCP" -eq 1 ]; then
  MANIFEST="$PROJECT_DIR/Packages/manifest.json"
  if [ ! -f "$MANIFEST" ]; then
    warn "No Packages/manifest.json found — skipping --with-mcp."
  elif grep -q "$MCP_PKG_NAME" "$MANIFEST"; then
    ok "$MCP_PKG_NAME already in manifest.json."
  elif command -v python3 >/dev/null 2>&1; then
    PKG_NAME="$MCP_PKG_NAME" PKG_URL="$MCP_PKG_URL" python3 - "$MANIFEST" <<'PY'
import json, os, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
deps = data.setdefault("dependencies", {})
deps[os.environ["PKG_NAME"]] = os.environ["PKG_URL"]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
    ok "Added $MCP_PKG_NAME to manifest.json."
  else
    warn "python3 not available to edit manifest.json safely. Add this line under \"dependencies\":"
    warn "    \"$MCP_PKG_NAME\": \"$MCP_PKG_URL\""
  fi
fi

# ── Done ─────────────────────────────────────────────────────────────────────
printf '\n%s\n' "${BOLD}Overlay applied.${NC} Installed: $COPIED  ·  Skipped (already present): $SKIPPED"
cat <<EOF

Next steps:
  1. Set up the Unity MCP — see MCP-SETUP.md (Window > MCP for Unity > Auto-Setup; Python 3.10+ & uv).
  2. Copy this overlay's CLAUDE.md into your project root and fill in the FILL: markers
     (genre, pillars, vision, scope). The architecture section is fixed on purpose.
  3. In Claude Code, try /brainstorm  (or check that the 9 commands appear in /help).
  4. Health check any time:  ./scripts/studio-doctor.sh --project-dir "$PROJECT_DIR"
EOF
[ "$SKIPPED" -gt 0 ] && warn "Some files already existed and were left untouched (no overwrite)."
exit 0
