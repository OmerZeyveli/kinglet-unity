# The Installer Owns What It Writes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `.claude/skills/subagent-driven-implementation/SKILL.md` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every claim `install.sh` makes about what it owns, leaves behind, or detected is true — and a guard keeps it true.

**Architecture:** Two new self-contained bash tests. One asserts the receipt records *ownership* rather than *this run's writes*, across four fixture states including the one where a user edits a file the installer previously owned. The other asserts the dry-run and the real run agree, using three oracles: new paths, receipt rows, and the content of pre-existing files. Both are written red-first against defects that exist today. The fixes follow, plus one shared pipeline detector replacing two that disagree.

**Tech Stack:** bash 3.2-compatible shell, Markdown, TSV. `tests/run-tests.sh`, `scripts/check-provenance.sh`, `tests/fixtures/mkproject.sh`, `python3 -m tools.kinglet_build`.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-08-12-installer-owns-what-it-writes-design.md` at `2d081f0`. Where this plan and the spec disagree, **the spec wins** and the disagreement is a bug in this plan — report it rather than resolving it silently.
- **Branch:** `pioneer/installer-ownership`, cut from `main` at `c5280c4`.
- **Gates, both, before any task is reported done:**
  - `bash tests/run-tests.sh` — needs a timeout above **150000 ms**. Current: `Total: 503  Passed: 503  Failed: 0`, 31 test files.
  - `bash scripts/check-provenance.sh` — must end `provenance OK`.
- **Strip ANSI before counting suite headers.** The runner colours the `--- test-*.sh ---` header, so `grep -c '^--- test-.*\.sh ---'` on raw output returns **0** on a completely healthy suite — the exact signal of the catastrophe the count exists to detect. Use `sed $'s/\x1b\\[[0-9;]*m//g'` first, then compare against `ls tests/test-*.sh | wc -l`.
- **This repository is not a Unity project.** No Editor, no MCP bridge, no C#. `install.sh` gates on `Assets/` + `ProjectSettings/`, so **the fixture is how the installer is exercised**: `bash tests/fixtures/mkproject.sh <dir> [--variant urp|builtin|bare|dirty|legacy|async-mixed]`. Make fixtures realistic — a one-line `ProjectVersion.txt` once hid a real bug, because Unity writes two lines and both match the version regex.
- **bash 3.2 compatible.** No `declare -A`, no `grep -oP`. A macOS pass is planned.
- **Never pipe into a reader that can exit early** under `set -euo pipefail` — `grep -q` exits on first match without draining stdin, and SIGPIPE + pipefail kills the script on large inputs while passing on small ones. Use a here-string: `grep -qF -- "$needle" <<< "$haystack"`.
- **`[ x = y ] && continue` is a `set -e` trap** as the last command in a loop body: the false test makes the whole AND-list exit 1 and kills the script. Write `if [ x = y ]; then continue; fi`.
- **Both new tests are self-contained** — they set their own `set -euo pipefail` and define their own `pass()` / `fail()`. Model them on `tests/test-provenance-origins.sh`. Do **not** use the runner's `assert_*` helpers in them; those are only defined for runner-provided files, and calling an undefined helper under the runner's `set +e` **prints to stderr and contributes no `FAIL:` token** — the test would report green on the defect it exists to catch.
- **Print `PASS:` / `FAIL:`, not `ok:`.** `run-tests.sh` aggregates by grepping each file's output for those tokens; anything else contributes 0 and is indistinguishable from a file that never ran.
- **Baseline discipline.** `.claude/` content changes trip `tests/kinglet/test_baseline_inventory.py`'s sha256 tripwires. Order is **commit, regenerate, commit** — the reverse is circular, because the test reads `git ls-files` while the regenerator reads `git ls-tree`. Entry point is the **package**: `python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift <n>`; `python3 -m tools.kinglet_build.cli` silently no-ops with exit 0. `--dry-run` first, **use the tool's numbers, not this plan's estimate**, and report a disagreement rather than tuning the flag. A categorised file counts twice.
- **Every new tracked file needs a `provenance.tsv` row** — seven tab-separated columns: path, origin, upstream_version, upstream_path, upstream_sha256, status, note. Files originating here: `original	-	-	-	original	<note>`.
- **Cite by content, not by line number.** This repository's previous wave proved the failure twice over: a 29-line insertion invalidated every citation below it, and then the fix round's own edits moved the numbers it existed to repair. If you write a citation, prefer an anchor a rename breaks loudly (`grep -n 'for group in scripts'`) over a number an insertion breaks silently.
- **A check's silence is only as wide as what it read.** Nine times in the previous two waves a probe's *shape*, not its execution, decided what it found — including three cases where an oracle was disjoint from the class it was meant to certify. **Say what each probe you write cannot see.**
- **A needle that passes for the wrong reason is worse than no needle**, and **a red-first step that starts green is worse than no red-first step**. Every "watch it fail" step means observe the *specific* failure named.
- **A sentinel must not contain its own needle.**

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `tests/test-install-ownership.sh` | **Create.** Asserts the receipt records ownership across four fixture states, and that `uninstall.sh` acts on it correctly in each | 1, 2 |
| `tests/test-install-dryrun.sh` | **Create.** Asserts the dry-run and the real run agree, across three oracles | 3 |
| `install.sh` | Modify. Receipt rows for owned-not-written files; `manifest.json.bak` recorded; the `.gitignore` announcement computed | 1, 2, 4 |
| `scripts/detect-pipeline.sh` | **Create.** The single render-pipeline detector both callers use | 5 |
| `scripts/generate-claude-md.sh` | Modify. Calls the shared detector | 5 |
| `docs/GETTING-STARTED.md` | Modify. Option B states its costs | 5 |
| `provenance.tsv` | Modify. Rows for three new files | 1 |
| `docs/superpowers/plans/2026-08-12-installer-owns-what-it-writes-ledger.md` | Controller-owned. **Do not create or edit** | — |

---

## Task 1: The receipt records ownership, not this run's writes

**Files:**
- Create: `tests/test-install-ownership.sh`
- Modify: `install.sh` — the `MCP-SETUP.md` block and the `.mcp.json` block
- Modify: `provenance.tsv`

**Interfaces:**
- Consumes: nothing.
- Produces: `tests/test-install-ownership.sh`, self-contained, with the helper `own_row()` — takes a receipt path and a project-relative path, prints the matching receipt line or nothing. Task 2 extends this file and reuses it.

- [ ] **Step 1: Write the four-state test, red**

The four states are the spec's Risks section, and **the fourth is the one that is easy to get wrong**, because the file was the installer's a moment ago.

Create `tests/test-install-ownership.sh`. Model its shape on `tests/test-provenance-origins.sh` (self-contained, own `pass`/`fail`, `REPO` from `${BASH_SOURCE[0]}`). It must build a fixture, install, and assert per state:

| State | Receipt row for `MCP-SETUP.md` | `uninstall.sh --yes` |
|---|---|---|
| A: fresh install | present, `toolkit` | removes the file |
| B: **second install**, file untouched | **present** | removes the file |
| C: user's own file present before install 1 | **absent** | leaves the file |
| D: install 1, then user edits the file, then install 2 | **absent** | leaves the file |

Assert the same four for `.mcp.json`.

Use `bash "$REPO/tests/fixtures/mkproject.sh" "$d"` per state, in `$(mktemp -d)`, and clean up. `uninstall.sh` needs `--yes`; check its flag name before writing the call rather than assuming.

- [ ] **Step 2: Run it and watch B and D fail for different reasons**

```bash
bash tests/test-install-ownership.sh; echo "exit=$?"
```

Expected: **A and C pass; B fails** (the row is missing after the second install, so uninstall leaves the file). **D's expectation already holds today** — the row is absent because no row is ever written on a second run — but it holds *by accident*, for the wrong reason, and Step 3's fix must not break it.

**Report exactly which assertions failed.** If B passes, stop — the defect the task exists to close is not present and the controller needs to know before anything is changed.

- [ ] **Step 3: Make the row a statement of ownership**

The current block writes its row inside the create branch:

```bash
MCP_SETUP_MD="$PROJECT_DIR/MCP-SETUP.md"
if [ -f "$SCRIPT_DIR/MCP-SETUP.md" ] && [ ! -f "$MCP_SETUP_MD" ]; then
  cp "$SCRIPT_DIR/MCP-SETUP.md" "$MCP_SETUP_MD"
  ok "Installed MCP-SETUP.md"
  printf '%s\n' "$(printf 'MCP-SETUP.md\t%s\t644\ttoolkit' "$(sha_of "$MCP_SETUP_MD")")" >> "$RECEIPT_TMP"
