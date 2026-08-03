# Skill Catalog

One-page reference for all skills in everything-claude-unity.

---

## Overview

39 skills, one directory each at `.claude/skills/<name>/SKILL.md`. The model selects one by reading
its `description` and invoking it with the `Skill` tool. That is the whole mechanism — there is no
glob matching, no preloading, and no always-apply.

**Correction (2026-08-03) — the important one.** Every skill in this catalog was unreachable for the
toolkit's entire life. They were filed under `core/`, `gameplay/`, `genre/`, `systems/` and
`third-party/`, inherited from everything-claude-unity, and Claude Code only discovers skills one
level deep. Nothing was registered; the `Skill` tool could not invoke a single entry below. An
eight-hour Endless-Evolution session on 2026-08-02 used zero skills, which read as the model
declining them and was not.

The measurement, in an empty project: `.claude/skills/flatprobe/SKILL.md` is listed in the session's
skill inventory; `.claude/skills/category/nestedprobe/SKILL.md` is not. The layout is now flat and
`tests/test-skill-discovery.sh` keeps it that way.

**Correction (2026-07-30), superseded in part.** A probe found `alwaysApply: true` inert — nothing in
this repository reads it — and concluded the nine skills it marked were "selected by description like
every other skill." The mechanism was right; the conclusion was too generous. They could not be
selected at all. That probe's own evidence says so in hindsight: the model answered the
`commit-trailers` question only after it *searched for and read the file*, which is what you do when
a skill is not invocable. Both `alwaysApply` and `globs` have been stripped from all 39 skills.

---

## Skills That Formerly Carried `alwaysApply: true`

These twelve were marked as if they loaded unconditionally. They never did, and the key is now gone.
They hold knowledge that should rarely be skipped, which makes them the ones most worth naming
explicitly in an agent's **Skills to load** block — see `.claude/agents/unity-coder.md` for the shape.
Where the content genuinely must reach every session, the right home is `.claude/rules/`.

| Skill | Description |
|-------|-------------|
| `serialization-safety` | Unity serialization rules -- FormerlySerializedAs on renames, SerializeField vs public, SerializeReference for polymorphism, Unity null check (`== null` not `?.`). Prevents silent data loss. |
| `unity-mcp-patterns` | How to use unity-mcp tools effectively -- `batch_execute` for speed, `read_console` for verification, resource queries for project state. |
| `model-routing` | Heuristics for choosing the right model tier (haiku/sonnet/opus) when delegating to agents. Loaded by orchestrating commands. |
| `assembly-definitions` | Assembly definition management -- when to create asmdefs, reference rules, Editor/Runtime/Test separation, platform filters, compilation speed optimization. |
| `commit-trailers` | Structured commit trailers -- adds Constraint, Rejected, Scope-risk, and Not-tested metadata to commit messages. |
| `deep-interview` | Ambiguity gating -- detects vague feature requests and forces structured requirements gathering. Prevents wasted cycles on underspecified tasks. |
| `event-systems` | Event system patterns -- C# events, UnityEvent, SO event channels, static EventBus. When to use each, zero-allocation patterns. |
| `object-pooling` | Object pooling patterns -- Unity `ObjectPool<T>`, custom ComponentPool, warm-up strategies, return-to-pool lifecycle. |
| `scriptable-objects` | ScriptableObject architecture patterns -- event channels, variable references, runtime sets, factory pattern, data containers. |

---

## Core Skills

Fundamentals loaded across many contexts.

| Skill | Description | Glob Patterns |
|-------|-------------|---------------|
| `assembly-definitions` | Assembly definition management, reference rules, Editor/Runtime/Test separation | Always loaded |
| `commit-trailers` | Structured commit trailers with architectural decision metadata | Always loaded |
| `deep-interview` | Ambiguity gating and structured requirements gathering | Always loaded |
| `event-systems` | Event system patterns -- C# events, UnityEvent, SO channels | Always loaded |
| `hud-statusline` | Configures Claude Code's statusline to display Unity workflow state | On demand |
| `learner` | Post-debugging knowledge extraction -- captures codebase-specific learnings | On demand |
| `model-routing` | Heuristics for choosing haiku/sonnet/opus model tier | Always loaded |
| `object-pooling` | Object pooling patterns -- Unity ObjectPool<T>, custom pools | Always loaded |
| `scriptable-objects` | ScriptableObject architecture -- event channels, runtime sets, factories | Always loaded |
| `serialization-safety` | FormerlySerializedAs, Unity null checks, SerializeReference | Always loaded |
| `unity-instincts` | How the atomic instinct learning system works -- observations, distillation, confidence scoring, project vs global scope, promotion/evolution | `.claude/hooks/instinct-*.sh`, `.claude/state/instincts/**/*`, `.claude/commands/unity-instincts.md` |
| `unity-mcp-patterns` | batch_execute, read_console, resource query patterns | Always loaded |

