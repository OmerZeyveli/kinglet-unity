#!/usr/bin/env python3
"""build-record.py — assemble a kinglet.spike.evidence/v1 record for one native
runtime bake-off cell.

Platform-neutral: run-host.sh (Linux, macOS) and run-host.ps1 (Windows) all call
this. The environment triple is supplied by the caller via --os/--release/--arch;
the defaults are the Linux values (linux / ubuntu-24.04-noble / x64).

It reads the candidate's own host-probe result.json
(the raw artifact), derives the 18 assertion entries, embeds the measurements
from measure.sh, computes the artifact's sha256, and writes a strict record.json
under .kinglet/local/spikes/<run-id>/.

The evidence schema is strict (see tools/kinglet_spike/load.py): top-level keys
are exactly {schema, run_id, subject, probe, environment, started_at, ended_at,
status, command, artifacts, assertions, measurements, sources, prompt}.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

EVIDENCE_SCHEMA = "kinglet.spike.evidence/v1"
RESULT_SCHEMA = "kinglet.host-probe.result/v1"

# Frozen host-probe assertion ids (must mirror runtime_contract.REQUIRED_ASSERTIONS).
REQUIRED_ASSERTIONS = (
    "manifest.accept-valid",
    "manifest.reject-unknown",
    "path.unicode-space",
    "filesystem.atomic-replace",
    "lease.acquire",
    "lease.renew",
    "lease.reject-competitor",
    "lease.expire",
    "lease.release",
    "process.child-grandchild",
    "process.cancel",
    "process.no-descendants",
    "crypto.sha256",
    "crypto.ed25519",
    "cleanup.success",
    "cleanup.crash",
    "cleanup.timeout",
    "cleanup.cancel",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _split_lines(value: str) -> list[str]:
    return [line for line in value.splitlines() if line.strip() != ""]


def _assertions_from_result(result: dict) -> tuple[list[dict], str]:
    """Map the probe's own result.json onto record assertions + a record status.

    Returns (assertions, status) where status is "pass" only when all eighteen
    assertions passed, and "fail" when any of them failed.

    THIS USED TO REFUSE ANY NON-PASS ASSERTION and hardcode `"status": "pass"` at
    the call site, which meant the evidence pipeline could not express a failing
    cell AT ALL — while rubric-v1.json is built entirely around failures being
    committed evidence ("A failed gate is committed evidence, not a low score")
    and load.py's RECORD_STATUSES has always accepted "fail". The first real
    failure (the Python candidate on native Windows: `os.killpg` is POSIX-only)
    aborted the whole bake-off with nothing published, and no honest record of
    the failure could be produced by the tooling that exists to produce records.

    What is NOT relaxed: an assertion status outside {pass, fail} is still
    refused rather than coerced, a missing assertion is still refused, and the
    probe's own top-level `status` must agree with its assertions — a probe that
    claims "pass" while reporting a failed assertion is self-contradictory and
    gets no record at all. Those are the "I could not tell" branches; without
    them, an unparseable result would fall through to the permissive answer.
    """
    schema = result.get("schema")
    if schema != RESULT_SCHEMA:
        raise SystemExit(f"build-record: unexpected result schema: {schema!r}")
    raw = result.get("assertions")
    if not isinstance(raw, list):
        raise SystemExit("build-record: result.assertions must be a list")
    by_id: dict[str, str] = {}
    for entry in raw:
        if not isinstance(entry, dict):
            raise SystemExit("build-record: assertion entry must be an object")
        a_id = entry.get("id")
        a_status = entry.get("status")
        if not isinstance(a_id, str) or not a_id:
            raise SystemExit("build-record: assertion missing id")
        by_id[a_id] = str(a_status)

    missing = [a for a in REQUIRED_ASSERTIONS if a not in by_id]
    if missing:
        raise SystemExit(f"build-record: result missing assertions: {missing}")

    # Run-level diagnostics from the probe. They are not attributed to a single
    # assertion by the contract, so they are carried on every FAILING assertion
    # rather than dropped — this is the only free-text slot in the schema, and
    # losing the diagnosis is what makes a committed failure useless later.
    errors = result.get("errors")
    error_detail = ""
    if isinstance(errors, list) and errors:
        error_detail = "; run-level errors: " + "; ".join(str(e) for e in errors)

    assertions: list[dict] = []
    failed: list[str] = []
    for a_id in REQUIRED_ASSERTIONS:
        status = by_id[a_id]
        if status not in ("pass", "fail"):
            raise SystemExit(
                f"build-record: unusable assertion status for {a_id!r}: {status!r}"
            )
        if status == "fail":
            failed.append(a_id)
            detail = "host-probe assertion failed" + error_detail
        else:
            detail = "host-probe assertion passed"
        assertions.append({"id": a_id, "status": status, "detail": detail})

    record_status = "fail" if failed else "pass"

    # Cross-check the probe's own verdict against its assertions. Disagreement in
    # EITHER direction is a broken probe, not a result to publish.
    claimed = result.get("status")
    if isinstance(claimed, str) and claimed in ("pass", "fail") and claimed != record_status:
        raise SystemExit(
            f"build-record: probe reported status {claimed!r} but its assertions say "
            f"{record_status!r} (failed: {failed or 'none'})"
        )

    return assertions, record_status


def _measurements(measure: dict) -> list[dict]:
    cold = measure.get("cold_start_ms")
    if not isinstance(cold, list) or not all(isinstance(x, int) for x in cold):
        raise SystemExit("build-record: cold_start_ms must be a list of ints")
    peak = measure.get("peak_rss_kb")
    artifact_bytes = measure.get("artifact_bytes")
    dep_count = measure.get("dependency_count")
    for name, value in (
        ("peak_rss_kb", peak),
        ("artifact_bytes", artifact_bytes),
        ("dependency_count", dep_count),
    ):
        if not isinstance(value, int):
            raise SystemExit(f"build-record: {name} must be an int, got {value!r}")
    return [
        {"id": "cold-start", "unit": "milliseconds", "samples": cold},
        {"id": "peak-rss", "unit": "kilobytes", "samples": [peak]},
        {"id": "artifact-size", "unit": "bytes", "samples": [artifact_bytes]},
        {"id": "dependency-count", "unit": "count", "samples": [dep_count]},
    ]


def main() -> int:
    parser = argparse.ArgumentParser(prog="build-record.py")
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--started-at", required=True)
    parser.add_argument("--ended-at", required=True)
    parser.add_argument("--artifact-rel", required=True)
    parser.add_argument("--result-file", required=True)
    parser.add_argument("--measure-json", required=True)
    # environment.{os,release,arch} must match a matrix cell exactly
    # (tools/kinglet_spike/coverage.py::_matches). The defaults keep the original
    # Linux behaviour for callers that do not pass them.
    parser.add_argument("--os", dest="os_name", default="linux")
    parser.add_argument("--release", default="ubuntu-24.04-noble")
    parser.add_argument("--arch", default="x64")
    parser.add_argument("--host-line", required=True)
    parser.add_argument("--kernel-line", required=True)
    parser.add_argument("--toolchain-data", required=True)
    parser.add_argument("--sources-data", required=True)
    parser.add_argument("--command-data", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    result_path = Path(args.result_file)
    result = json.loads(result_path.read_text(encoding="utf-8"))
    assertions, record_status = _assertions_from_result(result)

    measure = json.loads(args.measure_json)
    measurements = _measurements(measure)

    toolchain = _split_lines(args.toolchain_data)
    toolchain.append(args.host_line)
    toolchain.append(args.kernel_line)

    sources: list[dict] = []
    for line in _split_lines(args.sources_data):
        title, _, url = line.partition("|")
        sources.append({"title": title, "url": url})

    command = _split_lines(args.command_data)

    artifact_sha = _sha256(result_path)

    record = {
        "schema": EVIDENCE_SCHEMA,
        "run_id": args.run_id,
        "subject": {
            "kind": "runtime",
            "id": args.candidate,
            "version": args.version,
        },
        "probe": {"id": "host-probe", "contract": "kinglet.host-probe/v1"},
        "environment": {
            "os": args.os_name,
            "release": args.release,
            "arch": args.arch,
            "native": True,
            "toolchain": toolchain,
        },
        "started_at": args.started_at,
        "ended_at": args.ended_at,
        # Derived from the assertions — never a literal. A hardcoded "pass" here
        # is what made a failing cell unrecordable.
        "status": record_status,
        "command": command,
        "artifacts": [
            {
                "path": args.artifact_rel,
                "sha256": artifact_sha,
                "media_type": "application/json",
                "required": True,
            }
        ],
        "assertions": assertions,
        "measurements": measurements,
        "sources": sources,
        "prompt": None,
    }

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"build-record: wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
