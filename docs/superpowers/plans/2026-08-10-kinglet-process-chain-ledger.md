# Ledger — plan: `docs/superpowers/plans/2026-08-10-kinglet-process-chain.md`

Spec: `docs/superpowers/specs/2026-08-10-kinglet-process-chain-design.md`

- **Branch:** `pioneer/process-chain`
- **Base commit (the whole-branch review diffs against this):** `7b18e630`
- **Loop starts from:** `40df066`
- **Gates:** `bash tests/run-tests.sh` (needs a timeout above 150000ms; the `--- test-*.sh ---`
  header count must equal `ls tests/test-*.sh | wc -l`) and `bash scripts/check-provenance.sh`
  (must end `provenance OK`).

## RESUME HERE — state for a session that has lost its context

**Tasks 1–6 are done and closed. The chain exists, the sequencers are gone, and the injected text is
a mandate rather than a summary.**

`unity-brainstorming` → `unity-planning` → the fork → `subagent-driven-implementation` or
`unity-execution`. Pool is **8 agents + 9 commands + 16 skills = 33**, exactly D7's arithmetic.
Nothing is dispatched.

**Task 7 is next** — the licence facts. It is the task with the sharpest external consequence:
`.claude/NOTICE.md` ships into **every installed project**, and since Task 2 it has carried a claim
that adaptation made false. Read the Task 5 and Task 2 deferred items before writing the brief —
`CREDITS.md` now contradicts **itself internally**, not merely upstream, and Task 7 is scheduled to
fix the staleness rather than the self-contradiction.

Suite is at **438 passing**, `provenance OK`, 541 manifest rows, 96 `rule=absent` enforced.
Reports under `.superpowers/sdd/2026-08-10-process-chain/`: `task-1-report.md` (rounds 0–3),
`task-1-round4-report.md`, `task-2-report.md`, `task-3-report.md`, `task-4-report.md`,
`task-5-report.md`.

**The cut-criterion gate on `unity-execution` was answered "ship it"**, and the argument is on the
record: the Deslop Pass's two restraining rules — a scope boundary and a default — are what an
unaided cleanup lacks, and folding into `subagent-driven-implementation` would force that skill's
`description:` generic, weakening selection for both branches. Review upheld the conclusion and
corrected the reasoning: the load-bearing content is **ECU's, transplanted**, not Kinglet's. The
surface still earns its place — the criterion asks what a surface *does*, not who wrote the words.

Read, before dispatching Task 2, in this order: *Standing facts*, *Interfaces produced so far*, and
*Ask the shape question early* — the last is why Task 1 cost four rounds and is the cheapest thing
here to reuse.

## Controller decisions, made at setup

1. **All eight tasks get a general implementer and a general reviewer, not `unity-coder` /
   `unity-reviewer`.** This is the toolkit repository, not a Unity project: there is no Editor, no
   MCP bridge, and no C#. Every task is bash, Markdown or TSV. The skill's own exception covers this
   — routing documentation and shell work to an agent built to drive the Unity Editor measures the
   dispatch rather than the task. Recorded here so the run stays readable.
2. **The brief for each task is that task's section in the plan, cited by heading** — not a separate
   brief file. `writing-plans` produced the plan specifically to be executed task by task, with full
   code blocks and no placeholders, and copying each section into a second file would create two
   definitions of the same requirement. That is the exact defect this wave exists to remove; doing it
   inside the wave would be self-refuting. A dispatch names the plan path and the task heading.
3. **The ledger is tracked, at `docs/superpowers/plans/…-ledger.md`.** This repo's earlier ledgers
   lived under the gitignored `.superpowers/sdd/`. The skill says "next to the plan", and spec D8
   puts design, plan and ledger in one directory precisely so the record survives the session. It
   therefore needs a `provenance.tsv` row, like any tracked file.

## Standing facts for every dispatch

Copy this section into every dispatch. A fresh subagent inherits none of it.

- **This is the Kinglet toolkit repository, not a Unity project.** There is no Unity Editor, no MCP
  bridge, no `read_console`, and no C#. An implementer reaching for `mcp__UnityMCP__*` is in the
  wrong repository and should stop and report.
- **Branch is `pioneer/process-chain`.** Never commit to `main`.
- **Both gates must pass before every commit** — the two commands above. The suite takes ~2m25s.
- **Bash 3.2 compatible.** No `declare -A` (bash 4), no `grep -oP` (GNU-only). macOS ships 3.2 and a
  macOS host pass is planned.
- **Never pipe into a reader that exits early.** Under `set -euo pipefail`, `head` **and `grep -q`**
  both exit on first match without draining stdin; the writer gets SIGPIPE and pipefail turns 141
  into a failure. It fires on large inputs and hides on small ones. Use a here-string:
  `grep -qF -- "$needle" <<< "$haystack"`. Three implementers in this repo called this a flake; it
  reproduces every time under CPU contention.
- **Validate an argument before `shift 2`** — `shift` fails under `set -u` before the error message
  prints, and the user gets a silent exit 1.
