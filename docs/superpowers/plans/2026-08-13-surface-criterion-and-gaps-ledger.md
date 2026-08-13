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

### IN FLIGHT as of 2026-08-14 02:10 — Task 9 CLOSED (`5b636d3`…`d038ca9`, unmerged); 2b, 10, 13 running; Task 4 in review

All four are based on `5b636d3` and commit to their own branches. **Nothing of theirs is merged.**
If this session is lost, `git worktree list` is the recovery map and each report path below is the
verdict.

| task | worktree | branch | scratch root | report |
|---|---|---|---|---|
| 2b | `/home/riive/Documents/Github/kinglet-wt/task-2b` | `task/2b-tokeniser-quote-model` | `/tmp/kinglet-2b-NprXPW` | `.superpowers/sdd/2026-08-13-surface-criterion/task-2b-report.md` |
| 4 | `…/kinglet-wt/task-4` | `task/4` | `/tmp/kinglet-t4-WuaZVF` | `…/task-4-report.md` |
| 9 | `…/kinglet-wt/task-9` | `task/9` | `/tmp/kinglet-t9-cqGTgD` | `…/task-9-report.md` |
| 10 | `…/kinglet-wt/task-10` | `task/10` | `/tmp/kinglet-t10-p8ZTUf` | `…/task-10-report.md` |
| 13 | `…/kinglet-wt/task-13` | `task/13` | `/tmp/kinglet-t13-8jVeGK` | `…/task-13-report.md` |

**Task 13 was dispatched out of batch order** — it shares no file with anything running and its
output improves the loop that is executing the rest of the wave.

**Merge order at the boundary: 4, then 9, then 13, then 10 last** — Task 10 changes `run-tests.sh`'s tally
arithmetic and invalidates every quoted total the moment it lands (H4). Task 2b merges independently
of the three; it shares no file with any of them.

**After merging: re-run `tests/test-surface-references.sh` on the merged tree** — Task 9's approach
depends on a property of a file Task 10 may touch, and that collision is invisible in either
worktree (H2).

A figure re-derivation workflow was also dispatched for Batch 1 (three derive agents plus a
synthesis) writing to `.superpowers/sdd/2026-08-13-surface-criterion/batch1-facts.md`. It is
**advisory** — every brief already tells its implementer to derive its own figures — so a missing
facts sheet does not block anything.

---

**Stage 1 is closed. Task 2 was adjudicated at its cap into Task 2b. Batch 1 is dispatched.**

- **HEAD `3fd22dc`** plus this ledger/plan commit. Working tree clean.
- `bash tests/run-tests.sh` → **1189/1189**, rc=0, **35** ANSI-stripped headers == `ls tests/test-*.sh
  | wc -l` = 35. ~~1190~~ was a transcription slip in this ledger, caught by a figure
  re-derivation wave: **four independent measurements at three different commits all say 1189**,
  and this ledger already disagreed with itself, since Task 9's expected end state below is built
  on 1189. **The wall clock is 191–255 s** depending on concurrent load, so the plan's
  `timeout above 150000 ms` truncates every real run and a truncated run reads as red —
  **use 400000 ms**.
- `bash scripts/check-provenance.sh` → **`provenance OK`**.
- **Every figure below is pinned to the commit beside it. Re-derive before quoting one in a brief.**

### Task 2 hit the cap, and the ruling is Task 2b

**Five rounds. Not clean. One new Critical, and it is a data-loss path.** Round 5's clause bound
truncates a command's arguments at the first bare shell-operator token, and `find_exec_commands`
word-splits with no quote awareness — so a quoted `awk`/`sed` program containing ` && `, ` || `,
` | ` or ` ; ` yields those operators as bare tokens and everything after them, **including the write
flag, the redirect, and `system(`**, is silently dropped. Verified against real files: one payload
**truncated 3 of 3 `.meta` files, 104 B → 39 B**; its `system("rm ")` twin **deleted all three**.
Both are rc=0 at round 5 and rc=2 at rounds 3 and 4.

**The pattern across the rounds is the finding, not the last symptom:**

| payload class | r3 `546870f` | r4 `06883cc` | r5 `3fd22dc` |
|---|---|---|---|
| `-exec \rm {} \;` | **permitted** | blocked | blocked |
| eleven in-place spellings (`sed -i''` …) | blocked | **permitted** | blocked |
| quoted operator in an awk/sed program | blocked | blocked | **permitted** |
| interior quote (`sed -'i'`, `gawk -'i' inplace`) | blocked | **permitted** | **permitted** |

Three consecutive rounds each closed one hole and opened another, in the same function, each found
only by a reader who came at it from a different angle. **No earlier commit is safe to fall back to** —
every one of the three has a hole. Forward is the only direction.

**The ruling: no sixth round. A new unit — Task 2b — with a fresh implementer, a fresh budget, and a
brief written from the pattern rather than the symptom.** The cap exists to stop a loop whose
implementer's model of the problem is wrong; that is not what happened here, since each round solved
the finding it was handed. What was wrong was the *scope* every round was given. Task 2b's brief
names the cause — a tokeniser with no quote model — and requires a **regression corpus checked
against the three historical versions**, so that re-opening a closed hole becomes a test failure
rather than the next review's discovery.

Task 2's own closing line is the reason the corpus is the deliverable: *"my own checks were exactly
the three spellings that fall inside the boundary I wrote — that is why the suite stayed green. **A
test built from the same idea as the code confirms the idea, not the behaviour.**"* A corpus cannot
have a different idea on its own; checked against history, it has one by construction.

