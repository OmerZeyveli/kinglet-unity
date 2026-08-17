# Getting Started

A step-by-step guide to setting up Kinglet Pioneer — a PC/console toolkit for Unity 6 — in your Unity project.

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| **A client** | — | **Claude Code** ([install guide](https://claude.ai/claude-code)), or **Codex CLI**, which Kinglet supports as a second client — partially, and measurably. Read [Kinglet on Codex CLI](../README.md#kinglet-on-codex-cli) before choosing it: hooks, skills, rules and the entry document cross; commands and agents do not cross as surfaces. Measured against `codex-cli 0.145.0` |
| **Unity** | 6 (6000.0+) | URP unless your project states otherwise. `scripts/detect-pipeline.sh` looks in `Packages/manifest.json` for the URP and HDRP packages, and the installer and the `CLAUDE.md` generator both read that one answer. Built-in is the fallback when it finds neither, or when there is no manifest — inferred, not detected; in the generated `CLAUDE.md` it reads `Built-in (default)`. If **both** packages are present it says so rather than picking one: package presence cannot tell you which pipeline is active, and `ProjectSettings/GraphicsSettings.asset` — where Unity records that — is deliberately not read |
| **Python** | 3.10+ | Only needed for unity-mcp integration |
| **uv** | Latest | Python package manager, only needed for unity-mcp |

A client is the only hard requirement, and either of the two above will do. Python and uv are only needed if you want the MCP bridge for direct Unity Editor control.

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

**If your client is Codex CLI, add `--client codex`:**

```bash
/tmp/kinglet/install.sh --project-dir . --client codex
```

That **adds** a layer and removes nothing Claude Code reads: `AGENTS.md` (the document Codex injects
whole, where `CLAUDE.md` is only findable), an `.agents/skills/` root of symlinks plus one generated
skill per command, a generated `.codex/hooks.json`, and a `.codex/config.toml` row for the Unity
bridge. Two things then need doing that a Claude Code install does not need, and the installer's
closing "Next steps" repeats both: **run `codex` once in the project and accept its trust prompt**
(without it Codex registers no hooks there at all and says nothing about it), and fill the `FILL:`
markers in `AGENTS.md` rather than in `CLAUDE.md`. Once you have made that edit, a later install
refreshes **only** the `kinglet:generated` region of that file — the project-facts block — and leaves
everything else, including what the document says about hooks, skills and slash-command names, as the
install that wrote it left them; the file is also recorded as yours from then on, so `uninstall.sh`
keeps it and reports it, and `--purge` is what removes it. Per-hook trust is a separate grant —
`--client codex --codex-trust` — and it is the only thing in this toolkit that writes a file outside
your Unity project, so it is opt-in. [Kinglet on Codex CLI](../README.md#kinglet-on-codex-cli) is the
full account.

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
  (8 of the 8 installed scripts are named by some agent, command or skill, so a model can reach
  them; any that were not would be reachable only by a user who went looking for them. That count
  is derived by `tests/test-derived-counts.sh` rather than maintained by hand.) To match Option A,
  copy them yourself — **all except `check-provenance.sh` and `codex-probe.sh`**, which Option A
  deliberately skips in both its announcement and its write loop. Both measure *this repository*:
  one validates its `provenance.tsv` and expects the repo's layout, the other runs Codex CLI
  against Kinglet's own surfaces, writing into a `docs/research/` directory that does not ship.
  Two of the eight that **do** copy belong to Codex CLI rather than Claude Code —
  `codex-hook-shim.sh`, which makes Kinglet's hooks readable to a client whose file tool hands them
  a patch envelope instead of a file path, and `codex-command-to-skill.sh`, which converts the
  commands into skills for a client that has no command surface. Neither does anything in a Claude
  Code session; both have to be *in* the project because the Codex hook config points at an
  absolute path inside it.
  The repo has 10 scripts; an installed project has 8:

  ```bash
  mkdir -p your-unity-project/.claude/scripts
  for f in kinglet-unity/scripts/*.sh; do
    case "$(basename "$f")" in
      check-provenance.sh|codex-probe.sh) continue ;;
    esac
    cp "$f" your-unity-project/.claude/scripts/
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

This runs a full diagnostic: MCP server connectivity, `.claude/` directory integrity, hook registration, the second client if one is installed, and Unity project structure. It is a safe, read-only operation and a good way to verify everything is working.

**On Codex CLI:** run `codex` instead, and there is no `/unity-doctor` to type — `codex-cli 0.145.0`
has no slash-command surface at all. Every `/unity-*` in this guide is installed there as a skill of
the same name, so ask for a health check and let the model read
`.agents/skills/unity-doctor/SKILL.md`. `bash .claude/scripts/studio-doctor.sh` is the same check
run directly and works from any shell, under either client.

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

**A `--client codex` install adds three things beside `.claude/`, and none of it is a second copy:**
`AGENTS.md` in the project root, `.agents/skills/` (one symlink per skill into `.claude/skills/`,
plus one generated `SKILL.md` per command), and `.codex/` holding a generated `hooks.json` and a
`config.toml` row for the Unity bridge. **"Always loaded" is Claude Code's mechanism and does not
carry:** under Codex nothing reads `.claude/rules/` unless something points at it, which is what
`AGENTS.md` is for, and there is no `Skill` tool — a skill is loaded by reading its file.

---

## Configuring CLAUDE.md for Your Project

Run `/unity-init` to auto-generate a `CLAUDE.md` tailored to your project. It scans:

- Unity version (the active build platform is **not** among the facts it writes — the generated
  table has four rows: Unity version, render pipeline, assembly definitions, scenes in build settings)
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

That applies to `/unity-scene` in the table above, and equally to `/unity-ui`, which is not listed there at all. Both dispatch an agent that writes to your project through the MCP bridge, so both are the step that *builds* a screen or scene an approved design already specifies — never the step that decides one. Each states that precondition in its own description and again at the top of its own file, and the two agents they dispatch state it a third time, for the case where another agent calls them directly.

---

## Troubleshooting

### Quick Diagnostic

Run `/unity-doctor` as a first troubleshooting step — or, on Codex CLI, ask for a health check and let the model read `.agents/skills/unity-doctor/SKILL.md`. Its checks are MCP connectivity, the install itself (via `.claude/scripts/studio-doctor.sh`, which covers `.claude/` integrity and hook registration), what that script does not read, **the second client — skipped entirely unless the project has a `.codex/` or an `.agents/skills/` directory**, and Unity project structure — and it reports actionable fixes rather than changing anything. Derive the number from the file rather than reading one here (`grep -c '^## Check' .claude/commands/unity-doctor.md`): this sentence said *"its four checks are"* against five headings from the day the second-client check was added, in the same sentence that records the previous instance of itself — it listed a fifth, *skill/package alignment*, until 2026-08-14, and that check's package-to-skill mapping table was deleted in the 2026-08-03 surface cut.

### Hooks Not Firing

Under **Claude Code**:

- Verify hooks are executable: `ls -la .claude/hooks/*.sh`
- If not: `chmod +x .claude/hooks/*.sh`
- Check that `settings.json` has the `hooks` block (compare with the template)
- Hooks require `jq` installed on your system for JSON parsing
- To temporarily disable hooks: set `DISABLE_UNITY_HOOKS=1` in your environment
- To downgrade blocking hooks to warnings: set `UNITY_HOOK_MODE=warn`

Under **Codex CLI**, all six of those still apply and none of them is the likely cause. Every measured
way a hook fails to fire there **reports success in its own terms**, which is why "it looks fine" is
not evidence. The causes below are ordered by how often a user meets them, not by layer; the full set,
including the two that are not user-actionable, is `docs/research/codex-client/findings.md`
§ *The six silent-failure layers, in one place*.

1. **The project is not trusted.** `hooks/list` returns `hooks: [], warnings: [], errors: []` — the
   hooks are not reported as untrusted, they are **not registered at all**, and nothing is logged.
   This is the state a correct install is in until you have run `codex` once in the project and
   accepted its trust prompt. **Most likely cause; fix it first.**
2. **`.codex/hooks.json` was never written.** With only the skills bridged, the install is advisory
   rather than enforcing. `bash .claude/scripts/studio-doctor.sh` reports the file's absence; re-run
   the installer with `--client codex`.
3. **The entries are registered but individually untrusted.** They report `enabled: true`,
   `trustStatus: untrusted`, and fire **zero** times with no prompt. Grant it with
   `--client codex --codex-trust`.
4. **The timeouts were copied as milliseconds.** Codex reads `timeout` in **seconds**, so a
   four-digit value is a 33-to-83-minute hook. Regenerate — do not hand-edit, which drops every
   entry to *"modified"* and therefore untrusted.
5. **The hook ran and did nothing.** Codex's file tool is `apply_patch` and its payload carries a
   patch envelope, not `file_path` / `content`, so 8 of the 9 tool-event hooks are inert unless every
   command routes through `.claude/scripts/codex-hook-shim.sh`. Check the commands in
   `.codex/hooks.json`.
6. **The command cannot run at all** — a moved or renamed project directory breaks every entry at
   once, because the config carries absolute paths. Under Codex a hook whose command cannot run is
   not an error you see; **it is an allow.** Regenerate with the installer.

An organisation-managed Codex (`allow_managed_hooks_only`) can stop project hooks running regardless
of all six. `docs/HOOK-REFERENCE.md` § *Everything below assumes Claude Code* and `README.md`
§ *Hook trust* carry the detail.

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

**On Codex CLI they never will show up**, and that is not a fault to fix: `codex-cli 0.145.0` has no
slash-command surface at all — 24 subcommands, none of them a prompt registry. The *content* of every
command crosses; the installer converts each into a skill under `.agents/skills/`. What you lose is
typing `/unity-fix` and getting it. If a converted skill is missing from that directory, re-run
`bash .claude/scripts/codex-command-to-skill.sh`.

### The Model Does Not Know About Unity

- Run `/unity-init` to generate the project-specific CLAUDE.md — or, on Codex CLI, read
  `.agents/skills/unity-init/SKILL.md`, and fill `AGENTS.md`'s `FILL:` markers rather than
  `CLAUDE.md`'s, since `AGENTS.md` is the file Codex injects
- Verify that `.claude/rules/` contains the rule files. **Under Claude Code these load
  automatically; under Codex nothing loads them** — measured, `.claude/rules/` was opened 0 times in
  24 runs without an explicit pointer, and the failure mode was confidently wrong conventions rather
  than none. `AGENTS.md` carries that pointer, so an `AGENTS.md` that was never generated is the
  thing to check
- Skills are loaded by agents as needed; they do not need manual activation. On Codex there are no
  agents and no `Skill` tool — a skill is loaded because the model chose to read its file
