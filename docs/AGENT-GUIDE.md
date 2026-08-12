# Agent Guide

How to use, customize, and create agents for Kinglet Pioneer.

---

## All 8 Agents at a Glance

Every agent in this toolkit is an ECU-origin `unity-*` implementer with `mcp__UnityMCP__*` tools that
writes C# and drives the editor. An earlier design/production layer (`game-designer`,
`systems-designer`, `level-designer`, `creative-director`, `technical-director`, `narrative-director`,
`world-builder`, `writer` — documentation-only, no MCP tools) and a second engineering tier
(`unity-coder-lite`, `unity-fixer-lite`, `unity-shader-dev`, `unity-network-dev`, `unity-build-runner`,
`unity-migrator`, `unity-verifier`, `unity-scout`, `unity-linter`, `unity-security-reviewer`,
`unity-git-master`, `unity-critic`) existed in earlier builds of this toolkit and were removed in the
2026-08-03 surface cut — a surface survives only if it does something the model cannot do unaided, and
none of these passed that test. See `provenance-skip.tsv` and `MERGE-NOTES.md`.

| Agent | Model | Description |
|-------|-------|-------------|
| `unity-coder` | opus | Feature work that touches existing architecture — new Model/System/View split, VContainer registration, cross-system messaging. Dispatched by whichever execution branch the plan recorded — `subagent-driven-implementation` or `unity-execution`. |
| `unity-fixer` | opus | A bug whose cause isn't obvious yet — investigates across execution order, coroutine lifecycle, destroyed-object access, live API behavior. Invoked by `/unity-fix`. |
| `unity-optimizer` | opus | Profiles and fixes CPU/GPU bottlenecks, GC spikes, draw-call issues, shader variant bloat via the MCP profiler. Invoked by `/unity-optimize`. |
| `unity-prototyper` | opus | Builds a new, disposable test scene end-to-end from a mechanic description — scripts, physics, camera, wiring — via MCP. Invoked by `/unity-prototype`. |
| `unity-reviewer` | sonnet | Read-only review of C# changes for Unity-specific correctness, performance, and serialization pitfalls. Invoked by `/unity-review`. |
| `unity-scene-builder` | opus | Builds or reorganizes a scene from a natural-language description via MCP. Does not write C#. Invoked by `/unity-scene`. |
| `unity-test-runner` | sonnet | Writes and executes EditMode/PlayMode tests, reports results via MCP `run_tests`. Invoked by `/unity-test`. |
| `unity-ui-builder` | opus | Builds a UI screen — UGUI Canvas or UI Toolkit, gamepad focus navigation, responsive layout. Invoked by `/unity-ui`. |

---

## When to Use Each Agent

```
What do you need?
|
+-- Write new gameplay code?
|     +-- From scratch with a scene? ---------> unity-prototyper
|     +-- Adding to existing architecture? ---> unity-coder
|     +-- UI screens? -------------------------> unity-ui-builder
|
+-- Build or modify a scene?
|     +-- Scene layout from description? ------> unity-scene-builder
|
+-- Fix or improve existing code?
|     +-- Bug / error in console? -------------> unity-fixer
|     +-- Performance issue? ------------------> unity-optimizer
|     +-- Code review? ------------------------> unity-reviewer
|
+-- Test?
      +-- Write and run tests? ----------------> unity-test-runner
```

Seven of the eight are invoked by exactly one command of the same shape (`unity-fixer` ↔
`/unity-fix`, `unity-reviewer` ↔ `/unity-review`, etc.) — see `docs/MODEL-ROUTING.md`. Most users go
through the command, not the agent name.

`unity-coder` is the exception since 2026-08-10: the command that routed to it only sequenced other
surfaces and was deleted with the rest of the chain-duplicating commands, so the agent is now
dispatched by whichever execution branch the plan recorded. It is still selectable by name.

---

## How Agents Are Selected

Agents are invoked in two ways:

1. **By commands** -- when you run `/unity-prototype`, the command delegates to the `unity-prototyper` agent automatically.
2. **Manually** -- you can ask Claude to use a specific agent: "Use the unity-reviewer agent to check this file."

Most users interact through commands and never need to name agents directly. The command layer handles agent selection based on the task.

---

## Agent Frontmatter Reference

Every agent is a Markdown file in `.claude/agents/` with YAML frontmatter:

```yaml
---
name: unity-coder                    # Unique identifier
description: "Implements features"   # One-line summary
model: opus                          # opus | sonnet | haiku
color: green                         # Terminal display color
tools: Read, Write, Edit, Glob, Grep, Bash, mcp__UnityMCP__*
---
```

### Field Details

**name** -- Must be unique across all agents. Used by commands to reference the agent.

**description** -- Displayed when listing agents. Keep it under 120 characters.

**model** -- Controls which Claude model runs the agent:
- `opus` -- best reasoning, creative implementation, complex debugging
- `sonnet` -- fast and capable, good for review, analysis, and structured tasks
- `haiku` -- fastest and cheapest, suitable for simple lookups and formatting

