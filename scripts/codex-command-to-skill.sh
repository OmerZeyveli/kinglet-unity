#!/usr/bin/env bash
# =============================================================================
# codex-command-to-skill.sh
# Converts Kinglet's commands into Codex CLI skills.
#
# Usage:
#   ./scripts/codex-command-to-skill.sh [--project-dir DIR] [--out DIR] [--list]
#   In an installed Unity project this file is ./.claude/scripts/codex-command-to-skill.sh.
#
#   --project-dir DIR  project root holding .claude/ (default: the tree this
#                      script was installed into).
#   --out DIR          where the skill directories go (default:
#                      <project>/.agents/skills, the root Codex reads).
#   --list             print the SKILL.md paths that WOULD be written, one per
#                      line, and write nothing. For an installer's receipt.
#
# CONTRACT: files go to --out. Logs go to STDERR. Only --list writes stdout.
#
# WHY THIS EXISTS. codex-cli 0.145.0 has no command surface — 24 subcommands,
# none of them a prompt registry, no ~/.codex/prompts, and the only
# command-shaped app-server methods are shell execution. Codex's own answer is
# that a command is a skill: its external-config importer's COMMANDS item reads
# "Migrate commands from <repo>/.claude/commands to <repo>/.agents/skills".
#
# WHY KINGLET DOES IT RATHER THAN THE IMPORTER. Measured: the importer drops a
# command whose body contains $ARGUMENTS or a $-digit token, silently — it never
# appears in `detect`, so `import` reports success with the file absent. Seven
# of Kinglet's nine commands carry $ARGUMENTS, so seven are lost with a zero
# failure count. On the Kinglet path with no converter at all, nine of nine are
# lost, which is worse. A generator that writes the body itself never emits the
# token in the first place.
#
# WHAT IS LOST ANYWAY, STATED RATHER THAN IMPLIED. A Codex "command" is a skill
# the model may choose to load, not a user-typed /unity-fix. Task 5 observed 6
# distinct skills ever loading out of 16-18 discovered. A converted command is
# DISCOVERABLE, not dispatchable, and the note this script prepends says so to
# the model rather than pretending otherwise.
#
# WHAT THIS DELIBERATELY DOES NOT DO: rewrite paths. The importer's blind
# Claude->Codex substitution rewrote 84 `.claude/` references to a `.Codex/`
# that exists under no spelling, including 29 into a rules directory that never
# migrates at all. On the Kinglet path `.claude/` is right there, so every path
# in a command body already resolves. The only token rewritten here is
# $ARGUMENTS, because a skill has no argument substitution and the literal would
# reach the model as text naming a mechanism that does not exist.
# =============================================================================

set -euo pipefail

# The header block between its two `# ====` rules; tests/test-help-ranges.sh derives
# both numbers from the line below and checks the slice is whole — it ends at the last
# prose line, not one line short of it, which is the defect that shipped a truncated
# --help from generate-claude-md.sh for as long as its closing paragraph existed.
usage() { sed -n '3,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

SELF_NAME="codex-command-to-skill.sh"
info() { printf '%s: %s\n' "$SELF_NAME" "$1" >&2; }
die()  { printf '%s: %s\n' "$SELF_NAME" "$1" >&2; exit 1; }

# Every value is validated BEFORE `shift 2`: under `set -u`, `shift 2` with one
# argument left fails before the error message prints and the caller gets a
# silent exit 1.
PROJECT_DIR_ARG=""
OUT_ARG=""
LIST_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) [ $# -ge 2 ] || die "--project-dir requires a value"; PROJECT_DIR_ARG="$2"; shift 2 ;;
    --out)         [ $# -ge 2 ] || die "--out requires a value";         OUT_ARG="$2";         shift 2 ;;
    --list)        LIST_ONLY=1; shift ;;
    -h|--help)     usage ;;
    -*)            die "unknown option: $1" ;;
    *)             die "unexpected argument: $1" ;;
  esac
done

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -n "$PROJECT_DIR_ARG" ]; then
  PROJECT_DIR="$(cd "$PROJECT_DIR_ARG" 2>/dev/null && pwd)" || die "--project-dir not found: $PROJECT_DIR_ARG"
