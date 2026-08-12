# Ledger — plan: `docs/superpowers/plans/2026-08-12-installer-owns-what-it-writes.md`

Spec: `docs/superpowers/specs/2026-08-12-installer-owns-what-it-writes-design.md` at `2d081f0`.

- **Branch:** `pioneer/installer-ownership`, cut from `main` at `c5280c4`.
- **Base commit for the whole-branch review:** `c5280c4`.
- **Gates:** `bash tests/run-tests.sh` (timeout above 150000 ms; ANSI-stripped `--- test-*.sh ---`
  header count must equal `ls tests/test-*.sh | wc -l`) and `bash scripts/check-provenance.sh`
  (must end `provenance OK`).
- **Reports:** `.superpowers/sdd/2026-08-12-installer-ownership/` (gitignored).

## RESUME HERE

**Tasks 1, 1b, 1c, 1d and 2 are done and closed.** Task 2 passed review with **no fix round** — Spec ✅,
Quality Approved — which is the first time in this wave. **Task 2b is the next action**, then 3, 4, 5,
6.

**Task 2b was inserted 2026-08-13** because Task 2's review measured a second live member of the class
Task 2 closes: `CLAUDE.md.generated` is created by the installer, kept, announced, and never recorded —
permanent debris on the project root. Spec **D10**, criterion 13. D10 declared itself the wave's last
insertion, with one exemption: **data loss in shipped software**.

