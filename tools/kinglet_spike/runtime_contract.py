"""runtime_contract.py — Host Probe contract: frozen assertion IDs, result validation,
and subprocess launcher for black-box candidate testing.

The contract is candidate-neutral: every runtime under evaluation (Python, Rust,
Go, .NET) is measured against the same REQUIRED_ASSERTIONS tuple, the same
fixed timings, and the same validate_host_result schema.
"""
from __future__ import annotations

import os
import signal
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from tools.kinglet_spike.model import EvidenceError

# ---------------------------------------------------------------------------
# Contract constants
# ---------------------------------------------------------------------------

REQUIRED_ASSERTIONS: tuple[str, ...] = (
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

RESULT_SCHEMA: str = "kinglet.host-probe.result/v1"

# Fixed timings (milliseconds) — must match host-probe-v1.json
LEASE_TTL_MS: int = 1200
LEASE_RENEWAL_MS: int = 400
LEASE_COMPETITOR_ATTEMPT_MS: int = 600
CHILD_LIFETIME_MS: int = 30000
CANCEL_DEADLINE_MS: int = 5000

# Subprocess timeout for candidate run (seconds)
_CANDIDATE_TIMEOUT_S: float = 60.0
_KILL_WAIT_S: float = 5.0

# ---------------------------------------------------------------------------
# Result dataclass
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class AssertionEntry:
    id: str
    status: str


@dataclass(frozen=True)
class HostProbeResult:
    schema: str
    candidate_id: str
    candidate_version: str
    status: str
    errors: tuple[str, ...]
    assertions: tuple[AssertionEntry, ...]
    descendant_pids: tuple[int, ...]
    active_lease: bool


# ---------------------------------------------------------------------------
# validate_host_result
# ---------------------------------------------------------------------------

_REQUIRED_ASSERTION_SET: frozenset[str] = frozenset(REQUIRED_ASSERTIONS)


def validate_host_result(value: Any) -> HostProbeResult:
    """Parse and strictly validate a raw host-probe result dict.

    Raises EvidenceError (code E_SCHEMA or E_ASSERTION) on any violation.
    """
    if not isinstance(value, dict):
        raise EvidenceError("E_SCHEMA", "result must be a JSON object")

    # Schema id
    schema = value.get("schema")
    if schema != RESULT_SCHEMA:
        raise EvidenceError(
            "E_SCHEMA",
            f"expected schema '{RESULT_SCHEMA}', got {schema!r}",
        )

    # Candidate block
    candidate = value.get("candidate")
    if not isinstance(candidate, dict):
        raise EvidenceError("E_SCHEMA", "missing 'candidate' object")
    candidate_id = candidate.get("id", "")
    candidate_version = candidate.get("version", "")

    # Top-level fields
    status = value.get("status")
    if status not in ("pass", "fail"):
        raise EvidenceError("E_SCHEMA", f"status must be 'pass' or 'fail', got {status!r}")

    errors_raw = value.get("errors", [])
    if not isinstance(errors_raw, list):
        raise EvidenceError("E_SCHEMA", "'errors' must be a list")

    # Assertions — must contain exactly one entry per required id, no extras
    assertions_raw = value.get("assertions")
    if not isinstance(assertions_raw, list):
        raise EvidenceError("E_ASSERTION", "'assertions' must be a list")

    seen_ids: set[str] = set()
    parsed_assertions: list[AssertionEntry] = []
    for entry in assertions_raw:
        if not isinstance(entry, dict):
            raise EvidenceError("E_ASSERTION", "each assertion entry must be an object")
        a_id = entry.get("id")
        a_status = entry.get("status")
        if not isinstance(a_id, str) or not a_id:
            raise EvidenceError("E_ASSERTION", "assertion entry missing 'id'")
        if a_id in seen_ids:
            raise EvidenceError("E_ASSERTION", f"duplicate assertion id: {a_id!r}")
        seen_ids.add(a_id)
        parsed_assertions.append(AssertionEntry(id=a_id, status=str(a_status)))

    # Every required assertion must be present
    missing = _REQUIRED_ASSERTION_SET - seen_ids
    if missing:
        missing_sorted = sorted(missing)
        raise EvidenceError(
            "E_ASSERTION",
            f"missing required assertions: {missing_sorted}",
        )

    # No extra assertion ids beyond the required set
    extra = seen_ids - _REQUIRED_ASSERTION_SET
    if extra:
        raise EvidenceError(
            "E_ASSERTION",
            f"unexpected assertion ids: {sorted(extra)}",
        )

    # descendant_pids and active_lease — must be clean on pass
    descendant_pids_raw = value.get("descendant_pids", [])
    if not isinstance(descendant_pids_raw, list):
        raise EvidenceError("E_SCHEMA", "'descendant_pids' must be a list")

    active_lease = value.get("active_lease", False)

    if status == "pass":
        if descendant_pids_raw:
            raise EvidenceError(
                "E_ASSERTION",
                "a passing result must have no descendant_pids",
            )
        if active_lease:
            raise EvidenceError(
                "E_ASSERTION",
                "a passing result must have active_lease=false",
            )

    return HostProbeResult(
        schema=schema,
        candidate_id=candidate_id,
        candidate_version=candidate_version,
        status=status,
        errors=tuple(str(e) for e in errors_raw),
        assertions=tuple(parsed_assertions),
        descendant_pids=tuple(int(p) for p in descendant_pids_raw),
        active_lease=bool(active_lease),
    )


# ---------------------------------------------------------------------------
# run_candidate — subprocess launcher
# ---------------------------------------------------------------------------


def _terminate_process_group(pgid: int) -> None:
    """Send SIGTERM to the entire process group."""
    try:
        os.killpg(pgid, signal.SIGTERM)
    except ProcessLookupError:
        pass


def _kill_process_group(pgid: int) -> None:
    """Send SIGKILL to the entire process group."""
    try:
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def run_candidate(
    executable: Path,
    contract_dir: Path,
    workspace: Path,
) -> HostProbeResult:
    """Launch a packaged candidate and return its validated HostProbeResult.

    The candidate is started in a new process group (POSIX: start_new_session=True;
    Windows: CREATE_NEW_PROCESS_GROUP). If it does not complete within
    _CANDIDATE_TIMEOUT_S seconds the whole process group is terminated, then
    after _KILL_WAIT_S seconds it is killed.

    Args:
        executable:   Path to the candidate binary / script.
        contract_dir: Directory containing host-probe-v1.json and the fixtures.
        workspace:    Scratch directory the candidate may read/write.

    Returns:
        Validated HostProbeResult.

    Raises:
        EvidenceError: if the candidate times out, returns non-zero, or produces
            an invalid result document.
    """
    import json

    cmd = [str(executable), str(contract_dir), str(workspace)]

    if sys.platform == "win32" or os.name == "nt":
        # Windows: use CREATE_NEW_PROCESS_GROUP flag (0x00000200)
        CREATE_NEW_PROCESS_GROUP = 0x00000200
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            creationflags=CREATE_NEW_PROCESS_GROUP,
        )
    else:
        # POSIX: start in a new session so pgid == proc.pid
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )

    try:
        stdout, _stderr = proc.communicate(timeout=_CANDIDATE_TIMEOUT_S)
    except subprocess.TimeoutExpired:
        # Terminate process group, wait, then kill
        if sys.platform != "win32" and os.name != "nt":
            pgid = os.getpgid(proc.pid)
            _terminate_process_group(pgid)
        else:
            proc.terminate()

        try:
            proc.wait(timeout=_KILL_WAIT_S)
        except subprocess.TimeoutExpired:
            if sys.platform != "win32" and os.name != "nt":
                _kill_process_group(pgid)
            else:
                proc.kill()
            proc.wait()

        raise EvidenceError(
            "E_TIMEOUT",
            f"candidate did not complete within {_CANDIDATE_TIMEOUT_S}s",
        )

    if proc.returncode != 0:
        raise EvidenceError(
            "E_NONZERO",
            f"candidate exited with code {proc.returncode}",
        )

    try:
        raw = json.loads(stdout.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise EvidenceError("E_SCHEMA", f"candidate stdout is not valid JSON: {exc}") from exc

    return validate_host_result(raw)
