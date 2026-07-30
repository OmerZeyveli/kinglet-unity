# Endless Evolution — Four Parallel Tracks

> **For agentic workers:** each Track is handed to **one agent that spawns its own subagents**. Tracks run simultaneously. Read "Ground rules" and then **only your own Track** — the others are not your business and reading them costs context you will need.

**Goal:** Long-running, genuinely different work on a real Unity game, run in parallel, producing a safety net, documentation an AI can use, a correctness record, and a design for what to change next.

**Repository:** `/home/riive/Documents/GitHub/Endless-Evolution` — capital **H**; a sibling repo uses lowercase `Github`.

**Base branch:** `hardening/base`, which sits on `origin/main` — the current line of development.

---

## Sequencing: Track 1 runs alone, first

The owner's call, and it is the right one. **Track 1 runs by itself. Tracks 2, 3 and 4 start only once it has landed.**

The reason is the dependency the four-way split otherwise hides: **this repository has no automated test of any kind.** Until Track 1 changes that, any code change is unverifiable — a compile proves the syntax, nothing proves the game still plays. Running a redesign Track in parallel with the Track that builds its safety net means the redesign finishes before the net exists.

**What this changes for Tracks 2–4.** With a net in place they are no longer confined to reporting. **They may change code — and each writes tests for what it changes**, using the harness Track 1 established. A change without a test is a change nobody can verify later, including the person who made it.

The Track descriptions below are written for the with-a-net world. Where one says "read-only" or "propose, do not apply", read that as the floor rather than the ceiling: propose first, then implement what you can cover with a test. **If Track 1 reports that this codebase cannot be tested without a structural change the owner has not approved, the floor is where Tracks 2–4 stay** — and that is the honest outcome, not a failure.

---

## Ground rules — every Track

### Unity stays closed

The owner will not have Unity open while you work. **Do not open it, and do not ask them to.**

Your compile gate symlinks `Library/` from the owner's checkout. If Unity runs, it rewrites `Library/ScriptAssemblies` underneath you and your builds fail for reasons that have nothing to do with your code — and you cannot tell that apart from a real failure. Verification in the Editor happens once, at the end, by the owner.

### Your workspace

```bash
MAIN=/home/riive/Documents/GitHub/Endless-Evolution
TRACK=<your track number>

cd "$MAIN"
git worktree add /tmp/ee-track-$TRACK -b hardening/track-$TRACK hardening/base
cp "$MAIN"/*.csproj /tmp/ee-track-$TRACK/          # gitignored, Unity-generated
ln -sfn "$MAIN/Library" /tmp/ee-track-$TRACK/Library
```

If `git status --porcelain` in your worktree shows `Library` as untracked, add it to `$MAIN/.git/info/exclude` once — the tracked `.gitignore`'s `/[Ll]ibrary/` is directory-only and does not match a symlink. Do not edit the tracked `.gitignore`.

### Your compile gate

```bash
cd /tmp/ee-track-$TRACK
dotnet build Assembly-CSharp.csproj \
  -p:BaseIntermediateOutputPath=/tmp/ee-obj-$TRACK/ \
  -p:BaseOutputPath=/tmp/ee-bin-$TRACK/ --nologo
```

**Measured: 2–12 seconds, `0 Error(s)`, writes nothing into the repository.** Run it after every meaningful change.

`Assembly-CSharp-Editor.csproj` is **currently broken** by a stale generated reference and self-heals when the owner next opens Unity. Every worktree inherits it. If your gate reports errors, check they are not that before assuming they are yours.

### What this project is

**~150 first-party files, ~25,300 lines.** `Assets/Extensions/` holds 923 vendored files (MoreMountains/Feel, vFolders, vHierarchy, vInspector) that the project's own guidance already tells agents to ignore. **Do not touch it.** Allocating effort by raw file count spends it almost entirely on vendor code.

**It has a real architecture and it is not Kinglet's** — singleton services with owner-keyed request/release arbitration, and a hand-rolled finite state machine for player and enemy locomotion. Internally coherent on its own terms. No VContainer, no MessagePipe, no UniTask, no Model-View-System.

> **Do not convert this project to Kinglet's patterns.** Those rules describe how new Kinglet projects are built. This one predates them and works. Rewriting a working singleton service into VContainer because a rule file says so would be the most destructive thing an agent could do here. If you find yourself reaching for it, stop and write it down instead.

**There are no tests.** Zero `[Test]`, zero `[UnityTest]`. Track 1 exists to change that; until it lands, nothing automatic catches a behavioural regression anywhere in this repository.

### Unity asset safety

The project's `AGENTS.md` records that `UnityEditor.Events.UnityEventTools` once silently zeroed a persistent `UnityEvent`'s `m_MethodName` override on a nested prefab instance.

- **Never** move or rename a `.cs` file with a bare `mv` or `git mv` — its `.meta` carries the GUID every scene and prefab depends on. Use `AssetDatabase.MoveAsset`, or move file and `.meta` together with the Editor closed.
- Do not hand-edit `.unity`, `.prefab` or `.asset` files.
- Never `git add -A` in a Unity project — stage by name. A stray `mono_crash.mem.*.blob` or a generated `csproj` will land in history.

