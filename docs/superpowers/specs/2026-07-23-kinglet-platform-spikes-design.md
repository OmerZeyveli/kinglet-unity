# Kinglet Platform Spikes and Capability Proof Design

**Status:** Approved design; written-spec review requested

**Date:** 2026-07-23

**Parent design:** `2026-07-23-kinglet-platform-design.md`

## Decision

Kinglet will not select its core implementation technology or finalize client and Unity adapter
contracts from documentation, preference, or small “hello world” demonstrations. Subproject 0 will
produce a candidate-neutral evidence harness, compare four runtime approaches through the same
representative Host Probe, and execute real capability probes against every first-class client
surface and all four Unity execution routes.

The runtime candidates are:

1. the existing Python foundation packaged with a bundled interpreter;
2. Rust;
3. Go;
4. self-contained .NET.

The spike does not implement the Kinglet product. It creates just enough disposable prototype code
to answer decisions that would otherwise make later file maps, package layouts, process contracts,
and implementation plans speculative.

## Existing baseline

The repository already contains a Python standard-library canonical loader, validator, writer, CLI,
Claude and Codex adapter profiles, a frozen migration inventory, and a substantial test suite. At
the start of this design, the baseline completed:

- 122 Python unit tests;
- 98 aggregate shell assertions;
- zero reported failures or skips.

This implementation is an evaluated migration asset, not a decision that the future product must
remain Python. Spike work must not rewrite or delete it. The bundled-Python candidate starts from
the existing behavior; other candidates measure the cost and risk of reproducing the same
representative vertical slice.

The existing tests remain behavioral inventory even if another runtime wins. A later canonical
foundation spec will decide which modules are kept, adapted, ported, or retired.

## Goals

1. Select a core runtime using native Windows, macOS, and Linux evidence.
2. Validate the cross-platform filesystem, process, security, and packaging behaviors on which the
   Kinglet platform depends.
3. Establish observed Native, Emulated, and Unavailable capability facts for each target client.
4. Prove the boundaries of filesystem-only, live Editor + MCP, same-project headless, and isolated
   headless Unity execution.
5. Produce sanitized, reviewable evidence and ADRs that later specs can cite as hard dependencies.
6. Allow independent downstream work to begin as soon as its specific evidence gate passes.

## Non-goals

- The spike will not ship an end-user Kinglet runtime or plugin.
- It will not migrate the canonical content inventory.
- It will not implement production setup, upgrade, rollback, or uninstall.
- It will not attempt client feature parity.
- It will not rewrite the existing Python foundation during experiments.
- It will not choose a candidate that failed a hard gate merely because it has the highest score.
- It will not treat official documentation, cross-compilation, file registration, or a generated
  artifact as proof of live behavior.
- It will not commit raw logs containing absolute user paths, account details, prompts, credentials,
  or other machine-sensitive information.

## Architecture

Subproject 0 has five independently gated work packages.

### 0A — Evidence Harness

A maintainer-only Python standard-library harness defines the evidence schema, invokes black-box
probes, verifies their outputs, detects missing coverage, and renders deterministic reports. It is
not a product-runtime candidate and may not share candidate-specific process or filesystem code.

The harness accepts only versioned records and rejects unknown fields. It validates:

- subject, probe, environment, and contract identities;
- exact toolchain and dependency versions;
- operating system, release, and architecture;
- start/end timestamps and exit state;
- `pass`, `fail`, `unavailable`, or `inconclusive` status;
- relative artifact paths and their SHA-256 checksums;
- declared native build and execution commands;
- required repetition counts and measurement units;
- official-source references for documented client capabilities;
- redaction and sensitive-path rules.

A `pass` record requires the artifacts and assertions named by that probe. Skipped, absent,
unavailable, inconclusive, manually asserted, or checksum-invalid results never satisfy coverage.
The harness reports these states distinctly instead of collapsing them into success or failure.

### 0R — Runtime Bake-off

Each runtime implements the same narrow Host Probe as a native command-line application. The Host
Probe:

- loads and validates the same representative canonical manifest;
- operates in a workspace whose path contains whitespace and non-ASCII characters;
- performs staged and atomic file replacement;
- acquires, renews, rejects, expires, and releases a cross-process lease;
- creates a child/grandchild process tree and cancels it without leaving descendants;
- calculates SHA-256 and validates a fixed signature test vector;
- emits the same versioned structured result and stable error categories;
- builds a distributable artifact that does not require the user to install its runtime or
  toolchain;
- records repeated cold-start duration, peak resident memory, artifact size, and dependency
  footprint using the same units and repetition policy.

This is not a full port. The manifest and process scenarios are intentionally small and fixed before
candidate implementation begins. Candidate-specific dependencies are allowed when necessary, but
their versions, licenses, transitive dependency counts, artifact impact, and supply-chain source
must be recorded.

The bundled-Python candidate must use the existing implementation where it already satisfies the
contract. Its packaging mechanism is part of the candidate and is measured on each operating
system. Rust, Go, and .NET candidates may not receive simplified cases or weaker assertions.

### 0C — Client Capability Proof

Six native surfaces are tested separately:

- Claude Code;
- Codex;
- Cursor;
- GitHub Copilot CLI;
- GitHub Copilot in VS Code;
- Antigravity.

A minimal disposable probe plugin or package exercises:

- installation, discovery, update, and removal;
- natural-language skill or workflow discovery;
- rules, commands, and project-instruction binding;
- custom agents or delegation;
- pre/post hooks and mutation blocking;
- local executable invocation;
- MCP registration and tool discovery;
- global versus project scope;
- approval and permission behavior;
- structured result presentation.

Shared package formats do not share pass status. Every surface runs in a clean client session
against a disposable Unity-shaped project. Evidence records the exact client version, host,
sanitized prompt digest, expected behavior, observed behavior, capability grade, and transcript or
screenshot checksum.

Official documentation establishes an advertised surface and guides the probe; it does not prove
runtime behavior. If an account, subscription, platform, or current client cannot be accessed, the
result is `inconclusive`. No later adapter plan may promote that result to Native or Emulated.

All client surfaces run on Windows at minimum. Where the client officially supports macOS or Linux,
local executable, path, hook, approval, and MCP behavior is repeated on those hosts. A documented
absence on an operating system is recorded as Unavailable with its official source, not treated as
a test failure.

### 0U — Unity Execution Proof

A pinned, disposable Unity 6 project exercises the four execution routes:

1. filesystem-only with no Unity process;
2. live Editor with a connected CoplayDev Unity MCP bridge;
3. same-project headless compile/test while the GUI Editor is closed;
4. isolated headless in a separate copy while the main project remains open.

The Unity probes also prove:

- exact Editor resolution from `ProjectVersion.txt`;
- refusal to substitute a mismatched Editor or silently upgrade the project;
- Editor launch, import, compilation, MCP readiness, and timeout states;
- distinction between a running MCP server and a connected ready Editor;
- rejection of same-path batchmode before process launch when the GUI Editor owns the project;
- isolation of `Library`, `Temp`, process locks, file writes, and unsaved Editor state;
- cancellation without orphaned Unity, helper, or bridge processes;
- release or expiry of execution leases after success, failure, and cancellation;
- one normalized evidence contract for MCP and headless outcomes.

The routes run natively on Windows, macOS, and Linux. The collision probe detects and refuses the
unsafe launch; it does not intentionally corrupt a project by starting GUI and batchmode on the
same path.

### 0D — Decision Package

The decision package contains:

- a runtime comparison report and approved runtime ADR;
- a per-client capability baseline;
- a Unity execution baseline;
- a keep/adapt/replace inventory for the existing Python foundation;
- source and license records for spike dependencies;
- the exact gate state consumed by each downstream spec.

It distinguishes measured facts, documented facts, reviewer judgments, and unresolved limitations.
Generated summaries link back to evidence record and artifact checksums.

## Host and architecture matrix

Runtime candidates execute natively on:

- Windows 10 x64;
- Windows 11 x64;
- a currently supported macOS release on Apple Silicon;
- macOS on Intel;
- Ubuntu LTS x64.

