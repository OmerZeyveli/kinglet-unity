"""00D Task 2 — every tracked foundation file gets a disposition, and no file gets
a disposition by being forgotten.

The migration inventory decides what happens to the existing Python builder if
another runtime wins 0R. The failure mode is not a wrong disposition — a wrong
one is visible and arguable. It is a file that never appears at all: nobody
decides about it, nothing flags it, and it is discovered when it stops working.
So the exhaustiveness test is the load-bearing one, and it is written against
`git ls-files` rather than against a list this module keeps.

Two rules from the plan are enforced here rather than trusted:

* **A behavioural test is never immediately retired.** Tests are migration
  ASSETS: they are the specification of what the Python builder actually does,
  and they retain that value whichever runtime wins. `retire-after-parity` is
  the strongest disposition any of them may carry.
* **Nothing is replaced or retired without naming the parity suite.** A
  disposition that says "this goes away" and cannot say what proves the
  replacement equivalent is a plan to lose behaviour.
"""
from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path

from tools.kinglet_spike.inventory import (
    DISPOSITIONS,
    FOUNDATION_ROOTS,
    build_inventory,
    tracked_foundation_files,
)

REPO = Path(__file__).resolve().parents[2]
RULES_FILE = REPO / "spikes/platform/decision/inventory-rules-v1.json"


class TrackedFileDiscoveryTests(unittest.TestCase):
    def test_the_roots_are_not_vacuous(self):
        # A mistyped root discovers nothing and every exhaustiveness test below
        # then passes over an empty set.
        files = tracked_foundation_files(REPO)
        self.assertGreater(len(files), 20, "foundation discovery returned almost nothing")
        for root in FOUNDATION_ROOTS:
            self.assertTrue(
                any(path.startswith(root) for path in files),
                f"no tracked file discovered under {root!r}",
            )

    def test_discovery_agrees_with_git_itself(self):
        expected = set(
            subprocess.run(
                ["git", "ls-files", "--", *FOUNDATION_ROOTS],
                cwd=str(REPO),
                capture_output=True,
                text=True,
                check=True,
            ).stdout.split()
        )
        self.assertEqual(expected, set(tracked_foundation_files(REPO)))

    def test_untracked_build_output_is_excluded(self):
        self.assertFalse(
            [path for path in tracked_foundation_files(REPO) if "__pycache__" in path]
        )

    def test_the_result_is_sorted(self):
        files = tracked_foundation_files(REPO)
        self.assertEqual(list(files), sorted(files))


class FoundationInventoryTests(unittest.TestCase):
    def test_every_tracked_foundation_file_appears_once(self):
        report = build_inventory(REPO, "rust")
        paths = [row.path for row in report.rows]
        self.assertEqual(set(tracked_foundation_files(REPO)), set(paths))
        self.assertEqual(len(paths), len(set(paths)), "a file was inventoried twice")

    def test_behavioral_tests_are_never_immediately_retired(self):
        report = build_inventory(REPO, "rust")
        test_rows = [row for row in report.rows if row.path.startswith("tests/kinglet/")]
        self.assertTrue(test_rows)
        self.assertTrue(
            all(
                row.disposition in {"keep", "adapt", "retire-after-parity"}
                for row in test_rows
            )
        )

    def test_replace_or_retire_requires_parity_reference(self):
        for row in build_inventory(REPO, "go").rows:
            if row.disposition in {"replace", "retire-after-parity"}:
                self.assertTrue(row.parity_tests, f"{row.path} names no parity suite")

    def test_every_disposition_is_one_of_the_four(self):
        for row in build_inventory(REPO, "go").rows:
            self.assertIn(row.disposition, DISPOSITIONS, row.path)

    def test_every_row_carries_a_git_blob_id(self):
        for row in build_inventory(REPO, "go").rows:
            self.assertRegex(row.blob_sha, r"^[0-9a-f]{40}$", row.path)

    def test_every_row_says_why_for_this_runtime(self):
        for row in build_inventory(REPO, "go").rows:
            self.assertTrue(row.reason.strip(), row.path)
            self.assertIn("go", row.reason, row.path)


