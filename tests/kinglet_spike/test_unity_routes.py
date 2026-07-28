"""test_unity_routes.py -- The filesystem and same-project-headless routes.

Every guard here is EXECUTED, not asserted as source text. The refusal paths
run through the real `assert_headless_safe` with a fabricated process table,
the real `verify_project_editor` with a fabricated `-version` stdout, and the
real `WorkspaceLease` on a real directory; only the Unity process itself is a
double, and its behaviour is scripted from artifacts CAPTURED FROM REAL UNITY
runs on this host:

  fixtures/unity_results_passed.xml     exit 0, `Passed 1/1/0/0`
  fixtures/unity_results_failed.xml     exit 2, `Failed(Child)`, failed=1
  fixtures/unity_compile_error_log.txt  exit 1, no results file at all

Those three files are the measured exit-code disjointness (0/1/2) as Unity
actually produced it, machine paths scrubbed. Driving the parsers through them
is deliberate: Task 3's newline bug survived a review round precisely because
its fixture bypassed the real reader.
"""
from __future__ import annotations

import json
import os
import subprocess
import unittest
from pathlib import Path
from unittest import mock

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.unity import routes
from tools.kinglet_spike.unity.lease import WorkspaceLease, read_lease
from tools.kinglet_spike.unity.model import PROJECT_ID, RECEIPT_SCHEMA
from tools.kinglet_spike.unity.process import CleanupResult
from tools.kinglet_spike.unity.receipt import (
    unity_receipt_from_dict,
    validate_unity_receipt,
)

_REPO = Path(__file__).resolve().parents[2]
_FIXTURES = Path(__file__).resolve().parent / "fixtures"
_CONTRACT = _REPO / "spikes/platform/unity/contracts/routes-v1.json"

PASSED_XML = (_FIXTURES / "unity_results_passed.xml").read_text(encoding="utf-8")
FAILED_XML = (_FIXTURES / "unity_results_failed.xml").read_text(encoding="utf-8")
COMPILE_LOG = (_FIXTURES / "unity_compile_error_log.txt").read_text(encoding="utf-8")

EDITOR_VERSION = "6000.3.18f1"
EDITOR_REVISION = "5ebeb53e4c07"


# ---------------------------------------------------------------------------
# Synthetic project + doubles
# ---------------------------------------------------------------------------

def make_project(root: Path, *, version: str = EDITOR_VERSION, marker: str = PROJECT_ID) -> Path:
    """A minimal project with exactly REQUIRED_PROJECT_FILES present."""
    project = Path(root)
    (project / "ProjectSettings").mkdir(parents=True, exist_ok=True)
    (project / "ProjectSettings" / "ProjectVersion.txt").write_text(
        # Two lines, as Unity really writes -- a one-line file has hidden a
        # real bug in this repo before.
        f"m_EditorVersion: {version}\n"
        f"m_EditorVersionWithRevision: {version} ({EDITOR_REVISION})\n",
        encoding="utf-8",
    )
    (project / "Packages").mkdir(parents=True, exist_ok=True)
    (project / "Packages" / "manifest.json").write_text(
        json.dumps({"dependencies": {"com.unity.test-framework": "1.5.1"}}) + "\n",
        encoding="utf-8",
    )
    editor_dir = project / "Assets" / "KingletSpike" / "Editor"
    tests_dir = project / "Assets" / "KingletSpike" / "Tests" / "Editor"
    editor_dir.mkdir(parents=True, exist_ok=True)
    tests_dir.mkdir(parents=True, exist_ok=True)
    (editor_dir / "KingletSpike.Editor.asmdef").write_text('{"name":"KingletSpike.Editor"}\n', encoding="utf-8")
    (editor_dir / "KingletSpikeProbe.cs").write_text(
        "namespace KingletSpike {\n"
        "  public static class Probe {\n"
        f'    public const string ProjectId = "{marker}";\n'
        "  }\n}\n",
        encoding="utf-8",
    )
    (tests_dir / "KingletSpike.Tests.asmdef").write_text('{"name":"KingletSpike.Tests"}\n', encoding="utf-8")
    (tests_dir / "KingletSpikeTests.cs").write_text("using NUnit.Framework;\n", encoding="utf-8")
    return project


def version_stdout(version: str = EDITOR_VERSION):
    return lambda editor: f"{version}\n"


def empty_process_table():
    return ()


class FakeUnity:
    """A scripted stand-in for ManagedProcess that writes the artifacts a real run writes."""

    def __init__(
        self,
        *,
        exit_code: int | None = 0,
        results_text: str | None = PASSED_XML,
        log_text: str = "",
        stdout_text: str = "",
        survivors: tuple[int, ...] = (),
        pid: int = 4242,
        pgid: int = 4242,
        recorder: list | None = None,
        leaves_lockfile: Path | None = None,
    ) -> None:
        self.leaves_lockfile = leaves_lockfile
        self.exit_code = exit_code
        self.results_text = results_text
        self.log_text = log_text
        self.stdout_text = stdout_text
        self.survivors = survivors
        self.pid = pid
        self.pgid = pgid
        self.recorder = recorder if recorder is not None else []
        self.argv: list[str] | None = None
        self.cancelled = False

    def factory(self, argv, *, cwd, env, stdout_path, stderr_path, **kwargs):
        self.argv = list(argv)
        self.cwd = cwd
        self.env = env
        self.recorder.append("start")
        # Write exactly what the argv told Unity to write, so the route reads
        # its evidence from the paths it actually asked for.
        results_path = Path(argv[argv.index("-testResults") + 1])
        log_path = Path(argv[argv.index("-logFile") + 1])
        if self.results_text is not None:
            results_path.write_text(self.results_text, encoding="utf-8")
        if self.log_text:
            log_path.write_text(self.log_text, encoding="utf-8")
        Path(stdout_path).write_text(self.stdout_text, encoding="utf-8")
        Path(stderr_path).write_text("", encoding="utf-8")
        if self.leaves_lockfile is not None:
            # Unity takes Temp/UnityLockfile within ~2s of launch and removes
            # it on CLEAN exit. Leaving it behind is the crash/kill shape.
            lock = routes.unity_lockfile_path(self.leaves_lockfile)
            lock.parent.mkdir(parents=True, exist_ok=True)
            lock.write_text("", encoding="utf-8")
        return self

    def wait(self, timeout_seconds):
        self.recorder.append("wait")
        return self.exit_code

    def cancel(self, deadline_seconds):
        self.recorder.append("cancel")
        self.cancelled = True
        return CleanupResult(
            signalled=False, escalated=False,
            survivors=self.survivors, exit_code=self.exit_code,
        )


