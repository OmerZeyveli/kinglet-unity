"""test_claude_code_observations.py — Contract tests for the COMMITTED Claude Code evidence.

test_client_results.py covers the validator against synthetic fixtures. This file
covers the real artefacts on disk: the authored observations document, the published
evidence records — one per matrix probe cell — and the published artifact tree.

The invariants worth failing over:
  1. The observations document validates against the frozen 12-case catalog.
  2. Every artifact a *passing* case leans on is actually published, with the
     checksum recorded in the published record matching the bytes on disk.
  3. No case is graded `pass` on the strength of a frozen prompt that was never
     executed. This is the specific fabrication risk this evidence set ran into:
     two cases were summarised as Native/pass from memory, but their prompts were
     never run and no artifact supported them.
  4. The published records partition the 12 cases across the frozen matrix's
     probe cells: each case is asserted in exactly one record, each record binds
     to exactly one cell, and a cell closes only if every case it carries passed.
  5. Committed evidence AND the committed probe scripts that produced it carry
     no absolute user path, credential, or disposable probe root. The scripts are
     the highest-risk text in this tree — they are the only committed files that
     legitimately mention the credential file at all — so they are scanned by the
     same sanitization pass as the evidence, plus a dedicated rule: a script may
     TEST for the credential file inside the disposable root, never copy it.

Everything here names claude-code files explicitly, which is a per-client
guarantee and nothing more — it is exactly why the probe scripts went unguarded
until a mutation found them. test_committed_tree_sanitization.py sweeps every
client tree BY SHAPE so the next client is covered without anyone remembering.
test_the_by_name_set_is_inside_the_client_agnostic_sweep below pins the two
together: nothing listed here may fall outside that sweep.
"""
from __future__ import annotations

import hashlib
import json
import re
import unittest
from dataclasses import replace
from pathlib import Path

from tests.kinglet_spike.spike_tree import (
    ALLOWED_CREDENTIAL_REFERENCE as GENERIC_ALLOWED_CREDENTIAL_REFERENCE,
)
from tests.kinglet_spike.spike_tree import CREDENTIAL_FILE as GENERIC_CREDENTIAL_FILE
from tests.kinglet_spike.spike_tree import DISPOSABLE_CONFIG_VARS
from tests.kinglet_spike.spike_tree import committed_text_files as swept_text_files
from tests.kinglet_spike.spike_tree import credential_copy_violations
from tools.kinglet_spike.client_results import (
    OBSERVATIONS_SCHEMA,
    client_sources,
    load_client_observations,
)
from tools.kinglet_spike.coverage import evaluate_coverage
from tools.kinglet_spike.load import load_record
from tools.kinglet_spike.validate import (
    SECRET_PATTERNS,
    SENSITIVE_PATH_PATTERNS,
    validate_record,
)

REPO = Path(__file__).resolve().parents[2]
OBSERVATIONS = REPO / "spikes/platform/clients/claude-code/observations-linux.json"
CASES = REPO / "spikes/platform/clients/contracts/cases-v1.json"
PLATFORM = REPO / "docs/research/platform-spike"
EVIDENCE_DIR = PLATFORM / "evidence/client/claude-code"
ARTIFACT_ROOT = PLATFORM / "artifacts/client/claude-code"
MATRIX = REPO / "spikes/platform/contracts/matrix-v1.json"
CELL_PREFIX = "client.claude-code.linux-ubuntu-24-04-x64."
PROBE_DIR = REPO / "spikes/platform/clients/claude-code/probe"
EXPECTED_PROBE_SCRIPTS = ("run.sh", "run2.sh")

# Frozen prompt each case is scored from, per the runbook's "Cases evidenced" lists.
# A case may only be `pass` if its prompt actually ran.
CASE_PROMPT = {
    "workflow.natural-language": "workflow-natural-language-01",
    "agents.delegation": "agent-delegation-01",
}

# The disposable live-run root must never appear in committed evidence.
PROBE_ROOT = re.compile(r"/tmp/kinglet-live")

# The credential file may only ever be named as a presence check on the
# credential file inside the DISPOSABLE config root — "$CFG/.credentials.json"
# for this client. Any other mention (a copy, a read, a path under $HOME) is a
# leak of the operator's real credentials.
CREDENTIALS = re.compile(r"\.credentials")
# NOT a second, $CFG-pinned copy of the allow-regex. It was one, and the two
# rules then contradicted each other: a client whose disposable root is named by
# any other variable in DISPOSABLE_CONFIG_VARS — CODEX_HOME, say — could not
# write a legitimate presence check without turning
# test_the_client_agnostic_credential_rule_is_never_weaker_than_this_one RED
# with a message claiming the generic rule had gone soft. One alphabet, one
# source of truth, in spike_tree.py; the invariant below still bites, because
# the two CREDENTIAL patterns remain independent.
ALLOWED_CREDENTIAL_REFERENCE = GENERIC_ALLOWED_CREDENTIAL_REFERENCE


