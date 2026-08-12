# Ledger — plan: `docs/superpowers/plans/2026-08-11-shipped-citations-resolve.md`

Spec: `docs/superpowers/specs/2026-08-11-shipped-citations-resolve-design.md`

- **Branch:** `pioneer/process-chain`
- **Base commit (the whole-branch review diffs against this):** `7f4b9f3`
- **Gates:** `bash tests/run-tests.sh` (needs a timeout above 150000 ms; the `--- test-*.sh ---`
  header count, **ANSI-stripped**, must equal `ls tests/test-*.sh | wc -l`) and
  `bash scripts/check-provenance.sh` (must end `provenance OK`).
- **Reports:** `.superpowers/sdd/2026-08-11-shipped-citations/` (gitignored).

## RESUME HERE — state for a session that has lost its context

**Task 1 is done and closed** (`c56a1fd..a4f49ea`, 1 fix round, Spec ✅, Quality Approved, 0 Critical).
**Task 2 is next**, and its brief is amended — see *Task 2's brief, as amended* below. Nothing is
dispatched.

The wave makes every citation a shipped surface makes resolve in an installed Unity project. Eight
`§N` markers abbreviate a citation to `docs/research/pioneer/field-notes.md`, which is tracked and
does not ship; eight backticked paths name files `install.sh` does not copy, one of them a **rule**
instructing the reader to inspect a test and report a regression. A new guard,
`tests/test-shipped-citations.sh`, enforces both rules against a payload it derives rather than
hardcodes.

Suite at wave start: 488 passing, 30 test files, 544 manifest rows. **Now: 491 passing, 31 test
files, `provenance OK`.**

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
| 2 | Guard rule 2 (repo-only paths) + the eight path sites | open (brief amended) | — | Extends Task 1's file. Mutation proof is Step 7 and it is the task's real deliverable. Four amendments below |
| 3 | The installer's dry-run states what the real run does | open (brief pending) | — | `install.sh:257` |
| 4 | The fork states its threshold once | open (brief pending) | — | Runner-provided test file — verify through the runner |
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
6. **No trailing newline on a red run** (`:71`). → Task 2, amendment 4. Cosmetic; does not affect
   the runner's PASS/FAIL aggregation.

### Carried to Task 6 — its sweep as written can never report clean

Plan Task 6 Step 2 greps for `sourced-incidents` and expects `clean: no reference survives`. The
string survives by design in the spec, in the plan, and — until Task 2 — in the guard's header
comment. **The check as written is unsatisfiable and must be rewritten in Task 6's brief** to scope
the sweep to what ships: `.claude/` and nothing else. Reported by Task 1's implementer.
