"""isolation.py -- Proving one Unity workspace is physically separate from another.

Why this module exists
----------------------
The plan states the isolated route's licence in one sentence:

    "Isolated headless may run while the main Editor is open only from a
    separate physical copy with separate Library, Temp, logs, lease, and
    outputs."

and its lease rule in another:

    "One mutating execution lease exists per physical workspace; a lease never
    spans main and isolated copies as if they were the same physical workspace."

Both are claims about PHYSICAL identity, and neither is provable from a path
string. Two different strings routinely name one directory (a symlinked
parent, a bind mount, `..` segments, case folding on Windows/macOS), and one
string can name two directories across a remount. So this module never decides
separateness by comparing spellings. `assert_isolated` compares canonical
paths AND `(st_dev, st_ino)`, because `realpath` resolves symlinks but cannot
see through a bind mount -- `mount --bind main iso` gives two distinct
canonical paths for one physical directory, and a purely lexical check would
call that isolated.

The refusal branch is the point, not the happy path
---------------------------------------------------
Task 3's defect, repeated in Task 6, was a safety function with no "I could
not tell" outcome: everything it failed to resolve fell through to the
permissive answer by construction. Here that failure mode would be silent and
expensive -- it would authorise a headless Unity to import, compile and write
generated state into the project a developer has open, which is exactly the
`Library` corruption the whole route exists to avoid.

So every path through `assert_isolated` that does not END in a positive,
observed proof of separateness raises `E_UNITY_NOT_ISOLATED`. A directory it
cannot `stat` is not isolated. A destination that does not exist is not
isolated. A `Library` under the copy that resolves back under the main project
is not isolated. There is no branch that returns normally without having
compared two successful `stat` results.

Copy by whitelist, never by exclusion
-------------------------------------
`prepare_isolated_copy` copies exactly `Assets`, `Packages` and
`ProjectSettings`, and nothing else. That is deliberate: an exclusion list
("copy everything except Library/Temp/Logs") is wrong the day Unity adds a
generated directory, and wrong today for `obj/`, `Builds/`, `.vs/`,
`UserSettings/` and every stray file a developer left in the project root. A
whitelist fails closed -- an unknown directory is simply not copied.

This is also the entire mechanism behind "never imports the unsaved state of
the open Editor". Unsaved state is, by definition, state that is NOT on disk:
a scene edited but not saved lives in the running Editor's memory and in its
`Library`/`Temp` scratch, never in the committed `Assets` bytes. A copy taken
from disk of the three committed trees can only ever contain SAVED state.
There is no filter that achieves this; the tree selection is the guarantee.

Symlinks
--------
A symlink whose target resolves OUTSIDE the source is refused outright
(`E_UNITY_ISOLATION_SYMLINK`): copying it would hand the isolated Unity a door
straight back into whatever it points at, which on a real developer machine is
frequently the main project. A symlink whose target stays inside the source is
MATERIALIZED -- its content is copied as a regular file or directory -- so the
finished copy contains no symlinks at all and its containment does not have to
be re-proved for the life of the run. Loops are detected by canonical path and
refused rather than followed.
"""
from __future__ import annotations

import hashlib
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence

from ..model import EvidenceError
from .lease import physical_path_hash

__all__ = (
    "ISOLATION_MANIFEST_SCHEMA",
    "COPIED_TREES",
    "GENERATED_TREES",
    "CopiedFile",
    "IsolationBoundary",
    "IsolationManifest",
    "WORKSPACE_IDENTITY_DOMAIN",
    "workspace_identity",
    "assert_isolated",
    "assert_manifest_self_consistent",
    "inventory_copy",
    "isolation_manifest_from_dict",
    "manifest_for_copy",
    "prepare_isolated_copy",
    "verify_manifest",
    "manifest_to_dict",
)

ISOLATION_MANIFEST_SCHEMA: str = "kinglet.unity-probe.isolation-manifest/v1"

# Domain separation for the workspace identity digest, so a `(st_dev, st_ino)`
# digest can never be confused with any other SHA-256 in this plan.
WORKSPACE_IDENTITY_DOMAIN: str = "kinglet.unity-probe.workspace-identity/v1"

