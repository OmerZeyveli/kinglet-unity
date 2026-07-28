"""routes.py -- The `filesystem`, `same-project-headless` and `live-editor-mcp` routes.

Three routes, one honesty rule
------------------------------
`filesystem` never launches anything. It reads the project's own committed
text, checksums it, and reports `compile=not-run` / `tests=not-run`. That is
the whole claim: "these bytes are here and they say this". Task 1's validator
already refuses any other claim from this route.

`same-project-headless` launches the real Editor against the real project and
must therefore answer a much harder question: did tests actually run, and did
they pass? Three measured facts on this host decide how it answers.

MEASURED FACT 1 -- `-quit` and `-runTests` are mutually destructive.
With `-quit` in the argv, Unity honours the quit first: the log says
`Batchmode quit successfully invoked - shutting down!`, the process **exits 0**,
and **no `results.xml` is ever written**. So `exit == 0` is NOT evidence that
tests ran. The task brief's literal argv listed `-quit`; this module
deliberately omits it (see `_headless_argv`), because with it the route can
only ever produce a receipt it cannot back. Nothing else in the brief's argv
changed.

MEASURED FACT 2 -- exit codes are DISJOINT, and 1 writes no results at all.
  0 -> tests passed, `results.xml` present
  1 -> compile error; **no `results.xml` is written**, and the log carries
       `error CS...` plus `Aborting batchmode due to failure: Scripts have
       compiler errors.`
  2 -> test failure; `results.xml` present with `result="Failed(Child)"`
They are never collapsed into "non-zero" here. Because a compile error writes
no results file at all, the contract's `compile=fail` + `tests=pass`
combination is physically impossible on this route -- routes-v1.json already
rejects it, and `_derive_outcome` cannot construct it.

MEASURED FACT 3 -- `Temp/UnityLockfile` appears within ~2s of launch even in
batchmode, and is REMOVED on clean exit. A lockfile still present after the
run means crash or kill, not normal operation, so a claimed pass is
cross-checked against its absence.

What "could not tell" means here
--------------------------------
Task 3's defect was a safety path with no ambiguity branch, so every case it
could not resolve fell through to the permissive answer. The receipt
vocabulary (`not-run` / `pass` / `fail`) has no "unknown" value, and inventing
one by mapping ambiguity onto `not-run` would produce a receipt that reads as
"this route never ran" for a route that ran and whose outcome nobody
established. So this module RAISES instead of emitting a receipt it cannot
back:

* results file absent AND no compile error in the log -> `E_UNITY_RESULTS_MISSING`
  (this is the `-quit` shape, and also the timeout/cancel shape)
* results file present AND compile errors in the log -> `E_UNITY_RESULTS_CONFLICT`
  (physically impossible per fact 2; something is not what we think it is)
* a results file that ran tests but recorded neither a pass nor a failure
  (all skipped, or inconclusive) -> `E_UNITY_RESULTS_UNRESOLVED`
* a derived outcome that contradicts the exit code -> `E_UNITY_EXIT_CONFLICT`

Every one of those still runs the full `finally`: cancel the containment,
prove the survivor set, release the lease.

The ordering is structural, not documented
------------------------------------------
`assert_headless_safe` -> `verify_project_editor` -> `acquire` -> `start` +
`bind_holder` -> `cancel` -> `release`. Task 4's reviewer found nothing forced
that order, and that it is load-bearing rather than tidy: until `bind_holder`
runs, the lease names only the controller, and `ManagedProcess.start` puts
Unity in its own session on purpose, so a controller crash in that window
leaves a live Unity under a lease that becomes reclaimable at TTL -- a
double-open, the exact thing the lease exists to prevent.

So every route runs through a private guarded path -- `_run_headless_guarded`,
`_live_mcp_guarded`, `_run_isolated_guarded`, one per executing route, none of
them exported -- and `_start_bound()` is the ONLY way any of them launches: it
starts and binds in one call and cancels the process if the bind fails, so
"started but never bound" is not a state a caller can reach by forgetting a
line. See `_start_bound`'s docstring for the residual window that cannot be
closed from inside this process.

(This paragraph read "there is exactly one guarded path" until the final
whole-branch review. Task 7 added `_run_isolated_guarded` -- correctly, and it
enforces the same ordering -- but the sentence was left behind, and a docstring
that undercounts the launch paths is how the next reader concludes there is
nothing else to check. `_run_prefs_pass` was the real instance of that: it
launched a batchmode Editor on the physical project through `process_factory`
directly, and both this paragraph and the count above said it could not.)

`_start_bound` and `_headless_argv` are private, and `__all__` names the public
surface, because a caller holding either could launch Unity while skipping
ownership detection and Editor verification entirely -- with a duck-typed
object that merely has a `bind_holder` method, which the tests themselves
demonstrate is easy to write. That is not the "forgot a line" failure mode; it
takes deliberate new launch code. It is closed anyway, because the ordering
above is only a guarantee if there is no second door.

The lease is per-WORKSPACE, and so is its directory
---------------------------------------------------
`lease_path_for` keys the lease FILENAME on the project's physical-path hash,
which makes two runs of one project agree on the name -- but only if they also
agree on the DIRECTORY. Deriving that directory from the run directory
(`raw_dir`) made two invocations differing only in `--raw-dir` both acquire
cleanly for the same project: a lock that excluded nobody. `default_lease_dir()`
is host-wide and independent of `raw_dir`; see its docstring.

The ordering trade-off, stated honestly
---------------------------------------
The brief's order is `verify_project_editor` -> `assert_headless_safe`; this
module runs ownership FIRST. That is not guarantee-neutral. `verify_editor`
spawns `<Unity> -version`, which takes seconds, and placing that spawn between
the ownership check and `acquire` widens the staleness of the ownership result
by exactly that much -- a TOCTOU window in which someone else's Editor can open
the project after we cleared it. What the chosen order buys is a cheaper
refusal that never executes the Editor binary at all for a project we are going
to refuse anyway, and a refusal receipt that needs only the project's declared
version. The residual window is covered by the lease (host-wide, above) and by
Unity's own single-Editor-per-project enforcement; it is a deliberate trade, not
an absence of cost.

Ownership refusal is its own probe, not a run
---------------------------------------------
When `assert_headless_safe` refuses (a confirmed live owner, or an ownership
it could not clear), the route returns a receipt with
`collision_refused=true` and `compile`/`tests` both `not-run`. Nothing was
launched, so the receipt carries no Unity pid and no lease. It is the matrix
cell `same-project-headless.collision-refusal`, and Task 1's validator
enforces that it can never also claim a compile or a test result.

`live-editor-mcp` is the third route
------------------------------------
It launches a real GUI Editor and reads its outcome through the pinned MCP
bridge instead of from a file Unity wrote. Everything that makes "the bridge
answered" different from "the expected Editor is ready" lives in `mcp.py`,
including the measured fact that a server with ZERO Editors connected answers
`{"success": true, "instances": []}` and exits 0. See `run_live_editor_mcp`
and the block comment above it for what this route does differently from the
headless one -- most importantly that it has no collision-refusal receipt
(the contract reserves `collision_refused` for `same-project-headless`, so an
ownership refusal here raises) and that it mutates the developer's
EditorPrefs and must put them back.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import time
import xml.etree.ElementTree as ElementTree
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence

from ..model import EvidenceError
from . import mcp as mcp_module
from .editor import read_project_version, verify_project_editor
from .isolation import (
    IsolationManifest,
    assert_isolated,
    manifest_for_copy,
    manifest_to_dict,
    verify_manifest,
)
from .lease import WorkspaceLease, lease_path_for
from .model import PROJECT_ID, RECEIPT_SCHEMA, CompileResult, TestResult, UnityReceipt
from .ownership import assert_headless_safe, detect_gui_owner
from .process import ManagedProcess

# The public surface. `_start_bound` and `_headless_argv` are deliberately
# absent AND underscored: either one lets a caller launch Unity without the
# ownership and Editor-verification steps that precede it on the guarded path.
# `_live_mcp_guarded` and the three live argv builders are absent for the same
# reason: each one launches a real Editor.
__all__ = (
    "FILESYSTEM_ROUTE",
    "SAME_PROJECT_HEADLESS_ROUTE",
    "LIVE_EDITOR_MCP_ROUTE",
    "ISOLATED_HEADLESS_ROUTE",
    "run_live_editor_mcp",
    "run_isolated_headless",
    "main_guard_digest",
    "MAIN_GUARDED_TREES",
    "MAIN_GUARDED_FILES",
    "LEASE_DIR_ENV",
    "default_lease_dir",
    "run_filesystem",
    "run_same_project_headless",
    "receipt_to_dict",
    "inventory_project",
    "read_project_marker",
    "sha256_file",
    "count_compile_errors",
    "log_reports_compile_abort",
    "parse_test_results",
    "unity_lockfile_path",
    "FileFact",
    "ResultsSummary",
)

FILESYSTEM_ROUTE = "filesystem"
SAME_PROJECT_HEADLESS_ROUTE = "same-project-headless"
LIVE_EDITOR_MCP_ROUTE = "live-editor-mcp"
ISOLATED_HEADLESS_ROUTE = "isolated-headless"

# Receipt artifact paths are relative to docs/research/platform-spike/ (see
# receipt.py's _is_safe_relative_artifact_path). The files themselves are
# written into the RAW run directory under .kinglet/local/; only their
# sanitized, publishable names appear in the receipt.
ARTIFACT_PREFIX = "artifacts/unity"

FILESYSTEM_INVENTORY_NAME = "filesystem-inventory.json"
HEADLESS_SUMMARY_NAME = "same-project-headless-summary.json"
HEADLESS_LOG_NAME = "same-project-headless.log"
HEADLESS_RESULTS_NAME = "same-project-headless-results.xml"
HEADLESS_STDOUT_NAME = "same-project-headless.stdout"
HEADLESS_STDERR_NAME = "same-project-headless.stderr"

ISOLATED_SUMMARY_NAME = "isolated-headless-summary.json"
ISOLATED_MANIFEST_NAME = "isolated-headless-manifest.json"
ISOLATED_LOG_NAME = "isolated-headless.log"
ISOLATED_RESULTS_NAME = "isolated-headless-results.xml"
ISOLATED_STDOUT_NAME = "isolated-headless.stdout"
ISOLATED_STDERR_NAME = "isolated-headless.stderr"

LIVE_MCP_SUMMARY_NAME = "live-editor-mcp-summary.json"
LIVE_MCP_SETUP_LOG_NAME = "live-editor-mcp-setup.log"
LIVE_MCP_EDITOR_LOG_NAME = "live-editor-mcp-editor.log"
LIVE_MCP_RESTORE_LOG_NAME = "live-editor-mcp-restore.log"
LIVE_MCP_PREFS_BACKUP_NAME = "live-editor-mcp-prefs-backup.json"

# The files `filesystem` proves are present, and whose checksums it records.
# This is the pinned fixture's shape (Task 2): the two ProjectSettings /
# Packages markers Unity itself needs, plus the probe assembly and its test.
REQUIRED_PROJECT_FILES: tuple[str, ...] = (
    "ProjectSettings/ProjectVersion.txt",
    "Packages/manifest.json",
    "Assets/KingletSpike/Editor/KingletSpike.Editor.asmdef",
    "Assets/KingletSpike/Editor/KingletSpikeProbe.cs",
    "Assets/KingletSpike/Tests/Editor/KingletSpike.Tests.asmdef",
    "Assets/KingletSpike/Tests/Editor/KingletSpikeTests.cs",
)

# The file that must carry the frozen project marker, and nothing else may.
PROJECT_MARKER_FILE = "Assets/KingletSpike/Editor/KingletSpikeProbe.cs"

# Phase budgets summed from routes-v1.json. A headless test run has to get the
# Editor up, import and compile the project, and then run EditMode tests, so
# the wall-clock budget is those three phases and not just the test phase.
# test_unity_routes.py binds these to the contract file so an edit to one
# cannot silently diverge from the other.
HEADLESS_TIMEOUT_PHASES: tuple[str, ...] = (
    "editor_startup",
    "import_compile_ready",
    "edit_mode_tests",
)
HEADLESS_TIMEOUT_SECONDS: float = 780.0

# routes-v1.json timings_seconds.cancellation_cleanup.
CANCELLATION_DEADLINE_SECONDS: float = 15.0

# Override for the host-wide lease directory. Every caller on a host must
# agree on it or the lease excludes nobody -- see default_lease_dir().
LEASE_DIR_ENV: str = "KINGLET_UNITY_LEASE_DIR"


def default_lease_dir() -> Path:
    """The ONE directory every run on this host looks in for a workspace lease.

    This deliberately does NOT derive from the run directory. `lease_path_for`
    keys the lease FILENAME on the SHA-256 of the project's physical path, so
    two runs of the same project agree on the file name -- but only if they
    also agree on the directory. Round-1 review proved the hole: two
    invocations differing only in `--raw-dir` both acquired cleanly for the
    same project, because they never looked in the same place. Nothing then
    stood between them and a double-open except `assert_headless_safe`, which
    needs Unity #1 to have written `Temp/UnityLockfile` (measured: ~2s) or to
    have surfaced in the process table. Inside that window the mutual
    exclusion the lease exists to provide was simply absent -- and the ordering
    guarantee built on top of it read stronger than it was.

    It is also not inside the project: a file under `Assets/` becomes a
    Unity-imported asset, a file anywhere else in the project pollutes the very
    tree `isolated-headless` copies (the copy would inherit a foreign lease),
    and a crashed run's leftover lease must be removable without touching a
    project someone may be working in. That reasoning is `lease.py`'s and is
    unchanged; what is fixed here is only WHICH directory outside the project.

    Host state, not repo content, so it lives where host state lives:
    `$KINGLET_UNITY_LEASE_DIR`, else `$XDG_STATE_HOME/kinglet-unity/leases`,
    else `~/.local/state/kinglet-unity/leases`. A cwd-relative or repo-relative
    default would reintroduce the same hole for any caller run from elsewhere.
    Nothing here is ever committed, and the lease record carries no path -- only
    the hash -- so this directory never accumulates machine paths either.

    The crashed-run consequence is the sharper half: `bind_holder` records the
    contained pgid precisely so a later run can clean up a leaked group. That
    record is worthless if the later run looks in a different directory, which
    is exactly what a per-run lease directory guaranteed.
    """
    override = os.environ.get(LEASE_DIR_ENV)
    if override:
        return Path(override)
    state_home = os.environ.get("XDG_STATE_HOME")
    base = Path(state_home) if state_home else Path.home() / ".local" / "state"
    return base / "kinglet-unity" / "leases"


# ---------------------------------------------------------------------------
# Receipt serialization
# ---------------------------------------------------------------------------

def receipt_to_dict(receipt: UnityReceipt) -> dict:
    """The exact JSON shape `unity_receipt_from_dict` accepts back.

    Kept here rather than in receipt.py so Task 1's frozen surface is not
    edited by a later task; the round trip is asserted in the route tests, so
    the two cannot drift apart unnoticed.
    """
    return {
        "schema": receipt.schema,
        "route": receipt.route,
        "project_id": receipt.project_id,
        "unity_version": receipt.unity_version,
        "compile": {"status": receipt.compile.status, "errors": receipt.compile.errors},
        "tests": {
            "status": receipt.tests.status,
            "passed": receipt.tests.passed,
            "failed": receipt.tests.failed,
            "skipped": receipt.tests.skipped,
        },
        "ready": receipt.ready,
        "collision_refused": receipt.collision_refused,
        "active_lease": receipt.active_lease,
        "descendant_pids": list(receipt.descendant_pids),
        "artifacts": list(receipt.artifacts),
    }


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# filesystem route
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class FileFact:
    """One inspected project file: its project-relative path, size and digest."""

    path: str
    size: int
    sha256: str


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inventory_project(project: Path) -> tuple[FileFact, ...]:
    """Checksum every REQUIRED_PROJECT_FILES entry, or refuse.

    A missing file is `E_UNITY_PROJECT_INCOMPLETE`, never an omitted row:
    an inventory that silently shrinks would let the filesystem route report
    success over a project that has lost its test assembly.
    """
    facts: list[FileFact] = []
    for relative in REQUIRED_PROJECT_FILES:
        target = project / relative
        if not target.is_file():
            raise EvidenceError(
                "E_UNITY_PROJECT_INCOMPLETE",
                f"required project file is missing: {relative}",
            )
        facts.append(FileFact(
            path=relative,
            size=target.stat().st_size,
            sha256=sha256_file(target),
        ))
    return tuple(facts)


def read_project_marker(project: Path) -> str:
    """Read the frozen project id the fixture declares, or refuse.

    The marker is the C# `ProjectId = "..."` constant in KingletSpikeProbe.cs
    -- the same literal Task 2's fixture test binds to `PROJECT_ID`. The
    filesystem route proves it by reading it, not by assuming it.
    """
    target = project / PROJECT_MARKER_FILE
    try:
        text = target.read_text(encoding="utf-8")
    except OSError as error:
        raise EvidenceError(
            "E_UNITY_PROJECT_INCOMPLETE",
            f"cannot read project marker {PROJECT_MARKER_FILE}: {error}",
        ) from error
    needle = f'ProjectId = "{PROJECT_ID}";'
    if needle not in text:
        raise EvidenceError(
            "E_UNITY_PROJECT_MARKER",
            f"{PROJECT_MARKER_FILE} does not declare ProjectId "
            f"{PROJECT_ID!r}; this is not the pinned probe project",
        )
    return PROJECT_ID


def run_filesystem(project, raw_dir) -> UnityReceipt:
    """Inspect the project's committed bytes. Launch nothing.

    Reads the declared Editor version, proves the frozen project marker, and
    checksums every required file into an inventory written under `raw_dir`.
    `compile` and `tests` stay `not-run` because nothing compiled and nothing
    ran -- Task 1's validator rejects this route claiming anything else.
    """
    project = Path(project)
    raw_dir = Path(raw_dir)

    unity_version = read_project_version(project)
    project_id = read_project_marker(project)
    facts = inventory_project(project)

    _write_json(raw_dir / FILESYSTEM_INVENTORY_NAME, {
        "schema": "kinglet.unity-probe.inventory/v1",
        "route": FILESYSTEM_ROUTE,
        "project_id": project_id,
        "unity_version": unity_version,
        "files": [
            {"path": fact.path, "size": fact.size, "sha256": fact.sha256}
            for fact in facts
        ],
    })

    return UnityReceipt(
        schema=RECEIPT_SCHEMA,
        route=FILESYSTEM_ROUTE,
        project_id=project_id,
        unity_version=unity_version,
        compile=CompileResult(status="not-run", errors=0),
        tests=TestResult(status="not-run", passed=0, failed=0, skipped=0),
        ready=False,
        collision_refused=False,
        active_lease=False,
        descendant_pids=(),
        artifacts=(f"{ARTIFACT_PREFIX}/{FILESYSTEM_INVENTORY_NAME}",),
    )


# ---------------------------------------------------------------------------
# Unity log and NUnit result readers
# ---------------------------------------------------------------------------

# Unity prints one `error CS####:` per diagnostic, and repeats each of them
# across the compile summary. Distinct stripped lines are counted so a
# repeated diagnostic is one error, not three.
#
# ANCHORED, not a substring search. `error CS` anywhere in the concatenated
# log/stdout/stderr also matches PROSE -- a test named
# `Handles_error_CS1002_Gracefully`, or an assertion message quoting a
# diagnostic code, both echo into the Editor log on a PASSING run. That would
# count as a compile error, and because a passing run also has a results file
# it would raise E_UNITY_RESULTS_CONFLICT and refuse a good run. So a
# diagnostic is recognised only in the two shapes Unity actually emits:
#   Assets/KingletSpike/Editor/Broken.cs(1,102): error CS1002: ; expected
#   error CS8034: ...                      (assembly-level, no file position)
# i.e. `error CS<digits>:` either at the very start of the line or directly
# after a `(line,col):` file position.
_COMPILE_ERROR_RE = re.compile(
    r"^(?:error CS\d+:|.*\(\d+,\d+\):\s*error CS\d+:)"
)

# MEASURED on this host with a deliberately broken .cs in the fixture: Unity
# writes the banner "Aborting batchmode due to failure:" and the sentence
# "Scripts have compiler errors." as TWO SEPARATE LINES, and it writes them to
# the process's STDOUT, not into the file named by -logFile. The Editor log
# carries only the second sentence, on its own line. So the marker is that
# sentence, and the route scans the log and the captured stdout together --
# a single-line "Aborting batchmode due to failure: Scripts have compiler
# errors." literal matched neither stream and would have made this branch
# permanently dead code.
COMPILE_ABORT_MARKER = "Scripts have compiler errors."


def count_compile_errors(log_text: str) -> int:
    """How many DISTINCT `error CS####` diagnostics the Unity log carries."""
    seen: set[str] = set()
    for line in log_text.splitlines():
        stripped = line.strip()
        if _COMPILE_ERROR_RE.match(stripped):
            seen.add(stripped)
    return len(seen)


def log_reports_compile_abort(log_text: str) -> bool:
    """True iff Unity itself said it aborted batchmode for compiler errors."""
    return COMPILE_ABORT_MARKER in log_text


@dataclass(frozen=True)
class ResultsSummary:
    """The `<test-run>` root attributes, which map 1:1 onto the receipt."""

    result: str
    total: int
    passed: int
    failed: int
    skipped: int
    inconclusive: int


def _attr_int(element, name: str) -> int:
    raw = element.get(name)
    if raw is None:
        raise EvidenceError(
            "E_UNITY_RESULTS_MALFORMED",
            f"test-run element has no {name!r} attribute",
        )
    try:
        value = int(raw)
    except ValueError as error:
        raise EvidenceError(
            "E_UNITY_RESULTS_MALFORMED",
            f"test-run {name!r} is not an integer: {raw!r}",
        ) from error
    if value < 0:
        raise EvidenceError(
            "E_UNITY_RESULTS_MALFORMED", f"test-run {name!r} is negative: {value}"
        )
    return value


def parse_test_results(xml_text: str) -> ResultsSummary:
    """Parse an NUnit3 `results.xml` root into a ResultsSummary.

    `total` is not decoration: it is the cross-check that the four outcome
    counts account for every test the run knew about. A results file whose
    counts do not add up is malformed, not a pass.
    """
    try:
        root = ElementTree.fromstring(xml_text)
    except ElementTree.ParseError as error:
        raise EvidenceError(
            "E_UNITY_RESULTS_MALFORMED", f"results file is not valid XML: {error}"
        ) from error
    if root.tag != "test-run":
        raise EvidenceError(
            "E_UNITY_RESULTS_MALFORMED",
            f"results root element is {root.tag!r}, expected 'test-run'",
        )
    result = root.get("result")
    if not result:
        raise EvidenceError(
            "E_UNITY_RESULTS_MALFORMED", "test-run element has no 'result' attribute"
        )
    summary = ResultsSummary(
        result=result,
        total=_attr_int(root, "total"),
        passed=_attr_int(root, "passed"),
        failed=_attr_int(root, "failed"),
        skipped=_attr_int(root, "skipped"),
        inconclusive=_attr_int(root, "inconclusive"),
    )
    counted = summary.passed + summary.failed + summary.skipped + summary.inconclusive
    if counted != summary.total:
        raise EvidenceError(
            "E_UNITY_RESULTS_MALFORMED",
            f"test-run counts do not add up: passed+failed+skipped+inconclusive"
            f"={counted} but total={summary.total}",
        )
    return summary


def _tests_from_summary(summary: ResultsSummary) -> TestResult:
    """Map a ResultsSummary onto the receipt's TestResult, or refuse.

    `fail` requires an observed failure and `pass` requires an observed pass
    with nothing else in the run -- exactly what Task 1's validator demands.
    Anything in between (a run that was entirely skipped, or inconclusive)
    is a real outcome the frozen three-value vocabulary cannot express, so it
    raises rather than being rounded toward either claim.
    """
    if summary.failed >= 1:
        return TestResult(
            status="fail",
            passed=summary.passed,
            failed=summary.failed,
            skipped=summary.skipped,
        )
    if (
        summary.result == "Passed"
        and summary.passed >= 1
        and summary.skipped == 0
        and summary.inconclusive == 0
    ):
        return TestResult(
            status="pass", passed=summary.passed, failed=0, skipped=0
        )
    raise EvidenceError(
        "E_UNITY_RESULTS_UNRESOLVED",
        f"test run reported result={summary.result!r} with passed="
        f"{summary.passed} failed={summary.failed} skipped={summary.skipped} "
        f"inconclusive={summary.inconclusive}; that is neither an observed "
        "pass nor an observed failure, and this route does not guess",
    )


def _derive_outcome(
    *,
    exit_code: int | None,
    results_text: str | None,
    log_text: str,
) -> tuple[CompileResult, TestResult]:
    """Turn (exit code, results file, log) into a compile/tests claim, or refuse.

    Nothing here trusts the exit code on its own; it is only ever used to
    CONTRADICT a claim derived from the artifacts (see the module docstring's
    measured facts).
    """
    compile_errors = count_compile_errors(log_text)
    aborted = log_reports_compile_abort(log_text)

    if compile_errors and results_text is not None:
        raise EvidenceError(
            "E_UNITY_RESULTS_CONFLICT",
            f"the Unity log reports {compile_errors} compile error(s) but a "
            "results file was also written; a compile failure writes no "
            "results file, so one of these artifacts is not what it claims",
        )

    if compile_errors:
        if exit_code not in (None, 1):
            raise EvidenceError(
                "E_UNITY_EXIT_CONFLICT",
                f"the Unity log reports {compile_errors} compile error(s) but "
                f"Unity exited {exit_code}; a compile failure exits 1",
            )
        return (
            CompileResult(status="fail", errors=compile_errors),
            TestResult(status="not-run", passed=0, failed=0, skipped=0),
        )

    if aborted:
        # Unity said it aborted for compiler errors but no `error CS` line
        # survived into the log. Claiming compile=fail needs errors>=1 and we
        # have none to cite; claiming anything else is worse.
        raise EvidenceError(
            "E_UNITY_RESULTS_UNRESOLVED",
            "the Unity log reports a compile abort but carries no 'error CS' "
            "diagnostic to count; the failure cannot be quantified",
        )

    if results_text is None:
        raise EvidenceError(
            "E_UNITY_RESULTS_MISSING",
            f"Unity exited {exit_code} without writing a results file and "
            "without a compile error in its log; nothing establishes that any "
            "test ran (this is the measured `-quit` shape, and also what a "
            "timeout or cancellation looks like)",
        )

    tests = _tests_from_summary(parse_test_results(results_text))

    if tests.status == "pass" and exit_code != 0:
        raise EvidenceError(
            "E_UNITY_EXIT_CONFLICT",
            f"the results file records a passing run but Unity exited "
            f"{exit_code}; a passing test run exits 0",
        )
    if tests.status == "fail" and exit_code not in (None, 2):
        raise EvidenceError(
            "E_UNITY_EXIT_CONFLICT",
            f"the results file records a failing run but Unity exited "
            f"{exit_code}; a test failure exits 2",
        )

    return CompileResult(status="pass", errors=0), tests


def unity_lockfile_path(project: Path) -> Path:
    return Path(project) / "Temp" / "UnityLockfile"


# ---------------------------------------------------------------------------
# The guarded launch
# ---------------------------------------------------------------------------

def _headless_argv(editor: Path, project: Path, results_path: Path, log_path: Path) -> list[str]:
    """The exact argument ARRAY for a same-project headless EditMode run.

    An array, never a string: `-projectPath` is its own argv entry carrying an
    absolute path, and a project directory containing a space (or a literal
    "- Copy") is not hypothetical -- ownership.py exists because that shape
    breaks string-based reasoning about Unity command lines.

    `-quit` is deliberately ABSENT. See MEASURED FACT 1 in the module
    docstring: with `-quit`, Unity exits 0 and writes no results file at all,
    which is the one shape that could talk this route into a receipt it cannot
    back.
    """
    return [
        str(editor),
        "-batchmode",
        "-nographics",
        "-projectPath", str(project),
        "-runTests",
        "-testPlatform", "EditMode",
        "-testResults", str(results_path),
        "-logFile", str(log_path),
    ]


def _start_bound(
    lease: WorkspaceLease,
    argv: Sequence[str],
    *,
    cwd,
    env,
    stdout_path,
    stderr_path,
    process_factory: Callable[..., ManagedProcess] = ManagedProcess.start,
    cancellation_deadline: float = CANCELLATION_DEADLINE_SECONDS,
    **start_kwargs,
) -> ManagedProcess:
    """Launch, then IMMEDIATELY bind the lease to what was launched.

    This is the only launch path in this module, and it exists so that
    "started but never bound" is not a state a caller can reach by forgetting
    a line. If `bind_holder` raises, the process is cancelled here rather than
    returned: a live Unity under a lease that still names the controller is
    the double-open this whole mechanism exists to prevent.

    RESIDUAL WINDOW, stated precisely because it cannot be closed from inside
    this process: `ManagedProcess.start` returns once `Popen` has returned, and
    `bind_holder` then does a read-modify-atomic-write of the lease file. If
    the controller dies (SIGKILL, power loss) between those two points, the
    lease on disk still names the controller and not the contained group, so
    at TTL it reads as reclaimable while a real Unity holds the project. The
    window is a few milliseconds of one file write, versus a run measured in
    minutes, and it cannot be narrowed further here because the pgid that
    `bind_holder` needs does not EXIST until the child has been forked --
    there is nothing truthful to write before `Popen` returns. Closing it
    fully needs a pre-write of an intent record that a later acquirer treats
    as "unknown, refuse" (lease.py's conservative direction already refuses on
    unknown), which is a lease-format change and belongs to whoever owns
    lease.py's schema, not to this route.
    """
    process = process_factory(
        list(argv),
        cwd=cwd,
        env=env,
        stdout_path=stdout_path,
        stderr_path=stderr_path,
        **start_kwargs,
    )
    try:
        lease.bind_holder(pid=process.pid, pgid=process.pgid)
    except BaseException:
        try:
            process.cancel(cancellation_deadline)
        except BaseException:
            pass
        raise
    return process


def _read_text_or_none(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def _refusal_receipt(unity_version: str) -> UnityReceipt:
    return UnityReceipt(
        schema=RECEIPT_SCHEMA,
        route=SAME_PROJECT_HEADLESS_ROUTE,
        project_id=PROJECT_ID,
        unity_version=unity_version,
        compile=CompileResult(status="not-run", errors=0),
        tests=TestResult(status="not-run", passed=0, failed=0, skipped=0),
        ready=False,
        collision_refused=True,
        active_lease=False,
        # A refusal never launched Unity, so there is no Unity pid to carry.
        descendant_pids=(),
        artifacts=(f"{ARTIFACT_PREFIX}/{HEADLESS_SUMMARY_NAME}",),
    )


def run_same_project_headless(
    editor,
    project,
    raw_dir,
    *,
    process_table_provider=None,
    windows: bool | None = None,
    run_version_flag=None,
    process_factory: Callable[..., ManagedProcess] = ManagedProcess.start,
    env: dict | None = None,
    timeout_seconds: float = HEADLESS_TIMEOUT_SECONDS,
    cancellation_deadline: float = CANCELLATION_DEADLINE_SECONDS,
    lease_ttl_seconds: float | None = None,
    lease_dir=None,
    clock: Callable[[], float] = time.time,
) -> UnityReceipt:
    """Run EditMode tests headlessly against the project itself.

    The one public entry point for this route. Everything ordering-sensitive
    happens inside `_run_headless_guarded`, which is private precisely so a
    caller cannot assemble the same steps in a different order.

    Every keyword argument other than the paths is an injectable seam with a
    real default, so the refusal, conflict and cleanup branches are all
    EXECUTABLE from a test on any host rather than asserted as source text.
    """
    # ABSOLUTE, always. `ManagedProcess.start` runs Unity with cwd=<project>,
    # so a relative -projectPath is resolved a second time against the project
    # itself: a real run of this route with a relative path produced
    # "Couldn't set project path to: <project>/<project>" and exit 1. The same
    # trap applies to -testResults and -logFile, which is why raw_dir is
    # resolved here too and every path in the argv comes from these three.
    editor = Path(editor).resolve()
    project = Path(project).resolve()
    raw_dir = Path(raw_dir)
    raw_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = raw_dir.resolve()

    ownership_kwargs = {}
    if process_table_provider is not None:
        ownership_kwargs["process_table_provider"] = process_table_provider
    if windows is not None:
        ownership_kwargs["windows"] = windows

    # STEP 1 -- ownership. Cheapest refusal, and the one that must happen
    # before anything touches the Editor binary or the lease directory.
    try:
        assert_headless_safe(project, **ownership_kwargs)
    except EvidenceError as error:
        if error.code not in ("E_UNITY_OWNED", "E_UNITY_OWNER_UNKNOWN"):
            raise
        # A refusal receipt records the version the PROJECT declares, because
        # no Editor ran to report one. collision_refused=true is what says so.
        declared = read_project_version(project)
        _write_json(raw_dir / HEADLESS_SUMMARY_NAME, {
            "schema": "kinglet.unity-probe.summary/v1",
            "route": SAME_PROJECT_HEADLESS_ROUTE,
            "collision_refused": True,
            "refusal_code": error.code,
            "refusal_detail": error.detail,
            "launched": False,
            "unity_version_declared": declared,
        })
        return _refusal_receipt(declared)

    return _run_headless_guarded(
        editor=editor,
        project=project,
        raw_dir=raw_dir,
        run_version_flag=run_version_flag,
        process_factory=process_factory,
        env=env,
        timeout_seconds=timeout_seconds,
        cancellation_deadline=cancellation_deadline,
        lease_ttl_seconds=lease_ttl_seconds,
        lease_dir=default_lease_dir() if lease_dir is None else Path(lease_dir),
        clock=clock,
    )


def _run_headless_guarded(
    *,
    editor: Path,
    project: Path,
    raw_dir: Path,
    run_version_flag,
    process_factory,
    env,
    timeout_seconds: float,
    cancellation_deadline: float,
    lease_ttl_seconds: float | None,
    lease_dir: Path,
    clock: Callable[[], float],
) -> UnityReceipt:
    """The single guarded path. Steps 2-6, in the only order they are correct.

    2. verify_project_editor -- the project's own pinned version decides which
       Editor may open it; a mismatch raises rather than upgrading it.
    3. acquire the physical-workspace lease.
    4. _start_bound -- launch and bind in one call (see _start_bound).
    5. wait, then derive the outcome from the ARTIFACTS, never the exit code.
    6. finally: cancel the containment, record the proven survivor set, then
       release the lease. Cleanup runs on the refusal, timeout, conflict and
       success paths alike -- which is why steps 4-5 sit inside the try and
       the lease release sits in the outermost finally.
    """
    identity = verify_project_editor(
        project, editor,
        **({} if run_version_flag is None else {"run_version_flag": run_version_flag}),
    )

    log_path = raw_dir / HEADLESS_LOG_NAME
    results_path = raw_dir / HEADLESS_RESULTS_NAME
    # A previous run's artifacts would be read as this run's evidence.
    for stale in (
        log_path, results_path,
        raw_dir / HEADLESS_STDOUT_NAME, raw_dir / HEADLESS_STDERR_NAME,
    ):
        if stale.exists():
            stale.unlink()

    lease_kwargs = {}
    if lease_ttl_seconds is not None:
        lease_kwargs["ttl_seconds"] = lease_ttl_seconds
    lease = WorkspaceLease.acquire(
        project,
        route=SAME_PROJECT_HEADLESS_ROUTE,
        lease_dir=lease_dir,
        **lease_kwargs,
    )

    argv = _headless_argv(editor, project, results_path, log_path)
    survivors: tuple[int, ...] = ()
    exit_code: int | None = None
    started = clock()
    try:
        process = _start_bound(
            lease, argv,
            cwd=project,
            env=dict(os.environ) if env is None else dict(env),
            stdout_path=raw_dir / HEADLESS_STDOUT_NAME,
            stderr_path=raw_dir / HEADLESS_STDERR_NAME,
            process_factory=process_factory,
            cancellation_deadline=cancellation_deadline,
        )
        try:
            exit_code = process.wait(timeout_seconds)
        finally:
            # Unconditional: Unity orphans children into the contained group
            # and the set is cache-state dependent (a cold `Library/` left a
            # Roslyn server AND a package-manager server behind on a run that
            # exited 0). A clean exit is not evidence of no leak.
            cleanup = process.cancel(cancellation_deadline)
            survivors = cleanup.survivors
            if exit_code is None:
                exit_code = cleanup.exit_code

        # Both streams, concatenated: -logFile takes the Editor log, but the
        # batchmode abort banner goes to stdout (measured), and a launch that
        # dies before it can open the log file -- a bad -projectPath, for one
        # -- leaves stdout as the ONLY account of what happened.
        log_text = "\n".join(
            text for text in (
                _read_text_or_none(log_path),
                _read_text_or_none(raw_dir / HEADLESS_STDOUT_NAME),
                _read_text_or_none(raw_dir / HEADLESS_STDERR_NAME),
            ) if text
        )
        results_text = _read_text_or_none(results_path)
        compile_result, tests_result = _derive_outcome(
            exit_code=exit_code, results_text=results_text, log_text=log_text
        )

        if tests_result.status == "pass" and unity_lockfile_path(project).exists():
            raise EvidenceError(
                "E_UNITY_STALE_LOCK",
                "Temp/UnityLockfile is still present after the run; Unity "
                "removes it on clean exit, so a passing claim cannot be made "
                "over what looks like a crash or a kill",
            )

        _write_json(raw_dir / HEADLESS_SUMMARY_NAME, {
            "schema": "kinglet.unity-probe.summary/v1",
            "route": SAME_PROJECT_HEADLESS_ROUTE,
            "collision_refused": False,
            "launched": True,
            "unity_version": identity.version,
            "exit_code": exit_code,
            "duration_seconds": round(clock() - started, 3),
            "compile": {
                "status": compile_result.status,
                "errors": compile_result.errors,
            },
            "tests": {
                "status": tests_result.status,
                "passed": tests_result.passed,
                "failed": tests_result.failed,
                "skipped": tests_result.skipped,
            },
            "survivors": len(survivors),
        })

        return UnityReceipt(
            schema=RECEIPT_SCHEMA,
            route=SAME_PROJECT_HEADLESS_ROUTE,
            project_id=PROJECT_ID,
            unity_version=identity.version,
            compile=compile_result,
            tests=tests_result,
            ready=False,
            collision_refused=False,
            active_lease=False,
            # Proven-empty on a clean teardown. When it is NOT empty the pids
            # are recorded rather than swallowed, and Task 1's validator turns
            # that receipt into a failure -- a leak is evidence, not an
            # exception to be lost.
            descendant_pids=survivors,
            artifacts=(f"{ARTIFACT_PREFIX}/{HEADLESS_SUMMARY_NAME}",),
        )
    finally:
        lease.release()


# ---------------------------------------------------------------------------
# live-editor-mcp
# ---------------------------------------------------------------------------
#
# The one route whose receipt may carry `ready=true`, and the only one whose
# evidence passes through a bridge instead of a file Unity wrote. Everything
# that makes that safe lives in mcp.py; this function is the ordering.
#
# Two things about this route differ from same-project-headless on purpose:
#
# 1. There is NO collision-refusal receipt. `collision_refused` is
#    same-project-headless's own probe -- routes-v1.json and
#    validate_unity_receipt both reject it on any other route -- so when
#    ownership refuses here there is no honest receipt to emit and the route
#    RAISES. Emitting `collision_refused=true` from this route would produce a
#    receipt its own validator fails.
#
# 2. It edits the user's EditorPrefs, and EditorPrefs are per-user and
#    per-Unity-version, NOT per-project. The four MCPForUnity keys are backed
#    up (including their previous ABSENCE, which is why the fixture's
#    PrefBackup carries a `*Present` flag beside each value) and restored in
#    the finally -- so a crashed run leaves a backup file on disk and a
#    developer's Editor with our transport settings, which is exactly why the
#    backup is written before anything is changed and its existence is
#    verified before the run proceeds.

# Phase budgets summed from routes-v1.json: the Editor has to start, import
# and compile, the server has to come up, the Editor has to reach the bridge
# and go idle, and only then can tests run.
LIVE_MCP_TIMEOUT_PHASES: tuple[str, ...] = (
    "editor_startup",
    "import_compile_ready",
    "mcp_server_startup",
    "mcp_editor_ready",
    "edit_mode_tests",
)
LIVE_MCP_TIMEOUT_SECONDS: float = 1140.0

CONFIGURE_METHOD = "KingletSpike.Probe.ConfigureMcpProbe"
RESTORE_METHOD = "KingletSpike.Probe.RestoreMcpProbe"


def _prefs_argv(editor: Path, project: Path, method: str, log_path: Path) -> list[str]:
    """Batchmode argv for the EditorPrefs configure/restore passes.

    `-quit` IS present here, and correctly so: Task 5's measured fact is that
    `-quit` suppresses `-runTests`, and there is no `-runTests` in this argv.
    These passes run `-executeMethod` and then must exit; without `-quit` a
    batchmode Editor stays resident and holds the project open, which would
    deadlock the very GUI launch this pass exists to prepare for.
    """
    return [
        str(editor),
        "-batchmode",
        "-nographics",
        "-quit",
        "-projectPath", str(project),
        "-executeMethod", method,
        "-logFile", str(log_path),
    ]


def _gui_argv(editor: Path, project: Path, log_path: Path) -> list[str]:
    """Argv for the real GUI Editor. No `-batchmode` -- that is the point.

    The whole route exists to prove that a LIVE Editor, the kind a developer
    actually has open, can be driven through MCP. A batchmode Editor would
    make the route a slower duplicate of same-project-headless.
    """
    return [
        str(editor),
        "-projectPath", str(project),
        "-logFile", str(log_path),
    ]


def _run_prefs_pass(
    *,
    lease: WorkspaceLease,
    editor: Path,
    project: Path,
    method: str,
    log_path: Path,
    raw_dir: Path,
    backup_path: Path,
    mcp_url: str,
    process_factory,
    env: dict | None,
    timeout_seconds: float,
    cancellation_deadline: float,
    tag: str,
) -> tuple[int | None, tuple[int, ...]]:
    """Run one batchmode `-executeMethod` pass and prove it exited cleanly.

    Contained like every other launch here, and its survivors are returned
    rather than dropped: a Roslyn server orphaned by the configure pass is a
    leak whether or not the pass itself exited 0 (Task 5's measured fact 4).

    LAUNCHES THROUGH `_start_bound`, and the `lease` argument is why. This
    function used to call `process_factory` directly, which made it the ONE
    launch in this module that skipped the bind -- and it is the route's FIRST
    Unity launch, so for the whole configure pass the lease named the
    controller rather than the contained group. That is precisely the
    double-open window `_start_bound` exists to close, and it also made the
    module docstring's "`_start_bound()` is the ONLY way this module launches"
    false. The bind is not optional for a batchmode pass: it opens a real
    Editor on the real project for as long as the configure takes.
    """
    pass_env = dict(os.environ) if env is None else dict(env)
    pass_env["KINGLET_MCP_URL"] = mcp_url
    pass_env["KINGLET_MCP_PREFS_BACKUP"] = str(backup_path)

    process = _start_bound(
        lease,
        _prefs_argv(editor, project, method, log_path),
        cwd=project,
        env=pass_env,
        stdout_path=raw_dir / f"{tag}.stdout",
        stderr_path=raw_dir / f"{tag}.stderr",
        process_factory=process_factory,
        cancellation_deadline=cancellation_deadline,
    )
    exit_code: int | None = None
    try:
        exit_code = process.wait(timeout_seconds)
    finally:
        cleanup = process.cancel(cancellation_deadline)
        survivors = cleanup.survivors
        if exit_code is None:
            exit_code = cleanup.exit_code
    return exit_code, survivors


def run_live_editor_mcp(
    editor,
    project,
    raw_dir,
    *,
    process_table_provider=None,
    windows: bool | None = None,
    run_version_flag=None,
    process_factory: Callable[..., ManagedProcess] = ManagedProcess.start,
    client_factory=None,
    env: dict | None = None,
    host: str = "127.0.0.1",
    port: int | None = None,
    timeout_seconds: float = LIVE_MCP_TIMEOUT_SECONDS,
    editor_ready_timeout: float = mcp_module.MCP_EDITOR_READY_SECONDS,
    server_ready_timeout: float = mcp_module.MCP_SERVER_STARTUP_SECONDS,
    tests_timeout: float = mcp_module.EDIT_MODE_TESTS_SECONDS,
    cancellation_deadline: float = CANCELLATION_DEADLINE_SECONDS,
    lease_ttl_seconds: float | None = None,
    lease_dir=None,
    clock: Callable[[], float] = time.time,
) -> UnityReceipt:
    """Drive a LIVE GUI Editor through the pinned MCP bridge.

    The one public entry point for this route. Every keyword is an injectable
    seam with a real default, so the refusal, not-ready, timeout and cleanup
    branches are executable from a test on any host -- including hosts with no
    Unity, no display and no MCP server.
    """
    editor = Path(editor).resolve()
    project = Path(project).resolve()
    raw_dir = Path(raw_dir)
    raw_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = raw_dir.resolve()

    ownership_kwargs = {}
    if process_table_provider is not None:
        ownership_kwargs["process_table_provider"] = process_table_provider
    if windows is not None:
        ownership_kwargs["windows"] = windows

    # Ownership first, same as the headless route and for the same reason: it
    # is the cheapest refusal and it must precede anything that touches the
    # Editor binary. Unlike that route it RAISES -- see the block comment
    # above; this route has no honest refusal receipt to emit.
    assert_headless_safe(project, **ownership_kwargs)

    identity = verify_project_editor(
        project, editor,
        **({} if run_version_flag is None else {"run_version_flag": run_version_flag}),
    )

    return _live_mcp_guarded(
        editor=editor,
        project=project,
        raw_dir=raw_dir,
        identity=identity,
        process_factory=process_factory,
        client_factory=client_factory,
        env=env,
        host=host,
        port=port,
        timeout_seconds=timeout_seconds,
        editor_ready_timeout=editor_ready_timeout,
        server_ready_timeout=server_ready_timeout,
        tests_timeout=tests_timeout,
        cancellation_deadline=cancellation_deadline,
        lease_ttl_seconds=lease_ttl_seconds,
        lease_dir=default_lease_dir() if lease_dir is None else Path(lease_dir),
        clock=clock,
    )


def _live_mcp_guarded(
    *,
    editor: Path,
    project: Path,
    raw_dir: Path,
    identity,
    process_factory,
    client_factory,
    env,
    host: str,
    port: int | None,
    timeout_seconds: float,
    editor_ready_timeout: float,
    server_ready_timeout: float,
    tests_timeout: float,
    cancellation_deadline: float,
    lease_ttl_seconds: float | None,
    lease_dir: Path,
    clock: Callable[[], float],
) -> UnityReceipt:
    """The single guarded path for live-editor-mcp.

    Order, and why it is this one:

    1. acquire the lease BEFORE the prefs pass. The configure pass opens the
       project in batchmode; doing that outside the lease is a second Editor
       on an unguarded project, which is the thing the lease exists to stop.
    2. start the MCP server and prove it REACHABLE, before launching the
       Editor. The Editor is configured to dial the server on load, so a
       server that is not listening yet costs a retry cycle at best.
    3. launch the GUI Editor with `_start_bound`, so the lease names the
       process that actually holds the workspace -- the Editor, not the
       server. The server holds nothing and is cancelled independently.
    4. wait for the EXPECTED Editor. Not for "an instance": mcp.py's
       select_instance matches the project hash and the exact version.
    5. only then clear the console, refresh, wait again, and run tests.
    6. finally, in this order: cancel the Editor, restore the EditorPrefs
       (which needs the project free, hence after the cancel), cancel the
       server, release the lease. Every step runs on every path.
    """
    started = clock()
    survivors: list[int] = []
    setup_log = raw_dir / LIVE_MCP_SETUP_LOG_NAME
    editor_log = raw_dir / LIVE_MCP_EDITOR_LOG_NAME
    restore_log = raw_dir / LIVE_MCP_RESTORE_LOG_NAME
    backup_path = raw_dir / LIVE_MCP_PREFS_BACKUP_NAME
    for stale in (setup_log, editor_log, restore_log, backup_path):
        if stale.exists():
            stale.unlink()

    lease_kwargs = {}
    if lease_ttl_seconds is not None:
        lease_kwargs["ttl_seconds"] = lease_ttl_seconds
    lease = WorkspaceLease.acquire(
        project,
        route=LIVE_EDITOR_MCP_ROUTE,
        lease_dir=lease_dir,
        **lease_kwargs,
    )

    state = {
        "server": None,
        "gui": None,
        "configured": False,
        "torn_down": False,
        "teardown_failures": (),
    }
    ready_state = None
    compile_result: CompileResult | None = None
    tests_result: TestResult | None = None

    def teardown() -> None:
        """Cancel everything and put the EditorPrefs back. Idempotent.

        Runs BEFORE the receipt is built, not after, and that ordering is the
        whole point: `descendant_pids` is a claim about what survived cleanup,
        so a receipt assembled while the Editor was still running could only
        ever report an empty survivor set. The first version of this function
        built the receipt in the `try` and cancelled in the `finally`, which
        made `descendant_pids` structurally incapable of being non-empty --
        the leak field would have read clean on a run that leaked. A test
        caught it; the idempotent flag is what lets the same teardown run from
        the success path and from the outermost `finally` without cancelling
        twice.
        """
        if state["torn_down"]:
            return
        state["torn_down"] = True
        # EVERY step runs, whatever any earlier one did. This used to be three
        # bare statements: `gui.cancel()` and `server.cancel()` were unguarded
        # and genuinely raise (process.py re-raises a cancel whose outcome it
        # could not prove), so ONE raise skipped the EditorPrefs restore, the
        # server cancel, and -- because the outermost handler was
        # `finally: teardown(); lease.release()` -- the lease release too. A
        # live server, mutated developer EditorPrefs and a live lease all
        # leaked from a single failure.
        failures: list[str] = []

        def attempt(what: str, action) -> None:
            try:
                action()
            except BaseException as error:  # noqa: BLE001 -- recorded, not swallowed
                failures.append(f"{what}: {error!r}")

        if state["gui"] is not None:
            attempt(
                "cancelling the GUI Editor",
                lambda: survivors.extend(
                    state["gui"].cancel(cancellation_deadline).survivors
                ),
            )
        if state["configured"]:
            # Best effort by necessity: the run may be unwinding from an
            # exception and this is the only chance to put the developer's
            # EditorPrefs back. A failure here must not mask the original
            # error -- but it is RECORDED, because a run that could not put
            # the developer's Editor back has not cleaned up.
            def restore() -> None:
                _, leaked = _run_prefs_pass(
                    lease=lease,
                    editor=editor, project=project, method=RESTORE_METHOD,
                    log_path=restore_log, raw_dir=raw_dir, backup_path=backup_path,
                    mcp_url="", process_factory=process_factory, env=env,
                    timeout_seconds=timeout_seconds,
                    cancellation_deadline=cancellation_deadline,
                    tag="live-editor-mcp-restore",
                )
                survivors.extend(leaked)

            attempt("restoring the developer's EditorPrefs", restore)
        if state["server"] is not None:
            attempt(
                "cancelling the MCP server",
                lambda: survivors.extend(
                    state["server"].cancel(cancellation_deadline).survivors
                ),
            )
        state["teardown_failures"] = tuple(failures)

    def require_clean_teardown() -> None:
        """A receipt may not claim cleanliness cleanup could not establish.

        `descendant_pids: []` is a POSITIVE claim -- "nothing survived". When
        a cancel raised, the survivor set was never computed, so publishing an
        empty one turns "I could not tell" into "it was clean". That is the
        inversion this plan exists to prevent, and it used to be exactly what
        `except BaseException: pass` produced on the SUCCESS path.
        """
        failures = state.get("teardown_failures") or ()
        if failures:
            raise EvidenceError(
                "E_UNITY_CLEANUP_UNKNOWN",
                "cleanup did not complete, so this run cannot report what "
                "survived it: " + "; ".join(failures),
            )

    try:
        server, resolved_port = mcp_module.start_mcp(
            raw_dir, host=host, port=port, env=env, process_factory=process_factory
        )
        state["server"] = server
        mcp_url = f"http://{host}:{resolved_port}/mcp"

        client = (
            mcp_module.SubprocessMcpClient(host=host, port=resolved_port, env=env)
            if client_factory is None
            else client_factory(host=host, port=resolved_port)
        )

        probe = mcp_module.wait_for_server(client, timeout=server_ready_timeout)
        if not probe.reachable:
            raise EvidenceError(
                "E_UNITY_MCP_NOT_READY",
                f"{mcp_module.CATEGORY_SERVER_START_FAILED}: the pinned MCP server "
                f"never answered on {host}:{resolved_port} within "
                f"{server_ready_timeout}s",
            )

        # Point the Editor at THIS server, backing up what was there first.
        exit_code, leaked = _run_prefs_pass(
            lease=lease,
            editor=editor, project=project, method=CONFIGURE_METHOD,
            log_path=setup_log, raw_dir=raw_dir, backup_path=backup_path,
            mcp_url=mcp_url, process_factory=process_factory, env=env,
            timeout_seconds=timeout_seconds,
            cancellation_deadline=cancellation_deadline, tag="live-editor-mcp-setup",
        )
        survivors.extend(leaked)
        if exit_code != 0:
            raise EvidenceError(
                "E_UNITY_MCP_CONFIGURE",
                f"the EditorPrefs configure pass exited {exit_code}; the Editor "
                "was never pointed at the probe's MCP server",
            )
        if not backup_path.is_file():
            # Without a backup we cannot put the developer's Editor back, so we
            # refuse to change it further rather than proceed and hope.
            raise EvidenceError(
                "E_UNITY_MCP_CONFIGURE",
                "the configure pass exited 0 but wrote no EditorPrefs backup; "
                "refusing to run a route whose changes could not be reverted",
            )
        state["configured"] = True

        gui = _start_bound(
            lease, _gui_argv(editor, project, editor_log),
            cwd=project,
            env=dict(os.environ) if env is None else dict(env),
            stdout_path=raw_dir / "live-editor-mcp-editor.stdout",
            stderr_path=raw_dir / "live-editor-mcp-editor.stderr",
            process_factory=process_factory,
            cancellation_deadline=cancellation_deadline,
        )
        state["gui"] = gui

        ready_state = mcp_module.wait_for_editor(
            client,
            project=project,
            unity_version=identity.version,
            timeout=editor_ready_timeout,
        ).require_ready()
        instance = ready_state.instance

        # Console cleared BEFORE the refresh, so the errors we count are this
        # compile's and not whatever was on screen when the Editor opened.
        mcp_module.clear_console(client, instance=instance)
        mcp_module.refresh_assets(client, instance=instance)
        ready_state = mcp_module.wait_for_editor(
            client,
            project=project,
            unity_version=identity.version,
            timeout=editor_ready_timeout,
        ).require_ready()

        errors, _messages = mcp_module.read_console_errors(client, instance=instance)
        if errors:
            compile_result = CompileResult(status="fail", errors=errors)
            tests_result = TestResult(status="not-run", passed=0, failed=0, skipped=0)
        else:
            summary = mcp_module.run_tests_via_mcp(
                client, instance=instance, timeout=tests_timeout
            )
            compile_result = CompileResult(status="pass", errors=0)
            tests_result = _tests_from_job(summary)
            # A compile error can surface DURING the run (a test that triggers
            # a reimport). Re-reading closes the window in which we would claim
            # compile=pass over a console that had since filled with CS errors.
            errors, _messages = mcp_module.read_console_errors(client, instance=instance)
            if errors:
                raise EvidenceError(
                    "E_UNITY_RESULTS_CONFLICT",
                    f"the Editor console reports {errors} compile error(s) after a "
                    f"test run this route recorded as {tests_result.status!r}; one "
                    "of those two observations is not describing this run",
                )

        # BEFORE the receipt, never after. `descendant_pids` is a claim about
        # what survived cleanup, so cleanup has to have happened. The outer
        # `finally` calls this again on every other path; it is idempotent.
        teardown()
        # ...and cleanup has to have SUCCEEDED, or there is no survivor set to
        # publish. Without this the success path published `descendant_pids:
        # []` as proof of cleanliness on a run whose cleanup raised.
        require_clean_teardown()

        _write_json(raw_dir / LIVE_MCP_SUMMARY_NAME, {
            "schema": "kinglet.unity-probe.summary/v1",
            "route": LIVE_EDITOR_MCP_ROUTE,
            "collision_refused": False,
            "launched": True,
            "unity_version": identity.version,
            "mcp_commit": mcp_module.MCP_SERVER_COMMIT,
            "mcp_host": host,
            "instance_hash": instance.hash,
            "ready": True,
            "ready_polls": ready_state.polls,
            "duration_seconds": round(clock() - started, 3),
            "compile": {
                "status": compile_result.status,
                "errors": compile_result.errors,
            },
            "tests": {
                "status": tests_result.status,
                "passed": tests_result.passed,
                "failed": tests_result.failed,
                "skipped": tests_result.skipped,
            },
            "survivors": len(survivors),
        })

        return UnityReceipt(
            schema=RECEIPT_SCHEMA,
            route=LIVE_EDITOR_MCP_ROUTE,
            project_id=PROJECT_ID,
            unity_version=identity.version,
            compile=compile_result,
            tests=tests_result,
            # True because wait_for_editor RETURNED ready for the expected
            # instance at the expected version -- not because a server started.
            ready=True,
            collision_refused=False,
            active_lease=False,
            descendant_pids=tuple(survivors),
            artifacts=(f"{ARTIFACT_PREFIX}/{LIVE_MCP_SUMMARY_NAME}",),
        )
    finally:
        # `lease.release()` is in its own `finally` so a raising teardown
        # cannot skip it. It used to sit after `teardown()` as a plain second
        # statement, which meant one unguarded `cancel()` raise leaked the
        # lease as well as everything teardown had not yet reached.
        #
        # STATED PLAINLY so nobody mistakes this for a tested branch: teardown
        # is now TOTAL -- every step inside it runs through `attempt`, which
        # catches BaseException and records it -- so there is currently no
        # input that makes it raise, and no test can kill a mutant that
        # flattens these two statements. That is the stronger fix, not a
        # weaker one, and this construction is here for the next edit that
        # adds a statement to teardown outside `attempt`.
        try:
            teardown()
        finally:
            lease.release()


def _tests_from_job(summary) -> TestResult:
    """Map an MCP test-job summary onto the receipt's TestResult, or refuse.

    Identical discipline to `_tests_from_summary` for the headless route, and
    deliberately so: the plan requires MCP and headless to publish the SAME
    normalized fields, which means the same claim needs the same evidence
    whichever bridge produced it. A run that was entirely skipped is not a
    pass here either.
    """
    if summary.failed >= 1:
        return TestResult(
            status="fail",
            passed=summary.passed,
            failed=summary.failed,
            skipped=summary.skipped,
        )
    if summary.status == "succeeded" and summary.passed >= 1 and summary.skipped == 0:
        return TestResult(status="pass", passed=summary.passed, failed=0, skipped=0)
    raise EvidenceError(
        "E_UNITY_RESULTS_UNRESOLVED",
        f"MCP test job finished as {summary.status!r} / {summary.result_state!r} "
        f"with passed={summary.passed} failed={summary.failed} "
        f"skipped={summary.skipped}; that is neither an observed pass nor an "
        "observed failure, and this route does not guess",
    )


# ---------------------------------------------------------------------------
# isolated-headless
# ---------------------------------------------------------------------------
#
# The route the plan licenses in one sentence:
#
#   "Isolated headless may run while the main Editor is open only from a
#    separate physical copy with separate Library, Temp, logs, lease, and
#    outputs."
#
# Every clause of that sentence is a check here, and every check is made
# BEFORE Unity is launched, because after launch the damage is already done:
#
#   separate physical copy -> isolation.assert_isolated, which compares
#       (st_dev, st_ino) and not just canonical paths (a bind mount defeats
#       path comparison, and `realpath` cannot see it).
#   separate Library/Temp -> assert_isolated again: every generated tree
#       present under the copy must resolve under the copy and must not be
#       the main project's tree of that name.
#   separate logs, outputs -> _assert_writes_outside, which requires the run
#       directory (log, results, both captured streams) to lie outside BOTH
#       workspaces. Outside main is the isolation claim; outside the copy is
#       so Unity does not import its own log as an asset.
#   separate lease -> the lease is acquired on the ISOLATED workspace only,
#       and its file path is asserted different from the main workspace's.
#       That is the plan's second constraint -- "a lease never spans main and
#       isolated copies as if they were the same physical workspace" -- stated
#       in the lease's own vocabulary rather than in a comment.
#
# WHAT THIS ROUTE DOES NOT DO, and why: it does not refuse because the main
# project is open. That is the entire point of the route. It OBSERVES the main
# project's ownership through the same detector the other routes refuse with,
# and records what it saw (`main_owner` in the summary), because a concurrency
# claim made without looking at whether anything was concurrent is not a
# claim. `require_main_owner=True` turns the observation into a precondition,
# which is how the plan's "run it while the main Editor is open" proof is
# expressed as code rather than as a procedure someone has to remember.
#
# It DOES refuse if the ISOLATED path is owned or ambiguous, and it RAISES
# rather than emitting a refusal receipt: `collision_refused` is
# same-project-headless's own probe and routes-v1.json rejects it on any other
# route, so there is no honest receipt for this route to emit. Same reasoning
# as live-editor-mcp.
#
# THE RECEIPT-SHAPE GAP, stated rather than papered over: `asdict` of an
# isolated-headless receipt and of a same-project-headless receipt differ in
# the `route` label alone. The frozen Task 1 shape has no field for physical
# workspace identity, so nothing in the receipt itself distinguishes a real
# isolated run from a same-project run relabelled. This route narrows that as
# far as the frozen shape allows: it always writes an isolation manifest and
# always CITES it in `artifacts`, and that manifest carries two distinct
# physical-path hashes plus a digest of every copied file. So the isolation
# claim is now backed by a named artifact a reader can check against the
# workspaces, instead of resting on a label. It is narrowed, not closed --
# closing it needs a receipt field (a `workspace_id`, or an artifact digest),
# which is a contract change and belongs to whoever owns routes-v1.json.

# What the isolated run must not have touched in the main workspace. Not all
# of ProjectSettings: a main Editor legitimately rewrites several .asset files
# there while it is open (and a COLD first open creates about thirty of them),
# so digesting the whole directory would make this guard fire on the main
# Editor doing its job and would teach a reader to ignore it. These three are
# the ones whose mutation means real damage -- the source, the package set,
# and the pinned Editor version that "refuse silent project upgrade" protects.
MAIN_GUARDED_TREES: tuple[str, ...] = ("Assets", "Packages")
MAIN_GUARDED_FILES: tuple[str, ...] = ("ProjectSettings/ProjectVersion.txt",)


def main_guard_digest(
    project,
    *,
    trees: Sequence[str] = MAIN_GUARDED_TREES,
    files: Sequence[str] = MAIN_GUARDED_FILES,
) -> str:
    """One digest over the main workspace's source, packages and pinned version.

    Taken before and after the isolated run. A difference is
    `E_UNITY_ISOLATION_BREACH` rather than a note in the summary, and
    deliberately so: this route cannot tell whether the change came from the
    isolated Unity or from the main Editor saving a file, and "I cannot tell"
    resolves to refusal here as everywhere else in this plan. A main Editor
    that saves during the window will trip it; that is the honest outcome,
    not a false alarm to be tuned away.
    """
    project = Path(project)
    digest = hashlib.sha256()
    entries: list[tuple[str, str]] = []
    for tree in trees:
        root = project / tree
        if not root.is_dir():
            raise EvidenceError(
                "E_UNITY_ISOLATION_BREACH",
                f"the main workspace has no {tree} directory to guard",
            )
        for current, directory_names, file_names in os.walk(root):
            directory_names.sort()
            for name in sorted(file_names):
                target = Path(current) / name
                entries.append((
                    target.relative_to(project).as_posix(), sha256_file(target)
                ))
    for relative in files:
        target = project / relative
        if not target.is_file():
            raise EvidenceError(
                "E_UNITY_ISOLATION_BREACH",
                f"the main workspace has no {relative} to guard",
            )
        entries.append((relative, sha256_file(target)))
    for path, checksum in sorted(entries):
        digest.update(f"{path}\0{checksum}\n".encode("utf-8"))
    return digest.hexdigest()


def _assert_writes_outside(*, label: str, target: Path, main: Path, isolated: Path) -> None:
    """Refuse a write destination that lies inside either workspace."""
    resolved = Path(os.path.realpath(target))
    for boundary, name, reason in (
        (main, "main", "an isolated run must write nothing beneath the workspace it is isolated from"),
        (isolated, "isolated", "a run directory beneath the copy is imported by Unity as project content"),
    ):
        if resolved == boundary or resolved.is_relative_to(boundary):
            raise EvidenceError(
                "E_UNITY_ISOLATION_BREACH",
                f"the {label} lies inside the {name} workspace; {reason}",
            )


def _isolated_argv(editor: Path, project: Path, results_path: Path, log_path: Path) -> list[str]:
    """The isolated run's argv.

    Identical in shape to `_headless_argv`, and that is the requirement rather
    than a coincidence: the plan asks for "the same batchmode command and test
    parser against the isolated path", so the two routes must differ only in
    WHICH project they open and WHERE they write. `-quit` is absent here for
    the same measured reason it is absent there.
    """
    return _headless_argv(editor, project, results_path, log_path)


def run_isolated_headless(
    editor,
    main_project,
    isolated_project,
    raw_dir,
    *,
    manifest: IsolationManifest | None = None,
    require_main_owner: bool = False,
    process_table_provider=None,
    windows: bool | None = None,
    run_version_flag=None,
    process_factory: Callable[..., ManagedProcess] = ManagedProcess.start,
    env: dict | None = None,
    timeout_seconds: float = HEADLESS_TIMEOUT_SECONDS,
    cancellation_deadline: float = CANCELLATION_DEADLINE_SECONDS,
    lease_ttl_seconds: float | None = None,
    lease_dir=None,
    stat_reader=os.stat,
    clock: Callable[[], float] = time.time,
) -> UnityReceipt:
    """Run EditMode tests headlessly from an isolated copy, main project or not.

    The one public entry point for this route. `isolated_project` is a copy
    already made by `isolation.prepare_isolated_copy`; this function does not
    make it, because a route that both creates the copy and vouches for it
    would be its own witness.

    If `manifest` is supplied it is VERIFIED against the bytes on disk before
    anything launches, and a mismatch is `E_UNITY_ISOLATION_MANIFEST`. If it
    is not supplied, one is derived from the copy as it stands. Either way a
    manifest is written and cited in the receipt's artifacts -- see the block
    comment above for exactly how much of the receipt-shape gap that closes
    and how much it does not.

    Every keyword is an injectable seam with a real default, so each refusal
    and cleanup branch is executable from a test on a host with no Unity.
    """
    editor = Path(editor).resolve()
    main_project = Path(main_project).resolve()
    isolated_project = Path(isolated_project).resolve()
    raw_dir = Path(raw_dir)
    raw_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = raw_dir.resolve()
    lease_dir = default_lease_dir() if lease_dir is None else Path(lease_dir)

    # STEP 1 -- separateness. Nothing else may run until this holds: every
    # later step (ownership on the copy, the lease, the launch) is meaningless
    # if the two paths turn out to name one workspace.
    boundary = assert_isolated(main_project, isolated_project, stat_reader=stat_reader)

    main_real = Path(os.path.realpath(main_project))
    isolated_real = Path(os.path.realpath(isolated_project))

    # STEP 2 -- separate logs and outputs. The run directory holds the Editor
    # log, the results file and both captured streams.
    _assert_writes_outside(
        label="run directory", target=raw_dir, main=main_real, isolated=isolated_real
    )
    lease_dir.mkdir(parents=True, exist_ok=True)
    _assert_writes_outside(
        label="lease directory", target=lease_dir, main=main_real, isolated=isolated_real
    )

    # STEP 3 -- separate lease. The boundary already proved the two path
    # hashes differ; this asserts the consequence the plan actually names, in
    # the lease's own terms, so a future change to how lease files are named
    # cannot quietly make one file serve both workspaces.
    main_lease = lease_path_for(main_project, lease_dir)
    isolated_lease = lease_path_for(isolated_project, lease_dir)
    if main_lease == isolated_lease:
        raise EvidenceError(
            "E_UNITY_NOT_ISOLATED",
            "the main and isolated workspaces resolve to one lease file; a "
            "lease would span both as if they were the same physical workspace",
        )

    ownership_kwargs = {}
    if process_table_provider is not None:
        ownership_kwargs["process_table_provider"] = process_table_provider
    if windows is not None:
        ownership_kwargs["windows"] = windows

    # STEP 4 -- OBSERVE the main workspace. Never a refusal by itself: running
    # while main is open is the route's purpose. `require_main_owner` makes it
    # a precondition for the concurrency proof.
    main_owner = detect_gui_owner(main_project, **ownership_kwargs)
    if main_owner is None:
        main_owner_state = "clear"
    elif main_owner.confirmed:
        main_owner_state = "confirmed"
    else:
        main_owner_state = "unresolved"
    if require_main_owner and main_owner_state != "confirmed":
        raise EvidenceError(
            "E_UNITY_MAIN_NOT_OPEN",
            "this run was asked to prove isolated headless execution while the "
            f"main workspace is open, but its ownership reads {main_owner_state!r}; "
            "a concurrency claim with nothing concurrent is not a claim",
        )

    # STEP 5 -- the COPY must be unowned. Raises rather than emitting a
    # refusal receipt: collision_refused belongs to same-project-headless and
    # routes-v1.json rejects it here, so there is no honest receipt to emit.
    assert_headless_safe(isolated_project, **ownership_kwargs)

    # STEP 6 -- the copy's own declared version decides which Editor may open
    # it. Reading it from the COPY and not from main is the point: a copy that
    # somehow declares a different version must not be opened by main's Editor.
    identity = verify_project_editor(
        isolated_project, editor,
        **({} if run_version_flag is None else {"run_version_flag": run_version_flag}),
    )

    # STEP 7 -- the manifest is evidence, so it is checked against the bytes.
    if manifest is None:
        manifest = manifest_for_copy(boundary, isolated_project)
    else:
        if (
            manifest.main_path_hash != boundary.main_path_hash
            or manifest.isolated_path_hash != boundary.isolated_path_hash
            # The physical-directory identities too, not only the lease keys:
            # a manifest whose path hashes match while its inode identities do
            # not is describing a different pair of directories that happen to
            # sit at the same two paths -- a workspace replaced between the
            # copy and the run.
            or manifest.main_identity != boundary.main_identity
            or manifest.isolated_identity != boundary.isolated_identity
        ):
            raise EvidenceError(
                "E_UNITY_ISOLATION_MANIFEST",
                "the supplied manifest records different workspace identities "
                "than the two workspaces this run proved separate; it does not "
                "describe this copy",
            )
        verify_manifest(isolated_project, manifest)

    return _run_isolated_guarded(
        editor=editor,
        main_project=main_project,
        isolated_project=isolated_project,
        raw_dir=raw_dir,
        identity=identity,
        manifest=manifest,
        main_owner_state=main_owner_state,
        process_factory=process_factory,
        env=env,
        timeout_seconds=timeout_seconds,
        cancellation_deadline=cancellation_deadline,
        lease_ttl_seconds=lease_ttl_seconds,
        lease_dir=lease_dir,
        clock=clock,
    )


def _run_isolated_guarded(
    *,
    editor: Path,
    main_project: Path,
    isolated_project: Path,
    raw_dir: Path,
    identity,
    manifest: IsolationManifest,
    main_owner_state: str,
    process_factory,
    env,
    timeout_seconds: float,
    cancellation_deadline: float,
    lease_ttl_seconds: float | None,
    lease_dir: Path,
    clock: Callable[[], float],
) -> UnityReceipt:
    """The single guarded path for isolated-headless. Private for the same
    reason `_run_headless_guarded` is: a caller holding it could assemble the
    launch while skipping the separateness proof entirely.

    Order:
      a. digest the main workspace's guarded content BEFORE the launch;
      b. acquire the ISOLATED workspace's lease -- and only that one;
      c. `_start_bound`, the module's only launch path, so "started but never
         bound" is unreachable;
      d. wait, then in a `finally` cancel the containment and record the
         PROVEN survivor set (cold `Library` is the leak-prone case, and an
         isolated copy has a cold `Library` by construction -- it was just
         created, so this route is the one most likely to orphan a Roslyn
         server and the last one that may report an empty survivor set
         without having looked);
      e. derive the outcome from the artifacts, never the exit code;
      f. re-digest the main workspace and refuse if it moved;
      g. release the lease in the outermost `finally`, on every path.
    """
    main_digest_before = main_guard_digest(main_project)

    log_path = raw_dir / ISOLATED_LOG_NAME
    results_path = raw_dir / ISOLATED_RESULTS_NAME
    stdout_path = raw_dir / ISOLATED_STDOUT_NAME
    stderr_path = raw_dir / ISOLATED_STDERR_NAME
    for stale in (log_path, results_path, stdout_path, stderr_path):
        if stale.exists():
            stale.unlink()

    lease_kwargs = {}
    if lease_ttl_seconds is not None:
        lease_kwargs["ttl_seconds"] = lease_ttl_seconds
    lease = WorkspaceLease.acquire(
        isolated_project,
        route=ISOLATED_HEADLESS_ROUTE,
        lease_dir=lease_dir,
        **lease_kwargs,
    )

    argv = _isolated_argv(editor, isolated_project, results_path, log_path)
    survivors: tuple[int, ...] = ()
    exit_code: int | None = None
    started = clock()
    try:
        process = _start_bound(
            lease, argv,
            cwd=isolated_project,
            env=dict(os.environ) if env is None else dict(env),
            stdout_path=stdout_path,
            stderr_path=stderr_path,
            process_factory=process_factory,
            cancellation_deadline=cancellation_deadline,
        )
        try:
            exit_code = process.wait(timeout_seconds)
        finally:
            cleanup = process.cancel(cancellation_deadline)
            survivors = cleanup.survivors
            if exit_code is None:
                exit_code = cleanup.exit_code

        log_text = "\n".join(
            text for text in (
                _read_text_or_none(log_path),
                _read_text_or_none(stdout_path),
                _read_text_or_none(stderr_path),
            ) if text
        )
        results_text = _read_text_or_none(results_path)
        compile_result, tests_result = _derive_outcome(
            exit_code=exit_code, results_text=results_text, log_text=log_text
        )

        if tests_result.status == "pass" and unity_lockfile_path(isolated_project).exists():
            raise EvidenceError(
                "E_UNITY_STALE_LOCK",
                "Temp/UnityLockfile is still present in the isolated copy after "
                "the run; Unity removes it on clean exit, so a passing claim "
                "cannot be made over what looks like a crash or a kill",
            )

        # The isolation claim, checked after the fact and not only designed
        # for. A change here is a refusal even on an otherwise passing run.
        main_digest_after = main_guard_digest(main_project)
        if main_digest_after != main_digest_before:
            raise EvidenceError(
                "E_UNITY_ISOLATION_BREACH",
                "the main workspace's guarded content changed while the "
                "isolated run was in progress; this route cannot tell whether "
                "the isolated Unity wrote it or the open Editor did, and it "
                "does not guess",
            )

        # The isolated copy's own generated trees, recorded as the observation
        # they are: they exist, and they are under the copy.
        generated = tuple(
            name for name in ("Library", "Temp", "Logs")
            if (isolated_project / name).exists()
        )

        _write_json(raw_dir / ISOLATED_MANIFEST_NAME, manifest_to_dict(manifest))
        _write_json(raw_dir / ISOLATED_SUMMARY_NAME, {
            "schema": "kinglet.unity-probe.summary/v1",
            "route": ISOLATED_HEADLESS_ROUTE,
            "collision_refused": False,
            "launched": True,
            "unity_version": identity.version,
            "exit_code": exit_code,
            "duration_seconds": round(clock() - started, 3),
            "main_owner": main_owner_state,
            "main_path_hash": manifest.main_path_hash,
            "isolated_path_hash": manifest.isolated_path_hash,
            "main_identity": manifest.main_identity,
            "isolated_identity": manifest.isolated_identity,
            "isolated_tree_sha256": manifest.tree_sha256,
            "isolated_generated_trees": list(generated),
            "main_guard_digest": main_digest_after,
            "compile": {
                "status": compile_result.status,
                "errors": compile_result.errors,
            },
            "tests": {
                "status": tests_result.status,
                "passed": tests_result.passed,
                "failed": tests_result.failed,
                "skipped": tests_result.skipped,
            },
            "survivors": len(survivors),
        })

        return UnityReceipt(
            schema=RECEIPT_SCHEMA,
            route=ISOLATED_HEADLESS_ROUTE,
            project_id=PROJECT_ID,
            unity_version=identity.version,
            compile=compile_result,
            tests=tests_result,
            ready=False,
            collision_refused=False,
            active_lease=False,
            descendant_pids=survivors,
            # TWO artifacts, and the second is the whole point: it is the only
            # place a receipt from this route can point at the two distinct
            # physical workspace identities its name asserts.
            artifacts=(
                f"{ARTIFACT_PREFIX}/{ISOLATED_SUMMARY_NAME}",
                f"{ARTIFACT_PREFIX}/{ISOLATED_MANIFEST_NAME}",
            ),
        )
    finally:
        lease.release()
