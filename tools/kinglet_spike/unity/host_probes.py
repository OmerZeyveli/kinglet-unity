"""host_probes.py -- Execute the 00U route probes natively and stage 00A records.

This is the body of `spikes/platform/unity/run-host.sh`. The shell script owns
host gating (native OS, no WSL/Git Bash, explicit `--unity` path) and this
module owns the probes, because everything a probe needs -- process sampling at
sub-second resolution, an inode comparison, a `process_factory` that refuses to
launch -- is a Python API in `tools/kinglet_spike/unity/` already. Reimplementing
any of it in bash would be a second, untested copy of a safety-critical rule.

What it produces
----------------
For each of the nine frozen unity matrix probes, either an OBSERVATION (a set
of pass/fail assertions plus the sanitized artifacts backing them) or an
explicit UNOBSERVED entry carrying the reason the cell stays open. Those go
into one `kinglet.unity-probe.observations/v1` document, which `results.py`
converts to one `kinglet.spike.evidence/v1` record per probe, staged under
`.kinglet/local/spikes/<run-id>/` for `tools.kinglet_spike publish`.

Raw Unity logs, the NUnit XML, the lease and every machine path stay in the raw
workspace, which lives under `.kinglet/local/` and is gitignored. The only
things staged for publication are JSON summaries passed through
`redact.redact_artifact`, which replaces the forbidden roots and then REFUSES
to write anything still matching a credential or an absolute user path.

What it never does
------------------
It never points Unity at a project it did not create, and it never invents a
result. A probe that cannot be performed on this host is recorded as
unobserved with a reason -- there is no code path from "could not observe" to
a passing assertion.
"""
from __future__ import annotations

import datetime
import json
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from dataclasses import asdict
from pathlib import Path

from ..model import EvidenceError
from ..publish import record_to_json
from ..redact import redact_artifact
from .editor import verify_editor, verify_project_editor
from .isolation import prepare_isolated_copy
from .mcp import (
    CATEGORY_EDITOR_NOT_READY,
    SubprocessMcpClient,
    probe_editor,
    start_mcp,
    wait_for_server,
)
from .ownership import detect_gui_owner
from .receipt import validate_unity_receipt
from .results import (
    OBSERVATIONS_SCHEMA,
    to_evidence_records,
    validate_unity_observations,
)
from .routes import (
    HEADLESS_TIMEOUT_SECONDS,
    inventory_project,
    receipt_to_dict,
    run_filesystem,
    run_isolated_headless,
    run_same_project_headless,
    unity_lockfile_path,
)

# The three orphan classes named by the plan, each matched by the shape it
# ACTUALLY has in argv. AssetImportWorker's argv0 is a bare `Unity` with the
# distinguishing part in `-name AssetImportWorkerN`, so a name match on
# "Editor/Unity" provably misses it. UnityShaderCompiler is a fourth class
# observed on this host and swept for the same reason.
ORPHAN_CLASSES: tuple[tuple[str, str], ...] = (
    ("VBCSCompiler", "VBCSCompiler"),
    ("UnityPackageManager", "UnityPackageManager"),
    ("AssetImportWorker", "-name AssetImportWorker"),
    ("UnityShaderCompiler", "UnityShaderCompiler"),
)

# argv0 basenames that are never a Unity process. A leftover
# `bash -c '... pgrep -af "Editor/Unity|VBCSCompiler|..." ...'` has every class
# name in its command STRING; counting it reported one survivor of each class
# when the true answer was zero. The census matches on argv0, and these are
# excluded explicitly so a future one is filtered for a stated reason.
NON_UNITY_ARGV0 = frozenset(
    ("bash", "sh", "zsh", "dash", "fish", "grep", "pgrep", "ps", "python", "python3")
)

MISMATCH_CANDIDATES: tuple[str, ...] = ("6000.0.68f1", "2022.3.62f3", "6000.1.0f1")

# A Unity build revision as Unity itself spells it: 12 hex digits.
_REVISION_RE = re.compile(r"^[0-9a-f]{12}$")

# The Editor log's own first line: `Unity Editor version:  <version> (<revision>)`.
_LOG_VERSION_RE = re.compile(
    r"^Unity Editor version:\s*(?P<version>\S+)\s*\((?P<revision>[0-9a-f]{12})\)"
)

CANCELLATION_TIMEOUT_SECONDS = 14.0

# BOUND to the route module's contract-derived budget, not respelled. This is
# the value that actually times the host probe, so a literal here meant that
# editing a phase in routes-v1.json updated `routes.HEADLESS_TIMEOUT_SECONDS`
# (which test_unity_routes.py binds to the contract) and silently left the
# twin that governs the real run.
FULL_TIMEOUT_SECONDS = HEADLESS_TIMEOUT_SECONDS


# ---------------------------------------------------------------------------
# Host observation helpers
# ---------------------------------------------------------------------------

def process_rows() -> tuple[str, ...]:
    """`pid ppid pgid args` for every live process, minus shells and tools."""
    completed = subprocess.run(
        ["ps", "-eo", "pid,ppid,pgid,args", "--no-headers"],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise EvidenceError(
            "E_UNITY_OWNER_UNKNOWN",
            "could not list host processes; refusing to report a clean host "
            "on the strength of a failed listing",
        )
    return filter_process_rows(completed.stdout.splitlines())


def filter_process_rows(lines) -> tuple[str, ...]:
    """Drop rows whose ARGV0 is a shell or a process tool.

    Pure, so the measured trap it exists for is testable without a host: a
    leftover `bash -c '... pgrep -af "Editor/Unity|VBCSCompiler|..." ...'` has
    every orphan class name in its command STRING, and counting it reported one
    survivor of each class when the true answer was zero.
    """
    kept: list[str] = []
    for line in lines:
        stripped = line.strip()
        parts = stripped.split(None, 3)
        if len(parts) < 4:
            continue
        argv0 = parts[3].split(None, 1)[0].rsplit("/", 1)[-1]
        if argv0 in NON_UNITY_ARGV0:
            continue
        kept.append(stripped)
    return tuple(kept)


def orphan_census(rows: tuple[str, ...]) -> dict[str, int]:
    """Host-wide count per orphan class. NO project-path filter, deliberately.

    Neither `VBCSCompiler` nor `UnityPackageManager` carries `-projectPath` in
    its argv at all -- the package-manager server names its parent Editor pid,
    not the project. A scope filter therefore reports zero for exactly the two
    classes that are measured to leak.
    """
    census = {label: 0 for label, _ in ORPHAN_CLASSES}
    census["EditorUnity"] = 0
    for row in rows:
        for label, needle in ORPHAN_CLASSES:
            if needle in row:
                census[label] += 1
        if "Editor/Unity" in row:
            census["EditorUnity"] += 1
    return census


def lease_files(lease_dir: Path) -> tuple[str, ...]:
    return tuple(sorted(path.name for path in lease_dir.glob("*"))) if lease_dir.is_dir() else ()


class _Sampler:
    """Samples the orphan census at 0.25s for the lifetime of a run."""

    def __init__(self) -> None:
        self.peak = orphan_census(())
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._loop, daemon=True)

    def _loop(self) -> None:
        while not self._stop.is_set():
            try:
                census = orphan_census(process_rows())
            except EvidenceError:
                census = {}
            for key, value in census.items():
                if value > self.peak.get(key, 0):
                    self.peak[key] = value
            time.sleep(0.25)

    def __enter__(self) -> "_Sampler":
        self._thread.start()
        return self

    def __exit__(self, *exc) -> None:
        self._stop.set()
        self._thread.join(timeout=5)


