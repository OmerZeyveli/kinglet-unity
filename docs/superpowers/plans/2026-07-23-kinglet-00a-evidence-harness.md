# Kinglet 00A Evidence Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the candidate-neutral, standard-library evidence boundary that must accept a spike result before any runtime, client, or Unity gate can pass.

**Architecture:** A maintainer-only Python package loads one strict versioned JSON record, validates its shape, safety, checksums, and assertion completeness, then publishes an immutable sanitized copy. Separate coverage and reporting modules consume only published evidence; candidate probes never import harness process or filesystem helpers.

**Tech Stack:** Python 3 standard library, `unittest`, JSON, SHA-256, Markdown, existing Bash test runner, GitHub Actions.

## Global Constraints

- This harness is maintainer tooling, not a Kinglet product-runtime candidate.
- Use only the Python standard library.
- Do not import from `tools/kinglet_build/` or any runtime candidate.
- Raw records live under `.kinglet/local/spikes/<run-id>/` and are never committed.
- Published evidence lives under `docs/research/platform-spike/evidence/`.
- Published artifacts live under `docs/research/platform-spike/artifacts/`.
- Generated reports live under `docs/research/platform-spike/reports/`.
- A pass requires every named artifact, checksum, assertion, and repetition.
- `fail`, `unavailable`, `inconclusive`, absent, invalid, and skipped are distinct non-pass states.
- Reject absolute paths, path traversal, symlink escapes, credentials, account identifiers, and raw prompts.
- Retries create new immutable run IDs; publishing may never overwrite an existing run.
- JSON and Markdown output use UTF-8, LF, sorted keys, deterministic ordering, and a final newline.

---

## File map

| Path | Responsibility |
| --- | --- |
| `tools/kinglet_spike/model.py` | Frozen evidence, assertion, artifact, environment, and diagnostic types |
| `tools/kinglet_spike/load.py` | Strict JSON decoding and unknown-field rejection |
| `tools/kinglet_spike/validate.py` | Status, timestamp, path, checksum, redaction, and pass-completeness checks |
| `tools/kinglet_spike/redact.py` | Deterministic text/JSON/XML sanitization into a raw run's publish subset |
| `tools/kinglet_spike/publish.py` | Immutable sanitized evidence publication |
| `tools/kinglet_spike/coverage.py` | Required matrix-cell evaluation without false passes |
| `tools/kinglet_spike/report.py` | Byte-stable Markdown and machine-readable gate reports |
| `tools/kinglet_spike/cli.py` | `validate`, `publish`, `coverage`, and `report` command boundary |
| `spikes/platform/contracts/evidence-v1.json` | Human-reviewable exact v1 field and enum contract |
| `spikes/platform/contracts/matrix-v1.json` | Initial required runtime, client, and Unity cells |
| `tests/kinglet_spike/` | Unit and CLI tests, isolated from existing product tests |
| `tests/test-kinglet-spike.sh` | Bridge into the existing aggregate Bash runner |
| `.github/workflows/ci.yml` | Executes harness tests and deterministic fixture regeneration |
| `.gitignore` | Ignores `.kinglet/local/`, not committed evidence |
| `docs/research/platform-spike/README.md` | Evidence handling and reviewer workflow |

## Stable interfaces

```python
class EvidenceError(ValueError):
    code: str
    detail: str

@dataclass(frozen=True)
class EvidenceRecord:
    schema: str
    run_id: str
    subject: Subject
    probe: Probe
    environment: Environment
    started_at: str
    ended_at: str
    status: Literal["pass", "fail", "unavailable", "inconclusive"]
    command: tuple[str, ...]
    artifacts: tuple[Artifact, ...]
    assertions: tuple[AssertionResult, ...]
    measurements: tuple[Measurement, ...]
    sources: tuple[SourceReference, ...]
    prompt: PromptReference | None

def load_record(path: Path) -> EvidenceRecord: ...
def redact_artifact(source: Path, target: Path, media_type: str, forbidden_roots: tuple[str, ...]) -> str: ...
def validate_record(record: EvidenceRecord, artifact_root: Path) -> tuple[Diagnostic, ...]: ...
def publish_record(raw_path: Path, repo_root: Path) -> Path: ...
def evaluate_coverage(
    records: Iterable[EvidenceRecord], matrix_path: Path
) -> tuple[CoverageCell, ...]: ...
def render_markdown(cells: Iterable[CoverageCell]) -> str: ...
```

