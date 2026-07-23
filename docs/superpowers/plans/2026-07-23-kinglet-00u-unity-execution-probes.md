# Kinglet 00U Unity Execution Probes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove safe, evidence-equivalent execution for filesystem-only, live Editor + MCP, same-project headless, and isolated headless Unity workflows.

**Architecture:** A maintainer-only Python controller resolves an exact pinned Unity Editor, refuses unsafe project ownership before process launch, controls native process trees and per-physical-workspace leases, and normalizes every route into one receipt. A disposable Unity 6.3 LTS project and pinned CoplayDev Unity MCP release run the same compile/test marker across Windows, macOS, and Linux.

**Tech Stack:** 00A evidence harness; Python standard library controller; Unity 6000.3.11f1; Unity Test Framework 1.1.31 through the MCP package; CoplayDev Unity MCP v9.7.1 at commit `78ee5418415953b79c358bfe6355fcc3fde7912b`; uv 0.11.28; PowerShell 7; native POSIX shell.

## Global Constraints

- 00A must be closed before accepting a Unity result.
- Use Unity Editor `6000.3.11f1` exactly; refuse substitution and silent project upgrade.
- Use CoplayDev Unity MCP `v9.7.1` at exact commit
  `78ee5418415953b79c358bfe6355fcc3fde7912b`.
- Native execution hosts are Windows 11 25H2 x64, macOS Tahoe 26.5.2 Apple Silicon, and Ubuntu
  24.04.4 LTS x64.
- Do not use WSL, Git Bash, containers, emulation, or cross-host results for native cells.
- Never launch batchmode against a physical project path owned by a GUI Unity Editor.
- Same-project headless requires the GUI Editor for that physical path to be closed.
- Isolated headless may run while the main Editor is open only from a separate physical copy with
  separate `Library`, `Temp`, logs, lease, and outputs.
- A running MCP server is not an Editor-ready state.
- MCP readiness requires the expected project instance, Unity version, compilation idle state, and
  `ready_for_tools=true`.
- One mutating execution lease exists per physical workspace; a lease never spans main and isolated
  copies as if they were the same physical workspace.
- Cancellation, timeout, crash, and success must leave no Unity, MCP helper, or child process and no
  live lease owned by that route.
- MCP and headless routes publish the same normalized compile/test/evidence fields.
- Raw Unity logs, machine paths, license data, and full MCP transcripts remain under
  `.kinglet/local/spikes/<run-id>/`.

---

## Route and receipt contract

Routes are:

```text
filesystem
live-editor-mcp
same-project-headless
isolated-headless
```

Every route emits:

```json
{
  "schema": "kinglet.unity-probe.receipt/v1",
  "route": "filesystem",
  "project_id": "kinglet-unity-probe",
  "unity_version": "6000.3.11f1",
  "compile": {"status": "not-run", "errors": 0},
  "tests": {"status": "not-run", "passed": 0, "failed": 0, "skipped": 0},
  "ready": false,
  "collision_refused": false,
  "active_lease": false,
  "descendant_pids": [],
  "artifacts": []
}
```

`filesystem` legitimately reports compile/tests as `not-run`. The other three require
`compile.status=pass`, `tests.status=pass`, `passed=1`, `failed=0`, and `skipped=0`.

## File map

| Path | Responsibility |
| --- | --- |
| `spikes/platform/unity/contracts/routes-v1.json` | Fixed cases, readiness rules, timeouts, and receipt schema |
| `spikes/platform/unity/fixture/` | Minimal pinned Unity project and EditMode probe |
| `spikes/platform/unity/mcp.lock.json` | Exact MCP tag/commit/package/server/tool references |
| `tools/kinglet_spike/unity/model.py` | Route, editor, owner, process, and normalized receipt types |
| `tools/kinglet_spike/unity/editor.py` | Exact Editor resolution and version verification |
| `tools/kinglet_spike/unity/ownership.py` | GUI ownership detection and pre-launch refusal |
| `tools/kinglet_spike/unity/process.py` | Native process group/job lifecycle and orphan checks |
| `tools/kinglet_spike/unity/lease.py` | One writer lease per physical workspace |
| `tools/kinglet_spike/unity/mcp.py` | Server-vs-Editor readiness and pinned MCP CLI calls |
| `tools/kinglet_spike/unity/routes.py` | Four route implementations and normalized receipts |
| `tools/kinglet_spike/unity/cli.py` | Native `prepare`, `run`, `cancel`, and `inspect` commands |
| `spikes/platform/unity/run-host.ps1` | Windows-native route runner |
| `spikes/platform/unity/run-host.sh` | macOS/Linux-native route runner |
| `docs/research/platform-spike/reports/unity-execution.md` | Generated route/host baseline |

