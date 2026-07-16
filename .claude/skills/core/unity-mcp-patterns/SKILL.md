---
name: unity-mcp-patterns
description: "How to use unity-mcp tools effectively — batch_execute for speed, read_console for verification, resource queries for project state, tool organization patterns."
alwaysApply: true
---

# Unity MCP Patterns

The unity-mcp server gives Claude Code direct control over the Unity Editor. These patterns ensure you use it efficiently and safely.

## Rule 1: batch_execute for Everything

Individual MCP calls have network overhead. `batch_execute` bundles multiple operations into one call — **10-100x faster**.

```
// BAD — 5 separate calls, 5 round trips
manage_gameobject → create Player
manage_components → add Rigidbody2D to Player
manage_components → add BoxCollider2D to Player
manage_components → add SpriteRenderer to Player
manage_components → configure Rigidbody2D

// GOOD — 1 batch call
batch_execute → [
  create Player,
  add Rigidbody2D,
  add BoxCollider2D,
  add SpriteRenderer,
  configure Rigidbody2D
]
```

Always batch when doing 2+ operations.

## Rule 2: read_console After Every Change

After writing scripts, creating objects, or modifying components, always check the console:

```
1. Write/Edit C# file
2. read_console → check for compilation errors
3. If errors: fix and repeat
4. Continue with MCP operations
5. read_console → check for runtime warnings
```

The console is your feedback loop. Don't assume operations succeeded.

## Rule 3: project_info Before Assumptions

Before making decisions about the project, read its state:

```
project_info resource → Unity version, platform, render pipeline
```

Don't assume:
- The project uses URP (might be Built-in or HDRP)
- The project targets PC (might be mobile)
- Certain packages are installed

## Rule 4: Tool Selection Guide

| Task | Tool | Key Actions |
|------|------|-------------|
| Create/load/save scene | `manage_scene` | create, load, save, validate |
| Create/modify GameObjects | `manage_gameobject` | create, modify, delete, find |
| Add/configure components | `manage_components` | add, remove, configure, get |
| Physics setup | `manage_physics` | settings, layers, materials, joints |
| Camera/Cinemachine | `manage_camera` | create, configure presets, extensions |
| Materials/Shaders | `manage_material` / `manage_shader` | create, assign, configure |
| Animation | `manage_animation` | clips, controllers, states |
| UI elements | `manage_ui` | create, layout, style |
| VFX | `manage_vfx` | particles, effects |
| Prefabs | `manage_prefabs` | create, instantiate, modify |
| ScriptableObjects | `manage_scriptable_object` | create, edit |
| Packages | `manage_packages` | install, remove, search |
| Builds | `manage_build` | configure, build, switch platform |
| Tests | `run_tests` | execute, get results |
| Profiling | `manage_profiler` | sessions, timing, memory |
| Graphics stats | `manage_graphics` | rendering stats, pipeline |
| Console output | `read_console` | errors, warnings, logs |
| API inspection | `unity_reflect` | live C# reflection |
| Documentation | `unity_docs` | official Unity docs |
| C# scripts | `create_script` / `validate_script` | create, validate |

## Rule 5: Scene Templates

When creating new scenes, use templates for quick setup:

```
manage_scene action:"create" template:"3d_basic"
// Creates scene with: Main Camera, Directional Light

manage_scene action:"create" template:"2d_basic"
// Creates scene with: Main Camera (orthographic)
```

## Rule 6: Error Recovery

If an MCP operation fails:
1. `read_console` — get the error message
2. Fix the underlying issue (missing reference, wrong type, etc.)
3. Retry the operation
4. If the error persists, fall back to writing an Editor script

## Rule 7: MCP vs File Editing

| Operation | Use MCP | Use File Edit |
|-----------|---------|---------------|
| Create GameObjects | Yes | Never |
| Edit scenes | Yes | Never |
| Edit prefabs | Yes | Never |
| Write C# scripts | Either | Preferred for complex scripts |
| Configure components | Yes | Never |
| Modify ProjectSettings | Yes | Never |
| Edit .shader/.hlsl files | No (Write tool) | Yes |
| Edit .uxml/.uss files | No (Write tool) | Yes |
| Edit .asmdef files | No (Write tool) | Yes |

## Rule 8: Multi-Instance

If the user has multiple Unity Editor instances:
```
unity_instances resource → list all running editors
set_active_instance → route commands to specific editor
```

Always check which instance is active before sending commands.