- **Two test idioms coexist and mixing them fails silently.** The runner does `( source "$file" )`.
  A *self-contained* file defines its own helpers and sets `set -euo pipefail`; `bash tests/<f>.sh`
  is valid. A *runner-provided* file uses the runner's `assert_contains` / `assert_eq` /
  `assert_file_exists` and `$REPO_DIR`, defines neither, and **exits 0 having asserted nothing** when
  run standalone. Run a runner-provided file through the runner and read its section.
- **`assert_eq` takes (expected, actual).** Some files define a local shadow with the opposite order
  — read the file before adding a call to it.
- **Every new tracked file needs a `provenance.tsv` row** or `check-provenance.sh` fails it as an
  orphan. A row whose file does not exist fails as a ghost.
- **Never hardcode a derived count** in `CLAUDE.md`, a test, or prose. Counts have gone stale twice.
- **Adding a vendored row has two gate-breaking side effects the plan does not mention. Both recur in
  Tasks 3 and 4.** Reported by Task 2's implementer; verified by the controller only to the extent
  that Task 2's suite is green with the fixes in place.
  1. **`tests/test-derived-counts.sh` reddens.** `CREDITS.md` and `README.md` quoted an
     **ECU-scoped** vendored split in phrasing the guard reads as **repo-wide** — the two were equal
     only while ECU was the only upstream, and `origin=superpowers` ends that. Expect to update the
     wording, not the number.
  2. **`baseline-regenerate` updates `migration/baseline-inventory.json` but not
     `tests/kinglet/test_baseline_inventory.py`'s hand-maintained constants** — three assertions go
     red while the tool prints success. Fold the constants into the baseline commit; they are one
     logical change with the JSON.
- **Sweep by insertion as well as by deletion — they find different things.** Every sweep before
  Task 6 deleted lines, which finds unguarded **content**. Inserting at every position finds
  unguarded **space**: places where nothing is asserted because nothing is there yet. Task 6's
  insertion sweep found twelve silent positions *between two table rows* — `UK_TAIL` discarded them,
  the row count stayed 11, and in Markdown a line there **ends the table**, so every route below it
  stops rendering while the guard reads eleven rows.

- **A sweep proves something only about the payload shapes it uses.** Task 6's first sweep used one
  generic marker and reported "zero silent at 65 positions". A marker that never matches `^\|` is
  *structurally incapable* of reaching a guard's pipe-shaped exclusions. Re-run with seven content
  shapes × 65 positions: 455 insertions, zero silent — and the eighth shape, a bare blank line, is
  silent at 26 positions **by design**, recorded because "zero silent" without that footnote is the
  same overclaim one size down.

- **A guess about shape is a costume anyone can wear.** Task 6's row guard excluded the header and
  delimiter by *what they look like* (`$2 !~ /^ *Situation *$/`, `$0 !~ /^\s*\|-/`). A twelfth row
  wearing either costume was invisible to the row count, the residue rule, the existence rule and the
  contiguity check at once. Two positions were worse than a smuggled row: displacing the real header
  makes **the table stop being a table in GFM** while the needle still matches and the count still
  reads eleven. Anchor by **position** — line 1 must *be* the header, line 2 must *be* the delimiter.

  The `assert_contains` forms were **deleted, not moved**: "does such a line exist anywhere" stays
  true exactly when a row has been inserted above the real header. An existence check satisfied by
  the mutation that breaks the thing is worse than no check.

- **Only the artifact ships.** Task 5's implementer read `unity-brainstorming`, wrote the accurate
  claim into its *report*, and then wrote a stronger, false version into the **payload file injected
  at session start**. Its own words: *"I read the file, wrote the accurate version in prose, then
  wrote a stronger false version into the artifact."* The reasoning being right is not evidence that
  the shipped sentence is. Check the artifact against the file, not against your understanding of it.

  The same defect twice over, because a rename does not carry a sentence's truth: `using-kinglet`
  said three skills carry a "the thought that means you are about to skip this" section. Renaming
  `deep-interview` kept the sentence grammatical and made it false — **and then the correction was
  false too**, because D2 removed the exemption *list*, not the section, which exists retitled at
  `unity-brainstorming:183`.

- **A guard can be narrowed by narrowing what it inspects, and every assertion about the inspection
  stays green.** Five routes were measured in Task 5, all with a real dead name planted behind the
  loss and the suite at exit 0: a second entry in a skip `case`; excluding `.claude/commands/*` or
  `.claude/agents/*`; narrowing `scripts/*` to `scripts/*.sh` (a `.py` script lives there **today**,
  so this reads as a tidy-up); replacing a glob with an explicit file list.

  The shape, in the implementer's words: **each narrows *what is inspected* while leaving *what is
  asserted about the inspection* untouched.** A file-count floor does not move; sentinels named by
  path still match. The fix that worked was to assert against **the set the loop actually read**,
  accumulated after the skip, rather than against the raw `git ls-files` output.

- **A comment asking for something is not a check for it.** Round 1 of Task 5 wrote *"The skip is one
  file and stays one file"* two blocks above a check that could not detect a second entry — written
  in the same edit that enforced the other half, by an implementer who had just quoted
  `test-derived-counts.sh`'s *"a warning is not a guard"*. Prose next to a guard reads as part of the
  guard and is not.

