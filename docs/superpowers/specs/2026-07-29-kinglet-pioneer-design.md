# Kinglet Pioneer — Design

**Status:** Approved design

**Date:** 2026-07-29

**Relates to:** `2026-07-23-kinglet-platform-design.md` (the full platform). This document does not
supersede it. Pioneer is the platform's first shipping edition, deliberately narrowed.

## Decision

Ship **Kinglet Pioneer** — a Claude Code / Linux / Unity 6 edition of Kinglet, installable into a
real Unity game project now, while the full multi-client platform continues in parallel.

Pioneer is not a fork, not a prototype, and not a separate product. It is the existing `.claude/`
payload, renamed to the Kinglet brand, with the loop it already implements repaired and closed. The
name `cloud-nine-unity` is retired.

The reasoning is that the payload is already substantial — 28 agents, 36 commands, 39 skills, 25
hooks, 6 rules — and the content decisions behind it (what to take from Everything Claude Unity,
what to take from Claude-Code-Game-Studios, what to leave out, what platform to target) are already
made and enforced by `check-provenance.sh` and the test suite. What is *not* made is the runtime
decision, and that one is blocked on host evidence that cannot be gathered today.

Pioneer separates those two classes of decision. It cashes in every content decision that can be
made without a host pass, and defers every decision that cannot.

## Identity

| | |
|---|---|
| Product name | **Kinglet Pioneer** |
| Version | `3.0.0-pioneer.1` |
| Client | Claude Code — one, and only one |
| Host | Linux x64 — one, and only one |
| Unity | Unity 6, PC/console, URP unless the project states otherwise |
| Branch | `pioneer/wave-1` → merge to `main` → tag `v3.0.0-pioneer.1` |

`3.0.0-pioneer.1` sorts before `3.0.0` under semver precedence, which states machine-readably that
Pioneer is a prerelease of Kinglet 3.0.0 rather than a different lineage. The repository's
`3.0.0-dev.1` remains as the planning line.

### Identifiers are brand-level; the edition is data

Every persistent identifier Pioneer writes into a user's project uses the **Kinglet** brand, not the
Pioneer edition name. The edition is recorded beside it as a value.

| Artifact | Value |
|---|---|
| Generated block markers in the project's `CLAUDE.md` | `kinglet:generated:begin` / `kinglet:generated:end` |
| Install receipt header | `# kinglet install receipt`, followed by `# edition: pioneer` |
| `.claude/UPSTREAM` | `edition=pioneer`, `supported_clients=claude`, `supported_hosts=linux-x64` |

This is the single most consequential naming choice in this design. When the full platform takes
over a project Pioneer has been writing into, the markers it must find are already correct and the
receipt it must read is already in its own format. Handover becomes a field update rather than a
migration. Choosing `kinglet-pioneer:` markers instead would convert every one of those into a
rename that must be detected, matched, and rewritten in a user's file.

The `supported_clients` / `supported_hosts` keys exist as a brake on the version string. A reader
who sees `3.0.0-pioneer.1` might infer Pioneer is nearly Kinglet 3.0.0; these keys state in
machine-readable form that it claims exactly one client and one operating system.

## What Pioneer is not

- Not a claim of Windows or macOS support.
- Not a second client. Codex, Cursor, Copilot, and Antigravity are out of scope.
- Not the `.kinglet/` project model. Pioneer keeps `.claude/`.
- Not a runtime change. The Python foundation stays; the runtime bake-off remains undecided and
  blocked, and nothing here prejudges it.
- Not a consolidation of the command/skill surface. The stocktake in Wave 1 produces a *finding*;
  acting on it is a separate decision.

## Problem statement

The payload already implements the development loop the user wants — brainstorm, plan, ask, execute
inline or via subagents, verify — and implements it twice, once for design and once for engineering:

- **Design track:** `/brainstorm` → `/map-systems` → `/design-system` → `/design-review` →
  `/sprint-plan`
- **Engineering track:** `/unity-interview` → `/unity-workflow` (Clarify → Plan → Critic → Execute →
  Verify, each phase gated on explicit user confirmation)

`/unity-workflow` even decides inline-versus-subagent rather than asking: Phase 2 rates the work
simple / moderate / complex and routes to `unity-coder-lite`, `unity-coder`, or `/unity-team`.

The loop is not missing. It is broken in four specific places, and every break has the same shape —
the mechanism exists and nothing is wired to it.

