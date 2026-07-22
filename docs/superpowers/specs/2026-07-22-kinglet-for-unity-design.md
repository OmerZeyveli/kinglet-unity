# Kinglet for Unity — Canonical Core and Dual-Client Design

**Status:** Approved design, pending written-spec review

**Date:** 2026-07-22

## Summary

Kinglet is a multi-agent toolkit for Unity 6 projects targeting PC and console. It will provide
Claude Code and Codex with the same supported workflows, safety rules, Unity MCP discipline,
verification requirements, and user-facing outcomes without forcing the two clients into the same
file format.

Human-maintained content will move into a platform-neutral canonical core. Deterministic adapters
will render a Claude distribution and a native Codex plugin plus project bootstrap. A normalized
capability manifest and parity suite will block releases whenever a supported workflow is missing,
weaker, or unverifiable on either client.

The migration is incremental. The existing Claude product remains usable after every slice, and no
legacy source category is removed until its generated Claude output and Codex counterpart pass
parity and golden tests.

## Product Identity

- Product brand: **Kinglet**
- Display name: **Kinglet for Unity**
- Repository slug: `kinglet-unity`
- Codex plugin ID: `kinglet-unity`
- Codex skill namespace: `$kinglet-unity:<skill-name>`
- Tagline: **Multi-agent toolkit for Unity 6**

The word “Unity” is descriptive, not presented as the owner of the product. Documentation will use
“Kinglet for Unity” or “Kinglet, a multi-agent toolkit for Unity 6” rather than “Unity Kinglet.” The
README and distributed notices will include Unity’s required trademark attribution.

Existing Claude command names such as `/unity-feature` remain stable. Canonical IDs also remain
brand-neutral, such as `workflow.unity-feature`, so a future product rename does not invalidate
cross-references or receipts.

During migration, installers recognize both the old
`cloud-nine-unity:generated:{begin,end}` markers and the new
`kinglet-unity:generated:{begin,end}` markers. A successful managed-block update rewrites the old
marker pair to the new pair. Historical attribution in `MERGE-NOTES.md`, `CREDITS.md`, and upstream
provenance is preserved rather than rewritten as if Kinglet had always been the project name.

## Goals

1. Preserve or improve the current Claude Code behavior and safety contract.
2. Give Codex every supported Kinglet capability at the same acceptance quality.
3. Maintain one human-authored source for shared roles, workflows, knowledge, rules, hook policies,
   templates, provenance, and Unity MCP usage.
4. Keep client-native UX: Claude slash commands and agent Markdown; Codex plugin skills, custom
   agent TOML, `AGENTS.md`, and plugin hooks.
5. Prevent generated-output drift and silent platform omissions in CI.
6. Preserve user-authored files and edits across install, upgrade, rollback, and uninstall.
7. Use one pinned CoplayDev MCP for Unity bridge and one shared orchestration contract.

## Non-Goals

- Kinglet will not implement or fork its own Unity MCP server.
- Claude and Codex output files will not be byte-identical to each other.
- Model prose is not expected to be deterministic or textually identical across clients.
- Canonical content will not contain current Claude or OpenAI model names.
- Mobile guidance remains excluded. Unity 6 PC/console is the product target.
- Simultaneous Unity mutations from multiple agents or clients are not supported.
- Native Windows host support is not part of the first canonical-core migration. The first Kinglet
  release preserves the current Linux and macOS host contract; Windows is explicitly reported as
  unsupported until it has a native installer, hook runner, and release matrix.

## Architecture

The repository has four layers:

```text
src/                              Human-authored canonical source
adapters/                         Client-specific mappings and renderers
packages/claude/                  Generated Claude distribution
plugins/kinglet-unity/            Generated Codex plugin
packages/codex-project/           Generated Codex project bootstrap
.agents/plugins/marketplace.json  Generated repo marketplace entry
```

Repository-level `AGENTS.md` and `CLAUDE.md` describe how contributors maintain Kinglet. They are
not end-user payloads. End-user project guidance is generated under `packages/` and installed into a
target Unity project.

Generated output is committed so users can install a release without Python or a generator. CI
rebuilds into a temporary directory and requires byte-identical output. Generated files are never
the source for a later build and are not edited by hand.

### Canonical source layout

