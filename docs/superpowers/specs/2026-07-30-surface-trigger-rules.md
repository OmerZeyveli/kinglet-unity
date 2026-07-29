# Surface trigger-condition rules — Wave 1b-2, Task 2

Authority: `docs/superpowers/plans/2026-07-30-kinglet-pioneer-wave-1b2-make-it-findable.md`
("Authority" section, "Three corrections to the design, recorded", "The house style for a trigger
description", "Global Constraints"). Source material for current text: `.superpowers/sdd/surface-selection-survey.md`
and the actual `.claude/commands/*.md` / `.claude/agents/*.md` files read directly for this task.

This document designs the differentiation rules for six colliding families plus five command/agent
shadow pairs, **before** Task 3 touches any of their files. Task 3 transcribes the descriptions below
verbatim into frontmatter; it does not re-derive them. No `.claude/` file is changed by this task.

---

## 1. The command-versus-agent rule

**Adopted, with the survey's suggestion kept as the mechanism and its reasoning made explicit:**

> **Commands own the user-facing "let's do X" trigger. Shadow agents that are wrapped 1:1 by a
> command do not compete for that same trigger — their description leans on two things instead:
> (a) being invoked by name from their command, and (b) a standalone dispatch cue for the one case
> a command can't cover: a *supervising agent* (not a human typing a slash command) delegating work
> directly via the Task tool.**

Reasoning:

1. **A user never picks between `/unity-ui` and `unity-ui-builder`.** They type a command or they
   describe a screen in prose; either way the natural-language surface that should win is the
   command, because it is what shows up in the command palette and what the house-style examples
   in the plan are written against. If the shadow agent's description also chases "build a UI
   screen," the two are functionally identical strings and the model has no signal to prefer one —
   which is the exact "arbitrary selection among near-duplicates" failure mode Correction 3 in the
   plan warns about, just shrunk to a pair instead of a family of five.

2. **But the agent's description is not decorative.** Per the plan's "Note" under Task 2 point 1:
   Claude Code's agent auto-selection is also exercised by a *dispatching model* — e.g. `unity-workflow`,
   `unity-team`, or a supervising agent reasoning about which subagent to `Agent()`-launch for a
   sub-step — and that dispatch happens from the agent's description, not from whether a human typed
   the command. If the shadow agent's description is reduced to only "invoked by `/unity-x`", a
   dispatching model that is choosing an agent directly (never routing through the command file) has
   nothing to select on and may pick something else, or nothing.

3. **Resolution:** the shadow agent's description gets two clauses, in this order:
   - **Primary:** *"Invoked by `/unity-x`;"* — states the normal path, so it does not compete with
     the command on freeform user prompts.
   - **Secondary:** *"also selectable directly when \[the narrow, concrete condition that's true of
     the agent but not of arbitrary prose\]."* — gives the dispatching-model path something real to
     match. The secondary clause must name a condition specific enough that it does not just restate
     the command's trigger in different words (that would recreate the tie this rule exists to
     prevent).

This rule is decided once here and applied identically to all five shadow pairs in §9 — it is not
relitigated per pair.

---

## 2. Feature / prototype family — highest risk

**Members:** `/unity-feature`, `/unity-prototype`, `unity-coder`, `unity-coder-lite`, `unity-prototyper`.

**What each actually does, read from the files (not guessed from the name):**

- `/unity-feature` — routes to `unity-coder` by default, or `unity-coder-lite` on a `--quick` flag.
  It is the general "build this feature into the existing project" entry point.
- `/unity-prototype` — routes to `unity-prototyper` unconditionally. Its own description already
  says the differentiator: "One prompt to playable prototype."
- `unity-coder` (opus) — full architectural reasoning: new gameplay systems, multi-script features,
  correct namespace/asmdef placement, integrating into the existing project's architecture.
- `unity-coder-lite` (sonnet) — by its own "Good Fit For" list: a new field or method on an existing
  class, a component with 1-2 responsibilities, wiring an existing system to a new UI element. Its
  own "Not Good Fit For" list explicitly excludes multi-system features and new gameplay systems —
  that's `unity-coder`'s job.
