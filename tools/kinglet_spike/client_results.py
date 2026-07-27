"""client_results.py — Load, validate, and convert client probe observations.

Public API
----------
ClientObservationSet    Parsed observation document (dataclass).
load_client_observations(path)      Path → ClientObservationSet
validate_client_observations(value, cases)  dict → ClientObservationSet
to_evidence(observations, environment)      → EvidenceRecord

Validation rules (kinglet.client-probe.observations/v1)
-------------------------------------------------------
* Unknown fields in a case entry → E_FIELD.
* Missing or duplicate case IDs vs. the frozen case catalog → E_COVERAGE.
* Native/pass  requires ≥1 artifact_path (E_ASSERTION).
* Emulated/pass additionally requires emulation_mechanism (E_ASSERTION).
* Unavailable   requires status=unavailable and ≥1 source_url (E_FIELD).
* inconclusive must have no grade field (grade absent/None); if a grade is
  present, raise E_ENUM.
* A fail may carry a grade but never closes the cell.
* Cases sorted by ID in the resulting ClientObservationSet.

to_evidence probe.id choice
---------------------------
All 12 rich cases are grouped under a single probe.id of "capability-suite"
(the same coarse probe id used for the capability-suite matrix cell on all
platforms). The per-client probe tasks (4–5) will refine the cell grouping
once the matrix mapping is finalised.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

from .model import (
    Artifact,
    AssertionResult,
    Environment,
    EvidenceError,
    EvidenceRecord,
    Measurement,
    Probe,
    PromptReference,
    SourceReference,
    Subject,
)

# ---------------------------------------------------------------------------
# Schema constants
# ---------------------------------------------------------------------------

OBSERVATIONS_SCHEMA = "kinglet.client-probe.observations/v1"
EVIDENCE_SCHEMA = "kinglet.spike.evidence/v1"

VALID_GRADES = frozenset(("Native", "Emulated", "Unavailable"))
VALID_STATUSES = frozenset(("pass", "fail", "unavailable", "inconclusive"))

# Exact set of allowed fields in a case observation entry.
_CASE_FIELDS = frozenset((
    "id",
    "advertised",
    "observed",
    "grade",
    "status",
    "source_urls",
    "artifact_paths",
    "notes",
    "emulation_mechanism",
))

# Probe id used when converting to EvidenceRecord.
# Rationale: the coverage matrix groups all client capabilities under the
# coarse "capability-suite" cell; refined per-case mapping is deferred to
# Tasks 4–5. See module docstring for the probe.id choice note.
_PROBE_ID = "capability-suite"
_PROBE_CONTRACT = "kinglet.client-probe.observations/v1"


# ---------------------------------------------------------------------------
# Dataclasses
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class CaseObservation:
    id: str
    advertised: bool
    observed: str
    grade: str | None          # None for inconclusive
    status: str
    source_urls: tuple[str, ...]
    artifact_paths: tuple[str, ...]
    notes: str
    emulation_mechanism: str | None


@dataclass(frozen=True)
class ClientObservationSet:
    schema: str
    subject: str
    client_version: str
    cases: tuple[CaseObservation, ...]   # sorted by id


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _string(value: Any, path: str) -> str:
    if not isinstance(value, str):
        raise EvidenceError("E_FIELD", f"{path} must be a string")
    return value


def _boolean(value: Any, path: str) -> bool:
    if type(value) is not bool:
        raise EvidenceError("E_FIELD", f"{path} must be a boolean")
    return value


def _strings(value: Any, path: str) -> tuple[str, ...]:
    if not isinstance(value, list):
        raise EvidenceError("E_FIELD", f"{path} must be an array")
    return tuple(_string(item, f"{path}[{i}]") for i, item in enumerate(value))


def _opt_string(value: Any, path: str) -> str | None:
    if value is None:
        return None
    return _string(value, path)


def _parse_case(raw: Any, index: int) -> CaseObservation:
    path = f"cases[{index}]"
    if not isinstance(raw, dict):
        raise EvidenceError("E_FIELD", f"{path} must be an object")

    unknown = sorted(raw.keys() - _CASE_FIELDS)
    if unknown:
        raise EvidenceError("E_FIELD", f"{path}.{unknown[0]} is an unknown field")

    case_id = _string(raw.get("id", ""), f"{path}.id")
    advertised = _boolean(raw.get("advertised", None), f"{path}.advertised")
    observed = _string(raw.get("observed", ""), f"{path}.observed")
    raw_grade = raw.get("grade", None)
    status_raw = raw.get("status", "")

    status = _string(status_raw, f"{path}.status")
    if status not in VALID_STATUSES:
        raise EvidenceError("E_ENUM", f"{path}.status has unsupported value: {status!r}")

    # inconclusive must have no grade
    if status == "inconclusive":
        if raw_grade is not None:
            raise EvidenceError(
                "E_ENUM",
                f"{path}: inconclusive status must not carry a grade; got {raw_grade!r}",
            )
        grade: str | None = None
    else:
        if raw_grade is not None:
            grade = _string(raw_grade, f"{path}.grade")
            if grade not in VALID_GRADES:
                raise EvidenceError("E_ENUM", f"{path}.grade has unsupported value: {grade!r}")
        else:
            grade = None

    source_urls = _strings(raw.get("source_urls", []), f"{path}.source_urls")
    artifact_paths = _strings(raw.get("artifact_paths", []), f"{path}.artifact_paths")
    notes = _string(raw.get("notes", ""), f"{path}.notes")
    emulation_mechanism = _opt_string(raw.get("emulation_mechanism", None), f"{path}.emulation_mechanism")

    # Grade/status specific validation
    if status == "pass":
        if grade == "Native":
            if not artifact_paths:
                raise EvidenceError(
                    "E_ASSERTION",
                    f"{path}: Native/pass requires at least one artifact_path",
                )
        elif grade == "Emulated":
            if not artifact_paths:
                raise EvidenceError(
                    "E_ASSERTION",
                    f"{path}: Emulated/pass requires at least one artifact_path",
                )
            if not emulation_mechanism:
                raise EvidenceError(
                    "E_ASSERTION",
                    f"{path}: Emulated/pass requires a non-null emulation_mechanism",
                )

    if grade == "Unavailable":
        if status != "unavailable":
            raise EvidenceError(
                "E_FIELD",
                f"{path}: Unavailable grade requires status=unavailable",
            )
        if not source_urls:
            raise EvidenceError(
                "E_FIELD",
                f"{path}: Unavailable grade requires at least one source_url",
            )

    return CaseObservation(
        id=case_id,
        advertised=advertised,
        observed=observed,
        grade=grade,
        status=status,
        source_urls=source_urls,
        artifact_paths=artifact_paths,
        notes=notes,
        emulation_mechanism=emulation_mechanism,
    )


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def validate_client_observations(
    value: Any,
    cases: Sequence[dict],
) -> ClientObservationSet:
    """Parse and strictly validate a raw observations dict against the frozen case catalog.

    Args:
        value:  Raw decoded JSON object (dict).
        cases:  The frozen case catalog — a sequence of dicts each with an "id" key.
                Typically CASES from tests.kinglet_spike.client_support or loaded from
                cases-v1.json.

    Returns:
        ClientObservationSet with cases sorted by id.

    Raises:
        EvidenceError with one of:
          E_SCHEMA   — wrong or missing schema string.
          E_FIELD    — wrong type, unknown field, missing required field.
          E_ENUM     — invalid grade/status value, or inconclusive carrying a grade.
          E_ASSERTION— Native/pass missing artifact; Emulated/pass missing artifact or mechanism.
          E_COVERAGE — missing or duplicate case IDs vs. the frozen catalog.
    """
    if not isinstance(value, dict):
        raise EvidenceError("E_SCHEMA", "observations must be a JSON object")

    schema = value.get("schema")
    if schema != OBSERVATIONS_SCHEMA:
        raise EvidenceError("E_SCHEMA", f"unsupported observations schema: {schema!r}")

    subject = _string(value.get("subject", ""), "subject")
    client_version = _string(value.get("client_version", ""), "client_version")

    raw_cases = value.get("cases")
    if not isinstance(raw_cases, list):
        raise EvidenceError("E_FIELD", "cases must be an array")

    parsed: list[CaseObservation] = []
    for index, raw in enumerate(raw_cases):
        parsed.append(_parse_case(raw, index))

    # Coverage check: all required case IDs must appear exactly once.
    required_ids = tuple(c["id"] for c in cases)
    required_set = frozenset(required_ids)
    seen_ids: dict[str, int] = {}
    for obs in parsed:
        if obs.id in seen_ids:
            raise EvidenceError(
                "E_COVERAGE",
                f"duplicate case id: {obs.id!r}",
            )
        seen_ids[obs.id] = 1

    missing = sorted(required_set - seen_ids.keys())
    if missing:
        raise EvidenceError(
            "E_COVERAGE",
            f"missing case ids: {missing}",
        )

    extra = sorted(seen_ids.keys() - required_set)
    if extra:
        raise EvidenceError(
            "E_COVERAGE",
            f"unexpected case ids: {extra}",
        )

    return ClientObservationSet(
        schema=schema,
        subject=subject,
        client_version=client_version,
        cases=tuple(sorted(parsed, key=lambda c: c.id)),
    )


def load_client_observations(path: Path) -> ClientObservationSet:
    """Load a kinglet.client-probe.observations/v1 JSON file from disk.

    The frozen case catalog is loaded from
    spikes/platform/clients/contracts/cases-v1.json (relative to cwd).

    Args:
        path:  Path to the observations JSON file.

    Returns:
        Validated ClientObservationSet.

    Raises:
        EvidenceError (E_JSON) if the file cannot be read or is not valid JSON.
        EvidenceError (other codes) on schema / validation failure.
    """
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError("E_JSON", f"cannot decode {path}: {error}") from error

    cases_path = Path("spikes/platform/clients/contracts/cases-v1.json")
    try:
        cases_raw = json.loads(cases_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError("E_JSON", f"cannot load case catalog: {error}") from error

    cases = cases_raw.get("cases", [])
    return validate_client_observations(value, cases)


def _prompt_digest(text: str) -> str:
    """Return the SHA-256 digest of the UTF-8 encoded prompt text."""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _load_prompts() -> dict[str, str]:
    """Load prompts-v1.json and return {id: sha256_digest} mapping.

    Digests are recomputed from the UTF-8 text at load time.
    """
    prompts_path = Path("spikes/platform/clients/contracts/prompts-v1.json")
    try:
        raw = json.loads(prompts_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError("E_JSON", f"cannot load prompt catalog: {error}") from error
    return {p["id"]: _prompt_digest(p["text"]) for p in raw.get("prompts", [])}


def to_evidence(
    observations: ClientObservationSet,
    environment: Environment,
) -> EvidenceRecord:
    """Convert a validated ClientObservationSet to an EvidenceRecord.

    The record uses subject.kind="client" and probe.id="capability-suite"
    (see module docstring for the probe.id rationale).

    Passing cases contribute AssertionResult entries (status="pass").
    Failing/inconclusive cases contribute AssertionResult entries (status="fail").

    Artifacts are synthesised from artifact_paths on passing Native/Emulated cases.
    The prompt field is omitted (None) since the probe set covers multiple prompts.

    Args:
        observations:   Validated ClientObservationSet.
        environment:    Environment dataclass (os, release, arch, native, toolchain).

    Returns:
        EvidenceRecord with schema="kinglet.spike.evidence/v1".
    """
    import datetime

    now = datetime.datetime.now(tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # Build assertions from cases.
    assertions: list[AssertionResult] = []
    artifacts: list[Artifact] = []
    sources: list[SourceReference] = []
    seen_paths: set[str] = set()
    seen_urls: set[str] = set()

    overall_status = "pass"

    for case in observations.cases:
        a_status = "pass" if case.status == "pass" else "fail"
        if case.status != "pass":
            overall_status = "fail"
        assertions.append(AssertionResult(
            id=case.id,
            status=a_status,
            detail=case.observed or case.status,
        ))

        # Collect artifacts from passing Native/Emulated cases.
        if case.status == "pass" and case.grade in ("Native", "Emulated"):
            for ap in case.artifact_paths:
                if ap not in seen_paths:
                    seen_paths.add(ap)
                    artifacts.append(Artifact(
                        path=ap,
                        sha256="0" * 64,   # placeholder — harness verifies real checksum on disk
                        media_type="application/json",
                        required=True,
                    ))

        # Collect source URLs.
        for url in case.source_urls:
            if url not in seen_urls:
                seen_urls.add(url)
                sources.append(SourceReference(
                    title=case.id,
                    url=url,
                ))

    # Build a stable run_id from subject + version.
    safe_subject = observations.subject.replace("-", "")[:24]
    run_id = f"client-probe-{safe_subject}"

    return EvidenceRecord(
        schema=EVIDENCE_SCHEMA,
        run_id=run_id,
        subject=Subject(
            kind="client",
            id=observations.subject,
            version=observations.client_version,
        ),
        probe=Probe(
            id=_PROBE_ID,
            contract=_PROBE_CONTRACT,
        ),
        environment=environment,
        started_at=now,
        ended_at=now,
        status=overall_status,
        command=(),
        artifacts=tuple(artifacts),
        assertions=tuple(assertions),
        measurements=(),
        sources=tuple(sources),
        prompt=None,
    )