**Task 2c was then inserted the same day, through that exemption, and it is the wave's most serious
finding.** Task 2b's review reproduced on three independent paths that `install.sh` has two writers
that overwrite without asking — and that **this wave taught both of them to claim the file was safe**
while doing it. See the Task 2b section below. Spec **D11**, criterion 14, plus an amendment to
criterion 13. **The exemption is now spent**: nothing further is promoted unless it is data loss, and
the two known non-data-loss instances (`.gitignore`, and the `.bak` `cp` clobber's remaining half) are
recorded for a second wave.

The wave keeps growing because each task's review finds the next instance of one root cause. The
spec now carries **nine decisions**, and the tally is: the origin column is written in four places
and, before this wave, read in none. Task 1 fixed the project-root rows, Task 1b fixed
`uninstall.sh`, **Task 1c fixes the scripts loop — which does not check `is_modified` at all, so the
run prints `keeping yours:` naming a file it overwrites in the same output** — and Task 1d fixes
`studio-doctor.sh`, the last reader, which also carries two `printf | head` SIGPIPE traps.

Suite: **645/645**, 32 test files, `provenance OK`, baseline zero drift, tree clean at `29a8593`.

Nine defects now, one shape: the installer makes a claim it does not keep. The receipt is rebuilt every
run and two project-root files write their rows inside a *create* branch, so a second install
silently disowns them and `uninstall.sh` leaves them behind. `manifest.json.bak` is kept without a
row, so uninstall can never remove it. Two pipeline detectors disagree when both packages are
present, and neither has a both-installed state. The dry-run announces two of four `.gitignore`
entries, unconditionally. And "Option B: Manual Copy" produces an install `uninstall.sh` refuses to
touch.

Three of those nine were found *by this wave's own reviews*, not by the survey that opened it —
D7, D8 and D9, each surfaced by the task before it. State at wave start: suite **503/503**, 31 test
files, tree clean at `f8cd590`.

## Controller decisions, made at setup

1. **The controller owns this ledger.** Created before the first dispatch — a recovery map that a
   task was going to write does not exist if that task dies. The plan does not assign it to anyone.
2. **Every task gets a general implementer and a general reviewer.** This is the toolkit
   repository: no Editor, no MCP bridge, no C#. Routing shell work to an agent built to drive the
   Unity Editor measures the dispatch rather than the task.
3. **The brief for each task is that task's section in the plan, cited by heading.** Copying it into
   a second file would create two definitions of one requirement.
4. **The controller does not commit while a round is open** — from dispatch until the re-review's
   verdict.
5. **Every dispatch says "commit your work."** The previous wave's round A finished correct and
   uncommitted because the dispatch omitted the step.

## Standing facts for every dispatch

- **Spec** at `2d081f0`. Where the plan and the spec disagree, **the spec wins** and the
  disagreement is a bug in the plan — report it rather than resolving it silently.
- **This is NOT a Unity project.** No Editor, no MCP bridge, no C#, no console. `install.sh` gates on
  `Assets/` + `ProjectSettings/`, so the fixture is how it is exercised:
  `bash tests/fixtures/mkproject.sh <dir> [--variant urp|builtin|bare|dirty|legacy|async-mixed]`.
  Make fixtures realistic — a one-line `ProjectVersion.txt` once hid a real bug, because Unity writes
  two lines and both match the version regex.
- **Gates, both, before reporting done.** Current: `Total: 602  Passed: 602  Failed: 0`, 32 files.
  *(This line is copied into dispatches and goes stale every task — re-measure before quoting it.)*
- **Strip ANSI before counting suite headers.** `grep -c '^--- test-.*\.sh ---'` on raw output
  returns **0** on a healthy suite — the exact signal of the catastrophe the count detects. Use
  `sed $'s/\x1b\\[[0-9;]*m//g'` first.
- **bash 3.2 compatible.** No `declare -A`, no `grep -oP`.
- **Never pipe into a reader that can exit early** under `set -euo pipefail`. `grep -q` exits on
  first match without draining stdin. Use `grep -qF -- "$needle" <<< "$haystack"`.
- **`[ x = y ] && continue` is a `set -e` trap** as a loop body's last command. Use `if/then/fi`.
- **Both new tests are self-contained** — own `set -euo pipefail`, own `pass`/`fail`, `REPO` from
  `${BASH_SOURCE[0]}`. Model on `tests/test-provenance-origins.sh`. **Do not use the runner's
  `assert_*` helpers in them**: the runner does `set +e` before sourcing, so an undefined helper
  prints to stderr and contributes **no `FAIL:` token** — the test would report green on the defect
  it exists to catch. Measured in the previous wave.
- **Print `PASS:` / `FAIL:`, not `ok:`.**
- **Baseline discipline.** `.claude/` content changes trip sha256 tripwires; order is
  **commit, regenerate, commit**. Entry point is the **package**:
  `python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift <n>`;
  `python3 -m tools.kinglet_build.cli` silently no-ops with exit 0. `--dry-run` first, **use the
  tool's numbers**, report a disagreement rather than tuning the flag. A categorised file counts
  twice. `scripts/` ships into `.claude/scripts/`, so a new script **is** a payload change.
- **Every new tracked file needs a `provenance.tsv` row** — seven tab-separated columns.
- **Cite by content, not by line number.** Proven twice in the previous wave: a 29-line insertion
  invalidated every citation below it, and then the fix round's own edits moved the numbers it
  existed to repair.
- **A check's silence is only as wide as what it read.** Nine times across the previous two waves a
  probe's *shape* decided what it found, including three cases where an oracle was disjoint from the
  class it was meant to certify. **Say what each probe you write cannot see.**
- **A needle that passes for the wrong reason is worse than no needle**; **a red-first step that
  starts green is worse than none**.
- **A sentinel must not contain its own needle.**
- **One implementer at a time.**
- **Probe on a scratch copy:** `git archive HEAD | tar -x -C "$(mktemp -d)"`.

## Interfaces produced so far

**`tests/test-install-ownership.sh`** exists — self-contained, states A–D plus B2 and G, and it
defines (does **not** `export -f`) `own_row()`: takes a receipt path and a project-relative path,
prints the matching receipt line or nothing. Tasks 1b, 1c and 2 all extend this same file, which is
what makes the un-exported helper safe.

**`install.sh` has `owned_by_installer()`** — the conjunction `path == want && sha == have && origin
== toolkit`, failing closed on every malformed input tested.

**`uninstall.sh`'s classifier is a `case`**, not an `if/elif`: `user-modified` keeps, `toolkit` takes
the checksum test, **anything else keeps**. Task 1d must match that grammar rather than invent a
second one.

**The three readers of the origin column now disagree in grammar, and that asymmetry is load-bearing
for anything that touches them.** `uninstall.sh` is a `case` (`user-modified` keeps, `toolkit` takes
the checksum test, `*)` keeps). `scripts/studio-doctor.sh` is a `case` with the same three arms, but
its third arm **reports separately** rather than folding into the modified bucket — a read-only
diagnostic must not certify a row it cannot read. **`install.sh` is still an `if/else`** on
`"$origin" = user-modified`, so an unrecognised origin falls through to the sha test. Any task that
changes one of the three must state what it means for the other two.

`tests/test-studio-doctor.sh` is **runner-provided** — the runner's `assert_*` and `$REPO_DIR`,
neither defined locally. Standalone it exits 0 having asserted nothing. It now carries 31 assertions
and takes ~12 s.

Task 5 will produce `scripts/detect-pipeline.sh` printing one of `builtin`, `urp`, `hdrp`,
`urp+hdrp`.

## Tasks

| # | Task | Status | Commits | Notes |
|---|---|---|---|---|
| 1 | The receipt records ownership, not this run's writes | **done** | `e6116d0..6684165` | 1 fix round. Spec ✅, Quality Approved, 5 Minor. Added state B2 after proving the upgrade path was dead code; found the `uninstall.sh` data loss |
| 1b | `uninstall.sh` reads the origin column | **done** | `5650580..493db8a` | 1 fix round. Spec ✅, Approved, 4 Minor. Fails closed via `case`; guarded by a receipt row `install.sh` cannot produce |
| 1c | The scripts loop respects a user edit | **done** | `a192776..2f2b820` | 1 fix round. Spec ✅, Approved. State H now edits **two** scripts — one file cannot tell "keeps edits" from "keeps THIS file" from "keeps ONE file" |
| 1d | `studio-doctor.sh` reads origin, and stops piping into `head` | **done** | `cfc35b9..11ff9ee` | Reviewed after the fact — see below. Spec ✅, Quality Needs work: 1 Important + 6 Minor. **3 fix rounds**, and rounds 2 and 3 each closed a defect the previous round's own fix introduced. Round 1 ran on a fresh implementer because the original was killed |
| 2 | A kept backup is a file the installer owns | **done** | `c096d1b..a8acd49` | **No fix round** — Spec ✅, Quality Approved. The implementer refused the brief's literal Step 3 and implemented the spec; the review reproduced that the brief's shape *is* the defect. Suite 645 → 674 |
| 2b | The other file the installer keeps and does not record | **done** | `c4d36f3..15dfda4` | **No fix round** — Spec ✅ (criterion 13 clause 3 narrowed, disclosed), Quality Approved. Answered the open question by measurement; added I4/I5 beyond the plan, and I4 is the only state that discriminates the receipt arm. Suite 674 → 738 |
| 2c | The two writers that overwrite without asking | open | — | Inserted 2026-08-13 from Task 2b's review. **Data loss**, D10's one exemption, and the wave created the aggravating half |
| 3 | The dry-run guard, three oracles | open (brief pending) | — | The third oracle is the task's reason to exist |
| 4 | The `.gitignore` announcement says what will happen | open (brief pending) | — | Turns Task 3's guard green |
| 5 | One pipeline detector, and Option B states its costs | open (brief pending) | — | `urp+hdrp` display and skill routing is the implementer's call |
| 6 | Whole-wave verification | open (brief pending) | — | Criterion 6 re-run, not cited |

## What Task 1 found, and the controller error it exposed

**The implementer found a data-loss defect its brief did not cover and reported it rather than
fixing it.** `uninstall.sh` deletes user-edited `.claude/` files without `--purge`. Reproduced twice
— by the implementer and independently by its reviewer — with the plan output naming the file under
*unchanged since install* while `--purge`'s help text promises the opposite. **Now Task 1b.**

**It added state B2 because it proved the test's own coverage was a lie.** States A–D all install the
*same* toolkit twice, so the previous-receipt half of `owned_by_installer` was dead code — shown by
mutation: replace that branch with `return 1`, excise B2, and the file still passes. B2 installs a
scratch "previous version" first, so the upgrade path is actually exercised. Its reviewer confirmed
the dead-code claim independently rather than accepting M1.

**The predicate fails closed on 16 inputs the four states do not cover** — malformed rows, a CRLF
receipt, an empty argument, a broken symlink, a path that is a directory — with the only two
fail-opens being the two D1 explicitly authorises.

### The controller's error, which is the wave's own subject in its most basic form

**The controller's review dispatch accused the implementer of an unflagged widening it did not
make.** While measuring, the controller read `install.sh`'s sticky `user-modified` block, saw it in
the region it was reading, and **inferred authorship from proximity** — without running `git log -S`
or `git blame`. That block is `c2d27f1f`, 2026-08-03, nine days before this wave and already on
`main`.

Ten times across three waves a probe's *shape* decided a finding. This one is the floor of that
class: **no probe was run at all.** The reviewer refuted the premise in its first section and
answered the questions anyway.

## Carried to Task 3 — its oracle must expect a subtraction that did not exist before

The dry run's scripts line now **overstates the real run's `WRITTEN`** by the number of kept scripts:
`76 + 9 − 4 = 81`, with `keep 4 file(s) you modified` printed separately. Internally consistent, and
identical in shape to the pre-existing payload line — but Task 3's dry-run/real-run oracle did not
have to model that subtraction before Task 1c, and now does.

## A finding that becomes its own task — the runner cannot see a test file die mid-way

Measured by Task 1c's reviewer with two synthetic files:

```
--- test-dies-clean.sh ---     PASS: only assertion
  FAIL  exited 1 without reporting a failure          ← backstop fires
--- test-dies-midway.sh ---    PASS: first assertion
FAIL: an unrelated red                                 ← dies here, silently
```

`run-tests.sh`'s backstop is `[ "$test_rc" -ne 0 ] && [ "$file_fail" -eq 0 ]`. A file that printed
one `FAIL:` and *then* died satisfies neither branch. **The death is invisible, the suite is red for
an incomplete reason, and every assertion after the death reads as absent rather than unrun.**

This is not hypothetical here: Task 1c's `sha_of` trap killed the test file mid-state, and the
anti-"keep everything" guard printed *nothing* while the exit status was already 1 from something
else. The guard read as absent rather than red.

Same family as the previous wave's finding that the runner is blind to python results in both
directions. **A test file needs a completion sentinel** — the runner has no way today to tell a
deliberate `exit 1` from a death, and that is the discriminator it lacks.

## Task 1d — reviewed after the fact, and what that cost

The implementer was killed by the operator mid-report, after committing `6a2793e`. No implementer
report exists and none can be written now. `.superpowers/sdd/…/task-1d-no-report.md` stands in its
place: a controller-written account of what was measured after the fact and, more usefully, of the
four things the controller did **not** know. That file is what the review was dispatched against.

**All four are now answered, and none of them the way the controller framed them.**

1. **There was no pipe-count discrepancy.** Brief said two, commit title said four, commit body said
   "both list printers" — three numbers counting three different sets, all three correct.
   `git show cfc35b9:scripts/studio-doctor.sh | grep -n '|[[:space:]]*head'` → **four**. The brief's
   own anchor was `grep -n 'head -5'`, which *cannot* find the other two. **The plan was narrower
   than the spec it cites** (criterion 12: "no `| head` remains in it"), and per Global Constraints
   the spec wins and the plan is the bug. Recorded below.
   The two the brief missed were the more dangerous ones: `SRV=$(printf … | sed … | head -1)` is a
   **bare assignment**, where a 141 kills the script. Measured in isolation: N=100 died 0/10; N=1000,
   5000, 200000 died **10/10**.
2. **The catch-all's classification was right and its message was false.** See the next section — it
   became the round's only Important finding.
3. **The 13 new assertions are real.** The reviewer emulated `run-tests.sh`'s loop exactly: 27 PASS,
   14 pre-existing + 13 new, accounting for 628 → 641 precisely. Six mutations, each producing
   targeted reds; M1 and M2 separate cleanly.
4. **SIGPIPE reproduces in both directions.** Pre-task at `cfc35b9`, 1500-row lists: **29 of 30 runs
   exited 141** with no summary. Post-task: 10/10 completed. The fix is structurally immune, not
   lucky — `awk '…' <<< "$1"` has no writer process and no `PIPESTATUS` for `pipefail` to promote.

**The controller's framing was wrong on the one point it was most confident about.** It wrote that
"two or more replacements were made that nothing has examined, and the discrepancy itself is
unexplained." There was no discrepancy. The controller had the brief's anchor in front of it and did
not notice that the anchor could not have found what it was accusing the implementer of hiding. Same
class as this wave's other controller error — a judgement made from proximity instead of a probe.

**Also measured, and it corrects the plan a second time:** Task 1d Step 4 says `scripts/` ships into
`.claude/scripts/` so expect baseline drift. Wrong for this file. `migration/baseline-inventory.json`
covers `.claude/**` (143 paths) and `templates/` (10) only; `grep -c 'studio-doctor'
migration/baseline-inventory.json` → **0**. The repo has no `.claude/scripts/` tree — the copy happens
at install time into the *user's* project. Zero drift was correct, for a reason the plan does not give.

### The Important finding, and why it is the wave's own thesis again

`studio-doctor.sh`'s new catch-all filed unreadable-origin rows under
`WARN N file(s) modified since install — install.sh will keep your versions:`. **That sentence is
false for those rows.** `uninstall.sh`'s classifier is a `case`; **`install.sh`'s upgrade scan is an
`if/else`** on `"$origin" = user-modified`. An unreadable origin is `!=`, falls to the sha test, the
sha matches, the file never enters `MODIFIED_FILES`, and the payload loop overwrites it. Measured:
origin mangled to `toolkit ` (trailing space), bytes untouched, toolkit copy bumped → no
`keeping yours` line, file overwritten, row rewritten clean `toolkit`.

**The diff introduced the false claim along with the branch** — before it, the file was silently
counted verified and no sentence was printed about it at all. A diagnostic asserting something about
another program's behaviour that the other program does not do is exactly what Task 1d exists to end.

Fixed in round 1 by option (a): the catch-all got its own counter, its own report line, and two
continuation lines stating only what is true of both readers. `install.sh will keep your versions`
now covers only the two branches where it holds.

### Round 1 — three findings, all ADDRESSED, and the probes that established it

**Round 1 ran on a fresh implementer, not a resume.** The loop's rounds 1–3 resume the original
because its context is intact and cheap; here the original had been killed, so there was nothing to
resume. Recorded as a deviation, not a precedent.

The re-review deliberately used probe shapes the implementer had not:

- **The row class the implementer used to justify its wording.** The implementer argued its new
  sentence avoids promising an overwrite "because the receipt also carries rows outside the payload
  tree (`.mcp.json`, `MCP-SETUP.md`)" — but measured only on `.claude/rules/*`. The re-review built
  four fixtures on those two paths and confirmed the claim holds, *and* found something new (below).
- **M-2's derived count is a mirror, and mirrors drift.** The review had suggested
  `grep -vc '^#' "$RECEIPT"`; the implementer measured it as **88 against the doctor's 87** — it keeps
  the `path` header — and wrote an awk mirroring the doctor's own skip list instead. The re-review
  then found three receipt shapes where even that mirror disagrees: a **tabs-only line**, `\t# …`,
  and `\tpath\t…`. Cause: the doctor reads with `IFS=$'\t' read -r`, and tab is IFS whitespace, so
  leading tabs are stripped before its `case`; `awk -F'\t'` sees an empty `$1` with non-zero `NF`.
  **Every drift makes the positive assertion RED, never vacuous** — awk's skip conditions are each a
  superset-or-equal of the doctor's, so the mirror cannot under-count and the "both pass while the
  derivation is wrong" failure is unreachable.
- **The `WARN ` anchor is absent on a TTY.** `warn()` emits `${YELLOW}WARN${NC}`; under a real pty the
  bytes are `^[[0;33mWARN^[[0m 1 file(s)…`. The test never sees it because `$( … 2>&1 )` is always a
  pipe, so `[ -t 1 ]` is false and the colour vars are empty. If that ever changed the assertion goes
  **red, not vacuous** — the safe direction.

**Assertion accounting, checked rather than assumed:** 31 call sites → 31 result lines, PASS tokens
31, FAIL 0, no `command not found` / unbound-variable / syntax-error lines, helpers used ⊆ helpers the
runner defines. The origin block went 7 → 11 lines, **+4**, reconciling 641 → 645 exactly.

**No new breakage from the fix diff**, checked specifically: no `declare -A` / `grep -oP`, no added
pipe into an early-exiting reader, no `&& continue` as a loop body's last command, counters written
`X=$((X + 1))` rather than `((X++))` so a zero result cannot abort under `set -e`, and no added line
carrying a `PASS`/`FAIL`/`SKIP` token. Nothing outside the doctor and its test reads
`Install intact` / `modified since install`.

### Rounds 2 and 3 — each closed a defect the previous round's own fix introduced

**That is the finding of this task, and it is worth more than either fix.** Round 1 corrected a false
sentence and round 2's correction of *its* leftovers wrote a new false sentence. Neither implementer
was careless; both were writing about a program whose behaviour they had measured, and both
generalised one measurement one step too far. **The fix loop is not overhead here — it is the only
thing that caught either.**

**Round 2, two items.** The long-list assertion was *proven* vacuous rather than argued: mutation E7
prefixes a digit (`1500 → 11500`) and the unanchored needle stayed PASS against a line reading
`11500 file(s) modified since install`. And N-1's over-general clause was reworded.

Round 2 found something the round could not have anticipated. **The missing-files line cannot take
the same anchor**, because the doctor prints it through `fail`, so its prefix is the literal token
`FAIL` — and `assert_contains` echoes its needle on failure while `run-tests.sh` tallies with
`grep -cE '(^|[[:space:]])FAIL(:|[[:space:]])'`. A `FAIL`-carrying needle makes the test count itself
as a second failure. That is the file's own *"a sentinel must not contain its own needle"* rule, one
level in: the rule was written about assertion **messages**, and this is a needle. Measured by the
re-review: the rejected form, forced to fail, tallies **2** and moves the total 31 → 32. **The
direction is inflation of an existing failure, never a false green** — worth recording precisely,
because the near-miss reads scarier than it is. The replacement (an `awk` extraction compared with
`assert_eq`) was then attacked with that same trap — the extracted field made literally `FAIL` — and
held, because the runner's regex needs a delimiter *after* the token and end-of-line does not supply
one. It fails closed on zero matches, on two, and on a changed line shape.

**Round 2's verification went past both sides' probes.** The re-review re-ran the **original E7 shape**
— the case the round existed to close, and *not* the appended-digit mutation the implementer chose —
and both long-list assertions went red. Then it attacked the **severity token** rather than the digits
(`warn` → `pass`), which no count mutation reaches, and that went red too. So the `WARN ` anchor buys
something beyond digit mutations, which the implementer's own honesty note had left open.

**Round 3: round 2's fix put a new false measurement claim into the file.** Its comment stated that
all three fixtures were run "each with the toolkit's own copy bumped so an overwrite would show" and
concluded *"even the two root files do not agree."* **The precondition was false for the `.mcp.json`
fixture and could not have been true** — `.mcp.json`'s reference copy is not a shipped file but the
heredoc at `grep -n 'cat > "$MCP_JSON_REF"' install.sh`, regenerated byte-identically every run. The
comparison moved two variables. Bump the heredoc between installs and the divergence vanishes:

```
[jsonA0  ] origin=clean   bumpref=no  -> KEPT
[jsonB0  ] origin=mangled bumpref=no  -> KEPT      ← round 2's observation
[jsonAref] origin=clean   bumpref=yes -> KEPT
[jsonBref] origin=mangled bumpref=yes -> DROPPED   ← identical to MCP-SETUP.md
```

Same rule, same `$4 == "toolkit"` gate, one variable apart. The implementer also ran the control it
had skipped: clean origin + drifted bytes **also** drops the row, because `$2 == have` fails first —
so round 2's `jsonC` proved nothing about the column and had been reported as though it did. It said
so in those words.

**A load-bearing conclusion drawn from an uncontrolled comparison and then recorded in-file as
measurement is I-1's shape exactly** — the file's own comment asserting something the measurement does
not support. The claim was **withdrawn, not softened**, and the drifted-bytes non-result recorded so
the next reader does not reach for that control again.

**Controller ruling: no fourth review was dispatched.** Round 3 is comment-only — verified directly,
not assumed: `git diff 99a29b9..11ff9ee` touches one file, contributes **zero** non-comment added or
removed lines, changes no `warn`/`printf`/`pass`/`fail` line, and the withdrawn phrase is absent from
`scripts/`, `.claude/`, `install.sh` and `uninstall.sh`. Its factual content rests on **two
independent measurements that agree** — the re-review's and the implementer's own rerun, run
separately and reaching the same four-row table. That is more corroboration than most of this wave's
claims carry. Recorded as a ruling so it is auditable, not as a default.

**One overstatement noted and left:** the implementer's report says "there is no `.mcp.json` in the
toolkit tree at all". `git ls-files` finds two, under `spikes/platform/clients/` — spike artifacts,
not payload, and not `$MCP_JSON_REF`'s source, so the claim is true where it matters and the shipped
comment scopes it correctly ("no shipped copy"). Noted because it is the same one-step-too-far
generalisation this task produced three times, caught here in a report rather than in a file.

## Task 2 — the implementer refused the brief, and the review proved it right

**The brief's Step 3 said to write the receipt row "in the branch that keeps the file". That
instruction is the defect.** Writing there records **authorship**, and the spec's D1 governs this
whole class explicitly: *"Ownership is a property of the file, not of the run that happened to create
it."*

The implementer measured the consequence before writing anything, and the reviewer then reproduced it
with a **different probe shape** — the implementer had narrowed its own condition; the reviewer
implemented the brief *literally*, relocating the `printf` into the keep branch so the only difference
from the shipped code was where the write lives:

| probe | result |
|---|---|
| brief-literal, `--with-mcp` → plain install → `uninstall.sh --yes`, non-git fixture | run 1 row present; **run 2 receipt has no `Packages/` row**; `.bak` still on disk after uninstall |
| brief-literal, `--with-mcp` twice | run 2 prints `already in manifest.json.`, row gone |
| the shipped test file against a brief-literal `install.sh` | **151 PASS / 2 FAIL**, both the second-install assertions |

The chain, each link measured separately: `add_manifest_dependency` returns early once the package is
present (`grep -n 'already in manifest.json."' install.sh`); a plain run never calls it at all, both
flags defaulting to `0`; and the receipt is rebuilt from scratch every run
(`grep -n 'RECEIPT_TMP=\$(mktemp)' install.sh`). **So the brief's shape reinstates the spec's defect #2
one run later.** One piece of apparent counter-evidence had to be disposed of first: a plain run *does*
print `ok com.unity.inputsystem already in manifest.json.`, but that comes from an advisory check, not
from `add_manifest_dependency`.

**The third plan bug, and the third time an implementer found one by checking instead of assuming.**
Left in the plan as written, corrected here — editing a brief after its task has run rewrites the
record of what the implementer was told.

**The second deviation was also correct, and worse than it sounds.** The spec says the backup comes
from `--with-mcp` **or** `--with-input-system`; the plan names only the first. Both can reach the keep
branch in one run, so the implementer writes the row once *after* both callers. The reviewer built the
duplicate directly and found the receipt carrying two rows for one path with different checksums —
whereupon `uninstall.sh`, whose classifier is per-row, puts the stale one in `MODIFIED` and the fresh
one in `TO_REMOVE` and prints:

```
  keep     1 file(s) you modified
             Packages/manifest.json.bak
 ok  Removed 88 file(s).
after uninstall: .bak GONE
```

**It says "keep" and removes the file** — D8's exact failure shape, arriving through a receipt instead
of through a loop.

**Red-first was real, and F's pre-existing green is real coverage.** Reproduced by putting `c096d1b`'s
`install.sh` under `a8acd49`'s test file: 149 PASS / 3 FAIL, byte-identical to the reported failures.
All 9 of state F's assertions were green in the red run, including both preconditions that could have
made it vacuous — its `git ls-files --error-unmatch` check, and its branch discriminator asserted in
**both** directions.

**E3 fires, and it is the only state that catches its direction.** The reviewer's mutation — claim by
existence rather than by provenance — reddened all three E3 assertions and **left F green**, which is
what isolation looks like. The implementer's own mutation had reddened F and G too, so it had not
isolated anything. E3 ends `FAIL: E3: uninstall.sh deleted Packages/manifest.json.bak, which the user
wrote` — the fail-closed direction the spec's Risks section demands.

## Task 2b — the wave's thesis failing in the wave's own subject, for the second time

**Task 2b itself was clean.** Spec ✅, Quality Approved, no fix round, and its review verified the work
with three mutation shapes the implementer never ran. What it found while doing so is the wave's most
serious finding.

**The open question the brief could not answer, answered by measurement.** `owned_by_installer` tries a
**reference copy** first and the **previous receipt** second, and `CLAUDE.md.generated` is generated per
project — it has no fixed toolkit source. The implementer passes `''`, so arm 1 is skipped **by
construction** rather than by luck, which is the distinction Task 1d's `.mcp.json` finding made
necessary. It then used `install.sh`'s own existing branch variable for the other half.

**The reviewer verified both halves are load-bearing by deleting each, not by repeating the
implementer's tracing:**

| deletion | result |
|---|---|
| drop the receipt half | **2 FAIL, state I4 only** |
| drop the branch half | **8 FAIL** — degenerates to "no row ever", identical to red-first |

**I4 is the single state that discriminates the receipt arm — and the plan's four-state table did not
have it.** The implementer added it beyond the brief. Without it, that disjunct would have been the
`.mcp.json` failure one file over: a never-consulted arm wearing a safety argument. This is the exact
trap the dispatch flagged, and it was avoided by an implementer widening its own task.

**Criterion 13's third clause was met only under a narrowed reading, and the narrowing was disclosed
three times** — in the report, in a `# WHAT THESE STATES CANNOT SEE` block, and in the plan-disagreement
section. The reviewer's judgement, which is the right one: the reading is the only implementable one
**and** the honest statement of it is that *criterion 13 as written requires the clobber to be fixed*.
Which is now Task 2c, and criterion 13 carries an amendment saying so.

### The Critical finding: two writers destroy user work, and this wave taught them to claim otherwise

```bash
mv "$TMP_MD" "$PROJECT_DIR/CLAUDE.md.generated"     # the separate-file branch
cp "$MANIFEST" "$MANIFEST.bak"                       # add_manifest_dependency, per --with-* flag
```

Reproduced on **three independent paths**:

1. **The workflow the installer prescribes.** Its own summary says *"2. Fill in the `FILL:` markers in
   `CLAUDE.md.generated`, then merge what you want into your own `CLAUDE.md`."* Fill the 9 markers,
   reinstall — back to 9 unfilled. **The edit survives zero reinstalls.** `c2d27f1f` was fixed on
   2026-08-03 because an edit survived exactly *one*.
2. **A first install ever.** A user who wrote their own `CLAUDE.md.generated` and has never run this
   installer loses it — and the receipt then records it as `toolkit`.
3. **The backup.** `--with-mcp`, edit the kept `.bak`, then `--with-input-system` — the `cp` runs again
   and the edit is gone.

**The destruction pre-dates the wave. The claim does not.** Before Tasks 2 and 2b there were no receipt
rows for these paths, so the upgrade scan never named them. Now both have rows, so both land in
`MODIFIED_FILES`:

```
warn 1 installed file(s) have local edits — keeping yours:
       CLAUDE.md.generated
 ok  Installed 85 file(s).
warn CLAUDE.md exists and has no generated markers — wrote CLAUDE.md.generated instead.
warn Yours was not touched. Merge by hand, or add the markers to let us refresh in place.
```

**Three surfaces speak about that file and all three say the opposite of what happens** — the dry-run's
`is NOT touched`, the upgrade scan's `keeping yours`, and `Yours was not touched.` one line after the
`mv`. That is **D8's exact failure shape, twice, created by the two tasks that were closing D8's
class.** Neither implementer erred: it is the unavoidable consequence of adding a correct row on top of
an incorrect writer. **It is still a regression the wave now owns**, and Task 2's own review did not
catch its half.

**Controller ruling: fixed in this wave, as Task 2c.** D10 closed the wave *"unless it is data loss in
shipped software."* This is data loss, in shipped software, in the workflow the installer itself
prescribes, on three paths. Deferring would ship two *fresh* instances of the defect the wave exists to
eliminate, and criterion 13 could not honestly be signed off. **The exemption is now spent.**

## Deferred and parked findings

### From Task 2's review — four, one of which became Task 2b

12. **`CLAUDE.md.generated` is the same defect, second instance — now Task 2b.** Created by the
    installer, kept, announced (`warn CLAUDE.md exists and has no generated markers — wrote
    CLAUDE.md.generated instead.`), unrecorded, un-removable. Measured: the receipt's non-`.claude/`
    rows are `.mcp.json` and `MCP-SETUP.md` only, and the file survives a full uninstall. **Not
    deferred — promoted**, because D2's own sentence applies to it verbatim.
13. **A read-only `Packages/manifest.json.bak` aborts the whole installer, with no receipt written at
    all.** `cp "$MANIFEST" "$MANIFEST.bak"` under `set -euo pipefail` dies on `Permission denied`
    *after* the payload is written, and a run with no receipt is the one state that makes
    `uninstall.sh` refuse to run. Reproduced with `chmod 444`. Pre-existing — that `cp` is untouched by
    Task 2 — and **reachable on a real workflow this toolkit targets**: Perforce keeps files read-only
    until checked out, and console projects live there. The sharpest thing Task 2's review produced.
14. **The `cp` clobbers a user's own `.bak` before anything asks whose the file is**, and Task 2 has
    changed the consequence's shape: the user's file at that path is now *deleted* by the subsequent
    uninstall, not merely overwritten. Measured, with a control run proving the destructive step is the
    pre-existing `cp` and the new code is fail-closed wherever it can be. **Belongs in the spec's
    out-of-scope list**; E3 covers only the plain-install half and the test header says so.
15. **`MANIFEST_BAK_KEPT` is a memory one statement can invalidate.** `add_manifest_dependency`'s
    failure arm restores the backup over the manifest (`grep -n 'mv "\$MANIFEST.bak" "\$MANIFEST"'
    install.sh`), **deleting a `.bak` an earlier caller kept**, while the flag stays `1`. `sha_of` then
    hashes a path that no longer exists and — because the substitution sits inside a `printf` argument,
    where `set -e` does not reach — the row is written with an **empty checksum**. Demonstrated on a
    scratch copy. **Latent, not live**: with the shipped flags the second caller's `sed` cannot fail
    after the first succeeded. Downstream it is fail-closed. A `[ -f … ] &&` conjunct closes it for
    free and would make the site match the other four, each of which hashes a file it just wrote or
    just proved present.
16. **No state covers "the user edits a backup we own, then reinstalls"** — the spec's Risks section's
    fourth case, the one it calls easy to get wrong, asserted as state D for both other files. The
    behaviour is correct (measured: `keeping yours`, no row, uninstall leaves the user's bytes); it is
    the *assertion* that is missing. Minor because the mechanism is `owned_by_installer`'s `$2 == have`
    conjunct, which states C and D already guard through the shared helper.

**Also confirmed clean, worth recording so nobody re-checks it:** `uninstall.sh` removes a two-segment
project-relative path (proven by hand-appending a row to a real receipt *before* any `install.sh`
change existed), never removes `Packages/manifest.json` itself, and never prunes `Packages/` — both its
sweep and its empty-directory prune are scoped to `$CLAUDE_DIR`.

### From Task 1d — round 2's scope, and four deferred

**Round 2 carries two items, both measured rather than argued:**

1. **The long-list assertion is demonstrably vacuous, in the same file as the one M-1 fixed.** The
   re-review's mutation E7 prefixes a digit to the count (`1 → 11`, `1500 → 11500`). The *anchored*
   origin assertion goes red; `"$TSD_LONG_N file(s) modified since install"` **stays PASS against a
   line reading `11500 file(s) modified since install`**. M-1's text named the origin block; M-1's
   content is "an unanchored count assertion survives the miscount it exists to detect", and one
   instance is still green under a live demonstration of that miscount. Deferring it would leave a
   provably vacuous assertion in the suite *with the proof already on file*. One token.
2. **N-1 — the replacement sentence over-generalises for the row class that justified it.** Anchor:
   `grep -n 'depends on its bytes, not on that column' scripts/studio-doctor.sh`. True for `.claude/**`
   payload rows. For `.mcp.json` / `MCP-SETUP.md`, install.sh's write is **create-only** (`[ ! -f ]`),
   so the file outcome is identical in both byte states — it does not depend on the bytes — and the
   column *does* decide something. A hedge that overstates uncertainty, so it cannot cause I-1's harm;
   one clause.

**Deferred to the ledger, not fixed:**

3. **An unreadable origin column silently drops the `.mcp.json` / `MCP-SETUP.md` ownership row on the
   next upgrade.** Measured by the re-review on four fixtures: `owned_by_installer`'s `$4 == "toolkit"`
   test fails on a mangled origin, so on a real upgrade the row is dropped, the file stops being owned,
   and **`uninstall.sh` will never remove it again**. The identical fixture with a clean origin keeps
   its row. Pre-existing `install.sh` behaviour, outside Task 1d — but it means a future task that
   makes install.sh's upgrade scan a `case` must revisit `owned_by_installer`'s gate too, not only the
   classifier. New information, and the sharpest thing this task produced.
4. **M-3 — the static `| head` guard is shaped like the symptom, not the class.** Anchor:
   `grep -n 'TSD_HEAD_HITS' tests/test-studio-doctor.sh`. The file itself is confirmed clean —
   `| cut -c1-70` drains (5/5 at 3 MB), the `awk … exit` reads a file argument not a pipe, every
   `grep -q` is on a file or a here-string. The *guard* would not notice `| grep -q`, `| sed -n '…q'`
   or `| read` arriving later. One-line widening, whenever.
5. **M-4 — the in-file determinism claim says 30/30 where the measurement is 29/30** at N=1500 on this
   host. Fine as a regression guard; the house convention is to write the measured number.
6. **M-5 — the same shape survives in sibling shipped scripts, one of which Task 5 will edit.**
   `grep -n 'head -1' scripts/generate-claude-md.sh` → `name=$(sed -n '…' "$asmdef" 2>/dev/null |
   head -1)` under `set -euo pipefail` with **no `|| true`** — the serverInfo shape exactly, on a file
   that can carry many `"name"` matches. `scripts/detect-missing-refs.sh` and
   `scripts/validate-asmdefs.sh` carry several `echo "$x" | grep -q …`.
   `scripts/validate-architecture.sh`'s many `| head -1` are **safe** — each ends `|| true` inside the
   substitution. **Task 5's dispatch must carry this**: it edits `generate-claude-md.sh`.
   It also answers "does the fix cover the class" honestly: it covers the file, not the repo.
7. **M-6 — cost and cleanup.** The file went **3.3 s → 12.1 s** through the runner, now the single most
   expensive test file (1500 files + 3000 receipt rows + two extra installs). Acceptable against the
   >150 s budget. `TSD_LONG` / `TSD_ORIGIN` leak 1500 files into `/tmp` if the block dies before its
   `rm -rf`; the file's existing convention is the same, so consistency rather than regression.

### From Task 1d rounds 2 and 3 — four more, all deferred

8. **The long-list fixture is symmetric, so that block cannot tell its two lists apart.** Both counts
   are 1500 by construction; the re-review swapped the two counters in the doctor and **both long-list
   assertions stayed green**. The file as a whole is not blind — the *origin* block's fixture is 1
   modified / 0 missing and its assertion went red — and the long-list block's stated purpose is the
   SIGPIPE regression, not counting accuracy. Fix is one line: make the fixture `N` and `N+k`.
9. **The doctor's two unreadable-origin continuation `warn` lines are asserted by nothing**, in any
   revision. The block's header line is anchored; the two sentences under it are not — so **the suite
   would not notice if the sentence rounds 2 and 3 both worked to make true were deleted.** Same class
   as M-3: the guard is shaped like the symptom.
10. **`.mcp.json`'s reference copy is a heredoc, not a file** — so `owned_by_installer`'s
    reference-copy arm short-circuits for it on every run where install.sh's heredoc has not changed,
    and the receipt is never consulted. **A constant reference copy can mask a receipt problem
    indefinitely.** Goes with item 3 above for whichever future task makes install.sh's upgrade scan a
    `case`: the reference-copy arm masks the column read for one of the two root files and not the
    other.
11. **The `FAIL`-token tally trap is inflation, not concealment.** Recorded with its direction because
    the direction is the whole of its severity: a `FAIL`-carrying needle makes one failing assertion
    tally as two and moves the file's total by one. It cannot produce a false green. The repo already
    documents this rule for assertion *messages*; it now also applies to needles.

### Two plan bugs Task 1d's review found — the spec was right both times

- **Step 2's anchor undercounts its own class.** `grep -n 'head -5'` finds two; criterion 12 says "no
  `| head` remains", which is four. Global Constraints say the spec wins; the plan is the bug.
- **Step 4's baseline expectation is wrong for `scripts/`.** It predicts drift; the correct expectation
  is zero, because the baseline inventory covers `.claude/**` and `templates/` only and `scripts/` is
  copied into the *user's* project at install time.

Both left in the plan as written, with this ledger entry as the correction — editing a brief after its
task has run rewrites the record of what the implementer was actually told.

### From Task 2b's review — three, none promoted

17. **`.gitignore` is a third unrecorded instance of D10's class.** `--variant bare`: the run prints
    `==> Created .gitignore`, keeps it, writes no row, and it survives uninstall carrying only Kinglet's
    four entries. Debris, **not** data loss, so D10's rule holds and this goes to the second wave —
    with one exception: **Task 3's dry-run guard will see it**, because a created file is exactly what
    its first oracle is for, and Task 4 owns the `.gitignore` announcement. If closing it falls inside
    those diffs naturally, close it there; do not widen them to reach it.
    *(A fourth candidate, `CLAUDE.md` on the `new` branch, was examined and rejected: `uninstall.sh`
    states the exclusion — `Left alone: CLAUDE.md, docs/, and anything you wrote.` — so it is stated
    policy, not silent debris.)*
18. **The dry-run line names the wrong subject.** `grep -n 'yours exists and has no markers, so it is
    NOT touched' install.sh` prints the label `CLAUDE.md.generated` followed by "it is NOT touched",
    which is false about the file it names — its intent is "your `CLAUDE.md`". **Task 3's ground**, and
    its third oracle only catches it if that fixture carries a pre-existing `CLAUDE.md.generated`.
    Carry this into Task 3's dispatch.
19. **`stat -c '%a'` is GNU-only**, now at a fifth site. On BSD `stat` the row records `644` for a
    `600` file. Nothing reads the mode column (`uninstall.sh` destructures it as `_mode`), and mirroring
    the four existing sites beats introducing a second idiom. **For the macOS pass.**

### From Task 1's review — five Minor, four closed in round 1

1. **`$4 == "toolkit"` has no mutation coverage** — dropping it while keeping `$2 == have` leaves the
   file green. **Unfalsifiable by construction, not merely untested**: `install.sh` emits no
   non-`toolkit` row for either path, so no fixture can build a receipt where the conjunct changes
   the answer. It guards inputs that do not exist yet — a hand-edited receipt, Task 2's project-root
   rows. Now named in the test's *what this cannot see* block.
2. **The receipt-still-present enumeration omitted `mv "$CLAUDE_DIR" "$BACKUP_DIR"`** and read as
   exhaustive. Conclusion unchanged — that path runs only in `foreign` mode, which is defined by the
   receipt's absence — but it is now named with its disposition attached.
3. **A shipped comment blessed the `uninstall.sh` defect** as *"defensible"*. Reworded: it is a live
   defect, and the paragraph now names itself as the one to revisit when the classifier is fixed.
4. **`own_row()` is defined, not exported.** Report wording; holds because Task 2 extends the same
   file, breaks silently if that ever changes.
5. **The `cat >` over `cp` reasoning holds only at umask 022.** On umask 002 both project-root files
   land 664 while the row hardcodes 644. Pre-existing and harmless — `uninstall.sh` never reads the
   mode column — but the comment's reasoning is overstated. **Not fixed.**

### The sticky trade is real, unstated, and pre-existing — for the ledger, not this wave

Measured by Task 1's reviewer. `user-modified` is **permanent and survives a revert**: after the user
restores an edited file to the toolkit's exact bytes, the next install rewrites the row as
`user-modified/<toolkit sha>`, and a toolkit v2 shipping new bytes for that file **never reaches the
project** — while a control project that never edited it does receive v2. The run prints
`keeping yours` about a file with no local edits.

Defensible trade — never silently clobber — but `install.sh` states only the benefit, and there is no
supported way back except deleting the row by hand. **`c2d27f1f`'s code, not this wave's.**

## Carried from the previous wave — not this wave's scope

The shipped-citations ledger records twelve spin-out items. Six are closed by this plan. The
remainder, still open:

- the runner is blind to python results in both directions — 1443 results reach the total as one PASS;
- five unguarded derived counts in `docs/GETTING-STARTED.md`;
- no guard resolves `file:line` citations in `tests/` and `docs/` against the tree;
- the unguarded closing `---` frontmatter fence across all skills;
- `unity-planning` states no fork threshold and labels one branch "(recommended)" unconditionally;
- `scripts/studio-doctor.sh` says *"run `install.sh`"* at six sites without saying from where —
  **and the controller's original ruling on it rested on a premise the recommended install `rm -rf`s**;
- **the surface criterion applied to hooks and `scripts/` — the owner's call**, because it decides
  what leaves the pool;
- P1 and P3, the two parked owner design calls.
