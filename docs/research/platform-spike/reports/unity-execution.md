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
