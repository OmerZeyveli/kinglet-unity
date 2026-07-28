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


UNITY_REPORT_SCHEMA = "kinglet.spike.unity-execution/v1"


def _unity_open_reasons(records: Iterable[EvidenceRecord]) -> dict[str, str]:
    """For each non-passing unity record, the reason it did not close its cell.

    Taken from the record's own failing assertions, never from a table kept
    beside them: a reason that is not in the published evidence is a claim no
    reader can check.
    """
    reasons: dict[str, str] = {}
    for record in records:
        if record.subject.kind != "unity" or record.status == "pass":
            continue
        failing = [a for a in record.assertions if a.status != "pass"]
        key = f"{record.probe.id}@{record.environment.os}-{record.environment.release}"
        reasons[key] = "; ".join(f"{a.id}: {a.detail}" for a in failing) or record.status
    return reasons


def render_unity_json(
    cells: Iterable[CoverageCell],
    records: Iterable[EvidenceRecord],
    matrix_name: str,
) -> str:
    unity_cells = sorted(
        (cell for cell in cells if cell.id.startswith("unity.")),
        key=lambda item: item.id,
    )
    unity_records = [record for record in records if record.subject.kind == "unity"]
    states: dict[str, int] = {}
    for cell in unity_cells:
        states[cell.state] = states.get(cell.state, 0) + 1
    value = {
        "schema": UNITY_REPORT_SCHEMA,
        "generated_from_matrix": matrix_name,
        "cells": [asdict(cell) for cell in unity_cells],
        "state_counts": dict(sorted(states.items())),
        "open_cell_reasons": _unity_open_reasons(unity_records),
        "subject_versions": sorted(
            {record.subject.version for record in unity_records}
        ),
        "environments": sorted(
            {
                f"{record.environment.os}/{record.environment.release}/"
                f"{record.environment.arch}"
                for record in unity_records
            }
        ),
    }
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def render_unity_markdown(
    cells: Iterable[CoverageCell],
    records: Iterable[EvidenceRecord],
) -> str:
    unity_cells = sorted(
        (cell for cell in cells if cell.id.startswith("unity.")),
        key=lambda item: item.id,
    )
    unity_records = [record for record in records if record.subject.kind == "unity"]
    reasons = _unity_open_reasons(unity_records)
    lines = [
        "# Kinglet 00U — Unity Execution Routes",
        "",
        "One row per frozen matrix cell. A cell is closed only by a published",
        "`pass` record; `missing` means no host has run it, and `inconclusive`",
        "means a host looked and could not establish the claim.",
        "",
        "| Cell | State | Runs |",
        "| --- | --- | --- |",
    ]
    for cell in unity_cells:
        runs = ", ".join(f"`{run}`" for run in cell.run_ids) if cell.run_ids else "—"
        lines.append(f"| `{cell.id}` | {cell.state} | {runs} |")
    if reasons:
        lines += ["", "## Why the open cells are open", ""]
        for key in sorted(reasons):
            lines.append(f"- **`{key}`** — {reasons[key]}")
    lines += _known_artefact_lines(unity_records)
    return "\n".join(lines) + "\n"


def _known_artefact_lines(records) -> list[str]:
    """Disclose, to a READER of the evidence, defects the records still carry.

    Four cosmetic defects were found in the assembling code after these records
    were published. Published evidence is immutable and regenerating it would
    mean either deleting committed records or launching Unity again for a
    cosmetic gain, so the code was fixed and the records were left alone. That
    decision is defensible; leaving it recorded only in a plan report under
    `.superpowers/`, which ships to nobody, is not. A reader auditing this
    evidence must not have to go looking to learn that a cited artifact name
    does not resolve.

    The trigger is DERIVED, not a hardcoded run id: a record whose start and
    end stamps are identical is one the pre-fix assembler produced, because the
    fixed one records each probe's real span. The section therefore retires
    itself the moment no such record remains.
    """
    zero_span = sorted(
        record.run_id
        for record in records
        if record.status == "pass" and record.started_at == record.ended_at
    )
    if not zero_span:
        return []
    lines = [
        "",
        "## Known artefacts of the committed records",
        "",
        "These are defects in the tooling that ASSEMBLED the records, found",
        "after they were published. Every measured fact in them was verified",
        "against its artifact and stands. The assembling code is fixed; the",
        "records are immutable and were deliberately not regenerated, so the",
        "next run — a Linux re-run or the first macOS run — carries the",
        "corrections and these notes disappear from this report.",
        "",
        f"1. **Zero-length spans.** {len(zero_span)} records report",
        "   `started_at == ended_at` although their artifacts record real",
        "   durations (`wall_seconds` of 14.216, 18.197 and 22.151 among",
        "   them). The probe's span is now carried through to the record.",
        "2. **One dangling artifact reference.** Inside",
        "   `collision-refusal-receipt.json`, the `artifacts` field names",
        "   `artifacts/unity/same-project-headless-summary.json` — the route's",
        "   own route-relative name. That cell publishes the file as",
        "   `collision-refusal-summary.json`, so the reference resolves to",
        "   nothing in its directory. The receipt's references are now",
        "   rewritten to the paths actually published.",
        "3. **`orphan-cleanup` wording.** Its assertion detail says \"peak",
        "   population during the cold run\"; that run was CANCELLED at 14s,",
        "   and it is the same run and the same artifact as the `cancellation`",
        "   cell. A killed run is the stronger case for cleanup, and the",
        "   artifact discloses the kill, but the wording did not.",
        "4. **No post-run census on `isolated-headless`.** That artifact",
        "   publishes `orphan_peak_during_run` and no `orphan_census_after`,",
        "   so the suite's strongest `AssetImportWorker` cleanup datapoint is",
        "   unpublished. The census is now collected and staged.",
        "",
        "Affected records:",
        "",
    ]
    lines += [f"- `{run_id}`" for run_id in zero_span]
    return lines


def write_unity_reports(repo_root: Path, matrix_path: Path) -> tuple[CoverageCell, ...]:
    records = load_published_records(repo_root)
    cells = evaluate_coverage(records, matrix_path)
    report_root = repo_root / "docs/research/platform-spike/reports"
    matrix_name = _matrix_name(matrix_path, repo_root)
    _atomic_replace(
        report_root / "unity-execution.json",
        render_unity_json(cells, records, matrix_name),
    )
    _atomic_replace(
        report_root / "unity-execution.md",
        render_unity_markdown(cells, records),
    )
    return cells


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
