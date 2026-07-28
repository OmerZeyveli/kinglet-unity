"""Task 8 -- the native host entry point and the observations -> evidence layer.

Two things are under test here and they are tested differently.

`spikes/platform/unity/run-host.sh` is tested by RUNNING IT. Every case below
is a refusal, and each one is arranged so that the act it forbids cannot happen
even if the guard is deleted: the `--unity` path handed in is never an
executable Unity, and `--repo-root` points at a directory with no pinned
fixture, so a script that reached its Python body would die there rather than
launch an Editor. A refusal test that could perform the act it forbids is not a
test, it is a loaded gun.

`tools/kinglet_spike/unity/results.py` and the pure helpers in
`host_probes.py` are tested directly, because they are where a dishonest
document would have to get through. The probes that launch Unity are NOT
exercised here -- they need a real Editor, and a stubbed Unity would prove only
that the stub behaves.
"""
from __future__ import annotations

import json
import os
import subprocess
import unittest
from pathlib import Path

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.unity import host_probes
from tools.kinglet_spike.unity.results import (
    OBSERVATIONS_SCHEMA,
    PROBES,
    to_evidence_records,
    validate_unity_observations,
)

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "spikes/platform/unity/run-host.sh"


def run_script(arguments, *, env=None, cwd=None):
    environment = dict(os.environ)
    environment.pop("WSL_DISTRO_NAME", None)
    environment.pop("WSLENV", None)
    if env:
        environment.update(env)
    return subprocess.run(
        ["bash", str(SCRIPT), *arguments],
        capture_output=True,
        text=True,
        cwd=str(cwd or REPO),
        env=environment,
        timeout=120,
    )


def observation_document(**overrides):
    document = {
        "schema": OBSERVATIONS_SCHEMA,
        "unity_version": "6000.3.18f1",
        "unity_revision": "5ebeb53e4c07",
        "environment": {
            "os": "linux",
            "release": "ubuntu-24.04.4-lts",
            "arch": "x64",
            "native": True,
            "toolchain": ["host=Pop!_OS 24.04 LTS", "kernel=7.0.11"],
        },
        "probes": [
            {
                "id": "filesystem-only",
                "unobserved": False,
                "command": ["python3", "-m", "tools.kinglet_spike.unity", "filesystem"],
                "assertions": [
                    {"id": "receipt-valid", "status": "pass", "detail": "ok"},
                ],
                "artifact_paths": [],
            },
        ],
    }
    document.update(overrides)
    return document


