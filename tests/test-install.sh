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
    echo -e "  ${GREEN}PASS${NC} agents installed (${AGENT_COUNT} found)"
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
    echo -e "  ${GREEN}PASS${NC} commands installed (${CMD_COUNT} found)"
else
    FAIL=$((FAIL + 1))
    echo -e "  ${RED}FAIL${NC} no command files found after install"
fi

# Verify CLAUDE.md was generated
assert_file_exists "${MOCK_DIR}/CLAUDE.md" "install generates CLAUDE.md"

# --- Test: .gitignore matches a realistic uninstall backup path (Defect 8) ---
# uninstall.sh writes .claude.backup.<timestamp>/ at the project root. The .gitignore entries the
# installer adds must match that path, or the backup shows up as untracked and dirties the user's
# git status in their own repository.
BACKUP_SAMPLE="${MOCK_DIR}/.claude.backup.20260101120000"
mkdir -p "$BACKUP_SAMPLE"
if command -v git >/dev/null 2>&1; then
    ( cd "$MOCK_DIR" && git init -q . ) 2>/dev/null
    IGNORE_EXIT=0
    ( cd "$MOCK_DIR" && git check-ignore -q ".claude.backup.20260101120000/" ) || IGNORE_EXIT=$?
    assert_eq "0" "$IGNORE_EXIT" ".gitignore matches a realistic uninstall backup path"
else
    assert_contains "$(cat "${MOCK_DIR}/.gitignore" 2>/dev/null)" ".claude.backup" ".gitignore has a pattern for backup dirs (no git available)"
fi
rm -rf "$BACKUP_SAMPLE"

# --- Test: next-steps message follows the CLAUDE.md branch actually taken (Defect 9) ---
# Fresh mock project without an existing CLAUDE.md: install writes CLAUDE.md directly, so telling
# the user to edit CLAUDE.md is correct here.
assert_contains "$INSTALL_OUTPUT" "CLAUDE.md" "next steps mention CLAUDE.md when it was freshly generated"

# --- Test: a project that already has a CLAUDE.md gets CLAUDE.md.generated, and the message says so ---
MOCK_DIR2="/tmp/unity-test-mock-existing-claudemd-$$"
mkdir -p "${MOCK_DIR2}/Assets/Scripts"
mkdir -p "${MOCK_DIR2}/ProjectSettings"
mkdir -p "${MOCK_DIR2}/Packages"
echo "m_EditorVersion: 2022.3.20f1" > "${MOCK_DIR2}/ProjectSettings/ProjectVersion.txt"
cat > "${MOCK_DIR2}/Packages/manifest.json" << 'MANIFEST2'
{
  "dependencies": {
    "com.unity.ugui": "1.0.0"
  }
}
MANIFEST2
cat > "${MOCK_DIR2}/CLAUDE.md" << 'EXISTINGCLAUDEMD'
# My Own Project Notes

This project already has its own CLAUDE.md with no generated markers.
EXISTINGCLAUDEMD

INSTALL_OUTPUT2=$(bash "$INSTALL_SCRIPT" --project-dir "$MOCK_DIR2" 2>&1) || true

assert_file_exists "${MOCK_DIR2}/CLAUDE.md.generated" "install writes CLAUDE.md.generated when a CLAUDE.md already exists without markers"
assert_contains "$INSTALL_OUTPUT2" "CLAUDE.md.generated" "next steps name CLAUDE.md.generated when that is the branch taken"
assert_not_contains "$INSTALL_OUTPUT2" "Fill in the FILL: markers in CLAUDE.md —" "next steps do not tell the user to edit CLAUDE.md when it was left untouched"

rm -rf "$MOCK_DIR2"

# --- Test: an approved provider declaration survives a --yes refresh ---------
#
# PROVIDER_CHOICE was set only on the interactive branch, so --yes or a non-tty took
# "the safe default (no provider declaration)" even when the provider was still installed
# and already approved. emit_provider_verdict lives inside the marked region, so the
# --facts-only refresh rewrote that region without the sentence and deleted it — and
# studio-doctor.sh's remedy is literally "Re-run install.sh to refresh the declaration".
#
# The runner runs test files with stdin at /dev/null, so [ ! -t 0 ] is true here and this
# exercises the non-tty path even without --yes. --yes is passed anyway; both are the
# same branch.
MOCK_DIR3="/tmp/unity-test-provider-$$"
mkdir -p "${MOCK_DIR3}/Assets/Scripts" "${MOCK_DIR3}/ProjectSettings" "${MOCK_DIR3}/Packages"
echo "m_EditorVersion: 6000.0.23f1" > "${MOCK_DIR3}/ProjectSettings/ProjectVersion.txt"
printf '{\n  "dependencies": {\n    "com.unity.ugui": "1.0.0"\n  }\n}\n' > "${MOCK_DIR3}/Packages/manifest.json"

# A user settings file that reports the provider as installed and enabled.
FAKE_USER_SETTINGS="/tmp/unity-test-provider-settings-$$.json"
printf '{"enabledPlugins": {"superpowers@claude-plugins-official": true}}' > "$FAKE_USER_SETTINGS"

# The state after an install the user approved: an authentic generated document carrying
# the declaration inside the markers. Written by the one producer of that region.
bash "${REPO_DIR}/scripts/generate-claude-md.sh" --provider superpowers "$MOCK_DIR3" \
    > "${MOCK_DIR3}/CLAUDE.md" 2>/dev/null

KINGLET_USER_SETTINGS="$FAKE_USER_SETTINGS" \
    bash "$INSTALL_SCRIPT" --project-dir "$MOCK_DIR3" --yes > /dev/null 2>&1 || true

PROVIDER_MD3=$(cat "${MOCK_DIR3}/CLAUDE.md" 2>/dev/null || true)
assert_contains "$PROVIDER_MD3" 'owned by `superpowers`' \
    "an approved provider declaration survives a --yes refresh"
assert_contains "$PROVIDER_MD3" "### Process provider" \
    "the Process provider heading survives a --yes refresh"

# Negative control: with no prior declaration, --yes must still NOT invent one. Without
# this, the assertion above would also pass if the installer simply always declared.
MOCK_DIR4="/tmp/unity-test-noprovider-$$"
mkdir -p "${MOCK_DIR4}/Assets/Scripts" "${MOCK_DIR4}/ProjectSettings" "${MOCK_DIR4}/Packages"
echo "m_EditorVersion: 6000.0.23f1" > "${MOCK_DIR4}/ProjectSettings/ProjectVersion.txt"
printf '{\n  "dependencies": {\n    "com.unity.ugui": "1.0.0"\n  }\n}\n' > "${MOCK_DIR4}/Packages/manifest.json"

KINGLET_USER_SETTINGS="$FAKE_USER_SETTINGS" \
    bash "$INSTALL_SCRIPT" --project-dir "$MOCK_DIR4" --yes > /dev/null 2>&1 || true

PROVIDER_MD4=$(cat "${MOCK_DIR4}/CLAUDE.md" 2>/dev/null || true)
assert_not_contains "$PROVIDER_MD4" "### Process provider" \
    "--yes still declares no provider when the project never approved one"

rm -rf "$MOCK_DIR3" "$MOCK_DIR4" "$FAKE_USER_SETTINGS"

# --- Cleanup ---
rm -rf "$MOCK_DIR"
