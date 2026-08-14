#!/usr/bin/env bash
# ============================================================================
# test-mcp-citations.sh — every `<tool> action:"<action>"` pair a shipped surface cites must name an
# action that exists on the MCP bridge.
#
# THIS VERIFIES AGAINST A SNAPSHOT, NOT AGAINST A LIVE SERVER, AND THE SNAPSHOT IS THE PART THAT
# ROTS. The allow-list below was recorded on 2026-08-14 by executing calls against
# `mcp-for-unity-server 3.4.5` (`mcpforunityserver==10.1.0`) on Unity 6000.0.68f1. Nothing in this
# suite can reach a live editor — checking a cited action for real needs Unity running and the bridge
# up, which is exactly why the four dead names below survived from the day they were written. So this
# guard cannot tell you that a citation is live. It tells you that a citation matches what a live
# bridge said on one day, which catches the failure that actually happened: someone writes a
# plausible action name from memory and nothing ever executes it.
#
# The consequence, stated so it is not discovered as a surprise: WHEN THE BRIDGE CHANGES, THIS FILE
# GOES WRONG BEFORE THE PAYLOAD DOES. A genuinely new action reds this guard until someone verifies
# it against a live server and records it here with its date. That cost is the point — it converts
# "I think this action exists" into "this action was executed on <date> against <server>".
#
# WHAT WENT WRONG, AND WHY A NUMBER-FREE ALLOW-LIST IS THE INSTRUMENT. On 2026-08-14 the first
# execution of this toolkit against a live bridge found FOUR of the six lines in
# `unity-optimizer`'s Step 1 — the agent's very first action — naming actions that do not exist:
# `manage_profiler action:"start_session"` (twice), `manage_profiler action:"memory_snapshot"`, and
# `manage_graphics action:"get_rendering_stats"`. The real names are `profiler_start`,
# `memory_take_snapshot` and `stats_get`. `get_frame_timing` and `get_counters`, on the same lines,
# were correct — so the recipe was two-thirds dead and looked entirely plausible.
#
# THE REASON NOBODY NOTICED IS THE FAILURE SHAPE, and it is documented in `unity-mcp-patterns`
# Rule 2: an unknown action returns MCP `isError: false` carrying `"success": false` in the body. A
# caller that branches on the tool-call error flag — the natural thing to do — sees a successful
# call. `read_console` is clean too, because the action never ran.
#
# THE EXTRACTION IS THE HARD PART, NOT THE COMPARISON.
#
# A regex that grabs a tool name and an `action=` from anywhere on the same line produces false
# pairs, and the payload carries four of them today. Every activation preamble has this shape:
#
#     Before your first `run_tests` call: `manage_tools(action="activate", group="testing")`
#
# `activate` belongs to `manage_tools`, not to `run_tests` — but a line-scoped regex attributes it to
# whichever tool token it happens to reach first. Four such lines exist, in `unity-optimizer.md`,
# `unity-test-runner.md`, `unity-fixer.md` and `unity-mcp-patterns/SKILL.md`, and every one of them
# would be reported as a dangling citation by a guard that got this wrong — noise in the first run,
# and a guard whose failures are noise gets switched off.
#
# So attribution is by ADJACENCY, never by proximity: the tool token must sit immediately against
# the action, separated by nothing but the call syntax itself. Four shapes, because the payload
# writes calls four ways and each hides from the others:
#
#   A   manage_profiler action:"get_counters"        pseudo-call in a fenced recipe
#   B   manage_tools(action="activate", group=…)     prose call, the activation preambles
#   C   {"tool": "manage_components", …, "action": "add", …}   a batch_execute JSON element
#   D   `manage_scene` with action "validate"        prose, in a list of what a tool can do
#
# Shape D is deliberately narrow — it requires the literal words `with action` between a backticked
# tool and a quoted action — because prose has no reliable structure and a looser pattern here buys
# false pairs rather than coverage.
#
# WHAT THIS CANNOT SEE, and the list is not short:
#
#   * IT READS `.claude/` ONLY. A dead action cited in `docs/`, in `README.md` or in a plan is green
#     here. The payload is what ships into a user's project and is what an agent reads at run time;
#     that is the scope, and widening it means widening the allow-list to whatever those documents
#     legitimately quote from other server versions.
#   * IT SKIPS `.claude/state/`. Those files are hook output — `bash-gate-denied.txt` records the
#     text of denied commands verbatim — so a maintainer who so much as types a bad citation into a
#     blocked shell command would fail this guard on a file no user ever sees. Runtime output is not
#     a surface. This is a scope decision, not a hole: `.gitignore` carries `.claude/state/*`.
#   * IT CHECKS ACTION NAMES, NOT CALLS, AND THAT GAP HAS ALREADY COST A LINE. This guard has no
#     view of a call's ARGUMENTS, so a citation can name a real action and still be dead. Measured
#     2026-08-14, one round after this file shipped: `manage_profiler action:"get_counters"` — cited
#     in `unity-optimizer`'s recipe with no parameters, and classified "resolves" by the same live
#     sweep that condemned the four dead names beside it — returns `success: false` with an EMPTY
#     message, because `category` is required. The NAME was right and the CALL was dead, and the two
#     verdicts were reported as one. Closing this means recording each tool's parameter schema, which
#     is a far larger snapshot to keep true than a list of action names; it is stated rather than
#     closed. A green run here means "no cited action name is unknown", never "these calls work".
#   * IT CANNOT SEE AN ACTION THAT EXISTS BUT IS WRONG FOR THE JOB. `profiler_stop` where
#     `profiler_start` was meant passes every check here.
#   * IT CANNOT SEE A DEAD TOOL, only a dead action on a tool it knows. A cited tool absent from the
#     snapshot is reported, but as "not recorded" rather than "does not exist" — this guard has no
#     way to tell those apart offline, and says so in the failure message.
#   * THE `manage_graphics` ROW IS A FAMILY, NOT THE TOOL'S WHOLE ACTION SPACE. The live server
#     reported its STATS actions; its other families were not enumerated on the day. A citation of a
#     real `manage_graphics` action outside that family reds here and the fix is to verify it and add
#     it, not to relax the check.
#
# THE FLOORS, and why each one is not the others (see docs/ANTI-VACUITY.md):
#
#   * The comparison below is "no cited pair is outside the allow-list". That claim is SATISFIED BY
#     EMPTINESS — no pairs, no violations, green — so every derivation feeding it is floored.
#   * Per SHAPE (F3), not per union: a union of four sweeps lets two live ones carry a dead one.
#   * Per DECLARED SOURCE (F8), because a derived source list cannot see a deleted source. The three
#     files whose citations are load-bearing are named; the sweep then derives the rest of the tree
#     on top, so a new file with a bad citation is still caught the day it lands.
#   * Both declared arrays carry an ABSOLUTE floor (F4), because every check above is relative to an
#     array a mutation can empty.
#   * The union pair floor is sized against the cheapest plausible narrowing rather than against
#     zero: losing `unity-optimizer`'s profiling fence — the exact regression this guard exists for —
#     drops seven pairs, so the floor sits above that.
#   * The file sweep is floored through THE SAME READER the sweep uses (Shape 3): both are `find`
#     over the working tree, never `git ls-files`, because the extraction opens files from disk.
# ============================================================================

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

