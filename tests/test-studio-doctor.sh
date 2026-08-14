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
# 2026-08-12, by which point install.sh:327 was dry-run commentary about .mcp.json
# and the grep was far below it — a 2026-08-12 line number, kept as history rather
# than re-derived. Anchors do not move; line numbers into install.sh do.)
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
#
# The two branches also report SEPARATELY, and that is asserted below rather than assumed. They were
# one bucket until 2026-08-13, printed under `install.sh will keep your versions` — a sentence
# measured false for the unreadable-origin row on that date: with its bytes still matching the
# recorded sha, install.sh printed no `keeping yours` line, overwrote the file, and rewrote the row as
# a clean `toolkit`. install.sh's upgrade scan classifies with an `if/else` on `user-modified`, not
# with a `case`, so an origin it cannot read falls to the sha test and the bytes decide.
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
# The counts are anchored on the `WARN ` prefix the doctor prints. Unanchored, `grep -F` substring
# matching accepts `11`, `21`, … `81 file(s) modified since install` as a match for `1 file(s) …`,
# so the assertion would survive the very miscount it exists to detect.
assert_contains "$TSD_ORIGIN_OUT" "WARN 1 file(s) modified since install" \
    "doctor counts the user-modified row as modified, and only it"
assert_contains "$TSD_ORIGIN_OUT" ".claude/rules/pc-console.md" \
    "doctor NAMES the edited file rather than folding it into the verified count"
assert_contains "$TSD_ORIGIN_OUT" "WARN 1 file(s) have a receipt origin this check does not recognise" \
    "the unreadable-origin row is reported on its OWN line, not merged into the modified count"
assert_contains "$TSD_ORIGIN_OUT" ".claude/rules/performance.md" \
    "doctor names the origin it cannot read rather than certifying it, as uninstall.sh keeps such a file"
# The three continuation lines under that header were asserted by NOTHING until 2026-08-14.
#
# They are the substance of the diagnosis, not decoration: the header says only "reported, not
# verified", and these lines are what tell the user which of the two tools will do what to the file.
# Two fix rounds worked to make them true — the 2026-08-13 round measured that install.sh classifies
# by bytes rather than by the origin column and rewrote the sentence away from the false "install.sh
# will keep your versions" — and deleting all three was invisible: measured 2026-08-14, removing
# every one of them left this file 31/31 green.
#
# Asserted as three separate needles rather than one reflowed paragraph, because the doctor prints
# them as three `warn` calls and a reflow that merged two of them would be a legitimate edit that a
# single whole-paragraph needle would red. Each needle is a clause that carries a distinct claim, and
# each is short enough to survive rewrapping.
assert_contains "$TSD_ORIGIN_OUT" "Neither toolkit nor user-modified in the receipt's fourth column" \
    "the unreadable-origin header is followed by the line that says WHAT was unreadable"
assert_contains "$TSD_ORIGIN_OUT" "uninstall.sh keeps" \
    "…and by the line that states uninstall.sh's behaviour for such a row"
assert_contains "$TSD_ORIGIN_OUT" "install.sh classifies it by bytes and not by that column" \
    "…and by the line the 2026-08-13 round rewrote: install.sh decides by bytes, not by the origin column"
