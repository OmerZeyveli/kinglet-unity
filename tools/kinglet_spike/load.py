"""Strict JSON loader for the platform-spike evidence v1 record."""

from __future__ import annotations

import json
import re
from pathlib import Path

from tools.kinglet_spike.model import (
    Artifact,
    Assertion,
    Environment,
    EvidenceError,
    EvidenceRecord,
    Measurement,
    Prompt,
    Probe,
    Source,
    Subject,
)


SCHEMA = "kinglet.spike.evidence/v1"
STATUSES = frozenset({"pass", "fail", "unavailable", "inconclusive"})
SUBJECT_KINDS = frozenset({"runtime", "client", "unity"})
PROMPT_ID = re.compile(r"^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$")


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


def _bool(value: object, path: str) -> bool:
    if not isinstance(value, bool):
        raise EvidenceError("E_FIELD", f"{path} must be a boolean")
    return value


def _array(value: object, path: str) -> list:
    if not isinstance(value, list):
        raise EvidenceError("E_FIELD", f"{path} must be an array")
    return value


def _status(value: object, path: str) -> str:
    status = _string(value, path)
    if status not in STATUSES:
        raise EvidenceError("E_ENUM", f"{path} must be a supported status")
    return status


def _subject(value: object) -> Subject:
    item = _keys(value, "subject", {"kind", "id", "version"})
    kind = _string(item["kind"], "subject.kind")
    if kind not in SUBJECT_KINDS:
        raise EvidenceError("E_ENUM", "subject.kind must be a supported subject kind")
    return Subject(kind, _string(item["id"], "subject.id"), _string(item["version"], "subject.version"))


def _probe(value: object) -> Probe:
    item = _keys(value, "probe", {"id", "contract"})
    return Probe(_string(item["id"], "probe.id"), _string(item["contract"], "probe.contract"))


def _environment(value: object) -> Environment:
    item = _keys(value, "environment", {"os", "release", "arch", "native", "toolchain"})
    toolchain = tuple(
        _string(part, f"environment.toolchain[{index}]")
        for index, part in enumerate(_array(item["toolchain"], "environment.toolchain"))
    )
    return Environment(
        _string(item["os"], "environment.os"),
        _string(item["release"], "environment.release"),
        _string(item["arch"], "environment.arch"),
        _bool(item["native"], "environment.native"),
        toolchain,
    )


def _artifact(value: object, index: int) -> Artifact:
    path = f"artifacts[{index}]"
    item = _keys(value, path, {"path", "sha256", "media_type", "required"})
    return Artifact(
        _string(item["path"], f"{path}.path"),
        _string(item["sha256"], f"{path}.sha256"),
        _string(item["media_type"], f"{path}.media_type"),
        _bool(item["required"], f"{path}.required"),
    )


def _assertion(value: object, index: int) -> Assertion:
    path = f"assertions[{index}]"
    item = _keys(value, path, {"id", "status", "detail"})
    return Assertion(
        _string(item["id"], f"{path}.id"),
        _status(item["status"], f"{path}.status"),
        _string(item["detail"], f"{path}.detail"),
    )


def _measurement(value: object, index: int) -> Measurement:
    path = f"measurements[{index}]"
    item = _keys(value, path, {"id", "unit", "samples"})
    samples: list[int] = []
    for sample_index, sample in enumerate(_array(item["samples"], f"{path}.samples")):
        if isinstance(sample, bool) or not isinstance(sample, int):
            raise EvidenceError("E_FIELD", f"{path}.samples[{sample_index}] must be an integer")
        samples.append(sample)
    return Measurement(
        _string(item["id"], f"{path}.id"),
        _string(item["unit"], f"{path}.unit"),
        tuple(samples),
    )


def _source(value: object, index: int) -> Source:
    path = f"sources[{index}]"
    item = _keys(value, path, {"title", "url"})
    return Source(_string(item["title"], f"{path}.title"), _string(item["url"], f"{path}.url"))


def _prompt(value: object) -> Prompt | None:
    if value is None:
        return None
    item = _keys(value, "prompt", {"id", "sha256"})
    prompt_id = _string(item["id"], "prompt.id")
    if len(prompt_id) > 64 or not PROMPT_ID.fullmatch(prompt_id):
        raise EvidenceError("E_FIELD", "prompt.id must be a lowercase opaque identifier")
    return Prompt(prompt_id, _string(item["sha256"], "prompt.sha256"))


def load_record(path: Path) -> EvidenceRecord:
    """Load one UTF-8 evidence record, rejecting unknown or ill-typed fields."""
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceError("E_JSON", f"{path} is not valid UTF-8 JSON") from error

    item = _keys(
        raw,
        "record",
        {
            "schema", "run_id", "subject", "probe", "environment", "started_at", "ended_at",
            "status", "command", "artifacts", "assertions", "measurements", "sources", "prompt",
        },
    )
    schema = _string(item["schema"], "schema")
    if schema != SCHEMA:
        raise EvidenceError("E_SCHEMA", "schema must be kinglet.spike.evidence/v1")
    command = tuple(
        _string(part, f"command[{index}]")
        for index, part in enumerate(_array(item["command"], "command"))
    )
    return EvidenceRecord(
        schema=schema,
        run_id=_string(item["run_id"], "run_id"),
        subject=_subject(item["subject"]),
        probe=_probe(item["probe"]),
        environment=_environment(item["environment"]),
        started_at=_string(item["started_at"], "started_at"),
        ended_at=_string(item["ended_at"], "ended_at"),
        status=_status(item["status"], "status"),
        command=command,
        artifacts=tuple(_artifact(value, index) for index, value in enumerate(_array(item["artifacts"], "artifacts"))),
        assertions=tuple(_assertion(value, index) for index, value in enumerate(_array(item["assertions"], "assertions"))),
        measurements=tuple(
            _measurement(value, index) for index, value in enumerate(_array(item["measurements"], "measurements"))
        ),
        sources=tuple(_source(value, index) for index, value in enumerate(_array(item["sources"], "sources"))),
        prompt=_prompt(item["prompt"]),
    )
