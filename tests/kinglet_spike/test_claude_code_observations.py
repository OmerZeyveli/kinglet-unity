"""test_claude_code_observations.py — Contract tests for the COMMITTED Claude Code evidence.

test_client_results.py covers the validator against synthetic fixtures. This file
covers the real artefacts on disk: the authored observations document, the published
evidence record, and the published artifact tree.

The invariants worth failing over:
  1. The observations document validates against the frozen 12-case catalog.
  2. Every artifact a *passing* case leans on is actually published, with the
     checksum recorded in the published record matching the bytes on disk.
  3. No case is graded `pass` on the strength of a frozen prompt that was never
     executed. This is the specific fabrication risk this evidence set ran into:
     two cases were summarised as Native/pass from memory, but their prompts were
     never run and no artifact supported them.
  4. Committed evidence carries no absolute user path, credential, or disposable
     probe root.
"""
from __future__ import annotations

import hashlib
import json
import re
import unittest
from pathlib import Path

from tools.kinglet_spike.client_results import (
    OBSERVATIONS_SCHEMA,
    load_client_observations,
)
from tools.kinglet_spike.load import load_record
from tools.kinglet_spike.validate import SECRET_PATTERNS, SENSITIVE_PATH_PATTERNS

REPO = Path(__file__).resolve().parents[2]
OBSERVATIONS = REPO / "spikes/platform/clients/claude-code/observations-linux.json"
CASES = REPO / "spikes/platform/clients/contracts/cases-v1.json"
PLATFORM = REPO / "docs/research/platform-spike"
RUN_ID = "20260727T095800Z-client-probe-claudecode-linux-ubuntu-24.04.4-lts-x64-01"
RECORD = PLATFORM / f"evidence/client/claude-code/{RUN_ID}.json"
ARTIFACTS = PLATFORM / f"artifacts/client/claude-code/{RUN_ID}"

# Frozen prompt each case is scored from, per the runbook's "Cases evidenced" lists.
# A case may only be `pass` if its prompt actually ran.
CASE_PROMPT = {
    "workflow.natural-language": "workflow-natural-language-01",
    "agents.delegation": "agent-delegation-01",
}

# The disposable live-run root must never appear in committed evidence.
PROBE_ROOT = re.compile(r"/tmp/kinglet-live")


def _digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _committed_text_files() -> tuple[Path, ...]:
    paths = [OBSERVATIONS, RECORD]
    paths.extend(sorted(p for p in ARTIFACTS.iterdir() if p.is_file()))
    return tuple(paths)


