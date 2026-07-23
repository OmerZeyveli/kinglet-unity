"""Deterministic redaction for the tiny textual evidence publish subset."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from tools.kinglet_spike.model import EvidenceError


ALLOWED_MEDIA_TYPES = frozenset(
    {"application/json", "application/xml", "text/plain", "text/markdown"}
)
SECRET_PATTERNS = (
    re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"sk-[A-Za-z0-9_-]{20,}"),
    re.compile(r"(?i)(token|password|secret)=\S+"),
    re.compile(r"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"),
)
ABSOLUTE_PATH_PATTERNS = (
    re.compile(r"(?i)(?:(?<![A-Za-z0-9])[a-z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+[\\/])"),
    re.compile(r"(?<![:/A-Za-z0-9_.-])/(?!/)(?:[^\s\"']+/?)+"),
)


def _normalise_text(source: Path, media_type: str) -> str:
    try:
        value = source.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise EvidenceError("E_JSON", f"{source} is not UTF-8 text") from error
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    if media_type == "application/json":
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError as error:
            raise EvidenceError("E_JSON", f"{source} is not valid JSON") from error
        return json.dumps(parsed, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    return value if value.endswith("\n") else value + "\n"


def _redact_roots(value: str, roots: tuple[str, ...]) -> str:
    for root in roots:
        if not Path(root).is_absolute() and not re.match(r"(?i)^[a-z]:[\\/]", root):
            raise EvidenceError("E_PATH", f"redaction root is not absolute: {root}")
        value = value.replace(root.replace("/", "\\"), "<redacted-root>")
        value = value.replace(root.replace("\\", "/"), "<redacted-root>")
        value = value.replace(root, "<redacted-root>")
    return value


def _reject_sensitive(value: str) -> None:
    for pattern in SECRET_PATTERNS:
        if pattern.search(value):
            raise EvidenceError("E_SECRET", "published artifact contains a credential")
    for pattern in ABSOLUTE_PATH_PATTERNS:
        if pattern.search(value):
            raise EvidenceError("E_PATH", "published artifact contains an absolute path")


def redact_artifact(
    source: Path, target: Path, media_type: str, declared_roots: tuple[str, ...]
) -> str:
    """Publish a sanitized text artifact by exclusive create and return its SHA-256."""
    if media_type not in ALLOWED_MEDIA_TYPES:
        raise EvidenceError("E_ENUM", f"unsupported published media type: {media_type}")
    value = _redact_roots(_normalise_text(source, media_type), declared_roots)
    _reject_sensitive(value)
    data = value.encode("utf-8")
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        with target.open("xb") as output:
            output.write(data)
    except FileExistsError as error:
        raise EvidenceError("E_IMMUTABLE", f"published artifact already exists: {target}") from error
    return hashlib.sha256(data).hexdigest()