class SelectedRuntimeChangesTheAnswerTests(unittest.TestCase):
    """The inventory is a function of the winner, and must visibly be one.

    An inventory that returns the same dispositions whichever runtime is selected
    is not classifying anything; it is a file listing with an opinion column. The
    Python implementation modules are the ones that must move.
    """

    def _by_path(self, runtime: str) -> dict:
        return {row.path: row for row in build_inventory(REPO, runtime).rows}

    def test_the_python_implementation_is_kept_when_python_wins(self):
        rows = self._by_path("python")
        self.assertEqual("keep", rows["tools/kinglet_build/loader.py"].disposition)
        self.assertEqual("keep", rows["tools/kinglet_build/writer.py"].disposition)

    def test_the_python_implementation_retires_after_parity_when_it_does_not(self):
        rows = self._by_path("rust")
        row = rows["tools/kinglet_build/loader.py"]
        self.assertEqual("retire-after-parity", row.disposition)
        # "Every current test module named" — the plan's words. A parity suite
        # that names nothing cannot be checked against.
        self.assertTrue(row.parity_tests)
        self.assertTrue(
            all(name.startswith("tests/kinglet/") for name in row.parity_tests)
        )

    def test_canonical_source_data_is_kept_whichever_runtime_wins(self):
        # The catalog, rules and profiles are data. No runtime choice touches
        # them, and marking them for migration would be busywork with risk.
        for runtime in ("python", "rust", "go", "dotnet"):
            rows = self._by_path(runtime)
            with self.subTest(runtime=runtime):
                self.assertEqual(
                    "keep", rows["src/catalog/capabilities.json"].disposition
                )
                self.assertEqual(
                    "keep", rows["adapters/claude/profile.json"].disposition
                )

    def test_no_source_file_is_deleted_ported_or_rewritten_by_this_module(self):
        # The plan's hard constraint. build_inventory reads; it must not write.
        before = {
            path: (REPO / path).stat().st_mtime_ns
            for path in tracked_foundation_files(REPO)
        }
        build_inventory(REPO, "rust")
        after = {
            path: (REPO / path).stat().st_mtime_ns
            for path in tracked_foundation_files(REPO)
        }
        self.assertEqual(before, after)


class DeterminismTests(unittest.TestCase):
    def test_two_runs_produce_identical_rows(self):
        first = build_inventory(REPO, "rust")
        second = build_inventory(REPO, "rust")
        self.assertEqual(first.rows, second.rows)

    def test_rows_are_sorted_by_path(self):
        rows = build_inventory(REPO, "rust").rows
        self.assertEqual([row.path for row in rows], sorted(row.path for row in rows))


class RenderTests(unittest.TestCase):
    """The Markdown table is generated from the same rows as the JSON.

    The plan's words: "Markdown contains one table generated from JSON and no
    hand-edited disposition." A hand-edited Markdown disposition is the failure
    this guards — a reader trusts the human-readable file, and it is the one
    nothing checks.
    """

    def setUp(self):
        from tools.kinglet_spike.inventory import render_inventory_json

        self.report = build_inventory(REPO, "rust")
        self.value = json.loads(render_inventory_json(self.report))

    def test_json_carries_every_row_with_its_disposition(self):
        self.assertEqual(
            {row.path: row.disposition for row in self.report.rows},
            {row["path"]: row["disposition"] for row in self.value["rows"]},
        )

    def test_markdown_dispositions_come_from_the_same_rows(self):
        from tools.kinglet_spike.inventory import render_inventory_markdown

        text = render_inventory_markdown(self.report)
        for row in self.report.rows:
            line = next(
                (l for l in text.splitlines() if f"`{row.path}`" in l), None
            )
            self.assertIsNotNone(line, f"{row.path} missing from the table")
            self.assertIn(row.disposition, line, row.path)

    def test_rendering_is_deterministic(self):
        from tools.kinglet_spike.inventory import (
            render_inventory_json,
            render_inventory_markdown,
        )

        again = build_inventory(REPO, "rust")
        self.assertEqual(
            render_inventory_json(self.report), render_inventory_json(again)
        )
        self.assertEqual(
            render_inventory_markdown(self.report), render_inventory_markdown(again)
        )

    def test_the_report_contains_no_machine_local_path(self):
        # A deterministic report cannot carry an absolute path from the machine
        # that generated it.
        from tools.kinglet_spike.inventory import render_inventory_markdown

        for text in (json.dumps(self.value), render_inventory_markdown(self.report)):
            self.assertNotIn(str(REPO), text)
            self.assertNotIn("/home/", text)

    def test_the_selected_runtime_is_stated_in_the_report(self):
        # Every disposition is conditional on the winner. A report that does not
        # say which runtime it assumed is a table of unattributed opinions.
        from tools.kinglet_spike.inventory import render_inventory_markdown

        self.assertEqual("rust", self.value["selected_runtime"])
        self.assertIn("rust", render_inventory_markdown(self.report))


