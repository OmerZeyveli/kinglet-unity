`docs/superpowers/plans/2026-08-14-unmeasured-surfaces-and-floors.md`

# Ledger — Unmeasured Surfaces and Floors

**Base commit: `e17f310`** (`main`, the merge of `pioneer/surface-criterion-and-gaps`).
**Branch: `pioneer/unmeasured-surfaces`.** The whole-branch review at the end diffs `e17f310..HEAD`.

## RESUME HERE

**Tasks 1, 3, 4 and 5 are merged and both gates are green on the branch.** `Total: 3458  Passed:
3455  Failed: 0  Skipped: 3`, rc=0, **39** ANSI-stripped headers == `ls tests/test-*.sh | wc -l`
**39**; `provenance OK`. Baseline regenerated outside a worktree twice, at `--expect-drift 2` each
time (Task 1, then Task 4); Tasks 3 and 5 changed no `.claude/` file and contribute no drift.

**The cut is complete. Next: Endless Evolution, with Tasks 2, 6, 7 and 8 running alongside it.**

**A merge-time trap worth the line.** Regenerating the baseline and running the suite *before
committing it* produced **18 failures**, none of them real: `tools/kinglet_spike/inventory.py`
**refuses to inventory a dirty foundation** and named the uncommitted file in every message. Loud,
correctly signposted, and invisible to every implementer — **the spike suite skips in a fresh
checkout and in every worktree**, so only this checkout can see it. The controller is the only party
who ever runs the suite with a dirty `migration/` and is therefore the only one this can bite.
**Commit the baseline before running the suite.**

| task | state | commit range |
|---|---|---|
| 1 — the three hooks nothing has ever executed | **DONE**, merged `d770bf5` | `3ca4327..1ff204a` |
| 2 — execution-keyed hook coverage | open *(brief pending — consumes Task 1's output)* | |
| 3 — anchor the unanchored pathspecs | **DONE**, merged `3cc8aa8` | `4e299b6..ef8a7ab` |
| 4 — the doctor's two remaining compensations | **DONE**, merged `22c232e` | `4e299b6..f868677` |
| 5 — anti-vacuity floors, written | **DONE**, merged `1b948c6` | `4e299b6..34880d0` |
| 6 — a heading inventory for `docs/` | open *(brief pending — cites Task 5)* | |
| 7 — the claims with no owner | open *(brief pending — cites Task 5)* | |
| 8 — record what a second reader can reproduce | open | |

**Ordering that binds:** T1 → T2 (T2's mechanism is T1's output). T5 → T6 and T5 → T7 (both cite its
criterion). T3, T4, T8 are independent.

### Owner's ruling, 2026-08-14: cut to 3 + 4 + 5, then Endless Evolution

**The remaining four are not cancelled — they run in the background while the EE migration proceeds.**
The ruling came from a question worth recording, because it is the right question and this wave was
drifting away from it: *does any of this improve game development quality?*

**The honest split, and it is uncomfortable.** What reached a real Unity project was all in the
*previous* wave plus Task 1: `bash-gate.sh`'s four executed `.meta` destruction routes (a lost `.meta`
means a new GUID and **every reference to that asset breaks**, in scenes, prefabs and
ScriptableObjects); `install.sh` amputating the user's `CLAUDE.md` on every install while printing
success; `warn-serialization.sh` — the hook that catches a field rename without
`[FormerlySerializedAs]`, i.e. every configured value in every scene silently resetting — proven by
behaviour for the first time; and `warn-filename.sh` returning rc=1 with zero bytes mid-session on a
routine Edit.

**Of the eight tasks here, exactly one — Task 4 — reaches a user's project.** The rest are the
toolkit's claims about itself. The defensible case for them is real (`warn-serialization.sh`'s
hollowness was found *by* this kind of sweep) but **the marginal value is falling fast**: Task 1's
three rounds each found a genuine defect; Tasks 6/7/8 will find a number in a comment.

**And the largest gap is still untouched, as the plan's own last paragraph says: nobody has ever run
this toolkit inside Claude Code against a live Unity project.** No agent has issued a single command
to a real Editor. The fixture is **1 C# file, 0 `.meta` files**. So the toolkit's internal
consistency is now heavily measured and its behaviour on a game is not measured at all — and
continuing down this plan makes that imbalance worse, not better. That is what EE tests.

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

**Task 1 → `tests/test-hook-behaviour.sh`** (runner-provided; standalone it exits 0 asserting nothing).

- **The durable interface Task 2 consumes is the `HOOK-PROBE <hook> kind=… act=NNNB rc=… off_all=…
  off_own=…` lines on stdout — one per hook, written only by a probe that ran.** *Not* the TSV
  record file: it lives inside `$WORK_DIR` and `rm -rf "$WORK_DIR"` deletes it before the run ends.
  The file's own comment said Task 2 would read it; that is corrected in Task 1's fix round. **This
  is exactly what the Interfaces section is for — a brief written before the task ran would have
  guessed the TSV.**