FAILURES=0
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'PASS: %s\n' "$1"; }

SNAPSHOT_SERVER="mcp-for-unity-server 3.4.5"
SNAPSHOT_DATE="2026-08-14"

# --- The snapshot. One `tool<TAB>action` row per verified action. -----------------------------
#
# `manage_profiler` is the tool's COMPLETE action list as the server reported it. `manage_graphics`
# is its STATS family only (see the blind-spot list above). Every other row is an action that was
# executed and answered on the day; those tools certainly have more actions than are listed, and
# adding one means verifying it, not guessing it.
ALLOW="manage_profiler	ping
manage_profiler	profiler_start
manage_profiler	profiler_stop
manage_profiler	profiler_status
manage_profiler	profiler_set_areas
manage_profiler	get_frame_timing
manage_profiler	get_counters
manage_profiler	get_object_memory
manage_profiler	memory_take_snapshot
manage_profiler	memory_list_snapshots
manage_profiler	memory_compare_snapshots
manage_profiler	frame_debugger_enable
manage_profiler	frame_debugger_disable
manage_profiler	frame_debugger_get_events
manage_graphics	stats_get
manage_graphics	stats_list_counters
manage_graphics	stats_set_scene_debug
manage_graphics	stats_get_memory
manage_tools	activate
manage_scene	create
manage_scene	validate
manage_gameobject	create
manage_components	add"

