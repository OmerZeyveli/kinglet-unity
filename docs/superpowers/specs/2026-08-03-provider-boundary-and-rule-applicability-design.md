# Provider boundary and rule applicability — design

**Date:** 2026-08-03

**Status:** approved design, spec awaiting owner review

**Decides:** how Kinglet coexists with an external process provider, and how it stops asserting an
architecture the target project does not use

**Does not decide:** the trigger-description rewrite (deferred, see "Deferred, with triggers"), the
Wave 2 discipline skills, or whether the 103-surface pool should be cut

**Relates to:** `2026-07-23-kinglet-platform-design.md` (§"Process provider interoperability"),
`2026-07-29-kinglet-pioneer-design.md` (§"Relationship to Superpowers", Break 2, Item 2),
`2026-08-02-agent-context-and-verification-design.md` (approach A),
`2026-07-30-surface-trigger-rules.md` (amended here, not executed here)

---

## The question

The owner asked how to bring Superpowers' structure into Kinglet. The answer turned out to be
already written, in two places, and the interesting part was what the existing designs got wrong.

`2026-07-23-kinglet-platform-design.md` already settles the relationship: Superpowers is an
**optional process provider** behind a contract, never a runtime dependency, proposed by setup and
approved by the user. `2026-07-29-kinglet-pioneer-design.md` already settles the per-skill
disposition: nine not taken, one refused, three to adapt in Wave 2.

So the open question was never "vendor or declare". It was two narrower things:

1. Where the boundary between provider and Kinglet actually falls, given that the one head-to-head
   measurement we have says the provider wins the most ordinary request in game development.
2. What Kinglet does about the fact that the rules it ships assert an architecture the only real
   game using it does not have.

## Evidence

### The head-to-head, and what it actually measured

`docs/research/pioneer/smoke-pass.md` §10, on a fresh URP fixture:

| Prompt | Provider enabled | Provider disabled |
|---|---|---|
| *"Let's add a double jump to the player."* | `superpowers:brainstorming` | **`/unity-feature`** |
| *"The enemy AI keeps walking through walls, can you fix it?"* | not run | **`unity-fixer`** |
| *"I want to check this project for performance problems."* | not run | **`unity-optimize`** |

§10's own conclusion: Pioneer's descriptions "are good enough to be selected when uncontested."

The owner's decision, 2026-08-03: **the provider winning that prompt is correct behaviour, not a
defect.** An unscoped idea belongs in the discovery stage, and discovery is the provider's stage
under the platform contract.

That decision reframes the loss. It was not `/unity-feature` losing to `brainstorming` — those are
not the same stage. It was `/unity-interview`, Kinglet's own built-in discovery surface, losing —
and `2026-07-30-surface-trigger-rules.md` never considered `/unity-interview` at all. It appears in
none of the six families and none of the five shadow pairs.

### The rules assert an architecture that is not there

Measured in `Endless-Evolution/Assets`, the only real game project using this toolkit:

| Symbol | Files |
|---|---|
| `VContainer` | **0** |
| `MessagePipe` | **0** |
| `UniTask` | **1** |
| `StartCoroutine` | **130** |

`.claude/rules/architecture.md` mandates the first three plus Model-View-System.
`.claude/rules/unity-specifics.md` bans coroutines. Endless-Evolution's `CLAUDE.md` carries a
section titled *"Engineering Reality (this project, not Kinglet's defaults)"* whose entire job is
to neutralise its own toolkit.

This is the single largest source of wrong guidance Kinglet ships.

### What the auto-loaded layer actually does — measured, not assumed

`docs/research/pioneer/field-notes.md` §87, 2026-08-03: twelve headless runs, two prompts, three
attempts each, with and without `architecture.md` present.

All twelve converged on the same design. Neither arm proposed VContainer, MessagePipe, UniTask or
MVS. In the arm where the file was **deleted**, one run wrote:

> *"Follow this project's architecture, not `.claude/rules/architecture.md` (no VContainer/MessagePipe
> here — see CLAUDE.md 'Engineering Reality')"*

It rejected a file that was not there, because `CLAUDE.md` named it.

**The finding that governs this design: the bulk auto-loaded layer steered nothing; one precedence
sentence steered everything.** §87's own conclusion — "size is not influence, and I had used size as
a proxy for harm" — is why this design writes a sentence rather than deleting a file, and why it
ships no enforcement blocks.

