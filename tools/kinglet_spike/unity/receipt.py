"""receipt.py -- Load, strictly validate, and convert Unity execution-probe receipts.

Public API
----------
load_unity_receipt(path)                  Path -> UnityReceipt
unity_receipt_from_dict(value)            dict -> UnityReceipt   (raises EvidenceError)
validate_unity_receipt(receipt)           UnityReceipt -> tuple[Diagnostic, ...]
verify_cited_isolation_manifest(r, root)  -> IsolationManifest    (raises EvidenceError)
receipt_to_evidence(receipt, environment) -> EvidenceRecord

Two receipt schemas
-------------------
`kinglet.unity-probe.receipt/v2` is current; `/v1` is LEGACY -- readable,
never written, and not publishable. The difference is one mandatory field:
under v2 an `isolated-headless` receipt must cite the isolation manifest that
proves the two workspaces are physically separate. Before that, an
`isolated-headless` receipt and a `same-project-headless` receipt were
byte-identical apart from the route label; the runtime check was real and the
published document encoded none of it.

v1 survives because eight published records were made under it and are
immutable -- regenerating them means re-running Unity. It is never upgraded
(the v2 field is an unknown field on a v1 document) and never republished
(`receipt_to_evidence` refuses it), so "emit v1" is not a way around the rule.
See model.RECEIPT_SCHEMA_V1 / _V2 and the isolated-headless note in
routes-v1.json.

Two-stage validation, matching the house style in tools/kinglet_spike/load.py
and tools/kinglet_spike/client_results.py:

* unity_receipt_from_dict() is STRUCTURAL. It raises EvidenceError the moment
  a document does not conform to the shape in
  spikes/platform/unity/contracts/routes-v1.json -- wrong schema, an unknown
  field, a wrong type, or an enum value (route, compile.status, tests.status)
  outside the frozen set. There is nothing to "diagnose" here: a document
  that fails this stage is not a receipt at all.

* validate_unity_receipt() is SEMANTIC. It takes an already-well-formed
  UnityReceipt and returns a (possibly empty) tuple of Diagnostic, never
  raising. This is where the honesty properties of the 00U plan's global
  constraints are enforced -- the ones that are true of an assembled receipt
  and cannot be checked field-by-field during parsing:

    - "ready" is exclusive to live-editor-mcp (only that route defines MCP
      Editor readiness; a running MCP server is not itself an Editor-ready
      state per the plan's global constraints).
    - "filesystem" never launches Unity, so it must not claim compile or
      test results -- both fields must stay "not-run".
    - The three executing routes may not claim tests.status="pass" without
      at least one observed passing test (passed >= 1), and may not claim
      tests.status="fail" with failed=0 -- a status claim must be backed by
      the counts that justify it.
    - collision_refused is same-project-headless's own refusal probe (matrix
      cell same-project-headless.collision-refusal). It is not a successful
      headless run: it may only be true on that one route, and when it is
      true the route never launched Unity, so compile/tests must both stay
      "not-run".
    - active_lease and descendant_pids must be clean (false / empty) on
      EVERY receipt, not only passing ones. The plan's global constraint is
      unconditional: "Cancellation, timeout, crash, and success must leave
      no Unity, MCP helper, or child process and no live lease owned by that
      route." A receipt is only ever written after that teardown, so there
      is no outcome for which a live lease or a live descendant is honest.
    - project_id is pinned by routes-v1.json.
    - unity_version must be a well-formed Unity version string. The plan's
      literal `6000.3.11f1` pin is RELAXED by standing user ruling: this
      host has 6000.3.18f1, 6000.0.68f1, and 2022.3.62f3 installed, and any
      well-formed Unity 6000.x or 2022.x release string is accepted. What is
      NOT relaxed is that the receipt must carry whatever version actually
      produced the run -- this function only checks shape, never a pinned
      literal, precisely so a receipt is never forced to lie about which
      Editor ran it.
    - artifact paths must be safe, relative paths (no absolute path, no
      backslash, no ".." component) -- the brief requires every committed
      artifact path to resolve underneath docs/research/platform-spike/.
    - (v2) route="isolated-headless" must cite an isolation manifest, that
      citation must be a safe relative path, and it must ALSO appear in
      `artifacts` -- a reader fetches artifacts, not free-text fields. No
      other route may cite one.

* verify_cited_isolation_manifest() is the half that needs a FILESYSTEM, and
  it RAISES. Requiring a field to be present would be nearly worthless: an
  empty or invented value satisfies presence. This resolves the citation
  under the record's artifact root, refuses if nothing is there, parses the
  manifest strictly, and judges its contents -- distinct 64-hex workspace
  identities (the `(st_dev, st_ino)` digests that catch a bind-mounted fake
  copy, which no path comparison can), distinct path hashes, the frozen tree
  list, a non-empty inventory, and a `tree_sha256` matching that inventory.
  There is no "could not tell" outcome; every path that is not observed proof
  is a refusal.
"""
from __future__ import annotations