```text
src/
  catalog/
    capabilities.json
    support-policy.json
  roles/<slug>/
    role.json
    instructions.md
  workflows/<slug>/
    workflow.json
    instructions.md
    references/
  knowledge/<slug>/
    knowledge.json
    SKILL.md
    references/
    scripts/
  rules/<slug>/
    rule.json
    instructions.md
  hooks/<slug>/
    hook.json
    policy.sh
  templates/<slug>/
    template.json
    content.md
```

JSON holds strict machine metadata. Markdown and shell hold long-form content that humans need to
review. YAML is not used for canonical metadata because it would add a parser dependency. The
generator validates JSON with explicit Python types and rejects unknown fields.

Each file has one responsibility. A descriptor identifies and connects a unit; its Markdown defines
behavior; references and scripts belong to that unit rather than a global miscellaneous directory.

### Canonical identity and references

IDs are namespaced by kind:

- `role.unity-reviewer`
- `workflow.unity-feature`
- `knowledge.serialization`
- `rule.pc-console`
- `hook.block-dangerous-command`
- `template.edit-mode-test`

Descriptors reference these IDs rather than paths. Paths may be reorganized without changing the
public identity. Duplicate IDs, unresolved references, reference cycles where cycles are forbidden,
and two units claiming the same generated path are fatal build errors.

### Workflow descriptor

A workflow descriptor declares:

- stable ID, public name, summary, and schema version;
- ordered stages drawn from `investigate`, `clarify`, `design`, `plan`, `implement`, `verify`, and
  `report`;
- participating role IDs;
- required rules and knowledge IDs;
- required logical capabilities;
- inputs, artifacts, completion evidence, and failure behavior;
- provenance;
- support state for Claude and Codex.

Support state is one of `supported`, `unsupported`, or `exception`. `exception` requires a visible
reason, an owner, and a named test that proves the stated reduced behavior. An absent platform entry
is invalid; it never means implicit support.

### Logical capabilities

Canonical roles and workflows use logical capabilities rather than native tool names:

- `filesystem.read`
- `filesystem.write`
- `shell`
- `delegate`
- `unity.read`
- `unity.write`
- `web`

Verification requirements are declared separately as evidence such as `console-clean`,
`unity-tests-pass`, `scene-state-readback`, `screenshot-reviewed`, and `references-valid`. This
prevents a role’s broad tool permission from being mistaken for proof that verification happened.

Canonical reasoning tiers are `fast`, `balanced`, and `deep`. Adapter profiles map tiers to native
client configuration. Current model names live only in the adapter profile and may be updated
without editing canonical roles.

## Adapters and Generated Products

Both adapters consume the same validated in-memory canonical graph. Neither adapter parses the
other client’s generated files.

### Claude adapter

The Claude adapter produces:

- `.claude/agents/*.md` with native frontmatter, model tier mapping, and allowed tools;
- `.claude/commands/*.md` with existing `/unity-*` public names;
- `.claude/skills/**/SKILL.md`;
- `.claude/rules/*.md`;
- `.claude/hooks/` and `.claude/settings.json`;
- `.claude/templates/`, notices, version, and installed provenance;
- the managed project-facts block used in end-user `CLAUDE.md`.

The generated Claude package must initially match the current distribution’s supported behavior.
Intentional improvements, including the new MCP snapshot flow, get explicit golden updates and
parity scenarios rather than being hidden inside migration noise.

### Codex adapter

The Codex adapter produces two artifacts.

The installable plugin at `plugins/kinglet-unity/` contains:

- `.codex-plugin/plugin.json`;
- namespaced workflow skills under `skills/`;
- shared hook dispatcher assets under `hooks/`;
- notices, version, and presentation assets.

The project bootstrap at `packages/codex-project/` contains:

- a managed root `AGENTS.md` block for binding project rules;
- `.codex/agents/kinglet-*.toml` custom roles;
- bootstrap and doctor scripts;
- project-local ignore entries and receipt metadata.

Custom agent TOML is project bootstrap content because Codex plugins do not use the plugin manifest
to install project `.codex/agents`. Plugin cache content remains immutable and separate from user
project files.

The plugin does not bundle a second Unity MCP server. It documents the logical dependency and
verifies the configured CoplayDev bridge. Client registration remains the responsibility of MCP for
Unity’s “Configure All Detected Clients” flow.

### Capability manifest and parity

Each adapter emits a normalized capability manifest in addition to native files. For every workflow
it records:

- ordered stages;
- roles and reasoning tiers;
- capabilities granted per role;
- binding rules and hook policies;
- Unity MCP preconditions;
- required verification evidence;
- user-facing artifacts;
- declared platform exception, if any.

Parity compares these manifests, not unrelated native syntax. A `supported` workflow may not differ
on stages, safety blocks, MCP discipline, evidence, or required artifacts. Presentation-only
differences such as `/unity-feature` versus `$kinglet-unity:unity-feature` are allowed.

## Unity MCP Architecture

Kinglet uses one pinned, tested CoplayDev MCP for Unity release. A moving `#main` reference is
forbidden. Claude and Codex use the same server implementation, tool contract, and Unity package.

One bridge does not mean every agent receives every MCP tool. Connection availability and role
authorization are separate concerns.

### Shared orchestration sequence

Every MCP-backed workflow follows this order:

1. Confirm bridge availability, Unity version, editor state, compilation state, play mode, and
   active scene.
2. Capture or refresh a task-scoped `EditorSnapshot`.
3. Select a role and grant the minimum live capability needed for the next stage.
4. Acquire the single-writer lease before any Unity mutation.
5. Perform the action.
6. Invalidate the previous snapshot after a successful or uncertain mutation.
7. Capture fresh console, test, scene-state, and screenshot evidence required by the workflow.
8. Release the writer lease and report evidence and remaining risk.

### EditorSnapshot

Runtime state lives at `.kinglet/state/editor-snapshot.json` and is ignored by version control. The
snapshot schema contains:

- snapshot schema version and capture time;
- Unity version, active build target, and render pipeline;
- compilation and play-mode state;
- active scene path, dirty flag, hierarchy digest, and task-relevant object summary;
- package-manifest digest and relevant installed packages;
- console error/warning counts and digest;
- current selection when relevant;
- the workflow and MCP bridge version that produced it.

The orchestrator passes only the task-relevant subset to an agent. The snapshot is invalid after any
write, scene load, compilation transition, play-mode transition, or detected digest change.

### Agent capability model

| Role class | Default Unity context | Live MCP access | Write policy |
| --- | --- | --- | --- |
| Orchestrator | Full task snapshot | `unity.read` | Manages leases; delegates mutations |
| Scout/reviewer | Snapshot plus live state | `unity.read` | No scene or asset mutation |
| Design/production | Relevant snapshot | Temporary `unity.read` only when the snapshot cannot answer the task | No C# or Unity mutation |
| Implementer/builder | Fresh snapshot | `unity.read`, scoped `unity.write` | Requires active single-writer lease |
| Verifier/test runner | Fresh post-write state | Read, tests, console, capture | No arbitrary production mutation |
| Documentation/research | Supplied context | None by default | No mutation |

This hybrid model avoids two failure modes: isolating design roles from the real project and giving
every role a noisy, dangerous, and expensive tool surface.

### Single-writer lease

The project-local lease is `.kinglet/state/unity-write-lease.json`. It contains a random lease ID,
client, workflow ID, acquisition time, and expiry time. Creation is atomic. A writer renews the lease
after each MCP mutation and releases it at workflow completion.

The default lease duration is 15 minutes. Another agent or client may read Unity while a lease is
active but may not mutate it. Only an expired lease can be cleared automatically. `kinglet doctor`
reports the owner and provides an explicit recovery command for an expired lease; it never steals an
active lease.

## Hook Policy Architecture

Canonical hook policies do not know Claude or Codex event JSON. Each client has a thin normalizer
that converts its native event to:

```text
event, tool, path, command, cwd, client, session, workflow
```

A single ordered dispatcher evaluates policies and returns `allow`, `warn`, or `block` plus a stable
policy ID and explanation. Native adapters translate that decision into the client’s expected hook
response.

Policy ordering is explicit. Blocking safety policies run before advisory policies, and hooks do not
race in parallel. The same normalized fixture suite is sent through both native normalizers and must
produce the same ordered decisions.

## Deterministic Generator

The build tool is a Python standard-library-only package under `tools/kinglet_build/`. Python is a
maintainer dependency, not an end-user install dependency.

The build pipeline is:

1. Load UTF-8 JSON and Markdown in a stable path order.
2. Validate descriptor fields and reject unknown keys.
3. Resolve a typed canonical graph.
4. Validate references, output ownership, provenance, support state, and capability mappings.
5. Render Claude, Codex plugin, Codex project bootstrap, marketplace, and normalized manifests into
   a staging directory.
