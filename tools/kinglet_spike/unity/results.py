"""results.py -- Load, validate, and convert Unity execution-probe observations.

Public API
----------
UnityObservationSet                          Parsed observation document.
load_unity_observations(path)                Path -> UnityObservationSet
validate_unity_observations(value)           dict -> UnityObservationSet
to_evidence_records(observations)            -> tuple[EvidenceRecord, ...]

Why this module exists at all
-----------------------------
`receipt.receipt_to_evidence` already turns a `UnityReceipt` into an
`EvidenceRecord`, and it CANNOT close a coverage cell. Two reasons, both
structural rather than cosmetic:

* it sets `subject.id = receipt.project_id` (`kinglet-unity-probe`), while
  every unity cell in `matrix-v1.json` carries `subject.id = "execution"`;
* it sets `probe.id = receipt.route`, and only two of the nine unity probe
  values are route names. The matrix names `filesystem-only` where the route
  is `filesystem`, and it defines five probes -- `collision-refusal`,
  `bridge-not-ready`, `mismatched-editor`, `cancellation`, `orphan-cleanup` --
  that no receipt has a route for, because they are refusal and teardown
  observations rather than runs.

`coverage._matches` keys on `subject.kind`, `subject.id`, `probe.id` and the
three environment fields, so a record built by `receipt_to_evidence` matches
nothing anywhere. That function stays untouched (Task 1 froze it and its tests
pin its shape); this module is the layer between an executed probe and the
00A evidence harness.

Honesty rules enforced here
---------------------------
* `probe.id` must be one of the nine frozen matrix probes -- E_COVERAGE
  otherwise, so a typo publishes nothing rather than publishing an orphan
  record that silently closes no cell.
* A probe entry carries NO status field. The record's status is DERIVED from
  its assertions: all pass -> "pass", otherwise "fail". A document therefore
  cannot claim a pass over a failing assertion; the claim and the evidence for
  it are the same object.
* An `unobserved` probe entry is how a cell is left open ON PURPOSE. It has a
  mandatory `reason` and produces an "inconclusive" record with a single
  failing assertion carrying that reason, mirroring how the client subject
  publishes a cell it could not close. It may carry no assertions -- an
  unobserved probe that also asserted things would be claiming to have looked.
* `environment.release` is the matrix release string, and `toolchain` must
  carry the real host identification. A deviation between the two is legitimate
  only because it is visible; `toolchain` is where it is made visible, so it is
  required to be non-empty on every record, not only on a pass.
"""
from __future__ import annotations

import datetime
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from ..model import (
    Artifact,
    AssertionResult,
    Environment,
    EvidenceError,
    EvidenceRecord,
    Probe,
    SourceReference,
    Subject,
)
from .model import RECEIPT_SCHEMA

OBSERVATIONS_SCHEMA = "kinglet.unity-probe.observations/v1"
EVIDENCE_SCHEMA = "kinglet.spike.evidence/v1"

# The subject id every unity cell in matrix-v1.json carries. Not the project id.
SUBJECT_ID = "execution"

# BOUND, not spelled again. This value is written into `probe.contract` on
# every published record, so a third unbound copy of the receipt schema string
# (model.RECEIPT_SCHEMA and routes-v1.json's receipt_schema being the other
# two) means an edit to the contract silently corrupts published provenance --
# the records would name a contract nothing else in the tree answers to.
PROBE_CONTRACT = RECEIPT_SCHEMA

# The nine frozen unity probe values, exactly as spelled in matrix-v1.json.
PROBES: tuple[str, ...] = (
    "bridge-not-ready",
    "cancellation",
    "collision-refusal",
    "filesystem-only",
    "isolated-headless",
    "live-editor-mcp",
    "mismatched-editor",
    "orphan-cleanup",
    "same-project-headless",
)

# Provenance of the subject under test, declared once. `validate_record`
# requires a pass record to carry at least one source, and a probe's own
# observations are not the provenance of the thing observed.
UNITY_SOURCES: tuple[SourceReference, ...] = (
    SourceReference(
        title="Unity 6.3 (6000.3) release notes",
        url="https://unity.com/releases/editor/whats-new/6000.3.18",
    ),
    SourceReference(
        title="MCP for Unity (CoplayDev), pinned v9.7.1",
        url="https://github.com/CoplayDev/unity-mcp/tree/v9.7.1",
    ),
    SourceReference(
        title="Unity Editor command line arguments",
        url="https://docs.unity3d.com/6000.3/Documentation/Manual/EditorCommandLineArguments.html",
    ),
)

_ROOT_FIELDS = frozenset(("schema", "unity_version", "unity_revision", "environment", "probes"))
_ENV_FIELDS = frozenset(("os", "release", "arch", "native", "toolchain"))
_PROBE_FIELDS = frozenset((
    "id", "command", "assertions", "artifact_paths", "unobserved", "reason",
    "started_at", "ended_at",
))
_ASSERTION_FIELDS = frozenset(("id", "status", "detail"))
_ARTIFACT_FIELDS = frozenset(("path", "sha256", "media_type"))


# ---------------------------------------------------------------------------
# Strict structural parsing
# ---------------------------------------------------------------------------

