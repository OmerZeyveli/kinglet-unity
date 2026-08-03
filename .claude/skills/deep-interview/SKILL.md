---
name: deep-interview
description: "Use before starting any feature work when the request is vague or underspecified — e.g. 'add a jump', 'make an inventory system' — before writing a plan or touching code."
---

# Deep Interview — Ambiguity Gating

Before executing any feature request, evaluate whether the requirements are clear enough to proceed. Vague requests waste agent cycles and produce code that needs reworking.

## When to Activate

A request is **vague** when ALL of these are true:
- No file paths or directory references mentioned
- No function, class, or component names specified
- No code blocks or snippets included
- No numbered steps or explicit instructions
- The request is more than 10 words (short requests like "add a jump" are intentionally open-ended and acceptable)

If **any one** specificity signal is present, skip the interview and proceed normally.

## Exemptions — Skip the Interview

Do NOT activate for:
- **Bug fixes** — request mentions "error", "bug", "crash", "fix", "broken", "NullReference", "exception"
- **Commands with built-in clarification** — `/unity-workflow` has its own Phase 1: Clarify, `/unity-prototype` expects open-ended prompts
- **Explicit opt-out** — user includes `--skip-interview` or says "just do it" / "don't ask"
- **Follow-up requests** — user is continuing a conversation where requirements were already established
- **Simple modifications** — "make it faster", "change the color to red", "increase the speed"

## Ambiguity Score

Rate the request across 5 dimensions. Each scores 0–2:

| Score | Meaning |
|-------|---------|
| 0 | Unspecified — no information provided |
| 1 | Partial — vague or implied |
| 2 | Clear — explicitly stated or obvious from context |

### Dimensions

1. **Scope** — What exactly is being built? What are its boundaries? What is NOT included?
2. **Platform** — Target platform, Unity version, render pipeline, input method?
3. **Performance** — FPS target, memory budget, draw call limits, target device tier?
4. **Integration** — What existing systems does this touch? Dependencies? Data flow?
5. **Acceptance Criteria** — How do we know it's done? What should we test? What does success look like?

**Threshold: total score >= 6 out of 10 to proceed.**

## Interview Protocol

When the score is below threshold:

1. **Present the current scores** — show the user which dimensions are weak
2. **Ask targeted questions** — max 3 questions per round, focused on the lowest-scoring dimensions
3. **Re-score after each round** — update scores based on answers
4. **Proceed when threshold is met** — or when the user explicitly opts out

Question style: be direct and specific, not generic. Instead of "What platform?", ask "Is this keyboard+mouse first or gamepad first — and does it have to hold 60fps on min-spec, or is the target high-end PC only?"

## Output: Requirements Document

When the threshold is met, produce a structured summary:

```
## Requirements Summary

**Feature:** [one-line description]

**Scope:** [what's included and what's explicitly excluded]
**Platform:** [target platform, input method, render pipeline]
**Performance:** [constraints, budgets, target devices]
**Integration:** [systems touched, dependencies, data flow]
**Acceptance Criteria:**
- [criterion 1]
- [criterion 2]
- [criterion 3]
```

Ask the user to confirm the summary before proceeding to implementation.

## Scoring Examples

**Vague (score 3/10):** "Add multiplayer to my game"
- Scope: 1 (multiplayer is broad — co-op? competitive? matchmaking?)
- Platform: 0 (unspecified)
- Performance: 0 (unspecified)
- Integration: 1 (implies networking but no specifics)
- Acceptance: 1 (implied: "it works")

**Clear enough (score 7/10):** "Add 2-player local co-op split-screen for the existing PlayerController using the new Input System"
- Scope: 2 (2-player local co-op split-screen)
- Platform: 1 (implies desktop from split-screen, but not explicit)
- Performance: 1 (split-screen implies rendering budget concern)
- Integration: 2 (PlayerController, Input System explicitly named)
- Acceptance: 1 (implied: both players can play simultaneously)

## The thought that means you are about to treat vague as clear

| Thought | Reality | Source |
|---|---|---|
| "They said what they want" | A want is not an acceptance criterion. "Add multiplayer" states a want; it does not say whether success is two players on one screen or matchmaking across regions. | The Ambiguity Score's own Acceptance Criteria dimension, and the scoring examples above |
| "I can infer which file/system this means" | Inferring is guessing with extra steps. Name the inference out loud and let them correct it — a silent guess that's wrong costs a rework cycle; a stated guess that's wrong costs one sentence. | This wave itself — the operator twice had to say "read what I wrote first" and "we already decided this, go read the plans" after being asked questions whose answers were already written down |
| "Asking is slower than doing" | It is slower than doing it right once, and faster than doing it twice. This project has the second case on record. | Same as above — the re-asked questions cost a correction round each; a brief that was followed exactly still produced findings, and they clustered where the brief had been vague |
| "The request has a code block, so it is specific" | A code block establishes syntax, not scope. Specificity is about the *outcome* — what done looks like — not about whether the input contains a snippet. | The Ambiguity Score's five dimensions, none of which is "contains code" |
| "The brief didn't say, so it must not matter" | A brief that leaves a decision implicit does not remove the decision — it moves it to whoever reads the brief, silently, and they may move it somewhere the author didn't intend. | This wave — every task brief followed exactly still produced findings, clustered where the brief had been vague |

## Handoff

- **Gate passes** (requirements are clear enough): hand off to `/unity-workflow` for anything
  needing a plan, or `/unity-feature` for one scoped addition. Say which and why.
- **Gate fails** (still ambiguous): ask the specific questions the score identified, and **stop**.
  Do not proceed on an assumption and do not answer your own question.
