#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# validate-code-quality.sh
# Grep-based C# code quality scanner for Unity projects.
# Detects common performance pitfalls, bad practices, and potential bugs
# without requiring Roslyn or any .NET tooling.
#
# Usage:
#   ./scripts/validate-code-quality.sh [--path <dir>]
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
${BOLD}validate-code-quality.sh${RESET} - Grep-based C# code quality scanner for Unity.

${BOLD}Usage:${RESET}
  ./scripts/validate-code-quality.sh [--path <dir>]

${BOLD}Options:${RESET}
  --path <dir>   Directory to scan (defaults to Assets/ in the project root).
  --help         Show this help message.

${BOLD}Checks:${RESET}
  - GetComponent in Update/FixedUpdate/LateUpdate
  - Camera.main without caching
  - FindObjectOfType in Update methods
  - Heap allocations (new List/Dictionary/HashSet) in Update methods
  - String concatenation in Update methods
  - tag == "..." instead of CompareTag()
  - SendMessage / BroadcastMessage usage
  - Unguarded Debug.Log in non-Editor code
  - foreach on arrays in Update (pre-2021 allocation)
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
# Locate scan directory
# ---------------------------------------------------------------------------
if [[ -n "$SCAN_PATH" ]]; then
    SCAN_DIR="$(cd "$SCAN_PATH" && pwd)"
else
    # Walk up to find project root
    dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/Assets" && -d "$dir/ProjectSettings" ]]; then
            break
        fi
        dir="$(dirname "$dir")"
    done
    SCAN_DIR="$dir/Assets"
fi

if [[ ! -d "$SCAN_DIR" ]]; then
    echo "${RED}[ERROR]${RESET} Scan directory not found: $SCAN_DIR"
    exit 1
fi

echo ""
echo "${BOLD}=== C# Code Quality Scan ===${RESET}"
echo "  Scanning: $SCAN_DIR"
echo ""

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
declare -A COUNTS
CATEGORIES=(
    "GetComponent-in-Update"
    "Camera.main-uncached"
    "FindObjectOfType-in-Update"
    "Heap-alloc-in-Update"
    "String-concat-in-Update"
    "tag-equality"
    "SendMessage-usage"
    "Unguarded-Debug.Log"
    "foreach-array-in-Update"
)
for cat in "${CATEGORIES[@]}"; do
    COUNTS["$cat"]=0
done

total_issues=0

# ---------------------------------------------------------------------------
# Helper: report an issue
# ---------------------------------------------------------------------------
report() {
    local category="$1" file="$2" lineno="$3" line="$4" fix="$5"
    echo "  ${YELLOW}[$category]${RESET} ${file}:${lineno}"
    echo "    ${RED}> ${line}${RESET}"
    echo "    ${CYAN}Fix: ${fix}${RESET}"
    echo ""
    COUNTS["$category"]=$(( ${COUNTS["$category"]} + 1 ))
    ((total_issues++))
}

# ---------------------------------------------------------------------------
# Helper: check if a line number is inside an Update-like method.
# This is a heuristic: we look backwards from the line for a method signature
# containing Update, FixedUpdate, or LateUpdate before hitting another method
# or class boundary.
# ---------------------------------------------------------------------------
is_in_update_method() {
    local file="$1" target_line="$2"
    # Extract lines before target_line, reversed, look for method signature
    local context
    context=$(head -n "$target_line" "$file" | tac | head -n 100)
    local brace_depth=0
    while IFS= read -r cline; do
        # Count braces to find method boundary
        local open close
        open=$(echo "$cline" | tr -cd '{' | wc -c)
        close=$(echo "$cline" | tr -cd '}' | wc -c)
        brace_depth=$(( brace_depth + close - open ))
        # If we closed more than opened, we left the method
        if (( brace_depth > 0 )); then
            return 1
        fi
        # Check for Update method signatures
        if echo "$cline" | grep -qE '\b(void\s+)(Update|FixedUpdate|LateUpdate)\s*\('; then
            return 0
        fi
        # Check for any other method signature (we left the Update method)
        if echo "$cline" | grep -qE '(void|int|float|bool|string|IEnumerator|async)\s+[A-Z][a-zA-Z0-9_]+\s*\('; then
            return 1
        fi
    done <<< "$context"
    return 1
}

# ---------------------------------------------------------------------------
# Helper: check if file is under an Editor folder
# ---------------------------------------------------------------------------
is_editor_file() {
    local file="$1"
    [[ "$file" == */Editor/* || "$file" == */Editor.* ]]
}

