# MCP Setup — CoplayDev Unity MCP

`Kinglet Pioneer` uses **one** MCP server: CoplayDev's open-source **Unity MCP** bridge.

**Claude Code does not read MCP server configuration from `.claude/settings.json`** — a version of
this toolkit shipped `mcpServers.unityMCP` there and `claude mcp list` reported no servers at all in
a freshly installed project. Project-scoped MCP servers live in `.mcp.json` at the project root, and
that is what `install.sh` writes for you:

```json
{
  "mcpServers": {
    "unityMCP": {
      "type": "http",
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

If `.mcp.json` already exists and has no `unityMCP` entry, the installer will not touch it — merging
JSON by script is how a hand-written config gets destroyed. It prints the block above for you to add
yourself. Either way, you do not need to write this by hand on a fresh install; you only need to
install the Unity-side package, start the bridge, and approve the server (next section).

> The `unity-*` agents (coder, scene-builder, prototyper, build-runner, …) are what drive the Editor
> through MCP. The design/production layer — `/brainstorm`, `/map-systems`, `game-designer`,
> `technical-director`, and friends — is a **documentation layer** and calls no MCP tools at all. It
> works fine with the bridge offline.

**Version:** these instructions — including the MCP-location fix, the approval step, and the
headless bridge recipe below — were checked against `com.coplaydev.unity-mcp` at commit
`a4c2d0a84573` (the same commit the toolkit pins with `--with-mcp`). See `.claude/UPSTREAM` for the
pin of record.

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
   https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#a4c2d0a84573
   ```

This installs `com.coplaydev.unity-mcp` (the "MCP for Unity" editor package), pinned to the commit
this toolkit was last measured against (see `.claude/UPSTREAM`) rather than `#main` — which version
you got used to depend on the day you installed. `./install.sh --with-mcp` pins the same commit.

> Prefer to edit the manifest directly? Add this line to your project's
> `Packages/manifest.json` dependencies:
> ```json
> "com.coplaydev.unity-mcp": "https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#a4c2d0a84573"
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

### One-time approval, every fresh install

Writing `.mcp.json` makes the server visible, but project-scoped MCP servers still require a
one-time interactive approval before Claude Code will call their tools:

```
$ claude mcp list
unityMCP: http://localhost:8080/mcp (HTTP) - ⏸ Pending approval (run `claude` to approve)
```

Run `claude` interactively in the project and approve it when prompted. This is a required manual
step, not a bug — do it once per project/checkout.

**Adding `enabledMcpjsonServers: ["unityMCP"]` to `.claude/settings.json` did NOT clear this in the
version tested.** Do not rely on it to skip the approval; nothing verified here bypasses it. If you
find a way that reliably does, update this file and say how you confirmed it.

### If port 8080 is taken

`.mcp.json` ships `http://localhost:8080/mcp` because that is the bridge's default. **We cannot
detect the real one.** The Editor stores its HTTP URL in a machine-local EditorPref, not in the
project — so if you change it in the MCP window, nothing in your repo records that, and the shipped
default silently stops matching.

This is not hypothetical: on a machine where an unrelated service already held 8080, the configured
URL pointed at that service instead of Unity. Worse, a naive reachability check *passes* — the other
service answers HTTP perfectly well. It just isn't Unity.

Set the port in the MCP window, then edit the `url` in `.mcp.json` to match. `.mcp.json` lives at the
project root and is typically committed — if the port really is machine-specific, keep the change
local rather than pushing it (no per-machine override path for `.mcp.json` has been verified here;
do not assume `.claude/settings.local.json` still does this, since the same defect that put
`mcpServers` in `.claude/settings.json` in the first place applies to `settings.local.json` too).

`./scripts/studio-doctor.sh --project-dir <project>` speaks JSON-RPC to whatever answers at the
configured URL, so it tells you when something other than Unity is on the line.

### Running the bridge headlessly (no Editor UI)

The bridge does **not** require the Editor UI — the package ships `MCPForUnity.Editor.McpCiBoot` and
an `HttpAutoStartHandler` whose batchmode guard only blocks the auto-start when the environment
variable below is unset. Measured working recipe:

```bash
UNITY_MCP_ALLOW_BATCH=1 Unity -batchmode -nographics \
  -projectPath <project> -executeMethod <Boot>.StartHttpBridge
```

where the boot method:

1. Sets `MCPForUnity.UseHttpTransport` and calls
   `MCPServiceLocator.Server.StartLocalHttpServer(quiet: true)`.
   **`quiet: true` is load-bearing.** The default `quiet: false` opens an
   `EditorUtility.DisplayDialog` confirmation; batchmode auto-cancels it, `StartLocalHttpServer`
   returns `False`, and nothing starts — silently, with no exception.
2. **Waits for the port to start listening** before continuing — `StartLocalHttpServer` returns as
   soon as the server process is *spawned*, not once it is accepting connections. Calling
   `Bridge.StartAsync()` immediately loses that race: the WebSocket dial reports "Unable to connect
   to the remote server."
3. Then calls `MCPServiceLocator.Bridge.StartAsync()`. This is what makes Unity connect *out* to the
   HTTP server over WebSocket (`ws://127.0.0.1:8080/hub/plugin`) and register a session. Skipping it
   leaves the server up with nobody on the Unity end — a client sees `no_unity_session` /
   `instance_count: 0`.

**`-nographics` crashes on real scenes.** `-batchmode -nographics` is fine for a scratch/empty
project, but loading a real scene with URP content (e.g. a Tilemap) under `-nographics` crashes the
Editor with a fatal signal in `UniversalRenderPipeline:RenderSingleCamera` — URP needs an actual
graphics device to render. This is a Unity batchmode limitation, not a Kinglet or CoplayDev defect.
Drop `-nographics` (keep an existing `DISPLAY`) when driving a real project's scenes.

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
