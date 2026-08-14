# Getting Started

A step-by-step guide to setting up Kinglet Pioneer — a PC/console toolkit for Unity 6 — in your Unity project.

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| **Claude Code** | Latest | [Install guide](https://claude.ai/claude-code) |
| **Unity** | 6 (6000.0+) | URP unless your project states otherwise. `scripts/detect-pipeline.sh` looks in `Packages/manifest.json` for the URP and HDRP packages, and the installer and the `CLAUDE.md` generator both read that one answer. Built-in is the fallback when it finds neither, or when there is no manifest — inferred, not detected; in the generated `CLAUDE.md` it reads `Built-in (default)`. If **both** packages are present it says so rather than picking one: package presence cannot tell you which pipeline is active, and `ProjectSettings/GraphicsSettings.asset` — where Unity records that — is deliberately not read |
| **Python** | 3.10+ | Only needed for unity-mcp integration |
| **uv** | Latest | Python package manager, only needed for unity-mcp |

Claude Code is the only hard requirement. Python and uv are only needed if you want the MCP bridge for direct Unity Editor control.

---

## Installation

### Option A: One-Command Install (Recommended)

From your Unity project root:

```bash
git clone https://github.com/OmerZeyveli/kinglet-unity.git /tmp/kinglet
/tmp/kinglet/install.sh --project-dir .
rm -rf /tmp/kinglet
```

The installer copies the `.claude/` directory into your project and validates the structure.

### Option B: Manual Copy — unsupported, and here is what it costs

Kept for the case it exists for: an air-gapped or vendored checkout where running the installer is
not an option. It is **not** an equal alternative to Option A.

```bash
git clone https://github.com/OmerZeyveli/kinglet-unity.git
cp -r kinglet-unity/.claude your-unity-project/.claude
```

Make sure the hooks are executable:

```bash
chmod +x your-unity-project/.claude/hooks/*.sh
```

Each cost below was measured against a manual copy, not assumed:

- **No install receipt, so `uninstall.sh` refuses to run.** The receipt at
  `.claude/state/install-receipt.tsv` is what records which files are the toolkit's and what their
  checksums were; a `cp -r` writes none. Run against a manual copy, the uninstaller prints
  `No install receipt at .claude/state/install-receipt.tsv.`, explains that it cannot tell your
  files from ours, and ends:

  ```
  err  Refusing to guess which files are ours. Remove .claude/ by hand if you are sure.
  ```

  It exits 1 and removes nothing. Undoing a manual copy is `rm -rf .claude/`, by hand, including
  anything you added under it.

- **No generated `CLAUDE.md`, so run `/unity-init` afterwards.** Option A runs
  `scripts/generate-claude-md.sh`, which writes your Unity version, render pipeline, packages,
  assembly definitions and scenes into `CLAUDE.md` — and with them the *"Architecture stack —
  detected, not assumed"* block that decides which of `.claude/rules/` binds in this project.
  `cp -r .claude` produces no `CLAUDE.md` at all, so until `/unity-init` runs, the rules apply on
  assumption rather than on detection.

- **No `.claude/scripts/`.** That directory does not exist in this repository — Option A builds it
  by copying the repo-root `scripts/`. A manual copy of `.claude/` therefore has no
  `.claude/scripts/`, which this guide points at by that exact path and which `install.sh` writes.
  (6 of the 6 installed scripts are named by some agent, command or skill, so a model can reach
  them; any that were not would be reachable only by a user who went looking for them. That count
  is derived by `tests/test-derived-counts.sh` rather than maintained by hand.) To match Option A,
  copy them yourself — **all except
  `check-provenance.sh`**, which Option A deliberately skips in both its announcement and its write
  loop, because it validates *this repository's* `provenance.tsv` and expects the repo's layout. The
  repo has 7 scripts; an installed project has 6:

  ```bash
  mkdir -p your-unity-project/.claude/scripts
  for f in kinglet-unity/scripts/*.sh; do
    [ "$(basename "$f")" = check-provenance.sh ] || cp "$f" your-unity-project/.claude/scripts/
  done
  chmod +x your-unity-project/.claude/scripts/*.sh
  ```

---

## First Run

1. Open a terminal in your Unity project root (the folder containing `Assets/`).
2. Run `claude` to start Claude Code.
3. Try your first command:

```
/unity-doctor
```

This runs a full diagnostic: MCP server connectivity, `.claude/` directory integrity, hook registration, and Unity project structure. It is a safe, read-only operation and a good way to verify everything is working.

---

## Understanding the .claude/ Directory

After installation, your project contains:

```
.claude/
  agents/           8 specialized sub-agents (coder, reviewer, scene-builder, prototyper, etc.)
  commands/         9 slash commands (/unity-prototype, /unity-fix, /unity-doctor, etc.)
  hooks/           12 hooks + _lib.sh (safety, session, quality warnings) — 5 of them blocking
  rules/            6 always-loaded coding standards (C# style, performance, architecture, PC/console)
  skills/          16 knowledge modules, one directory each — flat, never nested, because one level
                   is the only depth Claude Code discovers (see below)
  settings.json    Permissions, hook definitions
```

Skills are flat on purpose: Claude Code discovers `.claude/skills/<name>/SKILL.md` and nothing
deeper, so a tidy `category/name/` tree makes every skill invisible. They are loaded by the model
invoking the `Skill` tool, never automatically — the agents that need one name it in a
**Skills to load** block.

There is no `platform/` category. This toolkit targets PC and console only, and that guidance lives
in `.claude/rules/pc-console.md`, which really is always loaded — rules are the mechanism for
anything that must reach every session.

---

## Configuring CLAUDE.md for Your Project

Run `/unity-init` to auto-generate a `CLAUDE.md` tailored to your project. It scans:

- Unity version and active platform
- Installed packages (render pipeline, Input System, Addressables, etc.)
- Networking stack (Netcode, Mirror, Photon, Fish-Net)
- Third-party packages (DOTween, UniTask, VContainer, Zenject, Odin)
- Assembly definition structure

You can then customize the generated `CLAUDE.md` to add:

- Project-specific conventions (naming, folder structure)
- Which skills to always load
- Which features are in active development
- Any team-specific rules or constraints

---

## Setting Up unity-mcp (Optional but Recommended)

The MCP bridge gives Claude direct control over the Unity Editor: creating GameObjects, building scenes, running tests, profiling performance.

> **Set it up before you start a session, not during one.** Tool schemas register when the Claude Code
> process starts. Registering the server mid-session succeeds, reports `✔ Connected`, and gives you
> nothing — no `mcp__UnityMCP__*` tools appear, and subagents you spawn afterwards inherit the same
> empty set. The order that works is: open Unity → start the bridge → confirm the port answers →
> *then* start the session. Unity must also stay open: the HTTP server is a child of the editor and
> `EditorApplication.quitting` stops it.
>
> The failure mode is quiet rather than loud. Agents that require MCP — `unity-coder`,
> `unity-test-runner`, `unity-fixer` — remain listed and dispatchable, start normally, and work with
> empty hands. Nothing announces that their main capability is missing; you get a plausible report
> about code that was never touched. If you are planning work that needs the editor, plan the session
> around it.

1. In Unity: **Window > Package Manager > Add package from git URL**
   ```
   https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main
   ```

2. In Unity: **Window > MCP for Unity > Start Server**

3. Verify the server is running on `localhost:8080`

4. The `.mcp.json` is already configured to connect:
   ```json
   "mcpServers": {
     "UnityMCP": {
       "url": "http://localhost:8080/mcp"
     }
   }
   ```

5. Start Claude Code and test the connection by asking Claude to list objects in the scene.

See [MCP-SETUP.md](../MCP-SETUP.md) for detailed setup and troubleshooting.

---

## Common First Commands

| Command | What It Does |
|---------|-------------|
| `/unity-doctor` | Diagnostic health check — verify MCP, hooks, project structure are all working |
| `/unity-init` | Scans your project and generates a tailored CLAUDE.md |
| `/unity-review` | Reviews your C# code for Unity-specific issues |
| `/unity-prototype "description"` | Creates a playable prototype from a text description |
| `unity-brainstorming` (a skill, not a command) | The chain's entry for anything new: clarify requirements → plan → execute → verify, one skill handing to the next |
| `/unity-fix` | Diagnoses and fixes bugs using console errors |
| `/unity-scene "description"` | Builds a scene an approved design already specifies — a build step, not a first command (see below) |
| `/unity-test` | Writes and runs EditMode/PlayMode tests |

**To set the project up:** `/unity-init`, then `/unity-doctor` for a baseline. On a project that already has code, `/unity-review` is the safe next thing to run — it reads and reports, and changes nothing.

**To build something:** don't type a command. Start at `unity-brainstorming`, which hands to `unity-planning`, where how the work gets executed is decided. The one exception is a throwaway scene made to try a mechanic — `/unity-prototype` — and that is a choice made before the work starts, never from part-way in.

That applies to `/unity-scene` and `/unity-ui` above as much as to anything else. Both dispatch an agent that writes to your project through the MCP bridge, so both are the step that *builds* a screen or scene an approved design already specifies — never the step that decides one. Each states that precondition at the top of its own file.

---

## Troubleshooting

### Quick Diagnostic

Run `/unity-doctor` as a first troubleshooting step. It checks MCP connectivity, .claude/ integrity, hook registration, project structure, and skill/package alignment — and provides actionable fixes for any issues found.

### Hooks Not Firing

- Verify hooks are executable: `ls -la .claude/hooks/*.sh`
- If not: `chmod +x .claude/hooks/*.sh`
- Check that `settings.json` has the `hooks` block (compare with the template)
- Hooks require `jq` installed on your system for JSON parsing
- To temporarily disable hooks: set `DISABLE_UNITY_HOOKS=1` in your environment
- To downgrade blocking hooks to warnings: set `UNITY_HOOK_MODE=warn`

### MCP Not Connecting

- Confirm the server is running: check Unity's MCP for Unity window
- Verify `localhost:8080` is reachable: `curl http://localhost:8080/mcp`
- Check for port conflicts: another service on 8080
- Ensure `.mcp.json` (project root) has the correct `mcpServers` block
- See [MCP-SETUP.md](../MCP-SETUP.md) for detailed troubleshooting

### Permission Issues

- On macOS/Linux, hooks need execute permission: `chmod +x .claude/hooks/*.sh`
- The `install.sh` script handles this automatically

### Commands Not Showing Up

- Commands must be in `.claude/commands/` with a `.md` extension
- They need valid frontmatter with `name` and `user-invocable: true`
- Restart Claude Code after adding new commands

### Claude Does Not Know About Unity

- Run `/unity-init` to generate the project-specific CLAUDE.md
- Verify that `.claude/rules/` contains the rule files (these load automatically)
- Skills are loaded by agents as needed; they do not need manual activation
