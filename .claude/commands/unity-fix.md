---
name: unity-fix
description: "Use when the user reports a bug, error, crash, or something not working in Unity — before proposing a fix from memory. Reads the actual console output and verifies the fix via MCP rather than guessing."
user-invocable: true
args: bug_description
---

# /unity-fix — Diagnose and Fix a Bug

> **Architecture stack — read before you write or refuse.** Which parts of
> `.claude/rules/architecture.md` bind here is stated in `CLAUDE.md`'s generated block, detected
> from this project's own code rather than assumed. A project with no VContainer is **not** a
> project where this surface does not apply — it is a project where you follow the architecture
> the code actually has. Refusing on stack grounds without reading that block is how a measured
> session locked itself out of every MCP-driven agent it had.

Fix the issue described by the user: **$ARGUMENTS**

## Agent Routing

- Use the `unity-fixer` agent (opus — deep investigation).

## Workflow

Use the selected fixer agent to:

1. **Gather evidence:**
   - Read Unity console via `read_console` MCP for errors, warnings, stack traces
   - Search the codebase for the error message or related code
   - If the user pasted an error, parse it for file name, line number, and error type

2. **Diagnose** — check these common Unity causes in order:
   - NullReferenceException → missing reference, destroyed object, execution order
   - Missing Script → file/class name mismatch, asmdef issue
   - Serialization data loss → field renamed without FormerlySerializedAs
   - Coroutine stopped → SetActive(false) or Destroy
   - Physics not working → wrong layers, missing collider/rigidbody
   - Build failure → UnityEditor in runtime, platform defines

3. **Fix** — apply the minimal targeted fix. Don't refactor surrounding code.

4. **Verify:**
   - Check console via `read_console` — error should be gone
   - If it was a serialization issue, warn about data that may need re-configuration
   - If it was a build issue, suggest triggering a build via MCP (`manage_build`) to verify

5. **Explain** what caused the bug and how the fix prevents recurrence.

## Suggest next

When this command finishes, name the next step and offer it. Do not take it.

Offer `/unity-test` to pin the bug so it cannot come back. State the reproduction that no longer reproduces.
