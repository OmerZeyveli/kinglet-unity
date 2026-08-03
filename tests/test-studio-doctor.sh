#!/usr/bin/env bash
# ============================================================================
# test-studio-doctor.sh — studio-doctor.sh must not stop halfway and call it
# success.
#
# read_mcp_url() used to end its `for` loop with a bare `[ -n "$url" ] && { ... }`.
# When nothing matched, that was the function's exit status — 1 — and
# `MCP_URL=$(read_mcp_url)` killed the whole script under `set -e` after only two
# checks. It then exited 0, certifying a project it had examined a fraction of.
#
# This got triggered by Task 2 moving mcpServers out of .claude/settings.json
# (which Claude Code never read) into .mcp.json — read_mcp_url only knew about
# the settings files, so the lookup started failing on every run.
# ============================================================================

TSD_DOCTOR="${REPO_DIR}/scripts/studio-doctor.sh"
TSD_MOCK="/tmp/kinglet-studio-doctor-$$"

assert_file_exists "$TSD_DOCTOR" "studio-doctor.sh exists"

bash "${REPO_DIR}/tests/fixtures/mkproject.sh" "$TSD_MOCK" --variant urp > /dev/null 2>&1
bash "${REPO_DIR}/install.sh" --project-dir "$TSD_MOCK" --yes > /dev/null 2>&1

