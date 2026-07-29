"""00D Task 3 — what the platform spike distributes, and where it came from.

One record per (ecosystem, name, version-or-commit), carrying the fields a
distribution actually needs: exact version, source URL, SPDX licence, usage,
owning candidate or probe, and a checksum **with its algorithm**.

The algorithm is its own field because the ecosystems disagree and there is no
lossless way to pretend otherwise:

    NuGet `contentHash`   base64 SHA-512
    .NET SDK artifacts    hex SHA-512   (Microsoft publishes no SHA-256)
    crates.io / PyPI      hex SHA-256
    Unity MCP package     a 40-hex git commit — the commit IS the pin

A single `sha256` field forces one of two lies: relabel someone else's digest,
or discard the authoritative one and substitute a value nobody published. A
mislabelled checksum is worse than an absent one, because it verifies against
nothing while reading as verified.

Nothing enters `items` with a field missing — a supply-chain record with a blank
licence column looks like diligence and is not. But the gap is *reported* rather
than swallowed: transitive dependencies carry checksums in their ecosystem
lockfiles and no recorded licence anywhere in this repo, and they are shipped all
the same. They go to `unlicensed`, counted and named. Dropping them would leave a
report that looks complete and an omission nobody can see.

No network access. A report that reaches out differs by the day it ran and
cannot be regenerated from a checkout.
"""
from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

from .model import EvidenceError

PROVENANCE_SCHEMA = "kinglet.spike.dependency-provenance/v1"

USAGES = (
    "direct-toolchain",
    "runtime-candidate",
    "client-probe-only",
    "unity-probe",
)

_REQUIRED_FIELDS = (
    "ecosystem",
    "name",
    "version_or_commit",
    "source_url",
    "license_spdx",
    "usage",
    "owner",
    "checksum",
    "checksum_algorithm",
)


@dataclass(frozen=True)
class ProvenanceItem:
    ecosystem: str
    name: str
    version_or_commit: str
    source_url: str
    license_spdx: str
    usage: str
    owner: str
    checksum: str
    checksum_algorithm: str


@dataclass(frozen=True)
class UnlicensedItem:
    """Shipped, checksummed, and with no licence recorded anywhere in this repo.

    Not an error and not a `ProvenanceItem`: the checksum is real, the licence
    genuinely has not been established. Kept separate so the report can say how
    many rather than implying zero.
    """

    ecosystem: str
    name: str
    version_or_commit: str
    source_url: str
    owner: str
    checksum: str
    checksum_algorithm: str
    license_spdx: str = ""


@dataclass(frozen=True)
class DeclaredVersionMismatch:
    """A declared direct pin that the ecosystem lockfile did not resolve to.

    The lock is the human-facing pin record; the lockfile is what was actually
    built and measured. When they disagree, the declared pin is stale and every
    measurement was taken against something else. Reported on its own rather than
    absorbed into `unlicensed`, where it would look like an ordinary transitive
    nobody got round to licensing.

    The declared licence is deliberately NOT carried over to the resolved
    version. Doing so would assume the crate did not relicense between them,
    which is exactly the kind of assumption this record exists to stop making.
    """

    ecosystem: str
    name: str
    declared_version: str
    resolved_version: str
    owner: str
    declared_license_spdx: str


@dataclass(frozen=True)
class ProvenanceReport:
    items: tuple[ProvenanceItem, ...] = ()
    unlicensed: tuple[UnlicensedItem, ...] = ()
    declared_version_mismatches: tuple[DeclaredVersionMismatch, ...] = ()


def _key(item: ProvenanceItem) -> tuple[str, str, str]:
    return (item.ecosystem, item.name, item.version_or_commit)


def merge_records(items: Iterable[ProvenanceItem]) -> tuple[ProvenanceItem, ...]:
    """Deduplicate by (ecosystem, name, version), refusing any disagreement.

    Two licences or two digests for one artifact means one of the readers is
    describing something else. Keeping either silently is how a supply-chain
    record starts documenting a package nobody shipped.
    """
    merged: dict[tuple[str, str, str], ProvenanceItem] = {}
    for item in items:
        for field in _REQUIRED_FIELDS:
            if not str(getattr(item, field)).strip():
                raise EvidenceError(
                    "E_PROVENANCE",
                    f"{item.name}@{item.version_or_commit}: {field} is required",
                )
        key = _key(item)
        existing = merged.get(key)
        if existing is None:
            merged[key] = item
            continue
        if existing != item:
            differing = [
                field
                for field in _REQUIRED_FIELDS
                if getattr(existing, field) != getattr(item, field)
            ]
            raise EvidenceError(
                "E_PROVENANCE",
                f"conflicting provenance for {item.name}@{item.version_or_commit}: "
                f"{', '.join(differing)} disagree",
            )
    return tuple(sorted(merged.values(), key=_key))


