---
name: design-system
description: "Guided, section-by-section GDD authoring for a single game system. Gathers context from existing docs, walks each required section collaboratively, cross-references dependencies, and writes incrementally to docs/design/."
user-invocable: true
args: system-name
---
<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT — https://github.com/Donchitos/Claude-Code-Game-Studios -->

# /design-system — Author One System's GDD

Author a complete, implementable GDD for one system, one section at a time. This command's
advantage over ad-hoc design is that it arrives **informed** — it reads all relevant context
first. Design-layer only: writes Markdown to `docs/design/`, no code, no editor.

## 1. Parse Arguments & Validate

A system name is required. If missing: read `docs/design/systems-index.md`, find the
highest-priority "Not Started" system, and ask (via `AskUserQuestion`) whether to design it,
pick another, or stop. If no index exists, fail with: "No systems index found. Run
`/map-systems` first." Normalize the system name to kebab-case for the filename.

**Retrofit mode:** if the argument is a path to an existing GDD (or starts with `retrofit`),
read the file, detect which of the 8 required sections are missing or placeholder-only, list
them for the user, and fill ONLY the missing sections — never overwrite existing content (use
Edit to replace `[To be designed]` placeholders).

## 2. Gather Context (read first)

- **Required:** `docs/design/game-concept.md` (fail if missing → "Run `/brainstorm` first") and
  `docs/design/systems-index.md` (fail if missing → "Run `/map-systems` first"). Find the
  target system in the index.
- **Dependencies:** from the index, read the GDDs of upstream dependencies (decisions this
  system must respect) and downstream dependents (expectations it must satisfy). Extract their
  key interfaces, formulas, edge cases, and tuning knobs.
- **Optional:** `docs/design/game-pillars.md`, an existing GDD for this system (resume), and any
  thematically related GDDs (glob `docs/design/*.md`).
- **Cross-system facts:** scan dependency GDDs for any value/entity/formula this system must not
  contradict. Hold these as **locked facts** — if this GDD needs a different number, surface the
  conflict before writing; do not silently diverge.

Present a brief **context summary** (priority/layer, depends-on, depended-on-by, decisions to
respect, pillar alignment, locked cross-system facts). Warn about any undesigned upstream
dependency. Then ask (via `AskUserQuestion`): "Ready to start designing [system-name]?"

## 3. Create File Skeleton

Once confirmed, immediately create the GDD file from the template at
`.claude/templates/game-design-document.md` with all section headers present and bodies marked
`[To be designed]`. This gives incremental writes a target.

## 4. Section-by-Section Design

Walk the 8 required sections **one at a time** (skip completed ones in retrofit mode). For each
section: discuss in conversation, present options where there are choices (`AskUserQuestion`,
Explain → Capture), draft the section, get approval, then write it to file before moving on.

- **Overview** — what the system is, in plain language.
- **Player Fantasy** — what the player should FEEL (the emotional target driving all detail).
- **Detailed Design** (Core Rules / States & Transitions / Interactions) — precise enough for a
  programmer to implement without guessing.
- **Formulas** — named expression, variable table (symbol/type/range/description), output range,
  worked example. For complex math, spawn the `systems-designer` agent (`Agent` tool) for the
  formula work.
- **Edge Cases** — unusual/extreme situations with explicit resolutions.
- **Dependencies** — every system this depends on or that depends on it, with direction.
- **Tuning Knobs** — adjustable values, ranges, and what happens at the extremes. These target
  **ScriptableObjects / external config — never hardcoded** (ECU `serialization` + `architecture` rules).
- **Acceptance Criteria** — testable functional AND experiential criteria. For testability, you
  MAY spawn `systems-designer` to validate that criteria are independently verifiable.

Optional sections (Visual/Audio Requirements, Game Feel, UI Requirements) apply when relevant —
the Game Feel section's input-latency and frame-budget targets matter for PC/console responsiveness.

## 5. Post-Design Validation

- Self-check that all 8 sections are complete.
- **Optional senior review:** spawn the `creative-director` agent for a pillar-alignment verdict
  (APPROVE / CONCERNS / REJECT) — skip for a fast solo pass; it is not a gate.
- Update `docs/design/systems-index.md` to mark this system's status.
- Offer to run `/design-review docs/design/[system].md` in a fresh session for a full review.

## Next Steps

- `/design-review docs/design/[system].md` — validate the finished GDD.
- `/map-systems next` — move to the next system in design order.
- When the GDD is approved, hand it to ECU's `/unity-feature` to implement.
