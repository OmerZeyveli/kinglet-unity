---
name: subagent-driven-implementation
description: "Use when a written plan needs to be executed task by task, with a fresh implementer per task and a review gate before the next one starts. Prefer this over inline execution when the plan has more than one task, or when a task is large enough that its own context would crowd out review."
---

# Subagent-Driven Implementation

Dispatching each task and taking its report at face value is a document, not a loop. This skill is
the loop that ran on this repository instead — fresh implementer per task, review gating on spec
*and* quality, a bounded fix loop, a ledger, one whole-branch review at the end — and what it found
is the argument for running it rather than executing inline: an installer that overwrote user files
under SIGPIPE, an installer that never removed what a shrinking payload had dropped, a skill whose
first instruction named a tool that does not resolve, a spec justification that was false when
written, and a guard that could pass while the tree was dirty. **Six defects, and every one of them
was invisible to the task that produced it and visible to the review that followed.** The task that
writes code is the worst-positioned reader of that code's problems — it just finished convincing
itself the approach was right.

This is the toolkit's own copy of an idea Superpowers had first (`subagent-driven-development`); see
`.claude/NOTICE.md` for the credit. The architecture is adopted, the wiring is not — this version is
built on Kinglet's own surfaces and carries rules a generic loop does not need.

## The loop

**Setup.** **Look for the ledger before creating one.** The plan's own handoff line routes a fresh
session straight to this skill, bypassing `unity-planning`, so starting a plan and resuming a
half-finished one arrive by the same door and look identical from here. If a ledger already exists at
the address below, this is a resume: read it, do not overwrite it, and pick up at the first open item.
**If it already records a mode, do not ask** — a decision already written down is not reopened, and it
does not matter which surface wrote it. Only create a ledger when there is none.

**A ledger lives beside its plan** — the pairing is what makes it
findable, and every address below is that one rule applied. A plan written by `unity-planning` sits
at `docs/features/<slug>/plan.md`, so its ledger is `docs/features/<slug>/ledger.md`: the third file
beside the `design.md` and `plan.md` this work came from, so one directory holds what was decided,
what was planned, and where the work stopped, and a later session opens it and reads the three in
order. A plan that lives anywhere else — a provider's plan under `docs/superpowers/plans/`, say —
takes `<plan-slug>-ledger.md` next to it, by the same rule.

Line one is the plan's path. **Line two is the execution mode**, written exactly as
`**Execution mode:** subagent-driven`, because this run took that branch of `unity-planning`'s fork.
It is what makes the choice survive the session that made it: a controller resuming this ledger reads
that line and does not reopen the decision. Add one open item per task in the plan, in order. Record
the base commit the branch started from — the whole-branch review needs a range to diff against, and
"since we started" is not a range once the session that remembers "started" is gone.

Then open two sections the ledger keeps for the whole run:

- **Standing facts for every dispatch.** What every implementer needs and no brief will contain:
  which architecture actually binds here (`CLAUDE.md`'s generated block, and any project instruction
  that overrides a rule), the gate and suite commands, and the one-implementer rule. A fresh
  subagent inherits none of the controller's reading of the project — state it, every time, or the
  first implementer rediscovers it and the third one does not.
- **Interfaces produced so far.** What each completed task actually shipped, in the form the next
  task must call it by. A brief written before a task ran guesses; this section is what really
  happened. On a measured run it carried a real trap — one pair of types exposed *properties* while
  the sibling type the brief compared them to used public *fields*, so "same as X" would have been
  wrong.

Both grow during the run. **When a task discovers a repository constraint that reddens the suite
from a distance — a documentation spec, a naming collision, a gate that scopes itself to tracked
files — it goes in Standing facts immediately, not in that task's closing notes.** Measured: one
project's first implementer lost a suite run to a rule requiring every new runtime script to be
named by some subsystem document, and no brief had mentioned it. Written down once, it cost the
remaining eleven tasks nothing.

**When to write each brief.** Write the first stage's briefs up front, and write every later brief
**just before its task is dispatched**. A brief written against a signature that does not exist yet
is a brief that gets withdrawn — and by step 5 below, a withdrawn brief costs a whole task. Waiting
also lets the brief carry what the Interfaces section learned in the meantime. A task whose brief is
not written yet is marked *(brief pending)* in the ledger, which is a state, not an omission.

