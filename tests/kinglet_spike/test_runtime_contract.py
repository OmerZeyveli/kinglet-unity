import json
import os
import stat
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.runtime_contract import (
    REQUIRED_ASSERTIONS,
    main,
    run_candidate,
    validate_host_result,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_CONTRACT_DIR = Path("spikes/platform/runtime/contract")


def valid_result() -> dict:
    return {
        "schema": "kinglet.host-probe.result/v1",
        "candidate": {"id": "fake", "version": "1.0.0"},
        "status": "pass",
        "errors": [],
        "assertions": [{"id": item, "status": "pass"} for item in REQUIRED_ASSERTIONS],
        "descendant_pids": [],
        "active_lease": False,
    }


def _write_fake_candidate(tmp_dir: Path, script_body: str) -> Path:
    """Write a Python script with a shebang + chmod +x into tmp_dir.

    ``script_body`` is the Python source AFTER the shebang line.
    """
    exe = tmp_dir / "fake_candidate"
    exe.write_text("#!/usr/bin/env python3\n" + textwrap.dedent(script_body), encoding="utf-8")
    exe.chmod(exe.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return exe


# ---------------------------------------------------------------------------
# Fake candidate script bodies
# ---------------------------------------------------------------------------

_PASSING_CANDIDATE_BODY = """\
import argparse, json, sys
from pathlib import Path

def make_result():
    assertions = [
        "manifest.accept-valid", "manifest.reject-unknown", "path.unicode-space",
        "filesystem.atomic-replace", "lease.acquire", "lease.renew",
        "lease.reject-competitor", "lease.expire", "lease.release",
        "process.child-grandchild", "process.cancel", "process.no-descendants",
        "crypto.sha256", "crypto.ed25519", "cleanup.success", "cleanup.crash",
        "cleanup.timeout", "cleanup.cancel",
    ]
    return {
        "schema": "kinglet.host-probe.result/v1",
        "candidate": {"id": "fake", "version": "0.0.1"},
        "status": "pass",
        "errors": [],
        "assertions": [{"id": a, "status": "pass"} for a in assertions],
        "descendant_pids": [],
        "active_lease": False,
    }

parser = argparse.ArgumentParser()
sub = parser.add_subparsers(dest="cmd")
run_p = sub.add_parser("run")
run_p.add_argument("--contract")
run_p.add_argument("--workspace")
run_p.add_argument("--result")
args = parser.parse_args()
if args.cmd != "run":
    sys.exit(2)
result_path = Path(args.result)
result_path.parent.mkdir(parents=True, exist_ok=True)
result_path.write_text(json.dumps(make_result()), encoding="utf-8")
sys.exit(0)
"""

_NONZERO_CANDIDATE_BODY = """\
import sys
sys.exit(1)
"""

_BAD_RESULT_CANDIDATE_BODY = """\
import argparse, json, sys
from pathlib import Path

parser = argparse.ArgumentParser()
sub = parser.add_subparsers(dest="cmd")
run_p = sub.add_parser("run")
run_p.add_argument("--contract")
run_p.add_argument("--workspace")
run_p.add_argument("--result")
args = parser.parse_args()
if args.cmd != "run":
    sys.exit(2)
result_path = Path(args.result)
result_path.parent.mkdir(parents=True, exist_ok=True)
# Write a result that is missing assertions — validate_host_result will reject it.
bad = {"schema": "kinglet.host-probe.result/v1",
       "candidate": {"id": "bad", "version": "0"},
       "status": "pass", "errors": [],
       "assertions": [],  # empty — missing all required assertions
       "descendant_pids": [], "active_lease": False}
result_path.write_text(json.dumps(bad), encoding="utf-8")
sys.exit(0)
"""


# ---------------------------------------------------------------------------
# Tests — existing validate_host_result suite
# ---------------------------------------------------------------------------

class RuntimeContractTests(unittest.TestCase):
    def test_accepts_complete_pass(self):
        self.assertEqual("pass", validate_host_result(valid_result()).status)

    def test_rejects_missing_assertion(self):
        value = valid_result()
        value["assertions"].pop()
        with self.assertRaisesRegex(EvidenceError, "E_ASSERTION"):
            validate_host_result(value)

    def test_rejects_pass_with_descendant_or_lease(self):
        for field, value in (("descendant_pids", [4123]), ("active_lease", True)):
            result = valid_result()
            result[field] = value
            with self.subTest(field=field):
                with self.assertRaisesRegex(EvidenceError, "E_ASSERTION"):
                    validate_host_result(result)


# ---------------------------------------------------------------------------
# Tests — run_candidate spawn path (fake protocol candidate)
# ---------------------------------------------------------------------------

@unittest.skipIf(sys.platform == "win32", "fake shebang script tests require POSIX")
class RunCandidateTests(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.tmp = Path(self._td.name)

    def tearDown(self):
        self._td.cleanup()

    def _workspace(self) -> Path:
        ws = self.tmp / "workspace"
        ws.mkdir(exist_ok=True)
        return ws

    def test_passing_candidate_returns_host_probe_result(self):
        exe = _write_fake_candidate(self.tmp, _PASSING_CANDIDATE_BODY)
        result = run_candidate(exe, _CONTRACT_DIR, self._workspace())
        self.assertIsNotNone(result)
        self.assertEqual("pass", result.status)
        self.assertEqual(18, len(result.assertions))
        self.assertTrue(all(a.status == "pass" for a in result.assertions))

    def test_nonzero_exit_raises_evidence_error(self):
        exe = _write_fake_candidate(self.tmp, _NONZERO_CANDIDATE_BODY)
        with self.assertRaisesRegex(EvidenceError, "E_CANDIDATE"):
            run_candidate(exe, _CONTRACT_DIR, self._workspace())

    def test_bad_result_raises_evidence_error(self):
        exe = _write_fake_candidate(self.tmp, _BAD_RESULT_CANDIDATE_BODY)
        with self.assertRaisesRegex(EvidenceError, "E_ASSERTION"):
            run_candidate(exe, _CONTRACT_DIR, self._workspace())


# ---------------------------------------------------------------------------
# Tests — main() CLI
# ---------------------------------------------------------------------------

@unittest.skipIf(sys.platform == "win32", "fake shebang script tests require POSIX")
class MainCLITests(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.tmp = Path(self._td.name)

    def tearDown(self):
        self._td.cleanup()

    def test_main_passing_candidate_exits_zero(self):
        exe = _write_fake_candidate(self.tmp, _PASSING_CANDIDATE_BODY)
        workspace = self.tmp / "ws_main"
        workspace.mkdir()
        rc = main([
            "--executable", str(exe),
            "--contract-dir", str(_CONTRACT_DIR),
            "--workspace", str(workspace),
        ])
        self.assertEqual(0, rc)

    def test_main_prints_18_of_18(self, capsys=None):
        """main() must print '18/18 assertions passed'."""
        import io
        from unittest.mock import patch

        exe = _write_fake_candidate(self.tmp, _PASSING_CANDIDATE_BODY)
        workspace = self.tmp / "ws_print"
        workspace.mkdir()
        buf = io.StringIO()
        with patch("sys.stdout", buf):
            rc = main([
                "--executable", str(exe),
                "--contract-dir", str(_CONTRACT_DIR),
                "--workspace", str(workspace),
            ])
        self.assertEqual(0, rc)
        self.assertIn("18/18 assertions passed", buf.getvalue())

    def test_main_bad_executable_exits_two(self):
        rc = main([
            "--executable", str(self.tmp / "does_not_exist"),
            "--contract-dir", str(_CONTRACT_DIR),
        ])
        self.assertEqual(2, rc)
