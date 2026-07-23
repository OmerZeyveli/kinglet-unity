# Kinglet 00R Runtime Bake-off Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce directly comparable native evidence for bundled Python, Rust, Go, and self-contained .NET, then select a core runtime only if a candidate passes every hard gate.

**Architecture:** One immutable Host Probe contract and one black-box conformance runner are frozen before candidate code. Each candidate independently implements the same executable protocol, is packaged without an end-user runtime, and is run on the same native host matrix; 00A validates and publishes the results before a fixed rubric can score them.

**Tech Stack:** 00A evidence harness; Python 3.14.6 + uv 0.11.28 + PyInstaller 6.21.0 + cryptography 49.0.0; Rust 1.97.1 + Cargo + ed25519-dalek 3.0.0; Go 1.26.5; .NET SDK 10.0.302/runtime 10.0.10 + NSec.Cryptography 26.4.0; PowerShell 7; POSIX shell; JSON.

## Global Constraints

- 00A must be closed before any runtime result is accepted.
- The existing `tools/kinglet_build/` implementation and its tests are a protected migration asset.
- No candidate receives a simplified case, weaker assertion, or a candidate-specific scoring rule.
- A distributable must run without a separately installed user runtime or toolchain.
- Required native hosts are Windows 10 22H2 x64, Windows 11 25H2 x64, macOS Tahoe 26.5.2 Apple Silicon, macOS Tahoe 26.5.2 Intel, and Ubuntu 24.04.4 LTS x64.
- Windows probes use native PowerShell and native executables; WSL and Git Bash are forbidden.
- Cross-compilation is build evidence only and never closes a runtime cell.
- Every cold-start measurement uses 30 individual samples and reports integer microseconds, median, and p95.
- Every candidate must pass manifest, Unicode/space path, atomic replace, lease, process-tree cancellation, SHA-256, Ed25519, structured error, crash cleanup, timeout cleanup, packaging, provenance, and redaction gates on every native host.
- A hard-gate failure disqualifies the candidate from weighted scoring but remains committed evidence.
- The fixed weights total 100; a difference of three or fewer points triggers the approved tie-break order.
- Runtime selection requires explicit user approval and an ADR; this plan must not silently choose a winner.

---

## File map

| Path | Responsibility |
| --- | --- |
| `spikes/platform/runtime/contract/host-probe-v1.json` | Fixed operations, assertions, timing, and result schema ID |
| `spikes/platform/runtime/contract/canonical-valid/` | Representative valid canonical tree copied from the protected baseline fixture |
| `spikes/platform/runtime/contract/canonical-invalid/` | Same tree with one fixed unknown descriptor field |
| `spikes/platform/runtime/contract/ed25519-rfc8032.json` | Public RFC 8032 verification vector |
| `tools/kinglet_spike/runtime_contract.py` | Candidate-neutral executable launcher and result validator |
| `spikes/platform/runtime/python/` | Bundled-Python candidate and native PyInstaller package |
| `spikes/platform/runtime/rust/` | Rust candidate |
| `spikes/platform/runtime/go/` | Go candidate |
| `spikes/platform/runtime/dotnet/` | Self-contained .NET candidate |
| `spikes/platform/runtime/run-host.ps1` | Windows-native build/run/measure/publish entry point |
| `spikes/platform/runtime/run-host.sh` | macOS/Linux native build/run/measure/publish entry point |
| `spikes/platform/runtime/toolchains.lock.json` | Exact toolchain, dependency, license, and source lock |
| `spikes/platform/runtime/rubric-v1.json` | Frozen hard gates, scoring bands, weights, and tie rule |
| `docs/research/platform-spike/reports/runtime-comparison.md` | Generated facts and reviewer-entered qualitative judgments |
| `docs/architecture/adr/0001-kinglet-core-runtime.md` | User-approved final decision |

## Executable protocol

Every packaged candidate must support:

```text
kinglet-host-probe --version
kinglet-host-probe run --contract <absolute-contract.json> --workspace <absolute-dir> --result <absolute-result.json>
kinglet-host-probe child --sentinel <absolute-file> --lifetime-ms <positive-int>
```

`run` returns `0` only when all internal assertions pass, `1` when a contract assertion fails, and
`2` for invalid invocation. It atomically writes `kinglet.host-probe.result/v1` JSON. Stable error
categories are:

