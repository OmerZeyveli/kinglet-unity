---
name: systematic-debugging
description: "Use when something in Unity is broken and the cause is not yet known — before proposing a fix. Establishes the order: read the real console, reproduce, inspect the live API, then change one thing."
---

# Systematic Debugging — Unity

A fix proposed from memory is a guess. Unity's failures are disproportionately lifecycle and
identity problems that reading the code does not reveal.

## Order

1. **Read the real console.** `mcp__UnityMCP__read_console`. Not the code, not your recollection of
   what the code does — the actual error, with its stack. If the bridge is not running, say so and
   stop rather than substituting a guess.
2. **Reproduce, and say how.** A bug you cannot trigger is a bug you cannot confirm you fixed.
3. **Inspect the live API before assuming it.** `mcp__UnityMCP__unity_reflect` reports what the
   installed Unity and packages actually expose. Recalled API surface goes stale between versions.
4. **Change one thing.** Then re-read the console. Two changes at once means you learn nothing from
   the result.

## The Unity-specific causes to rule out early

- **`?.` and `is null` on a UnityEngine.Object.** Unity overrides `==` to report destroyed objects
  as null; `?.` and `is null` use C# reference equality and do not. Calls land on destroyed objects.
- **Lifecycle order.** `Awake` order across objects is not defined. `Start` never runs on an object
  that is never enabled. `OnDisable` runs before `OnDestroy`.
- **A renamed serialized field with no `[FormerlySerializedAs]`.** Values silently reset to default
  across every scene, prefab and ScriptableObject. Nothing warns.
- **An editor-only API used in runtime code without `#if UNITY_EDITOR`.** Compiles in the Editor,
  fails at build.
- **Input that never arrives** because an action map was never `Enable()`d in `OnEnable`.

## When it is fixed

Hand off to `verification-before-completion`. A fix you have not re-run is a hypothesis.
