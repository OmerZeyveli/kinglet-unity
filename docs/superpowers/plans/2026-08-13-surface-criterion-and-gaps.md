# The Surface Criterion, Applied — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `.claude/skills/subagent-driven-implementation/SKILL.md` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Twenty surfaces that fail the criterion leave; the two gates worth keeping stop blocking prose; and every claim the toolkit makes about what it owns, runs, or counts is either derived or guarded.

**Architecture:** Four stages, in dependency order. Stage 1 removes surfaces, so it runs first — everything after it works against the smaller tree. Stage 2 is installer correctness, where the only permanent-damage path lives. Stage 3 is the generated block and the routing that rests on it. Stage 4 is the guards and the claims. **Stage boundaries are the natural stopping points**; the suite is green at each.

**Tech Stack:** bash 3.2-compatible shell, Markdown, TSV. `tests/run-tests.sh`, `scripts/check-provenance.sh`, `tests/fixtures/mkproject.sh`, `python3 -m tools.kinglet_build`.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-08-13-surface-criterion-and-gaps-design.md` at `3845e5a`. **Where this plan and the spec disagree, the spec wins** — report it rather than resolving it silently. The previous wave produced **seven plan bugs and two spec bugs**, every one found by an implementer who checked instead of assuming, and one was a brief whose literal instruction *was* the defect. **Read your brief adversarially.**
- **Branch:** `pioneer/surface-criterion-and-gaps`, cut from `main` at `3e4c6e5`.
- **Gates, both, before any task is reported done:** `bash tests/run-tests.sh` (**timeout at least 400000 ms**) and `bash scripts/check-provenance.sh`, ending `provenance OK`. ~~timeout above **150000 ms**; currently `Total: 1022  Passed: 1022  Failed: 0`~~ — **both figures amended 2026-08-14, and the timeout one was actively harmful.** Four independent measurements at three commits put the wall clock at **191–255 s**, higher under concurrent load, so `150000 ms` truncates every real run — and **a truncated run reads as red**, which is a failure the implementer then starts diagnosing. The total is not restated here on purpose: **re-measure it**, and note that Task 10 changes the runner's tally arithmetic, so after it lands every total written anywhere is invalid at once.
- **Strip ANSI before counting suite headers.** `grep -c '^--- test-.*\.sh ---'` on raw runner output returns **0** on a completely healthy suite — the exact signal of the catastrophe the count detects. Use `sed $'s/\x1b\\[[0-9;]*m//g'` first, then compare against `ls tests/test-*.sh | wc -l`.
- **Interactive `grep` here is a shell function wrapping `ugrep 7.5.0`; `/usr/bin/grep` is GNU 3.11.** An unescaped `$` mid-pattern is a **literal** in GNU BRE and an **anchor** in ugrep, so such a probe silently returns nothing. **Use `/usr/bin/grep` for anything you report as an absence**, and say which you used. This already produced one confident false conclusion.
- **`.claude/hooks/block-projectsettings.sh` will block your commit if the message quotes the string it matches.** Write commit messages to a file and use `git commit -F <file>`. This happened to the controller on the commit that introduced the spec describing the defect.
- **bash 3.2 compatible.** No `declare -A`, no `grep -oP`, no `$'…'` inside a parameter-expansion pattern.
- **Never pipe into a reader that can exit early** under `set -euo pipefail`. `head` and `grep -q` both exit without draining stdin; SIGPIPE + `pipefail` + `set -e` kills the script. It fires on large inputs and hides on small ones. **`grep -q` on a file argument is fine — it is the pipe that kills.**
- **`set -e` does not exempt a function after the final `&&` of an AND-list**, nor a bare `X="$(fn)"` assignment. Measured twice: a non-zero return in the wrong place kills `install.sh` **after the payload is written and before the receipt is**.
- **`[ x = y ] && continue` is a `set -e` trap** as a loop body's last command.
- **New tests are self-contained** — own `set -euo pipefail`, own `pass()`/`fail()`, `REPO` from `${BASH_SOURCE[0]}`. **Do not use the runner's `assert_*` helpers**: the runner does `set +e` before sourcing, so an undefined helper prints to stderr and contributes **no `FAIL:` token** — the test would report green on the defect it exists to catch.
- **Print `PASS:` / `FAIL:`, not `ok:`.** **No needle may carry a literal `FAIL` token** — the runner tallies on it, so one failing assertion counts twice.
- **An unanchored count needle passes for the wrong reason** — `"1 file"` also matches `11 files`.
- **A test must not fabricate its own fixture.** Measured: a state's `printf >>` created a file that was supposed to exist, measured the test's own bytes, and printed `PASS:` — masking a live spec violation. Any step that assumes a file is present must **assert** it; any step that can die must fail as an assertion instead.
- **Cite by content, not by line number**, everywhere. Two `file:line` citations in this repository have already rotted.
- **A check's silence is only as wide as what it read. Say what each probe you write cannot see.**
- **A red-first step that starts green is worse than none.** Observe the *specific* failure named; if it does not fail, **stop and report**.
- **Baseline.** `migration/baseline-inventory.json` covers `.claude/**` and `templates/` only. `.claude/hooks/` **is** under it; `tests/`, `scripts/` and the repo root are outside it. Entry point is the **package**: `python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift <n>`; `python3 -m tools.kinglet_build.cli` silently no-ops with exit 0. ~~`--dry-run` first, **use the tool's number**~~ — **struck by ruling R6 on 2026-08-14.** `--dry-run` reads the **anchor commit's** tree, so on an uncommitted edit it returns a confident `0 change(s)`, rc=0; taken literally this constraint produces **0 for every drifting task**. Two scouts measured it independently on different files. **Implementers do not run `baseline-regenerate` at all** — regeneration is the controller's merge step (`commit → regenerate → commit`, `--expect-drift` derived on the merged tree). Implementers instead **list every file they changed under `.claude/` or `templates/`** in their report, as a measured statement rather than as silence.
- **Every new tracked file needs a `provenance.tsv` row** — seven tab-separated columns. **Every removed path needs a `provenance-skip.tsv` `rule=absent` row**; that is how this repository keeps a removed surface from silently returning.
- **Probe on a scratch copy:** `git archive HEAD | tar -x -C "$(mktemp -d)"`. Note `tests/test-help-ranges.sh` cannot run there — it reads `git ls-files`. Task 10 fixes that.

---

# Stage 1 — the cut

## Task 1: Twenty surfaces leave, and the counts that quote them get a guard

**Files:** delete 15 `.claude/hooks/*.sh` and 5 `scripts/*.sh`; modify `.claude/settings.json`, `provenance.tsv`, `provenance-skip.tsv`, `tests/test-derived-counts.sh`, and the five documents quoting a hook count.

**Interfaces:** produces a tree with 12 hooks and 6 repo scripts. Every later task works against it.

- [ ] **Step 1: Establish the cut list yourself, from the criterion**

The spec's **O1** names the three grounds — never runs, structurally broken, net-negative — and gives the measurements. **Re-derive the membership rather than copying a list.** For each of the 27 hooks answer: does it run under the default profile; does it work; and does it do something the model cannot do unaided.

```bash
/usr/bin/grep -rn 'HOOK_PROFILE_LEVEL=' .claude/hooks/*.sh | /usr/bin/grep strict
/usr/bin/grep -rn 'UNITY_HOOK_PROFILE' .claude/settings.json install.sh scripts/
```

The second returns nothing, which is why the first matters. **Note that `_lib.sh` itself matches the first grep** — it defines the constant. Seven hooks are strict-gated, not eight.

**If your derivation disagrees with the spec's on any surface, stop and report.** The spec's count is 15 hooks and 5 scripts; a disagreement is either a spec bug or a misreading, and both need the controller.

- [ ] **Step 2: Check each cut against what still asserts it**

This is the risk the spec names. `unity-specifics.md` states **in bold** that legacy `Input.*` is *"BLOCKED by hooks"* — so cutting `block-legacy-input.sh` would falsify a shipped claim. It is not being cut for exactly that reason; **find the others**:

```bash
for h in <each hook you plan to cut>; do
  /usr/bin/grep -rn "${h%.sh}" .claude/ docs/ README.md tests/ | /usr/bin/grep -v '^\.claude/hooks/'
done
```

Report every hit. A hook named by a shipped surface is a cut that needs a paired documentation change, not a silent deletion.

- [ ] **Step 3: Cut, re-register, record**

Delete the files. Remove their entries from `.claude/settings.json` — **verify the JSON still parses and that the count of registered hooks equals the count on disk**, which is a property nothing asserts today. Add a `rule=absent` row to `provenance-skip.tsv` for every removed path, and remove their `provenance.tsv` rows.

- [ ] **Step 4: Guard the counts before they go stale**

Five documents quote a hook count and **`tests/test-derived-counts.sh` has no hook block** (`/usr/bin/grep -c hook tests/test-derived-counts.sh` → 0). Extend its surface-pool block to hooks and to the installed script count, deriving both:

```bash
ls .claude/hooks/*.sh | /usr/bin/grep -vc '_lib'
```

**This must land in the same commit as the cut**, or the wave ships its own version of the defect it is closing — which this repository has now done three times. Then update the five quoting documents to whatever the derivation says.

- [ ] **Step 5: Gates, baseline, commit**

`.claude/hooks/` is inside the baseline inventory, so **expect real drift**. `--dry-run` first, use the tool's number, and follow commit → regenerate → commit.

---

## Task 2: The two gates block the act and permit the prose

**Files:** `.claude/hooks/bash-gate.sh`, `.claude/hooks/block-legacy-input.sh`, `tests/test-bash-gate-precision.sh`.

- [ ] **Step 1: Reproduce all nine, red**

The spec's **O1** tabulates them. Run each payload through the hook and record the exit status. **`tests/test-bash-gate-precision.sh` exists specifically for this hook and the leaks shipped anyway** — so start by reading what it does assert, and say why it did not catch these.

- [ ] **Step 2: Anchor the patterns**

`bash-gate.sh` already defines `CMD_START` and `SAME_CMD` prefixes for six of its eleven patterns. Five are substring-anywhere. Give them the prefix the file already uses. For `block-legacy-input.sh`: a left `\b` on `Input\.`, and `Editor/` and `Tests/` in the skip list.

**The trap, and it is the mirror of the defect:** an anchor that is slightly wrong turns a false positive into a false **negative**. A gate that stops blocking the act is worse than one that blocks prose.

- [ ] **Step 3: Assert both directions, for every probe**

Every row of O1's table becomes two assertions: the prose **passes**, and the act is **still blocked**. A test that only checks the prose passes would accept a gate that blocks nothing.

Include the shapes the spec measured as *permitted today and wrong*: staging everything at once, and the real editor-namespace build break. Those are `block-projectsettings.sh` and `guard-editor-runtime.sh` — **both on the cut list**, so decide and report whether their true-positive behaviour needs to survive anywhere.

- [ ] **Step 4: Gates, baseline (`.claude/hooks/` drifts), commit**

---

## Task 2b: The tokeniser gets a quote model, and a corpus stops the next hole

**Files:** `.claude/hooks/bash-gate.sh` (`find_exec_commands`, and whatever
`find_exec_is_read_only` needs to consume its output), `tests/test-bash-gate-precision.sh`,
`provenance.tsv` (note column).

**Interfaces:**
- Consumes: Task 2's five rounds, `5041b4b`…`3fd22dc`. The read-only allowlist inversion (round 3)
  and the positional flag read (round 5) are **correct and stay**. This task does not revisit either.
- Produces: a tokeniser whose output the second stage can trust, and a **regression corpus** in
  `tests/test-bash-gate-precision.sh` that later work on this hook is measured against.

### Why this is a new task and not Task 2 round six

Task 2 reached its five-round cap. The controller adjudicated rather than dispatching again, which is
what the cap is for. The cap's stated purpose is to stop a loop *"where the implementer's model of the
problem is wrong, and more resumes reinforce that model rather than escape it."* That is not what
happened here — each round solved the finding it was given — so the ruling is a new unit with a fresh
implementer, a fresh budget, and a brief written from the **pattern across the rounds** rather than
from the last symptom.

**The pattern is the finding.** Three consecutive rounds each closed one hole and opened another, all
in the same function, and each was found only by a review that came at it from a different angle:

| payload class | r3 `546870f` | r4 `06883cc` | r5 `3fd22dc` |
|---|---|---|---|
| `-exec \rm {} \;` (escaped verb) | **permitted** | blocked | blocked |
| `-exec sed -i'' … {} \;` (eleven in-place spellings) | blocked | **permitted** | blocked |
| `-exec awk '/a/ && /b/ {print > FILENAME}' {} \;` | blocked | blocked | **permitted** |
| `sed -'i'`, `sed "-"i`, `gawk -'i' inplace` (interior quote) | blocked | **permitted** | **permitted** |

Every one of these is the same root cause one level down: **the tokeniser splits on whitespace with
no model of quoting**, and each round has been repairing the consequences downstream of that instead
of the cause. A fourth local patch buys a fourth hole.

### Step 1: Reproduce, from the review's evidence, and extend it

The full evidence is `.superpowers/sdd/2026-08-13-surface-criterion/task-2-round5-rereview.md`.
Read it. Its probing method — three hook versions side by side (`546870f`, `06883cc`, `3fd22dc`),
a **fresh state dir per probe** so the two-stage gate cannot be mistaken for a classification pass —
is the method this task uses throughout.

- [ ] Run `find_exec_commands` directly on these two and read its output:

```
-exec awk '/guid/ && /:/ {print > FILENAME}' {} \;   ->  awk<TAB> /guid/
-exec sed -E 's/(a | b)/x/' -i {} \;                 ->  sed<TAB> -E s/(a
```

In the first, `>` never reaches the awk arm. In the second, `-i` never reaches the sed arm. The
review verified the damage against real files: the awk payload **truncated 3 of 3 `.meta` files,
104 B → 39 B**, removing `fileFormatVersion` and the importer block; the `system("rm ")` twin
**deleted all three**. Reproduce both before you change anything. If either does not reproduce,
**stop and report** — the tree has moved and this brief's premise is void.

- [ ] Extend the reproduction to the classes the review ledgered, because they share the cause and
      this task is the one that can close them:
  - interior-quote in-place spellings: `sed -'i'`, `sed "-"i`, `sed --in-'place'`,
    `gawk -'i' inplace`, `sort -'o' {}`;
  - `-exec grep -l 'xargs gzip' {} \;`, where a dequoted `xargs` **inside grep's pattern** is read as
    an introducer and the next pattern word becomes "the command" (r4=0, r5=2 — a false positive
    from the same blindness, in the other direction).

### Step 2: Red first, as a corpus — this is the deliverable that outlives the fix

**Do not start with the fix.** Build the corpus first, and make it the shape of the test file's new
section.

A corpus is a list of payloads, each with an expected verdict and a one-line reason. It must contain,
at minimum: every payload in the table above, every payload the review lists, every payload
`tests/test-bash-gate-precision.sh` already asserts, and the read-only payloads that must keep
passing. Run it against the current hook and record the failures you expect to fix.

**Then add the differential arm, which is the point.** Round 5's implementer wrote the sentence this
whole task exists because of:

> *A test built from the same idea as the code confirms the idea, not the behaviour.*

Every round's own probes passed. What caught each hole was a reader who had a **different idea**. A
corpus cannot have a different idea on its own — but it can be checked against *history*, which is a
different idea by construction. So:

- [ ] Extract the hook at `546870f`, `06883cc` and `3fd22dc` into your scratch root
      (`git show <rev>:.claude/hooks/bash-gate.sh > "$SCRATCH/gate-<rev>.sh"`).
- [ ] Run the whole corpus through all four versions (three historical, plus your working copy).
- [ ] **Assert the monotonic property: your version must block everything that ANY earlier version
      blocked**, except payloads you have explicitly recorded as verified false positives with a
      reason. A payload that any earlier version blocked and yours permits is a regression, by
      definition, and this is the mechanism that makes the r3→r4→r5 pattern impossible to repeat.

The permanent test cannot shell out to `git show` (it must run in a `git archive` scratch copy — see
the standing facts). So **freeze the historical verdicts as data**: a table of payload → the set of
versions that blocked it, generated once by you, committed, with the generating command recorded in a
comment so the next person can regenerate it. State plainly in the test what this cannot see: it
freezes the *past*, so it catches re-opening an old hole and says nothing about a new one.

Observe the specific failures before proceeding. **A red-first step that starts green is worse than
none.**

### Step 3: Give `find_exec_commands` a quote model

The fix is in the tokeniser, not in a fifth arm of the table.

`find_exec_commands` currently word-splits and then dequotes each token. It must instead **respect
quoting while splitting**: a single- or double-quoted run is one token and its contents are inert —
no operator inside it terminates a clause, no `xargs` inside it introduces a command, no `;` inside it
is find's terminator. That single property closes the new Critical, both ledgered classes, and the
Minor at once. Verify that it does rather than assuming it.

Constraints, all of which have already cost this repository a round:

- **bash 3.2.** No `declare -A`, no `mapfile`, no `${x^^}`, no `grep -oP`. A character-at-a-time
  scan in pure bash is acceptable if it meets Step 4's budget; measure before you commit to it.
- **The condition stays negative.** An arm asks whether a write flag is present among a command's own
  arguments. There is no vouching direction, and a spelling the table has not thought of must cost a
  **block on a read**, never a **pass on a write**. Do not introduce a shape that can vouch.
- **Do not touch the read-only allowlist inversion or the positional flag read.** Both are correct and
  both were expensive. If your change requires altering either, **stop and report** rather than
  doing it.
- You may not be able to make quoting fully correct in bash for every shell construct. **Say what your
  model does not handle** — command substitution, ANSI-C quoting, backslash-continued lines, nested
  quotes — and assert the *conservative* direction for each: unparseable means blocked, not permitted.

### Step 4: The cost, with a bound you state and assert

This hook runs on **every** Bash tool call, so its worst case is a user-visible hang.

The review measured that round 5's dequote guard fires five parameter expansions where round 4 ran
one, and that on a **quote-leading** long token round 5 is the slowest version ever shipped:

| input | r3 | r4 | r5 |
|---|---|---|---|
| 122 KB quoted | 219 ms | 774 ms | **2325 ms** |
| 1 MB quoted | 1.2 s | 51.9 s | **172.5 s** |

Attribution was nailed at fixed size: 131 072 chars quoted **2088 ms** vs unquoted **134 ms**. The
cause is bash parameter expansion over a long string in a UTF-8 locale — one `${x#pat}` on a
122 880-char token cost 432 ms in an earlier measurement, while a `case` over the same string costs
3–4 ms.

- [ ] Re-measure all three versions yourself; do not carry these numbers forward.
- [ ] **Decide and state a bound** — a wall-clock ceiling at a stated input size, on this host. Assert
      it in the test file. A guard with no cost assertion is how this regression shipped twice.
- [ ] If a correct quote model cannot meet your bound in bash 3.2, **that is a finding, not a
      failure** — report it with the measurement and say what the alternatives are (a length cutoff
      above which the hook blocks rather than parses, `case`-based scanning instead of `${x#…}`,
      or declining the input). **A hook that blocks a 1 MB command line is defensible; one that hangs
      for three minutes is not.**

### Step 5: Prove the new guards are not hollow

- [ ] Mutate the quote model to ignore quotes and confirm the corpus reds — and report **which**
      assertions red. A mutation that reddens everything has isolated nothing.
- [ ] Empty the corpus's payload list and confirm the test **fails** rather than reporting green over
      zero payloads. This repository's worst guard shape is one that is green because it scanned
      nothing, and this wave has an entire task about it.
- [ ] Confirm the two-stage gate still behaves: first call rc=2, byte-identical retry rc=0, a
      different command in the same state dir still rc=2. Use a fresh state dir per probe.

### Step 6: Gates, report, commit

Both gates, re-measured after your last commit, with the ANSI-stripped header count and the
`ls tests/test-*.sh | wc -l` it was compared against. `.claude/hooks/` is **inside**
`migration/baseline-inventory.json` — list the files you changed under `.claude/` in your report and
**do not run `baseline-regenerate`** (ruling R6). Commit messages through a file.

In your report, answer the question this task was created by: **what class of hole is still open after
your change, and what would find it?** Five rounds of this task have each ended confident. The two
that were wrong were wrong in a direction their own probes could not look.

---

## Task 2c: What decides the route, and what the allowlist vouches for

**Files:** `.claude/hooks/bash-gate.sh` (the route precondition and the allowlist's identity test),
`tests/test-bash-gate-precision.sh` (the corpus), `provenance.tsv` (note column).

**Interfaces:**
- Consumes: **Task 2b's tokeniser and its 242-payload corpus.** Both are correct and both stay. The
  corpus's frozen `hist` column now spans four versions; **extend it, do not restart it.**
- Produces: two holes closed that every version of this hook has had, and corpus anchors for both —
  Task 2b's review recorded that **neither has any corpus payload today**, so a future tightening has
  nothing to regress against.

**Why this is a task and not more of 2b.** Task 2b was scoped to `find_exec_commands` — how a
command's own tokens are read. Both findings below sit **one level up**, in the code that decides
*whether that function runs at all* and *which command it is looking at*. They are identical at
`546870f`, `06883cc`, `3fd22dc` and `f735fe2`, so nothing regressed; 2b's reviewer ruled them
correctly-scoped successor items rather than Criticals, and this section is that ruling.

### Step 1: Reproduce both, and derive the third

All measured by Task 2b's reviewer against real `.meta` files. **Re-run each before changing
anything** — if one does not reproduce, the tree has moved and this brief's premise is void.

**The route precondition.** The regex deciding whether the `.meta` route applies runs *before* the
tokeniser, so a name split across quotes never reaches the parser that would resolve it:

| payload | verdict at all four versions |
|---|---|
| `ls Assets/*.meta \| xargs sed -i s/a/b/` | **0** |
| `find Assets -name "*.m"*"eta" -exec sed -i s/a/b/ {} \;` | **0** |
| `find Assets -name '*.met'a -exec sed -i s/a/b/ {} \;` | **0** |

The second and third are the sharp ones, and they are **the same defect one level up**: Task 2b's
tokeniser resolves those names correctly, and the gate never asks it. The first is different — no
`find` at all — and may need a different answer; say so rather than folding them together.

**Basename vouching.** The read-only allowlist matches on the command's basename, so any executable
whose *name* is on the list is vouched for regardless of where it comes from. Executed, not reasoned:
a real program at `./evil/grep` that rewrites its arguments, invoked as
`find Assets -name '*.meta' -exec ./evil/grep -l guid {} \;`, **destroyed all three `.meta` files,
127 B → 6 B, with the gate returning 0 at all four versions.** `/tmp/evil/grep` behaves the same.

- [ ] Reproduce all four. Report the third route spelling's derivation — it was found by a reviewer
      generalising from two, and **the class is "a glob whose literal text is split by quoting", not
      "these three spellings".** Derive the class, then write payloads for it.

### Step 2: Decide what the route precondition should be, and say why

This is the load-bearing judgement and the brief does not make it for you. Three shapes, and none is
obviously right:

1. **Tokenise first, then decide the route.** Correct, and it inverts the hook's cost model: every
   Bash call pays for a full parse before the cheap regex can reject it. Task 2b measured the awk
   scan at 114 ms on a 248 KB payload — cheap in isolation, not free on every call.
2. **Widen the precondition regex** to match a quote-split literal. Cheap, and it is a fourth
   iteration of exactly the pattern that put Task 2 at its cap — a regex chasing spellings.
3. **Make the precondition conservative rather than exact**: if the command names `find`, `xargs` or
   a glob over `Assets/`, tokenise; otherwise the fast reject stands. Wider than (2), cheaper than
   (1), and it costs first-attempt blocks on reads that mention `Assets/`.

**Measure before choosing.** Cost the fast-reject path on an ordinary command under each shape (Task
2b's figure for an ordinary command is 42 ms; r3's was 38 ms) and report the numbers. **If your
measurement says the obvious choice is wrong, take the other one and say so.**

### Step 3: Decide what the allowlist's identity test should be

`grep` on the allowlist means *"the `grep` I expect"*, and the code cannot tell that from
`./evil/grep`. Options, again yours to choose:

- **Reject any command containing `/`** — a path-qualified command is never allowlisted, so it blocks.
  Conservative and blunt: `/usr/bin/grep` blocks too, which is a legitimate spelling a careful user
  writes deliberately.
- **Allow only a fixed set of absolute prefixes** (`/usr/bin`, `/bin`) plus bare names.
- **Resolve and compare** against `command -v` — accurate and it makes the gate depend on `PATH`,
  which is attacker-controlled in exactly the scenario that matters.

Whatever you choose, **keep the direction negative**: an identity the table cannot establish must
cost a **block on a read**, never a **pass on a write**. And note the interaction with Task 2b's
`*/xargs` handling — that arm exists precisely because path-qualified introducers are real, so a rule
that rejects every `/` must not break it. Task 2b's own reviewer found the corpus had **no
path-qualified `xargs` payload at all**; check whether that gap is closed before you rely on it.

### Step 4: Corpus anchors, and extend the frozen column

Both findings must gain corpus payloads, with the `hist` column extended to record the verdict at
Task 2b's commit as a fifth historical version. **The corpus's monotonic property is what makes the
r3→r4→r5 pattern impossible to repeat; adding versions to it is how it keeps working.**

- [ ] Add payloads for **every** route spelling in your derived class, plus the basename class in
      both directions (`./evil/grep` blocks; `/usr/bin/grep` behaves as you decided in Step 3).
- [ ] **Then run the sweep Task 2b's review asked for and generalise it:** for every branch in the
      hook that exists on purpose, is there a corpus payload that would notice its removal? Report
      the branches with no payload. That sweep, not the payloads, is this step's deliverable — the
      measured lesson from Task 2b is that **a corpus catches the mutants its author imagined.**

### Step 5: Mutation-prove, both directions

- [ ] Mutate each fix so it fails open and confirm the new payloads red. Report **which** assertions
      red — a mutation that reds everything has isolated nothing.
- [ ] `cmp` the mutated file against the original and emit an explicit **`MUTANT DID NOT APPLY`**
      when it did not. Three measured instances in this repository of an unapplied mutant reporting a
      clean zero, and the failure is **symmetric**: it makes a broken guard look sound *and* a sound
      guard look broken.
- [ ] Confirm the exemption marker scheme Task 2b introduced still holds, and that nothing you add
      uses an exemption where a fix belongs.

### Step 6: Gates, report, commit

Both gates. `bash tests/run-tests.sh` with a timeout of **at least 400000 ms** — a killed run is not
a red suite. `.claude/hooks/` is inside `migration/baseline-inventory.json`, so **your suite will be
RED with failures naming exactly the files you changed under `.claude/`, and that is correct** —
enumerate them and show the failure set is only that. **Do not run `baseline-regenerate`** (R6); list
your `.claude/` files for the controller. Commit messages through a file.

**Report the one thing this task cannot settle:** whether a determined caller can still reach a write
through some third route. Every version of this hook has been confidently wrong about that once.

---

## Task 3: The surviving scripts become reachable

**Amended after Task 1 (2026-08-13).** This section was written before the cut and every figure in it
was pre-cut. The heading said *"The five surviving scripts"*; there are six installed. Its **Files**
line named only the two commands below; Task 1's controller ruling restored
`scripts/detect-missing-refs.sh`, which is referenced by nothing and whose wiring is **this task's**.
The figures below are left as written, marked, because what they were is the point — a plan that
quotes a count is the defect this wave exists to close, and replacing a stale count with a fresher one
repeats it rather than fixing it.

**Files:** `.claude/commands/unity-doctor.md`, `.claude/commands/unity-init.md`, and whichever agent or command should name the rest — **including a home for `detect-missing-refs.sh`**.

- [ ] **Step 1: Derive what is reachable today — do not read the figures below**

```bash
/usr/bin/grep -rn 'scripts/' .claude/
```

~~Three references from shipped surfaces, naming two scripts. **Eight of ten installed scripts are named by nothing that ships.**~~ *(pre-cut, superseded — derive it.)* `studio-doctor.sh` is pointed at humans from four places and reachable from no agent, command or skill — while `/unity-doctor.md` **re-implements its checks by hand**. That much is unchanged by the cut; verify it anyway.

Count the installed set (`.claude/scripts/`, not the repo's `scripts/`), count how many are named by a shipped surface, and state both. Task 1's re-review measured one shipped surface naming one installed script — treat that as a figure to reproduce, not to cite.

- [ ] **Step 2: Wire them, and delete the duplication**

`/unity-doctor` runs `studio-doctor.sh` rather than re-deriving it. Decide where `validate-serialization.sh` and `validate-asmdefs.sh` belong — both do something a model does not do unaided (git-history field-rename diffing; transitive-closure cycle detection) and neither is currently invocable.

**A path that does not resolve in an installed project is the defect the previous wave spent a whole pass on.** These live at `.claude/scripts/<name>` once installed, not at `scripts/<name>`. Verify against a real install, not against the repo.

- [ ] **Step 3: Gates, commit.** `.claude/commands/` is inside the baseline inventory.

---

# Stage 2 — installer correctness

## Task 4: The receipt exists before anything that can abort

**Files:** `install.sh`, `tests/test-install-ownership.sh`.

- [ ] **Step 1: Reproduce the permanent-damage path**

```bash
ln -s /nonexistent "$PROJECT/Packages/manifest.json.bak"
bash install.sh --project-dir "$PROJECT" --with-mcp --yes
```

Expected today: `cp: not writing through dangling symlink`, **rc=1, 86 files under `.claude/`, no receipt**, and `uninstall.sh` printing *"Refusing to guess which files are ours."* `[ -e ]` is false through a dangling link, so D11's guard does not fire.

- [ ] **Step 2: Add the states, red**

| state | expectation |
|---|---|
| dangling symlink at the `.bak` path, `--with-mcp` | the run leaves a receipt; `uninstall.sh` cleans the project |
| `--variant bare`, no `.gitignore` beforehand | `.gitignore` is created **and has a receipt row**; uninstall removes it |
| a receipt row whose origin column is unreadable, for `MCP-SETUP.md`, across an upgrade | the row is **not** dropped |

- [ ] **Step 3: Move the receipt, do not patch the symptom**

The fix is where the receipt is committed, not a `[ -L ]` test bolted onto one `cp`. Write the receipt for what has been installed **before** the step that can abort, or trap and finish it on failure. **Then the two lesser members close for free** — verify that they do rather than assuming it:

- `.gitignore` created-and-unrecorded;
- `MANIFEST_BAK_KEPT` outliving the file it names (the failure arm's `mv` deletes the backup while the flag stays `1`, and `sha_of` inside a `printf` argument — where `set -e` does not reach — writes a row with an **empty checksum**).

Also in scope: `owned_by_installer`'s `$4 == "toolkit"` gate drops a root file's ownership row forever on an unreadable origin column, and `.mcp.json`'s reference copy is a heredoc written to `mktemp`, so **that arm short-circuits every run and the receipt is never consulted for that file**. A constant reference copy can mask a receipt problem indefinitely.

- [ ] **Step 4: Prove it did not become "always write a receipt"**

A `foreign` install — one where the receipt's absence is what defines the mode — must still behave as it does today. Mutation-prove it.

- [ ] **Step 5: Gates, commit.** `install.sh` is outside the baseline inventory; confirm zero drift.

---

## Task 4b: A CLAUDE.md missing its end marker is amputated, silently, on every install

**Files:** `install.sh` (the `kinglet:generated` awk merge), `tests/test-install-ownership.sh`.

**Interfaces:**
- Consumes: nothing from Tasks 1–4. The awk merge is untouched by every task before this one.
- Produces: the merge's behaviour on a malformed marker pair. **Task 7 owns the markers as a
  contract** and will state what a well-formed region looks like; it must not also state what
  happens when the region is malformed — that sentence is this task's, and two tasks writing the
  same sentence is how the pair drifts.

- [ ] **Step 1: Reproduce the amputation, red**

Install into a fixture, then delete **only** the closing marker and reinstall:

```bash
P="$(mktemp -d)/proj"; bash tests/fixtures/mkproject.sh "$P" --variant urp
bash install.sh --project-dir "$P" --yes
wc -lc "$P/CLAUDE.md"
/usr/bin/grep -v 'kinglet:generated:end' "$P/CLAUDE.md" > "$P/CLAUDE.md.tmp" && mv "$P/CLAUDE.md.tmp" "$P/CLAUDE.md"
bash install.sh --project-dir "$P" --yes
wc -lc "$P/CLAUDE.md"
```

Expected today — **derive the two figures yourself, do not quote these**: the file shrinks, the
installer prints `ok Refreshed the generated section of CLAUDE.md (your prose untouched)`, and the
user's own sections below the region are gone. The scout wave measured 122 lines / 4839 bytes →
80 lines / 2746 bytes on the tree at `06883cc`, destroying `## Engineering Stance`, `## Where things
go`, `## How to work`, `## Conventions reminder` and `## Custom Notes`. **That measurement is pinned
to a commit this branch has passed. Re-measure; report both numbers.**

