---
name: unity-brainstorming
description: "You MUST use this before building anything in this Unity project — a new mechanic, system, component, scene, or UI screen — and before writing a plan, touching C#, or mutating the scene. Explores intent, constraints and approaches, then writes the design decision to a file. Not for a tweak to something that already works."
---

# Brainstorming a Unity Feature Into a Design

Turn a request into a **design decision**: what is being built, which approaches were weighed, which
one was chosen and why. This is the chain's entry point — `unity-planning` and everything past it
read what this step writes down, so a decision that stays in the conversation reaches nobody.

<HARD-GATE>
Until a design has been presented and approved: no implementer agent is dispatched, no `.cs` is
written, and **no MCP write call is made** — scene, prefab and ScriptableObject included. A single
MCP call mutates state that no test can restore. This applies to every request regardless of
perceived simplicity.
</HARD-GATE>

## The category, and its boundary

**Building something new in this Unity project** is the category. There is no exemption list: a list
of exemptions is a list of ways to talk yourself out of the round, and the judgment "this one is
clear enough" is made by a model that has just read six rule files and a generated block.

The boundary between build and tweak is a pair, not a paragraph:

| Build — this runs | Tweak — it does not |
|---|---|
| "Add a double jump" | "Jump feels floaty — raise `_gravityMultiplier` to 3" |
| "Give enemies a patrol state" | "Patrol radius should be 8, not 5" |
| "Add a pause menu" | "Move the pause button left of settings" |

A tweak names the thing that already works and the value to change. A build does not — however short
the sentence. If you cannot name the existing script, field or object being adjusted, it is a build.

Two situations look like exemptions and are not. Something **broken** goes to
`.claude/skills/systematic-debugging/SKILL.md` — a different job, not a shortcut past this one. A
**resumed run** already carries its decisions in its ledger, so there is nothing there to re-decide;
for a task the ledger does not cover, there is.

**One real exemption, and it is a decision rather than an oversight.** A **throwaway scene built to
try an idea** — disposable, not an addition the project comes to depend on — goes to
`/unity-prototype`, which runs its own open-ended Clarify instead of this round. That is the
build/tweak question one level up: nothing downstream inherits an undesigned decision, because
nothing downstream keeps the scene. The moment its result is wanted in the real project, it is a
build and it comes back here first.

## Checklist

You MUST create a task for each of these items and complete them in order:

1. **Explore project context** — the scripts, scenes and assets this touches, recent commits, and
   `CLAUDE.md`'s generated block for what this project actually uses
2. **Score the request** — the Ambiguity Score below sets how deep the round goes
3. **Ask clarifying questions** — one per message, on purpose, constraints, and what done looks like
4. **Propose 2–3 approaches** — with trade-offs, led by your recommendation and why
5. **Present the design in sections** — scaled to their complexity, asking after each whether it is
   right so far
6. **Write `docs/features/<slug>/design.md`** — content spec below — and commit it
7. **Self-review the written file** — placeholders, contradictions, ambiguity, scope
8. **Ask the user to review the file** — the file, not the conversation
9. **Hand off to `unity-planning`** — see Handoff

**At depth 1, items 5 and 8 are one approval, not two.** The design is three sentences, item 5's own
scaling collapses it to a single section, and asking again for a review of the written file makes a
human approve the same three sentences twice. That is the cost that makes people stop running the
round at all. Present it, write it, ask once. Nothing above is waived by this: `design.md` is still
written, still presented, and still approved.

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

### Threshold

**Threshold: total score >= 6 out of 10 to proceed.**

That line is ECU's, kept, and "proceed" is now defined: it means **proceed to presenting the
design**, never proceed past it. The threshold divides the same two states it always divided; what
changed is what lies on the far side. Below 6 nothing routes around the round, and at or above 6
nothing skips the artifact.

### What the score decides

The score sets the depth of the round, not whether the round happens. Below 6, ask up to three
questions and re-score. At or above 6, one confirming round is enough.

**Depth scales the round, never the artifact.** At depth 1 the design may be three sentences, but
`design.md` is still written, still presented, and still approved. "Short design" and "no design"
are different outcomes and only one of them is allowed.

## Interview Protocol

When the score is below threshold:

1. **Present the current scores** — show the user which dimensions are weak
2. **Ask targeted questions** — max 3 questions per round, focused on the lowest-scoring dimensions
3. **Re-score after each round** — update scores based on answers
4. **Proceed when threshold is met** — to presenting the design. There is no opt-out. "Just do it"
   is answered by the depth-1 round: three sentences, one approval, and the file still written.

**One question per message.** Three per round is the budget, not the message size: a message
carrying three questions gets one answer, usually to the last of them. Prefer multiple choice where
the options are genuinely enumerable, open-ended where they are not.

Question style: be direct and specific, not generic. Instead of "What platform?", ask "Is this keyboard+mouse first or gamepad first — and does it have to hold 60fps on min-spec, or is the target high-end PC only?"

## Exploring approaches

Propose 2–3 approaches with their trade-offs, lead with the one you recommend, and say why it wins
over the others rather than only why it is good. Two approaches with a real trade-off between them
beat three where one is padding. YAGNI ruthlessly — cut from every approach the parts the request
did not ask for.

An approach nobody wrote down was not considered; it was skipped. The written comparison is what
makes a later session able to reopen the decision instead of re-discovering it.

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

Both of these are builds. The second scores 7 and still gets a design — one round, a short file.

## What `design.md` carries

Write it to `docs/features/<slug>/design.md`, the slug being the feature in lowercase hyphenated
form. `unity-planning` writes `plan.md` beside it and the executing branch writes `ledger.md`, so
one directory holds what was decided, what was planned, and where the work stopped.

1. **Scope and non-scope** — what is included, and what is explicitly excluded. The exclusions are
   the half that stops a plan quietly growing a second feature.
2. **Approaches considered** — the 2–3 that were weighed, each with its trade-off, and why this one.
3. **The architecture decision, in Model/View/System terms** — which Models hold state, which
   Systems own and mutate them, which Views observe. Name **which rules bind, by reference to
   `CLAUDE.md`'s generated block** ("Architecture stack — detected, not assumed"): VContainer,
   MessagePipe and UniTask are detected per project rather than assumed, and a design that assumes
   them into a project that does not have them is wrong from its first line.
4. **Acceptance criteria** — what has to be true for this to be done, in terms someone else can
   check. Where the feature has a feel — a jump, a hit reaction, a camera — say what right feels
   like. A plan cannot carry a criterion the design never stated.
5. **Operator steps** — the Unity work an agent cannot do: sprite atlases, texture import settings,
   lightmap bakes, an `AnimatorOverrideController`. `.claude/rules/performance.md` already makes
   these mandatory rather than optional and they have had no home until now. Say which menu, which
   settings, which assets.

Then read it back with fresh eyes: placeholders ("TBD", an unfinished section), sections that
contradict each other, a requirement that could be read two ways, and scope large enough to need
decomposing into more than one design. Fix what you find inline and move on.

Commit the artifact — an uncommitted file is lost at the next checkout, which is the defect this
step repairs. Commit **only the artifact path**. Never `git add -A`: in a Unity project that stages
`.meta` churn, and `.meta` loss is the damage these rules spend the most effort preventing.

Then ask the user to review the written file before anything is planned. Wait for the answer. If
they want changes, make them, re-read, and ask again.

## The thought that means you are about to treat vague as clear

| Thought | Reality | Source |
|---|---|---|
| "They said what they want" | A want is not an acceptance criterion. "Add multiplayer" states a want; it does not say whether success is two players on one screen or matchmaking across regions. | The Ambiguity Score's own Acceptance Criteria dimension, and the scoring examples above |
| "The request has a code block, so it is specific" | A code block establishes syntax, not scope. Specificity is about the *outcome* — what done looks like — not about whether the input contains a snippet. | The Ambiguity Score's five dimensions, none of which is "contains code" |

## Handoff

The terminal state is `.claude/skills/unity-planning/SKILL.md`. Invoke no other skill. Do **not**
invoke `/unity-prototype`, `unity-coder`, or any MCP agent — the HARD-GATE at the top of this file is
still in force here. It lifts on an approved design, not on reaching this section.

`/unity-prototype` is exempt from the round entirely, per the boundary section above — but that
choice is made *before* the round starts and cannot be taken from inside it. Arriving here means the
round happened, so the exemption is spent.

If the round did not reach an approved design — requirements still unclear after asking — ask the
specific questions the score identified and **stop**. Do not proceed on an assumption and do not
answer your own question.