- **A check that fires on everything distinguishes nothing.** The controller deleted a skill's closing
  frontmatter fence, saw two failures, and concluded the fence was guarded. It was not: both failures
  came from `tests/kinglet/test_baseline_inventory.py`'s **sha256 tripwires**, which fire for any byte
  change to any tracked `.claude/**` file and know nothing about frontmatter — deleting a random prose
  line produces the same two. Committing the change and regenerating the baseline the way the normal
  workflow does gives `402 passed, exit 0`.

  **Before reading a red as evidence, ask whether the red is about the thing you changed.** A hash
  tripwire is reset by the very workflow every task in this plan performs.

- **A guard that skips is a guard that goes quiet where nobody is watching.** Task 4's ECU-derivation
  block skipped when the vendor blob was unreachable. In a `git clone --depth 1` the figure was set to
  `99 of ECU's 69` in **both** the manifest and `MERGE-NOTES.md`: `FAILCOUNT 0`, and
  `check-provenance.sh` still printed `provenance OK`. Ruled: **fail, do not skip** — a shallow
  checkout is not a supported test environment anywhere else in this suite.

- **Documenting a trap is not protection against it.** Task 4's implementer wrote a two-line
  `assert_contains` needle — the `grep -F` alternatives trap — **six lines below the comment
  documenting that trap in the same file**. Its own words, worth keeping.

- **Guard what `provenance.tsv` claims — that is the criterion, not "does this read as important".**
  Derived in Task 3's re-review and it unifies the two most expensive defects of this wave: Task 2's
  Critical (a note calling ECU text Kinglet's) and Task 3's Spec ❌ (a note listing a header the file
  did not carry). Neither is *loss of the idea*; both are **the manifest becoming a lie**, and
  `check-provenance.sh` **never reads the free-text `note` column** — so the only thing standing
  between a manifest claim and a silent falsehood is a guard on the content it claims.

  Task 3's live instance, measured: `provenance.tsv:555` claimed the `Files:`/`Interfaces:` blocks
  were carried, and deleting the whole 23-line template left the suite **27/27 green**. Four needles
  closed it. The rejected criterion — *"is there an upstream to restore from?"* — is reasonable and
  answers the wrong question.

- **`grep -F` treats a multi-line pattern as alternatives, not a block.** This has now bitten two
  different guards in this wave wearing different text: Task 1's here-doc pin (any surviving line
  satisfied it) and Task 3's three-line handoff assertion (same). Confirmed on both binaries here
  (GNU grep 3.11, ugrep 7.5.0). **Adding more needles does not fix it** — full-line needles still
  miss reordering. Compare the block character-for-character instead; Task 3 added a local
  `assert_same` that survived six vacuity probes (missing file, empty file, em-dash swap, backticks
  stripped, one trailing space, two-space indent).

- **Before recording transcribed text as original, sweep every line against the vendor commit.**
  Task 2 asserted the Deslop Pass was Kinglet-original; it is **ECU v1.5.0 verbatim**, and so are the
  Final Summary, the `max 3 iterations` bound and two verify-loop steps — 32 content lines in three
  blocks. The brief said it, the implementer expanded it, and neither asked. `check-provenance.sh`
  cannot catch this: one origin per row is the schema, so the `note` column is the only place a
  second upstream can live.

  The method, and it is one command rather than a judgement: dump the vendor commit
  (`git show 45eada9:<path>`) and test each non-blank line with `grep -qxF`. It turned two rounds of
  clause-guessing into a measured fact. **Tasks 3 and 4 both transcribe from
  `.claude/commands/unity-workflow.md` and the provenance of what they carry is unknown until swept.**

  Record a second upstream in this fixed, greppable form:
  `carries verbatim ecu 1.5.0 text from <path>: <what>`. It is convention, not enforced — nothing in
  `tests/` or `scripts/` reads it.

- **Do not write a causal claim about a shell option, runner semantic or tool flag you have not
  executed in this session.** Two mechanism claims were corrected in Task 2, both wrong, and neither
  was a knowledge failure — both generalised from a *neighbouring* fact with a shell one keystroke
  away, and both landed in a **comment**, the cheapest place to write one and the least likely to be
  challenged because nothing executes a comment.

  The implementer's own trigger, worth reusing verbatim: *"Am I naming a shell option, runner
  semantic, or tool flag whose behaviour I have not executed in this session?"* And its remedy,
  applied rather than proposed: **paste the probe transcript into the comment as its evidence** — you
  cannot cite a transcript you never ran without noticing you are inventing one, and it makes the
  omission greppable.

- **The plan's "add the provenance row, then regenerate the baseline" ordering is circular** and Task
  2 worked around it: the test reads `git ls-files` while the regenerator reads `git ls-tree`, so
  neither can be satisfied first in the working tree. Use the repo's established pattern —
  **commit, regenerate, commit** — rather than trying to satisfy both before the first commit.
