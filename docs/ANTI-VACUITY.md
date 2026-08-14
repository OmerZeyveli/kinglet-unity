# Anti-Vacuity Floors

*Written 2026-08-14. The rule this repository had applied about sixty times and never written down.*

A guard that is green because it **scanned nothing** is this repository's worst failure shape. It is
worse than a red, because a red gets fixed. Every sweep here is some form of *"derive a set, look for
violations in it, report none"* — and every one of them reports **the same green over the empty set
as over a clean tree**.

An **anti-vacuity floor** is an assertion whose only job is to establish that the derived set is
there, so the silence beside it means something.

This file is the criterion, the rules, and — the part that is the artifact — **the table of every
floor in the tree, its subject, the ratio it implies, and whether it survives its subject
collapsing.** The prose is secondary; the table is what a reviewer reads.

---

## The criterion

Written before the set was counted, because two readers who agree on a number without a written
criterion have agreed by accident. One quantity in this repository was reported as 10, 11 and 12 by
three careful readers and settled only when someone stated what was being counted.

A construct is an **anti-vacuity floor** if and only if all four hold.

| | |
|---|---|
| **C1 — derived subject** | It bounds a quantity produced by reading the tree at run time — a glob, `find`, `grep -c`, `awk`, `jq`, a pathspec sweep, a document scan — not a literal written into the guard. |
| **C2 — lower-bound verdict** | Its verdict is that the subject is *present* or *big enough*: a numeric bound (`-ge N`, `-gt 0`, `-lt N` as the failure trigger), a non-empty string or file (`[ -n … ]`, `[ -s … ]`), a readable-shape check (`assert_eq yes "$([ -n "$X" ] && echo yes || echo no)"`), an **identity** against a second *independent* derivation of the same quantity, or a sentinel string that any of those set. |
| **C3 — it fails the file** | The verdict reaches an assertion helper, an `exit`, or a counted failure. A printed warning, a `continue`, or a comment is not a floor. |
| **C4 — vacuity is its purpose** | The assertions it guards would **pass** over the empty subject. A bound that is itself the claim under test is not a floor: *"0 mobile terms found"*, *"0 dangling references"*, *"0 orphan rows"* are all **satisfied** by emptiness rather than defeated by it, and each needs a floor of its own. |

**Scope.** Files that *execute* assertions: `tests/*.sh`, `scripts/*.sh`, `.claude/hooks/*.sh`,
`install.sh`, `uninstall.sh`. A Markdown file can never satisfy C3, so **this document is outside the
derivation's scope by construction** — not by an exclusion pattern. That matters: the standard remedy
for a derivation that matches its own record is an exclusion, and an exclusion anchored `^\./`
excludes nothing under this host's `ugrep` front-end and reports a *larger* number rather than
erroring. Filter by something the recording cannot match.

**Unit of count.** One floor = **one assertion site that can red on its own**. A single `assert_eq`
fed by a sentinel that four separate bounds can set is **one** floor whose subject is the union of
four sources — and collapsing it into one is not a rounding convenience, it is the defect this file
is about.

---

## The two failure shapes, named separately

A reader who fixes one of these still ships the other. They are different.

### Shape 1 — composition. *A floor over a summed multi-source subject cannot detect one source dying, however tight the number.*

The floor sees the sum. One source can reach zero and the survivors carry the total over the bar.
**Tightening the number does not help**: with sources of 13, 7 and 40, a floor of 55 out of 60 still
passes with the 13 gone.

Two guards in this tree stayed green over a **fully emptied payload** for exactly this reason, and
they were the only two of the suite's 39 test files that did.

- `tests/test-no-mobile.sh` — `SCAN_FILES >= 1` over five roots summing to 329 files. `docs/` alone
  holds 186, so the floor cleared with **zero files under `.claude/`**. Measured in a clone:
  **17 passed, 0 failed, rc 0** — identical in verdict to a healthy tree.
- `tests/test-bash32-compat.sh` — `SS_ALL_N > 0` over five sources and `SS_PIPE_N > 0` over four.
  `tests/` holds 40 `.sh` files, so both totals cleared with `.claude/hooks/` — the directory the
  file was originally written for — completely empty. Measured: **8 passed, 0 failed, rc 0**.