```text
manifest.invalid filesystem.atomic-replace lease.busy lease.owner
process.timeout process.cleanup crypto.digest crypto.signature internal
```

### Task 1: Freeze the Host Probe contract and black-box test runner

**Files:**
- Create: `spikes/platform/runtime/contract/host-probe-v1.json`
- Create: `spikes/platform/runtime/contract/canonical-valid/`
- Create: `spikes/platform/runtime/contract/canonical-invalid/`
- Create: `spikes/platform/runtime/contract/ed25519-rfc8032.json`
- Create: `tools/kinglet_spike/runtime_contract.py`
- Test: `tests/kinglet_spike/test_runtime_contract.py`

**Interfaces:**
- Consumes: a packaged candidate path and the three fixed contract fixtures.
- Produces: `run_candidate(executable: Path, contract_dir: Path, workspace: Path) -> HostProbeResult`
  and `validate_host_result(value: object) -> HostProbeResult`.

- [ ] **Step 1: Write failing result-contract tests**

```python
# tests/kinglet_spike/test_runtime_contract.py
import unittest

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.runtime_contract import REQUIRED_ASSERTIONS, validate_host_result


def valid_result() -> dict:
    return {
        "schema": "kinglet.host-probe.result/v1",
        "candidate": {"id": "fake", "version": "1.0.0"},
        "status": "pass",
        "errors": [],
        "assertions": [{"id": item, "status": "pass"} for item in REQUIRED_ASSERTIONS],
        "descendant_pids": [],
        "active_lease": False,
    }


class RuntimeContractTests(unittest.TestCase):
    def test_accepts_complete_pass(self):
        self.assertEqual("pass", validate_host_result(valid_result()).status)

    def test_rejects_missing_assertion(self):
        value = valid_result()
        value["assertions"].pop()
        with self.assertRaisesRegex(EvidenceError, "E_ASSERTION"):
            validate_host_result(value)

    def test_rejects_pass_with_descendant_or_lease(self):
        for field, value in (("descendant_pids", [4123]), ("active_lease", True)):
            result = valid_result()
            result[field] = value
            with self.subTest(field=field):
                with self.assertRaisesRegex(EvidenceError, "E_ASSERTION"):
                    validate_host_result(result)
```

- [ ] **Step 2: Run the contract tests and verify failure**

Run: `python3 -m unittest tests.kinglet_spike.test_runtime_contract -v`

Expected: import error for `tools.kinglet_spike.runtime_contract`.

- [ ] **Step 3: Add the fixed assertions and exact fixtures**

`REQUIRED_ASSERTIONS` must be this tuple:

```python
REQUIRED_ASSERTIONS = (
    "manifest.accept-valid",
    "manifest.reject-unknown",
    "path.unicode-space",
    "filesystem.atomic-replace",
    "lease.acquire",
    "lease.renew",
    "lease.reject-competitor",
    "lease.expire",
    "lease.release",
    "process.child-grandchild",
    "process.cancel",
    "process.no-descendants",
    "crypto.sha256",
    "crypto.ed25519",
    "cleanup.success",
    "cleanup.crash",
    "cleanup.timeout",
    "cleanup.cancel",
)
```

Use RFC 8032 test vector 1 in `ed25519-rfc8032.json`: empty message, public key
`d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a`, and signature
`e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155`
`5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b`.

Copy `tests/kinglet/fixtures/valid-minimal/` byte-for-byte to `canonical-valid/`; this fixes the
seven-capability catalog plus the four units `knowledge.serialization`, `role.unity-scout`,
`rule.pc-console`, and `workflow.unity-audit`. Copy that tree to `canonical-invalid/` and add only
`"unknown": true` to `src/roles/unity-scout/role.json`. The contract requires the valid tree to
yield those exact capabilities/IDs and the invalid tree to yield stable category
`manifest.invalid`.

The contract fixes lease TTL at 1200 ms, renewal at 400 ms, competitor attempt at 600 ms, child
lifetime at 30000 ms, cancellation deadline at 5000 ms, and result schema above.

- [ ] **Step 4: Implement strict result validation and subprocess timeout**

