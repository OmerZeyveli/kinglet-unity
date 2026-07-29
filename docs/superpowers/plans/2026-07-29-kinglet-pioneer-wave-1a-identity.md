# Kinglet Pioneer — Wave 1a (Identity) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire the name `cloud-nine-unity` and establish the Kinglet Pioneer identity — including the two identifiers the installer writes into a user's Unity project — before anything is installed anywhere.

**Architecture:** Two tasks. Task 1 changes the identity *contract*: the version string, the generated-block markers written into the user's `CLAUDE.md`, the install receipt header, and the machine-readable edition keys in `.claude/UPSTREAM`. These are the values that become expensive to change after a first install, and they are covered by a new behavioural test that installs into a mock project and reads the results back. Task 2 changes the remaining prose and banners, and lands a repository-wide guard asserting the old name is gone everywhere it should be gone.

**Tech Stack:** bash 3.2-compatible shell, the existing `tests/run-tests.sh` harness (auto-discovers `tests/test-*.sh`), `scripts/check-provenance.sh`.

## Global Constraints

- **Bash 3.2 (macOS) compatible.** No `declare -A`. No `grep -oP` and no `grep -qP` — GNU-only.
- **Never pipe into `head`** under `set -euo pipefail`. Read with `awk` instead.
- **Validate an argument before `shift 2`** — `shift` fails under `set -u` before an error message can print.
- **`scripts/check-provenance.sh` must pass at every commit.** A red manifest is a failed change, not a follow-up.
- **`bash tests/run-tests.sh` must pass at every commit.** It currently reports 99 assertions across 8 files; after this plan it is 9 files. Confirm every file still appears in the output — the runner has silently skipped files before.
- **Upstream attribution is untouched.** Every mention of Everything Claude Unity, Claude-Code-Game-Studios, XeldarAlz, Donchitos, CoplayDev, their repository URLs, their commits, and their MIT notices survives verbatim. This rename changes our name, not theirs.
- **Do NOT edit these files.** They contain `cloud-nine` legitimately and permanently:

  | Path | Why |
  |---|---|
  | `migration/baseline-inventory.json` | Evidence anchored at commit `72e4218b8837e295ece20b17cd38aa26c58298fb`. `tools/kinglet_build/baseline.py` verifies it with `git ls-tree` + `git cat-file` **at that commit**, so the working tree cannot invalidate it — but editing the record would. |
  | `docs/superpowers/plans/2026-07-22-*.md` | Frozen history. Superseded, must not be executed, must not be rewritten. |
  | `docs/superpowers/specs/2026-07-22-kinglet-for-unity-design.md` | Same. |
  | `docs/superpowers/specs/2026-07-29-kinglet-pioneer-design.md` | Describes the rename; the old name is the subject matter. |
  | `docs/superpowers/plans/2026-07-29-kinglet-pioneer-wave-1a-identity.md` | This file, for the same reason. |

- **Provenance status transitions: none.** Every file this plan edits is already `origin=original status=original` or already `status=modified`. Verified against `provenance.tsv`. New files added by this plan need a new row with `origin=original`, `status=original`.

## Deviation from the spec, recorded

The spec's Item 7 bundles two things: the MCP pin and teaching `provenance.tsv` the `superpowers` origin. **Neither is in this plan.**

- **The MCP pin** is set by the smoke pass, per the spec's own rule that Pioneer pins what it actually ran against. Writing a value now would be a placeholder.
- **The `superpowers` origin** has no file to describe yet. The first Superpowers-derived file arrives in Wave 2 (Items 4–6). Adding the origin now is speculative surface of exactly the kind `csharp-unity.md` forbids: *"If you can't name a concrete caller in the current codebase, it stays private."* It moves to the Wave 2 task that adapts the first file, where it will have one.

Both are recorded in the Wave 1b plan's preconditions.

---

### Task 1: The identity contract

Changes the four values that get written into a user's Unity project or read back out of it, plus the version they are stamped with.

