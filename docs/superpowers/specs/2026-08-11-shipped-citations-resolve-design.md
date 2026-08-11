# Every Citation a Shipped Surface Makes Must Resolve — Design

*2026-08-11. Branch `pioneer/process-chain`. Approved by the owner before this file was written.*

## The problem, measured

A surface that ships into a user's Unity project can only cite what that user has. Eight citations
in four shipped skills point at `sourced-incidents.md`, and seven more paths point at files
`install.sh` deliberately does not copy. One of them is a **rule** that instructs the reader to
inspect a test file and report a regression.

### The `§N` class — a document that has never existed

```
.claude/skills/verification-before-completion/SKILL.md   §80  §84  §86  §82
.claude/skills/systematic-debugging/SKILL.md             §77  §75  §82
.claude/skills/urp-pipeline/SKILL.md                     §82 in `sourced-incidents.md`
```

Eight citations. `urp-pipeline:363` names the target file; the other seven are bare section numbers
with no antecedent anywhere in the tree.

`sourced-incidents.md` is absent from the working tree, from `provenance.tsv`, and from
`provenance-skip.tsv`. `git log --all --diff-filter=D -- '*sourced-incidents*'` returns nothing — it
was never deleted, because **it never existed**. These citations were born pointing at nothing.

A ninth match, `NOTICE.md:25`'s `§3`, refers to a section of `NOTICE.md` itself. It resolves and is
not in scope.

`systematic-debugging:39` is the worst of the eight: its entire Source cell is the string `§75`.
There is no prose. `git log --all -S'§75'` returns exactly one commit — `86db3fd`, the commit that
introduced the line. Nothing was lost; nothing was ever there.

### The path class — files `install.sh` does not copy

`install.sh:175` derives the payload as every file under `.claude/` except `state/`. `install.sh:379`
then copies `scripts/*.sh` into `.claude/scripts/`, and `:384` excludes exactly one file,
`check-provenance.sh`. `tests/` is copied by nothing; the comment at `:370-378` says so explicitly and
adds that an installed `.claude/tests/` left by an older version is **pruned**.

Against that payload, seven live citations do not resolve:

| Site | Cites | Why it is wrong |
|---|---|---|
| `.claude/rules/pc-console.md:43` | `tests/test-no-mobile.sh` | A shipped **rule** telling the reader "that test has regressed; treat it as a bug and report it" |
| `.claude/rules/pc-console.md:6` | `provenance-skip.tsv` | Unframed "see" |
| `.claude/skills/verification-before-completion/SKILL.md:38` | `tests/test-surface-references.sh` | Evidence the reader cannot reach |
| `.claude/skills/verification-before-completion/SKILL.md:39` | `tests/test-bash32-compat.sh`, `install.sh` | Same |
| `.claude/NOTICE.md:49` | `tests/test-provenance-origins.sh` | A contributor instruction resting on a test; its audience is by definition in an installed project |
| `.claude/NOTICE.md:149` | `scripts/check-provenance.sh` | The one script the installer explicitly withholds |
| `.claude/NOTICE.md:197` | `CREDITS.md` | Framed as the toolkit repository's, but with no URL — unlike `:12`, which does it correctly |

### Three that no citation guard can see

- **`install.sh:257` misreports the installer to the person deciding whether to install.** The
  dry-run prints `scripts/ and tests/ into .claude/`. The real run ships `scripts/` only, and prunes
  an existing `.claude/tests/`. The dry-run promises a directory the real run removes.
- **The fork's two descriptions disagree on the same boundary.** `unity-execution` says prefer
  `subagent-driven-implementation` when the plan has "more than one **substantial** task";
  `subagent-driven-implementation` says prefer itself when the plan has "more than one task". A plan
  with two small tasks matches both.
- **`docs/GETTING-STARTED.md:162` sends a new user to the one chain-exempt surface.** "try
  `/unity-review` on existing code or `/unity-prototype` to see the full pipeline in action" —
  `/unity-prototype` is the single documented exemption from the chain (`unity-brainstorming`'s
  boundary section). Line 157 of the same table names `unity-brainstorming` as the chain's entry, so
  the file contradicts itself five lines apart.

