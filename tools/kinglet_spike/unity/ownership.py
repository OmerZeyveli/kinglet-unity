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
   (shlex, then "stop at the first flag-shaped token", then "slice at
   every plausible flag boundary") and each was demonstrated to produce a
   false SAFE for a real launch a live Editor held open, because a
   two-outcome design (owned / not-owned) has no way to say "I could not
   tell" -- every case the slicer couldn't resolve fell through to
   not-owned by construction, whatever the slicer's cleverness. This
   module now (a) reads the OS's own EXACT, unambiguous argv wherever the
   platform provides one -- Linux's /proc/<pid>/cmdline and macOS's sysctl
   KERN_PROCARGS2 are both NUL-delimited, so there is nothing to resolve,
   and a per-pid read failure is not treated as "not Unity": see
   _linux_proc_process_table and _build_macos_process_table -- (b) uses the
   lossy `ps` string only as a last resort, where it fails CLOSED for
   Unity-shaped entries (see _ps_process_table: a newline in the path whose
   TAIL parses as another `<pid> <command>` line leaves NO unparseable line
   to detect, so a ps rendering can never establish a Unity process's path
   beyond doubt), and (c) for the remaining lossy-string case (an unquoted
   Windows line), has a THIRD outcome. find_owning_process() slices the original string at
   every plausible flag boundary (see _project_path_candidates_from_raw)
   and:
     - any candidate that exactly matches the caller's known target is
       accepted as owned, immediately;
     - otherwise, if exactly one candidate resolves to a directory that
       actually exists on disk, that is treated as the process's true
       path and -- since it didn't match the target above -- this process
       is not the owner;
     - otherwise (zero candidates exist on disk, so the true path could
       not be recovered at all; or more than one distinct candidate
       exists, so which one is true can't be told) this process's
       ownership of the target is UNRESOLVABLE, and the caller returns an
       unconfirmed ProjectOwner (source="process-ambiguous") rather than
       None -- exactly the outcome a bare flag-not-found case (no
       following real flag, a bare "-", "--", a slash-style flag, or a
       ps-truncated line spanning an embedded newline) used to fall
       through as "safe". This module never fabricates a false match
       against an unrelated project (a non-matching candidate is simply a
       different string), and as of this round it also never silently
       concludes "not owned" when it genuinely could not tell.

3. Path equality must be whole-resolved-path equality, never a
   prefix/substring comparison -- `/x/proj` and `/x/proj2` (no separator
   between them) canonicalize to different paths and must never match.

WHAT HAS AND HAS NOT BEEN RUN ON A REAL HOST
--------------------------------------------
Stated here, in the module, rather than only in a planning note: a caveat
that lives somewhere a reader of this file will not look is a caveat that
does not exist.

- Linux /proc: exercised live on the development host.
- macOS `sysctl` KERN_PROCARGS2 (_read_procargs2_bytes): the ctypes call
  itself has NEVER been executed on macOS. Its buffer DECODER
  (_parse_procargs2) and its table ASSEMBLY (_build_macos_process_table)
  are pure and fully unit-tested from any host, but the mib layout, the
  KERN_ARGMAX sizing and the sysctl(3) return conventions are reasoned
  from the xnu sources, not measured. A macOS pass must confirm that
  _read_argv_via_sysctl returns non-None for the caller's own process
  before any conclusion drawn on macOS is trusted.
- Windows Win32_Process via PowerShell: the invocation has never been
  executed either; _parse_windows_process_table is pure and tested.
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

@dataclass(frozen=True)
class _TruncatedCommand:
    """Sentinel command value: a process-table entry known to be Unity-shaped
    (argv0 established some other way) whose -projectPath value is NOT
    trustworthy -- either a `ps` line-oriented capture lost the tail of
    this argv to an embedded newline (see _parse_posix_process_table), or
    /proc/<pid>/cmdline could not be read for a live pid and only its
    coarser /proc/<pid>/comm was available (see _linux_proc_process_table).
    Always resolves as ambiguous in find_owning_process -- never as "no
    -projectPath" (which would silently drop it) and never with a guessed
    path (which could silently mismatch).
    """

    argv0: str


# A process-table entry's command is one of:
#   - an EXACT argv tuple (e.g. from /proc/<pid>/cmdline -- no ambiguity),
#   - a LOSSY, space-joined command-line string (ps, or an unquoted Windows
#     line) that must be parsed with _project_path_candidates_from_raw, or
#   - a _TruncatedCommand (Unity-shaped, but -projectPath unrecoverable).
ProcessCommand = Union[str, "tuple[str, ...]", _TruncatedCommand]
ProcessEntry = tuple[int, ProcessCommand]

# ONE argument-separator alphabet, shared by the flag REGEXES and the value
# EXTRACTOR below.
#
# They used to disagree: the regexes accepted any `\s` while the extractor
# accepted only space and tab. `-projectPath\n/path` therefore MATCHED the
# flag regex and was then rejected by `rest[0] not in (" ", "\t")`, and the
# function returned `[]` -- which its caller reads as "no -projectPath here",
# i.e. a POSITIVE ruling-out, for a command line that plainly carries one.
# Same shape as the credential-rule defect fixed in 6257de1: two guards, two
# alphabets, and their disagreement resolving toward SAFE.
#
# The alphabet is spelled once, as an explicit character class rather than
# `\s`, because `\s` on a str pattern also matches Unicode separators that
# `str.__contains__` over a literal would not -- which is how two spellings of
# "whitespace" drift apart in the first place. test_unity_ownership.py asserts
# character-by-character that the regex and the extractor agree.
_SEPARATOR_CHARS: str = " \t\n\r\v\f"
_SEPARATOR_CLASS: str = "[ \\t\\n\\r\\v\\f]"

_PROJECT_PATH_FLAG_RE = re.compile(
    r'(?:(?<=' + _SEPARATOR_CLASS + r')|^)-projectPath(?=' + _SEPARATOR_CLASS + r'|$)'
)
# A plausible start of the NEXT real flag: a dash immediately followed by a
# letter, with nothing but a separator (or the start of string) before it.
# "- Copy" (dash, space, letter) does NOT match -- only an unspaced
# "-Word" does, exactly the shape every real Unity flag has
# (-logFile, -batchmode, -quit, -projectPath itself, ...).
_FLAG_BOUNDARY_RE = re.compile(
    r'(?:(?<=' + _SEPARATOR_CLASS + r')|^)-[A-Za-z][\w-]*'
)


@dataclass(frozen=True)
class ProjectOwner:
    """A detected owner of a Unity project's physical path.

    confirmed=True: a live process's -projectPath (or, failing that, an
    EditorInstance.json pid) was matched directly against a live Unity
    Editor process. Authoritative -- assert_headless_safe raises
    E_UNITY_OWNED.

    confirmed=False: either Temp/UnityLockfile or Library/EditorInstance.json
    is present but no live process corroborates it (source="lockfile") --
    a stale lock, proving a project WAS opened but not that anything owns
    it now -- or a live Unity-shaped process carries a -projectPath value
    this module could not unambiguously resolve (source="process-ambiguous",
    see find_owning_process). Neither is "not owned": assert_headless_safe
    still refuses (E_UNITY_OWNER_UNKNOWN) for both, because "probably safe"
    is not "known safe".

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
    # Same alphabet the flag regex's lookahead just used. Anything narrower
    # here turns a matched flag into `[]`, which reads as "ruled out".
    if not rest or rest[0] not in _SEPARATOR_CHARS:
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
        if candidate.endswith(tuple(_SEPARATOR_CHARS)):
            candidate = candidate[:-1]
        if candidate and candidate not in candidates:
            candidates.append(candidate)
    if rest not in candidates:
        candidates.append(rest)
    return candidates


def _candidate_paths_for_command(
    command: ProcessCommand, *, windows: bool
) -> tuple[str | None, list[str] | None]:
    """Return (argv0, candidates) for one process entry.

    candidates is one of:
      - None            -- this entry is KNOWN Unity-shaped but its
                            -projectPath is unrecoverable (_TruncatedCommand);
                            the caller must treat this as unresolvable, never
                            as "no -projectPath present".
      - []               -- no -projectPath flag was found at all; this
                            process is not a candidate owner of anything.
      - [str, ...]        -- one (exact argv) or several (lossy command-line
                            string, see _project_path_candidates_from_raw)
                            plausible -projectPath values to check.
    """
    if isinstance(command, _TruncatedCommand):
        return (command.argv0 or None), None
    if isinstance(command, (tuple, list)):
        argv0 = command[0] if command else None
        raw_path = _extract_project_path_from_argv(command)
        return argv0, ([raw_path] if raw_path is not None else [])
    argv0 = _extract_argv0(command, windows=windows)
    return argv0, _project_path_candidates_from_raw(command, windows=windows)


def _canonical(path: str | Path) -> Path:
    """Resolve symlinks and relative components so aliasing can't hide or fake a match."""
    return Path(path).expanduser().resolve()


def _canonical_or_none(path: str | Path) -> Path | None:
    """_canonical() that reports "could not determine" instead of raising.

    Path.resolve() is NOT total: on Python 3.13 a component under an
    unreadable parent directory raises PermissionError, while on <=3.12 the
    same input silently reads as "does not exist". Version-dependent safety
    behaviour is itself a defect -- a raw OSError escaping this module
    bypasses its EvidenceError contract entirely, and "does not exist" is a
    RESOLVED answer this module is not entitled to. Both must instead
    become ambiguity, so this returns None for "unknown" and the caller
    refuses.
    """
    try:
        return _canonical(path)
    except OSError:
        return None


def _is_dir_or_unknown(path: Path) -> bool | None:
    """Path.is_dir() with a third answer: None means "could not determine".

    Same reason as _canonical_or_none: is_dir() raises PermissionError on
    3.13 for a path under an unreadable parent and returns False on <=3.12.
    An OSError here means we could not establish existence, which is
    ambiguity, never "absent".
    """
    try:
        return path.is_dir()
    except OSError:
        return None


def find_owning_process(
    process_table: Sequence[ProcessEntry],
    project: Path,
    *,
    windows: bool = False,
) -> ProjectOwner | None:
    """Pure: scan a process table for a live Unity Editor owning `project`.

    A candidate must be a genuine Unity Editor binary (see
    _is_unity_editor_argv0). What happens next depends on how certain its
    -projectPath value is (see _candidate_paths_for_command):

    - _TruncatedCommand (candidates is None): known Unity-shaped, value
      unrecoverable -- unconditionally ambiguous.
    - no -projectPath at all (candidates == []): not a candidate owner,
      skip.
    - exact argv (from /proc): the single candidate is either the target
      (owned) or it isn't (definitively not this process -- no ambiguity
      is possible when the OS gave us the literal argument).
    - a lossy command-line string: several candidates. Any EXACT match
      against the known target wins immediately (owned). Failing that,
      this module does NOT conclude "not owned" merely because no
      candidate happened to match -- a candidate can be truncated by
      construction (see _project_path_candidates_from_raw). It instead
      asks which candidates resolve to a directory that actually exists:
      exactly one existing candidate is treated as this process's true,
      established path (and since it didn't match the target, this
      process is not the owner); zero or more-than-one existing
      candidates means the true path could not be pinned down, which is
      UNRESOLVABLE, not "safe".

    Path equality is always whole-resolved-path equality, never a
    prefix/substring comparison. Returns a confirmed ProjectOwner
    (source="process"/"process-exact-argv") for an outright match, an
    unconfirmed one (source="process-ambiguous") if any process could not
    be ruled out, or None only when every Unity-shaped process in the
    table was positively ruled out (or there were none).
    """
    canonical_project = _canonical_or_none(project)
    if canonical_project is None:
        raise EvidenceError(
            "E_UNITY_OWNER_UNKNOWN",
            f"cannot canonicalize project path {str(project)!r} to check Unity "
            "ownership; refusing headless launch until inspected",
        )
    ambiguous_owner: ProjectOwner | None = None

    for pid, command in process_table:
        argv0, candidates = _candidate_paths_for_command(command, windows=windows)
        if argv0 is None or not _is_unity_editor_argv0(argv0, windows=windows):
            continue

        if candidates is None:
            # Known Unity-shaped, -projectPath unrecoverable (truncated
            # ps capture, or /proc/<pid>/cmdline unreadable) -- cannot be
            # ruled out as the owner.
            if ambiguous_owner is None:
                ambiguous_owner = ProjectOwner(
                    pid=pid,
                    project_path=str(canonical_project),
                    source="process-ambiguous",
                    confirmed=False,
                    detail=(
                        f"pid {pid} is a live Unity-shaped process whose "
                        "-projectPath could not be read at all; refusing "
                        "rather than guessing safe"
                    ),
                )
            continue

        if not candidates:
            continue  # no -projectPath flag -- not a candidate owner

        exact_argv = isinstance(command, (tuple, list))

        # A candidate we cannot even canonicalize is not "different from the
        # target" -- it is unknown, and unknown must not silently read as a
        # non-match (see _canonical_or_none).
        undetermined = False
        matched = None
        for candidate in candidates:
            resolved = _canonical_or_none(candidate)
            if resolved is None:
                undetermined = True
                continue
            if resolved == canonical_project:
                matched = candidate
                break
        if matched is not None:
            return ProjectOwner(
                pid=pid,
                project_path=str(canonical_project),
                source="process-exact-argv" if exact_argv else "process",
                confirmed=True,
                detail=(
                    f"pid {pid} -projectPath resolves to {matched!r}"
                    + (" (exact argv)" if exact_argv else " (from command line)")
                ),
            )

        if exact_argv and not undetermined:
            # The OS gave us the literal argument; a non-match here is
            # definitive, not ambiguous.
            continue

        # Lossy string, no direct match. Disambiguate via filesystem
        # existence: which candidate(s), if any, are real directories?
        existing: list[Path] = []
        for candidate in candidates:
            resolved = _canonical_or_none(candidate)
            if resolved is None:
                undetermined = True
                continue
            if resolved in existing:
                continue
            is_dir = _is_dir_or_unknown(resolved)
            if is_dir is None:
                undetermined = True
            elif is_dir:
                existing.append(resolved)

        if len(existing) == 1 and not undetermined:
            # Exactly one candidate is a real directory, and it already
            # failed the exact-match check above -- this process's true
            # path is established and it is not the target.
            continue

        if ambiguous_owner is None:
            if undetermined:
                reason = (
                    "a candidate path could not be probed at all "
                    "(unreadable parent directory)"
                )
            elif not existing:
                reason = "no candidate resolves to an existing directory"
            else:
                reason = "multiple candidates resolve to different existing directories"
            ambiguous_owner = ProjectOwner(
                pid=pid,
                project_path=str(canonical_project),
                source="process-ambiguous",
                confirmed=False,
                detail=(
                    f"pid {pid} -projectPath could not be unambiguously "
                    f"resolved ({reason}); refusing rather than guessing safe"
                ),
            )

    return ambiguous_owner


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


def _proc_pid_is_alive(pid: int) -> bool:
    # Unknown (an OSError from the probe) counts as alive: the caller uses
    # this only to decide whether an unreadable-cmdline pid is worth
    # keeping as ambiguous, and "might be alive" must not become "gone".
    return _is_dir_or_unknown(Path(f"/proc/{pid}")) is not False


def _read_comm_via_proc(pid: int) -> str | None:
    """/proc/<pid>/comm: just the executable basename, no arguments.

    A much lower bar than cmdline in practice (empty for kernel threads
    but they carry a bracketed name here too, e.g. "[kworker/0:1]" via ps
    -- and this file is unaffected by argv/environ-specific access
    restrictions some hardened configurations apply). Used only as a
    per-pid fallback when cmdline itself could not be read.
    """
    try:
        return Path(f"/proc/{pid}/comm").read_text(
            encoding="utf-8", errors="surrogateescape"
        ).strip()
    except OSError:
        return None


def _linux_proc_process_table() -> tuple[ProcessEntry, ...] | None:
    """Exact argv for every readable PID via /proc -- the authoritative Linux source.

    Returns None (never an empty tuple) when /proc itself cannot be
    listed, so the caller can distinguish "no processes" from "couldn't
    look" and fall back to `ps` instead of silently reporting nobody
    running anything.

    A per-pid cmdline read can fail for a LIVE process (hidepid, a
    pid-namespace boundary, a permission denial, a decode fault) without
    the whole /proc listing failing -- round 2 dropped that pid from the
    table silently, which could make a live Editor vanish and read as
    SAFE. This function never does that: when cmdline is unreadable for a
    pid that is still alive, it falls back to /proc/<pid>/comm (a much
    lower access bar). If comm confirms the process is Unity-shaped, the
    pid is kept as a _TruncatedCommand -- unconditionally ambiguous, since
    we know it might be the Editor but cannot read its -projectPath. If
    comm is also unreadable or doesn't look like Unity, the pid is
    omitted: there would be nothing actionable to refuse on, and treating
    every unreadable non-Unity process (there are many on any real
    multi-user or containerized host) as ambiguous would make headless
    launches permanently impossible rather than merely cautious.
    """
    try:
        names = os.listdir("/proc")
    except OSError:
        return None
    entries: list[ProcessEntry] = []
    for name in names:
        if not name.isdigit():
            continue
        pid = int(name)
        argv = _read_argv_via_proc(pid)
        if argv:
            entries.append((pid, argv))
            continue
        if not _proc_pid_is_alive(pid):
            continue  # gone by the time we looked -- not a live owner
        comm = _read_comm_via_proc(pid)
        if comm and _is_unity_editor_argv0(comm, windows=False):
            entries.append((pid, _TruncatedCommand(argv0=comm)))
    return tuple(entries)


# --- macOS: exact argv via sysctl KERN_PROCARGS2 -------------------------
#
# The macOS analogue of Linux's /proc/<pid>/cmdline. `ps -axo command=` is a
# space-joined rendering of argv whose LINE STRUCTURE cannot be trusted
# either: a project directory whose name contains a literal newline makes ps
# print that newline verbatim, and if the text after it happens to parse as
# `<pid> <command>` the split is completely invisible to a line-oriented
# reader -- the real Editor entry is left looking like a clean, complete
# command line that ends at the truncated prefix. No amount of repairing the
# string after the fact fixes that (each such repair closed one instance and
# left the class), so this module stops deriving macOS argv from ps at all
# and asks the kernel for the NUL-separated argv it actually stored.
# KERN_PROCARGS2 is readable for same-user processes, which is exactly the
# threat model: the user's own GUI Editor.
_CTL_KERN = 1
_KERN_ARGMAX = 8
_KERN_PROCARGS2 = 49


def _parse_procargs2(raw: bytes) -> tuple[str, ...] | None:
    """Pure: decode a KERN_PROCARGS2 buffer into an EXACT argv tuple.

    Buffer layout (xnu, unchanged since 10.4): a native-endian 32-bit argc,
    then the NUL-terminated executable path, then NUL alignment padding,
    then exactly argc NUL-terminated argv strings, then the environment.
    Each argv element is delimited by the kernel itself, so a path
    containing spaces, tabs or newlines survives verbatim -- there is
    nothing to re-split and nothing to guess.

    Returns None for any buffer that does not yield exactly argc elements.
    None means "no exact argv available", which the caller turns into
    ambiguity, never into "not Unity".

    Extracted from the ctypes call specifically so it is exercised by tests
    on this Linux host with representative NUL-separated bytes, rather than
    only reviewed as source text.
    """
    if len(raw) < 4:
        return None
    argc = int.from_bytes(raw[:4], sys.byteorder, signed=True)
    if argc <= 0:
        return None
    rest = raw[4:]
    exec_end = rest.find(b"\x00")
    if exec_end == -1:
        return None
    rest = rest[exec_end + 1:]
    rest = rest.lstrip(b"\x00")  # alignment padding before argv[0]
    parts: list[bytes] = []
    for _ in range(argc):
        end = rest.find(b"\x00")
        if end == -1:
            return None  # truncated buffer -- refuse rather than guess
        parts.append(rest[:end])
        rest = rest[end + 1:]
    return tuple(part.decode("utf-8", errors="surrogateescape") for part in parts)


def _read_procargs2_bytes(pid: int) -> bytes | None:
    """Raw KERN_PROCARGS2 buffer for pid via libc sysctl(3). Darwin only."""
    if sys.platform != "darwin":
        return None
    try:
        import ctypes

        libc = ctypes.CDLL(None, use_errno=True)
        libc.sysctl.restype = ctypes.c_int
        libc.sysctl.argtypes = [
            ctypes.POINTER(ctypes.c_int),
            ctypes.c_uint,
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_size_t),
            ctypes.c_void_p,
            ctypes.c_size_t,
        ]

        argmax = ctypes.c_int(0)
        argmax_size = ctypes.c_size_t(ctypes.sizeof(argmax))
        mib2 = (ctypes.c_int * 2)(_CTL_KERN, _KERN_ARGMAX)
        if libc.sysctl(
            mib2, 2, ctypes.byref(argmax), ctypes.byref(argmax_size), None, 0
        ) != 0 or argmax.value <= 0:
            return None

        buffer = ctypes.create_string_buffer(argmax.value)
        size = ctypes.c_size_t(argmax.value)
        mib3 = (ctypes.c_int * 3)(_CTL_KERN, _KERN_PROCARGS2, pid)
        if libc.sysctl(mib3, 3, buffer, ctypes.byref(size), None, 0) != 0:
            return None  # process gone, or another user's (EINVAL/EPERM)
        return buffer.raw[: size.value]
    except (OSError, AttributeError, ValueError, MemoryError, ctypes.ArgumentError):
        # ctypes.ArgumentError derives from Exception, NOT from any of the
        # others: a pid that does not fit c_int (a value from a hostile or
        # simply unexpected `ps`) raises it out of the (c_int * 3) build and
        # escaped this handler entirely, breaking the module's "every route
        # yields E_UNITY_OWNER_UNKNOWN, never a bare traceback" guarantee on
        # macOS. Returning None here is the same answer as every other
        # unreadable-argv case: no exact argv, so the caller decides ambiguity.
        return None


def _read_argv_via_sysctl(pid: int) -> tuple[str, ...] | None:
    """Exact argv for pid on macOS, or None when unavailable."""
    raw = _read_procargs2_bytes(pid)
    if raw is None:
        return None
    return _parse_procargs2(raw)


def _build_macos_process_table(
    pids: Sequence[int],
    *,
    argv_reader: Callable[[int], "tuple[str, ...] | None"],
    comm_reader: Callable[[int], "str | None"],
) -> tuple[ProcessEntry, ...]:
    """Pure: assemble a macOS process table from injected per-pid readers.

    Mirrors _linux_proc_process_table's contract exactly. A pid with exact
    argv is recorded as an argv tuple. A pid whose exact argv is
    unavailable is NOT silently dropped when its command name says it is a
    Unity Editor -- it is kept as a _TruncatedCommand, i.e. unconditionally
    ambiguous, because we know it might be the Editor and cannot read its
    -projectPath. A pid whose name is not Unity-shaped is dropped, the same
    documented bound as on Linux: there is nothing actionable to refuse on,
    and holding every unreadable process ambiguous would make headless
    launches permanently impossible rather than merely cautious.
    """
    entries: list[ProcessEntry] = []
    for pid in pids:
        argv = argv_reader(pid)
        if argv:
            entries.append((pid, argv))
            continue
        comm = comm_reader(pid)
        if comm and _is_unity_editor_argv0(comm, windows=False):
            entries.append((pid, _TruncatedCommand(argv0=comm)))
    return tuple(entries)


def _run_ps(args: Sequence[str]) -> str:
    try:
        result = subprocess.run(
            list(args),
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
    return result.stdout


def _parse_pid_list(stdout: str) -> tuple[int, ...]:
    """Pure: parse `ps -axo pid=` output -- one integer per line.

    A pid column is unambiguous no matter what any argument contains, which
    is why enumeration still goes through ps while the command line does
    not. A stray non-numeric line (the tail of some other process's
    newline-containing argument, which this listing does not print at all)
    is simply skipped; a phantom numeric line can only cause an extra
    kernel argv read for a pid, whose real argv is then read exactly.
    """
    pids: list[int] = []
    for line in stdout.splitlines():
        stripped = line.strip()
        if stripped.isdigit():
            pid = int(stripped)
            if pid not in pids:
                pids.append(pid)
    return tuple(pids)


def _parse_comm_map(stdout: str) -> dict[int, str]:
    """Pure: parse `ps -axo pid=,comm=` output into {pid: executable name}.

    Used only to decide Unity-shaped-or-not for a pid whose exact argv
    could not be read -- never to derive a project path.
    """
    mapping: dict[int, str] = {}
    for line in stdout.splitlines():
        parts = line.strip().split(maxsplit=1)
        if len(parts) != 2 or not parts[0].isdigit():
            continue
        mapping[int(parts[0])] = parts[1].strip()
    return mapping


def _macos_process_table() -> tuple[ProcessEntry, ...]:
    """macOS authoritative table: pid enumeration via ps, argv via the kernel."""
    pids = _parse_pid_list(_run_ps(["ps", "-axo", "pid="]))
    # NOT wrapped in `except EvidenceError: comm_map = {}`. That is what it
    # used to be, and an empty map disables the ambiguity fallback for EVERY
    # pid at once: a pid whose exact argv could not be read then has no comm
    # to say "Unity-shaped", so it is dropped, and a live Editor whose argv
    # was unreadable vanishes from the table and reads as SAFE. That converts
    # "I could not look" into "there was nothing to see" -- the inversion this
    # module exists to prevent. `_run_ps` already raises
    # E_UNITY_OWNER_UNKNOWN, which IS the "I could not tell" outcome, so the
    # error is allowed through instead of being downgraded to a fact.
    comm_map = _parse_comm_map(_run_ps(["ps", "-axo", "pid=,comm="]))
    return _build_macos_process_table(
        pids, argv_reader=_read_argv_via_sysctl, comm_reader=comm_map.get
    )


def _ps_process_table() -> tuple[ProcessEntry, ...]:
    """LAST-RESORT lossy fallback: `ps -axo pid=,command=`.

    Reached only when neither exact-argv source is available (/proc on
    Linux, KERN_PROCARGS2 on macOS). Its line structure is untrustworthy in
    a way no post-hoc repair can detect (see the KERN_PROCARGS2 comment
    above), so it fails CLOSED: every Unity-shaped entry it produces is
    marked ambiguous rather than being run through the candidate-slicing
    heuristic, which can be confidently wrong on a newline-split line.
    Non-Unity entries are untouched -- they are only ever used to
    corroborate an EditorInstance.json pid.
    """
    return _parse_posix_process_table(
        _run_ps(["ps", "-axo", "pid=,command="]), fail_closed_unity=True
    )


def _parse_posix_process_line(stripped: str) -> ProcessEntry | None:
    """Parse one already-stripped `<pid> <command>` line, or return None."""
    parts = stripped.split(maxsplit=1)
    if len(parts) != 2:
        return None
    pid_text, command = parts
    try:
        pid = int(pid_text)
    except ValueError:
        return None
    return (pid, command)


def _mark_truncated(command: ProcessCommand, *, windows: bool = False) -> ProcessCommand:
    """Replace a command with a _TruncatedCommand carrying its best-known argv0.

    `windows` is not decorative. The argv0 stored here is what
    _candidate_paths_for_command hands back, and the caller runs it through
    _is_unity_editor_argv0 -- which splits on the WRONG separator if the
    platform is guessed. A Windows command line marked with windows=False
    yields an argv0 of `C:\\Program Files\\...\\Unity.exe` whose POSIX
    basename is the whole string, so a truncated ELEVATED Editor would read
    as not-Unity and be ignored: the same false SAFE, one layer down.
    """
    if isinstance(command, _TruncatedCommand):
        return command
    if isinstance(command, (tuple, list)):
        argv0 = command[0] if command else ""
    else:
        argv0 = _extract_argv0(command, windows=windows) or ""
    return _TruncatedCommand(argv0=argv0)


def _parse_posix_process_table(
    stdout: str, *, fail_closed_unity: bool = False
) -> tuple[ProcessEntry, ...]:
    """Parse `ps -axo pid=,command=` output.

    fail_closed_unity=True (what the real, last-resort _ps_process_table
    passes) additionally marks every Unity-shaped entry ambiguous. That is
    not belt-and-braces: an embedded newline in a project path whose TAIL
    happens to parse as `<pid> <command>` produces no unparseable line at
    all, so the truncation-detection below never fires and the Editor's own
    entry reads as a clean command line ending at the truncated prefix. If
    that prefix exists on disk, the candidate slicer resolves it
    confidently and rules the real owner out -- a false SAFE. When exact
    argv is unavailable, a Unity-shaped process's path is therefore not
    established beyond doubt by construction, and this refuses instead.

    A directory name containing a literal newline makes ps itself print
    that newline verbatim, so the tail of that one process's argv appears
    as a SEPARATE line that will not parse as `<pid> <command>` -- a naive
    line-oriented parser drops it, and the corresponding entry's
    -projectPath value is then silently truncated (the previous round's
    CRITICAL 1 finding: this fed a confidently-wrong path to the slicer
    instead of a signal). Any line that fails to parse is therefore never
    just discarded: if there is a preceding entry to attribute it to, that
    entry is marked _TruncatedCommand (unconditionally ambiguous in
    find_owning_process) rather than left looking like a clean, complete
    command line.
    """
    entries: list[ProcessEntry] = []
    for line in stdout.splitlines():
        stripped = line.strip()
        parsed = _parse_posix_process_line(stripped) if stripped else None
        if parsed is not None:
            entries.append(parsed)
            continue
        if entries:
            prev_pid, prev_command = entries[-1]
            entries[-1] = (prev_pid, _mark_truncated(prev_command))
    if fail_closed_unity:
        entries = [
            (pid, _mark_truncated(command))
            if _entry_is_unity_shaped(command)
            else (pid, command)
            for pid, command in entries
        ]
    return tuple(entries)


def _entry_is_unity_shaped(command: ProcessCommand) -> bool:
    argv0, _candidates = _candidate_paths_for_command(command, windows=False)
    return bool(argv0) and _is_unity_editor_argv0(argv0, windows=False)


def _posix_process_table() -> tuple[ProcessEntry, ...]:
    """Exact argv where the OS provides it; the lossy `ps` string only as a last resort.

    Linux: /proc/<pid>/cmdline (NUL-delimited). macOS: sysctl
    KERN_PROCARGS2 (NUL-delimited). Both are the kernel's own record of
    argv, so a project path containing spaces, tabs or newlines survives
    verbatim. `ps -axo command=` is used only when neither is available,
    and then fails closed for Unity-shaped entries.
    """
    if sys.platform.startswith("linux") and _is_dir_or_unknown(Path("/proc")):
        proc_table = _linux_proc_process_table()
        if proc_table is not None:
            return proc_table
    if sys.platform == "darwin":
        return _macos_process_table()
    return _ps_process_table()


def _windows_process_table() -> tuple[ProcessEntry, ...]:
    """Win32_Process.CommandLine via PowerShell -- the plan's prescribed Windows source."""
    try:
        result = subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-Command",
                # `Name` is fetched as well as `CommandLine`, and that is not
                # cosmetic: CommandLine is $null for any process the caller
                # cannot inspect -- INCLUDING an elevated Editor -- and Name
                # is the only field left that can say "Unity-shaped". Without
                # it the fallback data for _TruncatedCommand does not exist,
                # so the pid could only be dropped, and a live elevated Editor
                # read as SAFE.
                "Get-CimInstance Win32_Process | "
                "ForEach-Object { \"$($_.ProcessId)`t$($_.Name)`t$($_.CommandLine)\" }",
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
    """Pure: parse `<pid><TAB><Name><TAB><CommandLine>` lines -- unit-tested from Linux.

    Extracted from _windows_process_table() specifically so the parsing
    logic (as opposed to the PowerShell invocation itself) is exercised by
    tests on every host, not merely reviewed as source text. Splits on a
    literal tab, never generic whitespace: Win32_Process.CommandLine values
    can legitimately contain spaces (quoted paths, arguments), and a
    generic-whitespace split risks misreading the pid/command boundary if
    any whitespace precedes the real tab separator.

    TWO WAYS THIS USED TO RESOLVE TOWARD SAFE, both closed here:

    1. `if "\\t" not in line: continue`. PowerShell prints a CommandLine
       verbatim, so a project directory whose name contains a NEWLINE makes
       one process emit two lines: the head keeps the pid and a TRUNCATED
       command, and the tail -- carrying no tab -- was silently dropped. The
       Editor's entry was then left looking like a clean, complete command
       line ending at the truncated prefix, which is EXACTLY the shape
       _parse_posix_process_table documents as "the previous round's
       CRITICAL 1 finding" and closes on the POSIX side. It is closed the
       same way here: an unparseable line is never just discarded, it marks
       the preceding entry _TruncatedCommand (unconditionally ambiguous).

    2. `if command:` -- dropping the pid outright when CommandLine is empty.
       Win32_Process.CommandLine is $null for a process the caller cannot
       inspect, and an ELEVATED Editor is precisely such a process. Dropping
       it means no owner is found, `assert_headless_safe` clears, and
       headless Unity launches on a project a live Editor owns. Linux
       (_linux_proc_process_table) and macOS (_build_macos_process_table)
       both KEEP such a pid as a _TruncatedCommand when its coarser name
       says Unity; Windows now does the same, using Win32_Process.Name. A
       pid with no command AND a non-Unity name is dropped, the same
       documented bound as the other two platforms.
    """
    entries: list[ProcessEntry] = []
    for line in stdout.splitlines():
        parts = line.split("\t", 2)
        pid: int | None = None
        if len(parts) == 3:
            try:
                pid = int(parts[0].strip())
            except ValueError:
                pid = None
        if pid is None:
            # Unparseable: either a tail left behind by an embedded newline,
            # or a non-numeric pid column. Never discarded -- see (1) above.
            if entries:
                prev_pid, prev_command = entries[-1]
                entries[-1] = (prev_pid, _mark_truncated(prev_command, windows=True))
            continue
        name = parts[1].strip()
        command = parts[2].strip()
        if command:
            entries.append((pid, command))
        elif name and _is_unity_editor_argv0(name, windows=True):
            entries.append((pid, _TruncatedCommand(argv0=name)))
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
    Linux and sysctl KERN_PROCARGS2 on macOS, the lossy `ps` string only as
    a last resort elsewhere, Win32_Process.CommandLine on Windows.
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
    E_UNITY_OWNER_UNKNOWN for a stale lock, a live Unity-shaped process
    whose -projectPath could not be unambiguously resolved, or a process
    listing this function could not obtain -- any case it cannot clear --
    and returns None only when launch is safe.
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
        f"project {owner.project_path} ownership could not be confirmed clear "
        f"({owner.detail}); refusing headless launch until inspected",
    )