### The measurement that cannot carry the weight put on it

`2026-08-02-agent-context-and-verification-design.md` records that Kinglet's 28 agents, 36 commands
and 39 skills were invoked **zero times across six sessions**, and attributes it to prescriptive
briefs.

That number is more confounded than the spec admits. `Endless-Evolution/docs/hardening/wave-9-prompts.md`
states, verbatim:

> *"CORRECTED MID-WAVE: YOU CANNOT INVOKE AN AGENT, so do not try. Your tool surface is Bash, Read,
> Write, Edit, Skill and ToolSearch plus the todo-list tools; none spawns a subagent, and
> `unity-reviewer` is an agent under `.claude/agents/`, not one of the 39 skills, so `Skill` does not
> reach it."*

So 28 of the surfaces were structurally unreachable, and slash commands are not reachable from a
headless brief either. The number reduces to: *zero of 39 skills, under briefs that prescribed the
method, in a project whose `CLAUDE.md` explicitly overrides what several of those skills encode.*

The same file records the other half, which is easy to miss: *"the hooks and rules have been
load-bearing throughout."*

**Nothing in this design rests on that zero, in either direction.** Re-measuring it honestly is
listed under "Deferred, with triggers" as the gate for the descriptive-layer work.

### A document did catch a defect

`2026-08-02`'s evidence section says "None was caught by a document." That is not quite true.
`Endless-Evolution/docs/hardening/track-4-report.md:2517-2523`: unable to invoke `unity-reviewer` as
an agent, a session walked `.claude/agents/unity-reviewer.md`'s checklist **as a document** and found
that `WaitFor` computed its timeout from `Time.time` — scaled — so a leaked `Time.timeScale = 0`
would hang the run instead of failing with its message. Changed to `Time.unscaledTime`.

The reading this design takes from it: the descriptive layer's value is as **checklists a human or
an agent can walk**, not as content to wrap in enforcement and not as dead weight to delete.

## Decision

Four changes, in this order. Two mechanisms are new; two existing designs are amended rather than
executed as written.

### 1. Rule applicability is detected and declared, never assumed

`scripts/generate-claude-md.sh` gains detection for `VContainer`, `MessagePipe` and `UniTask`, and a
counter-signal count of `StartCoroutine`. The marked region gains one section stating which rules
bind.

**What is scanned, stated precisely, because the obvious implementation inverts the answer.** The
primary signal is `Packages/manifest.json`. The secondary signal is a source scan of **`Assets/`
only, excluding vendored subtrees** — never `Packages/`, never `Library/`. Scanning `Packages/` would
find the dependency's own source and report every project as using it. Vendored subtrees matter for
the same reason at smaller scale: Endless-Evolution carries 923 third-party `.cs` files under
`Assets/Extensions/`, and its root `.ignore` exists precisely because they drown first-party hits. A
symbol found only in vendored code is not the project using it.

The rule files are **not deleted and not conditionally installed.** §87 measured that deleting one
changed nothing while a sentence naming it changed everything. Deletion also costs the 31% of
`architecture.md` that is architecture-agnostic and that the measured answers used —
`ScriptableObjects for Static Data`, `Input System Architecture`, `No God Objects`,
`Composition Over Inheritance`.

Emitted shape, brownfield with contrary evidence:

> **Architecture stack — detected, not assumed**
>
> Detected in this project: VContainer no, MessagePipe no, UniTask 1 file; 130 files use
> `StartCoroutine`.
>
> Therefore `.claude/rules/architecture.md` and the "No Coroutines — Use UniTask" section of
> `unity-specifics.md` **do not bind here.** Follow the architecture this project actually uses.
> `csharp-unity.md`, `performance.md`, `serialization.md` and the rest of `unity-specifics.md`
> **bind in full.**

Detected the other way, the sentence inverts and the rules bind.

Three cases, decided:

- **Greenfield (no scripts yet):** the rules **bind**, and the sentence says *recommended for this
  new project* rather than *detected*. In an empty project the toolkit's default stack is a
  legitimate recommendation, not a false assertion about existing code.
- **Mixed evidence:** print the counts, take **no side**, and say the project decides. Silently
  picking a side is the failure this section exists to prevent.
- **Detection fails:** emit no sentence at all. Today's behaviour is unchanged. A wrong detection is
  worse than none.

### 2. A written plan is a first-class input to the engineering track

