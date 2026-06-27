# Credits & Third-Party Licenses

`cloud-nine-unity` is an **overlay** — it stands on three excellent open-source projects, all
MIT-licensed. This file gives each its due. Attribution for **Claude-Code-Game-Studios
(Donchitos)** is mandatory because this overlay *includes adapted copies* of its files; the other
two are integrations/dependencies and are credited here as a courtesy and a pointer.

---

## 1. Claude-Code-Game-Studios ("Donchitos") — adapted (attribution required)

- **Repository:** https://github.com/Donchitos/Claude-Code-Game-Studios
- **Copyright:** Copyright (c) 2026 Donchitos
- **License:** MIT
- **How it's used here:** The design and production layer of this overlay is **adapted** from
  Donchitos. Specifically, the agents `game-designer`, `systems-designer`, `level-designer`,
  `narrative-director`, `writer`, `world-builder`, `creative-director`, `technical-director`; the
  commands `brainstorm`, `design-review`, `map-systems`, `design-system`, `sprint-plan`,
  `scope-check`, `milestone-review`, `estimate`, `retrospective`; and the templates
  `game-design-document`, `architecture-decision-record`, `sprint-plan`, `game-concept`,
  `systems-index`. Each adapted file carries an inline `Adapted from Claude-Code-Game-Studios
  (Donchitos), MIT` comment. Donchitos's slash-commands ("skills") and agents were reformatted to
  the everything-claude-unity (ECU) conventions, scoped to Unity 6 / PC-console, and trimmed of
  Donchitos's heavy multi-gate production pipeline. See `MERGE-NOTES.md` for the full delta.

```
MIT License

Copyright (c) 2026 Donchitos

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 2. everything-claude-unity ("ECU") — required base layer (dependency)

- **Repository:** https://github.com/XeldarAlz/everything-claude-unity
- **Author:** XeldarAlz
- **License:** MIT
- **How it's used here:** ECU is the **foundation this overlay extends**. cloud-nine-unity does
  **not** copy or redistribute ECU's files — you install ECU yourself, then apply this overlay on
  top. ECU provides the Unity coder/reviewer agents, the `unity-*` commands, the MCP-powered
  skills (`unity-mcp-patterns`), the architecture/performance/serialization rules, the hooks, and
  the `settings.json` MCP wiring. This overlay was built and tested against **ECU v1.5.0**.

> No ECU source is included in this repository. ECU is MIT-licensed; obtain it from the repository
> above and follow its own license.

---

## 3. MCP for Unity / unity-mcp (CoplayDev) — integrated MCP bridge (dependency)

- **Repository:** https://github.com/CoplayDev/unity-mcp
- **Copyright:** Copyright (c) 2025 CoplayDev
- **License:** MIT
- **How it's used here:** This overlay targets CoplayDev's open-source **Unity MCP bridge**
  (Unity package `com.coplaydev.unity-mcp`) — the same MCP server ECU's `settings.json` already
  points at (`http://localhost:8080/mcp`). cloud-nine-unity does **not** include or redistribute
  CoplayDev's code; `MCP-SETUP.md` only documents how to install and verify it. The open-source
  bridge requires **no API key** for local use (that is Coplay's separate commercial product).

> No CoplayDev source is included in this repository. It is MIT-licensed; obtain it from the
> repository above and follow its own license.

---

### Summary

| Project | Role here | License | Included in this repo? |
|---------|-----------|---------|------------------------|
| Claude-Code-Game-Studios (Donchitos) | Design/production layer **adapted** into the overlay | MIT | Yes — adapted files, each attributed inline |
| everything-claude-unity (ECU) | Base toolkit this overlay **extends** | MIT | No — install separately |
| unity-mcp (CoplayDev) | MCP editor bridge this overlay **targets** | MIT | No — install separately |
