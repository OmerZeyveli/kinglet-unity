# Process layer, second pass — design

**Date:** 2026-08-03
**Status:** approved for planning
**Builds on:** `2026-08-03-surface-cut-and-process-chain-design.md`, whose Decision 4 added a
three-skill process chain. That decision was right and this one does not reverse it — it finishes it.

---

## Why this exists

Three things surfaced after the surface-cut wave merged, and they belong in one pass because two of
them are the same defect wearing different clothes.

**1. The seven surfaces that survived the cut cannot do the thing they survived for.**

The cut kept seven agents on one criterion: they drive the Unity Editor over MCP, which is something
the model cannot do unaided. All seven declare `tools: mcp__unityMCP__*`. The server actually running
on the operator's machine is named **`UnityMCP`** — capital U — registered in `~/.claude.json` by
CoplayDev's Auto-Setup wizard. Tool permissions are matched by name, so the glob matches nothing and
**every one of the seven is silently MCP-less.**

This is not new and it is not the cut's doing: all 11 `mcp__` references in the payload are lowercase
and came from ECU. What is new is that the cut removed everything else, so these seven are now the
entire editor-driving capability of the toolkit.

`MCP-SETUP.md:99-115` already records the collision, measured 2026-07-30: *"Auto-Setup empties the
`.mcp.json` this toolkit ships"*, and advises `claude mcp remove UnityMCP -s local` to drop the
wizard's copy. Endless Evolution's live state shows the opposite outcome — `.mcp.json` empty, the
wizard's `UnityMCP` in place — and nothing reported it for four days.

**2. The process chain states the happy path and closes no escape hatch.**

The three skills added by the previous wave are 36, 35 and 36 lines. Measured against their
Superpowers counterparts (283, 120, 62 lines) they share nothing but YAML boilerplate — text
similarity 0.120, 0.183 and 0.156, zero shared runs over 40 characters outside the frontmatter. The
text is ours.

Being short was the right call and `verification-before-completion`'s claim/evidence table earns its
space. But brevity was applied to the wrong dimension. What makes the upstream versions work is not
length for its own sake — it is that they enumerate the ways a model talks itself out of the process
and answer each one. "Red Flags — STOP and follow process". "Common Rationalizations". A table whose
left column is the thought you are having right now and whose right column is why it is wrong.

Ours say what to do. They do not say what it looks like when you are about to not do it.

**3. There is no execution loop, so a plan is a document rather than a process.**

`/unity-workflow` has Phase 3: Execute. It dispatches. What it does not have is the loop that made
this repo's own last wave work: a fresh implementer per task, a review after each task that gates on
both spec compliance and quality, a bounded fix loop, a ledger that survives compaction, and one
whole-branch review at the end that sees what per-task reviews structurally cannot.

That loop is not theory here. It ran seven tasks on this repository today and found, among other
things: an installer that overwrote user files under SIGPIPE, an installer that never removed what a
shrinking payload dropped, a skill whose first instruction named a tool that does not resolve, a
spec justification that was false when written, and a guard that could pass while the tree was dirty.
**Six of those were invisible to the task that produced them and visible to the review that
followed.** The operator watched it work and asked for it.

---

## Decision 1 — Let the wizard own the MCP server name

Align every `mcp__unityMCP__` reference to `mcp__UnityMCP__`, change what `install.sh` writes into
`.mcp.json` to `UnityMCP`, and rewrite `MCP-SETUP.md` to stop advising users to remove the wizard's
registration.

**Why concede rather than fight.** The wizard is upstream, it re-asserts its name on every Auto-Setup,
and `MCP-SETUP.md` tells users to run Auto-Setup — so the toolkit currently ships instructions that
produce the configuration in which it does not work. Keeping our own casing means every user who
follows our own setup document breaks their agents, and the only fix is a manual `claude mcp remove`
that the next Auto-Setup undoes.

A name is not worth a permanent maintenance battle with the upstream that owns it.

**What this does not do:** it does not make the reference robust against a *third* naming. Nothing
can, short of Claude Code offering case-insensitive or wildcard server matching. What it does is pick
the name that the documented setup path actually produces.

