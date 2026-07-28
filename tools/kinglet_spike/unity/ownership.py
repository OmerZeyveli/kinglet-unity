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

Three traps this module exists to avoid, all observed or reproduced live:

1. A loose substring/grep match on a process's command line finds ITSELF
   (this controller's own shell command line can contain the text
   "Editor/Unity" merely by naming it), or finds an unrelated Unity-shipped
   helper whose path merely CONTAINS "Unity" -- `UnityShaderCompiler` and
   `unityhub` are both real, non-Editor processes. This module only ever
   treats a process as a candidate Editor when its argv[0] BASENAME is
   EXACTLY "Unity" or "Unity.exe".

2. `ps -axo command=` is a LOSSY, space-joined rendering of argv: it cannot
   be unambiguously re-split, and no tokenize-then-rejoin scheme recovers
   it in general, because a directory named "Kinglet - Copy", "proj -- old",
   or containing a literal double space/tab/newline is indistinguishable
   from several arguments once ps has joined them with single spaces.
   Round 1 and round 2 of this module each tried a narrower heuristic here
   (shlex, then "stop at the first flag-shaped token") and each was
   demonstrated to produce a false SAFE for a real launch a live Editor
   held open. This module now (a) reads the OS's own EXACT, unambiguous
   argv wherever the platform provides one (Linux's /proc/<pid>/cmdline is
   NUL-delimited -- there is nothing to resolve), and (b) for the
   remaining lossy-string case (macOS ps, an unquoted Windows line), SLICES
   the original string at every plausible flag boundary instead of
   tokenizing-and-rejoining, so a candidate can never lose whitespace it
   never should have collapsed in the first place, and generates every
   candidate a real Unity invocation could produce rather than only the
   first. Any exact match against the caller's OWN known target project is
   accepted as owned; a caller can never falsely conclude "not owned" by
   this method, because the true path -- if it IS the target -- always
   survives as one of the generated candidates (see
   _project_path_candidates_from_raw's docstring for why).

3. Path equality must be whole-resolved-path equality, never a
   prefix/substring comparison -- `/x/proj` and `/x/proj2` (no separator
   between them) canonicalize to different paths and must never match.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path, PureWindowsPath
from typing import Callable, Sequence, Union

from ..model import EvidenceError

# A process-table entry's command is either:
#   - an EXACT argv tuple (e.g. from /proc/<pid>/cmdline -- no ambiguity), or
#   - a LOSSY, space-joined command-line string (ps, or an unquoted Windows
#     line) that must be parsed with _project_path_candidates_from_raw.
ProcessCommand = Union[str, "tuple[str, ...]"]
ProcessEntry = tuple[int, ProcessCommand]

_PROJECT_PATH_FLAG_RE = re.compile(r'(?:(?<=\s)|^)-projectPath(?=\s|$)')
# A plausible start of the NEXT real flag: a dash immediately followed by a
# letter, with nothing but whitespace (or the start of string) before it.
# "- Copy" (dash, space, letter) does NOT match -- only an unspaced
# "-Word" does, exactly the shape every real Unity flag has
# (-logFile, -batchmode, -quit, -projectPath itself, ...).
_FLAG_BOUNDARY_RE = re.compile(r'(?:(?<=\s)|^)-[A-Za-z][\w-]*')


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

def _extract_argv0(command: str, *, windows: bool) -> str | None:
    """Return the first whitespace-delimited token of a lossy command-line string.

    windows=True additionally recognizes an explicitly quoted argv0
    (`"C:\\Program Files\\Unity\\Editor\\Unity.exe" ...`), since WMI quotes
    any argument containing a space and a naive whitespace split would
    otherwise stop at "C:\\Program".
    """
    stripped = command.lstrip()
    if not stripped:
        return None
    if windows and stripped[0] == '"':
        end = stripped.find('"', 1)
        if end != -1:
            return stripped[1:end]
    return stripped.split(None, 1)[0]


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


def _extract_project_path_from_argv(argv: Sequence[str]) -> str | None:
    """Return the EXACT value following `-projectPath` in a real argv tuple.

    No ambiguity to resolve here at all: each element of argv is already
    exactly one shell argument (this is what /proc/<pid>/cmdline gives us),
    so the value immediately after the flag IS the path, spaces, tabs,
    newlines and all -- there is nothing to rejoin or guess.
    """
    for index, token in enumerate(argv):
        if token == "-projectPath" and index + 1 < len(argv):
            return argv[index + 1]
    return None


def _project_path_candidates_from_raw(command: str, *, windows: bool) -> list[str]:
    """Every plausible -projectPath VALUE a lossy, space-joined command line
    could encode, for a caller to test against a KNOWN target path.

    Why not tokenize-and-rejoin (round 1 and round 2's approach, both
    demonstrated unsafe): a space-joined line cannot be unambiguously
    re-split, and str.split()-based tokenization additionally COLLAPSES
    whitespace runs, so it can never reconstruct a path containing a
    double space, a tab, or an embedded newline even in principle. This
    function instead SLICES the ORIGINAL string, preserving every
    character exactly, and returns one candidate per place a real Unity
    flag plausibly starts (dash immediately followed by a letter, e.g.
    -logFile/-batchmode/-quit -- see _FLAG_BOUNDARY_RE), plus the
    untruncated remainder for when -projectPath is the last argument. A
    directory literally named "Kinglet - Copy" (Windows' own name for a
    duplicated folder), "proj -- old", "My -Project", or one containing
    "-logFile" as a substring therefore all recover correctly instead of
    being truncated at the first dash, because ONE of the generated
    candidates always coincides with the true path whenever the real next
    argument is a genuine Unity flag (the overwhelmingly common case) or
    -projectPath is the last argument.

    Every candidate is checked by the caller with exact canonicalized-path
    equality against ONE already-known target -- generating extra,
    non-matching candidates can therefore only ever produce a correct
    match a narrower heuristic would have missed; it can never fabricate a
    false match against an unrelated project, because an unrelated
    project's canonical path is simply a different string. That asymmetry
    is the point: false negatives here would be a safety hole (a false
    SAFE), so this function is deliberately generous rather than clever.
    """
    match = _PROJECT_PATH_FLAG_RE.search(command)
    if match is None:
        return []
    rest = command[match.end():]
    if not rest or rest[0] not in (" ", "\t"):
        return []
    rest = rest[1:]
    if not rest:
        return []

    if windows and rest[0] == '"':
        end = rest.find('"', 1)
        if end != -1:
            return [rest[1:end]]
        # Unterminated quote -- fall through to the unquoted heuristic below.

    candidates: list[str] = []
    for flag_match in _FLAG_BOUNDARY_RE.finditer(rest):
        candidate = rest[: flag_match.start()]
        if candidate.endswith((" ", "\t")):
            candidate = candidate[:-1]
        if candidate and candidate not in candidates:
            candidates.append(candidate)
    if rest not in candidates:
        candidates.append(rest)
    return candidates


def _candidate_paths_for_command(
    command: ProcessCommand, *, windows: bool
) -> tuple[str | None, list[str]]:
    """Return (argv0, [candidate -projectPath values]) for one process entry.

    Dispatches on whether `command` is an exact argv tuple (single
    unambiguous candidate, or none) or a lossy command-line string
    (possibly several candidates -- see _project_path_candidates_from_raw).
    """
    if isinstance(command, (tuple, list)):
        argv0 = command[0] if command else None
        raw_path = _extract_project_path_from_argv(command)
        return argv0, ([raw_path] if raw_path is not None else [])
    argv0 = _extract_argv0(command, windows=windows)
    return argv0, _project_path_candidates_from_raw(command, windows=windows)


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
    _is_unity_editor_argv0). Its -projectPath candidates (exact, from an
    argv tuple, or several, from a lossy command-line string -- see
    _candidate_paths_for_command) are each canonicalized and compared to
    the canonicalized requested project; ANY exact match is authoritative.
    Path equality is always whole-resolved-path equality, never a
    prefix/substring comparison.
    """
    canonical_project = _canonical(project)
    for pid, command in process_table:
        argv0, candidates = _candidate_paths_for_command(command, windows=windows)
        if argv0 is None or not _is_unity_editor_argv0(argv0, windows=windows):
            continue
        exact_argv = isinstance(command, (tuple, list))
        for candidate in candidates:
            if _canonical(candidate) == canonical_project:
                return ProjectOwner(
                    pid=pid,
                    project_path=str(canonical_project),
                    source="process-exact-argv" if exact_argv else "process",
                    confirmed=True,
                    detail=(
                        f"pid {pid} -projectPath resolves to {candidate!r}"
                        + (" (exact argv)" if exact_argv else " (from command line)")
                    ),
                )
    return None


def _pid_is_live_unity_process(
    process_table: Sequence[ProcessEntry], pid: int, *, windows: bool = False
) -> bool:
    for entry_pid, command in process_table:
        if entry_pid != pid:
            continue
        argv0, _candidates = _candidate_paths_for_command(command, windows=windows)
        if argv0 and _is_unity_editor_argv0(argv0, windows=windows):
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

def _read_argv_via_proc(pid: int) -> tuple[str, ...] | None:
    """Exact argv for `pid` via /proc/<pid>/cmdline (Linux only).

    NUL-delimited -- each element is exactly one argv entry, so there is no
    ambiguity to resolve at all, unlike a `ps`-rendered command-line
    string. Returns None if unavailable (process already gone, no /proc,
    permission denied reading another user's process) so the caller can
    fall back to `ps`.
    """
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return None
    if not raw:
        return None
    parts = raw.split(b"\x00")
    if parts and parts[-1] == b"":
        parts = parts[:-1]
    if not parts:
        return None
    try:
        return tuple(part.decode("utf-8") for part in parts)
    except UnicodeDecodeError:
        return tuple(part.decode("utf-8", errors="surrogateescape") for part in parts)


def _linux_proc_process_table() -> tuple[ProcessEntry, ...] | None:
    """Exact argv for every readable PID via /proc -- the authoritative Linux source.

    Returns None (never an empty tuple) when /proc itself cannot be
    listed, so the caller can distinguish "no processes" from "couldn't
    look" and fall back to `ps` instead of silently reporting nobody
    running anything.
    """
    try:
        names = os.listdir("/proc")
    except OSError:
        return None
    entries: list[ProcessEntry] = []
    for name in names:
        if not name.isdigit():
            continue
        argv = _read_argv_via_proc(int(name))
        if argv:
            entries.append((int(name), argv))
    return tuple(entries)


def _ps_process_table() -> tuple[ProcessEntry, ...]:
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


def _posix_process_table() -> tuple[ProcessEntry, ...]:
    """Linux: exact argv via /proc when available (authoritative); else `ps` (lossy fallback)."""
    if sys.platform.startswith("linux") and Path("/proc").is_dir():
        proc_table = _linux_proc_process_table()
        if proc_table is not None:
            return proc_table
    return _ps_process_table()


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
    tests on every host, not merely reviewed as source text. Splits on a
    literal tab, never generic whitespace: Win32_Process.CommandLine values
    can legitimately contain spaces (quoted paths, arguments), and a
    generic-whitespace split risks misreading the pid/command boundary if
    any whitespace precedes the real tab separator.
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

    Real OS process listing is the default -- exact argv via /proc on
    Linux, `ps` elsewhere on POSIX, Win32_Process.CommandLine on Windows.
    process_table_provider is the injectable seam tests use to drive this
    from a fabricated table on any host, matching every other
    platform-dependent gate in this plan; entries may be either an exact
    argv tuple or a lossy command-line string (see ProcessCommand).
    `windows` selects the lossy-string parsing dialect and defaults to the
    real host platform; tests override it explicitly rather than relying
    on sys.platform.

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
