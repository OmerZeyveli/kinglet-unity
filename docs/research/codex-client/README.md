# Codex client evidence

Raw evidence for the 2026-08-15 wave that measured whether Kinglet's surfaces
cross to Codex CLI. The spec is
`docs/superpowers/specs/2026-08-15-codex-cli-second-client-design.md`.

## Pinned versions

| Thing | Version | Why pinned |
|---|---|---|
| `codex-cli` | 0.145.0 | 0.147.0 was available during the wave and was deliberately not taken. A hook-schema change between versions invalidates this evidence; the pin makes that detectable rather than silent. |
| Unity MCP bridge | CoplayDev unity-mcp, `http://127.0.0.1:8080/mcp` | Task 7 only. |

## Re-running a probe

```bash
bash scripts/codex-probe.sh --name <name> --prompt <prompt-file>
```

Each probe writes four files here: `NAME.jsonl` (the event stream),
`NAME.last.txt` (the final agent message), `NAME.stderr.txt`, and
`NAME.meta.json` (the exact invocation, the codex version, the exit code).

**Every probe's `NAME.stderr.txt` begins with `Reading additional input from
stdin...`, and it is not a warning.** The harness runs codex with stdin at
`/dev/null`, which is what stops `codex exec` blocking; measured on the first
live run, 2026-08-15, the message is printed whenever stdin is not a terminal —
codex then reads EOF and proceeds normally, exit 0. Read past it when looking
for real warnings. It is not filtered, because a harness that edits its own
evidence is worth less than one that explains it.

The first live run also confirmed the event-stream shape the plan recorded:
four line-delimited objects — `thread.started`, `turn.started`, an
`item.completed` whose `item.type` is `agent_message`, and `turn.completed`
carrying the token usage.

**The transcripts are not committed.** They are large, they are not
deterministic between runs, and committing them would make every re-measurement
a diff. What is committed is the verdict, in `findings.md` and
`codex-facts.md`, each carrying the command that produced it — so a reader
re-runs rather than trusts.

## What is measured where

- `codex-facts.md` — Codex's own capabilities. Every claim carries the command
  that established it. This file is what turns the spec's "inferred, NOT
  verified" list into measured or refuted.
- `findings.md` — Kinglet's surfaces under Codex: one verdict per surface
  class, the architecture decision, everything excluded, the machinery the
  decision strands, and the six silent-failure layers in one table.

## Two reading conventions, so a sweep over these files is not misread

**Angle brackets here are metavariables, not unfilled placeholders.** `<repo>`,
`<key>`, `<name>`, `<abs>`, `<dir>`, `<replica>` and their kin stand in for a path
or a hash the reader supplies; several are quoted verbatim out of Codex's own
response strings, where the brackets are Codex's. A sweep for `<…>` therefore
returns dozens of hits on a complete document. It was run to completion on
2026-08-16 and every hit triaged: the one genuine unfilled slot, a `'<prompt>'` in
`## Hooks`'s reproduction recipe, is filled.

**A number here is a dated measurement unless it is derived in place.** These are
records of what was true against `codex-cli 0.145.0` on 2026-08-15/16, and a guard
that silently updated them would destroy the record rather than protect it. Where a
figure comes from Kinglet's own tree rather than from a probe, the surrounding text
gives the command to re-derive it and tells you to. Two such figures had already
moved by the time the wave closed, both inside it: the command bodies' line count,
and the bash-4 census in `docs/ANTI-VACUITY.md`.

**This paragraph said "which is why nothing in `tests/` reads these two files" until
2026-08-17, and three separate guards falsified it.** `tests/test-codex-surface.sh`
reads `findings.md` **as its authority** (`SHIP_LIST=`), extracts `## Ship list`, and
reds if the file is missing, if that section is under 20 lines, or if an exclusion
heading is gone. `tests/test-derived-counts.sh` carries four claim rows over
`findings.md`. And `tests/test-codex-shim.sh` cites `codex-facts.md` as the source of
two of its own criteria. The sentence predated the first of those guards and nothing
re-read it; it was falsified again by a later commit, and then a third time, before
anyone re-read it. What the sentence was reaching for is true and is stated below as
a criterion instead — **a guard here must read only the live figures**, and the whole
of the work is saying which those are.

## Live and pinned — the criterion a guard over this directory must apply

