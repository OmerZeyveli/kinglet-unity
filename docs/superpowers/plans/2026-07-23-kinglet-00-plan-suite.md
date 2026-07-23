# Kinglet Subproject 0 Plan Suite

**Status:** Ready for execution; not started

**Date:** 2026-07-23

**Approved design:** `../specs/2026-07-23-kinglet-platform-spikes-design.md`

## Execution order

Subproject 0 is split into five independently reviewable plans. Do not execute a dependent plan
before its named gate is green.

| Plan | Purpose | Dependency | Gate produced | State |
| --- | --- | --- | --- | --- |
| `2026-07-23-kinglet-00a-evidence-harness.md` | Validate, sanitize, store, and report immutable spike evidence | none | 0A | Not started |
| `2026-07-23-kinglet-00r-runtime-bakeoff.md` | Compare bundled Python, Rust, Go, and self-contained .NET | 0A | 0R | Locked by 0A |
| `2026-07-23-kinglet-00c-client-capability-probes.md` | Test six client surfaces independently | 0A | one 0C gate per client | Locked by 0A |
| `2026-07-23-kinglet-00u-unity-execution-probes.md` | Test four Unity execution routes on native hosts | 0A | 0U | Locked by 0A |
| `2026-07-23-kinglet-00d-decision-package.md` | Generate ADR inputs, baselines, inventory, and gate state | accepted 0R and 0U evidence; 0C may remain visibly open | 0D | Locked by 0R and 0U |

After 0A, plans 00R, 00C, and 00U may run concurrently because they write separate raw run
directories and committed evidence namespaces. Plan 00D consumes their committed outputs and does
not manufacture a pass for an unavailable host or client.

## Frozen history

The six plans dated 2026-07-22 describe the earlier Claude/Codex-only architecture. They remain in
Git as historical context, but are superseded and must not be executed. The 2026-07-23 platform
design and this suite are authoritative.

## Shared execution rules

- Use an isolated worktree created at execution time.
- Implement each plan test-first and commit at its task checkpoints.
- Never commit `.kinglet/local/`, `.research/`, raw prompts, credentials, account identifiers, or
  absolute user paths.
- Do not rewrite the existing `tools/kinglet_build/` implementation during Subproject 0.
- A native run means a native process on the target operating system; cross-compilation is not a
  runtime pass, and Windows runs may not use WSL or Git Bash.
- A failed or inconclusive candidate, host, route, or client result remains visible evidence.
- Runtime selection and any change to the fixed scoring rubric require explicit user approval.

## Completion boundary

This suite ends with evidence and approved architecture decisions. It does not build the production
Kinglet runtime, migrate the content inventory, or publish an end-user plugin.
