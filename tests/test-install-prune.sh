#!/usr/bin/env bash
# ============================================================================
# test-install-prune.sh — an upgrade must remove what the payload dropped,
# and must never remove a file the user edited.
#
# The installer only ever added. The 2026-08-03 surface cut removed 74 files,
# and installing over an older install left every one of them on disk and
# selectable — 114 orphans measured against a real project. The cut was
# invisible in the only place it matters, because the model still saw the
# deleted agents.
#
# The other half is the one that costs more when it is wrong: a file the user
# edited is theirs, whatever the payload now says. Removing it is the same
# class of loss as overwriting it, and this installer has already done that
# once in the field.
#
# Runner-provided: uses the runner's assert_eq and $REPO_DIR, defines neither.
# `bash tests/test-install-prune.sh` standalone exits 0 having asserted
# nothing — run it through tests/run-tests.sh and read this section.
# ============================================================================

echo "--- install prune ---"

PRUNE_DIR="/tmp/kinglet-prune-test-$$"
mkdir -p "$PRUNE_DIR/Assets/Scripts" "$PRUNE_DIR/ProjectSettings" "$PRUNE_DIR/Packages"
printf 'm_EditorVersion: 6000.0.23f1\nm_EditorVersionWithRevision: 6000.0.23f1 (b2c3d4e5f6a7)\n' \
  > "$PRUNE_DIR/ProjectSettings/ProjectVersion.txt"
printf '{\n  "dependencies": {\n    "com.unity.ugui": "2.0.0"\n  }\n}\n' > "$PRUNE_DIR/Packages/manifest.json"

# A first install, then two files planted as if a previous payload had shipped them: one the user
# leaves alone, one the user edits. Both are recorded in the receipt, so the next run sees them as
# files this toolkit owns — which is exactly the state an upgrade after a surface cut arrives in.
bash "$REPO_DIR/install.sh" --project-dir "$PRUNE_DIR" >/dev/null 2>&1

DROPPED_CLEAN="$PRUNE_DIR/.claude/agents/gone-untouched.md"
DROPPED_EDITED="$PRUNE_DIR/.claude/agents/gone-edited.md"
printf -- '---\nname: gone-untouched\n---\nfrom an older payload\n' > "$DROPPED_CLEAN"
printf -- '---\nname: gone-edited\n---\nfrom an older payload\n' > "$DROPPED_EDITED"

RECEIPT="$PRUNE_DIR/.claude/state/install-receipt.tsv"
printf '.claude/agents/gone-untouched.md\t%s\t644\ttoolkit\n' \
  "$(sha256sum "$DROPPED_CLEAN" | cut -d' ' -f1)" >> "$RECEIPT"
printf '.claude/agents/gone-edited.md\t%s\t644\ttoolkit\n' \
  "$(sha256sum "$DROPPED_EDITED" | cut -d' ' -f1)" >> "$RECEIPT"

# Now the user edits one of them. Its checksum no longer matches the receipt, which is the only
# signal the installer has that a file stopped being ours.
printf 'a line the user added\n' >> "$DROPPED_EDITED"

bash "$REPO_DIR/install.sh" --project-dir "$PRUNE_DIR" >/dev/null 2>&1

assert_eq "$([ -e "$DROPPED_CLEAN" ] && echo present || echo removed)" "removed" \
  "an untouched file the payload no longer ships is removed on upgrade"

assert_eq "$([ -e "$DROPPED_EDITED" ] && echo present || echo removed)" "present" \
  "a file the user edited is never removed, even when the payload drops it"

assert_eq "$(grep -c 'a line the user added' "$DROPPED_EDITED" 2>/dev/null || echo 0)" "1" \
  "the user's edit to a dropped file survives intact"

# The receipt must stop claiming a file that is gone, or the next run reports it as an orphan again.
assert_eq "$(cut -f1 "$RECEIPT" | grep -cxF '.claude/agents/gone-untouched.md' || true)" "0" \
  "the receipt no longer lists the removed file"

# A skill directory emptied by the cut still reads as a skill to anything listing the tree.
assert_eq "$(find "$PRUNE_DIR/.claude" -mindepth 1 -type d -empty 2>/dev/null | grep -c . || true)" "0" \
  "no empty directory is left behind by a removal"

# Nothing outside .claude/ is in scope. The receipt also records .mcp.json and MCP-SETUP.md, and an
# over-broad prune would delete a user's MCP configuration.
assert_eq "$([ -f "$PRUNE_DIR/.claude/settings.json" ] && echo present || echo gone)" "present" \
  "files still in the payload are untouched by the prune"

# A refresh must be idempotent. install.sh used to print the "## Project Facts" heading itself and
# then insert --facts-only's output, which prints that heading too — one region, two producers. The
# generator's own comment warns about exactly this and the fix had been applied on one side only,
# so every re-install added another empty heading. A real project was found carrying two.
#
# Two installs have already run above, so any duplication is present by now.
assert_eq "$(grep -c 'Project Facts (auto-detected)' "$PRUNE_DIR/CLAUDE.md" 2>/dev/null || echo 0)" "1" \
  "re-installing does not duplicate the generated heading"

assert_eq "$(grep -c 'kinglet:generated:begin' "$PRUNE_DIR/CLAUDE.md" 2>/dev/null || echo 0)" "1" \
  "re-installing does not duplicate the generated-region markers"

# A kept edit must stay kept, upgrade after upgrade.
#
# When a run keeps your edit it records the file as it then stands. A sha-only test therefore finds
# the checksum matching the receipt on the NEXT run, concludes the file is untouched, and overwrites
# it. The edit survived exactly one upgrade and then vanished with no message. Measured twice on the
# same file in one day, on a real project, hours apart — the second time while verifying the fix for
# the first. Two installs are not enough to catch it; the third is where it died.
STICKY="$PRUNE_DIR/.claude/hooks/block-scene-edit.sh"
printf '\n# a line the user added\n' >> "$STICKY"
bash "$REPO_DIR/install.sh" --project-dir "$PRUNE_DIR" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$PRUNE_DIR" >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$PRUNE_DIR" >/dev/null 2>&1

assert_eq "$(grep -c 'a line the user added' "$STICKY" 2>/dev/null || echo 0)" "1" \
  "an edit kept by one upgrade is still kept three upgrades later"

rm -rf "$PRUNE_DIR"