# The tools the snapshot claims to cover. Declared rather than derived from ALLOW, so that deleting a
# tool's rows reds by name instead of quietly shrinking the census (F8).
SNAPSHOT_TOOLS="manage_profiler
manage_graphics
manage_tools
manage_scene
manage_gameobject
manage_components"

# --- Declared citing surfaces (F8). The derived sweep below adds whatever else the tree holds. ---
#
# These three are named because their citations are load-bearing: `unity-optimizer` is the recipe
# that was wrong, `unity-scene-builder` carries the only `batch_execute` JSON in the payload, and
# `unity-mcp-patterns` is the reference every other surface points at. A fourth file losing its one
# activation preamble is a smaller loss and is left to the union floor.
CITING_FILES=".claude/agents/unity-optimizer.md
.claude/agents/unity-scene-builder.md
.claude/skills/unity-mcp-patterns/SKILL.md"

# --- Exemptions: a citation written as the DEMONSTRATION of a dead call. ---------------------
#
# `unity-mcp-patterns` Rule 2 shows what an unknown action looks like coming back, and it can only do
# that by writing one. Four tab-separated fields — file, tool, action, and a needle that must appear
# on the citing LINE — so an exemption names one pair on one marked line rather than blessing a file
# or a line wholesale. Every row is audited at the bottom: a row matching nothing is a hole with no
# subject and fails.
EXEMPT=".claude/skills/unity-mcp-patterns/SKILL.md	manage_profiler	start_session	NOT A REAL ACTION — demonstration of the failure shape"

# --- F4: the declared arrays are what every relative check below is measured against. ----------
ALLOW_N="$(printf '%s\n' "$ALLOW" | grep -c . || true)"
TOOLS_N="$(printf '%s\n' "$SNAPSHOT_TOOLS" | grep -c . || true)"
FILES_N="$(printf '%s\n' "$CITING_FILES" | grep -c . || true)"

if [ "$ALLOW_N" -ge 18 ]; then
  pass "the $SNAPSHOT_SERVER snapshot carries $ALLOW_N verified tool/action row(s) (floor 18)"
else
  fail "the snapshot carries only $ALLOW_N tool/action row(s) — expected at least 18; an emptied allow-list makes every comparison below meaningless"
fi

if [ "$TOOLS_N" -ge 6 ]; then
  pass "the snapshot declares $TOOLS_N tool(s) (floor 6)"
else
  fail "the snapshot declares only $TOOLS_N tool(s) — expected at least 6; the per-tool census below is measured against this list and an emptied list passes it trivially"
fi

if [ "$FILES_N" -ge 3 ]; then
  pass "$FILES_N citing surface(s) are declared by name (floor 3)"
else
  fail "only $FILES_N citing surface(s) are declared — expected at least 3; a derived source list cannot see a deleted source, which is what this list exists for"
fi

