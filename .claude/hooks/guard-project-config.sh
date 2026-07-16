#!/usr/bin/env bash
# ============================================================================
# guard-project-config.sh — BLOCKING HOOK (standard profile)
# Prevents modification of project configuration files that enforce code
# quality rules. Forces the agent to fix code to meet existing rules rather
# than weakening the rules to match problematic code.
#
# Protected files:
#   - .editorconfig
#   - *.ruleset, *.globalconfig
#   - Directory.Build.props (analyzer severity sections)
#   - *.csproj (analyzer/NoWarn sections only)
# ============================================================================
# Trigger: PreToolUse on Edit|Write
# Exit: 2 = block, 0 = allow
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

BASENAME=$(basename "$FILE_PATH")

# Block edits to code quality configuration files
case "$BASENAME" in
    .editorconfig|.eslintrc|.eslintrc.json|.eslintrc.js|.eslintrc.yml)
        echo "" >&2
        echo "  BLOCKED: Modifying code quality rules" >&2
        echo "  File: $FILE_PATH" >&2
        echo "" >&2
        echo "  This file defines code quality standards for the project." >&2
        echo "  Fix the code to comply with the rules instead of weakening them." >&2
        unity_hook_block "Modifying code quality config is not allowed. Fix the code instead."
        ;;
    .globalconfig)
        echo "" >&2
        echo "  BLOCKED: Modifying analyzer global config" >&2
        echo "  File: $FILE_PATH" >&2
        echo "  Fix the code rather than suppressing analyzer warnings." >&2
        unity_hook_block "Modifying analyzer globalconfig is not allowed. Fix the code instead."
        ;;
esac

# Block ruleset files by extension
case "$BASENAME" in
    *.ruleset)
        echo "" >&2
        echo "  BLOCKED: Modifying analyzer ruleset" >&2
        echo "  File: $FILE_PATH" >&2
        echo "  Fix the code rather than changing analyzer rules." >&2
        unity_hook_block "Modifying analyzer rulesets is not allowed. Fix the code instead."
        ;;
esac

# Block analyzer severity changes in Directory.Build.props
if [ "$BASENAME" = "Directory.Build.props" ]; then
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty')
    if echo "$CONTENT" | grep -qiE '(NoWarn|WarningsAsErrors|TreatWarningsAsErrors|Severity)'; then
        echo "" >&2
        echo "  BLOCKED: Modifying analyzer severity in Directory.Build.props" >&2
        echo "  Fix the code instead of suppressing warnings." >&2
        unity_hook_block "Modifying analyzer severity in Directory.Build.props is blocked. Fix the code instead."
    fi
fi

# Block analyzer settings in .csproj files
case "$BASENAME" in
    *.csproj)
        CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty')
        if echo "$CONTENT" | grep -qiE '(NoWarn|RuleSet|AnalyzerConfig|CodeAnalysis)'; then
            echo "" >&2
            echo "  BLOCKED: Modifying analyzer settings in .csproj" >&2
            echo "  Fix the code rather than disabling analyzers." >&2
            unity_hook_block "Modifying analyzer settings in .csproj files is blocked. Fix the code instead."
        fi
        ;;
esac

exit 0