---

## Gameplay Skills

Game system implementations loaded by file glob matching.

| Skill | Description | Glob Patterns |
|-------|-------------|---------------|
| `character-controller` | 2D/3D character controllers -- coyote time, input buffering, variable jump, wall slide, dash, slopes | `**/Player*.cs`, `**/Character*.cs`, `**/Movement*.cs`, `**/Controller*.cs` |
| `dialogue-system` | Dialogue tree patterns -- SO graph, node types, typewriter effect, localization-ready | `**/Dialogue*.cs`, `**/Conversation*.cs`, `**/NPC*.cs` |
| `inventory-system` | Inventory, equipment, crafting -- SO item definitions, slot-based inventory, UI binding | `**/Inventory*.cs`, `**/Item*.cs`, `**/Equipment*.cs`, `**/Craft*.cs` |
| `procedural-generation` | Perlin/Simplex noise, BSP dungeons, random walk, loot tables, wave function collapse | `**/Procedural*.cs`, `**/Generate*.cs`, `**/Dungeon*.cs`, `**/Noise*.cs`, `**/Loot*.cs` |
| `save-system` | Save/load patterns -- ISaveable interface, JSON serialization, scene persistence, cloud sync | `**/Save*.cs`, `**/Load*.cs`, `**/Persist*.cs`, `**/Serializ*.cs` |
| `state-machine` | Generic state machine -- IState interface, StateMachine<T>, game states, enemy AI, hierarchical FSM | `**/State*.cs`, `**/FSM*.cs`, `**/*Machine*.cs` |

---

## Genre Skills

Genre-specific architecture and patterns loaded by file glob matching.

| Skill | Description | Glob Patterns |
|-------|-------------|---------------|
| `idle-clicker` | Big number math, offline progress, prestige/rebirth, upgrade trees, automation, currency systems | `**/Idle*.cs`, `**/Clicker*.cs`, `**/Currency*.cs`, `**/Upgrade*.cs`, `**/Prestige*.cs` |
| `match3` | Grid system, tile matching, cascade/gravity, special tiles, combo chains, level objectives | `**/Match*.cs`, `**/Grid*.cs`, `**/Tile*.cs`, `**/Board*.cs`, `**/Puzzle*.cs` |
| `platformer-2d` | Tight controls, level design patterns, collectibles, checkpoints, hazards, boss patterns | `**/Platform*.cs`, `**/Player*.cs`, `**/Level*.cs` |
| `puzzle` | Grid/board logic, undo system, hint system, level packs, star ratings, mouse drag-and-drop | `**/Puzzle*.cs`, `**/Board*.cs`, `**/Grid*.cs`, `**/Hint*.cs`, `**/Undo*.cs` |
| `rpg` | Stat system (base + modifiers), level/XP, skill trees, quest system, turn-based and real-time combat | `**/RPG*.cs`, `**/Stat*.cs`, `**/Quest*.cs`, `**/Skill*.cs`, `**/Level*.cs` |
| `topdown` | Twin-stick / mouse-aim movement, room transitions, fog of war, spawner patterns, wave systems | `**/TopDown*.cs`, `**/Room*.cs`, `**/Wave*.cs`, `**/Spawn*.cs` |

> `endless-runner` and `hyper-casual` were removed — they are mobile genres, and both loaded on
> generic globs (`**/Level*.cs`, `**/GameManager*.cs`, `**/Chunk*.cs`) that any PC game trips.
> See `provenance-skip.tsv`.

---

## Platform Skills

_None._ Kinglet Pioneer targets PC/console only, so there is no platform-switching layer. Platform
guidance lives in `.claude/rules/pc-console.md`, which is always in force.

> Upstream shipped a `mobile` skill here. The note that used to sit in this spot said it "loaded on
> every C# file" via `alwaysApply: true` and `globs: ["**/*.cs"]`; that is not how Claude Code works
> and the skill auto-loaded nothing. It is removed, not disabled, and removal was still right —
> mobile guidance in a PC/console toolkit is wrong whichever way it reaches the model. See
> `provenance-skip.tsv`.

---

## Systems Skills

Unity subsystem knowledge loaded by file glob matching.

