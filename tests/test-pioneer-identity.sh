#!/usr/bin/env bash
# ============================================================================
# test-pioneer-identity.sh — Tests the Kinglet Pioneer identity contract.
#
# These four values are written into (or read back out of) a USER'S Unity
# project. Changing them after a first install strands the previous values in
# a file we no longer recognise: the installer would not find its own markers
# in the user's CLAUDE.md and would append a second generated block. So they
# are pinned by behaviour, not by reading our own source.
#
# The scratch project directory is created with `mktemp -d`, not a PID-keyed
# path. This file runs as `( source "$test_file" )` from run-tests.sh, so `$$`
# would be the RUNNER's PID, not one unique to this file — and if an assertion
# or an install aborted the subshell early, the trailing `rm -rf` would never
# run, leaving a stale directory that a LATER run with the same PID would reuse
# already containing `.claude/` and a receipt. That stale state sends
# install.sh down its ours-upgrade / refresh path instead of a fresh install,
# which changes what the assertions below are actually observing. `mktemp -d`
# makes that impossible: every run gets a directory no prior run could have
# touched.
#
# Both install invocations below also capture stdout/stderr and the exit
# status instead of discarding them with `> /dev/null 2>&1 || true`. On a
# failed assertion about the install's results, or on any non-zero install
# exit status, the captured output is printed — so a failure here explains
# itself instead of requiring a re-run with the redirects removed by hand.
# ============================================================================

PID_MOCK=$(mktemp -d "${TMPDIR:-/tmp}/kinglet-pioneer-identity.XXXXXX")
INSTALL_SCRIPT="${REPO_DIR}/install.sh"

mkdir -p "${PID_MOCK}/Assets/Scripts" "${PID_MOCK}/ProjectSettings" "${PID_MOCK}/Packages"
# Two lines: Unity writes both, and a one-line fixture has hidden a real bug before.
printf 'm_EditorVersion: 6000.3.18f1\nm_EditorVersionWithRevision: 6000.3.18f1 (abcdef123456)\n' \
    > "${PID_MOCK}/ProjectSettings/ProjectVersion.txt"
printf '{\n  "dependencies": {\n    "com.unity.ugui": "1.0.0"\n  }\n}\n' \
    > "${PID_MOCK}/Packages/manifest.json"

# --- The version string ---
PID_VERSION=$(cat "${REPO_DIR}/.claude/VERSION")
assert_eq "3.0.0-pioneer.1" "$PID_VERSION" "toolkit version is 3.0.0-pioneer.1"

# --- The edition keys are machine-readable ---
PID_UPSTREAM=$(cat "${REPO_DIR}/.claude/UPSTREAM")
assert_contains "$PID_UPSTREAM" "edition=pioneer" "UPSTREAM declares edition=pioneer"
assert_contains "$PID_UPSTREAM" "supported_clients=claude" "UPSTREAM claims exactly one client"
assert_contains "$PID_UPSTREAM" "supported_hosts=linux-x64" "UPSTREAM claims exactly one host"

# --- Install, then read the contract back out of the project ---
PID_INSTALL_OUT_1=$(bash "$INSTALL_SCRIPT" --project-dir "$PID_MOCK" 2>&1)
PID_INSTALL_RC_1=$?
if [ "$PID_INSTALL_RC_1" -ne 0 ]; then
    echo "--- first install.sh invocation exited $PID_INSTALL_RC_1 ---"
    echo "$PID_INSTALL_OUT_1"
    echo "--- end install output ---"
fi

PID_RECEIPT=$(cat "${PID_MOCK}/.claude/state/install-receipt.tsv" 2>/dev/null || echo "")
if [ -z "$PID_RECEIPT" ] || [[ "$PID_RECEIPT" != *"# kinglet install receipt"* ]]; then
    echo "--- first install.sh output (receipt assertion about to fail) ---"
    echo "$PID_INSTALL_OUT_1"
    echo "--- end install output ---"
fi
assert_contains "$PID_RECEIPT" "# kinglet install receipt" "receipt header is brand-level"
assert_contains "$PID_RECEIPT" "# edition: pioneer" "receipt records the edition as data"
assert_contains "$PID_RECEIPT" "# toolkit-version: 3.0.0-pioneer.1" "receipt stamps the version"
assert_not_contains "$PID_RECEIPT" "cloud-nine" "receipt carries no retired name"