Also carried into 2b: an **Important** cost regression (round 5 is the slowest version ever shipped
on a quote-leading long token — 1 MB quoted: r3 1.2 s, r4 51.9 s, **r5 172.5 s**; this hook runs on
every Bash call), one **Minor** false positive (`-exec grep -l 'xargs gzip' {} \;`, an `xargs` inside
grep's *pattern* read as an introducer), and the interior-quote class the review ledgered — all four
share the root cause, so 2b closes them or says why not.

### What Task 1 and Task 2 cost, and the two different lessons

- **Task 1 closed in three rounds** (`818b2bd`…`38dec6c`). Each round found the same class in a
  different document; error rate 3-of-6 → 2-of-6 → 1 → 0. The implementer's diagnosis held: *every
  claim it got wrong was composed from memory of the tree; every one it got right came out of a
  command it had just run.* The counts were never the problem — the sentences explaining them were.
  Structural fix: `tests/test-derived-counts.sh` became the single guarded statement of hook
  membership.
- **Task 2 ran five rounds** (`5041b4b`…`3fd22dc`) and **each round fixed the previous round's fix.**
  Rounds 0–2 enumerated harmful verbs four times and were wrong four times. Round 3 inverted to a
  read-only allowlist — correct, and its skip list ate `\rm`. Round 4 fixed that and regexed the whole
  raw command string. Round 5 narrowed to a positional read of each command's own argument tokens.
  **The inversion and the positional read are both correct and both stay.**

### Two whole-task audits ran, and their rulings are below

- **Task 1 whole-task audit** — 6 lenses, every finding attacked by an independent skeptic, 37 agents.
  **15 findings survived.** The criterion lens attacked all 19 removals and **could not construct a
  case for a single wrong cut** — no reversal. One real defect (**F1**), ruled into the new **Task
  4c**. See *Audit findings F1–F13*.
- **Scout wave over the ten undispatched tasks** — 11 agents. **20 Tier-1 plan bugs**, each measured
  to cost a full implementer+reviewer round. See *Scout rulings R1–R12* and *Execution plan*.

### The order from here

1. **Task 2b**, its own worktree, concurrent with Batch 1 — it touches `.claude/hooks/bash-gate.sh`
   and `tests/test-bash-gate-precision.sh`, which no Batch 1 task opens.
2. **Batch 1 — `{4, 9, 10}`**, concurrent, isolated worktrees, one implementer each.
3. Batch 2 — `{5, 3, 12}`. Batch 3 — `{6, 7}`. Batch 4 — `{8, 4b, 4c, 13}`. Batch 5 — `{11}` alone.
4. Whole-branch review from `3e4c6e5`, then merge.

**Every dispatch passes the implementer its own `mktemp -d` scratch root.** Round 5 of Task 2 reported
its probe harnesses were **replaced mid-task by another agent** writing to a shared scratchpad. With
several worktrees concurrent this stops being a nuisance and becomes silent cross-contamination of
measurements.

**Last step of every round, before anything else: update this section.** It is the controller's own
file, nothing guards it, and its entire value is being the one true statement of where the wave
stands. It has now gone stale twice.

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
- **Baseline.** `.claude/**` and `templates/` only. **`.claude/hooks/` IS inside it**; `tests/`,
  `scripts/` and the repo root are outside it. Entry point is the **package**
  (`python3 -m tools.kinglet_build …`; `…kinglet_build.cli` silently no-ops with exit 0).
  **Ruling R6: implementers do NOT run `baseline-regenerate`.** `--dry-run` reads the **anchor
  commit's** tree, so on an uncommitted edit it returns a confident `0 change(s)`, rc=0 — no
  implementer can produce a correct drift figure from inside a worktree. **Regeneration is the
  controller's merge step**, `commit → regenerate → commit`, with `--expect-drift` derived on the
  merged tree. Implementers instead **list the files they changed under `.claude/` or `templates/`**,
  as a measured statement rather than as silence.
- **A task that drifts the baseline reports a RED suite by construction, and that is correct.**
  Discovered on Task 9, 2026-08-14, and not anticipated when R6 was written. R6 forbids the
  implementer from regenerating, so `migration/baseline-inventory.json` still holds the pre-edit
  checksum and the baseline assertion reds until the controller regenerates at the merge. Task 9
  reported `1189/1191, rc=1` with **both** failures being one file's sha drift, reported twice.
  **The gate contract for such a task is therefore: green everywhere except the baseline
  assertions, and the implementer must show that the failures are ONLY that.** A brief that says
  "both gates green" without this carve-out asks for something the ruling makes impossible, and the
  implementer either reports a false green or stalls. **Say it in the dispatch, and have the
  reviewer confirm the failure set rather than accept the claim.**
- **Every dispatch gets its own `mktemp -d` scratch root, and no shared temp path.** Round 5 of Task 2
  had its `probe.sh` and `mutate.sh` replaced mid-task by another agent writing to a shared
  scratchpad, and the measurements it took afterwards were of the other agent's harness.
- **Do not quote a suite total in any shipped document.** Every total in this ledger and the plan
  predates completed tasks, and **Task 10 changes `run-tests.sh`'s tally arithmetic** — after it
  lands, every quoted total everywhere is invalid at once.
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

**Task 4** (`86abc0a` on `task/4`, unmerged at time of writing — reviewed separately).

- **The receipt's commit point is now an `EXIT` trap** (`write_receipt` / `receipt_rescue`), not an
  earlier line. The reason is an invariant every later `install.sh` task must respect: **four
  `owned_by_installer` call sites read `$RECEIPT` expecting the PREVIOUS run's rows**, so writing the
  receipt early silently changes what all four read. `[ -s "$RECEIPT_TMP" ]` is what stops it
  degenerating into "always write a receipt", which would break the `foreign` mode where the
  receipt's *absence* is the definition.
- **That invariant is asserted by nothing.** It is held by a comment. **It is the edit Tasks 5, 6,
  4b and 4c can each break silently** — every one of them opens `install.sh`. Their dispatches must
  carry it, and §7 of `task-4-report.md` is written for them.
- `.gitignore` now gets an ownership row **when the installer created it**, never when it appended to
  the user's. `owned_by_installer` **trims the origin column**, so one trailing space no longer
  disowns a root file forever, while a mangled `user-modified` is still declined.
  `MANIFEST_BAK_KEPT` is cleared by the arm that deletes the file it names.
- **Ruling R1 amended by measurement:** there are now **six** `stat` sites, not five, and the
  fallback is **not** uniformly 644 — the scripts-loop `user-modified` row falls back to **755**.
  The new `.gitignore` row reads the mode rather than hardcoding it.
- **The brief's "86 files" is pre-Task-1.** Measured after the cut: **67**
  (`find "$P/.claude" -type f | wc -l`). The mechanism the figure illustrated is unchanged.
- **`README.md` is now false** where it says the installer *"creates or appends to that file and
  never claims it"* about `.gitignore` — Task 4 made the installer claim it, which spec acceptance
  criterion 6 requires. **→ Task 11** (sole owner of `README.md` by R4). `install.sh`'s own `--help`
  header now carries the correct wording to copy.

## Batch 1 hazards — derived by the controller from the plan text, not measured

**In one line each:** H1 Task 10's
Files line, its Steps and ruling R9 give three different memberships; H2 Task 9's approach rests
on `ub_section`'s heading boundary in a file Task 10 may edit; H3 only Task 9 drifts the
baseline and is the one task forbidden to measure it; H4 Task 10 invalidates every suite total,
so it merges last; H5 Task 9's red-first step may not be executable by any command. Full text
below.

These go into the dispatches as **Interfaces the brief cannot know** and into the ledger.

### H1 — Task 10's Files list does not contain the files its own Steps name

The section's **Files** line names five: `tests/test-help-ranges.sh`, `tests/test-studio-doctor.sh`,
`tests/test-skill-discovery.sh`, `tests/test-surface-references.sh`, `tests/run-tests.sh`.

Its Steps name two more that are absent from that line: **`tests/test-pipeline-detector.sh`**
(Step 1, "check whether it too still dies") and — via ruling **R9** — **`tests/test-mcp-naming.sh`**,
which is the guard whose measurement is the whole basis of the ruling.

The title says **six** guards; the Files line has five; R9 says the finding is **nine files, not
two**. **Three different numbers in one task.** The brief must tell the implementer to derive the
membership and treat the Files line as incomplete rather than as a boundary — otherwise it will scope
to five files and report success, which is the exact shape of the audit's third durable finding (*a
class-fix is reviewed as a list of edits, never as a class*).

