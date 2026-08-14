`docs/superpowers/plans/2026-08-14-unmeasured-surfaces-and-floors.md`

# Ledger — Unmeasured Surfaces and Floors

**Base commit: `e17f310`** (`main`, the merge of `pioneer/surface-criterion-and-gaps`).
**Branch: `pioneer/unmeasured-surfaces`.** The whole-branch review at the end diffs `e17f310..HEAD`.

## RESUME HERE

**Nothing dispatched yet.** Task 1 is next.

| task | state | commit range |
|---|---|---|
| 1 — the three hooks nothing has ever executed | open | |
| 2 — execution-keyed hook coverage | open *(brief pending — consumes Task 1's output)* | |
| 3 — anchor the unanchored pathspecs | open | |
| 4 — the doctor's two remaining compensations | open | |
| 5 — anti-vacuity floors, written | open | |
| 6 — a heading inventory for `docs/` | open *(brief pending — cites Task 5)* | |
| 7 — the claims with no owner | open *(brief pending — cites Task 5)* | |
| 8 — record what a second reader can reproduce | open | |

**Ordering that binds:** T1 → T2 (T2's mechanism is T1's output). T5 → T6 and T5 → T7 (both cite its
criterion). T3, T4, T8 are independent.

---

## Standing facts for every dispatch

A fresh subagent inherits none of the controller's reading of this project. State these every time.

- **This is the toolkit repository, not a Unity project.** No Editor, no MCP, no C#. Everything is
  bash, Markdown, TSV, JSON. Routing a documentation or shell task to `unity-coder` measures the
  dispatch rather than the task — use a general implementer.
- **Read `CLAUDE.md` first.** The provenance contract, the shell conventions and the testing section
  all bind, and none of them is guessable from the diff.
- **Gates, both, every task.** `bash tests/run-tests.sh` with a timeout of **at least 400000 ms** —
  ~300 s, and **a killed run is not a red suite**. Headers: strip ANSI *before* counting
  (`sed $'s/\x1b\\[[0-9;]*m//g'`), then `grep -c '^--- test-.*\.sh ---'` must equal
  `ls tests/test-*.sh | wc -l`. **Raw output returns 0 on a perfectly healthy suite.**
  `bash scripts/check-provenance.sh` must end exactly `provenance OK`.
- **`cmd > log 2>&1; echo "EXIT=$?"` reports the `echo`'s status.** It misreported a four-failure run
  as green during the last wave's review. Capture status on its own line.
- **Interactive `grep` is `ugrep 7.5.0`, interactive `find` is `bfs 4.1.1`.** Use `/usr/bin/` for any
  absence claim and say which you used. **Two measured divergences:** an unescaped mid-pattern `$` is
  a literal in GNU BRE and an **anchor** in ugrep; and `grep -r … .` prints `./path` under GNU and
  `path` under ugrep, so an exclusion anchored `^\./` **excludes nothing** and reports a *larger*
  number rather than an error.
- **Under `set -euo pipefail`, do not pipe into a reader that exits early.** `head` and `grep -q`
  both do. Use `grep -qF -- "$needle" <<< "$haystack"`.
- **No `declare -A`, no `grep -oP`** — macOS ships bash 3.2 and BSD grep.
- **Every `.claude/` file changed drifts `migration/baseline-inventory.json`.** Regenerate **last**
  and **derive `--expect-drift` yourself** — it is a property of the file set, not a constant. Last
  wave: 6 for one set, 4 for another, from identical reasoning. `full_claude_tree/files` counts every
  `.claude/` file once; commands and `SKILL.md` files count again under `categories/`; `_lib.sh` and
  non-`SKILL.md` skill files do **not** double.
- **`provenance.tsv`: seven tab-separated columns, append to `note` only, straight apostrophes.** A
  curly `'` reds `tests/test-provenance-origins.sh`. **A new file with no row fails as an orphan.**
- **Two test idioms coexist and mixing them fails silently.** A *runner-provided* file uses the
  runner's `assert_contains` / `assert_eq` / `$REPO_DIR` and defines none of them —
  `bash tests/<file>.sh` standalone **exits 0 having asserted nothing**. A *self-contained* file
  defines its own helpers and sets `set -euo pipefail`. Say which kind you wrote.
- **One implementer at a time.** Isolated worktree under `/home/riive/Documents/Github/kinglet-wt/`,
  own `mktemp -d` scratch root per dispatch. **Never `git stash`** — repository-global.
- **Implementers do not run `baseline-regenerate --dry-run` from a worktree (R6)** — it reads the
  *anchor commit's* tree and returns a confident `0 change(s)`. Regenerate for real, or list your
  `.claude/` files for the controller.
- **Cite by anchor, never by bare line number.** A verdict is read after the fix round has already
  moved the file.

## The two rules the last wave paid for, in full

> **A derivation whose scope includes the file recording its result is not a derivation.**

Ten instances last wave — the house defect. Filter by something the recording cannot match. **And the
standard remedy for it was itself silently broken on this host**: `grep -v '^\./path/to/self:'`
excludes nothing under ugrep, and reports a *larger* number rather than an error.

> **A probe whose passing condition is silence must first prove its own baseline is not silent.**

Print the non-silent byte count beside every zero.

## Measurement discipline, carried forward

- **Derive a class by enumerating its mechanism space, not by listing instances.**
- **Mutate more than one way**, `cmp` the mutant, check the injected marker is present, and emit
  **`MUTANT DID NOT APPLY`** when it is not. The failure is **symmetric** — an unapplied mutant makes
  a hollow guard look sound *and* a sound guard look broken.
- **Measure damage by checksum, never by size.** One state grew 11 lines while losing four sections.
- **Never accept a guard's own coverage list as its coverage** — the same commit wrote both.
- **Build an `awk` window from an array, not with `getline`** — `getline` consumes the lines it looks
  ahead at; one derivation silently missed 14 of ~28 members and looked complete.
- **Regenerate derived numbers LAST.**
- **`git clone --no-hardlinks --shared`, never `cp -a`** — a `.git` file pointing back at the real
  repo cost a reviewer 15 spurious failures.
- **Write down what is being counted before counting it.** One quantity was reported as 10, 11 and 12
  by three careful readers and settled only when someone stated the criterion.

## Interfaces produced so far

*(empty — nothing has shipped on this branch yet)*

## Inherited state, measured at the base commit

- Both gates green at `e17f310`: `Total: 3326  Passed: 3323  Failed: 0  Skipped: 3`, rc=0, 38 headers
  == 38 files; `provenance OK`.
- **A fresh clone reports `Skipped: 22`, not `3`** — 19 assertions run only for the author, gated on
  the untracked gitignored `spikes/platform/clients/probe-host/dist/`. Both green. **Task 8 owns
  this**; until it lands, quote the figure with its reader named.
- Surfaces, derived: 8 agents, 9 commands, 16 skills, 6 rules, 12 hooks, 38 test files. **Derive,
  never quote** — `tests/test-derived-counts.sh` fails when a user-facing document disagrees.
- **`.claude/hooks/warn-filename.sh` dies rc=1 with 0 bytes** on an Edit fragment matching
  `: MonoBehaviour` without a `class` keyword, against its own `# Exit: 0 always` header. Confirmed by
  reading the mechanism; Task 1 step 1 reproduces it by execution.

## Deferred, parked, and rulings

*(empty)*
