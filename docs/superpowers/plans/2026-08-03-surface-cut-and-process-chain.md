# Surface Cut and Process Chain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut Kinglet Pioneer's surface pool from 103 to 32, give the survivors trigger-condition descriptions, and chain them together with a small process layer so the toolkit is used without anyone memorising a name.

**Architecture:** Seven tasks in dependency order. Two remove surfaces (the design/production track first, because it is one evidence source and one clean cascade; then everything else). One adds the guard that today's measurement proved missing. One transcribes descriptions that were already designed and never shipped. One adds the process chain. One adds proactive suggestion. One corrects the repo's own documentation and re-runs the measurement that justifies the whole wave.

**Tech Stack:** Markdown frontmatter, bash 3.2-compatible shell, `tests/run-tests.sh`, `scripts/check-provenance.sh`, `python3 -m tools.kinglet_build baseline-regenerate`.

**Authority:** `docs/superpowers/specs/2026-08-03-surface-cut-and-process-chain-design.md` (commit `765a58a`). Where this plan and the spec disagree, the spec governs and the disagreement is a bug in this plan — report it.

## Global Constraints

- **Bash 3.2 (macOS) compatible.** No `declare -A`. No `grep -oP`, no `grep -qP` — GNU-only.
- **Do not pipe into a reader that can exit early** under `set -euo pipefail`. `head` and `grep -q` both exit on first match without draining stdin; the writer takes SIGPIPE, `pipefail` turns 141 into failure, and `set -e` kills the script. Use a here-string: `grep -qF -- "$needle" <<< "$haystack"`.
- **Validate an argument before `shift 2`** — `shift` fails under `set -u` before the error message prints.
- **`bash tests/run-tests.sh` must pass at every commit, with every test file present in its output.** Count `--- test-*.sh ---` headers and confirm the count equals `ls tests/test-*.sh | wc -l`. The summary line is not evidence.
- **`bash scripts/check-provenance.sh` must report `provenance OK`** at every commit.
- **Every removed path gets a `provenance-skip.tsv` row with `rule=absent`, in the same commit that removes it.** Its `provenance.tsv` row is deleted in that same commit. A file with no row fails as an orphan; a row with no file fails too.
- **`provenance.tsv` columns, tab-separated:** `path │ origin │ upstream_version │ upstream_path │ upstream_sha256 │ status │ note`. Valid `origin`: `ecu|donchitos|original`. Valid `status`: `verbatim|modified|original`.
- **`provenance-skip.tsv` columns, tab-separated:** `path │ origin │ rule │ note`. Valid `rule`: `absent|ours-wins`. `rule=ours-wins` paths must be `origin=original`.
- **Editing or removing anything under `.claude/` drifts `migration/baseline-inventory.json`.** Regenerate in a **separate commit** from the content change. Each path is tracked in **two** places (`full_claude_tree.files` and `categories.<kind>.files`), so one file is a drift of 2.
- **Learn the drift count with `--dry-run` before regenerating.** The tool refuses when the predicted count is wrong, and that refusal is the safety net — do not guess the number and do not tune it to make the refusal go away. If the count differs from this plan's prediction, stop and report: it means the change set is not what the plan thought.
- **Frontmatter only when editing `description:`.** Some files carry a second `description:` in the body inside example blocks. Target only the first `description:` inside the first `---` block.
- **Preserve unusual frontmatter keys verbatim.** `unity-optimizer`, `unity-prototyper`, `unity-shader-dev` and `unity-ui-builder` carry a `skills:` key nothing else has. `unity-shader-dev` is removed; the other three keep the key, with removed skill names taken out of its value.
- **Do not touch `spikes/platform/clients/`.** A separate experiment there asserts on exact description wording.
- **Announce nothing to the user mid-task.** Report at task end.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `.claude/agents/*.md` | 20 removed, 8 survive with rewritten descriptions | 1, 2, 4 |
| `.claude/commands/*.md` | 25 removed, 11 survive with rewritten descriptions | 1, 2, 4 |
| `.claude/skills/*/SKILL.md` | 29 removed, 10 survive, 3 added, 1 rewritten | 1, 2, 5 |
| `.claude/skills/using-kinglet/SKILL.md` | Entry point, chain map, proactive posture | 5 |
| `.claude/skills/systematic-debugging/SKILL.md` | Debugging method (Kinglet has an agent, no method) | 5 |
| `.claude/skills/verification-before-completion/SKILL.md` | Field note §36's "ship the test" rule | 5 |
| `.claude/hooks/session-brief.sh` | Injects `using-kinglet` at session start | 5 |
| `.claude/settings.json` | Registers the `SessionStart` hook | 5 |
| `tests/test-surface-references.sh` | New guard: bare-name skill references | 3 |
| `provenance.tsv` / `provenance-skip.tsv` | Rows follow their files | 1, 2, 5 |
| `migration/baseline-inventory.json` | Regenerated, always its own commit | 1, 2, 5 |
| `CLAUDE.md` | Corrected for the provenance re-basing | 7 |
| `docs/research/pioneer/smoke-pass.md` | New dated section with the re-measurement | 7 |

---

### Task 0: Teach the baseline regenerator to accept a deliberate path-set change

**Added mid-execution.** Task 1 shipped its content commit (`ad42902`) and then hit a hard stop: `python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift 52 --dry-run` exits 2 with 52 `path missing at anchor` refusals and `expected drift 52, found 0`. This is not a wrong-number case. Reading `tools/kinglet_build/baseline.py`, `regeneration_plan` sorts every path into one of three outcomes:

- present at anchor with a different `sha256`/`git_mode` → a countable `BaselineChange`;
- **recorded but missing at anchor → an unconditional refusal** (`:218`, `:226`), never countable;
- **present under `.claude/` but not recorded → an unconditional refusal** (`unrecorded .claude path at anchor`).

So no `--expect-drift` value can describe a removal or an addition. The module docstring states this is deliberate — the plan gate "makes the *path set* of the baseline immutable without a deliberate act" — but the tool provides no way to *perform* that deliberate act. Tasks 1 and 2 remove 74 files and Task 5 adds 4; all three are blocked.

`apply_regeneration` has the matching gap: it only rewrites `sha256`/`git_mode` on records that already exist. It cannot drop a record or insert one, and it never touches the `expected_count` fields.

**The fix is the missing door, not a bypass.** `--expect-drift` makes a content change deliberate by forcing the caller to name the count. This task adds the same mechanism for the path set: `--expect-removed` and `--expect-added`. **Absent both flags, behaviour is byte-for-byte what it is today** — a path-set change is still a hard refusal. That default is itself a test.