import datetime
import json
import re
from pathlib import Path, PureWindowsPath
from typing import Any

from ..model import (
    AssertionResult,
    Diagnostic,
    Environment,
    EvidenceError,
    EvidenceRecord,
    Probe,
    Subject,
)
from .isolation import (
    assert_manifest_self_consistent,
    isolation_manifest_from_dict,
)
from .model import (
    EXECUTING_ROUTES,
    ISOLATED_HEADLESS_ROUTE,
    LEGACY_RECEIPT_SCHEMAS,
    PROJECT_ID,
    RECEIPT_SCHEMA,
    RECEIPT_SCHEMA_V2,
    ROUTES,
    STATUS_VALUES,
    SUPPORTED_RECEIPT_SCHEMAS,
    UNITY_VERSION_RE,
    CompileResult,
    TestResult,
    UnityReceipt,
)

EVIDENCE_SCHEMA = "kinglet.spike.evidence/v1"

# IMPORTED from model, not respelled -- see model.UNITY_VERSION_RE. Shape-only;
# see this module's docstring on why no exact literal is pinned.
_UNITY_VERSION_RE = UNITY_VERSION_RE

_RECEIPT_FIELDS_V1 = frozenset((
    "schema",
    "route",
    "project_id",
    "unity_version",
    "compile",
    "tests",
    "ready",
    "collision_refused",
    "active_lease",
    "descendant_pids",
    "artifacts",
))
# v2 = v1 + the mandatory isolation-manifest citation. The two field sets are
# kept apart so a v1 document carrying `isolation_manifest` is an UNKNOWN
# FIELD rather than a quietly upgraded v2 one: v1 receipts were published
# before this rule existed, and a v1 document that could grow the field would
# be a v2 receipt wearing a v1 label.
_RECEIPT_FIELDS_V2 = _RECEIPT_FIELDS_V1 | {"isolation_manifest"}
_RECEIPT_FIELDS_BY_SCHEMA = {
    schema: (_RECEIPT_FIELDS_V2 if schema == RECEIPT_SCHEMA_V2 else _RECEIPT_FIELDS_V1)
    for schema in SUPPORTED_RECEIPT_SCHEMAS
}
_COMPILE_FIELDS = frozenset(("status", "errors"))
_TESTS_FIELDS = frozenset(("status", "passed", "failed", "skipped"))


# ---------------------------------------------------------------------------
# Structural parsing helpers
# ---------------------------------------------------------------------------

def _object(value: Any, path: str) -> dict:
    if not isinstance(value, dict):
        raise EvidenceError("E_FIELD", f"{path} must be an object")
    return value


def _string(value: Any, path: str) -> str:
    if not isinstance(value, str):
        raise EvidenceError("E_FIELD", f"{path} must be a string")
    return value


def _boolean(value: Any, path: str) -> bool:
    if type(value) is not bool:
        raise EvidenceError("E_FIELD", f"{path} must be a boolean")
    return value


