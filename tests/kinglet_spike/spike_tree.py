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

Three ways this sweep was quietly narrower than it read, all closed here:

* It skipped `bin`/`dist`/`obj`/`target` by NAME at any depth, so any client got
  a free no-scan zone. Skips are anchored paths now (`SKIP_RELATIVE_DIRS`), and
  only tool caches are matched by name.
* It `continue`d past files it could not decode, which is also exactly what the
  CI grep's `-I` does — a leak with a stray byte in it was invisible to both.
  `_walk` now raises and names the file.
* Its "allowed presence check" accepted ANY variable, where the by-name
  claude-code rule pins `$CFG`. A generalization that accepts more than the rule
  it generalizes protects every client except the one already covered. The
  variable is pinned to a known list, and `credential_copy_violations` follows a
  credential path across assignments so the copy need not be on one line.
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

# Tool caches. These are generated, never committed, and matching them by NAME at
# any depth is safe only because nothing tracked ever lives inside one —
# `test_no_tracked_file_hides_in_a_skipped_directory` holds that line.
#
# Build-output NAMES are deliberately absent. `bin`, `dist`, `obj` and `target`
# used to be skipped by name at any depth, which handed every client a silent
# no-scan zone: `clients/<any>/bin/leak.sh` was green in the sweep and invisible
# to the CI grep. `probe/run.sh` already creates a `bin/` in its package layout,
# so that is a shape someone would plausibly commit. Real build output is skipped
# by ANCHORED path below instead, so a new `bin/` anywhere is swept.
SKIP_DIR_NAMES = frozenset((".git", "__pycache__", "node_modules", ".venv"))

# Committed-adjacent build output, skipped by exact repo-relative path. Adding a
# row here is a deliberate, reviewable act; adding a directory name is not.
SKIP_RELATIVE_DIRS = ("spikes/platform/clients/probe-host/dist",)

# The disposable live-run root must never appear in committed text.
PROBE_ROOT = re.compile(r"/tmp/kinglet-live")

# A credential FILE, however it is spelled. Bare "credentials" in prose ("the
# scripts do not copy credentials") is deliberately not matched — this is about
# naming a file, not about the word. `\.credentials` carries no trailing `\b` so
# that this pattern is never narrower than the `\.credentials` the by-name
# claude-code test uses; see test_the_generic_credential_rule_is_at_least_as_
# strict_as_the_by_name_one.
CREDENTIAL_FILE = re.compile(r"\.credentials|\bcredentials\.json\b|\bauth\.json\b")

# The only legitimate mention: a presence CHECK on the credential file inside the
# DISPOSABLE config root the operator provisioned, e.g. "$CFG/.credentials.json".
#
# The variable used to be unpinned — any `$X/.credentials.json` passed. That made
# this generic rule strictly WEAKER than the `$CFG`-pinned by-name rule it
# generalizes, and the gap was exploitable in three lines:
#
#     H="$HOME/.claude"
#     F="$H/.credentials.json"      # "allowed" presence check under the unpinned rule
#     cp "$F" ./stolen.json         # no credential filename on this line
#
# Two defences, because either alone is bypassable. First: the variable must be a
# known disposable-config name, so `$H` is not a presence check. Second:
# `credential_copy_violations` follows the credential across assignments, so the
# copy on line 3 is caught whatever the variable is called.
DISPOSABLE_CONFIG_VARS = (
    "CFG",
    "CLAUDE_CONFIG_DIR",
    "CLIENT_CFG",
    "CODEX_HOME",
    "CONFIG_DIR",
    "KINGLET_CFG",
    "PROBE_CFG",
    "XDG_CONFIG_HOME",
)
ALLOWED_CREDENTIAL_REFERENCE = re.compile(
    r"\$\{?(?:" + "|".join(DISPOSABLE_CONFIG_VARS) + r")\}?/\.credentials\.json"
)

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