class RunHostScriptSafety(unittest.TestCase):
    """The script exists, is bash, and refuses before it can do harm."""

    def test_the_script_exists_and_parses_as_bash(self):
        self.assertTrue(SCRIPT.is_file(), "run-host.sh is missing")
        parsed = subprocess.run(
            ["bash", "-n", str(SCRIPT)], capture_output=True, text=True
        )
        self.assertEqual(parsed.returncode, 0, parsed.stderr)

    def test_an_explicit_unity_path_is_required(self):
        result = run_script([])
        self.assertEqual(result.returncode, 2)
        self.assertIn("--unity is required", result.stderr)
        self.assertIn("never searches", result.stderr)

    def test_unity_without_an_operand_reports_instead_of_shifting_into_set_u(self):
        # `shift 2` on a one-element argv fails under `set -u` BEFORE any error
        # message can print, and the operator gets a silent exit 1. The message
        # is the assertion.
        result = run_script(["--unity"])
        self.assertEqual(result.returncode, 2)
        self.assertIn("--unity requires a path", result.stderr)

    def test_run_id_without_an_operand_reports_too(self):
        result = run_script(["--unity", "/nonexistent/Unity", "--run-id"])
        self.assertEqual(result.returncode, 2)
        self.assertIn("--run-id requires a value", result.stderr)

    def test_an_unknown_argument_is_refused(self):
        result = run_script(["--unity", "/nonexistent/Unity", "--yolo"])
        self.assertEqual(result.returncode, 2)
        self.assertIn("unknown argument", result.stderr)

    def test_a_non_executable_editor_is_refused(self):
        result = run_script(["--unity", str(REPO / "README.md")])
        self.assertEqual(result.returncode, 2)
        self.assertIn("not an executable Unity Editor", result.stderr)

    def test_wsl_is_refused_by_environment(self):
        # --repo-root is a directory with no pinned fixture, so a build of this
        # script with the WSL guard deleted still refuses one line later and
        # still creates nothing. Killing the mutant is not worth a test that
        # can start a run.
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            result = run_script(
                ["--unity", "/bin/true", "--repo-root", temporary],
                env={"WSL_DISTRO_NAME": "Ubuntu"},
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn("WSL", result.stderr)

    def test_wslenv_alone_is_also_refused(self):
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            result = run_script(
                ["--unity", "/bin/true", "--repo-root", temporary],
                env={"WSLENV": "PATH/l"},
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn("WSL", result.stderr)

    def test_a_repo_root_without_the_pinned_fixture_is_refused(self):
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            result = run_script(
                ["--unity", "/bin/true", "--repo-root", temporary]
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("pinned fixture missing", result.stderr)

    def test_an_existing_raw_run_directory_is_refused(self):
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "spikes/platform/unity/fixture").mkdir(parents=True)
            existing = root / ".kinglet/local/spikes/reused"
            existing.mkdir(parents=True)
            result = run_script(
                ["--unity", "/bin/true", "--repo-root", str(root),
                 "--run-id", "reused"]
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("already exists", result.stderr)

    def test_the_script_installs_a_cleanup_trap(self):
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("trap cleanup EXIT INT TERM", text)
        # All three orphan classes must be reachable by the sweep. The
        # AssetImportWorker one is the trap: its argv0 is a bare `Unity`, so the
        # sweep matches on the workspace path rather than on a process name.
        self.assertIn("UnityShaderCompiler", text)
        self.assertIn("AssetImportWorker", text)

    def test_the_script_never_evaluates_the_editor_path(self):
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn("eval ", text)
        self.assertIn('python3 -m tools.kinglet_spike.unity.host_probes "$REPO_ROOT" "$UNITY"', text)


class ObservationValidation(unittest.TestCase):
    """A document cannot claim more than its own assertions support."""

    def test_a_valid_document_round_trips(self):
        observations = validate_unity_observations(observation_document())
        self.assertEqual(observations.unity_version, "6000.3.18f1")
        self.assertEqual(observations.probes[0].id, "filesystem-only")

    def test_an_unknown_root_field_is_refused(self):
        document = observation_document()
        document["extra"] = 1
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_FIELD")

    def test_a_probe_id_outside_the_frozen_matrix_is_refused(self):
        document = observation_document()
        document["probes"][0]["id"] = "filesystem"      # the ROUTE name, not the cell
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_COVERAGE")

    def test_every_frozen_probe_id_is_accepted(self):
        for probe_id in PROBES:
            document = observation_document()
            document["probes"][0]["id"] = probe_id
            validate_unity_observations(document)

    def test_a_duplicate_probe_is_refused(self):
        document = observation_document()
        document["probes"].append(dict(document["probes"][0]))
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_COVERAGE")

    def test_an_observed_probe_must_assert_something(self):
        document = observation_document()
        document["probes"][0]["assertions"] = []
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_ASSERTION")

    def test_an_unobserved_probe_must_carry_a_reason(self):
        document = observation_document(probes=[
            {"id": "live-editor-mcp", "unobserved": True},
        ])
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_FIELD")
        self.assertIn("why it is open", caught.exception.detail)

    def test_an_unobserved_probe_may_not_also_assert(self):
        document = observation_document(probes=[
            {
                "id": "live-editor-mcp",
                "unobserved": True,
                "reason": "blocked",
                "assertions": [{"id": "x", "status": "pass", "detail": "d"}],
            },
        ])
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_ASSERTION")

    def test_an_observed_probe_may_not_carry_a_reason(self):
        document = observation_document()
        document["probes"][0]["reason"] = "sneaking an excuse into a pass"
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_FIELD")

    def test_an_empty_toolchain_is_refused(self):
        document = observation_document()
        document["environment"]["toolchain"] = []
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_FIELD")
        self.assertIn("real host", caught.exception.detail)

    def test_an_assertion_status_outside_pass_fail_is_refused(self):
        document = observation_document()
        document["probes"][0]["assertions"][0]["status"] = "inconclusive"
        with self.assertRaises(EvidenceError) as caught:
            validate_unity_observations(document)
        self.assertEqual(caught.exception.code, "E_ENUM")


class RecordConversion(unittest.TestCase):
    """The record's status is derived, never declared."""

    def test_a_probe_whose_assertions_all_pass_becomes_a_pass_record(self):
        records = to_evidence_records(
            validate_unity_observations(observation_document()),
            now="2026-07-28T00:00:00Z",
        )
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0].status, "pass")

    def test_one_failing_assertion_drops_the_record_off_pass(self):
        document = observation_document()
        document["probes"][0]["assertions"].append(
            {"id": "tests-pass", "status": "fail", "detail": "status=not-run"}
        )
        records = to_evidence_records(
            validate_unity_observations(document), now="2026-07-28T00:00:00Z"
        )
        self.assertEqual(records[0].status, "fail")

    def test_an_unobserved_probe_becomes_inconclusive_carrying_its_reason(self):
        document = observation_document(probes=[
            {"id": "live-editor-mcp", "unobserved": True, "reason": "bridge never registered"},
        ])
        records = to_evidence_records(
            validate_unity_observations(document), now="2026-07-28T00:00:00Z"
        )
        self.assertEqual(records[0].status, "inconclusive")
        self.assertEqual(records[0].assertions[0].status, "fail")
        self.assertIn("bridge never registered", records[0].assertions[0].detail)

    def test_the_record_targets_the_matrix_subject_not_the_project_id(self):
        # This is the whole reason results.py exists: coverage matches on
        # subject.id, and every unity cell carries "execution".
        records = to_evidence_records(
            validate_unity_observations(observation_document()),
            now="2026-07-28T00:00:00Z",
        )
        self.assertEqual(records[0].subject.kind, "unity")
        self.assertEqual(records[0].subject.id, "execution")
        self.assertEqual(records[0].probe.id, "filesystem-only")

    def test_the_subject_version_carries_the_exact_version_and_revision(self):
        records = to_evidence_records(
            validate_unity_observations(observation_document()),
            now="2026-07-28T00:00:00Z",
        )
        self.assertEqual(records[0].subject.version, "6000.3.18f1 (5ebeb53e4c07)")

    def test_every_record_carries_subject_provenance_sources(self):
        records = to_evidence_records(
            validate_unity_observations(observation_document()),
            now="2026-07-28T00:00:00Z",
        )
        self.assertTrue(records[0].sources)
        self.assertTrue(all(source.url.startswith("https://") for source in records[0].sources))

    def test_run_ids_are_qualified_by_probe_and_environment(self):
        document = observation_document()
        document["probes"].append({
            "id": "same-project-headless",
            "unobserved": False,
            "command": ["unity"],
            "assertions": [{"id": "a", "status": "pass", "detail": "d"}],
            "artifact_paths": [],
        })
        records = to_evidence_records(
            validate_unity_observations(document), now="2026-07-28T00:00:00Z"
        )
        identifiers = {record.run_id for record in records}
        self.assertEqual(len(identifiers), 2)
        for record in records:
            self.assertIn(record.probe.id, record.run_id)
            self.assertIn("linux", record.run_id)
            self.assertIn("x64", record.run_id)


class HostCensusHelpers(unittest.TestCase):
    """The measured traps, encoded as tests."""

    def test_a_shell_quoting_every_class_name_is_filtered_before_the_census(self):
        # MEASURED on this host: a leftover
        # `bash -c '... pgrep -af "Editor/Unity|VBCSCompiler|..." ...'`
        # reported one survivor of EACH class when the true answer was zero.
        shell_row = (
            "923560 4158 923560 /bin/bash -c pgrep -af "
            "Editor/Unity|VBCSCompiler|UnityPackageManager|AssetImportWorker"
        )
        real_row = (
            "1020229 1 1018591 dotnet exec "
            "/opt/Unity/Editor/Data/DotNetSdkRoslyn/VBCSCompiler.dll -pipename:x"
        )
        # The raw census cannot tell them apart -- that is the whole point of
        # filtering first.
        self.assertEqual(host_probes.orphan_census((shell_row,))["VBCSCompiler"], 1)

        kept = host_probes.filter_process_rows([shell_row, real_row])
        self.assertEqual(kept, (real_row,))
        census = host_probes.orphan_census(kept)
        self.assertEqual(census["VBCSCompiler"], 1)
        self.assertEqual(census["EditorUnity"], 0)

    def test_filtering_keeps_a_real_editor_row(self):
        editor_row = (
            "1000166 1 1000166 /opt/Unity/Hub/Editor/6000.3.18f1/Editor/Unity "
            "-projectPath /w -logFile /w.log"
        )
        kept = host_probes.filter_process_rows([editor_row])
        self.assertEqual(kept, (editor_row,))
        self.assertEqual(host_probes.orphan_census(kept)["EditorUnity"], 1)

    def test_process_rows_filters_by_argv0_not_by_the_whole_line(self):
        self.assertIn("bash", host_probes.NON_UNITY_ARGV0)
        self.assertIn("pgrep", host_probes.NON_UNITY_ARGV0)
        self.assertIn("python3", host_probes.NON_UNITY_ARGV0)

    def test_the_asset_import_worker_class_is_matched_on_its_name_flag(self):
        # Its argv0 is a bare `Unity`, so "Editor/Unity" provably misses it.
        classes = dict(host_probes.ORPHAN_CLASSES)
        self.assertEqual(classes["AssetImportWorker"], "-name AssetImportWorker")
        row = (
            "1001855 1 1001855 Unity -adb2 -batchMode -noUpm "
            "-name AssetImportWorker0 -projectPath /w -logFile Logs/a.log"
        )
        census = host_probes.orphan_census((row,))
        self.assertEqual(census["AssetImportWorker"], 1)
        self.assertEqual(census["EditorUnity"], 0)

    def test_the_package_manager_server_carries_no_project_path(self):
        # Which is why the census is host-wide: a scope filter reports zero for
        # exactly the classes that leak.
        row = (
            "1016780 1016768 1016768 /opt/Unity/Editor/Data/Resources/"
            "PackageManager/Server/UnityPackageManager server -s 1016768 "
            "--ipc-path /tmp/Unity-Upm-1016768.sock -l 2"
        )
        self.assertNotIn("-projectPath", row)
        self.assertEqual(host_probes.orphan_census((row,))["UnityPackageManager"], 1)

    def test_the_log_version_reader_returns_the_pair_unity_itself_printed(self):
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / "editor.log"
            log.write_text(
                "Unity Editor version:    6000.3.18f1 (5ebeb53e4c07)\n"
                "Branch: 6000.3/staging\n",
                encoding="utf-8",
            )
            self.assertEqual(
                host_probes._log_version(log), ("6000.3.18f1", "5ebeb53e4c07")
            )

    def test_the_log_version_reader_reports_nothing_when_it_cannot_read(self):
        self.assertEqual(host_probes._log_version(Path("/nonexistent.log")), ("", ""))

    def test_the_revision_reader_rejects_a_non_hex_url_component(self):
        # MEASURED: `/download_unity/open-jdk/...` sits in the same position as
        # the revision, and reading it produced two "revisions" for one install.
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            editor_dir = root / "6000.3.18f1" / "Editor"
            editor_dir.mkdir(parents=True)
            editor = editor_dir / "Unity"
            editor.write_text("", encoding="utf-8")
            (root / "6000.3.18f1" / "modules.json").write_text(json.dumps([
                {"url": "https://d.unity3d.com/download_unity/5ebeb53e4c07/a.pkg"},
                {"url": "https://d.unity3d.com/download_unity/open-jdk/b.zip"},
            ]), encoding="utf-8")
            self.assertEqual(
                host_probes._editor_revision(editor, "6000.3.18f1"), "5ebeb53e4c07"
            )

    def test_the_revision_reader_refuses_rather_than_guessing(self):
        import tempfile

        with tempfile.TemporaryDirectory() as temporary:
            editor_dir = Path(temporary) / "6000.3.18f1" / "Editor"
            editor_dir.mkdir(parents=True)
            editor = editor_dir / "Unity"
            editor.write_text("", encoding="utf-8")
            with self.assertRaises(EvidenceError) as caught:
                host_probes._editor_revision(editor, "6000.3.18f1")
            self.assertEqual(caught.exception.code, "E_UNITY_VERSION")

    def test_the_environment_records_the_matrix_key_and_the_real_host(self):
        environment = host_probes.host_environment()
        self.assertIn(environment["os"], ("linux", "macos"))
        self.assertTrue(environment["native"])
        self.assertTrue(environment["toolchain"])
        self.assertTrue(any("host=" in item for item in environment["toolchain"]))

    def test_the_live_editor_mcp_reason_names_the_defect_not_the_run(self):
        reason = host_probes.LIVE_EDITOR_MCP_REASON
        self.assertIn("EditorPrefs", reason)
        self.assertIn("not worked around", reason)


if __name__ == "__main__":
    unittest.main()
