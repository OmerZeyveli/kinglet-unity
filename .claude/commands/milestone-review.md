---
name: milestone-review
description: "Generates a milestone progress review — feature completeness, quality metrics, risk assessment, and a GO / CONDITIONAL GO / NO-GO recommendation. Use at milestone checkpoints. Writes to docs/production/milestones/."
user-invocable: true
args: milestone-name
---
<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT — https://github.com/Donchitos/Claude-Code-Game-Studios -->

# /milestone-review — Review Milestone Readiness

Assess a milestone's progress and produce a go/no-go recommendation.

## Phase 1: Load Milestone Data

Read the milestone definition from `docs/production/milestones/` (if `$ARGUMENTS` is `current`,
use the most recently modified one). Read all sprint reports for sprints in this milestone from
`docs/production/sprints/`.

## Phase 2: Scan Codebase Health

Scan for `TODO`, `FIXME`, `HACK` markers indicating incomplete work. Check any risk notes in
`docs/production/`.

## Phase 3: Generate the Review

```markdown
# Milestone Review: [Name]

## Overview
- Target Date / Current Date / Days Remaining / Sprints Completed (X/Y)

## Feature Completeness
### Fully Complete | Partially Complete (% + remaining + risk) | Not Started (priority + can-cut?)

## Quality Metrics
- Open S1/S2/S3 bugs · Test status (ECU's `/unity-test`) · Performance within budget? (see pc-console.md)

## Code Health
- TODO / FIXME / HACK counts · notable technical debt

## Risk Assessment
| Risk | Status | Impact if Realized | Mitigation Status |

## Velocity Analysis
- Planned vs Completed across sprints · trend · adjusted estimate for remaining work

## Scope Recommendations
### Protect | At Risk | Cut Candidates

## Go/No-Go Assessment
**Recommendation: [GO / CONDITIONAL GO / NO-GO]**
**Conditions** (if conditional): [...]
**Rationale**: [...]

## Action Items
| # | Action | Owner | Deadline |
```

Derive the Go/No-Go from feature completeness, quality, and velocity. For a heavier
production-risk opinion you MAY consult the `technical-director` agent — optional, not a gate.

## Phase 4: Save

Present the review, then ask: "May I write this to
`docs/production/milestones/[milestone-name]-review.md`?" Write only on approval.

## Next Steps

- `/retrospective [milestone-name]` — capture lessons learned.
- `/sprint-plan new` — plan the next sprint from the scope recommendations above.
