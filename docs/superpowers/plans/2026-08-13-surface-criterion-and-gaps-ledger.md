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

**Stage 1, Task 1 is closed and green. Task 2 is next and has not been dispatched.**

- **HEAD `38dec6c`. Working tree clean.**
- `bash tests/run-tests.sh` → **1023/1023**, 35/35 ANSI-stripped headers.
- `bash scripts/check-provenance.sh` → **`provenance OK`**, 116 `rule=absent` enforced.
- `python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --dry-run --expect-drift 0` → rc=0,
  `0 change(s), 0 removal(s), 0 addition(s)`. **`--expect-drift` is required** — without it, rc=64.

Task 1 took **three fix rounds**. What they cost is worth knowing before dispatching Task 2, because
every round found the same class in a different document:

- **Round 0 → 1:** three of six corrections were false.
- **Round 1 → 2:** two of six were false, both in the two documents the implementer writes *about*
  the structure rather than *from* a command.
- **Round 2 → 3:** one finding survived — `ARCHITECTURE.md` still named three hooks' membership four
  lines above the sentence claiming it did not.
- **Round 3:** clean, and its own first draft of the fix was an over-claim the implementer caught
  itself.

The implementer's diagnosis, which held up: *every claim it got wrong was composed from memory of the
tree; every one it got right came out of a command it had just run.* The counts were never the
problem. The sentences explaining them were.

**The structural fix that came out of it:** `tests/test-derived-counts.sh` is now the single guarded
statement of hook membership. Before this task, the Event and Matcher columns had **no assertion of
any kind**, and four hand-written restatements of the profile membership were each proved silent when
falsified.

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

**Task 1.**

- **`tests/test-derived-counts.sh` is the single guarded statement of hook membership.** It asserts
  the twelve per-hook `Profile:` lines, the Summary Table's **event, matcher and profile** columns,
  the `minimal`-keeps list **as a set**, and every hook named as a state-file writer in
  `ARCHITECTURE.md`'s Tracking Files table. **Any task that adds, removes, renames or re-registers a
  hook must update `docs/HOOK-REFERENCE.md` in the same commit, or the suite goes red.** This lands
  on Task 2 immediately — it edits two hooks.
- The keeps list is asserted as a **set** because keeps and drops are complements and a hand-written
  complement drifts *independently*: a hook can vanish from both lists while each still reads
  coherently on its own. Verified — that mutation reds on the keeps assertion and nothing else.
- **`docs/ARCHITECTURE.md` no longer states any hook's profile, event or matcher.** Do not restate
  membership there; the file now says so about itself, and the sentence is true.
- **`scripts/detect-missing-refs.sh` is restored** (controller ruling — see Deferred, item 0) and is
  referenced by nothing. **Wiring it is Task 3's**, and Task 3's section does not know it exists.
- Enforced `rule=absent` count is **116**.
- `docs/GETTING-STARTED.md`'s script counts are derived and guarded (`DCK_REPO_SCRIPTS`,
  `DCK_INSTALLED_SCRIPTS`). Moving a script reds them, correctly.

## Tasks

| # | Task | Status | Commits | Notes |
|---|---|---|---|---|
| **Stage 1 — the cut** | | | | |
| 1 | Twenty surfaces leave, and the counts get a guard | **done** | `818b2bd`…`38dec6c` | **19, not 20** — cut is 15 hooks + 4 scripts. 3 fix rounds. `detect-missing-refs.sh` restored by ruling; wiring is Task 3's |
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

**0. The one ruling, not a deferral: `scripts/detect-missing-refs.sh` was cut and restored.**
Measured before ruling: the compiler never reads scene YAML; no surviving script or hook reports a
dangling GUID; and the only two shipped surfaces with a path to it — `unity-scene-builder`'s
`manage_scene action:"validate"` and `unity-fixer`'s missing-script section — **both need a live
Editor and neither produces a project-wide negative.** Offline, project-wide dangling-GUID detection
is exactly where a model samples a few scenes and answers confidently wrong. The cut became 15 hooks
and 4 scripts.

**From Task 1's rounds. None of these blocks Stage 1; each has an owner.**

1. **`_lib.sh`: `unity_track_read` / `unity_was_read` have zero callers and zero test references.**
   Confirmed independently by two reviewers. Deleting them is a `_lib.sh` surface decision, not a
   consequence of the hook cut. `docs/HOOK-REFERENCE.md:259-260` documents both and would go with
   them. **`UNITY_READS_FILE` is NOT free to remove alongside** — `tests/test-state.sh` reads it
   twice. *Ruling: carry forward, → a later surface pass.*
2. **The writer-column assertion requires backticks.** The cell is matched as
   `` /^`[a-z0-9-]+\.sh`$/ ``; de-backticking a writer cell silences the assertion for that cell
   while the suite stays green. The N2 failure class in its *silent* direction. One-line awk fix
   (strip optional backticks — they are not needed to exclude the `Various hooks` row, which fails
   the name pattern anyway). **→ Task 10.**
3. **`tests/test-derived-counts.sh:858` and `:215` — a command substitution that exits 1 at an
   assignment site** when `dck_want2` is `-` (10 of the claim rows). Reachable only on the *failure*
   path and inert under the runner, which is the only supported way to run this runner-provided file.
   Pre-existing from `818b2bd`. **→ Task 10.**
4. **`docs/ARCHITECTURE.md:363` is false and self-contradicting** — *"All hooks source a shared
   library"* against `:172-173`'s *"except one, which sources nothing"*. `session-brief.sh` provably
   sources nothing. `docs/HOOK-REFERENCE.md:252` carries the same false sentence. Pre-existing since
   the ECU vendor commit `45eada9`. **→ Task 11.**
5. **Unguarded prose about named hooks in `ARCHITECTURE.md`** — `:221`, `:420`, `:421`, `:427`. All
   currently **true**, all proved silent when falsified. None asserts a profile, event or matcher, so
   the file's narrowed sentence still holds; these are behaviour/registration claims outside every
   guard. **→ Task 11**, with the ruling to make: guard them or delete them, not both.
6. **`docs/ARCHITECTURE.md:197`** still lists `PreCompact` in the Event Types table while `:213` says
   no `PreCompact` registration remains. Adjacent, not contradictory. **→ Task 11.**
7. **`test-derived-counts.sh:460` says "4 … left in one commit"**, but that commit removed 5; 4 is the
   net after round 2's restoration. `test-help-ranges.sh:90` discloses the restoration; `:460` does
   not. **→ Task 11.**

**Inherited from earlier waves, still open:**

8. **`HOOK-REFERENCE.md` §Shared Library makes two false claims.** **→ Task 11.**
9. **`dirty_foundation_files()` has no `--cached`**, so `git add` silences the guard entirely — and
   the suite goes red during the `commit → regenerate → commit` sequence this repo prescribes.
   **→ Task 10.**
10. **`session-brief.sh` sources nothing** while the template claims `DISABLE_UNITY_HOOKS` bypasses
    ALL safety hooks. **→ Task 11.**