# WHICH list a path lands in is the whole point, and a substring test over the full output cannot see
# it — both paths are present either way. So extract the indented block that follows the
# `keep your versions` header (print_first_5 indents by seven spaces) and test membership there.
# The two assertions are a pair on purpose: if the extraction ever yields nothing, the assert_contains
# goes red, so the assert_not_contains cannot quietly pass on an empty haystack.
TSD_ORIGIN_KEPT=$(awk '
    /file\(s\) modified since install/ { in_block = 1; next }
    in_block && /^       / { print; next }
    in_block { in_block = 0 }' <<< "$TSD_ORIGIN_OUT")
assert_contains "$TSD_ORIGIN_KEPT" ".claude/rules/pc-console.md" \
    "…listed under the header promising install.sh keeps it, which for a user-modified row is true"
assert_not_contains "$TSD_ORIGIN_KEPT" ".claude/rules/performance.md" \
    "…and the unreadable-origin row is NOT under that header: measured 2026-08-13, install.sh overwrote such a file whose bytes still matched its recorded sha"
# Derived, not hardcoded. This read `Install intact: 87 file(s)` until 2026-08-13; 87 is this
# payload's receipt row count today, so the assertion would have gone permanently vacuous — with no
# signal — the day the payload gained or lost a file. The expression mirrors the doctor's own skip
# list (`case "$rel" in ''|\#*|path`). Note `grep -vc '^#' "$RECEIPT"` does NOT work here: measured
# 2026-08-13 it returns 88 against the doctor's 87, because it keeps the `path` header row.
TSD_ORIGIN_ROWS=$(awk -F'\t' '!/^#/ && NF && $1 != "path" { rows++ } END { print rows + 0 }' \
    "$TSD_ORIGIN_RECEIPT")
assert_contains "$TSD_ORIGIN_OUT" "Install intact: $((TSD_ORIGIN_ROWS - 2)) file(s) verified against the receipt" \
    "the verified count is every receipt row less the two unverifiable ones"
assert_not_contains "$TSD_ORIGIN_OUT" "Install intact: $TSD_ORIGIN_ROWS file(s)" \
    "…and specifically not the full row count, which is what a classifier that certifies them prints"
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
#
# THE FIXTURE IS ASYMMETRIC, AND THAT IS THE SECOND THING IT IS FOR.
#
# It made both lists exactly 1500 until 2026-08-14, which meant the block could not tell its two
# lists apart: `MODIFIED` and `MISSING` both printed 1500, so the two assertions below were
# satisfied by either counter. Measured on that version — swap the doctor's two counters (print
# `$MISSING file(s) modified since install` and `$MODIFIED receipted file(s) missing`) and BOTH
# assertions stay green, on a doctor that has its two diagnoses backwards. A fixture whose inputs
# are indistinguishable cannot discriminate between the outputs derived from them, however many
# assertions are written on top of it.
#
# So the missing list is N + K rows and the modified list is N. Any confusion of the two counters
# now reddens by name. K is small and non-round on purpose: 7 cannot be produced by an off-by-one, a
# halving, or a rounding of N, so a failure message reading `1507` versus `1500` names its own cause.
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
TSD_LONG_K=7
TSD_LONG_MISSING_N=$((TSD_LONG_N + TSD_LONG_K))
TSD_LONG_SHA=0000000000000000000000000000000000000000000000000000000000000000
mkdir -p "$TSD_LONG/.claude/generated"
TSD_LONG_I=0
{
  # One row whose file exists but whose checksum cannot match  → the modified list, N rows.
  while [ "$TSD_LONG_I" -lt "$TSD_LONG_N" ]; do
    printf 'generated payload %s\n' "$TSD_LONG_I" \
      > "$TSD_LONG/.claude/generated/present-payload-file-$TSD_LONG_I.md"
    printf '%s\t%s\t664\ttoolkit\n' \
      ".claude/generated/present-payload-file-$TSD_LONG_I.md" "$TSD_LONG_SHA"
    TSD_LONG_I=$((TSD_LONG_I + 1))
  done
  # One row whose file was never created → the missing list, N + K rows. Both lists stay well inside
  # the deterministic SIGPIPE region measured above; the asymmetry only has to be readable, not big.
  TSD_LONG_I=0
  while [ "$TSD_LONG_I" -lt "$TSD_LONG_MISSING_N" ]; do
    printf '%s\t%s\t664\ttoolkit\n' \
      ".claude/generated/absent-payload-file-$TSD_LONG_I.md" "$TSD_LONG_SHA"
    TSD_LONG_I=$((TSD_LONG_I + 1))
  done
} >> "$TSD_LONG/.claude/state/install-receipt.tsv"

TSD_LONG_OUT=$(bash "$TSD_DOCTOR" --project-dir "$TSD_LONG" 2>&1)
TSD_LONG_RC=$?
# Both counts are anchored, and they are anchored by two different means on purpose.
#
# `assert_contains` is a substring test, so an unanchored count needle accepts any output whose
# number merely CONTAINS it. That was not theoretical here: measured 2026-08-13 against a doctor
# mutated to prefix a digit to the count, the old needle `1500 file(s) modified since install`
# stayed green against a line reading `11500 file(s) modified since install`. The modified line
# takes the same `WARN ` prefix the origin block above uses.
#
# The missing line is printed by the doctor's `fail`, so its prefix is the literal token FAIL — and
# the runner tallies each file's results by grepping its output for
# `(^|[[:space:]])FAIL(:|[[:space:]])` (anchor: `grep -n 'file_fail=' tests/run-tests.sh`).
# assert_contains echoes the needle in its failure branch, so a needle carrying that token would be
# counted as a SECOND failure — the trap this file already records for assertion MESSAGES, one level
# further in. So that count is extracted and compared exactly, which is stricter than any substring:
# `awk` with no `exit`, so two matching lines would print two numbers and fail loudly rather than
# silently taking the first.
assert_contains "$TSD_LONG_OUT" "WARN $TSD_LONG_N file(s) modified since install" \
    "the fixture reaches the state under test — the modified list is long, and its count is N not N+K"
TSD_LONG_MISSING_GOT=$(awk '/receipted file\(s\) missing/ { print $2 }' <<< "$TSD_LONG_OUT")
assert_eq "$TSD_LONG_MISSING_N" "$TSD_LONG_MISSING_GOT" \
    "…and the missing list is N+K, counted exactly rather than by substring — the two counters are distinguishable"
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

# ── Two helpers, and why neither of them is an assertion ───────────────────
#
# NEITHER MAY PUT A VERDICT TOKEN INTO AN ASSERTION'S ARGUMENTS. The runner tallies each file's
# results by grepping its output for `(^|[[:space:]])(PASS|FAIL|SKIP)(:|[[:space:]])`
# (anchor: `grep -n 'file_fail=' tests/run-tests.sh`), and both `assert_contains` and `assert_eq`
# echo their needle or their expected/actual values in the FAILURE branch. So an assertion written
# directly against the doctor's `PASS All hooks referenced…` line would, on the day it went red,
# print that token and be counted as a passing result — a red assertion inflating the pass count.
# This file already records the same trap one level out, for assertion MESSAGES. So the doctor's
# verdict lines are reduced to a token-free value BEFORE they reach an assertion: a 0/1 flag, or a
# count.
#
# tsd_verdict <output> <line substring> — the verdict word the doctor printed on the line carrying
# that substring, or the empty string when it printed no such line at all. Colour codes are empty
# here because the doctor's `[ -t 1 ]` is false inside `$( )`.
tsd_verdict() { awk -v needle="$2" 'index($0, needle) { print $1 }' <<< "$1"; }

# tsd_payload_fails <output> — how many of the doctor's failures came from the payload-directory
# loop specifically. The summary total cannot answer that: emptying `.claude/hooks/` also produces
# one dead-registration failure per registration, so a total-count assertion over that state would
# be counting two checks at once and moving when either changed.
# The `$1 == "FAIL"` is load-bearing and was added after a mutation showed why: downgrading the
# empty-directory `fail` to a `warn` left every count below green, because a WARN line names the
# directory in exactly the same words. The verdict token cannot appear in an assertion's arguments,
# but nothing stops it being read INSIDE the helper — what leaves here is a number.
tsd_payload_fails() { awk '$1 == "FAIL" && /Payload directory \.claude\//{ n++ } END { print n + 0 }' <<< "$1"; }

# tsd_failures <output> — the failure count off the summary line, exactly, never by substring.
# `assert_contains "$out" "1 failure(s)"` is satisfied by `11 failure(s)`, which is the same defect
# measured in this file on 2026-08-13 against `1500` matching `11500`. Splitting the summary line on
# whitespace and taking the field before the `failure(s)` token is exact and stays ASCII — the `·`
# separators are multibyte and are never made a field separator here.
tsd_failures() { awk '{ for (i = 1; i <= NF; i++) if ($i == "failure(s)") print $(i - 1) }' <<< "$1"; }

# ── The hook-registration sweep: settings.json → disk ──────────────────────
#
# ASSERTED BY NOTHING UNTIL 2026-08-14. `scripts/studio-doctor.sh` has had this check all along, and
# it is the one that diagnoses the state a cross-version upgrade produces: install.sh keeps the
# user's `settings.json`, the payload drops a hook, and the kept file goes on registering a script
# that is no longer there — a registration Claude Code reports nothing about, ever. The doctor prints
# `FAIL settings.json references a missing hook:` per dead entry and exits 1. Measured on the
# 2026-08-14 tree before this section existed: `/usr/bin/grep -rn 'missing hook' tests/` returned
# nothing and this file contained zero occurrences of the string `hook`, so the check that catches
# the defect lived in a script no test ever questioned.
#
# THE COUNT IS PINNED TO EXACTLY ONE, not merely to the planted name being present. A mutant that
# deletes the existence test reports EVERY registration as dead, and "the dead hook is named" is
# satisfied by naming all twelve. That exact mutant survived the first version of the sibling guard
# in `tests/test-install-prune.sh`; it is cheaper to pin the count than to rediscover why.
echo ""
echo "--- Test: the hook-registration sweep, settings.json → disk ---"
TSD_DEAD="/tmp/kinglet-doctor-deadhook-$$"
bash "${REPO_DIR}/tests/fixtures/mkproject.sh" "$TSD_DEAD" --variant urp >/dev/null 2>&1
bash "${REPO_DIR}/install.sh" --project-dir "$TSD_DEAD" --yes >/dev/null 2>&1
TSD_DEAD_SETTINGS="$TSD_DEAD/.claude/settings.json"

# (a) The healthy control. Without it, every assertion below is satisfied by a doctor that reports
#     every registration dead on every project, and the passing condition of the mutation check is
#     silence about a state that was never quiet.
TSD_DEAD_OK_OUT=$(bash "$TSD_DOCTOR" --project-dir "$TSD_DEAD" 2>&1)
TSD_DEAD_OK_RC=$?
if [ "$(tsd_verdict "$TSD_DEAD_OK_OUT" 'hooks referenced by settings.json exist')" = "PASS" ]
then TSD_DEAD_OK_VERDICT=1; else TSD_DEAD_OK_VERDICT=0; fi
assert_eq "1" "$TSD_DEAD_OK_VERDICT" \
    "the sweep issues a verdict on a healthy install, rather than being silent about the registrations"
TSD_DEAD_OK_N=$(awk '/references a missing hook/ { n++ } END { print n + 0 }' <<< "$TSD_DEAD_OK_OUT")
assert_eq "0" "$TSD_DEAD_OK_N" \
    "…and names no dead registration on a project whose payload and settings.json arrived together"
assert_eq "0" "$TSD_DEAD_OK_RC" \
    "…and a healthy project's registrations do not make the doctor exit non-zero"

# (b) One registration pointed at a script that is not there. Rewriting an existing entry rather
#     than appending one keeps the JSON valid without a parser — this suite has none — and the
#     sweep reads settings.json with a grep, so the state under test is reached either way.
#     The name is lowercase-and-hyphens on purpose: the sweep's own `[a-z_-]+` character class is
#     what decides whether a registration is visible to it at all.
awk '{ gsub(/\.claude\/hooks\/track-edits\.sh/, ".claude/hooks/warn-does-not-exist.sh"); print }' \
    "$TSD_DEAD_SETTINGS" > "${TSD_DEAD_SETTINGS}.probe"
mv "${TSD_DEAD_SETTINGS}.probe" "$TSD_DEAD_SETTINGS"
TSD_DEAD_PLANTED=$(grep -cF 'warn-does-not-exist.sh' "$TSD_DEAD_SETTINGS" || true)
assert_eq "1" "$TSD_DEAD_PLANTED" \
    "the fixture reaches the state under test — settings.json now registers exactly one hook by a name it did not before"
assert_eq "absent" \
    "$([ -f "$TSD_DEAD/.claude/hooks/warn-does-not-exist.sh" ] && echo present || echo absent)" \
    "…and no file answers to that name, which is what makes the registration dead"

TSD_DEAD_OUT=$(bash "$TSD_DOCTOR" --project-dir "$TSD_DEAD" 2>&1)
TSD_DEAD_RC=$?
TSD_DEAD_N=$(awk '/references a missing hook/ { n++ } END { print n + 0 }' <<< "$TSD_DEAD_OUT")
assert_eq "1" "$TSD_DEAD_N" \
    "the sweep reports exactly one dead registration — not every registration, which is what a deleted existence test prints"
TSD_DEAD_NAMED=$(awk '/references a missing hook/ { print $NF }' <<< "$TSD_DEAD_OUT")
assert_eq ".claude/hooks/warn-does-not-exist.sh" "$TSD_DEAD_NAMED" \
    "…and names the registration, so the user can find it in their own settings.json"
if [ -n "$(tsd_verdict "$TSD_DEAD_OUT" 'hooks referenced by settings.json exist')" ]
then TSD_DEAD_STILL_OK=1; else TSD_DEAD_STILL_OK=0; fi
assert_eq "0" "$TSD_DEAD_STILL_OK" \
    "…and the all-present line is gone, so the two verdicts cannot both print on one run"
assert_eq "1" "$TSD_DEAD_RC" \
    "a dead hook registration makes the doctor exit 1 — a hook that never fires is a broken install"
assert_contains "$TSD_DEAD_OUT" "passed ·" \
    "…and the run still reaches its summary line, so a project with many dead registrations is diagnosed rather than abandoned"
rm -rf "$TSD_DEAD"

# ── An empty-but-present payload directory is a FAILURE, not a count ───────
#
# Measured 2026-08-14 on a --variant urp fixture with the receipt removed — the teammate's-git-clone
# shape the doctor's own receipt branch names, and the only shape in which the receipt cannot notice
# the files are gone: `.claude/agents/*.md` deleted gave `INFO agents=0`, `0 failure(s)`, exit 0. A
# project with no agents at all, reported healthy. `.claude/commands/unity-doctor.md` carried the
# compensation — "read those four numbers yourself: any zero is this item's ERROR" — a check
# performed by a model against a script already holding the answer. That item is deleted in the same
# commit as this section: two sources for one fact is how the duplication its Check 2 removed creeps
# back.
#
# THREE STATES, IN ONE FIXTURE, AND THE FIRST ONE IS THE CONTROL. Receipt gone and payload intact
# must still be zero failures — otherwise everything below is satisfied by a doctor that fails on
# the missing receipt and has never looked at a directory. Then one directory emptied, then a second
# one removed outright, with the failure count read exactly at each step: 0 → 1 → 2. A count that
# moves with the damage is what separates this from a guard pinned to a single hardcoded failure.
echo ""
echo "--- Test: an empty-but-present payload directory is a failure ---"
TSD_PAY="/tmp/kinglet-doctor-payload-$$"
bash "${REPO_DIR}/tests/fixtures/mkproject.sh" "$TSD_PAY" --variant urp >/dev/null 2>&1
bash "${REPO_DIR}/install.sh" --project-dir "$TSD_PAY" --yes >/dev/null 2>&1
rm -f "$TSD_PAY/.claude/state/install-receipt.tsv"

TSD_PAY_OK_OUT=$(bash "$TSD_DOCTOR" --project-dir "$TSD_PAY" 2>&1)
TSD_PAY_OK_RC=$?
if [ "$(tsd_verdict "$TSD_PAY_OK_OUT" 'Payload complete')" = "PASS" ]
then TSD_PAY_OK_VERDICT=1; else TSD_PAY_OK_VERDICT=0; fi
assert_eq "1" "$TSD_PAY_OK_VERDICT" \
    "the payload check issues a verdict on a complete payload, so its silence later means something"
assert_eq "0" "$(tsd_failures "$TSD_PAY_OK_OUT")" \
    "…and a project with no receipt but a complete payload still has zero failures — the control this section rests on"
assert_eq "0" "$TSD_PAY_OK_RC" \
    "…and exits 0, so the failures below belong to the directories and not to the missing receipt"

rm -f "$TSD_PAY/.claude/agents/"*.md
# The fixture-state probe runs BEFORE the run it justifies, not after. The state is unchanged
# either way here, so the old order was harmless — but a probe that reports after the fact cannot
# stop an assertion being made against a state that was never reached, which is the only reason to
# write one. The sibling probes in the hook section above are in this order for the same reason.
assert_eq "0" "$(find "$TSD_PAY/.claude/agents" -name '*.md' | wc -l | tr -d ' ')" \
    "the fixture reaches the state under test — .claude/agents/ is present and holds no agent"
TSD_PAY_EMPTY_OUT=$(bash "$TSD_DOCTOR" --project-dir "$TSD_PAY" 2>&1)
TSD_PAY_EMPTY_RC=$?
assert_contains "$TSD_PAY_EMPTY_OUT" "Payload directory .claude/agents/ is present but holds no *.md" \
    "an empty-but-present payload directory is reported, naming the directory and what it should hold"
assert_eq "1" "$(tsd_failures "$TSD_PAY_EMPTY_OUT")" \
    "…as exactly one failure — an empty directory is one finding, not a cascade"
assert_not_contains "$TSD_PAY_EMPTY_OUT" "Payload complete:" \
    "…and the complete-payload line does not print beside it"
assert_eq "1" "$TSD_PAY_EMPTY_RC" \
    "…and the doctor exits 1: measured 2026-08-14 before this check, the same project exited 0 with INFO agents=0"

rm -rf "$TSD_PAY/.claude/rules"
TSD_PAY_GONE_OUT=$(bash "$TSD_DOCTOR" --project-dir "$TSD_PAY" 2>&1)
TSD_PAY_GONE_RC=$?
assert_contains "$TSD_PAY_GONE_OUT" "Payload directory .claude/rules/ is missing" \
    "a payload directory that is gone is reported as missing, distinctly from one that is merely empty"
assert_contains "$TSD_PAY_GONE_OUT" "Payload directory .claude/agents/ is present but holds no *.md" \
    "…without swallowing the empty directory already reported"
assert_eq "2" "$(tsd_failures "$TSD_PAY_GONE_OUT")" \
    "…and the failure count moves with the damage, 1 → 2, rather than being pinned to one finding"
assert_eq "1" "$TSD_PAY_GONE_RC" \
    "…and the doctor still exits 1"

# ── WHERE THAT LIST COMES FROM, AND EVERY MEMBER OF IT ─────────────────────
#
# The loop in studio-doctor.sh carries a hand-written list of five `name:glob` specs, and the two
# states above exercise TWO of them. Measured 2026-08-14 against the first version of this section:
# dropping `commands`, `hooks` and `skills` from that list left this file 56/56 GREEN, and dropping
# `"hooks:*.sh"` alone did too. `hooks/` is the member this task ADDED — the prose it replaced made
# exactly that argument, that the INFO block "reads four of these five … never hooks" — so the one
# new member was the one nothing asserted.
#
# THREE DEFENCES, BECAUSE THEY FAIL DIFFERENTLY — AND THE FIRST ONE REPLACES A CLAIM THAT WAS FALSE.
#
#   1. THE MEMBER SET, from the expression install.sh installs the payload WITH. The first version of
#      this section pinned the set to install.sh's completion SUMMARY and said a sixth payload
#      directory could not be installed without appearing there. Measured false the same week: a real
#      `.claude/newsurface/thing.md` with its provenance row installs, the doctor calls the project
#      healthy, `check-provenance.sh` says `provenance OK`, and this file stayed 70/70 green. The
#      summary is five hand-written `printf` lines; the INSTALL is
#      `PAYLOAD_FILES=$(cd "$SCRIPT_DIR/.claude" && find . -type f ! -path './state/*' …)` at
#      install.sh's Step 4, whose own comment says why it is a find: hand-synced lists drift and find
#      cannot. So the set is derived from that expression, EVALUATED FROM INSTALL.SH'S OWN BYTES —
#      the same idiom this file already uses to exercise `read_mcp_url` in isolation, and the reason
#      it is not a re-implementation: a re-implementation is a third hand-written list.
#      `.claude/state/` drops out because that expression excludes it. `.claude/scripts/` is the
#      known exception in the other direction: it IS installed, by the separate `for group in
#      scripts` loop, and it is on no side of this pin — asserted below as a scope statement rather
#      than left to a comment.
#   2. THE GLOBS, against the completion summary, which is the only thing that carries them: the find
#      has no opinion about what makes a file count in a directory. That comparison is a LOCKSTEP PIN
#      BETWEEN TWO HAND-WRITTEN LISTS and is not called a derivation here — it cannot see a directory
#      that is absent from both, which is exactly what defence 1 is for.
#   3. Every member is exercised BEHAVIOURALLY below. A static set assertion cannot see a member that
#      is listed and does not work; and a set pinned on both sides at once still passes when both
#      sides are loosened together — measured, `skills:SKILL.md` widened to `*.md` in the doctor AND
#      in install.sh satisfies defences 1 and 2 completely, and only the probe below catches it,
#      because `.claude/skills/subagent-driven-implementation/` holds four non-SKILL.md `.md` files
#      and reads as non-empty with every SKILL.md gone.
#
# THE ONE THING THAT CANNOT BE DERIVED, SAID OUT LOUD: install.sh supplies no disk glob for `hooks`,
# because it counts hooks from settings.json — precisely so `_lib.sh`, a sourced library and not a
# hook, is never counted as one. So `hooks:*.sh` is the single spec pinned by a literal here, and
# the `_lib.sh` exclusion is asserted by behaviour instead.
TSD_DOCTOR_CMD="${REPO_DIR}/.claude/commands/unity-doctor.md"
TSD_PAY_SPECS=$(awk '/^  for pd_spec in /{
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^"[a-z]+:/) { s = $i; sub(/^"/, "", s); sub(/".*$/, "", s); print s }
      }
    }' "$TSD_DOCTOR" | sort)
