# Kinglet Process Chain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL — execute this plan task by task with
> `.claude/skills/subagent-driven-implementation/SKILL.md` (recommended) or inline with checkpoints.
> Steps use checkbox (`- [ ]`) syntax for tracking. Do not implement directly from this file.
>
> *(This line arrived from `writing-plans`' template naming the upstream skills, which would have
> routed a fresh session to a loop this repo does not use. Corrected 2026-08-10 — the same defect
> D8 exists to prevent, caught on its first real outing.)*

**Goal:** Replace Kinglet's process chain with three skills that pull each other, delete the two commands that only sequence them, and turn `using-kinglet` from a summary into a mandate.

**Architecture:** `unity-brainstorming` → `unity-planning` → the execution fork (`subagent-driven-implementation` or `unity-execution`). Each surface names its successor and forbids the alternatives, so the chain fires on every route rather than only through a command. Surfaces are adapted at the expression level from Superpowers (MIT), which makes the licence facts change — that is a task, not a footnote.

**Tech Stack:** Bash 3.2-compatible shell, Markdown surfaces with YAML frontmatter, Python 3 for the baseline regenerator (`tools.kinglet_build`), TSV manifests.

**Spec:** `docs/superpowers/specs/2026-08-10-kinglet-process-chain-design.md` (commit `62059b9`). Read it before Task 1. Every decision reference below (D1…D10) points into it.

**Branch:** `pioneer/process-chain`, already created, spec already committed on it.

## Global Constraints

Every task's requirements implicitly include this section.

- **Bash 3.2 compatible.** No `declare -A` (bash 4), no `grep -oP` (GNU-only). macOS ships bash 3.2 and a macOS host pass is planned.
- **Never pipe into a reader that exits early.** Under `set -euo pipefail`, `head` and **`grep -q`** both exit on first match without draining stdin; the writer gets SIGPIPE, pipefail turns 141 into failure. Use a here-string: `grep -qF -- "$needle" <<< "$haystack"`. This has already produced three "flakes" in this repo that were not flakes.
- **Validate an argument before `shift 2`** — `shift` fails under `set -u` before an error message can print.
- **Skills are flat**: `.claude/skills/<name>/SKILL.md`, one level. `name:` must match the directory. `description:` must be non-empty — it is the entire selection mechanism. No `alwaysApply`, no `globs`: both are inert Cursor keys read as guarantees.
- **Test-file idioms do not mix.** The runner does `( source "$test_file" )`. A *self-contained* file defines its own helpers and sets `set -euo pipefail` and may be run standalone. A *runner-provided* file uses the runner's `assert_contains` / `assert_eq` / `assert_file_exists` and `$REPO_DIR` and **exits 0 having asserted nothing** when run standalone. Pick one deliberately and say which in the commit.
- **`assert_eq` takes (expected, actual)** in that order. Some files define a local shadow with the opposite order — check the file you are editing before adding a call.
- **Gates, both must pass before every commit:**
  - `bash tests/run-tests.sh` — exit 0, and the number of `--- test-*.sh ---` headers must equal `ls tests/test-*.sh | wc -l`. Takes ~2m25s; use a timeout above 150000ms.
  - `bash scripts/check-provenance.sh` — output ends `provenance OK`.
- **Never hardcode a derived count** in `CLAUDE.md`, a test, or prose. Counts have gone stale twice; `tests/test-derived-counts.sh` exists because of it.
- **Baseline discipline.** Run `python3 -m tools.kinglet_build baseline-regenerate … --dry-run` first. **Use the tool's numbers, not your estimate**, and if they disagree with this plan, report the disagreement rather than tuning the flag until it passes. A categorised file counts **twice** (once in `full_claude_tree`, once in its category), and skills and commands are both categorised. Put the baseline update in its own commit.
- **The entry point is the package, not the module**: `python3 -m tools.kinglet_build`. `python3 -m tools.kinglet_build.cli` silently no-ops with exit 0.

---

### Task 1: Provenance can record a Superpowers origin, and two refusals get recorded

The wave cannot add a single adapted surface until the manifest can express where it came from. The Pioneer design mandated this value and it was never implemented (D10).

**Files:**
- Modify: `scripts/check-provenance.sh:103`
- Modify: `provenance-skip.tsv` (append two rows)
- Test: `tests/test-provenance-origins.sh` (create — **self-contained**)

**Interfaces:**
- Consumes: nothing.
- Produces: `origin=superpowers` becomes a legal value in `provenance.tsv`, subject to the same rule as `ecu` — a vendored file must carry an upstream and may not be `status=original`. Tasks 2, 3 and 4 rely on this.

- [ ] **Step 1: Write the failing test**

Create `tests/test-provenance-origins.sh`:

```bash
#!/usr/bin/env bash
# Self-contained: defines its own helpers, safe to run standalone.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$1"; }

# 1. The checker must accept origin=superpowers.
haystack="$(cat "$REPO/scripts/check-provenance.sh")"
if grep -qF -- 'ecu|donchitos|superpowers|original' <<< "$haystack"; then
  pass "check-provenance.sh accepts origin=superpowers"
else
  fail "check-provenance.sh does not accept origin=superpowers (D10)"
fi

# 2. A superpowers row must obey the vendored rule: it cannot be status=original.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'x.md\tsuperpowers\t6.2.0\tskills/x/SKILL.md\tdeadbeef\toriginal\tprobe\n' > "$tmp/row"
if grep -qF -- 'vendored file cannot have status=original' <<< "$haystack"; then
  pass "the vendored/status agreement rule is present and covers superpowers"
else
  fail "no vendored-status agreement rule found"
fi

# 3. Both deliberate refusals must be recorded in the skip manifest.
skip="$(cat "$REPO/provenance-skip.tsv")"
for needle in 'skills/using-git-worktrees/' 'skills/brainstorming/visual-companion.md'; do
  if grep -qF -- "$needle" <<< "$skip"; then
    pass "refusal recorded: $needle"
  else
    fail "refusal not recorded in provenance-skip.tsv: $needle"
  fi
done

[ "$FAILURES" -eq 0 ] || exit 1
printf 'all provenance-origin assertions passed\n'
```

