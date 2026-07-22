# Kinglet Rules, Templates, and Knowledge Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all shared rules, templates, and knowledge skills into canonical `src/` units and generate behavior-preserving Claude output plus native Codex content from that single source.

**Architecture:** A one-use strict importer converts the frozen Plan 01 baseline into reviewable canonical descriptors and bodies. Category renderers then create complete, deterministic product subtrees. Claude keeps its existing paths and frontmatter; Codex receives namespaced skills, generated project guidance, and template references suited to its plugin surface. Root `.claude/skills`, `.claude/rules`, and `.claude/templates` become temporary generated compatibility mirrors while unmigrated Claude categories remain untouched.

**Tech Stack:** Plan 01 Python builder, Python `unittest`, Markdown, JSON, Bash 3.2-compatible verification, SHA-256 golden manifests.

## Global Constraints

- Execute after Plan 01's completion gate.
- Import only from the hashes recorded in `migration/baseline-inventory.json`; abort on source drift.
- Canonical bodies retain all operational instructions, examples, safety warnings, reference files, and scripts.
- Canonical prose contains no current Claude or OpenAI model names and no client-specific tool names.
- Existing Claude skill paths and explicit skill names remain stable.
- Codex knowledge skill directories use `knowledge-<slug>` so `unity-instincts` cannot collide with workflow skill `unity-instincts` in Plan 03.
- Natural-language discovery metadata must be concrete enough to distinguish adjacent skills; a generic description such as “helps with Unity” is invalid.
- No legacy source file is deleted until its generated Claude counterpart passes semantic, frontmatter, executable-bit, and provenance checks.
- Every new tracked file receives one `provenance.tsv` row in the same task commit.

## Dependency and File Map

```text
migration/content-inventory.json                  Exact legacy-to-canonical mapping
tools/kinglet_build/import_legacy.py              Hash-guarded one-use importer
tools/kinglet_build/frontmatter.py                Minimal frontmatter parser/emitter
tools/kinglet_build/renderers/claude_content.py   Rules/templates/knowledge Claude renderer
tools/kinglet_build/renderers/codex_content.py    Rules/templates/knowledge Codex renderer
src/rules/<slug>/{rule.json,instructions.md}      Six canonical rules
src/templates/<slug>/{template.json,content.md}   Fifteen canonical templates
src/knowledge/<slug>/**                           Thirty-nine canonical knowledge units
packages/claude/.claude/{rules,templates,skills}  Generated Claude content
plugins/kinglet-unity/skills/knowledge-*/**       Generated Codex knowledge skills
plugins/kinglet-unity/references/templates/**     Generated Codex template library
packages/codex-project/AGENTS.md                  Generated rule/template project block
.claude/{rules,templates,skills}                  Temporary generated compatibility mirror
tests/kinglet/test_content_inventory.py           Mapping completeness tests
tests/kinglet/test_frontmatter.py                 Parser/emitter tests
tests/kinglet/test_content_import.py              Canonical import tests
tests/kinglet/test_claude_content.py              Claude compatibility goldens
tests/kinglet/test_codex_content.py               Codex-native structure tests
tests/kinglet/test_content_parity.py              Cross-client semantic parity tests
```

## Task 1: Freeze the Exact Content Mapping and Frontmatter Contract

**Files:**