- **Baseline regenerator:** `python3 -m tools.kinglet_build baseline-regenerate --anchor … ` — the
  entry point is the **package**; `python3 -m tools.kinglet_build.cli` silently no-ops with exit 0.
  Run `--dry-run` first, **use the tool's numbers rather than the plan's estimate**, and report a
  disagreement instead of tuning the flag until it passes. A categorised file counts twice — once in
  `full_claude_tree`, once in its category — and skills and commands are both categorised. Put the
  baseline update in its own commit.
- **Skills are flat**: `.claude/skills/<name>/SKILL.md`, one level, `name:` matching the directory,
  non-empty `description:`, and no `alwaysApply` / `globs` — both are inert Cursor keys that get read
  as guarantees.
- **One implementer at a time.** The Unity rationale does not apply here, but the shared working tree
  does: this repo has already had a controller's untracked probe file mistaken for a concurrent
  agent's leftovers.
- **Strip ANSI before counting suite headers.** `bash tests/run-tests.sh` **colours** the
  `--- test-*.sh ---` header, so the escape sequence sits between the line start and the text and
  `grep -c '^--- test-.*\.sh ---'` on raw output returns **0** on a completely healthy suite.
  Measured in Task 1 round 4; confirmed by the controller (raw 0, stripped 30, files 30). Use
  `sed 's/\x1b\[[0-9;]*m//g'` first.

  **This is worse than a broken check.** The count exists to catch the runner dying and reporting
  green — which has happened here, with 7 of 8 files never running. The unstripped form returns the
  exact signal of that catastrophe on every healthy run, so anyone following the instruction
  literally either panics or "fixes" something that was never wrong. `CLAUDE.md` carries the same
  wording; **Task 8 Step 0 now corrects it there**, and the plan's own Task 8 Step 3 has been fixed.

## Interfaces produced so far

State these in later dispatches rather than letting a brief guess.

**From Task 1** (commit `61e0dcb`, plus its round-2 fix):

- **`origin=superpowers` is a legal value** in `provenance.tsv` (`scripts/check-provenance.sh:103`).
  It is subject to the same agreement rules as `ecu`, unedited: a vendored file may not carry
  `status=original`, and `origin=original` must. Tasks 2 and 3 add rows with this origin.
- **The upstream pin is `provenance.tsv:5`, on its own line**, reading
  `# superpowers=6.2.0 (3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9)`. **Do not merge it into the
  `# ecu=` line** — `check-provenance.sh:152` extracts the SHA with a greedy `.*`, so a second
  40-hex parenthesis on that line wins and `--online` breaks. Measured, not theorised.
- **`provenance-skip.tsv`'s first column is the path as it would exist in *this repository***, not
  upstream's path; the checker resolves it from the repo root. Where the two differ, the upstream
  path goes in the reason column. The header now states this (`provenance-skip.tsv:7-10`).
  **Task 5's `ecu` rows for the deleted commands follow the same rule** — they happen to coincide,
  which is why the convention was never written down before.
- **`.claude/skills/unity-brainstorming/visual-companion.md` is already a `rule=absent` path.** It is
  trivially satisfied until Task 4 creates that directory, and becomes a live prohibition at that
  point. Task 4 needs to do nothing about it; the row prohibits the file, not the directory.
**From Task 2** (commits `4fb4493`, `68a5b77`; review in flight at the time of writing):

- **`.claude/skills/unity-execution/SKILL.md` exists.** It is the inline branch of the fork. Task 3's
  `unity-planning` names it by that path; do not invent a different one.
- **It already names `unity-brainstorming` and `unity-planning` by path** in its Handoff section —
  forward references to Tasks 4 and 3. No guard is red on them today, which is itself worth noting:
  **nothing currently catches a dangling forward reference**, and Task 8's step 2 is where that gets
  checked.
- **The Deslop Pass now lives there, transcribed verbatim** — five categories, two restraining rules.
  Its guard in `tests/test-surface-references.sh` matches **capital-D** `Do not touch code that
  existed before`. The plan's own needle was lowercase, which would have made the guard pass against
  a paraphrase and fail against the verbatim transcription the plan required.

**From Task 3** (commits `dfa8684..5e81a49`):

- **`.claude/skills/unity-planning/SKILL.md` exists** and carries the fork. Phase 1a's plan-adoption
  logic moved into it and was **measured Kinglet-original** — 21 of 21 non-blank lines absent from
  `45eada9`, plus a substring sweep with zero hits, and `git log -S` dating it to `b19d3d0`.
- **The execution-mode contract is live and has five ends, all asserted.** The ledger's **line two**
  is `**Execution mode:** subagent-driven` or `**Execution mode:** inline`, line one being the plan
  path. Written by `unity-planning` §6 after the choice, and by whichever branch runs; read by all
  three surfaces, each honouring a mode **whichever surface wrote it** — otherwise a run started
  inline and resumed through the recommended branch silently changes mode.
  **`unity-execution` previously kept no ledger at all**, which made the inline branch the one that
  could not be resumed; it now writes two lines.
- **A ledger lives beside its plan** — `docs/features/<slug>/ledger.md` and `<plan-slug>-ledger.md`
  are that one rule applied, not a rule plus an exception.
