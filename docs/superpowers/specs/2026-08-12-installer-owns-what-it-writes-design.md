# The Installer Owns What It Writes — Design

*2026-08-12. Branch: to be cut from `main` at `c5280c4`. Scoped by the owner as "handle everything
that does not require me"; every decision below is the author's, and each one that could reasonably
have gone the other way says so.*

## The problem, measured

Five defects, all found during the shipped-citations wave, all recorded and none closed. They share
one shape: **the installer makes a claim it does not keep** — about what it owns, what it leaves
behind, or what it detected.

### 1. The receipt disowns files on upgrade

`uninstall.sh` removes only receipt-listed paths — deliberately, because a previous version deleted
by filename and would happily remove a file it had never installed.

`$RECEIPT_TMP` is rebuilt from scratch on every run. `install.sh`'s Step 8c writes its row **inside**
the create branch:

```bash
MCP_SETUP_MD="$PROJECT_DIR/MCP-SETUP.md"
if [ -f "$SCRIPT_DIR/MCP-SETUP.md" ] && [ ! -f "$MCP_SETUP_MD" ]; then
  cp "$SCRIPT_DIR/MCP-SETUP.md" "$MCP_SETUP_MD"
  ok "Installed MCP-SETUP.md"
  printf '%s\n' "$(printf 'MCP-SETUP.md\t%s\t644\ttoolkit' "$(sha_of "$MCP_SETUP_MD")")" >> "$RECEIPT_TMP"
fi
```

So run 1 installs the file and records it. **Run 2 skips the branch, writes no row, and the rebuilt
receipt no longer mentions the file.** `uninstall.sh` then leaves it behind. `.mcp.json` behaves
identically through `MCP_JSON_RECEIPT_LINE`.

Measured on a fixture: rows go 1 → 0 across two installs, and both files survive
`uninstall.sh --yes`.

**The install is not idempotent in the dimension that matters.** Two runs produce the same files and
a different ownership record, and the second record is the wrong one.

### 2. `Packages/manifest.json.bak` is permanent debris

With `--with-mcp` or `--with-input-system`, `install.sh` copies the manifest to `manifest.json.bak`
before editing. It removes that copy **only when git already tracks the manifest** — the reasoning
being that git is then the backup. When git does not track it, the `.bak` is kept and announced.

It never enters the receipt, so `uninstall.sh` can never remove it. It is permanent, in exactly the
projects least able to `git checkout` it away: a project not under git, or one whose manifest is not
yet added.

### 3. Two pipeline detectors disagree, and both answer the wrong question

```bash
# install.sh — two unconditional greps; HDRP is last, so HDRP wins
RENDER_PIPELINE="Built-in"
grep -q 'com.unity.render-pipelines.universal'       "$MANIFEST" && RENDER_PIPELINE="URP"
grep -q 'com.unity.render-pipelines.high-definition' "$MANIFEST" && RENDER_PIPELINE="HDRP"

# scripts/generate-claude-md.sh — if/elif; URP is first, so URP wins
if   grep -q 'com.unity.render-pipelines.universal'       "$MANIFEST"; then RENDER_PIPELINE="… (URP)"
elif grep -q 'com.unity.render-pipelines.high-definition' "$MANIFEST"; then RENDER_PIPELINE="… (HDRP)"
fi
```

A project carrying both packages gets **HDRP on the console line and URP in its generated
`CLAUDE.md`**, from one install. And `generate-claude-md.sh` routes the `urp-pipeline` skill on
`*URP*`, so the skill loadout follows one answer while the installer's own output states the other.

**Both answer "which package is present", and the question is "which pipeline is active."** Nothing
in this repository reads `ProjectSettings/GraphicsSettings.asset`, which is where Unity records it. A
project can carry URP for one sample and render with Built-in; package presence cannot distinguish
that.

### 4. Nothing guards `install.sh --dry-run`

`grep -rn 'dry.run' tests/` returns no reference to `install.sh`. The shipped-citations wave's only
installer change was text inside that block, and it went in with no coverage. The dry-run is what a
user reads before consenting; it is the one output whose honesty is load-bearing and the one with no
test.