### H2 — Task 9 depends on the behaviour of a guard Task 10 is allowed to edit

Task 9 Step 2 rests on a mechanism: `tests/test-surface-references.sh` freezes six named sections of
`.claude/skills/unity-brainstorming/SKILL.md` character-for-character, and its `ub_section` extractor
**stops at the next `#{1,3}` heading** — which is why a *new* heading is invisible to every frozen
comparison and editing an existing one is not. Task 9's entire approach is "add a new section,
because new headings are invisible."

`tests/test-surface-references.sh` is on **Task 10's Files line.**

They do not collide as text — Task 9 only *runs* that file, it does not edit it. They collide as
**meaning**: if Task 10 changes the heading-boundary behaviour of `ub_section` while Task 9 is
writing a section that depends on it, Task 9 passes in its own worktree and reds at the merge.

**Dispatch instruction, both directions:**
- **Task 10:** if any change you make touches `ub_section` or the `#{1,3}` heading interval, **stop
  and report** — another task in this batch depends on that exact behaviour. Do not "improve" it.
- **Task 9:** state in your report that your section's invisibility to the frozen comparisons rests
  on `ub_section`'s heading boundary, and that the controller must re-run
  `tests/test-surface-references.sh` on the **merged** tree, not only in your worktree.

Related, and already in the ledger's honest-limits list: **BSD awk's handling of `/^#{1,3} /` is
untested, and seven frozen comparisons depend on it.** If the interval is not honoured, every one
runs to EOF. That is a macOS-pass finding, not a Batch-1 one, but Task 9 is the task that makes it
load-bearing, so it belongs in Task 9's report.

### H3 — only Task 9 drifts the baseline, and it is the one task forbidden to measure the drift

`.claude/skills/unity-brainstorming/SKILL.md` is under `.claude/**`, so Task 9 drifts
`migration/baseline-inventory.json`. Tasks 4 and 10 touch `install.sh` and `tests/` only, both
outside it.

Ruling **R6** forbids every implementer from running `baseline-regenerate` — `--dry-run` reads the
**anchor commit's** tree, so from inside a worktree it returns a confident `0 change(s)`, rc=0,
whether or not anything drifted. So Task 9 must report **the file list**, and the controller derives
`--expect-drift` on the merged tree.

Tasks 4 and 10 must still report "nothing under `.claude/` or `templates/`" **as a measured
statement**, not as silence — an empty section and an unwritten section look identical to the
controller.

### H4 — Task 10 invalidates every suite total in every other document, including its batch-mates'

Task 10 Step 4 changes `tests/run-tests.sh`'s tally arithmetic (1443 python results across two files
currently contribute **1** to the total). The moment it lands:

- every quoted suite total in the plan, the ledger, the briefs and the two batch-mates' reports is
  invalid;
- `run-tests.sh`'s own header imposes a same-commit obligation to update the totals it governs.

**Controller step at the Batch 1 merge:** merge Task 10 **last** of the three, then re-run both gates
and re-derive the total before writing it anywhere. Tasks 4 and 9 must be told **not to quote a suite
total in prose at all** — report it in their report (which is not a shipped document) and nowhere
else.

### H5 — Task 9's red-first step may not be executable at all

The scout wave concluded the **Ambiguity Score has no code path** — no script, hook, tool or test
computes it. Task 9 Step 1 says "score it twice, with and without a generated block", which is a
*model* operation, not a command. If that holds, Step 1 cannot fail in the way a red-first step is
supposed to fail, and the plan's own global constraint applies: **a red-first step that starts green
is worse than none — observe the specific failure, and if it does not fail, stop and report.**

The brief must resolve this rather than pass it through. **Controller resolution:** Task 9's
red-first artefact is not the score, it is the **invisibility of a new heading to the six frozen
comparisons**. That *is* executable: add a throwaway heading, run `tests/test-surface-references.sh`,
observe it stays green; edit a frozen section, observe it reds. If the second does not red, the freeze
is hollow and that is a Task 10 finding, filed not fixed.