# The ONLY trees an isolated copy is made from. See the module docstring for
# why this is a whitelist and why that whitelist is the unsaved-state
# guarantee rather than merely a size optimisation.
COPIED_TREES: tuple[str, ...] = ("Assets", "Packages", "ProjectSettings")

# Trees Unity (or a build) generates. NOT an exclusion list for the copy --
# the whitelist above already excludes them and everything else. These are the
# names `assert_isolated` and the post-copy check look for, because each one
# is a place a copy could be secretly wired back into the main workspace.
GENERATED_TREES: tuple[str, ...] = ("Library", "Temp", "Logs")


@dataclass(frozen=True)
class CopiedFile:
    """One file in the isolated copy: its POSIX-relative path, size and digest."""

    path: str
    size: int
    sha256: str


def workspace_identity(dev: int, ino: int) -> str:
    """A publishable digest of one directory's `(st_dev, st_ino)`.

    Domain-separated and UNSALTED on purpose: a reader holding this artifact
    and the two directories must be able to recompute it and check it. A random
    salt would make the field unverifiable, which is the opposite of the point.

    It is a digest rather than the raw pair because the raw pair is host state
    that varies per machine and per remount, and a receipt-adjacent artifact
    that changes every time a disk is remounted invites people to stop reading
    it. The digest is stable for as long as the directory is, which is the
    window in which the claim means anything.
    """
    return hashlib.sha256(
        f"{WORKSPACE_IDENTITY_DOMAIN}\0{dev}\0{ino}".encode("utf-8")
    ).hexdigest()


@dataclass(frozen=True)
class IsolationBoundary:
    """A PROVEN separation between two physical workspaces.

    Only `assert_isolated` constructs one, and only after two successful
    `stat` calls that disagreed. Holding one of these is the evidence that
    the two workspaces are not the same directory under two names -- and the
    two path hashes are the same values `lease.lease_path_for` keys on, so
    `main_path_hash != isolated_path_hash` IS the plan's "a lease never spans
    main and isolated copies" stated in the lease's own vocabulary.

    `main_identity` and `isolated_identity` digest the `(st_dev, st_ino)` pair
    that step 4 actually compared. They are carried out of this function
    BECAUSE the path hashes cannot stand in for them: a bind mount presents one
    directory under two canonical paths, so it produces two DIFFERENT path
    hashes and one IDENTICAL identity. Without these two fields the artifact a
    reader is told to check would validate the exact forgery `assert_isolated`
    exists to refuse.
    """

    main_path_hash: str
    isolated_path_hash: str
    main_identity: str
    isolated_identity: str


@dataclass(frozen=True)
class IsolationManifest:
    """What was copied, from which physical workspace, into which other one.

    `tree_sha256` digests the sorted `(path, sha256)` pairs, so it changes if
    a file is added, removed, renamed or edited. `verify_manifest` recomputes
    the whole inventory rather than trusting this field, and the field exists
    so a receipt-adjacent artifact can cite one short content identity for the
    copy instead of asking a reader to diff a file list.

    Only HASHES are recorded, never the two paths. This artifact is published
    next to a receipt, and the sanitization sweep rejects absolute machine
    paths -- the hashes carry the identity the lease already uses without
    carrying anybody's home directory.

    THE PATH HASHES ARE NOT SUFFICIENT, which is why `main_identity` and
    `isolated_identity` are here as well. Round-1 review found the asymmetry:
    the artifact a reader is told to check must carry the fact the decision
    rests on, and for a bind mount the path hashes DIFFER while the directory
    is one and the same. A manifest carrying only path hashes therefore
    validates cleanly for exactly the forgery `assert_isolated` step 4 exists
    to refuse. The identity digests come from that comparison, so the artifact
    now encodes the refusal instead of merely being consistent with it.
    """

    schema: str
    main_path_hash: str
    isolated_path_hash: str
    main_identity: str
    isolated_identity: str
    trees: tuple[str, ...]
    files: tuple[CopiedFile, ...]
    tree_sha256: str


