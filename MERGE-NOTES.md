# Merge Notes (developer record)

How `cloud-nine-unity` was assembled: what was taken from Donchitos, what was adapted to ECU's
conventions, what was deliberately left out, and which calls/assumptions were mine. This is a
build record for maintainers — end users want `README.md`.

## Source projects (all MIT)

| Project | Version / commit basis | Role |
|---------|------------------------|------|
| everything-claude-unity (ECU) | **v1.5.0** (`.claude/VERSION`; note `plugin.json` is stale at 1.3.0 with old counts 22/41) | Base toolkit this overlay extends. Reference only — **not copied**. |
| Claude-Code-Game-Studios (Donchitos) | repo `main` as cloned | Source of the adapted design/production layer. |
| unity-mcp (CoplayDev) | package `com.coplaydev.unity-mcp` 9.7.x | MCP bridge targeted by docs/automation — **not copied**. |

ECU file counts I worked against (actual files in the v1.5.0 clone, not `plugin.json`): 20 agents,
27 commands, 42 skills, 5 rules. The README intentionally does **not** hard-assert ECU's counts
(they drift between versions); it only counts this overlay's own additions.

## Taken from Donchitos and adapted

- **8 agents:** `game-designer`, `systems-designer`, `level-designer`, `narrative-director`,
  `writer`, `world-builder`, `creative-director`, `technical-director`.
- **9 commands** (Donchitos calls them "skills"): `brainstorm`, `design-review`, `map-systems`,
  `design-system`, `sprint-plan`, `scope-check`, `milestone-review`, `estimate`, `retrospective`.
- **5 templates:** `game-design-document`, `architecture-decision-record`, `sprint-plan`,
  `game-concept`, `systems-index`.

Every adapted file carries an inline `<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT -->`
comment, in addition to the central `CREDITS.md` attribution.

## Format delta applied (Donchitos → ECU)

Verified field-by-field against real ECU files (`agents/unity-reviewer.md`, `commands/unity-review.md`),
not an assumed schema:

- **Agents.** Donchitos frontmatter carried `maxTurns`, `disallowedTools`, `memory`, and a `skills: []`
  array. **Removed** those; **added** ECU's `color`; reduced `tools` to a doc-layer set
  (`Read, Write, Edit, Glob, Grep`, plus `WebSearch` for the designer/narrative/director roles).
  Crucially, **none of these agents get `mcp__unityMCP__*` tools or write C#** — they are a
  documentation/design layer. ECU's coder agents own implementation.
- **Commands.** Donchitos skill frontmatter (`argument-hint`, `allowed-tools`, `model`, sometimes a
  `context:` bash preamble) was reduced to ECU's command frontmatter (`name`, `description`,
  `user-invocable`, `args`). Model/agent routing moved into the body, mirroring ECU's `unity-review`.
- **Rules.** `pc-console.md` is plain Markdown with **no frontmatter**, matching ECU's rule files.
- **Paths.** Repointed Donchitos's `design/gdd/` → `docs/design/`, `production/*` → `docs/production/*`,
  `docs/architecture/adr-*` → `docs/adr/`, and `assets/data/` → ScriptableObjects / external config.

## Process weight: trimmed to MEDIUM

Donchitos runs a heavy multi-gate pipeline. I cut it to keep the overlay solo-friendly:

- **Removed** the `--review full|lean|solo` mode machinery, the `production/review-mode.txt` file,
  and all references to `.claude/docs/director-gates.md` and named gates (`CD-PILLARS`,
  `TD-FEASIBILITY`, `PR-SPRINT`, etc.).
- **Removed** the mandatory `producer` / `art-director` gate spawns. Where a senior check still adds
  value, the command now **optionally** spawns `creative-director` or `technical-director` for a
  verdict (APPROVE/CONCERNS/REJECT) — explicitly "not a gate, skip for a fast solo pass."
- **Kept** the collaborative, section-by-section authoring flow (skeleton → discuss → approve →
  write) because that is the genuinely valuable part and is light enough for solo use.

## Left out (and why)