def _record_paths() -> tuple[Path, ...]:
    """Every published Claude Code record, discovered rather than named.

    One record per matrix probe cell now, so a hardcoded run_id would either go
    stale or — worse — keep passing while silently ignoring two of the three.
    """
    return tuple(sorted(EVIDENCE_DIR.glob("*.json")))


def _probe_scripts() -> tuple[Path, ...]:
    return tuple(sorted(p for p in PROBE_DIR.glob("*.sh") if p.is_file()))


def _digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _committed_text_files() -> tuple[Path, ...]:
    paths = [OBSERVATIONS]
    paths.extend(_record_paths())
    for directory in sorted(p for p in ARTIFACT_ROOT.iterdir() if p.is_dir()):
        paths.extend(sorted(p for p in directory.iterdir() if p.is_file()))
    # The probe scripts are committed too, and they are the files that actually
    # touch the operator's machine. Scanning only the evidence they produced left
    # the riskiest text in the tree unguarded.
    paths.extend(_probe_scripts())
    return tuple(paths)


class ClaudeCodeObservationsTests(unittest.TestCase):
    def setUp(self):
        self.observations = load_client_observations(OBSERVATIONS)
        self.records = tuple(load_record(path) for path in _record_paths())
        self.assertTrue(self.records, f"no published record under {EVIDENCE_DIR}")
        self.by_id = {case.id: case for case in self.observations.cases}
        self.by_probe = {record.probe.id: record for record in self.records}

    def _artifact(self, name: str) -> Path:
        """The published copy of `name`, whichever record directories carry it.

        A file cited by cases in two different probe groups is published under
        both run_ids. Those copies must stay byte-identical, or a reader of one
        record sees different evidence from a reader of the other.
        """
        copies = sorted(ARTIFACT_ROOT.glob(f"*/{name}"))
        self.assertTrue(copies, f"{name} is not published under {ARTIFACT_ROOT}")
        digests = {_digest(path) for path in copies}
        self.assertEqual(
            1,
            len(digests),
            f"{name} is published in {len(copies)} record directories with "
            f"differing bytes: {sorted(p.parent.name for p in copies)}",
        )
        return copies[0]

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

    def test_inconclusive_cases_carry_no_grade_KEY_in_the_committed_json(self):
        # The parsed check above reads `case.grade is None`, which an explicit
        # `"grade": null` in the document satisfies just as well as an absent
        # key. Those are not the same claim: a written-out null is somebody
        # having reached for a grade and left the field behind, which is exactly
        # the state the contract says an inconclusive case may not be in.
        # Assert against the raw bytes, where the difference is visible.
        raw = json.loads(OBSERVATIONS.read_text(encoding="utf-8"))
        inconclusive = [c for c in raw["cases"] if c.get("status") == "inconclusive"]
        self.assertTrue(
            inconclusive,
            "no inconclusive case in the document, so this test asserts nothing",
        )
        for case in inconclusive:
            self.assertNotIn(
                "grade",
                case,
                f"{case['id']} is inconclusive and still writes a `grade` key "
                f"(value {case.get('grade')!r}); the key must be absent",
            )

    # -- 2. every passing case's evidence is really on disk ----------------
    def test_passing_cases_cite_published_artifacts(self):
        published = {
            artifact.path: artifact
            for record in self.records
            for artifact in record.artifacts
        }
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
        flat = [
            assertion
            for record in self.records
            for assertion in record.assertions
        ]
        assertions = {a.id: a.status for a in flat}
        self.assertEqual(
            len(flat),
            len(assertions),
            "a case is asserted in more than one record, so one observation "
            "would be counted toward two coverage cells",
        )
        self.assertEqual(
            set(assertions),
            set(self.by_id),
            "the published records are not a partition of the observed cases",
        )
        for case_id, case in self.by_id.items():
            expected = "pass" if case.status == "pass" else "fail"
            self.assertEqual(
                assertions[case_id],
                expected,
                f"{case_id}: record says {assertions[case_id]}, observations say {case.status}",
            )

    # -- 3. no pass may rest on a prompt that never ran --------------------
    def test_no_case_passes_on_an_unexecuted_prompt(self):
        used = json.loads(self._artifact("prompts-used.json").read_text())
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
        used = json.loads(self._artifact("prompts-used.json").read_text())
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

    def test_the_probe_scripts_are_actually_in_the_sanitization_sweep(self):
        # Guards the guard: if the scripts are renamed or the glob stops matching,
        # test_committed_evidence_is_sanitized would silently scan nothing new and
        # keep passing.
        scanned = {p.name for p in _committed_text_files()}
        for name in EXPECTED_PROBE_SCRIPTS:
            self.assertIn(
                name,
                scanned,
                f"probe/{name} is committed but no sanitization test looks at it",
            )

    def test_the_by_name_set_is_inside_the_client_agnostic_sweep(self):
        # The by-name list above protects claude-code only. The client-agnostic
        # sweep in test_committed_tree_sanitization.py protects every client,
        # including ones that do not exist yet. If a file named here is outside
        # that sweep, the sweep is narrower than this file and the next client's
        # equivalent file is unguarded.
        swept = {path.resolve() for path in swept_text_files()}
        for path in _committed_text_files():
            self.assertIn(
                path.resolve(),
                swept,
                f"{path.name} is covered by name here but not by the "
                f"client-agnostic sweep",
            )

    def test_the_client_agnostic_credential_rule_is_never_weaker_than_this_one(self):
        # Being INSIDE the generic sweep is not enough; the generic sweep's RULE
        # has to be at least as strict. It was not: this file pins the allowed
        # presence check to $CFG, while the generic rule accepted any variable.
        # That gap was worth three lines in a new client's probe script —
        #
        #     H="$HOME/.claude"; F="$H/.credentials.json"; cp "$F" ./stolen.json
        #
        # — RED here for claude-code, green everywhere else. Every client but
        # claude-code was less protected by the test written to protect them all.
        #
        # The allow-regexes are one object now, so this can no longer fail on the
        # allow side; it still fails if CREDENTIAL_FILE is narrowed below the
        # `\.credentials` this file looks for, and it fails again the moment
        # anyone re-pins the allow-regex to a single variable, because of the
        # derived presence checks below.
        lines = [
            'F="$H/.credentials.json"',
            'F="$HOME/.claude/.credentials.json"',
            'cat "$CFG/.credentials.json"',
            'if [ ! -f "$CFG/.credentials.json" ]; then',
            'echo "${CFG}/.credentials.json"',
            "cp x/.credentials.json y",
            'p = home / ".credentials.json"',
            "look at .credentialsFoo",
            "the scripts do not copy credentials",
        ]
        # One legitimate presence check per disposable-config variable, in both
        # spellings. These are the lines a client that is not claude-code has to
        # be able to write, and while this file kept its own $CFG-pinned
        # allow-regex every one of them failed HERE — fail-closed, but it meant
        # the alphabet in DISPOSABLE_CONFIG_VARS was a list of names no probe
        # could use. Derived from the tuple, so a new entry is covered the moment
        # it is added.
        for name in DISPOSABLE_CONFIG_VARS:
            lines.append(f'if [ ! -f "${name}/.credentials.json" ]; then')
            lines.append(f'if [ ! -f "${{{name}}}/.credentials.json" ]; then')
        for path in swept_text_files():
            lines.extend(path.read_text(encoding="utf-8").splitlines())
        for line in lines:
            by_name = CREDENTIALS.search(ALLOWED_CREDENTIAL_REFERENCE.sub("", line))
            if by_name is None:
                continue
            self.assertIsNotNone(
                GENERIC_CREDENTIAL_FILE.search(
                    GENERIC_ALLOWED_CREDENTIAL_REFERENCE.sub("", line)
                ),
                f"the by-name rule here flags this line and the "
                f"client-agnostic rule does not, so every client except "
                f"claude-code is less protected: {line.strip()!r}",
            )

    def test_probe_scripts_never_copy_a_credential_file_indirectly(self):
        # The by-name rule above is line-local: it never sees a credential path
        # stashed in a variable and copied later. Run the taint-following rule
        # over these scripts too, so the by-name set is not the weaker of the two
        # in the other direction either.
        for path in _probe_scripts():
            for number, line, reason in credential_copy_violations(
                path.read_text(encoding="utf-8")
            ):
                self.fail(f"{path.name}:{number} {reason}: {line.strip()!r}")

    def test_probe_scripts_never_copy_the_credential_file(self):
        # The scripts are permitted to CHECK that "$CFG/.credentials.json" exists
        # in the disposable root — provisioning it is a manual operator step. They
        # must never copy, read, or otherwise name the credential file anywhere
        # else, above all not under the operator's real ~/.claude.
        scripts = _probe_scripts()
        self.assertTrue(scripts, f"no probe scripts found under {PROBE_DIR}")
        for path in scripts:
            for number, line in enumerate(
                path.read_text(encoding="utf-8").splitlines(), start=1
            ):
                residue = ALLOWED_CREDENTIAL_REFERENCE.sub("", line)
                self.assertIsNone(
                    CREDENTIALS.search(residue),
                    f"{path.name}:{number} names the credential file outside a "
                    f'"$CFG/.credentials.json" presence check: {line.strip()!r}',
                )

    def test_probe_scripts_keep_their_disposable_root_discipline(self):
        # KINGLET_LIVE_BASE has no default on purpose: a default would let an
        # unattended run pick a root the operator never authorised.
        for path in _probe_scripts():
            text = path.read_text(encoding="utf-8")
            self.assertIn('BASE="$KINGLET_LIVE_BASE"', text, path.name)
            # `${KINGLET_LIVE_BASE:-}` is the set -u guard and is fine; a default
            # VALUE (`${KINGLET_LIVE_BASE:-/tmp/...}`) is not.
            self.assertIsNone(
                re.search(r"\$\{KINGLET_LIVE_BASE:-[^}]", text),
                f"{path.name} supplies a default live base",
            )
            self.assertIn('export CLAUDE_CONFIG_DIR="$CFG"', text, path.name)
            # The real-config interlock must use the PHYSICAL pwd; bash's logical
            # `pwd` returns the link path, so a symlinked $CFG would bypass it.
            guards = [
                line
                for line in text.splitlines()
                if ("$CFG" in line or "$HOME" in line) and "pwd" in line
            ]
            self.assertTrue(guards, f"{path.name} has no real-config interlock")
            for line in guards:
                self.assertIn(
                    "pwd -P",
                    line,
                    f"{path.name} uses bash's logical pwd in its only safety "
                    f"interlock, which a symlinked $CFG bypasses: {line.strip()!r}",
                )

    def test_record_environment_pins_the_observed_client(self):
        for record in self.records:
            self.assertEqual(record.subject.kind, "client")
            self.assertEqual(record.subject.id, "claude-code")
            self.assertEqual(record.subject.version, self.observations.client_version)
            self.assertEqual(record.environment.os, "linux")
            self.assertIn(
                f"claude={self.observations.client_version}",
                record.environment.toolchain,
            )

    def test_record_run_id_is_environment_and_probe_qualified(self):
        # A subject-only run_id would collide with the next Claude Code host and
        # make it unpublishable (publish.py raises E_IMMUTABLE on the key). One
        # host now emits one record per probe cell, so the probe id has to be in
        # there too or those records collide with each other.
        run_ids = [record.run_id for record in self.records]
        self.assertEqual(
            len(run_ids),
            len(set(run_ids)),
            f"published records share a run_id: {sorted(run_ids)}",
        )
        for record in self.records:
            run_id = record.run_id
            self.assertNotEqual(run_id, "client-probe-claudecode")
            self.assertIn(record.environment.os, run_id)
            self.assertIn(record.environment.arch, run_id)
            self.assertIn(record.probe.id, run_id)
            self.assertTrue(
                all(
                    artifact.path.split("/")[3] == run_id
                    for artifact in record.artifacts
                ),
                f"{run_id}: published artifacts are not filed under the "
                f"record's run_id",
            )

    def test_tool_trace_preserves_the_advertised_subagents(self):
        # agents.delegation is inconclusive, but the client DID register and
        # advertise the plugin's sub-agent. That is real evidence and the trace
        # must keep it, so a re-run has a baseline to compare against.
        trace = json.loads(self._artifact("tool-trace.json").read_text())
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
            for line in self._artifact("receipts-listing.txt").read_text().splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        self.assertNotIn("agent.json", listing)

    def test_record_status_reflects_unclosed_cases(self):
        # Any non-pass case must keep its OWN record off `pass`. Coverage keys a
        # cell's state on record.status, so this is what stops an inconclusive
        # case from closing a cell — and, since the suite is split, it must hold
        # per record rather than only for the suite as a whole.
        for record in self.records:
            observed = [self.by_id[a.id] for a in record.assertions]
            self.assertTrue(observed, f"{record.run_id} asserts nothing")
            if any(case.status != "pass" for case in observed):
                unclosed = sorted(c.id for c in observed if c.status != "pass")
                self.assertNotEqual(
                    record.status,
                    "pass",
                    f"{record.probe.id} is `pass` while {unclosed} were never "
                    f"observed to pass",
                )