### Break 1 — the loop lives in conversation, not on disk

`/unity-interview` produces a comprehensive Feature Brief but never states where to write it.
`/unity-workflow` Phase 1 produces a Requirements Summary that exists only in the transcript.
`.claude/state/session.json` already carries `workflow_phase`, `plan`, `verification`, and
`agent_context` fields — all empty, populated by nothing.

Context compaction destroys anything that lives only in a transcript. Everything else in this design
rests on artifacts surviving the session that produced them.

### Break 2 — the two tracks do not connect

`/design-system` writes a GDD containing Acceptance Criteria and a fully specified `## Game Feel`
section. `/unity-workflow` never reads it; it starts from a free-text feature description. Design
decisions do not reach implementation.

### Break 3 — feel is specified at design time and never checked afterwards

The GDD template's `## Game Feel` section is complete: Feel Reference, Input Responsiveness,
Animation Feel Targets, Impact Moments, and Feel Acceptance Criteria. Nothing returns to it after
implementation. `unity-verifier` verifies code; no test can report that a jump feels floaty.

In ordinary software, "the tests pass" approximates done. In a game it is the floor, and the bar is
whether the thing is fun. The loop has to return to tuning, not to code.

### Break 4 — the surface is not machine-selectable

In Claude Code the model chooses a command or skill from its `description` field alone. Measured
across the payload: **zero of 39 skills** phrase their description as a trigger condition. They are
topic summaries — they describe what the surface does, not when it applies.

Compare:

- Payload: `"Full development pipeline — clarify requirements, plan implementation, execute with
  agents, verify with review + tests."`
- Superpowers: `"Use when encountering any bug, test failure, or unexpected behavior, before
  proposing fixes"`

The second gets selected automatically; the first does not. This matters because nobody should have
to memorize 36 commands, and the platform design already commits to this: *"Primary interaction:
ordinary natural-language requests. Deterministic interaction: namespaced native commands/skills."*

### Break 5 — there is no code map

`systems-index.md` maps each system to its **design document**. It does not map any system to its
**code**. So `unity-scout` re-derives the project structure from scratch on every question — glob,
grep, assembly scan. That cost is precisely the "the agent loses the thread and is slow to find
things" problem, and it recurs every session.

## Relationship to Superpowers

Superpowers is a **research and adaptation source**, not a runtime dependency. Pioneer must work on
a machine where Superpowers is not installed. It is MIT © Jesse Vincent — the same licence class as
Everything Claude Unity and Claude-Code-Game-Studios — so adaptation with recorded provenance is
clean. `provenance.tsv` gains a third origin value, `superpowers`, and `check-provenance.sh` must
accept it.

Its 14 skills were assessed against the existing surface:

| Superpowers skill | Disposition | Reason |
|---|---|---|
| `writing-skills` | Not taken | `/unity-skillify`, `/unity-learn`, `/unity-skill-stocktake` are richer |
| `dispatching-parallel-agents` | Not taken | `/unity-team` |
| `subagent-driven-development` | Not taken | `/unity-team`, `unity-verifier` |
| `requesting-code-review` | Not taken | `/unity-review`, `unity-reviewer` |
| `verification-before-completion` | Not taken | `unity-verifier`, `/unity-ralph`, `stop-validate.sh` |
| `using-superpowers` | Not taken | Meta; Break 4 addresses the same need natively |
| `executing-plans` | Not taken | `/unity-workflow` Phase 3 |
| `brainstorming`, `writing-plans` | Adapted as Break 1 + Break 2 repairs, not imported | The payload has the loop; it lacks the durable artifacts |
| `using-git-worktrees` | **Refused** | Actively harmful in Unity — see below |
| `test-driven-development` | **Adapt** | `/unity-test` writes missing tests; there is no discipline |
| `systematic-debugging` | **Adapt** | `/unity-fix` repairs directly; there is no reproduce-first gate |
| `receiving-code-review` | **Adapt** | Nothing prevents performative agreement with `unity-reviewer` |
| `finishing-a-development-branch` | Not taken | `unity-git-master` covers the Unity-specific parts |

### Why `using-git-worktrees` is refused

A git worktree does not share `Library/`. Every worktree triggers a full asset reimport, which on a
real project is minutes to hours. `.meta` GUIDs then diverge across trees, which is the failure mode
the payload's existing rules spend the most effort preventing. The skill is correct for ordinary
repositories and wrong for Unity projects. This is recorded as a deliberate exclusion, not an
oversight.

