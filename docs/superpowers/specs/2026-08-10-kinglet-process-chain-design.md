# Kinglet process chain — design

*2026-08-10. Status: approved by the owner, section by section, in the session that produced it.*

## Decision

Kinglet's process chain becomes three skills that pull each other — `unity-brainstorming` →
`unity-planning` → the execution fork — adapted at the expression level from Superpowers' MIT
`brainstorming` / `writing-plans` / `executing-plans`. The two commands that only *sequence* other
surfaces, `/unity-workflow` and `/unity-feature`, are deleted; their content moves into the chain and
nothing is dropped silently. `using-kinglet` stops being a summary the model can answer from and
becomes a mandate that points at files. Every behaviour claim in this document names the scenario
that would prove it.

The surface pool is unchanged at 33: two new skills paid for by the two deleted sequencer commands.

## What was measured, and what it says

Three runs produced the evidence this design answers to. None of it is argued.

1. **The trigger is defeated by the context that makes the toolkit good.** `deep-interview`'s
   description fires "when the request is vague or underspecified" — a judgment made *before* the
   skill loads, by a model that has just read six rule files and a generated `CLAUDE.md` and feels
   informed. Across four runs there was **one applicable case and one miss**. (The other three were
   ledger-resume work, which the skill's own exemption list correctly excludes; the "0/4" figure
   reported earlier that day was wrong and was corrected in the same session.)

2. **The `Skills to load` block works; the injected table does not pull.** Twelve implementers loaded
   both skills their block named, without exception, and seven reached past it for a third. Over the
   same runs the `using-kinglet` table described each process skill well enough that the model
   executed the behaviour without ever loading the file — twice, and an explicit instruction did not
   change it.

3. **The fork is orphaned.** The inline-vs-subagent choice lives in `/unity-workflow` Phase 2, and two
   of the three routes to execution (the `using-kinglet` table row; resuming from a ledger) never pass
   through it. `subagent-driven-implementation`'s own `description:` claims it is "offered by
   `/unity-workflow`", which is false on most routes — and `description:` is the entire selection
   mechanism.

Against that, one thing already works and must not regress: asked a serialization question the rules
already answer, the chain correctly selected **nothing**.

## What Superpowers does differently, structurally

Read from the packaged plugin at `.research/superpowers` (6.2.0) and its eval repo at
`.research/superpowers-evals`.

- **The trigger is a category of work, not a judgment about the request.** *"You MUST use this before
  any creative work — creating features, building components, adding functionality, or modifying
  behavior."* Nothing is self-assessed before loading.
- **The fork lives in the upstream step that cannot be skipped** — inside `writing-plans`, not in an
  optional entry point — and it is carried a second time by the written plan file itself
  (*"REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development…"*), so a fresh session that
  opens only the plan is still routed.
- **Handoffs are closed.** `brainstorming` ends: *"Do NOT invoke any other skill. writing-plans is the
  next step."* One named successor, everything else prohibited.
- **The injected text is a mandate that points at files, not a summary that answers.** An announce
  ritual makes a non-load visible; a Red Flags table names the rationalizations in advance.
- **Skill invocation is a tested behaviour.** 85 scenarios, per-model baselines, deterministic
  transcript assertions (`check-transcript skill-called`, `skill-before-implementation-tool`), and
  calibration pairs that assert both firing and *not* firing on the same fixture. The prose devices
  above are downstream of this loop; they are what a red scenario produced.

The last point is the one that matters most, and it is why this document names scenarios inline.

## Decisions

### D1 — `deep-interview` becomes `unity-brainstorming`, and its content grows

Renaming alone would be cosmetic. The surface gains the half it never had: **approaches considered,
trade-offs, a recommendation, and a written design decision.** Today it extracts requirements and
prints a summary into the conversation; that is a requirements interview, not a design step.

The name is `unity-brainstorming` rather than bare `brainstorming` because `superpowers:brainstorming`
may be installed alongside — as it is in Endless Evolution today — and the word `unity` is what
separates two surfaces that otherwise do the same job. It also matches the repo's existing
convention. Under the current name the surface **won** head to head (a "double jump" prompt selected
`deep-interview`; `superpowers:brainstorming` never appeared), so the rename must not cost that win;
scenario `brainstorming-fires-on-new-mechanic` is what proves it did not.

