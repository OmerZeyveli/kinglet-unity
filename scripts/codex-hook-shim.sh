#!/usr/bin/env bash
#
# codex-hook-shim.sh — make Kinglet's Claude Code hooks enforce under Codex CLI.
#
# ---------------------------------------------------------------------------
# WHY THIS EXISTS
#
# Codex fires Kinglet's hooks correctly. All 12 register, and Claude Code's
# tool-name matchers (`Edit|Write`, `Bash`) match — both measured in
# docs/research/codex-client/codex-facts.md. What breaks is one level below the
# matcher: Codex's file tool is `apply_patch`, and its `tool_input` carries
# exactly ONE key —
#
#     "tool_input": { "command": "*** Begin Patch\n*** Add File: X.cs\n+…\n*** End Patch" }
#
# — where every Kinglet hook reads `.tool_input.file_path`, `.content`,
# `.new_string` or `.old_string`. Measured control, same hook, same edit, same
# file: block-scene-edit.sh exits 2 on a Claude-shaped payload and 0 on the real
# Codex payload. Eight of the nine tool-event hooks match, run, and do nothing.
# Only bash-gate.sh survives, because `command` happens to be the one field it
# reads.
#
# This script normalises the patch envelope into the shape the hooks already
# read and runs one hook against it, once per file the patch touches. The hooks
# themselves are NOT edited: `.claude/hooks/*.sh` is a shipped Claude Code
# surface with 122 assertions in tests/test-hook-behaviour.sh behind it, and one
# implementation with one test surface is worth more than twelve forks.
#
# ---------------------------------------------------------------------------
# IT FAILS CLOSED, AND THAT IS THE SHARPEST CONSTRAINT IN THE FILE
#
# Codex's block contract, measured (codex-facts.md §F4): a hook refuses a tool
# call by exiting **2** with **at least one byte on stderr**, or by exiting 0
# printing one JSON object with `"decision":"block"` and a non-empty `reason`.
# **Everything else allows the call and logs nothing anywhere** — not to the
# model, not to Codex's stderr, not under `RUST_LOG=debug`. Five near-miss
# shapes were measured into that silent-allow class, and two of them are what a
# careless script does by accident:
#
#   * `exit 2` with no output at all  → allowed, silently
#   * `exit 1` with a message         → allowed, silently
#
# So the ordinary bash failure mode is the dangerous one. Under `set -e`, or on
# an unbound variable under `set -u`, or on a missing `jq`, a script exits
# non-zero but **not 2** — Claude Code reads that as an error, Codex reads it as
# an unlogged allow. A shim that dies on a malformed patch envelope therefore
# fails OPEN, silently, forever.
#
# Three things defend against that, and all three are load-bearing:
#
#   1. **`set -e` is deliberately NOT set.** Every fallible step is checked
#      explicitly. Errexit here would convert a bug into a silent allow.
#   2. **An EXIT trap converts every exit status that is neither 0 nor 2 into a
#      2 with a message on stderr.** Unbound variable, missing interpreter,
#      SIGPIPE, a `return` nobody checked — all of them land on a refusal.
#   3. **Nothing exits 2 without writing stderr first.** `shim_block` is the
#      only refusal path and it always writes. A hook that exits 2 in silence
#      has a message supplied on its behalf, because its silence would be an
#      allow.
#
# The direction is deliberate: an unreadable payload is refused, not waved
# through. A gate that cannot read what it is gating cannot vouch for it.
#
# ---------------------------------------------------------------------------
# DEPENDENCY: jq, AND NOTHING ELSE
#
# Every Kinglet hook already requires `jq` — a tree where it is missing has no
# working hooks under either client, so the shim adds no new obligation. The
# patch envelope is model-authored text that may contain quotes, backslashes,
# `$`, and newlines; jq builds the output JSON directly and never round-trips it
# through a shell word, which is where quoting bugs and injection live.
#
# ---------------------------------------------------------------------------
# USAGE
#
#   codex-hook-shim.sh --hook <name-or-path>          # reads a payload on stdin
#   codex-hook-shim.sh --emit-config [--project-dir D] # writes .codex/hooks.json
#
# See --help.
#
# ---------------------------------------------------------------------------

