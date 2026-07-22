import ctypes
import errno
import hashlib
import json
import os
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tempfile

from .renderers import RenderedFile


_MANIFEST_PATH = PurePosixPath(".kinglet-generated.json")
_DIRECTORY_MODE = 0o755
_TEXT_NAMES = frozenset(
    {
        ".gitattributes",
        ".gitignore",
        "AGENTS.md",
        "CLAUDE.md",
        "LICENSE",
        "NOTICE",
        "README",
        "SKILL.md",
        "UPSTREAM",
        "VERSION",
    }
)
_TEXT_SUFFIXES = frozenset(
    {
        ".asmdef",
        ".asmref",
        ".bash",
        ".cs",
        ".css",
        ".html",
        ".js",
        ".json",
        ".md",
        ".ps1",
        ".py",
        ".sh",
        ".template",
        ".toml",
        ".tsv",
        ".txt",
        ".xml",
        ".yaml",
        ".yml",
    }
)


@dataclass(frozen=True)
class WriteResult:
    changed: tuple[PurePosixPath, ...]
    stale: tuple[PurePosixPath, ...]


class _RollbackError(OSError):
    pass


@dataclass(frozen=True)
class _ExpectedFile:
    content: bytes
    mode: int


@dataclass(frozen=True)
class _ActualFile:
    kind: str
    content: bytes | None
    mode: int | None


def _is_text_path(path: PurePosixPath) -> bool:
    return path.name in _TEXT_NAMES or path.suffix.lower() in _TEXT_SUFFIXES


def _normalized_content(rendered: RenderedFile) -> bytes:
    content = rendered.content
    if not isinstance(content, bytes):
        raise TypeError(f"rendered content for {rendered.path} must be bytes")
    if _is_text_path(rendered.path):
        return content.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return content


def _validate_path(path: object) -> PurePosixPath:
    if not isinstance(path, PurePosixPath):
        raise TypeError("rendered file path must be a PurePosixPath")
    if (
        path.is_absolute()
        or not path.parts
        or path == PurePosixPath(".")
        or ".." in path.parts
        or path == _MANIFEST_PATH
        or _MANIFEST_PATH in path.parents
        or "\\" in path.as_posix()
        or "\x00" in path.as_posix()
    ):
        raise ValueError(
            "rendered file path must name a safe relative product file"
        )
    return path


