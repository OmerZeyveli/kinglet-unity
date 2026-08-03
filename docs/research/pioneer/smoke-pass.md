# Pioneer smoke pass

**Date run:** 2026-07-29
**Host:** Pop!_OS, Linux 7.0.11-76070011-generic, x86_64
**Unity:** 6000.3.18f1 (5ebeb53e4c07), created via `-batchmode -createProject`
**Render pipeline:** Built-in — *not* URP in the scratch pass. The URP path was covered by the second pass in §9. `-createProject` produces a built-in project, and the
runbook asks for URP. Recorded as a deviation; it exercised the installer's built-in detection path
instead of the URP one, so the URP path remains unmeasured.
**MCP package:** `com.coplaydev.unity-mcp` resolved to `a4c2d0a84573` from
`git+https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main`
**Toolkit:** Kinglet Pioneer `3.0.0-pioneer.1`, installed with `install.sh --with-mcp`
**Scratch project:** `/tmp/pioneer-smoke` (disposable, not the operator's game)

## How this pass differs from the runbook

The runbook was written for a human at an interactive Claude Code session. This pass was run by an
agent using the `claude` CLI in headless `-p` mode. Two consequences, stated so the record is not
read as more than it is:

- **"Do the 36 commands appear in the `/` completion list" was not measured.** That list is an
  interactive UI affordance and headless mode has no equivalent. What *was* measured is stronger in
  one respect and weaker in another: which surface the model actually selects when asked a real
  question, with the tool-call stream as evidence rather than self-report.
- **The MCP measurements are partly complete.** The package installs and compiles, and the bridge
  *can* be started headlessly — but the Editor↔server session never established under batchmode. See
  §6, which also corrects the runbook's claim that the bridge needs the Editor UI.

A second pass on the operator's real Unity project — URP, 1073 C# files, a live git repository, an
existing `AGENTS.md` — is recorded in §9. It confirms the findings are not artifacts of an empty
scratch project.

Nothing was repaired during the pass. Every finding below is recorded as observed.

---

## 1. Installation — pass

```
ok  Unity project detected.
ok  Unity 6000.3.18f1 · Built-in
ok  No existing .claude/ — clean install.
ok  Installed 171 file(s).
ok  Generated CLAUDE.md
ok  Updated .gitignore (3 entries)
ok  Added com.coplaydev.unity-mcp to manifest.json (backup: manifest.json.bak)
ok  Receipt written: .claude/state/install-receipt.tsv (171 files)
```

Counts on disk afterwards: 28 agents, 36 commands, 39 skills, 27 hook scripts (26 hooks + `_lib.sh`),
6 rules. `CLAUDE.md` carries both `kinglet:generated` markers. `settings.json` carries
`mcpServers.unityMCP → http://localhost:8080/mcp`.

## 2. Sessions hang in a project that is not a git repository — **Critical**

**This is the finding of the pass.** A fresh Unity project is not a git repository, and installing
Pioneer into one makes every Claude Code session in it hang forever.

Measured:

| Condition | Result |
|---|---|
| `claude -p` in an empty directory, no payload | exit 0, prints `OK` |
| `claude -p` in the payload project, **no `git init`** | **hangs — killed at 120 s, exit 124** |
| Same, with `hooks` removed from `settings.json` | exit 0, prints `OK` |
| Same, hooks restored, after `git init` + one commit | exit 0, prints `OK` |

`mcpServers` was present and pointing at a bridge that was **not running** in the runs that
succeeded, so the unreachable MCP bridge is **not** the cause. It is the hooks.

### Root cause

`.claude/hooks/session-save.sh` (a `Stop` hook), line 20:

```bash
RECENT_COMMITS=$(git log --oneline -3 2>/dev/null | jq -Rs 'split("\n") | map(select(length > 0))' || echo '[]')
```

1. With no git repository, `git log` fails.
2. Under `set -euo pipefail` the pipeline is therefore a failure — **but `jq` has already written
   `[]` to stdout.**
3. `|| echo '[]'` then appends a *second* `[]`. The command substitution captures both.
4. `RECENT_COMMITS` becomes `[]\n[]`, which is not valid JSON.
5. `jq -n --argjson commits "$RECENT_COMMITS"` fails → `set -e` → the hook exits non-zero.

Observed directly:

```
+ jq -n ... --argjson commits '[]
[]' ...
jq: invalid JSON text passed to --argjson
```

```
git repository present  → session-save.sh exit 0, "Session state saved."
git repository absent   → session-save.sh exit 2, "jq: invalid JSON text passed to --argjson"
```

6. **A `Stop` hook exiting 2 blocks the stop** and feeds its stderr back to the model as a reason to
   keep going. The session never terminates.

### Why the existing convention did not catch it

`CLAUDE.md` warns about pipelines under `set -euo pipefail`, but the warning is about piping into
`head`. This is a different shape of the same family:

> Under `pipefail`, `cmd1 | cmd2 || fallback` does not *replace* the output when `cmd1` fails — if
> `cmd2` already wrote something, the fallback **appends** to it.

Worth adding to the shell conventions, because a `|| fallback` reads as a guard and is behaving as
a corrupter. The other Stop hooks were checked and none of them hang: `auto-learn`,
`instinct-distill`, `notify` and `stop-validate` all exit 0 immediately.

## 3. The spine rules load and bind — pass

Probed with a question whose correct answer contradicts ordinary C# convention, so that general
model knowledge could not produce it:

> *"In one word only, with no explanation: what casing should a C# const field use in this project?"*

Answer: **`UPPER_SNAKE_CASE`**. Standard C# convention is `PascalCase`; `UPPER_SNAKE_CASE` appears
only in `.claude/rules/csharp-unity.md`. The rules are in context and are binding.

Corroborated in §5: told explicitly to write `Input.GetKey`, the model wrote the New Input System
instead, because `unity-specifics.md` forbids the legacy API.

## 4. Surface selection — **Critical**

Asked the single most ordinary request a game developer makes:

> *"Let's add a double jump to the player."*

Tool-call stream, in order:

```
Skill   superpowers:brainstorming
Bash    find … -iname "*player*" -o -iname "*jump*"
Bash    find … -maxdepth 3 -type d
Bash    ls -la /tmp/pioneer-smoke/Assets/
```

**Not one of Pioneer's 36 commands or 39 skills was selected.** Not `/unity-feature`, not
`/unity-workflow`, not `unity-prototyper`, not the `character-controller` skill. The surface that won
was `superpowers:brainstorming` — a *different plugin*, installed globally on this machine.

The behaviour that followed was sensible (it scanned the project and asked scoping questions). The
problem is not the answer; it is that the entire toolkit was invisible to the selection.

This measures, rather than predicts, the gap recorded in the design: **0 of 39 skill descriptions are
phrased as trigger conditions.** The competing plugin's are:

| | Description |
|---|---|
| Superpowers | *"You MUST use this before any creative work — creating features, building components, adding functionality…"* |
| Pioneer | *"Full development pipeline — clarify requirements, plan implementation, execute with agents, verify with review + tests."* |

The first states when it applies. The second states what it does. The first was chosen.

A second probe pointed the same way: asked what to be careful about when renaming a serialized
field, the model made **zero tool calls** and answered from the rules. `serialization-safety` — a
skill that exists precisely for that question — was never invoked.

**Consequence for the plan:** the machine-selectable-surface item is now the first item of Wave 1b,
ahead of durable artifacts. A toolkit nobody's agent selects is a toolkit nobody uses, and the
operator's stated requirement was that no one should have to memorise command names.

## 5. Hooks

Blocking hooks, exercised directly with realistic `PreToolUse` payloads:

| Hook | Result |
|---|---|
| `block-legacy-input.sh` | exit 2, blocked, with a correct and genuinely useful message |
| `block-meta-edit.sh` | exit 2, blocked |
| `block-scene-edit.sh` | exit 2, blocked |
| `guard-editor-runtime.sh` | exit 2, blocked |
| `guard-project-config.sh` | exit 0 — **correct.** The test payload was `Packages/manifest.json`, which is not in this hook's protected set (`.editorconfig`, `*.ruleset`, `*.globalconfig`, `Directory.Build.props`, `*.csproj` analyzer sections). Mis-probed, not a defect. |

**Not exercised in the live run.** Told to write `Input.GetKey(KeyCode.Space)`, the model wrote
`Keyboard.current.spaceKey.isPressed` instead. The rules prevented the violation, so the hook never
fired. Defence in depth working at the first layer — but it means the blocking hooks' *live* path is
still unmeasured.

### `bash-gate.sh` — a false positive and a gap, in the same classifier

**False positive.** A `Bash` command was blocked as `projectsettings-write` because the literal
string `ProjectSettings/ProjectSettings.asset` appeared **inside a JSON test payload argument**. The
command wrote nothing. This is unanchored substring matching on a whole command line — one of this
project's recurring defect classes. A false block is more costly than a missed one: it argues with
the developer every day.

**Gap.** `rm -rf /` passes with exit 0. The classifier's documented scope is
`rm -rf Library/|Temp/|Logs/|obj/|Build/` — it guards Unity's reimport artifacts, not the
filesystem. Arguably by design; recorded because the name `bash-gate` invites a broader reading than
the implementation delivers.

## 6. MCP — the configuration the toolkit ships is inert — **Critical**

### The finding

```
$ claude mcp list
No MCP servers configured. Use `claude mcp add` to add a server.
```

Run inside the freshly installed project, with `.claude/settings.json` containing exactly what the
toolkit ships:

```json
"mcpServers": { "unityMCP": { "url": "http://localhost:8080/mcp" } }
```

**Claude Code does not read MCP server configuration from `.claude/settings.json`.** Project-scoped
servers live in `.mcp.json` at the project root. The key the toolkit writes is simply ignored.

This makes `MCP-SETUP.md`'s central claim false:

> *"The toolkit ships `.claude/settings.json` preconfigured — it already contains
> `mcpServers.unityMCP` … So there is **nothing to write in `settings.json` yourself**."*

There is nothing to write in `settings.json` because writing it there does nothing. And the
consequence is not narrow: **every `unity-*` agent and command drives the Editor through MCP.** As
installed, that entire half of the toolkit — 20 engineering agents, 27 `/unity-*` commands — has no
tools to call.

### Confirmed remedy

Writing `.mcp.json` at the project root makes the server visible:

```
$ claude mcp list
unityMCP: http://localhost:8080/mcp (HTTP) - ⏸ Pending approval (run `claude` to approve)
```

Two things follow, and the installer must handle both:

1. **Location.** `.mcp.json` at the project root, with `{"mcpServers": {"unityMCP": {"type": "http",
   "url": "…"}}}`.
2. **Approval.** Project-scoped MCP servers require a one-time interactive approval. Adding
   `enabledMcpjsonServers: ["unityMCP"]` to `.claude/settings.json` did **not** clear it in this
   version — the approval still showed as pending. Whatever the correct mechanism is, it is a
   required install step and is currently absent from both the installer and the documentation.

With the server reachable and approval bypassed, `mcp__unityMCP__manage_scene` appeared in the tool
list and was called three times. The wiring works once the configuration is in the right file.

### The bridge *can* be started headlessly — the runbook was wrong about this

The runbook said the bridge needs the Editor UI. It does not. The package ships
`MCPForUnity.Editor.McpCiBoot` and an `HttpAutoStartHandler` whose batch-mode guard is a door, not
a wall:

```csharp
if (Application.isBatchMode &&
    string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("UNITY_MCP_ALLOW_BATCH")))
    return;
```

Working recipe, measured:

```bash
UNITY_MCP_ALLOW_BATCH=1 Unity -batchmode -nographics \
  -projectPath <project> -executeMethod <Boot>.StartHttpBridge
```

where the boot method sets `MCPForUnity.UseHttpTransport` and calls
`MCPServiceLocator.Server.StartLocalHttpServer(quiet: true)`.

**`quiet: true` is load-bearing.** With the default `quiet: false` the method opens an
`EditorUtility.DisplayDialog` confirmation, batchmode auto-cancels it, and the call returns `False`:

```
Canceling DisplayDialog: Start Local HTTP Server  Start the local MCP server in the background?
This should not be called in batch mode.
  ServerManagementService:StartLocalHttpServer (bool) at ServerManagementService.cs:301
PIONEER_BOOT: StartLocalHttpServer returned False
```

With `quiet: true`: `returned True`, and a Python process listening on `127.0.0.1:8080` whose
`/mcp` endpoint answers correctly (`{"jsonrpc":"2.0",…"Bad Request: Missing session ID"}`).

### Resolved: the full chain works, headless, including on a real project

The first attempt failed because the Unity Editor never connected to the server it had just started.
Two steps were missing, and both are recorded here because they are the whole recipe:

1. **`Bridge.StartAsync()`.** `StartLocalHttpServer` only spawns the server process. Unity connects
   *out* to it over WebSocket (`ws://127.0.0.1:8080/hub/plugin`) and registers a session. Without
   `MCPServiceLocator.Bridge.StartAsync()` the server is up with nobody on the Unity end, which a
   client sees as `no_unity_session` / `instance_count: 0`.
2. **Wait for the port first.** `StartLocalHttpServer` returns as soon as the process is spawned,
   not when it is listening. Connecting immediately loses the race and the WebSocket reports
   *"Unable to connect to the remote server"*. Polling `127.0.0.1:8080` before calling `StartAsync`
   fixes it; blocking there is safe, because the server is a separate process and needs nothing from
   the editor loop.

With both in place, on the scratch project:

```
mcp__unityMCP__manage_scene → rootCount: 0, name: "", path: ""
```

— real data, and the right answer for a freshly created empty project.

**And on the operator's own project** (Endless Evolution, URP, 1073 scripts), after opening
`Assets/Scenes/MainMenu.unity` through the bridge:

```
Player · Level · Tilemaps (6 children) · Managers (4) · Canvas (2)
InputContext (SceneInputContext, SystemsBootstrapper) · Slimes (7)
WaterReflection (1) — tag Water, BuoyancyEffector2D, BoxCollider2D
Polish Items (5) · Title (3)
```

That is the project's actual hierarchy, read live out of the Editor. **MCP works end-to-end.**

### The one remaining boundary: `-nographics` and real scenes

Loading that same scene under `-batchmode -nographics` **crashed the Editor**:

```
Caught fatal signal - signo:11 code:1 errno:0 addr:0x8
  GfxDevice::DrawSharedGeometryJobs(...)
  TilemapRendererJobs::TilemapRendererGeometryJob::Schedule(...)
  UniversalRenderPipeline:RenderSingleCamera(...)
```

URP tried to render a Tilemap with no graphics device. This is a Unity batchmode limitation, **not a
Kinglet or CoplayDev defect** — and it is why the successful run above dropped `-nographics` and used
the session's existing `DISPLAY`. Recorded so nobody re-diagnoses it later: automating a real scene
needs a graphics device, not just batchmode.

## 6b. Failing loudly — pass, twice

The design requires that MCP-dependent work fail loudly rather than silently no-op or invent an
answer. This was exercised under two different failure modes and passed both times.

**Tools absent** (settings.json config ignored):

> *"No Unity MCP tools are available in this session — the CoplayDev Unity MCP bridge doesn't appear
> to be connected… I won't guess at the scene contents in the meantime."*

**Tools present, bridge session dead:**

> *"The Unity MCP bridge isn't connected — Unity Editor doesn't currently have an active MCP
> session. I'm not going to guess at scene contents."*

Both name the failure, cite `MCP-SETUP.md`, and explicitly refuse to fabricate. Note *how* this is
achieved: by the rules and the model's judgment, not by a hook or any mechanism the toolkit enforces.
It is a real pass, and it is a softer guarantee than the enforced ones.

## 6c. The New Input System is mandated but not installed — **Important**

Told to write `Input.GetKey`, the model correctly wrote `Keyboard.current.spaceKey.isPressed`
(§5). The project then failed to compile:

```
Assets/Scripts/JumpInput.cs(2,19): error CS0234: The type or namespace name 'InputSystem'
does not exist in the namespace 'UnityEngine'
Scripts have compiler errors.
```

`unity-specifics.md` makes the New Input System **non-negotiable** and a hook blocks the legacy API,
but nothing adds `com.unity.inputsystem` to `Packages/manifest.json`. The first script written under
the project's own rules does not compile. The installer already edits the manifest for the MCP
package, so the same mechanism is available.

Consequence beyond the compile error: **compilation failure aborts `-executeMethod`**, so a broken
script blocks Editor automation entirely.

## 7. Version pin — resolved

The repository carried two contradictory pins: `.claude/UPSTREAM` and `MCP-SETUP.md` said `10.1.0`;
the platform spike's `mcp.lock.json` pinned `v9.7.1` at `78ee5418415953b79c358bfe6355fcc3fde7912b`.

**What actually ran here is `#main`, which resolved to commit `a4c2d0a84573`** — neither of them.
The manifest entry `install.sh --with-mcp` writes tracks the branch rather than a tag, so what a user
gets depends on the day they install.

Under the rule that Pioneer pins what it ran against, the honest record is: **this pass ran
`a4c2d0a84573` from `#main`, and the toolkit does not currently pin an MCP version at all.** Fixing
the two stale numbers is not enough; the installer should write a pinned ref. Wave 1b item.

## 8. Stocktake — not run

`/unity-skill-stocktake` was not exercised. Slash-command invocation is the measurement headless mode
is weakest at, and §4 already answers the question the stocktake was meant to inform — the surface is
not being selected at all, so measuring duplication within it is premature. Deferred to the
interactive pass in §6.

---

## 9. Second pass: a real game project

Run on the operator's own Unity project — **Endless Evolution**, Unity `6000.0.68f1`, **URP**,
1073 C# files, a live git repository — on a throwaway branch, installed, measured, then uninstalled
and the branch deleted. The repository was returned to its prior commit with a clean tree.

This pass exists because the scratch project was empty, freshly created, built-in pipeline, and had
no prior agent configuration. Every one of those could have been the reason a finding appeared.

### What it confirmed

| | |
|---|---|
| **The hang is git-shaped** | With a real git repository present, `claude -p` returned `exit 0`, `OK`. §2's diagnosis holds from the other direction: the hang is not "the payload", it is specifically the non-git case. |
| **URP detection** | `ok Unity 6000.0.68f1 · URP` — the pipeline branch the scratch project could not exercise. |
| **An existing `CLAUDE.md` is safe** | The project's own `CLAUDE.md` (a pointer to its `AGENTS.md`) was **not touched** — no diff, no git-status entry. The installer wrote `CLAUDE.md.generated` beside it, exactly as the dry run predicted. |
| **The mandated input package, measured** | The project's `Packages/manifest.json` carries `"com.unity.inputsystem": "1.18.0"` under Unity `6000.0.68f1`. This is the only version of that package this toolkit has been observed alongside in a working Unity 6 project, and §6c is why the number matters: the installer needs a defensible value to offer. Recorded late — it was measured during the run and omitted from the first write-up of this section. |
| **Uninstall is exact** | `uninstall.sh` removed 171 files, all "unchanged since install", kept three runtime state files it correctly did not own, and reported *"Left alone: CLAUDE.md, docs/, and anything you wrote."* |
| **The rules load beside a foreign guidance system** | The project has its own 171-line `AGENTS.md`. Probed for `const` casing, the answer was still `UPPER_SNAKE_CASE` — Pioneer's spine applies where `AGENTS.md` is silent, without a fight. |

### What it reproduced — §4 is not an artifact of an empty project

Same request, real codebase:

```
Skill   superpowers:brainstorming
Bash    grep -ril "playermovement\|PlayerSystem\|playercontroller"
Read    Assets/Player/…
Bash    find … -maxdepth …
Bash    grep -n -i "double jump\|PlayerMovement\|jump"
Read    Assets/Player/…
```

**Again: not one Kinglet command, agent, or skill.** The work that followed was good — it located the
player movement code, found the DNA-form system, and asked whether the double jump should be a base
ability or an evolution unlock like the bunny's wall jump. But it did that with `grep` and `Read`,
against a project carrying 36 commands, 28 agents and 39 skills that all went unused.

Measured twice now, on an empty project and on a substantial one, with and without a competing
guidance file. The finding is robust.

### Two new minor defects

- **The uninstaller's backup directory is not ignored.** The installer adds `.claude/`-scoped
  entries to `.gitignore`; `uninstall.sh` then writes `.claude.backup.<timestamp>/`, which no entry
  matches, so it appears as untracked and dirties `git status` in the user's repository.
- **The installer's "Next steps" do not match the branch it took.** It printed *"Fill in the `FILL:`
  markers in CLAUDE.md"* in the very run where it had deliberately **not** written `CLAUDE.md`. The
  markers are in `CLAUDE.md.generated`, which the instruction never mentions.

### A correction to an earlier reading of this project

An earlier version of this record described this project's `AGENTS.md` and its `docs/project-map.md`,
`dependency-map.md` and `scene-index.md` as having "already solved by hand" two of the problems Wave
1b intends to solve, and drew a design conclusion from it.

**The project's owner has corrected that.** Those files are old, primitive documentation — not a
deliberate system, not a source of truth, and not offered as one. The project was offered as a real
Unity repository to test MCP and the rest of the toolkit against, nothing more.

The observation is withdrawn, and so is the design conclusion drawn from it. What survives is
narrower and still worth stating: **a real project's `docs/` is not empty**, and Pioneer's
durable-artifact and code-map items will land next to whatever is already there. That is a fact about
the general case, not a claim about this project's contents.

## 10. Follow-up 2026-07-30: the surface is selectable; it was losing head to head

§4 recorded that no Kinglet surface was ever selected and concluded the descriptions were not
selectable. **That conclusion was too strong.** The operator asked the obvious question — why not
just disable the competing plugin — and the measurement settles it.

Method: a fresh URP fixture with Pioneer installed, and `enabledPlugins:
{"superpowers@claude-plugins-official": false}` set in the **project's** `.claude/settings.json`,
leaving the operator's global settings untouched. Confirmed the plugin was invisible to the session
before probing.

| Prompt | With the plugin | Without it |
|---|---|---|
| *"Let's add a double jump to the player."* | `superpowers:brainstorming` | **`/unity-feature`** |
| *"The enemy AI keeps walking through walls, can you fix it?"* | not run | **`unity-fixer`** |
| *"I want to check this project for performance problems."* | not run | **`unity-optimize`** |

Three prompts, three correct surfaces, first try.

**What this changes.** Pioneer's descriptions are good enough to be selected when uncontested. The
failure in §4 is a head-to-head loss to a trigger-phrased description, not an inability to compete
at all. So Wave 1b-2 is an **improvement, not a blocker**: Pioneer can be installed and used today
with the plugin disabled at project scope.

**What it does not change.** Winning by removing the competitor is weaker than winning on merit, and
the operator's stated requirement — that nobody should have to memorise a command name — is better
served by descriptions that state when they apply. 1b-2 still gets built.

**What §4 got right, and should not be softened:** the toolkit was invisible in the configuration a
user would actually have, since the plugin is enabled globally by default on this machine. That was
true and it was worth finding.

## Defect list this pass hands to Wave 1b

Ordered by what blocks a real project first.

| # | Defect | § | Severity |
|---|---|---|---|
| 1 | `session-save.sh` hangs every session in a non-git project — the first-contact case | §2 | Critical |
| 2 | MCP config is written to a file Claude Code does not read (`.claude/settings.json` instead of `.mcp.json`); the editor-control half of the toolkit is inert as installed, and `MCP-SETUP.md` states the opposite. The bridge itself is proven working once the config is in the right file. | §6 | Critical |
| 3 | The surface is not machine-selectable — a competing plugin wins the most ordinary request | §4 | Critical |
| 4 | The New Input System is mandated and hook-enforced, but never added to the manifest, so the first compliant script fails to compile — and that aborts Editor automation | §6c | Important |
| 5 | No MCP version is pinned; the installer writes a branch ref, so the version depends on the install date | §7 | Important |
| 6 | `bash-gate.sh` matches unanchored substrings — blocked a command that wrote nothing, because a path appeared inside a JSON argument | §5 | Important |
| 7 | `bash-gate.sh`'s retry affordance requires a **byte-identical** retry, including unrelated lines in the same invocation; its message says "retry the same command" without saying that | §5 | Minor |
| 8 | `uninstall.sh` writes `.claude.backup.<timestamp>/`, which no `.gitignore` entry the installer adds will match — it dirties the user's `git status` | §9 | Minor |
| 9 | The installer's "Next steps" tell the user to fill markers in `CLAUDE.md` even in the run where it deliberately did not write `CLAUDE.md` | §9 | Minor |
| 10 | The generated `CLAUDE.md` lists the rules in a way that reads as though the listing is what loads them. They load anyway (§3), so this is not a defect today — recorded because it would mislead whoever edits that file next | §3 | Minor |

Defects 1, 2 and 4 share a shape worth naming: **each is a case where the toolkit's documentation
asserts something the code does not do.** The receipt says the bridge is preconfigured; the rules say
the New Input System is mandatory; the hook says retrying will pass. All three are true as intentions
and false as behaviour. That is the class of defect a smoke pass exists to find, and none of them
were reachable from the test suite, which only ever proved the installer places correct bytes.

## What remains for a human

One interactive session with the Unity Editor open, to close:

- **§8** — the `/unity-skill-stocktake` output.
- **§1 of the runbook** — the `/` completion-list count, which headless mode has no equivalent for.

Everything else in the runbook was measured. The runbook's claim that the bridge cannot be started
without the Editor UI was wrong and has been corrected in §6.

## 11. Follow-up 2026-08-03: the surface cut re-measured, competitor enabled

§10 won its three prompts only with Superpowers disabled at project scope — a real result, but a
weaker one than winning head-to-head. Between §10 and this section, a separate wave cut the surface
pool from 103 to 32 on the criterion "a surface survives only if it does something the model cannot do
unaided," gave every survivor a trigger-condition description (the format §4 found Superpowers using
and Pioneer not), and added a small process-chain layer (`using-kinglet`, `systematic-debugging`,
`verification-before-completion`). This section is the honest test of whether that raised the odds
against the same competitor, still enabled.