### D2 — The trigger becomes unconditional over a category; the boundary is measured, not listed

The five-item exemption list is removed. In its place:

- The trigger names a **category of work**: building something new in this Unity project.
- The **Ambiguity Score survives with a different job.** It no longer decides *whether* to fire; it
  decides *how deep* the round goes. A clear request passes in one round; a vague one turns three.
  **Depth scales the round, never the artifact:** at depth 1 the design may be three sentences, but
  `design.md` is still written, still presented, and still approved. "Short design" and "no design"
  are different outcomes and only one of them is allowed.
- The category boundary — build versus tweak — is drawn by a **calibration pair**, not by prose.

This mirrors Superpowers' actual behaviour rather than its prose. Their skill says *"Every project
goes through this process… the design can be short"*, and their eval `cost-checkbox-over-trigger`
asserts that a trivial checkbox request must **not** trigger it. Both are true because the category
excludes tweaks; the boundary is the pair's job, not a sentence's.

Removed exemptions are not lost capability: a broken thing already routes to `systematic-debugging`,
and a resumed run already carries its decisions in a ledger.

**Proposed description string** — the single most load-bearing text in the payload:

```
You MUST use this before building anything in this Unity project — a new mechanic,
system, component, scene, or UI screen — and before writing a plan, touching C#, or
mutating the scene. Explores intent, constraints and approaches, then writes the
design decision to a file. Not for a tweak to something that already works.
```

### D3 — The HARD-GATE covers MCP writes, not only code

Superpowers' gate forbids code, scaffolding, and implementation actions. In Unity that is incomplete:
a single MCP call mutates a scene, a prefab, or a ScriptableObject, and those are the least reversible
actions an agent can take.

> Until a design has been presented and approved: no implementer agent is dispatched, no `.cs` is
> written, **and no MCP write call is made** — scene, prefab and ScriptableObject included.

This is adaptation rather than copying, and it is the clearest example of why the text could not be
imported unchanged.

### D4 — Handoffs are closed, and name the forbidden alternatives

`unity-brainstorming`'s terminal state is `unity-planning`, stated as a prohibition on everything
else. Ours must name the tempting alternatives explicitly, because unlike Superpowers we ship them:
`/unity-prototype`, `unity-coder`, and any MCP agent are named and forbidden until the chain reaches
execution.

### D5 — `unity-planning` is a skill, and it carries the fork

Plan-writing stops being Phase 2 of a command. As a skill it sits on every route into execution, which
is the structural fix for the orphaned fork. It carries, from Superpowers' `writing-plans`: checkbox
task syntax, the bad-task anti-patterns (*"add appropriate error handling"* as a task is a defect), the
type-consistency self-review, and the closed handoff.

The fork's rule, decided 2026-08-05 and unimplemented until now:

> Confirm the execution mode before starting. **If the ledger already records a mode, do not ask** —
> a recorded decision is not reopened. On a fresh run, state both routes and choose.

`subagent-driven-implementation`'s `description:` loses the clause *"offered by `/unity-workflow`"*.

### D6 — `unity-execution` exists so the fork's two branches are the same kind of thing

Today one branch is a skill and the other is a command's phase. That asymmetry is the defect being
removed, so the inline branch gets a home at `.claude/skills/unity-execution/SKILL.md`, adapted from
`executing-plans`.

It is also where the two orphans land:

- **The Deslop Pass** — five categories and five rules, including *"do not touch code that existed
  before this workflow started"* and *"false positives are worse than missed bloat"*. Nothing else in
  the payload carries this. It is the only content of `/unity-workflow` with no other owner, and
  moving it is a named task with its own guard.
- **The Phase 4 verify loop** — the subagent branch has its own review loop; the inline branch needs
  this one.

