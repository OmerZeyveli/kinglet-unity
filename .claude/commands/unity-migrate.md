---
name: unity-migrate
description: "Plan and execute Unity version or render pipeline migration — identifies deprecated APIs, package compatibility, and executes migration steps."
user-invocable: true
args: migration_target
---

# /unity-migrate — Migration Assistant

Plan and execute a migration to: **$ARGUMENTS**

## Workflow

Use the `unity-migrator` agent to:

### Step 1: Assess Current State
```
project_info resource → current Unity version, platform, packages
manage_packages action:"list" → all installed packages with versions
```

Scan codebase for:
- Deprecated API usage (Grep for known deprecated methods)
- Platform-specific code that may need updating
- Shader code using old includes

### Step 2: Create Migration Plan

Present a step-by-step plan:
1. **Backup** — create git branch
2. **Package updates** — which packages need version bumps
3. **API changes** — specific code changes needed (old → new)
4. **Shader changes** — if render pipeline migration
5. **Material conversion** — if render pipeline migration
6. **Testing** — what to test after migration

### Step 3: Execute (with user approval)

For each step:
1. Make the change
2. Check console via `read_console`
3. Fix any errors before proceeding
4. Report progress

### Step 4: Verify

- Run all tests via `run_tests` MCP
- Check console for warnings
- Verify build still succeeds

## Common Migrations
- Unity 2021 → 2022 LTS
- Unity 2022 → Unity 6
- Built-in → URP
- Legacy Input → Input System
- Coroutines → UniTask
