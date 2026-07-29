# Kinglet Pioneer — Wave 1b-2 (Make It Findable) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Kinglet Pioneer's command, agent and skill surfaces selectable by the model from natural language, so that nobody has to memorise a command name to use the toolkit.

**Architecture:** Five tasks. One verifies an assumption the whole scope rests on. One designs differentiation rules for surfaces that would otherwise collide. One does the bulk rewrite. One guards the result. One re-runs the measurement that found the defect, which is the only honest proof the work succeeded.

**Tech Stack:** Markdown frontmatter, bash 3.2-compatible shell, the `tests/run-tests.sh` harness, `scripts/check-provenance.sh`.

## Authority, and the measurement this exists to reverse

`docs/research/pioneer/smoke-pass.md` §4. Asked *"Let's add a double jump to the player"* — the most ordinary request a game developer makes — **not one of the toolkit's 36 commands, 28 agents or 39 skills was selected.** A competing plugin won, twice: on an empty project and again on the operator's real 1073-script Unity project.

In Claude Code, a surface is chosen from its `description` frontmatter and nothing else. Ours describe *what the thing does*; the plugin that won describes *when it applies*.

The scope below comes from a survey at `.superpowers/sdd/surface-selection-survey.md`, which read all 103 surfaces. **That survey corrected this plan's parent design in three ways, and each correction is built into the tasks below.**

## Three corrections to the design, recorded

**1. Agents were out of scope and should not have been.** The design's Item 8 named "the 36 commands and the `core/` process skills". It did not mention agents. But 24 of 28 agents are process surfaces selected by the same description-only mechanism — `unity-prototyper`, `unity-reviewer`, `unity-fixer` and the rest. Shipping Item 8 as written would fix the command layer and leave the agent layer with the identical measured defect, so that a request which should reach `unity-prototyper` directly stays invisible. **Agents are in scope.**

**2. The exemption for `core/` skills may rest on nothing.** `docs/ARCHITECTURE.md` and `docs/SKILL-CATALOG.md` both state that the nine `core/` skills marked `alwaysApply: true` are loaded for every agent in every session, which would make their descriptions irrelevant to selection. The survey found **no hook, no `settings.json` entry, and no script anywhere in this repository that reads `alwaysApply` or injects skill content unconditionally.** If it is inert metadata, those skills face exactly the selection failure the smoke pass measured, and the "core skills are safe" assumption in this repo's own documentation is false. Task 1 settles this before anything is scoped around it.

**2a. Task 1 has run. `alwaysApply` is inert, and the scope decision it forced is recorded here.**

Result: **no hook, no `settings.json` entry, no script reads `alwaysApply`.** The serialization probe made zero tool calls and answered from `.claude/rules/serialization.md`. A second probe settled it — a fact that exists **only** in the `commit-trailers` skill was answered correctly only after the model went looking for and read that file itself. Skills marked `alwaysApply: true` are selected from their description like every other skill. `docs/ARCHITECTURE.md` and `docs/SKILL-CATALOG.md` have been corrected (`041c52d`).

So the nine `core/` skills are **not** exempt. But that does not make all nine a rewrite, because five spine rules **do** auto-load, and where a rule already carries a skill's content, the skill never being selected costs nothing:

| Core skill | Covered by an auto-loading rule? | Decision |
|---|---|---|
| `serialization-safety` | **Yes** — `serialization.md`, and the probe proved the rule answered the question | Leave |
| `event-systems` | Largely — `architecture.md`'s MessagePipe section | Leave; record the overlap |
| `scriptable-objects` | Partly — `architecture.md` | Leave; record the overlap |
| `object-pooling` | Partly — one line in `performance.md` | Leave; record the overlap |
| `assembly-definitions` | Partly — one line in `architecture.md` | Leave; record the overlap |
| `commit-trailers` | **No** | **Rewrite** — process-triggered ("when committing") |
| `unity-mcp-patterns` | **No** | **Rewrite** |
| `deep-interview` | **No** | **Rewrite** (already REWRITE) |
| `model-routing` | **No** | **Rewrite** (already REWRITE) |

**Skills scope becomes 4, not 2.** The 25 non-core knowledge skills are unaffected: they are `globs`-scoped and topic-matched, and nothing measured suggests that is failing.

