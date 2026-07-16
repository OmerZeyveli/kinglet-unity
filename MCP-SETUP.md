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

Keep the Unity Editor open while you work — the MCP tools talk to the live Editor.

### If port 8080 is taken

`settings.json` ships `http://localhost:8080/mcp` because that is the bridge's default. **We cannot
detect the real one.** The Editor stores its HTTP URL in a machine-local EditorPref, not in the
project — so if you change it in the MCP window, nothing in your repo records that, and the shipped
default silently stops matching.

This is not hypothetical: on a machine where an unrelated service already held 8080, `settings.json`
pointed at that service instead of Unity. Worse, a naive reachability check *passes* — the other
service answers HTTP perfectly well. It just isn't Unity.

Set the port in the MCP window, then record it where per-machine settings belong:

```jsonc
// .claude/settings.local.json — gitignored, overrides settings.json
{ "mcpServers": { "unityMCP": { "url": "http://127.0.0.1:8081/mcp" } } }
```

`./scripts/studio-doctor.sh --project-dir <project>` reads that file first and speaks JSON-RPC to
whatever answers, so it tells you when something other than Unity is on the line.

---

## 3. Verify from Claude Code

Open Claude Code in your Unity project and ask something that requires the Editor, e.g.:

> "What's in the current scene?"

If MCP is connected, Claude reads the live scene (via tools like `manage_scene`, `manage_gameobject`,
`read_console`). If it can't, check that (a) the Unity Editor is open, (b) the bridge is started in
the MCP window, and (c) `python3 --version` ≥ 3.10 and `uv --version` both succeed.
`scripts/studio-doctor.sh` checks all of these for you.

---

## Unity's official MCP is a different thing entirely

Unity 6 ships its own MCP with `com.unity.ai.assistant`, run through a relay
(`~/.unity/relay/relay_* --mcp`, stdio). **If you already have that, you do not have what this
toolkit targets.** Both can be registered at once and both will say "Connected" — they are separate
servers driving the same Editor.

They are not variants of one API. Measured side by side against the same running Editor:

| | CoplayDev (what we target) | Unity official relay |
|---|---|---|
| Tools | 42 | 7 |
| Naming | `snake_case` — `manage_scene`, `read_console` | `PascalCase` — `Unity_GetConsoleLogs`, `Unity_RunCommand` |
| Shape | many typed tools, one per domain | one C# execution tool + screen captures + asset generation |
| Overlap with our skill | complete | **none** |

Every tool name in `unity-mcp-patterns`, and every `unity-*` agent that calls one, assumes CoplayDev.
On the official relay **not one of them exists**. Migrating is not "update the tool names" — there is
no mapping to update. `manage_gameobject`, `manage_prefabs`, `manage_scene` have no counterpart;
the official server expects you to write C# and hand it to `Unity_RunCommand`. That is a rewrite of
the skill and of the agents that name tools, against a fundamentally different design.

So: pick CoplayDev, and keep the official relay for the things it is good at (scene captures, asset
generation) if you want both — but do not expect this toolkit's guidance to apply to it.
