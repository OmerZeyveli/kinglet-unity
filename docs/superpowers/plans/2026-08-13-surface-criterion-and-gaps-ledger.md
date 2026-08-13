# Ledger — plan: `docs/superpowers/plans/2026-08-13-surface-criterion-and-gaps.md`

Spec: `docs/superpowers/specs/2026-08-13-surface-criterion-and-gaps-design.md` at `3845e5a` — six
settled owner decisions (O1–O6) and six work decisions (D1–D6), **fifteen acceptance criteria**.

- **Branch:** `pioneer/surface-criterion-and-gaps`, cut from `main` at `3e4c6e5`.
- **Base commit for the whole-branch review:** `3e4c6e5`.
- **Gates:** `bash tests/run-tests.sh` (timeout above 150000 ms; ANSI-stripped `--- test-*.sh ---`
  header count must equal `ls tests/test-*.sh | wc -l`) and `bash scripts/check-provenance.sh`
  (must end `provenance OK`).
- **Reports:** `.superpowers/sdd/2026-08-13-surface-criterion/` (gitignored).

## RESUME HERE

**STOPPED BY THE OPERATOR mid-round, and the tree is RED. Read this before running anything.**

Task 1's implementer was killed while running its closing gates, after committing. **It committed its
work** — `6cd80bd` (the round-1 fixes) and `8e216b2` (the baseline) — so nothing is lost, but it never
reached the check that would have caught what it left.

### State, measured by the controller after the stop

- **HEAD `8e216b2`. Working tree clean.**
- **`bash scripts/check-provenance.sh` FAILS — 2 problems**, and this is the thing to fix first:

  ```
  FAIL status=verbatim but the file differs from its recorded upstream: .claude/hooks/session-restore.sh
  FAIL status=verbatim but the file differs from its recorded upstream: .claude/hooks/track-edits.sh
  ```

  Round 1 edited both (`git diff --stat 48d42bb..8e216b2 --` those paths → 11 insertions, 5 deletions)
  to fix the stale comments naming cut hooks, and **did not flip their `provenance.tsv` status from
  `verbatim` to `modified`.** That is the identical class the implementer's own third commit
  (`48d42bb`) fixed for two other files one round earlier. It hit it again and was stopped before the
  gate ran.

  **Do not fix this in the controller session.** Resume the implementer; it is one round's leftover.

- **`bash tests/run-tests.sh` → `Total: 1015  Passed: 1014  Failed: 1`.** The failure is in
  `tests/test-kinglet-spike.sh`'s embedded python suite (`FAILED (failures=1, errors=17, skipped=3)`),
  and **it does not reproduce in a clean clone of the same commit** — measured both ways:

  | | rc |
  |---|---|
  | `git clone` → checkout `48d42bb` → run the file | **0**, 18/18 |
  | `git clone` → checkout `8e216b2` → run the file | **0**, 18/18 |
  | the same file in the main working tree | **1** |

  Clearing `__pycache__` under `tests/` and `tools/` did **not** change it. So it is environmental to
  this working tree, not a regression from round 1 — **but the cause was not established**, and
  "environmental" is a hypothesis, not a finding. One error reads
  `E_CANDIDATE: failed to launch candidate '/tmp/tmpXXXX/does_not_exist'`, which is a test that expects
  a failure, so the 17 "errors" may be reporting noise around one real failure.

  **This is also the file the wave's own D4 names**: the runner is blind to python results, 1443 of
  them contributing 1 to the total. Task 10 owns that.

- **`migration/baseline-inventory.json` was left modified** and the controller reverted it. The change
  was the regenerator bumping `source_commit` from `6cd80bd` to `8e216b2` — **circular**, because
  `8e216b2` *is* the baseline commit. The committed state points at the content commit, which is what
  the commit → regenerate → commit discipline produces. Baseline reports `0 change(s)` either way.

### The next action

**Resume Task 1's implementer for the provenance leftover**, then let round 1's re-review run. Do not
start Task 2 until the gate is green — everything after Task 1 works against the tree it leaves.

Round 1's six findings and the three-script measurement were dispatched and are in the implementer's
context; its report at `.superpowers/sdd/2026-08-13-surface-criterion/task-1-report.md` has a
`# Round 1` section only if it got that far — **check before assuming.**

## Controller decisions, made at setup

1. **The controller owns this ledger.** Created before the first dispatch.
2. **Every task gets a general implementer and a general reviewer.** This is the toolkit repository —
   no Editor, no MCP bridge, no C#.
3. **The brief for each task is that task's section in the plan, cited by heading.**
4. **The controller does not commit while a round is open** — from dispatch until the re-review's
   verdict.
5. **Every dispatch says "commit your work."**
6. **New this wave: every dispatch says commit messages go through a file.** `block-projectsettings.sh`
   blocked the controller's own commit because the *message* quoted the string it matches.

## Standing facts for every dispatch

- **Where the plan and the spec disagree, the spec wins** — report it rather than resolving it silently.
  The previous wave produced **seven plan bugs and two spec bugs**, every one found by an implementer
  who checked instead of assuming, and one was a brief whose literal instruction *was* the defect.