### 5. The dry-run announces two of the four `.gitignore` entries, unconditionally

```bash
printf '  .gitignore — add .claude/settings.local.json and .claude/state/*\n'
```

`add_ignore` is called four times; `.claude.backup.*/` and one other are unannounced. And the line
prints whether or not the real run adds anything — a project that already ignores `/.claude/`
wholesale is fully covered, `already_ignored` correctly skips every entry, and the dry-run still
promises the edit.

This is the third instance of the dry-run under-announcing, and the reason the shipped-citations
wave's own check missed it is worth keeping: that check used a `find` snapshot as its oracle, and
`.gitignore` already exists, so a path snapshot has nothing to diff. **A third oracle — file
*content* before and after — is what sees this class.**

### 6. "Option B: Manual Copy" produces an install that cannot be uninstalled

`docs/GETTING-STARTED.md` offers a `cp -r` alternative to running `install.sh`. That install:

- writes no receipt, so `uninstall.sh` hard-fails and refuses to touch it;
- skips `CLAUDE.md` generation, which `/unity-init` and `architecture.md`'s *"detected, not assumed"*
  block both depend on.

It is four lines in the document a new user reads first.

## Decisions

### D1 — The receipt records what the installer owns, not what it wrote this run

Ownership is a property of the file, not of the run that happened to create it. A row is written when
the installer **owns** the file at the end of the run — which includes the case where it owns it
because a previous run installed it.

The test for "we own it" is the one the installer already uses elsewhere: the file matches the
toolkit's copy, or the previous receipt recorded it as `toolkit`. If the user has edited it, it is
theirs and gets no row — which is the existing `user-modified` path and stays.

**Rejected: always writing the row.** That would adopt a user's hand-written `MCP-SETUP.md` on the
first upgrade and let `uninstall.sh` delete it. The whole reason `uninstall.sh` is receipt-driven is
that a previous version deleted by filename.

Applies to `MCP-SETUP.md` and `.mcp.json` identically — they are one class and the fix is one shape.

### D2 — A backup the installer keeps is a file the installer owns

`manifest.json.bak`, when kept, gets a receipt row. `uninstall.sh` then removes it like anything else
the installer put there.

**Rejected: never creating it.** The backup exists for a real failure mode — a manifest edit that goes
wrong — and removing the safety net to fix a cleanup bug trades a small permanent cost for a rare
catastrophic one.

**Rejected: always deleting it at the end of a successful run.** Same objection one step later: the
user has no copy of their pre-edit manifest once the run exits, and "the edit succeeded" is the
installer's own judgement of its own work.

### D3 — One pipeline detector, and it says what it actually knows

The two implementations become one, in a place both can reach. `install.sh` runs before the payload
is installed, so the shared implementation lives in `scripts/` where both the installer and the
generator can source it.

**And it stops overstating.** Package presence is evidence, not an answer. The detector reports:

- **Built-in** when no pipeline package is present — reliable, because Unity cannot render with a
  pipeline whose package is absent;
- **URP** or **HDRP** when exactly one is present — the overwhelmingly common case, and the
  inference is sound;
- **both present** as its own state, named as such, rather than silently picking a winner.

The third state is the one that produced this defect. Neither existing implementation has it; each
invented a precedence rule by accident of control flow, and the two accidents disagreed.

**`ProjectSettings/GraphicsSettings.asset` is the authoritative source and this design does not read
it.** That is a deliberate limit, stated rather than hidden: the file references the active pipeline
asset by GUID, and resolving that GUID to "URP" or "HDRP" means finding the `.asset` it points at and
reading the script reference inside it — two more file formats and a `.meta` lookup, in bash, on a
path where a wrong answer is worse than an honest "both are installed". **Recorded as the deeper
improvement, with what it would take.**

### D4 — The dry-run gets the guard the wave's own fix should have had

