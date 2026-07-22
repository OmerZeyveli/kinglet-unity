from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class BuildError(ValueError):
    code: str
    source: Path
    field: str
    detail: str

    def __str__(self) -> str:
        return f"{self.source}:{self.field}: [{self.code}] {self.detail}"


__all__ = ["BuildError"]
