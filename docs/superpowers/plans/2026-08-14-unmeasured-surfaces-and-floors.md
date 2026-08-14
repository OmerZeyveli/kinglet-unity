# Unmeasured Surfaces and Floors — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `.claude/skills/subagent-driven-implementation/SKILL.md`.
> Fresh implementer per task, review gating on spec *and* quality, bounded fix loop, ledger, one
> whole-branch review at the end. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Measure the surfaces the previous wave never measured, and put the guards that survive an
empty payload onto a criterion instead of a feel.

**Architecture:** Nine follow-ups spun out by the whole-branch review of
`2026-08-13-surface-criterion-and-gaps`, plus eight ledger items routed during its correction pass.
They are not nine independent chores — they are **three questions the last wave answered for
documents and never asked about hooks, floors, or scope**. Grouped accordingly.

**Tech stack:** bash, Markdown, TSV, JSON. **This is the toolkit repository, not a Unity project** —
no Editor, no MCP, no C#.

## Where the evidence lives

- `.superpowers/sdd/2026-08-13-surface-criterion/final-review.md` — the whole-branch review, 1166
  lines. §5 lists the nine follow-ups; each cites the § that measured it. **Gitignored: read it, do
  not assume the next controller has it.** Every claim below that cites a § is reproducible from the
  tree without it.
- `docs/superpowers/plans/2026-08-13-surface-criterion-and-gaps-ledger.md` — items 200–210 carry the
  measurements and the rulings.

## Global Constraints

- **Gates, both, every task.** `bash tests/run-tests.sh` with a timeout of **at least 400000 ms** —
  it runs ~300 s and **a killed run is not a red suite**. Strip ANSI before counting headers:
  `sed $'s/\x1b\\[[0-9;]*m//g' log | grep -c '^--- test-.*\.sh ---'` must equal
  `ls tests/test-*.sh | wc -l`. An anchored `grep -c` on **raw** output returns 0 on a healthy suite.
  `bash scripts/check-provenance.sh` must end exactly `provenance OK`.
- **Never `cmd > log 2>&1; echo "EXIT=$?"`** — that reports the `echo`'s status. It misreported a
  four-failure run as green during the last wave's review. Capture status on its own line.
- **Interactive `grep` is `ugrep 7.5.0`; interactive `find` is `bfs 4.1.1`.** Use `/usr/bin/grep` and
  `/usr/bin/find` for any absence claim and **say which you used**. Two measured divergences: an
  unescaped mid-pattern `$` is a literal in GNU BRE and an **anchor** in ugrep; and `grep -r … .`
  prints `./path` under GNU and `path` under ugrep, so **an exclusion anchored `^\./` excludes
  nothing** and reports a *larger* number rather than an error (ledger 207).
- **Under `set -euo pipefail`, do not pipe into a reader that exits early.** `head` and `grep -q`
  both do. Use `grep -qF -- "$needle" <<< "$haystack"`.
- **`declare -A` and `grep -oP` are forbidden** — macOS ships bash 3.2 and BSD grep.
- **Every file changed under `.claude/` drifts `migration/baseline-inventory.json`.** Regenerate
  **last**, and **derive `--expect-drift` yourself**: it is a property of the file set, not a
  constant. A file in `full_claude_tree/files` counts once; a command or a skill's `SKILL.md` counts
  again in its `categories/` record; `_lib.sh` does **not** double (`categories/hooks` holds the
  registered hooks only) and a non-`SKILL.md` skill file does **not** double.
- **`provenance.tsv`: seven tab-separated columns, append to `note` only, straight apostrophes.** A
  curly `'` reds `tests/test-provenance-origins.sh`.
- **Cite by anchor, never by bare line number** — symbol, heading, or exact text to search for.
- **A derivation whose scope includes the file recording its result is not a derivation.** Ten
  instances last wave. Filter by something the recording cannot match.
