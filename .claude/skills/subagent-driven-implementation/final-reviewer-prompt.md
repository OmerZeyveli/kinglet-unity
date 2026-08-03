# Whole-branch review dispatch

One dispatch, after every task in the plan is complete, on the most capable model available. This is
not a bigger task review — it exists because a per-task review structurally cannot see what this
dispatch is asking for.

## Why a per-task review cannot do this job

Each task review saw one brief and one diff. Cross-task properties — a file two tasks both touch, a
number one task typed into prose that a later task's change invalidates, a check whose scope was
correct when task 2 wrote it and stale by the time task 6 added the thing it should have covered —
were nobody's job, because no single task review's scope includes another task's diff. Running the
same kind of review five more times does not find these; only a review that sees the branch as one
artifact does.

## The three jobs

1. **Triage the ledger's deferred and parked findings for merge.** Every Minor finding deferred
   during the loop and every finding parked at a fix-loop cap is sitting in the ledger unresolved.
   Read them against the finished branch — some are now moot (a later task overwrote the code), some
   are still real and small enough to fix here, and some are real and large enough to become their
   own follow-up. Say which is which.
2. **Find what per-task reviews structurally could not see.** Diff the whole branch — base commit to
   current HEAD — and look across it, not through it task by task. **The categories that paid off
   running this on this repository:**
   - **Files nothing references any more.** A file an earlier task wrote and a later task's edits
     made obsolete, still sitting in the tree with no reference pointing at it.
   - **A check whose scanned set is not the whole reality.** A guard added or modified in one task
     that scopes itself to a directory or a file pattern that was complete when that task wrote it
     and stopped being complete once another task added something outside that scope.
   - **Documentation asserting what the code no longer does.** Prose written honestly against the
     code as it stood at the time, now describing behavior a later task changed.
   - **A number typed into prose that a later commit invalidated.** A count, a percentage, a file
     total — written as a fact, and no longer true once something after it shipped.
3. **Judge shipped content as product, not just as correct.** A task review asks "does this diff meet
   its brief." This review asks the question none of them asked: is this good, on its own terms, for
   someone who did not write it and has no plan document to explain it — the wording an operator
   would actually want to read, not just wording that passes.

## Output

A verdict per triaged ledger item (merge as-is / fix now / spin out as follow-up, with reasoning), a
list of new findings by the four categories above (or others found, labeled), and a product judgment
with specifics rather than a bare "looks good." Findings here follow the same severity and fix-or-park
adjudication as the task-level loop — this review does not get its own separate process, it uses the
one already established.