## Tasks

| # | Task | Status | Commits | Notes |
|---|---|---|---|---|
| **Stage 1 — the cut** | | | | |
| 1 | Twenty surfaces leave, and the counts get a guard | **done** | `818b2bd`…`38dec6c` | **19, not 20** — cut is 15 hooks + 4 scripts. 3 fix rounds. `detect-missing-refs.sh` restored by ruling; wiring is Task 3's. Whole-task audit ran after closure → F1–F13 |
| 2 | The two gates block the act and permit the prose | **adjudicated at cap → 2b** | `5041b4b`…`3fd22dc` | 5 rounds; each fixed the previous round's fix. Inverted to a read-only allowlist in round 3, positional argument read in round 5 |
| 2b | The tokeniser gets a quote model, and a corpus stops the next hole | open | — | **New.** Data loss: a quoted operator truncates the arg list, dropping the write flag. Requires a regression corpus checked against `546870f` / `06883cc` / `3fd22dc` |
| 3 | The surviving scripts become reachable | open | — | **R2**: leaves `scripts/` entirely. **R8**: no `Bash` for `unity-reviewer`. **R7** if it lands second |
| **Stage 2 — installer correctness** | | | | |
| 4 | The receipt exists before anything that can abort | open | — | The only permanent-damage path in the wave. **R1**: gains the five `stat -c` sites |
| 4b | A `CLAUDE.md` missing its end marker is amputated silently | open | — | **New, R5.** Data loss, repeats on every install, prints success |
| 4c | An upgrade across the cut leaves dead hook registrations | open | — | **New, F1.** Not a Task 1 reopen — Task 1 never opened `install.sh` |
| 5 | A run that abandons work says so, and something asserts it | open | — | **R3**: contract goes in `MCP-SETUP.md`. **R11**: exit code stays 0; ≥10 sites, not 4 |
| 6 | A reverted file stops being sticky | open | — | **R10**: shape (iii), `--toolkit-dir`. Shape (ii) silently breaks three origin readers |
| **Stage 3 — the generated block** | | | | |
| 7 | `/unity-init` names the generator, markers become a contract | open | — | Sixteen surfaces rest on that region. **R7** if it lands second |
| 8 | `/unity-ui` and `/unity-scene` stop reading as entry points | open | — | A HARD-GATE bypass, not a tidiness fix |
| 9 | The Ambiguity Score says what it does not know | **done** | `5b636d3`…`d038ca9` | Must be a **new** heading; six sections are frozen. **The score has no code path at all** — Step 1 may not be executable |
| **Stage 4 — guards, claims, and the loop** | | | | |
| 10 | Six guards see the class | open | — | **R9**: the deliverable is the CLASS. "Nine files, not two". Changes `run-tests.sh` tally arithmetic → invalidates every quoted suite total |
| 11 | Claims are re-derived or removed | open | — | **R4**: sole owner of `tests/test-derived-counts.sh`. **R12**: pointers vs historical narrative. **F9**: `CLAUDE.md` joins its file list. **F11**: widen Step 1's pattern *before* it runs |
| 12 | The early-exit-reader trap leaves the shipped scripts | open | — | **R1**: leaves `install.sh` entirely. **R2**: gains the six `--help` texts |
| 13 | The loop learns the five shapes a scoped review cannot see | open | — | **New**, from Task 1's audit. Payload skill — drifts the baseline |

---

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

**From Task 9's review (2026-08-14).**

11. **Task 9's new section `### What the score does not know` is entirely unguarded.** Measured by
    the reviewer, not reasoned: deleting the section outright leaves the suite at full green, and so
    does **replacing it with prose stating the opposite of its ruling**. The cause is that
    `unity-brainstorming` has **no heading-inventory assertion at all**, unlike `using-kinglet`'s
    `UK_SECTIONS_EXPECTED` — the same absence that made the insertion invisible in the first place.
    It cuts both ways. Two concrete closures: an `assert_eq` on
    `ub_section '### What the score does not know'`, **or** a `UB_SECTIONS_EXPECTED` inventory
    mirroring `UK_SECTIONS_EXPECTED` — the second closes the general hole rather than this instance.
    *Deferred by ruling, with Task 9's collision reason accepted: `tests/test-surface-references.sh`
    is on Task 10's edit list and Task 10 was running concurrently.* **-> Task 10.**
12. **`provenance.tsv`, the `unity-brainstorming` row's note:** the 2026-08-14 clause is a *content
    claim* placed immediately after the sentence asserting content claims are guarded by
    `tests/test-surface-references.sh` — which does not guard it. Roughly four words closes it.
    Offered to Task 9's fix round as fold-in-if-trivial. **-> Task 11 if it was not folded.**
