# Kinglet 00D Decision Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn accepted runtime, client, and Unity evidence into auditable architecture decisions, migration inventory, provenance records, and machine-readable downstream gate state.

**Architecture:** Deterministic generators consume only committed 00A-valid evidence, the approved runtime ADR, fixed dependency rules, and reviewer judgments. They keep measured facts, documented facts, judgments, and unresolved limitations separate; 0D may close with individual client gates open, but never with 0R or 0U open.

**Tech Stack:** Python standard library, 00A evidence/coverage modules, JSON, Markdown, SPDX identifiers, Architecture Decision Records, existing Git history.

## Global Constraints

- 0R and 0U must be closed before 0D can close.
- Individual 0C client gates may remain open only when visibly marked inconclusive; their adapter
  specs remain locked.
- The runtime ADR must contain the user-approved decision; a generated score is not approval.
- Every generated claim links to a committed evidence record, artifact checksum, official source,
  or named reviewer judgment.
- Keep measured facts, documented facts, reviewer judgments, and unresolved limitations in separate
  fields and report sections.
- Existing Python behavior and tests are migration assets even when Python is not selected.
- Inventory dispositions are exactly `keep`, `adapt`, `replace`, or `retire-after-parity`.
- No source file is deleted, ported, or rewritten in this plan.
- No open, missing, invalid, unavailable, or inconclusive cell is converted to pass.
- Reports are deterministic and contain no generation timestamp or machine-local path.
- Dependency records contain name, exact version/commit, source URL, license/SPDX, usage, candidate
  or probe owner, and evidence checksum.
- Downstream specs consume `docs/research/platform-spike/gates.json`; prose alone never unlocks work.

---

## File map

| Path | Responsibility |
| --- | --- |
| `spikes/platform/decision/gate-rules-v1.json` | Exact prerequisites and unlock targets |
| `spikes/platform/decision/inventory-rules-v1.json` | Existing Python classification rules |
| `tools/kinglet_spike/decision.py` | Gate evaluation and deterministic decision-package assembly |
| `tools/kinglet_spike/inventory.py` | Git-aware keep/adapt/replace inventory |
| `tools/kinglet_spike/provenance.py` | Toolchain/package/source/license aggregation |
| `docs/research/platform-spike/gates.json` | Machine-readable authoritative gate state |
| `docs/research/platform-spike/reports/python-foundation-inventory.{json,md}` | Migration inventory |
| `docs/research/platform-spike/reports/dependency-provenance.{json,md}` | Supply-chain record |
| `docs/research/platform-spike/reports/decision-package.{json,md}` | Consolidated facts and limits |
| `docs/architecture/adr/0002-kinglet-unity-execution-model.md` | Evidence-backed four-route decision |
| `docs/architecture/adr/0003-kinglet-platform-spike-outcome.md` | 0D closure and open-client record |
| `docs/superpowers/plans/2026-07-23-kinglet-00-plan-suite.md` | Human execution/gate index |

## Gate IDs and unlocks

```text
0A
0R
0C:claude-code
0C:codex
0C:cursor
0C:copilot-cli
0C:copilot-vscode
0C:antigravity
0U
0D
```

Unlock rules:

```text
canonical-foundation-spec   ← 0R
adapter:<client>-spec       ← 0C:<client>
unity-execution-spec        ← 0U
windows-reference-slice     ← 0R + 0C:claude-code + 0C:codex + required Windows 0U cells
platform-plan-rewrite       ← 0D
```

### Task 1: Freeze and test downstream gate semantics

**Files:**
- Create: `spikes/platform/decision/gate-rules-v1.json`
- Create: `tools/kinglet_spike/decision.py`
- Test: `tests/kinglet_spike/test_decision_gates.py`

**Interfaces:**
- Consumes: 00A `CoverageCell` values and approved ADR status.
- Produces:
  - `runtime_gate_state(coverage_state: str, adr_status: str) -> str`
  - `evaluate_unlocks(gates: Mapping[str, str], windows_cells_passed: bool) -> Mapping[str, bool]`
  - `can_close_0d(gates: Mapping[str, str]) -> bool`

- [ ] **Step 1: Write failing independence and prerequisite tests**

