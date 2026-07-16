---
name: unity-audit
description: "Full project health check — meta file integrity, missing references, assembly definition graph, code quality scan, scene hierarchy audit."
user-invocable: true
---

# /unity-audit — Full Project Health Check

Run a comprehensive audit of the Unity project.

## Checks

### 1. Meta File Integrity
Run `./scripts/validate-meta-integrity.sh --all`:
- Every asset has a `.meta` file
- No orphaned `.meta` files
- No duplicate GUIDs

### 2. Missing References
Run `./scripts/detect-missing-refs.sh`:
- Broken script references in scenes/prefabs
- Missing asset GUIDs
- Null serialized references

### 3. Assembly Definition Graph
Run `./scripts/validate-asmdefs.sh`:
- No circular dependencies
- Editor/Runtime properly separated
- All scripts covered by an asmdef

### 4. Code Quality
Run `./scripts/validate-code-quality.sh`:
- GetComponent/Camera.main in Update
- LINQ in gameplay code
- Allocations in hot paths
- CompareTag usage
- Debug.Log in production code

### 5. Console Errors
Via `read_console` MCP:
- Compilation errors
- Runtime warnings
- Deprecation notices

## Output

Present a health report card:
```
Meta Integrity:    PASS / X issues
Missing Refs:      PASS / X broken
Assembly Graph:    PASS / X issues
Code Quality:      PASS / X warnings
Console:           PASS / X errors
```

Then list all issues grouped by severity (critical → warning → info) with file locations and fix suggestions.
