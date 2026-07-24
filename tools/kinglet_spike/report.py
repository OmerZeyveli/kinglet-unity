from __future__ import annotations

import json
import os
from dataclasses import asdict, replace
from pathlib import Path
from typing import Iterable

from .coverage import evaluate_coverage
from .load import load_record
from .model import CoverageCell, EvidenceRecord
from .validate import validate_record

COVERAGE_SCHEMA = "kinglet.spike.coverage/v1"


def render_markdown(cells: Iterable[CoverageCell]) -> str:
    lines = [
        "# Kinglet Platform Spike Coverage",
        "",
        "| Cell | State | Runs |",
        "| --- | --- | --- |",
    ]
    for cell in sorted(cells, key=lambda item: item.id):
        runs = (
            ", ".join(f"`{run_id}`" for run_id in cell.run_ids)
            if cell.run_ids
            else "—"
        )
        lines.append(f"| `{cell.id}` | {cell.state} | {runs} |")
    return "\n".join(lines) + "\n"


def render_json(cells: Iterable[CoverageCell], matrix_name: str) -> str:
    value = {
        "schema": COVERAGE_SCHEMA,
        "generated_from_matrix": matrix_name,
        "cells": [
            asdict(cell)
            for cell in sorted(cells, key=lambda item: item.id)
        ],
    }
    return json.dumps(
        value,
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    ) + "\n"


def load_published_records(repo_root: Path) -> tuple[EvidenceRecord, ...]:
    platform_root = repo_root / "docs/research/platform-spike"
    evidence_root = platform_root / "evidence"
    if not evidence_root.is_dir():
        return ()
    records: list[EvidenceRecord] = []
    for path in sorted(evidence_root.rglob("*.json")):
        record = load_record(path)
        diagnostics = validate_record(record, platform_root)
        records.append(replace(record, status="invalid") if diagnostics else record)
    return tuple(records)


def _matrix_name(matrix_path: Path, repo_root: Path) -> str:
    try:
        return matrix_path.resolve().relative_to(repo_root.resolve()).as_posix()
    except ValueError:
        return matrix_path.resolve().as_posix()


def _atomic_replace(path: Path, payload: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f"{path.name}.tmp")
    try:
        with temporary.open("w", encoding="utf-8", newline="\n") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def write_reports(
    repo_root: Path,
    matrix_path: Path,
) -> tuple[CoverageCell, ...]:
    records = load_published_records(repo_root)
    cells = evaluate_coverage(records, matrix_path)
    report_root = repo_root / "docs/research/platform-spike/reports"
    matrix_name = _matrix_name(matrix_path, repo_root)
    _atomic_replace(report_root / "coverage.json", render_json(cells, matrix_name))
    _atomic_replace(report_root / "coverage.md", render_markdown(cells))
    return cells