All diagnostics use stable codes. Version 1 reserves:

```text
E_SCHEMA E_JSON E_FIELD E_ENUM E_TIME E_PATH E_SYMLINK E_CHECKSUM
E_SECRET E_PROMPT E_ASSERTION E_REPETITION E_IMMUTABLE E_COVERAGE
```

### Task 1: Freeze the evidence model and strict loader

**Files:**
- Create: `tools/kinglet_spike/__init__.py`
- Create: `tools/kinglet_spike/model.py`
- Create: `tools/kinglet_spike/load.py`
- Create: `spikes/platform/contracts/evidence-v1.json`
- Create: `tests/kinglet_spike/__init__.py`
- Create: `tests/kinglet_spike/support.py`
- Test: `tests/kinglet_spike/test_load.py`

**Interfaces:**
- Consumes: UTF-8 JSON with schema ID `kinglet.spike.evidence/v1`.
- Produces: `EvidenceError`, frozen model types, and `load_record(path: Path) -> EvidenceRecord`.

- [ ] **Step 1: Add the exact v1 fixture builder and failing strictness tests**

```python
# tests/kinglet_spike/support.py
from __future__ import annotations

import hashlib
import json
from pathlib import Path


def valid_record(
    artifact_path: str = (
        "artifacts/runtime/python/"
        "20260723T120000Z-runtime-python-windows11-x64-01/result.json"
    ),
) -> dict:
    payload = b'{"ok":true}\n'
    return {
        "schema": "kinglet.spike.evidence/v1",
        "run_id": "20260723T120000Z-runtime-python-windows11-x64-01",
        "subject": {"kind": "runtime", "id": "python", "version": "3.14.6"},
        "probe": {"id": "host-probe", "contract": "kinglet.host-probe/v1"},
        "environment": {
            "os": "windows",
            "release": "11-24H2",
            "arch": "x64",
            "native": True,
            "toolchain": ["python=3.14.6", "pyinstaller=6.21.0"],
        },
        "started_at": "2026-07-23T12:00:00Z",
        "ended_at": "2026-07-23T12:00:02Z",
        "status": "pass",
        "command": ["kinglet-host-probe.exe", "--contract", "contract.json"],
        "artifacts": [{
            "path": artifact_path,
            "sha256": hashlib.sha256(payload).hexdigest(),
            "media_type": "application/json",
            "required": True,
        }],
        "assertions": [
            {"id": "manifest.valid", "status": "pass", "detail": "accepted"},
            {"id": "process.no-orphans", "status": "pass", "detail": "zero descendants"},
        ],
        "measurements": [
            {"id": "cold-start", "unit": "milliseconds", "samples": [12, 11, 13, 12, 11]},
        ],
        "sources": [{
            "title": "Python 3.14.6",
            "url": "https://www.python.org/downloads/release/python-3146/",
        }],
        "prompt": None,
    }


def write_record(root: Path, value: dict) -> Path:
    path = root / "record.json"
    path.write_text(json.dumps(value), encoding="utf-8")
    return path
```

```python
# tests/kinglet_spike/test_load.py
import tempfile
import unittest
from pathlib import Path

from tools.kinglet_spike.load import load_record
from tools.kinglet_spike.model import EvidenceError
from tests.kinglet_spike.support import valid_record, write_record


class LoadRecordTests(unittest.TestCase):
    def test_loads_v1_into_frozen_types(self):
        with tempfile.TemporaryDirectory() as directory:
            record = load_record(write_record(Path(directory), valid_record()))
        self.assertEqual("python", record.subject.id)
        self.assertEqual(("python=3.14.6", "pyinstaller=6.21.0"), record.environment.toolchain)
        self.assertEqual((12, 11, 13, 12, 11), record.measurements[0].samples)

    def test_rejects_unknown_nested_field(self):
        value = valid_record()
        value["subject"]["preference"] = "favorite"
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(EvidenceError, "E_FIELD.*subject.preference"):
                load_record(write_record(Path(directory), value))

    def test_rejects_wrong_schema(self):
        value = valid_record()
        value["schema"] = "kinglet.spike.evidence/v2"
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(EvidenceError, "E_SCHEMA"):
                load_record(write_record(Path(directory), value))
```