**Files:**
- Modify: `.claude/VERSION` (whole file)
- Modify: `.claude/UPSTREAM` (whole file)
- Modify: `install.sh:65`, `install.sh:72`, `install.sh:105`, `install.sh:110`, `install.sh:168`, `install.sh:223`, `install.sh:263`, `install.sh:267-268`, `install.sh:366`
- Modify: `uninstall.sh:3`, `uninstall.sh:56`, `uninstall.sh:64`
- Modify: `scripts/generate-claude-md.sh:263`, `scripts/generate-claude-md.sh:290`, `scripts/generate-claude-md.sh:296`
- Test: `tests/test-pioneer-identity.sh` (create)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: the string constants Task 2's guard test relies on — `kinglet:generated:begin`, `kinglet:generated:end`, `# kinglet install receipt`, `# edition: pioneer`, and the version `3.0.0-pioneer.1`.

- [ ] **Step 1: Write the failing test**

Create `tests/test-pioneer-identity.sh`. It follows the convention of `tests/test-install.sh`: the runner executes it in a subshell with `REPO_DIR` set and the assertion helpers already defined, so the file declares no shebang boilerplate of its own beyond the header comment.

```bash
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

rm -rf "$PID_MOCK"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/run-tests.sh 2>&1 | grep -A40 'test-pioneer-identity'`

Expected: FAIL. `toolkit version is 3.0.0-pioneer.1` fails with actual `2.0.0`; `UPSTREAM declares edition=pioneer` fails; the receipt, marker, and no-retired-name assertions all fail.

Confirm the failures are about missing values, not about the test file erroring — a test that errors proves nothing.

- [ ] **Step 3: Set the version and the edition keys**

`.claude/VERSION` — replace the entire contents with:

```
3.0.0-pioneer.1
```

`.claude/UPSTREAM` — replace the first four lines and append three keys. The file is `key=value`, dependency-free to parse, so keep it that way:

```
# Kinglet Pioneer — vendored upstream pins
# key=value, dependency-free to parse. provenance.tsv holds the per-file truth; this is the summary.
toolkit=kinglet
edition=pioneer
toolkit_version=3.0.0-pioneer.1
supported_clients=claude
supported_hosts=linux-x64
```

Leave every `ecu=`, `donchitos=`, and `unity_mcp=` line below it exactly as it is. The `unity_mcp=10.1.0` line is knowingly left alone here; Wave 1b reconciles it against the smoke pass.

- [ ] **Step 4: Change the markers and the receipt header**

`scripts/generate-claude-md.sh` — three lines:

```bash
# line 263
> Unity 6 · C# · PC / Console · built with Kinglet Pioneer.

# line 290
echo "<!-- kinglet:generated:begin — content between these markers is rewritten on re-install. Everything outside is yours. -->"

# line 296
echo "<!-- kinglet:generated:end -->"
```

`install.sh` — the marker appears in three places and all three must agree, or the dry run reports one branch while the real install takes another:

```bash
# line 168 (dry-run branch)
  elif grep -q 'kinglet:generated:begin' "$PROJECT_DIR/CLAUDE.md" 2>/dev/null; then

# line 263 (real install branch)
  elif grep -q 'kinglet:generated:begin' "$CLAUDE_MD"; then

# lines 267-268 (the awk that refreshes the block)
        /kinglet:generated:begin/ { print; print ""; print "## Project Facts (auto-detected)"; print ""; while ((getline l < factsfile) > 0) print l; skip=1; next }
        /kinglet:generated:end/   { print ""; print; skip=0; next }
```

`install.sh` — the receipt header at line 366, plus the new edition line:

```bash
  printf '# kinglet install receipt\n'
  printf '# edition: pioneer\n'
```

`install.sh` — the four remaining prose strings:

```bash
# line 3 (file header comment)
# Kinglet Pioneer — installer

# line 65
printf '%s\n' "${BOLD}Kinglet Pioneer ${TOOLKIT_VERSION}${NC} — installer"

# line 72
[ -d "$SCRIPT_DIR/.claude" ] || die "Payload not found at $SCRIPT_DIR/.claude — run install.sh from the kinglet-unity repo root."

# line 105
    info "Existing Kinglet install found (version $PREV) — upgrading to $TOOLKIT_VERSION."

# line 110
    warn "Kinglet did not create it, so it will not be removed or merged blindly."

# line 223
    printf '# The full manifest (tests, docs, repo tooling) lives in the kinglet-unity repo.\n'
```

Note lines 105 and 110 say **Kinglet**, not **Kinglet Pioneer**: they describe an install this installer recognises, and after handover that install may be full Kinglet. The brand is the right granularity there, exactly as it is for the markers.

`uninstall.sh` — three lines:

```bash
# line 3
# Kinglet Pioneer — uninstaller

# line 56
printf '%s\n' "${BOLD}Kinglet Pioneer — uninstaller${NC}"

# line 64
  err "Kinglet did not install this .claude/ — or it was installed by someone else and"
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/run-tests.sh`

Expected: PASS. `test-pioneer-identity.sh` appears in the output with all assertions green, and **all 9 test files appear**. Count them; the runner has previously reported green while silently skipping 7 of 8 files.

- [ ] **Step 6: Record the new test file in the manifest**

`scripts/check-provenance.sh` fails a tracked file with no manifest row as an orphan. Append to `provenance.tsv`:

```bash
printf 'tests/test-pioneer-identity.sh\toriginal\t-\t-\t-\toriginal\tpins-the-pioneer-identity-contract-by-behaviour\n' >> provenance.tsv
```

Run: `bash scripts/check-provenance.sh`
Expected: `provenance OK`

- [ ] **Step 7: Commit**

```bash
git add .claude/VERSION .claude/UPSTREAM install.sh uninstall.sh \
        scripts/generate-claude-md.sh tests/test-pioneer-identity.sh provenance.tsv
git commit -m "feat: establish the Kinglet Pioneer identity before anything is installed

The installer writes a marker into the user's own CLAUDE.md and reads it back
on every upgrade, and stamps a header into the receipt that its ours/foreign
mode detection depends on. Both become expensive the moment a real project
exists, and no project has one yet.

The markers say kinglet, not kinglet-pioneer. The full platform will look for
its own marker in a project Pioneer wrote into, and it now finds one. The
edition is data beside it, not part of the identifier.

The test installs into a mock project, re-installs over it, and asserts the
block was refreshed rather than duplicated. Reading our own source would not
have caught the case that matters."
```

---

### Task 2: Prose, banners, and the guard

Everything else the old name appears in, plus a repository-wide assertion that it is gone from every file it should be gone from.

**Files:**
- Modify: `README.md`, `CREDITS.md`, `CONTRIBUTING.md`, `MCP-SETUP.md`, `MERGE-NOTES.md`, `CLAUDE.md`
- Modify: `.claude/NOTICE.md`, `.claude/rules/pc-console.md`
- Modify: `.claude/templates/architecture-decision-record.md`, `.claude/templates/game-concept.md`, `.claude/templates/game-design-document.md`, `.claude/templates/sprint-plan.md`, `.claude/templates/systems-index.md`
- Modify: `docs/AGENT-GUIDE.md`, `docs/ARCHITECTURE.md`, `docs/SKILL-CATALOG.md`
- Modify: `scripts/studio-doctor.sh:3`, `scripts/studio-doctor.sh:44`, `scripts/studio-doctor.sh:49`, `scripts/studio-doctor.sh:162`
- Modify: `tests/run-tests.sh:150`, `tests/test-no-mobile.sh:3`
- Modify: `provenance.tsv` — only the `note` column, only where it names the toolkit
- Test: `tests/test-pioneer-identity.sh` (extend the file created in Task 1)