### Task 1: Freeze route contracts and strict normalized receipts

**Files:**
- Create: `spikes/platform/unity/contracts/routes-v1.json`
- Create: `tools/kinglet_spike/unity/__init__.py`
- Create: `tools/kinglet_spike/unity/model.py`
- Create: `tools/kinglet_spike/unity/receipt.py`
- Create: `tests/kinglet_spike/unity_support.py`
- Test: `tests/kinglet_spike/test_unity_receipt.py`

**Interfaces:**
- Produces `load_unity_receipt(path: Path) -> UnityReceipt`,
  `unity_receipt_from_dict(value: object) -> UnityReceipt`,
  `validate_unity_receipt(receipt: UnityReceipt) -> tuple[Diagnostic, ...]`, and
  `receipt_to_evidence(receipt, environment) -> EvidenceRecord`.

- [ ] **Step 1: Write failing route-specific receipt tests**

```python
# tests/kinglet_spike/unity_support.py
from tools.kinglet_spike.unity.receipt import unity_receipt_from_dict


def receipt(route: str) -> dict:
    return {
        "schema": "kinglet.unity-probe.receipt/v1",
        "route": route,
        "project_id": "kinglet-unity-probe",
        "unity_version": "6000.3.11f1",
        "compile": {"status": "not-run", "errors": 0},
        "tests": {"status": "not-run", "passed": 0, "failed": 0, "skipped": 0},
        "ready": False,
        "collision_refused": False,
        "active_lease": False,
        "descendant_pids": [],
        "artifacts": [],
    }


def passing_receipt(route: str) -> dict:
    value = receipt(route)
    value["compile"] = {"status": "pass", "errors": 0}
    value["tests"] = {"status": "pass", "passed": 1, "failed": 0, "skipped": 0}
    value["ready"] = route == "live-editor-mcp"
    return value


def load(value: object):
    return unity_receipt_from_dict(value)
```

```python
# tests/kinglet_spike/test_unity_receipt.py
import unittest

from tools.kinglet_spike.unity.receipt import validate_unity_receipt
from tests.kinglet_spike.unity_support import load, passing_receipt, receipt


class UnityReceiptTests(unittest.TestCase):
    def test_filesystem_must_not_claim_compile_or_editor_ready(self):
        value = receipt("filesystem")
        value["compile"] = {"status": "pass", "errors": 0}
        value["ready"] = True
        self.assertEqual(
            {"E_ASSERTION"},
            {item.code for item in validate_unity_receipt(load(value))},
        )

    def test_executing_routes_require_one_passing_test(self):
        for route in ("live-editor-mcp", "same-project-headless", "isolated-headless"):
            value = receipt(route)
            value["compile"] = {"status": "pass", "errors": 0}
            value["tests"] = {"status": "pass", "passed": 0, "failed": 0, "skipped": 0}
            with self.subTest(route=route):
                self.assertTrue(validate_unity_receipt(load(value)))

    def test_pass_never_has_lease_or_descendants(self):
        value = passing_receipt("same-project-headless")
        value["active_lease"] = True
        value["descendant_pids"] = [1234]
        self.assertEqual(2, len(validate_unity_receipt(load(value))))
```

- [ ] **Step 2: Run tests and verify missing package failure**

Run: `python3 -m unittest tests.kinglet_spike.test_unity_receipt -v`

Expected: import error for `tools.kinglet_spike.unity`.

- [ ] **Step 3: Implement frozen types and exact route assertions**

Reject unknown fields. `ready` may be true only for `live-editor-mcp`. Collision refusal is a pass
only for the separate `same-project-headless.collision-refusal` probe; it is not a successful
headless run. Tests/compile fields use only `not-run`, `pass`, or `fail`. All committed artifact
paths are relative to `docs/research/platform-spike/`.

