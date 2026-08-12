# Ledger — plan: `docs/superpowers/plans/2026-08-11-shipped-citations-resolve.md`

Spec: `docs/superpowers/specs/2026-08-11-shipped-citations-resolve-design.md`

- **Branch:** `pioneer/process-chain`
- **Base commit (the whole-branch review diffs against this):** `7f4b9f3`
- **Gates:** `bash tests/run-tests.sh` (needs a timeout above 150000 ms; the `--- test-*.sh ---`
  header count, **ANSI-stripped**, must equal `ls tests/test-*.sh | wc -l`) and
  `bash scripts/check-provenance.sh` (must end `provenance OK`).
- **Reports:** `.superpowers/sdd/2026-08-11-shipped-citations/` (gitignored).

## RESUME HERE — state for a session that has lost its context

**Tasks 1–4 are done and closed.** The guard exists, both rules pass, all sixteen citation sites are
fixed, the installer's dry-run describes the program it actually runs, and the fork's two branches
agree on their threshold. **Task 5 is next** — `GETTING-STARTED.md:162` and the process-chain
ledger's stale `RESUME HERE`. Nothing is dispatched.

The wave makes every citation a shipped surface makes resolve in an installed Unity project. Eight
`§N` markers abbreviate a citation to `docs/research/pioneer/field-notes.md`, which is tracked and
does not ship; eight backticked paths name files `install.sh` does not copy, one of them a **rule**
instructing the reader to inspect a test and report a regression. A new guard,
`tests/test-shipped-citations.sh`, enforces both rules against a payload it derives rather than
hardcodes.

Suite at wave start: 488 passing, 30 test files, 544 manifest rows. **Now: 495 passing, 31 test
files, `provenance OK`.** The guard prints 7 PASS lines and examines 561 backticked tokens.

**Spec D3 was withdrawn mid-Task-1 and the spec is corrected on the record.** The first draft said
the `§N` markers pointed at nothing and ruled `systematic-debugging:39`'s empty cell should stay
empty. The numbers resolve — against a repo-only document — so the cell was filled from field note 75
instead. The action for the other seven is unchanged, because `docs/` does not ship. Read the
correction block at the top of the spec before reasoning about the `§` class.

## Controller decisions, made at setup

1. **The controller owns this ledger, not Task 1.** The plan assigned its creation to Task 1 Step 6
   and its provenance row to Step 7. That is wrong in a way the skill is explicit about: the ledger
   is the recovery map and must exist *before* the first dispatch — if Task 1's implementer dies,
   a ledger that Task 1 was going to write does not exist. Created and committed at setup, before
   any round opened. **Task 1's brief drops Step 6 and drops the ledger row from Step 7.**
2. **All six tasks get a general implementer and a general reviewer, not `unity-coder` /
   `unity-reviewer`.** This is the toolkit repository: no Editor, no MCP bridge, no C#. Every file
   here is bash, Markdown or TSV. Routing shell and documentation work to an agent built to drive
   the Unity Editor measures the dispatch rather than the task.
3. **The brief for each task is that task's section in the plan, cited by heading** — not a separate
   brief file. The plan was written by `writing-plans` specifically to be executed task by task, with
   full code blocks and no placeholders. Copying each section into a second file would create two
   definitions of the same requirement, which is the exact defect this branch exists to remove.
4. **The controller does not commit while a round is open.** Carried from the previous wave, where
   an implementer's `git commit --amend` amended the controller's ledger commit. A round is open from
   dispatch until the re-review's verdict.

## Standing facts for every dispatch

Copied into every dispatch. A fresh subagent inherits none of the controller's reading of the repo.

- **Spec:** `docs/superpowers/specs/2026-08-11-shipped-citations-resolve-design.md` at `99c18a2`.
  Where the plan and the spec disagree, the spec wins and the disagreement is a bug in the plan —
  report it rather than resolving it silently.
- **This is not a Unity project.** `kinglet-unity` is the toolkit repository. No Editor, no MCP, no
  C#. `read_console` does not apply; there is no console.
- **Gates, both, before reporting done:** `bash tests/run-tests.sh` (timeout above 150000 ms) and
  `bash scripts/check-provenance.sh` ending `provenance OK`.
