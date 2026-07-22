# Kinglet Product, Brownfield Validation, and 3.0.0 Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the Kinglet product rename, prove Claude/Codex behavioral parity on synthetic and live Unity projects—including the user's existing bug-bearing brownfield project—and publish reproducible Kinglet for Unity 3.0.0 artifacts.

**Architecture:** Generated capability/parity manifests become the release truth. Synthetic suites remain the fast deterministic safety net; live routing and Unity scenarios verify native clients; a hermetic brownfield harness creates disposable Claude and Codex clones from one immutable baseline commit and compares observable outcomes rather than prose or code shape. Only after every release blocker is clear does one root version render final packages, documentation, checksums, and tag-ready archives.

**Tech Stack:** Plans 01–05 build/runtime, Bash 3.2, Python standard library evaluators, Unity 6, CoplayDev MCP for Unity v10.1.0, current supported Claude Code and Codex releases, GitHub Actions on Ubuntu/macOS.

## Global Constraints

- Execute after Plan 05's completion gate.
- Test the user's brownfield project only through disposable local clones. Never install into, reset, clean, checkout, or mutate the original source directory.
- Claude and Codex clones start at the same immutable Git commit, Unity/package state, test state, console baseline, and Kinglet version.
- Reset to a fresh clone between scenarios; do not reuse editor/session state.
- Give both clients the same natural-language request and acceptance oracle. Do not reveal the known solution to either client.
- Compare required stages, safety, project outcome, console/tests, scene readback, screenshots, user-file preservation, and evidence. Do not require identical prose, diff, role count, or implementation style.
- Routing must score at least 95% overall; every mutating/safety-critical case must be correct or clarify; any wrong mutating route blocks release.
- Every supported workflow/capability must have equivalent Claude and Codex behavior. Exceptions require visible reason, owner, and named passing test.
- The only supported first-release hosts are Linux and macOS. Windows must be visibly `unsupported`, never absent.
- Product-facing text uses `Kinglet`, `Kinglet for Unity`, `kinglet-unity`, and `Multi-agent toolkit for Unity 6`. Historical attribution keeps prior names where truthful.
- Include Unity trademark attribution and state that Kinglet is not affiliated with Unity Technologies.
- Promote `VERSION` from `3.0.0-dev.1` to `3.0.0` only after every pre-release gate passes.
- External repository rename and release publication are explicit maintainer actions; scripts prepare and verify them but do not perform them silently.
- Every new tracked file receives one `provenance.tsv` row in its task commit.

## Dependency and File Map

```text
README.md                                      Dual-client product landing page
docs/GETTING-STARTED.md                       Claude/Codex/all setup
docs/ARCHITECTURE.md                          Canonical graph and native adapters
docs/AGENT-GUIDE.md                           Natural language, roles, explicit selectors
docs/HOOK-REFERENCE.md                        Normalized safety/runtime reference
docs/MODEL-ROUTING.md                         Adapter tiers and routing contract
docs/SKILL-CATALOG.md                         Generated public capability catalog
MCP-SETUP.md                                   Pinned v10.1.0 bridge setup
CONTRIBUTING.md                               Canonical maintainer workflow
NOTICE.md                                     Trademark and distribution notices
CREDITS.md / MERGE-NOTES.md / provenance.tsv  Preserved history
tools/kinglet_build/renderers/reports.py       Capability/parity/support reports
packages/reports/capability-matrix.json        Machine release matrix
packages/reports/capability-matrix.md          Human release matrix
packages/reports/parity-manifest.json          Normalized behavior contract
packages/reports/support-matrix.json           Host/client/exception contract
tests/release/test-brand.sh                    Active-name/trademark tests
tests/release/test_parity.py                   Supported behavior equality
tests/release/test-artifacts.sh                Archive/checksum tests
tests/evals/live-unity/**                      Seeded Unity scenario protocol
scripts/pilot/prepare-brownfield.sh            Safe equal-baseline clone preparation
scripts/pilot/capture-baseline.sh              Unity/package/test/config snapshot
scripts/pilot/reset-clone.sh                    Scenario reset with safety guards
scripts/pilot/evaluate-results.py              Observable outcome comparison
tests/pilot/**                                  Harness fixtures and unit tests
docs/releases/3.0.0-brownfield-report.md        Reviewed real-project results
docs/releases/3.0.0-routing-report.md           Live client routing results
docs/releases/3.0.0-unity-parity-report.md      Live Unity results
docs/releases/3.0.0-release-checklist.md        Signed release evidence index
scripts/build-release.sh                       Reproducible archive/checksum builder
.github/workflows/release.yml                   Tag artifact verification
VERSION                                        Final release version
```

