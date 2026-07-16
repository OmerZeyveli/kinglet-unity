#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# validate-architecture.sh
# Checks Model-View-System (MVS) architecture compliance via grep-based
# static analysis. Detects violations of dependency direction, forbidden
# patterns (singletons, coroutines), and injection misuse.
#
# Usage:
#   ./scripts/validate-architecture.sh [--path <dir>]
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
${BOLD}validate-architecture.sh${RESET} - MVS architecture compliance checker.

${BOLD}Usage:${RESET}
  ./scripts/validate-architecture.sh [OPTIONS]

${BOLD}Options:${RESET}
  --path <dir>   Directory to scan (default: Assets/ under Unity project root)
  -h, --help     Show this help

${BOLD}What it checks:${RESET}
  1. Models don't reference Views, Systems, or MonoBehaviour
  2. Systems don't reference Views or MonoBehaviour
  3. No singleton patterns (static Instance, FindObjectOfType)
  4. No coroutines (StartCoroutine, IEnumerator, yield return)
  5. Correct injection patterns (method for MonoBehaviour, constructor for Systems)

${BOLD}Note:${RESET}
  This is heuristic-based (grep). It may produce false positives.
  Add "// architecture:ignore" on any line to suppress a warning for that line.
EOF
    exit 0
fi

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
SCAN_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path) SCAN_PATH="$2"; shift 2 ;;
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
# Counters
# ---------------------------------------------------------------------------
ERRORS=0
WARNINGS=0

report_issue() {
    local severity="$1" file="$2" line="$3" message="$4"
    if [[ "$severity" == "ERROR" ]]; then
        echo "${RED}ERROR${RESET}: ${BOLD}$file:$line${RESET} — $message"
        ERRORS=$((ERRORS + 1))
    else
        echo "${YELLOW}WARNING${RESET}: ${BOLD}$file:$line${RESET} — $message"
        WARNINGS=$((WARNINGS + 1))
    fi
}

# ---------------------------------------------------------------------------
# Check 1: Models must not reference Views or Systems
# ---------------------------------------------------------------------------
echo "${BOLD}${CYAN}[1/5] Checking Model dependency direction...${RESET}"

MODEL_FILES=$(find "$SCAN_PATH" -name "*Model.cs" -o -name "*Model[0-9]*.cs" | grep -v '/Editor/' | grep -v '/Tests/' || true)

while IFS= read -r FILE; do
    [[ -z "$FILE" ]] && continue

    # Check for MonoBehaviour inheritance (Models should be pure C#)
    LINE_NUM=$(grep -nE ':\s*MonoBehaviour' "$FILE" | grep -v 'architecture:ignore' | head -1 | cut -d: -f1 || true)
    if [[ -n "$LINE_NUM" ]]; then
        report_issue "ERROR" "$FILE" "$LINE_NUM" "Model inherits MonoBehaviour — Models must be pure C# classes"
    fi

    # Check for View references
    LINE_NUM=$(grep -nE '\bI?\w+View\b' "$FILE" | grep -v '^\s*//' | grep -v 'architecture:ignore' | head -1 | cut -d: -f1 || true)
    if [[ -n "$LINE_NUM" ]]; then
        report_issue "ERROR" "$FILE" "$LINE_NUM" "Model references a View — Models must not depend on Views"
    fi

    # Check for System references (but allow the word "System" in using statements)
    LINE_NUM=$(grep -nE '\b\w+System\b' "$FILE" | grep -v '^\s*using' | grep -v '^\s*//' | grep -v 'architecture:ignore' | grep -v 'IDisposable' | head -1 | cut -d: -f1 || true)
    if [[ -n "$LINE_NUM" ]]; then
        report_issue "WARNING" "$FILE" "$LINE_NUM" "Model may reference a System — check dependency direction"
    fi
done <<< "$MODEL_FILES"
echo ""

# ---------------------------------------------------------------------------
# Check 2: Systems must not reference Views
# ---------------------------------------------------------------------------
echo "${BOLD}${CYAN}[2/5] Checking System dependency direction...${RESET}"

SYSTEM_FILES=$(find "$SCAN_PATH" -name "*System.cs" -o -name "*System[0-9]*.cs" | grep -v '/Editor/' | grep -v '/Tests/' || true)

while IFS= read -r FILE; do
    [[ -z "$FILE" ]] && continue

    # Check for MonoBehaviour inheritance
    LINE_NUM=$(grep -nE ':\s*MonoBehaviour' "$FILE" | grep -v 'architecture:ignore' | head -1 | cut -d: -f1 || true)
    if [[ -n "$LINE_NUM" ]]; then
        report_issue "ERROR" "$FILE" "$LINE_NUM" "System inherits MonoBehaviour — Systems must be plain C# classes"
    fi

    # Check for View references
    LINE_NUM=$(grep -nE '\bI?\w+View\b' "$FILE" | grep -v '^\s*//' | grep -v 'architecture:ignore' | head -1 | cut -d: -f1 || true)
    if [[ -n "$LINE_NUM" ]]; then
        report_issue "ERROR" "$FILE" "$LINE_NUM" "System references a View — Systems must not depend on Views"
    fi
done <<< "$SYSTEM_FILES"
echo ""

# ---------------------------------------------------------------------------
# Check 3: No singletons
# ---------------------------------------------------------------------------
echo "${BOLD}${CYAN}[3/5] Checking for singleton patterns...${RESET}"