def _integer(value: Any, path: str) -> int:
    if type(value) is not int or type(value) is bool:
        raise EvidenceError("E_FIELD", f"{path} must be an integer")
    return value


def _int_array(value: Any, path: str) -> tuple[int, ...]:
    if not isinstance(value, list):
        raise EvidenceError("E_FIELD", f"{path} must be an array")
    return tuple(_integer(item, f"{path}[{index}]") for index, item in enumerate(value))


def _string_array(value: Any, path: str) -> tuple[str, ...]:
    if not isinstance(value, list):
        raise EvidenceError("E_FIELD", f"{path} must be an array")
    return tuple(_string(item, f"{path}[{index}]") for index, item in enumerate(value))


def _unknown_fields(raw: dict, allowed: frozenset[str], path: str) -> None:
    unknown = sorted(raw.keys() - allowed)
    if unknown:
        raise EvidenceError("E_FIELD", f"{path}.{unknown[0]} is an unknown field")


def _compile(value: Any, path: str) -> CompileResult:
    item = _object(value, path)
    _unknown_fields(item, _COMPILE_FIELDS, path)
    status = _string(item.get("status", ""), f"{path}.status")
    if status not in STATUS_VALUES:
        raise EvidenceError("E_ENUM", f"{path}.status has unsupported value: {status!r}")
    errors = _integer(item.get("errors", None), f"{path}.errors")
    if errors < 0:
        raise EvidenceError("E_FIELD", f"{path}.errors must not be negative")
    return CompileResult(status=status, errors=errors)


def _tests(value: Any, path: str) -> TestResult:
    item = _object(value, path)
    _unknown_fields(item, _TESTS_FIELDS, path)
    status = _string(item.get("status", ""), f"{path}.status")
    if status not in STATUS_VALUES:
        raise EvidenceError("E_ENUM", f"{path}.status has unsupported value: {status!r}")
    passed = _integer(item.get("passed", None), f"{path}.passed")
    failed = _integer(item.get("failed", None), f"{path}.failed")
    skipped = _integer(item.get("skipped", None), f"{path}.skipped")
    for name, count in (("passed", passed), ("failed", failed), ("skipped", skipped)):
        if count < 0:
            raise EvidenceError("E_FIELD", f"{path}.{name} must not be negative")
    return TestResult(status=status, passed=passed, failed=failed, skipped=skipped)


# ---------------------------------------------------------------------------
# Public parsing API
# ---------------------------------------------------------------------------

def unity_receipt_from_dict(value: object) -> UnityReceipt:
    """Strictly parse a Unity execution-probe receipt (v1 legacy, v2 current).

    Raises EvidenceError (E_FIELD / E_SCHEMA / E_ENUM) on any structural
    violation. See the module docstring for the split between this function
    and validate_unity_receipt().
    """
    item = _object(value, "receipt")

    # The schema is read BEFORE the unknown-field sweep, because which fields
    # are known IS a property of the schema. Reading them the other way round
    # would either reject a legitimate v2 field or accept it on a v1 document.
    schema = _string(item.get("schema", ""), "receipt.schema")
    if schema not in SUPPORTED_RECEIPT_SCHEMAS:
        raise EvidenceError("E_SCHEMA", f"unsupported receipt schema: {schema!r}")
    _unknown_fields(item, _RECEIPT_FIELDS_BY_SCHEMA[schema], "receipt")

    isolation_manifest: str | None = None
    if schema == RECEIPT_SCHEMA_V2 and item.get("isolation_manifest") is not None:
        isolation_manifest = _string(
            item["isolation_manifest"], "receipt.isolation_manifest"
        )

    route = _string(item.get("route", ""), "receipt.route")
    if route not in ROUTES:
        raise EvidenceError("E_ENUM", f"receipt.route has unsupported value: {route!r}")

    project_id = _string(item.get("project_id", ""), "receipt.project_id")
    unity_version = _string(item.get("unity_version", ""), "receipt.unity_version")

    compile_result = _compile(item.get("compile"), "receipt.compile")
    tests_result = _tests(item.get("tests"), "receipt.tests")

    ready = _boolean(item.get("ready", None), "receipt.ready")
    collision_refused = _boolean(item.get("collision_refused", None), "receipt.collision_refused")
    active_lease = _boolean(item.get("active_lease", None), "receipt.active_lease")
    descendant_pids = _int_array(item.get("descendant_pids", None), "receipt.descendant_pids")
    artifacts = _string_array(item.get("artifacts", None), "receipt.artifacts")

    return UnityReceipt(
        schema=schema,
        route=route,
        project_id=project_id,
        unity_version=unity_version,
        compile=compile_result,
        tests=tests_result,
        ready=ready,
        collision_refused=collision_refused,
        active_lease=active_lease,
        descendant_pids=descendant_pids,
        artifacts=artifacts,
        isolation_manifest=isolation_manifest,
    )