- `unity-prototyper` (opus) — "the star agent": given a mechanic description, writes scripts, builds
  a *new* test scene from scratch via MCP (physics/colliders/camera), wires it end-to-end. It
  produces a standalone playable thing, not an addition to existing project structure.

**The real axis is not "scale" alone — it's two independent axes that this family conflates today:**

1. **Phase of work:** is this project-integrated feature work (extends what exists, respects
   existing architecture/scenes) or greenfield prototyping (a new, disposable, self-contained scene
   built to test a mechanic)?
2. **Scale, within the integrated-feature branch only:** trivial single-class tweak vs. a
   multi-system feature needing architectural decisions.

`unity-prototyper` sits alone on axis 1's "greenfield" side. `unity-coder` / `unity-coder-lite` split
axis 2 on the "integrated" side. This is what makes "let's add a double jump" resolve cleanly (see
§8): a double jump modifies an *existing* player controller — it is integrated work, not a new scene —
so it never even reaches `unity-prototyper`'s branch.

**Proposed descriptions:**

`/unity-feature`
> "Use when the user wants to add or extend a feature in the existing Unity project — a new
> mechanic, system, or component that plugs into scripts and scenes that already exist. Routes to
> the full architectural implementer by default, or a lighter/faster path for simple additions."

`unity-coder`
> "Use for feature work that touches the project's existing architecture — a new gameplay system,
> a multi-script feature, or anything requiring an architectural decision (new Model/System/View
> split, new VContainer registration, cross-system messaging). Writes C# with correct
> namespace/asmdef placement and wires it into the scene via MCP. Invoked by `/unity-feature`; also
> selectable directly when a dispatching agent needs full architectural reasoning for a non-trivial
> addition, not a one-line change."

`unity-coder-lite`
> "Use for a small, self-contained addition to an existing script or scene — a new field, a new
> method, a component with one or two responsibilities, wiring an existing system to a new UI
> element. Not for new gameplay systems or anything needing an architectural decision (use
> `unity-coder` for that). Invoked by `/unity-feature --quick`; also selectable directly when a
> dispatching agent has already scoped the change to something this small."

`/unity-prototype`
> "Use when the user wants to go from a mechanic description straight to something playable — a new,
> self-contained test scene built from scratch to try an idea, not an addition to the existing
> project. The one-prompt path from idea to hit-play-and-test-it."

`unity-prototyper`
> "Use to build a new, disposable test scene end-to-end from a mechanic description — scripts,
> physics/colliders/camera, and wiring, all via MCP, with no dependency on the project's existing
> scenes or architecture. Invoked by `/unity-prototype`; also selectable directly when a dispatching
> agent needs a throwaway playable scene to validate a mechanic, rather than an addition to the real
> project (use `unity-coder` for that)."

---

## 3. Bug-fixing family

**Members:** `/unity-fix`, `unity-fixer`, `unity-fixer-lite`.

**Differentiator axis:** depth of investigation required, exactly as the plan's worked example
states it. `unity-fixer-lite`'s own "Good Fit For" list is concrete: missing `using`, a typo in a
field/method name, a missing `[SerializeField]`, an obvious unassigned reference, a simple
compilation error, a missing `[FormerlySerializedAs]`. Its "Not Good Fit For" list hands off
explicitly: complex bugs needing deep investigation, intermittent issues/race conditions,
physics/timing bugs, multi-file bugs, anything needing profiling — that is `unity-fixer`'s territory.

**Proposed descriptions:**

`/unity-fix`
> "Use when the user reports a bug, error, crash, or something not working in Unity — before
> proposing a fix from memory. Reads the actual console output and verifies the fix via MCP rather
> than guessing. Routes to deep investigation by default, or a quick path for obviously simple
> fixes."

`unity-fixer`
> "Use for a bug whose cause isn't obvious yet — needs investigation across multiple possible
> causes (execution order, coroutine lifecycle, destroyed-object access, live API behavior via
> `unity_reflect`), not a one-line fix. Invoked by `/unity-fix`; also selectable directly when a
> dispatching agent has an unresolved bug report with no clear single cause."

