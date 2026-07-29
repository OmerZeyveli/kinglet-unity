# Endless Evolution — Parallel Hardening & Documentation Plan

> **For agentic workers:** each Unit below is designed to be handed to **one agent that can spawn its own subagents**. Units run in parallel. Read "How to run this" first, then your own Unit, then nothing else — the other Units are not your business and reading them costs you context you will need.

**Goal:** Review every first-party script in Endless Evolution for correctness, verify that its bindings and call sites hold, improve its organisation and quality, and leave behind documentation an AI can actually use — without breaking a working game.

**Architecture:** One serial setup phase that hands every agent an isolated workspace and a compile gate, then eight independent Units over non-overlapping file sets, then a serial integration phase. Each Unit is one agent; each agent fans out to subagents per file or per subsystem.

**Repository:** `/home/riive/Documents/GitHub/Endless-Evolution` — note the capital **H**; a sibling repo uses lowercase `Github`.

---

## What this project actually is

Read this before you form a plan of your own. Two of these facts overturn the obvious assumption.

**It is a 150-file project, not a 1073-file one.** `Assets/Extensions/` holds 923 files and 165,931 lines of vendored MoreMountains/Feel, vFolders, vHierarchy and vInspector code. The project's own `AGENTS.md` already tells agents to ignore it. **The first-party codebase is ~150 files and ~25,300 lines.** Any agent that allocates effort by raw file count will spend it almost entirely in vendor code.

**There are no tests.** Zero `[Test]`, zero `[UnityTest]`, anywhere. `com.unity.test-framework` is installed and unused. `SaveMigrationTests.cs` is a manually-invoked editor tool, not a test. **Nothing automatic catches a behavioural regression.** A compile is necessary and nowhere near sufficient.

**It has a real architecture, and it is not Kinglet's.** Singleton services with owner-keyed request/release arbitration; a genuine finite state machine for player and enemy locomotion. It is internally coherent on its own terms. It shares none of Kinglet's mandated patterns — no VContainer, no MessagePipe, no UniTask, no Model-View-System.

> **Do not migrate this project to Kinglet's patterns. Nobody asked for that.** Kinglet's rules describe how *new* Kinglet projects are built; this project predates them and works. Rewriting a working singleton service into VContainer because a rule file says so would be the single most destructive thing an agent could do here. If you find yourself reaching for that, stop and report it instead.

**Its existing documentation is better than its owner thinks.** The owner called `AGENTS.md` and `docs/` "old and primitive". A survey spot-checked their claims — file existence, class names, folder renames — and found them **accurate**, with a changelog maintained through April 2026. Treat that content as a source to restructure, not as noise to discard.

---

## How to run this

### The setup phase is not optional and runs once, before any Unit

Every Unit depends on two things the setup phase produces: an isolated workspace, and a compile gate that works without opening Unity. Both are proven — the recipe below was executed and measured, not designed on paper.

### Your workspace

Each agent works in its own git worktree, on its own branch, off a shared integration branch. **Nobody works in the owner's checkout, and nobody touches `omer-sfx`.**

```bash
MAIN=/home/riive/Documents/GitHub/Endless-Evolution
UNIT=<your unit number>

cd "$MAIN"
git worktree add /tmp/ee-unit-$UNIT -b hardening/unit-$UNIT hardening/base

# The .csproj files are Unity-generated and gitignored, so a worktree has none.
cp "$MAIN"/*.csproj /tmp/ee-unit-$UNIT/

# Library/ is gitignored and holds the compiled Unity + package assemblies the
# csproj references. Symlink it read-only rather than copying 
# several gigabytes per agent.
ln -sfn "$MAIN/Library" /tmp/ee-unit-$UNIT/Library
```

**One-time fix, run once against `$MAIN`, before any worktree is created:** the tracked
`.gitignore` ignores `Library` with `/[Ll]ibrary/` — the trailing slash means the pattern
only matches a real directory. A symlink named `Library` does not match it, so every
worktree above will show `Library` as untracked in `git status --porcelain`. This was
caught by running S4 end to end, not assumed. Fix it once, centrally, without touching
the tracked `.gitignore` (which the owner did not ask to change) by adding a local-only
exclude rule shared across all worktrees via the common `.git` dir:

```bash
grep -qxF 'Library' "$MAIN/.git/info/exclude" || echo 'Library' >> "$MAIN/.git/info/exclude"
```

This file is never committed and is shared by every worktree automatically. Do this once
in the setup phase, not per-agent.

### Your compile gate

```bash
cd /tmp/ee-unit-$UNIT
dotnet build Assembly-CSharp.csproj \
  -p:BaseIntermediateOutputPath=/tmp/ee-obj-$UNIT/ \
  -p:BaseOutputPath=/tmp/ee-bin-$UNIT/ \
  --nologo
```

**Measured: 2–12 seconds, `0 Error(s)`, and it writes nothing into the repository** — the two output-path overrides are what keep it clean. Run it after every meaningful change. It is fast enough that there is no excuse not to.

Baseline at the time of writing: **0 errors, 29 warnings.** If your Unit's build reports an error, it is yours; fix it before you go further.

**Two constraints on the gate:**

- `Library/` is a symlink into the owner's checkout. If the owner opens Unity while you work, Unity rewrites `Library/ScriptAssemblies` and your build may fail transiently through no fault of your own. Re-run it before concluding anything.
- The gate proves your code **compiles**. It proves nothing about whether the game still behaves. See "The missing net".

### Read these three before you touch a file

The setup phase ran and left you things. Skipping them will cost you more than reading them.

1. **`docs/hardening/migration-map.md`** — where the project's own guidance was carried, restructured, or left in place, and **four stale claims** found while checking it. It also records gotchas migrated out of `AGENTS.md`, at least one of which is a **real pre-existing bug** (in `DNASample`, Unit 2's territory). These were paid for in someone's debugging time; do not rediscover them.

2. **The project's root `AGENTS.md`.** Yes, actually read it. Its claims were spot-checked and found accurate, and it records incidents — the `UnityEventTools` prefab-override corruption among them — that will not be obvious from the code.

3. **`docs/hardening/baseline.md`** — 0 errors, 29 warnings, grouped by which Unit owns them. **Your Unit's warnings are your starting backlog**, already classified and waiting. Units 1, 4, 6 and 7 have entries; the rest are vendor code and out of scope.

### A known-broken csproj that is not your fault

`Assembly-CSharp-Editor.csproj` currently **fails to build** — a stale generated-file reference, not a code defect. It self-heals the next time the owner opens Unity. The workspace recipe copies `*.csproj` verbatim, so **every worktree inherits it.**

`Assembly-CSharp.csproj` — the one your compile gate builds — is unaffected: 0 errors.

This matters most to **Unit 8**, which owns editor tooling and would otherwise spend an hour investigating it as a regression it caused. If your gate reports errors, check whether they are in `Assembly-CSharp-Editor` before assuming they are yours.

### The missing net, and what to do about it

There is no test suite. That is the central risk of this whole effort, larger than the file decomposition.

**Therefore: every Unit's default posture is to report rather than to change.** A finding written down costs nothing and is worth something. A "fix" to hand-tuned behaviour — `PlayerMovement`'s coroutine dash-freeze, `Enemy`'s chase-facing dead-zone, both documented with dated behavioural notes in the project's own `docs/system-inventory.md` — can silently ruin the game's feel, and **nothing in this pipeline will catch it.**

Classify every finding into one of three, and act accordingly:

| Class | Examples | Action |
|---|---|---|
| **Safe** | Dead code, unused fields, a `CS0649` warning, a missing `[SerializeField]` on a field the inspector already sets, a comment that contradicts the code | Fix it. Note it. |
| **Behavioural** | Anything touching timing, physics values, state-machine transitions, input handling, tuned constants | **Do not fix.** Write it up with file, line, what you believe is wrong, and what you would change. The owner decides. |
| **Structural** | Splitting a 1,400-line file, renaming a class, moving a file between folders | **Do not do it in this pass.** Propose it, with the specific seam you would cut along. Structural moves risk `.meta`/GUID damage and this project has already been bitten once. |