def manifest_to_dict(manifest: IsolationManifest) -> dict:
    return {
        "schema": manifest.schema,
        "main_path_hash": manifest.main_path_hash,
        "isolated_path_hash": manifest.isolated_path_hash,
        "main_identity": manifest.main_identity,
        "isolated_identity": manifest.isolated_identity,
        "trees": list(manifest.trees),
        "files": [
            {"path": item.path, "size": item.size, "sha256": item.sha256}
            for item in manifest.files
        ],
        "tree_sha256": manifest.tree_sha256,
    }


# ---------------------------------------------------------------------------
# Reading a manifest back -- the auditor's direction
# ---------------------------------------------------------------------------
#
# `manifest_to_dict` writes the artifact; these read it. A reader auditing a
# published `isolated-headless` receipt has the JSON and nothing else -- not
# the two directories, not the boundary object -- so everything that can still
# be decided from the bytes must be decided here, and everything that cannot
# must be refused rather than assumed.

_MANIFEST_FIELDS = frozenset((
    "schema",
    "main_path_hash",
    "isolated_path_hash",
    "main_identity",
    "isolated_identity",
    "trees",
    "files",
    "tree_sha256",
))
_MANIFEST_FILE_FIELDS = frozenset(("path", "size", "sha256"))

# Every hash this artifact carries is a SHA-256 hexdigest. Two UNEQUAL strings
# are not two proven identities: without this, `main_identity="a"` and
# `isolated_identity="b"` satisfies every inequality below.
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def _manifest_refuse(detail: str) -> "EvidenceError":
    return EvidenceError("E_UNITY_ISOLATION_MANIFEST", detail)


def _manifest_digest_field(raw: dict, name: str) -> str:
    value = raw.get(name)
    if not isinstance(value, str) or not _SHA256_RE.fullmatch(value):
        raise _manifest_refuse(
            f"manifest {name} is not a SHA-256 hexdigest: {value!r}"
        )
    return value


def isolation_manifest_from_dict(value: object) -> IsolationManifest:
    """Strictly parse an isolation-manifest document. Raises EvidenceError.

    Structural only -- the claims the document makes are judged by
    `assert_manifest_self_consistent`, exactly as `unity_receipt_from_dict`
    and `validate_unity_receipt` split the receipt.
    """
    if not isinstance(value, dict):
        raise _manifest_refuse("an isolation manifest must be a JSON object")
    unknown = sorted(value.keys() - _MANIFEST_FIELDS)
    if unknown:
        raise _manifest_refuse(f"manifest.{unknown[0]} is an unknown field")
    missing = sorted(_MANIFEST_FIELDS - value.keys())
    if missing:
        raise _manifest_refuse(f"manifest is missing {missing[0]}")

    schema = value["schema"]
    if not isinstance(schema, str):
        raise _manifest_refuse("manifest.schema must be a string")

    trees = value["trees"]
    if not isinstance(trees, list) or not all(isinstance(item, str) for item in trees):
        raise _manifest_refuse("manifest.trees must be an array of strings")

    raw_files = value["files"]
    if not isinstance(raw_files, list):
        raise _manifest_refuse("manifest.files must be an array")
    files: list[CopiedFile] = []
    for index, item in enumerate(raw_files):
        if not isinstance(item, dict):
            raise _manifest_refuse(f"manifest.files[{index}] must be an object")
        extra = sorted(item.keys() - _MANIFEST_FILE_FIELDS)
        if extra:
            raise _manifest_refuse(
                f"manifest.files[{index}].{extra[0]} is an unknown field"
            )
        path = item.get("path")
        size = item.get("size")
        digest = item.get("sha256")
        if not isinstance(path, str) or not path:
            raise _manifest_refuse(f"manifest.files[{index}].path must be a string")
        if type(size) is not int or type(size) is bool or size < 0:
            raise _manifest_refuse(
                f"manifest.files[{index}].size must be a non-negative integer"
            )
        if not isinstance(digest, str) or not _SHA256_RE.fullmatch(digest):
            raise _manifest_refuse(
                f"manifest.files[{index}].sha256 is not a SHA-256 hexdigest"
            )
        files.append(CopiedFile(path=path, size=size, sha256=digest))

    return IsolationManifest(
        schema=schema,
        main_path_hash=_manifest_digest_field(value, "main_path_hash"),
        isolated_path_hash=_manifest_digest_field(value, "isolated_path_hash"),
        main_identity=_manifest_digest_field(value, "main_identity"),
        isolated_identity=_manifest_digest_field(value, "isolated_identity"),
        trees=tuple(trees),
        files=tuple(files),
        tree_sha256=_manifest_digest_field(value, "tree_sha256"),
    )