Launch candidates with a new process group/session. On Windows pass
`CREATE_NEW_PROCESS_GROUP`; on POSIX pass `start_new_session=True`. If 60 seconds elapse, terminate
the whole group, wait 5 seconds, then kill the group. Validate exact top-level keys, exact assertion
IDs, empty descendants, false lease, and one result per required assertion.

- [ ] **Step 5: Run focused and existing baseline tests**

Run:

```bash
python3 -m unittest tests.kinglet_spike.test_runtime_contract -v
python3 -m unittest discover -s tests/kinglet -t . -v
```

Expected: runtime contract tests pass; existing suite still reports 122 passing tests.

- [ ] **Step 6: Commit the frozen candidate-neutral contract**

```bash
git add spikes/platform/runtime/contract tools/kinglet_spike/runtime_contract.py tests/kinglet_spike/test_runtime_contract.py
git commit -m "test: freeze runtime host probe contract"
```

### Task 2: Implement and package the bundled-Python candidate

**Files:**
- Create: `spikes/platform/runtime/python/pyproject.toml`
- Create: `spikes/platform/runtime/python/uv.lock`
- Create: `spikes/platform/runtime/python/kinglet_host_probe.py`
- Create: `spikes/platform/runtime/python/kinglet-host-probe.spec`
- Create: `spikes/platform/runtime/python/test_candidate.py`

**Interfaces:**
- Consumes: `tools.kinglet_build.loader.load_graph`, the frozen Host Probe fixtures, and
  `cryptography.hazmat.primitives.asymmetric.ed25519.Ed25519PublicKey`.
- Produces: packaged candidate ID `python-bundled`, version `3.14.6-pyinstaller6.21.0`.

- [ ] **Step 1: Pin the candidate dependency and write its failing unit tests**

```toml
# spikes/platform/runtime/python/pyproject.toml
[project]
name = "kinglet-python-host-probe"
version = "0.0.1"
requires-python = "==3.14.6"
dependencies = ["cryptography==49.0.0"]

[dependency-groups]
dev = ["pyinstaller==6.21.0"]
```

```python
# spikes/platform/runtime/python/test_candidate.py
import tempfile
import unittest
from pathlib import Path

from kinglet_host_probe import atomic_replace, verify_ed25519


class PythonCandidateTests(unittest.TestCase):
    def test_atomic_replace_leaves_only_complete_new_file(self):
        with tempfile.TemporaryDirectory(prefix="Kral Yalıçapkını ") as directory:
            target = Path(directory) / "state.json"
            target.write_text("old", encoding="utf-8")
            atomic_replace(target, b"new\n")
            self.assertEqual(b"new\n", target.read_bytes())
            self.assertEqual([], list(target.parent.glob("*.tmp")))

    def test_rfc8032_vector(self):
        self.assertTrue(verify_ed25519(
            "",
            "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
            "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155"
            "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
        ))
```

- [ ] **Step 2: Run the candidate unit tests and verify failure**

Run from `spikes/platform/runtime/python`:
`python3 -m unittest test_candidate -v`

Expected: import failure because `kinglet_host_probe.py` does not exist.

- [ ] **Step 3: Implement the complete command boundary**

The module must expose `atomic_replace`, `verify_ed25519`, `Lease`, `spawn_tree_and_cancel`,
`run_contract`, and `main`. Atomic replacement writes a unique sibling created with
`O_CREAT|O_EXCL`, flushes and `fsync`s it, calls `os.replace`, then fsyncs the containing directory
where supported. `Lease` stores owner UUID and UTC expiry in JSON, acquires by exclusive create,
renews only its own owner, treats malformed leases as busy, and removes only its own lease.

Use this signature implementation:

```python
def verify_ed25519(message_hex: str, public_hex: str, signature_hex: str) -> bool:
    try:
        Ed25519PublicKey.from_public_bytes(bytes.fromhex(public_hex)).verify(
            bytes.fromhex(signature_hex), bytes.fromhex(message_hex)
        )
        return True
    except (ValueError, InvalidSignature):
        return False
```

For canonical validation, call the existing `load_graph()` on `canonical-valid/` and
`canonical-invalid/`; map the expected `BuildError` to `manifest.invalid`. This is the measured
reuse path and may not be replaced by a second Python-only manifest parser.

