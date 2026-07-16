<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT — https://github.com/Donchitos/Claude-Code-Game-Studios -->
<!-- cloud-nine-unity systems index (output of /map-systems). Authored copy goes to docs/design/systems-index.md. -->

# Systems Index: [Game Title]

> **Status**: [Draft / Under Review / Approved]
> **Created**: [Date]
> **Last Updated**: [Date]
> **Source Concept**: docs/design/game-concept.md

---

## Overview

[One paragraph explaining the game's mechanical scope. What kinds of systems does this game need?
Reference the core loop and pillars so any reader understands the big picture.]

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | [e.g., Player Controller] | Core | MVP | [Not Started / In Design / In Review / Approved / Implemented] | [docs/design/player-controller.md or "—"] | [Input System, Physics] |
| 2 | [e.g., Camera System] | Core | MVP | Not Started | — | Player Controller |

[Add a row per identified system. Mark inferred systems (not explicit in the concept) with
"(inferred)".]

---

## Categories

| Category | Description | Typical Systems |
|----------|-------------|-----------------|
| **Core** | Foundation everything depends on | Player controller, input, physics, camera, scene management, state machine |
| **Gameplay** | The systems that make the game fun | Combat, AI, movement abilities, interaction |
| **Progression** | How the player grows over time | XP/leveling, skill trees, unlocks, achievements |
| **Economy** | Resource creation and consumption | Currency, loot, crafting, shops, item database, drop tables |
| **Persistence** | Save state and continuity | Save/load, settings, profile management |
| **UI** | Player-facing displays | HUD, menus, inventory screen, map, notifications |
| **Audio** | Sound and music systems | Music manager, SFX bus, ambient, adaptive music |
| **Narrative** | Story and dialogue delivery | Dialogue system, quest tracking, journal, lore entries |
| **Meta** | Outside the core game loop | Tutorials/onboarding, accessibility options |

[Remove categories that don't apply; add custom ones if needed.]

---

## Priority Tiers

| Tier | Definition | Target Milestone | Design Urgency |
|------|------------|------------------|----------------|
| **MVP** | Required for the core loop to function | First playable prototype | Design FIRST |
| **Vertical Slice** | Required for one complete, polished area | Vertical slice / demo | Design SECOND |
| **Alpha** | All features in rough form, placeholder content OK | Alpha milestone | Design THIRD |
| **Full Vision** | Polish, edge cases, content-complete | Beta / Release | Design as needed |

---

## Dependency Map

### Foundation Layer (no dependencies)
1. [System] — [why it's foundational]

### Core Layer (depends on foundation)
1. [System] — depends on: [list]

### Feature Layer (depends on core)
1. [System] — depends on: [list]

### Presentation Layer (depends on features)
1. [System] — depends on: [list]

### Polish Layer (depends on everything)
1. [System] — depends on: [list]

> **Architecture note:** dependencies are wired with VContainer; cross-system communication uses
> MessagePipe (no singletons / static event buses) per ECU's `architecture` rule.

---

## Recommended Design Order

| Order | System | Priority | Layer | Agent(s) | Est. Effort |
|-------|--------|----------|-------|----------|-------------|
| 1 | [First system] | MVP | Foundation | game-designer | [S/M/L] |
| 2 | [Second system] | MVP | Foundation | systems-designer | [S/M/L] |

[Effort: S = 1 session, M = 2–3 sessions, L = 4+ sessions. A "session" is one focused design
conversation producing a complete GDD. Agents are this overlay's design agents — game-designer,
systems-designer, level-designer, narrative-director.]

---

## Circular Dependencies

- [None found] OR
- [System A ↔ System B: description and proposed resolution (interface, simultaneous design, contract)]

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| [System] | [Technical / Design / Scope] | [What could go wrong] | [Prototype in-engine via /unity-prototype, research, or scope fallback] |

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | [N] |
| Design docs started | [N] |
| Design docs reviewed | [N] |
| Design docs approved | [N] |
| MVP systems designed | [N / total MVP] |

---

## Next Steps

- [ ] Review and approve this enumeration
- [ ] Design MVP-tier systems first: `/design-system [system-name]`
- [ ] `/design-review docs/design/[system].md` on each completed GDD
- [ ] Prototype the highest-risk systems in-engine (`/unity-prototype`) before committing
