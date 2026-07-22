# Kinglet Identity and Canonical Build Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the Kinglet product identity, strict canonical data model, deterministic Python build tool, and CI guardrails without changing the installed Claude product.

**Architecture:** A Python-standard-library-only builder loads JSON descriptors and Markdown bodies into one validated canonical graph. Client renderers consume that graph through a stable renderer protocol, while an atomic writer makes committed generated products reproducible. During migration the existing root `.claude/` tree remains a generator-controlled compatibility mirror; it is not a second source of truth and is removed only in Plan 05.

**Tech Stack:** Python 3 standard library, `unittest`, Bash 3.2-compatible test wrappers, JSON, GitHub Actions, existing provenance tooling.

## Global Constraints

- Product brand is `Kinglet`; display name is `Kinglet for Unity`; repository and plugin slug is `kinglet-unity`.
- The initial migration version is `3.0.0-dev.1`; Plan 06 promotes it to `3.0.0` after the release matrix passes.
- Canonical metadata is JSON. Do not add PyYAML, Pydantic, Jinja, or another runtime dependency.
- The public build commands are exactly:
  - `python3 -m tools.kinglet_build validate`
  - `python3 -m tools.kinglet_build build --all`
  - `python3 -m tools.kinglet_build build --all --check`
- Generated packages are committed, byte-stable, and never read back as build input.
- Every descriptor rejects unknown fields and requires explicit Claude and Codex support states.
- First-release host support remains Linux and macOS. Native Windows is reported as unsupported.
- Preserve all historical attribution and upstream provenance.
- Every tracked file added by this plan receives one row in `provenance.tsv` before its task commit.

## Dependency and File Map

This plan has no implementation-plan dependency and must run first. Plans 02–06 import its Python APIs.

```text
VERSION                                      Product version source
src/catalog/capabilities.json                Canonical capability registry
src/catalog/support-policy.json              Per-client support rules
src/catalog/routing.json                     Empty, valid routing catalog for Plan 03
adapters/claude/profile.json                  Claude capability/tool/tier mapping
adapters/codex/profile.json                   Codex capability/tool/tier mapping
tools/__init__.py                             Python package marker
tools/kinglet_build/__init__.py               Public package exports
tools/kinglet_build/__main__.py               `python -m` entry point
tools/kinglet_build/cli.py                    Argument parsing and exit codes
tools/kinglet_build/errors.py                 Stable diagnostic type
tools/kinglet_build/model.py                  Frozen canonical graph dataclasses
tools/kinglet_build/loader.py                 Strict JSON and body loader
tools/kinglet_build/validator.py              Graph, support, and path validation
tools/kinglet_build/renderers/__init__.py     Renderer protocol and registry
tools/kinglet_build/writer.py                 Deterministic check/write engine
tests/kinglet/__init__.py                     Python test package
tests/kinglet/test_identity.py                 Product identity test
tests/kinglet/fixtures/valid-minimal/**        Minimal valid graph fixture
tests/kinglet/fixtures/invalid-unknown/**      Unknown-field fixture
tests/kinglet/test_loader.py                  Loader/schema tests
tests/kinglet/test_validator.py               Graph validation tests
tests/kinglet/test_writer.py                  Reproducibility tests
tests/kinglet/test_cli.py                     Public CLI tests
tests/test-kinglet-build.sh                   Existing shell-suite bridge
.github/workflows/ci.yml                      Build/check CI gates
provenance.tsv                                Ownership records
```

## Task 1: Lock Product Identity and the Python Test Harness

**Files:**

- Create: `VERSION`
- Create: `tools/__init__.py`
- Create: `tools/kinglet_build/__init__.py`
- Create: `tests/kinglet/__init__.py`
- Create: `tests/kinglet/test_identity.py`
- Create: `tests/test-kinglet-build.sh`
- Modify: `tests/run-tests.sh`
- Modify: `provenance.tsv`

