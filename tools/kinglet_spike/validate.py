"""Safety, integrity, and pass-completeness checks for spike evidence."""

from __future__ import annotations

import hashlib
import re
from dataclasses import asdict
from datetime import datetime
from pathlib import Path

from tools.kinglet_spike.model import Diagnostic, EvidenceError, EvidenceRecord
from tools.kinglet_spike.redact import SECRET_PATTERNS


SHA256 = re.compile(r"^[0-9a-f]{64}$")
WINDOWS_ABSOLUTE = re.compile(r"(?i)^[a-z]:[\\/]|^\\\\")


def _artifact_path(artifact_root: Path, relative: str) -> Path:
    candidate = Path(relative)
    if candidate.is_absolute() or WINDOWS_ABSOLUTE.match(relative) or "\\" in relative or ".." in candidate.parts:
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


def _diagnostic(code: str, location: str, message: str) -> Diagnostic:
    return Diagnostic(code, location, message)


def _timestamp(value: str, location: str) -> datetime:
    if not value.endswith("Z"):
        raise EvidenceError("E_TIME", f"{location} must end in Z")
    try:
        parsed = datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as error:
        raise EvidenceError("E_TIME", f"{location} is not an ISO-8601 timestamp") from error
    if parsed.tzinfo is None:
        raise EvidenceError("E_TIME", f"{location} must be UTC")
    return parsed


def _strings(value: object):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from _strings(item)
    elif isinstance(value, (tuple, list)):
        for item in value:
            yield from _strings(item)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(65536), b""):
            digest.update(block)
    return digest.hexdigest()


def validate_record(record: EvidenceRecord, artifact_root: Path) -> tuple[Diagnostic, ...]:
    """Return stable diagnostics without permitting unsafe evidence publication."""
    diagnostics: list[Diagnostic] = []
    try:
        started_at = _timestamp(record.started_at, "started_at")
        ended_at = _timestamp(record.ended_at, "ended_at")
        if ended_at < started_at:
            diagnostics.append(_diagnostic("E_TIME", "ended_at", "ended_at precedes started_at"))
    except EvidenceError as error:
        diagnostics.append(_diagnostic(error.code, "timestamps", error.detail))

    for index, value in enumerate(_strings(asdict(record))):
        for pattern in SECRET_PATTERNS:
            if pattern.search(value):
                diagnostics.append(_diagnostic("E_SECRET", f"string[{index}]", "evidence contains a credential"))
                break

    if record.prompt is not None and not SHA256.fullmatch(record.prompt.sha256):
        diagnostics.append(_diagnostic("E_PROMPT", "prompt.sha256", "prompt digest must be lowercase SHA-256"))

    for index, artifact in enumerate(record.artifacts):
        location = f"artifacts[{index}]"
        if not SHA256.fullmatch(artifact.sha256):
            diagnostics.append(_diagnostic("E_CHECKSUM", f"{location}.sha256", "artifact digest must be lowercase SHA-256"))
        try:
            path = _artifact_path(artifact_root, artifact.path)
            if not path.is_file():
                raise EvidenceError("E_PATH", f"artifact is missing: {artifact.path}")
            elif SHA256.fullmatch(artifact.sha256) and _sha256(path) != artifact.sha256:
                diagnostics.append(_diagnostic("E_CHECKSUM", f"{location}.sha256", "artifact digest does not match"))
        except EvidenceError as error:
            diagnostics.append(_diagnostic(error.code, f"{location}.path", error.detail))

    if record.status == "pass":
        if not any(artifact.required for artifact in record.artifacts):
            diagnostics.append(_diagnostic("E_ASSERTION", "artifacts", "pass requires a required artifact"))
        for index, assertion in enumerate(record.assertions):
            if assertion.status != "pass":
                diagnostics.append(_diagnostic("E_ASSERTION", f"assertions[{index}].status", "pass requires passing assertions"))
        cold_start_found = False
        for index, measurement in enumerate(record.measurements):
            if measurement.id == "cold-start":
                cold_start_found = True
            if measurement.id == "cold-start" and (
                len(measurement.samples) < 5 or any(sample <= 0 for sample in measurement.samples)
            ):
                diagnostics.append(_diagnostic("E_REPETITION", f"measurements[{index}].samples", "cold-start requires five positive samples"))
        if not cold_start_found:
            diagnostics.append(_diagnostic("E_REPETITION", "measurements", "pass requires a cold-start measurement"))

    return tuple(sorted(set(diagnostics)))
