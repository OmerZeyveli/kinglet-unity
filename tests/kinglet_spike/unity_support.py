"""unity_support.py -- Shared fixtures for Unity execution-probe receipt tests."""
from __future__ import annotations

from tools.kinglet_spike.unity.receipt import unity_receipt_from_dict


def receipt(route: str) -> dict:
    return {
        "schema": "kinglet.unity-probe.receipt/v1",
        "route": route,
        "project_id": "kinglet-unity-probe",
        "unity_version": "6000.3.11f1",
        "compile": {"status": "not-run", "errors": 0},
        "tests": {"status": "not-run", "passed": 0, "failed": 0, "skipped": 0},
        "ready": False,
        "collision_refused": False,
        "active_lease": False,
        "descendant_pids": [],
        "artifacts": [],
    }


def passing_receipt(route: str) -> dict:
    value = receipt(route)
    value["compile"] = {"status": "pass", "errors": 0}
    value["tests"] = {"status": "pass", "passed": 1, "failed": 0, "skipped": 0}
    value["ready"] = route == "live-editor-mcp"
    return value


def load(value: object):
    return unity_receipt_from_dict(value)
