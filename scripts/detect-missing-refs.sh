#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# detect-missing-refs.sh
# Finds broken/missing references in Unity YAML serialised files (.unity,
# .prefab, .asset). Detects null GUIDs, missing scripts, and GUIDs that
# don't correspond to any .meta file in the project.
#
# Usage:
#   ./scripts/detect-missing-refs.sh [--path <dir>]
#   Defaults to Assets/ under the nearest Unity project root.
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
${BOLD}detect-missing-refs.sh${RESET} - Find broken references in Unity YAML files.

${BOLD}Usage:${RESET}
  ./scripts/detect-missing-refs.sh [--path <dir>]

${BOLD}Options:${RESET}
  --path <dir>   Directory to scan (defaults to Assets/).
  --help         Show this help message.

${BOLD}Detects:${RESET}
  - Null/zero GUIDs (guid: 00000000...)
  - Missing script references (m_Script: {fileID: 0})
  - Script GUIDs that don't match any .meta file in the project
EOF
    exit 0
fi

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
SCAN_PATH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --path) SCAN_PATH="$2"; shift 2 ;;
        *) echo "${RED}Unknown option: $1${RESET}"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Locate project root and scan directory
# ---------------------------------------------------------------------------
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
    echo "${RED}[ERROR]${RESET} Could not find Unity project root."
    exit 1
}

if [[ -n "$SCAN_PATH" ]]; then
    SCAN_DIR="$(cd "$SCAN_PATH" && pwd)"
else
    SCAN_DIR="$PROJECT_ROOT/Assets"
fi

if [[ ! -d "$SCAN_DIR" ]]; then
    echo "${RED}[ERROR]${RESET} Scan directory not found: $SCAN_DIR"
    exit 1
fi

echo ""
echo "${BOLD}=== Missing Reference Detection ===${RESET}"
echo "  Project: $PROJECT_ROOT"
echo "  Scanning: $SCAN_DIR"
echo ""

# ---------------------------------------------------------------------------
# 1. Build a set of all known GUIDs from .meta files
# ---------------------------------------------------------------------------
info_msg() { echo "  ${CYAN}[INFO]${RESET}  $*"; }

info_msg "Building GUID index from .meta files..."

declare -A KNOWN_GUIDS
meta_count=0

while IFS= read -r -d '' meta_file; do
    guid=$(grep -oP '^guid:\s*\K[0-9a-fA-F]+' "$meta_file" 2>/dev/null | head -1 || true)
    if [[ -n "$guid" ]]; then
        KNOWN_GUIDS["$guid"]=1
    fi
    ((meta_count++))
done < <(find "$PROJECT_ROOT/Assets" "$PROJECT_ROOT/Packages" -name '*.meta' -print0 2>/dev/null || find "$PROJECT_ROOT/Assets" -name '*.meta' -print0 2>/dev/null)

info_msg "Indexed $meta_count .meta files (${#KNOWN_GUIDS[@]} unique GUIDs)."
echo ""

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
null_guid_count=0
missing_script_count=0
dangling_guid_count=0
total_issues=0
files_scanned=0

report() {
    local type="$1" file="$2" lineno="$3" detail="$4"
    local rel="${file#"$PROJECT_ROOT/"}"
    echo "  ${RED}[$type]${RESET} ${rel}:${lineno}"
    echo "    ${YELLOW}${detail}${RESET}"
    ((total_issues++))
}

# ---------------------------------------------------------------------------
# 2. Scan Unity YAML files
# ---------------------------------------------------------------------------
echo "${BOLD}--- Scanning YAML files ---${RESET}"
echo ""

process_file() {
    local filepath="$1"
    local rel="${filepath#"$PROJECT_ROOT/"}"
    ((files_scanned++))

    # --- Null/zero GUIDs ---
    while IFS=: read -r lineno line; do
        [[ -z "$lineno" ]] && continue
        # Match guid: followed by all zeros (either 16 or 32 hex digits)
        if echo "$line" | grep -qE 'guid:\s*(0{16}|0{32})'; then
            report "NULL GUID" "$filepath" "$lineno" "$(echo "$line" | sed 's/^[[:space:]]*//')"
            ((null_guid_count++))
        fi
    done < <(grep -n 'guid:' "$filepath" 2>/dev/null || true)

    # --- Missing script (fileID: 0) ---
    while IFS=: read -r lineno line; do
        [[ -z "$lineno" ]] && continue
        report "MISSING SCRIPT" "$filepath" "$lineno" "$(echo "$line" | sed 's/^[[:space:]]*//')"
        ((missing_script_count++))
    done < <(grep -n 'm_Script:\s*{fileID:\s*0}' "$filepath" 2>/dev/null || true)

    # --- Dangling script GUIDs ---
    while IFS=: read -r lineno line; do
        [[ -z "$lineno" ]] && continue
        # Extract the GUID from m_Script: {fileID: 11500000, guid: <GUID>, ...}
        guid=$(echo "$line" | grep -oP 'guid:\s*\K[0-9a-fA-F]+' || true)
        if [[ -z "$guid" ]]; then
            continue
        fi
        # Skip null GUIDs (already caught above)
        if [[ "$guid" =~ ^0+$ ]]; then
            continue
        fi
        # Check if GUID exists in our index
        if [[ -z "${KNOWN_GUIDS[$guid]:-}" ]]; then
            report "DANGLING GUID" "$filepath" "$lineno" "Script GUID $guid not found in any .meta file"
            ((dangling_guid_count++))
        fi
    done < <(grep -n 'm_Script:\s*{fileID:\s*11500000,\s*guid:' "$filepath" 2>/dev/null || true)
}

# Find all .unity, .prefab, .asset files
while IFS= read -r -d '' yaml_file; do
    process_file "$yaml_file"
done < <(find "$SCAN_DIR" \( -name '*.unity' -o -name '*.prefab' -o -name '*.asset' \) -print0 2>/dev/null)

if (( total_issues == 0 )); then
    echo "  ${GREEN}No broken references found.${RESET}"
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "${BOLD}=== Summary ===${RESET}"
echo "  Files scanned      : $files_scanned"
echo "  Null GUIDs         : $null_guid_count"
echo "  Missing scripts    : $missing_script_count"
echo "  Dangling GUIDs     : $dangling_guid_count"
echo "  ${BOLD}Total issues${RESET}       : $total_issues"

if (( total_issues > 0 )); then
    echo ""
    echo "${RED}${BOLD}ISSUES FOUND${RESET} - $total_issues broken reference(s) detected."
    echo "  ${CYAN}Tip: Missing scripts often mean a .cs file was deleted without updating prefabs/scenes.${RESET}"
    echo "  ${CYAN}Tip: Dangling GUIDs may indicate a package was removed or a script was moved incorrectly.${RESET}"
    exit 1
else
    echo ""
    echo "${GREEN}${BOLD}CLEAN${RESET} - No broken references."
    exit 0
fi
