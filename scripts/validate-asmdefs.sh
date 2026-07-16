#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# validate-asmdefs.sh
# Assembly definition (.asmdef) graph checker for Unity projects.
# Validates reference integrity, detects circular dependencies, checks
# Editor/Test assembly conventions, and reports uncovered C# files.
#
# Requires: jq
#
# Usage:
#   ./scripts/validate-asmdefs.sh [--all]
#   --all   Include detailed per-assembly output.
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
${BOLD}validate-asmdefs.sh${RESET} - Assembly definition graph checker for Unity.

${BOLD}Usage:${RESET}
  ./scripts/validate-asmdefs.sh [--all]

${BOLD}Options:${RESET}
  --all    Show detailed per-assembly information.
  --help   Show this help message.

${BOLD}Checks:${RESET}
  - Circular references between assemblies
  - Editor assemblies referencing runtime assemblies incorrectly
  - Test assemblies missing testOnly flag
  - C# files without assembly definition coverage

${BOLD}Requirements:${RESET}
  jq (https://stedolan.github.io/jq/) must be installed.
EOF
    exit 0
fi

# ---------------------------------------------------------------------------
# Check jq
# ---------------------------------------------------------------------------
if ! command -v jq &>/dev/null; then
    echo "${RED}[ERROR]${RESET} jq is required but not installed."
    echo "  Install with: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------
VERBOSE=false
[[ "${1:-}" == "--all" ]] && VERBOSE=true

# ---------------------------------------------------------------------------
# Locate project root
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

ASSETS_DIR="$PROJECT_ROOT/Assets"

echo ""
echo "${BOLD}=== Assembly Definition Validation ===${RESET}"
echo "  Project: $PROJECT_ROOT"
echo ""

error_count=0
warning_count=0

err()  { echo "  ${RED}[ERROR]${RESET} $*"; ((error_count++)); }
warn_msg() { echo "  ${YELLOW}[WARN]${RESET}  $*"; ((warning_count++)); }
info() { echo "  ${CYAN}[INFO]${RESET}  $*"; }

# ---------------------------------------------------------------------------
# 1. Collect all .asmdef files
# ---------------------------------------------------------------------------
declare -A ASMDEF_NAME_TO_PATH    # name -> file path
declare -A ASMDEF_PATH_TO_NAME    # file path -> name
declare -A ASMDEF_REFS            # name -> space-separated list of ref names
declare -A ASMDEF_DIR             # name -> directory containing the asmdef
declare -A ASMDEF_IS_EDITOR       # name -> true/false
declare -A ASMDEF_IS_TEST         # name -> true/false
declare -A ASMDEF_TEST_ONLY       # name -> true/false (from JSON)

asmdef_count=0

while IFS= read -r -d '' asmdef_file; do
    ((asmdef_count++))

    # Parse JSON
    name=$(jq -r '.name // empty' "$asmdef_file" 2>/dev/null || true)
    if [[ -z "$name" ]]; then
        warn_msg "Could not parse name from: ${asmdef_file#"$PROJECT_ROOT/"}"
        continue
    fi

    # Check for duplicate names
    if [[ -n "${ASMDEF_NAME_TO_PATH[$name]:-}" ]]; then
        err "Duplicate assembly name '$name':"
        echo "         ${ASMDEF_NAME_TO_PATH[$name]#"$PROJECT_ROOT/"}"
        echo "         ${asmdef_file#"$PROJECT_ROOT/"}"
        continue
    fi

    ASMDEF_NAME_TO_PATH["$name"]="$asmdef_file"
    ASMDEF_PATH_TO_NAME["$asmdef_file"]="$name"
    ASMDEF_DIR["$name"]="$(dirname "$asmdef_file")"

    # Extract references (can be plain names or GUIDs in GUID: format)
    refs=$(jq -r '(.references // [])[] | select(startswith("GUID:") | not)' "$asmdef_file" 2>/dev/null || true)
    ASMDEF_REFS["$name"]="$refs"

    # Determine if Editor assembly
    asmdef_dir_lower=$(echo "$(dirname "$asmdef_file")" | tr '[:upper:]' '[:lower:]')
    include_platforms=$(jq -r '(.includePlatforms // [])[]' "$asmdef_file" 2>/dev/null || true)
    is_editor=false
    if echo "$include_platforms" | grep -qi 'editor'; then
        is_editor=true
    elif [[ "$asmdef_dir_lower" == */editor* ]] || echo "$name" | grep -qi '\.editor'; then
        is_editor=true
    fi
    ASMDEF_IS_EDITOR["$name"]="$is_editor"

    # Determine if Test assembly
    is_test=false
    if [[ "$asmdef_dir_lower" == */tests* ]] || [[ "$asmdef_dir_lower" == */test* ]] || echo "$name" | grep -qi '\.tests\|\.test'; then
        is_test=true
    fi
    override_refs=$(jq -r '(.overrideReferences // false)' "$asmdef_file" 2>/dev/null || true)
    define_constraints=$(jq -r '(.defineConstraints // [])[]' "$asmdef_file" 2>/dev/null || true)
    if echo "$define_constraints" | grep -q 'UNITY_INCLUDE_TESTS'; then
        is_test=true
    fi
    ASMDEF_IS_TEST["$name"]="$is_test"

    # testOnly field (Unity doesn't have this natively, but some projects use defineConstraints)
    # We consider it "test only" if defineConstraints includes UNITY_INCLUDE_TESTS
    test_only=false
    if echo "$define_constraints" | grep -q 'UNITY_INCLUDE_TESTS'; then
        test_only=true
    fi
    ASMDEF_TEST_ONLY["$name"]="$test_only"

    if $VERBOSE; then
        info "Assembly: $name (editor=$is_editor, test=$is_test)"
    fi
done < <(find "$ASSETS_DIR" -name '*.asmdef' -print0 2>/dev/null)

info "Found $asmdef_count assembly definition(s)."
echo ""

if (( asmdef_count == 0 )); then
    warn_msg "No .asmdef files found. Consider adding assembly definitions."
    echo ""
    echo "${YELLOW}${BOLD}DONE${RESET} - No assemblies to validate."
    exit 0
fi

# ---------------------------------------------------------------------------
# 2. Detect circular references (DFS cycle detection)
# ---------------------------------------------------------------------------
echo "${BOLD}--- Circular Reference Check ---${RESET}"

declare -A VISIT_STATE  # 0=unvisited, 1=in-progress, 2=done
cycle_found=false

detect_cycle() {
    local node="$1"
    local path="$2"

    VISIT_STATE["$node"]=1  # in-progress

    local refs="${ASMDEF_REFS[$node]:-}"
    for ref in $refs; do
        # Skip references to assemblies not in our project (Unity packages etc.)
        [[ -z "${ASMDEF_NAME_TO_PATH[$ref]:-}" ]] && continue

        local state="${VISIT_STATE[$ref]:-0}"
        if (( state == 1 )); then
            err "Circular reference detected: ${path} -> ${ref}"
            cycle_found=true
        elif (( state == 0 )); then
            detect_cycle "$ref" "${path} -> ${ref}"
        fi
    done

    VISIT_STATE["$node"]=2  # done
}

for name in "${!ASMDEF_NAME_TO_PATH[@]}"; do
    if [[ "${VISIT_STATE[$name]:-0}" == "0" ]]; then
        detect_cycle "$name" "$name"
    fi
done

if ! $cycle_found; then
    echo "  ${GREEN}No circular references found.${RESET}"
fi

echo ""

# ---------------------------------------------------------------------------
# 3. Editor assembly checks
# ---------------------------------------------------------------------------
echo "${BOLD}--- Editor Assembly Checks ---${RESET}"
editor_issues=false

for name in "${!ASMDEF_NAME_TO_PATH[@]}"; do
    is_editor="${ASMDEF_IS_EDITOR[$name]}"
    refs="${ASMDEF_REFS[$name]:-}"

    if [[ "$is_editor" == "true" ]]; then
        # Editor assemblies should not be referenced by runtime assemblies
        for other_name in "${!ASMDEF_NAME_TO_PATH[@]}"; do
            [[ "$other_name" == "$name" ]] && continue
            [[ "${ASMDEF_IS_EDITOR[$other_name]}" == "true" ]] && continue
            [[ "${ASMDEF_IS_TEST[$other_name]}" == "true" ]] && continue

            other_refs="${ASMDEF_REFS[$other_name]:-}"
            if echo "$other_refs" | grep -qw "$name"; then
                err "Runtime assembly '$other_name' references Editor assembly '$name'."
                editor_issues=true
            fi
        done
    fi
done

if ! $editor_issues; then
    echo "  ${GREEN}No Editor/Runtime reference violations.${RESET}"
fi

echo ""

# ---------------------------------------------------------------------------
# 4. Test assembly checks
# ---------------------------------------------------------------------------
echo "${BOLD}--- Test Assembly Checks ---${RESET}"
test_issues=false

for name in "${!ASMDEF_NAME_TO_PATH[@]}"; do
    is_test="${ASMDEF_IS_TEST[$name]}"
    test_only="${ASMDEF_TEST_ONLY[$name]}"

    if [[ "$is_test" == "true" && "$test_only" == "false" ]]; then
        warn_msg "Test assembly '$name' lacks UNITY_INCLUDE_TESTS defineConstraint. It may be included in production builds."
        test_issues=true
    fi
done

if ! $test_issues; then
    echo "  ${GREEN}All test assemblies properly configured.${RESET}"
fi

echo ""

# ---------------------------------------------------------------------------
# 5. Files without assembly definition coverage
# ---------------------------------------------------------------------------
echo "${BOLD}--- Uncovered C# Files ---${RESET}"
uncovered_count=0

# Build list of asmdef directories (sorted deepest first for matching)
asmdef_dirs=()
for name in "${!ASMDEF_DIR[@]}"; do
    asmdef_dirs+=("${ASMDEF_DIR[$name]}")
done

is_covered() {
    local cs_dir="$1"
    for adir in "${asmdef_dirs[@]}"; do
        if [[ "$cs_dir" == "$adir"* ]]; then
            return 0
        fi
    done
    return 1
}

while IFS= read -r -d '' csfile; do
    cs_dir="$(dirname "$csfile")"
    if ! is_covered "$cs_dir"; then
        rel="${csfile#"$PROJECT_ROOT/"}"
        if (( uncovered_count < 20 )); then
            warn_msg "No .asmdef coverage: $rel"
        fi
        ((uncovered_count++))
    fi
done < <(find "$ASSETS_DIR" -name '*.cs' -not -path '*/Editor/*' -print0 2>/dev/null)

if (( uncovered_count > 20 )); then
    warn_msg "... and $(( uncovered_count - 20 )) more uncovered files."
fi

if (( uncovered_count == 0 )); then
    echo "  ${GREEN}All C# files are covered by an assembly definition.${RESET}"
else
    echo "  ${YELLOW}$uncovered_count file(s) without assembly definition coverage.${RESET}"
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "${BOLD}=== Summary ===${RESET}"
echo "  Assemblies found : $asmdef_count"
echo "  Errors           : $error_count"
echo "  Warnings         : $warning_count"

if (( error_count > 0 )); then
    echo ""
    echo "${RED}${BOLD}FAILED${RESET} - $error_count error(s) found."
    exit 1
elif (( warning_count > 0 )); then
    echo ""
    echo "${YELLOW}${BOLD}PASSED WITH WARNINGS${RESET} - $warning_count warning(s)."
    exit 0
else
    echo ""
    echo "${GREEN}${BOLD}PASSED${RESET} - All assembly definitions valid."
    exit 0
fi
