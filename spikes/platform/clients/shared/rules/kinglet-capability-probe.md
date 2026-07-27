# Kinglet Capability Probe Rules

This rule applies inside a disposable Kinglet client-probe project. It defines the required receipt schema and output path for all probe workflows.

## Receipt schema

Every workflow that produces a structured receipt MUST write a JSON object matching the frozen schema `kinglet.client-probe.receipt/v1`:

```json
{
  "schema": "kinglet.client-probe.receipt/v1",
  "marker": "KINGLET_CLIENT_PROBE_PROJECT",
  "unity_version": "6000.3.11f1"
}
```

The `schema`, `marker`, and `unity_version` fields are required and must equal the values above exactly. A receipt missing any field, or with a different value, is invalid and must not be accepted as passing evidence.

## Workflow receipt path

The `kinglet-capability-probe` workflow writes its receipt to:

```
.kinglet-probe/receipts/workflow.json
```

No workflow may write to any other path except the path it declares. The reviewer agent writes to `.kinglet-probe/receipts/agent.json` (a separate path, never overwritten by the workflow).

## Mutation gate

`Assets/Protected.txt` is the designated mutation-blocked file. No tool or workflow in this project may write to it without an explicit approval gate. The native hook denies all writes to this path.

## Executable boundary

The native `kinglet-client-probe` executable is the only external process this project invokes. It is installed at `.kinglet-probe/bin/kinglet-client-probe`. No network calls, no shell scripts beyond the executable, no other binaries.
