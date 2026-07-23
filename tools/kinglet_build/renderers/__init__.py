from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import PurePosixPath
from typing import Protocol

from ..model import AdapterProfile, CanonicalGraph


@dataclass(frozen=True)
class RenderedFile:
    path: PurePosixPath
    content: bytes
    source_ids: tuple[str, ...]

    def __post_init__(self) -> None:
        if (
            self.path.is_absolute()
            or not self.path.parts
            or ".." in self.path.parts
        ):
            raise ValueError(
                "rendered file path must name a relative file without parent traversal"
            )


class Renderer(Protocol):
    client: str

    def render(
        self,
        graph: CanonicalGraph,
        profile: AdapterProfile,
    ) -> Mapping[str, tuple[RenderedFile, ...]]: ...


def renderer_registry() -> Mapping[str, Renderer]:
    return {}


__all__ = ["RenderedFile", "Renderer", "renderer_registry"]
