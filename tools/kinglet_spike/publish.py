from __future__ import annotations

import hashlib
import json
import os
import re
from dataclasses import asdict
from pathlib import Path

from .load import load_record
from .model import EvidenceError, EvidenceRecord
from .validate import _artifact_path, validate_record

SAFE_COMPONENT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def record_to_json(record: EvidenceRecord) -> str:
    return json.dumps(
        asdict(record),
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    ) + "\n"


def _component(value: str, location: str) -> str:
    if not SAFE_COMPONENT.fullmatch(value):
        raise EvidenceError("E_PATH", f"unsafe {location}: {value}")
    return value


def _destination(root: Path, relative: Path) -> Path:
    if relative.is_absolute() or ".." in relative.parts:
        raise EvidenceError("E_PATH", f"unsafe publication path: {relative}")
    if root.is_symlink():
        raise EvidenceError("E_SYMLINK", f"publication root is a symlink: {root}")
    resolved_root = root.resolve()
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise EvidenceError(
                "E_SYMLINK",
                f"publication path contains symlink: {relative}",
            )
    resolved = current.resolve()
    if not resolved.is_relative_to(resolved_root):
        raise EvidenceError("E_PATH", f"publication path escapes root: {relative}")
    return current


def _copy_exclusive(source: Path, destination: Path, expected_sha256: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        descriptor = os.open(
            destination,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
            0o644,
        )
    except FileExistsError as error:
        raise EvidenceError(
            "E_IMMUTABLE",
            f"artifact already published: {destination}",
        ) from error

    digest = hashlib.sha256()
    try:
        with source.open("rb") as input_stream, os.fdopen(descriptor, "wb") as output_stream:
            for chunk in iter(lambda: input_stream.read(1024 * 1024), b""):
                output_stream.write(chunk)
                digest.update(chunk)
            output_stream.flush()
            os.fsync(output_stream.fileno())
        if digest.hexdigest() != expected_sha256:
            raise EvidenceError(
                "E_CHECKSUM",
                f"published artifact checksum mismatch: {destination}",
            )
    except Exception:
        destination.unlink(missing_ok=True)
        raise


def _write_exclusive(target: Path, payload: bytes, run_id: str) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    except FileExistsError as error:
        raise EvidenceError("E_IMMUTABLE", f"run already published: {run_id}") from error
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
    except Exception:
        target.unlink(missing_ok=True)
        raise


def publish_record(raw_path: Path, repo_root: Path) -> Path:
    record = load_record(raw_path)
    publish_root = raw_path.parent / "publish"
    diagnostics = validate_record(record, publish_root)
    if diagnostics:
        first = diagnostics[0]
        raise EvidenceError(first.code, f"{first.location}: {first.message}")

    committed_root = repo_root / "docs/research/platform-spike"
    targets: list[tuple[Path, Path, str]] = []
    for artifact in record.artifacts:
        source = _artifact_path(publish_root, artifact.path)
        artifact_target = _destination(committed_root, Path(artifact.path))
        targets.append((source, artifact_target, artifact.sha256))

    subject_kind = _component(record.subject.kind, "subject kind")
    subject_id = _component(record.subject.id, "subject ID")
    run_id = _component(record.run_id, "run ID")
    target = _destination(
        committed_root,
        Path("evidence") / subject_kind / subject_id / f"{run_id}.json",
    )
    if target.exists() or any(destination.exists() for _, destination, _ in targets):
        raise EvidenceError("E_IMMUTABLE", f"run already published: {record.run_id}")

    for source, destination, expected_sha256 in targets:
        _copy_exclusive(source, destination, expected_sha256)
    _write_exclusive(
        target,
        record_to_json(record).encode("utf-8"),
        record.run_id,
    )
    return target