def assert_manifest_self_consistent(manifest: IsolationManifest) -> None:
    """Refuse unless the manifest's own contents describe an isolated copy.

    Everything decidable WITHOUT the two directories. `verify_manifest` runs
    this first and then re-walks the disk on top of it; an auditor holding
    only the published artifact runs this alone.
    """
    if manifest.schema != ISOLATION_MANIFEST_SCHEMA:
        raise _manifest_refuse(
            f"manifest declares schema {manifest.schema!r}, expected "
            f"{ISOLATION_MANIFEST_SCHEMA!r}"
        )
    for name, value in (
        ("main_path_hash", manifest.main_path_hash),
        ("isolated_path_hash", manifest.isolated_path_hash),
        ("main_identity", manifest.main_identity),
        ("isolated_identity", manifest.isolated_identity),
        ("tree_sha256", manifest.tree_sha256),
    ):
        if not _SHA256_RE.fullmatch(value):
            raise _manifest_refuse(
                f"manifest {name} is not a SHA-256 hexdigest: {value!r}"
            )
    if manifest.main_path_hash == manifest.isolated_path_hash:
        raise _manifest_refuse(
            "manifest records one lease identity for both the main and the "
            "isolated workspace; it does not describe an isolated copy"
        )
    # The check the path hashes CANNOT make. A bind mount gives two canonical
    # paths -- so two different path hashes -- for one directory, and the
    # clause above passes it. This one does not.
    if manifest.main_identity == manifest.isolated_identity:
        raise _manifest_refuse(
            "manifest records the same physical directory identity for the "
            "main and the isolated workspace; two canonical paths naming one "
            "directory is not isolation, whatever the path hashes say"
        )
    # A manifest that narrows its own scope narrows the verification of it:
    # `trees=()` used to walk nothing, match an empty `files`, digest to the
    # empty digest, and return success over any content whatsoever.
    if tuple(manifest.trees) != tuple(COPIED_TREES):
        raise _manifest_refuse(
            f"manifest declares trees {tuple(manifest.trees)!r}, but an "
            f"isolated copy is defined by {tuple(COPIED_TREES)!r}; a manifest "
            "that narrows its own scope narrows the verification of it"
        )
    if not manifest.files:
        raise _manifest_refuse(
            "manifest lists no files; an isolated copy of a Unity project is "
            "never empty, and an empty inventory verifies nothing"
        )
    recomputed = _tree_digest(manifest.files)
    if recomputed != manifest.tree_sha256:
        raise _manifest_refuse(
            f"manifest tree_sha256 is {manifest.tree_sha256!r} but its own "
            f"file list digests to {recomputed!r}"
        )


# ---------------------------------------------------------------------------
# Separateness
# ---------------------------------------------------------------------------

def _real(path) -> Path:
    return Path(os.path.realpath(os.fspath(path)))


def _refuse(detail: str) -> "EvidenceError":
    return EvidenceError("E_UNITY_NOT_ISOLATED", detail)


def _identity(path: Path, label: str, stat_reader) -> tuple[int, int]:
    """(st_dev, st_ino) for `path`, or refuse.

    An OSError here is the "I could not tell" case, and it resolves to a
    refusal rather than to a permissive default: a directory whose identity we
    cannot read is not a directory we can prove is separate from another one.
    """
    try:
        info = stat_reader(os.fspath(path))
    except OSError as error:
        raise _refuse(
            f"cannot stat the {label} workspace to establish its physical "
            f"identity: {error}"
        ) from error
    return (info.st_dev, info.st_ino)


def _contains(outer: Path, inner: Path) -> bool:
    return inner == outer or inner.is_relative_to(outer)


