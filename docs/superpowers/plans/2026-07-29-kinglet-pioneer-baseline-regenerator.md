# Baseline Regenerator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make regenerating `migration/baseline-inventory.json` a durable tool with its safety gate built in, instead of a script in a frozen plan document guarded by prose someone must remember to follow.

**Architecture:** One task. A pure planner in `tools/kinglet_build/baseline.py` that reads the anchor commit's tree, classifies every baseline record against it, and **refuses** rather than writing whenever the change is anything other than the caller already predicted. A thin writer applies an approved plan. A CLI subcommand wires them together.

**Tech Stack:** Python 3.10+ standard library only, `git` via `subprocess`, `unittest` under `tests/kinglet/`.

## Why this exists

`migration/baseline-inventory.json` records the sha256 and git mode of every payload file. Its purpose is to detect unintended change. That makes regenerating it the single most dangerous operation in this repository: **regenerating over unrelated breakage records the breakage as the new expected state**, laundering a regression into evidence, permanently and invisibly.

Wave 1a regenerated it once, and what protected that operation was a prose instruction in a plan document — *"if any fourth test name appears, stop and report BLOCKED"* — executed correctly by a human-directed agent that happened to read it. Nothing about that protection survives into the next regeneration, and Wave 1b and Wave 2 will each drift the baseline again with every payload edit.

The gate belongs in the tool.

## Global Constraints

- **Python 3.10+, standard library only.** No new dependencies. `tools/kinglet_build/` currently imports only `hashlib`, `json`, `subprocess`, `re`, `pathlib`, `collections.abc`.
- **The planner is pure with respect to the filesystem it is auditing**: it reads git and the baseline document, and returns a decision. It never writes. Writing is a separate function that takes an already-approved plan. A planner that could write is a planner whose refusal can be bypassed by a caller in a hurry.
- **Read blobs from git, not from the working tree.** `git ls-tree -r -z <anchor>` and `git cat-file blob <oid>`, matching `source_commit_errors`. The working tree and the anchor agree only when the tree is clean, and the checks compare against git.
- **`bash tests/run-tests.sh` must pass, with all test files present in the output.** Count them; this runner has reported green while running one file of eight.
- **`scripts/check-provenance.sh` must report `provenance OK`.** New tracked files need a `provenance.tsv` row (`original` / `original`).
- **Do not change `migration/baseline-inventory.json` in this plan.** The tool is built and tested against fixtures and temporary repositories. Running it for real is a later, separate act.
- **Do not move or rewrite `full_tree_errors`.** It currently lives in `tests/kinglet/test_baseline_inventory.py`. Relocating it is a real improvement and a different change; doing it here would mix a refactor into the one commit that must be easy to audit.

---

### Task 1: The regeneration planner, its gate, and the writer

**Files:**
- Modify: `tools/kinglet_build/baseline.py` — add `regeneration_plan`, `apply_regeneration`, and their supporting dataclasses; extend `__all__`
- Modify: `tools/kinglet_build/cli.py` — add a `baseline-regenerate` subcommand following the existing subparser pattern
- Test: `tests/kinglet/test_baseline_regenerator.py` (create)
- Modify: `provenance.tsv` — one new row for the test file

**Interfaces:**

- Consumes: `_git` and the tree-reading approach already in `tools/kinglet_build/baseline.py`.
- Produces:

```python
@dataclass(frozen=True)
class BaselineChange:
    path: str
    structure: str          # "full_claude_tree" or "categories.<name>"
    old_sha256: str
    new_sha256: str
    old_git_mode: str
    new_git_mode: str


@dataclass(frozen=True)
class RegenerationPlan:
    anchor: str                                  # resolved full commit id
    changes: tuple[BaselineChange, ...]          # content/mode drift, ordered by (structure, path)
    refusals: tuple[str, ...]                    # non-empty means: write nothing

    @property
    def approved(self) -> bool:
        return not self.refusals


def regeneration_plan(
    repository_root: Path,
    anchor: str,
    baseline: Mapping,
    *,
    expected_drift: int | None = None,
) -> RegenerationPlan: ...


def apply_regeneration(baseline: Mapping, plan: RegenerationPlan) -> dict: ...
```

