import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from tools.kinglet_build.baseline import (
    apply_regeneration,
    category_paths,
    regeneration_plan,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BASELINE_PATH = REPOSITORY_ROOT / "migration" / "baseline-inventory.json"
EXPECTED_COUNTS = {
    "agents": 8,
    "commands": 11,
    "skills": 16,
    "hooks": 27,
    "rules": 6,
    "claude_templates": 0,
    "code_templates": 10,
}
FULL_CLAUDE_TREE_COUNT = 79
OMITTED_FROM_SEVEN_CATEGORIES = {
    ".claude/NOTICE.md",
    ".claude/UPSTREAM",
    ".claude/VERSION",
    ".claude/hooks/_lib.sh",
    ".claude/settings.json",
    ".claude/settings.local.json.template",
    ".claude/state/.gitkeep",
}


def tracked_paths() -> list[str]:
    output = subprocess.check_output(
        ["git", "ls-files", "-z"],
        cwd=REPOSITORY_ROOT,
    )
    return sorted(path for path in output.decode().split("\0") if path)


def tracked_modes() -> dict[str, str]:
    output = subprocess.check_output(
        ["git", "ls-files", "-s", "-z"],
        cwd=REPOSITORY_ROOT,
    )
    modes = {}
    for record in output.decode().split("\0"):
        if not record:
            continue
        metadata, path = record.split("\t", 1)
        modes[path] = metadata.split()[0]
    return modes


def source_commit_errors(
    repository_root: Path,
    source_commit: object,
    records: list[dict[str, str]],
) -> list[str]:
    specification = importlib.util.find_spec("tools.kinglet_build.baseline")
    if specification is None:
        raise AssertionError("tools.kinglet_build.baseline must implement anchor checks")
    from tools.kinglet_build.baseline import source_commit_errors as check

    return check(repository_root, source_commit, records)


def full_tree_errors(
    repository_root: Path,
    actual_paths: list[str],
    actual_modes: dict[str, str],
    baseline_records: list[dict[str, str]],
) -> list[str]:
    errors = []
    expected_by_path = {record["path"]: record for record in baseline_records}
    expected_paths = set(expected_by_path)
    tracked_paths = set(actual_paths)

    for path in sorted(expected_paths - tracked_paths):
        errors.append(f"missing full-tree path: {path}")
    for path in sorted(tracked_paths - expected_paths):
        errors.append(f"unexpected full-tree path: {path}")

    for path in sorted(expected_paths & tracked_paths):
        record = expected_by_path[path]
        source = repository_root / path
        if not source.is_file():
            errors.append(f"missing inventory path: {path}")
            continue
        actual_sha256 = hashlib.sha256(source.read_bytes()).hexdigest()
        if actual_sha256 != record["sha256"]:
            errors.append(f"sha256 drift: {path}")
        actual_mode = actual_modes.get(path)
        if actual_mode != record["git_mode"]:
            errors.append(
                f"git mode drift: {path} "
                f"(expected {record['git_mode']}, got {actual_mode})"
            )

    return errors


class BaselineInventoryTests(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls) -> None:
        cls.baseline = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))

    # --- regeneration_plan / apply_regeneration fixture -------------------
    #
    # Task 0 findings, Important-1: the original four tests deep-copied the
    # real migration/baseline-inventory.json and checked it against the real
    # HEAD tree. That makes them joint assertions over three things — the
    # tool, the current contents of that JSON, and the HEAD tree — and they
    # go red every time a real removal/addition wave leaves the baseline
    # deliberately out of sync, which is precisely when this tool is used.
    #
    # Instead, build an isolated one-commit git repository with a small,
    # fully controlled `.claude` + `templates` tree, and a baseline document
    # that records only some of it. regeneration_plan and apply_regeneration
    # are then exercised entirely against this fixture — never against
    # REPOSITORY_ROOT or the real baseline — so these tests stay green
    # regardless of what the real baseline or the real tree currently say.
    #
    # The fixture also carries the case Important-2 requires: a tracked
    # path outside `.claude/` (`templates/two.template`, category
    # `code_templates`) that the baseline does not record, so the addition
    # scan is proven to see paths the old `.claude/`-only scan missed.

    _RECORDED_AGENT_PATHS = (".claude/agents/alpha.md", ".claude/agents/gamma.md")
    _UNRECORDED_AGENT_PATH = ".claude/agents/beta.md"  # sorts between alpha and gamma
    _PHANTOM_AGENT_PATH = ".claude/agents/does-not-exist.md"
    _RECORDED_TEMPLATE_PATHS = ("templates/one.template", "templates/three.template")
    _UNRECORDED_TEMPLATE_PATH = "templates/two.template"  # sorts between one and three

    def _make_regeneration_fixture(
        self, directory: str, *, include_unrecorded_additions: bool = False
    ) -> tuple[Path, str, dict]:
        """Build an isolated one-commit repo and a baseline that records it.

        By default the tree contains exactly the recorded paths, so the
        baseline is clean at the anchor — the shape removal tests need,
        since `regeneration_plan` unconditionally refuses any unrecorded
        `.claude`/tracked path unless `expected_added` is also given.
        `include_unrecorded_additions=True` adds the two paths this
        fixture also carries but keeps out of the baseline, for tests that
        exercise the addition side.
        """
        root = Path(directory) / "repository"
        root.mkdir()
        self.git(root, "init", "-q")
        self.git(root, "config", "user.name", "Kinglet Test")
        self.git(root, "config", "user.email", "kinglet@example.invalid")

        all_paths = list(self._RECORDED_AGENT_PATHS) + list(self._RECORDED_TEMPLATE_PATHS)
        if include_unrecorded_additions:
            all_paths += [self._UNRECORDED_AGENT_PATH, self._UNRECORDED_TEMPLATE_PATH]
        for path in all_paths:
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(f"fixture content for {path}\n", encoding="utf-8")

        self.git(root, "add", ".")
        self.git(root, "commit", "-q", "-m", "fixture tree")
        anchor = self.git(root, "rev-parse", "HEAD")

        def record(path: str) -> dict:
            return {
                "path": path,
                "sha256": hashlib.sha256((root / path).read_bytes()).hexdigest(),
                "git_mode": "100644",
            }

        agent_records = sorted(
            (record(path) for path in self._RECORDED_AGENT_PATHS),
            key=lambda item: item["path"],
        )
        template_records = sorted(
            (record(path) for path in self._RECORDED_TEMPLATE_PATHS),
            key=lambda item: item["path"],
        )

        baseline = {
            "full_claude_tree": {
                "expected_count": len(agent_records),
                "files": [dict(item) for item in agent_records],
            },
            "categories": {
                "agents": {
                    "expected_count": len(agent_records),
                    "files": [dict(item) for item in agent_records],
                },
                "code_templates": {
                    "expected_count": len(template_records),
                    "files": [dict(item) for item in template_records],
                },
            },
        }
        return root, anchor, baseline

    def _with_phantom_removal(self, baseline: dict) -> dict:
        """Add an unrecorded-at-anchor record for `_PHANTOM_AGENT_PATH`.

        Appended to both `full_claude_tree.files` and `categories.agents`,
        both lists re-sorted, both `expected_count` incremented — the same
        doubling `regeneration_plan`'s Global Constraints already state for
        drift, so one absent phantom path produces two removals.
        """
        baseline = copy.deepcopy(baseline)
        record = {"path": self._PHANTOM_AGENT_PATH, "sha256": "0" * 64, "git_mode": "100644"}

        full_tree = baseline["full_claude_tree"]
        full_tree["files"].append(record)
        full_tree["files"].sort(key=lambda item: item["path"])
        full_tree["expected_count"] += 1

        agents = baseline["categories"]["agents"]
        agents["files"].append(dict(record))
        agents["files"].sort(key=lambda item: item["path"])
        agents["expected_count"] += 1

        return baseline

    def test_removal_is_refused_when_no_expect_removed_flag_is_given(self) -> None:
        """The default must not change: a path-set change stays a hard refusal."""
        with tempfile.TemporaryDirectory() as directory:
            root, anchor, baseline = self._make_regeneration_fixture(directory)
            baseline = self._with_phantom_removal(baseline)
            plan = regeneration_plan(root, anchor, baseline)
            self.assertFalse(plan.approved)
            self.assertTrue(
                any(
                    f"path missing at anchor: {self._PHANTOM_AGENT_PATH}" in refusal
                    for refusal in plan.refusals
                ),
                plan.refusals,
            )
            self.assertEqual((), plan.removals)

    def test_removal_is_counted_when_expect_removed_matches(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root, anchor, baseline = self._make_regeneration_fixture(directory)
            baseline = self._with_phantom_removal(baseline)
            plan = regeneration_plan(root, anchor, baseline, expected_removed=2)
            self.assertTrue(plan.approved, plan.refusals)
            self.assertEqual(
                {self._PHANTOM_AGENT_PATH},
                {removal.path for removal in plan.removals},
            )
            self.assertEqual(
                {"full_claude_tree", "categories.agents"},
                {removal.structure for removal in plan.removals},
            )

    def test_removal_count_mismatch_still_refuses(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root, anchor, baseline = self._make_regeneration_fixture(directory)
            baseline = self._with_phantom_removal(baseline)
            plan = regeneration_plan(root, anchor, baseline, expected_removed=99)
            self.assertFalse(plan.approved)
            self.assertTrue(
                any("expected removed 99" in refusal for refusal in plan.refusals),
                plan.refusals,
            )

    def test_apply_regeneration_drops_the_record_and_decrements_expected_count(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root, anchor, baseline = self._make_regeneration_fixture(directory)
            baseline = self._with_phantom_removal(baseline)
            before_full = baseline["full_claude_tree"]["expected_count"]
            before_agents = baseline["categories"]["agents"]["expected_count"]
            plan = regeneration_plan(root, anchor, baseline, expected_removed=2)
            applied = apply_regeneration(baseline, plan)

            full_paths = [r["path"] for r in applied["full_claude_tree"]["files"]]
            agent_paths = [r["path"] for r in applied["categories"]["agents"]["files"]]
            self.assertNotIn(self._PHANTOM_AGENT_PATH, full_paths)
            self.assertNotIn(self._PHANTOM_AGENT_PATH, agent_paths)
            self.assertEqual(before_full - 1, applied["full_claude_tree"]["expected_count"])
            self.assertEqual(
                before_agents - 1, applied["categories"]["agents"]["expected_count"]
            )
            self.assertEqual(sorted(full_paths), full_paths)
            self.assertEqual(sorted(agent_paths), agent_paths)

    def test_addition_is_refused_when_no_expect_added_flag_is_given(self) -> None:
        """Covers both the `.claude` and non-`.claude` default refusal strings."""
        with tempfile.TemporaryDirectory() as directory:
            root, anchor, baseline = self._make_regeneration_fixture(directory, include_unrecorded_additions=True)
            plan = regeneration_plan(root, anchor, baseline)
            self.assertFalse(plan.approved)
            self.assertIn(
                f"unrecorded .claude path at anchor: {self._UNRECORDED_AGENT_PATH}",
                plan.refusals,
            )
            self.assertIn(
                f"unrecorded path at anchor: {self._UNRECORDED_TEMPLATE_PATH}",
                plan.refusals,
            )
            self.assertEqual((), plan.additions)

    def test_addition_is_counted_when_expect_added_matches(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root, anchor, baseline = self._make_regeneration_fixture(directory, include_unrecorded_additions=True)
            plan = regeneration_plan(root, anchor, baseline, expected_added=3)
            self.assertTrue(plan.approved, plan.refusals)
            self.assertEqual(
                {self._UNRECORDED_AGENT_PATH, self._UNRECORDED_TEMPLATE_PATH},
                {addition.path for addition in plan.additions},
            )
            self.assertEqual(
                {
                    ("full_claude_tree", self._UNRECORDED_AGENT_PATH),
                    ("categories.agents", self._UNRECORDED_AGENT_PATH),
                    ("categories.code_templates", self._UNRECORDED_TEMPLATE_PATH),
                },
                {(addition.structure, addition.path) for addition in plan.additions},
            )

    def test_addition_count_mismatch_still_refuses(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root, anchor, baseline = self._make_regeneration_fixture(directory, include_unrecorded_additions=True)
            plan = regeneration_plan(root, anchor, baseline, expected_added=99)
            self.assertFalse(plan.approved)
            self.assertTrue(
                any("expected added 99" in refusal for refusal in plan.refusals),
                plan.refusals,
            )

    def test_addition_scan_covers_tracked_paths_outside_claude(self) -> None:
        """Important-2: a new templates/ (code_templates) path must be seen."""
        with tempfile.TemporaryDirectory() as directory:
            root, anchor, baseline = self._make_regeneration_fixture(directory, include_unrecorded_additions=True)
            plan = regeneration_plan(root, anchor, baseline, expected_added=3)
            self.assertTrue(plan.approved, plan.refusals)
            template_additions = [
                addition
                for addition in plan.additions
                if addition.path == self._UNRECORDED_TEMPLATE_PATH
            ]
            self.assertEqual(1, len(template_additions))
            self.assertEqual("categories.code_templates", template_additions[0].structure)

    def test_apply_regeneration_inserts_the_record_and_increments_expected_count(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root, anchor, baseline = self._make_regeneration_fixture(directory, include_unrecorded_additions=True)
            before_full = baseline["full_claude_tree"]["expected_count"]
            before_agents = baseline["categories"]["agents"]["expected_count"]
            before_templates = baseline["categories"]["code_templates"]["expected_count"]
            plan = regeneration_plan(root, anchor, baseline, expected_added=3)
            applied = apply_regeneration(baseline, plan)

            full_paths = [r["path"] for r in applied["full_claude_tree"]["files"]]
            agent_paths = [r["path"] for r in applied["categories"]["agents"]["files"]]
            template_paths = [
                r["path"] for r in applied["categories"]["code_templates"]["files"]
            ]

            self.assertIn(self._UNRECORDED_AGENT_PATH, full_paths)
            self.assertIn(self._UNRECORDED_AGENT_PATH, agent_paths)
            self.assertIn(self._UNRECORDED_TEMPLATE_PATH, template_paths)
            self.assertNotIn(self._UNRECORDED_TEMPLATE_PATH, full_paths)

            self.assertEqual(before_full + 1, applied["full_claude_tree"]["expected_count"])
            self.assertEqual(
                before_agents + 1, applied["categories"]["agents"]["expected_count"]
            )
            self.assertEqual(
                before_templates + 1,
                applied["categories"]["code_templates"]["expected_count"],
            )

            self.assertEqual(sorted(full_paths), full_paths)
            self.assertEqual(sorted(agent_paths), agent_paths)
            self.assertEqual(sorted(template_paths), template_paths)
            # the unrecorded agent path sorts strictly between the two
            # already-recorded ones — this proves sorted-position insertion,
            # not append-at-end.
            self.assertEqual(
                list(self._RECORDED_AGENT_PATHS[:1])
                + [self._UNRECORDED_AGENT_PATH]
                + list(self._RECORDED_AGENT_PATHS[1:]),
                agent_paths,
            )

    def test_inventory_counts_match_the_expected_counts_constant(self) -> None:
        categories = self.baseline["categories"]
        self.assertEqual(set(EXPECTED_COUNTS), set(categories))
        for category, expected_count in EXPECTED_COUNTS.items():
            with self.subTest(category=category):
                records = categories[category]["files"]
                paths = [record["path"] for record in records]
                self.assertEqual(expected_count, categories[category]["expected_count"])
                self.assertEqual(expected_count, len(records))
                self.assertEqual(sorted(paths), paths)
                self.assertEqual(len(paths), len(set(paths)))

    def test_tracked_legacy_paths_and_sha256_match_exactly(self) -> None:
        tracked = tracked_paths()
        modes = tracked_modes()
        for category, expected_count in EXPECTED_COUNTS.items():
            with self.subTest(category=category):
                records = self.baseline["categories"][category]["files"]
                expected_paths = [record["path"] for record in records]
                actual_paths = category_paths(category, tracked)
                self.assertEqual(expected_count, len(actual_paths))
                self.assertEqual(expected_paths, actual_paths)

            for record in records:
                path = REPOSITORY_ROOT / record["path"]
                with self.subTest(category=category, path=record["path"]):
                    self.assertTrue(path.is_file(), f"missing inventory path: {record['path']}")
                    actual_sha256 = hashlib.sha256(path.read_bytes()).hexdigest()
                    self.assertEqual(record["sha256"], actual_sha256)
                    self.assertEqual(record["git_mode"], modes.get(record["path"]))

    def test_source_commit_is_ancestor_and_matches_every_baseline_record(self) -> None:
        records = list(self.baseline["full_claude_tree"]["files"])
        for category in EXPECTED_COUNTS:
            records.extend(self.baseline["categories"][category]["files"])

        self.assertEqual(
            [],
            source_commit_errors(
                REPOSITORY_ROOT,
                self.baseline.get("source_commit"),
                records,
            ),
        )

    def git(self, root: Path, *arguments: str) -> str:
        completed = subprocess.run(
            ["git", *arguments],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        )
        return completed.stdout.strip()

    def make_git_fixture(
        self,
        directory: str,
    ) -> tuple[Path, str, str, dict[str, str]]:
        root = Path(directory) / "repository"
        root.mkdir()
        self.git(root, "init", "-q")
        self.git(root, "config", "user.name", "Kinglet Test")
        self.git(root, "config", "user.email", "kinglet@example.invalid")
        self.git(root, "commit", "--allow-empty", "-q", "-m", "base")
        base = self.git(root, "rev-parse", "HEAD")
        payload = root / "payload.txt"
        payload.write_bytes(b"anchored payload\n")
        self.git(root, "add", "payload.txt")
        self.git(root, "commit", "-q", "-m", "anchor")
        anchor = self.git(root, "rev-parse", "HEAD")
        record = {
            "path": "payload.txt",
            "sha256": hashlib.sha256(payload.read_bytes()).hexdigest(),
            "git_mode": "100644",
        }
        return root, base, anchor, record

    def test_source_commit_checks_reject_invalid_anchor_states(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root, base, anchor, record = self.make_git_fixture(directory)

            for moving_reference in ("HEAD", anchor[:12]):
                with self.subTest(moving_reference=moving_reference):
                    self.assertEqual(
                        [
                            "source_commit must be a full lowercase Git object ID: "
                            f"{moving_reference}"
                        ],
                        source_commit_errors(root, moving_reference, [record]),
                    )

            nonexistent = "0" * 40
            self.assertEqual(
                [f"source_commit is not a Git commit: {nonexistent}"],
                source_commit_errors(root, nonexistent, [record]),
            )

            inconsistent = dict(record)
            inconsistent["sha256"] = "f" * 64
            inconsistent["git_mode"] = "100755"
            self.assertEqual(
                [
                    "source_commit sha256 mismatch: payload.txt",
                    "source_commit git mode mismatch: payload.txt "
                    "(expected 100755, got 100644)",
                ],
                source_commit_errors(root, anchor, [inconsistent]),
            )

            missing = dict(record, path="missing.txt")
            self.assertEqual(
                ["source_commit missing path: missing.txt"],
                source_commit_errors(root, anchor, [missing]),
            )

            self.git(root, "checkout", "-q", "--detach", base)
            (root / "current.txt").write_text("current branch\n", encoding="utf-8")
            self.git(root, "add", "current.txt")
            self.git(root, "commit", "-q", "-m", "current")
            self.assertEqual(
                [f"source_commit is not an ancestor of HEAD: {anchor}"],
                source_commit_errors(root, anchor, [record]),
            )

    def test_policy_hooks_remain_executable_in_git_and_checkout(self) -> None:
        modes = tracked_modes()
        hooks = self.baseline["categories"]["hooks"]["files"]
        for record in hooks:
            with self.subTest(path=record["path"]):
                self.assertEqual("100755", record["git_mode"])
                self.assertEqual(record["git_mode"], modes.get(record["path"]))
                self.assertTrue(
                    os.access(REPOSITORY_ROOT / record["path"], os.X_OK),
                    f"hook is not executable in checkout: {record['path']}",
                )

    def test_full_claude_tree_baseline_covers_every_tracked_claude_file(self) -> None:
        full_tree = self.baseline.get("full_claude_tree")
        self.assertIsNotNone(
            full_tree,
            "baseline must record the complete tracked .claude tree",
        )
        if full_tree is None:
            return

        records = full_tree["files"]
        expected_paths = [record["path"] for record in records]
        actual_paths = [
            path for path in tracked_paths() if path.startswith(".claude/")
        ]
        self.assertEqual(FULL_CLAUDE_TREE_COUNT, full_tree["expected_count"])
        self.assertEqual(FULL_CLAUDE_TREE_COUNT, len(records))
        self.assertEqual(expected_paths, sorted(expected_paths))
        self.assertEqual(FULL_CLAUDE_TREE_COUNT, len(set(expected_paths)))
        self.assertTrue(OMITTED_FROM_SEVEN_CATEGORIES.issubset(expected_paths))
        self.assertEqual(
            [],
            full_tree_errors(
                REPOSITORY_ROOT,
                actual_paths,
                tracked_modes(),
                records,
            ),
        )

        for record in records:
            with self.subTest(path=record["path"], mode=record["git_mode"]):
                is_executable = os.access(
                    REPOSITORY_ROOT / record["path"],
                    os.X_OK,
                )
                self.assertEqual(record["git_mode"] == "100755", is_executable)

    def test_full_tree_enforcement_rejects_settings_json_byte_drift(self) -> None:
        relative_path = ".claude/settings.json"
        source = REPOSITORY_ROOT / relative_path
        original = source.read_bytes()
        baseline_record = {
            "path": relative_path,
            "sha256": hashlib.sha256(original).hexdigest(),
            "git_mode": "100644",
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / relative_path
            target.parent.mkdir(parents=True)
            target.write_bytes(original + b"\n")
            errors = full_tree_errors(
                root,
                [relative_path],
                {relative_path: "100644"},
                [baseline_record],
            )

        self.assertEqual(
            [f"sha256 drift: {relative_path}"],
            errors,
        )

    def test_full_tree_enforcement_rejects_new_uncategorized_claude_file(self) -> None:
        relative_path = ".claude/settings.json"
        addition = ".claude/uncategorized-review-fixture.txt"
        original = (REPOSITORY_ROOT / relative_path).read_bytes()
        baseline_record = {
            "path": relative_path,
            "sha256": hashlib.sha256(original).hexdigest(),
            "git_mode": "100644",
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / relative_path
            target.parent.mkdir(parents=True)
            target.write_bytes(original)
            added = root / addition
            added.write_text("new legacy payload\n", encoding="utf-8")
            errors = full_tree_errors(
                root,
                [addition, relative_path],
                {addition: "100644", relative_path: "100644"},
                [baseline_record],
            )

        self.assertEqual([f"unexpected full-tree path: {addition}"], errors)

    def test_ci_runs_foundation_gates_on_ubuntu_and_python_suite_on_macos(self) -> None:
        workflow = (REPOSITORY_ROOT / ".github/workflows/ci.yml").read_text(
            encoding="utf-8"
        )
        ubuntu, macos = workflow.split("\n  macos:", 1)
        repository_tests = "run: bash tests/run-tests.sh"
        kinglet_tests = "run: bash tests/test-kinglet-build.sh"
        script_shellcheck = (
            "run: shellcheck --severity=warning -x install.sh uninstall.sh "
            "scripts/*.sh tests/*.sh tests/fixtures/*.sh"
        )
        validate = "run: python3 -m tools.kinglet_build validate"
        check = "run: python3 -m tools.kinglet_build build --all --check"

        self.assertEqual(2, workflow.count("fetch-depth: 0"))
        self.assertEqual(2, workflow.count(kinglet_tests))
        self.assertIn(script_shellcheck, ubuntu)
        self.assertIn(repository_tests, ubuntu)
        self.assertIn(kinglet_tests, ubuntu)
        self.assertIn(validate, ubuntu)
        self.assertIn(check, ubuntu)
        self.assertLess(ubuntu.index(repository_tests), ubuntu.index(kinglet_tests))
        self.assertLess(ubuntu.index(kinglet_tests), ubuntu.index(validate))
        self.assertLess(ubuntu.index(validate), ubuntu.index(check))

        self.assertIn(repository_tests, macos)
        self.assertIn(kinglet_tests, macos)
        self.assertLess(macos.index(repository_tests), macos.index(kinglet_tests))


if __name__ == "__main__":
    unittest.main()
