from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from .model import CoverageCell, EvidenceError, EvidenceRecord

MATRIX_SCHEMA = "kinglet.spike.matrix/v1"
MATRIX_SCHEMA_V2 = "kinglet.spike.matrix/v2"
MATRIX_SCHEMAS = frozenset((MATRIX_SCHEMA, MATRIX_SCHEMA_V2))
COVERAGE_STATES = frozenset(
    ("pass", "fail", "unavailable", "inconclusive", "invalid")
)

# A cell's standing in the matrix, as distinct from what evidence says about it.
#
#   required — the frozen default. Keeps its gate open until it passes.
#   deferred — reachable, not yet run, and consciously postponed. Does not hold a
#              gate open; still reported, and still closes normally if evidence
#              lands.
#   dropped  — unreachable on any hardware the project has or expects. Same gate
#              effect, different meaning: nobody is waiting for it.
#
# `deferred` and `dropped` behave identically for gating on purpose. Collapsing
# them into one value would lose the only thing a reader needs later: whether the
# cell is coming back.
DISPOSITIONS = ("required", "deferred", "dropped")


@dataclass(frozen=True)
class _MatrixCell:
    id: str
    subject_kind: str
    subject_id: str
    probe: str
    os: str
    release: str
    arch: str
    disposition: str = "required"


def _keys(
    value: object, path: str, required: set[str], optional: set[str] | None = None
) -> dict:
    if not isinstance(value, dict):
        raise EvidenceError("E_COVERAGE", f"{path} must be an object")
    missing = sorted(required - value.keys())
    unknown = sorted(value.keys() - required - (optional or set()))
    if missing:
        raise EvidenceError("E_COVERAGE", f"{path}.{missing[0]} is required")
    if unknown:
        raise EvidenceError("E_COVERAGE", f"{path}.{unknown[0]} is unknown")
    return value


def _string(value: object, path: str) -> str:
    if not isinstance(value, str) or not value:
        raise EvidenceError("E_COVERAGE", f"{path} must be a non-empty string")
    return value


def _amendment_index(root: dict) -> dict[str, str]:
    """cell id -> the disposition a committed amendment grants it.

    A cell cannot leave `required` on its own say-so. This is the whole point of
    the mechanism: without the coupling, `"disposition": "dropped"` is a one-word
    edit that silently shrinks what the project claims to have tested, which is
    exactly what freezing the matrix was meant to prevent. Writing the reason
    down is the cost, and it is supposed to be the cost.
    """
    raw = root.get("amendments", [])
    if not isinstance(raw, list):
        raise EvidenceError("E_COVERAGE", "matrix.amendments must be an array")

    granted: dict[str, str] = {}
    for index, raw_amendment in enumerate(raw):
        location = f"matrix.amendments[{index}]"
        item = _keys(
            raw_amendment,
            location,
            {"id", "date", "disposition", "reason", "decided_by", "cells"},
        )
        _string(item["id"], f"{location}.id")
        _string(item["date"], f"{location}.date")
        _string(item["decided_by"], f"{location}.decided_by")
        # An empty reason is refused rather than defaulted. An amendment whose
        # justification is blank is the silent edit wearing the mechanism's coat.
        _string(item["reason"], f"{location}.reason")
        disposition = _string(item["disposition"], f"{location}.disposition")
        if disposition not in DISPOSITIONS or disposition == "required":
            raise EvidenceError(
                "E_COVERAGE",
                f"{location}.disposition must be one of "
                f"{[d for d in DISPOSITIONS if d != 'required']}, got {disposition!r}",
            )
        cell_ids = item["cells"]
        if not isinstance(cell_ids, list) or not cell_ids:
            raise EvidenceError(
                "E_COVERAGE", f"{location}.cells must be a non-empty array"
            )
        for cell_index, cell_id in enumerate(cell_ids):
            identifier = _string(cell_id, f"{location}.cells[{cell_index}]")
            if identifier in granted:
                raise EvidenceError(
                    "E_COVERAGE", f"cell amended twice: {identifier}"
                )
            granted[identifier] = disposition
    return granted


