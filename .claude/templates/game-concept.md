<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT — https://github.com/Donchitos/Claude-Code-Game-Studios -->
<!-- cloud-nine-unity game concept template (output of /brainstorm). Authored copy goes to docs/design/game-concept.md. -->

# Game Concept: [Working Title]

*Created: [Date]*
*Status: [Draft / Under Review / Approved]*

---

## Elevator Pitch

> [1–2 sentences capturing the whole game. Format: "It's a [genre] where you [core action] in a
> [setting] to [goal]." Test: can someone who's never heard of it understand what they'd be doing
> in 10 seconds? If not, simplify.]

---

## Core Identity

| Aspect | Detail |
| ---- | ---- |
| **Genre** | [Primary genre + subgenre(s)] |
| **Platform** | PC / Console / PC + Console *(this is a PC/console project — no mobile)* |
| **Engine** | Unity 6 (C#), VContainer + MessagePipe + UniTask *(fixed by the project architecture)* |
| **Player Count** | [Single-player / Co-op / Multiplayer] |
| **Session Length** | [10 min / 30 min / 1 hr / 2+ hr] |
| **Estimated Scope** | [Small (1–3 months) / Medium (3–9 months) / Large (9+ months) — state team size] |
| **Comparable Titles** | [2–3 existing games in the same space] |

---

## Core Fantasy

[What power, experience, or feeling does the player get here that they can't get anywhere else?
The emotional promise — not a feature list.]

---

## Unique Hook

[The single most important differentiator. Passes the "and also" test: "It's like [comparable
game], AND ALSO [unique thing]." Explainable in one sentence, genuinely novel, connected to the
core fantasy, and affecting gameplay (not just aesthetics).]

---

## Player Experience Analysis (MDA Framework)

### Target Aesthetics (What the player FEELS)

| Aesthetic | Priority | How We Deliver It |
| ---- | ---- | ---- |
| **Sensation** (sensory pleasure) | [1–8 or N/A] | [Visual, audio, haptics] |
| **Fantasy** (make-believe) | [Priority] | [World, characters, identity] |
| **Narrative** (drama) | [Priority] | [Plot, player-driven stories] |
| **Challenge** (mastery) | [Priority] | [Difficulty curve, skill ceiling] |
| **Fellowship** (social) | [Priority] | [Co-op, shared experiences] |
| **Discovery** (exploration) | [Priority] | [Hidden areas, emergent systems, lore] |
| **Expression** (creativity) | [Priority] | [Build variety, cosmetics, creation tools] |
| **Submission** (relaxation) | [Priority] | [Low-stress loops, ambient gameplay] |

### Key Dynamics (Emergent player behaviors)

[What behaviors do we WANT to emerge from the mechanics?]

### Core Mechanics (Systems we build)

1. [Mechanic 1]
2. [Mechanic 2]
3. [Mechanic 3]

---

## Player Motivation Profile

### Primary Psychological Needs (Self-Determination Theory)

| Need | How This Game Satisfies It | Strength |
| ---- | ---- | ---- |
| **Autonomy** (meaningful choice) | [...] | [Core / Supporting / Minimal] |
| **Competence** (mastery, growth) | [...] | [Core / Supporting / Minimal] |
| **Relatedness** (connection) | [...] | [Core / Supporting / Minimal] |

### Player Type Appeal (Bartle)

- [ ] **Achievers** — How: [...]
- [ ] **Explorers** — How: [...]
- [ ] **Socializers** — How: [...]
- [ ] **Killers/Competitors** — How: [...]

### Flow State Design