For cancellation, launch this same executable with `child`; the child launches its own `child`
grandchild once, writes PIDs to the sentinel, and sleeps. The parent terminates the process group
and proves every recorded PID is gone before emitting `process.no-descendants=pass`. Wrap every
scenario in `try/finally` so leases and descendants are cleaned after injected success, crash,
timeout, and cancellation modes.

The PyInstaller spec must use `onefile`, include `tools/kinglet_build` as source, collect
cryptography binaries, set console mode, and name the artifact `kinglet-host-probe`.

- [ ] **Step 4: Run unit and unpackaged black-box conformance**

Run:

```bash
python3 -m unittest spikes.platform.runtime.python.test_candidate -v
python3 spikes/platform/runtime/python/kinglet_host_probe.py run \
  --contract spikes/platform/runtime/contract/host-probe-v1.json \
  --workspace ".kinglet/local/spikes/python dev/Kral Yalıçapkını" \
  --result ".kinglet/local/spikes/python dev/result.json"
```

Expected: unit tests pass; command exits `0`; result has 18 passing assertions, no descendants,
and no active lease.

- [ ] **Step 5: Build the native one-file artifact**

Run with the pinned build tool:

```bash
uv python install 3.14.6
uv lock --project spikes/platform/runtime/python --python 3.14.6
uv sync --project spikes/platform/runtime/python --frozen --python 3.14.6
uv run --project spikes/platform/runtime/python pyinstaller --clean \
  spikes/platform/runtime/python/kinglet-host-probe.spec
dist/kinglet-host-probe --version
```

Expected: `uv.lock` records exact direct/transitive versions and source hashes; version output is
`python-bundled 3.14.6-pyinstaller6.21.0`.

- [ ] **Step 6: Commit the Python candidate**

```bash
git add spikes/platform/runtime/python
git commit -m "spike: add bundled Python host probe"
```

### Task 3: Implement and package the Rust candidate

**Files:**
- Create: `spikes/platform/runtime/rust/Cargo.toml`
- Create: `spikes/platform/runtime/rust/Cargo.lock`
- Create: `spikes/platform/runtime/rust/src/main.rs`
- Create: `spikes/platform/runtime/rust/src/lease.rs`
- Create: `spikes/platform/runtime/rust/src/process.rs`

**Interfaces:**
- Consumes: the frozen Host Probe files only; never imports Python candidate code.
- Produces: candidate ID `rust`, version `1.97.1`.

- [ ] **Step 1: Pin dependencies and write failing Rust tests**

```toml
[package]
name = "kinglet-host-probe"
version = "0.0.1"
edition = "2024"
rust-version = "1.97.1"

[dependencies]
ed25519-dalek = "3.0.0"
hex = "0.4.3"
serde = { version = "1.0.219", features = ["derive"] }
serde_json = "1.0.140"
sha2 = "0.10.9"
uuid = { version = "1.16.0", features = ["v4"] }
```

In `lease.rs`, add tests named `competitor_cannot_acquire_live_lease` and
`expired_lease_can_be_replaced`. In `main.rs`, add `rfc8032_vector_verifies` using the exact vector
from Task 1 and `atomic_replace_survives_unicode_space_path`.

- [ ] **Step 2: Run Rust tests and verify compile failure**

Run: `cargo +1.97.1 test --manifest-path spikes/platform/runtime/rust/Cargo.toml`

Expected: compile failures for the unimplemented lease and verification functions.

- [ ] **Step 3: Implement the protocol with platform-native process groups**

Use `OpenOptions::create_new(true)` for leases and staging, `File::sync_all`, `std::fs::rename`,
and directory sync on POSIX. Use Job Objects with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` on Windows;
use a fresh process group plus `killpg` on macOS/Linux. Keep Windows bindings in a
`cfg(windows)` section and POSIX code in `cfg(unix)`. `main.rs` must emit the exact result keys and
18 assertion IDs from Task 1 and the same stable error categories.

For Ed25519:

```rust
let key = VerifyingKey::from_bytes(&public_key.try_into()?)?;
let signature = Signature::from_slice(&signature_bytes)?;
key.verify_strict(&message, &signature)?;
```

- [ ] **Step 4: Run tests, locked release build, and black-box conformance**

Run:

```bash
cargo +1.97.1 test --locked --manifest-path spikes/platform/runtime/rust/Cargo.toml
cargo +1.97.1 build --locked --release --manifest-path spikes/platform/runtime/rust/Cargo.toml
python3 -m tools.kinglet_spike.runtime_contract \
  --executable spikes/platform/runtime/rust/target/release/kinglet-host-probe \
  --contract-dir spikes/platform/runtime/contract
