# MCP Setup — CoplayDev Unity MCP

`cloud-nine-unity` uses **one** MCP server: CoplayDev's open-source **Unity MCP** bridge. This is
the same server ECU already wires up in `.claude/settings.json` (`mcpServers.unityMCP` →
`http://localhost:8080/mcp`), so there is **nothing to change in `settings.json`** — you only need
to install the Unity-side package and start the bridge.

> The design/production agents and commands this overlay adds are a **documentation layer** — they
> do not call MCP tools. MCP is used by ECU's coder/scene/build agents to drive the Unity Editor.

---

## Prerequisites

- **Unity 6** (the project's target; the bridge supports 2021.3 LTS+).
- **Python 3.10 or newer.**
- **[uv](https://docs.astral.sh/uv/getting-started/installation/)** — the Python package manager
  the MCP server runs under.
- **Claude Code** (this CLI).

No API key is required. The open-source bridge is fully free under MIT — API keys are only relevant
to Coplay's separate commercial hosted product, which you do **not** need here.

---

## 1. Install the Unity package

In the Unity Editor:

1. **Window → Package Manager**
2. **+ ▾ → Add package from git URL…**
3. Paste:

   ```
   https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main
   ```

This installs `com.coplaydev.unity-mcp` (the "MCP for Unity" editor package).

> Prefer to edit the manifest directly? Add this line to your project's
> `Packages/manifest.json` dependencies:
> ```json
> "com.coplaydev.unity-mcp": "https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main"
> ```
> Or run `cloud-nine-unity`'s `install.sh --with-mcp`, which adds this dependency for you.

---

## 2. Run the setup wizard & start the server

1. In Unity: **Window → MCP for Unity** (opens the MCP window; shortcut **Ctrl+Shift+M**).
2. Click **Auto-Setup**. The wizard detects **Python 3.10+** and **uv**, configures the server,
   and registers it with the Claude CLI. Install Python/uv first if it flags them missing.
3. If the bridge isn't already running, click **Start Bridge** (a.k.a. "Start Server").

The bridge serves on `http://localhost:8080/mcp`, which matches ECU's `settings.json`. Keep the
Unity Editor open while you work — the MCP tools talk to the live Editor.

---

## 3. Verify from Claude Code

Open Claude Code in your Unity project and ask something that requires the Editor, e.g.:

> "What's in the current scene?"

If MCP is connected, Claude reads the live scene (via tools like `manage_scene`, `manage_gameobject`,
`read_console`). If it can't, check that (a) the Unity Editor is open, (b) the bridge is started in
the MCP window, and (c) `python3 --version` ≥ 3.10 and `uv --version` both succeed. The overlay's
`scripts/studio-doctor.sh` checks these for you.

---

## Switching to Unity's official MCP (optional)

cloud-nine-unity is **CoplayDev-only** by design, but nothing locks you in. If you later migrate to
Unity's official MCP server, you would (instructions only — no code shipped here):

1. **Re-point the server** in your project's `.claude/settings.json`: replace the `unityMCP` entry
   under `mcpServers` with the official server's connection (its relay command/URL, per Unity's MCP
   docs). Keep the key name or update references consistently.
2. **Update the tool names** ECU's `unity-mcp-patterns` skill references. CoplayDev exposes
   `snake_case` tools (`manage_scene`, `manage_gameobject`, `read_console`, `batch_execute`, …).
   The official server uses different names — revise the tool table in
   `.claude/skills/core/unity-mcp-patterns/SKILL.md` (and any MCP-powered ECU agents) to match the
   official server's naming so guidance stays accurate.

This overlay does not support running both MCP servers at once — pick one.
