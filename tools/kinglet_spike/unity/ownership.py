"""ownership.py -- GUI ownership detection and pre-launch refusal.

Never launch batchmode against a physical project path a live Unity Editor
already owns (plan global constraint). The detection logic itself is split
into small pure functions that take a process table (and lock-file facts)
as plain arguments and return a decision -- no subprocess call, no file I/O
-- so tests can drive every branch (owned / not-owned / stale-lock-unknown)
from a fabricated table on any host, per the plan's "extract host gates as
injectable pure functions" lesson from 0R's review. detect_gui_owner() and
assert_headless_safe() are the only functions that touch the real OS, and
they do so through an injectable provider with a real default.

Two traps this module exists to avoid, both observed or reproduced live:

1. A loose substring/grep match on a process's command line finds ITSELF
   (this controller's own shell command line can contain the text
   "Editor/Unity" merely by naming it), or finds an unrelated Unity-shipped
   helper whose path merely CONTAINS "Unity" -- `UnityShaderCompiler` and
   `unityhub` are both real, non-Editor processes. This module only ever
   treats a process as a candidate Editor when its argv[0] BASENAME is
   EXACTLY "Unity" or "Unity.exe".
2. A space in the project path defeats naive whitespace tokenization: `ps
   -axo command=` prints raw, unescaped argv space-joined, so
   `-projectPath /home/u/My Project -logFile -` splits into `/home/u/My`
   and `Project` as two separate tokens, and comparing only the first
   token against the canonical project silently returns "not owned" for a
   project a live Editor holds open. `_extract_project_path` recombines
   every token after `-projectPath` up to the next flag-shaped token
   (rather than taking exactly one token) specifically to survive this.
   shlex was also tried and rejected here: shlex's shell-escape semantics
   do not describe this data (ps does not shell-quote its output) and
   POSIX-mode shlex.split silently eats backslashes, which is actively
   destructive on a Windows command line (`C:\\Unity\\Editor\\Unity.exe`
   becomes `C:UnityEditorUnity.exe`). Tokenization here is therefore a
   platform-aware, quote-only split (see _tokenize_command_line), never
   shlex.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path, PureWindowsPath
from typing import Callable, Sequence

from ..model import EvidenceError

# (pid, full command line) -- the shape every process-table provider in this
# module (real or injected-for-tests) produces.
ProcessEntry = tuple[int, str]

_WINDOWS_TOKEN_RE = re.compile(r'"[^"]*"|\S+')


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

    Note on naming: "GUI" in this module's public function names describes
    the INTENT (refuse a second launch against a project a person has open)
    but the detector cannot actually distinguish a GUI Editor from a
    concurrent headless run holding the same lock artifacts -- Unity's own
    lock files do not encode that distinction either. A match here means
    "some live Unity process/lock owns this path", stated as such in the
    raised error text rather than overclaiming "GUI".
    """

    pid: int | None
    project_path: str
    source: str
    confirmed: bool
    detail: str


# ---------------------------------------------------------------------------
# Pure helpers -- no I/O, fully unit-testable.
# ---------------------------------------------------------------------------

def _tokenize_command_line(command: str, *, windows: bool) -> list[str]:
    """Split a raw process command line into argv-shaped tokens.

    windows=False (ps -axo command= on macOS/Linux): the value is raw,
    unescaped argv space-joined by ps itself -- there is no quoting to
    remove, so a plain whitespace split is the correct, non-lossy
    tokenization. (shlex was tried and rejected: its shell-escape rules do
    not apply to this data and silently eat backslashes.)

    windows=True (Win32_Process.CommandLine via PowerShell): Windows
    command lines quote arguments that contain spaces
    (`"C:\\Program Files\\Unity\\Editor\\Unity.exe"`), so a quote-aware
    split is required; backslashes are still never treated as escapes,
    since Windows paths use them as literal separators.
    """
    if windows:
        tokens = _WINDOWS_TOKEN_RE.findall(command)
        return [
            token[1:-1] if len(token) >= 2 and token[0] == token[-1] == '"' else token
            for token in tokens
        ]
    return command.split()


