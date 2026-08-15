#!/usr/bin/env bash
# ============================================================================
# test-codex-probe.sh — guards scripts/codex-probe.sh: isolation, argument
# safety, and failure reporting.
#
# A stub `codex` on PATH stands in for the real CLI, so this test never calls a
# model: it is free, offline, and deterministic. The stub records how it was
# invoked (argv, CODEX_HOME, the mode and contents of that home, what it saw on
# stdin) and emits a minimal but valid event stream.
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
# Every read of an evidence file goes through this. A bare `cat` of a file the
# harness failed to write kills the whole file under `set -e`, and it dies
# BEFORE the verdict line at the bottom — so the section reads, in a suite log,
# exactly like a section that finished. Measured with the harness moved aside:
# 19 FAILs, the last three assertions never reached, and no `=== … ===` line.
slurp() { if [ -f "$1" ]; then cat "$1"; else printf '(missing file: %s)' "$1"; fi; }

# Read one prefixed line out of the stub's log. awk on the file directly, never
# `grep | head`: a reader that exits early on a pipe SIGPIPEs the writer, and
# pipefail turns that into a failed test.
logline() { awk -v pfx="$1" 'index($0, pfx) == 1 { print substr($0, length(pfx) + 1); exit }' "$STUB_LOG"; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/codex-probe-test.XXXXXX")"

# The default --out is the repository's own evidence directory, and it is used
# by one probe below precisely because it is NOT under /tmp. Its contents are
# gitignored, but the run still leaves four files behind, so clean them up.
#
# The probe's NAME carries this test's pid. It did not until 2026-08-15, and
# fixed names in a shared directory mean two concurrent suite runs write and
# delete each other's evidence — CLAUDE.md records running two suites at once as
# the way its SIGPIPE flake reproduces every time, and the cost of that class of
# bug is not its failure rate but the afternoon the next person spends
# disbelieving it. `$$` removes the collision by construction.
DEFAULT_OUT="$REPO_DIR/docs/research/codex-client/evidence"
DEFAULT_NAME="defaultout.$$"
cleanup() {
  rm -rf "$SANDBOX"
  rm -f "$DEFAULT_OUT/$DEFAULT_NAME".jsonl "$DEFAULT_OUT/$DEFAULT_NAME".last.txt \
        "$DEFAULT_OUT/$DEFAULT_NAME".stderr.txt "$DEFAULT_OUT/$DEFAULT_NAME".meta.json
  rm -rf "$DEFAULT_OUT/.home-$DEFAULT_NAME".*
}
trap cleanup EXIT

# --- stub codex -------------------------------------------------------------
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/codex" <<'STUB'
#!/usr/bin/env bash
# Records how it was called, then emits a minimal valid event stream.
if [ "${1:-}" = "--version" ]; then echo "codex-cli 0.145.0-stub"; exit 0; fi

# GNU first, BSD second: `stat -c` is GNU-only and macOS needs `stat -f '%Lp'`.
mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || echo "?"; }

