# Kinglet Hook Policy and Unity MCP Orchestration Implementation Plan

> **Superseded:** Historical plan; do not execute. The approved platform redesign starts with
> `2026-07-23-kinglet-00-plan-suite.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Claude and Codex the same ordered safety decisions and Unity MCP orchestration contract, including workflow-selection enforcement, a single-writer lease, task-scoped EditorSnapshot, and evidence-backed verification.

**Architecture:** Thin client normalizers turn native hook events into one canonical event. A single sequential Bash dispatcher evaluates client-neutral policies and native adapters translate its decision back. A versioned MCP lock classifies tool/action pairs from CoplayDev v10.1.0. State helpers atomically manage request selection, writer lease, EditorSnapshot, and verification receipts beneath `.kinglet/state/`. The orchestrator owns state and grants roles only the minimum live MCP capability.

**Tech Stack:** Bash 3.2, `jq`, JSON, Plan 01 Python build/tests, Claude and Codex plugin hook adapters, CoplayDev MCP for Unity v10.1.0, Unity 6 release fixture.

## Global Constraints

- Execute after Plan 03's completion gate.
- Pin CoplayDev `unity-mcp` tag `v10.1.0`; Unity package and Python server versions are both `10.1.0`. The verified release commit begins `c14de1e`. Record the full immutable commit returned by the tag in the lock file and reject a tag/commit mismatch.
- The Unity package URL is `https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#v10.1.0`; `#main` and `#beta` are forbidden in generated products.
- Kinglet does not ship, fork, patch, proxy, or wrap a second MCP server.
- Native event JSON never enters a canonical policy. Native tool names never enter canonical roles/workflows.
- Policies execute sequentially in ascending priority; a block stops later mutation/advisory policies.
- Unknown or malformed mutation-capable events fail closed. Clearly read-only events may fail with a visible diagnostic but never gain write authority.
- First mutation requires a valid current selection and a compatible `filesystem.write` or `unity.write` capability.
- Only one project-local Unity writer may hold the 15-minute lease. An active lease is never stolen automatically.
- Every successful or uncertain mutation invalidates the prior snapshot.
- Scene verification requires fresh state readback; visual changes additionally require a captured and reviewed screenshot.
- End-user runtime requires Bash and `jq`, already part of the supported Linux/macOS host contract; it does not require the Kinglet Python builder.
- Every new tracked file receives one `provenance.tsv` row in its task commit.

## Dependency and File Map

```text
migration/hook-inventory.json                         Exact 26-hook migration map
src/hooks/<slug>/{hook.json,policy.sh}                Canonical hook policies
src/catalog/mcp-lock.json                             Immutable bridge/version/tool lock
src/catalog/mcp-actions.json                          Tool/action read-write classification
src/catalog/editor-snapshot-schema.json               Snapshot contract
src/catalog/verification-evidence.json                Evidence schemas and invalidation rules
adapters/claude/hooks.json                            Claude event/response mapping
adapters/codex/hooks.json                             Codex event/response mapping
runtime/hooks/dispatcher.sh                           One ordered policy engine
runtime/hooks/normalize-claude.sh                     Claude JSON to canonical event
runtime/hooks/normalize-codex.sh                      Codex JSON to canonical event
runtime/hooks/respond-claude.sh                       Canonical decision to Claude JSON
runtime/hooks/respond-codex.sh                        Canonical decision to Codex JSON
runtime/lib/json.sh                                   jq validation helpers
runtime/lib/path.sh                                   Project-relative path classifier
runtime/lib/state.sh                                  Atomic state-file helpers
runtime/bin/kinglet-workflow-state                    Selection set/show/clear CLI
runtime/bin/kinglet-writer-lease                      Lease acquire/renew/release/status CLI
runtime/bin/kinglet-editor-snapshot                   Snapshot validate/show/invalidate CLI
packages/claude/.claude/hooks/**                      Generated Claude hook runtime
packages/claude/.claude/settings.json                 Generated Claude hook registration
plugins/kinglet-unity/hooks/**                        Generated Codex hook runtime
.claude/{hooks,settings.json}                         Temporary generated compatibility mirror
tests/hooks/fixtures/{canonical,claude,codex}/**      Native and normalized event fixtures
tests/hooks/test-normalizers.sh                       Native parity tests
tests/hooks/test-dispatcher.sh                        Ordering/decision tests
tests/hooks/test-workflow-selection.sh                First-mutation guard tests
tests/hooks/test-writer-lease.sh                      Atomic lease tests
tests/hooks/test-state-runtime.sh                     State CLI tests
tests/mcp/test-mcp-lock.sh                            Version/action lock tests
tests/mcp/test-editor-snapshot.sh                     Snapshot validity tests
tests/kinglet/test_hook_renderers.py                  Package registration tests
```

