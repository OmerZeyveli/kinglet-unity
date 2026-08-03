# Task review dispatch

One dispatch, one `unity-reviewer` invocation via the `Agent` tool, after every implementer report
that is not `BLOCKED`. This is the shape — fill it in per task.

## The three inputs, by path

Give the reviewer three file paths. **The diff arrives as a file, never pasted into the dispatch
prompt.** A diff pasted inline is a diff the reviewer cannot re-open, re-grep, or check line numbers
against once it starts writing the verdict — a path is.

1. **The brief** — `<path to this task's brief>`.
2. **The implementer's report** — `<path to the report file named in the implementer dispatch>`.
3. **The diff** — write `git diff <task-start-commit>..<task-end-commit>` to a file and pass that
   path. Not `git diff HEAD~N` counted by hand, and not the working tree — the exact commit range the
   implementer produced.

## Tell the reviewer what the controller already verified

State plainly what has already been checked — for example, "the suite was run at the end of this
task and reported N/N; do not re-run it to confirm what the report already states." The reviewer's
job is to review the *work*, not to re-derive facts the controller already holds. A reviewer that
reruns a 2-minute suite to learn something the dispatch could have told it in one line is wasted time
on every single task in the plan.

## The binding constraints, copied verbatim

Paste the constraints that bind this task's kind of change — the relevant rules from
`.claude/rules/`, and anything the plan's Global Constraints section states that applies here. Copy
them verbatim, not summarized; a summary is a second-hand paraphrase of a rule the reviewer is being
asked to enforce exactly, and a paraphrase can silently drop the clause that mattered. This is the
reviewer's attention lens — the specific things to check, not "review the code" unscoped.

## Verdict format the reviewer must return

**Spec:** ✅ or ❌, with specifics — which requirement, and what the diff does or does not do about
it. Not a bare checkmark.

**Quality:** Approved or Needs work. If Needs work, every finding classified:

- **Critical** — must fix before this task can be marked complete.
- **Important** — should fix; can be deferred to the ledger only with an explicit reason.
- **Minor** — worth noting, safe to carry to the ledger as deferred.

Each finding at `file:line`. A finding with no location is not actionable — send it back for one.

**`⚠️ Cannot verify from diff`** for anything the reviewer cannot confirm by reading the diff alone —
behavior that depends on unchanged code, a runtime property, anything that needs the Editor running
and the reviewer does not have MCP access to check. Say so explicitly rather than asserting confidence
the diff does not support.

## What happens next

Critical or Important findings enter the fix loop (`re-review-prompt.md`) against the original
implementer. Minor findings and any `⚠️ Cannot verify from diff` items go straight to the ledger — do
not spend a fix-loop round on a Minor.