- **Strip ANSI before counting suite headers.** The runner colours `--- test-*.sh ---`, so
  `grep -c '^--- test-.*\.sh ---'` on raw output returns **0** on a completely healthy suite — the
  exact signal of the catastrophe the count exists to detect. Use
  `sed $'s/\x1b\\[[0-9;]*m//g'` first.
- **bash 3.2 compatible.** No `declare -A`, no `grep -oP`. A macOS pass is planned.
- **Never pipe into a reader that can exit early** under `set -euo pipefail`. `grep -q` exits on
  first match without draining stdin; SIGPIPE plus pipefail kills the script on large inputs and
  passes on small ones. Use a here-string: `grep -qF -- "$needle" <<< "$haystack"`.
- **`[ x = y ] && continue` is a `set -e` trap** as the last command in a loop body — the false test
  makes the AND-list exit 1 and kills the script. Write `if [ x = y ]; then continue; fi`.
- **Two test idioms, and mixing them fails silently.** *Self-contained*: sets its own
  `set -euo pipefail`, defines its own helpers, `bash tests/<file>.sh` is valid.
  *Runner-provided*: uses the runner's `assert_contains` / `assert_eq` / `$REPO_DIR`, defines
  neither, and run standalone **exits 0 having asserted nothing**.
  `tests/test-shipped-citations.sh` is self-contained. `tests/test-surface-references.sh` is
  runner-provided — verify it **through the runner**, reading its section.
- **Print `PASS:` / `FAIL:`, not `ok:`.** `run-tests.sh` aggregates by grepping for those tokens; a
  file printing anything else contributes 0 and is indistinguishable from one that never ran.
- **Baseline discipline.** `.claude/` content changes trip `tests/kinglet/test_baseline_inventory.py`
  sha256 tripwires. Order is **commit, regenerate, commit** — the reverse is circular, because the
  test reads `git ls-files` while the regenerator reads `git ls-tree`. Entry point is the
  **package**: `python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift <n>`;
  `python3 -m tools.kinglet_build.cli` silently no-ops with exit 0. `--dry-run` first, **use the
  tool's numbers, not the plan's estimate**, and report a disagreement instead of tuning the flag
  until it passes. A categorised file counts twice. The tool updates the JSON but **not** the
  hand-maintained constants in `test_baseline_inventory.py` — fold those into the same commit.
- **Every new tracked file needs a `provenance.tsv` row** — seven tab-separated columns: path,
  origin, upstream_version, upstream_path, upstream_sha256, status, note. Files originating here:
  `original	-	-	-	original	<note>`. A file with no row fails as an orphan.
- **`grep` is line-oriented and prose is not.** Flatten before asserting a phrase is absent: a
  sentence wrapping across two lines cannot be read by any single-line pattern. This repository has
  shipped two stale claims for exactly this reason.
- **A needle that passes for the wrong reason is worse than no needle**, and **a red-first step that
  starts green is worse than no red-first step** — it reads as "the work is already done". Every
  "watch it fail" step means observe the *specific* failure named.
- **A sentinel must not contain its own needle.** A note or comment carrying the string a guard
  searches for satisfies that guard by itself.
- **One implementer at a time.** The Unity rationale does not apply here, but the shared working tree
  does: this repo has already had a controller's untracked probe file mistaken for a concurrent
  agent's leftovers.
- **Probe on a scratch copy, never the working tree.** `git archive HEAD | tar -x -C "$(mktemp -d)"`.
  The controller broke this rule itself in the previous wave.

## Interfaces produced so far

**`tests/test-shipped-citations.sh` exists** (self-contained, 71 lines at `a4f49ea`) and exports to
Task 2, by these exact names:

- `payload_paths()` — no arguments, prints one payload-relative path per line. Verified byte-exact
  against a real fixture install: the only difference from the installed `.claude/` tree is
  `state/install-receipt.tsv`, which install generates and the derivation correctly excludes.
- `PAYLOAD` — its output, **85 entries** (76 under `.claude/` plus 9 shipped scripts). The brief's
  comment said 86; the implementer measured 85 and wrote 85.
