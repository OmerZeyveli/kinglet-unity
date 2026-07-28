"""editor.py -- Exact Unity Editor resolution and version verification.

This module answers exactly one question honestly: "did the Editor binary we
were handed report the EXACT version this project declares?" It never
answers a softer question. In particular:

* read_project_version() never reads m_EditorVersionWithRevision -- that
  field appends a parenthesised changeset hash and is not a bare version
  string a caller can compare against `<editor> -version` stdout.
* verify_editor() performs exact string equality against the required
  version. It never selects the "closest" installed Editor, never falls
  back to a different one, and never writes to the project's
  ProjectSettings/ProjectVersion.txt to make a mismatch disappear. A caller
  may use native helper scripts (Unity Hub install-root enumeration) to
  PROPOSE a matching Editor path for a required version, but that proposal
  carries no authority on its own -- only this function's exact stdout
  check does. This is Task 3's half of "refuse substitution and silent
  project upgrade" from the plan's global constraints; ownership.py is the
  other half.
"""
from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from ..model import EvidenceError
from .model import UNITY_VERSION_RE

# IMPORTED, not respelled. This module and receipt.py judge the same version
# string from opposite ends (may this Editor run / may this receipt publish),
# and the two literals had no test asserting they agreed. `model` is the frozen
# shape module both already depend on, so this adds no new coupling.
_UNITY_VERSION_RE = UNITY_VERSION_RE

_EDITOR_VERSION_LINE_RE = re.compile(r"^m_EditorVersion:\s*(\S+)\s*$")


@dataclass(frozen=True)
class EditorIdentity:
    """The exact, verified identity of an Editor binary that passed verify_editor()."""

    editor_path: str
    version: str


def read_project_version(project: Path) -> str:
    """Read the exact Editor version a project declares.

    Parses ProjectSettings/ProjectVersion.txt and returns m_EditorVersion --
    never m_EditorVersionWithRevision. Unity always writes both lines
    (m_EditorVersion first); a fixture missing the second line has hidden
    real bugs in this repo before (see the ProjectVersion.txt note in
    CLAUDE.md), which is why the pinned fixture at
    spikes/platform/unity/fixture/ProjectSettings/ProjectVersion.txt carries
    both lines and this reader only ever consumes the first.
    """
    version_path = project / "ProjectSettings" / "ProjectVersion.txt"
    try:
        text = version_path.read_text(encoding="utf-8")
    except OSError as error:
        raise EvidenceError("E_FIELD", f"cannot read {version_path}: {error}") from error

    for line in text.splitlines():
        match = _EDITOR_VERSION_LINE_RE.match(line)
        if match:
            version = match.group(1)
            if not _UNITY_VERSION_RE.fullmatch(version):
                raise EvidenceError(
                    "E_FIELD",
                    f"{version_path} m_EditorVersion is not a well-formed "
                    f"Unity version string: {version!r}",
                )
            return version

    raise EvidenceError("E_FIELD", f"{version_path} has no m_EditorVersion line")


def _default_run_version_flag(editor: Path) -> str:
    """Real `<editor> -version` invocation -- the default seam for verify_editor()."""
    try:
        result = subprocess.run(
            [str(editor), "-version"],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
    except OSError as error:
        raise EvidenceError("E_FIELD", f"cannot execute editor {editor}: {error}") from error
    return result.stdout


def verify_editor(
    editor: Path,
    required_version: str,
    *,
    run_version_flag: Callable[[Path], str] = _default_run_version_flag,
) -> EditorIdentity:
    """Verify an explicit Editor binary reports EXACTLY required_version.

    This is the sole authority for "which Editor may launch this project" --
    see the module docstring for what it refuses to do. run_version_flag is
    an injectable seam (defaults to a real subprocess call) so tests can
    drive this with a fake editor and no real Unity install, and so the
    same comparison logic runs unmodified regardless of how a given host
    invokes the binary.

    Raises E_UNITY_VERSION when the reported version does not exactly equal
    required_version. Never raises for a "close" mismatch differently than
    a wildly different one -- exact equality is the only rule.
    """
    stdout = run_version_flag(editor)
    stripped = stdout.strip()
    reported = stripped.splitlines()[0].split()[0] if stripped else ""

    if reported != required_version:
        raise EvidenceError(
            "E_UNITY_VERSION",
            f"editor {editor} reports version {reported!r}, required exactly "
            f"{required_version!r} -- refusing substitution",
        )

    return EditorIdentity(editor_path=str(editor), version=reported)


def verify_project_editor(
    project: Path,
    editor: Path,
    *,
    run_version_flag: Callable[[Path], str] = _default_run_version_flag,
) -> EditorIdentity:
    """Bind required_version to what the PROJECT declares, then verify the Editor against it.

    read_project_version() and verify_editor() are each correct in
    isolation, but nothing forced a caller to actually chain them --
    without this function, "refuse substitution" was a convention for a
    future route runner to remember, not a guarantee this module enforces.
    This is the one path that reads a project's own pinned version and
    requires the handed-in Editor to match it exactly; see verify_editor()
    for what "exactly" means (E_UNITY_VERSION on any mismatch, no
    closest-match fallback).
    """
    required_version = read_project_version(project)
    return verify_editor(editor, required_version, run_version_flag=run_version_flag)