fi
```

Restructure so the row is written whenever the installer **owns** the file at the end of the run — created this run, or present and still matching what the installer would have put there. **The ownership test must fail closed**: unknown provenance means no row, means `uninstall.sh` leaves it alone.

The installer already has the pieces. `sha_of` gives a checksum; `$SCRIPT_DIR/MCP-SETUP.md` is the toolkit's copy; the previous receipt is readable at `$RECEIPT` before it is replaced. Use them; do not invent a new mechanism.

Apply the same shape to `.mcp.json` through `MCP_JSON_RECEIPT_LINE`. **They are one class and the fix is one shape** — if your two implementations differ, say why in the report.

- [ ] **Step 4: Run it and watch all four states pass, for the right reasons**

```bash
bash tests/test-install-ownership.sh; echo "exit=$?"
```

All four states, both files. **Then prove D specifically was not made to pass by luck**: after the fix, edit the file, run install a third time, and confirm the row is still absent and uninstall still leaves it. Report that separately.

- [ ] **Step 5: Add the provenance row, run both gates, commit**

```
tests/test-install-ownership.sh	original	-	-	-	original	the receipt records what the installer owns rather than what it wrote this run: four fixture states including a user editing a file the installer previously owned
```

Then `bash scripts/check-provenance.sh` (must end `provenance OK`) and `bash tests/run-tests.sh`, with the ANSI-stripped header count equal to `ls tests/test-*.sh | wc -l` — which is now one higher.

Commit. No `.claude/` file was touched, so confirm zero baseline drift with `--expect-drift 0 --dry-run` rather than assuming it.

---

## Task 1b: `uninstall.sh` reads the origin column it is already given

**Inserted 2026-08-12, not appended.** Task 1 measured this and its review reproduced it: a `.claude/`
file the user edited is **deleted by a plain `uninstall.sh --yes`**. It goes here rather than at the
end because it is data loss in shipped software, and because it is the same root cause as Task 1 —
the origin column is written in three places and read in none. Spec decision **D7**.

**Files:**
- Modify: `uninstall.sh` — the classifier loop
- Modify: `tests/test-install-ownership.sh`

**Interfaces:**
- Consumes: `own_row()` from Task 1.
- Produces: nothing.

- [ ] **Step 1: Reproduce the defect before changing anything**

Build a fixture, install, edit a `.claude/` file the payload owns, install again, then
`uninstall.sh --yes --no-backup`. Expected today: the run reports the file under
`remove N file(s) — unchanged since install`, the `keep N file(s) you modified` branch never fires,
and **the edited file is gone**.

Capture that output verbatim. If the file survives, stop and report — the defect is absent and the
controller needs to know before anything changes.

- [ ] **Step 2: Add the three assertions, red**

Extend `tests/test-install-ownership.sh` with state **G**, all three directions:

| | expectation |
|---|---|
| `uninstall.sh --yes` | the edited file **survives** |
| its plan output | counts the file under *modified*, not *unchanged since install* |
| `uninstall.sh --yes --purge` | the edited file **is** removed |

The third is what stops the fix from becoming "never delete anything". Run and confirm the first two
fail and the third passes.

- [ ] **Step 3: Branch on the column**

`uninstall.sh`'s classifier already destructures the origin field and discards it — find it with
`grep -n "IFS=\$'\\\\t' read -r rel recorded" uninstall.sh`. A row whose origin is `user-modified` is
the user's file, whatever its checksum says.

Keep the checksum test for `toolkit` rows: there it correctly separates *we installed it and nobody
touched it* from *we installed it and someone did*.

**Do not change what `install.sh` records.** It writes the edited sha so the next install recognises
the file as still-edited; changing that reintroduces the defect `c2d27f1f` fixed on 2026-08-03, where
an edit survived exactly one upgrade and the second silently overwrote it. Two consumers need
different things from one row, and the origin column is how the row already tells them apart.

- [ ] **Step 4: Green, and prove the fix did not become "keep everything"**

All three of state G's assertions. Then confirm the pre-existing states still hold — in particular
that a `toolkit` row whose file is untouched is **still removed**, or the fix has traded a
data-loss bug for an uninstaller that does not uninstall.

Mutation-prove it: make the classifier treat *every* row as `user-modified` and confirm the suite
goes red on the untouched-file case.

- [ ] **Step 5: Gates, commit**

Both gates. `uninstall.sh` is not under `.claude/`, so confirm zero baseline drift rather than
assuming it.

---

## Task 1c: The scripts loop respects a user edit

**Inserted 2026-08-12** after Task 1b's review measured it. Spec **D8**, acceptance criterion 11.
Data loss, and the run says the opposite of what it does in the same output.

**Files:** modify `install.sh` (the `for group in scripts` loop) and `tests/test-install-ownership.sh`.

**Interfaces:** consumes `own_row()`; produces nothing.

- [ ] **Step 1: Reproduce the contradiction**

Install into a fixture, edit `.claude/scripts/studio-doctor.sh`, install again. Expected today: the
run prints `keeping yours:` **naming that file**, then reports files installed, and **the edit is
gone**. Capture both the warning and the byte comparison.

If the edit survives, stop and report.

- [ ] **Step 2: Add state H, red**

| | expectation |
|---|---|
| after reinstall | the edited `.claude/scripts/*.sh` **keeps the user's bytes** |
| its receipt row | origin is `user-modified`, sha is the **edited** one |
| the run's `keeping yours` list | matches what was actually kept |
| an **untouched** shipped script | is still overwritten and still recorded `toolkit` |

The last row is the anti-"keep everything" guard, as in Task 1b.

- [ ] **Step 3: Give the loop the payload loop's shape**

Find both with `grep -n 'for group in scripts\|is_modified' install.sh`. The payload loop checks
`is_modified ".claude/$rel"`, keeps the file, increments `KEPT`, and writes a `user-modified` row
carrying the file's **current** bytes. Apply that shape here. The path form for these rows is
`.claude/scripts/<name>`, matching what `MODIFIED_FILES` is computed against — **verify that rather
than assuming it**, or the check silently never matches.

Mind `WRITTEN` and `KEPT`: the summary line reports both, and a kept script must not be counted as
written.

- [ ] **Step 4: Green, and prove the warning and the writes now agree**

All four of state H. Then re-run Step 1's recipe and confirm the `keeping yours` list and the files
actually kept are the same set.

- [ ] **Step 5: Gates, commit.** `install.sh` is not under `.claude/`; confirm zero baseline drift.

---

## Task 1d: `studio-doctor.sh` reads the origin column, and stops piping into `head`

**Inserted 2026-08-12.** Spec **D9**, acceptance criterion 12. Two defects, one of each kind.

**Files:** modify `scripts/studio-doctor.sh`, and `tests/test-studio-doctor.sh`.

**Note:** `tests/test-studio-doctor.sh` is **runner-provided** — it uses the runner's helpers and
`$REPO_DIR` and defines neither. Run standalone it **exits 0 having asserted nothing**. Verify
through the runner, reading its section:
`bash tests/run-tests.sh 2>&1 | sed -n '/--- test-studio-doctor/,/^--- test-/p'`.

- [ ] **Step 1: Reproduce both, red**

**The origin blindness:** install into a fixture, edit a `.claude/` payload file, install again, then
run `studio-doctor.sh`. Expected today: `PASS Install intact: N file(s) verified against the
receipt`, with the edited file never named. It matches its recorded (edited) sha, so it reads as
verified.

**The SIGPIPE trap:** `grep -n 'head -5' scripts/studio-doctor.sh` finds two
`printf '%s' "$LIST" | head -5` calls under `set -euo pipefail`. Build a project with **more than
five** modified files and run the script. It **fires on a long list and hides on a short one** —
which is why every test written against a healthy project passes.

Report what each actually did. If the pipe does not fail on your fixture, say so and say how many
files you used — the failure depends on `PIPE_BUF` and timing, and "did not reproduce" is a finding,
not a reason to skip the fix.

- [ ] **Step 2: Read the column, and drop the pipes**

The classifier destructures `_origin` and discards it. Give it the shape Task 1b gave
`uninstall.sh`'s — and match that one deliberately, so one grammar covers both readers.

For the pipes: `head` is the documented case, and the fix is a form with no pipe. `awk 'NR<=5'` on a
here-string, or a counter in the existing `while` loop, both work. **Whichever you pick, the writer
must not be a `printf` on the left of a pipe.**

- [ ] **Step 3: Green, both**

The edited file is named under "modified since install", and the long-list run completes.

- [ ] **Step 4: Gates, commit.** `scripts/` **ships** into `.claude/scripts/`, so this is a payload
change: expect baseline drift, `--dry-run` first, use the tool's number, commit / regenerate / commit.

---

## Task 2: A backup the installer keeps is a file the installer owns

**Files:**
- Modify: `tests/test-install-ownership.sh`
- Modify: `install.sh` — the manifest-backup block

**Interfaces:**
- Consumes: `own_row()` from Task 1.
- Produces: nothing.

- [ ] **Step 1: Extend the test, red**

`install.sh` copies the manifest to `manifest.json.bak` before editing it under `--with-mcp` (find it with `grep -n 'MANIFEST.bak' install.sh`), and removes that copy **only when git already tracks the manifest**. When git does not, the `.bak` is kept, announced — and never recorded.

Add two states:

| State | `Packages/manifest.json.bak` | Receipt row | `uninstall.sh --yes` |
|---|---|---|---|
| E: `--with-mcp`, project **not** under git | kept | **present** | removes it |
| F: `--with-mcp`, manifest **tracked** by git | removed by the installer | absent | nothing to remove |

State F needs a real `git init` plus `git add Packages/manifest.json` in the fixture. State E must **not** be a git repository at all, or must have the manifest untracked — check which branch `install.sh` actually takes rather than assuming.

- [ ] **Step 2: Run and watch E fail**

```bash
bash tests/test-install-ownership.sh; echo "exit=$?"
```

Expected: E fails on the missing receipt row and on the file surviving uninstall. F passes already.

- [ ] **Step 3: Record the backup when it is kept**

Write the receipt row in the branch that keeps the file, not in the one that removes it. The path in the row is project-relative, matching every other row's form (`Packages/manifest.json.bak`).

**Check `uninstall.sh` removes non-`.claude/` paths** before assuming the row is sufficient — it already handles `CLAUDE.md`, `.mcp.json` and `MCP-SETUP.md`, so it should, but confirm rather than assume. If it does not, that is a finding for the controller, not something to fix inside this task.

- [ ] **Step 4: Run, green, commit**

Both gates. Commit. Baseline `--expect-drift 0 --dry-run` to confirm `install.sh` stays outside it.

---

## Task 2b: The other file the installer keeps and does not record

**Inserted 2026-08-13** after Task 2's review measured it. Spec **D10**, acceptance criterion 13.
Same defect as Task 2, second instance — and the spec's scope-discipline note makes this the wave's
**last** insertion.

**Files:** modify `install.sh` (the `CLAUDE.md.generated` block) and `tests/test-install-ownership.sh`.

**Interfaces:** consumes `own_row()` and `owned_by_installer()`; produces nothing.

- [ ] **Step 1: Reproduce both, red**

**The unrecorded file.** Build a fixture, write a `CLAUDE.md` that is the *user's own* — real content,
no generated markers — then install. Expected today: the run prints

```
warn  CLAUDE.md exists and has no generated markers — wrote CLAUDE.md.generated instead.
```

the receipt's only non-`.claude/` rows are `.mcp.json` and `MCP-SETUP.md`, and after
`uninstall.sh --yes` the project root **still holds `CLAUDE.md.generated`**. Find the write with
`grep -n 'CLAUDE.md.generated' install.sh`.

**The duplicate row.** `install.sh` calls `add_manifest_dependency` twice, once per `--with-*` flag —
find both with `grep -n 'add_manifest_dependency "' install.sh`. Against a fixture **missing both
packages** (`--variant builtin`), run `install.sh --with-mcp --with-input-system` once. Task 2's row is
written after both callers, so today this produces **one** row; that is the property to lock down, and
the way to see it is to relocate the write into the keep branch on a scratch copy and watch two rows
appear with different checksums. Do that on `git archive HEAD | tar -x -C "$(mktemp -d)"`, not in the
tree.

**Report exactly what each produced.** If either is already correct, stop — the defect the step exists
to close is not present and the controller needs to know before anything changes.

- [ ] **Step 2: Add the states, red**

Extend `tests/test-install-ownership.sh`. Follow the file's existing convention: self-contained, its
own `pass`/`fail`, `own_row()` for row lookups, and **no runner `assert_*` helpers**.

| State | Setup | Receipt row for `CLAUDE.md.generated` | `uninstall.sh --yes` |
|---|---|---|---|
| I | user's own marker-less `CLAUDE.md`, install once | **present** | removes it |
| I2 | the same, installed **twice** | **present** | removes it |
| I3 | user writes their **own** `CLAUDE.md.generated` before install 1 | **absent** | leaves it |
| J | `--variant builtin`, one run with **both** `--with-*` flags | — | exactly **one** `Packages/manifest.json.bak` row |

**I3 is the state that is easy to get wrong**, for the reason D1's Risks section gives: after the fix
the file looks like ours. It is the only assertion that catches an ownership test that claims by
existence rather than by provenance, so prove it can go red rather than assuming it — Task 2's review
did exactly this for E3 and it is the pattern to copy.

**J counts rows, so anchor it.** A needle like `"1 row"` matches `11 rows`; count with `awk` and
compare with an equality test, and do not put a bare `FAIL` token in any needle — `run-tests.sh`
tallies on that token and the test's own failure message would be counted as a second failure.

- [ ] **Step 3: Record the file when the installer owns it**

Write the row when the installer **owns** `CLAUDE.md.generated` at the end of the run — created this
run, or present and still matching what the installer would have written. `owned_by_installer` already
exists and already fails closed; use it rather than inventing a second mechanism, and rather than
testing for existence. Task 2's review measured what an existence test costs: it deletes a file the
user wrote.

**Note what makes this file harder than `MCP-SETUP.md`.** Its content is *generated per project*, not
copied from a fixed toolkit source, so "what the installer would have written" is not a file sitting
in `$SCRIPT_DIR`. Establish how `owned_by_installer`'s two arms behave for a path with no reference
copy **before** you rely on either — Task 1d found that `.mcp.json`'s reference is a heredoc
regenerated every run, which makes its first arm always match, and a wrong assumption here is the same
mistake one file over.

For **J**: keep Task 2's write where it is. The task is to assert the property, not to move the code.

- [ ] **Step 4: Green, and prove I3 did not pass by luck**

All four states. Then mutate: make the ownership test claim by existence
(`[ -f "$PROJECT_DIR/CLAUDE.md.generated" ]`) and confirm **I3 specifically** goes red. Report which
other states also reddened — a mutation that reddens everything has not isolated anything.

For **J**, mutate in the other direction: relocate Task 2's row write into the keep branch and confirm
J goes red. That is the refactor J exists to stop.

- [ ] **Step 5: Gates, commit.** `install.sh` is not under `.claude/`; confirm zero baseline drift
rather than assuming it. No new file, so no `provenance.tsv` row — confirm via the gate.

---

## Task 2c: The two writers that overwrite without asking

**Inserted 2026-08-13** after Task 2b's review reproduced it on three independent paths. Spec **D11**,
acceptance criterion 14, and the amendment to criterion 13. This is **data loss in shipped software** —
the one exemption D10 left open — and the wave itself created the half that makes it worse.

**Files:** modify `install.sh` (the `CLAUDE.md.generated` branch and `add_manifest_dependency`) and
`tests/test-install-ownership.sh`.

**Interfaces:** consumes `own_row()` and `owned_by_installer()`; produces nothing.

- [ ] **Step 1: Reproduce all three, red**

Find the two writers with `grep -n 'mv "\$TMP_MD"' install.sh` and
`grep -n 'cp "\$MANIFEST" "\$MANIFEST.bak"' install.sh`. Then, capturing full output each time:

1. **The prescribed workflow.** Default fixture, a marker-less `CLAUDE.md` that is the user's own,
   install, **fill in the `FILL:` markers** in `CLAUDE.md.generated` the way the run's own summary step
   2 says, install again. Expected today: the markers are back, and the run prints `keeping yours:`
   naming that file **and** `Yours was not touched.` in the same output.
2. **First install ever.** Same fixture, but the user wrote their own `CLAUDE.md.generated` before any
   install. Expected today: destroyed, and the receipt then records it as `toolkit`.
3. **The backup.** `--variant builtin`, `install --with-mcp`, edit the kept `.bak`, then
   `install --with-input-system` (the second package is still missing, so the `cp` runs again).
   Expected today: `keeping yours:` names the file and the edit is gone.

**If any of the three does not reproduce, stop and report** — the defect the task exists to close may
not be present in the shape the spec describes.

- [ ] **Step 2: Add the states, red**

Extend `tests/test-install-ownership.sh` — self-contained, its own `pass`/`fail`, `own_row()` for row
lookups, **no runner `assert_*` helpers**. One state per reproduction above, and each asserts **three**
things, because two of them are what makes this D11 rather than a plain overwrite:

| | expectation |
|---|---|
| the user's bytes | **survive** |
| the run's output | does **not** claim `keeping yours` about that file, and does not claim `Yours was not touched` about a file it touched |
| the toolkit's own file | is **still written** when the installer does own it |

The third row is the anti-"never write anything" guard, as in Tasks 1b and 1c. Without it the fix can
pass by refusing to install.

**Also add criterion 13's third clause as it is actually written** — a marker-less `CLAUDE.md` **and** a
user-authored `CLAUDE.md.generated`, across two installs, the file getting no row and surviving. Task
2b could only assert a narrowed reading of that clause because the file was destroyed before ownership
was asked; once this task lands, the clause is achievable as written. Say in the report whether it now
is.

- [ ] **Step 3: Ask before writing**

Both writers consult `owned_by_installer` first. **Do not invent a second ownership mechanism** — the
helper exists, it fails closed on 16 malformed inputs, and Task 2b established how to call it for a
file with no fixed reference copy.

For **`CLAUDE.md.generated`**: when the installer does not own it, keep the user's file, warn naming
it, and **do not set the branch variable that makes the row predicate claim ownership** — find it with
`grep -n 'CLAUDE_MD_BRANCH' install.sh`. Getting this wrong writes a receipt row for a file you just
declined to write, which is the same defect pointing the other way. Tell the user what to do: the
generated content was not produced this run, and renaming or deleting their file gets it.

For **`Packages/manifest.json.bak`**: when the installer does not own it, **decline the manifest edit
itself for that flag** and say why. A backup exists to make a risky edit recoverable; performing the
edit while silently skipping the backup keeps the risk and drops the mitigation. Name the file that is
in the way and say that moving it lets the flag proceed. **Return non-zero from that path or otherwise
make sure the caller does not report success** — check what `add_manifest_dependency`'s callers do with
its exit status before deciding, rather than assuming.

- [ ] **Step 4: Green, and prove the fix did not become "never write anything"**

All three states plus criterion 13's clause. Then, separately: a **clean** fixture still gets its
`CLAUDE.md.generated` written and recorded, and a clean `--with-mcp` still edits the manifest and keeps
its backup. Report both.

Mutation-prove the declines: make each ownership test always return true and confirm the matching
state's user-bytes assertion goes red. **Report which other states reddened** — a mutation that reddens
everything has isolated nothing.

- [ ] **Step 5: Gates, commit.** `install.sh` is not under `.claude/`; confirm zero baseline drift.

---

## Task 3: The dry-run guard, with three oracles

**Files:**
- Create: `tests/test-install-dryrun.sh`
- Modify: `provenance.tsv`

**Interfaces:**
- Consumes: nothing.
- Produces: `tests/test-install-dryrun.sh`, self-contained.

- [ ] **Step 1: Write the guard, red**

The property: **the dry-run announces every path the real run writes, and announces no path it does not.**

Three oracles, and the third is why this task exists as its own:

1. **New paths** — `find "$d" -type f | sort` before and after a real install, diffed. Sees files created.
2. **Receipt rows** — everything the installer claims to own. Sees ownership the filesystem cannot distinguish.
3. **Content of pre-existing files** — `sha256sum` every file present before the run, compared after. **Sees an edit to a file that already existed**, which neither of the others can. `.gitignore` is exactly that case, and it is the reason the previous wave's two-oracle check reported clean while a defect stood.

Run against at least: the default fixture, and one that already ignores `/.claude/` wholesale (write `/.claude/` into its `.gitignore` before installing).

The assertion is a set comparison between what the dry-run's `Would install:` block names and what the three oracles observe. **State in a comment what this guard cannot see** — for instance, a write to a path outside the fixture directory, and any behaviour that depends on flags the test does not exercise.

- [ ] **Step 2: Run it and watch it fail on the `.gitignore` line**

```bash
bash tests/test-install-dryrun.sh; echo "exit=$?"
```

Expected: it flags that the dry-run promises a `.gitignore` edit against the wholesale-ignore fixture where the real run makes none, and/or that the announced entry list does not match what is appended.

**If it passes, the guard is not reading what it claims to.** Do not proceed — report it.

- [ ] **Step 3: Prove both directions by mutation, on a scratch copy**

```bash
scratch=$(mktemp -d); git archive HEAD | tar -x -C "$scratch"
```

Two mutations, each reverted before the next:

- **a write with no announcement** — add a line to `install.sh`'s real-run path that writes a new file at the project root; the guard must go red.
- **an announcement with no write** — add a `printf` to the dry-run block naming a file nothing creates; the guard must go red.

Then a third, aimed at oracle 3 specifically: **append to a pre-existing file in the real run without announcing it.** Oracles 1 and 2 cannot see it; if the guard stays green, oracle 3 is not wired correctly.

Report all three results.

- [ ] **Step 4: Provenance row, gates, commit**

```
tests/test-install-dryrun.sh	original	-	-	-	original	the dry-run announces every path the real run writes and no path it does not; three oracles — new paths, receipt rows, and the content of pre-existing files
```

---

## Task 4: The `.gitignore` announcement says what will happen

**Files:**
- Modify: `install.sh` — the dry-run's `.gitignore` line

**Interfaces:**
- Consumes: Task 3's guard.
- Produces: nothing.

- [ ] **Step 1: Read what the real run actually does**

Find both halves: `grep -n 'add_ignore\|already_ignored\|WANT_IGNORED' install.sh`. The real run consults `already_ignored` per entry and appends only what is not covered. The dry-run's line names two entries and prints unconditionally.

Count the `add_ignore` calls and compare against `WANT_IGNORED`'s entries — a comment in that region claims a number; **derive it rather than trusting the comment**, which has been wrong before in this exact file.

- [ ] **Step 2: Compute the announcement from the same source as the action**

The dry-run must run the same `already_ignored` test and name the entries that will actually be appended. When none will be, say so — `.gitignore — already covered, no change` — rather than promising an edit.

**The trap, and it is the mirror of the one Task 3's guard exists to catch:** an announcement computed from a *copy* of the real run's logic is a second definition that will drift. Share the computation.

- [ ] **Step 3: Task 3's guard goes green**

```bash
bash tests/test-install-dryrun.sh; echo "exit=$?"
```

Against both fixtures — the default and the wholesale-ignore one. Report both.

- [ ] **Step 4: Gates, commit**

---

## Task 5: One pipeline detector, and Option B states its costs

**Files:**
- Create: `scripts/detect-pipeline.sh`
- Modify: `install.sh`, `scripts/generate-claude-md.sh`
- Modify: `docs/GETTING-STARTED.md`
- Modify: `provenance.tsv`

**Interfaces:**
- Consumes: nothing.
- Produces: `scripts/detect-pipeline.sh` — takes a project directory, prints one of `builtin`, `urp`, `hdrp`, `urp+hdrp` on stdout, exits non-zero only on a usage error. Callers map that token to their own display string.

- [ ] **Step 1: Read both implementations and confirm they disagree**

```bash
grep -n 'RENDER_PIPELINE' install.sh scripts/generate-claude-md.sh
```

`install.sh` runs two unconditional greps, so HDRP wins. `generate-claude-md.sh` uses `if/elif`, so URP wins. Build a fixture carrying **both** packages and run both — capture the two answers verbatim before changing anything. That disagreement is the red-first evidence.

- [ ] **Step 2: Write the shared detector**

`scripts/detect-pipeline.sh`, self-contained, bash 3.2. Four states, and **the fourth is the one neither implementation had**:

- no `Packages/manifest.json`, or neither package → `builtin`
- URP only → `urp`
- HDRP only → `hdrp`
- **both → `urp+hdrp`**

It ships (`scripts/*.sh` is copied into `.claude/scripts/`), so it must be useful in an installed project and must not reference anything that does not ship.

**Its comment must state what it does not do**: it reports which pipeline *packages are present*, which is evidence and not the answer. Unity records the active pipeline in `ProjectSettings/GraphicsSettings.asset` by GUID reference, and resolving that means finding the referenced `.asset` and reading the script GUID inside it — deliberately out of scope, per the spec's D3.

- [ ] **Step 3: Both callers use it**

`install.sh` prints its own short form; `generate-claude-md.sh` prints its long form and routes the `urp-pipeline` skill. **Both must handle `urp+hdrp`** — decide what each says and make sure the skill routing is defensible for that state. Say what you chose and why in the report; this is a judgement the plan is not making for you.

`install.sh` runs before the payload is installed, so it calls `$SCRIPT_DIR/scripts/detect-pipeline.sh`. `generate-claude-md.sh` lives in the same directory; use a path relative to its own location, not the caller's cwd.

- [ ] **Step 4: Prove they now agree**

Run both against every `mkproject.sh` variant plus the both-packages fixture, and compare their verdicts pairwise. **Report the table.** Acceptance criterion 6 is that they agree for every fixture, proven by running them, not by reading the code.

- [ ] **Step 5: Option B states its costs**

In `docs/GETTING-STARTED.md`, find the manual-copy option (`grep -n 'Manual Copy' docs/GETTING-STARTED.md`). Annotate it — do not delete it — with the two costs, both verified rather than copied from here:

- it writes no receipt, so `uninstall.sh` refuses to run (check `uninstall.sh`'s no-receipt branch and quote what it actually does);
- it skips `CLAUDE.md` generation, so `/unity-init` must be run afterwards.

- [ ] **Step 6: Provenance row, gates, commit**

```
scripts/detect-pipeline.sh	original	-	-	-	original	the single render-pipeline detector; install.sh and generate-claude-md.sh had two that disagreed when both packages were present, and neither had a both-installed state
```

`scripts/` ships into `.claude/scripts/`, so this **is** a payload change — expect baseline drift, run `--dry-run` first, use the tool's number, and follow commit / regenerate / commit.

---

## Task 6: Whole-wave verification

**Files:** none modified unless a check fails.

- [ ] **Step 1: Run the spec's nine acceptance criteria**

Each one, with the command and its actual output. Criterion 6 requires running both detectors against every fixture — do it, do not cite Task 5.

- [ ] **Step 2: Sweep for the class, scoped to what ships**

Two questions the guards do not answer:

```bash
# Does any other project-root write skip the receipt?
grep -n 'PROJECT_DIR/' install.sh | grep -vE 'RECEIPT|receipt'

# Does any shipped script still carry its own pipeline detection?
grep -rn 'render-pipelines' .claude/ scripts/ install.sh
```

Record what each returns. **Say what each sweep cannot see** — the first is line-oriented over a file whose writes are not all one-line, and the second matches a package name rather than the concept.

- [ ] **Step 3: Branch coherence**

`git status --short`, `git log --oneline c5280c4..HEAD`, `git diff --stat c5280c4..HEAD`.

- [ ] **Step 4: What this does not verify**

The section that matters most. Name every guard added here and what it cannot see — including the two sweeps above, the fixture states not exercised, and the fact that **nothing here proves the toolkit behaves correctly inside Claude Code**, only that the installer's claims match its behaviour on a synthetic project.

`scripts/detect-pipeline.sh` reports package presence and not the active pipeline. Say so plainly, with what closing the gap would take.

---

## Self-Review

**Spec coverage.** D1 → Task 1. D2 → Task 2. D3 → Task 5 Steps 1–4. D4 → Task 3. D5 → Task 4. D6 → Task 5 Step 5. Acceptance criteria 1–9 → Task 6 Step 1, with 6 re-run rather than cited.

**Placeholder scan.** No "TBD", no "handle edge cases". Three places delegate judgement deliberately and say so: Task 1 Step 3's ownership mechanism (the pieces exist; inventing a new one is the failure), Task 5 Step 3's `urp+hdrp` display and skill routing, and Task 4 Step 2's shared computation. Each names what the implementer must report.

**Type consistency.** `own_row()` is defined in Task 1 and consumed in Task 2 under that name. `scripts/detect-pipeline.sh`'s four output tokens — `builtin`, `urp`, `hdrp`, `urp+hdrp` — are fixed in Task 5 Step 2 and consumed in Step 3. Both new test files are self-contained and neither uses the runner's helpers.

**One gap found and closed while reviewing:** Task 1's state D already passes today, for the wrong reason — no row is ever written on a second run, so "no row" is right by accident. A red-first step that starts green reads as work already done, so Step 2 now names D as expected-green-for-the-wrong-reason and Step 4 requires proving it did not become right by luck.