- `SHIPPED_MD` — `find "$REPO/.claude" -name '*.md' | sort`, currently 44 files.
- `FAILURES`, `pass()`, `fail()` — the counter and the two token-printing helpers.

**The file's closing two lines are reversed from what the plan shows.** Controller resolution 3
replaced the brief's footer with the house idiom, so the file now ends:

```bash
[ "$FAILURES" -eq 0 ] || exit 1
printf 'all shipped-citation assertions passed\n'
```

**Task 2's rule-2 block must therefore be inserted before `[ "$FAILURES" -eq 0 ] || exit 1`**, not
before a trailing `printf` as the plan's Step 1 implies. Reported by Task 1's implementer.

## Tasks

| # | Task | Status | Commits | Notes |
|---|---|---|---|---|
| 1 | Guard rule 1 (`§N`) + the eight marker sites | **done** | `c56a1fd..a4f49ea` | 1 fix round. Spec ✅, Quality Approved, 1 Important + 5 Minor, none blocking. **The implementer found the spec's premise false and said so instead of proceeding on it** — see below |
| 2 | Guard rule 2 (repo-only paths) + the eight path sites | **done** | `909d85b..803b3d6` | 2 fix rounds. Spec ✅, 4 Important + 8 Minor, all Important ADDRESSED. **The header comment written to state true things stated two false ones, falsified by its own commit** — see below. Round 2's verification was the controller's, by stated deviation |
| 3 | The installer's dry-run states what the real run does | **done** | `037304b..240ee6f` | 2 fix rounds. Spec ✅, 2 Important + 3 Minor. **Scope widened once by controller ruling** (`MCP-SETUP.md`), then held. The reviewer built seven fixture states; the implementer had built three |
| 4 | The fork states its threshold once | **done** | `c78c70e..42ae003` | 1 fix round. Spec ✅, 2 Important + 4 Minor. **A third statement of the threshold existed that neither plan nor spec anticipated**, and the guard's flattening read one wrap shape of six — see below |
| 5 | The two documents that contradict themselves | open (brief pending) | — | `GETTING-STARTED.md:162`, the process-chain ledger's `RESUME HERE` |
| 6 | Whole-wave verification | open (brief pending) | — | Cites Task 2's mutation results rather than re-running them |

## What Task 1 found that the controller had wrong

**The implementer reported the spec's premise false rather than implementing it.** The brief told it
to empty a table cell because "there is no incident to recover". It ran `git log --all -S'§75'`,
got four commits rather than the one the spec claimed, followed them to
`docs/research/pioneer/field-notes.md`, and found all six cited numbers as real headings. It then
did the work anyway *for the seven sites the finding did not affect*, and flagged the eighth.

That is the behaviour the loop's rule 5 exists to produce, and it is worth naming because the
alternative was invisible: a brief carrying the controller's authority said "empty this cell", the
diff would have been small and tidy, and the review would have approved it against a spec that was
wrong. The measured cost of not catching it is one row of real evidence deleted from a shipped skill.

**The transferable half:** an absent *filename* is not an absent *referent*. Both of the controller's
measurements were correct — `sourced-incidents.md` never existed, and `§75`'s cell was bare — and the
conclusion drawn from them was not supported by either.

## Task 2's brief, as amended

The plan's "Task 2" section stands, with four changes. All four come from Task 1's review or report.

1. **Insertion point.** Rule 2's block goes before `[ "$FAILURES" -eq 0 ] || exit 1`, not before a
   trailing `printf`. See *Interfaces produced so far*.
2. **Rewrite the guard's header comment at `tests/test-shipped-citations.sh:4-7`.** It is the
   withdrawn narrative, verbatim, in a tracked file: it says "four shipped skills" (it is three) and
   "eight citations… pointed at `sourced-incidents.md`" (exactly one did). Review finding 1,
   Important, deferred here rather than fixed in Task 1 because Task 2 already modifies this file and
   a fifth commit there is more expensive than one line here. **It must not be deferred past Task 2**
   — Task 6's sweep greps for `sourced-incidents` and will force the ruling anyway.