TSD_PAY_INSTALL=$(awk -v q="'" '
    {
      line = $0
      pat = "count_in [a-z]+ " q "[^" q "]+" q
      while (match(line, pat)) {
        m = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        sub(/^count_in /, "", m)
        gsub(q, "", m)
        sub(/ /, ":", m)
        print m
      }
      if ($0 ~ /\$\(count_hooks\)/) { print "hooks:" }
    }' "${REPO_DIR}/install.sh" | sort -u)
# Defence 1 — the payload tree, from install.sh's own enumeration expression, run as install.sh runs
# it. `SCRIPT_DIR` is what that line reads; the repo checkout is what install.sh sets it to.
TSD_PAY_FIND_EXPR=$(awk '/^PAYLOAD_FILES=\$\(cd /{ print; exit }' "${REPO_DIR}/install.sh")
assert_contains "$TSD_PAY_FIND_EXPR" "find . -type f" \
    "install.sh's payload enumeration was found and still enumerates files — an expression that moved must fail here, loudly, rather than silently deriving an empty set"
TSD_PAY_TREE=$(SCRIPT_DIR="$REPO_DIR" bash -c "$TSD_PAY_FIND_EXPR
printf '%s\n' \"\$PAYLOAD_FILES\"" | awk -F/ 'NF > 1 { print $1 }' | sort -u)
assert_eq "5" "$(printf '%s\n' "$TSD_PAY_TREE" | grep -c . || true)" \
    "the payload tree holds five directories — the derivation is non-empty, without which every comparison below is vacuously true"
assert_eq "$TSD_PAY_TREE" "$(cut -d: -f1 <<< "$TSD_PAY_SPECS")" \
    "the doctor checks every directory install.sh actually installs — a sixth added under .claude/ is in that find the moment it exists, so this loop must grow in the same commit"
assert_not_contains "$TSD_PAY_TREE" "scripts" \
    "…and the pin's scope is the payload tree: .claude/scripts/ is installed by the separate 'for group in scripts' loop, is on no side of it, and is a ledger item rather than a gap this claim hides"
assert_eq "5" "$(printf '%s\n' "$TSD_PAY_SPECS" | grep -c . || true)" \
    "the doctor's payload list parses to five specs — a derivation that reads nothing must not be compared against another that reads nothing"
assert_eq "5" "$(printf '%s\n' "$TSD_PAY_INSTALL" | grep -c . || true)" \
    "…and install.sh's completion summary parses to five counted directories"
assert_eq "$(cut -d: -f1 <<< "$TSD_PAY_INSTALL")" "$(cut -d: -f1 <<< "$TSD_PAY_SPECS")" \
    "the summary reports the same set the doctor checks — two hand-written lists held in lockstep, which is what this assertion is; the find above is the derivation"
assert_eq "$(grep -v '^hooks:' <<< "$TSD_PAY_INSTALL" || true)" "$(grep -v '^hooks:' <<< "$TSD_PAY_SPECS" || true)" \
    "…with the same glob per directory, so the one structurally different member (skills/SKILL.md) cannot be edited to *.md unnoticed"
assert_eq "*.sh" "$(grep '^hooks:' <<< "$TSD_PAY_SPECS" | cut -d: -f2 || true)" \
    "hooks is the one spec install.sh supplies no disk glob for — it counts registrations — so its glob is pinned here"
TSD_PAY_DOC_NAMES=$(awk '/the payload directories/ {
      line = $0
      while (match(line, /`[a-z]+\/`/)) {
        print substr(line, RSTART + 1, RLENGTH - 3)
        line = substr(line, RSTART + RLENGTH)
      }
    }' "$TSD_DOCTOR_CMD" | sort)
assert_eq "$(cut -d: -f1 <<< "$TSD_PAY_SPECS")" "$TSD_PAY_DOC_NAMES" \
    "and the shipped /unity-doctor claim about what the script covers names exactly those directories — it reaches a user, and nothing else derived it"

# Every remaining member, on the fixture already standing at two payload failures. Counted with
# tsd_payload_fails rather than the summary total: emptying hooks/ also lights up the
# dead-registration sweep, and one number cannot be evidence for two checks.
rm -f "$TSD_PAY/.claude/commands/"*.md
assert_eq "3" "$(tsd_payload_fails "$(bash "$TSD_DOCTOR" --project-dir "$TSD_PAY" 2>&1)")" \
    "emptying .claude/commands/ is the third payload failure — the member is checked, not merely listed"
find "$TSD_PAY/.claude/skills" -name 'SKILL.md' -delete
TSD_PAY_SKILLS_OUT=$(bash "$TSD_DOCTOR" --project-dir "$TSD_PAY" 2>&1)
assert_contains "$TSD_PAY_SKILLS_OUT" "Payload directory .claude/skills/ is present but holds no SKILL.md" \
    "skills/ is checked on SKILL.md and not on *.md — the skill directories are all still there, holding everything except the file that makes one a skill"
assert_eq "4" "$(tsd_payload_fails "$TSD_PAY_SKILLS_OUT")" \
    "…and that is the fourth payload failure"
# hooks/ keeping ONLY _lib.sh. Reconstructed 2026-08-14 with the exclusion removed and nothing else
# changed: `PASS Payload complete` beside TWELVE `references a missing hook` failures — one per
# registered hook — `12 failure(s)`, exit 1. The payload verdict satisfied by the shared library that
# CLAUDE.md and /unity-doctor's own registration item both exclude from the hook set. This comment
# said thirteen in its first draft, which is the count of `.sh` FILES in hooks/ (twelve hooks plus
# the library) and the one quantity a count of dead registrations cannot be.
for tsd_h in "$TSD_PAY/.claude/hooks/"*.sh; do
  case "$(basename "$tsd_h")" in _lib.sh) continue ;; esac
  rm -f "$tsd_h"