def assert_isolated(
    main_project,
    isolated_project,
    *,
    stat_reader: Callable[[str], os.stat_result] = os.stat,
) -> IsolationBoundary:
    """Prove that two directories are separate physical workspaces, or refuse.

    Returns an `IsolationBoundary` ONLY after every one of these held:

    1. both paths are existing directories;
    2. their canonical paths differ;
    3. neither canonical path contains the other (a copy nested inside the
       main project shares its `Library` scanning, its `.gitignore` semantics
       and, if it lands under `Assets/`, its importer);
    4. their `(st_dev, st_ino)` differ -- the check `realpath` cannot make.
       A bind mount presents one directory under two canonical paths, and
       steps 2 and 3 both pass for it;
    5. every generated tree present under the copy (`Library`, `Temp`,
       `Logs`) resolves UNDER the copy, and is not the same directory as the
       main project's tree of that name. A copy whose `Library` is a symlink
       to the main project's `Library` satisfies 1-4 and is the single most
       damaging shape this function exists to catch;
    6. the two physical-path hashes differ, i.e. the two workspaces get
       different lease files.

    `stat_reader` is the injectable seam that makes step 4 and its refusal
    branch executable from a test on a host where creating a bind mount needs
    root.
    """
    main_raw = os.fspath(main_project)
    isolated_raw = os.fspath(isolated_project)

    for raw, label in ((main_raw, "main"), (isolated_raw, "isolated")):
        if not os.path.isdir(raw):
            raise _refuse(
                f"the {label} workspace is not an existing directory, so its "
                "physical identity cannot be resolved"
            )

    main_real = _real(main_raw)
    isolated_real = _real(isolated_raw)

    if main_real == isolated_real:
        raise _refuse(
            "the main and isolated workspaces resolve to one canonical path; "
            "they are the same physical workspace"
        )
    if _contains(main_real, isolated_real):
        raise _refuse(
            "the isolated workspace lies inside the main workspace; a copy "
            "beneath the project it copies is not a separate workspace"
        )
    if _contains(isolated_real, main_real):
        raise _refuse(
            "the main workspace lies inside the isolated workspace; the copy "
            "would contain the project it is supposed to be isolated from"
        )

    main_identity = _identity(main_real, "main", stat_reader)
    isolated_identity = _identity(isolated_real, "isolated", stat_reader)
    if main_identity == isolated_identity:
        raise _refuse(
            "the main and isolated workspaces have the same (device, inode); "
            "two canonical paths naming one directory (a bind mount) is not "
            "isolation, and no comparison of path strings can see it"
        )

    for name in GENERATED_TREES:
        candidate = isolated_real / name
        if not os.path.lexists(candidate):
            continue
        candidate_real = _real(candidate)
        if not _contains(isolated_real, candidate_real):
            raise _refuse(
                f"the isolated workspace's {name} resolves outside the "
                "isolated workspace; its generated state would not be its own"
            )
        main_candidate = main_real / name
        if os.path.lexists(main_candidate):
            if _identity(candidate_real, f"isolated {name}", stat_reader) == _identity(
                _real(main_candidate), f"main {name}", stat_reader
            ):
                raise _refuse(
                    f"the isolated workspace's {name} is the same directory as "
                    f"the main workspace's {name}; the copy would write its "
                    "generated state into the open project"
                )

    main_hash = physical_path_hash(main_real)
    isolated_hash = physical_path_hash(isolated_real)
    if main_hash == isolated_hash:
        # Unreachable given the checks above; kept because it is the exact
        # invariant the lease depends on, and an unreachable assertion that
        # names its own guarantee is cheaper than discovering it was reachable.
        raise _refuse(
            "the main and isolated workspaces hash to one lease identity; a "
            "lease would span both as if they were one physical workspace"
        )

    return IsolationBoundary(
        main_path_hash=main_hash,
        isolated_path_hash=isolated_hash,
        # Carried out of the comparison that was actually made, not recomputed
        # later from a path -- a second stat could see a different directory.
        main_identity=workspace_identity(*main_identity),
        isolated_identity=workspace_identity(*isolated_identity),
    )