- [ ] **Step 1: Write the failing identity smoke test**

Create `tests/kinglet/test_identity.py` with assertions that `VERSION` is exactly `3.0.0-dev.1`, the package exposes `PRODUCT_NAME == "Kinglet for Unity"`, and `PRODUCT_SLUG == "kinglet-unity"`.

Run:

```bash
python3 -m unittest tests.kinglet.test_identity -v
```

Expected: `ImportError` for `tools.kinglet_build` or missing constants.

- [ ] **Step 2: Add the minimum identity implementation**

`tools/kinglet_build/__init__.py` must expose this API:

```python
PRODUCT_NAME = "Kinglet for Unity"
PRODUCT_SLUG = "kinglet-unity"
CANONICAL_SCHEMA_VERSION = 1

__all__ = ["CANONICAL_SCHEMA_VERSION", "PRODUCT_NAME", "PRODUCT_SLUG"]
```

Write `3.0.0-dev.1` followed by one newline to `VERSION`. Package markers contain no side effects.

- [ ] **Step 3: Connect Python tests to the existing shell runner**

`tests/test-kinglet-build.sh` must use `#!/usr/bin/env bash`, `set -euo pipefail`, resolve the repository root without `readlink -f`, and run:

```bash
python3 -m unittest discover -s tests/kinglet -p 'test_*.py' -v
```

Make it executable. Confirm `tests/run-tests.sh` already discovers `test-*.sh`; change it only if the current discovery excludes this filename.

- [ ] **Step 4: Verify and commit**

Run:

```bash
bash tests/test-kinglet-build.sh
bash scripts/check-provenance.sh
```

Expected: the identity test passes and provenance reports zero untracked ownership records after staging.

Commit:

```bash
git add VERSION tools tests/kinglet tests/test-kinglet-build.sh tests/run-tests.sh provenance.tsv
git commit -m "feat: establish Kinglet build identity"
```

## Task 2: Define Strict Canonical Models and Loaders

**Files:**

- Create: `tools/kinglet_build/errors.py`
- Create: `tools/kinglet_build/model.py`
- Create: `tools/kinglet_build/loader.py`
- Create: `src/catalog/capabilities.json`
- Create: `src/catalog/support-policy.json`
- Create: `src/catalog/routing.json`
- Create: `tests/kinglet/fixtures/valid-minimal/src/roles/unity-scout/role.json`
- Create: `tests/kinglet/fixtures/valid-minimal/src/roles/unity-scout/instructions.md`
- Create: `tests/kinglet/fixtures/valid-minimal/src/catalog/*.json`
- Create: `tests/kinglet/fixtures/invalid-unknown/src/roles/unity-scout/role.json`
- Create: `tests/kinglet/test_loader.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test strict loading before implementing it**

Cover these cases in `test_loader.py`:

1. the valid fixture becomes one `CanonicalUnit` keyed by `role.unity-scout`;
2. a descriptor with `mystery_field` raises `BuildError` with code `unknown-field`;
3. a missing Markdown body raises code `missing-content`;
4. duplicate IDs raise code `duplicate-id`;
5. invalid support values raise code `invalid-support`;
6. a missing `claude` or `codex` support entry raises code `missing-support`.

Run:

```bash
python3 -m unittest tests.kinglet.test_loader -v
```

Expected: import failure for the loader API.

- [ ] **Step 2: Implement stable diagnostics and immutable models**

Expose these exact public types:

```python
@dataclass(frozen=True)
class BuildError(ValueError):
    code: str
    source: Path
    field: str
    detail: str

@dataclass(frozen=True)
class SupportDeclaration:
    state: Literal["supported", "unsupported", "exception"]
    reason: str | None
    owner: str | None
    test: str | None

@dataclass(frozen=True)
class Provenance:
    origin: str
    upstream_version: str | None
    upstream_path: str | None
    upstream_sha256: str | None

