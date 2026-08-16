#!/usr/bin/env bash
# ============================================================================
# test-codex-surface.sh — guards the shipped Codex CLI payload.
#
# Self-contained: defines its own helpers and sets `set -euo pipefail`, so
# `bash tests/test-codex-surface.sh` is a valid way to run it.
#
# WHAT THIS GUARDS, AND WHY IT IS TWO-DIRECTIONAL.
#
# The Codex payload is decided by `docs/research/codex-client/findings.md`'s
# `## Ship list`, which was written before any payload file existed. A one-way
# check — "everything the ship list names exists" — passes while half the
# payload is missing; the other one-way check — "everything shipped is named" —
# passes while the ship list promises files nobody wrote. Both run here.
#
# THE ANTI-VACUITY FLOORS ARE PLURAL, DELIBERATELY.
#
# An identity over two empty sets passes at 0 == 0. One global "at least N
# files" floor closes that hole for the whole payload at once, which means a
# class can go to zero while another class's growth keeps the total above the
# line. So each derived set carries its OWN floor: tracked Codex files, Codex
# scripts in the install payload, hooks named by the emitted config, and skills
# emitted by the command converter. Deleting any one class reds this file.
#
# THE GENERATED HALVES ARE RUN, NOT READ.
#
# Three of the four payload rows are generators rather than tracked files:
# `--emit-config` derives the Codex hook config, `codex-command-to-skill.sh`
# derives the command skills, and `generate-claude-md.sh --client codex` derives
# the entry document. Asserting on the scripts' source would guard the wrong
# thing, so each is executed and its OUTPUT is asserted. `--emit-config` and the
# generator write to stdout, so neither can create `.codex/` in this repository;
# the converter is given a temp directory, for the same reason.
#
# THE ENTRY-DOCUMENT CHECK IS DIFFERENTIAL, AND THAT IS THE POINT.
#
# "The Codex document does not name the Skill tool" passes vacuously if the
# phrase is deleted from BOTH clients' output. So the same assertion pair checks
# that the DEFAULT (Claude Code) document still names it. What is asserted is
# the swap, not an absence.
# ============================================================================
set -euo pipefail

# ${BASH_SOURCE[0]}, not $0: the runner does `( source "$test_file" )`, and inside
# a sourced file $0 is the sourcing shell's $0.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SHIP_LIST="docs/research/codex-client/findings.md"

# ---------------------------------------------------------------------------
# 0. The ship list itself
# ---------------------------------------------------------------------------
echo "--- codex surface: the ship list ---"

if [ -f "$SHIP_LIST" ]; then
  ok "the ship list's home exists: $SHIP_LIST"
else
  bad "$SHIP_LIST is missing — the ship list is a section of it, and every check below reads it"
fi

# The section, not the whole file: findings.md discusses paths it does NOT ship
# (`.codex/agents/*.toml`, the importer's tree), and matching those as ship-list
# entries would let an excluded surface satisfy this guard.
SHIP_SECTION=""
if [ -f "$SHIP_LIST" ]; then
  SHIP_SECTION="$(awk '/^## Ship list$/{p=1} p' "$SHIP_LIST")"
fi
SHIP_SECTION_LINES="$(printf '%s\n' "$SHIP_SECTION" | /usr/bin/grep -c . || true)"

if [ "$SHIP_SECTION_LINES" -ge 20 ]; then
  ok "the ship list section is present and substantive ($SHIP_SECTION_LINES lines)"
else
  bad "no usable '## Ship list' section in $SHIP_LIST (found $SHIP_SECTION_LINES lines) — Task 8 writes it before the payload"
fi

# An excluded surface must be named as excluded, not merely omitted. A class
# dropped silently is indistinguishable from a class forgotten.
for phrase in "Excluded, each with its measurement" "Open, not answered"; do
  if /usr/bin/grep -qF -- "$phrase" <<< "$SHIP_SECTION"; then
    ok "the ship list carries its '$phrase' section"
  else
    bad "the ship list has no '$phrase' section — an exclusion that is not written down is a surface that was forgotten"
  fi
done

# ---------------------------------------------------------------------------
# 1. The tracked Codex surface, derived — and its floor
# ---------------------------------------------------------------------------
echo "--- codex surface: tracked payload ---"

CODEX_TRACKED="$(git ls-files 'AGENTS.md' '.codex/*' '.agents/*' 2>/dev/null || true)"
CODEX_TRACKED_N="$(printf '%s\n' "$CODEX_TRACKED" | /usr/bin/grep -c . || true)"

if [ "$CODEX_TRACKED_N" -ge 1 ]; then
  ok "the tracked Codex payload is non-empty ($CODEX_TRACKED_N file(s)) — this guard is not passing vacuously"
else
  bad "no tracked Codex payload found — with an empty set every identity below passes at 0 == 0"
fi

while IFS= read -r f; do
  [ -n "$f" ] || continue
  if /usr/bin/grep -qF -- "$f" <<< "$SHIP_SECTION"; then
    ok "tracked Codex file is named in the ship list: $f"
  else
    bad "tracked Codex file is absent from the ship list: $f"
  fi
done <<< "$CODEX_TRACKED"

# `.codex/` must NOT be tracked: the hook config's command strings carry absolute
# paths to this machine, so a committed copy is one developer's paths frozen into
# everyone's checkout. provenance-skip.tsv carries the prohibition; this asserts
# the tree agrees with it.
CODEX_DIR_TRACKED="$(git ls-files '.codex/*' 2>/dev/null | /usr/bin/grep -c . || true)"
if [ "$CODEX_DIR_TRACKED" -eq 0 ]; then
  ok ".codex/ is not tracked — the hook config is generated, because its command strings are absolute paths"
else
  bad "$CODEX_DIR_TRACKED file(s) tracked under .codex/ — that config must be generated by --emit-config, never committed"
fi

# ---------------------------------------------------------------------------
# 2. The Codex scripts in the install payload — and its floor
# ---------------------------------------------------------------------------
echo "--- codex surface: installed scripts ---"

# Derived the way install.sh derives it, by the same one-name-per-line comparison
# shape tests/test-derived-counts.sh and tests/test-shipped-citations.sh read.
# Hardcoding the skip list here would go stale the first time it changed.
INSTALL_SKIP="$(/usr/bin/grep -oE '\[ "\$b" = "[^"]+" \] && continue' install.sh \
  | sed -E 's/.*= "([^"]+)".*/\1/' | sort -u || true)"
INSTALL_SKIP_N="$(printf '%s\n' "$INSTALL_SKIP" | /usr/bin/grep -c . || true)"

if [ "$INSTALL_SKIP_N" -ge 1 ]; then
  ok "install.sh's script-skip list was extracted ($INSTALL_SKIP_N name(s)) — the payload derivation is reading the installer"
else
  bad "install.sh's script-skip pattern matched nothing — the installed-script derivation below would be guessing"
fi

CODEX_SCRIPTS=""
CODEX_SCRIPTS_N=0
for f in scripts/codex-*.sh; do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  if /usr/bin/grep -qxF -- "$b" <<< "$INSTALL_SKIP"; then continue; fi
  CODEX_SCRIPTS="${CODEX_SCRIPTS}${b}
"
  CODEX_SCRIPTS_N=$((CODEX_SCRIPTS_N + 1))
done

if [ "$CODEX_SCRIPTS_N" -ge 2 ]; then
  ok "the install payload carries $CODEX_SCRIPTS_N Codex script(s) — the hook shim and the command converter"
else
  bad "the install payload carries only $CODEX_SCRIPTS_N Codex script(s); the ship list requires two — codex-hook-shim.sh (the hooks' translation) and codex-command-to-skill.sh (the command conversion). A script excluded in install.sh reaches no user project"
fi