## Task 1: Freeze and Classify the Existing 26 Hook Behaviors

**Files:**

- Create: `migration/hook-inventory.json`
- Create: `tests/kinglet/test_hook_inventory.py`
- Extend: `tools/kinglet_build/import_legacy.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Assert the exact executable-hook set**

The inventory test asserts these slugs and source hashes exactly, excluding `_lib.sh`:

```text
auto-learn bash-gate block-legacy-input block-meta-edit block-projectsettings
block-scene-edit build-analyze cost-tracker gateguard guard-editor-runtime
guard-project-config instinct-capture instinct-distill notify pre-compact
quality-gate session-restore session-save stop-validate suggest-verify
track-edits track-reads validate-commit warn-filename warn-platform-defines
warn-serialization
```

Every entry declares canonical events, priority, default decision, whether it needs `jq`, state files read/written, and legacy SHA-256. Priority bands are:

| Band | Purpose |
|---:|---|
| `100–199` | malformed event, routing, workflow selection |
| `200–299` | writer lease and protected Unity paths |
| `300–399` | dangerous shell/editor/runtime/commit blocks |
| `400–499` | validation and verification gates |
| `500–599` | advisory warnings |
| `600–699` | observations, learning, cost tracking |
| `800–899` | session/compaction lifecycle |
| `900–999` | stop/report behavior |

- [ ] **Step 2: Test import preservation**

Extend importer tests to reject Bash syntax errors, non-executable policies, absolute sourced paths, direct parsing of native Claude fields in canonical policy bodies, and policies that mutate outside `.kinglet/state/` without declaring the path.

- [ ] **Step 3: Commit the reviewed inventory**

```bash
python3 -m unittest tests.kinglet.test_hook_inventory -v
git add migration/hook-inventory.json tools/kinglet_build/import_legacy.py tests/kinglet provenance.tsv
git commit -m "test: freeze Kinglet hook migration map"
```

## Task 2: Define the Canonical Event, Decision, and Native Normalizers

**Files:**

- Create: `adapters/claude/hooks.json`
- Create: `adapters/codex/hooks.json`
- Create: `runtime/lib/json.sh`
- Create: `runtime/lib/path.sh`
- Create: `runtime/hooks/normalize-claude.sh`
- Create: `runtime/hooks/normalize-codex.sh`
- Create: `runtime/hooks/respond-claude.sh`
- Create: `runtime/hooks/respond-codex.sh`
- Create: `tests/hooks/fixtures/**`
- Create: `tests/hooks/test-normalizers.sh`
- Modify: `provenance.tsv`

- [ ] **Step 1: Capture native fixtures before writing normalizers**

Record redacted, version-labeled native events for each supported client lifecycle equivalent of:

```text
session_start user_request before_action after_action stop
```

Include filesystem reads/writes, shell commands, read-only Unity MCP calls, mutating Unity MCP calls, malformed input, absent optional fields, spaces/unicode in paths, and a session ID mismatch. Fixtures contain no user secret or absolute developer path.

- [ ] **Step 2: Specify the normalized event**

Both normalizers emit exactly this shape with absent values represented by `null`, never omitted:

```json
{
  "schema_version": 1,
  "event_id": "evt-018f6c6f",
  "event": "before_action",
  "client": "claude",
  "session_id": "session-018f6c6f",
  "workflow_id": "workflow.unity-feature",
  "request_sha256": "8db0f03b8b8d9f665ad231bfbcf5c0b7f117e65909849e440db3c62f66d6347a",
  "tool": "manage_gameobject",
  "operation": "create",
  "path": "Assets/Scenes/Arena.unity",
  "command": null,
  "cwd": "/project",
  "timestamp": "2026-07-22T12:00:00Z",
  "native_payload_sha256": "915e3a4c2836bb6ea41876e4319ebf8e12c212676c39b2e5f2526267b9dd23d1"
}
```

The test compares normalized Claude and Codex pairs byte-for-byte after replacing `client`, `event_id`, and native payload digest. It also proves native responders translate canonical `allow`, `warn`, and `block` without weakening a block.

- [ ] **Step 3: Implement Bash 3.2-safe normalizers**

Use `jq -e` for types and required fields. Resolve `cwd` physically, reject NUL/newline path ambiguity, and convert paths to project-relative form only after proving they remain under the project root. Do not use associative arrays, `mapfile`, `readarray`, `local -n`, GNU-only `realpath`, or process substitution whose failure is hidden.

Malformed `before_action` input returns canonical block `hook.invalid-event`; malformed non-mutating lifecycle input returns warn plus a diagnostic. Native response scripts must never include raw commands or full native payloads in user-facing text.

- [ ] **Step 4: Verify on Linux-compatible shell and macOS Bash contract**

```bash
bash tests/hooks/test-normalizers.sh
bash -n runtime/lib/*.sh runtime/hooks/*.sh
```

Expected: all paired fixtures produce equivalent canonical decisions and malformed mutation fixtures block.

- [ ] **Step 5: Commit**

```bash
git add adapters runtime tests/hooks provenance.tsv
git commit -m "feat: normalize Kinglet client hook events"
```

## Task 3: Import Policies and Build One Ordered Dispatcher

**Files:**

- Create: `src/hooks/*/{hook.json,policy.sh}`
- Create: `runtime/hooks/dispatcher.sh`
- Create: `tests/hooks/test-dispatcher.sh`
- Modify: `tools/kinglet_build/validator.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test dispatcher ordering and failure semantics**

