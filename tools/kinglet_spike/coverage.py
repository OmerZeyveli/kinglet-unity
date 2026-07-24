from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from .model import CoverageCell, EvidenceError, EvidenceRecord

MATRIX_SCHEMA = "kinglet.spike.matrix/v1"
COVERAGE_STATES = frozenset(
    ("pass", "fail", "unavailable", "inconclusive", "invalid")
)


@dataclass(frozen=True)
class _MatrixCell:
    id: str
    subject_kind: str
    subject_id: str
    probe: str
    os: str
    release: str
    arch: str


def _keys(value: object, path: str, required: set[str]) -> dict:
    if not isinstance(value, dict):
        raise EvidenceError("E_COVERAGE", f"{path} must be an object")
    missing = sorted(required - value.keys())
    unknown = sorted(value.keys() - required)
    if missing:
        raise EvidenceError("E_COVERAGE", f"{path}.{missing[0]} is required")
    if unknown:
        raise EvidenceError("E_COVERAGE", f"{path}.{unknown[0]} is unknown")
    return value


def _string(value: object, path: str) -> str:
    if not isinstance(value, str) or not value:
        raise EvidenceError("E_COVERAGE", f"{path} must be a non-empty string")
    return value


def _load_matrix(path: Path) -> tuple[_MatrixCell, ...]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError("E_COVERAGE", f"cannot decode matrix {path}: {error}") from error
    root = _keys(value, "matrix", {"schema", "cells"})
    schema = _string(root["schema"], "matrix.schema")
    if schema != MATRIX_SCHEMA:
        raise EvidenceError("E_COVERAGE", f"unsupported matrix schema: {schema}")
    raw_cells = root["cells"]
    if not isinstance(raw_cells, list):
        raise EvidenceError("E_COVERAGE", "matrix.cells must be an array")

    cells: list[_MatrixCell] = []
    for index, raw_cell in enumerate(raw_cells):
        location = f"matrix.cells[{index}]"
        item = _keys(
            raw_cell,
            location,
            {"id", "subject", "probe", "os", "release", "arch"},
        )
        subject = _keys(item["subject"], f"{location}.subject", {"kind", "id"})
        cells.append(
            _MatrixCell(
                id=_string(item["id"], f"{location}.id"),
                subject_kind=_string(subject["kind"], f"{location}.subject.kind"),
                subject_id=_string(subject["id"], f"{location}.subject.id"),
                probe=_string(item["probe"], f"{location}.probe"),
                os=_string(item["os"], f"{location}.os"),
                release=_string(item["release"], f"{location}.release"),
                arch=_string(item["arch"], f"{location}.arch"),
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
    for matrix_cell in _load_matrix(matrix_path):
        matching = tuple(
            record for record in ordered_records if _matches(record, matrix_cell)
        )
        cells.append(
            CoverageCell(
                matrix_cell.id,
                choose_state(record.status for record in matching),
                tuple(record.run_id for record in matching),
            )
        )
    return tuple(cells)
