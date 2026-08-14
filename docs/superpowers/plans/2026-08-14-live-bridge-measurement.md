# Live Bridge Measurement — findings and fix plan

> **For agentic workers:** REQUIRED SUB-SKILL: `.claude/skills/subagent-driven-implementation/SKILL.md`.

**What this is.** The first measurement of this toolkit against a **live Unity MCP bridge and a
shipping game**. Everything below was executed, not read. Bridge: `mcp-for-unity-server 3.4.5`
(`mcpforunityserver==10.1.0`) on `127.0.0.1:8080/mcp`, Unity **6000.0.68f1**, project
**Endless-Evolution** (`StandaloneLinux64`, 1417 `.cs` files, 12 asmdefs, 29 asmrefs), EE `main` at
`bedc4e07`.

**How, given the session could not see MCP.** This Claude Code session started in `kinglet-unity`,
which has **no `.mcp.json`** — so no `mcp__UnityMCP__*` tools here, and none for any subagent either
(subagents inherit the parent session's MCP connections). Two paths were used instead:

1. **A minimal MCP-over-HTTP client** (`initialize` → `notifications/initialized` → call, carrying
   `mcp-session-id`) driving the bridge directly with `curl`. This is what produced every
   tool/action verdict below.
2. **A real headless Claude Code session inside EE** (`claude -p "/unity-doctor"`, read-only
   allowlist, `stream-json`), where EE's own `.mcp.json` + `enableAllProjectMcpServers` connect the
   bridge. 16 turns, 110 s, $1.48. This is what produced the model-behaviour findings.

EE was snapshotted before the run (`bedc4e07`, 0 porcelain lines) and verified unchanged after.

---

## The conclusion that outranks the individual findings

**Prose describing MCP call shapes is close to inert when the bridge is live.** Three independent
measurements, each of a different surface, each arrived at the same place:

- **F1** — `/unity-doctor` told the model to call a resource as a tool. Measured before *and* after
  the fix: **0 attempts** either way, identical call sequences, no observable cost.
- **F2** — a `unity-optimizer` subagent carried **four dead action names in its own system prompt**
  and used the correct ones anyway. **0 attempts** at the dead names across a 602-event trace.
- **F13** — `unity-test-runner`'s results workflow cannot work. It was never exercised: the model
  read *the project's own* `docs/systems/testing.md` and ran the project's harness instead.

The reason is the same in all three: **the model routes by the live tool and resource surface, and by
project-specific documentation, not by the toolkit's prose recipes.** The MCP tool schemas are in the
model's context, they enumerate their own actions, and they outrank a sentence in a system prompt. A
project's own `docs/` outranks a generic agent.

**This should change where effort goes.** The parts of this toolkit a model *cannot* route around are:

- **hooks** — a `PreToolUse` block is not advice. Measured tonight: `bash-gate.sh` stopped the
  controller mid-verification and made it declare intent before proceeding; `block-legacy-input.sh`
  produced 0 false positives across 1417 real files, and F14 shows a hole in it silently disabling
  the gate for whole checkouts.
- **scripts** — `studio-doctor.sh`, `validate-asmdefs.sh`, `install.sh`. These execute and their
  output is the answer. F4 was worth 21 warnings over 800 files on a real project, and fixing it
  changed a real number to a real number.
- **process surfaces** — `unity-brainstorming`, `unity-planning`, `/unity-review`. These shape
  *judgment*, not tool syntax, and the measurements show them doing real work: refusing to build from
  a 3/10 request, catching that a stated premise did not transfer between a kinematic and a
  force-based mover, and finding two defects in a file that nobody planted.

The MCP-recipe prose still deserves to be correct — a wrong sentence is wrong, it misleads human
readers, and it would bite wherever the schema is absent. But it is not where this toolkit earns its
keep, and this document should not pretend otherwise.

---

## Findings

### F1 — `/unity-doctor` Check 1 calls a resource as if it were a tool  (payload)

`.claude/commands/unity-doctor.md:13` says *"Attempt to call `project_info` via MCP"*. Executed:

```
tools/call project_info        → {"content":[{"text":"Unknown tool: 'project_info'"}],"isError":true}
resources/read mcpforunity://project/info
                               → {"unityVersion":"6000.0.68f1","platform":"StandaloneLinux64", …}
```

`project_info` is one of 19 **resources**, not one of the 48 tools. The server's own instructions are
explicit that names and URIs are not interchangeable.

**What the model actually did — measured before AND after the fix, and the honest answer is that
nothing changed.** The headless run did not follow the instruction. It called `ToolSearch` for
`ListMcpResourcesTool`/`ReadMcpResourceTool`, listed the server's resources, read
`mcpforunity://project/info`, and reported **`MCP Server: PASS (Unity 6000.0.68f1, LinuxEditor /
StandaloneLinux64, not in play mode, idle, ready_for_tools=true)`**. The predicted false `ERROR` did
not occur.

**This section first claimed the model "repaired the instruction at a cost of two extra tool calls."
That was wrong, and re-running the doctor after installing the fix into the same project proves it:**

| | turns | tool calls | `ToolSearch` | `ListMcpResourcesTool` | `ReadMcpResourceTool` | `project_info` as a **tool** |
|---|---|---|---|---|---|---|
| before (F1 present) | 16 | 14 | 1 | 1 | 2 | **0 attempts** |
| after (F1 fixed) | 14 | 12 | 1 | 1 | 2 | **0 attempts** |

The opening sequence is identical in both — `Skill` →
`ToolSearch(select:ListMcpResourcesTool,ReadMcpResourceTool)` → `studio-doctor.sh` →
`ListMcpResourcesTool` → … — and **neither run ever attempted `project_info` as a tool.** That
`ToolSearch` is a harness requirement (both resource tools are deferred and must be loaded before
use), not a repair, and it happens the same way with the corrected text. The instruction was wrong
and cost **nothing observable**. Step 3's ERROR branch is still worth keeping honest for a bridge
that is genuinely down, but no measured behaviour was bought by this fix.

Same citation at `.claude/commands/unity-init.md:84`.

### F2 — `unity-optimizer`'s profiling recipe: 4 of its 6 lines name actions that do not exist (payload)

`.claude/agents/unity-optimizer.md`, Step 1 — the agent's **first** action. Every line executed
against the live editor:

| line | cited | result | actual |
|---|---|---|---|
| 44, 90 | `manage_profiler action:"start_session"` | `success:false — Unknown action` | `profiler_start` |
| 45, 91 | `manage_profiler action:"get_frame_timing"` | **works** (`cpu_frame_time_ms` …) | — |
| 46 | `manage_profiler action:"get_counters"` | **works** | — |
| 47 | `manage_profiler action:"memory_snapshot"` | `success:false — Unknown action` | `memory_take_snapshot` |
| 48 | `manage_graphics action:"get_rendering_stats"` | `success:false — Unknown action` | `stats_get` |

`stats_get` returns real data (`draw_calls`, `batches`, `set_pass_calls`, `triangles`, …), so the
capability exists and only the name is wrong.

**CORRECTION, 2026-08-14, after the fix shipped.** This section first stated that
`memory_take_snapshot` *"additionally requires `com.unity.memoryprofiler`, which EE does not have"*,
and Task 1's implementer — which has no MCP access — faithfully wrote that precondition into
`unity-optimizer.md:47`. **It is false.** Executed afterwards on EE, whose manifest has no such
package (`grep -c memoryprofiler Packages/manifest.json` → 0), the call wrote a real **253,428-byte**
`.snap` file. Taking a snapshot is a built-in engine API; the package supplies the analysis window.

The claim came from the MCP server's own tool description — *"MEMORY SNAPSHOT (requires
com.unity.memoryprofiler)"* — copied into a brief as fact without being run. That is this wave's own
defect class, committed by the document warning against it, and the lesson is the sharper half of the
finding: **a server's description of its tool is not evidence about the tool, any more than a
surface's description of its behaviour is evidence about the behaviour.** Both must be executed.