- [ ] **Step 2: Run it and watch it fail**

```bash
bash tests/test-provenance-origins.sh
```

Expected: FAIL on assertion 1 (`check-provenance.sh does not accept origin=superpowers`) and on both refusal assertions. Assertion 2 should already pass — if it does not, stop and report, because the agreement rule is load-bearing for the others.

- [ ] **Step 3: Teach the checker the third origin**

In `scripts/check-provenance.sh:103`, change:

```bash
  case "$origin" in ecu|donchitos|original) ;; *) fail "bad origin '$origin': $path"; BADFIELD=$((BADFIELD + 1)) ;; esac
```

to:

```bash
  case "$origin" in ecu|donchitos|superpowers|original) ;; *) fail "bad origin '$origin': $path"; BADFIELD=$((BADFIELD + 1)) ;; esac
```

No other line changes: the two agreement rules below it (`origin=original` must have `status=original`; a vendored file may not have `status=original`) already read `origin != original`, so they cover `superpowers` without edit.

- [ ] **Step 4: Record the two refusals**

Append to `provenance-skip.tsv` (columns are `upstream_path<TAB>upstream<TAB>rule<TAB>reason`):

```
skills/using-git-worktrees/	superpowers	absent	a git worktree does not share Library/; every one triggers a full asset reimport and .meta GUIDs diverge across trees, which is the failure the payload's rules spend the most effort preventing. Refused in the Pioneer design with this reason and never recorded here, so no guard enforced it until now
skills/brainstorming/visual-companion.md	superpowers	absent	browser-based mockup companion; shipping a local server into a user's Unity project is separate work with its own consent question. Declined for this wave, not overlooked
```

- [ ] **Step 5: Run the test and the gates**

```bash
bash tests/test-provenance-origins.sh
bash scripts/check-provenance.sh
```

Expected: the new test prints `all provenance-origin assertions passed`; the checker ends `provenance OK` and its `rule=absent` count rises by 2.

- [ ] **Step 6: Add the provenance row for the new test file**

A new tracked file with no row fails as an orphan. Append to `provenance.tsv`:

```
tests/test-provenance-origins.sh	original	-	-	-	original	guards the superpowers origin value and the two recorded refusals (using-git-worktrees, visual-companion)
```

- [ ] **Step 7: Run the full suite**

```bash
bash tests/run-tests.sh
```

Expected: exit 0, and the header count equals `ls tests/test-*.sh | wc -l` (which just grew by one).

- [ ] **Step 8: Commit**

```bash
git add scripts/check-provenance.sh provenance-skip.tsv provenance.tsv tests/test-provenance-origins.sh
git commit -m "feat(provenance): accept a superpowers origin, and record two refusals that only lived in prose"
```

---

### Task 2: `unity-execution` — the inline branch, and the two orphans it rescues

Built first because it sits at the bottom of the chain: `unity-planning` (Task 3) names it, so it must exist before that task's reference guard can pass.

**This task carries an explicit gate.** The spec's D6 says `unity-execution`'s defence against the cut criterion — *"does something the model cannot do unaided"* — rests on the Deslop Pass and the bounded verify loop, and that if the defence cannot be made concretely, the honest outcome is to fold it into `subagent-driven-implementation`. Upstream's `executing-plans` is 64 lines and its own text says to prefer the subagent skill when subagents exist, so the adapted skeleton is thin by admission; the Kinglet content is what earns the surface.

**Files:**
- Create: `.claude/skills/unity-execution/SKILL.md`
- Read (do not modify yet): `.claude/commands/unity-workflow.md:108-150` — the source of the Deslop Pass, the verify loop and the Final Summary
- Read: `.research/superpowers/skills/executing-plans/SKILL.md` — the adapted skeleton
- Modify: `provenance.tsv`
- Test: `tests/test-surface-references.sh` (extend)

**Interfaces:**
- Consumes: `origin=superpowers` from Task 1.
- Produces: skill name `unity-execution`, path `.claude/skills/unity-execution/SKILL.md`. Task 3 references it by that path. The five Deslop category headings below are the exact strings Task 2's guard tests for.

- [ ] **Step 1: Write the failing guard**

