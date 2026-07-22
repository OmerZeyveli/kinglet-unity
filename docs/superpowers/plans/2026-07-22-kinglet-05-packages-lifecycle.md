# Kinglet Packages, Installation, Upgrade, and Uninstall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship valid Claude and Codex packages and a transaction-safe, ownership-preserving lifecycle for fresh install, legacy migration, upgrade, rollback, doctor, and client-selective uninstall.

**Architecture:** The generator emits immutable release products plus explicit base/profile-overlay install manifests. One Bash lifecycle engine validates the requested agent profile and native model capabilities before planning, then stages all manifest-driven writes, profile state, and a client-neutral receipt, validates the staged tree, backs up touched destinations, and commits atomically or rolls back. Claude's legacy entry point remains the default. Codex users normally install the plugin and run its setup skill; the root installer exposes equivalent project bootstrap for source/archive users. At this plan's final gate the installer reads only `packages/`, so the temporary root `.claude/` compatibility mirror is removed.

**Tech Stack:** Bash 3.2, `jq`, generated JSON manifests, SHA-256, Plan 01–04 builder/runtime, Codex plugin manifest/marketplace JSON, existing shell fixture suite.

## Global Constraints

- Execute after Plan 04's completion gate.
- `./install.sh --project-dir PATH` remains equivalent to `--client claude`.
- Valid client values are `claude`, `codex`, and `all`; reject every other value before any write.
- Valid agent profiles are `standard` and `frontier`. Fresh and legacy installs default only to `standard`; `frontier` always requires an explicit CLI/setup selection.
- One project has one Kinglet agent profile across all installed clients. Reject mixed Claude/Codex profiles and require a profile switch to include every installed client.
- Kinglet never changes the user's main-session model or writes a global/project-wide Claude/Codex model default.
- Frontier is fail-closed: no Fable access, no Sol access, no provable native Codex Pro binding, or `max` without Pro stops before staging. Never fall back to standard or emulate Pro in prompt text.
- `--client all --agent-profile frontier` preflights both clients before any write; a partial frontier install is forbidden.
- Codex setup never edits global `~/.codex/config.toml`, accepts hook trust, or registers MCP on the user's behalf.
- `--with-mcp` adds only the pinned v10.1.0 package URL and never replaces another MCP version silently.
- The receipt path is `.kinglet/state/install-receipt-v2.tsv` for all clients.
- User-modified receipted files stay in place; new versions go to `.kinglet/pending/3.0.0-dev.1/<client>/<path>`.
- Foreign collisions are never overwritten. Modified removed files become reported orphans.
- Managed-block replacement preserves every byte outside the markers.
- A dry run writes nothing, including no state, backup, pending, temp, or lock file in the target project.
- A failed transaction leaves the pre-run project state plus a diagnostic; it never leaves half of a client installed.
- Default uninstall never removes modified or foreign files. `--purge` remains explicit and requires confirmation unless `--yes` is present.
- Linux and macOS paths/modes/hashes must behave identically; no GNU-only command is allowed without a portable fallback.
- Every new tracked file receives one `provenance.tsv` row in its task commit.

## Dependency and File Map

```text
packages/claude/install-manifest.json                Claude immutable install manifest
packages/claude/.claude/**                          Complete Claude release payload
packages/claude/profiles/frontier/**                 Claude deep-role overlay
plugins/kinglet-unity/.codex-plugin/plugin.json     Codex plugin manifest
plugins/kinglet-unity/skills/setup/SKILL.md          Deterministic project setup entry
plugins/kinglet-unity/bin/kinglet-setup              Bundled bootstrap launcher
plugins/kinglet-unity/**                             Complete immutable Codex plugin
packages/codex-project/install-manifest.json         Codex project bootstrap manifest
packages/codex-project/**                            Project-local Codex/Kinglet payload
packages/codex-project/profiles/frontier/**          Codex deep-role overlay
.agents/plugins/marketplace.json                     Repository marketplace entry
tools/kinglet_build/renderers/package_manifests.py   Manifest/plugin/marketplace renderer
scripts/lib/kinglet-common.sh                        Logging, arguments, portability
scripts/lib/kinglet-hash.sh                          Linux/macOS SHA and mode helpers
scripts/lib/kinglet-receipt.sh                       Receipt v1/v2 parsing and validation
scripts/lib/kinglet-managed-block.sh                 Safe marker parser/replacer
scripts/lib/kinglet-plan.sh                          Ownership classification
scripts/lib/kinglet-transaction.sh                   Stage/backup/commit/rollback
scripts/lib/kinglet-mcp.sh                           Explicit pinned package handling
scripts/lib/kinglet-agent-profile.sh                 Profile selection/capability probes/state
install.sh                                           Backward-compatible lifecycle CLI
uninstall.sh                                         Client-selective safe removal
scripts/studio-doctor.sh                             Kinglet/client/MCP/state diagnostics
tests/lifecycle/fixtures/**                          Synthetic Unity/client states
tests/lifecycle/test-packages.sh                     Product schema tests
tests/lifecycle/test-install.sh                      Fresh/dual installation tests
tests/lifecycle/test-legacy-migration.sh             v1 receipt/marker tests
tests/lifecycle/test-upgrade.sh                      Modified/pending/stale tests
tests/lifecycle/test-transaction.sh                  Failure/rollback tests
tests/lifecycle/test-uninstall.sh                    Selective removal tests
tests/lifecycle/test-doctor.sh                       Recovery diagnostic tests
```

