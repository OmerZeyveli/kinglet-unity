<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT — https://github.com/Donchitos/Claude-Code-Game-Studios -->
<!-- cloud-nine-unity ADR template. Authored copies go to docs/adr/. -->

# ADR-[NNNN]: [Title]

## Status

[Proposed | Accepted | Deprecated | Superseded by ADR-XXXX]

## Date

[YYYY-MM-DD — when this ADR was written]

## Last Verified

[YYYY-MM-DD — when this ADR was last confirmed accurate against the current Unity version and
design. Update when you re-read and confirm it, even if nothing changed.]

## Decision Makers

[Who was involved — typically the user + the `technical-director` agent]

## Summary

[2 sentences: what problem this ADR solves, and what was decided. Name the system, the problem,
and the chosen approach.]

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Unity 6 (C#) |
| **Domain** | [Physics / Rendering / UI / Audio / Navigation / Animation / Networking / Core / Input / Scripting] |
| **Knowledge Risk** | [LOW — in training data / MEDIUM — near cutoff, verify / HIGH — post-cutoff, must verify] |
| **References Consulted** | [Unity 6 docs, package docs, ECU rules consulted] |
| **Verification Required** | [Concrete behaviors to test against Unity 6 before shipping, or "None"] |

> If Knowledge Risk is MEDIUM or HIGH, re-validate this ADR if the project upgrades Unity
> versions. Flag it "Superseded" and write a new ADR.

## Architecture Constraints (project-fixed)

This project's architecture is fixed by ECU's rules and may not be overridden by an ADR:
**Model-View-System** pattern, **VContainer** (DI), **MessagePipe** (cross-system messaging),
**UniTask** (async, no coroutines), and the **New Input System**. An ADR refines *how* these are
applied to this decision; if a decision appears to require violating them, stop and surface the
conflict instead.

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | [ADR-NNNN (must be Accepted first), or "None"] |
| **Enables** | [ADR-NNNN this unlocks, or "None"] |
| **Blocks** | [System/feature that cannot start until this is Accepted, or "None"] |

## Context

### Problem Statement

[What problem are we solving? Why decide now? What is the cost of not deciding?]

### Current State

[How does the system work today? What is wrong with the current approach?]

### Constraints

- [Technical — Unity 6 / package limitations, platform (PC/console) requirements]
- [Timeline — deadlines, dependencies]
- [Resource — team size, expertise]
- [Compatibility — must work with existing systems and ECU's architecture]

### Requirements

- [Functional requirement(s)]
- [Performance requirement — specific, measurable (see pc-console.md for PC/console targets)]

## Decision

[The specific technical decision, described in enough detail to implement without further
clarification.]

### Architecture

```
[ASCII diagram: components, data-flow direction, key interfaces. Show LifetimeScope registration
and MessagePipe message flow where relevant.]
```

### Key Interfaces

```csharp
// Interface/contract definitions this decision creates — the contracts implementers must respect.
```

### Implementation Guidelines

[Specific guidance for the programmer (ECU's unity-coder) implementing this decision.]

## Alternatives Considered

### Alternative 1: [Name]

- **Description** / **Pros** / **Cons** / **Estimated Effort** / **Rejection Reason**

### Alternative 2: [Name]

[Same structure]

## Consequences

### Positive / Negative / Neutral

- [...]

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| CPU (frame time) | [X]ms | [Y]ms | [Z]ms |
| Memory | [X]MB | [Y]MB | [Z]MB |
| Load Time | [X]s | [Y]s | [Z]s |

## Migration Plan

[If this changes existing systems, the step-by-step plan to migrate.]

**Rollback plan**: [How to revert if this decision proves wrong]

## Validation Criteria

- [ ] [Measurable criterion 1]
- [ ] [Performance criterion]

## GDD Requirements Addressed

<!-- MANDATORY. Every ADR traces back to at least one GDD requirement, or explicitly states it is
     a foundational decision with no GDD dependency. -->

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| [e.g. `docs/design/combat.md`] | [Combat] | [e.g. "Hitbox detection resolves within 1 frame"] | [e.g. "Physics queries run synchronously in FixedUpdate"] |

> If this is a foundational decision with no direct GDD dependency, write: "Foundational — no GDD
> requirement. Enables: [GDD systems this unlocks or constrains]."

## Related

- [Links to related ADRs — note if supersedes, contradicts, or depends on]
- [Links to relevant code files once implemented]