6. Normalize line endings to LF, sort map-derived output, and omit timestamps, absolute paths,
   locale-dependent values, and host-specific values.
7. Atomically replace the requested output directory or compare staging with committed output in
   `--check` mode.

The public maintainer commands are:

```bash
python3 -m tools.kinglet_build validate
python3 -m tools.kinglet_build build --all
python3 -m tools.kinglet_build build --all --check
```

Build errors include source path, canonical ID, and field path. Examples include an unmapped
`unity.write` capability, an unknown descriptor key, a missing role reference, or two outputs
claiming the same destination. Missing adapter mappings are fatal; there is no silent fallback.

## Provenance

Canonical descriptors retain origin, upstream version, upstream path, original checksum, adaptation
status, and a human explanation. Moving upstream-derived prose into canonical Markdown does not
erase its origin.

The root `provenance.tsv` remains the repository-wide audit index. Generated outputs add the
canonical IDs that produced them, while canonical sources retain upstream evidence. The checker
continues enforcing both directions: no tracked payload/source without a row, no row without a
file, unchanged upstream-verbatim checksums, and absence rules in `provenance-skip.tsv`.

## Installation, Upgrades, and User Ownership

### Installation surfaces

Claude users keep the existing entry point. Omitting `--client` is equivalent to `--client claude`
for backward compatibility:

```bash
./install.sh --project-dir /path/to/UnityProject
./install.sh --project-dir /path/to/UnityProject --client claude
```

Codex users install `kinglet-unity` from the repository marketplace and run
`$kinglet-unity:setup` inside the Unity project. The setup skill invokes the deterministic bundled
bootstrap; it does not ask the model to recreate configuration from prose.

Source and release-archive users may also bootstrap explicitly:

```bash
./install.sh --project-dir /path/to/UnityProject --client codex
./install.sh --project-dir /path/to/UnityProject --client all
```

The Codex bootstrap does not silently modify global `~/.codex/config.toml`. Plugin installation,
plugin hook trust, and Unity MCP client registration remain visible user actions. The doctor reports
each missing action with the exact recovery instruction.

### Client-neutral receipt

Both clients use `.kinglet/state/install-receipt-v2.tsv`. Each row records:

```text
canonical_id, client, path, installed_sha256, mode, origin, toolkit_version
```

The installer migrates a valid legacy `.claude/state/install-receipt.tsv` before replacing any
managed file. It preserves a snapshot under `.kinglet/backups/<timestamp>/` and records the legacy
toolkit version.

### Ownership classes

1. **Immutable package:** committed Claude package and installed Codex plugin cache. Users replace a
   version; they do not merge into it.
2. **Managed project surface:** receipted payload files, managed `CLAUDE.md`/`AGENTS.md` blocks, and
   `kinglet-*` custom agent files.
3. **User-owned extension:** text outside managed markers, user-created `.agents/skills`, custom
   `.codex/agents` without the reserved `kinglet-` prefix, local settings, and files absent from the
   receipt.

### Upgrade decisions

- A receipted file whose hash still matches is atomically replaced.
- A user-modified receipted file stays in place. The new version is written under
  `.kinglet/pending/<version>/<client>/<path>`, and the upgrade prints a diff command.
- A foreign path collision is not overwritten. That target is reported as a conflict.
- A valid managed block is replaced without changing bytes outside the markers.
- Missing, duplicated, nested, or reversed markers stop that file’s update and produce an error.
- A canonical item removed from a release is deleted only when its installed hash still matches.
  A modified removed item remains as a reported orphan.
- `--dry-run` classifies every destination as `create`, `replace`, `keep`, `remove`, `orphan`, or
  `conflict` and writes nothing.

Installation stages all writes before changing managed destinations. A failed build, validation, or
copy does not leave a half-installed client surface.

Uninstall accepts `--client claude`, `--client codex`, or `--client all`. It removes only matching,
unchanged receipt rows. Removing one client leaves the other client, user extensions, shared
project prose, backups, and pending conflict files intact.

## Validation and Testing

Validation has four automated layers.

### Schema tests

These cover valid descriptors, every required field, enum boundaries, unknown keys, malformed IDs,
invalid support exceptions, path traversal, invalid UTF-8, and malformed provenance.

### Graph and renderer tests

These cover duplicate IDs, unresolved references, forbidden cycles, output collisions, capability
mapping, reasoning-tier mapping, stable ordering, line endings, deterministic rebuilds, and
client-native manifest validity.

