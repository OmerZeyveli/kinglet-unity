# Kinglet Pioneer

**A standalone, PC/console-focused Claude Code toolkit for Unity 6.** One repo, one installer.

It gives Claude Code an **engineering** layer for your Unity project: agents that drive the Unity
Editor over MCP (coder, reviewer, optimizer, scene-builder, …), `/unity-*` commands, safety hooks,
and architecture rules. A **design & production** layer adapted from Claude-Code-Game-Studios shipped
earlier and was removed 2026-08-03 — a field note measured its `docs/design`, `docs/production`, and
`docs/adr` output used 0 of 3 on a real project. See `provenance-skip.tsv` and `MERGE-NOTES.md` Part 1
for the record of what was cut and why.

> **Honest positioning:** almost none of this is written from scratch. The engineering layer is
> [everything-claude-unity](https://github.com/XeldarAlz/everything-claude-unity) (MIT), vendored and
> then rewritten for an agent reader. What this project adds is the merge: one installer, PC/console
> instead of mobile, a provenance manifest so you can see exactly whose code is whose, a 32-surface
> pool cut down from 103 on the criterion "does this do something the model cannot do unaided," and
> fixes to a handful of upstream defects — including one that destroyed your `CLAUDE.md` on
> re-install. See [CREDITS.md](CREDITS.md) and [MERGE-NOTES.md](MERGE-NOTES.md).

---

## Status — what actually works today

**This is not finished, and the gap between what it installs and what it has been proven to do is
worth reading before you adopt it.** Every claim below is checkable with the command beside it.

| | State |
|---|---|
| **Client** | **Claude Code only.** `adapters/codex/profile.json` exists, but `src/catalog/routing.json` is empty and `python3 -m tools.kinglet_build validate` reports *0 canonical units, 0 routes, 2 adapters*. Nothing renders for Codex yet. |
| **Host** | **linux-x64 only** (`.claude/UPSTREAM`). The shell avoids bash-4 and GNU-only constructs so a macOS pass stays possible, but that pass has not happened. Windows: nothing. |
| **The build system** | **Scaffolded, not in use.** `src/templates/` does not exist. `.claude/` is still the hand-authored surface, pinned by a human-owned manifest in `migration/`. Adding one file there means updating five separate records — see `migration/baseline-inventory.json`'s description. |
| **Unity MCP** | **Session-bound.** Tool schemas register when the client process starts, so Unity must be open and the bridge listening *before* you start the session, and must stay up. A session that begins without it can never acquire it — registering mid-session succeeds and changes nothing. |
| **Verification in your project** | **None ships.** The hooks below are prompt-time guards: they refuse a tool call. The toolkit installs no tests, no gates, no CI, and no pre-push chain for your game. Build-time verification is yours to write. |

### The architecture is a constraint, not a default

`.claude/rules/` mandates **Model-View-System + VContainer + MessagePipe + UniTask + New Input
System**, and the agents and commands assume it. If your project uses a different stack — singletons,
coroutines, plain C# events — the rules are actively wrong for you and you must override them in your
own `CLAUDE.md`. A real project doing exactly that needed a substantial "if a Kinglet rule contradicts
this, this section wins" section to keep the agents from migrating working code.

Read `.claude/rules/architecture.md` before installing. If you disagree with it, this toolkit will
fight you.

### What has actually been exercised

On one Unity 6 / URP 2D project, 2026-08-02: the MCP bridge drove the editor through `execute_code`
and closed eight parked findings; the (now-removed) Donchitos design agents produced design documents
from a real codebase; a headless authoring tool created a complete DNA form in one call. The `unity-*`
engineering agents, commands and skills were **not** invoked in that session — detailed task briefs
left them nothing to decide.

That gap is closed as of 2026-08-03 (Task 7 of the surface-cut wave, see
`docs/research/pioneer/smoke-pass.md`'s dated section): three of smoke-pass.md §10's prompts were
re-run against a fresh install with the competing Superpowers plugin **enabled**, and all three
selected a Kinglet surface — `deep-interview` for an ambiguous "add a double jump," `systematic-debugging`
routed through `/unity-fix` → `unity-fixer` for a bug report, and `/unity-optimize` → `unity-optimizer`
for a performance check. A fourth, unrelated regression probe (a serialization-rename question already
answered by `.claude/rules/serialization.md`) correctly triggered zero tool calls — no skill was
selected to answer a question a rule already answers.

Frontmatter validity and command registration still have had no exhaustive systematic pass, but agent
invocation under real-ish prompts against the live competitor is now measured, not assumed.

---

## What's opinionated

- **PC / console only.** No mobile. Keyboard/mouse + gamepad with rebinding, no touch. Desktop and
  console performance framing throughout. This is enforced by a test, not just requested.
- **Fixed architecture:** Unity 6 · C# · **VContainer** (DI) + **MessagePipe** (messaging) +
  **UniTask** (async) + New Input System. Legacy `Input.*` is blocked by a hook.
- **Medium-weight process.** Enough structure for a solo dev or small team. Senior
  "creative/technical director" reviews are optional, not gates.
- **One MCP.** The open-source [CoplayDev Unity MCP](https://github.com/CoplayDev/unity-mcp) bridge,
  preconfigured in `.mcp.json`. A migration note for Unity's official MCP is in
  [MCP-SETUP.md](MCP-SETUP.md), but only one at a time is supported.

## What's in the box

Installed into your project's `.claude/`:

| | Count | |
|---|---|---|
| **Agents** | 8 | ECU-origin `unity-*` implementers: `unity-coder`, `unity-reviewer`, `unity-optimizer`, `unity-fixer`, `unity-prototyper`, `unity-scene-builder`, `unity-test-runner`, `unity-ui-builder` |
| **Commands** | 11 | All `/unity-*` — see `.claude/commands/` |
| **Skills** | 13 | Unity subsystems and cross-cutting process skills, flat at `.claude/skills/<name>/SKILL.md` |
| **Hooks** | 27 registered | Prompt-time guards (some blocking, the rest advisory). 28 files on disk — `_lib.sh` is a shared library, not a hook |
| **Rules** | 6 | 5 spine rules + `pc-console.md` |
| **Templates** | 10 | C# templates for the MVS pattern (`Model`, `View`, `System`, `LifetimeScope`, `Message`, tests, …) at the repo-level `templates/`. `.claude/templates/` (design-doc templates) does not exist — that layer was removed 2026-08-03. |

### The design & production layer — removed

An earlier build adapted 8 agents, 9 commands, and 5 GDD/ADR/sprint templates from
Claude-Code-Game-Studios as a documentation-only layer (no MCP tools, wrote only to `docs/`). It was
cut in the 2026-08-03 surface reduction: a field note measured its output directories used 0 of 3 on
a real project. `provenance-skip.tsv` records every path as `rule=absent`, and `MERGE-NOTES.md` Part 1
keeps the original adaptation reasoning for history. None of those agents or commands ship today.

---

## Installation

```bash
git clone https://github.com/OmerZeyveli/kinglet-unity.git
cd kinglet-unity
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
between the `kinglet:generated` markers is refreshed — your prose is left byte-for-byte.

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
/unity-init                         → fills the generated CLAUDE.md's FILL: markers once, post-install
/unity-workflow "add a dash ability"  → Clarify → Plan → Execute → Verify, for a multi-step feature
/unity-feature "add a double jump"  → one scoped addition, no plan phase — routes to unity-coder
/unity-fix "enemy walks through walls" → reads console output, verifies the fix via MCP
/unity-review                       → Unity-aware review before considering changes done
/unity-test                         → writes and runs EditMode/PlayMode tests via MCP
/unity-optimize                     → profiles via MCP before changing anything
/unity-doctor                       → checks the install and MCP bridge before you trust them
```

---

## Provenance

Because this repo contains other people's code, it tracks whose:

- **`provenance.tsv`** — one row per file: origin (`ecu` / `donchitos` / `original`), upstream
  version and path, upstream checksum, and whether we modified it. Currently 526 rows: 101 from ECU
  (29 verbatim, 72 modified — nearly every surviving ECU surface has been rewritten for an agent
  reader), 425 original, 0 from Donchitos (that layer was removed 2026-08-03; `provenance-skip.tsv`
  keeps the record).
- **`provenance-skip.tsv`** — what we deliberately did *not* vendor, and why. This is what stops a
  future upstream sync from quietly reintroducing the mobile content.
- **`scripts/check-provenance.sh`** — validates the manifest in both directions: no rows without
  files, no files without rows. `--online` re-fetches the pinned upstream and verifies every
  `verbatim` row still matches.
- **`.claude/UPSTREAM`** — the pinned versions, shipped into your project alongside
  **`.claude/NOTICE.md`**, which carries the upstream MIT notices as their licenses require.

Vendoring trades one risk for another. The old overlay broke whenever ECU moved a file; that risk is
gone. The new one is staleness — upstream fixes no longer reach us on their own, and with 71 of 101
ECU-origin files now `modified`, a future `--online` diff against a newer ECU verifies little. The
offline half of `provenance.tsv` — no rows without files, no files without rows, every `rule=absent`
path stays absent — is what still carries weight; see `CLAUDE.md`'s provenance section for the full
reasoning.

---

## Credits & License

- **License:** MIT — see [LICENSE](LICENSE). Copyright (c) 2026 OmerZeyveli.
- **Credits & third-party licenses:** [CREDITS.md](CREDITS.md). ECU is vendored and Donchitos is
  adapted; both are MIT and both are attributed there in full.
- **Build record:** [MERGE-NOTES.md](MERGE-NOTES.md) — what was taken, adapted, fixed, and left out.

> **Support:** this is a **low-support** project — issues and PRs are welcome but may be slow. See
> [CONTRIBUTING.md](CONTRIBUTING.md).