ALL_CS=$(find "$SCAN_PATH" -name "*.cs" -not -path "*/Editor/*" -not -path "*/Tests/*" 2>/dev/null || true)

while IFS= read -r FILE; do
    [[ -z "$FILE" ]] && continue

    # Skip LifetimeScope files (they are the DI containers)
    case "$FILE" in *LifetimeScope* | *Scope*) continue ;; esac

    # Static Instance pattern
    LINE_NUM=$(grep -nE 'static\s+\w+\s+Instance\b' "$FILE" | grep -v 'architecture:ignore' | head -1 | cut -d: -f1 || true)
    if [[ -n "$LINE_NUM" ]]; then
        report_issue "WARNING" "$FILE" "$LINE_NUM" "Singleton pattern detected (static Instance) — use VContainer registration instead"
    fi

    # FindObjectOfType outside of tests
    LINE_NUM=$(grep -nE 'FindObjectOfType|FindObjectsOfType|FindFirstObjectByType' "$FILE" | grep -v 'architecture:ignore' | head -1 | cut -d: -f1 || true)
    if [[ -n "$LINE_NUM" ]]; then
        report_issue "WARNING" "$FILE" "$LINE_NUM" "FindObjectOfType usage — use VContainer injection instead"
    fi

    # DontDestroyOnLoad outside LifetimeScope
    LINE_NUM=$(grep -nE 'DontDestroyOnLoad' "$FILE" | grep -v 'architecture:ignore' | head -1 | cut -d: -f1 || true)
    if [[ -n "$LINE_NUM" ]]; then
        report_issue "WARNING" "$FILE" "$LINE_NUM" "DontDestroyOnLoad — prefer bootstrapper scene with RootLifetimeScope"
    fi
done <<< "$ALL_CS"
echo ""

# ---------------------------------------------------------------------------
# Check 4: No coroutines
# ---------------------------------------------------------------------------
echo "${BOLD}${CYAN}[4/5] Checking for coroutine usage...${RESET}"

while IFS= read -r FILE; do
    [[ -z "$FILE" ]] && continue

    LINE_NUM=$(grep -nE 'StartCoroutine|StopCoroutine|StopAllCoroutines' "$FILE" | grep -v 'architecture:ignore' | head -1 | cut -d: -f1 || true)
    if [[ -n "$LINE_NUM" ]]; then
        report_issue "WARNING" "$FILE" "$LINE_NUM" "Coroutine usage — use UniTask for all async work"
    fi

    LINE_NUM=$(grep -nE 'IEnumerator\b.*\(' "$FILE" | grep -v 'architecture:ignore' | grep -v '^\s*//' | head -1 | cut -d: -f1 || true)
    if [[ -n "$LINE_NUM" ]]; then
        report_issue "WARNING" "$FILE" "$LINE_NUM" "IEnumerator method (likely coroutine) — use async UniTask instead"
    fi

    LINE_NUM=$(grep -nE 'yield\s+return' "$FILE" | grep -v 'architecture:ignore' | head -1 | cut -d: -f1 || true)
    if [[ -n "$LINE_NUM" ]]; then
        report_issue "WARNING" "$FILE" "$LINE_NUM" "yield return (coroutine) — use UniTask.Delay, UniTask.WaitUntil, etc."
    fi
done <<< "$ALL_CS"
echo ""

# ---------------------------------------------------------------------------
# Check 5: Injection patterns
# ---------------------------------------------------------------------------
echo "${BOLD}${CYAN}[5/5] Checking injection patterns...${RESET}"

while IFS= read -r FILE; do
    [[ -z "$FILE" ]] && continue

    # Check MonoBehaviours using [Inject] on fields (should use Construct method)
    if grep -qE ':\s*MonoBehaviour' "$FILE"; then
        LINE_NUM=$(grep -nE '^\s*\[Inject\]\s*$' "$FILE" | head -1 | cut -d: -f1 || true)
        if [[ -n "$LINE_NUM" ]]; then
            # Check if the next line is a field (not a method)
            NEXT_LINE=$(sed -n "$((LINE_NUM + 1))p" "$FILE" 2>/dev/null || true)
            if echo "$NEXT_LINE" | grep -qE '^\s*(private|public|protected|internal)\s+\w+\s+\w+\s*;'; then
                report_issue "WARNING" "$FILE" "$LINE_NUM" "Field injection on MonoBehaviour — use [Inject] method injection (Construct pattern)"
            fi
        fi
    fi
done <<< "$ALL_CS"
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "═══════════════════════════════════════════════════════════════"
TOTAL=$((ERRORS + WARNINGS))
if [[ $TOTAL -eq 0 ]]; then
    echo "${GREEN}${BOLD}Architecture check passed.${RESET} No issues found."
else
    echo "${BOLD}Architecture check: ${RED}$ERRORS error(s)${RESET}, ${YELLOW}$WARNINGS warning(s)${RESET}"
    if [[ $ERRORS -gt 0 ]]; then
        echo "Errors indicate MVS pattern violations that should be fixed."
    fi
    echo ""
    echo "Suppress false positives by adding ${CYAN}// architecture:ignore${RESET} to the line."
fi
echo "═══════════════════════════════════════════════════════════════"

exit 0