Fixtures prove:

- policies run by numeric priority then canonical hook ID;
- the first block stops later policies;
- warnings accumulate in deterministic order and never overwrite a block;
- observations run only after blocking mutation policies allow;
- an undeclared state write blocks with `hook.policy-contract`;
- missing, non-executable, malformed-JSON, timed-out, or crashing policy fails closed for `before_action`;
- dispatcher output is one JSON document with `decision`, `policy_id`, `message`, `warnings`, and `evaluated`.

Set a five-second per-policy timeout using a portable watchdog helper that works with macOS Bash; do not depend on GNU `timeout`.

- [ ] **Step 2: Import all existing behaviors**

Run:

```bash
python3 -m tools.kinglet_build.import_legacy --kind hook
```

Refactor each body to consume the normalized event from stdin or a read-only temporary file supplied by the dispatcher. Shared helpers move into `runtime/lib/`; policy bodies never source root `.claude/hooks/_lib.sh`. Preserve each blocking/advisory behavior unless a golden exception records a deliberate safety strengthening.

- [ ] **Step 3: Implement the policy protocol**

Each policy exits `0` and prints one compact JSON decision:

```json
{"policy_id":"hook.block-meta-edit","decision":"block","message":"Unity .meta files must be created by the editor."}
```

Allowed decisions are `allow`, `warn`, `block`, and `pass`. `pass` means no opinion; final default is `allow`. A policy process error is not a valid `pass`.

- [ ] **Step 4: Validate and commit**

```bash
bash tests/hooks/test-dispatcher.sh
python3 -m tools.kinglet_build validate
git add src/hooks runtime/hooks/dispatcher.sh tests/hooks tools/kinglet_build/validator.py provenance.tsv
git commit -m "feat: dispatch canonical Kinglet hook policies"
```

## Task 4: Enforce Current Workflow Selection Before First Mutation

**Files:**

- Create: `src/hooks/require-workflow-selection/hook.json`
- Create: `src/hooks/require-workflow-selection/policy.sh`
- Create: `runtime/lib/state.sh`
- Create: `runtime/bin/kinglet-workflow-state`
- Create: `tests/hooks/test-workflow-selection.sh`
- Modify: `.gitignore`
- Modify: `provenance.tsv`

- [ ] **Step 1: Write the complete deny/allow matrix**

Test writes under `Assets/`, `Packages/`, and `ProjectSettings/`, plus every v10.1.0 MCP tool/action classification. A mutation blocks for missing file, malformed JSON, wrong schema, wrong client, wrong session, wrong request digest, stale/completed workflow, medium/low confidence, `needs_clarification`, unknown workflow, read-only workflow, or incompatible capability.

Allow cases require:

- current client and session match;
- request digest matches the current request captured by the native adapter;
- confidence is `high` and clarification is false;
- selected workflow exists and is not complete;
- filesystem mutation has `filesystem.write`;
- Unity mutation has `unity.write`;
- attempted path is inside the project and within the workflow's declared scope.

Read-only MCP calls, reads outside protected Unity roots, documentation replies, and project files outside protected roots do not require selection, though other policies may govern them.

