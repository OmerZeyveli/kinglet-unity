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

### MERGED AND GREEN — seven tasks are in the branch

**1, 3, 4, 9, 10, 12, 13.** Both gates pass on the merged tree, re-measured after every merge:

- `bash tests/run-tests.sh` → **rc=0, `Total: 2758  Passed: 2755  Failed: 0  Skipped: 3`**, of which
  1444 results came from 2 python suites. **35** ANSI-stripped headers == `ls tests/test-*.sh | wc -l`
  **35**.
- `bash scripts/check-provenance.sh` → **`provenance OK`**.
- Baseline regenerated at each merge against the **committed merged tree** — the one situation where
  `--dry-run` is trustworthy, since R6's defect is that it reads the anchor commit's tree and after a
  merge commit that *is* the right tree. Drift so far: **11** (Tasks 9 + 13), **1** (Task 10), **0**
  (Task 4), **6** (Task 3), **0** (Task 12).
- **H2 resolved by measurement.** Task 9's approach rested on `ub_section`'s `/^#{1,3} /` boundary in
  a file Task 10 edited, and that collision is invisible from inside either worktree. On the merged
  tree the guard is **111 PASS / 0 FAIL**, Task 9's section is present, the interval is untouched at
  both sites.
- **Every suite total written before Task 10 merged is invalid.** It changed the runner's tally
  arithmetic — python results counted per result rather than per file — so 1189 became 2653 and has
  moved with each merge since. **Re-measure; never transcribe.**

### STILL IN FLIGHT

| task | worktree | branch | scratch root | state |
|---|---|---|---|---|
| 2b | `…/kinglet-wt/task-2b` | `task/2b-tokeniser-quote-model` | `/tmp/kinglet-2b-NprXPW` | fix round **2** (two one-line guard additions); based on `5b636d3` |
| 5 | `…/kinglet-wt/task-5` | `task/5` | `/tmp/kinglet-t5-vCm1jg` | fix round **1** (three Important); based on `75ea1de` |
| 7 | `…/kinglet-wt/task-7` | `task/7` | `/tmp/kinglet-t7-Co4LNJ` | dispatched from `05d9cfe` |

**Task 5 owns `install.sh`; Task 7 only runs it.** Both are based on trees the branch has since
moved past — `provenance.tsv` is the shared file and the rows are disjoint, so concatenate the note
appends by hand and **keep apostrophes straight**.

### Remaining, in batch order

**2c, 4b, 4c, 6, 8, 11.** Task 6 waits on Task 5 (`install.sh`); Task 8 waits on Task 7;
2c waits on 2b; 4b and 4c are the `install.sh` lane after 6. **Task 11 runs alone and last** — it
conflicts with nearly every other task on a file, **and its subject is the claims the others
falsify.** **Re-derive every figure at each
boundary; nothing above this line is inherited.**

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
- **The interactive `find` is a `bfs 4.1.1` wrapper, the same trap as `grep`→`ugrep`.** Use
  `/usr/bin/find` (GNU 4.9.0) for any behaviour or absence claim. Discovered 2026-08-14 by a
  reviewer measuring real file damage.
- **`pgrep -f <pattern>` is not a usable wait condition when several agents share a session.** It
  matches **the waiter's own command line** (which contains the pattern) and **every other agent
  running the same command**. Measured 2026-08-14: three `until ! pgrep -f 'run-tests.sh'` loops that
  could never exit, while two other agents' suites ran in their own scratch directories. **A wait
  that can never finish looks identical to a command that never finished.** Block on the command's
  own completion, never on a process-name probe.
- **"A probe that dies reports nothing" has now been measured three times this wave, in three
  different disguises**, and every one produced a **clean zero** that a careless reader would have
  believed: a reviewer's `perl -pi -e` without `/g` landing in a comment (`325 PASS / 0 FAIL` —
  reads as *the guard is hollow*); an implementer's helper killed by `set -u` because **bash expands
  all `local` arguments before performing any assignment**, so `local name="$1" d="$SCRATCH/$name"`
  took `$name` from the enclosing scope (`374 PASS, 0 FAIL, exit 1`, with two whole states simply
  absent); and a guard dying `rc=128` in an archive copy having asserted 14 of 47 with **no `FAIL`
  token at all**. **The exit code is the only one of the three signals that survives all three.**
- **`git stash` is repository-global, not per-worktree. Never use it while worktrees are live.**
  Measured 2026-08-14: a chained probe in one worktree ran `git stash` then `git stash pop`, and the
  pop applied **a stash entry that was not its own** into that worktree. **Corrected on inspection:
  the entry was a stale detached-HEAD stash from a session predating this wave** (`WIP on (no
  branch): 3c18aa7`), not a concurrent agent's work — every one of the ten worktrees was clean before
  and after, and `stash@{0}` is still present with its original contents. **And do not check
  ownership by ancestry:** that stash's base commit *is* an ancestor of several worktrees' HEADs,
  purely because every worktree shares one object store and it predates their bases. The marker that
  identifies it is `WIP on (no branch)` — it was taken from a detached HEAD, and every worktree in
  this wave has been on a named branch for its whole life. **The hazard is real and
  the incident was milder than first reported; record both.** `pop` takes what is on top of a stack
  every worktree shares, and it is shared **silently**. The alternatives are all per-invocation:
  `git archive HEAD | tar -x -C "$(mktemp -d)"` (the documented probe method), `git clone
  --no-hardlinks --shared .` when history or an index is needed, or a second `git worktree add`
  under your own scratch root.
- **Measure file damage by checksum, never by size.** Task 2c reproduced three route payloads that
  destroy `.meta` files with **no byte-size change at all** — `sed -i s/a/b/` rewrites in place at
  equal length. **A size-only probe would have called all three harmless.** Earlier payloads in this
  same wave *did* change size (127 B → 6 B, 104 B → 39 B), so both behaviours are real and a probe
  must assume neither.
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

**Task 2b** (`f735fe2` on `task/2b-tokeniser-quote-model`, in review).

- **`find_exec_commands` now splits with a one-pass `LC_ALL=C awk` scanner.** A quoted run is one
  token whose contents are inert; arguments reach the four arms TAB-joined; `;` terminates an
  `-exec` clause unconditionally while `+` requires a preceding `{}`; a redirect is skipped rather
  than ending the clause; and **command substitution, backticks, ANSI-C quoting and an unterminated
  quote are unparseable and block.** The allowlist inversion and the positional flag read are
  untouched, as the brief required.
- **The corpus is the durable deliverable, not the fix.** 242 unique payloads carrying a frozen
  `hist` column — each payload's verdict at `546870f` / `06883cc` / `3fd22dc` — of which **155 are
  monotonically protected** and **45 are exemptions each with a reason, 0 unexplained permits.**
  Any later work on this hook is now measured against the union of what every past version blocked.
- **Cost: a 1 MB quote-leading command line went r3 1 144 ms → r4 44 632 ms → r5 123 504 ms → new
  1 976 ms**, and a **10 000 ms ceiling is asserted where none existed before.** This hook runs on
  every Bash call, so the previous state was a two-minute hang on a hostile input.
- **Three recorded facts were wrong, and the implementer measured rather than inherited them:**
  `sort -u '+' -o {} {}` is a *find* problem (GNU find needs `{}` before `+`, so sort really receives
  `-o {}`); `sed -e ';' -i {} \;` **cannot write at all** (`find rc=1, "unknown predicate -i"`, 0
  files changed), so the r3/r4 blocks were **false positives** and it is the one deliberate monotonic
  exemption; and `./\grep` blocking was a dequoting artifact — `./grep` is permitted at all four
  versions.
- **§9, raised by the implementer against itself, and it is the same defect one level up:** the
  route's *precondition* is now the weakest thing in the file. `ls Assets/*.meta | xargs sed -i` and
  `find Assets -name "*.m"*"eta" -exec sed -i` are **permitted at every version** — and the second is
  the shape the new tokeniser would resolve correctly, except **the regex gating the route never sees
  the tokeniser's output.** *"No corpus payload could look there."* Also inherited and open: **the
  allowlist vouches by basename**, so any `/tmp/evil/grep` passes.

**Task 10** (`44eea70` on `task/10`, in review).

- **The wave's own gate was vacuous.** `scripts/check-provenance.sh` printed
  `pass no orphan files (0 tracked files covered)` and ended **`provenance OK`, rc=0, over a tree it
  never enumerated.** Every "provenance OK" recorded from a scratch copy in this wave was that.
  Fixed.
- **The two sets are 5 and 8, and only 3 are in both** — so **4 of the 8 are invisible to an archive
  diff.** The archive-breakage set (diff a clone against a `git archive` extraction) is 5; the
  vacuous-green class R9's own measurement is about is 8: `test-mcp-naming.sh`,
  `test-mcp-doc-instructions.sh`, `test-skills.sh`, `test-no-mobile.sh`,
  `test-surface-references.sh`, `test-cross-validation.sh`, `test-skill-discovery.sh`, and
  `scripts/check-provenance.sh`. **A figure re-derivation put the archive set at 9; the implementer
  measures 5. The reviewer is settling it.** The brief's Files line misses the decisive file
  entirely, and `test-pipeline-detector.sh` needs no change.
