"""Immutable publication for sanitized platform-spike evidence."""

from __future__ import annotations

from dataclasses import asdict, dataclass
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
_DIRECTORY_FD_SUPPORTED = (
    os.open in os.supports_dir_fd
    and os.mkdir in os.supports_dir_fd
    and os.unlink in os.supports_dir_fd
    and hasattr(os, "O_NOFOLLOW")
)


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


@dataclass
class _CreatedTarget:
    """A new file held beneath the directory that was verified for its creation."""

    descriptor: int
    destination: Path
    identity: tuple[int, int]
    parent_descriptor: int | None = None
    name: str | None = None
    windows_handle: bool = False


def _directory_fd_supported() -> bool:
    return _DIRECTORY_FD_SUPPORTED


def _directory_open_flags() -> int:
    return (
        os.O_RDONLY
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_BINARY", 0)
    )


def _open_verified_parent(repo_root: Path, committed_root: Path, destination: Path) -> int:
    """Return a no-follow descriptor for destination.parent, creating it safely."""
    try:
        relative_to_root = destination.parent.relative_to(repo_root)
        destination.parent.relative_to(committed_root)
    except ValueError as error:
        raise EvidenceError("E_PATH", f"destination escapes platform-spike evidence: {destination}") from error

    try:
        current = os.open(repo_root, _directory_open_flags())
    except OSError as error:
        if error.errno == errno.ELOOP:
            _raise_symlink(repo_root)
        raise EvidenceError("E_PATH", f"repository root is unavailable: {repo_root}") from error

    try:
        for part in relative_to_root.parts:
            try:
                os.mkdir(part, mode=0o755, dir_fd=current)
            except FileExistsError:
                pass
            except OSError as error:
                raise EvidenceError("E_PATH", f"destination parent is unavailable: {destination.parent}") from error
            try:
                child = os.open(part, _directory_open_flags(), dir_fd=current)
            except OSError as error:
                if error.errno == errno.ELOOP:
                    _raise_symlink(destination.parent)
                raise EvidenceError("E_PATH", f"destination parent is unavailable: {destination.parent}") from error
            try:
                if not stat.S_ISDIR(os.fstat(child).st_mode):
                    raise EvidenceError("E_PATH", f"destination parent is not a directory: {destination.parent}")
            except BaseException:
                os.close(child)
                raise
            os.close(current)
            current = child
        return current
    except BaseException:
        os.close(current)
        raise


def _windows_final_path(descriptor: int) -> str:
    """Read a Windows handle's canonical path; callers use it before writing."""
    import ctypes
    import msvcrt

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    function = kernel32.GetFinalPathNameByHandleW
    function.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32]
    function.restype = ctypes.c_uint32
    handle = ctypes.c_void_p(msvcrt.get_osfhandle(descriptor))
    size = 260
    while True:
        buffer = ctypes.create_unicode_buffer(size)
        length = function(handle, buffer, size, 0)
        if not length:
            raise OSError(ctypes.get_last_error(), "GetFinalPathNameByHandleW failed")
        if length < size:
            return buffer.value
        size = length + 1


def _windows_is_relative_to(path: str, root: str) -> bool:
    import ntpath

    normalized_path = ntpath.normcase(ntpath.normpath(path))
    normalized_root = ntpath.normcase(ntpath.normpath(root))
    try:
        return ntpath.commonpath((normalized_path, normalized_root)) == normalized_root
    except ValueError:
        return False


def _windows_mark_delete(descriptor: int) -> None:
    """Delete precisely the open file handle, never a later pathname replacement."""
    import ctypes
    import msvcrt

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    function = kernel32.SetFileInformationByHandle
    function.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    function.restype = ctypes.c_int
    delete = ctypes.c_int(1)
    if not function(
        ctypes.c_void_p(msvcrt.get_osfhandle(descriptor)),
        4,  # FileDispositionInfo
        ctypes.byref(delete),
        ctypes.sizeof(delete),
    ):
        raise OSError(ctypes.get_last_error(), "SetFileInformationByHandle failed")