UNITY_ARGV0 = "/opt/Unity/Hub/Editor/6000.3.18f1/Editor/Unity"


def owning_table(project: Path):
    """A process table in which a live Unity Editor owns `project` (exact argv)."""
    return lambda: (
        (99001, (UNITY_ARGV0, "-projectPath", str(Path(project).resolve()))),
    )


class _TempCase(unittest.TestCase):
    def setUp(self):
        import tempfile
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)
        self.project = make_project(self.root / "project")
        self.raw = self.root / "raw"
        self.editor = self.root / "Unity"
        self.editor.write_text("#!/bin/sh\n", encoding="utf-8")

    def lease_dir(self):
        # A HOST-WIDE lease directory, deliberately not derived from raw_dir --
        # see routes.default_lease_dir(). Tests point it at a temp dir so the
        # real one is never touched.
        return self.root / "leases"

    def lease_files(self):
        directory = self.lease_dir()
        if not directory.is_dir():
            return []
        return sorted(p.name for p in directory.glob("*.lease.json"))

    def run_headless(self, fake: FakeUnity, *, raw_dir_override=None, **overrides):
        kwargs = dict(
            process_table_provider=empty_process_table,
            windows=False,
            run_version_flag=version_stdout(),
            process_factory=fake.factory,
            env={"PATH": "/usr/bin"},
            lease_dir=self.lease_dir(),
        )
        kwargs.update(overrides)
        return routes.run_same_project_headless(
            self.editor, self.project,
            self.raw if raw_dir_override is None else raw_dir_override,
            **kwargs
        )


# ---------------------------------------------------------------------------
# Contract binding
# ---------------------------------------------------------------------------

class ContractBindingTests(unittest.TestCase):
    """The timeouts are the frozen contract's, not numbers someone liked."""

    def setUp(self):
        self.contract = json.loads(_CONTRACT.read_text(encoding="utf-8"))

    def test_headless_timeout_is_the_sum_of_its_contract_phases(self):
        timings = self.contract["timings_seconds"]
        expected = sum(timings[phase] for phase in routes.HEADLESS_TIMEOUT_PHASES)
        self.assertEqual(float(expected), routes.HEADLESS_TIMEOUT_SECONDS)

    def test_headless_timeout_phases_all_exist_in_the_contract(self):
        timings = self.contract["timings_seconds"]
        for phase in routes.HEADLESS_TIMEOUT_PHASES:
            self.assertIn(phase, timings)

    def test_cancellation_deadline_is_the_contract_value(self):
        self.assertEqual(
            float(self.contract["timings_seconds"]["cancellation_cleanup"]),
            routes.CANCELLATION_DEADLINE_SECONDS,
        )

    def test_route_names_are_the_contract_names(self):
        self.assertIn(routes.FILESYSTEM_ROUTE, self.contract["routes"])
        self.assertIn(routes.SAME_PROJECT_HEADLESS_ROUTE, self.contract["executing_routes"])


# ---------------------------------------------------------------------------
# filesystem route
# ---------------------------------------------------------------------------

class FilesystemRouteTests(_TempCase):
    def test_reports_not_run_for_compile_and_tests(self):
        receipt = routes.run_filesystem(self.project, self.raw)
        self.assertEqual("not-run", receipt.compile.status)
        self.assertEqual("not-run", receipt.tests.status)
        self.assertEqual(0, receipt.compile.errors)

    def test_reads_the_version_the_project_declares(self):
        project = make_project(self.root / "other", version="6000.0.68f1")
        receipt = routes.run_filesystem(project, self.raw)
        self.assertEqual("6000.0.68f1", receipt.unity_version)

    def test_reads_the_project_marker_rather_than_assuming_it(self):
        receipt = routes.run_filesystem(self.project, self.raw)
        self.assertEqual(PROJECT_ID, receipt.project_id)

    def test_refuses_a_project_whose_marker_is_a_different_id(self):
        project = make_project(self.root / "wrong", marker="some-other-project")
        with self.assertRaises(EvidenceError) as caught:
            routes.run_filesystem(project, self.raw)
        self.assertEqual("E_UNITY_PROJECT_MARKER", caught.exception.code)

    def test_refuses_when_a_required_file_is_missing(self):
        for relative in routes.REQUIRED_PROJECT_FILES:
            with self.subTest(missing=relative):
                project = make_project(self.root / f"missing-{relative.count('/')}-{Path(relative).name}")
                (project / relative).unlink()
                with self.assertRaises(EvidenceError) as caught:
                    routes.run_filesystem(project, self.raw)
                self.assertIn(
                    caught.exception.code,
                    ("E_UNITY_PROJECT_INCOMPLETE", "E_UNITY_PROJECT_MARKER", "E_FIELD"),
                )

    def test_inventory_records_a_real_sha256_for_every_required_file(self):
        import hashlib
        routes.run_filesystem(self.project, self.raw)
        inventory = json.loads((self.raw / routes.FILESYSTEM_INVENTORY_NAME).read_text(encoding="utf-8"))
        recorded = {row["path"]: row for row in inventory["files"]}
        self.assertEqual(set(routes.REQUIRED_PROJECT_FILES), set(recorded))
        for relative, row in recorded.items():
            raw_bytes = (self.project / relative).read_bytes()
            self.assertEqual(hashlib.sha256(raw_bytes).hexdigest(), row["sha256"])
            self.assertEqual(len(raw_bytes), row["size"])

    def test_inventory_checksum_changes_when_the_file_changes(self):
        routes.run_filesystem(self.project, self.raw)
        before = json.loads((self.raw / routes.FILESYSTEM_INVENTORY_NAME).read_text(encoding="utf-8"))
        target = self.project / "Packages" / "manifest.json"
        target.write_text(target.read_text(encoding="utf-8") + "\n", encoding="utf-8")
        routes.run_filesystem(self.project, self.raw)
        after = json.loads((self.raw / routes.FILESYSTEM_INVENTORY_NAME).read_text(encoding="utf-8"))
        self.assertNotEqual(before["files"], after["files"])

    def test_launches_no_process_at_all(self):
        """The route's whole claim is 'I inspected bytes'. Prove it executably."""
        def explode(*args, **kwargs):
            raise AssertionError("filesystem route must not launch a process")

        with mock.patch.object(subprocess, "Popen", explode), \
             mock.patch.object(subprocess, "run", explode), \
             mock.patch.object(routes.ManagedProcess, "start", staticmethod(explode)), \
             mock.patch.object(os, "system", explode):
            receipt = routes.run_filesystem(self.project, self.raw)
        self.assertEqual(routes.FILESYSTEM_ROUTE, receipt.route)

    def test_takes_no_lease(self):
        routes.run_filesystem(self.project, self.raw)
        self.assertEqual([], self.lease_files())

    def test_receipt_is_clean_under_the_frozen_validator(self):
        receipt = routes.run_filesystem(self.project, self.raw)
        self.assertEqual((), validate_unity_receipt(receipt))

    def test_receipt_round_trips_through_the_strict_parser(self):
        receipt = routes.run_filesystem(self.project, self.raw)
        self.assertEqual(receipt, unity_receipt_from_dict(routes.receipt_to_dict(receipt)))

    def test_artifact_path_is_a_safe_relative_path(self):
        receipt = routes.run_filesystem(self.project, self.raw)
        self.assertEqual(1, len(receipt.artifacts))
        artifact = receipt.artifacts[0]
        self.assertFalse(Path(artifact).is_absolute())
        self.assertNotIn("..", Path(artifact).parts)
        self.assertTrue(artifact.startswith(routes.ARTIFACT_PREFIX + "/"))

    def test_never_claims_ready_or_collision_refusal(self):
        receipt = routes.run_filesystem(self.project, self.raw)
        self.assertFalse(receipt.ready)
        self.assertFalse(receipt.collision_refused)
        self.assertFalse(receipt.active_lease)
        self.assertEqual((), receipt.descendant_pids)

    def test_runs_against_the_real_pinned_fixture(self):
        """Not a synthetic project -- the committed Task 2 fixture itself."""
        receipt = routes.run_filesystem(
            _REPO / "spikes/platform/unity/fixture", self.raw
        )
        self.assertEqual(PROJECT_ID, receipt.project_id)
        self.assertEqual((), validate_unity_receipt(receipt))


