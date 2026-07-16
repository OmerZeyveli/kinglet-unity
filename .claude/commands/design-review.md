---
name: design-review
description: "Reviews a game design document for completeness, internal consistency, implementability, and adherence to the project's design standards. Run before handing a GDD to implementation."
user-invocable: true
args: path-to-design-doc
---
<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT — https://github.com/Donchitos/Claude-Code-Game-Studios -->

# /design-review — Review a Game Design Document

Review a GDD and produce a verdict: **APPROVED / NEEDS REVISION / MAJOR REVISION NEEDED**. This
is read-only analysis through Phase 4 (no files written). Design-layer only.

## Depth

By default, run the full review including specialist agents (Phase 3b). If `$ARGUMENTS` contains
`--lean`, run all phases except specialist delegation (faster, single-session). Strip the flag
before treating the rest of the argument as the document path.

## Phase 1: Load Documents

Read the target GDD in full. Read the project CLAUDE.md for context/standards. Read related GDDs
(glob `docs/design/`). **Dependency-graph validation:** for every system in the Dependencies
section, check via Glob whether its GDD exists in `docs/design/` — flag broken references.
**Lore/pillar alignment:** if `docs/design/game-concept.md` or narrative docs exist, read them
and note any mechanical choice that contradicts established tone, world rules, or pillars.

## Phase 2: Completeness Check

Evaluate against the 8-section standard: Overview, Player Fantasy, Detailed Rules, Formulas
(math defined with variables), Edge Cases, Dependencies, Tuning Knobs, Acceptance Criteria.
List missing sections as `[X/8]`.

## Phase 3: Consistency & Implementability

- **Internal consistency** — formulas match described behavior; edge cases don't contradict
  main rules; dependencies are bidirectional.
- **Implementability** — rules precise enough to implement without guessing; no hand-wave
  sections; performance implications considered; tuning values are externalized (not hardcoded)
  per the project's architecture.
- **Cross-system consistency** — no conflict with existing mechanics; no unintended
  interactions; consistent with established tone and pillars.

## Phase 3b: Adversarial Specialist Review (default; skip with `--lean`)

Before spawning, print: "Full review: spawning specialist agents in parallel — this takes a few
minutes. Use `--lean` for a faster single-session analysis."

Identify the domains the GDD touches and spawn the relevant design agents **in parallel** via
the `Agent` tool (issue all calls at once — these are real subagents, do NOT simulate them):

| If the GDD contains… | Spawn |
|----------------------|-------|
| Any gameplay system / player-facing rules | `game-designer` (baseline) |
| Formulas or system-interaction rules | `systems-designer` (baseline) |
| Level layout, encounters, spawning | `level-designer` |
| Dialogue, quests, story, lore | `narrative-director` |
| Architecture / performance / feasibility concerns | `technical-director` |

Prompt each adversarially: "Your job is NOT to validate this design — find problems. Challenge
it from your domain. What is wrong, underspecified, likely to cause problems, or missing?"
- `game-designer`: anchor to the stated Player Fantasy — does the design deliver that feeling?
- `systems-designer`: plug boundary values into every formula — report degenerate outputs
  (negative, divide-by-zero, infinity, nonsense at extremes).

Then spawn `creative-director` as **senior reviewer**: pass the GDD, all specialist findings,
and any disagreements; ask for a synthesis and an overall verdict (its first-line verdict token
becomes the final verdict). Surface specialist disagreements explicitly — do not silently
resolve them. Tag every finding with its source, e.g. `[systems-designer]`.

## Phase 4: Output Review

```
## Design Review: [Document Title]
Specialists consulted: [list]

### Completeness: [X/8 sections present]
[missing sections]

### Dependency Graph
[each declared dependency and whether its GDD exists on disk]

### Required Before Implementation
[blocking issues only — source-tagged]

### Recommended Revisions
[important but non-blocking — source-tagged]

### Specialist Disagreements
[present both sides — do not resolve silently]

### Senior Verdict [creative-director]
[synthesis]

### Scope Signal: [S / M / L / XL]
(based on dependency count, formula count, systems touched, new ADRs likely)

### Verdict: [APPROVED / NEEDS REVISION / MAJOR REVISION NEEDED]
```

## Phase 5: Next Steps

Use `AskUserQuestion` to close:
- If NEEDS REVISION / MAJOR REVISION: offer to revise blocking items now (batch design questions
  into one multi-tab question, then apply edits and show a blocker→fix summary), or revise later.
- If APPROVED: offer to update the system's status in `docs/design/systems-index.md`, then point
  to the next system (`/design-system [next]`) or to implementation (ECU's `/unity-feature`).
