"""model.py -- Frozen types for the Unity execution-probe receipt.

Mirrors spikes/platform/unity/contracts/routes-v1.json. These are pure data
shapes; parsing and validation live in receipt.py so the same rules used by
kinglet_spike.load / kinglet_spike.validate (strict-parse, then separate
semantic validation returning Diagnostics) apply here too.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

RECEIPT_SCHEMA: str = "kinglet.unity-probe.receipt/v1"

# The one spelling of a Unity version string: <year>.<major>.<minor><stage><build>
# -- 6000.3.18f1, 6000.0.68f1, 2022.3.62f3. Shape only; no literal version is
# pinned (standing user ruling, recorded in routes-v1.json's notes).
#
# It lived twice, in receipt.py and editor.py, with a comment on the copy
# saying the duplication was deliberate and no test asserting the two agreed.
# They govern the same decision from opposite ends -- editor.py refuses an
# Editor whose version does not parse, receipt.py refuses a RECEIPT whose
# version does not -- so a divergence means a run that was allowed to start
# cannot publish, or worse, the reverse.
UNITY_VERSION_RE = re.compile(r"^\d{4}\.\d+\.\d+(a|b|c|f|p|rc|x)\d+$")

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


# ---------------------------------------------------------------------------
# The contract document's own unbound fields
# ---------------------------------------------------------------------------
#
# routes-v1.json's `receipt_schema`, `project_id`, `routes`, `executing_routes`,
# `compile_statuses`, `test_statuses` and `timings_seconds` are all bound to
# code by test_unity_receipt.py. Its `schema` and its `notes` were not, and the
# final whole-branch review measured the consequence: DELETING ALL SEVEN RULES
# -- including "refuse silent project upgrade" -- left the entire suite green.
# A frozen contract nothing reads is a document, not a contract.

CONTRACT_SCHEMA: str = "kinglet.unity-probe.contract/v1"

# One entry per frozen rule, in the order the contract states them. Each pairs
# a phrase that must survive in the note with the module that enforces it, so
# the binding is not merely "seven strings exist" -- a rule whose enforcement
# point is gone fails too.
#
# The phrases are deliberately the rule's SUBJECT, not a whole sentence: a note
# may be reworded, and this must not turn into a spellchecker. What it must
# refuse is a rule silently disappearing.
CONTRACT_RULES: tuple[tuple[str, str], ...] = (
    ("filesystem never launches Unity", "receipt"),
    ("The three executing routes", "receipt"),
    ("ready=true is exclusive to live-editor-mcp", "receipt"),
    ("collision_refused is same-project-headless's own refusal probe", "receipt"),
    ("active_lease and descendant_pids must be clean on every receipt", "receipt"),
    ("Refuse silent project upgrade", "editor"),
    ("unity_version records whatever Unity version actually produced the run", "receipt"),
)