# ---------------------------------------------------------------------------
# argv
# ---------------------------------------------------------------------------

class HeadlessArgvTests(unittest.TestCase):
    def build(self, project="/w/proj"):
        return routes._headless_argv(
            Path("/opt/Unity"), Path(project),
            Path("/raw/r.xml"), Path("/raw/r.log"),
        )

    def test_quit_is_absent(self):
        # MEASURED: with -quit, Unity exits 0 and writes no results.xml at all.
        self.assertNotIn("-quit", self.build())

    def test_project_path_is_its_own_argv_entry(self):
        argv = self.build()
        self.assertEqual("/w/proj", argv[argv.index("-projectPath") + 1])

    def test_a_project_path_containing_spaces_stays_one_entry(self):
        argv = self.build("/w/Kinglet - Copy")
        self.assertEqual("/w/Kinglet - Copy", argv[argv.index("-projectPath") + 1])

    def test_required_flags_present(self):
        argv = self.build()
        for flag in ("-batchmode", "-nographics", "-runTests", "-testPlatform"):
            self.assertIn(flag, argv)
        self.assertEqual("EditMode", argv[argv.index("-testPlatform") + 1])

    def test_results_and_log_are_separate_entries(self):
        argv = self.build()
        self.assertEqual("/raw/r.xml", argv[argv.index("-testResults") + 1])
        self.assertEqual("/raw/r.log", argv[argv.index("-logFile") + 1])

    def test_editor_is_argv0(self):
        self.assertEqual("/opt/Unity", self.build()[0])


class ArgvAbsolutenessTests(_TempCase):
    def test_every_path_in_the_launched_argv_is_absolute(self):
        """A relative -projectPath is re-resolved against cwd=<project>.

        Measured: it produced "Couldn't set project path to:
        <project>/<project>" and exit 1 on a real run.
        """
        os.chdir(self.root)
        self.addCleanup(os.chdir, _REPO)
        fake = FakeUnity()
        routes.run_same_project_headless(
            Path("Unity"), Path("project"), Path("raw"),
            process_table_provider=empty_process_table,
            windows=False,
            run_version_flag=version_stdout(),
            process_factory=fake.factory,
            env={"PATH": "/usr/bin"},
            lease_dir=self.lease_dir(),
        )
        argv = fake.argv
        for flag in ("-projectPath", "-testResults", "-logFile"):
            with self.subTest(flag=flag):
                self.assertTrue(Path(argv[argv.index(flag) + 1]).is_absolute())
        self.assertTrue(Path(argv[0]).is_absolute())


# ---------------------------------------------------------------------------
# Readers, driven through REAL captured Unity artifacts
# ---------------------------------------------------------------------------