`routes-v1.json` fixes editor startup at 300 seconds, import/compile readiness at 300 seconds, MCP
server startup at 60 seconds, MCP Editor readiness at 300 seconds, EditMode tests at 180 seconds,
and cancellation cleanup at 15 seconds.

- [ ] **Step 4: Run tests and commit**

Run: `python3 -m unittest tests.kinglet_spike.test_unity_receipt -v`

Expected: all tests pass.

```bash
git add spikes/platform/unity/contracts tools/kinglet_spike/unity tests/kinglet_spike/test_unity_receipt.py
git commit -m "test: freeze Unity execution receipt"
```

### Task 2: Create the pinned disposable Unity project

**Files:**
- Create: `spikes/platform/unity/fixture/ProjectSettings/ProjectVersion.txt`
- Create: `spikes/platform/unity/fixture/Packages/manifest.json`
- Create: `spikes/platform/unity/fixture/Assets/KingletSpike/Editor/KingletSpike.Editor.asmdef`
- Create: `spikes/platform/unity/fixture/Assets/KingletSpike/Editor/KingletSpikeProbe.cs`
- Create: `spikes/platform/unity/fixture/Assets/KingletSpike/Tests/Editor/KingletSpike.Tests.asmdef`
- Create: `spikes/platform/unity/fixture/Assets/KingletSpike/Tests/Editor/KingletSpikeTests.cs`
- Create: `spikes/platform/unity/mcp.lock.json`
- Test: `tests/kinglet_spike/test_unity_fixture.py`

**Interfaces:**
- Produces project ID `kinglet-unity-probe`, Unity `6000.3.11f1`, one deterministic EditMode test,
  and an Editor method `KingletSpike.Probe.WriteReceipt`.

- [ ] **Step 1: Write failing fixture-lock tests**

Tests assert exact `m_EditorVersion`, exact MCP Git tag and commit, package name/version, assembly
references, one `[Test]`, no network/file access outside the project, and receipt schema/version.

- [ ] **Step 2: Run tests and verify missing fixture failure**

Run: `python3 -m unittest tests.kinglet_spike.test_unity_fixture -v`

Expected: missing file failures.

- [ ] **Step 3: Add exact Unity and package locks**

`ProjectVersion.txt`:

```text
m_EditorVersion: 6000.3.11f1
m_EditorVersionWithRevision: 6000.3.11f1 (3000ef702840)
```

The revision `3000ef702840` is the immutable revision embedded in Unity's official
6000.3.11f1 download URLs. The fixture test compares both version fields to these committed values.
The package manifest contains:

```json
{
  "dependencies": {
    "com.coplaydev.unity-mcp": "https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#v9.7.1"
  }
}
```

`mcp.lock.json` records package name `com.coplaydev.unity-mcp`, version `9.7.1`, tag, commit, MIT
license, package URL, server project version `9.7.1`, and the CLI/resources used:
`instances`, `get_editor_state`, `read_console`, and `run_tests`.

- [ ] **Step 4: Add the complete probe and test**

For `Assets/KingletSpike/Editor/KingletSpike.Editor.asmdef`:

```json
{
  "name": "KingletSpike.Editor",
  "rootNamespace": "KingletSpike",
  "includePlatforms": ["Editor"]
}
```

For `Assets/KingletSpike/Tests/Editor/KingletSpike.Tests.asmdef`:

```json
{
  "name": "KingletSpike.Tests",
  "rootNamespace": "KingletSpike.Tests",
  "references": ["KingletSpike.Editor"],
  "includePlatforms": ["Editor"],
  "optionalUnityReferences": ["TestAssemblies"]
}
```

