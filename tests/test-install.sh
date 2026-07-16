#!/usr/bin/env bash
# ============================================================================
# test-install.sh — Tests for install.sh
# Creates a mock Unity project, runs install.sh, verifies results.
# ============================================================================

MOCK_DIR="/tmp/unity-test-mock-$$"
INSTALL_SCRIPT="${REPO_DIR}/install.sh"

# --- Setup: create mock Unity project ---
mkdir -p "${MOCK_DIR}/Assets/Scripts"
mkdir -p "${MOCK_DIR}/ProjectSettings"
mkdir -p "${MOCK_DIR}/Packages"

# Create minimal ProjectVersion.txt
echo "m_EditorVersion: 2022.3.20f1" > "${MOCK_DIR}/ProjectSettings/ProjectVersion.txt"

# Create minimal manifest.json
cat > "${MOCK_DIR}/Packages/manifest.json" << 'MANIFEST'
{
  "dependencies": {
    "com.unity.ugui": "1.0.0"
  }
}
MANIFEST

# --- Test: install.sh exists and is executable ---
assert_file_exists "$INSTALL_SCRIPT" "install.sh exists"
assert_file_executable "$INSTALL_SCRIPT" "install.sh is executable"

# --- Test: install into mock project ---
INSTALL_OUTPUT=$(bash "$INSTALL_SCRIPT" --project-dir "$MOCK_DIR" 2>&1) || true

# Verify .claude directory was created
assert_file_exists "${MOCK_DIR}/.claude" "install creates .claude directory"

# Verify subdirectories
assert_file_exists "${MOCK_DIR}/.claude/agents" "install creates agents directory"
assert_file_exists "${MOCK_DIR}/.claude/commands" "install creates commands directory"
assert_file_exists "${MOCK_DIR}/.claude/hooks" "install creates hooks directory"
assert_file_exists "${MOCK_DIR}/.claude/skills" "install creates skills directory"
assert_file_exists "${MOCK_DIR}/.claude/rules" "install creates rules directory"

# Verify hooks are executable
if [ -d "${MOCK_DIR}/.claude/hooks" ]; then
    HOOK_COUNT=$(find "${MOCK_DIR}/.claude/hooks" -name "*.sh" -type f | wc -l | tr -d ' ')
    if [ "$HOOK_COUNT" -gt 0 ]; then
        NON_EXEC=$(find "${MOCK_DIR}/.claude/hooks" -name "*.sh" -type f ! -perm -u+x | wc -l | tr -d ' ')
        assert_eq "0" "$NON_EXEC" "all hook scripts are executable"
    else
        skip_test "no hook scripts found to check permissions"
    fi
else
    skip_test "hooks directory not found"
fi

# Verify settings.json was copied
assert_file_exists "${MOCK_DIR}/.claude/settings.json" "install copies settings.json"

# Verify settings.json is valid JSON
if [ -f "${MOCK_DIR}/.claude/settings.json" ]; then
    JQ_EXIT=0
    jq . "${MOCK_DIR}/.claude/settings.json" > /dev/null 2>&1 || JQ_EXIT=$?
    assert_eq "0" "$JQ_EXIT" "installed settings.json is valid JSON"
fi

# Verify VERSION file
assert_file_exists "${MOCK_DIR}/.claude/VERSION" "install copies VERSION file"

# Verify _lib.sh exists
assert_file_exists "${MOCK_DIR}/.claude/hooks/_lib.sh" "install copies _lib.sh"

# Verify at least one agent exists
AGENT_COUNT=0
if [ -d "${MOCK_DIR}/.claude/agents" ]; then
    AGENT_COUNT=$(find "${MOCK_DIR}/.claude/agents" -name "*.md" -type f | wc -l | tr -d ' ')
fi
if [ "$AGENT_COUNT" -gt 0 ]; then
    PASS=$((PASS + 1))
    if [ "$VERBOSE" = "--verbose" ]; then
        echo -e "  ${GREEN}PASS${NC} agents installed (${AGENT_COUNT} found)"
    fi
else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC} no agent files found after install"
fi

# Verify at least one command exists
CMD_COUNT=0
if [ -d "${MOCK_DIR}/.claude/commands" ]; then
    CMD_COUNT=$(find "${MOCK_DIR}/.claude/commands" -name "*.md" -type f | wc -l | tr -d ' ')
fi
if [ "$CMD_COUNT" -gt 0 ]; then
    PASS=$((PASS + 1))
    if [ "$VERBOSE" = "--verbose" ]; then
        echo -e "  ${GREEN}PASS${NC} commands installed (${CMD_COUNT} found)"
    fi
else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC} no command files found after install"
fi

# Verify CLAUDE.md was generated
assert_file_exists "${MOCK_DIR}/CLAUDE.md" "install generates CLAUDE.md"

# --- Cleanup ---
rm -rf "$MOCK_DIR"