class ResultsParserTests(unittest.TestCase):
    def test_parses_a_real_passing_results_file(self):
        summary = routes.parse_test_results(PASSED_XML)
        self.assertEqual("Passed", summary.result)
        self.assertEqual((1, 1, 0, 0, 0), (
            summary.total, summary.passed, summary.failed,
            summary.skipped, summary.inconclusive,
        ))

    def test_parses_a_real_failing_results_file(self):
        summary = routes.parse_test_results(FAILED_XML)
        self.assertEqual("Failed(Child)", summary.result)
        self.assertEqual(1, summary.failed)
        self.assertEqual(0, summary.passed)

    def test_real_passing_file_maps_to_a_pass(self):
        tests = routes._tests_from_summary(routes.parse_test_results(PASSED_XML))
        self.assertEqual(("pass", 1, 0, 0), (tests.status, tests.passed, tests.failed, tests.skipped))

    def test_real_failing_file_maps_to_a_fail(self):
        tests = routes._tests_from_summary(routes.parse_test_results(FAILED_XML))
        self.assertEqual(("fail", 1), (tests.status, tests.failed))

    def test_counts_that_do_not_add_up_are_malformed(self):
        broken = PASSED_XML.replace('total="1"', 'total="7"', 1)
        with self.assertRaises(EvidenceError) as caught:
            routes.parse_test_results(broken)
        self.assertEqual("E_UNITY_RESULTS_MALFORMED", caught.exception.code)

    def test_wrong_root_element_is_malformed(self):
        with self.assertRaises(EvidenceError) as caught:
            routes.parse_test_results("<test-results result='Passed'/>")
        self.assertEqual("E_UNITY_RESULTS_MALFORMED", caught.exception.code)

    def test_non_xml_is_malformed(self):
        with self.assertRaises(EvidenceError) as caught:
            routes.parse_test_results("not xml at all")
        self.assertEqual("E_UNITY_RESULTS_MALFORMED", caught.exception.code)

    def test_missing_count_attribute_is_malformed(self):
        broken = PASSED_XML.replace(' passed="1"', "", 1)
        with self.assertRaises(EvidenceError) as caught:
            routes.parse_test_results(broken)
        self.assertEqual("E_UNITY_RESULTS_MALFORMED", caught.exception.code)

    def test_non_integer_count_is_malformed(self):
        broken = PASSED_XML.replace('passed="1"', 'passed="many"', 1)
        with self.assertRaises(EvidenceError) as caught:
            routes.parse_test_results(broken)
        self.assertEqual("E_UNITY_RESULTS_MALFORMED", caught.exception.code)

    def test_a_run_that_only_skipped_is_unresolved_not_a_pass(self):
        summary = routes.ResultsSummary(
            result="Skipped", total=1, passed=0, failed=0, skipped=1, inconclusive=0
        )
        with self.assertRaises(EvidenceError) as caught:
            routes._tests_from_summary(summary)
        self.assertEqual("E_UNITY_RESULTS_UNRESOLVED", caught.exception.code)

    def test_a_passed_result_with_zero_passed_is_unresolved(self):
        summary = routes.ResultsSummary(
            result="Passed", total=0, passed=0, failed=0, skipped=0, inconclusive=0
        )
        with self.assertRaises(EvidenceError) as caught:
            routes._tests_from_summary(summary)
        self.assertEqual("E_UNITY_RESULTS_UNRESOLVED", caught.exception.code)

    def test_a_pass_with_a_skip_alongside_it_is_unresolved(self):
        summary = routes.ResultsSummary(
            result="Passed", total=2, passed=1, failed=0, skipped=1, inconclusive=0
        )
        with self.assertRaises(EvidenceError) as caught:
            routes._tests_from_summary(summary)
        self.assertEqual("E_UNITY_RESULTS_UNRESOLVED", caught.exception.code)


class CompileLogTests(unittest.TestCase):
    def test_repeated_diagnostics_from_a_real_log_count_once(self):
        # The captured log carries the SAME CS1002 line three times.
        self.assertEqual(3, COMPILE_LOG.count("error CS1002"))
        self.assertEqual(1, routes.count_compile_errors(COMPILE_LOG))

    def test_distinct_diagnostics_count_separately(self):
        text = (
            "Assets/A.cs(1,1): error CS1002: ; expected\n"
            "Assets/B.cs(2,2): error CS0103: name not found\n"
        )
        self.assertEqual(2, routes.count_compile_errors(text))

    def test_prose_mentioning_a_diagnostic_code_is_not_a_compile_error(self):
        """A passing run whose log echoes a test name must not read as a failure.

        A bare `error CS` substring search counted this as a compile error, and
        because a passing run ALSO has a results file, the route then raised
        E_UNITY_RESULTS_CONFLICT and refused a good run.
        """
        text = (
            "Running KingletSpike.Tests.Handles_error_CS1002_Gracefully\n"
            "  Expected: no error CS1002 in output\n"
            "Test run finished.\n"
        )
        self.assertEqual(0, routes.count_compile_errors(text))

    def test_an_assembly_level_diagnostic_with_no_file_position_still_counts(self):
        # Not every Unity diagnostic carries a (line,col) prefix.
        self.assertEqual(1, routes.count_compile_errors("error CS8034: no analyzer\n"))

    def test_a_prose_only_log_alongside_a_results_file_does_not_conflict(self):
        # The end-to-end consequence of the anchor, driven through _derive_outcome.
        compile_result, tests = routes._derive_outcome(
            exit_code=0, results_text=PASSED_XML,
            log_text="Ran Handles_error_CS1002_Gracefully\n",
        )
        self.assertEqual("pass", compile_result.status)
        self.assertEqual("pass", tests.status)

    def test_a_clean_log_reports_zero(self):
        self.assertEqual(0, routes.count_compile_errors("Refreshing native plugins\nExiting\n"))

    def test_abort_marker_is_found_in_the_real_captured_streams(self):
        self.assertTrue(routes.log_reports_compile_abort(COMPILE_LOG))

    def test_abort_marker_survives_unitys_two_line_split(self):
        # Measured: Unity writes the banner and the sentence on SEPARATE lines,
        # and writes them to stdout rather than into -logFile.
        self.assertIn("Aborting batchmode due to failure:\nScripts have compiler errors.", COMPILE_LOG)

    def test_a_clean_log_reports_no_abort(self):
        self.assertFalse(routes.log_reports_compile_abort("Exiting batchmode successfully now!\n"))


