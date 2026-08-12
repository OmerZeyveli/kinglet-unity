# Ledger — plan: `docs/superpowers/plans/2026-08-12-installer-owns-what-it-writes.md`

Spec: `docs/superpowers/specs/2026-08-12-installer-owns-what-it-writes-design.md` at `2d081f0`.

- **Branch:** `pioneer/installer-ownership`, cut from `main` at `c5280c4`.
- **Base commit for the whole-branch review:** `c5280c4`.
- **Gates:** `bash tests/run-tests.sh` (timeout above 150000 ms; ANSI-stripped `--- test-*.sh ---`
  header count must equal `ls tests/test-*.sh | wc -l`) and `bash scripts/check-provenance.sh`
  (must end `provenance OK`).
- **Reports:** `.superpowers/sdd/2026-08-12-installer-ownership/` (gitignored).

## RESUME HERE

**Tasks 1, 1b and 1c are done and closed.** **Task 1d is next.**

The wave keeps growing because each task's review finds the next instance of one root cause. The
spec now carries **nine decisions**, and the tally is: the origin column is written in four places
and, before this wave, read in none. Task 1 fixed the project-root rows, Task 1b fixed
`uninstall.sh`, **Task 1c fixes the scripts loop — which does not check `is_modified` at all, so the
run prints `keeping yours:` naming a file it overwrites in the same output** — and Task 1d fixes
`studio-doctor.sh`, the last reader, which also carries two `printf | head` SIGPIPE traps.

Suite: **628/628**, 32 test files, `provenance OK`.

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

Task 5 will produce `scripts/detect-pipeline.sh` printing one of `builtin`, `urp`, `hdrp`,
`urp+hdrp`.

## Tasks

| # | Task | Status | Commits | Notes |
|---|---|---|---|---|
| 1 | The receipt records ownership, not this run's writes | **done** | `e6116d0..6684165` | 1 fix round. Spec ✅, Quality Approved, 5 Minor. Added state B2 after proving the upgrade path was dead code; found the `uninstall.sh` data loss |
| 1b | `uninstall.sh` reads the origin column | **done** | `5650580..493db8a` | 1 fix round. Spec ✅, Approved, 4 Minor. Fails closed via `case`; guarded by a receipt row `install.sh` cannot produce |
| 1c | The scripts loop respects a user edit | **done** | `a192776..2f2b820` | 1 fix round. Spec ✅, Approved. State H now edits **two** scripts — one file cannot tell "keeps edits" from "keeps THIS file" from "keeps ONE file" |
| 1d | `studio-doctor.sh` reads origin, and stops piping into `head` | open (brief pending) | — | **Inserted.** Last reader; plus two documented SIGPIPE traps; spec D9 |
| 2 | A kept backup is a file the installer owns | open (brief pending) | — | Extends Task 1's test |
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

## Deferred and parked findings

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