def _prepare_files(
    files: tuple[RenderedFile, ...],
) -> dict[PurePosixPath, _ExpectedFile]:
    rendered_by_path: dict[PurePosixPath, RenderedFile] = {}
    for rendered in files:
        path = _validate_path(rendered.path)
        if path in rendered_by_path:
            raise ValueError(f"duplicate rendered file path: {path.as_posix()}")
        for parent in path.parents:
            if parent in rendered_by_path:
                raise ValueError(
                    f"rendered file path overlaps another file: {path.as_posix()}"
                )
        if any(path in other.parents for other in rendered_by_path):
            raise ValueError(
                f"rendered file path overlaps another file: {path.as_posix()}"
            )
        if not isinstance(rendered.source_ids, tuple) or not all(
            isinstance(source_id, str) for source_id in rendered.source_ids
        ):
            raise TypeError(f"source IDs for {path.as_posix()} must be strings")
        rendered_by_path[path] = rendered

    expected: dict[PurePosixPath, _ExpectedFile] = {}
    manifest_files: list[dict[str, object]] = []
    for path in sorted(rendered_by_path, key=PurePosixPath.as_posix):
        rendered = rendered_by_path[path]
        content = _normalized_content(rendered)
        mode = 0o755 if path.suffix.lower() == ".sh" else 0o644
        expected[path] = _ExpectedFile(content=content, mode=mode)
        manifest_files.append(
            {
                "path": path.as_posix(),
                "sha256": hashlib.sha256(content).hexdigest(),
                "source_ids": sorted(set(rendered.source_ids)),
            }
        )

    manifest = {
        "files": manifest_files,
        "schema_version": 1,
    }
    manifest_content = (
        json.dumps(
            manifest,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n"
    ).encode("utf-8")
    expected[_MANIFEST_PATH] = _ExpectedFile(
        content=manifest_content,
        mode=0o644,
    )
    return expected


def _expected_directories(
    expected: dict[PurePosixPath, _ExpectedFile],
) -> frozenset[PurePosixPath]:
    directories = {PurePosixPath(".")}
    for path in expected:
        directories.update(
            parent for parent in path.parents if parent != PurePosixPath(".")
        )
    return frozenset(directories)


def _raise_symlink(path: Path) -> None:
    raise OSError(
        errno.ELOOP,
        "generated product paths must not be symbolic links",
        path,
    )


def _assert_safe_ancestors(path: Path) -> None:
    for ancestor in reversed((path, *path.parents)):
        try:
            metadata = ancestor.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(metadata.st_mode):
            _raise_symlink(ancestor)


def _canonical_destination(destination: Path) -> Path:
    return destination.parent.resolve(strict=False) / destination.name


def _destination_state(destination: Path) -> str:
    try:
        metadata = destination.lstat()
    except FileNotFoundError:
        return "missing"
    if stat.S_ISLNK(metadata.st_mode):
        _raise_symlink(destination)
    if not stat.S_ISDIR(metadata.st_mode):
        raise NotADirectoryError(
            errno.ENOTDIR,
            "generated destination must be a directory",
            destination,
        )
    return "directory"


def _read_file_without_following(
    path: str | Path,
    *,
    directory_fd: int | None = None,
) -> _ActualFile:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags, dir_fd=directory_fd)
    except OSError as error:
        if error.errno in (errno.ELOOP, errno.EISDIR):
            return _ActualFile(kind="other", content=None, mode=None)
        raise
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            return _ActualFile(kind="other", content=None, mode=None)
        chunks: list[bytes] = []
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        return _ActualFile(
            kind="file",
            content=b"".join(chunks),
            mode=stat.S_IMODE(metadata.st_mode),
        )
    finally:
        os.close(descriptor)


def _scan_tree(
    destination: Path,
) -> tuple[
    dict[PurePosixPath, _ActualFile],
    dict[PurePosixPath, int],
]:
    actual: dict[PurePosixPath, _ActualFile] = {}
    directory_modes: dict[PurePosixPath, int] = {}
    directory_flags = (
        os.O_RDONLY
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )

    def visit(directory_fd: int, relative: PurePosixPath) -> None:
        with os.scandir(directory_fd) as entries:
            ordered = sorted(entries, key=lambda entry: entry.name)
        for entry in ordered:
            item_relative = relative / entry.name
            metadata = os.stat(
                entry.name,
                dir_fd=directory_fd,
                follow_symlinks=False,
            )
            if stat.S_ISLNK(metadata.st_mode):
                _raise_symlink(destination.joinpath(*item_relative.parts))
            elif stat.S_ISDIR(metadata.st_mode):
                child_fd = os.open(
                    entry.name,
                    directory_flags,
                    dir_fd=directory_fd,
                )
                try:
                    child_metadata = os.fstat(child_fd)
                    if not stat.S_ISDIR(child_metadata.st_mode):
                        actual[item_relative] = _ActualFile(
                            kind="other",
                            content=None,
                            mode=None,
                        )
                    else:
                        directory_modes[item_relative] = stat.S_IMODE(
                            child_metadata.st_mode
                        )
                        visit(child_fd, item_relative)
                finally:
                    os.close(child_fd)
            elif stat.S_ISREG(metadata.st_mode):
                actual[item_relative] = _read_file_without_following(
                    entry.name,
                    directory_fd=directory_fd,
                )
            else:
                actual[item_relative] = _ActualFile(
                    kind="other",
                    content=None,
                    mode=None,
                )
    root_fd = os.open(destination, directory_flags)
    try:
        root_metadata = os.fstat(root_fd)
        if not stat.S_ISDIR(root_metadata.st_mode):
            raise NotADirectoryError(
                errno.ENOTDIR,
                "generated destination must be a directory",
                destination,
            )
        directory_modes[PurePosixPath(".")] = stat.S_IMODE(root_metadata.st_mode)
        visit(root_fd, PurePosixPath())
    finally:
        os.close(root_fd)
    return actual, directory_modes


