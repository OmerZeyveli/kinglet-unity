---
name: unity-interview
description: "Socratic interview flow — explores requirements, identifies edge cases, clarifies scope, and outputs a structured feature brief before any coding begins."
user-invocable: true
args: topic
---

# /unity-interview — Deep Requirements Interview

Conduct a thorough, multi-phase requirements interview for: **$ARGUMENTS**

This command produces a comprehensive feature brief BEFORE any code is written. It is deliberately more thorough than the quick clarify phase in `/unity-workflow` — use this for large or ambiguous features where getting requirements right is critical.

## Phase 1: Scope Exploration

Ask the user to define boundaries:

1. **What does this feature DO?** — core behavior, primary use case
2. **What does this feature NOT do?** — explicit exclusions, out-of-scope items
3. **Who is the user?** — player-facing, designer-facing, developer tool?
4. **What triggers it?** — player input, game event, timer, external signal?
5. **What is the expected output?** — visual change, data mutation, event emission, audio?

Summarize scope before proceeding. Ask user to confirm or adjust.

## Phase 2: Technical Requirements

Gather project context automatically and ask targeted questions:

1. **Read** `CLAUDE.md` for project config (Unity version, render pipeline, target platform, packages)
2. **Read** `Packages/manifest.json` to identify available packages
3. **Scan** existing assembly definitions to understand project structure
4. Ask about:
   - **Performance budget** — target FPS? Memory ceiling? Max draw calls?
   - **Platform constraints** — mobile thermal throttling? WebGL size limits?
   - **Unity subsystems** — physics, UI, animation, audio, networking, addressables?
   - **Data persistence** — does any state need saving? What format?
   - **Multiplayer** — any networked aspects? Authority model?

## Phase 3: Edge Case Identification

For each major component identified in Phase 1-2, systematically explore:

1. **Error states** — what happens when things go wrong? (null references, missing assets, network failure)
2. **Boundary conditions** — minimum/maximum values, empty collections, zero-duration timers
3. **Platform differences** — does this behave differently on iOS vs Android? Editor vs build?
4. **Race conditions** — scene transitions, async operations, destruction timing
5. **Performance under load** — what happens with 100x the expected entities/items/particles?
6. **Undo/reset** — can the player undo this action? What happens on scene reload?

Present the edge cases found and ask: "Are there any I missed? Any you want to explicitly exclude?"

## Phase 4: Integration Mapping

Identify every existing system the feature touches:

1. **List systems** that will be read from, written to, or subscribed to
2. For each system, clarify:
   - **Data flow direction** — does the new feature read, write, or both?
   - **Ownership** — who owns the Model? Which System mutates it?
   - **Message dependencies** — what MessagePipe messages does it publish/subscribe?
3. **Identify new dependencies** — any new packages, services, or assets needed?
4. **Assembly placement** — which assembly definition should new code live in?

Present an integration diagram (text-based) showing data flow between systems.

## Phase 5: Acceptance Criteria

Produce a numbered list of testable acceptance criteria:

```
## Acceptance Criteria

1. [ ] [Specific, testable condition]
2. [ ] [Another condition]
...
```

Rules for acceptance criteria:
- Each criterion must be **independently testable**
- Use concrete values, not vague language ("health decreases by 10" not "health goes down")
- Include at least one **negative test** (what should NOT happen)
- Include at least one **performance criterion** if relevant ("spawning 50 enemies does not drop below 30 FPS")

Ask the user to confirm, add, or remove criteria.

## Output: Structured Feature Brief

After all phases are complete, generate a comprehensive document:

```markdown
## Feature Brief: [Title]

### Scope
- **Does:** [bullet list from Phase 1]
- **Does NOT:** [explicit exclusions]
- **Trigger:** [what initiates the feature]
- **Output:** [what the feature produces]

### Technical Requirements
- **Unity:** [version] | **Pipeline:** [URP/HDRP/Built-in] | **Platform:** [targets]
- **Subsystems:** [physics, UI, animation, etc.]
- **Performance budget:** [FPS, memory, draw calls]
- **Data persistence:** [yes/no, format]

### Edge Cases
| Case | Expected Behavior |
|------|-------------------|
| [edge case] | [what should happen] |

### Integration Points
| System | Direction | Messages |
|--------|-----------|----------|
| [system] | read/write/both | [MessagePipe messages] |

### Assembly Placement
- New scripts go in: `[assembly name]`
- New tests go in: `[test assembly name]`

### Acceptance Criteria
1. [ ] [criterion]
2. [ ] [criterion]
...

### Estimated Complexity
[simple / moderate / complex] — [brief justification]

### Recommended Approach
[1-3 sentences on how to implement, which agents to use]
```

## Rules

- **Never skip a phase** — each phase builds on the previous
- **Ask, don't assume** — if something is unclear, ask rather than guessing
- **Summarize after each phase** — let the user course-correct early
- **Keep code out** — this command produces a brief, not code. Use `/unity-workflow` or `/unity-feature` to implement.
- **Respect the user's time** — if the user gives detailed answers, don't re-ask what's already clear