def load_unity_receipt(path: Path) -> UnityReceipt:
    """Load and strictly parse a Unity execution-probe receipt JSON file from disk."""
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError("E_JSON", f"cannot decode {path}: {error}") from error
    return unity_receipt_from_dict(raw)


# ---------------------------------------------------------------------------
# Semantic validation
# ---------------------------------------------------------------------------

def _is_safe_relative_artifact_path(value: str) -> bool:
    """True iff value is a relative, non-escaping path (no '..', no absolute form).

    PureWindowsPath("C:foo.txt").is_absolute() is False -- "C:foo.txt" is
    drive-RELATIVE (relative to the current directory on drive C:), not
    drive-absolute ("C:\\foo.txt" would be). is_absolute() alone therefore
    lets a drive-qualified path through. Windows is a real target host for
    this toolkit, so any path carrying a drive letter is rejected outright,
    absolute or not.
    """
    if not value or "\\" in value:
        return False
    candidate = Path(value)
    windows_candidate = PureWindowsPath(value)
    if candidate.is_absolute() or windows_candidate.is_absolute():
        return False
    if windows_candidate.drive:
        return False
    if ".." in candidate.parts or ".." in windows_candidate.parts:
        return False
    return True


def validate_unity_receipt(receipt: UnityReceipt) -> tuple[Diagnostic, ...]:
    """Semantically validate an already-parsed UnityReceipt.

    Returns a tuple of Diagnostic (empty when the receipt is honest). Never
    raises -- callers decide what to do with the diagnostics, same as
    tools.kinglet_spike.validate.validate_record().
    """
    diagnostics: list[Diagnostic] = []

    # "ready" names MCP Editor readiness, which only live-editor-mcp exposes.
    if receipt.ready and receipt.route != "live-editor-mcp":
        diagnostics.append(Diagnostic(
            "E_ASSERTION",
            "ready",
            f"route {receipt.route!r} must not report ready=true; only "
            "live-editor-mcp defines MCP Editor readiness",
        ))

    # filesystem never launches Unity.
    if receipt.route == "filesystem":
        if receipt.compile.status != "not-run":
            diagnostics.append(Diagnostic(
                "E_ASSERTION",
                "compile.status",
                "route filesystem must report compile.status=not-run; it never launches Unity",
            ))
        if receipt.tests.status != "not-run":
            diagnostics.append(Diagnostic(
                "E_ASSERTION",
                "tests.status",
                "route filesystem must report tests.status=not-run; it never launches Unity",
            ))

    # Executing routes actually launch Unity, so compile is always attempted:
    # "not-run" is only honest when the route refused to launch at all
    # (collision_refused=true, handled separately below). Without this, the
    # bare default receipt() fixture -- compile=not-run, tests=not-run, every
    # count 0 -- validates clean for a route that ran nothing and never says
    # so; receipt_to_evidence would then stamp it "pass".
    if receipt.route in EXECUTING_ROUTES and not receipt.collision_refused:
        if receipt.compile.status == "not-run":
            diagnostics.append(Diagnostic(
                "E_ASSERTION",
                "compile.status",
                f"route {receipt.route!r} launches Unity, so compile.status must "
                "not be not-run unless collision_refused=true",
            ))

    # Executing routes: a status claim must be backed by the counts.
    if receipt.route in EXECUTING_ROUTES:
        if receipt.tests.status == "pass" and receipt.tests.passed < 1:
            diagnostics.append(Diagnostic(
                "E_ASSERTION",
                "tests.passed",
                "route reports tests.status=pass but passed=0; a pass requires "
                "at least one observed passing test",
            ))
        if receipt.tests.status == "pass" and receipt.tests.failed != 0:
            diagnostics.append(Diagnostic(
                "E_ASSERTION",
                "tests.failed",
                "route reports tests.status=pass but failed>0",
            ))
        if receipt.tests.status == "pass" and receipt.tests.skipped != 0:
            diagnostics.append(Diagnostic(
                "E_ASSERTION",
                "tests.skipped",
                "route reports tests.status=pass but skipped>0; the frozen "
                "contract requires skipped=0 for a passing run",
            ))
        if receipt.tests.status == "fail" and receipt.tests.failed < 1:
            diagnostics.append(Diagnostic(
                "E_ASSERTION",
                "tests.failed",
                "route reports tests.status=fail but failed=0; a fail requires "
                "at least one observed failing test",
            ))

    # A passing compile claim must be backed by zero reported errors, and a
    # failing one must cite at least one -- the same "claim needs a count"
    # discipline already applied to tests above.
    if receipt.compile.status == "pass" and receipt.compile.errors != 0:
        diagnostics.append(Diagnostic(
            "E_ASSERTION",
            "compile.errors",
            "route reports compile.status=pass but errors>0",
        ))
    if receipt.compile.status == "fail" and receipt.compile.errors < 1:
        diagnostics.append(Diagnostic(
            "E_ASSERTION",
            "compile.errors",
            "route reports compile.status=fail but errors=0; a fail requires "
            "at least one observed compile error",
        ))

    # Tests cannot pass without a successful compile -- this links the two
    # fields the plan's route contract always states together
    # ("compile.status=pass, tests.status=pass, ..."), and it is what keeps
    # receipt_to_evidence from emitting a record whose own assertions
    # contradict each other (tests pass while compile is reported failed).
    if receipt.tests.status == "pass" and receipt.compile.status != "pass":
        diagnostics.append(Diagnostic(
            "E_ASSERTION",
            "tests.status",
            "route reports tests.status=pass but compile.status is "
            f"{receipt.compile.status!r}; tests cannot pass without a "
            "successful compile",
        ))

    # live-editor-mcp's tests only ran through a bridge whose readiness the
    # receipt itself must attest to. Claiming a passing test run without
    # ready=true asserts execution nobody confirmed was ready for tools.
    if receipt.route == "live-editor-mcp" and receipt.tests.status == "pass" and not receipt.ready:
        diagnostics.append(Diagnostic(
            "E_ASSERTION",
            "ready",
            "route live-editor-mcp reports tests.status=pass but ready=false; "
            "a passing test claim through this route requires MCP Editor "
            "readiness (ready_for_tools=true)",
        ))

    # collision_refused is same-project-headless's own refusal probe -- it is
    # not a successful headless run.
    if receipt.collision_refused:
        if receipt.route != "same-project-headless":
            diagnostics.append(Diagnostic(
                "E_ASSERTION",
                "collision_refused",
                f"route {receipt.route!r} must not report collision_refused=true; "
                "collision refusal only applies to same-project-headless",
            ))
        if receipt.compile.status != "not-run" or receipt.tests.status != "not-run":
            diagnostics.append(Diagnostic(
                "E_ASSERTION",
                "collision_refused",
                "a refused collision never launched Unity; compile and tests "
                "must both stay not-run",
            ))

    # Process/lease cleanliness is unconditional -- true of every outcome,
    # not only a passing one.
    if receipt.active_lease:
        diagnostics.append(Diagnostic(
            "E_ASSERTION",
            "active_lease",
            "a receipt must never be emitted while a lease is still active",
        ))
    if receipt.descendant_pids:
        diagnostics.append(Diagnostic(
            "E_ASSERTION",
            "descendant_pids",
            "a receipt must never be emitted with live descendant processes: "
            f"{list(receipt.descendant_pids)}",
        ))

    if receipt.project_id != PROJECT_ID:
        diagnostics.append(Diagnostic(
            "E_FIELD",
            "project_id",
            f"project_id must be {PROJECT_ID!r}, got {receipt.project_id!r}",
        ))

    if not _UNITY_VERSION_RE.fullmatch(receipt.unity_version):
        diagnostics.append(Diagnostic(
            "E_FIELD",
            "unity_version",
            f"unity_version {receipt.unity_version!r} is not a well-formed Unity "
            "version string",
        ))

    # --- the isolation claim must come with its proof (receipt/v2) ---------
    #
    # A `same-project-headless` receipt and an `isolated-headless` receipt used
    # to be byte-identical apart from the route label. `assert_isolated` really
    # does compare `(st_dev, st_ino)` -- the one thing `realpath` cannot do, so
    # a bind-mounted fake copy is caught -- but none of that reached the
    # published document, so a reader had the label and no way to check it.
    #
    # Requiring a FIELD would be nearly worthless: an empty or invented value
    # satisfies presence. So the citation must name a path that also appears in
    # `artifacts` (a reader fetches artifacts, not free-text fields), and the
    # file behind it is resolved and judged by
    # `verify_cited_isolation_manifest`, which needs a filesystem and therefore
    # cannot live in this pure function.
    if receipt.route == ISOLATED_HEADLESS_ROUTE and receipt.schema == RECEIPT_SCHEMA_V2:
        if not receipt.isolation_manifest:
            diagnostics.append(Diagnostic(
                "E_ASSERTION",
                "isolation_manifest",
                "route isolated-headless must cite the isolation manifest that "
                "proves the two workspaces are physically separate; without it "
                "this receipt differs from a same-project-headless receipt only "
                "by its label",
            ))
        elif not _is_safe_relative_artifact_path(receipt.isolation_manifest):
            diagnostics.append(Diagnostic(
                "E_PATH",
                "isolation_manifest",
                "the cited isolation manifest must be a safe path relative to "
                f"docs/research/platform-spike/: {receipt.isolation_manifest!r}",
            ))
        elif receipt.isolation_manifest not in receipt.artifacts:
            diagnostics.append(Diagnostic(
                "E_ASSERTION",
                "isolation_manifest",
                f"the cited isolation manifest {receipt.isolation_manifest!r} is "
                "not among this receipt's artifacts, so nothing published beside "
                "the record carries the isolation proof",
            ))
    if receipt.isolation_manifest is not None and receipt.route != ISOLATED_HEADLESS_ROUTE:
        diagnostics.append(Diagnostic(
            "E_ASSERTION",
            "isolation_manifest",
            f"route {receipt.route!r} must not cite an isolation manifest; only "
            "isolated-headless makes a physical-separation claim",
        ))

    for index, artifact_path in enumerate(receipt.artifacts):
        if not _is_safe_relative_artifact_path(artifact_path):
            diagnostics.append(Diagnostic(
                "E_PATH",
                f"artifacts[{index}]",
                "artifact path must be a safe path relative to "
                f"docs/research/platform-spike/: {artifact_path!r}",
            ))

    return tuple(sorted(diagnostics))


