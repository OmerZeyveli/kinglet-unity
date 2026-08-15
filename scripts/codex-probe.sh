#!/usr/bin/env bash
#
# codex-probe.sh — run one Codex probe headless under a disposable CODEX_HOME.
#
# Why disposable: the owner's real ~/.codex carries their model choice, their
# reasoning effort, their trusted-project list and their MCP servers. A probe
# that ran against it would measure their configuration, not Kinglet's payload.
#
# Two behaviours were measured on 2026-08-15 against codex-cli 0.145.0 and are
# load-bearing here:
#   * without stdin redirected, `codex exec` prints "Reading additional input
#     from stdin..." and blocks;
#   * a CODEX_HOME under /tmp makes codex warn that it refuses to create helper
#     binaries there, polluting every probe's stderr.
#
set -euo pipefail

EXIT_USAGE=64

usage() {
  cat <<'EOF'
Usage: scripts/codex-probe.sh --name NAME --prompt FILE [options]

  --name NAME       probe name; names the four evidence files
  --prompt FILE     file holding the prompt text
  --workdir DIR     directory Codex runs in           (default: repo root)
  --seed DIR        directory copied into CODEX_HOME  (default: none)
  --sandbox MODE    read-only | workspace-write | danger-full-access
                                                      (default: read-only)
  --out DIR         evidence directory                (default: docs/research/codex-client/evidence)
  --model MODEL     model override passed to codex

Writes NAME.jsonl, NAME.last.txt, NAME.stderr.txt and NAME.meta.json into the
evidence directory. Exits with codex's own exit code.
EOF
}

die() { printf 'codex-probe: %s\n' "$*" >&2; exit "$EXIT_USAGE"; }

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

NAME=""
PROMPT_FILE=""
WORKDIR="$REPO_DIR"
SEED_DIR=""
SANDBOX_MODE="read-only"
OUT_DIR="$REPO_DIR/docs/research/codex-client/evidence"
MODEL=""

# Validate before shifting: under `set -u`, `shift 2` with one argument left
# fails before the error message prints and the caller gets a silent exit 1.
while [ $# -gt 0 ]; do
  case "$1" in
    --name)    [ $# -ge 2 ] || die "--name requires a value"; NAME="$2"; shift 2 ;;
    --prompt)  [ $# -ge 2 ] || die "--prompt requires a value"; PROMPT_FILE="$2"; shift 2 ;;
    --workdir) [ $# -ge 2 ] || die "--workdir requires a value"; WORKDIR="$2"; shift 2 ;;
    --seed)    [ $# -ge 2 ] || die "--seed requires a value"; SEED_DIR="$2"; shift 2 ;;
    --sandbox) [ $# -ge 2 ] || die "--sandbox requires a value"; SANDBOX_MODE="$2"; shift 2 ;;
    --out)     [ $# -ge 2 ] || die "--out requires a value"; OUT_DIR="$2"; shift 2 ;;
    --model)   [ $# -ge 2 ] || die "--model requires a value"; MODEL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)         usage >&2; die "unknown argument: $1" ;;
  esac
done

[ -n "$NAME" ]        || { usage >&2; die "--name is required"; }
[ -n "$PROMPT_FILE" ] || { usage >&2; die "--prompt is required"; }
[ -f "$PROMPT_FILE" ] || die "prompt file not found: $PROMPT_FILE"
[ -d "$WORKDIR" ]     || die "workdir not found: $WORKDIR"
command -v codex >/dev/null 2>&1   || die "codex not found on PATH"
command -v python3 >/dev/null 2>&1 || die "python3 not found on PATH (needed to write NAME.meta.json)"

case "$NAME" in
  *[!A-Za-z0-9._-]*) die "probe name may hold only letters, digits, dot, dash and underscore: $NAME" ;;
esac

mkdir -p "$OUT_DIR"

# Clear this probe's previous outputs. NAME.jsonl and NAME.stderr.txt are
# truncated by the redirections below, but NAME.last.txt and NAME.meta.json are
# not — and a stale last.txt read as this run's answer is a silent wrong result.
rm -f "$OUT_DIR/$NAME.last.txt" "$OUT_DIR/$NAME.meta.json"

