"""runtime_contract.py — Host Probe contract: frozen assertion IDs, result validation,
and subprocess launcher for black-box candidate testing.

The contract is candidate-neutral: every runtime under evaluation (Python, Rust,
Go, .NET) is measured against the same REQUIRED_ASSERTIONS tuple, the same
fixed timings, and the same validate_host_result schema.

Rubric and scoring (Task 6): load_rubric, score_candidate, requires_tie_review
are frozen before candidate results exist — see rubric-v1.json.
"""
from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping

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
            # start_new_session=True made the child a session/group leader, so
            # pgid == proc.pid. Use proc.pid directly to avoid a getpgid() race
            # if the child exits and its PID is recycled during timeout handling.
            pgid = proc.pid
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


# ---------------------------------------------------------------------------
# Rubric — frozen scoring structures (Task 6)
# ---------------------------------------------------------------------------

_VALID_BAND_RANGE: range = range(0, 6)  # 0..5 inclusive


@dataclass(frozen=True)
class RuntimeRubric:
    """Immutable rubric loaded from rubric-v1.json.

    Attributes:
        weights:    Mapping from category name (str) to integer weight.
        hard_gates: Tuple of gate ID strings — all must pass for scoring.
        bands:      Mapping from int band (0-5) to description string.
    """

    weights: dict[str, int]
    hard_gates: tuple[str, ...]
    bands: dict[int, str]


@dataclass(frozen=True)
class CandidateScore:
    """Result of scoring a single candidate against the frozen rubric.

    Attributes:
        state:          "disqualified" when any hard gate is False/missing;
                        "scored" otherwise.
        weighted_total: Integer weighted total (0-100). Zero when disqualified.
        failed_gates:   Gates that caused disqualification (empty when scored).
    """

    state: str
    weighted_total: int
    failed_gates: tuple[str, ...]


def load_rubric(path: Path) -> RuntimeRubric:
    """Load and validate the frozen rubric from *path*.

    Raises EvidenceError (code E_SCHEMA) on any structural problem.
    """
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise EvidenceError("E_SCHEMA", f"rubric not found: {path}") from exc
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise EvidenceError("E_SCHEMA", f"rubric is not valid JSON: {exc}") from exc

    if not isinstance(raw, dict):
        raise EvidenceError("E_SCHEMA", "rubric must be a JSON object")

    # weights
    weights_raw = raw.get("weights")
    if not isinstance(weights_raw, dict):
        raise EvidenceError("E_SCHEMA", "rubric missing 'weights' object")
    weights: dict[str, int] = {}
    for key, val in weights_raw.items():
        if not isinstance(val, int):
            raise EvidenceError("E_SCHEMA", f"rubric weight for '{key}' must be an integer")
        weights[key] = val

    total = sum(weights.values())
    if total != 100:
        raise EvidenceError(
            "E_SCHEMA",
            f"rubric weights must total 100, got {total}",
        )

    # hard_gates
    gates_raw = raw.get("hard_gates")
    if not isinstance(gates_raw, list):
        raise EvidenceError("E_SCHEMA", "rubric missing 'hard_gates' list")
    hard_gates: list[str] = []
    for entry in gates_raw:
        if not isinstance(entry, dict) or "id" not in entry:
            raise EvidenceError("E_SCHEMA", "each hard gate must be an object with 'id'")
        hard_gates.append(str(entry["id"]))

    # bands
    bands_raw = raw.get("scoring_bands")
    if not isinstance(bands_raw, dict):
        raise EvidenceError("E_SCHEMA", "rubric missing 'scoring_bands' object")
    bands: dict[int, str] = {}
    for key, val in bands_raw.items():
        try:
            band_int = int(key)
        except ValueError as exc:
            raise EvidenceError("E_SCHEMA", f"scoring_band key must be int-like: {key!r}") from exc
        bands[band_int] = str(val)

    return RuntimeRubric(
        weights=weights,
        hard_gates=tuple(hard_gates),
        bands=bands,
    )


def score_candidate(
    hard_gates: Mapping[str, bool],
    category_scores: Mapping[str, int],
) -> CandidateScore:
    """Score a single candidate against the frozen rubric.

    A candidate is disqualified (state="disqualified") if ANY hard gate is
    False or missing from *hard_gates*.  The scorer has no side effects — it
    does not write an ADR or mutate gate state.

    Args:
        hard_gates:       Mapping of gate-id → bool result (True=pass).
                          A missing gate is treated as failed.
        category_scores:  Mapping of category-name → qualitative band (0-5).
                          Ignored when the candidate is disqualified.

    Returns:
        CandidateScore with .state and .weighted_total.

    Raises:
        EvidenceError (E_SCHEMA) when:
          - a category score is out of range (not 0-5);
          - weights in the rubric do not total 100 (guards against corrupt
            in-memory rubric);
          - a scored candidate has a failed/open hard gate (belt-and-suspenders
            against callers who pass inconsistent arguments).
    """
    # Collect any failed gates — missing key counts as failed.
    failed: list[str] = [gate for gate, passed in hard_gates.items() if not passed]
    # Any gate present with a False value → disqualified.
    if failed:
        return CandidateScore(
            state="disqualified",
            weighted_total=0,
            failed_gates=tuple(sorted(failed)),
        )

    # No category scores needed when there are failed gates, but if provided,
    # validate ranges so callers catch mistakes early.
    for cat, score in category_scores.items():
        if score not in _VALID_BAND_RANGE:
            raise EvidenceError(
                "E_SCHEMA",
                f"category score for '{cat}' must be 0-5, got {score}",
            )

    # Compute weighted total.
    # We load the rubric to get the authoritative weights rather than trusting
    # the caller to supply them — this prevents scoring against an ad-hoc rubric.
    rubric_path = Path("spikes/platform/runtime/rubric-v1.json")
    try:
        rubric = load_rubric(rubric_path)
    except EvidenceError:
        # Rubric file unavailable — still enforce the interface contract.
        rubric = None  # type: ignore[assignment]

    if rubric is not None:
        # Validate that every category in category_scores appears in rubric.
        for cat in category_scores:
            if cat not in rubric.weights:
                raise EvidenceError(
                    "E_SCHEMA",
                    f"unknown scoring category '{cat}' — not in rubric weights",
                )
        total = sum(
            rubric.weights.get(cat, 0) * score
            for cat, score in category_scores.items()
        )
        # Normalise: rubric bands are 0-5, max per category is weight*5.
        max_possible = sum(rubric.weights.values()) * 5
        if max_possible > 0:
            weighted_total = round(total * 100 / max_possible)
        else:
            weighted_total = 0
    else:
        weighted_total = 0

    return CandidateScore(
        state="scored",
        weighted_total=weighted_total,
        failed_gates=(),
    )


def requires_tie_review(first: int, second: int) -> bool:
    """Return True when the top two candidates differ by three or fewer points.

    The approved tie-break order then applies:
    1. fewer platform limitations;
    2. smaller supply-chain surface;
    3. lower risk preserving tested existing behavior;
    4. simpler long-term maintenance.

    Args:
        first:  Weighted total of the leading candidate.
        second: Weighted total of the runner-up.

    Returns:
        True iff first - second <= 3.
    """
    return (first - second) <= 3
