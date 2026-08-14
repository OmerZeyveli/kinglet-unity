---
name: unity-mcp-patterns
description: "Use before making several unity-mcp tool calls in a row, or when a tool call fails because its group isn't active — covers activating tool groups (only core is on by default), batch_execute for speed, read_console for verification, resource queries for project state."
---

# Unity MCP Patterns

*Written against Unity 6000.0 and MCP for Unity 10.1.0 (server 3.4.4), current as of 2026-08-04.*

## Boundary with the rules

No rule in `.claude/rules/` covers unity-mcp usage — the rules govern the C# and architecture the
tools produce, not the tool calls themselves. Tool-group activation, batching, and which tool to reach
for are not addressed by any rule. It is yours to judge.

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

### The failure that looks like a success — read the body, not the error flag

**A call naming an action the tool does not have is not reported as an error.** Measured
2026-08-14 against `mcp-for-unity-server 3.4.5` on Unity 6000.0.68f1:

```
manage_profiler action:"start_session"    # NOT A REAL ACTION — demonstration of the failure shape
  → MCP layer:  isError: false          ← the call "succeeded"
  → body:       {"success": false, "message": "Unknown action ..."}
```

So a caller that branches on the tool-call error flag — which is the natural thing to do, and what a
model does by default — sees a clean call, records a profile it never took, and reasons from
nothing. Nothing appears in `read_console` either: the action never ran, so it logged no error.

This is the shape that hid four dead action names inside `unity-optimizer`'s profiling recipe from
the day it was written until the day someone executed them. **After any tool call, read `success` in
the body.** `isError` tells you the transport worked; `success` tells you the operation did. A
misspelled action, a wrong enum value, and a genuinely unsupported operation all arrive this way.

Two corollaries worth stating separately, because they are what makes the shape survive:

- **A wrong action name is indistinguishable from an unactivated tool group by feel, and not by
  message.** An inactive tool fails as *unknown tool* (Rule 4); a bad action succeeds at the MCP
  layer and fails in the body. Different diagnoses, different fixes.
- **Do not invent action names from the tool's name.** `get_rendering_stats` and `memory_snapshot`
  are both plausible and both nonexistent; the real ones are `stats_get` and `memory_take_snapshot`.
  When unsure, ask the live server rather than your memory of it.

## Rule 3: project_info Before Assumptions

Before making decisions about the project, read its state:

```
resources/read mcpforunity://project/info
  → projectRoot, projectName, unityVersion, platform, assetsPath
```

**`project_info` is a resource, not a tool.** `tools/call project_info` answers
`Unknown tool: 'project_info'` — measured 2026-08-14 on server 3.4.5. Resource names and URIs are
not interchangeable, and the server's own instructions warn that guessing a URI by swapping
separators 404s, so read the URI above verbatim rather than deriving one from a name.

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

Verified against MCP for Unity 10.1.0 (server 3.4.5) on 2026-08-14, by executing against a live
bridge: all ten groups below, every `Default` value, every membership, and `default_enabled =
['core']`. One row had drifted since the previous check and is corrected — `asset_gen` ships five
tools, not four.

**The two tool counts are dated, not current.** *29 before activation, 42 after* was measured on
server 3.4.4; the 3.4.5 host exposed **48** tools with every group active. Treat both as a record of
a day rather than as this server's numbers, and re-derive: `mcpforunity://tool-groups` reports the
live mapping, and it is the answer that wins over this table.

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
| `asset_gen` | off | `generate_image`, `generate_model`, `generate_audio`, `import_model`, `import_model_file` |

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

## Rule 7b: A success flag is not a written value — read it back

**A unity-mcp call reporting success tells you the call was accepted. It does not tell you the
value landed.** The two come apart, and when they do nothing is logged and `read_console` is clean.

Measured on a real project, 2026-08-04, authoring a ScriptableObject array through
`manage_scriptable_object`:

- the resize patch on `_skins.Array.size` was **rejected** — `Unsupported SerializedPropertyType:
  ArraySize`;
- the twelve `_skins.Array.data[i]` element writes that followed each reported **success**.

Twelve successes into an array whose size the same batch had just failed to set. The implementer
did not trust the flags, read the `.asset` back from disk, and only then knew the real state.

**So:** after any MCP write to an asset, prefab or scene, verify by reading the result — the file
from disk, a `git diff`, or a separate query for the value you just set. Component counts and
reference counts before and after are a cheap version of this for prefab edits. Reserve the trust
you would otherwise put in the flag for the read-back.

This is the same failure shape as writing a `.cs` file that does not compile: the write succeeds,
the outcome does not, and only a second look distinguishes them.

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
