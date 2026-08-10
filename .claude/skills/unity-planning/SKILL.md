---
name: unity-planning
description: "Use after a design decision exists — from unity-brainstorming, a written spec, or a plan path handed over to be adopted — to turn it into a task-by-task implementation plan with its own test cycle per task. Writes the plan to docs/features/<slug>/plan.md. Handed a plan path, come here first even though the plan is already written: this is where the execution mode is chosen and recorded, and going straight to an executor skips that choice."
---

# Writing the Plan

Plan-writing is a skill and not a phase of a command, for one structural reason: the choice between
executing a plan inline and executing it task by task with a fresh implementer belongs to whoever
wrote the plan, and until now that fork existed on exactly one route in. A plan reached any other way
— handed over as a path, resumed from a ledger, written straight from a spec — never met it. This
skill is where the plan gets written **and** where that choice gets made, so every route meets it.

Write for an engineer who is skilled but has zero context for this project and has not read the spec.
Everything they need is in the plan or it does not reach them: which files to touch, the code, how to
test it, what a neighbouring task produced. DRY. YAGNI. Frequent commits.

## 1. Adopt an existing plan first

Before planning anything, look for work that has already been scoped. What you were handed may be a
path to a written plan or spec rather than a feature description.

Search in this order and stop at the first hit:

1. the path you were given, if it resolves to a readable file
2. `docs/features/<slug>/plan.md`
3. `docs/superpowers/plans/*<slug>*.md` — a process provider's output is as legitimate an input
   as a design document
4. `docs/design/<system>.md`

**Found:** do not re-plan it. Carry the plan's **Acceptance Criteria**, and its
**Game Feel → Feel Acceptance Criteria** if present, into your working summary **verbatim**.
Verbatim matters: a paraphrase is a silent design change. Record which file was adopted, by path,
so a later session can tell where the requirements came from. Then go to section 6 — an adopted plan
still needs its execution mode chosen.

**Found, but it has no acceptance criteria:** adopt what is there and state plainly what was
missing. Never invent the criteria the plan would have contained.

**More than one match:** list them and ask. Never silently take the newest.

**A file was named that cannot be read:** **Hard stop.** Say the path and the reason, and stop. Do
not fall back to planning from scratch as though nothing was handed over — a silent degradation into
conversation is invisible to the user and is exactly how requirements stopped surviving sessions in
the first place.

**Nothing found:** say so in one line, then write the plan.

If there is no design decision yet — no spec, no agreed approach, only a request — this is the wrong
skill. Go to `.claude/skills/unity-brainstorming/SKILL.md` first and come back with a design.

## 2. Plan shape

**File structure before tasks.** Map which files will be created or modified and what each is
responsible for, before drawing any task boundary. This is where the decomposition gets decided;
doing it inside the task list means deciding it several times, differently. Prefer smaller focused
files, keep files that change together together, and in an existing codebase follow the patterns that
are already there rather than restructuring on the way past.

**Right-size the tasks.** A task is the smallest unit that carries its own test cycle and is worth a
fresh reviewer's gate. Fold setup, configuration, scaffolding and documentation into the task whose
deliverable needs them; split only where a reviewer could meaningfully reject one task while
approving its neighbour. Every task ends with an independently testable deliverable.

**Bite-sized steps.** Each step is one action, two to five minutes: write the failing test, run it
and watch it fail, write the minimal code, run it and watch it pass, commit.

**Every task carries `Files:` and `Interfaces:`.**

````markdown
### Task N: [Component Name]

**Files:**
- Create: `Assets/Scripts/Exact/Path.cs`
- Modify: `Assets/Scripts/Existing.cs:123-145`
- Test: `Assets/Tests/EditMode/ExactPathTests.cs`

**Interfaces:**
- Consumes: what this task uses from earlier tasks — exact signatures
- Produces: what later tasks rely on — exact type and method names, parameter and return types.
  A task's implementer sees only their own task; this block is how they learn the names and types
  the neighbouring tasks use.

- [ ] **Step 1: Write the failing test**

```csharp
[Test]
public void SetMoveInput_WithRightVector_MovesPositiveX() { }
```

- [ ] **Step 2: Run it and watch it fail**
````

Steps use checkbox (`- [ ]`) syntax so an executor can track them.

**No placeholders.** These are plan failures, not shortcuts. Never write them:

- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases" — as a task, this is a
  defect: it names no file, no behaviour and no test
- "Write tests for the above", with no test code
- "Similar to Task N" — repeat the code; the engineer may be reading tasks out of order, and under
  `subagent-driven-implementation` they are reading exactly one
