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
| "It compiles" | `mcp__unityMCP__read_console` shows no errors after a refresh |
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

## When there is nothing left to verify

Say what was built, what was verified and how, and what still needs a human. Then offer the next
step — do not take it.