**The fix is one shape for both: assert per source, not per union.** Both are converted; the
mutations are recorded under [Proof](#proof) below.

### Shape 2 — magnitude. *A floor catches a subject that empties. It does not catch one that narrows.*

A single-source floor sized far below its subject tolerates losing most of it. Measured on
`tests/test-citations-resolve.sh`, whose scanned set comes from a git pathspec guarded by
`LIVE_N >= 30`:

- the pathspec **emptied** → the floor fires, **2 pass / 3 fail, rc 1**;
- the pathspec **narrowed** — one element dropped, scanned set from 125 files to 63, **half the
  subject gone** → **5 pass / 0 fail. Fully green.**

And it is not hypothetical. A deliberate correction to that same pathspec narrowed the set from 142
to 125 on the same day, and **nothing in the suite would have caught that either**. A 24 % floor
tolerates losing three quarters of what it watches.

---

## The rules

### F1 — a floor is needed wherever silence is the passing condition

If an assertion passes when a sweep finds nothing, it needs a floor. That is nearly every guard here.
The question to ask of any new one is not *"is this likely?"* but *"what does this print if the
derivation returns the empty set?"* — and if the answer is `PASS`, write the floor in the same
commit.

Corollary, already paid for once: **a probe whose passing condition is silence must first prove its
own baseline is not silent.** Print the non-silent measurement beside every zero.
`tests/test-hook-behaviour.sh` prints each hook's acting byte count beside its two silenced zeros for
this reason.

### F2 — prefer an identity to a threshold

**A threshold has to be sized, and sizing is where feel enters.** An identity does not.

The worked example is `tests/test-hook-behaviour.sh`, at the assertion reading *"settings.json
registers every hook file present in .claude/hooks"*. Its floor is not a number at all: it is an
identity between **two independently derived tree quantities** — the `.claude/hooks/*.sh` files less
`_lib.sh`, against the distinct commands `jq` finds in `.claude/settings.json`. Currently 12 == 12.

An identity floor:

- **cannot be sized too low** — it is 100 % by construction;
- **cannot go stale** — it moves with the tree, so adding or cutting a hook keeps it correct with
  nobody editing a number;
- **detects both failure shapes** — emptying *and* narrowing, because the other side does not move
  when one side shrinks.

`tests/run-tests.sh` uses the same instrument twice: the test-file glob against `find`, and the
number of files actually **run** against the number discovered.

**What it costs, stated because it is not free.** An identity needs a *second, independent*
derivation of the same quantity, and not every subject has one. Independence is the whole
requirement, and it is easy to lose: `tests/test-skill-discovery.sh` asserts `FM_CHECKED == FM_DIRS`,
which looks like an identity and is not — `FM_CHECKED` is counted by the loop that iterates over
`FM_DIRS`, so both go to zero together and `0 == 0` passes. That file's own comment says so, and it
adds `FM_DIRS >= 1` underneath precisely because the equality could not carry the weight.

**Where no independent derivation exists**, in order of preference:

1. **Bound the subject against a property of the guard's own source** rather than of the tree — an
   array length, a table's row count. The tree cannot move it, and it moves when the guard is
   edited. `tests/test-bash32-compat.sh` now compares its per-source census against the sum of its
   four scope-array lengths.
2. **Bound each source separately** (F3), which converts one loose threshold into k tight presence
   checks.
3. **Only then** a threshold — and size it against **the cheapest plausible narrowing**, not against
   zero. `tests/test-skill-discovery.sh`'s `S2S_CHECKED >= 5` is the model: five is calibrated so
   that restricting the sweep to a single skill directory, which yields at most four, trips it.
   *"Far above zero"* is not a calibration.

### F3 — per source, not per union

Where a subject is assembled from k sources, assert on each of the k. This is the fix for Shape 1,
and it costs nothing but a loop.

Three guards already do it and are worth copying:

- `tests/test-citations-resolve.sh` bounds each of its **four citation-shape sweeps** separately,
  with the comment *"a union hides it: two live sweeps carry a dead one to a green result."*
- `tests/test-provenance-origins.sh` bounds its dead-name scan **per glob** — payload, scripts, docs,
  README — instead of on the 77-file total.
- `tests/test-shipped-citations.sh` floors `.claude/scripts/` entries at 1 *inside* a payload
  derivation already floored at 55, and says why in the failure message: without it *"the count then
  falls to 61 and still clears the floor of 55."*

**Accumulate the failing sources; do not overwrite a sentinel.** A reassigned sentinel names only the
last dead source, and which one that is depends on iteration order. Measured while writing this: on a
fully emptied payload the first version of the converted `tests/test-no-mobile.sh` named
`.claude/state` — the least interesting of its seven dead sources — and nothing else.

### F4 — a floor whose reference the mutation also moves is not a floor

**Measured on this task's own fix, on its first mutation run.**

The converted `tests/test-no-mobile.sh` derives its source list from `SCAN_DIRS` plus the
subdirectories of `.claude/`, and floored the result at `>= ${#SCAN_DIRS[@]}`. Setting
`SCAN_DIRS=()` drives that reference to **0**, so `-ge 0` is trivially true; the six derived
`.claude/` sources still populate the census, so every per-source check passes; and the actual
`grep -r` sweeps below then run over **no roots at all**. Result: **17 pass / 0 fail** — a full green
over a sweep with nothing in its scope, from the block written to stop exactly that.

The same shape sat in the converted `tests/test-bash32-compat.sh`: emptying `SHIPPED_SCRIPT_DIRS`
removes three rows from **both sides** of the census identity at once, so the identity holds, every
surviving per-source count is ≥ 1, and the bash-4 sweep silently falls from 62 files to two.

Both are closed with an **absolute** floor on the array itself. The rule generalises: when you write
a floor, ask what the reference is made of, and whether the failure you are guarding against moves
it. If it does, the floor is decoration.

### F5 — the predicate must be the requirement, not a weaker relative of it

A floor that tests the wrong predicate is the same defect as a floor sized by feel; it just fails
later.

`tests/test-hook-behaviour.sh` requires each probe to carry a **discriminating** needle, and floors
it with `[ -n "$NEEDLE" ]`. That predicate's covered set is the singleton `{""}`. Measured: `' '`,
`'e'` and `$'\n'` all pass the floor and all match anything — and `grep -qF -- $'\n' <<< ""` matches
an **empty haystack**, because `grep -F` splits the pattern on newlines into two empty patterns, so a
newline needle is behaviourally identical to the empty one the floor exists to reject. The decisive
combination — gutting a hook's warning *and* using a whitespace needle — was measured at **86 pass /
0 fail**.

**Ruling, carried from that task and confirmed here:** the floor stays. The uncaught cases require
deliberately *typing* a degenerate value rather than omitting a line, and the floor does close
omission in every reachable form. Under a written criterion — *a needle is degenerate if it matches
the one-character haystack `x`* — all twelve shipped needles are 15–70 bytes and none is degenerate.
What the criterion demands is that the gap be **stated**, not that it be closed at any cost.

### F6 — the vacuity check is itself a subject, and unions hide inside it

A per-file *"this file still states its claim"* check is a floor whose subject is *the set of sites in
that file matching the pattern*. If the pattern matches two sites, the floor is a union over them and
either one can be reworded out of reach.

This repository has now found the same defect at **three granularities**, each time inside the fix
for the last one:

1. **Across files** (2026-08-03) — a combined threshold let one file lose its occurrence entirely
   while another's kept the total up. Remedy: count per file.
2. **Across phrasings** in one file — a per-file check was satisfied by an unrelated occurrence and
   could not see a third phrasing being reworded away. Remedy: `tests/test-derived-counts.sh`'s
   `DC_PAIR_VACUOUS`, a named check for that phrasing alone.
3. **Across sites** of one phrasing — `docs/HOOK-REFERENCE.md` states the cost of the `minimal`
   profile in two sentences, both matched by one claim row. Measured 2026-08-14: reverting either
   sentence to a digit-free wording left `tests/test-derived-counts.sh` at **32 pass / 0 fail**,
   while a wrong digit correctly red it at 31/1. **The digit was checked; the sentence was not.**

Remedy, and it is a rule rather than a fourth hand-fix: **every claim row must match exactly one
site**, asserted mechanically in all three claim tables of `tests/test-derived-counts.sh`. Measured
across the 43 rows at the time: 42 matched one site, one matched two.

### F7 — never lower a floor to make a run pass

Lowering a floor is the exact move that hides a broken derivation. The only legitimate reason is that
the tree **shrank by a decision recorded somewhere a second guard reads** — a `rule=absent` row in
`provenance-skip.tsv`, a cut with a ledger entry. `tests/test-shipped-citations.sh` lowered
`MD_COUNT` when 15 hooks and 4 scripts were cut, and pinned the justification to the skip list rather
than to the run that failed. Say which decision, in the commit.

---

## The floor set

**68 assertion sites** meet the criterion in the current tree — **63 before this document existed**,
plus five added by the conversions and the F6 rule.

**That is more than twice the ~28 the previous wave carried, and the difference is a finding rather
than a discrepancy to reconcile.** The earlier figure was produced by a window scan with no written
criterion — the same derivation lost 14 of its members to an `awk` `getline` window and looked
complete. Under C1–C4, applied to every file that executes an assertion, the set is the table below.
Re-derive it rather than trusting this number; the mechanism space to enumerate is C2's, and **build
the window from an array, never with `getline`**.

Ratio = the smallest subject that still passes, over the subject today. **Survives** = does the floor
still pass after the subject loses a whole source (Shape 1) or most of its magnitude (Shape 2)?

**The table has one row per BOUND; the count of 68 is per SITE.** Where one assertion carries several
bounds they are listed separately because each is a different claim about a different subject — the
three `test-no-mobile.sh` rows below are one site, and so are the four `test-bash-gate-precision.sh`
rows. Reading the table as a census of sites will overcount; that is the price of showing every
bound, and showing every bound is the point.

### Converted or added by this pass

| Guard · assertion anchor | Subject | Bound | Today | Ratio | Survives |
|---|---|---|---|---|---|
| `test-no-mobile.sh` · *every mobile-sweep source has files in it* | 11 sources: 5 scan roots + 6 `.claude/` subdirectories | ≥ 1 **each** | 63/8/9/13/6/20/2/186/4/8/10 | 100 % per source | **no** |
| `test-no-mobile.sh` · same assertion, census floor | rows in the derived source list | ≥ `${#SCAN_DIRS[@]}` | 11 ≥ 5 | — | no |
| `test-no-mobile.sh` · same assertion, array floor (F4) | `SCAN_DIRS` itself | ≥ 1 | 5 | — | no |
| `test-bash32-compat.sh` · *every source of both sweeps resolves to at least one file* | 9 sources across two scopes | ≥ 1 **each** | 13/7/40/1/1 + 13/7/1/1 | 100 % per source | **no** |
| `test-bash32-compat.sh` · *the per-source census covered every declared scope entry* | census rows vs. four array lengths | **identity** | 9 == 9 | 100 % | no |
| `test-bash32-compat.sh` · *all four scope arrays are non-empty* (F4) | the four arrays | ≥ 1 each | 3/2/2/2 | — | no |
| `test-derived-counts.sh` · *every hook-count claim row matches exactly one site* (F6) | sites per claim row | **== 1** | 20 rows | 100 % | no |
| `test-derived-counts.sh` · *every surface-count claim row matches exactly one site* | sites per claim row | == 1 | 15 rows | 100 % | no |
| `test-derived-counts.sh` · *every ECU-footprint claim row matches exactly one site* | sites per claim row | == 1 | 8 rows | 100 % | no |

**What they replaced:** `SCAN_FILES >= 1` over 329 files from 5 roots (**0.3 %**, survived losing 5
of 6 payload directories) and `SS_ALL_N > 0` / `SS_PIPE_N > 0` over 62 and 22 files from 5 and 4
sources (**1.6 % / 4.5 %**, survived losing `.claude/hooks/` entirely).

### Identity floors — no ratio, and that is the point

| Guard · assertion anchor | The two derivations | Today |
|---|---|---|
| `test-hook-behaviour.sh` · *settings.json registers every hook file present in .claude/hooks* | `.claude/hooks/*.sh` less `_lib.sh` **vs** distinct commands in `settings.json` | 12 == 12 |
| `run-tests.sh` · *Test discovery is inconsistent* | the `test-*.sh` glob **vs** `find -type f -name 'test-*.sh'` | 39 == 39 |
| `run-tests.sh` · *ran N test files but M match* | files actually executed **vs** files discovered | 39 == 39 |
| `test-bash32-compat.sh` · per-source census | census rows **vs** four array lengths | 9 == 9 |

### Numeric thresholds — every one implies a ratio

| Guard · assertion anchor | Subject | Bound | Today | Ratio | Survives |
|---|---|---|---|---|---|
| `test-citations-resolve.sh` · *citation sweep read N live surface file(s)* | files from a 9-element git pathspec | ≥ 30 | 142 | **21 %** | **yes — both shapes; a 50 % narrowing measured green** |
| `test-citations-resolve.sh` · *all four citation shapes matched* | four regex sweeps | ≥ 1 **each** | 31/11/34/2 | per source | no |
| `test-citations-resolve.sh` · *resolved N live citation(s)* | citations reaching the resolver | ≥ 10 | 26 | 38 % | yes |
| `test-shipped-citations.sh` · *guard scanned N shipped .md files* | `.md` under `.claude/` | ≥ 35 | 44 | 80 % | yes |
| `test-shipped-citations.sh` · *payload derivation produced N entries* | install.sh's payload groups | ≥ 55 | 67 | 82 % | **yes — a whole group can die** |
| `test-shipped-citations.sh` · *payload carries N .claude/scripts/ entries* | one group of the above | ≥ 1 | 6 | 17 % | no *(the per-source refinement of the row above)* |
| `test-shipped-citations.sh` · *guard examined N backticked tokens* | tokens in shipped `.md` | ≥ 200 | 779 | **26 %** | yes |
| `test-shipped-citations.sh` · *guard examined N .claude/scripts/ path reference(s)* | script references in surfaces | ≥ 6 | 9 | 67 % | yes |
| `test-shipped-citations.sh` · *rule 4 derived the project-root installed set* | receipt-row formats in `install.sh` | ≥ 2 | 4 | **50 %** | yes |
| `test-shipped-citations.sh` · *rule 4 examined N repository path(s)* | paths named in `.claude/UPSTREAM` | ≥ 1 | 5 | **20 %** | yes |
| `test-mcp-naming.sh` · *the scan below has a payload to read* | 9-element git pathspec | ≥ 40 | 82 | 49 % | **yes — one element can die** |
| `test-mcp-doc-instructions.sh` · *the sweeps in this file have files to read* | tracked paths under `.claude/` | ≥ 30 | 62 | 48 % | yes |
| `test-surface-references.sh` · *git can read this repository's index* | tracked paths under `.claude/` | ≥ 30 | 62 | 48 % | yes |
| `test-surface-references.sh` · *the absence check read N .md files* | `.md` under `.claude/` | ≥ 35 | 44 | 80 % | yes |
| `test-surface-references.sh` · *the same scan finds the surviving phrase* | files stating the surviving phrase | ≥ 2 | 3 | 67 % | yes |
| `test-surface-references.sh` · *every agent still has a Skills to load block* | per agent file | ≥ 1 **each** | 8 agents | per source | no |
| `test-provenance-origins.sh` · *derived N retired hook/script path(s)* | `rule=absent` rows | ≥ 15 | 19 | 79 % | yes |
| `test-provenance-origins.sh` · *every glob in the dead-name scan returned a plausible number* | 4 globs | ≥ 60 / ≥ 5 / ≥ 4 / == 1 | 62/8/6/1 | **97 % / 63 % / 67 % / 100 %** | per source — no |
| `test-provenance-origins.sh` · *the manifest yields N Superpowers-adapted surfaces* | two derivation routes | ≥ 3 | 3 | 100 % | no |
| `test-skill-discovery.sh` · *the skill→skill sweep still reads the chain* | skill→skill references | ≥ 5 | 11 (6 distinct targets) | 45 % | yes |
| `test-skill-discovery.sh` · *there are skills to check* | skill directories | ≥ 1 | 16 | **6 %** | yes |
| `test-skills.sh` · *the skill walk found skills to check* | `SKILL.md` files | ≥ 1 | 16 | **6 %** | yes |
| `test-hooks.sh` · *the kill-switch sweep found hook files to read* | hook files | ≥ 1 | 12 | **8 %** | yes |
| `test-hooks.sh` · *session-brief prints the brief with no switch set* | output lines | ≥ 1 | 49 | **2 %** | yes |
| `test-cross-validation.sh` · *the hook registrations were actually extracted* | `jq` commands from `settings.json` | ≥ 8 | 12 | 67 % | yes |
| `test-stack-arbitration.sh` · *the guard examined a plausible number of stack-naming surfaces* | surfaces naming the stack | ≥ 10 | 21 | 48 % | yes |
| `test-help-ranges.sh` · *found N self-slicing usage() range(s)* | ranges in tracked scripts | > 0 | 6 | **17 %** | yes |
| `test-help-ranges.sh` · *every self-slicing script carries a literal line range* | the coarse needle's hits | > 0 | 6 | 17 % | yes |
| `test-bash-gate-precision.sh` · *the corpus is not empty* | corpus payloads | > 0 | 331 | **0.3 %** | yes |
| `test-bash-gate-precision.sh` · *…contains payloads that must be blocked* | blocking payloads | > 0 | 113 | 0.9 % | no *(per source)* |
| `test-bash-gate-precision.sh` · *…contains payloads that must be permitted* | permitting payloads | > 0 | 112 | 0.9 % | no *(per source)* |
| `test-bash-gate-precision.sh` · *…payloads an earlier hook version blocked* | historically-blocked payloads | > 0 | not printed | — | no *(per source)* |
| `test-install-ownership.sh` · *H.3: the run announced N kept file(s)* | announced kept paths | > 0 | 2 | 50 % | no |
| `test-install-ownership.sh` · *K: install 1's CLAUDE.md.generated carries the FILL: markers* | `FILL:` markers | > 0 | not printed | — | no |
| `test-install-ownership.sh` · *L: the run wrote N file(s) under .claude/* | files installed before the stop | > 0 | 67 | **1.5 %** | yes |
| `test-install-dryrun.sh` · *dirty: the foreign .claude/ holds N user file(s)* | fixture files | ≥ 2 | 2 | 100 % | no |
| `run-tests.sh` · *No test files found* | discovered test files | ≥ 1 | 39 | **2.6 %** | yes |
| `run-tests.sh` · *ran a python suite that discovered 0 tests* | python results | > 0 | 1444 | **0.07 %** | yes |
| `test-derived-counts.sh` · *the surface counts are derived from a tree that actually has surfaces* | agents / commands / skills | ≥ 1 **each** | 8/9/16 | 13 % / 11 % / 6 % | per source — no |
| `test-derived-counts.sh` · *the hook and script counts are derived from a tree that actually has hooks and scripts* | hooks / registrations / scripts / skipped | ≥ 1 / ≥ 1 / ≥ 1 / == 1 | 12/12/7/1 | 8 % / 8 % / 14 % / 100 % | per source — no |

### Presence floors — no ratio, 100 % by construction

| Guard · assertion anchor | Subject |
|---|---|
| `test-derived-counts.sh` · *still carries a readable kinglet:minimal-drops region* | the marked region in `docs/HOOK-REFERENCE.md` |
| `test-derived-counts.sh` · *still carries a readable kinglet:minimal-keeps region* | the complement region |
| `test-derived-counts.sh` · *still has readable per-hook Profile lines* | the twelve `- **Profile:**` lines |
| `test-derived-counts.sh` · *still has a readable hook Summary Table* | the table's profile column |
| `test-derived-counts.sh` · *still has a readable Tracking Files writer column* | `docs/ARCHITECTURE.md`'s writer column |
| `test-derived-counts.sh` · *still has a readable Event Types table* | `docs/ARCHITECTURE.md`'s event table |
| `test-derived-counts.sh` · the five `…_VACUOUS` accumulators | one per claim row / quoting file — **this is where the F6 union lived** |
| `test-hook-behaviour.sh` · *probe for X carries a non-empty needle* | the needle, per hook — **see F5 for what this predicate does not cover** |
| `test-provenance-origins.sh` · *carries exactly one 40-hex pin* | the ECU pin in `provenance.tsv` |
| `test-stack-arbitration.sh` · *the generator still emits the block every surface now points at* | the heading in `scripts/generate-claude-md.sh` |
| `test-surface-references.sh` · *every .md the absence check opened flattened to something* | per file |
| `test-pipeline-detector.sh` · *git tracks no files at all under the roots* | the sweep's index |
| `run-tests.sh` · *started a python suite that never printed an OK/FAILED outcome* | the suite's outcome line |

---

## Proof

Every floor changed or added here was mutated **twice, in differently shaped ways**, each mutant
`cmp`'d against the original **and** checked for its injected marker, with an explicit
`MUTANT DID NOT APPLY` when either check failed. The payload was emptied in a
`git clone --no-hardlinks --shared`, never a `cp -a` — a `.git` *file* pointing back at the real
repository once cost a reviewer 15 spurious failures.

| Mutation | `test-no-mobile.sh` | `test-bash32-compat.sh` |
|---|---|---|
| pristine | 17 pass / 0 fail | 9 pass / 0 fail |
| **payload fully emptied** (0 files under `.claude/`) | **16 / 1** — names all 7 dead sources | **8 / 1** — names both dead `hooks` rows |
| `.claude/skills/` emptied **only** | **16 / 1** — names `skills` | 9 / 0 — *correctly out of scope* |
| `.claude/hooks/` emptied **only** | **16 / 1** — names `hooks` | **8 / 1** — names `hooks` in both scopes |
| scope array emptied | **16 / 1** — the F4 floor *(17 / 0 before it existed)* | **9 / 1** — the four-arrays floor |
| census derivation silenced | — | **9 / 1** — the identity floor alone |
| a scope directory repointed at a path that does not exist | — | **9 / 1** — the per-source floor alone |

Each mutation reds **one** assertion and leaves the rest passing. A mutation that reds everything has
isolated nothing.

For F6, on `tests/test-derived-counts.sh` (32 pass / 0 fail before the split, 35 after):

| Mutation | Before | After |
|---|---|---|
| second `drops` sentence reverted to its exact pre-fix digit-free wording | **32 / 0 — green** | **34 / 1** — the vacuity assertion |
| first `drops` sentence stripped of its digits | **32 / 0 — green** | **34 / 1** — the vacuity assertion |
| a wrong digit *(control)* | 31 / 1 | **34 / 1** — the **value** assertion, not the vacuity one |
| the two claim rows merged back into one | *(n/a)* | **34 / 1** — the F6 class guard |

---

## What this file does not close

- **Shape 2 is documented, not fixed.** Every threshold in the table with a ratio below ~80 %
  tolerates a narrowing nobody would notice. Converting them to identities needs a second independent
  derivation per subject, and most do not have one.
- **Growing the covered set is still manual.** A guard added without a floor is caught by nothing
  here; there is no check that every sweep has one.
- **`docs/` is not in the derivation's scope**, correctly — a Markdown file cannot fail — but that
  also means this table is maintained by hand and will drift. It is dated, and the anchors are text
  to search for rather than line numbers, so a reader can re-derive rather than trust it.
- **The unit is the assertion site.** A site carrying four per-source bounds counts once. That is
  deliberate — one thing reds — but it makes the count smaller than a bound-by-bound census, which
  would be near 90.
- **Several guards have no floor at all**, and this file does not fix them: `tests/test-templates.sh`
  iterates a glob whose emptiness would pass, and `tests/test-install.sh` answers an empty hook
  directory with `skip_test` rather than a failure — a skip is not a floor, because a suite reports
  skips as neither pass nor fail and nobody reads them.
