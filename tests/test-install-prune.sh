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

assert_eq "removed" "$([ -e "$DROPPED_CLEAN" ] && echo present || echo removed)" \
  "an untouched file the payload no longer ships is removed on upgrade"

assert_eq "present" "$([ -e "$DROPPED_EDITED" ] && echo present || echo removed)" \
  "a file the user edited is never removed, even when the payload drops it"

assert_eq "1" "$(grep -c 'a line the user added' "$DROPPED_EDITED" 2>/dev/null || echo 0)" \
  "the user's edit to a dropped file survives intact"

# The receipt must stop claiming a file that is gone, or the next run reports it as an orphan again.
assert_eq "0" "$(cut -f1 "$RECEIPT" | grep -cxF '.claude/agents/gone-untouched.md' || true)" \
  "the receipt no longer lists the removed file"

# A skill directory emptied by the cut still reads as a skill to anything listing the tree.
assert_eq "0" "$(find "$PRUNE_DIR/.claude" -mindepth 1 -type d -empty 2>/dev/null | grep -c . || true)" \
  "no empty directory is left behind by a removal"

# Nothing outside .claude/ is in scope. The receipt also records .mcp.json and MCP-SETUP.md, and an
# over-broad prune would delete a user's MCP configuration.
assert_eq "present" "$([ -f "$PRUNE_DIR/.claude/settings.json" ] && echo present || echo gone)" \
  "files still in the payload are untouched by the prune"

# A refresh must be idempotent. install.sh used to print the "## Project Facts" heading itself and
# then insert --facts-only's output, which prints that heading too — one region, two producers. The
# generator's own comment warns about exactly this and the fix had been applied on one side only,
# so every re-install added another empty heading. A real project was found carrying two.
#
# Two installs have already run above, so any duplication is present by now.
assert_eq "1" "$(grep -c 'Project Facts (auto-detected)' "$PRUNE_DIR/CLAUDE.md" 2>/dev/null || echo 0)" \
  "re-installing does not duplicate the generated heading"

assert_eq "1" "$(grep -c 'kinglet:generated:begin' "$PRUNE_DIR/CLAUDE.md" 2>/dev/null || echo 0)" \
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

assert_eq "1" "$(grep -c 'a line the user added' "$STICKY" 2>/dev/null || echo 0)" \
  "an edit kept by one upgrade is still kept three upgrades later"

# The test suite must not ship into a project.
#
# check-provenance.sh was excluded from the payload because a check that can only fail in the
# environment it ships to trains people to ignore checks. Measured 2026-08-04, that argument had been
# applied to one script and not to the class: the shipped suite gives 143 failures out of 229
# assertions in a real installed project, and always has — run-tests.sh resolves REPO_DIR to the
# parent of tests/, which is `.claude/` there rather than a repo root, and a large share of the files
# reference install.sh, provenance.tsv, tests/fixtures/ or the baseline, none of which ship. (Read
# "twelve of the files" until 2026-08-12 — a second copy of the same hardcoded count install.sh
# carried, stale in both places at once. Derive it; install.sh's Step 5 comment has the command.)
#
# scripts/studio-doctor.sh is what a project actually needs and it does ship.
assert_eq "absent" "$([ -d "$PRUNE_DIR/.claude/tests" ] && echo present || echo absent)" \
  "the test suite does not ship into an installed project"

assert_eq "present" "$([ -f "$PRUNE_DIR/.claude/scripts/studio-doctor.sh" ] && echo present || echo absent)" \
  "the project-facing health check does ship"

rm -rf "$PRUNE_DIR"