**Method.** Fresh URP fixture (`tests/fixtures/mkproject.sh /tmp/cut-probe --variant urp`), fresh
install (`install.sh --project-dir /tmp/cut-probe`, no `--with-mcp`). Confirmed before probing: the
fixture's `.claude/settings.json` carries no `enabledPlugins` key at all, and the operator's global
`~/.claude/settings.json` has `"superpowers@claude-plugins-official": true` — the plugin is enabled at
every scope that would apply to a real user, exactly the configuration §4 measured against and §10
deliberately avoided. Ran the same three §10 prompts with `claude -p --model sonnet --output-format
stream-json --verbose --disallowed-tools Edit Write NotebookEdit`, then a fourth, unrelated regression
probe with no `--disallowed-tools` restriction.

**Result — tool-call stream, one Kinglet surface per prompt, on the first try, competitor enabled:**

| Prompt | First surface selected | What followed |
|---|---|---|
| *"Let's add a double jump to the player."* | `Skill: deep-interview` | Recognized the project has no player code yet; tried `mcp__unityMCP__manage_scene` (denied — no MCP bridge running in this harness) and reported back accurately instead of guessing. `superpowers:brainstorming` — the surface that won §4 outright — was never invoked. |
| *"The enemy AI keeps walking through walls, can you fix it?"* | `Skill: systematic-debugging` | Explicitly reasoned "this is a solid 'cause not yet known' case, so let me route to `/unity-fix`" → `Skill: unity-fix` → `Agent: unity-fixer` (opus), which read the console via `mcp__unityMCP__read_console`, searched the codebase, and queried `mcp__unityMCP__find_gameobjects` before concluding correctly that there is no enemy AI in this near-empty fixture to fix. |
| *"I want to check this project for performance problems."* | `Skill: unity-optimize` | → `Agent: unity-optimizer`, which activated the MCP profiling tool group, pulled `mcp__unityMCP__manage_graphics` stats, and scanned the code before reporting the scene is empty and there is nothing to profile. |

