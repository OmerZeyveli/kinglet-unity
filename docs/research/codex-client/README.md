# Codex client evidence

Raw evidence for the 2026-08-15 wave that measured whether Kinglet's surfaces
cross to Codex CLI. The spec is
`docs/superpowers/specs/2026-08-15-codex-cli-second-client-design.md`.

## Pinned versions

| Thing | Version | Why pinned |
|---|---|---|
| `codex-cli` | 0.145.0 | 0.147.0 was available during the wave and was deliberately not taken. A hook-schema change between versions invalidates this evidence; the pin makes that detectable rather than silent. |
| Unity MCP bridge | CoplayDev unity-mcp, `http://127.0.0.1:8080/mcp` | Task 7 only. |

## Re-running a probe

```bash
bash scripts/codex-probe.sh --name <name> --prompt <prompt-file>
```

Each probe writes four files here: `NAME.jsonl` (the event stream),
`NAME.last.txt` (the final agent message), `NAME.stderr.txt`, and
`NAME.meta.json` (the exact invocation, the codex version, the exit code).

**The transcripts are not committed.** They are large, they are not
deterministic between runs, and committing them would make every re-measurement
a diff. What is committed is the verdict, in `findings.md` and
`codex-facts.md`, each carrying the command that produced it — so a reader
re-runs rather than trusts.

## What is measured where

- `codex-facts.md` — Codex's own capabilities. Every claim carries the command
  that established it. This file is what turns the spec's "inferred, NOT
  verified" list into measured or refuted.
- `findings.md` — Kinglet's surfaces under Codex: one verdict per surface
  class, the architecture decision, and everything excluded.