# The disposable home lives beside the evidence, deliberately not under /tmp.
PROBE_HOME="$OUT_DIR/.home-$NAME.$$"
cleanup() { rm -rf "$PROBE_HOME"; }
trap cleanup EXIT
rm -rf "$PROBE_HOME"
mkdir -p "$PROBE_HOME"
chmod 700 "$PROBE_HOME"

if [ -n "$SEED_DIR" ]; then
  [ -d "$SEED_DIR" ] || die "seed directory not found: $SEED_DIR"
  cp -R "$SEED_DIR/." "$PROBE_HOME/"
fi

# Auth: codex reads credentials from CODEX_HOME even under --ignore-user-config,
# so the disposable home needs a copy. It is mode 600 and dies with the trap.
if [ -f "$HOME/.codex/auth.json" ]; then
  cp "$HOME/.codex/auth.json" "$PROBE_HOME/auth.json"
  chmod 600 "$PROBE_HOME/auth.json"
fi

CODEX_VERSION="$(codex --version 2>/dev/null || echo unknown)"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

set -- exec --json --skip-git-repo-check --ignore-user-config \
  --sandbox "$SANDBOX_MODE" --cd "$WORKDIR" \
  -o "$OUT_DIR/$NAME.last.txt"
if [ -n "$MODEL" ]; then set -- "$@" --model "$MODEL"; fi

PROMPT_TEXT="$(cat "$PROMPT_FILE")"

# `< /dev/null` is not decoration: without it `codex exec` prints "Reading
# additional input from stdin..." and blocks forever under any caller whose own
# stdin is open.
set +e
CODEX_HOME="$PROBE_HOME" codex "$@" "$PROMPT_TEXT" \
  > "$OUT_DIR/$NAME.jsonl" 2> "$OUT_DIR/$NAME.stderr.txt" < /dev/null
CODEX_RC=$?
set -e

# `-o` is codex's own answer and is authoritative when it exists. It does not
# always: a run that fails before the first turn completes writes nothing there.
# Fall back to the last agent_message in the event stream, which is the same
# text by another route, so the file is always present and always current.
if [ ! -s "$OUT_DIR/$NAME.last.txt" ]; then
  PROBE_JSONL="$OUT_DIR/$NAME.jsonl" python3 -c '
import json, os, sys
last = ""
try:
    with open(os.environ["PROBE_JSONL"], "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except ValueError:
                continue
            item = event.get("item") or {}
            if event.get("type") == "item.completed" and item.get("type") == "agent_message":
                last = item.get("text", "")
except IOError:
    pass
sys.stdout.write(last + ("\n" if last and not last.endswith("\n") else ""))
' > "$OUT_DIR/$NAME.last.txt"
fi

# Metadata: written with python3 so the command array is JSON-correct even when
# a prompt or a path holds a quote.
CODEX_ARGS_JOINED="$*" \
CODEX_VERSION="$CODEX_VERSION" \
CODEX_RC="$CODEX_RC" \
PROBE_NAME="$NAME" \
PROBE_STAMP="$STAMP" \
PROBE_WORKDIR="$WORKDIR" \
PROBE_SANDBOX="$SANDBOX_MODE" \
PROBE_MODEL="$MODEL" \
PROBE_PROMPT="$PROMPT_FILE" \
python3 -c '
import json, os, sys
meta = {
    "name":        os.environ["PROBE_NAME"],
    "timestamp":   os.environ["PROBE_STAMP"],
    "codex_version": os.environ["CODEX_VERSION"],
    "exit_code":   int(os.environ["CODEX_RC"]),
    "workdir":     os.environ["PROBE_WORKDIR"],
    "sandbox":     os.environ["PROBE_SANDBOX"],
    "model":       os.environ["PROBE_MODEL"] or None,
    "prompt_file": os.environ["PROBE_PROMPT"],
    "codex_args":  os.environ["CODEX_ARGS_JOINED"],
}
sys.stdout.write(json.dumps(meta, indent=2) + "\n")
' > "$OUT_DIR/$NAME.meta.json"

printf 'codex-probe: %s -> %s (exit %d, codex %s)\n' \
  "$NAME" "$OUT_DIR" "$CODEX_RC" "$CODEX_VERSION" >&2

exit "$CODEX_RC"
