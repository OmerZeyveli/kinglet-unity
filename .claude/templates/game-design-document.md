<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT — https://github.com/Donchitos/Claude-Code-Game-Studios -->
<!-- cloud-nine-unity GDD template. Lives at .claude/templates/ after install; authored copies go to docs/design/. -->

# [Mechanic/System Name]

> **Status**: Draft | In Review | Approved | Implemented
> **Author**: [Agent or person]
> **Last Updated**: [Date]
> **Implements Pillar**: [Which game pillar this supports]

## Summary

[2–3 sentences: what this system is, what it does for the player, and why it exists in this
game. Written so a skill scanning many GDDs can decide whether to read further. No jargon.]

> **Quick reference** — Layer: `[Foundation | Core | Feature | Presentation]` · Priority: `[MVP | Vertical Slice | Alpha | Full Vision]` · Key deps: `[System names or "None"]`

## Overview

[One paragraph that explains this mechanic to someone who knows nothing about the project. What
is it, what does the player do, and why does it exist?]

## Player Fantasy

[What should the player FEEL when engaging with this mechanic? What emotional or power fantasy is
served? This section guides all detail decisions below.]

## Detailed Design

### Core Rules

[Precise, unambiguous rules. A programmer should be able to implement this section without asking
questions. Numbered rules for sequential processes, bullets for properties.]

### States and Transitions

[If this system has states (weapon states, status effects, phases), document every state and
every valid transition.]

| State | Entry Condition | Exit Condition | Behavior |
|-------|----------------|----------------|----------|

### Interactions with Other Systems

[How does this interact with combat, inventory, progression, UI? For each interaction, specify
the interface: what data flows in, what flows out, who owns what. In this project, cross-system
communication goes through **MessagePipe**, not direct references — note which messages this
system publishes/subscribes to.]

## Formulas

[Every mathematical formula used by this system. For each:]

### [Formula Name]

```
result = base_value * (1 + modifier_sum) * scaling_factor
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| base_value | float | 1–100 | ScriptableObject | The base amount before modifiers |
| modifier_sum | float | -0.9 to 5.0 | calculated | Sum of all active modifiers |
| scaling_factor | float | 0.5–2.0 | ScriptableObject | Level-based scaling |

**Expected output range**: [min] to [max]
**Edge case**: When modifier_sum < -0.9, clamp to -0.9 to prevent negative results.

> Tuning values are authored in **ScriptableObjects / external config, never hardcoded**
> (ECU `serialization` + `architecture` rules).

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| [What if X is zero?] | [This happens] | [Why] |
| [What if both effects trigger?] | [Priority rule] | [Design reasoning] |

## Dependencies

| System | Direction | Nature of Dependency |
|--------|-----------|---------------------|
| [Combat] | This depends on Combat | Needs damage calculation results |
| [Inventory] | Inventory depends on this | Provides item effect data |

## Tuning Knobs

| Parameter | Current Value | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|--------------|------------|-------------------|-------------------|

## Visual/Audio Requirements

| Event | Visual Feedback | Audio Feedback | Priority |
|-------|----------------|---------------|----------|

## Game Feel

> Visual/Audio Requirements document WHAT feedback events occur. Game Feel documents HOW the
> mechanic feels to operate — responsiveness, weight, snap, kinesthetic quality. Specify at design
> time because it drives animation budgets, input-handling architecture, and hitbox timing.
> On PC/console, target a crisp 60 FPS response (and account for high-refresh PC displays).

### Feel Reference

[Name a specific game, mechanic, or moment that captures the target feel. Be precise. Optionally
include an anti-reference (what this should NOT feel like).]

### Input Responsiveness

[Max acceptable latency from input to visible/audible response, per action. Author for
keyboard/mouse AND gamepad — this is a PC/console game.]

| Action | Max Input-to-Response Latency (ms) | Frame Budget (at 60 fps) | Notes |
|--------|-----------------------------------|--------------------------|-------|
| [Primary action] | [e.g., 50ms] | [e.g., 3 frames] | |

### Animation Feel Targets

| Animation | Startup Frames | Active Frames | Recovery Frames | Feel Goal | Notes |
|-----------|---------------|--------------|----------------|-----------|-------|

### Impact Moments

| Impact Type | Duration (ms) | Effect Description | Configurable? |
|-------------|--------------|-------------------|---------------|
| Hit-stop (freeze frames) | [e.g., 80ms] | [Freeze both objects on contact] | Yes |
| Screen shake | [e.g., 150ms] | [Directional, decaying] | Yes |
| Controller rumble | | [Gamepad haptics] | Yes |

### Feel Acceptance Criteria

- [ ] [e.g., "Combat feels impactful — playtesters comment on weight unprompted"]
- [ ] [e.g., "No reviewer uses 'floaty', 'slippery', or 'unresponsive'"]
- [ ] [e.g., "Input latency is imperceptible at target 60 fps"]

## UI Requirements

[What information needs to be displayed, where, and when? Anchor for multiple resolutions and
aspect ratios, including ultrawide on PC.]

| Information | Display Location | Update Frequency | Condition |
|-------------|-----------------|-----------------|-----------|

## Cross-References

[Declare every explicit dependency on another GDD's specific mechanic, value, or rule. If you
reference another system's behavior anywhere in this document, it must appear here.]

| This Document References | Target GDD | Specific Element | Nature |
|--------------------------|-----------|------------------|--------|
| [e.g., "combo multiplier feeds score"] | `docs/design/score.md` | `combo_multiplier` output | Data dependency |

> **Nature** is one of: `Data dependency` (we consume their output), `State trigger` (their
> state change triggers our behavior), `Rule dependency` (our rule assumes their rule holds),
> `Ownership handoff` (we hand off ownership of a value to them).

## Acceptance Criteria

- [ ] [Criterion 1: specific, measurable, testable]
- [ ] [Criterion 2]
- [ ] Performance: system update completes within [X]ms; zero GC allocations in hot paths
- [ ] No hardcoded tuning values in implementation

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