`apply_regeneration` raises `ValueError` when handed a plan that is not `approved`. It returns a new document; it does not write to disk. The CLI does the writing.

### The refusal rules

`refusals` is populated — and therefore nothing is written — when any of these hold. Each entry is a human-readable string naming the specific problem.

| Condition | Refusal | Why |
|---|---|---|
| `anchor` does not resolve to a commit | `anchor is not a commit: <anchor>` | Anchoring evidence to a non-commit is meaningless |
| `anchor` is not an ancestor of `HEAD` | `anchor is not an ancestor of HEAD: <anchor>` | Same rule `source_commit_errors` already enforces |
| A recorded path is absent from the tree at `anchor` | `path missing at anchor: <path>` | A baseline that silently shrinks is how coverage evidence rots |
| A recorded path is not a blob at `anchor` | `path is not a blob at anchor: <path>` | — |
| `full_claude_tree` does not list every `.claude/**` path present at `anchor` | `unrecorded .claude path at anchor: <path>` | `full_claude_tree` claims completeness; a new payload file must be added deliberately, not absorbed |
| `expected_drift` is not `None` and differs from `len(changes)` | `expected drift <n>, found <m>` | The forcing function — see below |

**On `expected_drift`.** The caller must state how many files they believe they changed. A regeneration that touches a different number than predicted is, by definition, not the change the caller had in mind, and that is exactly the case where regenerating anyway is dangerous. It is the same shape as the occurrence-count assertion the identity guard uses: knowing the number is what proves you looked.

It defaults to `None` (unchecked) so that the planner stays useful for reporting — `regeneration_plan(...)` with no expectation is how you *find out* the number. The CLI makes it mandatory.

**What this gate does not do.** It cannot distinguish an intended content edit from an unintended one — nothing can, from bytes alone. What it does is make the *path set* immutable without a deliberate act, and force the caller to name the drift count before anything is written. Say this in the module docstring so the next reader does not over-trust it.

- [ ] **Step 1: Write the failing tests**

Create `tests/kinglet/test_baseline_regenerator.py`. Build temporary git repositories in `tempfile.TemporaryDirectory()` — do not test against this repository's real baseline, and do not mutate this checkout.