### F11 — `get_counters` is cited with no parameters and cannot run as written (payload)

`unity-optimizer.md:46` reads `manage_profiler action:"get_counters" → specific performance
counters`. Executed exactly as written it returns `success:false` with an **empty message** — the
least diagnosable of the five failures, since there is not even an "unknown action" string to search
for. `category` is required:

```
{"action":"get_counters"}                      → FAIL, message: None
{"action":"get_counters","category":"Memory"}  → OK, "Captured 44 counter(s) from 'Memory'."
{"action":"get_counters","category":"Render"}  → OK, "Captured 569 counter(s) from 'Render'."
```

This also corrects a verdict recorded earlier in this document: the first pass classified
`get_counters` as *resolves*, having checked only that it was not an unknown action. **It resolves as
an action name and fails as a call.** The distinction matters structurally, not just here — an
action-name allow-list, which is what the new `tests/test-mcp-citations.sh` guards, is
constitutionally unable to see a missing required parameter. That gap belongs in the guard's
blind-spot list, not in a claim that the guard covers citations.

### F3 — the failure shape is invisible to a caller that checks only the tool error (payload)

An unknown action returns **`isError: false`** at the MCP layer, carrying `"success": false` in the
body. A model that branches on the tool-call error flag sees a successful call. `unity-mcp-patterns`
Rule 2 says "don't assume operations succeeded", but nothing states *this* shape, which is the one
that produced F2's silent failures.

### F4 — `validate-asmdefs.sh` does not know `.asmref` exists  (repo script, ships as `.claude/scripts/`)

```
grep -rn 'asmref' scripts/ .claude/     → no matches anywhere in the toolkit
```

Its "C# files without assembly definition coverage" check reads `.asmdef` only. On EE this produced
**21 warnings covering 800 files**, every one false: EE has **29 `.asmref` files** (8 first-party, 21
under `Assets/Extensions/`) extending assembly scope into `Assets/Core/`, `Player/`, `Enemies/`,
`Environment/`, `PlayerPrefsEditor/` and MMFeedbacks.

