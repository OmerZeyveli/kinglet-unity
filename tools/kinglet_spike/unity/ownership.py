"""ownership.py -- GUI ownership detection and pre-launch refusal.

Never launch batchmode against a physical project path a GUI Unity Editor
already owns (plan global constraint). The detection logic itself is split
into small pure functions that take a process table (and lock-file facts)
as plain arguments and return a decision -- no subprocess call, no file I/O
-- so tests can drive every branch (owned / not-owned / stale-lock-unknown)
from a fabricated table on any host, per the plan's "extract host gates as
injectable pure functions" lesson from 0R's review. detect_gui_owner() and
assert_headless_safe() are the only functions that touch the real OS, and
they do so through an injectable provider with a real default.

The trap this module exists to avoid, observed live on this host: a loose
substring/grep match on a process's command line finds ITSELF (this
controller's own shell command line can contain the text "Editor/Unity"
merely by naming it), or finds an unrelated orphaned helper (a `dotnet exec
.../VBCSCompiler.dll` process was observed surviving Unity's own exit with
PPID=1). Neither is a live Editor owning the project. This module only ever
treats a process as a candidate Unity Editor when its argv[0] BASENAME is
exactly "Unity" or "Unity.exe", and only ever matches -projectPath by exact
canonicalized-path equality, never substring containment.
"""
from __future__ import annotations

import json
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence

from ..model import EvidenceError

# (pid, full command line) -- the shape every process-table provider in this
# module (real or injected-for-tests) produces.
ProcessEntry = tuple[int, str]


@dataclass(frozen=True)
class ProjectOwner:
    """A detected owner of a Unity project's physical path.

    confirmed=True: a live process's -projectPath (or, failing that, an
    EditorInstance.json pid) was matched directly against a live Unity
    Editor process. Authoritative -- assert_headless_safe raises
    E_UNITY_OWNED.

    confirmed=False: Temp/UnityLockfile or Library/EditorInstance.json is
    present but no live process corroborates it -- a stale lock. This is
    NOT the same claim as "not owned": the lock proves a project WAS
    opened, and this module cannot prove it is safe now, so
    assert_headless_safe still refuses (E_UNITY_OWNER_UNKNOWN) until a
    human or a future task inspects it.
    """

    pid: int | None
    project_path: str
    source: str
    confirmed: bool
    detail: str


# ---------------------------------------------------------------------------
# Pure helpers -- no I/O, fully unit-testable.
# ---------------------------------------------------------------------------

def _split_command_line(command: str) -> list[str]:
    """Tokenize a process command line into argv-shaped tokens.

    POSIX shlex rules: `ps -axo pid=,command=` on macOS/Linux emits plain
    space-joined argv, and the Windows seam (Win32_Process.CommandLine,
    read via the native helper in _windows_process_table) is normalized to
    the same plain-token shape before it reaches this function.
    """
    try:
        return shlex.split(command)
    except ValueError:
        # Unbalanced quoting (e.g. a truncated ps line) -- degrade to a
        # naive split rather than raising out of a detector.
        return command.split()


def _is_unity_editor_argv0(token: str) -> bool:
    """True iff token's basename is exactly Unity's Editor binary name.

    Deliberately not a substring/contains check -- see the module docstring
    for the two failure modes (self-match, orphaned-helper-match) a loose
    grep produced live on this host.
    """
    return Path(token).name in ("Unity", "Unity.exe")


def _extract_project_path(argv: Sequence[str]) -> str | None:
    """Return the value following an exact `-projectPath` token, or None.

    Exact flag-token match, not a substring search over the raw command
    line -- a substring match would also fire on "-projectPathFoo" or on
    the literal text appearing inside an unrelated argument.
    """
    for index, token in enumerate(argv):
        if token == "-projectPath" and index + 1 < len(argv):
            return argv[index + 1]
    return None


def _canonical(path: str | Path) -> Path:
    """Resolve symlinks and relative components so aliasing can't hide or fake a match."""
    return Path(path).expanduser().resolve()


def find_owning_process(
    process_table: Sequence[ProcessEntry], project: Path
) -> ProjectOwner | None:
    """Pure: scan a process table for a live Unity Editor owning `project`.

    A candidate must be a genuine Unity Editor binary (see
    _is_unity_editor_argv0) carrying an exact -projectPath token whose
    canonicalized value equals the canonicalized requested project. A
    similarly-prefixed sibling path (e.g. requested `.../proj`, process
    reports `.../proj-other`) never matches, because canonicalization
    compares whole resolved paths, not string prefixes.
    """
    canonical_project = _canonical(project)
    for pid, command in process_table:
        argv = _split_command_line(command)
        if not argv or not _is_unity_editor_argv0(argv[0]):
            continue
        raw_path = _extract_project_path(argv)
        if raw_path is None:
            continue
        if _canonical(raw_path) == canonical_project:
            return ProjectOwner(
                pid=pid,
                project_path=str(canonical_project),
                source="process",
                confirmed=True,
                detail=f"pid {pid} has -projectPath {raw_path!r}",
            )
    return None


def _pid_is_live_unity_process(process_table: Sequence[ProcessEntry], pid: int) -> bool:
    for entry_pid, command in process_table:
        if entry_pid != pid:
            continue
        argv = _split_command_line(command)
        if argv and _is_unity_editor_argv0(argv[0]):
            return True
    return False


