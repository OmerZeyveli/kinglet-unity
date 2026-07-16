---
name: unity-scene
description: "Build or modify a Unity scene entirely via MCP — GameObjects, hierarchy, lighting, cameras, physics layers."
user-invocable: true
args: scene_description
---

# /unity-scene — Build a Scene

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
