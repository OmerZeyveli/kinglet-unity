# Pioneer smoke pass

**Date run:** 2026-07-29
**Host:** Pop!_OS, Linux 7.0.11-76070011-generic, x86_64
**Unity:** 6000.3.18f1 (5ebeb53e4c07), created via `-batchmode -createProject`
**Render pipeline:** Built-in — *not* URP. `-createProject` produces a built-in project, and the
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
- **The MCP-dependent measurements are incomplete.** The package installs and compiles; the bridge
  does not auto-start in batchmode. See §6.

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

## 6. MCP — partially measured

- **Package resolution: pass.** `install.sh --with-mcp` wrote the dependency into
  `Packages/manifest.json`, and Unity fetched and compiled it —
  `Library/PackageCache/com.coplaydev.unity-mcp@a4c2d0a84573`, with `MCPForUnity.Editor.dll` and
  `MCPForUnity.Runtime.dll` built. No compile errors.
- **Bridge start: not measured.** With the Editor running in `-batchmode -nographics`, nothing
  listened on `localhost:8080`. The bridge is started from the Editor UI
  (`Window > MCP for Unity > Auto-Setup`), which batchmode has no path to.
- **Therefore untested:** whether `mcp__unityMCP__*` tools work with the bridge up, and — the more
  important one — whether they fail **loudly** with the bridge down or silently no-op. That
  distinction is a design requirement and it remains unverified.

**This needs one interactive pass on a machine with the Editor open.** It is the only part of the
runbook that could not be automated.

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

## Defect list this pass hands to Wave 1b

Ordered by what blocks a real project first.

1. **`session-save.sh` hangs any session in a non-git project** (§2). Highest priority: it makes the
   toolkit unusable on first contact with a new Unity project.
2. **The surface is not machine-selectable** (§4). Promoted to the first content item of Wave 1b.
3. **No MCP version is pinned; the installer tracks `#main`** (§7).
4. **`bash-gate.sh` matches unanchored substrings** (§5) — false positives on harmless commands.
5. **The generated `CLAUDE.md` names the rules but does not import them** — they load anyway (§3), so
   this is not a defect today; recorded because the file reads as though the listing is what loads
   them, which would mislead anyone editing it.

## What remains for a human

An interactive session with the Unity Editor open and the MCP bridge started, to close §6 (bridge-up
and bridge-down behaviour), §8 (stocktake), and the `/` completion-list count from the runbook's §1.
