# Third-Party Notices

The `.claude/` directory installed into your project contains MIT-licensed material from two upstream
projects. The MIT License requires their copyright and permission notices to travel with all copies
or substantial portions of the software — this file is how that obligation is met, and it is why it
ships into your project rather than staying in the toolkit repo.

You do not need to do anything with this file. Keep it alongside `.claude/` and the obligation stays
satisfied.

`.claude/provenance.tsv` records which specific file came from which upstream, so the claims below
are verifiable rather than asserted.

| Project | Role | Files |
|---|---|---|
| [everything-claude-unity](https://github.com/XeldarAlz/everything-claude-unity) | vendored at v1.5.0 (`bb28ccb`); mobile content removed, some files modified | agents `unity-*`, commands `unity-*`, skills, hooks, 5 rules, `settings.json` |
| [Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) | adapted at `984023d`; reformatted to this toolkit's conventions | 8 design agents, 9 design commands, 5 templates |

Files not attributable to either — `rules/pc-console.md`, this notice, and the manifest — are
original to cloud-nine-unity, MIT, Copyright (c) 2026 OmerZeyveli.

The [CoplayDev Unity MCP bridge](https://github.com/CoplayDev/unity-mcp) is **not** included here.
`settings.json` merely points at it on `localhost`; install it yourself via Package Manager.

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

Reproduced verbatim from Claude-Code-Game-Studios' `LICENSE` at `984023d`. Each adapted file also
carries an inline `<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT -->` comment.

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