- **F6 needed an exemption mechanism, not a skip list.** Bare retired names red 10 sites across 5
  files, **8 of them the past-tense records the guard's own comment prescribes** — so the 19 retired
  names are matched as **path-form pointers on non-comment lines, derived from `provenance-skip.tsv`
  rather than typed**. **No prose was deleted**, which was the named risk.
- **R4 was honoured after the controller withdrew its exception:** `tests/test-derived-counts.sh` is
  reverted, and both findings are in the report as text for Task 11 with the one-line awk repair and
  the measured proof that de-backticking silences the assertion.
- **Task 9 is safe:** `tests/test-surface-references.sh` gained a 19-line **pure insertion**;
  `ub_section` and its `/^#{1,3} /` interval are untouched. **Still re-run that guard on the merged
  tree** — that is the whole point of H2.
- **The runner's tally changed as predicted:** `Total: 1189 → 2653`, with **1444 python results from
  2 suites (was 1)**. Every suite total written anywhere before this is now invalid.

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
| 2b | The tokeniser gets a quote model, and a corpus stops the next hole | **done, merged** | `5b636d3`…`c050743` | **New.** Data loss: a quoted operator truncates the arg list, dropping the write flag. Requires a regression corpus checked against `546870f` / `06883cc` / `3fd22dc` |
| 2c | What decides the route, and what the allowlist vouches for | open | — | **New.** Both holes exist at all four hook versions; `./evil/grep` destroyed 3/3 `.meta` files with the gate at 0 |
| 3 | The surviving scripts become reachable | **done, merged** | `75ea1de`…`d607839` | **R2**: leaves `scripts/` entirely. **R8**: no `Bash` for `unity-reviewer`. **R7** if it lands second |
| **Stage 2 — installer correctness** | | | | |
| 4 | The receipt exists before anything that can abort | **done, merged** | `5b636d3`…`8056f53` | The only permanent-damage path in the wave. **R1**: gains the five `stat -c` sites |
| 4b | A `CLAUDE.md` missing its end marker is amputated silently | open | — | **New, R5.** Data loss, repeats on every install, prints success |
| 4c | An upgrade across the cut leaves dead hook registrations | open | — | **New, F1.** Not a Task 1 reopen — Task 1 never opened `install.sh` |
| 5 | A run that abandons work says so, and something asserts it | **done, merged** | `75ea1de`…`0755d2a` | **R3**: contract goes in `MCP-SETUP.md`. **R11**: exit code stays 0; ≥10 sites, not 4 |
| 6 | A reverted file stops being sticky | open | — | **R10**: shape (iii), `--toolkit-dir`. Shape (ii) silently breaks three origin readers |
| **Stage 3 — the generated block** | | | | |
| 7 | `/unity-init` names the generator, markers become a contract | **done, merged** | `05d9cfe`…`f804913` | Sixteen surfaces rest on that region. **R7** if it lands second |
| 8 | `/unity-ui` and `/unity-scene` stop reading as entry points | **done, merged** | `468c382`…`6f91053` | A HARD-GATE bypass, not a tidiness fix |
| 9 | The Ambiguity Score says what it does not know | **done, merged** | `5b636d3`…`d038ca9` | Must be a **new** heading; six sections are frozen. **The score has no code path at all** — Step 1 may not be executable |
| **Stage 4 — guards, claims, and the loop** | | | | |
| 10 | Six guards see the class | **done, merged** | `5b636d3`…`5db856d` | **R9**: the deliverable is the CLASS. "Nine files, not two". Changes `run-tests.sh` tally arithmetic → invalidates every quoted suite total |
| 11 | Claims are re-derived or removed | open | — | **R4**: sole owner of `tests/test-derived-counts.sh`. **R12**: pointers vs historical narrative. **F9**: `CLAUDE.md` joins its file list. **F11**: widen Step 1's pattern *before* it runs |
| 12 | The early-exit-reader trap leaves the shipped scripts | **done, merged** | `75ea1de`…`71a3965` | **R1**: leaves `install.sh` entirely. **R2**: gains the six `--help` texts |
| 13 | The loop learns the five shapes a scoped review cannot see | **done, merged** | `234fa85`…`222e40e` | **New**, from Task 1's audit. Payload skill — drifts the baseline |

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

**From Task 10's review (2026-08-14). Task 10 is in fix round 1.**

23. **The three-way membership disagreement is settled, and all three numbers were right for
    different criteria — none had been written down.** **Nine** of the 35 test files change verdict
    with vs without a git index. **Five** of those change it *unsafely* (die silently, or report
    green/greener over a violation). The **vacuous-green** class — green because the sweep was empty,
    whatever emptied it — is **eight**, and **5 ∩ 8 = exactly 3**. The task title's "six" corresponds
    to nothing. *Sharper still:* the implementer's own nine-row table overlapped the true nine in
    only **six** places, because it enumerated candidates instead of sweeping all 35 — it omitted
    three that change verdict loudly (`test-derived-counts.sh`, `test-kinglet-build.sh`,
    `test-lib.sh`) and included three that do not change verdict at all (`mcp-naming`,
    `mcp-doc-instructions`, `surface-references`) — **which is precisely why those three are the
    interesting ones.**

    **Finished form, from the closing re-review — this is the statement to carry:** the
    with/without-index derivation is blind to the **entire** eight-member class, for **two distinct
    reasons.** The three git-fed members are invisible *because they are vacuous* — being
    vacuous-green **is** the property of producing the same verdict either way, so the differential's
    own signal is the thing they suppress. The other five never enter the differential's domain at
    all: `test-skills.sh` via `find`, `test-no-mobile.sh` via `grep -r`, `test-cross-validation.sh`
    via `jq`, `test-skill-discovery.sh` via globs, and `scripts/check-provenance.sh`, **which is not
    a test file at all.** So "nine" is not a different count of the same thing — **the derivation
    that produced it is structurally incapable of finding a single member of the class R9's decisive
    measurement demonstrates.** *(Third time this wave that two careful readers produced different
    memberships for one class, and the third time the cause was a question never pinned to a
    definition.)*
24. **Four latent `tests/run-tests.sh` arithmetic issues, all fail-closed, none reachable today.**
    The 0-discovery guard aggregates `ran`/`suites` across suites, so it cannot fire when a sibling
    suite ran; `match($0, /failures=[0-9]+/)` also matches inside `expected failures=N` (no
    `@unittest.expectedFailure` in the tree today); `/^(OK|FAILED)/` fires on any line starting with
    those words, so a shell probe printing `OK: the tool reported success` yields *"ran a python
    suite that discovered 0 tests"*; and `file_pass=$((file_pass + py_ran - py_skip - py_bad))` is
    unclamped, so `Ran 1 test` + `FAILED (failures=3)` subtracts **2 from global Passed** (rc still
    1, so no failure hides — but Total and Passed go wrong). **→ a later runner pass.**
25. **`scripts/check-provenance.sh`'s new arm cannot say *why* the index was unreadable.**
    `git ls-files 2>/dev/null | sort` discards stderr and `$TRACKED_RC` is never printed, so "no git
    at all" and "a real repo with an empty index" produce byte-identical output. Both fail closed.
    **Every sibling guard added in the same commit captures the exit code and git's stderr; the one
    on the gate does not.** **→ Task 12.**
26. **`scripts/check-provenance.sh`'s `--online` branch drops `$TRACKED_LIST` from cleanup** — the
    `trap 'rm -f "$TMP_PATHS"; rm -rf "$TMP_ECU"' EXIT` replaces the trap installed for the new temp
    file, leaking one `mktemp` per `--online` run. **→ Task 12.**
27. **`.claude/hooks/_lib.sh`'s new derivation is anchored, so it can still misclassify in the
    unsafe direction.** The three commands key on `^HOOK_PROFILE_LEVEL=` and `="minimal"`; a hook
    that **indents** the declaration or **single-quotes** the value lands in the *runs at minimal*
    list while `_lib.sh` itself reads it correctly — and 1+3+8 still totals 12, so the header's own
    partition tripwire stays silent. **→ a later hook pass.**
28. **`tests/test-install-dryrun.sh` is insensitive to an emptied `.claude/*.md` payload** (`165/0`
    both ways) — but it is a dry-run-vs-real *differential* and its own header already names *"A RUN
    THAT WRITES NOTHING IS INVISIBLE TO ALL THREE ORACLES AT ONCE"*. **A documented adjacent case,
    not a missed member.** Settling it needs the criterion applied **per assertion**, which no task
    in this wave scoped. **→ open question, no owner.**
29. **`tests/test-surface-references.sh`'s `.gitignore` residual is not closed and does not claim to
    be.** With `.claude/` gitignored and a real untracked payload file present, the new floor
    **passes** (the files are still tracked, so the index count holds) and the untracked payload
    stays invisible. Named in the guard's own blind-spot list. **Not a regression. → open.**
