# Architecture

Technical documentation for Kinglet Pioneer.

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
  commands/           9 user-invocable slash commands
  hooks/             12 registered shell scripts + _lib.sh (safety, session, quality warnings)
  rules/              6 always-loaded coding standards
  skills/            16 knowledge modules, flat — one directory per skill, no categories
  state/             Session state directory (session.json, tracking files)
  VERSION            Installed version for upgrade tracking
```

(The agent, command and skill counts above are **derived and guarded**: `tests/test-derived-counts.sh`
counts `.claude/agents/*.md`, `.claude/commands/*.md` and `.claude/skills/*/SKILL.md` in the tree and
fails when this block, `README.md` or `docs/SKILL-CATALOG.md` drifts from it. Do not "cross-check if
they look stale" — the suite does it on every run. That is the correction this parenthetical needed:
it used to say nothing enforced these numbers, and while it said so, four of them went stale at once.
The pool itself came from the 2026-08-03 surface cut, which reduced 103 surfaces — agents, commands,
skills and hooks — to 32 on the criterion "a surface survives only if it does something the model
cannot do unaided"; the `process-layer-2` wave then added a fourteenth skill, and the 2026-08-10
process-chain wave traded two commands for two skills. The **hook counts here are derived and
guarded** by the same file — see "How Hooks Work" below, which says so 150 lines down; this sentence
claimed the opposite until 2026-08-14, because the commit that added the guard and the commit that
documented it were the first and last of one task and neither reread this one. **The rule count is
derived too — and still unguarded in this file.** `tests/test-derived-counts.sh:36` counts
`.claude/rules/*.md` into `DCS_RULES`, but that guard's claim table carries a rules row for
`README.md` and `docs/GETTING-STARTED.md` and none for `docs/ARCHITECTURE.md`. Measured 2026-08-14
by mutation: changing the `6` above to `99` leaves `tests/test-derived-counts.sh` green, while the
same change to the `8` on the agents line reds it, and the same change to
`docs/GETTING-STARTED.md`'s rule count reds it. So the gap this parenthetical names is **a missing
row, not a missing derivation** — it read "nothing derives `.claude/rules/*`" until 2026-08-14, in
the same commit that added `DCS_RULES`.)

Supporting files outside `.claude/`:

```
scripts/             Shell scripts: the two surviving validators (serialization, assembly
                     definitions), the pipeline detector, the CLAUDE.md generator, the doctor,
                     the dangling-reference sweep, and this repo's provenance check
install.sh           One-command installer
uninstall.sh         Receipt-driven removal — the installer's inverse, not a separate flow
templates/           C# templates for MVS pattern (Model, View, System, LifetimeScope, Message)
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
  ...                              16 in total, flat
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

Both keys are now stripped from every skill — all 16 of them: the 13 that survived the 2026-08-03
surface cut out of the 39 that existed at flattening time, plus the three the process-chain work has
added since — and `tests/test-no-mobile.sh` asserts they stay gone.
A key that reads as a safety control but controls nothing is worse than no key: it gets believed. If
guidance genuinely must reach every session, it belongs in `.claude/rules/`, which CLAUDE.md loads
unconditionally — that mechanism is real, and it is where the serialization and performance rules
already live.

---

## How Hooks Work

Hooks are shell scripts in `.claude/hooks/` configured in `settings.json`. They run automatically at various lifecycle events: before/after tool invocations, before context compaction, on session start, and on session stop.

Of the 12 registered hooks, 11 source a shared library (`_lib.sh`, a sourced library and not itself
a hook) that provides kill switches, profile filtering, and utility functions. `session-brief.sh`
sources nothing and carries the two kill switches inline instead; until 2026-08-14 it carried
neither, which made it the one hook `DISABLE_UNITY_HOOKS=1` did not reach. Hooks are organized into
three
**profile levels** -- `minimal` (4 cumulative, one of which declares no `HOOK_PROFILE_LEVEL` at all
and therefore runs under every profile), `standard` (12 cumulative), and `strict` (12 cumulative).
Set the active profile via `UNITY_HOOK_PROFILE=standard`.

**No hook declares `strict` any more**, so `standard` and `strict` are the same set. That is a
consequence of the 2026-08-13 cut, not an oversight: every strict-declared hook was removed, because
`UNITY_HOOK_PROFILE` is set nowhere in `settings.json`, `install.sh` or `scripts/`, so `standard` is
the only profile that has ever been active and seven hooks had never run.

The tier that is left doing work is `minimal`, and **it drops 8 of the 12 — among them a blocking
gate and the hook that warns about the silent-data-loss case `.claude/rules/serialization.md` opens
with.** It reads as a performance setting and is in fact a safety setting; do not set it without
reading what it costs.

**Which hooks those are is in [HOOK-REFERENCE.md](HOOK-REFERENCE.md), named there and nowhere else.**
That document's list is derived from the hook files and asserted as a set by
`tests/test-derived-counts.sh`. This file names **no hook's profile, event or matcher** — it states
only counts, and those are guarded. Two documents listing one set by hand is how the list goes stale
in one of them, and a name here would be the whole of that failure at three-quarters the size.

(The Tracking Files table further down does name hooks, as the *writers* of state files. That is a
different fact from profile membership, and it is asserted too: `tests/test-derived-counts.sh` checks
that every hook named there still exists.)

### Event Types

These are the events this toolkit registers, not every event Claude Code emits. The **first column**
is asserted against `.claude/settings.json` in both directions by `tests/test-derived-counts.sh`: a
row here that no registration uses, and a registration whose event has no row, both fail.
`PreCompact` had a row here after its last registration was removed on 2026-08-13, twelve lines
above a paragraph that said so.

**The third column is read by nothing**, and it rotted exactly where you would expect. The `Stop`
row read *"Validation, persistence, learning, notifications"* until 2026-08-14, having lost three of
its four members without one word changing: validation was `stop-validate.sh`, learning was
`auto-learn.sh` and `instinct-distill.sh`, notifications was `notify.sh`, and all four were removed
on 2026-08-13 (`provenance-skip.tsv` carries each as `rule=absent`). `Stop` has one registration now,
`session-save.sh`. Derive a cell before trusting it.

| Event | When | Hook Types |
|-------|------|------------|
| PreToolUse | Before a tool executes | Blocking (exit 2) or allow (exit 0) |
| PostToolUse | After a tool executes | Advisory warnings and tracking (exit 0) |
| SessionStart | When a conversation begins | State restoration (exit 0) |
| Stop | When the agent stops | Persistence (exit 0) |

### Hook Summary

**Deliberately not here.** The per-hook table that used to sit at this point restated every hook's
event, matcher and profile by hand — the same membership `docs/HOOK-REFERENCE.md` states, in a second
place, kept in step by nothing. A wrong value in it was silent, and this file's own paragraph above
argues against exactly that duplication; it was contradicting itself twenty lines apart.

**[HOOK-REFERENCE.md](HOOK-REFERENCE.md) holds the membership, and it is guarded**:
`tests/test-derived-counts.sh` compares that document's per-hook `Profile:` lines, its summary
table's profile column, and its event and matcher columns against the hook files and
`.claude/settings.json` — by name, in both directions.

There is no `PreCompact` or `PostToolUse`-on-`Bash` registration left. Fifteen hooks were removed on
2026-08-13 when the surface criterion — *does it do something the model cannot do unaided?* — was
applied to this directory for the first time; `provenance-skip.tsv` carries the ground for each, and
`scripts/check-provenance.sh` fails if any of them reappears.

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

Every hook honours the overrides below. 11 of the 12 get them by sourcing a shared library
(`.claude/hooks/_lib.sh`); `session-brief.sh` implements the two kill switches inline and sources
nothing, deliberately — it runs at `SessionStart`, and a library failure there is a session that does
not start. This sentence read *"All hooks source a shared library"* until 2026-08-14, contradicting
**`## How Hooks Work`**'s own *"`session-brief.sh` sources nothing and carries the two kill switches
inline instead"*, and at that point the exception honoured no kill switch at all.

**That correction cited the contradiction as a quotation its own commit had just deleted.** Until
2026-08-14 the sentence above quoted *"except one, which sources nothing"* as **190 lines above**.
Derived from history rather than from this file: `38dec6c` wrote that wording into `## How Hooks
Work` (*"…except one, which sources nothing and therefore honours no kill switch"*, wrapped across
two lines); `3b4cc85` **rewrote that sentence into the one quoted above and, in the same commit,
quoted the wording it had just removed as this file's own**. The quotation was true for one commit
and false from the commit that wrote it. The distance was never right — in `3b4cc85` the citing line
is 378 and the real text is at 178, which is 200 lines, not 190.

**Two rules come out of it.** *Cite by anchor, not by distance* — a line count is stale the next time
anything above it is edited, and nothing here reads it: `tests/test-citations-resolve.sh` resolves
`file:line` shapes and never compares quoted text against the location cited, so a quotation is the
one kind of pointer this tree cannot check. And *flatten before concluding a string is absent* — a
line-oriented `grep` for the full quoted phrase returns 0 at `3b4cc85^` while
`tr '\n' ' ' | tr -s ' '` finds it, because the wrap falls between "sources" and "nothing". The same
wrap-blindness hid the `minimal`-profile undercount in `docs/HOOK-REFERENCE.md`, and it is how a
sweep talks itself into "this file has never said that".

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
| `session-edits.txt` | Files edited during session | `track-edits.sh` |
| `session-warnings.txt` | Hook warnings for analytics | `bash-gate.sh` |

`_lib.sh` still defines paths for `gateguard-reads.txt`, `session-cost.jsonl`, `learnings.jsonl` and
`notify-event.json`, and `session-restore.sh` still clears three of them at session start, but the
hooks that wrote and read them were removed on 2026-08-13. `session-save.sh` reads
`session-cost.jsonl` and `precompact-state.md` behind `[ -f ]` guards, so it now reports 0 tool calls
and an empty workflow phase rather than failing.

### Session TTL

Sessions expire after a configurable time-to-live. Set via `UNITY_SESSION_TTL_HOURS` (default: 4 hours). The `session-restore.sh` hook checks the `saved_at` timestamp and discards stale sessions.

---

## Workflow Pipeline

The process chain implements a staged pipeline inspired by modern AI coding orchestrators:

```
Clarify → Plan → Execute → Verify
```

Until 2026-08-10 the pipeline was a single command that sequenced the stages. It is now a chain of
skills, each naming the next: a command that only sequences other surfaces is a second definition of
the chain, and the two that did were deleted (see `provenance-skip.tsv`, and D7 in
`docs/superpowers/specs/2026-08-10-kinglet-process-chain-design.md`). Every stage can therefore be
entered directly, and no stage is reachable only by typing a command name nobody remembers.

1. **Clarify** -- `unity-brainstorming` interviews the user about requirements, constraints and
   acceptance criteria, weighs 2-3 approaches, and writes the decision to
   `docs/features/<slug>/design.md`
2. **Plan** -- `unity-planning` analyzes the project, identifies subsystems, and writes a
   task-by-task plan to `docs/features/<slug>/plan.md`. It also adopts a plan written elsewhere, and
   it is where the execution branch is chosen and recorded
3. **Execute** -- the recorded branch runs the plan and routes to the agents (coder, prototyper, UI
   builder, etc.): `subagent-driven-implementation` with a fresh implementer per task and a review
   gate between tasks, or `unity-execution` inline in this session
4. **Verify** -- `unity-execution` performs a verify-fix loop directly in its own body (no dedicated
   verifier agent — that agent was removed 2026-08-03; see `provenance-skip.tsv`)

### Verify-Fix Loop

`unity-execution` runs a bounded loop (max 3 iterations) directly, without a dedicated agent:

```
Invoke unity-reviewer (read-only) → Auto-fix safe issues → Run tests → Re-verify
```

Auto-fixable issues include: missing `[FormerlySerializedAs]`, `?.` on Unity objects, uncached `GetComponent` in Update, `tag ==` instead of `CompareTag`, missing `#if UNITY_EDITOR` guards.

Issues requiring human judgment (architecture, design patterns, ambiguous trade-offs) are reported but not auto-fixed.

---

## Version Management

`.claude/VERSION` carries the toolkit version, and the installer reads it and stamps it into the
receipt's `# toolkit-version:` header.

**There is no separate upgrade path — upgrading is re-running `install.sh`.** It reads
`.claude/state/install-receipt.tsv`, recognises the existing install, and prints the version it is
moving from and to. Files you edited are reported and kept; untouched toolkit files are replaced.
Measured on a real install with one payload file edited: *"Existing Kinglet install found (version
3.0.0-pioneer.1) — upgrading to 3.0.0-pioneer.1"*, then *"Installed 66 file(s), kept 1 of yours."*
Your `settings.local.json` is never in the payload, so nothing overwrites it.

**Two sections used to sit here and both described paths this repository forbids.** A `## Benchmarking`
section documented `benchmarks/run-benchmarks.sh`, `benchmarks/results/` and a `BENCHMARK-GUIDE.md`;
this paragraph's own predecessor described an `upgrade.sh` that "compares source and target versions,
creates a backup, preserves user customizations". `benchmarks/`, `upgrade.sh` and
`docs/BENCHMARK-GUIDE.md` are all `rule=absent` in `provenance-skip.tsv` — paths that must **never**
exist here — and `scripts/check-provenance.sh` fails if any reappears. The one-line directory-listing
entries for two of them were removed on 2026-08-14 and these sections were left standing in the same
file, which is why the removal is recorded here rather than only in the manifest.