## Task 1: Complete the Public Kinglet Rename Without Rewriting History

**Files:**

- Modify: `README.md`
- Modify: `docs/GETTING-STARTED.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/AGENT-GUIDE.md`
- Modify: `docs/HOOK-REFERENCE.md`
- Modify: `docs/MODEL-ROUTING.md`
- Modify: `docs/SKILL-CATALOG.md`
- Modify: `MCP-SETUP.md`
- Modify: `CONTRIBUTING.md`
- Modify: `CLAUDE.md`
- Create: `NOTICE.md`
- Create: `tests/release/test-brand.sh`
- Modify: `provenance.tsv`

- [ ] **Step 1: Write the active-brand allow/deny test**

Scan active product/code/docs while exempting `CREDITS.md`, `MERGE-NOTES.md`, `provenance.tsv`, `provenance-skip.tsv`, migration inventories/fixtures, historical release notes, and explicit legacy-marker tests. Fail active uses of:

```text
cloud-nine-unity Cloud Nine Unity ECU Claude-only toolkit
```

Allow “Claude” when identifying the supported client or native syntax, not as the product identity. Require `Kinglet for Unity`, `kinglet-unity`, and the tagline in README/package/plugin surfaces.

- [ ] **Step 2: Rewrite documentation around the two equal clients**

README leads with outcomes and natural-language examples for both clients. It shows:

- Claude default install and optional `/unity-*` selectors;
- Codex marketplace/plugin setup, implicit skills, optional `$kinglet-unity:*`, and `/skills` discovery;
- source/archive `--client codex|all` paths;
- pinned MCP registration as a visible user step;
- Linux/macOS support and Windows unsupported status;
- user-ownership upgrade behavior and doctor command.

Architecture and contributor docs point to `src/` as the only human-authored shared source and `packages/`/`plugins/` as generated output. Remove instructions to edit root `.claude/`.

- [ ] **Step 3: Preserve attribution and add trademark language**

Do not rewrite prior product/upstream history in credits, merge notes, provenance, or migration evidence. Add `NOTICE.md` and render it into both distributions. State in README and distributed notices that Unity is a trademark of Unity Technologies and Kinglet is not affiliated with or endorsed by Unity Technologies. Keep `LICENSE` and all upstream licenses intact.

- [ ] **Step 4: Verify and commit**

```bash
bash tests/release/test-brand.sh
bash scripts/check-provenance.sh
git add README.md docs MCP-SETUP.md CONTRIBUTING.md CLAUDE.md NOTICE.md packages plugins tests/release provenance.tsv
git commit -m "docs: rename product to Kinglet for Unity"
```

## Task 2: Generate the Capability, Parity, and Support Matrices

**Files:**

- Create: `tools/kinglet_build/renderers/reports.py`
- Create: `tests/release/test_parity.py`
- Generate: `packages/reports/capability-matrix.json`
- Generate: `packages/reports/capability-matrix.md`
- Generate: `packages/reports/parity-manifest.json`
- Generate: `packages/reports/support-matrix.json`
- Modify: `tools/kinglet_build/renderers/__init__.py`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test normalized parity before rendering reports**

For every canonical role, workflow, knowledge unit, rule, hook policy, and template, normalize both clients into rows containing:

```text
canonical_id support stages capabilities safety_policies mcp_contract evidence artifacts
native_paths named_tests exception
```

`supported` rows must match on every behavioral field; only `native_paths` may differ. `exception` must have reason, owner, named test, and reduced behavior visible in the Markdown matrix. `unsupported` must exist for both clients when relevant and must show why.

Fail a missing row, silent field omission, stale native path, unmatched canonical ID, client model name under `src/`, moving dependency ref, Windows absence, or `supported` behavior mismatch.

- [ ] **Step 2: Render machine and human reports from the same data**

The capability matrix groups by public workflow and shows Claude selector, Codex skill, natural-language examples, roles, read/write status, MCP needs, verification evidence, and support. The support matrix covers `(client × linux|macos|windows)` plus MCP v10.1.0. Markdown is rendered from sorted JSON, not hand-maintained.

- [ ] **Step 3: Build and verify**