def resolve_lock_owner(
    process_table: Sequence[ProcessEntry],
    project: Path,
    *,
    lockfile_exists: bool,
    instance_pid: int | None,
) -> ProjectOwner | None:
    """Pure: corroborate lock artifacts when no direct -projectPath match fired.

    Called only after find_owning_process() returned None. A live process
    holding the pid recorded in Library/EditorInstance.json confirms
    ownership even when that process's -projectPath argument could not be
    parsed (e.g. truncated ps output) -- the pid is the strongest remaining
    signal. Absent that corroboration, any lock artifact (Temp/UnityLockfile
    or EditorInstance.json) is treated as a STALE lock: it proves a project
    WAS opened, not that anything owns it now, so this returns an
    *unconfirmed* ProjectOwner rather than None. The caller still refuses
    headless for it (E_UNITY_OWNER_UNKNOWN) -- "probably safe" is not
    "known safe".
    """
    if instance_pid is not None and _pid_is_live_unity_process(process_table, instance_pid):
        return ProjectOwner(
            pid=instance_pid,
            project_path=str(_canonical(project)),
            source="lockfile+process",
            confirmed=True,
            detail=f"EditorInstance.json pid {instance_pid} is a live Unity Editor process",
        )
    if lockfile_exists or instance_pid is not None:
        return ProjectOwner(
            pid=instance_pid,
            project_path=str(_canonical(project)),
            source="lockfile",
            confirmed=False,
            detail=(
                "Temp/UnityLockfile or Library/EditorInstance.json is present "
                "but no live process corroborates it -- stale lock, ownership unknown"
            ),
        )
    return None


def _read_editor_instance_pid(project: Path) -> int | None:
    instance_path = project / "Library" / "EditorInstance.json"
    try:
        raw = instance_path.read_text(encoding="utf-8")
    except OSError:
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    pid = data.get("process_id")
    return pid if isinstance(pid, int) and not isinstance(pid, bool) else None


# ---------------------------------------------------------------------------
# Real OS process-table providers -- the only I/O in this module.
# ---------------------------------------------------------------------------

def _posix_process_table() -> tuple[ProcessEntry, ...]:
    try:
        result = subprocess.run(
            ["ps", "-axo", "pid=,command="],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except OSError:
        return ()
    entries: list[ProcessEntry] = []
    for line in result.stdout.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        parts = stripped.split(maxsplit=1)
        if len(parts) != 2:
            continue
        pid_text, command = parts
        try:
            pid = int(pid_text)
        except ValueError:
            continue
        entries.append((pid, command))
    return tuple(entries)


def _windows_process_table() -> tuple[ProcessEntry, ...]:
    """Win32_Process.CommandLine via PowerShell -- the plan's prescribed Windows source."""
    try:
        result = subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-Command",
                "Get-CimInstance Win32_Process | "
                "ForEach-Object { \"$($_.ProcessId)`t$($_.CommandLine)\" }",
            ],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
    except OSError:
        return ()
    entries: list[ProcessEntry] = []
    for line in result.stdout.splitlines():
        if "\t" not in line:
            continue
        pid_text, command = line.split("\t", 1)
        command = command.strip()
        try:
            pid = int(pid_text.strip())
        except ValueError:
            continue
        if command:
            entries.append((pid, command))
    return tuple(entries)


def _default_process_table() -> tuple[ProcessEntry, ...]:
    if sys.platform == "win32":
        return _windows_process_table()
    return _posix_process_table()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def detect_gui_owner(
    project: Path,
    *,
    process_table_provider: Callable[[], Sequence[ProcessEntry]] = _default_process_table,
) -> ProjectOwner | None:
    """Detect whether project's physical path is currently owned by a GUI Editor.

    Real OS process listing is the default; process_table_provider is the
    injectable seam tests use to drive this from a fabricated table on any
    host, matching every other platform-dependent gate in this plan.
    Returns None only when neither a live process nor a lock artifact gives
    any reason for caution.
    """
    process_table = tuple(process_table_provider())

    owner = find_owning_process(process_table, project)
    if owner is not None:
        return owner

    lock_path = project / "Temp" / "UnityLockfile"
    lockfile_exists = lock_path.exists()
    instance_pid = _read_editor_instance_pid(project)

    return resolve_lock_owner(
        process_table,
        project,
        lockfile_exists=lockfile_exists,
        instance_pid=instance_pid,
    )


def assert_headless_safe(
    project: Path,
    *,
    process_table_provider: Callable[[], Sequence[ProcessEntry]] = _default_process_table,
) -> None:
    """Refuse to launch headless Unity against an owned or ambiguous project.

    Must run before Popen for every headless route (same-project-headless,
    isolated-headless). Raises E_UNITY_OWNED for a confirmed live GUI
    owner, E_UNITY_OWNER_UNKNOWN for a stale lock this function cannot
    clear, and returns None only when launch is safe.
    """
    owner = detect_gui_owner(project, process_table_provider=process_table_provider)
    if owner is None:
        return
    if owner.confirmed:
        raise EvidenceError(
            "E_UNITY_OWNED",
            f"project {owner.project_path} is owned by a live Unity Editor "
            f"(pid {owner.pid}); refusing headless launch",
        )
    raise EvidenceError(
        "E_UNITY_OWNER_UNKNOWN",
        f"project {owner.project_path} has a stale lock with no corroborating "
        "live process; refusing headless launch until inspected",
    )
