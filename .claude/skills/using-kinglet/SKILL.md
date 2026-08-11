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
| Kinglet was just installed and `CLAUDE.md` still has unfilled `FILL:` markers | `/unity-init` |
| The request is vague and has no file, type, or acceptance criterion | `unity-brainstorming` — ask, do not guess |
| Anything to build in this project — a whole feature or one scoped addition | `unity-brainstorming`, then `unity-planning`. Depth scales the round, not the chain |
| A written plan handed over to be executed | `unity-planning` first — it adopts the plan and records how it runs |
| A written plan to execute, task by task, with review between | `subagent-driven-implementation` |
| A plan small enough to execute inline, in this session | `unity-execution` |
| A mechanic to try, in a new throwaway scene | `/unity-prototype` |
| Something is broken and the cause is not yet known | `systematic-debugging`, then `/unity-fix` |
| Code was just written and is not yet verified | `verification-before-completion`, then `/unity-review` or `/unity-test` |
| A performance complaint, or a "how is performance" check | `/unity-optimize` |
| A UI screen, or a scene to build | `/unity-ui`, `/unity-scene` |
| The setup itself may be wrong | `/unity-doctor` |

A question that the rules already answer needs no surface. Answer it.

`unity-brainstorming`, `systematic-debugging` and `verification-before-completion` each carry a "the
thought that means you are about to…" section — read it when the situation feels like an exception,
because that feeling is what it names. `unity-brainstorming`'s is titled for its own failure mode:
**the thought that means you are about to treat vague as clear**.

What `unity-brainstorming` does not keep is a *list* of exemptions. It has exactly one — a throwaway
scene built to try an idea goes to `/unity-prototype` — and that choice is made before a round
starts, never from inside one.

## Offer the next step

When a unit of work finishes, name what would sensibly come next and offer it — a review after an
implementation, a test after a fix, a profile after an optimisation. **Offer; do not act.** Starting
a review nobody asked for is worse than waiting to be asked.
