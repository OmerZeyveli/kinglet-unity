---
name: unity-scene
description: "Use when the user wants a scene built or reorganized — GameObjects, hierarchy, lighting, cameras, physics layers — entirely through the editor, not by hand-writing scene files. Prefer `/unity-prototype` when the request is a mechanic to try out in a new, disposable scene rather than work on the existing project."
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

If the scene is a throwaway built to try a mechanic rather than an addition the project will keep,
it is not this command at all — `/unity-prototype` runs its own round instead. That choice is made
before the work starts and cannot be taken from part-way in.

**Why here and not in the agent.** `unity-scene-builder`'s tools are `Skill, Read, Glob, Grep,
mcp__UnityMCP__*` — no `Bash`, so it cannot run that check. This command body is executed by the
session that dispatches it, which is where the check can actually run.

**What the check cannot tell you.** A file on disk records a design; it does not record an approval,
and it does not know which scene you were asked for. Both halves are yours to establish before
dispatching — the listing is a necessary condition, never a sufficient one.

## Workflow

Use the `unity-scene-builder` agent to:

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

Both of the surfaces this section used to offer belong before the dispatch, not after it, and they
are stated above as preconditions: `.claude/skills/unity-brainstorming/SKILL.md` is where a scene
gets designed, and `/unity-prototype` is where a throwaway one goes instead. Offering either here
would be offering the gate to a session that has already driven through it.
