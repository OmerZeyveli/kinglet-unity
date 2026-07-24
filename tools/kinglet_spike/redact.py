from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PureWindowsPath

from .model import EvidenceError
from .validate import SECRET_PATTERNS, SENSITIVE_PATH_PATTERNS, TEXT_MEDIA_TYPES


def _is_absolute_root(value: str) -> bool:
    return Path(value).is_absolute() or PureWindowsPath(value).is_absolute()


def _replace_roots(value: object, roots: tuple[str, ...]) -> object:
    if isinstance(value, str):
        for root in roots:
            value = value.replace(root, "<redacted-root>")
        return value
    if isinstance(value, list):
        return [_replace_roots(item, roots) for item in value]
    if isinstance(value, dict):
        return {
            key: _replace_roots(item, roots)
            for key, item in sorted(value.items())
        }
    return value


def _string_values(value: object):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from _string_values(key)
            yield from _string_values(item)
    elif isinstance(value, list):
        for item in value:
            yield from _string_values(item)


def _reject_sensitive(value: object) -> None:
    strings = tuple(_string_values(value))
    for pattern in SECRET_PATTERNS:
        if any(pattern.search(text) for text in strings):
            raise EvidenceError("E_SECRET", "artifact contains a credential-like value")
    for pattern in SENSITIVE_PATH_PATTERNS:
        if any(pattern.search(text) for text in strings):
            raise EvidenceError("E_PATH", "artifact contains an absolute user path")


def _exclusive_write(target: Path, payload: bytes) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    except FileExistsError as error:
        raise EvidenceError("E_IMMUTABLE", f"target already exists: {target}") from error
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
    except Exception:
        target.unlink(missing_ok=True)
        raise


def redact_artifact(
    source: Path,
    target: Path,
    media_type: str,
    forbidden_roots: tuple[str, ...],
) -> str:
    if source.is_symlink():
        raise EvidenceError("E_SYMLINK", f"artifact source is a symlink: {source}")
    if media_type not in TEXT_MEDIA_TYPES:
        raise EvidenceError("E_ENUM", f"unsupported artifact media type: {media_type}")
    for root in forbidden_roots:
        if not _is_absolute_root(root):
            raise EvidenceError("E_PATH", f"redaction root must be absolute: {root}")
    try:
        text = source.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise EvidenceError("E_JSON", f"cannot read UTF-8 artifact: {source}") from error
    text = text.replace("\r\n", "\n").replace("\r", "\n")

    if media_type == "application/json":
        try:
            value = json.loads(text)
        except json.JSONDecodeError as error:
            raise EvidenceError("E_JSON", f"invalid JSON artifact: {source}") from error
        redacted = _replace_roots(value, forbidden_roots)
        _reject_sensitive(redacted)
        published = json.dumps(
            redacted,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        ) + "\n"
    else:
        published = text
        for root in forbidden_roots:
            published = published.replace(root, "<redacted-root>")
        if not published.endswith("\n"):
            published += "\n"
        _reject_sensitive(published)

    payload = published.encode("utf-8")
    _exclusive_write(target, payload)
    return hashlib.sha256(payload).hexdigest()
