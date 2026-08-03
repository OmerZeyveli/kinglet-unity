# Surface cut and process chain — design

**Date:** 2026-08-03
**Status:** approved for planning
**Supersedes in part:** the deferral row *"Consolidating the 103-surface pool → a separate decision"* in
`docs/superpowers/plans/2026-07-30-kinglet-pioneer-wave-1b2-make-it-findable.md`. That decision has now
been made by the operator. This document is the judgement the deferral was waiting for.

---

## Why this exists

`docs/research/pioneer/smoke-pass.md` §4 measured the defect: asked *"Let's add a double jump to the
player"*, **not one of Pioneer's 36 commands, 28 agents or 39 skills was selected.** A competing plugin
won, on an empty fixture and again on a real 1073-script project.

§10 then softened the diagnosis, and the softening matters: with the competitor disabled at project
scope, three prompts selected three correct Kinglet surfaces on the first try. So the surfaces *can* be
selected. They lose head-to-head to trigger-phrased descriptions, and they are diluted by a pool of 103.

Two follow-ups from 2026-08-03 refine it further:

- Five natural-language probes in Endless Evolution produced five correct answers and zero skill
  invocations. This is **not** a selection failure: all five were questions, and the auto-loading spine
  rules answered them correctly with zero tool calls. A question that a rule answers should not select a
  surface. Task-shaped prompts still do.
- Field note §36: across 17,316 lines of documentation produced on a real project, `docs/design/`,
  `docs/production/` and `docs/adr/` were used **zero times out of three**. The design/production track
  ships a documentation layer nothing consumed.

Together these say the problem is not that surfaces cannot be selected. It is that **most of them should
not exist**, and the ones that should are described in the wrong grammar.

---

## Decision 1 — Cut the pool from 103 to 32

### The criterion

> **A surface survives only if it does something the model cannot do unaided.**

The five EE probes are the evidence for the negative half: with correct rules loaded, the model answered
serialization, DI-binding, and Addressables questions correctly on its own. A surface that restates what
an auto-loading rule already says is not neutral — it is one more near-duplicate in a selection pool that
§4 measured as already too crowded to win.

The positive half is equally concrete: an agent that drives the Unity Editor over MCP, reads the real
console, or captures real profiler frames does something no amount of reasoning substitutes for. Those
survive.

### Skills: 39 → 13

**Kept (10 existing):**

| Skill | Justification |
|---|---|
| `unity-mcp-patterns` | No rule covers the MCP bridge. Named by five engineering agents. |
| `physics` | The most-referenced skill in the toolkit — 15 surfaces name it. |
| `input-system` | `pc-console.md` points at it explicitly for `DeviceDetector`. |
| `addressables` | Real API surface, no rule coverage. |
| `assembly-definitions` | Named by seven agents; `architecture.md` gives it one line. |
| `save-system` | In use on a real project; reached by an EE probe. |
| `urp-pipeline` | Rendering specifics `pc-console.md` refers to but does not carry. |
| `object-pooling` | Loaded by three kept agents; `performance.md` gives it one line. |
| `state-machine` | Loaded by kept agents; no rule coverage. |
| `deep-interview` | The ambiguity gate — see Decision 4, where it is rewritten as a chain link. |

**Added (3 new process skills)** — see Decision 4.

**Removed (29),** in three groups:

1. **Nine genre templates** — `match3`, `rpg`, `puzzle`, `topdown`, `platformer-2d`, `idle-clicker`,
   `inventory-system`, `dialogue-system`, `procedural-generation`. The model knows these genres. They
   exist to be selected, and being selected is the scarce resource.
2. **Rule duplicates** — `serialization-safety`, `event-systems`, `scriptable-objects` and the rest of
   the set Correction 2a in the 1b-2 plan recorded as consolidation evidence. The serialization probe
   settled this empirically: the rule answered, the skill was never invoked.
3. **Orphans and toolkit self-reference** — `commit-trailers`, `hud-statusline`, `learner`, `navmesh`,
   `character-controller`, `cinemachine`, `dotween`, `odin-inspector`, `shader-graph`, `textmeshpro`,
   `ui-toolkit`, `unitask`, `vcontainer`, `animation`, `audio`, `unity-instincts`, `model-routing`.
   Several are named by nobody at all; the rest are package-conditional and belong behind detection, not
   in a permanent pool.

### Agents: 28 → 8