class DeriveOutcomeTests(unittest.TestCase):
    """The exit codes 0 / 1 / 2 are DISJOINT and are never collapsed."""

    def test_exit_zero_with_a_real_passing_results_file(self):
        compile_result, tests = routes._derive_outcome(
            exit_code=0, results_text=PASSED_XML, log_text="all good\n"
        )
        self.assertEqual(("pass", 0), (compile_result.status, compile_result.errors))
        self.assertEqual(("pass", 1), (tests.status, tests.passed))

    def test_exit_one_with_a_real_compile_error_log_and_no_results_file(self):
        compile_result, tests = routes._derive_outcome(
            exit_code=1, results_text=None, log_text=COMPILE_LOG
        )
        self.assertEqual(("fail", 1), (compile_result.status, compile_result.errors))
        self.assertEqual("not-run", tests.status)

    def test_exit_two_with_a_real_failing_results_file(self):
        compile_result, tests = routes._derive_outcome(
            exit_code=2, results_text=FAILED_XML, log_text=""
        )
        self.assertEqual("pass", compile_result.status)
        self.assertEqual(("fail", 1), (tests.status, tests.failed))

    def test_exit_zero_with_no_results_file_is_refused(self):
        """The measured `-quit` shape: exit 0 is NOT evidence tests ran."""
        with self.assertRaises(EvidenceError) as caught:
            routes._derive_outcome(
                exit_code=0, results_text=None,
                log_text="Batchmode quit successfully invoked - shutting down!\n",
            )
        self.assertEqual("E_UNITY_RESULTS_MISSING", caught.exception.code)

    def test_a_cancelled_run_with_no_results_file_is_refused(self):
        with self.assertRaises(EvidenceError) as caught:
            routes._derive_outcome(exit_code=None, results_text=None, log_text="")
        self.assertEqual("E_UNITY_RESULTS_MISSING", caught.exception.code)

    def test_compile_errors_alongside_a_results_file_is_a_conflict(self):
        # Physically impossible per the measured behaviour: exit 1 writes no
        # results file at all. Seeing both means an artifact is not what it says.
        with self.assertRaises(EvidenceError) as caught:
            routes._derive_outcome(exit_code=0, results_text=PASSED_XML, log_text=COMPILE_LOG)
        self.assertEqual("E_UNITY_RESULTS_CONFLICT", caught.exception.code)

    def test_a_passing_results_file_with_a_nonzero_exit_is_a_conflict(self):
        with self.assertRaises(EvidenceError) as caught:
            routes._derive_outcome(exit_code=2, results_text=PASSED_XML, log_text="")
        self.assertEqual("E_UNITY_EXIT_CONFLICT", caught.exception.code)

    def test_a_failing_results_file_with_exit_zero_is_a_conflict(self):
        with self.assertRaises(EvidenceError) as caught:
            routes._derive_outcome(exit_code=0, results_text=FAILED_XML, log_text="")
        self.assertEqual("E_UNITY_EXIT_CONFLICT", caught.exception.code)

    def test_compile_errors_with_exit_zero_is_a_conflict(self):
        with self.assertRaises(EvidenceError) as caught:
            routes._derive_outcome(exit_code=0, results_text=None, log_text=COMPILE_LOG)
        self.assertEqual("E_UNITY_EXIT_CONFLICT", caught.exception.code)

    def test_an_abort_with_no_countable_error_is_unresolved(self):
        with self.assertRaises(EvidenceError) as caught:
            routes._derive_outcome(
                exit_code=1, results_text=None,
                log_text="Scripts have compiler errors.\n",
            )
        self.assertEqual("E_UNITY_RESULTS_UNRESOLVED", caught.exception.code)

    def test_compile_fail_with_tests_pass_is_unconstructible(self):
        """The contract's impossible combination cannot come out of here."""
        for exit_code in (None, 0, 1, 2):
            for results in (None, PASSED_XML, FAILED_XML):
                for log in ("", COMPILE_LOG):
                    with self.subTest(exit_code=exit_code, results=bool(results), log=bool(log)):
                        try:
                            compile_result, tests = routes._derive_outcome(
                                exit_code=exit_code, results_text=results, log_text=log
                            )
                        except EvidenceError:
                            continue
                        self.assertFalse(
                            compile_result.status != "pass" and tests.status == "pass"
                        )


# ---------------------------------------------------------------------------
# Ordering, lease binding, cleanup
# ---------------------------------------------------------------------------

class CallOrderingTests(_TempCase):
    """The order is structural. This test executes it and pins the sequence."""

    def test_full_sequence(self):
        recorder: list[str] = []

        def table():
            recorder.append("assert_headless_safe")
            return ()

        def version(editor):
            recorder.append("verify_project_editor")
            return f"{EDITOR_VERSION}\n"

        real_acquire = WorkspaceLease.acquire.__func__
        real_bind = WorkspaceLease.bind_holder
        real_release = WorkspaceLease.release

        def acquire(cls, *args, **kwargs):
            recorder.append("acquire")
            return real_acquire(cls, *args, **kwargs)

        def bind_holder(self, **kwargs):
            recorder.append("bind_holder")
            return real_bind(self, **kwargs)

        def release(self):
            recorder.append("release")
            return real_release(self)

        fake = FakeUnity(recorder=recorder)
        with mock.patch.object(WorkspaceLease, "acquire", classmethod(acquire)), \
             mock.patch.object(WorkspaceLease, "bind_holder", bind_holder), \
             mock.patch.object(WorkspaceLease, "release", release):
            self.run_headless(fake, process_table_provider=table, run_version_flag=version)

        self.assertEqual(
            [
                "assert_headless_safe",
                "verify_project_editor",
                "acquire",
                "start",
                "bind_holder",
                "wait",
                "cancel",
                "release",
            ],
            recorder,
        )

    def test_bind_holder_happens_before_the_process_is_waited_on(self):
        """The acquire->bind window is what a crash would turn into a double-open."""
        recorder: list[str] = []
        real_bind = WorkspaceLease.bind_holder

        def bind_holder(self, **kwargs):
            recorder.append("bind_holder")
            return real_bind(self, **kwargs)

        fake = FakeUnity(recorder=recorder)
        with mock.patch.object(WorkspaceLease, "bind_holder", bind_holder):
            self.run_headless(fake)
        self.assertLess(recorder.index("bind_holder"), recorder.index("wait"))
        self.assertLess(recorder.index("start"), recorder.index("bind_holder"))

    def test_the_lease_on_disk_names_the_launched_group_not_the_controller(self):
        seen = {}
        real_bind = WorkspaceLease.bind_holder

        def bind_holder(self, **kwargs):
            record = real_bind(self, **kwargs)
            seen["record"] = read_lease(self.path)
            return record

        fake = FakeUnity(pid=5150, pgid=5150)
        with mock.patch.object(WorkspaceLease, "bind_holder", bind_holder):
            self.run_headless(fake)
        self.assertEqual(5150, seen["record"].pid)
        self.assertEqual(5150, seen["record"].pgid)
        self.assertNotEqual(os.getpid(), seen["record"].pgid)


class StartBoundTests(_TempCase):
    def test_a_failed_bind_cancels_the_process_and_raises(self):
        """Never return a live Unity under a lease that still names the controller."""
        fake = FakeUnity()

        class BrokenLease:
            def bind_holder(self, **kwargs):
                raise EvidenceError("E_UNITY_LEASE_LOST", "gone")

        with self.assertRaises(EvidenceError) as caught:
            routes._start_bound(
                BrokenLease(), routes._headless_argv(
                    self.editor, self.project,
                    self.root / "r.xml", self.root / "r.log",
                ),
                cwd=self.project, env={},
                stdout_path=self.root / "o", stderr_path=self.root / "e",
                process_factory=fake.factory,
            )
        self.assertEqual("E_UNITY_LEASE_LOST", caught.exception.code)
        self.assertTrue(fake.cancelled)

    def test_binds_with_the_processes_own_pid_and_pgid(self):
        seen = {}

        class RecordingLease:
            def bind_holder(self, *, pid, pgid):
                seen.update(pid=pid, pgid=pgid)

        fake = FakeUnity(pid=777, pgid=778)
        returned = routes._start_bound(
            RecordingLease(), routes._headless_argv(
                self.editor, self.project, self.root / "r.xml", self.root / "r.log",
            ),
            cwd=self.project, env={},
            stdout_path=self.root / "o", stderr_path=self.root / "e",
            process_factory=fake.factory,
        )
        self.assertEqual({"pid": 777, "pgid": 778}, seen)
        self.assertIs(fake, returned)


