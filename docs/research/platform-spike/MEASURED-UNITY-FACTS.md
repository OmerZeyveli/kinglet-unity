# Measured Unity behaviour — reference

Every fact here was **executed and observed**, not reasoned. Each was expensive to learn and three
of them corrected the plan text. They lived only in gitignored SDD scratch until 2026-07-28; this
file exists so they survive and so an agent on another host does not rediscover them the hard way.

Host: Pop!_OS 24.04 x64, Unity `6000.3.18f1` revision `5ebeb53e4c07`, batchmode.
Anything below that was *inferred* rather than observed is labelled as such.

---

## Exit codes are disjoint — and exit 0 is not proof

| Condition | Unity exit | `results.xml` |
| --- | --- | --- |
| tests pass | **0** | written; root `result=Passed total=1 passed=1 failed=0 skipped=0` |
| test fails | **2** | written; root `result=Failed(Child) total=1 passed=0 failed=1 skipped=0` |
| compile error | **1** | **not written at all**; log carries `error CS…` and `Aborting batchmode due to failure: Scripts have compiler errors.` |

Consequences:
- Never collapse 1 and 2 into "non-zero". They mean different things.
- On a compile error there is **no results file**, so `compile=fail` together with `tests=pass` is
  not merely inconsistent — it is physically impossible for a headless route.
- The receipt's `tests {passed, failed, skipped}` map 1:1 onto the `results.xml` root attributes;
  `total` is available as a cross-check.

## `-quit` and `-runTests` are mutually destructive

With `-quit`, Unity **exits 0 and never writes `results.xml`** — the log says
`quit successfully invoked`. Without it, the results file appears normally.

**So exit 0 alone is not evidence that tests ran.** Only a parsed `results.xml` with `passed >= 1`
distinguishes "tests passed" from "Unity exited before running them". Found while running, then
independently reproduced by a second reviewer. The route runners omit `-quit` for this reason.

## The compile-abort banner goes to stdout, not the log file

Unity writes `Aborting batchmode due to failure:` / `Scripts have compiler errors.` as **two lines
to stdout**, not into `-logFile`. A detector that scans only the log file silently never fires.
Scan log + stdout + stderr.

## Unity orphans child processes — four known classes, all reparenting to PID 1

Discovered one at a time, each time after the previous list was believed complete:

| Class | argv0 | Notes |
| --- | --- | --- |
| `VBCSCompiler` | `dotnet` | `dotnet exec …/DotNetSdkRoslyn/VBCSCompiler.dll`; shared and pipe-named, so it may belong to another run or to the user's own Editor |
| `UnityPackageManager` | — | the Editor's own package-manager server |
| `AssetImportWorker` | **bare `Unity`** | distinguishing part is `-name AssetImportWorkerN`; **`pgrep -af "Editor/Unity"` provably does not match it**, and it **ignores SIGTERM** — SIGKILL was required |
| `UnityShaderCompiler` | — | found last, during the evidence run |

- **The set is cache-state dependent.** A cold `Library` leaks; a warm re-run of the same project
  leaked nothing. **One clean run is not evidence of no leak** — test cleanup cold.
- A plain batchmode invocation therefore violates "leave no child process" unless the runner does
  something deliberate about it.
- **A naive "kill Unity's children after it exits" finds nothing** — by then they have been
  reparented to PID 1 and are outside Unity's tree. Contain the tree *before or during* the run
  (process group / session), or record child pids while the parent still owns them.
- **Do not kill by process name.** A pattern that matched the first two classes misses the third,
  and a host-wide name match will destroy an unrelated Editor's helpers. Identity must be
  established — the kernel's pgid — not guessed.

## `Temp/UnityLockfile`

- Appears **within ~2 seconds of launch**, in **batchmode too** — not only under a GUI Editor. So
  its presence does not distinguish "a GUI Editor owns this project" from "another headless run is
  in progress". Refusing on any live owner is still correct, but a diagnostic claiming "a GUI
  Editor owns this" would be factually wrong.
- **Removed on clean exit.** A stale lockfile therefore means a crash or a kill, not normal
  operation.

## `-projectPath` and `ProjectVersion.txt`

- `-projectPath` is a **separate argv entry** carrying the absolute path. On Linux
  `/proc/<pid>/cmdline` gives exact NUL-separated argv, so there is no need to re-split a
  space-joined `ps` line. macOS's equivalent is `sysctl KERN_PROCARGS2` (**implemented but never
  executed on Apple hardware** — see the host-pass handoff).
- `ProjectSettings/ProjectVersion.txt` is **two lines**, and both match a version regex:
  `m_EditorVersion: 6000.3.18f1` and `m_EditorVersionWithRevision: 6000.3.18f1 (5ebeb53e4c07)`.
  A one-line fixture once hid a real bug in this repo. Record both — the revision hash is what
  keeps a relaxed version pin reproducible.

## Licensing works headless

`-batchmode -nographics` resolves the license offline: `Successfully connected to LicensingClient`
then `Successfully resolved entitlement details`. One benign line — `Error: Access token is
unavailable; failed to update` — appears while the cached entitlement still resolves. Do not treat
it as a licensing failure.

Unity also tries to launch a `build-server` and may report `No .NET SDKs were found` depending on
PATH. Benign for test runs (exit 0).

---

## MCP bridge (CoplayDev unity-mcp, pinned `v9.7.1` @ `78ee5418…`)

- **EditorPrefs written in a batchmode `-executeMethod` pass do not reach a subsequently launched
  Editor.** Measured: an exit-0 configure pass left **zero** `MCPForUnity` keys in
  `~/.local/share/unity3d/prefs`. The key names were verified correct against
  `EditorPrefKeys.cs`, so this is not a typo. *Inferred* (single external source, a macOS report):
  this is Unity's own batchmode behaviour, not package-specific.
- `UNITY_MCP_ALLOW_BATCH` is a **gate on two `[InitializeOnLoad]` static constructors, not a config
  channel** — it configures nothing by itself. For the HTTP path it is insufficient:
  `HttpAutoStartHandler` still requires EditorPrefs `AutoStartOnLoad` and `UseHttpTransport`, and
  **no environment variable overrides any transport preference** at this pin. There is no config
  file, ScriptableObject or CLI flag for transport settings.
- **Upstream's own CI does not attempt a two-pass configure.** It runs **one persistent batchmode
  Editor with no `-quit`**, whose `-executeMethod MCPForUnity.Editor.McpCiBoot.StartStdioForCi`
  configures and starts the bridge in the same process, after a separate `-quit` warm-up import.
  Discovery is a status JSON (`$UNITY_MCP_STATUS_DIR/unity-mcp-status-<projectHash>.json`, field
  `unity_port`) followed by a TCP connect — **stdio/TCP, not HTTP**. `StartStdioForCi` appears in
  **zero** docs, README or issues; it exists in the source and in upstream's own workflow only.
- **Operational warning — upstream issue #1196.** At this pin `McpEditorShutdownCleanup` has **no
  batch guard**, so **any batchmode Unity exit kills a live interactive MCP server on the same
  host.** Fixed only after `v9.7.1`. Keep the developer's own MCP server closed while fixtures run.
- `McpCiBoot.cs` is byte-identical at `v10.1.0` and the batch guards are unchanged, so nothing here
  justifies moving the pin.
