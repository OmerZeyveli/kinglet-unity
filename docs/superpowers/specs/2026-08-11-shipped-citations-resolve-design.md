# Every Citation a Shipped Surface Makes Must Resolve — Design

*2026-08-11. Branch `pioneer/process-chain`. Approved by the owner before this file was written.*

## The problem, measured

A surface that ships into a user's Unity project can only cite what that user has. Eight section
markers in three shipped skills abbreviate a citation to a document that does not ship, and eight
more paths name files `install.sh` deliberately does not copy. One of them is a **rule** that
instructs the reader to inspect a test file and report a regression.

> **Corrected 2026-08-12, after Task 1.** This paragraph originally read "eight citations in four
> shipped skills point at `sourced-incidents.md`", and the section below claimed the markers
> resolved to nothing. Both halves were wrong. It is **three** skills, not four — the spec said four
> while listing three. And the numbers **do** resolve, against `docs/research/pioneer/field-notes.md`,
> which is tracked, 172 KB, and carries `## 75.` through `## 86.` as real headings. Only the
> *filename* `sourced-incidents.md`, named once at `urp-pipeline:363`, has never existed.
>
> The action is unchanged for seven of the eight, because `docs/` is not in the installed payload and
> the marker fails for an installed reader whatever it resolves to here. **D3 was derived from the
> wrong half and is withdrawn below.** Found by Task 1's implementer, confirmed by the controller
> against the file itself. The wrong text is corrected in place rather than silently replaced,
> because a spec that quietly rewrites its own premise teaches the next reader to trust it less.

### The `§N` class — markers that resolve only for someone holding this repository

```
.claude/skills/verification-before-completion/SKILL.md   §80  §84  §86  §82
.claude/skills/systematic-debugging/SKILL.md             §77  §75  §82
.claude/skills/urp-pipeline/SKILL.md                     §82 in `sourced-incidents.md`
```

Eight markers across three files. `urp-pipeline:363` names a target file; the other seven are bare
section numbers with no antecedent in anything that ships.

Two separate facts, which the first draft of this spec conflated:

- **The filename is dead.** `sourced-incidents.md` is absent from the working tree, from
  `provenance.tsv`, and from `provenance-skip.tsv`, and
  `git log --all --diff-filter=D -- '*sourced-incidents*'` returns nothing — it was never deleted,
  because it never existed. Exactly one citation names it.
- **The numbers are live.** All six distinct numbers — 75, 77, 80, 82, 84, 86 — are headings in
  `docs/research/pioneer/field-notes.md`, tracked and 172441 bytes. `## 75. You can verify an MCP
  server without restarting the session`, and so on.

`docs/` is not in the installed payload, so the distinction changes the *explanation* and not the
*action*: a reader with only the installed project cannot follow `§80` either way. What it does
change is D3, below, which was reasoned from the dead half.

It also reclassifies the finding. This is not a separate defect class from the paths in the next
section — it is the same one, abbreviated. A `§N` marker is a citation to a repository-only document
with the document's name left out. One rule covers both, which is why the guard has two rules rather
than two guards.

A ninth match, `NOTICE.md:25`'s `§3`, refers to a section of `NOTICE.md` itself. It resolves and is
not in scope. Four further `§Heading` cross-references in `state-machine` and `save-system` name
headings in `architecture.md` and `unity-specifics.md`, both of which ship — they resolve for an
installed reader and are correctly untouched.

`systematic-debugging:39` is the odd one of the eight: its entire Source cell is the string `§75`,
with no prose. That is what made the first draft conclude nothing was recoverable. Field note 75 is
substantial and is precisely that row's incident, so the cell is filled from it rather than emptied.

### The path class — files `install.sh` does not copy

`install.sh`'s `PAYLOAD_FILES` assignment derives the payload as every file under `.claude/` except
`state/`. Its `for group in scripts` copy loop then copies `scripts/*.sh` into `.claude/scripts/`,
excluding exactly one file, `check-provenance.sh`. `tests/` is copied by nothing; the comment block
that opens *"Validation scripts ship alongside the payload. The test suite does not."* — immediately
above that loop — says so explicitly and adds that an installed `.claude/tests/` left by an older
version is **pruned**.

> **Cited by anchor, not by line — corrected 2026-08-12.** This paragraph read `install.sh:175`,
> `:379`, `:384` and `:370-378`. Task 3 of this wave inserted 29 lines into `install.sh`'s dry-run
> block, above every one of them, and all but `:175` went stale; the fix round that repaired them
> moved them again by 11.
> Measured on 2026-08-12 after that round: `PAYLOAD_FILES` at `:175`, the copy loop at `:417`, the
> exclusion at `:423`, the comment block at `:385-416`. Those numbers are a snapshot, not the
> citation — `grep -n 'PAYLOAD_FILES=\|for group in scripts' install.sh` is.

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

**Rejected: shipping the source document so the markers resolve.** The document exists — it is
`docs/research/pioneer/field-notes.md` — so this was a live option, not a hypothetical. It loses on
two counts. It is 172 KB of internal research written for maintainers of this repository, and adding
it to the payload puts that in every user's project to satisfy eight table cells. And its numbering
is positional: a note inserted at 74 renumbers everything after it, so every citation would rot
silently the next time the document grew. The prose in each Source cell is the durable form of the
same evidence.

### D3 — **Withdrawn.** `systematic-debugging:39`'s cell is filled from field note 75, not emptied

