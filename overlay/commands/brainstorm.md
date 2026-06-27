---
name: brainstorm
description: "Guided game-concept ideation — from zero idea to a structured game concept document under docs/design/. Uses studio ideation techniques and player-psychology frameworks."
user-invocable: true
args: genre-or-theme-hint
---
<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT — https://github.com/Donchitos/Claude-Code-Game-Studios -->

# /brainstorm — Guided Game Concept Ideation

Facilitate a collaborative ideation session and produce a complete game concept document.
You are a creative facilitator, **not** a replacement for the user's vision — ask questions at
every phase, do not generate everything silently.

## Agent & Model

- Drive this yourself (sonnet is plenty). For a senior sanity-check on pillars, you MAY spawn
  the `creative-director` agent once at the end of Phase 4 (see below) — optional, not required.
- This is a **design-layer** command: it writes Markdown to `docs/design/`. It does not write
  C# or touch the Unity Editor.

## Target

If `$ARGUMENTS` contains a genre/theme hint (e.g. `roguelike`, `cozy farming`), start there.
If `open` or empty, start from scratch.

First, **check for existing concept work** — read `docs/design/game-concept.md` if it exists
(resume, don't restart).

Use `AskUserQuestion` at every decision point (Explain → Capture): write the full creative
analysis in conversation, then capture the choice with concise labels. Studio brainstorming
principles: withhold judgment, encourage unusual ideas, build with "yes, and…", use
constraints as fuel, time-box each phase.

## Phase 1: Creative Discovery

Understand the **person**, not the game yet. Ask conversationally:

- **Emotional anchors** — a game moment that genuinely moved/thrilled them; a fantasy they've
  always wanted but never found.
- **Taste profile** — their 3 most-played games and what kept them coming back *(ask as plain
  text — let them type real titles, do NOT preset options)*; genres they love/avoid.
- **Practical constraints** — bundle into one multi-tab `AskUserQuestion` with tabs
  **"Experience"** (Challenge & Mastery / Story & Discovery / Expression & Creativity /
  Relaxation & Flow), **"Timeline"** (Weeks / Months / 1–2 years / Multi-year), **"Dev level"**
  (First game / Shipped before / Professional background).

Synthesize into a 3–5 sentence **Creative Brief** and read it back for confirmation.

## Phase 2: Concept Generation

Generate **3 distinct concepts**, each a different creative direction, using: **Verb-First
Design** (the core verb IS the game), **Mashup Method** ([Genre A] + [Theme B]), and
**Experience-First / MDA-backward** (start from the target emotion). For each: Working Title,
Elevator Pitch (passes the 10-second test), Core Verb, Core Fantasy, Unique Hook (passes the
"and also" test), Primary MDA Aesthetic, Estimated Scope, Why It Could Work, Biggest Risk.

Present all three, then capture the selection with a plain `AskUserQuestion` (prompt + options:
the three titles + "Combine elements" + "Generate fresh directions"). Never pressure a choice.

## Phase 3: Core Loop Design

For the chosen concept, build the loop with structured questions (derive options from the
concept, don't hardcode):

- **30-second loop** — core action feel; the single most important design variable for this
  concept. Then analyze: is the action intrinsically satisfying? Why (audio/visual juice,
  timing, tactical depth)?
- **5-minute loop** — what structures play into cycles; where "one more run" kicks in.
- **Session loop** (30–120 min) — what a full session looks like; natural stopping points; the
  hook that lingers after play.
- **Progression loop** (days/weeks) — how the player grows; the long-term goal.
- **Player motivation** (SDT) — Autonomy, Competence, Relatedness for this concept.

## Phase 4: Pillars and Boundaries

Collaboratively define **3–5 pillars** (each with a name, one-sentence definition, and a design
test: "if we're debating X vs Y, this pillar says we choose ___"). Pillars should create
tension with each other. Then define **3+ anti-pillars** ("We will NOT do [thing] because it
would compromise [pillar]").

Confirm with `AskUserQuestion` ("Do these pillars feel right?" → Lock in / Reframe one / Swap
one / Something else) and repeat until locked.

**Optional senior review:** once pillars are locked, you MAY spawn the `creative-director`
agent via the `Agent` tool, passing the full pillar set, anti-pillars, core fantasy, and unique
hook, and ask for a verdict (APPROVE / CONCERNS / REJECT) plus notes. Present its feedback and
let the user decide whether to revise. Skip this for a fast solo pass — it is not a gate.

## Phase 5: Player Type Validation

Using Bartle + Quantic Foundry: who will LOVE this game (primary type), who else might enjoy it
(secondary), who it is NOT for, and whether successful comparable games serve a similar audience.

## Phase 6: Scope and Feasibility

Ground the concept: **target platform** — capture with `AskUserQuestion` (PC (Steam/Epic) /
Console / PC + Console). *(This overlay is PC/console-focused; do not steer toward mobile.)*
The engine is **Unity 6 / C#** with the VContainer + MessagePipe + UniTask architecture — that
is fixed, so don't re-litigate the engine. Then cover: art style and labor, content scope
(level/item counts, hours), **MVP definition** (the minimum build that tests "is the core loop
fun?"), biggest risks (technical/design/market), and **scope tiers** (full vision vs. what ships
if time runs out).

## Generate the Document

Build the game concept using the template at `.claude/templates/game-concept.md`. Fill ALL
sections from the conversation (MDA analysis, player-motivation profile, flow design, pillars,
core loop, MVP, scope tiers, risks).

Ask with `AskUserQuestion`: "May I write it to `docs/design/game-concept.md`?" If the user wants
revisions first, ask which section, revise, re-confirm, then write (creating `docs/design/` if
needed).

## Output & Next Steps

Summarize the chosen concept: elevator pitch, pillars, primary player type, biggest risk, and
file path. Then suggest next steps in order:

1. `/design-review docs/design/game-concept.md` — validate concept completeness.
2. `/map-systems` — decompose the concept into systems with dependencies and a design order.
3. `/design-system [first-system]` — author per-system GDDs in dependency order.
4. For an unproven core mechanic, prototype it in-engine first with ECU's `/unity-prototype`
   before committing to full GDDs.

**Context note:** this is a long multi-phase command. The concept document persists on disk —
if context gets tight, the user can continue in a fresh session; progress is not lost.