**Files:**
- Modify: `tools/kinglet_build/baseline.py`
- Modify: `tools/kinglet_build/cli.py`
- Modify: `tests/kinglet/test_baseline_inventory.py`
- Modify: `migration/baseline-inventory.json` (its own commit, at the end — clears Task 1's outstanding removal)
- Modify: `provenance.tsv` (status/note for the edited tracked files, if they carry rows)

**Interfaces:**
- Produces: `regeneration_plan(repo_root, commit, baseline, expected_drift=None, expected_removed=None, expected_added=None) -> RegenerationPlan`, where `RegenerationPlan` gains `removals: tuple[BaselineRemoval, ...]` and `additions: tuple[BaselineAddition, ...]` beside its existing `changes`. CLI gains `--expect-removed N` and `--expect-added N`. Tasks 1, 2 and 5 consume this.

**A correction to the option this task was chosen from.** The choice offered to the operator said the tests would read their expected counts from the JSON. **Do not do that.** Today the test asserts four independent things agree: a hardcoded constant, the JSON's `expected_count`, `len(records)`, and the actual git tree. Reading the constant from the JSON deletes the only independent witness and turns the guard into a tautology. The constants stay hardcoded. What changes is that the **test names** stop encoding them, because a name is what goes stale silently — `CLAUDE.md` records that exact failure twice.

- [ ] **Step 1: Write the failing tests first.** Add to `tests/kinglet/test_baseline_inventory.py`. These use the real `regeneration_plan` against a synthetic baseline document, so they need no git anchor beyond `HEAD`.

```python
    def test_removal_is_refused_when_no_expect_removed_flag_is_given(self) -> None:
        """The default must not change: a path-set change stays a hard refusal."""
        baseline = self._baseline_with_extra_record(".claude/agents/does-not-exist.md")
        plan = regeneration_plan(REPOSITORY_ROOT, "HEAD", baseline)
        self.assertFalse(plan.approved)
        self.assertTrue(
            any("path missing at anchor" in refusal for refusal in plan.refusals),
            plan.refusals,
        )
        self.assertEqual((), plan.removals)

    def test_removal_is_counted_when_expect_removed_matches(self) -> None:
        baseline = self._baseline_with_extra_record(".claude/agents/does-not-exist.md")
        plan = regeneration_plan(
            REPOSITORY_ROOT, "HEAD", baseline, expected_removed=2
        )
        self.assertTrue(plan.approved, plan.refusals)
        self.assertEqual(
            {".claude/agents/does-not-exist.md"},
            {removal.path for removal in plan.removals},
        )

    def test_removal_count_mismatch_still_refuses(self) -> None:
        baseline = self._baseline_with_extra_record(".claude/agents/does-not-exist.md")
        plan = regeneration_plan(
            REPOSITORY_ROOT, "HEAD", baseline, expected_removed=99
        )
        self.assertFalse(plan.approved)
        self.assertTrue(
            any("expected removed 99" in refusal for refusal in plan.refusals),
            plan.refusals,
        )

    def test_apply_regeneration_drops_the_record_and_decrements_expected_count(
        self,
    ) -> None:
        baseline = self._baseline_with_extra_record(".claude/agents/does-not-exist.md")
        before_full = baseline["full_claude_tree"]["expected_count"]
        before_agents = baseline["categories"]["agents"]["expected_count"]
        plan = regeneration_plan(
            REPOSITORY_ROOT, "HEAD", baseline, expected_removed=2
        )
        applied = apply_regeneration(baseline, plan)

        full_paths = [r["path"] for r in applied["full_claude_tree"]["files"]]
        agent_paths = [r["path"] for r in applied["categories"]["agents"]["files"]]
        self.assertNotIn(".claude/agents/does-not-exist.md", full_paths)
        self.assertNotIn(".claude/agents/does-not-exist.md", agent_paths)
        self.assertEqual(before_full - 1, applied["full_claude_tree"]["expected_count"])
        self.assertEqual(
            before_agents - 1, applied["categories"]["agents"]["expected_count"]
        )
        self.assertEqual(sorted(full_paths), full_paths)
        self.assertEqual(sorted(agent_paths), agent_paths)
```

`_baseline_with_extra_record(path)` is a helper this task also writes: it deep-copies the real baseline document, appends a record for `path` with a fake but well-formed `sha256` (64 hex chars) and `git_mode` `100644` to **both** `full_claude_tree.files` and the matching `categories.<kind>.files`, re-sorts both lists by path, and increments both `expected_count` fields. The record is for a path that does not exist in the tree, which is what makes it read as a removal.

**Note the count in the second and third tests is 2, not 1.** The helper adds one record to `full_claude_tree` and one to `categories.agents`, and `regeneration_plan` walks both structures — so one absent file produces two removals, the same doubling the plan's Global Constraints already state for drift.

- [ ] **Step 2: Run them and watch them fail.**

Run: `python3 -m unittest tests.kinglet.test_baseline_inventory -v 2>&1 | tail -20`
Expected: the four new tests fail — `regeneration_plan() got an unexpected keyword argument 'expected_removed'` for three of them, and `AttributeError: 'RegenerationPlan' object has no attribute 'removals'` for the first. A test that passes here is testing nothing; stop and fix the test before writing the implementation.

- [ ] **Step 3: Implement removals in `baseline.py`.**

Add beside `BaselineChange`:

```python
@dataclass(frozen=True)
class BaselineRemoval:
    path: str
    structure: str  # "full_claude_tree" or "categories.<name>"


@dataclass(frozen=True)
class BaselineAddition:
    path: str
    structure: str
    sha256: str
    git_mode: str
```

Give `RegenerationPlan` the two new tuple fields, defaulting to `()` so existing constructions keep working. Then in `regeneration_plan`, change the two `path missing at anchor` sites so they append a `BaselineRemoval` when `expected_removed is not None`, and keep the refusal otherwise. Add the count gate beside the existing drift gate:

```python
    if expected_drift is not None and expected_drift != len(changes):
        refusals.append(f"expected drift {expected_drift}, found {len(changes)}")
    if expected_removed is not None and expected_removed != len(removals):
        refusals.append(f"expected removed {expected_removed}, found {len(removals)}")
    if expected_added is not None and expected_added != len(additions):
        refusals.append(f"expected added {expected_added}, found {len(additions)}")
```

- [ ] **Step 4: Implement additions in `baseline.py`.** The `unrecorded .claude path at anchor` loop becomes a `BaselineAddition` when `expected_added is not None`, carrying the anchor's real `sha256` and mode. An addition must be recorded in `full_claude_tree` **and** in its category — so it needs the path→category mapping.

**Do not invent that mapping.** `tests/kinglet/test_baseline_inventory.py` already implements it as `category_paths(category, tracked)`, and the baseline also has a set of paths deliberately in `full_claude_tree` but in no category (`OMITTED_FROM_SEVEN_CATEGORIES` in the same file). Lift that categorisation into `tools/kinglet_build/baseline.py` as a module-level function and have the test import it from there, so one definition serves both. A path that maps to no category gets a `full_claude_tree` addition only.

- [ ] **Step 5: Implement removal and addition in `apply_regeneration`.** It must drop removed records from each structure they appear in, insert added records in sorted position, and update `expected_count` on every structure it touched. Assert the invariant the tests check: `files` stays sorted by `path` and `expected_count == len(files)`.

- [ ] **Step 6: Run the new tests to green.**

Run: `python3 -m unittest tests.kinglet.test_baseline_inventory -v 2>&1 | tail -20`
Expected: the four new tests pass. The 30 pre-existing failures from Task 1's removal are still there — Step 9 clears them.

- [ ] **Step 7: Add the CLI flags in `cli.py`,** beside `--expect-drift` and with the same shape (`type=int`, **not** `required`, so omitting them preserves today's behaviour), and pass them through to `regeneration_plan`.

```python
    regenerate.add_argument(
        "--expect-removed",
        type=int,
        dest="expect_removed",
        help="the number of recorded paths the caller expects to be gone at the anchor",
    )
    regenerate.add_argument(
        "--expect-added",
        type=int,
        dest="expect_added",
        help="the number of unrecorded .claude paths the caller expects at the anchor",
    )
```

- [ ] **Step 8: Rename the two tests whose names encode counts.** Their assertions and constants stay exactly as they are — only the names change, because a count in a name goes stale silently while a count in an assertion fails loudly.

- `test_inventory_counts_are_exact_28_36_39_26_6_5_10` → `test_inventory_counts_match_the_expected_counts_constant`
- `test_full_claude_tree_baseline_covers_all_148_tracked_files` → `test_full_claude_tree_baseline_covers_every_tracked_claude_file`

Then update `EXPECTED_COUNTS` and the `148` literals to the values that hold after Task 1's removal: agents `20`, commands `27`, skills `30`, hooks `26`, rules `6`, claude_templates `6`, code_templates `10`, and full tree `122`. **Verify each against the tree rather than trusting this list** — `git ls-files '.claude/agents/*.md' | wc -l` and the equivalents — and if any disagrees, report the discrepancy instead of writing the number that makes the test pass.

- [ ] **Step 9: Clear Task 1's outstanding baseline.** This is what proves the new flags work on the real case.

```bash
cd "$(git rev-parse --show-toplevel)"
python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD \
    --expect-drift 0 --expect-removed 52 --expect-added 0 --dry-run
```

Expected: an approved plan with 52 removals. If it refuses, read the refusal — it is telling you the change set is not what this plan predicted, and that is information to report, not a number to tune. Then run without `--dry-run`.

- [ ] **Step 10: Full suite green.**

```bash
bash tests/run-tests.sh > /tmp/t0.log 2>&1; echo "exit=$?"
tail -3 /tmp/t0.log
grep -c -- '--- test-' /tmp/t0.log; ls tests/test-*.sh | wc -l
bash scripts/check-provenance.sh
```

Expected: `exit=0`, zero failures, header count equal to the file count, `provenance OK`. The suite takes about 2m25s — use a timeout above 150000ms.

- [ ] **Step 11: Commit in two commits** — the tool and tests first, the regenerated baseline second, so the baseline change is reviewable on its own.

```bash
git add tools/kinglet_build/baseline.py tools/kinglet_build/cli.py tests/kinglet/test_baseline_inventory.py provenance.tsv
git commit -m "feat(baseline): let a deliberate path-set change be named, not just refused

regeneration_plan sorted every path into countable content drift or an
unconditional refusal, and a removal or addition could only ever be the
latter. The docstring says the path set is immutable 'without a
deliberate act' — but there was no way to perform that act, so the
2026-08-03 skill flattening was applied by hand.

--expect-removed and --expect-added do for the path set what
--expect-drift does for content. Absent both, behaviour is unchanged
and a path-set change is still a hard refusal; that default has its own
test.

Two test names encoded their counts and are renamed. The counts stay
hardcoded as assertions: they are the independent witness against the
JSON, and reading them from the JSON would make the guard a tautology."

git add migration/baseline-inventory.json
git commit -m "chore(baseline): record the design/production track removal

52 removals (26 files, each tracked in full_claude_tree and its
category). First use of --expect-removed."
```

---

### Task 1: Remove the design/production track

The single best-measured cut. Field note §36: across 17,316 lines of documentation on the only real project this toolkit has met, `docs/design/`, `docs/production/` and `docs/adr/` were used **zero times out of three**. Removing the eight design agents strands nine genre skills by itself — one chain through two layers.

**Files:**
- Delete (8 agents): `.claude/agents/creative-director.md`, `game-designer.md`, `level-designer.md`, `narrative-director.md`, `systems-designer.md`, `technical-director.md`, `world-builder.md`, `writer.md`
- Delete (9 commands): `.claude/commands/brainstorm.md`, `design-review.md`, `design-system.md`, `estimate.md`, `map-systems.md`, `milestone-review.md`, `retrospective.md`, `scope-check.md`, `sprint-plan.md`
- Delete (9 skills): `.claude/skills/match3/`, `rpg/`, `puzzle/`, `topdown/`, `platformer-2d/`, `idle-clicker/`, `inventory-system/`, `dialogue-system/`, `procedural-generation/`
- Modify: `tests/test-no-mobile.sh:51` — remove the hardcoded skill-count assertion (see below)
- Modify: `provenance.tsv` (delete 26 rows), `provenance-skip.tsv` (add 26 rows)
- Separate commit: `migration/baseline-inventory.json`

**A blocking conflict, found in pre-flight and resolved by the operator.** `tests/test-no-mobile.sh:51`
asserts `find .claude/skills -name SKILL.md | wc -l` equals `39`. Removing nine skills makes it 30 and
the suite fails at this task's own gate.

**Delete the assertion line, do not update the number.** That test's purpose is the mobile guard — the
`assert_absent` lines above it and the banned-term sweep below it — and the total count is incidental to
that purpose. `CLAUDE.md` states the rule directly for a different count and gives the reason: *"a
hardcoded count goes stale the next time a test file is added or removed, which is exactly the failure
mode this note exists to prevent, and it had gone stale twice."* The same argument applies here, and the
cut is the third staleness event. Leave the neighbouring `assert_eq` on `find examples -type f` at `4`
alone — examples are untouched by this wave.

**Interfaces:**
- Produces: a `.claude/` tree with 20 agents, 27 commands, 30 skills. Task 2 consumes that state.

- [ ] **Step 1: Confirm nothing surviving points at these by path.** Run:

```bash
cd "$(git rev-parse --show-toplevel)"
grep -rhoE '\.claude/(agents|commands|skills)/[A-Za-z0-9_-]+' .claude/agents .claude/commands \
  | sort -u > /tmp/refs-before.txt
wc -l < /tmp/refs-before.txt
```

Expected: a list you will re-check in Step 6. This is a snapshot, not an assertion.

- [ ] **Step 2: Delete the 26 files.**

```bash
git rm -q .claude/agents/creative-director.md .claude/agents/game-designer.md \
  .claude/agents/level-designer.md .claude/agents/narrative-director.md \
  .claude/agents/systems-designer.md .claude/agents/technical-director.md \
  .claude/agents/world-builder.md .claude/agents/writer.md
git rm -q .claude/commands/brainstorm.md .claude/commands/design-review.md \
  .claude/commands/design-system.md .claude/commands/estimate.md \
  .claude/commands/map-systems.md .claude/commands/milestone-review.md \
  .claude/commands/retrospective.md .claude/commands/scope-check.md \
  .claude/commands/sprint-plan.md
git rm -q -r .claude/skills/match3 .claude/skills/rpg .claude/skills/puzzle \
  .claude/skills/topdown .claude/skills/platformer-2d .claude/skills/idle-clicker \
  .claude/skills/inventory-system .claude/skills/dialogue-system \
  .claude/skills/procedural-generation
```

- [ ] **Step 3: Move their provenance rows to the skip manifest.** For each deleted path, delete its `provenance.tsv` row and append a `provenance-skip.tsv` row. The skip row is four tab-separated fields: `path`, `origin` (copied from the provenance row it replaces), `rule` (always `absent`), `note`.

Use these three notes verbatim, by group:

- 8 agents + 9 commands: `design/production track removed 2026-08-03; field note 36 measured docs/design, docs/production and docs/adr used 0 of 3 on a real project`
- 9 skills: `genre template removed 2026-08-03; the model knows these genres and selection pool size is the scarce resource`

Skill directories are recorded by their `SKILL.md` path, matching how `provenance.tsv` already records them. Check the existing row before writing the skip row so the path form matches exactly:

```bash
grep -F 'skills/match3' provenance.tsv
```

- [ ] **Step 4: Verify the manifests agree with the tree.**

Run: `bash scripts/check-provenance.sh`
Expected: `provenance OK`. If it reports an orphan, a file exists with no row; if it reports a missing file, a row survived its file.

- [ ] **Step 5: Run the suite.**

Run: `bash tests/run-tests.sh`
Expected: pass, and `--- test-` header count equals `ls tests/test-*.sh | wc -l`. Confirm both:

```bash
bash tests/run-tests.sh > /tmp/t1.log 2>&1; echo "exit=$?"
grep -c -- '--- test-' /tmp/t1.log; ls tests/test-*.sh | wc -l
```

- [ ] **Step 6: Confirm no dangling references were introduced.**

```bash
grep -rhoE '\.claude/skills/[A-Za-z0-9_-]+' .claude/agents .claude/commands 2>/dev/null \
  | sed 's|.claude/skills/||' | sort -u | while read -r s; do
      [ -f ".claude/skills/$s/SKILL.md" ] || echo "DANGLING: $s"
    done
```

Expected: no output. `tests/test-skill-discovery.sh` asserts this too; this is the fast local check.

- [ ] **Step 7: Commit the removal.**

```bash
git add -A .claude provenance.tsv provenance-skip.tsv
git commit -m "feat(cut): remove the design/production track

8 agents, 9 commands, 9 genre skills. Field note 36 measured
docs/design, docs/production and docs/adr used 0 of 3 across 17,316
lines of documentation on the only real project this toolkit has met.

Removing the design agents strands the genre skills by itself.

Refs: docs/superpowers/specs/2026-08-03-surface-cut-and-process-chain-design.md"
```

- [ ] **Step 8: SUPERSEDED by Task 0.** This step originally said to regenerate the baseline with
`--expect-drift 52`. The tool refuses a path-set change by design and no `--expect-drift` value can
express a removal — see Task 0, which adds `--expect-removed` and clears this task's outstanding 52
removals at its Step 9. Task 1 ends at Step 7 plus Step 9's verification. Do not attempt the
regeneration here.

```bash
python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift 52 --dry-run
```

If the tool reports a different count, **stop and report it** — the change set is not what this plan predicted. Do not adjust the number to make it pass. If it agrees, run without `--dry-run` and commit:

```bash
python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift 52
git add migration/baseline-inventory.json
git commit -m "chore(baseline): record the design/production track removal"
```

- [ ] **Step 9: Confirm green.** `bash tests/run-tests.sh` and `bash scripts/check-provenance.sh` both pass.

---

### Task 2: Remove the remaining surfaces

**Files:**
- Delete (12 agents): `.claude/agents/unity-coder-lite.md`, `unity-fixer-lite.md`, `unity-linter.md`, `unity-build-runner.md`, `unity-critic.md`, `unity-git-master.md`, `unity-migrator.md`, `unity-network-dev.md`, `unity-scout.md`, `unity-security-reviewer.md`, `unity-shader-dev.md`, `unity-verifier.md`
- Delete (16 commands): `.claude/commands/unity-skillify.md`, `unity-skill-stocktake.md`, `unity-instincts.md`, `unity-learn.md`, `unity-sessions.md`, `unity-session-save.md`, `unity-session-resume.md`, `unity-team.md`, `unity-ralph.md`, `unity-audit.md`, `unity-interview.md`, `unity-build.md`, `unity-migrate.md`, `unity-network.md`, `unity-shader.md`, `unity-profile.md`
- Delete (20 skills): `.claude/skills/serialization-safety/`, `event-systems/`, `scriptable-objects/`, `commit-trailers/`, `hud-statusline/`, `learner/`, `navmesh/`, `character-controller/`, `cinemachine/`, `dotween/`, `odin-inspector/`, `shader-graph/`, `textmeshpro/`, `ui-toolkit/`, `unitask/`, `vcontainer/`, `animation/`, `audio/`, `unity-instincts/`, `model-routing/`
- Modify (7 survivors, reference cleanup): `.claude/agents/unity-coder.md`, `unity-prototyper.md`, `unity-fixer.md`, `unity-ui-builder.md`, `unity-reviewer.md`, `.claude/commands/unity-workflow.md`, `.claude/commands/unity-doctor.md`
- Delete (6 orphaned templates): `.claude/templates/game-concept.md`, `systems-index.md`, `sprint-plan.md`, `architecture-decision-record.md`, `game-design-document.md`, `game-decision-record.md` — see "The emitters outside `.claude/`" below
- Modify (emitters): `scripts/generate-claude-md.sh`, `install.sh`, `CREDITS.md`, `MCP-SETUP.md`
- Modify: `provenance.tsv`, `provenance-skip.tsv`
- Separate commit: `migration/baseline-inventory.json`

**The emitters outside `.claude/` — added after the Task 1 review, and the most serious gap in this plan.**

This plan scoped the cut to `.claude/agents`, `.claude/commands` and `.claude/skills`, and never asked what points *at* those surfaces from outside that tree. The answer is that the toolkit's own installer does, and it writes those references **into every project it installs**:

- `scripts/generate-claude-md.sh:541-553` emits, into the generated `CLAUDE.md`, a "Where things go" block naming `docs/design/`, `docs/adr/` and `docs/production/` — the three directories field note §36 measured at zero use out of three — and a "How to work" section naming `/brainstorm`, `/map-systems`, `/design-system`, `/design-review`, `/sprint-plan`, `/estimate`, `/scope-check`, `/milestone-review`, `/retrospective` and five removed agents.
- `install.sh:600` ends the install with *"try /brainstorm, or /unity-audit for a health check"*. Both are removed — `/brainstorm` in Task 1, `/unity-audit` in this task.
- `CREDITS.md` and `MCP-SETUP.md` also name removed surfaces.

This is worse than stale documentation. The generated `CLAUDE.md` is **project instructions the model reads every session**, so a Kinglet-installed project would instruct the model to run commands that do not exist and to file work in directories nothing consumes. That is the exact defect class the smoke pass found three times and that this wave's spec exists to close.

**The reason Task 1's checks missed it** is worth carrying forward: its Step 1 and Step 6 grep only **path-form** references (`.claude/skills/<name>`) and only under `.claude/agents` and `.claude/commands`. That check structurally cannot see `/brainstorm`, cannot see a bare agent name, and never looks at `scripts/`, `install.sh` or `.claude/templates/` at all. Task 1's report saying "no dangling references" was true of the check it ran and false of the tree.

**The six templates are orphaned by the same omission.** Every one of `.claude/templates/*.md` had its producer removed in Task 1 — `/brainstorm`, `/map-systems`, `/design-system`, `/design-review`, `/sprint-plan`, and `technical-director`. Verified after Task 1: all six report zero producers among the surviving agents and commands. A template no surviving surface produces is dead payload, which is the same criterion that removed the surfaces themselves, so they go with them. Their `claude_templates` category count drops from 6 to 0.

- [ ] **Step 2b: Fix the emitters.**

`scripts/generate-claude-md.sh` — rewrite the "Where things go" and "How to work" sections so they name only surviving surfaces and directories. The design-track workflow chain is gone; what replaces it is the chain Task 5 builds (`deep-interview` → `/unity-workflow` → `/unity-review`). Keep the section short: this text lands in every user's `CLAUDE.md` and field note §87 measured that a precedence sentence naming a file changes behaviour while bulk changes none.

`install.sh:600` — the "Next steps" line must name surviving surfaces. `/unity-init` is the honest first step after an install, and `/unity-doctor` replaces `/unity-audit` as the health check.

`CREDITS.md` and `MCP-SETUP.md` — sweep for removed surface names and correct them. `CREDITS.md`'s MIT attribution to ECU and Donchitos is a standing obligation and does **not** change; only surface names do.

- [ ] **Step 2c: Verify nothing outside `.claude/` still names a removed surface.** This is the check Task 1 lacked — bare names, whole tree, excluding the git directory and the provenance manifests, which record removals on purpose.

```bash
cd "$(git rev-parse --show-toplevel)"
for dead in brainstorm design-review design-system map-systems sprint-plan estimate scope-check \
            milestone-review retrospective unity-audit unity-team unity-ralph unity-skillify \
            unity-instincts unity-learn unity-interview unity-build unity-migrate unity-network \
            unity-shader unity-profile unity-scout unity-linter unity-critic unity-verifier \
            unity-migrator unity-git-master unity-network-dev unity-security-reviewer \
            unity-shader-dev unity-build-runner unity-coder-lite unity-fixer-lite \
            creative-director game-designer level-designer narrative-director systems-designer \
            technical-director world-builder; do
  git grep -l -- "$dead" -- ':!provenance.tsv' ':!provenance-skip.tsv' ':!docs/' ':!.superpowers/' \
    2>/dev/null | while read -r f; do echo "STALE: $f -> $dead"; done
done
```

Expected: no output. `docs/` is excluded because Task 7 owns it; `provenance*.tsv` because recording what was removed is their job. Anything else that appears is a real emitter and must be fixed here, not deferred.

**Interfaces:**
- Consumes: Task 1's tree (20 agents, 27 commands, 30 skills).
- Produces: 8 agents, 11 commands, 10 skills. Tasks 4 and 5 consume this.

**The reference cleanup, measured on 2026-08-03.** `tests/test-skill-discovery.sh:119` only matches **path-form** references (`.claude/skills/<name>`). No surviving surface has a path-form reference to a removed skill — verified, the check returns empty. But nine surviving surfaces name removed skills in **bare form**, which no test catches and which would leave an agent instructed to load something that does not exist:

| File | Bare-name references to removed skills | Real or false positive |
|---|---|---|
| `.claude/agents/unity-coder.md:20-22` | `serialization-safety`, `scriptable-objects`, `event-systems` | **Real** — a "Skills to load" list |
| `.claude/agents/unity-prototyper.md:7,20` | `character-controller` (in the `skills:` frontmatter key *and* the body list) | **Real** — both occurrences |
| `.claude/agents/unity-fixer.md` | `serialization-safety` | **Real** |
| `.claude/agents/unity-ui-builder.md` | `textmeshpro`, `ui-toolkit` | **Real** |
| `.claude/agents/unity-reviewer.md` | `serialization-safety`, `event-systems` | **Real** |
| `.claude/commands/unity-workflow.md:65` | `model-routing` | **Real** |
| `.claude/commands/unity-workflow.md:51` | the words "animation? audio?" | **False positive** — prose naming Unity subsystems, not skills. Leave it. |
| `.claude/commands/unity-optimize.md` | the word "audio" | **False positive** — prose. Leave it. |
| `.claude/commands/unity-doctor.md:62-71` | `cinemachine`, `textmeshpro`, `dotween`, `unitask`, `vcontainer`, `odin-inspector` | **Real, and already broken** — see below |

**A pre-existing defect this task must not paper over.** `unity-doctor.md:62-71` maps Unity packages to skill paths using the **pre-flattening nested form** — `systems/cinemachine`, `third-party/dotween`, `third-party/unitask`. Skills have been flat at `.claude/skills/<name>/SKILL.md` since 2026-08-03; those paths have not resolved for some time and no test caught it, because the guard only matches paths beginning `.claude/skills/`. Removing the skills makes the mapping moot, so the fix here is to delete the mapping table, not to correct it to paths that are about to stop existing. Record this in the commit message — it is a finding, not just a cleanup.

- [ ] **Step 1: Delete the 48 surface files.** (The six orphaned templates go in Step 2b's commit alongside the emitter fixes, so the surface removal stays reviewable on its own.)

```bash
cd "$(git rev-parse --show-toplevel)"
git rm -q .claude/agents/unity-coder-lite.md .claude/agents/unity-fixer-lite.md \
  .claude/agents/unity-linter.md .claude/agents/unity-build-runner.md \
  .claude/agents/unity-critic.md .claude/agents/unity-git-master.md \
  .claude/agents/unity-migrator.md .claude/agents/unity-network-dev.md \
  .claude/agents/unity-scout.md .claude/agents/unity-security-reviewer.md \
  .claude/agents/unity-shader-dev.md .claude/agents/unity-verifier.md
git rm -q .claude/commands/unity-skillify.md .claude/commands/unity-skill-stocktake.md \
  .claude/commands/unity-instincts.md .claude/commands/unity-learn.md \
  .claude/commands/unity-sessions.md .claude/commands/unity-session-save.md \
  .claude/commands/unity-session-resume.md .claude/commands/unity-team.md \
  .claude/commands/unity-ralph.md .claude/commands/unity-audit.md \
  .claude/commands/unity-interview.md .claude/commands/unity-build.md \
  .claude/commands/unity-migrate.md .claude/commands/unity-network.md \
  .claude/commands/unity-shader.md .claude/commands/unity-profile.md
git rm -q -r .claude/skills/serialization-safety .claude/skills/event-systems \
  .claude/skills/scriptable-objects .claude/skills/commit-trailers \
  .claude/skills/hud-statusline .claude/skills/learner .claude/skills/navmesh \
  .claude/skills/character-controller .claude/skills/cinemachine .claude/skills/dotween \
  .claude/skills/odin-inspector .claude/skills/shader-graph .claude/skills/textmeshpro \
  .claude/skills/ui-toolkit .claude/skills/unitask .claude/skills/vcontainer \
  .claude/skills/animation .claude/skills/audio .claude/skills/unity-instincts \
  .claude/skills/model-routing
```

- [ ] **Step 2: Clean the seven surviving surfaces.**

`.claude/agents/unity-coder.md` — remove the three list entries `serialization-safety`, `scriptable-objects`, `event-systems` from its "Skills to load" block. Do not remove the block itself; `assembly-definitions` and `physics` survive and stay.

`.claude/agents/unity-prototyper.md` — remove `character-controller` from **both** the `skills:` frontmatter value on line 7 and the body list. The frontmatter value becomes `skills: physics, state-machine`. Preserve the key.

`.claude/agents/unity-fixer.md` — remove `serialization-safety` from its skills list.

`.claude/agents/unity-ui-builder.md` — remove `textmeshpro` and `ui-toolkit` from its skills list and from the `skills:` frontmatter key if they appear there.

`.claude/agents/unity-reviewer.md` — remove `serialization-safety` and `event-systems` from its skills list.

`.claude/commands/unity-workflow.md:65` — the line reads *"Assess complexity using the `model-routing` skill heuristics"*. Replace the skill reference with the heuristic stated inline, so the instruction survives the skill's removal:

```
3. **Assess complexity** — a single-file change with no new types is simple; a change
   introducing a new Model/System/View split, a new VContainer registration, or
   cross-system messaging is not. Route simple work directly; take non-trivial work
   through Plan and Verify.
```

`.claude/commands/unity-doctor.md:62-71` — delete the package-to-skill mapping table and the `DOTween`/`UniTask`/`VContainer`/`Odin` bullet list under it. Package **detection** stays if the command does anything else with it; only the mapping to skill paths goes.

**Leave `unity-workflow.md:51` and `unity-optimize.md` alone** — those are prose about Unity subsystems, not skill references.

- [ ] **Step 3: Move 54 provenance rows to the skip manifest** (48 surfaces + the 6 orphaned templates), same mechanics as Task 1 Step 3. Notes by group, verbatim:

- 3 speed variants (`unity-coder-lite`, `unity-fixer-lite`, `unity-linter`): `speed variant removed 2026-08-03; twins an existing surface on a cost axis, doubling the selection pool with nothing to discriminate on`
- 9 specialists: `specialist removed 2026-08-03; surface cut to 32 on the criterion that a surface survives only if it does something the model cannot do unaided`
- 16 commands: `removed 2026-08-03 with its agent, or as toolkit self-reference; see the surface cut design`
- 3 rule duplicates (`serialization-safety`, `event-systems`, `scriptable-objects`): `duplicates an auto-loading rule; the serialization probe answered from .claude/rules/serialization.md and the skill was never invoked`
- 17 remaining skills: `removed 2026-08-03; orphaned, package-conditional, or toolkit self-reference`

Since the seven surviving files were edited, flip each of their `provenance.tsv` rows to `status=modified` with a note in the same commit if they are currently `verbatim`. Check first:

```bash
grep -E 'unity-(coder|prototyper|fixer|ui-builder|reviewer)\.md|unity-(workflow|doctor)\.md' provenance.tsv \
  | cut -f1,6
```

- [ ] **Step 4: Verify no dangling references.**

```bash
for s in $(grep -rhoE '\.claude/skills/[A-Za-z0-9_-]+' .claude/agents .claude/commands 2>/dev/null \
           | sed 's|.claude/skills/||' | sort -u); do
  [ -f ".claude/skills/$s/SKILL.md" ] || echo "DANGLING PATH: $s"
done
```

Expected: no `DANGLING PATH` output.

- [ ] **Step 5: Confirm the counts.**

```bash
echo "agents=$(ls .claude/agents/*.md | wc -l) commands=$(ls .claude/commands/*.md | wc -l) skills=$(ls -d .claude/skills/*/ | wc -l)"
```

Expected exactly: `agents=8 commands=11 skills=10`. If any number differs, a file was missed or over-deleted — stop and report which.

- [ ] **Step 6: Suite and provenance green.**

```bash
bash tests/run-tests.sh > /tmp/t2.log 2>&1; echo "exit=$?"
grep -c -- '--- test-' /tmp/t2.log; ls tests/test-*.sh | wc -l
bash scripts/check-provenance.sh
```

- [ ] **Step 7: Commit.**

```bash
git add -A .claude provenance.tsv provenance-skip.tsv
git commit -m "feat(cut): remove the remaining 48 surfaces, clean survivor references

12 agents, 16 commands, 20 skills. Pool is now 8/11/10 = 29 surfaces
before the process layer adds 3.

Seven surviving surfaces named removed skills in bare form, which
test-skill-discovery.sh does not catch (it matches path-form refs only).
Cleaned.

Finding: unity-doctor.md mapped packages to skill paths in the
PRE-FLATTENING nested form (systems/cinemachine, third-party/dotween).
Those paths have not resolved since skills were flattened and no test
caught it, for the same reason. Table deleted rather than corrected,
since the skills it points at are removed here."
```

- [ ] **Step 8: Baseline, own commit.** 54 files removed. Templates are recorded in `full_claude_tree` and in `categories.claude_templates`, agents/commands/skills likewise, so the expected removal count is **108** — but confirm with `--dry-run` before writing, and if the tool disagrees, report its output rather than tuning the number. Use the flags Task 0 added:

```bash
python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD \
    --expect-drift 0 --expect-removed 108 --expect-added 0 --dry-run
```

Superseded text follows for reference only — 48 files removed = drift **96**. Seven files were edited, not removed; confirm with `--dry-run` whether edits register as drift in this tool before assuming 96 is complete:

```bash
python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift 96 --dry-run
```

If the reported number is not 96, **stop and report it with the tool's actual output** rather than retrying with the reported number — a mismatch here means content edits also drift the baseline, which changes the prediction for every later task in this plan.

Then, with the confirmed number `N`:

```bash
python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift N
git add migration/baseline-inventory.json
git commit -m "chore(baseline): record the surface cut"
```

---

### Task 3: Guard bare-name skill references

Today's measurement found nine surviving surfaces naming skills in bare form, invisible to every test. Task 2 cleaned them by hand; nothing stops the next edit from reintroducing one.

**Files:**
- Create: `tests/test-surface-references.sh`
- Modify: `provenance.tsv` (one new row, `origin=original`, `status=original`)
- Separate commit: none — `tests/` is not under `.claude/`, so no baseline drift.

**Interfaces:**
- Consumes: Task 2's tree (8 agents, 11 commands, 10 skills).
- Produces: nothing later tasks depend on, but it must stay green through Tasks 4-7.

This test is **runner-provided**: it uses the runner's `assert_eq` and `$REPO_DIR` and defines neither. `bash tests/test-surface-references.sh` standalone **exits 0 having asserted nothing** — the helpers are undefined and the file sets no `-e`. Run it through `tests/run-tests.sh` and read its section. This is not a style preference; a plan written on 2026-08-03 told an implementer to verify a check by running a runner-provided file standalone, and it would have reported a pass in both directions.

- [ ] **Step 1: Write the guard.**

```bash
#!/usr/bin/env bash
#
# test-surface-references.sh — an agent or command must not name a skill that does not exist.
#
# tests/test-skill-discovery.sh already checks PATH-FORM references (`.claude/skills/<name>`).
# It does not catch a bare name in a "Skills to load" list or a `skills:` frontmatter value,
# and on 2026-08-03 nine surviving surfaces carried exactly that after a cut. An agent told to
# load a skill that is not there gets no error of any kind — it just silently loads nothing.
#
# Runner-provided: uses the runner's assert_eq and $REPO_DIR. Run through tests/run-tests.sh.

echo "--- surface references ---"

SKILL_NAMES=$(ls -1 "$REPO_DIR/.claude/skills" 2>/dev/null | sort)

# Collect every bare name that appears either in a `skills:` frontmatter value or as a
# backticked list item in a "Skills to load" block, then report the ones with no directory.
BAD_REFS=$(
  for f in "$REPO_DIR"/.claude/agents/*.md "$REPO_DIR"/.claude/commands/*.md; do
    [ -f "$f" ] || continue
    awk -v file="$f" '
      # `skills: a, b, c` in frontmatter
      /^skills:[[:space:]]/ {
        line = $0
        sub(/^skills:[[:space:]]*/, "", line)
        n = split(line, parts, /[[:space:]]*,[[:space:]]*/)
        for (i = 1; i <= n; i++) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
          if (parts[i] != "") print file "\t" parts[i]
        }
      }
      # a backticked bare name on its own list line: "- `name`"
      /^[[:space:]]*-[[:space:]]*`[A-Za-z0-9_-]+`[[:space:]]*$/ {
        line = $0
        gsub(/[^A-Za-z0-9_`-]/, "", line)
        gsub(/`/, " ", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        sub(/^-+/, "", line)
        if (line != "") print file "\t" line
      }
    ' "$f"
  done | sort -u | while IFS="$(printf '\t')" read -r src name; do
    [ -n "$name" ] || continue
    if [ ! -d "$REPO_DIR/.claude/skills/$name" ]; then
      printf '%s names missing skill: %s\n' "${src#$REPO_DIR/}" "$name"
    fi
  done
)

if [ -n "$BAD_REFS" ]; then
  printf '%s\n' "$BAD_REFS"
fi
assert_eq "$(printf '%s' "$BAD_REFS" | grep -c . || true)" "0" \
  "no agent or command names a skill that does not exist"
```

Note the constraints this obeys: no `grep -oP`, no `declare -A`, no pipe into an early-exiting reader (`grep -c` drains its input), and `$SKILL_NAMES` is computed but the existence check uses a direct `-d` test rather than a substring match, so a skill named `physics` does not mask a missing `physics-2d`.

- [ ] **Step 2: Watch it fail before trusting it.** A guard written after the fix and never seen to fail is decoration. Reintroduce one bad reference in a scratch worktree and confirm the guard names the file:

```bash
cd "$(git rev-parse --show-toplevel)"
git worktree add -q /tmp/guard-probe HEAD
printf -- '- `character-controller`\n' >> /tmp/guard-probe/.claude/agents/unity-coder.md
( cd /tmp/guard-probe && bash tests/run-tests.sh 2>&1 | grep -A3 'surface references' )
```

Expected: the run reports `unity-coder.md names missing skill: character-controller` and the suite fails. If it passes, the guard is not matching the list form actually used in these files — read `.claude/agents/unity-coder.md`'s block and fix the awk pattern to match it before continuing.

```bash
git worktree remove --force /tmp/guard-probe
```

- [ ] **Step 3: Run it clean against the real tree.**

```bash
bash tests/run-tests.sh > /tmp/t3.log 2>&1; echo "exit=$?"
grep -A3 'surface references' /tmp/t3.log
grep -c -- '--- test-' /tmp/t3.log; ls tests/test-*.sh | wc -l
```

Expected: the guard's section passes, exit 0, and the header count matches the file count — the new file must appear.

- [ ] **Step 4: Add its provenance row and commit.**

The row is tab-separated: `tests/test-surface-references.sh`, `original`, `-`, `-`, `-`, `original`, `guards bare-name skill references; test-skill-discovery.sh matches path-form only`. Match the placeholder convention used by existing `origin=original` rows:

```bash
grep -P '\toriginal\t' provenance.tsv | head -2   # if grep -P is unavailable, use: awk -F'\t' '$2=="original"' provenance.tsv | sed -n 1,2p
```

```bash
git add tests/test-surface-references.sh provenance.tsv
git commit -m "test(surfaces): guard bare-name skill references

test-skill-discovery.sh matches path-form refs only. Nine surviving
surfaces carried bare-name refs to removed skills after the cut, and
no test saw them. An agent told to load a missing skill gets no error.

Seen to fail before being trusted."
```

---

### Task 4: Transcribe the trigger descriptions

In Claude Code a surface is selected from its `description` frontmatter and nothing else. `docs/superpowers/specs/2026-07-30-surface-trigger-rules.md` contains finished, differentiated descriptions written in one sitting so ties were visible on one page. It was Task 2 of Wave 1b-2; Task 3 — transcribing them — never ran. Verified 2026-08-03: zero of 36 commands carry the designed text.

**Transcribe, do not re-derive.** The hard work is done and re-deriving it one file at a time is how five descriptions written on five different days collide.

**Files:**
- Modify: 8 agents and 11 commands under `.claude/`
- Modify: `provenance.tsv` (flip edited rows to `status=modified`)
- Separate commit: `migration/baseline-inventory.json`

**Interfaces:**
- Consumes: Task 2's tree.
- Produces: the descriptions Task 7's re-measurement tests.

**Sixteen come from the rules document verbatim.** Read `docs/superpowers/specs/2026-07-30-surface-trigger-rules.md` and copy the proposed description for: `/unity-feature` and `unity-coder` (§2), `/unity-prototype` and `unity-prototyper` (§2), `/unity-fix` and `unity-fixer` (§3), `/unity-review` and `unity-reviewer` (§4), `/unity-optimize` and `unity-optimizer` (§5), `/unity-test` and `unity-test-runner` (§6), `/unity-ui` and `unity-ui-builder` (§9), `/unity-scene` and `unity-scene-builder` (§9).

**Three clauses name surfaces that no longer exist and must be dropped during transcription:**

1. `/unity-fix` — the designed text ends *"Routes to deep investigation by default, or a quick path for obviously simple fixes."* `unity-fixer-lite` is removed. Drop the trailing clause; the sentence ends at *"...rather than guessing."*
2. `/unity-feature` — ends *"Routes to the full architectural implementer by default, or a lighter/faster path for simple additions."* `unity-coder-lite` is removed. Replace with *"Routes to the architectural implementer, which writes the C# and wires it into the scene."*
3. `/unity-review` — ends *"at standard depth by default, or opus-level architectural depth on request."* That second depth was `unity-verifier`/`unity-critic`, both removed. Drop the clause; the sentence ends at *"...performance, architecture."*

`unity-optimizer`'s designed text says *"Invoked by both `/unity-optimize` (fix a known complaint) and `/unity-profile` (measure first)"*. `/unity-profile` is removed; replace that clause with *"Invoked by `/unity-optimize`"*.

`unity-coder`'s *"not a one-line change"* stays — it discriminates against triviality generally, not only against the removed `unity-coder-lite`.

**Three have no designed text and are written here, in the same house style** — state when it applies, in the user's words, then what it does:

`/unity-workflow`
> "Use when the user wants a feature taken all the way through — clarified, planned, implemented and verified — rather than a single step, or when they hand over a written plan to execute. Prefer `/unity-feature` when the request is one scoped addition that needs no plan."

`/unity-init`
> "Use once per project, right after Kinglet is installed — when `CLAUDE.md` still has unfilled `FILL:` markers, or when the user asks to set up or initialise the toolkit for this Unity project."

`/unity-doctor`
> "Use when the user asks whether the setup is correct, reports that Kinglet or the Unity MCP bridge is not working, or wants to check the install before trusting it on a new machine. Reports what is wrong rather than changing anything."

- [ ] **Step 1: Rewrite the eight agent descriptions.** Edit only the first `description:` inside the first `---` block. Preserve `model`, `color`, `tools`, and the `skills:` key where present.

- [ ] **Step 2: Rewrite the eleven command descriptions.** Same rule. Preserve `name`, `user-invocable`, `args`.

- [ ] **Step 3: Confirm every description changed and none of the frontmatter was lost.**

```bash
cd "$(git rev-parse --show-toplevel)"
for f in .claude/agents/*.md .claude/commands/*.md; do
  d=$(awk '/^---/{n++} n==1 && /^description:/{print; exit}' "$f")
  case "$d" in *"Use "*) ;; *) echo "NOT TRIGGER-PHRASED: $f -- $d" ;; esac
done
```

Expected: no output. Every one of the 19 descriptions should contain the word `Use`, because every designed description opens with "Use when" or "Use for" or "Use to".

- [ ] **Step 4: Confirm no description names a removed surface.**

```bash
for dead in unity-coder-lite unity-fixer-lite unity-linter unity-verifier unity-critic unity-profile; do
  grep -l -- "$dead" .claude/agents/*.md .claude/commands/*.md 2>/dev/null \
    | while read -r f; do echo "STALE REF: $f -> $dead"; done
done
```

Expected: no output. A description that disambiguates against a surface the user cannot reach is dead text pointing at nothing.

- [ ] **Step 5: Flip provenance rows** for all 19 edited files to `status=modified`, note `trigger-condition description transcribed from the 2026-07-30 surface-trigger-rules spec`. Rows already `modified` keep that status; update the note.

- [ ] **Step 6: Suite, provenance, commit.**

```bash
bash tests/run-tests.sh > /tmp/t4.log 2>&1; echo "exit=$?"
grep -c -- '--- test-' /tmp/t4.log; ls tests/test-*.sh | wc -l
bash scripts/check-provenance.sh
git add -A .claude provenance.tsv
git commit -m "feat(triggers): transcribe trigger-condition descriptions to the 19 survivors

A surface is selected from its description and nothing else. Ours said
what they do; the description that beat us said when it applies.

Text comes from the 2026-07-30 surface-trigger-rules spec, which
designed all of these in one sitting and was never transcribed. Four
clauses disambiguating against now-removed surfaces were dropped;
/unity-workflow, /unity-init and /unity-doctor had no designed text and
were written in the same house style."
```

- [ ] **Step 7: Baseline, own commit.** Predict with `--dry-run` first; 19 files edited, so expect **38** if content edits drift the baseline, or **0** if only path-set changes do. Task 2 Step 8 will have already established which. Use the confirmed behaviour, and stop and report if the tool disagrees.

---

### Task 5: Add the process chain

Superpowers' value is not its individual skills; it is that each names the next, and an always-loaded entry skill establishes that a process surface is chosen before code is written. Kinglet has most pieces scattered inside `unity-workflow`'s phases and lacks the linkage.

**Files:**
- Create: `.claude/skills/using-kinglet/SKILL.md`
- Create: `.claude/skills/systematic-debugging/SKILL.md`
- Create: `.claude/skills/verification-before-completion/SKILL.md`
- Create: `.claude/hooks/session-brief.sh`
- Modify: `.claude/skills/deep-interview/SKILL.md` (add the handoff)
- Modify: `.claude/settings.json` (register the `SessionStart` hook)
- Modify: `provenance.tsv` (4 new `origin=original` rows, plus flips for the two edited files)
- Separate commit: `migration/baseline-inventory.json`

**Interfaces:**
- Consumes: Task 4's tree with trigger descriptions in place.
- Produces: `.claude/hooks/session-brief.sh`, invoked by `settings.json`'s `SessionStart` matcher `startup|clear|compact`, printing the contents of `.claude/skills/using-kinglet/SKILL.md` on stdout.

**Keep `using-kinglet` short.** Field note §87 measured that deleting an entire rule file changed none of twelve runs, while one precedence sentence naming that file changed all of them. Size is not influence, and this file is read every session.

- [ ] **Step 1: Write `.claude/skills/using-kinglet/SKILL.md`.**

```markdown
---
name: using-kinglet
description: "Use at the start of every session in a Unity project — establishes which Kinglet surface handles which situation, and that a process surface is chosen before code is written."
---

# Using Kinglet

Kinglet is a Unity 6 PC/console toolkit. Five rules in `.claude/rules/` load automatically and
bind: `architecture.md`, `csharp-unity.md`, `performance.md`, `serialization.md`,
`unity-specifics.md`. `pc-console.md` adds platform specifics on top; it does not override them.

**Which of those rules apply to this project is stated in `CLAUDE.md`'s generated block.** It is
detected from the project's own code, not assumed. Read it before asserting that a rule binds.

## The chain

| Situation | Surface |
|---|---|
| The request is vague and has no file, type, or acceptance criterion | `deep-interview` — ask, do not guess |
| A feature, taken end to end, or an existing written plan to execute | `/unity-workflow` |
| One scoped addition to code that already exists | `/unity-feature` |
| A mechanic to try, in a new throwaway scene | `/unity-prototype` |
| Something is broken and the cause is not yet known | `systematic-debugging`, then `/unity-fix` |
| Code was just written and is not yet verified | `verification-before-completion`, then `/unity-review` or `/unity-test` |
| A performance complaint, or a "how is performance" check | `/unity-optimize` |
| A UI screen, or a scene to build | `/unity-ui`, `/unity-scene` |
| The setup itself may be wrong | `/unity-doctor` |

A question that the rules already answer needs no surface. Answer it.

## Offer the next step

When a unit of work finishes, name what would sensibly come next and offer it — a review after an
implementation, a test after a fix, a profile after an optimisation. **Offer; do not act.** Starting
a review nobody asked for is worse than waiting to be asked.
```

- [ ] **Step 2: Write `.claude/skills/systematic-debugging/SKILL.md`.**

```markdown
---
name: systematic-debugging
description: "Use when something in Unity is broken and the cause is not yet known — before proposing a fix. Establishes the order: read the real console, reproduce, inspect the live API, then change one thing."
---

# Systematic Debugging — Unity

A fix proposed from memory is a guess. Unity's failures are disproportionately lifecycle and
identity problems that reading the code does not reveal.

## Order

1. **Read the real console.** `mcp__UnityMCP__read_console`. Not the code, not your recollection of
   what the code does — the actual error, with its stack. If the bridge is not running, say so and
   stop rather than substituting a guess.
2. **Reproduce, and say how.** A bug you cannot trigger is a bug you cannot confirm you fixed.
3. **Inspect the live API before assuming it.** `mcp__UnityMCP__unity_reflect` reports what the
   installed Unity and packages actually expose. Recalled API surface goes stale between versions.
4. **Change one thing.** Then re-read the console. Two changes at once means you learn nothing from
   the result.

## The Unity-specific causes to rule out early

- **`?.` and `is null` on a UnityEngine.Object.** Unity overrides `==` to report destroyed objects
  as null; `?.` and `is null` use C# reference equality and do not. Calls land on destroyed objects.
- **Lifecycle order.** `Awake` order across objects is not defined. `Start` never runs on an object
  that is never enabled. `OnDisable` runs before `OnDestroy`.
- **A renamed serialized field with no `[FormerlySerializedAs]`.** Values silently reset to default
  across every scene, prefab and ScriptableObject. Nothing warns.
- **An editor-only API used in runtime code without `#if UNITY_EDITOR`.** Compiles in the Editor,
  fails at build.
- **Input that never arrives** because an action map was never `Enable()`d in `OnEnable`.

## When it is fixed

Hand off to `verification-before-completion`. A fix you have not re-run is a hypothesis.
```

- [ ] **Step 3: Write `.claude/skills/verification-before-completion/SKILL.md`.**

```markdown
---
name: verification-before-completion
description: "Use before reporting any code change as done — establishes what counts as evidence that it works, and that a claim without evidence is not a completion."
---

# Verification Before Completion

**A documentation layer is worth what its verification is worth. If only one of the two ships, ship
the test.** That is a measured conclusion, not a preference: on the only real project this toolkit
has met, 17,316 lines of documentation were produced and three of its directories were read zero
times, while the tests were read every time.

## What counts as evidence

| Claim | Evidence |
|---|---|
| "It compiles" | `mcp__UnityMCP__read_console` shows no errors after a refresh |
| "It works" | A test that fails without the change and passes with it, run via `/unity-test` |
| "The bug is fixed" | The reproduction from `systematic-debugging` no longer reproduces |
| "It is faster" | Profiler frames before and after, via `/unity-optimize` |
| "It follows the rules" | `/unity-review` ran and reported clean |

## Rules

- **Report what actually happened.** If tests fail, say so and show the output. If a step was
  skipped, say which. A green claim over a red run is the most expensive thing you can write.
- **A test that asserts nothing passes.** Watch a new test fail before trusting it.
- **Manual Editor steps are not done because you described them.** If the change needs a sprite
  atlas, a lightmap bake, or an import setting the agent cannot create, stop and say so explicitly
  rather than writing code that assumes it exists.

## When there is nothing left to verify

Say what was built, what was verified and how, and what still needs a human. Then offer the next
step — do not take it.
```

- [ ] **Step 4: Add the handoff to `deep-interview`.** Keep its existing activation logic (specificity signals, exemptions, ambiguity score) unchanged — it is sound. Append this section at the end of the file:

```markdown
## Handoff

- **Gate passes** (requirements are clear enough): hand off to `/unity-workflow` for anything
  needing a plan, or `/unity-feature` for one scoped addition. Say which and why.
- **Gate fails** (still ambiguous): ask the specific questions the score identified, and **stop**.
  Do not proceed on an assumption and do not answer your own question.
```

- [ ] **Step 5: Write `.claude/hooks/session-brief.sh`.**

```bash
#!/usr/bin/env bash
#
# session-brief.sh — inject the using-kinglet skill at session start.
#
# Carries the chain and the proactive posture, NOT surface selection: selection comes from each
# surface's own description frontmatter. This is the mechanism Superpowers uses, run from the
# project's own .claude/settings.json rather than from a plugin.
#
# Prints nothing and exits 0 when the skill is absent — a session must never fail to start because
# a brief is missing.
set -euo pipefail

SKILL_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/skills/using-kinglet/SKILL.md"

[ -f "$SKILL_FILE" ] || exit 0

# cat, not a pipeline: nothing downstream here can exit early, and the file is small.
cat "$SKILL_FILE"
```

Make it executable: `chmod +x .claude/hooks/session-brief.sh`

- [ ] **Step 6: Register the hook in `.claude/settings.json`.** Read the file first — it already contains hook registrations, and this adds a `SessionStart` entry alongside whatever is there. Do **not** overwrite existing entries; `session-restore.sh` is already registered on `SessionStart` and must keep running.

```json
{
  "matcher": "startup|clear|compact",
  "hooks": [
    { "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/session-brief.sh\"" }
  ]
}
```

- [ ] **Step 7: Verify the hook runs and emits the brief.**

```bash
cd "$(git rev-parse --show-toplevel)"
CLAUDE_PROJECT_DIR="$PWD" bash .claude/hooks/session-brief.sh | head -5
```

Expected: the first lines of `using-kinglet/SKILL.md`. Then confirm the absent-file path is silent:

```bash
CLAUDE_PROJECT_DIR=/nonexistent bash .claude/hooks/session-brief.sh; echo "exit=$?"
```

Expected: no output, `exit=0`.

- [ ] **Step 8: Confirm the new skills satisfy the discovery rules.** Each must sit at `.claude/skills/<name>/SKILL.md`, have `name:` matching its directory, a non-empty `description:`, and **no** `alwaysApply` or `globs` keys (both are inert Cursor keys that get read as guarantees).

```bash
bash tests/run-tests.sh > /tmp/t5.log 2>&1; echo "exit=$?"
grep -A5 'skill discovery' /tmp/t5.log
grep -c -- '--- test-' /tmp/t5.log; ls tests/test-*.sh | wc -l
```

- [ ] **Step 9: Add provenance rows and commit.** Four new `origin=original`, `status=original` rows for the three skills and the hook; flip `deep-interview`'s and `settings.json`'s rows to `modified`.

```bash
bash scripts/check-provenance.sh
git add -A .claude provenance.tsv
git commit -m "feat(chain): add the process chain — using-kinglet, systematic-debugging, verification-before-completion

Superpowers' contribution is the chain and the entry point, not the
individual skills. Kinglet had the pieces inside unity-workflow's
phases and no linkage.

session-brief.sh injects using-kinglet at SessionStart from the
project's own settings.json — no plugin needed; a project hook is read
exactly as a plugin's is. Its job is the chain and the proactive
posture. Selection is the descriptions' job (Task 4)."
```

- [ ] **Step 10: Baseline, own commit.** Four files added plus two edited. Predict with `--dry-run` using the drift behaviour Task 2 confirmed, and stop and report on any disagreement.

---

### Task 6: Proactive next-step suggestion

Trigger descriptions get a surface selected when the user asks for something. They say nothing about what happens when the user stops asking. This is the half that makes a small pool usable without memorising names.

**Files:**
- Modify: 11 commands under `.claude/commands/` (append a section to each body)
- Modify: `provenance.tsv` (notes on the 11 rows)
- Separate commit: `migration/baseline-inventory.json`

**Interfaces:**
- Consumes: Task 5's tree, where `using-kinglet` already states the posture once.
- Produces: nothing later tasks depend on.

The posture is stated once in `using-kinglet` (Task 5, Step 1). This task puts the concrete next step in each command's body, where the model reads it mid-task. **Body text, not frontmatter** — this is instruction during work, not selection metadata.

**The boundary is offer, not act.** The toolkit already ships hooks that block; an assistant that silently starts a review after every edit is worse than one that waits.

- [ ] **Step 1: Append a `## Suggest next` section to each of the eleven commands**, using these pairings:

| Command | Section content |
|---|---|
| `/unity-workflow` | Already verifies in Phase 4. Offer `/unity-test` if no test was written, and say plainly what still needs a human. |
| `/unity-feature` | Offer `/unity-review` on the code just written; offer `/unity-test` if the feature has behaviour worth pinning. |
| `/unity-prototype` | Offer `/unity-feature` to move the mechanic into the real project, once the prototype proves it. |
| `/unity-fix` | Offer `/unity-test` to pin the bug so it cannot come back. State the reproduction that no longer reproduces. |
| `/unity-review` | If findings were reported, offer to fix them. Do not fix them unasked. |
| `/unity-test` | If any test fails, report the output and stop — do not offer anything else until it is green. |
| `/unity-optimize` | Offer a second profile pass to confirm the gain is real, with before/after frames. |
| `/unity-ui` | Offer `/unity-review` — UI code is where Canvas rebuild and raycast-target faults land. |
| `/unity-scene` | Offer `/unity-prototype` or `/unity-feature` depending on whether the scene is throwaway. |
| `/unity-init` | Offer `/unity-doctor` to confirm the install, and name the `FILL:` markers still unfilled in `CLAUDE.md`. |
| `/unity-doctor` | If anything is wrong, offer the specific fix. Report; do not change anything on your own. |

Use this shape, with the row's content substituted:

```markdown
## Suggest next

When this command finishes, name the next step and offer it. Do not take it.

<the row's content>
```

- [ ] **Step 2: Confirm every command carries the section.**

```bash
cd "$(git rev-parse --show-toplevel)"
for f in .claude/commands/*.md; do
  grep -qF -- '## Suggest next' "$f" || echo "MISSING: $f"
done
```

Expected: no output, and 11 files present.

- [ ] **Step 3: Confirm no `Suggest next` section names a removed surface.**

```bash
for dead in unity-profile unity-critic unity-verifier unity-linter design-review unity-audit; do
  grep -l -- "$dead" .claude/commands/*.md 2>/dev/null \
    | while read -r f; do echo "STALE: $f -> $dead"; done
done
```

Expected: no output.

- [ ] **Step 4: Suite, provenance, commit, baseline.**

```bash
bash tests/run-tests.sh > /tmp/t6.log 2>&1; echo "exit=$?"
grep -c -- '--- test-' /tmp/t6.log; ls tests/test-*.sh | wc -l
bash scripts/check-provenance.sh
git add -A .claude provenance.tsv
git commit -m "feat(suggest): offer the next step from every command

Descriptions get a surface selected when the user asks. They say
nothing about what happens when the user stops asking, and that is the
half that makes a 32-surface pool usable without memorising names.

Offer, do not act."
```

Then regenerate the baseline in its own commit, predicting with `--dry-run` first.

---

### Task 7: Correct the repo's documentation and re-run the measurement

The whole wave is a hypothesis until this runs. And `CLAUDE.md` currently describes a provenance contract the repo will no longer honour — leaving it is the exact defect class the smoke pass found three times (defects 1, 2 and 4: *the documentation asserts something the code does not do*).

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/research/pioneer/smoke-pass.md` (append a new dated section — do **not** edit §4 or §10)
- Modify: `MERGE-NOTES.md`
- Modify: `docs/ARCHITECTURE.md`, `docs/SKILL-CATALOG.md`, `README.md` (see Step 2b)

**Interfaces:**
- Consumes: the finished tree from Tasks 1-6.

- [ ] **Step 1: Correct `CLAUDE.md`'s provenance section.** It currently says the manifest is *"the only thing that makes a future diff against a newer ECU tractable rather than archaeological."* After this wave nearly every row is `modified`, so `--online` verifies almost nothing. Replace the rationale with what is now true:

> Kinglet's surfaces are no longer vendored copies. `origin` records where a file came from and is a
> standing MIT obligation; `status` is now `modified` or `original` for nearly every row, because the
> surfaces have been rewritten for an agent reader. `--online` therefore verifies little and the
> diff-tractability it once provided has been deliberately traded away. **The offline half is what
> matters now**: no rows without files, no files without rows, and every `rule=absent` path stays
> absent. That is what keeps a removed surface from silently returning.

- [ ] **Step 2: Correct `CLAUDE.md`'s surface counts.** It describes the toolkit's composition; update any count that the cut invalidated, and add the two facts a future maintainer needs:

- the surface pool is 32 by design, cut on the criterion *a surface survives only if it does something the model cannot do unaided*;
- `tests/test-surface-references.sh` guards bare-name skill references, because `tests/test-skill-discovery.sh` matches path-form only — and that gap shipped nine dangling references on 2026-08-03.

Do **not** write a hardcoded test-file or assertion count into `CLAUDE.md`. It has gone stale twice, and the file already says so.

- [ ] **Step 2b: Refresh the three documents nothing guards.** These carry surface counts and surface names that the cut invalidates, and no test protects any of them — so they go stale silently, which is the defect class the spec exists to avoid.

`docs/ARCHITECTURE.md` — line 28 reads `skills/            39 knowledge modules in 5 categories`. **Both halves are wrong**: the count, and "5 categories", which has been false since skills were flattened to `.claude/skills/<name>/SKILL.md`. Correct both. Line 65 names `unity-scout` and `unity-linter` as the Haiku agents; both are removed, and no surviving agent runs on Haiku — remove that model tier's bullet rather than renaming it to a surface that does not exist. Sweep the whole file for other removed surface names.

`docs/SKILL-CATALOG.md` — line 9 reads `39 skills, one directory each at ...`. Correct the count to 13 and drop the catalog rows for removed skills. Its `## Skills That Formerly Carried alwaysApply: true` section must survive: it records that `alwaysApply` is inert, which was measured in Wave 1b-2 Task 1 and is still true. Add rows for the three skills Task 5 created.

`README.md` — lines 77-78 hold a surface table (`Agents | 28`, `Commands | 36`). Update to the post-cut numbers, and check line 50's sentence about the `unity-*` surfaces not being invoked in a measured session — Task 7 Step 5 re-measures exactly that, so it must agree with the new result, not the old one.

Verify no removed surface name survives in any of the three:

```bash
cd "$(git rev-parse --show-toplevel)"
for dead in unity-scout unity-linter unity-verifier unity-critic unity-migrator unity-git-master \
            unity-security-reviewer unity-shader-dev unity-build-runner unity-network-dev \
            unity-coder-lite unity-fixer-lite design-review sprint-plan; do
  grep -l -- "$dead" docs/ARCHITECTURE.md docs/SKILL-CATALOG.md README.md 2>/dev/null \
    | while read -r f; do echo "STALE: $f -> $dead"; done
done
```

Expected: no output.

- [ ] **Step 3: Record the wave in `MERGE-NOTES.md`** — what was taken, adapted, and now cut, with the evidence for each group. This is the build record; a 74-surface removal that is not in it makes the next maintainer excavate.

- [ ] **Step 4: Install into a fresh fixture.**

```bash
cd "$(git rev-parse --show-toplevel)"
bash tests/fixtures/mkproject.sh /tmp/cut-probe --variant urp
bash install.sh --project-dir /tmp/cut-probe
```

- [ ] **Step 5: Run smoke-pass §10's three prompts with the competitor ENABLED.** §10 won them only by disabling Superpowers at project scope. Winning with it enabled is the honest proof; anything less is winning by removing the opponent. Confirm the competitor is enabled before probing — check `/tmp/cut-probe/.claude/settings.json` has no `enabledPlugins` entry disabling it.

```bash
cd /tmp/cut-probe
for p in "Let's add a double jump to the player." \
         "The enemy AI keeps walking through walls, can you fix it?" \
         "I want to check this project for performance problems."; do
  printf '%s' "$p" | timeout 500 claude -p --model sonnet --output-format stream-json --verbose \
    --disallowed-tools Edit Write NotebookEdit >> /tmp/cut-probe.jsonl 2>&1
done
```

Extract the tool-call stream from `/tmp/cut-probe.jsonl` and **record what was selected, whatever it was.**

- [ ] **Step 6: Run the regression probe.** The serialization question must still select **nothing** — the rule answers it, and a surface being selected for a question a rule already answers is a regression, not a win.

```bash
cd /tmp/cut-probe
printf '%s' "I need to rename a serialized field on a MonoBehaviour from _speed to _moveSpeed. What do I have to be careful about?" \
  | timeout 300 claude -p --model sonnet --output-format stream-json --verbose > /tmp/cut-regress.jsonl 2>&1
```

Expected: zero tool calls, correct answer from `.claude/rules/serialization.md`.

- [ ] **Step 7: Write the results into `smoke-pass.md` as a new dated section**, beside §4 and §10. Do not edit either: the record of the failure is what makes the fix meaningful.

- [ ] **Step 8: If a Kinglet surface still is not selected in Step 5, say so plainly and stop.** That is a real result — it means trigger phrasing is insufficient against a well-tuned competitor — not a bad run. Report it and let the controller decide. **Do not retry with a friendlier prompt**; the prompt is the measurement, and changing it to get a better answer is fabricating a pass.

- [ ] **Step 9: Commit.**

```bash
git add CLAUDE.md MERGE-NOTES.md docs/research/pioneer/smoke-pass.md
git commit -m "docs: correct the provenance contract and record the re-measurement

CLAUDE.md described a contract the repo no longer honours: with nearly
every row now 'modified', --online verifies little and the
diff-tractability it claimed is deliberately traded away. The offline
half is what carries the weight now.

Records the measurement this whole wave is a hypothesis until."
```

---

## What this plan does not do

| Deferred | Why |
|---|---|
| Plugin packaging, marketplace, `/plugin update` | Dropped in the spec. The team is multi-client; a Claude Code plugin serves one of them. A project-installed `.claude/` reaches all of them and enters the same registry. |
| Making re-installation safe over user customisation | Observed 2026-08-03: a second install into Endless Evolution overwrote a customised hook and a `settings.json` key, recovered by hand. Must be fixed before the toolkit is handed to anyone else — but it is a prerequisite for the install-by-prompt entry path, not for this cut. |
| A tagged release | `main` carried a field-broken commit for part of 2026-08-03. Not safe to say "install from `main`" until a tag names a known-good state. |
| Re-adding package-conditional skills behind detection | `generate-claude-md.sh` already detects packages; wiring cut skills back in on detection is additive and separate. |

## Self-review

**Spec coverage.** Decision 1 (the cut) → Tasks 1-2. Decision 2 (provenance re-basing) → Tasks 1, 2, 5 for the rows and Task 7 Step 1 for the documentation. Decision 3 (trigger descriptions) → Task 4. Decision 4 (process chain) → Task 5. Decision 5 (proactive suggestion) → Task 6. Success criteria 1 → the per-task gates; 2 and 3 → Task 7 Steps 5-6; 4 → Task 6 Step 2. No spec section is without a task.

**A spec claim this plan corrects.** The spec's risk section says *"The reference cascade is real work"* and names `test-skill-discovery.sh` as what would fail. Measured on 2026-08-03: that test matches **path-form references only**, and no surviving surface has one pointing at a removed skill — the check returns empty. The real cascade is nine **bare-name** references that no test catches at all, which is a smaller cleanup but a worse gap. Task 2 fixes them and Task 3 adds the missing guard. The spec should be amended to say this.

**Placeholder scan.** No TBD. Every description is either quoted verbatim or given in full. The guard script, the hook script, and all three new skills are written out. The one deliberately unfixed number is the baseline drift in Tasks 4-6, which depends on whether content edits drift the tool's count — Task 2 Step 8 establishes it empirically and every later task defers to that finding rather than guessing.

**Type consistency.** Surface counts are 8 agents / 11 commands / 10 skills after Task 2, becoming 13 skills after Task 5 — used identically in Tasks 2, 3 and 5. `provenance-skip.tsv`'s four columns and `rule=absent` are used the same way in Tasks 1 and 2. `session-brief.sh` is named identically in the file structure table, Task 5's file list, Step 5, Step 6 and Step 7.