else
  # Repo layout: <root>/scripts/ -> <root>/.claude/
  # Installed layout: <project>/.claude/scripts/ -> <project>/.claude/
  if [ -d "$SELF_DIR/../.claude/commands" ]; then
    PROJECT_DIR="$(cd "$SELF_DIR/.." && pwd)"
  elif [ -d "$SELF_DIR/../commands" ]; then
    PROJECT_DIR="$(cd "$SELF_DIR/../.." && pwd)"
  else
    die "cannot locate .claude/commands from $SELF_DIR — pass --project-dir"
  fi
fi

CMD_DIR="$PROJECT_DIR/.claude/commands"
[ -d "$CMD_DIR" ] || die "no commands directory at $CMD_DIR"

OUT_DIR="${OUT_ARG:-$PROJECT_DIR/.agents/skills}"

# ---------------------------------------------------------------------------
# Frontmatter reading. A command's frontmatter is `name`, `description`,
# `user-invocable` and `args`; a skill's is `name` and `description` and nothing
# else, so the other two are dropped rather than carried across. `args` in
# particular describes a mechanism the target does not have.
# ---------------------------------------------------------------------------
fm_value() {   # $1 = file, $2 = key
  awk -v key="$2" '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---"  { exit }
    inside {
      if (index($0, key ":") == 1) {
        v = substr($0, length(key) + 2)
        sub(/^[[:space:]]+/, "", v)
        print v
        exit
      }
    }
  ' "$1"
}

fm_end_line() {  # $1 = file -> line number of the closing ---, or empty
  awk '
    NR == 1 && $0 == "---" { open = 1; next }
    open && $0 == "---"    { print NR; exit }
  ' "$1"
}

# ---------------------------------------------------------------------------
# Emit
# ---------------------------------------------------------------------------
WROTE=0
for src in "$CMD_DIR"/*.md; do
  [ -f "$src" ] || continue
  name="$(basename "$src" .md)"
  target_dir="$OUT_DIR/$name"
  target="$target_dir/SKILL.md"

  if [ "$LIST_ONLY" -eq 1 ]; then
    printf '%s\n' "$target"
    WROTE=$((WROTE + 1))
    continue
  fi

  desc="$(fm_value "$src" description)"
  if [ -z "$desc" ]; then
    # `description` is the entire selection mechanism — a skill with an empty one
    # is discovered and never chosen. Refuse rather than emit a dead surface.
    die "$src has no description: in its frontmatter; a skill with no description is discovered and never selected"
  fi

  end="$(fm_end_line "$src")"
  [ -n "$end" ] || end=0

  mkdir -p "$target_dir"

  {
    printf '%s\n' '---'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$desc"
    printf '%s\n' '---'
    printf '\n'
    printf '%s\n' "> **Converted from Kinglet's \`$name\` command for Codex CLI.** Codex has no command"
    printf '%s\n' "> surface and no skill tool: there is no \`/$name\` to type, and nothing loads this file"
    printf '%s\n' '> for you — you are reading it because you chose to. Two things in the body below name'
    printf '%s\n' '> Claude Code mechanisms that do not exist here, and both have a stated fallback:'
    printf '%s\n' '>'
    printf '%s\n' '> - **Sub-agent dispatch.** There is no per-agent tool grant in Codex, so an agent'
    printf '%s\n' '>   cannot be started narrowed. Take the degraded path the body already describes: do'
    printf '%s\n' '>   the work inline and say that you are doing so.'
    printf '%s\n' '> - **`CLAUDE.md`.** In this project the injected entry document is `AGENTS.md`, which'
    printf '%s\n' '>   carries the same generated block. `CLAUDE.md` is present and readable; it is simply'
    printf '%s\n' '>   not loaded for you.'
    printf '%s\n' '>'
    printf '%s\n' '> Every other path in this file resolves as written — nothing here was rewritten.'
    printf '\n'
    awk -v skip="$end" 'NR > skip' "$src" | sed 's/[$]ARGUMENTS/the request the user just made/g'
  } > "$target"

  WROTE=$((WROTE + 1))
done

if [ "$LIST_ONLY" -eq 1 ]; then
  info "$WROTE command(s) would be written under $OUT_DIR"
else
  info "converted $WROTE command(s) into $OUT_DIR"
fi