- [ ] **Step 2: Run the loader tests and verify the missing package failure**

Run: `python3 -m unittest tests.kinglet_spike.test_load -v`

Expected: `ERROR` with `ModuleNotFoundError: No module named 'tools.kinglet_spike'`.

- [ ] **Step 3: Implement the frozen model and strict object decoder**

Create model dataclasses for every field in `valid_record()`. `EvidenceError.__str__` must return
`"<code>: <detail>"`. In `load.py`, use this exact key guard at every object boundary:

```python
def _keys(value: object, path: str, required: set[str]) -> dict:
    if not isinstance(value, dict):
        raise EvidenceError("E_FIELD", f"{path} must be an object")
    missing = sorted(required - value.keys())
    unknown = sorted(value.keys() - required)
    if missing:
        raise EvidenceError("E_FIELD", f"{path}.{missing[0]} is required")
    if unknown:
        raise EvidenceError("E_FIELD", f"{path}.{unknown[0]} is unknown")
    return value
```

Use explicit constructors rather than `TypeError`-driven `**dict` decoding. Accept only the four
status strings and only integer measurement samples; reject booleans as samples because
`isinstance(True, int)` is true in Python.

The top-level contract file must contain this exact review surface:

```json
{
  "schema": "kinglet.spike.contract/v1",
  "recordSchema": "kinglet.spike.evidence/v1",
  "statuses": ["pass", "fail", "unavailable", "inconclusive"],
  "subjectKinds": ["runtime", "client", "unity"],
  "requiredTopLevelFields": [
    "schema", "run_id", "subject", "probe", "environment", "started_at", "ended_at",
    "status", "command", "artifacts", "assertions", "measurements", "sources", "prompt"
  ],
  "diagnosticCodes": [
    "E_SCHEMA", "E_JSON", "E_FIELD", "E_ENUM", "E_TIME", "E_PATH", "E_SYMLINK",
    "E_CHECKSUM", "E_SECRET", "E_PROMPT", "E_ASSERTION", "E_REPETITION",
    "E_IMMUTABLE", "E_COVERAGE"
  ]
}
```

- [ ] **Step 4: Run the loader tests**

Run: `python3 -m unittest tests.kinglet_spike.test_load -v`

Expected: `Ran 3 tests ... OK`.

- [ ] **Step 5: Commit the model boundary**

```bash
git add tools/kinglet_spike tests/kinglet_spike spikes/platform/contracts/evidence-v1.json
git commit -m "test: freeze spike evidence contract"
```

### Task 2: Validate safety, integrity, and pass completeness

**Files:**
- Create: `tools/kinglet_spike/redact.py`
- Create: `tools/kinglet_spike/validate.py`
- Test: `tests/kinglet_spike/test_validate.py`

**Interfaces:**
- Consumes: `EvidenceRecord`, a raw run's `publish/` root, and artifact paths relative to the
  eventual `docs/research/platform-spike/` root.
- Produces: `validate_record(record, artifact_root) -> tuple[Diagnostic, ...]`, sorted by
  `(code, location, message)`.

- [ ] **Step 1: Write the failing security and completeness tests**