{
  echo "ARGS: $*"
  echo "CODEX_HOME: ${CODEX_HOME:-UNSET}"
  # The credential constraint has three clauses — home 700, copy 600, and the
  # home holding nothing it was not given. All three are recorded here, because
  # a constraint asserted by nothing is a constraint the next edit can drop.
  echo "HOME_MODE: $(mode_of "${CODEX_HOME:-/nonexistent}")"
  echo "AUTH_MODE: $(mode_of "${CODEX_HOME:-/nonexistent}/auth.json")"
  home_entries="$( (cd "${CODEX_HOME:-/nonexistent}" 2>/dev/null && ls -A) | sort | tr '\n' ' ')"
  echo "HOME_ENTRIES: [${home_entries% }]"
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

# Long enough to be killed mid-run, for the orphan-reclamation section.
if [ -n "${STUB_SLEEP:-}" ]; then sleep "$STUB_SLEEP"; fi

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

# The fake ~/.codex is DELIBERATELY not just a credential. config.toml and
# skills/ are the owner's real configuration, and they are here so that widening
# the harness's `cp` to the whole directory has something to leak — without
# them, `cp -R "$HOME/.codex/."` and a single-file copy produce byte-identical
# homes and the contamination assertion is green in both directions.
mkdir -p "$SANDBOX/home/.codex/skills/owner-skill"
printf '{"stub":"credential"}' > "$SANDBOX/home/.codex/auth.json"
printf 'model = "owners-choice"\n' > "$SANDBOX/home/.codex/config.toml"
printf 'name: owner-skill\n' > "$SANDBOX/home/.codex/skills/owner-skill/SKILL.md"

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
: > "$STUB_LOG"
set +e
out="$(run_probe --name smoke --prompt "$SANDBOX/prompt.txt" --out "$OUT" 2>&1)"; rc=$?
set -e
check "$rc" "0" "a normal run exits 0"
[ -f "$OUT/smoke.jsonl" ]     && ok "writes NAME.jsonl"      || bad "writes NAME.jsonl"
[ -f "$OUT/smoke.last.txt" ]  && ok "writes NAME.last.txt"   || bad "writes NAME.last.txt"
[ -f "$OUT/smoke.stderr.txt" ]&& ok "writes NAME.stderr.txt" || bad "writes NAME.stderr.txt"
[ -f "$OUT/smoke.meta.json" ] && ok "writes NAME.meta.json"  || bad "writes NAME.meta.json"
check "$(slurp "$OUT/smoke.last.txt")" "STUB-OK" "last.txt holds the final agent message"

log="$(slurp "$STUB_LOG")"
contains "$log" "STDIN: empty" "codex is invoked with stdin at /dev/null"

# --- 2b. the invocation itself, pinned ---------------------------------------
# Every flag here is a contract some later task depends on, and until 2026-08-15
# only --ignore-user-config was asserted: --sandbox could be rewritten to
# danger-full-access, and --cd, --json and --skip-git-repo-check could each be
# deleted outright, with the suite staying green through all four. --sandbox is
# the worst of them, because meta.json's "sandbox" field is written from the
# variable rather than from argv, so the evidence file would have recorded
# read-only for a run that executed at danger-full-access — and this wave's whole
# deliverable is a recorded verdict.
#
# Pinned as the WHOLE argv rather than as four `contains` needles: a needle set
# says nothing about what else is on the line, and adding a flag ought to be a
# deliberate edit here.
check "$(logline 'ARGS: ')" \
      "exec --json --skip-git-repo-check --ignore-user-config --sandbox read-only --cd $REPO_DIR -o $OUT/smoke.last.txt say hello" \
      "the default invocation is exactly the documented argv"
contains "$log" "--ignore-user-config" "codex is invoked with --ignore-user-config"

# The three flags that vary, and their agreement with what meta.json records.
mkdir -p "$SANDBOX/work"
: > "$STUB_LOG"
set +e
run_probe --name argv --prompt "$SANDBOX/prompt.txt" --out "$OUT" \
          --sandbox workspace-write --model probe-model-x --workdir "$SANDBOX/work" >/dev/null 2>&1
rc=$?
set -e
check "$rc" "0" "a run with --sandbox, --model and --workdir exits 0"
check "$(logline 'ARGS: ')" \
      "exec --json --skip-git-repo-check --ignore-user-config --sandbox workspace-write --cd $SANDBOX/work -o $OUT/argv.last.txt --model probe-model-x say hello" \
      "--sandbox, --workdir and --model reach codex's argv"
argv_meta="$(slurp "$OUT/argv.meta.json")"
contains "$argv_meta" "\"sandbox\": \"workspace-write\"" "meta's sandbox agrees with the argv codex was given"
contains "$argv_meta" "\"model\": \"probe-model-x\"" "meta records the model"
contains "$argv_meta" "\"workdir\": \"$SANDBOX/work\"" "meta records the workdir"
contains "$argv_meta" "\"say hello\"" "meta's codex_argv records the prompt, not just the flags"

# --- 3. isolation -----------------------------------------------------------
: > "$STUB_LOG"
set +e
run_probe --name iso --prompt "$SANDBOX/prompt.txt" --out "$OUT" >/dev/null 2>&1
set -e
probe_home="$(logline 'CODEX_HOME: ')"
if [ -z "$probe_home" ]; then
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

# The credential constraint, all three clauses. Only the third was guarded until
# 2026-08-15; the two chmods could each be replaced by `:`, and the copy widened
# to the owner's whole ~/.codex, with the suite staying at green.
check "$(logline 'HOME_MODE: ')" "700" "the disposable CODEX_HOME is mode 700"
check "$(logline 'AUTH_MODE: ')" "600" "the copied credential is mode 600"
check "$(logline 'HOME_ENTRIES: ')" "[auth.json]" \
      "the disposable home holds the credential and nothing else of the owner's"

# The disposable home held a credential; it must be gone. An empty or UNSET
# path would make `[ ! -e ]` pass while proving nothing, so it is rejected here.
if [ -z "$probe_home" ] || [ "$probe_home" = "UNSET" ]; then
  bad "the disposable CODEX_HOME is removed on exit (no path was recorded to check)"
elif [ ! -e "$probe_home" ]; then
  ok "the disposable CODEX_HOME is removed on exit"
else
  bad "the disposable CODEX_HOME survived: $probe_home"
fi

# --seed is the one way anything is meant to reach that home besides the
# credential, and it is how Task 3 will plant a config. Same assertion, one file
# added: the home is the credential plus exactly what was seeded.
mkdir -p "$SANDBOX/seed"
printf 'seeded\n' > "$SANDBOX/seed/seedmarker.txt"
: > "$STUB_LOG"
set +e
run_probe --name seeded --prompt "$SANDBOX/prompt.txt" --out "$OUT" --seed "$SANDBOX/seed" >/dev/null 2>&1
set -e
check "$(logline 'HOME_ENTRIES: ')" "[auth.json seedmarker.txt]" \
      "a seeded home holds the credential plus exactly what --seed carried"

# Codex warns "Refusing to create helper binaries under temporary dir" when
# CODEX_HOME sits under /tmp, which would pollute every probe's stderr. The
# assertion above cannot catch that on its own, because this test's own sandbox
# lives under /tmp. So run one probe against the harness's DEFAULT --out — the
# repository's evidence directory, which is not under /tmp — and check there.
: > "$STUB_LOG"
set +e
run_probe --name "$DEFAULT_NAME" --prompt "$SANDBOX/prompt.txt" >/dev/null 2>&1
rc=$?
set -e
check "$rc" "0" "a run with the default --out exits 0"
default_home="$(logline 'CODEX_HOME: ')"
case "$default_home" in
  /tmp/*|/var/tmp/*|/private/tmp/*|/private/var/tmp/*)
      bad "the disposable CODEX_HOME landed under a temp dir: $default_home" ;;
  "$DEFAULT_OUT"/*)
      ok  "with the default --out the disposable CODEX_HOME is not under /tmp" ;;
  *)  bad "the disposable CODEX_HOME is not under the default evidence dir: $default_home" ;;
esac
[ -f "$DEFAULT_OUT/$DEFAULT_NAME.meta.json" ] \
  && ok "the default --out is the repository's evidence directory" \
  || bad "the default --out is the repository's evidence directory"

# --- 4. metadata ------------------------------------------------------------
meta="$(slurp "$OUT/smoke.meta.json")"
contains "$meta" "0.145.0-stub" "meta records the codex version actually used"
contains "$meta" "\"exit_code\": 0" "meta records the exit code"

# --- 5. a failing codex run is reported, not swallowed -----------------------
set +e
STUB_EXIT=3 run_probe --name boom --prompt "$SANDBOX/prompt.txt" --out "$OUT" >/dev/null 2>&1
rc=$?
set -e
check "$rc" "3" "a non-zero codex exit propagates"
contains "$(slurp "$OUT/boom.meta.json")" "\"exit_code\": 3" "meta records a non-zero exit"

# --- 6. a killed run's disposable home is reclaimed --------------------------
# SIGKILL is the case no trap can ever cover, and the disposable home holds a
# copy of the credential. Before 2026-08-15 nothing reclaimed it: the harness's
# pre-run `rm -rf` clears only its OWN pid's path, so an orphan survived every
# subsequent run forever. SIGKILL is used rather than SIGINT because it is the
# only signal whose outcome is deterministic — measured on this host, bash 5.2
# runs the EXIT trap for SIGINT and SIGTERM (0 leftovers in 70 runs each), so a
# test built on those would be green with or without the harness's signal arms.
REAP_OUT="$SANDBOX/evidence-reap"
mkdir -p "$REAP_OUT"
set -m
STUB_SLEEP=20 PATH="$SANDBOX/bin:$PATH" HOME="$SANDBOX/home" \
  bash "$REPO_DIR/scripts/codex-probe.sh" --name reaped --prompt "$SANDBOX/prompt.txt" \
       --out "$REAP_OUT" >/dev/null 2>&1 < "$SANDBOX/stdin.txt" &
victim=$!
set +m
reap_wait=0
while [ ! -d "$REAP_OUT/.home-reaped.$victim" ] && [ "$reap_wait" -lt 200 ]; do
  sleep 0.05; reap_wait=$((reap_wait+1))
done
kill -KILL -"$victim" 2>/dev/null || true
set +e; wait "$victim" 2>/dev/null; set -e

# The setup has to be real or the reclamation below proves nothing: an orphan
# that was never created is reclaimed by doing nothing at all. Measured with the
# harness moved aside, before this was carried into the second assertion: the
# setup went red and the reclamation still reported PASS — the one vacuous pass
# in the file.
orphan_made=no
if [ -f "$REAP_OUT/.home-reaped.$victim/auth.json" ]; then
  orphan_made=yes
  ok "a killed run leaves its disposable home behind, credential and all (the state being fixed)"
else
  bad "the orphan setup did not produce a home holding a credential — the reclamation assertion below would be vacuous"
fi

set +e
run_probe --name after --prompt "$SANDBOX/prompt.txt" --out "$REAP_OUT" >/dev/null 2>&1
set -e
if [ "$orphan_made" != yes ]; then
  bad "a later probe reclaims the killed run's disposable home (no orphan was created, so nothing was reclaimed)"
elif [ -e "$REAP_OUT/.home-reaped.$victim" ]; then
  bad "a later probe did not reclaim the killed run's home: $REAP_OUT/.home-reaped.$victim"
else
  ok "a later probe reclaims the killed run's disposable home"
fi

printf '\n=== Codex Probe Harness: %d/%d passed, %d failed ===\n' \
  "$PASS" "$((PASS+FAIL))" "$FAIL"
[ "$FAIL" -eq 0 ]
