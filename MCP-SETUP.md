# MCP Setup — CoplayDev Unity MCP

`cloud-nine-unity` uses **one** MCP server: CoplayDev's open-source **Unity MCP** bridge.

The toolkit ships `.claude/settings.json` preconfigured — it already contains
`mcpServers.unityMCP` → `http://localhost:8080/mcp`, which matches the bridge's default HTTP
transport. So there is **nothing to write in `settings.json` yourself**; you only need to install
the Unity-side package and start the bridge.

> The `unity-*` agents (coder, scene-builder, prototyper, build-runner, …) are what drive the Editor
> through MCP. The design/production layer — `/brainstorm`, `/map-systems`, `game-designer`,
> `technical-director`, and friends — is a **documentation layer** and calls no MCP tools at all. It
> works fine with the bridge offline.

**Version:** these instructions were checked against **`com.coplaydev.unity-mcp` v10.1.0**
(released 2026-07-13). See `.claude/UPSTREAM` for the pin of record.

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

This installs `com.coplaydev.unity-mcp` (the "MCP for Unity" editor package). Swap `#main` for a tag
(e.g. `#v10.1.0`) if you'd rather pin than track the branch.

> Prefer to edit the manifest directly? Add this line to your project's
> `Packages/manifest.json` dependencies:
> ```json
> "com.coplaydev.unity-mcp": "https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main"
> ```
> Or run `./install.sh --with-mcp`, which inserts exactly that dependency into
> `Packages/manifest.json` for you. It's a surgical insert, not a reformat: your manifest keeps its
> existing formatting, a `manifest.json.bak` backup is written first, and if the edit can't be made
> safely the backup is restored and the line is printed for you to add by hand.

---

## 2. Run the setup wizard & start the server

1. In Unity: **Window → MCP for Unity** (opens the MCP window; shortcut **Ctrl+Shift+M**).
2. Click **Auto-Setup**. The wizard detects **Python 3.10+** and **uv**, configures the server,
   and registers it with the Claude CLI. Install Python/uv first if it flags them missing.
3. If the bridge isn't already running, click **Start Bridge** (a.k.a. "Start Server").

The bridge serves on `http://localhost:8080/mcp`, which matches the `settings.json` we ship. Keep the
Unity Editor open while you work — the MCP tools talk to the live Editor.

---

## 3. Verify from Claude Code

Open Claude Code in your Unity project and ask something that requires the Editor, e.g.:

> "What's in the current scene?"

If MCP is connected, Claude reads the live scene (via tools like `manage_scene`, `manage_gameobject`,
`read_console`). If it can't, check that (a) the Unity Editor is open, (b) the bridge is started in
the MCP window, and (c) `python3 --version` ≥ 3.10 and `uv --version` both succeed.
`scripts/studio-doctor.sh` checks all of these for you.

---

## Switching to Unity's official MCP (optional)

cloud-nine-unity is **CoplayDev-only** by design, but nothing locks you in. If you later migrate to
Unity's official MCP server, you would (instructions only — no code shipped here):

1. **Re-point the server** in your project's `.claude/settings.json`: replace the `unityMCP` entry
   under `mcpServers` with the official server's connection (its relay command/URL, per Unity's MCP
   docs). Keep the key name or update references consistently.
2. **Update the tool names** in `.claude/skills/core/unity-mcp-patterns/SKILL.md`. CoplayDev exposes
   `snake_case` tools (`manage_scene`, `manage_gameobject`, `batch_execute`, `read_console`,
   `create_script`, …); the official server uses different names. Revise that skill's tool table —
   and any `unity-*` agent that names tools directly — so the guidance stays accurate. It's an
   ordinary file in this toolkit, so edit it freely; if you're sending the change back as a PR, see
   `CONTRIBUTING.md` on marking it `modified` in `provenance.tsv`.

This toolkit does not support running both MCP servers at once — pick one.