```python
import unittest

from tools.kinglet_spike.decision import (
    can_close_0d,
    evaluate_unlocks,
    runtime_gate_state,
)


def closed_required_gates() -> dict[str, str]:
    return {
        "0A": "closed",
        "0R": "closed",
        "0C:claude-code": "closed",
        "0C:codex": "closed",
        "0C:cursor": "inconclusive",
        "0C:copilot-cli": "inconclusive",
        "0C:copilot-vscode": "inconclusive",
        "0C:antigravity": "inconclusive",
        "0U": "closed",
        "0D": "open",
    }


class DecisionGateTests(unittest.TestCase):
    def test_open_client_does_not_block_0d(self):
        gates = closed_required_gates()
        gates["0C:antigravity"] = "inconclusive"
        self.assertTrue(can_close_0d(gates))
        self.assertFalse(evaluate_unlocks(gates)["adapter:antigravity-spec"])

    def test_runtime_or_unity_blocks_0d(self):
        for gate in ("0R", "0U"):
            gates = closed_required_gates()
            gates[gate] = "open"
            with self.subTest(gate=gate):
                self.assertFalse(can_close_0d(gates))

    def test_runtime_requires_approved_adr(self):
        self.assertEqual("open", runtime_gate_state("pass", "proposed"))

    def test_windows_slice_has_four_independent_inputs(self):
        gates = closed_required_gates()
        gates["0C:codex"] = "open"
        unlocks = evaluate_unlocks(gates, windows_cells_passed=True)
        self.assertFalse(unlocks["windows-reference-slice"])
```

- [ ] **Step 2: Run tests and verify missing functions**

Run: `python3 -m unittest tests.kinglet_spike.test_decision_gates -v`

Expected: import/function failure.

- [ ] **Step 3: Commit exact machine-readable rules**

`gate-rules-v1.json` uses schema `kinglet.spike.gate-rules/v1`, lists all ten gate IDs, lists the
unlocks above, and sets:

```json
{
  "close0D": {
    "all": ["0A", "0R", "0U"],
    "allowOpenPrefixes": ["0C:"]
  }
}
```

Every client unlock has only its own 0C prerequisite. The Windows slice uses `windowsCellsPassed`
in addition to its three gates; it does not accept a global 0U pass without the named Windows
evidence references.

- [ ] **Step 4: Implement pure evaluation**

Use mappings passed as arguments; do not read global files inside evaluators. A gate closes only
from valid published pass cells and, for 0R, ADR status `accepted`. Return sorted frozen values.
Unknown/missing gates are open with reason `missing`.

- [ ] **Step 5: Run tests and commit**

Run: `python3 -m unittest tests.kinglet_spike.test_decision_gates -v`

Expected: all tests pass.

```bash
git add spikes/platform/decision/gate-rules-v1.json tools/kinglet_spike/decision.py tests/kinglet_spike/test_decision_gates.py
git commit -m "test: freeze platform decision gates"
```

### Task 2: Inventory the existing Python foundation without rewriting it

**Files:**
- Create: `spikes/platform/decision/inventory-rules-v1.json`
- Create: `tools/kinglet_spike/inventory.py`
- Test: `tests/kinglet_spike/test_foundation_inventory.py`
- Create: `docs/research/platform-spike/reports/python-foundation-inventory.json`
- Create: `docs/research/platform-spike/reports/python-foundation-inventory.md`

**Interfaces:**
- Consumes: tracked files below `tools/kinglet_build/`, `tests/kinglet/`, canonical source data used
  by the builder, selected runtime ID, runtime report, and Git blob IDs.
- Produces: one disposition per tracked file with behavior/test/evidence references.
- Produces `tracked_foundation_files(repo_root: Path) -> tuple[str, ...]` and
  `build_inventory(repo_root: Path, selected_runtime: str) -> FoundationInventory`.

- [ ] **Step 1: Write failing exhaustiveness and evidence tests**

```python
from pathlib import Path
import unittest

from tools.kinglet_spike.inventory import build_inventory, tracked_foundation_files


class FoundationInventoryTests(unittest.TestCase):
    def test_every_tracked_foundation_file_appears_once(self):
        report = build_inventory(Path("."), "rust")
        self.assertEqual(
            set(tracked_foundation_files(Path("."))),
            {row.path for row in report.rows},
        )

    def test_behavioral_tests_are_never_immediately_retired(self):
        report = build_inventory(Path("."), "rust")
        test_rows = [row for row in report.rows if row.path.startswith("tests/kinglet/")]
        self.assertTrue(test_rows)
        self.assertTrue(all(row.disposition in {"keep", "adapt", "retire-after-parity"} for row in test_rows))

    def test_replace_or_retire_requires_parity_reference(self):
        for row in build_inventory(Path("."), "go").rows:
            if row.disposition in {"replace", "retire-after-parity"}:
                self.assertTrue(row.parity_tests)
```