```python
# tests/kinglet_spike/test_validate.py
import json
import tempfile
import unittest
from pathlib import Path

from tools.kinglet_spike.load import load_record
from tools.kinglet_spike.redact import redact_artifact
from tools.kinglet_spike.validate import validate_record
from tests.kinglet_spike.support import valid_record, write_record


class ValidateRecordTests(unittest.TestCase):
    def _diagnostics(self, value: dict, artifact: bool = True):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        if artifact:
            path = (
                root / "publish/artifacts/runtime/python"
                / "20260723T120000Z-runtime-python-windows11-x64-01/result.json"
            )
            path.parent.mkdir(parents=True)
            path.write_bytes(b'{"ok":true}\n')
        record = load_record(write_record(root, value))
        return validate_record(record, root / "publish")

    def test_valid_record_has_no_diagnostics(self):
        self.assertEqual((), self._diagnostics(valid_record()))

    def test_rejects_absolute_and_parent_paths(self):
        absolute = valid_record("/Users/alice/result.json")
        traversal = valid_record("../result.json")
        self.assertEqual("E_PATH", self._diagnostics(absolute, artifact=False)[0].code)
        self.assertEqual("E_PATH", self._diagnostics(traversal, artifact=False)[0].code)

    def test_rejects_symlink_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target.json"
            target.write_bytes(b'{"ok":true}\n')
            link = root / "publish/artifacts/link.json"
            link.parent.mkdir(parents=True)
            link.symlink_to(target)
            record = load_record(
                write_record(root, valid_record("artifacts/link.json"))
            )
            self.assertEqual(
                "E_SYMLINK", validate_record(record, root / "publish")[0].code
            )

    def test_missing_required_artifact_is_not_a_pass(self):
        diagnostics = self._diagnostics(valid_record(), artifact=False)
        self.assertEqual("E_PATH", diagnostics[0].code)

    def test_pass_requires_artifact_checksum_and_all_assertions(self):
        value = valid_record()
        value["artifacts"][0]["sha256"] = "0" * 64
        value["assertions"][0]["status"] = "fail"
        codes = {item.code for item in self._diagnostics(value)}
        self.assertEqual({"E_ASSERTION", "E_CHECKSUM"}, codes)

    def test_rejects_raw_prompt_and_sensitive_command(self):
        value = valid_record()
        value["prompt"] = {"id": "client-discovery-01", "sha256": "a" * 64, "raw": "secret"}
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(Exception, "E_FIELD.*prompt.raw"):
                load_record(write_record(Path(directory), value))

        value = valid_record()
        value["command"] = ["tool", "--token", "ghp_123456789012345678901234567890123456"]
        self.assertEqual("E_SECRET", self._diagnostics(value)[0].code)

    def test_pass_requires_five_cold_start_samples(self):
        value = valid_record()
        value["measurements"][0]["samples"] = [12, 11, 13, 12]
        self.assertEqual("E_REPETITION", self._diagnostics(value)[0].code)

    def test_redactor_replaces_declared_root_and_rejects_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "raw.json"
            target = root / "publish.json"
            source.write_text('{"path":"C:\\\\Users\\\\probe\\\\project"}', encoding="utf-8")
            digest = redact_artifact(
                source, target, "application/json", ("C:\\\\Users\\\\probe",)
            )
            self.assertIn("<redacted-root>", target.read_text(encoding="utf-8"))
            self.assertEqual(64, len(digest))
            with self.assertRaisesRegex(Exception, "E_ENUM"):
                redact_artifact(source, root / "image.png", "image/png", ())
```

- [ ] **Step 2: Run the validator tests and verify failure**

Run: `python3 -m unittest tests.kinglet_spike.test_validate -v`

Expected: `ERROR` with `ModuleNotFoundError: No module named 'tools.kinglet_spike.validate'`.

- [ ] **Step 3: Implement validation with repository containment**

Implement `Diagnostic` as a frozen ordered dataclass in `model.py`. Use `Path.resolve()` only after
rejecting absolute paths and `..`, reject any symlink component before following it, then require:

```python
SHA256 = re.compile(r"^[0-9a-f]{64}$")
SECRET_PATTERNS = (
    re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"sk-[A-Za-z0-9_-]{20,}"),
    re.compile(r"(?i)(token|password|secret)=\\S+"),
)


def _artifact_path(artifact_root: Path, relative: str) -> Path:
    candidate = Path(relative)
    if candidate.is_absolute() or ".." in candidate.parts:
        raise EvidenceError("E_PATH", f"unsafe artifact path: {relative}")
    root = artifact_root.resolve()
    current = root
    for part in candidate.parts:
        current = current / part
        if current.is_symlink():
            raise EvidenceError("E_SYMLINK", f"artifact path contains symlink: {relative}")
    resolved = current.resolve()
    if not resolved.is_relative_to(root):
        raise EvidenceError("E_PATH", f"artifact escapes evidence root: {relative}")
    return resolved
```

