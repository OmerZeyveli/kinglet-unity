---
name: unity-ui
description: "Use when the user wants a UI screen built — menu, HUD, settings panel, inventory screen. Writes the backing code and sets up the visual hierarchy via MCP; supports both UGUI Canvas and UI Toolkit."
user-invocable: true
args: screen_description
---

# /unity-ui — Build a UI Screen

> **Architecture stack — read before you write or refuse.** Which parts of
> `.claude/rules/architecture.md` bind here is stated in `CLAUDE.md`'s generated block, detected
> from this project's own code rather than assumed. A project with no VContainer is **not** a
> project where this surface does not apply — it is a project where you follow the architecture
> the code actually has. Refusing on stack grounds without reading that block is how a measured
> session locked itself out of every MCP-driven agent it had.

Build a UI screen based on: **$ARGUMENTS**

## Precondition: the approved design this command does not create

This command is the build step for a screen a design already specifies. It is not where a screen
gets decided. `unity-ui-builder` holds `mcp__UnityMCP__*` and writes `.cs`, and
`.claude/skills/unity-brainstorming/SKILL.md` withholds both until a design has been presented and
approved — so dispatching without one is not a shortcut through that gate, it is the thing the gate
forbids.

Run this yourself, here, before the agent starts:

```bash
ls -1 docs/features/*/design.md 2>/dev/null || true
```

- **Nothing listed** — this project has no written design at all. Stop. Go to
  `.claude/skills/unity-brainstorming/SKILL.md` and come back with one. Do not dispatch the agent.
- **Something listed** — open the one that covers this screen and build what it specifies. If none
  of them covers it, that is the same stop.

**Why here and not in the agent.** `unity-ui-builder`'s tools are `Skill, Read, Write, Edit, Glob,
Grep, mcp__UnityMCP__*` — no `Bash`, so it cannot run that check. This command body is executed by
the session that dispatches it, which is where the check can actually run.

**What the check cannot tell you.** A file on disk records a design; it does not record an approval,
and it does not know which screen you were asked for. Both halves are yours to establish before
dispatching — the listing is a necessary condition, never a sufficient one.

## Workflow

Use the `unity-ui-builder` agent to:

1. **Choose UI system** — UGUI (Canvas) or UI Toolkit based on project context
2. **Plan the layout** — identify elements, hierarchy, interaction, styling
3. **Write scripts:**
   - UGUI: MonoBehaviour with `[SerializeField]` Button/Text/Image references
   - UI Toolkit: UXML document + USS stylesheet + controller script
4. **Build visual hierarchy** via MCP:
   - UGUI: Canvas, panels, buttons, text via `manage_ui` + `manage_gameobject`
   - UI Toolkit: write UXML/USS files, attach UIDocument component
5. **Wire interactions** — button clicks, input fields, toggles
6. **Verify** via `read_console`

## UGUI Performance Rules
- Disable Raycast Target on non-interactive elements
- Split static/dynamic content into separate Canvases
- Avoid Layout Groups in scroll views

Report the screen structure, scripts created, and how to test.

## Suggest next

When this command finishes, name the next step and offer it. Do not take it.

Offer `/unity-review` — UI code is where Canvas rebuild and raycast-target faults land.