PID_CLAUDE_MD=$(cat "${PID_MOCK}/CLAUDE.md" 2>/dev/null || echo "")
if [[ "$PID_CLAUDE_MD" != *"kinglet:generated:begin"* ]]; then
    echo "--- first install.sh output (CLAUDE.md marker assertion about to fail) ---"
    echo "$PID_INSTALL_OUT_1"
    echo "--- end install output ---"
fi
assert_contains "$PID_CLAUDE_MD" "kinglet:generated:begin" "generated block opens with the brand marker"
assert_contains "$PID_CLAUDE_MD" "kinglet:generated:end" "generated block closes with the brand marker"
assert_not_contains "$PID_CLAUDE_MD" "cloud-nine" "generated CLAUDE.md carries no retired name"

# --- The marker round-trips: a re-install must FIND its own marker ---
# This is the whole reason the marker is brand-level. If the installer cannot
# recognise the block it wrote, it appends a second one.
printf '\n## My own prose\n\nDo not touch this.\n' >> "${PID_MOCK}/CLAUDE.md"
PID_INSTALL_OUT_2=$(bash "$INSTALL_SCRIPT" --project-dir "$PID_MOCK" 2>&1)
PID_INSTALL_RC_2=$?
if [ "$PID_INSTALL_RC_2" -ne 0 ]; then
    echo "--- second install.sh invocation exited $PID_INSTALL_RC_2 ---"
    echo "$PID_INSTALL_OUT_2"
    echo "--- end install output ---"
fi

PID_REINSTALLED=$(cat "${PID_MOCK}/CLAUDE.md")
if [ "$(grep -c 'kinglet:generated:begin' "${PID_MOCK}/CLAUDE.md" || true)" != "1" ] \
    || [[ "$PID_REINSTALLED" != *"Do not touch this."* ]]; then
    echo "--- second install.sh output (re-install assertion about to fail) ---"
    echo "$PID_INSTALL_OUT_2"
    echo "--- end install output ---"
fi
PID_BEGIN_COUNT=$(grep -c 'kinglet:generated:begin' "${PID_MOCK}/CLAUDE.md" || true)
assert_eq "1" "$PID_BEGIN_COUNT" "re-install refreshes the block instead of appending a second"
assert_contains "$PID_REINSTALLED" "Do not touch this." "re-install leaves the user's prose intact"

# --- The scripts that write these values carry no retired name ---
for pid_script in "${REPO_DIR}/install.sh" "${REPO_DIR}/uninstall.sh" \
                  "${REPO_DIR}/scripts/generate-claude-md.sh"; do
    PID_BODY=$(cat "$pid_script")
    assert_not_contains "$PID_BODY" "cloud-nine" "$(basename "$pid_script") carries no retired name"
done

# --- Guard: the retired name is gone from every file it should be gone from ---
#
# The exclusion list is not laziness. Each entry contains the old name for a
# reason that outlives the rename:
#   docs/superpowers/{plans,specs}/2026-07-22-* — frozen, superseded history.
#   the pioneer spec and this plan — the rename is their subject matter.
#   tests/test-pioneer-identity.sh — this file. Its subject matter IS the
#       retired name: the assertions above assert its absence by naming it
#       literally, so the string necessarily appears here forever, the same
#       way the pioneer spec and plan are excluded for being about the rename.
#   MERGE-NOTES.md — the build record. It carries legitimate historical
#       occurrences (see the exact-count check below) so it cannot be run
#       through a scan that demands zero matches. It is NOT a whole-file
#       blind spot, though: the count check re-reads it every run and fails
#       the moment a new occurrence appears anywhere in it.
#
# migration/baseline-inventory.json used to need an exclusion too — Task 3
# deleted the legacy_product_positioning section that held the name, so the
# file now has zero occurrences and needs none. It is deliberately NOT
# excluded, so a future regeneration that reintroduced the name there would
# be caught by this scan like anything else.
#
# Anything NOT on this list that still says cloud-nine is a missed rename.
set +e
PID_OFFENDERS=$(cd "$REPO_DIR" && git grep -lie "cloud.nine" \
    -- . \
    ':(exclude)docs/superpowers/plans/2026-07-22-*' \
    ':(exclude)docs/superpowers/specs/2026-07-22-*' \
    ':(exclude)docs/superpowers/specs/2026-07-29-kinglet-pioneer-design.md' \
    ':(exclude)docs/superpowers/plans/2026-07-29-kinglet-pioneer-wave-1a-identity.md' \
    ':(exclude)MERGE-NOTES.md' \
    ':(exclude)tests/test-pioneer-identity.sh')