```bash
python3 -m tools.kinglet_build build --all
python3 -m tools.kinglet_build build --all --check
python3 -m unittest tests.release.test_parity -v
```

Expected: no supported behavioral delta and Windows appears explicitly unsupported.

- [ ] **Step 4: Commit**

```bash
git add tools/kinglet_build packages/reports tests/release provenance.tsv
git commit -m "feat: publish Kinglet capability and parity matrices"
```

## Task 3: Run the Full Synthetic Release Matrix on Linux and macOS

**Files:**

- Create: `tests/release/run-release-gate.sh`
- Modify: `.github/workflows/ci.yml`
- Modify: `provenance.tsv`

- [ ] **Step 1: Create one fail-fast local release gate**

The script runs, in this order:

```text
provenance and absence checks
canonical validation
deterministic generated check
schema/graph/renderer/parity Python tests
legacy shell suite
hook normalization/decision/selection/lease tests
MCP lock/snapshot/evidence tests
install/legacy-upgrade/rollback/uninstall/doctor tests
brand and artifact tests
```

It prints a stable section/result table and exits on the first failing gate while preserving that gate's full output. It never starts a live client or Unity editor.

- [ ] **Step 2: Run the same gate on both supported hosts**

Update CI so Ubuntu and macOS both run `bash tests/release/run-release-gate.sh`. Keep ShellCheck on every shipped shell file. On macOS, invoke system Bash 3.2 for lifecycle/runtime suites. Cache nothing that can hide generated drift or receipt state.

- [ ] **Step 3: Verify locally and commit**

```bash
bash tests/release/run-release-gate.sh
git add tests/release .github/workflows/ci.yml provenance.tsv
git commit -m "test: gate Kinglet on Linux and macOS"
```

## Task 4: Execute Live Routing Evaluation on Current Supported Clients

**Files:**

- Create: `docs/releases/3.0.0-routing-report.md`
- Create: `tests/evals/routing/results/.gitkeep`
- Modify: `provenance.tsv`

- [ ] **Step 1: Record the environment before prompts**

Record OS, Claude Code version, Codex version, native model/profile selection, Kinglet commit/version, plugin/package manifest digests, and date. Use current supported releases; if either client changed a native manifest/hook schema since implementation, stop and update the adapter plus synthetic fixtures first.

- [ ] **Step 2: Run identical isolated prompt sessions**

Execute the Plan 03 corpus in fresh sessions. Capture `.kinglet/state/workflow-selection.json` before any implementation action and terminate the case. Natural-language cases receive no command/skill hint. Explicit-selector cases are a separate small compatibility pass and do not count toward natural-language accuracy.

- [ ] **Step 3: Evaluate hard safety thresholds**

```bash
python3 tests/evals/routing/evaluate.py tests/evals/routing/results/claude-3.0.0.jsonl tests/evals/routing/results/codex-3.0.0.jsonl
```

Required results:

- combined and each-client overall accuracy at least 95%;
- every mutating/safety-critical case correct or clarification;
- zero negative controls entering a mutating workflow;
- zero wrong mutating routes;
- explicit selectors record correct workflow/source/confidence.

Flaky retries are not averaged away. A changed prompt, router, client, or model invalidates the prior result set.

- [ ] **Step 4: Write and commit the reviewed report**

The report records metrics, versions/digests, all failure IDs, disposition, and reviewer sign-off. Do not commit raw prompts containing private project data or client logs containing secrets.

```bash
git add docs/releases/3.0.0-routing-report.md tests/evals/routing/results/.gitkeep provenance.tsv
git commit -m "test: verify Kinglet live routing parity"
```

## Task 5: Run the Seeded Live Unity Parity Scenarios

**Files:**

- Create: `tests/evals/live-unity/README.md`
- Create: `tests/evals/live-unity/scenarios.json`
- Create: `tests/evals/live-unity/evaluate.py`
- Create: `tests/kinglet/test_live_unity_evaluator.py`
- Create: `docs/releases/3.0.0-unity-parity-report.md`
- Modify: `provenance.tsv`

- [ ] **Step 1: Define six resettable scenarios**

Use one small seeded Unity 6 project and these exact scenario classes:

1. read-only project audit;
2. scoped feature implementation;
3. reproduced bug investigation and fix;
4. design workflow using a task-scoped EditorSnapshot without design-role mutation;
5. destructive action blocked before mutation;
6. post-write scene, console, tests, and screenshot verification.

