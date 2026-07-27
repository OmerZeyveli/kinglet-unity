"""client_support.py — Shared fixtures for client probe tests.

Frozen case IDs and a valid_observations() helper used across
tests/kinglet_spike/test_client_results.py.
"""
from __future__ import annotations

CASE_IDS = (
    "install.discover", "install.update", "install.remove",
    "workflow.natural-language", "instructions.project", "agents.delegation",
    "hooks.pre-mutation-block", "executable.local", "mcp.discover-call",
    "scope.project-user", "approvals.mutation", "structured-result",
)
CASES = tuple({"id": case_id} for case_id in CASE_IDS)


def valid_observations() -> dict:
    return {
        "schema": "kinglet.client-probe.observations/v1",
        "subject": "claude-code",
        "client_version": "2.1.206",
        "cases": [{
            "id": case_id,
            "advertised": True,
            "observed": "fixed synthetic behavior observed",
            "grade": "Native",
            "status": "pass",
            "source_urls": ["https://code.claude.com/docs/en/discover-plugins"],
            "artifact_paths": [f"artifacts/client/claude-code/run-01/{case_id}.json"],
            "notes": "",
            "emulation_mechanism": None,
        } for case_id in CASE_IDS],
    }
