---
name: systematic-debugging
description: "Use when something in Unity is broken and the cause is not yet known — before proposing a fix. Establishes the order: read the real console, reproduce, inspect the live API, then change one thing."
---

# Systematic Debugging — Unity

A fix proposed from memory is a guess. Unity's failures are disproportionately lifecycle and
identity problems that reading the code does not reveal.

## Order

1. **Read the real console.** The unity-mcp `read_console` tool. Not the code, not your recollection
   of what the code does — the actual error, with its stack. If the bridge is not running, say so and
   stop rather than substituting a guess.
2. **Reproduce, and say how.** A bug you cannot trigger is a bug you cannot confirm you fixed.
3. **Inspect the live API before assuming it.** The unity-mcp `unity_reflect` tool reports what the
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

## The thought that means you are about to skip a step

| Thought | Reality | Source |
|---|---|---|
| "The bridge reports connected, so I can call its tools" | `claude mcp add` reporting `✔ Connected` means the server is reachable over HTTP — not that a tool for it exists in this session's tool list. A freshly spawned subagent inherits the freeze and gets the same empty result. | The MCP tool table is frozen at session start; if `read_console` is not in your tool list, retrying will not make it appear in this session |
| "I should restart the session to get the bridge back" | The server's health is checkable over HTTP independently of whether this session can call it — "is the bridge up" and "can I reach it" have different remedies, and only one of them needs a restart. | — |
| "Zero references in the project — I grepped and found none" | In Unity, source is not the project. Scenes, prefabs, and ScriptableObjects hold state no `grep` over `.cs` will find. | "zero `Light2D` references" asserted from a `.cs` grep; the type was authored in 52 scenes and 26 prefabs, invalidating the conclusion built on it |

## When it is fixed

Hand off to `verification-before-completion`. A fix you have not re-run is a hypothesis.