30. **Two `provenance.tsv` notes run on without a separator** (`…adopt Also: the profile header…`
    on the `_lib.sh` row; `…without word splitting Also: the single assertion…` on the
    `test-skills.sh` row). Every other multi-clause note uses `; ` or `. `. **→ Task 11.**

**From Task 13's review (2026-08-14). Task 13 is in fix round 1. Both Importants are the five
shapes applied to the task that wrote them down.**

31. **The new review instructions landed only in the document that structurally cannot fire first.**
    Task 13's own Step 1 diagnosed it — *"a guard first lands at the **task** review… so the clause
    that would have caught F6 was in a document that does not run at the moment F6 is created"* — and
    then placed the fix in that same document. `SKILL.md` makes the two explicitly disjoint and the
    fix loop only runs once the task review **already found something**, so a guard landing in a
    clean task review is reached by none of the three. **Ruled a fix round, not a brief amendment**:
    `task-reviewer-prompt.md` is already in the task's Files list.
32. **Step 0 reconciled the citation rule in two files and left it standing in the surface the
    reviewer actually reads.** `.claude/agents/unity-reviewer.md` still pairs `file:line` with **the
    identical sentence** Step 0 exists to reconcile, interpolates a bare line number three times in
    its output template, and says so again in its frontmatter `description:`;
    `.claude/commands/unity-review.md` repeats it. `SKILL.md` dispatches that agent **with**
    `task-reviewer-prompt.md`, so the reviewer reads both in one turn and they disagree. **The Step 0
    probe was scoped to the skill directory — shape 1 applied to this task and missed.** *Ruled:
    widen the scope; those files have no other owner and a citation-format change is not a capability
    change, so R8 does not bite.*
33. **Five Minor, folded into the same round because each is a defect in shipped prose and three are
    the rot this task teaches against, inside the rule that teaches it:** the two surfaces disagree
    on the size of the same class (three shapes vs four); F1's corroboration is restated as *"both by
    running the upgrade"* when one lens walked the dependency graph; a quotation-marked *"finish with
    two green gates"* appears **nowhere** in the plan; *"the instruction is not 'check that your
    mutation applied'"* is followed immediately by a mechanical way of checking that your mutation
    applied; and the bare-numeral sweep is the only one of four with no search needle — **the shape
    with the highest measured cost**, as its own section states.
34. **The honest answer to "do these additions reduce the risk or merely name it": mostly name it,
    with exactly one real reduction — and it is the part the implementer added beyond the brief.**
    `re-review-prompt.md`'s Output paragraph (*"a verdict that omits them reads identically to one
    that ran them"*) converts a skipped mutation from invisible into a **visible omission** a human
    or controller can see. That is a genuine if weak mechanism, and it binds **only the fix-loop
    reviewer** — which is finding 31 from the other side. **Record it: it is the only structural
    change in the task, and everything else is a rule a model reads under load.**
35. **`provenance.tsv`'s SUPERSEDED append was ruled acceptable as-is**, not deferred. Tagged append
    is that file's own convention, the marker is explicit and adjacent, and editing the stale clause
    out would destroy the record of what the row claimed **while the contradiction shipped** — the
    historical-narrative case R12 says to preserve. Residual risk checked and not live: no
    `tests/*.sh` greps `file:line` at all.

**From Task 2b's review (2026-08-14). Task 2b is in fix round 1. No Critical; three Important.**

36. **The asserted cost bound measures the one shape the implementer optimised.** A command line a
    quarter the size blows through the 10 000 ms ceiling: 8 000 short args (248 KB) costs **21 563
    ms** where r5 costs 22 320 — **the fix bought nothing on that shape** — and 20 000 args (620 KB)
    costs **127 182 ms**. Attribution measured directly: the awk scan is **114 ms**; the bash loop is
    **19 612 ms**, and the cost is the `args="$args$FIND_TOK_SEP$tok"` accumulation, **O(n²) in
    tokens per clause**. *The awk scanner is exonerated.* Inherited, not introduced. **This is the
    task's own thesis applied to its cost guard: a test built from the same idea as the code confirms
    the idea.** → in fix round.
37. **The corpus catches the mutants its author imagined — measured one iteration further out.**
    46 corpus payloads contain `xargs`; **none is path-qualified.** Deleting `*/xargs` from both arms
    of `find_exec_commands` leaves the corpus at **419 PASS / 0 FAIL** while
    `… | /usr/bin/xargs -0 sed -i` goes 2 → 0 and **destroys all three `.meta` files**. Calibration:
    three of the reviewer's five mutants *were* caught, so the corpus works — it just does not cover
    this. The task's own §5 had already noticed the shape (three of its mutants reddened zero first
    try) and added five payloads; this is the same finding one level out. **The deliverable is the
    sweep, not the payload:** for every branch that exists on purpose, is there a payload that would
    notice its removal?
38. **The exemption mechanism accepts "this is a known live hole" as a monotonic waiver.** The brief's
    property is *verified false positives*; the guard accepts `X` plus **any non-empty string**.
    Three records use it for **true positives** and two were executed: `awk -f script.awk` (127 B →
    40 B) and `sed --in-pl` both destroy files. **So a future round can downgrade a real block to a
    permit by typing `KNOWN HOLE` in the note column and the guard stays green** — defeating the very
    mechanism the brief says makes the r3→r4→r5 pattern impossible to repeat. Fix: distinct markers
    with the count of known-holes asserted.
39. **43 of the 45 exemptions were executed against real `.meta` files and caused no damage
    whatsoever** (byte length + cksum identical). Their reasons are measured facts, not assertions.
    Recorded because it is the strongest evidence in the wave that a mechanism was built honestly.
40. **Minor, all confirmed and carried:** the `awk`-failure fail-open is inherited (a broken `awk` on
    `PATH` → rc=1 on both new and r5); the unbalanced-apostrophe false positive reproduces
    (`# it's only a read` above a read-only find → 2 where all three earlier versions → 0), bounded
    by the route precondition, and it cost the reviewer one blocked probe; a **2–3× slowdown on the
    linear path** (576 ms vs r5's 267 at 71 KB; 42 vs 38 ms on ordinary commands); and the second
    `unity_hook_block` after the unparseable one is unreachable — correct, but a fall-through rather
    than an `else`.
41. **A trap worth knowing beyond this task: the interactive `find` here is a `bfs 4.1.1` wrapper**,
    exactly like `grep`→`ugrep`. Task 2b's reviewer used `/usr/bin/find` (GNU 4.9.0) for every
    damage measurement. **Add it to the standing facts** — an absence or a behaviour claim made with
    the interactive `find` is the same silent-false-negative class.

**From Task 10's closing re-review (2026-08-14). Both findings ADDRESSED; one comment fix in round 2.**

42. **`dead_body="$(cat "$REPO/$dead_f")"` is the same unguarded `set -e` shape, three lines above
    the `case` the fix round edited, in the loop body that round rewrote.** Measured: one tracked
    scanned file made unreadable → **rc=1, PASS=16, FAIL=0** — the file asserts 16 of 49, reports no
    failure of its own, and the live-pointer scan never runs for the remaining files. Predates both
    commits, so it is not new breakage and did not extend the loop. **The habit recurring in the same
    block is the finding**; the repair is the one-line arm now used twice in that file. **→ a later
    guard pass.**
43. **Four holes in the new heredoc tracker, with measured directions and measured unreachability.**
    Lax (payload silently dropped as commentary — the hole this round closes): a **variable
    delimiter** (`cat <<$D`), where `match()` finds no introducer so the tracker never enters; and
    **two heredocs on one line** (`cat <<A <<B`), where only `A` is followed. Strict (a genuine
    comment stops being exempt): `x=$((1<<n))` latches on `n`, and a `<<EOF` inside a **trailing
    comment** latches. **None is reachable on this tree** — all 7 real introducers use a literal or
    quoted delimiter, one per line, independently re-derived over 20 files. *A limitation with a
    measured reachability is a different object from one without, which is why this row records
    both.*
44. **The tracker's awk is portable.** Byte-identical output under **gawk 5.2.1, mawk and busybox
    awk** across 12 probe shapes, and `\047` works under mawk — no finding for the planned macOS
    pass, though this is the file that introduces `\047` to the repository.

**From Task 13's closing re-review (2026-08-14). Task 13 is COMPLETE at `222e40e`; every finding
ADDRESSED, none returned to the fix loop.**

45. **The demonstrated blindness is not 167 assertions. It is 1189 — the whole suite.** The reviewer
    did not repeat the implementer's probe: it reverted **all six** payload files to their pre-task
    content (revert proved applied by `cmp` on all six plus marker-absence) and ran the **entire
    suite**: **`Total: 1189  Passed: 1189  Failed: 0`, rc=0.** Every word this task added across six
    shipped surfaces — now including an agent definition and a command, which **more** guards read
    than read the skill directory — can be deleted with the whole suite green. **The finding did not
    grow by two files; it grew from "four guards do not see this" to "nothing in the repository sees
    this."** *(That run also settles the one item marked unverified in round 0: the clean-tree tally
    at `234fa85` is 1189/1189 rc=0.)*