# ============================================================================
# Upgrade across a payload that shrank — the half of the prune that lives in a
# file the prune is forbidden to touch.
#
# Everything above proves the FILES are retired correctly. A hook is not a file:
# it is a file plus an entry in settings.json, and settings.json is the
# most-edited file in the payload, so on any real project it is the user's and
# it is kept. The prune therefore deletes a retired hook's script and leaves the
# entry naming it, in a file it is right not to rewrite. Claude Code reports
# nothing about a hook command it cannot find — the registration is simply dead,
# and it stays dead, because the kept file is kept again on every later run.
#
# Measured on the real upgrade across the 2026-08-13 cut, from the pre-cut
# commit to the current tree: 27 registrations over 12 hooks on disk, 15 of them
# naming deleted scripts, and `Hooks 27` printed under `Installation complete.`
# One appended newline in settings.json is the whole trigger.
#
# THE FIXTURE IS AN UPGRADE, NOT A FRESH INSTALL, and that is the durable point
# rather than an implementation detail: every artifact this suite reviews is a
# repository, while the artifact that breaks is a user's project. A change to
# the payload's SHAPE is invisible to a fresh-install fixture by construction —
# there is no previous state for the new shape to disagree with.
#
# Both directions are asserted. The upgrade below must report the dead entry and
# print an honest count; the control beside it — same shrunk payload, same cut,
# settings.json never touched — must report nothing, because ours is overwritten
# and the entry goes with it. A check that fires on the second project is a check
# that would fire on every ordinary install.
echo "--- install prune: upgrade across a payload that shrank ---"

UPG_ROOT="$(mktemp -d)"
UPG_DIR="$UPG_ROOT/proj"
CTL_DIR="$UPG_ROOT/control"
SHRUNK="$UPG_ROOT/payload"

# A realistic project, from the fixture the suite already owns, rather than a
# hand-built directory: mkproject.sh writes the two-line ProjectVersion.txt Unity
# actually writes, and a one-line stand-in has hidden a real bug here before.
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$UPG_DIR" --variant urp >/dev/null 2>&1
bash "$REPO_DIR/tests/fixtures/mkproject.sh" "$CTL_DIR" --variant urp >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$UPG_DIR" --yes >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --project-dir "$CTL_DIR" --yes >/dev/null 2>&1

# The next payload, one hook smaller. Copied from the WORKING TREE and not from
# `git archive HEAD`: the point is to exercise the install.sh sitting on disk, and
# an archive of HEAD would silently test the committed copy instead. Only what
# install.sh reads from $SCRIPT_DIR is copied — .claude/, scripts/, MCP-SETUP.md
# and install.sh itself; `cp -pR` so the hooks keep their exec bits.
mkdir -p "$SHRUNK"
cp -pR "$REPO_DIR/.claude" "$SHRUNK/.claude"
cp -pR "$REPO_DIR/scripts" "$SHRUNK/scripts"
cp -p "$REPO_DIR/MCP-SETUP.md" "$SHRUNK/MCP-SETUP.md"
cp -p "$REPO_DIR/install.sh" "$SHRUNK/install.sh"
rm -rf "$SHRUNK/.claude/state"

# A cut removes both halves — the script and its registration. Removing only the
# script would leave the payload registering a hook it does not ship, which is the
# defect this fixture is about, pointed the other way. python3 rather than sed:
# the entry is nested three deep in JSON and a text deletion can leave a file that
# parses nowhere. The suite already depends on python3 in test-install-not-done.sh.
# TWO hooks leave the payload, and the difference between them is the whole point.
#
# CUT_HOOK is untouched, so the prune deletes it and its registration is left
# naming nothing. KEPT_HOOK the user has edited, so ORPHAN_KEPT leaves it on disk
# — and a registration whose file is still there STILL FIRES, whatever the payload
# now says. One fixture, both answers, on a state this installer creates itself.
#
# Without KEPT_HOOK this section pins that the check FIRES, not what it TESTS.
# Measured: an install.sh whose predicate asked "is it still in the payload?"
# instead of "is it still on disk?" passed every other assertion here. That
# predicate is wrong on exactly this state, and self-contradictory within one run
# — it warns that the file is not there while the summary beside it counts the
# same hook live.
CUT_HOOK='warn-filename.sh'
KEPT_HOOK='warn-platform-defines.sh'
UPG_CUT_HOOKS="$CUT_HOOK
$KEPT_HOOK"
UPG_CUT_N="$(printf '%s\n' "$UPG_CUT_HOOKS" | grep -c . || true)"

while IFS= read -r upg_h; do
  [ -n "$upg_h" ] || continue
  rm -f "$SHRUNK/.claude/hooks/$upg_h"