A new self-contained test exercises `install.sh --dry-run` against fixtures and asserts the property
the shipped-citations wave established by hand: **the dry-run announces every path the real run
writes, and announces no path it does not.**

Its oracle is the **filesystem** — a `find` snapshot before and after a real run, with the flags
exercised — and the receipt is a **second, different check** asking what the first cannot: does
everything the installer should own actually get a row.

That two-oracle shape is not a preference. It is the correction of a measured failure: during the
shipped-citations wave an implementer used the receipt alone, reported "no third unannounced write",
and was structurally unable to see `manifest.json.bak` — which never enters the receipt. **A guard
built the same way would certify the class it cannot inspect.**

### D5 — The `.gitignore` line names what it will add, and only when it will add it

The announcement is computed from the same `already_ignored` results the real run uses, and lists the
entries that will actually be appended. When none will be, it says so or says nothing — it does not
promise an edit that will not happen.

**The dry-run guard in D4 therefore needs a third oracle**: a `find` snapshot sees new paths, the
receipt sees claimed ownership, and neither sees a line appended to a file that already existed. Hash
the content of every pre-existing file the installer may touch, before and after.

### D6 — "Option B: Manual Copy" is marked unsupported, not deleted

It is annotated with what it costs — no receipt, so `uninstall.sh` will refuse; no generated
`CLAUDE.md`, so `/unity-init` must be run — and kept.

**Rejected: deleting it.** Someone installing into an air-gapped or vendored checkout may have a
reason to copy by hand, and removing the option silently is worse than documenting its cost. The
defect is that it reads as an equal alternative, not that it exists.

### D7 — `uninstall.sh` reads the origin column it is already given

**Added 2026-08-12, after Task 1 measured it and its review reproduced it.** This is data loss in
shipped software and it belongs in this wave, because it is the same root cause as everything above:
**the origin column is written in three places and read in none.**

`install.sh` records a kept user-modified file with its **current** — that is, edited — checksum, so
that the next run recognises it. `uninstall.sh`'s classifier then compares the file against that
recorded checksum:

```bash
while IFS=$'\t' read -r rel recorded _mode _origin; do
  …
  if [ "$(sha_of "$abs")" = "$recorded" ]; then TO_REMOVE=…  else MODIFIED=…  fi
```

The sha matches, because install recorded the edited state. **The file lands in `TO_REMOVE` and is
deleted without `--purge`.** `_origin` is destructured and discarded — the underscore is deliberate.

Reproduced twice, independently: install → edit `.claude/rules/pc-console.md` → install →
`uninstall.sh --yes --no-backup` reports `remove 87 file(s) — unchanged since install`, the
`keep N file(s) you modified` branch never fires, and the edited file is gone. `--purge`'s own help
text reads *"Also remove files you modified (default: keep and report them)"* — the default already
removes them.

**The `MODIFIED` branch only ever catches a file edited *after* the last install.** A file edited
before it reads as untouched forever.

**The fix is to branch on the column that was written for this.** `origin = user-modified` means the
file is the user's, whatever its checksum says, and it is kept unless `--purge`. The checksum test
stays for `toolkit` rows, where it correctly distinguishes "we installed it and nobody touched it"
from "we installed it and someone did".

**Rejected: making `install.sh` record the pristine sha instead of the edited one.** It records the
edited sha so the *next install* recognises the file as still-edited; changing that reintroduces the
defect `c2d27f1f` fixed on 2026-08-03, where an edit survived exactly one upgrade and was silently
overwritten by the second. Two consumers need two different things from one row, and the origin
column is how the row already tells them apart.

### D8 — The scripts loop respects a user edit, and the run stops contradicting itself

**Added 2026-08-12, after Task 1b's review measured it.** `install.sh`'s payload loop checks
`is_modified` before writing and records `user-modified` when it keeps. **Its `for group in scripts`
loop does neither** — `cp` is unconditional and the receipt row is `toolkit` regardless.

So a user who edits `.claude/scripts/studio-doctor.sh` gets, in **one run**:

```
warn  5 installed file(s) have local edits — keeping yours:
        .claude/scripts/studio-doctor.sh
ok    Installed 81 file(s), kept 4 of yours.
```

— and the edit is gone. `MODIFIED_FILES` was computed from the receipt *before* the loop ran, so the
warning is accurate about what the installer knew and false about what it then did.

**This is the wave's own thesis failing in the wave's own subject**: every claim `install.sh` makes
about what it owns should be true, and here it makes the right claim and does the opposite. It is
also worse than silent data loss, because the user is told the file is safe in the same breath.

The fix is the payload loop's shape, applied to the loop beside it: check `is_modified`, keep the
user's file, record `user-modified` with its current bytes.

**Task 1b could not have caught this.** The row never reaches `user-modified`, so a classifier that
reads the origin column correctly still sees `toolkit` and correctly deletes.

### D9 — `studio-doctor.sh` reads the origin column, and stops piping into `head`

Two defects in the third reader, one of each kind.

**It discards `_origin`.** A `user-modified` file matches its recorded (edited) checksum, so the
health check counts it as verified: `PASS Install intact: 87 file(s) verified against the receipt`,
with the edited file never named under "modified since install". The diagnostic tells the user
nothing has changed, about a file they changed.

**And it pipes into an early-exiting reader, twice** — `printf '%s' "$LIST" | head -5` — under
`set -euo pipefail`. That is the trap `CLAUDE.md` documents in full: `head` exits after five lines,
the writer takes SIGPIPE, pipefail turns 141 into a failure, and `set -e` kills the script. It
**fires on a long list and hides on a short one**, so it passes every test written against a healthy
project and breaks on the one that needs the diagnostic most.

### D10 — `CLAUDE.md.generated` is the same defect as `manifest.json.bak`, and D2's sentence already covers it

**Added 2026-08-13, after Task 2's review measured it.** D2 says *"A backup the installer keeps is a
file the installer owns."* The reasoning was never specific to backups; it is specific to **files the
installer creates, keeps, announces, and does not record.** Task 2 fixed the one instance the survey
had found. There is a second, and it is on the project root where a user will see it:

```
warn  CLAUDE.md exists and has no generated markers — wrote CLAUDE.md.generated instead.
```

Measured on a fixture whose `CLAUDE.md` is the user's own and marker-less: the receipt's non-`.claude/`
rows are `.mcp.json` and `MCP-SETUP.md` only, and after a full `uninstall.sh --yes` the project root
still holds `CLAUDE.md.generated`. Created by the installer, kept, announced, unrecorded,
**un-removable — forever**, in exactly the projects where the user already had their own `CLAUDE.md`
and the installer politely declined to overwrite it.

The fix is Task 2's, applied again: write the row when the installer **owns** the file at the end of
the run, not when this run happened to create it. The ownership test is `owned_by_installer`, which
already exists and already fails closed.

**Rejected: deleting it at the end of the run.** Same objection D2 makes about the manifest backup —
the file exists so the user can diff it against their own `CLAUDE.md` and merge, and that is work they
do after the installer exits.

**Rejected: treating this as Task 6's sweep.** Task 6 Step 2's `grep -n 'PROJECT_DIR/'` would surface
it, and surfacing it at the end of the wave means recording it as a known defect rather than closing
it. D2's own sentence applies to it verbatim; a wave whose thesis is *"every claim the installer makes
about what it owns is true"* should not ship with a measured, unfixed instance of its own subject.

**Also in scope, because it guards Task 2's own placement decision:** `install.sh` calls
`add_manifest_dependency` twice — once per `--with-*` flag — and both can reach the keep branch in one
run. Task 2 therefore writes its row **once, after both callers**. Nothing asserts that:
`grep -rn 'with-input-system' tests/` returns three comment lines and **no test passes the flag**.
Moving that write back inside the branch is exactly the tidying refactor a later implementer makes,
and the suite would stay green while the receipt carried two rows for one path — at which point
`uninstall.sh` classifies them separately, prints `keep 1 file(s) you modified` naming the file, and
**removes it in the same run**. That is D8's failure shape reached through a receipt rather than
through a loop, and it is measured, not hypothetical.