class CleanupAndLeaseTests(_TempCase):
    def test_success_releases_the_lease(self):
        self.run_headless(FakeUnity())
        self.assertEqual([], self.lease_files())

    def test_a_refused_outcome_still_releases_the_lease(self):
        with self.assertRaises(EvidenceError) as caught:
            self.run_headless(FakeUnity(results_text=None))
        self.assertEqual("E_UNITY_RESULTS_MISSING", caught.exception.code)
        self.assertEqual([], self.lease_files())

    def test_a_refused_outcome_still_cancels_the_containment(self):
        fake = FakeUnity(results_text=None)
        with self.assertRaises(EvidenceError):
            self.run_headless(fake)
        self.assertTrue(fake.cancelled)

    def test_cancel_runs_even_when_wait_raises(self):
        fake = FakeUnity()

        def exploding_wait(timeout_seconds):
            raise RuntimeError("wait blew up")

        fake.wait = exploding_wait
        with self.assertRaises(RuntimeError):
            self.run_headless(fake)
        self.assertTrue(fake.cancelled)
        self.assertEqual([], self.lease_files())

    def test_survivors_are_recorded_in_the_receipt_not_swallowed(self):
        receipt = self.run_headless(FakeUnity(survivors=(31337,)))
        self.assertEqual((31337,), receipt.descendant_pids)

    def test_a_receipt_with_survivors_fails_the_frozen_validator(self):
        receipt = self.run_headless(FakeUnity(survivors=(31337,)))
        codes = [(d.code, d.location) for d in validate_unity_receipt(receipt)]
        self.assertIn(("E_ASSERTION", "descendant_pids"), codes)

    def test_a_lockfile_left_behind_by_the_run_blocks_a_passing_claim(self):
        # MEASURED: Temp/UnityLockfile is removed on clean exit, so a lockfile
        # still present when the run is over means crash or kill. The lockfile
        # is created BY the run here -- one that exists beforehand is a
        # different case, refused earlier by ownership detection (see
        # CollisionRefusalTests.test_an_unresolvable_ownership_also_refuses).
        with self.assertRaises(EvidenceError) as caught:
            self.run_headless(FakeUnity(leaves_lockfile=self.project))
        self.assertEqual("E_UNITY_STALE_LOCK", caught.exception.code)
        self.assertEqual([], self.lease_files())

    def test_a_lockfile_left_behind_does_not_mask_a_compile_failure(self):
        # The cross-check guards the PASS claim only; a compile failure is
        # already a truthful negative and must still be reported as one.
        receipt = self.run_headless(FakeUnity(
            exit_code=1, results_text=None, log_text=COMPILE_LOG,
            leaves_lockfile=self.project,
        ))
        self.assertEqual("fail", receipt.compile.status)

    def test_a_previous_runs_results_file_is_not_read_as_this_runs_evidence(self):
        self.raw.mkdir(parents=True, exist_ok=True)
        (self.raw / routes.HEADLESS_RESULTS_NAME).write_text(PASSED_XML, encoding="utf-8")
        with self.assertRaises(EvidenceError) as caught:
            self.run_headless(FakeUnity(results_text=None))
        self.assertEqual("E_UNITY_RESULTS_MISSING", caught.exception.code)


# ---------------------------------------------------------------------------
# Lease scope -- the lock is per WORKSPACE, not per invocation
# ---------------------------------------------------------------------------

class LeaseScopeTests(_TempCase):
    """Two runs of one project must collide however they name their run dirs.

    Round-1 review proved the hole these tests close: the lease directory was
    derived from `raw_dir`, so two invocations differing only in `--raw-dir`
    both acquired cleanly for the SAME project. `lease_path_for` keys the
    FILENAME on the project's physical-path hash, which is worth nothing if the
    two callers never look in the same directory.
    """

    def test_two_runs_with_different_raw_dirs_cannot_both_hold_the_lease(self):
        held = WorkspaceLease.acquire(
            self.project,
            route=routes.SAME_PROJECT_HEADLESS_ROUTE,
            lease_dir=self.lease_dir(),
        )
        self.addCleanup(held.release)
        with self.assertRaises(EvidenceError) as caught:
            # lease_dir=None -> the route uses default_lease_dir(), which is
            # what a second operator invoking the CLI would get.
            self.run_headless(
                FakeUnity(), raw_dir_override=self.root / "raw-b", lease_dir=None
            )
        self.assertEqual("E_UNITY_LEASE_HELD", caught.exception.code)

    def test_a_concurrent_second_invocation_is_refused_mid_run(self):
        """The real scenario: run B starts while run A's Unity is still up."""
        inner: dict = {}
        outer = FakeUnity()

        def wait_and_launch_a_second_run(timeout_seconds):
            # Called while run A holds the lease and its "Unity" is live.
            try:
                self.run_headless(
                    FakeUnity(), raw_dir_override=self.root / "raw-b", lease_dir=None
                )
                inner["error"] = None
            except EvidenceError as error:
                inner["error"] = error.code
            return 0

        outer.wait = wait_and_launch_a_second_run
        self.run_headless(outer, lease_dir=None)
        self.assertEqual("E_UNITY_LEASE_HELD", inner["error"])

    def test_the_lease_does_not_live_under_the_run_directory(self):
        self.run_headless(FakeUnity(), lease_dir=None)
        stray = list(self.raw.rglob("*.lease.json"))
        self.assertEqual([], stray)

    def test_the_default_lease_dir_ignores_the_run_directory_entirely(self):
        with mock.patch.dict(os.environ, {routes.LEASE_DIR_ENV: str(self.root / "shared")}):
            self.assertEqual(self.root / "shared", routes.default_lease_dir())

    def test_the_default_lease_dir_follows_xdg_state_home(self):
        environ = {k: v for k, v in os.environ.items() if k != routes.LEASE_DIR_ENV}
        environ["XDG_STATE_HOME"] = "/state"
        with mock.patch.dict(os.environ, environ, clear=True):
            self.assertEqual(Path("/state/kinglet-unity/leases"), routes.default_lease_dir())

    def test_the_default_lease_dir_falls_back_to_the_home_state_dir(self):
        environ = {
            k: v for k, v in os.environ.items()
            if k not in (routes.LEASE_DIR_ENV, "XDG_STATE_HOME")
        }
        with mock.patch.dict(os.environ, environ, clear=True), \
             mock.patch.object(Path, "home", staticmethod(lambda: Path("/hometest"))):
            self.assertEqual(
                Path("/hometest/.local/state/kinglet-unity/leases"),
                routes.default_lease_dir(),
            )

    def test_a_crashed_runs_pgid_is_findable_by_a_run_with_another_raw_dir(self):
        """The crashed-run half: the recorded pgid must be reachable later.

        `bind_holder` records the contained pgid so a later run can clean up a
        leaked group. A per-run lease directory made that record unreachable to
        any later run that chose a different `--raw-dir`.
        """
        crashed = WorkspaceLease.acquire(
            self.project,
            route=routes.SAME_PROJECT_HEADLESS_ROUTE,
            lease_dir=self.lease_dir(),
        )
        crashed.bind_holder(pid=6100, pgid=6100)
        self.addCleanup(crashed.release)
        # A different run directory entirely -- the later run still finds it.
        from tools.kinglet_spike.unity.lease import lease_path_for
        found = read_lease(lease_path_for(self.project, routes.default_lease_dir()))
        self.assertEqual(6100, found.pgid)

    def setUp(self):
        super().setUp()
        # default_lease_dir() must be the one every caller in these tests
        # agrees on, without touching the real host directory.
        patcher = mock.patch.dict(
            os.environ, {routes.LEASE_DIR_ENV: str(self.root / "leases")}
        )
        patcher.start()
        self.addCleanup(patcher.stop)


