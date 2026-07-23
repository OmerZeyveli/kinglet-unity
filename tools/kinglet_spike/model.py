"""Frozen data model for platform-spike evidence v1."""

from __future__ import annotations

from dataclasses import dataclass


class EvidenceError(Exception):
    """A stable, machine-readable evidence validation error."""

    def __init__(self, code: str, detail: str) -> None:
        self.code = code
        self.detail = detail
        super().__init__(code, detail)

    def __str__(self) -> str:
        return f"{self.code}: {self.detail}"


@dataclass(frozen=True)
class Subject:
    kind: str
    id: str
    version: str


@dataclass(frozen=True)
class Probe:
    id: str
    contract: str


@dataclass(frozen=True)
class Environment:
    os: str
    release: str
    arch: str
    native: bool
    toolchain: tuple[str, ...]


@dataclass(frozen=True)
class Artifact:
    path: str
    sha256: str
    media_type: str
    required: bool


@dataclass(frozen=True)
class Assertion:
    id: str
    status: str
    detail: str


@dataclass(frozen=True)
class Measurement:
    id: str
    unit: str
    samples: tuple[int, ...]


@dataclass(frozen=True)
class Source:
    title: str
    url: str


@dataclass(frozen=True)
class EvidenceRecord:
    schema: str
    run_id: str
    subject: Subject
    probe: Probe
    environment: Environment
    started_at: str
    ended_at: str
    status: str
    command: tuple[str, ...]
    artifacts: tuple[Artifact, ...]
    assertions: tuple[Assertion, ...]
    measurements: tuple[Measurement, ...]
    sources: tuple[Source, ...]
    prompt: str | None
