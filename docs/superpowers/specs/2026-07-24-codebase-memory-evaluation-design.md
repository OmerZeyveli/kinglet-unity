# Codebase Memory Evaluation and Optional Provider Design

**Status:** Approved design

**Date:** 2026-07-24

**Parent designs:**

- `2026-07-23-kinglet-platform-design.md`
- `2026-07-23-kinglet-platform-spikes-design.md`

## Decision

Kinglet will evaluate `DeusData/codebase-memory-mcp` before either using it during Kinglet
development or exposing it through the future Kinglet product.

The evaluation produces two independent decisions:

1. **Development-tool decision:** whether maintainers should use Codebase Memory while building
   Kinglet alongside Superpowers.
2. **Product decision:** whether Kinglet should later support Codebase Memory as an optional,
   externally installed code-intelligence provider.

Kinglet will not bundle the Codebase Memory binary. It will not reimplement Codebase Memory's
Tree-sitter, SQLite graph, watcher, or query engine. It may independently adopt small design
principles such as freshness checks, bounded structural context, evidence tiers, and source
fallbacks.

The balanced adoption threshold is:

- no correctness regression; and
- at least 50% median paired token reduction in representative Codex tasks.

Headline upstream claims are hypotheses, not acceptance evidence. The evaluation must measure the
current Kinglet and Unity-shaped workloads directly.

## Upstream snapshot

The ignored research clone is:

`.research/codebase-memory-mcp`

The initial audit inspected upstream `main` at:

`97ce23f9827177fff3858831156e9795c6832b18`

Reproducible execution will use tag `v0.9.0` pinned by commit, not the moving branch:

`b637e3330c96cfe452da623db068c241aaa3ec01`

The plan must record the source commit, compiler identity, build command, executable checksum, and
test result. A later upstream revision is a new candidate and may not overwrite the original run.

## Approaches considered

### 1. Run the upstream global installer

The upstream installer can configure Codex MCP entries, global instructions, a skill, three agent
profiles, and lifecycle hooks. This is convenient but changes too many variables for a controlled
evaluation and could interfere with the existing Superpowers workflow.

This approach is rejected for the experiment.

### 2. Isolated read-only provider evaluation

Build the pinned source locally, index only explicit roots with one-shot CLI commands, and expose a
read-only MCP `analysis` profile to disposable Codex runs. Do not install global instructions,
skills, agents, hooks, auto-indexing, or the UI.

This is the selected approach. It isolates the retrieval mechanism, preserves the existing
Superpowers process layer, and matches the intended optional-provider boundary.

### 3. Build a Kinglet-native graph engine

Kinglet could reproduce selected upstream capabilities internally. A full implementation would add
language parsers, call resolution, persistent graph storage, incremental indexing, query tooling,
and a substantial new security and maintenance surface.

This approach is rejected. Kinglet may adopt provider-neutral principles and contracts, but it will
not recreate the upstream engine unless a future independently approved design supplies compelling
evidence.

## Evaluation architecture

The evaluation has five isolated components.

### Candidate workspace

The pinned upstream commit is checked out in an ignored or temporary workspace. Its build products
never enter Kinglet release inputs. Upstream scripts are inspected before execution, and the
candidate is built from source without running `install`, `update`, or `uninstall`.

### Explicit index controller

Index creation uses one-shot CLI mode. Each target receives:

- an explicit absolute repository root;
- `CBM_ALLOWED_ROOT` restricted to that target;
- a fresh experiment-specific `CBM_CACHE_DIR`;
- auto-index disabled;
- the UI disabled;
- no standing watcher after the command exits.

Indexes for different targets and repetitions are separate. A cold-index result and an incremental
refresh result are recorded independently.

### Read-only MCP surface

Treatment Codex runs receive the candidate with:

`--tool-profile=analysis`

This surface permits structural inspection but excludes graph and index mutation tools. Index
creation remains an explicit maintainer action. The restricted profile also prevents the normal
full-profile background update and auto-index work.

### Paired-run harness

A standard-library evaluation harness prepares tasks, launches baseline and treatment runs,
captures machine-readable Codex events, validates receipts, scores ground-truth facts, and renders
deterministic reports.