13. **Two counting slips in `task-9-report.md`** (report-only, no diff impact): whole-section frozen
    comparisons are **11 (7 + 4)**, not 10 — the derivation grep was single-line and missed the
    two-line `assert_eq "$UK_REDFLAGS_EXPECTED" \` form; and `provenance.tsv` was counted as
    Markdown in the no-code-path split. Neither changes a conclusion. **Recorded, no owner.**

**From Task 9's fix round and closing re-review (2026-08-14). Task 9 is complete at `d038ca9`.**

14. **`provenance.tsv`'s note paraphrases wording the section no longer carries.** The row's note
    still says the ruling holds *"because a constant cannot discriminate between requests"* — the
    plan's bolded phrase — and the fix round deliberately replaced that rationale in the skill with
    the stronger regressive-lift argument. `/usr/bin/grep -c -F` on that phrase: **1 in
    `provenance.tsv`, 0 in the file the row describes.** Not false (the new rationale entails the
    old), only stale in substance. One clause fixes it. **→ Task 11.**
15. **The extractor-dependent `assert_eq` count is settled, and the reason three readers gave three
    numbers is that the question was never pinned to a definition.** Record it as
    **11 direct / 6 indirect / 17 total**, with the command, which must join backslash continuations
    first — that omission is where the original **10** came from:

    ```bash
    awk '{ line = line $0 } /\\$/ { sub(/\\$/, "", line); next } { print line; line = "" }' \
      tests/test-surface-references.sh \
    | /usr/bin/grep -c 'assert_eq.*\(ub_section\|uk_section\)'
    ```

    Direct = 11 (7 on `unity-brainstorming`, 4 on `using-kinglet`). Indirect = 6, found by a taint
    trace through `UK_CHAIN` / `UK_TABLE_LINES` / `UK_ROWS` / `UK_TAIL`; the four tainted `UB_*`
    variables feed only `assert_contains` and contribute nothing. `UK_INJECTED` is **not**
    extractor-derived — it comes from running `.claude/hooks/session-brief.sh` — so its two
    `assert_eq` belong in neither bucket. **Do not conflate 17 with the 15 from the BSD-awk
    simulation**: they measure different things, and the 15 includes assertions outside this set.
16. **The plan's bolded reason is deliberately not in the tree verbatim.** The plan says the content
    must argue *"a constant cannot discriminate between requests"*; the shipped section argues
    something strictly stronger — the constant does not merely fail to discriminate, **it
    discriminates backwards**. The reviewer accepted the substitution (a brief states an argument,
    not a frozen string; no test freezes the phrase). **Recorded so the next reader does not treat
    the plan's wording as missing.**
17. **The `--expect-drift` figure for Task 9's merge is contested and must be derived, not chosen.**
    The closing re-review says **1** (one file changed). The figure re-derivation counted
    `.claude/skills/unity-brainstorming/SKILL.md` appearing **twice** in
    `migration/baseline-inventory.json` (123 records, 72 distinct paths), and the suite reds **two**
    assertions — one per index. **Derive it at the merge with `--dry-run` against the committed
    merged tree**, which is the one situation where `--dry-run` is trustworthy: R6's defect is that
    it reads the anchor commit's tree, and after the merge commit that tree is the right one. File
    sha at `d038ca9`: `b8bd6d1fa2a2c288753d016663e237e777c2f97936546d5825c2fcb6868cf767`,
    superseding `0284206…` from the first commit.

**From Task 4's review (2026-08-14). Task 4 is in fix round 1; these are the deferrals.**

18. **The `$RECEIPT`-holds-the-previous-run invariant gets a cheap, non-hollow guard — and it goes to
    Task 5**, the next `install.sh` owner, so it protects 6, 4b and 4c rather than arriving after
    them. The reviewer's proposed form: **assert `install.sh` contains exactly one `> "$RECEIPT"`
    redirection and that it lives inside `write_receipt`.** That is the single edit the four
    downstream owners cannot make silently, and it reads `install.sh`'s *structure* rather than the
    filesystem — a different oracle from `tests/test-install-ownership.sh`'s, which is why it did not
    belong in Task 4. **→ Task 5.**
19. **`README.md`'s `.gitignore` sentence, with its replacement wording, moves into Task 11's row
    here rather than living only in Task 4's report.** The sentence *"Your `.gitignore` is not in it:
    the installer creates or appends to that file and never claims it"* is confirmed present and
    confirmed **false** at HEAD — Task 4 made the installer claim it, which spec acceptance criterion
    6 requires. **Nothing guards the sentence**: `/usr/bin/grep -rn 'never claims it\|creates or
    appends' tests/` is empty. The corrected wording is already written in `install.sh`'s own
    `--help` header; copy it from there. **→ Task 11.** *(Recorded here because "it is in the report"
    is not a delivery mechanism — the whole point of this ledger is that a report nobody re-reads is
    a finding that did not happen.)*
20. **An asynchronous signal leaves exactly one file unrowed.** Measured across eight
    `timeout -s TERM/INT` runs at 0.15–0.30 s: the EXIT trap always fires and never writes a spurious
    row, but in five of eight the file being copied when the signal landed had no row. **One leftover
    file instead of 67 is about as tight as this design gets** — recorded as a known bound, not a
    defect. Cosmetic companion: `$?` at trap entry is 0 for SIGINT/SIGQUIT, so those runs print
    *"This install did not finish (exit 0)"*. **No owner; carried.**
