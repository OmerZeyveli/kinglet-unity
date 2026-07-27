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


def _run_shell_lib_raw(
    script: str, body: str, env: dict | None = None
) -> subprocess.CompletedProcess:
    """Source a runner in library mode and run `body`; return the whole result.

    Used by the refusal tests, which assert on a NON-zero exit status.
    """
    if script == "run-host.sh":
        env_flag = "KINGLET_RUNHOST_LIB=1"
    else:
        env_flag = "KINGLET_MEASURE_LIB=1"
    path = _RUNTIME_DIR / script
    program = f'{env_flag} . "{path}"\n{body}\n'
    child_env = dict(os.environ)
    if env:
        child_env.update(env)
    return subprocess.run(
        ["bash", "-c", program],
        capture_output=True,
        text=True,
        cwd=str(_REPO_ROOT),
        env=child_env,
        check=False,
    )


def _run_shell_lib(script: str, body: str, env: dict | None = None) -> str:
    """Source a runner in library mode and run `body`; return stdout."""
    completed = _run_shell_lib_raw(script, body, env)
    if completed.returncode != 0:
        raise AssertionError(
            f"library-mode bash failed ({completed.returncode}): {completed.stderr}"
        )
    return completed.stdout


def _make_uname_shim(directory: Path, sysname: str, release: str, machine: str) -> None:
    """Write a `uname` shim so the runner's own platform detection can be driven.

    This is what makes the END-TO-END refusal tests possible: run-host.sh is invoked
    for real, main() calls gate_host() for real, and the platform it sees is ours.
    A gate tested only through the predicate it calls does not notice a deleted call.
    """
    shim = directory / "uname"
    shim.write_text(
        "#!/usr/bin/env bash\n"
        "case \"${1:-}\" in\n"
        f"  -s) echo {sysname} ;;\n"
        f"  -r) echo {release} ;;\n"
        f"  -m) echo {machine} ;;\n"
        f"  *)  echo {sysname} ;;\n"
        "esac\n",
        encoding="utf-8",
    )
    shim.chmod(0o755)


def _make_sw_vers_shim(
    directory: Path, product_name: str, product_version: str, build_version: str
) -> None:
    shim = directory / "sw_vers"
    shim.write_text(
        "#!/usr/bin/env bash\n"
        "case \"${1:-}\" in\n"
        f"  -productName)    echo '{product_name}' ;;\n"
        f"  -productVersion) echo '{product_version}' ;;\n"
        f"  -buildVersion)   echo '{build_version}' ;;\n"
        "esac\n",
        encoding="utf-8",
    )
    shim.chmod(0o755)


def _run_run_host(shim_dir: Path, args: list[str], env: dict | None = None):
    """Invoke run-host.sh for real with `shim_dir` first on PATH."""
    child_env = dict(os.environ)
    child_env["PATH"] = f"{shim_dir}{os.pathsep}{child_env['PATH']}"
    child_env.pop("WSL_DISTRO_NAME", None)
    if env:
        child_env.update(env)
    return subprocess.run(
        ["bash", str(_RUNTIME_DIR / "run-host.sh")] + args,
        capture_output=True,
        text=True,
        cwd=str(_REPO_ROOT),
        env=child_env,
        check=False,
    )


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


def _run_pwsh_raw(body: str, cwd: Path | None = None) -> subprocess.CompletedProcess:
    """Run `body` under pwsh and return the whole result, failures included.

    `_run_pwsh` raises on a non-zero exit, which is exactly what the REFUSAL tests
    need to inspect, and `cwd` lets a test drive the runner from a scratch
    directory so a non-dry-run cell writes nothing into the repository.
    """
    return subprocess.run(
        [_PWSH, "-NoProfile", "-NonInteractive", "-Command", body],
        capture_output=True,
        text=True,
        cwd=str(cwd or _REPO_ROOT),
        check=False,
    )