The original ruling read: *"It has no prose to keep and no incident to recover; `86db3fd` created it
bare… A single empty cell in a table where every other row carries measured evidence is itself
informative: it marks that row as reasoning rather than measurement."*

**Every load-bearing clause of that is false.** Field note 75 exists, is substantial, and is exactly
that row's incident — its title, *"You can verify an MCP server without restarting the session"*,
restates the Reality cell it sits beside. The row is measurement, not reasoning. `git log --all
-S'§75'` returns four commits, not the one the first draft reported.

The cell carries a compressed statement of the measured incident, in the same shape as its
neighbours: no marker, no path, no URL, standing on its own for a reader who has only the installed
project. What earns its place is the concrete part — the server is reachable over HTTP independently
of the session's tool list, and a probe against it returns the live tool set rather than a yes/no.

**The general lesson, which is why this is corrected rather than deleted:** the first draft measured
two things correctly (`sourced-incidents.md` never existed; `§75`'s cell was bare) and drew a
conclusion neither supported. An absent *filename* is not an absent *referent*. A spec about
citations that fail to resolve mis-resolved its own.

### D4 — The guard derives its payload; it does not hardcode one

`tests/test-shipped-citations.sh` computes the installed set the same way `install.sh`'s
`PAYLOAD_FILES` assignment and its `for group in scripts` copy loop do: every file under `.claude/`
except `state/`, plus `scripts/*.sh` less `check-provenance.sh`. A hardcoded list would go stale the
first time the payload changes, which is the failure mode this repository has recorded three times.

D4 named those two by line (`install.sh:175` and `:379-390`) until 2026-08-12, and the second went
stale inside this wave — the derivation was rot-proof and its *citation* was not, which is the same
defect one level up. Both are named by anchor now, here and in the guard's own comment.

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
7. Every surface that states the fork's threshold states the **same** one, verbatim — and no surface
   anywhere carries the retired looser form.

   > **Corrected 2026-08-12, after Task 4.** This read "No two surfaces state the fork's threshold",
   > which contradicts D9's own text four screens up: *"Both descriptions carry the same phrase
   > afterwards, verbatim, and a guard asserts they do."* D9 is right and the criterion was wrong —
   > and wrong on its facts as well as its logic, because **three** places state the threshold, not
   > two: both `description:` fields and `unity-execution`'s body at `:10-11`. The defect was never
   > that the threshold is stated more than once; it was that the statements **disagreed**.

## Out of scope, recorded

- `NOTICE.md`'s URL-bearing citations. They resolve; there is nothing to fix.
- The surface criterion applied to hooks and `scripts/`.
- The unguarded closing `---` frontmatter fence across all 16 skills.
- P1 (Ambiguity Score calibration against the generated block) and P3 (routing precedence between
  `unity-brainstorming`'s unconditional trigger and `/unity-ui` / `/unity-scene`). Both are product
  decisions, deferred by the owner to their own round after this one.

### Four things rule 2 cannot see, measured during Task 2 and left standing

Every one is latent today — no shipped surface currently trips it — and every one is a consequence
of the frozen token expression the Risks section names. They are written down because a guard's
silence is only as wide as what it reads, and an unrecorded blind spot reads as coverage.

- **Command-form citations evade it entirely.** ``Run `bash tests/test-no-mobile.sh` to check`` leaves
  the guard green: the expression cannot match a path inside a multi-word backtick span. This is the
  most idiomatic way to write the exact citation this wave spent eight fixes removing, and it is the
  sharpest of the four.
- **The `.claude/*` case arm is unreachable.** The expression requires `[A-Za-z0-9_]` as the first
  character, so no token beginning with `.` is ever produced. 56 backticked `.claude/…` citations in
  shipped Markdown are invisible to rule 2. Harmless while the payload *is* `.claude/**` less
  `state/`, but the arm reads as coverage that does not exist.
- **The URL escape is narrowed, not closed.** Any URL whose text ends `/<token>` clears the citation
  regardless of where it points — the property is basename-suffix equality, not resolution. D5 calls
  text-matching what "keeps it from being a loophole"; that is accurate for the URLs this repository
  carries and is not a general guarantee.
- **`scripts/<x>.sh` clears against a payload entry at a different path.** The installed file is
  under `.claude/scripts/`, so the citation as written does not literally resolve for a reader. No
  shipped Markdown cites that form today.

**And one thing outside the guard by construction:** `.claude/UPSTREAM` ships and names four
repository-only files — `provenance.tsv`, `provenance-skip.tsv`, `MERGE-NOTES.md`,
`check-provenance.sh`. Both rules scan `find .claude -name '*.md'`, so a non-Markdown surface is out
of reach. D1's principle covers it; this guard does not.

### One class the guard will never cover, closed by hand instead

**A revision of this repository cited in a shipped surface** is exactly as unfollowable as a path
that does not ship, and rule 2 cannot see it — a SHA is not a path. Task 2 removed the last two by
hand: `git log 0f772a4..HEAD` and a bare `2b543f2`.

The discriminator matters, because a blind sweep would have done damage. `bb28ccb`, `984023d` and
`3dcbd5c` also appear in `NOTICE.md` and are **correctly kept**: `git cat-file -t` reports them as
not objects in this repository — they are upstream pins — and each sits on a row carrying that
upstream's repository URL, so a reader follows the link and resolves the SHA where it lives. That is
D1's test passing, in a shape rule 2 does not implement. Deleting them would have broken the MIT
attribution this branch spent Task 7 of the previous wave discharging.

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