- `subagent-driven-implementation`'s `description:` no longer names `/unity-workflow`. **One body
  reference survives at its line 8** (`"/unity-workflow Phase 3 today is a document…"`) — historical
  framing, and **Task 5's to resolve**.

- **`tests/test-provenance-origins.sh` exists and is self-contained** — own helpers, own
  `set -euo pipefail`, valid to run standalone. Tasks 5 and 7 extend it. It uses
  `${BASH_SOURCE[0]}`, not `$0`: inside `( source "$file" )` a test file sees the *sourcing* shell's
  `$0`, and the plan's original line resolved correctly only by the accident that `run-tests.sh`
  also lives in `tests/`.

## Tasks

| # | Task | Status | Commits | Notes |
|---|---|---|---|---|
| 1 | Provenance accepts a `superpowers` origin; two refusals recorded | **done** | `0b67c49..a7c0d7f` | 4 fix rounds. Spec ✅, Quality Approved, 0 Critical. Rounds 1–3 with the original implementer, round 4 with a fresh one per the loop's rule; round 4 found the guard's **shape** was wrong, which retroactively explains rounds 2–3 as symptom-patching |
| 2 | `unity-execution` — inline branch, Deslop Pass, cut-criterion gate | **done** | `4fb4493..04e1d96` | 2 fix rounds. Spec ✅, 1 Critical + 2 Important + 3 Minor, all ADDRESSED. **The cut-criterion gate was answered "ship it" with a concrete defence** — see below |
| 3 | `unity-planning` — plan-writing as a skill, carrying the fork | **done** | `dfa8684..5e81a49` | 2 fix rounds. Spec ❌→✅ (the `writing-plans` document header was missing), 4 Important + 7 Minor, all ADDRESSED. **The fork's write half did not exist** — see below |
| 4 | `unity-brainstorming` — rename + the design half | **done** | `dd7f434..f648047` | 2 fix rounds. Spec ✅, 5 Important + 5 Minor, all ADDRESSED. **32 of ECU's 69 substantive lines survive**, measured, so D10's `origin=ecu` ruling holds. Reverse-sweep escapes 153/176 → **66/153, zero in any ECU or manifest-named section** |
| 5 | Delete the two sequencer commands, repair every reference | **done** | `308136e..b0adca5` | 2 fix rounds. Spec ✅, 3 Important + 5 Minor, all ADDRESSED. **28 files touched**, three dead names swept, and the pool is now **8 + 9 + 16 = 33**, matching D7's arithmetic exactly |
| 6 | `using-kinglet` becomes a mandate | **done** | `0492ec5..4222036` | 2 fix rounds. Spec ✅, 2 Important + 8 Minor, all ADDRESSED. The file is 64 lines and still read in full; the growth was all meta. **Nothing in `tests/` had ever executed `session-brief.sh`** — see below |
| 7 | Licence facts — NOTICE gains MIT text, stale claims go | **pending** | — | NOTICE ships into user projects |
| 8 | Whole-wave verification | **pending** | — | |

## Loop rule added mid-run — the controller does not commit while a round is open

Learned the hard way in Task 1 round 3, and the root cause was the controller's, not the
implementer's.

The controller committed the ledger onto the branch while the implementer was mid-round. The
implementer's `git commit --amend` then amended **the controller's commit**, producing a commit that
carried the ledger's contents under the implementer's message. Its pre-amend check was
`git branch -r --contains HEAD`, which answers *"is this pushed"* — not *"is HEAD still mine"*, which
is the question `--amend` actually depends on. Two rounds of that check working is what stopped it
being read.

It caught the mistake itself, because `git status` came back clean when it expected the controller's
ledger to be dirty. Repaired properly: tagged `rescue-479fd28`, reset, re-applied its own change,
amended its own commit, cherry-picked the ledger commit back with its original message, authorship
and date. Verified by the controller: `git diff --stat rescue-479fd28 HEAD` empty, `87d995d` carries
the ledger author and touches only the ledger, `0b67c49` touches only the implementer's four files.

**Two rules follow, both binding for Tasks 2–8:**

1. **The controller writes to the ledger during a round but commits it only after the round closes.**
   A round is open from dispatch until the re-review's verdict.
2. **An implementer that amends re-verifies HEAD is its own commit first** — by hash recorded at
   creation, not by `branch -r --contains`. If it is not, add a commit instead of amending.

The transferable half is smaller than the incident: **a check that has passed twice stops being
read.** Both of Task 1's controller errors and this one share that shape.

## Ask the shape question early — Task 1 cost four rounds for not asking it

Rounds 2, 3 and 4 were **one defect at increasing depth**: a copy of `check-provenance.sh`'s
extraction expression lived inside the test, and each round added machinery to keep the copy honest.
Round 4's fresh implementer was the first to ask whether the guard was the right shape at all, and
the answer was no — what `--online` depends on is a property of `provenance.tsv`, not of the
checker's code, and asserting the property directly deletes the copy rather than policing it.

