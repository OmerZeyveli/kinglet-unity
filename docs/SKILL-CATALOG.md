# Skill Catalog

One-page reference for all skills in Kinglet Pioneer.

---

## Overview

16 skills, one directory each at `.claude/skills/<name>/SKILL.md`. The model selects one by reading
its `description` and invoking it with the `Skill` tool. That is the whole mechanism — there is no
glob matching, no preloading, and no always-apply.

The 2026-08-03 surface cut reduced the skill set from 39 (already flat, per the correction below) to
13: a skill survives only if it does something the model cannot do unaided. Ten are ECU-origin,
rewritten for an agent reader; three (`systematic-debugging`, `using-kinglet`,
`verification-before-completion`) are original, written in the same wave to carry the process chain —
see `provenance.tsv`. A fourteenth, `subagent-driven-implementation`, was added afterward in the same
wave that built the execution loop it documents — see below. The 2026-08-10 process-chain wave added
two more, `unity-planning` and `unity-execution`, and renamed the discovery skill to
`unity-brainstorming`: the chain that used to be sequenced by a command is now skills that name each
other, and the two commands that only sequenced them were deleted. The rename's full history — every
note clause, oldest first — is in `MERGE-NOTES.md` under "unity-brainstorming ... the full note
history".

**Correction (2026-08-03) — the important one.** Every skill in this catalog was once unreachable for
the toolkit's entire life. They were filed under `core/`, `gameplay/`, `genre/`, `systems/` and
`third-party/`, inherited from everything-claude-unity, and Claude Code only discovers skills one
level deep. Nothing was registered; the `Skill` tool could not invoke a single entry below. An
eight-hour Endless-Evolution session on 2026-08-02 used zero skills, which read as the model
declining them and was not.

The measurement, in an empty project: `.claude/skills/flatprobe/SKILL.md` is listed in the session's
skill inventory; `.claude/skills/category/nestedprobe/SKILL.md` is not. The layout is now flat and
`tests/test-skill-discovery.sh` keeps it that way.

**Correction (2026-07-30), superseded in part.** A probe found `alwaysApply: true` inert — nothing in
this repository reads it — and concluded the nine skills it marked were "selected by description like
every other skill." The mechanism was right; the conclusion was too generous. They could not be
selected at all. That probe's own evidence says so in hindsight: the model answered the
`commit-trailers` question only after it *searched for and read the file*, which is what you do when
a skill is not invocable. Both `alwaysApply` and `globs` have been stripped from every skill.

---

## Skills That Formerly Carried `alwaysApply: true`

These were marked as if they loaded unconditionally. They never did, and the key is now gone. Where
content genuinely must reach every session, the right home is `.claude/rules/`, not a skill —
`alwaysApply` reads as a guarantee and controls nothing. Some of the skills originally marked this way
were themselves cut in the 2026-08-03 surface reduction (`commit-trailers`, `model-routing`,
`event-systems`, `scriptable-objects`); the ones that survived are listed below, alongside the current
mechanism that replaces the dead key: naming them explicitly in an agent's **Skills to load** block —
see `.claude/agents/unity-coder.md` for the shape.

| Skill | Description |
|-------|-------------|
| `assembly-definitions` | Assembly definition management -- when to create asmdefs, reference rules, Editor/Runtime/Test separation, platform filters, compilation speed optimization. |
| `unity-mcp-patterns` | Activating unity-mcp tool groups, `batch_execute` for speed, `read_console` for verification, resource queries for project state. |
| `object-pooling` | Object pooling patterns -- Unity `ObjectPool<T>`, custom ComponentPool, warm-up strategies, return-to-pool lifecycle. |
| `unity-brainstorming` | Ambiguity gating -- detects vague feature requests and forces structured requirements gathering before planning or code. Renamed on 2026-08-10; see `MERGE-NOTES.md`. |

---

## Current Skills (16, flat)

No categories — Claude Code only discovers `.claude/skills/<name>/SKILL.md`, one level deep, so the
old `core/` / `gameplay/` / `genre/` / `systems/` / `third-party/` split shown in the corrections above
is history, not a live grouping. Loosely by subject, for a maintainer's orientation only:

| Skill | Description |
|-------|-------------|
| `addressables` | Addressables asset loading -- `LoadAssetAsync`, handle lifecycle, labels, remote catalogs, memory management. |
| `assembly-definitions` | Assembly definition management -- when to create asmdefs, reference rules, Editor/Runtime/Test separation, platform filters, compilation speed. |
| `input-system` | New Input System -- action maps, `PlayerInput` component, generated C# classes, runtime rebinding, multi-device support, input buffering. |
| `object-pooling` | Object pooling patterns -- Unity `ObjectPool<T>`, custom `ComponentPool`, warm-up strategies, return-to-pool lifecycle. |
| `physics` | Unity physics -- non-allocating queries, collision layers, FixedUpdate discipline, continuous collision detection, character controllers, joints. |
| `save-system` | Save/load patterns -- `ISaveable` interface, JSON serialization, save file management, scene persistence, cloud sync prep. |
| `state-machine` | Generic state machine patterns -- `IState` interface, `StateMachine<T>`, game state management, enemy AI states, hierarchical FSM. |
| `unity-mcp-patterns` | Activating unity-mcp tool groups (only core is on by default), `batch_execute` for speed, `read_console` for verification, resource queries for project state. |
| `urp-pipeline` | Universal Render Pipeline -- URP asset configuration, renderer features, 2D renderer, lighting, shadows, post-processing volumes, SRP Batcher. |
| `unity-brainstorming` | The chain's entry point. Ambiguity gating for anything new -- e.g. "add a jump," "make an inventory system" -- then 2-3 approaches weighed and the chosen one written to `docs/features/<slug>/design.md`, before a plan exists or C# is touched. **(process chain, 2026-08-10; renamed in that wave)** |
| `unity-planning` | Turns a design decision, a written spec, or an adopted plan path into a task-by-task plan at `docs/features/<slug>/plan.md`, and is where the execution branch is chosen and recorded. **(process chain, 2026-08-10)** |
| `unity-execution` | Executes an approved plan inline, in this session, with a bounded verify loop and the Deslop Pass. The other branch of `unity-planning`'s fork. **(process chain, 2026-08-10)** |
| `systematic-debugging` | For a bug whose cause is not yet known -- read the real console, reproduce, inspect the live API, then change one thing, before proposing a fix. **(process chain, Task 5)** |
| `using-kinglet` | Session-start orientation -- which Kinglet surface handles which situation, and that a process surface is chosen before code is written. **(process chain, Task 5)** |
| `verification-before-completion` | What counts as evidence a code change works, before reporting it done -- a claim without evidence is not a completion. **(process chain, Task 5)** |
| `subagent-driven-implementation` | Executes a written plan task by task, a fresh implementer per task with a review gate before the next one starts. One of the two branches `unity-planning` forks to; `unity-execution` is the other. |

### Removed in the 2026-08-03 surface cut

Everything else that appeared in earlier drafts of this catalog — the mobile skill and mobile genres,
the remaining gameplay/genre/systems/third-party entries, and the `alwaysApply`-marked skills not
listed above — was cut on the same criterion: a surface survives only if it does something the model
cannot do unaided. `provenance-skip.tsv` has the full list and the reasoning for each.

---

## How Skills Are Loaded

One way, and only one: the model invokes the `Skill` tool with the skill's name.

Two things have to be true for that to happen. The skill must be **discoverable** — flat at
`.claude/skills/<name>/SKILL.md`, or it is not registered and the tool cannot name it. And it must be
**reachable** — the agent needs `Skill` in its `tools:` frontmatter, and something has to prompt it to
load that particular skill. The agents carry a **Skills to load** block naming the two to four they
would otherwise never think of; the `Skill` tool's own listing covers the rest.

Both conditions failed silently until 2026-08-03: no error, no warning, no missing file. That is why
`tests/test-skill-discovery.sh` checks the layout, the `name:`/directory agreement, and that every
path-form skill reference an agent names actually exists. It matches path-form references only —
`tests/test-surface-references.sh` (added in the same wave) guards the bare-name references it misses.

Skills are additive — several can be loaded at once, and they do not conflict, each covering a
distinct domain. Loading none is the failure mode that actually occurs.

---

## Creating a New Skill

Create a new directory and `SKILL.md` file:

```
.claude/skills/<skill-name>/SKILL.md
```

One level. A `SKILL.md` nested any deeper is invisible to Claude Code and will never load —
`tests/test-skill-discovery.sh` fails if one appears.

Frontmatter — these two keys and nothing else:

```yaml
---
name: skill-name
description: "When to load this skill -- be specific about the use case"
---
```

`name` must equal the directory name. `description` is the entire selection mechanism: it is what the
model reads when deciding whether this skill is relevant, so write it as *when to reach for this*, not
as a title. Do not add `alwaysApply` or `globs` — they do nothing here, and the test rejects them.

The Markdown body contains the skill's knowledge: patterns, code examples, rules, and anti-patterns. Keep skills focused on one domain. If a skill grows beyond 200 lines, consider splitting it.
