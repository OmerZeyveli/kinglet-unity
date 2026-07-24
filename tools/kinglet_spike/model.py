from __future__ import annotations

from dataclasses import dataclass


class EvidenceError(ValueError):
    """A stable evidence-boundary diagnostic."""

    def __init__(self, code: str, detail: str) -> None:
        self.code = code
        self.detail = detail
        super().__init__(str(self))

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
class AssertionResult:
    id: str
    status: str
    detail: str


@dataclass(frozen=True)
class Measurement:
    id: str
    unit: str
    samples: tuple[int, ...]


@dataclass(frozen=True)
class SourceReference:
    title: str
    url: str


@dataclass(frozen=True)
class PromptReference:
    id: str
    sha256: str


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
    assertions: tuple[AssertionResult, ...]
    measurements: tuple[Measurement, ...]
    sources: tuple[SourceReference, ...]
    prompt: PromptReference | None