The mechanism is two awk rules:

```awk
/kinglet:generated:begin/ { print; while ((getline l < factsfile) > 0) print l; skip=1; next }
/kinglet:generated:end/   { print ""; print; skip=0; next }
```

`skip` is set at `begin` and cleared **only** at `end`. With no `end` line, it is never cleared, so
every remaining line of the user's file is dropped. The result is begin-only, which means **the next
install amputates again and reports success again** — the scout wave measured it stable at the
shrunken size over three consecutive runs. Reproduce that third run too: a one-shot loss and a
permanent one are different findings, and the permanent one is why this is not a Minor.

- [ ] **Step 2: Write the failing test first**

In `tests/test-install-ownership.sh`, self-contained idiom (own `set -euo pipefail`, own
`pass()`/`fail()`, `REPO` from `${BASH_SOURCE[0]}`, no runner `assert_*`). Three states:

| state | expectation |
|---|---|
| `begin` present, `end` deleted | the user's prose below the region survives byte-for-byte |
| `end` present, `begin` deleted | no silent partial write; the run says what it did |
| both markers present but `end` **before** `begin` | the run does not amputate |

Run it and observe the **specific** failure — the surviving-prose assertion failing on a byte
comparison. A red-first step that starts green is worse than none: if any of the three passes
already, stop and report rather than proceeding.