```

Expected: Rust tests pass; black-box runner reports `18/18 assertions passed`.

- [ ] **Step 5: Record licenses and commit**

Run: `cargo metadata --locked --format-version 1 > .kinglet/local/spikes/rust-cargo-metadata.json`

Expected: metadata names every direct and transitive crate. Add their SPDX identifiers and source
URLs to `toolchains.lock.json` in Task 6.

```bash
git add spikes/platform/runtime/rust
git commit -m "spike: add Rust host probe"
```

### Task 4: Implement and package the Go candidate

**Files:**
- Create: `spikes/platform/runtime/go/go.mod`
- Create: `spikes/platform/runtime/go/main.go`
- Create: `spikes/platform/runtime/go/lease.go`
- Create: `spikes/platform/runtime/go/process_windows.go`
- Create: `spikes/platform/runtime/go/process_unix.go`
- Create: `spikes/platform/runtime/go/main_test.go`

**Interfaces:**
- Consumes: the frozen Host Probe files and Go standard library only.
- Produces: candidate ID `go`, version `1.26.5`.

- [ ] **Step 1: Create the module and failing behavior tests**

```go
module kinglet.dev/spikes/host-probe

go 1.26.5
```

Tests must create `t.TempDir()/Kral Yalıçapkını`, assert atomic replacement has no partial file,
assert a second owner cannot acquire a live lease, assert an expired lease can be replaced, and
verify the RFC 8032 vector with `crypto/ed25519.Verify`.

- [ ] **Step 2: Run tests and verify failure**

Run: `cd spikes/platform/runtime/go && go version && go test ./...`

Expected: version begins `go version go1.26.5`; compile failures name `atomicReplace`,
`acquireLease`, and `runContract`.

- [ ] **Step 3: Implement the complete protocol**

Use `os.OpenFile(..., os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)`, `File.Sync`, and `os.Rename`.
Decode JSON with `Decoder.DisallowUnknownFields()`. On Windows create and assign descendants to a
Job Object with kill-on-close; on POSIX set `Setpgid: true` and kill the negative process group ID.
Use `crypto/sha256` and `crypto/ed25519`; add no third-party dependency. Emit the same 18 assertions,
stable categories, and cleanup state as the other candidates.

- [ ] **Step 4: Run unit, race, release, and black-box tests**

Run:

```bash
cd spikes/platform/runtime/go
go version
go test -race ./...
go build -trimpath -ldflags="-s -w" -o dist/kinglet-host-probe .
cd ../../../..
python3 -m tools.kinglet_spike.runtime_contract \
  --executable spikes/platform/runtime/go/dist/kinglet-host-probe \
  --contract-dir spikes/platform/runtime/contract
