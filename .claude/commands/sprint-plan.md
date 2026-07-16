---
name: sprint-plan
description: "Generates a new sprint plan or updates an existing one based on the current milestone, completed work, and available capacity. Writes to docs/production/sprints/."
user-invocable: true
args: new-update-or-status
---
<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT — https://github.com/Donchitos/Claude-Code-Game-Studios -->

# /sprint-plan — Plan a Sprint

Generate or update a sprint plan, or report status. Lightweight production planning for a solo
dev or small team — no heavy gate ceremony. Writes Markdown to `docs/production/sprints/`.

## Mode

`$ARGUMENTS` selects the mode: `new` (default), `update`, or `status`.

## Phase 1: Gather Context

Read the current milestone from `docs/production/milestones/` (if any), the previous sprint from
`docs/production/sprints/` (for velocity and carryover), and scan `docs/design/` for systems/GDDs
marked ready for implementation.

## Phase 2: Generate Output

**For `new`** — generate a sprint plan and present it (don't write yet):

```markdown
# Sprint [N] — [Start Date] to [End Date]

## Sprint Goal
[One sentence toward the milestone]

## Capacity
- Total days: [X]  ·  Buffer (20%): [Y]  ·  Available: [Z]

## Tasks
### Must Have (Critical Path)
| ID | Task | Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------|-----------|--------------|---------------------|

### Should Have
| ID | Task | Owner | Est. Days | Dependencies | Acceptance Criteria |

### Nice to Have (Cut First)
| ID | Task | Owner | Est. Days | Dependencies | Acceptance Criteria |

## Carryover from Previous Sprint
| Task | Reason | New Estimate |

## Risks
| Risk | Probability | Impact | Mitigation |

## Definition of Done
- [ ] All Must Have tasks completed and passing their acceptance criteria
- [ ] Logic/system code has passing tests (run ECU's `/unity-test`)
- [ ] Code reviewed (run ECU's `/unity-review`) — no S1/S2 issues in delivered features
- [ ] Design docs updated for any deviations
```

Use the template at `.claude/templates/sprint-plan.md` for the full structure.

**For `update`** — read the most recent sprint plan, present the current task list, ask the user
(via `AskUserQuestion`) what to add/remove/reprioritize/re-estimate, apply changes, and
re-present. Tasks already in progress or done keep their status.

**For `status`** — generate a concise status report: Progress (X/Y, Z%), Completed, In Progress
(+ blockers), Not Started (at risk?), Blocked, a burndown assessment (on track / behind /
ahead), and emerging risks.

## Phase 3: Feasibility Check (lightweight)

Before writing, sanity-check the plan against capacity: does the Must-Have effort fit inside
Available days with the buffer intact? If it overflows, say so plainly and offer to defer the
weakest Should/Nice-to-Have items. For a heavier feasibility opinion, the user can consult the
`technical-director` agent — optional, not required.

Then ask: "May I write the sprint plan to `docs/production/sprints/sprint-[N].md`?" Write only
after approval (create directories as needed).

## Next Steps

- Implement the first task with ECU's `/unity-feature`.
- `/sprint-plan status` — check progress mid-sprint.
- `/scope-check sprint-[N]` — verify no scope creep before/while implementing.
- `/retrospective sprint-[N]` — at sprint end.
