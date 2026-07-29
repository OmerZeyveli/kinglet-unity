# Kinglet 00U — Unity Execution Routes

One row per frozen matrix cell. A cell is closed only by a published
`pass` record; `missing` means no host has run it, and `inconclusive`
means a host looked and could not establish the claim.

A state followed by `(deferred)` or `(dropped)` is a cell a committed
matrix amendment excused from its gate — deferred means it is expected
back, dropped means no hardware exists for it. Neither is covered, and
neither holds 0U open. See `amendments` in the matrix for the reason.

| Cell | State | Runs |
| --- | --- | --- |
| `unity.editor-resolution.linux-ubuntu-24-04-x64.mismatched-editor` | pass | `20260728T132858Z-unity-probe-mismatched-editor-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.editor-resolution.macos-26-arm64.mismatched-editor` | missing | — |
| `unity.editor-resolution.windows-11-x64.mismatched-editor` | missing (deferred) | — |
| `unity.execution.linux-ubuntu-24-04-x64.cancellation` | pass | `20260728T132858Z-unity-probe-cancellation-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.execution.linux-ubuntu-24-04-x64.orphan-cleanup` | pass | `20260728T132858Z-unity-probe-orphan-cleanup-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.execution.macos-26-arm64.cancellation` | missing | — |
| `unity.execution.macos-26-arm64.orphan-cleanup` | missing | — |
| `unity.execution.windows-11-x64.cancellation` | missing (deferred) | — |
| `unity.execution.windows-11-x64.orphan-cleanup` | missing (deferred) | — |
| `unity.filesystem-only.linux-ubuntu-24-04-x64.route` | pass | `20260728T132858Z-unity-probe-filesystem-only-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.filesystem-only.macos-26-arm64.route` | missing | — |
| `unity.filesystem-only.windows-11-x64.route` | missing (deferred) | — |
| `unity.isolated-headless.linux-ubuntu-24-04-x64.route` | pass | `20260728T132858Z-unity-probe-isolated-headless-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.isolated-headless.macos-26-arm64.route` | missing | — |
| `unity.isolated-headless.windows-11-x64.route` | missing (deferred) | — |
| `unity.live-editor-mcp.linux-ubuntu-24-04-x64.bridge-not-ready` | pass | `20260728T132858Z-unity-probe-bridge-not-ready-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.live-editor-mcp.linux-ubuntu-24-04-x64.route` | inconclusive | `20260728T132858Z-unity-probe-live-editor-mcp-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.live-editor-mcp.macos-26-arm64.bridge-not-ready` | missing | — |
| `unity.live-editor-mcp.macos-26-arm64.route` | missing | — |
| `unity.live-editor-mcp.windows-11-x64.bridge-not-ready` | missing (deferred) | — |
| `unity.live-editor-mcp.windows-11-x64.route` | missing (deferred) | — |
| `unity.same-project-headless.linux-ubuntu-24-04-x64.collision-refusal` | pass | `20260728T132858Z-unity-probe-collision-refusal-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.same-project-headless.linux-ubuntu-24-04-x64.route` | pass | `20260728T132858Z-unity-probe-same-project-headless-linux-ubuntu-24-04-4-lts-x64-01` |
| `unity.same-project-headless.macos-26-arm64.collision-refusal` | missing | — |
| `unity.same-project-headless.macos-26-arm64.route` | missing | — |
| `unity.same-project-headless.windows-11-x64.collision-refusal` | missing (deferred) | — |
| `unity.same-project-headless.windows-11-x64.route` | missing (deferred) | — |

### Cells that share one artifact

Each row above is a cell, not an independent observation. These cells
are closed by the SAME byte-identical artifact:

- `cancellation` and `orphan-cleanup`

Count the evidence by artifact, not by cell, when reading the table.

## Why the open cells are open

- **`live-editor-mcp@linux-ubuntu-24.04.4-lts`** — observed: BLOCKED by a confirmed plan-level defect, not by this run: the EditorPrefs a batchmode configure pass writes never become visible to a subsequently launched Editor on this host, so no Editor has ever registered with the pinned bridge and no `instances` poll has ever returned one. The key names were verified against MCPForUnity's own EditorPrefKeys.cs, and HttpAutoStartHandler.cs also returns early in batchmode unless UNITY_MCP_ALLOW_BATCH is set. Without a registered Editor there is no readiness to observe and no test to run through the bridge, and a receipt claiming otherwise would be fabricated. Escalated; not worked around.

## Known artefacts of the committed records

These are defects in the tooling that ASSEMBLED the records, found
after they were published. The assembling code is fixed; the
records are immutable and were deliberately not regenerated, so the
next run — a Linux re-run or the first macOS run — carries the
corrections and these notes disappear from this report.

Every measured fact in a record that HAS an artifact was verified
against that artifact and stands. That is not every record: the
following carry no artifact at all, so there was nothing to verify
them against, and nothing in them should be read as measured.

- `20260728T132858Z-unity-probe-live-editor-mcp-linux-ubuntu-24-04-4-lts-x64-01`

1. **Zero-length spans.** 9 records report
   `started_at == ended_at`. Some — not all — of their artifacts
   record a real duration, under two different field names
   (`wall_seconds` on the cancelled run, `duration_seconds` on the
   headless summaries), and two cells share one artifact and so one
   value. The probe's span is now carried through to the record, which
   is the only place a per-record duration belongs.
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
- `20260728T132858Z-unity-probe-live-editor-mcp-linux-ubuntu-24-04-4-lts-x64-01`
- `20260728T132858Z-unity-probe-mismatched-editor-linux-ubuntu-24-04-4-lts-x64-01`
- `20260728T132858Z-unity-probe-orphan-cleanup-linux-ubuntu-24-04-4-lts-x64-01`
- `20260728T132858Z-unity-probe-same-project-headless-linux-ubuntu-24-04-4-lts-x64-01`