3. **Two guard hardenings, from review finding 3.** The coverage floors are lower bounds, so a
   derivation that *over-*includes passes them silently — and over-inclusion is the dangerous
   direction, because a payload with extra entries makes rule 2 stop flagging genuinely unshipped
   paths. Add two property assertions, which do not go stale the way an exact count would:
   `PAYLOAD` contains no path under `.claude/state/`, and `PAYLOAD` contains at least one
   `.claude/scripts/` entry. The second catches the `scripts/*.sh` loop silently matching nothing,
   which today would drop the count to 76 and still clear the floor of 70.
4. **Two one-line corrections in the same file**, from review findings 2 and 6: the rule-1 pass
   message says "carries a § section marker" when the rule is `§[0-9]` — four legitimate `§Heading`
   cross-references in `state-machine` and `save-system` are correctly unflagged, and the message
   should say `§N` so a maintainer does not read it as covering them. And `:71` prints without a
   trailing newline on a red run.

## Deferred and parked findings

### From Task 1's review — one Important, deferred with a reason

1. **The guard's header comment carries the withdrawn narrative** (`tests/test-shipped-citations.sh:4-7`).
   Deferred to **Task 2**, which already modifies the file. Not deferrable further. See amendment 2
   above.

### From Task 1's review — five Minor, four closed by amendment

2. **The rule-1 pass message overclaims its scope.** → Task 2, amendment 4.
3. **The coverage floors are lower bounds only.** → Task 2, amendment 3. Note the reviewer
   established the derivation is exact *today* by installing into a fixture and diffing; the gap is
   drift detection, not current correctness.
4. **`provenance.tsv`'s note describes rule 2, which does not exist until Task 2.** No action —
   self-correcting one task from now, and the row is the plan's prescribed text.
5. **`f7adc86`'s commit message is wrong and wider than the implementer reported** — its subject
   line, not only its closing sentence, carries the withdrawn premise. **No action, and not
   amending was right**: `a7b1dfd`'s hash is already recorded in `.claude/state/session.json` and in
   this ledger's commit range, so a rewrite would invalidate references the controller had already
   taken. `ec6c889`'s message states the correction in full, so history is self-correcting for
   anyone reading it in order.
6. **No trailing newline on a red run** (`:71`). → Task 2, amendment 4. ~~Cosmetic; does not affect
   the runner's PASS/FAIL aggregation.~~ **That ruling was wrong and Task 2 disproved it by
   measurement.** `run-tests.sh:278` matches `PASS` at a line start *or after whitespace*, so the
   un-newlined flag dump glued the next line on as `…measurement.PASS: guard examined 562 …`,
   preceded by `.`, matching neither. **PASS lines counted: 5 before the fix, 6 after** — a pass
   silently dropped from the tally, on exactly the runs whose numbers get read. Left struck through
   rather than deleted: a reviewer reading this ledger should see that this class was called
   cosmetic once and was not.

### Carried to Task 6 — its sweep as written can never report clean

Plan Task 6 Step 2 greps for `sourced-incidents` and expects `clean: no reference survives`. The
string survives by design in the spec, in the plan, and in this ledger. **The check as written is
unsatisfiable and must be rewritten in Task 6's brief** to scope the sweep to what ships: `.claude/`
and nothing else. Reported by Task 1's implementer.

## Task 2's mutation results — Task 6 cites these rather than re-running them

Produced at Step 7, **re-verified at `472a0fd` and again after round 2's edit**, and independently
reproduced by two reviewers using differently-shaped probes.

| Mutation | Result |
|---|---|
| (a) `§N` injected into a shipped skill | `exit 1`, the injected line named with `file:line` |
| (b) a repo-only path injected into a shipped skill | `exit 1`, the token named; `tokens_seen` moved 562→563, independently confirming the token was read |
| (c) `CLAUDE.md` removed from the allow-list | **26** — matching D6 exactly |

The re-review reproduced all three by injecting into a **rules file, an agent, and a command** rather
than the skill the implementer used, so the guard is not a guard for one file. Its controls behaved:
`scripts/studio-doctor.sh` was not flagged (it ships), and `docs/features/slug/design.md` was not
flagged (no such file exists here, which is what keeps user-project paths from firing). It also
extended (c): dropping `LICENSE` → 1, dropping `VERSION` → 1. **All three allow-list entries are
load-bearing; none is dead weight.**