```

Expected: tests pass; black-box runner reports `18/18 assertions passed`.

- [ ] **Step 5: Commit the Go candidate**

```bash
git add spikes/platform/runtime/go
git commit -m "spike: add Go host probe"
```

### Task 5: Implement and package the self-contained .NET candidate

**Files:**
- Create: `spikes/platform/runtime/dotnet/Kinglet.HostProbe.csproj`
- Create: `spikes/platform/runtime/dotnet/Program.cs`
- Create: `spikes/platform/runtime/dotnet/Lease.cs`
- Create: `spikes/platform/runtime/dotnet/ProcessTree.cs`
- Create: `spikes/platform/runtime/dotnet/Kinglet.HostProbe.Tests/Kinglet.HostProbe.Tests.csproj`
- Create: `spikes/platform/runtime/dotnet/Kinglet.HostProbe.Tests/ProbeTests.cs`
- Create: `spikes/platform/runtime/dotnet/packages.lock.json`

**Interfaces:**
- Consumes: frozen Host Probe files and NSec.Cryptography 26.4.0.
- Produces: candidate ID `dotnet-self-contained`, version `10.0.10`.

- [ ] **Step 1: Pin the project and write failing xUnit tests**

The executable project targets `net10.0`, enables nullable and invariant globalization, pins
`NSec.Cryptography` 26.4.0, and enables locked restore. The test project pins
`Microsoft.NET.Test.Sdk` 17.14.1 and `xunit` 2.9.3. Tests cover the same four atomic/lease/Ed25519
behaviors as Go and assert `HostResult` serializes the exact 18 IDs.

- [ ] **Step 2: Run tests and verify compile failure**

Run:
`dotnet test spikes/platform/runtime/dotnet/Kinglet.HostProbe.Tests/Kinglet.HostProbe.Tests.csproj --locked-mode`

Expected: compile failures for missing `Lease`, `ProcessTree`, and `ProbeRunner`.

- [ ] **Step 3: Implement the protocol**

Use `FileMode.CreateNew`, `FileStream.Flush(flushToDisk: true)`, and `File.Move(temp, target, true)`.
Use a Windows Job Object with kill-on-close and POSIX process groups through minimal
`LibraryImport` declarations. Parse with `JsonUnmappedMemberHandling.Disallow`.

Verify the fixed signature with:

```csharp
var algorithm = SignatureAlgorithm.Ed25519;
var publicKey = PublicKey.Import(
    algorithm,
    Convert.FromHexString(publicHex),
    KeyBlobFormat.RawPublicKey);
return algorithm.Verify(
    publicKey,
    Convert.FromHexString(messageHex),
    Convert.FromHexString(signatureHex));
```

Emit the same result protocol and cleanup assertions. Do not use shell scripts from the executable.

- [ ] **Step 4: Test and publish one self-contained file per native RID**

Run on the matching host, substituting only the native RID from this fixed list:
`win-x64`, `osx-arm64`, `osx-x64`, `linux-x64`.

```bash
dotnet test spikes/platform/runtime/dotnet/Kinglet.HostProbe.Tests/Kinglet.HostProbe.Tests.csproj --locked-mode
dotnet publish spikes/platform/runtime/dotnet/Kinglet.HostProbe.csproj \
  -c Release -r linux-x64 --self-contained true \
  -p:PublishSingleFile=true -p:PublishTrimmed=true -p:ContinuousIntegrationBuild=true
```

Expected: tests pass; published directory contains the executable and lock/runtime metadata; the
artifact runs after the .NET SDK is removed from `PATH`.

- [ ] **Step 5: Run black-box conformance and commit**

Run the published executable through `tools.kinglet_spike.runtime_contract`; expected:
`18/18 assertions passed`.

```bash
git add spikes/platform/runtime/dotnet
git commit -m "spike: add self-contained dotnet host probe"
```

### Task 6: Freeze toolchains, hard gates, and weighted rubric

**Files:**
- Create: `spikes/platform/runtime/toolchains.lock.json`
- Create: `spikes/platform/runtime/rubric-v1.json`
- Create: `tests/kinglet_spike/test_runtime_rubric.py`
- Modify: `tools/kinglet_spike/runtime_contract.py`

**Interfaces:**
- Consumes: candidate lockfiles and the approved design weights.
- Produces:
  - `load_rubric(path: Path) -> RuntimeRubric`
  - `score_candidate(hard_gates: Mapping[str, bool], category_scores: Mapping[str, int]) -> CandidateScore`
  - `requires_tie_review(first: int, second: int) -> bool`.

- [ ] **Step 1: Write failing hard-gate, weight, and tie tests**

```python
from pathlib import Path
import unittest

from tools.kinglet_spike.runtime_contract import (
    load_rubric,
    requires_tie_review,
    score_candidate,
)


class RuntimeRubricTests(unittest.TestCase):
    def test_weights_total_one_hundred(self):
        rubric = load_rubric(Path("spikes/platform/runtime/rubric-v1.json"))
        self.assertEqual(100, sum(rubric.weights.values()))

    def test_failed_hard_gate_is_not_scored(self):
        gates = {"windows-native": False}
        result = score_candidate(gates, {})
        self.assertEqual("disqualified", result.state)

    def test_three_points_or_less_requires_tie_review(self):
        self.assertTrue(requires_tie_review(88, 85))
        self.assertFalse(requires_tie_review(88, 84))
