from __future__ import annotations

import hashlib
import json
import re
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path, PureWindowsPath

from .model import Diagnostic, EvidenceError, EvidenceRecord

SHA256 = re.compile(r"^[0-9a-f]{64}$")
SECRET_PATTERNS = (
    re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"sk-[A-Za-z0-9_-]{20,}"),
    re.compile(r"(?i)(token|password|secret)=\S+"),
)
SENSITIVE_PATH_PATTERNS = (
    re.compile(r"(?<![A-Za-z0-9])/(?:Users|home)/[^/\s]+"),
    re.compile(r"(?i)(?<![A-Za-z0-9])[A-Z]:\\Users\\[^\\\s]+"),
)


def _artifact_path(artifact_root: Path, relative: str) -> Path:
    candidate = Path(relative)
    windows_candidate = PureWindowsPath(relative)
    if (
        not relative
        or candidate.is_absolute()
        or windows_candidate.is_absolute()
        or ".." in candidate.parts
        or ".." in windows_candidate.parts
    ):
        raise EvidenceError("E_PATH", f"unsafe artifact path: {relative}")
    if artifact_root.is_symlink():
        raise EvidenceError("E_SYMLINK", f"artifact root is a symlink: {artifact_root}")
    root = artifact_root.resolve()
    current = artifact_root
    for part in candidate.parts:
        current = current / part
        if current.is_symlink():
            raise EvidenceError("E_SYMLINK", f"artifact path contains symlink: {relative}")
    resolved = current.resolve()
    if not resolved.is_relative_to(root):
        raise EvidenceError("E_PATH", f"artifact escapes evidence root: {relative}")
    return resolved


def _digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _diagnostic(error: EvidenceError, location: str) -> Diagnostic:
    return Diagnostic(error.code, location, error.detail)


def _parse_utc(timestamp: str, location: str) -> tuple[datetime | None, Diagnostic | None]:
    if not timestamp.endswith("Z"):
        return None, Diagnostic("E_TIME", location, "timestamp must use UTC Z")
    try:
        parsed = datetime.fromisoformat(f"{timestamp[:-1]}+00:00")
    except ValueError:
        return None, Diagnostic("E_TIME", location, "timestamp is not valid ISO 8601")
    if parsed.tzinfo != timezone.utc:
        return None, Diagnostic("E_TIME", location, "timestamp must use UTC Z")
    return parsed, None


def _scan_sensitive(record: EvidenceRecord) -> tuple[Diagnostic, ...]:
    serialized = json.dumps(asdict(record), ensure_ascii=False, sort_keys=True)
    diagnostics: list[Diagnostic] = []
    for pattern in SECRET_PATTERNS:
        if pattern.search(serialized):
            diagnostics.append(
                Diagnostic("E_SECRET", "record", "record contains a credential-like value")
            )
            break
    for pattern in SENSITIVE_PATH_PATTERNS:
        if pattern.search(serialized):
            diagnostics.append(
                Diagnostic("E_PATH", "record", "record contains an absolute user path")
            )
            break
    return tuple(diagnostics)


def validate_record(
    record: EvidenceRecord,
    artifact_root: Path,
) -> tuple[Diagnostic, ...]:
    diagnostics: list[Diagnostic] = list(_scan_sensitive(record))

    started, started_error = _parse_utc(record.started_at, "started_at")
    ended, ended_error = _parse_utc(record.ended_at, "ended_at")
    if started_error is not None:
        diagnostics.append(started_error)
    if ended_error is not None:
        diagnostics.append(ended_error)
    if started is not None and ended is not None and ended < started:
        diagnostics.append(
            Diagnostic("E_TIME", "ended_at", "ended_at precedes started_at")
        )

    for index, artifact in enumerate(record.artifacts):
        location = f"artifacts[{index}]"
        try:
            path = _artifact_path(artifact_root, artifact.path)
        except EvidenceError as error:
            diagnostics.append(_diagnostic(error, f"{location}.path"))
            continue
        if not path.is_file():
            diagnostics.append(
                Diagnostic("E_PATH", f"{location}.path", "artifact file is missing")
            )
            continue
        if not SHA256.fullmatch(artifact.sha256):
            diagnostics.append(
                Diagnostic(
                    "E_CHECKSUM",
                    f"{location}.sha256",
                    "artifact checksum must be lowercase SHA-256",
                )
            )
            continue
        if _digest(path) != artifact.sha256:
            diagnostics.append(
                Diagnostic(
                    "E_CHECKSUM",
                    f"{location}.sha256",
                    "artifact checksum does not match",
                )
            )

    if record.prompt is not None:
        if not record.prompt.id or not SHA256.fullmatch(record.prompt.sha256):
            diagnostics.append(
                Diagnostic(
                    "E_PROMPT",
                    "prompt",
                    "prompt requires an ID and lowercase SHA-256 digest",
                )
            )

    if record.status == "pass":
        if not any(artifact.required for artifact in record.artifacts):
            diagnostics.append(
                Diagnostic(
                    "E_ASSERTION",
                    "artifacts",
                    "pass requires at least one required artifact",
                )
            )
        for index, assertion in enumerate(record.assertions):
            if assertion.status != "pass":
                diagnostics.append(
                    Diagnostic(
                        "E_ASSERTION",
                        f"assertions[{index}]",
                        f"pass record contains {assertion.status} assertion: {assertion.id}",
                    )
                )
        if not record.assertions:
            diagnostics.append(
                Diagnostic("E_ASSERTION", "assertions", "pass requires assertions")
            )
        for index, measurement in enumerate(record.measurements):
            if measurement.id != "cold-start":
                continue
            if len(measurement.samples) < 5 or any(
                type(sample) is not int or sample <= 0 for sample in measurement.samples
            ):
                diagnostics.append(
                    Diagnostic(
                        "E_REPETITION",
                        f"measurements[{index}]",
                        "cold-start requires at least five positive integer samples",
                    )
                )

    return tuple(sorted(diagnostics))
