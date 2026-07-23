"""Immutable publication for sanitized platform-spike evidence."""

from __future__ import annotations

from dataclasses import asdict
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import stat

from tools.kinglet_spike.load import load_record
from tools.kinglet_spike.model import EvidenceError, EvidenceRecord
from tools.kinglet_spike.validate import _artifact_path, validate_record


_MAX_OPAQUE_SEGMENT_BYTES = 128
_WINDOWS_DRIVE = re.compile(r"(?i)^[a-z]:")


def _opaque_segment(value: str, location: str) -> str:
    """Return one bounded path component, rejecting platform-neutral escapes."""
    if (
        not value
        or len(value.encode("utf-8")) > _MAX_OPAQUE_SEGMENT_BYTES
        or value in {".", ".."}
        or "/" in value
        or "\\" in value
        or "\x00" in value
        or Path(value).is_absolute()
        or _WINDOWS_DRIVE.match(value)
    ):
        raise EvidenceError("E_PATH", f"{location} must be a bounded opaque path component")
    return value


def _artifact_parts(relative: str) -> tuple[str, ...]:
    """Preserve only portable, explicit relative artifact components."""
    if not relative or "\\" in relative or relative.startswith("/") or _WINDOWS_DRIVE.match(relative):
        raise EvidenceError("E_PATH", f"unsafe artifact path: {relative}")
    parts = tuple(relative.split("/"))
    if any(part in {"", ".", ".."} for part in parts):
        raise EvidenceError("E_PATH", f"unsafe artifact path: {relative}")
    return parts


def _identity(metadata: os.stat_result) -> tuple[int, int]:
    return metadata.st_dev, metadata.st_ino


def _raise_symlink(path: Path) -> None:
    raise EvidenceError("E_SYMLINK", f"path contains a symbolic link: {path}")


def _require_directory(path: Path) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        raise EvidenceError("E_PATH", f"destination parent is unavailable: {path}") from None
    if stat.S_ISLNK(metadata.st_mode):
        _raise_symlink(path)
    if not stat.S_ISDIR(metadata.st_mode):
        raise EvidenceError("E_PATH", f"destination parent is not a directory: {path}")


def _assert_existing_parent_chain(repo_root: Path, destination: Path) -> None:
    """Reject a pre-existing symbolic link before creating or opening a target."""
    try:
        relative = destination.parent.relative_to(repo_root)
    except ValueError as error:
        raise EvidenceError("E_PATH", f"destination escapes repository: {destination}") from error

    current = repo_root
    _require_directory(current)
    for part in relative.parts:
        current = current / part
        try:
            metadata = current.lstat()
        except FileNotFoundError:
            return
        if stat.S_ISLNK(metadata.st_mode):
            _raise_symlink(current)
        if not stat.S_ISDIR(metadata.st_mode):
            raise EvidenceError("E_PATH", f"destination parent is not a directory: {current}")


def _prepare_destination_parent(repo_root: Path, committed_root: Path, destination: Path) -> None:
    """Create a parent chain while rejecting links, then re-check containment."""
    _assert_existing_parent_chain(repo_root, destination)
    relative = destination.parent.relative_to(repo_root)
    current = repo_root
    for part in relative.parts:
        current = current / part
        try:
            metadata = current.lstat()
        except FileNotFoundError:
            try:
                current.mkdir()
            except FileExistsError:
                pass
            _require_directory(current)
            continue
        if stat.S_ISLNK(metadata.st_mode):
            _raise_symlink(current)
        if not stat.S_ISDIR(metadata.st_mode):
            raise EvidenceError("E_PATH", f"destination parent is not a directory: {current}")

    _assert_existing_parent_chain(repo_root, destination)
    try:
        resolved_root = committed_root.resolve(strict=True)
        resolved_parent = destination.parent.resolve(strict=True)
    except OSError as error:
        raise EvidenceError("E_PATH", f"destination parent is unavailable: {destination.parent}") from error
    if not resolved_parent.is_relative_to(resolved_root):
        raise EvidenceError("E_PATH", f"destination escapes platform-spike evidence: {destination}")