**Cut-criterion defence.** The criterion is *"does something the model cannot do unaided."*
`unity-planning` passes on protocol the model does not reproduce (task granularity, the anti-patterns,
the self-review, the artifact-carried handoff). `unity-execution` is the weaker case and this document
says so plainly: its defence rests on the Deslop Pass and the bounded verify loop, and if the
implementation cannot make that defence concretely, the honest outcome is to fold it into
`subagent-driven-implementation` rather than ship a thin surface.

**If that fallback is taken, say what it costs.** That skill would then own both branches, so its name
and `description:` stop being true and must change with it — and the Deslop Pass and verify loop still
need an explicit home inside it. Folding is not deleting; a fold that loses the orphans is the same
silent loss D7 exists to prevent.

### D7 — `/unity-workflow` and `/unity-feature` are deleted

A command that only sequences other surfaces is a second definition of the chain. A command that
routes to an agent doing work the chain does not is a real surface. By that criterion the two
sequencers go and the nine routers stay (`/unity-fix`, `/unity-review`, `/unity-test`, `/unity-scene`,
`/unity-ui`, `/unity-optimize`, `/unity-doctor`, `/unity-init`, `/unity-prototype`).

The owner's standing requirement — *"nobody should have to memorise these commands"* — points the same
way, and the measurement agrees: a "double jump" prompt selected the chain's entry point, not
`/unity-feature`.

Phase mapping, so nothing is lost by omission:

| `/unity-workflow` phase | New home |
|---|---|
| Phase 1: Clarify | `unity-brainstorming` |
| Phase 1a: adopt an existing plan | `unity-planning` input handling |
| Phase 2: Plan | `unity-planning` |
| Phase 3: Execute | `unity-execution` |
| Phase 4: Verify loop | `unity-execution` |
| **Deslop Pass** | `unity-execution` — **guarded by its own test** |
| Final Summary | `unity-execution` output format |

`/unity-prototype` keeps its own open-ended Clarify and is **deliberately** exempt. Recording it here
means the exception is a decision, not an oversight.

### D8 — Artifacts live in `docs/features/<slug>/`

```
docs/features/<slug>/
  design.md    written by unity-brainstorming
  plan.md      written by unity-planning
  ledger.md    written by subagent-driven-implementation
```

`/unity-workflow` Phase 1a already **reads** `docs/features/<slug>/plan.md` and nothing ever wrote it.
Choosing this path closes a dangling reference instead of creating a second one. Three files in one
directory is also where the design↔engineering link becomes a fact of the filesystem: a later session
opens one directory and reads what was decided, what was planned, and where the work stopped.

`design.md` carries, beyond Superpowers' spec shape:

- the architecture decision in Model/View/System terms, **and which rules bind**, by reference to
  `CLAUDE.md`'s generated block — because that is detected per project, not assumed;
- **operator steps** — the Unity work an agent cannot do (sprite atlases, import settings, lightmap
  bakes, `AnimatorOverrideController`s). `performance.md` already makes these mandatory and they have
  had no home; in the Endless Evolution run they were hand-written into a ledger for want of one.

`plan.md` carries the artifact-borne handoff, Superpowers' quietest and most effective device: the
plan file itself names the required next skill, so a fresh session given only a path is routed without
reading any table. **This is what closes the ledger-resume route.** The line is fixed text, because a
guard has to test the same string the template writes:

```
**For agentic workers:** REQUIRED SUB-SKILL — execute this plan task by task with
`subagent-driven-implementation` (recommended) or `unity-execution` (inline). Do not
implement directly from this file.
```

**Committing.** The artifact is committed — that is what Break 1 exists for, and an uncommitted file
is lost at the next checkout, which is the defect being repaired. Two constraints, both Unity-specific:
only the artifact path is committed, and **never `git add -A`**, because in a Unity project `-A` stages
`.meta` churn, and `.meta` loss is the damage these rules spend the most effort preventing.

### D9 — `using-kinglet` becomes a mandate; the agent blocks are untouched

Both carriers, because they reach different populations: the agent blocks (measured 12/12) reach
subagents, while the chain's surfaces live at controller level where the blocks never apply.

**The escape sentence is rewritten, not deleted.** Its measured justification stands — the serialization
probe correctly selected nothing, and a selection there would be a regression. What must close is its
generalisation to *"if I feel I can answer, I need no surface."*