- Create: `migration/content-inventory.json`
- Create: `tools/kinglet_build/frontmatter.py`
- Create: `tests/kinglet/test_content_inventory.py`
- Create: `tests/kinglet/test_frontmatter.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Write the inventory test with explicit path sets**

The test must assert the following rule slugs exactly:

```text
architecture csharp-unity pc-console performance serialization unity-specifics
```

It must assert these five Markdown template slugs and ten code template source names exactly:

```text
architecture-decision-record game-concept game-design-document sprint-plan systems-index
AssemblyDefinition.asmdef.template EditModeTest.cs.template LifetimeScope.cs.template
Message.cs.template Model.cs.template MonoBehaviour.cs.template PlayModeTest.cs.template
ScriptableObject.cs.template System.cs.template View.cs.template
```

It must assert these 39 knowledge source paths exactly:

```text
core/assembly-definitions
core/commit-trailers
core/deep-interview
core/event-systems
core/hud-statusline
core/learner
core/model-routing
core/object-pooling
core/scriptable-objects
core/serialization-safety
core/unity-instincts
core/unity-mcp-patterns
gameplay/character-controller
gameplay/dialogue-system
gameplay/inventory-system
gameplay/procedural-generation
gameplay/save-system
gameplay/state-machine
genre/idle-clicker
genre/match3
genre/platformer-2d
genre/puzzle
genre/rpg
genre/topdown
systems/addressables
systems/animation
systems/audio
systems/cinemachine
systems/input-system
systems/navmesh
systems/physics
systems/shader-graph
systems/ui-toolkit
systems/urp-pipeline
third-party/dotween
third-party/odin-inspector
third-party/textmeshpro
third-party/unitask
third-party/vcontainer
```

Run:

```bash
python3 -m unittest tests.kinglet.test_content_inventory -v
```

Expected: failure because `migration/content-inventory.json` does not exist.

- [ ] **Step 2: Create the reviewed mapping file**

Each entry records `kind`, `slug`, `category`, `legacy_path`, `canonical_descriptor`, `canonical_body`, `sha256`, and `generated_paths`. `generated_paths` has explicit `claude`, `codex`, and `compatibility` arrays. Code templates use kind `template`, category `code`, and retain the exact legacy filename as `output_name`.

Sort entries by `(kind, slug)`. Populate hashes from `migration/baseline-inventory.json`, never from a changed working file. The mapping totals must be `rules: 6`, `templates: 15`, `knowledge: 39`.

- [ ] **Step 3: Test and implement the restricted frontmatter codec**

The importer needs only the current repository's scalar/list frontmatter, not general YAML. Test LF and CRLF input, quoted/unquoted scalars, bracket lists, dash lists, empty documents, duplicate keys, malformed fences, and body preservation.

Expose:

```python
@dataclass(frozen=True)
class MarkdownDocument:
    metadata: Mapping[str, str | tuple[str, ...]]
    body: str

def parse_markdown_document(source: Path, text: str) -> MarkdownDocument:
    """Parse the repository's restricted frontmatter subset or raise BuildError."""

def emit_markdown_document(document: MarkdownDocument, key_order: tuple[str, ...]) -> str:
    """Emit deterministic LF Markdown with one terminal newline."""
