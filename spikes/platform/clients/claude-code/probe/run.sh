#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Claude Code client-probe live pass 1 — the procedure that produced the
# evidence in docs/research/platform-spike/.../client-probe-claudecode/.
#
# OPERATOR AUTHORISATION REQUIRED. This script installs a plugin into a Claude
# Code profile and then runs headless (`claude -p`) agent sessions that are
# permitted to edit files. Run it only with explicit authorisation, only
# against a DISPOSABLE config root, and only against the disposable project
# that create-project.sh builds.
#
# It must NEVER be pointed at a real ~/.claude. CLAUDE_CONFIG_DIR is set to
# $KINGLET_LIVE_BASE/cfg and the script aborts if that resolves to the
# operator's real config directory.
#
# It does NOT copy credentials. Provisioning the disposable config root with a
# logged-in session is a manual operator prerequisite — see runbook.md,
# "Step 0 — Provision the disposable config root".
#
# Usage:
#   KINGLET_LIVE_BASE=/some/disposable/dir bash .../probe/run.sh
#
# Environment:
#   KINGLET_LIVE_BASE   (required) disposable root for cfg/, pkg/, project/, artifacts/
#   KINGLET_REPO_ROOT   (optional) repo root; defaults to this script's repo
#   KINGLET_PROBE_MODEL (optional) model passed to `claude --model`; default sonnet
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="${KINGLET_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../../../.." && pwd)}"
MODEL="${KINGLET_PROBE_MODEL:-sonnet}"

if [ -z "${KINGLET_LIVE_BASE:-}" ]; then
  echo "run.sh: set KINGLET_LIVE_BASE to a disposable directory first" >&2
  exit 1
fi
BASE="$KINGLET_LIVE_BASE"
PKG="$BASE/pkg"
CFG="$BASE/cfg"
PROJ="$BASE/project"
ART="$BASE/artifacts"

# --- safety: never touch the operator's real config -------------------------
mkdir -p "$CFG"
real_home_config="$(cd "$HOME" && pwd)/.claude"
if [ "$(cd "$CFG" && pwd)" = "$real_home_config" ]; then
  echo "run.sh: refusing to run against the real config root ($real_home_config)" >&2
  exit 1
fi
if [ ! -f "$CFG/.credentials.json" ]; then
  echo "run.sh: $CFG/.credentials.json is missing." >&2
  echo "run.sh: provision the disposable config root first (runbook.md, Step 0)." >&2
  exit 1
fi

# sha256_of <file> — portable digest (Linux coreutils / macOS shasum).
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1; exit}'
  else
    shasum -a 256 "$1" | awk '{print $1; exit}'
  fi
}

# prompt_text <prompt-id> — the frozen prompt body, by ID. Prompt text is never
# inlined here: prompts-v1.json is the single source and evidence references it
# by ID and SHA-256.
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

rm -rf "$PKG" "$PROJ" "$ART"
mkdir -p "$PKG" "$ART"

export CLAUDE_CONFIG_DIR="$CFG"

# Strip inherited plugin/marketplace state from the DISPOSABLE config so
# discovery starts cold. Operates on $CFG only; the real config is untouched.
if [ -f "$CFG/.claude.json" ]; then
  python3 - "$CFG/.claude.json" <<'PY'
import json, sys
path = sys.argv[1]
config = json.load(open(path, encoding="utf-8"))
for key in ("installedPlugins", "enabledPlugins", "knownMarketplaces", "plugins"):
    config.pop(key, None)
config["projects"] = {}
json.dump(config, open(path, "w", encoding="utf-8"))
PY
fi

# --- disposable project -----------------------------------------------------
bash "$REPO/spikes/platform/clients/shared/create-project.sh" "$PROJ" \
  > "$ART/create-project.txt" 2>&1

# --- assemble package -------------------------------------------------------
cp -r "$REPO/spikes/platform/clients/claude-code/." "$PKG"
rm -rf "$PKG/probe"
mkdir -p "$PKG/skills/kinglet-capability-probe" "$PKG/agents" "$PKG/bin"
cp "$REPO/spikes/platform/clients/shared/skills/kinglet-capability-probe/SKILL.md" \
   "$PKG/skills/kinglet-capability-probe/SKILL.md"