# NO `set -e`. See "IT FAILS CLOSED" above — errexit is the fail-open hazard
# here, not a safety net. `-u` stays on because an unbound variable is a bug
# worth catching, and the EXIT trap turns it into a refusal rather than an
# allow. `pipefail` reports a failing writer, which the explicit checks read.
set -uo pipefail

SHIM_NAME="codex-hook-shim"
SHIM_TMPDIR=""
HOOK_LABEL="(unresolved)"

# ---------------------------------------------------------------------------
# The fail-closed guard. Installed before ANY other work, including argument
# parsing: a shim that dies while reading its own arguments must still refuse.
#
# Bash does not re-enter an EXIT trap from inside itself, so the `exit 2` below
# is final.
# ---------------------------------------------------------------------------
shim_cleanup() {
  if [ -n "$SHIM_TMPDIR" ] && [ -d "$SHIM_TMPDIR" ]; then
    rm -rf "$SHIM_TMPDIR" 2>/dev/null || true
  fi
}

shim_guard() {
  shim_rc=$?
  shim_cleanup
  if [ "$shim_rc" -eq 0 ] || [ "$shim_rc" -eq 2 ]; then
    exit "$shim_rc"
  fi
  # Anything else is a bug in this script or in its environment. Under Codex a
  # non-2 status is an unlogged allow, so it is converted here rather than
  # reported.
  printf 'BLOCKED: %s failed internally (exit %s) while normalising a tool payload for hook %s.\n' \
    "$SHIM_NAME" "$shim_rc" "$HOOK_LABEL" >&2
  printf '  The tool call is refused because the gate could not read it. A gate that cannot\n' >&2
  printf '  read the payload cannot vouch for it, and under Codex an unreadable failure is\n' >&2
  printf '  otherwise a silent allow.\n' >&2
  exit 2
}
trap shim_guard EXIT

# The one refusal path. Always writes stderr, because `exit 2` in silence is an
# allow under Codex.
shim_block() {
  printf 'BLOCKED: %s\n' "$1" >&2
  exit 2
}

usage() {
  cat <<'EOF'
Usage:
  codex-hook-shim.sh --hook <name-or-path> [options]     # gate mode (reads stdin)
  codex-hook-shim.sh --emit-config [--project-dir DIR]   # config mode (writes stdout)

Gate mode options:
  --hook NAME|PATH     the Kinglet hook to run. A bare name is resolved against
                       $KINGLET_HOOKS_DIR, then <shim>/../.claude/hooks, then
                       <shim>/../hooks (the installed .claude/scripts layout).
  --hooks-dir DIR      explicit hooks directory; takes precedence over the search.
  --timeout SECONDS    per-invocation ceiling for the wrapped hook (default 15,
                       0 disables). On expiry the call is REFUSED, not allowed.

Config mode options:
  --project-dir DIR    project root holding .claude/ (default: the tree this
                       script was installed into).

Gate mode reads one hook payload on stdin and exits:
  0  allow    2  refuse (with a reason on stderr)
Any internal failure is reported as a refusal — see the header.
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing. Every value is validated BEFORE `shift 2`: under `set -u`,
# `shift 2` with one argument left fails before the error message prints and the
# caller gets a silent exit — which here would be a silent allow.
# ---------------------------------------------------------------------------
MODE="gate"
HOOK_ARG=""
HOOKS_DIR_ARG=""
PROJECT_DIR_ARG=""
HOOK_TIMEOUT="${KINGLET_CODEX_HOOK_TIMEOUT:-15}"

while [ $# -gt 0 ]; do
  case "$1" in
    --hook)
      [ $# -ge 2 ] || shim_block "$SHIM_NAME: --hook requires a value"
      HOOK_ARG="$2"; shift 2 ;;
    --hooks-dir)
      [ $# -ge 2 ] || shim_block "$SHIM_NAME: --hooks-dir requires a value"
      HOOKS_DIR_ARG="$2"; shift 2 ;;
    --timeout)
      [ $# -ge 2 ] || shim_block "$SHIM_NAME: --timeout requires a value"
      HOOK_TIMEOUT="$2"; shift 2 ;;
    --project-dir)
      [ $# -ge 2 ] || shim_block "$SHIM_NAME: --project-dir requires a value"
      PROJECT_DIR_ARG="$2"; shift 2 ;;
    --emit-config)
      MODE="emit-config"; shift ;;
    -h|--help)
      # Not a gate invocation: clear the guard so --help exits 0 rather than
      # being converted into a refusal.
      trap - EXIT; usage; exit 0 ;;
    --)
      shift; break ;;
    -*)
      shim_block "$SHIM_NAME: unknown argument: $1" ;;
    *)
      # Bare positional is the hook, so `shim.sh block-meta-edit` works.
      if [ -z "$HOOK_ARG" ]; then HOOK_ARG="$1"; shift
      else shim_block "$SHIM_NAME: unexpected argument: $1"; fi ;;
  esac
