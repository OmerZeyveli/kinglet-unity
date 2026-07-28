# Kinglet 00U — Unity Execution Routes

One row per frozen matrix cell. A cell is closed only by a published
`pass` record; `missing` means no host has run it, and `inconclusive`
means a host looked and could not establish the claim.

| Cell | State | Runs |
| --- | --- | --- |
| `unity.editor-resolution.linux-ubuntu-24-04-x64.mismatched-editor` | pass | `20260728T132858Z-unity-probe-mismatched-editor-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.editor-resolution.macos-26-arm64.mismatched-editor` | missing | — |
| `unity.editor-resolution.windows-11-x64.mismatched-editor` | missing | — |
| `unity.execution.linux-ubuntu-24-04-x64.cancellation` | pass | `20260728T132858Z-unity-probe-cancellation-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.execution.linux-ubuntu-24-04-x64.orphan-cleanup` | pass | `20260728T132858Z-unity-probe-orphan-cleanup-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.execution.macos-26-arm64.cancellation` | missing | — |
| `unity.execution.macos-26-arm64.orphan-cleanup` | missing | — |
| `unity.execution.windows-11-x64.cancellation` | missing | — |
| `unity.execution.windows-11-x64.orphan-cleanup` | missing | — |
| `unity.filesystem-only.linux-ubuntu-24-04-x64.route` | pass | `20260728T132858Z-unity-probe-filesystem-only-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.filesystem-only.macos-26-arm64.route` | missing | — |
| `unity.filesystem-only.windows-11-x64.route` | missing | — |
| `unity.isolated-headless.linux-ubuntu-24-04-x64.route` | pass | `20260728T132858Z-unity-probe-isolated-headless-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.isolated-headless.macos-26-arm64.route` | missing | — |
| `unity.isolated-headless.windows-11-x64.route` | missing | — |
| `unity.live-editor-mcp.linux-ubuntu-24-04-x64.bridge-not-ready` | pass | `20260728T132858Z-unity-probe-bridge-not-ready-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.live-editor-mcp.linux-ubuntu-24-04-x64.route` | inconclusive | `20260728T132858Z-unity-probe-live-editor-mcp-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.live-editor-mcp.macos-26-arm64.bridge-not-ready` | missing | — |
| `unity.live-editor-mcp.macos-26-arm64.route` | missing | — |
| `unity.live-editor-mcp.windows-11-x64.bridge-not-ready` | missing | — |
| `unity.live-editor-mcp.windows-11-x64.route` | missing | — |
| `unity.same-project-headless.linux-ubuntu-24-04-x64.collision-refusal` | pass | `20260728T132858Z-unity-probe-collision-refusal-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.same-project-headless.linux-ubuntu-24-04-x64.route` | pass | `20260728T132858Z-unity-probe-same-project-headless-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.same-project-headless.macos-26-arm64.collision-refusal` | missing | — |
| `unity.same-project-headless.macos-26-arm64.route` | missing | — |
| `unity.same-project-headless.windows-11-x64.collision-refusal` | missing | — |
| `unity.same-project-headless.windows-11-x64.route` | missing | — |

## Why the open cells are open

- **`live-editor-mcp@linux-ubuntu-24.04.4-lts`** — observed: BLOCKED by a confirmed plan-level defect, not by this run: the EditorPrefs a batchmode configure pass writes never become visible to a subsequently launched Editor on this host, so no Editor has ever registered with the pinned bridge and no `instances` poll has ever returned one. The key names were verified against MCPForUnity's own EditorPrefKeys.cs, and HttpAutoStartHandler.cs also returns early in batchmode unless UNITY_MCP_ALLOW_BATCH is set. Without a registered Editor there is no readiness to observe and no test to run through the bridge, and a receipt claiming otherwise would be fabricated. Escalated; not worked around.

## Known artefacts of the committed records

These are defects in the tooling that ASSEMBLED the records, found
after they were published. Every measured fact in them was verified
against its artifact and stands. The assembling code is fixed; the
records are immutable and were deliberately not regenerated, so the
next run — a Linux re-run or the first macOS run — carries the
corrections and these notes disappear from this report.

1. **Zero-length spans.** 8 records report
   `started_at == ended_at` although their artifacts record real
   durations (`wall_seconds` of 14.216, 18.197 and 22.151 among
   them). The probe's span is now carried through to the record.
2. **One dangling artifact reference.** Inside
   `collision-refusal-receipt.json`, the `artifacts` field names
   `artifacts/unity/same-project-headless-summary.json` — the route's
   own route-relative name. That cell publishes the file as
   `collision-refusal-summary.json`, so the reference resolves to
   nothing in its directory. The receipt's references are now
   rewritten to the paths actually published.
3. **`orphan-cleanup` wording.** Its assertion detail says "peak
   population during the cold run"; that run was CANCELLED at 14s,
   and it is the same run and the same artifact as the `cancellation`
   cell. A killed run is the stronger case for cleanup, and the
   artifact discloses the kill, but the wording did not.
4. **No post-run census on `isolated-headless`.** That artifact
   publishes `orphan_peak_during_run` and no `orphan_census_after`,
   so the suite's strongest `AssetImportWorker` cleanup datapoint is
   unpublished. The census is now collected and staged.

Affected records:

- `20260728T132858Z-unity-probe-bridge-not-ready-linux-ubuntu-24-04-4-lts-x64-01`
- `20260728T132858Z-unity-probe-cancellation-linux-ubuntu-24-04-4-lts-x64-01`
- `20260728T132858Z-unity-probe-collision-refusal-linux-ubuntu-24-04-4-lts-x64-01`
- `20260728T132858Z-unity-probe-filesystem-only-linux-ubuntu-24-04-4-lts-x64-01`
- `20260728T132858Z-unity-probe-isolated-headless-linux-ubuntu-24-04-4-lts-x64-01`
- `20260728T132858Z-unity-probe-mismatched-editor-linux-ubuntu-24-04-4-lts-x64-01`
- `20260728T132858Z-unity-probe-orphan-cleanup-linux-ubuntu-24-04-4-lts-x64-01`
- `20260728T132858Z-unity-probe-same-project-headless-linux-ubuntu-24-04-4-lts-x64-01`