46. **`.claude/skills/unity-planning/SKILL.md`'s `**Files:**` template teaches the defect the anchor
    rule forbids** — `- Modify: \`Assets/Scripts/Existing.cs:123-145\``. It is **chained to this
    loop**: `subagent-driven-implementation/SKILL.md` states a plan written by `unity-planning` sits
    at `docs/features/<slug>/plan.md`, so that range is written into a plan, carried into a brief,
    and read after other tasks have moved the file — the exact rot path the rule describes. **Found
    only by a third probe shape** (a generic path-with-line-number pattern; the token sweep and the
    bare-`:NNN` sweep both miss it), and the reviewer filed it as **its own round-0 miss**: its first
    sweep was token-shaped too, *"the identical defect one level up from the one I filed."* One
    template line. **→ Task 11, and add the file to its Files list.**
47. **The three review requirements now live in two files at two fidelities with nothing guarding
    their agreement** — `task-reviewer-prompt.md` compressed, `re-review-prompt.md` full. **A new
    two-file agreement obligation, of exactly the class Step 0 existed to close, created in the
    commit that closes Step 0.** The same commit applied *point-don't-restate* to the four-shapes
    Minor and *restate-compressed* here; the asymmetry is defensible — a reviewer that must open a
    second file before it knows what to do will not open it — but the pair must be edited together
    and no test says so. **→ a later loop pass.**
48. **`final-reviewer-prompt.md`'s bare-numeral regex is narrower than its own prose, in the one
    direction this repository has already been bitten.** Judged by **executing** it: for
    `NOUN=hooks` over `README.md` + `docs/ARCHITECTURE.md`, the shipped
    `grep -rniE '[0-9]+[^0-9]{0,40}hooks|hooks[^0-9]{0,40}[0-9]+'` returns **7 lines**; the plain
    noun search its own sentence prescribes returns **26**. It discards 19 of 26, and **a count
    separated from its noun by a line wrap is in the discarded set** — the exact failure
    `tests/test-derived-counts.sh`'s own note records (README's "71 of 101", line-wrapped, thirteen
    lines below its own correct 99). Dropping the digit half makes the recipe match its sentence.
    **→ a later loop pass.**
49. **One observation on the delegation, not a finding.** Of the three ways a mutation lies, the one
    named **inline** in `task-reviewer-prompt.md` is the one that manufactures a **false Critical**;
    the wrong-shape mutation — the one that makes a first reviewer **drop a real finding** — is only
    in the sibling. **That is the more expensive direction for a review that gates every task.**
50. **A no-regression signal worth keeping: `Passed` constant across a moving `Total` is valid, and
    here is why.** A passing python test emits no `PASS:` token; a failing one emits `FAIL:`. So
    `Total` rises by exactly the number of *failing* python assertions — 1189 → 1191 (2 drift) →
    1193 (4 drift) — while `Passed` is untouched. **A regressed bash assertion would drop `Passed`.**
    Constant 1189 across a moving `Total` is therefore evidence, not a coincidence.

**From Task 10's round-2 re-review (2026-08-14). Task 10 is COMPLETE at `5db856d`.**

51. **Four more heredoc-tracker shapes, found by a reviewer looking past the five it was handed.**
    `<<` inside a **single-quoted** string (`awk 'BEGIN { print "a<<b" }'` → latches on `b`), inside a
    **double-quoted** string (`msg="use << to open a heredoc"` → latches on `to`), and in a **case
    pattern** (`*"<<Q"*)` → latches on `Q`) are all **strict** and share the root cause of the two
    already-known strict rows — leftmost-anywhere `match()` on a non-comment line. **The fourth is
    the one that matters: a backslash line-continuation before the delimiter** (`cat << \` + newline
    + `EOF`) — confirmed with `bash -c` to be valid shell that really opens a heredoc, and the
    tracker **never enters**. **That is a THIRD lax trigger**, and the block's closing sentence names
    only two. Unreachable on this tree (census re-derived a third time, differently shaped: 46 lines
    containing `<<` across 20 scanned `.sh` files → 39 here-strings, 0 whole-line comments, 7 real
    introducers, all with a literal or quoted delimiter, one per line, at exactly the file:line pairs
    the shipped comment names). **One clause repairs the sentence if that block is ever touched.**
52. **A comment-only claim needs three proofs, not one, and the reviewer gave the reason.** Stripping
    `#` lines to compare revisions **would itself hide a change inside the single-quoted awk
    program**, where a `#` line is not a shell comment. So: `git diff -U0` (every changed line begins
    with `#`), comment-stripped revisions identical, **and the awk program extracted from each
    revision `cmp`-identical** — the third is what closes the gap the first two leave. Behaviourally
    corroborated: per-file tallies across the full suite unchanged between the two commits.

**From Task 4's round-2 re-review (2026-08-14). Task 4 is COMPLETE at `8056f53`.**

53. **The unreadable-origin sentence is false for a path this payload no longer ships.** Constructed
    an upgrade across a payload shrink with a mangled origin: the payload loop never reaches a path
    that is not in the payload, so **no row is written** — *"recorded as yours"* is false and
    `--purge` **leaves** the file. The same run also says *"dropped from the payload have your
    edits"* about a file nobody edited (the `ORPHAN_KEPT` line, driven by the union and outside the
    N2 split). Narrow reach (needs a shrink **and** a mangled origin), and the consequence is debris
    the user believes is purgeable — **the inverse of the direction that was fixed, and no data
    loss.** The repair is not a wording tweak: the sentence is right for every in-payload case, so
    the orphan path must either write a row or be excluded from the unreadable bucket. **→ Task 4b
    or 4c, whichever opens that region.**
54. **A comment-precision note, not a defect.** The justification for routing a both-unreadable-and-
    edited file under the unreadable header — *"the installer cannot know it was edited; that row is
    precisely what it can't read"* — **overstates.** Field 2 is still readable, so a drift *does*
    prove an edit whichever value the origin held; what the installer cannot recover is what the
    baseline **meant**. The routing is still right for two better reasons: the unreadable header is
    **never false** in that state and is strictly more informative, and reporting under both would
    revive the double-count defect exactly. **→ Task 11.**
55. **A trap for anyone re-checking a keep-or-overwrite claim, worth more than either finding.** The
    reviewer's first option-B probe used an **unedited** file and looked survivable — the overwrite
    *had* happened, but **the toolkit's bytes are identical to an unedited file's**, so only the
    receipt row betrayed it. **Measure this class on an edited file, or by reading the row. Never by
    the bytes.**

**From Task 3's implementation (2026-08-14, `6928a43`, in review).**

56. **`docs/GETTING-STARTED.md`'s reachability sentence is now false, and nothing guards it.** Task 3
    took the count from **1 of 6** to **5 of 6**, which falsifies *"The other five are named by no
    agent, command or skill"*. **Ruling R7 stands: it goes to whichever of Tasks 3 and 7 lands
    SECOND, and must become a derived claim row rather than corrected prose** — corrected prose
    falsifies again on the next reachability change, which is this wave's own D5 thesis. Task 3's new
    guard already prints the derived replacement figure on every run. **→ Task 7.**
57. **`docs/GETTING-STARTED.md` still credits `/unity-doctor` with "skill/package alignment"**, a
    check deleted on 2026-08-03. **→ Task 11.**
58. **`tests/test-shipped-citations.sh` rule 2 was structurally blind to `.claude/scripts/…`
    paths** — its first test requires the token to name a real file **in this repository**, and that
    directory does not exist here, so **a misspelled installed-script path resolved to nothing in
    every installed project with the suite green.** Task 3 added rule 3 for it. *Recorded because the
    shape is the wave's own subject: a guard whose scanned set is not the reality it claims to
    guard.*
59. **Handed to Task 12 while it was running** (forwarded directly, not left in a report): every
    `--help` string names `./scripts/…`, **10 hits across 7 files**, wrong in an installed project —
    and Task 3 made it *more* visible by wiring four surfaces to send readers there. Plus the
    `grep -q` form of the early-exit trap live at **six sites** (`detect-missing-refs.sh` and five in
    `validate-asmdefs.sh`), found by reading rather than by sweeping, so **Task 12 must treat the
    list as a cross-check on its own derivation — if its sweep finds fewer than six, that gap is the
    finding.**

**From Task 12's implementation (2026-08-14, `daf745a`, in review).**

60. **The early-exit trap has one site that actually kills, and its consequence is a silent
    user-facing failure, not a script bug.** `scripts/generate-claude-md.sh`'s asmdef-name read
    (`sed … | head -1` in a bare assignment) on a `.asmdef` producing **80 KB** of sed output — past
    the 64 KiB pipe capacity — exits **141 with zero bytes of document**, dying right after the
    "Architecture stack" line; the same file at **413 B** exits 0. **Both halves of the trap in one
    fixture.** And `install.sh` calls the script inside `if … 2>/dev/null`, **so the install
    completes, writes no `CLAUDE.md`, and prints nothing.**