21. **`stat -c` sites are now six and the plan says five, with nothing guarding the figure.** Task 4
    added the sixth (the `.gitignore` row, which **reads** the mode rather than hardcoding it —
    measured `664` on a created `.gitignore`, `600` on `CLAUDE.md.generated`; hardcoding `644` there
    would have produced a receipt disagreeing with its own file). All six are **GNU-only**;
    `stat -c` is unsupported on macOS. **→ Task 12** (R1 leaves `install.sh` to Task 4, but the
    *figure* and the macOS exposure are Task 12's subject).
22. **`assert_not_owned "$O" '.claude/agents/teammate.md'` is weakly guarded** — it did not red under
    the reviewer's `MODE=ours` mutation, because in `ours` mode the payload loop never writes that
    path, so no row appears either way. The state's first two assertions carry it. **Noted, not
    actionable.**

**A method note from the same review, worth more than any of the above.** The reviewer's first
mutation attempt used `perl -pi -e` **without `/g`**; the first occurrence of the target string was
in a **comment**, so the mutation landed there, the code was untouched, and the suite reported a
clean **325 PASS / 0 FAIL**. Read naively that is *"the guard is hollow"* — a finding that does not
exist, and a round spent chasing it. **The unapplied-mutation failure is symmetric**: it makes a
broken guard look sound *and* a sound guard look broken. The remedy is not "check it applied" but
`cmp` plus an explicit `MUTANT DID NOT APPLY` marker, because **a zero means nothing until you know
which zero it is.** Third measured instance in this repository. **→ Task 13** (already sent).

**Inherited from earlier waves, still open:**

8. **`HOOK-REFERENCE.md` §Shared Library makes two false claims.** **→ Task 11.**
9. **`dirty_foundation_files()` has no `--cached`**, so `git add` silences the guard entirely — and
   the suite goes red during the `commit → regenerate → commit` sequence this repo prescribes.
   **→ Task 10.**
10. **`session-brief.sh` sources nothing** while the template claims `DISABLE_UNITY_HOOKS` bypasses
    ALL safety hooks. **→ Task 11.**


---

## Scout rulings R1–R12 — binding on the briefs

Source: 11 agents over the ten undispatched tasks, **20 Tier-1 plan bugs**, each measured to cost a
full implementer+reviewer round. Every figure in that document is pinned to a commit this branch has
since passed; **the rulings bind, the figures do not.**

| # | Ruling |
|---|---|
| **R1** | `install.sh`'s five `stat -c` sites belong to **Task 4**, not 12 — two are the payload receipt-row writers and one is the `$MANIFEST_BAK_REL` row, the exact region Task 4 rewrites. The plan's claim that the fallback is uniformly 644 is wrong: one site falls back to **755**. **Task 12 leaves `install.sh` entirely.** |
| **R2** | The six scripts' `./scripts/<name>` `--help` text belongs to **Task 12**, not 3. **Task 3 leaves `scripts/` entirely.** |
| **R3** | Task 5's exit contract goes in **`MCP-SETUP.md`**. Of the three candidates, only that one installs into a project. Task 5 leaves `README.md` and `docs/GETTING-STARTED.md`. |
| **R4** | **`tests/test-derived-counts.sh` has exactly one owner for the whole wave: Task 11.** Tasks 3, 5 and 10 hand it claim rows as *text in their reports*. Resolves six conflicting pairs at once. |
| **R5** | The missing-end-marker data loss becomes **Task 4b**, in the `install.sh` lane — not folded into Task 7 (not an `install.sh` task) and not into Task 5 (scope already contested). |
| **R6** | **Baseline regeneration leaves the implementer briefs and becomes the controller's merge step.** Two scouts measured independently that `baseline-regenerate --dry-run` reads the **anchor commit's** tree, so on an uncommitted edit it returns a confident `0 change(s)`, rc=0. Combined with the ×2 path indexing, **no implementer can produce a correct drift figure from inside a worktree.** The global constraint "`--dry-run` first, use the tool's number" produces 0 for every drifting task if taken literally. **Struck from the briefs.** |
| **R7** | `docs/GETTING-STARTED.md`'s script-reachability sentence goes to whichever of **Tasks 3 and 7 lands SECOND**, and must be replaced by a **derived claim row**, not corrected prose. Three scouts found it independently; both tasks falsify it, and corrected prose falsifies again on the next reachability change. This is the wave's own D5 thesis applied to the wave. |
| **R8** | **Do NOT grant `Bash` to `unity-reviewer`.** It ships read-only; adding Bash is a capability change and out of Task 3's scope. `detect-missing-refs.sh` goes to **`unity-fixer`** — the only agent with both `Bash` and an existing anchor. For `validate-serialization.sh`, prefer naming it in a **command**; if no command is a correct home, **report back rather than granting a capability.** |
| **R9** | **Task 10's deliverable is the CLASS, not the symptom.** Decisive measurement: with a planted violation, `tests/test-mcp-naming.sh` reports **1 pass / 1 fail with `.git` present, and 2 pass / 0 fail without it** — a *higher* pass count on a real violation, because the sweep goes empty and the loop body never runs. A guard that is green because it scanned nothing is the worst shape in this repository. The finding is **"nine files, not two"** — re-derive the membership. |
| **R10** | **Task 6 Step 4 takes shape (iii): the doctor gains a `--toolkit-dir`.** Shape (ii) — a fifth receipt column — is **measured to silently break all three origin readers**: every one does `IFS=$'\t' read -r rel recorded _mode origin`, so a fifth column makes `origin` become `user-modified<TAB>deadbeef` and every `case` falls through to the catch-all, in `install.sh`, `uninstall.sh` **and** `studio-doctor.sh`. Shape (i) leaves the doctor wrong between revert and reinstall. **If (iii) turns out larger than a contained change, stop and report.** |
| **R11** | **Task 5's exit code stays 0.** Changing it reds three existing assertions in two files and breaks anything scripting the installer. The deliverable is the **reporting**: complete the existing `Not done:` summary to cover all measured sites (**≥10, not the plan's 4**) and assert it. The unreachable third red-first member is reached **by mutation** or dropped — and it is not a flag abandonment, it fires on a run passing no `--with-*` flag at all. |
| **R12** | **Task 11 distinguishes live pointers from historical narrative.** About half the rotted citations **quote the rot as the finding**; renumbering those falsifies a record. Rule: a citation used as a *pointer* must resolve at HEAD; a citation inside a narrative about a past state must be **pinned to its commit and marked historical**. The new guard checks pointers only. |

## Audit findings F1–F13 — Task 1's whole-task audit

**F1 is the one real defect, and it is ruled into the new Task 4c, not a Task 1 reopen.** Upgrading
across the cut with an edited `.claude/settings.json` leaves registrations pointing at deleted hook
files and `install.sh` prints a pre-cut hook count. Two lenses found it independently, one by walking
the dependency graph and one by running the upgrade. It fires on **any project that has ever edited
`settings.json`** — one appended newline is enough — and it does not self-heal.

*Why 4c and not a reopen:* `git log 3e4c6e5..38dec6c -- install.sh` is empty. Task 1 never opened that
file; reopening it misattributes the work and corrupts the commit range the whole-branch review
diffs. `install.sh` already has four owners (4, 5, 6, 4b) and the batch plan serialises them.

