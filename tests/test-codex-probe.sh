#!/usr/bin/env bash
# ============================================================================
# test-codex-probe.sh — guards scripts/codex-probe.sh: isolation, argument
# safety, and failure reporting.
#
# A stub `codex` on PATH stands in for the real CLI, so this test never calls a
# model: it is free, offline, and deterministic. The stub records how it was
# invoked (argv, CODEX_HOME, what it saw on stdin) and emits a minimal but
# valid event stream.
#
# Self-contained idiom: own helpers, own `set -euo pipefail`. `bash
# tests/test-codex-probe.sh` really does assert.
# ============================================================================
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

# The default --out is the repository's own evidence directory, and it is used
# by one probe below precisely because it is NOT under /tmp. Its contents are
# gitignored, but the run still leaves four files behind, so clean them up.
DEFAULT_OUT="$REPO_DIR/docs/research/codex-client/evidence"
cleanup() {
  rm -rf "$SANDBOX"
  rm -f "$DEFAULT_OUT"/defaultout.jsonl "$DEFAULT_OUT"/defaultout.last.txt \
        "$DEFAULT_OUT"/defaultout.stderr.txt "$DEFAULT_OUT"/defaultout.meta.json
  rm -rf "$DEFAULT_OUT"/.home-defaultout.*
}
trap cleanup EXIT

# --- stub codex -------------------------------------------------------------
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/codex" <<'STUB'
#!/usr/bin/env bash
# Records how it was called, then emits a minimal valid event stream.
if [ "${1:-}" = "--version" ]; then echo "codex-cli 0.145.0-stub"; exit 0; fi
{
  echo "ARGS: $*"
  echo "CODEX_HOME: ${CODEX_HOME:-UNSET}"
  # Stdin: the harness must hand codex /dev/null. A real read distinguishes the
  # two states that matter — EOF (redirected to /dev/null) versus a line of data
  # (the caller's stdin leaked through). `read -t 0` cannot: measured on this
  # host, it reports /dev/null as "input available" exactly as it reports a data
  # file, so it would be green in both directions.
  #
  # The timeout is what keeps a leak from becoming a hang: an inherited stdin
  # that is an open pipe with no data would block a plain `read` forever, and a
  # hung suite is worse than a red one. rc>128 is the timeout, and it is reported
  # as its own third state rather than folded into "empty".
  if [ -t 0 ]; then
    echo "STDIN: tty"
  else
    stdin_line=""
    IFS= read -r -t 5 stdin_line; stdin_rc=$?
    if [ "$stdin_rc" -eq 0 ]; then echo "STDIN: leaked [$stdin_line]"
    elif [ "$stdin_rc" -gt 128 ]; then echo "STDIN: blocked (read timed out)"
    elif [ -n "$stdin_line" ]; then echo "STDIN: leaked [$stdin_line]"
    else echo "STDIN: empty"
    fi
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

# Fed to the harness on stdin. If the harness fails to redirect codex's stdin to
# /dev/null, the stub reads this sentinel and the stdin assertion goes red.
printf 'SENTINEL-STDIN-MUST-NOT-REACH-CODEX\n' > "$SANDBOX/stdin.txt"

# Every invocation reads its stdin from the sentinel file — not just the one
# that checks stdin. Two reasons. It makes the stdin assertion mean the same
# thing on every run regardless of what the caller's stdin happened to be (the
# runner hands each test file /dev/null, which would make a harness that forgot
# to redirect look identical to one that did). And it keeps a leak from hanging:
# the stub's read always meets a regular file, never an open pipe.
run_probe() {
  PATH="$SANDBOX/bin:$PATH" HOME="$SANDBOX/home" \
    bash "$REPO_DIR/scripts/codex-probe.sh" "$@" 2>&1 < "$SANDBOX/stdin.txt"
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
# awk reading the file directly, not `grep | head`: a reader that exits early on
# a pipe SIGPIPEs the writer, and pipefail turns that into a failed test.
home_line="$(awk '/^CODEX_HOME: / {print; exit}' "$STUB_LOG")"
probe_home="${home_line#CODEX_HOME: }"
if [ -z "$home_line" ]; then
  bad "CODEX_HOME is set for the probe (the stub recorded no CODEX_HOME line at all)"
elif [ "$probe_home" = "UNSET" ]; then
  bad "CODEX_HOME is set for the probe (it was UNSET)"
else
  ok "CODEX_HOME is set for the probe"
fi
case "$probe_home" in
  "$OUT"/*) ok  "the disposable CODEX_HOME is derived from --out, beside the evidence" ;;
  *)        bad "the disposable CODEX_HOME is not under --out: $probe_home" ;;
esac
contains "$log" "--ignore-user-config" "codex is invoked with --ignore-user-config"

# The disposable home held a credential; it must be gone. An empty or UNSET
# path would make `[ ! -e ]` pass while proving nothing, so it is rejected here.
if [ -z "$probe_home" ] || [ "$probe_home" = "UNSET" ]; then
  bad "the disposable CODEX_HOME is removed on exit (no path was recorded to check)"
elif [ ! -e "$probe_home" ]; then
  ok "the disposable CODEX_HOME is removed on exit"
else
  bad "the disposable CODEX_HOME survived: $probe_home"
fi

# Codex warns "Refusing to create helper binaries under temporary dir" when
# CODEX_HOME sits under /tmp, which would pollute every probe's stderr. The
# assertion above cannot catch that on its own, because this test's own sandbox
# lives under /tmp. So run one probe against the harness's DEFAULT --out — the
# repository's evidence directory, which is not under /tmp — and check there.
: > "$STUB_LOG"
set +e
run_probe --name defaultout --prompt "$SANDBOX/prompt.txt" >/dev/null 2>&1
rc=$?
set -e
check "$rc" "0" "a run with the default --out exits 0"
default_home_line="$(awk '/^CODEX_HOME: / {print; exit}' "$STUB_LOG")"
default_home="${default_home_line#CODEX_HOME: }"
case "$default_home" in
  /tmp/*|/var/tmp/*|/private/tmp/*|/private/var/tmp/*)
      bad "the disposable CODEX_HOME landed under a temp dir: $default_home" ;;
  "$DEFAULT_OUT"/*)
      ok  "with the default --out the disposable CODEX_HOME is not under /tmp" ;;
  *)  bad "the disposable CODEX_HOME is not under the default evidence dir: $default_home" ;;
esac
[ -f "$DEFAULT_OUT/defaultout.meta.json" ] \
  && ok "the default --out is the repository's evidence directory" \
  || bad "the default --out is the repository's evidence directory"

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