**Kept:** `unity-coder`, `unity-prototyper`, `unity-fixer`, `unity-optimizer`, `unity-scene-builder`,
`unity-ui-builder`, `unity-test-runner`, `unity-reviewer`.

Seven of the eight drive the Editor over MCP — building scenes, reading the real console, capturing real
profiler frames, running real tests. That is the criterion's positive half, met directly.
`unity-reviewer` is the one read-only survivor, kept because `/unity-review` routes to it and because a
Unity-aware review catches lifecycle and serialization faults a general reviewer does not.

**Removed (20):**

- **Eight design/production agents** — `creative-director`, `game-designer`, `level-designer`,
  `narrative-director`, `systems-designer`, `technical-director`, `world-builder`, `writer`. Field note
  §36: their output directories were used zero of three on the only real project this toolkit has met.
  This is the single best-measured cut in the document.
- **Three speed variants** — `unity-coder-lite`, `unity-fixer-lite`, `unity-linter`. They twin an
  existing surface on a cost axis, which doubles the pool while giving the selector nothing to
  discriminate on. The 1b-2 rules document already flagged `unity-linter` as consolidation evidence for
  exactly this reason (§9, "A finding, not a blocker").
- **Nine specialists** — `unity-build-runner`, `unity-critic`, `unity-git-master`, `unity-migrator`,
  `unity-network-dev`, `unity-scout`, `unity-security-reviewer`, `unity-shader-dev`, `unity-verifier`.

Cutting the eight design agents strands eight genre skills by itself — a single chain through two
layers, not two separate judgements.

### Commands: 36 → 11

**Kept:** `unity-workflow`, `unity-init`, `unity-doctor`, `unity-feature`, `unity-fix`, `unity-review`,
`unity-test`, `unity-optimize`, `unity-prototype`, `unity-scene`, `unity-ui`.

Every surviving agent has exactly one command that reaches it, plus setup and diagnosis. That invariant
is deliberate: an agent with no command is reachable only by a dispatching model, which §1 of the trigger
rules identifies as the weaker of the two selection paths. `unity-test` and `unity-optimize` are kept for
that reason — `unity-test-runner` and `unity-optimizer` survive, so a user-facing trigger for each must
survive too. Keeping `/unity-test` is also what makes Decision 4's `verification-before-completion` a
skill with somewhere to hand off to.

**Removed (25):** the nine Donchitos production commands (`brainstorm`, `design-review`, `design-system`,
`estimate`, `map-systems`, `milestone-review`, `retrospective`, `scope-check`, `sprint-plan`) per §36,
plus the toolkit's self-referential commands (`unity-skillify`, `unity-skill-stocktake`,
`unity-instincts`, `unity-learn`, `unity-sessions`, `unity-session-save`, `unity-session-resume`,
`unity-team`, `unity-ralph`, `unity-audit`, `unity-interview`), plus the commands whose agents were cut
(`unity-build`, `unity-migrate`, `unity-network`, `unity-shader`), plus `unity-profile`.

`unity-profile` is the one command removed while its agent survives, and it is a deliberate collapse: the
trigger rules' §5 splits `/unity-optimize` (fix a known complaint) from `/unity-profile` (measure first) on
a phase-of-work axis, then records in the same document that the two "could both look valid" for an
ambivalent request. Both route to the same agent. Collapsing them to `/unity-optimize` removes a tie the
rules document could not fully resolve, which is precisely what this cut is for.

**A contested cut, recorded rather than hidden.** `/design-review` is removed, and the operator named
that exact phrase as behaviour they valued in an earlier toolkit. The reading this document takes is that
the *behaviour* they described — the assistant proactively offering the next step — is Decision 5, not a
command, and that it is better served through the surviving `unity-review`. If that reading is wrong,
`/design-review` returns and this paragraph is the record of why it left.

### The reference cascade is real work

`tests/test-skill-discovery.sh` enforces that every skill an agent or command names by path exists.
Surviving agents name removed skills — `unity-prototyper` loads `character-controller`, `unity-ui-builder`
loads `textmeshpro` and `ui-toolkit`, `unity-doctor` names a long package list. Every such reference must
be edited out in the same change that removes the skill, or the suite fails. This is mechanical but it is
not free, and it is the step most likely to be under-estimated.

---

## Decision 2 — Re-base provenance from vendoring to attribution

Kinglet's surfaces stop being vendored copies and become ours. We will edit them freely, rewrite them for
an agent reader rather than a human one, and add, remove, or re-link them as the design requires.

