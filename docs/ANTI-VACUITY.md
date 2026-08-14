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
| **C2 — lower-bound verdict** | Its verdict is that the subject is *present* or *big enough*: **(a)** a numeric bound (`-ge N`, `-gt 0`, `-lt N` as the failure trigger); **(b)** a non-empty string or file (`[ -n … ]`, `[ -s … ]`); **(c)** a readable-shape check (`assert_eq yes "$([ -n "$X" ] && echo yes || echo no)"`); **(d)** an **identity** against a second derivation of the same quantity that is independent *of the failure being guarded against* — see F2; **(e)** a sentinel string that any of those set; **(f)** **the derivation's own failure**, where the guard treats a non-zero `rc` from `git ls-files` / `awk` / `jq` as *"the subject is empty"* rather than as an error; **(g)** **the absence of a fixture or run-output the guarded assertions need** — *"the run announced nothing, so every assertion below is vacuous."* |
| **C3 — it fails the file** | The verdict reaches an assertion helper, an `exit`, or a counted failure. A printed warning, a `continue`, or a comment is not a floor. |
| **C4 — vacuity is its purpose** | The assertions it guards would **pass** over the empty subject. A bound that is itself the claim under test is not a floor: *"0 mobile terms found"*, *"0 dangling references"*, *"0 orphan rows"* are all **satisfied** by emptiness rather than defeated by it, and each needs a floor of its own. |

**Scope.** Files that *execute* assertions: `tests/*.sh`, `tests/kinglet/**`, `scripts/*.sh`,
`.claude/hooks/*.sh`, `install.sh`, `uninstall.sh`.

**Four of those six segments hold no floor today, and that is now established by criterion rather
than assumed** — a shipped scope that quietly drops a segment is how a segment stops being swept, so
each is stated:

- `tests/kinglet/**` — none. Named because the scope written before counting named it.
- `install.sh` and `uninstall.sh` — none. Every count they derive (`MOD_COUNT`, `RECLAIMED_COUNT`,
  `UNREADABLE_COUNT`, `ORPHAN_COUNT`, `DRY_MOD`, …) reaches only `info` / `warn` / `printf` /
  `note_not_done`, so **C3 fails**; and every numeric guard is `-gt 0`, which fires when the subject
  is *non*-empty. That is the claim being reported, not a floor under it, so **C2 and C4 fail** too.
  The only non-zero exits in either file are `die()`'s and one argument check.
- `.claude/hooks/*.sh` — none, across all 13 files. The single non-zero exit in the segment is
  `_lib.sh`'s `unity_hook_block` → `exit 2`, which is the block verdict, i.e. the claim under test,
  **excluded by C4**. And a hook's subject is the JSON payload on stdin, not the tree, so **C1 fails
  for every one of them.**

`scripts/*.sh` holds exactly one, `scripts/check-provenance.sh`'s, tabled below. `tests/*.sh` holds
the rest. A Markdown file can never satisfy C3, so **this
document is outside the
derivation's scope by construction** — not by an exclusion pattern. That matters: the standard remedy
for a derivation that matches its own record is an exclusion, and an exclusion anchored `^\./`
excludes nothing under this host's `ugrep` front-end and reports a *larger* number rather than
erroring. Filter by something the recording cannot match.

**Unit of count.** One floor = **one assertion site that can red on its own**. A single `assert_eq`
fed by a sentinel that four separate bounds can set is **one** floor whose subject is the union of
four sources — and collapsing it into one is not a rounding convenience, it is the defect this file
is about.

---

## The measured class: what survives an emptied payload

Before the shapes, the measurement they explain. **`find .claude -type f -delete`** on the pre-task
tree — 62 files to 0, every directory kept (**six** under `.claude/` at depth 1, 22 counting the
per-skill subdirectories) — then all 39 test files through the runner. The depth-1 six are the
number F8 turns on: `find .claude -mindepth 1 -maxdepth 1 -type d` still answers *six* over this
tree, which is why a **derived** source list sees nothing wrong with it:

| verdict | files |
|---|---|
| **green, byte-for-byte the same counts as a healthy tree** | `test-assert-helpers-under-load.sh` (2/0) · `test-bash32-compat.sh` (8/0) · `test-help-ranges.sh` (27/0) · `test-input-system-check.sh` (2/0) · `test-install-dryrun.sh` (168/0) · `test-kinglet-spike.sh` (1/0) · `test-mcp-config.sh` (10/0) · `test-mcp-naming.sh` (3/0) · `test-no-mobile.sh` (17/0) · `test-rule-applicability.sh` (41/0) · `test-templates.sh` (3/0) — **eleven** |
| **green at a collapsed count** | `test-hook-behaviour.sh` **86 → 2** |
| red | the other 27 |

**An earlier draft of this section said "the only two of the suite's 39 test files". That was
false**, and it was false in the direction that matters: it under-reported the class by a factor of
six and named as unique a property that eleven files share. It came from measuring only the two
files the task was scoped to convert and generalising from them. **The two converted here are two of
eleven, and they are the two whose subject is unambiguously the payload; at least three of the other
nine also scan the payload** and are equally wrong to be green — `test-mcp-naming.sh`,
`test-install-dryrun.sh` and `test-help-ranges.sh`. Some of the eleven are *correctly* green
(`test-templates.sh` reads `templates/`, `test-assert-helpers-under-load.sh` reads nothing under
`.claude/`); the criterion cannot tell those apart from the wrong ones without reading each guard's
subject, and this table does not claim to.

**The floors those guards printed while their payload did not exist** — each one a PASS, quoted from
the emptied run:

```
PASS: citation sweep read 142 live surface file(s) (floor 30)
PASS: found 6 self-slicing usage() range(s) across 6 tracked script(s)
PASS  the sweeps in this file have files to read
PASS  the scan below has a payload to read
PASS  settings.json registers every hook file present in .claude/hooks (0 present)
```

The last one is this document's own worked example, printing its zero.

---

## The three failure shapes, named separately

A reader who fixes one of these still ships the others. They are different.

### Shape 1 — composition. *A floor over a summed multi-source subject cannot detect one source dying, however tight the number.*

The floor sees the sum. One source can reach zero and the survivors carry the total over the bar.

**Tightening the number moves the boundary; it does not close the class.** Worked on the real subject
this shape was found in — `tests/test-bash32-compat.sh`'s bash-4 sweep, whose five sources measure
**13 + 7 + 40 + 1 + 1 = 62** files (`.claude/hooks`, `scripts`, `tests`, `install.sh`,
`uninstall.sh`; re-derived in a clean clone at `5881463`). Against a hypothetical floor of `>= 55`:

| source that dies | total left | verdict |
|---|---|---|
| `.claude/hooks` (13) | 49 | **caught** — 49 is below 55 |
| `scripts` (7) | 55 | **missed** — 55 clears the bar exactly |
| `install.sh` or `uninstall.sh` (1) | 61 | **missed** |

A floor of `F` over a total of `T` catches exactly the sources **larger than `T - F`**; every source
inside that slack dies green. Raising `F` shrinks the slack and catches more sources, so tightening
is not useless — but the only constant that catches all five is `T` itself, 62, and that is not a
threshold sized against a narrowing. It is a hand-written copy of today's tree, red on the next file
legitimately added or removed, and stale by construction. **For any constant a maintainer would
actually ship there is a smaller source above it.** That is what the heading means by *however tight
the number*: no constant short of the identity closes the class, and the identity is not a constant.

**This paragraph read *"Tightening the number does not help: with sources of 13, 7 and 40, a floor of
55 out of 60 still passes with the 13 gone"* for four rounds, and it was wrong in every clause.**
13 + 7 + 40 is 60, and 60 - 13 = **47**, which is *below* 55: the floor fires. It fires on every
single-source death in that example (47, 53, 20), so the example demonstrated the opposite of its own
sentence. The subject it was drawn from has **five** sources totalling **62**, not three totalling
60. And the consequence was not cosmetic — as written it told a maintainer that tightening the union
floor is futile *and* that no other move exists, when F3 two sections down says to convert the union
to per-source. **The sole worked justification for this shape inverted the rule it justifies.**
Recorded rather than quietly replaced: a file about unchecked numbers that silently repairs its own
is not making the point.