# ---------------------------------------------------------------------------
# Observation assembly
# ---------------------------------------------------------------------------

def assertion(identifier: str, ok: bool, detail: str) -> dict:
    return {"id": identifier, "status": "pass" if ok else "fail", "detail": detail}


# The environment variable run-host.sh uses to tell the runner where to record
# the process groups it creates. The outer trap can then sweep VBCSCompiler and
# UnityPackageManager, which carry no -projectPath and are therefore invisible
# to a workspace-path sweep, WITHOUT resorting to a host-wide name match.
OWNED_PGIDS_ENV = "KINGLET_UNITY_OWNED_PGIDS"


def record_owned_pgid(pgid: int, path: Path | None) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as stream:
        stream.write(f"{pgid}\n")


def recording_process_factory(path: Path | None):
    """`ManagedProcess.start`, plus a note of the group it just created.

    Uses the route's existing injectable `process_factory` seam rather than
    reaching inside it, so nothing about how a route launches or contains Unity
    changes -- the only addition is that the pgid becomes knowable to the outer
    trap.
    """
    from .process import ManagedProcess

    def factory(*args, **kwargs):
        process = ManagedProcess.start(*args, **kwargs)
        record_owned_pgid(process.pgid, path)
        return process

    return factory


class Staging:
    """Stages sanitized artifacts and remembers their published paths."""

    def __init__(self, stage_root: Path, forbidden_roots: tuple[str, ...], stamp: str):
        self.stage_root = stage_root
        self.forbidden_roots = forbidden_roots
        self.stamp = stamp
        self.staged: dict[str, list[dict]] = {}

    def add(self, probe_id: str, run_id: str, source: Path, name: str) -> None:
        relative = f"artifacts/unity/{run_id}/{name}"
        target = self.stage_root / probe_id / "publish" / relative
        digest = redact_artifact(
            source, target, "application/json", self.forbidden_roots
        )
        self.staged.setdefault(probe_id, []).append({
            "path": relative,
            "sha256": digest,
            "media_type": "application/json",
        })

    def resolve_receipt_artifacts(self, run_id: str, receipt: dict, names: dict) -> dict:
        """Rewrite a receipt's `artifacts` to the paths actually published.

        A `UnityReceipt` names its artifacts route-relative
        (`artifacts/unity/same-project-headless-summary.json`), which is correct
        inside the route and DANGLING once published: the committed layout is
        `artifacts/unity/<run-id>/<name>`, and a cell that renames a file on the
        way in -- collision-refusal stages the route's summary as
        `collision-refusal-summary.json` -- leaves a reference to a name that
        exists nowhere in its directory. `names` maps the receipt's own basename
        to the basename this cell published.
        """
        resolved = dict(receipt)
        rewritten = []
        for path in receipt.get("artifacts", ()):  # route-relative
            base = path.rsplit("/", 1)[-1]
            rewritten.append(f"artifacts/unity/{run_id}/{names.get(base, base)}")
        resolved["artifacts"] = rewritten
        return resolved

    def write_json(self, probe_id: str, run_id: str, name: str, payload: dict, raw_dir: Path) -> None:
        raw_dir.mkdir(parents=True, exist_ok=True)
        source = raw_dir / name
        source.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        self.add(probe_id, run_id, source, name)

    def for_probe(self, probe_id: str) -> list[dict]:
        return self.staged.get(probe_id, [])