done <<< "$UPG_CUT_HOOKS"
python3 - "$SHRUNK/.claude/settings.json" $UPG_CUT_HOOKS <<'PY'
import json, sys
path, hooks = sys.argv[1], sys.argv[2:]
targets = [".claude/hooks/" + h for h in hooks]
with open(path) as fh:
    doc = json.load(fh)
events = doc.get("hooks", {})
for event, groups in events.items():
    for group in groups:
        group["hooks"] = [h for h in group.get("hooks", [])
                          if not any(t in h.get("command", "") for t in targets)]
doc["hooks"] = {e: [g for g in gs if g.get("hooks")] for e, gs in events.items()}
with open(path, "w") as fh:
    json.dump(doc, fh, indent=2)
    fh.write("\n")
PY

# `>>` CREATES. Either append below would manufacture the very file whose state it
# is supposed to be perturbing, had the install above failed, so each is preceded
# by the check that makes it an edit rather than a fixture.
assert_file_exists "$UPG_DIR/.claude/settings.json" \
  "the first install left a settings.json to edit — the append below perturbs it, it does not create it"
assert_file_exists "$UPG_DIR/.claude/hooks/$KEPT_HOOK" \
  "the first install left the hook the user is about to edit"

# One appended newline is the entire difference between "ours" and "yours". This
# is not a contrived edit: settings.json is where a plugin gets disabled or a
# permission widened, so on a real project it has drifted long before the upgrade.
printf '\n' >> "$UPG_DIR/.claude/settings.json"
printf '\n# a line the user added\n' >> "$UPG_DIR/.claude/hooks/$KEPT_HOOK"
UPG_SETTINGS_BEFORE="$(sha256sum "$UPG_DIR/.claude/settings.json" | cut -d' ' -f1)"

# The status is captured, not swallowed. `$(cmd | sed)` reports sed's rc, and exit
# 0 is half the contract this section defends: the point of the Not done: block is
# that a run which abandons work still ends 0 and says so. `|| UPG_RC=$?` rather
# than a bare call, so the capture survives a future `set -e` in this file.
UPG_RC=0
CTL_RC=0
bash "$SHRUNK/install.sh" --project-dir "$UPG_DIR" --yes > "$UPG_ROOT/upgrade.log" 2>&1 || UPG_RC=$?
bash "$SHRUNK/install.sh" --project-dir "$CTL_DIR" --yes > "$UPG_ROOT/control.log" 2>&1 || CTL_RC=$?
UPG_OUT="$(sed $'s/\x1b\\[[0-9;]*m//g' "$UPG_ROOT/upgrade.log")"
CTL_OUT="$(sed $'s/\x1b\\[[0-9;]*m//g' "$UPG_ROOT/control.log")"

# The dead-registration block's OWN list, not the whole log. Three blocks in this
# run print a 7-space indented path — kept orphans, unregistered hooks, dead
# registrations — so a log-wide grep for a hook name answers a different question
# than the one being asked, and answers it wrongly for KEPT_HOOK, which appears
# under kept orphans by design.
UPG_DEAD_LIST="$(printf '%s\n' "$UPG_OUT" | awk '
  /^warn Your settings.json was kept, so [0-9]+ hook registration\(s\)/ { inb = 1; next }
  inb && /^ +\.claude\// { sub(/^ +/, ""); print; next }
  inb { inb = 0 }
')"

assert_eq "0" "$UPG_RC" \
  "the upgrade ends 0 — a run that reports abandoned work still succeeds"

# The precondition, asserted rather than assumed: without the prune actually
# removing the script, every assertion below would be green for the wrong reason.
assert_eq "removed" "$([ -e "$UPG_DIR/.claude/hooks/$CUT_HOOK" ] && echo present || echo removed)" \
  "the retired hook's script is pruned even though the kept settings.json still names it"

# The other precondition, and the one that gives the assertion after it something
# to be about: the edited hook survives the cut, so its registration is live.
assert_eq "present" "$([ -e "$UPG_DIR/.claude/hooks/$KEPT_HOOK" ] && echo present || echo removed)" \
  "a hook the user edited survives the payload dropping it, so its registration still fires"