**Cite by name, not by line number.** In dispatches and re-review prompts, name the test, the method
or the symbol — `SkinRulesSpec.ClampsAtZero`, not `SkinRulesSpec.cs:410-423`. Line numbers passed
from a report into a dispatch go stale between the two, and a stale citation that gets repeated is
how a document starts describing a file that no longer exists. Measured: a controller forwarded a
range citing lines 410–423 of a 378-line file.

**Per task, in plan order:**

1. **Dispatch one implementer.** `unity-coder` via the `Agent` tool, using `implementer-prompt.md` as
   the shape of the dispatch — **unless the task is not Unity work.** A Unity project's plan routinely
   contains build scripts, CI, editor tooling and documentation, and routing those to an agent that
   writes C# and drives the Editor measures the dispatch rather than the task. Use a general
   implementer for them, and record the choice in the ledger so the run stays readable. One implementer. Never two, and never this task's implementer running
   while another task's is still active — see the Unity-specific rules below.
2. **Handle the report.** The implementer returns one of four statuses — see `implementer-prompt.md`
   for what each means and what you do with it. Do not read the implementer's tool-call transcript to
   second-guess a DONE; the report is the contract, and if the report is wrong that is what review is
   for.
3. **Review.** Dispatch `unity-reviewer` with `task-reviewer-prompt.md`, pointing it at the brief, the
   report, and the diff as three file paths — never pasted inline. The same exception applies: a
   non-Unity task gets a general reviewer. It returns a spec verdict and a
   quality verdict with findings by severity.
4. **Fix loop, if the review is not clean.** Bounded at five rounds. Rounds 1–3 resume the original
   implementer — its context is intact and it wrote the code under discussion. Rounds 4–5 dispatch a
   fresh implementer on a more capable model — a loop that has survived three resumes and is still
   producing the same class of finding usually means the implementer cannot see its own problem, and
   a new one with fresh eyes and a stronger model is a different attempt, not a fourth try at the same
   one. Each round's review uses `re-review-prompt.md`, not the full task-reviewer prompt — it is
   scoped to the open findings, not a re-review of everything.
5. **If the implementer reports the brief itself is wrong, stop and re-brief — do not review it.**
   A review compares the work against the brief, so a false premise passes review and ships. Measured
   on this loop's first real run: a brief said "make every call site agree with the helper", and
   seven files turned out to define their own helper with the opposite contract under the same name.
   The implementer changed 49 call sites on that premise, caught it by probing a failure, and reverted
   29. Had it not probed, the review would have seen a tidy consistent diff and approved it.

   A brief carries the controller's authority, which makes it the more dangerous of the two documents
   to be wrong. When an implementer says the premise does not hold, that is not a fix-loop finding —
   it is a new task, and the ledger records the old brief as withdrawn rather than completed.

6. **At the cap, adjudicate — do not keep dispatching.** A sixth round is not "one more try", it is
   the controller declining to make a decision. Either park the finding in the ledger with a ruling
   (why it is safe to carry forward, and to whom) or stop the loop entirely if the finding is load-
   bearing — a security gate, a data-loss path, anything the plan cannot be shipped without.
7. **Complete.** Mark the ledger item done with its commit range (first commit of the task through
   its last, inclusive — the range the whole-branch review will diff). Record every deferred Minor
   finding and every parked finding with its ruling. Record scene and prefab state if the task touched
   either — see below.

**Final review.** After every task in the plan is complete, dispatch one review of the *whole branch*
— base commit to current HEAD — on the most capable model available, using `final-reviewer-prompt.md`.
This is not a bigger task review; it looks for what a per-task review structurally cannot, because
each task review saw one brief and one diff and nothing was ever anyone's job to check across all of
them. Triage its findings the same way the task-level fix loop does: fix, park with a ruling, or (rare)
stop.

**Finish.** Once the final review is clean or its findings are triaged, the plan is done. Report what
shipped, what was parked and why, and what still needs a human — the same three questions
`verification-before-completion` always asks.

## Rules learned running this