Cross-validated from two independent directions by the headless run: `Library/ScriptAssemblies/` has
**no `Assembly-CSharp.dll`** (which would exist if 800 files really were uncovered), and Unity's own
generated `EndlessEvolution.Runtime.csproj` compiles those folders. The fixture has no `.asmref`,
which is why this survived every prior suite run.

### F5 — GNU-only regex atoms across the hooks, against the repo's own stated rule (payload)

`block-legacy-input.sh` documents the rule at its `LEGACY` pattern: *"`\b` is a GNU extension and
`.claude/UPSTREAM` plans a macOS host pass, where grep is BSD"* — and writes an explicit character
class instead. Ten sites in five hooks then use `\b`, `\s` or `\w` anyway, including
**`block-legacy-input.sh:86` itself**, one line after the comment:

```
bash-gate.sh:914            \b(main|master|develop|release)\b
block-legacy-input.sh:86    #if\s+(ENABLE_LEGACY_INPUT_MANAGER|UNITY_EDITOR)
warn-filename.sh:51         :\s*(MonoBehaviour|ScriptableObject|…)
warn-filename.sh:46,77      (class|struct|interface)\s+$FILENAME\b   /   (class|struct)\s+\w+
warn-platform-defines.sh:38,40,44
warn-serialization.sh:37,38
```

**Not tested on BSD** — there is no macOS host here. This is reported as an inconsistency against the
repo's own written standard, not as measured breakage. Note the failure mode if the standard is
right: `warn-filename.sh`'s guards would stop matching and the hook would fall through to `exit 0`,
i.e. **warn nothing, silently**.

### F6 — `warn-platform-defines.sh` has no third-party exclusion, unlike its sibling (payload)

`block-legacy-input.sh` skips `*/Assets/Extensions/*`, `*/Assets/Plugins/*`, `*/Assets/ThirdParty/*`,
`*/Assets/PlayerPrefsEditor/*`, `*/Packages/*`, `*/Library/*`. `warn-platform-defines.sh` skips
nothing (`grep -c 'Extensions|Plugins|ThirdParty'` → 0). Fired on **4 of 1417** real files, all four
in `Assets/Extensions/Feel/` (third-party). Low volume, but it is noise the sibling hook was
deliberately taught to suppress.

### F7 — `unity-mcp-patterns` tool-group table: one row drifted (payload, minor)

The table is otherwise **exactly right** against the live server — all 10 groups, every
`default_enabled`, every membership, and `default_enabled = ['core']`. One row drifted: `asset_gen`
lists 4 tools, server 3.4.5 ships **5** (adds `import_model_file`). The skill stamps its own
provenance — *"Verified against MCP for Unity 10.1.0 (server 3.4.4)"* — which is precisely why this
drift is legible instead of silently wrong. Its counts (29 before activation / 42 after) were taken
on 3.4.4; this host exposes 48 with all groups active.

### F8 — EE's `CLAUDE.md` still claims 39 skills  (EE repo, not the toolkit)

`CLAUDE.md:244` — *"The 39 skills in `.claude/skills/` do not."* Live count is **16**. The line is
outside the `kinglet:generated` block (which starts at 253), so it is EE's own prose, written
2026-08-03 in `a7532b89`. The 2026-08-14 re-baseline rewrote "How to work" and missed this bullet.
Found by the headless doctor run, not by any guard.

### F9 — `/unity-ui` names `manage_ui` for UGUI, which is backwards, and nothing activates its group (payload)

`.claude/commands/unity-ui.md:61` — *"UGUI: Canvas, panels, buttons, text via `manage_ui` + `manage_gameobject`"*. Two defects in one line:

- **`manage_ui` is not a UGUI tool.** Its live action enum is entirely UI Toolkit: `attach_ui_document`, `detach_ui_document`, `create_panel_settings`, `update_panel_settings`, `get_visual_tree`, `link_stylesheet`, `modify_visual_element`, `render_ui`. There is no Canvas, Button or RectTransform in it. The very next line — *"UI Toolkit: write UXML/USS files, attach UIDocument component"* — is the one that should be calling it.
- **`manage_ui` is in the `ui` group, `default_enabled: false`**, so on a default install it is not in `tools/list` at all and a call fails as *unknown tool*. `unity-optimizer`, `unity-test-runner` and `unity-fixer` each open with a `manage_tools(action="activate", group=…)` preamble for their group. `unity-ui-builder.md` — the agent this command dispatches to, and the one holding `mcp__UnityMCP__*` — has no preamble and **never names `manage_ui` anywhere in its body**. Its UI Toolkit workflow writes UXML and USS through the plain `Write` tool.

Derived across the whole payload: of the nine non-default groups, `ui` is the only one cited by a command whose dispatch chain activates nothing.

### F10 — a copyable code sample uses an API deprecated in the toolkit's own target version (payload)

`.claude/skills/save-system/SKILL.md:377`:

```csharp
foreach (var mb in FindObjectsOfType<MonoBehaviour>(true))
```

Reflected against the live editor:

```
Object.FindObjectsOfType   is_obsolete=True   "has been deprecated. Use Object.FindObjectsByType instead."
Object.FindObjectsByType   is_obsolete=False
```