`unity-fixer-lite`
> "Use for a bug with an obvious, single cause — a missing reference, a typo in a name, a missing
> `using`, a missing `[SerializeField]` or `[FormerlySerializedAs]`, a simple compile error. Not for
> intermittent issues, race conditions, or anything needing profiling (use `unity-fixer`). Invoked
> by `/unity-fix --quick`; also selectable directly when a dispatching agent has already isolated the
> cause to one obvious thing."

---

## 4. Review / quality family

**Members:** `/unity-review`, `unity-reviewer`, `unity-security-reviewer`, `unity-critic`,
`unity-verifier`, `unity-linter`.

**Reading each file, these are six genuinely different things — not two wearing six names.** The
depth/scope differentiator, read off the actual bodies:

| Surface | Model | What it reviews | Read-only? | Loop? |
|---|---|---|---|---|
| `unity-linter` | haiku | Written code against the project's style/rule checklist, fast, no deep reasoning | yes | no |
| `unity-reviewer` | sonnet | Written code — correctness, performance, serialization, architecture, Unity pitfalls | yes | no |
| `unity-security-reviewer` | sonnet | Written code — security only: PlayerPrefs secrets, unencrypted saves, hardcoded keys, insecure network calls, cert pinning, debug-in-release | yes | no |
| `unity-critic` | opus | An implementation **plan**, before any code is written — risk, missed edge cases, over-engineering | yes | no |
| `unity-verifier` | opus | Recent code changes, and it **fixes** what it finds, re-checking up to 3 iterations | no (writes) | yes, bounded |

Five real distinctions, on three separable axes: **phase** (plan vs. written code), **focus**
(general quality vs. security-specific), and **whether it stops at reporting or loops until fixed**.
`unity-linter` and `unity-reviewer` are the pair closest to colliding — both are general-purpose,
read-only reviews of written code — and the honest differentiator between them is speed/cost, not
depth of finding: `unity-linter` is a fast haiku pass for a mechanical checklist, `unity-reviewer` is
the sonnet pass for judgment calls the checklist can't automate. That is a real distinction (a linter
that never reasons versus a reviewer that does), not a strained one, so all six stay.

**Proposed descriptions:**

`/unity-review`
> "Use after C# code changes are written and before they're considered done, when the user asks for
> a code review or a check before merging/committing. Runs a Unity-aware review — serialization
> safety, performance, architecture — at standard depth by default, or opus-level architectural
> depth on request."

`unity-reviewer`
> "Use after C# code changes are written and before they're considered done — checks for
> Unity-specific correctness, performance, and serialization pitfalls a general code reviewer would
> miss (lifecycle ordering, GC in hot paths, `CompareTag`, cached lookups, editor/runtime leaks).
> Read-only: reports issues with file:line references, does not fix them. Invoked by `/unity-review`;
> also selectable directly when a dispatching agent needs a standard-depth review of written code."

`unity-security-reviewer`
> "Use when the user asks for a security check, or before a release/build, on code or save/network
> logic — not for general code quality (use `unity-reviewer` for that). Checks for PlayerPrefs
> secrets, unencrypted save data, hardcoded API keys, insecure network calls, missing certificate
> pinning, and debug builds shipped in release config. Read-only."

`unity-critic`
> "Use on an implementation plan, before any code is written — challenges the plan itself for risks,
> missed edge cases, over-engineering, and Unity-specific gotchas. Not for reviewing code that
> already exists (use `unity-reviewer`). Read-only; default posture is skeptical, not approving."

`unity-verifier`
> "Use after code changes when the user wants them checked *and* fixed, not just reported — reviews
> recent changes, applies fixes for what it finds, and re-checks itself for up to 3 iterations until
> clean. The only reviewer in this family that writes files. Invoked by `/unity-workflow` and
> embeddable in any command that needs a bounded fix loop instead of a one-shot report."

