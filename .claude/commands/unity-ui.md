---
name: unity-ui
description: "Use after a design for the screen is approved — this is the build step for a menu, HUD, settings panel or inventory screen, not where a screen gets decided. Writes the backing code and sets up the visual hierarchy via MCP; supports both UGUI Canvas and UI Toolkit."
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
- **Listed, but you cannot point to where the user approved it** — ask, and wait for the answer
  before dispatching. The gate turns on "presented **and** approved", and your own reading of the
  file is not the approval.

**What the listing cannot tell you.** It reports that a design exists. It does not report that this
one covers the screen you were asked for, and it cannot report an approval at all — approval happens
in the conversation, not on disk. The three branches above are how each of those is settled; the
listing is a necessary condition, never a sufficient one.

**Why here and not in the agent.** `unity-ui-builder`'s tools are `Skill, Read, Write, Edit, Glob,
Grep, mcp__UnityMCP__*` — no `Bash`, so it cannot run that check. This command body is executed by
the session that dispatches it, which is where the check can actually run. The agent carries the
same precondition in prose, because it can also be dispatched directly and then never sees this file.

## Workflow

Use the `unity-ui-builder` agent to:

> **If the agent cannot be dispatched, do the work inline and say so.** A user or project setting
> that forbids unrequested `Agent` calls outranks this command body, and that precedence is correct.
> Run these steps yourself, load the skills `unity-ui-builder` lists under **Skills to load**, and
> report that the work ran inline rather than in the agent.

1. **Choose UI system** — UGUI (Canvas) or UI Toolkit based on project context
2. **Plan the layout** — identify elements, hierarchy, interaction, styling
3. **Write scripts:**
   - UGUI: MonoBehaviour with `[SerializeField]` Button/Text/Image references
   - UI Toolkit: UXML document + USS stylesheet + controller script
4. **Build visual hierarchy** via MCP:
   - UGUI: Canvas, panels, buttons, text via `manage_gameobject` + `manage_components`, both in the
     `core` tool group. **Not `manage_ui`** — its action set holds nothing that touches a Canvas, a
     Button or a RectTransform.
   - UI Toolkit: write the UXML and USS files yourself (no MCP tool authors that markup), then wire
     them into the scene with `manage_ui` — `attach_ui_document`, `create_panel_settings`,
     `link_stylesheet`. `manage_ui` is in the `ui` group, which is off by default; the agent
     activates it before its first call.
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
