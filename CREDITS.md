# Credits & Third-Party Licenses

`Kinglet Pioneer` is built out of other people's excellent open-source work, all MIT-licensed. It
does not merely depend on it — it **contains** it: everything-claude-unity is vendored, and the
process-chain skills are adapted from Superpowers at the expression level. Attribution is therefore
an obligation, not a courtesy.

`provenance.tsv` at the repo root records, for every tracked file, which upstream it came from,
which version, and whether we modified it. Everything below is verifiable against it; nothing here
is asserted on trust. The manifest's 17/64 split is derived, not typed by hand: `awk -F'\t' '$0 !~ /^#/ &&
$1 != "path" {print $6}' provenance.tsv | sort | uniq -c` counts 17 `verbatim` and 64 `modified` rows
across the whole manifest. The table below states each upstream's own footprint instead, in wording
that cannot be mistaken for this repo-wide number — see the next paragraph for why that matters.

**The split is repo-wide, not ECU's.** This paragraph attributed it to `origin=ecu` until
2026-08-10, and that was true only by coincidence: ECU was the only vendored origin. It no longer
is. The process-chain surfaces adapted from Superpowers 6.2.0 carry `origin=superpowers`, and every
one of them is `modified`, so the second number now counts files from two upstreams. Per-origin
counts belong in the sections below and in `provenance.tsv`, never in this sentence — a per-origin
number written in the same phrasing as the repo-wide one is indistinguishable from it to any reader,
including `tests/test-derived-counts.sh`.

**Re-derive it before quoting it.** A single `status` flip changes the split, and this number has now
gone stale twice — most recently one commit after it was corrected, when `docs/MODEL-ROUTING.md`
moved from `verbatim` to `modified`. Nothing asserts it, so nothing will tell you it is wrong.