```csharp
// Assets/KingletSpike/Editor/KingletSpikeProbe.cs
using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace KingletSpike
{
    public static class Probe
    {
        public const string ProjectId = "kinglet-unity-probe";

        [System.Serializable]
        private sealed class PrefBackup
        {
            public bool autoStartPresent;
            public bool autoStart;
            public bool useHttpPresent;
            public bool useHttp;
            public bool scopePresent;
            public string scope;
            public bool urlPresent;
            public string url;
        }

        public static void ConfigureMcpProbe()
        {
            var url = System.Environment.GetEnvironmentVariable("KINGLET_MCP_URL");
            var backupPath = System.Environment.GetEnvironmentVariable("KINGLET_MCP_PREFS_BACKUP");
            if (string.IsNullOrWhiteSpace(url))
                throw new System.InvalidOperationException("KINGLET_MCP_URL is required.");
            if (string.IsNullOrWhiteSpace(backupPath))
                throw new System.InvalidOperationException("KINGLET_MCP_PREFS_BACKUP is required.");
            var backup = new PrefBackup {
                autoStartPresent = EditorPrefs.HasKey("MCPForUnity.AutoStartOnLoad"),
                autoStart = EditorPrefs.GetBool("MCPForUnity.AutoStartOnLoad", false),
                useHttpPresent = EditorPrefs.HasKey("MCPForUnity.UseHttpTransport"),
                useHttp = EditorPrefs.GetBool("MCPForUnity.UseHttpTransport", false),
                scopePresent = EditorPrefs.HasKey("MCPForUnity.HttpTransportScope"),
                scope = EditorPrefs.GetString("MCPForUnity.HttpTransportScope", ""),
                urlPresent = EditorPrefs.HasKey("MCPForUnity.HttpUrl"),
                url = EditorPrefs.GetString("MCPForUnity.HttpUrl", "")
            };
            File.WriteAllText(backupPath, JsonUtility.ToJson(backup) + "\n");
            EditorPrefs.SetBool("MCPForUnity.AutoStartOnLoad", true);
            EditorPrefs.SetBool("MCPForUnity.UseHttpTransport", true);
            EditorPrefs.SetString("MCPForUnity.HttpTransportScope", "local");
            EditorPrefs.SetString("MCPForUnity.HttpUrl", url);
        }

        public static void RestoreMcpProbe()
        {
            var backupPath = System.Environment.GetEnvironmentVariable("KINGLET_MCP_PREFS_BACKUP");
            var backup = JsonUtility.FromJson<PrefBackup>(File.ReadAllText(backupPath));
            RestoreBool("MCPForUnity.AutoStartOnLoad", backup.autoStartPresent, backup.autoStart);
            RestoreBool("MCPForUnity.UseHttpTransport", backup.useHttpPresent, backup.useHttp);
            RestoreString("MCPForUnity.HttpTransportScope", backup.scopePresent, backup.scope);
            RestoreString("MCPForUnity.HttpUrl", backup.urlPresent, backup.url);
        }

        private static void RestoreBool(string key, bool present, bool value)
        {
            if (present) EditorPrefs.SetBool(key, value); else EditorPrefs.DeleteKey(key);
        }

        private static void RestoreString(string key, bool present, string value)
        {
            if (present) EditorPrefs.SetString(key, value); else EditorPrefs.DeleteKey(key);
        }

        [MenuItem("Kinglet Spike/Exit Without Saving")]
        public static void ExitWithoutSaving()
        {
            EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            EditorApplication.Exit(0);
        }

        [MenuItem("Kinglet Spike/Write Receipt")]
        public static void WriteReceipt()
        {
            var directory = Path.Combine("Library", "KingletSpike");
            Directory.CreateDirectory(directory);
            var json = "{\"schema\":\"kinglet.unity-fixture/v1\","
                + "\"project_id\":\"kinglet-unity-probe\","
                + "\"unity_version\":\"" + Application.unityVersion + "\"}\n";
            File.WriteAllText(Path.Combine(directory, "fixture-receipt.json"), json);
        }
    }
}
```

```csharp
// Assets/KingletSpike/Tests/Editor/KingletSpikeTests.cs
using NUnit.Framework;

namespace KingletSpike.Tests
{
    public sealed class KingletSpikeTests
    {
        [Test]
        public void ProjectMarkerMatchesPinnedFixture()
        {
            Assert.That(Probe.ProjectId, Is.EqualTo("kinglet-unity-probe"));
        }
    }
}
```

- [ ] **Step 5: Validate JSON/C# structure and commit**

Run:

```bash
python3 -m json.tool spikes/platform/unity/fixture/Packages/manifest.json >/dev/null
python3 -m json.tool spikes/platform/unity/mcp.lock.json >/dev/null
python3 -m unittest tests.kinglet_spike.test_unity_fixture -v
```

Expected: tests pass.

```bash
git add spikes/platform/unity/fixture spikes/platform/unity/mcp.lock.json tests/kinglet_spike/test_unity_fixture.py
git commit -m "spike: add pinned Unity fixture"
```

