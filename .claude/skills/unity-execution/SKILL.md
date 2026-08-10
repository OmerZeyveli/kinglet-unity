---
name: unity-execution
description: "Use to execute an approved plan inline, in this session, when the plan is small enough that a fresh implementer per task would cost more than it catches. The other branch of unity-planning's fork; prefer subagent-driven-implementation when the plan has more than one substantial task."
---

# Inline Execution

One of the two branches `unity-planning` forks to. Take this one when the plan is one task, or a
few small ones, and the context that wrote the plan is the right context to write the code. Take
`.claude/skills/subagent-driven-implementation/SKILL.md` instead when the plan has more than one
substantial task, or when a single task is large enough that its own context would crowd out the
review of it.

**If the ledger already records a mode, do not ask** — a recorded decision is not reopened.

The two branches differ in where the review comes from, not in whether there is one. The subagent
loop gets a fresh reader per task. This branch does not, which is why the verify loop and the
Deslop Pass below are not optional: they are the whole of this branch's defence against the fact
that the author is also the reviewer.

## 1. Load and review the plan

1. Read the plan file. All of it, before starting anything.
2. Review it critically — identify any questions or concerns about the plan.
3. If concerns: raise them **before starting**, not after the first task exposes them.
4. If no concerns: create one todo per task in the plan, in plan order, and proceed.

Do not create a worktree. Upstream's version of this step opens one; Unity is the reason it is
dropped here. Worktrees do not share `Library/`, so every one triggers a full reimport, and
`.meta` GUIDs diverge between trees — the refusal is recorded in `provenance-skip.tsv`. Work in
the checkout you are in, on a branch that is not `main`.

## 2. Execute

For each task, in plan order:

1. Mark it in progress.
2. Follow each step exactly. The plan's steps are bite-sized on purpose; a step you improve on is
   a step whose verification no longer proves what it was written to prove.
3. Run the verification the step names. Do not skip it because the change "obviously" worked.
4. Mark it complete.

Report progress at natural milestones ("scripts written, setting up the scene now"), not per file.

## 3. Verify

Perform a verify-fix loop directly:

1. **Review** — invoke the `unity-reviewer` agent (read-only) against all changed files
2. **Auto-fix** issues that are safe to fix automatically
3. **Re-verify** if fixes were applied (max 3 iterations)
4. **Run tests** via MCP if available

The cap of 3 is a decision, not a budget. A loop still producing the same class of finding on its
fourth pass is not converging — it means the fix is aimed at the wrong thing. At the cap, stop and
say what is still open rather than running a fourth round; an unresolved finding stated plainly is
worth more than a loop that ends when it runs out of patience.

A task is not complete until the console is clean. Unity writes a `.cs` file whether or not it
compiles, so git sees a finished change either way — check `read_console` after the last write, or
you have no way to tell "done" from "done and broken".

## 4. Deslop Pass

*"This workflow" below means this execution run: the files this plan's tasks created or modified,
from the first task to the last.*

After verification succeeds with no critical issues, perform a targeted code-bloat review on all files created or modified during this workflow. Specifically target:

1. **Unnecessary abstractions** — interfaces with one implementation, factory classes that create one type, wrapper classes that add no behavior
2. **Over-commenting** — comments that restate the code, obvious doc comments, commented-out code blocks
3. **Redundant error handling** — try/catch that just rethrows, null checks on values that can never be null, defensive code with no plausible failure mode
4. **Dead code** — unused private methods, unreachable branches, unused parameters
5. **Over-engineering** — generic solutions for non-generic problems, premature optimization patterns, unnecessary design patterns

Deslop rules:
- Only simplify, never add complexity
- Preserve all runtime behavior
- Do not touch code that existed before this workflow started
- If in doubt, leave it alone — false positives are worse than missed bloat
- Apply fixes directly, then re-check console via `read_console` to confirm no regressions

The last two rules are the ones that make this pass safe to run, and the ones an abbreviated
version drops first. Without them the pass is "tidy up the code", which reliably becomes a diff
that touches files this plan never mentioned and cannot be reviewed against anything.

## 5. Final Summary

Present a complete summary to the user:

```
## Workflow Complete

### What was built
- [list of features implemented]

### Files created/modified
- [file paths with brief descriptions]

### Verification results
- [auto-fixed issues]
- [remaining items for human review]

### Test results
- [compilation status, test pass/fail counts]

### Manual steps needed
- [any inspector assignments, scene references, etc.]

### How to test
- [step-by-step testing instructions]
```

**Manual steps needed** is the section that is load-bearing and the one most often left empty.
An inspector assignment, a sprite atlas, a lightmap bake — anything the plan needed that could not
be done through MCP — belongs there by name. A described step nobody performed did not happen;
`.claude/skills/verification-before-completion/SKILL.md` is the standard this summary is measured
against.

## When to stop and ask

**Stop executing immediately when:**

- you hit a blocker — a missing dependency, a failing test, an instruction you cannot read
- the plan has a gap that prevents starting
- you do not understand an instruction
- verification fails repeatedly
- the plan's premise turns out to be false — not "this step is awkward", but "the thing this task
  is built on does not exist / does not work the way the plan says"

**Ask rather than guess.** A guess against a plan is invisible: the diff looks deliberate, and the
verification the plan wrote passes because it was written for the plan's premise, not yours.

Return to step 1 when the plan is updated in response to your concerns, or when the approach needs
rethinking rather than the step. Do not force through a blocker.

## Handoff

When the plan is complete and its summary is delivered, this skill is done. Do not start a new
feature from here — a new feature goes back to the top of the chain
(`.claude/skills/unity-brainstorming/SKILL.md`, then
`.claude/skills/unity-planning/SKILL.md`). Name what still needs a human and stop.
