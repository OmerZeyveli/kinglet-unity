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

## Output

The same finding list, each marked ADDRESSED or NOT ADDRESSED with its evidence, plus any new-
breakage findings from the fix diff, plus a note of anything routed to the ledger. NOT ADDRESSED
findings return to the fix loop for the next round; ADDRESSED findings close. If every finding is
ADDRESSED and there is no new breakage, the task is complete — record its commit range in the ledger.