# --- Every snapshot row belongs to a declared tool, and every declared tool has rows. ----------
#
# An identity in one direction and a presence check in the other. Together they mean the per-tool
# census reads the whole allow-list: a row whose tool is undeclared would be enforced but never
# counted, and a declared tool with no rows would be counted but enforce nothing.
TOOL_BAD=""
TOOL_ROWS=0
while IFS= read -r t; do
  [ -n "$t" ] || continue
  n="$(printf '%s\n' "$ALLOW" | awk -F'\t' -v k="$t" '$1 == k {c++} END {print c+0}')"
  TOOL_ROWS=$((TOOL_ROWS + n))
  [ "$n" -ge 1 ] || TOOL_BAD="${TOOL_BAD}${t}: no action rows in the snapshot"$'\n'
done <<< "$SNAPSHOT_TOOLS"
if [ -n "$TOOL_BAD" ]; then printf '%s' "$TOOL_BAD" | sed 's|^|     |'; fi
if [ -z "$TOOL_BAD" ]; then
  pass "every declared snapshot tool carries at least one verified action"
else
  fail "$(printf '%s' "$TOOL_BAD" | grep -c . || true) declared snapshot tool(s) carry no action — verify against a live bridge and record them, or drop the tool from the declaration"
fi

if [ "$TOOL_ROWS" -eq "$ALLOW_N" ]; then
  pass "the per-tool census read every snapshot row ($TOOL_ROWS of $ALLOW_N)"
else
  fail "the per-tool census read $TOOL_ROWS of $ALLOW_N snapshot rows — some row names a tool the declaration does not carry, so it is enforced without ever being counted"
fi

# --- The sweep. `find` over the working tree, because the extraction opens files from disk. -----
SWEEP_FILES=()
while IFS= read -r -d '' f; do
  SWEEP_FILES+=("$f")
done < <(find .claude -type f -not -path '.claude/state/*' -print0)
SWEPT_N="${#SWEEP_FILES[@]}"

if [ "$SWEPT_N" -ge 30 ]; then
  pass "the citation sweep opened $SWEPT_N payload file(s) (floor 30)"
else
  fail "the citation sweep opened only $SWEPT_N payload file(s) — expected at least 30; a sweep over an empty payload finds no bad citation and reports a clean tree"
fi

# A sweep with no files would leave `awk` reading stdin. Under the runner that is /dev/null and the
# result is a silent green; standalone it hangs. Neither is a test result.
if [ "$SWEPT_N" -eq 0 ]; then
  fail "the citation sweep has no files to read — every assertion below is vacuous"
  printf '%s\n' "mcp citation guard: $FAILURES failure(s)"
  exit 1
fi

