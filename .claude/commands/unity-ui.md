---
name: unity-ui
description: "Build UI screens — writes code + sets up visual hierarchy via MCP. Supports UGUI Canvas and UI Toolkit."
user-invocable: true
args: screen_description
---

# /unity-ui — Build a UI Screen

Build a UI screen based on: **$ARGUMENTS**

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