# ---------------------------------------------------------------------------
# Module surface
# ---------------------------------------------------------------------------

class ModuleSurfaceTests(unittest.TestCase):
    def test_the_launcher_is_not_part_of_the_public_surface(self):
        # Either of these lets a caller launch Unity while skipping ownership
        # detection and Editor verification.
        self.assertNotIn("start_bound", routes.__all__)
        self.assertNotIn("headless_argv", routes.__all__)
        self.assertFalse(hasattr(routes, "start_bound"))
        self.assertFalse(hasattr(routes, "headless_argv"))

    def test_the_two_routes_are_public(self):
        self.assertIn("run_filesystem", routes.__all__)
        self.assertIn("run_same_project_headless", routes.__all__)

    def test_every_name_in_all_actually_exists(self):
        for name in routes.__all__:
            with self.subTest(name=name):
                self.assertTrue(hasattr(routes, name))


# ---------------------------------------------------------------------------
# Refusals
# ---------------------------------------------------------------------------

class CollisionRefusalTests(_TempCase):
    def refuse(self, **overrides):
        fake = FakeUnity()
        receipt = self.run_headless(fake, **overrides)
        return receipt, fake

    def test_a_confirmed_owner_produces_a_collision_refusal(self):
        receipt, _ = self.refuse(process_table_provider=owning_table(self.project))
        self.assertTrue(receipt.collision_refused)

    def test_the_process_launcher_is_never_called(self):
        receipt, fake = self.refuse(process_table_provider=owning_table(self.project))
        self.assertIsNone(fake.argv)

    def test_the_refusal_receipt_carries_no_unity_pid(self):
        receipt, _ = self.refuse(process_table_provider=owning_table(self.project))
        self.assertEqual((), receipt.descendant_pids)
        self.assertFalse(receipt.active_lease)
        payload = json.dumps(routes.receipt_to_dict(receipt))
        self.assertNotIn("99001", payload)

    def test_a_refusal_never_claims_a_compile_or_test_result(self):
        receipt, _ = self.refuse(process_table_provider=owning_table(self.project))
        self.assertEqual("not-run", receipt.compile.status)
        self.assertEqual("not-run", receipt.tests.status)

    def test_the_refusal_receipt_is_clean_under_the_frozen_validator(self):
        receipt, _ = self.refuse(process_table_provider=owning_table(self.project))
        self.assertEqual((), validate_unity_receipt(receipt))

    def test_a_refusal_takes_no_lease(self):
        self.refuse(process_table_provider=owning_table(self.project))
        self.assertEqual([], self.lease_files())

    def test_an_unresolvable_ownership_also_refuses(self):
        """A stale Temp/UnityLockfile is 'unknown', which is not 'safe'."""
        lock = routes.unity_lockfile_path(self.project)
        lock.parent.mkdir(parents=True, exist_ok=True)
        lock.write_text("", encoding="utf-8")
        receipt, fake = self.refuse()
        self.assertTrue(receipt.collision_refused)
        self.assertIsNone(fake.argv)
        summary = json.loads((self.raw / routes.HEADLESS_SUMMARY_NAME).read_text(encoding="utf-8"))
        self.assertEqual("E_UNITY_OWNER_UNKNOWN", summary["refusal_code"])
        self.assertFalse(summary["launched"])

    def test_a_refusal_records_the_version_the_project_declares(self):
        receipt, _ = self.refuse(process_table_provider=owning_table(self.project))
        self.assertEqual(EDITOR_VERSION, receipt.unity_version)

    def test_a_non_ownership_error_is_not_laundered_into_a_refusal(self):
        def angry_table():
            raise EvidenceError("E_UNITY_SOMETHING_ELSE", "not an ownership verdict")

        with self.assertRaises(EvidenceError) as caught:
            self.run_headless(FakeUnity(), process_table_provider=angry_table)
        self.assertEqual("E_UNITY_SOMETHING_ELSE", caught.exception.code)


