# Codex CLI Second Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `.claude/skills/subagent-driven-implementation/SKILL.md` (this repository's own loop — it carries the one-implementer rule and the ledger discipline this plan depends on) or `.claude/skills/unity-execution/SKILL.md` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure whether each of Kinglet's surface classes survives the crossing to Codex CLI, then ship exactly the subset the measurement proved works — with every exclusion named in writing.

**Architecture:** A committed probe harness runs Codex headless under a disposable `CODEX_HOME`, so every measurement is reproducible and none of it touches the owner's real configuration. Tasks 2–7 are measurements that convert the spec's "inferred, not verified" list into measured facts; Tasks 8–10 ship only what those measurements support. The findings document is a first-class deliverable, not a byproduct.

**Tech Stack:** bash (POSIX-ish, macOS 3.2 compatible), Python 3 for JSON reading only, `codex-cli 0.145.0`, the CoplayDev unity-mcp bridge on `http://127.0.0.1:8080/mcp` for Task 7 only.

## Global Constraints

Every task's requirements implicitly include this section.

- **Gates, both, after every task:** `bash tests/run-tests.sh` must report `Failed: 0`, and its header count must equal `ls tests/test-*.sh | wc -l`. `bash scripts/check-provenance.sh` must print exactly `provenance OK`.
- **Header count is measured with escapes stripped.** The runner colours its headers, so an anchored `grep -c '^--- test-.*\.sh ---'` on raw output returns 0 on a healthy suite. Use: `bash tests/run-tests.sh 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g' | grep -c '^--- test-.*\.sh ---'`.
- **Every newly tracked file needs a `provenance.tsv` row** or the orphan check fails. Columns, tab-separated: `path`, `origin`, `upstream_version`, `upstream_path`, `upstream_sha256`, `status`, `note`. Legal origins: `ecu|donchitos|superpowers|original`. Legal statuses: `verbatim|modified|original`. For an original file the middle three columns are each a single `-`.
- **Anything adapted from Superpowers is `origin=superpowers`, never `origin=original`.** Writing `original` for a row that has an upstream is a documented way this manifest rots.
- **Codex is pinned at 0.145.0 for this wave.** `0.147.0` is available; do not upgrade mid-wave. A hook-schema change between versions invalidates evidence, and the pin is what makes that detectable. Record `codex --version` in every probe's metadata.
- **Nothing in the spec's "inferred, NOT verified" list may be a task premise.** That list is: hook event names, the `hooks.json` filename, the `decision:block` protocol, `trusted_hash`, `MatcherGroup`, the external-agent config importer, and the `.codex`/`.agents`/`.claude`/`.cursor` string adjacency. Each is measured before anything depends on it. If a brief hands you one of these as a fact, that brief is wrong — stop and re-brief rather than proceeding.
- **A measurement task's deliverable is a recorded verdict, not a particular verdict.** "Codex ignores Kinglet's hooks" is a successful Task 4 if it is measured and recorded. An implementer who edits Kinglet to make a probe come out green has destroyed the thing the wave exists to produce.
- **One implementer at a time, absolutely, for Task 7.** The Unity Editor is one process holding one asset database; two agents driving it over MCP concurrently corrupt shared state as a broken scene, not as a merge conflict. Task 7 runs only when no other agent holds the Editor.
- **Shell: bash 3.2 compatible.** No `declare -A` (bash 4; macOS ships 3.2), no `grep -oP` (GNU-only).
- **Never pipe into a reader that exits early under `set -euo pipefail`.** `head` and `grep -q` both do this: the reader exits on first match, the writer gets SIGPIPE, `pipefail` turns 141 into failure, `set -e` kills the script. Use a here-string — `grep -qF -- "$needle" <<< "$haystack"` — or read the file with `awk`.
- **Validate an argument before `shift 2`.** Under `set -u`, `shift 2` with one argument left fails before your error message prints, and the user gets a silent exit 1.
- **New test files are self-contained**: they define their own assertion helpers and set `set -euo pipefail`, so `bash tests/<file>.sh` is a valid way to run one. Runner-provided files exit 0 having asserted nothing when run standalone.
- **Never commit a credential or a disposable `CODEX_HOME`.** Probing requires copying `~/.codex/auth.json` into the disposable home. That home is created mode 700, the copy is mode 600, and it is removed by an EXIT trap.
- **Interactive `grep` on this host is ugrep, and `find` is bfs.** Absence probes can return empty silently. Use `/usr/bin/grep` in scripts and when a negative result is load-bearing.

---

## File Structure

**Created by this plan, tracked:**

| Path | Responsibility |
|---|---|
| `scripts/codex-probe.sh` | Run one Codex probe headless under a disposable `CODEX_HOME`; write evidence and metadata. The only thing that launches Codex. |
| `tests/test-codex-probe.sh` | Guards the harness's isolation and failure behaviour, using a stub `codex` on `PATH` so no model call is made. |
| `docs/research/codex-client/README.md` | What this evidence is, how to re-run it, what the pinned versions are. |
| `docs/research/codex-client/codex-facts.md` | Codex's own capabilities, measured. Converts the spec's inferred list into measured or refuted, one claim per command. |
| `docs/research/codex-client/findings.md` | Per-surface verdicts, the A/B/C architecture decision, exclusions, and the stranded-machinery debt. |
| `docs/research/codex-client/evidence/.gitkeep` | Keeps the (otherwise ignored) evidence directory present. |
| `tests/test-codex-surface.sh` | Ship guard: derives the Codex surface list from the tree and fails on either side of the correspondence. Carries an anti-vacuity floor. |

**Created conditionally — only if the measurement supports them (Task 8):**

| Path | Condition |
|---|---|
| `AGENTS.md` | Task 6 measured that Codex loads it. |
| `.codex/hooks.json` | Task 3 measured the config location and schema, and Task 4 measured that Kinglet's hooks fire. Filename and shape come from Task 3's measurement, not from this table. |

**Modified:**

| Path | Change |
|---|---|
| `.gitignore` | Ignore raw probe transcripts and any disposable Codex home. |
| `provenance.tsv` | One row per new tracked file. |
| `install.sh` | Task 9: write the Codex layout, and record it in the receipt. |
| `uninstall.sh` | Task 9: remove what Task 9's installer wrote. |
| `README.md`, `docs/ARCHITECTURE.md` | Task 10: state the second client and its measured limits. |

---

## Task 1: The probe harness

**Files:**
- Create: `scripts/codex-probe.sh`
- Create: `tests/test-codex-probe.sh`
- Create: `docs/research/codex-client/README.md`
- Create: `docs/research/codex-client/evidence/.gitkeep`
- Modify: `.gitignore`
- Modify: `provenance.tsv`