The harness never edits user Codex configuration. Candidate MCP configuration is supplied only to
the disposable treatment process. Both arms use:

- the same Codex version;
- the same model and reasoning setting;
- the same read-only sandbox;
- ephemeral sessions;
- the same working tree snapshot;
- the same prompt and structured answer schema;
- the same timeout and retry policy.

The baseline can use normal filesystem search and reads. The treatment can also use the read-only
Codebase Memory surface. Superpowers remains available in both arms so the experiment measures the
incremental value of the provider rather than replacing the development process.

### Evidence and report renderer

Raw prompts, event streams, absolute paths, and local diagnostics remain ignored under:

`.kinglet/local/experiments/codebase-memory/`

Sanitized manifests and deterministic reports are published under:

`docs/research/codebase-memory/`

The report distinguishes observed results, upstream claims, evaluator judgments, unresolved
limitations, and future native-host requirements.

## Evaluation targets

### Target A — Kinglet repository

The current repository is primarily Python, Bash, Markdown, and JSON. Tasks cover:

- symbol discovery across `tools/kinglet_build` and `tools/kinglet_spike`;
- loader, validator, publisher, reporter, and CLI relationships;
- callers and consumers of gate state;
- cross-file impact of representative contract changes;
- architecture and package-boundary questions;
- Bash-to-Python execution paths;
- literal or configuration searches that should favor ordinary text tools;
- one bounded negative or exhaustive claim requiring coverage verification.

### Target B — Unity/C# research corpus

The existing ignored `.research/unity-mcp` clone supplies a substantial Unity-shaped C# corpus
without adding product code. Tasks cover:

- Editor and server boundary discovery;
- command or tool dispatch paths;
- C# caller/callee relationships;
- package and assembly structure;
- representative change impact;
- a literal/configuration case;
- one graph-incomplete case that must fall back to source inspection.

Results from this corpus determine only whether optional product support is promising. They do not
close Kinglet's Windows, macOS, client, or live-Unity evidence gates.

## Task and ground-truth design

Tasks are preregistered before candidate queries run. Each task contains:

- a stable ID and target commit;
- the exact user question;
- required facts with accepted symbol and relative-path forms;
- critical facts whose omission fails the task;
- allowed uncertainty;
- forbidden claims;
- the expected answer schema.

Ground truth is established from source and repository history without using Codebase Memory
output. A task score is the weighted fraction of required facts present after subtracting explicit
false-claim penalties. Critical false claims score the task as failed.

The final corpus contains eight tasks:

- four Kinglet structural tasks;
- two Unity/C# structural tasks;
- one literal/configuration task;
- one negative or coverage-sensitive task.

This mix prevents a graph-favoring benchmark from standing in for normal development work.

## Experiment phases

### Phase 0 — Readiness and safety

1. Verify the pinned source identity.
2. Inspect the build and test entry points.
3. Build the candidate locally.
4. Run the relevant upstream unit, security, and smoke tests.
5. Confirm the executable checksum and version.
6. Confirm no global Codex file changed.
7. Confirm read-only profile tool exposure.
8. Confirm explicit-root refusal and ignored cache placement.
9. Verify that Codex JSON events expose exact token usage.

If exact token usage is unavailable, the token gate is blocked. Bytes, characters, or guessed
tokenization may be reported diagnostically but may not substitute for the adoption metric.

### Phase 1 — Deterministic tool probe

Run direct CLI queries for the preregistered facts and compare them with source ground truth. This
phase measures index coverage, query precision, missing relationships, cold-index time,
incremental-refresh time, query latency, database size, and process cleanup.

This is a capability check, not the token-saving decision.

### Phase 2 — Codex pilot

Run three representative tasks once in each arm, for six Codex runs total.

Stop before the full experiment when:

- treatment correctness is lower;
- a critical false claim appears;
- the graph cannot stay fresh;
- token telemetry is incomplete;
- the candidate writes outside its assigned cache/config boundaries;
- the candidate leaves a process behind;
- treatment uses more tokens on all pilot tasks.

### Phase 3 — Full paired experiment

If the pilot passes, run all eight tasks twice per arm in randomized arm order. This produces 32
ephemeral Codex runs. Repetitions use fresh sessions and record their own usage; failed
infrastructure runs are not silently retried into a pass.