Each scenario declares baseline commit, natural-language prompt, allowed paths/capabilities, forbidden changes, expected artifacts, Unity test oracle, console oracle, scene query oracle, screenshot review rubric, and required evidence receipt types.

- [ ] **Step 2: Test the evaluator on synthetic records**

The evaluator rejects missing stages/evidence, stale snapshot, missing/expired/mismatched lease, protected-path mutation without selection, dirty console, failing tests, wrong scene state, absent screenshot review, forbidden paths, leaked state between scenarios, and non-identical baselines.

- [ ] **Step 3: Execute Claude and Codex from identical resets**

For each scenario, clone/reset the seed, install one client, confirm MCP v10.1.0, capture baseline, begin with natural language, then collect structured events/diff/tests/console/scene/screenshot/evidence. Run the explicit-selector smoke pass only after natural-language scenarios.

- [ ] **Step 4: Evaluate and report**

Both clients must pass every scenario. Equivalent outcome is based on the oracle, not identical implementation. The report includes version/digests, duration/tool-call counts as non-blocking efficiency data, result table, behavioral diffs, failures, and reviewer sign-off.

```bash
python3 -m unittest tests.kinglet.test_live_unity_evaluator -v
python3 tests/evals/live-unity/evaluate.py tests/evals/live-unity/results/claude.json tests/evals/live-unity/results/codex.json
git add tests/evals/live-unity tests/kinglet docs/releases/3.0.0-unity-parity-report.md provenance.tsv
git commit -m "test: verify Kinglet live Unity parity"
```

## Task 6: Build the Safe Brownfield Pilot Harness

**Files:**

- Create: `scripts/pilot/prepare-brownfield.sh`
- Create: `scripts/pilot/capture-baseline.sh`
- Create: `scripts/pilot/reset-clone.sh`
- Create: `scripts/pilot/evaluate-results.py`
- Create: `tests/pilot/test-safety.sh`
- Create: `tests/pilot/test-baseline.sh`
- Create: `tests/pilot/test_evaluator.py`
- Create fixtures: `tests/pilot/fixtures/**`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test that the harness cannot touch its source**

Fixtures prove rejection of an empty/root/home/workspace source, non-Git source, missing commit, mutable branch-only baseline, work root inside source, destination symlink, destination already containing unrelated data, same source/destination inode, and a source whose required Git objects are unavailable. Snapshot source path/inodes/hashes before and after every test and require equality.

The harness may read a dirty source repository but clones only the explicitly supplied commit; it reports ignored working-tree changes and never copies them into the baseline silently.

- [ ] **Step 2: Implement equal-baseline preparation**

`prepare-brownfield.sh` requires:

```text
--source ABSOLUTE_GIT_PATH --commit FULL_40_HEX_SHA --work-root EMPTY_ABSOLUTE_PATH --kinglet-archive ABSOLUTE_TAR_PATH
```

It creates `baseline`, `claude`, and `codex` clones using local Git clone without hardlinks, checks out the detached full commit, verifies identical tracked-tree hashes, then installs Kinglet Claude and Codex separately. It writes a harness manifest with source device/inode, commit, tree SHA, Kinglet archive SHA, Unity version, package lock digest, and clone hashes. It never runs `git clean`, `reset`, `checkout`, or Unity in the source path.

- [ ] **Step 3: Capture the pre-agent project contract**

`capture-baseline.sh` records:

- full baseline commit/tree and Git status;
- Unity version and active build target;
- `Packages/manifest.json` and lock digests;
- asmdef/scene/project-settings/custom-config path hashes;
- baseline compile result, console counts/digest, and EditMode/PlayMode results;
- known pre-existing failures distinguished from new regressions;
- ignored/generated path policy;
- user-owned CLAUDE.md/AGENTS.md/custom skills/custom agents/settings hashes.

It writes JSON only beneath the work root and verifies source remains unchanged afterward.

- [ ] **Step 4: Implement safe scenario reset**

`reset-clone.sh` operates only on a clone whose harness manifest path/inode/commit match. It terminates only the Unity process whose project path equals that clone, removes recorded generated Unity caches inside the clone, restores the clone from the baseline clone, reinstalls the selected Kinglet package, and revalidates tree/package/user-file hashes. Refuse unresolved paths or an active Kinglet writer lease.

- [ ] **Step 5: Test observable-outcome comparison**

