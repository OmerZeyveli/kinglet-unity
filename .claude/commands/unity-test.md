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

> **If the agent cannot be dispatched, do the work inline and say so.** A user or project setting
> that forbids unrequested `Agent` calls outranks this command body, and that precedence is correct.
> Run these steps yourself, load the skills `unity-test-runner` lists under **Skills to load**, and
> report that the work ran inline rather than in the agent.

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

`run_tests` is **asynchronous** — it starts a job and returns a `job_id`, not results — and it takes
no `action` parameter. `read_console` does **not** carry test results; it carries compile errors,
which is what to check it for.

```
run_tests mode:"EditMode"                                       → {"job_id":"…","status":"running"}
get_test_job job_id:"…" wait_timeout:120 include_details:true   → summary + per-test results
```

### Step 4: Report

Present results, taking the counts from `data.result.summary` on the `get_test_job` reply. If the
job never finished, say so and report `data.progress.stuck_suspected` and
`data.progress.blocked_reason` rather than reporting nothing — and if the run was PlayMode, take the
editor back out with `manage_editor action:"stop"`.

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
