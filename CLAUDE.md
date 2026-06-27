<!--
  cloud-nine-unity — end-user CLAUDE.md TEMPLATE.

  This is a STARTING POINT for YOUR game, not a description of any specific game.
  Copy it to your Unity project root as `CLAUDE.md` (or merge it into the CLAUDE.md
  that ECU's installer generated), then fill in every `FILL:` marker below.

  The "Fixed" sections are deliberate constraints from this overlay — leave them as-is
  unless you really mean to diverge. The "Fill in" sections are yours.
-->

# [FILL: Game Title] — Project Guide

> Unity 6 · C# · PC / Console · built with everything-claude-unity (ECU) + the cloud-nine-unity overlay.

## Vision (fill in)

- **Elevator pitch:** <!-- FILL: "It's a [genre] where you [core action] in a [setting] to [goal]." -->
- **Core fantasy:** <!-- FILL: the emotional promise — what the player gets to be/do here -->
- **Unique hook:** <!-- FILL: passes the "and also" test -->
- **Genre / subgenre:** <!-- FILL -->
- **Target platforms:** <!-- FILL: PC (Steam/Epic) / Console / both — NO mobile -->
- **Primary input:** <!-- FILL: keyboard+mouse and/or gamepad (with rebinding) -->

## Pillars (fill in — 3–5, each with a design test)

<!-- FILL: run /brainstorm to generate these, then paste the locked set here.
1. **[Pillar name]** — [one-sentence definition]. Design test: if debating X vs Y, choose ___.
2. ...
Anti-pillars (what this game is NOT):
- NOT [thing], because it would compromise [pillar].
-->

## Scope (fill in)

- **Estimated scope / team size:** <!-- FILL: e.g. Medium (3–9 months), solo -->
- **MVP hypothesis:** <!-- FILL: the single question the MVP answers — "is the core loop fun?" -->
- **Current milestone:** <!-- FILL -->

---

## Engineering Stance (fixed — do not casually change)

This project uses **everything-claude-unity (ECU)** as its engineering backbone and the
**cloud-nine-unity** overlay for design/production. The architecture is opinionated and fixed:

- **Engine / language:** Unity 6, C#.
- **Architecture:** Model-View-System (MVS) with **VContainer** (DI), **MessagePipe** (cross-system
  messaging — no singletons or static event buses), **UniTask** (async — no coroutines), and the
  **New Input System** (legacy `Input.*` is blocked by ECU hooks).
- **Authoritative rules** live in `.claude/rules/` (installed by ECU + this overlay):
  - ECU: `architecture.md`, `csharp-unity.md`, `performance.md`, `serialization.md`, `unity-specifics.md`
  - Overlay: `pc-console.md` — PC/console input & performance addendum. **ECU rules win on any conflict.**
- **Platform focus:** PC / Console. No mobile-specific code, touch input, or mobile performance
  budgets (see `pc-console.md`). You may delete ECU's `.claude/skills/platform/mobile/` if you never
  ship to mobile.

## Where things go

- **Design docs** (GDDs, concept, systems index): `docs/design/`
- **Architecture decisions** (ADRs): `docs/adr/`
- **Production** (sprints, milestones, retrospectives): `docs/production/`
- **Game code:** `Assets/Scripts/` (per ECU conventions). Tuning data lives in ScriptableObjects /
  external config — never hardcoded.

## How to work

- **Design/production** (this overlay, documentation layer — no editor/code):
  `/brainstorm` → `/map-systems` → `/design-system` → `/design-review`; plan with `/sprint-plan`,
  `/estimate`, `/scope-check`, `/milestone-review`, `/retrospective`. Agents: `game-designer`,
  `systems-designer`, `level-designer`, `creative-director`, `technical-director` (+ optional
  `narrative-director`, `writer`, `world-builder`).
- **Implementation** (ECU, drives the Unity Editor via MCP): `/unity-feature`, `/unity-prototype`,
  `/unity-scene`, `/unity-test`, `/unity-review`, etc.
- **MCP:** CoplayDev Unity MCP must be running for editor control — see `MCP-SETUP.md`. Verify with
  "What's in the current scene?"

## Conventions reminder (from ECU rules — see `.claude/rules/`)

- `[SerializeField] private` for inspector fields; `_lowerCamelCase` privates; `== null` (never `?.`
  / `is null`) on Unity objects; `[FormerlySerializedAs]` on every renamed serialized field; zero GC
  allocations in `Update`/`FixedUpdate`/`LateUpdate`; cache `GetComponent` / `Camera.main`.