## Task 1: Generate Complete Product and Install Manifests

**Files:**

- Create: `tools/kinglet_build/renderers/package_manifests.py`
- Create: `tests/kinglet/test_package_manifests.py`
- Create: `tests/lifecycle/test-packages.sh`
- Generate: `packages/claude/install-manifest.json`
- Generate: `packages/codex-project/install-manifest.json`
- Generate: `plugins/kinglet-unity/.codex-plugin/plugin.json`
- Generate: `.agents/plugins/marketplace.json`
- Modify: `tools/kinglet_build/renderers/__init__.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Write manifest-schema tests first**

Each install manifest contains schema version, product slug, toolkit version, client, `default_agent_profile: standard`, sorted base file rows, profile overlays, managed blocks, runtime prerequisites, host support, and canonical source IDs. Each file row contains `path`, `sha256`, `mode`, `origin`, and `canonical_ids`. A profile overlay contains `profile`, replaced destination rows, and hard native capabilities. Reject absolute paths, `..`, duplicates, missing generated files, hash mismatch, undeclared executable files, a manifest that includes itself in its file rows, any non-standard default, or an overlay outside the reserved `frontier` profile.

Claude base rows install standard agents beneath `.claude/` plus its project `CLAUDE.md` block; its frontier overlay replaces only the 14 deep-agent destinations. Codex base rows install standard `.codex/agents/`, `.kinglet/bin/`, shared project runtime, and its `AGENTS.md` block; its frontier overlay replaces only the 14 deep-agent destinations. A dual install may share identical runtime rows only when their manifest origin is `shared`; conflicting hashes for the same path are fatal. Manifests declare Fable and native Sol-Pro prerequisites but do not claim they are available.

- [ ] **Step 2: Render a valid Codex plugin manifest**

The plugin manifest uses ID `kinglet-unity`, display name `Kinglet for Unity`, description `Multi-agent toolkit for Unity 6`, version `3.0.0-dev.1`, and declares its skills/hooks/assets using paths within the plugin. It contains no project-absolute path and no MCP server bundle.

The repository marketplace has one entry for `kinglet-unity`, points to `plugins/kinglet-unity`, carries the same version/description, and orders Kinglet deterministically among any existing entries rather than replacing them.

- [ ] **Step 3: Build and validate product closure**

`tests/lifecycle/test-packages.sh` runs the manifest unit test, validates both generated install manifests with `jq -e`, checks every declared source hash/mode, and confirms the Codex plugin and marketplace versions match root `VERSION`.

```bash
python3 -m tools.kinglet_build build --all
python3 -m tools.kinglet_build build --all --check
python3 -m unittest tests.kinglet.test_package_manifests -v
bash tests/lifecycle/test-packages.sh
```

Expected: every generated product file is owned by one manifest and every manifest row resolves.

- [ ] **Step 4: Commit**

```bash
git add tools/kinglet_build packages plugins .agents/plugins tests/kinglet tests/lifecycle/test-packages.sh provenance.tsv
git commit -m "feat: generate Kinglet release manifests"
```

## Task 2: Extract Portable Lifecycle Libraries Without Behavior Change

**Files:**

- Create: `scripts/lib/kinglet-common.sh`
- Create: `scripts/lib/kinglet-hash.sh`
- Create: `scripts/lib/kinglet-receipt.sh`
- Create: `scripts/lib/kinglet-managed-block.sh`
- Create: `scripts/lib/kinglet-plan.sh`
- Create: `scripts/lib/kinglet-transaction.sh`
- Create: `scripts/lib/kinglet-mcp.sh`
- Create: `tests/lifecycle/test-libraries.sh`
- Modify: `install.sh`
- Modify: `uninstall.sh`
- Modify: `provenance.tsv`

- [ ] **Step 1: Characterize the current Claude lifecycle**

Before refactoring, add black-box fixtures for current fresh install, existing receipted upgrade, foreign `.claude`, modified installed file, managed CLAUDE.md, unmanaged CLAUDE.md, dry run, `--with-mcp`, safe uninstall, and modified-file preservation. Store only observable stdout classes, exit codes, target hashes, and ownership outcomes; do not golden terminal colors or timestamps.

- [ ] **Step 2: Define library contracts**

Libraries are source-only modules and never execute on import. Their public function prefixes are:

```text
kinglet_common_*       logging, usage, project validation, portable temp paths
kinglet_hash_*         sha256, file mode, constant-time hash comparison
kinglet_receipt_*      strict parse, validate, migrate, query, emit
kinglet_block_*        locate, validate, replace, remove managed blocks
kinglet_plan_*         classify create/replace/keep/remove/orphan/conflict
kinglet_tx_*           stage, backup, journal, commit, rollback, cleanup
kinglet_mcp_*          inspect/add pinned package and diagnose bridge contract
```

All functions return status and write data to an explicit file descriptor or output file. Avoid global variables except readonly library identity. Validate argument count before `shift`. Do not use process substitutions where a producer failure can be lost under `set -e`.

- [ ] **Step 3: Refactor while keeping legacy tests green**

At this task boundary, `install.sh` still installs Claude only and reads the root `.claude` mirror. Move code mechanically into libraries, use a portable SHA helper (`sha256sum` then `shasum -a 256`), and use portable mode detection (`stat -c` then `stat -f`).

Run:

```bash
bash tests/test-install.sh
bash tests/lifecycle/test-libraries.sh
bash -n install.sh uninstall.sh scripts/lib/*.sh
```

Expected: existing Claude outcomes are unchanged.

- [ ] **Step 4: Commit**

```bash
git add install.sh uninstall.sh scripts/lib tests/lifecycle provenance.tsv
git commit -m "refactor: extract Kinglet lifecycle engine"
```

## Task 3: Implement the Client-Neutral v2 Receipt and Legacy Migration

**Files:**

- Create: `tests/lifecycle/test-legacy-migration.sh`
- Create fixtures: `tests/lifecycle/fixtures/legacy-receipt/**`
- Modify: `scripts/lib/kinglet-receipt.sh`
- Modify: `scripts/lib/kinglet-transaction.sh`
- Modify: `install.sh`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test strict receipt v2 parsing**

The header and column order are exactly:

```text
canonical_id	client	path	installed_sha256	mode	origin	toolkit_version
```

Rows sort by `(client, path, canonical_id)`. Valid clients are `claude`, `codex`, and `shared`; modes are four octal digits; hashes are lowercase SHA-256; paths are project-relative and unique per client. Reject duplicate rows, traversal, absolute paths, unknown client/origin, malformed header, bad hash/mode/version, symlinked receipt, and a row that claims `.kinglet/state/install-receipt-v2.tsv` itself.

- [ ] **Step 2: Test all legacy migration cases before implementation**

Cover a valid `.claude/state/install-receipt.tsv`, malformed legacy receipt, source file whose hash changed, already migrated v2 receipt, both receipts present, interrupted prior migration, and legacy receipt received through Git without matching files.

A valid migration must:

1. make `.kinglet/backups/<UTC timestamp>/legacy-claude/`;
2. preserve the legacy receipt and every touched file snapshot;
3. translate recognized rows to canonical IDs through generated Claude install-manifest paths;
4. mark unrecognized valid rows as `legacy.unmapped.<sha-prefix>` with origin `legacy-preserved`;
5. record prior toolkit version in backup metadata;
6. write v2 only after its parse/ownership validation passes;
7. leave the old receipt in the backup and remove the live copy only at transaction commit.

- [ ] **Step 3: Implement migration as the first write transaction**

The installer detects v2 first. If only v1 exists, it plans migration before replacing any payload. Malformed or ambiguous receipts stop with an exact recovery instruction and no mutation. `--dry-run` reports `migrate-receipt` and planned backup but creates neither.

- [ ] **Step 4: Verify and commit**

```bash
bash tests/lifecycle/test-legacy-migration.sh
bash tests/test-install.sh
git add install.sh scripts/lib tests/lifecycle provenance.tsv
git commit -m "feat: migrate Kinglet install receipts to v2"
```

## Task 4: Implement Exact Managed-Block Ownership and Marker Migration

**Files:**

- Create: `tests/lifecycle/test-managed-blocks.sh`
- Create fixtures: `tests/lifecycle/fixtures/managed-blocks/**`
- Modify: `scripts/lib/kinglet-managed-block.sh`
- Modify: `scripts/lib/kinglet-plan.sh`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test byte preservation and malformed markers**

Recognize exactly:

```text
<!-- kinglet-unity:generated:begin -->
<!-- kinglet-unity:generated:end -->
<!-- cloud-nine-unity:generated:begin -->
<!-- cloud-nine-unity:generated:end -->
```

One matching old pair migrates to the new pair. Missing, duplicated, nested, reversed, mixed-brand, or unclosed markers are conflicts and stop that file update. Preserve BOM status, newline style outside the block, terminal newline status, and every outside byte. A file with no markers is foreign and receives `CLAUDE.md.kinglet-generated` or `AGENTS.md.kinglet-generated`; the user file is untouched.

- [ ] **Step 2: Implement managed-block planning and removal**

Managed blocks carry canonical ID `project-guidance.<client>`. Update changes only the block; uninstall removes only the exact current installed block when its receipt hash matches. If the user edited inside the block, preserve the file and report it as modified; do not attempt a three-way merge.

- [ ] **Step 3: Verify and commit**

```bash
bash tests/lifecycle/test-managed-blocks.sh
git add scripts/lib tests/lifecycle provenance.tsv
git commit -m "feat: preserve Kinglet managed project guidance"
```

## Task 5: Add Claude, Codex, and Dual-Client Installation

**Files:**

- Create: `tests/lifecycle/test-install.sh`
- Create fixtures: `tests/lifecycle/fixtures/install/**`
- Modify: `install.sh`
- Modify: `scripts/lib/kinglet-plan.sh`
- Modify: `scripts/lib/kinglet-transaction.sh`
- Modify: `scripts/lib/kinglet-mcp.sh`
- Create: `scripts/lib/kinglet-agent-profile.sh`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test the public CLI before changing it**

Supported invocations:

```bash
./install.sh --project-dir tests/lifecycle/fixtures/unity-project --client claude
./install.sh --project-dir tests/lifecycle/fixtures/unity-project --client codex
./install.sh --project-dir tests/lifecycle/fixtures/unity-project --client all
./install.sh --project-dir tests/lifecycle/fixtures/unity-project --client claude --agent-profile standard
./install.sh --project-dir tests/lifecycle/fixtures/unity-project --client all --agent-profile frontier
./install.sh --project-dir tests/lifecycle/fixtures/unity-project --with-mcp --yes
./install.sh --project-dir tests/lifecycle/fixtures/unity-project --client all --dry-run
```

Omitted `--client` equals Claude byte-for-byte. On a fresh or legacy target, omitted `--agent-profile` equals `standard` byte-for-byte. Reject an invalid profile and reject a frontier request whose client capability fixture is missing Fable, Sol, or native Pro. Validate project path/client/profile/manifest/prerequisites before transaction staging. Reject native Windows with a clear support-matrix message.

- [ ] **Step 2: Switch payload selection to generated manifests**

Claude reads `packages/claude/install-manifest.json`; Codex reads `packages/codex-project/install-manifest.json`; all merges them and deduplicates identical `shared` rows. Standard uses only base rows. Frontier overlays exactly the deep-agent destination rows after capability validation. Do not enumerate payload files with `find`. Verify every base/overlay source hash and mode against the manifest before planning target changes.

- [ ] **Step 3: Implement the deterministic Codex setup skill**

Generate `plugins/kinglet-unity/skills/setup/SKILL.md` so `$kinglet-unity:setup` invokes the bundled `bin/kinglet-setup` with the current project path and passes an explicit `--agent-profile` only when the user selected one. The launcher uses the same lifecycle libraries bundled in the plugin, defaults to client `codex`, and defaults fresh installs to standard. The skill states visible prerequisites: plugin installation, hook trust, MCP registration, and frontier capability access when requested. It never asks the model to recreate files from prose or to change the active-session model.

Source/archive `install.sh --client codex` produces the same project hashes and receipt rows as plugin setup. Test equivalence.

- [ ] **Step 4: Validate and record the selected agent profile**

Implement `kinglet-agent-profile.sh` with pure parse/validate helpers plus client-specific, read-only capability probes. The state payload is written transactionally to `.kinglet/state/agent-profile.json` and contains:

```json
{
  "schema_version": 1,
  "agent_profile": "frontier",
  "selected_explicitly": true,
  "clients": ["claude", "codex"],
  "adapter_digests": {
    "claude": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "codex": "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
  },
  "capabilities": {
    "claude": {"fable": {"status": "available", "source": "native-probe"}},
    "codex": {
      "sol": {"status": "available", "source": "native-probe"},
      "pro_mode": {"status": "available", "binding": "custom-agent-native", "source": "native-probe"}
    }
  },
  "resolved_models": {
    "claude": {"requested": "fable", "resolved": null, "visibility": "not-exposed"},
    "codex": {"requested": "gpt-5.6-sol", "resolved": "gpt-5.6-sol", "visibility": "native-probe"}
  }
}
```

Allow a Codex Pro binding only when a supported native machine-readable surface proves either a custom-agent-native binding or documented native inheritance; record the exact binding instead of assuming it. `reasoning effort=max`, a model name, environment guess, or prompt instruction is insufficient. If the installed client has no inspectable proof surface, return `frontier-unavailable` and make no write. For `--client all`, gather and validate all probe records before planning.

Existing profile state controls upgrades: omitted profile preserves `standard`; it preserves a previously explicit `frontier` only after revalidating every capability. A failed revalidation stops without downgrading. Switching either direction requires an explicit flag and must cover every already installed client; adding a client must use the recorded project profile. Missing/malformed/foreign state is a conflict, except a legacy install with no profile state migrates to standard. Unit fixtures cover every transition, reject mixed profiles, and prove no global Claude/Codex config changes.

- [ ] **Step 5: Handle MCP only with explicit consent**

`--with-mcp`:

- requires `Packages/manifest.json` and valid JSON;
- adds `com.coplaydev.unity-mcp` at the exact v10.1.0 Git URL if absent;
- leaves an existing identical value unchanged;
- stops on another value and prints the installed/required versions plus a manual migration instruction;
- stages the JSON edit and preserves key ordering/indentation as far as `jq` permits;
- records the changed manifest as a managed block-like receipt item only for the exact dependency entry, not ownership of the whole user file.

- [ ] **Step 6: Verify fresh and dual installs**

```bash
bash tests/lifecycle/test-install.sh
bash tests/test-install.sh
```

Expected: Claude compatibility, Codex bootstrap, standard default, qualified frontier overlays, fail-closed capability checks, all-mode deduplication, dry-run purity, no main-session/global model mutation, and pinned MCP handling pass.

- [ ] **Step 7: Commit**

```bash
git add install.sh scripts/lib plugins/kinglet-unity packages tests/lifecycle tests/kinglet provenance.tsv
git commit -m "feat: install Kinglet for Claude and Codex"
```

## Task 6: Implement Upgrade Planning, Pending Copies, Stale Removal, and Rollback

**Files:**

- Create: `tests/lifecycle/test-upgrade.sh`
- Create: `tests/lifecycle/test-transaction.sh`
- Create fixtures: `tests/lifecycle/fixtures/upgrade/**`
- Modify: `scripts/lib/kinglet-plan.sh`
- Modify: `scripts/lib/kinglet-transaction.sh`
- Modify: `install.sh`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test all six dry-run classifications**

Every destination is exactly one of `create`, `replace`, `keep`, `remove`, `orphan`, or `conflict`. Dry-run prints client, canonical ID, path, classification, and reason in stable path order. Assert target tree and filesystem metadata are unchanged after dry-run.

- [ ] **Step 2: Test modified and removed-file ownership**

- unchanged receipted file: replace atomically;
- modified receipted file: keep and write new bytes to `.kinglet/pending/3.0.0-dev.1/<client>/<path>`;
- foreign collision: conflict and do not write pending as if Kinglet owned it;
- removed unchanged item: remove;
- removed modified item: keep as orphan and retain receipt history with origin `user-modified-orphan`;
- previously pending identical version: replace only if its recorded pending hash still matches; otherwise create a conflict-suffixed pending copy and report both;
- omitted profile on standard upgrade: remain standard;
- omitted profile on an explicit frontier upgrade: revalidate and remain frontier, or stop without writes;
- explicit all-installed-clients profile switch: replace only the affected deep-role rows and update profile state in the same transaction;
- failed/changed capability probe: never downgrade frontier or leave state disagreeing with installed agent hashes.

Print an exact portable diff command for each pending file using quoted paths.

- [ ] **Step 3: Test transaction failure injection**

Inject failure after plan, staging, validation, backup, first managed-file swap, receipt write preparation, and commit journal write. After each, compare every target hash/mode/managed-block outside byte, then prove rerun succeeds. Backups live beneath `.kinglet/backups/<UTC timestamp>/`; staging lives beneath `.kinglet/staging/<transaction-id>/`; a journal identifies incomplete commits for doctor recovery.

- [ ] **Step 4: Implement plan/stage/validate/backup/commit**

Take an exclusive install transaction lock distinct from the Unity writer lease. Refuse concurrent install/uninstall. Stage complete destination bytes and v2 receipt, validate both, back up only touched paths, write an ordered journal, then rename. On failure, reverse committed journal entries and preserve the diagnostic backup. Never recursively delete an unresolved staging path.

- [ ] **Step 5: Verify and commit**

```bash
bash tests/lifecycle/test-upgrade.sh
bash tests/lifecycle/test-transaction.sh
git add install.sh scripts/lib tests/lifecycle provenance.tsv
git commit -m "feat: make Kinglet upgrades transactional"
```

## Task 7: Add Client-Selective Safe Uninstall

**Files:**

- Create: `tests/lifecycle/test-uninstall.sh`
- Create fixtures: `tests/lifecycle/fixtures/uninstall/**`
- Modify: `uninstall.sh`
- Modify: `scripts/lib/kinglet-plan.sh`
- Modify: `scripts/lib/kinglet-transaction.sh`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test exact ownership outcomes**

`uninstall.sh` accepts `--client claude`, `codex`, or `all`; omitted client remains `claude` for backward compatibility. Test fresh single clients, dual client, shared runtime, modified files, foreign extensions, removed files, pending files, backups, valid/edited managed blocks, missing/malformed receipt, and interrupted transaction recovery.

Removing one client:

- removes only its unchanged rows;
- retains shared rows while another installed client references them;
- keeps user-created `.agents/skills` and non-`kinglet-` `.codex/agents`;
- keeps modified rows and reports them;
- keeps `.kinglet/backups` and `.kinglet/pending`;
- updates v2 receipt atomically;
- removes that client from agent-profile state while preserving the other client's validated profile record; removing the last client removes unchanged generated profile state;
- does not unregister MCP or edit global Codex configuration.

- [ ] **Step 2: Preserve explicit purge semantics**

`--purge` may remove modified rows only after the complete plan is displayed and confirmation occurs, unless `--yes` was supplied. It never purges foreign paths, backups, pending copies, or user extensions. `--no-backup` and `--keep-local` retain their documented Claude behavior.

- [ ] **Step 3: Verify and commit**

```bash
bash tests/lifecycle/test-uninstall.sh
bash tests/test-install.sh
git add uninstall.sh scripts/lib tests/lifecycle provenance.tsv
git commit -m "feat: uninstall Kinglet clients safely"
```

## Task 8: Make Doctor Diagnose Clients, MCP, State, and Recovery

**Files:**

- Create: `tests/lifecycle/test-doctor.sh`
- Create fixtures: `tests/lifecycle/fixtures/doctor/**`
- Modify: `scripts/studio-doctor.sh`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test stable doctor result codes**

Doctor reports `ok`, `warn`, `error`, or `unsupported` for:

- Unity project/version and supported host;
- Kinglet version and generated-product hashes;
- Claude package/install/managed block/hook registration;
- Codex plugin visibility/project bootstrap/custom agents/hook trust;
- selected agent profile, explicit/default origin, adapter digests, installed deep-role hashes, requested/resolved models when exposed, and profile drift;
- Claude Fable access plus Codex Sol/native-Pro capability and binding when frontier is selected;
- v2 receipt validity and pending/orphan/conflict counts;
- MCP package tag/server version/bridge connectivity/tool digest/client registration;
- workflow selection owner/status;
- writer lease owner/expiry;
- EditorSnapshot freshness;
- interrupted lifecycle transaction.

Human output and `--json` output derive from the same result records. Exit `0` for all ok/warn, `1` for an error, and `2` for invalid invocation.

- [ ] **Step 2: Give exact, non-destructive recovery instructions**

Doctor may offer:

- rerun install for generated drift;
- install/enable the plugin or trust hooks through the native UI;
- register/start the pinned bridge through MCP for Unity;
- `kinglet-writer-lease clear-expired` only for an expired lease;
- resume or roll back an interrupted lifecycle transaction using its journal;
- compare a pending copy.

For an unavailable frontier capability, doctor prints `frontier-unavailable`, the failed native
check, and the exact command or native UI path for enabling/accessing it when the client exposes
one. If Codex exposes no supported custom-agent Pro binding, doctor says that frontier is not
currently activatable; it does not recommend `max` or prompt wording as substitutes. Standard
installations treat unavailable frontier-only capabilities as informational, not warnings.

It never steals an active lease, rewrites a receipt, trusts a hook, modifies global config, or runs recovery automatically.

- [ ] **Step 3: Verify and commit**

```bash
bash tests/lifecycle/test-doctor.sh
git add scripts/studio-doctor.sh tests/lifecycle provenance.tsv
git commit -m "feat: diagnose Kinglet lifecycle and bridge state"
```

## Task 9: Remove the Temporary Root `.claude/` Compatibility Mirror

**Files:**

- Delete: `.claude/**`
- Modify: `migration/baseline-inventory.json`
- Modify: `migration/content-inventory.json`
- Modify: `migration/role-workflow-inventory.json`
- Modify: `migration/hook-inventory.json`
- Create: `tests/kinglet/test_no_compatibility_mirror.py`
- Modify: `CLAUDE.md`
- Modify: `provenance.tsv`

- [ ] **Step 1: Prove no runtime/build/test reads the mirror**

Before deletion, rename root `.claude` in a temporary checkout and run build, package, install, upgrade, uninstall, hook, and doctor suites. Add a static test that rejects active code references to repository-root `.claude` except migration inventories/fixtures and historical documentation.

- [ ] **Step 2: Preserve migration evidence before deletion**

Mark each legacy inventory entry `migration_status: generated-and-retired` and record its canonical ID plus generated Claude/Codex paths. Keep historical hashes/provenance. Remove live `provenance.tsv` rows for deleted paths only after inventories preserve their origin.

- [ ] **Step 3: Delete only the generated compatibility tree**

Remove tracked root `.claude/`. Do not remove `packages/claude/.claude/`, user-project fixtures, migration fixtures, or contributor `CLAUDE.md`. Update contributor guidance to build/install from canonical source and generated packages.

- [ ] **Step 4: Run the complete lifecycle gate**

```bash
python3 -m tools.kinglet_build build --all --check
bash tests/lifecycle/test-packages.sh
bash tests/lifecycle/test-install.sh
bash tests/lifecycle/test-legacy-migration.sh
bash tests/lifecycle/test-upgrade.sh
bash tests/lifecycle/test-transaction.sh
bash tests/lifecycle/test-uninstall.sh
bash tests/lifecycle/test-doctor.sh
bash tests/run-tests.sh
bash scripts/check-provenance.sh
```

Expected: every test passes without a repository-root `.claude` source.

- [ ] **Step 5: Commit**

```bash
git add -A .claude migration CLAUDE.md tests/kinglet provenance.tsv
git commit -m "refactor: retire Kinglet Claude compatibility mirror"
```

## Plan 05 Completion Gate

Plan 06 may start only when:

- package/plugin/marketplace manifests validate and `--check` is clean;
- default install still produces the supported Claude surface;
- fresh/legacy installs select standard, explicit frontier is capability-gated for each selected client, and neither lifecycle path changes the main-session model;
- plugin setup and source installer produce identical Codex bootstrap hashes;
- fresh, legacy, upgrade, failure-injection, rollback, and selective-uninstall fixtures pass;
- modified and foreign user files are never overwritten or silently deleted;
- dual-client receipt/shared-runtime ownership is correct;
- doctor reports exact profile/capability recovery without making hidden changes or silent model fallback;
- repository-root `.claude/` no longer exists and no active code reads it.