while IFS= read -r b; do
  [ -n "$b" ] || continue
  # Named in the ship list, by the path it has once installed AND by its repo path.
  if /usr/bin/grep -qF -- "scripts/$b" <<< "$SHIP_SECTION"; then
    ok "installed Codex script is named in the ship list: $b"
  else
    bad "installed Codex script is absent from the ship list: $b"
  fi
  # Reachable: some shipped surface must name it, or a model never finds it.
  if /usr/bin/grep -rqF -- ".claude/scripts/$b" .claude --include='*.md'; then
    ok "a shipped surface names .claude/scripts/$b"
  else
    bad "no agent, command or skill names .claude/scripts/$b — it installs into every project and nothing routes to it"
  fi
done <<< "$CODEX_SCRIPTS"

# ---------------------------------------------------------------------------
# 3. Reverse direction: every repo path the ship list names exists
# ---------------------------------------------------------------------------
echo "--- codex surface: the ship list's own paths resolve ---"

# Only repository-relative tokens. The ship list also names per-project paths
# (`<project>/.agents/skills/...`) which by construction do not exist here.
SHIP_PATHS="$(printf '%s\n' "$SHIP_SECTION" \
  | /usr/bin/grep -oE '`(scripts|tests)/[A-Za-z0-9_./-]+\.sh`' \
  | tr -d '`' | sort -u || true)"
SHIP_PATHS_N="$(printf '%s\n' "$SHIP_PATHS" | /usr/bin/grep -c . || true)"

if [ "$SHIP_PATHS_N" -ge 3 ]; then
  ok "the ship list names $SHIP_PATHS_N repository script/test path(s) — enough to check the reverse direction"
else
  bad "the ship list names only $SHIP_PATHS_N repository script/test path(s); the reverse-direction check would be near-vacuous"
fi

while IFS= read -r p; do
  [ -n "$p" ] || continue
  if [ -f "$p" ]; then
    ok "ship-list path exists: $p"
  else
    bad "ship-list path does not exist: $p — the list promises a file nobody wrote"
  fi
done <<< "$SHIP_PATHS"

# ---------------------------------------------------------------------------
# 4. The generated Codex hook config
#
# GENERATED TWICE, AGAINST TWO PROJECT LAYOUTS, AND THE SECOND IS THE ONE THAT
# MATTERS. `--emit-config` picks the shim path it writes into every command
# string by preferring `<project>/.claude/scripts/codex-hook-shim.sh` and falling
# back to the toolkit clone it was invoked from. Generated against THIS
# repository only the fallback branch is ever taken, because this repository has
# no `.claude/scripts/` — so the branch that carries this task's whole reason for
# shipping the shim would never be exercised. It was not, in the first version of
# this file: a mutation deleting the in-project preference emitted a path outside
# the project and this guard stayed green at 72/72.
#
# A path outside the project is not a broken config that errors. Per `## Hooks`
# in findings.md, a hook command Codex cannot run is a silent ALLOW. So the
# assertion is not "the string mentions the shim" — both branches satisfy that —
# it is "the path exists AND lies under the project root it was generated for".
# ---------------------------------------------------------------------------
echo "--- codex surface: the generated hook config ---"

# A real install, because the installed layout is the layout users run. 0.7 s.
INSTFIX="$WORK/instfix"
INSTFIX_OK=0
if bash tests/fixtures/mkproject.sh "$INSTFIX" --variant urp >/dev/null 2>&1 \
   && bash install.sh --project-dir "$INSTFIX" --yes >/dev/null 2>&1; then
  ok "built a real fixture install to exercise the installed layout"
  INSTFIX_OK=1
else
  bad "could not build a fixture install — the installed-layout assertions below cannot run"
fi

# --emit-config writes to STDOUT and reads only .claude/settings.json, so neither
# run creates anything in this repository.
HCFG="$WORK/hooks.json"
if bash scripts/codex-hook-shim.sh --emit-config --project-dir "$REPO_DIR" > "$HCFG" 2>"$WORK/emit.err"; then
  ok "codex-hook-shim.sh --emit-config succeeds against this repository"
else
  bad "codex-hook-shim.sh --emit-config failed: $(cat "$WORK/emit.err" 2>/dev/null | tr '\n' ' ')"
fi

# The installed-layout arm, driven from the REPO copy of the shim with the
# fixture as --project-dir. That is the shape Task 9's installer has and the one
# in which the in-project preference is the only thing keeping the emitted path
# inside the project.
HCFG_INST="$WORK/hooks-installed.json"
HCFG_INST_OK=0
if [ "$INSTFIX_OK" -eq 1 ] \
   && bash scripts/codex-hook-shim.sh --emit-config --project-dir "$INSTFIX" > "$HCFG_INST" 2>"$WORK/emit-inst.err"; then
  ok "--emit-config succeeds against an installed project"
  HCFG_INST_OK=1
elif [ "$INSTFIX_OK" -eq 1 ]; then
  bad "--emit-config failed against an installed project: $(cat "$WORK/emit-inst.err" 2>/dev/null | tr '\n' ' ')"
fi

# Every path a command string carries — the shim and the hook alike — must exist
# and sit under the project the config was generated for. Checked on BOTH arms:
# the repo arm pins the fallback branch, the installed arm pins the preference.
check_paths_inside() {   # $1 = config, $2 = project root, $3 = label
  [ -f "$1" ] || return 0
  cpi_bad="$(PROJ="$2" python3 - "$1" <<'PY'
import json, os, re, sys
root = os.path.realpath(os.environ["PROJ"])
cfg = json.load(open(sys.argv[1])).get("hooks", {})
problems, seen = [], 0
for event, groups in cfg.items():
    for group in groups:
        for hook in group.get("hooks", []):
            for path in re.findall(r"'([^']+)'", hook.get("command", "")):
                seen += 1
                if not os.path.isfile(path):
                    problems.append("%s: does not exist: %s" % (event, path))
                    continue
                real = os.path.realpath(path)
                if real != root and not real.startswith(root + os.sep):
                    problems.append("%s: outside the project: %s" % (event, path))
if not seen:
    problems.append("no quoted path found in any command string")
print("\n".join(problems))
PY
)"
  if [ -z "$cpi_bad" ]; then
    ok "every path the emitted config names exists and lies under the project root ($3)"
  else
    bad "emitted config names path(s) outside the project or absent ($3) — under Codex a hook command that cannot run is a silent allow, not an error: $cpi_bad"
  fi
}
check_paths_inside "$HCFG" "$REPO_DIR" "repo layout"
[ "$HCFG_INST_OK" -eq 1 ] && check_paths_inside "$HCFG_INST" "$INSTFIX" "installed layout"

# The installed arm additionally pins WHICH copy was chosen. "Inside the project"
# is the invariant; "the project's own .claude/scripts/ copy" is the decision,
# and it is the one that makes copying scripts/ before generating the config a
# hard ordering constraint rather than a preference.
if [ "$HCFG_INST_OK" -eq 1 ]; then
  INST_SHIMS="$(python3 - "$HCFG_INST" <<'PY'
import json, re, sys
cfg = json.load(open(sys.argv[1])).get("hooks", {})
found = set()
for groups in cfg.values():
    for group in groups:
        for hook in group.get("hooks", []):
            for path in re.findall(r"'([^']+)'", hook.get("command", "")):
                if path.endswith("codex-hook-shim.sh"):
                    found.add(path)
print("\n".join(sorted(found)))
PY
)"
  if [ "$INST_SHIMS" = "$INSTFIX/.claude/scripts/codex-hook-shim.sh" ]; then
    ok "the installed layout's config points at the project's own shim copy"
  else
    bad "the installed layout's config points at [$INST_SHIMS], not $INSTFIX/.claude/scripts/codex-hook-shim.sh — the toolkit clone is a directory the user is under no obligation to keep"
  fi
fi

