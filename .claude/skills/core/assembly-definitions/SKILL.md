---
name: assembly-definitions
description: "Assembly definition management — when to create asmdefs, reference rules, Editor/Runtime/Test separation, platform filters, compilation speed optimization."
alwaysApply: true
---

# Assembly Definitions

Assembly definitions (`.asmdef`) split your project into separate compilation units. Without them, Unity recompiles ALL scripts on every change. With them, only the changed assembly and its dependents recompile.

## When to Create an Asmdef

- **> 50 scripts in a folder** — the compilation speed benefit becomes noticeable
- **Editor-only code** — MUST be in a separate Editor assembly
- **Test code** — MUST be in separate test assemblies
- **Shared library code** — core utilities used across systems
- **Third-party code** — isolate external packages

## Recommended Structure

```
Assets/
├── Scripts/
│   ├── Core/                          # MyGame.Core.asmdef
│   │   ├── Core.asmdef
│   │   ├── Events/
│   │   ├── Pooling/
│   │   └── Utilities/
│   │
│   ├── Gameplay/                      # MyGame.Gameplay.asmdef
│   │   ├── Gameplay.asmdef
│   │   ├── Player/
│   │   ├── Enemies/
│   │   └── Items/
│   │
│   ├── Systems/                       # MyGame.Systems.asmdef
│   │   ├── Systems.asmdef
│   │   ├── Audio/
│   │   ├── Save/
│   │   └── UI/
│   │
│   └── Editor/                        # MyGame.Editor.asmdef
│       ├── Editor.asmdef
│       └── CustomInspectors/
│
├── Tests/
│   ├── EditMode/                      # MyGame.Tests.Editor.asmdef
│   │   └── Tests.Editor.asmdef
│   └── PlayMode/                      # MyGame.Tests.Runtime.asmdef
│       └── Tests.Runtime.asmdef
```

## Reference Rules (Dependency Direction)

```
Gameplay → Systems → Core
    ↓         ↓        ↓
  (game)   (audio,   (events,
            save,     pooling,
            UI)       utilities)

Editor → [any runtime assembly]
Tests  → [assembly being tested]
```

**Never reverse the arrows.** Core must not reference Gameplay. Systems must not reference Gameplay.

## Asmdef JSON Structure

```json
{
    "name": "MyGame.Gameplay",
    "rootNamespace": "MyGame.Gameplay",
    "references": [
        "MyGame.Core",
        "MyGame.Systems"
    ],
    "includePlatforms": [],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": false,
    "precompiledReferences": [],
    "autoReferenced": true,
    "defineConstraints": [],
    "versionDefines": [],
    "noEngineReferences": false
}
```

## Editor Assembly

```json
{
    "name": "MyGame.Editor",
    "rootNamespace": "MyGame.Editor",
    "references": [
        "MyGame.Core",
        "MyGame.Gameplay"
    ],
    "includePlatforms": ["Editor"],
    "excludePlatforms": [],
    "allowUnsafeCode": false
}
```

**Key:** `"includePlatforms": ["Editor"]` — this assembly is excluded from builds entirely.

## Test Assembly

```json
{
    "name": "MyGame.Tests.Editor",
    "rootNamespace": "MyGame.Tests.Editor",
    "references": [
        "MyGame.Core",
        "MyGame.Gameplay",
        "UnityEngine.TestRunner",
        "UnityEditor.TestRunner"
    ],
    "includePlatforms": ["Editor"],
    "defineConstraints": ["UNITY_INCLUDE_TESTS"],
    "overrideReferences": true,
    "precompiledReferences": ["nunit.framework.dll"]
}
```

## Optional Dependencies

Use `defineConstraints` for optional package dependencies:

```json
{
    "name": "MyGame.DOTweenIntegration",
    "defineConstraints": ["DOTWEEN"],
    "references": ["MyGame.Core"]
}
```

This assembly only compiles if the `DOTWEEN` scripting define is present.

## Common Mistakes

1. **Circular references** — A references B, B references A → compilation error
2. **Editor referencing Runtime incorrectly** — Editor asmdef can reference runtime, but runtime CANNOT reference Editor
3. **Missing reference** — Type in Assembly A uses type from Assembly B, but A doesn't reference B → error
4. **Scripts outside any asmdef** — these go into `Assembly-CSharp.dll` which recompiles on ANY script change
5. **Root namespace mismatch** — `rootNamespace` should match the folder's intended namespace

## Compilation Order

Unity compiles assemblies in dependency order:
1. Assemblies with no dependencies (Core)
2. Assemblies depending only on step 1 (Systems)
3. Assemblies depending on step 1-2 (Gameplay)
4. `Assembly-CSharp` (scripts without asmdef — compiles LAST, slowest)

The fewer scripts in `Assembly-CSharp`, the faster your iteration time.