| Skill | Description | Glob Patterns |
|-------|-------------|---------------|
| `addressables` | Addressables asset loading -- LoadAssetAsync, handle lifecycle, labels, remote catalogs, memory management | `**/Addressable*.cs`, `**/*Address*` |
| `animation` | Animator controllers, layers, blend trees, state machine behaviors, root motion, animation events, Timeline | `**/*.controller`, `**/*Anim*.cs`, `**/*.anim` |
| `audio` | AudioMixer groups, snapshots, spatial audio, audio source pooling, compression per platform | `**/*.mixer`, `**/*Audio*.cs`, `**/*Sound*.cs`, `**/*Music*.cs` |
| `cinemachine` | Virtual cameras, FreeLook, blending, noise profiles, state-driven cameras, confiner | `**/*Cinemachine*`, `**/*Camera*.cs`, `**/*Cam*.cs` |
| `input-system` | New Input System -- action maps, PlayerInput, generated C# classes, runtime rebinding, multi-device | `**/*.inputactions`, `**/Input*.cs`, `**/PlayerInput*` |
| `navmesh` | NavMeshAgent configuration, NavMeshSurface, off-mesh links, dynamic obstacles, pathfinding | `**/*Nav*.cs`, `**/*Pathfind*.cs`, `**/*Agent*.cs` |
| `physics` | Non-allocating queries, collision layers, FixedUpdate discipline, continuous collision detection, joints | `**/*Physics*.cs`, `**/*Collider*.cs`, `**/*Rigidbody*.cs`, `**/*Trigger*.cs` |
| `shader-graph` | Custom function nodes, sub-graphs, keyword-driven variants, master stack outputs, URP effects | `**/*.shadergraph`, `**/*.shadersubgraph` |
| `ui-toolkit` | UXML document structure, USS styling, UQuery, data binding, ListView virtualization, custom elements | `**/*.uxml`, `**/*.uss`, `**/UIDocument*` |
| `urp-pipeline` | URP asset configuration, renderer features, 2D renderer, lighting, shadows, post-processing, SRP Batcher | `**/URP*.asset`, `**/*Renderer*.asset`, `**/*Volume*.cs` |

---

## Third-Party Skills

Integration patterns for popular Unity packages.

| Skill | Description | Glob Patterns |
|-------|-------------|---------------|
| `dotween` | DOTween animation library -- sequence composition, tween lifecycle, easing, kill strategies. Always kill tweens in OnDestroy. | `**/DOTween*`, `**/*Tween*.cs`, `**/*Animation*.cs` |
| `odin-inspector` | Odin Inspector and Serializer -- SerializedMonoBehaviour, validation attributes, custom drawers, editor windows | `**/Odin*`, `**/Sirenix*`, `**/*Inspector*.cs` |
| `textmeshpro` | TextMeshPro -- font asset creation, material presets, rich text tags, dynamic font fallback, sprite assets | `**/TMP_*.cs`, `**/TextMesh*.cs`, `**/*Text*.cs`, `**/*.asset` |
| `unitask` | UniTask zero-allocation async/await -- cancellation tokens, PlayerLoop integration, async LINQ. Replaces coroutines. | `**/UniTask*`, `**/*Async*.cs`, `**/Cysharp*` |
| `vcontainer` | VContainer DI -- LifetimeScope hierarchy, registration patterns, constructor injection, `[Inject]` for MonoBehaviours | `**/VContainer*`, `**/*LifetimeScope*.cs`, `**/*Installer*.cs`, `**/Container*.cs` |

---

## How Skills Are Loaded

One way, and only one: the model invokes the `Skill` tool with the skill's name.

Two things have to be true for that to happen. The skill must be **discoverable** — flat at
`.claude/skills/<name>/SKILL.md`, or it is not registered and the tool cannot name it. And it must be
**reachable** — the agent needs `Skill` in its `tools:` frontmatter, and something has to prompt it to
load that particular skill. The agents carry a **Skills to load** block naming the two to four they
would otherwise never think of; the `Skill` tool's own listing covers the rest.

Both conditions failed silently until 2026-08-03: no error, no warning, no missing file. That is why
`tests/test-skill-discovery.sh` checks the layout, the `name:`/directory agreement, and that every
skill an agent names actually exists.

Skills are additive — several can be loaded at once, and they do not conflict, each covering a
distinct domain. Loading none is the failure mode that actually occurs.

---

## Creating a New Skill

Create a new directory and `SKILL.md` file:

```
.claude/skills/<skill-name>/SKILL.md
```

One level. A `SKILL.md` nested any deeper is invisible to Claude Code and will never load —
`tests/test-skill-discovery.sh` fails if one appears.

Frontmatter — these two keys and nothing else:

```yaml
---
name: skill-name
description: "When to load this skill -- be specific about the use case"
---
```

`name` must equal the directory name. `description` is the entire selection mechanism: it is what the
model reads when deciding whether this skill is relevant, so write it as *when to reach for this*, not
as a title. Do not add `alwaysApply` or `globs` — they do nothing here, and the test rejects them.

The Markdown body contains the skill's knowledge: patterns, code examples, rules, and anti-patterns. Keep skills focused on one domain. If a skill grows beyond 200 lines, consider splitting it.