class EditorVerificationTests(_TempCase):
    def test_a_mismatched_editor_refuses_before_anything_launches(self):
        fake = FakeUnity()
        with self.assertRaises(EvidenceError) as caught:
            self.run_headless(fake, run_version_flag=version_stdout("6000.0.68f1"))
        self.assertEqual("E_UNITY_VERSION", caught.exception.code)
        self.assertIsNone(fake.argv)

    def test_a_mismatched_editor_leaves_no_lease_behind(self):
        with self.assertRaises(EvidenceError):
            self.run_headless(FakeUnity(), run_version_flag=version_stdout("2022.3.62f3"))
        self.assertEqual([], self.lease_files())

    def test_the_receipt_records_the_version_that_actually_ran(self):
        project = make_project(self.root / "p68", version="6000.0.68f1")
        fake = FakeUnity()
        receipt = routes.run_same_project_headless(
            self.editor, project, self.raw,
            process_table_provider=empty_process_table,
            windows=False,
            run_version_flag=version_stdout("6000.0.68f1"),
            process_factory=fake.factory,
            env={"PATH": "/usr/bin"},
            lease_dir=self.lease_dir(),
        )
        self.assertEqual("6000.0.68f1", receipt.unity_version)


# ---------------------------------------------------------------------------
# End-to-end receipt shape
# ---------------------------------------------------------------------------

class HeadlessReceiptTests(_TempCase):
    def test_a_passing_run_produces_a_clean_receipt(self):
        receipt = self.run_headless(FakeUnity())
        self.assertEqual(RECEIPT_SCHEMA, receipt.schema)
        self.assertEqual(routes.SAME_PROJECT_HEADLESS_ROUTE, receipt.route)
        self.assertEqual("pass", receipt.compile.status)
        self.assertEqual("pass", receipt.tests.status)
        self.assertEqual(1, receipt.tests.passed)
        self.assertEqual((), validate_unity_receipt(receipt))

    def test_a_passing_run_never_claims_ready(self):
        # ready is exclusive to live-editor-mcp.
        self.assertFalse(self.run_headless(FakeUnity()).ready)

    def test_a_compile_failure_produces_a_compile_fail_receipt(self):
        receipt = self.run_headless(
            FakeUnity(exit_code=1, results_text=None, log_text=COMPILE_LOG)
        )
        self.assertEqual(("fail", 1), (receipt.compile.status, receipt.compile.errors))
        self.assertEqual("not-run", receipt.tests.status)
        self.assertEqual((), validate_unity_receipt(receipt))

    def test_a_test_failure_produces_a_tests_fail_receipt(self):
        receipt = self.run_headless(FakeUnity(exit_code=2, results_text=FAILED_XML))
        self.assertEqual("pass", receipt.compile.status)
        self.assertEqual(("fail", 1), (receipt.tests.status, receipt.tests.failed))
        self.assertEqual((), validate_unity_receipt(receipt))

    def test_receipt_round_trips_through_the_strict_parser(self):
        receipt = self.run_headless(FakeUnity())
        self.assertEqual(receipt, unity_receipt_from_dict(routes.receipt_to_dict(receipt)))

    def test_summary_artifact_is_written_and_names_the_exit_code(self):
        self.run_headless(FakeUnity())
        summary = json.loads((self.raw / routes.HEADLESS_SUMMARY_NAME).read_text(encoding="utf-8"))
        self.assertEqual(0, summary["exit_code"])
        self.assertTrue(summary["launched"])
        self.assertEqual(EDITOR_VERSION, summary["unity_version"])

    def test_the_run_writes_its_log_and_results_where_the_argv_said(self):
        self.run_headless(FakeUnity(log_text="hello\n"))
        self.assertTrue((self.raw / routes.HEADLESS_LOG_NAME).is_file())
        self.assertTrue((self.raw / routes.HEADLESS_RESULTS_NAME).is_file())

    def test_the_abort_banner_on_stdout_alone_is_still_seen(self):
        """Unity writes the abort banner to stdout, not into -logFile."""
        receipt = self.run_headless(FakeUnity(
            exit_code=1, results_text=None, log_text="",
            stdout_text="\nAborting batchmode due to failure:\n"
                        "Assets/A.cs(1,1): error CS1002: ; expected\n",
        ))
        self.assertEqual(("fail", 1), (receipt.compile.status, receipt.compile.errors))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

class CliTests(_TempCase):
    def run_cli(self, argv):
        import io
        from tools.kinglet_spike.unity import cli
        out, err = io.StringIO(), io.StringIO()
        code = cli.main(argv, stdout=out, stderr=err)
        return code, out.getvalue(), err.getvalue()

    def test_filesystem_route_exits_zero_and_prints_a_parseable_receipt(self):
        code, out, err = self.run_cli([
            "filesystem", "--project", str(self.project), "--raw-dir", str(self.raw),
        ])
        self.assertEqual(0, code, err)
        receipt = unity_receipt_from_dict(json.loads(out))
        self.assertEqual(routes.FILESYSTEM_ROUTE, receipt.route)

    def test_a_route_that_cannot_produce_a_receipt_exits_two(self):
        code, out, err = self.run_cli([
            "filesystem", "--project", str(self.root / "nope"), "--raw-dir", str(self.raw),
        ])
        self.assertEqual(2, code)
        self.assertEqual("", out)
        self.assertIn("E_", err)

    def test_a_usage_error_exits_two(self):
        code, _, err = self.run_cli(["filesystem"])
        self.assertEqual(2, code)
        self.assertIn("usage error", err)

    def test_an_unknown_route_exits_two(self):
        code, _, _ = self.run_cli(["live-editor-mcp"])
        self.assertEqual(2, code)

    def test_a_dishonest_receipt_exits_one_but_is_still_printed(self):
        from tools.kinglet_spike.unity import cli
        from tools.kinglet_spike.unity.model import CompileResult, TestResult, UnityReceipt
        dishonest = UnityReceipt(
            schema=RECEIPT_SCHEMA, route=routes.FILESYSTEM_ROUTE,
            project_id=PROJECT_ID, unity_version=EDITOR_VERSION,
            compile=CompileResult(status="pass", errors=0),
            tests=TestResult(status="pass", passed=1, failed=0, skipped=0),
            ready=False, collision_refused=False, active_lease=False,
            descendant_pids=(), artifacts=(),
        )
        import io
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(cli, "run_filesystem", lambda *a, **k: dishonest):
            code = cli.main(
                ["filesystem", "--project", str(self.project), "--raw-dir", str(self.raw)],
                stdout=out, stderr=err,
            )
        self.assertEqual(1, code)
        self.assertIn("compile.status", err.getvalue())
        self.assertEqual(dishonest, unity_receipt_from_dict(json.loads(out.getvalue())))


if __name__ == "__main__":
    unittest.main()