Cross-compilation can satisfy a build observation but never a runtime observation. A produced
artifact must execute on its target host for that cell to pass. Windows cells may not use WSL or
Git Bash.

The implementation plan pins exact toolchain versions and the exact macOS, Ubuntu, and Unity 6
versions used for reproducible execution. Evidence always records the actual versions. Changing a
pinned environment creates a new run rather than rewriting an older record.

## Evidence storage and data flow

Candidate, client, and Unity probes emit raw output into:

```text
.kinglet/local/spikes/<run-id>/
```

This directory is ignored and may contain machine-local paths and full diagnostics. The harness
validates and redacts a publishable subset into:

```text
docs/research/platform-spike/evidence/
docs/research/platform-spike/artifacts/
docs/research/platform-spike/reports/
```

Only relative repository paths appear in committed records. Credentials, user/account names,
absolute home paths, project source outside the disposable fixtures, and raw prompts are forbidden.
Prompt evidence uses a stable digest plus a committed synthetic prompt ID. Small required artifacts
are committed; large logs remain local and are represented by checksum and a reproducible command.

The flow is:

```text
fixed probe contract
  → native or client-specific probe
  → raw local result
  → schema/checksum/redaction validation
  → sanitized committed evidence
  → coverage and comparison report
  → reviewed gate or ADR
```

Reports are regenerated from committed evidence and must be byte-identical. Hand-edited prose may
interpret a result but cannot change its status or measurements.

## Runtime hard gates

A runtime candidate enters weighted scoring only when every hard gate passes:

1. No separately installed end-user runtime or toolchain is required.
2. Every Host Probe filesystem, lease, process, Unicode-path, signature, and result-contract case
   passes on every required native host.
3. Unity-like and MCP-like long-running process trees can be started, timed out, cancelled, and
   cleaned reliably.
4. Success, crash, timeout, and cancellation leave no live child process or active lease.
5. Each target produces a reproducible, checksummed artifact that can participate in native
   platform signing.
6. Candidate and dependency licenses are compatible with Kinglet distribution and completely
   recorded.
7. Structured errors and committed evidence contain no forbidden secrets or absolute user paths.
8. Windows execution is native and uses neither WSL nor Git Bash.
9. The canonical manifest and structured result behaviors are implementable without a blocking
   platform limitation.

A hard-gate failure remains valuable evidence. It disqualifies that candidate from the current
selection; it is not hidden or converted into a low weighted score.

## Fixed weighted rubric

Candidates that pass all hard gates receive a score out of 100:

| Category | Weight |
| --- | ---: |
| Process and filesystem reliability | 25 |
| Cross-platform packaging and lifecycle | 20 |
| Testability and maintainability | 20 |
| Supply-chain and security | 15 |
| Existing Python foundation reuse or migration cost | 10 |
| Startup time, memory, and artifact size | 10 |

Measurable values come from repeated harness runs. Cold-start measurements record individual
samples, median, and p95; artifact and dependency sizes use bytes. Qualitative scores require a
written rubric entry with concrete code, dependency, or operational evidence.

Weights and scoring bands are committed before candidate results are accepted. After results exist,
a change requires an ADR explaining why the original criterion was invalid and a complete rerun of
all affected candidates. Criteria may not be changed to favor a preferred result.

If the top candidates differ by three or fewer points, the tie-break review considers, in order:

1. fewer platform limitations;
2. smaller supply-chain surface;
3. lower risk in preserving tested existing behavior;
4. simpler long-term maintenance.

The final runtime selection always requires user approval and an ADR. A score never silently
changes product architecture.

## Error and inconclusive behavior

The harness never invents a winner or capability:

- If no runtime passes every hard gate, no runtime is selected. The failure is reviewed and a new
  candidate or changed requirement requires user approval and affected reruns.
- If a host is unavailable, the relevant runtime cells remain inconclusive and the 0R gate remains
  open.
- If a client cannot be accessed, only that client’s 0C gate remains open. Other independent gates
  may complete.
- If a Unity route cannot run on one required host, that route/host cell remains open and later
  specs cannot assume it.
