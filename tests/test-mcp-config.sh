#!/usr/bin/env bash
# ============================================================================
# test-mcp-config.sh — the MCP config must land where Claude Code reads it.
#
# The toolkit shipped mcpServers inside .claude/settings.json, which Claude
# Code ignores: `claude mcp list` reported no servers in a freshly installed
# project, so every unity-* agent had no tools to call. Project-scoped MCP
# servers are configured in .mcp.json at the project root.
# ============================================================================

TMC_MOCK="/tmp/kinglet-mcp-config-$$"
mkdir -p "${TMC_MOCK}/Assets/Scripts" "${TMC_MOCK}/ProjectSettings" "${TMC_MOCK}/Packages"
printf 'm_EditorVersion: 6000.3.18f1\nm_EditorVersionWithRevision: 6000.3.18f1 (abcdef123456)\n' \
    > "${TMC_MOCK}/ProjectSettings/ProjectVersion.txt"
printf '{\n  "dependencies": {\n    "com.unity.ugui": "1.0.0"\n  }\n}\n' \
    > "${TMC_MOCK}/Packages/manifest.json"

bash "${REPO_DIR}/install.sh" --project-dir "$TMC_MOCK" > /dev/null 2>&1 || true

assert_file_exists "${TMC_MOCK}/.mcp.json" "install writes .mcp.json at the project root"

TMC_JSON=$(cat "${TMC_MOCK}/.mcp.json" 2>/dev/null || echo "")
assert_contains "$TMC_JSON" "unityMCP" ".mcp.json names the unityMCP server"
assert_contains "$TMC_JSON" "localhost:8080/mcp" ".mcp.json carries the bridge URL"

# The inert key must be gone, or a reader will believe it does something.
TMC_SETTINGS=$(cat "${TMC_MOCK}/.claude/settings.json" 2>/dev/null || echo "")
assert_not_contains "$TMC_SETTINGS" "mcpServers" \
    "settings.json no longer carries an mcpServers key Claude Code ignores"

# The receipt must own it, or uninstall cannot remove it.
TMC_RECEIPT=$(cat "${TMC_MOCK}/.claude/state/install-receipt.tsv" 2>/dev/null || echo "")
assert_contains "$TMC_RECEIPT" ".mcp.json" "the receipt records .mcp.json"

# Direct field-structure assertion — not incidental. A tab written as a literal `\t` inside double
# quotes (instead of an actual tab character) produces a row that "contains .mcp.json" as a string
# and would still pass the assert_contains above, but splits into one field, not four, and
# uninstall.sh's `IFS=$'\t' read` then never matches it against any project path. This is the
# assertion that catches that bug directly, at the row itself, instead of three steps downstream
# in whichever uninstall assertion happens to depend on the row being well-formed.
TMC_RECEIPT_LINE=$(awk -F'\t' '$1 == ".mcp.json" {print; exit}' \
    "${TMC_MOCK}/.claude/state/install-receipt.tsv" 2>/dev/null || echo "")
TMC_FIELD_COUNT=$(printf '%s' "$TMC_RECEIPT_LINE" | awk -F'\t' '{print NF}')
assert_eq "4" "$TMC_FIELD_COUNT" \
    "the .mcp.json receipt row splits into exactly 4 tab-separated fields (path, sha256, mode, origin)"

IFS=$'\t' read -r TMC_RECEIPT_PATH TMC_RECEIPT_SHA TMC_RECEIPT_MODE TMC_RECEIPT_ORIGIN <<EOF
$TMC_RECEIPT_LINE
EOF
assert_eq ".mcp.json" "$TMC_RECEIPT_PATH" "the .mcp.json receipt row's first field is exactly the path"

# An existing .mcp.json belongs to the user and is not overwritten.
rm -rf "$TMC_MOCK/.claude" "$TMC_MOCK/.mcp.json"
printf '{"mcpServers":{"mine":{"type":"http","url":"http://localhost:9999/mcp"}}}\n' \
    > "${TMC_MOCK}/.mcp.json"
bash "${REPO_DIR}/install.sh" --project-dir "$TMC_MOCK" > /dev/null 2>&1 || true
TMC_EXISTING=$(cat "${TMC_MOCK}/.mcp.json")
assert_contains "$TMC_EXISTING" "localhost:9999" "an existing .mcp.json keeps the user's server"

# uninstall.sh is receipt-driven: verify it actually removes .mcp.json when unchanged, and
# leaves it when the user edited it — rather than assuming the existing logic covers a new row.
rm -rf "$TMC_MOCK/.claude" "$TMC_MOCK/.mcp.json"
bash "${REPO_DIR}/install.sh" --project-dir "$TMC_MOCK" --yes > /dev/null 2>&1 || true
bash "${REPO_DIR}/uninstall.sh" --project-dir "$TMC_MOCK" --yes --no-backup > /dev/null 2>&1 || true
if [ -f "${TMC_MOCK}/.mcp.json" ]; then TMC_UNINSTALL_REMOVED=1; else TMC_UNINSTALL_REMOVED=0; fi
assert_eq "0" "$TMC_UNINSTALL_REMOVED" "uninstall removes an unchanged .mcp.json"

rm -rf "$TMC_MOCK/.claude"
bash "${REPO_DIR}/install.sh" --project-dir "$TMC_MOCK" --yes > /dev/null 2>&1 || true
printf '{"mcpServers":{"unityMCP":{"type":"http","url":"http://localhost:8080/mcp"},"extra":{"type":"http","url":"http://localhost:1/mcp"}}}\n' \
    > "${TMC_MOCK}/.mcp.json"
bash "${REPO_DIR}/uninstall.sh" --project-dir "$TMC_MOCK" --yes --no-backup > /dev/null 2>&1 || true
assert_file_exists "${TMC_MOCK}/.mcp.json" "uninstall leaves a user-modified .mcp.json in place"

rm -rf "$TMC_MOCK"
