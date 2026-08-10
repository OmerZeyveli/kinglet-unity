# Ledger — plan: `docs/superpowers/plans/2026-08-10-kinglet-process-chain.md`

Spec: `docs/superpowers/specs/2026-08-10-kinglet-process-chain-design.md`

- **Branch:** `pioneer/process-chain`
- **Base commit (the whole-branch review diffs against this):** `7b18e630`
- **Loop starts from:** `40df066`
- **Gates:** `bash tests/run-tests.sh` (needs a timeout above 150000ms; the `--- test-*.sh ---`
  header count must equal `ls tests/test-*.sh | wc -l`) and `bash scripts/check-provenance.sh`
  (must end `provenance OK`).

## RESUME HERE — state for a session that has lost its context

Setup complete. No task dispatched yet.

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

*(Nothing yet — populated as tasks complete. State these in later dispatches rather than letting a
brief guess.)*

## Tasks

| # | Task | Status | Commits | Notes |
|---|---|---|---|---|
| 1 | Provenance accepts a `superpowers` origin; two refusals recorded | **pending** | — | unblocks 2, 3 |
| 2 | `unity-execution` — inline branch, Deslop Pass, cut-criterion gate | **pending** | — | carries an explicit stop-and-escalate gate |
| 3 | `unity-planning` — plan-writing as a skill, carrying the fork | **pending** | — | |
| 4 | `unity-brainstorming` — rename + the design half | **pending** | — | path-set change: rename = removal + addition |
| 5 | Delete the two sequencer commands, repair 22 references | **pending** | — | `generate-claude-md.sh` ships names into user projects |
| 6 | `using-kinglet` becomes a mandate | **pending** | — | |
| 7 | Licence facts — NOTICE gains MIT text, stale claims go | **pending** | — | NOTICE ships into user projects |
| 8 | Whole-wave verification | **pending** | — | |

## Deferred and parked findings

*(none yet)*
