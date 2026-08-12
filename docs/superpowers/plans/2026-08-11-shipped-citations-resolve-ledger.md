# Ledger — plan: `docs/superpowers/plans/2026-08-11-shipped-citations-resolve.md`

Spec: `docs/superpowers/specs/2026-08-11-shipped-citations-resolve-design.md`

- **Branch:** `pioneer/process-chain`
- **Base commit (the whole-branch review diffs against this):** `7f4b9f3`
- **Gates:** `bash tests/run-tests.sh` (needs a timeout above 150000 ms; the `--- test-*.sh ---`
  header count, **ANSI-stripped**, must equal `ls tests/test-*.sh | wc -l`) and
  `bash scripts/check-provenance.sh` (must end `provenance OK`).
- **Reports:** `.superpowers/sdd/2026-08-11-shipped-citations/` (gitignored).

## RESUME HERE — state for a session that has lost its context

Nothing is dispatched yet. Task 1 is next.

The wave makes every citation a shipped surface makes resolve in an installed Unity project. Eight
`§N` markers point at `sourced-incidents.md`, a document that was never deleted because it never
existed; eight backticked paths name files `install.sh` does not copy, one of them a **rule**
instructing the reader to inspect a test and report a regression. A new guard,
`tests/test-shipped-citations.sh`, enforces both rules against a payload it derives rather than
hardcodes.

Suite at wave start: **488 passing**, 30 test files, `provenance OK`, 544 manifest rows.

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

Nothing yet. Task 1 produces `payload_paths()` and `PAYLOAD` in
`tests/test-shipped-citations.sh`; Task 2 extends the same file and reuses both.

## Tasks

| # | Task | Status | Commits | Notes |
|---|---|---|---|---|
| 1 | Guard rule 1 (`§N`) + the eight marker sites | open | — | Brief: plan heading "Task 1". Steps 6 and the ledger provenance row are already done by the controller |
| 2 | Guard rule 2 (repo-only paths) + the eight path sites | open (brief pending) | — | Extends Task 1's file. Mutation proof is Step 7 and it is the task's real deliverable |
| 3 | The installer's dry-run states what the real run does | open (brief pending) | — | `install.sh:257` |
| 4 | The fork states its threshold once | open (brief pending) | — | Runner-provided test file — verify through the runner |
| 5 | The two documents that contradict themselves | open (brief pending) | — | `GETTING-STARTED.md:162`, the process-chain ledger's `RESUME HERE` |
| 6 | Whole-wave verification | open (brief pending) | — | Cites Task 2's mutation results rather than re-running them |

## Deferred and parked findings

None yet.