## Components

### Wave 1 — the installable core

Wave 1 ends with an install into the user's Unity project.

#### Item 0 — Smoke pass

An operator procedure, not code, in the same shape as the Windows and macOS host passes: a written
record produced by a human running the thing once.

The repository guide is explicit that this has never been done:

> *"None of this proves the toolkit works in Claude Code — only that the installer places correct
> bytes. Frontmatter validity, command registration, and agent invocation still need one manual pass
> in a real Unity project with the MCP bridge running."*

Every other item in this design is built on top of that untested surface, so it runs first.

- **Environment:** a scratch Unity 6 project — not the user's game — with the CoplayDev MCP bridge
  running. First contact does not risk work that matters.
- **Measured:** how many of the 36 commands registered; how many of the 28 agents were invocable;
  how many of the 39 skills loaded; whether the 25 hooks fired; MCP connectivity; the exact Unity
  version and MCP package version actually run.
- **Also run:** `/unity-skill-stocktake`, to measure duplication and never-loaded entries across the
  75-surface selection pool rather than guessing at it.
- **Output:** `docs/research/pioneer/smoke-pass.md`, recording the date it was actually run.
- **Effect:** its findings join the Wave 1 defect list. A finding that contradicts this design
  amends this design; it is not worked around.

The smoke pass runs under the old name. What it measures is what the payload does, not what it is
called.

#### Item 10 — Rename to Kinglet Pioneer

30 tracked files, 111 occurrences of `cloud-nine`. The first code work of Wave 1, immediately after
the smoke pass, because two of those occurrences are written into the user's project and become
expensive the moment anything is installed:

- `install.sh` writes `<!-- cloud-nine-unity:generated:begin -->` into the project's `CLAUDE.md` and
  finds that marker again on every re-install to refresh the block between the markers.
- `install-receipt.tsv` carries `# cloud-nine-unity install receipt` in its header, and the
  installer's `ours` / `foreign` mode detection reads the receipt.

Renaming after a first install would leave the old markers in the user's file, where the new
installer cannot find them, and a second block would be appended.

Scope: product name, banner strings, marker strings, receipt header, `.claude/UPSTREAM` keys, README,
`MERGE-NOTES.md`, `CREDITS.md`, `.claude/NOTICE.md`, `CONTRIBUTING.md`, `MCP-SETUP.md`, the repo
`CLAUDE.md`, `scripts/generate-claude-md.sh`, `scripts/studio-doctor.sh`, `tests/run-tests.sh`,
`tests/test-no-mobile.sh`, and the `note` column of `provenance.tsv` where it names the toolkit.

Attribution to Everything Claude Unity, Claude-Code-Game-Studios, and their authors is unaffected
and must survive verbatim. The rename changes our name, not theirs.

#### Item 7 — MCP pin and provenance origin

The repository currently holds two contradictory pins for the same dependency:

- `.claude/UPSTREAM` and `MCP-SETUP.md`: `com.coplaydev.unity-mcp` **10.1.0**
- `spikes/platform/unity/mcp.lock.json`: **v9.7.1** @ `78ee5418415953b79c358bfe6355fcc3fde7912b`,
  described as a strict pin, and the source of every measured Unity fact in the spike

Rule: **Pioneer pins the version it was actually run against.** The smoke pass establishes that
version, and this item records it. If it diverges from the spike's pin, the divergence is stated
explicitly rather than silently reconciled — the spike's measurements were taken against 9.7.1 and
remain true of 9.7.1.

Also in this item: `provenance.tsv` accepts `superpowers` as an origin, and
`scripts/check-provenance.sh` is extended to recognise it.

#### Item 8 — Make the surface machine-selectable

Rewrite the `description` field of the 36 commands and the `core/` process skills as trigger
conditions rather than topic summaries.

**Targeted, not blanket.** Knowledge skills — `serialization-safety`, `object-pooling`,
`assembly-definitions`, and similar — keep topic descriptions, because topic matching is what
actually selects them and because every edited file vendored from Everything Claude Unity must flip
to `status=modified` in `provenance.tsv`. Narrowing the edit narrows the provenance churn.

**Automatic selection, yes. Automatic destructive execution, no.** The model announces which surface
it selected and why; that surface's own phase gates then take over. `/unity-workflow` gating every
phase on explicit confirmation is what keeps an inference from turning into a mutated scene. A
request like "let's add a jump" must not silently become `/unity-prototype` writing scripts and
driving the Editor over MCP.

