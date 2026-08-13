# Fix-loop re-review dispatch

One dispatch per round of the fix loop, after the implementer reports it has addressed the review's
Critical/Important findings. Scoped — this is not a second `task-reviewer-prompt.md` pass.

## What the re-review covers

1. **Verdict each open finding: ADDRESSED or NOT ADDRESSED, with evidence for each.** List the
   findings from the previous review verbatim, one by one. "Evidence" means a specific thing the
   reviewer checked — a line in the new diff, an experiment run, an output read — not "looks fixed."
2. **Flag new breakage introduced by the fix diff only.** The re-review is not a license to re-audit
   the whole task from scratch — that already happened once. Scope to what the fix round actually
   changed; a new Critical found here should be something the fix itself introduced, not something
   the first review missed and this round happens to notice.
3. **Send anything out of scope to the ledger, not into another round.** An observation that is real
   but is not one of the open findings and is not new breakage does not extend the loop — it goes to
   the ledger as a deferred item. Scope creep in the fix loop is how three rounds becomes six.

## The instruction that made the difference

**Where a fix claims a guard now works, prove it by experiment, using a probe shape the implementer
did not use.** Reading the corrected code and agreeing it looks right is not verification — it is a
second person's confidence, not a second data point. Repeating the implementer's own probe proves
only that their probe passes; a probe shaped differently is what catches a fix that patches the
specific case that was reported rather than the class of case the finding named. This is the same
failure this repository has already seen from the other direction: a guard rescoped from a substring
match to a path match still needs testing against an input the *original* bug report didn't use,
because a fix that only satisfies the reported input is a fix for one symptom, not the defect.

Concretely: if the finding was "this check passes when the tree is dirty," do not re-run the exact
dirty-tree scenario from the original finding — construct a different dirty state (staged-but-
uncommitted, untracked-but-present, modified-but-unstaged) and confirm the guard catches that one too.
If it doesn't, the finding is NOT ADDRESSED even though the reported case now passes.

## A claim you verified by reading is not verified — mutate it

**Required, not suggested, for every claim this round asserts a guard now covers.** Falsify the
claim — edit the thing the guard is supposed to catch into something wrong — run the gate, and read
the result. If the gate stays green, the claim is unguarded, and **that is the finding**, not a
footnote to one. Restore the mutation before you write your verdict, and say in the verdict what you
mutated and what the gate did.

This is the cheapest instrument a reviewer has and the one with the best record here: of thirteen
findings in one whole-task audit, four were settled by mutation in minutes, and every time the answer
was that the suite did not care. Each of those four was introduced by a round whose own review had
read the guard and agreed with it. A per-round review that mutated would have caught them at the
round that wrote them.

**A green gate carries no information until you know the mutant applied — and the failure runs both
ways.** If the text you meant to break was already gone, or your edit missed by a character, the gate
is green because nothing changed. That green is indistinguishable from a hollow guard, so the
reviewer files a finding that does not exist and a round gets dispatched after it; and it is equally
indistinguishable from a guard doing its job, so a real hole survives. **So the instruction is not
"check that your mutation applied."** It is: `cmp` the mutated file against the original, confirm the
marker you injected is actually present in it, and emit an explicit `MUTANT DID NOT APPLY` when it is
not. A zero is not evidence until you know which zero it is.

Measured three times in one wave, the third by a reviewer in the act of verifying someone else's
work — which is the instance worth remembering, because nobody involved had a stake in the answer. It
mutated with `perl -pi -e` and no `/g`. The first occurrence of the target string was in a **comment**
and the code occurrence was the second, so the edit landed in the comment, the code was untouched,
and the guard file it was attacking reported a clean 325 pass / 0 fail. Read straight, that is
*"this guard is hollow"* — a Critical finding, entirely fictional. It caught it only because the
implementer it was reviewing had established the habit and it copied it: assert the injection is
present before measuring anything.

**A third way, and it kills a real finding rather than inventing one: the mutation is not the shape
the finding measured.** A finding recorded as `3 pass / 2 fail → 5 pass / 0 fail` reproduces as
`3/2 → 4/1` under a **replacement** violation, because a replacement is visible from both directions
and the second assertion still reds; the reported figure needs a violation isolated to the one sweep.
A reviewer handed the wrong shape concludes the finding evaporated.

## When the round names a class, re-derive the class

A report that says "five stale counts", "every reference to X", "all the call sites" is asserting a
**membership**, and the finding list in front of you is that assertion's output, not its input.
Checking the five edits is not checking the class. **Derive the membership yourself, from the
criterion, and diff your set against the round's.**

Measured twice in one wave. A round announced five stale counts and fixed three files — including one
of two parallel justifications written the same day for the same reason — and the review verified the
five edits while the sixth member shipped stale. Then a ruling in the same wave named "nine files,
not two"; a re-derivation established that those nine were the set a *different* criterion selects,
disjoint from the class the ruling's own decisive measurement was about. An implementer re-deriving
by that proxy would have fixed the wrong nine and reported success, because all nine behave
afterwards.

**Write down what is being counted before you count it.** One quantity in one file was reported as
10, 11 and 12 by three careful readers, and settled at 11 direct and 6 indirect only once someone
stated the criterion — the 10 came from a pattern that did not join backslash continuations. A class
with no written criterion has no membership, and two readers who agree on a number have agreed by
accident.

## Do not accept a guard's own coverage list as the coverage measurement

Where the round added or repaired a guard, the guard usually arrives with prose about what it covers,
and sometimes with a list of what it cannot see. **Both were written by the same commit as the guard,
so a review that finds them consistent with each other has measured nothing about the world.**

Derive the covered set mechanically instead — search the tree for the *shape* being guarded, every
column of that table, every field line of that entry — and diff it against what the guard actually
reads. Where a guard carries a hand-maintained list of names, adding a thing to the tree and adding
it to that list must be the same commit, or the list is an assertion that decays silently. Measured:
one wave retired 19 surfaces and extended the relevant list by zero, and the guard stayed green the
whole time. Measured again, on a payload skill: a round added a section, and its own reviewer found
that deleting that section — or replacing it with prose asserting the opposite of what it rules —
left the suite fully green. The absence that made the insertion invisible is the same absence that
leaves it unguarded.

## Output

The same finding list, each marked ADDRESSED or NOT ADDRESSED with its evidence, plus any new-
breakage findings from the fix diff, plus a note of anything routed to the ledger. NOT ADDRESSED
findings return to the fix loop for the next round; ADDRESSED findings close. If every finding is
ADDRESSED and there is no new breakage, the task is complete — record its commit range in the ledger.

Three things belong in that output explicitly, because a verdict that omits them reads identically to
one that ran them: **each mutation you ran and what the gate did** (including any `MUTANT DID NOT
APPLY`), **the class membership you derived yourself** alongside the round's, and **how you measured
any guard's coverage** other than by reading its own description of itself. A guard the round claims
to have fixed and you did not mutate is ADDRESSED on the implementer's word, and you should say so
rather than let it read as verified.