Every other mention of this API family in the payload is an **avoid-this** instruction — `performance.md`'s allocation table, `architecture.md`'s no-singletons rule, `unity-reviewer`'s checklist. This one is a sample a model is meant to copy, and copying it emits a deprecation warning in any Unity 6 project. The `(true)` overload maps to
`FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Include, FindObjectsSortMode.None)` — and `SortMode.None` is the right choice here, since a save system enumerating every MonoBehaviour has no use for sorted results.

Checked and clean at the same time: `Physics.RaycastNonAlloc`, `OverlapSphereNonAlloc`, `SphereCastNonAlloc` and `Component.CompareTag` are **not** deprecated in 6000.0.68f1 — `is_obsolete=False` on all 21 overloads — so `performance.md`'s non-allocating-variant guidance stands as written. (A first pass here reported them all obsolete; that was a substring match against a blob that contains an `is_obsolete` key on every overload. Read the per-overload flag, never the serialized record.)

---

## What passed, measured rather than assumed

These are recorded because a wave that reports only defects teaches nothing about what holds.

- **`block-legacy-input.sh`: 0 false blocks on 1417 real files.** Its `Assets/Extensions/` exclusion
  was written for this exact project — the comment says *"Feel/MoreMountains alone ships 16"*, and
  EE's Feel copy is where 19 of its 20 legacy-input files live.
- **The one first-party legacy-input file passes correctly.** `Assets/Core/Debug/PerfProbe.cs` is
  editor-only by whole-file `#if UNITY_EDITOR` (line 1 to line 312) and guards its
  `Input.GetKeyDown(KeyCode.F9)` behind `#if ENABLE_LEGACY_INPUT_MANAGER` with a parallel
  `#if ENABLE_INPUT_SYSTEM` branch. The hook exits 0 on it by an explicit dual-path clause whose
  guidance text uses `KeyCode.F9` — the same key. It was written with this file open.
- **`warn-filename.sh`: 0 warnings on 1417 files, and that zero is correct.** Its real gate is
  line 46 — *does the file define any type named like the file* — which every EE file satisfies. A
  probe that instead compared the **first** `class|struct` token found 336 "mismatches" that are
  English words lifted out of doc comments (`answers`, `with`, `rather`). The hook never reaches that
  extraction. The probe was wrong; the hook was right.
- **Every hook's positive control fires**, so none of the zeros above is silence:
  `block-legacy-input` rc=2/823 B, `warn-filename` 388 B, `warn-serialization` 450 B,
  `warn-platform-defines` 484 B.
- **`mcp__UnityMCP__*` is the correct casing**, confirmed against the running server for the first
  time. `verification-before-completion` records a 2026-08-03 whole-branch review that reasoned from
  this repository's own habit and changed it to the broken `mcp__unityMCP__`; the live server
  registers as `UnityMCP`.