| # | Finding | Owner |
|---|---|---|
| F2 | `README.md` sells a hook count over 2× the tree's. Falsifying it to nonsense leaves the suite green, exit 0. | **Task 11**, guard row in the same commit. Escalate to a reopen only if anything is tagged or released first — a 2.25× overstatement on the install-decision page must not cross a release boundary. |
| F3 | `minimal` profile membership is hand-stated in two shipped files. `_lib.sh` states the keeps as a **closed list**, so it rots in the **unsafe** direction; the template says "INCLUDING", which can only over-state. | **Task 10.** Derive membership by name in both directions. Prioritise `_lib.sh`. |
| F4 | The shipped template points at `docs/HOOK-REFERENCE.md`; `install.sh` never installs `docs/`. | **Task 11.** One line. |
| F5 | `docs/ARCHITECTURE.md` contradicts itself about hook counts 150 lines apart — written by the **first and last commits of the same task**. | **Task 11.** Split the sentence: hooks guarded, rules not. |
| F6 | Guard blind spots absent from the guard's own "what this cannot see" list. | **Task 10.** Add the 19 retired names to `dead_needles` first — one line, retroactively catches a class. |
| F7 | `ARCHITECTURE.md`'s `scripts/` gloss advertises validators that no longer exist. | **Task 11.** |
| F8 | `HOOK-REFERENCE.md`'s session entries promise permanently-empty fields. | **Task 11.** |
| F9 | **`CLAUDE.md` still says the criterion was never applied to hooks and the question is open** — settled by `818b2bd`. | **Task 11, and `CLAUDE.md` must be ADDED to its Files list** — it is not there, so folding without the amendment silently drops it. |
| F10 | The floor-lowering justification of record carries two numbers this wave's own round 2 falsified. | **Task 11**, with deferred item 7 — same class. |
| F11 | Two bare line-number self-citations rotted, and **Task 11's own enumeration pattern cannot see them**. | **Task 11 — widen its Step 1 pattern to bare `:NNN(-NNN)?` BEFORE it runs.** Cheapest change in the audit; converts a task that would report success into one that closes its class. |
| F12 | A clean uninstall leaves `.claude/` and `.claude/skills/` behind and prints a self-contradiction. | **PARKED.** Outside the range and identical at branch base. Recorded mechanism: `-exec rmdir {} +` vs `-delete`, with a BSD-`find` caveat, so the macOS pass does not rediscover it. |
| F13 | The ledger's `RESUME HERE` is stale again. | **Acted on.** Updating it is now the last step of every round rather than a habit. |

## The five shapes a scoped review structurally cannot see

These are the audit's durable output, and they belong in the loop itself rather than only here —
**that is Task 13.**

1. **The diff is not the blast radius.** A removal's damage lands in files the round never opened.
   Sharper: the removal sweep was keyed on **names**, and a bare numeral, a category word, a
   capability sentence and a scope claim contain no removed name. *Loop step: after any removal run
   **two** sweeps — by removed name, and by the **aggregate** (re-derive every count, category list
   and capability phrase the removed things contributed to). Sweep (b) has never run.*
2. **Prose has tense; a round can falsify a sentence it never opened.** *Loop step: ask "what became
   false because of what we just made true?" — sweep for prose describing the area's absence
   ("unguarded", "hand-maintained", "open question", "not yet").*
3. **A class-fix is reviewed as a list of edits, never as a class.** One round announced "five stale
   counts" and fixed three files; the review verified the five and never re-derived the class to find
   the sixth. *Loop step: when a round names a class, the reviewer independently re-derives its
   membership and diffs it against the round's list.*
4. **Every artifact under review is a repository; the artifact that breaks is a user's project.**
   `scripts/studio-doctor.sh` has the exact check that catches F1 — nothing calls it and no test
   asserts it. *Loop step: any change to the payload's **shape** needs an **upgrade** fixture, not
   only a fresh-install one.*
5. **Coverage is self-attested by the commit that wrote the guard.** A review reads the guard and its
   own "cannot see" list and finds them consistent **with each other**, which is not evidence about
   the world. *Loop step: derive the restatement set mechanically and diff it against the covered set;
   where a guard has a hand-maintained needle list, adding a surface and extending that list must be
   the same commit.*

**Sixth, meta:** the audit's strongest instrument was **mutation** — falsify a claim, run the suite,
see whether anything reddens. Four of thirteen findings were settled that way in minutes, and every
time the answer was *the suite does not care*. **A per-round review that mutated each claim it
verified would have caught four of thirteen findings at the round that introduced them.**

## Execution plan — five batches, isolated worktrees

Batch boundaries are merge points. **One implementer per task; tasks inside a batch run concurrently
in separate worktrees, each with its own `mktemp -d` scratch root.**

1. **`{4, 9, 10}`** — intersection is `provenance.tsv` with disjoint rows; only 9 drifts the baseline.
2. **`{5, 3, 12}`** — safe given R1–R4.
3. **`{6, 7}`** — safe given R5. Task 7 rebases onto Task 3's `unity-init.md` and `GETTING-STARTED`.
4. **`{8, 4b, 4c, 13}`** — disjoint. Task 8 rebases onto Task 7 and Task 10. 4b and 4c both touch
   `install.sh` and are **serialised against each other** inside the batch; 13 touches only
   `.claude/skills/subagent-driven-implementation/`.
5. **`{11}` alone** — it conflicts with eight of nine on a file, **and its subject is the claims the
   other nine falsify.** Running it earlier guarantees a second round.

Fallback if a ruling is withdrawn: `{4,9,10}` → `{12,8}` → `{5}` → `{6}` → `{3}` → `{7}` → `{11}`.

**Merge protocol at every boundary:** merge worktrees → hand-resolve `provenance.tsv` note appends
(concatenate; **keep straight apostrophes** — a curly `'` reds `tests/test-provenance-origins.sh`) →
commit → `baseline-regenerate --anchor HEAD --expect-drift <derived on the MERGED tree>` → commit →
both gates → **re-derive every count the next batch's brief quotes.**

**After Batch 1, every quoted suite total in the plan, ledger and briefs is invalid** — Task 10
changes `run-tests.sh`'s tally arithmetic, and that file's own header imposes a same-commit
obligation to update them.

**Why `provenance.tsv` is not the serializer it looks like:** four scouts independently established
that **no file this wave touches is `status=verbatim`**, and `check-provenance.sh` only checksums
verbatim rows. The wave's provenance work is note-column appends on existing rows, plus a full
seven-column row **iff a task adds a tracked file**. `migration/baseline-inventory.json` is the real
semantic serializer, and only five of the tasks drift it. Treating provenance as a hard serializer
would have cost four to five unnecessary rounds.