```

Reject anchors, tags, folded scalars, nested mappings, duplicate keys, and unknown scalar types with code `unsupported-frontmatter`.

- [ ] **Step 4: Verify and commit**

Run:

```bash
python3 -m unittest tests.kinglet.test_content_inventory tests.kinglet.test_frontmatter -v
```

Expected: all mappings, hashes, and frontmatter round trips pass.

Commit:

```bash
git add migration/content-inventory.json tools/kinglet_build/frontmatter.py tests/kinglet provenance.tsv
git commit -m "test: freeze Kinglet content migration map"
```

## Task 2: Import Six Rules and Fifteen Templates

**Files:**

- Create: `tools/kinglet_build/import_legacy.py`
- Create: `tests/kinglet/test_content_import.py`
- Create: `src/rules/*/{rule.json,instructions.md}`
- Create: `src/templates/*/{template.json,content.md}`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test a hash-guarded, idempotent import**

In a temporary fixture repository, assert that:

- a matching rule becomes `rule.<slug>` plus byte-preserved body content;
- a matching template becomes `template.<slug>` with the exact output filename;
- a changed source hash aborts before any destination write with code `legacy-source-drift`;
- a second import produces no file changes;
- an existing non-identical canonical file aborts with code `canonical-conflict`;
- imported provenance matches the existing `provenance.tsv` origin/upstream fields.

Run:

```bash
python3 -m unittest tests.kinglet.test_content_import -v
```

- [ ] **Step 2: Implement the one-use import command**

Add this maintainer-only command without adding it to the public three-command contract:

```bash
python3 -m tools.kinglet_build.import_legacy --kind rule --kind template
```

The command loads the reviewed mapping, verifies every source hash, stages all results under a temporary directory, validates the staged canonical graph, and copies only after the entire selection passes. It exits `2` on `BuildError`, `74` on I/O failure, and `0` on success or an identical rerun.

Rule descriptors set `scope` from the original rule frontmatter and `always_loaded` only where the current Claude behavior loads the rule globally. Template descriptors set `language` to `markdown`, `csharp`, or `json` and retain the exact `output_name`.

- [ ] **Step 3: Run and review the import**

Run:

```bash
python3 -m tools.kinglet_build.import_legacy --kind rule --kind template
python3 -m tools.kinglet_build validate
git diff -- src/rules src/templates
```

Review every descriptor and body. Confirm there are 6 rule directories and 15 template directories, with no Claude tool/model names in canonical prose.

- [ ] **Step 4: Verify and commit**

```bash
python3 -m unittest tests.kinglet.test_content_import tests.kinglet.test_validator -v
git add src/rules src/templates tools/kinglet_build/import_legacy.py tests/kinglet provenance.tsv
git commit -m "feat: migrate Kinglet rules and templates"
```

## Task 3: Import Thirty-Nine Knowledge Units with Their Assets

**Files:**

- Create: `src/knowledge/*/knowledge.json`
- Create: `src/knowledge/*/SKILL.md`
- Create as mapped: `src/knowledge/*/references/**`
- Create as mapped: `src/knowledge/*/scripts/**`
- Extend: `tests/kinglet/test_content_import.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Add knowledge-specific failing tests**

Assert the exact 39 `(category, slug)` pairs from Task 1, asset hash preservation, executable bits on scripts, relative-link closure, rejection of links escaping a knowledge unit, and descriptions containing both an action and a trigger context.

Add a collision test proving canonical `knowledge.unity-instincts` and future `workflow.unity-instincts` are distinct while their Codex output names must differ.

- [ ] **Step 2: Extend the importer for complete skill trees**

Run:

```bash
python3 -m tools.kinglet_build.import_legacy --kind knowledge
```

For each legacy `SKILL.md`, move client-neutral `name`/`description` into `knowledge.json` as `public_name` and `summary`. Preserve the remaining body in canonical `SKILL.md`. Copy only referenced files under that skill's legacy directory into `references/` or `scripts/`; reject unclassified extra files instead of silently dropping them.

Descriptors set `category` to `core`, `gameplay`, `genre`, `systems`, or `third-party`. Preserve original provenance per file, including independently sourced reference files.

- [ ] **Step 3: Review discovery quality**

Generate `migration/knowledge-discovery-report.json` with one row per knowledge ID containing its summary, positive trigger nouns, neighboring skills, and collision result. The validator rejects an empty trigger set or identical normalized summaries.

Review these high-risk neighbors explicitly:

- `serialization-safety` vs `save-system`;
- `object-pooling` vs `addressables`;
- `event-systems` vs `state-machine`;
- `ui-toolkit` vs `textmeshpro`;
- `unity-mcp-patterns` vs the Plan 03 workflow router.

- [ ] **Step 4: Verify and commit**

Run:

```bash
python3 -m tools.kinglet_build validate
python3 -m unittest tests.kinglet.test_content_import -v
```

Expected: 39 knowledge units load, every relative reference resolves, and no asset is unclassified.

Commit:

```bash
git add src/knowledge migration/knowledge-discovery-report.json tests/kinglet tools/kinglet_build provenance.tsv
git commit -m "feat: migrate Kinglet knowledge library"
```

## Task 4: Render Behavior-Preserving Claude Content

**Files:**

- Create: `tools/kinglet_build/renderers/claude_content.py`
- Create: `tests/kinglet/test_claude_content.py`
- Generate: `packages/claude/.claude/rules/**`
- Generate: `packages/claude/.claude/templates/**`
- Generate: `packages/claude/.claude/skills/**`
- Regenerate: `.claude/rules/**`
- Regenerate: `.claude/templates/**`
- Regenerate: `.claude/skills/**`
- Modify: `tools/kinglet_build/renderers/__init__.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Write Claude compatibility goldens**

For all 60 migrated units, assert:

- the generated relative path equals `content-inventory.json`;
- public `name` and `description` frontmatter remain compatible;
- operational body sections and fenced examples remain present;
- all relative links resolve inside the generated package;
- scripts retain executable bits;
- the generated file records canonical source IDs in `.kinglet-generated.json`;
- output contains no `3.0.0-dev.1` timestamp or machine-specific path.

Use semantic frontmatter comparison plus exact body comparison after normalizing line endings. Intentional client-neutral wording changes must be recorded in a checked-in golden exception map with old text hash, new text hash, and reason.

- [ ] **Step 2: Implement category-owned render targets**

Extend the renderer result with a declared target key so the compatibility mirror can atomically replace only these complete subtrees:

```text
.claude/rules
.claude/templates
.claude/skills
```

The same render pass produces corresponding paths beneath `packages/claude/.claude/`. It must not read the compatibility mirror or touch `.claude/agents`, `.claude/commands`, `.claude/hooks`, or `.claude/settings.json`.

- [ ] **Step 3: Build twice and compare**

Run:

```bash
python3 -m tools.kinglet_build build --claude
python3 -m tools.kinglet_build build --claude --check
python3 -m unittest tests.kinglet.test_claude_content -v
```

Expected: first build owns exactly the three migrated categories; check mode reports zero drift; Claude compatibility tests cover all 60 units.

- [ ] **Step 4: Commit canonical and generated output together**

```bash
git add tools/kinglet_build packages/claude .claude/rules .claude/templates .claude/skills tests/kinglet provenance.tsv
git commit -m "feat: generate Claude content from Kinglet core"
```

## Task 5: Render Native Codex Knowledge, Rules, and Templates

**Files:**

- Create: `tools/kinglet_build/renderers/codex_content.py`
- Create: `tests/kinglet/test_codex_content.py`
- Create: `tests/kinglet/test_content_parity.py`
- Generate: `plugins/kinglet-unity/skills/knowledge-*/SKILL.md`
- Generate as needed: `plugins/kinglet-unity/skills/knowledge-*/references/**`
- Generate as needed: `plugins/kinglet-unity/skills/knowledge-*/scripts/**`
- Generate: `plugins/kinglet-unity/references/templates/**`
- Generate: `packages/codex-project/AGENTS.md`
- Modify: `tools/kinglet_build/renderers/__init__.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Write native-output tests before the renderer**

Assert:

- exactly 39 directories named `knowledge-<slug>` exist under the plugin;
- every `SKILL.md` has only Codex-supported `name` and `description` frontmatter;
- descriptions identify when the skill should be selected implicitly;
- the body contains no Claude slash-command requirement or Claude-only tool name;
- the 15 templates are available at stable plugin-relative paths;
- `packages/codex-project/AGENTS.md` contains a generated `kinglet-unity:generated` block with all six rule IDs and instructions to consult template references;
- no generated project file claims native Windows support.

- [ ] **Step 2: Implement the Codex renderer**

Knowledge skill names are exactly `knowledge-<slug>`. Preserve all relative references by rewriting links relative to the new skill directory. Scripts remain local to their skill. Rules are compiled into one deterministic project block ordered by canonical rule ID; scoped rules state their scope in prose rather than pretending Codex has Claude's rule-file loader.

Template references are placed at `plugins/kinglet-unity/references/templates/<output_name>`. The AGENTS block tells the agent to copy from that directory through installed project bootstrap paths defined in Plan 05.

- [ ] **Step 3: Add cross-client semantic parity**

For each canonical ID, compare both rendered products against a machine-readable `content-capabilities.json` generated from the graph. A row includes ID, support state, generated paths, required references, scripts, and behavioral assertions. `supported` requires both clients to expose every assertion; `exception` requires its named test; `unsupported` must show an end-user-visible reason.

- [ ] **Step 4: Build, verify, and commit**

Run:

```bash
python3 -m tools.kinglet_build build --all
python3 -m tools.kinglet_build build --all --check
python3 -m unittest tests.kinglet.test_codex_content tests.kinglet.test_content_parity -v
bash scripts/check-provenance.sh
```

Expected: 39 Codex knowledge skills, 15 template references, and six compiled project rules pass parity.

Commit:

```bash
git add tools/kinglet_build plugins/kinglet-unity packages/codex-project packages/claude .claude tests/kinglet provenance.tsv
git commit -m "feat: generate Codex content from Kinglet core"
```

## Task 6: Remove the Migrated Legacy Sources as Human-Owned Inputs

**Files:**

- Modify: `CLAUDE.md`
- Create: `docs/maintainers/canonical-content.md`
- Create: `tests/kinglet/test_no_content_backflow.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test that generated content cannot become source**

Monkeypatch file access in the builder and fail if it reads beneath `packages/`, `plugins/`, or the root `.claude/` compatibility categories while loading/rendering. Also fail if a generated file lacks its source-ID manifest entry.

- [ ] **Step 2: Document the contributor contract**

Explain exact edit locations, descriptor/body responsibilities, importer's one-use migration purpose, commands for validate/build/check, golden-exception review, and the prohibition on direct edits to generated content. Update repository `CLAUDE.md` to point contributors to `src/` for migrated categories while keeping current instructions for unmigrated roles, commands, and hooks.

- [ ] **Step 3: Run the phase gate**

```bash
bash tests/test-kinglet-build.sh
bash tests/run-tests.sh
python3 -m tools.kinglet_build validate
python3 -m tools.kinglet_build build --all --check
bash scripts/check-provenance.sh
```

Expected: all pass and `git diff --exit-code -- packages plugins .claude/skills .claude/rules .claude/templates` is clean.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md docs/maintainers tests/kinglet provenance.tsv
git commit -m "docs: establish Kinglet canonical content workflow"
```

## Plan 02 Completion Gate

Plan 03 may start only when:

- all 60 migrated units have exact inventory mappings and canonical provenance;
- Claude generated output passes the legacy behavior goldens;
- Codex exposes 39 discoverable knowledge skills, six rules, and 15 templates;
- all generated references resolve and executable assets preserve modes;
- the builder performs no read from a generated product or compatibility mirror;
- only unmigrated `.claude/agents`, `.claude/commands`, and hook/settings content remain human-owned temporarily.