If in doubt, it is Behavioural. The bar is not "am I confident this is better" — it is "would a wrong answer here be invisible until someone plays the game".

### Unity asset safety, which has bitten this project before

The project's own `AGENTS.md` records that `UnityEditor.Events.UnityEventTools` once silently zeroed a persistent `UnityEvent`'s `m_MethodName` override on a nested prefab instance. It mandates `SerializedObject` writes instead.

- **Never** move or rename a `.cs` file with a bare `mv` or `git mv`. Its `.meta` carries the GUID every scene and prefab reference depends on. Use `AssetDatabase.MoveAsset`, or move file and `.meta` together with the editor closed.
- Do not edit `.unity`, `.prefab` or `.asset` files by hand.
- Do not touch anything under `Library/`, `Temp/`, `Logs/`, `UserSettings/`, or any `*.csproj` — all generated.
- **Do not touch `Assets/Extensions/`** unless your Unit explicitly says so. None does.
- `Assets/Player/Rebinding Samples/` is vendored sample code with its own asmdef. Out of scope.

### What you deliver

Per Unit, on your branch:

1. **A findings report** at `docs/hardening/unit-<N>-findings.md` in your worktree — every finding, classified Safe / Behavioural / Structural, with file and line. This is the primary deliverable. The fixes are secondary.
2. **The Safe fixes**, committed in coherent batches with the compile gate green.
3. **A subsystem document** at `docs/systems/<subsystem>.md` for each subsystem you own — see "The documentation standard".
4. **Nothing else.** No structural moves, no behavioural changes, no new dependencies, no reformatting sweeps. A diff that touches every line of a file because an agent reformatted it is unreviewable and will be reverted wholesale.

### The documentation standard

The point is documentation an **AI agent** can act on, which is not the same as documentation a person browses. For each subsystem:

- **What it owns** — the state it is authoritative for, in one paragraph.
- **Its public surface** — the methods and fields other systems actually call, with their preconditions. Not a generated API dump: the ones that are really used, found by grepping call sites.
- **Who calls it, and who it calls.** Concrete file names. This is the part that makes an agent able to trace a change's blast radius.
- **Invariants and hand-tuned values** — anything where changing a number changes how the game feels. Flag these explicitly; they are exactly what a future agent must not casually adjust.
- **Known gotchas**, including any the existing `AGENTS.md` or `docs/` already records for this area. Carry them across; they were paid for in bugs.

Write it the way you would brief a competent colleague who has never seen the file. No marketing adjectives.

---

## Setup Phase — DONE 2026-07-30, all five steps. Evidence: `.superpowers/sdd/ee-setup-phase-report.md`

- [x] **S1. Create the integration branch.** From `omer-sfx`, create `hardening/base`. Every Unit branches from it and merges back to it. **`omer-sfx` is never touched.**

- [x] **S2. Record the baseline.** Run the compile gate on `hardening/base` and record the exact error and warning counts into `docs/hardening/baseline.md`. Capture the 29 warnings in full — they are the first concrete backlog and several Units will find their own entries there.

- [x] **S3. Migrate the existing guidance.** This is where the project's `AGENTS.md` and `docs/` tree get restructured into the toolkit's mechanism (rules, skills, subsystem docs) rather than left as a second competing system. Preserve every accurate claim; the survey found them accurate. Where the toolkit has no equivalent structure for something `AGENTS.md` does well, **say so and keep the original** rather than dropping it to fit.

- [x] **S4. Prove the workspace recipe once**, end to end: create a throwaway worktree, copy the csprojs, symlink `Library/`, run the gate, confirm `0 Error(s)`, remove the worktree. If any step fails, fix the recipe **before** eight agents hit the same wall.

- [x] **S5. Write the cross-unit notice file** at `docs/hardening/cross-unit-notices.md`, empty but present, with a header explaining its use: any agent proposing a signature change to one of the ten shared singletons appends a notice here rather than making the change.