- **A probe whose passing condition is silence must first prove its own baseline is not silent.**

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `tests/test-hook-behaviour.sh` | **new.** One positive behavioural probe per registered hook: it acts, and its kill switch kills it. | 1 |
| `.claude/hooks/warn-filename.sh` | repair the `set -e` death that contradicts its own header | 1 |
| `tests/test-hooks.sh` | replace the name-keyed coverage derivation with an execution-keyed one | 2 |
| `tests/test-citations-resolve.sh`, `tests/test-mcp-doc-instructions.sh` | anchor the pathspecs; correct the blind-spot lists | 3 |
| `.claude/commands/unity-doctor.md` | Check 3 item 2, the twin of the item-4 defect already fixed | 4 |
| `scripts/studio-doctor.sh`, `tests/test-studio-doctor.sh` | assert the dead-registration check; fail on empty-but-present payload dirs | 4 |
| `tests/test-no-mobile.sh`, `tests/test-bash32-compat.sh` | the last two guards that stay green over a fully emptied payload | 5 |
| `docs/ANTI-VACUITY.md` | **new.** The written floor criterion the last wave sized by feel ~28 times | 5 |
| `tests/test-surface-references.sh` | a heading inventory for `docs/`; `UB_SECTIONS_EXPECTED` | 6 |
| `CONTRIBUTING.md` | apply the surface criterion to hooks, in the file a contributor opens | 7 |
| `.claude/skills/subagent-driven-implementation/SKILL.md` | refuse a deferral routed to a role rather than a named task | 7 |
| `.claude/hooks/_lib.sh`, `.claude/skills/…/final-reviewer-prompt.md`, `tests/test-shipped-citations.sh` | ledger 207, 209, 205 — three false or half-specified claims | 7 |

---

## Task 1: The three hooks nothing has ever executed

**Files:**
- Create: `tests/test-hook-behaviour.sh`
- Modify: `.claude/hooks/warn-filename.sh`
- Modify: `provenance.tsv` (note column, `warn-filename.sh` row)

**Interfaces:**
- Consumes: nothing. This is the first task and depends on no other.
- Produces: `tests/test-hook-behaviour.sh` — a **runner-provided** test file (it uses the runner's
  `assert_contains` / `assert_eq` / `$REPO_DIR` and defines none of them). **`bash
  tests/test-hook-behaviour.sh` standalone exits 0 having asserted nothing.** Task 2 reads its
  per-hook execution record.

**Why this is task 1.** `warn-filename.sh`, `warn-platform-defines.sh` and `warn-serialization.sh`
are registered in `.claude/settings.json` and executed by **zero** tests. `warn-serialization.sh` is
the hook `.claude/rules/serialization.md` opens its silent-data-loss case with, and the one
`.claude/settings.local.json.template` names as the reason `minimal` is a safety setting — **guarded
by name in three shipped places and by behaviour nowhere.** The first one anyone actually ran turned
out broken. That is a 1-of-1 defect rate on the unmeasured set.

### Step 1: Reproduce the `warn-filename.sh` death before changing it

`.claude/hooks/warn-filename.sh` sets `set -euo pipefail` and its header declares
`# Exit: 0 always (warning only, via stderr)`. The line that contradicts it:

```bash
CLASS_NAME=$(grep -oE '(class|struct)\s+\w+' <<< "$CONTENT" | awk 'NR==1{print $2}')
```

Reaching it requires content that matches `:\s*(MonoBehaviour|...)` but **not**
`(class|struct|interface)\s+$FILENAME\b`. An Edit fragment satisfies both. Then `grep` matches
nothing, exits 1, `pipefail` propagates, the assignment's status **is** the substitution's status,
and `set -e` kills the script before any of the `echo … >&2` lines run.

- [ ] Construct that input as a real hook payload on stdin — `{"tool_input":{"file_path":
      "Assets/Player.cs","new_string":"    : MonoBehaviour, IDamageable\n"}}` — pipe it to the hook,
      and record **rc and byte count**. Expected: **rc=1, 0 bytes.**
- [ ] **Derive the class, do not fix the instance.** Ask of every hook: is there a command
      substitution whose failure is the assignment's status under `set -e`? Report the set. This is
      the same shape `scripts/studio-doctor.sh` was fixed for last wave with `|| true` on four
      `find` sites — **so the class has already bitten this repository once, in a different file.**

### Step 2: Fix it in the direction the header promises

The header is the contract: a warning hook must not fail the tool call. Two shapes, and the choice
is yours to make and justify:

1. `|| true` on the substitution — matches the `studio-doctor.sh` precedent exactly.
2. Restructure so the `grep` runs inside an `if`, where a non-zero status is a condition rather than
   a death.