# --- the hook set is an IDENTITY against settings.json, not a floor -----------
# A floor of >= 1 let a mutation that emitted only PreToolUse drop 12 entries to
# 5 and stay green at 65/65: seven hooks silently unregistered, and the whole
# assertion total quietly seven smaller. The command section one screen down
# already asserts exactly this identity (`EMITTED_N -eq CMD_N`); the asymmetry
# was the defect. Compared as SETS and per-event COUNTS, not as one total, so a
# hook swapped for another cannot net out.
#
# WHAT THIS IDENTITY DOES NOT CHECK, AND THE OPTION NOT TAKEN. Event names are
# passed through from settings.json unvalidated, and Codex's `HookEventName` enum
# has 11 members against the four in use. This identity narrows that to a
# reviewed edit — an unknown event can no longer arrive through generator drift,
# only by someone adding one to settings.json — but such an edit still emits a
# key Codex answers with a parse warning. Not checked here for two reasons and
# ONE non-reason: deriving the enum needs `codex app-server generate-json-schema`
# (a binary the other 43 test files do not require), and hardcoding the 11
# members is the stale-list-inside-a-guard failure CLAUDE.md names. The
# non-reason is "so it cannot be checked at all": this suite already skips with a
# stated reason — tests/test-codex-shim.sh's %N clock probe does exactly that —
# so a check that derives the enum WHEN `codex` is on PATH and skips otherwise
# adds no dependency and hardcodes nothing. That is a real third option; it is
# left undone because the residual is one reviewed edit wide, not because it is
# unavailable. Recorded so the next reader inherits the option rather than the
# false dichotomy.
SETTINGS_HOOKS="$(python3 - "$REPO_DIR/.claude/settings.json" <<'PY'
import json, os, sys
cfg = json.load(open(sys.argv[1])).get("hooks", {})
rows = []
for event, groups in cfg.items():
    for group in groups:
        for hook in group.get("hooks", []):
            rows.append("%s\t%s" % (event, os.path.basename(hook.get("command", ""))))
print("\n".join(sorted(rows)))
PY
)"
EMITTED_HOOKS="$(python3 - "$HCFG" <<'PY'
import json, os, re, sys
cfg = json.load(open(sys.argv[1])).get("hooks", {})
rows = []
for event, groups in cfg.items():
    for group in groups:
        for hook in group.get("hooks", []):
            cmd = hook.get("command", "")
            paths = re.findall(r"'([^']+)'", cmd)
            # The wrapped form is '<shim>' --hook '<hook>'; the unwrapped form is
            # just '<hook>'. The hook is the last quoted path either way.
            rows.append("%s\t%s" % (event, os.path.basename(paths[-1]) if paths else "?"))
print("\n".join(sorted(rows)))
PY
)"
SETTINGS_N="$(printf '%s\n' "$SETTINGS_HOOKS" | /usr/bin/grep -c . || true)"
EMITTED_N_HOOKS="$(printf '%s\n' "$EMITTED_HOOKS" | /usr/bin/grep -c . || true)"

if [ "$SETTINGS_N" -ge 1 ]; then
  ok ".claude/settings.json registers $SETTINGS_N hook entr(ies) for the identity below to be an identity over"
else
  bad ".claude/settings.json registers no hook entries — the identity below would hold vacuously"
fi

if [ "$EMITTED_HOOKS" = "$SETTINGS_HOOKS" ]; then
  ok "the emitted config is the whole of .claude/settings.json's hook set, event for event ($EMITTED_N_HOOKS entries)"
else
  bad "the emitted config is not settings.json's hook set: $EMITTED_N_HOOKS emitted against $SETTINGS_N registered. A hook that Claude Code enforces and Codex never registers is not an error a user sees — it is a gate that is simply absent. Missing: $(comm -23 <(printf '%s\n' "$SETTINGS_HOOKS") <(printf '%s\n' "$EMITTED_HOOKS") | tr '\n' ' ')"
fi

if [ -s "$HCFG" ] && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$HCFG" 2>/dev/null; then
  ok "the emitted Codex hook config is valid JSON"

  # The top level is the `hooks` wrapper. Codex rejects a bare event map with
  # `unknown field PreToolUse, expected description or hooks` — measured, and it
  # is the one shape a hand-written file gets wrong.
  TOPKEYS="$(python3 -c 'import json,sys; print(" ".join(sorted(json.load(open(sys.argv[1])).keys())))' "$HCFG")"
  if [ "$TOPKEYS" = "hooks" ]; then
    ok "the emitted config's top level is the hooks wrapper, not the bare event map Codex rejects"
  else
    bad "the emitted config's top-level keys are '$TOPKEYS' — Codex accepts only 'hooks' (and an optional 'description'); a bare event map is refused with a parse warning"
  fi

  NAMED_HOOKS="$(python3 - "$HCFG" <<'PY'
import json, re, sys
blob = json.dumps(json.load(open(sys.argv[1])))
print('\n'.join(sorted(set(re.findall(r'hooks/([A-Za-z0-9_-]+)\.sh', blob)))))
PY
)"
  NAMED_N="$(printf '%s\n' "$NAMED_HOOKS" | /usr/bin/grep -c . || true)"

  if [ "$NAMED_N" -ge 1 ]; then
    ok "the emitted Codex hook config names $NAMED_N hook(s)"
  else
    bad "the emitted Codex hook config names no hooks — it would register a payload that guards nothing"
  fi

  while IFS= read -r h; do
    [ -n "$h" ] || continue
    if [ -f ".claude/hooks/$h.sh" ]; then
      ok "Codex-registered hook resolves: $h"
    else
      bad "Codex-registered hook does not exist: .claude/hooks/$h.sh"
    fi
  done <<< "$NAMED_HOOKS"

  # Every tool event must route through the shim. A tool-event entry pointing
  # straight at a hook is the measured failure: it registers, it fires, and it
  # reads a patch envelope none of the hooks can parse.
  UNWRAPPED="$(python3 - "$HCFG" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))["hooks"]
bad = []
for event, groups in cfg.items():
    if event not in ("PreToolUse", "PostToolUse"):
        continue
    for group in groups:
        for hook in group.get("hooks", []):
            if "codex-hook-shim.sh" not in hook.get("command", ""):
                bad.append(event + ":" + hook.get("command", "")[:60])
print("\n".join(bad))
PY
)"
  if [ -z "$UNWRAPPED" ]; then
    ok "every tool-event entry in the emitted config routes through codex-hook-shim.sh"
  else
    bad "tool-event entries bypass the shim and would read a patch envelope they cannot parse: $UNWRAPPED"
  fi

  # The unit conversion, and the ORDER of the two ceilings. Codex reads seconds;
  # settings.json declares milliseconds. Unconverted, `timeout: 3000` is fifty
  # minutes. And the shim's own budget must be strictly BELOW Codex's, or Codex
  # kills the shim from outside — which is a silent allow.
  TIMEOUT_BAD="$(python3 - "$HCFG" <<'PY'
import json, re, sys
cfg = json.load(open(sys.argv[1]))["hooks"]
bad = []
for event, groups in cfg.items():
    for group in groups:
        for hook in group.get("hooks", []):
            t = hook.get("timeout")
            cmd = hook.get("command", "")
            if not isinstance(t, int) or t <= 0 or t > 120:
                bad.append("%s timeout=%r is not a converted second-scale value" % (event, t))
                continue
            m = re.search(r'--timeout\s+(\d+)', cmd)
            if m and int(m.group(1)) >= t:
                bad.append("%s shim budget %s is not below Codex's %s" % (event, m.group(1), t))
print("\n".join(bad))
PY
)"
  if [ -z "$TIMEOUT_BAD" ]; then
    ok "every emitted timeout is second-scale, and every shim budget is strictly below Codex's ceiling"
  else
    bad "emitted timeout defects: $TIMEOUT_BAD"
  fi
else
  bad "the emitted Codex hook config is empty or not valid JSON"
fi

# ---------------------------------------------------------------------------
# 5. The generated command skills
# ---------------------------------------------------------------------------
echo "--- codex surface: commands converted to skills ---"

CMD_N="$(ls -1 .claude/commands/*.md 2>/dev/null | /usr/bin/grep -c . || true)"
SKILLDIR="$WORK/agentskills"

if [ ! -x scripts/codex-command-to-skill.sh ] && [ ! -f scripts/codex-command-to-skill.sh ]; then
  bad "scripts/codex-command-to-skill.sh does not exist — the ship list converts commands to skills, because the importer drops 7 of 9 silently and the Kinglet path would otherwise drop 9 of 9"