- **Key on presence, never on the byte number.** Measured across clones of the same tree:
  `session-save` **540 / 552 / 559 B**, `session-restore` **293 / 315 B**. They vary with branch name
  and `git log` output. Nothing asserts them today; the moment something does, it is flaky.
- **Coverage is execution-keyed, and it is proven so.** Renaming only the `case` label — leaving the
  hook's name in the file three times — dropped the probed count to 11. A name-keyed sweep would have
  reported full coverage.
- **The anti-vacuity floor here has no ratio, and that is the point.** It is an identity between
  `.claude/hooks/*.sh` less `_lib.sh` and the distinct commands in `settings.json`, currently
  12 == 12. A 100 % floor that moves with the tree cannot go stale and cannot have been sized by feel.

  **CORRECTION, 2026-08-14 — this entry originally read "two *independently* derived tree quantities"
  and that word is false.** Settled by execution during Task 5's second re-review, after the
  implementer and its first reviewer reported **opposite verdicts for what looked like the same
  state**. Both were right; the discriminator is `settings.json`, not the hooks directory:

  | state | verdict | file |
  |---|---|---|
  | `.claude/hooks` **deleted**, `settings.json` intact | `FAIL … (0 present)` | 25 / 61 |
  | `.claude/hooks` **emptied**, `settings.json` intact | `FAIL … (0 present)` | 25 / 61 |
  | `find .claude -type f -delete` — `settings.json` gone too | **`PASS … (0 present)`** | **2 / 0** |

  `PRESENT_COUNT` is 0 in all three; `REGISTERED_COUNT` is 12 while the file exists and **0 once it is
  deleted**, so the identity is `0 == 12` (red) twice and `0 == 0` (green) once. **The two sides die
  together when the payload as a whole goes, and the file falls from 86 assertions to 2 while
  reporting green.**

  **What survives:** the floor is not stale, was not sized by feel, and catches every failure it was
  written for — deleted, emptied and mis-registered hooks all red it. **What does not:** the word
  *independently*, and with it the claim that this is the unqualified worked example. It is an example
  of an identity **and of Shape 3 (oracle collapse)** — the shape Task 5 discovered and named because
  of this. `docs/ANTI-VACUITY.md`'s F2 rules the repair — *an identity needs an absolute floor on one
  side* — and **that repair is not applied to `tests/test-hook-behaviour.sh`, nor is the file listed
  under what the document does not close.** → **Task 2**, which already owns that file's coverage
  derivation.

  **The lesson is the controller's, not Task 1's.** I wrote a property — *independence* — into the
  ledger from a description rather than from a measurement, told a later task to cite it as its worked
  example, and it took two agents reporting contradictory verdicts to surface it. **A ledger entry is
  a claim with the same shelf life as any other, and this file is read as if it were not.**

## Task 5 — adjudicated at the cap, merged, and the standing risk it leaves

**Five fix rounds, the cap. Rounds 1–3 resumed the original implementer; rounds 4–5 went to fresh
eyes**, because three consecutive rounds produced **the same class of finding — wrong figures in this
document's tables** — which is exactly the condition the loop names for switching.

**The switch paid for itself immediately.** The fresh implementer found the fifth instance of the
house defect that **four reviews had missed**: the floor set's head said *"at least 83 assertion
**sites**"*, and 83 is the tables' **row** count, in the section that rules one row per **bound** and
warns that reading it as a census of sites will overcount. It also reported an unsettled scope
question rather than editing around it.

**The last blocker is the one worth remembering.** Round 4 wrote: *"Those two are the only bounds
stated twice, and a textual dedup will not find them — they are worded differently in the two
tables."* **False in both clauses** — there were four, and an exact-string dedup finds one of the two
it missed. **The sentence told a maintainer that the cheapest available check does not work here, and
that check is what catches the instance the sentence missed.**

And round 5 found why it survived three rounds: the *Sites* table writes `tests/test-…` on 14 of 16
rows while every other table writes the bare basename, so the raw dedup returns **one** collision and
the second appears only after normalising the prefix. **The duplicate was verbatim-identical and
invisible to the obvious check because of a formatting inconsistency nobody had reason to look at.**

### The standing risk, named rather than closed

**Nothing in the tree reads a number in this document.** Proven by falsifying four headline figures at
once — `83 rows`→`999`, `81`→`4242`, the S2S subject `6`→`11`, Shape 1's `62`→`60` — and running the
nine guards that could plausibly read it: **all nine fully green.** Three files cite it, all in
comments. **A wrong figure here ships silently, which is why it shipped four times.** The dedup
command the document now carries is its only mechanical check, **and it is one a human has to choose
to run.** → the follow-up that gives `docs/` a guard (Task 6).