# ---------------------------------------------------------------------------
# Auditing the cited isolation manifest -- the half that needs a filesystem
# ---------------------------------------------------------------------------

def verify_cited_isolation_manifest(receipt: UnityReceipt, artifact_root) -> object:
    """Resolve and judge the isolation manifest `receipt` cites. Or refuse.

    `artifact_root` is the directory the receipt's artifact paths are relative
    to -- the published record's own root, so
    `artifact_root / receipt.isolation_manifest` is exactly the file a reader
    would fetch.

    RAISES rather than returning diagnostics, and there is no third answer.
    Every path out of this function that is not a positive, observed proof is a
    refusal: a legacy receipt (which cites nothing) is refused, a receipt from
    another route is refused, a citation with no file behind it is refused, a
    file that will not decode is refused, and a manifest whose own contents do
    not describe an isolated copy is refused. "I could not tell" must never
    reach the permissive answer -- that is the exact defect this plan keeps
    re-learning, and the cost of it here is a published isolation claim nobody
    checked.

    Returns the parsed `IsolationManifest` on success.
    """
    if receipt.schema in LEGACY_RECEIPT_SCHEMAS:
        raise EvidenceError(
            "E_UNITY_ISOLATION_MANIFEST",
            f"receipt schema {receipt.schema!r} predates the mandatory "
            "isolation manifest: it carries no citation, so its isolation "
            "claim cannot be audited from the published bytes",
        )
    if receipt.route != ISOLATED_HEADLESS_ROUTE:
        raise EvidenceError(
            "E_UNITY_ISOLATION_MANIFEST",
            f"route {receipt.route!r} makes no physical-separation claim; there "
            "is no isolation manifest to audit",
        )
    cited = receipt.isolation_manifest
    if not cited:
        raise EvidenceError(
            "E_UNITY_ISOLATION_MANIFEST",
            "the receipt cites no isolation manifest",
        )
    if not _is_safe_relative_artifact_path(cited):
        raise EvidenceError(
            "E_UNITY_ISOLATION_MANIFEST",
            f"the cited isolation manifest is not a safe relative path: {cited!r}",
        )
    if cited not in receipt.artifacts:
        raise EvidenceError(
            "E_UNITY_ISOLATION_MANIFEST",
            f"the cited isolation manifest {cited!r} is not among this "
            "receipt's artifacts",
        )

    root = Path(artifact_root)
    candidate = root / cited
    # Containment is re-checked against the RESOLVED paths, not against the
    # spelling: `_is_safe_relative_artifact_path` rejects a lexical `..`, and a
    # symlink under the artifact root carries a path out of it without one.
    try:
        real_root = root.resolve(strict=True)
        real_candidate = candidate.resolve(strict=True)
    except OSError as error:
        raise EvidenceError(
            "E_UNITY_ISOLATION_MANIFEST",
            f"the cited isolation manifest {cited!r} does not resolve to an "
            f"existing file beneath the artifact root: {error}",
        ) from error
    if real_candidate != real_root and not real_candidate.is_relative_to(real_root):
        raise EvidenceError(
            "E_UNITY_ISOLATION_MANIFEST",
            f"the cited isolation manifest {cited!r} resolves outside the "
            "artifact root; a record may only cite what is published with it",
        )
    if not real_candidate.is_file():
        raise EvidenceError(
            "E_UNITY_ISOLATION_MANIFEST",
            f"the cited isolation manifest {cited!r} is not a regular file",
        )

    try:
        payload = json.loads(real_candidate.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError(
            "E_UNITY_ISOLATION_MANIFEST",
            f"cannot decode the cited isolation manifest {cited!r}: {error}",
        ) from error

    manifest = isolation_manifest_from_dict(payload)
    assert_manifest_self_consistent(manifest)
    return manifest


# ---------------------------------------------------------------------------
# Evidence conversion
# ---------------------------------------------------------------------------

def receipt_to_evidence(receipt: UnityReceipt, environment: Environment) -> EvidenceRecord:
    """Convert a UnityReceipt into one kinglet.spike.evidence/v1 EvidenceRecord.

    subject.kind="unity" (already a recognised SUBJECT_KINDS entry in
    tools.kinglet_spike.load). The record's status is "pass" only when
    validate_unity_receipt() finds nothing to report; any diagnostic --
    honesty violation or otherwise -- demotes the record to "fail", mirroring
    the rule that a receipt which cannot pass its own contract cannot close a
    coverage cell.

    This function performs no I/O and launches nothing; started_at/ended_at
    are stamped at conversion time because the receipt itself carries no
    timestamps (see routes-v1.json / the brief's receipt shape). The caller
    (a future task's route runner) is expected to call this immediately after
    building the receipt, not long after.

    command, measurements, and sources are intentionally empty/absent here --
    Task 1 freezes the contract and does not launch Unity, so there is no
    real command line or provenance URL to cite yet. A later task that
    actually runs a route is expected to populate them before publishing.
    """
    diagnostics = validate_unity_receipt(receipt)

    # A legacy receipt is READABLE but not PUBLISHABLE. This is the only
    # receipt -> published-record conversion in the tree, so it is the only
    # place the downgrade route can be closed: without it, a producer that did
    # not want to attach an isolation manifest could simply stamp
    # `kinglet.unity-probe.receipt/v1` and keep every other rule. Nothing in
    # the committed evidence was built this way, so closing it costs no
    # published byte.
    legacy: tuple[Diagnostic, ...] = ()
    if receipt.schema in LEGACY_RECEIPT_SCHEMAS:
        legacy = (Diagnostic(
            "E_SCHEMA",
            "schema",
            f"{receipt.schema} is legacy: it predates the mandatory isolation "
            f"manifest and cannot back a NEW published record. Emit "
            f"{RECEIPT_SCHEMA} instead.",
        ),)
    diagnostics = tuple(sorted(diagnostics + legacy))
    status = "pass" if not diagnostics else "fail"

    now = datetime.datetime.now(tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    stamp = now.replace("-", "").replace(":", "")
    run_id = f"{stamp}-unity-probe-{receipt.route}-01"

    # "not-run" is only an honest pass for filesystem, which never launches
    # Unity. On every other route "not-run" means the route claims nothing
    # happened, which is never a pass claim -- mapping it to "pass" here is
    # exactly the bug that let an executing route which ran nothing convert
    # to a passing EvidenceRecord (see CRITICAL 1 in the round-1 review).
    compile_ok = receipt.compile.status == "pass" or (
        receipt.route == "filesystem" and receipt.compile.status == "not-run"
    )
    tests_ok = receipt.tests.status == "pass" or (
        receipt.route == "filesystem" and receipt.tests.status == "not-run"
    )

    assertions = (
        AssertionResult(
            id="compile",
            status="pass" if compile_ok else "fail",
            detail=f"status={receipt.compile.status} errors={receipt.compile.errors}",
        ),
        AssertionResult(
            id="tests",
            status="pass" if tests_ok else "fail",
            detail=(
                f"status={receipt.tests.status} passed={receipt.tests.passed} "
                f"failed={receipt.tests.failed} skipped={receipt.tests.skipped}"
            ),
        ),
        AssertionResult(
            id="contract",
            status="pass" if not diagnostics else "fail",
            detail=(
                f"receipt satisfies {receipt.schema}"
                if not diagnostics
                else "; ".join(f"{d.code} {d.location}: {d.message}" for d in diagnostics)
            ),
        ),
    )

    return EvidenceRecord(
        schema=EVIDENCE_SCHEMA,
        run_id=run_id,
        subject=Subject(kind="unity", id=receipt.project_id, version=receipt.unity_version),
        probe=Probe(id=receipt.route, contract=RECEIPT_SCHEMA),
        environment=environment,
        started_at=now,
        ended_at=now,
        status=status,
        command=(),
        artifacts=(),
        assertions=assertions,
        measurements=(),
        sources=(),
        prompt=None,
    )