Artifact record paths are relative to `docs/research/platform-spike/`, so the fixture path
`artifacts/runtime/python/<run-id>/result.json` resolves below the raw `publish/` root before being
copied to the same relative committed path. For `status == "pass"`,
require at least one required artifact, every assertion to be `pass`, and exactly five or more
positive integer samples for `cold-start`. Parse timestamps with `datetime.fromisoformat`, require
UTC `Z`, and require end time not before start time. Scan all string fields recursively after
serialization; prompt evidence permits only `id` and a lowercase SHA-256 digest.

`redact_artifact()` accepts only UTF-8 `application/json`, `application/xml`, `text/plain`, and
`text/markdown`. It normalizes CRLF to LF, replaces only the explicitly supplied absolute roots
with `<redacted-root>`, rejects all remaining secret/path patterns, canonicalizes JSON, writes the
target by exclusive create, and returns the published SHA-256. Binary logs, executables, and
screenshots are not committed by v1; probes publish a small sanitized JSON observation plus the
local binary's checksum and reproduction command instead. A redaction failure keeps the result
inconclusive.

- [ ] **Step 4: Run validation and loader tests**

Run: `python3 -m unittest tests.kinglet_spike.test_load tests.kinglet_spike.test_validate -v`

Expected: `Ran 11 tests ... OK`.

- [ ] **Step 5: Commit the evidence validator**

```bash
git add tools/kinglet_spike/model.py tools/kinglet_spike/validate.py tests/kinglet_spike/test_validate.py
git commit -m "feat: validate spike evidence safety"
```

### Task 3: Publish sanitized evidence immutably

**Files:**
- Create: `tools/kinglet_spike/publish.py`
- Test: `tests/kinglet_spike/test_publish.py`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: one raw `record.json` below `.kinglet/local/spikes/<run-id>/`.
- Produces: `publish_record(raw_path, repo_root) -> Path` at
  `docs/research/platform-spike/evidence/<subject-kind>/<subject-id>/<run-id>.json`, plus byte-identical
  immutable copies from `<run-dir>/publish/<artifact.path>` to
  `docs/research/platform-spike/<artifact.path>`.

- [ ] **Step 1: Write failing publication and overwrite tests**

```python
# tests/kinglet_spike/test_publish.py
import tempfile
import unittest
from pathlib import Path

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.publish import publish_record
from tests.kinglet_spike.support import valid_record, write_record


class PublishTests(unittest.TestCase):
    def test_publishes_canonical_json_once(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw_root = root / ".kinglet/local/spikes/run-01"
            artifact = (
                raw_root / "publish/artifacts/runtime/python"
                / "20260723T120000Z-runtime-python-windows11-x64-01/result.json"
            )
            artifact.parent.mkdir(parents=True)
            artifact.write_bytes(b'{"ok":true}\n')
            raw = write_record(raw_root, valid_record())
            target = publish_record(raw, root)
            self.assertTrue(target.is_file())
            published_artifact = (
                root / "docs/research/platform-spike/artifacts/runtime/python"
                / "20260723T120000Z-runtime-python-windows11-x64-01/result.json"
            )
            self.assertEqual(b'{"ok":true}\n', published_artifact.read_bytes())
            self.assertTrue(target.read_text(encoding="utf-8").endswith("\n"))
            with self.assertRaisesRegex(EvidenceError, "E_IMMUTABLE"):
                publish_record(raw, root)
```

- [ ] **Step 2: Run the publication test and verify failure**

Run: `python3 -m unittest tests.kinglet_spike.test_publish -v`

Expected: `ERROR` with `ModuleNotFoundError: No module named 'tools.kinglet_spike.publish'`.

- [ ] **Step 3: Implement validate-before-publish and atomic create**