| Project | Relationship | In this repo? |
|---------|--------------|---------------|
| [everything-claude-unity](https://github.com/XeldarAlz/everything-claude-unity) (XeldarAlz) | **Vendored** at v1.5.0 — the engineering layer | **Yes** — 79 files; 17 of them still byte-identical to upstream, the rest rewritten |
| [Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) (Donchitos) | **Adapted** at `984023d` — the design/production layer, removed 2026-08-03 | **No** — 0 files; see §2 for why the notice is retained anyway |
| [Superpowers](https://github.com/obra/superpowers) (Jesse Vincent) | **Adapted** at 6.2.0 on 2026-08-10 — the process chain, at the expression level | **Yes** — the skills listed in §4, all rewritten for Unity |
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
of Kinglet Pioneer were an overlay that required you to install ECU separately and shipped none of
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

## 2. Claude-Code-Game-Studios ("Donchitos") — adapted historically, removed 2026-08-03

- **Repository:** https://github.com/Donchitos/Claude-Code-Game-Studios
- **Copyright:** Copyright (c) 2026 Donchitos
- **Pinned at:** commit `984023d` (2026-05-13)
- **License:** MIT

The design and production layer **was adapted** from Donchitos: a set of design/production agents,
commands and templates, listed by name in `provenance-skip.tsv` (`origin=donchitos`,
`rule=absent`) rather than repeated here — a name enumerated in this document is one more place
that goes stale the next time the set changes, which is exactly the defect this section exists to
avoid.

**All of it was removed on 2026-08-03** (see the surface-cut design in
`docs/superpowers/specs/`) — zero `origin=donchitos` rows remain in `provenance.tsv`, and no
Claude-Code-Game-Studios content ships in this toolkit today. This section and its license text
below are retained because the work was derived from Donchitos historically; that is a standing
obligation regardless of whether the derived files still exist. Upstream, the commands were
"skills" at `.claude/skills/<name>/SKILL.md` and the templates lived under
`.claude/docs/templates/`; `provenance-skip.tsv` records the original path and removal reason for
each.

Donchitos's files were reformatted to this toolkit's conventions, scoped to Unity 6 / PC-console, and
trimmed of the heavy multi-gate production pipeline — a thin slice of a much larger project, roughly
8 of its 49 agents and 9 of its 73 commands, before that slice was itself removed. See
`MERGE-NOTES.md` for the full delta.

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
`com.coplaydev.unity-mcp`). Our `.mcp.json` points at it on `http://localhost:8080/mcp`,
and the `unity-mcp-patterns` skill documents its `snake_case` tools (`manage_scene`,
`manage_gameobject`, `create_script`, `validate_script`, `read_console`, `batch_execute`).

**No CoplayDev code is included here.** `MCP-SETUP.md` documents how to install and verify it; the
open-source bridge needs no API key (that is Coplay's separate commercial product). `install.sh
--with-mcp` will add the package to your `Packages/manifest.json`.

---

## 4. Superpowers — adapted (attribution required)

- **Repository:** https://github.com/obra/superpowers
- **Author:** Jesse Vincent
- **Adapted at:** 6.2.0 — commit `3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9`
- **License:** MIT

**What this section used to say, and when that stopped being true.** Until 2026-08-10 it recorded
Superpowers as an influence and nothing more: the chain design (skills that name the next skill, so
a process surface is chosen before code is written) and two skill names had been taken; the skills
that existed then had had their wording measured against their Superpowers counterparts and found to
be ours; and no license text was reproduced. That was an accurate account of the repository as it
stood, and it is kept here as history rather than deleted.

**On 2026-08-10 the process chain was rebuilt and three skills were adapted at the expression
level** — structure, step sequence and, in places, wording. MIT covers expression, so from that date
the obligation exists. `.claude/NOTICE.md` §3 discharges it in the copy installed into user projects;
this section is the repository's own record of the same facts.

### Adapted surfaces

| File in this repo | Adapted from Superpowers 6.2.0 | How `provenance.tsv` records it |
|---|---|---|
| `.claude/skills/unity-brainstorming/SKILL.md` | `skills/brainstorming/SKILL.md` | `origin=ecu`, `status=modified` — its lineage begins at ECU's `deep-interview` and ECU's material survives in it, so the origin column stays with the first upstream and the Superpowers adaptation is recorded in the row's note |
| `.claude/skills/unity-planning/SKILL.md` | `skills/writing-plans/SKILL.md` | `origin=superpowers`, `status=modified` |
| `.claude/skills/unity-execution/SKILL.md` | `skills/executing-plans/SKILL.md` | `origin=superpowers`, `status=modified` |

The manifest is the per-file record; that table is derived from it, and
`tests/test-provenance-origins.sh` re-derives the set on every run and fails if the two disagree in
either direction. A future adapted surface left out of these documents fails there.

**The similarity figures this section used to quote are withdrawn, not re-measured.** They described
a state that no longer holds. A fresh number would be correct on the day it was taken and would rot
the same way, and this document has already been bitten by numbers in prose that nothing re-derives
— see the paragraphs at the top of this file.

**The Superpowers pin is a record, not a verified fact.** `scripts/check-provenance.sh` compares
checksums only for `status=verbatim` rows, and its `--online` pass filters on `origin=ecu` as well.
Every row above is `status=modified`, so no code path in this repository verifies the Superpowers
pin or those rows' upstream paths. The version and commit are maintained by hand, and the checksum
machinery next door should not be read as covering them.

### Influence, not expression

The surfaces below owe Superpowers something short of expression, and keep `origin=original`:

- `.claude/skills/subagent-driven-implementation/` — the shape of the loop (a fresh implementer per
  task, a review gate between tasks) comes from Superpowers' `subagent-driven-development`. The
  wording is ours, as are the Unity rules layered on it: no parallel implementers against one
  Editor, console-clean as a completion gate, manual Editor steps as a first-class task outcome.
- `.claude/skills/systematic-debugging/` and `.claude/skills/verification-before-completion/` —
  the names, and nothing else.

They are recorded here for completeness and are not part of the obligation above.

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

---

## Everything else

Files marked `origin=original` in `provenance.tsv` — `.claude/rules/pc-console.md`, the installer,
the provenance tooling, the tests we added, and this documentation — are original to
Kinglet Pioneer: MIT, Copyright (c) 2026 OmerZeyveli. See `LICENSE`.