### The ten shared singletons

`SaveManager` · `SettingsManager` · `PauseService` · `TimeScaleService` · `MusicPlayer` · `SFXPlayer` · `SceneTransitionService` · `VFXManager` · `InputModeController` · `UserInput`

**No Track changes a signature on this list.** Append a notice to `docs/hardening/cross-unit-notices.md` — file, current signature, proposed signature, every call site you found — and let the owner decide. A unilateral change breaks other Tracks silently, and with no test net nothing reports it.

### Read before you start

- `docs/hardening/migration-map.md` — where the project's guidance went, four stale claims found, and gotchas carried out of `AGENTS.md` including **a real pre-existing bug in `DNASample`**.
- The root `AGENTS.md` — its claims were spot-checked and found accurate.
- `docs/hardening/baseline.md` — the compile baseline and its warnings.

### Commit and report

Commit on your own branch, in coherent batches, staged by name. Write your report to `docs/hardening/track-<N>-report.md` in your worktree. Do not merge into `hardening/base` — the owner sequences integration.

---

## Track 1 — Build the safety net

**Own:** a new test tree, and whatever assembly structure tests require. **Do not modify existing game code** except where Task 1 proves it unavoidable, and then only with the reasoning written down first.

This is the highest-value Track because everything else in this repository is currently unverifiable. It is also the one with a real unknown at the front, and **that unknown must be settled before any test is written.**

### Task 1 — Determine how a test can reference this game's code at all

`com.unity.test-framework 1.6.0` is installed. **There is not one assembly definition in first-party code** — all ~150 files compile into the predefined `Assembly-CSharp`.

Unity's rule is that an assembly-definition assembly cannot reference the predefined assemblies. If that holds here, a conventional `Assets/Tests/` with its own asmdef **cannot see a single class in this game**, and no amount of test-writing skill works around it.

**Determine empirically what this project actually permits.** Candidate routes, to be tested rather than assumed:

- Tests in an asmdef that references `Assembly-CSharp` — does Unity accept it, or refuse?
- Tests placed so they compile *into* `Assembly-CSharp` — can the Test Framework discover them, and does `Assembly-CSharp` reference `nunit.framework`?
- `testables` in `Packages/manifest.json`.
- Introducing asmdefs for the game code — a large structural change with `.meta`/GUID risk, and the thing the owner has not asked for.

**Report which routes you tried, what each did, and which one you chose, before writing tests.** If the honest answer is that testing this codebase requires introducing asmdefs, **say so and stop** — that is a decision for the owner, not for you, and it is a genuinely valuable finding on its own.

Also settle: **can tests be run at all without opening Unity?** Unity has a batch-mode test runner. Only one process can hold the project lock, and the owner's checkout is shared — work out whether a worktree can run it, and say what you found. A test that has never executed is worth a fraction of one that has.

### Task 2 onward — build the net, cheapest and highest-value first

Once Task 1 gives you a working route:

**Start with pure logic.** Save-format migration, progression rules, timescale arbitration, state-machine transition tables — anything computable without a scene. These are cheap, fast, and cover the code where a silent break is most expensive.

**`SaveMigration` deserves particular attention.** Save-format changes are irreversible for players who already have saves. The project's own `SaveMigrationTests.cs` is a manually-invoked editor tool, not an automated test — a good specification for what the real tests should assert.

**Then the FSMs.** Player locomotion has 18 state classes; enemies have 7. Transition logic is testable without physics if you can drive the machine directly.

**Do not chase coverage.** A hundred tests that assert getters return what setters set is worse than fifteen that pin real invariants, because it creates the appearance of a net where there is none. Every test you write must be able to fail — construct the failure and confirm it before moving on.

**Do not write tests that pin current behaviour you believe is wrong.** If something looks like a bug, write it up in your report; do not enshrine it in an assertion.

---

## Track 2 — Documentation an agent can act on

**Own:** `docs/systems/`, `CLAUDE.md`, `.claude/` and the guidance tree. **No code changes at all.**

Kinglet Pioneer is installed on this branch and its structures are empty of this project's knowledge. Fill them, so that an agent opening this repository cold can find what it needs without reading 25,000 lines.

The target is documentation **an AI acts on**, which is not documentation a person browses. For each subsystem:

- **What it owns** — the state it is authoritative for, one paragraph.
- **Its real public surface** — the methods other systems actually call, found by grepping call sites, with preconditions. Not a generated API dump.
- **Who calls it and who it calls**, by file name. This is what lets an agent trace a change's blast radius.
- **Invariants and hand-tuned values** — anything where changing a number changes how the game feels. `PlayerMovement`'s coroutine dash-freeze and `Enemy`'s chase-facing dead-zone are the known examples. Flag them; they are exactly what a future agent must not casually adjust.
- **Known gotchas**, including every one already recorded in `AGENTS.md` or `docs/`. Carry them across. They were paid for in someone's debugging time.