**Whichever you choose, the fix must not silence a real failure** — a hook that cannot determine the
class name should print nothing and exit 0, which is what the header already promises and what the
`[ -n "$CLASS_NAME" ]` guard on the next line was written for.

- [ ] Fix, re-run the Step 1 payload, record rc and bytes. Expected: **rc=0, 0 bytes.**
- [ ] Re-run a payload that *should* warn (`Assets/Player.cs` carrying `class Enemy : MonoBehaviour`)
      and confirm it still warns: **rc=0, non-zero bytes.** **Prove the baseline is not silent
      before treating silence as a signal.**

### Step 3: One positive behavioural probe per registered hook

`tests/test-hook-behaviour.sh`, runner-provided. For **every** hook registered in
`.claude/settings.json` — derive that list by parsing the JSON, do not hand-maintain it — assert two
things:

1. **It acts.** Given an input it is supposed to respond to, it produces the response: a blocking
   hook exits 2, an advisory hook writes to stderr. **Assert on the output, not on the exit code
   alone**, and assert the output is non-empty *before* any test asserts it is empty.
2. **Its kill switch kills it.** With `DISABLE_UNITY_HOOKS=1`, and again with its own
   `DISABLE_HOOK_<NAME>=1`, the same input produces **zero bytes**.

**The list must not be hand-maintained.** A hand list is an assertion that decays silently — last
wave retired 19 surfaces and extended the relevant hand list by zero while the guard stayed green.
Derive the set from `settings.json` and **fail when a registered hook has no probe**, so adding a
hook and adding its probe are the same commit.

- [ ] Write the derivation and the per-hook loop. **Report which hooks needed a payload you had to
      invent** — that is the honest measure of how unmeasured they were.
- [ ] For each hook, record its acting-output byte count in the test's own output. A probe whose
      passing condition is silence is worthless without its non-silent baseline printed beside it.

### Step 4: Mutation-prove the new file, both directions

- [ ] For each hook, break it so it fails open (comment out the acting branch) and confirm **that
      hook's** assertion reds and the others do not. **A mutation that reds everything has isolated
      nothing.**
- [ ] Break a kill switch (replace `source _lib.sh` with `if false; then source …; fi`) and confirm
      the switch assertion reds. Measured last wave on `warn-serialization.sh`: pristine
      `397 B / 0 B / 0 B` across the three switch states, mutant `397 B / 397 B / 397 B` — **the hook
      survives, the switch is what is lost.**
- [ ] `cmp` each mutant against the original **and** check the injected marker is present, and emit
      an explicit **`MUTANT DID NOT APPLY`** when it is not. The failure is **symmetric**: an
      unapplied mutant makes a hollow guard look sound *and* a sound guard look broken.

### Step 5: Provenance, gates, commit

- [ ] Append to `warn-filename.sh`'s `note` column: what was wrong, and that the header was the
      contract the fix restored. New file `tests/test-hook-behaviour.sh` needs an `original/original`
      row — **a new file with no row fails as an orphan.**
- [ ] Both gates. `.claude/hooks/warn-filename.sh` is inside the baseline, so the suite will be RED
      with baseline failures naming exactly that file, **and that is correct** — enumerate them and
      show the failure set is only that. Regenerate last, derive the drift.

---

## Task 2: Replace the name-keyed hook-coverage derivation with an execution-keyed one

**Files:**
- Modify: `tests/test-hooks.sh` (the comment block containing `TWO HOOKS ARE NAMED BY NO TEST FILE
  AT ALL` and its printed recipe)

**Interfaces:**
- Consumes: Task 1's `tests/test-hook-behaviour.sh` — after it lands, *every* registered hook is
  executed by a test, which is precisely what makes the old sentence false.
- Produces: nothing downstream.

**The three ways it fails at once, and all three are instructive.** `tests/test-hooks.sh` records a
measurement that is **inverted** (a hook with a dead `source` line was called inert in all three
switch states; it is live and *unkillable*); prints a re-derivation command and tells the reader to
trust the command over the comment, where **the command now returns the opposite** because writing
the two hook names into a `tests/*.sh` file is exactly what the command matches; and the row was
**already half-false when written**, because two concurrent worktrees each measured a tree lacking
the other's tests. The inverted conclusion was fixed last wave. **The self-matching recipe was not.**

- [ ] Reproduce: run the printed recipe verbatim. Expected: **it returns nothing**, because the
      record is inside its own scope.