**Scope discipline, stated so it binds.** This wave has grown four times, each time because a task's
review found the next instance of one root cause. D10 is the **last** insertion. Anything further goes
to the ledger and to a second wave, unless it is data loss in shipped software — which is the bar D7
cleared and nothing since has.

## Acceptance criteria

1. `bash tests/run-tests.sh` green, ANSI-stripped header count equal to `ls tests/test-*.sh | wc -l`.
2. `bash scripts/check-provenance.sh` ends `provenance OK`, with rows for every added file.
3. **Two consecutive installs leave the receipt unchanged in its `MCP-SETUP.md` and `.mcp.json`
   rows**, and `uninstall.sh --yes` after the second removes both.
4. A user's own `MCP-SETUP.md` still gets **no** row after any number of installs, and survives
   uninstall.
5. `manifest.json.bak`, when kept, has a receipt row, and `uninstall.sh` removes it.
6. `install.sh` and `scripts/generate-claude-md.sh` produce the **same** pipeline verdict for every
   fixture, including one carrying both packages — proven by running both against the same fixture
   and comparing, not by reading the code.
7. The new dry-run guard fails when a write is added without an announcement, and fails when an
   announcement is added without a write. **Both directions, mutation-proven**, and across all three
   oracles — a new path, a missing receipt row, and a modified pre-existing file.
8. Against a fixture that already ignores `/.claude/` wholesale, the dry-run does **not** promise a
   `.gitignore` edit, and the real run makes none.
9. `docs/GETTING-STARTED.md`'s Option B states its two costs.
10. **A `.claude/` file the user edited survives `uninstall.sh --yes`**, is counted under
    `keep N file(s) you modified` rather than `unchanged since install`, and is removed by
    `uninstall.sh --purge`. Proven on a fixture in all three directions.
11. **An edited `.claude/scripts/*.sh` survives a reinstall**, and the run's `keeping yours` list and
    its actual writes agree. Proven by editing a shipped script, reinstalling, and comparing bytes.
12. **`studio-doctor.sh` names an edited file under "modified since install"** rather than counting
    it verified, and **no `| head` remains in it** — proven by running it against a project with more
    than five modified files under `set -euo pipefail`.
13. **`CLAUDE.md.generated`, when the installer writes it, has a receipt row and `uninstall.sh` removes
    it** — proven on a fixture whose `CLAUDE.md` is the user's own and marker-less, across two installs,
    with a user-authored `CLAUDE.md.generated` getting **no** row and surviving. And **a single
    `install.sh --with-mcp --with-input-system` run against a project missing both packages produces
    exactly one `Packages/manifest.json.bak` row** — asserted, not verified by hand.

## Out of scope, recorded

- **Reading `ProjectSettings/GraphicsSettings.asset`** — see D3 for what it would take.
- The remaining spin-out items: the runner's blindness to python results, the unguarded derived
  counts, the `file:line` citation guard, the closing `---` fence, `unity-planning`'s missing
  threshold, `studio-doctor.sh`'s unqualified `install.sh` references. **A second wave.**
- **The surface criterion applied to hooks and `scripts/`** — that decides what leaves the pool and
  is the owner's, not this design's.
- P1 and P3, the two parked owner design calls.

## Risks

**D1's ownership test is the whole fix, and it can be wrong in one direction that matters.** If it
decides "we own it" for a file the user wrote, `uninstall.sh` deletes the user's work. The test must
fail *closed* — unknown provenance means no row, means uninstall leaves it alone. Every fixture case
below is written to prove that direction specifically:

- fresh install → row present, uninstall removes it;
- second install → row present, uninstall removes it;
- user's own file present from the start → **no row**, uninstall leaves it;
- user edits a file the installer previously owned → **no row**, uninstall leaves it.

The fourth is the one that is easy to get wrong, because the file was ours a moment ago.