**Interfaces:**
- Consumes: the string constants Task 1 produced. The guard asserts the *absence* of `cloud-nine`; Task 1 already removed it from the installer scripts, so those assertions stay green.
- Produces: nothing later tasks consume. This task closes the rename.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-pioneer-identity.sh`, before the `rm -rf "$PID_MOCK"` line:

```bash
# --- Guard: the retired name is gone from every file it should be gone from ---
#
# The exclusion list is not laziness. Each entry contains the old name for a
# reason that outlives the rename:
#   migration/baseline-inventory.json — evidence anchored at a commit; the
#       baseline verifier reads blobs AT that commit, so the working tree
#       cannot invalidate it, but editing the record would.
#   docs/superpowers/{plans,specs}/2026-07-22-* — frozen, superseded history.
#   the pioneer spec and this plan — the rename is their subject matter.
#
# Anything NOT on this list that still says cloud-nine is a missed rename.
PID_OFFENDERS=$(cd "$REPO_DIR" && git grep -lie "cloud.nine" \
    -- . \
    ':(exclude)migration/baseline-inventory.json' \
    ':(exclude)docs/superpowers/plans/2026-07-22-*' \
    ':(exclude)docs/superpowers/specs/2026-07-22-*' \
    ':(exclude)docs/superpowers/specs/2026-07-29-kinglet-pioneer-design.md' \
    ':(exclude)docs/superpowers/plans/2026-07-29-kinglet-pioneer-wave-1a-identity.md' \
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/run-tests.sh 2>&1 | grep -A20 'test-pioneer-identity'`

Expected: FAIL on `no tracked file outside the recorded exclusions says cloud-nine`, listing the ~20 files Task 2 has not yet touched. The two attribution assertions should already PASS — if either fails now, stop: something was damaged in Task 1.

- [ ] **Step 3: Rewrite the prose**

Replace `cloud-nine-unity` with **`Kinglet Pioneer`** in running prose, and with **`kinglet-unity`** where the text names the repository or a path. Do not use `sed -i` across the tree — the exclusion list makes a blanket sweep wrong, and several occurrences need a judgement call between the two replacements.

Per file:

| File | Occurrences | Replacement |
|---|---|---|
| `README.md` | 1 | Title/product prose → `Kinglet Pioneer` |
| `CREDITS.md` | 1 | Product prose → `Kinglet Pioneer`. **Upstream names untouched.** |
| `CONTRIBUTING.md` | 1 | Product prose → `Kinglet Pioneer` |
| `MCP-SETUP.md` | 1 | Product prose → `Kinglet Pioneer` |
| `MERGE-NOTES.md` | 1 | This is the build record. Keep the sentence historically true: if it describes what the merge produced, `Kinglet Pioneer (then named cloud-nine-unity)` is correct and preserves the record. |
| `CLAUDE.md` | 1 | Repo guide heading → `# kinglet-unity — repo guide` |
| `.claude/NOTICE.md` | 1 | Product prose → `Kinglet Pioneer`. **MIT text untouched.** |
| `.claude/rules/pc-console.md` | 1 | `cloud-nine-unity ships no mobile content` → `Kinglet Pioneer ships no mobile content` |
| `.claude/templates/*.md` (5 files) | 1 each | HTML comment attributing the template → `Kinglet Pioneer` |
| `docs/AGENT-GUIDE.md`, `docs/ARCHITECTURE.md`, `docs/SKILL-CATALOG.md` | 1 each | Product prose → `Kinglet Pioneer` |
| `scripts/studio-doctor.sh` | 4 | Lines 3 and 44 → `Kinglet Pioneer — studio-doctor`. Line 49 → `Installed: Kinglet Pioneer %s (vendored ECU %s)`. Line 162 → `Kinglet did not write it here` (brand-level: after handover it may be full Kinglet). |
| `tests/run-tests.sh` | 1 | Line 150 banner → `Kinglet Pioneer test suite` |
| `tests/test-no-mobile.sh` | 1 | Line 3 comment → `Kinglet Pioneer is PC/console only. Prove it.` |
| `provenance.tsv` | grep to find | Only the `note` column, and only where it names the toolkit. **Do not touch `origin`, `upstream_*`, or `status`** — those are the manifest's load-bearing fields. |

`MERGE-NOTES.md` note: it is the record of what was taken and adapted. Rewriting it to claim the merge produced "Kinglet Pioneer" makes the record say something that was not true at the time. The parenthetical keeps it accurate.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/run-tests.sh`
Expected: PASS, 9 files present, including `no tracked file outside the recorded exclusions says cloud-nine`.

Run: `bash scripts/check-provenance.sh`
Expected: `provenance OK`. The `note` column is free text and is not checksummed, so editing it is safe — but run this to confirm no row was structurally damaged while editing.

- [ ] **Step 5: Verify the installer end-to-end against a fixture**

The unit assertions cover strings. This confirms the whole path still works:

```bash
rm -rf /tmp/pioneer-check
bash tests/fixtures/mkproject.sh /tmp/pioneer-check --variant urp
bash install.sh --project-dir /tmp/pioneer-check --dry-run
bash install.sh --project-dir /tmp/pioneer-check
awk 'NR<=6' /tmp/pioneer-check/.claude/state/install-receipt.tsv
bash uninstall.sh --project-dir /tmp/pioneer-check
```

Expected: the dry run reports the `CLAUDE.md (new — generated)` branch; the install succeeds; the receipt's first lines show `# kinglet install receipt` and `# edition: pioneer`; the uninstall removes what it wrote and reports it.

Note `awk 'NR<=6'`, not `head -6` — this repository's shell convention forbids piping into `head` under `set -euo pipefail`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "docs: retire the name cloud-nine-unity

The guard asserts absence, with an explicit exclusion list. Three of the four
exclusions are frozen history and the fourth is the design that describes the
rename; a file outside the list that still carries the old name is a missed
rename, and now fails the suite.

Two assertions guard the sweep itself. A careless rename is capable of eating
the MIT obligations along with our own name, so the ECU and CCGS attributions
and the shipped NOTICE are asserted present. MERGE-NOTES keeps the old name in
a parenthetical: it records what the merge produced at the time, and it did not
produce something called Kinglet."
```

---

## What this plan does not do, and what unblocks it

| Deferred | Blocked on |
|---|---|
| MCP package pin reconciliation (`10.1.0` vs `9.7.1`) | The smoke pass. Pioneer pins what it ran against. |
| `superpowers` as a `provenance.tsv` origin | The first adapted Superpowers file, in Wave 2. |
| Items 8, 9, 1, 2 — surface descriptions, code map, durable artifacts, track connection | The smoke pass. All four edit command and skill files; if the smoke pass finds that some do not register at all, editing them first is work spent on a surface that does not load. |
| The command/skill surface consolidation | The Wave 1 stocktake measurement. |

**The smoke pass is the next thing, and it needs a human.** It requires a scratch Unity 6 project with the CoplayDev MCP bridge running, which this session cannot provide. Wave 1a is the work that is correct regardless of what the smoke pass finds, so it proceeds in parallel.

## Self-review

**Spec coverage.** Item 10 (rename) is fully covered by Tasks 1 and 2. Item 7 is split: both halves are deferred with named triggers and recorded above. Items 0, 8, 9, 1, 2 are Wave 1b by the decomposition stated at the top. No spec requirement is silently dropped.

**Placeholder scan.** No TBD, no "handle edge cases", no "similar to Task N". Every replacement string is written out. The one value deliberately absent — the MCP pin — is named as deferred with its trigger, not left blank in a step.

**Type consistency.** The five constants Task 1 produces (`kinglet:generated:begin`, `kinglet:generated:end`, `# kinglet install receipt`, `# edition: pioneer`, `3.0.0-pioneer.1`) are spelled identically in Task 1's implementation steps, Task 1's test, and Task 2's guard. `install.sh` carries the begin-marker in three places and all three are listed; missing one would make the dry run and the real install disagree about which branch they take.
