---
name: unity-review
description: "Use after C# code changes are written and before they're considered done, when the user asks for a code review or a check before merging/committing. Runs a Unity-aware review — serialization safety, performance, architecture."
user-invocable: true
args: scope
---

# /unity-review — Unity Code Review

> **Architecture stack — read before you write or refuse.** Which parts of
> `.claude/rules/architecture.md` bind here is stated in `CLAUDE.md`'s generated block, detected
> from this project's own code rather than assumed. A project with no VContainer is **not** a
> project where this surface does not apply — it is a project where you follow the architecture
> the code actually has. Refusing on stack grounds without reading that block is how a measured
> session locked itself out of every MCP-driven agent it had.

Perform a comprehensive code review with Unity-specific checks.

## Agent Routing

- Default: use `unity-reviewer` agent (sonnet — efficient for standard reviews)
- If `$ARGUMENTS` contains `--thorough`: use opus model for deeper architectural analysis
- Strip the `--thorough` flag from arguments before passing to the agent

## Scope

If the user specified a scope: review **$ARGUMENTS**
If no scope: review recently changed files (`git diff` or all `.cs` files in `Assets/Scripts/`).

## Before dispatching: the rename check the agent cannot run

Run this yourself, here, before the agent starts:

```bash
bash .claude/scripts/validate-serialization.sh          # whole Assets/ tree
bash .claude/scripts/validate-serialization.sh --staged # only what is staged for commit
```

**Why here and not in the agent.** `unity-reviewer` is read-only — `Skill, Read, Glob, Grep`, no
`Bash` — and that is the shape it is meant to have. This command runs where a script can be
executed, so the script runs at this level and its findings go into the review as evidence.

**Why a script and not a read.** A rename is a difference between two versions of a file. The script
diffs each file's `[SerializeField]` and public field names against `git show HEAD:<file>` and
reports every name that disappeared without a matching `[FormerlySerializedAs("oldName")]`. Reading
the file as it stands now cannot see a name that is no longer in it — the old name exists only in
history — so critical issue 1 below is otherwise reviewed against whatever the diff happens to show.

Use `--staged` when the review is scoped to a commit about to be made; otherwise let it scan
`Assets/`. Two things to know before reading its result:

- **It always exits 0.** Read the output, not the status: `Found N serialization warning(s)` is the
  finding, `All serialized field renames have proper FormerlySerializedAs attributes` is the clean
  result.
- **It needs git and a Unity project root.** Outside a git repository it prints
  `Not a git repository. Cannot compare against history.` and exits 1. Report that as a check that
  did not run — not as a clean result, and not as a review finding.

Every warning it prints belongs in the review under critical issue 1, naming the field and file it
named. It supplements the agent's read rather than replacing it: it sees only what git can show it,
so a field renamed several commits ago, or one in an untracked file, is invisible to it and still
yours to catch.

## Workflow

Use the `unity-reviewer` agent to check:

> **If the agent cannot be dispatched, do the work inline and say so.** A user or project setting
> that forbids unrequested `Agent` calls outranks this command body, and that precedence is correct.
> Run these steps yourself, load the skills `unity-reviewer` lists under **Skills to load**, and
> report that the work ran inline rather than in the agent.

### 1. Critical Issues (must fix)
- `[SerializeField]` field renamed without `[FormerlySerializedAs]` (the script above is the
  history-aware half of this check; the agent still reads the code)
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

Present findings grouped by severity, each anchored to the file plus the symbol, method or exact text
to search for — a line number alongside that anchor is welcome, never instead of it — with suggested
fixes.
End with a summary: X critical, Y performance, Z suggestions.

## Suggest next

When this command finishes, name the next step and offer it. Do not take it.

If findings were reported, offer to fix them. Do not fix them unasked.