**Skill and agent prose stops naming the prefix at all.** A skill that says *"read the console with
`mcp__UnityMCP__read_console`"* is coupling instructional text to a deployment detail. It becomes
*"read the console with the unity-mcp `read_console` tool"*. Only the `tools:` frontmatter globs —
where the exact string is load-bearing — carry the server name.

---

## Decision 2 — Give the process skills their escape hatches

Each of the four process skills gains the section it is missing: the enumerated list of ways the
process gets abandoned, with the counter for each. Length is not the constraint; substance is. A
table row that restates the rule in different words is padding and does not ship.

The rows must come from **observed** failures, not imagined ones. This repository has a large stock
of them — `docs/research/pioneer/field-notes.md` runs to 87 sections and today's wave added a dozen
more, all with mechanisms attached. A rationalization table written from measured incidents is a
different artifact from one written from intuition, and this repo can afford the first.

| Skill | Gains |
|---|---|
| `using-kinglet` | Stays short. It is injected every session and §87 governs. It gains only a pointer to the others. |
| `deep-interview` | The ways a vague request gets treated as clear: "they said what they want", "I can infer the file", "asking is slow". |
| `systematic-debugging` | The ways a fix gets proposed before a cause is found, and the Unity-specific traps that make a wrong cause look right. |
| `verification-before-completion` | The ways "done" gets claimed without evidence. This is where the wave's own incidents concentrate. |

**Extended to the other three layers, at the operator's request.** The pattern above is not specific
to process skills, and each layer turned out to have its own version of the same gap. Measured before
scoping, not assumed:

| Layer | The gap, measured |
|---|---|
| **9 knowledge skills** | Not thin — 128 to 724 lines, 10 to 32 code blocks each. But four (`input-system` at 414 lines, `object-pooling`, `physics`, `urp-pipeline`) contain **no** warning or pitfall section at all; only one of nine names a Unity version, so nothing says when it goes stale; and **none says which part of its subject a rule already binds.** That last one has a precedent: the cut removed `serialization-safety` precisely because it duplicated `serialization.md`. The survivors were kept because rules cover them only *partly* — and none of them says which part, so a skill can drift into contradicting a rule that outranks it with nothing to flag it. |
| **8 agents** | All eight already carry limits and a `Skills to load` block, so the process-skill gap does not apply. The real one, from this wave's final review: **no agent's block names `systematic-debugging` or `verification-before-completion`.** The chain therefore holds only when a human enters through a command; a dispatching model that selects an agent directly — the path §1 of the trigger rules exists to support — gets an implementer with no method and no definition of done. None of them states what it returns, either, so callers parse prose. |
| **6 rules** | The layer that measurably works: they auto-load, they bind, and a probe answered from `serialization.md` with zero tool calls. Two gaps. `architecture.md` reads as unconditional while a real project has zero VContainer files and had to write its own `AGENTS.md` section to neutralise it — the generated `CLAUDE.md` block now says so, but **no non-Claude-Code client ever sees that block.** And none of the six is dated, so nothing says when a binding rule goes stale. |

The rules are amended, not weakened. An unconditional rule that says where to check its own
applicability is stronger than a hedged one.

---

## Decision 3 — Ship the execution loop as a Kinglet surface

A new skill, `subagent-driven-implementation`, plus the prompt templates it dispatches with. It is
offered as a choice at the end of planning, alongside inline execution — the same fork the operator
watched and asked for.

**What it is:** a fresh implementer per task; a task review gating on spec compliance *and* quality;
a bounded fix loop that resumes the same implementer for early rounds and escalates to a fresh one on
a more capable model when it stalls; a ledger file that survives compaction; and one whole-branch
review at the end, dispatched on the most capable model, that sees the branch as a product rather
than as a sequence of diffs.

**Wired to Kinglet's own surfaces, not to generic ones.** The implementer is `unity-coder`. The task
reviewer is `unity-reviewer`. A failing test routes to `unity-fixer` through `systematic-debugging`.
Tests are `unity-test-runner`. Verification is `verification-before-completion`. The plan comes from
`/unity-workflow` Phase 2, which already accepts a written plan as input.

