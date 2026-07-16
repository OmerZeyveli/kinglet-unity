---
name: estimate
description: "Estimates task effort by analyzing complexity, dependencies, and risk factors. Produces a structured estimate with optimistic/expected/pessimistic ranges and a confidence level. Read-only."
user-invocable: true
args: task-description
---
<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT — https://github.com/Donchitos/Claude-Code-Game-Studios -->

# /estimate — Estimate Task Effort

Produce a structured effort estimate with confidence levels. **Read-only** — writes no files.

## Phase 1: Understand the Task

Read the task from `$ARGUMENTS`. If too vague to estimate, ask for clarification first. Read the
project CLAUDE.md for tech stack and conventions, and any related GDD from `docs/design/`.

## Phase 2: Scan Affected Code

Identify files/modules that would change. Assess complexity (size, dependency count, coupling),
integration points, and existing test coverage. Read past sprints in `docs/production/sprints/`
for similar completed tasks and historical velocity.

## Phase 3: Analyze Complexity Factors

- **Code complexity** — size of affected files, coupling, core vs. leaf code, whether existing
  patterns apply or new ones are needed (e.g. a new VContainer scope, a new MessagePipe message).
- **Scope** — systems touched, new code vs. modification, test coverage required, data/config changes.
- **Risk** — unfamiliar tech, ambiguous requirements, dependencies on unfinished work,
  cross-system integration, performance sensitivity.

## Phase 4: Generate the Estimate

```markdown
## Task Estimate: [Task Name]  ·  Generated: [Date]

### Complexity Assessment
| Factor | Assessment | Notes |
| Systems affected / Files modified / New vs modify / Integration points / Test coverage / Patterns available |

### Effort Estimate
| Scenario | Days | Assumption |
| Optimistic | [X] | Everything goes right |
| Expected | [Y] | Normal pace, minor issues, one review round |
| Pessimistic | [Z] | Significant unknowns surface |

**Recommended budget: [Y days]** (the expected estimate, never the optimistic one)

### Confidence: [High / Medium / Low]  — which factors drive it

### Risk Factors / Dependencies / Suggested Breakdown (sub-tasks with per-task estimates)
```

## Phase 5: Next Steps

- Low confidence → recommend a time-boxed spike first (ECU's `/unity-prototype`).
- Task > 10 days → recommend breaking it into smaller tasks.
- To schedule it → `/sprint-plan update`.

**Guidelines:** always give a range, never a single number; recommend the expected (not
optimistic) figure; round to half-day increments; never pad silently — call out risk explicitly.
