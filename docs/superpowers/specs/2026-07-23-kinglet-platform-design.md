# Kinglet for Unity — Multi-Client Platform Design

**Status:** Approved design; written-spec review requested

**Date:** 2026-07-23

**Supersedes:** `2026-07-22-kinglet-for-unity-design.md` and its six implementation plans

## Decision

Kinglet will become a standalone, client-neutral Unity development product rather than a Claude
payload with a second client added beside it. It will maintain one canonical behavioral core and
project model, then project those capabilities into the native extension surfaces of Claude Code,
Codex, Cursor, GitHub Copilot CLI and VS Code, and Antigravity.

End users install a native client plugin or a signed standalone Kinglet distribution. They do not
clone the Kinglet source repository. Plugin installation makes Kinglet discoverable but does not
silently alter a Unity project. The user starts project initialization by asking the agent to run
Kinglet setup. Setup detects whether the project is new, already initialized, migrating from
another system, adding another client, upgrading, or repairing an installation.

Kinglet works without Unity MCP. When the CoplayDev Unity MCP bridge is available, Kinglet uses its
additional live-Editor capabilities and reports them honestly. Filesystem, live Editor, same-project
headless, and isolated headless execution are routes behind one execution broker, not separate
products.

Superpowers is both:

1. an optional installed process provider that can supply general development methodology at
   runtime; and
2. an upstream research source from which suitable ideas, tests, or content may be adapted into
   Kinglet with provenance.

Kinglet never requires Superpowers at runtime. The ignored `.research/` clones of Superpowers,
Everything Claude Unity (ECU), Claude Code Game Studios (CCGS), and Unity MCP are maintainer
references only. They are not release inputs, runtime dependencies, or vendored product content.

## Planning transition

This design replaces the architecture and delivery assumptions in the 2026-07-22 design. In
particular, native Windows support is now a first-class requirement, the client scope is broader
than Claude and Codex, end-user source cloning is no longer the primary distribution path, and
Unity execution is no longer MCP-only.

The six existing 2026-07-22 implementation plans are frozen and must not be executed, including
Plan 2. After this document passes written review, a new suite of independently gated specs and
implementation plans will replace them. The old files remain temporarily as historical records so
that prior reasoning is not destroyed during replanning.

## Product identity and scope

- Product brand: **Kinglet**
- Display name: **Kinglet for Unity**
- Repository slug: `kinglet-unity`
- Product type: standalone multi-client Unity development system
- Current Unity focus: Unity 6, PC and console
- Primary interaction: ordinary natural-language requests
- Deterministic interaction: namespaced native commands/skills and the Kinglet CLI

Kinglet is not a wrapper around one agent client and is not a fork of Unity MCP or Superpowers.
Client names, current model names, native command syntax, and tool identifiers do not appear in
shared behavioral bodies. The word “Unity” is descriptive; public documentation and packages must
follow Unity trademark requirements.

Mobile guidance remains outside the current product scope. Adding mobile later would be a separate
product decision with its own rules, tests, and support matrix rather than a silent relaxation of
the PC/console contract.

## Goals

1. Give supported clients the same observable Kinglet workflows, policies, artifacts, and
   verification requirements through their native extension mechanisms.
2. Preserve one human-maintained source for shared skills, roles, rules, semantic actions, Unity
   guidance, templates, routing, and evidence contracts.
3. Initialize a Unity project once and allow clients to be added idempotently without duplicating
   shared project state.
4. Adopt existing user and third-party agent systems without destroying, disabling, or silently
   replacing them.
5. Work natively on Windows 10/11 without WSL or Git Bash, while also supporting macOS and Linux.
6. Use the most capable safe Unity route available for each task and provide structured evidence
   regardless of whether the route is MCP or headless.
7. Make installation, upgrade, rollback, repair, and uninstall transactional and ownership-aware.
8. Verify behavior in real clients and real Unity projects rather than treating generated file
   presence as proof of support.
9. Keep upstream use legally and technically traceable from source material through releases.

## Non-goals

