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
