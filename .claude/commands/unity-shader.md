---
name: unity-shader
description: "Create or debug shaders — writes HLSL/ShaderLab, creates materials via MCP, applies to test objects, checks rendering stats."
user-invocable: true
args: shader_description
---

# /unity-shader — Create a Shader

Create a shader based on: **$ARGUMENTS**

## Workflow

Use the `unity-shader-dev` agent to:

1. **Determine shader type** — URP Lit, Unlit, custom effect (mobile-optimized, no compute shaders)
2. **Write the shader** file (`.shader` or `.hlsl`):
   - URP includes and HLSL structure
   - SRP Batcher compatible (CBUFFER_START)
   - Proper tags and render queue
3. **Create material** via `manage_material` MCP — assign the shader
4. **Apply to test object** via `manage_components` MCP:
   - Create or find a test mesh
   - Assign the material
5. **Check rendering stats** via `manage_graphics` MCP:
   - Verify SRP Batcher compatibility
   - Check draw call impact
6. **Check console** via `read_console` for shader compilation errors

Report the shader file, material, and any performance notes.