---

## The ten shared singletons

`SaveManager` · `SettingsManager` · `PauseService` · `TimeScaleService` · `MusicPlayer` · `SFXPlayer` · `SceneTransitionService` · `VFXManager` · `InputModeController` · `UserInput`

These live in Units 5–7. Units 1–4 **call** them and never edit them.

**No agent changes the signature of anything on this list.** If a change looks necessary, append a notice to `docs/hardening/cross-unit-notices.md` naming the file, the current signature, the proposed one, and every call site you found. The owner decides. A signature change made unilaterally breaks other agents' units silently, and with no test net nothing will report it.

---

## The Units

Eight Units, ~150 files. If you have four agents, merge adjacent low-conflict pairs — **3+4** and **6+7** are the intended seams. Never split one file across two agents.

**Sequencing:** Unit 5 is read by nearly everything. Run it **first or alone** if you can. Everything else is genuinely parallel.

### Unit 1 — Player Locomotion Core
`Assets/Player/Scripts/`, `Assets/Player/States/` · ~24 files, ~4,180 lines

`PlayerMovement.cs` (948 lines), `DNAController.cs`, `PlayerMovementData.cs`, and the locomotion FSM — `LocomotionStatePattern` plus 18 state classes.

Every other unit treats this unit's public surface as a stable API: movement locks, run-speed and jump multipliers. **Changing that surface breaks Unit 2 silently.**

`PlayerMovement.cs` is one of the two files most other systems reach into. **Do not parallelise subagents inside this single file** — two subagents editing it will produce conflicting edits nothing will catch. One subagent owns it end to end.

Nearly everything here is Behavioural. Expect this Unit's output to be mostly a report, and treat that as success.

### Unit 2 — Player Abilities & Input
`Assets/Player/DNA Forms/`, `Assets/Player/Input/`, `Assets/Player/Item_Behavior.cs` · ~19 files, ~2,596 lines

Consumes Unit 1's lock/multiplier API and Core's `TimeScaleService` / `VFXManager` / `SFXPlayer` — reads only, edits none of them.

The DNA-form system is the game's identity: bunny grants wall jump, butterfly grants flap. Its interaction matrix with locomotion state is exactly the kind of thing that is hand-tuned and undocumented. **Documenting it well may be worth more than any fix.**

`Assets/Player/Rebinding Samples/` is vendored sample code. Out of scope.

### Unit 3 — Enemies
`Assets/Enemies/` · 14 files, ~2,115 lines

`Enemy.cs` (1,116 lines) plus 7 enemy locomotion states. Depends on Unit 4's `EnemyStop` blocker objects (layer 18, `BlockChase` flag) and senses the player — read-only in both directions.

`Enemy.cs` is the other file everything reaches into: **one subagent owns it, not several.** The chase-facing dead-zone is hand-tuned and documented as such — Behavioural, report only.

### Unit 4 — Environment & Interactables
`Assets/Environment/` · 27 files, ~2,954 lines

Puzzles, doors, switches, boxes, breakables, currency, spikes, falling rocks (pooled, with a documented Animator Write-Defaults gotcha on `Rock.controller`), 2D water, rope and spool.

The most self-contained unit — its only coupling out is the `EnemyStop` contract Unit 3 reads. Good place to be thorough.

### Unit 5 — Core Foundation
`Assets/Core/Save System/`, `Assets/Core/Time/`, `Assets/Core/Steam/`, `Assets/Core/Debug/` · 17 files, ~1,475 lines

`SaveManager`, `SettingsManager`, `ProgressionService`, `SaveMigration`, `TimeScaleService`.

**Small by line count and the highest-risk unit in the plan.** Nearly every other unit reads from here. Run it first or alone.

Save-format changes are irreversible for players who already have saves. `SaveMigration` exists because this has been handled carefully before — **read it before proposing anything about save shape.** Treat every save-format thought as Behavioural, without exception.

### Unit 6 — Core Presentation: Menu & Audio
`Assets/Core/Menu/`, `Assets/Core/Audio/` · ~19 files, ~3,569 lines