# ---------------------------------------------------------------------------
# Scan all .cs files
# ---------------------------------------------------------------------------
file_count=0
while IFS= read -r -d '' csfile; do
    ((file_count++))
    rel_path="${csfile#"$SCAN_DIR/"}"

    # --- 1. GetComponent in Update ---
    while IFS=: read -r lineno line; do
        [[ -z "$lineno" ]] && continue
        if is_in_update_method "$csfile" "$lineno"; then
            report "GetComponent-in-Update" "$rel_path" "$lineno" \
                "$(echo "$line" | sed 's/^[[:space:]]*//')" \
                "Cache GetComponent<T>() result in Awake() or Start() and store in a field."
        fi
    done < <(grep -n 'GetComponent\s*[<(]' "$csfile" 2>/dev/null || true)

    # --- 2. Camera.main uncached ---
    while IFS=: read -r lineno line; do
        [[ -z "$lineno" ]] && continue
        # Check it's not being assigned to a field (cached)
        trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
        if ! echo "$trimmed" | grep -qE '^\s*(private|protected|public|internal|static|readonly|\[)'; then
            report "Camera.main-uncached" "$rel_path" "$lineno" \
                "$trimmed" \
                "Cache Camera.main in a field: private Camera _mainCam; void Awake() => _mainCam = Camera.main;"
        fi
    done < <(grep -n 'Camera\.main' "$csfile" 2>/dev/null || true)

    # --- 3. FindObjectOfType in Update ---
    while IFS=: read -r lineno line; do
        [[ -z "$lineno" ]] && continue
        if is_in_update_method "$csfile" "$lineno"; then
            report "FindObjectOfType-in-Update" "$rel_path" "$lineno" \
                "$(echo "$line" | sed 's/^[[:space:]]*//')" \
                "Cache FindObjectOfType result in Awake()/Start(). This is extremely slow per frame."
        fi
    done < <(grep -n 'FindObjectsOfType\|FindObjectOfType' "$csfile" 2>/dev/null || true)

    # --- 4. Heap allocations in Update ---
    while IFS=: read -r lineno line; do
        [[ -z "$lineno" ]] && continue
        if is_in_update_method "$csfile" "$lineno"; then
            report "Heap-alloc-in-Update" "$rel_path" "$lineno" \
                "$(echo "$line" | sed 's/^[[:space:]]*//')" \
                "Move collection allocation out of Update. Use a field and .Clear() instead of new."
        fi
    done < <(grep -n 'new\s\+\(List\|Dictionary\|HashSet\)<' "$csfile" 2>/dev/null || true)

    # --- 5. String concatenation in Update ---
    while IFS=: read -r lineno line; do
        [[ -z "$lineno" ]] && continue
        if is_in_update_method "$csfile" "$lineno"; then
            # Look for string + string patterns (heuristic)
            if echo "$line" | grep -qE '"[^"]*"\s*\+|\+\s*"[^"]*"'; then
                report "String-concat-in-Update" "$rel_path" "$lineno" \
                    "$(echo "$line" | sed 's/^[[:space:]]*//')" \
                    "Use string interpolation (\$\"\") or StringBuilder instead of + concatenation in hot paths."
            fi
        fi
    done < <(grep -n '+' "$csfile" 2>/dev/null || true)

    # --- 6. tag == "..." instead of CompareTag ---
    while IFS=: read -r lineno line; do
        [[ -z "$lineno" ]] && continue
        report "tag-equality" "$rel_path" "$lineno" \
            "$(echo "$line" | sed 's/^[[:space:]]*//')" \
            "Use CompareTag(\"TagName\") instead of .tag == \"TagName\" to avoid GC allocation."
    done < <(grep -n '\.tag\s*==\s*"' "$csfile" 2>/dev/null || true)

    # --- 7. SendMessage / BroadcastMessage ---
    while IFS=: read -r lineno line; do
        [[ -z "$lineno" ]] && continue
        report "SendMessage-usage" "$rel_path" "$lineno" \
            "$(echo "$line" | sed 's/^[[:space:]]*//')" \
            "Replace SendMessage/BroadcastMessage with direct method calls, events, or UnityEvent."
    done < <(grep -n 'SendMessage\s*(\|BroadcastMessage\s*(' "$csfile" 2>/dev/null || true)

    # --- 8. Unguarded Debug.Log in non-Editor code ---
    if ! is_editor_file "$csfile"; then
        while IFS=: read -r lineno line; do
            [[ -z "$lineno" ]] && continue
            # Check if preceded by #if UNITY_EDITOR or [Conditional("...")]
            local_context=""
            if (( lineno > 3 )); then
                local_context=$(sed -n "$(( lineno - 3 )),${lineno}p" "$csfile" 2>/dev/null || true)
            else
                local_context=$(head -n "$lineno" "$csfile" 2>/dev/null || true)
            fi
            if ! echo "$local_context" | grep -qE '#if\s+UNITY_EDITOR|\[Conditional'; then
                report "Unguarded-Debug.Log" "$rel_path" "$lineno" \
                    "$(echo "$line" | sed 's/^[[:space:]]*//')" \
                    "Wrap in #if UNITY_EDITOR / #endif or use [Conditional(\"UNITY_EDITOR\")] to strip from builds."
            fi
        done < <(grep -n 'Debug\.Log\s*(' "$csfile" 2>/dev/null || true)
    fi

    # --- 9. foreach on arrays in Update (pre-2021 issue) ---
    while IFS=: read -r lineno line; do
        [[ -z "$lineno" ]] && continue
        if is_in_update_method "$csfile" "$lineno"; then
            report "foreach-array-in-Update" "$rel_path" "$lineno" \
                "$(echo "$line" | sed 's/^[[:space:]]*//')" \
                "Use a for loop instead of foreach on arrays in Update to avoid enumerator allocation (pre-Unity 2021)."
        fi
    done < <(grep -n 'foreach\s*(' "$csfile" 2>/dev/null || true)

done < <(find "$SCAN_DIR" -name '*.cs' -not -path '*/.git/*' -print0 2>/dev/null)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "${BOLD}=== Summary ===${RESET}"
echo "  Files scanned: $file_count"
echo ""

has_issues=false
for cat in "${CATEGORIES[@]}"; do
    count=${COUNTS["$cat"]}
    if (( count > 0 )); then
        echo "  ${YELLOW}${cat}${RESET}: $count"
        has_issues=true
    fi
done

echo ""
echo "  Total issues: $total_issues"

if $has_issues; then
    echo ""
    echo "${YELLOW}${BOLD}WARNINGS FOUND${RESET} - $total_issues issue(s) detected. Review and fix as needed."
    exit 1
else
    echo ""
    echo "${GREEN}${BOLD}CLEAN${RESET} - No code quality issues detected."
    exit 0
fi