class ClaudeCodeObservationsTests(unittest.TestCase):
    def setUp(self):
        self.observations = load_client_observations(OBSERVATIONS)
        self.record = load_record(RECORD)
        self.by_id = {case.id: case for case in self.observations.cases}

    # -- 1. schema and coverage -------------------------------------------
    def test_observations_cover_the_frozen_catalog_exactly(self):
        frozen = {case["id"] for case in json.loads(CASES.read_text())["cases"]}
        self.assertEqual(self.observations.schema, OBSERVATIONS_SCHEMA)
        self.assertEqual(set(self.by_id), frozen)
        self.assertEqual(len(self.observations.cases), len(frozen))

    def test_inconclusive_cases_carry_no_grade(self):
        for case in self.observations.cases:
            if case.status == "inconclusive":
                self.assertIsNone(
                    case.grade,
                    f"{case.id} is inconclusive but carries a grade",
                )

    # -- 2. every passing case's evidence is really on disk ----------------
    def test_passing_cases_cite_published_artifacts(self):
        published = {artifact.path: artifact for artifact in self.record.artifacts}
        for case in self.observations.cases:
            if case.status != "pass":
                continue
            self.assertTrue(
                case.artifact_paths,
                f"{case.id} passes but cites no artifact",
            )
            for relative in case.artifact_paths:
                self.assertIn(
                    relative,
                    published,
                    f"{case.id} cites {relative}, which the record does not publish",
                )
                target = PLATFORM / relative
                self.assertTrue(target.is_file(), f"{relative} is not on disk")
                self.assertEqual(
                    _digest(target),
                    published[relative].sha256,
                    f"{relative} does not match its recorded checksum",
                )

    def test_record_assertions_agree_with_observed_statuses(self):
        assertions = {a.id: a.status for a in self.record.assertions}
        self.assertEqual(set(assertions), set(self.by_id))
        for case_id, case in self.by_id.items():
            expected = "pass" if case.status == "pass" else "fail"
            self.assertEqual(
                assertions[case_id],
                expected,
                f"{case_id}: record says {assertions[case_id]}, observations say {case.status}",
            )

    # -- 3. no pass may rest on a prompt that never ran --------------------
    def test_no_case_passes_on_an_unexecuted_prompt(self):
        used = json.loads((ARTIFACTS / "prompts-used.json").read_text())
        executed = {p["id"]: p["executed"] for p in used["prompts"]}
        for case_id, prompt_id in CASE_PROMPT.items():
            self.assertIn(prompt_id, executed, f"{prompt_id} missing from prompts-used.json")
            if not executed[prompt_id]:
                self.assertNotEqual(
                    self.by_id[case_id].status,
                    "pass",
                    f"{case_id} is graded pass but its prompt {prompt_id} was never executed",
                )

    def test_prompt_digests_match_the_frozen_catalog(self):
        used = json.loads((ARTIFACTS / "prompts-used.json").read_text())
        frozen = json.loads(
            (REPO / "spikes/platform/clients/contracts/prompts-v1.json").read_text()
        )
        expected = {
            p["id"]: hashlib.sha256(p["text"].encode("utf-8")).hexdigest()
            for p in frozen["prompts"]
        }
        self.assertEqual({p["id"]: p["sha256"] for p in used["prompts"]}, expected)

    def test_prompt_text_is_never_republished(self):
        texts = [
            p["text"]
            for p in json.loads(
                (REPO / "spikes/platform/clients/contracts/prompts-v1.json").read_text()
            )["prompts"]
        ]
        for path in _committed_text_files():
            content = path.read_text(encoding="utf-8")
            for text in texts:
                self.assertNotIn(
                    text,
                    content,
                    f"{path.name} republishes raw prompt text; reference it by ID and SHA-256",
                )

    # -- 4. sanitization ---------------------------------------------------
    def test_committed_evidence_is_sanitized(self):
        for path in _committed_text_files():
            content = path.read_text(encoding="utf-8")
            for pattern in SENSITIVE_PATH_PATTERNS:
                self.assertIsNone(
                    pattern.search(content),
                    f"{path.name} contains an absolute user path",
                )
            for pattern in SECRET_PATTERNS:
                self.assertIsNone(
                    pattern.search(content),
                    f"{path.name} contains a credential-like value",
                )
            self.assertIsNone(
                PROBE_ROOT.search(content),
                f"{path.name} leaks the disposable probe root",
            )

    def test_record_environment_pins_the_observed_client(self):
        self.assertEqual(self.record.subject.kind, "client")
        self.assertEqual(self.record.subject.id, "claude-code")
        self.assertEqual(self.record.subject.version, self.observations.client_version)
        self.assertEqual(self.record.environment.os, "linux")
        self.assertIn(
            f"claude={self.observations.client_version}",
            self.record.environment.toolchain,
        )

    def test_record_run_id_is_environment_qualified(self):
        # A subject-only run_id would collide with the next Claude Code host and
        # make it unpublishable (publish.py raises E_IMMUTABLE on the key).
        run_id = self.record.run_id
        self.assertNotEqual(run_id, "client-probe-claudecode")
        self.assertIn(self.record.environment.os, run_id)
        self.assertIn(self.record.environment.arch, run_id)
        self.assertTrue(
            all(artifact.path.split("/")[3] == run_id for artifact in self.record.artifacts),
            "published artifacts are not filed under the record's run_id",
        )

    def test_tool_trace_preserves_the_advertised_subagents(self):
        # agents.delegation is inconclusive, but the client DID register and
        # advertise the plugin's sub-agent. That is real evidence and the trace
        # must keep it, so a re-run has a baseline to compare against.
        trace = json.loads((ARTIFACTS / "tool-trace.json").read_text())
        self.assertTrue(trace["runs"])
        for run in trace["runs"]:
            self.assertIn(
                "kinglet-client-probe:kinglet-capability-reviewer",
                run.get("registered_agents", []),
                f"run {run['run']} drops the advertised sub-agent registration",
            )

    def test_agents_delegation_stays_inconclusive_without_an_invocation(self):
        # Registration is not delegation: agent_invoked and receipt_saved are
        # both unmet, so no grade may be attached.
        case = self.by_id["agents.delegation"]
        self.assertEqual(case.status, "inconclusive")
        self.assertIsNone(case.grade)
        listing = [
            line.strip()
            for line in (ARTIFACTS / "receipts-listing.txt").read_text().splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        self.assertNotIn("agent.json", listing)

    def test_record_status_reflects_unclosed_cases(self):
        # Any non-pass case must keep the whole record off `pass`, so a partially
        # observed suite can never close a coverage cell.
        if any(case.status != "pass" for case in self.observations.cases):
            self.assertNotEqual(self.record.status, "pass")


if __name__ == "__main__":
    unittest.main()