done
assert_eq "_lib.sh" "$(cd "$TSD_PAY/.claude/hooks" && printf '%s\n' *)" \
    "the fixture reaches the state under test — hooks/ holds the library and no hook"
TSD_PAY_HOOKS_OUT=$(bash "$TSD_DOCTOR" --project-dir "$TSD_PAY" 2>&1)
TSD_PAY_HOOKS_RC=$?
assert_contains "$TSD_PAY_HOOKS_OUT" "Payload directory .claude/hooks/ is present but holds no *.sh" \
    "a hooks/ holding only _lib.sh is empty of hooks, and the verdict says so rather than counting the library"
assert_eq "5" "$(tsd_payload_fails "$TSD_PAY_HOOKS_OUT")" \
    "…which is the fifth and last member: every spec in the doctor's list has now been made to fire"
if [ "$(tsd_failures "$TSD_PAY_HOOKS_OUT")" -gt "$(tsd_payload_fails "$TSD_PAY_HOOKS_OUT")" ]
then TSD_PAY_SWEEP_TOO=1; else TSD_PAY_SWEEP_TOO=0; fi
assert_eq "1" "$TSD_PAY_SWEEP_TOO" \
    "…and the dead-registration sweep fired on the same run, which is why these five were counted apart from the summary total"
assert_eq "1" "$TSD_PAY_HOOKS_RC" \
    "…and the doctor exits 1 with the whole payload gutted"
rm -rf "$TSD_PAY"

rm -rf "$TSD_MOCK"
