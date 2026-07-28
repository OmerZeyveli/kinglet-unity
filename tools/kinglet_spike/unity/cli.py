"""cli.py -- Command line for the Unity execution-probe routes.

    python3 -m tools.kinglet_spike.unity filesystem \
        --project spikes/platform/unity/fixture --raw-dir .kinglet/local/run

    python3 -m tools.kinglet_spike.unity same-project-headless \
        --project <disposable copy> --raw-dir .kinglet/local/run \
        --editor ~/Unity/Hub/Editor/<version>/Editor/Unity

Contract of the exit codes, which is the whole point of having a CLI here:

    0  a receipt was produced AND it satisfies kinglet.unity-probe.receipt/v1
    1  a receipt was produced but VIOLATES the contract (its diagnostics are
       printed to stderr; the receipt is still printed to stdout, because a
       dishonest receipt is evidence and must not be swallowed)
    2  no receipt could be produced -- the route refused, or it could not
       establish what happened. The EvidenceError code and detail go to stderr.

`--raw-dir` is a RAW run directory: it takes the Unity log, the results XML,
the lease and the summary, and it belongs under `.kinglet/local/` (gitignored),
never in the committed tree. Only the receipt printed on stdout, and the
sanitized summary/inventory named in its `artifacts`, are publishable.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from ..model import EvidenceError
from .receipt import validate_unity_receipt
from .routes import (
    FILESYSTEM_ROUTE,
    SAME_PROJECT_HEADLESS_ROUTE,
    receipt_to_dict,
    run_filesystem,
    run_same_project_headless,
)


class _ArgumentParser(argparse.ArgumentParser):
    """Raises instead of calling sys.exit, matching tools/kinglet_spike/cli.py."""

    def error(self, message: str) -> None:
        raise ValueError(message)


def _parser() -> argparse.ArgumentParser:
    parser = _ArgumentParser(prog="python3 -m tools.kinglet_spike.unity")
    commands = parser.add_subparsers(dest="route", required=True)

    filesystem = commands.add_parser(FILESYSTEM_ROUTE)
    filesystem.add_argument("--project", type=Path, required=True)
    filesystem.add_argument("--raw-dir", type=Path, required=True)

    headless = commands.add_parser(SAME_PROJECT_HEADLESS_ROUTE)
    headless.add_argument("--project", type=Path, required=True)
    headless.add_argument("--raw-dir", type=Path, required=True)
    headless.add_argument("--editor", type=Path, required=True)
    return parser


def main(argv: list[str] | None = None, *, stdout=None, stderr=None) -> int:
    out = sys.stdout if stdout is None else stdout
    err = sys.stderr if stderr is None else stderr
    try:
        args = _parser().parse_args(sys.argv[1:] if argv is None else argv)
    except ValueError as error:
        print(f"usage error: {error}", file=err)
        return 2

    try:
        if args.route == FILESYSTEM_ROUTE:
            receipt = run_filesystem(args.project, args.raw_dir)
        else:
            receipt = run_same_project_headless(
                args.editor, args.project, args.raw_dir
            )
    except EvidenceError as error:
        print(f"{error.code}: {error.detail}", file=err)
        return 2

    print(json.dumps(receipt_to_dict(receipt), indent=2, sort_keys=True), file=out)

    diagnostics = validate_unity_receipt(receipt)
    for diagnostic in diagnostics:
        print(
            f"{diagnostic.code} {diagnostic.location}: {diagnostic.message}",
            file=err,
        )
    return 1 if diagnostics else 0
