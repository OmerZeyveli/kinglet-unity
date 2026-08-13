# MCP Setup — CoplayDev Unity MCP

`Kinglet Pioneer` uses **one** MCP server: CoplayDev's open-source **Unity MCP** bridge.

**Claude Code does not read MCP server configuration from `.claude/settings.json`** — a version of
this toolkit shipped `mcpServers.unityMCP` there and `claude mcp list` reported no servers at all in
a freshly installed project. Project-scoped MCP servers live in `.mcp.json` at the project root, and
that is what `install.sh` writes for you:

```json
{
  "mcpServers": {
    "UnityMCP": {
      "type": "http",
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

If `.mcp.json` already exists and has no `unityMCP`/`UnityMCP` entry, the installer will not touch it — merging
JSON by script is how a hand-written config gets destroyed. It prints the block above for you to add
yourself. Either way, you do not need to write this by hand on a fresh install; you only need to
install the Unity-side package, start the bridge, and approve the server (next section).

> The `unity-*` agents (coder, scene-builder, prototyper, fixer, …) are what drive the Editor
> through MCP.

**Version:** the toolkit pins `com.coplaydev.unity-mcp` at `v10.1.0`, commit
`c14de1e6dc01ab42d2bb358730cff954bce0ce6b`. That is what `--with-mcp` installs and what
`.claude/UPSTREAM` records.

The instructions below — the MCP-location fix, the approval step, the headless bridge recipe — were
written against whatever `#main` resolved to during the smoke pass, which was never recorded. Read
them as verified in shape, not against this exact commit. **What has been verified against this pin,
end to end on 2026-07-30: the package resolves, the bridge starts, and `claude mcp list` reports it
connected.**

> **The pin must be a full 40-character SHA or a tag.** UPM refuses a short hash:
> `Could not clone. Make sure [<ref>] is a valid branch name, tag or full commit hash`.
> This file and `install.sh` carried `a4c2d0a84573` until 2026-07-30, which is not a commit at all —
> it is the suffix of Unity's package cache directory
> (`Library/PackageCache/com.coplaydev.unity-mcp@a4c2d0a84573`), a content hash rather than a git
> revision. Registry packages with no git repository carry one too. Every `--with-mcp` install
> failed on it, and nobody found out because the smoke pass had installed from `#main`.

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
   https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#c14de1e6dc01ab42d2bb358730cff954bce0ce6b
   ```

This installs `com.coplaydev.unity-mcp` (the "MCP for Unity" editor package), pinned to the commit
this toolkit was last measured against (see `.claude/UPSTREAM`) rather than `#main` — which version
you got used to depend on the day you installed. `./install.sh --with-mcp` pins the same commit.

> Prefer to edit the manifest directly? Add this line to your project's
> `Packages/manifest.json` dependencies:
> ```json
> "com.coplaydev.unity-mcp": "https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#c14de1e6dc01ab42d2bb358730cff954bce0ce6b"
> ```
> Or run `./install.sh --with-mcp`, which inserts exactly that dependency into
> `Packages/manifest.json` for you. It's a surgical insert, not a reformat: your manifest keeps its
> existing formatting, a `manifest.json.bak` backup is written first, and if the edit can't be made
> safely the backup is restored and the line is printed for you to add by hand. On success the backup
> is kept — unless git already tracks the manifest, in which case git is the better record and the
> `.bak` is removed. And if a `manifest.json.bak` is already there that the installer didn't write,
> it declines the flag rather than overwrite the file: nothing is backed up, nothing is edited, and
> you get the line to add yourself.

---

## 2. Run the setup wizard & start the server

1. In Unity: **Window → MCP for Unity** (opens the MCP window; shortcut **Ctrl+Shift+M**).
2. Click **Auto-Setup**. The wizard detects **Python 3.10+** and **uv**, configures the server,
   and registers it with the Claude CLI. Install Python/uv first if it flags them missing.
3. If the bridge isn't already running, click **Start Bridge** (a.k.a. "Start Server").

Keep the Unity Editor open while you work — the MCP tools talk to the live Editor.

### Auto-Setup's registration is the one this toolkit targets

Measured 2026-07-30, and still true: before Auto-Setup, `.mcp.json` holds Pioneer's project-scoped
entry. After it, that file reads `{"mcpServers": {}}` — the wizard **removes** the entry and
registers its own server under `~/.claude.json` as *Local config (private to you in this project)*,
at `127.0.0.1` rather than `localhost`, named **`UnityMCP`** (capital U).

That capitalization is not cosmetic. Claude Code matches a `tools:` glob against the registered
server name by exact string, and every `unity-*` agent in this toolkit declares
`mcp__UnityMCP__*`. `install.sh` writes the same spelling into `.mcp.json` for the same reason —
see `provenance.tsv` and `tests/test-mcp-naming.sh`, which fails the build if the two ever disagree
again.

**Run Auto-Setup. It is the supported path — do not undo it.** An earlier version of this file told
you to restore `.mcp.json` and run `claude mcp remove UnityMCP -s local` to drop "the wizard's
private duplicate." That advice was wrong: it produces a Claude Code session where every `unity-*`
agent silently has no MCP tools, because a previous version of this toolkit spelled the server
`unityMCP` (lowercase) while Auto-Setup has always registered `UnityMCP`. Rather than ask every user
to fight the wizard's spelling on every fresh setup, **the toolkit conceded the name** — agents and
`install.sh` now both spell it `UnityMCP`, matching what Auto-Setup actually writes. If you ran the
old advice and removed the wizard's registration, re-run Auto-Setup to put it back.

A project whose `.mcp.json` still has an old lowercase `unityMCP` entry from before this fix keeps
working with no edits required: Auto-Setup empties `.mcp.json` regardless of what is in it and
registers its own copy under `~/.claude.json`, and it is that registration — not the stale key
sitting in `.mcp.json` — that the agents actually call.

```bash
claude mcp list                        # expect UnityMCP, Connected
```

### One-time approval, every fresh install

Writing `.mcp.json` makes the server visible, but project-scoped MCP servers still require a
one-time interactive approval before Claude Code will call their tools:

```
$ claude mcp list
UnityMCP: http://localhost:8080/mcp (HTTP) - ⏸ Pending approval (run `claude` to approve)
```

Run `claude` interactively in the project and approve it when prompted. This is a required manual
step, not a bug — do it once per project/checkout.

**Adding `enabledMcpjsonServers: ["UnityMCP"]` to `.claude/settings.json` did NOT clear this in the
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

`./.claude/scripts/studio-doctor.sh --project-dir <project>` speaks JSON-RPC to whatever answers at the
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
`.claude/scripts/studio-doctor.sh` checks all of these for you.

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
