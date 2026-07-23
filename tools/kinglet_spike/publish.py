"""Immutable publication for sanitized platform-spike evidence."""

from __future__ import annotations

from dataclasses import asdict
import hashlib
import json
import os
from pathlib import Path

from tools.kinglet_spike.load import load_record
from tools.kinglet_spike.model import EvidenceError, EvidenceRecord
from tools.kinglet_spike.validate import _artifact_path, validate_record


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(65536), b""):
            digest.update(block)
    return digest.hexdigest()


def _copy_exclusive(source: Path, destination: Path, expected_sha256: str) -> None:
    """Copy one artifact without ever replacing an existing destination."""
    try:
        descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    except FileExistsError as error:
        raise EvidenceError("E_IMMUTABLE", f"artifact already published: {destination}") from error

    try:
        with source.open("rb") as input_stream, os.fdopen(descriptor, "wb") as output_stream:
            for block in iter(lambda: input_stream.read(65536), b""):
                output_stream.write(block)
            output_stream.flush()
            os.fsync(output_stream.fileno())
        if _sha256(destination) != expected_sha256:
            raise EvidenceError("E_CHECKSUM", f"published artifact checksum changed: {source}")
    except BaseException:
        destination.unlink(missing_ok=True)
        raise


def record_to_json(record: EvidenceRecord) -> str:
    """Render a stable, reviewable representation of a frozen evidence record."""
    return json.dumps(asdict(record), ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def _raw_run_directory(raw_path: Path, repo_root: Path) -> Path:
    raw_root = (repo_root / ".kinglet/local/spikes").resolve()
    try:
        resolved = raw_path.resolve(strict=True)
    except OSError as error:
        raise EvidenceError("E_PATH", f"raw record is unavailable: {raw_path}") from error
    if raw_path.name != "record.json" or not resolved.is_relative_to(raw_root):
        raise EvidenceError("E_PATH", "raw record must be below .kinglet/local/spikes/<run-id>/record.json")
    return resolved.parent


def _write_record_exclusive(target: Path, payload: bytes, run_id: str) -> None:
    try:
        descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    except FileExistsError as error:
        raise EvidenceError("E_IMMUTABLE", f"run already published: {run_id}") from error
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())


def publish_record(raw_path: Path, repo_root: Path) -> Path:
    """Publish validated sanitized evidence exactly once, without overwriting history."""
    raw_path = Path(raw_path)
    repo_root = Path(repo_root)
    run_directory = _raw_run_directory(raw_path, repo_root)
    record = load_record(raw_path)
    publish_root = run_directory / "publish"
    diagnostics = validate_record(record, publish_root)
    if diagnostics:
        first = diagnostics[0]
        raise EvidenceError(first.code, f"{first.location}: {first.message}")

    committed_root = repo_root / "docs/research/platform-spike"
    targets = tuple(
        (
            _artifact_path(publish_root, artifact.path),
            committed_root / artifact.path,
            artifact.sha256,
        )
        for artifact in record.artifacts
    )
    target = (
        committed_root / "evidence" / record.subject.kind / record.subject.id / f"{record.run_id}.json"
    )
    if target.exists() or any(destination.exists() for _, destination, _ in targets):
        raise EvidenceError("E_IMMUTABLE", f"run already published: {record.run_id}")

    for source, destination, expected_sha256 in targets:
        destination.parent.mkdir(parents=True, exist_ok=True)
        _copy_exclusive(source, destination, expected_sha256)

    target.parent.mkdir(parents=True, exist_ok=True)
    _write_record_exclusive(target, record_to_json(record).encode("utf-8"), record.run_id)
    return target
