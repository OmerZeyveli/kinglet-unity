---
name: scope-check
description: "Analyzes a feature or sprint for scope creep by comparing current scope against the original plan. Flags additions, quantifies bloat, and recommends cuts. Read-only — writes no files."
user-invocable: true
args: feature-or-sprint
---
<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT — https://github.com/Donchitos/Claude-Code-Game-Studios -->

# /scope-check — Detect Scope Creep

Compare original planned scope against the current state to detect, quantify, and triage scope
creep. **Read-only** — reports findings, writes no files. A lightweight check; sonnet or haiku.

**Argument:** `$ARGUMENTS` — a feature name, sprint number (e.g. `sprint-3`), or milestone name.

## Phase 1: Find the Original Plan

Locate the baseline: a feature → `docs/design/[feature].md`; a sprint → `docs/production/sprints/sprint-[N].md`;
a milestone → `docs/production/milestones/[name].md`. If not found, report the missing file and
stop — do not proceed without a baseline.

## Phase 2: Read the Current State

Check what is actually implemented or in progress: scan `Assets/Scripts/` (and the repo) for
files related to the feature/sprint; read `git log --oneline` for related commits; check for
TODO/FIXME comments indicating unfinished additions; read the active sprint plan if mid-sprint.

## Phase 3: Compare Original vs Current

```markdown
## Scope Check: [Feature/Sprint Name]  ·  Generated: [Date]

### Scope Additions (not in original plan)
| Addition | Source | When | Justified? | Effort |

### Scope Removals (in original but dropped)
| Removed Item | Reason | Impact |

### Bloat Score
- Original items: [N] · Current items: [N] · Added: [N] (+[X]%) · Removed: [N] · Net: [+/-N] ([X]%)

### Risk Assessment
- Schedule / Quality / Integration risk: [Low/Medium/High] each — with one-line explanation

### Recommendations
1. Cut · 2. Defer · 3. Keep · 4. Flag (needs a decision)
```

## Phase 4: Verdict

| Net Change | Verdict | Meaning |
|-----------|---------|---------|
| ≤10% | **PASS** | On track — within acceptable variance |
| 10–25% | **CONCERNS** | Minor creep — manageable with targeted cuts |
| 25–50% | **FAIL** | Significant creep — must cut or extend timeline |
| >50% | **FAIL** | Out of control — stop, re-plan |

```
**Scope Verdict: [PASS / CONCERNS / FAIL]**  ·  Net change: [+X%]
```

## Phase 5: Next Steps

- **PASS** → no action; suggest re-running before the next milestone.
- **CONCERNS** → identify the 2–3 additions with the best cut ratio; reference `/sprint-plan update`.
- **FAIL** → recommend re-planning via `/sprint-plan update` or re-baselining with `/estimate`.

Always close with: "Run `/scope-check [name]` again after cuts to verify the verdict improves."

Scope creep is additions without corresponding cuts or timeline extensions. Not all additions
are bad — some are discovered requirements — but they must be acknowledged. Always quantify:
"+35% items", not "it feels bigger".