- [ ] **Step 3: Make the malformed case refuse rather than guess**

The fix is not "clear `skip` at EOF" — that silently reinterprets a file whose structure the
installer cannot actually parse, and it would still drop the region's old content on the
`end`-before-`begin` case. **A marker pair that is not well-formed is a state the installer must
decline to merge.** Treat it the way the installer already treats a file it does not own: leave
`CLAUDE.md` untouched, say so, and record it through whatever mechanism Task 5 settled for
work-not-done (`MANIFEST_DECLINED`'s sibling — read Task 5's shipped exit contract before you
choose; it landed in `MCP-SETUP.md` by ruling R3).

Do not print `your prose untouched` on a path that touched the prose. That string is the
false-reassurance half of this defect, and it is the half a user reads.

- [ ] **Step 4: Close the shipped claim, or hand it over with evidence**

`README.md` claims the user's prose is left **byte-for-byte**. Today that claim is false in exactly
this state. Verify at HEAD that the sentence is still there and still says that (`/usr/bin/grep -n
'byte-for-byte' README.md`). **Task 11 owns every claim in `README.md` by ruling R4/R12 — do not
edit it here.** Instead, put the measured before/after in your report under a heading Task 11's
implementer can find, and say which of the two closes it: the fix making the claim true, or the
claim needing narrowing. If your fix makes it true, say so; that is a claim moving from unguarded
prose to guarded behaviour, which is the wave's whole thesis.