#### Item 9 — Code map

Add an **`Implements`** column to the `systems-index.md` template: assembly definition plus primary
code paths for each system.

- `/unity-workflow` updates the row for the system it touched, after Execute.
- `unity-scout` reads the index *before* scanning, and scans only to fill gaps or resolve conflicts.

This closes system → design document → code in one place, and converts the repeated full-project
scan into a lookup.

**The map is information, not authority.** Where the map and the tree disagree, the tree is right
and the map is corrected. A stale map must never cause the agent to edit the wrong file or conclude
that code does not exist.

#### Item 1 — Durable artifacts

| Producer | Artifact |
|---|---|
| `/unity-interview` | `docs/features/<slug>/brief.md` |
| `/unity-workflow` Phase 1 | `docs/features/<slug>/requirements.md` |
| `/unity-workflow` Phase 2 | `docs/features/<slug>/plan.md` |
| `/unity-workflow` Phase 4 | `docs/features/<slug>/verification.md` |

**The mechanism is the gate, not the file.** A phase gate cannot be passed until its artifact is on
disk. Without that coupling the behaviour degrades back into conversation the first time it is
inconvenient — which is exactly how the current state arose.

`docs/features/` is a new sibling of the existing `docs/design/`, `docs/adr/`, and `docs/production/`
in the user's Unity project, outside `Assets/` so Unity does not import it. `<slug>` derives from the
feature name; a collision takes a numeric suffix rather than overwriting.

`session.json`'s existing `workflow_phase`, `plan`, and `verification` fields are populated by the
same phases, so a resumed session knows where it was.

#### Item 2 — Connect the two tracks

`/unity-workflow` and `/unity-feature` search `docs/design/` for a GDD matching the feature before
Phase 1 completes.

- **Found:** its **Acceptance Criteria** and **Game Feel → Feel Acceptance Criteria** are carried
  into `requirements.md` verbatim. Verbatim matters — a paraphrase is a silent design change. Its
  **Tuning Knobs** inform what the plan must externalize rather than hardcode.
- **Not found:** say so explicitly and offer `/design-system`. Never proceed silently, and never
  invent the design decisions the GDD would have contained.

### Wave 2 — the discipline layer

Delivered after the install, as an upgrade. `install.sh` already supports this precisely: a receipt
in the target puts it in `ours` mode, where it knows every file it wrote and its checksum, and marks
any file the user has edited as `user-modified` rather than overwriting it. Wave 2 is not a promise
to revisit; it is a tested mechanism.

The split is not arbitrary. Wave 1 items make the loop *trustworthy* — artifacts that survive,
design that reaches implementation, a surface that can be found, a map that stays current, one
honest dependency pin. Wave 2 items make it *disciplined*. Discipline is valuable, but its absence
does not prevent work; a loop that forgets itself does.

#### Item 3 — Playtest gate

A fifth phase after Verify. It presents the GDD's Feel Acceptance Criteria, the user plays and marks
each pass / fail / unsure, the result is written to `docs/features/<slug>/playtest.md`, and anything
not passing returns to a tuning round before the feature counts as done.

It writes no code and automates nothing. Its whole job is to make felt quality a recorded,
un-forgettable step instead of an impression that evaporates.

#### Item 4 — TDD discipline, adapted to Unity

Test first, watch it fail, then write the minimum that passes. The adaptation is the work: EditMode
tests run in seconds and PlayMode tests in minutes, so the discipline must say which loop applies
where; tests run through the MCP bridge, so it must state what happens when the bridge is down; and
the Model-View-System boundary the rules already mandate is what makes a Unity feature testable at
all, so the discipline points at the Model and the System, not the MonoBehaviour.

#### Item 5 — Systematic debugging gate

A reproduce-first gate ahead of `/unity-fix`. The Unity adaptation covers the difference between a
console error and a silent behavioural fault, and the recurring causes the rules already name:
domain reload, execution order, destroyed-object access through `?.`.

#### Item 6 — Receiving code review

A discipline for responding to `unity-reviewer` output with verification rather than agreement.
Single file, small item, disproportionate value when it applies.

## Data flow