@dataclass(frozen=True)
class CanonicalUnit:
    schema_version: int
    id: str
    kind: str
    name: str
    summary: str
    capabilities: tuple[str, ...]
    requires: tuple[str, ...]
    support: Mapping[str, SupportDeclaration]
    provenance: Provenance
    content_path: Path
    attributes: Mapping[str, object]

@dataclass(frozen=True)
class CanonicalGraph:
    root: Path
    capabilities: frozenset[str]
    support_policy: Mapping[str, object]
    routes: tuple[Mapping[str, object], ...]
    units: Mapping[str, CanonicalUnit]
```

`BuildError.__str__()` must produce `source:field: [code] detail` so CI messages are stable.

- [ ] **Step 3: Implement the strict descriptor loader**

Expose `load_graph(repository_root: Path) -> CanonicalGraph`. It scans only these descriptor/body pairs:

| Kind | Descriptor | Required body |
|---|---|---|
| `role` | `src/roles/*/role.json` | `instructions.md` |
| `workflow` | `src/workflows/*/workflow.json` | `instructions.md` |
| `knowledge` | `src/knowledge/*/knowledge.json` | `SKILL.md` |
| `rule` | `src/rules/*/rule.json` | `instructions.md` |
| `hook` | `src/hooks/*/hook.json` | `policy.sh` |
| `template` | `src/templates/*/template.json` | `content.md` |

Every descriptor accepts the common fields `schema_version`, `id`, `kind`, `name`, `summary`, `capabilities`, `requires`, `support`, and `provenance`. It may additionally contain only its kind-specific fields:

- role: `reasoning_tier`, `evidence`
- workflow: `public_name`, `stages`, `roles`, `rules`, `knowledge`, `inputs`, `artifacts`, `evidence`, `failure_behavior`, `mutation`
- knowledge: `public_name`, `category`, `references`, `scripts`
- rule: `scope`, `always_loaded`
- hook: `events`, `priority`, `decision`, `needs_jq`
- template: `public_name`, `output_name`, `language`

Reject symlinked descriptor/body files, non-UTF-8 input, non-integer schema versions, and IDs that do not match `^(role|workflow|knowledge|rule|hook|template)\.[a-z0-9][a-z0-9-]*$`.

- [ ] **Step 4: Add the canonical catalogs**

`capabilities.json` contains schema version `1` and exactly:

```json
{
  "schema_version": 1,
  "capabilities": [
    "delegate",
    "filesystem.read",
    "filesystem.write",
    "shell",
    "unity.read",
    "unity.write",
    "web"
  ]
}
```

`support-policy.json` requires clients `claude` and `codex`, permits states `supported`, `unsupported`, and `exception`, and requires `reason`, `owner`, and `test` for an exception. It declares `linux` and `macos` supported and `windows` unsupported for `3.0.0`.

`routing.json` is a valid empty catalog with schema version `1` and `routes: []`; Plan 03 replaces the empty route list before any product build is releasable.

- [ ] **Step 5: Verify and commit**

Run:

```bash
python3 -m unittest tests.kinglet.test_loader -v
bash tests/test-kinglet-build.sh
```

Expected: all loader tests pass; no traceback escapes a tested `BuildError` case.

Commit:

```bash
git add src tools/kinglet_build tests/kinglet provenance.tsv
git commit -m "feat: load strict canonical Kinglet graph"
```

## Task 3: Validate References, Support, Capabilities, and Output Claims

**Files:**

- Create: `tools/kinglet_build/validator.py`
- Create: `tests/kinglet/test_validator.py`
- Extend: `tests/kinglet/fixtures/valid-minimal/**`
- Modify: `provenance.tsv`

- [ ] **Step 1: Add failing graph-invariant tests**

Use in-memory `dataclasses.replace` copies of the valid fixture to prove failures for:

- unresolved `requires`, `roles`, `rules`, and `knowledge` IDs;
- a reference to the wrong unit kind;
- capability names absent from `capabilities.json`;
- a forbidden cycle in `requires`;
- `exception` without reason, owner, or named test;
- `supported` with an exception-only field;
- duplicate generated-path claims;
- a workflow with `mutation: true` but neither `filesystem.write` nor `unity.write`;
- a workflow missing at least one stage, artifact, and evidence item.

Run and observe failure:

```bash
python3 -m unittest tests.kinglet.test_validator -v
```

- [ ] **Step 2: Implement one validation entry point**

Expose:

```python
def validate_graph(graph: CanonicalGraph) -> None:
    """Raise the first deterministic BuildError after sorting units by ID."""
```

Validation order is: catalog schemas, unit schemas, IDs/kinds, capabilities, references, support, workflow contract, dependency cycles, generated-path claims. Sort both unit IDs and reference IDs before inspecting them so the same invalid tree always emits the same error.

Only `requires` is cycle-checked. A workflow may legitimately list a role that requires knowledge also listed by the workflow.

Generated-path claims are read from adapter profiles introduced in Task 4; until those profiles exist this phase validates that canonical `public_name` values are unique within a kind.

- [ ] **Step 3: Verify and commit**

Run:

```bash
python3 -m unittest tests.kinglet.test_loader tests.kinglet.test_validator -v
```

Expected: every negative fixture identifies its exact error code; the valid fixture passes.

Commit:

```bash
git add tools/kinglet_build/validator.py tests/kinglet provenance.tsv
git commit -m "feat: validate Kinglet canonical graph"
```

## Task 4: Add Native Adapter Profiles and the Renderer Contract

**Files:**

- Create: `adapters/claude/profile.json`
- Create: `adapters/codex/profile.json`
- Create: `tools/kinglet_build/renderers/__init__.py`
- Create: `tests/kinglet/test_adapter_profiles.py`
- Modify: `tools/kinglet_build/loader.py`
- Modify: `tools/kinglet_build/model.py`
- Modify: `tools/kinglet_build/validator.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test complete and client-native mappings**

Tests must require both client adapters to map all seven logical capabilities and all three reasoning tiers. Each adapter has `default_agent_profile: standard` plus `standard` and `frontier` profile definitions. Assert the exact standard mapping:

| Tier | Claude profile | Codex profile |
|---|---|---|
| `fast` | `haiku` | `gpt-5.6-luna`, reasoning effort `medium` |
| `balanced` | `sonnet` | `gpt-5.6-terra`, reasoning effort `medium` |
| `deep` | `opus` | `gpt-5.6-sol`, reasoning effort `high` |

`frontier` is not a fourth canonical tier. It must equal `standard` for `fast` and `balanced`, map Claude `deep` to `fable`, and map Codex `deep` to `gpt-5.6-sol` with effort `max` plus required native capability `reasoning.mode.pro`. Test that `max` without the Pro capability is invalid and that no prompt-text field may claim or emulate Pro. Fable availability and Codex native Pro support are runtime prerequisites, not assumed adapter facts.

Model names, Codex reasoning effort, and native capability requirements live only in profiles. Canonical content tests must fail if `haiku`, `sonnet`, `opus`, `fable`, or `gpt-5.6-` occurs under `src/`. Repository-wide active-source tests must also reject the deprecated `gpt-5.3-codex` mapping outside migration/history fixtures. Neither adapter may declare a main-session, project-wide, or global default model. Claude aliases remain aliases so the user's provider resolves the supported generation; Codex model IDs are explicit.

The initial quality policy deliberately uses Luna `medium` for both fast roles. Store a non-shipping evaluation candidate for `unity-linter` at Luna `low`; do not change the standard mapping unless Plan 06 proves identical correctness/evidence with an efficiency improvement. `unity-scout` is not eligible for the initial low-effort trial.

The Codex capability mapping uses logical action groups, not invented tool names: `filesystem.read`, `filesystem.write`, and `shell` map to the sandboxed command surface; `delegate` maps to agent delegation; `unity.read` and `unity.write` map to the pinned MCP surface; `web` maps to web access. The Claude profile maps the same logical set to its native allowed-tool patterns.

- [ ] **Step 2: Implement `AdapterProfile` loading**

Add immutable `AdapterProfile(client, default_agent_profile, agent_profiles, capabilities, output_roots)` and expose:

```python
def load_adapter_profiles(repository_root: Path) -> Mapping[str, AdapterProfile]:
```

Each `agent_profiles` entry maps the three canonical tiers to a native model configuration and optional hard capability requirements. Reject missing clients, extra clients, any default other than `standard`, unknown agent-profile names, missing/extra tiers, unknown capabilities, `frontier.fast` or `frontier.balanced` drift from standard, a Claude frontier without `fable`, a Codex frontier without Sol/`max`/native Pro, absolute output paths, `..` path components, and overlapping product output roots.

The loader exposes no API that sets the active session model. Profile selection is an installer/renderer input added in Plans 03 and 05, never implicit process-global state.

- [ ] **Step 3: Define the renderer boundary**

`tools.kinglet_build.renderers` exposes:

```python
@dataclass(frozen=True)
class RenderedFile:
    path: PurePosixPath
    content: bytes
    source_ids: tuple[str, ...]

class Renderer(Protocol):
    client: str
    def render(self, graph: CanonicalGraph, profile: AdapterProfile) -> tuple[RenderedFile, ...]: ...

def renderer_registry() -> Mapping[str, Renderer]:
    return {}
```

An empty registry is valid in Plan 01. Plans 02–04 register content renderers. `RenderedFile.path` is always relative to its declared product root and may not contain `..`.

- [ ] **Step 4: Verify and commit**

Run:

```bash
python3 -m unittest tests.kinglet.test_adapter_profiles -v
python3 -m tools.kinglet_build validate
```

Expected: profiles validate and the repository graph reports `0 canonical units, 0 routes, 2 adapters`.

Commit:

```bash
git add adapters tools/kinglet_build tests/kinglet provenance.tsv
git commit -m "feat: define Kinglet adapter contract"
```

## Task 5: Implement Deterministic Writes and the Public CLI

**Files:**

- Create: `tools/kinglet_build/writer.py`
- Create: `tools/kinglet_build/cli.py`
- Create: `tools/kinglet_build/__main__.py`
- Create: `tests/kinglet/test_writer.py`
- Create: `tests/kinglet/test_cli.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Write failing deterministic-writer tests**

Cover sorted output, LF newline normalization for declared text files, executable-bit preservation for `.sh`, byte-for-byte `--check`, stale generated-file detection, path traversal rejection, duplicate path rejection, and absence of partial output after a simulated write failure.

Run:

```bash
python3 -m unittest tests.kinglet.test_writer -v
```

- [ ] **Step 2: Implement the write/check boundary**

Expose:

```python
@dataclass(frozen=True)
class WriteResult:
    changed: tuple[PurePosixPath, ...]
    stale: tuple[PurePosixPath, ...]

def write_product(
    files: tuple[RenderedFile, ...],
    destination: Path,
    *,
    check: bool,
) -> WriteResult:
    """Compare or atomically replace one generated product tree."""
```

The implementation stages under `destination.parent` with `tempfile.mkdtemp`, sorts paths using POSIX strings, writes a generated manifest named `.kinglet-generated.json`, and swaps only after every file is durable. In check mode it performs no write and returns all differences. It never follows a destination symlink.

- [ ] **Step 3: Test CLI contracts and exit codes**

`test_cli.py` invokes `cli.main(argv, repository_root=fixture)` and asserts:

| Situation | Exit |
|---|---:|
| valid graph/check clean | `0` |
| schema or graph error | `2` |
| generated drift in `--check` | `3` |
| usage error | `64` |
| unexpected I/O error | `74` |

`build` accepts exactly one of `--all`, `--claude`, or `--codex`, plus optional `--check`. `validate` accepts no target flag. Diagnostics go to stderr; stable summaries go to stdout.

- [ ] **Step 4: Implement and exercise the CLI**

`__main__.py` calls `raise SystemExit(main())`. `build --all` loads and validates once, invokes registered renderers in client-name order, and writes the Claude package, Codex plugin, Codex project bootstrap, and migration compatibility mirror to their profile roots. With an empty renderer registry, it creates no product directory and reports zero rendered files.

Run:

```bash
python3 -m tools.kinglet_build validate
python3 -m tools.kinglet_build build --all
python3 -m tools.kinglet_build build --all --check
python3 -m unittest tests.kinglet.test_cli tests.kinglet.test_writer -v
```

Expected: all commands exit `0`; the two build commands report `0 rendered files`.

- [ ] **Step 5: Commit**

```bash
git add tools/kinglet_build tests/kinglet provenance.tsv
git commit -m "feat: add deterministic Kinglet build CLI"
```

## Task 6: Record the Migration Baseline and Gate CI

**Files:**

- Create: `migration/baseline-inventory.json`
- Create: `tests/kinglet/test_baseline_inventory.py`
- Modify: `.github/workflows/ci.yml`
- Modify: `provenance.tsv`

- [ ] **Step 1: Capture the exact legacy surface**

Generate `migration/baseline-inventory.json` from the tracked tree, then review and commit it as human-owned migration evidence. It must enumerate paths and SHA-256 values for:

- 28 files under `.claude/agents/`;
- 36 files under `.claude/commands/`;
- 39 `SKILL.md` files under `.claude/skills/`;
- 26 executable policy hooks under `.claude/hooks/`, excluding `_lib.sh`;
- 6 files under `.claude/rules/`;
- 5 Markdown files under `.claude/templates/`;
- 10 code templates under `templates/`.

The test compares both counts and exact sorted path lists. A count-only match is insufficient.

- [ ] **Step 2: Add failing drift and identity tests**

Test that every inventory SHA matches, every inventory path exists, and no additional file appears in a listed category without an inventory update. Also scan tracked product text and fail on new product-positioning uses of `cloud-nine-unity`; permit historical occurrences only in `MERGE-NOTES.md`, `CREDITS.md`, `provenance.tsv`, migration fixtures, and legacy-marker tests.

- [ ] **Step 3: Add CI gates**

In the existing Ubuntu validation job, after repository tests, run:

```bash
python3 -m tools.kinglet_build validate
python3 -m tools.kinglet_build build --all --check
```

Run `bash tests/test-kinglet-build.sh` on both Ubuntu and macOS. Keep the existing Bash 3.2 compatibility, ShellCheck, installer, and provenance jobs intact.

- [ ] **Step 4: Run the phase gate**

Run:

```bash
bash tests/test-kinglet-build.sh
bash tests/run-tests.sh
python3 -m tools.kinglet_build validate
python3 -m tools.kinglet_build build --all --check
bash scripts/check-provenance.sh
```

Expected: all commands exit `0`; the baseline test reports the exact `28/36/39/26/6/5/10` inventory.

- [ ] **Step 5: Commit**

```bash
git add migration .github/workflows/ci.yml tests/kinglet provenance.tsv
git commit -m "test: gate Kinglet canonical build foundation"
```

## Plan 01 Completion Gate

Plan 02 may start only when:

- all five public build/validation commands above pass on Linux;
- the Python suite passes on the repository's macOS runner;
- generated-check mode performs no writes;
- no canonical descriptor can omit either client support state;
- the legacy Claude tree is unchanged byte-for-byte from the baseline inventory;
- `git status --short` contains no generated drift.