def _object(value: Any, path: str) -> dict:
    if not isinstance(value, dict):
        raise EvidenceError("E_FIELD", f"{path} must be an object")
    return value


def _keys(value: Any, path: str, allowed: frozenset[str], required: frozenset[str]) -> dict:
    item = _object(value, path)
    missing = sorted(required - item.keys())
    unknown = sorted(item.keys() - allowed)
    if missing:
        raise EvidenceError("E_FIELD", f"{path}.{missing[0]} is required")
    if unknown:
        raise EvidenceError("E_FIELD", f"{path}.{unknown[0]} is unknown")
    return item


def _string(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise EvidenceError("E_FIELD", f"{path} must be a non-empty string")
    return value


def _bool(value: Any, path: str) -> bool:
    if type(value) is not bool:
        raise EvidenceError("E_FIELD", f"{path} must be a boolean")
    return value


def _list(value: Any, path: str) -> list:
    if not isinstance(value, list):
        raise EvidenceError("E_FIELD", f"{path} must be an array")
    return value


def _strings(value: Any, path: str) -> tuple[str, ...]:
    return tuple(
        _string(item, f"{path}[{index}]") for index, item in enumerate(_list(value, path))
    )


@dataclass(frozen=True)
class ProbeArtifact:
    path: str
    sha256: str
    media_type: str


@dataclass(frozen=True)
class ProbeObservation:
    id: str
    command: tuple[str, ...]
    assertions: tuple[AssertionResult, ...]
    artifacts: tuple[ProbeArtifact, ...]
    unobserved: bool
    reason: str
    # The probe's real span, or ("", "") when it has none. Both or neither:
    # a half-recorded span is a duration nobody can check.
    started_at: str = ""
    ended_at: str = ""


@dataclass(frozen=True)
class UnityObservationSet:
    schema: str
    unity_version: str
    unity_revision: str
    environment: Environment
    probes: tuple[ProbeObservation, ...]


def _environment(value: Any) -> Environment:
    item = _keys(value, "environment", _ENV_FIELDS, _ENV_FIELDS)
    toolchain = _strings(item["toolchain"], "environment.toolchain")
    if not toolchain:
        # The cell key is the matrix release string; the toolchain is where the
        # REAL host identification lives. An empty toolchain turns a legitimate
        # recorded deviation into an undocumented one.
        raise EvidenceError(
            "E_FIELD",
            "environment.toolchain must identify the real host, not only the "
            "matrix release key",
        )
    return Environment(
        os=_string(item["os"], "environment.os"),
        release=_string(item["release"], "environment.release"),
        arch=_string(item["arch"], "environment.arch"),
        native=_bool(item["native"], "environment.native"),
        toolchain=toolchain,
    )


def _assertion(value: Any, path: str) -> AssertionResult:
    item = _keys(value, path, _ASSERTION_FIELDS, _ASSERTION_FIELDS)
    status = _string(item["status"], f"{path}.status")
    if status not in ("pass", "fail"):
        raise EvidenceError("E_ENUM", f"{path}.status has unsupported value: {status}")
    return AssertionResult(
        id=_string(item["id"], f"{path}.id"),
        status=status,
        detail=_string(item["detail"], f"{path}.detail"),
    )


def _artifact(value: Any, path: str) -> ProbeArtifact:
    item = _keys(value, path, _ARTIFACT_FIELDS, _ARTIFACT_FIELDS)
    return ProbeArtifact(
        path=_string(item["path"], f"{path}.path"),
        sha256=_string(item["sha256"], f"{path}.sha256"),
        media_type=_string(item["media_type"], f"{path}.media_type"),
    )


def _probe(value: Any, index: int) -> ProbeObservation:
    path = f"probes[{index}]"
    item = _keys(value, path, _PROBE_FIELDS, frozenset(("id", "unobserved")))
    identifier = _string(item["id"], f"{path}.id")
    if identifier not in PROBES:
        raise EvidenceError(
            "E_COVERAGE",
            f"{path}.id is not a frozen unity matrix probe: {identifier}",
        )
    unobserved = _bool(item["unobserved"], f"{path}.unobserved")
    reason = item.get("reason")
    assertions = tuple(
        _assertion(entry, f"{path}.assertions[{sub}]")
        for sub, entry in enumerate(_list(item.get("assertions", []), f"{path}.assertions"))
    )
    artifacts = tuple(
        _artifact(entry, f"{path}.artifact_paths[{sub}]")
        for sub, entry in enumerate(
            _list(item.get("artifact_paths", []), f"{path}.artifact_paths")
        )
    )
    command = _strings(item.get("command", []), f"{path}.command")
    started_at = item.get("started_at")
    ended_at = item.get("ended_at")
    if (started_at is None) != (ended_at is None):
        raise EvidenceError(
            "E_TIME",
            f"{path} must carry both started_at and ended_at or neither; a "
            "half-recorded span is a duration no reader can check",
        )
    if started_at is not None:
        started_at = _string(started_at, f"{path}.started_at")
        ended_at = _string(ended_at, f"{path}.ended_at")
        if ended_at < started_at:
            raise EvidenceError("E_TIME", f"{path}.ended_at precedes started_at")
    else:
        started_at = ended_at = ""

    if unobserved:
        if not isinstance(reason, str) or not reason.strip():
            raise EvidenceError(
                "E_FIELD",
                f"{path}.reason is required when unobserved is true; an open "
                "cell must say why it is open",
            )
        if assertions:
            # An unobserved probe that also asserts things is claiming to have
            # looked. The two states are mutually exclusive by construction.
            raise EvidenceError(
                "E_ASSERTION",
                f"{path} is unobserved and therefore cannot carry assertions",
            )
        return ProbeObservation(identifier, command, (), artifacts, True, reason.strip(),
                                started_at, ended_at)

    if reason is not None:
        raise EvidenceError(
            "E_FIELD",
            f"{path}.reason belongs to an unobserved probe only",
        )
    if not assertions:
        raise EvidenceError(
            "E_ASSERTION",
            f"{path} was observed but asserts nothing; there is no claim to publish",
        )
    return ProbeObservation(identifier, command, assertions, artifacts, False, "",
                            started_at, ended_at)


def validate_unity_observations(value: Any) -> UnityObservationSet:
    root = _keys(value, "observations", _ROOT_FIELDS, _ROOT_FIELDS)
    schema = _string(root["schema"], "schema")
    if schema != OBSERVATIONS_SCHEMA:
        raise EvidenceError("E_SCHEMA", f"unsupported observations schema: {schema}")

    raw_probes = _list(root["probes"], "probes")
    probes = tuple(_probe(entry, index) for index, entry in enumerate(raw_probes))
    identifiers = [probe.id for probe in probes]
    duplicates = sorted({p for p in identifiers if identifiers.count(p) > 1})
    if duplicates:
        raise EvidenceError("E_COVERAGE", f"duplicate probe observation: {duplicates[0]}")

    return UnityObservationSet(
        schema=schema,
        unity_version=_string(root["unity_version"], "unity_version"),
        unity_revision=_string(root["unity_revision"], "unity_revision"),
        environment=_environment(root["environment"]),
        probes=tuple(sorted(probes, key=lambda probe: probe.id)),
    )


def load_unity_observations(path: Path) -> UnityObservationSet:
    import json

    try:
        value = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        raise EvidenceError("E_JSON", f"cannot decode {path}: {error}") from error
    return validate_unity_observations(value)


# ---------------------------------------------------------------------------
# Conversion
# ---------------------------------------------------------------------------

def _release_key(release: str) -> str:
    """A run_id-safe spelling of a release string: dots collapse to dashes.

    `ubuntu-24.04.4-lts` becomes `ubuntu-24-04-4-lts`. This is NOT the matrix
    cell id's release segment, which is the shorter `ubuntu-24-04` -- the two
    are independent and only the run_id uses this function. Coverage matches on
    `environment.release` verbatim, never on either spelling, so the run_id is
    free to keep the full release string and stay unique per host.
    """
    return release.replace(".", "-")


def build_run_id(observations: UnityObservationSet, probe_id: str, stamp: str) -> str:
    environment = observations.environment
    return (
        f"{stamp}-unity-probe-{probe_id}-{environment.os}-"
        f"{_release_key(environment.release)}-{environment.arch}-01"
    )


def _record(
    observations: UnityObservationSet,
    probe: ProbeObservation,
    now: str,
    stamp: str,
) -> EvidenceRecord:
    if probe.unobserved:
        status = "inconclusive"
        assertions = (
            AssertionResult(
                id="observed",
                status="fail",
                detail=probe.reason,
            ),
        )
    else:
        assertions = probe.assertions
        status = "pass" if all(a.status == "pass" for a in assertions) else "fail"

    return EvidenceRecord(
        schema=EVIDENCE_SCHEMA,
        run_id=build_run_id(observations, probe.id, stamp),
        subject=Subject(
            kind="unity",
            id=SUBJECT_ID,
            version=f"{observations.unity_version} ({observations.unity_revision})",
        ),
        probe=Probe(id=probe.id, contract=PROBE_CONTRACT),
        environment=observations.environment,
        # The probe's own span when it recorded one. Falling back to `now` for
        # both is honest only for a probe that never ran (an unobserved cell);
        # for an observed one it discards a duration the artifacts measured.
        started_at=probe.started_at or now,
        ended_at=probe.ended_at or now,
        status=status,
        command=probe.command,
        artifacts=tuple(
            Artifact(
                path=artifact.path,
                sha256=artifact.sha256,
                media_type=artifact.media_type,
                required=True,
            )
            for artifact in probe.artifacts
        ),
        assertions=assertions,
        measurements=(),
        sources=UNITY_SOURCES,
        prompt=None,
    )


def to_evidence_records(
    observations: UnityObservationSet,
    *,
    now: str | None = None,
) -> tuple[EvidenceRecord, ...]:
    """One EvidenceRecord per observed or deliberately-unobserved probe."""
    if now is None:
        now = datetime.datetime.now(tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    stamp = now.replace("-", "").replace(":", "")
    return tuple(_record(observations, probe, now, stamp) for probe in observations.probes)