else
  if bash scripts/codex-command-to-skill.sh --project-dir "$REPO_DIR" --out "$SKILLDIR" >"$WORK/conv.out" 2>&1; then
    ok "codex-command-to-skill.sh succeeds against this repository's commands"
  else
    bad "codex-command-to-skill.sh failed: $(tail -3 "$WORK/conv.out" | tr '\n' ' ')"
  fi

  # --- THE DEFAULT ROOT, run exactly as the shipped documentation prescribes ---
  # Every assertion in this section passes --out explicitly, so the default root
  # was the one invocation form the guard never exercised — while being the only
  # form anything shipped actually prescribes: `.claude/commands/unity-doctor.md`
  # Check 3b step 4 tells the user to run the script with no arguments at all,
  # and Task 9's installer will do the same. A mutation changing the default from
  # `.agents/skills` to a root Codex was measured NOT to read left this guard
  # green at 72/72.
  #
  # Run from inside the installed fixture with NO arguments, so this also pins
  # the installed-layout project-dir resolution (<project>/.claude/scripts/ ->
  # <project>) rather than only the default's spelling.
  if [ "$INSTFIX_OK" -eq 1 ]; then
    if ( cd "$INSTFIX" && bash .claude/scripts/codex-command-to-skill.sh ) >"$WORK/conv-default.out" 2>&1; then
      ok "the converter runs with no arguments from inside an installed project, as Check 3b prescribes"
    else
      bad "the converter failed with no arguments from an installed project: $(tail -3 "$WORK/conv-default.out" | tr '\n' ' ')"
    fi

    DEF_MISSING=""
    DEF_SEEN=0
    for c in .claude/commands/*.md; do
      [ -f "$c" ] || continue
      n="$(basename "$c" .md)"
      DEF_SEEN=$((DEF_SEEN + 1))
      [ -f "$INSTFIX/.agents/skills/$n/SKILL.md" ] || DEF_MISSING="$DEF_MISSING $n"
    done
    if [ "$DEF_SEEN" -ge 1 ] && [ -z "$DEF_MISSING" ]; then
      ok "the default root is .agents/skills/ — all $DEF_SEEN converted command(s) landed where Codex reads"
    else
      bad "the converter's DEFAULT root is not <project>/.agents/skills/ (missing:$DEF_MISSING). Measured: .claude/skills/ unaided discovers 0 skills, and any other root is discovered the same way — the files exist and Codex never sees them"
    fi
  fi

  EMITTED_N="$(ls -1d "$SKILLDIR"/*/ 2>/dev/null | /usr/bin/grep -c . || true)"
  if [ "$EMITTED_N" -ge 1 ]; then
    ok "the converter emitted $EMITTED_N skill(s)"
  else
    bad "the converter emitted no skills — every assertion below it would pass over an empty set"
  fi

  # Forward: every command becomes a skill.
  for c in .claude/commands/*.md; do
    [ -f "$c" ] || continue
    n="$(basename "$c" .md)"
    if [ -f "$SKILLDIR/$n/SKILL.md" ]; then
      ok "command crossed to Codex as a skill: $n"
    else
      bad "command did not cross: $n — no $SKILLDIR/$n/SKILL.md"
    fi
  done

  # Reverse: every emitted skill traces back to a command.
  for d in "$SKILLDIR"/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    if [ -f ".claude/commands/$n.md" ]; then
      ok "emitted skill traces back to a command: $n"
    else
      bad "emitted skill $n has no .claude/commands/$n.md behind it"
    fi
  done

  if [ "$EMITTED_N" -eq "$CMD_N" ]; then
    ok "the converted set is the whole command set ($CMD_N)"
  else
    bad "converted $EMITTED_N of $CMD_N commands"
  fi

  # Frontmatter: `name` must match the directory and `description` must be
  # non-empty — the same two rules tests/test-skill-discovery.sh enforces for
  # Claude Code, because `description` is the entire selection mechanism.
  FM_BAD=""
  for d in "$SKILLDIR"/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    s="$d/SKILL.md"
    [ -f "$s" ] || { FM_BAD="$FM_BAD $n(no-SKILL.md)"; continue; }
    got_name="$(awk 'NR>1 && /^---$/{exit} /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' "$s")"
    got_desc="$(awk 'NR>1 && /^---$/{exit} /^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$s")"
    [ "$got_name" = "$n" ] || FM_BAD="$FM_BAD $n(name=$got_name)"
    [ -n "$got_desc" ] || FM_BAD="$FM_BAD $n(no-description)"
  done
  if [ -z "$FM_BAD" ]; then
    ok "every emitted skill's name matches its directory and carries a non-empty description"
  else
    bad "emitted skill frontmatter defects:$FM_BAD"
  fi

  # No name may collide with a real skill: the two would occupy one directory in
  # the .agents/skills root, and the generated one would shadow the symlink.
  COLLIDE=""
  for d in "$SKILLDIR"/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    [ -d ".claude/skills/$n" ] && COLLIDE="$COLLIDE $n"
  done
  if [ -z "$COLLIDE" ]; then
    ok "no converted command collides with a skill name in the shared .agents/skills root"
  else
    bad "converted command(s) collide with real skills and would shadow their symlinks:$COLLIDE"
  fi

  # The argument placeholder must be gone. Two reasons, and the second is the
  # one that bites on the Kinglet path: a `$ARGUMENTS` token drops the file
  # silently if the user ever ALSO runs Codex's importer, and a skill has no
  # argument substitution at all, so the token reaches the model as literal text
  # naming a mechanism that does not exist.
  ARG_BAD=""
  for d in "$SKILLDIR"/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    if /usr/bin/grep -qE '\$ARGUMENTS|\$[0-9]' "$d/SKILL.md"; then
      ARG_BAD="$ARG_BAD $n"
    fi
  done
  if [ -z "$ARG_BAD" ]; then
    ok "no emitted skill carries an argument placeholder"
  else
    bad "emitted skill(s) still carry an argument placeholder:$ARG_BAD"
  fi

  # The control for the assertion above: the SOURCE commands do carry the token,
  # so "none in the output" is a strip that happened rather than a property of a
  # tree that never had one.
  SRC_WITH_ARGS="$(/usr/bin/grep -lE '\$ARGUMENTS|\$[0-9]' .claude/commands/*.md 2>/dev/null | /usr/bin/grep -c . || true)"
  if [ "$SRC_WITH_ARGS" -ge 1 ]; then
    ok "control: $SRC_WITH_ARGS source command(s) do carry an argument placeholder, so the strip above is doing work"
  else
    bad "no source command carries an argument placeholder — the strip assertion above cannot fail and is guarding nothing"
  fi
fi

# ---------------------------------------------------------------------------
# 6. The generated Codex entry document
# ---------------------------------------------------------------------------
echo "--- codex surface: the entry document ---"

FIX="$WORK/fixture"
if bash tests/fixtures/mkproject.sh "$FIX" --variant urp >/dev/null 2>&1; then
  ok "built a fixture Unity project to generate both entry documents against"
else
  bad "could not build the fixture Unity project — the entry-document checks below cannot run"
fi

DOC_CODEX="$WORK/AGENTS.md"
DOC_CLAUDE="$WORK/CLAUDE.md"
GEN_OK=0
if bash scripts/generate-claude-md.sh --client codex "$FIX" > "$DOC_CODEX" 2>/dev/null; then
  ok "generate-claude-md.sh --client codex emits a document"
  GEN_OK=1
else
  bad "generate-claude-md.sh --client codex failed — the ship list makes it the only source of AGENTS.md, because the importer's copy carries dead .Codex/rules/ references into a document Codex injects whole"
fi
bash scripts/generate-claude-md.sh "$FIX" > "$DOC_CLAUDE" 2>/dev/null || true

if [ "$GEN_OK" -eq 1 ] && [ -s "$DOC_CODEX" ] && [ -s "$DOC_CLAUDE" ]; then
  # The rules pointer is load-bearing and measured: without it `.claude/rules/`
  # was opened 0 times in 24 runs, and the control did not degrade to "no
  # conventions" but to confidently wrong ones.
  if /usr/bin/grep -qF -- '.claude/rules/' "$DOC_CODEX"; then
    ok "the Codex entry document keeps the declarative rules pointer"
  else
    bad "the Codex entry document has no .claude/rules/ pointer — measured: without it the rules directory was opened 0 times in 24 runs"
  fi

  # The inlined digest. Measured: a pointer is followed 1 time in 12 under a
  # conventions-blind request, while the same rule inlined binds 12 of 12.
  DIGEST_MISSING=""
  for token in '_lowerCamelCase' 'FormerlySerializedAs' 'Camera.main'; do
    /usr/bin/grep -qF -- "$token" "$DOC_CODEX" || DIGEST_MISSING="$DIGEST_MISSING $token"
  done
  if [ -z "$DIGEST_MISSING" ]; then
    ok "the Codex entry document keeps the inlined conventions digest"
  else
    bad "the Codex entry document dropped digest content:$DIGEST_MISSING"
  fi

  # The non-negotiables that no hook covers. Derived membership, not a list
  # someone remembered: the five rules' NON-NEGOTIABLE/CRITICAL sections less the
  # one the digest carries (FormerlySerializedAs) and the one a hook enforces
  # (legacy Input), plus the editor-guard rule that is neither. An earlier version
  # of findings.md claimed all of these were hook-enforced; the only UNITY_EDITOR
  # occurrence in .claude/hooks/ is an EXEMPTION in block-legacy-input.sh, not a
  # check, so nothing was covering four of them.
  # ONE token list, used for both directions below, so the two can never drift
  # into checking different things.
  NN_TOKENS='ServiceLocator
Minimum visibility
PlayerControls
MaterialPropertyBlock
UNITY_EDITOR'
  NN_MISSING=""
  NN_SEEN=0
  while IFS= read -r token; do
    [ -n "$token" ] || continue
    NN_SEEN=$((NN_SEEN + 1))
    /usr/bin/grep -qF -- "$token" "$DOC_CODEX" || NN_MISSING="$NN_MISSING $token"
  done <<< "$NN_TOKENS"
  if [ "$NN_SEEN" -ge 5 ] && [ -z "$NN_MISSING" ]; then
    ok "the Codex entry document inlines all $NN_SEEN non-negotiables that no hook covers"
  else
    bad "the Codex entry document is missing inlined non-negotiable(s):$NN_MISSING — measured: a pointed-at rule is followed 1 time in 12 under a conventions-blind request while the same rule inlined binds 12 of 12, and no hook checks any of these"
  fi

  # And they are inlined for Codex ONLY. Nothing in this wave measured Claude
  # Code's rule reachability, so the shipping client's document is left alone;
  # this pins that as a decision rather than an oversight, and it fails loudly if
  # someone later inlines into both without measuring the other client.
  #
  # THE CONTENT, NOT THE HEADING. This matched the literal heading string until
  # 2026-08-16, which caught only a maintainer who copied the heading verbatim —
  # and that is not the failure mode. Someone persuaded the rules belong in both
  # documents writes their own heading: measured, the same five rules inlined
  # under `## Rules that no gate checks` grew the Claude document from 4870 to
  # 5250 bytes with every token present, and this assertion stayed green. It is
  # the same token list the forward direction uses, so the two cannot disagree.
  NN_LEAKED=""
  while IFS= read -r token; do
    [ -n "$token" ] || continue
    ! /usr/bin/grep -qF -- "$token" "$DOC_CLAUDE" || NN_LEAKED="$NN_LEAKED $token"
  done <<< "$NN_TOKENS"
  if [ -z "$NN_LEAKED" ]; then
    ok "the inlined non-negotiables are Codex-only — none of the $NN_SEEN appears in the Claude Code document"
  else
    bad "the Claude Code entry document has grown the Codex-only inlined content:$NN_LEAKED — every pointer rate behind that decision was measured under Codex, so inlining here is the substitution this wave exists to avoid. Measure Claude Code's rule reachability first, and change this assertion deliberately rather than around it"
  fi

  # The skill root. Codex reads `.agents/skills/`; `.claude/skills/` unaided
  # gives it zero skills.
  if /usr/bin/grep -qF -- '.agents/skills' "$DOC_CODEX"; then
    ok "the Codex entry document names the .agents/skills root Codex actually reads"
  else
    bad "the Codex entry document does not name .agents/skills — measured: .claude/skills/ unaided discovers 0 skills"
  fi

  # THE DIFFERENTIAL. Codex has no skill tool: ThreadItem carries no skill item,
  # and a skill is loaded by the model reading its SKILL.md with the shell tool.
  # Asserting only the absence would pass if the phrase were deleted from both
  # documents, so the Claude Code half is asserted as still present.
  if /usr/bin/grep -qF -- '`Skill` tool' "$DOC_CLAUDE"; then
    ok "control: the default (Claude Code) entry document still names the Skill tool"
  else
    bad "the default entry document no longer names the Skill tool — the swap assertion below would then pass vacuously"
  fi
  if /usr/bin/grep -qF -- '`Skill` tool' "$DOC_CODEX"; then
    bad "the Codex entry document names the Skill tool — Codex has none, and this document is injected whole into every turn"
  else
    ok "the Codex entry document names no Skill tool"
  fi

  # Slash commands do not exist in codex-cli 0.145.0 — 24 subcommands, none a
  # prompt registry — so the document must not present one as invocable.
  if /usr/bin/grep -qE '(^|[^a-zA-Z0-9`])/unity-[a-z]+' "$DOC_CODEX"; then
    bad "the Codex entry document offers a slash command; codex-cli 0.145.0 has no command surface, and the ship list converts commands to skills instead"
  else
    ok "the Codex entry document offers no slash command"
  fi

  # The second client must be named as such, and the open question must travel
  # with it. Task 7 has not run: nothing measured whether the MCP routes behave
  # under Codex.
  if /usr/bin/grep -qiF -- 'codex' "$DOC_CODEX"; then
    ok "the Codex entry document names its client"
  else
    bad "the Codex entry document never names Codex — a reader cannot tell which client's guarantees apply"
  fi
  if /usr/bin/grep -qiE 'unmeasured|not been measured|not measured' "$DOC_CODEX"; then
    ok "the Codex entry document marks at least one question open rather than claiming parity"
  else
    bad "the Codex entry document claims no open question; MCP route behaviour under Codex is unmeasured and must be stated, not assumed"
  fi
fi

# ---------------------------------------------------------------------------
# 7. The prohibitions are recorded where a red gate reads them
# ---------------------------------------------------------------------------
echo "--- codex surface: recorded exclusions ---"

for p in '.codex/hooks.json' '.codex/agents' '.agents'; do
  if /usr/bin/grep -qE "^$(printf '%s' "$p" | sed 's/[.]/\\./g')	.*	absent	" provenance-skip.tsv; then
    ok "excluded path is recorded rule=absent in provenance-skip.tsv: $p"
  else
    bad "excluded path is not recorded rule=absent in provenance-skip.tsv: $p — without the row it can drift back in silently"
  fi
done

# ---------------------------------------------------------------------------
# 8. The shipped Codex diagnosis is not gated out of its own case
#
# `/unity-doctor` Check 3b exists to find one thing: a project that took the
# skills bridge and not the hook layer, which the ship list names as its residual
# and which `## Success criterion 1` says a user cannot detect from the inside.
# Its first version skipped the whole check unless `.codex/` existed — so in the
# headline case, where `.codex/` is exactly what is missing, the check never ran.
# The gate has to be a disjunction, and prose that reads fine is how it stopped
# being one.
# ---------------------------------------------------------------------------
echo "--- codex surface: the shipped diagnosis ---"

DOCTOR=".claude/commands/unity-doctor.md"
if [ -f "$DOCTOR" ]; then
  GATE_LINE="$(awk '/Skip this whole check/{print; exit}' "$DOCTOR")"
  if [ -z "$GATE_LINE" ]; then
    bad "$DOCTOR has no Codex-layer skip gate — Check 3b either vanished or was reworded past this guard"
  else
    gate_bad=""
    /usr/bin/grep -qF -- '.codex/' <<< "$GATE_LINE" || gate_bad="$gate_bad .codex/"
    /usr/bin/grep -qF -- '.agents/skills' <<< "$GATE_LINE" || gate_bad="$gate_bad .agents/skills"
    if [ -z "$gate_bad" ]; then
      ok "the Codex check's skip gate names both layers, so the skills-bridge-without-hooks case reaches it"
    else
      bad "the Codex check's skip gate does not name:$gate_bad — gating on one layer skips the check in exactly the case it was written to detect (skills bridge installed, hook layer absent)"
    fi

    # THE CONNECTIVE, NOT JUST THE TERMS. Naming both directories says nothing
    # about the relation between them, and the relation is the whole finding: a
    # one-word edit from "or" to "and" left this green while making the gate
    # STRICTLY WORSE than the defect it replaced — a conjunction re-closes the
    # skills-bridge-without-hooks case and additionally closes the
    # hooks-without-skills case. The comment two screens up says prose that reads
    # fine is how this gate stopped being a disjunction, and a prose edit is
    # exactly what slipped past. Matched as whole words with a portable ERE: no
    # `\b`, which is a GNU extension absent from BSD grep on the macOS host this
    # repository keeps compatible.
    gate_or=0
    gate_and=0
    /usr/bin/grep -qE '(^|[^A-Za-z])or([^A-Za-z]|$)'  <<< "$GATE_LINE" && gate_or=1
    /usr/bin/grep -qE '(^|[^A-Za-z])and([^A-Za-z]|$)' <<< "$GATE_LINE" && gate_and=1
    if [ "$gate_or" -eq 1 ] && [ "$gate_and" -eq 0 ]; then
      ok "the Codex check's skip gate joins the two layers with a disjunction"
    elif [ "$gate_and" -eq 1 ]; then
      bad "the Codex check's skip gate joins the two layers with a conjunction — that is worse than the original defect: it skips BOTH the skills-bridge-without-hooks case this check exists for AND the hooks-without-skills case. Either layer means a Codex layer was installed; only running the check says whether all of it was"
    else
      bad "the Codex check's skip gate names both layers but states no disjunction between them — the relation is the finding, not the terms; a reader cannot tell whether one directory or both are required"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 9. The installer places the Codex layout, and the receipt disowns it
#
# EVERY INSTALL BELOW RUNS UNDER A DISPOSABLE `CODEX_HOME`. install.sh's trust
# step is the first thing this toolkit has ever written outside a project, and a
# test that pointed it at the real `~/.codex` would be a test that can damage the
# machine running it. The disposable home is also an ASSERTION: no consent was
# given on any of these runs, so it must still be empty afterwards.
# ---------------------------------------------------------------------------
echo "--- codex surface: the installer writes the layout ---"

CODEX_HOME_T="$WORK/codexhome"
mkdir -p "$CODEX_HOME_T"
chmod 700 "$CODEX_HOME_T"

# Derived from the tree, never listed: the skill set and the command set are what
# rows 2 and 3 of the ship list promise, one entry each.
SKILL_NAMES="$(for d in .claude/skills/*/; do [ -d "$d" ] && basename "$d"; done)"
CMD_NAMES="$(for c in .claude/commands/*.md; do [ -f "$c" ] && basename "$c" .md; done)"
SKILL_NAMES_N="$(printf '%s\n' "$SKILL_NAMES" | /usr/bin/grep -c . || true)"
CMD_NAMES_N="$(printf '%s\n' "$CMD_NAMES" | /usr/bin/grep -c . || true)"