The evidence was measured, and it is the part worth carrying: an **honest two-line refactor** of the
checker reds the round-3 design and leaves round 4 green. So the old construction issued a false
positive on ordinary maintenance, whose only resolution was hand-syncing the copy — which re-armed
the very defect round 2 had closed. **The construction manufactured the pressure that produced its
own worst failure.** Re-review reproduced this independently, and found a second instance (changing
the checker's quote style from `'^# ecu='` to `"^# ecu="` reds round 3, not round 4).

**For Tasks 2–8:** when a review's finding is the same *class* as the one before it, stop patching and
ask whether the construction is right. Two rounds of the same class is the signal, not four.

## Task 1's residual, recorded rather than resolved

The requirement the controller set — *no single edit may make the file stop detecting the target
regression while it still exits 0* — **does not hold literally.** Re-review found three single-line
edits to the shared observation path of assertions 5b/5c that blind both and exit 0.

Accepted, with its reasoning, because the distinction is real: those edits **blind the observation of
primary data**, which every test ever written is vulnerable to. The round-2/3/4 class was different in
kind — the observation stayed honest-looking while the thing observed was an unpinned copy that had
drifted from its subject. There is no copy left to drift. None of the three is reachable by honest
maintenance, which is exactly the property round 3 lacked, one contradicts a comment two lines below
it, and `run-tests.sh` separately flags a file that exits non-zero without reporting.

## Deferred and parked findings

### Five from Task 4, deferred with rulings

1. **The closing `---` frontmatter fence is unguarded across all 16 skills**, and belongs in
   `tests/test-skill-discovery.sh`, not in one skill's guard. Measured: deleting it produces **zero
   failures for 15 of 16** once the baseline is regenerated the way the workflow does; the sixteenth
   is caught incidentally, because the description extractor reads into the body and trips an
   unrelated assertion. The **opening** fence is caught everywhere, since `name:` extraction depends
   on it. Fixing it in one skill would be the "applied on one side only" shape this repo keeps finding.
2. **Load-bearing sentences inside surfaces the manifest names are still unguarded** — the
   `/unity-prototype` exemption's limiting clause, the Handoff's stop instruction, the whole
   Build/Tweak table, and the vague-as-clear table's header row. The blocks the row names *verbatim*
   are all guarded; these are sentences inside blocks it names by description.
3. **The field-6 assertion's comment states an inverted rationale.** It says flipping to `verbatim`
   "would skip the checksum comparison"; measured, `verbatim` **triggers** it and
   `check-provenance.sh` fails with `status=verbatim but the file differs`. The assertion is right;
   the reason written beside it is wrong.
4. **`ub_section` uses `/^#{1,3} /`, the only ERE interval expression in `tests/` or `scripts/`.**
   Simulated against an awk without interval support the suite goes **red**, not silently wrong, so
   the failure direction is safe. Confirm during the planned macOS pass.
5. **The old `deep-interview` path has no `provenance-skip.tsv` row.** Its absence is guarded instead
   by an `assert_eq` in `test-surface-references.sh`. That works, and the plan did not ask for a row,
   but `CLAUDE.md` designates `rule=absent` as *"what keeps a removed surface from silently
   returning"* — Task 8 should say yes or no deliberately.

### Four from Task 6, deferred with rulings

1. **`.claude/hooks/session-brief.sh` had never been executed by any test.** Delete the closing `---`
   of `using-kinglet`'s frontmatter and its awk stays in frontmatter mode for the whole file: the hook
   **prints nothing, exits 0, and a session opens with no brief at all**, suite green in both
   directions. Task 6 closed it **for that one file, via the hook**. The class stands for the other
   15 skills: `test-skill-discovery.sh` greps for a `name:` line and a `description:` line, so any
   skill can carry a third key or an unparseable block with the suite green. Same shape as Task 4's
   deferred fence item; they are one item and belong together in `test-skill-discovery.sh`.
2. **The Situation column is free text.** A full description of what a surface contains lives there
   green — measured, renders, ships. Closing it needs a rule about what a Situation cell may *say*,
   which is a design question rather than a guard fix.
3. **`UK_SECTIONS_EXPECTED` matches ATX headings only.** Setext underlines and `<h2>` blocks are
   caught *only* because the five whole-block compares tile the file end to end, so relaxing any one
   of them to an `assert_contains` reopens both. A note now says so in the guard; no check.
4. **`SKILL.md:8`'s "Five rules" and `:54`'s "six rule files"** are true today and rot together on a
   seventh rule file; `"six rule files"` is duplicated in `unity-brainstorming:23`. Same class as the
   surface counts nothing re-derives.

### Four from Task 5, deferred with rulings

1. **Four narrowing routes past the dead-name guard remain** — excluding `.claude/commands/*` or
   `.claude/agents/*`, narrowing `scripts/*` to `*.sh`, or replacing the docs glob with a file list.
   Each measured with a plant getting through. Narrower and less likely than the skip-case route that
   was fixed; the honest limit of floors-plus-sentinels is that **skipping a non-sentinel file still
   passes**, since one file does not move a `>= 60` floor. Inherent to the mechanism, not residue.
2. **The red-flag assertion is existence-only for `systematic-debugging` and
   `verification-before-completion`.** Gutting either body or retitling either tail passes everything
   — Task 4's exact-title assertion covers only `unity-brainstorming`. It is nonetheless **the only
   coverage those two skills have.**
3. **`using-kinglet:20` and `:21` overlap.** Row 20 preserves the pre-D2 vagueness gate that D2
   explicitly replaced with an unconditional category trigger. **Task 6 owns this rewrite** — do not
   let it survive as a second, softer trigger sitting above the real one.
4. **Nothing re-derives the surface counts** in `docs/GETTING-STARTED.md`, `docs/SKILL-CATALOG.md` or
   `CLAUDE.md`. Task 5 audited and corrected them (they are true today: 9 commands, 8 agents, 16
   skills, 27 hooks), but the class stands. Extending `tests/test-derived-counts.sh` to surface counts
   would close it **and** catch `CLAUDE.md`'s "32", which Task 8 Step 1 currently fixes by hand.

### Task 5 must do these — they are not optional cleanups

- **Drop `provenance.tsv:545`'s parenthetical** *"(it is still present in the tree this row
  describes)"*. It is true today and becomes false the moment the command is deleted.