def _existing_destination(destination: Path) -> bool:
    try:
        metadata = destination.lstat()
    except FileNotFoundError:
        return False
    if stat.S_ISLNK(metadata.st_mode):
        _raise_symlink(destination)
    return True


def _open_regular_source(source: Path) -> int:
    """Open a regular artifact without following a symlink at the copy boundary."""
    try:
        before = source.lstat()
    except FileNotFoundError as error:
        raise EvidenceError("E_PATH", f"artifact is missing: {source}") from error
    if stat.S_ISLNK(before.st_mode):
        _raise_symlink(source)
    if not stat.S_ISREG(before.st_mode):
        raise EvidenceError("E_PATH", f"artifact is not a regular file: {source}")

    flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(source, flags)
    except OSError as error:
        if error.errno == errno.ELOOP:
            _raise_symlink(source)
        raise EvidenceError("E_PATH", f"artifact is unavailable: {source}") from error
    try:
        after = os.fstat(descriptor)
        final = source.lstat()
        if stat.S_ISLNK(final.st_mode):
            _raise_symlink(source)
        if not stat.S_ISREG(after.st_mode) or _identity(before) != _identity(after) or _identity(after) != _identity(final):
            raise EvidenceError("E_PATH", f"artifact changed while opening: {source}")
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def _unlink_if_same(path: Path, expected: tuple[int, int] | None) -> None:
    if expected is None:
        return
    try:
        actual = path.lstat()
    except FileNotFoundError:
        return
    if stat.S_ISREG(actual.st_mode) and _identity(actual) == expected:
        path.unlink()


def _copy_exclusive(
    source: Path,
    destination: Path,
    expected_sha256: str,
    *,
    repo_root: Path | None = None,
    committed_root: Path | None = None,
) -> None:
    """Copy one regular artifact without replacing a destination or following links."""
    if (repo_root is None) != (committed_root is None):
        raise ValueError("repo_root and committed_root must be supplied together")
    source_descriptor = _open_regular_source(source)
    destination_descriptor: int | None = None
    destination_identity: tuple[int, int] | None = None
    try:
        if repo_root is not None and committed_root is not None:
            _prepare_destination_parent(repo_root, committed_root, destination)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
        try:
            destination_descriptor = os.open(destination, flags, 0o644)
        except FileExistsError as error:
            raise EvidenceError("E_IMMUTABLE", f"artifact already published: {destination}") from error
        except OSError as error:
            if error.errno == errno.ELOOP:
                _raise_symlink(destination)
            raise EvidenceError("E_PATH", f"artifact destination is unavailable: {destination}") from error
        destination_identity = _identity(os.fstat(destination_descriptor))
        digest = hashlib.sha256()
        with os.fdopen(source_descriptor, "rb") as input_stream, os.fdopen(destination_descriptor, "wb") as output_stream:
            source_descriptor = None
            destination_descriptor = None
            for block in iter(lambda: input_stream.read(65536), b""):
                digest.update(block)
                output_stream.write(block)
            output_stream.flush()
            os.fsync(output_stream.fileno())
        if digest.hexdigest() != expected_sha256:
            raise EvidenceError("E_CHECKSUM", f"published artifact checksum changed: {source}")
    except BaseException:
        _unlink_if_same(destination, destination_identity)
        raise
    finally:
        if source_descriptor is not None:
            os.close(source_descriptor)
        if destination_descriptor is not None:
            os.close(destination_descriptor)


