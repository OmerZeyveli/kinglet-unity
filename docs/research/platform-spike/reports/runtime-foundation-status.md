# 0R Runtime Bake-off — Foundation Status

**Date:** 2026-07-27
**Plan:** `docs/superpowers/plans/2026-07-23-kinglet-00r-runtime-bakeoff.md`
**Scope of this record:** what was built and verified locally, and exactly what remains gated on
hardware and user approval. This document does **not** select a runtime — that is Task 8 and
requires explicit user approval per the plan's Global Constraints.

## TL;DR

The entire **authorable, test-verifiable foundation of 0R is complete and green**: the frozen
Host Probe contract, the black-box validator + runner + CLI, the frozen selection rubric, and **all
four runtime candidates** — each built at its **exact pinned toolchain** and each independently
passing the black-box conformance validator **18/18 assertions** on this Linux host.

What is **not** done is the part that needs machines and a human this session did not have: the
20-cell **native host matrix** (Windows 10/11 + macOS ×2 + a *locked* Ubuntu 24.04.4) and the
**runtime-selection ADR** (needs user approval). No runtime has been chosen, and no host pass has
been fabricated.

## Done and verified (committed)

| Piece | Where | Verification |
| --- | --- | --- |
| Frozen Host Probe contract + fixtures | `spikes/platform/runtime/contract/` | 18 assertion ids, RFC 8032 vector, fixed timings; canonical-valid/invalid trees |
| Black-box validator + runner + CLI | `tools/kinglet_spike/runtime_contract.py` | `validate_host_result` enforces exactly-18 ids; `--executable/--contract-dir` CLI; fake-script spawn tests |
| Frozen selection rubric | `spikes/platform/runtime/rubric-v1.json`, `toolchains.lock.json` | 9 hard gates, weights 25/20/20/15/10/10=100, bands 0-5, tie≤3; scorer disqualifies on open/failed gate |
| **Python** candidate | `spikes/platform/runtime/python/` | 18/18 (unpackaged, CPython 3.13.12 + cryptography 46.0.5); PyInstaller packaging deferred |
| **Go** candidate | `spikes/platform/runtime/go/` | 18/18 at **exact go1.26.5**, `go test -race` clean, stdlib-only |
| **Rust** candidate | `spikes/platform/runtime/rust/` | 18/18 at **exact rustc 1.97.1**, `cargo test --locked` 4/4, all crate pins resolved |
| **.NET** candidate | `spikes/platform/runtime/dotnet/` | 18/18 at **exact SDK 10.0.302**, xUnit 11/11, NSec.Cryptography 26.4.0 |