```python
"""Tests for the migration-baseline regenerator and its refusal gate."""

import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.kinglet_build.baseline import (
    apply_regeneration,
    regeneration_plan,
)


def _run(root: Path, *arguments: str) -> None:
    subprocess.run(arguments, cwd=root, check=True, capture_output=True)


def _init_repository(root: Path) -> None:
    _run(root, "git", "init", "-q")
    _run(root, "git", "config", "user.email", "test@example.invalid")
    _run(root, "git", "config", "user.name", "Test")


def _write(root: Path, relative: str, text: str) -> None:
    target = root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def _commit(root: Path, message: str) -> str:
    _run(root, "git", "add", "-A")
    _run(root, "git", "commit", "-q", "-m", message)
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True
    )
    return result.stdout.decode("ascii").strip()


def _sha256_of(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _baseline_for(paths: dict[str, str], categories: dict[str, list[str]]) -> dict:
    return {
        "schema_version": 1,
        "source_commit": "0" * 40,
        "full_claude_tree": {
            "expected_count": len(paths),
            "files": [
                {"path": path, "sha256": _sha256_of(text), "git_mode": "100644"}
                for path, text in sorted(paths.items())
            ],
        },
        "categories": {
            name: {
                "files": [
                    {
                        "path": path,
                        "sha256": _sha256_of(paths[path]),
                        "git_mode": "100644",
                    }
                    for path in sorted(members)
                ]
            }
            for name, members in categories.items()
        },
    }


class RegenerationPlanTests(unittest.TestCase):
    def test_a_clean_tree_produces_no_changes_and_no_refusals(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _init_repository(root)
            files = {".claude/VERSION": "1.0.0\n", ".claude/rules/a.md": "alpha\n"}
            for path, text in files.items():
                _write(root, path, text)
            anchor = _commit(root, "initial")
            baseline = _baseline_for(files, {"rules": [".claude/rules/a.md"]})

            plan = regeneration_plan(root, anchor, baseline)

            self.assertEqual((), plan.refusals)
            self.assertEqual((), plan.changes)
            self.assertTrue(plan.approved)

    def test_content_drift_is_reported_in_both_structures(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _init_repository(root)
            files = {".claude/VERSION": "1.0.0\n", ".claude/rules/a.md": "alpha\n"}
            for path, text in files.items():
                _write(root, path, text)
            _commit(root, "initial")
            baseline = _baseline_for(files, {"rules": [".claude/rules/a.md"]})

            _write(root, ".claude/rules/a.md", "beta\n")
            anchor = _commit(root, "edit the rule")

            plan = regeneration_plan(root, anchor, baseline)

            self.assertEqual((), plan.refusals)
            structures = sorted(change.structure for change in plan.changes)
            self.assertEqual(["categories.rules", "full_claude_tree"], structures)
            for change in plan.changes:
                self.assertEqual(".claude/rules/a.md", change.path)
                self.assertEqual(_sha256_of("beta\n"), change.new_sha256)

    def test_a_path_missing_at_the_anchor_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _init_repository(root)
            files = {".claude/VERSION": "1.0.0\n"}
            _write(root, ".claude/VERSION", files[".claude/VERSION"])
            anchor = _commit(root, "initial")
            baseline = _baseline_for(
                {**files, ".claude/gone.md": "vanished\n"}, {}
            )

            plan = regeneration_plan(root, anchor, baseline)

            self.assertFalse(plan.approved)
            self.assertIn("path missing at anchor: .claude/gone.md", plan.refusals)

    def test_an_unrecorded_claude_path_at_the_anchor_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _init_repository(root)
            files = {".claude/VERSION": "1.0.0\n"}
            _write(root, ".claude/VERSION", files[".claude/VERSION"])
            _write(root, ".claude/surprise.md", "new payload\n")
            anchor = _commit(root, "initial")
            baseline = _baseline_for(files, {})

            plan = regeneration_plan(root, anchor, baseline)

            self.assertFalse(plan.approved)
            self.assertIn(
                "unrecorded .claude path at anchor: .claude/surprise.md",
                plan.refusals,
            )

    def test_a_drift_count_other_than_predicted_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _init_repository(root)
            files = {".claude/a.md": "one\n", ".claude/b.md": "two\n"}
            for path, text in files.items():
                _write(root, path, text)
            _commit(root, "initial")
            baseline = _baseline_for(files, {})

            _write(root, ".claude/a.md", "ONE\n")
            _write(root, ".claude/b.md", "TWO\n")
            anchor = _commit(root, "edit both")

            plan = regeneration_plan(root, anchor, baseline, expected_drift=1)

            self.assertFalse(plan.approved)
            self.assertIn("expected drift 1, found 2", plan.refusals)

    def test_the_predicted_drift_count_is_approved(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _init_repository(root)
            files = {".claude/a.md": "one\n", ".claude/b.md": "two\n"}
            for path, text in files.items():
                _write(root, path, text)
            _commit(root, "initial")
            baseline = _baseline_for(files, {})

            _write(root, ".claude/a.md", "ONE\n")
            anchor = _commit(root, "edit one")

            plan = regeneration_plan(root, anchor, baseline, expected_drift=1)

            self.assertTrue(plan.approved)

    def test_a_non_commit_anchor_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _init_repository(root)
            _write(root, ".claude/a.md", "one\n")
            _commit(root, "initial")
            baseline = _baseline_for({".claude/a.md": "one\n"}, {})

            plan = regeneration_plan(root, "not-a-commit", baseline)

            self.assertFalse(plan.approved)
            self.assertTrue(
                any("is not a commit" in refusal for refusal in plan.refusals),
                plan.refusals,
            )

    def test_an_anchor_that_is_not_an_ancestor_of_head_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _init_repository(root)
            _write(root, ".claude/a.md", "one\n")
            _commit(root, "initial")
            _run(root, "git", "checkout", "-q", "-b", "sidetrack")
            _write(root, ".claude/a.md", "side\n")
            sidetrack = _commit(root, "sidetrack")
            _run(root, "git", "checkout", "-q", "-")
            baseline = _baseline_for({".claude/a.md": "one\n"}, {})

            plan = regeneration_plan(root, sidetrack, baseline)

            self.assertFalse(plan.approved)
            self.assertTrue(
                any("not an ancestor" in refusal for refusal in plan.refusals),
                plan.refusals,
            )


class ApplyRegenerationTests(unittest.TestCase):
    def test_applying_a_refused_plan_raises(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _init_repository(root)
            _write(root, ".claude/a.md", "one\n")
            anchor = _commit(root, "initial")
            baseline = _baseline_for(
                {".claude/a.md": "one\n", ".claude/gone.md": "x\n"}, {}
            )
            plan = regeneration_plan(root, anchor, baseline)

            with self.assertRaises(ValueError):
                apply_regeneration(baseline, plan)

    def test_applying_updates_both_structures_and_the_anchor(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _init_repository(root)
            files = {".claude/rules/a.md": "alpha\n"}
            _write(root, ".claude/rules/a.md", files[".claude/rules/a.md"])
            _commit(root, "initial")
            baseline = _baseline_for(files, {"rules": [".claude/rules/a.md"]})

            _write(root, ".claude/rules/a.md", "beta\n")
            anchor = _commit(root, "edit")

            plan = regeneration_plan(root, anchor, baseline, expected_drift=2)
            updated = apply_regeneration(baseline, plan)

            self.assertEqual(anchor, updated["source_commit"])
            self.assertEqual(
                _sha256_of("beta\n"),
                updated["full_claude_tree"]["files"][0]["sha256"],
            )
            self.assertEqual(
                _sha256_of("beta\n"),
                updated["categories"]["rules"]["files"][0]["sha256"],
            )

    def test_applying_does_not_mutate_the_document_it_was_given(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _init_repository(root)
            _write(root, ".claude/a.md", "one\n")
            _commit(root, "initial")
            baseline = _baseline_for({".claude/a.md": "one\n"}, {})
            original = json.dumps(baseline, sort_keys=True)

            _write(root, ".claude/a.md", "ONE\n")
            anchor = _commit(root, "edit")

            plan = regeneration_plan(root, anchor, baseline, expected_drift=1)
            apply_regeneration(baseline, plan)

            self.assertEqual(original, json.dumps(baseline, sort_keys=True))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 90 python3 -m unittest tests.kinglet.test_baseline_regenerator -v 2>&1 | awk 'NR<=40'`

