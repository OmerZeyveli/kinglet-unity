---
name: unity-mcp-patterns
description: "How to use unity-mcp tools effectively — activating tool groups (only core is on by default), batch_execute for speed, read_console for verification, resource queries for project state."
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
- The build target matches the ship target (a PC/console project can sit on the wrong platform in Build Settings)
- Certain packages are installed

## Rule 4: Activate the Tool Group Before You Need It

**Only the `core` group is exposed by default.** Everything else is opt-in, and a tool from an
inactive group does not appear in `tools/list` at all — a call to it fails as "unknown tool", not as
"unavailable". If you are about to do shaders, UI, VFX, animation, profiling, tests, or reflection,
activate the group first:

```
manage_tools(action="activate", group="vfx")     # then manage_shader / manage_vfx exist
```

Verified against MCP for Unity 10.1.0 (server 3.4.4): 29 tools before activation, 42 after.
`mcpforunity://tool-groups` reports the live mapping.

| Group | Default | Tools |
|-------|---------|-------|
| `core` | **on** | `batch_execute`, `manage_scene`, `manage_gameobject`, `manage_components`, `manage_physics`, `manage_camera`, `manage_material`, `manage_prefabs`, `manage_packages`, `manage_build`, `manage_graphics`, `manage_asset`, `manage_editor`, `read_console`, `create_script`, `manage_script`, `validate_script`, `delete_script`, `apply_text_edits`, `script_apply_edits`, `find_gameobjects`, `find_in_file`, `execute_menu_item`, `refresh_unity`, `get_sha` |
| `vfx` | off | `manage_shader`, `manage_vfx`, `manage_texture` |
| `ui` | off | `manage_ui` |
| `animation` | off | `manage_animation` |
| `testing` | off | `run_tests`, `get_test_job` |
| `profiling` | off | `manage_profiler` |
| `scripting_ext` | off | `manage_scriptable_object`, `execute_code` |
| `docs` | off | `unity_reflect`, `unity_docs` |
| `probuilder` | off | `manage_probuilder` |
| `asset_gen` | off | `generate_image`, `generate_model`, `generate_audio`, `import_model` |

## Rule 5: Tool Selection Guide

Tools marked **(group)** need `manage_tools(action="activate", group=...)` first — see Rule 4.

| Task | Tool | Key Actions |
|------|------|-------------|
| Create/load/save scene | `manage_scene` | create, load, save, validate |
| Create/modify GameObjects | `manage_gameobject` | create, modify, delete, find |
| Add/configure components | `manage_components` | add, remove, configure, get |
| Physics setup | `manage_physics` | settings, layers, materials, joints |
| Camera/Cinemachine | `manage_camera` | create, configure presets, extensions |
| Materials | `manage_material` | create, assign, configure |
| Shaders | `manage_shader` **(vfx)** | create, configure |
| Animation | `manage_animation` **(animation)** | clips, controllers, states |
| UI elements | `manage_ui` **(ui)** | create, layout, style |
| VFX | `manage_vfx` **(vfx)** | particles, effects |
| Prefabs | `manage_prefabs` | create, instantiate, modify |
| ScriptableObjects | `manage_scriptable_object` **(scripting_ext)** | create, edit |
| Packages | `manage_packages` | install, remove, search |
| Builds | `manage_build` | configure, build, switch platform |
| Tests | `run_tests` **(testing)** | execute, get results |
| Profiling | `manage_profiler` **(profiling)** | sessions, timing, memory |
| Graphics stats | `manage_graphics` | rendering stats, pipeline |
| Console output | `read_console` | errors, warnings, logs |
| API inspection | `unity_reflect` **(docs)** | live C# reflection |
| Documentation | `unity_docs` **(docs)** | official Unity docs |
| C# scripts | `create_script` / `manage_script` / `validate_script` | create, edit, validate |
| Assets | `manage_asset` | import, move, delete (GUID-safe) |

## Rule 6: Scene Templates

When creating new scenes, use templates for quick setup:

```
manage_scene action:"create" template:"3d_basic"
// Creates scene with: Main Camera, Directional Light

manage_scene action:"create" template:"2d_basic"
// Creates scene with: Main Camera (orthographic)
```

## Rule 7: Error Recovery

If an MCP operation fails:
1. `read_console` — get the error message
2. Fix the underlying issue (missing reference, wrong type, etc.)
3. Retry the operation
4. If the error persists, fall back to writing an Editor script

## Rule 8: MCP vs File Editing

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

## Rule 9: Multi-Instance

If the user has multiple Unity Editor instances:
```
unity_instances resource → list all running editors
set_active_instance → route commands to specific editor
```

Always check which instance is active before sending commands.