## Corrections the figure re-derivation forced on the rulings themselves

A four-agent wave re-derived every figure Batch 1's briefs quote, at a commit none of the source
documents saw, in private `mktemp -d` trees. It corrected the controller, the scouts and the audit —
and two of its corrections were to rulings, not to numbers.

- **R9's "nine files, not two" names the WRONG nine.** The nine are the **archive-breakage** set, and
  that set is **disjoint** from the vacuous-green class R9's own decisive measurement is about. An
  implementer who re-derives by diffing a clone against a `git archive` extraction **fixes the wrong
  nine and ships the class untouched, while reporting success**, because the nine it fixed all now
  behave. The class R9 actually measured — *a guard whose loop body never runs when its sweep goes
  empty, so it reports green, or greener, on a real violation* — measures **eight**: seven in
  `tests/` plus `scripts/check-provenance.sh`. **Derive by the criterion; report both sets and name
  the overlap.**
- **Task 10's title corresponds to no derivable set.** Files line 5, Steps 6, R9 9, archive-breakage
  9, vacuous-green 8. **No command in this repository produces six.** Retitle by the criterion — this
  wave's own thesis applied to its own task title.
- **R4 was carved into, and R4 wins.** The controller's Task 10 dispatch handed it two repairs living
  in `tests/test-derived-counts.sh`. R4 gives that file **exactly one owner for the whole wave: Task
  11**, and it was made to resolve six conflicting pairs at once. **Both repairs move to Task 10's
  report as text for Task 11.** A ruling with a convenience exception is not a ruling.
- **F6's one line reds 10 sites across 5 files immediately** (not 6 — the source's own repair list
  said 5 while its prose said 6), and several are **deliberate documented residue**: a retired name
  legitimately appearing in `docs/ARCHITECTURE.md`, in `_lib.sh`'s comments, and in `session-save.sh`
  / `track-edits.sh`. The five: `.claude/hooks/_lib.sh`, `.claude/hooks/session-save.sh`,
  `.claude/hooks/track-edits.sh`, `docs/ARCHITECTURE.md`, `scripts/validate-asmdefs.sh`. **The risk
  is an implementer deleting correct prose to make a guard green.**
- **The jq vacuity is real but its tally is violation-dependent.** Reported `3/2 → 5/0 rc=0`; a
  *replacement* violation gives `3/2 → 4/1 rc=1`, because a replacement is visible from both
  directions and the non-jq assertion still reds. `5/0 rc=0` needs a violation isolated to the
  jq-fed sweep — an **added** dangling registration that removes nothing. **An implementer handed
  the replacement recipe concludes the finding evaporated.**
- **Task 4 and Task 4c collide on two files, not one.** Both write `install.sh` (receipt block vs
  summary block) **and both write `README.md`** (Task 4 falsified the `.gitignore` sentence; 4c/F2
  owns the hook-count row). **Serialise, or give each an explicit line-disjointness instruction.**
- **`.claude/hooks/bash-gate.sh` blocks probes that rewrite a fixture's `Packages/manifest.json`** —
  four instances in this wave. The retry after clearing must be **byte-identical, including
  unrelated lines**. **Prefer `python3` over `grep -v … > tmp && mv` for fixture edits**; the
  re-derivation agent used python3 throughout and was never blocked once.
- **"The 29 failure-capable write commands in the pre-receipt window" is not derivable by any
  command.** It is a hand classification, and a mechanical grep gives a different number per verb
  set. **Do not put 29 in a brief.** Four *reachable* triggers were verified by execution instead —
  and spec acceptance criterion 5 grades **one of the four**, three of which need no flag, so a
  `[ -L ]` patch on the single `cp` satisfies the criterion while leaving three live.
- **`test-provenance-origins.sh` in an archive copy dies rc=128 having asserted 14 of 47, emitting
  no `FAIL` token** — the `1` in an earlier report is the runner's own backstop line. Word it that
  way or the next reader hunts for a named assertion that does not exist.
- **Say "69 *data* rows"** of the receipt: the file is 76 lines = a 7-line preamble + 69 data rows
  (67 `.claude/*` + 2 root). A brief that writes "69 rows" sends an implementer to `wc -l`.

**Method note worth keeping:** the driver that produced every per-file figure replicates
`run-tests.sh`'s loop body exactly — `source tests/run-tests.sh --source-only`, `set +e`,
`( source tests/<file> ) 2>&1 </dev/null`, tallied with the runner's own ANSI-stripped needles. It
does **not** synthesise the runner's backstop line, which is the whole of disagreement D4. **A
faithful driver and the real runner disagree in exactly one place, and knowing which place is worth
more than either number.**

## The honest limits, carried forward to EE

- **Nothing in either audit proves the toolkit works inside Claude Code.** No scout ran a command
  against a live Editor; no MCP. Every claim about what a model does with a rewritten surface is a
  reading of instructions.
- **The Ambiguity Score has no code path at all** — no script, hook, tool or test computes it.
- **The fixture is thin.** All script behaviour was measured on `--variant urp`: **1 C# file, 0
  `.meta` files, 1 assembly.** `detect-missing-refs.sh` indexed **0 GUIDs** there. The scripts run;
  nobody has confirmed they *find* anything on a project with real content. **This is what EE tests.**
- **One host — and this one improved on measurement.** BSD awk's handling of `/^#{1,3} /` was
  recorded here as untested, with the fear that an unhonoured interval would run every frozen
  comparison to EOF. Task 9 simulated it — both terminators replaced with a pattern no heading can
  match, which is what an awk treating `{1,3}` literally produces — and its reviewer reproduced the
  result exactly: **95 pass / 15 fail**, spanning both extractors, all seven `unity-brainstorming`
  whole-section comparisons plus eight on `using-kinglet`. **The failure is loud, not silent**,
  which is the good direction. The pattern appears exactly twice in the tree, both in
  `tests/test-surface-references.sh` (`ub_section` and `uk_section`). Still unverified on real BSD
  awk: the simulation measures the consequence, not the cause.
