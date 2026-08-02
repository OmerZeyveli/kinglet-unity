# Kinglet: agent context and verification — design

**Date:** 2026-08-02
**Status:** approved in principle (approach A), spec awaiting owner review
**Decides:** where kinglet's leverage lives for AI-driven game development, and what it ships to get it
**Does not decide:** the Codex adapter's contents, or any implementation ordering inside kinglet

---

## The question

Kinglet has no project map. Starting a game from scratch, the only structural facts it persists are
five rows in a generated `CLAUDE.md` (Unity version, render pipeline, assembly definitions, build
scenes, detected packages). Everything else — where the player controller is, what calls a method,
which scenes use a prefab — is re-derived every session by `Glob`/`Grep` and the `unity-scout` agent.

The gap is inherited: `provenance.tsv` has no `AGENTS.md` row and `provenance-skip.tsv` has no
"deliberately not vendored" entry for one, so neither ECU 1.5.0 nor Claude-Code-Game-Studios shipped
one and nobody evaluated it.

Endless-Evolution, by contrast, has a three-layer documentation architecture — root `AGENTS.md`,
seven per-subtree `AGENTS.md`, and `docs/systems/` plus four project-wide inventories — **all of it
hand-built during the hardening waves, none of it from kinglet.**

So: should kinglet build a project-map feature, and if so where does it live?

---

## Evidence

### External, and it does not say what we assumed

