# Ledger — plan: `docs/superpowers/plans/2026-08-12-installer-owns-what-it-writes.md`

Spec: `docs/superpowers/specs/2026-08-12-installer-owns-what-it-writes-design.md` at `2d081f0`.

- **Branch:** `pioneer/installer-ownership`, cut from `main` at `c5280c4`.
- **Base commit for the whole-branch review:** `c5280c4`.
- **Gates:** `bash tests/run-tests.sh` (timeout above 150000 ms; ANSI-stripped `--- test-*.sh ---`
  header count must equal `ls tests/test-*.sh | wc -l`) and `bash scripts/check-provenance.sh`
  (must end `provenance OK`).
- **Reports:** `.superpowers/sdd/2026-08-12-installer-ownership/` (gitignored).

## RESUME HERE

**Nothing dispatched. Task 1 is next.**

Six defects, one shape: the installer makes a claim it does not keep. The receipt is rebuilt every
run and two project-root files write their rows inside a *create* branch, so a second install
silently disowns them and `uninstall.sh` leaves them behind. `manifest.json.bak` is kept without a
row, so uninstall can never remove it. Two pipeline detectors disagree when both packages are
present, and neither has a both-installed state. The dry-run announces two of four `.gitignore`
entries, unconditionally. And "Option B: Manual Copy" produces an install `uninstall.sh` refuses to
touch.

State at wave start: suite **503/503**, 31 test files, `provenance OK`, tree clean at `f8cd590`.

## Controller decisions, made at setup

1. **The controller owns this ledger.** Created before the first dispatch — a recovery map that a
   task was going to write does not exist if that task dies. The plan does not assign it to anyone.
2. **All six tasks get a general implementer and a general reviewer.** This is the toolkit
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
- **Gates, both, before reporting done.** Current: `Total: 503  Passed: 503  Failed: 0`, 31 files.
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

Nothing yet. Task 1 produces `own_row()` in `tests/test-install-ownership.sh`; Task 2 extends that
file. Task 5 produces `scripts/detect-pipeline.sh` printing one of `builtin`, `urp`, `hdrp`,
`urp+hdrp`.

## Tasks

| # | Task | Status | Commits | Notes |
|---|---|---|---|---|
| 1 | The receipt records ownership, not this run's writes | open | — | State D already passes for the wrong reason — the plan says so |
| 2 | A kept backup is a file the installer owns | open (brief pending) | — | Extends Task 1's test |
| 3 | The dry-run guard, three oracles | open (brief pending) | — | The third oracle is the task's reason to exist |
| 4 | The `.gitignore` announcement says what will happen | open (brief pending) | — | Turns Task 3's guard green |
| 5 | One pipeline detector, and Option B states its costs | open (brief pending) | — | `urp+hdrp` display and skill routing is the implementer's call |
| 6 | Whole-wave verification | open (brief pending) | — | Criterion 6 re-run, not cited |

## Deferred and parked findings

None yet.

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