- **This is NOT a Unity project.** `install.sh` gates on `Assets/` + `ProjectSettings/`, so the fixture
  is how it is exercised: `bash tests/fixtures/mkproject.sh <dir> [--variant
  urp|builtin|bare|dirty|legacy|async-mixed|hdrp|both]`. Make fixtures realistic — a one-line
  `ProjectVersion.txt` once hid a real bug.
- **Gates, both, before reporting done.** Re-measure; do not quote a stale figure.
- **Strip ANSI before counting suite headers** — the raw count returns 0 on a healthy suite.
- **`grep` in an interactive shell is a function wrapping `ugrep 7.5.0`; `/usr/bin/grep` is GNU 3.11.**
  An unescaped `$` mid-pattern is a **literal** in GNU BRE and an **anchor** in ugrep, so such a probe
  returns a **silent false negative**. **Use `/usr/bin/grep` for anything reported as an absence.**
  Scripts run as `bash x.sh` get `/usr/bin/grep`; the hazard is hand probing.
- **Commit messages go through a file** — `git commit -F <path>`. A message quoting a blocked command's
  text is itself blocked.
- **bash 3.2 compatible.** No `declare -A`, no `grep -oP`, no `$'…'` inside a parameter-expansion
  pattern.
- **Never pipe into a reader that can exit early** under `set -euo pipefail`; `grep -q` on a **file
  argument** is fine — it is the pipe that kills.
- **`set -e` does not exempt a function after the final `&&` of an AND-list**, nor a bare `X="$(fn)"`
  assignment.
- **`[ x = y ] && continue` is a `set -e` trap** as a loop body's last command.
- **New tests are self-contained** — own `set -euo pipefail`, own `pass`/`fail`, `REPO` from
  `${BASH_SOURCE[0]}`, **no runner `assert_*`** (the runner's `set +e` makes an undefined helper
  contribute no `FAIL:` token).
- **Print `PASS:` / `FAIL:`; no needle carries a literal `FAIL` token; no unanchored count needle.**
- **A test must not fabricate its own fixture** — measured last wave, it masked a live spec violation.
- **Cite by content, not by line number.** Two `file:line` citations in this repo have already rotted.
- **A check's silence is only as wide as what it read. Say what each probe cannot see.**
- **Baseline.** `.claude/**` and `templates/` only. **`.claude/hooks/` IS inside it** — stage 1
  produces real drift; `--dry-run` first, use the tool's number, commit → regenerate → commit.
  `tests/`, `scripts/` and the repo root are outside it. Entry point is the **package**.
- **Every new tracked file needs a `provenance.tsv` row; every removed path needs a
  `provenance-skip.tsv` `rule=absent` row.**
- **Probe on a scratch copy:** `git archive HEAD | tar -x -C "$(mktemp -d)"`. **`tests/test-help-ranges.sh`
  cannot run there** — it reads `git ls-files`; Task 10 fixes that.

## Interfaces produced so far

*(nothing yet)*

## Tasks

| # | Task | Status | Commits | Notes |
|---|---|---|---|---|
| **Stage 1 — the cut** | | | | |
| 1 | Twenty surfaces leave, and the counts get a guard | open | — | Re-derive the membership; do not copy the list |
| 2 | The two gates block the act and permit the prose | open | — | Two probe subjects are on Task 1's cut list |
| 3 | The five surviving scripts become reachable | open | — | 8 of 10 named by nothing that ships |
| **Stage 2 — installer correctness** | | | | |
| 4 | The receipt exists before anything that can abort | open | — | The only permanent-damage path in the wave |
| 5 | A run that abandons work says so, and something asserts it | open | — | Exit contract is the implementer's to decide |
| 6 | A reverted file stops being sticky | open | — | Three consecutive installs is the regression check |
| **Stage 3 — the generated block** | | | | |
| 7 | `/unity-init` names the generator, markers become a contract | open | — | Sixteen surfaces rest on that region |
| 8 | `/unity-ui` and `/unity-scene` stop reading as entry points | open | — | A HARD-GATE bypass, not a tidiness fix |
| 9 | The Ambiguity Score says what it does not know | open | — | Must be a **new** heading; six sections are frozen |
| **Stage 4 — guards and claims** | | | | |
| 10 | Six guards see the class | open | — | Two cannot run under the documented probe method |
| 11 | Claims are re-derived or removed | open | — | Two citations have already rotted |
| 12 | The early-exit-reader trap leaves the shipped scripts | open | — | The sweep that missed them gets widened |

## What this wave already knows about itself

**The ledgers it inherits had a twenty-one-item error rate.** An inventory built against the finished
tree found **16 recorded items already closed** without their entries being updated, and **5 moot**. A
finding record that is not re-verified against the tree is a to-do list, not a map.

**Three surfaces blocked read-only work during the analysis that produced this plan** — twice for the
agent auditing the hooks, once for the controller committing the spec that describes the defect. The
available workaround in every case was to reword the text until the gate stopped matching.

**The cut is the risk, and it has a worked example.** `unity-specifics.md` states **in bold** that
legacy `Input.*` is *"BLOCKED by hooks"*. Cutting `block-legacy-input.sh` would falsify a shipped
claim, which is why it is being fixed rather than cut — and why every other cut must be checked against
what still asserts it.

## Deferred and parked findings

*(none yet)*