# --------------------------------------------------------------------------
# ecosystem readers — each one offline, each one reading a committed lockfile
# --------------------------------------------------------------------------


def _read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError("E_PROVENANCE", f"cannot read {path.name}: {error}") from error


def _toolchain_items(repo_root: Path) -> list[ProvenanceItem]:
    """Direct toolchains, from the per-host `downloads` entries that are pinned.

    A host with no entry contributes nothing: it is not pinned, and inventing a
    row for it would be the fabrication the lock's own note forbids.
    """
    lock = _read_json(repo_root / "spikes/platform/runtime/toolchains.lock.json")
    items: list[ProvenanceItem] = []
    for candidate in lock.get("candidates", []):
        owner = candidate["id"]
        for slot in ("toolchain", "build_tool"):
            block = candidate.get(slot)
            if not isinstance(block, dict):
                continue
            license_spdx = block.get("license_spdx", "")
            for download in block.get("downloads", []):
                items.append(
                    ProvenanceItem(
                        ecosystem="toolchain",
                        # The host is part of the identity: the linux and windows
                        # artifacts of one toolchain are different files with
                        # different digests, and merging them by name alone would
                        # raise a conflict on two facts that are both true.
                        name=f"{block['name']} ({download['host_id']})",
                        version_or_commit=block["version"],
                        source_url=download["url"],
                        license_spdx=license_spdx,
                        usage="direct-toolchain",
                        owner=owner,
                        checksum=download["checksum"],
                        checksum_algorithm=download["checksum_algorithm"],
                    )
                )
    return items


_CARGO_PACKAGE = re.compile(
    r'^\[\[package\]\]\s*$\n'
    r'(?P<body>(?:^(?!\[\[).*$\n?)*)',
    re.MULTILINE,
)


def _parse_toml_blocks(text: str) -> list[dict[str, str]]:
    """Scalar `key = "value"` pairs per `[[package]]` block.

    Deliberately not a TOML parser: both Cargo.lock and uv.lock state name,
    version, source and checksum as flat scalars, and pulling in a parser to read
    four strings would add a dependency to the tool that records dependencies.
    """
    blocks: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for line in text.splitlines():
        stripped = line.strip()
        if stripped == "[[package]]":
            current = {}
            blocks.append(current)
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            current = None
            continue
        if current is None or "=" not in stripped:
            continue
        key, _, value = stripped.partition("=")
        key = key.strip()
        value = value.strip()
        if value.startswith('"') and value.endswith('"') and len(value) > 1:
            current[key] = value[1:-1]
        else:
            current[key] = value
    return blocks


_SHA256_IN_TEXT = re.compile(r'hash\s*=\s*"sha256:([0-9a-f]{64})"')


def _cargo_entries(repo_root: Path) -> list[tuple[str, str, str, str]]:
    """(name, version, source_url, sha256) for every checksummed crate."""
    path = repo_root / "spikes/platform/runtime/rust/Cargo.lock"
    entries = []
    for block in _parse_toml_blocks(path.read_text(encoding="utf-8")):
        name = block.get("name")
        version = block.get("version")
        checksum = block.get("checksum")
        if not (name and version and checksum):
            # A workspace member has no checksum because it is not fetched. It is
            # this repo's own code and is not a third-party dependency.
            continue
        entries.append(
            (name, version, f"https://crates.io/crates/{name}/{version}", checksum)
        )
    return entries


def _pypi_entries(repo_root: Path) -> list[tuple[str, str, str, str]]:
    path = repo_root / "spikes/platform/runtime/python/uv.lock"
    text = path.read_text(encoding="utf-8")
    entries = []
    for raw_block in text.split("[[package]]")[1:]:
        block = _parse_toml_blocks("[[package]]" + raw_block)[0]
        name = block.get("name")
        version = block.get("version")
        if not (name and version):
            continue
        found = _SHA256_IN_TEXT.search(raw_block)
        if not found:
            continue
        entries.append(
            (
                name,
                version,
                f"https://pypi.org/project/{name}/{version}/",
                found.group(1),
            )
        )
    return entries