if __name__ == "__main__":
    unittest.main()


class ClaudeCodeCoverageBindingTests(unittest.TestCase):
    """The committed records must actually reach the frozen matrix.

    This is the call site, and it is the bug the split exists to fix: probe.id
    was the constant "capability-suite", which is the suffix of the *windows
    cell id* and not the `probe` value of any cell anywhere. coverage.py matches
    on `record.probe.id == cell.probe`, so a correct, published, sanitized
    evidence set closed nothing at all. Asserting probe id strings in the
    library would not have caught it; only running the real matrix does.
    """

    def setUp(self):
        self.records = tuple(load_record(path) for path in _record_paths())
        self.assertTrue(self.records, f"no published record under {EVIDENCE_DIR}")
        self.cells = {
            cell.id: cell
            for cell in evaluate_coverage(self.records, MATRIX)
            if cell.id.startswith(CELL_PREFIX)
        }

    def test_every_committed_record_lands_in_a_matrix_cell(self):
        self.assertTrue(self.cells, f"matrix defines no cells under {CELL_PREFIX}")
        landed = {run_id for cell in self.cells.values() for run_id in cell.run_ids}
        for record in self.records:
            self.assertIn(
                record.run_id,
                landed,
                f"{record.run_id} publishes probe.id {record.probe.id!r}, which "
                f"matches no cell in matrix-v1.json — it closes nothing",
            )

    def test_each_linux_cell_is_reached_by_exactly_one_record(self):
        for cell_id, cell in sorted(self.cells.items()):
            self.assertEqual(
                1,
                len(cell.run_ids),
                f"{cell_id} is backed by {len(cell.run_ids)} records "
                f"({list(cell.run_ids)}); one probe cell takes one record",
            )

    def test_a_cell_closes_only_when_every_case_it_carries_passed(self):
        # The honest form of "an inconclusive case must not close a cell":
        # derived from the observations, not from a hardcoded expectation about
        # which cells happen to be open today.
        by_id = {case.id: case for case in load_client_observations(OBSERVATIONS).cases}
        for record in self.records:
            observed = [by_id[assertion.id] for assertion in record.assertions]
            unclosed = sorted(c.id for c in observed if c.status != "pass")
            cell = self.cells[CELL_PREFIX + record.probe.id]
            if unclosed:
                self.assertNotEqual(
                    "pass",
                    cell.state,
                    f"{cell.id} is closed while {unclosed} were never observed "
                    f"to pass",
                )

    def test_no_record_is_invalid_for_any_reason(self):
        # This tolerated one diagnostic -- ("E_FIELD", "sources") -- while the
        # records derived `sources` from case source_urls, which are empty for
        # every non-Unavailable case. The all-pass path-semantics record
        # therefore published as `invalid`.
        #
        # The fix was not to relax the validator: the records now carry the
        # client's OWN provenance at record level (CLIENT_SOURCES), the same way
        # runtime records cite the runtime they measured. Nothing about a case
        # changed. So the tolerance is gone, and any diagnostic at all is rot.
        for record in self.records:
            codes = sorted(
                (d.code, d.location) for d in validate_record(record, PLATFORM)
            )
            self.assertEqual(
                [],
                codes,
                f"{record.run_id} is invalid: {codes}",
            )

    def test_every_record_cites_the_declared_provenance_of_the_client(self):
        # Record-level, per-client, and identical across the three records --
        # `sources` says where the binary under test came from, not what any
        # probe observed. Deriving it from a case would make it evidence of the
        # observation, which is the fabrication this whole file guards against.
        version = load_client_observations(OBSERVATIONS).client_version
        expected = client_sources("claude-code", version)
        self.assertTrue(expected, "no CLIENT_SOURCES row for claude-code")
        for record in self.records:
            self.assertEqual(
                list(expected),
                list(record.sources),
                f"{record.run_id} does not carry the declared claude-code "
                f"provenance",
            )
        for source in expected:
            self.assertRegex(source.url, r"^https://")

    def test_a_client_record_without_sources_is_still_rejected(self):
        # The load-bearing half of the fix. If validate.py ever exempts
        # `kinglet.client-probe.observations/v1` from "a pass requires source
        # references", every derived test in this suite stays GREEN while an
        # unsourced all-pass client record starts closing a cell. Assert the
        # rule directly, against a real record with its sources stripped.
        passing = [r for r in self.records if r.status == "pass"]
        self.assertTrue(passing, "no passing client record to check the rule on")
        for record in passing:
            codes = {
                (d.code, d.location)
                for d in validate_record(replace(record, sources=()), PLATFORM)
            }
            self.assertIn(
                ("E_FIELD", "sources"),
                codes,
                f"{record.run_id} passes validation with no sources at all, so "
                f"the pass-requires-sources rule no longer applies to client "
                f"records",
            )
