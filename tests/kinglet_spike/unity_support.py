"""unity_support.py -- Shared fixtures for Unity execution-probe receipt tests."""
from __future__ import annotations

from tools.kinglet_spike.unity.model import (
    ISOLATED_HEADLESS_ROUTE,
    RECEIPT_SCHEMA,
    RECEIPT_SCHEMA_V1,
)
from tools.kinglet_spike.unity.receipt import unity_receipt_from_dict

# The manifest path an isolated-headless receipt cites, spelled the way the
# route itself spells it (routes.ARTIFACT_PREFIX / routes.ISOLATED_MANIFEST_NAME).
ISOLATION_MANIFEST_ARTIFACT = "artifacts/unity/isolated-headless-manifest.json"


def receipt(route: str) -> dict:
    """A current-schema (v2) receipt for `route`.

    An `isolated-headless` receipt carries the mandatory isolation-manifest
    citation, because under v2 there is no such thing as an isolated-headless
    receipt without one.
    """
    value = {
        "schema": RECEIPT_SCHEMA,
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
    if route == ISOLATED_HEADLESS_ROUTE:
        value["isolation_manifest"] = ISOLATION_MANIFEST_ARTIFACT
        value["artifacts"] = [ISOLATION_MANIFEST_ARTIFACT]
    return value


def legacy_receipt(route: str) -> dict:
    """A v1 receipt -- the shape the eight published records were made under.

    v1 has no `isolation_manifest` field at all; adding one is an unknown
    field, which is how a v1 document is kept from being read as a v2 one.
    """
    value = receipt(route)
    value["schema"] = RECEIPT_SCHEMA_V1
    value.pop("isolation_manifest", None)
    return value


def passing_receipt(route: str) -> dict:
    value = receipt(route)
    value["compile"] = {"status": "pass", "errors": 0}
    value["tests"] = {"status": "pass", "passed": 1, "failed": 0, "skipped": 0}
    value["ready"] = route == "live-editor-mcp"
    return value


def load(value: object):
    return unity_receipt_from_dict(value)
