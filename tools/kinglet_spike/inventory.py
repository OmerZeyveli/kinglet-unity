"""00D Task 2 — a disposition for every tracked file of the Python foundation.

If a runtime other than Python wins 0R, the existing builder does not disappear:
it is the only working implementation of the canonical format, and its tests are
the only written specification of what that implementation actually does. This
module decides, per file, what happens to it — and, more importantly, guarantees
that no file gets decided about by being forgotten.

Exhaustiveness is the property that matters. A wrong disposition is visible and
arguable; a file that never appears in the report is discovered when it stops
working. So the file list comes from `git ls-files`, not from a list kept here,
and `test_foundation_inventory.py` asserts the two agree.

Two rules are refusals rather than defaults:

* **A behavioural test is never `replace`.** Tests are migration assets whichever
  runtime wins. `retire-after-parity` is as strong as it gets.
* **Nothing leaves without naming its parity suite.** A row that says "this goes
  away" and cannot say what proves the replacement equivalent is a plan to lose
  behaviour quietly.

This module READS. It never writes to the tree it inventories.
"""
from __future__ import annotations

import json
import subprocess
from dataclasses import asdict, dataclass, field
from pathlib import Path

INVENTORY_SCHEMA = "kinglet.spike.foundation-inventory/v1"

# The plan's four, and only these.
DISPOSITIONS = ("keep", "adapt", "replace", "retire-after-parity")

# Where the foundation lives. `src`, `adapters` and `migration` are the canonical
# DATA the builder consumes; the other two are the implementation and its tests.
FOUNDATION_ROOTS = (
    "adapters",
    "migration",
    "src",
    "tests/kinglet",
    "tools/kinglet_build",
)

# The Python-only process entry point. `python3 -m tools.kinglet_build` is a
# packaging fact, not behaviour: whatever wins 0R ships its own entry point, and
# nothing about this file survives the move.
PACKAGING_ENTRY_POINTS = ("tools/kinglet_build/__main__.py",)


@dataclass(frozen=True)
class InventoryRow:
    path: str
    blob_sha: str
    responsibility: str
    disposition: str
    reason: str
    current_tests: tuple[str, ...] = ()
    parity_tests: tuple[str, ...] = ()
    evidence_ids: tuple[str, ...] = ()


@dataclass(frozen=True)
class FoundationInventory:
    selected_runtime: str
    rows: tuple[InventoryRow, ...] = field(default_factory=tuple)


def _git(repo_root: Path, *args: str) -> str:
    """Run git with an argument ARRAY. No shell, no quoting, no path surprises."""
    completed = subprocess.run(
        ["git", *args],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
        check=True,
    )
    return completed.stdout


def tracked_foundation_files(repo_root: Path) -> tuple[str, ...]:
    """Every tracked file under the foundation roots, sorted.

    From git, so untracked build output (`__pycache__`, `*.egg-info`) is excluded
    by construction rather than by a filter someone has to remember to widen.
    """
    output = _git(repo_root, "ls-files", "--", *FOUNDATION_ROOTS)
    return tuple(sorted(line for line in output.splitlines() if line))


def _blob_ids(repo_root: Path) -> dict[str, str]:
    """path -> git blob SHA, from `git ls-files -s`.

    The blob id is what makes a row checkable later: it names the exact content
    the disposition was decided about, so a reader can tell whether the file has
    moved on since.
    """
    output = _git(repo_root, "ls-files", "-s", "--", *FOUNDATION_ROOTS)
    blobs: dict[str, str] = {}
    for line in output.splitlines():
        if not line:
            continue
        # "<mode> <sha> <stage>\t<path>" — split on the TAB, because a path may
        # contain spaces and splitting on whitespace would truncate it.
        meta, _, path = line.partition("\t")
        fields = meta.split()
        if len(fields) < 2 or not path:
            raise ValueError(f"cannot parse `git ls-files -s` line: {line!r}")
        blobs[path] = fields[1]
    return blobs


def dirty_foundation_files(repo_root: Path) -> tuple[str, ...]:
    """Tracked foundation files with uncommitted modifications.

    An inventory generated over a dirty tree records blob ids that do not match
    what anybody else will check out, which makes every row unverifiable.

    ``diff HEAD``, not a bare ``diff``. A bare ``git diff`` compares the working
    tree against the INDEX, so ``git add`` silences this guard completely: the
    file is modified, its blob id is about to change, and the refusal never
    fires. That is not an unlikely sequence — the workflow this repository
    prescribes is commit, regenerate, commit, and staging is what sits between
    the first two. ``--cached`` alone has the mirror defect (it sees the staged
    change and misses the unstaged one); ``HEAD`` is the single form that sees
    both, which is what "uncommitted" means.

    Still invisible: an UNTRACKED file under a foundation root. It has no blob
    id to disagree with, so it cannot make an existing row unverifiable — but it
    can mean the inventory is missing a file, which is the exhaustiveness
    property ``tracked_foundation_files`` covers rather than this function.
    """
    output = _git(repo_root, "diff", "--name-only", "HEAD", "--", *FOUNDATION_ROOTS)
    return tuple(sorted(line for line in output.splitlines() if line))


def _test_modules(files: tuple[str, ...]) -> tuple[str, ...]:
    return tuple(
        path
        for path in files
        if path.startswith("tests/kinglet/") and path.endswith(".py")
        and Path(path).name.startswith("test_")
    )