- **One implementer at a time. Never two against one Unity project — absolute, no exceptions.** The
  generic version of this rule is about merge conflicts in a shared working tree, and a reader who
  thinks their two tasks touch disjoint files reasonably concludes the rule does not apply to them.
  It is not about files here. The Unity Editor is a single process holding a single asset database in
  memory; two agents driving it over MCP concurrently — one calling `manage_scene`, the other
  `manage_gameobject` — corrupt that shared state in ways that show up as a broken scene, not as a
  merge conflict. A diff review will not catch it, because there is no diff between two agents'
  concurrent Editor calls — only one corrupted `.unity` file, discovered later, with no record of
  which call did it. Serialize every dispatch, even when the tasks look independent.
- **The ledger is the recovery map, not a nice-to-have log.** Conversation memory does not survive
  compaction, and a controller that has lost its place re-dispatches completed work — burning a task's
  worth of implementer and reviewer calls on something already shipped, and risking a second write
  against work the first write already finished. Record the plan path on line one, one line per task
  completion with its commit range, every deferred Minor, and every parked finding with its ruling. If
  the ledger does not say it, the next controller session does not know it happened.
- **Never fix findings in the controller session.** The controller's context holds the plan and the
  ledger; a hand-written fix pollutes it with implementation detail the controller does not need to
  carry, and — the sharper problem — a controller fix skips review entirely. The whole point of the
  loop is that a second reader checks the first reader's work; a controller that patches around a
  finding is the first reader marking its own homework. Resume the implementer instead, even for a
  one-line fix.
- **Do not pre-judge findings for the reviewer.** If a dispatch prompt contains "do not flag" or "at
  most Minor," the loop has already failed before the reviewer opens the diff — a reviewer told what
  not to find is a reviewer whose findings are curated by the party being reviewed. Send the reviewer
  the brief and the diff and let the finding be raised; adjudicate severity after it exists, not
  before.
- **The task review gates on spec compliance AND quality — either alone passes work that should not
  ship.** Code that matches the brief exactly can still be badly written (the brief cannot enumerate
  every way to write bad code), and code that is well written can still not be what was asked for. A
  reviewer who checks only one axis will wave through the other kind of defect every time.
- **The fix loop is bounded at five rounds, split 3 and 2 for a reason, not an arbitrary total.**
  Rounds 1–3 resume the original implementer because its context — the brief, the earlier findings,
  the reasoning it already did — is intact and cheap to reuse. Rounds 4–5 dispatch a fresh implementer
  on a more capable model, because a loop that has survived three resumes on the same finding is
  usually not a loop that needs a fourth attempt from the same vantage point — it is a loop where the
  implementer's model of the problem is wrong, and more resumes reinforce that model rather than
  escape it.
- **At the cap, adjudicate; do not keep dispatching.** A sixth dispatch is the controller refusing to
  make the call the process asks it to make at this point. Park the finding in the ledger with a
  ruling that says why it is acceptable to carry forward, or stop the loop outright if the finding is
  load-bearing.
- **A task is not complete until the console is clean.** `read_console` after the implementer's last
  write, every time. Unity writes files independently of whether they compile — a `.cs` file that
  fails to compile was still written successfully, git sees it as a completed change, and a report
  that never called `read_console` has no way to know the difference between "done" and "done and
  broken."
- **Manual Editor steps are a task outcome, not a footnote.** `performance.md` already states this for
  the architect: if the work needs a sprite atlas, a lightmap bake, or an import setting the agent
  cannot create through MCP, the task does not end with a description of the step — it ends by naming
  the step explicitly in the report and blocking whatever downstream work depends on the asset
  existing. A described step nobody performed did not happen (`verification-before-completion`).
- **Record scene and prefab state in the ledger.** A task that edits a scene through MCP and never
  saves it has changed nothing on disk — the next task's implementer opens a project that git says is
  clean and the Editor says is not, and inherits a disagreement it has no way to detect on its own.
  Note in the ledger whether a scene or prefab was left dirty, saved, or untouched.

## The four templates

- `implementer-prompt.md` — what a dispatch contains, and the four report statuses.
- `task-reviewer-prompt.md` — the per-task review, spec and quality, against three file paths.
- `re-review-prompt.md` — the fix-loop review, scoped to open findings, verified by experiment.
- `final-reviewer-prompt.md` — the whole-branch review and the categories that pay off.

Read the one you are about to use; do not assume its shape from this list.