def _open_windows_exclusive(destination: Path, committed_root: Path) -> _CreatedTarget:
    """Create once, then prove the opened Windows handle remains under the root."""
    # Load both APIs before creating anything, so a missing safe cleanup path fails closed.
    try:
        root_descriptor = os.open(committed_root, os.O_RDONLY | getattr(os, "O_BINARY", 0))
        try:
            root_final = _windows_final_path(root_descriptor)
        finally:
            os.close(root_descriptor)
        # Probe the exact-handle deletion API before creating a target.
        import ctypes

        ctypes.WinDLL("kernel32", use_last_error=True).SetFileInformationByHandle
    except OSError as error:
        raise EvidenceError("E_PATH", f"Windows safe publication is unavailable: {destination}") from error

    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_BINARY", 0)
    try:
        descriptor = os.open(destination, flags, 0o644)
    except FileExistsError as error:
        raise EvidenceError("E_IMMUTABLE", f"target already published: {destination}") from error
    except OSError as error:
        raise EvidenceError("E_PATH", f"destination is unavailable: {destination}") from error
    created = _CreatedTarget(
        descriptor=descriptor,
        destination=destination,
        identity=_identity(os.fstat(descriptor)),
        windows_handle=True,
    )
    try:
        if not _windows_is_relative_to(_windows_final_path(descriptor), root_final):
            _windows_mark_delete(descriptor)
            raise EvidenceError("E_PATH", f"destination escapes platform-spike evidence: {destination}")
        return created
    except BaseException:
        if created.descriptor is not None:
            os.close(created.descriptor)
            created.descriptor = None  # type: ignore[assignment]
        raise


def _open_exclusive_target(repo_root: Path, committed_root: Path, destination: Path, immutable_message: str) -> _CreatedTarget:
    """Open a fresh target without losing the verified parent to a pathname race."""
    if _directory_fd_supported():
        parent_descriptor = _open_verified_parent(repo_root, committed_root, destination)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0)
        try:
            descriptor = os.open(destination.name, flags, 0o644, dir_fd=parent_descriptor)
        except FileExistsError as error:
            os.close(parent_descriptor)
            raise EvidenceError("E_IMMUTABLE", immutable_message) from error
        except OSError as error:
            os.close(parent_descriptor)
            if error.errno == errno.ELOOP:
                _raise_symlink(destination)
            raise EvidenceError("E_PATH", f"destination is unavailable: {destination}") from error
        return _CreatedTarget(
            descriptor=descriptor,
            destination=destination,
            identity=_identity(os.fstat(descriptor)),
            parent_descriptor=parent_descriptor,
            name=destination.name,
        )
    if os.name == "nt":
        return _open_windows_exclusive(destination, committed_root)
    raise EvidenceError("E_PATH", "safe descriptor-relative publication is unavailable on this platform")


def _cleanup_created(target: _CreatedTarget | None) -> None:
    if target is None or target.descriptor is None:
        return
    if target.windows_handle:
        _windows_mark_delete(target.descriptor)
        return
    if target.parent_descriptor is not None and target.name is not None:
        try:
            actual = os.stat(target.name, dir_fd=target.parent_descriptor, follow_symlinks=False)
        except FileNotFoundError:
            return
        if stat.S_ISREG(actual.st_mode) and _identity(actual) == target.identity:
            os.unlink(target.name, dir_fd=target.parent_descriptor)
        return
        return


def _close_created(target: _CreatedTarget | None) -> None:
    if target is None:
        return
    if target.descriptor is not None:
        os.close(target.descriptor)
        target.descriptor = None  # type: ignore[assignment]
    if target.parent_descriptor is not None:
        os.close(target.parent_descriptor)
        target.parent_descriptor = None  # type: ignore[assignment]


def _write_all(descriptor: int, content: bytes) -> None:
    view = memoryview(content)
    while view:
        written = os.write(descriptor, view)
        if written <= 0:
            raise OSError("short write while publishing evidence")
        view = view[written:]


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
    created: _CreatedTarget | None = None
    try:
        if repo_root is not None and committed_root is not None:
            created = _open_exclusive_target(
                repo_root,
                committed_root,
                destination,
                f"artifact already published: {destination}",
            )
        else:
            created = _open_exclusive_target(
                destination.parent,
                destination.parent,
                destination,
                f"artifact already published: {destination}",
            )
        digest = hashlib.sha256()
        while True:
            block = os.read(source_descriptor, 65536)
            if not block:
                break
            digest.update(block)
            _write_all(created.descriptor, block)
        os.fsync(created.descriptor)
        if digest.hexdigest() != expected_sha256:
            raise EvidenceError("E_CHECKSUM", f"published artifact checksum changed: {source}")
    except BaseException:
        _cleanup_created(created)
        raise
    finally:
        os.close(source_descriptor)
        _close_created(created)


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
    created: _CreatedTarget | None = None
    try:
        created = _open_exclusive_target(
            repo_root,
            committed_root,
            target,
            f"run already published: {run_id}",
        )
        _write_all(created.descriptor, payload)
        os.fsync(created.descriptor)
    except BaseException:
        _cleanup_created(created)
        raise
    finally:
        _close_created(created)


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
