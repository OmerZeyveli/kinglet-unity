import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
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


def is_legacy_marker_occurrence(
    line: str,
    start: int,
    marker_tokens: tuple[str, ...],
) -> bool:
    for token in marker_tokens:
        if not line.startswith(token, start):
            continue
        end = start + len(token)
        if end == len(line):
            return True
        boundary = line[end]
        if boundary.isspace() or boundary in "\"'`/\\<>()[]{};,":
            return True
        if line.startswith("-->", end):
            return True
    return False


def identity_occurrences(
    repository_root: Path,
    paths: list[str],
    policy: dict,
) -> list[dict[str, str]]:
    term = policy["term"]
    historical_paths = set(policy["historical_exact_paths"])
    historical_prefixes = tuple(policy["historical_path_prefixes"])
    test_prefix = policy["legacy_marker_test_path_prefix"]
    marker_tokens = tuple(policy["legacy_marker_tokens"])
    occurrences = []

    for relative_path in paths:
        if relative_path in historical_paths:
            continue
        if relative_path.startswith(historical_prefixes):
            continue
        raw = (repository_root / relative_path).read_bytes()
        if b"\0" in raw:
            continue
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            continue
        for line in text.splitlines():
            start = 0
            while True:
                occurrence = line.find(term, start)
                if occurrence < 0:
                    break
                exempt_marker = relative_path.startswith(
                    test_prefix
                ) and is_legacy_marker_occurrence(
                    line,
                    occurrence,
                    marker_tokens,
                )
                if not exempt_marker:
                    occurrences.append({"path": relative_path, "text": line})
                start = occurrence + len(term)

    occurrences.sort(key=lambda item: (item["path"], item["text"]))
    return occurrences


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

    def test_full_claude_tree_baseline_covers_all_147_tracked_files(self) -> None:
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
        self.assertEqual(147, full_tree["expected_count"])
        self.assertEqual(147, len(records))
        self.assertEqual(expected_paths, sorted(expected_paths))
        self.assertEqual(147, len(set(expected_paths)))
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

    def test_active_legacy_product_positioning_matches_grandfathered_baseline(self) -> None:
        policy = self.baseline["legacy_product_positioning"]
        occurrences = identity_occurrences(
            REPOSITORY_ROOT,
            tracked_paths(),
            policy,
        )
        expected = policy["grandfathered_active_occurrences"]
        self.assertEqual(expected, occurrences)

    def scan_identity_fixture(self, files: dict[str, str]) -> list[dict[str, str]]:
        term = self.baseline["legacy_product_positioning"]["term"]
        policy = {
            "term": term,
            "historical_exact_paths": ["CREDITS.md"],
            "historical_path_prefixes": ["migration/fixtures/"],
            "legacy_marker_test_path_prefix": "tests/",
            "legacy_marker_tokens": [
                f"{term}:generated:begin",
                f"{term}:generated:end",
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for path, content in files.items():
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(content, encoding="utf-8")
            return identity_occurrences(root, sorted(files), policy)

    def test_legacy_marker_exception_is_per_occurrence_for_begin_and_end(self) -> None:
        term = self.baseline["legacy_product_positioning"]["term"]
        for marker_name in ("begin", "end"):
            with self.subTest(marker=marker_name):
                line = (
                    f"<!-- {term}:generated:{marker_name} --> "
                    f"active product position: {term}"
                )
                occurrences = self.scan_identity_fixture(
                    {"tests/test-legacy-marker.py": f"{line}\n"}
                )
                self.assertEqual(
                    [{"path": "tests/test-legacy-marker.py", "text": line}],
                    occurrences,
                )

    def test_duplicate_active_occurrence_is_detected(self) -> None:
        term = self.baseline["legacy_product_positioning"]["term"]
        path = "docs/active.md"
        line = f"active product: {term}"
        expected = [{"path": path, "text": line}]
        actual = self.scan_identity_fixture({path: f"{line}\n{line}\n"})
        self.assertEqual(2, len(actual))
        self.assertNotEqual(expected, actual)

    def test_active_occurrence_path_move_is_detected(self) -> None:
        term = self.baseline["legacy_product_positioning"]["term"]
        line = f"active product: {term}"
        expected = [{"path": "docs/active.md", "text": line}]
        actual = self.scan_identity_fixture({"docs/moved.md": f"{line}\n"})
        self.assertNotEqual(expected, actual)

    def test_active_occurrence_text_context_change_is_detected(self) -> None:
        term = self.baseline["legacy_product_positioning"]["term"]
        path = "docs/active.md"
        expected = [{"path": path, "text": f"active product: {term}"}]
        actual = self.scan_identity_fixture(
            {path: f"changed active product: {term}\n"}
        )
        self.assertNotEqual(expected, actual)

    def test_historical_exceptions_are_exact_and_prefix_bounded(self) -> None:
        term = self.baseline["legacy_product_positioning"]["term"]
        line = f"historical product: {term}"
        occurrences = self.scan_identity_fixture(
            {
                "CREDITS.md": f"{line}\n",
                "docs/CREDITS.md": f"{line}\n",
                "migration/fixtures/old.txt": f"{line}\n",
                "migration/fixtures-archive/old.txt": f"{line}\n",
            }
        )
        self.assertEqual(
            [
                {"path": "docs/CREDITS.md", "text": line},
                {"path": "migration/fixtures-archive/old.txt", "text": line},
            ],
            occurrences,
        )

    def test_marker_exception_is_test_only_and_exact_token_bounded(self) -> None:
        term = self.baseline["legacy_product_positioning"]["term"]
        begin = f"<!-- {term}:generated:begin -->"
        end = f"<!-- {term}:generated:end -->"
        near_begin = f"<!-- {term}:generated:beginning -->"
        near_end = f"<!-- {term}:generated:endnote -->"
        suffixed_begin = f"<!-- {term}:generated:begin:extra -->"
        suffixed_end = f"<!-- {term}:generated:end.more -->"
        occurrences = self.scan_identity_fixture(
            {
                "tests/test-markers.py": (
                    f"{begin}\n{end}\n{near_begin}\n{near_end}\n"
                    f"{suffixed_begin}\n{suffixed_end}\n"
                ),
                "docs/not-a-test.md": f"{begin}\n{end}\n",
            }
        )
        self.assertEqual(
            [
                {"path": "docs/not-a-test.md", "text": begin},
                {"path": "docs/not-a-test.md", "text": end},
                {"path": "tests/test-markers.py", "text": suffixed_begin},
                {"path": "tests/test-markers.py", "text": near_begin},
                {"path": "tests/test-markers.py", "text": suffixed_end},
                {"path": "tests/test-markers.py", "text": near_end},
            ],
            occurrences,
        )

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