### Task 3: Resolve the exact Editor and reject GUI ownership before launch

**Files:**
- Create: `tools/kinglet_spike/unity/editor.py`
- Create: `tools/kinglet_spike/unity/ownership.py`
- Test: `tests/kinglet_spike/test_unity_editor.py`
- Test: `tests/kinglet_spike/test_unity_ownership.py`

**Interfaces:**
- Produces:
  - `read_project_version(project: Path) -> str`
  - `verify_editor(editor: Path, required_version: str) -> EditorIdentity`
  - `detect_gui_owner(project: Path) -> ProjectOwner | None`
  - `assert_headless_safe(project: Path) -> None`

- [ ] **Step 1: Write failing mismatch and pre-launch refusal tests**

Use mocked native process listings and real temp lock files. Assert mismatched `6000.3.12f1`
raises `E_UNITY_VERSION`; a GUI process whose canonical `-projectPath` equals the requested path
raises `E_UNITY_OWNED`; a similarly prefixed sibling path does not; symlink aliases canonicalize to
the same owned project.

- [ ] **Step 2: Run tests and verify missing functions**

Run:
`python3 -m unittest tests.kinglet_spike.test_unity_editor tests.kinglet_spike.test_unity_ownership -v`

Expected: import/function failures.

- [ ] **Step 3: Implement exact resolution**

The controller accepts an explicit Editor executable, executes `<editor> -version`, and requires
exact stdout version equality before any project launch. It never selects a “closest” installed
version or changes `ProjectVersion.txt`. Native helper scripts may enumerate Unity Hub install
roots only to propose an exact matching path; the Python boundary still verifies it.

- [ ] **Step 4: Implement ownership detection**

Inspect Unity processes with argument arrays via `Win32_Process.CommandLine` on Windows,
`ps -axo pid=,command=` on macOS/Linux, then parse `-projectPath` without substring matching.
Corroborate with `Temp/UnityLockfile` and `Library/EditorInstance.json`. A matching live process is
authoritative; a stale lock produces `E_UNITY_OWNER_UNKNOWN`, which also refuses headless until
inspected. `assert_headless_safe` runs before `Popen`.

- [ ] **Step 5: Run tests and commit**

Run the two test modules; expected all pass.

```bash
git add tools/kinglet_spike/unity/editor.py tools/kinglet_spike/unity/ownership.py \
  tests/kinglet_spike/test_unity_editor.py tests/kinglet_spike/test_unity_ownership.py
git commit -m "feat: guard Unity project ownership"
```

### Task 4: Control native process trees and per-workspace leases

**Files:**
- Create: `tools/kinglet_spike/unity/process.py`
- Create: `tools/kinglet_spike/unity/lease.py`
- Create: `tests/kinglet_spike/fixtures/process_tree.py`
- Test: `tests/kinglet_spike/test_unity_process.py`
- Test: `tests/kinglet_spike/test_unity_lease.py`

**Interfaces:**
- Produces `ManagedProcess.start(argv, cwd, env)`, `cancel(deadline_seconds)`,
  `descendants() -> tuple[int, ...]`, and `WorkspaceLease.acquire/renew/release`.

- [ ] **Step 1: Write failing crash, timeout, cancellation, and competitor tests**

Use `tests/kinglet_spike/fixtures/process_tree.py`, whose `parent` mode launches its own `child`
mode, records both PIDs as JSON, and waits for 30 seconds. Each test asserts zero descendants and no
lease after the outcome. A lease for the main project does not block a different isolated physical
path, but two owners for the same canonical path conflict.

- [ ] **Step 2: Run tests and verify failure**

Run:
`python3 -m unittest tests.kinglet_spike.test_unity_process tests.kinglet_spike.test_unity_lease -v`

Expected: missing implementation failures.

- [ ] **Step 3: Implement native process group/job cleanup**

On Windows create a Job Object with kill-on-close and assign every launched process. On POSIX start
a new session and terminate/kill the process group. Always wait/reap. Capture stdout/stderr to raw
files, never pipes that can deadlock on Unity logs.

- [ ] **Step 4: Implement canonical-path lease identity**

Hash the normalized physical path with SHA-256; store leases below the raw run directory, not the
Unity project. Lease JSON contains owner UUID, physical path hash, route, pid, acquired/renewed/expiry
UTC. Acquire by exclusive create, renew only the owner, reject malformed/live competitor, replace
only proven-expired leases, and release in `finally`.