- **Every other cited tool and action resolves**: `manage_scene action:"validate"`,
  `manage_tools(action="activate", group=…)` (and `profiling`/`testing`/`docs` really are
  `default_enabled: false`, so the three agents' activation preambles are right),
  `get_frame_timing`, `get_counters`, `unity_reflect` (`search`/`get_type`/`get_member`).
- **The install is healthy on a shipping game.** `studio-doctor.sh` → `9 passed · 5 warning(s) ·
  0 failure(s)`, exit 0; all five warnings are the one known `settings.json` receipt collision, which
  is `bedc4e07` — the `block-projectsettings.sh` registration put back after the re-baseline dropped
  it. 13 hooks all registered, executable, on the right events.

### F13 — `unity-test-runner`'s "run tests" step cannot get test results (payload)

`.claude/agents/unity-test-runner.md`, Step 4, is the whole point of the agent:

```
run_tests → execute all tests or specific test fixture
read_console → check for test output and results
```

**Both lines are wrong, and each was executed against the live editor on this project's real
EditMode suite.**

`run_tests` is **asynchronous**. It returns immediately with a handle, not results:

```json
{"success":true,"message":"Test job started.",
 "data":{"job_id":"abde6087…","status":"running","mode":"EditMode"}}
```

The results come from `get_test_job`, which the agent names **only** in its group-activation
preamble and never in its workflow:

```json
{"status":"succeeded",
 "result":{"summary":{"total":1,"passed":1,"failed":0,"skipped":0,
                      "durationSeconds":0.1486,"resultState":"Passed"}},
 "progress":{"completed":1,"total":1,"stuck_suspected":false,"blocked_reason":null,
             "editor_is_focused":true,"failures_so_far":[]}}
```

And `read_console` — the fallback Step 4 actually prescribes — carries **none** of it. Read straight
after the run, it returned thread-niceness warnings, an MCP WebSocket error, and
`[TestRunnerNoThrottle] Applied No Throttling for test run.` Infrastructure noise, no counts.

So the agent's Step 5 (*"list passed/failed/skipped counts"*) is asked to report numbers that its own
Step 4 never obtains. `get_test_job` also takes `wait_timeout`, which is the clean way to block until
completion, and its `progress` block carries `stuck_suspected` and `blocked_reason` — exactly the
states a test-running agent needs and currently cannot see.

### F14 — `*/Packages/*` and `*/Library/*` are unanchored, and the gate switches off silently

Found by Task 3 while copying `block-legacy-input.sh`'s skip list into its sibling, and recorded
there as a `KNOWN HOLE` rather than fixed in one hook of a pair. Confirmed independently by
execution:

| path | result | should be |
|---|---|---|
| `/home/dev/MyGame/Assets/Scripts/Player.cs` | rc=2, 790 B — blocked | blocked |
| `/home/dev/Projects/**Packages**/Game/Assets/Scripts/Player.cs` | **rc=0, 0 B — allowed** | blocked |
| `/home/dev/**Library**/MyGame/Assets/Scripts/Player.cs` | **rc=0, 0 B — allowed** | blocked |
| `/home/dev/MyGame/Packages/com.foo/Runtime/Player.cs` | rc=0 — skipped | skipped |
| `/home/dev/MyGame/Assets/Extensions/Feel/Player.cs` | rc=0 — skipped | skipped |

`*/Assets/Extensions/*` and its siblings are anchored by the `Assets/` segment; `*/Packages/*` and
`*/Library/*` are not, and cannot be by that means, because the hook does not know the project root.
Any checkout living under a directory named `Packages` or `Library` loses the gate entirely, with no
error — the exact shape of the 2026-08-13 `*/Tests/*` and `*/Editor/*` anchoring defect, which was
fixed then and reintroduced here by inheritance.

**`~/Library/` is a standard location on macOS**, and `.claude/UPSTREAM` plans a macOS host pass, so
this is not a hypothetical path.

**The fix has a clean anchor available.** In a Unity project every first-party runtime file has
`/Assets/` in its path, while engine and package content under `<root>/Packages/` and
`<root>/Library/PackageCache/` does not. Keying on the presence of `/Assets/` — rather than on the
absence of two unanchored segment names — classifies all five rows above correctly. Whoever
implements it must decide what to do about a package that ships an `Assets/` folder inside itself,
and say so.

### F15 — the 2D non-allocating physics family is deprecated; the 3D one is not (payload)

Found by reflecting **every** `Type.member` reference in the payload against the live editor — 40
distinct references extracted from `.claude/`, each resolved through `unity_reflect`. Exactly one was
a live defect, and it is one no offline reader could have settled, because the 2D and 3D families
look symmetric and are not:

| API | overloads obsolete | verdict |
|---|---|---|
| `Physics.OverlapSphereNonAlloc` | **0 / 3** | fine |
| `Physics.RaycastNonAlloc` | **0 / 8** | fine |
| `Physics2D.OverlapCircleNonAlloc` | **4 / 4** | *"deprecated. Use Physics2D.OverlapCircle instead."* |
| `Physics2D.RaycastNonAlloc` | **4 / 5** | *"deprecated. Use Physics2D.Raycast instead."* |
| `Physics2D.CircleCastNonAlloc` | **5 / 5** | *"deprecated. Use Physics2D.CircleCast instead."* |
| `Physics2D.BoxCastNonAlloc` | **5 / 5** | *"deprecated. Use Physics2D.BoxCast instead."* |
| `Physics2D.OverlapBoxNonAlloc` | **4 / 4** | *"deprecated. Use Physics2D.OverlapBox instead."* |
| `Physics2D.OverlapCircle` / `Physics2D.Raycast` | 0 / 6 and 0 / 8 | fine |

Unity 6 gave the plain 2D names overloads that take a `ContactFilter2D` and a `List<T>` or results
array, so the plain name **is** the non-allocating call now and the `NonAlloc` suffix was retired.

**`.claude/skills/physics/SKILL.md:126` teaches the retired one**, in a 3D→2D equivalence table:

```
| `Physics.OverlapSphereNonAlloc` | `Physics2D.OverlapCircleNonAlloc` |
```

The left column is correct and the right column is deprecated — which is exactly why this survived:
the row looks internally consistent. **The project this toolkit was measured on is a 2D game**, so
this is the column a model working on it would copy. `performance.md`'s allocation table is clean; it
names only 3D `RaycastNonAlloc`.

### Also settled with the live editor: `Rigidbody.drag`

Task 4 found `.claude/agents/unity-scene-builder.md:125` — *"Configure Rigidbody properties (mass,
**drag**, gravity, constraints)"* — and deliberately left it, on the correct ground that without a
live editor it could only swap one guess for another. Measured now:

```
Rigidbody.drag           obsolete = True        Rigidbody.linearDamping     obsolete = False
Rigidbody.angularDrag    obsolete = True        Rigidbody.angularDamping    obsolete = False
Rigidbody.mass           obsolete = False
```

So the prose should name `linearDamping`. The separate question Task 4 raised — which key
`manage_components` expects — is not answered by this and should not be guessed at either.

---

## The model-behaviour measurement, which is what this repository has never had

Two headless Claude Code sessions ran **inside EE** with the bridge live. Both are recorded because
"what a surface says" and "what a model does with it" turned out to differ in both directions.

