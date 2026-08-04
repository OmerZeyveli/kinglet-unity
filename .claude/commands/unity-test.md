---
name: unity-test
description: "Use when the user wants tests written or run — for a specific area if named, otherwise for the most critical untested code paths. Writes EditMode/PlayMode tests and executes them via MCP, reporting real results rather than assuming coverage."
user-invocable: true
args: scope
---

# /unity-test — Write and Run Tests

> **Architecture stack — read before you write or refuse.** Which parts of
> `.claude/rules/architecture.md` bind here is stated in `CLAUDE.md`'s generated block, detected
> from this project's own code rather than assumed. A project with no VContainer is **not** a
> project where this surface does not apply — it is a project where you follow the architecture
> the code actually has. Refusing on stack grounds without reading that block is how a measured
> session locked itself out of every MCP-driven agent it had.

Write tests for the project and execute them via MCP.

## Scope

If the user specified a scope: test **$ARGUMENTS**
If no scope: identify the most critical untested code paths.

## Workflow

Use the `unity-test-runner` agent to:

### Step 1: Assess Test Coverage

1. Find existing test assemblies (`.asmdef` files with test references)
2. If no test assemblies exist, create them:
   - `ProjectName.Tests.Editor` — EditMode tests (fast, no scene)
   - `ProjectName.Tests.Runtime` — PlayMode tests (full lifecycle)
3. Identify scripts with public APIs that lack tests
4. Prioritize: gameplay logic > systems > utilities

### Step 2: Write Tests

For each untested class/method:
- **EditMode test** if it's pure logic (no MonoBehaviour lifecycle needed)
- **PlayMode test** if it involves MonoBehaviour, physics, or scene state
- Naming: `MethodName_Condition_ExpectedResult`
- Arrange-Act-Assert pattern
- Clean up GameObjects in TearDown

### Step 3: Run Tests

```
run_tests → execute all tests (or specific fixture if scoped)
read_console → get test results
```

### Step 4: Report

Present results:
- Total: X passed, Y failed, Z skipped
- For failures: test name, expected vs actual, stack trace, suggested fix
- New tests created: list with file paths
- Coverage gaps: what still needs testing

## Test Priority

1. **Game state logic** — health, damage, scoring, inventory
2. **Input processing** — movement calculation, ability activation
3. **Data systems** — save/load, serialization, configuration
4. **Edge cases** — zero health, empty inventory, null references

## Suggest next

When this command finishes, name the next step and offer it. Do not take it.

If any test fails, report the output and stop — do not offer anything else until it is green.