# The warning names the dead entry, by path, on its own line.
assert_eq "1" "$(printf '%s\n' "$UPG_DEAD_LIST" | grep -cxF ".claude/hooks/$CUT_HOOK" || true)" \
  "the upgrade names the registration left pointing at a file the payload dropped"

# And does NOT name the other one. This is the assertion that separates "is it on
# disk?" from "is it in the payload?" — the two predicates agree everywhere except
# on this state, and everything else in this section passes under either.
assert_eq "0" "$(printf '%s\n' "$UPG_DEAD_LIST" | grep -cxF ".claude/hooks/$KEPT_HOOK" || true)" \
  "a registration whose file is still there is not called dead, even though the payload dropped it"

# And names ONLY it. Asserting that the cut hook appears is satisfied by a check
# that reports every registration in the file as dead, which is a live mutant:
# measured, the whole of this section stayed green against an install.sh whose
# existence test had been deleted outright. The headline count is the number the
# reader acts on, so it is the one pinned.
assert_eq "1" \
  "$(printf '%s\n' "$UPG_OUT" | sed -n 's/^warn Your settings.json was kept, so \([0-9][0-9]*\) hook registration(s).*/\1/p')" \
  "exactly one registration is reported dead — the ones whose files are still there are not"

# The summary is honest about it. Derived from the tree, never typed: the
# registration total is whatever this version's settings.json carries, and of the
# hooks cut from the payload above exactly one lost its file.
UPG_REG_TOTAL="$(grep -oE '\.claude/hooks/[a-z_-]+\.sh' "$REPO_DIR/.claude/settings.json" | sort -u | grep -c . || true)"
assert_eq "$((UPG_REG_TOTAL - 1)) ($UPG_REG_TOTAL registered, 1 dead)" \
  "$(printf '%s\n' "$UPG_OUT" | sed -n 's/^  Hooks  *//p')" \
  "the Hooks summary counts what will fire and says how many entries are dead"

# `Not done:` is the contract MCP-SETUP.md makes: an exit-0 run with no such block
# abandoned nothing. A registration this installer will not repair is abandoned
# work, so it belongs in the block and not only in a warn line the reader scrolled
# past four hundred lines ago.
#
# The decision is made in END and not by an `exit` inside the body. An awk that
# exits early stops draining, the `printf` on the left of the pipe takes SIGPIPE,
# and `pipefail` promotes 141 — the standing constraint this repository keeps
# relearning. It is inert here only because the runner clears errexit before
# sourcing, which is not a property to build on.
assert_eq "found" \
  "$(printf '%s\n' "$UPG_OUT" | awk '/^Not done:$/ { f = 1; next } f && /hook registration\(s\) listed above/ { hit = 1 } END { if (hit) print "found" }')" \
  "the dead registration reaches the Not done: block, not just a warn line"

# WARN, DO NOT EDIT. The file was kept because it is the user's; measured by
# checksum and not by size, because a rewrite of a JSON file can land on the same
# byte count. This is the assertion that would catch a future "fix" that helpfully
# merges the user's settings.json.
assert_eq "$UPG_SETTINGS_BEFORE" "$(sha256sum "$UPG_DIR/.claude/settings.json" | cut -d' ' -f1)" \
  "the kept settings.json is reported on and never rewritten"

# The control. Same shrunk payload, same retired hooks, a settings.json that is
# still ours — so it is replaced, the entries go with it, and there is nothing to
# report. A check that also fired here would fire on every ordinary upgrade.
assert_eq "0" "$CTL_RC" \
  "the control upgrade ends 0 too"

assert_eq "0" "$(printf '%s\n' "$CTL_OUT" | grep -cxF "       .claude/hooks/$CUT_HOOK" || true)" \
  "a project that never edited settings.json gets the cut applied and is warned about nothing"

assert_eq "$((UPG_REG_TOTAL - UPG_CUT_N))" "$(printf '%s\n' "$CTL_OUT" | sed -n 's/^  Hooks  *//p')" \
  "the honest count collapses to a bare number when no registration is dead"

rm -rf "$UPG_ROOT"
