---
name: kinglet-capability-probe
description: "Kinglet capability workflow — inspects the Unity version and project marker in a disposable probe project and writes a structured workflow receipt. Invoke via natural language to use the installed Kinglet capability workflow."
globs: [".kinglet-probe/**/*", "ProjectSettings/ProjectVersion.txt"]
alwaysApply: false
---

# Kinglet Capability Probe Workflow

You are the **Kinglet capability workflow**. When invoked — for example via the prompt "use the installed Kinglet capability workflow" — execute the steps below exactly and return only `KINGLET_CLIENT_PROBE_OK 6000.3.11f1` when successful.

## Purpose

This skill exercises three verifiable capabilities in a single workflow:

1. Reading two fixed project files to confirm the project identity.
2. Invoking the native `kinglet-client-probe` executable via its `exec` subcommand.
3. Validating the structured receipt and writing it to the declared output path.

## Preconditions

The following files must be readable inside the current project root:

- `ProjectSettings/ProjectVersion.txt` — must contain `m_EditorVersion: 6000.3.11f1`
- `.kinglet-probe/project-marker.txt` — must contain exactly `KINGLET_CLIENT_PROBE_PROJECT`

## Steps

### Step 1 — Locate the native executable

The executable is installed at `.kinglet-probe/bin/kinglet-client-probe` (relative to the project root). Resolve it to an absolute path before use. If the file does not exist or is not executable, report an error and stop.

### Step 2 — Invoke `exec`

Call the executable with the following argument array (no shell interpolation):

```
kinglet-client-probe exec --project <absolute-project-root> --output <absolute-project-root>/.kinglet-probe/receipts/workflow.json
```

The executable reads `ProjectSettings/ProjectVersion.txt` and `.kinglet-probe/project-marker.txt`, validates them, and atomically writes the receipt to `--output`.

### Step 3 — Validate the receipt

Read `.kinglet-probe/receipts/workflow.json`. Assert all three fields:

| Field | Expected value |
|-------|---------------|
| `schema` | `kinglet.client-probe.receipt/v1` |
| `marker` | `KINGLET_CLIENT_PROBE_PROJECT` |
| `unity_version` | `6000.3.11f1` |

If any field differs, report a validation error with the actual and expected values. Do not silently accept a partial match.

### Step 4 — Return

Return exactly the string:

```
KINGLET_CLIENT_PROBE_OK 6000.3.11f1
```

No additional prose. No file modifications except `.kinglet-probe/receipts/workflow.json`.

## Constraints

- Write **only** `.kinglet-probe/receipts/workflow.json`. Do not create, edit, or delete any other file.
- Do not write `agent.json` — that path belongs to the `kinglet-capability-reviewer` agent.
- Pass arguments as an array when the client surface permits. Do not rely on shell word-splitting.
- Do not search for this skill by filename — it must be reachable via the natural-language trigger above.
