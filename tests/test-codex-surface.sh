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
# ---------------------------------------------------------------------------
echo "--- codex surface: the generated hook config ---"

# --emit-config writes to STDOUT and reads only .claude/settings.json, so running
# it against this repository creates nothing here.
HCFG="$WORK/hooks.json"
if bash scripts/codex-hook-shim.sh --emit-config --project-dir "$REPO_DIR" > "$HCFG" 2>"$WORK/emit.err"; then
  ok "codex-hook-shim.sh --emit-config succeeds against this repository"
else
  bad "codex-hook-shim.sh --emit-config failed: $(cat "$WORK/emit.err" 2>/dev/null | tr '\n' ' ')"
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

for p in '.codex/hooks.json' '.codex/agents'; do
  if /usr/bin/grep -qE "^$(printf '%s' "$p" | sed 's/[.]/\\./g')	.*	absent	" provenance-skip.tsv; then
    ok "excluded path is recorded rule=absent in provenance-skip.tsv: $p"
  else
    bad "excluded path is not recorded rule=absent in provenance-skip.tsv: $p — without the row it can drift back in silently"
  fi
done

printf '\n=== Codex Surface: %d/%d passed, %d failed ===\n' "$PASS" "$((PASS + FAIL))" "$FAIL"
[ "$FAIL" -eq 0 ]