- [ ] **Step 5: Run tests and commit**

Run both modules; expected all pass.

```bash
git add tools/kinglet_spike/unity/process.py tools/kinglet_spike/unity/lease.py \
  tests/kinglet_spike/test_unity_process.py tests/kinglet_spike/test_unity_lease.py
git commit -m "feat: control Unity execution lifecycle"
```

### Task 5: Implement filesystem-only and same-project headless routes

**Files:**
- Create: `tools/kinglet_spike/unity/routes.py`
- Create: `tools/kinglet_spike/unity/cli.py`
- Create: `tools/kinglet_spike/unity/__main__.py`
- Test: `tests/kinglet_spike/test_unity_routes.py`

**Interfaces:**
- Produces:
  - `run_filesystem(project, raw_dir) -> UnityReceipt`
  - `run_same_project_headless(editor, project, raw_dir) -> UnityReceipt`

- [ ] **Step 1: Write failing filesystem and collision tests**

Assert filesystem reads the version/project marker without launching a process and reports
compile/tests `not-run`. For headless, mock an owner and assert the process launcher was never
called, `collision_refused=true`, and the refusal receipt contains no Unity PID.

- [ ] **Step 2: Run tests and verify failure**

Run: `python3 -m unittest tests.kinglet_spike.test_unity_routes -v`

Expected: missing route functions.

- [ ] **Step 3: Implement filesystem-only**

Validate the fixed project files, calculate their checksums, write the normalized receipt, and make
no Unity/MCP/process call. This proves content inspection and safe file operations only; it must not
claim compile/test success.

- [ ] **Step 4: Implement headless after preflight**

Call `verify_editor`, then `assert_headless_safe`, then acquire the physical-workspace lease. Launch:

```text
<Unity> -batchmode -nographics -quit
  -projectPath <project>
  -runTests -testPlatform EditMode
  -testResults <raw>/same-project-headless-results.xml
  -logFile <raw>/same-project-headless.log
```

Argument arrays are mandatory. Parse NUnit XML, scan Unity log for compile errors, require exactly
one passing test, normalize receipt, and release/clean in `finally`. A refusal is a separate probe
pass; it does not masquerade as a successful headless compile.

- [ ] **Step 5: Run tests and commit**

Run the route tests; expected all pass.

```bash
git add tools/kinglet_spike/unity/routes.py tools/kinglet_spike/unity/cli.py \
  tools/kinglet_spike/unity/__main__.py tests/kinglet_spike/test_unity_routes.py
git commit -m "feat: probe filesystem and headless Unity routes"
```

### Task 6: Implement server-vs-Editor readiness and live Editor + MCP

**Files:**
- Create: `tools/kinglet_spike/unity/mcp.py`
- Modify: `tools/kinglet_spike/unity/routes.py`
- Test: `tests/kinglet_spike/test_unity_mcp.py`

**Interfaces:**
- Produces:
  - `start_mcp(raw_dir) -> ManagedProcess`
  - `wait_for_editor(instance, version, timeout) -> McpEditorState`
  - `run_live_editor_mcp(editor, project, raw_dir) -> UnityReceipt`

- [ ] **Step 1: Write failing readiness-state tests**

Mock these states in order: HTTP port closed; server reachable with zero instances; wrong project
instance; expected instance compiling; expected instance `ready_for_tools=false`; expected instance
idle/ready. Assert only the final state returns ready. Assert server-only timeout is categorized
`mcp.editor-not-ready`, not `mcp.server-start-failed`.

- [ ] **Step 2: Run tests and verify missing module**

Run: `python3 -m unittest tests.kinglet_spike.test_unity_mcp -v`

Expected: missing `unity.mcp`.

- [ ] **Step 3: Start the exact pinned MCP server**

Use uv 0.11.28 and:

```text
uvx --from git+https://github.com/CoplayDev/unity-mcp.git@78ee5418415953b79c358bfe6355fcc3fde7912b#subdirectory=Server
  mcp-for-unity --transport http --http-host 127.0.0.1 --http-port <reserved-local-port>
```

Set `DISABLE_TELEMETRY=1`. Capture the resolved uv environment/package lock and server process tree
in raw evidence. Do not bind non-loopback.