`/unity-workflow`'s `args` becomes `feature-description-or-plan-path`. When the argument resolves to
a file, or a plan exists for the named feature, Phase 1 (Clarify) is skipped and the plan is adopted.

Search order: explicit path → `docs/features/<slug>/plan.md` → `docs/superpowers/plans/*<slug>*.md` →
`docs/design/<system>.md`. The adopted source path is recorded in the phase output.

Acceptance criteria are carried **verbatim**. Pioneer Item 2's rule holds unchanged: a paraphrase is
a silent design change.

This is not new scope. It is Pioneer Item 2 (Break 2 — "the two tracks do not connect") with the
source set widened to include a process provider's output alongside a GDD. A provider's plan is as
legitimate an input as a design document.

### 3. Provider ownership is declared in one sentence

When setup detects a compatible provider **and** the user approves it, the marked region gains:

> *"Discovery and written planning in this project are owned by `superpowers`. `/unity-interview`
> yields to it and does not compete for the discovery stage."*

Not a routing block. §87 is explicit that the bulk layer did not steer and the single precedence
sentence did.

Two platform-design constraints hold unchanged: Kinglet *"does not copy, uninstall, disable, or
secretly shadow the detected plugin"*, and provider choice is *"project configuration, not hidden
client state"* — so the sentence lands in the git-tracked `CLAUDE.md` and the user's global settings
are never written.

`install.sh` reads nothing from `$HOME` today. This detection is its first user-global read, and it
is therefore constrained: read-only, path overridable for tests, and benign in absence.

`scripts/studio-doctor.sh` gains a check: a block declaring a provider that is not installed warns
and offers regeneration without it. That is the platform design's *"doctor offers the built-in
provider as an explicit fallback"* made concrete.

### 4. The trigger amendment is deferred, and narrowed when it runs

Its gate is stated once, in "Deferred, with triggers" below, and is two conditions rather than one:
(2) shipped, so the second entry path this section adds refers to something that exists, **and** the
invocation measurement corrected. The amendments themselves are recorded here so that whoever opens
that gate transcribes rather than re-derives — the same discipline `2026-07-30-surface-trigger-rules.md`
imposed on its own Task 3.

`2026-07-30-surface-trigger-rules.md` is amended, not executed. Three changes, to be applied when
the gate below opens:

- **`/unity-interview` becomes its own family.** It is absent from all six families and five shadow
  pairs today, and it is the surface that actually lost the head-to-head. Its trigger owns the
  discovery stage and yields when a provider is declared.
- **`/unity-feature` gains a second entry path and loses none.** The earlier draft of this design
  re-pointed it at already-scoped work only. That would have surrendered a first-try win measured in
  §10 before its replacement existed. Corrected: *either an already-scoped plan, spec or GDD, **or** a
  direct feature request.*
- **§8's sanity check yields two verdicts, not one.** With a provider configured: discovery first.
  Without one: `/unity-feature`, exactly as §10 measured.

§8's unresolved Prompt B — *"the player falls through the floor sometimes when landing"* — resolves
under the stage axis where it did not resolve under the family axis: it is a debugging-stage request,
`/unity-fix`. The spec recorded it as unresolvable because the axis was wrong, not because the prompt
was ambiguous.

## What this design does not do, and why

| Not done | Why |
|---|---|
| Enforcement blocks (`HARD-GATE`, mandatory checklist→todo, red-flag tables) | Enforcement multiplies the content it wraps, and §"the rules assert an architecture that is not there" shows the content is wrong for real projects. §87 also measured that the mechanism enforcement would add is one a precedence sentence already provides. Revisit only after (1) ships. |
| A `superpowers` origin in `provenance.tsv` | No file in this design derives from Superpowers. Widening the origin enum with no rows to use it is dead code. It lands in Wave 2 with the first adapted file, as `2026-07-29`'s Item 7 specifies. |
| The full 103-surface description rewrite | Already deferred by its own plan's Task 3. The gate is below. |
| The Wave 2 discipline skills (TDD, systematic debugging, receiving code review) | `2026-08-02`'s rule holds: nothing unproven ships. The gate is the corrected invocation measurement. |
| Cutting the 103-surface pool | A separate decision, deferred by `2026-07-29` and untouched here. |

## Deferred, with triggers

Neither of these is a promise to revisit. Each names the measurement that opens it.