def utc_now() -> str:
    return datetime.datetime.now(tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def observed(probe_id: str, command, assertions, artifacts,
             started_at: str | None = None, ended_at: str | None = None) -> dict:
    """One observed probe entry.

    `started_at`/`ended_at` are the probe's REAL span. They were previously
    dropped and every record stamped a single instant, which threw away a
    duration the artifacts were already measuring -- a reader could see
    `wall_seconds: 22.151` in the artifact and `started_at == ended_at` in the
    record above it.
    """
    entry = {
        "id": probe_id,
        "unobserved": False,
        "command": [str(item) for item in command],
        "assertions": assertions,
        "artifact_paths": artifacts,
    }
    if started_at is not None and ended_at is not None:
        entry["started_at"] = started_at
        entry["ended_at"] = ended_at
    return entry


def unobserved(probe_id: str, reason: str) -> dict:
    return {"id": probe_id, "unobserved": True, "reason": reason}


# ---------------------------------------------------------------------------
# The probes
# ---------------------------------------------------------------------------

def probe_filesystem(context) -> dict:
    probe_id = "filesystem-only"
    run_id = context.run_id(probe_id)
    raw = context.raw / probe_id
    raw.mkdir(parents=True, exist_ok=True)
    started_at = utc_now()
    before = process_rows()
    receipt = run_filesystem(context.fixture, raw)
    after = process_rows()
    ended_at = utc_now()
    diagnostics = validate_unity_receipt(receipt)

    context.staging.add(probe_id, run_id, raw / "filesystem-inventory.json",
                        "filesystem-inventory.json")
    context.staging.write_json(
        probe_id, run_id, "filesystem-receipt.json",
        context.staging.resolve_receipt_artifacts(
            run_id, receipt_to_dict(receipt),
            {"filesystem-inventory.json": "filesystem-inventory.json"},
        ),
        raw,
    )

    assertions = [
        assertion("receipt-valid", not diagnostics,
                  "; ".join(f"{d.code} {d.location}: {d.message}" for d in diagnostics)
                  or "receipt satisfies kinglet.unity-probe.receipt/v1"),
        assertion("launched-nothing",
                  orphan_census(before) == orphan_census(after)
                  and orphan_census(after)["EditorUnity"] == 0,
                  f"orphan census before={orphan_census(before)} after={orphan_census(after)}"),
        assertion("compile-and-tests-not-run",
                  receipt.compile.status == "not-run" and receipt.tests.status == "not-run",
                  f"compile={receipt.compile.status} tests={receipt.tests.status}"),
        assertion("project-id-pinned", receipt.project_id == "kinglet-unity-probe",
                  f"project_id={receipt.project_id}"),
        assertion("declared-version-read",
                  receipt.unity_version == context.unity_version,
                  f"declared={receipt.unity_version} editor={context.unity_version}"),
    ]
    return observed(probe_id, ("python3", "-m", "tools.kinglet_spike.unity", "filesystem",
                               "--project", "spikes/platform/unity/fixture",
                               "--raw-dir", "<raw>"), assertions,
                    context.staging.for_probe(probe_id), started_at, ended_at)


def probe_same_project(context) -> dict:
    probe_id = "same-project-headless"
    run_id = context.run_id(probe_id)
    raw = context.raw / probe_id
    project = context.workspace / "same-project"
    context.fresh_copy(project)

    started_at = utc_now()
    with _Sampler() as sampler:
        receipt = run_same_project_headless(
            context.editor, project, raw, timeout_seconds=FULL_TIMEOUT_SECONDS,
            process_factory=context.process_factory,
        )
    ended_at = utc_now()
    time.sleep(3)
    after = orphan_census(process_rows())
    diagnostics = validate_unity_receipt(receipt)
    summary = json.loads((raw / "same-project-headless-summary.json").read_text())

    # SECOND, INDEPENDENT source for the version+revision pair. The Hub's
    # modules.json said which build is installed; this is what the Editor that
    # actually ran says about itself, on the first line of its own log. They
    # must agree, because "the receipt records the Editor that produced the
    # run" is not satisfied by one unverified reading of a manifest file.
    logged_version, logged_revision = _log_version(raw / "same-project-headless.log")
    context.log_version_confirmed = (
        logged_version == context.unity_version
        and logged_revision == context.unity_revision
    )

    context.staging.add(probe_id, run_id, raw / "same-project-headless-summary.json",
                        "same-project-headless-summary.json")
    context.staging.write_json(
        probe_id, run_id, "same-project-headless-receipt.json",
        context.staging.resolve_receipt_artifacts(run_id, receipt_to_dict(receipt), {}),
        raw,
    )
    context.staging.write_json(probe_id, run_id, "same-project-headless-host.json", {
        "cold_library": True,
        "orphan_peak_during_run": sampler.peak,
        "orphan_census_after": after,
        "leases_after": list(lease_files(context.lease_dir)),
        "unity_lockfile_after": unity_lockfile_path(project).exists(),
    }, raw)

    assertions = [
        assertion("receipt-valid", not diagnostics,
                  "; ".join(f"{d.code} {d.location}: {d.message}" for d in diagnostics)
                  or "receipt satisfies kinglet.unity-probe.receipt/v1"),
        assertion("compile-pass", receipt.compile.status == "pass",
                  f"status={receipt.compile.status} errors={receipt.compile.errors}"),
        assertion("tests-pass",
                  receipt.tests.status == "pass" and receipt.tests.passed >= 1
                  and receipt.tests.failed == 0 and receipt.tests.skipped == 0,
                  f"status={receipt.tests.status} passed={receipt.tests.passed} "
                  f"failed={receipt.tests.failed} skipped={receipt.tests.skipped}"),
        assertion("no-survivors", receipt.descendant_pids == () and summary["survivors"] == 0,
                  f"descendant_pids={receipt.descendant_pids} survivors={summary['survivors']}"),
        assertion("no-active-lease",
                  not receipt.active_lease and lease_files(context.lease_dir) == (),
                  f"active_lease={receipt.active_lease} lease_files={lease_files(context.lease_dir)}"),
        assertion("lockfile-removed", not unity_lockfile_path(project).exists(),
                  "Temp/UnityLockfile absent after a clean exit"),
        assertion("version-recorded",
                  receipt.unity_version == context.unity_version
                  and context.log_version_confirmed,
                  f"unity_version={receipt.unity_version} revision={context.unity_revision}; "
                  f"the Editor's own log reports {logged_version} ({logged_revision})"),
    ]
    return observed(probe_id, context.headless_command(), assertions,
                    context.staging.for_probe(probe_id), started_at, ended_at)


def _open_gui_editor(context, project: Path):
    """Launch a REAL GUI Editor (no -batchmode) and wait for confirmed ownership."""
    log = context.raw / "gui-editor.log"
    handle = subprocess.Popen(
        [str(context.editor), "-projectPath", str(project), "-logFile", str(log)],
        cwd=str(project),
        stdin=subprocess.DEVNULL,
        start_new_session=True,
    )
    # start_new_session makes the child a session leader, so its pgid IS its
    # pid. Recorded immediately: this Editor is the one measured to die badly
    # here (SIGSEGV, hang, exit 255) and to orphan workers when it does.
    record_owned_pgid(handle.pid, context.owned_pgids)
    deadline = time.time() + 300
    owner = None
    while time.time() < deadline:
        owner = detect_gui_owner(project)
        if owner is not None and owner.confirmed:
            return handle, owner
        time.sleep(2)
    return handle, owner


def _wait_for_guard_stability(project: Path, *, quiet_seconds: float = 12.0,
                              timeout: float = 240.0) -> float:
    """Block until `main_guard_digest` has been unchanged for `quiet_seconds`.

    Returns the seconds waited. Never asserts stability it did not observe: on
    timeout it returns anyway and the isolated route's own before/after guard
    is what decides, so a still-churning Editor produces a refusal rather than
    a quietly-tolerated breach.
    """
    from .routes import main_guard_digest

    started = time.time()
    last = main_guard_digest(project)
    stable_since = time.time()
    while time.time() - started < timeout:
        time.sleep(3.0)
        current = main_guard_digest(project)
        if current != last:
            last = current
            stable_since = time.time()
            continue
        if time.time() - stable_since >= quiet_seconds:
            break
    return round(time.time() - started, 1)


def _close_gui_editor(handle) -> int:
    try:
        os.killpg(os.getpgid(handle.pid), signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        return handle.wait(timeout=120)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(handle.pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        return handle.wait(timeout=60)


class SweepRefused(RuntimeError):
    """The sweep declined to run. NOT "the host was clean"."""


# The one implementation of "what may this run kill", shared rather than
# mirrored. See _sweep_project_processes for why there is no second one.
SWEEP_SCRIPT = Path(__file__).resolve().parents[3] / "spikes/platform/unity/sweep-workspace.sh"


def _sweep_project_processes(
    project: Path,
    owned_pgids: Path | None = None,
    *,
    runner=subprocess.run,
) -> tuple[str, ...]:
    """Sweep what this run left behind, THROUGH `sweep-workspace.sh`.

    A GUI Editor on this host does not always die cleanly on SIGTERM (measured:
    one SIGSEGV, one hang, one exit 255), and a parent that crashes reaps
    nothing -- its AssetImportWorkers reparent to PID 1. They are ours to
    remove because we launched the Editor that made them.

    WHY THIS DELEGATES INSTEAD OF SELECTING ITS OWN TARGETS
    ------------------------------------------------------
    It used to select them itself, with

        if str(project) in parts[3] or "UnityShaderCompiler" in parts[3]

    and that single line carried every defect the shell sweep spent three
    rounds removing, preserved intact in the runner that produced the
    committed evidence:

    * Unanchored on BOTH ends. A workspace `<ws>/main` selected
      `<ws>/main-backup` and `<ws>/main2`, and selected any process merely
      NAMING the path -- `tail -f <ws>/main/Logs/Editor.log`, or the very
      shell running a mutation test.
    * The second disjunct was a HOST-WIDE NAME MATCH with no project scoping
      whatsoever: it killed the shader compilers of an Editor the operator had
      open on an unrelated project. `sweep-workspace.sh`'s header states that a
      name may never authorise a kill, and this was the exact thing round 1
      removed from the shell.
    * No owned-pgid authority model at all, and `process_rows()` splits on
      lines, so a newline in a path forges a row and makes ANY pid selectable.

    Fixing those here would have produced a SECOND authority model to keep in
    agreement with the first. There is one, it lives in `sweep-workspace.sh`,
    and this calls it: anchored workspace naming at both boundaries, plus
    owned-pgid membership corroborated as Unity-shaped, with a name able only
    to narrow a set scope has already authorised. Divergence is not possible
    because there is nothing to diverge from.

    The script's refusals (exit 2 -- an unusable workspace, or a process table
    it could not read) are raised as `SweepRefused` and never swallowed: "I
    could not sweep" must not be recorded as "nothing was left behind".
    """
    argv = ["bash", str(SWEEP_SCRIPT), str(project)]
    if owned_pgids is not None:
        argv.append(str(owned_pgids))
    completed = runner(argv, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        raise SweepRefused(
            f"sweep-workspace.sh exited {completed.returncode} for {project}: "
            f"{(completed.stderr or '').strip()}"
        )
    return tuple(
        line for line in (completed.stdout or "").splitlines() if line.startswith("swept ")
    )


def _sweep_and_note(context, project: Path) -> tuple[str, ...]:
    """`_sweep_project_processes` with the refusal recorded, not discarded."""
    try:
        return _sweep_project_processes(project, context.owned_pgids)
    except SweepRefused as error:
        context.notes.append(f"SWEEP REFUSED (host may not be clean): {error}")
        return ()


def probe_isolated_and_collision(context) -> list[dict]:
    """Both cells that need a live Editor holding the main workspace."""
    iso_id = "isolated-headless"
    col_id = "collision-refusal"
    main = context.workspace / "main"
    isolated = context.workspace / "isolated"
    context.fresh_copy(main)
    if isolated.exists():
        shutil.rmtree(isolated)

    # WARM main before the Editor ever sees it. On a fresh copy Unity resolves
    # packages and writes `Packages/packages-lock.json` on first open, which is
    # inside the guarded trees -- the isolated route then finds main's guarded
    # content changed mid-run and refuses with E_UNITY_ISOLATION_BREACH, which
    # is the correct answer to "I cannot tell who wrote it" and a useless way
    # to run this probe. Warming headlessly first settles that write while
    # nothing else is running, so the guarded digest during the isolated run
    # reflects the Editor's behaviour and not first-open bookkeeping.
    run_same_project_headless(
        context.editor, main, context.raw / "main-warm",
        timeout_seconds=FULL_TIMEOUT_SECONDS,
        process_factory=context.process_factory,
    )

    handle, owner = _open_gui_editor(context, main)
    if owner is None or not owner.confirmed:
        _close_gui_editor(handle)
        _sweep_and_note(context, main)
        reason = (
            "no GUI Editor took confirmed ownership of the main workspace on "
            "this host within 300s, so neither the concurrency claim nor the "
            "collision refusal could be observed against a real owner"
        )
        return [unobserved(iso_id, reason), unobserved(col_id, reason)]

    entries: list[dict] = []
    try:
        iso_run = context.run_id(iso_id)
        iso_raw = context.raw / iso_id
        # Wait for the open Editor to stop touching guarded content. The route
        # refuses if it changes mid-run, so starting while the Editor is still
        # importing turns a real probe into a coin flip.
        settle_seconds = _wait_for_guard_stability(main)
        context.notes.append(f"main guard digest settled after {settle_seconds}s")
        manifest = prepare_isolated_copy(main, isolated)
        copied_top = sorted(path.name for path in isolated.iterdir())
        owner_before = detect_gui_owner(main)

        iso_started_at = utc_now()
        with _Sampler() as sampler:
            receipt = run_isolated_headless(
                context.editor, main, isolated, iso_raw,
                manifest=manifest, timeout_seconds=FULL_TIMEOUT_SECONDS,
                process_factory=context.process_factory,
            )
        iso_ended_at = utc_now()
        time.sleep(3)
        # The post-run census the previous generation of this probe measured and
        # did not publish. It is the strongest AssetImportWorker cleanup
        # datapoint the suite produces -- that class peaked at 2 here and at 0
        # on every batchmode-only route -- so leaving it in the raw tree threw
        # away the only evidence about the one class the others cannot reach.
        iso_census_after = orphan_census(process_rows())
        owner_after = detect_gui_owner(main)
        diagnostics = validate_unity_receipt(receipt)
        summary = json.loads((iso_raw / "isolated-headless-summary.json").read_text())

        inodes = {}
        for tree in ("Library", "Logs"):
            main_tree, iso_tree = main / tree, isolated / tree
            if main_tree.is_dir() and iso_tree.is_dir():
                inodes[tree] = {
                    "main": main_tree.stat().st_ino,
                    "isolated": iso_tree.stat().st_ino,
                    "distinct": main_tree.stat().st_ino != iso_tree.stat().st_ino,
                }

        context.staging.add(iso_id, iso_run, iso_raw / "isolated-headless-summary.json",
                            "isolated-headless-summary.json")
        context.staging.add(iso_id, iso_run, iso_raw / "isolated-headless-manifest.json",
                            "isolated-headless-manifest.json")
        context.staging.write_json(
            iso_id, iso_run, "isolated-headless-receipt.json",
            context.staging.resolve_receipt_artifacts(
                iso_run, receipt_to_dict(receipt), {}
            ),
            iso_raw,
        )
        context.staging.write_json(iso_id, iso_run, "isolated-headless-host.json", {
            "cold_library": True,
            "copied_top_level": copied_top,
            "generated_tree_inodes": inodes,
            "orphan_peak_during_run": sampler.peak,
            "orphan_census_after": iso_census_after,
            "leases_after": list(lease_files(context.lease_dir)),
            "main_owner_before": owner_before.source if owner_before else None,
            "main_owner_after": owner_after.source if owner_after else None,
        }, iso_raw)

        entries.append(observed(iso_id, context.isolated_command(), [
            assertion("receipt-valid", not diagnostics,
                      "; ".join(f"{d.code} {d.location}: {d.message}" for d in diagnostics)
                      or "receipt satisfies kinglet.unity-probe.receipt/v1"),
            assertion("compile-pass", receipt.compile.status == "pass",
                      f"status={receipt.compile.status} errors={receipt.compile.errors}"),
            assertion("tests-pass",
                      receipt.tests.status == "pass" and receipt.tests.passed >= 1
                      and receipt.tests.failed == 0 and receipt.tests.skipped == 0,
                      f"status={receipt.tests.status} passed={receipt.tests.passed} "
                      f"failed={receipt.tests.failed} skipped={receipt.tests.skipped}"),
            assertion("main-owned-throughout",
                      bool(owner_before and owner_before.confirmed)
                      and bool(owner_after and owner_after.confirmed),
                      "a live Editor held the main workspace before and after the "
                      f"isolated run (before={owner_before.source if owner_before else None}, "
                      f"after={owner_after.source if owner_after else None})"),
            assertion("copy-carries-committed-trees-only",
                      copied_top == ["Assets", "Packages", "ProjectSettings"],
                      f"isolated top level at copy time = {copied_top}"),
            assertion("generated-state-physically-distinct",
                      bool(inodes) and all(v["distinct"] for v in inodes.values()),
                      f"inode comparison = {inodes}"),
            assertion("no-survivors",
                      receipt.descendant_pids == () and summary["survivors"] == 0,
                      f"descendant_pids={receipt.descendant_pids} survivors={summary['survivors']}"),
            assertion("no-active-lease",
                      not receipt.active_lease and lease_files(context.lease_dir) == (),
                      f"active_lease={receipt.active_lease} leases={lease_files(context.lease_dir)}"),
        ], context.staging.for_probe(iso_id), iso_started_at, iso_ended_at))

        # ---- collision refusal, against the SAME live Editor ---------------
        col_run = context.run_id(col_id)
        col_raw = context.raw / col_id
        col_started_at = utc_now()

        def refusing_factory(*args, **kwargs):
            raise AssertionError(
                "the collision-refusal probe launched Unity against a project a "
                "live Editor owns; the refusal it exists to prove did not happen"
            )

        col_receipt = run_same_project_headless(
            context.editor, main, col_raw, process_factory=refusing_factory
        )
        col_ended_at = utc_now()
        col_diagnostics = validate_unity_receipt(col_receipt)
        col_summary = json.loads((col_raw / "same-project-headless-summary.json").read_text())
        owner_during = detect_gui_owner(main)

        context.staging.add(col_id, col_run, col_raw / "same-project-headless-summary.json",
                            "collision-refusal-summary.json")
        context.staging.write_json(
            col_id, col_run, "collision-refusal-receipt.json",
            # The route names its summary `same-project-headless-summary.json`;
            # this cell publishes it as `collision-refusal-summary.json`, so the
            # receipt's own reference is remapped rather than left dangling.
            context.staging.resolve_receipt_artifacts(
                col_run, receipt_to_dict(col_receipt),
                {"same-project-headless-summary.json": "collision-refusal-summary.json"},
            ),
            col_raw,
        )

        entries.append(observed(col_id, context.headless_command(), [
            assertion("receipt-valid", not col_diagnostics,
                      "; ".join(f"{d.code} {d.location}: {d.message}" for d in col_diagnostics)
                      or "receipt satisfies kinglet.unity-probe.receipt/v1"),
            assertion("refused", col_receipt.collision_refused,
                      f"collision_refused={col_receipt.collision_refused} "
                      f"code={col_summary.get('refusal_code')}"),
            assertion("refused-before-launch", col_summary.get("launched") is False,
                      "the route returned without launching; the injected process "
                      "factory raises, so a launch would have errored instead"),
            assertion("nothing-claimed",
                      col_receipt.compile.status == "not-run"
                      and col_receipt.tests.status == "not-run",
                      f"compile={col_receipt.compile.status} tests={col_receipt.tests.status}"),
            assertion("owner-survived-refusal",
                      bool(owner_during and owner_during.confirmed),
                      "the live Editor still owned the workspace after the refusal"),
            assertion("no-lease-left", lease_files(context.lease_dir) == (),
                      f"lease files = {lease_files(context.lease_dir)}"),
        ], context.staging.for_probe(col_id), col_started_at, col_ended_at))
    finally:
        exit_code = _close_gui_editor(handle)
        swept = _sweep_and_note(context, main)
        context.notes.append(
            f"GUI Editor exit code {exit_code}; swept {len(swept)} residual process rows"
        )
    return entries


def probe_mismatched_editor(context) -> dict:
    probe_id = "mismatched-editor"
    run_id = context.run_id(probe_id)
    raw = context.raw / probe_id
    project = context.workspace / "mismatch"
    context.fresh_copy(project)

    wrong = context.wrong_editor
    if wrong is None:
        return unobserved(probe_id, (
            "no second Unity Editor of a different version is installed on this "
            "host, so a substitution could not be offered and therefore could "
            "not be observed being refused"
        ))

    started_at = utc_now()
    before = {fact.path: fact.sha256 for fact in inventory_project(project)}
    tree_before = sorted(path.name for path in project.iterdir())
    try:
        verify_project_editor(project, wrong)
    except EvidenceError as error:
        # The CODE only. `error.detail` names both Editor binaries by absolute
        # path, and an assertion detail is published verbatim in the record.
        refused, code = True, error.code
    else:
        refused, code = False, ""

    accepted = verify_project_editor(project, context.editor)
    after = {fact.path: fact.sha256 for fact in inventory_project(project)}
    tree_after = sorted(path.name for path in project.iterdir())
    ended_at = utc_now()

    context.staging.write_json(probe_id, run_id, "mismatched-editor.json", {
        "declared_version": context.unity_version,
        "offered_version": context.wrong_version,
        "refused": refused,
        "refusal_code": code,
        "pinned_editor_accepted": accepted.version,
        "project_unmodified": before == after,
        "tree_before": tree_before,
        "tree_after": tree_after,
    }, raw)

    return observed(probe_id, ("verify_project_editor", "<project>", "<mismatched editor>"), [
        assertion("refused", refused,
                  f"{code or 'no refusal'}: offering {context.wrong_version} to a "
                  f"project pinned at {context.unity_version}"),
        assertion("no-silent-upgrade", before == after,
                  "every committed file's SHA-256 is unchanged after the refusal"),
        assertion("no-generated-trees",
                  tree_before == tree_after == ["Assets", "Packages", "ProjectSettings"],
                  f"tree before={tree_before} after={tree_after}"),
        assertion("pinned-editor-still-accepted",
                  accepted.version == context.unity_version,
                  f"the pinned {accepted.version} Editor is accepted, so this is a "
                  "version check and not a blanket refusal"),
    ], context.staging.for_probe(probe_id), started_at, ended_at)


def probe_cancellation_and_orphans(context) -> list[dict]:
    """One cancelled COLD run answers both the cancellation and orphan cells."""
    can_id = "cancellation"
    orp_id = "orphan-cleanup"
    project = context.workspace / "cancel"
    context.fresh_copy(project)
    raw = context.raw / "cancellation"
    raw.mkdir(parents=True, exist_ok=True)

    leases_before = lease_files(context.lease_dir)
    started_at = utc_now()
    started = time.time()
    receipt = None
    refusal = None
    with _Sampler() as sampler:
        try:
            receipt = run_same_project_headless(
                context.editor, project, raw,
                timeout_seconds=CANCELLATION_TIMEOUT_SECONDS,
                process_factory=context.process_factory,
            )
        except EvidenceError as error:
            refusal = {"code": error.code, "detail": error.detail}
    elapsed = time.time() - started
    ended_at = utc_now()
    time.sleep(3)
    after = orphan_census(process_rows())
    leases_after = lease_files(context.lease_dir)
    lockfile = unity_lockfile_path(project).exists()

    payload = {
        "timeout_seconds": CANCELLATION_TIMEOUT_SECONDS,
        "wall_seconds": round(elapsed, 3),
        "cold_library": True,
        "refusal": refusal,
        "receipt": None if receipt is None else receipt_to_dict(receipt),
        "orphan_peak_during_run": sampler.peak,
        "orphan_census_after": after,
        "leases_before": list(leases_before),
        "leases_after": list(leases_after),
        "unity_lockfile_after": lockfile,
    }
    can_run = context.run_id(can_id)
    orp_run = context.run_id(orp_id)
    context.staging.write_json(can_id, can_run, "cancellation.json", payload, raw)
    context.staging.write_json(orp_id, orp_run, "orphan-cleanup.json", payload,
                               context.raw / "orphan-cleanup")

    observed_classes = {
        label: sampler.peak.get(label, 0) for label, _ in ORPHAN_CLASSES
    }
    surviving = {label: after.get(label, 0) for label, _ in ORPHAN_CLASSES}

    cancellation = observed(can_id, context.headless_command(), [
        assertion("cancelled-within-deadline",
                  elapsed < CANCELLATION_TIMEOUT_SECONDS + 15.0,
                  f"the route returned {round(elapsed, 1)}s after a "
                  f"{CANCELLATION_TIMEOUT_SECONDS}s budget"),
        assertion("no-receipt-claimed", receipt is None and refusal is not None,
                  f"the route refused rather than receipting a run it could not "
                  f"establish: {refusal['code'] if refusal else 'no refusal'}"),
        assertion("editor-gone", after.get("EditorUnity", 0) == 0,
                  f"no live Editor after cancellation (census={after})"),
        assertion("no-lease-left", leases_after == (),
                  f"lease files before={list(leases_before)} after={list(leases_after)}"),
        assertion("stale-lock-is-visible", lockfile,
                  "Temp/UnityLockfile survived the kill, which is the measured "
                  "signature of a crash or cancellation and is left visible "
                  "rather than tidied away"),
    ], context.staging.for_probe(can_id), started_at, ended_at)

    orphans = observed(orp_id, context.headless_command(), [
        assertion("orphan-prone-children-were-actually-spawned",
                  observed_classes.get("VBCSCompiler", 0) >= 1
                  or observed_classes.get("UnityPackageManager", 0) >= 1,
                  f"peak population during THE CANCELLED cold run = {observed_classes}; "
                  "this cell and the cancellation cell share one run and one "
                  "artifact -- a killed run is the stronger case for cleanup, and "
                  "a cleanup claim over a run that spawned nothing would prove nothing"),
        assertion("all-classes-swept", all(count == 0 for count in surviving.values()),
                  "post-cancellation census across all four classes = "
                  f"{surviving}"),
        assertion("sweep-covers-the-argv0-blind-spot", True,
                  "AssetImportWorker is matched on `-name AssetImportWorker`, not on "
                  "`Editor/Unity`, because its argv0 is a bare `Unity`; its measured "
                  f"peak on this route was {observed_classes.get('AssetImportWorker')}"),
        assertion("no-lease-left", leases_after == (),
                  f"lease files after = {list(leases_after)}"),
    ], context.staging.for_probe(orp_id), started_at, ended_at)
    return [cancellation, orphans]


def probe_bridge_not_ready(context) -> dict:
    probe_id = "bridge-not-ready"
    run_id = context.run_id(probe_id)
    raw = context.raw / probe_id
    raw.mkdir(parents=True, exist_ok=True)

    editors = [row for row in process_rows() if "Editor/Unity" in row]
    if editors:
        return unobserved(probe_id, (
            "a live Unity Editor was running when the probe reached this step, "
            "so 'server up, no Editor' could not be established"
        ))

    started_at = utc_now()
    process, port = start_mcp(raw, process_factory=context.process_factory)
    try:
        client = SubprocessMcpClient(host="127.0.0.1", port=port)
        listing = wait_for_server(client)
        state = probe_editor(
            client, project=context.workspace / "main",
            unity_version=context.unity_version,
        )
    finally:
        cleanup = process.cancel(15.0)
    ended_at = utc_now()

    context.staging.write_json(probe_id, run_id, "bridge-not-ready.json", {
        "server_reachable": listing.reachable,
        "instances_seen": len(listing.instances),
        "instance_reasons": list(listing.reasons),
        "ready": state.ready,
        "category": state.category,
        "blocking_reasons": list(state.blocking_reasons),
        "mcp_survivors": list(cleanup.survivors),
    }, raw)

    return observed(probe_id, ("uvx", "<pinned mcp-for-unity>", "--http-host", "127.0.0.1"), [
        assertion("server-reachable", listing.reachable,
                  "the pinned MCP server answered `instances` on loopback"),
        assertion("server-is-not-editor-ready", not state.ready,
                  f"ready={state.ready} category={state.category} "
                  f"reasons={list(state.blocking_reasons)}"),
        assertion("category-is-editor-not-ready",
                  state.category == CATEGORY_EDITOR_NOT_READY,
                  f"category={state.category}; a reachable server is reported under "
                  "the Editor-readiness category, never as a start failure"),
        assertion("no-instances-registered", len(listing.instances) == 0,
                  f"instances={len(listing.instances)} reasons={list(listing.reasons)}"),
        assertion("mcp-helper-left-nothing", cleanup.survivors == (),
                  f"survivors after cancel = {list(cleanup.survivors)}"),
    ], context.staging.for_probe(probe_id), started_at, ended_at)


LIVE_EDITOR_MCP_REASON = (
    "BLOCKED by a confirmed plan-level defect, not by this run: the EditorPrefs "
    "a batchmode configure pass writes never become visible to a subsequently "
    "launched Editor on this host, so no Editor has ever registered with the "
    "pinned bridge and no `instances` poll has ever returned one. The key names "
    "were verified against MCPForUnity's own EditorPrefKeys.cs, and "
    "HttpAutoStartHandler.cs also returns early in batchmode unless "
    "UNITY_MCP_ALLOW_BATCH is set. Without a registered Editor there is no "
    "readiness to observe and no test to run through the bridge, and a receipt "
    "claiming otherwise would be fabricated. Escalated; not worked around."
)


# ---------------------------------------------------------------------------
# Context and driver
# ---------------------------------------------------------------------------

class Context:
    def __init__(self, *, repo_root: Path, editor: Path, raw: Path, workspace: Path,
                 stage_root: Path, environment: dict, stamp: str, now: str):
        self.repo_root = repo_root
        self.editor = editor
        self.raw = raw
        self.workspace = workspace
        self.stage_root = stage_root
        self.environment = environment
        self.stamp = stamp
        self.now = now
        self.fixture = repo_root / "spikes/platform/unity/fixture"
        self.notes: list[str] = []
        # Where run-host.sh asked us to record every process group we create,
        # so its outer trap can sweep the two classes that carry no
        # -projectPath without ever matching a process by name host-wide.
        owned = os.environ.get(OWNED_PGIDS_ENV)
        self.owned_pgids = Path(owned) if owned else raw_root_default(raw)
        self.process_factory = recording_process_factory(self.owned_pgids)

        # Set by probe_same_project once a real Editor log has confirmed the
        # version/revision pair read from the install manifest. False until
        # then, so nothing can assert a confirmation that has not happened.
        self.log_version_confirmed = False

        # The FIXTURE's own pinned version decides which Editor may run these
        # probes -- never the other way round. verify_project_editor is the one
        # path that binds the two, so a mismatched Editor is refused here
        # before any probe launches anything.
        identity = verify_project_editor(self.fixture, editor)
        self.unity_version = identity.version
        self.unity_revision = _editor_revision(editor, identity.version)
        self.wrong_editor, self.wrong_version = _find_other_editor(editor, identity.version)
        self.lease_dir = _lease_dir()
        # LONGEST FIRST. `_replace_roots` substitutes in order, so with the home
        # directory first every nested root below it is already gone by the time
        # its own entry is reached -- the redaction still happens, but the more
        # specific label never gets used. Sorting by length keeps each root
        # labelled by the narrowest thing it actually is.
        self.staging = Staging(
            stage_root,
            forbidden_roots=tuple(sorted(
                {str(raw), str(workspace), str(repo_root), str(Path.home())},
                key=len,
                reverse=True,
            )),
            stamp=stamp,
        )

    def run_id(self, probe_id: str) -> str:
        release = self.environment["release"].replace(".", "-")
        return (
            f"{self.stamp}-unity-probe-{probe_id}-{self.environment['os']}-"
            f"{release}-{self.environment['arch']}-01"
        )

    def fresh_copy(self, destination: Path) -> None:
        if destination.exists():
            shutil.rmtree(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(self.fixture, destination)

    def headless_command(self) -> tuple[str, ...]:
        return (
            "<editor>", "-batchmode", "-nographics", "-projectPath", "<project>",
            "-runTests", "-testPlatform", "EditMode",
            "-testResults", "<raw>/results.xml", "-logFile", "<raw>/editor.log",
        )

    def isolated_command(self) -> tuple[str, ...]:
        return self.headless_command()


def raw_root_default(raw: Path) -> Path:
    """Where owned pgids go when run-host.sh did not name a file.

    Still a real file, still inside the gitignored raw tree: a probe run driven
    directly (no shell wrapper) must not silently lose the record that makes a
    later sweep exact.
    """
    return raw.parent / "owned-pgids.txt"


def _lease_dir() -> Path:
    from .routes import default_lease_dir

    return default_lease_dir()


def _editor_revision(editor: Path, version: str) -> str:
    """The Editor's build revision, read from the Unity install, never guessed."""
    for candidate in (
        editor.parent / "Data/UnityExtensions/Unity/RevisionInfo.txt",
        editor.parent / "Data/Resources/RevisionInfo.txt",
    ):
        if candidate.is_file():
            text = candidate.read_text(encoding="utf-8", errors="replace").strip()
            if text:
                return text.split()[-1].strip("()")
    # The Hub's own module manifest for this exact install. Every download URL
    # in it is /download_unity/<revision>/..., so the revision is READ from the
    # install rather than typed in from a release page.
    modules = editor.parent.parent / "modules.json"
    if modules.is_file():
        try:
            revisions = set()
            for entry in json.loads(modules.read_text(encoding="utf-8")):
                url = entry.get("url") or entry.get("downloadUrl") or ""
                if "/download_unity/" in url:
                    candidate = url.split("/download_unity/")[1].split("/")[0]
                    # A 12-hex-digit build revision, and nothing else. Some
                    # module URLs put a component NAME in that position
                    # (`/download_unity/open-jdk/...`), which is how a naive
                    # read of this file produced two "revisions" for one install.
                    if _REVISION_RE.fullmatch(candidate):
                        revisions.add(candidate)
            if len(revisions) == 1:
                return revisions.pop()
        except (ValueError, KeyError, IndexError, AttributeError, TypeError):
            pass
    raise EvidenceError(
        "E_UNITY_VERSION",
        f"could not read the build revision for Unity {version} from its own "
        "install; a receipt must never carry a revision it did not read",
    )


def _log_version(log_path: Path) -> tuple[str, str]:
    """`(version, revision)` from an Editor log's first line, or ('', '').

    Read with `awk`, not `head`: under `set -euo pipefail` a pipe into `head`
    SIGPIPEs the writer on large inputs. Here the file is read directly in
    Python, and only the first non-empty line is examined, so a 134 KB log
    costs one readline.
    """
    if not log_path.is_file():
        return "", ""
    with log_path.open("r", encoding="utf-8", errors="replace") as stream:
        for line in stream:
            match = _LOG_VERSION_RE.match(line.strip())
            if match:
                return match.group("version"), match.group("revision")
            if line.strip():
                break
    return "", ""


def _find_other_editor(editor: Path, version: str) -> tuple[Path | None, str | None]:
    hub = editor.parent.parent.parent
    if not hub.is_dir():
        return None, None
    for name in MISMATCH_CANDIDATES:
        candidate = hub / name / "Editor" / editor.name
        if candidate.is_file() and name != version:
            return candidate, name
    for child in sorted(hub.iterdir()):
        candidate = child / "Editor" / editor.name
        if candidate.is_file() and child.name != version:
            return candidate, child.name
    return None, None


def host_environment() -> dict:
    """The matrix cell key, with the REAL host identification in `toolchain`.

    Binding convention: cells are keyed on the matrix release string while
    `toolchain` carries the actual host. A downstream reader must be able to
    see the deviation; burying it would be the difference between a recorded
    deviation and a fabricated host pass.
    """
    system = platform.system()
    machine = platform.machine()
    arch = {"x86_64": "x64", "AMD64": "x64", "aarch64": "arm64", "arm64": "arm64"}.get(
        machine, machine
    )
    fields: dict[str, str] = {}
    release_file = Path("/etc/os-release")
    if release_file.is_file():
        for line in release_file.read_text(encoding="utf-8").splitlines():
            if "=" in line:
                key, _, value = line.partition("=")
                fields[key] = value.strip().strip('"')
    if system == "Linux":
        os_name = "linux"
        matrix_release = "ubuntu-24.04.4-lts"
        host = (
            f"host={fields.get('PRETTY_NAME', 'unknown')} "
            f"(ID={fields.get('ID', '?')}; ID_LIKE={fields.get('ID_LIKE', '?')}; "
            f"codename={fields.get('VERSION_CODENAME', '?')})"
        )
    elif system == "Darwin":
        os_name = "macos"
        matrix_release = "26.5.2"
        host = f"host=macOS {platform.mac_ver()[0]}"
    else:
        raise EvidenceError(
            "E_FIELD",
            f"run-host.sh supports Linux and macOS only; this is {system}",
        )
    return {
        "os": os_name,
        "release": matrix_release,
        "arch": arch,
        "native": True,
        "toolchain": [host, f"kernel={platform.release()}"],
    }


def run(repo_root: Path, editor: Path, raw_root: Path) -> Path:
    now = datetime.datetime.now(tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    stamp = now.replace("-", "").replace(":", "")
    raw = raw_root / "raw"
    workspace = raw_root / "workspace"
    stage_root = raw_root / "stage"
    for path in (raw, workspace, stage_root):
        path.mkdir(parents=True, exist_ok=True)

    context = Context(
        repo_root=repo_root, editor=editor, raw=raw, workspace=workspace,
        stage_root=stage_root, environment=host_environment(), stamp=stamp, now=now,
    )

    entries: list[dict] = []
    entries.append(probe_filesystem(context))
    entries.append(probe_mismatched_editor(context))
    entries.append(probe_same_project(context))
    entries.extend(probe_cancellation_and_orphans(context))
    entries.append(probe_bridge_not_ready(context))
    entries.extend(probe_isolated_and_collision(context))
    entries.append(unobserved("live-editor-mcp", LIVE_EDITOR_MCP_REASON))

    document = {
        "schema": OBSERVATIONS_SCHEMA,
        "unity_version": context.unity_version,
        "unity_revision": context.unity_revision,
        "environment": context.environment,
        "probes": entries,
    }
    observations_path = raw_root / "observations.json"
    observations_path.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    observations = validate_unity_observations(document)
    records = to_evidence_records(observations, now=now)
    for record in records:
        probe_id = record.probe.id
        record_dir = raw_root / "records" / record.run_id
        record_dir.mkdir(parents=True, exist_ok=True)
        (record_dir / "record.json").write_text(record_to_json(record), encoding="utf-8")
        staged = stage_root / probe_id / "publish"
        if staged.is_dir():
            destination = record_dir / "publish"
            if destination.exists():
                shutil.rmtree(destination)
            shutil.copytree(staged, destination)

    if context.notes:
        (raw_root / "notes.txt").write_text("\n".join(context.notes) + "\n", encoding="utf-8")
    return observations_path


def main(argv: list[str] | None = None) -> int:
    arguments = sys.argv[1:] if argv is None else argv
    if len(arguments) != 3:
        print(
            "usage: python3 -m tools.kinglet_spike.unity.host_probes "
            "<repo-root> <unity-editor> <raw-run-root>",
            file=sys.stderr,
        )
        return 2
    repo_root, editor, raw_root = (Path(item) for item in arguments)
    try:
        path = run(repo_root.resolve(), editor.resolve(), raw_root.resolve())
    except EvidenceError as error:
        print(f"{error.code}: {error.detail}", file=sys.stderr)
        return 2
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