if [ "$SKILL_NAMES_N" -ge 1 ] && [ "$CMD_NAMES_N" -ge 1 ]; then
  ok "derived $SKILL_NAMES_N skill(s) and $CMD_NAMES_N command(s) for the layout checks to be an identity over"
else
  bad "derived $SKILL_NAMES_N skill(s) and $CMD_NAMES_N command(s) — the layout checks below would pass over an empty set"
fi

CXFIX="$WORK/cxfix"
CXFIX_OK=0
if bash tests/fixtures/mkproject.sh "$CXFIX" --variant urp >/dev/null 2>&1 \
   && CODEX_HOME="$CODEX_HOME_T" bash install.sh --project-dir "$CXFIX" --client codex --yes \
        >"$WORK/cxinstall.out" 2>&1; then
  ok "install.sh --client codex succeeds against a fixture project"
  CXFIX_OK=1
else
  bad "install.sh --client codex failed against a fixture project: $(tail -3 "$WORK/cxinstall.out" 2>/dev/null | tr '\n' ' ')"
fi

# The set of project-relative paths the Codex layer owns, derived from the tree
# rather than written down, so a payload that grows or shrinks moves this with it.
codex_layout_paths() {   # $1 = project root
  printf 'AGENTS.md\n.codex/hooks.json\n.codex/config.toml\n'
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    printf '.agents/skills/%s\n' "$n"
  done <<< "$SKILL_NAMES"
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    printf '.agents/skills/%s/SKILL.md\n' "$n"
  done <<< "$CMD_NAMES"
}

