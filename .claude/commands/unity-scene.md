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

Offer `/unity-prototype` or `/unity-feature` depending on whether the scene is throwaway.