`SFXPlayer.cs` (1,456 lines — the largest first-party file), `MusicPlayer`, `VolumeSetting`, `MenuStack`, `PauseService`.

Consumed by nearly everything for feedback calls; nothing else writes here. `SFXPlayer` at 1,456 lines is a strong Structural candidate — **propose the seam, do not cut it.** A split done without tests is how a working audio system stops working.

### Unit 7 — Core Presentation: VFX, Localization, Input UI, Tutorial, World Level
`Assets/Core/VFX/`, `Assets/Core/Localization/`, `Assets/Core/Input UI/`, `Assets/Core/Tutorial/`, `Assets/Core/World Level/` · ~20 files, ~4,634 lines

`VFXManager.cs` (673), `LevelTutorialController.cs` (711), `FlightTutorialController.cs` (407), the rebinding/glyph subsystem, the level-graph world-map navigator.

Internally cross-referential — tutorial controllers drive VFX spotlight and input glyphs — but needs no file from Units 1–6. Localization and glyph tables are where a silently wrong key produces no error and no visible failure until a player switches language: worth specific attention.

### Unit 8 — Editor Tooling
`Assets/Editor/`, `Assets/PlayerPrefsEditor/` · 9 files, ~3,743 lines

Lowest risk, no runtime coupling. `Plist.cs` (966) and `PlayerPrefsEditor.cs` (954) are vendored/adapted macOS plist code — **low priority, do not rewrite vendored code.**

**Run this Unit first if you are proving the workflow.** If the worktree recipe, the compile gate or the report format has a problem, discovering it here costs nothing.

---

## Integration Phase — serial, after the Units

- [ ] **I1. Merge Units into `hardening/base` one at a time**, running the compile gate after each. One at a time is what makes a failure attributable.

- [ ] **I2. Consolidate the findings** into `docs/hardening/findings.md`: all Behavioural and Structural findings from all eight Units, grouped by subsystem, each with file, line and proposed change. **This is the plan's real output** — the document the owner reads to decide what to actually change.

- [ ] **I3. Re-run the compile gate on the merged result** and compare against the baseline from S2. Warnings should be down. If any went up, say which and why.

- [ ] **I4. Manual verification session.** Open Unity on `hardening/base`, let it reimport, confirm no console errors, play the game. **This step cannot be delegated to an agent and cannot be skipped** — it is the only thing in this entire plan that verifies the game still works.

- [ ] **I5. Report to the owner** and stop. Do not merge to `omer-sfx`. That is the owner's decision, not the pipeline's.

---

## What this plan deliberately does not do

| Not doing | Why |
|---|---|
| Migrating to VContainer / MessagePipe / UniTask / MVS | Nobody asked. The existing architecture works and is coherent. |
| Introducing first-party asmdefs | It would speed compiles and enforce boundaries, and it is a real proposal — but it is a large structural change to a working project, and the worktree compile gate already solves the parallel-isolation problem it would have solved. Propose it in the findings; do not do it here. |
| Writing a test suite | Genuinely valuable and a plan of its own. Doing it badly and in parallel with eight agents editing the same code would produce tests that pin the bugs. |
| Touching `Assets/Extensions/` | 923 vendored files the owner has already fenced off. |
| Merging anything to `omer-sfx` | The owner's branch. |

## Self-review

**Decomposition.** Eight Units over ~150 files, non-overlapping in both files and coupling direction. No Unit writes into another's files; all cross-unit coupling is call-out. The ten shared singletons are named and fenced.

**The hazards are each answered, not just listed.** Single compilation unit → per-agent worktree with a proven 2-second gate. No test net → the Safe/Behavioural/Structural classification, with report-don't-fix as the default. `.meta`/GUID risk → no structural moves in this pass. Vendor decoy → `Assets/Extensions/` excluded by name in the constraints and in every Unit's scope.

**Placeholder scan.** No TBD. The workspace recipe and the compile gate are given as executable commands and were measured before being written down.