**color** -- Visual indicator in the terminal. Options: red, green, yellow, blue, magenta, cyan.

**tools** -- Comma-separated list of allowed tools. Common values:
- `Read, Glob, Grep` -- read-only access (reviewers, analyzers)
- `Read, Write, Edit, Glob, Grep, Bash` -- full code access
- `mcp__UnityMCP__*` -- all unity-mcp tools (wildcard)
- `Agent` -- ability to spawn sub-agents

---

## Customizing Agents

### Changing the Model

If an agent is too slow or too expensive for your needs, change the `model` field:

```yaml
# Make the reviewer use haiku for faster, cheaper reviews
model: haiku
```

Trade-off: cheaper models may miss subtle Unity-specific issues.

### Adding or Removing Tools

To give the reviewer write access for auto-fixing:

```yaml
# Before
tools: Read, Glob, Grep

# After
tools: Read, Write, Edit, Glob, Grep
```

To remove MCP access from an agent (if you do not use unity-mcp):

```yaml
# Before
tools: Read, Write, Edit, Glob, Grep, Bash, Agent, mcp__UnityMCP__*

# After
tools: Read, Write, Edit, Glob, Grep, Bash, Agent
```

### Editing Instructions

The Markdown body below the frontmatter contains the agent's instructions. You can:

- Add project-specific conventions
- Remove checklist items that do not apply
- Add new checks relevant to your codebase
- Reference additional skills to load

---

## Creating a New Agent

### Step 1: Create the File

Create a new `.md` file in `.claude/agents/`:

```bash
touch .claude/agents/unity-localization.md
```

### Step 2: Write the Frontmatter

```yaml
---
name: unity-localization
description: "Manages localization — string tables, font assets, RTL support, locale switching, and Unity Localization package integration."
model: sonnet
color: cyan
tools: Read, Write, Edit, Glob, Grep, Bash
---
```

### Step 3: Write the Instructions

```markdown
# Unity Localization Agent

You manage localization for Unity projects using the Unity Localization package.

## Before Making Changes

1. Check if Unity Localization package is installed in Packages/manifest.json
2. Identify existing string tables in Assets/Localization/
3. Check the current locale setup in ProjectSettings

## Tasks You Handle

- Creating and populating string tables
- Setting up locale selectors (system language, player prefs, command line)
- Configuring font assets for different scripts (CJK, Arabic, Devanagari)
- RTL layout support
- Smart strings with pluralization and gender
- Addressable asset tables for localized sprites/audio

## Rules

- Always use table references, never hardcoded strings
- String table entries use snake_case keys: `menu_start_game`, `dialog_npc_greeting_01`
- Every user-facing string must go through the localization system
- Provide fallback locale (English) for every entry
```

### Step 4: Create a Command (Optional)

To make your agent accessible via a slash command, create `.claude/commands/unity-localize.md`:

```yaml
---
name: unity-localize
description: "Manage project localization"
user-invocable: true
args: task_description
---

# /unity-localize

Use the `unity-localization` agent to handle: **$ARGUMENTS**
```

---

## Model Selection Guide

| Use Case | Recommended Model | Reasoning |
|----------|-------------------|-----------|
| Implement a new gameplay system | opus | Needs to understand architecture, write correct code, wire up components |
| Build a scene from description | opus | Creative interpretation, complex MCP tool orchestration |
| Debug a subtle issue | opus | Needs deep reasoning about Unity lifecycle, serialization, threading |
| Write shaders | opus | HLSL requires precise understanding of GPU pipelines |
| Challenge a plan before execution | opus | Needs deep Unity knowledge to find subtle risks |
| Review code | sonnet | Structured checklist, pattern matching, faster turnaround |
| Write unit tests | sonnet | Test patterns are well-defined, speed matters for iteration |
| Run a build | sonnet | Mostly configuration and tool invocation |
| Migrate deprecated APIs | sonnet | Mapping old API to new API is well-documented |
| Security audit | sonnet | Pattern matching for known vulnerability classes |
| Git LFS and .meta hygiene | sonnet | Structured git operations, tool invocation |
| Quick lint pass | haiku | Fast pattern matching against known rules, no deep reasoning needed |
| Find files and map dependencies | haiku | Simple lookups and grep, speed matters more than depth |
| Format or rename files | haiku | Simple mechanical task |

---

## Tips for Effective Agent Prompts

1. **Be specific about the scope.** "Add a health system to the player" is better than "improve the player."

2. **Name the Unity subsystems involved.** "Use the Input System and Cinemachine" helps the agent load the right skills.

3. **Reference existing code.** "Follow the pattern in EnemyController.cs" gives the agent a concrete example.

4. **State constraints up front.** "Must hold 60fps on min-spec (GTX 1060, 1080p)" prevents wasted work.

5. **For prototypes, describe the feel.** "Tight, responsive controls like Celeste" conveys more than a feature list.

6. **Let the agent ask questions.** If you give a vague prompt, a good agent will ask for clarification rather than guess.
