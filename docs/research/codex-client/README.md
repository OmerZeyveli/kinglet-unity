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

**Every probe's `NAME.stderr.txt` begins with `Reading additional input from
stdin...`, and it is not a warning.** The harness runs codex with stdin at
`/dev/null`, which is what stops `codex exec` blocking; measured on the first
live run, 2026-08-15, the message is printed whenever stdin is not a terminal —
codex then reads EOF and proceeds normally, exit 0. Read past it when looking
for real warnings. It is not filtered, because a harness that edits its own
evidence is worth less than one that explains it.

The first live run also confirmed the event-stream shape the plan recorded:
four line-delimited objects — `thread.started`, `turn.started`, an
`item.completed` whose `item.type` is `agent_message`, and `turn.completed`
carrying the token usage.

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
  class, the architecture decision, everything excluded, the machinery the
  decision strands, and the six silent-failure layers in one table.

## Two reading conventions, so a sweep over these files is not misread

**Angle brackets here are metavariables, not unfilled placeholders.** `<repo>`,
`<key>`, `<name>`, `<abs>`, `<dir>`, `<replica>` and their kin stand in for a path
or a hash the reader supplies; several are quoted verbatim out of Codex's own
response strings, where the brackets are Codex's. A sweep for `<…>` therefore
returns dozens of hits on a complete document. It was run to completion on
2026-08-16 and every hit triaged: the one genuine unfilled slot, a `'<prompt>'` in
`## Hooks`'s reproduction recipe, is filled.

**A number here is a dated measurement unless it is derived in place.** These are
records of what was true against `codex-cli 0.145.0` on 2026-08-15/16, and a guard
that silently updated them would destroy the record rather than protect it — which
is why nothing in `tests/` reads these two files. Where a figure comes from
Kinglet's own tree rather than from a probe, the surrounding text gives the command
to re-derive it and tells you to. Two such figures had already moved by the time the
wave closed, both inside it: the command bodies' line count, and the bash-4 census
in `docs/ANTI-VACUITY.md` — that one is guarded, in `tests/test-derived-counts.sh`.
