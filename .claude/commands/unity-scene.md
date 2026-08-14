---
name: unity-scene
description: "Use after a design for the scene is approved — this is the build step for GameObjects, hierarchy, lighting, cameras and physics layers, worked entirely through the editor rather than by hand-writing scene files, and not where a scene gets decided. Prefer `/unity-prototype` when the request is a mechanic to try out in a new, disposable scene rather than work on the existing project."
user-invocable: true
args: scene_description
---

# /unity-scene — Build a Scene

> **Architecture stack — read before you write or refuse.** Which parts of
> `.claude/rules/architecture.md` bind here is stated in `CLAUDE.md`'s generated block, detected
> from this project's own code rather than assumed. A project with no VContainer is **not** a
> project where this surface does not apply — it is a project where you follow the architecture
> the code actually has. Refusing on stack grounds without reading that block is how a measured
> session locked itself out of every MCP-driven agent it had.

Build or modify a scene based on the description: **$ARGUMENTS**

## Precondition: the approved design this command does not create

This command is the build step for a scene a design already specifies. It is not where a scene gets
decided. `unity-scene-builder` holds `mcp__UnityMCP__*`, and
`.claude/skills/unity-brainstorming/SKILL.md` withholds every MCP write call — scene, prefab and
ScriptableObject included — until a design has been presented and approved. A single MCP call
mutates state no test can restore, which is why the gate sits before the dispatch and not after it.

Run this yourself, here, before the agent starts:

```bash
ls -1 docs/features/*/design.md 2>/dev/null || true
```

- **Nothing listed** — this project has no written design at all. Stop. Go to
  `.claude/skills/unity-brainstorming/SKILL.md` and come back with one. Do not dispatch the agent.
- **Something listed** — open the one that covers this scene and build what it specifies. If none of
  them covers it, that is the same stop.
- **Listed, but you cannot point to where the user approved it** — ask, and wait for the answer
  before dispatching. The gate turns on "presented **and** approved", and your own reading of the
  file is not the approval.

If the scene is a throwaway built to try a mechanic rather than an addition the project will keep,
it is not this command at all — `/unity-prototype` runs its own round instead. That choice is made
before the work starts and cannot be taken from part-way in.

**What the listing cannot tell you.** It reports that a design exists. It does not report that this
one covers the scene you were asked for, and it cannot report an approval at all — approval happens
in the conversation, not on disk. The three branches above are how each of those is settled; the
listing is a necessary condition, never a sufficient one.

**Why here and not in the agent.** `unity-scene-builder`'s tools are `Skill, Read, Glob, Grep,
mcp__UnityMCP__*` — no `Bash`, so it cannot run that check. This command body is executed by the
session that dispatches it, which is where the check can actually run. The agent carries the same
precondition in prose, because it can also be dispatched directly and then never sees this file.

## Workflow

Use the `unity-scene-builder` agent to:

> **If the agent cannot be dispatched, do the work inline and say so.** A user or project setting
> that forbids unrequested `Agent` calls outranks this command body, and that precedence is correct.
> Run these steps yourself, load the skills `unity-scene-builder` lists under **Skills to load**, and
> report that the work ran inline rather than in the agent.

1. **Plan the scene** — identify GameObjects, components, hierarchy, lighting, and camera setup
2. **Create or load scene** via `manage_scene` MCP (use templates: `3d_basic` or `2d_basic`)
3. **Build hierarchy** using `batch_execute`:
   - Environment objects (ground, walls, platforms)
   - Character spawn points
   - Camera (Cinemachine virtual camera)
   - Lighting (directional light, point lights)
   - System objects (managers, spawners)
4. **Configure components** via `manage_components`
5. **Set up physics** via `manage_physics` (layers, collision matrix)
6. **Set up camera** via `manage_camera` (follow, confiner, blending)
7. **Verify** via `read_console` — no errors

## Hierarchy Convention
```
@Environment/ — static world geometry
@Characters/  — player, NPCs, enemies
@Cameras/     — main camera, virtual cameras
@Lighting/    — lights, reflection probes
@UI/          — canvases
@Systems/     — managers, spawners
_Dynamic/     — parent for runtime-spawned objects
```

Report the complete scene structure when done.

## Suggest next

When this command finishes, name the next step and offer it. Do not take it.

Offer `.claude/skills/verification-before-completion/SKILL.md` — a built scene is unverified work
until something confirms it loads and plays as the design says.

Do not offer `.claude/skills/unity-brainstorming/SKILL.md` here. It is a precondition of this
command, stated at the top, and offering it now would be offering the gate to a session that has
already driven through it.
