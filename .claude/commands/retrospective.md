---
name: retrospective
description: "Generates a sprint or milestone retrospective by analyzing completed work, velocity, blockers, and patterns. Produces actionable insights for the next iteration. Writes to docs/production/retrospectives/."
user-invocable: true
args: sprint-or-milestone
---
<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT — https://github.com/Donchitos/Claude-Code-Game-Studios -->

# /retrospective — Sprint or Milestone Retrospective

Analyze what actually happened and produce 3–5 concrete action items for the next iteration.

## Phase 1: Parse & Check for Existing

Determine sprint (`sprint-N`) vs. milestone (`milestone-name`) from `$ARGUMENTS`. Glob
`docs/production/retrospectives/` for an existing retrospective; if found, ask (via
`AskUserQuestion`) whether to update it or start fresh (archive the old one with a
`-archived-[date]` suffix).

## Phase 2: Load Data

Read the sprint/milestone plan from `docs/production/sprints/` or `docs/production/milestones/`.
Run git log for the period to see what was actually committed (use the Bash tool — Git Bash on
Windows): `git log --oneline --since="4 weeks ago" || git log --oneline -20` (adjust `--since`
to the sprint duration). If no data exists, offer to take the details manually or stop.

## Phase 3: Analyze Completion & Trends

Compare plan vs. actual: completed as planned, completed but modified, carried over, added
mid-sprint, descoped. Scan the codebase for TODO/FIXME/HACK trends vs. previous retrospectives
(is debt growing or shrinking?). Read previous retrospectives — were prior action items
addressed? Are the same problems recurring?

## Phase 4: Generate the Retrospective

```markdown
## Retrospective: [Sprint N / Milestone]  ·  Period: [start]–[end]  ·  Generated: [date]

### Metrics
| Metric | Planned | Actual | Delta | (tasks, completion %, effort, bugs found/fixed, unplanned added, commits)

### Velocity Trend
| Sprint | Planned | Completed | Rate |   — Trend: [Increasing/Stable/Decreasing]

### What Went Well  ·  What Went Poorly (systemic causes, no blame)

### Blockers Encountered
| Blocker | Duration | Resolution | Prevention |

### Estimation Accuracy (most over/under-estimated, likely cause)

### Carryover Analysis  ·  Technical Debt Status (TODO/FIXME/HACK counts vs. previous)

### Previous Action Items Follow-Up
| Action (from last time) | Status | Notes |

### Action Items for Next Iteration (3–5 max, each with an owner)
| # | Action | Owner | Priority | Deadline |

### Summary (2–3 sentences: was this a good sprint? single most important thing to change?)
```

## Phase 5: Save

Present the retrospective and top findings, then ask: "May I write this to
`docs/production/retrospectives/retro-[sprint/milestone]-[date].md`?" Write only on approval.

## Next Steps

- `/sprint-plan new` — plan the next sprint with these action items and velocity in mind.
- For a milestone retro, `/milestone-review [next]` when approaching the next checkpoint.

**Guidelines:** be specific and data-backed; focus on systemic issues, not blame; limit to 3–5
action items, each with an owner; flag recurring unaddressed items as a process smell.