def _is_unity_editor_argv0(token: str, *, windows: bool = False) -> bool:
    """True iff token's basename is exactly Unity's Editor binary name.

    Deliberately not a substring/contains check. `UnityShaderCompiler` and
    `unityhub` are both real Unity-shipped binaries whose path contains the
    text "Unity" but are not the Editor -- a contains-check would treat
    either as a candidate owner.

    windows selects PureWindowsPath so a backslash-separated argv0 (e.g.
    `C:\\Program Files\\Unity\\Editor\\Unity.exe`) is split on the right
    separator -- plain Path() on a POSIX host treats backslashes as
    ordinary filename characters and would never isolate "Unity.exe" at
    all, silently failing to recognize a genuine Windows Editor process.
    """
    name = PureWindowsPath(token).name if windows else Path(token).name
    return name in ("Unity", "Unity.exe")


def _extract_project_path(argv: Sequence[str]) -> str | None:
    """Return the value of `-projectPath`, rejoining a path split by spaces.

    Finds the exact `-projectPath` token (not a substring search over the
    raw line), then collects every following token up to -- but not
    including -- the next flag-shaped token (one starting with "-"), or
    the end of argv. A single-token path (the overwhelmingly common case)
    is returned unchanged; a path containing spaces, which a naive
    single-next-token read would truncate, is rejoined instead of silently
    losing everything after the first space.
    """
    for index, token in enumerate(argv):
        if token != "-projectPath":
            continue
        remainder = argv[index + 1:]
        if not remainder or remainder[0].startswith("-"):
            return None
        parts = [remainder[0]]
        for later in remainder[1:]:
            if later.startswith("-"):
                break
            parts.append(later)
        return " ".join(parts)
    return None


def _canonical(path: str | Path) -> Path:
    """Resolve symlinks and relative components so aliasing can't hide or fake a match."""
    return Path(path).expanduser().resolve()


def find_owning_process(
    process_table: Sequence[ProcessEntry],
    project: Path,
    *,
    windows: bool = False,
) -> ProjectOwner | None:
    """Pure: scan a process table for a live Unity Editor owning `project`.

    A candidate must be a genuine Unity Editor binary (see
    _is_unity_editor_argv0) carrying a -projectPath whose canonicalized
    value equals the canonicalized requested project. Path equality is
    always whole-resolved-path equality, never a prefix/substring
    comparison -- `/x/proj` and `/x/proj2` (no separator between them)
    canonicalize to different paths and never match, and neither does
    `/x/proj` against `/x/proj-other`.
    """
    canonical_project = _canonical(project)
    for pid, command in process_table:
        argv = _tokenize_command_line(command, windows=windows)
        if not argv or not _is_unity_editor_argv0(argv[0], windows=windows):
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


def _pid_is_live_unity_process(
    process_table: Sequence[ProcessEntry], pid: int, *, windows: bool = False
) -> bool:
    for entry_pid, command in process_table:
        if entry_pid != pid:
            continue
        argv = _tokenize_command_line(command, windows=windows)
        if argv and _is_unity_editor_argv0(argv[0], windows=windows):
            return True
    return False