Expected: an `ImportError` on `apply_regeneration` / `regeneration_plan`, because neither exists yet. That is the correct first failure. Once the functions exist as stubs, every test must fail on its assertion, not on a `TypeError` from a wrong signature — check that before implementing the bodies.

- [ ] **Step 3: Implement the planner and the writer**

In `tools/kinglet_build/baseline.py`, alongside `source_commit_errors`:

- Add a module docstring paragraph stating plainly what the gate does and does not do: it makes the path set immutable without a deliberate act and forces the caller to name the drift count, and it **cannot** tell an intended content edit from an unintended one.
- Read the tree at the anchor once, with `git ls-tree -r -z <anchor>`, and cache blob digests by object id so a file recorded in both structures is hashed once. `source_commit_errors` already does this; follow it.
- Build `changes` from every record whose `sha256` or `git_mode` differs, across `full_claude_tree.files` and every `categories.<name>.files`. A path in both structures yields two changes — that is correct, they are two records.
- Order `changes` by `(structure, path)` so the output is deterministic and diffable.
- Collect refusals in the table's order; return them all rather than stopping at the first, so one run tells the caller everything that is wrong.
- `apply_regeneration` deep-copies the document, applies each change to its structure, sets `source_commit`, and returns the copy.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 90 python3 -m unittest tests.kinglet.test_baseline_regenerator -v`
Expected: all tests pass.

Run: `timeout 90 python3 -m unittest discover -s tests/kinglet -t .`
Expected: `OK` — the existing baseline tests must be unaffected.

- [ ] **Step 5: Wire the CLI**

Add a `baseline-regenerate` subcommand to `tools/kinglet_build/cli.py`, following the subparser pattern already there:

- `--anchor <commit>` (required)
- `--expect-drift <n>` (**required** — the CLI does not accept `None`; a human running this by hand is exactly who must state the number)
- `--repo-root <path>` (default: the repository root, resolved the same way the existing subcommands resolve it)
- `--dry-run` — print the plan and write nothing

Behaviour: build the plan; if it is not approved, print every refusal to stderr and exit non-zero **without writing**; if approved and not `--dry-run`, write the updated document back with `indent=2`, `ensure_ascii=False`, and a trailing newline, matching the file's existing formatting. Print the change count and the anchor on success.

- [ ] **Step 6: Verify the CLI refuses and reports**

Against this repository, where the baseline is currently in sync, both of these must hold:

```bash
python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift 0 --dry-run
python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift 3 --dry-run; echo "exit=$?"
```

Expected: the first reports zero changes and writes nothing; the second exits non-zero with `expected drift 3, found 0`. Confirm `git status --porcelain` is empty afterwards — a `--dry-run` that writes is the one bug this command must not have.

- [ ] **Step 7: Full suite, provenance, and commit**

```bash
bash tests/run-tests.sh          # green; count the test files in the output
bash scripts/check-provenance.sh # provenance OK
printf 'tests/kinglet/test_baseline_regenerator.py\toriginal\t-\t-\t-\toriginal\tgates-the-baseline-regeneration-against-laundered-regressions\n' >> provenance.tsv
bash scripts/check-provenance.sh
```

```bash
git add tools/kinglet_build/baseline.py tools/kinglet_build/cli.py \
        tests/kinglet/test_baseline_regenerator.py provenance.tsv
git commit -m "feat: put the baseline regeneration gate in the tool, not in prose

Regenerating the baseline over unrelated breakage records the breakage as
the expected state. Wave 1a was protected from that by an instruction in a
plan document, which the next regeneration does not inherit — and every
payload edit from here on drifts the baseline again.

The planner refuses rather than writing: a path that vanished, a .claude
file nobody recorded, an anchor that is not an ancestor of HEAD, or a drift
count other than the one the caller predicted. Naming the number is what
proves you looked.

It still cannot tell an intended edit from an unintended one. The docstring
says so, because a gate people over-trust is worse than one they read."
```

## Self-review

**Spec coverage.** This plan implements the final review's deferred minor in full: the regeneration script becomes a tool, and the pre-flight gate becomes code rather than prose.

**Placeholder scan.** No TBD, no "handle errors appropriately". Every refusal string, signature, and test body is written out.

**Type consistency.** `RegenerationPlan.changes` is a tuple of `BaselineChange` in Steps 1, 3 and 5; `approved` is a property in the interface block and used as one in the tests and the CLI; `expected_drift` is keyword-only and optional in the library, required at the CLI, and both are stated. `apply_regeneration` returns a document and never writes, in the interface block, Step 3, and Step 5 alike.
