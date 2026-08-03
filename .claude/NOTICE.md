# Third-Party Notices

The `.claude/` directory installed into your project contains MIT-licensed material from two upstream
projects. The MIT License requires their copyright and permission notices to travel with all copies
or substantial portions of the software — this file is how that obligation is met, and it is why it
ships into your project rather than staying in the toolkit repo.

You do not need to do anything with this file. Keep it alongside `.claude/` and the obligation stays
satisfied.

The per-file record — which upstream each file came from, at which commit, verbatim or modified,
with its checksum — lives in the toolkit repository as `provenance.tsv`, not here:

> https://github.com/OmerZeyveli/kinglet-unity/blob/main/provenance.tsv

It is deliberately not copied into installed projects. A copy goes stale the moment the toolkit's
own manifest changes, and a stale attribution record is worse than a link to a live one — that is
not hypothetical, it happened twice in two days and was believed both times. The claims below stay
verifiable; you just verify them against the source rather than a snapshot.

| Project | Role | Files |
|---|---|---|
| [everything-claude-unity](https://github.com/XeldarAlz/everything-claude-unity) | vendored at v1.5.0 (`bb28ccb`); mobile content removed, some files modified | agents `unity-*`, commands `unity-*`, skills, hooks, 5 rules, `settings.json` |
| [Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) | adapted at `984023d`, removed 2026-08-03; no Claude-Code-Game-Studios content ships in this toolkit today | 0 files |

Files not attributable to either are original to Kinglet Pioneer, MIT, Copyright (c) 2026
OmerZeyveli. **The manifest is the list**, not this paragraph — every row with `origin=original` in the
toolkit's `provenance.tsv`, linked above. At the time of writing that is five files:

| File | What it is |
|---|---|
| `rules/pc-console.md` | the platform spec; the only rule not vendored |
| `hooks/block-legacy-input.sh` | blocks the legacy Input Manager API. Three rule files had claimed for a long time that a hook enforced this. None did — not here, not in ECU v1.5.0. This is that hook. |
| `NOTICE.md` | this file |
| `VERSION`, `UPSTREAM` | which toolkit build this is, and what it pins |

This paragraph used to name three of them and stop, which meant three original files travelled with
no stated copyright holder at all — in the document whose whole job is to state copyright holders.
It was found by someone reading this file and reporting back what it said. If you add an original
file under `.claude/`, add its manifest row; that is what makes it attributable, and this table is a
convenience that follows from it.

The [CoplayDev Unity MCP bridge](https://github.com/CoplayDev/unity-mcp) is **not** included here.
`.mcp.json` merely points at it on `localhost`; install it yourself via Package Manager.

---

## 1. everything-claude-unity

Reproduced verbatim from everything-claude-unity's `LICENSE` at v1.5.0. **The upstream notice names
no copyright holder**; the repository is authored by XeldarAlz. We reproduce the notice as published
rather than amend it — writing a holder into someone else's copyright notice is not ours to do.

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

## 2. Claude-Code-Game-Studios

The design and production layer was adapted from Claude-Code-Game-Studios at `984023d` and was
removed on 2026-08-03, so no Claude-Code-Game-Studios content ships in this toolkit today. This
notice is retained because the work was derived from it historically. Its license text is
reproduced verbatim from Claude-Code-Game-Studios' `LICENSE` at `984023d`.

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