def _responsibility(path: str) -> str:
    if path.startswith("tests/kinglet/fixtures/"):
        return "test fixture data"
    if path.startswith("tests/kinglet/"):
        return "behavioural test of the Python builder"
    if path in PACKAGING_ENTRY_POINTS:
        return "Python packaging entry point"
    if path.startswith("tools/kinglet_build/"):
        return "Python builder implementation"
    if path.startswith("adapters/"):
        return "adapter profile data"
    if path.startswith("migration/"):
        return "baseline inventory data"
    return "canonical source data"


def _classify(
    path: str, selected_runtime: str, test_modules: tuple[str, ...]
) -> tuple[str, str, tuple[str, ...]]:
    """(disposition, reason, parity_tests) for one file."""
    python_wins = selected_runtime == "python"

    if path.startswith("tests/kinglet/fixtures/"):
        return (
            "keep",
            f"fixture data is runtime-neutral; {selected_runtime} reads the same "
            f"canonical shapes",
            (),
        )

    if path.startswith("tests/kinglet/"):
        if python_wins:
            return ("keep", "python is the selected runtime; the suite runs as is", ())
        # Never `replace`: the assertions ARE the specification of current
        # behaviour, and that value does not depend on the implementation
        # language.
        return (
            "adapt",
            f"behavioural test: port the assertions to {selected_runtime}, keeping "
            f"the cases; the suite is the specification of current behaviour",
            (),
        )

    if path.startswith("tools/kinglet_build/"):
        if python_wins:
            return ("keep", "python is the selected runtime; the module stays", ())
        if path in PACKAGING_ENTRY_POINTS:
            return (
                "replace",
                f"packaging entry point only; {selected_runtime} ships its own, and "
                f"no behaviour of this file survives the move",
                test_modules,
            )
        return (
            "retire-after-parity",
            f"implementation behaviour must exist in {selected_runtime} and be "
            f"proved equivalent before this module is retired",
            test_modules,
        )

    return (
        "keep",
        f"canonical data consumed by the builder; unchanged by selecting "
        f"{selected_runtime}",
        (),
    )


def build_inventory(
    repo_root: Path,
    selected_runtime: str,
    *,
    allow_dirty: bool = False,
    evidence_ids: tuple[str, ...] = (),
) -> FoundationInventory:
    """One row per tracked foundation file, sorted by path.

    `allow_dirty` exists for local experimentation and must not be used for 0D
    generation: a row's blob id is its only anchor to reviewable content.
    """
    repo_root = Path(repo_root)
    if not allow_dirty:
        dirty = dirty_foundation_files(repo_root)
        if dirty:
            raise ValueError(
                "refusing to inventory a dirty foundation; commit or pass "
                f"allow_dirty=True: {', '.join(dirty)}"
            )

    files = tracked_foundation_files(repo_root)
    blobs = _blob_ids(repo_root)
    test_modules = _test_modules(files)

    rows: list[InventoryRow] = []
    for path in files:
        disposition, reason, parity = _classify(path, selected_runtime, test_modules)
        rows.append(
            InventoryRow(
                path=path,
                blob_sha=blobs[path],
                responsibility=_responsibility(path),
                disposition=disposition,
                reason=reason,
                current_tests=test_modules if path.startswith("tools/kinglet_build/") else (),
                parity_tests=parity,
                evidence_ids=evidence_ids,
            )
        )
    return FoundationInventory(selected_runtime=selected_runtime, rows=tuple(rows))


def render_inventory_json(report: FoundationInventory) -> str:
    """The report as data. No timestamp, no machine-local path — a regenerated
    report must be byte-identical or the difference is real."""
    value = {
        "schema": INVENTORY_SCHEMA,
        "selected_runtime": report.selected_runtime,
        "rows": [asdict(row) for row in report.rows],
    }
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def render_inventory_markdown(report: FoundationInventory) -> str:
    """One table, generated from the same rows as the JSON.

    Nothing here is hand-authored, and that is the point: the human-readable file
    is the one a reader trusts and the one nothing would otherwise check.
    """
    lines = [
        "# Kinglet Python Foundation — Migration Inventory",
        "",
        f"Selected runtime: **{report.selected_runtime}**. Every disposition below "
        "is conditional on that choice.",
        "",
        "Generated from `git ls-files` over the foundation roots — the file list is "
        "not maintained by hand, so a file cannot be decided about by being "
        "forgotten. No source file is deleted, ported or rewritten by this report.",
        "",
        "| File | Blob | Responsibility | Disposition | Why | Parity suite |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for row in report.rows:
        parity = (
            ", ".join(f"`{name}`" for name in row.parity_tests)
            if row.parity_tests
            else "—"
        )
        lines.append(
            f"| `{row.path}` | `{row.blob_sha[:12]}` | {row.responsibility} | "
            f"{row.disposition} | {row.reason} | {parity} |"
        )
    counts: dict[str, int] = {}
    for row in report.rows:
        counts[row.disposition] = counts.get(row.disposition, 0) + 1
    lines += ["", "## Totals", ""]
    for disposition in DISPOSITIONS:
        lines.append(f"- **{disposition}** — {counts.get(disposition, 0)}")
    return "\n".join(lines) + "\n"