61. **The recorded ground for excluding `scripts/` from the pipe sweep was a *size* argument, and
    size is not what decides.** Measured at 1 / 50 / 120 / 400 KB: **a one-line haystack never fires
    at any size**, because grep must read the whole line and therefore drains its writer; the same
    bytes newline-separated fail open from ~50 KB. So the historically-named exception
    (`validate-asmdefs.sh`'s list) was safe because of a **`tr '\n' ' '` seventy lines above it**,
    not because the list is small — **right verdict, wrong reason, and nothing re-ran it.** *This is
    the most transferable measurement in the task: the sweep's exclusion was justified by a property
    that does not govern the failure.*
62. **Two plan premises had gone stale and were reported rather than resolved.**
    `scripts/validate-architecture.sh`, whose `| head -1 … || true` instances Step 1 asks about,
    **was removed 2026-08-13** and none survive anywhere — the question was answered on merit anyway,
    by measurement: `|| true` really is safe, the trap fires but the value is already complete. And
    **`tests/test-install-dryrun.sh`'s own record went stale after Task 4** — **nine** row writers,
    **six** read the mode, not the "eight/five" it records. **That second one is a live stale claim
    inside a test file. → Task 11.**

**From Task 3's and Task 12's reviews (2026-08-14). Both are in fix round 1.**

63. **A new class nobody has swept: the pipeline whose LEFT side fails.** `scripts/studio-doctor.sh`
    dies at `A=$(find "$CLAUDE_DIR/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')` when the
    directory is missing — `find` exits 1, `pipefail` promotes it, `set -e` kills the script:
    **rc=1, zero `FAIL` lines, no summary.** Four consecutive assignments share the shape. **This is
    the opposite cause from the trap Task 12 owns** — there a *reader* exits early and SIGPIPEs its
    writer; here the *writer* fails — and **neither of Task 12's needles reaches it.** Task 12's
    reviewer swept for early-exiting readers and found none beyond `tail -1`; **that is the wrong
    direction for this one.** Routed to Task 12 to rule on scope and to derive whether other swept
    pipelines have a failure-capable left side.
64. **`/unity-doctor` Check 2 says `It exits 1 when anything FAILed and 0 otherwise`, and that is
    false** — the death above produces rc=1 with no FAIL and no summary, and a model following Check
    2's own `PASS`/`WARN`/`FAIL` mapping reports **WARNING** on a project whose entire
    `.claude/rules/` is gone. **The text Task 3 deleted caught exactly this** (*"Verify expected
    directories exist … Any missing directories → ERROR"*). **The duplication removal was right and
    a coverage narrowed silently underneath it, while the commit's own text claims coverage.** → in
    Task 3's fix round.
65. **A satisfied exemption is stale by definition, and the handover made keeping it the default.**
    `tests/test-shipped-citations.sh`'s `SC_REACH_PENDING` entry is consulted **only** for scripts
    already found unreferenced, so once Task 7 wires the generator the entry goes inert **and
    stays** — from then on that script can be wired *and unwired again* with no red, permanently.
    Measured: entry present + reference added → green; entry present + reference absent → green.
    **They differ by a reference and agree on green.** Task 3's report said *"you may delete it; you
    are not required to"*, which makes a quiet permanent relaxation the expected outcome. → in Task
    3's fix round, with the guard failing when a pending name **is** already named.
66. **Two shipped statements in Task 12's own commit name the wrong reason.**
    `provenance.tsv`'s `generate-claude-md.sh` row and `tests/test-bash32-compat.sh`'s ruling block
    both say the failing install *"prints no diagnostic"*. **It prints two** — a generic
    `warn CLAUDE.md generation failed — skipped.` and a Next-steps line. What `2>/dev/null` swallows
    is **the generator's own diagnostic**, so the install exits 0 with no `CLAUDE.md` and only a
    warning that does not name the cause. **This is the defect class the task is about, committed in
    the round that names it** — the same round that overturned an exclusion for exactly this shape.
67. **The widened pipe sweep reports green over zero files**, and the sibling guard from the same
    wave already carries the fix. Mutation verified applied: scope pointed at a nonexistent directory
    → **7 pass / 0 fail over an empty file set**. The round's own comment claims the derived glob
    means *"no list here can go stale"* — **true for additions, false for an emptied scope.**
    `tests/test-help-ranges.sh` opens with a non-empty index assertion; one line closes it.
68. **`tests/test-install-dryrun.sh`'s own record went stale when Task 4 landed, and nothing guards
    it.** It says *"of the eight row writers, five read the mode and three hardcode it"*. Derived at
    HEAD: **nine** writers, **six** read the mode, **three** hardcode — the *three* half and the
    three names are right, the other two figures are wrong. **It is Task 4's rot** (Task 4 added the
    ninth writer and the sixth `stat -c`), and Task 12 correctly measured it and handed it back
    rather than editing a file outside its Files line from a concurrent worktree. **→ whichever task
    owns `install.sh`'s numbers next.**
69. **Three smaller measured facts worth not re-deriving.** `test-help-ranges.sh`'s "six" is a
    **different six** from the six installed scripts — only three overlap, so "green on all six"
    does not mean what it reads like. The **heredoc `--help` texts** in three scripts are unguarded:
    corrupting one leaves the suite green, documented as out of scope, so *"the suite checks every
    `--help`"* is not true. And **all six scripts genuinely run from both `./scripts/` and
    `./.claude/scripts/`**, so Task 12's additive fix was the right shape — a flat rewrite would have
    been wrong in the other direction.

**From Task 3's and Task 12's closing re-reviews (2026-08-14). Both COMPLETE and merged.**

70. **`.claude/hooks/warn-filename.sh` has a fifth live writer-failure site, and the round recorded
    "four, all `studio-doctor.sh`".** Anchor: the line beginning
    `CLASS_NAME=$(grep -oE '(class|struct)\s+\w+'`. Measured: a payload with a declaration token →
    rc=0 and a warning; a payload **without** one (`    : MonoBehaviour\n{\n  void Awake() {}\n}`)
    → **rc=1, no output.** Its `if grep -qE ':\s*(MonoBehaviour|ScriptableObject|…)'` guard proves a
    **base-class clause**; the pipeline needs a **declaration token the guard says nothing about** —
    **character-for-character the round's own correct finding, one file over.** The payload is
    routine: the second half of an Edit tool's `new_string` is a fragment.
    `tests/test-hook-advisory-exit.sh` does not exercise this hook, which is why the suite is green.
    **Important. No owner — triage at the whole-branch review.**
71. **The deferral of the general failing-left-side needle names no retirement condition, so it is an
    exemption that cannot ever close.** The `stat -c` precedent it invokes *does* name one (fix the
    six sites and the needle becomes addable); here the blocker is `uninstall.sh:204`, which is
    **correct code** and will never be "fixed", so the deferral is permanent by construction —
    **the exact class this wave filed against another task the same night.** Two exits that do not
    make a guard guess at control flow: **(a) needle the unprotected *form*** — flag `X=$( … | … )`
    that does not end `|| true`, which repairs `uninstall.sh:204` with a one-token no-op and turns
    the needle green on a tree one token from today's; or **(b) scope the needle to failing-capable
    left sides** (`find`, `grep`, `jq`, `sha256sum`, `sort`, `git`) and carry that one site as a
    named exception with a written retirement. **Do not carry the deferral a second time without
    one.**
72. **The failing-left-side derivation is not reproducible, and that is the finding.** The round
    reported buckets summing to 39 against a stated class of 38; an independent sweep under an
    explicit definition got **62 piped bare assignments, 26 immune by `|| true`, 36 unprotected, 27
    builtin left sides, 9 external, 7 guarded, 1 adjacent-guarded, 1 live.** **Fourth membership
    disagreement in this wave, and the fourth to be a definition dispute.** **Whoever inherits the
    sweep carries a written class definition, not a count.**
73. **Three measured residuals in shipped text, all Minor.** `rc=1` should read **`rc=2`** in two
    places (`scripts/generate-claude-md.sh`'s `THE || true IS A DELIBERATE BEHAVIOUR CHANGE`
    paragraph and the matching `provenance.tsv` note) — GNU `sed` exits **2** on an unreadable file,
    reproduced twice; *a measurement written in the round that corrected another measurement in the
    open.* `grep_pipe_check`'s new docstring **restates the membership in the same sentence that
    tells the reader not to** — delete the `which is …` clause, keep the array names. And
    `studio-doctor.sh`'s new comment names the cost as *"an undercount reported as a count"* but does
    not say the permission case now returns **rc=0 with `0 failure(s)`** — i.e. reports **healthy**
    on a project with an unreadable directory inside `.claude/`. **That last one is a caveat for
    Task 3's command body, which maps rc=0 to healthy.**
74. **The non-empty-scope assertion is a threshold, not a scope check.** Emptying **one** of the two
    arrays leaves the sweep at 2 files — losing `.claude/hooks/` and `scripts/` entirely — and the
    guard stays green. Total collapse is caught in both directions (verified independently, each
    array with its own message, **so no OR is hiding an AND**); **partial collapse is not, and a
    renamed directory or a repo-layout move is the likelier accident.** Documented at the code.
75. **Two Task 3 residuals worth the next reader's time.** `/unity-doctor` Check 3's opening line
    *"These five are outside what it reads"* is **falsified by its own item 1 two lines later** —
    the accurate predicate is *outside what it **reports***. And Check 3 item 1 tests **existence**,
    so an **empty-but-present** `.claude/agents/` passes both it and the script (`INFO agents=0`,
    `0 failure(s)`, rc=0). Asserting non-empty closes it for free. **→ Task 11.**
76. **A structural result worth keeping: "summary printed, then dies" is impossible.**
    `scripts/studio-doctor.sh` ends `printf … summary` / `[ "$FAIL_C" -gt 0 ] && exit 1` / `exit 0`,
    with nothing after the summary that can print or abort. **So *summary present ⇒ every check ran*
    is sound, not merely observed** — which is what makes Task 3's three-state table a real
    invariant. The table's third row reads *"no summary line, **any exit status**"*, and that clause
    is what makes it survive a **SIGTERM (rc=143)**; "exit 1" would have been wrong there.

**From Task 2b's closing confirmation (2026-08-14). COMPLETE at `c050743`, merged.**

77. **A two-sided `hist` forgery is invisible to any count.** Rewriting one record `222`→`000` and
    another `000`→`222` in the same edit keeps the total at 211 and reds nothing. **This is the
    structural limit of a count, not a gap in the guard** — recorded so nobody "fixes" it with a
    third count. The one-sided directions *are* caught, in both senses: inventing protection on a
    permit reds **two** assertions (the hist count and the no-unexplained-permit rule); inventing it
    on a block reds one.
78. **The three `H` records are live holes and two are verified destructive by execution** —
    `awk -f script.awk` (127 B → 40 B) and `sed --in-pl` (all three files rewritten). **The ceiling
    of 3 is the only thing keeping them from growing.**
79. **Two accepted false positives, both blocking reads and both clearing a byte-identical retry:**
    any `$(…)` inside a `find … .meta` command, and an unbalanced apostrophe on any line of a
    multi-line one.
80. **The cost residual is documented and has no cliff.** 1.4 MB / 131 072 tokens still exceeds the
    10 000 ms ceiling, but the law is linear at ~75–90 µs/token across every constructed shape
    including a 4.2 MB one, with **~6× headroom at every asserted point**. *The character of the
    finding changed between rounds: round 1 broke the ceiling at 248 KB with a shape-dependent
    blowup.*
81. **bash 3.2 was never executed.** `local -a`, `args+=()` and `${#args[@]}` under `set -u` are
    reasoned, not measured — awaits the macOS host pass. Documented in the hook beside the guard.

**From Task 5's closing confirmation (2026-08-14). COMPLETE at `0755d2a`, merged.**

82. **The `> "$RECEIPT"` guard's stated limit has exactly one entry, and folding is what keeps it to
    one.** `$SOME_CMD /dev/null "$RECEIPT"` still passes. The alternative — extending the limit —
    was rejected on the implementer's own ground, which is the better statement of it: **"a limit
    with one entry is a caveat; a limit with a growing list is a disclaimer."**
83. **Rule 3 misdiagnoses a line that only *reads* both references** (`diff "$RECEIPT_TMP"
    "$RECEIPT"`, or a log line naming both): it is short-circuited into the write counter and reds as
    an ownership violation. **Fail-closed and loud**, `lines=` points straight at it, documented
    beside the rule.
84. **Three of the four `CLAUDE_MD_BRANCH=skipped` arms are covered only by the shared recording
    point**; the block **inherits the unreadable-origin stickiness defect** (it reports that state
    once, not persistently); the entries' consequence prose (*"they will never fire"*, *"no MCP
    server to reach"*) is **reasoned, not measured**; and the block's internal **ordering** is
    `install.sh`'s line order, asserted nowhere — only its position relative to `Next steps:` is.
85. **B.11's coupling to B.10** is real and **avoidable** (reuse another run's `INSTALL_OUT`), and it
    fails safe — an extra red, never a missed one. Agreed deferral.