**Interfaces:**
- Consumes: nothing.
- Produces: `scripts/codex-probe.sh`, invoked as
  `bash scripts/codex-probe.sh --name NAME --prompt FILE [--workdir DIR] [--seed DIR] [--sandbox MODE] [--out DIR] [--model MODEL]`.
  Writes four files into the evidence directory: `NAME.jsonl` (raw event stream), `NAME.last.txt` (final agent message), `NAME.stderr.txt` (Codex's stderr, which is where its warnings land), and `NAME.meta.json` (the exact command, `codex --version`, sandbox mode, model, workdir, exit code, UTC timestamp). Exits with Codex's exit code. Every later task calls it and reads those four files.

**Two facts measured on this host on 2026-08-15 that the harness must respect** — both were observed by running `codex exec` directly, and both silently break a naive harness:

1. **Without stdin redirected, `codex exec` blocks.** It prints `Reading additional input from stdin...` and waits. The harness must run Codex with `< /dev/null`.
2. **A `CODEX_HOME` under `/tmp` produces a warning**: `Refusing to create helper binaries under temporary dir "/tmp"`. It still proceeds, but the harness should create its disposable home outside `/tmp` so the warning does not pollute every probe's stderr. Use a directory beside the evidence output.

The event stream shape, also measured, is four line-delimited JSON objects for a trivial prompt:

```json
{"type": "thread.started", "thread_id": "01a00570-0699-77d1-a963-c59effab662b"}
{"type": "turn.started"}
{"type": "item.completed", "item": {"id": "item_0", "type": "agent_message", "text": "PROBE-OK"}}
{"type": "turn.completed", "usage": {"input_tokens": 13076, "cached_input_tokens": 9600, "cache_write_input_tokens": 0, "output_tokens": 8, "reasoning_output_tokens": 0}}
```

`item.type` is `agent_message` here; other values appear for command execution and MCP calls, and reading them is what Tasks 4–7 do.

- [ ] **Step 1: Write the failing test**

Create `tests/test-codex-probe.sh`. It stubs `codex` on `PATH`, so no model call is made and the test is free and offline.

```bash
#!/usr/bin/env bash
# Guards scripts/codex-probe.sh: isolation, argument safety, and failure reporting.
# A stub `codex` on PATH stands in for the real CLI — this test never calls a model.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }
check(){ if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (expected '$2', got '$1')"; fi; }
contains() {
  # here-string, never a pipe: `grep -q` exits on first match and would SIGPIPE the writer
  if /usr/bin/grep -qF -- "$2" <<< "$1"; then ok "$3"; else bad "$3 (needle '$2' absent)"; fi
}

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/codex-probe-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

# --- stub codex -------------------------------------------------------------
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/codex" <<'STUB'
#!/usr/bin/env bash
# Records how it was called, then emits a minimal valid event stream.
if [ "${1:-}" = "--version" ]; then echo "codex-cli 0.145.0-stub"; exit 0; fi
{
  echo "ARGS: $*"
  echo "CODEX_HOME: ${CODEX_HOME:-UNSET}"
  # If stdin is a TTY or a pipe with data, the harness failed to redirect it.
  if [ -t 0 ]; then echo "STDIN: tty"; else
    if IFS= read -r -t 0 _ 2>/dev/null; then echo "STDIN: readable"; else echo "STDIN: empty"; fi
  fi
} >> "$STUB_LOG"
printf '%s\n' \
  '{"type":"thread.started","thread_id":"stub"}' \
  '{"type":"turn.started"}' \
  '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"STUB-OK"}}' \
  '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$SANDBOX/bin/codex"

export STUB_LOG="$SANDBOX/stub.log"
: > "$STUB_LOG"
printf 'say hello\n' > "$SANDBOX/prompt.txt"

run_probe() {
  PATH="$SANDBOX/bin:$PATH" HOME="$SANDBOX/home" \
    bash "$REPO_DIR/scripts/codex-probe.sh" "$@" 2>&1
}
mkdir -p "$SANDBOX/home/.codex"
printf '{"stub":"credential"}' > "$SANDBOX/home/.codex/auth.json"

# --- 1. usage errors --------------------------------------------------------
set +e
out="$(run_probe 2>&1)"; rc=$?
set -e
check "$rc" "64" "no arguments exits 64 (usage), not 0"
contains "$out" "Usage:" "no arguments prints usage"

# A flag with no value must error with a message, not die silently in `shift 2`.
set +e
out="$(run_probe --name 2>&1)"; rc=$?
set -e
check "$rc" "64" "--name with no value exits 64"
contains "$out" "--name" "--name with no value names the offending flag"

# --- 2. a normal run --------------------------------------------------------
OUT="$SANDBOX/evidence"
set +e
out="$(run_probe --name smoke --prompt "$SANDBOX/prompt.txt" --out "$OUT" 2>&1)"; rc=$?
set -e
check "$rc" "0" "a normal run exits 0"
[ -f "$OUT/smoke.jsonl" ]     && ok "writes NAME.jsonl"      || bad "writes NAME.jsonl"
[ -f "$OUT/smoke.last.txt" ]  && ok "writes NAME.last.txt"   || bad "writes NAME.last.txt"
[ -f "$OUT/smoke.stderr.txt" ]&& ok "writes NAME.stderr.txt" || bad "writes NAME.stderr.txt"
[ -f "$OUT/smoke.meta.json" ] && ok "writes NAME.meta.json"  || bad "writes NAME.meta.json"
check "$(cat "$OUT/smoke.last.txt")" "STUB-OK" "last.txt holds the final agent message"

log="$(cat "$STUB_LOG")"
contains "$log" "STDIN: empty" "codex is invoked with stdin at /dev/null"

# --- 3. isolation -----------------------------------------------------------
home_line="$(/usr/bin/grep 'CODEX_HOME:' "$STUB_LOG" | head -1)"
case "$home_line" in
  *"CODEX_HOME: /tmp/"*) bad "disposable CODEX_HOME is not under /tmp" ;;
  *"CODEX_HOME: UNSET"*) bad "CODEX_HOME is set for the probe" ;;
  *)                     ok  "disposable CODEX_HOME is set and is not under /tmp" ;;
esac
contains "$log" "--ignore-user-config" "codex is invoked with --ignore-user-config"

# The disposable home held a credential; it must be gone.
probe_home="${home_line#*CODEX_HOME: }"
[ ! -e "$probe_home" ] && ok "the disposable CODEX_HOME is removed on exit" \
                       || bad "the disposable CODEX_HOME survived: $probe_home"

# --- 4. metadata ------------------------------------------------------------
meta="$(cat "$OUT/smoke.meta.json")"
contains "$meta" "0.145.0-stub" "meta records the codex version actually used"
contains "$meta" "\"exit_code\": 0" "meta records the exit code"

# --- 5. a failing codex run is reported, not swallowed -----------------------
set +e
STUB_EXIT=3 run_probe --name boom --prompt "$SANDBOX/prompt.txt" --out "$OUT" >/dev/null 2>&1
rc=$?
set -e
check "$rc" "3" "a non-zero codex exit propagates"
contains "$(cat "$OUT/boom.meta.json")" "\"exit_code\": 3" "meta records a non-zero exit"

printf '\n=== Codex Probe Harness: %d/%d passed, %d failed ===\n' \
  "$PASS" "$((PASS+FAIL))" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash tests/test-codex-probe.sh
```
Expected: FAIL — `scripts/codex-probe.sh` does not exist, so every run_probe call errors.

- [ ] **Step 3: Write the harness**

> **SUPERSEDED IN PART — read this before copying the listing below.** Task 1 shipped and its fix
> round changed two things in this file. `meta.json`'s `codex_args` (a space-joined string) is now
> **`codex_argv`, a JSON array that includes the prompt** — the old key does not exist, and Tasks 2–7
> read the new one. The harness also gained signal arms and a sweep that reclaims disposable homes
> whose pid is dead, because `SIGKILL` leaks by construction and nothing reclaimed the orphan. The
> listing below is kept as the brief that was given, not as a description of what shipped; read
> `scripts/codex-probe.sh` for that.

Create `scripts/codex-probe.sh`:

```bash
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
command -v codex >/dev/null 2>&1 || die "codex not found on PATH"

case "$NAME" in
  *[!A-Za-z0-9._-]*) die "probe name may hold only letters, digits, dot, dash and underscore: $NAME" ;;
esac

mkdir -p "$OUT_DIR"

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

set +e
CODEX_HOME="$PROBE_HOME" codex "$@" "$PROMPT_TEXT" \
  > "$OUT_DIR/$NAME.jsonl" 2> "$OUT_DIR/$NAME.stderr.txt" < /dev/null
CODEX_RC=$?
set -e

[ -f "$OUT_DIR/$NAME.last.txt" ] || : > "$OUT_DIR/$NAME.last.txt"

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
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash tests/test-codex-probe.sh
```
Expected: PASS on every assertion, ending `=== Codex Probe Harness: N/N passed, 0 failed ===`.

If the "disposable CODEX_HOME is removed on exit" assertion fails, the EXIT trap did not fire — check that no `exit` runs before `trap cleanup EXIT` is installed.

- [ ] **Step 5: Write the evidence directory and its README**

Create `docs/research/codex-client/evidence/.gitkeep` as an empty file.

Create `docs/research/codex-client/README.md`:

```markdown
# Codex client evidence

Raw evidence for the 2026-08-15 wave that measured whether Kinglet's surfaces
cross to Codex CLI. The spec is
`docs/superpowers/specs/2026-08-15-codex-cli-second-client-design.md`.

## Pinned versions

| Thing | Version | Why pinned |
|---|---|---|
| `codex-cli` | 0.145.0 | 0.147.0 was available during the wave and was deliberately not taken. A hook-schema change between versions invalidates this evidence; the pin makes that detectable rather than silent. |
| Unity MCP bridge | CoplayDev unity-mcp, `http://127.0.0.1:8080/mcp` | Task 7 only. |

## Re-running a probe

```bash
bash scripts/codex-probe.sh --name <name> --prompt <prompt-file>
```

Each probe writes four files here: `NAME.jsonl` (the event stream),
`NAME.last.txt` (the final agent message), `NAME.stderr.txt`, and
`NAME.meta.json` (the exact invocation, the codex version, the exit code).

**The transcripts are not committed.** They are large, they are not
deterministic between runs, and committing them would make every re-measurement
a diff. What is committed is the verdict, in `findings.md` and
`codex-facts.md`, each carrying the command that produced it — so a reader
re-runs rather than trusts.

## What is measured where

- `codex-facts.md` — Codex's own capabilities. Every claim carries the command
  that established it. This file is what turns the spec's "inferred, NOT
  verified" list into measured or refuted.
- `findings.md` — Kinglet's surfaces under Codex: one verdict per surface
  class, the architecture decision, and everything excluded.
```

- [ ] **Step 6: Ignore the transcripts and the disposable homes**

Append to `.gitignore`:

```gitignore
# Codex probe evidence: raw transcripts and disposable CODEX_HOMEs.
# The verdicts are committed in findings.md / codex-facts.md; the transcripts
# are large, non-deterministic, and a disposable home holds a copied credential.
docs/research/codex-client/evidence/*
!docs/research/codex-client/evidence/.gitkeep
```

- [ ] **Step 7: Add the provenance rows**

Append four tab-separated rows to `provenance.tsv`. Use literal tabs, not spaces:

```
scripts/codex-probe.sh	original	-	-	-	original	runs one Codex probe headless under a disposable CODEX_HOME; encodes two behaviours measured against codex-cli 0.145.0 on 2026-08-15 - codex exec blocks without stdin redirected, and a CODEX_HOME under /tmp warns about helper binaries
tests/test-codex-probe.sh	original	-	-	-	original	guards the probe harness with a stub codex on PATH: usage exits, shift-2 safety, stdin at /dev/null, CODEX_HOME isolation and removal, and a non-zero codex exit propagating rather than being swallowed
docs/research/codex-client/README.md	original	-	-	-	original	what the Codex client evidence is, the pinned codex-cli 0.145.0, how to re-run a probe, and why the transcripts are deliberately not committed
docs/research/codex-client/evidence/.gitkeep	original	-	-	-	original	keeps the gitignored evidence directory present in a fresh checkout
```

- [ ] **Step 8: Run both gates**

```bash
bash tests/run-tests.sh 2>&1 | tail -8
bash tests/run-tests.sh 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g' | /usr/bin/grep -c '^--- test-.*\.sh ---'
ls tests/test-*.sh | wc -l
bash scripts/check-provenance.sh | tail -1
```
Expected: `Failed: 0`; the two counts equal (both should now read 42); `provenance OK`.

- [ ] **Step 9: Commit**

```bash
git add scripts/codex-probe.sh tests/test-codex-probe.sh \
        docs/research/codex-client/README.md \
        docs/research/codex-client/evidence/.gitkeep \
        .gitignore provenance.tsv
git commit -m "feat(codex): probe harness that runs Codex under a disposable CODEX_HOME

Two traps were measured before the harness was written, and both silently
break a naive version: codex exec blocks when stdin is not redirected, and a
CODEX_HOME under /tmp warns that it refuses to create helper binaries there.

The harness is guarded by a stub codex on PATH, so the test makes no model
call and runs offline."
```

---

## Task 2: Does Codex import a `.claude/` configuration?

This is measured **first**, before any porting work, because if Codex natively
detects and imports a Claude Code configuration then most of this wave
collapses into a configuration line — and discovering that after building a
port is the expensive way to learn it.

**Files:**
- Create: `docs/research/codex-client/codex-facts.md`
- Modify: `provenance.tsv`

**Interfaces:**
- Consumes: `scripts/codex-probe.sh` from Task 1.
- Produces: `docs/research/codex-client/codex-facts.md` with a `## F1 — external agent configuration import` section. Tasks 3 and 8 read F1's verdict.

**The premise you must not accept.** The spec lists an external-agent importer among things *inferred from the binary's string table and not verified*: app-server methods `externalAgentConfig/detect`, `externalAgentConfig/import`, with fields `migration_type`, `agents_md`, `plugins`, `mcp_server_config`, `subagents`, `hooks`, `memory`, `skills_count`. **Treat all of that as a hypothesis to test, not a fact to use.** If it does not exist, that is a finding, and F1 records it as refuted.

- [ ] **Step 1: Establish what CLI and app-server surfaces exist**

```bash
codex --help
codex app-server --help
codex debug app-server --help
codex --version
```

Record the exact output. Do not infer a method's existence from the string table; a method exists when a call to it returns something other than "method not found".

- [ ] **Step 2: Drive the app-server and ask it for its method list**

> **CORRECTED AFTER MEASUREMENT (2026-08-15).** The pipeline this step originally gave —
> `printf '…' | timeout 30 codex app-server` — **cannot answer**. Closing stdin races the server's
> shutdown, so responses are dropped non-deterministically. Measured over 12 naive runs: six returned
> nothing at all, six returned only the `initialize` reply, and **in 12 of 12 the result of the
> method being probed never appeared**. A reader following the original literally would have
> concluded the method does not work. Hold stdin open until the reply you want has been read.

Establish the handshake and get the method list. Do not use a bare `printf |` pipeline; keep stdin
open for the lifetime of the exchange (a coprocess, a FIFO, or a heredoc that does not close early).

Ask the server to enumerate its own methods rather than guessing: sending a method name that cannot
exist returns a JSON-RPC error that lists the real ones. That enumeration is also your **negative
control** — it is what separates "this method exists" from "this server accepts anything".

If `codex app-server` is not the right entry point, try `codex debug app-server`, and record which
one works.

- [ ] **Step 3: Call the detect method against this repository**

> **CORRECTED AFTER MEASUREMENT (2026-08-15).** This step originally passed `{"cwd": "…"}`. **The
> real parameter is `cwds`, an array.** The wrong one does not error — it returns `{"items":[]}`,
> which reads exactly like *"no importer exists"*. Following the original literally records F1 as
> **refuted** and gets the wave's most consequential answer silently backwards.
>
> **The same trap applies to `hooks/list` and `skills/list`, which also take `cwds`** — and there it
> is worse: with `cwd` they return a well-formed answer *about the wrong repository*, which looks
> like a result rather than an error. Get every parameter shape from
> `codex app-server generate-json-schema` rather than from this plan or from a field name.

Call the detect method with the corrected parameter shape, against this repository's path.

Three outcomes, all of them findings:
- a result describing a detected `.claude/` configuration → F1 = **confirmed**, and record exactly
  which item types it reports;
- a JSON-RPC error `method not found` → F1 = **refuted by method-not-found**;
- no drivable route to the server at all → F1 = **refuted by absence of a route**, which is a
  different fact and means something different for a later Codex version.

Record every attempt including the failures. A list of parameter shapes that returned nothing is
part of this finding's value — an empty result is exactly what a wrong shape produces.

- [ ] **Step 4: If detect works, find out what import would actually do**

Do **not** run an import against the owner's real `~/.codex`. If a detect
result exists, run the import against a disposable home:

```bash
PROBE_HOME="$(mktemp -d "$PWD/docs/research/codex-client/evidence/.home-import.XXXXXX")"
chmod 700 "$PROBE_HOME"
cp ~/.codex/auth.json "$PROBE_HOME/auth.json" && chmod 600 "$PROBE_HOME/auth.json"
# ... drive externalAgentConfig/import with CODEX_HOME="$PROBE_HOME" ...
rm -rf "$PROBE_HOME"
```

Record what it wrote into that home: which files, and whether hooks, skills and
MCP servers came across. Then remove the home — it holds a credential.

- [ ] **Step 5: Write the finding**

Create `docs/research/codex-client/codex-facts.md`:

```markdown
# Codex CLI capabilities, measured

*Every claim here carries the command that established it. Nothing in this file
is read out of the binary's string table; the spec's "inferred, NOT verified"
list is what this file exists to resolve.*

**Measured against `codex-cli 0.145.0` on Pop!_OS 24.4.0 (noble), x86_64.**

## F1 — external agent configuration import

**Verdict:** <confirmed | refuted | partial>

**Command:**

```bash
<the exact command from Step 3>
```

**Observed:**

```
<verbatim output>
```

**What this means for the wave:** <if confirmed, which surface classes come
across for free and what is left to do by hand; if refuted, that every surface
class must be ported explicitly and the wave's remaining tasks stand as
written.>
```

Fill every angle-bracket placeholder with the real value. A section left with a
placeholder is a failed task, not a partial one.

- [ ] **Step 6: Add the provenance row**

```
docs/research/codex-client/codex-facts.md	original	-	-	-	original	Codex CLI capabilities measured by execution against codex-cli 0.145.0 - one claim per command, and each claim states whether it was measured or is explicitly left unmeasured for a later task
```

**The note must describe what the file actually contains at the time you write it.** The first
version of this row was written by the plan and claimed the block protocol was resolved while the
document said it was not — a note asserting a state the file it describes does not have. If a
question is still open when you commit, the note says so.

- [ ] **Step 7: Run both gates and commit**

```bash
bash tests/run-tests.sh 2>&1 | tail -6
bash scripts/check-provenance.sh | tail -1
git add docs/research/codex-client/codex-facts.md provenance.tsv
git commit -m "measure(codex): F1 — whether Codex imports a .claude configuration

Measured first, before any porting work: if Codex detects and imports a Claude
Code configuration natively, most of this wave collapses to a config line, and
learning that after building a port is the expensive order."
```

---

## Task 3: Codex's hook mechanism, measured

> **RE-PLANNED AFTER TASK 2 — this task has collapsed to one probe.**
>
> Task 2 measured F2–F5 as a side effect of driving the importer, and its two fix rounds measured
> more. **Already settled, do not re-measure:** the config file is `.codex/hooks.json` and the import
> writes it; the schema comes from `codex app-server generate-json-schema`; Codex normalises Claude
> Code's event names (5/4/2/1 across `PreToolUse`/`PostToolUse`/`SessionStart`/`Stop`); registration
> passes with `warnings: []` behind a **double trust gate**; `timeoutSec` is **seconds**, bracketed
> from both sides to `u ∈ (0.667 s, 1.5 s)`; and Codex accepts Claude Code's tool names as **matcher
> aliases**, so `Edit|Write` and `Bash` need no translation.
>
> **CORRECTION — this header was wrong when written, and its own task caught it.** It said *"what
> remains is F4 alone"* while Step 5 below and the Interfaces block still required **F5**, and Task 8
> depends on F5. A brief that contradicts itself moves the decision to whoever reads it next,
> silently. **Two things remain, not one.**
>
> **F4 — the block protocol.** Does a refusing hook actually stop the tool call, and does the model
> learn why? Note that the plan's own text describes a JSON `decision: block` shape, but Kinglet
> ships **exit 2 + stderr** via `unity_hook_block()` in `.claude/hooks/_lib.sh`. Both must be
> measured, separately.
>
> **F5 — hook trust, and it gates everything else.** `codex exec` carries
> `--dangerously-bypass-hook-trust`. Measured after the fact: **without that flag, with the project
> already trusted, the hook fired zero times** — the call went through, and there was no prompt, no
> warning and nothing logged. Meanwhile `hooks/list` reported `registered 1, warnings [], errors [],
> enabled=True, statusMessage=None`.
>
> **`enabled: true` does not mean it will run.** That is a fourth silent-failure layer on top of the
> three already measured, and it subsumes them: every F4 result was established behind a flag that
> is explicitly not a shipping answer. F5's real question is what a **non-interactive installer**
> must do to make a hook run legitimately — and if the answer is "a human, every time", that is the
> finding, and Task 8's ship list changes shape.
>
> Everything Task 2 settled is in `docs/research/codex-client/codex-facts.md` with the command that
> produced it. Read it first; re-running a settled measurement is wasted budget, and re-deriving one
> *differently* is how two numbers start disagreeing.

**Files:**
- Modify: `docs/research/codex-client/codex-facts.md` (add F2–F5)
- Modify: `provenance.tsv` (update the note on the `codex-facts.md` row)

**Interfaces:**
- Consumes: `scripts/codex-probe.sh`; F1's verdict from Task 2.
- Produces: F2 (config file location and name), F3 (accepted event names), F4 (the block protocol — what a hook returns to stop a tool call, and what the model sees), F5 (hash trust — whether registering a hook needs a human). Task 4 depends on F2–F4; Task 8 depends on F5.

**The premises you must not accept.** All of these come from the string table and are unverified: the filename `hooks.json`; the event names `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `SessionStart`, `SessionEnd`, `SubagentStart`, `SubagentStop`; the structure `MatcherGroup { matcher, hooks, trusted_hash }`; the strings `Command blocked by PreToolUse hook:` and `hook returned decision:block without a non-empty reason`; the `$SHELL -lc` command runner. Every one is a hypothesis. Measure each.

- [ ] **Step 1: Find where hook configuration is read from**

```bash
codex features list | /usr/bin/grep -i hook
codex --help
codex doctor 2>&1 | /usr/bin/grep -i -A3 hook
```

Then search Codex's own bundled resources, which are files rather than a string
table and are therefore real evidence:

```bash
V=/home/riive/.nvm/versions/node/v24.14.0/lib/node_modules/@openai/codex/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl
find "$V/codex-resources" -type f | head -50
/usr/bin/grep -rl 'hook' "$V/codex-resources" 2>/dev/null | head
```

Record F2 with whatever the evidence supports. If the location cannot be
established from documentation or bundled resources, establish it empirically in
Step 2 by trying candidate locations and seeing which one takes effect.

- [ ] **Step 2: Register a trivial hook and prove it ran**

Write a hook that is unmistakable when it fires — it appends to a file whose
existence and content are the evidence:

```bash
PROBE_OUT="$PWD/docs/research/codex-client/evidence"
mkdir -p "$PROBE_OUT/seed-f3"
cat > "$PROBE_OUT/seed-f3/marker-hook.sh" <<'HOOK'
#!/usr/bin/env bash
# Fires and records that it fired. Reads the hook payload from stdin so the
# recorded file also shows what Codex actually passes.
payload="$(cat)"
printf 'HOOK-FIRED %s\n%s\n' "${1:-no-arg}" "$payload" >> "${KINGLET_HOOK_LOG:?}"
exit 0
HOOK
chmod +x "$PROBE_OUT/seed-f3/marker-hook.sh"
```

Then write the candidate hook configuration into the seed directory, run a probe
that forces a tool call, and check the log:

```bash
printf 'Run the shell command: echo hello\n' > "$PROBE_OUT/prompt-f3.txt"
KINGLET_HOOK_LOG="$PROBE_OUT/f3-hook.log" \
  bash scripts/codex-probe.sh --name f3-hook-fires \
    --prompt "$PROBE_OUT/prompt-f3.txt" \
    --seed "$PROBE_OUT/seed-f3" \
    --sandbox workspace-write
cat "$PROBE_OUT/f3-hook.log" 2>/dev/null || echo "HOOK DID NOT FIRE"
```

**The assertion is that the log exists and holds `HOOK-FIRED`.** Checking that
the config file exists proves nothing — this repository has been burned by
presence-keyed checks repeatedly, and a hook that is configured but never
invoked is exactly the failure this step exists to catch.

Iterate on the configuration filename and shape until the hook fires or until
you have tried every candidate the evidence supports. Record every attempt,
including the ones that did not fire — a list of shapes that do *not* work is
part of F2's value.

- [ ] **Step 3: Establish which events actually fire**

With a hook that fires, register the same marker script on each candidate event
name in turn and record which ones Codex accepts and which ones it rejects or
silently ignores. An event that is accepted by the config parser but never
invoked is a distinct outcome from one that is rejected, and F3 must separate
them.

- [ ] **Step 4: Establish the block protocol**

Make the marker hook refuse instead of allowing:

```bash
cat > "$PROBE_OUT/seed-f4/block-hook.sh" <<'HOOK'
#!/usr/bin/env bash
payload="$(cat)"
printf 'BLOCK-HOOK-FIRED\n%s\n' "$payload" >> "${KINGLET_HOOK_LOG:?}"
printf '{"decision":"block","reason":"kinglet probe: this call was refused on purpose"}\n'
exit 0
HOOK
```

Run a probe that attempts the blocked call and read the event stream:

```bash
python3 -c "
import json
for line in open('docs/research/codex-client/evidence/f4-block.jsonl'):
    line = line.strip()
    if not line: continue
    d = json.loads(line)
    print(d.get('type'), json.dumps(d)[:300])
"
```

Record three things separately, because they can differ: whether the tool call
was actually prevented; whether the model was told why; and the exact shape the
hook must emit to achieve it. Kinglet's 12 hooks emit `decision: block` with a
non-empty `reason` — F4's value is whether that exact shape works unchanged, or
needs translation, and if so what the translation is.

- [ ] **Step 5: Establish whether hook registration needs a human**

`--dangerously-bypass-hook-trust` exists on `codex exec`, which implies a trust
gate. Determine what happens **without** the flag on a freshly seeded home:
does the hook run, is it refused, or is a prompt shown? Then determine what a
non-interactive install would have to do to register a hook legitimately.

Record F5 as one of: no trust step required; a trust step that a non-interactive
installer can satisfy (and exactly how); or a trust step that requires a human
(and exactly what the human does). **`--dangerously-bypass-hook-trust` is a
measurement tool and is not an acceptable shipping answer** — a toolkit that
tells its users to disable hook trust is worse than one that ships no hooks.

- [ ] **Step 6: Write F2–F5 into `codex-facts.md`**

Append four sections in the same shape as F1: a verdict, the exact command, the
verbatim observation, and what it means for the wave. Where a candidate did not
work, record it — the shapes that failed are part of the finding.

- [ ] **Step 7: Update the provenance note**

The `docs/research/codex-client/codex-facts.md` row's note already names F1–F5;
confirm it still describes the file's contents and extend it if the measurement
produced something the note does not cover.

- [ ] **Step 8: Run both gates and commit**

```bash
bash tests/run-tests.sh 2>&1 | tail -6
bash scripts/check-provenance.sh | tail -1
git add docs/research/codex-client/codex-facts.md provenance.tsv
git commit -m "measure(codex): F2-F5 — hook config location, events, block protocol, trust

Every claim keyed on execution: a hook counts as working when a marker file
proves it fired, not when its configuration file exists."
```

---

## Task 4: Kinglet's 12 hooks under Codex

> **RE-PLANNED AFTER TASK 2 — this task did not shrink. It got sharper, and it is now the wave's
> centre of gravity.**
>
> Task 2 already answered the question this task was going to ask first, and the answer is worse than
> "they do not register". **All 12 hooks register. The matchers fire. Eight of the nine tool-event
> hooks then do nothing.**
>
> The cause is one field. **Codex's file tool is `apply_patch`, and `tool_input` carries exactly one
> key — `command`, a patch envelope** (`*** Begin Patch…`), for creating a file and for editing one
> alike. There is no `file_path`, `new_string`, `old_string` or `content`. Measured control, same
> hook, same edit, same file: `block-scene-edit.sh` exits **2** on a Claude-shaped payload and **0**
> on the real Codex payload. Only `bash-gate.sh` survives, because it happens to read
> `.tool_input.command`. **No Kinglet hook reads `tool_name`**, so nothing is wrong at the matcher
> layer — the break is entirely in what the hook bodies reach for.
>
> **Do not re-measure the inertness.** It is measured, with a per-hook paired control and a criterion
> that refuses to classify against a dead control. Start from it.
>
> **This task's two risks, both open:**
>
> 1. **Rewriting the hook bodies against the `apply_patch` envelope.** Eight hooks currently enforce
>    nothing. Whatever you write must keep working under Claude Code — `.claude/hooks/*.sh` is a
>    shipped surface with 122 assertions in `tests/test-hook-behaviour.sh` behind it — so a payload
>    shim is likelier to be right than an edit to the twelve.
> 2. **The block protocol**, if Task 3 has not closed it by the time you start.
>
> **A third thing, already measured, that must not be lost:** every one of the 12 entries carries a
> `timeout` in **milliseconds**, and Codex reads that field as **seconds**. Derived from
> `.claude/settings.json`:
>
> | value | hooks | becomes |
> |---|---|---|
> | 3000 | 6 | 50 minutes |
> | 5000 | 5 | 83 minutes |
> | 2000 | 1 | 33 minutes |
>
> A hung hook that should have been killed in three seconds holds the turn for fifty minutes. This
> ships in the same file the import writes, so it is this task's to fix or this task's to name.

**Files:**
- Create: `docs/research/codex-client/findings.md`
- Modify: `provenance.tsv`

**Interfaces:**
- Consumes: F2–F5 from Task 3; `scripts/codex-probe.sh`.
- Produces: `findings.md` with a `## Hooks` section holding a per-hook verdict table. Task 8 ships the hook layer only if this section says it works.

**Context an implementer needs.** Kinglet has 12 hooks in `.claude/hooks/`, plus a shared library `_lib.sh` which is not a hook. All 12 are registered in `.claude/settings.json`. Derive the list rather than trusting this paragraph:

```bash
ls .claude/hooks/*.sh | /usr/bin/grep -v '_lib\.sh$'
python3 -c "
import json, re
s = json.dumps(json.load(open('.claude/settings.json')))
print(sorted(set(re.findall(r'hooks/([a-z-]+)\.sh', s))))
"
```

The hook whose violation is easiest to construct unambiguously is
`block-legacy-input.sh`: Kinglet forbids the legacy Unity input API, so a file
containing `Input.GetKey` is a violation with no judgement call in it.

- [ ] **Step 1: Confirm the hook rejects the violation locally, before involving Codex**

This establishes the hook works at all, so a Codex failure is attributable to
Codex rather than to a malformed payload:

```bash
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/p/Assets/Scripts/X.cs","content":"if (Input.GetKey(KeyCode.W)) {}"}}' \
  | bash .claude/hooks/block-legacy-input.sh; echo "exit=$?"
```
Expected: a non-zero exit or a `decision: block` payload naming the legacy API.
Record the exact behaviour — it is the baseline the Codex run is compared to.

- [ ] **Step 2: Build a Codex seed that registers Kinglet's hooks**

Using F2's measured location and shape and F4's measured block protocol, write a
seed directory that registers the 12 hooks. If F4 measured that Kinglet's
`decision: block` shape needs translation, write the translation as a thin
wrapper script rather than editing the hooks — the hooks are Claude Code's
shipped surface and must keep working there.

- [ ] **Step 3: Run the violation probe**

```bash
PROBE_OUT="$PWD/docs/research/codex-client/evidence"
cat > "$PROBE_OUT/prompt-hooks.txt" <<'EOF'
Create a file at Assets/Scripts/ProbeInput.cs whose contents are exactly:

using UnityEngine;
public class ProbeInput : MonoBehaviour {
    void Update() { if (Input.GetKey(KeyCode.W)) { } }
}

Then tell me whether the file was created.
EOF
bash scripts/codex-probe.sh --name hooks-legacy-input \
  --prompt "$PROBE_OUT/prompt-hooks.txt" \
  --seed "$PROBE_OUT/seed-hooks" \
  --workdir "$PROBE_OUT/workspace" \
  --sandbox workspace-write
```

Create `$PROBE_OUT/workspace` as a disposable directory first — the probe must
not write into the repository.

- [ ] **Step 4: Assert on the outcome, not on the configuration**

Three independent questions, recorded separately:

```bash
# 1. Did the file land? (the hook's actual job)
ls "$PROBE_OUT/workspace/Assets/Scripts/ProbeInput.cs" 2>/dev/null \
  && echo "FILE LANDED — hook did not block" \
  || echo "FILE ABSENT — consistent with a block"

# 2. Did the hook fire at all?
cat "$PROBE_OUT/hooks-fired.log" 2>/dev/null || echo "NO HOOK LOG"

# 3. Did the model learn why?
cat "$PROBE_OUT/hooks-legacy-input.last.txt"
```

A file that is absent because the model chose not to write it is **not** a
block. Distinguish them by reading the event stream for the attempted tool call:

```bash
python3 -c "
import json
for line in open('docs/research/codex-client/evidence/hooks-legacy-input.jsonl'):
    line = line.strip()
    if not line: continue
    d = json.loads(line)
    item = d.get('item') or {}
    if d.get('type') == 'item.completed' and item.get('type') != 'agent_message':
        print(item.get('type'), json.dumps(item)[:400])
"
```

- [ ] **Step 5: Repeat for the other 11 hooks, or record why not**

For each remaining hook, either run an equivalent execution-keyed probe or
record explicitly why it was not probed — a session-lifecycle hook such as
`session-save.sh` may have no Codex counterpart event, and that is a finding.
**Do not mark a hook "works" because a sibling hook worked.**

- [ ] **Step 6: Write the Hooks section**

Create `docs/research/codex-client/findings.md`:

```markdown
# Kinglet's surfaces under Codex CLI — findings

*Measured against `codex-cli 0.145.0`. Codex's own capabilities are in
`codex-facts.md`; this file is about Kinglet's surfaces running on top of them.*

## Hooks

Kinglet ships 12 hooks (`.claude/hooks/*.sh` less the shared `_lib.sh`), all 12
registered in `.claude/settings.json`.

| Hook | Fires on Codex | Blocks | Model told why | Evidence |
|---|---|---|---|---|
| `block-legacy-input` | <yes/no> | <yes/no> | <yes/no> | `hooks-legacy-input` |
| … one row per hook, or a row saying it was not probed and why … |

**Verdict:** <hooks port unchanged | hooks port with a named translation |
hooks do not port>

**What this means for the ship:** <…>
```

Fill every angle bracket. If a hook was not probed, its row says so and gives
the reason; an empty cell is a failed task.

- [ ] **Step 7: Add the provenance row**

```
docs/research/codex-client/findings.md	original	-	-	-	original	Kinglet's surfaces measured under codex-cli 0.145.0 - one verdict per surface class keyed on execution, the A/B/C architecture decision with the measurement that chose it, everything excluded named in writing, and the machinery the decision strands
```

- [ ] **Step 8: Run both gates and commit**

```bash
bash tests/run-tests.sh 2>&1 | tail -6
bash scripts/check-provenance.sh | tail -1
git add docs/research/codex-client/findings.md provenance.tsv
git commit -m "measure(codex): Kinglet's 12 hooks under Codex, keyed on execution

The assertion is that a violation did not land and the model was told why —
not that a configuration file exists. A hook that is registered and never
invoked is the failure this probe is built to catch."
```

---

## Task 5: Kinglet's 16 skills under Codex

> **RE-PLANNED AFTER TASK 2 — this task shrank the most.**
>
> **Already settled:** the import writes the skills into `.agents/skills/`, and they load with
> `enabled: true`. Discovery is not in question. **Only invocation behaviour remains** — is a skill
> reached for when it is relevant without being named, which is the only mode in which a skill
> library helps an unprompted session.
>
> **A trap that will cost you a wrong number if you skip it.** `skills/list` totals are **not
> stable**: Task 2's disposable home reported 24, its reviewer's reported **59** — 18 repo, 35 user,
> 6 system — with the 35 fetched over the network into the home from
> `plugins/cache/openai-curated-remote/`. Only the **repo-scope count reproduces**. Quote the
> repo-scope figure, say that it is repo-scope, and never quote a total.
>
> **And one thing to resolve rather than inherit:** the repo scope reports **18** while
> `.claude/skills/` holds **16** (`ls -d .claude/skills/*/ | wc -l` — derive it, do not trust this
> line). Two extra somethings are being counted as repo skills. Find out what they are before you
> report a discovery figure, because a count nobody has reconciled is how Task 2's `84` went into
> three places attached to the wrong noun.
>
> **`skills/list` takes `cwds`, an array, not `cwd`.** With `cwd` it returns a well-formed answer
> about the wrong repository — a result, not an error.

**Files:**
- Modify: `docs/research/codex-client/findings.md` (add `## Skills`)

**Interfaces:**
- Consumes: `scripts/codex-probe.sh`; F1 from Task 2.
- Produces: `findings.md` `## Skills` — discovery verdict, invocation verdict, and whether a second copy of the tree is needed. Task 8 reads all three.

**Context.** Kinglet has 16 skills at `.claude/skills/<name>/SKILL.md`, flat, one
level deep. Codex's own skills live at `~/.codex/skills/<name>/SKILL.md` with the
same `SKILL.md` container shape, and `codex` exposes a `skills` configuration
key. Derive the list:

```bash
ls -d .claude/skills/*/ | wc -l
ls .claude/skills/
```

The spec proposes **no second copy** — Codex reads `.claude/skills/` directly —
with a symlink and then an install-time copy as ordered fallbacks. This task
measures which of the three is actually needed.

- [ ] **Step 1: Measure discovery without any copying**

Seed a home whose configuration points the `skills` key at the repository's
`.claude/skills`, then ask Codex what skills it can see:

```bash
PROBE_OUT="$PWD/docs/research/codex-client/evidence"
printf 'List every skill you have available, one per line, with no commentary.\n' \
  > "$PROBE_OUT/prompt-skills-list.txt"
bash scripts/codex-probe.sh --name skills-discovery \
  --prompt "$PROBE_OUT/prompt-skills-list.txt" \
  --seed "$PROBE_OUT/seed-skills-pointed"
cat "$PROBE_OUT/skills-discovery.last.txt"
```

Count how many of the 16 appear. If the `skills` key does not accept an external
path, record that and move to the symlink fallback, then the copy fallback,
recording each attempt.

- [ ] **Step 2: Cross-check discovery against the app server**

A model's self-report is not evidence of what the harness loaded. If Task 2
established a working app-server handshake, `skills/list` appears in the method
list and is the authoritative answer:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"kinglet-probe","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"skills/list","params":{}}' \
  | timeout 60 codex app-server 2>&1 | tail -5
```

Where the two disagree, the app server wins and the disagreement is itself
recorded — a model that claims a skill it does not have is a finding worth
having.

- [ ] **Step 3: Measure invocation, not just discovery**

Discovery is cheap and nearly worthless on its own: the 2026-08-14 measurement
established that a surface being present is not evidence that it is used. Give
Codex a task whose correct handling requires a specific skill, and read the
event stream for whether the skill was actually loaded:

```bash
printf 'I want to add a save system to this Unity project. What is the first thing you do?\n' \
  > "$PROBE_OUT/prompt-skills-invoke.txt"
bash scripts/codex-probe.sh --name skills-invocation \
  --prompt "$PROBE_OUT/prompt-skills-invoke.txt" \
  --seed "$PROBE_OUT/seed-skills-pointed"
```

Record whether `save-system` (or the process chain's `unity-brainstorming`) was
loaded, and whether the answer reflects Kinglet's rules or generic Unity advice.
**The distinction that matters is whether the skill was invoked without being
named**, because that is the only mode in which a skill library helps an
unprompted session.

- [ ] **Step 4: Write the Skills section**

Append to `findings.md`:

```markdown
## Skills

Kinglet ships 16 skills at `.claude/skills/<name>/SKILL.md`.

| Question | Verdict | Evidence |
|---|---|---|
| Discovered when `skills` points at `.claude/skills` | <yes/no> | `skills-discovery` |
| App-server `skills/list` agrees with the model's self-report | <yes/no/n-a> | Step 2 output |
| Invoked when relevant without being named | <yes/no> | `skills-invocation` |
| Second copy needed | <none / symlink / install-time copy> | <…> |

**Verdict:** <…>
```

- [ ] **Step 5: Run both gates and commit**

```bash
bash tests/run-tests.sh 2>&1 | tail -6
bash scripts/check-provenance.sh | tail -1
git add docs/research/codex-client/findings.md
git commit -m "measure(codex): Kinglet's 16 skills — discovery, invocation, and copies

Discovery alone is nearly worthless: the live-bridge wave established that a
surface being present is not evidence it is used. The load-bearing question is
whether a skill is invoked without being named."
```

---

## Task 6: Rules, `AGENTS.md`, commands and agents

> **RE-PLANNED AFTER TASK 2 — this task split. Two of its four classes are settled mechanically;
> the other two stopped being measurements and became design work the measurement created.**
>
> **Settled — do not re-measure:**
>
> - **`AGENTS.md`** is written by the import. Whether its *content* reaches the model is still worth
>   one sentinel probe, and that is all this half needs.
> - **Agents convert**: 8 files become `.codex/agents/*.toml`. But they carry only `name`,
>   `description` and `developer_instructions`. **`model`, `color` and `tools` are dropped — and
>   `mcp__UnityMCP` appears exactly 0 times across all 8.** Every Unity capability grant is gone. The
>   measurement is done; what it means for a Unity toolkit is this task's judgement to write down.
>
> **Now design work, not measurement:**
>
> - **Rules never cross.** There is no `RULES` item type. Worse, a blind `Claude` → `Codex`
>   substitution rewrites **29 references** to a `.Codex/rules/` that does not exist, and leaves
>   **22** `.claude/` references behind — so the imported tree points at two different non-existent
>   directories. **The number is 29, not 84.** 84 is every `.claude/` → `.Codex/` rewrite across all
>   classes (skills 23, scripts 9, NOTICE 4, and so on); scoping this work off 84 would be scoping it
>   off a superset of four unrelated repairs. Source-side reconciliation, already derived:
>   `85 = 84 + 1`, `30 = 29 + 1`, `22 = 1 + 21` — the 21 live in the rewrite-exempt `.sh` class and
>   were never inside the 85.
> - **7 of 9 commands are silently dropped**, because their bodies contain `$ARGUMENTS` — and `$1`
>   and `$5` in prose trigger it too, so the trigger is broader than the name suggests. They never
>   appear in `detect`, so there is **no failure entry**: the import reports 31 successes and 0
>   failures while dropping them.
>
> Both remaining halves are decisions about what Kinglet should ship, not questions about what Codex
> does. Write them as recommendations with the measurement attached, and let Task 8's ship list act
> on them.

These four surface classes are grouped because they share one question — does a
document reach the model at all — and because commands and agents are the two
classes the spec expects to measure dead. Grouping them keeps the expected-dead
classes from being quietly skipped.

**Files:**
- Modify: `docs/research/codex-client/findings.md` (add `## Rules and AGENTS.md`, `## Commands`, `## Agents`)

**Interfaces:**
- Consumes: `scripts/codex-probe.sh`.
- Produces: three `findings.md` sections. Task 8 ships `AGENTS.md` only if the rules section says a document reaches the model; Task 10 records commands and agents as excluded if they measure dead.

**Context.** Kinglet has 6 rules in `.claude/rules/`, loaded into Claude Code
through `CLAUDE.md`; 9 commands in `.claude/commands/`; 8 agents in
`.claude/agents/`. Codex's `~/.codex/rules/*.rules` is a **different thing** — it
holds `prefix_rule(pattern=[...], decision="allow")` entries, which are
command-approval policy, not model guidance. The name collides; the meaning does
not. Nothing in Kinglet's rule layer maps there.

- [ ] **Step 1: Measure whether a project document reaches the model**

Put a sentinel in a candidate entry document and ask for it back:

```bash
PROBE_OUT="$PWD/docs/research/codex-client/evidence"
mkdir -p "$PROBE_OUT/workspace-doc"
cat > "$PROBE_OUT/workspace-doc/AGENTS.md" <<'EOF'
# Project instructions

The project sentinel is KINGLET-SENTINEL-4417. When asked for the sentinel,
reply with it and nothing else.
EOF
printf 'What is the project sentinel?\n' > "$PROBE_OUT/prompt-agentsmd.txt"
bash scripts/codex-probe.sh --name rules-agentsmd \
  --prompt "$PROBE_OUT/prompt-agentsmd.txt" \
  --workdir "$PROBE_OUT/workspace-doc"
cat "$PROBE_OUT/rules-agentsmd.last.txt"
```

A reply containing `KINGLET-SENTINEL-4417` means the document reached the model.
A reply that says it cannot find one means it did not. This is a clean
execution-keyed test with no judgement in it.

- [ ] **Step 2: Measure whether the rule files themselves reach the model**

Kinglet's rules are separate files that `CLAUDE.md` pulls in. Repeat Step 1 with
the sentinel in `.claude/rules/architecture.md` instead of in the entry
document, and with an `AGENTS.md` that references it the way `CLAUDE.md` does.
Record whether a referenced file is followed or only the entry document is read
— this decides whether `AGENTS.md` can be a pointer or must be self-contained.

- [ ] **Step 3: Measure commands**

Kinglet's 9 commands are files with frontmatter that Claude Code exposes as
`/unity-doctor` and friends. Establish whether Codex has any equivalent:

```bash
codex --help
codex exec --help
ls ~/.codex
find ~/.codex/skills/.system -name 'SKILL.md' | head
```

Then test the strongest candidate empirically. If Codex has no slash-command
surface, the finding is that commands do not cross, and the follow-up question
is whether the 9 commands' *content* has anywhere to go — most of them route to
an agent, and a routing document with nothing to route to is dead weight.

- [ ] **Step 4: Measure agents**

Kinglet's 8 agents are files with a `tools:` allowlist that Claude Code
dispatches through its `Agent` tool. Codex reports `multi_agent` as a stable,
enabled feature, and Codex's own skills carry an `agents/` subdirectory.
Establish whether either accepts Kinglet's agent files, or whether the concept
requires a rewrite:

```bash
codex features list | /usr/bin/grep -i agent
find ~/.codex/skills/.system -path '*/agents/*' -type f | head
cat ~/.codex/skills/.system/review-agent/SKILL.md | head -40
```

Record the shape Codex expects, and whether Kinglet's 8 agents could be
expressed in it — but **do not port them in this task**. This is a measurement.

- [ ] **Step 5: Write the three sections**

Append to `findings.md`:

```markdown
## Rules and AGENTS.md

| Question | Verdict | Evidence |
|---|---|---|
| A project `AGENTS.md` reaches the model | <yes/no> | `rules-agentsmd` |
| A file referenced from the entry document is followed | <yes/no> | Step 2 |
| Kinglet's 6 rules can ship as pointers | <yes/no> | <…> |

Codex's `~/.codex/rules/*.rules` is command-approval policy
(`prefix_rule(pattern=[...], decision="allow")`), not model guidance. The name
collides with `.claude/rules/`; nothing maps.

**Verdict:** <…>

## Commands

Kinglet ships 9 commands in `.claude/commands/`.

**Codex equivalent:** <what, or none>

**Verdict:** <…>

## Agents

Kinglet ships 8 agents in `.claude/agents/` with `tools:` allowlists.

**Codex equivalent:** <what Codex's multi_agent and skill-local agents/ expect>

**Could Kinglet's 8 be expressed in it:** <yes, with what work / no, why>

**Verdict:** <…>
```

- [ ] **Step 6: Run both gates and commit**

```bash
bash tests/run-tests.sh 2>&1 | tail -6
bash scripts/check-provenance.sh | tail -1
git add docs/research/codex-client/findings.md
git commit -m "measure(codex): rules, AGENTS.md, commands and agents

Grouped because they share one question — does a document reach the model —
and because commands and agents are the two classes expected to measure dead.
Grouping keeps an expected-dead class from being quietly skipped."
```

---

## Task 7: Layer B — MCP route behaviour against the live bridge

**THE ONE-IMPLEMENTER RULE BINDS ABSOLUTELY HERE.** The Unity Editor is a single
process holding a single asset database. Two agents driving it over MCP
concurrently corrupt that shared state in ways that surface as a broken scene,
not as a merge conflict — there is no diff to review, only a damaged `.unity`
file discovered later with no record of which call did it. **Before starting,
confirm with the controller that no other agent holds the Editor.**

**Files:**
- Modify: `docs/research/codex-client/findings.md` (add `## MCP routes`)

**Interfaces:**
- Consumes: `scripts/codex-probe.sh`.
- Produces: `findings.md` `## MCP routes`. Task 10 reads it for the architecture decision.

**Context.** The owner's real `~/.codex/config.toml` already carries
`[mcp_servers.unityMCP] url = "http://127.0.0.1:8080/mcp"` and
`[features] rmcp_client = true`, and the bridge answered a plain GET with HTTP
406 on 2026-08-15 — alive, and correctly demanding an `Accept` header. Because
probes run with `--ignore-user-config`, the seed must carry that MCP server
entry itself.

Three things the 2026-08-14 Claude measurement established, which this task
checks for Codex:

1. **Reads are resources (`mcpforunity://…`), writes are tools.** Names and URIs
   are not interchangeable.
2. **The silent-failure shape:** an unknown action returns MCP `isError: false`
   with `"success": false` in the body. A client that only checks `isError`
   reports success on a failed call.
3. **Only the `core` tool group is `default_enabled`;** nine others need
   `manage_tools(action="activate", group=…)`.

- [ ] **Step 1: Confirm the bridge is alive and no one else holds the Editor**

```bash
curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/mcp
```
Expected: `406` — alive, demanding an `Accept` header. Anything else, stop and
report; do not proceed against a bridge you cannot see.

- [ ] **Step 2: Seed a home with the Unity MCP server and confirm Codex connects**

```bash
PROBE_OUT="$PWD/docs/research/codex-client/evidence"
mkdir -p "$PROBE_OUT/seed-mcp"
cat > "$PROBE_OUT/seed-mcp/config.toml" <<'EOF'
[mcp_servers.unityMCP]
url = "http://127.0.0.1:8080/mcp"

[features]
rmcp_client = true
EOF
printf 'List every Unity MCP tool you can call, one per line, no commentary.\n' \
  > "$PROBE_OUT/prompt-mcp-list.txt"
bash scripts/codex-probe.sh --name mcp-connect \
  --prompt "$PROBE_OUT/prompt-mcp-list.txt" --seed "$PROBE_OUT/seed-mcp"
cat "$PROBE_OUT/mcp-connect.last.txt"
```

- [ ] **Step 3: Measure the read path**

Ask for something that is a resource rather than a tool, and read the event
stream for how Codex fetched it:

```bash
printf 'Read the Unity project info and tell me the Unity version and the render pipeline.\n' \
  > "$PROBE_OUT/prompt-mcp-read.txt"
bash scripts/codex-probe.sh --name mcp-read \
  --prompt "$PROBE_OUT/prompt-mcp-read.txt" --seed "$PROBE_OUT/seed-mcp"
python3 -c "
import json
for line in open('docs/research/codex-client/evidence/mcp-read.jsonl'):
    line = line.strip()
    if not line: continue
    d = json.loads(line)
    item = d.get('item') or {}
    if 'mcp' in json.dumps(item).lower():
        print(json.dumps(item)[:500])
"
```

Record whether Codex reached for the resource `mcpforunity://project/info` or
tried a tool call, and whether it succeeded.

- [ ] **Step 4: Measure the silent-failure shape**

Ask for an action name that does not exist, and record what Codex's client
reports:

```bash
printf 'Call the Unity MCP tool manage_editor with action "definitely_not_an_action" and tell me exactly what came back.\n' \
  > "$PROBE_OUT/prompt-mcp-bogus.txt"
bash scripts/codex-probe.sh --name mcp-bogus \
  --prompt "$PROBE_OUT/prompt-mcp-bogus.txt" --seed "$PROBE_OUT/seed-mcp"
```

The question is whether Codex surfaces the `"success": false` body or reports a
success because `isError` was false. This is the single most consequential
difference a client can have, because it decides whether a failed Unity call is
visible to the model.

- [ ] **Step 5: Measure tool-group activation**

Ask for something in a non-`core` group — a profiler read — and record whether
Codex discovers that it must call `manage_tools(action="activate", group=…)`
first, or fails without diagnosing it.

- [ ] **Step 6: Leave the Editor as you found it**

Every probe in this task runs `--sandbox read-only` unless a write is the thing
being measured. If any probe wrote to the project or left a scene dirty, record
it explicitly — a scene changed through MCP and never saved has changed nothing
on disk, and the next agent inherits a disagreement between git and the Editor
that it cannot detect.

- [ ] **Step 7: Write the MCP routes section**

Append to `findings.md`:

```markdown
## MCP routes

Measured against the live CoplayDev unity-mcp bridge on
`http://127.0.0.1:8080/mcp`, Unity project `<name>`, on `<date>`.

| Question | Claude (2026-08-14) | Codex | Evidence |
|---|---|---|---|
| Connects to the bridge | yes | <…> | `mcp-connect` |
| Uses resources for reads | yes | <…> | `mcp-read` |
| Surfaces `isError:false` + `"success":false` as a failure | <…> | <…> | `mcp-bogus` |
| Diagnoses an inactive tool group | <…> | <…> | Step 5 |

**Editor state left behind:** <clean / named dirty scenes>

**Verdict:** <…>
```

- [ ] **Step 8: Run both gates and commit**

```bash
bash tests/run-tests.sh 2>&1 | tail -6
bash scripts/check-provenance.sh | tail -1
git add docs/research/codex-client/findings.md
git commit -m "measure(codex): MCP route behaviour against the live Unity bridge

Layer B, run with the Editor held by nobody else. The consequential question is
whether Codex surfaces the isError:false + success:false shape as a failure —
that decides whether a failed Unity call is visible to the model at all."
```

---

## Task 8: Ship the payload the measurement supports

**Files:**
- Create: `tests/test-codex-surface.sh`
- Create (conditionally, per the measurement): `AGENTS.md`, `.codex/hooks.json`
- Modify: `provenance.tsv`

**Interfaces:**
- Consumes: every verdict in `findings.md` and `codex-facts.md`.
- Produces: the shipped Codex payload and `tests/test-codex-surface.sh`, which guards it. Task 9's installer writes exactly the files this task creates.

**What ships is decided by the measurement, not by this plan.** The spec's
expectation is hooks plus skills plus `AGENTS.md`, and it is written down as an
expectation precisely so that it can be contradicted. Before writing anything,
re-read `findings.md` and write down the ship list. If a surface class measured
dead, it does not ship, and Task 10 records the exclusion.

**If hooks did not port,** the ship is skills plus `AGENTS.md`, success
criterion 1 is recorded as not met with its evidence, and the shipped
`AGENTS.md` must state plainly that Kinglet on Codex is advisory rather than
enforcing. Shipping the skills and letting a reader assume the hooks came with
them is the one outcome this wave must not produce.

- [ ] **Step 1: Write the ship list down before writing any file**

Append to `findings.md` a `## Ship list` section naming each surface class as
`ships` or `excluded`, each with the verdict that decided it. This section is
the brief for the rest of this task.

- [ ] **Step 2: Write the failing guard**

Create `tests/test-codex-surface.sh`. It derives both sides from the tree and
fails on either direction, with a floor so it cannot pass on an empty set:

```bash
#!/usr/bin/env bash
# Guards the shipped Codex payload: every Codex surface has a counterpart, and
# every counterpart has a Codex surface. Both directions, because a one-way
# check passes while half the payload is missing.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# --- the shipped Codex surface, derived ------------------------------------
CODEX_FILES="$(git ls-files 'AGENTS.md' '.codex/*' || true)"
CODEX_COUNT="$(printf '%s\n' "$CODEX_FILES" | /usr/bin/grep -c . || true)"

# --- anti-vacuity floor -----------------------------------------------------
# An identity over two empty sets passes at 0 == 0. The floor is what stops
# this file from going green after someone deletes the payload it guards.
if [ "$CODEX_COUNT" -ge 1 ]; then
  ok "the Codex payload is non-empty ($CODEX_COUNT tracked files)"
else
  bad "no tracked Codex payload found — this guard would pass vacuously"
fi

# --- every shipped Codex file is declared in the ship list ------------------
SHIP_LIST="docs/research/codex-client/findings.md"
[ -f "$SHIP_LIST" ] || bad "findings.md is missing; the ship list is its section"

for f in $CODEX_FILES; do
  if /usr/bin/grep -qF -- "$f" "$SHIP_LIST"; then
    ok "shipped Codex file is named in the ship list: $f"
  else
    bad "shipped Codex file is absent from the ship list: $f"
  fi
done

# --- every hook the Codex config names actually exists ----------------------
if [ -f .codex/hooks.json ]; then
  NAMED="$(python3 -c "
import json, re, sys
print('\n'.join(sorted(set(re.findall(r'hooks/([A-Za-z0-9_-]+)\.sh',
      json.dumps(json.load(open('.codex/hooks.json'))))))))
")"
  NAMED_COUNT="$(printf '%s\n' "$NAMED" | /usr/bin/grep -c . || true)"
  if [ "$NAMED_COUNT" -ge 1 ]; then
    ok "the Codex hook config names $NAMED_COUNT hook(s)"
  else
    bad "the Codex hook config names no hooks — it would guard nothing"
  fi
  for h in $NAMED; do
    if [ -f ".claude/hooks/$h.sh" ]; then
      ok "Codex-registered hook resolves: $h"
    else
      bad "Codex-registered hook does not exist: .claude/hooks/$h.sh"
    fi
  done
fi

printf '\n=== Codex Surface: %d/%d passed, %d failed ===\n' \
  "$PASS" "$((PASS+FAIL))" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 3: Run the guard to verify it fails**

```bash
bash tests/test-codex-surface.sh
```
Expected: FAIL — no Codex payload is tracked yet, so the anti-vacuity floor
fires. That failure is the guard proving it is not vacuous.

- [ ] **Step 4: Write the payload the ship list names**

Write each file the ship list names, using the shapes measured in Tasks 2–7 and
no others. Do not invent a `hooks.json` shape from the spec's inferred list — F2
measured the real one, and if F2 refuted the whole mechanism, `.codex/hooks.json`
is not written at all.

- [ ] **Step 5: Run the guard to verify it passes**

```bash
bash tests/test-codex-surface.sh
```
Expected: PASS on every assertion.

- [ ] **Step 6: Prove the guard still fails when the payload is wrong**

A guard that has only ever been seen green is not known to work. Break it
deliberately and confirm it goes red, then restore:

```bash
git stash push -- AGENTS.md 2>/dev/null || true
bash tests/test-codex-surface.sh; echo "expected non-zero: $?"
git stash pop 2>/dev/null || true
bash tests/test-codex-surface.sh >/dev/null && echo "restored green"
```

- [ ] **Step 7: Add provenance rows**

One row per newly tracked file. `tests/test-codex-surface.sh` is
`origin=original`. Any file whose shape was taken from Superpowers — for
instance a polyglot hook wrapper modelled on `hooks/run-hook.cmd` — is
`origin=superpowers` with the upstream version `6.2.0` and the upstream path
recorded, **not** `origin=original`.

- [ ] **Step 8: Run both gates and commit**

```bash
bash tests/run-tests.sh 2>&1 | tail -6
bash tests/run-tests.sh 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g' | /usr/bin/grep -c '^--- test-.*\.sh ---'
ls tests/test-*.sh | wc -l
bash scripts/check-provenance.sh | tail -1
git add -A
git commit -m "feat(codex): ship the payload the measurement supports

The ship list is written into findings.md before any file is created, and the
guard checks both directions with an anti-vacuity floor — a one-way check
passes while half the payload is missing, and an identity over two empty sets
passes at 0 == 0."
```

---

## Task 9: The installer writes and removes the Codex layout

**Files:**
- Modify: `install.sh`
- Modify: `uninstall.sh`
- Modify: `tests/test-codex-surface.sh` (extend with installer assertions)

**Interfaces:**
- Consumes: the payload files Task 8 created.
- Produces: `install.sh --client codex` (and `--client claude`, the existing behaviour, named explicitly), plus receipt entries so `uninstall.sh` removes exactly what was written.

**Context.** `install.sh` is 2197 lines and already owns the receipt, the
project detection and the generated `CLAUDE.md` block. It gates on `Assets/` and
`ProjectSettings/` being present, so it is exercised against the fixture:

```bash
bash tests/fixtures/mkproject.sh /tmp/p
bash install.sh --project-dir /tmp/p --dry-run
```

The receipt is what makes uninstall correct. A file written without a receipt
entry is a file `uninstall.sh` will refuse to touch forever — that exact defect
shipped once already and is recorded in the 2026-08-12 spec.

- [ ] **Step 1: Write the failing installer assertions**

Append to `tests/test-codex-surface.sh`, before its summary block:

```bash
# --- the installer places and disowns the Codex payload ---------------------
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/kinglet-codex-install.XXXXXX")"
bash tests/fixtures/mkproject.sh "$FIXTURE" >/dev/null 2>&1

if bash install.sh --project-dir "$FIXTURE" --client codex >/dev/null 2>&1; then
  ok "install.sh --client codex succeeds against a fixture project"
else
  bad "install.sh --client codex failed against a fixture project"
fi

for f in $CODEX_FILES; do
  if [ -e "$FIXTURE/$f" ]; then
    ok "installer placed $f"
  else
    bad "installer did not place $f"
  fi
done

RECEIPT="$(find "$FIXTURE" -name 'manifest.json' -path '*kinglet*' | head -1)"
if [ -n "$RECEIPT" ]; then
  ok "the install wrote a receipt"
  for f in $CODEX_FILES; do
    if /usr/bin/grep -qF -- "$f" "$RECEIPT"; then
      ok "receipt covers $f"
    else
      bad "receipt does not cover $f — uninstall will refuse to remove it"
    fi
  done
else
  bad "no receipt found after install"
fi

if bash uninstall.sh --project-dir "$FIXTURE" --yes >/dev/null 2>&1; then
  for f in $CODEX_FILES; do
    if [ -e "$FIXTURE/$f" ]; then
      bad "uninstall left $f behind"
    else
      ok "uninstall removed $f"
    fi
  done
else
  bad "uninstall.sh failed after a codex install"
fi
rm -rf "$FIXTURE"
```

Adjust `--yes` and `--project-dir` to `uninstall.sh`'s real flags; read
`uninstall.sh`'s argument parser first rather than assuming them.

- [ ] **Step 2: Run to verify it fails**

```bash
bash tests/test-codex-surface.sh
```
Expected: FAIL — `install.sh` does not accept `--client`.

- [ ] **Step 3: Add `--client` to the installer**

Read `install.sh`'s existing argument parser and payload-writing section first.
Add `--client claude|codex` defaulting to `claude`, so existing invocations are
unchanged. Validate the value before `shift 2`. Write the Codex payload through
the same receipt-recording path the Claude payload uses — do not add a second
way to write files.

- [ ] **Step 4: Run to verify it passes**

```bash
bash tests/test-codex-surface.sh
bash install.sh --project-dir /tmp/p --client codex --dry-run
```
Expected: PASS, and the dry run lists the Codex files without writing them.

- [ ] **Step 5: Verify the dry run really is dry**

```bash
rm -rf /tmp/p-dry && bash tests/fixtures/mkproject.sh /tmp/p-dry >/dev/null
bash install.sh --project-dir /tmp/p-dry --client codex --dry-run >/dev/null
git -C /tmp/p-dry status --porcelain 2>/dev/null | head
ls /tmp/p-dry/AGENTS.md 2>/dev/null && echo "DRY RUN WROTE A FILE — bug" || echo "dry run wrote nothing"
```

- [ ] **Step 6: Run both gates and commit**

```bash
bash tests/run-tests.sh 2>&1 | tail -6
bash scripts/check-provenance.sh | tail -1
git add install.sh uninstall.sh tests/test-codex-surface.sh
git commit -m "feat(install): --client codex writes and disowns the Codex layout

The Codex payload goes through the same receipt-recording path the Claude
payload uses. A file written without a receipt entry is one uninstall refuses
to touch forever — that defect shipped once already."
```

---

## Task 10: Findings synthesis, the architecture decision, and the debt

**Files:**
- Modify: `docs/research/codex-client/findings.md`
- Modify: `README.md`
- Modify: `docs/ARCHITECTURE.md`

**Interfaces:**
- Consumes: every section of `findings.md` and `codex-facts.md`.
- Produces: the A/B/C decision, the exclusion list, the stranded-machinery debt paragraph, and the user-facing statement of what Kinglet on Codex is and is not.

- [ ] **Step 1: Write the architecture decision**

Append a `## Architecture decision` section to `findings.md` choosing A, B or C
with the measurement that chose it. The three, restated so the section is
readable without the spec:

- **A — the Superpowers shape:** one shared content tree, a thin per-client
  manifest, `AGENTS.md` as an entry document, a per-client hook manifest.
  Evidence: it ships to seven clients today.
- **B — the 2026-07-23 platform design:** fill `src/catalog/`, write renderers in
  `tools/kinglet_build/`, generate a product per client.
- **C — installer-only:** leave the repository shape alone; `install.sh`
  translates.

State which measurement decided it. "A, because it is what Superpowers does" is
not a decision — the measurement is the reason.

- [ ] **Step 2: Write the exclusion list**

Every surface class that measured dead gets a named entry: what it is, the
measurement that killed it, and whether it could be revived by work or is
structurally absent on Codex. A class dropped without an entry is
indistinguishable from a class forgotten.

- [ ] **Step 3: Write the debt paragraph**

If the decision is A or C, then `src/catalog/` (3 files),
`tools/kinglet_build/` (10 Python modules, one of which is the renderer
package's `__init__.py`), `adapters/claude/profile.json`,
`adapters/codex/profile.json` and `migration/baseline-inventory.json` are
stranded. Name them, with the measurement that stranded them, and state that
this wave deliberately did not retire them. Re-derive the counts rather than
copying them from this plan:

```bash
ls src/catalog | wc -l
find tools/kinglet_build -name '*.py' | wc -l
ls adapters/*/profile.json | wc -l
```

- [ ] **Step 4: State the second client in the user-facing documents**

`README.md` and `docs/ARCHITECTURE.md` are what a reader uses to decide whether
to install. Add what Kinglet on Codex actually is, including its measured
limits. If hooks did not port, say **"advisory, not enforcing, on Codex"** in
plain words — a reader who installs expecting guardrails and gets none has been
misled by an omission.

`tests/test-derived-counts.sh` guards quoted surface counts in `README.md`,
`docs/ARCHITECTURE.md` and `docs/SKILL-CATALOG.md` against the tree. Any count
you add or change must agree with the derivation:

```bash
ls .claude/agents/*.md | wc -l
ls .claude/commands/*.md | wc -l
ls -d .claude/skills/*/ | wc -l
```

- [ ] **Step 5a: Re-derive `docs/ANTI-VACUITY.md`'s bash-4 census, and put it under a guard**

Added during the run, by the Task 1 completion sweep. That document carries the five-source census
of `tests/test-bash32-compat.sh`'s bash-4 sweep as a live figure with a date stamp — search for
`SHIPPED:scripts` — and states the sum in prose. Task 1 added one file to `scripts/` and one to
`tests/`, and Tasks 8 and 9 add at least one more test file each, so the figure recorded before this
step is wrong by construction. Derive and correct it:

```bash
printf '%s + %s + %s + 1 + 1 = %s\n' \
  "$(ls .claude/hooks/*.sh | wc -l)" "$(ls scripts/*.sh | wc -l)" "$(ls tests/*.sh | wc -l)" \
  "$(( $(ls .claude/hooks/*.sh | wc -l) + $(ls scripts/*.sh | wc -l) + $(ls tests/*.sh | wc -l) + 2 ))"
```

Note that `tests/*.sh` is **not** `tests/test-*.sh` — it includes `run-tests.sh`, which is why the
tests figure is one higher than the suite's file count. Reading the wrong one is how this number was
mis-stated before.

**Correcting the number is not the deliverable — the guard is.** This figure has now gone stale
three recorded times, twice inside a document whose entire subject is numbers that rot. Extend
`tests/test-derived-counts.sh` to derive this census from the tree and fail when
`docs/ANTI-VACUITY.md` disagrees, the same shape its existing surface-pool block already uses for
`README.md` and `docs/ARCHITECTURE.md`. Prove the guard by mutation: change the document's figure by
one, confirm red, restore, confirm green.

Leave the pinned historical measurements alone. The `39 test files` figure under
**## The measured class** is a past measurement whose own table sums to 39 (11 green + 1 collapsed +
27 red), and the `15 hooks and 4 scripts were cut` line is a record of a past wave. Both are correct
as history. If you touch them at all, it is only to say in the text that they are pinned — a live
figure and a historical one that look identical is the ambiguity that produced this step.

- [ ] **Step 5: Re-derive every number in both research documents**

Numbers written during a measurement go stale as later tasks change the tree.
Flatten each file before reading, because a count and its noun sit either side
of a line wrap often enough that a line-oriented reader skips them, and search
on the **noun**, never on the number:

```bash
for f in docs/research/codex-client/findings.md docs/research/codex-client/codex-facts.md; do
  echo "=== $f ==="
  tr '\n' ' ' < "$f" | tr -s ' ' | /usr/bin/grep -oE '[^ ]+ [^ ]+ [0-9]+ [^ ]+ [^ ]+' | sort -u
  tr '\n' ' ' < "$f" | tr -s ' ' | /usr/bin/grep -oiE '[^ ]+ (one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve) [^ ]+' | sort -u
done
```

Re-derive each against the tree. The spelled-out sweep is not optional: a digit
pattern reaches none of "two", "a dozen", "ten".

- [ ] **Step 6: Confirm no angle-bracket placeholder survives**

```bash
/usr/bin/grep -rn '<[a-z…/ ]*>' docs/research/codex-client/*.md || echo "no placeholders"
/usr/bin/grep -rniE 'TBD|TODO|FIXME|fill in' docs/research/codex-client/*.md || echo "no markers"
```
Both must report clean. A findings document with an unfilled verdict is a
failed wave, not a partial one.

- [ ] **Step 7: Run both gates and commit**

```bash
bash tests/run-tests.sh 2>&1 | tail -8
bash tests/run-tests.sh 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g' | /usr/bin/grep -c '^--- test-.*\.sh ---'
ls tests/test-*.sh | wc -l
bash scripts/check-provenance.sh | tail -1
git add -A
git commit -m "docs(codex): the architecture decision, the exclusions, and the debt

The decision names the measurement that chose it, every dead surface class is
named with what killed it, and the machinery the decision strands is recorded
as debt rather than quietly ignored."
```

---

## Task 11: Close the probe harness's residual guard gaps

Added during the run. The Task 1 fix-round re-review measured three places where
`scripts/codex-probe.sh` behaves correctly and **nothing would notice if it stopped**. None was worth
extending that fix loop; all three are worth an assertion before the wave ends, because each is a
silent regression waiting for an unrelated edit.

**Files:**
- Modify: `tests/test-codex-probe.sh`

**Interfaces:**
- Consumes: `scripts/codex-probe.sh` as Task 1 shipped it. Changes no behaviour — assertions only.
- Produces: nothing later tasks call.

Run this **after Task 9**, so the harness has stopped changing.

- [ ] **Step 1: Guard the sweep's liveness check**

Measured: deleting `if kill -0 "$stale_pid" …; then continue; fi` from the reclamation loop leaves the
guard at 35/35 green, and the consequence is real rather than theoretical — a concurrent probe's
`CODEX_HOME` and its copied credential are deleted out from under it while it is still running,
reproduced deterministically 2/2 each way. The suite itself runs a probe into the default `--out`,
which is the same directory a live Task 3–7 probe uses.

Write an assertion that fails when the liveness check is gone: start a long-running probe, run a
second probe into the same `--out`, and assert the first probe's home and credential survive. Prove
it by mutation — delete the `kill -0` line, confirm red, restore, confirm green.

- [ ] **Step 2: Make deleting the signal arms detectable**

Measured: removing all three of `trap 'on_signal …' HUP`, `INT`, `TERM` leaves the guard at 35/35
green. The arms are correct — isolated (EXIT trap removed, arms kept) they clean up on all three
signals and exit with the right `128+signo` — but on bash 5.2.21 the EXIT trap alone already covers
those signals, so a *behavioural* assertion would be green with or without them. That is why Task 1
deliberately left them unasserted, and that reasoning was right.

The gap is that they now read as covered while being deletable. Add a **structural** assertion that
the three arms exist and route to `cleanup`, and **label it in the file as a presence check standing
in for a behaviour this host cannot observe** — the label is the point, because an unlabelled
presence check is how a structural assertion gets mistaken for a behavioural one. Prove it by
deleting one arm and confirming red.

- [ ] **Step 3: Widen the disposable-home entry check past the top level**

Measured: `HOME_ENTRIES` is a top-level `ls -A`, so a leak nested inside a directory the seed already
creates is invisible — a seed carrying `skills/` plus the owner's skills leaked into it produces the
expected entry list and the guard stays green. Contrived compared to the wholesale `cp -R` widening
the guard does catch, but **Task 5 measures skill discovery**, and a leaked `~/.codex/skills/` is
precisely the contamination that would corrupt it with a green suite.

Compare the home's full recursive contents against the seed's, not just the top level. Prove it by
leaking one nested file and confirming red.

- [ ] **Step 4: Run both gates and commit**

```bash
bash tests/test-codex-probe.sh
bash tests/run-tests.sh 2>&1 | tail -6
bash scripts/check-provenance.sh | tail -1
git add tests/test-codex-probe.sh
git commit -m "test(codex): assert the three harness behaviours nothing would have missed

Each was measured green after deleting the thing it protects. The signal-arm
assertion is structural and says so in the file: on this host the EXIT trap
already covers HUP/INT/TERM, so a behavioural assertion would pass with the
arms removed."
```

---

## Task 12: The installed project does not know it is on Codex

**Added 2026-08-16**, after the whole-branch review. It owns the review's user-facing remainder — the
findings its fix loop deliberately did not take, because they are documentation correctness rather
than defects in the branch's own new code.

**The finding, in the review's own words:** *"Can a reader tell what Kinglet on Codex enforces and
what it does not? From `README.md`, yes, clearly. From inside the installed project, no."* The wave
measured Codex honestly and wrote the measurement into `README.md` and `docs/ARCHITECTURE.md`. It did
not go back to the shipped surfaces those measurements falsified. A Codex session opens its
orientation skill, is told the rules load automatically, and therefore does not read them.

**What a session reads and is misled by**

- `.claude/skills/using-kinglet/SKILL.md` — *"Five rules in `.claude/rules/` load automatically and
  bind."* Symlinked **verbatim** into `.agents/skills/`, so it never gets the converter's caveat
  banner. Measured: `.claude/rules/` opened **0 times in 24 runs** under Codex without a pointer. The
  same file routes to 8 `/unity-*` commands Codex has no surface for.
- Five unqualified copies of *"legacy `Input.*` is blocked by a hook"* — `.claude/rules/unity-specifics.md`
  (two sites), `.claude/rules/pc-console.md`, `.claude/skills/input-system/SKILL.md`, `README.md`.
  `scripts/generate-claude-md.sh` **already forks exactly this bullet by client**, with the comment
  *"Claiming enforcement that may not be installed is exactly the failure this wave exists to avoid."*
  The fork was applied to one generated bullet and none of the five shipped copies.
- Zero `codex` mentions across all 8 agents, 8 of 9 commands, all 16 skills, all 6 rules.
  **Do not carpet-bomb this** — decide the criterion (which surfaces make a claim that is false or
  unreachable under Codex), apply it, and write the criterion down. Two that matter concretely:
  `docs/AGENT-GUIDE.md` teaches `tools:` as an access control with no destination under Codex, and
  `MCP-SETUP.md` lists *"Claude Code (this CLI)"* as a prerequisite — and is where `install.sh`'s
  Next step 1 sends every Codex user.

**What a user reads and is misled by**

- `install.sh`'s closing summary, client-unconditional: prints `Agents 8 / Commands 9 / Skills 16` to
  a client whose agents README says are excluded entirely and whose command surface ARCHITECTURE says
  does not exist. The run created 25 entries in `.agents/skills/` (16 links + 9 converted).
- `install.sh`'s Next steps, also unconditional: step 1 → `MCP-SETUP.md`; step 2 → fill `CLAUDE.md`'s
  `FILL:` markers, the file Codex never loads, while the generated `AGENTS.md` carries its own
  unfilled markers nothing mentions; step 3 → *"Run `claude` … try `/unity-init`"*, wrong binary and
  two commands with no Codex surface. **Also missing:** nothing tells a Codex user to run `codex` once
  to grant project trust — the layer-6 fix — unless trust happens to fail.
- `docs/GETTING-STARTED.md` never introduces the second client. `:16` says *"Claude Code is the only
  hard requirement."* `## Installation` shows no `--client codex`. § *Hooks Not Firing* has six
  Claude-shaped bullets and none of the six ways this branch measured hooks silently failing under
  Codex — which is that section's literal title. § *Quick Diagnostic* says *"Its four checks are…"*
  against five `## Check` headings.
- `.claude/commands/unity-doctor.md` § Check 3 — *"and only these"* is a closed-world claim the branch
  falsified six lines below its own paragraph.

**Two categoricals the branch's own committed schema refutes — scope them, do not delete them**

- *"there is no way to tell from inside the session"* whether hooks are trusted. `HookTrustStatus` is
  `["managed","untrusted","trusted","modified"]` and `trustStatus` is a **required** field of
  `HookMetadata` in the `hooks/list` response, which takes `cwds` and reads no home. The categorical
  **holds for layer 6** and is **false for layers 3–5**. `unity-doctor.md` currently forbids reporting
  trust state at all, which forbids the one route that answers without touching the user's home — and
  `install.sh` already calls `hooks/list`.
- *"a read-only reviewer cannot be expressed, only requested."* The narrow claim (no per-agent tool
  allowlist) is true; the sentences built on it are over-broad. `SandboxMode` is
  `["read-only","workspace-write","danger-full-access"]`, `permissionProfile/list` exists, and
  `HookEventName` carries `subagentStart`/`subagentStop`.

**One behaviour defect, here because this task already opens `install.sh`**

Installing `--client claude` over an existing `--client codex` install takes the receipt's symlink
rows **16 → 0** while `.agents/` stays on disk — sixteen files with no reader that owns them, and a
receipt-driven `uninstall.sh` that can no longer remove them. Pre-existing branch behaviour.
**Its guard is an upgrade fixture, not an assertion:** install one client, install the other over it,
then assert the resulting tree is internally consistent — every file owned by a row, every row present
on disk. Silently keeping the files and dropping the rows is the one answer that is wrong.

**Must not:** measure Codex behaviour that is not already measured (if closing an item needs a live
Unity bridge it belongs to Task 7); weaken an honest sentence into a vague one; add a `codex` mention
to a surface that makes no client-specific claim.

---

## Task 13: The record documents — residuals, floors, criteria, and the guard's edge

**Added 2026-08-16.** The whole-branch review's internal-record remainder, plus everything its fix
loop closed on rather than carrying into a fourth round.

**Disclosed residuals that undercount.** `docs/research/codex-client/README.md` says *"nothing in
`tests/` reads these two files"* — `tests/test-codex-surface.sh` reads `findings.md` **as its
authority** and reds on its absence; `codex-facts.md` is read by `tests/test-codex-shim.sh`. Falsified
twice independently. `tests/test-shipped-citations.sh`'s residual says *"NINE in `.claude/scripts/`"*
against a derived fifteen, total at least twenty-one; its neighbouring site-counts were never
re-derived while `scripts/` grew by three.

**The anti-vacuity floor set.** `docs/ANTI-VACUITY.md` declares `tests/*.sh` and `scripts/*.sh` in
scope and has zero `codex` rows, while the branch added three test files carrying six qualifying
floors. The document's *"zero rows means swept and empty"* rule cannot distinguish swept from never
swept, because that segment has rows. Derive the membership from the document's own criterion.

**One stale ordinal at three sites.** The wave ended with **six** silent-failure layers;
`findings.md`, `install.sh` and `README.md` still say five (README's number is right and its **scope
word** is wrong). `codex-facts.md` already annotates the identical shape at a fourth site — the class
was identified and the sweep ran against one site of three. Derive the class yourself.

**The deliverable: the live-vs-pinned criterion for `docs/research/codex-client/*`.** Fix round 1
named this as the honest blocker on guarding that directory — its figures are *mostly* per-run
measurements against gitignored transcripts that must **not** be re-derived, and *mostly* is what let a
second unguarded copy of `install.sh`'s `982` hide there. Writing the criterion is the work; the guard
rows follow from it. If the criterion selects nothing guardable, write it down anyway with what it
excluded and why.

**What the fix loop handed over rather than opening a round 4.** Its measured pathology is the reason:
each round discharged its findings and produced a smaller, same-shaped crop of false statements inside
the prose written to close them — four, then two, then five.

- **`DCT_DECLARED` compares files, not rows** (Important, and a mechanism rather than a sentence).
  Deleting one row from any multi-row file — `findings.md` ×4, `ANTI-VACUITY` ×3,
  `test-shipped-citations` ×2 — leaves the suite green, **including the row that added it**. The
  block's prose claims otherwise and the honest paragraph it replaced was true for those nine.
- **The surface-pool block excludes `CLAUDE.md` on a false ground** — *"a file that quotes no number
  cannot quote a stale one"*, while `CLAUDE.md` quotes the agent count twice in present tense. Four
  more live unguarded sites travel with it (`docs/AGENT-GUIDE.md`, `CONTRIBUTING.md`,
  `tests/test-studio-doctor.sh`, five `Kinglet ships N …` sentences in `findings.md`). All correct
  today — a guard gap, not a stale figure, and the **ground** matters more than the sites.
- **Word-numeral forms have never been swept in any round.** A word-numeral arm produced two class
  members no digit sweep across three rounds could see, and a positive control against known members
  killed one sweep pass outright by returning zero. Take both instruments.
- `scripts/studio-doctor.sh` says *"called from FOUR sites"* and names five, in the paragraph whose
  point is enumerating rather than characterising; a four-reader table has an orphaned row; a `sed`
  comment's *"each of those paths also appears in bare form"* is false for 2 of 9; `DCT_HOOKS_SH` is
  derived and floor-checked and read by no row.
- `findings.md` says the importer *"reports 31 successes"* at three sites with the importer path as
  the subject — the same subject/figure mismatch already corrected in `README.md`.
- `MERGE-NOTES.md` Part 2's `## What shipped` table reads `28 / 36 / 39 / 25` against a live
  `8 / 9 / 16 / 12`, under the heading *"Counts verified against disk"*. The file's
  *"records of what a wave produced on a date"* disclaimer exists but is scoped to a different
  section.
- **Ledger items 8 and 14** — close them or give each a ruling that names a task. A ruling naming a
  role is not a deferral.

**Two items handed over from Task 12's fix loop, both guard defects rather than prose.**
`install.sh`'s comment cites *"the trap `CLAUDE.md` already records"* — a flattened probe over
`CLAUDE.md` returns 0 for every phrasing; the lesson is right and filed at `install.sh:1475` and in
`provenance.tsv`, so only the address is wrong. And `tests/test-install-upgrade-client.sh` needs **one
negative-direction assertion**: a shadow `codex_layer_path() { return 0; }` leaves it at 24/24 green,
because arms 1–4 all assert that Codex paths are *included* and none asserts that a non-Codex path is
*excluded*. The full suite reds on it elsewhere, so nothing ships silently — but a guard that only
ever tests one direction of a predicate is half a guard.

**Every guard added or repaired here must be proved by mutation in both directions**, with the mutant
confirmed applied before measuring and `MUTANT DID NOT APPLY` emitted explicitly when it is not.

---

## Task 14: `AGENTS.md` has no marked-region merge, and something now depends on it

**Added 2026-08-16**, from Task 12's fix round. Task 12 raised it, closed the half it could close, and
ruled the rest a task rather than rushing a new write path into a user-owned file inside a fix round.
That ruling is correct and this task is the other half.

**The defect.** `install.sh` generates `AGENTS.md` with `FILL:` markers and its own Next steps tell a
Codex user to fill them. `CLAUDE.md` has marked-region merge machinery — five branches plus a
marker-state detector, each with a state arm in `tests/test-install-ownership.sh` — and `AGENTS.md`
has none. So the moment the user does what the installer instructs, the file is **permanently
frozen**: no reinstall, upgrade or fix can ever update it again, silently.

**Why it is not merely symmetry.** Task 9 argued the absence deliberately — *"no `separate` sibling
and no in-place refresh arm, because there is no established convention of hand-written prose in an
`AGENTS.md` this installer wrote."* That reasoning was sound when `AGENTS.md` carried only generated
content. Task 12 changed the premise by making a correctness argument depend on the file: the J2-20
exclusion holds because the always-injected `AGENTS.md` carries the `/name` translation once. So
**reversing Task 9's decision needs a reason, not just a mechanism** — the reason is that the file is
now load-bearing for a rule, and a frozen copy of a rule is a rule that stops being true.

**What Task 12 already closed, and must not be redone.** The exclusion no longer rests on one copy:
`using-kinglet`'s intro block states the `/name` rule inline as a second home.

**This paragraph said that second home was "a symlinked skill no install branch can freeze" until
2026-08-17, and that was false** — measured by Task 12's own second re-review: appending a line to
`.claude/skills/using-kinglet/SKILL.md` makes every later install keep the user's copy, receipt row
`user-modified`, shipped text never landing. Both files are freezable. **What differs is who
initiates it and how much it takes down** — nothing in this toolkit ever tells a user to edit a skill,
whereas the installer's own Codex Next step 2 tells them to edit `AGENTS.md`; and a frozen skill costs
one file where a frozen entry document costs the whole generated block, Project Facts refreshes
included. That asymmetry is the argument for two homes, and it is the residual risk this task is
being asked to remove — not a safety property it can assume.

Do not re-derive that from scratch: `CLAUDE.md`'s criterion carries the load path, the freeze
mechanism, and the standing instruction that a surface whose only correction lives in `AGENTS.md` must
get a second home **knowing that copy is freezable too**. Read it there rather than here, because this
brief has already been wrong about it once.

**One correction to carry with you, because `CLAUDE.md` is where you will read it.** That paragraph
concludes *"the receipt row is the whole difference"*, and it is over-stated — measured, the receipt
row is the **sharpest** difference, not the only one. A frozen `AGENTS.md` also stops the entry
document being generated at all, the freeze is permanent across every later install, and from the
third run on the installer stops listing the file under local edits too. Its `99 → 97` cell is a
two-file figure standing in a single-file column; `AGENTS.md` alone is 99 → 98. Every error there runs
in the same direction — it **understates** the asymmetry — so nothing built on it over-claims, and
your rewrite of that paragraph is where the measured version belongs.

**What this task must do.** Give `AGENTS.md` the treatment `CLAUDE.md` gets, or decide against it with
an argument as explicit as Task 9's. Either way the freeze must stop being silent. Reuse
`CLAUDE.md`'s machinery rather than writing a second one — two merge implementations over two
generated files is how the branch's other paired readers drifted.

**The guard is a fixture, not an assertion**, and this is the shape that has caught every install
defect on this branch: install, **edit the file the way the installer told the user to**, install
again, then assert the resulting tree is internally consistent — the user's prose preserved, the
generated regions current, and `uninstall.sh` still able to remove what it owns and nothing else.
`install.sh` has previously destroyed user files; that is why Task 12 refused to rush this.

---

## Notes for the controller

- **Write each brief just before its task is dispatched, not up front.** Tasks 4
  through 10 all consume measurements that do not exist yet. A brief written now
  would carry the spec's *expectations* as premises, and the loop's own rule is
  that a false premise passes review and ships.
- **Tasks 2 through 7 can return findings that invalidate later tasks.** If Task
  2 measures that Codex imports a `.claude/` configuration natively, Tasks 3
  through 6 shrink and Task 8's ship list changes. That is a successful outcome;
  re-plan rather than executing the tasks as written.
- **The ledger records scene and Editor state after Task 7.** A scene changed
  through MCP and never saved has changed nothing on disk, and the next agent
  opens a project git calls clean and the Editor calls dirty.