- [ ] **Step 4: Implement Editor launch and readiness**

With no GUI owner, run the exact Editor once with `-batchmode -nographics -quit`, the project path,
`-executeMethod KingletSpike.Probe.ConfigureMcpProbe`, `KINGLET_MCP_URL` set to the reserved
loopback URL, `KINGLET_MCP_PREFS_BACKUP` set to a new raw JSON path, and a raw setup log; verify
exit `0` and the backup file. Acquire the main physical-workspace lease, start the MCP server, then
launch the exact Unity Editor with `-projectPath`, `-logFile`, and no batchmode. Poll
`unity-mcp --host 127.0.0.1 --port <port> --format json instances`, select only the instance whose
canonical project and version match, then poll raw `get_editor_state` until compilation is false
and `ready_for_tools` true. A server with no matching ready instance never passes. In `finally`,
after the GUI exits, run the same exact Editor in batchmode with
`-executeMethod KingletSpike.Probe.RestoreMcpProbe` and the backup path to restore all four keys,
including their previous absence.

- [ ] **Step 5: Run compile/test through MCP and normalize evidence**

Call `read_console` to clear, refresh scripts, wait ready, call
`unity-mcp ... editor tests --mode EditMode --wait 180 --details`, then read the console. Require
the same one passing test and zero compile errors as headless. Close the disposable Editor, stop
MCP helpers, release the lease, and report no descendants.

- [ ] **Step 6: Run tests and commit**

Run the MCP and route tests; expected all pass.

```bash
git add tools/kinglet_spike/unity/mcp.py tools/kinglet_spike/unity/routes.py \
  tests/kinglet_spike/test_unity_mcp.py
git commit -m "feat: probe live Unity MCP readiness"
```

### Task 7: Implement isolated headless while the main Editor stays open

**Files:**
- Create: `tools/kinglet_spike/unity/isolation.py`
- Modify: `tools/kinglet_spike/unity/routes.py`
- Test: `tests/kinglet_spike/test_unity_isolation.py`

**Interfaces:**
- Produces `prepare_isolated_copy(source, destination) -> IsolationManifest` and
  `run_isolated_headless(editor, main_project, isolated_project, raw_dir) -> UnityReceipt`.

- [ ] **Step 1: Write failing copy-boundary and unsaved-state tests**

Create a source fixture with `Library`, `Temp`, `Logs`, `.kinglet/local`, a saved marker, and a
synthetic unsaved-state sentinel under `Library`. Assert the isolated copy includes committed
Assets/Packages/ProjectSettings only, has none of those generated trees, has a distinct canonical
path, and never imports the unsaved sentinel.

- [ ] **Step 2: Run tests and verify failure**

Run: `python3 -m unittest tests.kinglet_spike.test_unity_isolation -v`

Expected: missing isolation module.

- [ ] **Step 3: Implement a manifest-driven isolated copy**

Copy only `Assets`, `Packages`, and `ProjectSettings`; reject symlinks escaping the source; record
each copied relative path and SHA-256. Create isolated `Library`, `Temp`, log, results, and lease
paths only by the isolated Unity process/controller. Never copy a dirty scene or generated import
state from the open Editor.

- [ ] **Step 4: Run isolated batchmode with the main owner present**

Require a confirmed live main GUI owner for the concurrency proof, verify the exact editor, verify
the isolated path is not owned, acquire only the isolated physical-workspace lease, and run the
same batchmode command/test parser against the isolated path. Before launch, use MCP
`manage_gameobject` to create `KINGLET_UNSAVED_SENTINEL` in the main Editor without saving the
scene; confirm it exists through the main instance hierarchy and is absent from every saved scene
asset. While isolated headless runs, confirm the main Editor PID and unsaved GameObject remain
alive. Afterward query the main hierarchy again, prove the sentinel still exists, prove no isolated
saved asset contains it, and prove distinct Library/Temp/log paths with no isolated writes beneath
main. Execute the fixture menu item `Kinglet Spike/Exit Without Saving`, wait for the GUI PID to
exit, and verify no scene asset gained the sentinel.

- [ ] **Step 5: Run tests and commit**

Run isolation plus route tests; expected all pass.

