# Credits & Third-Party Licenses

`cloud-nine-unity` is built out of two excellent open-source projects, both MIT-licensed. It does not
merely depend on them — it **contains** them. Attribution is therefore an obligation, not a courtesy.

`provenance.tsv` at the repo root records, for every tracked file, which upstream it came from,
which version, and whether we modified it. Everything below is verifiable against it; nothing here
is asserted on trust.

| Project | Relationship | In this repo? |
|---------|--------------|---------------|
| [everything-claude-unity](https://github.com/XeldarAlz/everything-claude-unity) (XeldarAlz) | **Vendored** at v1.5.0 — the engineering layer | **Yes** — 158 files (120 verbatim, 38 modified) |
| [Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) (Donchitos) | **Adapted** at `984023d` — the design/production layer | **Yes** — 22 files, each attributed inline |
| [unity-mcp](https://github.com/CoplayDev/unity-mcp) (CoplayDev) | **Targeted** — the MCP editor bridge | No — install it yourself |

`.claude/NOTICE.md` carries these notices into every project the installer touches, because the
installer makes the user a recipient of the vendored code and MIT requires the notice to travel with
the copies.

---

## 1. everything-claude-unity ("ECU") — vendored (attribution required)

- **Repository:** https://github.com/XeldarAlz/everything-claude-unity
- **Author:** XeldarAlz
- **Pinned at:** v1.5.0 — commit `bb28ccbd40b065b0958b02df0c03fb91c4fb7c5b` (2026-04-24)
- **License:** MIT

**ECU is the engineering backbone of this toolkit and its source is included here.** Earlier versions
of cloud-nine-unity were an overlay that required you to install ECU separately and shipped none of
its code. That is no longer true: the `unity-*` agents and commands, the skills, the hooks, the five
spine rules in `.claude/rules/`, `settings.json`, and the repo's `scripts/`, `tests/`, `docs/`,
`examples/`, and `templates/` are all ECU's work, vendored into this repository.

**What we changed.** Mobile content was removed rather than disabled — ECU targets mobile developers
and this toolkit is PC/console only (`provenance-skip.tsv` lists every omission and why). Some
vendored files were modified: the mobile strip, and fixes to defects found in the upstream (see
`MERGE-NOTES.md`). `provenance.tsv` marks each such file `status=modified`, so ECU's work and our
divergence from it stay distinguishable.

### License text

Reproduced verbatim from everything-claude-unity's `LICENSE` at v1.5.0.

**The upstream notice names no copyright holder** — it reads `Copyright (c) 2026` with nothing after
it. The repository is authored by XeldarAlz. We reproduce the notice exactly as published rather than
amend it: writing a holder into someone else's copyright notice is not ours to do. This paragraph is
the attribution the bare notice cannot give.

```
MIT License

Copyright (c) 2026

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

## 2. Claude-Code-Game-Studios ("Donchitos") — adapted (attribution required)

- **Repository:** https://github.com/Donchitos/Claude-Code-Game-Studios
- **Copyright:** Copyright (c) 2026 Donchitos
- **Pinned at:** commit `984023d` (2026-05-13)
- **License:** MIT

The design and production layer is **adapted** from Donchitos: the agents `game-designer`,
`systems-designer`, `level-designer`, `narrative-director`, `writer`, `world-builder`,
`creative-director`, `technical-director`; the commands `brainstorm`, `design-review`, `map-systems`,
`design-system`, `sprint-plan`, `scope-check`, `milestone-review`, `estimate`, `retrospective`; and
the templates `game-design-document`, `architecture-decision-record`, `sprint-plan`, `game-concept`,
`systems-index`.

Each adapted file carries an inline `<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT -->`
comment. Upstream, the commands are "skills" at `.claude/skills/<name>/SKILL.md` and the templates
live under `.claude/docs/templates/`; `provenance.tsv` records the original path for each.

Donchitos's files were reformatted to this toolkit's conventions, scoped to Unity 6 / PC-console, and
trimmed of the heavy multi-gate production pipeline. This is a thin slice of a much larger project —
roughly 8 of its 49 agents and 9 of its 73 commands. See `MERGE-NOTES.md` for the full delta.

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

## 3. MCP for Unity / unity-mcp (CoplayDev) — targeted (dependency)

- **Repository:** https://github.com/CoplayDev/unity-mcp
- **Copyright:** Copyright (c) 2025 CoplayDev
- **Current version:** 10.1.0 (2026-07-13)
- **License:** MIT

This toolkit targets CoplayDev's open-source **Unity MCP bridge** (Unity package
`com.coplaydev.unity-mcp`). Our `.claude/settings.json` points at it on `http://localhost:8080/mcp`,
and the `unity-mcp-patterns` skill documents its `snake_case` tools (`manage_scene`,
`manage_gameobject`, `create_script`, `validate_script`, `read_console`, `batch_execute`).

**No CoplayDev code is included here.** `MCP-SETUP.md` documents how to install and verify it; the
open-source bridge needs no API key (that is Coplay's separate commercial product). `install.sh
--with-mcp` will add the package to your `Packages/manifest.json`.

---

## Everything else

Files marked `origin=original` in `provenance.tsv` — `.claude/rules/pc-console.md`, the installer,
the provenance tooling, the tests we added, and this documentation — are original to
cloud-nine-unity: MIT, Copyright (c) 2026 OmerZeyveli. See `LICENSE`.
