"""Contract tests on the native host-runner scripts (Linux, macOS, Windows).

Three layers, deliberately:

1. Text-presence assertions on the script SOURCE — the original layer, which is
   what keeps the enforced shell conventions (no `declare -A`, no `grep -oP`, no
   pipe into `head`, no hardcoded home path) from creeping back in.
2. EXECUTION of the platform-dependent shell helpers. Both POSIX scripts have a
   library mode (`KINGLET_RUNHOST_LIB=1` / `KINGLET_MEASURE_LIB=1`) that defines
   every function and returns without gating the host, so the macOS branches run
   for real on this Linux box instead of merely being inspected.
3. EXECUTION of the PowerShell helpers under `pwsh`. Both .ps1 files are
   parse-checked with the PowerShell parser, and the pure functions (RID
   selection, caption gate, release derivation, PATH stripping, bytes->KB) are
   dot-sourced with `-LibraryOnly` and driven with a table of inputs. Guarded by
   `shutil.which("pwsh")` with a `KINGLET_REQUIRE_PWSH=1` escape hatch, mirroring
   `KINGLET_REQUIRE_PROBE` in test_claude_probe_package.py.

Anything that genuinely needs the foreign OS (a real Win32_OperatingSystem query,
a real `sw_vers`, a real PeakWorkingSet64 after exit) is skipped with a reason,
never faked.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
_RUNTIME_DIR = _REPO_ROOT / "spikes" / "platform" / "runtime"

RUN_HOST = (_RUNTIME_DIR / "run-host.sh").read_text(encoding="utf-8")
MEASURE = (_RUNTIME_DIR / "measure.sh").read_text(encoding="utf-8")
BUILD_RECORD = (_RUNTIME_DIR / "build-record.py").read_text(encoding="utf-8")
RUN_HOST_PS1 = (_RUNTIME_DIR / "run-host.ps1").read_text(encoding="utf-8")
MEASURE_PS1 = (_RUNTIME_DIR / "measure.ps1").read_text(encoding="utf-8")


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------


def _run_shell_lib(script: str, body: str) -> str:
    """Source a runner in library mode and run `body`; return stdout."""
    if script == "run-host.sh":
        env_flag = "KINGLET_RUNHOST_LIB=1"
    else:
        env_flag = "KINGLET_MEASURE_LIB=1"
    path = _RUNTIME_DIR / script
    program = f'{env_flag} . "{path}"\n{body}\n'
    completed = subprocess.run(
        ["bash", "-c", program],
        capture_output=True,
        text=True,
        cwd=str(_REPO_ROOT),
        check=False,
    )
    if completed.returncode != 0:
        raise AssertionError(
            f"library-mode bash failed ({completed.returncode}): {completed.stderr}"
        )
    return completed.stdout


def _find_pwsh() -> str:
    found = shutil.which("pwsh")
    if found:
        return found
    # pwsh is installed in this repo's environment as a dotnet global tool.
    candidate = Path.home() / ".dotnet" / "tools" / "pwsh"
    if candidate.is_file() and os.access(candidate, os.X_OK):
        return str(candidate)
    return ""


_PWSH = _find_pwsh()


def _pwsh_skip_or_error() -> str:
    if _PWSH:
        return ""
    if os.environ.get("KINGLET_REQUIRE_PWSH") == "1":
        raise RuntimeError(
            "KINGLET_REQUIRE_PWSH=1 but pwsh was not found — "
            "install it with: dotnet tool install --global PowerShell"
        )
    return "pwsh not installed — skip PowerShell parse/execution tests"


_PWSH_SKIP_REASON = _pwsh_skip_or_error()


def _run_pwsh(body: str) -> str:
    completed = subprocess.run(
        [_PWSH, "-NoProfile", "-NonInteractive", "-Command", body],
        capture_output=True,
        text=True,
        cwd=str(_REPO_ROOT),
        check=False,
    )
    if completed.returncode != 0:
        raise AssertionError(
            f"pwsh failed ({completed.returncode}):\n{completed.stdout}\n{completed.stderr}"
        )
    return completed.stdout


_PS1_LIB_PREAMBLE = (
    ". ./spikes/platform/runtime/run-host.ps1 -LibraryOnly\n"
    ". ./spikes/platform/runtime/measure.ps1 -LibraryOnly\n"
)


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
        # The command array must not embed any hardcoded user home path.
        # Check the current host's home directory and also the generic patterns
        # /home/<word>, /Users/<word>, and Windows C:\Users\<word>.
        home = os.path.expanduser("~")
        self.assertNotIn(home, RUN_HOST,
                         "run-host.sh must not contain the current user's home path")
        self.assertIsNone(
            re.search(r'(/home/\w|/Users/\w|[A-Z]:\\Users\\)', RUN_HOST),
            "run-host.sh must not contain any hardcoded user home path"
        )


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

    def test_environment_triple_is_caller_supplied(self):
        # The Linux triple stays the DEFAULT, but macOS/Windows must be able to
        # override it: coverage matching is an exact match on os/release/arch.
        for flag in ('"--os"', '"--release"', '"--arch"'):
            self.assertIn(flag, BUILD_RECORD)
        self.assertIn('"os": args.os_name', BUILD_RECORD)
        self.assertIn('"release": args.release', BUILD_RECORD)
        self.assertIn('"arch": args.arch', BUILD_RECORD)


class BuildRecordEnvironmentBehaviourTests(unittest.TestCase):
    """Execute build-record.py and assert the environment triple lands in the record."""

    _ASSERTIONS = (
        "manifest.accept-valid", "manifest.reject-unknown", "path.unicode-space",
        "filesystem.atomic-replace", "lease.acquire", "lease.renew",
        "lease.reject-competitor", "lease.expire", "lease.release",
        "process.child-grandchild", "process.cancel", "process.no-descendants",
        "crypto.sha256", "crypto.ed25519", "cleanup.success", "cleanup.crash",
        "cleanup.timeout", "cleanup.cancel",
    )

    def _build(self, tmp: Path, extra: list[str]) -> dict:
        result = tmp / "result.json"
        result.write_text(
            json.dumps(
                {
                    "schema": "kinglet.host-probe.result/v1",
                    "assertions": [
                        {"id": a, "status": "pass"} for a in self._ASSERTIONS
                    ],
                }
            ),
            encoding="utf-8",
        )
        out = tmp / "record.json"
        measure = json.dumps(
            {
                "cold_start_ms": [1] * 30,
                "peak_rss_kb": 2048,
                "artifact_bytes": 100,
                "dependency_count": 0,
            }
        )
        argv = [
            "python3", str(_RUNTIME_DIR / "build-record.py"),
            "--candidate", "go",
            "--version", "1.26.5",
            "--run-id", "20260727T000000Z-runtime-go-test-01",
            "--started-at", "2026-07-27T00:00:00Z",
            "--ended-at", "2026-07-27T00:00:01Z",
            "--artifact-rel", "artifacts/runtime/go/x/result.json",
            "--result-file", str(result),
            "--measure-json", measure,
            "--host-line", "host=test",
            "--kernel-line", "kernel=test",
            "--toolchain-data", "go=1.26.5",
            "--sources-data", "Go|https://go.dev/dl/",
            "--command-data", "measure.sh",
            "--out", str(out),
        ] + extra
        completed = subprocess.run(argv, capture_output=True, text=True, check=False)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(out.read_text(encoding="utf-8"))

    def test_default_environment_is_the_linux_triple(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            record = self._build(Path(tmpdir), [])
        self.assertEqual(record["environment"]["os"], "linux")
        self.assertEqual(record["environment"]["release"], "ubuntu-24.04-noble")
        self.assertEqual(record["environment"]["arch"], "x64")

    def test_macos_environment_triple_is_honoured(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            record = self._build(
                Path(tmpdir),
                ["--os", "macos", "--release", "26.5.2", "--arch", "arm64"],
            )
        self.assertEqual(record["environment"]["os"], "macos")
        self.assertEqual(record["environment"]["release"], "26.5.2")
        self.assertEqual(record["environment"]["arch"], "arm64")

    def test_windows_environment_triple_is_honoured(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            record = self._build(
                Path(tmpdir),
                ["--os", "windows", "--release", "11-25H2", "--arch", "x64"],
            )
        self.assertEqual(record["environment"]["os"], "windows")
        self.assertEqual(record["environment"]["release"], "11-25H2")


# ==========================================================================
# macOS support in the POSIX runner — source text
# ==========================================================================


class RunHostDarwinTextTests(unittest.TestCase):
    def test_accepts_only_darwin_or_linux(self):
        self.assertIn("Linux|Darwin", RUN_HOST)
        self.assertIn("accept only Darwin or Linux", RUN_HOST)

    def test_points_windows_hosts_at_the_powershell_runner(self):
        self.assertIn("run-host.ps1", RUN_HOST)

    def test_uses_sw_vers_for_macos_identity(self):
        self.assertIn("sw_vers -productName", RUN_HOST)
        self.assertIn("sw_vers -productVersion", RUN_HOST)
        self.assertIn("sw_vers -buildVersion", RUN_HOST)

    def test_uses_shasum_on_darwin_and_sha256sum_on_linux(self):
        self.assertIn("shasum -a 256", RUN_HOST)
        self.assertIn("sha256sum", RUN_HOST)

    def test_dotnet_rid_is_not_hardcoded_to_linux(self):
        self.assertIn("osx-arm64", RUN_HOST)
        self.assertIn("osx-x64", RUN_HOST)
        self.assertIn("$DOTNET_RID", RUN_HOST)

    def test_passes_environment_triple_to_the_record_builder(self):
        self.assertIn('--os "$RECORD_OS"', RUN_HOST)
        self.assertIn('--release "$RECORD_RELEASE"', RUN_HOST)
        self.assertIn('--arch "$RECORD_ARCH"', RUN_HOST)

    def test_macos_version_is_recorded_not_hardcoded(self):
        # No macOS version literal may be baked in; the release comes from sw_vers.
        self.assertIsNone(re.search(r'RECORD_RELEASE="\d', RUN_HOST))
        self.assertIn('RECORD_RELEASE="$MACOS_PRODUCT_VERSION"', RUN_HOST)


class MeasureDarwinTextTests(unittest.TestCase):
    def test_uses_time_l_on_darwin(self):
        self.assertIn("/usr/bin/time -l", MEASURE)

    def test_documents_the_bytes_to_kilobytes_conversion(self):
        self.assertIn("1024", MEASURE)
        self.assertIn("rss_kb_from_time_l_output", MEASURE)

    def test_does_not_use_gnu_date_percent_n_on_darwin(self):
        # BSD date has no %3N; a Darwin branch that used it would silently emit
        # a literal string instead of a millisecond clock.
        darwin_branch = MEASURE.split("now_ms_mode_for()", 1)[1]
        self.assertIn("perl", darwin_branch)


# ==========================================================================
# macOS support in the POSIX runner — EXECUTED on this Linux box
# ==========================================================================


class RunHostShellExecutionTests(unittest.TestCase):
    """Run the platform-dependent shell helpers with an injected platform value."""

    def test_supported_platform_accepts_only_darwin_and_linux(self):
        out = _run_shell_lib(
            "run-host.sh",
            'for p in Linux Darwin Windows_NT FreeBSD MINGW64_NT; do\n'
            '  if supported_platform "$p"; then echo "$p=yes"; else echo "$p=no"; fi\n'
            'done',
        )
        self.assertIn("Linux=yes", out)
        self.assertIn("Darwin=yes", out)
        self.assertIn("Windows_NT=no", out)
        self.assertIn("FreeBSD=no", out)
        self.assertIn("MINGW64_NT=no", out)

    def test_dotnet_rid_selection_from_uname_machine(self):
        out = _run_shell_lib(
            "run-host.sh",
            'echo "A=$(dotnet_rid_for Darwin arm64)"\n'
            'echo "B=$(dotnet_rid_for Darwin x86_64)"\n'
            'echo "C=$(dotnet_rid_for Linux x86_64)"\n'
            'echo "D=$(dotnet_rid_for Darwin i386)"\n',
        )
        self.assertIn("A=osx-arm64", out)
        self.assertIn("B=osx-x64", out)
        self.assertIn("C=linux-x64", out)
        self.assertIn("D=unsupported", out)

    def test_record_os_and_arch_mapping(self):
        out = _run_shell_lib(
            "run-host.sh",
            'echo "A=$(record_os_for Darwin)"\n'
            'echo "B=$(record_os_for Linux)"\n'
            'echo "C=$(record_arch_for arm64)"\n'
            'echo "D=$(record_arch_for x86_64)"\n'
            'echo "E=$(record_arch_for ppc64)"\n',
        )
        self.assertIn("A=macos", out)
        self.assertIn("B=linux", out)
        self.assertIn("C=arm64", out)
        self.assertIn("D=x64", out)
        self.assertIn("E=unsupported", out)

    def test_sha256_tool_per_platform(self):
        out = _run_shell_lib(
            "run-host.sh",
            'echo "L=$(sha256_tool_for Linux)"\n'
            'echo "D=$(sha256_tool_for Darwin)"\n',
        )
        self.assertIn("L=sha256sum", out)
        self.assertIn("D=shasum -a 256", out)

    def test_sha256_of_file_matches_hashlib(self):
        import hashlib

        target = _RUNTIME_DIR / "build-record.py"
        expected = hashlib.sha256(target.read_bytes()).hexdigest()
        out = _run_shell_lib(
            "run-host.sh", f'sha256_of_file Linux "{target}"'
        ).strip()
        self.assertEqual(out, expected)

    def test_dotnet_distributable_path_follows_the_rid(self):
        out = _run_shell_lib(
            "run-host.sh",
            'DOTNET_RID=osx-arm64; echo "A=$(dist_of dotnet)"\n'
            'DOTNET_RID=linux-x64; echo "B=$(dist_of dotnet)"\n',
        )
        self.assertIn("A=spikes/platform/runtime/dotnet/bin/Release/net10.0/osx-arm64/publish/kinglet-host-probe", out)
        self.assertIn("B=spikes/platform/runtime/dotnet/bin/Release/net10.0/linux-x64/publish/kinglet-host-probe", out)

    def test_host_slug_distinguishes_the_platforms(self):
        out = _run_shell_lib(
            "run-host.sh",
            'echo "L=$(host_slug_for Linux ubuntu-24.04-noble x64)"\n'
            'echo "D=$(host_slug_for Darwin 26.5.2 arm64)"\n',
        )
        self.assertIn("L=linux-noble", out)
        self.assertIn("D=macos-26.5.2-arm64", out)

    def test_macos_host_line_carries_the_detected_build(self):
        out = _run_shell_lib(
            "run-host.sh", 'macos_host_line macOS 26.5.2 25F74 arm64'
        )
        self.assertIn("26.5.2", out)
        self.assertIn("25F74", out)
        self.assertIn("arm64", out)

    def test_linux_host_gate_is_unchanged(self):
        # Regression net for the existing Linux behaviour: Pop!_OS (ID=pop,
        # ID_LIKE=ubuntu, codename=noble) is accepted, plain ubuntu is accepted,
        # a non-ubuntu distro is refused.
        out = _run_shell_lib(
            "run-host.sh",
            'if linux_host_accepted pop ubuntu noble; then echo POP=yes; else echo POP=no; fi\n'
            'if linux_host_accepted ubuntu "" noble; then echo UBU=yes; else echo UBU=no; fi\n'
            'if linux_host_accepted fedora "" ""; then echo FED=yes; else echo FED=no; fi\n'
            'if linux_host_accepted pop ubuntu jammy; then echo OLD=yes; else echo OLD=no; fi\n',
        )
        self.assertIn("POP=yes", out)
        self.assertIn("UBU=yes", out)
        self.assertIn("FED=no", out)
        self.assertIn("OLD=no", out)


class MeasureShellExecutionTests(unittest.TestCase):
    def test_darwin_time_l_bytes_are_converted_to_kilobytes(self):
        # /usr/bin/time -l on macOS reports BYTES. 2097152 B = 2048 KB. Without the
        # divide the record would claim 2097152 KB and macOS would look 1024x worse
        # than Linux, with nothing downstream to catch it.
        sample = (
            "        1.23 real         0.10 user         0.05 sys\n"
            "           2097152  maximum resident set size\n"
            "                 0  average shared memory size\n"
        )
        out = _run_shell_lib(
            "measure.sh", f'rss_kb_from_time_l_output "{sample}"'
        ).strip()
        self.assertEqual(out, "2048")

    def test_linux_time_v_kbytes_are_used_as_is(self):
        sample = "\tMaximum resident set size (kbytes): 2048\n"
        out = _run_shell_lib(
            "measure.sh", f'rss_kb_from_time_v_output "{sample}"'
        ).strip()
        self.assertEqual(out, "2048")

    def test_rss_dispatch_uses_the_right_parser_per_platform(self):
        darwin_text = "           4194304  maximum resident set size\n"
        linux_text = "\tMaximum resident set size (kbytes): 4096\n"
        out = _run_shell_lib(
            "measure.sh",
            f'echo "D=$(rss_kb_from_output Darwin "{darwin_text}")"\n'
            f'echo "L=$(rss_kb_from_output Linux "{linux_text}")"\n',
        )
        self.assertIn("D=4096", out)
        self.assertIn("L=4096", out)

    def test_missing_rss_line_reports_zero_not_empty(self):
        out = _run_shell_lib(
            "measure.sh",
            'echo "D=$(rss_kb_from_time_l_output "nothing here")"\n'
            'echo "L=$(rss_kb_from_time_v_output "nothing here")"\n',
        )
        self.assertIn("D=0", out)
        self.assertIn("L=0", out)

    def test_time_flag_per_platform(self):
        out = _run_shell_lib(
            "measure.sh",
            'echo "L=$(time_flag_for Linux)"\n'
            'echo "D=$(time_flag_for Darwin)"\n'
            'echo "X=$(time_flag_for FreeBSD)"\n',
        )
        self.assertIn("L=-v", out)
        self.assertIn("D=-l", out)
        self.assertIn("X=unsupported", out)

    def test_millisecond_clock_mode_per_platform(self):
        out = _run_shell_lib(
            "measure.sh",
            'echo "L=$(now_ms_mode_for Linux)"\n'
            'echo "D=$(now_ms_mode_for Darwin)"\n',
        )
        self.assertIn("L=date", out)
        # BSD date cannot do sub-second formatting, so Darwin must not use it.
        self.assertNotIn("D=date", out)
        self.assertTrue("D=perl" in out or "D=python" in out, out)

    def test_now_ms_returns_a_plausible_epoch_millisecond_value(self):
        out = _run_shell_lib("measure.sh", 'now_ms date').strip()
        self.assertRegex(out, r"^\d{13}$")


# ==========================================================================
# Windows runner — source text
# ==========================================================================


class RunHostPowerShellTextTests(unittest.TestCase):
    def test_rejects_wsl_distro_env_var(self):
        self.assertIn("WSL_DISTRO_NAME", RUN_HOST_PS1)

    def test_uses_cim_instance_for_the_host_gate(self):
        self.assertIn("Get-CimInstance -ClassName Win32_OperatingSystem", RUN_HOST_PS1)

    def test_requires_windows_10_or_11(self):
        self.assertIn("Microsoft Windows 10", RUN_HOST_PS1)
        self.assertIn("Microsoft Windows 11", RUN_HOST_PS1)

    def test_uses_get_filehash_for_sha256(self):
        self.assertIn("Get-FileHash -LiteralPath", RUN_HOST_PS1)
        self.assertIn("SHA256", RUN_HOST_PS1)

    def test_requires_empty_run_dir_under_kinglet_local(self):
        self.assertIn(".kinglet/local/spikes", RUN_HOST_PS1)
        self.assertIn("run dir is not empty", RUN_HOST_PS1)

    def test_invokes_all_four_candidates(self):
        self.assertIn("@('python', 'go', 'rust', 'dotnet')", RUN_HOST_PS1)

    def test_invokes_black_box_conformance_and_publish(self):
        self.assertIn("tools.kinglet_spike.runtime_contract", RUN_HOST_PS1)
        self.assertIn("'tools.kinglet_spike', 'publish'", RUN_HOST_PS1)

    def test_reuses_the_shared_record_builder(self):
        self.assertIn("build-record.py", RUN_HOST_PS1)
        self.assertIn("'--os'", RUN_HOST_PS1)
        self.assertIn("'--release'", RUN_HOST_PS1)
        self.assertIn("'--arch'", RUN_HOST_PS1)

    def test_strips_toolchain_dirs_from_child_path(self):
        self.assertIn("Get-StrippedPath", RUN_HOST_PS1)
        self.assertIn("ToolchainCommands", RUN_HOST_PS1)
        self.assertIn("$env:PATH = $RunPath", RUN_HOST_PS1)
        self.assertIn("$env:PATH = $savedPath", RUN_HOST_PS1)

    def test_supports_a_dry_run(self):
        self.assertIn("$DryRun", RUN_HOST_PS1)
        self.assertIn("Alias('WhatIf')", RUN_HOST_PS1)
        self.assertIn("dry-run complete; nothing published", RUN_HOST_PS1)

    def test_windows_distributable_has_the_exe_suffix(self):
        self.assertIn("kinglet-host-probe.exe", RUN_HOST_PS1)

    def test_never_invokes_bash_or_wsl(self):
        for text in (RUN_HOST_PS1, MEASURE_PS1):
            self.assertIsNone(
                re.search(r"(?i)-FilePath\s+['\"]?(bash|wsl|cmd)\b", text)
            )
            self.assertIsNone(re.search(r"(?i)\b(bash|wsl|cmd)\.exe\b", text))
            self.assertNotIn("Invoke-Expression", text)

    def test_no_bom_emitting_utf8_encoding(self):
        # [System.Text.Encoding]::UTF8 writes a BOM; a BOM on a text file has
        # already broken create-project.ps1 in this repo.
        for text in (RUN_HOST_PS1, MEASURE_PS1):
            self.assertNotIn("[System.Text.Encoding]::UTF8", text)
            self.assertIn("UTF8Encoding($false)", text)

    def test_path_cmdlets_use_literal_path(self):
        # A '[' or ']' in a Windows path is a wildcard to -Path but not -LiteralPath.
        for text, name in ((RUN_HOST_PS1, "run-host.ps1"), (MEASURE_PS1, "measure.ps1")):
            for cmdlet in (
                "Test-Path", "Get-Item", "Copy-Item", "Get-FileHash",
                "Get-ChildItem", "Remove-Item", "Resolve-Path",
                "Get-ItemProperty", "Set-Location",
            ):
                for match in re.finditer(re.escape(cmdlet) + r"\s+(-\w+)", text):
                    self.assertEqual(
                        match.group(1), "-LiteralPath",
                        f"{name}: {cmdlet} must use -LiteralPath, saw {match.group(1)}",
                    )

    def test_start_process_uses_an_argument_array(self):
        for text in (RUN_HOST_PS1, MEASURE_PS1):
            for match in re.finditer(r"Start-Process[^\n]*", text):
                if "-ArgumentList" in match.group(0):
                    self.assertIn("-ArgumentList @(", match.group(0))

    def test_no_hardcoded_machine_path_or_credential(self):
        for text in (RUN_HOST_PS1, MEASURE_PS1):
            self.assertIsNone(
                re.search(r"(/Users/|/home/|[A-Z]:\\Users\\|gh[pousr]_|sk-)", text)
            )

    def test_no_hardcoded_windows_build_number(self):
        # The exact build must be DETECTED and recorded, never baked in.
        self.assertIn("Get-WindowsDisplayVersion", RUN_HOST_PS1)
        self.assertIn("$osInfo.BuildNumber", RUN_HOST_PS1)
        self.assertIsNone(re.search(r"\b(19045|22621|22631|26100|26200)\b", RUN_HOST_PS1))


class MeasurePowerShellTextTests(unittest.TestCase):
    def test_collects_thirty_cold_start_samples(self):
        self.assertIn("ColdStartSampleCount = 30", MEASURE_PS1)

    def test_uses_measure_command(self):
        self.assertIn("Measure-Command", MEASURE_PS1)

    def test_uses_peak_working_set(self):
        self.assertIn("PeakWorkingSet64", MEASURE_PS1)

    def test_converts_bytes_to_kilobytes(self):
        self.assertIn("Convert-BytesToKilobytes", MEASURE_PS1)
        self.assertIn("1024", MEASURE_PS1)

    def test_emits_expected_json_keys(self):
        for key in ("cold_start_ms", "peak_rss_kb", "artifact_bytes", "dependency_count"):
            self.assertIn(key, MEASURE_PS1)

    def test_refuses_to_emit_a_zero_peak_measurement(self):
        self.assertIn("refusing to emit a fabricated measurement", MEASURE_PS1)


# ==========================================================================
# Windows runner — EXECUTED under pwsh
# ==========================================================================


@unittest.skipIf(_PWSH_SKIP_REASON, _PWSH_SKIP_REASON)
class PowerShellParseTests(unittest.TestCase):
    def test_both_scripts_parse_without_errors(self):
        out = _run_pwsh(
            "$errs = $null; $toks = $null\n"
            "foreach ($f in @('spikes/platform/runtime/run-host.ps1',"
            "'spikes/platform/runtime/measure.ps1')) {\n"
            "  $null = [System.Management.Automation.Language.Parser]::ParseFile("
            "(Resolve-Path -LiteralPath $f).ProviderPath, [ref]$toks, [ref]$errs)\n"
            "  Write-Output ('{0}|errors={1}' -f $f, $errs.Count)\n"
            "  foreach ($e in $errs) { Write-Output ('  ' + $e.Message) }\n"
            "}"
        )
        self.assertIn("run-host.ps1|errors=0", out)
        self.assertIn("measure.ps1|errors=0", out)


@unittest.skipIf(_PWSH_SKIP_REASON, _PWSH_SKIP_REASON)
class PowerShellHelperExecutionTests(unittest.TestCase):
    """Dot-source the .ps1 helpers and drive them with a table of inputs."""

    def test_windows_caption_gate_accepts_10_and_11_only(self):
        table = [
            ("Microsoft Windows 10 Pro", "True"),
            ("Microsoft Windows 10 Enterprise LTSC 2021", "True"),
            ("Microsoft Windows 11 Pro", "True"),
            ("Microsoft Windows 11", "True"),
            ("Microsoft Windows Server 2022 Standard", "False"),
            ("Microsoft Windows 8.1", "False"),
            ("Microsoft Windows 7 Ultimate", "False"),
            ("Microsoft Windows 100", "False"),
            ("Ubuntu 24.04", "False"),
            ("", "False"),
        ]
        body = _PS1_LIB_PREAMBLE + "".join(
            f"Write-Output ('{i}=' + (Test-LockedWindowsCaption -Caption '{caption}'))\n"
            for i, (caption, _) in enumerate(table)
        )
        out = _run_pwsh(body)
        for index, (caption, expected) in enumerate(table):
            self.assertIn(f"{index}={expected}", out, f"caption={caption!r}")

    def test_windows_release_is_composed_from_caption_and_display_version(self):
        body = _PS1_LIB_PREAMBLE + (
            "Write-Output ('A=' + (Get-WindowsRelease -Caption 'Microsoft Windows 11 Pro' -DisplayVersion '25H2'))\n"
            "Write-Output ('B=' + (Get-WindowsRelease -Caption 'Microsoft Windows 10 Pro' -DisplayVersion '22h2'))\n"
            "Write-Output ('C=[' + (Get-WindowsRelease -Caption 'Microsoft Windows Server 2022' -DisplayVersion '22H2') + ']')\n"
            "Write-Output ('D=[' + (Get-WindowsRelease -Caption 'Microsoft Windows 11 Pro' -DisplayVersion '') + ']')\n"
        )
        out = _run_pwsh(body)
        # Both locked Windows hosts must be derivable, and they must differ.
        self.assertIn("A=11-25H2", out)
        self.assertIn("B=10-22H2", out)
        # A non-locked caption yields no release at all — the runner then refuses.
        self.assertIn("C=[]", out)
        self.assertIn("D=[]", out)

    def test_dotnet_rid_selection_from_processor_architecture(self):
        body = _PS1_LIB_PREAMBLE + (
            "Write-Output ('A=' + (Get-DotnetRid -Architecture 'AMD64'))\n"
            "Write-Output ('B=' + (Get-DotnetRid -Architecture 'ARM64'))\n"
            "Write-Output ('C=' + (Get-DotnetRid -Architecture 'x86'))\n"
            "Write-Output ('D=' + (Get-RecordArch -Architecture 'AMD64'))\n"
            "Write-Output ('E=' + (Get-RecordArch -Architecture 'ARM64'))\n"
            "Write-Output ('F=' + (Get-RecordArch -Architecture 'x86'))\n"
        )
        out = _run_pwsh(body)
        self.assertIn("A=win-x64", out)
        self.assertIn("B=win-arm64", out)
        self.assertIn("C=unsupported", out)
        self.assertIn("D=x64", out)
        self.assertIn("E=arm64", out)
        self.assertIn("F=unsupported", out)

    def test_dotnet_distributable_path_follows_the_rid(self):
        body = _PS1_LIB_PREAMBLE + (
            "Write-Output ('A=' + (Get-CandidateDistributable -Candidate 'dotnet' -DotnetRid 'win-x64'))\n"
            "Write-Output ('B=' + (Get-CandidateDistributable -Candidate 'go' -DotnetRid 'win-x64'))\n"
        )
        out = _run_pwsh(body)
        self.assertIn(
            "A=spikes/platform/runtime/dotnet/bin/Release/net10.0/win-x64/publish/kinglet-host-probe.exe",
            out,
        )
        self.assertIn("B=spikes/platform/runtime/go/dist/kinglet-host-probe.exe", out)

    def test_path_stripping_is_case_insensitive_and_drops_empty_entries(self):
        body = _PS1_LIB_PREAMBLE + (
            "$p = 'D:\\toolchains\\go\\bin;D:\\toolchains\\cargo\\bin\\;D:\\Windows;;D:\\Windows\\System32'\n"
            "Write-Output ('A=[' + (Get-StrippedPath -Path $p -ToolchainDirectory "
            "@('d:\\TOOLCHAINS\\go\\BIN','D:\\toolchains\\cargo\\bin')) + ']')\n"
            "Write-Output ('B=[' + (Get-StrippedPath -Path $p -ToolchainDirectory @()) + ']')\n"
        )
        out = _run_pwsh(body)
        self.assertIn("A=[D:\\Windows;D:\\Windows\\System32]", out)
        # With nothing to strip only the empty entry disappears.
        self.assertIn(
            "B=[D:\\toolchains\\go\\bin;D:\\toolchains\\cargo\\bin\\;D:\\Windows;D:\\Windows\\System32]",
            out,
        )

    def test_run_id_and_host_slug(self):
        body = _PS1_LIB_PREAMBLE + (
            "Write-Output ('A=' + (Get-HostSlug -Release '11-25H2' -Arch 'x64'))\n"
            "Write-Output ('B=' + (Get-HostSlug -Release '10-22H2' -Arch 'x64'))\n"
            "Write-Output ('C=' + (Get-RunId -Stamp '20260727T000000Z' -Candidate 'go' "
            "-HostSlug 'windows-11-25h2-x64'))\n"
        )
        out = _run_pwsh(body)
        self.assertIn("A=windows-11-25h2-x64", out)
        self.assertIn("B=windows-10-22h2-x64", out)
        self.assertIn("C=20260727T000000Z-runtime-go-windows-11-25h2-x64-01", out)

    def test_run_id_is_a_safe_publication_component(self):
        out = _run_pwsh(
            _PS1_LIB_PREAMBLE
            + "Write-Output (Get-RunId -Stamp '20260727T000000Z' -Candidate 'dotnet' "
              "-HostSlug (Get-HostSlug -Release '11-25H2' -Arch 'x64'))"
        ).strip()
        # tools/kinglet_spike/validate.py::SAFE_COMPONENT
        self.assertRegex(out, r"^[A-Za-z0-9][A-Za-z0-9._-]*$")

    def test_bytes_to_kilobytes_conversion(self):
        body = _PS1_LIB_PREAMBLE + (
            "Write-Output ('A=' + (Convert-BytesToKilobytes -Bytes 2097152))\n"
            "Write-Output ('B=' + (Convert-BytesToKilobytes -Bytes 1024))\n"
            "Write-Output ('C=' + (Convert-BytesToKilobytes -Bytes 1))\n"
            "Write-Output ('D=' + (Convert-BytesToKilobytes -Bytes 1536))\n"
            "Write-Output ('E=' + (Convert-BytesToKilobytes -Bytes 0))\n"
        )
        out = _run_pwsh(body)
        # PeakWorkingSet64 is BYTES; peak_rss_kb is KILOBYTES on every platform.
        self.assertIn("A=2048", out)
        self.assertIn("B=1", out)
        self.assertIn("C=1", out)
        self.assertIn("D=2", out)
        self.assertIn("E=0", out)

    def test_sample_milliseconds_are_positive_integers(self):
        body = _PS1_LIB_PREAMBLE + (
            "Write-Output ('A=' + (ConvertTo-SampleMilliseconds -TotalMilliseconds 0.2))\n"
            "Write-Output ('B=' + (ConvertTo-SampleMilliseconds -TotalMilliseconds 0))\n"
            "Write-Output ('C=' + (ConvertTo-SampleMilliseconds -TotalMilliseconds 12.7))\n"
        )
        out = _run_pwsh(body)
        self.assertIn("A=1", out)
        self.assertIn("B=1", out)
        self.assertIn("C=13", out)

    def test_measurement_json_is_parseable_and_matches_the_shell_shape(self):
        body = _PS1_LIB_PREAMBLE + (
            "Write-Output (Format-MeasurementJson -ColdStartMs @(3,4,5) -PeakRssKb 2048 "
            "-ArtifactBytes 123456 -DependencyCount 12)"
        )
        out = _run_pwsh(body).strip()
        parsed = json.loads(out)
        self.assertEqual(parsed["cold_start_ms"], [3, 4, 5])
        self.assertEqual(parsed["peak_rss_kb"], 2048)
        self.assertEqual(parsed["artifact_bytes"], 123456)
        self.assertEqual(parsed["dependency_count"], 12)
        self.assertEqual(
            out,
            '{"cold_start_ms":[3,4,5],"peak_rss_kb":2048,"artifact_bytes":123456,'
            '"dependency_count":12}',
        )

    def test_cold_start_sampler_runs_the_executable_the_requested_number_of_times(self):
        # Executes the real sampling loop (with a small count) against a real
        # process. The 30-sample production value is asserted separately.
        marker = shutil.which("true")
        if not marker:
            self.skipTest("no 'true' executable on PATH")
        body = _PS1_LIB_PREAMBLE + (
            f"$s = Measure-ColdStartSamples -Exe '{marker}' -VersionArg '--version' -SampleCount 4\n"
            "Write-Output ('COUNT=' + $s.Count)\n"
            "Write-Output ('MIN=' + ($s | Measure-Object -Minimum).Minimum)\n"
        )
        out = _run_pwsh(body)
        self.assertIn("COUNT=4", out)
        # Every sample must be a positive integer (the record schema requires it).
        minimum = int(re.search(r"MIN=(\d+)", out).group(1))
        self.assertGreaterEqual(minimum, 1)


class ForeignHostOnlyTests(unittest.TestCase):
    """Placeholders for the checks that genuinely need the foreign OS."""

    @unittest.skipUnless(
        os.uname().sysname == "Darwin" if hasattr(os, "uname") else False,
        "needs a real macOS host: sw_vers and /usr/bin/time -l cannot be run here",
    )
    def test_macos_sw_vers_gate(self):  # pragma: no cover - macOS only
        out = _run_shell_lib("run-host.sh", "gate_darwin; echo \"$RECORD_RELEASE\"")
        self.assertTrue(out.strip())

    @unittest.skipUnless(
        os.name == "nt",
        "needs a real Windows host: Win32_OperatingSystem, the registry "
        "DisplayVersion, and a post-exit PeakWorkingSet64 read are unavailable here",
    )
    def test_windows_host_gate(self):  # pragma: no cover - Windows only
        out = _run_pwsh(
            _PS1_LIB_PREAMBLE + "Write-Output (Resolve-HostEnvironment).RecordRelease"
        )
        self.assertRegex(out.strip(), r"^(10|11)-\w+$")


if __name__ == "__main__":
    unittest.main()