- **Resolve `subagent-driven-implementation`'s line 8**, which opens by describing `/unity-workflow`
  Phase 3 in the present tense.

### Seven from Task 3, deferred with rulings

1. **`unity-execution`'s ledger address is unguarded** while `subagent-driven-implementation`'s
   identical address is guarded. The two writers can drift apart silently.
2. **The handoff's *position* inside the header block is prose-only.** `assert_same` extracts by awk
   from the first `**For agentic workers:**` regardless of where it sits, so "in this order" and
   "under the title" are asserted in text and not enforced.
3. **The precedence sentence that does Important 3's actual work is unguarded** — deleting only it
   leaves the suite green, because the needle `plan path` is satisfied by the input-list clause.
4. **`## Global Constraints` inside a fenced block reads as a real heading to any `^## ` scanner**,
   and silently truncated the re-reviewer's own extraction. A hazard for any future section-anchored
   assertion in `unity-planning`.
5. **Selection tie-break is one-sided.** `unity-planning` now owns the token "plan path" and states a
   precedence rule; `subagent-driven-implementation`'s description does not concede it.
6. **~18 pre-existing `docs/superpowers/plans/*.md` carry the upstream
   `superpowers:subagent-driven-development` handoff**, which is not a Kinglet surface. Task 7/8.
7. **Nothing in the suite covers a skill→skill path reference.** `test-skill-discovery.sh` scans only
   `.claude/agents` and `.claude/commands`; `test-surface-references.sh` scans skill bodies only for
   `/unity-*` **command** tokens. Task 8 step 2 checks it once; consider making it permanent.

### Six from Task 2, deferred with rulings

1. **Nine unguarded ECU-verbatim lines in `unity-execution/SKILL.md`** — `Deslop rules:`,
   `Present a complete summary to the user:`, five Final Summary sample bullets, two fences. Re-review
   demonstrated the two-edit path end to end: delete them, run the **mandatory** `baseline-regenerate`,
   and the suite reads `327 passed, exit 0` — the total does not even move, because no assertion was
   removed, only content no assertion named.

   **Deferred deliberately.** The guard covers every load-bearing instruction: five categories with
   their bodies, all five rules, the max-3 bound, all seven summary headings. What is exposed is
   template scaffolding, and the two-edit path runs through a regeneration that is itself reviewed.
   **The method to close it is recorded below and is the transferable part.**

2. **`tests/` sits outside every checksum and nothing asserts the suite total.** The baseline covers
   only `.claude/` and `templates/`; `CLAUDE.md` forbids hardcoding the total. So shortening a
   needle list is silent — measured: blanking one needle takes the file from 29 passes to 28 with no
   failure. Structural and pre-existing; belongs in the hooks pass, not here.

3. **The `carries verbatim ecu …` note form is unenforced** — convention only. Worth a guard if it is
   to be relied on, since Tasks 3 and 4 are told to follow it.

4. **`SKILL.md:49`** — the verify loop's `unity-reviewer` step is the only one of four with no needle.
   Kinglet-rewritten, so not an ECU-loss vector, but it is the step that makes the loop a review.

5. **`CREDITS.md` now contradicts itself internally**, not merely upstream: §4 still says Superpowers
   is *"influence, not a license obligation… nothing is vendored"* while the same commit records the
   first adapted `origin=superpowers` row. **Task 7 must be given this sharper version** — it is
   scheduled to fix the staleness, not the self-contradiction.

6. **Nothing catches a dangling forward reference.** `unity-execution` names `unity-brainstorming` and
   `unity-planning` by path; neither exists yet. `test-skill-discovery.sh` scans only
   `.claude/agents` and `.claude/commands`; `test-surface-references.sh` scans skill bodies only for
   `/unity-*` **command** references. If Tasks 3 and 4 never landed, **the suite would stay green and
   a user would be handed two paths resolving to nothing, with no error of any kind** — the exact
   silent-load failure that guard exists for, in the one direction it does not cover. Task 8 step 2
   is where this gets checked; consider whether it should become a permanent guard.

### The method that found what the deletion proof could not