- **The trigger rewrite (Task 3/4/5 of Wave 1b-2), amended per §4 above.** Gate, both conditions:
  **(a)** decision (2) shipped, so `/unity-feature`'s new "already-scoped plan" entry path refers to a
  mechanism that exists rather than to an intention; and **(b)** the invocation measurement re-run
  honestly — one session, a thin brief that names the skills and omits the method, the `Agent` tool
  present, on Endless-Evolution. As recorded, the zero cannot support the weight being put on it in
  either direction.
- **Enforcement form.** Gate: (1) shipped, and a project where the declared rules are the rules that
  actually apply. Enforcement on wrong content is worse than no enforcement.

## Error handling

| Condition | Behaviour |
|---|---|
| `Packages/manifest.json` unreadable or absent | Emit no stack sentence. Today's behaviour unchanged. A wrong detection is worse than none. |
| Mixed evidence (some VContainer, mostly not) | Print the counts, take no side, state that the project decides. |
| Greenfield project | Sentence says *recommended for this new project*, never *detected*. |
| Named plan file missing or unreadable | **Hard stop.** Never degrade silently into conversation — Pioneer Item 1's rule. |
| Plan found but carries no acceptance criteria | Adopt what is there and say explicitly what was missing. Never invent criteria. |
| Multiple plans match the slug | List them and ask. Never silently take the newest. |
| Block declares a provider that is not installed | `studio-doctor.sh` warns and offers regeneration without it. |
| Provider detected but user declines | No sentence. `/unity-interview` behaves as today. |

## Testing

**Mechanically checkable, and new:**

- `tests/test-rule-applicability.sh` — all three cases (binds / does not bind / greenfield), plus
  detection failure emitting nothing. Needs a fixture variant carrying VContainer in
  `Packages/manifest.json` and in source; `tests/fixtures/mkproject.sh` currently offers
  `urp|builtin|bare|dirty` only.
- The `--facts-only` / full-generation byte-identity property must hold with the new section
  included. Both paths already run through the single `emit_marked_region` producer; they disagreed
  before `89c661c` and the regression is cheap to reintroduce.
- Provider detection under an overridden user-config path, present and absent.
- `studio-doctor.sh`'s stale-provider warning.

**Must stay green:** `tests/run-tests.sh` with every test file present in its output — count the
`--- test-*.sh ---` headers, the summary line is not evidence — and `scripts/check-provenance.sh`.
Editing `.claude/` drifts `migration/baseline-inventory.json`; regenerate in a separate commit.

**Not testable, and not claimed:** whether `/unity-workflow` actually adopts a plan it was handed,
and whether the corrected stack sentence changes what the model proposes. Both are prompt behaviour.
Per `2026-07-29`'s own rule, claiming the suite covers them would be exactly the green-but-meaningless
assertion this repository's history is a record of finding and removing.

**The honest proof is §87's method:** a fixture, headless runs, two prompts times three attempts,
with and without the corrected sentence. A negative result is a real result — on 2026-08-03 that
exact experiment retired a confident architectural argument in twenty minutes.

## Success criteria

1. `tests/test-rule-applicability.sh` passes; `run-tests.sh` green with every file present;
   `check-provenance.sh` reports `provenance OK`; baseline regenerated in its own commit.
2. Generating against a project shaped like Endless-Evolution emits *does not bind* for
   `architecture.md`; generating against a VContainer project emits *binds in full*; generating
   against an empty project emits *recommended*.
3. An A/B by §87's method reports whether the corrected sentence changes the architecture the model
   proposes — **whatever the answer is**, written into `field-notes.md`.
4. `/unity-workflow` handed a plan path records which plan it adopted, and carries its acceptance
   criteria verbatim.
5. A project with a provider installed and approved carries the one-sentence declaration; one
   without carries nothing new.

## Open questions

- **Does the trigger rewrite happen at all, or does the deletion argument win first?** An independent
  review argued that cutting the surface pool from 103 to roughly ten is strictly cheaper than
  rewriting 64 descriptions and more likely to fix selection, because most of the tie-breaking
  problem is population size. This design does not decide it. The corrected invocation measurement
  informs both.
- **Does `/unity-interview` survive as a surface once a provider is the norm?** It is Kinglet's
  built-in discovery provider and the platform design requires standalone completeness, so it cannot
  simply be cut — but if a provider is present in every real installation, its cost is being paid for
  a case that never occurs.