## Decisions

### D1 — A shipped surface cites only what resolves in an installed project

Not "no toolkit-repository citation". The test is whether the reader can follow the pointer. Two
things satisfy it: the path exists in the installed payload, or an accompanying URL resolves it.

`NOTICE.md:12` already does the second, deliberately:

```
lives in the toolkit repository as `provenance.tsv`, not here:
> https://github.com/OmerZeyveli/kinglet-unity/blob/main/provenance.tsv
```

That is not a convention the guard must learn to recognise — the pointer genuinely resolves. A prose
frame alone ("the toolkit repository's `CREDITS.md`") does not, and `:197` is fixed by adding the URL
rather than by deleting the reference.

### D2 — `§N` is removed, and the prose that follows it is the evidence

Seven of the eight sites are pure deletions of a marker. The Source cell already carries the whole
incident — `§80 — a guard correctly refused a git add of engine-settings YAML; …` loses four
characters and reads identically.

**Rejected: writing and shipping `sourced-incidents.md`.** The only incidents with content are the
six already written out in full in the Source columns that cite them. A document would be a second
definition of the same text — the precise defect this branch exists to remove. Doing it inside this
wave would be self-refuting.

### D3 — `systematic-debugging:39`'s Source cell becomes `—`

It has no prose to keep and no incident to recover; `86db3fd` created it bare. No incident will be
invented to fill it.

A single empty cell in a table where every other row carries measured evidence is itself
informative: it marks that row as reasoning rather than measurement. The Reality column already
carries the full argument — the bridge's health is checkable over HTTP independently of whether this
session can call its tools, and those two states have different remedies.

### D4 — The guard derives its payload; it does not hardcode one

`tests/test-shipped-citations.sh` computes the installed set the same way `install.sh:175` and
`:379-390` do: every file under `.claude/` except `state/`, plus `scripts/*.sh` less
`check-provenance.sh`. A hardcoded list would go stale the first time the payload changes, which is
the failure mode this repository has recorded three times.

### D5 — The guard has exactly two rules

1. **No `§N` in any shipped `.md`**, except `NOTICE.md`'s own `§3` — a section of the file it appears
   in.
2. **No backticked token that names a real file in this repository and is absent from the payload**,
   unless the same file carries a URL whose own text ends with that path.

The escape is scoped to the file, not to the block. `NOTICE.md` is one document: a reader who meets
"linked at the top of this file" scrolls up and finds the link. Scoping it to the block would force a
URL into `:140`'s table header — `| How `provenance.tsv` records it |` — which is naming the manifest,
not pointing at it.

The escape matches on the URL's **text**, not its presence, and that is what keeps it from being a
loophole: `NOTICE.md` carries five URLs, and none of them ends in `test-provenance-origins.sh`, so
`:49` still fires.

Rule 2 resolves against the repository tree, which is what keeps it from firing on user-project
paths: `docs/features/<slug>/design.md` names no file here, so it is never flagged, while
`tests/test-no-mobile.sh` names one and is not shipped.

### D6 — The allow-list is three entries, each a measured name collision

The naive form of rule 2 flags twelve tokens. Three of them are not citations of repository-only
artifacts at all:

| Token | Why it is allowed |
|---|---|
| `CLAUDE.md` | The user's own file, generated by `/unity-init`. Cited in 26 shipped files, correctly. |
| `LICENSE` | In `NOTICE.md` this is always an **upstream's** licence — "everything-claude-unity's `LICENSE`". A root `LICENSE` here caused the match. |
| `VERSION` | `NOTICE.md:41` lists `.claude/VERSION`, which ships. A root `VERSION` here caused the match. |

Each entry carries its reason in the test file. The list is expected to stay at three; growth is a
signal to re-examine rule 2, not to append.

### D7 — The remaining nine tokens are fixed, not allow-listed

`CREDITS.md`, `install.sh`, `provenance.tsv`, `provenance-skip.tsv`, `scripts/check-provenance.sh`,
and four `tests/*.sh`. Every one is either deleted with its prose kept, reframed, or given a URL.

