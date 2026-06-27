---
name: map-systems
description: "Decompose a game concept into individual systems, map dependencies, prioritize design order, and write the systems index under docs/design/."
user-invocable: true
args: next-or-system-name
---
<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT — https://github.com/Donchitos/Claude-Code-Game-Studios -->

# /map-systems — Decompose Concept into Systems

Turn the game concept into a dependency-ordered systems index. This is the creative bridge
between "what is the game" and "design each system."

## Modes

- **No argument** — run the full decomposition workflow (Phases 1–5) to create/update the index.
- **`next`** — pick the highest-priority undesigned system from the index and hand off to
  `/design-system`.

This is a **design-layer** command — it writes Markdown to `docs/design/`, no code, no editor.
Use `AskUserQuestion` (Explain → Capture) at every decision point.

## Phase 1: Read Concept (required)

Read `docs/design/game-concept.md` — **fail with a clear message if missing**: "No game concept
found at `docs/design/game-concept.md`. Run `/brainstorm` first." Optionally read
`docs/design/systems-index.md` (resume if it exists) and glob `docs/design/*.md` to see which
system GDDs already exist. If the index already exists, present current status and ask whether
to update it, design the next system, or revise priorities.

## Phase 2: Systems Enumeration (collaborative)

- **Extract explicit systems** from the concept's Core Mechanics, Core Loop, Technical
  Considerations, and MVP sections.
- **Identify implicit systems** each explicit one implies (e.g. "Inventory" implies item
  database, equipment slots, capacity rules, inventory UI, save serialization; "Combat" implies
  damage calc, health, hit detection, status effects, enemy AI, combat UI, death/respawn).
  Explain in conversation why each implicit system is needed.
- **User review** — present the enumeration by category (name, category, 1-sentence description,
  explicit vs. inferred) and ask: missing systems? combine/split? anything this game does NOT
  need? Iterate until approved.

## Phase 3: Dependency Mapping (collaborative)

Map each system's dependencies (input/output, structural, UI-on-gameplay). Sort into layers:
**Foundation** (zero deps), **Core** (deps on Foundation only), **Feature**, **Presentation**
(UI/feedback wrappers), **Polish** (meta/tutorial/accessibility). Detect circular dependencies
and propose resolutions (interface abstraction, simultaneous design, contract definition).
Present the layered map, highlight bottleneck systems (many dependents = high risk) and leaf
nodes, and confirm the ordering with the user.

> **Architecture note:** in this project, cross-system dependencies are wired with **VContainer**
> and cross-system communication goes through **MessagePipe** (no singletons, no static event
> buses) — per ECU's `architecture` rule. Keep that in mind when judging boundaries; for a
> deeper technical sign-off, the user can consult the `technical-director` agent.

## Phase 4: Priority Assignment (collaborative)

Auto-assign each system to a tier — **MVP** (concept's required features + their Foundation
deps), **Vertical Slice** (one complete area), **Alpha** (remaining gameplay), **Full Vision**
(polish/meta) — then present a table and ask the user to adjust. In the "why" reasoning, connect
to player experience, not just technical necessity (e.g. "Required for the core loop — without
it, placement decisions have no consequence (Pillar 2)"). Then combine dependency sort + tier
into the final **design order**.

## Phase 5: Create Systems Index (write)

Using the template at `.claude/templates/systems-index.md`, populate enumeration, dependency
map, design order, high-risk systems, and the progress tracker (all "Not Started" unless GDDs
exist). Present a summary (counts by category, MVP count, first 3 in design order, high-risk
items) and ask: "May I write the systems index to `docs/design/systems-index.md`?" Write only
after approval.

## Phase 6: Design Individual Systems (handoff)

When the user wants to start (or runs `/map-systems next` or `/map-systems [system-name]`),
select the system (named, or highest-priority undesigned by design order) and hand off to
`/design-system [system-name]`. **Do not duplicate the `/design-system` workflow here** — this
command owns the *index*; `/design-system` owns individual *GDDs*. After each GDD, offer to
continue to the next system or stop.

## Next Steps

- `/design-system [first-system-in-order]` — author the first GDD.
- `/map-systems next` — always pick the highest-priority undesigned system automatically.
- `/design-review docs/design/[system].md` — validate each GDD after authoring.
