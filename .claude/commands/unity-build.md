---
name: unity-build
description: "Configures and triggers Unity builds via MCP — handles platform settings, scenes, player settings, and monitors build progress."
user-invocable: true
args: platform
---

# /unity-build — Build the Project

Configure and trigger a build for the specified platform.

## Target

If the user specified a platform: build for **$ARGUMENTS**
If no platform: ask the user which platform to build for.

## Workflow

Use the `unity-build-runner` agent to:

### Step 1: Pre-Build Checks

1. **Check console** via `read_console` — abort if compilation errors exist
2. **Check project info** via `project_info` resource — current platform and Unity version
3. **Validate build scenes** — ensure all scenes in build list exist
4. **Run code quality check** — look for `UnityEditor` namespace leaks

### Step 2: Configure Platform

Switch platform if needed via `manage_build`:
- Set player settings (company, product name, version, bundle ID)
- Configure platform-specific settings:
  - **Windows / Standalone**: IL2CPP, x86_64, graphics APIs (DX12/DX11), code stripping
  - **Console (PS5/Xbox)**: platform module present, IL2CPP, title ID from the dev portal
  - **macOS / Linux**: notarization/signing (macOS), Vulkan (Linux)

### Step 3: Build

```
manage_build action:"build" → trigger the build
read_console → monitor progress and catch errors
```

### Step 4: Report

- Build result: SUCCESS or FAILURE
- Build size (if available from log)
- Warnings from build log
- If failed: error details and suggested fixes
- Next steps: where to find the build output

## Common Build Fixes

| Error | Fix |
|-------|-----|
| `UnityEditor` namespace | Add `#if UNITY_EDITOR` guard |
| Missing type/assembly | Check `.asmdef` references |
| Stripping removes code | Add entries to `link.xml` |
| Build too large | Run `/unity-optimize` or `analyze-build-size.sh` |