Append to `tests/test-surface-references.sh` (**runner-provided** file — use `$REPO_DIR` and the runner's helpers, define nothing, and read its existing section before adding; run it through `bash tests/run-tests.sh`, never standalone, or it exits 0 having asserted nothing):

```bash
# The Deslop Pass was the only content of /unity-workflow with no other owner.
# It must survive the move to unity-execution, category by category — a move that
# drops a category is exactly the silent loss this wave exists to prevent.
deslop="$(cat "$REPO_DIR/.claude/skills/unity-execution/SKILL.md")"
for category in \
  "Unnecessary abstractions" \
  "Over-commenting" \
  "Redundant error handling" \
  "Dead code" \
  "Over-engineering"
do
  assert_contains "$deslop" "$category"
done
assert_contains "$deslop" "do not touch code that existed before"
assert_contains "$deslop" "false positives are worse than missed bloat"
```

- [ ] **Step 2: Run the suite and watch this fail**

```bash
bash tests/run-tests.sh 2>&1 | sed -n '/test-surface-references/,/^--- /p'
```

Expected: failures naming the missing file `.claude/skills/unity-execution/SKILL.md`.

- [ ] **Step 3: Create the skill**

Create `.claude/skills/unity-execution/SKILL.md`. Frontmatter is exactly two keys:

```markdown
---
name: unity-execution
description: "Use to execute an approved plan inline, in this session, when the plan is small enough that a fresh implementer per task would cost more than it catches. The other branch of unity-planning's fork; prefer subagent-driven-implementation when the plan has more than one substantial task."
---
```

Body, in this order:

1. **Load and review the plan** — read the file, raise concerns before starting, create one todo per task. Adapted from `executing-plans` Step 1, with the worktree step **removed**: `using-git-worktrees` is refused for Unity (Task 1 recorded why).
2. **Execute** — follow each step exactly, run the verification each step names, mark complete.
3. **Verify loop** — transcribe from `.claude/commands/unity-workflow.md` Phase 4 steps 1–4: invoke `unity-reviewer` (read-only) against changed files, auto-fix what is safe, re-verify if fixes were applied (**max 3 iterations**), run tests via MCP if available.
4. **Deslop Pass** — transcribe all five categories and all five rules verbatim from `unity-workflow.md`. Do not paraphrase; the guard tests the strings.
5. **Final Summary** — transcribe the summary format from `unity-workflow.md`.
6. **Stop conditions** — from `executing-plans`: stop on a blocker, a plan gap, an unclear instruction, or repeated verification failure. Ask rather than guess.

- [ ] **Step 4: Make the cut-criterion defence, in the report**

Write, in the task report, the concrete answer to: *what does this surface do that the model does not do unaided?* The Deslop Pass's five categories and its two restraining rules, and the bounded (max-3) verify loop, are the candidates. If the honest answer is "nothing the subagent loop does not already do", **stop and escalate** rather than shipping the surface — the spec pre-authorises folding it into `subagent-driven-implementation`, and pre-states that folding must carry the Deslop Pass and verify loop into that skill and rename its `description:` accordingly.

- [ ] **Step 5: Add the provenance row**

```
.claude/skills/unity-execution/SKILL.md	superpowers	6.2.0	skills/executing-plans/SKILL.md	<sha256 of the upstream file>	modified	inline branch of the execution fork; skeleton adapted from executing-plans (worktree step removed — using-git-worktrees is refused for Unity, see provenance-skip.tsv); the Deslop Pass, the bounded verify loop and the Final Summary are Kinglet-original, transcribed from the deleted /unity-workflow Phase 4
```

Compute the checksum from the clone:

```bash
sha256sum .research/superpowers/skills/executing-plans/SKILL.md
```

- [ ] **Step 6: Run the gates**

```bash
bash tests/run-tests.sh
bash scripts/check-provenance.sh
```

Expected: both green. `check-provenance.sh` now reports one more row and one more covered file.

- [ ] **Step 7: Regenerate the baseline, dry-run first**

```bash
python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift 0 --expect-added 2 --dry-run
```

`--expect-added 2` because one new `.claude` file counts twice — once in `full_claude_tree`, once in its category. **If the tool disagrees, report its number and stop**; do not tune the flag. Then run without `--dry-run`.

- [ ] **Step 8: Commit, baseline separately**

```bash
git add .claude/skills/unity-execution/SKILL.md provenance.tsv tests/test-surface-references.sh
git commit -m "feat(unity-execution): the inline branch, and a home for the Deslop Pass"
git add migration/baseline-inventory.json
git commit -m "chore(baseline): record unity-execution"
```

---

### Task 3: `unity-planning` — plan-writing as a skill, carrying the fork

**Files:**
- Create: `.claude/skills/unity-planning/SKILL.md`
- Read: `.research/superpowers/skills/writing-plans/SKILL.md` — the adapted source
- Read: `.claude/commands/unity-workflow.md:23-52` — Phase 1a, whose capability moves here
- Modify: `.claude/skills/subagent-driven-implementation/SKILL.md` (frontmatter `description:` only)
- Modify: `tests/test-workflow-plan-input.sh` — **retarget, do not delete**
- Modify: `provenance.tsv`
- Test: `tests/test-workflow-plan-input.sh`, `tests/test-surface-references.sh`

**Interfaces:**
- Consumes: `unity-execution` (Task 2) by path `.claude/skills/unity-execution/SKILL.md`.
- Produces: skill name `unity-planning`; the plan template's required handoff line, quoted verbatim in Step 3 below and tested in Step 1. Task 4 references `unity-planning` by path.

- [ ] **Step 1: Write the failing tests**

First, retarget `tests/test-workflow-plan-input.sh`. Read the whole file before editing and note which idiom it uses. Its subject is plan **adoption** — `$ARGUMENTS` resolving to an existing plan, the search order, the verbatim-acceptance-criteria rule, the hard stop on an unreadable path. That capability is not being deleted; it is moving. Replace every path reference `.claude/commands/unity-workflow.md` with `.claude/skills/unity-planning/SKILL.md`, and leave every assertion's *substance* unchanged.

Then append to the same file:

```bash
# The plan artifact carries its own handoff, so a fresh session given only the plan
# path is routed without reading any table. This is what closes the ledger-resume route.
planning="$(cat "$REPO_DIR/.claude/skills/unity-planning/SKILL.md")"
assert_contains "$planning" "REQUIRED SUB-SKILL"
assert_contains "$planning" "subagent-driven-implementation"
assert_contains "$planning" ".claude/skills/unity-execution/SKILL.md"

# The fork lives here, and it does not reopen a decision the ledger already records.
assert_contains "$planning" "If the ledger already records a mode, do not ask"
```

- [ ] **Step 2: Run the suite and watch it fail**

```bash
bash tests/run-tests.sh 2>&1 | sed -n '/test-workflow-plan-input/,/^--- /p'
```

Expected: failures naming the missing `.claude/skills/unity-planning/SKILL.md`.

- [ ] **Step 3: Create the skill**

Create `.claude/skills/unity-planning/SKILL.md` with frontmatter:

```markdown
---
name: unity-planning
description: "Use after a design decision exists — from unity-brainstorming or a written spec — to turn it into a task-by-task implementation plan with its own test cycle per task. Writes the plan to docs/features/<slug>/plan.md and chooses how it will be executed."
---
```

Body sections:

1. **Adopt an existing plan first.** Transcribe Phase 1a from `unity-workflow.md:23-52`: the four-entry search order; carry Acceptance Criteria **verbatim** because a paraphrase is a silent design change; record the adopted path; adopt-and-state-what-was-missing when there are no criteria; ask when more than one matches; **hard stop** on a named-but-unreadable path.
2. **Plan shape.** Adapted from `writing-plans`: the document header, right-sized tasks (the smallest unit carrying its own test cycle and worth a fresh reviewer's gate), bite-sized 2–5 minute steps, the `Files:` and `Interfaces:` blocks, and the **No Placeholders** list — `TBD`, "add appropriate error handling", "similar to Task N", steps with no code block.
3. **The Unity additions**, which upstream has no reason to carry:
   - a task that needs an asset an agent cannot create (sprite atlas, import settings, lightmap bake, `AnimatorOverrideController`) states the **operator steps** as part of its deliverable, per `performance.md`;
   - **one implementer at a time against one Editor** — two agents driving the Unity Editor over MCP corrupt a shared in-memory asset database, and it surfaces as a broken `.unity` file, not a merge conflict;
   - a new runtime `.cs` must be created through Unity so the `.meta` and csproj entry exist.
4. **Write the plan** to `docs/features/<slug>/plan.md`, and include this line verbatim under the title:

```
**For agentic workers:** REQUIRED SUB-SKILL — execute this plan task by task with
`subagent-driven-implementation` (recommended) or `unity-execution` (inline). Do not
implement directly from this file.
```

5. **Self-review** — adapted from `writing-plans`: spec coverage, placeholder scan, type consistency. Fix inline, do not re-review.
6. **The fork**, and it is the terminal state:

```markdown
Confirm the execution mode before starting. **If the ledger already records a mode, do not ask** —
a recorded decision is not reopened. On a fresh run, state both routes and choose:

1. **Subagent-driven** — a fresh implementer per task, a review after each, a bounded fix loop, and
   one whole-branch review at the end. Loads `.claude/skills/subagent-driven-implementation/SKILL.md`.
2. **Inline** — execute here with checkpoints. Loads `.claude/skills/unity-execution/SKILL.md`.

Invoke no other skill. One of those two is the next step.
```

- [ ] **Step 4: Drop the false clause from `subagent-driven-implementation`, and give its ledger an address**

In its frontmatter `description:`, delete ` — offered by \`/unity-workflow\` as an alternative to executing inline`. The claim is false on most routes and `description:` is the entire selection mechanism. Leave the rest of the sentence intact.

Then, in the same file's Setup section, name where the ledger lives — spec D8 puts all three artifacts in one directory, and the ledger is the third:

```markdown
The ledger is `docs/features/<slug>/ledger.md`, beside the `design.md` and `plan.md` this work came
from. One directory holds what was decided, what was planned, and where the work stopped; a later
session opens it and reads the three in order.
```

Add the matching assertion to the block written in Step 1:

```bash
sdi="$(cat "$REPO_DIR/.claude/skills/subagent-driven-implementation/SKILL.md")"
assert_contains "$sdi" "docs/features/<slug>/ledger.md"
```

- [ ] **Step 5: Add the provenance rows**

```
.claude/skills/unity-planning/SKILL.md	superpowers	6.2.0	skills/writing-plans/SKILL.md	<sha256>	modified	plan-writing as a skill so the execution fork sits on every route; plan-adoption (search order, verbatim acceptance criteria, hard stop on an unreadable path) transcribed from the deleted /unity-workflow Phase 1a; Unity additions original (operator steps, one-implementer-per-Editor, create .cs through Unity)
```

Compute the checksum the same way Task 2 did:

```bash
sha256sum .research/superpowers/skills/writing-plans/SKILL.md
```

Append to the existing `subagent-driven-implementation` row's note (do not replace it):

```
;process-chain: dropped the false "offered by /unity-workflow" clause from description — the command is deleted and the claim was untrue on two of three routes
```

- [ ] **Step 6: Run the gates and the baseline**

```bash
bash tests/run-tests.sh
bash scripts/check-provenance.sh
python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift 2 --expect-added 2 --dry-run
```

`--expect-drift 2` covers the edited `subagent-driven-implementation` counted twice. Use the tool's numbers if they differ, and report the difference.

- [ ] **Step 7: Commit, baseline separately**

```bash
git add .claude/skills/unity-planning/SKILL.md .claude/skills/subagent-driven-implementation/SKILL.md provenance.tsv tests/test-workflow-plan-input.sh
git commit -m "feat(unity-planning): plan-writing as a skill, and the fork on every route"
git add migration/baseline-inventory.json
git commit -m "chore(baseline): record unity-planning and the description fix"
```

---

### Task 4: `deep-interview` becomes `unity-brainstorming`, and gains the design half

**Files:**
- Rename: `.claude/skills/deep-interview/SKILL.md` → `.claude/skills/unity-brainstorming/SKILL.md`
- Read: `.research/superpowers/skills/brainstorming/SKILL.md` — the adapted source
- Modify: `provenance.tsv` (path change + note)
- Test: `tests/test-skill-discovery.sh`, `tests/test-surface-references.sh`

**Interfaces:**
- Consumes: `unity-planning` (Task 3) by path.
- Produces: skill name `unity-brainstorming`; the artifact path `docs/features/<slug>/design.md`. Task 6's `using-kinglet` table row names this skill.

- [ ] **Step 1: Write the failing guard**

Append to `tests/test-surface-references.sh`:

```bash
brainstorm="$(cat "$REPO_DIR/.claude/skills/unity-brainstorming/SKILL.md")"

# D2: the trigger is a category of work, not a judgment about the request.
assert_contains "$brainstorm" "You MUST use this before building anything"
# D3: the gate covers MCP writes, not only code — the Unity adaptation.
assert_contains "$brainstorm" "no MCP write call is made"
# D4: the handoff is closed and names the forbidden alternatives.
assert_contains "$brainstorm" ".claude/skills/unity-planning/SKILL.md"
assert_contains "$brainstorm" "unity-coder"
# D2: depth scales the round, never the artifact.
assert_contains "$brainstorm" "design.md is still written"

# The old name must be gone from the tree, not merely unused.
assert_file_absent "$REPO_DIR/.claude/skills/deep-interview/SKILL.md"
```

If `assert_file_absent` does not exist in the runner, use the file-existence idiom already present in that file rather than inventing a helper — read the file first and match what is there.

- [ ] **Step 2: Run the suite and watch it fail**

Expected: failures naming the missing `unity-brainstorming` path.

- [ ] **Step 3: Rename with git so history follows**

```bash
git mv .claude/skills/deep-interview .claude/skills/unity-brainstorming
```

- [ ] **Step 4: Rewrite the surface**

Frontmatter — `name:` must match the new directory, and the description is the exact string the spec fixes in D2:

```markdown
---
name: unity-brainstorming
description: "You MUST use this before building anything in this Unity project — a new mechanic, system, component, scene, or UI screen — and before writing a plan, touching C#, or mutating the scene. Explores intent, constraints and approaches, then writes the design decision to a file. Not for a tweak to something that already works."
---
```

Body changes, in order:

1. **Delete the "When to Activate" section and the five-item Exemptions list.** They are replaced by the category trigger in the description. A broken thing routes to `systematic-debugging`; a resumed run carries its decisions in a ledger.
2. **Add the hard gate**, immediately after the opening paragraph:

```markdown
<HARD-GATE>
Until a design has been presented and approved: no implementer agent is dispatched, no `.cs` is
written, and **no MCP write call is made** — scene, prefab and ScriptableObject included. A single
MCP call mutates state that no test can restore. This applies to every request regardless of
perceived simplicity.
</HARD-GATE>
```

3. **Add the checklist, as todos.** "You MUST create a task for each of these items and complete them in order": explore project context; ask clarifying questions one at a time; propose 2–3 approaches with trade-offs and a recommendation; present the design in sections and get approval after each; write `docs/features/<slug>/design.md`; self-review it; ask the user to review the written file; hand off to `unity-planning`.
4. **Keep the Ambiguity Score, change its job.** It no longer decides whether to fire. Add, in the score's own section:

```markdown
The score sets the depth of the round, not whether the round happens. Below 6, ask up to three
questions and re-score. At or above 6, one confirming round is enough.

**Depth scales the round, never the artifact.** At depth 1 the design may be three sentences, but
`design.md` is still written, still presented, and still approved. "Short design" and "no design"
are different outcomes and only one of them is allowed.
```

5. **Add the design content spec** — what `design.md` carries: scope and non-scope; the 2–3 approaches considered with trade-offs and why this one; the architecture decision in Model/View/System terms **and which rules bind, by reference to `CLAUDE.md`'s generated block** because that is detected per project rather than assumed; acceptance criteria; and **operator steps**, the Unity work an agent cannot do.
6. **Add the commit rule:**

```markdown
Commit the artifact — an uncommitted file is lost at the next checkout, which is the defect this
step repairs. Commit **only the artifact path**. Never `git add -A`: in a Unity project that stages
`.meta` churn, and `.meta` loss is the damage these rules spend the most effort preventing.
```

7. **Replace the Handoff section** with a closed one:

```markdown
## Handoff

The terminal state is `.claude/skills/unity-planning/SKILL.md`. Invoke no other skill. Do **not**
invoke `/unity-prototype`, `unity-coder`, or any MCP agent — the gate above is still holding when
this section is reached.

If the gate did not pass — requirements still unclear after a round — ask the specific questions the
score identified and **stop**. Do not proceed on an assumption and do not answer your own question.
```

8. **Keep** the "the thought that means you are about to treat vague as clear" table. It is measured content and its rows still apply.

- [ ] **Step 5: Update the provenance row**

The row's `path` changes. `origin=ecu` **stays** — the file's lineage begins at ECU and the Ambiguity Score being kept is ECU's contribution (D10). Append to its note, do not replace:

```
;process-chain: renamed deep-interview -> unity-brainstorming; trigger changed from a judgment about the request to a category of work; exemption list removed; gained the design half (2-3 approaches, sections, docs/features/<slug>/design.md) and a HARD-GATE covering MCP writes — structure adapted from Superpowers 6.2.0 skills/brainstorming/SKILL.md, MIT, see .claude/NOTICE.md
```

- [ ] **Step 6: The note-field rethink is now due**

That row now carries its **fifth** clause. The 2026-08-03 ledger deferred note-field readability with an explicit trigger — *"may need a rethink if another wave adds a fifth"* — and this is it. Do one of: (a) collapse the row's note to a one-line summary plus a pointer to `MERGE-NOTES.md` where the full history lives, or (b) state in the task report why leaving five clauses is still the better trade. **Either is acceptable; silently adding the fifth and moving on is not.**

- [ ] **Step 7: Run the gates and the baseline**

```bash
bash tests/run-tests.sh
bash scripts/check-provenance.sh
python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift 0 --expect-removed 2 --expect-added 2 --dry-run
```

A rename is a removal plus an addition, each counted twice. **The 2026-08-03 ledger records that a path-set change was an unconditional refusal by design until the tool was taught otherwise — confirm it handles a rename before assuming these flags are right, and report the tool's numbers.**

- [ ] **Step 8: Commit, baseline separately**

```bash
git add -- .claude/skills/unity-brainstorming .claude/skills/deep-interview provenance.tsv tests/test-surface-references.sh
git commit -m "feat(unity-brainstorming): the design half deep-interview never had"
git add migration/baseline-inventory.json
git commit -m "chore(baseline): record the rename to unity-brainstorming"
```

---

### Task 5: Delete the two sequencer commands and repair every reference

Twenty-two files name one or both. The landmine is `scripts/generate-claude-md.sh`: it emits surface names **into installed projects' `CLAUDE.md`**, and shipping the name of a deleted command as a project instruction is a defect this repo has already made once, in the 2026-08-03 wave, and had to fix as a Critical.

**Files:**
- Delete: `.claude/commands/unity-workflow.md`, `.claude/commands/unity-feature.md`
- Modify: `provenance.tsv` (remove two rows), `provenance-skip.tsv` (add two)
- Modify: `scripts/generate-claude-md.sh`
- Modify: `.claude/agents/unity-coder.md`, `.claude/commands/unity-prototype.md`, `.claude/commands/unity-scene.md`, `.claude/skills/subagent-driven-implementation/SKILL.md`
- Modify: `docs/ARCHITECTURE.md`, `docs/GETTING-STARTED.md`, `docs/SKILL-CATALOG.md`, `docs/AGENT-GUIDE.md`, `README.md`, `MERGE-NOTES.md`, `CREDITS.md`, `.claude/NOTICE.md`
- Modify: `tests/test-stack-arbitration.sh`
- Test: `tests/test-provenance-origins.sh` (extend), plus the whole suite

**Interfaces:**
- Consumes: the three chain surfaces from Tasks 2–4, which are what the repaired references point to instead.
- Produces: nothing new. `using-kinglet` is deliberately **not** touched here — it is Task 6's whole subject.

- [ ] **Step 1: Write the failing guard**

Append to `tests/test-provenance-origins.sh`:

```bash
# The two sequencer commands are gone and must stay gone.
for gone in ".claude/commands/unity-workflow.md" ".claude/commands/unity-feature.md"; do
  if [ -e "$REPO/$gone" ]; then
    fail "deleted sequencer command has returned: $gone"
  else
    pass "absent: $gone"
  fi
  if grep -qF -- "$gone" <<< "$skip"; then
    pass "skip row present: $gone"
  else
    fail "no rule=absent row for $gone"
  fi
done

# No shipped payload file may name a command that does not exist.
payload="$(git -C "$REPO" ls-files '.claude/*' 'scripts/generate-claude-md.sh')"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  body="$(cat "$REPO/$f")"
  case "$f" in *NOTICE.md) continue ;; esac   # history section, see Step 6
  if grep -qF -- '/unity-workflow' <<< "$body"; then fail "names deleted /unity-workflow: $f"; fi
  if grep -qF -- '/unity-feature' <<< "$body"; then fail "names deleted /unity-feature: $f"; fi
done <<< "$payload"
```

Note the `<<<` here-strings throughout: `grep -q` exits on first match without draining stdin, and a pipe here would produce an intermittent failure that looks like a flake.

- [ ] **Step 2: Run it and watch it fail**

```bash
bash tests/test-provenance-origins.sh
```

Expected: FAIL on both "has returned" assertions and on many "names deleted" assertions.

- [ ] **Step 3: Delete, and record the absence**

```bash
git rm .claude/commands/unity-workflow.md .claude/commands/unity-feature.md
```

Remove their two rows from `provenance.tsv`, and append to `provenance-skip.tsv`:

```
.claude/commands/unity-workflow.md	ecu	absent	a command that only sequences other surfaces is a second definition of the chain; its phases moved to unity-brainstorming, unity-planning and unity-execution, and the Deslop Pass moved with a guard. See docs/superpowers/specs/2026-08-10-kinglet-process-chain-design.md D7
.claude/commands/unity-feature.md	ecu	absent	same criterion as /unity-workflow: a sequencer, not a router. A scoped addition now runs the chain at depth 1
```

- [ ] **Step 4: Repair `scripts/generate-claude-md.sh` first, and read what it emits**

This file writes into user projects. Find every emitted mention of the two commands — including `suggest_skills()` and any "How to work" or "Where things go" prose — and replace them with the chain surfaces. Then prove it by generating against the fixture rather than by reading the diff:

```bash
bash tests/fixtures/mkproject.sh /tmp/chain-fixture --variant urp
bash scripts/generate-claude-md.sh --project-dir /tmp/chain-fixture > /tmp/chain-claude.md
grep -n 'unity-workflow\|unity-feature' /tmp/chain-claude.md || echo "clean"
```

Expected: `clean`. If the script takes different flags, read its usage rather than guessing.

- [ ] **Step 5: Repair the payload references**

For each of `.claude/agents/unity-coder.md`, `.claude/commands/unity-prototype.md`, `.claude/commands/unity-scene.md`, `.claude/skills/subagent-driven-implementation/SKILL.md`: replace the named command with the surface that now owns the behaviour. The mapping, by what the sentence is doing:

| The sentence says | It now names |
|---|---|
| "invoked by `/unity-feature`" (an agent describing who dispatches it) | `unity-planning`'s fork, via `subagent-driven-implementation` or `unity-execution` |
| "run `/unity-feature` for one scoped addition" (routing advice) | `unity-brainstorming` — the chain's entry, at depth 1 |
| "`/unity-workflow` takes a feature end to end" (routing advice) | `unity-brainstorming` |
| "`/unity-workflow` Phase 1a adopts a written plan" (capability) | `unity-planning` |
| "prefer `/unity-feature` over this for the real project" (a contrast) | keep the contrast, name `unity-brainstorming` as the other side |

**Read each sentence — do not run a blind substitution.** The 2026-08-03 wave recorded a docs pass that ran over a named list instead of the tree and missed files; the guard in Step 1 is what catches that here.

- [ ] **Step 6: Repair the docs, and leave history alone where it is history**

`docs/ARCHITECTURE.md`, `docs/GETTING-STARTED.md`, `docs/SKILL-CATALOG.md`, `docs/AGENT-GUIDE.md`, `README.md`: these describe the current toolkit and must name only surviving surfaces.

`MERGE-NOTES.md`, `CREDITS.md` and `.claude/NOTICE.md` are **records**. Where they describe what happened historically, the mention stays and gains a "removed 2026-08-10" clause; where they describe how the toolkit works today, it is corrected. The guard in Step 1 skips `NOTICE.md` for exactly this reason — if you find yourself wanting to skip more files, that is a sign the sentence should be rewritten instead.

- [ ] **Step 7: Repair `tests/test-stack-arbitration.sh`**

Read the file and find what it actually asserts about the two commands — it is the stack-arbitration block (the "read before you write or refuse" guidance), not the commands as such. That block lives in `unity-coder.md` and the surviving commands. Retarget the assertions to the files that still carry it; do not delete the coverage.

- [ ] **Step 8: Run everything**

```bash
bash tests/test-provenance-origins.sh
bash tests/run-tests.sh
bash scripts/check-provenance.sh
```

Expected: all green. `check-provenance.sh` reports two fewer rows, two fewer covered files, and two more `rule=absent` entries.

- [ ] **Step 9: Baseline, then commit**

```bash
python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift 0 --expect-removed 4 --dry-run
```

Four: two files, each counted twice. Report the tool's number if it differs.

```bash
git add -A -- .claude scripts docs README.md MERGE-NOTES.md CREDITS.md provenance.tsv provenance-skip.tsv tests
git commit -m "refactor(surfaces): delete the two sequencer commands, repair every reference"
git add migration/baseline-inventory.json
git commit -m "chore(baseline): record the sequencer-command removals"
```

---

### Task 6: `using-kinglet` becomes a mandate

**Files:**
- Modify: `.claude/skills/using-kinglet/SKILL.md`
- Modify: `provenance.tsv` (note)
- Test: `tests/test-surface-references.sh` (extend)

**Interfaces:**
- Consumes: all three chain surfaces, by name, in the routing table.
- Produces: the injected session text. Nothing consumes it programmatically; the hook already injects this file and no hook change is needed.

- [ ] **Step 1: Write the failing guard**

```bash
uk="$(cat "$REPO_DIR/.claude/skills/using-kinglet/SKILL.md")"

# The ordering rule, the announce ritual, and the red-flag table.
assert_contains "$uk" "before any response or action"
assert_contains "$uk" "Using [skill] to [purpose]"
assert_contains "$uk" "The table names the file. It is not the file."

# The escape clause is rewritten, not deleted: the measured negative control still holds.
assert_contains "$uk" "that is not work, and it selects no surface"
assert_contains "$uk" "work always"

# The chain names the new surfaces and none of the deleted ones.
assert_contains "$uk" "unity-brainstorming"
assert_contains "$uk" "unity-planning"
```

- [ ] **Step 2: Run the suite and watch it fail**

- [ ] **Step 3: Rewrite the escape clause**

Replace:

```
A question that the rules already answer needs no surface. Answer it.
```

with:

```
A question about what the rules already state is answered from the rules — that is not work, and it
selects no surface. A request to build, change, or fix something is work, and work always selects a
surface.
```

**Do not delete it.** Its justification is measured: a serialization question correctly selected nothing, and a selection there would be a regression. What closes is the generalisation to "if I feel I can answer, I need no surface."

- [ ] **Step 4: Add the ordering rule and the announce ritual**

```markdown
## The rule

Invoke the surface **before any response or action** — including clarifying questions, reading files,
and exploring the code. Then announce `Using [skill] to [purpose]` and follow it. If it turns out
wrong for the situation, you do not have to use it — but you have to have looked.
```

- [ ] **Step 5: Add the Red Flags table**

Use exactly these five rows, which are this toolkit's own measured rationalizations rather than a generic list:

```markdown
## The thoughts that mean you are about to skip a surface

| Thought | Reality |
|---|---|
| "This request is already clear" | That judgment is made by a model that has just read six rule files and a generated block. It is exactly the one miss that was measured. |
| "The table already tells me what to do" | The table names the file. It is not the file. Twice, the chain was executed without ever loading it. |
| "I am resuming from a ledger, the decision is made" | A ledger records the **mode**. It does not record the design of a new task. |
| "I remember this skill" | The block is 41 lines; the skill is over 110. What you remember is the block. |
| "Let me look at the code first" | The surface is the thing that tells you how to look at it. |
```

- [ ] **Step 6: Rewrite the chain table**

Replace the deleted commands' rows and strip the descriptive parentheticals — a row names a surface, it does not summarise it, and the summary is what made loading unnecessary. Concretely: `deep-interview — ask, do not guess` becomes `unity-brainstorming`. Rows for `/unity-workflow` and `/unity-feature` are replaced by the chain's own entry point. Keep every row for a surviving router unchanged.

- [ ] **Step 7: Gates, provenance note, baseline, commit**

```bash
bash tests/run-tests.sh
bash scripts/check-provenance.sh
python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift 2 --dry-run
git add .claude/skills/using-kinglet/SKILL.md provenance.tsv tests/test-surface-references.sh
git commit -m "feat(using-kinglet): a mandate that points at files, not a summary that answers"
git add migration/baseline-inventory.json
git commit -m "chore(baseline): record the using-kinglet rewrite"
```

---

### Task 7: The licence facts change, and NOTICE ships

Adapting Superpowers at the expression level makes three currently-shipping statements false. `.claude/NOTICE.md` goes into every installed project, so a stale attribution claim there is the defect this repo already fixed once as a Critical.

**Files:**
- Modify: `.claude/NOTICE.md` (§3), `CREDITS.md` (§4)
- Test: `tests/test-provenance-origins.sh` (extend)

**Interfaces:**
- Consumes: the `origin=superpowers` rows created in Tasks 2 and 3 — they are the evidence that the obligation now exists.
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Write the failing guard**

```bash
notice="$(cat "$REPO/.claude/NOTICE.md")"

# The stale claims must be gone.
for stale in "influence, not a license obligation" "What was not taken is the text" "0.120"; do
  if grep -qF -- "$stale" <<< "$notice"; then
    fail "NOTICE.md still carries a claim adaptation made false: $stale"
  else
    pass "stale claim removed: $stale"
  fi
done

# The obligation must be discharged: MIT text, and the copyright line.
for needed in "Permission is hereby granted, free of charge" "Jesse Vincent"; do
  if grep -qF -- "$needed" <<< "$notice"; then
    pass "NOTICE.md carries: $needed"
  else
    fail "NOTICE.md does not discharge the MIT obligation: missing $needed"
  fi
done
```

- [ ] **Step 2: Run it and watch it fail**

Expected: three "still carries" failures and one or two "does not discharge" failures.

- [ ] **Step 3: Rewrite `.claude/NOTICE.md` §3**

Retitle from *"Superpowers — influence, not a license obligation"* to *"Superpowers — adapted, MIT"*. State plainly what changed and when: until 2026-08-10 this toolkit took the chain design and two skill names but not the text, and measured the similarity to prove it; on 2026-08-10 three surfaces were adapted at the expression level from `brainstorming`, `writing-plans` and `executing-plans`, so the obligation now exists and is discharged here. Name the three surfaces and the upstream version (6.2.0). Then reproduce the MIT licence text from `.research/superpowers/LICENSE` in full, with its copyright line.

**Delete the similarity figures rather than re-measuring them.** They described a state that no longer holds, and a re-measured number would invite the same staleness a year from now. Say what was adapted; the manifest carries the per-file truth.

- [ ] **Step 4: Rewrite `CREDITS.md` §4**

Same correction, at the repository's level of detail: which files, which upstream paths, and a pointer to `provenance.tsv` for the per-file record. Keep the historical account — that the section was once "influence, not obligation" is true of the period it described and worth preserving, dated.

- [ ] **Step 5: Verify the claim against the manifest**

```bash
awk -F'\t' '$2=="superpowers" {print $1"\t"$4}' provenance.tsv
```

Every path this prints must be named in `NOTICE.md` §3, and nothing else. If they disagree, the document is wrong, not the manifest.

- [ ] **Step 6: Gates and commit**

```bash
bash tests/test-provenance-origins.sh
bash tests/run-tests.sh
bash scripts/check-provenance.sh
git add .claude/NOTICE.md CREDITS.md tests/test-provenance-origins.sh
git commit -m "docs(notice): adaptation makes it an obligation, so discharge it"
git add migration/baseline-inventory.json
git commit -m "chore(baseline): record the NOTICE rewrite"
```

---

### Task 8: Whole-wave verification

**Files:**
- Modify: `CLAUDE.md` (the surface-pool sentence), `docs/` counts if any went stale
- Test: the whole suite

**Interfaces:**
- Consumes: everything.
- Produces: the wave's own evidence.

- [ ] **Step 1: Correct the stale pool sentence**

`CLAUDE.md` says *"The surface pool is 32 by design"*; the real count was already 33 before this wave and is 33 after it (8 agents + 9 commands + 16 skills). Correct the number **and** state the criterion rather than only the count, so the sentence does not rot again:

```bash
ls .claude/agents/*.md | wc -l
ls .claude/commands/*.md | wc -l
ls -d .claude/skills/*/ | wc -l
```

- [ ] **Step 2: Prove the chain references resolve**

```bash
grep -rn '\.claude/skills/[a-z-]*/SKILL\.md' .claude/skills/unity-brainstorming .claude/skills/unity-planning .claude/skills/unity-execution \
  | sed 's/.*\(\.claude[^ `]*\.md\).*/\1/' | sort -u | while IFS= read -r p; do
      [ -f "$p" ] || echo "DANGLING: $p"
    done