- [ ] **Step 5: Gates, commit**

Both gates. `install.sh` is outside `migration/baseline-inventory.json`; `tests/` is outside it too,
so this task drifts nothing — confirm that rather than assuming it, and note in your report that
**you did not run `baseline-regenerate`** (ruling R6: `--dry-run` reads the *anchor commit's* tree,
so from inside a worktree it returns a confident `0 change(s)` whether or not you drifted anything;
baseline regeneration is the controller's merge step, not yours).

Commit message through a file: `git commit -F <path>`.

---

## Task 4c: An upgrade across the cut leaves registrations pointing at deleted hooks

**Files:** `install.sh` (the kept-`settings.json` block and `count_hooks()`), `tests/test-install-prune.sh`.

**Interfaces:**
- Consumes: **Task 1's cut.** Task 1 removed 15 hooks and 4 scripts; this task is the install path's
  reaction to a payload that shrank. Its membership figure comes from the tree, never from a
  document — `ls .claude/hooks/*.sh | /usr/bin/grep -v '_lib\.sh' | wc -l`.
- Produces: a guard on upgrade-across-a-shrink in `tests/test-install-prune.sh`. Task 10 owns
  hollow guards in **existing** tests; this is **new install-path coverage** and stays here.

**Why this is its own task and not a Task 1 reopen:** `git log 3e4c6e5..38dec6c -- install.sh` is
empty. Task 1 never opened this file. Reopening it to fix a file it never touched would misattribute
the work and corrupt the commit range the whole-branch review diffs. `install.sh` already has four
owners in this wave (4, 5, 6, 4b) and the batch plan serialises them; a reopened Task 1 would be a
fifth concurrent writer.

- [ ] **Step 1: Reproduce the upgrade, red**

The trigger is an *edited* `settings.json`, and `install.sh`'s own comment calls it *"the most-edited
file in the payload… so on any real project it is 'yours'"*. **One appended newline is enough.**

```bash
P="$(mktemp -d)/proj"; bash tests/fixtures/mkproject.sh "$P" --variant urp
git -C . stash list >/dev/null           # (you are in a worktree; do not touch the main tree)
# install the PRE-CUT payload, edit settings.json, then install the CURRENT payload over it:
git worktree add "$(mktemp -d)/pre" 3e4c6e5
bash "$(dirname .)/pre/install.sh" --project-dir "$P" --yes   # adjust to the worktree path
printf '\n' >> "$P/.claude/settings.json"
bash install.sh --project-dir "$P" --yes
```

Measure three numbers and report all three with the command that produced each:

1. how many `\.claude/hooks/[a-z_-]+\.sh` paths the kept `settings.json` registers;
2. how many of those files exist under `$P/.claude/hooks/`;
3. what the installer **printed** on the `Hooks` summary line.

The audit measured **15 registrations pointing at deleted files** and a printed `Hooks 27` over a
tree holding 12. **Those are pinned to an earlier commit — re-derive.**

- [ ] **Step 2: Name the direction that is missing**

The kept-settings block asks one question:

```bash
grep -oE '\.claude/hooks/[a-z_-]+\.sh' "$SCRIPT_DIR/.claude/settings.json" | sort -u   # what we ship
  → for each: is it registered in the user's settings.json?
```

That is *"we ship it — is it registered?"*. The direction the cut created — *"it is registered — does
it exist?"* — is asked by nothing. Write the reverse-direction check as a **warning that names each
dead registration**, in the same block, using the same `is_modified` precondition. Warn; do not edit
the user's `settings.json`. It is theirs, that is why it was kept, and an installer that silently
rewrites the file it just told you it preserved is a worse defect than the one being fixed.

- [ ] **Step 3: `count_hooks()` stops counting things that are not there**

```bash
count_hooks() { grep -oE '\.claude/hooks/[a-z_-]+\.sh' "$CLAUDE_DIR/settings.json" 2>/dev/null | sort -u | wc -l | tr -d ' '; }
```

It counts registrations in the **user's** file, which is why it prints a pre-cut number after an
upgrade. Two shapes are acceptable and you choose: count only registrations whose file exists, or
report both (`Hooks 12 (27 registered, 15 dead)`). The second is more honest and more code; say why
you chose what you chose. **The comment above it explains why hooks are counted from `settings.json`
rather than from `*.sh` on disk — `hooks/` also holds `_lib.sh`, which is sourced, not registered.
Whatever you write must keep that true.**

Note `grep -oE … | sort -u | wc -l` is a pipe into readers that drain — safe. If you restructure it,
do not introduce a `head` or a `grep -q` on the right-hand side of a pipe.

- [ ] **Step 4: The upgrade fixture, which is the part that must not be deferred**

`tests/test-install-prune.sh` gains an **upgrade-across-a-shrink** fixture: install a payload, remove
a hook from the payload *and* leave it registered in a kept `settings.json`, reinstall, assert the
warning names it and the count is honest. A fix without a guard reproduces this wave's own named
failure mode, and the audit's fourth durable shape is exactly this: *every artifact under review is a
repository; the artifact that breaks is a user's project — any change to the payload's **shape** needs
an **upgrade** fixture, not only a fresh-install one.*

`scripts/studio-doctor.sh` already contains a check of this shape and nothing calls it and no test
asserts it. Read it before writing yours — reusing its logic is better than a second dialect, and if
you can make the doctor's check and the installer's check the same code, say so in your report even
if you do not do it here.

- [ ] **Step 5: Prove the guard is not hollow**

Mutate: make the reverse-direction check pass unconditionally and confirm your new test reds. Then
empty the sweep the check iterates over and confirm the test still reds — a guard that is green
because it scanned nothing is the exact shape Task 10 exists to remove, and it must not be introduced
by the task that quotes Task 10's finding.

- [ ] **Step 6: Gates, commit**

Both gates. `install.sh` and `tests/` are both outside the baseline inventory — confirm, and do not
run `baseline-regenerate` (ruling R6). Commit message through a file.

---

## Task 5: A run that abandons work says so, and something asserts it

**Files:** `install.sh`, `tests/test-install-dryrun.sh` or a new guard, plus one shipped document for the exit contract.

- [ ] **Step 1: Reproduce the two that do not reach `Not done:`**

`--variant bare` + `--with-mcp` → `warn No Packages/manifest.json — skipping --with-mcp.` … `Installation complete.`, **rc=0, no `Not done:`**. A manifest with no `"dependencies"` key → `warn Could not edit manifest.json safely` … same. `gitignore_plan`'s `*)` fallback is a third.

- [ ] **Step 2: One recording point for all four**

The `MANIFEST_DECLINED` mechanism already exists. Route the others through it — and note the fallback does not name its consequence (`.claude/settings.local.json` and `.claude/state/*` are then not gitignored).

- [ ] **Step 3: Decide and write down the exit contract**

`/usr/bin/grep -n 'exit status\|exit code' README.md docs/GETTING-STARTED.md MCP-SETUP.md` is **empty**. All four outcomes exit 0, so a scripted `install.sh --with-mcp && start_unity` proceeds as though the package landed.

**The controller is not deciding this for you.** The previous wave measured that a non-zero return from `add_manifest_dependency` kills the installer before the receipt; that is an argument about *where* the status is raised, not about whether the contract should exist. Decide, implement, document it in a shipped file, and **say what a caller can now rely on.**

- [ ] **Step 4: Assert the block**

`/usr/bin/grep -rn 'Not done' tests/` is **empty**. The dry-run guard cannot reach it — all three of its oracles are silent on a run that writes nothing, which is the same blindness D4 was written to correct. Decide where the assertion lives and say why.

- [ ] **Step 5: Gates, commit**

---

## Task 6: A reverted file stops being sticky, and the doctor stops repeating the claim

**Files:** `install.sh`, `scripts/studio-doctor.sh`, `tests/test-install-ownership.sh`.

- [ ] **Step 1: Reproduce the trap and the control**

Install → edit → install → **revert to the toolkit's exact bytes** → install. Expected today: `keeping yours` about a file with no local edits, row still `user-modified` carrying the toolkit's own sha. Then simulate a toolkit v2 by changing the shipped file: the project does **not** receive it; a control project that never touched the file does.

And `studio-doctor.sh` reports `1 file(s) modified since install` about a file byte-identical to the toolkit's — **it classifies by the column alone, never comparing bytes.**

- [ ] **Step 2: Compare against the toolkit's copy, not the recorded sha**

Drop the sticky flag only on an exact match with `$SCRIPT_DIR`'s shipped copy. **This is a different comparison from the one that failed in `c2d27f1f`** — that was against the *recorded* sha, and an edited file never equals the toolkit's bytes.

Root-level rows (`.mcp.json`, `MCP-SETUP.md`, `CLAUDE.md.generated`) have no static reference copy and stay sticky. **Say so in the report** rather than leaving it to be discovered.

- [ ] **Step 3: The regression check that decides it**

Edit, then **three consecutive installs**. The edit must survive all three. If it does not, stop — you have reintroduced `c2d27f1f`.

- [ ] **Step 4: Fix the doctor in the same commit**

`studio-doctor.sh`'s own comments reason at length about its readers agreeing. Shipping an installer that unsticks while the doctor still classifies by column alone recreates exactly the drift those comments were written to prevent.

- [ ] **Step 5: Gates, baseline (`scripts/` is outside it — confirm zero), commit**

---

# Stage 3 — the generated block, and what rests on it

## Task 7: `/unity-init` names the generator, and the markers become a contract

**Files:** `.claude/commands/unity-init.md`, and at least one shipped surface for the marker contract.

- [ ] **Step 1: Establish the gap**

```bash
/usr/bin/grep -n 'generate-claude-md' .claude/commands/unity-init.md
/usr/bin/grep -rn 'generated:begin' .claude/ docs/ README.md
```

The first is empty. The second finds the markers **only in historical plans** — no shipped surface knows they exist. Then count what depends on the region: `/usr/bin/grep -rln 'generated block' .claude/`.

- [ ] **Step 2: Call the generator, state the contract**

`/unity-init` invokes `.claude/scripts/generate-claude-md.sh` rather than re-deriving the block by hand. **Check the invocation resolves in an installed project** — the script lives at `.claude/scripts/` there, and this repository has shipped a path that resolved only in the repo before.

State the contract where a model will read it: the region between the markers is regenerated in place, everything outside is the user's, and a re-install rewrites it.

- [ ] **Step 3: Prove the two producers agree**

Run `/unity-init`'s path and `install.sh`'s path against the same fixture and compare the block byte-for-byte. **Two producers of one region is the defect the previous wave spent a task removing** from `.gitignore`; if they disagree, that is the finding, not a nuisance.

- [ ] **Step 4: Gates, baseline (`.claude/commands/` drifts), commit**

---

## Task 8: `/unity-ui` and `/unity-scene` stop reading as entry points

**Files:** `.claude/skills/using-kinglet/SKILL.md`, `.claude/commands/unity-ui.md`, `.claude/commands/unity-scene.md`, `docs/GETTING-STARTED.md`.

- [ ] **Step 1: Establish the bypass**

`/unity-ui` dispatches `unity-ui-builder`, which holds `mcp__UnityMCP__*`. Check whether either builder agent gates on an approved design:

```bash
/usr/bin/grep -n 'brainstorm\|design.md\|HARD-GATE\|approved' .claude/agents/unity-ui-builder.md .claude/agents/unity-scene-builder.md
```

Expected: no match. So taking row 11 writes C# and makes MCP write calls with no approved design.

- [ ] **Step 2: Reword the row, and make it true where it bites**

Row 11 becomes the *execution step* it actually is — a UI screen or scene **whose design is already approved**. **This adds no exemption**, which matters: `unity-brainstorming` explicitly refuses to keep a list of them.

Then the command-side half: `/unity-ui.md` opens with the precondition, stated as a **precondition** and not a "Suggest next". `/unity-scene.md` already half-has it, as an after-the-fact offer once the scene is built.

- [ ] **Step 3: Fix the document that already ruled, and the table that contradicts it**

`docs/GETTING-STARTED.md` rules that row 2 wins — and two lines above, a Common First Commands table lists `/unity-scene`. Make them agree.

- [ ] **Step 4: Record the second exemption**

Row 4 routes a handed-over plan straight to `unity-planning`, skipping row 2 — a second de-facto exemption, undeclared. **Report it; do not add it to a list.** The skill's refusal-to-list is the reason it is worth naming out loud.

- [ ] **Step 5: Gates, baseline, commit**

---

## Task 9: The Ambiguity Score says what it does not know

**Files:** `.claude/skills/unity-brainstorming/SKILL.md`.

- [ ] **Step 1: Reproduce the leak on the skill's own example**

Score *"Add multiplayer to my game"* by the file's rubric, twice: with and without a generated block that reports a Unity version, URP and a networking package. The file scores it **3/10**. With the block, Platform goes 0 → 2 and Integration 1 → 2: **6/10, exactly the threshold.**

- [ ] **Step 2: Add a new section — and it must be new**

`tests/test-surface-references.sh` freezes ~~six~~ **a set of named sections of this skill character-for-character** — **derive the membership, do not take a number from this plan** — and `ub_section` stops at the next `#{1,3}` heading, so **a new heading is invisible to every frozen comparison; editing an existing one is not.** Confirm both yourself before writing.

*(Amended 2026-08-14. This section was written saying **six**. Task 9's implementer reported the disagreement rather than resolving it silently, and its reviewer counted independently: the file freezes **seven** — the six ECU-survival sections plus the vague-as-clear table. The stale number is struck through and left visible rather than replaced, because a plan that quotes a count is the defect this wave exists to close, and replacing a stale count with a fresher one repeats it. **The plan is corrected, not the tree.**)*

The content is one argument: a fact supplied by the generated block is context for *answering* a dimension, never points, because **a constant cannot discriminate between requests**. Restate that the score gates depth, not whether the round happens.

- [ ] **Step 3: Prove you did not disturb the frozen prose**

Run `tests/test-surface-references.sh` and confirm the six comparisons still pass. If one fails, you edited a frozen section — and `provenance.tsv` records this file `origin=ecu` on the specific ground that ECU's score survived, so that is a provenance question, not a formatting one.

- [ ] **Step 4: Gates, baseline, commit**

---

# Stage 4 — guards and claims

## Task 10: Six guards see the class

**Files:** `tests/test-help-ranges.sh`, `tests/test-studio-doctor.sh`, `tests/test-skill-discovery.sh`, `tests/test-surface-references.sh`, `tests/run-tests.sh`.

- [ ] **Step 1: The two that cannot run under the documented probe method**

`tests/test-help-ranges.sh` derives its file set from `git ls-files`, so a `git archive HEAD | tar -x` extraction makes it die `rc=128` asserting nothing. `tests/test-pipeline-detector.sh` faced the same dependency and grew explicit no-index arms — **copy that shape**, and check whether it too still dies.

- [ ] **Step 2: The symmetric fixture, and the unasserted sentences**

`tests/test-studio-doctor.sh`'s long-list fixture makes both counters `1500`, so the block cannot tell its two lists apart — swapping the doctor's counters leaves both assertions green. Make it `N` and `N+k`, and **prove the swap now reddens.**

The doctor's two unreadable-origin continuation `warn` lines are asserted by nothing. Two fix rounds worked to make those sentences true; deleting them is currently invisible.

- [ ] **Step 3: The frontmatter fence and the red-flag bodies**

`tests/test-skill-discovery.sh` reads only a `name:` line and a `description:` line, so **the closing `---` fence is unguarded across all 16 skills** and a skill can carry a third key with the suite green. And the red-flag assertion is existence-only for `systematic-debugging` and `verification-before-completion` — both bodies can be gutted green, and it is their **only** coverage.

- [ ] **Step 4: The runner's python blindness**

1443 python results across two files contribute **1** to the total, and one of the two emits no `PASS` line at all. Give the runner a granularity that distinguishes them. **`CLAUDE.md` forbids hardcoding the expected total**, so the fix is not writing a number down.

- [ ] **Step 5: Mutation-prove each, then gates and commit**

Every guard you touch: break the thing it now claims to check and confirm **that specific assertion** reddens. Report which other assertions reddened — a mutation that reddens everything has isolated nothing.

---

## Task 11: Claims are re-derived or removed

**Files:** `docs/HOOK-REFERENCE.md`, `docs/GETTING-STARTED.md`, `.claude/UPSTREAM`, `.claude/skills/unity-planning/SKILL.md`, `tests/test-derived-counts.sh`, and the citation sites.

- [ ] **Step 1: The citations that have already rotted**

```bash
/usr/bin/grep -rhoE '[A-Za-z0-9_./-]+\.(sh|md|tsv|json):[0-9]+' tests/*.sh docs/*.md | sort -u
```

Fifteen citations; **at least two are wrong** — one cites a line that is now blank, another a line that is now a section banner. Fix them, then **guard the class**: a check that resolves each citation and fails when it does not. Say what that guard cannot see — a rename breaks a content anchor as silently as an insertion breaks a number.

- [ ] **Step 2: `HOOK-REFERENCE.md` states two things that are false**

It says twice that **all hooks source `_lib.sh`** — `session-brief.sh` does not, which makes it the only hook honouring no kill switch. And it says the standard profile includes **18** hooks; the measurement is different. Derive both.

Decide whether `session-brief.sh` should gain the kill switch or the document should record the exception. **It is the hook that seeds `using-kinglet` into every session**, so the answer is not obvious — say which you chose and why.

- [ ] **Step 3: `.claude/UPSTREAM` names four files that do not exist in an installed project**

Verify against a real install, not the repo.

- [ ] **Step 4: `unity-planning` states no threshold**

It owns the execution fork and labels one branch "(recommended)" unconditionally, while `unity-execution` and `subagent-driven-implementation` both carry the same threshold verbatim. Make the three agree.

- [ ] **Step 5: The five derived counts, guarded**

`docs/GETTING-STARTED.md`'s five counts have no guard, and Task 1 added the hook block. Extend the derivation to the rest rather than correcting the numbers by hand.

- [ ] **Step 6: Gates, commit**

---

## Task 12: The early-exit-reader trap leaves the shipped scripts

**Files:** `scripts/generate-claude-md.sh`, `scripts/detect-missing-refs.sh`, `scripts/validate-asmdefs.sh`, `tests/test-bash32-compat.sh`, and the five `stat -c` sites in `install.sh`.

- [ ] **Step 1: Establish which of the survivors carry it**

```bash
/usr/bin/grep -n 'head -1\|| *grep -q' scripts/*.sh
```

`generate-claude-md.sh` has `name=$(sed -n '…' "$asmdef" 2>/dev/null | head -1)` — a bare assignment under `set -euo pipefail` with **no `|| true`**, the exact shape that killed `studio-doctor.sh` at 29 of 30 runs. `validate-architecture.sh`'s many `| head -1` are **safe** — each ends `|| true` inside the substitution. Check each rather than assuming.

- [ ] **Step 2: Fix, and widen the sweep that missed them**

`tests/test-bash32-compat.sh`'s `PIPE_CHECK_DIRS` excludes `scripts/` on a recorded ground that names one of these files as the accepted exception. That judgement was made before the current set of scripts existed and nothing re-runs it. **Bring `scripts/` into the sweep** or record why not, deriving the file set rather than listing it.

- [ ] **Step 3: `stat -c '%a'` at five sites**

GNU-only; on BSD the row records `644` for a `600` file. Nothing reads the mode column, so the consequence is cosmetic — **move all five together** or none, and say which.

- [ ] **Step 4: Gates, commit**

---

## Task 13: The loop learns the five shapes a scoped review cannot see

**Files:** `.claude/skills/subagent-driven-implementation/SKILL.md`,
`.claude/skills/subagent-driven-implementation/re-review-prompt.md`,
`.claude/skills/subagent-driven-implementation/final-reviewer-prompt.md`,
`.claude/skills/subagent-driven-implementation/task-reviewer-prompt.md` (Step 0 only),
`provenance.tsv` (note column only). **Do not touch `implementer-prompt.md`** — the shapes below are
review-side, and widening the implementer's prompt with them turns a dispatch into a checklist the
implementer performs on itself, which is the thing this whole loop exists to stop.

**Interfaces:**
- Consumes: nothing. This task reads two audit records and writes prose.
- Produces: three shipped surfaces gain content. **`tests/test-derived-counts.sh` and
  `tests/test-skill-discovery.sh` both read this skill directory** — discovery asserts the flat
  layout and the frontmatter, and any skill an agent, a command **or another skill** names by path
  must exist. If you add a path-form reference to a surface, that surface must exist.

**Why this is a task and not a controller edit:** the controller never fixes findings in its own
session — a controller patch skips review entirely, and the whole point of the loop is that a second
reader checks the first reader's work. These findings came out of an audit the controller
commissioned; they get an implementer and a reviewer like everything else.

- [ ] **Step 0: The skill contradicts itself about how a finding is cited — settle it**

`SKILL.md` states, as a rule with a measured incident behind it: *"Cite by name, not by line number.
In dispatches and re-review prompts, name the test, the method or the symbol — line numbers passed
from a report into a dispatch go stale between the two… Measured: a controller forwarded a range
citing lines 410–423 of a 378-line file."*

`task-reviewer-prompt.md` states, in its verdict format: *"Each finding at `file:line`. A finding
with no location is not actionable — send it back for one."*

Both are shipped, in the same skill directory, and they instruct opposite things. Verify both
sentences are still present at HEAD before you touch either (`/usr/bin/grep -n` — the interactive
`grep` here is ugrep and will lie to you about an absence).

**The resolution is not "pick one".** The reviewer's requirement is real — a finding with no location
is not actionable — and so is the rot. Rewrite the reviewer's clause to demand a location that does
not rot: **the file, plus the symbol, heading, function or exact needle text**, with a line number
permitted only as a convenience alongside it, never alone. Then make `SKILL.md`'s rule say that too,
so the pair agrees rather than one deferring to the other.

This is in scope because it is the same defect class as the five shapes below — a claim inside a
guard, consistent with itself, never checked against the world — and because every review this plan
still has to run reads one of these two files.

- [ ] **Step 1: Read the two records, and check the skill against them**

`.superpowers/sdd/2026-08-13-surface-criterion/task-1-whole-audit.md` (the audit) and the ledger's
*The five shapes a scoped review structurally cannot see*. For each of the five, decide by reading
`SKILL.md`: does the loop already say this, say something adjacent, or say nothing? **Report the
three-way split before you write anything.** A skill that already says it and was ignored is a
different defect from one that never said it, and the fix for the first is not more prose.

- [ ] **Step 2: The five shapes go into the loop as steps, not as an essay**

`SKILL.md` already has a *Rules learned running this* section built from measured incidents — match
that voice: the incident, then what it costs, then the step. Each of the five must land somewhere a
reader executing the loop actually is when they need it:

- **(1) the diff is not the blast radius** and **(2) prose has tense** are *post-round* steps →
  they belong in the per-task flow, at the point the round is about to be reported complete.
- **(3) a class-fix is reviewed as a list of edits** and **(5) coverage is self-attested** are
  *reviewer* instructions → `re-review-prompt.md`, whose existing text already argues the adjacent
  point ("repeating the implementer's own probe proves only that their probe passes").
- **(4) every artifact under review is a repository** is a *dispatch* condition → the per-task flow,
  worded so it fires on a payload **shape** change rather than on any change.

Do not create a sixth heading called "The five shapes". A list that reads as an appendix gets read
once; the loop's existing rules are read because they sit where the work is.

- [ ] **Step 3: Mutation becomes an instruction, not a suggestion**

The audit's strongest instrument was mutation — falsify a claim, run the suite, see whether anything
reddens. Four of thirteen findings were settled that way in minutes, and every time the answer was
*the suite does not care*. A per-round review that mutated each claim it verified would have caught
four of thirteen at the round that introduced them.

Add it to `re-review-prompt.md` as a requirement with its own failure mode named: **a claim you
verified by reading is not verified.** Give the shape concretely — change the claim to something
false, run the gate, and if the gate stays green the claim is unguarded and that is the finding, not
a footnote. Include the counter-case: a mutation that does not apply (because the code it targets was
deleted) reports a clean result that means nothing — this wave measured exactly that twice, and the
remedy is `cmp` plus an explicit `MUTANT DID NOT APPLY` rather than trusting a zero.

- [ ] **Step 4: `final-reviewer-prompt.md` gains the aggregate sweep**

Shape (1)'s sub-finding is that the removal sweep was keyed on **names**, and a bare numeral, a
category word, a capability sentence and a scope claim contain no removed name — **sweep (b) has
never run.** The whole-branch review is the only reader positioned to run it, because it is the only
one that sees every removal at once. Write it as a required category with its four search shapes
spelled out.

- [ ] **Step 5: Red-first — prove the skill's own guards see the change**

This is a payload directory with two guards over it. Before committing, verify by mutation:

```bash
bash tests/run-tests.sh 2>&1 | tee "$SCRATCH/suite.log"
sed $'s/\x1b\\[[0-9;]*h//g;s/\x1b\\[[0-9;]*m//g' "$SCRATCH/suite.log" | /usr/bin/grep -c '^--- test-.*\.sh ---'
ls tests/test-*.sh | wc -l
```

Then break each of these deliberately, one at a time, confirm the suite reds, and restore:
`name:` no longer matching the directory; a `description:` emptied; a path-form reference to a skill
that does not exist. **If any of the three stays green, that is a Task 10-class finding and it goes
in your report** — do not fix it here, Task 10 owns hollow guards.

- [ ] **Step 6: Provenance and baseline**

`.claude/skills/subagent-driven-implementation/` is **inside** `migration/baseline-inventory.json`'s
scope (`.claude/**`), so this task drifts it. **Do not run `baseline-regenerate` yourself** — ruling
R6: `--dry-run` reads the *anchor commit's* tree and returns a confident `0 change(s)` on uncommitted
edits, so no figure you produce from inside a worktree is trustworthy. Regeneration is the
controller's merge step. Say in your report **which files you changed**, so the controller's
`--expect-drift` is derived rather than guessed.

`provenance.tsv`: these rows exist already. Append to the **note** column; do not add rows, and do
not change `origin` — `subagent-driven-implementation` is this repository's own surface built on an
idea Superpowers had first, and `.claude/NOTICE.md` carries that credit. Keep apostrophes **straight**
in anything you append: a curly `'` reds `tests/test-provenance-origins.sh`.

- [ ] **Step 7: Gates, commit**

Both gates. Commit message through a file (`git commit -F <path>`).

---

## Self-Review

**Spec coverage.** O1 → Task 1. O2 → Task 2. O3 → Task 3. D2 → Tasks 4, **4b**, **4c**. D3 → Task 5.
O4 → Task 6. D1 → Task 7. O5 → Task 8. O6 → Task 9. D4 → Task 10. D5 → Tasks 1, 11. D6 → Task 12.
**Task 13 implements no spec item** — it is the loop's own correction, from the whole-task audit that
ran after Task 1 closed, and it is in this plan because it must be reviewed like everything else
rather than hand-applied by the controller. Acceptance criteria 1–15 are checked at each stage
boundary and re-run whole at the end.

**Placeholder scan.** Five places delegate judgement deliberately and say so: Task 5 Step 3's exit
contract, Task 5 Step 4's assertion location, Task 6 Step 2's root-level rows, Task 11 Step 2's
kill-switch choice, and Task 12 Step 3's five sites. Each names what the implementer must report.
Two more were added with the new tasks: Task 4c Step 3's count shape, and Task 13 Step 2's placement
of each of the five shapes. Both name the decision and require it in the report.

**Ordering.** Stage 1 first because it shrinks the tree everything else works against; Task 2 after
Task 1 because two of its probe subjects are on the cut list; Task 11's count guard depends on Task
1's hook block existing. **The three new tasks slot by file, not by stage:** 4b and 4c are
`install.sh` work and are serialised against 4, 5 and 6 by the batch plan; 13 touches only
`.claude/skills/subagent-driven-implementation/` and conflicts with nothing.

**One gap found and closed while reviewing:** Task 2's probes include two hooks that Task 1 deletes,
so Step 3 now asks explicitly whether their true-positive behaviour needs to survive anywhere —
otherwise the wave cuts a gate and silently drops the protection with it.

**Two gaps found after the fact, by audits rather than by review, and that is the point.** The
missing-end-marker data loss (**4b**) and the dead-registration upgrade (**4c**) were both invisible
to every per-task review that ran, because each sat in a file the task under review never opened.
Task 13 exists so the loop stops relying on an audit to find them.