- [ ] Replace *named by a test file* with *executed by a test*. Task 1 gives you the mechanism —
      a hook is covered if `tests/test-hook-behaviour.sh` has a probe for it. **Derive coverage by
      running the probes, not by grepping for names.**
- [ ] The replacement recipe must **exclude nothing by its own path** — filter by something the
      recording cannot match. If you write an exclusion, verify it under **both** `grep` front-ends
      (ledger 207: `^\./` excludes nothing under ugrep and inflates the count).
- [ ] Mutate: remove one hook's probe and confirm the coverage assertion reds.

---

## Task 3: Anchor the unanchored pathspecs — it has a clock on it

**Files:**
- Modify: `tests/test-citations-resolve.sh` (the `git ls-files '*.md'` call and its blind-spot comment)
- Modify: `tests/test-mcp-doc-instructions.sh` (same, plus the TMDI4 assertion)

**Interfaces:** independent of Tasks 1–2.

**`'*.md'` in a git pathspec crosses `/`.** Both guards therefore scan `spikes/`, `tools/` and
`tests/kinglet_spike/` — **17 files** — inside a set whose own blind-spot comment names those trees
as *outside* it. TMDI4 has a **live false-failure vector**: a spike or fixture Markdown file that
happens to match its pattern reds the suite for a reason no maintainer will be able to locate,
because the comment says those trees are not scanned.

- [ ] Reproduce both scanned sets before changing anything: print what each guard actually reads and
      diff it against what its comment claims. **Report the 17, by path.**
- [ ] Anchor with `:(glob)` or an explicit top-level list — your choice, justified. Verify the
      scanned set afterwards equals the documented one **by derivation, not by re-reading the
      comment**: the comment and the code were written by the same commit, so their agreeing with
      each other measures nothing.
- [ ] Demonstrate the false-failure vector before the fix and its absence after: add a Markdown file
      under `spikes/` that trips TMDI4, run the guard, remove it. **Restore the tree; `git status`
      clean in your verdict.**
- [ ] Correct both blind-spot comments to name the set the anchored pathspec actually reads.

---

## Task 4: The doctor's two remaining compensations