**A finding to carry forward, not to act on here.** Four skills substantially duplicate content in an auto-loading rule. They cost provenance churn and dilute a 103-surface selection pool while the rule does the actual work. That is consolidation evidence for the deferred stocktake decision — **record it, do not act on it in this wave.**

**3. Sixty-two independent edits would make the problem worse.** Several surfaces cover near-identical ground. The worst is the feature/prototype family — `/unity-feature`, `/unity-prototype`, `unity-coder`, `unity-coder-lite`, `unity-prototyper` — five surfaces that would all naturally phrase their trigger around *"let's add X"*, which is the exact prompt that failed. Rewritten independently they tie, and the model picks arbitrarily among them. **Arbitrary selection among five is worse than today's uniform non-selection**, because it looks like it works. Task 2 designs the differentiation rule before any of those files is touched.

## Global Constraints

- **Bash 3.2 (macOS) compatible.** No `declare -A`. No `grep -oP`, no `grep -qP` — GNU-only.
- **Do not pipe into a reader that can exit early** under `set -euo pipefail` — `head` and `grep -q` both do. See `CLAUDE.md`'s shell conventions.
- **Validate an argument before `shift 2`.**
- **`bash tests/run-tests.sh` must pass at every commit, with every test file present in its output.** Count them by name; the summary line is not evidence.
- **`scripts/check-provenance.sh` must report `provenance OK`** at every commit.
- **27 of the REWRITE files are `status=verbatim`** — 19 commands, 7 agents, 1 skill. Each needs its `status` flipped to `modified` with a reason in `note`, **in the same commit as the edit**. Change only `status` and `note`. This manifest has already rotted once, when 38 files were edited and left marked verbatim.
- **Editing `.claude/` drifts `migration/baseline-inventory.json`.** Regenerate with `python3 -m tools.kinglet_build baseline-regenerate --anchor <commit> --expect-drift <n>` in a **separate** commit. `--dry-run` first to learn the count; it refuses if the path set changed or the count is not what you predicted, and that refusal is the point.
- **Frontmatter only.** `unity-instincts.md`, `unity-learn.md` and `unity-skillify.md` each contain a second `description:` line **in the body**, inside example output blocks. A regex over the whole file corrupts them. Target only the first `description:` inside the first `---` block.
- **Do not touch `spikes/platform/clients/`.** A separate experiment there has tests that assert on exact description wording. Nothing in this plan goes near it.
- **Preserve unusual frontmatter keys verbatim.** Four agents (`unity-optimizer`, `unity-prototyper`, `unity-shader-dev`, `unity-ui-builder`) carry a `skills:` key nothing else has.

## The house style for a trigger description

Every rewritten description states **when the surface applies**, in the words a user would actually use, and only then what it does. Three examples from the survey, which are the pattern:

| Surface | Before | After |
|---|---|---|
| `/unity-fix` | *"Diagnoses and fixes a Unity bug — reads console errors, checks common causes, applies targeted fix, verifies via MCP."* | *"Use when the user reports a bug, error, crash, or something not working in Unity — before proposing a fix from memory. Reads the actual console output and verifies the fix via MCP rather than guessing."* |
| `unity-reviewer` | *"Reviews Unity C# code for correctness, performance, serialization safety, architecture patterns, and Unity-specific pitfalls…"* | *"Use after C# code changes are written and before they're considered done — checks for Unity-specific correctness, performance, and serialization pitfalls a general code reviewer would miss."* |
| `core/deep-interview` | *"Ambiguity gating — detects vague feature requests and forces structured requirements gathering…"* | *"Use before starting any feature work when the request is vague or underspecified — e.g. 'add a jump', 'make an inventory system' — before writing a plan or touching code."* |

Keep the product's voice: concrete, no marketing, no "powerful" or "seamless". A description is a sentence a tired developer reads at speed.

---

### Task 1: Find out whether `alwaysApply` does anything

**Files:** none changed. This task produces a written answer and, if the answer is "inert", a documentation correction.

The whole LEAVE bucket — 34 knowledge skills — rests on the claim that `core/` skills load unconditionally and are therefore selected by topic rather than by trigger. Two shipped documents assert it. No code implements it.

