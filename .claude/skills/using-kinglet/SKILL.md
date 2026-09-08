---
name: using-kinglet
description: "Use at the start of every session in a Unity project — establishes which Kinglet surface handles which situation, and that a process surface is chosen before code is written."
---

# Using Kinglet

Kinglet is a Unity 6 PC/console toolkit. Five rules in `.claude/rules/` bind: `architecture.md`,
`csharp-unity.md`, `performance.md`, `serialization.md`, `unity-specifics.md`. `pc-console.md` adds
platform specifics on top; it does not override them.

**Whether they are in front of you depends on the client, and this is the one line in this file that
is not the same for both.** Under **Claude Code** the rule files load automatically — they are
already in context and you do not open them. Under **Codex CLI** nothing loads them: measured on
`codex-cli 0.145.0`, `.claude/rules/` was opened **0 times in 24 runs** without an explicit pointer,
and the failure mode was not "no conventions" but confidently wrong ones. **If you are on Codex —
you are, if the injected entry document you were given is `AGENTS.md` rather than `CLAUDE.md` — read
the rule file that covers what you are about to do before you do it.**

**Which of those rules apply to this project is stated in the generated block** — in `CLAUDE.md`
under Claude Code, in `AGENTS.md` under Codex. Both files carry one and both are readable; only the
client's own is injected. It is detected from the project's own code, not assumed. Read it before
asserting that a rule binds. `AGENTS.md` also carries the one translation the chain below needs
there: Codex has no slash-command surface, so every `/name` is a skill of that name — read it, do
not skip it.

## The rule

Invoke the surface **before any response or action** — including clarifying questions, reading files,
and exploring the code. Then announce `Using [skill] to [purpose]` and follow it. If it turns out
wrong for the situation, route to the right surface — but you have to have looked, and "wrong
surface" never means "no surface". A surface that states it has no opt-out is not made optional by
this line.

## The chain

| Situation | Surface |
|---|---|
| Kinglet was just installed and `CLAUDE.md` still has unfilled `FILL:` markers | `/unity-init` |
| Anything to build in this project — a whole feature or one scoped addition | `unity-brainstorming`, then `unity-planning` |
| A tweak — a named field or value in something that already works | `verification-before-completion` |
| A written plan handed over to be executed | `unity-planning` first |
| A written plan to execute, task by task, with review between | `subagent-driven-implementation` |
| A plan small enough to execute inline, in this session | `unity-execution` |
| A mechanic to try, in a new throwaway scene | `/unity-prototype` |
| Something is broken and the cause is not yet known | `systematic-debugging`, then `/unity-fix` |
| Code was just written and is not yet verified | `verification-before-completion`, then `/unity-review` or `/unity-test` |
| A performance complaint, or a "how is performance" check | `/unity-optimize` |
| Building the UI screen or scene an approved design already specifies | `/unity-ui`, `/unity-scene` |
| The setup itself may be wrong | `/unity-doctor` |

A question about what the rules already state is answered from the rules — that is not work, and it
selects no surface. A request to build, change, or fix something is work, and work always selects a
surface.

`unity-brainstorming`, `systematic-debugging` and `verification-before-completion` each carry a "the
thought that means you are about to…" section — read it when the situation feels like an exception,
because that feeling is what it names. `unity-brainstorming`'s is titled for its own failure mode:
**the thought that means you are about to treat vague as clear**.

What `unity-brainstorming` does not keep is a *list* of exemptions. It has exactly one — a throwaway
scene built to try an idea goes to `/unity-prototype` — and that choice is made before a round
starts, never from inside one.

## The thoughts that mean you are about to skip a surface

| Thought | Reality |
|---|---|
| "This request is already clear" | That judgment is made by a model that has just read six rule files and a generated block. It is exactly the one miss that was measured. |
| "The table already tells me what to do" | The table names the file. It is not the file. Twice, the chain was executed without ever loading it. |
| "I am resuming from a ledger, the decision is made" | A ledger records the **mode**. It does not record the design of a new task. |
| "I remember this skill" | You have read this block at the start of every session, and the skill perhaps once. Confidence that strong is evidence of the block, not of the skill. |
| "Let me look at the code first" | The surface is the thing that tells you how to look at it. |

## Offer the next step

When a unit of work finishes, name what would sensibly come next and offer it — a review after an
implementation, a test after a fix, a profile after an optimisation. **Offer; do not act.** Starting
a review nobody asked for is worse than waiting to be asked.