# ---------------------------------------------------------------------------
# The copy
# ---------------------------------------------------------------------------

def _sha256_file(path: Path) -> tuple[int, str]:
    digest = hashlib.sha256()
    size = 0
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            size += len(chunk)
            digest.update(chunk)
    return size, digest.hexdigest()


def _tree_digest(files: Sequence[CopiedFile]) -> str:
    digest = hashlib.sha256()
    for item in sorted(files, key=lambda entry: entry.path):
        digest.update(f"{item.path}\0{item.sha256}\n".encode("utf-8"))
    return digest.hexdigest()


def _copy_directory(
    source_dir: Path,
    dest_dir: Path,
    *,
    source_real: Path,
    relative: str,
    visited: set[Path],
    files: list[CopiedFile],
) -> None:
    dest_dir.mkdir(parents=True, exist_ok=True)
    with os.scandir(source_dir) as scanner:
        entries = sorted(scanner, key=lambda entry: entry.name)
    for entry in entries:
        entry_path = Path(entry.path)
        child_relative = f"{relative}/{entry.name}"

        if entry.is_symlink():
            target = _real(entry_path)
            if not os.path.exists(entry_path):
                raise EvidenceError(
                    "E_UNITY_ISOLATION_SYMLINK",
                    f"{child_relative} is a dangling symlink; an isolated copy "
                    "is not made from links whose target cannot be read",
                )
            if not _contains(source_real, target):
                raise EvidenceError(
                    "E_UNITY_ISOLATION_SYMLINK",
                    f"{child_relative} is a symlink escaping the source "
                    "workspace; copying it would give the isolated Unity a "
                    "path back out of its own copy",
                )

        if entry.is_dir(follow_symlinks=True):
            canonical = _real(entry_path)
            if canonical in visited:
                raise EvidenceError(
                    "E_UNITY_ISOLATION_SYMLINK",
                    f"{child_relative} resolves to a directory already being "
                    "copied; this is a link loop and it is refused, not "
                    "followed",
                )
            visited.add(canonical)
            _copy_directory(
                entry_path,
                dest_dir / entry.name,
                source_real=source_real,
                relative=child_relative,
                visited=visited,
                files=files,
            )
            continue

        if not entry.is_file(follow_symlinks=True):
            raise EvidenceError(
                "E_UNITY_ISOLATION_UNSUPPORTED",
                f"{child_relative} is neither a regular file nor a directory "
                "(fifo, socket or device); an isolated copy carries only the "
                "committed bytes of a project",
            )

        target_file = dest_dir / entry.name
        # copyfile, not copy2: content only. Mode, ownership and xattrs of the
        # open project are not part of what makes the copy a valid project,
        # and reproducing them is a second way for the copy to differ from
        # what the manifest says it is.
        with open(entry_path, "rb") as src, open(target_file, "wb") as dst:
            for chunk in iter(lambda: src.read(1 << 20), b""):
                dst.write(chunk)
        size, digest = _sha256_file(target_file)
        files.append(CopiedFile(path=child_relative, size=size, sha256=digest))


def inventory_copy(
    root, trees: Sequence[str] = COPIED_TREES
) -> tuple[CopiedFile, ...]:
    """Digest every regular file under `trees` in `root`, or refuse.

    Used to build a manifest and, in `verify_manifest`, to re-derive one from
    the bytes on disk rather than trusting a manifest handed in by a caller.
    A symlink found here is a refusal for the same reason it is during the
    copy: `prepare_isolated_copy` materializes every link it accepts, so a
    symlink in a finished copy means something other than that function put it
    there.
    """
    root = Path(root)
    files: list[CopiedFile] = []
    for tree in trees:
        tree_root = root / tree
        if not tree_root.is_dir():
            raise EvidenceError(
                "E_UNITY_ISOLATION_INCOMPLETE",
                f"{tree} is missing from the workspace at {tree_root.name}; a "
                "Unity project without it is not one this route can run",
            )
        for current, directory_names, file_names in os.walk(tree_root):
            directory_names.sort()
            current_path = Path(current)
            relative_dir = current_path.relative_to(root).as_posix()
            for name in sorted(directory_names) + sorted(file_names):
                candidate = current_path / name
                if candidate.is_symlink():
                    raise EvidenceError(
                        "E_UNITY_ISOLATION_SYMLINK",
                        f"{relative_dir}/{name} is a symlink; an isolated copy "
                        "contains materialized bytes only",
                    )
            for name in sorted(file_names):
                candidate = current_path / name
                size, digest = _sha256_file(candidate)
                files.append(CopiedFile(
                    path=candidate.relative_to(root).as_posix(),
                    size=size,
                    sha256=digest,
                ))
    return tuple(sorted(files, key=lambda item: item.path))


