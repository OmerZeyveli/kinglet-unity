---
name: unity-ralph
description: "Relentless verify-fix loop — refuses to stop until the project is clean. Runs unity-verifier repeatedly with configurable max iterations and stall detection."
user-invocable: true
args: options
---

# /unity-ralph — Persistent Verify-Fix Loop

Run a relentless verification loop that refuses to stop until the project is clean: **$ARGUMENTS**

Named after oh-my-claudecode's persistent execution mode. Where `/unity-workflow` runs the verifier once (up to 3 internal iterations), ralph runs it repeatedly until there are zero remaining issues — or until hitting the safety limit.

## Configuration

Parse `$ARGUMENTS` for options:

| Option | Default | Description |
|--------|---------|-------------|
| `--max-iterations N` | 10 | Maximum outer loop iterations (each runs verifier with up to 3 internal passes) |
| `--focus <path>` | all | Limit verification to a specific directory or file pattern |
| `--no-tests` | false | Skip test execution between iterations |

Everything after the flags is treated as context for the verifier (e.g., "focus on the new combat system").

## Loop Protocol

### Initialization

1. Record the starting state: `git diff --stat` to capture baseline
2. Set `iteration = 0`, `previous_issues = ""`
3. If `--focus` was provided, note the scope restriction

### Each Iteration

```
iteration += 1
echo "Ralph iteration {iteration}/{max}: Starting verification pass..."
```

1. **Invoke `unity-verifier` agent** via the Agent tool with:
   - The focus scope (if provided)
   - Context from the previous iteration's remaining issues
   - Instruction to report a structured summary at the end

2. **Collect the verifier's final report** — look for:
   - "No auto-fixable issues found" or equivalent → **SUCCESS, exit loop**
   - List of auto-fixed issues → note them
   - List of remaining issues → capture for next iteration

3. **Check console** via MCP `read_console` (if available) for compilation errors

4. **Run tests** via MCP `run_tests` (if available and `--no-tests` not set)

5. **Progress report:**
   ```
   Ralph iteration {iteration}/{max}: {fixed_count} issues fixed, {remaining_count} remaining
   ```

### Stall Detection

After each iteration, compare current remaining issues with `previous_issues`:

- If the **same issues persist for 2 consecutive iterations** with zero fixes applied → **stall detected**
- On stall: stop the loop and report:
  ```
  Ralph stalled after {iteration} iterations. The following issues could not be auto-fixed
  and require human intervention:
  [list of persistent issues]
  ```

Update `previous_issues` with current remaining issues.

### Exit Conditions

Stop the loop when ANY of these are true:

1. **Clean** — no auto-fixable issues remain and compilation succeeds
2. **Max iterations reached** — report remaining issues
3. **Stall detected** — same issues for 2 consecutive iterations
4. **Compilation broken** — a fix introduced new compile errors that the verifier couldn't resolve in its internal 3-pass loop

### Effective Depth

Each outer iteration invokes the verifier which runs up to 3 internal passes. With the default max of 10 outer iterations, ralph can perform up to **30 verification-fix passes** total. This is sufficient for cascading issues where fixing one problem reveals the next.

## Final Report

```markdown
## Ralph Results

**Status:** Clean | Stalled | Max iterations reached | Compilation broken
**Outer iterations:** {count} of {max}
**Total fixes applied:** {total_fix_count}

### Fixes Applied (by iteration)
#### Iteration 1
- `PlayerController.cs:45` — replaced `?.` with `== null` check
- `EnemySpawner.cs:12` — added `[FormerlySerializedAs("_spawnRate")]`

#### Iteration 2
- `PlayerController.cs:67` — cached GetComponent<Rigidbody>() in Awake

### Remaining Issues (requires human review)
- `GameManager.cs` — class handles 6+ responsibilities, consider splitting
- `UIManager.cs:89` — missing tests for score display logic

### Compilation Status
[PASS / FAIL with error details]

### Test Results
[pass/fail counts or "skipped"]
```

## Rules

- **Never modify architecture** — ralph fixes safe, mechanical issues only (the verifier's auto-fix list)
- **Respect the verifier's judgment** — if the verifier marks something as "requires human review", ralph does not attempt to fix it
- **Log everything** — every fix must be traceable to an iteration and a specific issue
- **Fail safe** — if anything unexpected happens (MCP unavailable, git state corrupted), stop immediately and report
- **No infinite loops** — the max iteration cap and stall detection are non-negotiable safety rails