- [ ] **Step 1: Search for an implementation.** Grep the whole repository for `alwaysApply`, and for anything that reads `SKILL.md` and injects it: `.claude/hooks/`, `.claude/settings.json`, `scripts/`, `install.sh`. Report every hit and what it does. A documentation mention is not an implementation.

- [ ] **Step 2: Probe it behaviourally.** Install into a scratch fixture (`bash tests/fixtures/mkproject.sh /tmp/aa-probe --variant urp`, then `bash install.sh --project-dir /tmp/aa-probe`) and run, from inside it:

```bash
printf '%s' "I need to rename a serialized field on a MonoBehaviour from _speed to _moveSpeed. What do I have to be careful about?" \
  | timeout 300 claude -p --model sonnet --output-format stream-json --verbose > /tmp/aa-probe.jsonl 2>&1
```

Then extract the tool calls. The smoke pass ran this exact probe and observed **zero tool calls** with a correct answer — meaning the answer came from `.claude/rules/serialization.md`, which genuinely does auto-load, and **not** from the `serialization-safety` skill.

Confirm or refute that. If `serialization-safety` is never invoked, the skill is not doing the work its documentation claims, whatever `alwaysApply` is supposed to mean.

- [ ] **Step 3: Report the finding and correct the documentation if it is wrong.** If `alwaysApply` is inert, say so in `docs/ARCHITECTURE.md` and `docs/SKILL-CATALOG.md` rather than leaving two documents asserting a mechanism that does not exist — that is the same defect class this wave has closed five times. Do **not** expand this plan's rewrite scope on your own; report the consequence and let the controller decide.

- [ ] **Step 4: Commit** the documentation correction if there is one, with the evidence in the message.

---

### Task 2: Design the differentiation rules before touching a colliding file

**Files:**
- Create: `docs/superpowers/specs/2026-07-30-surface-trigger-rules.md`

Six families would otherwise produce ambiguous triggers. Write the rule for each **before** any of their files is edited, and write it down where the later tasks can follow it.

| Family | Members |
|---|---|
| Feature / prototype — **highest risk** | `/unity-feature`, `/unity-prototype`, `unity-coder`, `unity-coder-lite`, `unity-prototyper` |
| Bug fixing | `/unity-fix`, `unity-fixer`, `unity-fixer-lite` |
| Review / quality | `/unity-review`, `unity-reviewer`, `unity-security-reviewer`, `unity-critic`, `unity-verifier`, `unity-linter` |
| Performance | `/unity-optimize`, `/unity-profile`, `unity-optimizer` |
| Testing | `/unity-test`, `unity-test-runner` |
| Migration | `/unity-migrate`, `unity-migrator` |

Plus the **shadow pairs** — `/unity-ui`+`unity-ui-builder`, `/unity-scene`+`unity-scene-builder`, `/unity-network`+`unity-network-dev`, `/unity-build`+`unity-build-runner`, `/unity-shader`+`unity-shader-dev` — each a thin command wrapping one agent with nearly the same job.

- [ ] **Step 1: Decide the command-versus-agent rule once, globally.** The survey's suggestion is that commands own the user-facing trigger and shadow agents lean on being invoked by their command plus a narrower internal cue. Adopt it or replace it, but **decide it once** rather than re-litigating it in each of five pairs. Write the decision and its reasoning.

- [ ] **Step 2: Give each family an explicit differentiator**, on an axis a description can actually express — scale, depth, speed, or phase of work. "Lite handles a single obvious fix: a missing reference, a typo, an import error" versus "the full agent investigates across multiple possible causes" is the shape. Vague differentiators produce vague triggers.

- [ ] **Step 3: Write the whole family's proposed descriptions together, in one document**, so the ties are visible on one page. This is the step that makes the difference: five descriptions written on five different days will collide no matter how careful each one is.

- [ ] **Step 4: Sanity-check against the failing prompt.** For *"Let's add a double jump to the player"*, exactly one surface in the feature/prototype family should read as the obvious match, and you should be able to say which and why. If two still tie, the rule is not finished.

- [ ] **Step 5: Commit** the rules document. No `.claude/` file changes in this task, so no baseline drift.

---

### Task 3: Rewrite the surfaces