# --- Extraction: file, line, shape, tool, action. Attribution is by ADJACENCY. -----------------
EXTRACT='
{
  s = $0

  # Shape A:  TOOL action:"ACT"
  t = s
  while (match(t, /[A-Za-z_][A-Za-z0-9_]*[ \t]+action:"[A-Za-z_][A-Za-z0-9_]*"/)) {
    m = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
    p = index(m, "action:\"")
    tool = substr(m, 1, p - 1); sub(/[ \t]+$/, "", tool)
    act = substr(m, p + 8); sub(/"$/, "", act)
    printf "%s\t%d\tA\t%s\t%s\n", FILENAME, FNR, tool, act
  }

  # Shape B:  TOOL(action="ACT"
  t = s
  while (match(t, /[A-Za-z_][A-Za-z0-9_]*\(action="[A-Za-z_][A-Za-z0-9_]*"/)) {
    m = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
    p = index(m, "(action=\"")
    tool = substr(m, 1, p - 1)
    act = substr(m, p + 9); sub(/"$/, "", act)
    printf "%s\t%d\tB\t%s\t%s\n", FILENAME, FNR, tool, act
  }

  # Shape C:  {"tool": "TOOL", … "action": "ACT"} — one batch element per line, which is how the
  # payload writes them. A batch element split across lines is not matched, and is a known gap.
  if (match(s, /"tool"[ \t]*:[ \t]*"[A-Za-z_][A-Za-z0-9_]*"/)) {
    m = substr(s, RSTART, RLENGTH)
    tool = substr(m, index(m, ":") + 1); gsub(/[ \t"]/, "", tool)
    if (match(s, /"action"[ \t]*:[ \t]*"[A-Za-z_][A-Za-z0-9_]*"/)) {
      m2 = substr(s, RSTART, RLENGTH)
      act = substr(m2, index(m2, ":") + 1); gsub(/[ \t"]/, "", act)
      printf "%s\t%d\tC\t%s\t%s\n", FILENAME, FNR, tool, act
    }
  }

  # Shape D:  `TOOL` with action "ACT"
  t = s
  while (match(t, /`[A-Za-z_][A-Za-z0-9_]*`[ \t]+with[ \t]+action[ \t]+"[A-Za-z_][A-Za-z0-9_]*"/)) {
    m = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
    q = index(substr(m, 2), "`")
    tool = substr(m, 2, q - 1)
    act = substr(m, index(m, "\"") + 1); sub(/"$/, "", act)
    printf "%s\t%d\tD\t%s\t%s\n", FILENAME, FNR, tool, act
  }
}'

PAIRS="$(awk "$EXTRACT" "${SWEEP_FILES[@]}" || true)"
PAIRS_N="$(printf '%s\n' "$PAIRS" | grep -c . || true)"

count_shape() { printf '%s\n' "$PAIRS" | awk -F'\t' -v k="$1" '$3 == k {c++} END {print c+0}'; }
count_file()  { printf '%s\n' "$PAIRS" | awk -F'\t' -v k="$1" '$1 == k {c++} END {print c+0}'; }

# --- Per shape (F3). A union hides a regex that has stopped matching. --------------------------
SHAPE_BAD=""
for sh in A B C D; do
  n="$(count_shape "$sh")"
  [ "$n" -ge 1 ] || SHAPE_BAD="${SHAPE_BAD}shape ${sh} matched nothing"$'\n'
done
if [ -n "$SHAPE_BAD" ]; then printf '%s' "$SHAPE_BAD" | sed 's|^|     |'; fi
if [ -z "$SHAPE_BAD" ]; then
  pass "all four citation shapes matched (A=$(count_shape A), B=$(count_shape B), C=$(count_shape C), D=$(count_shape D))"
else
  fail "a citation shape stopped matching — the extraction is now narrower than this guard claims, and the pairs it no longer sees are unchecked rather than absent"
fi

# --- Per declared source (F8). The file must exist AND the sweep must reach it. ----------------
SRC_BAD=""
while IFS= read -r cf; do
  [ -n "$cf" ] || continue
  if [ ! -f "$cf" ]; then
    SRC_BAD="${SRC_BAD}${cf}: GONE — the file the declaration names does not exist"$'\n'
    continue
  fi
  n="$(count_file "$cf")"
  [ "$n" -ge 1 ] || SRC_BAD="${SRC_BAD}${cf}: present but the sweep extracted no citation from it"$'\n'
done <<< "$CITING_FILES"
if [ -n "$SRC_BAD" ]; then printf '%s' "$SRC_BAD" | sed 's|^|     |'; fi
if [ -z "$SRC_BAD" ]; then
  pass "every declared citing surface exists and still yields at least one citation"
else
  fail "$(printf '%s' "$SRC_BAD" | grep -c . || true) declared citing surface(s) are gone or silent — a deleted source is not a dead source, it is not a source, and the sweep below cannot notice its absence"
fi

# --- The union, sized against the cheapest plausible narrowing. --------------------------------
if [ "$PAIRS_N" -ge 15 ]; then
  pass "the sweep extracted $PAIRS_N tool/action citation(s) from the payload (floor 15)"
else
  fail "the sweep extracted only $PAIRS_N tool/action citation(s) — expected at least 15; losing unity-optimizer's profiling recipe alone drops seven, so this is a narrowing and not a clean tree"
fi

# --- The comparison. -------------------------------------------------------------------------
is_exempt() { # $1=file $2=line $3=tool $4=action
  local f="$1" n="$2" tl="$3" ac="$4" line ef et ea en
  line="$(awk -v k="$n" 'NR == k { print; exit }' "$f")"
  while IFS=$'\t' read -r ef et ea en; do
    [ -n "$ef" ] || continue
    [ "$ef" = "$f" ] || continue
    [ "$et" = "$tl" ] || continue
    [ "$ea" = "$ac" ] || continue
    case "$line" in *"$en"*) return 0 ;; esac
  done <<< "$EXEMPT"
  return 1
}

BAD=""
CHECKED=0
EXEMPTED=""
while IFS=$'\t' read -r cf cl shape tool act; do
  [ -n "$cf" ] || continue
  if is_exempt "$cf" "$cl" "$tool" "$act"; then
    EXEMPTED="${EXEMPTED}${cf}	${tool}	${act}"$'\n'
    continue
  fi
  CHECKED=$((CHECKED + 1))
  if ! grep -qxF -- "$tool" <<< "$SNAPSHOT_TOOLS"; then
    BAD="${BAD}${cf}:${cl} cites ${tool} action:\"${act}\" — ${tool} is not in the ${SNAPSHOT_DATE} snapshot at all, so this guard cannot say whether either name is real"$'\n'
    continue
  fi
  if ! grep -qxF -- "$(printf '%s\t%s' "$tool" "$act")" <<< "$ALLOW"; then
    BAD="${BAD}${cf}:${cl} cites ${tool} action:\"${act}\" — no such action on ${SNAPSHOT_SERVER}"$'\n'
  fi
done <<< "$PAIRS"

if [ "$CHECKED" -ge 15 ]; then
  pass "checked $CHECKED live citation(s) against the snapshot (floor 15)"
else
  fail "checked only $CHECKED live citation(s) — expected at least 15; the exemption table has swallowed the subject"
fi

if [ -n "$BAD" ]; then printf '%s' "$BAD" | sed 's|^|     |'; fi
if [ -z "$BAD" ]; then
  pass "every cited MCP action resolves against the $SNAPSHOT_SERVER snapshot of $SNAPSHOT_DATE"
else
  fail "$(printf '%s' "$BAD" | grep -c . || true) cited MCP action(s) do not resolve — an unknown action answers isError:false with success:false in the body, so nothing at run time will tell the agent"
fi

# --- Every exemption row must still name a citation that exists. -------------------------------
ORPHANED=""
while IFS=$'\t' read -r ef et ea en; do
  [ -n "$ef" ] || continue
  if [ ! -f "$ef" ]; then
    ORPHANED="${ORPHANED}${ef} (file is gone)"$'\n'
  elif ! grep -qxF -- "$(printf '%s\t%s\t%s' "$ef" "$et" "$ea")" <<< "$EXEMPTED"; then
    ORPHANED="${ORPHANED}${ef}: ${et} action:\"${ea}\" is exempted but no such citation was extracted"$'\n'
  fi
done <<< "$EXEMPT"
if [ -n "$ORPHANED" ]; then printf '%s' "$ORPHANED" | sed 's|^|     |'; fi
if [ -z "$ORPHANED" ]; then
  pass "every exemption row still names a citation that exists"
else
  fail "$(printf '%s' "$ORPHANED" | grep -c . || true) exemption row(s) match nothing — delete them rather than leaving a hole with no subject"
fi

if [ "$FAILURES" -gt 0 ]; then
  printf '%s\n' "mcp citation guard: $FAILURES failure(s)"
  exit 1
fi
exit 0