def _run_pwsh_file(args: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    """Execute a .ps1 as a SCRIPT, the way the runner is actually invoked.

    `-Command` with a dot-source never reaches the bottom-of-file entry point, so a
    dot-sourcing test cannot see anything about how (or whether) that entry point
    is wired. `-File` runs the script exactly as an operator would.
    """
    return subprocess.run(
        [_PWSH, "-NoProfile", "-NonInteractive", "-File"] + args,
        capture_output=True,
        text=True,
        cwd=str(cwd or _REPO_ROOT),
        check=False,
    )


def _ps_fact_literal(fact: dict) -> str:
    pairs = "; ".join(f"{k} = '{v}'" for k, v in fact.items())
    return "[pscustomobject]@{ " + pairs + " }"


# The locked Windows 11 host, as Get-LiveHostFact would report it.
_ACCEPTED_WINDOWS_FACT = {
    "Caption": "Microsoft Windows 11 Pro",
    "Version": "10.0.26200",
    "BuildNumber": "26200",
    "Ubr": "1742",
    "DisplayVersion": "25H2",
    "Architecture": "AMD64",
    "WslDistroName": "",
}


def _join_ps_continuations(text: str) -> str:
    """Join PowerShell backtick line-continuations into single logical lines.

    A regex anchored with `[^\\n]*` stops at the newline, so a command split across
    a continuation is only half-inspected — and this repo's real code already uses
    backtick continuations, so that is not a hypothetical shape.
    """
    return re.sub(r"`\r?\n\s*", " ", text)


def _strip_ps_comments(text: str) -> str:
    """Remove <# block #> and # line comments, so prose cannot satisfy a code check.

    The BOM assertion previously passed because the only occurrence of the literal
    in each file was a comment describing the rule — a comment standing in for the
    code it describes.
    """
    without_blocks = re.sub(r"<#.*?#>", "", text, flags=re.DOTALL)
    lines = []
    for line in without_blocks.splitlines():
        # Not inside a string literal: these scripts have no '#' in any string.
        lines.append(re.sub(r"#.*$", "", line))
    return "\n".join(lines)


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


class RunHostGateRefusalTests(unittest.TestCase):
    """The host gate's REFUSAL path, executed end-to-end.

    The brief's central anti-fabrication invariant is that a runner must refuse a
    non-locked host rather than proceed. Asserting the refusal message exists in the
    source does not test it: deleting the `if ! supported_platform` block, or the
    `command -v sw_vers` check, leaves every such assertion green. These tests run
    run-host.sh for real behind a `uname` shim, so main() -> gate_host() -> the
    refusal is the code path under test.
    """

    def _refuses(self, sysname, release="6.0.0-generic", machine="x86_64", **kw):
        with tempfile.TemporaryDirectory() as tmpdir:
            shim_dir = Path(tmpdir)
            _make_uname_shim(shim_dir, sysname, release, machine)
            for name, value in kw.pop("shims", {}).items():
                (shim_dir / name).write_text(value, encoding="utf-8")
                (shim_dir / name).chmod(0o755)
            return _run_run_host(shim_dir, ["--dry-run"], kw.get("env"))

    def test_refuses_an_unsupported_platform(self):
        for sysname in ("Windows_NT", "FreeBSD", "MINGW64_NT", "SunOS"):
            with self.subTest(platform=sysname):
                result = self._refuses(sysname)
                self.assertNotEqual(
                    result.returncode, 0,
                    f"{sysname} must be REFUSED, not run: {result.stdout}{result.stderr}",
                )
                self.assertIn("unsupported platform", result.stderr)
                # Nothing downstream may have been reached.
                self.assertNotIn("DRY-RUN", result.stderr)

    def test_points_a_windows_host_at_the_powershell_runner(self):
        result = self._refuses("Windows_NT")
        self.assertIn("run-host.ps1", result.stderr)

    def test_refuses_wsl_via_the_environment_variable(self):
        result = self._refuses("Linux", env={"WSL_DISTRO_NAME": "Ubuntu-24.04"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing to run under WSL", result.stderr)
        self.assertNotIn("DRY-RUN", result.stderr)

    def test_refuses_wsl_via_the_kernel_release(self):
        result = self._refuses("Linux", release="5.15.0-microsoft-standard-WSL2")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing to run under WSL", result.stderr)
        self.assertNotIn("DRY-RUN", result.stderr)

    def test_refuses_an_unsupported_architecture(self):
        result = self._refuses("Linux", machine="ppc64")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unsupported machine architecture", result.stderr)
        self.assertNotIn("DRY-RUN", result.stderr)

    def test_darwin_is_refused_when_sw_vers_is_absent(self):
        # gate_darwin must REFUSE a host it cannot identify. Without the
        # `command -v sw_vers` check the runner would proceed with an empty
        # RECORD_RELEASE and publish a record for a host it never verified.
        with tempfile.TemporaryDirectory() as tmpdir:
            shim_dir = Path(tmpdir)
            _make_uname_shim(shim_dir, "Darwin", "24.0.0", "arm64")
            # No sw_vers shim is written, and this Linux host has no sw_vers.
            self.assertIsNone(shutil.which("sw_vers"), "unexpected sw_vers on this host")
            result = _run_run_host(shim_dir, ["--dry-run"])
        self.assertNotEqual(
            result.returncode, 0,
            f"a macOS host without sw_vers must be refused: {result.stderr}",
        )
        self.assertIn("sw_vers is not available", result.stderr)
        self.assertNotIn("DRY-RUN", result.stderr)

    def test_darwin_is_refused_when_sw_vers_reports_no_product_version(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            shim_dir = Path(tmpdir)
            _make_uname_shim(shim_dir, "Darwin", "24.0.0", "arm64")
            _make_sw_vers_shim(shim_dir, "macOS", "", "25F74")
            result = _run_run_host(shim_dir, ["--dry-run"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("returned nothing", result.stderr)
        self.assertNotIn("DRY-RUN", result.stderr)

    def test_darwin_dry_run_uses_the_detected_version_and_the_osx_rid(self):
        # The accepting half of the same gate: a real macOS-shaped host runs the
        # whole Darwin branch on this Linux box and the record triple, the RID and
        # the host slug all follow the DETECTED version rather than a literal.
        with tempfile.TemporaryDirectory() as tmpdir:
            shim_dir = Path(tmpdir)
            _make_uname_shim(shim_dir, "Darwin", "24.0.0", "arm64")
            _make_sw_vers_shim(shim_dir, "macOS", "26.5.2", "25F74")
            result = _run_run_host(shim_dir, ["--dry-run"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("host accepted: macOS macOS 26.5.2 (build=25F74; arch=arm64", result.stderr)
        self.assertIn(
            "platform=Darwin machine=arm64 rid=osx-arm64 os=macos release=26.5.2 arch=arm64",
            result.stderr,
        )
        self.assertIn("macos-26.5.2-arm64", result.stderr)
        # The dotnet distributable path must follow the macOS RID, not linux-x64.
        self.assertIn("net10.0/osx-arm64/publish/kinglet-host-probe", result.stderr)
        self.assertNotIn("linux-x64", result.stderr)
        # All four candidates still planned.
        for candidate in ("python", "go", "rust", "dotnet"):
            self.assertIn(f"DRY-RUN {candidate}:", result.stderr)

    @staticmethod
    def _tree_snapshot() -> dict:
        """Every tracked path under the runtime dir with its size and mtime.

        A filesystem snapshot rather than `git status`, so the check is meaningful
        when the tree is not a git checkout (which is exactly the situation in a
        mutation-testing copy — there it silently errored on every run instead of
        checking anything).
        """
        snapshot = {}
        for path in sorted((_REPO_ROOT / "spikes").rglob("*")):
            if path.is_file():
                stat = path.stat()
                snapshot[str(path)] = (stat.st_size, stat.st_mtime_ns)
        return snapshot

    def test_darwin_dry_run_mutates_nothing_outside_kinglet_local(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            shim_dir = Path(tmpdir)
            _make_uname_shim(shim_dir, "Darwin", "24.0.0", "arm64")
            _make_sw_vers_shim(shim_dir, "macOS", "26.5.2", "25F74")
            before = self._tree_snapshot()
            self.assertTrue(before, "snapshot must not be vacuously empty")
            result = _run_run_host(shim_dir, ["--dry-run"])
            after = self._tree_snapshot()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, after, "the Darwin dry-run modified the source tree")


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


class MeasurePeakRssDispatchTests(unittest.TestCase):
    """The bytes->KB conversion at the CALL SITE, not merely at the helper.

    `rss_kb_from_time_l_output` being correct proves nothing if the production
    dispatch hardcodes a platform: feeding BSD `-l` BYTES to the GNU `-v` kbytes
    parser matches nothing, and peak_rss_kb is published as 0 on the exact platform
    this task exists to add. So these drive `measure_peak_rss_kb`, which reads the
    platform itself, with canned /usr/bin/time output.
    """

    _DARWIN_TIME_L = (
        "        1.23 real         0.10 user         0.05 sys\\n"
        "           4194304  maximum resident set size\\n"
    )
    _LINUX_TIME_V = "\\tMaximum resident set size (kbytes): 4096\\n"

    def _dispatch(self, sysname: str, canned: str) -> str:
        """Run measure_peak_rss_kb with `uname` shimmed and time output injected."""
        with tempfile.TemporaryDirectory() as tmpdir:
            shim_dir = Path(tmpdir)
            _make_uname_shim(shim_dir, sysname, "0.0.0", "x86_64")
            body = (
                f'capture_time_output() {{ printf "{canned}"; }}\n'
                'measure_peak_rss_kb /bin/true --version\n'
            )
            return _run_shell_lib(
                "measure.sh", body,
                env={"PATH": f"{shim_dir}{os.pathsep}{os.environ['PATH']}"},
            ).strip()

    def test_darwin_bytes_are_converted_to_kilobytes_by_the_dispatch(self):
        # 4194304 BYTES = 4096 KB. If the dispatch passed a hardcoded 'Linux' the
        # GNU kbytes pattern would not match and this would be '0'.
        self.assertEqual(self._dispatch("Darwin", self._DARWIN_TIME_L), "4096")

    def test_linux_kbytes_are_used_as_is_by_the_dispatch(self):
        self.assertEqual(self._dispatch("Linux", self._LINUX_TIME_V), "4096")

    def test_the_dispatch_does_not_cross_the_parsers(self):
        # The negative half: each platform's parser must reject the OTHER
        # platform's output rather than silently producing a plausible number.
        self.assertEqual(self._dispatch("Darwin", self._LINUX_TIME_V), "0")
        self.assertEqual(self._dispatch("Linux", self._DARWIN_TIME_L), "0")

    def test_the_time_flag_and_the_parser_cannot_disagree(self):
        # measure_peak_rss_kb reads the platform ONCE, so the flag it passes to
        # /usr/bin/time and the parser it selects are always the same platform.
        with tempfile.TemporaryDirectory() as tmpdir:
            shim_dir = Path(tmpdir)
            _make_uname_shim(shim_dir, "Darwin", "0.0.0", "arm64")
            out = _run_shell_lib(
                "measure.sh",
                'capture_time_output() { echo "FLAG=$1"; }\n'
                'measure_peak_rss_kb /bin/true --version > /dev/null\n'
                'capture_time_output() { printf "%s" "FLAG=$1"; }\n'
                'echo "SEEN=$(capture_time_output "$(time_flag_for "$(host_platform)")")"\n',
                env={"PATH": f"{shim_dir}{os.pathsep}{os.environ['PATH']}"},
            )
        self.assertIn("SEEN=FLAG=-l", out)


class MeasureZeroPeakGuardTests(unittest.TestCase):
    """measure.sh must refuse a zero peak, as measure.ps1 already does.

    Without this the POSIX runner would publish `peak_rss_kb: 0` — a placeholder in
    place of a real measurement, which the brief forbids.
    """

    def test_assert_nonzero_peak_rejects_zero_and_accepts_a_real_value(self):
        for value, ok in (("0", False), ("1", True), ("2048", True), ("", False),
                          ("abc", False)):
            with self.subTest(value=value):
                result = _run_shell_lib_raw(
                    "measure.sh", f'assert_nonzero_peak_kb "{value}"'
                )
                if ok:
                    self.assertEqual(result.returncode, 0, result.stderr)
                else:
                    self.assertEqual(result.returncode, 3, result.stdout)
                    self.assertIn("refusing to emit a fabricated measurement",
                                  result.stderr)

    def test_measure_sh_exits_rather_than_emitting_a_zero_peak(self):
        # End-to-end: with `uname` shimmed to Darwin, GNU /usr/bin/time rejects the
        # BSD `-l` flag, so no RSS line is parsed and the peak is 0. measure.sh must
        # exit non-zero and emit NO json rather than publish the zero.
        with tempfile.TemporaryDirectory() as tmpdir:
            shim_dir = Path(tmpdir)
            _make_uname_shim(shim_dir, "Darwin", "0.0.0", "x86_64")
            env = dict(os.environ)
            env["PATH"] = f"{shim_dir}{os.pathsep}{env['PATH']}"
            result = subprocess.run(
                ["bash", str(_RUNTIME_DIR / "measure.sh"), "/bin/true", "0", "--version"],
                capture_output=True, text=True, cwd=str(_REPO_ROOT), env=env,
                check=False,
            )
        self.assertEqual(result.returncode, 3, result.stdout)
        self.assertNotIn("peak_rss_kb", result.stdout)
        self.assertIn("refusing to emit a fabricated measurement", result.stderr)


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

    # The candidate list used to be checked here as an array LITERAL, which says
    # nothing about whether the entry point iterates it — building all four cells
    # from 'python' kept that assertion green. It is now
    # WindowsRunnerEntryPointTests.test_the_entry_point_drives_all_four_candidates,
    # which executes Invoke-RunHost and reads the per-candidate plan back.

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
        # PowerShell's `&` call operator is the IDIOMATIC invocation form, so it is
        # the first case covered — `& wsl cargo build` is the shape that a
        # -FilePath/.exe-only check waves straight through.
        for text, name in ((RUN_HOST_PS1, "run-host.ps1"), (MEASURE_PS1, "measure.ps1")):
            code = _strip_ps_comments(text)
            for pattern, why in (
                (r"(?i)&\s*['\"]?(bash|wsl|cmd|sh|wsl\.exe)\b", "& call operator"),
                (r"(?i)-FilePath\s+['\"]?(bash|wsl|cmd|sh)\b", "-FilePath"),
                (r"(?i)\b(bash|wsl|cmd)\.exe\b", "explicit .exe"),
                (r"(?i)^\s*(bash|wsl|cmd)\s+\S", "bare command invocation"),
                (r"(?i)Start-Process\s+['\"]?(bash|wsl|cmd|sh)\b", "Start-Process"),
            ):
                match = re.search(pattern, code, re.MULTILINE)
                self.assertIsNone(
                    match,
                    f"{name}: must not invoke bash/wsl/cmd ({why}): "
                    f"{match.group(0) if match else ''}",
                )
            self.assertNotIn("Invoke-Expression", code)

    def test_no_bom_emitting_utf8_encoding(self):
        # [System.Text.Encoding]::UTF8 writes a BOM; a BOM on a text file has
        # already broken create-project.ps1 in this repo.
        #
        # The BOM-free encoding is only REQUIRED where a text file is actually
        # written. Asserting the literal unconditionally was satisfied by the prose
        # in each doc-block — neither script writes a text file at all — which is
        # a comment passing for code.
        writers = (
            "Out-File", "Set-Content", "Add-Content", "WriteAllText",
            "WriteAllLines", "StreamWriter", "Export-Csv",
        )
        for text, name in ((RUN_HOST_PS1, "run-host.ps1"), (MEASURE_PS1, "measure.ps1")):
            code = _strip_ps_comments(text)
            self.assertNotIn("[System.Text.Encoding]::UTF8", code)
            used = [w for w in writers if w in code]
            if used:
                self.assertIn(
                    "UTF8Encoding($false)", code,
                    f"{name}: writes a text file ({', '.join(used)}) so it must use "
                    "a BOM-free UTF8Encoding($false)",
                )

    def test_path_cmdlets_use_literal_path(self):
        # A '[' or ']' in a Windows path is a wildcard to -Path but not -LiteralPath.
        for text, name in ((RUN_HOST_PS1, "run-host.ps1"), (MEASURE_PS1, "measure.ps1")):
            joined = _join_ps_continuations(text)
            for cmdlet in (
                "Test-Path", "Get-Item", "Copy-Item", "Get-FileHash",
                "Get-ChildItem", "Remove-Item", "Resolve-Path",
                "Get-ItemProperty", "Set-Location", "Split-Path",
            ):
                for match in re.finditer(re.escape(cmdlet) + r"\s+(-\w+)", joined):
                    self.assertEqual(
                        match.group(1), "-LiteralPath",
                        f"{name}: {cmdlet} must use -LiteralPath, saw {match.group(1)}",
                    )

    def test_new_item_is_not_used_for_paths(self):
        # New-Item has no -LiteralPath, so a '[' in a Windows path would be read as
        # a wildcard. [System.IO.Directory]::CreateDirectory takes a literal path.
        for text, name in ((RUN_HOST_PS1, "run-host.ps1"), (MEASURE_PS1, "measure.ps1")):
            code = _strip_ps_comments(text)
            self.assertNotIn(
                "New-Item", code,
                f"{name}: New-Item cannot take -LiteralPath; use "
                "[System.IO.Directory]::CreateDirectory",
            )

    def test_start_process_uses_an_argument_array(self):
        # Joined across backtick continuations: the real Start-Process call in
        # measure.ps1 already spans three physical lines, so a newline-anchored
        # regex inspects only the first of them.
        seen = 0
        for text, name in ((RUN_HOST_PS1, "run-host.ps1"), (MEASURE_PS1, "measure.ps1")):
            joined = _join_ps_continuations(_strip_ps_comments(text))
            for match in re.finditer(r"Start-Process[^\n]*", joined):
                seen += 1
                self.assertIn(
                    "-ArgumentList", match.group(0),
                    f"{name}: Start-Process must pass arguments explicitly",
                )
                self.assertIn(
                    "-ArgumentList @(", match.group(0),
                    f"{name}: Start-Process must take an argument ARRAY, never a "
                    f"string-evaluated command line: {match.group(0)}",
                )
        # The assertion must not be vacuous: measure.ps1 really does Start-Process.
        self.assertGreaterEqual(seen, 1, "no Start-Process call found to check")

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

    def test_all_four_candidates_are_driven(self):
        # Executed rather than grepped: the candidate list is what the entry point
        # actually iterates.
        out = _run_pwsh(
            _PS1_LIB_PREAMBLE + "Write-Output ('LIST=' + ($script:Candidates -join ','))"
        )
        self.assertIn("LIST=python,go,rust,dotnet", out)

    def test_every_windows_distributable_has_the_exe_suffix(self):
        # A bare `assertIn("kinglet-host-probe.exe", ...)` is satisfied by one
        # occurrence anywhere; the requirement is that EVERY candidate's Windows
        # distributable ends in .exe.
        body = _PS1_LIB_PREAMBLE + "".join(
            f"Write-Output ('{c}=' + (Get-CandidateDistributable -Candidate '{c}' "
            f"-DotnetRid 'win-x64'))\n"
            for c in ("python", "go", "rust", "dotnet")
        )
        out = _run_pwsh(body)
        for candidate in ("python", "go", "rust", "dotnet"):
            match = re.search(rf"^{candidate}=(\S+)$", out, re.MULTILINE)
            self.assertIsNotNone(match, f"no distributable for {candidate}: {out}")
            self.assertTrue(
                match.group(1).endswith("kinglet-host-probe.exe"),
                f"{candidate}: Windows distributable must end in .exe, "
                f"saw {match.group(1)}",
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


@unittest.skipIf(_PWSH_SKIP_REASON, _PWSH_SKIP_REASON)
class WindowsHostGateRefusalTests(unittest.TestCase):
    """The Windows gate's REFUSAL path, executed under pwsh on this Linux box.

    Mirrors what `linux_host_accepted` already had. Previously the only coverage of
    this gate was a regex inside Test-LockedWindowsCaption plus a doc-block string,
    both of which survive DELETING the caller: the caption `throw` could be removed,
    or Assert-NotWsl never called, and the suite stayed green. Resolve-HostEnvironment
    now takes its facts as a parameter, so the whole gate is driven from a table.
    """

    _ACCEPTED = _ACCEPTED_WINDOWS_FACT

    @staticmethod
    def _fact_literal(fact: dict) -> str:
        return _ps_fact_literal(fact)

    def _resolve(self, **overrides) -> subprocess.CompletedProcess:
        fact = dict(self._ACCEPTED)
        fact.update(overrides)
        body = (
            _PS1_LIB_PREAMBLE
            + f"$fact = {self._fact_literal(fact)}\n"
            + "try {\n"
            + "  $resolved = Resolve-HostEnvironment -Fact $fact\n"
            + "  Write-Output ('ACCEPTED=' + $resolved.RecordRelease + '|' + "
              "$resolved.RecordArch + '|' + $resolved.DotnetRid + '|' + "
              "$resolved.HostSlug)\n"
            + "} catch {\n"
            + "  Write-Output ('REFUSED=' + $_.Exception.Message)\n"
            + "}\n"
        )
        return subprocess.run(
            [_PWSH, "-NoProfile", "-NonInteractive", "-Command", body],
            capture_output=True, text=True, cwd=str(_REPO_ROOT), check=False,
        )

    def _assert_refused(self, expected_fragment: str, **overrides):
        result = self._resolve(**overrides)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "REFUSED=", result.stdout,
            f"host must be REFUSED ({overrides}), but was accepted: {result.stdout}",
        )
        self.assertIn(expected_fragment, result.stdout)

    def test_the_locked_host_is_accepted(self):
        result = self._resolve()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "ACCEPTED=11-25H2|x64|win-x64|windows-11-25h2-x64", result.stdout
        )

    def test_the_other_locked_host_is_accepted(self):
        result = self._resolve(
            Caption="Microsoft Windows 10 Pro", DisplayVersion="22H2",
            Version="10.0.19045", BuildNumber="19045",
        )
        self.assertIn("ACCEPTED=10-22H2|x64|win-x64|windows-10-22h2-x64", result.stdout)

    def test_refuses_a_non_locked_caption(self):
        for caption in (
            "Microsoft Windows Server 2022 Standard",
            "Microsoft Windows Server 2019 Datacenter",
            "Microsoft Windows 8.1",
            "Microsoft Windows 7 Ultimate",
            "Microsoft Windows 100",
            "Ubuntu 24.04",
            "",
        ):
            with self.subTest(caption=caption):
                self._assert_refused("host not accepted", Caption=caption)

    def test_refuses_wsl(self):
        # The WSL refusal must fire even on an otherwise perfectly locked host.
        self._assert_refused("refusing to run under WSL", WslDistroName="Ubuntu-24.04")

    def test_refuses_a_host_whose_release_cannot_be_derived(self):
        self._assert_refused("could not derive environment.release", DisplayVersion="")
        self._assert_refused("could not derive environment.release", DisplayVersion="   ")

    def test_refuses_an_unsupported_architecture(self):
        for arch in ("x86", "IA64", "ARM", ""):
            with self.subTest(arch=arch):
                self._assert_refused("unsupported architecture", Architecture=arch)

    def test_the_gate_predicate_refuses_directly(self):
        # Assert-LockedHost is the injectable pure predicate; drive it on its own so
        # a refusal reason cannot be lost by a caller-side edit either.
        body = _PS1_LIB_PREAMBLE + (
            "function T($c,$d,$a,$w) {\n"
            "  try { Assert-LockedHost -Caption $c -DisplayVersion $d -Architecture $a "
            "-WslDistroName $w; return 'OK' } catch { return 'REFUSED' }\n"
            "}\n"
            "Write-Output ('A=' + (T 'Microsoft Windows 11 Pro' '25H2' 'AMD64' ''))\n"
            "Write-Output ('B=' + (T 'Microsoft Windows Server 2022' '25H2' 'AMD64' ''))\n"
            "Write-Output ('C=' + (T 'Microsoft Windows 11 Pro' '25H2' 'AMD64' 'Ubuntu'))\n"
            "Write-Output ('D=' + (T 'Microsoft Windows 11 Pro' '' 'AMD64' ''))\n"
            "Write-Output ('E=' + (T 'Microsoft Windows 11 Pro' '25H2' 'x86' ''))\n"
        )
        out = _run_pwsh(body)
        self.assertIn("A=OK", out)
        for label in ("B", "C", "D", "E"):
            self.assertIn(f"{label}=REFUSED", out)

    def test_no_record_fields_are_produced_for_a_refused_host(self):
        # A refused host must produce NO record at all — not a partial one.
        result = self._resolve(Caption="Microsoft Windows Server 2022 Standard")
        self.assertNotIn("ACCEPTED=", result.stdout)


@unittest.skipIf(_PWSH_SKIP_REASON, _PWSH_SKIP_REASON)
class WindowsAntiFabricationGuardTests(unittest.TestCase):
    """The two guards whose COMPARISON is the invariant, executed.

    Both were previously asserted only by the presence of their message string, so
    inverting the operator left them unfireable and the suite green.
    """

    def test_run_dir_must_be_empty(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            empty = Path(tmpdir) / "empty"
            empty.mkdir()
            dirty = Path(tmpdir) / "dirty"
            dirty.mkdir()
            (dirty / "record.json").write_text("{}", encoding="utf-8")
            hidden = Path(tmpdir) / "hidden"
            hidden.mkdir()
            (hidden / ".leftover").write_text("x", encoding="utf-8")
            missing = Path(tmpdir) / "missing"

            body = _PS1_LIB_PREAMBLE + (
                f"Write-Output ('EMPTY=' + (Test-RunDirEmpty -Path '{empty}'))\n"
                f"Write-Output ('DIRTY=' + (Test-RunDirEmpty -Path '{dirty}'))\n"
                f"Write-Output ('HIDDEN=' + (Test-RunDirEmpty -Path '{hidden}'))\n"
                f"Write-Output ('MISSING=' + (Test-RunDirEmpty -Path '{missing}'))\n"
            )
            out = _run_pwsh(body)
        self.assertIn("EMPTY=True", out)
        # A run dir with content must NOT be reused: that would silently mix a new
        # run's evidence with a previous one's.
        self.assertIn("DIRTY=False", out)
        # -Force: a dot-file is still content.
        self.assertIn("HIDDEN=False", out)
        self.assertIn("MISSING=True", out)

    def test_a_zero_peak_measurement_is_refused(self):
        body = _PS1_LIB_PREAMBLE + (
            "function T($v) { try { Assert-NonZeroPeak -PeakRssKb $v; return 'OK' } "
            "catch { return 'REFUSED' } }\n"
            "Write-Output ('ZERO=' + (T 0))\n"
            "Write-Output ('NEG=' + (T -1))\n"
            "Write-Output ('ONE=' + (T 1))\n"
            "Write-Output ('REAL=' + (T 2048))\n"
        )
        out = _run_pwsh(body)
        # Publishing 0 would be a placeholder in place of a real measurement.
        self.assertIn("ZERO=REFUSED", out)
        self.assertIn("NEG=REFUSED", out)
        self.assertIn("ONE=OK", out)
        self.assertIn("REAL=OK", out)


@unittest.skipIf(_PWSH_SKIP_REASON, _PWSH_SKIP_REASON)
class WindowsRunnerEntryPointTests(unittest.TestCase):
    """The Windows runner's ENTRY POINT, executed — not its helpers, the caller.

    Every other pwsh test here dot-sources with `-LibraryOnly`, which returns
    before `Invoke-RunHost` and before measure.ps1's Main. That left the extracted
    guards well tested and their CALL SITES covered by nothing but
    `assertIn("run dir is not empty", RUN_HOST_PS1)` — a message-string check that
    survives neutering the condition it belongs to, and survives deleting the call
    altogether. An injectable seam whose call site is unchecked is the defect, not
    the fix.

    The POSIX runner never had this hole: `run-host.sh` and `measure.sh` are driven
    end-to-end through a `uname`/`sw_vers` PATH shim. These tests are the
    PowerShell equivalent, and they run on this Linux box because a non-Windows
    host is precisely what the runner must refuse.
    """

    def test_the_production_entry_point_gates_the_live_host(self):
        # run-host.ps1 executed as a SCRIPT, with no injection: the bottom-of-file
        # call must reach Resolve-HostEnvironment against the LIVE host, which on
        # any non-Windows box cannot be resolved. Fabricating $hostEnvironment in
        # Invoke-RunHost — or skipping the gate — makes this dry run SUCCEED here
        # and print four candidate plans.
        result = _run_pwsh_file(
            [str(_RUNTIME_DIR / "run-host.ps1"), "-DryRun"]
        )
        combined = result.stdout + result.stderr
        self.assertNotEqual(
            result.returncode, 0,
            f"a non-Windows host must be REFUSED, not planned: {combined}",
        )
        for forbidden in (
            "DRY-RUN",                      # no candidate cell may be reached
            "host accepted",                # the gate must not have passed
            "dry-run complete",             # the entry point must not have finished
            "published",
        ):
            self.assertNotIn(
                forbidden, combined,
                f"refused host still produced runner output ({forbidden!r}): {combined}",
            )

    def test_the_entry_point_refuses_an_injected_non_locked_host(self):
        # The gate's call site, not the gate: Invoke-RunHost must propagate the
        # refusal before the candidate loop, for every refusal reason.
        for overrides, fragment in (
            ({"Caption": "Microsoft Windows Server 2022 Standard"}, "host not accepted"),
            ({"Caption": "Microsoft Windows 8.1"}, "host not accepted"),
            ({"WslDistroName": "Ubuntu-24.04"}, "refusing to run under WSL"),
            ({"DisplayVersion": ""}, "could not derive environment.release"),
            ({"Architecture": "x86"}, "unsupported architecture"),
        ):
            with self.subTest(**overrides):
                fact = dict(_ACCEPTED_WINDOWS_FACT)
                fact.update(overrides)
                body = (
                    _PS1_LIB_PREAMBLE
                    + f"$fact = {_ps_fact_literal(fact)}\n"
                    + "try { Invoke-RunHost -DryRun -Fact $fact; "
                      "Write-Output 'PLANNED' } "
                      "catch { Write-Output ('REFUSED=' + $_.Exception.Message) }\n"
                )
                result = _run_pwsh_raw(body)
                combined = result.stdout + result.stderr
                self.assertIn("REFUSED=", result.stdout, combined)
                self.assertIn(fragment, result.stdout)
                self.assertNotIn("PLANNED", result.stdout)
                # Nothing may be planned for any candidate.
                self.assertNotIn("DRY-RUN", combined, combined)

    def _dry_run_plan(self, fact: dict) -> str:
        body = (
            _PS1_LIB_PREAMBLE
            + f"$fact = {_ps_fact_literal(fact)}\n"
            + "Invoke-RunHost -DryRun -Fact $fact\n"
        )
        result = _run_pwsh_raw(body)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # Write-Log goes to stderr, matching run-host.sh's log discipline.
        return result.stdout + result.stderr

    def test_the_entry_point_drives_all_four_candidates(self):
        plan = self._dry_run_plan(_ACCEPTED_WINDOWS_FACT)

        # (a) The loop really iterates the four DISTINCT candidates, in order.
        planned = re.findall(r"DRY-RUN (\w+):", plan)
        self.assertEqual(
            planned, ["python", "go", "rust", "dotnet"],
            f"the entry point must drive all four candidates: {plan}",
        )

        # (b) Each cell is built from ITS OWN candidate, not four copies of one.
        #     Passing the same candidate four times would still emit four blocks.
        expected = {
            "python": ("spikes/platform/runtime/python/dist/kinglet-host-probe.exe", "12", "version"),
            "go": ("spikes/platform/runtime/go/dist/kinglet-host-probe.exe", "0", "--version"),
            "rust": ("spikes/platform/runtime/rust/target/release/kinglet-host-probe.exe", "55", "--version"),
            "dotnet": (
                "spikes/platform/runtime/dotnet/bin/Release/net10.0/win-x64/publish/"
                "kinglet-host-probe.exe",
                "4",
                "--version",
            ),
        }
        for candidate, (dist, deps, version_arg) in expected.items():
            with self.subTest(candidate=candidate):
                self.assertIn(f"build: Build-Candidate {candidate} (rid=win-x64)", plan)
                self.assertIn(f"copy distributable: {dist} ->", plan)
                self.assertIn(f"-DependencyCount {deps} -VersionArg {version_arg}", plan)
                # The run id, and therefore the published evidence path, is
                # per-candidate.
                self.assertIn(f"-runtime-{candidate}-windows-11-25h2-x64-01", plan)

        self.assertIn("dry-run complete; nothing published", plan)
        # A dry run must not publish, and must not touch the working tree.
        self.assertNotIn("published OK", plan)
        # ...and it must not have CREATED any of the run dirs it planned. Scoped to
        # the planned paths rather than `git status`, which would be dirty for
        # unrelated reasons and, under a mutation copy in /tmp, would exit 128 and
        # check nothing at all.
        for run_id in set(re.findall(r"run_id=(\S+?)\)", plan)):
            self.assertFalse(
                (_REPO_ROOT / ".kinglet" / "local" / "spikes" / run_id).exists(),
                f"a dry run must not create its run dir: {run_id}",
            )

    def test_the_entry_point_uses_the_resolved_host_not_a_fabricated_one(self):
        # Same code path, the OTHER locked host. Every run id must follow the fact
        # that was resolved; a hardcoded or fabricated $hostEnvironment cannot
        # track both.
        fact = dict(_ACCEPTED_WINDOWS_FACT)
        fact.update(
            Caption="Microsoft Windows 10 Pro", DisplayVersion="22H2",
            Version="10.0.19045", BuildNumber="19045", Ubr="6093",
        )
        plan = self._dry_run_plan(fact)
        self.assertIn("host accepted: Microsoft Windows 10 Pro", plan)
        self.assertIn("release=10-22H2", plan)
        self.assertIn("build=19045.6093", plan)
        slugs = set(re.findall(r"-runtime-\w+-(windows-[a-z0-9.-]+)-01", plan))
        self.assertEqual(
            slugs, {"windows-10-22h2-x64"},
            f"every run id must carry the RESOLVED host slug: {plan}",
        )
        self.assertNotIn("25H2", plan)
        self.assertNotIn("11-25h2", plan)

    def test_the_run_dir_guard_fires_at_its_call_site(self):
        # Invoke-CandidateCell driven for real (build stubbed, distributable faked)
        # in a scratch cwd. Neutering the `if (-not (Test-RunDirEmpty ...))` while
        # keeping the throw string leaves the guard unfireable — and a dirty run
        # dir would silently mix a new run's evidence with a previous run's.
        def cell(dirty: bool) -> str:
            with tempfile.TemporaryDirectory() as tmpdir:
                scratch = Path(tmpdir)
                body = (
                    f". '{_RUNTIME_DIR / 'run-host.ps1'}' -LibraryOnly\n"
                    # Stub the build: this test is about the guard, not the toolchain.
                    "function Build-Candidate { param($Candidate,$DotnetRid,$RepoRoot) }\n"
                    "$he = [pscustomobject]@{ DotnetRid='win-x64'; "
                    "HostSlug='windows-11-25h2-x64'; RecordOs='windows'; "
                    "RecordRelease='11-25H2'; RecordArch='x64'; HostLine='h'; "
                    "KernelLine='k' }\n"
                    "$stamp = '20260727T000000Z'\n"
                    "$dist = Get-CandidateDistributable -Candidate 'go' -DotnetRid 'win-x64'\n"
                    "$null = [System.IO.Directory]::CreateDirectory("
                    "(Split-Path -LiteralPath $dist))\n"
                    "Set-Content -LiteralPath $dist -Value 'not-a-real-binary'\n"
                    "$runRoot = '.kinglet/local/spikes/' + (Get-RunId -Stamp $stamp "
                    "-Candidate 'go' -HostSlug $he.HostSlug)\n"
                )
                if dirty:
                    body += (
                        "$null = [System.IO.Directory]::CreateDirectory($runRoot)\n"
                        "Set-Content -LiteralPath ($runRoot + '/leftover.json') -Value '{}'\n"
                    )
                body += (
                    "try {\n"
                    "  Invoke-CandidateCell -Candidate 'go' -HostEnvironment $he "
                    "-Stamp $stamp -RepoRoot (Get-Location).ProviderPath -RunPath '' "
                    "-PythonCommand 'python3'\n"
                    "  Write-Output 'RESULT=NO-THROW'\n"
                    "} catch { Write-Output ('RESULT=THROW|' + $_.Exception.Message) }\n"
                )
                result = _run_pwsh_raw(body, cwd=scratch)
                return result.stdout

        # A run dir with leftover content must be REFUSED by name.
        self.assertIn("run dir is not empty", cell(dirty=True))
        # Control against a vacuous assertion: with an EMPTY run dir the guard must
        # NOT fire — the cell proceeds past it and fails later, on the fake binary.
        clean = cell(dirty=False)
        self.assertNotIn("run dir is not empty", clean)
        self.assertIn("RESULT=THROW", clean)
        self.assertIn("kinglet-host-probe.exe", clean)

    def test_measure_ps1_exits_rather_than_emitting_a_zero_peak(self):
        # measure.ps1's MAIN, executed. On a non-Windows host PeakWorkingSet64 is
        # unavailable, so the peak is 0 — the anti-fabrication case, for real.
        # Mirrors test_measure_sh_exits_rather_than_emitting_a_zero_peak.
        # `-VersionArg:--version` (colon form): under -File, a bare `--version`
        # would be parsed as another parameter name.
        probe = shutil.which("true")
        if not probe:
            self.skipTest("no 'true' executable on PATH")
        result = _run_pwsh_file([
            str(_RUNTIME_DIR / "measure.ps1"),
            "-Exe", probe, "-DependencyCount", "0", "-VersionArg:--version",
        ])
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn("refusing to emit a fabricated measurement", result.stderr)
        # No JSON at all — not a record with a placeholder 0 in it.
        self.assertNotIn("peak_rss_kb", result.stdout)
        self.assertNotIn("cold_start_ms", result.stdout)

    def test_measure_ps1_refuses_a_missing_executable(self):
        # The other guarded exit in Main, which shares the same failure mode:
        # Write-Error under $ErrorActionPreference='Stop' terminates before its
        # `exit 2`, so the documented status was never actually produced.
        with tempfile.TemporaryDirectory() as tmpdir:
            missing = Path(tmpdir) / "nope.exe"
            result = _run_pwsh_file([
                str(_RUNTIME_DIR / "measure.ps1"),
                "-Exe", str(missing), "-DependencyCount", "0",
                "-VersionArg:--version",
            ])
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("not a file", result.stderr)
        self.assertNotIn("peak_rss_kb", result.stdout)


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