# Files that are committed but are not text we can scan line by line. This list
# is the ONLY way out of the sweep: a file that is neither listed here nor
# decodable as UTF-8 raises, it is not skipped (see `_walk`).
BINARY_SUFFIXES = frozenset(
    (
        ".png", ".jpg", ".jpeg", ".gif", ".ico", ".pdf",
        ".zip", ".gz", ".bz2", ".xz", ".tar",
        ".exe", ".dll", ".so", ".dylib", ".a", ".o", ".pyc", ".class", ".jar", ".wasm",
        ".woff", ".woff2", ".ttf", ".otf",
    )
)

# An assignment, in the languages this tree actually ships: `F=x`, `export F=x`,
# `$F = x` (PowerShell), `f = x` (Python), `f := x`.
_ASSIGNMENT = re.compile(
    r"^\s*(?:export|local|declare|typeset|readonly|set|const|let|var)?\s*"
    r"\$?([A-Za-z_][A-Za-z0-9_]*)\s*(?::=|=)(?!=)\s*\S"
)


def _references(line: str, name: str) -> bool:
    """Does `line` mention variable `name`?

    A word boundary covers every spelling that matters here — `$F`, `${F}`, `%F%`
    and a bare Python identifier — because `$`, `{` and `%` are all non-word.
    """
    return re.search(r"\b" + re.escape(name) + r"\b", line) is not None


def credential_copy_violations(text: str) -> tuple[tuple[int, str, str], ...]:
    """Lines that copy a credential file, following it across assignments.

    The same-line rule (credential filename AND a copy verb on one line) is
    trivially defeated by naming the file on one line and copying the variable on
    the next. This walks the file top to bottom carrying a taint set: any
    variable assigned from something that names a credential file — or from an
    already-tainted variable — is itself tainted, and a copy verb applied to a
    tainted variable is a violation wherever it appears.

    Returns `(line_number, line, reason)` triples so the caller can name the line.
    """
    tainted: list[str] = []
    violations: list[tuple[int, str, str]] = []
    for number, line in enumerate(text.splitlines(), start=1):
        named = CREDENTIAL_FILE.search(line) is not None
        carrier = next((name for name in tainted if _references(line, name)), None)
        if (named or carrier) and COPY_VERB.search(line):
            reason = (
                "copies or reads out a credential file"
                if named
                else f"copies ${carrier}, which holds a credential file path"
            )
            violations.append((number, line, reason))
        if named or carrier:
            assignment = _ASSIGNMENT.match(line)
            if assignment and assignment.group(1) not in tainted:
                tainted.append(assignment.group(1))
    return tuple(violations)


def _walk(root: Path) -> tuple[Path, ...]:
    if not root.is_dir():
        raise AssertionError(f"sanitization sweep root does not exist: {root}")
    skipped = tuple((REPO / rel).resolve() for rel in SKIP_RELATIVE_DIRS)
    found: list[Path] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        if any(part in SKIP_DIR_NAMES for part in path.relative_to(root).parts[:-1]):
            continue
        if any(skip in path.resolve().parents for skip in skipped):
            continue
        if path.suffix.lower() in BINARY_SUFFIXES:
            continue
        try:
            path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, ValueError) as error:
            # NOT `continue`. A file that is neither a known binary suffix nor
            # decodable is an anomaly this sweep cannot vouch for, and skipping it
            # silently is how `leak.bin.txt` — a token, an absolute home path and
            # a few stray \xff bytes — passed both this sweep and the CI grep,
            # which classifies it as binary and ignores it too.
            raise AssertionError(
                f"sanitization sweep cannot decode {relative(path)} "
                f"as UTF-8 ({error}); it is not a known binary suffix, so it is "
                f"unscannable committed text — give it a binary suffix or remove it"
            ) from None
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
    try:
        return path.relative_to(REPO).as_posix()
    except ValueError:
        # Scratch paths outside the repo (the sweep's own unit tests) still have
        # to be nameable — the whole point of the undecodable-file failure is
        # that it names the file it could not read.
        return path.as_posix()