Per task, the report uses the median of the two valid repetitions. Across tasks, it reports median,
range, and individual paired deltas instead of relying on one aggregate.

## Metrics

### Primary

- task correctness score;
- critical false claims;
- total input plus output tokens;
- paired token reduction:

  `1 - treatment_tokens / baseline_tokens`

Cached input tokens are reported separately. The main comparison uses the same Codex accounting
field in both arms.

### Secondary

- tool-call count and type;
- wall-clock duration;
- cold and incremental index duration;
- query latency;
- index size and peak resident memory;
- number of graph answers requiring filesystem fallback;
- zero-result and stale-coverage rate;
- process and file cleanup;
- setup and maintenance complexity.

## Decision gates

### Development-tool gate

Codebase Memory is accepted for Kinglet development only when:

1. treatment correctness is not lower than baseline overall;
2. no treatment task introduces a critical false claim or safety regression;
3. the median paired token reduction is at least 50%;
4. at least six of eight tasks are neutral or better for correctness;
5. source fallback handles every recorded coverage gap;
6. no global configuration mutation, root escape, stale-process, or unbounded background-work
   failure occurs.

Wall-clock, memory, and maintenance findings can still reject adoption when they are operationally
disproportionate even if the token threshold passes; that judgment must cite measured evidence.

### Optional-product-provider gate

Codebase Memory becomes a candidate optional Kinglet provider only when:

1. the development-tool gate passes;
2. the Unity/C# subset has no correctness regression;
3. absence, stale index, partial coverage, and provider failure all produce a clean filesystem
   fallback;
4. Kinglet can detect the provider without installing, updating, or trusting it on the user's
   behalf;
5. the provider contract remains optional and no Codebase Memory artifact becomes a release input;
6. licensing and provenance can be represented without code or binary bundling.

Passing this gate does not implement the provider. It permits a future provider design and leaves
all required client and native-platform evidence open.

### Small-principle adoption

The final report may separately recommend provider-neutral ideas:

- freshness and generation identity;
- bounded context and pagination;
- coverage checks before negative claims;
- fast discovery versus verified/audited evidence tiers;
- exact-source verification for material claims;
- deterministic fallback when a provider is absent or incomplete.

These recommendations may pass even when both Codebase Memory adoption gates fail.

## Failure and safety behavior

- The experiment never runs an upstream `curl | shell` command.
- It never runs the upstream global installer.
- It never writes `~/.codex/config.toml`, `~/.codex/AGENTS.md`, global skills, agents, or hooks.
- It never enables the graph UI.
- It never commits a graph database, raw prompt, raw Codex event stream, absolute user path, or
  source snippet from an ignored research repository.
- A candidate process timeout triggers bounded process-tree termination and a cleanup assertion.
- Missing, corrupt, stale, partial, or ambiguous graph evidence is visible and cannot be upgraded
  to a pass.
- Windows and macOS remain explicitly untested until native evidence is collected.

## Testing strategy

The evaluation harness is implemented test-first. Tests cover:

- task and receipt schema validation;
- unknown-field rejection;
- token-accounting extraction;
- paired metric calculation;
- correctness and false-claim scoring;
- randomized arm order with a recorded seed;
- timeout and process cleanup;
- path containment and redaction;
- deterministic JSON and Markdown rendering;
- every development and product decision-gate boundary.

Fixture tests use synthetic Codex events and candidate outputs. Live candidate and Codex runs are
separate, explicitly invoked experiments and never ordinary CI requirements.

## Deliverables

The evaluation produces:

- a pinned candidate manifest;
- a preregistered task corpus and ground truth;
- sanitized environment and run receipts;
- deterministic JSON and Markdown comparison reports;
- a development-tool decision;
- an optional-product-provider decision;
- a short list of provider-neutral principles worth adopting;
- explicit unresolved Windows, macOS, client, and Unity evidence.

The result vocabulary is:

- `reject`;
- `development-only`;
- `optional-provider-candidate`;
- `inconclusive`.

No report may claim Codebase Memory saves 50%, 90%, or 99% of Kinglet tokens unless the recorded
paired runs support that exact statement.