```
/brainstorm ────▶ docs/design/game-concept.md
/map-systems ───▶ docs/design/systems-index.md ◀───────────────┐
                       │   (System │ Design Doc │ Implements)   │
                       ▼                                        │
/design-system ─▶ docs/design/<system>.md                       │
                  (Acceptance Criteria + Game Feel)             │  Item 9
                       │                                        │  Implements
                       ▼  Item 2                                │  updated
/unity-interview ▶ docs/features/<slug>/brief.md                │  after Execute
/unity-workflow  ▶ requirements.md ─▶ plan.md                   │
                       │                                        │
                       ▼  Execute ──────────────────────────────┘
                  verification.md
                       │
                       ▼  Wave 2, Item 3
                  playtest.md ──▶ tuning round ──▶ (back to plan.md)
```

## Error handling

| Condition | Behaviour |
|---|---|
| Artifact cannot be written (`docs/` missing, read-only) | **Hard stop.** Never degrade silently into conversation — that failure is invisible and defeats Item 1 entirely. |
| No GDD for the feature | Announce, offer `/design-system`, do not fabricate design decisions. |
| MCP bridge unreachable | The documentation layer works unchanged. `unity-*` MCP commands fail loudly — "bridge not reachable at localhost:8080" — never a silent no-op that looks like success. |
| Code map disagrees with the tree | The tree wins; the map is corrected. |
| A rewritten description breaks provenance | Every touched file flips to `status=modified` with a note **in the same commit**. `check-provenance.sh` stays green; a red manifest is a failed change, not a follow-up. |
| Smoke pass contradicts this design | This design is amended. Evidence outranks the plan. |

## Testing

**New and mechanically checkable:** `tests/test-command-triggers.sh` asserts that every
`.claude/commands/*.md` and every `core/` skill description matches the trigger grammar. Item 8 is
the one repair here whose result is a string, so it is the one that can be enforced by a test.

**Must stay green:** `tests/run-tests.sh` (99 assertions across 8 files),
`scripts/check-provenance.sh`, `tests/test-no-mobile.sh`.

**Not testable, and not claimed to be:** the substance of Items 1, 2, 8, and 9 is prompt behaviour.
No bash assertion can prove that a phase gate actually held, that a GDD was actually read, or that
the model actually selected the right command. These are verified by the smoke pass and by use.
Stating that the suite covers them would be exactly the kind of green-but-meaningless claim this
repository's history is a record of finding and removing.

## Handover to the full platform

Pioneer is designed to be superseded, and the handover is engineered rather than deferred.

- **Toolkit files:** `install-receipt.tsv` lists every file Pioneer wrote into the game project with
  its checksum, and distinguishes files the user edited. `uninstall.sh` already inverts it exactly.
- **User content:** `docs/design/` and `docs/features/` are deliberately absent from the receipt —
  they are the user's work, not the toolkit's. The full platform's Setup and Migration engine must
  **adopt** them, not remove them.
- **Identifiers:** already Kinglet-branded, so the markers the migration engine looks for are
  present and correct, and `edition=pioneer` tells it what it is looking at.

The platform design already names "migrating from another system" as a first-class setup case. Using
Pioneer as that case's canonical source makes it a planned test rather than a debt discovered later.

Consequently the directory choices in Item 1 — `docs/features/<slug>/` with `brief`, `requirements`,
`plan`, `verification`, and later `playtest` — are a **contract with the migration engine**, not an
incidental layout. Changing them later costs a migration path.

## Success criteria

1. The smoke pass record exists and states, per surface, what loaded and what did not.
2. `git grep -i cloud.nine` returns nothing outside historical documents that describe the rename.
3. `tests/test-command-triggers.sh` passes; `run-tests.sh` and `check-provenance.sh` stay green.
4. `install.sh` installs Pioneer into the user's Unity project and writes a receipt headed
   `# kinglet install receipt` with `# edition: pioneer`.
5. A feature taken through `/unity-workflow` leaves `requirements.md`, `plan.md`, and
   `verification.md` on disk, and its system's `Implements` row is filled in.
6. A feature with an existing GDD carries that GDD's acceptance criteria into `requirements.md`
   verbatim.
7. The user is building their game with it, and has not memorized a command name to do so.

## Open questions

None blocking. Two decisions are deliberately deferred with a named trigger:

- **Whether the 75-surface selection pool should be consolidated** — the Wave 1 stocktake produces
  the measurement; the cut is a separate decision made against that measurement.
- **Which MCP package version Pioneer pins** — the smoke pass establishes it. The rule is fixed even
  though the value is not: Pioneer pins what it ran against.
