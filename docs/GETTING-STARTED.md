# Getting Started

A step-by-step guide to setting up everything-claude-unity in your Unity project.

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| **Claude Code** | Latest | [Install guide](https://claude.ai/claude-code) |
| **Unity** | 2021.3 LTS+ | Any render pipeline (Built-in, URP, HDRP) |
| **Python** | 3.10+ | Only needed for unity-mcp integration |
| **uv** | Latest | Python package manager, only needed for unity-mcp |

Claude Code is the only hard requirement. Python and uv are only needed if you want the MCP bridge for direct Unity Editor control.

---

## Installation

### Option A: One-Command Install (Recommended)

From your Unity project root:

```bash
git clone https://github.com/<user>/everything-claude-unity.git /tmp/ecu
/tmp/ecu/install.sh --project-dir .
rm -rf /tmp/ecu
```

The installer copies the `.claude/` directory into your project and validates the structure.

### Option B: Manual Copy

```bash
git clone https://github.com/<user>/everything-claude-unity.git
cp -r everything-claude-unity/.claude your-unity-project/.claude
```

Make sure the hooks are executable:

```bash
chmod +x your-unity-project/.claude/hooks/*.sh
```

---

## First Run

1. Open a terminal in your Unity project root (the folder containing `Assets/`).
2. Run `claude` to start Claude Code.
3. Try your first command:

```
/unity-audit
```

This runs a full project health check: meta file integrity, missing references, assembly definition graph, and code quality scan. It is a safe, read-only operation and a good way to verify everything is working.

---

## Understanding the .claude/ Directory

After installation, your project contains:

```
.claude/
  agents/          15 specialized sub-agents (coder, reviewer, verifier, scene-builder, etc.)
  commands/        17 slash commands (/unity-workflow, /unity-prototype, /unity-doctor, etc.)
  hooks/            9 safety hooks + _lib.sh (block scene edits, warn on serialization, suggest review)
  rules/            5 always-loaded coding standards (C# style, performance, architecture)
  skills/          35 knowledge modules organized by category
    core/            Assembly definitions, event systems, object pooling, MCP patterns
    gameplay/        Character controllers, inventory, dialogue, save systems
    genre/           Genre-specific patterns (FPS, platformer, RPG, etc.)
    platform/        Platform-specific knowledge (mobile, console, VR)
    systems/         Unity subsystems (Input System, Addressables, Cinemachine, etc.)
    third-party/     Third-party integrations (DOTween, UniTask, VContainer, etc.)
  settings.json    Permissions, MCP server config, hook definitions
```

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

1. In Unity: **Window > Package Manager > Add package from git URL**
   ```
   https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main
   ```

2. In Unity: **Window > MCP for Unity > Start Server**

3. Verify the server is running on `localhost:8080`

4. The `settings.json` is already configured to connect:
   ```json
   "mcpServers": {
     "unityMCP": {
       "url": "http://localhost:8080/mcp"
     }
   }
   ```

5. Start Claude Code and test the connection by asking Claude to list objects in the scene.

See [MCP-SETUP.md](MCP-SETUP.md) for detailed setup and troubleshooting.

---

## Common First Commands

| Command | What It Does |
|---------|-------------|
| `/unity-doctor` | Diagnostic health check — verify MCP, hooks, project structure are all working |
| `/unity-init` | Scans your project and generates a tailored CLAUDE.md |
| `/unity-audit` | Full project health check (meta files, missing refs, code quality) |
| `/unity-review` | Reviews your C# code for Unity-specific issues |
| `/unity-prototype "description"` | Creates a playable prototype from a text description |
| `/unity-workflow "description"` | Full pipeline: clarify requirements → plan → execute → verify |
| `/unity-fix` | Diagnoses and fixes bugs using console errors |
| `/unity-scene "description"` | Builds a scene from a natural language description |
| `/unity-build` | Configures and triggers a build |
| `/unity-test` | Writes and runs EditMode/PlayMode tests |

Start with `/unity-init`, then `/unity-audit` to get a baseline. From there, try `/unity-review` on existing code or `/unity-prototype` to see the full pipeline in action.

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
- Ensure `settings.json` has the correct `mcpServers` block
- See [MCP-SETUP.md](MCP-SETUP.md) for detailed troubleshooting

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