**Step 7's method had to change, and the brief's version would have corrupted two of the three.**
`git archive HEAD` at Step 7 archives a tree from *before* the task's commit — so it would have had
no rule 2 — and `git checkout` cannot restore a file inside a `tar -x` directory that has no `.git`,
so (b) and (c) would have run with (a)'s injection still in place. The implementer used
`git stash create` plus a fresh extraction per mutation. The review verified the deviation two ways:
the stash object still exists and `git diff --stat <stash> 54f65a6` is empty, so the mutations ran
against exactly the committed tree.

## What Task 2 found, and the one it created

**The header comment rewritten to state true things stated two false ones — and both were falsified
by the very commit that wrote them.** It said `NOTICE.md` carries five URLs; the task's own
`CREDITS.md` fix added a sixth. It cited `test-provenance-origins.sh` as an example that "still
fires"; the task deleted that citation. Amendment 2 existed precisely to truth-check that comment,
and the rewrite reproduced the class it was fixing.

The repair was a **method, not a patch**: state the property rather than a count and an example. The
re-review tested that by trying to falsify the new sentence — adding a seventh URL, then deleting
one — and the old sentence flipped true→false→true across those states while the new one held in all
three. The added lines contain no digit and no backticked token at all.

**The class the guard cannot see, closed by hand.** A revision of this repository cited in a shipped
surface is exactly as unfollowable as a path that does not ship, and rule 2 cannot see it — a SHA is
not a path. Two survived: `git log 0f772a4..HEAD` at `verification-before-completion:45` and a bare
`2b543f2` at `:36`, nine rows above it in the same table. The implementer's own class probe
(`grep 'git log [0-9a-f]\{7\}'`) returned none and was materially incomplete, because `2b543f2` is
not a *range*. The re-review probed five other shapes and found exactly one survivor.

**The discriminator is what makes this safe**, and a blind sweep would have done damage: `bb28ccb`,
`984023d` and `3dcbd5c` also appear in `NOTICE.md` and are correctly kept. `git cat-file -t` reports
them as not objects here — they are upstream pins — and each sits on a row carrying that upstream's
repository URL. Deleting them would have broken the MIT attribution the previous wave's Task 7
discharged.

## Deferred from Task 2 — all real, all recorded rather than half-fixed

1. **Four more rot-prone claims in the same comment block**, all measured **true today** and all
   predating the rewrite: `NOTICE.md:140` and `install.sh:175`/`:379-390` as line citations, "cited
   in 26 shipped files", "the count then falls to 76". Same shape as the defect findings 1–2 fixed.
   **The block is not rot-proof end to end**, and fixing them inside the fix loop would have been the
   scope creep that turns three rounds into six.
2. **Four things rule 2 cannot see**, all latent today, now written into the spec's *Out of scope,
   recorded*: command-form citations like `` `bash tests/x.sh` `` evade the expression entirely (the
   sharpest — it is the idiomatic way to write the citation this wave removed eight of); the
   `.claude/*` case arm is unreachable, so 56 citations are invisible; the URL escape is
   basename-suffix equality rather than resolution; and `scripts/<x>.sh` clears against a payload
   entry at a different path.
3. **`.claude/UPSTREAM` ships and names four repository-only files.** Outside both rules by
   construction — they scan `*.md`. Recorded in the spec.
4. **Rule 1's `§3` exception is file-scoped, not line-scoped.** A future *false* `§3` anywhere in
   `NOTICE.md` is invisible. Harmless today: `NOTICE.md` has exactly one `§` line.
5. **The plan's `tokens_seen` estimate of "near 323" is wrong** — measured 569 pre-fix, 561 now. 323
   was a globally-unique count; `tokens_seen` is per (file, token). Nothing depends on it; the floor
   is 200. Fix the plan text, not the guard.