cp "$REPO/spikes/platform/clients/shared/agents/kinglet-capability-reviewer.agent.md" \
   "$PKG/agents/kinglet-capability-reviewer.agent.md"
cp "$REPO/spikes/platform/clients/probe-host/dist/linux-amd64/kinglet-client-probe" \
   "$PKG/bin/kinglet-client-probe"
chmod +x "$PKG/bin/kinglet-client-probe"

cd "$PROJ"

# --- install ----------------------------------------------------------------
claude plugin marketplace add "$PKG"        > "$ART/marketplace-add.txt" 2>&1
claude plugin install kinglet-client-probe@kinglet-client-probe --scope local \
                                            > "$ART/plugin-install.txt" 2>&1
claude plugin list                          > "$ART/plugin-list.txt" 2>&1
claude --version                            > "$ART/claude-version.txt" 2>&1

# `plugin list` is the real gate: a manifest can validate at exit 0 and still
# report "failed to load". No observation under a non-loading plugin is valid.
if grep -q "failed to load" "$ART/plugin-list.txt"; then
  echo "ABORT: plugin failed to load" >&2
  cat "$ART/plugin-list.txt" >&2
  exit 1
fi

run_prompt() {
  if [ "$#" -lt 1 ]; then
    echo "run_prompt: need a prompt id" >&2
    return 1
  fi
  id="$1"
  shift
  text="$(prompt_text "$id")"
  claude -p "$text" --model "$MODEL" --output-format stream-json --verbose \
    "$@" > "$ART/$id-stream.jsonl" 2> "$ART/$id.err" < /dev/null || true
}

# --- mutation-block-01: hook must deny the Write ----------------------------
# acceptEdits removes the permission prompt so the PreToolUse hook is the gate.
sha_before="$(sha256_of "$PROJ/Assets/Protected.txt")"
run_prompt mutation-block-01 --permission-mode acceptEdits
sha_after="$(sha256_of "$PROJ/Assets/Protected.txt")"
{
  echo "sha_before=$sha_before"
  echo "sha_after=$sha_after"
  echo "unchanged=$([ "$sha_before" = "$sha_after" ] && echo yes || echo no)"
  cat "$PROJ/Assets/Protected.txt"
} > "$ART/mutation-block-01-file.txt"

# --- mcp-call-01 ------------------------------------------------------------
run_prompt mcp-call-01 --permission-mode acceptEdits

# --- install.update ---------------------------------------------------------
# POSIX sed (no GNU -i): rewrite to a temp file, then move.
sed 's/"version": "0.0.1"/"version": "0.0.2"/' "$PKG/.claude-plugin/plugin.json" \
  > "$PKG/.claude-plugin/plugin.json.tmp" && mv "$PKG/.claude-plugin/plugin.json.tmp" "$PKG/.claude-plugin/plugin.json"
sed 's/"version": "0.0.1"/"version": "0.0.2"/' "$PKG/.claude-plugin/marketplace.json" \
  > "$PKG/.claude-plugin/marketplace.json.tmp" && mv "$PKG/.claude-plugin/marketplace.json.tmp" "$PKG/.claude-plugin/marketplace.json"
claude plugin marketplace update kinglet-client-probe > "$ART/marketplace-update.txt" 2>&1 || true
{
  echo "--- attempt: plugin update <name> --scope local"
  claude plugin update kinglet-client-probe --scope local 2>&1 || true
  echo "--- attempt: plugin update <name>@<marketplace> --scope local"
  claude plugin update kinglet-client-probe@kinglet-client-probe --scope local 2>&1 || true
} > "$ART/plugin-update.txt"
claude plugin list > "$ART/plugin-list-after-update.txt" 2>&1

# --- install.remove ---------------------------------------------------------
claude plugin uninstall kinglet-client-probe --scope local > "$ART/plugin-uninstall.txt" 2>&1 || true
claude plugin list > "$ART/plugin-list-after-uninstall.txt" 2>&1

echo "DONE — artifacts in $ART"
