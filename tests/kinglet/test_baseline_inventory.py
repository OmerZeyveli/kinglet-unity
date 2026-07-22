import hashlib
import json
import os
from pathlib import Path
import subprocess
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
BASELINE_PATH = REPOSITORY_ROOT / "migration" / "baseline-inventory.json"
EXPECTED_COUNTS = {
    "agents": 28,
    "commands": 36,
    "skills": 39,
    "hooks": 26,
    "rules": 6,
    "claude_templates": 5,
    "code_templates": 10,
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


def category_paths(category: str, paths: list[str]) -> list[str]:
    if category == "agents":
        selected = [path for path in paths if path.startswith(".claude/agents/")]
    elif category == "commands":
        selected = [path for path in paths if path.startswith(".claude/commands/")]
    elif category == "skills":
        selected = [
            path
            for path in paths
            if path.startswith(".claude/skills/") and path.endswith("/SKILL.md")
        ]
    elif category == "hooks":
        selected = [
            path
            for path in paths
            if path.startswith(".claude/hooks/")
            and path != ".claude/hooks/_lib.sh"
        ]
    elif category == "rules":
        selected = [path for path in paths if path.startswith(".claude/rules/")]
    elif category == "claude_templates":
        selected = [
            path
            for path in paths
            if path.startswith(".claude/templates/") and path.endswith(".md")
        ]
    elif category == "code_templates":
        selected = [path for path in paths if path.startswith("templates/")]
    else:
        raise AssertionError(f"unknown inventory category: {category}")
    return sorted(selected)


class BaselineInventoryTests(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls) -> None:
        cls.baseline = json.loads(BASELINE_PATH.read_text(encoding="utf-8"))

    def test_inventory_counts_are_exact_28_36_39_26_6_5_10(self) -> None:
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

    def test_active_legacy_product_positioning_matches_grandfathered_baseline(self) -> None:
        policy = self.baseline["legacy_product_positioning"]
        term = policy["term"]
        historical_paths = set(policy["historical_exact_paths"])
        historical_prefixes = tuple(policy["historical_path_prefixes"])
        test_prefix = policy["legacy_marker_test_path_prefix"]
        legacy_marker = policy["legacy_marker"]
        occurrences = []

        for relative_path in tracked_paths():
            if relative_path in historical_paths:
                continue
            if relative_path.startswith(historical_prefixes):
                continue
            raw = (REPOSITORY_ROOT / relative_path).read_bytes()
            if b"\0" in raw:
                continue
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                continue
            for line in text.splitlines():
                count = line.count(term)
                if not count:
                    continue
                if relative_path.startswith(test_prefix) and legacy_marker in line:
                    continue
                occurrences.extend(
                    {"path": relative_path, "text": line} for _ in range(count)
                )

        occurrences.sort(key=lambda item: (item["path"], item["text"]))
        expected = policy["grandfathered_active_occurrences"]
        self.assertEqual(expected, occurrences)

    def test_ci_runs_foundation_gates_on_ubuntu_and_python_suite_on_macos(self) -> None:
        workflow = (REPOSITORY_ROOT / ".github/workflows/ci.yml").read_text(
            encoding="utf-8"
        )
        ubuntu, macos = workflow.split("\n  macos:", 1)
        repository_tests = "run: bash tests/run-tests.sh"
        kinglet_tests = "run: bash tests/test-kinglet-build.sh"
        validate = "run: python3 -m tools.kinglet_build validate"
        check = "run: python3 -m tools.kinglet_build build --all --check"

        self.assertEqual(2, workflow.count(kinglet_tests))
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