86. **`shellcheck` is not installed on this host** and CI now lints a 580-line test file. Neither the
    implementer nor the reviewer ran it; **the report says so plainly rather than implying it**, and
    CI is the authority.
87. **A merge fact worth keeping: `main` is `3e4c6e5` and the wave's bases are NOT ancestors of it.**
    The integration branch is `pioneer/surface-criterion-and-gaps`. A reviewer checked `main` first,
    found `install.sh` there lacks Task 4 entirely, and corrected the controller's framing. **Suite
    totals never carry across a merge** — 2811 in the worktree became **3099** on the merged tree,
    exactly 3041 + 58. **What carries is the failure set and the discovery invariant** (glob = find =
    headers).

**From Task 7's review (2026-08-14). In fix round 1.**

88. **The refresh arm emits the region one byte longer than the fresh arm, on every variant, and the
    two producers are only "one producer" for *content*.** `emit_marked_region()` ends `echo ""` and
    `install.sh`'s `/kinglet:generated:end/ { print ""; print; … }` adds a second. Bounded
    (52 → 53 → 53 → 53 across four installs, `cmp`-clean between runs 2/3 and 3/4), prose outside
    byte-identical, and **the first `/unity-init` after a refresh install silently normalises it away
    — producing a one-line `git diff` the user did not ask for.** **The fix is Task 4b's**
    (`install.sh` is not Task 7's file); **the claim is Task 7's**, because the sentence asserting
    agreement lives in its file. *A producer that silently normalises another producer's output is
    not one producer; it is two that agree except where one of them loses.*
89. **Two Task 7 claims are contingent on Task 4b and become moot if it lands.** *"This is the one
    producer … so running it is how this command and the installer stay in agreement"* is off by one
    byte today; and *"refreshes exactly this region on every run"* is an unqualified universal while
    an installer meeting a missing `end` marker **drops everything below the region and prints
    `ok Refreshed the generated section of CLAUDE.md (your prose untouched)`** — the false-reassurance
    half of 4b's defect, restated in a surface a model reads. **Both are being qualified now rather
    than deferred, because 4b is not dispatched and a report file is not a delivery mechanism.**
    **→ simplify both when 4b lands.**
90. **`scripts/generate-claude-md.sh`'s `KNOWN_PACKAGES` (22 ids) contains none of the five packages
    the deleted hand-derivation named** — Timeline, Mirror, Photon, Fish-Net, Odin — and **Timeline
    and Mirror are ordinary manifest-detectable UPM ids.** The generator's only owner this wave was
    Task 12, which is **merged**, so nothing closes this unless it is recorded. **→ a later generator
    pass**; Task 7 softens the universal in the meantime.
91. **A hand-copied `.claude/` has no `.claude/scripts/`, so `/unity-init`'s remedy for that exact
    branch exits rc=127.** The command names the state by its cause and then strands the model in it.
    Loud, not silent. **→ in Task 7's fix round.**
92. **The empty `SC_REACH_PENDING` list is held by convention, not by a check.** Putting a name back
    **together with** the unwiring it exempts passes green — the retirement rule targets *stale*
    exemptions only, by design, inherited from Task 3. **Recorded so nobody reads the empty list as
    guarded.**
93. **The R4/R7 override was ruled correct, on a ground worth keeping: a directed instruction naming
    the artefact beats a general ownership rule.** R7 verbatim requires *"replaced by a derived claim
    row, not corrected prose"* and assigns it to whichever of Tasks 3 and 7 lands second. **Obeying
    R4's file ownership strictly would have required violating R7's explicit instruction.** No
    concurrent writer existed (`task-11` worktree confirmed absent) and the change is additive.

**From Task 7's closing re-review (2026-08-14). COMPLETE at `f804913`, merged.**

94. **The controller relayed a Minor that made a guard worse, and this is the record of it.** Round
    0's review noted the reference floor in `tests/test-shipped-citations.sh` had been left at 4
    while the live count rose 7 → 9; the controller relayed *"raise it"*; the implementer raised it
    to **8**. Measured in round 1: the raise **buys no detection** — a broken token expression yields
    **0** and trips any floor — while **creating a false-positive path.** The 9 references cover only
    **6 distinct scripts** (three files name one twice); dropping the two *duplicate* mentions leaves
    **6 of 6 scripts still named** and the floor reds with
    `expected at least 8; either the wiring has been removed or the token expression has stopped
    matching` — **neither disjunct true.** The reverse-direction arm, which actually owns wiring
    loss, stays green, and it reddens on its own when a script really is unwired. **And the retained
    sentence "the floor is set well below that" is now false in the same block that was edited.**
    Suggested value **6** — above half the tree, below the duplicate-consolidation cliff — or
    reconcile the sentence. **Nothing fails today. → whoever next opens that file.**
    *The lesson is the controller's: a Minor relayed without its measurement is a change made on
    someone else's confidence.*
95. **The `.claude/scripts/` precondition sits in step 2 while the rc=127 happens in step 1.** The
    bullet back-references step 1 explicitly, so a model reading on finds the explanation — but the
    guidance is not at the first point of failure. **And step 4's report contract was not extended to
    carry the package-gap item**, so Important 2's escape hangs entirely on step 1's own sentence and
    the two places disagree about what the report contains. **→ whoever next opens that command.**
96. **The citation form was forced by a guard, not chosen for style — and the reviewer proved it
    rather than reading it.** `docs/GETTING-STARTED.md` is named in prose because backticking it
    reds rule 2 (`FAIL: 1 shipped citation(s) name a file install.sh does not copy`), **the same
    guard that caught this task's `install.sh` citations in round 0.** *Recorded because a future
    reader will otherwise "tidy" the prose reference into a path.*
97. **`ProjectSettings/GraphicsSettings.asset` is a pre-existing token that resolves in a real Unity
    project but not in the fixture** — inherited, not this task's. **→ open.**

**Two Task 7 sentences are keyed to Task 4b and must be told to it:**

- *"One known disagreement, and it is the installer's, not the generator's"* — **the whole paragraph
  is deletable the moment 4b removes the `print ""` from the `/kinglet:generated:end/` arm.** Until
  then it is **the only place the delta is written down**, and nothing in the suite reddens on it.
- *"on every run that finds a well-formed one"* — **the qualifier can revert to the unconditional
  form once 4b makes the installer decline a malformed pair**, since the guarantee will then hold for
  every run that merges anything.

**From Task 8's implementation (2026-08-14, `c55f220`, in review).**

98. **No agent in the tree gates on anything, and that is wider than the plan asked about.** The
    brief expected the two builder agents to have no approval gate; a widened probe
    (`approval|gate|precondition|before you (start|begin|write)|docs/features`) across **all eight**
    `.claude/agents/*.md` exits 1. Both builders go **straight from their skill list to writing**,
    holding `mcp__UnityMCP__*`. **So row 11 did all three things `unity-brainstorming`'s HARD-GATE
    withholds.** *This is a fact about the agent layer, not about two commands.* **→ open, no owner.**
99. **`using-kinglet` behaves OPPOSITE to `unity-brainstorming` under the same guard, and the
    difference decides where an argument can live.** `UK_SECTIONS_EXPECTED` is a **five-heading
    inventory**, so a new heading **reds** here — measured — where `unity-brainstorming` has no
    inventory and a new heading was invisible (which is what Task 9's whole approach rested on).
    **Two sibling skills, one guard, opposite affordances.** Also measured: a thirteenth table row
    reds, and unbackticked prose in the Surface column reds via the residue rule. **That is why Task
    8's argument lives in the command bodies rather than in the skill.**
100. **The second exemption is named and deliberately not listed.** Row 4 — *a written plan handed
     over to be executed → `unity-planning` first* — skips `unity-brainstorming` entirely. **Adding
     it to a list would falsify the skill's own frozen sentence that it has exactly one exemption,
     and would build the artifact the skill explicitly refuses to build.** Row 4 left alone; whether
     it is legitimate or a hole is **a design question above this task**. **→ open, no owner.**

**From Task 6's implementation (2026-08-14, `ac98925`, in review).**

101. **The brief's stated reason for root rows staying sticky is wrong, and the implementer reported
     rather than resolved it.** **No `install.sh` writer emits `user-modified` for any project-root
     path** — all five write `toolkit` or nothing — so those rows can **never reach** the changed
     arm; the outcome the brief wanted is right and its mechanism is not. And **`MCP-SETUP.md` *does*
     ship a static reference copy**, contradicting the brief's *"no static reference copy"*, so
     giving it an arm would be **behaviour with no producer**. **→ the plan sentence is wrong; fix
     the plan, not the tree.**
102. **Why `c2d27f1f` failed, stated precisely enough to reuse.** That attempt compared against the
     **recorded** sha — and for a `user-modified` row the recorded sha **is the edited file's**, so it
     matched **while the work was still there**. The new comparison is against the toolkit's shipped
     copy, and **an edited file never equals the toolkit's bytes**, so it cannot answer yes while the
     work exists. *Two comparisons that look alike and differ in exactly the direction that loses
     data.*
103. **A ledger item came back narrower than recorded.** The doctor's unreadable-directory undercount
     (rc=0, `0 failure(s)`) reproduces **only when the receipt is absent**; with a receipt present the
     missing-files check fires first and it exits 1. **A ledger item wider than the truth is as much
     a defect as one that is narrower** — corrected here.
104. **Two more line-number citations shifted further** (`tests/test-mcp-doc-instructions.sh`,
     `tests/test-provenance-origins.sh`), comment-only, **already stale before this diff moved
     them**. **→ Tasks 10/11.** *Fourth and fifth instances in this repository of the rot the
     cite-by-anchor rule exists for.*

**From Task 8's review (2026-08-14). In fix round 1.**

105. **A controller override, recorded with its reasoning.** The reviewer recommended the
     agent-direct bypass become a **separate follow-up task**; the controller **widened Task 8's
     scope instead.** Grounds: the two agent files have **no other owner** in this wave; the change
     is **prose, not a capability**, so R8 does not bite; **the idiom already exists in both files**
     (each uses *"stop and say so explicitly"* for a different unmet dependency); and **the task's own
     title — "stop reading as entry points" — stays false if it closes one of two routes.** A
     separate task costs a full cycle for two paragraphs. *The reviewer's stated concern was that the
     finding not be lost when Task 8 is marked complete; widening satisfies that better than
     deferring.*
106. **The line that decides selection is the `description:`, and this repository already ruled so.**
     `docs/superpowers/specs/2026-07-30-surface-trigger-rules.md` says the command should win over
     its shadow agent *"because it is what shows up in the command palette."* The house style already
     encodes preconditions there (`/unity-review`'s *"after"*, `/unity-init`'s *"once per project"*,
     `/unity-fix`'s *"before proposing a fix from memory"*), and **no assertion in `tests/` reads a
     command `description:`** — verified. **A body-level precondition does not reach a model that is
     still choosing.**
107. **`111 PASS / 0 FAIL` on `tests/test-surface-references.sh` carries no information about a chain
     row's *content*.** Measured: reverting row 11 to its old bypassing wording is **111/0**, and
     writing an **overt exemption** into that cell is **111/0** — no assertion anywhere reads those
     characters. **The actual protection is `migration/baseline-inventory.json`'s per-file sha256,
     and it is whole-file, not semantic.** *The reviewer drafted this as a missing-guard finding and
     then falsified it itself* — recorded only so nobody later cites the green as evidence the row is
     protected.
108. **Row 4's routing is defensible and its recorded reasoning is not.** `unity-brainstorming`'s
     `## The category, and its boundary` keeps **two** lists — the exemption list it refuses to
     keep, **and an explicit not-an-exemption list** with two members. A handed-over plan is a **third
     member of the second list**, where adding it falsifies nothing; mutation M9 measured that
     section is read into `UB_BOUNDARY` but **is not frozen whole**, so the edit was available. *The
     reasoning is what gets inherited, which is why it is being corrected even though the outcome
     stands.*

**From Task 2c's review (2026-08-14). In fix round 1 — two Critical, both executed-destructive.**

109. **A class is derived by enumerating its mechanism space, not by listing spellings — and the
     reviewer did it: 343 generated members across eight argument positions, all run against two
     versions.** Every one of the round's twelve reproduced and blocked. **The divergence is what the
     method bought:** a backslash inside a quoted run (6 spellings, 5 arms), a bracket expression
     (2), ANSI-C quoting / `$( )` / backtick (3), and **all 27 direct-arm spellings uniformly
     permitted.** *Generated variants that leave an unterminated quote were excluded because
     `bash -n` rejects them — they never execute, so they are not members.* **This is the strongest
     class derivation in the wave and the shape to copy.**
110. **`meta_ref` tests `[*?]` while the glob metacharacter set is `* ? [ ] \`, and the scanner's own
     double-quote arm deliberately preserves a backslash** — *the two halves of one function disagree
     about what a backslash means.* `find Assets -name "*.\meta" -delete` returns **0 and deletes 3
     of 3 files.** **One character from the round's own row 8**, which *is* caught because bash
     consumes an unquoted backslash. `'*.[m]eta'` is sharper still: it **does** say `.meta` with a
     glob metacharacter standing inside it — the exact phrase `meta_ref` is documented to test.
111. **`exit 3` is silent and non-blocking, and an assertion labels it a block.** `_lib.sh` and
     `docs/HOOK-REFERENCE.md` both fix **exit 2** as the blocking code. Measured with a broken `awk`:
     **rc=3, stdout 0 bytes, stderr 0 bytes** — so the destructive payload **runs**, and the "loud
     error" framing is wrong in both the comment and the report. **The `|| META_ROUTE="1"` fallback
     choice is right** — the flipped version is strictly worse (silent *permit*, rc=0). **The finding
     is the label, not the branch.**
112. **A mutation the round recorded as "behaviour-preserving by construction, red 0" reddens 2.**
     The `if (index(v, ".meta") > 0) return 1` early return is **the bare-path arm**, not a
     performance guard: without it control falls to `if (v !~ /[*?]/) return 0` and any token naming
     `.meta` with no glob metacharacter returns 0. **A future round reading the report would delete
     it as dead weight and reopen the route.** *Fifth measured instance in this wave of a mutation
     result that meant something other than what it looked like.*
113. **The `X`-ceiling laundering exploit was attacked and confirmed, and is correctly disclosed
     rather than fixed.** Replacing a genuine verified-false-positive record with an
     executed-destructive live hole, marked `X`, leaves **every asserted count unchanged** and the
     per-record verdict assertion passes because the hook really returns 0 on it. **The file states
     this exploit explicitly above its own ceiling.** *Consistent with the earlier ruling that a
     two-sided forgery is the structural limit of a count — recorded as verified, not as a finding.*

**From Task 6's review (2026-08-14). In fix round 1.**

114. **A guard whose removal leaves the suite entirely green, standing between an arm and the exact
     destruction that got `c2d27f1f` reverted.** `install.sh`'s `[ -f "$ref" ]`: `sha_of` returns the
     **empty string** for a missing file, so without it a `user-modified` row for a **retired
     surface** (no shipped copy) whose project file is unreadable matches `"" = ""`, is reclaimed out
     of `MODIFIED_FILES`, and is **deleted by the orphan prune** — measured `head: survives` →
     `mutant: DELETED`. **The doctor's analogous guard IS asserted, so the coverage is asymmetric in
     the destructive direction.** → in Task 6's fix round.
115. **`--toolkit-dir` pointed at the project reports every live edit as reverted.** The
     `!= "$PROJECT_DIR"` guard exists **only in the auto-detect branch**; the explicit branch
     validates `cd` and `.claude/VERSION` and nothing else. **Every file trivially equals itself**,
     so every `user-modified` row reports as put-back — *precisely the direction the arm's own
     comment forbids*: "reporting a live edit as reverted tells the user their work is not at risk
     when it is." No shipped surface passes the flag today. → in the fix round.
116. **The two-arm mapping is duplicated and nothing would notice it drifting.** `install.sh`'s
     `user-modified)` arm and `scripts/studio-doctor.sh`'s `toolkit_ref` each carry it; both are
     self-consistent and separately asserted, and **no assertion would notice them disagreeing about
     a specific file. A third write loop breaks both silently.** **→ open, no owner.**
117. **A pre-existing prune exposure gains one crafted shape.** A hand-written
     `.claude/../README.md` row marked `user-modified`, with the toolkit's bytes on disk, is now
     reclaimed and orphan-pruned (`base: PRESENT` → `head: DELETED`). **An equivalently crafted
     `toolkit` row already deletes it at base**, no producer writes `..` paths, and **no path
     normalisation exists anywhere in `install.sh`.** → open.
118. **A reviewer's own probe artifact, reported rather than filed as a finding.** Its first suite run
     copied the worktree with `cp -a`, carrying a `.git` **file** pointing back at the real repo;
     severing it made **15 assertions fail because git was gone** (`Total: 3115 / Failed: 50`).
     **`git clone` reproduces the reported numbers exactly.** *Sixth measured instance in this wave
     of a result that meant something other than what it looked like — and the first where the
     measurer caught it in its own harness before reporting.*

**From Task 8's closing re-review (2026-08-14). COMPLETE at `6f91053`, merged.**

119. **Six of eight agents still gate on nothing**, and **five of those six hold `Write` *and*
     `mcp__UnityMCP__*`**: `unity-coder`, `unity-fixer`, `unity-optimizer`, `unity-prototyper`,
     `unity-test-runner`, `unity-reviewer`. **This is Step 1's tree-wide finding, now two-eighths
     closed.** The residual route is a dispatcher that builds the screen or scene **itself** rather
     than dispatching a builder — `unity-coder` and `unity-prototyper` each hold
     `Write, Edit, Bash, Agent, mcp__UnityMCP__*`. **Correctly outside Task 8's title**: all three
     routes *into* `/unity-ui` and `/unity-scene` are now gated, which is what the title claims;
     `unity-coder` sits downstream of `unity-planning`'s fork by design and `unity-prototyper` **is**
     the exemption path. **→ open, no owner.**
120. **None of this task's prose has a semantic guard — measured three ways.** Reverting row 11 to its
     old bypassing wording, writing an **overt exemption** into that cell, or **deleting both agent
     precondition sections entirely** each leave `tests/test-surface-references.sh` at **111 PASS /
     0 FAIL**. **The protection is `migration/baseline-inventory.json`'s per-file sha256 — whole-file,
     not semantic.** *Recorded so nobody cites the green as evidence.*
121. **`tests/test-shipped-citations.sh` is blind to a backticked path that exists nowhere** — it
     resolves against the repo tree first, so only repo paths `install.sh` does not copy can red.
     **That is what makes `docs/features/*/design.md` safe**, and it is a pre-existing property.
122. **The strongest construction in the task was reusing an idiom each agent already performs.**
     Both builders already carried *"a sprite atlas, a font asset import … stop and say so
     explicitly"* / *"a lightmap bake, an occlusion-culling pass"*; the new precondition quotes it
     back (*"the same way you would for a sprite atlas you cannot create"*). **The gate reuses a
     behaviour the agent already has language for rather than introducing a novel instruction** —
     and it avoids a false-stop loop by noting *"the dispatching prompt usually names it."*
123. **The `description:` rewrite reclassifies both commands in the first four words**, which is what
     survives truncation: rendered together, the nine commands now sort into *"Use when the user…"*
     (six situation-triggered) and *"Use after / Use once…"* (`/unity-init`, `/unity-review`,
     `/unity-scene`, `/unity-ui`). **`/unity-scene`'s negative clause is buried third in a comma
     chain ~230 chars in** where `/unity-ui`'s sits right after the noun list — stylistic, since the
     opening clause survives truncation in both. **→ open.**

**From Task 2c's fix round 1 (2026-08-14, `20aa2b7`, in re-review).**

124. **The implementer's own diagnosis, and it is the wave's thesis turned on its author:** *"Both
     Criticals are the same sentence twice — a class is not a list of spellings, and I shipped a list
     twice. That is the failure mode my own §8 names, found in the deliverable."*
125. **Extending the stripped metacharacter set was measured to be the WRONG fix.** Each
     metacharacter needs its own semantics: `*` and `\` are **deleted** (zero-width / escape), while
     `?` and a bracket expression each match **exactly one** character and must become a
     **wildcard**. **Deleting `?` turns `*.m?ta` into `.mta` and loses a real match** — caught only
     because **busybox awk disagreed with the other four** on a test case. *The obvious repair to a
     character-class bug is to widen the class, and here that was the bug.*
126. **A runtime death nearly shipped inside the fix for the hole.** The natural character class
     `"[][*?" BS "]"` **ends in an escaped bracket that never closes**: `gawk`, `gawk --posix`,
     `gawk --traditional` and `mawk` **all die at runtime; busybox accepts it.** Every pattern is now
     a dynamic string, verified 26 token values × five awks in both directions. **A portability
     death in this hook is worse than any hole it closes**, and only one of five interpreters would
     have shown it.
127. **The ruling on Critical 2 was to fix rather than defer, on a consistency argument worth
     keeping:** *"Admitting a program as an introducer **is** vouching for it. Deferring a six-line
     application of a rule I had just argued for would be inconsistent."*
128. **A damage probe agreed with its author, twice in one task.** The first `evil/xargs` harness
     rewrote only **named arguments**, so every pipeline payload came back `unchanged` — rebuilt to
     consume stdin, all three destroy. *Seventh measured instance in this wave of a result that meant
     something other than what it looked like.*
129. **A disagreement that was never a disagreement.** The reviewer's `N3a` and the implementer's
     `N3a` **removed different lines**; the reviewer's is the implementer's `N1a`, red 2 on exactly
     the reviewer's two payloads. **The measurement never disagreed — the label did**, and it read as
     the containment line. **Every mutant now carries the line it removes.**
130. **Two sweep branches came back at zero and both got payloads, with the distinction stated:**
     `M2b` reddened nothing **because every payload also carried a `*`** — and the added `?` payload
     **does not discriminate it**, *"since a payload that fails to discriminate is what the sweep
     exists to find."* `X2a` is the documented single-site no-op, recorded as a **shape**
     discriminator because it is not destructive as written. `M2a` **stays 0 and is unobservable by
     construction.**

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