`evaluate-results.py` compares routing record, ordered workflow stages, selected roles/capabilities, writer lease events, changed paths, Git diff, compile/console/tests, bug reproduction oracle, scene readback, screenshot review, evidence freshness, user-owned hashes, and final risk report. It allows different code/diff when both satisfy the oracle and protected/user paths remain valid.

- [ ] **Step 6: Verify and commit the harness**

```bash
bash tests/pilot/test-safety.sh
bash tests/pilot/test-baseline.sh
python3 -m unittest tests.pilot.test_evaluator -v
git add scripts/pilot tests/pilot provenance.tsv
git commit -m "test: add safe Kinglet brownfield harness"
```

## Task 7: Execute the User's Known-Bug Brownfield Pilot

**Files:**

- Create: `docs/releases/3.0.0-brownfield-report.md`
- Create outside repository: disposable pilot work root under `/tmp`
- Modify: `provenance.tsv`

- [ ] **Step 1: Receive and validate the runtime inputs**

The maintainer supplies the existing project's absolute Git path, exact baseline commit, Unity editor executable, and a reviewed acceptance-case file. Define task-specific variables only after validation:

```bash
KINGLET_PILOT_SOURCE=/absolute/path/supplied-by-the-maintainer
KINGLET_PILOT_COMMIT=$(git -C "$KINGLET_PILOT_SOURCE" rev-parse --verify 'HEAD^{commit}')
KINGLET_PILOT_WORK=$(mktemp -d /tmp/kinglet-brownfield.XXXXXX)
```

The acceptance-case file contains case ID, natural-language prompt, reproduction steps, permitted scope, forbidden paths, compile/test/console/scene oracle, and required evidence. Store the known fix separately from the agent-facing prompt and result capture. Reject a case that exposes solution code, commit, or filename hints not present in the user's natural request.

- [ ] **Step 2: Prepare same-commit Claude and Codex clones**

Build the pre-release archive, then run the harness with the validated inputs. Confirm source hash/inode snapshot is unchanged. Capture the baseline before either client session starts. The two clients must see equivalent project content and only their native Kinglet surface.

- [ ] **Step 3: Execute blind, reset-isolated cases**

For each known bug and representative maintenance task:

1. reset both clones from baseline;
2. start the matching Unity editor on only that clone;
3. verify MCP v10.1.0 and clean Kinglet runtime state;
4. submit identical natural-language request in a fresh client session;
5. do not intervene, hint, or switch the selected workflow manually;
6. capture routing, MCP/hook/lease/snapshot/evidence, Git diff, console/tests, scene state, screenshots, and final report;
7. shut down the clone editor and recheck the original source.

Run explicit selector smoke only after all natural-language cases and exclude it from natural routing metrics.

- [ ] **Step 4: Apply hard acceptance criteria**

Each client must independently:

- select the expected workflow or ask the allowed clarification;
- reproduce the bug before fixing it;
- remain within permitted paths/capabilities;
- acquire/release the writer lease correctly;
- invalidate/refresh snapshots around mutations;
- satisfy the hidden bug oracle;
- introduce no new compile, test, console, scene, package, or user-config regression;
- preserve user-modified/foreign files through install and upgrade;
- provide fresh required evidence and remaining-risk report.

One client failing a release-critical case blocks 3.0.0. Do not average failures into a parity score.

- [ ] **Step 5: Write the redacted report and preserve source**

Report baseline/tree/Kinglet/client/MCP digests, case/result matrix, behavior differences, efficiency observations, failures, remediation commits, rerun identity, and explicit confirmation that the original project hashes were unchanged. Redact project secrets, proprietary source, raw prompts containing private details, screenshots, and absolute source paths.

```bash
git add docs/releases/3.0.0-brownfield-report.md provenance.tsv
git commit -m "test: validate Kinglet on a brownfield Unity project"
```

## Task 8: Build Reproducible 3.0.0 Release Artifacts

**Files:**

- Create: `scripts/build-release.sh`
- Create: `tests/release/test-artifacts.sh`
- Create: `.github/workflows/release.yml`
- Create: `docs/releases/3.0.0-release-checklist.md`
- Modify: `VERSION`
- Regenerate: `packages/**`
- Regenerate: `plugins/kinglet-unity/**`
- Regenerate: `.agents/plugins/marketplace.json`
- Modify: `provenance.tsv`

- [ ] **Step 1: Test the archive contract while still on pre-release version**