```

Expected: no output. A bare-name reference (a skill named without its path) is what `tests/test-surface-references.sh` exists to catch — nine of them shipped once before that guard existed.

- [ ] **Step 3: Run both gates and check the header count**

```bash
bash tests/run-tests.sh 2>&1 | tee /tmp/chain-suite.log
grep -c '^--- test-.*\.sh ---' /tmp/chain-suite.log
ls tests/test-*.sh | wc -l
bash scripts/check-provenance.sh
```

The two numbers must be equal. They have silently disagreed before, and the suite reported green while 7 of 8 files never ran.

- [ ] **Step 4: Install into a fixture and read what shipped**

```bash
bash tests/fixtures/mkproject.sh /tmp/chain-install --variant urp
bash install.sh --project-dir /tmp/chain-install --dry-run
```

Read the installer's output for the **"kept N of yours"** line and for any mention of a deleted command. A dry run that names `/unity-workflow` means Task 5 missed a file.

- [ ] **Step 5: Commit and report**

```bash
git add CLAUDE.md
git commit -m "docs(claude-md): state the pool criterion, not a number that rots"
```

Report: the suite result with its header count, the provenance result, the fixture install result, and — separately, because it is the wave's honest open item — whether Task 2's cut-criterion defence for `unity-execution` was made or the fold-in fallback was taken.

---

## What this plan does not do

Named so the omission is tracked rather than assumed:

- **The measurement layer.** The seven scenarios in the spec's scenario table need a model harness; the five guards that do not are built inline above. Building the harness is its own spec.
- **Re-running the Superpowers disposition table.** Four of its declines are void (`writing-skills`, `dispatching-parallel-agents`, `finishing-a-development-branch`, and `executing-plans`, addressed here), and two rows marked "Adapt" — `test-driven-development` and `receiving-code-review` — were never done. Its own spec.
- **`save-system`'s zero inbound edges.** Recorded in the design spec, not addressed here.