def record_to_json(record: EvidenceRecord) -> str:
    """Render a stable, reviewable representation of a frozen evidence record."""
    return json.dumps(asdict(record), ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def _raw_run_directory(raw_path: Path, repo_root: Path) -> Path:
    raw_root = (repo_root / ".kinglet/local/spikes").absolute()
    raw_path = raw_path.absolute()
    try:
        relative = raw_path.relative_to(raw_root)
    except ValueError as error:
        raise EvidenceError("E_PATH", "raw record must be below .kinglet/local/spikes/<run-id>/record.json") from error
    if len(relative.parts) != 2 or relative.parts[1] != "record.json":
        raise EvidenceError("E_PATH", "raw record must be directly below .kinglet/local/spikes/<run-id>/record.json")
    _opaque_segment(relative.parts[0], "raw run directory")
    run_directory = raw_path.parent
    try:
        run_metadata = run_directory.lstat()
        record_metadata = raw_path.lstat()
        resolved_root = raw_root.resolve(strict=True)
        resolved_record = raw_path.resolve(strict=True)
    except OSError as error:
        raise EvidenceError("E_PATH", f"raw record is unavailable: {raw_path}") from error
    if stat.S_ISLNK(run_metadata.st_mode) or stat.S_ISLNK(record_metadata.st_mode):
        _raise_symlink(run_directory if stat.S_ISLNK(run_metadata.st_mode) else raw_path)
    if not stat.S_ISDIR(run_metadata.st_mode) or not stat.S_ISREG(record_metadata.st_mode):
        raise EvidenceError("E_PATH", f"raw record is not a regular file: {raw_path}")
    if resolved_record.parent.parent != resolved_root:
        raise EvidenceError("E_PATH", "raw record must be directly below .kinglet/local/spikes/<run-id>/record.json")
    return run_directory


def _write_record_exclusive(
    target: Path,
    payload: bytes,
    run_id: str,
    repo_root: Path,
    committed_root: Path,
) -> None:
    _prepare_destination_parent(repo_root, committed_root, target)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(target, flags, 0o644)
    except FileExistsError as error:
        raise EvidenceError("E_IMMUTABLE", f"run already published: {run_id}") from error
    except OSError as error:
        if error.errno == errno.ELOOP:
            _raise_symlink(target)
        raise EvidenceError("E_PATH", f"evidence destination is unavailable: {target}") from error
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())


def publish_record(raw_path: Path, repo_root: Path) -> Path:
    """Publish validated sanitized evidence exactly once, without overwriting history."""
    raw_path = Path(raw_path)
    repo_root = Path(repo_root).absolute()
    run_directory = _raw_run_directory(raw_path, repo_root)
    record = load_record(raw_path)
    subject_kind = _opaque_segment(record.subject.kind, "subject.kind")
    subject_id = _opaque_segment(record.subject.id, "subject.id")
    run_id = _opaque_segment(record.run_id, "run_id")
    publish_root = run_directory / "publish"
    diagnostics = validate_record(record, publish_root)
    if diagnostics:
        first = diagnostics[0]
        raise EvidenceError(first.code, f"{first.location}: {first.message}")

    committed_root = repo_root / "docs/research/platform-spike"
    targets = tuple(
        (
            _artifact_path(publish_root, artifact.path),
            committed_root.joinpath(*_artifact_parts(artifact.path)),
            artifact.sha256,
        )
        for artifact in record.artifacts
    )
    target = committed_root / "evidence" / subject_kind / subject_id / f"{run_id}.json"
    destinations = tuple(destination for _, destination, _ in targets) + (target,)
    if len(set(destinations)) != len(destinations):
        raise EvidenceError("E_PATH", "evidence record has duplicate publication destinations")
    for destination in destinations:
        _assert_existing_parent_chain(repo_root, destination)
    if any(_existing_destination(destination) for destination in destinations):
        raise EvidenceError("E_IMMUTABLE", f"run already published: {record.run_id}")

    for source, destination, expected_sha256 in targets:
        _prepare_destination_parent(repo_root, committed_root, destination)
        _copy_exclusive(
            source,
            destination,
            expected_sha256,
            repo_root=repo_root,
            committed_root=committed_root,
        )

    _write_record_exclusive(
        target,
        record_to_json(record).encode("utf-8"),
        record.run_id,
        repo_root,
        committed_root,
    )
    return target