`provenance.tsv` is **not** among them. It appears at four sites in `NOTICE.md` — `:12`, `:29`, `:135`
and `:140` — and rule 2's file-scoped escape clears all four from the URL `:12` already carries. No
edit is needed at any of them, and none was made.

Run against the rule as specified, the flag set is exactly eight, in three files:

```
CREDITS.md                         .claude/NOTICE.md
scripts/check-provenance.sh        .claude/NOTICE.md
tests/test-provenance-origins.sh   .claude/NOTICE.md
provenance-skip.tsv                .claude/rules/pc-console.md
tests/test-no-mobile.sh            .claude/rules/pc-console.md
install.sh                         .claude/skills/verification-before-completion/SKILL.md
tests/test-bash32-compat.sh        .claude/skills/verification-before-completion/SKILL.md
tests/test-surface-references.sh   .claude/skills/verification-before-completion/SKILL.md
```

`CREDITS.md` is fixed by adding the URL, which then clears it by the same rule that flagged it.

### D8 — `install.sh`'s dry-run states what the real run does

`:257` becomes `scripts/ into .claude/`. The dry-run is what a user reads before consenting; it does
not get to describe a different program.

### D9 — The fork's boundary is stated once, in one place

The threshold's job is selection, and selection happens by reading `description:` fields — so both
descriptions must state it, and they must state the **same** one.

**"More than one substantial task" is the surviving form; the bare "more than one task" goes.**
`unity-execution` exists for plans small enough that a fresh implementer per task would cost more
than it catches, and a two-task plan of trivial tasks is exactly that — the bare form routes it to
the expensive branch against the reason the branch exists. Both descriptions carry the same phrase
afterwards, verbatim, and a guard asserts they do.

### D10 — `GETTING-STARTED.md` sends a new user to the chain

`:162` names the chain's entry. `/unity-prototype` may still be offered — it is a real surface — but
never as "the full pipeline", which is the one thing it is not.

## Acceptance criteria

1. `bash tests/run-tests.sh` green, and its ANSI-stripped `--- test-*.sh ---` header count equals
   `ls tests/test-*.sh | wc -l`.
2. `bash scripts/check-provenance.sh` ends `provenance OK`, with rows for every file this wave adds.
3. `grep -rn '§[0-9]' .claude --include='*.md'` returns exactly one line: `NOTICE.md`'s `§3`.
4. The guard's flag set is **empty**. Before the fixes it is the eight rows listed under D7; each
   fix removes exactly one, and no row appears that is not on that list.
5. `tests/test-shipped-citations.sh` is mutation-proven on both rules and on the allow-list:
   - adding `§99` to any shipped skill → red;
   - adding `` `tests/anything.sh` `` to any shipped surface → red;
   - removing `CLAUDE.md` from the allow-list → red across 26 files, proving the guard reads what it
     claims to read.
6. `bash install.sh --dry-run` against a fixture prints no directory the real run does not create.
7. No two surfaces state the fork's threshold.

## Out of scope, recorded

- `NOTICE.md`'s URL-bearing citations. They resolve; there is nothing to fix.
- The surface criterion applied to hooks and `scripts/`.
- The unguarded closing `---` frontmatter fence across all 16 skills.
- P1 (Ambiguity Score calibration against the generated block) and P3 (routing precedence between
  `unity-brainstorming`'s unconditional trigger and `/unity-ui` / `/unity-scene`). Both are product
  decisions, deferred by the owner to their own round after this one.

## Risks

**The guard's token regex is the whole construction.** `` `[A-Za-z0-9_][A-Za-z0-9_./-]*` `` was the
form used for the measurement above, and it is what produced the twelve-token set the allow-list is
calibrated against. A different regex produces a different set and silently invalidates D6. The plan
freezes the expression in the test and asserts the derived set, not just its emptiness after
filtering.

**Rule 2 weakens as files are deleted.** A citation to a repository file that is later removed stops
resolving here and therefore stops being flagged. This is accepted: the `§N` rule covers the
cite-nothing case, and `tests/test-skill-discovery.sh` §6 covers skill paths. Broader
does-this-path-exist coverage belongs to the spin-out wave, where it can be built once for every
path form rather than twice.