**Fix the four stale claims** the migration map found while you are in these files.

**Write for the reader, not for the form.** No marketing adjectives. If a subsystem is genuinely simple, its document is short — padding a thin subsystem to match a template's shape produces documents nobody trusts.

**Where this project diverges from Kinglet's rules, document what the project does.** The rules describe a different kind of project. Guidance that describes an architecture the code does not have is worse than no guidance.

---

## Track 3 — The correctness sweep

**Own:** `docs/hardening/review/`, plus any code you can fix **and cover with a test**. Track 1 has landed, so a fix you can test is a fix you may make.

Go file by file through the ~150 first-party files. For each: do the bindings hold, do the call sites match the signatures, are the lifecycle assumptions sound, is there dead or unreachable code, does anything contradict its own comments?

Unity-specific things worth hunting, from this toolkit's own rules:
- `?.` on Unity objects — bypasses the destroyed-object check that `== null` performs. The most subtle bug class in Unity.
- `GetComponent`, `Camera.main` or `FindObjectOfType` inside `Update`.
- Coroutines that stop silently when a GameObject is deactivated.
- Missing `[FormerlySerializedAs]` on a field whose name changed — silently resets every configured value in every scene and prefab.
- Editor-only API in runtime code without `#if UNITY_EDITOR`.

Fan out to subagents — one per subsystem, or one per file for the large ones. **`PlayerMovement.cs` (948 lines), `Enemy.cs` (1,116) and `SFXPlayer.cs` (1,456) each get one subagent that owns the whole file**, never several working inside the same file.

**Classify every finding** — this is the deliverable's spine:

| Class | Examples |
|---|---|
| **Certain** | It is wrong and the fix is obvious. Dead code, an unused field, a comment contradicting the code. |
| **Behavioural** | Timing, physics values, state transitions, input handling, tuned constants. **Report only.** |
| **Structural** | A file that should be split, a class that should move. **Propose the seam; do not cut it.** |

The bar for "certain" is not *am I confident this is better* — it is **would a wrong answer here stay invisible until someone plays the game.** If in doubt, it is Behavioural.

**Fix the Certain findings, each with a test that fails before your fix and passes after.** No test, no fix — write it up instead. That rule is what keeps a sweep across 150 files from becoming 150 unverifiable edits.

Behavioural and Structural findings stay reports regardless of how confident you are. Track 4 and the owner sequence those.

Your report is still the primary output. A finding written clearly is worth more than a fix nobody can check.

---

## Track 4 — Design for quality and speed

**Own:** `docs/hardening/design/`, and — for proposals you can cover with tests — their implementation. Propose first, implement second, and only what a test can hold.

The owner's stated aim is a project that is faster to develop in and higher quality. Work out what would actually deliver that here, and be concrete enough to be argued with.

Ground it in what exists. Read the code, `AGENTS.md`, `docs/system-inventory.md` and `docs/dependency-map.md`. Then address at least:

**Assembly boundaries.** All first-party code is one compilation unit, so every edit recompiles everything and nothing enforces a dependency direction. Introducing asmdefs would cut compile times, make dependencies explicit, and is very likely a precondition for Track 1's tests. It is also a large structural change with `.meta`/GUID risk. **Propose the specific split**, name what each assembly owns and references, and say what it costs and what it breaks. If Track 1 reports that tests require this, your proposal becomes the path — write it so it can be executed.

**The three large files.** `SFXPlayer.cs` (1,456), `Enemy.cs` (1,116), `PlayerMovement.cs` (948). For each: is it large because the problem is large, or because two responsibilities are tangled? If a split is right, **name the seam** — which methods and fields go where, and what the new boundary's contract is.

**The singleton service pattern.** Ten services with owner-keyed request/release arbitration. That is a real pattern and it works. Where does it hurt — testability, initialisation order, hidden coupling? Is the answer a different pattern, or better discipline within this one? **A recommendation to keep it, argued, is a legitimate outcome.**

**Development speed.** What actually slows work here — compile times, finding things, unclear ownership, manual verification? Rank by how much time each costs.

**Constraints on your proposals:**

- **The net is only as wide as Track 1 made it.** Read what it actually covers before assuming a refactor is safe. A proposal touching untested code stays a proposal — say so explicitly rather than implementing past the coverage.
- **Cost and risk, not just benefit.** A proposal without them is a wish.
- **Sequence them.** Which must come first, which are independent, which are only worth doing together.
- **"Leave it alone" is a real recommendation.** This project works. Say so where it is true.

---

## After the Tracks

The owner opens Unity, lets it reimport, and confirms the game still runs. **That step cannot be delegated and cannot be skipped** — with no test net until Track 1 lands, it is the only thing that verifies the game still works.

Then the four reports are read together. Track 3 says what is wrong, Track 4 says what to do about it, Track 1 says what can now be changed safely, Track 2 says what any of it means. **What actually changes is decided then, by the owner, not by any Track.**
