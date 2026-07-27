"""spike_tree.py — Client-agnostic walk of the committed platform-spike text.

The sanitization sweep used to be a hand-written list of paths: the claude-code
observations document, its published record, its artifacts, and — after a
mutation proved they were unguarded — `claude-code/probe/*.sh` BY NAME. That
shape only ever protects the client someone remembered to add. The next client
(codex, and whatever follows) would ship its probe scripts and manifests into a
tree that no test looks at, exactly as claude-code did.

So the sweep walks directories instead of naming files: every committed text
file under `spikes/platform/clients/` and under the published evidence and
artifact trees is scanned, whichever client it belongs to. A new client
directory is covered the moment it exists.

Vacuity is the failure mode this file has to defend against most: a walk over a
mistyped root scans nothing and reports green. `committed_text_files()` raises
rather than returning an empty tuple, and the tests assert known-covered files
are really in the swept set.
"""
from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

# The roots that must be swept. Each one is asserted non-empty independently:
# a single combined count would let one root silently stop matching.
CLIENTS_ROOT = REPO / "spikes/platform/clients"
EVIDENCE_ROOT = REPO / "docs/research/platform-spike/evidence"
ARTIFACTS_ROOT = REPO / "docs/research/platform-spike/artifacts"
SWEPT_ROOTS = (CLIENTS_ROOT, EVIDENCE_ROOT, ARTIFACTS_ROOT)

# Build output and tool caches are not committed; they are large, binary, and
# full of absolute build paths. Matched on directory NAME at any depth.
SKIP_DIRS = frozenset(
    (".git", "__pycache__", "node_modules", ".venv", "dist", "bin", "obj", "target")
)

# The disposable live-run root must never appear in committed text.
PROBE_ROOT = re.compile(r"/tmp/kinglet-live")

# A credential FILE, however it is spelled. Bare "credentials" in prose ("the
# scripts do not copy credentials") is deliberately not matched — this is about
# naming a file, not about the word.
CREDENTIAL_FILE = re.compile(r"\.credentials\b|\bcredentials\.json\b|\bauth\.json\b")

# The only legitimate mention: a presence CHECK on the credential file inside a
# disposable config root the operator provisioned, e.g. "$CFG/.credentials.json".
# The variable is not pinned to CFG — a future client will name its own — but
# there may be no path segment between it and the file, which is what rules out
# "$HOME/.claude/.credentials.json".
ALLOWED_CREDENTIAL_REFERENCE = re.compile(r"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/\.credentials\.json")

# Copying, reading out, or shipping a credential file. Any of these on the same
# line as a credential file name is a leak of the operator's real credentials.
COPY_VERB = re.compile(
    r"(?<![A-Za-z0-9_-])"
    r"(cp|mv|scp|rsync|ln|dd|cat|tee|install|base64|curl|wget|xxd|od|"
    r"Copy-Item|Move-Item|Get-Content|shutil\.copy(?:file|2)?|read_text|read_bytes)"
    r"(?![A-Za-z0-9_-])"
)

# Files whose content is executed on the operator's machine. These carry the
# strict rule: a credential file may appear ONLY as the allowed presence check.
SCRIPT_SUFFIXES = frozenset(
    (".sh", ".bash", ".zsh", ".ps1", ".psm1", ".cmd", ".bat", ".py", ".js", ".ts", ".go")
)

# Files that are committed but are not text we can scan line by line.
BINARY_SUFFIXES = frozenset(
    (".png", ".jpg", ".jpeg", ".gif", ".pdf", ".zip", ".gz", ".tar", ".exe", ".dll", ".so")
)


def _walk(root: Path) -> tuple[Path, ...]:
    if not root.is_dir():
        raise AssertionError(f"sanitization sweep root does not exist: {root}")
    found: list[Path] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        if any(part in SKIP_DIRS for part in path.relative_to(root).parts[:-1]):
            continue
        if path.suffix.lower() in BINARY_SUFFIXES:
            continue
        try:
            path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, ValueError):
            continue
        found.append(path)
    if not found:
        raise AssertionError(f"sanitization sweep walked zero files under {root}")
    return tuple(found)


def files_by_root() -> tuple[tuple[Path, tuple[Path, ...]], ...]:
    """Every swept root paired with its files. Raises if any root is empty."""
    return tuple((root, _walk(root)) for root in SWEPT_ROOTS)


def committed_text_files() -> tuple[Path, ...]:
    """Every committed text file in the swept roots. Never empty — raises instead."""
    found: list[Path] = []
    for _root, paths in files_by_root():
        found.extend(paths)
    return tuple(found)


def is_script(path: Path) -> bool:
    return path.suffix.lower() in SCRIPT_SUFFIXES


def relative(path: Path) -> str:
    return path.relative_to(REPO).as_posix()
