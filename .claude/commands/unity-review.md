---
name: unity-review
description: "Full Unity-aware code review — checks serialization safety, performance, architecture, and Unity-specific pitfalls."
user-invocable: true
args: scope
---

# /unity-review — Unity Code Review

Perform a comprehensive code review with Unity-specific checks.

## Agent Routing

- Default: use `unity-reviewer` agent (sonnet — efficient for standard reviews)
- If `$ARGUMENTS` contains `--thorough`: use opus model for deeper architectural analysis
- Strip the `--thorough` flag from arguments before passing to the agent

## Scope

If the user specified a scope: review **$ARGUMENTS**
If no scope: review recently changed files (`git diff` or all `.cs` files in `Assets/Scripts/`).

## Workflow

Use the `unity-reviewer` agent to check:

### 1. Critical Issues (must fix)
- `[SerializeField]` field renamed without `[FormerlySerializedAs]`
- `?.` or `is null` used on Unity objects (must use `== null`)
- `UnityEditor` namespace in runtime code without `#if UNITY_EDITOR`
- MonoBehaviour class name doesn't match file name
- DOTween not killed in `OnDestroy`
- Event subscriptions without matching unsubscribe
- Naked `async void` methods

### 2. Performance Issues (should fix)
- GC allocations in Update/FixedUpdate/LateUpdate
- Uncached `GetComponent`, `Camera.main`, `FindObjectOfType`
- LINQ in gameplay code
- `tag ==` instead of `CompareTag`
- `SendMessage` / `BroadcastMessage`
- Non-cached `WaitForSeconds`
- `Animator.StringToHash` not cached as `static readonly`

### 3. Architecture Suggestions (consider)
- MonoBehaviour inheritance deeper than 2 levels
- God classes doing too many things
- Tight coupling between systems
- Public fields that should be `[SerializeField] private`
- Missing `[RequireComponent]` attributes

### 4. Unity-Specific Warnings
- Coroutine lifecycle issues
- Cross-object execution order dependencies
- Platform defines without fallback
- Time.deltaTime in FixedUpdate

## Output

Present findings grouped by severity with specific file:line references and suggested fixes.
End with a summary: X critical, Y performance, Z suggestions.