def _nuget_entries(repo_root: Path) -> list[tuple[str, str, str, str]]:
    lock = _read_json(repo_root / "spikes/platform/runtime/dotnet/packages.lock.json")
    entries = []
    for packages in lock.get("dependencies", {}).values():
        for name, meta in packages.items():
            version = meta.get("resolved")
            checksum = meta.get("contentHash")
            if not (version and checksum):
                continue
            entries.append(
                (
                    name,
                    version,
                    f"https://www.nuget.org/packages/{name}/{version}",
                    checksum,
                )
            )
    return entries


_ECOSYSTEMS = (
    # (ecosystem, owner, reader, checksum algorithm)
    ("cargo", "rust", _cargo_entries, "sha256"),
    ("pypi", "python-bundled", _pypi_entries, "sha256"),
    ("nuget", "dotnet", _nuget_entries, "sha512-base64"),
)


def _declared_dependencies(repo_root: Path) -> list[tuple[str, str, str, str]]:
    """(owner, name, version, license) for every direct dependency the lock declares."""
    lock = _read_json(repo_root / "spikes/platform/runtime/toolchains.lock.json")
    declared = []
    for candidate in lock.get("candidates", []):
        for dependency in candidate.get("dependencies", []):
            declared.append(
                (
                    candidate["id"],
                    dependency["name"],
                    dependency["version"],
                    dependency["license_spdx"],
                )
            )
    return declared


def _declared_licenses(repo_root: Path) -> dict[tuple[str, str], str]:
    """(name, version) -> SPDX, for the DIRECT dependencies the lock declares.

    Transitives are absent here, and that absence is the report's `unlicensed`
    section rather than a reason to guess.
    """
    lock = _read_json(repo_root / "spikes/platform/runtime/toolchains.lock.json")
    declared: dict[tuple[str, str], str] = {}
    for candidate in lock.get("candidates", []):
        for dependency in candidate.get("dependencies", []):
            declared[(dependency["name"], dependency["version"])] = dependency[
                "license_spdx"
            ]
    return declared


def _unity_items(repo_root: Path) -> list[ProvenanceItem]:
    lock = _read_json(repo_root / "spikes/platform/unity/mcp.lock.json")
    upstream = lock["upstream"]
    package = lock["package"]
    return [
        ProvenanceItem(
            ecosystem="unity-package",
            name=package["name"],
            version_or_commit=upstream["tag"],
            source_url=upstream["repository"],
            license_spdx=upstream["license"],
            usage="unity-probe",
            owner="unity-mcp",
            # The commit is the pin. There is no distribution tarball to hash;
            # naming a tag without the commit would leave the pin re-pointable.
            checksum=upstream["commit"],
            checksum_algorithm="git-commit",
        )
    ]


def build_provenance(repo_root: Path) -> ProvenanceReport:
    """The whole record, offline and deterministic."""
    repo_root = Path(repo_root)
    declared = _declared_licenses(repo_root)

    items: list[ProvenanceItem] = _toolchain_items(repo_root)
    items += _unity_items(repo_root)
    unlicensed: list[UnlicensedItem] = []

    for ecosystem, owner, reader, algorithm in _ECOSYSTEMS:
        for name, version, source_url, checksum in reader(repo_root):
            license_spdx = declared.get((name, version), "")
            if license_spdx:
                items.append(
                    ProvenanceItem(
                        ecosystem=ecosystem,
                        name=name,
                        version_or_commit=version,
                        source_url=source_url,
                        license_spdx=license_spdx,
                        usage="runtime-candidate",
                        owner=owner,
                        checksum=checksum,
                        checksum_algorithm=algorithm,
                    )
                )
            else:
                unlicensed.append(
                    UnlicensedItem(
                        ecosystem=ecosystem,
                        name=name,
                        version_or_commit=version,
                        source_url=source_url,
                        owner=owner,
                        checksum=checksum,
                        checksum_algorithm=algorithm,
                    )
                )

    # Every direct pin the lock declares must exist at that exact version in the
    # ecosystem lockfile. Where it does not, the declared pin is stale and the
    # measurements were taken against the resolved version instead.
    resolved: dict[tuple[str, str], set[str]] = {}
    for ecosystem, owner, reader, _algorithm in _ECOSYSTEMS:
        for name, version, _url, _checksum in reader(repo_root):
            resolved.setdefault((owner, name), set()).add(version)

    mismatches: list[DeclaredVersionMismatch] = []
    for owner, name, version, license_spdx in _declared_dependencies(repo_root):
        versions = resolved.get((owner, name))
        if versions is None or version in versions:
            continue
        ecosystem = next(
            (eco for eco, own, _r, _a in _ECOSYSTEMS if own == owner), owner
        )
        for found in sorted(versions):
            mismatches.append(
                DeclaredVersionMismatch(
                    ecosystem=ecosystem,
                    name=name,
                    declared_version=version,
                    resolved_version=found,
                    owner=owner,
                    declared_license_spdx=license_spdx,
                )
            )

    deduped_unlicensed = tuple(
        sorted(
            {
                (u.ecosystem, u.name, u.version_or_commit): u for u in unlicensed
            }.values(),
            key=lambda u: (u.ecosystem, u.name, u.version_or_commit),
        )
    )
    return ProvenanceReport(
        merge_records(items),
        deduped_unlicensed,
        tuple(
            sorted(
                mismatches,
                key=lambda m: (m.ecosystem, m.name, m.declared_version),
            )
        ),
    )


