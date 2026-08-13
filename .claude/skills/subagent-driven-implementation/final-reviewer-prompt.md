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

   **Required, and not a category to look for but a procedure to run: the aggregate sweep.** Every
   removal sweep during the loop was keyed on **names** — search the tree for the thing that was
   deleted. A bare numeral, a category word, a capability sentence and a scope claim contain no
   removed name, so a name-keyed sweep is structurally blind to all four, and this sweep has
   therefore never run. You are the only reader positioned to run it, because you are the only one who
   sees every removal on the branch at once. Collect what the branch removed or renamed, then search
   the whole shipped tree for these four shapes and **re-derive each against the tree as it now
   stands**:

   - **Bare numerals.** Any count of a thing whose number the branch changed, wherever it is written
     as a fact — a table cell, a summary line, a comment. **Search on the noun, not the number**,
     because the number is what you are trying to find and cannot be the needle: for each kind whose
     count moved, search the shipped tree for that kind's word and read every digit near a hit —
     `grep -rniE '[0-9]+[^0-9]{0,40}NOUN|NOUN[^0-9]{0,40}[0-9]+'`, plus its spelled-out forms ("two",
     "a dozen"), which no digit pattern reaches. Then derive the count and compare; never read it off
     the document that states it. **This is the highest-cost shape of the four** — see below.
   - **Category words.** A list of kinds ("meta, code quality, workflow") that a removal emptied or
     shortened. A list survives the deletion of its last member without one word changing.
   - **Capability sentences.** "X enforces Y", "the tool checks Z" — written about a behaviour rather
     than a file, so nothing that names a path will find them, and they stay true-sounding after the
     thing that did the enforcing is gone.
   - **Scope claims.** "This was never applied to W", "W is an open question". A branch that applies
     it leaves the sentence asserting the opposite, in a file nobody on the branch opened.

   In the audit that produced this instruction, **every documentation finding was one of these four,
   and not one was reachable by the name-keyed sweep the plan actually specified.** One of them was a
   count overstated by more than double on the page a reader uses to decide whether to install.
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