**[Do Context Files Help Coding Agents? A Two-Agent Ablation Study](https://arxiv.org/html/2607.27250)**
is the closest direct test. Three strategies — `none` / `always_on` / `selective` — 288 runs, Claude
and Codex, real merged PRs from three Python repositories.

| | none | with context |
|---|---|---|
| Claude | 53.3% | 55.6% |
| Codex | 58.8% | 56.9–52.9% |

**Correctness did not improve.** Codex's point estimates fell. Equivalence testing bounds the effect
at ≤10pp (Claude) / ≤15pp (Codex).

**The limit must be stated with the result:** n = 15–17 tasks and the authors report **MDE ≫ 30pp**.
The study could not have detected anything smaller than roughly thirty percentage points. This is a
*low-powered null*, not a demonstration that context files are worthless.

Two findings survive that caveat and both matter here:

- **The `selective` arm — topic files fetched on demand — significantly reduced Claude's
  cache-creation tokens (p = 0.012).** The `always_on` arm did not. Whatever context is worth, it is
  worth more when it is loaded on demand.
- **The one measured behavioural gain was waste avoidance:** on `opshin`, whose `AGENTS.md` warned
  that the test suite is slow, the agent stopped doing blind full-suite runs.

**[Agent READMEs: An Empirical Study of Context Files for Agentic Coding](https://arxiv.org/html/2511.12884v1)**
— 2,303 files from 1,925 repositories. Descriptive, and it explicitly does not measure performance.
Claude Code files: **median 485 words**, shallow hierarchy (one H1, 6–7 H2, 11–12 H3, H4+ rare).
Content is dominated by Testing 75.0%, Implementation Details 69.9%, Architecture 67.7%, Build and
Run 62.3%; Security and Performance sit at 14.5%. Files grow by small incremental additions.

**[SWE-Explore](https://arxiv.org/abs/2606.07297)** reports that **file-level localization is already
strong for modern methods**; what separates explorers is line-level coverage and ranking efficiency.

Taken together: nobody has shown that a persistent structural map improves outcomes, agents already
find files well, and the one measured benefit of a context file was stopping the agent doing
something expensive.

**Retracted from an earlier draft of this argument:** a claim that files over 150 lines cost 20–23%
more, sourced from a vendor blog. No paper read here supports it. It is not used.

### Internal, from 2026-08-02 in Endless-Evolution

Every defect caught that day was caught by something executable:

| Defect | Caught by |
|---|---|
| `DampClock.Fraction` reaching 1.5 against a property documented as capped at 1 | `DampClockSpec` |
| A fabricated `Enemies -> Player` edge from a type named `State` | layer-direction gate |
| Four new runtime scripts named by no document | `DocumentationMapSpec` |
| Two incomplete forms placed in a scene | `DnaFormCompletenessSpec` |
| `TUT-B2`/`DNA-B8` landing half-committed | `block-projectsettings.sh` + a ledger gap |
| A wall-transition intermittent, root cause **not** the assumed one | the PlayMode suite |

None was caught by a document.

The largest productivity change was also executable: `DnaFormAuthoringTool` turned adding a DNA form
from "eight editor steps, about an hour, impossible for an agent" into one headless call that
produced nine artefacts and exited 0 on the first attempt.

Meanwhile kinglet's descriptive layer — 28 agents, 36 commands, 39 skills, all installed and all
present in the client's registry — was invoked **zero times across six sessions.** That measurement
is confounded: the briefs those sessions ran under prescribed the method step by step, leaving
nothing for a skill to decide. It is evidence that presence does not produce use; it is not evidence
that skills are useless.

---

## Decision

**Approach A: a portable executable core, plus a thin `AGENTS.md` hierarchy. No project map.**

Two approaches were rejected:

- **Context-first** (build the `AGENTS.md` hierarchy and a generated map, change nothing else) —
  cheap, but it invests in the layer with a null result, for a job (localization) agents already do
  well, and produces an artefact that rots.
- **Client-payload-first** (populate the adapters, port skills and agents to Codex) — makes kinglet
  genuinely multi-client soonest, but ports the layer measured at zero use while leaving the layer
  that caught six defects unbuilt.

---

## Architecture: split by portability, not by kind

Kinglet already has the seam for this and it is unpopulated:

```
src/catalog/capabilities.json    abstract vocabulary: delegate, filesystem.read/write,
                                 shell, unity.read/write, web
adapters/claude/profile.json     Claude:  Agent | Read,Glob,Grep | Bash | mcp__unityMCP__*
adapters/codex/profile.json      Codex:   agent-delegation | sandboxed-command |
                                          mcp-for-unity@10.1.0
src/catalog/routing.json         "routes": []      <- empty
```

### Layer 1 — portable core (no adapter, ships once)

Bash scripts, C# EditMode/PlayMode specs, editor tools, git hooks, and Markdown in the
`AGENTS.md` format. These behave identically for Claude, Codex, Cursor, a human, and CI. **Adding a
client costs nothing here.**

- **Verification:** a gate chain (compile, tests, structural invariants) runnable by hand and wired
  to `pre-push`.
- **Completeness specs:** tests that fail when a thing is half-built — the class `DnaFormCompleteness`
  and `DocumentationMapSpec` belong to.
- **Authoring tools:** headless, exit-code-contracted commands that collapse multi-step editor work,
  in the shape of `DnaFormAuthoringTool` (0 or 2, no partial success).
- **Context files:** `AGENTS.md`, because it is the cross-client format — donated to the Linux
  Foundation's Agentic AI Foundation in December 2025 and read by roughly twenty tools including
  Claude Code and Codex. `CLAUDE.md` is Claude-only and becomes at most a thin pointer.

### Layer 2 — client adapter (regenerated per client)

Skills, agents, commands, and prompt-time hooks. Generated from `adapters/<client>/profile.json`
against the capability vocabulary. This is the layer that multiplies with client count, and the layer
whose value is currently unmeasured.

---

## Context files: what goes in them

Three tiers, and the tier is decided by load cost, not by importance.

**Always on — root `AGENTS.md`.** Routing and the standing rules that must never be violated. Not an
inventory. Skills, agents and commands are auto-discovered by the client and listing them pays twice
for the same information and rots when one is renamed; what is *not* auto-supplied is **sequence and
policy** — that `/brainstorm` precedes `/map-systems`, that the design agents write to `docs/design/`
and never write C#. Write the routing, not the roster.

For calibration rather than as a rule: real-world Claude Code context files have a median of 485
words. Endless-Evolution's root `AGENTS.md` is 222 lines and its `CLAUDE.md` is 348 — 570 lines in
every session's prefix, which is the one cost channel measured on this project (a median fixed prefix
of 40,536 tokens, and prefix re-reads accounting for 23% of two waves' bill).

**On demand — per-subtree `AGENTS.md`.** Traps and local rules, loaded only when work happens in that
subtree. Endless-Evolution's are 18–99 lines each. This is the `selective` arm that measurably
reduced cache-creation tokens, and it is the tier that earned its keep on 2026-08-02:
`Assets/Environment/AGENTS.md` was useful because it said *`RopeSwing2D` is the shipping rope and a
second rope implementation was already deleted once*, not because it listed file paths.

**Pointed at, never inlined — `docs/systems/`, `docs/decisions/`.** Endless-Evolution's `docs/systems/`
is 12,859 lines and a single decision record is 800. These are fetched, not carried.

### The highest-value content type, named explicitly

The one thing measured to change agent behaviour is **the exact command plus the trap inside it.**
Endless-Evolution documents its compile gate this way and it works. It does **not** document how to
run PlayMode, and on 2026-08-02 that cost a wasted turn discovering that `run-playmode-tests.sh` does
not exist, followed by a reported figure taken from another session's report rather than measured.
The correct invocation is:

```bash
EE_TEST_PLATFORM=PlayMode EE_TEST_CATEGORY='!SceneLoad' bash docs/hardening/run-editmode-tests.sh
```

`!SceneLoad` is excluded deliberately — the scene fixture bootstraps the real `Systems` root and
several specs in the same suite assert that no such singleton is alive — which is why the suite reads
709 under the gate's invocation and 745 when a client runs everything. Two sessions disagreed about
that number and both were right.

**A command without its trap is half a document.**

---

## What we explicitly do not build

**A project map.** Not as a generated artefact, not as a hand-written one. Agents localize files well
already; no evidence connects a persistent structural map to better outcomes; and a map is the
artefact most certain to rot. The generated facts block in `CLAUDE.md` (Unity version, render
pipeline, asmdefs, build scenes, packages) stays as it is — it is cheap, regenerated, and small.

If this is revisited, the trigger is a measurement, not an intuition: agents spending materially more
turns locating code than editing it, on this project, measured.

---

## Sequencing

1. **Finish it in Endless-Evolution.** Most of layer 1 already exists there. Four concrete gaps found
   on 2026-08-02 are listed below.
2. **Run several more sessions against it**, measuring rather than asserting.
3. **Then productise into kinglet**, converting only what is proven. Nothing unproven ships.

### The four gaps in Endless-Evolution

- **No gate covers a non-build scene.** `run-scene-load-gate.sh` scans the 36 scenes in the build
  list, so `cave_testbed.unity` — the one artefact the next playtest depends on — is verified by
  nothing.
- **The finding ledger's evidence resolver does not apply its staged-file rule to engine-settings
  paths.** It told one session that a spec existing only in the working tree must be staged, then
  certified two findings as `applied` whose changes were blocked from the index. One guard refused a
  file while another blessed a claim depending on it.
- **`DnaFormAuthoringToolSpec` must be re-pointed at the new last enum member every time a form is
  added**, and four of its six form-specific constants are not derivable from the form name. This is
  a per-form cost `operator-worklist.md` entry 16 does not count.
- **`block-projectsettings.sh` matches command text rather than the resolved target**, so writing
  *about* the guarded directory is blocked while indirection through a temporary file walks straight
  past it. Both are the same defect seen from two sides.

Add to these: **document the PlayMode invocation** in the place an agent will look.

---

## The skills question

Under approach A, skills and agents are not the mechanism — gates and tools are. Whether they get
used at all is an open empirical question, and the honest answer today is that we do not know,
because every session ran under a brief that prescribed the method.

**Prescriptive briefs and skills are substitutes.** Both encode how a kind of work is done. A brief
that specifies the steps leaves a skill nothing to contribute.

So the test is a thin brief: state the goal and the constraints, name the skills that exist, and
deliberately omit the method. Run it against a task comparable to one already done prescriptively,
and record invocation counts, cost per turn, gate outcomes, and defects found. One session, one
comparison.

**"Skills get used" is not a success criterion.** Better game development is. If a thin brief produces
no skill use and equal outcomes, that is information about the skills — which is worth having before
kinglet invests further in that layer.

---

## How we will know this worked

Three measurements, all already instrumented on this project:

1. **Defects caught by gates**, per wave, and where they were caught. The 2026-08-02 baseline is six,
   all executable, none documentary.
2. **Cost per delivered mechanic or form.** The Spider cost one authoring call plus one ability file;
   the baseline before the tool existed was an estimated hour of editor work per form and no agent
   able to do it at all.
3. **The thin-brief comparison** described above.

---

## Open questions

- **Does the thin-brief experiment run before or after the remaining Endless-Evolution work?** It is
  cheap and independent; running it early makes the kinglet productisation better informed.
- **Does `CLAUDE.md` survive at all once `AGENTS.md` carries the content?** Claude Code reads both.
  Keeping a thin `CLAUDE.md` that points at `AGENTS.md` costs a few lines; keeping two full documents
  costs the prefix twice. Not decided here.