def _compare(
    expected: dict[PurePosixPath, _ExpectedFile],
    destination: Path,
) -> WriteResult:
    if _destination_state(destination) == "missing":
        return WriteResult(
            changed=tuple(sorted(expected, key=PurePosixPath.as_posix)),
            stale=(),
        )

    actual, directory_modes = _scan_tree(destination)
    changed: set[PurePosixPath] = set()
    for path in sorted(expected, key=PurePosixPath.as_posix):
        wanted = expected[path]
        found = actual.get(path)
        if (
            found is None
            or found.kind != "file"
            or found.content != wanted.content
            or found.mode != wanted.mode
        ):
            changed.add(path)
    for path in _expected_directories(expected):
        if directory_modes.get(path) != _DIRECTORY_MODE:
            changed.add(path)
    stale = sorted(set(actual) - set(expected), key=PurePosixPath.as_posix)
    return WriteResult(
        changed=tuple(sorted(changed, key=PurePosixPath.as_posix)),
        stale=tuple(stale),
    )


def _write_file(path: Path, content: bytes, mode: int) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        with os.fdopen(descriptor, "wb", closefd=False) as stream:
            stream.write(content)
            stream.flush()
            os.fchmod(stream.fileno(), mode)
            os.fsync(stream.fileno())
    finally:
        os.close(descriptor)


def _fsync_directory(path: Path) -> None:
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    descriptor = os.open(path, flags)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _create_directory_chain(path: Path) -> None:
    missing: list[Path] = []
    cursor = path
    while True:
        try:
            metadata = cursor.lstat()
        except FileNotFoundError:
            missing.append(cursor)
            if cursor == cursor.parent:
                raise OSError(errno.ENOENT, "no existing directory ancestor", path)
            cursor = cursor.parent
            continue
        if stat.S_ISLNK(metadata.st_mode):
            _raise_symlink(cursor)
        if not stat.S_ISDIR(metadata.st_mode):
            raise NotADirectoryError(
                errno.ENOTDIR,
                "generated destination parent must be a directory",
                cursor,
            )
        break

    for directory in reversed(missing):
        try:
            os.mkdir(directory, _DIRECTORY_MODE)
        except FileExistsError:
            metadata = directory.lstat()
            if stat.S_ISLNK(metadata.st_mode):
                _raise_symlink(directory)
            if not stat.S_ISDIR(metadata.st_mode):
                raise NotADirectoryError(
                    errno.ENOTDIR,
                    "generated destination parent must be a directory",
                    directory,
                )
            _fsync_directory(directory.parent)
            _fsync_directory(directory)
            continue
        os.chmod(directory, _DIRECTORY_MODE, follow_symlinks=False)
        _fsync_directory(directory.parent)
        _fsync_directory(directory)


def _make_stage(
    expected: dict[PurePosixPath, _ExpectedFile],
    destination: Path,
) -> Path:
    stage = Path(
        tempfile.mkdtemp(
            prefix=f".{destination.name}.kinglet-stage-",
            dir=destination.parent,
        )
    )
    try:
        os.chmod(stage, _DIRECTORY_MODE, follow_symlinks=False)
        directories = {stage}
        for relative in sorted(
            _expected_directories(expected),
            key=lambda item: (len(item.parts), item.as_posix()),
        ):
            if relative == PurePosixPath("."):
                continue
            directory = stage.joinpath(*relative.parts)
            directory.mkdir(mode=_DIRECTORY_MODE)
            os.chmod(directory, _DIRECTORY_MODE, follow_symlinks=False)
            directories.add(directory)
        for relative in sorted(expected, key=PurePosixPath.as_posix):
            path = stage.joinpath(*relative.parts)
            _write_file(path, expected[relative].content, expected[relative].mode)
        for directory in sorted(
            (item for item in directories if item == stage or stage in item.parents),
            key=lambda item: len(item.parts),
            reverse=True,
        ):
            _fsync_directory(directory)
        return stage
    except BaseException:
        shutil.rmtree(stage, ignore_errors=True)
        raise