`unity-linter`
> "Use for a fast, mechanical pass over written code against the project's rules — no architectural
> judgment, just checklist violations (naming, serialization attributes, banned APIs) — when speed
> matters more than depth. Read-only. Not a substitute for `unity-reviewer` on anything requiring
> judgment."

---

## 5. Performance family

**Members:** `/unity-optimize`, `/unity-profile`, `unity-optimizer`.

**What's actually in the files:** both commands route to the same agent, `unity-optimizer`. The
current descriptions already blur profile-vs-optimize (survey's own hazard note). Reading the
command bodies: `/unity-optimize` frames around "optimize the project's performance, focus area: X"
— an action verb, implying the user already believes there's a problem to fix. `/unity-profile`
frames around "run a deep profiling session, focus: X" — a measurement request, no assumption of a
known problem yet.

**Differentiator axis: phase of work — diagnose (measure first, no assumption of cause) vs. act
(already suspects a bottleneck and wants it fixed).** Since both share one backing agent, there is no
agent-level ambiguity to resolve here — only the two commands need to not collide with each other,
and the agent's description should reflect that it does both, because it genuinely does.

**Proposed descriptions:**

`/unity-optimize`
> "Use when the user has a specific performance complaint — stuttering, frame drops, a known slow
> area — and wants it diagnosed and fixed. Profiles via MCP to confirm the cause, then applies the
> fix, rather than fixing from a guess."

`/unity-profile`
> "Use when the user wants performance data before deciding what to fix — no known bottleneck yet, or
> a general 'how is performance' check. Captures frames via MCP and reports CPU/GPU timing, memory,
> and rendering stats; does not apply fixes on its own."

`unity-optimizer`
> "Use to profile and fix Unity performance issues — CPU/GPU bottlenecks, GC spikes, draw-call
> issues, shader variant bloat — using the MCP profiler for real frame data rather than guessing.
> Invoked by both `/unity-optimize` (fix a known complaint) and `/unity-profile` (measure first);
> also selectable directly when a dispatching agent needs profiler-backed performance work of either
> kind."

---

## 6. Testing family

**Members:** `/unity-test`, `unity-test-runner`.

This is a shadow pair (command wraps one agent), so it also follows §1's rule, not a fresh axis.

**Proposed descriptions:**

`/unity-test`
> "Use when the user wants tests written or run — for a specific area if named, otherwise for the
> most critical untested code paths. Writes EditMode/PlayMode tests and executes them via MCP,
> reporting real results rather than assuming coverage."

`unity-test-runner`
> "Use to write and execute Unity EditMode/PlayMode tests and report results via MCP `run_tests` —
> knows NUnit attributes and frame-based test patterns. Invoked by `/unity-test`; also selectable
> directly when a dispatching agent needs tests written for code it just changed."

---

## 7. Migration family

**Members:** `/unity-migrate`, `unity-migrator`.

Also a shadow pair.

**Proposed descriptions:**

`/unity-migrate`
> "Use when the user wants to upgrade Unity version, switch render pipeline (Built-in to URP/HDRP),
> replace deprecated APIs, or bump package versions. Plans the migration and executes it step by
> step rather than doing a blind find-replace."

`unity-migrator`
> "Use to execute a Unity version upgrade, render-pipeline migration, deprecated-API replacement, or
> package upgrade — reads current project state via MCP before writing migration code, so changes
> are grounded in what's actually installed. Invoked by `/unity-migrate`; also selectable directly
> when a dispatching agent has already identified a specific migration target."

---

## 8. Sanity check against the failing prompt

**Prompt:** *"Let's add a double jump to the player."*

**Verdict: `unity-coder` wins**, via `/unity-feature`'s default routing (or directly, if a
dispatching model selects the agent rather than the command).

Why it and not the other four:

- **Not `unity-coder-lite`.** A double jump is not "a new field or method on an existing class" in
  isolation — it changes jump state handling (tracking jump count, resetting on ground contact),
  which is exactly the kind of small-but-stateful behavior change `unity-coder-lite`'s own
  "Not Good Fit For" list would exclude if it required rethinking how the existing jump system
  decides "can I jump." It is genuinely borderline, but "double jump" as a named mechanic reads as
  more than a one-field tweak, so it should default to the fuller reasoning path rather than the
  lite one. (If the request had been "let the player jump 20% higher," `unity-coder-lite` would be
  the right call — that really is a one-field change.)
