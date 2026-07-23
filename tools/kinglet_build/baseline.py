"""Git-tree checks for human-owned migration baseline anchors."""

import hashlib
from collections.abc import Mapping, Sequence
from pathlib import Path
import re
import subprocess


_FULL_OBJECT_ID = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")


def _git(repository_root: Path, *arguments: str) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["git", *arguments],
        cwd=repository_root,
        check=False,
        capture_output=True,
    )


def _commit_label(source_commit: object) -> str:
    if isinstance(source_commit, str) and source_commit:
        return source_commit
    return repr(source_commit)


def source_commit_errors(
    repository_root: Path,
    source_commit: object,
    records: Sequence[Mapping[str, str]],
) -> list[str]:
    """Return deterministic baseline errors for records anchored at a Git commit."""
    root = Path(repository_root)
    label = _commit_label(source_commit)
    if not isinstance(source_commit, str) or not source_commit:
        return [f"source_commit is not a Git commit: {label}"]
    if _FULL_OBJECT_ID.fullmatch(source_commit) is None:
        return [
            "source_commit must be a full lowercase Git object ID: "
            f"{source_commit}"
        ]

    resolved = _git(root, "rev-parse", "--verify", "--quiet", f"{source_commit}^{{commit}}")
    if resolved.returncode != 0:
        return [f"source_commit is not a Git commit: {label}"]
    commit = resolved.stdout.decode("ascii").strip()

    ancestor = _git(root, "merge-base", "--is-ancestor", commit, "HEAD")
    if ancestor.returncode != 0:
        return [f"source_commit is not an ancestor of HEAD: {label}"]

    tree = _git(root, "ls-tree", "-r", "-z", commit)
    if tree.returncode != 0:
        return [f"source_commit tree cannot be read: {label}"]
    entries: dict[str, tuple[str, str, str]] = {}
    for raw_entry in tree.stdout.split(b"\0"):
        if not raw_entry:
            continue
        metadata, raw_path = raw_entry.split(b"\t", 1)
        mode, object_type, object_id = metadata.decode("ascii").split()
        path = raw_path.decode("utf-8", errors="surrogateescape")
        entries[path] = (mode, object_type, object_id)

    errors: list[str] = []
    object_sha256: dict[str, str] = {}
    for record in sorted(records, key=lambda item: item["path"]):
        path = record["path"]
        entry = entries.get(path)
        if entry is None:
            errors.append(f"source_commit missing path: {path}")
            continue
        mode, object_type, object_id = entry
        if object_type != "blob":
            errors.append(f"source_commit path is not a blob: {path}")
            continue
        actual_sha256 = object_sha256.get(object_id)
        if actual_sha256 is None:
            blob = _git(root, "cat-file", "blob", object_id)
            if blob.returncode != 0:
                errors.append(f"source_commit blob cannot be read: {path}")
                continue
            actual_sha256 = hashlib.sha256(blob.stdout).hexdigest()
            object_sha256[object_id] = actual_sha256
        if actual_sha256 != record["sha256"]:
            errors.append(f"source_commit sha256 mismatch: {path}")
        if mode != record["git_mode"]:
            errors.append(
                f"source_commit git mode mismatch: {path} "
                f"(expected {record['git_mode']}, got {mode})"
            )
    return errors


__all__ = ["source_commit_errors"]
