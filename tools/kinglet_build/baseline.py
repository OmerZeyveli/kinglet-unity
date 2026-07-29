"""Git-tree checks for human-owned migration baseline anchors.

This module also plans and applies regeneration of the migration baseline
document (see ``regeneration_plan`` and ``apply_regeneration``). The gate
those two functions enforce makes the *path set* of the baseline immutable
without a deliberate act, and forces the caller to name the number of files
they expect to have drifted before anything is written. It does **not**,
and cannot, tell an intended content edit from an unintended one — that
distinction is not recoverable from bytes alone. Treat an approved plan as
proof the path set and the drift count matched the caller's expectation,
not as proof the content changes themselves are correct.
"""

import copy
import hashlib
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
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


@dataclass(frozen=True)
class BaselineChange:
    path: str
    structure: str  # "full_claude_tree" or "categories.<name>"
    old_sha256: str
    new_sha256: str
    old_git_mode: str
    new_git_mode: str


@dataclass(frozen=True)
class RegenerationPlan:
    anchor: str
    changes: tuple[BaselineChange, ...]
    refusals: tuple[str, ...]

    @property
    def approved(self) -> bool:
        return not self.refusals


def _structure_records(
    structure_name: str, records: object
) -> list[tuple[str, Mapping]]:
    if not isinstance(records, Sequence):
        return []
    return [(structure_name, record) for record in records]


def regeneration_plan(
    repository_root: Path,
    anchor: str,
    baseline: Mapping,
    *,
    expected_drift: int | None = None,
) -> RegenerationPlan:
    """Read Git and the baseline document and return a regeneration decision.

    This function only reads. It never writes the baseline document or any
    other file — the caller (the CLI) is the only thing permitted to write,
    and only once handed an approved plan.
    """
    root = Path(repository_root)
    label = anchor if isinstance(anchor, str) else repr(anchor)

    resolved = _git(root, "rev-parse", "--verify", "--quiet", f"{anchor}^{{commit}}")
    if resolved.returncode != 0:
        return RegenerationPlan(
            anchor=label,
            changes=(),
            refusals=(f"anchor is not a commit: {label}",),
        )
    commit = resolved.stdout.decode("ascii").strip()

    ancestor = _git(root, "merge-base", "--is-ancestor", commit, "HEAD")
    if ancestor.returncode != 0:
        return RegenerationPlan(
            anchor=commit,
            changes=(),
            refusals=(f"anchor is not an ancestor of HEAD: {label}",),
        )

    tree = _git(root, "ls-tree", "-r", "-z", commit)
    if tree.returncode != 0:
        return RegenerationPlan(
            anchor=commit,
            changes=(),
            refusals=(f"anchor tree cannot be read: {label}",),
        )

    entries: dict[str, tuple[str, str, str]] = {}
    for raw_entry in tree.stdout.split(b"\0"):
        if not raw_entry:
            continue
        metadata, raw_path = raw_entry.split(b"\t", 1)
        mode, object_type, object_id = metadata.decode("ascii").split()
        path = raw_path.decode("utf-8", errors="surrogateescape")
        entries[path] = (mode, object_type, object_id)

    object_sha256: dict[str, str] = {}

    def blob_sha256(object_id: str) -> str | None:
        cached = object_sha256.get(object_id)
        if cached is not None:
            return cached
        blob = _git(root, "cat-file", "blob", object_id)
        if blob.returncode != 0:
            return None
        digest = hashlib.sha256(blob.stdout).hexdigest()
        object_sha256[object_id] = digest
        return digest

    full_tree = baseline.get("full_claude_tree") or {}
    full_tree_records = list(full_tree.get("files") or [])
    to_check: list[tuple[str, Mapping]] = _structure_records(
        "full_claude_tree", full_tree_records
    )
    categories = baseline.get("categories") or {}
    for category_name in sorted(categories):
        category_records = (categories[category_name] or {}).get("files") or []
        to_check.extend(
            _structure_records(f"categories.{category_name}", category_records)
        )

    refusals: list[str] = []
    changes: list[BaselineChange] = []
    for structure_name, record in to_check:
        path = record["path"]
        entry = entries.get(path)
        if entry is None:
            refusals.append(f"path missing at anchor: {path}")
            continue
        mode, object_type, object_id = entry
        if object_type != "blob":
            refusals.append(f"path is not a blob at anchor: {path}")
            continue
        actual_sha256 = blob_sha256(object_id)
        if actual_sha256 is None:
            refusals.append(f"path missing at anchor: {path}")
            continue
        if actual_sha256 != record["sha256"] or mode != record["git_mode"]:
            changes.append(
                BaselineChange(
                    path=path,
                    structure=structure_name,
                    old_sha256=record["sha256"],
                    new_sha256=actual_sha256,
                    old_git_mode=record["git_mode"],
                    new_git_mode=mode,
                )
            )

    recorded_full_tree_paths = {record["path"] for record in full_tree_records}
    for path in sorted(entries):
        mode, object_type, _object_id = entries[path]
        if object_type != "blob":
            continue
        if not path.startswith(".claude/"):
            continue
        if path not in recorded_full_tree_paths:
            refusals.append(f"unrecorded .claude path at anchor: {path}")

    changes.sort(key=lambda change: (change.structure, change.path))

    if expected_drift is not None and expected_drift != len(changes):
        refusals.append(f"expected drift {expected_drift}, found {len(changes)}")

    return RegenerationPlan(
        anchor=commit,
        changes=tuple(changes),
        refusals=tuple(refusals),
    )


def apply_regeneration(baseline: Mapping, plan: RegenerationPlan) -> dict:
    """Return a new baseline document with `plan`'s changes applied.

    Raises `ValueError` if `plan` is not approved. Does not write to disk —
    the CLI does the writing, and only after building an approved plan.
    """
    if not plan.approved:
        raise ValueError(
            "cannot apply an unapproved regeneration plan: "
            + "; ".join(plan.refusals)
        )

    document = copy.deepcopy(dict(baseline))
    changes_by_structure: dict[str, dict[str, BaselineChange]] = {}
    for change in plan.changes:
        changes_by_structure.setdefault(change.structure, {})[change.path] = change

    def apply_to_records(records: list[dict], changes_by_path: dict[str, BaselineChange]) -> None:
        for record in records:
            change = changes_by_path.get(record["path"])
            if change is not None:
                record["sha256"] = change.new_sha256
                record["git_mode"] = change.new_git_mode

    full_tree_changes = changes_by_structure.get("full_claude_tree")
    if full_tree_changes:
        apply_to_records(document["full_claude_tree"]["files"], full_tree_changes)

    for structure_name, changes_by_path in changes_by_structure.items():
        if structure_name == "full_claude_tree":
            continue
        category_name = structure_name.split(".", 1)[1]
        apply_to_records(
            document["categories"][category_name]["files"], changes_by_path
        )

    document["source_commit"] = plan.anchor
    return document


__all__ = [
    "BaselineChange",
    "RegenerationPlan",
    "apply_regeneration",
    "regeneration_plan",
    "source_commit_errors",
]