```python
def publish_record(raw_path: Path, repo_root: Path) -> Path:
    record = load_record(raw_path)
    publish_root = raw_path.parent / "publish"
    diagnostics = validate_record(record, publish_root)
    if diagnostics:
        first = diagnostics[0]
        raise EvidenceError(first.code, f"{first.location}: {first.message}")
    committed_root = repo_root / "docs/research/platform-spike"
    targets = []
    for artifact in record.artifacts:
        source = _artifact_path(publish_root, artifact.path)
        artifact_target = committed_root / artifact.path
        targets.append((source, artifact_target))
    target = (
        repo_root / "docs/research/platform-spike/evidence"
        / record.subject.kind / record.subject.id / f"{record.run_id}.json"
    )
    if target.exists() or any(destination.exists() for _, destination in targets):
        raise EvidenceError("E_IMMUTABLE", f"run already published: {record.run_id}")
    for source, destination in targets:
        destination.parent.mkdir(parents=True, exist_ok=True)
        _copy_exclusive(source, destination)
    payload = record_to_json(record).encode("utf-8")
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    except FileExistsError as error:
        raise EvidenceError("E_IMMUTABLE", f"run already published: {record.run_id}") from error
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())
    return target
```

`_copy_exclusive()` uses `O_CREAT|O_EXCL`, streams bytes, fsyncs, verifies the destination SHA-256,
and removes only its incomplete destination if that copy fails. If a later artifact fails, retain
already published immutable files and fail the run; the retry uses a new run ID and new artifact
paths, never overwrites partial history.

`record_to_json()` must use `json.dumps(..., ensure_ascii=False, indent=2, sort_keys=True) + "\n"`.
Add exactly `.kinglet/local/` to `.gitignore`; do not add individual `.research/` clone names or
ignore `docs/research/`.

- [ ] **Step 4: Run publication and validation tests**

Run: `python3 -m unittest tests.kinglet_spike.test_publish tests.kinglet_spike.test_validate -v`

Expected: `Ran 9 tests ... OK`.

- [ ] **Step 5: Commit immutable publication**

```bash
git add .gitignore tools/kinglet_spike/publish.py tests/kinglet_spike/test_publish.py
git commit -m "feat: publish immutable spike evidence"
```

### Task 4: Evaluate the required matrix without false passes

**Files:**
- Create: `tools/kinglet_spike/coverage.py`
- Modify: `tools/kinglet_spike/model.py`
- Create: `spikes/platform/contracts/matrix-v1.json`
- Test: `tests/kinglet_spike/test_coverage.py`

**Interfaces:**
- Consumes: validated published records and a matrix whose cells have `id`, `subject`,
  `probe`, `os`, `release`, and `arch`.
- Produces: frozen `CoverageCell(id: str, state: str, run_ids: tuple[str, ...])` values sorted by
  ID, with state `pass`, `fail`, `unavailable`, `inconclusive`, `invalid`, or `missing`.

- [ ] **Step 1: Write failing state-preservation tests**

```python
# tests/kinglet_spike/test_coverage.py
import unittest

from tools.kinglet_spike.coverage import choose_state


class CoverageTests(unittest.TestCase):
    def test_only_valid_pass_satisfies_cell(self):
        self.assertEqual("pass", choose_state(["pass"]))
        self.assertEqual("fail", choose_state(["pass", "fail"]))
        self.assertEqual("invalid", choose_state(["pass", "invalid"]))

    def test_non_pass_states_remain_distinct(self):
        self.assertEqual("missing", choose_state([]))
        self.assertEqual("unavailable", choose_state(["unavailable"]))
        self.assertEqual("inconclusive", choose_state(["inconclusive"]))

    def test_retry_order_does_not_hide_failed_history(self):
        self.assertEqual("pass", choose_state(["fail", "pass"]))
        self.assertEqual("pass", choose_state(["inconclusive", "pass"]))
```

- [ ] **Step 2: Run the coverage test and verify failure**

Run: `python3 -m unittest tests.kinglet_spike.test_coverage -v`

Expected: `ERROR` with `ModuleNotFoundError: No module named 'tools.kinglet_spike.coverage'`.

- [ ] **Step 3: Implement deterministic cell selection and the fixed matrix**

Use this precedence for the latest valid retry: `invalid`, then the latest record status, with
records sorted by `(ended_at, run_id)`. `choose_state()` is a small unit-test helper that returns
`invalid` when any supplied record is invalid, otherwise the last supplied state, or `missing`.

The matrix must enumerate:

- 4 runtimes × Windows 10 x64, Windows 11 x64, macOS Apple Silicon, macOS Intel, Ubuntu LTS x64;
- 6 client surfaces × Windows, plus native local/MCP/path cells for each officially supported
  macOS/Linux surface;