class DirtyTreeRefusalTests(unittest.TestCase):
    def test_a_dirty_foundation_is_refused_by_default(self):
        from unittest.mock import patch

        with patch(
            "tools.kinglet_spike.inventory.dirty_foundation_files",
            return_value=("tools/kinglet_build/loader.py",),
        ):
            with self.assertRaises(ValueError) as caught:
                build_inventory(REPO, "rust")
            self.assertIn("loader.py", str(caught.exception))

    def test_allow_dirty_is_an_explicit_opt_in(self):
        from unittest.mock import patch

        with patch(
            "tools.kinglet_spike.inventory.dirty_foundation_files",
            return_value=("tools/kinglet_build/loader.py",),
        ):
            report = build_inventory(REPO, "rust", allow_dirty=True)
        self.assertTrue(report.rows)


class CliTests(unittest.TestCase):
    """The runtime must be named on the command line, never guessed.

    0R is open: no runtime has been selected and the ADR does not exist. A CLI
    with a default would silently produce a report that reads as a decision,
    which is the exact fabrication this project refuses everywhere else.
    """

    def test_omitting_the_selected_runtime_fails(self):
        # main() converts argparse's error into exit code 2 rather than letting
        # SystemExit escape, so the contract to assert is the code.
        from tools.kinglet_spike.cli import main

        self.assertEqual(2, main(["inventory", "--repo-root", str(REPO)]))

    def test_naming_a_runtime_writes_both_reports(self):
        import tempfile
        from tools.kinglet_spike.cli import main
        from tools.kinglet_spike.inventory import render_inventory_json

        with tempfile.TemporaryDirectory() as tmpdir:
            out = Path(tmpdir)
            code = main(
                [
                    "inventory",
                    "--repo-root", str(REPO),
                    "--selected-runtime", "rust",
                    "--out-dir", str(out),
                ]
            )
            self.assertEqual(0, code)
            written = (out / "python-foundation-inventory.json").read_text(
                encoding="utf-8"
            )
            self.assertTrue((out / "python-foundation-inventory.md").is_file())
        self.assertEqual(render_inventory_json(build_inventory(REPO, "rust")), written)


class CommittedRulesMatchTheCodeTests(unittest.TestCase):
    def setUp(self):
        self.rules = json.loads(RULES_FILE.read_text(encoding="utf-8"))

    def test_schema_is_the_frozen_one(self):
        self.assertEqual("kinglet.spike.inventory-rules/v1", self.rules["schema"])

    def test_the_file_declares_the_same_four_dispositions(self):
        self.assertEqual(list(DISPOSITIONS), self.rules["dispositions"])

    def test_the_file_declares_the_same_roots(self):
        self.assertEqual(list(FOUNDATION_ROOTS), self.rules["roots"])


if __name__ == "__main__":
    unittest.main()
