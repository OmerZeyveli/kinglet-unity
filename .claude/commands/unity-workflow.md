---
name: unity-workflow
description: "Use when the user wants a feature taken all the way through — clarified, planned, implemented and verified — rather than a single step, or when they hand over a written plan to execute. Prefer `/unity-feature` when the request is one scoped addition that needs no plan."
user-invocable: true
args: feature-description-or-plan-path
---

# /unity-workflow — Full Development Pipeline

Orchestrate a complete development workflow for: **$ARGUMENTS**

This command runs a 4-phase pipeline: **Clarify → Plan → Execute → Verify**. Each phase requires explicit user confirmation before proceeding to the next.

## Phase 1: Clarify

### Phase 1a: Adopt an existing plan, if there is one

Before interviewing anyone, look for work that has already been scoped. `$ARGUMENTS` may be a
path to a written plan or spec rather than a feature description.

Search in this order and stop at the first hit:

1. `$ARGUMENTS` itself, if it resolves to a readable file
2. `docs/features/<slug>/plan.md`
3. `docs/superpowers/plans/*<slug>*.md` — a process provider's output is as legitimate an input
   as a design document
4. `docs/design/<system>.md`

**Found:** skip the interview. Carry the plan's **Acceptance Criteria**, and its
**Game Feel → Feel Acceptance Criteria** if present, into the Requirements Summary **verbatim**.
Verbatim matters: a paraphrase is a silent design change. Record which file was adopted, by path,
in the Requirements Summary, so a later session can tell where the requirements came from.

**Found, but it has no acceptance criteria:** adopt what is there and state plainly what was
missing. Never invent the criteria the plan would have contained.

**More than one match:** list them and ask. Never silently take the newest.

**`$ARGUMENTS` names a file that cannot be read:** **Hard stop.** Say the path and the reason, and
stop. Do not fall back to interviewing as though nothing was asked for — a silent degradation into
conversation is invisible to the user and is exactly how requirements stopped surviving sessions
in the first place.

**Nothing found:** say so in one line, then run the interview below.

Interview the user to build a complete requirements picture. Ask about:

1. **Core mechanic / feature purpose** — what does it do? What problem does it solve?
2. **Target platform** — PC (Windows/macOS/Linux), console (PS5/Xbox), or both? What is the min-spec target?
3. **Performance constraints** — target FPS? Memory budget? Draw call limit?
4. **Unity subsystems involved** — physics? UI? animation? audio? networking?
5. **Integration points** — what existing systems does this touch?
6. **Acceptance criteria** — how do we know it's done? What should we test?

Produce a **Requirements Summary** with all answers consolidated. Ask the user to confirm before proceeding.

If the user provided a detailed description in `$ARGUMENTS` and the requirements are clear, you may present the summary directly for confirmation rather than asking each question individually.

## Phase 2: Plan

Based on confirmed requirements:

1. **Scan the project** — read CLAUDE.md, find relevant existing scripts, map assembly structure
2. **Identify subsystems** — which Unity packages and skills are involved?
3. **Assess complexity** — a single-file change with no new types is simple; a change
   introducing a new Model/System/View split, a new VContainer registration, or
   cross-system messaging is not. Route simple work directly; take non-trivial work
   through Plan and Verify.
4. **Choose execution strategy** based on complexity:
   - **Default** → `unity-coder` (opus) — full architectural reasoning
   - **Specialized** → route to domain agent: `unity-prototyper`, `unity-ui-builder`
5. **Generate implementation plan**:
   - Scripts to create/modify (with file paths and assembly placement)
   - Scene changes needed (GameObjects, components, physics layers)
   - Dependencies on existing systems
   - Risk areas (serialization, platform-specific, performance)
   - Estimated complexity and chosen agent tier with rationale

Present the plan to the user and wait for approval before executing.

## Phase 3: Execute

Follow the approved plan:

1. **Route to the appropriate agent(s)** based on the plan
2. **Write C# code** following all rules in `.claude/rules/`
3. **Set up scene elements** via MCP if needed (`batch_execute` for speed)
4. **Check console** via `read_console` after each major step for compilation errors
5. If errors are found, fix them before proceeding

Report progress at natural milestones (e.g., "Scripts written, setting up scene now...").

## Phase 4: Verify

Perform a verify-fix loop directly:

1. **Review** — invoke the `unity-reviewer` agent (read-only) against all changed files
2. **Auto-fix** issues that are safe to fix automatically
3. **Re-verify** if fixes were applied (max 3 iterations)
4. **Run tests** via MCP if available

### Deslop Pass

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

### Final Summary

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

## Design Principles

- **Each phase gate requires user confirmation** — never skip ahead
- **Prefer existing patterns** — match the project's established conventions
- **Minimal viable implementation** — don't overbuild on the first pass
- **Verify everything** — the verify phase is not optional

## Suggest next

When this command finishes, name the next step and offer it. Do not take it.

Already verifies in Phase 4. Offer `/unity-test` if no test was written, and say plainly what still needs a human.
