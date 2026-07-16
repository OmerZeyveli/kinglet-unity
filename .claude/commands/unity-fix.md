---
name: unity-fix
description: "Diagnoses and fixes a Unity bug — reads console errors, checks common causes, applies targeted fix, verifies via MCP."
user-invocable: true
args: bug_description
---

# /unity-fix — Diagnose and Fix a Bug

Fix the issue described by the user: **$ARGUMENTS**

## Agent Routing

- Default: use `unity-fixer` agent (opus — deep investigation)
- If `$ARGUMENTS` contains `--quick`: use `unity-fixer-lite` agent (sonnet — for obvious fixes)
- Strip the `--quick` flag from arguments before passing to the agent

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
   - If it was a build issue, suggest running `/unity-build` to verify

5. **Explain** what caused the bug and how the fix prevents recurrence.