**Files:**
- Modify: `.claude/commands/unity-doctor.md` (Check 3 item 2)
- Modify: `scripts/studio-doctor.sh` (dead-registration check; empty-but-present payload dirs)
- Modify: `tests/test-studio-doctor.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: a `studio-doctor.sh` that reports two things `unity-doctor.md` currently instructs a
  model to check by hand. **Retiring a compensation means deleting it from the command**, not
  leaving both.

**`unity-doctor.md` Check 3 item 2 carries the identical defect item 4 was fixed for last wave, four
lines above it.** It instructs: *for every `.sh` in `.claude/hooks/` except `_lib.sh`, confirm it
appears in `PreToolUse` or `PostToolUse`; unregistered → WARNING.* `session-brief.sh` and
`session-restore.sh` are on `SessionStart`; `session-save.sh` is on `Stop`. **Three spurious WARNINGs
on a healthy install, from a shipped payload command.** Item 4 was rescoped **by event** for exactly
this reason — apply the same axis.

- [ ] Fix item 2 on the event axis, matching item 4's wording so the two cannot drift apart.
- [ ] `studio-doctor.sh`'s dead-registration sweep (`Hooks N (M registered, K dead)`) is **asserted by
      nothing**. Add the assertion to `tests/test-studio-doctor.sh` — **runner-provided; read its
      section through the runner, never standalone.** A plan last wave told an implementer to verify
      a new check with `bash tests/test-studio-doctor.sh` and expect a failure; it would have
      reported a pass in both directions.
- [ ] Make the script **fail on an empty-but-present payload directory.** Measured: an empty
      `.claude/agents/` passes a bare existence test and passes the doctor, which prints
      `INFO agents=0`, `0 failure(s)` and exits 0 — **a project with no agents at all, reported
      healthy by both.**
- [ ] Delete from `unity-doctor.md` whatever the script now reports. Two sources for one fact is how
      the duplication Check 2 removed creeps back.
- [ ] Mutate each new assertion; confirm it reds; `cmp` the mutant.

---

## Task 5: A written rule for anti-vacuity floors, and the last two vacuous-green guards

**Files:**
- Create: `docs/ANTI-VACUITY.md`
- Modify: `tests/test-no-mobile.sh`, `tests/test-bash32-compat.sh`
- Modify: any guard whose floor the criterion reclassifies

**Interfaces:**
- Consumes: nothing.
- Produces: the criterion Task 7's ledger-205 fix cites.

**~28 floors, ratios from 2 % to 97 %, no criterion anywhere.** `LIVE_N ≥ 30` over 141; `up_seen ≥ 1`
over 5; a root-installed derivation's `≥ 2` over 4. Each was justified locally and **each survives
losing most of its subject.** No per-task review compares floors to their subjects, because a floor
and its subject live in different files.

**And the structural result, which is the actual finding:** *a floor over a summed multi-source
subject cannot detect one source dying, however tight the number.* `tests/test-no-mobile.sh` and
`tests/test-bash32-compat.sh` are the only two of 38 that stay green over a **fully emptied payload**,
and both fail for that one reason. **One shape fixes both: assert per source, not per union.**

- [ ] Re-derive the floor set. **Build the window from an array, not with `getline`** — a `getline`
      window scan silently missed 14 of ~28 members last wave and looked complete. Report your count
      *and* your criterion; two readers who agree on a number without a written criterion have agreed
      by accident.
- [ ] Write `docs/ANTI-VACUITY.md`: when a floor is needed, how it is sized, and the per-source rule.
      **State the ratio each existing floor implies** — that table is the artifact, not the prose.
- [ ] Convert `test-no-mobile.sh` and `test-bash32-compat.sh` to per-source assertions.
- [ ] **Prove it: empty the payload and confirm both now red.** Do it in a clone
      (`git clone --no-hardlinks --shared`, never `cp -a` — a `.git` file pointing at the real repo
      cost a reviewer 15 spurious failures), never `git stash` (repository-global).
- [ ] Ledger 203 belongs here: mutating `docs/HOOK-REFERENCE.md`'s `drops 8 of the 12` to a wrong
      digit reds the gate, **but reverting the whole sentence to its pre-fix spelled-out wording
      stays green**, because a sibling sentence at `:45` satisfies the per-file vacuity check alone.
      **The defect the last wave fixed can be reintroduced verbatim without reddening anything.**
      Fix it under the criterion you just wrote.

---

## Task 6: A heading inventory for `docs/`

**Files:**
- Modify: `tests/test-surface-references.sh`

**Interfaces:** consumes Task 5's criterion for the floor on the new inventory.

`docs/ARCHITECTURE.md` **lost a whole `##` section and no guard noticed.** Two skills carry a heading
inventory (`ub_section`, `uk_section`); **`docs/` has no analogue.** That is the second document this
wave silently changed shape.

- [ ] Add a heading inventory for the `docs/` files that are structural (`ARCHITECTURE.md`,
      `HOOK-REFERENCE.md`, `GETTING-STARTED.md`) and a `UB_SECTIONS_EXPECTED` for
      `unity-brainstorming`.
- [ ] **Do not use `/^#{1,3} /` without knowing the risk.** BSD awk's handling of the interval is
      untested on real BSD awk. Simulated last wave — both terminators replaced with a pattern no
      heading matches — the failure is **loud** (95 pass / 15 fail), not silent, which is the good
      direction. Keep it that way, and say which form you used.
- [ ] Mutate: delete a section, confirm red. Delete the *last* section, confirm red — a list survives
      the deletion of its last member without one word changing.

---

## Task 7: The claims with no owner

**Files:**
- Modify: `.claude/hooks/_lib.sh` (ledger 207)
- Modify: `.claude/skills/subagent-driven-implementation/final-reviewer-prompt.md` (ledger 209)
- Modify: `tests/test-shipped-citations.sh` (ledger 205)
- Modify: `.claude/skills/subagent-driven-implementation/SKILL.md` (follow-up 8)
- Modify: `CONTRIBUTING.md` (follow-up 4)

**Interfaces:** consumes Task 5's `docs/ANTI-VACUITY.md` for the citation in ledger 205.

Five small, unrelated-looking edits that are one thing: **a claim nobody owns.**