### Settled by criterion, not by needle

`install.sh`, `uninstall.sh` and `.claude/hooks/*.sh` hold **zero floors**, established by running
C1–C4 over all three rather than by one grep: install's fourteen count derivations reach only
`info`/`warn`/`printf` (**C3 fails**) and every numeric guard is `-gt 0`, which fires when the subject
is **non**-empty — that is the claim, not a floor (**C2/C4 fail**); the only non-zero exit in the whole
hook segment is `unity_hook_block`'s `exit 2`, the claim under test (**C4**), and hooks derive from the
stdin payload, not the tree (**C1**). For one round the document said *"holds no floor today"* only for
`tests/kinglet/**`, so zero rows from a segment meant **either** swept-and-empty **or** never-swept and
a reader could not tell which. It now says which.

## Task 3 — deferred

**The surviving universal is literally false at one value, and the exception is self-excluding.**
`tests/test-citations-resolve.sh`'s corrected bullet says *"no constant closes the class, because for
any constant there is a smaller narrowing above it."* Measured: set the floor to `LIVE_N` itself —
**125 green on pristine, 124 red on the smallest possible narrowing** (dropping
`provenance-skip.tsv`, which contributes 1). **A constant does close it: the one equal to the live set
size.**

**Ruling: carried, cosmetic, one word.** The only closing constant is a **transcription of the live
set size** — exactly what the two paragraphs above it forbid, in the bullet that exists *because*
`141`/`125`/`142` rotted. At that value the floor stops being a floor: it fires on every legitimate
file removal, and it stops closing the class the moment the tree grows. **No maintainer action
changes** — Task 5 owns the constant, and both the written and the strictly-correct versions steer it
away from "raise the number". `durably`, or `without transcribing the live set size`, makes it exact.

**`tests/test-mcp-naming.sh`'s `TMN_LIST` is a frozen four-name root list** that already omits
`CREDITS.md` and `MERGE-NOTES.md`, both tracked root Markdown — and `MERGE-NOTES.md` discusses MCP at
length. **This is the decay Task 3's own `:(glob)` justification predicts, already realized in a
sibling guard.** Routed here rather than fixed, because it is outside the brief's two-file scope.

**The three transcriptions of the code constant are closed, not deferred** — the bullet now carries
zero. The two surviving `30`s are a verbatim quotation of the withdrawn text and a historical
statement about it; both stay true if Task 5 changes the constant.

## Task 4 — deferred, and one obligation the shipped comment already cites

**`.claude/scripts/` is installed and nothing gives it a verdict.** `install.sh` writes it through the
separate `for group in scripts` loop; it is on **neither** side of the doctor's payload pin; and
`/unity-doctor` Check 2 **runs a script from it**. `scripts/studio-doctor.sh`'s shipped comment now
says *"that is a ledger item"* — **this entry is what that sentence points at.** Before Task 4, the
directory was not merely uncovered, it was invisible; it is now named in a shipped file with its
boundary asserted (`assert_not_contains "$TSD_PAY_TREE" "scripts"`, mutation-verified: adding
`.claude/scripts/muts1-probe.sh` reds it **by name**). → a later doctor pass.

**`awk`-first versus bash-last-assignment.** The test extracts install.sh's `PAYLOAD_FILES=` line with
`awk '…{ print; exit }'` — **first** match wins — while bash honours the **last** assignment. Measured:
a decoy `PAYLOAD_FILES=$(cd … ! -path './extradir/*' …)` placed *before* the real line installs
`.claude/extradir/` with the guard **74/0 green** and `provenance OK`. It needs two top-level
`PAYLOAD_FILES=$(cd ` assignments, a shape nobody writes and which does not exist. **Bounded, not
closed.**

**A behaviour-neutral edit reds three assertions.** `PAYLOAD_FILES="$(cd …)"` — quoting the
substitution, which is what shellcheck asks for — gives **71/3** while install.sh installs the same 61
files. **It fails closed and loud**, and the first failing assertion names the cause and the remedy in
its own message, so it is recorded as known brittleness rather than repaired.

**`assert_not_contains` is a substring claim, not set membership.** It cannot pass for the wrong reason
in the dangerous direction — `scripts` entering the tree is a whole line — but it could red spuriously
on a future member whose *name* contains `scripts`. `grep -qxF` is the one-word fix.

**A standing trust boundary, worth naming rather than filing.** The guard **evaluates a line of
`install.sh`'s own bytes** rather than re-implementing its `find`. Re-implementing it was correctly
rejected — that would have been a **third** hand-written list, which is the defect being fixed — but it
means the test trusts that line to stay a pure `cd` + `find` in a subshell. It is today.

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