Every candidate went through per-task review confirming **all 18 assertions are genuinely exercised
(no hardcoded passes)**, plus a final whole-branch review confirming the contract is candidate-neutral,
the four are semantically fair, no secrets/absolute-user-paths are committed (spike hard-gate #7), no
build output is tracked, and provenance is complete (342 rows, `check-provenance.sh` green).

### Local toolchains installed this session (for reproducibility)
- Go 1.26.5 → `$HOME/sdk/go1.26.5` (archive `go1.26.5.linux-amd64.tar.gz`, sha256
  `5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053`, verified on download).
- Rust 1.97.1 via rustup → `$HOME/.cargo` / `$HOME/.rustup` (released 2026-07-14).
- .NET SDK 10.0.302 → `$HOME/.dotnet` (alongside the pre-existing 8.0.419).

## Blocked — needs hardware and/or user approval

### Task 7 — the 20-cell native host matrix
The plan requires native runs on **five locked hosts**: Windows 10 22H2 x64, Windows 11 25H2 x64,
macOS Tahoe 26 Apple Silicon, macOS Tahoe 26 Intel, and **Ubuntu 24.04.4 LTS x64**. This session had
only a single **Pop!_OS 24.04** Linux box. Two hard blocks:
1. **No Windows or macOS hosts** — 4 of 5 hosts absent; cross-compilation is explicitly *not* a
   runtime pass.
2. **The one Linux host is not the locked host** — Pop!_OS ≠ Ubuntu 24.04.4, and the plan's host
   runner is required to *refuse a mismatch with the locked environment*. So even the local Linux
   cell cannot produce a **gate-closing** pass; at best it is *indicative* evidence.

Also still to author (they are Task 7 deliverables, not yet written): `run-host.sh` / `run-host.ps1`
/ `measure.sh` / `measure.ps1` — the native build/measure/publish runners that collect 30 cold-start
samples, peak RSS, artifact bytes, and publish via the 00A harness. These were intentionally not
written here because they cannot be honestly exercised without the locked hosts.

### Task 8 — the runtime-selection ADR
Blocked on the plan's Global Constraint: *"Runtime selection requires explicit user approval and an
ADR; this plan must not silently choose a winner."* No scoring, no winner, no ADR was produced.
`score_candidate` also defers one enforcement (evidence-record-id + rationale for qualitative scores)
because the frozen `Mapping[str,int]` interface must not change without user sign-off (see the
Task-6 ledger note).

## Observations for the eventual bake-off scoring (not defects)

Logged now so they are not lost when the matrix is actually run and scored:
- **cleanup.timeout / cleanup.cancel idiom split.** Python throws in all cleanup modes; Go/Rust/.NET
  model timeout/cancel via non-throw idioms (returned error / early-return + drop-guard / created-not-
  thrown exception) — only `cleanup.crash` throws in those three. All four still acquire a real lease
  and prove release + no descendants. Normalize (or score under "testability") when scoring.
- **manifest.* inspection depth.** Python reuses `load_graph` over the whole canonical tree; Go/Rust/
  .NET strict-decode only `role.json`. On this fixture all four reject the identical injected
  `"unknown": true` for the same reason, so the assertion is fair — but the depth difference is worth
  a note under qualitative "manifest robustness".
- **.NET packages.lock.json** carries `Microsoft.NET.ILLink.Tasks` (publish-time injection); publish
  needs `-p:RestoreLockedMode=false`. The test-path lock is clean and independent.

## Runbook — completing 0R on properly-provisioned hosts

Prereq per host: install the exact pinned toolchain(s), then from the repo root:

```
# Go
export PATH="$HOME/sdk/go1.26.5/bin:$PATH"; export GOTOOLCHAIN=local
(cd spikes/platform/runtime/go && go test -race ./... && go build -trimpath -ldflags="-s -w" -o dist/kinglet-host-probe .)
python3 -m tools.kinglet_spike.runtime_contract --executable spikes/platform/runtime/go/dist/kinglet-host-probe --contract-dir spikes/platform/runtime/contract

# Rust
export PATH="$HOME/.cargo/bin:$PATH"
(cd spikes/platform/runtime/rust && cargo test --locked && cargo build --locked --release)
python3 -m tools.kinglet_spike.runtime_contract --executable spikes/platform/runtime/rust/target/release/kinglet-host-probe --contract-dir spikes/platform/runtime/contract

# .NET
export DOTNET_ROOT="$HOME/.dotnet"; export PATH="$HOME/.dotnet:$PATH"
(cd spikes/platform/runtime/dotnet && dotnet test Kinglet.HostProbe.Tests/Kinglet.HostProbe.Tests.csproj && \
 dotnet publish Kinglet.HostProbe.csproj -c Release -r <native-rid> --self-contained true -p:PublishSingleFile=true -p:RestoreLockedMode=false)
python3 -m tools.kinglet_spike.runtime_contract --executable <published-exe> --contract-dir spikes/platform/runtime/contract

# Python — first package on a host with uv + Python 3.14.6 (Task 2 Step 5), then run the artifact.
```

Each must print `18/18 assertions passed` and exit 0. Then author the Task 7 host runners to wrap
this with 30-sample cold-start timing, peak RSS, artifact bytes, and 00A publication, run all five
locked hosts, regenerate coverage, and only then take scoring + the ADR to the user for approval.

## Provenance of this record
Every claim above maps to a committed commit on `main` between `9eb8ba2` (freeze contract) and the
head that adds this file. Toolchain checksums are recorded inline; candidate lockfiles are committed
(`Cargo.lock`, `packages.lock.json`) except where honestly deferred (`uv.lock`).
