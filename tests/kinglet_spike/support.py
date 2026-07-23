from __future__ import annotations

import hashlib
import json
from pathlib import Path


def valid_record(
    artifact_path: str = (
        "artifacts/runtime/python/"
        "20260723T120000Z-runtime-python-windows11-x64-01/result.json"
    ),
) -> dict:
    payload = b'{"ok":true}\n'
    return {
        "schema": "kinglet.spike.evidence/v1",
        "run_id": "20260723T120000Z-runtime-python-windows11-x64-01",
        "subject": {"kind": "runtime", "id": "python", "version": "3.14.6"},
        "probe": {"id": "host-probe", "contract": "kinglet.host-probe/v1"},
        "environment": {
            "os": "windows",
            "release": "11-24H2",
            "arch": "x64",
            "native": True,
            "toolchain": ["python=3.14.6", "pyinstaller=6.21.0"],
        },
        "started_at": "2026-07-23T12:00:00Z",
        "ended_at": "2026-07-23T12:00:02Z",
        "status": "pass",
        "command": ["kinglet-host-probe.exe", "--contract", "contract.json"],
        "artifacts": [{
            "path": artifact_path,
            "sha256": hashlib.sha256(payload).hexdigest(),
            "media_type": "application/json",
            "required": True,
        }],
        "assertions": [
            {"id": "manifest.valid", "status": "pass", "detail": "accepted"},
            {"id": "process.no-orphans", "status": "pass", "detail": "zero descendants"},
        ],
        "measurements": [
            {"id": "cold-start", "unit": "milliseconds", "samples": [12, 11, 13, 12, 11]},
        ],
        "sources": [{
            "title": "Python 3.14.6",
            "url": "https://www.python.org/downloads/release/python-3146/",
        }],
        "prompt": None,
    }


def write_record(root: Path, value: dict) -> Path:
    path = root / "record.json"
    path.write_text(json.dumps(value), encoding="utf-8")
    return path
