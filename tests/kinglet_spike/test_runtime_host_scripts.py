"""Text-presence assertions on the Linux host-runner scripts.

These tests parse the script SOURCE (they do not execute the runners) and assert
that the host gate, the four-candidate loop, the self-containment PATH stripping,
the publish call, and the 30-sample cold-start measurement are all present.
This mirrors the existing spike script tests: assert on script text, not behaviour.
"""
from __future__ import annotations

import unittest
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
_RUNTIME_DIR = _REPO_ROOT / "spikes" / "platform" / "runtime"

RUN_HOST = (_RUNTIME_DIR / "run-host.sh").read_text(encoding="utf-8")
MEASURE = (_RUNTIME_DIR / "measure.sh").read_text(encoding="utf-8")
BUILD_RECORD = (_RUNTIME_DIR / "build-record.py").read_text(encoding="utf-8")


class RunHostScriptTests(unittest.TestCase):
    def test_uses_strict_bash_mode(self):
        self.assertIn("set -euo pipefail", RUN_HOST)

    def test_rejects_wsl_distro_env_var(self):
        self.assertIn("WSL_DISTRO_NAME", RUN_HOST)

    def test_rejects_wsl_kernel(self):
        # uname -r read, and a microsoft/WSL match on it.
        self.assertIn("uname -r", RUN_HOST)
        self.assertIn("microsoft", RUN_HOST)
        self.assertIn("WSL", RUN_HOST)

    def test_accepts_only_ubuntu_or_noble_family(self):
        # ID=ubuntu OR (ID_LIKE contains ubuntu AND VERSION_CODENAME=noble).
        self.assertIn('"$OS_ID" = "ubuntu"', RUN_HOST)
        self.assertIn("ID_LIKE", RUN_HOST)
        self.assertIn("noble", RUN_HOST)
        self.assertIn("VERSION_CODENAME", RUN_HOST)

    def test_records_os_release_and_kernel(self):
        self.assertIn("/etc/os-release", RUN_HOST)
        self.assertIn("PRETTY_NAME", RUN_HOST)
        self.assertIn("kernel=", RUN_HOST)

    def test_requires_empty_run_dir_under_kinglet_local(self):
        self.assertIn(".kinglet/local/spikes", RUN_HOST)
        self.assertIn("run dir is not empty", RUN_HOST)

    def test_invokes_all_four_candidates(self):
        self.assertIn("python go rust dotnet", RUN_HOST)
        for cand in ("python", "go", "rust", "dotnet"):
            self.assertIn(cand, RUN_HOST)

    def test_invokes_black_box_conformance(self):
        self.assertIn("tools.kinglet_spike.runtime_contract", RUN_HOST)
        self.assertIn("--executable", RUN_HOST)
        self.assertIn("--contract-dir", RUN_HOST)

    def test_invokes_publish(self):
        self.assertIn("tools.kinglet_spike publish", RUN_HOST)

    def test_strips_toolchain_dirs_from_child_path(self):
        # A stripped PATH is built and applied when running the packaged artifact.
        self.assertIn("TOOLCHAIN_DIRS", RUN_HOST)
        self.assertIn("_strip_path", RUN_HOST)
        self.assertIn("RUN_PATH", RUN_HOST)
        self.assertIn('PATH="$RUN_PATH"', RUN_HOST)

    def test_supports_dry_run(self):
        self.assertIn("--dry-run", RUN_HOST)
        self.assertIn("DRY_RUN", RUN_HOST)

    def test_no_declare_associative_array(self):
        self.assertNotIn("declare -A", RUN_HOST)

    def test_no_grep_oP(self):
        self.assertNotIn("grep -oP", RUN_HOST)

    def test_no_pipe_into_head(self):
        self.assertNotIn("| head", RUN_HOST)

    def test_no_absolute_user_path_in_command_array(self):
        # The command array must not embed /home/<user>; relative paths only.
        self.assertNotIn("/home/riive", RUN_HOST)


class MeasureScriptTests(unittest.TestCase):
    def test_uses_strict_bash_mode(self):
        self.assertIn("set -euo pipefail", MEASURE)

    def test_collects_thirty_cold_start_samples(self):
        self.assertIn("sample_count=30", MEASURE)

    def test_measures_peak_rss_via_usr_bin_time(self):
        self.assertIn("/usr/bin/time -v", MEASURE)
        self.assertIn("Maximum resident set size", MEASURE)

    def test_measures_artifact_bytes(self):
        self.assertIn("artifact_bytes", MEASURE)

    def test_emits_expected_json_keys(self):
        for key in ("cold_start_ms", "peak_rss_kb", "artifact_bytes", "dependency_count"):
            self.assertIn(key, MEASURE)

    def test_millisecond_timestamps(self):
        self.assertIn("date +%s%3N", MEASURE)

    def test_no_declare_associative_array(self):
        self.assertNotIn("declare -A", MEASURE)

    def test_no_grep_oP(self):
        self.assertNotIn("grep -oP", MEASURE)

    def test_no_pipe_into_head(self):
        self.assertNotIn("| head", MEASURE)


class BuildRecordHelperTests(unittest.TestCase):
    def test_emits_evidence_schema(self):
        self.assertIn("kinglet.spike.evidence/v1", BUILD_RECORD)

    def test_pins_ubuntu_noble_release(self):
        self.assertIn("ubuntu-24.04-noble", BUILD_RECORD)

    def test_declares_eighteen_assertion_ids(self):
        # All 18 frozen assertion ids present.
        for a_id in (
            "manifest.accept-valid",
            "manifest.reject-unknown",
            "path.unicode-space",
            "filesystem.atomic-replace",
            "lease.acquire",
            "lease.renew",
            "lease.reject-competitor",
            "lease.expire",
            "lease.release",
            "process.child-grandchild",
            "process.cancel",
            "process.no-descendants",
            "crypto.sha256",
            "crypto.ed25519",
            "cleanup.success",
            "cleanup.crash",
            "cleanup.timeout",
            "cleanup.cancel",
        ):
            self.assertIn(a_id, BUILD_RECORD)

    def test_emits_four_measurement_ids(self):
        for m_id in ("cold-start", "peak-rss", "artifact-size", "dependency-count"):
            self.assertIn(m_id, BUILD_RECORD)


if __name__ == "__main__":
    unittest.main()
