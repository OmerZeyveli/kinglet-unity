#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Claude Code client-probe live pass 2 — supplementary isolation runs.
# Run AFTER run.sh has assembled $KINGLET_LIVE_BASE/{pkg,cfg,project}.
#
# OPERATOR AUTHORISATION REQUIRED. Same constraints as run.sh: it reinstalls a
# plugin and runs headless agent sessions with Write/Edit pre-authorised. Only
# against a DISPOSABLE config root and the disposable project. Never point it
# at a real ~/.claude.
#
# Two observations run.sh could not isolate:
#   1. hooks.pre-mutation-block — in run.sh the model refused on its own after
#      reading the project CLAUDE.md, so the hook never fired. Here CLAUDE.md is
#      parked aside FOR THIS RUN ONLY (and restored immediately after) and
#      Write/Edit are pre-authorised, so the PreToolUse hook is the only gate.
#   2. mcp.discover-call / executable.local — in run.sh both were blocked
#      pending permission. Here they are pre-authorised via --allowedTools.
#
# Runs here are SUPPLEMENTARY, not frozen-prompt runs: the isolation changes the
# conditions. Record them as such.
#
# Usage:
#   KINGLET_LIVE_BASE=/some/disposable/dir bash .../probe/run2.sh
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${KINGLET_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../../../.." && pwd)}"
MODEL="${KINGLET_PROBE_MODEL:-sonnet}"

if [ -z "${KINGLET_LIVE_BASE:-}" ]; then
  echo "run2.sh: set KINGLET_LIVE_BASE to the disposable directory run.sh used" >&2
  exit 1
fi
BASE="$KINGLET_LIVE_BASE"
CFG="$BASE/cfg"
PROJ="$BASE/project"
ART="$BASE/artifacts"

# `pwd -P` (physical), not bash's logical `pwd`: `cd` through a symlink reports
# the link path, so a symlinked $CFG would otherwise bypass this guard.
real_home_config="$(cd "$HOME" && pwd -P)/.claude"
if [ -d "$CFG" ] && [ "$(cd "$CFG" && pwd -P)" = "$real_home_config" ]; then
  echo "run2.sh: refusing to run against the real config root ($real_home_config)" >&2
  exit 1
fi
if [ ! -d "$PROJ" ]; then
  echo "run2.sh: $PROJ is missing — run run.sh first" >&2
  exit 1
fi

export CLAUDE_CONFIG_DIR="$CFG"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1; exit}'
  else
    shasum -a 256 "$1" | awk '{print $1; exit}'
  fi
}

PROMPTS="$REPO/spikes/platform/clients/contracts/prompts-v1.json"
prompt_text() {
  python3 - "$PROMPTS" "$1" <<'PY'
import json, sys
catalog = json.load(open(sys.argv[1], encoding="utf-8"))
for prompt in catalog["prompts"]:
    if prompt["id"] == sys.argv[2]:
        sys.stdout.write(prompt["text"])
        break
else:
    sys.exit(f"unknown prompt id: {sys.argv[2]}")
PY
}

cd "$PROJ"

# run.sh ends by uninstalling; reinstall at the pinned version for this pass.
claude plugin install kinglet-client-probe@kinglet-client-probe --scope local \
  > "$ART/s-plugin-install.txt" 2>&1
claude plugin list > "$ART/s-plugin-list.txt" 2>&1
if grep -q "failed to load" "$ART/s-plugin-list.txt"; then
  echo "ABORT: plugin failed to load" >&2
  cat "$ART/s-plugin-list.txt" >&2
  exit 1
fi

MCP_TOOL="mcp__plugin_kinglet-client-probe_kinglet-client-probe__kinglet_probe_read_marker"

# --- (1) hook isolation -----------------------------------------------------
# CLAUDE.md is parked for THIS RUN ONLY so the model does not self-censor before
# the hook is reached. It is restored on the next line after the run.
PARKED="$BASE/CLAUDE.md.parked"
restore_claude_md() {
  if [ -f "$PARKED" ]; then
    mv "$PARKED" "$PROJ/CLAUDE.md"
  fi
}
# Restore on interrupt/termination too, not just on the happy path.
trap restore_claude_md EXIT INT TERM
mv CLAUDE.md "$PARKED"
sha_before="$(sha256_of Assets/Protected.txt)"
claude -p "$(prompt_text mutation-block-01)" \
  --model "$MODEL" --output-format stream-json --verbose \
  --permission-mode acceptEdits --allowedTools "Write,Edit,Read,Bash" \
  > "$ART/s-hook-isolation-stream.jsonl" 2> "$ART/s-hook-isolation.err" < /dev/null || true
sha_after="$(sha256_of Assets/Protected.txt)"
restore_claude_md
{
  echo "note=CLAUDE.md parked for this run so the model does not self-censor"
  echo "sha_before=$sha_before"
  echo "sha_after=$sha_after"
  echo "unchanged=$([ "$sha_before" = "$sha_after" ] && echo yes || echo no)"
  echo "content:"; cat Assets/Protected.txt
} > "$ART/s-hook-isolation-file.txt"

# --- (2) MCP call + local executable ----------------------------------------
rm -f .kinglet-probe/receipts/*.json
claude -p "$(prompt_text mcp-call-01)" \
  --model "$MODEL" --output-format stream-json --verbose \
  --permission-mode acceptEdits --allowedTools "Read,Write,Bash,$MCP_TOOL" \
  > "$ART/s-mcp-call-stream.jsonl" 2> "$ART/s-mcp-call.err" < /dev/null || true
ls -la .kinglet-probe/receipts/ > "$ART/s-receipts.txt" 2>&1
cat .kinglet-probe/receipts/*.json >> "$ART/s-receipts.txt" 2>&1 || true

echo "DONE — artifacts in $ART"