def manifest_for_copy(
    boundary: IsolationBoundary,
    isolated_project,
    *,
    trees: Sequence[str] = COPIED_TREES,
    files: Sequence[CopiedFile] | None = None,
) -> IsolationManifest:
    """Assemble a manifest for an already-proven boundary.

    Takes an `IsolationBoundary` rather than two paths on purpose: a manifest
    that names two workspace identities must not be constructible without the
    proof that those identities are actually distinct.
    """
    inventory = tuple(inventory_copy(isolated_project, trees)) if files is None else tuple(files)
    return IsolationManifest(
        schema=ISOLATION_MANIFEST_SCHEMA,
        main_path_hash=boundary.main_path_hash,
        isolated_path_hash=boundary.isolated_path_hash,
        main_identity=boundary.main_identity,
        isolated_identity=boundary.isolated_identity,
        trees=tuple(trees),
        files=inventory,
        tree_sha256=_tree_digest(inventory),
    )


def prepare_isolated_copy(
    source,
    destination,
    *,
    trees: Sequence[str] = COPIED_TREES,
    stat_reader: Callable[[str], os.stat_result] = os.stat,
) -> IsolationManifest:
    """Copy the committed trees of `source` into a fresh `destination`.

    Copies `Assets`, `Packages` and `ProjectSettings` and NOTHING else, so the
    copy carries no `Library`, no `Temp`, no `Logs`, no build output and none
    of the open Editor's unsaved or generated state -- see the module
    docstring, where that whitelist IS the guarantee rather than an
    optimisation.

    `destination` must not already hold anything. A pre-existing tree could
    carry generated state from an earlier run (or from an entirely different
    project), and the manifest returned here would then describe a workspace
    assembled partly by someone else.

    Creates no `Library`, `Temp`, log, results or lease path. Those belong to
    the isolated Unity process and to the route that launches it; creating
    them here would mean this function decides where the isolated run writes,
    which is the route's job and the route's evidence.
    """
    source_raw = os.fspath(source)
    if not os.path.isdir(source_raw):
        raise _refuse(
            "the source workspace is not an existing directory; there is "
            "nothing whose physical identity could be copied from"
        )
    source_real = _real(source_raw)
    destination_real = _real(destination)

    # Nesting is checked BEFORE anything is created: making the destination
    # first would already have written into the main project.
    if source_real == destination_real:
        raise _refuse(
            "the destination resolves to the source workspace; a project "
            "cannot be an isolated copy of itself"
        )
    if _contains(source_real, destination_real):
        raise _refuse(
            "the destination lies inside the source workspace; the copy would "
            "be written into the project it copies"
        )
    if _contains(destination_real, source_real):
        raise _refuse(
            "the source workspace lies inside the destination; the copy would "
            "contain the project it is supposed to be isolated from"
        )

    destination_path = Path(destination)
    if destination_path.exists():
        if not destination_path.is_dir():
            raise EvidenceError(
                "E_UNITY_ISOLATION_DESTINATION",
                "the destination exists and is not a directory",
            )
        if any(destination_path.iterdir()):
            raise EvidenceError(
                "E_UNITY_ISOLATION_DESTINATION",
                "the destination is not empty; an isolated copy is never "
                "merged into an existing tree, because whatever is already "
                "there is state this manifest cannot account for",
            )
    destination_path.mkdir(parents=True, exist_ok=True)

    for tree in trees:
        if not (source_real / tree).is_dir():
            raise EvidenceError(
                "E_UNITY_ISOLATION_INCOMPLETE",
                f"the source workspace has no {tree} directory; it is not a "
                "Unity project this route can copy",
            )

    # Separateness is proven against the destination that now EXISTS, so the
    # (device, inode) comparison is made on the real directories.
    boundary = assert_isolated(source_real, destination_path, stat_reader=stat_reader)

    files: list[CopiedFile] = []
    for tree in trees:
        _copy_directory(
            source_real / tree,
            destination_path / tree,
            source_real=source_real,
            relative=tree,
            visited={_real(source_real / tree)},
            files=files,
        )

    # Post-conditions, checked rather than assumed. Each one is a claim the
    # manifest is about to make on this function's behalf.
    for name in GENERATED_TREES:
        if os.path.lexists(destination_path / name):
            raise EvidenceError(
                "E_UNITY_ISOLATION_LEAK",
                f"the finished copy contains {name}; the copy is made from a "
                "whitelist that cannot produce it, so something else did",
            )
    for current, directory_names, file_names in os.walk(destination_path):
        for name in directory_names + file_names:
            if (Path(current) / name).is_symlink():
                raise EvidenceError(
                    "E_UNITY_ISOLATION_LEAK",
                    "the finished copy contains a symlink; every accepted link "
                    "is materialized, so the copy must contain none",
                )

    manifest = manifest_for_copy(
        boundary, destination_path, trees=trees, files=tuple(files)
    )
    # Re-derive from what is actually on disk. `files` is what the copier
    # believes it wrote; this is what a reader would find. If those disagree
    # the manifest is not evidence about the copy.
    verify_manifest(destination_path, manifest)
    return manifest


