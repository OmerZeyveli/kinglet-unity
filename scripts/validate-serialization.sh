#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# validate-serialization.sh
# Checks for renamed serialized fields missing [FormerlySerializedAs].
# Compares current state against git history to detect field renames that
# would silently reset values in scenes, prefabs, and ScriptableObjects.
#
# Usage:
#   ./scripts/validate-serialization.sh [--path <dir>] [--staged]
#   --path <dir>   Scan a specific directory (default: Assets/)
#   --staged       Only check staged files (for pre-commit validation)
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
${BOLD}validate-serialization.sh${RESET} - Detect renamed serialized fields missing FormerlySerializedAs.

${BOLD}Usage:${RESET}
  ./scripts/validate-serialization.sh [OPTIONS]

${BOLD}Options:${RESET}
  --path <dir>   Directory to scan (default: Assets/ under Unity project root)
  --staged       Only check files staged for commit
  -h, --help     Show this help

${BOLD}What it checks:${RESET}
  - Compares [SerializeField] field names against previous git version
  - Reports renames without [FormerlySerializedAs("oldName")]
  - Also checks public fields on MonoBehaviour/ScriptableObject classes

${BOLD}Why it matters:${RESET}
  Renaming a serialized field without FormerlySerializedAs silently resets
  every configured value in every scene, prefab, and ScriptableObject.
EOF
    exit 0
fi

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
SCAN_PATH=""
STAGED_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path) SCAN_PATH="$2"; shift 2 ;;
        --staged) STAGED_ONLY=true; shift ;;
        *) echo "${RED}Unknown option: $1${RESET}" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Find Unity project root
# ---------------------------------------------------------------------------
find_unity_root() {
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

UNITY_ROOT=$(find_unity_root) || {
    echo "${RED}Error: Not inside a Unity project (no Assets/ + ProjectSettings/ found).${RESET}" >&2
    exit 1
}

if [[ -z "$SCAN_PATH" ]]; then
    SCAN_PATH="$UNITY_ROOT/Assets"
fi

# ---------------------------------------------------------------------------
# Check git availability
# ---------------------------------------------------------------------------
if ! git -C "$UNITY_ROOT" rev-parse --git-dir &>/dev/null; then
    echo "${RED}Error: Not a git repository. Cannot compare against history.${RESET}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Collect files to check
# ---------------------------------------------------------------------------
if $STAGED_ONLY; then
    FILES=$(git -C "$UNITY_ROOT" diff --cached --name-only --diff-filter=M | grep '\.cs$' || true)
else
    FILES=$(find "$SCAN_PATH" -name "*.cs" -not -path "*/Editor/*" -not -path "*/Tests/*" 2>/dev/null || true)
    # Make paths relative to UNITY_ROOT for git show
    FILES=$(echo "$FILES" | sed "s|^$UNITY_ROOT/||")
fi

if [[ -z "$FILES" ]]; then
    echo "${GREEN}No C# files to check.${RESET}"
    exit 0
fi

# ---------------------------------------------------------------------------
# Extract serialized field names from content
# ---------------------------------------------------------------------------
extract_serialized_fields() {
    local content="$1"
    # Match [SerializeField] ... fieldName; patterns
    echo "$content" | grep -E '\[SerializeField\]' | grep -oE '\b\w+\s*[;=]' | sed 's/[;= ]//g' || true
    # Match [field: SerializeField] ... PropertyName patterns
    echo "$content" | grep -E '\[field:\s*SerializeField\]' | grep -oE '\b\w+\s*\{' | sed 's/[{ ]//g' || true
    # Match public fields on MonoBehaviour/ScriptableObject (implicitly serialized)
    echo "$content" | grep -E '^\s*public\s+\w+\s+\w+\s*[;=]' | grep -v '\[NonSerialized\]' | grep -oE '\b\w+\s*[;=]' | tail -1 | sed 's/[;= ]//g' || true
}

# ---------------------------------------------------------------------------
# Scan
# ---------------------------------------------------------------------------
WARNINGS=0

echo "${BOLD}Scanning for serialized field renames without FormerlySerializedAs...${RESET}"
echo ""

while IFS= read -r FILE; do
    [[ -z "$FILE" ]] && continue

    # Get the previous version from git
    OLD_CONTENT=$(git -C "$UNITY_ROOT" show "HEAD:$FILE" 2>/dev/null || true)
    if [[ -z "$OLD_CONTENT" ]]; then
        continue  # New file, nothing to compare
    fi

    # Get current content
    if [[ -f "$UNITY_ROOT/$FILE" ]]; then
        NEW_CONTENT=$(cat "$UNITY_ROOT/$FILE")
    else
        continue
    fi

    # Extract field names
    OLD_FIELDS=$(extract_serialized_fields "$OLD_CONTENT")
    NEW_FIELDS=$(extract_serialized_fields "$NEW_CONTENT")

    if [[ -z "$OLD_FIELDS" ]]; then
        continue
    fi

    # Check each old field
    while IFS= read -r OLD_FIELD; do
        [[ -z "$OLD_FIELD" ]] && continue

        # Check if the field still exists in the new version
        if ! echo "$NEW_FIELDS" | grep -qx "$OLD_FIELD"; then
            # Field was removed or renamed — check for FormerlySerializedAs
            if ! echo "$NEW_CONTENT" | grep -q "FormerlySerializedAs.*\"$OLD_FIELD\""; then
                echo "${YELLOW}WARNING${RESET}: ${BOLD}$FILE${RESET}"
                echo "  Serialized field '${RED}$OLD_FIELD${RESET}' was removed/renamed without [FormerlySerializedAs(\"$OLD_FIELD\")]"
                echo "  This will silently reset values in all scenes, prefabs, and ScriptableObjects."
                echo ""
                WARNINGS=$((WARNINGS + 1))
            fi
        fi
    done <<< "$OLD_FIELDS"
done <<< "$FILES"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if [[ $WARNINGS -eq 0 ]]; then
    echo "${GREEN}All serialized field renames have proper FormerlySerializedAs attributes.${RESET}"
else
    echo "${YELLOW}Found $WARNINGS serialization warning(s).${RESET}"
    echo "Fix: Add [FormerlySerializedAs(\"oldName\")] above each renamed field."
fi

exit 0