- 4 Unity routes × Windows 11 x64, macOS Apple Silicon, and Ubuntu LTS x64;
- Unity safe-refusal, mismatched-Editor, bridge-not-ready, cancellation, and orphan-cleanup cases.

Give every cell a stable lowercase dotted ID, for example
`runtime.python.windows-11-x64.host-probe` and
`unity.same-project-headless.windows-11-x64.collision-refusal`. The JSON contract ID is
`kinglet.spike.matrix/v1`; sort cells by ID and reject duplicates.

- [ ] **Step 4: Run coverage tests and validate the matrix file**

Run:
`python3 -m unittest tests.kinglet_spike.test_coverage -v && python3 -m json.tool spikes/platform/contracts/matrix-v1.json >/dev/null`

Expected: `Ran 3 tests ... OK` and exit code `0`.

- [ ] **Step 5: Commit coverage evaluation**

```bash
git add tools/kinglet_spike/coverage.py tests/kinglet_spike/test_coverage.py spikes/platform/contracts/matrix-v1.json
git commit -m "feat: track spike coverage gates"
```

### Task 5: Render deterministic reports and expose the CLI

**Files:**
- Create: `tools/kinglet_spike/report.py`
- Create: `tools/kinglet_spike/cli.py`
- Create: `tools/kinglet_spike/__main__.py`
- Test: `tests/kinglet_spike/test_report.py`
- Test: `tests/kinglet_spike/test_cli.py`

**Interfaces:**
- Consumes: published evidence directory and `matrix-v1.json`.
- Produces: deterministic `coverage.json`, `coverage.md`, and exit code `0` only when the requested
  gate has no `fail`, `invalid`, `inconclusive`, `unavailable`, or `missing` cells.
- Produces internal boundaries
  `validate_path(path: Path, repo_root: Path) -> tuple[Diagnostic, ...]` and
  `gate_is_closed(gate_id: str, repo_root: Path) -> bool`, which `main()` calls.

- [ ] **Step 1: Write failing deterministic report and CLI exit tests**

```python
# tests/kinglet_spike/test_report.py
import unittest

from tools.kinglet_spike.model import CoverageCell
from tools.kinglet_spike.report import render_markdown


class ReportTests(unittest.TestCase):
    def test_markdown_is_sorted_and_byte_stable(self):
        cells = [
            CoverageCell("z.cell", "missing", ()),
            CoverageCell("a.cell", "pass", ("run-a",)),
        ]
        expected = (
            "# Kinglet Platform Spike Coverage\n\n"
            "| Cell | State | Runs |\n| --- | --- | --- |\n"
            "| `a.cell` | pass | `run-a` |\n"
            "| `z.cell` | missing | — |\n"
        )
        self.assertEqual(expected, render_markdown(cells))
        self.assertEqual(expected, render_markdown(reversed(cells)))
```

```python
# tests/kinglet_spike/test_cli.py
import unittest
from unittest.mock import patch

from tools.kinglet_spike.cli import main


class CliTests(unittest.TestCase):
    def test_validate_returns_two_for_invalid_evidence(self):
        with patch("tools.kinglet_spike.cli.validate_path", side_effect=ValueError("bad")):
            self.assertEqual(2, main(["validate", "record.json"]))

    def test_gate_returns_one_for_open_cells(self):
        with patch("tools.kinglet_spike.cli.gate_is_closed", return_value=False):
            self.assertEqual(1, main(["gate", "0A"]))
```

- [ ] **Step 2: Run the report and CLI tests and verify failure**

Run: `python3 -m unittest tests.kinglet_spike.test_report tests.kinglet_spike.test_cli -v`

Expected: imports fail because `report.py` and `cli.py` do not exist.

- [ ] **Step 3: Implement rendering and four explicit commands**

The parser exposes:

```text
python3 -m tools.kinglet_spike validate <record.json> --repo-root <path>
python3 -m tools.kinglet_spike publish <record.json> --repo-root <path>
python3 -m tools.kinglet_spike report --repo-root <path> --matrix <matrix.json>
python3 -m tools.kinglet_spike gate <0A|0R|0C:<client>|0U|0D> --repo-root <path>
```