**This does not contradict F2's fallback step 3, which sizes a threshold against the cheapest
plausible narrowing.** A constant *does* catch every narrowing that takes its subject below it — step
3 is right, and its model (`tests/test-skill-discovery.sh`'s `S2S_CHECKED >= 5` over a subject of 6)
is a single-subject **magnitude** floor whose cheapest narrowing is knowable and measurable. What
Shape 1 rules out is a constant that catches the **smallest source of a union** without being that
union's own total. Task 3 of this wave reached the same conclusion independently and by execution,
from the opposite direction: its equivalent *"no constant helps"* sentence was falsified by running
it — a narrowing to 17 files **does** fire a floor of 30, and raising 30 to 100 **does** catch the
63-file case. Both tasks landed on the same true form.

Two of the eleven above are green for exactly this reason, and they are the two converted here:

- `tests/test-no-mobile.sh` — `SCAN_FILES >= 1` over five roots summing to **271** files (the guard
  printed its own answer: `the mobile sweep has roots to read (271 file(s))`). `docs/` alone holds
  187, so the floor cleared with **zero files under `.claude/`**. Measured in a clone:
  **17 passed, 0 failed, rc 0** — identical in verdict to a healthy tree.
- `tests/test-bash32-compat.sh` — `SS_ALL_N > 0` over five sources and `SS_PIPE_N > 0` over four.
  `tests/` holds 40 `.sh` files, so both totals cleared with `.claude/hooks/` — the directory the
  file was originally written for — completely empty. Measured: **8 passed, 0 failed, rc 0**.

**The fix is one shape for both: assert per source, not per union.** Both are converted; the
mutations are recorded under [Proof](#proof) below.

**And per source is not enough on its own — see F8.** A per-source census whose *source list* is
derived from the tree cannot see a **deleted** source, because a deleted directory is not a dead
source, it is not a source. Measured on the first version of this task's own fix: `.claude/skills`
emptied → 16/1 caught; `.claude/skills` **deleted** → **17/0**, not caught.

### Shape 2 — magnitude. *A floor catches a subject that empties. It does not catch one that narrows.*

A single-source floor sized far below its subject tolerates losing most of it. Measured on
`tests/test-citations-resolve.sh`, whose scanned set comes from a nine-element git pathspec guarded
by `LIVE_N >= 30`. **Every number below was re-measured on this branch at `28f4a8a`** — an earlier
draft carried three sizes for one subject (142, 125, 63) taken partly from another branch, which is
the wave's own *"do not carry numbers across trees"* rule landing on the artifact:

**EVERY FIGURE BELOW NAMES ITS TREE, because this subject is being edited by another task right
now and the two trees disagree.** A number without a tree is the *"do not carry numbers across
trees"* rule waiting to happen — it has already cost this task one round.

On **`task/n5-floors` @ `2df8b92`** (this branch; the pathspec is unanchored, `'*.md'` crosses `/`):

| mutation | `LIVE_N` | verdict |
|---|---|---|
| pristine | **143** | 5 pass / 0 fail |
| drop `'.claude/*'` | 125 | **5 / 0 — fully green**, 18 files gone |
| drop `'*.md'` | 120 | **5 / 0 — fully green**, 23 files gone |
| drop `'docs/*.md'` | **143** | **5 / 0 — no change at all**: redundant *on this tree* |
| drop `'tests/*.sh'` | 103 | 4 / 1 — red, but on the *shape* sweep, not the floor |

On **`task/n3-pathspecs` @ `2f3293b`**, where Task 3 has already anchored `'*.md'` to
`':(glob)*.md'` so it no longer crosses `/`:

| mutation | `LIVE_N` | verdict |
|---|---|---|
| pristine | **125** | 5 pass / 0 fail |
| drop `'docs/*.md'` | 119 | **5 / 0 — fully green**; it now contributes **6 unique files** |
| drop `':(glob)*.md'` | 119 | **5 / 0 — fully green** |
| drop `'.claude/*'` | **63** | **5 / 0 — fully green**, 62 files gone, **half the subject** |

**The redundancy example is true on this branch and false on Task 3's**, which is the point of
naming the tree rather than the point being wrong: anchoring the pathspec is exactly what turns a
redundant element into a contributing one. The Shape-2 conclusion is unaffected and gets *worse* on
the anchored tree — a floor of 30 over 125 sits there while a single element takes the set to 63.

So the floor never fires on a narrowing. **Both figures in this sentence are `task/n5-floors`'s**, the
first of the two tables above — this is the one place the tree-naming rule was not applied to its own
conclusion: at 30 over 143 it tolerates losing **113 of 143 files**, and the largest single-element
loss measured on this branch is 40 (`'tests/*.sh'`, 143 → 103), well inside that. On
`task/n3-pathspecs` @ `2f3293b` the same sentence reads 30 over **125**, **95** tolerated, largest
single-element loss **62** — a worse result from the same shape, which is why neither number travels
without its tree. It catches an emptied pathspec and
nothing short of it. The one red is incidental — dropping `tests/*.sh` removes the last file matching
citation shape D, so a *different, per-source* floor fires. That is F3 doing the work the threshold
could not, by accident rather than by design.

### Shape 3 — oracle mismatch. *The floor's oracle is not the guarded sweep's oracle.*

A floor derived from **`git ls-files`** guarding a sweep that reads files **from disk** measures a
different thing from what it certifies. The index survives a deleted or emptied working tree, so the
floor passes at full strength while the sweep opens nothing.

Not composition and not magnitude: the subject did not shrink and it did not lose a source — the
floor is looking at a *different subject*. Measured over a payload with **zero files under
`.claude/`**, all of these printed PASS:

| guard | what it printed while its files did not exist |
|---|---|
| `tests/test-citations-resolve.sh` | `citation sweep read 142 live surface file(s) (floor 30)` |
| `tests/test-mcp-naming.sh` | `the scan below has a payload to read` |
| `tests/test-mcp-doc-instructions.sh` | `the sweeps in this file have files to read` |
| `tests/test-help-ranges.sh` | `found 6 self-slicing usage() range(s) across 6 tracked script(s)` |

**The rule.** Derive the floor through **the same reader the guarded sweep uses**. If the sweep opens
files, the floor must count files it could open — `[ -f ]` per path, or a `find` over the same roots
— not index entries. Where the index really is the right oracle because the guard's subject *is* the
index (`tests/test-surface-references.sh`'s untracked-payload check is the honest case, and its own
comment says the rest of the file does not depend on git), say so at the floor, so the next reader
does not repair a mismatch that is not there.

**And the same trap has a second form, in the instrument this file recommends:** an identity between
two derivations that are not independent *of the failure being guarded against*. See F2 — the worked
example itself fails this way.

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
registers every hook file present in .claude/hooks"*: an identity between the `.claude/hooks/*.sh`
files less `_lib.sh`, and the distinct commands `jq` finds in `.claude/settings.json`. Currently
12 == 12.

An identity floor:

- **cannot be sized too low** — it is 100 % by construction;
- **cannot go stale** — it moves with the tree, so adding or cutting a hook keeps it correct with
  nobody editing a number;
- **detects narrowing**, which no threshold below 100 % does, because the other side does not move
  when one side shrinks.

`tests/run-tests.sh` uses the same instrument twice: the test-file glob against `find`, and the
number of files actually **run** against the number discovered. `tests/test-bash32-compat.sh` uses it
against its four scope-array lengths.

**INDEPENDENCE IS THE WHOLE REQUIREMENT, AND IT IS INDEPENDENCE *OF THE FAILURE BEING GUARDED
AGAINST*, NOT OF THE CODE PATH.** Two derivations can come from different commands, different files
and different parsers and still die together.

**The worked example above fails exactly this way, and the measurement is not hypothetical.** Over a
payload with zero files under `.claude/`, `find .claude/hooks` returns 0 and `jq` on a deleted
`settings.json` returns 0, so the floor prints **`PASS settings.json registers every hook file
present in .claude/hooks (0 present)`** — its own zero, in its own message — and the file falls from
**86 assertions to 2** while reporting green. The two sides are independent of *a mis-registration*,
which is what the floor was written for and which it does catch; they are not independent of *the
payload disappearing*.

`tests/test-skill-discovery.sh` names the same trap from the other direction: `FM_CHECKED == FM_DIRS`
is satisfied by `0 == 0` because `FM_CHECKED` counts the loop over `FM_DIRS`. That file adds
`FM_DIRS >= 1` **above** it in source order because the equality could not carry the weight — **and that is the general
repair. An identity needs an absolute floor on one side.** State which failure the identity is
independent of, and floor the side that can reach zero.

**What it costs otherwise.** A second derivation of the same quantity, which not every subject has.

**Where no independent derivation exists**, in order of preference:

1. **Bound the subject against a property of the guard's own source** rather than of the tree — an
   array length, a table's row count. The tree cannot move it, and it moves when the guard is
   edited. `tests/test-bash32-compat.sh` now compares its per-source census against the sum of its
   four scope-array lengths.
2. **Bound each source separately** (F3), which converts one loose threshold into k tight presence
   checks.
3. **Only then** a threshold — and size it against **the cheapest plausible narrowing**, not against
   zero. `tests/test-skill-discovery.sh`'s `S2S_CHECKED >= 5` is the model, and the arithmetic is
   the point: `S2S_REFS` is `sort -u`'d **before** the loop, so `S2S_CHECKED` is the count of
   **distinct** reference targets — **six** today, not the eleven raw references the sweep matches.
   Five is calibrated so that restricting the sweep to a single skill directory, which yields at most
   four distinct targets, trips it. Measured at `5881463`: removing one of the six leaves 5 and the
   file stays **16 pass / 0 fail**; removing two leaves 4 and this floor reds at **15 / 1**. That is
   a bound at **83 %** of its subject — the tightest non-identity floor in the tree — and it is what
   *"the cheapest plausible narrowing"* buys. *"Far above zero"* is not a calibration.

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

**A PARTITION AND AN OVERLAPPING COVER NEED DIFFERENT RULES, and all three examples above are
partitions.** The three worked examples have disjoint sources — four regex shapes, four globs, one
payload group — so "each source contributes" is unambiguous. A git **pathspec** is not a partition:
in `tests/test-citations-resolve.sh`, `'.claude/*'` and `'*.md'` both match `.claude/**/*.md`, and
**`'docs/*.md'` is wholly redundant — dropping it changes the scanned set by zero files** (143 →
143, measured). A naive per-source presence check over the union passes forever, because every
element's files are also somebody else's.

**The rule for an overlapping cover: attribute per element IN ISOLATION** — `git ls-files <element>`
run for that element alone, asserted non-empty — not membership of the union. That catches the
failure worth catching: an element whose pattern stopped matching anything. **It does not catch
redundancy**, and should not: on this branch `'docs/*.md'` matches **65** paths in the index (**7**
after the guard's own two `grep -v` filters) while adding **zero unique files** to the scanned set,
and that is legitimate belt-and-braces rather than a defect. **An earlier draft put 187 here, which
is `find docs -type f` — a different guard's subject, and the wrong oracle for a pathspec claim.
`git ls-files` is what the element is evaluated by, so `git ls-files` is what the number must come
from.** Say which of the two you are asserting; the difference is
invisible in the code and decides what the floor can see.

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

### F8 — a derived source list cannot see a deleted source

**A deleted directory is not a dead source. It is not a source.** If the census asks the tree *what
the sources are*, everything F3 buys is lost the moment a source is removed rather than emptied —
the loop simply has one fewer iteration and every remaining check passes.

Measured on this task's own first fix, which derived its source list with
`find .claude -maxdepth 1 -type d`. **That version of `tests/test-no-mobile.sh` was 17 / 0 pristine**
— one assertion fewer than the shipped file, because F8's declared half and F4's array floors were
not there yet — so these figures sum to 17 and the [Proof](#proof) table's sum to 18. They describe
different files and neither can be read against the other:

| tree state | verdict |
|---|---|
| `.claude/skills` **emptied**, directory kept | 16 / 1 — caught |
| `.claude/skills` **deleted** | **17 / 0 — not caught** |
| all five payload directories **deleted** (62 → 6 files) | **17 / 0 — not caught** |

`tests/test-bash32-compat.sh` was immune to the identical mutation (9 / 1) for one reason: **its
census iterates a fixed array and asks the tree about each entry, rather than asking the tree what
the entries are.**

**The rule: declare the sources, then derive on top.** The declared list makes deletion detectable —
a declared source that is not there reds by name. The derived half makes the list unable to go stale
— a new subdirectory becomes a source the day it lands. Neither half alone is enough, and each
covers the other's failure mode: a hand list cannot grow, a derived list cannot miss what is not
there. Both halves then need F4's absolute floor, because emptying either array removes the property
it was added for.

**TWO BOUNDARIES OF WHAT THIS BUYS, measured rather than assumed, because a rule whose limits are
unstated gets read as a guarantee:**

- **The predicate is presence-of-any-file, not presence-of-the-right-kind.** Delete every
  `SKILL.md` under `.claude/skills/` and leave one stray `NOTES.txt`: the directory exists, holds a
  file, and **neither half reds — 18 pass / 0 fail.** The census answers *"is anything there?"*; the
  guarded sweep cares about *"is the payload there?"*. Closing this means a per-source expectation
  of the file KIND, which is a hand-maintained list — the shape F8 exists to avoid — so it is
  stated rather than closed. `tests/test-derived-counts.sh` and `tests/test-skill-discovery.sh` are
  what actually watch skill population; this floor is not their substitute.
- **F4's `>= 1` cannot see a declared list SHRINK.** Remove `.claude/skills` from `PAYLOAD_DIRS` and
  delete the directory: the array is still non-empty, the derived half never had the source, and the
  file reports **18 pass / 0 fail** — the F8 hole reopened by an edit to the very array that closes
  it. The honest guard for this is an identity against something outside the file, and there is
  none; **F4 bounds an array against zero, not against yesterday.**

---

## The floor set

The tables below carry **83 rows**, one per BOUND. **Three of those rows restate a bound another row
already carries**, so: **at least 80 distinct bounds** meet the criterion in the current tree. **This
is a lower bound and is written as one deliberately** — the count has now been wrong three times, and
a fourth confident total would be the artifact repeating its own subject's defect.

The three restatements, each identified by reading the assertion rather than the wording:
`test-bash32-compat.sh`'s and `test-no-mobile.sh`'s per-source census identities, each listed under
*Converted* and again under *Identity floors*; and `DCE_VACUOUS`, listed under *Sites* and again
inside the six-accumulator row under *Presence floors*. A fourth,
`test-pipeline-detector.sh`'s empty-index arm, was listed under *Sites* **and** *Presence floors*
until 2026-08-14 and is now one row.

**That is a count of bounds, and not of assertion sites.** This line read *"at least 83 assertion
sites"* until 2026-08-14: 83 is the row count, stated in the unit the *"one row per BOUND"* ruling
below explicitly forbids — the section warning that rows are not sites opened by counting rows and
calling them sites. It then read *"at least 81 distinct bounds"* for one round, from a restatement
set of two that was really four. Rows and sites diverge in **both** directions here (five rows are
two `assert_eq` calls in `tests/test-no-mobile.sh`; one row is the six `_VACUOUS` accumulators), so
no site total is written down. Deriving one means reading every row's assertion, which nobody has
done.

- The wave carried **~28**. A first derivation under C1–C4 gave **68**. A reviewer sweeping the same
  criterion found **fifteen more** that all four clauses admit, and the sweep is not exhaustive.
- The 68 was low for two reasons, both mine. **C2's mechanism space was too narrow**: it had no
  clause for *"the derivation itself failed"* (`git ls-files` returning non-zero, treated as an empty
  subject) or for *"the fixture the guarded assertions need is absent"*. Those are clauses (f) and
  (g) now, and they are where most of the fifteen live. **And whole scope segments were never
  swept** — the declared scope names `scripts/*.sh`, `install.sh`, `uninstall.sh` and
  `.claude/hooks/*.sh`, and the first table had zero rows from any of them.
  `scripts/check-provenance.sh` — the file the second gate of every task in this wave runs — carries
  a floor, and it was missed. **The other three have since been run through C1–C4 and hold none**;
  the grounds are under *Scope* above. Zero rows from a segment now means *swept and empty*, and it
  says which — for one round it meant neither, and a reader could not tell the two apart.
- The ~28 was low for a different reason: a window scan with no written criterion, which had already
  lost 14 members to an `awk` `getline` window and looked complete.

**Re-derive rather than trusting the number.** Enumerate C2's clauses (a)–(g) over every file in the
scope; **build the window from an array, never with `getline`**; and key C3 by **propagating the
sentinel variable to wherever it is asserted**, not by proximity — a proximity-keyed reach missed
`tests/test-derived-counts.sh`'s `-lt 1` accumulators, whose assertion is sixty lines away, and every
identity floor, which carries no bound at all.

Ratio = the smallest subject that still passes, over the subject today. **Survives** = does the floor
still pass after the subject loses a whole source (Shape 1) or most of its magnitude (Shape 2)?

**The table has one row per BOUND, not one per site.** Where one assertion carries several bounds
they are listed separately because each is a different claim about a different subject. Reading the
table as a census of sites will **overcount** — and, in one row, undercount. The **five**
`test-no-mobile.sh` rows (four under *Converted*, one repeated under *Identity floors*) are **two**
sites: one `assert_eq` on `SCAN_STATE`, one on the census identity. The four
`test-bash32-compat.sh` census rows — three under *Converted*, one repeated under *Identity floors* —
are three. A third bound is restated across tables in different words: `DCE_VACUOUS` under *Sites*
is one of the six accumulators under *Presence floors*, and is marked in its own row as cross-listed.
Corrected from an earlier draft that got this exactly backwards: the four
`test-bash-gate-precision.sh` rows are **four independent `assert_eq` calls, four sites.** And in the
other direction, the `_VACUOUS` accumulators are **six** sites in **one** row — not five, and not
one.

**RUN THE DEDUP. It takes five seconds and it has already caught a duplicate this paragraph missed:**

```bash
awk '/^## The floor set/{f=1;next} /^## Proof/{f=0} f && /^\| `/{split($0,a,"|"); k=a[2]; gsub(/^ +| +$/,"",k); print k}' \
  docs/ANTI-VACUITY.md | sed 's|`tests/|`|' | sort | uniq -d
```

**The `sed` is load-bearing.** The *Sites* table writes `tests/test-pipeline-detector.sh` while every
other table writes the bare basename, and on the raw column that one inconsistency hid a bound listed
in two tables under a **verbatim-identical** anchor — through three rounds and four reviews. Today
the command returns **one** line, the `same assertion, array floor (F4)` pair, and that pair is
**not** a repeat: one site, two different bounds (`SCAN_DIRS`, `PAYLOAD_DIRS`), the rule working as
intended.

What the dedup cannot see is a bound restated in *different words*, which is the other two.
**That is a reason to run it and then read, not a reason to skip it** — and this paragraph said
*"a textual dedup will not find them"* for exactly one round, which is advice to skip the only cheap
check available, written in the sentence where running it would have found the duplicate the
paragraph did not know it had. Do not accept a table's own account of its coverage as the coverage
measurement; that rule is in this repository's ledger and it applies to this table.

**Subject sizes are dated 2026-08-14, derived IN A CLEAN CLONE, and drift.** Two of them moved by one
at `4578854`, the commit that shipped this file, because `docs/ANTI-VACUITY.md` is itself matched by
`'docs/*.md'` and by `'docs/*'`: `test-citations-resolve.sh`'s `LIVE_N` went **142 → 143** and
`test-mcp-naming.sh`'s pathspec count went **82 → 83**. Both are named because for one round only the
first was updated — the sentence warning about the hazard shipped an instance of it, in the row of
the guard whose pathspec contains `'docs/*'`. The floor-set *derivation* is out of its own scope by
construction; the ratio table's *subject sizes* are not, and cannot be.

**"Clean clone" is load-bearing, and `git status` will not tell you.** The `test-no-mobile.sh` census
row shipped `.claude/state=2` and `.claude=63` for one round. Both were measurements of a **dirty
working tree**: `.claude/state/session-edits.txt`, written by the `track-edits` hook during this
task's own probe runs. `.gitignore` carries `.claude/state/*`, so
`git status --porcelain --untracked-files=all` printed **nothing** and the tree looked pristine. A
clean clone of the same commit gives `.claude/state=1`, `.claude=62`. **Any number in this table that
comes from `find` rather than `git ls-files` must be re-derived in a fresh clone**, because the
guards read the working tree and the working tree is where a gitignored artefact hides.

### Converted or added by this pass

| Guard · assertion anchor | Subject | Bound | Today | Ratio | Survives |
|---|---|---|---|---|---|
| `test-no-mobile.sh` · *every mobile-sweep source has files in it* | 11 sources: 5 scan roots + 6 **declared** payload dirs, unioned with whatever `find .claude` adds | ≥ 1 **each**, and each must EXIST (F8) | 62/8/9/13/6/20/1/187/4/8/10 | 100 % per source | **no** |
| `test-no-mobile.sh` · same assertion, array floor (F4) | `SCAN_DIRS` itself | ≥ 1 | 5 | — | no |
| `test-no-mobile.sh` · same assertion, array floor (F4) | `PAYLOAD_DIRS` itself — the declared half, without which F8 stops working | ≥ 1 | 6 | — | no |
| `test-no-mobile.sh` · *the per-source loop read every source the derivation produced* | census rows written vs. sources derived | **identity** | 11 == 11 | 100 % | no |
| `test-bash32-compat.sh` · *every source of both sweeps resolves to at least one file* | 9 sources across two scopes | ≥ 1 **each** | 13/7/40/1/1 + 13/7/1/1 | 100 % per source | **no** |
| `test-bash32-compat.sh` · *the per-source census covered every declared scope entry* | census rows vs. four array lengths | **identity** | 9 == 9 | 100 % | no |
| `test-bash32-compat.sh` · *all four scope arrays are non-empty* (F4) | the four arrays | ≥ 1 each | 3/2/2/2 | — | no |
| `test-derived-counts.sh` · *every hook-count claim row matches exactly one site* (F6) | sites per claim row | **== 1** | 20 rows | 100 % | no |
| `test-derived-counts.sh` · *every surface-count claim row matches exactly one site* | sites per claim row | == 1 | 15 rows | 100 % | no |
| `test-derived-counts.sh` · *every ECU-footprint claim row matches exactly one site* | sites per claim row | == 1 | 8 rows | 100 % | no |

**What they replaced:** `SCAN_FILES >= 1` over **271** files from 5 roots (**0.4 %**, survived losing 5
of 6 payload directories) and `SS_ALL_N > 0` / `SS_PIPE_N > 0` over 62 and 22 files from 5 and 4
sources (**1.6 % / 4.5 %**, survived losing `.claude/hooks/` entirely).

### Identity floors — no ratio, and that is the point

| Guard · assertion anchor | The two derivations | Today |
|---|---|---|
| `test-hook-behaviour.sh` · *settings.json registers every hook file present in .claude/hooks* | `.claude/hooks/*.sh` less `_lib.sh` **vs** distinct commands in `settings.json` | 12 == 12 |
| `run-tests.sh` · *Test discovery is inconsistent* | the `test-*.sh` glob **vs** `find -type f -name 'test-*.sh'` | 39 == 39 |
| `run-tests.sh` · *ran N test files but M match* | files actually executed **vs** files discovered | 39 == 39 |
| `test-bash32-compat.sh` · per-source census | census rows **vs** four array lengths | 9 == 9 |
| `test-no-mobile.sh` · per-source census | census rows written **vs** sources the derivation produced | 11 == 11 |

### Numeric thresholds — every one implies a ratio

| Guard · assertion anchor | Subject | Bound | Today | Ratio | Survives |
|---|---|---|---|---|---|
| `test-citations-resolve.sh` · *citation sweep read N live surface file(s)* | files from a 9-element **overlapping** git pathspec | ≥ 30 | **143** | **21 %** | **yes — all three shapes.** Drop `'.claude/*'` → 125, green. Oracle is the index, sweep reads disk. |
| `test-citations-resolve.sh` · *all four citation shapes matched* | four regex sweeps | ≥ 1 **each** | 31/11/34/2 | per source | no |
| `test-citations-resolve.sh` · *resolved N live citation(s)* | citations reaching the resolver | ≥ 10 | 26 | 38 % | yes |
| `test-shipped-citations.sh` · *guard scanned N shipped .md files* | `.md` under `.claude/` | ≥ 35 | 44 | 80 % | yes |
| `test-shipped-citations.sh` · *payload derivation produced N entries* | install.sh's payload groups | ≥ 55 | 67 | 82 % | **yes — a whole group can die** |
| `test-shipped-citations.sh` · *payload carries N .claude/scripts/ entries* | one group of the above | ≥ 1 | 6 | 17 % | no *(the per-source refinement of the row above)* |
| `test-shipped-citations.sh` · *guard examined N backticked tokens* | tokens in shipped `.md` | ≥ 200 | 779 | **26 %** | yes |
| `test-shipped-citations.sh` · *guard examined N .claude/scripts/ path reference(s)* | script references in surfaces | ≥ 6 | 9 | 67 % | yes |
| `test-shipped-citations.sh` · *rule 4 derived the project-root installed set* | receipt-row formats in `install.sh` | ≥ 2 | 4 | **50 %** | yes |
| `test-shipped-citations.sh` · *rule 4 examined N repository path(s)* | paths named in `.claude/UPSTREAM` | ≥ 1 | 5 | **20 %** | yes |
| `test-mcp-naming.sh` · *the scan below has a payload to read* | 9-element git pathspec (one element is `'docs/*'`, which matches this file) | ≥ 40 | **83** | **48 %** | **yes — one element can die** |
| `test-mcp-doc-instructions.sh` · *the sweeps in this file have files to read* | tracked paths under `.claude/` | ≥ 30 | 62 | 48 % | yes |
| `test-surface-references.sh` · *git can read this repository's index* | tracked paths under `.claude/` | ≥ 30 | 62 | 48 % | yes |
| `test-surface-references.sh` · *the absence check read N .md files* | `.md` under `.claude/` | ≥ 35 | 44 | 80 % | yes |
| `test-surface-references.sh` · *the same scan finds the surviving phrase* | files stating the surviving phrase | ≥ 2 | 3 | 67 % | yes |
| `test-surface-references.sh` · *every agent still has a Skills to load block* | per agent file | ≥ 1 **each** | 8 agents | per source | no |
| `test-provenance-origins.sh` · *derived N retired hook/script path(s)* | `rule=absent` rows | ≥ 15 | 19 | 79 % | yes |
| `test-provenance-origins.sh` · *every glob in the dead-name scan returned a plausible number* | 4 globs | ≥ 60 / ≥ 5 / ≥ 4 / == 1 | 62/8/**7**/1 | **97 % / 63 % / 57 % / 100 %** | per source — no |
| `test-provenance-origins.sh` · *the manifest yields N Superpowers-adapted surfaces* | two derivation routes | ≥ 3 | 3 | 100 % | no |
| `test-skill-discovery.sh` · *the skill->skill sweep still reads the chain* | skill->skill references, **deduplicated**: `S2S_REFS` is `sort -u`'d before the loop, so `S2S_CHECKED` counts distinct targets | ≥ 5 | **6** (from 11 raw references) | **83 %** | **no — losing one leaves 5 and stays green, losing two reds it** |
| `test-skill-discovery.sh` · *there are skills to check* | skill directories | ≥ 1 | 16 | **6 %** | yes |
| `test-skills.sh` · *the skill walk found skills to check* | `SKILL.md` files | ≥ 1 | 16 | **6 %** | yes |
| `test-hooks.sh` · *the kill-switch sweep found hook files to read* | hook files | ≥ 1 | 12 | **8 %** | yes |
| `test-hooks.sh` · *session-brief prints the brief with no switch set* | output lines | ≥ 1 | 49 | **2 %** | yes |
| `test-cross-validation.sh` · *the hook registrations were actually extracted* | `jq` commands from `settings.json` | ≥ 8 | 12 | 67 % | yes |
| `test-stack-arbitration.sh` · *the guard examined a plausible number of stack-naming surfaces* | surfaces naming the stack | ≥ 10 | 21 | 48 % | yes |
| `test-help-ranges.sh` · *found N self-slicing usage() range(s)* | ranges in tracked scripts | > 0 | 6 | **17 %** | yes |
| `test-help-ranges.sh` · *every self-slicing script carries a literal line range* | the coarse needle's hits | > 0 | 6 | 17 % | yes |
| `test-bash-gate-precision.sh` · *the corpus is not empty* | corpus payloads | > 0 | 331 | **0.3 %** | yes |
| `test-bash-gate-precision.sh` · *…contains payloads that must be blocked* | blocking payloads | > 0 | **216** | 0.5 % | no *(per source)* |
| `test-bash-gate-precision.sh` · *…contains payloads that must be permitted* | permitting payloads | > 0 | **115** | 0.9 % | no *(per source)* |
| `test-bash-gate-precision.sh` · *…payloads an earlier hook version blocked* | historically-blocked payloads still expected to block | > 0 | **170** (of 219 carrying a historic block) | 0.6 % | no *(per source)* |
| `test-install-ownership.sh` · *H.3: the run announced N kept file(s)* | announced kept paths | > 0 | 2 | 50 % | no |
| `test-install-ownership.sh` · *K: install 1's CLAUDE.md.generated carries the FILL: markers* | `FILL:` markers | > 0 | **9** | 11 % | no |
| `test-install-ownership.sh` · *L: the run wrote N file(s) under .claude/* | files installed before the stop | > 0 | 67 | **1.5 %** | yes |
| `test-install-dryrun.sh` · *dirty: the foreign .claude/ holds N user file(s)* | fixture files | ≥ 2 | 2 | 100 % | no |
| `run-tests.sh` · *No test files found* | discovered test files | ≥ 1 | 39 | **2.6 %** | yes |
| `run-tests.sh` · *ran a python suite that discovered 0 tests* | python results | > 0 | 1444 | **0.07 %** | yes |
| `test-derived-counts.sh` · *the surface counts are derived from a tree that actually has surfaces* | agents / commands / skills | ≥ 1 **each** | 8/9/16 | 13 % / 11 % / 6 % | per source — no |
| `test-derived-counts.sh` · *the hook and script counts are derived from a tree that actually has hooks and scripts* | hooks / registrations / scripts / skipped | ≥ 1 / ≥ 1 / ≥ 1 / == 1 | 12/12/7/1 | 8 % / 8 % / 14 % / 100 % | per source — no |

### Sites the first derivation missed — C2 clauses (f) and (g), and the unswept scope segments

These meet C1-C4 and were absent from the first table. Each either self-declares C4 in its own
failure message (*"every assertion below is vacuous"*, *"its silence above means nothing"*, *"the
sweep read nothing"*) or is a live counted assertion verified in the suite log. **Their common
feature is that the first scan's C2 had no clause for them.**

| Guard · assertion anchor | Subject | Mechanism | Today |
|---|---|---|---|
| `scripts/check-provenance.sh` · *the tracked-file index is readable* | `git ls-files` against the manifest's own row count | (a) + (f), **relative to the manifest** — the one floor in the whole `scripts/` segment | 544 tracked vs 544 rows, bound `>= rows/2` (**50 %** — half the manifest may vanish) |
| `tests/test-provenance-origins.sh` · *the dead-name scan's file list came from a readable git index* | the scan's tracked-file list | (f) | rc == 0 |
| `tests/test-provenance-origins.sh` · *the dead-name scan read its sentinel* | one assertion per named sentinel | (b), **per source** | 6 live PASS lines |
| `tests/test-provenance-origins.sh` · *check-provenance.sh reads the ECU pin* | the key the two assertions below describe | (b) | present |
| `tests/test-help-ranges.sh` · *this file's entire input set comes from git, and it could not be read* | tracked `*.sh` | (f) + (a) | rc == 0, count > 0 |
| `tests/test-pipeline-detector.sh` · *could not list tracked files under the roots* | the sweep's file list | (f) | `SWEEP_RC_NO_INDEX` |
| `tests/test-pipeline-detector.sh` · *git tracks no files at all under the roots* | the same list, empty | (a) | `SWEEP_RC_EMPTY_INDEX` |
| `tests/test-pipeline-detector.sh` · *the sweep for '$needle' exited N instead of searching* | the same sweep, broken rather than empty | **(f)** | `SWEEP_RC >= 2` — **added 2026-08-14; no row in any table before** |
| `tests/test-install-dryrun.sh` · *withmcp: the real run kept no backup — oracle 1's subject is absent* | a run-produced backup file | **(g)** | present |
| `tests/test-install-dryrun.sh` · *mcpthen: the backup is gone after the flagless run* | the same, second arm | **(g)** | present |
| `tests/test-install-not-done.sh` · *B.0: a clean install printed the block* | the negative control | **(g)** | absent |
| `tests/test-install-not-done.sh` · *B.9: the extra agent never landed, so install 2 has no orphan* | a fixture the arm needs | **(g)** | present |
| `tests/test-install-ownership.sh` · *F: git does not track the manifest* | the fixture's git state | **(g)** | tracked |
| `tests/test-install-ownership.sh` · *L: the fixture has no manifest* | the fixture | **(g)** | present |
| `tests/test-install-ownership.sh` · *install 1 did not produce exactly one marker pair* | the thing the mutation damages | **(g)** + (a) | == 1 |
| `tests/test-derived-counts.sh` · `DCE_VACUOUS` | ECU-survival phrasing, per quoting file | (a) | 3 files — **cross-listed**: one of the six `_VACUOUS` accumulators tabled under *Presence floors*. Kept in both because this table records what the first sweep missed and that one records the set; **counted once** |

**And the residual this row set exposes**: `scripts/check-provenance.sh`'s `ENFORCED` counter — the
number of `rule=absent` entries it enforces — has **no floor**. An unreadable or reshaped
`provenance-skip.tsv` yields `ENFORCED=0`, `CREPT=0`, and the script prints
`pass no prohibited path present (0 rule=absent entries enforced)`. The zero is in the message, as it
was in the worked example's. Not fixed here; it is the second gate of every task in this wave.

### Presence floors — no ratio, 100 % by construction

| Guard · assertion anchor | Subject |
|---|---|
| `test-derived-counts.sh` · *still carries a readable kinglet:minimal-drops region* | the marked region in `docs/HOOK-REFERENCE.md` |
| `test-derived-counts.sh` · *still carries a readable kinglet:minimal-keeps region* | the complement region |
| `test-derived-counts.sh` · *still has readable per-hook Profile lines* | the twelve `- **Profile:**` lines |
| `test-derived-counts.sh` · *still has a readable hook Summary Table* | the table's profile column |
| `test-derived-counts.sh` · *still has a readable Tracking Files writer column* | `docs/ARCHITECTURE.md`'s writer column |
| `test-derived-counts.sh` · *still has a readable Event Types table* | `docs/ARCHITECTURE.md`'s event table |
| `test-derived-counts.sh` · the **six** `…_VACUOUS` accumulators (`DC_PAIR`, `DC`, `DCF`, `DCE`, `DCS`, `DCK`) | one per claim row / quoting file — **this is where the F6 union lived**. An earlier draft said five. |
| `test-hook-behaviour.sh` · *probe for X carries a non-empty needle* | the needle, per hook — **see F5 for what this predicate does not cover** |
| `test-provenance-origins.sh` · *carries exactly one 40-hex pin* | the ECU pin in `provenance.tsv` |
| `test-stack-arbitration.sh` · *the generator still emits the block every surface now points at* | the heading in `scripts/generate-claude-md.sh` |
| `test-surface-references.sh` · *every .md the absence check opened flattened to something* | per file |
| `run-tests.sh` · *started a python suite that never printed an OK/FAILED outcome* | the suite's outcome line |

`tests/test-pipeline-detector.sh` · *git tracks no files at all under the roots* **was a fourteenth
row here and is deleted, not moved**: it is the same bound as the row of that name in *Sites the
first derivation missed*, set by the one `[ ! -s "$SWEEP_LIST" ]` in the file. The Sites row is kept
because it carries the mechanism clause and the sentinel name, and because that guard's other two
arms live beside it — splitting one arm of a three-arm block into a different table is what made two
rows look like two bounds for three rounds, and is why the third arm's absence went unnoticed.

---

## Proof

Every floor changed or added here was mutated in **at least two differently shaped ways**, each
mutant `cmp`'d against the original, checked for its injected marker, **and had its mutated line read
back**, with an explicit `MUTANT DID NOT APPLY` when any of the three failed. The payload was emptied
in a `git clone --no-hardlinks --shared`, never a `cp -a` — a `.git` *file* pointing back at the real
repository once cost a reviewer 15 spurious failures.

**The read-back is not ceremony, and this round is why.** Two mutants in the F8 battery passed `cmp`
*and* carried their marker *and* were still wrong:

- an early-`break` injected after the **unreachable** branch's counter rather than the reachable
  one. The mutant applied, the file differed, the marker was present — and the guard reported
  **18 / 0**, which reads exactly like a floor that failed to catch it. Only reading the line back
  and looking at its three predecessors showed the `break` sat in a branch that never runs.
- the same mutation written with `perl -0pi -e 's/…/…$SCAN_ROWS…/'`, where perl interpolated the
  shell variable and shipped `[ "" -lt 2 ]`. It broke on the first iteration by accident and the
  floor red — *for the wrong reason*. `cmp` differed; the marker was present; the read-back showed
  `[ "" -lt 2 ]`.

**An unapplied mutant makes a hollow guard look sound; an inert or malformed one makes a sound guard
look hollow, or right for the wrong reason.** Both were caught by reading the line.

| Mutation | `test-no-mobile.sh` | `test-bash32-compat.sh` |
|---|---|---|
| pristine | 18 pass / 0 fail | 10 pass / 0 fail |
| **payload fully emptied** (0 files under `.claude/`) | **17 / 1** — names all 7 dead sources | **9 / 1** — names both dead `hooks` rows |
| `.claude/skills/` emptied **only** | **17 / 1** — names `skills` | 10 / 0 — *correctly out of scope* |
| `.claude/hooks/` emptied **only** | **17 / 1** — names `hooks` | **9 / 1** — names `hooks` in both scopes |
| **`.claude/skills/` DELETED** (F8) | **17 / 1** — `skills=GONE` *(17 / 0 before F8)* | 10 / 0 — out of scope |
| **all five payload dirs DELETED**, 62 → 6 files (F8) | **17 / 1** — names all five *(17 / 0 before F8)* | **9 / 1** |
| **`.claude/hooks/` DELETED** (F8) | **17 / 1** — `hooks=GONE` | **9 / 1** |
| scope array emptied (F4) | **17 / 1** — `SCAN_DIRS` floor *(17 / 0 before it existed)* | **9 / 1** — the four-arrays floor |
| `PAYLOAD_DIRS` emptied (F4, the declared half) | **17 / 1** | — |
| `PAYLOAD_DIRS` emptied **and** `skills` deleted | **17 / 1** — F4 fires before the hole reopens | — |
| per-source loop stops after 2 sources | **17 / 1** — the census identity, `11 derived, 2 censused` | — |
| census derivation silenced | — | **9 / 1** — the identity floor alone |
| a scope directory repointed at a path that does not exist | — | **9 / 1** — the per-source floor alone |

Each mutation reds **one** assertion and leaves the rest passing. A mutation that reds everything has
isolated nothing.

**Every row therefore sums to its pristine total — 18 and 10 — and that arithmetic is the cheapest
check this table has.** The three emptied rows read `16 / 1` and `8 / 1` until 2026-08-14. They were
correct when written and went stale at `2df8b92`, the commit that raised the pristine row from
`17 / 0` and `9 / 0` to `18 / 0` and `10 / 0`: F8's declared half and F4's array floors each added
one assertion to each file, every other row was re-measured, and these three were not. Their totals
then stood at 17 and 9 against a stated pristine of 18 and 10 — **the table contradicted its own
first row on its face**, and two rounds of review read past it. All thirteen rows were re-run at
`5881463`, one fresh `git clone --no-hardlinks --shared` per mutant.

**Keep the mutant's backup copy of the file OUTSIDE the clone.** `SCAN_DIRS=()` leaves
`grep -rnE "$MOBILE_CS"` with no path operand, and GNU `grep -r` then searches the working directory
— so a `.bak` beside the tree was swept as payload and turned a true `17 / 1` into a `16 / 2` whose
second failure was the harness. It looked exactly like a real second finding.

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
  tolerates a narrowing nobody would notice. **This used to say "converting them to identities needs
  a second independent derivation per subject, and most do not have one." That sentence is false for
  the very subject it was written about** — see the routed follow-up below, which is what F2's
  fallback ladder produces when it is actually walked.
- **Shape 3 is documented, not fixed.** Four guards floor on `git ls-files` and sweep from disk. Each
  needs its floor re-derived through the reader the sweep uses; none of the four is in this task's
  range.
- **Growing the covered set is still manual.** A guard added without a floor is caught by nothing
  here; there is no check that every sweep has one.
- **The count is a lower bound**, for the reasons stated at the head of the floor set. Treat any
  total here as the largest set anyone has yet derived, not as the set.
- **`docs/` is not in the derivation's scope**, correctly — a Markdown file cannot fail C3 — but the
  ratio table's **subject sizes are read from the tree**, and two of them moved by one on the commit
  that shipped this file. Dated, and anchored by text rather than line number, so a reader
  re-derives.
- **`tests/test-templates.sh` and `tests/test-install.sh` have no floor, and the earlier version of
  this bullet described their consequences wrongly in both directions.** Measured:
  - `tests/test-templates.sh` with `templates/` emptied does **not** pass — it **dies**:
    `grep: …/templates/*.cs.template: No such file or directory`, **0 pass / 0 fail, rc 2**, and the
    runner's *"exited 2 without reporting a failure"* backstop reds it. The floor is genuinely
    missing; the *outcome* is loud rather than silent, which is the opposite of what was written.
  - `tests/test-install.sh` with `.claude/hooks/` emptied answers that check with `skip_test` — true
    of the check, misleading about the file, which reports **21 pass / 2 fail** and reds on other
    grounds. A skip is still not a floor: a suite counts it as neither pass nor fail.

---

## Routed follow-up: a floor for `tests/test-citations-resolve.sh`'s pathspec

**Owner: the task that owns `tests/test-citations-resolve.sh`** — Task 3 of the
`unmeasured-surfaces` wave, which is anchoring that file's pathspecs and is the only task permitted
to edit it. Not *"whoever next opens the file"*: a deferral routed to a role is a deletion with a
paper trail, and a row in a reference table is not even a role. This is written out so it can be
lifted into the ledger verbatim.

**The defect, measured ON TASK 3'S OWN TREE** (`task/n3-pathspecs` @ `2f3293b`), because that is the
tree the repair lands in and the anchoring has already moved every figure: `LIVE_N >= 30` over
**125** files from a nine-element pathspec fails all three shapes at once — composition (one element
can die), magnitude (**95 of 125** files can go), and oracle mismatch (the floor counts index
entries; the sweep opens files). Dropping `'.claude/*'` takes the set to **63** — half the subject —
and the file stays **5 pass / 0 fail**. On this branch the same drop gives 125 of 143; the shape is
identical and only the arithmetic differs, which is why each figure names its tree.

**The repair, and it needs no new tree property.** F2's fallback step 1 — *bound the subject against
a property of the guard's own source* — applies directly, and there is a working reference
implementation in `tests/test-bash32-compat.sh`, at the assertion reading *"the per-source census covered every declared scope entry"* (`SS_ROWS == SS_EXPECTED_ROWS`,
census rows against the sum of four array lengths). Lift the pathspec into an array, then:

1. **per element in isolation** (F3, overlapping-cover rule): `git ls-files <element>` for each
   element alone, asserted non-empty — this catches an element whose pattern stopped matching, which
   is the failure worth catching, and does **not** flag a redundant element, which is legitimate.
   Note that anchoring has *reduced* the redundancy: `'docs/*.md'` contributed 0 unique files before
   it and 6 after, so this check has more to bite on than it did;
2. **identity**: elements contributing == `${#PATHSPEC[@]}`, so an element deleted from the array
   reds rather than silently narrowing the scope;
3. **F4**: an absolute `${#PATHSPEC[@]} >= 1`, because both checks above are relative to an array
   that a mutation can empty;
4. **F2's independence clause**: the identity is independent of a *broken pattern* and not of *a
   missing index*, so the existing `LIVE_N` bound stays as the absolute floor on that side.

Shape 3 remains open for that file after this repair — every element is still counted through
`git ls-files` — and should be recorded as such rather than assumed closed.
