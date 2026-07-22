from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Literal


@dataclass(frozen=True)
class AdapterProfile:
    client: str
    default_agent_profile: str
    agent_profiles: Mapping[str, Mapping[str, Mapping[str, object]]]
    capabilities: Mapping[str, tuple[str, ...]]
    output_roots: Mapping[str, PurePosixPath]


@dataclass(frozen=True)
class SupportDeclaration:
    state: Literal["supported", "unsupported", "exception"]
    reason: str | None
    owner: str | None
    test: str | None


@dataclass(frozen=True)
class Provenance:
    origin: str
    upstream_version: str | None
    upstream_path: str | None
    upstream_sha256: str | None


@dataclass(frozen=True)
class CanonicalUnit:
    schema_version: int
    id: str
    kind: str
    name: str
    summary: str
    capabilities: tuple[str, ...]
    requires: tuple[str, ...]
    support: Mapping[str, SupportDeclaration]
    provenance: Provenance
    content_path: Path
    attributes: Mapping[str, object]


@dataclass(frozen=True)
class CanonicalGraph:
    root: Path
    capabilities: frozenset[str]
    support_policy: Mapping[str, object]
    routes: tuple[Mapping[str, object], ...]
    units: Mapping[str, CanonicalUnit]


__all__ = [
    "AdapterProfile",
    "CanonicalGraph",
    "CanonicalUnit",
    "Provenance",
    "SupportDeclaration",
]