def load_matrix_cells(path: Path) -> tuple[_MatrixCell, ...]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError("E_COVERAGE", f"cannot decode matrix {path}: {error}") from error
    root = _keys(
        value,
        "matrix",
        {"schema", "cells"},
        optional={"supersedes", "amendments"},
    )
    schema = _string(root["schema"], "matrix.schema")
    if schema not in MATRIX_SCHEMAS:
        raise EvidenceError("E_COVERAGE", f"unsupported matrix schema: {schema}")
    if schema == MATRIX_SCHEMA and ("amendments" in root or "supersedes" in root):
        # v1 is the frozen original. Amending it in place is the move this whole
        # mechanism exists to make impossible.
        raise EvidenceError(
            "E_COVERAGE", "matrix v1 is frozen; amendments belong in a v2 matrix"
        )
    raw_cells = root["cells"]
    if not isinstance(raw_cells, list):
        raise EvidenceError("E_COVERAGE", "matrix.cells must be an array")

    granted = _amendment_index(root)

    cells: list[_MatrixCell] = []
    for index, raw_cell in enumerate(raw_cells):
        location = f"matrix.cells[{index}]"
        item = _keys(
            raw_cell,
            location,
            {"id", "subject", "probe", "os", "release", "arch"},
            optional={"disposition"},
        )
        subject = _keys(item["subject"], f"{location}.subject", {"kind", "id"})
        identifier = _string(item["id"], f"{location}.id")
        disposition = item.get("disposition", "required")
        if disposition not in DISPOSITIONS:
            raise EvidenceError(
                "E_COVERAGE",
                f"{location}.disposition must be one of {list(DISPOSITIONS)}, "
                f"got {disposition!r}",
            )
        if disposition != "required" and granted.get(identifier) != disposition:
            raise EvidenceError(
                "E_COVERAGE",
                f"cell {identifier} is {disposition} but no amendment grants it "
                f"that disposition",
            )
        cells.append(
            _MatrixCell(
                id=identifier,
                subject_kind=_string(subject["kind"], f"{location}.subject.kind"),
                subject_id=_string(subject["id"], f"{location}.subject.id"),
                probe=_string(item["probe"], f"{location}.probe"),
                os=_string(item["os"], f"{location}.os"),
                release=_string(item["release"], f"{location}.release"),
                arch=_string(item["arch"], f"{location}.arch"),
                disposition=disposition,
            )
        )

    identifiers = [cell.id for cell in cells]
    duplicate_ids = sorted(
        identifier for identifier in set(identifiers) if identifiers.count(identifier) > 1
    )
    if duplicate_ids:
        raise EvidenceError("E_COVERAGE", f"duplicate matrix cell: {duplicate_ids[0]}")
    if identifiers != sorted(identifiers):
        raise EvidenceError("E_COVERAGE", "matrix cells must be sorted by ID")

    # The other half of the coupling: an amendment that names nothing real, or
    # names a cell the matrix still requires, is prose contradicting the contract
    # beside it. Whichever is wrong, publishing both is worse than either.
    by_id = {cell.id: cell for cell in cells}
    for identifier, disposition in granted.items():
        cell = by_id.get(identifier)
        if cell is None:
            raise EvidenceError(
                "E_COVERAGE", f"amendment names unknown cell: {identifier}"
            )
        if cell.disposition == "required":
            raise EvidenceError(
                "E_COVERAGE",
                f"amendment claims {identifier} is {disposition}, but the cell is "
                f"still required",
            )
    return tuple(cells)


def choose_state(states: Iterable[str]) -> str:
    values = tuple(states)
    unknown = sorted(set(values) - COVERAGE_STATES)
    if unknown:
        raise EvidenceError("E_COVERAGE", f"unknown coverage state: {unknown[0]}")
    if "invalid" in values:
        return "invalid"
    if not values:
        return "missing"
    return values[-1]


def _matches(record: EvidenceRecord, cell: _MatrixCell) -> bool:
    return (
        record.subject.kind == cell.subject_kind
        and record.subject.id == cell.subject_id
        and record.probe.id == cell.probe
        and record.environment.os == cell.os
        and record.environment.release == cell.release
        and record.environment.arch == cell.arch
    )


def evaluate_coverage(
    records: Iterable[EvidenceRecord],
    matrix_path: Path,
) -> tuple[CoverageCell, ...]:
    ordered_records = tuple(sorted(records, key=lambda item: (item.ended_at, item.run_id)))
    cells: list[CoverageCell] = []
    for matrix_cell in load_matrix_cells(matrix_path):
        matching = tuple(
            record for record in ordered_records if _matches(record, matrix_cell)
        )
        cells.append(
            CoverageCell(
                matrix_cell.id,
                choose_state(record.status for record in matching),
                tuple(record.run_id for record in matching),
                matrix_cell.disposition,
            )
        )
    return tuple(cells)
