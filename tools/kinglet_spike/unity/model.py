"""model.py -- Frozen types for the Unity execution-probe receipt.

Mirrors spikes/platform/unity/contracts/routes-v1.json. These are pure data
shapes; parsing and validation live in receipt.py so the same rules used by
kinglet_spike.load / kinglet_spike.validate (strict-parse, then separate
semantic validation returning Diagnostics) apply here too.
"""
from __future__ import annotations

from dataclasses import dataclass

RECEIPT_SCHEMA: str = "kinglet.unity-probe.receipt/v1"

# The frozen project id every route contract targets (routes-v1.json).
PROJECT_ID: str = "kinglet-unity-probe"

# The four routes proven by plan 00U. "filesystem" never launches Unity; the
# other three do, and are collected below as EXECUTING_ROUTES.
ROUTES: frozenset[str] = frozenset((
    "filesystem",
    "live-editor-mcp",
    "same-project-headless",
    "isolated-headless",
))

EXECUTING_ROUTES: frozenset[str] = ROUTES - {"filesystem"}

# compile.status and tests.status share the same three-value vocabulary.
STATUS_VALUES: frozenset[str] = frozenset(("not-run", "pass", "fail"))


@dataclass(frozen=True)
class CompileResult:
    status: str
    errors: int


@dataclass(frozen=True)
class TestResult:
    status: str
    passed: int
    failed: int
    skipped: int


@dataclass(frozen=True)
class UnityReceipt:
    schema: str
    route: str
    project_id: str
    unity_version: str
    compile: CompileResult
    tests: TestResult
    ready: bool
    collision_refused: bool
    active_lease: bool
    descendant_pids: tuple[int, ...]
    artifacts: tuple[str, ...]