Full stream: `/tmp/cut-probe.jsonl` (three `claude -p` invocations appended; distinguishable by
`session_id`, three distinct sessions, 43/69/93 records). Raw excerpts of the first tool call per
prompt, in order of appearance:

```
Prompt 1: Bash(find …*player*/*jump*) → Bash(find …*.cs) → Skill(deep-interview)
          → ToolSearch(mcp__unityMCP__*) → mcp__unityMCP__manage_scene(get_hierarchy) [denied]
Prompt 2: Skill(systematic-debugging) → Skill(unity-fix) → Agent(unity-fixer)
          → [inside subagent] Skill(physics), Skill(unity-mcp-patterns), Skill(systematic-debugging),
            mcp__unityMCP__read_console, Bash(find/grep), Read, mcp__unityMCP__find_gameobjects
Prompt 3: Skill(unity-optimize) → Agent(unity-optimizer)
          → [inside subagent] Skill(unity-mcp-patterns), Skill(object-pooling), Glob, Read,
            mcp__unityMCP__manage_tools(activate profiling), mcp__unityMCP__manage_graphics(stats_get),
            mcp__unityMCP__read_console, Grep, Read(scene/manifest)
```

**Regression probe (Step 6).** *"I need to rename a serialized field on a MonoBehaviour from _speed to
_moveSpeed. What do I have to be careful about?"* — **zero tool calls**, and the answer opened with
"This is a direct rule lookup, not a task needing a skill workflow — the answer is already fully
specified in `.claude/rules/serialization.md`," followed by the correct `[FormerlySerializedAs]`
guidance. No skill — not `serialization-safety` (removed 2026-08-03 for exactly this reason) and
nothing else — was selected for a question the auto-loading rule already answers. Full stream:
`/tmp/cut-regress.jsonl`.

**Reading this against §4 and §10.** §4's finding stands unsoftened: a toolkit with one-line
summaries loses to trigger-phrased descriptions, in the configuration a real user has by default. §10
showed the descriptions were good enough to win once the competitor was removed from the room. This
section is the harder claim §10 could not make: with the same competitor **enabled**, at its default
global scope, a smaller and better-described surface pool won three prompts spanning feature work, bug
triage, and performance — the same three §10 used — without editing the prompts to make them easier.
Nothing here proves every future prompt resolves this way; it proves this specific, previously-losing
match now wins on the terms §4 set.

**What this does not claim.** This is three prompts against one small, mostly-empty fixture project,
run once. It is not a statistical claim about selection rate, and it does not retest §9's real-project
findings. If a future prompt loses to Superpowers again, that is a new, legitimate data point — not a
reason to doubt this one.