- Kinglet will not implement or fork its own Unity MCP server.
- Kinglet will not require Unity MCP for filesystem-only or supported headless workflows.
- Kinglet will not require Superpowers or any other external process provider.
- Kinglet will not force Claude, Codex, Cursor, Copilot, and Antigravity into identical native file
  formats.
- Kinglet will not claim feature parity where a client lacks the necessary native capability.
- Kinglet will not automatically upload prompts, project content, code, paths, or diagnostics.
- Kinglet will not silently close a running Unity Editor, upgrade a project with another Unity
  version, weaken a client’s approval policy, or uninstall another system.
- Visual Studio and Rider integrations are not first-class targets in this design. They may receive
  capability-limited adapters later when their native extension surfaces can be evaluated.

## System architecture

Kinglet is divided into seven subsystems with explicit contracts.

### 1. Canonical Content Core

The canonical core owns platform-neutral behavioral content and typed metadata:

- skills and their activation boundaries;
- stable roles and capability requirements;
- rules and safety invariants;
- semantic actions and workflow stages;
- routing examples and negative boundaries;
- Unity knowledge, templates, and expected artifacts;
- completion evidence and failure behavior;
- source provenance and license metadata.

Long-form behavior is written in reviewable Markdown. Typed manifests and catalogs describe
identity, dependencies, capabilities, schemas, ownership, rendering requirements, and tests. A
descriptor identifies and connects a unit; its Markdown explains behavior. Client-native syntax
does not leak into shared content.

Canonical identities are stable and namespaced, such as:

- `kinglet.role.unity-reviewer`
- `kinglet.skill.verify-playmode`
- `kinglet.rule.protect-scene-yaml`
- `kinglet.action.project-doctor`

References use these identities instead of filesystem paths. Duplicate identities, unresolved
references, forbidden cycles, output collisions, missing provenance, and unsupported required
capabilities are build errors.

Kinglet favors a small set of stable roles and many composable skills. An adapter may render native
subagents when the client supports them, but the canonical workflow does not depend on a client
having a particular “agent” primitive. Model selection is expressed through capabilities such as
fast, deep-reasoning, long-context, and multimodal rather than current commercial model names.
Concrete model mappings belong to tested adapter profiles. Existing public agent, command, and
workflow names are retained as documented migration aliases where they still represent supported
behavior; an alias routes to a canonical identity and is not a second source of instructions.

### 2. Client Adapter and Plugin System

Each adapter consumes the same validated canonical graph and generates or exposes native client
artifacts. An adapter does not parse another adapter’s output.

First-class targets are:

- Claude Code
- Codex
- Cursor
- GitHub Copilot CLI
- GitHub Copilot in VS Code
- Antigravity

Copilot CLI and VS Code may share compatible package material, but they remain separately tested
surfaces. Shared formats do not imply identical lifecycle, discovery, permissions, or behavior.
Claude, Copilot CLI, and VS Code may also reuse portions of a compatible plugin layout, but each
receives a separately packaged adapter overlay and independent lifecycle and behavior results.

The adapter contract covers:

- plugin/package manifest and installation;
- bootstrap and project binding;
- skills, rules, roles, commands, and routing;
- hooks and policy enforcement;
- MCP configuration and discovery;
- local executable invocation;
- approval semantics;
- upgrade and uninstall lifecycle;
- native Windows behavior;
- normalized capability and evidence reporting.

Every feature is graded per client as:

- **Native:** the client directly supports the required primitive and behavior.
- **Emulated:** Kinglet can provide equivalent observable behavior through another declared
  mechanism.
- **Unavailable:** required behavior cannot be delivered safely or honestly.

An emulation must have behavior tests. An unavailable capability must be visible in setup, doctor,
documentation, and the published support matrix. A missing declaration is invalid; it never means
implicit support. The client’s own stricter permission or approval requirement always wins.

### 3. Setup and Migration Engine

One setup entry point automatically classifies the requested operation:

- fresh project initialization;
- add-client;
- migration/adoption;
- upgrade;
- repair;
- dry run.

Every mutating setup flow follows:

1. read-only discovery;
2. proposed change set;
3. user approval;
4. complete local backup of affected surfaces;
5. staging;
6. validation;
7. atomic application where the target permits it;
8. transaction receipt;
9. doctor verification;
10. rollback availability.

Discovery scans common project and user-defined surfaces, including ECU, CCGS, Superpowers,
`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, Cursor rules, Copilot instructions, agent definitions,
skills, hooks, MCP configuration, and durable design or production documents. Detection alone never
authorizes modification.

Setup distinguishes:

- **Kinglet-managed:** generated or installed by Kinglet and checksum-owned.
- **User-owned:** authored by the user and never silently replaced.
- **Adopted:** imported into Kinglet’s project layer while retaining origin and change history.
- **Foreign-managed:** owned by another product or plugin.
- **Local-sensitive:** credentials, machine paths, caches, logs, and process state.

Setup never deletes, disables, or uninstalls a foreign plugin or user system without an explicit
targeted approval. A modified managed file is not overwritten: setup shows the conflict and offers
adopt, keep, replace from backup, or merge. Global plugins remain global; Kinglet does not copy
their internals into the project.

Plugin installation is client-scoped; project initialization is project-scoped. Moving from Codex
to Claude, for example, requires installing the Claude plugin once and asking Kinglet to set up the
already initialized project. Discovery classifies that request as `add-client`, reuses shared
project state and the pinned core, and does not repeat a fresh migration.

Durable GDDs, ADRs, plans, decisions, QA records, and similar project knowledge live in a common
Git-tracked `docs/` tree by default, independent of the active agent client. Client-specific
directories are projection and integration surfaces, not the canonical home of project knowledge.

### 4. Unity Execution Layer

One execution broker selects among four routes:

1. **Filesystem-only:** source, documentation, configuration, and asset-side operations that do not
   require a running Unity process.
2. **Live Editor + MCP:** scene, prefab, PlayMode, inspector, console, visual, and other
   Editor-state-dependent operations.
3. **Same-project headless:** compile, tests, or builds when no GUI Editor owns that project path.
4. **Isolated headless:** a separate copy or worktree with separate Unity-generated state.

The default mode is `auto`; an expert or CI system can request a specific route. With a compatible
Editor and bridge ready, MCP is preferred for live-state work and for tests it can reliably
execute. With the Editor closed, headless is preferred for deterministic compile, test, and build
work. The same physical Unity project path must never be opened simultaneously by the GUI Editor
and batchmode.

When a Unity-dependent task is approved, Kinglet may locate the exact Unity version from project
metadata, resolve an installed matching Editor, launch it, wait through import and compilation, and
establish MCP readiness. Kinglet never silently launches the wrong Unity version, upgrades the
project, closes the user’s Editor, or assumes that a running MCP server implies a connected Editor.

Isolated headless execution cannot see unsaved live-Editor state. Kinglet explains this boundary and
does not silently save scenes to bridge it. If saving is appropriate, that is a separate visible
Unity mutation requiring approval.

All routes return one structured evidence contract containing the backend, project identity and
path, Unity version, client, start and end times, compile state, tests, build results, logs,
artifacts, cancellation state, and observed file changes. A skipped, unavailable, timed-out, or
inconclusive check is never reported as passed.

### 5. Safety and Verification

Safety is enforced by a central Kinglet policy engine. Client hooks are defense in depth and native
UX integration, not the only enforcement boundary.

Operations are classified as:

- observe;
- scoped project write;
- Unity-sensitive write;
- destructive;
- external side effect;
- sensitive-data access.

Direct edits to scene and prefab YAML are blocked by default. `.meta` files, `ProjectSettings`, and
`Packages` receive specialized guards. Destructive and external actions require precise targets and
appropriate approval. More restrictive client policy remains effective even when Kinglet policy
would permit an action.

A project has one execution/write lease shared by all Kinglet clients. Reads may run in parallel
when safe; writes are serialized. The Unity state machine exposes at least offline, starting,
importing, compiling, ready, playing, domain-reloading, busy, and failed states. An expired lease
can be recovered through a documented flow; an active lease is never silently stolen.

Verification is an evidence contract, not a prose suggestion. Depending on task scope it may require
compilation, EditMode tests, PlayMode tests, builds, console inspection, scene readback, screenshots,
asset validation, or documentation checks. Kinglet reports exactly which checks ran, which backend
produced them, and which risks remain.

### 6. Upstream and Provenance

Every imported item is classified as original, verbatim, adapted, inspired, or generated. Tracked
metadata records:

- source repository, tag or immutable commit, and path;
- license and required notice;
- original checksum;
- Kinglet target and canonical identity;
- change summary and adoption decision;
- tests that protect the adopted behavior;
- most recent upstream comparison.

The trace chain is:

```text
upstream source → canonical Kinglet item → client adapter output → release artifact
```

Upstream intake is deliberate: inspect the license, define the need, choose adopt/adapt/reference/
reject, add tests, record provenance and notices, then run behavior evaluations. There is no
automatic upstream synchronization. Tooling may prepare comparison reports, but a maintainer reviews
and approves every import or update.

README, CREDITS, NOTICE, shipped package notices, and relevant source annotations will credit ECU,
CCGS, Superpowers, and Unity MCP according to their actual use and licenses. Missing license,
checksum, provenance, or notice data blocks release.

The root `.research/` directory is ignored as a whole. Individual research project names are not
added to `.gitignore`. Research clones are disposable and may move independently from product pins;
their current checkout never defines a release dependency.

### 7. Packaging and Lifecycle

One Kinglet product version coordinates the canonical core, setup engine, policy engine, execution
broker, content catalog, and compatible adapter packages. Adapter implementations may have internal
build identifiers, but users reason about a Kinglet release and its published compatibility
manifest.

Client plugins are thin entry layers. A signed, versioned Kinglet core is installed once per user
and shared across supported clients. Immutable versions coexist:

- Windows: `%LOCALAPPDATA%\Kinglet\versions\<version>`
- macOS and Linux: the platform-standard per-user application data location

A project pins its release and schema through Git-tracked project metadata and `kinglet.lock`.
Adding another client reuses the pinned core and local artifact cache. Updating a thin plugin does
not silently upgrade the project’s core or schema.

The lifecycle surface includes:

- `setup`
- `add-client`
- `doctor`
- `upgrade`
- `rollback`
- `repair`
- `uninstall`
- deterministic test and build actions

Project upgrades are explicit, previewed, backed up, staged, migrated, validated, and receipted.
Rollback selects a previously installed immutable version and restores affected project state only
after validating ownership. Uninstall removes unchanged Kinglet-owned surfaces and leaves user,
adopted, and foreign-owned content intact.

The primary end-user path is a native plugin. The secondary path is a signed standalone installer
or portable `kinglet.exe`, especially for offline, enterprise, CI, or plugin-restricted
environments. Both consume the same signed release manifest and artifacts. An offline bundle is a
transport of the same release, not a separate product.

Early alpha and beta releases may use Kinglet’s own GitHub-hosted marketplace or direct plugin
source. Official marketplace submissions follow after stable behavior and lifecycle qualification.
Developers and contributors clone or fork the source repository; ordinary users do not.

## Process provider interoperability

General software-development methodology is replaceable behind a provider contract. The contract
defines stages such as discovery, brainstorming, planning, implementation, debugging, review, and
verification, along with their inputs, outputs, evidence, and handoff rules.

Kinglet ships a built-in provider so standalone behavior is complete. If setup detects a compatible
Superpowers installation, it proposes Superpowers as a general process provider and explains the
division of responsibility:

- the provider owns general development process;
- Kinglet owns Unity domain knowledge, project policies, execution, and Unity evidence.

The user approves provider selection. Kinglet does not copy, uninstall, disable, or secretly shadow
the detected plugin. If the active provider later disappears or becomes incompatible, doctor offers
the built-in provider as an explicit fallback.

A project normally has one active provider per process stage. Advanced configurations may assign
different compatible providers to different stages, but two providers do not compete for the same
stage. Provider choice is project configuration, not hidden client state.

## Extension and customization model

Users extend Kinglet through content packs instead of forking the product. A pack can contain
skills, roles, rules, semantic actions, Unity knowledge, templates, schemas, migrations, tests,
license data, and capability requirements.

Content is composed in this order:

1. Kinglet canonical core
2. selected process provider
3. organization or team pack
4. project-specific content
5. user-local preferences
6. client-native projection

More specific content may extend or intentionally replace identified behavior. Safety follows a
different rule: the most restrictive applicable policy wins. Weakening a safety policy requires an
explicit policy change, user approval, and transaction record; it cannot happen through an
accidental filename collision.

All extension items use stable namespaced identities. Deliberate replacement must name the target
identity and is visible in setup’s proposed change set. Migrated user content receives `adopted`
ownership and a non-Kinglet namespace. Generated client files retain a source map to their
canonical inputs. If a generated file is changed by hand, its checksum conflict is surfaced before
regeneration.

Initial releases support local directories, pinned Git sources, and signed release packages.
Kinglet will not build a central extension marketplace before the core contract is proven.
Extensions containing executable code require an explicit capability declaration, trusted source,
signature where distributed, and user approval.

## Project and local data model

Shared, durable project state is client-neutral and Git-tracked by default:

- `.kinglet/project.json` for project identity, feature choices, and shared policy;
- `kinglet.lock` for the pinned Kinglet release, schemas, content packs, providers, and adapter
  compatibility;
- `docs/` for GDDs, ADRs, plans, decisions, QA records, and other durable project knowledge.

Machine-local and transient state is ignored:

- Unity installation paths and resolved executables;
- credentials and tokens;
- caches and downloaded artifacts;
- logs and diagnostic journals;
- process IDs, execution leases, and runtime snapshots;
- backups and staging directories;
- machine-specific client settings.

These belong under an ignored `.kinglet/local/` hierarchy or the per-user Kinglet application-data
directory. A transaction may also emit a sanitized, durable migration or provenance record when
the decision itself should be shared, but it must not contain machine paths or secrets.

## Native Windows and dependency policy

Windows 10 and 11 are first-class native hosts. Core workflows must run from PowerShell, Command
Prompt, supported agent process APIs, or the Kinglet executable without WSL or Git Bash. Agents may
invoke `.exe` files when the local client’s permission model allows it.

Kinglet does not ban Python. It bans fragile, manual prerequisite management for ordinary users.
If a selected component needs Python, Kinglet may manage it through a pinned tool such as `uv` or
ship an appropriate self-contained runtime. Users should not need to install an arbitrary Python
version, construct a virtual environment, or edit PATH by hand.

The implementation language for the core is selected through an evidence-producing technical
spike. The spike must compare native packaging, process management, filesystem semantics,
signature verification, testability, and maintainability on Windows, macOS, and Linux. No later
implementation plan may assume a language before that gate passes.

A remote or cloud-hosted agent cannot control a local Windows Unity Editor without an explicitly
configured remote bridge. Kinglet must report that topology limitation instead of treating local
process launch as universally available.

## User experience and command surface

Natural language is the primary interface:

```text
Run Kinglet setup for this project.
Add Claude support to this existing Kinglet project.
Check the project and explain anything that needs attention.
Run the Unity tests and fix the compile failure.
Upgrade this project to the latest compatible Kinglet release.
```

An adapter maps these requests to canonical semantic actions. Client-specific slash commands,
skill mentions, or tool names are native shortcuts, not separate workflow definitions.

The equivalent CLI supports deterministic use, automation, troubleshooting, and CI:

```text
kinglet setup
kinglet add-client
kinglet doctor
kinglet upgrade
kinglet rollback
kinglet test
kinglet build
```

Mutating actions support dry-run where meaningful and a machine-readable result format. At session
start, an adapter performs only a cheap binding and compatibility check. It does not automatically
download, migrate, or modify the project. Skills and detailed Unity content load progressively
rather than flooding every initial context.

Setup behaves as a conversational wizard: show discoveries, explain capability grades, propose
changes, request approval, back up, apply, validate, and report evidence. Normal development
requests do not require the user to choose an internal role. Kinglet selects suitable skills and
roles; advanced users may explicitly choose a role, execution route, or verification level.

## Error handling and observability

Every setup, migration, lifecycle, Unity, and verification operation receives a transaction
identifier and produces a structured result:

- action and execution backend;
- completed, skipped, and failed stages;
- affected or proposed paths;
- project, Unity, client, and version context;
- evidence and local log locations;
- stable error code;
- safe next action such as retry, repair, rollback, or manual intervention.

Failures are classified into environment/dependency, adapter, Unity execution,
migration/lifecycle, and security/integrity domains. Optional capability failure may degrade only to
a declared and tested lower capability grade. Signature, ownership, destructive-action, and project
integrity failures stop safely.

Automatic retry is limited to transient, idempotent operations. Kinglet does not automatically
repeat project writes, Unity mutations, package changes, or destructive actions. Cancellation
terminates owned child process trees using native platform behavior, releases leases, preserves
evidence, and marks incomplete stages.

Setup and upgrade use staging for atomic project application. Unity operations are not falsely
described as atomic: receipts identify changed files, backups, and possible Editor-side effects.
Kinglet reports rollback success only after post-rollback validation passes.

Detailed journals stay local and are redacted for known credentials and sensitive fields. No
automatic telemetry is sent. A support bundle is opt-in, redacted, and previewable by the user
before sharing. Doctor may diagnose from local records but requires approval before repair.

## Distribution and supply-chain security

A plugin’s setup entry fetches a pinned release manifest and signed artifact, verifies checksum and
signature, then invokes the release’s setup engine. It never executes arbitrary code from the
repository’s moving default branch.

Releases include:

- immutable versioned artifacts;
- checksums and signatures;
- software bill of materials;
- canonical-to-adapter provenance;
- third-party notices;
- compatibility and capability matrices;
- migration and rollback metadata.

Kinglet’s own marketplace is sufficient for early releases. Official Claude, Codex, Cursor,
Copilot, VS Code, and Antigravity publication follows each platform’s current review and packaging
requirements. Publication mechanics are adapter concerns and may change without changing the
canonical workflow contract.

## Validation and release gates

### Deterministic PR tests

Every pull request runs:

- schema, identity, reference, and capability validation;
- deterministic generation and golden-output tests;
- normalized adapter manifest comparisons;
- path traversal and unsafe-target tests;
- ownership, setup, migration, repair, rollback, and uninstall fixtures;
- provenance, license, checksum, notice, and forbidden-content checks;
- plugin packaging and lifecycle tests;
- policy-engine and client-normalizer fixtures;
- platform-appropriate process and cancellation tests.

### Real client behavior evaluations

File existence or syntactic registration is insufficient. Clean client sessions must demonstrate:

- natural-language discovery;
- correct semantic action and workflow selection;
- correct skill and role loading;
- safe approval behavior;
- expected mutation blocks;
- correct Unity route selection;
- required evidence collection;
- honest failure and unavailable-capability reporting.

Each first-class client gets native lifecycle and behavior tests. Shared package formats may share
fixtures but cannot share unexamined pass status.

### Real Unity project matrix

Fixtures and pilot projects include:

- small 2D;
- URP;
- HDRP;
- larger or structurally complex projects;
- projects migrated from current Kinglet/ECU/CCGS/custom agent systems;
- deliberately broken imports, packages, locks, MCP connections, and test suites.

Windows, macOS, and Linux run natively. PRs run deterministic smoke coverage, nightly jobs run a
broader matrix, and release qualification runs the full promised matrix plus real-project pilots.
A compatibility entry is published only for combinations actually tested, including client, client
version, Unity version, operating system, execution backend, date, and known limitations.

Skipped, unavailable, inconclusive, flaky-without-resolution, or manually assumed results are not
passes. Stable release is blocked when any promised combination lacks evidence.

## Delivery decomposition

The implementation is divided into independently specified and gated subprojects.

### 0. Technical spikes and capability proof

Validate native executable approaches, all target clients’ real extension surfaces, Unity process
launch, batchmode/MCP coexistence constraints, signing, and cross-platform process control. Select
the core implementation technology from recorded evidence.

### 1. Canonical foundation

Define and validate manifests, catalogs, content identities, capability grades, provider and
extension contracts, ownership, provenance, policy types, transactions, evidence, and error
schemas.

### 2. Windows reference vertical slice

Deliver a minimal end-to-end shared core with Codex and Claude adapters, setup, add-client, doctor,
filesystem workflows, and basic headless compile/test on clean and migrated Windows projects.

Codex and Claude are the first reference pair because their different integration mechanisms expose
adapter mistakes early. This order does not reduce the stable support commitment for other
first-class clients. Capability spikes for every target client happen in subproject 0.

### 3. Unity execution layer

Complete live Editor + MCP, same-project headless, isolated headless, state machine, execution
lease, structured evidence, cancellation, recovery, EditMode, PlayMode, build, and visual
verification behavior.

### 4. Content and ecosystem

Migrate and refine Kinglet’s Unity knowledge and workflows, implement the built-in process
provider, integrate compatible Superpowers use, add content packs, and support selective adoption
from ECU, CCGS, current Kinglet, and custom project systems. Candidate Superpowers practices include
brainstorming, written planning, test-driven development, systematic debugging, verification,
review, and worktree isolation; each is adopted only when it fits Kinglet’s provider contract and
Unity-specific safety model.

### 5. Client expansion

Complete and behavior-test Cursor, Copilot CLI, Copilot in VS Code, and Antigravity adapters with
published Native/Emulated/Unavailable matrices.

### 6. Productization and stable release

Qualify macOS and Linux, real-project pilots, signed releases, SBOM, marketplace publication,
offline/enterprise distribution, upgrade/rollback/uninstall durability, and the full stable
compatibility matrix.

Every subproject receives its own design spec, implementation plan, test-driven implementation
cycle, real behavior evaluation, documentation, and completion gate. A later subproject may depend
only on an earlier gate that has actually passed.

## Success criteria

The redesign is complete only when:

- ordinary users can install Kinglet without cloning the source repository;
- a project is initialized once and additional supported clients can be added idempotently;
- shared project documents and policy remain client-neutral and Git-trackable;
- each first-class client exposes an honest, tested capability matrix;
- Windows works natively without WSL or Git Bash;
- Kinglet works without MCP and gains verified live-Editor capability when MCP is available;
- the execution broker never opens the same project in GUI and batchmode concurrently;
- cross-client writes are serialized and every claimed success has structured evidence;
- migration, upgrade, rollback, repair, and uninstall preserve user and foreign-owned content;
- Superpowers or another provider can be selected without making Kinglet dependent on it;
- extensions can add content without forking Kinglet or silently weakening safety;
- provenance follows every imported item into generated packages and release artifacts;
- release artifacts are pinned, signed, checksummed, and accompanied by SBOM and notices;
- real client and Unity evaluations pass on every combination Kinglet publicly promises.

## External references

The adapter and Unity capability spikes must revalidate current official documentation before
implementation because plugin surfaces and marketplace rules evolve:

- Claude Code plugins and marketplaces:
  `https://code.claude.com/docs/en/discover-plugins`
  and `https://code.claude.com/docs/en/plugin-marketplaces`
- Codex plugins and submission:
  `https://developers.openai.com/codex/plugins/build`
  and `https://learn.chatgpt.com/docs/submit-plugins`
- Cursor marketplace publishing:
  `https://cursor.com/blog/marketplace`
  and `https://cursor.com/marketplace/publish`
- GitHub Copilot CLI plugins:
  `https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-finding-installing`
- VS Code agent plugins:
  `https://code.visualstudio.com/docs/agent-customization/agent-plugins`
- Antigravity plugins:
  `https://antigravity.google/docs/ide/plugins?app=antigravity-ide`
- Unity command-line operation:
  `https://docs.unity3d.com/6000.0/Documentation/Manual/EditorCommandLineArguments.html`
- CoplayDev Unity MCP:
  `https://coplaydev.github.io/unity-mcp/`
