---
name: unity-feature
description: "Plans and implements a Unity feature — identifies subsystems, loads skills, writes code, sets up scene elements via MCP."
user-invocable: true
args: feature_description
---

# /unity-feature — Implement a Feature

Plan and implement the feature described by the user: **$ARGUMENTS**

## Agent Routing

- Default: use `unity-coder` agent (opus — full architectural reasoning)
- If `$ARGUMENTS` contains `--quick`: use `unity-coder-lite` agent (sonnet — faster, for simple additions)
- Strip the `--quick` flag from arguments before passing to the agent

## Phase 1: Plan

1. **Analyze the feature** — identify which Unity subsystems are involved:
   - Input System? Physics? Animation? UI? Audio? Networking?
   - Which existing scripts/systems does this integrate with?

2. **Identify required scripts** — what new scripts to create, what existing ones to modify.

3. **Identify scene changes** — what GameObjects, components, or scene setup is needed.

4. **Present the plan** to the user before implementing. Include:
   - Scripts to create/modify
   - Scene changes via MCP
   - Dependencies on existing systems
   - Estimated complexity (simple / moderate / complex)

## Phase 2: Implement

1. **Write C# code** using the `unity-coder` agent:
   - Follow all rules in `.claude/rules/`
   - Place scripts in correct assembly definition
   - Use `[SerializeField]` for inspector configuration
   - Add `[Header]` attributes for organization

2. **Set up scene elements** via MCP:
   - Create GameObjects with `batch_execute`
   - Configure components
   - Set up physics layers if needed

3. **Check console** via `read_console` for compilation errors.

## Phase 3: Verify

1. Verify no console errors via `read_console`
2. Summarize what was created/modified
3. Explain how to test the feature
4. Note any manual steps needed (e.g., assigning references in Inspector)

## Phase 4: Auto-Verify (Optional)

After implementation, offer to run the `unity-verifier` agent for a verify-fix loop:
- Reviews all changed files for serialization safety, performance, and Unity-specific pitfalls
- Auto-fixes safe issues (missing FormerlySerializedAs, CompareTag, cached GetComponent, etc.)
- Re-verifies up to 3 iterations until clean
- Reports remaining items that require human judgment

Suggest: "Would you like me to run a verification pass on the changes?"