def verify_manifest(isolated_project, manifest: IsolationManifest) -> None:
    """Refuse unless `isolated_project` on disk is exactly what `manifest` says.

    The manifest is the isolated route's only receipt-citable evidence that a
    separate physical copy existed at all, so a caller handing one in must not
    be taken at its word. This re-walks the trees and compares every path,
    size and digest, then the aggregate `tree_sha256`.
    """
    # Everything decidable from the document alone -- schema, digest shapes,
    # distinct path hashes, distinct physical identities, the frozen tree list,
    # a non-empty inventory, and a tree_sha256 that matches that inventory --
    # lives in ONE place, because a reader auditing the published artifact runs
    # exactly those rules with no disk to walk. Keeping a second copy here is
    # how the two drift.
    #
    # The manifest's OWN `trees` used to decide what gets verified, which made
    # verification a claim the thing being verified was allowed to make about
    # itself: `trees=()` walked nothing, matched an empty `files`, digested to
    # the empty digest, and returned success over any content whatsoever.
    assert_manifest_self_consistent(manifest)
    # COPIED_TREES and not `manifest.trees`, even though the guard above has
    # just proved them equal. The equality is what makes this line redundant
    # TODAY; naming the frozen constant is what keeps it correct if that guard
    # is ever relaxed. (Mutating this line back to `manifest.trees` therefore
    # survives the suite, which is expected and is why the refusal above is
    # the tested guard.)
    observed = inventory_copy(isolated_project, COPIED_TREES)
    expected = tuple(sorted(manifest.files, key=lambda item: item.path))
    if observed != expected:
        observed_paths = {item.path for item in observed}
        expected_paths = {item.path for item in expected}
        missing = sorted(expected_paths - observed_paths)
        extra = sorted(observed_paths - expected_paths)
        changed = sorted(
            item.path
            for item in observed
            if item.path in expected_paths and item not in expected
        )
        raise EvidenceError(
            "E_UNITY_ISOLATION_MANIFEST",
            "the isolated workspace does not match its manifest "
            f"(missing={missing}, unexpected={extra}, changed={changed})",
        )
    recomputed = _tree_digest(observed)
    if recomputed != manifest.tree_sha256:
        raise EvidenceError(
            "E_UNITY_ISOLATION_MANIFEST",
            f"manifest tree_sha256 is {manifest.tree_sha256!r} but the file "
            f"list digests to {recomputed!r}",
        )