```

- [ ] **Step 2: Run the rubric tests and verify failure**

Run: `python3 -m unittest tests.kinglet_spike.test_runtime_rubric -v`

Expected: import failure for rubric functions.

- [ ] **Step 3: Commit exact locks before accepting results**

`toolchains.lock.json` must pin the versions in this plan, host releases, download source URL,
download SHA-256, license/SPDX, and candidate dependency lock path. `rubric-v1.json` must copy the
nine hard gates and weights `25,20,20,15,10,10` from the approved design. Qualitative bands are
`0=blocking`, `1=high risk`, `2=material risk`, `3=acceptable`, `4=strong`, `5=best evidenced`;
each non-measured score requires an evidence record ID and reviewer rationale.

- [ ] **Step 4: Implement scoring without a winner side effect**

The scorer returns sorted candidate facts and whether tie review is required. It must not write the
ADR or change gate state. Reject missing judgments, evidence references, out-of-range scores,
weights that do not total 100, and any scored candidate with a failed/open hard gate.

- [ ] **Step 5: Run rubric and contract tests**

Run:
`python3 -m unittest tests.kinglet_spike.test_runtime_rubric tests.kinglet_spike.test_runtime_contract -v`

Expected: all tests pass.

- [ ] **Step 6: Commit the pre-result rubric**

```bash
git add spikes/platform/runtime/toolchains.lock.json spikes/platform/runtime/rubric-v1.json tools/kinglet_spike/runtime_contract.py tests/kinglet_spike/test_runtime_rubric.py
git commit -m "test: freeze runtime selection rubric"
```

### Task 7: Execute, measure, and publish every native host cell

**Files:**
- Create: `spikes/platform/runtime/run-host.ps1`
- Create: `spikes/platform/runtime/run-host.sh`
- Create: `spikes/platform/runtime/measure.ps1`
- Create: `spikes/platform/runtime/measure.sh`
- Create: `tests/kinglet_spike/test_runtime_host_scripts.py`
- Create per run: `.kinglet/local/spikes/<run-id>/` (ignored)
- Publish per run: `docs/research/platform-spike/evidence/runtime/<candidate>/<run-id>.json`
- Publish small artifacts: `docs/research/platform-spike/artifacts/runtime/<candidate>/<run-id>/`

**Interfaces:**
- Consumes: native toolchains, candidate sources, fixed contract, 00A `publish`.
- Produces: immutable runtime evidence with 30 cold-start samples, peak RSS bytes, artifact bytes,
  dependency count, build/run commands, and all hard-gate assertions.

- [ ] **Step 1: Write host-script contract tests**

Add tests that parse both scripts and assert:

- Windows script rejects `$env:WSL_DISTRO_NAME` and requires
  `Microsoft Windows 10`/`Microsoft Windows 11`;
- shell script accepts only `Darwin` or `Linux`;
- both require an empty new run directory;
- both invoke all four candidates and 00A publication;
- both run the packaged artifact after removing toolchain directories from `PATH`;
- both collect exactly 30 starts and process-tree/lease cleanup results.

- [ ] **Step 2: Run the host-script tests and verify failure**

Run: `python3 -m unittest tests.kinglet_spike.test_runtime_host_scripts -v`

Expected: failure because the scripts do not exist.

- [ ] **Step 3: Implement native host runners**

PowerShell uses `Get-CimInstance Win32_OperatingSystem`, `Get-FileHash`, `Measure-Command`,
`Get-Process.PeakWorkingSet64`, and an argument array to `Start-Process`; it must not invoke
`bash`, `wsl`, or string-evaluated commands. POSIX uses `uname`, `sw_vers` or `/etc/os-release`,
`shasum -a 256` on macOS, `sha256sum` on Ubuntu, `/usr/bin/time -l` on macOS, and
`/usr/bin/time -v` on Ubuntu.

Each runner first records the actual host/toolchain versions and refuses a mismatch with the
locked environment. It builds locally, copies only the distributable into a clean execution
directory, clears toolchains from child `PATH`, performs black-box conformance, measures 30 starts,
checks no descendant PID and no lease after success/crash/timeout/cancel, constructs 00A evidence,
and calls `python3 -m tools.kinglet_spike publish`.

- [ ] **Step 4: Run one smoke cell without publishing**

Run on the current native host with `-WhatIf` (PowerShell) or `--dry-run` (shell).

Expected: exact build/run/measurement commands for four candidates, no filesystem mutation outside
`.kinglet/local/`, and explicit refusal if the host release is not locked.

- [ ] **Step 5: Execute all 20 candidate/host cells**

Run the native script on each of the five locked hosts. Do not copy a result between hosts. A
missing physical host produces no pass record; record the cell as inconclusive only with a reason
and reviewer source.

Expected per cell: 18/18 Host Probe assertions, 30 cold-start samples, artifact/checksum, peak RSS,
dependency footprint, exact native commands, and no live descendants or lease. Failures are
published with `status=fail`, not rerun away.

- [ ] **Step 6: Regenerate runtime coverage**

Run:

```bash
python3 -m tools.kinglet_spike report --repo-root . --matrix spikes/platform/contracts/matrix-v1.json
python3 -m tools.kinglet_spike gate 0R --repo-root .
```

Expected: gate exits `0` only when every required runtime cell has valid evidence. Any required
host that is missing/inconclusive keeps exit code `1`.

- [ ] **Step 7: Commit sanitized native evidence**

```bash
git add spikes/platform/runtime/run-host.ps1 spikes/platform/runtime/run-host.sh \
  spikes/platform/runtime/measure.ps1 spikes/platform/runtime/measure.sh \
  docs/research/platform-spike/evidence/runtime docs/research/platform-spike/artifacts/runtime \
  docs/research/platform-spike/reports
