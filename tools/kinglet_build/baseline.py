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
class BaselineRemoval:
    path: str
    structure: str  # "full_claude_tree" or "categories.<name>"


@dataclass(frozen=True)
class BaselineAddition:
    path: str
    structure: str
    sha256: str
    git_mode: str


@dataclass(frozen=True)
class RegenerationPlan:
    anchor: str
    changes: tuple[BaselineChange, ...]
    refusals: tuple[str, ...]
    removals: tuple[BaselineRemoval, ...] = ()
    additions: tuple[BaselineAddition, ...] = ()

    @property
    def approved(self) -> bool:
        return not self.refusals


def category_paths(category: str, paths: Sequence[str]) -> list[str]:
    """Return the sorted subset of `paths` belonging to `category`.

    This is the single definition of the seven-category mapping used by
    both the regeneration planner (for additions) and the baseline
    inventory tests (for the legacy per-category drift check). Keeping
    one definition means the two never drift apart.
    """
    if category == "agents":
        selected = [path for path in paths if path.startswith(".claude/agents/")]
    elif category == "commands":
        selected = [path for path in paths if path.startswith(".claude/commands/")]
    elif category == "skills":
        selected = [
            path
            for path in paths
            if path.startswith(".claude/skills/") and path.endswith("/SKILL.md")
        ]
    elif category == "hooks":
        selected = [
            path
            for path in paths
            if path.startswith(".claude/hooks/")
            and path != ".claude/hooks/_lib.sh"
        ]
    elif category == "rules":
        selected = [path for path in paths if path.startswith(".claude/rules/")]
    elif category == "claude_templates":
        selected = [
            path
            for path in paths
            if path.startswith(".claude/templates/") and path.endswith(".md")
        ]
    elif category == "code_templates":
        selected = [path for path in paths if path.startswith("templates/")]
    else:
        raise ValueError(f"unknown inventory category: {category}")
    return sorted(selected)


_KNOWN_CATEGORIES = (
    "agents",
    "commands",
    "skills",
    "hooks",
    "rules",
    "claude_templates",
    "code_templates",
)