Written before the set was selected. Every figure in these three documents is one or
the other, and *"overwhelmingly per-run measurements"* was the honest summary of the
majority, not a property of the whole: applying the criterion below finds **eleven
guardable figures, carried as fourteen claim rows, in two of the three files** — and
it was the un-audited *mostly* that let a second unguarded copy of `install.sh`'s
command-body line count sit here while the guarded copy moved. **This file holds
none of the eleven**, which is the one place *overwhelmingly* was too weak rather
than too strong.

A figure is **live**, and may be guarded, if and only if all three hold:

- **L1 · Subject.** It is computable today from this repository's tracked files
  alone — no `codex` binary, no `CODEX_HOME`, no replica, no evidence transcript.
  A figure about Codex's schema bundle, about the tree the importer wrote into a
  replica, or about what a probe printed fails L1 **even when its value happens to
  equal a tree count**. That coincidence is the trap: `codex-facts.md` records the
  importer writing *"all N files from `.claude/hooks/`"*, and N is also this tree's
  own hook-file count today — but the sentence is a measurement of a run, and
  re-deriving it would rewrite the record. (The value is deliberately not
  transcribed here; this file sits inside the swept directory, so quoting it would
  manufacture the very thing the criterion exists to find.)
- **L2 · Tense and binding.** The sentence asserts the figure of the present tree.
  Quoted output, a table whose header is a probe name or `<replica>`, or a clause
  naming `codex-cli 0.145.0` / a probe / *"measured &lt;date&gt;"* is **pinned by that
  binding**. ***"Re-derived &lt;date&gt;" does not pin*** — it is a freshness stamp on a
  live figure, and the command-body line count carries one and is guarded.
- **L3 · Repair direction.** Writing a re-derived value in would leave the
  surrounding sentence true. Where the sentence's point is that the value *was*
  different — a correction, an *"it read N until"*, a before/after — the figure is
  pinned history and a guard that updated it would destroy exactly what it was added
  to protect.

**What it selected.** Values are written as `N` here on purpose: this file is inside the swept
directory, and a table that transcribed the guarded numbers would be a fresh set of unguarded copies
of exactly the figures below it. All are carried as claim rows in
`tests/test-derived-counts.sh` and each one a sentence that already tells the reader
to derive rather than trust it. Eleven figures, fourteen rows — the counts differ
because three figures are stated twice in one section and one is stated at two
sites, and a table that reported only one of those numbers would be describing a
different set than the guard holds:

| Site | Figure |
|---|---|
| `findings.md` § *Hooks* | `Kinglet ships N hooks`, and `all N registered` — two figures, one sentence |
| `findings.md` § *Skills* | `Kinglet ships N skills` |
| `findings.md` § *Rules and AGENTS.md* | `Kinglet ships N rules` |
| `findings.md` § *Commands* | `Kinglet ships N commands` |
| `findings.md` § *Agents* | `Kinglet ships N agents` |
| `findings.md` § stranded machinery | the `src/catalog` file count, the `tools/kinglet_build` Python-module count, the `adapters/*/profile.json` count — each in the code block **and** restated in the table beside it |
| `codex-facts.md` § *Hooks* | the hook total at **two** sites — `N of Kinglet's M hooks are PostToolUse` and `the remaining N of Kinglet's M hooks` — with both partitions derived as well as the total, because guarding a total and leaving its partition unguarded is how one sentence becomes internally inconsistent and stays green |

**What it excluded, and why, so the next reader is deciding rather than
rediscovering:**

- Every probe reading, every `<replica>` table, every `NAME.meta.json` quotation and
  every schema-bundle count — **L1**. This is the majority of the numerals here and
  it is what the directory exists to hold.
- `findings.md`'s *"drops 7 of 9 commands"*, `codex-facts.md`'s *"16 skills + 2
  commands-as-skills"* and their kin — **L1**, on the coincidence rule above. The
  denominator is a tree figure; the sentence is a measurement of a run.
- Every *"it read N until &lt;date&gt;"* correction — **L3**. There are several, and each
  one is the record of a figure that moved.
- `findings.md`'s *"`.claude/skills/` and `.claude/commands/` carry **0** references
  of this shape"* — passes all three, and is **deliberately not guarded**: the row
  would assert `0 == 0` over a sweep the guard would have to re-implement, which is
  the vacuity shape `docs/ANTI-VACUITY.md`'s C4 excludes unless a floor is added
  under it. Excluded on cost and shape, not on the criterion — the one place those
  come apart, so it is named rather than folded into the list above.
