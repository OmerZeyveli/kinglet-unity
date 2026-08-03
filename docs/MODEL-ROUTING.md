# Model Routing Guide

## Overview

Agents use different Claude models based on task complexity. **Opus** handles creative, multi-step
reasoning. **Sonnet** handles structured analysis. This optimizes cost and latency without sacrificing
quality where it matters.

There is no `model-routing` skill — it was cut in the 2026-08-03 surface reduction along with the
tiered/lite-agent scheme it supported. Each agent's model is fixed in its frontmatter (`model:` field
in `.claude/agents/<name>.md`); there is no automatic tier selection or complexity heuristic at
runtime.

## Agent Model Assignments

| Agent | Model | Rationale |
|-------|-------|-----------|
| `unity-coder` | opus | Multi-system feature work needs architectural reasoning |
| `unity-fixer` | opus | Bugs with no obvious cause need deep investigation |
| `unity-optimizer` | opus | Performance analysis requires understanding trade-offs |
| `unity-prototyper` | opus | End-to-end prototyping requires creativity and planning |
| `unity-scene-builder` | opus | Scene composition needs spatial reasoning |
| `unity-ui-builder` | opus | UI layout and responsive design need creative decisions |
| `unity-reviewer` | sonnet | Checklist-based review is structured, not creative |
| `unity-test-runner` | sonnet | Test writing follows patterns, not deep reasoning |

## Command Flags

### `/unity-review --thorough`

The only model-switching flag in the current command set. Routes `unity-reviewer` to opus instead of
its default sonnet for deeper architectural analysis.

```bash
/unity-review --thorough "review the entire combat system"
```

**Use when** the review covers complex, interconnected systems or you're preparing for a major
release.

There is no `--quick` flag and no "lite" agent variant of any kind — those belonged to the removed
tiered scheme.

## Cost/Latency Trade-offs

| Model | Relative Cost | Relative Speed | Best For |
|-------|--------------|----------------|----------|
| **Sonnet** | 5x | Fast | Structured tasks, reviews, test writing |
| **Opus** | 25x | Slower | Creative work, complex reasoning, multi-step tasks |

(Haiku is not used by any current agent — the two haiku-tier agents, `unity-scout` and `unity-linter`,
were both removed in the 2026-08-03 cut.)

## Guidelines for New Agents

When creating a new agent:
1. **Default to sonnet** — upgrade to opus only if the task requires multi-step reasoning or creative
   generation.
2. **Document the model choice** in the agent's own frontmatter; there is no external routing table
   or skill to update.
3. Before adding the agent at all, apply the surface-cut criterion in `CLAUDE.md`: it survives only if
   it does something the model cannot do unaided.