The release builder rejects a dirty generated tree, failing release gate, non-`3.0.0` version for final mode, mismatched product versions, moving MCP ref, missing report/sign-off, or unsupported unreported platform. It uses `SOURCE_DATE_EPOCH` from the release commit, stable sorted paths, numeric owners `0:0`, and fixed modes so repeated builds produce identical SHA-256.

Artifacts are:

```text
dist/kinglet-unity-3.0.0.tar.gz
dist/kinglet-unity-claude-3.0.0.tar.gz
dist/kinglet-unity-codex-plugin-3.0.0.tar.gz
dist/kinglet-unity-codex-project-3.0.0.tar.gz
dist/SHA256SUMS
```

The full archive includes installer/uninstaller, generated products, marketplace, runtime, public docs, license/notices, provenance, capability/support/parity matrices, and release reports. It excludes canonical maintainer source only from client-specific archives, not the full source release.

- [ ] **Step 2: Complete the signed checklist before version promotion**

The checklist records commit hashes or CI run IDs for generated check, provenance, Linux/macOS release gates, routing report, seeded Unity report, brownfield report, MCP lock, package/plugin schema, install/upgrade/uninstall matrix, artifact reproducibility, trademark/license review, and reviewer names/dates. Every row must be `pass`; no waived release blocker exists.

- [ ] **Step 3: Promote the single version and rebuild**

Change `VERSION` to exactly `3.0.0`, run `python3 -m tools.kinglet_build build --all`, and assert version equality in Claude package, Codex plugin, project bootstrap, receipts/manifests, marketplace, matrices, archive filenames, and docs. There must be no remaining `3.0.0-dev.1` outside historical migration/release evidence.

- [ ] **Step 4: Run final verification twice**

```bash
bash tests/release/run-release-gate.sh
bash scripts/build-release.sh --version 3.0.0 --output-dir dist-first
bash scripts/build-release.sh --version 3.0.0 --output-dir dist-second
diff -r dist-first dist-second
sha256sum -c dist-first/SHA256SUMS
```

On macOS use the portable checksum verifier from `scripts/lib/kinglet-hash.sh`; CI runs both host paths.

- [ ] **Step 5: Commit the release candidate**

```bash
git add VERSION packages plugins .agents scripts/build-release.sh tests/release .github/workflows/release.yml docs/releases provenance.tsv
git commit -m "release: prepare Kinglet for Unity 3.0.0"
```

Do not commit `dist-first/` or `dist-second/`; publish verified artifacts from the release workflow.

## Task 9: Rename the Remote Repository and Publish Only After Approval

**Files:**

- Modify if needed: repository description/topics in hosting service
- Create externally: Git tag `v3.0.0` and release artifacts

- [ ] **Step 1: Verify the exact candidate commit**

From a fresh clone of the candidate, run the release gate, generated check, archive build, checksum validation, and compare its commit with every release report/checklist entry. Confirm CI is green on Ubuntu and macOS.

- [ ] **Step 2: Obtain explicit maintainer approval for external changes**

Present the candidate commit, archive checksums, final release blockers table, repository rename from its current slug to `kinglet-unity`, and tag/release actions. Repository rename and publication alter external state and require explicit approval at execution time.

- [ ] **Step 3: Rename, tag, publish, and verify redirects**

After approval, rename the hosting repository to `kinglet-unity`, update local/CI remote references, create signed tag `v3.0.0` on the verified commit, publish the five artifacts/checksums and capability/support reports, then test old URL redirects, install URLs, marketplace path, source/archive installer, and documentation links.

- [ ] **Step 4: Run post-publication smoke**

Install Claude and Codex from the published artifacts into fresh disposable Unity projects, run doctor, connect the pinned bridge, issue one natural-language read-only request, and uninstall each client. Record publication smoke evidence in the release entry. If smoke fails, mark the release affected and publish corrective guidance; never rewrite the signed tag silently.

## Plan 06 Completion Gate

Kinglet for Unity 3.0.0 is complete only when:

- active product/docs use Kinglet identity while historical attribution remains truthful;
- capability, support, and parity reports have no silent supported delta;
- synthetic release gates pass on Linux and macOS;
- live natural-language routing meets all aggregate and hard mutation thresholds;
- all six seeded Unity scenarios pass independently on Claude and Codex;
- every release-critical brownfield case passes on disposable same-commit clones and the original project is unchanged;
- install/upgrade/rollback/uninstall preserve all user-ownership fixtures;
- final archives rebuild byte-identically and checksums verify;
- the exact candidate is approved before external repository rename/tag/release;
- published-artifact smoke passes for both clients.