- **Not `unity-prototyper`.** The prompt says "the player," meaning the existing player character in
  the existing project — this is integrated feature work extending something that already exists,
  not a request for a new disposable test scene. `unity-prototyper`'s trigger is explicitly
  greenfield ("a new, self-contained test scene built from scratch"), which this isn't.
- **Not `/unity-prototype`.** Same reasoning as `unity-prototyper` — no scene-from-scratch request.
- **Not `unity-fixer`/`unity-fixer-lite` or anything from the bug-fixing family.** Nothing is broken;
  this is new capability, not a defect report. Their triggers both open on "a bug" / "something not
  working," which this prompt does not contain.
- **`/unity-feature` and `unity-coder` do not tie with each other** — they aren't competitors, they
  are command and its default-routed agent, resolved by §1's rule.

**Two more prompts, chosen to include one genuinely ambiguous case:**

**Prompt A (feature-family, less ambiguous):** *"The enemy AI should patrol between waypoints and
chase the player when it sees them."*

Verdict: `unity-coder` (via `/unity-feature`). This is new gameplay-system behavior (state
management: patrol vs. chase, a sight check, waypoint traversal) touching the existing project's
enemy — squarely inside `unity-coder`'s "new gameplay systems with complex state management" trigger
and well past `unity-coder-lite`'s explicit exclusion of the same phrase. Not ambiguous under these
rules.

**Prompt B (deliberately ambiguous, feature vs. bug-fix boundary):** *"The player falls through the
floor sometimes when landing from a jump."*

This one does **not** resolve cleanly, and that is worth reporting honestly rather than forcing a
verdict:

- Read as a **defect report** ("falls through the floor" is clearly wrong behavior), it points at
  `/unity-fix` → `unity-fixer` (not `-lite`: "sometimes" signals an intermittent/timing issue, which
  `unity-fixer-lite`'s own exclusion list names directly — "intermittent issues or race conditions").
- But it could just as easily be **missing feature work** if the real cause is that landing/collision
  handling was never built robustly for high-velocity landings — in which case it's an incomplete
  system, and `unity-coder` (via `/unity-feature`) is arguably the better fit, since the fix isn't a
  single bug but a physics-handling gap.

Under the rules in this document, this prompt sits genuinely between the bug-fixing family and the
feature family, and no differentiator axis proposed here resolves it, because the two families are
differentiated from each other by *whether something that should exist already exists*, and this
prompt's own wording doesn't say. In practice `/unity-fix`'s trigger ("something not working") is the
literal reading of "falls through the floor," so it should win on a literal-match basis — but this is
the one case in this survey where the resolution rests on the model preferring the more literal
interpretation of the prompt over a strictly worse trigger match, not on the family rules
themselves fully disambiguating it. This is flagged, not silently resolved.

---

## 9. Shadow pairs

All five follow §1's rule directly: the command owns the user-facing trigger; the agent's
description leads with "Invoked by `/unity-x`" and adds a narrow, concrete secondary cue for direct
dispatch. Descriptions below are lighter-touch than the collision families above because there is
only one real axis (command vs. its own backing agent, not agent vs. agent).

**`/unity-ui` + `unity-ui-builder`**

`/unity-ui`
> "Use when the user wants a UI screen built — menu, HUD, settings panel, inventory screen. Writes
> the backing code and sets up the visual hierarchy via MCP; supports both UGUI Canvas and UI
> Toolkit."

`unity-ui-builder`
> "Use to build a UI screen with both code and MCP-driven visual setup — UGUI Canvas optimization, UI
> Toolkit USS/UXML, TextMeshPro, gamepad focus navigation, responsive layout from 16:9 to ultrawide.
> Invoked by `/unity-ui`; also selectable directly when a dispatching agent needs a UI screen built
> as part of a larger task (e.g. a prototype that needs a HUD)."

**`/unity-scene` + `unity-scene-builder`**

`/unity-scene`
> "Use when the user wants a scene built or reorganized — GameObjects, hierarchy, lighting, cameras,
> physics layers — entirely through the editor, not by hand-writing scene files."

`unity-scene-builder`
> "Use to build or reorganize a Unity scene from a natural-language description via MCP — hierarchy,
> lighting, cameras, physics layers. Does not write C# code — scene construction only. Invoked by
> `/unity-scene`; also selectable directly when a dispatching agent (e.g. `unity-prototyper`) needs
> scene assembly as one step of a larger task."

**`/unity-network` + `unity-network-dev`**

`/unity-network`
> "Use when the user wants multiplayer networking set up or extended — a NetworkManager, spawn
> points, replicated state — for Netcode for GameObjects, Mirror, Photon, or Fish-Net."

`unity-network-dev`
> "Use to implement multiplayer networking — writes networking code and configures NetworkManager,
> spawn points, and network prefabs via MCP, across Netcode, Mirror, Photon, or Fish-Net. Invoked by
> `/unity-network`; also selectable directly when a dispatching agent's feature work requires network
> replication as a sub-step."

**`/unity-build` + `unity-build-runner`**

`/unity-build`
> "Use when the user wants to build the project or switch build platform. Asks which platform if
> none is given, then configures and triggers the build."

`unity-build-runner`
> "Use to configure and trigger a Unity build via MCP — platform switching, player settings, build
> profiles, Addressables builds — and monitor progress from console output. Invoked by `/unity-build`;
> also selectable directly when a dispatching agent needs a build triggered as a verification step
> (e.g. after a migration)."

**`/unity-shader` + `unity-shader-dev`**

`/unity-shader`
> "Use when the user wants a shader created or debugged — a visual effect, a material behaving
> wrong, a custom ShaderGraph node. Writes HLSL/ShaderLab and tests it live via MCP with rendering
> stats."

`unity-shader-dev`
> "Use to create or debug PC/console shaders — HLSL/ShaderLab, ShaderGraph custom nodes, URP shader
> structure, SRP Batcher compatibility, compute shaders — and verify live via MCP materials and
> rendering stats. Invoked by `/unity-shader`; also selectable directly when a dispatching agent
> (e.g. `unity-optimizer`) needs a shader-level fix for a rendering bottleneck."

---

## What could not be resolved

- **Prompt B in §8** (intermittent floor-fall-through) sits genuinely between the bug-fixing and
  feature families. The rules in this document do not fully disambiguate it — see §8 for the
  reasoning and the fallback (literal-match preference for `/unity-fix`). This should be reported to
  the controller as a known remaining gap, not silently patched over with a stronger claim than the
  evidence supports.

- **A finding, not a blocker:** writing out `unity-linter` and `unity-reviewer` side by side (§4)
  raised the question of whether `unity-linter` earns its keep as a separate surface at all — a
  haiku "checklist against the rules" pass and a sonnet "checklist plus judgment" pass are close
  enough that a future stocktake might fold `unity-linter` into `unity-reviewer` as a `--fast` mode
  rather than keeping it a separate agent. This document does **not** act on that — per the plan's
  own deferral table, consolidating the 103-surface pool is a separate decision — but it is recorded
  here as evidence for that future decision, the same way Correction 2a recorded the four
  rule-duplicating skills as consolidation evidence rather than acting on it.

- **The performance family (§5)** has only one real ambiguity risk: `/unity-optimize` and
  `/unity-profile` both route to the same agent, so if a user's request is genuinely ambivalent
  between "diagnose" and "fix" (e.g. "how's performance looking, and fix anything bad"), the two
  commands could both look valid. This is a much narrower version of Prompt B's problem and is
  believed handled by the phase-of-work axis in §5, but it has not been sanity-checked against a
  live prompt the way §8 checks the feature family, since the plan only requires the sanity check for
  the feature/prototype family plus two of the author's choosing (used on §8's Prompt A and B
  instead, per the higher stated risk there).
