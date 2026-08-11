# Third-Party Notices

The `.claude/` directory installed into your project contains MIT-licensed material from other
open-source projects. The MIT License requires their copyright and permission notices to travel with
all copies or substantial portions of the software — this file is how that obligation is met, and it
is why it ships into your project rather than staying in the toolkit repo.

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
| [Superpowers](https://github.com/obra/superpowers) | adapted at 6.2.0 (`3dcbd5c`) on 2026-08-10 — the process chain, rewritten for Unity from its originals | the skills in §3's *Adapted surfaces* table |

Files not attributable to any of those are original to Kinglet Pioneer, MIT, Copyright (c) 2026
OmerZeyveli. **The manifest is the list**, not this paragraph — every row with `origin=original` in the
toolkit's `provenance.tsv`, linked above. Those rows are:

| File | What it is |
|---|---|
| `rules/pc-console.md` | the platform spec; the only rule not vendored |
| `hooks/block-legacy-input.sh` | blocks the legacy Input Manager API. Three rule files had claimed for a long time that a hook enforced this. None did — not here, not in ECU v1.5.0. This is that hook. |
| `hooks/session-brief.sh` | the session-start brief |
| `skills/using-kinglet/SKILL.md` | which surface handles which situation |
| `skills/subagent-driven-implementation/` | the execution loop — `SKILL.md` and its four prompt files |
| `skills/systematic-debugging/SKILL.md` | read the real console before proposing a fix |
| `skills/verification-before-completion/SKILL.md` | evidence before a completion claim |
| `NOTICE.md` | this file |
| `VERSION`, `UPSTREAM` | which toolkit build this is, and what it pins |

**This table carries no count, deliberately.** It used to name three files and stop, which meant
three original files travelled with no stated copyright holder at all — in the document whose whole
job is to state copyright holders. It was then given a count, and the count went stale by nine while
the sentence above it still read "at the time of writing". A number that moves every time an
original file is added carries no signal a reader would act on, so the table enumerates instead. If
you add an original file under `.claude/`, add its manifest row and a row here; the first is what
makes it attributable and `tests/test-provenance-origins.sh` fails until the second exists.

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

## 3. Superpowers — adapted, MIT

Superpowers is a Claude Code skill library by Jesse Vincent. This toolkit's process chain — the
skills that decide what happens before code is written — is adapted from it.

**What this section used to say, and why it changed.** Until 2026-08-10 it recorded Superpowers as
an influence only: the chain design (skills that name the next skill) and two skill names had been
taken; the skills that existed then had had their wording measured against their Superpowers
counterparts and found to be ours; and no license text was reproduced. That was an accurate account
of the toolkit as it stood on that date.

On 2026-08-10 the process chain was rebuilt, and three skills were adapted from Superpowers **at the
expression level** — their structure, their step sequence and, in places, their wording. MIT covers
expression. The obligation therefore exists as of that date, and this section is where it is
discharged.

The earlier similarity measurements are **withdrawn, not re-taken.** They described a state that no
longer holds, and a freshly measured number would go stale in exactly the same way. The per-file
truth lives in `provenance.tsv`, linked at the top of this file, where it is re-derived rather than
remembered.

### Adapted surfaces

| File in this toolkit | Adapted from Superpowers 6.2.0 | How `provenance.tsv` records it |
|---|---|---|
| `.claude/skills/unity-brainstorming/SKILL.md` | `skills/brainstorming/SKILL.md` | `origin=ecu` — this file's lineage begins at everything-claude-unity and that material survives in it, so the origin column stays with the first upstream and the Superpowers adaptation is recorded in the row's note |
| `.claude/skills/unity-planning/SKILL.md` | `skills/writing-plans/SKILL.md` | `origin=superpowers` |
| `.claude/skills/unity-execution/SKILL.md` | `skills/executing-plans/SKILL.md` | `origin=superpowers` |

All three are `status=modified`: every one was rewritten for Unity 6 and for this toolkit's surfaces,
and none is a copy. That is a statement about how much changed, not a reduction of the obligation.

**No automated check in the toolkit verifies the Superpowers pin.** `scripts/check-provenance.sh`
compares checksums only for rows marked `status=verbatim`, and its `--online` pass additionally only
for rows from everything-claude-unity — so both skip every row above. The `6.2.0` / `3dcbd5c` pin in
`provenance.tsv` is a record kept by hand, and it is worth saying so rather than letting the presence
of checksum machinery imply a coverage it does not have.

### Influence, not expression

The surfaces below owe Superpowers something short of expression, and stay `origin=original` in
`provenance.tsv`:

- `.claude/skills/subagent-driven-implementation/` takes the shape of its loop — a fresh implementer
  per task, a review gate between tasks — from Superpowers' `subagent-driven-development`. The
  wording, and the Unity rules layered on it, are ours.
- `.claude/skills/systematic-debugging/SKILL.md` and
  `.claude/skills/verification-before-completion/SKILL.md` share their names with Superpowers
  skills, and nothing else.

They are named here for completeness. They are not part of the obligation discharged above.

### License text

Reproduced verbatim from Superpowers' `LICENSE` at 6.2.0.

```
MIT License

Copyright (c) 2025 Jesse Vincent

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

See the toolkit repository's `CREDITS.md` for the same record at more detail.