- **Onboarding curve**: [How do the first 10 minutes teach the player?]
- **Difficulty scaling**: [How does challenge grow with skill?]
- **Feedback clarity**: [How does the player know they're improving?]
- **Recovery from failure**: [How fast can they retry? Punishing or educational?]

---

## Core Loop

### Moment-to-Moment (30 seconds)
[The most basic, repeated action. MUST be intrinsically satisfying in isolation.]

### Short-Term (5–15 minutes)
[The objective/cycle that structures play. Where "one more run" psychology lives.]

### Session-Level (30–120 minutes)
[What a full session looks like. Ends with a natural stopping point AND a reason to return.]

### Long-Term Progression
[How the player grows over days/weeks. What they're working toward.]

### Retention Hooks
- **Curiosity** / **Investment** / **Social** / **Mastery**: [...]

---

## Game Pillars

Non-negotiable principles that break ties between design choices. Keep to 3–5.

### Pillar 1: [Name]
[One-sentence definition.] *Design test*: [A concrete decision this pillar resolves.]

### Pillar 2: [Name]
[Definition.] *Design test*: [...]

### Pillar 3: [Name]
[Definition.] *Design test*: [...]

### Anti-Pillars (What This Game Is NOT)

- **NOT [thing]**: [Why it's excluded and what it would compromise]
- **NOT [thing]**: [Why]
- **NOT [thing]**: [Why]

---

## Inspiration and References

| Reference | What We Take | What We Do Differently | Why It Matters |
| ---- | ---- | ---- | ---- |
| [Game 1] | [...] | [Our twist] | [Validation] |

**Non-game inspirations**: [Films, books, music, art that influence tone, world, or feel.]

---

## Target Player Profile

| Attribute | Detail |
| ---- | ---- |
| **Age range** | [e.g., 18–35] |
| **Gaming experience** | [Casual / Mid-core / Hardcore] |
| **Platform preference** | [PC / Console — where they play most] |
| **Current games they play** | [2–3 specific titles] |
| **What they're looking for** | [The unmet need this game fills] |
| **What would turn them away** | [Dealbreakers] |

---

## Technical Considerations

| Consideration | Assessment |
| ---- | ---- |
| **Engine** | Unity 6 (C#) — fixed. Architecture: VContainer + MessagePipe + UniTask (see ECU rules) |
| **Key Technical Challenges** | [What's technically hard about this game?] |
| **Art Style** | [2D / 2.5D / 3D stylized / 3D realistic] |
| **Art Pipeline Complexity** | [Low / Medium / High] |
| **Audio Needs** | [Minimal / Moderate / Music-heavy / Adaptive] |
| **Input** | Keyboard/mouse + gamepad, with rebinding (PC/console — no touch; see `pc-console.md`) |
| **Networking** | [None / P2P / Client-Server / Dedicated] |
| **Content Volume** | [X levels, Y items, Z hours] |
| **Procedural Systems** | [Any procedural generation? Scope?] |

---

## Risks and Open Questions

### Design Risks / Technical Risks / Market Risks / Scope Risks
- [Risk per category — what could go wrong]

### Open Questions
- [Question — and what prototype/research would resolve it]

---

## MVP Definition

**Core hypothesis**: [The single statement the MVP tests — e.g., "Players find the core loop
engaging for 30+ minute sessions"]

**Required for MVP**:
1. [Essential feature that directly tests the hypothesis]
2. [...]

**Explicitly NOT in MVP** (defer):
- [Feature that adds scope without validating the core]

### Scope Tiers

| Tier | Content | Features | Timeline |
| ---- | ---- | ---- | ---- |
| **MVP** | [Minimal] | [Core loop only] | [X weeks] |
| **Vertical Slice** | [One complete area] | [Core + progression] | [X weeks] |
| **Alpha** | [All areas, placeholder] | [All features, rough] | [X weeks] |
| **Full Vision** | [Complete content] | [All features, polished] | [X weeks] |

---

## Next Steps

- [ ] `/design-review docs/design/game-concept.md` — validate concept completeness
- [ ] `/map-systems` — decompose the concept into systems with dependencies and a design order
- [ ] `/design-system [first-system]` — author per-system GDDs in dependency order
- [ ] For an unproven core mechanic, prototype it in-engine first with ECU's `/unity-prototype`
- [ ] `/sprint-plan new` — plan the first sprint once MVP systems are designed
