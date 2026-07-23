# Kinglet Roles, Workflows, and Natural-Language Router Implementation Plan

> **Superseded:** Historical plan; do not execute. The approved platform redesign starts with
> `2026-07-23-kinglet-00-plan-suite.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Canonicalize all 28 roles and 36 workflows, render native Claude and Codex execution surfaces, and make reliable natural-language workflow selection the primary UX on both clients.

**Architecture:** Canonical role contracts declare capabilities, reasoning tier, and evidence; workflow contracts declare stages, participants, mutation authority, artifacts, and failure behavior. The routing catalog connects user intents to workflows through positive examples and negative boundaries. Both adapters generate a broad router skill plus an always-loaded project instruction that must record a session-bound selection before workflow execution. Explicit Claude slash commands and Codex skill mentions use the same selection contract as natural language.

**Tech Stack:** Plan 01/02 Python builder, JSON/Markdown canonical units, Claude agents/commands/skills, Codex plugin skills and custom-agent TOML, `unittest`, model-assisted release eval fixtures.

## Global Constraints

- Execute after Plan 02's completion gate.
- Natural language is primary. Claude `/unity-*`, Codex `$kinglet-unity:<skill>`, and Codex `/skills` are optional explicit selectors.
- Preserve all existing Claude command names and intended role behavior.
- Do not generate deprecated Codex custom prompts.
- Every Unity request routes before investigation or mutation. High-confidence natural routes proceed; medium/low routes ask one focused clarification.
- Explicit selectors record confidence `high` and source `explicit` but do not bypass safety hooks.
- A selection is valid only for its client, session, request digest, and workflow capability set.
- Workflow completion clears selection. An abandoned selection may not authorize the next user request.
- Release routing threshold is at least 95% overall. Every safety-critical or mutating prompt must select the expected workflow or clarify. Any wrong mutating route blocks release.
- Canonical roles use `fast`, `balanced`, or `deep`; native model identifiers remain only in adapter profiles.
- Role rendering defaults to the `standard` agent profile. `frontier` changes only `deep` native role files and is never selected by routing or by the user's main-session model.
- Generated guidance must not set, recommend switching, or claim ownership of the Claude/Codex main-session model.
- Every new tracked file receives one `provenance.tsv` row in its task commit.

## Dependency and File Map

```text
migration/role-workflow-inventory.json                  Exact legacy mapping
tools/kinglet_build/renderers/claude_roles.py           Claude agent renderer
tools/kinglet_build/renderers/codex_roles.py            Codex custom-agent renderer
tools/kinglet_build/renderers/claude_workflows.py       Claude commands/workflow skills
tools/kinglet_build/renderers/codex_workflows.py        Codex plugin workflow skills
tools/kinglet_build/renderers/router.py                 Shared router content renderer
src/roles/<slug>/{role.json,instructions.md}            28 role units
src/workflows/<slug>/{workflow.json,instructions.md}    36 workflow units
src/catalog/routing.json                                36 route contracts
src/templates/workflow-selection/**                     Selection-state JSON schema/template
packages/claude/.claude/agents/**                       Generated Claude agents
packages/claude/profiles/frontier/.claude/agents/**     Generated deep-role overlay
packages/claude/.claude/commands/**                     Generated slash commands
packages/claude/.claude/skills/kinglet-router/**         Generated Claude router skill
plugins/kinglet-unity/skills/kinglet-router/**           Generated Codex router skill
plugins/kinglet-unity/skills/<workflow-slug>/**          Generated Codex workflows
packages/codex-project/.codex/agents/kinglet-*.toml      Generated Codex agents
packages/codex-project/profiles/frontier/.codex/agents/** Generated deep-role overlay
packages/{claude,codex-project}/**/project-guidance     Always-loaded routing contract
.claude/{agents,commands}                                Temporary compatibility mirror
tests/kinglet/test_role_workflow_inventory.py            Exact inventory tests
tests/kinglet/test_role_contracts.py                     Capability/evidence tests
tests/kinglet/test_workflow_contracts.py                 Stage/mutation tests
tests/kinglet/test_role_renderers.py                     Native-role output tests
tests/kinglet/test_workflow_renderers.py                 Native-workflow output tests
tests/kinglet/routing-cases.json                         Deterministic routing corpus
tests/kinglet/test_routing_catalog.py                    Static routing gates
tests/evals/routing/**                                   Live-client eval protocol
```

## Task 1: Freeze the 28-Role and 36-Workflow Migration Map

**Files:**

- Create: `migration/role-workflow-inventory.json`
- Create: `tests/kinglet/test_role_workflow_inventory.py`
- Extend: `tools/kinglet_build/import_legacy.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Assert exact role identity**

The test uses this sorted role set, not a count-only assertion:

```text
creative-director game-designer level-designer narrative-director systems-designer
technical-director unity-build-runner unity-coder unity-coder-lite unity-critic
unity-fixer unity-fixer-lite unity-git-master unity-linter unity-migrator
unity-network-dev unity-optimizer unity-prototyper unity-reviewer unity-scene-builder
unity-scout unity-security-reviewer unity-shader-dev unity-test-runner unity-ui-builder
unity-verifier world-builder writer
```

Each maps `.claude/agents/<slug>.md` to `src/roles/<slug>/` and records its Plan 01 SHA-256, provenance, generated Claude path, and generated Codex TOML path `packages/codex-project/.codex/agents/kinglet-<slug>.toml`.

- [ ] **Step 2: Assert exact workflow identity**

The test uses this sorted workflow set:

```text
brainstorm design-review design-system estimate map-systems milestone-review retrospective
scope-check sprint-plan unity-audit unity-build unity-doctor unity-feature unity-fix unity-init
unity-instincts unity-interview unity-learn unity-migrate unity-network unity-optimize unity-profile
unity-prototype unity-ralph unity-review unity-scene unity-session-resume unity-session-save
unity-sessions unity-shader unity-skill-stocktake unity-skillify unity-team unity-test unity-ui
unity-workflow
```

Each maps `.claude/commands/<slug>.md` to `src/workflows/<slug>/`, preserves the public Claude command `/<slug>`, and assigns Codex plugin skill `<slug>`.

- [ ] **Step 3: Extend the importer and prove all-or-nothing behavior**

Support `--kind role` and `--kind workflow`. Parse current agent/command frontmatter with the restricted codec. Convert model names to canonical reasoning tiers via the Claude adapter profile. Convert tool lists to canonical capabilities and reject a native tool that lacks a profile mapping.

Run:

```bash
python3 -m unittest tests.kinglet.test_role_workflow_inventory -v
```

Expected: exact lists, hashes, and mappings pass; one deleted or extra legacy file fails.

- [ ] **Step 4: Commit**

```bash
git add migration/role-workflow-inventory.json tools/kinglet_build/import_legacy.py tests/kinglet provenance.tsv
git commit -m "test: freeze Kinglet role and workflow map"
```

## Task 2: Import and Normalize the 28 Role Contracts

**Files:**

- Create: `src/roles/*/role.json`
- Create: `src/roles/*/instructions.md`
- Create: `tests/kinglet/test_role_contracts.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Write role-contract tests before import**

For every role, require non-empty `summary`, `capabilities`, `reasoning_tier`, and `evidence`. Assert:

- design-only roles do not claim `filesystem.write`, `unity.write`, or shell mutation;
- `unity-scout` is read-only;
- coder/fixer/builder roles that mutate declare `filesystem.write` or `unity.write`;
- `unity-scene-builder` declares `unity.read`, `unity.write`, and `scene-state-readback` evidence;
- `unity-test-runner` declares `unity.read` and `unity-tests-pass` evidence;
- `unity-verifier` declares `console-clean`, `unity-tests-pass`, and `scene-state-readback` as applicable evidence rather than broad write permission;
- lite/full pairs have distinct summaries and tiers but the same safety rules;
- no role instruction names a current model.

- [ ] **Step 2: Import roles and review native-to-logical mappings**

Run:

```bash
python3 -m tools.kinglet_build.import_legacy --kind role
python3 -m tools.kinglet_build validate
```

Preserve the reviewed legacy tier intent exactly:

- `fast`: `unity-linter`, `unity-scout`;
- `balanced`: `level-designer`, `systems-designer`, `unity-build-runner`, `unity-coder-lite`, `unity-fixer-lite`, `unity-git-master`, `unity-migrator`, `unity-reviewer`, `unity-security-reviewer`, `unity-test-runner`, `world-builder`, `writer`;
- `deep`: `creative-director`, `game-designer`, `narrative-director`, `technical-director`, `unity-coder`, `unity-critic`, `unity-fixer`, `unity-network-dev`, `unity-optimizer`, `unity-prototyper`, `unity-scene-builder`, `unity-shader-dev`, `unity-ui-builder`, `unity-verifier`.

Lite roles are therefore `balanced`, not `fast`. When legacy frontmatter and body disagree, preserve the safer capability set and record the normalization in `migration/role-normalizations.json` with role ID, old hash, changed field, and reason.

- [ ] **Step 3: Define delegation-safe instructions**

Every role body must state its responsibility, allowed changes, required inputs, evidence it returns, and stop conditions. Roles never acquire Unity write authority merely because their client supports MCP. A delegated role returns evidence to its orchestrating workflow and does not mark the workflow complete itself.

- [ ] **Step 4: Verify and commit**

```bash
python3 -m unittest tests.kinglet.test_role_contracts -v
python3 -m tools.kinglet_build validate
git add src/roles migration/role-normalizations.json tests/kinglet provenance.tsv
git commit -m "feat: migrate Kinglet role contracts"
```

## Task 3: Import and Complete the 36 Workflow Contracts

**Files:**

- Create: `src/workflows/*/workflow.json`
- Create: `src/workflows/*/instructions.md`
- Create as mapped: `src/workflows/*/references/**`
- Create: `tests/kinglet/test_workflow_contracts.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test workflow invariants**

Require every workflow to declare ordered stages from `investigate`, `clarify`, `design`, `plan`, `implement`, `verify`, and `report`; at least one role; rules/knowledge; inputs; artifacts; completion evidence; failure behavior; `mutation`; and both client support states.

Assert these safety classifications:

- read-only: `design-review`, `estimate`, `scope-check`, `unity-audit`, `unity-doctor`, `unity-profile`, `unity-review`, `unity-sessions`, `unity-skill-stocktake`;
- project/document writes but no Unity mutation: `brainstorm`, `design-system`, `map-systems`, `milestone-review`, `retrospective`, `sprint-plan`, `unity-init`, `unity-instincts`, `unity-interview`, `unity-learn`, `unity-session-resume`, `unity-session-save`, `unity-skillify`;
- Unity/code mutation: `unity-build`, `unity-feature`, `unity-fix`, `unity-migrate`, `unity-network`, `unity-optimize`, `unity-prototype`, `unity-ralph`, `unity-scene`, `unity-shader`, `unity-team`, `unity-test`, `unity-ui`, `unity-workflow`.

For a classification that the imported command contradicts, stop and update the reviewed classification plus test in the same commit; do not silently grant broader authority.

- [ ] **Step 2: Import workflows**

Run:

```bash
python3 -m tools.kinglet_build.import_legacy --kind workflow
```

Normalize prose so client-specific invocation syntax is rendered by adapters. Preserve public names and detailed command behavior. Each mutating workflow begins with selection validation and ends with verification plus selection clearing. Read-only workflows still record selection for observability but need no writer lease.

- [ ] **Step 3: Add explicit completion evidence**

At minimum:

- code changes: `console-clean` and relevant Unity tests;
- scene/prefab changes: `scene-state-readback` and `screenshot-reviewed` when visual;
- builds: successful build result and post-build console read;
- documentation/design: written artifact path and references validation;
- profiling/optimization: before/after measurement from the same scenario;
- bug fixes: reproduced-before and absent-after evidence.

Evidence requirements are data in `workflow.json`; the body explains collection, not a weaker substitute.

- [ ] **Step 4: Verify and commit**

```bash
python3 -m unittest tests.kinglet.test_workflow_contracts -v
python3 -m tools.kinglet_build validate
git add src/workflows tests/kinglet provenance.tsv
git commit -m "feat: migrate Kinglet workflow contracts"
```

## Task 4: Render Client-Native Roles

**Files:**

- Create: `tools/kinglet_build/renderers/claude_roles.py`
- Create: `tools/kinglet_build/renderers/codex_roles.py`
- Create: `tests/kinglet/test_role_renderers.py`
- Generate: `packages/claude/.claude/agents/*.md`
- Generate: `packages/claude/profiles/frontier/.claude/agents/*.md`
- Generate: `packages/codex-project/.codex/agents/kinglet-*.toml`
- Generate: `packages/codex-project/profiles/frontier/.codex/agents/kinglet-*.toml`
- Regenerate: `.claude/agents/*.md`
- Modify: `tools/kinglet_build/renderers/__init__.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test Claude role compatibility**

Assert exact 28-path standard coverage, public names/descriptions, allowed-tool equivalence through the Claude profile, the 2/12/14 tier partition above, body safety sections, and no loss of legacy operational content. Standard frontmatter resolves `fast|balanced|deep` to `haiku|sonnet|opus`. The frontier overlay contains exactly the 14 `deep` agents with `model: fable`; it contains no fast/balanced file. `.claude/agents` becomes a complete category-owned compatibility target and remains standard.

- [ ] **Step 2: Test valid Codex custom-agent TOML**

Parse all 28 standard files with `tomllib`. Assert each file has a generated name, canonical source ID, description, exact model/effort from the Codex standard profile (`Luna/medium`, `Terra/medium`, or `Sol/high`), native sandbox policy consistent with capabilities, and instructions preserving scope/evidence/stop conditions. Read-only roles must not get a write-enabled sandbox.

The frontier overlay contains exactly the 14 `deep` TOML files, each with `model = "gpt-5.6-sol"` and `model_reasoning_effort = "max"`, plus a generated manifest requirement for native `reasoning.mode.pro`. The renderer emits a Pro binding only when it is a validated native field or documented inheritance mode from the Codex adapter; it never invents a TOML key or substitutes prompt prose. A synthetic adapter fixture without a valid Pro binding must still render standard but must mark frontier non-activatable for Plan 05.

- [ ] **Step 3: Implement both renderers and verify twice**

```bash
python3 -m tools.kinglet_build build --all
python3 -m tools.kinglet_build build --all --check
python3 -m unittest tests.kinglet.test_role_renderers -v
```

Expected: both clients expose 28 standard roles and 14 frontier deep-role overlays; no native model name leaks into canonical role source; no generated file sets a main-session model; check mode is clean.

- [ ] **Step 4: Commit**

```bash
git add tools/kinglet_build packages/claude packages/codex-project .claude/agents tests/kinglet provenance.tsv
git commit -m "feat: generate native Kinglet roles"
```

## Task 5: Build the Routing Catalog and Selection-State Contract

**Files:**

- Modify: `src/catalog/routing.json`
- Create: `src/templates/workflow-selection/template.json`
- Create: `src/templates/workflow-selection/content.md`
- Create: `tests/kinglet/routing-cases.json`
- Create: `tests/kinglet/test_routing_catalog.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Write structural routing tests**

Require exactly one route per 36 workflow IDs. Every route contains:

- `intent_id`, `workflow_id`, and priority;
- at least three natural-language positive examples, including one Turkish or another non-English example for every Unity-mutating workflow;
- at least two negative boundaries naming the competing workflow;
- disambiguation question and answer-to-route mapping when overlap exists;
- safety class `read`, `project-write`, or `unity-write`.

Reject duplicate normalized examples, substring-only descriptions, negative examples that are also positive elsewhere without a clarification rule, and a mutation safety class inconsistent with the workflow.

- [ ] **Step 2: Encode high-risk boundaries explicitly**

The routing corpus must include these distinctions:

| User intent | Expected behavior |
|---|---|
| create production feature | `unity-feature`, not `unity-prototype` |
| fastest throwaway playable mechanic | `unity-prototype` |
| diagnose known bug | `unity-fix`, not `unity-review` |
| review code without changing it | `unity-review` |
| build or edit scene hierarchy | `unity-scene`, not generic `unity-feature` |
| create a UI screen | `unity-ui`, unless the request is only design documentation |
| write/run tests | `unity-test` |
| repeatedly fix until clean | `unity-ralph` |
| measure only | `unity-profile`; optimize after measurement | `unity-optimize` |
| full health audit | `unity-audit`; setup/connectivity diagnosis | `unity-doctor` |
| broad end-to-end delivery | `unity-workflow`; isolated implementation | `unity-feature` |
| ambiguous “make it better” | clarification, no mutating route |
| destructive project-setting request | clarification plus protected workflow, never direct mutation |

Add negative controls for ordinary conversation, Git-only questions, non-Unity repositories, requests to explain Kinglet, and prompts containing workflow words only as quoted text.

- [ ] **Step 3: Define exact state JSON**

The workflow-selection template documents this complete payload:

```json
{
  "schema_version": 1,
  "client": "codex",
  "session_id": "session-018f6c6f",
  "workflow_id": "workflow.unity-feature",
  "source": "natural-language",
  "confidence": "high",
  "reason": "The user requested implementation of a production Unity feature.",
  "needs_clarification": false,
  "selected_at": "2026-07-22T12:00:00Z",
  "request_sha256": "8db0f03b8b8d9f665ad231bfbcf5c0b7f117e65909849e440db3c62f66d6347a"
}
```

Allowed clients are `claude` and `codex`; sources are `natural-language`, `explicit`, and `clarification`; confidence is `high`, `medium`, or `low`; timestamps are UTC RFC 3339; request digests are lowercase SHA-256. Medium/low always sets `needs_clarification: true` and grants no workflow authority.

- [ ] **Step 4: Complete and test all 36 routes**

Populate at least 216 cases: three positives and two negatives per route plus 36 cross-route ambiguity/negative controls. The static test proves internal consistency; it does not pretend to measure a live model.

Run:

```bash
python3 -m unittest tests.kinglet.test_routing_catalog -v
python3 -m tools.kinglet_build validate
```

Expected: 36 routes and at least 216 unique cases pass.

- [ ] **Step 5: Commit**

```bash
git add src/catalog/routing.json src/templates/workflow-selection tests/kinglet provenance.tsv
git commit -m "feat: define Kinglet natural-language routing"
```

## Task 6: Render Workflows, Router Skills, and Always-Loaded Guidance

**Files:**

- Create: `tools/kinglet_build/renderers/claude_workflows.py`
- Create: `tools/kinglet_build/renderers/codex_workflows.py`
- Create: `tools/kinglet_build/renderers/router.py`
- Create: `tests/kinglet/test_workflow_renderers.py`
- Generate: `packages/claude/.claude/commands/*.md`
- Generate: `packages/claude/.claude/skills/kinglet-router/SKILL.md`
- Generate: `plugins/kinglet-unity/skills/<workflow-slug>/SKILL.md`
- Generate: `plugins/kinglet-unity/skills/kinglet-router/SKILL.md`
- Generate: project-guidance managed blocks for Claude and Codex packages
- Regenerate: `.claude/commands/*.md`
- Modify: `tools/kinglet_build/renderers/__init__.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test all native public surfaces**

Claude tests require 36 existing command paths and `/slug` names. Codex tests require 36 plugin workflow skills named by slug and no `/prompts:*` output. Both router skills must carry all 36 route summaries, selection-state instructions, clarification rule, session binding, and completion clearing.

The end-user `CLAUDE.md` and `AGENTS.md` managed blocks begin with the same invariant: every Unity task routes through Kinglet before investigation or mutation. They explain that users may speak naturally; they do not tell users to memorize command syntax.

- [ ] **Step 2: Render explicit selectors through the same state contract**

Every Claude command and Codex workflow skill starts by selecting its own canonical workflow ID with source `explicit`, confidence `high`, and the current request digest. It then follows canonical stages and ends by clearing only its own session-bound selection. Plan 04 supplies the hook/runtime mechanics; until then generated instructions state the contract and integration tests expect a missing-runtime diagnostic rather than silently continuing.

- [ ] **Step 3: Build and verify**

```bash
python3 -m tools.kinglet_build build --all
python3 -m tools.kinglet_build build --all --check
python3 -m unittest tests.kinglet.test_workflow_renderers -v
```

Expected: 36 Claude commands, 36 Codex workflow skills, two router skills, and two always-loaded guidance blocks pass.

- [ ] **Step 4: Commit**

```bash
git add tools/kinglet_build packages plugins .claude/commands tests/kinglet provenance.tsv
git commit -m "feat: generate Kinglet workflows and router"
```

## Task 7: Add Live Routing Evaluation Without Faking Determinism

**Files:**

- Create: `tests/evals/routing/README.md`
- Create: `tests/evals/routing/evaluate.py`
- Create: `tests/evals/routing/schema.json`
- Create: `tests/evals/routing/fixtures/**`
- Create: `tests/kinglet/test_routing_evaluator.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test the evaluator against recorded responses**

The evaluator reads JSONL records containing client, prompt ID, expected workflows, clarification allowance, safety class, selected workflow, confidence, and whether mutation began. It calculates overall accuracy, mutating accuracy, clarification correctness, false-mutating routes, and per-client deltas.

It exits nonzero when overall accuracy is below 95%, a safety-critical/mutating case is neither correct nor clarification, any negative control enters a mutating workflow, or any wrong mutating route occurs.

- [ ] **Step 2: Document the live-client protocol**

Run the identical prompt corpus in fresh Claude and Codex sessions against a disposable minimal Unity fixture. Capture only structured selection JSON before allowing workflow execution. Do not manually choose skills, add hints, or reuse conversational context between cases. Record client/model/plugin versions in the JSONL metadata.

The script intentionally does not call vendor APIs in unit CI. Plan 06 runs this protocol on current supported client releases and commits the signed result summary.

- [ ] **Step 3: Verify evaluator behavior and commit**

```bash
python3 -m unittest tests.kinglet.test_routing_evaluator -v
python3 tests/evals/routing/evaluate.py tests/evals/routing/fixtures/passing.jsonl
! python3 tests/evals/routing/evaluate.py tests/evals/routing/fixtures/wrong-mutation.jsonl
```

Expected: passing fixture exits `0`; wrong mutation fixture exits nonzero with `release blocker: wrong mutating route`.

Commit:

```bash
git add tests/evals tests/kinglet provenance.tsv
git commit -m "test: add Kinglet routing release evaluator"
```

## Plan 03 Completion Gate

Plan 04 may start only when:

- all 28 roles and 36 workflows exist once in canonical source;
- Claude preserves 28 native agents and 36 slash commands;
- Codex exposes 28 valid custom agents and 36 plugin workflow skills;
- both always-loaded project blocks require routing before Unity work;
- all static routing cases pass and the live evaluator correctly rejects wrong mutation;
- root `.claude/agents` and `.claude/commands` are generated compatibility categories;
- root `.claude/hooks` and settings remain the only unmigrated behavioral source.
