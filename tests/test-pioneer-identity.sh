#!/usr/bin/env bash
# ============================================================================
# test-pioneer-identity.sh — Tests the Kinglet Pioneer identity contract.
#
# These four values are written into (or read back out of) a USER'S Unity
# project. Changing them after a first install strands the previous values in
# a file we no longer recognise: the installer would not find its own markers
# in the user's CLAUDE.md and would append a second generated block. So they
# are pinned by behaviour, not by reading our own source.
# ============================================================================

PID_MOCK="/tmp/kinglet-pioneer-identity-$$"
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
bash "$INSTALL_SCRIPT" --project-dir "$PID_MOCK" > /dev/null 2>&1 || true

PID_RECEIPT=$(cat "${PID_MOCK}/.claude/state/install-receipt.tsv" 2>/dev/null || echo "")
assert_contains "$PID_RECEIPT" "# kinglet install receipt" "receipt header is brand-level"
assert_contains "$PID_RECEIPT" "# edition: pioneer" "receipt records the edition as data"
assert_contains "$PID_RECEIPT" "# toolkit-version: 3.0.0-pioneer.1" "receipt stamps the version"
assert_not_contains "$PID_RECEIPT" "cloud-nine" "receipt carries no retired name"

PID_CLAUDE_MD=$(cat "${PID_MOCK}/CLAUDE.md" 2>/dev/null || echo "")
assert_contains "$PID_CLAUDE_MD" "kinglet:generated:begin" "generated block opens with the brand marker"
assert_contains "$PID_CLAUDE_MD" "kinglet:generated:end" "generated block closes with the brand marker"
assert_not_contains "$PID_CLAUDE_MD" "cloud-nine" "generated CLAUDE.md carries no retired name"

# --- The marker round-trips: a re-install must FIND its own marker ---
# This is the whole reason the marker is brand-level. If the installer cannot
# recognise the block it wrote, it appends a second one.
printf '\n## My own prose\n\nDo not touch this.\n' >> "${PID_MOCK}/CLAUDE.md"
bash "$INSTALL_SCRIPT" --project-dir "$PID_MOCK" > /dev/null 2>&1 || true

PID_REINSTALLED=$(cat "${PID_MOCK}/CLAUDE.md")
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
#   migration/baseline-inventory.json — evidence anchored at a commit; the
#       baseline verifier reads blobs AT that commit, so the working tree
#       cannot invalidate it, but editing the record would.
#   docs/superpowers/{plans,specs}/2026-07-22-* — frozen, superseded history.
#   the pioneer spec and this plan — the rename is their subject matter.
#   MERGE-NOTES.md — the build record. Its one live occurrence is deliberately
#       kept, in the parenthetical "Kinglet Pioneer (then named cloud-nine-unity)",
#       because the sentence describes what Part 2 of the merge produced at the
#       time, under the name it had then. Rewriting it to omit the old name
#       would make the record claim something untrue.
#   tests/test-pioneer-identity.sh — this file. Its subject matter IS the
#       retired name: the assertions above assert its absence by naming it
#       literally, so the string necessarily appears here forever, the same
#       way the pioneer spec and plan are excluded for being about the rename.
#
# Anything NOT on this list that still says cloud-nine is a missed rename.
PID_OFFENDERS=$(cd "$REPO_DIR" && git grep -lie "cloud.nine" \
    -- . \
    ':(exclude)migration/baseline-inventory.json' \
    ':(exclude)docs/superpowers/plans/2026-07-22-*' \
    ':(exclude)docs/superpowers/specs/2026-07-22-*' \
    ':(exclude)docs/superpowers/specs/2026-07-29-kinglet-pioneer-design.md' \
    ':(exclude)docs/superpowers/plans/2026-07-29-kinglet-pioneer-wave-1a-identity.md' \
    ':(exclude)MERGE-NOTES.md' \
    ':(exclude)tests/test-pioneer-identity.sh' \
    || true)
assert_eq "" "$PID_OFFENDERS" "no tracked file outside the recorded exclusions says cloud-nine"

# --- Guard: upstream attribution survived the rename ---
# A careless sweep is capable of eating the MIT obligations along with our own
# name. These are the licence conditions, not decoration.
PID_CREDITS=$(cat "${REPO_DIR}/CREDITS.md")
assert_contains "$PID_CREDITS" "everything-claude-unity" "ECU attribution survives"
assert_contains "$PID_CREDITS" "Claude-Code-Game-Studios" "Donchitos attribution survives"
PID_NOTICE=$(cat "${REPO_DIR}/.claude/NOTICE.md")
assert_contains "$PID_NOTICE" "MIT" "the shipped NOTICE still states the licence"

rm -rf "$PID_MOCK"