- [ ] **Step 2: Run tests and verify missing inventory module**

Run: `python3 -m unittest tests.kinglet_spike.test_foundation_inventory -v`

Expected: import failure.

- [ ] **Step 3: Freeze exact classification rules**

Rules:

- canonical JSON/Markdown source content: `keep`;
- baseline inventory and behavioral tests: `keep` when runtime-neutral, otherwise `adapt`;
- loader/validator/writer/CLI implementation: `keep` for bundled Python; for another winner,
  `retire-after-parity` with every current test module named;
- adapter profile data: `keep`;
- Python-only packaging entry points not selected for product runtime: `replace` only after their
  behavior is named in a parity suite;
- `__pycache__` and other untracked build output: excluded, not inventoried.

Every row includes tracked path, Git blob SHA, responsibility, disposition, selected-runtime reason,
current test files, parity tests, and runtime evidence IDs.

- [ ] **Step 4: Implement Git-aware deterministic generation**

Use `git ls-files -s` through an argument-array subprocess. Refuse a dirty tracked foundation file
unless `--allow-dirty-inventory` is explicitly used; normal 0D generation must not use it. Sort by
path. Markdown contains one table generated from JSON and no hand-edited disposition.

- [ ] **Step 5: Generate twice and verify baseline behavior**

Run:

```bash
python3 -m tools.kinglet_spike inventory --repo-root .
sha256sum docs/research/platform-spike/reports/python-foundation-inventory.*
python3 -m tools.kinglet_spike inventory --repo-root .
sha256sum docs/research/platform-spike/reports/python-foundation-inventory.*
python3 -m unittest discover -s tests/kinglet -t . -v
```

Expected: matching SHA-256 pairs and 122 baseline Python tests pass.

- [ ] **Step 6: Commit the inventory**

```bash
git add spikes/platform/decision/inventory-rules-v1.json tools/kinglet_spike/inventory.py \
  tests/kinglet_spike/test_foundation_inventory.py \
  docs/research/platform-spike/reports/python-foundation-inventory.json \
  docs/research/platform-spike/reports/python-foundation-inventory.md
git commit -m "docs: inventory the Python foundation"
```

### Task 3: Aggregate dependency and source provenance

**Files:**
- Create: `tools/kinglet_spike/provenance.py`
- Test: `tests/kinglet_spike/test_spike_provenance.py`
- Create: `docs/research/platform-spike/reports/dependency-provenance.json`
- Create: `docs/research/platform-spike/reports/dependency-provenance.md`

**Interfaces:**
- Consumes: runtime toolchain lock, candidate lockfiles, Unity MCP lock/uv lock, client fixture
  toolchain lock, and evidence source references.
- Produces: unique dependency/source records keyed by `(ecosystem, name, version_or_commit)`.
- Produces frozen `ProvenanceItem(ecosystem, name, version_or_commit, source_url, license_spdx,
  usage, owner, sha256)` and `merge_records(items) -> tuple[ProvenanceItem, ...]`.

- [ ] **Step 1: Write failing completeness and conflict tests**

```python
from pathlib import Path
import unittest

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.provenance import ProvenanceItem, build_provenance, merge_records


def record(license_spdx: str) -> ProvenanceItem:
    return ProvenanceItem(
        ecosystem="nuget",
        name="NSec.Cryptography",
        version_or_commit="26.4.0",
        source_url="https://www.nuget.org/packages/NSec.Cryptography/26.4.0",
        license_spdx=license_spdx,
        usage="runtime-candidate",
        owner="dotnet-self-contained",
        sha256="a" * 64,
    )


class SpikeProvenanceTests(unittest.TestCase):
    def test_every_dependency_has_required_distribution_fields(self):
        for item in build_provenance(Path(".")).items:
            self.assertTrue(item.name)
            self.assertTrue(item.version_or_commit)
            self.assertTrue(item.source_url.startswith("https://"))
            self.assertTrue(item.license_spdx)
            self.assertRegex(item.sha256, r"^[0-9a-f]{64}$")

    def test_same_package_version_cannot_have_conflicting_license(self):
        with self.assertRaisesRegex(EvidenceError, "E_PROVENANCE"):
            merge_records([record("MIT"), record("Apache-2.0")])
```