**What changes:**

- `provenance.tsv` keeps its `origin` column (`ecu` / `donchitos` / `original`). Attribution is a
  standing MIT obligation and is not affected by editing.
- `status` becomes `modified` or `original` for essentially every surviving row. `verbatim` survives only
  where a file genuinely still matches upstream byte for byte.
- Removed paths move to `provenance-skip.tsv` as `rule=absent`, which is what keeps them from silently
  reappearing.
- `CREDITS.md` and `.claude/NOTICE.md` are unchanged in substance and remain the MIT compliance surface.

**What this costs, stated plainly.** `check-provenance.sh --online` currently re-fetches pinned upstream
and verifies recorded checksums. Once nearly every row is `modified`, that check verifies almost nothing,
and `CLAUDE.md`'s stated rationale — *"the only thing that makes a future diff against a newer ECU
tractable rather than archaeological"* — no longer holds. That capability is being deliberately traded
away. The offline half of the check (no rows without files, no files without rows, `rule=absent` paths
stay absent) keeps its full value and becomes the guard that matters.

`CLAUDE.md` must be updated to say this, in the same wave. A repo guide that describes a contract the repo
no longer honours is the exact defect class the smoke pass found three times (§6, §6c, and defect 1).

---

## Decision 3 — Give the survivors trigger-condition descriptions

In Claude Code a surface is selected from its `description` frontmatter and nothing else. Ours state what
the surface does; the description that beat us states when it applies.

`docs/superpowers/specs/2026-07-30-surface-trigger-rules.md` already contains finished, differentiated
descriptions for the colliding families, written in one sitting so the ties were visible on one page. It
was Task 2 of Wave 1b-2. **Task 3 — transcribing them into the files — never ran.** Verified 2026-08-03:
zero of 36 commands carry the designed text.

This decision revives Task 3, scoped to the survivors. Because the cut lands first, that scope falls from
62 files to roughly 19, and several of the collision families the rules document works hardest on
(`unity-coder`/`-lite`/`prototyper`; `unity-fixer`/`-lite`; the six-way review family) collapse to two or
three members, which makes them easier to keep distinct rather than harder.

Descriptions are **transcribed, not re-derived.** Where a family shrank, the surviving member keeps its
designed description with the now-absent sibling's disambiguating clause removed — the clause is dead
text once the sibling is gone, and leaving it in points at a surface that no longer exists.

---

## Decision 4 — Adopt Superpowers' chain, in our own words

Superpowers' value is not its individual skills. It is that each skill names the next one, and an
always-loaded entry skill establishes that a process skill is invoked *before* answering. Kinglet has
most of the pieces scattered inside `unity-workflow`'s phases; what it lacks is the linkage.

**Three new skills, written for an agent reader:**

| Skill | Fills |
|---|---|
| `using-kinglet` | The entry point and the chain map. States which surface handles which situation, and that a process surface is chosen before code is written. Also carries the proactive posture of Decision 5. |
| `systematic-debugging` | Kinglet has `unity-fixer` (an agent) but no *method*. Unity-flavoured: read the real console before theorising, reproduce before fixing, use `unity_reflect` for live API behaviour rather than recalled API behaviour. |
| `verification-before-completion` | Field note §36's conclusion — *"a documentation layer is worth what its verification is worth"*, and *"if only one of the two ships, ship the test."* Nothing in Kinglet currently states this as a rule an agent follows. |

**One rewritten:** `deep-interview` becomes the first link rather than a standalone gate. Its current
activation logic (specificity signals, exemptions, ambiguity score) is sound and is kept; what is added is
the handoff — on passing the gate, it names `/unity-workflow`; on failing it, it asks and stops.

**Carrier.** `using-kinglet` is injected at session start by a project-scoped `SessionStart` hook
(`matcher: startup|clear|compact`), the same mechanism Superpowers uses. This needs no plugin: a hook in
the project's `.claude/settings.json` is read exactly as a plugin's is.

Its job is **the chain and the posture, not selection.** Selection is Decision 3's work. This distinction
matters because an earlier reading of this session proposed injection *as* the selection fix, on the
mistaken belief that the five EE probes showed a selection failure. They did not. Injection is included
here for a different and narrower reason, and should be judged on that reason alone.