def render_provenance_json(report: ProvenanceReport) -> str:
    value = {
        "schema": PROVENANCE_SCHEMA,
        "items": [asdict(item) for item in report.items],
        "unrecorded_licenses": [asdict(item) for item in report.unlicensed],
        "declared_version_mismatches": [
            asdict(item) for item in report.declared_version_mismatches
        ],
    }
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def render_provenance_markdown(report: ProvenanceReport) -> str:
    lines = [
        "# Kinglet Platform Spike — Dependency Provenance",
        "",
        "Every dependency the spike distributes. `usage` says what a row is for:",
        "`direct-toolchain` builds a candidate, `runtime-candidate` is linked into",
        "one, `unity-probe` belongs to the Unity probe. **None of these is yet a",
        "product dependency** — this is a spike, and the runtime is not selected.",
        "",
        "Checksums carry their algorithm because the ecosystems disagree: NuGet",
        "publishes base64 SHA-512, Microsoft publishes hex SHA-512 for SDK",
        "artifacts, crates.io and PyPI publish hex SHA-256, and the Unity MCP",
        "package is pinned by git commit. A digest relabelled to fit one column",
        "verifies against nothing while reading as verified.",
        "",
        "| Ecosystem | Name | Version / commit | Licence | Usage | Owner | Checksum |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for item in report.items:
        lines.append(
            f"| {item.ecosystem} | `{item.name}` | `{item.version_or_commit}` | "
            f"{item.license_spdx} | {item.usage} | {item.owner} | "
            f"`{item.checksum[:16]}…` ({item.checksum_algorithm}) |"
        )

    lines += [
        "",
        "## Licences not recorded",
        "",
        f"**{len(report.unlicensed)}** transitive dependencies are checksummed by "
        "their ecosystem lockfile and have **no SPDX licence recorded anywhere in "
        "this repository**. They are distributed inside the candidate binaries all "
        "the same.",
        "",
        "They are listed rather than dropped on purpose: a report that silently "
        "omitted them would read as complete, and the omission would be invisible "
        "to exactly the reader who needs it. Establishing these licences is real "
        "work and it has not been done.",
        "",
        "| Ecosystem | Name | Version | Owner |",
        "| --- | --- | --- | --- |",
    ]
    for item in report.unlicensed:
        lines.append(
            f"| {item.ecosystem} | `{item.name}` | `{item.version_or_commit}` | "
            f"{item.owner} |"
        )

    lines += [
        "",
        "## Declared pins the lockfile did not resolve to",
        "",
        f"**{len(report.declared_version_mismatches)}** direct dependencies are "
        "declared in `toolchains.lock.json` at a version the ecosystem lockfile "
        "did not resolve. The lockfile is what was actually built and measured, "
        "so where these disagree the declared pin is stale and every published "
        "measurement was taken against the resolved version instead.",
        "",
        "The declared licence is **not** carried over to the resolved version: "
        "that would assume the package did not relicense in between, which is the "
        "kind of assumption this record exists to stop making. Until the lock is "
        "corrected these appear above as unlicensed.",
        "",
        "| Ecosystem | Name | Declared | Resolved | Owner | Declared licence |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for item in report.declared_version_mismatches:
        lines.append(
            f"| {item.ecosystem} | `{item.name}` | `{item.declared_version}` | "
            f"`{item.resolved_version}` | {item.owner} | "
            f"{item.declared_license_spdx} |"
        )
    return "\n".join(lines) + "\n"