```
today:  A question that the rules already answer needs no surface. Answer it.

after:  A question about what the rules already state is answered from the rules —
        that is not work, and it selects no surface.
        A request to build, change, or fix something is work, and work always
        selects a surface.
```

Three devices are added:

1. **An ordering rule** — invoke the surface *before any response or action*, including clarifying
   questions and reading code.
2. **An announce ritual** — `Using [skill] to [purpose]`. Its only job is to make a non-load visible in
   the conversation rather than only in a transcript read afterwards.
3. **A Red Flags table built from this toolkit's own measured rationalizations**, not Superpowers'
   generic list:

| Thought | Reality |
|---|---|
| "This request is already clear" | That judgment is made by a model that has just read six rule files and a generated block. It is exactly the one miss that was measured. |
| "The table already tells me what to do" | The table names the file. It is not the file. Twice, the chain was executed without ever loading it. |
| "I am resuming from a ledger, the decision is made" | A ledger records the **mode**. It does not record the design of a new task. |
| "I remember this skill" | The block is 41 lines; the skill is over 110. What you remember is the block. |
| "Let me look at the code first" | The surface is the thing that tells you how to look at it. |

**Removed from the table:** the descriptive parentheticals (e.g. `deep-interview — ask, do not guess`).
A row names a surface; it does not summarise it. That summary is what made loading unnecessary.

### D10 — Provenance and licence: adaptation changes the legal facts

`CREDITS.md` §4 and `.claude/NOTICE.md` §3 currently assert that Superpowers is *"influence, not a
license obligation"*, that *"what was not taken is the text"*, cite measured similarities of 0.120 /
0.183 / 0.156, and state that **no Superpowers licence text is reproduced** because nothing is derived
at the expression level.

**Adapting the text makes those statements false.** Consequences, all first-class:

1. `.claude/NOTICE.md` gains Superpowers' MIT licence text. NOTICE ships into every installed project,
   so a stale attribution claim there is precisely the defect already found and fixed once in this
   repo's history.
2. The similarity figures are re-measured or withdrawn. They cannot be left standing.
3. `scripts/check-provenance.sh:103` accepts `superpowers` as an origin. The Pioneer design mandated
   this and it was never implemented; `unity-planning` and `unity-execution` make it necessary.

**The two-origin file.** `deep-interview` is `origin=ecu` (ECU 1.5.0,
`.claude/skills/core/deep-interview/SKILL.md`, `status=modified`), and the Ambiguity Score being kept is
ECU's contribution. Adapting Superpowers structure into it makes the file derive from both, and the
schema has one origin column.

**Ruling: `origin=ecu` stays**, and the Superpowers adaptation is recorded in the `note` column. The
file's lineage begins at ECU and ECU's material survives; the licence obligations themselves are
discharged in `CREDITS.md` / `NOTICE.md`, which is where they belong.

**The cost is named rather than absorbed.** That row's `note` already carries four clauses, and the
2026-08-03 ledger deferred note-field bloat with an explicit trigger: *"readability may need a rethink
if another wave adds a fifth."* This wave adds the fifth. The rethink is therefore in scope.

**Two refusals were never recorded** and must be:

- `using-git-worktrees` — refused in the Pioneer design with a measured Unity reason (worktrees do not
  share `Library/`; every one triggers a full reimport and `.meta` GUIDs diverge), but it has **no
  `provenance-skip.tsv` row**. The refusal lives only in a design document, so no guard enforces it.
- `visual-companion` — deliberately not taken in this wave (shipping a browser server into user
  projects is separate work). Without a `rule=absent` row, "did we forget or decline?" has no answer a
  year from now.

`/unity-workflow` and `/unity-feature` also take `rule=absent` rows so they cannot silently return.

**Baseline hazard.** This wave changes the path set by two removals, two additions and one rename
(itself a removal plus an addition). The 2026-08-03 ledger records that a path-set change is an
unconditional refusal by design until the regenerator was taught otherwise. The plan must confirm the
tool handles a **rename**, and must run `--dry-run` first and report any disagreement with its
prediction rather than tuning to it.

## Scenarios — every claim above, and what would prove it

