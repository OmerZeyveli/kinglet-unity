"""routes.py -- The `filesystem` and `same-project-headless` execution routes.

Two routes, one honesty rule
----------------------------
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
deliberately omits it (see `headless_argv`), because with it the route can
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

So there is exactly one guarded path (`_run_headless_guarded`), it is private,
and `start_bound()` is the ONLY way this module launches: it starts and binds
in one call and cancels the process if the bind fails, so "started but never
bound" is not a state a caller can reach by forgetting a line. See
`start_bound`'s docstring for the residual window that cannot be closed from
inside this process.

Ownership refusal is its own probe, not a run
---------------------------------------------
When `assert_headless_safe` refuses (a confirmed live owner, or an ownership
it could not clear), the route returns a receipt with
`collision_refused=true` and `compile`/`tests` both `not-run`. Nothing was
launched, so the receipt carries no Unity pid and no lease. It is the matrix
cell `same-project-headless.collision-refusal`, and Task 1's validator
enforces that it can never also claim a compile or a test result.
"""
from __future__ import annotations

import hashlib
import json
import os
import time
import xml.etree.ElementTree as ElementTree
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence

from ..model import EvidenceError
from .editor import read_project_version, verify_project_editor
from .lease import WorkspaceLease
from .model import PROJECT_ID, RECEIPT_SCHEMA, CompileResult, TestResult, UnityReceipt
from .ownership import assert_headless_safe
from .process import ManagedProcess

FILESYSTEM_ROUTE = "filesystem"
SAME_PROJECT_HEADLESS_ROUTE = "same-project-headless"

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
_COMPILE_ERROR_MARKER = "error CS"

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
        if _COMPILE_ERROR_MARKER in stripped:
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

def headless_argv(editor: Path, project: Path, results_path: Path, log_path: Path) -> list[str]:
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


def start_bound(
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
    clock: Callable[[], float],
) -> UnityReceipt:
    """The single guarded path. Steps 2-6, in the only order they are correct.

    2. verify_project_editor -- the project's own pinned version decides which
       Editor may open it; a mismatch raises rather than upgrading it.
    3. acquire the physical-workspace lease.
    4. start_bound -- launch and bind in one call (see start_bound).
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
        lease_dir=raw_dir / "lease",
        **lease_kwargs,
    )

    argv = headless_argv(editor, project, results_path, log_path)
    survivors: tuple[int, ...] = ()
    exit_code: int | None = None
    started = clock()
    try:
        process = start_bound(
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