- [ ] **Step 2: Run tests and verify missing module**

Run: `python3 -m unittest tests.kinglet_spike.test_spike_provenance -v`

Expected: import failure.

- [ ] **Step 3: Implement ecosystem-specific readers**

Read PyInstaller requirements/metadata, Cargo.lock plus Cargo metadata artifact, go.mod/build info,
NuGet packages.lock.json, Unity `mcp.lock.json` plus pinned `Server/uv.lock`, and official client
documentation snapshots. Do not query the network during report generation. Reject missing license,
source, checksum, usage owner, or version.

- [ ] **Step 4: Generate deterministic JSON and Markdown**

Group direct toolchains, runtime-candidate dependencies, client-probe-only dependencies, Unity
probe dependencies, and external references. Clearly label probe-only dependencies so they are not
mistaken for future product dependencies.

- [ ] **Step 5: Run tests, generate twice, and commit**

Expected: all provenance tests pass and SHA-256 pairs match.

```bash
git add tools/kinglet_spike/provenance.py tests/kinglet_spike/test_spike_provenance.py \
  docs/research/platform-spike/reports/dependency-provenance.json \
  docs/research/platform-spike/reports/dependency-provenance.md
git commit -m "docs: record platform spike provenance"
```

### Task 4: Generate the authoritative gate file and decision package

**Files:**
- Modify: `tools/kinglet_spike/decision.py`
- Test: `tests/kinglet_spike/test_decision_package.py`
- Create: `docs/research/platform-spike/gates.json`
- Create: `docs/research/platform-spike/reports/decision-package.json`
- Create: `docs/research/platform-spike/reports/decision-package.md`

**Interfaces:**
- Consumes: all generated reports, approved ADR 0001, valid evidence, and gate rules.
- Produces immutable-content summaries and machine gate state.
- Produces `Claim(id: str, kind: str, statement: str, references: tuple[str, ...])`,
  `assemble_decision_package(claims, gates, unlocks, source_digests) -> DecisionPackage`, and
  `decision_package_to_dict(package) -> dict[str, object]`.

- [ ] **Step 1: Write failing fact-kind and no-fabrication tests**

```python
import unittest

from tools.kinglet_spike.decision import (
    Claim,
    assemble_decision_package,
    decision_package_to_dict,
)


def package_with(client_state: str = "closed"):
    gates = {"0A": "closed", "0R": "closed", "0U": "closed", "0D": "open",
             "0C:antigravity": client_state}
    unlocks = {"adapter:antigravity-spec": client_state == "closed"}
    claims = (
        Claim("runtime", "measured", "The selected runtime passed.", ("evidence/runtime/run-01",)),
        Claim("client", "limitation", "Antigravity remains gated.", ("evidence/client/run-01",)),
    )
    return assemble_decision_package(claims, gates, unlocks, {"coverage": "a" * 64})


class DecisionPackageTests(unittest.TestCase):
    def test_every_claim_has_one_fact_kind_and_reference(self):
        package = package_with()
        for claim in package.claims:
            self.assertIn(claim.kind, {"measured", "documented", "judgment", "limitation"})
            self.assertTrue(claim.references)

    def test_inconclusive_client_stays_open(self):
        package = package_with("inconclusive")
        self.assertEqual("inconclusive", package.gates["0C:antigravity"])
        self.assertFalse(package.unlocks["adapter:antigravity-spec"])

    def test_output_has_no_wall_clock_field(self):
        value = decision_package_to_dict(package_with())
        self.assertNotIn("generated_at", value)
```

- [ ] **Step 2: Run tests and verify missing package builder**

Run: `python3 -m unittest tests.kinglet_spike.test_decision_package -v`

Expected: missing function failures.

- [ ] **Step 3: Implement deterministic package assembly**