### `/unity-doctor` — the model routed around a broken instruction

16 turns, 110 s, $1.48. Told to *call* `project_info`, it instead called `ToolSearch` for
`ListMcpResourcesTool`/`ReadMcpResourceTool`, listed the server's resources, found the URI, read it,
and reported `MCP Server: PASS`. **The predicted false ERROR did not occur.** It also went beyond the
command — ran `validate-asmdefs.sh`, cross-checked its 800-file warning against
`Library/ScriptAssemblies/` and Unity's generated `.csproj`, and correctly called it a false positive
(F4). It found F8 unprompted. A capable model repairs F1; a weaker one gets step 3's ERROR branch.

### An ordinary feature request — the chain fires, and it refuses to build

25 turns, 96 s, $1.23. Prompt, in Turkish, of the kind a designer actually types: *"I want to add a
slow-motion power-up: when the player picks it up, everything slows down briefly. How should we do
it?"*

**The first tool call was `Skill: unity-brainstorming`** — before any file was read, before any
answer. That is `using-kinglet`'s central rule (*"invoke the surface before any response or action"*)
holding under a real request rather than a test.

What it then did, every claim of which was verified against the files afterwards and **none of which
was hallucinated**:

- Found that the project **already has the mechanic's infrastructure** — `Assets/Core/Time/TimeScaleService.cs`,
  an owner-keyed arbiter that owns `Time.timeScale`, scales `Time.fixedDeltaTime` proportionally from
  a baseline captured at startup, and exposes `RequestScaleOverTime` / `ReleaseScaleOverTime`. It
  concluded no new time system was needed.
- Found an **exact working precedent**: `HummingbirdFly.cs:316-317` already requests a slow-motion
  scale, and `:384-388` compensates player speed with
  `Mathf.Min(1f, slowMotionScale / Mathf.Max(currentScale, 0.01f))` so the world slows while the
  player does not. Both line citations are correct.
- Applied **the project's own conventions**, not just the toolkit's: `TimeScaleService.Instance` must
  be null-checked with `!= null` rather than `?.` — and the cited line in EE carries the comment
  *"static can hold a corpse that `?.` reads as live"*, which is `unity-specifics.md`'s `?.` rule
  already embedded in the game's source. It also noted the arbiter is a **min-fold**, so a pause (0f)
  always wins over a power-up's 0.5f.
- Scored the request's ambiguity **3/10 against a threshold of 6** and **asked instead of building**
  — one question at a time, with a recommendation and the reason for it, exactly as
  `unity-brainstorming` specifies.

**This is the answer to "does any of this improve game development".** Not the guards, not the
provenance manifest — this. An unprompted request produced a grounded design conversation that found
the existing system, refused to duplicate it, cited the project's own rules, and declined to write
code from a vague brief. It needed no MCP at all: `Read`, `Grep`, `Glob`, `Bash`.

### `/unity-review` — five planted pitfalls found, plus two nobody planted

11 turns, 200 s, $1.18. Five deliberate defects were written into one **editor-only** file
(`Assets/Core/Debug/PerfProbe.cs`) on a throwaway branch: uncached `GetComponent<Renderer>()` in
`Update`, uncached `Camera.main` in `Update`, `?.` on a Unity `Object`, `renderer.material` (which
clones and breaks batching), and per-frame string concatenation. **All five were found**, each
anchored to file and symbol, each tied back to the rule it violates.

Two findings were **not planted, and the controller did not know them**:

- **The method could never have worked.** The probe's GameObject is built bare at `PerfProbe.cs:56-58`
  — `new GameObject("_PerfProbe")` then `AddComponent<PerfProbe>()`, nothing more — so
  `GetComponent<Renderer>()` returns null on every frame and the tint the comment promises cannot
  happen. `_overlayLabel` was written and read nowhere: a tree-wide grep returns exactly two hits,
  the write and the declaration. Verified independently afterwards; both claims hold.
- **The allocations corrupt the file's own purpose.** `TintOverlay()` was called as the first
  statement of `Update()`, and `PerfProbe` samples `_gcBytesPerFrame`, `_gcAllocsPerFrame` and
  `_behaviourNs` from `ProfilerRecorder`s later in that same `Update()`. So a tool whose entire job
  is measuring GC now allocates inside its own measurement window and writes the contamination into
  its own JSON. Verified: the counters really are sampled at lines 152-156.

The second one is the difference between a linter and a review. Nothing in the toolchain could catch
it — the run confirmed that too, rather than assuming it: `validate-serialization.sh` clean, the
project's compile gate green with only three pre-existing `CS0649`s, and `_overlayLabel` never
tripping `CS0414`.

**EE was fully restored**: branch deleted, `PerfProbe.cs` byte-identical to `main`, `git status`
clean, HEAD `92b27d6c`.

### `/unity-test` — the broken workflow never ran, because the project had a better one