Task 2's implementer proved its guard by deleting each guarded string and confirming the matching
assertion failed. That proves **soundness** — every needle is load-bearing, none satisfied by other
text — and re-review reproduced it independently.

It cannot prove **completeness**, because its input set is the guard's own list: it can never notice a
line that has no needle. The reverse sweep is what finds those — **delete every line of the file in
turn and ask which deletions are silent.** That is how the nine unguarded lines surfaced, and it is
the cheaper habit to carry into Tasks 3–8.

### Three from Task 1, deferred with rulings — none blocks the wave

1. **Share one ECU lookup between checker and test.** Re-review agrees this is the real fix and gave a
   better reason than the implementer's: with a shared function, blinding it (`| head -1`) changes
   `--online`'s *actual* behaviour too, so the test's green would be truthful about a changed subject
   rather than blind to an unchanged one. It retires assertion 5a. **Note when doing it that the
   count assertion must stay local** — it catches the before/duplicate pin shapes a value check
   cannot see. Deferred because it edits `scripts/check-provenance.sh`, the repo's most load-bearing
   gate, which is a different risk profile than a test file and deserves its own review.

2. **`check-provenance.sh` dies where it claims to warn.** With no `# ecu=` header line,
   `ECU_COMMIT=$(grep -m1 … | sed …)` exits 1, pipefail propagates, and `set -e` kills the script *at
   the assignment* — its own `warn … skipping --online` branch is unreachable for that input.
   Measured in isolation. **Both** the round-3 and round-4 diagnostics describe it as "warn and skip",
   so both are wrong on that clause. One-line fix (`|| true` on the grep), same file as item 1, so do
   them together.

3. **One-line hardening for 5a's surviving OR hazard.** `grep -qF` still means "any one line of the
   key matches", which is what lets the self-reported two-line-key attack defeat 5a and 5b (5c catches
   it alone). Replacing it with pure-bash substring containment —
   `[ "${haystack#*"$ecu_key"}" != "$haystack" ]`, bash 3.2-safe — cannot be satisfied by a multi-line
   key, moving that attack from "caught by one assertion" to "caught by two". Deferred rather than
   taken as a fifth round: the re-reviewer, after four rounds of finding real defects, said it would
   not open one, and "one more one-line improvement" is precisely the scope creep that turns three
   rounds into six. Pair it with item 1.

### `bash-gate.sh` classifies on the whole command string, including prose

Appending the round-3 report section was blocked as `git-reset-hard` because the rollback command
appeared **in the prose being written**, not in a command being executed. The gate cannot distinguish
a documented command from an invoked one.

The reason this is worth a row rather than a shrug: the available workaround is to reword the
documentation until the gate stops matching — which trains quieting a guard by editing prose around
it. That is the opposite of what a guard is for, and it is a habit that transfers.

Out of scope for this wave. Recorded so it is not rediscovered as a novelty.

### Carried to Task 7/8 — the Superpowers pin is a record, not an enforced fact

`scripts/check-provenance.sh`'s `--online` loop filters on `origin=ecu` **and** `status=verbatim`.
Every adapted surface this wave adds will be `status=modified`, so **no code path will ever verify
the `# superpowers=` pin**. The reviewer named this as the same criticism the implementer correctly
levelled at the round-0 skip rows, one level up.

Correct for Task 1 — D10 asked only for the origin value, and the pin exists to serve Task 7's
CREDITS/NOTICE work. **Carried so it is not later mistaken for enforcement.** Task 7 should say
plainly in `NOTICE.md` that the pin records which upstream the text was adapted from and is not
machine-verified, or Task 8 should decide whether `--online` ought to cover `status=modified` rows
at all. Do not let it pass silently.

### Two controller errors in Task 1's brief, both caught by the implementer

Recorded because the pattern matters more than either instance, and both are the controller's, not
the implementer's:

1. **The brief's skip rows used upstream-relative paths.** `check-provenance.sh` resolves
   `rule=absent` from the repo root, so the rows would have been a record and not a prohibition —
   recreating, inside the fix, the exact defect the fix existed to close. The implementer flagged it,
   deferred to the controller's stated resolution rather than deviating, and the controller reversed
   itself. The file's own header contradicted the controller and said so plainly.
2. **The controller ordered the pin onto the `# ecu=` line.** The implementer made the change,
   *measured* it, and found `--online` would clone ECU's repository and check out the Superpowers
   SHA. Nothing in the suite runs `--online`, so both gates would have stayed green over it. It put
   the pin on its own line and guarded the extraction rather than editing the file it had been told
   not to touch.

The transferable lesson for the remaining seven tasks: **a controller resolution is not evidence.**
Both errors were caught because the implementer treated an instruction as a hypothesis and measured
it before obeying it. Dispatches should keep inviting that rather than discouraging it.

### `⚠️ Cannot verify from diff` — carried, no action

- The pre-implementation red run and the revert-and-watch-the-suite-redden proof. The reviewer
  confirmed the guard *can* go red independently, but not that those specific transcribed runs
  happened.
- Whether `70fdeb4` was ever pushed before the amend. No remote-tracking ref exists locally, which is
  consistent with the report, but the diff cannot rule it out.