```bash
git add tools/kinglet_spike/unity/isolation.py tools/kinglet_spike/unity/routes.py \
  tests/kinglet_spike/test_unity_isolation.py
git commit -m "feat: probe isolated Unity headless execution"
```

### Task 8: Execute all routes natively and publish 00U evidence

**Files:**
- Create: `spikes/platform/unity/run-host.ps1`
- Create: `spikes/platform/unity/run-host.sh`
- Create: `tests/kinglet_spike/test_unity_host_scripts.py`
- Publish: `docs/research/platform-spike/evidence/unity/`
- Publish: `docs/research/platform-spike/artifacts/unity/`
- Create: `docs/research/platform-spike/reports/unity-execution.json`
- Create: `docs/research/platform-spike/reports/unity-execution.md`
- Modify: `docs/superpowers/plans/2026-07-23-kinglet-00-plan-suite.md`

**Interfaces:**
- Consumes: exact native Editor path and host; four routes plus refusal/failure cases.
- Produces: 00U route/host cells and generated baseline.

- [ ] **Step 1: Test native script safety**

Tests require an explicit `--unity`/`-Unity` path, exact version preflight, new raw run ID, native OS
release check, no WSL/Git Bash, argument arrays, cleanup traps/finally, and all cases:
filesystem, MCP server without Editor, MCP ready Editor, same-path collision refusal, same-project
headless with GUI closed, isolated headless with GUI open, mismatched Editor, dirty/unsaved state,
timeout, cancellation, crash recovery, lease cleanup, and orphan cleanup.

- [ ] **Step 2: Run tests and verify missing scripts**

Run: `python3 -m unittest tests.kinglet_spike.test_unity_host_scripts -v`

Expected: missing script failures.

- [ ] **Step 3: Implement native host entry points**

PowerShell uses native process/CIM APIs and never invokes Bash. Shell script accepts Darwin/Linux
only. Both verify the locked OS and editor, copy the fixture into a new raw workspace, run cases in
the same fixed order, sanitize XML/log summaries, produce 00A records, and publish immutable
evidence. A timeout or failure is published before cleanup exits.

- [ ] **Step 4: Execute on Windows, macOS, and Ubuntu**

Run each native script on its locked host. Expected for each:

- filesystem succeeds without Unity;
- MCP server-only is correctly not ready;
- live Editor + MCP compiles and passes one test;
- same-path GUI collision is refused before a second Unity launch;
- same-project headless succeeds after GUI closes;
- isolated headless succeeds while main GUI and unsaved state remain;
- mismatched Editor is refused without project modification;
- timeout/cancel/crash leave no process or lease.

- [ ] **Step 5: Generate reports and evaluate the gate**

Run:

```bash
python3 -m tools.kinglet_spike unity-report --repo-root .
python3 -m tools.kinglet_spike gate 0U --repo-root .
```

Expected: gate exits `0` only when every required route/case has valid evidence on all three hosts.
Reports generated twice have identical SHA-256.

- [ ] **Step 6: Run repository and privacy verification**

Run:

```bash
python3 -m unittest discover -s tests/kinglet_spike -t . -v
bash tests/run-tests.sh
git diff --check
git grep -nE '(/Users/|/home/|[A-Z]:\\\\Users\\\\|SERIAL|LICENSE|TOKEN|PASSWORD)' docs/research/platform-spike
```

Expected: tests pass, aggregate `Failed: 0`, diff check silent, sensitive grep empty.

- [ ] **Step 7: Commit the accepted Unity baseline**

```bash
git add spikes/platform/unity/run-host.ps1 spikes/platform/unity/run-host.sh \
  tests/kinglet_spike/test_unity_host_scripts.py \
  docs/research/platform-spike/evidence/unity \
  docs/research/platform-spike/artifacts/unity \
  docs/research/platform-spike/reports/unity-execution.json \
  docs/research/platform-spike/reports/unity-execution.md \
  docs/superpowers/plans/2026-07-23-kinglet-00-plan-suite.md
git commit -m "test: prove native Unity execution routes"
```

## Plan acceptance

Do not close 0U unless all four routes and all refusal/failure cases have native Windows, macOS, and
Ubuntu evidence; server-only is never labeled Editor-ready; same-path batchmode is refused before
launch; isolated execution proves physical separation and unsaved-state safety; normalized MCP and
headless receipts have equivalent compile/test facts; and all process/lease/privacy checks pass.
