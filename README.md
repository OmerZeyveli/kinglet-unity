# cloud-nine-unity

**A standalone, PC/console-focused Claude Code toolkit for Unity 6.** One repo, one installer.

It gives Claude Code two layers for your Unity project: an **engineering** layer that drives the
Unity Editor over MCP (coder, reviewer, optimizer, scene-builder agents; `/unity-*` commands; safety
hooks; architecture rules), and a **design & production** layer that writes GDDs, ADRs, and sprint
plans into `docs/`.

> **Honest positioning:** almost none of this is written from scratch. The engineering layer is
> [everything-claude-unity](https://github.com/XeldarAlz/everything-claude-unity) (MIT), vendored
> wholesale. The design layer is adapted from
> [Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) (MIT). What this
> project adds is the merge: one installer instead of two, PC/console instead of mobile, a provenance
> manifest so you can see exactly whose code is whose, and fixes to a handful of upstream defects —
> including one that destroyed your `CLAUDE.md` on re-install. See [CREDITS.md](CREDITS.md) and
> [MERGE-NOTES.md](MERGE-NOTES.md).

---

## What's opinionated

- **PC / console only.** No mobile. Keyboard/mouse + gamepad with rebinding, no touch. Desktop and
  console performance framing throughout. This is enforced by a test, not just requested.
- **Fixed architecture:** Unity 6 · C# · **VContainer** (DI) + **MessagePipe** (messaging) +
  **UniTask** (async) + New Input System. Legacy `Input.*` is blocked by a hook.
- **Medium-weight process.** Enough structure for a solo dev or small team. Senior
  "creative/technical director" reviews are optional, not gates.
- **One MCP.** The open-source [CoplayDev Unity MCP](https://github.com/CoplayDev/unity-mcp) bridge,
  preconfigured in `settings.json`. A migration note for Unity's official MCP is in
  [MCP-SETUP.md](MCP-SETUP.md), but only one at a time is supported.

## What's in the box

Installed into your project's `.claude/`:

| | Count | |
|---|---|---|
| **Agents** | 28 | 20 engineering (`unity-coder`, `unity-reviewer`, `unity-optimizer`, …) + 8 design |
| **Commands** | 36 | 27 `/unity-*` + 9 design/production |
| **Skills** | 39 | Unity subsystems, gameplay patterns, genres, third-party packages |
| **Hooks** | 25 | Safety and quality gates (5 blocking, the rest advisory) |
| **Rules** | 6 | 5 spine rules + `pc-console.md` |
| **Templates** | 5 | GDD, ADR, sprint plan, game concept, systems index |

### The design & production layer

These 8 agents are a **documentation layer** — they write design docs to `docs/`. They do not write
C# or drive the editor; the engineering agents own that.

| Agent | Role |
|-------|------|
| `game-designer` | Core loops, systems, progression, balance |
| `systems-designer` | Formulas, interaction matrices, economy/loot tuning |
| `level-designer` | Spatial layouts, encounters, pacing |
| `narrative-director`\* | Story architecture, world direction, dialogue strategy |
| `writer`\* | Dialogue, lore, item text, barks |
| `world-builder`\* | Factions, history, geography, lore consistency |
| `creative-director` | Vision keeper / senior design reviewer (verdict role) |
| `technical-director` | Architecture authority / feasibility reviewer (writes ADRs) |

\* The narrative trio is optional — delete those three files from `.claude/agents/` if your game
isn't story-driven. Harmless to leave.

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

Design and production documents are written into a `docs/` tree in **your Unity project**, created on
demand, outside `Assets/` so Unity doesn't import them.

---

## Installation

```bash
git clone https://github.com/OmerZeyveli/cloud-nine-unity.git
cd cloud-nine-unity
./install.sh --project-dir /path/to/your/UnityProject

# optionally add the CoplayDev MCP package to Packages/manifest.json at the same time
./install.sh --project-dir /path/to/your/UnityProject --with-mcp
```

That's the whole thing. There is no prerequisite toolkit to install first.

The installer scans your project (Unity version, render pipeline, packages, asmdefs, scenes), copies
the payload into `.claude/`, and generates a `CLAUDE.md` with a vision section for you to fill in and
an auto-detected facts section. Use `--dry-run` to see what it would do, `--yes` for
non-interactive.

**Re-installing is safe.** Every file written is recorded in `.claude/state/install-receipt.tsv` with
its checksum. On upgrade, files you edited are reported and kept. In `CLAUDE.md`, only the region
between the `cloud-nine-unity:generated` markers is refreshed — your prose is left byte-for-byte.

### Then set up the MCP bridge

Follow **[MCP-SETUP.md](MCP-SETUP.md)**: add the CoplayDev package via Package Manager git URL, run
**Window → MCP for Unity → Auto-Setup**, start the bridge, and verify from Claude Code with *"What's
in the current scene?"* (Python 3.10+ and `uv` required; no API key.)

### Health check & uninstall

```bash
./scripts/studio-doctor.sh --project-dir /path/to/your/UnityProject
./uninstall.sh --project-dir /path/to/your/UnityProject
```

`uninstall.sh` removes only files listed in the receipt whose checksum still matches — so anything
you edited, and anything you wrote yourself, stays. Without a receipt it refuses rather than
guessing.

---

## A typical flow

```
/brainstorm                         → docs/design/game-concept.md
/design-review docs/design/game-concept.md
/map-systems                        → docs/design/systems-index.md
/design-system player-controller    → docs/design/player-controller.md
/design-review docs/design/player-controller.md
/unity-feature                      → implements the approved GDD in the editor via MCP
/sprint-plan new                    → docs/production/sprints/sprint-1.md
/scope-check sprint-1   ·   /retrospective sprint-1
```

---

## Provenance

Because this repo contains other people's code, it tracks whose:

- **`provenance.tsv`** — one row per file: origin (`ecu` / `donchitos` / `original`), upstream
  version and path, upstream checksum, and whether we modified it. Currently 201 rows: 158 from ECU
  (120 byte-identical, 38 modified by the mobile strip and the upstream fixes), 22 adapted from
  Donchitos, 21 original.
- **`provenance-skip.tsv`** — what we deliberately did *not* vendor, and why. This is what stops a
  future upstream sync from quietly reintroducing the mobile content.
- **`scripts/check-provenance.sh`** — validates the manifest in both directions: no rows without
  files, no files without rows. `--online` re-fetches the pinned upstream and verifies every
  `verbatim` row still matches.
- **`.claude/UPSTREAM`** — the pinned versions, shipped into your project alongside
  **`.claude/NOTICE.md`**, which carries the upstream MIT notices as their licenses require.

Vendoring trades one risk for another. The old overlay broke whenever ECU moved a file; that risk is
gone. The new one is staleness — upstream fixes no longer reach us on their own. `provenance.tsv` is
what makes a future diff against a newer ECU tractable rather than archaeological.

---

## Credits & License

- **License:** MIT — see [LICENSE](LICENSE). Copyright (c) 2026 OmerZeyveli.
- **Credits & third-party licenses:** [CREDITS.md](CREDITS.md). ECU is vendored and Donchitos is
  adapted; both are MIT and both are attributed there in full.
- **Build record:** [MERGE-NOTES.md](MERGE-NOTES.md) — what was taken, adapted, fixed, and left out.

> **Support:** this is a **low-support** project — issues and PRs are welcome but may be slow. See
> [CONTRIBUTING.md](CONTRIBUTING.md).