done

SHIM_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SHIM_DIR=""
[ -n "$SHIM_DIR" ] || shim_block "$SHIM_NAME: cannot resolve its own directory"

# ===========================================================================
# CONFIG MODE — derive .codex/hooks.json from .claude/settings.json
#
# THE TIMEOUT UNIT IS THE POINT OF THIS MODE, not a detail of it.
# `.claude/settings.json` declares every timeout in MILLISECONDS. Codex's field
# is `timeoutSec` and the unit is SECONDS — measured, not read off the field
# name (codex-facts.md: a 2 s hook survives `timeout: 5` and is killed by
# `timeout: 1`). The external-agent importer copies the number across unchanged,
# so Kinglet's 3000 / 5000 / 2000 become 50, 83 and 33 MINUTES. A hung hook that
# should die in three seconds holds the turn for fifty.
#
# The conversion is here, once, rather than in an installer, so that whatever
# writes the Codex layout cannot get it wrong by omission. Ceiling division: a
# sub-second timeout must not round down to 0, which Codex's schema accepts
# (`minimum: 0`) and which would kill every hook instantly.
# ===========================================================================
if [ "$MODE" = "emit-config" ]; then
  # Config generation is not a gate. Refusing to emit is a build failure, not a
  # tool refusal, so the fail-closed guard is retired here.
  trap 'shim_cleanup' EXIT

  if [ -n "$PROJECT_DIR_ARG" ]; then
    PROJECT_DIR="$(cd "$PROJECT_DIR_ARG" 2>/dev/null && pwd)" || PROJECT_DIR=""
    [ -n "$PROJECT_DIR" ] || { printf '%s: --project-dir not found: %s\n' "$SHIM_NAME" "$PROJECT_DIR_ARG" >&2; exit 1; }
  else
    # Repo layout: <root>/scripts/ -> <root>/.claude/
    # Installed layout: <project>/.claude/scripts/ -> <project>/.claude/
    if [ -f "$SHIM_DIR/../.claude/settings.json" ]; then
      PROJECT_DIR="$(cd "$SHIM_DIR/.." && pwd)"
    elif [ -f "$SHIM_DIR/../settings.json" ]; then
      PROJECT_DIR="$(cd "$SHIM_DIR/../.." && pwd)"
    else
      printf '%s: cannot locate .claude/settings.json from %s — pass --project-dir\n' "$SHIM_NAME" "$SHIM_DIR" >&2
      exit 1
    fi
  fi

  SETTINGS="$PROJECT_DIR/.claude/settings.json"
  [ -f "$SETTINGS" ] || { printf '%s: no settings.json at %s\n' "$SHIM_NAME" "$SETTINGS" >&2; exit 1; }
  command -v jq >/dev/null 2>&1 || { printf '%s: jq not found on PATH\n' "$SHIM_NAME" >&2; exit 1; }

  # Where the shim will live at run time. In the installed layout the hooks and
  # this script are siblings under .claude/; in the repo they are not.
  if [ -f "$PROJECT_DIR/.claude/scripts/codex-hook-shim.sh" ]; then
    SHIM_RUNTIME="$PROJECT_DIR/.claude/scripts/codex-hook-shim.sh"
  else
    SHIM_RUNTIME="$SHIM_DIR/codex-hook-shim.sh"
  fi

  # Tool events get the shim; session events do not. A SessionStart or Stop
  # payload carries no tool_input to normalise, and wrapping a Stop hook in a
  # gate that refuses on error is the wrong trade — there is nothing to refuse.
  jq -n \
    --arg root "$PROJECT_DIR" \
    --arg shim "$SHIM_RUNTIME" \
    --slurpfile s "$SETTINGS" '
    def ceil_sec($ms): if ($ms | type) != "number" then 0
                       elif $ms <= 0 then 0
                       else ((($ms + 999) / 1000) | floor) end;
    def quoted($p): "'"'"'" + $p + "'"'"'";
    ($s[0].hooks // {}) as $h
    | { hooks:
        ( $h
          | with_entries(
              .key as $event
              | .value |= [ .[]
                  | { matcher: (.matcher // ""),
                      hooks: [ .hooks[]
                        | (.command | sub("^\\./"; "")) as $rel
                        | ($root + "/" + $rel) as $abs
                        | { type: "command",
                            command: ( if ($event == "PreToolUse" or $event == "PostToolUse")
                                       then quoted($shim) + " --hook " + quoted($abs)
                                       else quoted($abs) end ),
                            timeout: ceil_sec(.timeout // 0) } ] } ] ) ) }
  ' || { printf '%s: failed to derive hooks.json from %s\n' "$SHIM_NAME" "$SETTINGS" >&2; exit 1; }
  exit 0
fi

# ===========================================================================
# GATE MODE
# ===========================================================================

[ -n "$HOOK_ARG" ] || shim_block "$SHIM_NAME: --hook is required (no hook named, so nothing could be checked)"

# --- Resolve the hook -------------------------------------------------------
resolve_hook() {
  case "$1" in
    */*) printf '%s\n' "$1"; return 0 ;;
  esac
  h_name="$1"
  case "$h_name" in *.sh) ;; *) h_name="${h_name}.sh" ;; esac
  for h_dir in \
      "${HOOKS_DIR_ARG:-}" \
      "${KINGLET_HOOKS_DIR:-}" \
      "$SHIM_DIR/../.claude/hooks" \
      "$SHIM_DIR/../hooks" \
      "$SHIM_DIR/hooks"; do
    [ -n "$h_dir" ] || continue
    if [ -f "$h_dir/$h_name" ]; then printf '%s\n' "$h_dir/$h_name"; return 0; fi
  done
  return 1
}

HOOK_PATH="$(resolve_hook "$HOOK_ARG")" || shim_block \
  "$SHIM_NAME: hook '$HOOK_ARG' not found. Searched \$KINGLET_HOOKS_DIR, <shim>/../.claude/hooks and <shim>/../hooks. Refusing rather than running unguarded."
HOOK_LABEL="$(basename "$HOOK_PATH")"
[ -f "$HOOK_PATH" ] || shim_block "$SHIM_NAME: hook file does not exist: $HOOK_PATH"
[ -r "$HOOK_PATH" ] || shim_block "$SHIM_NAME: hook file is not readable: $HOOK_PATH"

command -v jq >/dev/null 2>&1 || shim_block \
  "$SHIM_NAME: jq is not on PATH, so the payload cannot be read. Every Kinglet hook needs jq; a tree without it has no working gate under either client."

case "$HOOK_TIMEOUT" in
  ''|*[!0-9]*) shim_block "$SHIM_NAME: --timeout must be a whole number of seconds, got '$HOOK_TIMEOUT'" ;;
esac

# --- Read the payload -------------------------------------------------------
PAYLOAD="$(cat)" || shim_block "$SHIM_NAME: could not read the hook payload from stdin"
[ -n "$PAYLOAD" ] || shim_block \
  "$SHIM_NAME: empty payload on stdin for hook $HOOK_LABEL. Nothing could be checked, so the call is refused."

printf '%s' "$PAYLOAD" | jq -e 'type == "object"' >/dev/null 2>&1 || shim_block \
  "$SHIM_NAME: the payload handed to $HOOK_LABEL is not a JSON object. Refusing: an unparseable payload is exactly the case where allowing means the gate is silently dead."

SHIM_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/kinglet-codex-shim.XXXXXX")" \
  || shim_block "$SHIM_NAME: could not create a temporary directory"

# --- Decide the route -------------------------------------------------------
#
# passthrough — the payload is already in the shape the hooks read (a Bash
#               `command`, a Claude-shaped `file_path`, or a session event with
#               no tool_input at all). bash-gate.sh reaches Codex's shell
#               payload unaided; nothing needs translating.
# patch       — an apply_patch envelope. Normalise it.
# unparseable — announced as apply_patch but carrying no envelope this script
#               recognises. REFUSE: this is the case where guessing is what
#               makes a gate silently dead.
ROUTE="$(printf '%s' "$PAYLOAD" | jq -r '
  (.tool_name // "") as $tn
  | (if (.tool_input | type) == "object" then .tool_input else {} end) as $ti
  | (if ($ti.command | type) == "string" then $ti.command else "" end) as $cmd
  | if (($ti.file_path | type) == "string" and $ti.file_path != "") then "passthrough"
    elif ($cmd | startswith("*** Begin Patch")) then "patch"
    elif ($tn == "apply_patch") then "unparseable"
    else "passthrough" end
')" || shim_block "$SHIM_NAME: jq failed while classifying the payload for $HOOK_LABEL"

case "$ROUTE" in
  passthrough|patch|unparseable) ;;
  *) shim_block "$SHIM_NAME: could not classify the payload handed to $HOOK_LABEL" ;;
esac

if [ "$ROUTE" = "unparseable" ]; then
  shim_block "$SHIM_NAME: an apply_patch call reached $HOOK_LABEL carrying no readable patch envelope, so the files it would touch are unknown. Refusing the call rather than allowing an unchecked edit."
fi

# --- Normalise --------------------------------------------------------------
#
# One Claude-shaped payload per file the patch touches, because one envelope can
# carry several and a gate that only inspects the first is a gate with a hole.
#
# Paths are made ABSOLUTE against the payload's own `cwd`. That is not cosmetic:
# block-legacy-input.sh and warn-platform-defines.sh anchor their third-party
# skips on a leading path segment (`*/Assets/Extensions/*`, `*/Library/PackageCache/*`)
# and their own comments record that Claude Code sends absolute paths. Handing
# them Codex's relative `Add File:` path would change which files they skip.
#
# Content mapping, chosen so each hook sees what it sees under Claude Code:
#   Add File    -> tool_name "Write", tool_input.content   = the added lines
#   Update File -> tool_name "Edit",  tool_input.new_string = the added lines
#                                     tool_input.old_string = the removed lines
#   Delete File -> tool_name "Edit", both strings empty; the path is the signal
#   Move to     -> the source AND destination paths are each checked
if [ "$ROUTE" = "patch" ]; then
  PAYLOADS_FILE="$SHIM_TMPDIR/payloads.jsonl"
  printf '%s' "$PAYLOAD" | jq -c '
    def flush: if .cur == null then . else (.files += [.cur] | .cur = null) end;
    def hdrval($p): ltrimstr($p) | rtrimstr("\r");

    . as $orig
    | ($orig.cwd // "") as $cwd
    | ((.tool_input // {}).command // "") as $cmd
    | (reduce ($cmd | split("\n"))[] as $l ({files: [], cur: null};
          if   ($l | startswith("*** Begin Patch"))   then .
          elif ($l | startswith("*** End Patch"))     then flush
          elif ($l | startswith("*** Add File: "))    then flush | .cur = {op:"add",    path: ($l | hdrval("*** Add File: ")),    add: [], del: [], move: ""}
          elif ($l | startswith("*** Update File: ")) then flush | .cur = {op:"update", path: ($l | hdrval("*** Update File: ")), add: [], del: [], move: ""}
          elif ($l | startswith("*** Delete File: ")) then flush | .cur = {op:"delete", path: ($l | hdrval("*** Delete File: ")), add: [], del: [], move: ""}
          elif ($l | startswith("*** Move to: "))     then (if .cur == null then . else .cur.move = ($l | hdrval("*** Move to: ")) end)
          elif ($l | startswith("*** End of File"))   then .
          elif ($l | startswith("@@"))                then .
          elif (.cur == null)                         then .
          elif ($l | startswith("+"))                 then .cur.add += [$l[1:]]
          elif ($l | startswith("-"))                 then .cur.del += [$l[1:]]
          else . end)
       | flush | .files) as $files
    | [ $files[]
        | . as $f
        | ([$f.path] + (if ($f.move // "") == "" then [] else [$f.move] end))[]
        | . as $p
        | ($p | sub("^\\./"; "")) as $clean
        | (if ($clean | startswith("/")) then $clean
           elif ($cwd == "") then $clean
           else ($cwd + "/" + $clean) end) as $abs
        | $orig
          + { tool_name: (if $f.op == "add" then "Write" else "Edit" end),
              tool_input: ( if $f.op == "add"
                            then { file_path: $abs, content: ($f.add | join("\n")) }
                            else { file_path: $abs,
                                   old_string: ($f.del | join("\n")),
                                   new_string: ($f.add | join("\n")) } end),
              kinglet_shim: { source_tool: ($orig.tool_name // ""), op: $f.op, patch_path: $f.path } }
      ]
    | .[]
  ' > "$PAYLOADS_FILE" 2>"$SHIM_TMPDIR/jq.err"
  jq_rc=$?
  if [ "$jq_rc" -ne 0 ]; then
    shim_block "$SHIM_NAME: could not parse the apply_patch envelope handed to $HOOK_LABEL (jq exit $jq_rc). Refusing the call rather than allowing an unchecked edit."
  fi

  # An envelope that yields no files is not an empty edit — it is an envelope
  # this parser did not understand. Refuse.
  PAYLOAD_COUNT="$(awk 'NF { n++ } END { print n + 0 }' "$PAYLOADS_FILE")" \
    || shim_block "$SHIM_NAME: could not count the normalised payloads for $HOOK_LABEL"
  if [ "$PAYLOAD_COUNT" -eq 0 ]; then
    shim_block "$SHIM_NAME: the apply_patch envelope handed to $HOOK_LABEL named no file this shim could read (no Add/Update/Delete File header). Refusing: the files it would touch are unknown."
  fi
else
  PAYLOADS_FILE="$SHIM_TMPDIR/payloads.jsonl"
  printf '%s\n' "$PAYLOAD" > "$PAYLOADS_FILE" \
    || shim_block "$SHIM_NAME: could not stage the payload for $HOOK_LABEL"
fi

# --- Run the hook, once per normalised payload ------------------------------
#
# The wrapped hook gets its payload on a redirected stdin. Without the redirect
# it would inherit this loop's stdin and eat the remaining payloads — a bug that
# looks exactly like "the second file in a patch is never checked".
#
# THE WATCHDOG REFUSES ON EXPIRY. Codex enforces its own `timeoutSec`, but this
# script does not own the file that declares it, and the declared value has been
# measured wrong by a factor of 1000 in the tree this shim exists to serve. A
# ceiling here holds whatever that file says. `timeout(1)` is GNU coreutils and
# absent on a stock macOS host, so the watchdog is a background killer instead —
# the same shape works on bash 3.2.
run_hook() {
  rh_payload_file="$1"
  rh_out="$2"
  rh_err="$3"
  if [ "$HOOK_TIMEOUT" -eq 0 ]; then
    bash "$HOOK_PATH" < "$rh_payload_file" > "$rh_out" 2> "$rh_err"
    return $?
  fi
  bash "$HOOK_PATH" < "$rh_payload_file" > "$rh_out" 2> "$rh_err" &
  rh_pid=$!
  ( sleep "$HOOK_TIMEOUT"; kill -TERM "$rh_pid" ) >/dev/null 2>&1 &
  rh_killer=$!
  wait "$rh_pid" >/dev/null 2>&1
  rh_rc=$?
  kill -TERM "$rh_killer" >/dev/null 2>&1
  wait "$rh_killer" >/dev/null 2>&1
  return "$rh_rc"
}

ADVISORY_TEXT=""
LINE_NO=0
while IFS= read -r shim_line; do
  [ -n "$shim_line" ] || continue
  LINE_NO=$((LINE_NO + 1))
  printf '%s\n' "$shim_line" > "$SHIM_TMPDIR/payload.$LINE_NO.json" \
    || shim_block "$SHIM_NAME: could not stage payload $LINE_NO for $HOOK_LABEL"

  run_hook "$SHIM_TMPDIR/payload.$LINE_NO.json" \
           "$SHIM_TMPDIR/out.$LINE_NO" "$SHIM_TMPDIR/err.$LINE_NO"
  hook_rc=$?

  hook_err="$(cat "$SHIM_TMPDIR/err.$LINE_NO" 2>/dev/null || true)"
  hook_out="$(cat "$SHIM_TMPDIR/out.$LINE_NO" 2>/dev/null || true)"

  if [ "$hook_rc" -eq 2 ]; then
    # The hook refused. Forward its reason verbatim: Codex interpolates the
    # entire stderr into `Command blocked by PreToolUse hook: <stderr>`, so
    # Kinglet's own `BLOCKED:` prefix reaches the model unchanged.
    if [ -n "$hook_err" ]; then
      printf '%s\n' "$hook_err" >&2
      exit 2
    fi
    # A silent exit 2 is an ALLOW under Codex. Supply the message the hook
    # did not write, rather than forwarding its silence.
    shim_block "$HOOK_LABEL refused this call but wrote no reason. Refusing on its behalf: under Codex an exit 2 with no message is a silent allow."
  fi

  if [ "$hook_rc" -ge 128 ]; then
    shim_block "$HOOK_LABEL was killed by a signal (status $hook_rc) after ${HOOK_TIMEOUT}s. Refusing: a gate that did not finish has not approved anything."
  fi

  if [ "$hook_rc" -ne 0 ]; then
    # Not 0, not 2 — the hook itself failed. Under Codex this status is an
    # unlogged allow, so it is converted here.
    shim_block "$HOOK_LABEL exited $hook_rc, which is neither an allow (0) nor a refusal (2). Refusing: under Codex any other status permits the call and reports nothing. stderr was: ${hook_err:-<empty>}"
  fi

  # A REFUSAL EXPRESSED THE OTHER LEGAL WAY MUST NOT BE COLLECTED AS ADVICE.
  # Codex accepts two block protocols, and the second is a JSON object on stdout
  # with `decision: "block"` and a non-empty reason — exit status 0. No Kinglet
  # hook uses it today (they all go through `unity_hook_block`, which is exit 2 +
  # stderr), but a wrapper that swallowed it would silently convert a future
  # hook's block into an allow with a note attached, which is the exact failure
  # class this script exists to prevent. An EMPTY reason is refused too: Codex
  # measurably ignores that shape and says nothing, so passing it on would be a
  # silent allow.
  if [ -n "$hook_out" ]; then
    hook_decision="$(printf '%s' "$hook_out" \
      | jq -r 'if (type == "object") and (.decision == "block")
               then "KINGLET-BLOCK\t" + ((.reason // "") | tostring) else "" end' 2>/dev/null)" \
      || hook_decision=""
    case "$hook_decision" in
      "KINGLET-BLOCK	"*)
        hook_reason="${hook_decision#KINGLET-BLOCK	}"
        if [ -n "$hook_reason" ]; then
          shim_block "$HOOK_LABEL refused this call: $hook_reason"
        fi
        shim_block "$HOOK_LABEL emitted a decision:block with an empty reason. Refusing on its behalf: Codex ignores that shape entirely and reports nothing, so forwarding it would be a silent allow."
        ;;
    esac
  fi

  # Allowed. Collect anything advisory the hook wrote so it can be delivered
  # below — see the note at the emitter.
  if [ -n "$hook_err" ]; then
    ADVISORY_TEXT="${ADVISORY_TEXT}${hook_err}
"
  fi
  if [ -n "$hook_out" ]; then
    ADVISORY_TEXT="${ADVISORY_TEXT}${hook_out}
"
  fi
done < "$PAYLOADS_FILE"

if [ "$LINE_NO" -eq 0 ]; then
  shim_block "$SHIM_NAME: no payload reached $HOOK_LABEL, so nothing was checked."
fi

# --- Deliver advisory output ------------------------------------------------
#
# Kinglet's three warn-* hooks exit 0 and write their warning to stderr. Under
# Claude Code that is surfaced. Under Codex the stderr of a hook that exits 0 is
# DISCARDED, and so is plain text on stdout — measured, both. The one route that
# reaches the model is a JSON object on stdout carrying
# `hookSpecificOutput.additionalContext`, which was measured delivering a
# sentinel the model quoted back.
#
# Without this block the advisory hooks would fire, act, and still tell nobody —
# which is the same defect as the payload problem one layer further on.
if [ -n "$ADVISORY_TEXT" ]; then
  EVENT_NAME="$(printf '%s' "$PAYLOAD" | jq -r '.hook_event_name // "PreToolUse"' 2>/dev/null)" \
    || EVENT_NAME="PreToolUse"
  [ -n "$EVENT_NAME" ] || EVENT_NAME="PreToolUse"
  printf '%s' "$ADVISORY_TEXT" | jq -R -s \
    --arg event "$EVENT_NAME" \
    '{hookSpecificOutput: {hookEventName: $event, additionalContext: .}}' \
    2>/dev/null || true
fi

exit 0
