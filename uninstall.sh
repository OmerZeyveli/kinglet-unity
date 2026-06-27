#!/usr/bin/env bash
#
# cloud-nine-unity — overlay uninstaller
#
# Removes ONLY the overlay's own files from <project>/.claude/. It never touches ECU's files,
# your settings.json, or your docs/.
#
# Usage:
#   ./uninstall.sh --project-dir /path/to/UnityProject [--yes]
#
#   --project-dir <path>  Target Unity project root (default: current directory)
#   --yes                 Skip the confirmation prompt
#   -h, --help            Show this help
#
set -euo pipefail

if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi
info() { printf '%s\n' "${BLUE}==>${NC} $*"; }
ok()   { printf '%s\n' "${GREEN} ok${NC}  $*"; }
warn() { printf '%s\n' "${YELLOW}warn${NC} $*"; }
die()  { printf '%s\n' "${RED}err ${NC} $*" >&2; exit 1; }

# Payload manifest (keep in sync with install.sh)
AGENTS="game-designer systems-designer level-designer narrative-director writer world-builder creative-director technical-director"
COMMANDS="brainstorm design-review map-systems design-system sprint-plan scope-check milestone-review estimate retrospective"
RULES="pc-console"
TEMPLATES="game-design-document architecture-decision-record sprint-plan game-concept systems-index"

PROJECT_DIR="$(pwd)"; ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) PROJECT_DIR="${2:-}"; shift 2 ;;
    --yes|-y)      ASSUME_YES=1; shift ;;
    -h|--help)     sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             die "Unknown argument: $1 (use --help)" ;;
  esac
done

[ -n "$PROJECT_DIR" ] || die "--project-dir requires a path"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || die "Project directory not found: $PROJECT_DIR"
CLAUDE_DIR="$PROJECT_DIR/.claude"
[ -d "$CLAUDE_DIR" ] || die "No .claude/ directory in $PROJECT_DIR — nothing to uninstall."

printf '%s\n' "${BOLD}cloud-nine-unity — overlay uninstaller${NC}"
info "Project: $PROJECT_DIR"
warn "This removes ONLY the overlay's files. ECU files, settings.json, and docs/ are left intact."

if [ "$ASSUME_YES" -ne 1 ]; then
  printf '%s' "Proceed? [y/N] "
  read -r reply
  case "$reply" in y|Y|yes|YES) ;; *) info "Aborted."; exit 0 ;; esac
fi

REMOVED=0; MISSING=0
remove_one() {  # $1 = file path
  if [ -f "$1" ]; then
    rm -f "$1"; ok "removed: ${1#$PROJECT_DIR/}"; REMOVED=$((REMOVED+1))
  else
    MISSING=$((MISSING+1))
  fi
}

for n in $AGENTS;    do remove_one "$CLAUDE_DIR/agents/$n.md";    done
for n in $COMMANDS;  do remove_one "$CLAUDE_DIR/commands/$n.md";  done
for n in $RULES;     do remove_one "$CLAUDE_DIR/rules/$n.md";     done
for n in $TEMPLATES; do remove_one "$CLAUDE_DIR/templates/$n.md"; done

# Remove .claude/templates only if it is now empty (i.e., the overlay created it)
if [ -d "$CLAUDE_DIR/templates" ] && [ -z "$(ls -A "$CLAUDE_DIR/templates" 2>/dev/null)" ]; then
  rmdir "$CLAUDE_DIR/templates" && ok "removed empty .claude/templates/"
fi

printf '\n%s\n' "${BOLD}Done.${NC} Removed: $REMOVED  ·  Not present: $MISSING"
info "ECU is untouched. Your design/production docs under docs/ were not removed."
exit 0