- a step that describes what to do without showing how (a code step needs a code block)
- a reference to a type, method or property defined in no task

## 3. The Unity additions

Three things a generic planner has no reason to carry, and every plan here does.

**An asset an agent cannot create is an operator step, and it is part of the task's deliverable.**
Sprite atlases, texture import settings, lightmap bakes, an `AnimatorOverrideController` — MCP cannot
produce these, and `.claude/rules/performance.md` already makes them mandatory rather than optional.
The task that needs one states the operator steps: which menu, which settings, which assets. Do not
write code against an atlas or a shared material that does not exist yet — the task that creates it
comes first, and the dependent task says so.

**One implementer at a time, against one Editor.** Never plan two tasks to run concurrently against
one Unity project. The generic form of this rule is about merge conflicts, and a reader whose two
tasks touch disjoint files concludes it does not apply. It is not about files: the Editor is a single
process holding one asset database in memory, and two agents driving it over MCP corrupt that shared
state. It surfaces as a broken `.unity` file discovered later, not as a merge conflict, and no diff
review catches it. Sequence the tasks.

**A new runtime `.cs` is created through Unity.** A file written straight to disk has no `.meta` and
no csproj entry until Unity notices it, and a task that ends before the reimport ends with a project
that compiles for nobody else. Say so in the step that creates the file.

## 4. Write the plan

Save it to `docs/features/<slug>/plan.md` — beside the `design.md` this came from, and where the
ledger will land. One directory holds what was decided, what was planned and where the work stopped.

**Every plan starts with this header, in this order:**

````markdown
# [Feature Name] Implementation Plan

**For agentic workers:** REQUIRED SUB-SKILL — execute this plan task by task with
`subagent-driven-implementation` (recommended) or `unity-execution` (inline). Do not
implement directly from this file.

**Goal:** [one sentence describing what this builds]

**Architecture:** [2-3 sentences on the approach, in Model/View/System terms, naming which
rules bind by reference to `CLAUDE.md`'s generated block — that is detected per project, not
assumed]

**Tech Stack:** [the packages and libraries this depends on]

## Global Constraints

[The spec's project-wide requirements — version floors, dependency limits, naming and copy
rules, platform targets — one line each, values copied **verbatim** from the spec. Every
task's requirements implicitly include this section, so it is written once here rather than
repeated per task.]

---
````

The handoff line is fixed text, character for character, and
`tests/test-workflow-plan-input.sh` compares the whole block against a literal — reword it and the
suite goes red. That is deliberate: it is the quietest device in this chain and the most effective
one, because the plan file names its own required next skill, so a session handed nothing but a path
is routed correctly without consulting any table. A paraphrase still reads fine to a human and stops
being a match for anything.

Commit the plan. An uncommitted artifact is lost at the next checkout, which is the failure this
whole chain exists to repair. Commit **the plan path only** — never `git add -A`, because in a Unity
project that stages `.meta` churn, and `.meta` loss is the damage these rules spend the most effort
preventing.

## 5. Self-review

Run this yourself against the spec, with fresh eyes. It is a checklist, not a subagent dispatch.

1. **Spec coverage.** Walk each requirement in the spec. Can you point at the task that implements
   it? List the gaps, and add a task for each.
2. **Placeholder scan.** Search the plan for every red flag in section 2's list.
3. **Type consistency.** Do the types, signatures and property names used in later tasks match what
   earlier tasks defined? `ClearLayers()` in Task 3 and `ClearFullLayers()` in Task 7 is a bug, and
   it is a bug that costs a whole task under a fresh-implementer loop, because the implementer of
   Task 7 has no way to see Task 3.

Fix what you find inline. Do not re-review.

## 6. Choose the execution mode

Confirm the execution mode before starting. **If the ledger already records a mode, do not ask** —
a recorded decision is not reopened. On a fresh run, state both routes and choose:

1. **Subagent-driven** — a fresh implementer per task, a review after each, a bounded fix loop, and
   one whole-branch review at the end. Loads `.claude/skills/subagent-driven-implementation/SKILL.md`.
2. **Inline** — execute here with checkpoints. Loads `.claude/skills/unity-execution/SKILL.md`.

**Then write the choice down, before the first task starts.** The ledger's second line is:

```
**Execution mode:** subagent-driven
```

— or `inline`. That line is the whole of what "do not ask" reads, and a rule that reads a field
nobody writes is a rule that asks every time. Both branches below create the ledger and both write
this line; a resuming controller that finds it proceeds in that mode without reopening the question,
and one that finds a ledger without it knows the run predates the field and asks once.

Invoke no other skill. One of those two is the next step.