**Deliberately not adopted:** `writing-plans` (`unity-workflow` Phase 2 already does this, and Phase 1a
now accepts an existing plan as input), `subagent-driven-development` (Phase 3), `requesting-` and
`receiving-code-review` (`unity-review`), `using-git-worktrees` and `finishing-a-development-branch`
(general git process, not Unity-specific, and `unity-git-master` was cut).

---

## Decision 5 — Proactive next-step suggestion

The operator's stated want: an assistant that, having finished something, offers the sensible next step —
*"want me to run a review on this?"* — rather than waiting to be asked. This is what makes a small surface
pool usable without memorising names, and it is the half of the problem that trigger descriptions do not
solve: a description gets a surface selected when the user asks for something, but says nothing about what
happens when the user stops asking.

**Mechanism, smallest first:**

1. A **Suggest next** section in the body of each surviving command, naming the one or two surfaces that
   most often follow it. Body text, not frontmatter — this is instruction to the model mid-task, not
   selection metadata.
2. The posture stated once in `using-kinglet`: after completing a unit of work, name the next step and
   offer it; do not perform it unasked.

`.claude/hooks/stop-validate.sh` already exists and is a `Stop` hook. Whether the suggestion should also
fire from there is left to the plan, which must check what that hook currently does before extending it.

**The boundary:** offer, do not act. An assistant that silently starts a review after every edit is worse
than one that waits, and the toolkit already ships hooks that block rather than suggest.

---

## Success criteria

Measurable, and in the order they should be checked:

1. **The suite stays green at every commit**, with every test file present in the runner's output, and
   `check-provenance.sh` reporting `provenance OK`. Counted by name — the summary line is not evidence.
2. **Re-run smoke-pass §10's three prompts with the competitor *enabled*.** §10 won them only by disabling
   Superpowers at project scope. Winning them with it enabled is the honest proof that Decision 3 worked;
   anything less is winning by removing the opponent. Record the result whatever it is, in a new dated
   section of `smoke-pass.md`, beside the original.
3. **Re-run the serialization question probe.** The correct outcome is still *no skill invoked* — the rule
   answers it. If the cut or the chain causes a surface to be selected for a question a rule already
   answers, that is a regression, not a win.
4. **A prompt that completes a unit of work produces an offer,** not silence and not an unasked action.

Criterion 2 is the one that can fail honestly. If it does, the finding is that trigger phrasing is
insufficient against a well-tuned competitor, which is a real result and should be reported rather than
retried with a friendlier prompt.

---

## What this does not do

| Deferred | To | Why |
|---|---|---|
| Plugin packaging, marketplace, `/plugin update` | Indefinitely | Dropped. The team is multi-client (Antigravity, Copilot); a Claude Code plugin serves one of them. A project-installed `.claude/` plus `AGENTS.md` reaches all of them and enters the same registry. |
| Windows / macOS host passes | Subproject 0 | Already locked there. |
| Making re-installation safe over user customisation | The plan, as a named risk | Observed on 2026-08-03: a second install into Endless Evolution overwrote a customised hook and a `settings.json` key. Recovered by hand. This must be fixed before the toolkit is handed to anyone else, and it is a prerequisite for the install-by-prompt entry path, not for this cut. |
| A tagged release | Same | `main` carried a field-broken commit for part of 2026-08-03. "Install from `main`" is not safe until a tag names a state known to work. |
| Re-adding package-conditional skills behind detection | Later | `generate-claude-md.sh` already detects packages; wiring cut skills back in on detection is a separate, additive change. |

---

## Risks

- **The cascade is under-estimated.** Removing 74 surfaces touches `provenance.tsv`,
  `provenance-skip.tsv`, `migration/baseline-inventory.json` (each path tracked in two places),
  `tests/test-skill-discovery.sh`, the install receipt, and every surviving agent that names a removed
  skill. The baseline regenerator refuses when the predicted drift count is wrong, and that refusal is the
  designed safety net — predict with `--dry-run` first rather than guessing the number.
- **A smaller pool does not automatically win.** Criterion 2 tests this and can fail.
- **`using-kinglet` becomes noise if it is long.** Field note §87 measured that deleting an entire rule
  file changed none of twelve runs while one precedence sentence naming that file changed all of them.
  Size is not influence. This skill should be short enough to be read every session.
- **Removing a surface someone uses.** Every cut here is argued from measurement or from an explicit
  criterion, but the only real project this toolkit has met is one. `provenance-skip.tsv` records what
  left and why, so reversing a cut is a lookup rather than an excavation.