Package sections are exact: `runtime_decision`, `client_baseline`, `unity_baseline`,
`python_foundation_inventory`, `dependency_provenance`, `gates`, `unlocks`, `open_limitations`,
and `claims`. Store source report SHA-256 values at the top. `gates.json` uses schema
`kinglet.platform.gates/v1`, fixed gate IDs, state/reason/evidence arrays, unlock states, and source
report digests.

- [ ] **Step 4: Refuse 0D closure when required inputs are open**

The command may generate a draft with `0D=open`. It may write `0D=closed` only when 0A, 0R, and 0U
are closed, ADR 0001 is accepted, report digests validate, and no required evidence cell is invalid.
Open 0C entries are copied exactly and listed under limitations.

- [ ] **Step 5: Generate twice and commit draft facts**

Run generation twice; expected matching checksums. Validate with 00A and JSON parser.

```bash
git add tools/kinglet_spike/decision.py tests/kinglet_spike/test_decision_package.py \
  docs/research/platform-spike/gates.json \
  docs/research/platform-spike/reports/decision-package.json \
  docs/research/platform-spike/reports/decision-package.md
git commit -m "docs: assemble platform spike decisions"
```

### Task 5: Record Unity and overall spike ADRs

**Files:**
- Create: `docs/architecture/adr/0002-kinglet-unity-execution-model.md`
- Create: `docs/architecture/adr/0003-kinglet-platform-spike-outcome.md`
- Modify: `docs/superpowers/plans/2026-07-23-kinglet-00-plan-suite.md`

**Interfaces:**
- Consumes: decision package and explicit reviewer/user acceptance.
- Produces: accepted architecture decisions and 0D closure.

- [ ] **Step 1: Draft ADR 0002 from evidence**

Sections: Status, Context, Decision, Route selection table, Editor resolution, Ownership/refusal,
MCP readiness, Isolation, Lease/process cleanup, Evidence, Consequences, Revisit triggers. Preserve
the four routes and explicitly state live Editor + MCP is first-class and optional, same-project
headless requires GUI closed, and isolated headless may coexist only on a separate physical copy.

- [ ] **Step 2: Draft ADR 0003**

Sections: Status, Completed gates, Open client gates, Runtime decision reference, Unity decision
reference, Python migration inventory, Supply chain, Downstream unlocks, Non-goals, Revisit
triggers. It must say 0D is evidence/decision completion, not production readiness.

- [ ] **Step 3: Obtain user review**

Present the selected runtime, Unity route contract, closed/open client gates, migration
dispositions, dependency risks, and exact downstream work unlocked. Keep ADR status `Proposed`
until the user approves them.

- [ ] **Step 4: Accept ADRs and close 0D**

After approval, set both ADR statuses to `Accepted`, regenerate `gates.json` and the decision
package so `0D=closed`, and update the plan suite status to `Subproject 0 complete` with every 0C
state listed individually.

- [ ] **Step 5: Run final verification**

Run:

```bash
python3 -m unittest discover -s tests/kinglet_spike -t . -v
python3 -m tools.kinglet_spike gate 0D --repo-root .
bash tests/run-tests.sh
git diff --check
git grep -nE '(/Users/|/home/|[A-Z]:\\\\Users\\\\|gh[pousr]_|sk-|PASSWORD|TOKEN)' docs/research/platform-spike
```

Expected: spike tests pass; 0D exits `0`; aggregate suite reports `Failed: 0`; diff and privacy
checks are empty.

- [ ] **Step 6: Commit accepted Subproject 0 decisions**

```bash
git add docs/architecture/adr/0002-kinglet-unity-execution-model.md \
  docs/architecture/adr/0003-kinglet-platform-spike-outcome.md \
  docs/research/platform-spike/gates.json \
  docs/research/platform-spike/reports/decision-package.json \
  docs/research/platform-spike/reports/decision-package.md \
  docs/superpowers/plans/2026-07-23-kinglet-00-plan-suite.md
git commit -m "docs: close Kinglet platform spikes"
```

## Plan acceptance

00D is accepted only when runtime and Unity decisions are closed with valid native evidence, the
runtime is user-approved, the existing Python foundation has exhaustive evidence-backed
dispositions, provenance is complete, open clients remain open without blocking unrelated work,
machine-readable unlocks match the dependency rules, generated outputs are byte-stable, and the
ADRs clearly state what Subproject 0 did not build.