Format follows `.research/superpowers-evals`: `pre()` preconditions, `post()` deterministic transcript
assertions. **Unity addition:** ordering is asserted before MCP write calls as well as before
`Write`/`Edit`, because D3 put them inside the gate.

| Scenario | Assertion | Protects |
|---|---|---|
| `brainstorming-fires-on-new-mechanic` — *"add a double jump"* | `skill-called unity-brainstorming`, before Write/Edit **and** before any MCP write | D1, D2 |
| **pair:** `brainstorming-not-on-tweak` — *"make the jump 20% higher"* | `skill-not-called unity-brainstorming` | D2's category boundary |
| `rules-question-selects-nothing` — a serialization question | zero surface selections | D9's rewritten escape clause |
| `hard-gate-holds` — design not yet approved | no implementer agent, no MCP write | D3 |
| `fork-fires-on-fresh-run` | the mode question precedes dispatch | D5 |
| **pair:** `fork-silent-on-resume` — ledger records a mode | the mode question is **not** asked | D5 |
| `plan-carries-handoff` — fresh session given only the plan path | routes to the execution surface | D8 |

### Runnable in this wave, without a model harness

These become the wave's own gate, as bash guards under `tests/`:

- the `plan.md` template carries the required-next-skill line;
- the Deslop Pass's five categories are present in `unity-execution` (it is the only orphaned content,
  so it gets the only content-level guard);
- `provenance-skip.tsv` carries rows for `/unity-workflow`, `/unity-feature`, `using-git-worktrees` and
  `visual-companion`, and each path is absent;
- `NOTICE.md` names Superpowers as an obligation, carries the MIT text, and no longer carries the stale
  similarity figures;
- the three chain surfaces reference each other by path, not by bare name (`test-surface-references.sh`
  family).

### Our own blind spot, written down before it bites

Superpowers' `checks.sh` admits its ordering gate is vacuous against an agent that writes via shell
heredoc, so `skill-called` is its deterministic floor. Ours is wider: **a scene can be mutated through
an MCP tool we did not list.** The tool list is a floor, not a fence, and the gate's evidential value
depends on that list staying current. Any scenario built on it says so.

## Not in this spec, and recorded so it is tracked

The Pioneer design assessed Superpowers' 13 skills. **Four of its declines are now void**, because the
surfaces they cited were deleted in the 2026-08-03 cut and the table was never re-run:

| Skill | Declined because | Today |
|---|---|---|
| `writing-skills` | `/unity-skillify`, `/unity-learn`, `/unity-skill-stocktake` are richer | all three gone |
| `dispatching-parallel-agents` | `/unity-team` | gone |
| `finishing-a-development-branch` | `unity-git-master` | gone |
| `executing-plans` | `/unity-workflow` Phase 3 | **addressed here** (D6) |
| `test-driven-development` | marked **"Adapt"** | never done |
| `receiving-code-review` | marked **"Adapt"** | never done |
| `requesting-code-review` | `/unity-review`, `unity-reviewer` | both exist — **still valid** |
| `using-git-worktrees` | refused, measured Unity reason | **valid**, but unrecorded (D10) |

Re-running that table is its own spec. It is named here so "complete" is a tracked commitment rather
than a feeling.

Also carried, not addressed: `save-system` has **zero inbound edges** anywhere in the payload — no
agent and no command names it. Whether it survives the cut criterion is a separate question.

## Risks

- **`unity-execution` may not earn its place.** Stated in D6 with the honest fallback: fold it into
  `subagent-driven-implementation` rather than ship a thin surface.
- **Adapting text can carry a clause that does not fit Unity.** The countermeasure is that each adapted
  section names the scenario that would catch it, and that D3 is proof the reading is being done.
- **Deleting two commands removes typed entry points.** Mitigated by the measurement (the chain already
  pulls without them) and by the owner's standing requirement. If it proves wrong, the fix is a thin
  alias, not a restored phase — a restored phase is the second definition all over again.
- **The rename invalidates the one measurement we have.** `brainstorming-fires-on-new-mechanic` exists
  to re-establish it, and until it runs, the head-to-head win is a claim about the old name.