7 turns, 220 s, $0.95. Asked in plain Turkish to run the EditMode tests and report pass/fail counts.
**It did not touch MCP at all.** It invoked the command, read **the project's own**
`docs/systems/testing.md` and a project memory file, then ran EE's own harness
(`docs/hardening/run-editmode-tests.sh`) and reported `total=1098 passed=1098 failed=0 skipped=0`.

It read the **exit code** rather than the summary line, because EE's document insists on that
(`2 = tests failed`, `1 = compile failure`, `3 = harness problem`) — a rejected run can leave stale
XML behind that reads green. It also noticed that 1 of the 1098 cases belongs to the Addressables
package rather than the project, and that EE's doc records 1060 from a 2026-08-02 measurement, which
that doc already declares will drift.

**So F13's practical cost on this project is zero** — the model preferred project-specific
documentation over the toolkit's agent, which is the correct precedence and what
`architecture.md`'s own "the generated block is newer" clause asks for. F13 still binds on any
project **without** its own harness, which is every fresh install. The finding stands; its blast
radius is narrower than it looked.

**F12 recurred here**, second of two: `/unity-test` also routes to an agent, and also did not
dispatch one.

### `/unity-optimize` — the dead citations cost nothing, and the surface found three real defects

16 turns, 836 s, **$11.48** — by far the most expensive run, two `unity-optimizer` dispatches plus a
deep asset scan. Run against EE's **installed, pre-fix** agent, whose Step 1 still carried all four
dead actions.

**The dead citations were never attempted.** Grepped across the whole 602-event trace:
`start_session` 0, `get_rendering_stats` 0, `memory_snapshot` 0, `Unknown action` 0. The subagent
carried that recipe **in its system prompt** and used `stats_get`, `profiler_status`,
`get_frame_timing` and `get_counters` **with a category** anyway — because the live MCP tool schemas
were in its tool list, and `manage_graphics`'s own description enumerates `stats_get`. It also called
`manage_tools list_groups` and activated `profiling` and `docs` first, exactly as
`unity-mcp-patterns` Rule 4 instructs.

**So F2's measured blast radius on a live bridge is zero.** The tool schema outranks prose in the
system prompt, and the model reads the schema. Fixing the citations was still right — they are wrong,
they mislead a reader, and they would bite wherever the schema is *not* in context (planning offline,
writing a script, a weaker model that trusts prose). But this document should not claim a severity
the measurement contradicts.

**What the surface actually produced** — three real defects in a shipping game, each verified
independently afterwards:

1. **884 of 985 sprite `.meta` files carry a `buildTarget: Standalone` block, and not one has
   `overridden: 1`.** The override exists, says `textureCompression: 1`, and is completely inert;
   879 textures are uncompressed. RGBA32 instead of BC7 is ~4× VRAM across nearly the whole sprite
   budget. One setting, largest win, lowest risk. (The run reported 978 uncompressed; the
   reproducible count is **879 of 985**, so the number quoted here is the measured one.)
2. **Zero sprite atlases** across 987 first-party textures — `/usr/bin/find Assets -name '*.spriteatlas*'`
   returns nothing — while `Assets/Core/Input UI/InputGlyphSet.asset` pulls **137 glyphs as
   individual loose PNGs**, and the package's own ready-made atlas
   `Assets/Sprites/UI/kenney_input-prompts-pixel/Tilemap/tilemap_packed.png` sits in the repo
   unreferenced.
3. **A second full Base camera renders every frame with culling switched off.** `WaterCamera` in
   `Assets/Environment/2DWater/Prefabs/WaterReflection.prefab`: `m_CameraType: 0` (Base, not
   Overlay), `m_CullingMask.m_Bits: 4294967295` — all 32 layers — rendering into a render texture.
   The prefab's GUID appears in **50 scene files**, including `MainMenu.unity`.

**And it was honest about what it could not measure.** An unsaved, empty scene was open, so
`draw_calls`, `batches` and `triangles` were all 0 and `render_target_changes: 0` proved no camera
ran the pipeline that frame. It explicitly refused to load a scene — that would raise a modal
"Save changes?" dialog, block Unity's main thread and lock the bridge — and warned that the live
`cpu_frame 52 ms` is idle editor repaint and must not be quoted as game performance. It labelled its
own output a **static render configuration audit, not a frame profile**.

### `bash-gate.sh` blocked the controller, correctly, mid-verification

While verifying finding 1 above, a read-only command over `.meta` files was **blocked** by the
toolkit's own hook: *"this gate could not parse this command's quoting
(substitution-or-ansi-c-quoting), so it cannot tell which command runs over these files."* It
demanded a one-line read/write declaration and a byte-identical retry, and named the recorded key.
Declaring it a read and retrying byte-identically passed. First observation of this hook firing on an
unplanned command in a live session rather than on a test payload — the guidance was actionable and
the unblock protocol worked exactly as written.

### F12 — `/unity-review`'s dispatch is defeated by a common user-level instruction (payload)

The run reported: *"`/unity-review` defaults to dispatching the `unity-reviewer` agent, but your
standing instruction is not to call the Agent tool unless you ask. I ran the review inline instead."*
The user's global configuration forbids unrequested `Agent` calls, and that instruction outranks a
command body. The model improvised correctly and said so — but the command assumes a dispatch that
will not happen in this environment, and says nothing about what to do when it cannot. Every
`/unity-*` command that routes to an agent shares the assumption.