# --- A direct assertion on the cause, not only the symptom ------------------
#
# Call read_mcp_url in isolation, in a subshell, with no config present at all — no
# settings.local.json, no settings.json, no .mcp.json. If the fall-through ever comes back
# (the next refactor reintroduces it), this is the assertion that catches it at the source,
# instead of three indirect steps downstream via the full-script assertions below.
TSD_RMU_SRC=$(sed -n '/^read_mcp_url() {/,/^}/p' "$TSD_DOCTOR")
TSD_EMPTY_DIR="/tmp/kinglet-studio-doctor-empty-$$"
mkdir -p "$TSD_EMPTY_DIR"
# settings.json present but empty of mcpServers, and no .mcp.json at all — the loop runs to
# completion, finds files, but never finds a url. This is the exact shape that used to return 1:
# a bare "no file at all" directory would fall through to `continue` and return 0 by accident,
# which would pass this assertion for the wrong reason even with the old, buggy function.
printf '{}' > "${TSD_EMPTY_DIR}/settings.json"
TSD_RMU_OUT=$(bash -c "
$TSD_RMU_SRC
CLAUDE_DIR='$TSD_EMPTY_DIR'
PROJECT_DIR='$TSD_EMPTY_DIR'
PY=''
read_mcp_url
printf 'RC=%s' \"\$?\"
")
assert_eq "RC=0" "$TSD_RMU_OUT" \
    "read_mcp_url returns 0 when it finds nothing (no config present at all)"
rm -rf "$TSD_EMPTY_DIR"

# --- Full script, healthy project: must reach the summary line and exit 0 ---
TSD_HEALTHY_OUT=$(bash "$TSD_DOCTOR" --project-dir "$TSD_MOCK" 2>&1)
TSD_HEALTHY_RC=$?

assert_contains "$TSD_HEALTHY_OUT" "passed ·" \
    "studio-doctor reaches its summary line on a healthy install (not just the first two checks)"

# It must report ON the bridge, not silently skip it because the URL couldn't be found — now
# that the URL lives in .mcp.json (written by install.sh), not in settings.json.
assert_not_contains "$TSD_HEALTHY_OUT" "No mcpServers.unityMCP.url in settings — skipped the bridge check." \
    "studio-doctor finds the MCP URL in .mcp.json instead of reporting it missing"
assert_contains "$TSD_HEALTHY_OUT" "localhost:8080/mcp" \
    "studio-doctor's bridge check actually used the configured URL"

assert_eq "0" "$TSD_HEALTHY_RC" "studio-doctor exits 0 on a healthy, freshly installed project"

# --- A genuine failure must still exit non-zero -----------------------------
#
# This is the half of the fix that matters more than it looks: "always exit 0" would satisfy
# the assertion above completely while being a worse bug than the one being fixed. Break the
# install by deleting a receipted file and confirm the health check actually notices.
rm -f "${TSD_MOCK}/.claude/NOTICE.md"
TSD_BROKEN_OUT=$(bash "$TSD_DOCTOR" --project-dir "$TSD_MOCK" 2>&1)
TSD_BROKEN_RC=$?

assert_contains "$TSD_BROKEN_OUT" "passed ·" \
    "studio-doctor still reaches its summary line on a broken install"
assert_contains "$TSD_BROKEN_OUT" "NOTICE.md missing" \
    "studio-doctor actually reports the induced failure"
if [ "$TSD_BROKEN_RC" -ne 0 ]; then TSD_BROKEN_NONZERO=1; else TSD_BROKEN_NONZERO=0; fi
assert_eq "1" "$TSD_BROKEN_NONZERO" "studio-doctor exits non-zero when a check genuinely fails"

# ── A declared provider that is not installed is a WARN, not a FAIL ────────
echo ""
echo "--- Test: stale provider declaration ---"
TSD_STALE="/tmp/kinglet-doctor-stale-$$"
bash "${REPO_DIR}/tests/fixtures/mkproject.sh" "$TSD_STALE" --variant urp >/dev/null
bash "${REPO_DIR}/install.sh" --project-dir "$TSD_STALE" --yes >/dev/null 2>&1
printf '\n### Process provider\n\nDiscovery and written planning in this project are owned by `superpowers`.\n' \
  >> "$TSD_STALE/CLAUDE.md"

TSD_STALE_OUT="$(KINGLET_USER_SETTINGS=/nonexistent-on-purpose \
  bash "$TSD_DOCTOR" --project-dir "$TSD_STALE" 2>&1 || true)"
assert_contains "$TSD_STALE_OUT" "superpowers" \
    "doctor names the declared provider"
assert_contains "$TSD_STALE_OUT" "this project's process provider, but it is not" \
    "doctor says the declared provider is not installed"
assert_contains "$TSD_STALE_OUT" "deep-interview" \
    "doctor names the built-in fallback"
rm -rf "$TSD_STALE"

# ── A declared provider that IS present but disabled is still a WARN ───────
# install.sh's own definition of "installed" (line ~327) requires the plugin key's
# value to be `true`, not merely present. Doctor's check must agree, or a provider
# the user has switched off would be reported as usable.
echo ""
echo "--- Test: declared provider present but disabled ---"
TSD_DISABLED="/tmp/kinglet-doctor-disabled-$$"
bash "${REPO_DIR}/tests/fixtures/mkproject.sh" "$TSD_DISABLED" --variant urp >/dev/null
bash "${REPO_DIR}/install.sh" --project-dir "$TSD_DISABLED" --yes >/dev/null 2>&1
printf '\n### Process provider\n\nDiscovery and written planning in this project are owned by `superpowers`.\n' \
  >> "$TSD_DISABLED/CLAUDE.md"

TSD_DISABLED_SETTINGS="/tmp/kinglet-doctor-disabled-settings-$$.json"
printf '{"enabledPlugins": {"superpowers@claude-plugins-official": false}}' \
  > "$TSD_DISABLED_SETTINGS"

TSD_DISABLED_OUT="$(KINGLET_USER_SETTINGS="$TSD_DISABLED_SETTINGS" \
  bash "$TSD_DOCTOR" --project-dir "$TSD_DISABLED" 2>&1 || true)"
assert_contains "$TSD_DISABLED_OUT" "this project's process provider, but it is not" \
    "doctor warns on a provider that is present but disabled (value false), not just absent"
assert_not_contains "$TSD_DISABLED_OUT" "declared process provider 'superpowers' is installed" \
    "doctor does not pass a disabled provider as installed"
rm -rf "$TSD_DISABLED" "$TSD_DISABLED_SETTINGS"

rm -rf "$TSD_MOCK"
