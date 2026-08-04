---
name: verification-before-completion
description: "Use before reporting any code change as done — establishes what counts as evidence that it works, and that a claim without evidence is not a completion."
---

# Verification Before Completion

**A documentation layer is worth what its verification is worth. If only one of the two ships, ship
the test.** That is a measured conclusion, not a preference: on the only real project this toolkit
has met, 17,316 lines of documentation were produced and three of its directories were read zero
times, while the tests were read every time.

## What counts as evidence

| Claim | Evidence |
|---|---|
| "It compiles" | the unity-mcp `read_console` tool shows no errors after a refresh |
| "It works" | A test that fails without the change and passes with it, run via `/unity-test` |
| "The bug is fixed" | The reproduction from `systematic-debugging` no longer reproduces |
| "It is faster" | Profiler frames before and after, via `/unity-optimize` |
| "It follows the rules" | `/unity-review` ran and reported clean |

## Rules

- **Report what actually happened.** If tests fail, say so and show the output. If a step was
  skipped, say which. A green claim over a red run is the most expensive thing you can write.
- **A test that asserts nothing passes.** Watch a new test fail before trusting it.
- **Manual Editor steps are not done because you described them.** If the change needs a sprite
  atlas, a lightmap bake, or an import setting the agent cannot create, stop and say so explicitly
  rather than writing code that assumes it exists.

## The thought that means you are about to skip this

| Thought | Reality | Source |
|---|---|---|
| "The suite passed before I made this change" | A green run only proves the tree it ran on, not the one you are about to ship. | The merged-result rule, and `2b543f2` — a commit recorded as passing that did not pass its own suite |
| "It compiles, so it works" | Compilation is not behaviour, and in Unity it is not even proof of a valid file — the editor can write files that fail to compile without the write itself failing. | `unity-coder.md`'s Finishing section: "A file that fails to compile is still written successfully — the write itself does not fail" |
| "The test is green, so the test is real" | A test that asserts nothing passes every time. Watch it fail first, or you are trusting a test you have never seen fail. | `tests/test-surface-references.sh`, seen to fail before being trusted; and the runner-provided test file that "exits 0 having asserted nothing" |
| "The check reported no problems" | Ask what set the check ran over before trusting silence. A check scoped to one directory of a class reads as though it covers the whole class. | `tests/test-bash32-compat.sh` excluded `install.sh`, which then shipped the SIGPIPE bug the test exists to catch (2026-08-03, `git log 0f772a4..HEAD`) |
| "The reviewer confirmed it" | Confirm what it verified *against*. A review that checks a string for internal consistency with the repo's own convention can bless a string the live system does not accept. | The unity-mcp server-name casing (2026-08-03): a whole-branch review declared `mcp__UnityMCP__` wrong, reasoning from `install.sh` and eight existing references, and had it changed to `mcp__unityMCP__`. The live server registers as `UnityMCP`, so the fix moved a working string to a broken one. What mattered was the running system, not this repository's prior habit |
| "I made the change" | The change existing in a working tree and the change existing in the repository are different claims — check `git status`, not your memory of having typed it. | §80 — a guard correctly refused a `git add` of engine-settings YAML; the session committed everything else and marked the finding `applied` anyway, and a prefab shipped pointing at a layer the tracked file never named |
| "I fixed it, the finding is closed" | Closing a finding is not the same as not reintroducing it. Re-check the fix against the finding's own class, not just against the finding's text. | §84 — five specs closed every finding through revise-then-verify; two still failed, on defects the *revision* introduced, in the same class as the finding it had just fixed |
| "Nothing calls it, so it's unused — safe to leave, safe to cut" | An explanation that fits the data is not thereby correct. Ask what else would produce zero calls. | §86 — 39 skills, two multi-hour sessions, 216 tool calls, zero invocations; the actual cause was a discovery bug (nested one level too deep), not disuse, and it survived two sessions because "unused" explained the data perfectly |
| "I grepped and found no references, so there are none in the project" | In Unity, source is not the project. Scenes, prefabs and ScriptableObjects hold state no `grep` over `.cs` will find. | §82 — "zero `Light2D` references" asserted from grepping `.cs`; `Light2D` was authored in 52 scenes and 26 prefabs, one on the player's root GameObject |
| "The installer's checksum says this file is untouched" | A guard exercised once has been exercised once. A checksum taken *after* an upgrade that silently reverted a user's edit will match on the next run, because it is recording the reverted state as ground truth. | 2026-08-03, `git log 0f772a4..HEAD` — a user edit survived one upgrade and was overwritten by the next; the installer re-recorded the file as it then stood, so run three is where it dies, not run two |
| "It only needs to work once, an install is idempotent by nature" | Idempotence is a property you test, not one you assume. | 2026-08-03 — a generated-heading duplication compounded one copy per install, and nothing had asserted that a second install left the document unchanged |

## When there is nothing left to verify

Say what was built, what was verified and how, and what still needs a human. Then offer the next
step — do not take it.
