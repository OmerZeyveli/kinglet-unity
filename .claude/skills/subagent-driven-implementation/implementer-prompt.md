# Implementer dispatch

One dispatch, one task, one `unity-coder` invocation via the `Agent` tool. This is the shape — fill
it in per task, do not paste this file verbatim.

## What the dispatch contains

1. **Where this fits.** One line: the plan's name and this task's number and title. Enough for the
   implementer to orient itself, not a history lesson.
2. **The brief.** Introduce it as "read this first — your requirements, exact values verbatim":
   `<path to this task's brief>`. The brief is authoritative. If the dispatch prose and the brief
   disagree, the brief wins and say so.
3. **Interfaces the brief cannot know.** What earlier tasks in this plan actually produced — a file
   path that moved, a function signature that came out different from the brief's guess, a decision
   an earlier implementer made that this task depends on. The brief was written before those tasks
   ran; state what changed since.
4. **The controller's resolution of any ambiguity it noticed.** If the brief leaves a decision
   implicit, do not pass the ambiguity through unresolved — a brief that leaves a decision implicit
   does not remove the decision, it moves it to whoever reads the brief next, silently. Resolve it and
   say what you decided and why, in one or two lines.
5. **The report-file path and the report contract** (below). State the exact path the implementer
   must write its report to, and that the report is what the controller reads — not the transcript.

## What the dispatch must NOT contain

**Accumulated prior-task history.** A real dispatch in this repository reached 42,000 characters, and
almost all of it was pasted history from tasks the implementer did not need to re-litigate. History
belongs in the ledger, which the controller reads — not in the dispatch, which the implementer reads
once and then works from. If the implementer needs a fact from an earlier task, state that one fact
under "interfaces," not the earlier task's full report.

## Report statuses

The implementer's report ends with exactly one of these. The controller acts on the status, not on
its own reading of the transcript.

| Status | Means | Controller does |
|---|---|---|
| `DONE` | Spec met, console clean, verified per `verification-before-completion` | Proceeds to review |
| `DONE_WITH_CONCERNS` | Spec met but the implementer flagged something worth a second look — an assumption, a tradeoff, a test it could not run | Proceeds to review, and passes the concern to the reviewer explicitly so it is not missed |
| `NEEDS_CONTEXT` | The brief was ambiguous or contradicted something the implementer found in the repository, in a way the controller's dispatch did not resolve | Controller resolves the specific question and re-dispatches — does not guess on the implementer's behalf and does not fix it itself |
| `BLOCKED` | The task cannot proceed — a manual Editor step is needed first (sprite atlas, import setting, lightmap bake), a dependency task did not produce what this one needs, or the console will not go clean no matter what was tried | Controller records the block in the ledger, and either resolves it (perform or arrange the manual step) or stops the plan at this task and reports up |

A report with no status line is not a report. Ask for one before proceeding.