git commit -m "test: record native runtime bake-off evidence"
```

### Task 8: Review the result and approve the runtime ADR

**Files:**
- Create: `docs/research/platform-spike/reports/runtime-comparison.md`
- Create: `docs/architecture/adr/0001-kinglet-core-runtime.md`
- Modify: `docs/superpowers/plans/2026-07-23-kinglet-00-plan-suite.md`

**Interfaces:**
- Consumes: only published valid evidence, frozen rubric, and explicit reviewer judgments.
- Produces: one approved runtime ADR or an explicit “no candidate selected” ADR.

- [ ] **Step 1: Generate the comparison report**

Run:
`python3 -m tools.kinglet_spike runtime-report --rubric spikes/platform/runtime/rubric-v1.json --repo-root .`

Expected: each candidate shows hard-gate state, measurements, dependencies/licenses, qualitative
evidence references, weighted score only if qualified, and tie-review state.

- [ ] **Step 2: Verify report provenance**

For every fact row, open the linked record, recalculate artifact SHA-256, and run report generation
twice. Expected: every checksum matches and report bytes are identical.

- [ ] **Step 3: Obtain explicit user approval**

Present qualified candidates, disqualifications, sensitivity of reviewer judgments, tie-break
results when applicable, and migration impact on `tools/kinglet_build/`. If none qualifies, present
that result without proposing a fake winner. Do not write an “Accepted” ADR until the user approves
the named decision.

- [ ] **Step 4: Write the ADR with the approved outcome**

The ADR must include Status, Context, Decision, Hard-gate evidence, Weighted rubric, Existing
Python keep/adapt/replace implications, Rejected alternatives, Consequences, and Revisit triggers.
Every candidate claim links to a committed evidence record or report. Mark 0R closed in the plan
suite only if a runtime was approved and all required cells passed.

- [ ] **Step 5: Run final runtime verification**

Run:

```bash
python3 -m unittest discover -s tests/kinglet_spike -t . -v
python3 -m tools.kinglet_spike gate 0R --repo-root .
bash tests/run-tests.sh
git diff --check
```

Expected: spike tests pass; `gate 0R` exits `0`; aggregate suite has `Failed: 0`; diff check is
silent.

- [ ] **Step 6: Commit the approved decision**

```bash
git add docs/research/platform-spike/reports/runtime-comparison.md \
  docs/architecture/adr/0001-kinglet-core-runtime.md \
  docs/superpowers/plans/2026-07-23-kinglet-00-plan-suite.md
git commit -m "docs: select Kinglet core runtime"
```

## Plan acceptance

Do not mark 0R closed unless all 20 native runtime cells are valid, at least one candidate passes
all nine hard gates, the fixed rubric was committed before results, dependencies and licenses are
complete, failed history remains visible, the existing Python baseline still passes, and the user
explicitly approved the ADR.