**Unity-specific rules the generic loop does not have**, and the reason this is an adaptation rather
than a copy:

- **Never dispatch two implementers in parallel against one Unity project.** The Editor is a single
  process with a single asset database; two agents driving it over MCP corrupt each other's state in
  ways no diff shows. The generic loop forbids parallel implementers for merge-conflict reasons; here
  the reason is worse and the rule is absolute.
- **A task is not done until the console is clean.** Compilation errors do not fail a file write.
  The review gate must include `read_console` output, not just the diff.
- **Manual Editor steps are a first-class task outcome.** Sprite atlases, lightmap bakes, import
  settings — an agent cannot create them, and a loop that treats "I described what the human must do"
  as completion produces a plan that silently never happens. `performance.md` already states this for
  the architect; the loop must carry it.
- **The ledger records scene and prefab state**, because a task that leaves an unsaved scene has
  changed nothing on disk and the next task inherits an Editor that disagrees with git.

**What is deliberately not adopted:** git worktrees (Unity projects do not tolerate two checkouts
sharing a `Library/`), and the parallel-agent dispatch skill (same reason as the parallel-implementer
rule).

---

## Decision 4 — Credit Superpowers as an influence

Three files name Superpowers today; all three call it the competitor. The design of the chain, the
execution loop, and two skill names (`systematic-debugging`, `verification-before-completion`) came
from it.

MIT covers expression, and the measured similarity says the expression is ours. There is no license
obligation here and this decision does not claim one. It exists because `CREDITS.md`'s opening
sentence is *"nothing here is asserted on trust"*, and a credits file that names the project whose
architecture we adopted only as the thing we beat is an incomplete record by that standard.

One short section, with the measured numbers, in `CREDITS.md` and `.claude/NOTICE.md`.

---

## Success criteria

1. **The suite stays green at every commit**, every test file present in the runner's output,
   `check-provenance.sh` reporting `provenance OK`.
2. **A guard fails when an agent's `tools:` glob names a server no shipped configuration writes.**
   The current defect had no test and lived for as long as the toolkit has existed; the fix is worth
   nothing without something that keeps it fixed.
3. **The seven MCP agents can name a tool that resolves**, verified against the live registration
   rather than against the repo's own convention — which is the check that failed last time.
4. **The execution loop runs one real task end to end on this repository** and produces a ledger, a
   task review, and a whole-branch review. A process skill that has never executed is a document.
5. **The rationalization tables cite incidents, not intuitions.** Spot-check: every row traceable to a
   field note, a commit, or a measured probe.

Criterion 3 is the one that can fail honestly, and the shape of its failure is known: verifying
against the repo's own convention instead of the live system is exactly how this defect survived a
whole-branch review earlier today.

---

## What this does not do

| Deferred | Why |
|---|---|
| Headless Unity as an MCP replacement | It covers builds, tests and batch asset work — `docs/hardening/` already does this in Endless Evolution — but not live Editor state, which is what `read_console` and the profiler are for. Complementary, not a substitute. A separate evaluation. |
| Case-insensitive or multi-name MCP matching | Not expressible in a `tools:` glob. Would need Claude Code support. |
| Re-enabling Superpowers in Endless Evolution | The operator's environment, and their call. The measurement says we now win with it enabled. |
| Plugin packaging | Still dropped, for the reasons in the previous spec. |

---

## Risks

- **Decision 1 concedes a name and cannot be un-conceded cheaply.** If CoplayDev renames again, every
  reference moves again. The mitigation is Decision 1's second half: prose stops naming the prefix, so
  the blast radius is the frontmatter globs and one installer heredoc.
- **Decision 3 ships a process that this repository has run and a Unity project has not.** The loop's
  Unity-specific rules are reasoned from `performance.md`, `unity-specifics.md` and the MCP tool
  surface — not measured. Criterion 4 is the first real test and it is deliberately scoped to one task.
- **Decision 2 can produce padding.** The failure mode of "add a rationalization table" is a table of
  plausible-sounding rows nobody has ever thought. Criterion 5 exists to catch that, and rows that
  cannot cite an incident should be cut rather than softened.
