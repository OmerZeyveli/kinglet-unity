from __future__ import annotations

import json
from pathlib import Path

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

EVIDENCE_SCHEMA = "kinglet.spike.evidence/v1"
RECORD_STATUSES = frozenset(("pass", "fail", "unavailable", "inconclusive"))
SUBJECT_KINDS = frozenset(("runtime", "client", "unity"))
ASSERTION_STATUSES = frozenset(("pass", "fail"))


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


def _string(value: object, path: str) -> str:
    if not isinstance(value, str):
        raise EvidenceError("E_FIELD", f"{path} must be a string")
    return value


def _boolean(value: object, path: str) -> bool:
    if type(value) is not bool:
        raise EvidenceError("E_FIELD", f"{path} must be a boolean")
    return value


def _array(value: object, path: str) -> list:
    if not isinstance(value, list):
        raise EvidenceError("E_FIELD", f"{path} must be an array")
    return value


def _strings(value: object, path: str) -> tuple[str, ...]:
    items = _array(value, path)
    return tuple(_string(item, f"{path}[{index}]") for index, item in enumerate(items))


def _enum(value: object, path: str, accepted: frozenset[str]) -> str:
    item = _string(value, path)
    if item not in accepted:
        raise EvidenceError("E_ENUM", f"{path} has unsupported value: {item}")
    return item


def _subject(value: object) -> Subject:
    item = _keys(value, "subject", {"kind", "id", "version"})
    return Subject(
        kind=_enum(item["kind"], "subject.kind", SUBJECT_KINDS),
        id=_string(item["id"], "subject.id"),
        version=_string(item["version"], "subject.version"),
    )


def _probe(value: object) -> Probe:
    item = _keys(value, "probe", {"id", "contract"})
    return Probe(
        id=_string(item["id"], "probe.id"),
        contract=_string(item["contract"], "probe.contract"),
    )


def _environment(value: object) -> Environment:
    item = _keys(
        value,
        "environment",
        {"os", "release", "arch", "native", "toolchain"},
    )
    return Environment(
        os=_string(item["os"], "environment.os"),
        release=_string(item["release"], "environment.release"),
        arch=_string(item["arch"], "environment.arch"),
        native=_boolean(item["native"], "environment.native"),
        toolchain=_strings(item["toolchain"], "environment.toolchain"),
    )


def _artifact(value: object, index: int) -> Artifact:
    path = f"artifacts[{index}]"
    item = _keys(value, path, {"path", "sha256", "media_type", "required"})
    return Artifact(
        path=_string(item["path"], f"{path}.path"),
        sha256=_string(item["sha256"], f"{path}.sha256"),
        media_type=_string(item["media_type"], f"{path}.media_type"),
        required=_boolean(item["required"], f"{path}.required"),
    )


def _assertion(value: object, index: int) -> AssertionResult:
    path = f"assertions[{index}]"
    item = _keys(value, path, {"id", "status", "detail"})
    return AssertionResult(
        id=_string(item["id"], f"{path}.id"),
        status=_enum(item["status"], f"{path}.status", ASSERTION_STATUSES),
        detail=_string(item["detail"], f"{path}.detail"),
    )


def _measurement(value: object, index: int) -> Measurement:
    path = f"measurements[{index}]"
    item = _keys(value, path, {"id", "unit", "samples"})
    raw_samples = _array(item["samples"], f"{path}.samples")
    samples: list[int] = []
    for sample_index, sample in enumerate(raw_samples):
        if type(sample) is not int:
            raise EvidenceError(
                "E_FIELD",
                f"{path}.samples[{sample_index}] must be an integer",
            )
        samples.append(sample)
    return Measurement(
        id=_string(item["id"], f"{path}.id"),
        unit=_string(item["unit"], f"{path}.unit"),
        samples=tuple(samples),
    )


def _source(value: object, index: int) -> SourceReference:
    path = f"sources[{index}]"
    item = _keys(value, path, {"title", "url"})
    return SourceReference(
        title=_string(item["title"], f"{path}.title"),
        url=_string(item["url"], f"{path}.url"),
    )


def _prompt(value: object) -> PromptReference | None:
    if value is None:
        return None
    item = _keys(value, "prompt", {"id", "sha256"})
    return PromptReference(
        id=_string(item["id"], "prompt.id"),
        sha256=_string(item["sha256"], "prompt.sha256"),
    )


def load_record(path: Path) -> EvidenceRecord:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError("E_JSON", f"cannot decode {path}: {error}") from error

    item = _keys(
        value,
        "record",
        {
            "schema",
            "run_id",
            "subject",
            "probe",
            "environment",
            "started_at",
            "ended_at",
            "status",
            "command",
            "artifacts",
            "assertions",
            "measurements",
            "sources",
            "prompt",
        },
    )
    schema = _string(item["schema"], "schema")
    if schema != EVIDENCE_SCHEMA:
        raise EvidenceError("E_SCHEMA", f"unsupported evidence schema: {schema}")

    artifacts = _array(item["artifacts"], "artifacts")
    assertions = _array(item["assertions"], "assertions")
    measurements = _array(item["measurements"], "measurements")
    sources = _array(item["sources"], "sources")
    return EvidenceRecord(
        schema=schema,
        run_id=_string(item["run_id"], "run_id"),
        subject=_subject(item["subject"]),
        probe=_probe(item["probe"]),
        environment=_environment(item["environment"]),
        started_at=_string(item["started_at"], "started_at"),
        ended_at=_string(item["ended_at"], "ended_at"),
        status=_enum(item["status"], "status", RECORD_STATUSES),
        command=_strings(item["command"], "command"),
        artifacts=tuple(_artifact(value, index) for index, value in enumerate(artifacts)),
        assertions=tuple(
            _assertion(value, index) for index, value in enumerate(assertions)
        ),
        measurements=tuple(
            _measurement(value, index) for index, value in enumerate(measurements)
        ),
        sources=tuple(_source(value, index) for index, value in enumerate(sources)),
        prompt=_prompt(item["prompt"]),
    )