## Tasks

**Global constraints.** Both gates bind for every toolkit change: `bash tests/run-tests.sh`
(timeout ≥ 400000 ms; strip ANSI before counting `--- test-*.sh ---` headers) and
`bash scripts/check-provenance.sh` == `provenance OK`. A new file with no `provenance.tsv` row fails
as an orphan. `/usr/bin/grep` and `/usr/bin/find` for absence claims — interactive `grep` is
`ugrep 7.5.0` and `find` is `bfs 4.1.1`. No `declare -A`, no `grep -oP`. Under `set -euo pipefail`
never pipe into a reader that exits early (`head`, `grep -q`) — use a here-string.

### Task 1: The MCP citations that do not resolve  (F1, F2, F3, F7)

Fix the four cited actions in `unity-optimizer.md` (`profiler_start`, `memory_take_snapshot`,
`stats_get`), stating the `com.unity.memoryprofiler` precondition on the snapshot line. Fix
`project_info` in `unity-doctor.md` and `unity-init.md` to read the **resource**
`mcpforunity://project/info`, and keep the ERROR branch for a genuinely unreachable bridge. Add F3's
failure shape to `unity-mcp-patterns` (an unknown action is `isError:false` + `success:false`).
Correct the `asset_gen` row to 5 tools and restamp the skill's verified-against line to server 3.4.5.

**The guard matters more than the fix.** Nothing in the suite can currently tell that a cited action
is dead, because checking requires a live editor. Add a test that at minimum keeps every cited
`<tool> action:"<action>"` pair inside a recorded allow-list derived from this measurement, so a new
dangling citation fails the suite offline. Record in the test's own header that it verifies against a
**snapshot** of server 3.4.5, not against a live server, and that the snapshot is the thing that
rots.

### Task 2: `.asmref` support in `validate-asmdefs.sh`  (F4)

Teach the coverage check that a `.asmref` file extends the nearest enclosing assembly. An `.asmref`
is JSON with a single `"reference"` key naming either an assembly name or a `GUID:<hex>`. Both forms
occur in EE — check both before assuming. Add a fixture variant carrying an `.asmref` so the
regression is covered offline; `tests/fixtures/mkproject.sh` already takes `--variant`.

Verify against EE, which is the case that produced the finding: 21 warnings covering 800 files must
drop to whatever the real uncovered set is, and the number must be justified rather than assumed to
be zero.

### Task 3: Hook consistency  (F5, F6)

Replace the GNU-only atoms at the ten sites with the explicit character classes
`block-legacy-input.sh` already models, and give `warn-platform-defines.sh` the same third-party skip
list as its sibling. Every hook has a behavioural probe in `tests/test-hook-behaviour.sh` — each
changed hook must still act and still be killable, and the third-party skip needs its own probe
proving a `*/Assets/Extensions/*` path is passed over while a first-party one still warns.

### Task 4: The UI chain and the deprecated sample  (F9, F10)

Move `manage_ui` off the UGUI line in `.claude/commands/unity-ui.md` and onto the UI Toolkit line
where its actions actually apply, and give the UI chain the group-activation preamble its three
sibling agents already carry — in `unity-ui-builder.md`, matching their wording, since that is the
agent holding the MCP tools. Decide deliberately whether `unity-ui-builder` should call `manage_ui`
at all or keep writing UXML/USS as files: **either answer is defensible, but the command and the
agent must give the same one.** Today they disagree and neither can act on `manage_ui`.

Replace the deprecated call in `.claude/skills/save-system/SKILL.md:377` with
`FindObjectsByType<MonoBehaviour>(FindObjectsInactive.Include, FindObjectsSortMode.None)` and keep
the surrounding comment true to what the new call does. Then sweep the payload's C# samples for
other APIs deprecated in Unity 6 — this one was found by reflecting a live editor, and the same
class of drift is what `unity-mcp-patterns` warns about when it says training data carries outdated
Unity APIs.

### Task 5: The test workflow that cannot read its own results  (F13)

Rewrite `unity-test-runner`'s Step 4 around the job handle: `run_tests` returns `job_id` +
`status:"running"`, and `get_test_job(job_id, wait_timeout, include_details)` is where the summary
and the per-test results live. Step 5's "list passed/failed/skipped counts" then has a source. Keep
`read_console` in the workflow for **compile errors**, which is what it is genuinely good for, and
say plainly that it does not carry test results — the current text implies it does.

Surface `progress.stuck_suspected` and `progress.blocked_reason`: a test run that hangs is the
failure mode an agent most needs to recognise and currently has no way to name.

Check `/unity-test`'s command body for the same assumption before deciding the fix is confined to the
agent.

### Task 6: EE's stale skill count  (F8)

In the **EE repo**, not this one: `CLAUDE.md:244`, 39 → 16. Check the surrounding bullet for anything
else the 2026-08-14 re-baseline left stale, and derive the number rather than copying it from here.