- [ ] **Step 2: Implement atomic state commands**

`runtime/bin/kinglet-workflow-state` supports exactly:

```text
set --client CLIENT --session SESSION --workflow ID --source SOURCE --confidence LEVEL --reason TEXT --request-sha256 HEX [--needs-clarification]
show
complete --client CLIENT --session SESSION --workflow ID
clear --client CLIENT --session SESSION --workflow ID
```

`set` writes `.kinglet/state/workflow-selection.json` through a same-directory temporary file, `chmod 600`, `fsync` where portable, then rename. `complete` records completion before clearing so a stale hook event cannot recreate authority. `clear` refuses a mismatched owner. State commands take structured arguments; they never evaluate request text as shell.

- [ ] **Step 3: Add runtime-state ignore rules**

Ignore `.kinglet/state/`, `.kinglet/backups/`, `.kinglet/pending/`, and transient lock directories in installed projects. Do not ignore the canonical schemas, package manifests, or test fixtures in this repository.

- [ ] **Step 4: Verify and commit**

```bash
bash tests/hooks/test-workflow-selection.sh
bash tests/hooks/test-state-runtime.sh
git add src/hooks/require-workflow-selection runtime .gitignore tests/hooks provenance.tsv
git commit -m "feat: require Kinglet workflow selection for mutation"
```

## Task 5: Add the Atomic 15-Minute Single-Writer Lease

**Files:**

- Create: `src/hooks/require-writer-lease/hook.json`
- Create: `src/hooks/require-writer-lease/policy.sh`
- Create: `runtime/bin/kinglet-writer-lease`
- Create: `tests/hooks/test-writer-lease.sh`
- Modify: `runtime/lib/state.sh`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test ownership, expiry, and races**

Use a controllable clock fixture. Assert:

- first valid mutating workflow acquires a lease;
- the same client/session/workflow/lease ID may renew;
- a second session/client/workflow blocks while active;
- read-only events remain allowed during another writer's lease;
- only an expired lease may be cleared automatically;
- release requires exact client, session, workflow, and random lease ID;
- a crashed or interrupted writer leaves a diagnosable lease;
- 20 parallel acquire attempts yield exactly one owner;
- symlinked or malformed lease paths fail closed;
- clock rollback does not extend an already recorded expiry.

- [ ] **Step 2: Implement exact lease payload and CLI**

The payload is:

```json
{
  "schema_version": 1,
  "lease_id": "lease-4f05d7a94224484ca9884d8cab441976",
  "client": "codex",
  "session_id": "session-018f6c6f",
  "workflow_id": "workflow.unity-feature",
  "acquired_at": "2026-07-22T12:00:00Z",
  "renewed_at": "2026-07-22T12:05:00Z",
  "expires_at": "2026-07-22T12:20:00Z"
}
```

The CLI supports `acquire`, `renew`, `release`, `status`, and `clear-expired`. Acquisition uses atomic `mkdir .kinglet/state/unity-write-lease.lock`, validates state, writes by rename, and always removes only the lock directory it created. Generate 128-bit lease IDs from `/dev/urandom` using portable tools; fail rather than use a predictable fallback.

- [ ] **Step 3: Connect policy order and renewal**

`require-workflow-selection` runs first. `require-writer-lease` runs second and acquires on the first permitted Unity mutation, renews after every successful or uncertain mutation, and never releases on an individual tool call. The workflow completion path releases, records final evidence, and then clears selection.

- [ ] **Step 4: Verify and commit**

```bash
bash tests/hooks/test-writer-lease.sh
bash tests/hooks/test-dispatcher.sh
git add src/hooks/require-writer-lease runtime tests/hooks provenance.tsv
git commit -m "feat: serialize Kinglet Unity writers"
```

## Task 6: Lock MCP v10.1.0 and Classify Every Tool Action

**Files:**