- If a probe crashes or emits invalid evidence, the result is a harness failure, not a candidate
  pass or fail.
- If redaction cannot prove an artifact safe to commit, the artifact remains local and the result
  is inconclusive until another sufficient sanitized proof exists.

Retries create new immutable run records. They do not overwrite failed or inconclusive evidence.

## Gate dependencies

The gates are intentionally independent:

- **0A** must pass before any experimental result is accepted.
- **0R** unlocks the technology-specific Canonical Foundation spec and plan.
- A client-specific **0C** gate unlocks only that client’s adapter spec.
- **0U** unlocks the production Unity Execution Layer spec.
- The Windows reference vertical slice requires 0R, Claude and Codex 0C, and the necessary Windows
  0U evidence.
- Client Expansion requires each target client’s own completed 0C gate; one unavailable client does
  not create assumed behavior for another.

This permits evidence-backed downstream progress without treating the whole spike as one
all-or-nothing milestone.

## Testing strategy

The evidence harness is implemented test-first and receives:

- strict schema and unknown-field tests;
- checksum and missing-artifact tests;
- path traversal, symlink, and absolute-path tests;
- credential and sensitive-field redaction tests;
- duplicate, overwrite, and immutable-run tests;
- coverage tests for fail, unavailable, inconclusive, and missing cells;
- deterministic sorting and report-generation tests;
- scoring, hard-gate, rerun, and tie-threshold tests.

Every runtime candidate is exercised by the same black-box contract suite. Candidate-specific unit
tests are permitted but cannot replace contract results.

Client behavior cases use committed synthetic prompts and expected observations. Clean-session
execution is mandatory; a previously loaded skill or configuration invalidates discovery evidence.

Unity uses only disposable fixtures and backups. Tests cover successful execution, expected
refusal, timeout, cancellation, crash recovery, mismatched Editor, bridge-without-Editor, dirty
scene boundaries, and isolation.

## Completion criteria

Subproject 0 is complete when:

- the 0A harness rejects incomplete, unsafe, or fabricated evidence and deterministically renders
  reports;
- all four runtime candidates have immutable results for every required host;
- a hard-gate-qualified runtime is selected through the fixed rubric and approved ADR;
- every client surface has a documented and live-tested capability record or remains visibly
  gated as inconclusive;
- all four Unity routes have native evidence on Windows, macOS, and Linux, including safe refusal
  cases;
- existing Python behavior has a keep/adapt/replace inventory backed by tests;
- downstream dependency states are machine-readable and documentation links to their evidence;
- no raw secret, absolute user path, or unredacted account/project content is committed.

Subproject 0 delivers evidence and decisions, not a production Kinglet release.
The 0D decision package may close while an inaccessible client’s individual 0C gate remains open;
that client’s adapter spec remains locked until later live evidence closes its gate. Runtime and
Unity gates cannot be declared complete with required host cells still inconclusive.

## Reference constraints

Implementation planning must revalidate current official documentation before pinning probes,
because plugin and packaging surfaces evolve. Initial references include:

- PyInstaller platform and bundling behavior: `https://pyinstaller.org/en/stable/`
- Rust target support: `https://doc.rust-lang.org/rustc/platform-support.html`
- Go Windows cross-compilation: `https://go.dev/wiki/WindowsCrossCompiling`
- .NET single-file deployment:
  `https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview`
- Claude Code plugins: `https://code.claude.com/docs/en/discover-plugins`
- Codex plugins: `https://developers.openai.com/codex/plugins/build`
- Cursor marketplace: `https://cursor.com/marketplace/publish`
- Copilot CLI plugins:
  `https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-finding-installing`
- VS Code agent plugins:
  `https://code.visualstudio.com/docs/agent-customization/agent-plugins`
- Antigravity plugins:
  `https://antigravity.google/docs/ide/plugins?app=antigravity-ide`
- Unity command-line operation:
  `https://docs.unity3d.com/6000.0/Documentation/Manual/EditorCommandLineArguments.html`
- CoplayDev Unity MCP: `https://coplaydev.github.io/unity-mcp/`
