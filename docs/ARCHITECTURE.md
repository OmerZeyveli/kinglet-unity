# Architecture

Technical documentation for the everything-claude-unity system.

---

## Design Philosophy

This project follows the architecture established by [everything-claude-code](https://github.com/affaan-m/everything-claude-code), adapted for Unity game development:

- **Convention over configuration** -- drop `.claude/` into any Unity project and it works.
- **Safety by default** -- hooks block destructive operations (scene file edits, meta file corruption) before they happen.
- **MCP as the bridge** -- code changes go through normal file editing; scene/editor changes go through unity-mcp tools.
- **Composable knowledge** -- skills are modular and loaded on demand, not bundled into one massive prompt.
- **Agent specialization** -- each agent has a focused role, specific model selection, and limited tool access.

---

## Component Overview

```
.claude/
  settings.json      Configuration: permissions, hook definitions
  agents/             8 agent definitions (.md files with frontmatter)
  commands/          11 user-invocable slash commands
  hooks/             27 registered shell scripts + _lib.sh (safety, quality, session, learning)
  rules/              6 always-loaded coding standards
  skills/            14 knowledge modules, flat — one directory per skill, no categories
  state/             Session state directory (session.json, tracking files)
  VERSION            Installed version for upgrade tracking
```

(Agent/command/hook/rule counts are as of the 2026-08-03 surface cut, which reduced a 103-surface pool
to 32 on the criterion "a surface survives only if it does something the model cannot do unaided." The
skill count moved to 14 afterward, in the `process-layer-2` wave that added `subagent-driven-implementation`
— see `docs/SKILL-CATALOG.md`. Nothing enforces these exact numbers in text — cross-check against
`ls .claude/agents/*.md | wc -l` etc. if they look stale.)

Supporting files outside `.claude/`:

```
scripts/             Shell scripts for validation (meta, code quality, serialization, architecture)
install.sh           One-command installer
upgrade.sh           Version-aware upgrade with backup and customization preservation
uninstall.sh         Clean removal with backup option
templates/           C# templates for MVS pattern (Model, View, System, LifetimeScope, Message)
benchmarks/          Structural correctness benchmarks for agent output
```

---

## How Agents Work

Agents are Markdown files in `.claude/agents/` with YAML frontmatter that controls their behavior.

### Frontmatter Fields

| Field | Purpose | Example |
|-------|---------|---------|
| `name` | Identifier used by commands | `unity-coder` |
| `description` | One-line summary shown in agent selection | `"Implements Unity features..."` |
| `model` | Which Claude model to use | `opus`, `sonnet`, `haiku` |
| `color` | Terminal display color | `green`, `blue`, `yellow` |
| `tools` | Allowed tool access list | `Read, Write, Edit, Glob, Grep, Bash, mcp__UnityMCP__*` |
| `tools` must include `Skill` | Lets the agent load skills at all | Without it the **Skills to load** block in the body is unactionable |

### Model Selection

- **Opus** -- complex implementation and editor control: `unity-coder`, `unity-fixer`, `unity-optimizer`, `unity-prototyper`, `unity-scene-builder`, `unity-ui-builder` (6 agents)
- **Sonnet** -- read-only review and test execution: `unity-reviewer`, `unity-test-runner` (2 agents)
- **Haiku** -- not used by any current agent. The two Haiku agents this section used to name were
  removed in the 2026-08-03 surface cut, and no surviving agent runs on that tier.

### Tool Access

Agents only have access to the tools listed in their frontmatter. This enforces boundaries:

- `unity-reviewer` has `Read, Glob, Grep` only -- it cannot modify files.
- `unity-scene-builder` has `Read, Glob, Grep, mcp__UnityMCP__*` -- it controls the editor but does not write code.
- `unity-coder` has full access including `Write, Edit, Bash` and MCP tools.

---

## How Commands Work

Commands are Markdown files in `.claude/commands/` with `user-invocable: true` in frontmatter. Users invoke them with `/command-name` in Claude Code.

Commands are orchestration entry points. They:

1. Accept user arguments (via `$ARGUMENTS`)
2. Define a multi-step workflow
3. Delegate to one or more agents
4. Coordinate the overall task

Example flow for `/unity-prototype`:
```
User: /unity-prototype "2D platformer with wall jumping"
  -> Command: unity-prototype.md (decomposes the task)
    -> Agent: unity-prototyper (writes scripts, builds scene via MCP)
      -> Tools: Write (C# files), mcp__UnityMCP__* (scene setup)
```

---

## How Skills Work

Skills are knowledge modules in `.claude/skills/`, one directory per skill:

```
skills/
  assembly-definitions/SKILL.md
  input-system/SKILL.md
  physics/SKILL.md
  ...                              13 in total, flat
```

**Flat, and it has to be.** Claude Code discovers skills at `.claude/skills/<name>/SKILL.md` and
nowhere else. Until 2026-08-03 these 39 skills were filed under `core/`, `gameplay/`, `genre/`,
`systems/` and `third-party/`, inherited from everything-claude-unity — which meant none of them
were ever registered, and the `Skill` tool could not invoke a single one. The categories were a
tidier tree in exchange for the whole feature. They now live in each skill's `description`, which
is what selection actually reads.

The measurement, in an empty project: `.claude/skills/flatprobe/SKILL.md` is listed;
`.claude/skills/category/nestedprobe/SKILL.md` is not. `tests/test-skill-discovery.sh` holds the
line.

There is no `platform/` category and never will be. This toolkit targets PC and console only, so
platform guidance is a rule (`.claude/rules/pc-console.md`, always loaded) rather than a skill.

### Discovery

Claude Code registers every `.claude/skills/<name>/SKILL.md` and offers it to the model as an
invocable skill, described by its `description` frontmatter. That description is the entire
selection mechanism.

There is no glob matching. The `globs:` key that 28 of these skills carried is a Cursor rule
convention that rode in with the vendored frontmatter; nothing in Claude Code reads it, and it has
been removed. Neither is there any preloading — an agent that does not invoke a skill does not have
it. That is why the agents now name the skills they need in a **Skills to load** block and are
granted the `Skill` tool to load them.

### The two frontmatter keys that did nothing

Until 2026-08-03, twelve skills carried `alwaysApply: true` and twenty-eight carried `globs`. Neither
key has ever had an effect in Claude Code — both are Cursor rule conventions inherited with the
vendored everything-claude-unity frontmatter. A 2026-07-30 probe established the first
(`.superpowers/sdd/2026-07-30-alwaysapply-finding.md`); the discovery probe on 2026-08-03 established
the second, and also showed why the first probe's conclusion — "selected by description like every
other skill" — was still too generous. They were not being selected at all. Nested under category
directories, none of them was registered.

Both keys are now stripped from every skill (13, after the 2026-08-03 surface cut reduced the 39
that existed at flattening time), and `tests/test-no-mobile.sh` asserts they stay gone.
A key that reads as a safety control but controls nothing is worse than no key: it gets believed. If
guidance genuinely must reach every session, it belongs in `.claude/rules/`, which CLAUDE.md loads
unconditionally — that mechanism is real, and it is where the serialization and performance rules
already live.

---

## How Hooks Work

Hooks are shell scripts in `.claude/hooks/` configured in `settings.json`. They run automatically at various lifecycle events: before/after tool invocations, before context compaction, on session start, and on session stop.

All 27 registered hooks source a shared library (`_lib.sh`, a sourced library and not itself a hook)
that provides kill switches, profile filtering, and utility functions. Hooks are organized into three
**profile levels** -- `minimal` (7 cumulative, including `session-brief.sh`, which declares no
`HOOK_PROFILE_LEVEL` and always runs), `standard` (20 cumulative), and `strict` (27 cumulative, all
of them). Set the active profile via `UNITY_HOOK_PROFILE=standard`.

### Event Types

| Event | When | Hook Types |
|-------|------|------------|
| PreToolUse | Before a tool executes | Blocking (exit 2) or allow (exit 0) |
| PostToolUse | After a tool executes | Advisory warnings and tracking (exit 0) |
| PreCompact | Before context compaction | State preservation (exit 0) |
| SessionStart | When a conversation begins | State restoration (exit 0) |
| Stop | When the agent stops | Validation, persistence, learning, notifications (exit 0) |

### Hook Summary

| Hook | Event | Matcher | Profile | Type |
|------|-------|---------|---------|------|
| `block-scene-edit` | PreToolUse | Edit\|Write | minimal | Blocking |
| `block-meta-edit` | PreToolUse | Edit\|Write | minimal | Blocking |
| `guard-editor-runtime` | PreToolUse | Edit\|Write | minimal | Blocking |
| `block-legacy-input` | PreToolUse | Edit\|Write | minimal | Blocking |
| `guard-project-config` | PreToolUse | Edit\|Write | standard | Blocking |
| `gateguard` | PreToolUse | Edit\|Write | strict | Blocking |
| `block-projectsettings` | PreToolUse | Bash | minimal | Blocking |
| `bash-gate` | PreToolUse | Bash | standard | Blocking |
| `track-reads` | PostToolUse | Read | strict | Advisory |
| `warn-serialization` | PostToolUse | Edit\|Write | standard | Advisory |
| `warn-filename` | PostToolUse | Edit\|Write | standard | Advisory |
| `warn-platform-defines` | PostToolUse | Edit\|Write | standard | Advisory |
| `quality-gate` | PostToolUse | Edit\|Write | standard | Advisory |
| `track-edits` | PostToolUse | Edit\|Write | standard | Advisory |
| `suggest-verify` | PostToolUse | Edit\|Write | standard | Advisory |
| `validate-commit` | PostToolUse | Bash | standard | Advisory |
| `build-analyze` | PostToolUse | Bash | strict | Advisory |
| `cost-tracker` | PostToolUse | (all) | strict | Advisory |
| `instinct-capture` | PostToolUse | (all) | strict | Advisory |
| `pre-compact` | PreCompact | (all) | minimal | Advisory |
| `session-restore` | SessionStart | (all) | standard | Advisory |
| `session-brief` | SessionStart | startup\|clear\|compact | always (no `HOOK_PROFILE_LEVEL`) | Advisory |
| `stop-validate` | Stop | (all) | standard | Advisory |
| `session-save` | Stop | (all) | standard | Advisory |
| `auto-learn` | Stop | (all) | strict | Advisory |
| `instinct-distill` | Stop | (all) | strict | Advisory |
| `notify` | Stop | (all) | standard | Advisory |

### Hook Input

Hooks receive JSON on stdin with the tool invocation details (`tool_name`, `tool_input`). They use `jq` to parse and inspect the operation.

For the full hook catalog with detailed descriptions, environment variables, and configuration, see [HOOK-REFERENCE.md](HOOK-REFERENCE.md).

---

## How Rules Work

Rules are Markdown files in `.claude/rules/` that are always loaded as context for every conversation. They define coding standards that Claude follows:

| Rule | Content |
|------|---------|
| `csharp-unity.md` | Field naming (`_lowerCamelCase` private, `UPPER_SNAKE_CASE` const), explicit types, sealed by default, structure ordering |
| `performance.md` | Zero allocations in Update, cache GetComponent, NonAlloc physics, object pooling |
| `serialization.md` | FormerlySerializedAs on renames, field exposure, Unity null checks |
| `architecture.md` | Model-View-System, VContainer DI (no service locators), MessagePipe messaging (no SO event channels), UniTask (no coroutines), no god objects |
| `unity-specifics.md` | Editor vs runtime guards, lifecycle order, threading, coroutine gotchas |
| `pc-console.md` | PC/console addendum -- keyboard/mouse + gamepad input, rebinding, min-spec/console/high-end budgets, BC7/BC5 compression, ultrawide and focus handling |

Rules are not optional. They represent hard constraints that every agent follows.

---

## The MCP Integration

The unity-mcp bridge connects Claude Code to the Unity Editor via HTTP. It exposes tools for:

- **Scene management** -- create, load, save, modify scenes
- **GameObject operations** -- create, parent, position, configure
- **Component management** -- add, remove, configure components
- **Prefab operations** -- create, edit, instantiate prefabs
- **Physics** -- layers, collision matrix, raycasts
- **Graphics** -- materials, lighting, rendering settings
- **Profiler** -- frame timing, memory snapshots, rendering stats
- **Build** -- platform switching, player settings, trigger builds
- **Tests** -- run EditMode/PlayMode tests, get results

### The batch_execute Pattern

Individual MCP calls have network overhead. The `batch_execute` tool bundles multiple operations into a single HTTP request, providing 10-100x speedup for multi-step scene construction.

```
batch_execute([
  { "tool": "manage_gameobject", "params": { "action": "create", "name": "Player" } },
  { "tool": "manage_components", "params": { "action": "add", "gameobject": "Player", "component": "Rigidbody" } },
  { "tool": "manage_components", "params": { "action": "add", "gameobject": "Player", "component": "CapsuleCollider" } }
])
```

---

## Agent Interaction Pattern

The standard flow through the system:

```
User Input
  |
  v
Command (orchestration)        <- .claude/commands/
  |
  v
Agent (specialized executor)   <- .claude/agents/
  |                  |
  v                  v
File Tools         MCP Tools
(Read/Write/Edit)  (mcp__UnityMCP__*)
  |                  |
  v                  v
C# Source Files    Unity Editor
```

### Three Agent Categories (post-2026-08-03 cut, 8 agents total)

Read each agent's `tools:` frontmatter for ground truth; these are the three shapes it takes today.

1. **Read-Only Agent** -- read and analyze only, no file modification or MCP access
   - `unity-reviewer` (`Skill, Read, Glob, Grep`)

2. **MCP-Powered Agent** -- controls the Unity Editor, does not write files
   - `unity-scene-builder` (`Skill, Read, Glob, Grep, mcp__UnityMCP__*`)

3. **Hybrid Agents** -- both code (`Write, Edit`) and MCP access
   - `unity-coder`, `unity-fixer`, `unity-optimizer`, `unity-prototyper`, `unity-test-runner`,
     `unity-ui-builder`

The read-only-code / MCP-without-writing category and the Donchitos documentation-only
design/production category that used to round this out to five were removed 2026-08-03; see
`provenance-skip.tsv` for the full list of cut agent names.

---

## Settings.json Structure

```json
{
  "permissions": {
    "defaultMode": "acceptEdits"     // Claude can edit files without asking
  },
  "hooks": {
    "PreToolUse": [ ... ],           // Blocking hooks (safety gates)
    "PostToolUse": [ ... ],          // Warning hooks (quality, tracking)
    "PreCompact": [ ... ],           // State preservation before compaction
    "SessionStart": [ ... ],         // Session restoration
    "Stop": [ ... ]                  // Validation, persistence, learning, notifications
  }
}
```

`.claude/settings.json` has no `mcpServers` key, and never has: Claude Code does not read MCP server
config from there. The unity-mcp bridge endpoint (`http://localhost:8080/mcp`) is configured in
`.mcp.json` at the project root instead — `install.sh` writes it in a separate step (see "Step 8b"
in `install.sh`), independent of `.claude/settings.json`.

The `settings.local.json.template` provides a starting point for per-developer overrides.

---

## File Organization

This structure follows Claude Code's discovery conventions:

- **agents/** -- auto-discovered by name when referenced by commands or the user
- **commands/** -- auto-discovered and exposed as `/slash-commands`
- **skills/** -- registered one level deep (`skills/<name>/SKILL.md`), selected by description, invoked with the `Skill` tool
- **hooks/** -- referenced by path in `settings.json`, executed by Claude Code runtime
- **rules/** -- all files in this directory are loaded as context automatically
- **state/** -- runtime session state (session.json, tracking files), git-ignored

Each component is a standalone Markdown file. No build step, no compilation, no registration. Drop files in the right directory and they work.

---

## Hook Kill Switch System

All hooks source a shared library (`.claude/hooks/_lib.sh`) that provides environment variable overrides:

```
DISABLE_UNITY_HOOKS=1              All hooks exit 0 immediately
DISABLE_HOOK_<NAME>=1              Specific hook exits 0 (name derived from filename, uppercased, hyphens→underscores)
UNITY_HOOK_MODE=warn               Blocking hooks (exit 2) downgraded to warnings (exit 0)
```

The `unity_hook_block()` function replaces direct `exit 2` calls in blocking hooks. It respects `UNITY_HOOK_MODE=warn`, printing the block message as a warning instead.

Configure overrides in `.claude/settings.local.json` (git-ignored) so they don't affect the team.

---

## State Management

Session state is persisted in the `.claude/state/` directory (falls back to `/tmp/unity-claude-hooks` if the directory does not exist). This enables conversation continuity across sessions and context compaction.

### session.json Schema

```json
{
  "schema_version": 1,
  "branch": "feature/player-movement",
  "workflow_phase": "Execute",
  "modified_files": ["Assets/Scripts/PlayerSystem.cs", "Assets/Scripts/PlayerModel.cs"],
  "recent_commits": ["abc1234 Add PlayerSystem with movement"],
  "session_duration": "12m 34s",
  "tool_calls": 47,
  "warnings_count": 3,
  "saved_at": "2024-01-15T14:30:22Z",
  "plan": {
    "description": "Implement player movement",
    "steps": [
      { "name": "Write PlayerModel", "status": "done" },
      { "name": "Write PlayerSystem", "status": "in-progress" }
    ]
  },
  "verification": {
    "last_iteration": 2
  },
  "agent_context": {
    "last_agent": "unity-coder"
  }
}
```

### Tracking Files

| File | Purpose | Written By |
|------|---------|------------|
| `session.json` | Full session state for restore | `session-save.sh` |
| `session-start-time` | Epoch timestamp for duration calculation | `session-restore.sh` |
| `gateguard-reads.txt` | Files read during session (for GateGuard) | `track-reads.sh` |
| `session-edits.txt` | Files edited during session | `track-edits.sh` |
| `session-cost.jsonl` | Tool call log (tool name + timestamp) | `cost-tracker.sh` |
| `learnings.jsonl` | Extracted session patterns | `auto-learn.sh` |
| `session-warnings.txt` | Hook warnings for analytics | Various hooks |
| `precompact-state.md` | Git state snapshot before compaction | `pre-compact.sh` |

### Session TTL

Sessions expire after a configurable time-to-live. Set via `UNITY_SESSION_TTL_HOURS` (default: 4 hours). The `session-restore.sh` hook checks the `saved_at` timestamp and discards stale sessions.

---

## Workflow Pipeline

The `/unity-workflow` command implements a staged pipeline inspired by modern AI coding orchestrators:

```
Clarify → Plan → Execute → Verify
```

1. **Clarify** -- interview the user about requirements, constraints, and acceptance criteria
2. **Plan** -- analyze the project, identify subsystems, choose agents, present an implementation plan
3. **Execute** -- route to appropriate agent(s) (coder, prototyper, UI builder, etc.)
4. **Verify** -- perform a verify-fix loop directly in the command body (no dedicated verifier
   agent — that agent was removed 2026-08-03; see `provenance-skip.tsv`)

### Verify-Fix Loop

`/unity-workflow` Phase 4 runs a bounded loop (max 3 iterations) directly, without a dedicated agent:

```
Invoke unity-reviewer (read-only) → Auto-fix safe issues → Run tests → Re-verify
```

Auto-fixable issues include: missing `[FormerlySerializedAs]`, `?.` on Unity objects, uncached `GetComponent` in Update, `tag ==` instead of `CompareTag`, missing `#if UNITY_EDITOR` guards.

Issues requiring human judgment (architecture, design patterns, ambiguous trade-offs) are reported but not auto-fixed.

---

## Benchmarking

The `benchmarks/` directory contains structural correctness benchmarks for agent output. Each benchmark scenario defines a prompt, expected files, required patterns, and forbidden patterns.

Benchmarks do not invoke Claude Code directly. The workflow is:

1. Run Claude Code manually with a scenario prompt in a scratch Unity project.
2. Run `bash benchmarks/run-benchmarks.sh --workdir /path/to/output` to score the result.
3. Use `--compare` to diff against a previous run and detect regressions.

Results are written to `benchmarks/results/` as timestamped JSON files. Use benchmarks to validate that changes to agents, skills, or rules do not degrade output quality.

See [BENCHMARK-GUIDE.md](BENCHMARK-GUIDE.md) for the full reference.

---

## Version Management

The `.claude/VERSION` file tracks the installed version. The `upgrade.sh` script compares source and target versions, creates a backup, preserves user customizations (settings.local.json, custom agents/commands/skills), and reports a diff of changes.