PID_OFFENDERS_RC=$?
set -e
# git grep exits 1 on "no match", which is the success case here — but exit
# codes >= 2 (bad pathspec, corrupt index, git missing) and a failed `cd` also
# produce an empty PID_OFFENDERS, which would otherwise be indistinguishable
# from a clean tree and pass vacuously. Accept only 0 or 1.
if [ "$PID_OFFENDERS_RC" -gt 1 ]; then
    echo "--- git grep (offender scan) exited $PID_OFFENDERS_RC, expected 0 or 1 ---"
    echo "$PID_OFFENDERS"
    echo "--- end git grep output ---"
fi
assert_eq "0" "$([ "$PID_OFFENDERS_RC" -le 1 ] && echo 0 || echo "$PID_OFFENDERS_RC")" \
    "offender scan's git grep exited 0 or 1, not an error code"
assert_eq "" "$PID_OFFENDERS" "no tracked file outside the recorded exclusions says cloud-nine"

# --- Guard: the exclusion pathspecs still bind ---
# If ':(exclude)...' syntax ever silently stopped matching (a git version
# change, a typo), every excluded file would still show up as an "offender" —
# except MERGE-NOTES.md and this test file are ALSO excluded, and MERGE-NOTES.md
# alone would swallow that failure by legitimately containing the name, and an
# all-excluding guard would look identical to a clean tree either way. Running
# the same search with NO exclusions proves the pathspecs are still doing
# something: this file and MERGE-NOTES.md both say "cloud-nine" literally, so
# an unexcluded scan must find at least them.
set +e
PID_UNEXCLUDED=$(cd "$REPO_DIR" && git grep -lie "cloud.nine" -- .)
PID_UNEXCLUDED_RC=$?
set -e
if [ "$PID_UNEXCLUDED_RC" -gt 1 ]; then
    echo "--- git grep (unexcluded sanity scan) exited $PID_UNEXCLUDED_RC, expected 0 or 1 ---"
    echo "$PID_UNEXCLUDED"
    echo "--- end git grep output ---"
fi
PID_UNEXCLUDED_NONEMPTY="empty"
if [ -n "$PID_UNEXCLUDED" ]; then
    PID_UNEXCLUDED_NONEMPTY="nonempty"
fi
assert_eq "nonempty" "$PID_UNEXCLUDED_NONEMPTY" \
    "unexcluded scan still finds occurrences (proves the pathspecs still bind)"

# --- Guard: MERGE-NOTES.md's retained occurrences are counted, not hand-waved ---
# Exactly 5, each historical:
#   line 3   — the opening line, naming both the original and current product.
#   line 9   — Part 1 section, describing what cloud-nine-unity was at the time.
#   line 98  — records the original repo name as a past decision, plus the rename.
#   line 115 — "Kinglet Pioneer (then named cloud-nine-unity)" — true when written.
#   line 259 — quotes the placeholder licence-holder string Part 1 shipped.
# A new occurrence anywhere in this file changes the count and fails here.
PID_MERGE_NOTES_COUNT=$(grep -cie "cloud.nine" "${REPO_DIR}/MERGE-NOTES.md")
assert_eq "5" "$PID_MERGE_NOTES_COUNT" "MERGE-NOTES.md retains exactly its 5 historical occurrences"

# --- Guard: upstream attribution survived the rename ---
# A careless sweep is capable of eating the MIT obligations along with our own
# name. These are the licence conditions, not decoration.
PID_CREDITS=$(cat "${REPO_DIR}/CREDITS.md")
assert_contains "$PID_CREDITS" "everything-claude-unity" "ECU attribution survives"
assert_contains "$PID_CREDITS" "Claude-Code-Game-Studios" "Donchitos attribution survives"
PID_NOTICE=$(cat "${REPO_DIR}/.claude/NOTICE.md")
assert_contains "$PID_NOTICE" "MIT" "the shipped NOTICE still states the licence"

rm -rf "$PID_MOCK"
