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
assert_not_contains "$TSD_HEALTHY_OUT" "No mcpServers.UnityMCP.url in settings — skipped the bridge check." \
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
assert_contains "$TSD_STALE_OUT" "unity-brainstorming" \
    "doctor names the built-in fallback"
rm -rf "$TSD_STALE"

# ── A declared provider that IS present but disabled is still a WARN ───────
# install.sh's own definition of "installed" requires the plugin key's value to be
# `true`, not merely present — the grep for
# '"superpowers@claude-plugins-official"[[:space:]]*:[[:space:]]*true' against
# $CLAUDE_USER_SETTINGS. Doctor's check must agree, or a provider the user has
# switched off would be reported as usable. (Cited as "install.sh line ~327" until
# 2026-08-12, by which point :327 was dry-run commentary about .mcp.json and the
# grep was far below it. Anchors do not move; line numbers into install.sh do.)
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

# ── The receipt's origin column is READ, not discarded ─────────────────────
#
# install.sh writes a fourth column, `toolkit` or `user-modified`. A `user-modified` row carries the
# checksum of the file AS EDITED — deliberately, so the next install still recognises the edit as
# yours — so a sha-only comparison always matched and the file was counted under
# `PASS Install intact: N file(s) verified against the receipt`, never named. The diagnostic told the
# user nothing had changed about the one file they had changed. Reproduced 2026-08-12 on a fixture:
# `87 file(s) verified`, and no "modified since install" line printed at all.
#
# Two rows, because the classifier has two non-verifying branches and they exist for different
# reasons: `user-modified` (the real case) and an origin that is neither legal value — the catch-all
# uninstall.sh's classifier grew on 2026-08-12 for the same reason. A row whose provenance cannot be
# read is not ours to delete there, and not ours to certify here.
echo ""
echo "--- Test: the receipt's origin column is read ---"
TSD_ORIGIN="/tmp/kinglet-doctor-origin-$$"
bash "${REPO_DIR}/tests/fixtures/mkproject.sh" "$TSD_ORIGIN" --variant urp >/dev/null 2>&1
bash "${REPO_DIR}/install.sh" --project-dir "$TSD_ORIGIN" --yes >/dev/null 2>&1

# (a) Edit a payload file and reinstall. install.sh keeps the edit and rewrites the row.
printf '\n<!-- a rule this project rewrote -->\n' >> "$TSD_ORIGIN/.claude/rules/pc-console.md"
bash "${REPO_DIR}/install.sh" --project-dir "$TSD_ORIGIN" --yes >/dev/null 2>&1
TSD_ORIGIN_RECEIPT="$TSD_ORIGIN/.claude/state/install-receipt.tsv"
TSD_ORIGIN_ROW=$(grep -F '.claude/rules/pc-console.md' "$TSD_ORIGIN_RECEIPT" || true)
TSD_ORIGIN_SHA=$(sha256sum "$TSD_ORIGIN/.claude/rules/pc-console.md" | cut -d' ' -f1)
# Assert the fixture actually reached the state under test. Without these two, a change to
# install.sh that stopped writing `user-modified` at all would leave the assertions below passing
# for a reason that has nothing to do with what they are guarding.
assert_contains "$TSD_ORIGIN_ROW" "user-modified" \
    "the fixture reaches the state under test — install.sh rewrote the row as user-modified"
assert_contains "$TSD_ORIGIN_ROW" "$TSD_ORIGIN_SHA" \
    "…recording the EDITED checksum, which is exactly why a sha-only comparison matched"

# (b) An origin that is neither legal value, on a file that still matches its recorded checksum.
#     A trailing space is the realistic shape: hand-editing or transport, not a design decision.
#     Under the old if/elif this reached the sha test and was certified; the case's catch-all
#     reports it instead.
awk -F'\t' 'BEGIN { OFS = "\t" }
    $1 == ".claude/rules/performance.md" { $4 = "toolkit " }
    { print }' "$TSD_ORIGIN_RECEIPT" > "${TSD_ORIGIN_RECEIPT}.probe"
mv "${TSD_ORIGIN_RECEIPT}.probe" "$TSD_ORIGIN_RECEIPT"

TSD_ORIGIN_OUT=$(bash "$TSD_DOCTOR" --project-dir "$TSD_ORIGIN" 2>&1)
TSD_ORIGIN_RC=$?
assert_contains "$TSD_ORIGIN_OUT" "2 file(s) modified since install" \
    "doctor counts both the user-modified row and the unreadable-origin row as modified"
assert_contains "$TSD_ORIGIN_OUT" ".claude/rules/pc-console.md" \
    "doctor NAMES the edited file rather than folding it into the verified count"
assert_contains "$TSD_ORIGIN_OUT" ".claude/rules/performance.md" \
    "doctor fails closed on an origin it cannot read, as uninstall.sh keeps such a file"
assert_not_contains "$TSD_ORIGIN_OUT" "Install intact: 87 file(s)" \
    "the two unverifiable rows are subtracted from the verified count, not counted twice"