def resolve_lock_owner(
    process_table: Sequence[ProcessEntry],
    project: Path,
    *,
    lockfile_exists: bool,
    instance_pid: int | None,
    windows: bool = False,
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
    if instance_pid is not None and _pid_is_live_unity_process(
        process_table, instance_pid, windows=windows
    ):
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


def _unity_lockfile_present(project: Path) -> bool:
    """True iff Temp/UnityLockfile exists -- and true (not silently False) if we can't tell.

    Path.exists() swallows every OSError internally, including a
    permission error on an unreadable Temp/ directory, and reports that
    identically to "the file genuinely does not exist". For a safety gate
    those are not the same fact: an unreadable directory means "cannot
    confirm absence", which must be treated as a signal, not silently read
    as "no lock".
    """
    lock_path = project / "Temp" / "UnityLockfile"
    try:
        lock_path.stat()
        return True
    except FileNotFoundError:
        return False
    except OSError:
        return True


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
    except (OSError, subprocess.TimeoutExpired) as error:
        raise EvidenceError(
            "E_UNITY_OWNER_UNKNOWN",
            f"cannot list processes to check Unity ownership: {error}",
        ) from error
    if result.returncode != 0:
        raise EvidenceError(
            "E_UNITY_OWNER_UNKNOWN",
            f"process listing failed (ps exit {result.returncode}): "
            f"{result.stderr.strip()}",
        )
    return _parse_posix_process_table(result.stdout)


def _parse_posix_process_table(stdout: str) -> tuple[ProcessEntry, ...]:
    entries: list[ProcessEntry] = []
    for line in stdout.splitlines():
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
    except (OSError, subprocess.TimeoutExpired) as error:
        raise EvidenceError(
            "E_UNITY_OWNER_UNKNOWN",
            f"cannot list processes to check Unity ownership: {error}",
        ) from error
    if result.returncode != 0:
        raise EvidenceError(
            "E_UNITY_OWNER_UNKNOWN",
            f"process listing failed (powershell exit {result.returncode}): "
            f"{result.stderr.strip()}",
        )
    return _parse_windows_process_table(result.stdout)


def _parse_windows_process_table(stdout: str) -> tuple[ProcessEntry, ...]:
    """Pure: parse `<pid><TAB><CommandLine>` lines -- unit-tested from Linux.

    Extracted from _windows_process_table() specifically so the parsing
    logic (as opposed to the PowerShell invocation itself) is exercised by
    tests on every host, not merely reviewed as source text.
    """
    entries: list[ProcessEntry] = []
    for line in stdout.splitlines():
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


def _running_on_windows() -> bool:
    return sys.platform == "win32"


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def detect_gui_owner(
    project: Path,
    *,
    process_table_provider: Callable[[], Sequence[ProcessEntry]] = _default_process_table,
    windows: bool | None = None,
) -> ProjectOwner | None:
    """Detect whether project's physical path is currently owned by a live Unity process.

    Real OS process listing is the default; process_table_provider is the
    injectable seam tests use to drive this from a fabricated table on any
    host, matching every other platform-dependent gate in this plan.
    `windows` selects the command-line tokenization dialect (see
    _tokenize_command_line) and defaults to the real host platform; tests
    override it explicitly rather than relying on sys.platform.

    Returns None only when neither a live process nor a lock artifact gives
    any reason for caution. If the real process_table_provider cannot
    obtain a listing at all (subprocess failure, timeout, non-zero exit),
    it raises E_UNITY_OWNER_UNKNOWN itself rather than silently returning
    an empty table -- this function must never turn "I could not look"
    into "safe".
    """
    is_windows = _running_on_windows() if windows is None else windows
    process_table = tuple(process_table_provider())

    owner = find_owning_process(process_table, project, windows=is_windows)
    if owner is not None:
        return owner

    lockfile_exists = _unity_lockfile_present(project)
    instance_pid = _read_editor_instance_pid(project)

    return resolve_lock_owner(
        process_table,
        project,
        lockfile_exists=lockfile_exists,
        instance_pid=instance_pid,
        windows=is_windows,
    )


def assert_headless_safe(
    project: Path,
    *,
    process_table_provider: Callable[[], Sequence[ProcessEntry]] = _default_process_table,
    windows: bool | None = None,
) -> None:
    """Refuse to launch headless Unity against an owned or ambiguous project.

    Must run before Popen for every headless route (same-project-headless,
    isolated-headless). Raises E_UNITY_OWNED for a confirmed live owner,
    E_UNITY_OWNER_UNKNOWN for a stale lock (or a process listing this
    function could not obtain) that it cannot clear, and returns None only
    when launch is safe.
    """
    owner = detect_gui_owner(
        project, process_table_provider=process_table_provider, windows=windows
    )
    if owner is None:
        return
    if owner.confirmed:
        raise EvidenceError(
            "E_UNITY_OWNED",
            f"project {owner.project_path} is owned by a live Unity process "
            f"(pid {owner.pid}); refusing headless launch",
        )
    raise EvidenceError(
        "E_UNITY_OWNER_UNKNOWN",
        f"project {owner.project_path} has a stale lock with no corroborating "
        "live process; refusing headless launch until inspected",
    )