- [ ] **Ledger 207.** `_lib.sh` says the ugrep-blind exclusion left *"every count inflated by
      three"*. Six of twelve were inflated by **2 or 4** — the inflation is each function's own
      self-hit count, not a constant — and it is false for **one of the two rows the paragraph is
      written about**. Re-derive the twelve, then either state the rule or delete the number. It sits
      in a paragraph whose preceding sentences are *"DERIVE THE SET; DO NOT TRUST THIS LIST EITHER"*
      and *"Run the check; do not write the answer."*
- [ ] **Ledger 209.** `final-reviewer-prompt.md`'s `11/29` is pinned to commit `b9f2711` but **never
      names the two documents it was measured over.** A reviewer reproduced it only by trying pairs
      (`README.md` + `docs/ARCHITECTURE.md` → 11/29; four other pairings give 3/15, 12/38, 15/35,
      24/58). **A pin to a commit without a pin to a file set is half a pin.**
- [ ] **Ledger 205.** `tests/test-shipped-citations.sh` says its fifteen was derived by *"applying the
      same criterion"*, and it was not: an independent re-derivation returns **13**, because the guard's
      own code resolves `scripts/*` tokens it does not flag. **Both numbers are right under their own
      rule; the comment names neither.** Counting *citation sites* gives 15; counting distinct
      `(file, path)` pairs gives 13. Say which.
- [ ] **Follow-up 8.** Make `subagent-driven-implementation` **refuse a deferral routed to a role
      rather than a named task.** Four of six open ledger items last wave shared one cause —
      `→ whoever next opens that file` — which is the same defect ledger 71 filed against elsewhere
      the same night. **A deferral with no owner is not a deferral; it is a deletion with a
      paper trail.**
- [ ] **Follow-up 4.** Apply the surface criterion to hooks in `CONTRIBUTING.md`. `CLAUDE.md` already
      records that the criterion was applied to hooks on 2026-08-13 and that **nothing forces it to be
      answered for the next hook added.** `CONTRIBUTING.md` is the file a contributor actually opens.
- [ ] Both gates; `.claude/` files drift the baseline; derive the drift.

---

## Task 8: Record what a second reader can reproduce

**Files:**
- Modify: `docs/superpowers/plans/2026-08-13-surface-criterion-and-gaps-ledger.md`
- Modify: `tests/run-tests.sh` **or** the spike test files — your choice, justified

**The last wave gated sixteen units on a total nobody else can obtain.** This checkout reports
`Skipped: 3`; a fresh clone reports `Skipped: 22`, because **19 assertions run only for the author** —
they are gated on `spikes/platform/clients/probe-host/dist/`, an untracked gitignored build artifact.
Both are green. Neither is wrong. **But a figure a second reader cannot reproduce is not a gate.**

- [ ] Reproduce both: run the suite here, and in a `git clone --no-hardlinks --shared`. Report both.
- [ ] Decide and justify: make the spike skips **loud** (so the difference is visible in the log
      rather than in the total), or record the fresh-clone figures as the canonical ones. **State
      which reader each figure is for.**
- [ ] Whatever you choose, **`CLAUDE.md` forbids writing a total down** and is right to. The
      consequence — that the only cross-task check on suite size is a human reading consecutive
      reports — is the thing to address, not the rule.

---

## Self-review notes

**Spec coverage.** All nine spun-out follow-ups are placed: 1→T1, 2→T3, 3→T2, 4→T7, 5→T5, 6→T6,
7→T4, 8→T7, 9→T8. Ledger items: 203→T5, 205→T7, 207→T7, 208→T4, 209→T7, 210→T2. Items 200–202, 204
and 206 are subsumed by T1/T2/T4.

**Ordering.** T1 before T2 (T2's replacement mechanism is T1's output). T5 before T6 and T7 (both
cite its criterion). T3, T4, T8 are independent and may run in any slot.

**What this plan does not cover, deliberately.** Widening rule 4 to the other 22 non-Markdown payload
files (ledger 202) — it needs a decision no task owns: `install.sh` and `uninstall.sh` must be exempt
**by role, not by marker**. That is a design question, not an implementation one, and it goes to
`unity-brainstorming` before it goes into a plan.

**The honest limit, unchanged.** Nothing here proves the toolkit works **inside Claude Code**. No
scout has ever run a command against a live Editor; there is no MCP in this repository. Every claim
about what a model does with a rewritten surface is a reading of instructions. **That is what the
Endless Evolution migration tests, and it is a bigger gap than all nine follow-ups combined.**