### Golden and parity tests

Golden fixtures protect intended native output. Normalized manifests prove that every `supported`
workflow has equivalent stages, capabilities, safety policies, MCP discipline, verification
evidence, and artifacts on Claude and Codex.

The first migration baseline includes the current inventory: 28 agents, 36 commands, 39 skills, 26
executable hooks excluding `_lib.sh`, 6 rules, and 5 Markdown templates. Counts are not permanent
requirements; the catalog, rather than a hard-coded number, defines expected output.

### Lifecycle integration tests

Synthetic Unity fixtures cover:

- fresh Claude, Codex, and dual-client installs;
- legacy receipt migration;
- dirty managed files and foreign collisions;
- valid and malformed managed blocks;
- stale item removal and modified orphan preservation;
- interrupted staging;
- rollback and client-selective uninstall;
- MCP missing, wrong version, stopped bridge, and expired writer lease;
- Linux and macOS shell behavior.

### Live Unity release scenarios

Before release, the same seeded Unity 6 project runs representative scenarios in both clients:

1. read-only project audit;
2. scoped feature implementation;
3. bug investigation and fix;
4. design workflow using `EditorSnapshot`;
5. destructive-action block;
6. post-write scene, console, test, and screenshot verification.

The clients need not produce identical prose or code. Both must satisfy the same observable contract:
required stages occurred, scope and safety boundaries held, Unity tests passed, console evidence is
clean, scene state was read back, required screenshots were reviewed, and the final report lists
evidence and remaining risk.

## Release Contract

One root version drives the Claude package, Codex plugin, project bootstrap, receipt, marketplace,
and release tag. Dependencies use tested tags or immutable commits; `#main` is forbidden for the MCP
bridge and other runtime dependencies.

A release is blocked when:

- generated output is stale;
- provenance fails;
- a `supported` capability is missing from either client;
- parity manifests differ on behavior, safety, MCP, evidence, or artifacts;
- install, upgrade, rollback, or uninstall loses a user fixture;
- the hook decision suite differs between clients;
- a required live Unity scenario fails on either client.

Every release publishes a capability matrix. A platform-specific exception is visible in that
matrix with its reason and test evidence. Kinglet never reports silent partial support as parity.

## Incremental Migration

The migration is divided into independently reviewable projects:

1. **Identity and foundation:** Kinglet naming, canonical schema, typed loader, generator shell,
   output ownership, deterministic check, and baseline inventory.
2. **Rules, templates, and knowledge:** migrate the lowest-coupled content and produce both client
   outputs with parity.
3. **Roles and workflows:** migrate all 28 roles and 36 workflows, add adapter tier/tool mappings,
   and implement the hybrid `EditorSnapshot` capability model.
4. **Hooks and Unity MCP orchestration:** add native normalizers, ordered policy dispatcher, pinned
   bridge contract, verification evidence, and single-writer lease.
5. **Packages and lifecycle:** switch installers to generated packages, add Codex marketplace/setup,
   receipt-v2 migration, pending updates, rollback, and selective uninstall.
6. **Product and release:** rewrite user documentation for both clients, add doctor output,
   capability matrix, live Unity parity report, and release artifacts.

Each project keeps the previous Claude package installable. A category’s legacy `.claude/` source
is removed only in the same change that makes its canonical source authoritative and proves the
generated Claude and Codex outputs. The final cutover changes `install.sh` to consume only generated
packages and deletes the last legacy payload source.

Because these projects have independent review and test boundaries, implementation planning will
use one detailed plan per project rather than one unreviewable big-bang checklist.

## Success Criteria

The design is complete when implementation can demonstrate all of the following:

- Existing Claude workflows retain their supported behavior or have an explicitly reviewed
  improvement.
- Every catalog item marked `supported` passes normalized parity on Claude and Codex.
- Both clients use the same pinned Unity MCP bridge and orchestration contract.
- Design agents receive real project context without broad write access.
- Only one agent or client can mutate Unity at a time.
- Generated outputs rebuild byte-identically and CI rejects manual drift.
- Dirty install, upgrade, rollback, and uninstall fixtures lose no user-authored bytes.
- Live Unity release scenarios pass on both clients within the documented host matrix.
- Documentation calls the product Kinglet for Unity, uses `kinglet-unity` technical identifiers,
  preserves upstream credit, and makes unsupported surfaces explicit.
