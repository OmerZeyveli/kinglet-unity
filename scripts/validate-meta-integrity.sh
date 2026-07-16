#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# validate-meta-integrity.sh
# Checks .meta file health in a Unity project's Assets/ directory.
# Detects missing .meta files, orphaned .meta files, and duplicate GUIDs.
#
# Usage:
#   ./scripts/validate-meta-integrity.sh [--staged|--all]
#   --staged   Only check files staged in git (useful as a pre-commit hook).
#   --all      Scan the entire Assets/ directory (default).
# =============================================================================

# ---------------------------------------------------------------------------
# Color support
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3)
    CYAN=$(tput setaf 6); BOLD=$(tput bold); RESET=$(tput sgr0)
else
    RED=""; GREEN=""; YELLOW=""; CYAN=""; BOLD=""; RESET=""
fi

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<EOF
${BOLD}validate-meta-integrity.sh${RESET} - Check .meta file health in a Unity project.

${BOLD}Usage:${RESET}
  ./scripts/validate-meta-integrity.sh [--staged|--all]

${BOLD}Flags:${RESET}
  --staged   Only check files staged in git.
  --all      Scan the entire Assets/ directory (default).
  --help     Show this help message.

${BOLD}Exit codes:${RESET}
  0  No issues found.
  1  One or more issues detected.
EOF
    exit 0
fi

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------
MODE="all"
if [[ "${1:-}" == "--staged" ]]; then
    MODE="staged"
elif [[ "${1:-}" == "--all" ]]; then
    MODE="all"
fi

# ---------------------------------------------------------------------------
# Locate Assets/
# ---------------------------------------------------------------------------
# Walk up to find the Unity project root
find_project_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/Assets" && -d "$dir/ProjectSettings" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

PROJECT_ROOT=$(find_project_root) || {
    echo "${RED}[ERROR]${RESET} Could not find a Unity project root (Assets/ + ProjectSettings/)."
    exit 1
}

ASSETS_DIR="$PROJECT_ROOT/Assets"

error_count=0
warning_count=0
missing_meta=()
orphaned_meta=()
declare -A guid_map  # guid -> file path

err()  { echo "  ${RED}[ERROR]${RESET}   $*"; ((error_count++)); }
warn_msg() { echo "  ${YELLOW}[WARN]${RESET}    $*"; ((warning_count++)); }
info() { echo "  ${CYAN}[INFO]${RESET}    $*"; }

echo ""
echo "${BOLD}=== Meta Integrity Check ===${RESET}"
echo "  Project root: $PROJECT_ROOT"
echo "  Mode: $MODE"
echo ""

# ---------------------------------------------------------------------------
# Build file list
# ---------------------------------------------------------------------------
declare -a FILE_LIST=()

if [[ "$MODE" == "staged" ]]; then
    if ! git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
        echo "${RED}[ERROR]${RESET} --staged requires a git repository."
        exit 1
    fi
    while IFS= read -r f; do
        # Only care about files under Assets/
        if [[ "$f" == Assets/* ]]; then
            FILE_LIST+=("$PROJECT_ROOT/$f")
        fi
    done < <(git -C "$PROJECT_ROOT" diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
    info "Checking ${#FILE_LIST[@]} staged file(s) under Assets/."
else
    while IFS= read -r -d '' f; do
        FILE_LIST+=("$f")
    done < <(find "$ASSETS_DIR" -not -path '*/.git/*' -print0 2>/dev/null)
    info "Scanning all files/folders under Assets/."
fi

echo ""

# ---------------------------------------------------------------------------
# 1. Missing .meta files
# ---------------------------------------------------------------------------
echo "${BOLD}--- Missing .meta files ---${RESET}"
found_missing=0

check_missing_meta() {
    local item="$1"
    # Skip .meta files themselves and hidden files
    [[ "$item" == *.meta ]] && return
    [[ "$(basename "$item")" == .* ]] && return
    # The Assets folder itself does not need a .meta
    [[ "$item" == "$ASSETS_DIR" ]] && return

    if [[ ! -f "${item}.meta" ]]; then
        local rel="${item#"$PROJECT_ROOT/"}"
        err "Missing .meta: $rel"
        missing_meta+=("$rel")
        found_missing=1
    fi
}

for f in "${FILE_LIST[@]}"; do
    check_missing_meta "$f"
done

if (( found_missing == 0 )); then
    echo "  ${GREEN}No missing .meta files.${RESET}"
fi

echo ""

# ---------------------------------------------------------------------------
# 2. Orphaned .meta files
# ---------------------------------------------------------------------------
echo "${BOLD}--- Orphaned .meta files ---${RESET}"
found_orphaned=0

check_orphaned_meta() {
    local meta="$1"
    [[ "$meta" != *.meta ]] && return
    local asset="${meta%.meta}"
    if [[ ! -e "$asset" ]]; then
        local rel="${meta#"$PROJECT_ROOT/"}"
        warn_msg "Orphaned .meta: $rel"
        orphaned_meta+=("$rel")
        found_orphaned=1
    fi
}

if [[ "$MODE" == "all" ]]; then
    while IFS= read -r -d '' meta; do
        check_orphaned_meta "$meta"
    done < <(find "$ASSETS_DIR" -name '*.meta' -print0 2>/dev/null)
else
    for f in "${FILE_LIST[@]}"; do
        check_orphaned_meta "$f"
    done
fi

if (( found_orphaned == 0 )); then
    echo "  ${GREEN}No orphaned .meta files.${RESET}"
fi

echo ""

# ---------------------------------------------------------------------------
# 3. Duplicate GUIDs
# ---------------------------------------------------------------------------
echo "${BOLD}--- Duplicate GUID check ---${RESET}"
found_dupes=0

collect_guids() {
    local meta="$1"
    [[ "$meta" != *.meta ]] && return
    local guid
    guid=$(grep -oP '^guid:\s*\K[0-9a-f]+' "$meta" 2>/dev/null || true)
    if [[ -z "$guid" ]]; then
        return
    fi
    local rel="${meta#"$PROJECT_ROOT/"}"
    if [[ -n "${guid_map[$guid]:-}" ]]; then
        err "Duplicate GUID $guid:"
        echo "         ${guid_map[$guid]}"
        echo "         $rel"
        found_dupes=1
    else
        guid_map["$guid"]="$rel"
    fi
}

if [[ "$MODE" == "all" ]]; then
    while IFS= read -r -d '' meta; do
        collect_guids "$meta"
    done < <(find "$ASSETS_DIR" -name '*.meta' -print0 2>/dev/null)
else
    for f in "${FILE_LIST[@]}"; do
        collect_guids "$f"
    done
fi

if (( found_dupes == 0 )); then
    echo "  ${GREEN}No duplicate GUIDs found.${RESET}"
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "${BOLD}=== Summary ===${RESET}"
echo "  Missing .meta files : ${#missing_meta[@]}"
echo "  Orphaned .meta files: ${#orphaned_meta[@]}"
echo "  Errors              : $error_count"
echo "  Warnings            : $warning_count"

if (( error_count > 0 )); then
    echo ""
    echo "${RED}${BOLD}FAILED${RESET} - $error_count error(s) found."
    exit 1
else
    echo ""
    echo "${GREEN}${BOLD}PASSED${RESET} - No errors."
    exit 0
fi