- **Agents:** `producer` (heavy cross-domain coordination), `live-ops-designer`, `community-manager`,
  `localization-lead`, `economy-designer` (folded into `systems-designer`), `analytics-engineer` —
  post-launch / live-ops / heavy-coordination roles outside a medium-weight, pre-launch solo scope.
- **The full GDD gate pipeline** and the global review-mode system (see above).
- **Donchitos's engine-agnostic code rules** (`coding-standards.md`, `technical-preferences.md`,
  `coordination-rules.md`, `context-management.md`). These overlap with ECU's rules and would
  conflict (Donchitos is Godot/Unity/Unreal-generic; ECU is opinionated Unity). **ECU wins** — I did
  not bring these over.
- Donchitos's many extra templates (art bible, economy model, UX spec, etc.) — out of scope for a
  PC/console design+production overlay; can be added later if needed.

## PC/console adaptation

- Added a single new rule, `overlay/rules/pc-console.md` (installs to `.claude/rules/pc-console.md` —
  a new path, no collision with ECU's 5 rules). It neutralizes ECU's mobile assumptions (mobile
  draw-call ceilings, ASTC/TBDR/thermal, touch, safe-area) and adds keyboard/mouse + gamepad input
  (with rebinding) and desktop/console performance notes (60 fps baseline, high-refresh PC, settings
  scaling, ultrawide/multiple aspect ratios). **It does not modify or duplicate any ECU rule** and
  explicitly states ECU wins on conflict.
- Did **not** touch ECU's mobile skill — README notes it's harmlessly inert on PC/console and
  optionally deletable.

## MCP (CoplayDev-only)

- **Did not** ship or overwrite a `settings.json` — ECU's already has
  `mcpServers.unityMCP → http://localhost:8080/mcp`, which matches CoplayDev's HTTP transport.
  `install.sh` only **verifies** the entry and warns if absent.
- Confirmed ECU's `unity-mcp-patterns` skill already uses CoplayDev's `snake_case` tool names
  (`manage_scene`, `batch_execute`, `read_console`, …) → no MCP tool-name rework needed.
- The overlay's design/production agents and commands **do not call MCP** — they're a doc layer.
- `MCP-SETUP.md` documents install (UPM git URL, Python 3.10+/uv, Window → MCP for Unity →
  Auto-Setup/Start Bridge, "what's in the scene?" verification, no API key) plus a short
  instructions-only "switch to Unity's official MCP" note (re-point `settings.json` + update
  `unity-mcp-patterns` tool names).

## Decisions I made (assumptions)

- **Repo name** `cloud-nine-unity` (user-chosen, "cloud nine" pun; an earlier "cloude-nine" typo was
  corrected to a single consistent spelling).
- **Payload under `overlay/`**, distribution docs at repo root; `install.sh` maps
  `overlay/<x>` → `<project>/.claude/<x>`.
- **Design docs path** `docs/` at project root (lowercase), created in the **user's Unity project**,
  not in this overlay repo. Subfolders: `docs/design`, `docs/adr`, `docs/production`.
- **Templates install to** `<project>/.claude/templates/` (ECU's own templates live at its repo-root
  `templates/`, so no collision).
- **5 templates** = the 3 named in scope (GDD, ADR, sprint-plan) + 2 the included commands directly
  produce (game-concept from `/brainstorm`, systems-index from `/map-systems`). Not gold-plating.
- **Health check** is a shell script (`scripts/studio-doctor.sh`) rather than a `/`-command, since it
  inspects the environment (Python/uv/MCP/files); avoids overlap with ECU's `/unity-doctor`.
- **Director agents** kept the APPROVE/CONCERNS/REJECT verdict format but lost the heavy gate registry.
- **LICENSE holder** is a neutral placeholder (`cloud-nine-unity contributors`) for the end user to replace.

## ECU-version fragility (known risk)

`install.sh` detects ECU by the presence of `.claude/rules/architecture.md` and
`.claude/skills/core/unity-mcp-patterns/SKILL.md`, and places overlay files **alongside** ECU's. If a
future ECU release renames/moves those files or restructures `.claude/`, both detection and placement
can break. The overlay is therefore pinned and documented as **"tested against ECU v1.5.0."** Re-verify
against newer ECU releases before bumping that pin.