if [ "$CXFIX_OK" -eq 1 ]; then
  LAYOUT_MISSING=""
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    # `-e` OR `-L`: rows 2's entries are symlinks to directories, and `-f` is
    # false for those. A check that used `-f` would report the whole skill bridge
    # absent while it was sitting right there.
    if [ -e "$CXFIX/$rel" ] || [ -L "$CXFIX/$rel" ]; then :; else
      LAYOUT_MISSING="$LAYOUT_MISSING $rel"
    fi
  done <<< "$(codex_layout_paths "$CXFIX")"
  if [ -z "$LAYOUT_MISSING" ]; then
    ok "the installer placed every path the ship list's rows 1-4 and 6 name"
  else
    bad "the installer did not place:$LAYOUT_MISSING"
  fi

  # Row 2 is a symlink root, not a copy. A directory of copies discovers the same
  # 16 and then goes stale the moment a skill is edited, which is the whole reason
  # the ship list prefers the symlink to the importer's copy.
  LINK_BAD=""
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    l="$CXFIX/.agents/skills/$n"
    [ -L "$l" ] || { LINK_BAD="$LINK_BAD $n(not-a-symlink)"; continue; }
    [ -f "$l/SKILL.md" ] || LINK_BAD="$LINK_BAD $n(dangling)"
  done <<< "$SKILL_NAMES"
  if [ -z "$LINK_BAD" ]; then
    ok "every skill entry is a symlink that resolves to a SKILL.md"
  else
    bad "skill-root defects:$LINK_BAD — Codex lists what it can resolve and says nothing about the rest"
  fi

  # Row 6: the MCP server row, in the shape the importer was measured to write.
  if /usr/bin/grep -qF -- 'mcp_servers.UnityMCP' "$CXFIX/.codex/config.toml" 2>/dev/null; then
    ok "the project's .codex/config.toml carries the UnityMCP server row"
  else
    bad "the project's .codex/config.toml has no mcp_servers.UnityMCP row"
  fi

  # ── THE ORDERING PROOF ───────────────────────────────────────────────────
  #
  # This is the assertion section 4 explicitly cannot make. There the config is
  # emitted BY THE TEST against an already-installed project, so the generator's
  # preference is exercised and the installer's SEQUENCE is not. Here the
  # installer emitted it, on a FRESH install — the only shape where the ordering
  # is observable at all. On a re-install `<project>/.claude/scripts/` is already
  # there from run 1, so an installer that emits before copying still picks up the
  # project's copy and this assertion passes over the defect. Fresh, or nothing.
  #
  # What an emit-before-copy produces is not a broken config: it is a config whose
  # every command string points into the toolkit clone, which per `## Hooks` is a
  # silent ALLOW once that directory moves. Nine registered hooks enforcing
  # nothing, which is the exact defect the shim exists to close.
  INST_SHIM_PATHS="$(/usr/bin/grep -o "'[^']*codex-hook-shim\.sh'" "$CXFIX/.codex/hooks.json" 2>/dev/null \
    | tr -d "'" | sort -u || true)"
  if [ "$INST_SHIM_PATHS" = "$CXFIX/.claude/scripts/codex-hook-shim.sh" ]; then
    ok "ORDERING: the installer copied scripts/ before emitting, so the config names the project's own shim"
  else
    bad "ORDERING: the emitted config names [$INST_SHIM_PATHS], not $CXFIX/.claude/scripts/codex-hook-shim.sh. install.sh emitted .codex/hooks.json BEFORE copying scripts/ into the project, so the generator fell back to the toolkit clone — a directory the user is under no obligation to keep, and per findings.md a hook command Codex cannot run is a silent allow, not an error"
  fi

  # And the general form of it: every path in every command string exists and
  # lies inside the project.
  CFG_BAD=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ ! -f "$p" ]; then CFG_BAD="$CFG_BAD $p(absent)"; continue; fi
    case "$p" in "$CXFIX"/*) ;; *) CFG_BAD="$CFG_BAD $p(outside)" ;; esac
  done <<< "$(/usr/bin/grep -o "'[^']*'" "$CXFIX/.codex/hooks.json" 2>/dev/null | tr -d "'" | sort -u || true)"
  if [ -z "$CFG_BAD" ]; then
    ok "every path the installed hook config names exists and lies inside the project"
  else
    bad "installed hook config names unrunnable path(s):$CFG_BAD"
  fi

  # ── The receipt ──────────────────────────────────────────────────────────
  # A file written without a receipt row is one uninstall.sh refuses to touch
  # forever. That defect shipped once already.
  CXRECEIPT="$CXFIX/.claude/state/install-receipt.tsv"
  if [ -f "$CXRECEIPT" ]; then
    ok "the codex install wrote a receipt"
    RCPT_MISSING=""
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      /usr/bin/grep -q "^$(printf '%s' "$rel" | sed 's/[.[\*^$/]/\\&/g')	" "$CXRECEIPT" \
        || RCPT_MISSING="$RCPT_MISSING $rel"
    done <<< "$(codex_layout_paths "$CXFIX")"
    if [ -z "$RCPT_MISSING" ]; then
      ok "the receipt covers every Codex path the installer wrote"
    else
      bad "the receipt does not cover:$RCPT_MISSING — uninstall.sh removes only what the receipt lists, so those are permanent debris"
    fi
  else
    bad "no receipt after a codex install"
  fi

  # ── No consent, no home write ────────────────────────────────────────────
  # `--yes` takes the safe default at every prompt, and for the one write that
  # leaves the project the safe default is not to make it.
  HOME_N="$(find "$CODEX_HOME_T" -mindepth 1 2>/dev/null | /usr/bin/grep -c . || true)"
  if [ "$HOME_N" -eq 0 ]; then
    ok "no consent was given, so the disposable CODEX_HOME is untouched"
  else
    bad "install.sh wrote $HOME_N path(s) into CODEX_HOME without consent — writing a user's home is not something --yes may take as a default"
  fi

  # ── The inverse ──────────────────────────────────────────────────────────
  if bash uninstall.sh --project-dir "$CXFIX" --yes --no-backup >"$WORK/cxuninstall.out" 2>&1; then
    LEFT=""
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      if [ -e "$CXFIX/$rel" ] || [ -L "$CXFIX/$rel" ]; then LEFT="$LEFT $rel"; fi
    done <<< "$(codex_layout_paths "$CXFIX")"
    if [ -z "$LEFT" ]; then
      ok "uninstall.sh removed the whole Codex layout, symlinks included"
    else
      bad "uninstall.sh left behind:$LEFT"
    fi
    # The directories too. An empty `.agents/skills/` still reads as a skill root.
    DIRS_LEFT=""
    for d in .agents .codex; do
      [ -d "$CXFIX/$d" ] && DIRS_LEFT="$DIRS_LEFT $d"
    done
    if [ -z "$DIRS_LEFT" ]; then
      ok "uninstall.sh pruned the Codex directories it emptied"
    else
      bad "uninstall.sh left empty director(ies):$DIRS_LEFT"
    fi
  else
    bad "uninstall.sh failed after a codex install: $(tail -3 "$WORK/cxuninstall.out" 2>/dev/null | tr '\n' ' ')"
  fi
fi

# ---------------------------------------------------------------------------
# 10. `--client claude` is what runs today
#
# The resolution this task was given is that every existing invocation must be
# unchanged, and that it be PROVEN rather than asserted. The proof a test can
# make is the equivalence: the flag's default and the flag spelled out produce
# byte-identical trees, and neither carries a Codex artifact. (The other half —
# that this equals the installer BEFORE the flag existed — is a comparison
# against a commit, which lives in the task's report, not here.)
# ---------------------------------------------------------------------------
echo "--- codex surface: the default client is untouched ---"

DEFFIX="$WORK/deffix"
EXPFIX="$WORK/expfix"
if bash tests/fixtures/mkproject.sh "$DEFFIX" --variant urp >/dev/null 2>&1 \
   && bash tests/fixtures/mkproject.sh "$EXPFIX" --variant urp >/dev/null 2>&1 \
   && CODEX_HOME="$CODEX_HOME_T" bash install.sh --project-dir "$DEFFIX" --yes >/dev/null 2>&1 \
   && CODEX_HOME="$CODEX_HOME_T" bash install.sh --project-dir "$EXPFIX" --client claude --yes >/dev/null 2>&1; then
  ok "both the default and --client claude install cleanly"

  # The receipt records an install timestamp and the fixtures differ in path, so
  # the comparison is over the payload, not the state directory.
  DIFF_OUT="$(diff -r --exclude=state "$DEFFIX/.claude" "$EXPFIX/.claude" 2>&1 || true)"
  if [ -z "$DIFF_OUT" ]; then
    ok "--client claude writes the same .claude/ tree the default does"
  else
    bad "--client claude diverges from the default install: $(printf '%s' "$DIFF_OUT" | head -5 | tr '\n' ' ')"
  fi

  CLAUDE_ARM_EXTRA=""
  for p in AGENTS.md .codex .agents; do
    if [ -e "$DEFFIX/$p" ] || [ -e "$EXPFIX/$p" ]; then CLAUDE_ARM_EXTRA="$CLAUDE_ARM_EXTRA $p"; fi
  done
  if [ -z "$CLAUDE_ARM_EXTRA" ]; then
    ok "neither Claude Code install produced a Codex artifact"
  else
    bad "a Claude Code install produced Codex artifact(s):$CLAUDE_ARM_EXTRA — the second client must be opt-in"
  fi
else
  bad "could not install the two Claude Code arms — the equivalence below cannot run"
fi

# A dry run writes nothing, on the codex arm too. Verified, not assumed.
DRYFIX="$WORK/dryfix"
if bash tests/fixtures/mkproject.sh "$DRYFIX" --variant urp >/dev/null 2>&1; then
  DRY_BEFORE="$(find "$DRYFIX" | sort)"
  CODEX_HOME="$CODEX_HOME_T" bash install.sh --project-dir "$DRYFIX" --client codex --dry-run >"$WORK/dry.out" 2>&1 || true
  DRY_AFTER="$(find "$DRYFIX" | sort)"
  if [ "$DRY_BEFORE" = "$DRY_AFTER" ]; then
    ok "--client codex --dry-run wrote nothing"
  else
    bad "--client codex --dry-run changed the tree: $(diff <(printf '%s\n' "$DRY_BEFORE") <(printf '%s\n' "$DRY_AFTER") | tr '\n' ' ')"
  fi
  # And it announced the layer rather than staying silent about it, which is the
  # dry run's whole job on the one arm that writes outside .claude/.
  if /usr/bin/grep -qF -- 'AGENTS.md' "$WORK/dry.out" && /usr/bin/grep -qF -- '.codex/hooks.json' "$WORK/dry.out"; then
    ok "the codex dry run announces the layer it would write"
  else
    bad "the codex dry run does not name AGENTS.md and .codex/hooks.json — a dry run silent about a write outside .claude/ is worse than none"
  fi
fi

# ---------------------------------------------------------------------------
# 11. THE UPGRADE FIXTURE
#
# Every other guard in this repository runs against a tree this repository just
# built. The tree that actually breaks is the one a user already has, produced by
# the previous version and then updated — measured on this toolkit, where a wave
# removed 15 hook files and every guard stayed green while an upgraded project
# kept 15 registrations pointing at nothing.
#
# So: install, modify the one file the update is documented to preserve
# (`.claude/settings.json` — the most-edited file in the payload, and the only
# place a hook is registered), install again, and assert the RESULTING TREE IS
# INTERNALLY CONSISTENT rather than merely that files were written.
#
# The second arm is the one that matters here. A kept settings.json is the input
# `--emit-config` reads, so a registration naming a file that is not there
# produces a Codex hook entry that cannot run — and under Codex that is an ALLOW,
# not an error. The installer must refuse to write such a config.
# ---------------------------------------------------------------------------
echo "--- codex surface: the upgrade fixture ---"

UPFIX="$WORK/upfix"
UPFIX_OK=0
if bash tests/fixtures/mkproject.sh "$UPFIX" --variant urp >/dev/null 2>&1 \
   && CODEX_HOME="$CODEX_HOME_T" bash install.sh --project-dir "$UPFIX" --client codex --yes >/dev/null 2>&1; then
  # The documented preservation: one appended newline is enough to make the file
  # "yours", which is exactly how the measured regression arrived.
  printf '\n' >> "$UPFIX/.claude/settings.json"
  UP_SETTINGS_SHA="$(sha256sum "$UPFIX/.claude/settings.json" | cut -d' ' -f1)"
  if CODEX_HOME="$CODEX_HOME_T" bash install.sh --project-dir "$UPFIX" --client codex --yes \
       >"$WORK/upgrade.out" 2>&1; then
    ok "a second --client codex install over the first succeeds"
    UPFIX_OK=1
  else
    bad "the upgrade install failed: $(tail -3 "$WORK/upgrade.out" 2>/dev/null | tr '\n' ' ')"
  fi
else
  bad "could not build the upgrade fixture"
fi

if [ "$UPFIX_OK" -eq 1 ]; then
  if [ "$(sha256sum "$UPFIX/.claude/settings.json" | cut -d' ' -f1)" = "$UP_SETTINGS_SHA" ]; then
    ok "upgrade: the edit to the file the installer documents as preserved survived"
  else
    bad "upgrade: .claude/settings.json was overwritten — that is the file the installer reports as kept"
  fi

  # Internal consistency 1: the config still points at the project's own shim and
  # every path in it runs.
  UP_CFG_BAD=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ ! -f "$p" ]; then UP_CFG_BAD="$UP_CFG_BAD $p(absent)"; continue; fi
    case "$p" in "$UPFIX"/*) ;; *) UP_CFG_BAD="$UP_CFG_BAD $p(outside)" ;; esac
  done <<< "$(/usr/bin/grep -o "'[^']*'" "$UPFIX/.codex/hooks.json" 2>/dev/null | tr -d "'" | sort -u || true)"
  if [ -z "$UP_CFG_BAD" ]; then
    ok "upgrade: every path the hook config names still exists inside the project"
  else
    bad "upgrade: the hook config names unrunnable path(s):$UP_CFG_BAD"
  fi

  # Internal consistency 2: the skill root still resolves, entry by entry.
  UP_LINK_BAD=""
  for l in "$UPFIX"/.agents/skills/*; do
    [ -e "$l" ] || [ -L "$l" ] || continue
    n="$(basename "$l")"
    [ -f "$l/SKILL.md" ] || UP_LINK_BAD="$UP_LINK_BAD $n"
  done
  if [ -z "$UP_LINK_BAD" ]; then
    ok "upgrade: every entry in the skill root still resolves to a SKILL.md"
  else
    bad "upgrade: dangling skill-root entr(ies):$UP_LINK_BAD"
  fi

  # Internal consistency 3: the receipt and the tree agree in BOTH directions
  # over the Codex layer. A row with no file is a claim about nothing; a file
  # with no row is permanent debris.
  UPRCPT="$UPFIX/.claude/state/install-receipt.tsv"
  UP_ROW_DEAD=""
  while IFS=$'\t' read -r rel _sha _mode _origin; do
    case "$rel" in ''|\#*|path) continue ;; esac
    case "$rel" in AGENTS.md|.codex/*|.agents/*) ;; *) continue ;; esac
    if [ -e "$UPFIX/$rel" ] || [ -L "$UPFIX/$rel" ]; then :; else
      UP_ROW_DEAD="$UP_ROW_DEAD $rel"
    fi
  done < "$UPRCPT"
  if [ -z "$UP_ROW_DEAD" ]; then
    ok "upgrade: every Codex receipt row names a path that is there"
  else
    bad "upgrade: receipt row(s) name paths that do not exist:$UP_ROW_DEAD"
  fi

  UP_FILE_UNCLAIMED=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#"$UPFIX"/}"
    /usr/bin/grep -q "^$(printf '%s' "$rel" | sed 's/[.[\*^$/]/\\&/g')	" "$UPRCPT" \
      || UP_FILE_UNCLAIMED="$UP_FILE_UNCLAIMED $rel"
  done <<< "$(find "$UPFIX/.codex" "$UPFIX/.agents" -mindepth 1 \( -type f -o -type l \) 2>/dev/null | sort)"
  [ -f "$UPFIX/AGENTS.md" ] && { /usr/bin/grep -q '^AGENTS\.md	' "$UPRCPT" || UP_FILE_UNCLAIMED="$UP_FILE_UNCLAIMED AGENTS.md"; }
  if [ -z "$UP_FILE_UNCLAIMED" ]; then
    ok "upgrade: every file in the Codex layout carries a receipt row"
  else
    bad "upgrade: Codex file(s) with no receipt row:$UP_FILE_UNCLAIMED — uninstall.sh will refuse to touch them forever"
  fi

  # ── The measured upgrade defect, in the Codex layer ──────────────────────
  # A kept settings.json that registers a hook whose file is not there. Under
  # Claude Code that is a dead registration the installer already reports; under
  # Codex the SAME row becomes a command Codex cannot run, and a hook command
  # Codex cannot run is a silent allow. So the installer must not emit it.
  python3 - "$UPFIX/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
cfg = json.load(open(p))
cfg.setdefault("hooks", {}).setdefault("PreToolUse", []).append(
    {"matcher": "Edit|Write",
     "hooks": [{"type": "command",
                "command": ".claude/hooks/this-hook-does-not-exist.sh",
                "timeout": 3000}]})
json.dump(cfg, open(p, "w"), indent=2)
PY
  CODEX_HOME="$CODEX_HOME_T" bash install.sh --project-dir "$UPFIX" --client codex --yes \
    >"$WORK/upgrade2.out" 2>&1 || true
  DEAD_IN_CFG=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -f "$p" ] || DEAD_IN_CFG="$DEAD_IN_CFG $p"
  done <<< "$(/usr/bin/grep -o "'[^']*'" "$UPFIX/.codex/hooks.json" 2>/dev/null | tr -d "'" | sort -u || true)"
  if [ -z "$DEAD_IN_CFG" ]; then
    ok "upgrade: a settings.json registration naming a missing file never reaches .codex/hooks.json"
  else
    bad "upgrade: .codex/hooks.json carries command(s) that cannot run:$DEAD_IN_CFG — under Codex that is an allow, not an error, so the gate is simply absent and nothing reports it"
  fi
  if /usr/bin/grep -qiF -- 'this-hook-does-not-exist' "$WORK/upgrade2.out"; then
    ok "upgrade: the installer named the offending registration rather than failing quietly"
  else
    bad "upgrade: the installer did not name the unrunnable registration — a config it declines to write in silence is indistinguishable from one it wrote"
  fi
fi

printf '\n=== Codex Surface: %d/%d passed, %d failed ===\n' "$PASS" "$((PASS + FAIL))" "$FAIL"
[ "$FAIL" -eq 0 ]