6. **The runner's aggregation is blind to python results in both directions** — for the spin-out
   wave, with this framing rather than the narrower ERROR-only one. `run-tests.sh:278-280` matches
   `(^|[[:space:]])(PASS|FAIL)(:|[[:space:]])`, and unittest's `... ok`, `... FAIL`, `... ERROR` and
   `FAILED (failures=3, errors=17)` all fail that pattern. `tests/test-kinglet-build.sh`'s 1308 tests
   contribute **0 PASS and 0 FAIL**; `Total: 495` excludes them entirely. A red python run reaches
   the aggregate only through the `test_rc -ne 0 && file_fail -eq 0` fallback at `:285-288`, as
   exactly one FAIL. **The suite cannot go silently green on a python failure** — this is granularity
   loss, not a fail-open.

## What Task 3 found — and why its own method could not find all of it

The brief was one line: `install.sh:257` printed `scripts/ and tests/ into .claude/` while the real
run ships `scripts/` and *prunes* an installed `.claude/tests/`.

**The implementer widened its check from *directories* to *anything the real run writes*, and that
widening found a second instance:** `MCP-SETUP.md`, copied to the **project root**, recorded in the
receipt as toolkit-owned, announced by nothing. The controller ruled it in scope — D8's principle is
that the dry-run "does not get to describe a different program", and the block that copies it exists
*because* the summary once pointed at a file the installer never installed. The install half had been
fixed and the consent half left open.

**The fix's own trap was live and avoided.** The real copy is conditional, so an unconditional
announcement would promise a file the real run skips for every user who already has one — the same
defect pointing the other way. The announcement carries Step 8c's condition verbatim.

### The lesson: an oracle can be disjoint from the defect class

The implementer then re-ran its widened check and reported **no third unannounced write**. The
reviewer found one: with `--with-mcp` against a project whose `Packages/manifest.json` git does not
track, `install.sh:623` leaves `Packages/manifest.json.bak` behind permanently.

**The implementer's check could not have found it.** Its oracle was the receipt
(`grep -v '^#' <receipt> | cut -f1`), and `manifest.json.bak` never enters the receipt. The method
could not miss the defect — it could not *see* it. The reviewer used a `find` snapshot before and
after a real run, diffed, with the flags exercised.

This is the third time this wave that a probe's shape, not its execution, decided what it found:
Task 2's `grep 'git log [0-9a-f]\{7\}'` could not see a bare SHA, and Task 1's spec conflated an
absent filename with an absent referent. `verification-before-completion`'s own row —
*"Ask what set the check ran over before trusting silence"* — has now been demonstrated three times
inside the wave that edits it.

**The guard candidate was corrected before it could ship the blind spot.** The implementer had
recorded *"every conditional write in `install.sh` has a matching dry-run branch"*, with the receipt
as oracle. Built that way it would have certified the very class it cannot inspect. Corrected shape,
for the spin-out wave: **the filesystem is the primary oracle** — before/after `find` across a real
run, flags exercised, both `MODE=fresh` and `MODE=ours` — and **the receipt is a second, different
check** asking what the first cannot: does every write that should be owned actually get recorded.
That second check is what would catch both defects below.

## Deferred from Task 3 — two real installer defects this wave is not closing

1. **The receipt disowns files on upgrade.** `$RECEIPT_TMP` is rebuilt from scratch every run, and
   Step 8c (`install.sh:690-694`) appends its row **only on create**. So a second install drops
   `MCP-SETUP.md`'s row 1 → 0 and `uninstall.sh` — which removes only receipt-listed paths — then
   **leaves the file behind**. Measured, and `.mcp.json` (`:672`, `:683`) behaves identically, so it
   is a class. The fix is to re-record the row when the existing file is receipt-owned or matches the
   toolkit copy. **Out of this brief: an installer-ownership fix, not a dry-run fix.** Task 3's
   round-2 wording change was scoped precisely so the announcement no longer makes a claim about
   this.
2. **`Packages/manifest.json.bak` is permanent debris** (`install.sh:623`, `:642`). Created with
   `--with-mcp` against a project whose manifest git does not track; `:629` removes it only when the
   file *is* tracked. It never enters the receipt, so `uninstall.sh` can never remove it — in exactly
   the projects (non-git, or a manifest not yet added) least able to `git checkout` it away. Same
   class as `MCP-SETUP.md` and worse in that one respect.

