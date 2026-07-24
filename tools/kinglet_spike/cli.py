from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .coverage import evaluate_coverage
from .load import load_record
from .model import Diagnostic, EvidenceError
from .publish import publish_record
from .report import load_published_records, write_reports
from .validate import validate_record


class _ArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise ValueError(message)


def _parser() -> argparse.ArgumentParser:
    parser = _ArgumentParser(prog="python3 -m tools.kinglet_spike")
    commands = parser.add_subparsers(dest="command", required=True)

    validate = commands.add_parser("validate")
    validate.add_argument("record", type=Path)
    validate.add_argument("--repo-root", type=Path, default=Path("."))

    publish = commands.add_parser("publish")
    publish.add_argument("record", type=Path)
    publish.add_argument("--repo-root", type=Path, default=Path("."))

    report = commands.add_parser("report")
    report.add_argument("--repo-root", type=Path, default=Path("."))
    report.add_argument("--matrix", type=Path, required=True)

    gate = commands.add_parser("gate")
    gate.add_argument("gate_id")
    gate.add_argument("--repo-root", type=Path, default=Path("."))
    return parser


def validate_path(path: Path, repo_root: Path) -> tuple[Diagnostic, ...]:
    record = load_record(path)
    platform_root = repo_root / "docs/research/platform-spike"
    evidence_root = platform_root / "evidence"
    try:
        path.resolve().relative_to(evidence_root.resolve())
        artifact_root = platform_root
    except ValueError:
        artifact_root = path.parent / "publish"
    return validate_record(record, artifact_root)


def _all_pass(cells: tuple, prefix: str) -> bool:
    selected = tuple(cell for cell in cells if cell.id.startswith(prefix))
    return bool(selected) and all(cell.state == "pass" for cell in selected)


def _gate_0a_files(repo_root: Path) -> tuple[Path, ...]:
    return tuple(
        repo_root / path
        for path in (
            "tools/kinglet_spike/model.py",
            "tools/kinglet_spike/load.py",
            "tools/kinglet_spike/redact.py",
            "tools/kinglet_spike/validate.py",
            "tools/kinglet_spike/publish.py",
            "tools/kinglet_spike/coverage.py",
            "tools/kinglet_spike/report.py",
            "tools/kinglet_spike/cli.py",
            "spikes/platform/contracts/evidence-v1.json",
            "spikes/platform/contracts/matrix-v1.json",
            "docs/research/platform-spike/reports/coverage.json",
            "docs/research/platform-spike/reports/coverage.md",
        )
    )


def gate_is_closed(gate_id: str, repo_root: Path) -> bool:
    if gate_id == "0A":
        return all(path.is_file() for path in _gate_0a_files(repo_root))

    matrix = repo_root / "spikes/platform/contracts/matrix-v1.json"
    cells = evaluate_coverage(load_published_records(repo_root), matrix)
    if gate_id == "0R":
        return _all_pass(cells, "runtime.")
    if gate_id == "0U":
        return _all_pass(cells, "unity.")
    if gate_id.startswith("0C:") and gate_id.count(":") == 1:
        client = gate_id.split(":", 1)[1]
        if not client:
            raise EvidenceError("E_COVERAGE", "client gate requires an ID")
        return _all_pass(cells, f"client.{client}.")
    if gate_id == "0D":
        return _all_pass(cells, "runtime.") and _all_pass(cells, "unity.")
    raise EvidenceError("E_COVERAGE", f"unknown gate: {gate_id}")


def _print_diagnostics(diagnostics: tuple[Diagnostic, ...]) -> None:
    for diagnostic in diagnostics:
        print(
            f"{diagnostic.code}: {diagnostic.location}: {diagnostic.message}",
            file=sys.stderr,
        )


def main(argv: list[str] | None = None) -> int:
    try:
        arguments = _parser().parse_args(argv)
        if arguments.command == "validate":
            diagnostics = validate_path(arguments.record, arguments.repo_root)
            if diagnostics:
                _print_diagnostics(diagnostics)
                return 2
            print(f"accepted: {arguments.record}")
            return 0
        if arguments.command == "publish":
            target = publish_record(arguments.record, arguments.repo_root)
            print(target)
            return 0
        if arguments.command == "report":
            cells = write_reports(arguments.repo_root, arguments.matrix)
            print(f"reported {len(cells)} coverage cells")
            return 0
        if arguments.command == "gate":
            return 0 if gate_is_closed(arguments.gate_id, arguments.repo_root) else 1
        raise ValueError(f"unknown command: {arguments.command}")
    except (EvidenceError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 2
