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
majority, not a property of the whole — it was the un-audited *mostly* that let a
second unguarded copy of `install.sh`'s command-body line count sit here while the
guarded copy moved. **The selection is large enough that it is not written down as a
number anywhere.** Derive it:

```bash
awk '/^DC[TW]_CLAIMS="/{f=1} f{print} f&&/"$/{f=0}' tests/test-derived-counts.sh \
  | cut -f1 | grep '^docs/research/codex-client/' | sort | uniq -c
```

A total in this paragraph would be a live figure inside the swept directory, with no
row watching it and no way for the next reader to tell whether it had kept up — the
exact object this whole section exists to eliminate, one paragraph above the list of
what it eliminated. **This file still holds none of the selected figures**, which is
the one place *overwhelmingly* was too weak rather than too strong.

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

### The instruments, because a coverage claim is a claim about a search

**Round 1's selection was produced by a digit sweep alone, and it under-selected by
eight figures** — second copies of the very figures it guarded, plus one
(`AGENTS.md, tracked, N lines`) with no guarded copy anywhere. Five were falsified at
once with the full suite still reading `Failed: 0`. The instrument that would have
found four of the eight is the word-numeral arm, which the same round named as *the*
arm three earlier rounds had never run — and then ran on `CONTRIBUTING.md` rather
than on its own subject. So the instruments are named here, and any future coverage
claim over this directory must name its own:

| Arm | Finds | Why it is separate |
|---|---|---|
| **A · digits** | `12`, `**3**`, `` `16` `` | must tolerate markdown emphasis and backticks around the digits — a pattern demanding a space after them misses the dominant spelling here |
| **B · word numerals** | *twelve*, *sixteen*, *seven* | invisible to A, and invisible to every claim row in `tests/test-derived-counts.sh` except the word-numeral table, because those patterns are `[0-9]+` and their value check harvests digits |
| **C · derivation commands** | `… \| wc -l   # N` | carries no noun at all, so neither A nor B reaches it |

**Positive control, and it is not optional.** The union must recover every figure
already selected; run against the pre-existing selection it returned all of them, and
it caught three of its own recall failures on the way there — a noun list of whole
words that could not reach *registered*, a gap expression that could not span two
consecutive tokens, and the emphasis problem above. Each was a miss the control found
and no reader would have.

**AND THREE ARMS THAT AGREE ARE STILL ONE SEARCH WHEN THEY SHARE A NARROWING STEP.**
All three above select a **span**: A and B narrow by a noun list, C by a command
shape. A span is not a sentence — so **none of the three can see a second numeral
sharing a sentence with one they already selected.** That is a structural blind spot,
not a tuning problem, and adding a fourth span-selecting arm would not touch it.

It was found by an instrument with a different narrowing step entirely: take the
sentence around every *already-guarded* match and report every numeral in it the row
does not cover — arity-keyed rather than noun-keyed. Four live figures came out, and
the cleanest is `README.md`'s *"Five of the eight agents narrow their own tools"*,
where the **total** was guarded and the **partition beside it in the same sentence**
was not, by the same commit, at the same site. All four are rows now, and the
partition and its total are one row with two numerals — which is the shape this whole
paragraph argues for.

**This is recorded, not built.** Two instruments would close it — an arity-keyed pass
over every guarded row's sentence, and a value-keyed pass whose only narrowing step is
the value itself — and both are real designs with real costs, not a fix-round
addition. A reader who wants to claim this directory is swept needs one of them; a
reader who wants to add a row does not. **What is not acceptable is a coverage claim
that names three span-selecting arms and calls that a search.**

**What it selected.** Values are written as `N` here on purpose: this file is inside
the swept directory, and a table that transcribed the guarded numbers would be a
fresh set of unguarded copies of exactly the figures below it. Every row below is
carried in `tests/test-derived-counts.sh`, and every one is a sentence that already
tells the reader to derive rather than trust it:

| Site | Figure |
|---|---|
| `findings.md` § *Hooks* | `Kinglet ships N hooks`, and `all N registered` — two figures, one sentence |
| `findings.md` § *Skills* | `Kinglet ships N skills` |
| `findings.md` § *Rules and AGENTS.md* | `Kinglet ships N rules` |
| `findings.md` § *Commands* | `Kinglet ships N commands` |
| `findings.md` § *Agents* | `Kinglet ships N agents` |
| `findings.md` § stranded machinery | the `src/catalog` file count, the `tools/kinglet_build` Python-module count, the `adapters/*/profile.json` count — each in the code block **and** restated in the table beside it |
| `codex-facts.md` § *Hooks* and § *matcher aliases* | the hook total at **three** sites — `N of Kinglet's M hooks are PostToolUse`, `the remaining N of Kinglet's M hooks`, and `covering N of its M hook entries` — with every partition derived as well as the total, because guarding a total and leaving its partition unguarded is how one sentence becomes internally inconsistent and stays green. It read *"two sites"* until this was re-derived; the third is in a different section and a per-section reading missed it |
| `findings.md`, word-numeral sites | the registered-hook total spelled *twelve* at four sites, the advisory-hook count, the argument-taking command count and its complement, the spine-rule count and the non-negotiable-section count, the agent count, the skill count at two further sites, `AGENTS.md`'s own line count |
| `codex-facts.md`, word-numeral sites | the argument-taking command count, the registered-event count, the tool-name matcher count and the entries it covers, the advisory-hook count, the spine-rule count |
| `CLAUDE.md`, `README.md`, `.claude/commands/unity-doctor.md` | the spine-rule count (twice), the agent count, the spine-rule count again — **outside this directory**, found by the same word-numeral arm and guarded by the same table, because the class is not a property of these three documents |

**What it excluded, and why, so the next reader is deciding rather than
rediscovering:**

- Every probe reading, every `<replica>` table, every `NAME.meta.json` quotation and
  every schema-bundle count — **L1**. This is the majority of the numerals here and
  it is what the directory exists to hold.
- `findings.md`'s *"drops 7 of 9 commands"*, `README.md`'s *"drops seven of the nine
  commands"*, `codex-facts.md`'s *"16 skills + 2 commands-as-skills"* and their kin —
  **L1**, on the coincidence rule above. The denominator is a tree figure; the
  sentence is a measurement of a run. The word-numeral spelling of the same sentence
  is excluded for the same reason as the digit one, which is the test that the
  criterion is being applied rather than the alphabet.
- `findings.md`'s probe-result tables — *"discovers all 16"*, *"reports 18 at repo
  scope"*, *"`.claude/hooks/` | 0 | **0**"* — **L2**: the column header is a probe.
- The one derivation command that counts the **replica** rather than this tree
  (`… "$EV"/skillrig/.codex/agents/*.toml | wc -l`) — **L1**. Arm C found it and the
  criterion rejected it, which is the arm's negative direction working.
- Every *"it read N until &lt;date&gt;"* correction — **L3**. There are several, and each
  one is the record of a figure that moved.
- `findings.md`'s *"`.claude/skills/` and `.claude/commands/` carry **0** references
  of this shape"* — passes all three, and is **still deliberately not guarded**: the
  row would assert `0 == 0` over a sweep the guard would have to re-implement, which is
  the vacuity shape `docs/ANTI-VACUITY.md`'s C4 excludes unless a floor is added
  under it. Excluded on cost and shape, not on the criterion — the one place those
  come apart, so it is named rather than folded into the list above. **Its companion
  in the same sentence — the skill-tool reference count, stated twice in that row — IS now
  guarded**, and the ruling is that the `0 == 0` exclusion
  does not extend to it: a positive count with a one-line derivation
  (`grep -o '\`Skill\` tool' .claude/agents/*.md | grep -c .`) is not the shape C4
  excludes. One sentence, two numerals, two different rulings — which is the arity
  blind spot above, this time with both halves decided rather than one overlooked.
