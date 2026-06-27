# cloud-nine-unity

**A PC/console design-and-production overlay for [everything-claude-unity (ECU)](https://github.com/XeldarAlz/everything-claude-unity).**

cloud-nine-unity is **not a standalone toolkit.** It is an *overlay*: you install ECU first, then
apply this on top. It adds a **game-design and production discipline** — design agents, GDD/ADR/
sprint workflows, and a PC/console rules addendum — adapted from
[Claude-Code-Game-Studios (Donchitos)](https://github.com/Donchitos/Claude-Code-Game-Studios) and
fitted to ECU's conventions. It targets the open-source
[CoplayDev Unity MCP](https://github.com/CoplayDev/unity-mcp) that ECU already wires up.

> **Honest positioning:** ECU gives you the *engineering* side (Unity coder/reviewer agents,
> `unity-*` commands, architecture rules, hooks, MCP). This overlay adds the *design & production*
> side and narrows the focus to PC/console. No "toolkit from scratch" claims — the heavy lifting is
> ECU's and Donchitos's; this glues a focused slice of them together. Built and tested against
> **ECU v1.5.0**.

---

## What's opinionated

- **PC / Console only.** Nothing mobile-specific. Keyboard/mouse + gamepad (with rebinding), no
  touch. Desktop/console performance framing (see `pc-console.md`).
- **Fixed architecture:** Unity 6 · C# · **VContainer** (DI) + **MessagePipe** (messaging) +
  **UniTask** (async) + New Input System — inherited from ECU and preserved, not re-litigated.
- **Medium-weight process.** Enough structure for a solo dev or small team; none of the heavy
  full-studio gate ceremony. Senior "creative/technical director" reviews are *optional*, not gates.
- **CoplayDev MCP only.** One MCP server (the one ECU already points at). A short migration note for
  Unity's official MCP is in `MCP-SETUP.md`, but the overlay supports one at a time.

---

## What it adds (on top of ECU)

**8 design/production agents** (a documentation layer — they write design docs to `docs/`, they do
**not** write C# or drive the editor):

| Agent | Role |
|-------|------|
| `game-designer` | Core loops, systems, progression, balance |
| `systems-designer` | Formulas, interaction matrices, economy/loot tuning |
| `level-designer` | Spatial layouts, encounters, pacing |
| `narrative-director`* | Story architecture, world direction, dialogue strategy |
| `writer`* | Dialogue, lore, item text, barks |
| `world-builder`* | Factions, history, geography, lore consistency |
| `creative-director` | Vision keeper / senior design reviewer (verdict role) |
| `technical-director` | Architecture authority / feasibility reviewer (writes ADRs) |

\* Narrative trio is **optional** — for narrative-heavy games. If your game isn't story-driven, you
can simply delete `narrative-director.md`, `writer.md`, and `world-builder.md` from
`.claude/agents/` after install. Harmless to leave in place.

**9 commands:**

| Command | What it does |
|---------|--------------|
| `/brainstorm` | Guided concept ideation → `docs/design/game-concept.md` |
| `/map-systems` | Decompose concept into systems + dependencies → `docs/design/systems-index.md` |
| `/design-system` | Section-by-section GDD authoring for one system |
| `/design-review` | Review a GDD for completeness/consistency/implementability |
| `/sprint-plan` | Plan/update/report a sprint → `docs/production/sprints/` |
| `/scope-check` | Detect and quantify scope creep (read-only) |
| `/milestone-review` | Milestone go/no-go review |
| `/estimate` | Structured effort estimate with confidence |
| `/retrospective` | Sprint/milestone retrospective with action items |

**1 rule:** `pc-console.md` — neutralizes ECU's mobile assumptions; adds PC/console input &
performance notes. ECU's rules remain the spine and **win on any conflict.**

**5 templates** (install to `.claude/templates/`): `game-design-document`,
`architecture-decision-record`, `sprint-plan`, `game-concept`, `systems-index`.

> Design and production documents are written into a `docs/` tree (`docs/design`, `docs/adr`,
> `docs/production`) **in your Unity project** — created on demand by the commands. They are not part
> of this overlay repo, and they live outside `Assets/` so Unity doesn't import them.

---

## Installation

Order matters: **ECU → overlay → MCP.**

### 1. Install ECU into your Unity project

Follow [everything-claude-unity](https://github.com/XeldarAlz/everything-claude-unity)'s own
instructions (clone it, then run its `install.sh --project-dir /path/to/your/UnityProject`). This
creates `.claude/` in your project with ECU's agents, commands, rules, hooks, and `settings.json`.

### 2. Apply this overlay

```bash
git clone https://github.com/<you>/cloud-nine-unity.git
cd cloud-nine-unity
./install.sh --project-dir /path/to/your/UnityProject
# optional: also add the CoplayDev MCP package to Packages/manifest.json
./install.sh --project-dir /path/to/your/UnityProject --with-mcp
```

`install.sh` checks that ECU is present, then copies the overlay's agents/commands/rules/templates
**next to** ECU's under `.claude/` — it **warns and skips** on any filename clash and never
overwrites. It does **not** touch ECU's `settings.json` (just verifies the MCP entry exists).

### 3. Set up the Unity MCP

Follow **[MCP-SETUP.md](MCP-SETUP.md)**: add the CoplayDev package via Package Manager git URL,
run **Window → MCP for Unity → Auto-Setup**, start the bridge, and verify from Claude Code with
*"What's in the current scene?"* (Python 3.10+ and `uv` required; **no API key**).

### Health check & uninstall

```bash
./scripts/studio-doctor.sh --project-dir /path/to/your/UnityProject   # checks Python/uv/MCP + files
./uninstall.sh --project-dir /path/to/your/UnityProject               # removes only overlay files
```

### Fill in your project

Copy `CLAUDE.md` (the end-user **template**) into your project root (or merge it into the one ECU
generated) and fill in the `FILL:` markers — genre, pillars, vision, scope. The architecture
section is fixed on purpose.

---

## A typical flow

```
/brainstorm                         → docs/design/game-concept.md
/design-review docs/design/game-concept.md
/map-systems                        → docs/design/systems-index.md
/design-system player-controller    → docs/design/player-controller.md
/design-review docs/design/player-controller.md
/unity-feature  (ECU — implements the approved GDD in the editor via MCP)
/sprint-plan new                    → docs/production/sprints/sprint-1.md
/scope-check sprint-1   ·   /retrospective sprint-1
```

---

## Compatibility note (please read)

This overlay leans on ECU's file layout: `install.sh` detects ECU via
`.claude/rules/architecture.md` + `.claude/skills/core/unity-mcp-patterns/SKILL.md`, and drops files
alongside ECU's. **ECU is actively developed** — if a future release moves or renames those files,
detection and placement may break. The overlay is pinned to and tested against **ECU v1.5.0**;
re-verify before using it with a newer ECU.

---

## Optional: removing ECU's mobile content

ECU includes a mobile skill and a couple of mobile genres. On a PC/console project they simply never
trigger, so you can ignore them. If you want a clean tree, you may delete
`.claude/skills/platform/mobile/` (and `genre/hyper-casual`, `genre/endless-runner`). This is
optional — `pc-console.md` already tells the agents to ignore mobile assumptions.

---

## Credits & License

- **License:** MIT — see [LICENSE](LICENSE).
- **Credits & third-party licenses:** [CREDITS.md](CREDITS.md). The design/production layer is
  **adapted from Donchitos** (attribution required and provided, inline + central); ECU and CoplayDev
  are integrated dependencies, credited there too.
- **Build record:** [MERGE-NOTES.md](MERGE-NOTES.md) documents exactly what was taken, adapted, and left out.

> **Support:** this is a **low-support** project — issues and PRs are welcome but may be slow. See
> [CONTRIBUTING.md](CONTRIBUTING.md) for where help is most useful (PC/console design skills,
> production commands).