**Files:**
- Modify: `.claude/commands/*.md` — 36, all REWRITE
- Modify: `.claude/agents/*.md` — 24 REWRITE (4 are UNSURE; leave those and report why)
- Modify: `.claude/skills/**/SKILL.md` — 4 REWRITE: `core/deep-interview`, `core/model-routing`, `core/commit-trailers`, `core/unity-mcp-patterns` (see correction 2a)
- Modify: `provenance.tsv` — 27 verbatim flips
- Separate commit: `migration/baseline-inventory.json`

- [ ] **Step 1: Do the collision families first**, straight from Task 2's document. They are the hard part and they are already decided; transcribe rather than re-derive.

- [ ] **Step 2: Do the remaining surfaces.** Each gets a trigger-condition description in the house style above.

- [ ] **Step 3: Leave the UNSURE ones alone and say why.** Seven surfaces were unclear to the survey. Guessing at them is worse than leaving them: report each with your reading, and let the controller decide.

- [ ] **Step 4: Flip the 27 provenance rows**, in the same commit as their edits.

- [ ] **Step 5: Commit in coherent batches** — the collision families together, then the rest. Not 62 commits, and not one commit of 62 files.

- [ ] **Step 6: Regenerate the baseline** in a separate commit.

---

### Task 4: Guard it

**Files:**
- Create: `tests/test-surface-triggers.sh`
- Modify: `provenance.tsv`

- [ ] **Step 1: Write the guard, and make it fail first.** Every `.claude/commands/*.md` and every REWRITE agent must have a description matching the trigger grammar. Then **revert one description in a scratch `git worktree` and watch the guard name that file.** A guard written after the fixes and never seen to fail is decoration — this wave already caught one test that pinned nothing for exactly that reason.

- [ ] **Step 2: Do not let the exclusion list become the problem space.** Whatever surfaces are exempt, list them by exact path with a reason each, and confirm the guard still fails when a new bad description appears in a file that is not on the list.

- [ ] **Step 3:** Suite green with every file present; `check-provenance.sh` OK; new test file has a provenance row; baseline regenerated separately.

---

### Task 5: Re-run the measurement

This is the only honest proof. Everything above is a hypothesis until this runs.

- [ ] **Step 1: Install into a fresh scratch fixture** and run **the exact prompt that failed**:

```bash
printf '%s' "Let's add a double jump to the player." \
  | timeout 500 claude -p --model sonnet --output-format stream-json --verbose \
    --disallowed-tools Edit Write NotebookEdit > /tmp/dj-after.jsonl 2>&1
```

Extract the tool-call stream. **Record what was selected, whatever it was.**

- [ ] **Step 2: Run the second probe too** — the serialization-rename question from Task 1 — and record whether a skill is invoked now.

- [ ] **Step 3: Write the result into `docs/research/pioneer/smoke-pass.md` as a new dated section**, beside the original measurement. Do not edit the original: the record of the failure is what makes the fix meaningful.

- [ ] **Step 4: If a Kinglet surface still is not selected, say so plainly and stop.** That is a real result and it means the approach is insufficient, not that the run was bad. Report it and let the controller decide. **Do not retry with a friendlier prompt** — the prompt is the measurement, and changing it to get a better answer would be fabricating a pass.

---

## What this plan does not do

| Deferred | To | Why |
|---|---|---|
| Durable artifacts, design↔engineering link, code map | Wave 1b-3 | Independent of selection |
| The discipline layer (TDD, systematic debugging, receiving code review) | Wave 2 | Independent |
| The playtest gate | Indefinitely | Needs a GDD with Feel Acceptance Criteria; none exists yet |
| Consolidating the 103-surface pool | A separate decision | The stocktake produces a measurement; cutting is a judgement made against it |

## Self-review

**Spec coverage.** This plan implements the design's Item 8, expanded to agents per the survey, with the `alwaysApply` assumption tested rather than inherited and the collision families designed rather than discovered.

**Placeholder scan.** No TBD. The three worked examples are written out; the collision families are enumerated by member; the two verification prompts are given verbatim.

**Type consistency.** "REWRITE / LEAVE / UNSURE" carry the survey's meanings throughout. The 27 verbatim count is used identically in Global Constraints and Task 3. The house style in the preamble is what Tasks 2, 3 and 4 all refer to.