- Create: `src/catalog/mcp-lock.json`
- Create: `src/catalog/mcp-actions.json`
- Create: `tests/mcp/fixtures/v10.1.0-manifest.json`
- Create: `tests/mcp/test-mcp-lock.sh`
- Create: `tests/kinglet/test_mcp_catalog.py`
- Modify: `tools/kinglet_build/validator.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Freeze primary-source release evidence**

Fetch tag `v10.1.0`, verify its signed GitHub release commit, record the full commit SHA, and copy the tagged root `manifest.json` into the fixture with source URL and SHA-256. Assert tagged files report:

```text
MCPForUnity/package.json version = 10.1.0
Server/pyproject.toml version = 10.1.0
```

The tagged manifest enumerates the official tool surface. Tests fail if the lock omits or invents a listed tool. The official release is documented at [CoplayDev MCP for Unity v10.1.0](https://github.com/CoplayDev/unity-mcp/releases/tag/v10.1.0).

- [ ] **Step 2: Classify tool/action pairs, not names alone**

Tools such as `manage_scene`, `manage_script`, `manage_asset`, `manage_editor`, `manage_packages`, and `manage_profiler` contain both read and mutation operations. `mcp-actions.json` therefore declares allowed action values under each tool as `read`, `write`, or `dangerous-write`. The following are always mutation-capable regardless of omitted action:

```text
apply_text_edits batch_execute create_script delete_script execute_custom_tool execute_code
execute_menu_item refresh_unity script_apply_edits
```

Unknown actions on a mutation-capable or `manage_*` tool classify as `dangerous-write` and block. `read_console`, `find_gameobjects`, `find_in_file`, `get_sha`, `get_test_job`, `manage_script_capabilities`, `unity_docs`, `unity_reflect`, and `validate_script` may classify read-only only for action/arguments proven non-mutating by fixtures.

- [ ] **Step 3: Add validator and runtime classifier tests**

The Python validator checks full manifest coverage and lock consistency. Shell tests feed representative events to the workflow-selection and lease policies. `batch_execute` is write if any nested operation writes or cannot be classified.

- [ ] **Step 4: Verify and commit**

```bash
python3 -m unittest tests.kinglet.test_mcp_catalog -v
bash tests/mcp/test-mcp-lock.sh
rg -n '#(main|beta)' src packages plugins install.sh
```

Expected: catalog is complete; search finds no active MCP dependency using a moving branch. Historical migration fixtures may be explicitly exempted by path.

Commit:

```bash
git add src/catalog tests/mcp tests/kinglet tools/kinglet_build/validator.py provenance.tsv
git commit -m "feat: pin and classify MCP for Unity v10.1.0"
```

## Task 7: Implement EditorSnapshot and Verification Evidence

**Files:**

- Create: `src/catalog/editor-snapshot-schema.json`
- Create: `src/catalog/verification-evidence.json`
- Create: `runtime/bin/kinglet-editor-snapshot`
- Create: `runtime/bin/kinglet-evidence`
- Create: `tests/mcp/test-editor-snapshot.sh`
- Create: `tests/mcp/test-verification-evidence.sh`
- Modify: `runtime/lib/state.sh`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test the snapshot schema and invalidation matrix**

Require schema version/capture time; Unity version; active build target; render pipeline; compilation/play-mode state; active scene path/dirty flag/hierarchy digest/task-relevant objects; package manifest digest/relevant packages; console error/warning counts and digest; current selection; workflow ID; MCP version; and snapshot validity.

Invalidate after filesystem/Unity write, scene load, compile transition, play-mode transition, active-instance change, or a hierarchy/package/console digest change. Reject cross-project, cross-workflow, stale-version, future-time, and post-mutation snapshots.

- [ ] **Step 2: Implement safe snapshot state commands**

`kinglet-editor-snapshot` supports `capture`, `validate`, `show --scope ROLE_ID`, and `invalidate --reason CODE`. `capture` consumes a JSON document assembled from read-only v10.1.0 MCP calls; it does not invoke MCP itself. `show --scope` applies the role capability model and omits irrelevant/noisy state.

The orchestrator captures the full snapshot. Design/production roles get the task subset; scouts/reviewers get snapshot plus temporary live reads; implementers get fresh snapshot and scoped write only after lease; verifiers get fresh read/test/console/capture access and no arbitrary production mutation.

- [ ] **Step 3: Implement evidence receipts**

`kinglet-evidence record` writes append-only JSONL beneath `.kinglet/state/evidence/<workflow-id>/` with evidence type, capture time, source tool, snapshot digest, result digest, pass/fail, and artifact path. Supported evidence types are:

```text
console-clean unity-tests-pass scene-state-readback screenshot-reviewed references-valid
build-succeeded reproduced-before absent-after profile-before profile-after
```

`kinglet-evidence verify --workflow ID` reads canonical workflow requirements and fails if evidence predates the last mutation, comes from another session/workflow, references a stale snapshot, or lacks its artifact.

- [ ] **Step 4: Verify and commit**

```bash
bash tests/mcp/test-editor-snapshot.sh
bash tests/mcp/test-verification-evidence.sh
git add src/catalog runtime tests/mcp provenance.tsv
git commit -m "feat: capture Kinglet editor and verification state"
```

## Task 8: Render and Register Equivalent Native Hook Packages

**Files:**

- Create: `tools/kinglet_build/renderers/claude_hooks.py`
- Create: `tools/kinglet_build/renderers/codex_hooks.py`
- Create: `tests/kinglet/test_hook_renderers.py`
- Generate: `packages/claude/.claude/hooks/**`
- Generate: `packages/claude/.claude/settings.json`
- Generate: `plugins/kinglet-unity/hooks/**`
- Regenerate: `.claude/hooks/**`
- Regenerate: `.claude/settings.json`
- Modify: `tools/kinglet_build/renderers/__init__.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test native registrations against adapter schemas**

Assert every supported native event points first to its normalizer, then the canonical dispatcher, then its response translator. Paths are plugin/package relative, arguments are arrays rather than shell-concatenated user data, executable bits are preserved, and both clients include the same canonical policy manifest digest.

Claude output must preserve compatible lifecycle coverage from the legacy settings. Codex output uses only its supported plugin hook surface. If a native event lacks an exact equivalent, the adapter must prove the behavior at the next earlier enforceable event and declare a named parity test; silent omission is invalid.

- [ ] **Step 2: Generate both products and the final compatibility hook mirror**

After a passing build, root `.claude/hooks` and `.claude/settings.json` are generated compatibility outputs. The builder must no longer read them. Historical `_lib.sh` functionality must either exist in `runtime/lib/` or be proven unused before removal.

- [ ] **Step 3: Run full hook decision parity**

```bash
python3 -m tools.kinglet_build build --all
python3 -m tools.kinglet_build build --all --check
bash tests/hooks/test-normalizers.sh
bash tests/hooks/test-dispatcher.sh
bash tests/hooks/test-workflow-selection.sh
bash tests/hooks/test-writer-lease.sh
bash tests/mcp/test-mcp-lock.sh
bash tests/mcp/test-editor-snapshot.sh
python3 -m unittest tests.kinglet.test_hook_renderers -v
```

Expected: every paired native fixture reaches the same final `allow`, `warn`, or `block` and stable policy ID.

- [ ] **Step 4: Commit**

```bash
git add tools/kinglet_build packages plugins .claude/hooks .claude/settings.json tests/kinglet provenance.tsv
git commit -m "feat: generate equivalent Kinglet hook packages"
```

## Task 9: Run a Live MCP Contract Smoke Test

**Files:**

- Create: `tests/evals/mcp/README.md`
- Create: `tests/evals/mcp/record-contract.py`
- Create: `tests/evals/mcp/evaluate-contract.py`
- Create: `tests/kinglet/test_mcp_evaluator.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test the evaluator with recorded passing/failing sessions**

It checks bridge/package/server version, tool-list digest, read-only calls without a lease, mutation block without selection, mutation block without lease, one permitted scoped mutation, snapshot invalidation, fresh console/scene/test evidence, and lease/selection cleanup.

- [ ] **Step 2: Run against one disposable Unity 6 fixture**

Install the pinned tag, let MCP for Unity register each client, and record separate Claude/Codex sessions against the same reset fixture. Kinglet must not edit client registration automatically. The smoke mutation creates and removes a disposable object under a test scene; it never touches the user's brownfield project.

- [ ] **Step 3: Verify and commit the protocol, not machine-local output**

```bash
python3 -m unittest tests.kinglet.test_mcp_evaluator -v
python3 tests/evals/mcp/evaluate-contract.py tests/evals/mcp/fixtures/passing.jsonl
! python3 tests/evals/mcp/evaluate-contract.py tests/evals/mcp/fixtures/stale-snapshot.jsonl
```

Commit:

```bash
git add tests/evals/mcp tests/kinglet provenance.tsv
git commit -m "test: add Kinglet live MCP contract evaluation"
```

## Plan 04 Completion Gate

Plan 05 may start only when:

- all legacy hook behaviors are canonicalized and the root hook tree is generated;
- paired Claude/Codex native fixtures produce identical ordered decisions;
- missing/stale/clarifying/cross-session selections block protected mutation;
- concurrent lease tests produce exactly one writer and never steal an active lease;
- v10.1.0 package/server/tool locks match the signed release tag;
- snapshot invalidation and fresh evidence rules pass;
- one disposable live Unity 6 smoke session passes for both clients;
- no generated product references an MCP moving branch.