# The message deliberately avoids a bare `FAIL` token. The runner tallies results by grepping its
# subshell's output for `(^|[[:space:]])(PASS|FAIL|SKIP)(:|[[:space:]])`, so an assertion MESSAGE
# containing one is counted as a result in its own right: the first draft of this line read
# "…is a WARN, not a FAIL — …" and turned a green suite into `Total: 642  Passed: 641  Failed: 1`,
# with the single reported failure being the text of a passing assertion.
assert_eq "0" "$TSD_ORIGIN_RC" \
    "an edited payload file warns rather than failing — editing the toolkit in place is legitimate"
rm -rf "$TSD_ORIGIN"

# ── A long list must not kill the script ───────────────────────────────────
#
# Both list printers were `printf '%s' "$LIST" | head -5` under `set -euo pipefail`. head exits the
# instant it has five lines without draining stdin, the printf takes SIGPIPE, pipefail promotes 141,
# and `set -e` kills the script — after printing five paths and before the payload-sanity checks, the
# process-provider check and the summary line. It fires on a long list and hides on a short one,
# which is why every assertion above this one passed while the defect stood: measured 2026-08-12,
# 87 modified rows survived, 1200 exited 141 with no summary printed.
#
# BOTH lists are made long in ONE run deliberately. The missing-list printer runs first, so reaching
# the summary is only possible if neither printer aborted — one assertion covering both call sites.
echo ""
echo "--- Test: a long modified/missing list does not kill the script ---"
TSD_LONG="/tmp/kinglet-doctor-long-$$"
bash "${REPO_DIR}/tests/fixtures/mkproject.sh" "$TSD_LONG" --variant urp >/dev/null 2>&1
bash "${REPO_DIR}/install.sh" --project-dir "$TSD_LONG" --yes >/dev/null 2>&1
# 1500 rows of ~46 bytes puts each list near 69 KB. The failure is a race between the writer's
# chunked writes and the reader's exit, so it is probabilistic near the boundary — measured on this
# host, 400 entries died 2/10 and 500 died 3/10, while 1000 and 2000 died 10/10. The size is chosen
# to sit well inside the deterministic region, not just past the first failure seen.
TSD_LONG_N=1500
TSD_LONG_SHA=0000000000000000000000000000000000000000000000000000000000000000
mkdir -p "$TSD_LONG/.claude/generated"
TSD_LONG_I=0
{
  while [ "$TSD_LONG_I" -lt "$TSD_LONG_N" ]; do
    # One row whose file exists but whose checksum cannot match  → the modified list.
    # One row whose file was never created                       → the missing list.
    printf 'generated payload %s\n' "$TSD_LONG_I" \
      > "$TSD_LONG/.claude/generated/present-payload-file-$TSD_LONG_I.md"
    printf '%s\t%s\t664\ttoolkit\n' \
      ".claude/generated/present-payload-file-$TSD_LONG_I.md" "$TSD_LONG_SHA"
    printf '%s\t%s\t664\ttoolkit\n' \
      ".claude/generated/absent-payload-file-$TSD_LONG_I.md" "$TSD_LONG_SHA"
    TSD_LONG_I=$((TSD_LONG_I + 1))
  done
} >> "$TSD_LONG/.claude/state/install-receipt.tsv"

TSD_LONG_OUT=$(bash "$TSD_DOCTOR" --project-dir "$TSD_LONG" 2>&1)
TSD_LONG_RC=$?
assert_contains "$TSD_LONG_OUT" "$TSD_LONG_N receipted file(s) missing" \
    "the fixture reaches the state under test — the missing list is long"
assert_contains "$TSD_LONG_OUT" "$TSD_LONG_N file(s) modified since install" \
    "…and so is the modified list"
assert_contains "$TSD_LONG_OUT" "NOTICE.md present" \
    "doctor runs the checks that come AFTER both list printers"
assert_contains "$TSD_LONG_OUT" "passed ·" \
    "doctor reaches its summary line with both lists long — the assertion the pipes used to fail"
assert_eq "1" "$TSD_LONG_RC" \
    "doctor exits 1 on the missing files, not 141 from a SIGPIPE it never intended to take"
rm -rf "$TSD_LONG"

# ── No `| head` survives in the script ─────────────────────────────────────
#
# Spec criterion 12: no `| head` remains in this file. The two `head -5` list printers were the ones
# the plan named; `uv --version | head -1` and the serverInfo `sed | head -1` are the same shape and
# the second is worse — a bare assignment, so a 141 there kills the script at the bridge check and
# every check below it never runs.
#
# Whole-line comments are stripped first, because the fix's own commentary quotes the bad form
# verbatim and an explanation of a trap has to be able to name it. A `| head` in a TRAILING comment
# on a code line would still trip this, which is the conservative direction.
TSD_HEAD_HITS=$(grep -v '^[[:space:]]*#' "$TSD_DOCTOR" | grep -c '|[[:space:]]*head' || true)
assert_eq "0" "$TSD_HEAD_HITS" \
    'no `| head` remains in studio-doctor.sh outside its comments (spec criterion 12)'

rm -rf "$TSD_MOCK"