1. **The controller broke the provenance gate on its own two commits, and did not notice.**
   `a5085f7` added this wave's plan and `3ca4327` added this ledger — **both new files, neither with a
   `provenance.tsv` row**, which the contract fails as orphans. Verified afterwards at `3ca4327`:
   `provenance check FAILED — 2 problem(s)`. Task 1's implementer found it in a clean clone, repaired
   it by the existing convention (31 plan/ledger rows precede it), and flagged that it was not its
   work.

   **The ruling is about the class, not the instance.** This ledger's own standing facts say *"Gates,
   both, every task"* — and the controller read that as binding on **implementers**. It is not; it is
   binding on **commits**, and the controller makes commits. The plan/ledger pair at the start of a
   wave is the most likely place for this to happen again, because it is the one pair of files nobody
   dispatches a task for. **Run both gates after any controller commit that adds a file.**

   Cost: an implementer spent effort on someone else's defect, and the base commit every later task
   branches from was red for a reason unrelated to any of them. **A ledger asserting "both gates green
   at `e17f310`" was true for `e17f310` and false for the commit tasks actually branch from** — which
   is the same shelf-life problem this wave exists to fix, committed by the file that documents it.

2. **Task 1, Minor — the criterion's C2 clause as reported would misclassify a shape.** The report
   says a multi-substitution RHS dies; the assignment takes the status of the **last** substitution
   performed, so `x="$(false)$(true)"` survives rc=0 (measured). **No such site exists in the tree, so
   the membership is right and the fix is right** — and the hook's own in-file comment does not make
   this error, only the report did. Recorded because the criterion, not the count, is what the next
   wave inherits.

3. **Task 1, carried obligation — `migration/baseline-inventory.json` is not regenerated in Task 1's
   range**, correctly under R6 (an implementer in a worktree cannot trust `--dry-run`, which reads
   the anchor commit's tree and returns a confident `0 change(s)`). **The branch cannot merge green
   until it is regenerated outside a worktree, and the controller owns that.** Derived drift for
   Task 1 is **2** — `.claude/hooks/warn-filename.sh` in `full_claude_tree/files` and again in
   `categories/hooks/files`, independently confirmed by the reviewer against the two observed
   failures. **Recorded here so it is not discovered at the whole-branch review**, which is where an
   unregenerated baseline would otherwise surface as a mystery. **Discharged** at `f54e2f6`.

4. **Task 1, Minor — the needle floor rejects `""` and nothing else.** Its predicate is `[ -n
   "$NEEDLE" ]`, so its covered set is the singleton `{""}`; the needle's real requirement is
   *discriminating*, a strictly smaller set. Measured: `' '`, `'e'` and `$'\n'` all pass the floor and
   all match anything — and **`grep -qF -- $'\n' <<< ""` matches an empty haystack**, because
   `grep -F` splits the pattern on newlines into two empty patterns, so a newline needle is
   behaviourally identical to the empty one the floor exists to reject. The decisive combination:
   gutting `warn-serialization`'s warning — **the exact mutation this file's header cites as its
   reason for existing** — with a whitespace needle gives **86 pass / 0 fail**.

   **Ruling: carried.** The uncaught cases require deliberately *typing* a degenerate value rather
   than omitting a line, and the floor does close omission in every reachable form, including the
   header's own "adding a hook" scenario. Measured under a written criterion — a needle is degenerate
   if it matches the one-character haystack `x` — **all twelve shipped needles are 15–70 bytes and
   none is degenerate.** → Task 5, which is writing the floor criterion anyway.

5. **Task 1, Minor — two more needles carry the weakness `block-scene-edit` was repointed for.**
   `block-meta-edit` and `guard-project-config` match **static explanation lines printed beside the
   computed reason**, not the reason itself: replacing each hook's `$MSG` / `unity_hook_block` text
   with a placeholder leaves the file at **86 pass / 0 fail**. So the provenance note's superlative —
   *"block-scene-edit's needle was the weakest of the twelve"* — is false; it was **one of three**.
   The repoint itself is correct and proven by A/B (old needle 0 failures, new needle 1, byte
   assertion passing both ways). → Task 2, which is already in this file.

6. **Task 1, Minor — one sentence, two counting criteria.** The header says the three `warn-*` hooks
   appear *"SIX times across FOUR files — tests/test-hooks.sh (three, all in comments)"*. **Six is the
   line count; `test-hooks.sh` has two lines** (one of which names two hooks). Under the *occurrence*
   criterion the total is **seven** and `test-hooks.sh`'s "three" is right. Both numbers are correct
   under their own criterion and the sentence names neither — **the same shape as ledger 205 in the
   previous wave**, which is now the second instance. → Task 7, with 205.
