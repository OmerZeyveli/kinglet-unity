# Ledger — plan: `docs/superpowers/plans/2026-08-10-kinglet-process-chain.md`

Spec: `docs/superpowers/specs/2026-08-10-kinglet-process-chain-design.md`

- **Branch:** `pioneer/process-chain`
- **Base commit (the whole-branch review diffs against this):** `7b18e630`
- **Loop starts from:** `40df066`
- **Gates:** `bash tests/run-tests.sh` (needs a timeout above 150000ms; the `--- test-*.sh ---`
  header count must equal `ls tests/test-*.sh | wc -l`) and `bash scripts/check-provenance.sh`
  (must end `provenance OK`).

## RESUME HERE — state for a session that has lost its context

**Task 1 is in fix round 2 of 5.** Its review came back **Spec ✅ / Quality Approved**, zero Critical,
with 1 Important and 5 Minor. The controller took all six in one round rather than deferring the
Minors: every one is in the two files the task touched and five are in the silent-failure family.
Nothing else is dispatched. Tasks 2–8 are pending.

Task 1's commit is `61e0dcb` (amended from `70fdeb4` before any push, self-disclosed). The round-2
fix will amend again or add a commit — read the report at
`.superpowers/sdd/2026-08-10-process-chain/task-1-report.md` for which.

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
- **`tests/test-provenance-origins.sh` exists and is self-contained** — own helpers, own
  `set -euo pipefail`, valid to run standalone. Tasks 5 and 7 extend it. It uses
  `${BASH_SOURCE[0]}`, not `$0`: inside `( source "$file" )` a test file sees the *sourcing* shell's
  `$0`, and the plan's original line resolved correctly only by the accident that `run-tests.sh`
  also lives in `tests/`.

## Tasks

| # | Task | Status | Commits | Notes |
|---|---|---|---|---|
| 1 | Provenance accepts a `superpowers` origin; two refusals recorded | **fix round 2/5** | `61e0dcb` (+ fix) | Spec ✅, Approved, 0 Critical. Two controller errors in the brief, both caught by the implementer and corrected in flight — see below |
| 2 | `unity-execution` — inline branch, Deslop Pass, cut-criterion gate | **pending** | — | carries an explicit stop-and-escalate gate |
| 3 | `unity-planning` — plan-writing as a skill, carrying the fork | **pending** | — | |
| 4 | `unity-brainstorming` — rename + the design half | **pending** | — | path-set change: rename = removal + addition |
| 5 | Delete the two sequencer commands, repair 22 references | **pending** | — | `generate-claude-md.sh` ships names into user projects |
| 6 | `using-kinglet` becomes a mandate | **pending** | — | |
| 7 | Licence facts — NOTICE gains MIT text, stale claims go | **pending** | — | NOTICE ships into user projects |
| 8 | Whole-wave verification | **pending** | — | |

## Deferred and parked findings

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