### Three Minor from Task 3, recorded

3. **The second definition of `$PROJECT_DIR/MCP-SETUP.md`** (`:319` against `:690`) is **accepted**,
   with reasons. Hoisting is feasible — both variables are bound far earlier — but it is the file's
   established convention twice over (`CLAUDE.md` inline at `:272`/`:274` and assigned at `:460`;
   `.mcp.json` inline at `:300`/`:302` and assigned at `:660`), so hoisting only this one leaves the
   pattern half-migrated. And the path is not the duplication that matters: what must stay in step is
   the *condition*, and a hoisted variable does nothing for that. A shared predicate would, but the
   dry-run needs a three-way answer (silent / new / untouched) rather than a boolean. That refactor
   belongs with item 2's guard.
4. **Nothing guards either installer fix.** No test exercises `install.sh --dry-run`;
   `tests/test-install-prune.sh:33` already runs the installer against a fixture and does A/B upgrade
   sequences, so the infrastructure exists and the guard is cheap.
5. **`MCP-SETUP.md` as a *directory*** makes `[ ! -f ]` true, so both halves take the create branch —
   they agree, so it is not a dry-run defect — but `cp` then writes `MCP-SETUP.md/MCP-SETUP.md` and
   `sha_of` on a directory yields empty, producing a receipt row with an empty checksum. Uninstall
   degrades gracefully. Exotic and pre-existing.

## What Task 4 found — and the fifth time a probe's shape decided the finding

**A third statement of the threshold existed.** Neither the plan nor the spec anticipated it:
`unity-execution/SKILL.md:10-11` restates the fork in its **body**, and it wraps mid-phrase — `:10`
ends `more than one`, `:11` opens `substantial task`. A guard scoped to the frontmatter, which is
what the brief specified, could never see it.

The implementer widened the **negative** half to the whole flattened file and left the **positive**
half on the frontmatter, then asked for a ruling rather than assuming one. **Verdict: keep.** The
asymmetry is principled and both halves were proven load-bearing under mutation — by two different
people, in two different directions:

- the implementer showed the negative's whole-file scoping is needed: the loose form injected into a
  body goes red only under the widened form;
- the review showed the positive's frontmatter scoping is needed: deleting the qualified phrase from
  `unity-execution`'s **description** while leaving it in the body turns the positive red and leaves
  the negative green. **A body sentence cannot stand in for the field a reader selects on.**

The positive asks *does the selection field say the right thing* — it must be narrow. The negative
asks *does anything say the wrong thing* — it must be broad, because ambiguity returns from anywhere.

### The flattening read one wrap shape of six

The guard joined lines with `printf "%s ", $0` — one space appended, nothing trimmed, no runs
collapsed. Measured across six shapes, **one was caught and five were missed**: indented
continuation, blockquote continuation, a trailing space before the wrap, an indented YAML
continuation inside `description:`, and a double space on one line. The shape that worked was the one
the file happens to have today, which is why the implementer's single mutation did not surface it.

Fixed by stripping leading blockquote markers to any depth and collapsing whitespace runs, **built
once and concatenated into both awk programs** — two copies of a whitespace rule is how the two
halves would come to disagree about what "flattened" means. Re-mutated in situ across **ten** shapes:
ten of ten caught, control silent. Verified independently by the controller with an eleventh —
blockquote plus indent plus wrap, injected into the *other* skill's body — which went red.

**And one level down, the same defect again.** The implementer's fixture for the trailing-space shape
had its trailing space stripped in authoring and reported *caught*. Rewritten with an explicit
`\x20` it flipped to **missed**. A fixture for a whitespace bug that cannot hold whitespace is the
same class as the bug it tests, and it is now written so an editor cannot silently disarm it.

**Stated gaps, recorded rather than chased:** case variants (`More than one task`) and paraphrases
(`more than a single task`) pass — the guard defends against the exact retired phrase returning, not
against the ambiguity returning in new words. So does a phrase split by a Markdown construct that is
neither leading whitespace nor a blockquote marker: `more than one *emphasised* task`, or a phrase
broken by an HTML comment.

### The class the brief exposed by accident, and the sweep that closed it