def _category_for_path(path: str) -> str | None:
    for category in _KNOWN_CATEGORIES:
        if category_paths(category, [path]):
            return category
    return None


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
    expected_removed: int | None = None,
    expected_added: int | None = None,
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
    removals: list[BaselineRemoval] = []
    for structure_name, record in to_check:
        path = record["path"]
        entry = entries.get(path)
        if entry is None:
            if expected_removed is not None:
                removals.append(BaselineRemoval(path=path, structure=structure_name))
            else:
                refusals.append(f"path missing at anchor: {path}")
            continue
        mode, object_type, object_id = entry
        if object_type != "blob":
            refusals.append(f"path is not a blob at anchor: {path}")
            continue
        actual_sha256 = blob_sha256(object_id)
        if actual_sha256 is None:
            if expected_removed is not None:
                removals.append(BaselineRemoval(path=path, structure=structure_name))
            else:
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

    additions: list[BaselineAddition] = []
    recorded_full_tree_paths = {record["path"] for record in full_tree_records}
    recorded_category_paths: dict[str, set[str]] = {
        category_name: {
            record["path"]
            for record in (categories[category_name] or {}).get("files") or []
        }
        for category_name in categories
    }
    for path in sorted(entries):
        mode, object_type, object_id = entries[path]
        if object_type != "blob":
            continue
        category = _category_for_path(path)
        # In scope for the addition scan: either it lives under the fully
        # enumerated .claude tree, or it maps to a category the baseline
        # tracks outside .claude/ (code_templates, under templates/).
        # Hardcoding ".claude/" alone misses those — see Important-2.
        if not path.startswith(".claude/") and category is None:
            continue
        recorded = path in recorded_full_tree_paths or (
            category is not None
            and path in recorded_category_paths.get(category, set())
        )
        if recorded:
            continue
        if expected_added is not None:
            actual_sha256 = blob_sha256(object_id)
            if actual_sha256 is None:
                refusals.append(f"addition blob cannot be read at anchor: {path}")
                continue
            # full_claude_tree only ever enumerates the .claude tree — a new
            # templates/ path (code_templates) is recorded in its category
            # only, never in full_claude_tree.
            if path.startswith(".claude/"):
                additions.append(
                    BaselineAddition(
                        path=path,
                        structure="full_claude_tree",
                        sha256=actual_sha256,
                        git_mode=mode,
                    )
                )
            if category is not None:
                additions.append(
                    BaselineAddition(
                        path=path,
                        structure=f"categories.{category}",
                        sha256=actual_sha256,
                        git_mode=mode,
                    )
                )
        elif path.startswith(".claude/"):
            refusals.append(f"unrecorded .claude path at anchor: {path}")
        else:
            refusals.append(f"unrecorded path at anchor: {path}")

    changes.sort(key=lambda change: (change.structure, change.path))
    removals.sort(key=lambda removal: (removal.structure, removal.path))
    additions.sort(key=lambda addition: (addition.structure, addition.path))

    if expected_drift is not None and expected_drift != len(changes):
        refusals.append(f"expected drift {expected_drift}, found {len(changes)}")
    if expected_removed is not None and expected_removed != len(removals):
        refusals.append(f"expected removed {expected_removed}, found {len(removals)}")
    if expected_added is not None and expected_added != len(additions):
        refusals.append(f"expected added {expected_added}, found {len(additions)}")

    return RegenerationPlan(
        anchor=commit,
        changes=tuple(changes),
        refusals=tuple(refusals),
        removals=tuple(removals),
        additions=tuple(additions),
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

    removals_by_structure: dict[str, set[str]] = {}
    for removal in plan.removals:
        removals_by_structure.setdefault(removal.structure, set()).add(removal.path)

    additions_by_structure: dict[str, list[BaselineAddition]] = {}
    for addition in plan.additions:
        additions_by_structure.setdefault(addition.structure, []).append(addition)

    touched_structures = (
        set(changes_by_structure) | set(removals_by_structure) | set(additions_by_structure)
    )

    def structure_container(structure_name: str) -> dict:
        if structure_name == "full_claude_tree":
            return document["full_claude_tree"]
        category_name = structure_name.split(".", 1)[1]
        category_container = (document.get("categories") or {}).get(category_name)
        if category_container is None:
            raise ValueError(
                "apply_regeneration: baseline has no category to receive an "
                f"addition: {category_name}"
            )
        return category_container

    for structure_name in touched_structures:
        container = structure_container(structure_name)
        records: list[dict] = container["files"]
        # Invariant on the way in, not the way out: a record list that
        # arrives unsorted is a real bug in the baseline document, and this
        # is where it would first become visible.
        assert records == sorted(records, key=lambda record: record["path"]), (
            f"baseline structure arrived unsorted: {structure_name}"
        )
        changes_by_path = changes_by_structure.get(structure_name, {})
        removed_paths = removals_by_structure.get(structure_name, set())

        updated_records: list[dict] = []
        for record in records:
            if record["path"] in removed_paths:
                continue
            change = changes_by_path.get(record["path"])
            if change is not None:
                record = dict(record)
                record["sha256"] = change.new_sha256
                record["git_mode"] = change.new_git_mode
            updated_records.append(record)

        for addition in additions_by_structure.get(structure_name, []):
            updated_records.append(
                {
                    "path": addition.path,
                    "sha256": addition.sha256,
                    "git_mode": addition.git_mode,
                }
            )

        updated_records.sort(key=lambda record: record["path"])

        container["files"] = updated_records
        container["expected_count"] = len(updated_records)

    document["source_commit"] = plan.anchor
    return document


__all__ = [
    "BaselineAddition",
    "BaselineChange",
    "BaselineRemoval",
    "RegenerationPlan",
    "apply_regeneration",
    "category_paths",
    "regeneration_plan",
    "source_commit_errors",
]