def _exchange_paths(left: Path, right: Path) -> None:
    library = ctypes.CDLL(None, use_errno=True)
    left_bytes = os.fsencode(left)
    right_bytes = os.fsencode(right)
    ctypes.set_errno(0)
    if sys.platform.startswith("linux"):
        try:
            rename_exchange = library.renameat2
        except AttributeError as error:
            raise OSError(
                errno.ENOSYS,
                "atomic directory exchange is unavailable",
                left,
            ) from error
        rename_exchange.argtypes = (
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_int,
            ctypes.c_char_p,
            ctypes.c_uint,
        )
        rename_exchange.restype = ctypes.c_int
        result = rename_exchange(
            -100,
            left_bytes,
            -100,
            right_bytes,
            2,
        )
    elif sys.platform == "darwin":
        try:
            rename_exchange = library.renamex_np
        except AttributeError as error:
            raise OSError(
                errno.ENOSYS,
                "atomic directory exchange is unavailable",
                left,
            ) from error
        rename_exchange.argtypes = (
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.c_uint,
        )
        rename_exchange.restype = ctypes.c_int
        result = rename_exchange(left_bytes, right_bytes, 2)
    else:
        raise OSError(
            errno.ENOTSUP,
            "atomic directory exchange is unsupported on this platform",
            left,
        )
    if result != 0:
        error_number = ctypes.get_errno()
        raise OSError(
            error_number,
            os.strerror(error_number),
            left,
            right,
        )


def _discard_path(path: Path) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return
    try:
        if stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode):
            shutil.rmtree(path)
        else:
            path.unlink()
    except OSError:
        pass


def _replace_tree(stage: Path, destination: Path) -> None:
    if _destination_state(destination) == "missing":
        os.replace(stage, destination)
        try:
            _fsync_directory(destination.parent)
        except BaseException as commit_error:
            try:
                os.replace(destination, stage)
            except BaseException as rollback_error:
                raise _RollbackError(
                    errno.EIO,
                    "newly committed product retained for recovery at "
                    f"{destination} after commit durability failure "
                    f"({commit_error}) and rollback failure",
                    destination,
                ) from rollback_error
            try:
                _fsync_directory(destination.parent)
            except OSError:
                pass
            raise
        return

    _exchange_paths(stage, destination)
    try:
        _fsync_directory(destination.parent)
    except BaseException:
        try:
            _exchange_paths(stage, destination)
        except BaseException as rollback_error:
            raise _RollbackError(
                errno.EIO,
                "atomic exchange rollback failed; previous tree retained "
                f"for recovery at {stage}",
                destination,
            ) from rollback_error
        try:
            _fsync_directory(destination.parent)
        except OSError:
            pass
        raise
    _discard_path(stage)


def write_product(
    files: tuple[RenderedFile, ...],
    destination: Path,
    *,
    check: bool,
) -> WriteResult:
    """Compare or atomically replace one generated product tree."""
    destination = Path(destination)
    if destination == destination.parent or not destination.name:
        raise ValueError("generated destination must name a product directory")
    expected = _prepare_files(files)
    destination = _canonical_destination(destination)
    _assert_safe_ancestors(destination)
    result = _compare(expected, destination)
    if check or (not result.changed and not result.stale):
        return result

    _create_directory_chain(destination.parent)
    _assert_safe_ancestors(destination)
    stage = _make_stage(expected, destination)
    preserve_stage = False
    try:
        _assert_safe_ancestors(destination)
        _replace_tree(stage, destination)
    except _RollbackError:
        preserve_stage = True
        raise
    finally:
        if not preserve_stage:
            _discard_path(stage)
    return result


__all__ = ["WriteResult", "write_product"]