The plan's Step 2 code used `fail_test` / `pass_test`. **Neither exists** — `run-tests.sh:167`
exports exactly `assert_eq assert_exit_code assert_contains assert_not_contains assert_file_exists
assert_file_executable skip_test`.

That is worse than a rename. The runner does `set +e` before sourcing, so an undefined helper prints
to stderr and continues, contributing **no `FAIL:` token at all**. The review reproduced the
brief-shaped case: a failing positive assertion followed by the `fail_test`/`pass_test` loop, and the
loop contributed nothing in either direction — so red-first would have shown the expected FAIL and
the implementer would have concluded the negative half worked while it asserted nothing. **The guard
would have shipped green on the defect it exists to catch.**

The class is caught only *positionally*: as a file's last command it trips `run-tests.sh:285-289`
with `exited 127 without reporting a failure`, a message naming no cause. Anywhere else it is silent.

**The sweep came back clean.** No test file in `tests/` calls an unresolved helper, verified two
independent ways: dynamically, sourcing all 31 files through the runner's own `( source "$f" )`
mechanics with a `command_not_found_handle` trap (zero hits); and statically, checking every
command-position `assert*` / `pass_*` / `fail_*` / `*_test` token against each file's local
definitions plus the seven exported names (zero unresolved). The dynamic pass covers only branches
taken on this host; the static pass covers untaken branches but not dynamically constructed calls.

## Deferred from Task 4

1. **`unity-planning:139-141` and `:186-193` — the surface that owns the fork states no threshold at
   all**, and `:140` labels `subagent-driven-implementation` "(recommended)" unconditionally, which
   reads against D9's preference for inline on small plans. Pre-existing and outside D9's letter, so
   out of scope here — but it is where the corrected acceptance criterion 7 points next, and the
   negative assertion does not reach it.
2. **The guard's coverage limits**, listed under *Stated gaps* above. Recorded in the guard's own
   comment as well, so a maintainer meets them where they matter.
3. **`assert_contains "$fork_whole" "$fork_branch"`'s label overclaimed** and was reworded: it is
   satisfied by the `name:` line, so it proves the file was opened and flattened to something, not
   that a body was read. It still does its real job — the vacuity mutations fire, producing 3 named
   FAILs on an emptied or deleted file rather than a green absence check.

## Two controller-document defects Task 4 found, both now fixed

Both were confirmed by the review before the controller acted on them.

1. **Spec acceptance criterion 7 contradicted D9.** It read *"No two surfaces state the fork's
   threshold"* while D9 four screens up says *"Both descriptions carry the same phrase afterwards,
   verbatim, and a guard asserts they do."* Wrong on its facts as well as its logic — **three**
   places state it. The defect was never that the threshold is stated more than once; it is that the
   statements disagreed. Corrected in place with the correction dated.
2. **Task 6's criterion-7 command would have read a correct fix as a failure.** `grep -h 'more than
   one'` over the two skills prints **three** lines, and the middle one ends at a bare `more than
   one` because of the `:10-11` wrap. Replaced with a flattened form; verified to print two unique
   results, both `more than one substantial`.

## Controller deviations, stated so their absence is not read as an omission

1. **Round 2 of Task 2 was verified by the controller, not by a dispatched re-review.** A single-line
   deletion whose correctness is a `grep` returning empty does not need a fresh reader, and the
   dispatch would have cost more than it caught. Verified: `2b543f2` gone from shipped Markdown; the
   three upstream pins still present and still not objects in this repository; no hex string in any
   shipped `.md` resolves via `git cat-file -t`; guard `exit=0` with 7 PASS; `provenance OK`; tree
   clean.
2. **The controller's brief named the wrong line for the git-range fix** (`:44`; it is `:45`, and
   `:44` is the `Light2D` row carrying no range). The implementer reported the correction rather than
   silently retargeting, which is the distinction that matters.
3. **Task 2's implementer did not photograph the intermediate sha256 tripwire state** between its fix
   and baseline commits in round 2, as it had in rounds 0 and 1. It flagged the gap itself. Accepted:
   the tool's non-zero drift is itself evidence the tripwire had something to notice, and the final
   run is green.