Use exit codes `0=accepted/closed`, `1=valid but gate open`, `2=invalid invocation or evidence`.
Write reports through a sibling `.tmp` file followed by `os.replace`. The Markdown renderer must
produce the exact table in the failing test. JSON output must include `schema`,
`generated_from_matrix`, and sorted `cells`; it must not include a current timestamp.

- [ ] **Step 4: Run all Python harness tests**

Run: `python3 -m unittest discover -s tests/kinglet_spike -t . -v`

Expected: all harness tests pass with `OK`.

- [ ] **Step 5: Commit reports and CLI**

```bash
git add tools/kinglet_spike tests/kinglet_spike
git commit -m "feat: report platform spike gates"
```

### Task 6: Integrate the harness with repository verification

**Files:**
- Create: `tests/test-kinglet-spike.sh`
- Modify: `.github/workflows/ci.yml`
- Create: `docs/research/platform-spike/README.md`
- Create: `docs/research/platform-spike/evidence/.gitkeep`
- Create: `docs/research/platform-spike/artifacts/.gitkeep`
- Create: `docs/research/platform-spike/reports/.gitkeep`

**Interfaces:**
- Consumes: the existing `tests/run-tests.sh` auto-discovery convention.
- Produces: one shell-suite entry, one CI step, and a documented reviewer path.

- [ ] **Step 1: Add the failing aggregate bridge**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
python3 -m unittest discover -s tests/kinglet_spike -t . -v
echo "PASS: Kinglet spike harness unit tests"
```

Run: `bash tests/test-kinglet-spike.sh`

Expected before making it executable: exit code `0`; the aggregate runner’s executable check added
in the next step should fail until mode `755` is set.

- [ ] **Step 2: Make the bridge executable and add a CI determinism check**

Run: `chmod +x tests/test-kinglet-spike.sh`

Add after the existing “Run test suite” CI step:

```yaml
      - name: Verify spike contract JSON
        run: |
          python3 -m json.tool spikes/platform/contracts/evidence-v1.json > /dev/null
          python3 -m json.tool spikes/platform/contracts/matrix-v1.json > /dev/null
```

- [ ] **Step 3: Document the evidence boundary**

In `docs/research/platform-spike/README.md`, state the raw and committed paths, the four commands
from Task 5, immutable retry rule, artifact size rule, secret/path prohibition, and reviewer
sequence: inspect record → verify checksum → regenerate report → evaluate gate. Explicitly say that
manual prose cannot change a record status.

- [ ] **Step 4: Run focused and full verification**

Run:

```bash
python3 -m unittest discover -s tests/kinglet_spike -t . -v
bash tests/run-tests.sh
git diff --check
```

Expected: harness tests end in `OK`; aggregate runner reports `Failed: 0`; `git diff --check` emits
no output.

- [ ] **Step 5: Prove byte-stable regeneration**

Run:

```bash
python3 -m tools.kinglet_spike report --repo-root . --matrix spikes/platform/contracts/matrix-v1.json
sha256sum docs/research/platform-spike/reports/coverage.json docs/research/platform-spike/reports/coverage.md
python3 -m tools.kinglet_spike report --repo-root . --matrix spikes/platform/contracts/matrix-v1.json
sha256sum docs/research/platform-spike/reports/coverage.json docs/research/platform-spike/reports/coverage.md
```

Expected: the two SHA-256 pairs are identical. All cells are initially `missing`; report generation
still exits `0`, while `gate 0R`, `gate 0C:claude-code`, and `gate 0U` exit `1`.

- [ ] **Step 6: Commit the accepted 0A gate**

```bash
git add .github/workflows/ci.yml tests/test-kinglet-spike.sh docs/research/platform-spike
git commit -m "ci: enforce platform spike evidence"
```

## Plan acceptance

Before marking 0A closed, verify:

- every invalid record is rejected before publication;
- no committed record can escape `docs/research/platform-spike/`;
- a second publication of the same run ID fails;
- missing, unavailable, inconclusive, fail, and invalid never satisfy a gate;
- report regeneration is byte-identical;
- existing Python and shell suites still pass;
- `git grep -nE '(/Users/|/home/|[A-Z]:\\\\Users\\\\|gh[pousr]_|sk-)' docs/research/platform-spike`
  returns no sensitive match.
