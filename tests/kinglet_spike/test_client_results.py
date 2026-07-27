"""test_client_results.py — Behavioral contract tests for client probe validation.

Tests the three core invariants of validate_client_observations:
  1. Native/pass requires at least one live artifact (E_ASSERTION).
  2. inconclusive status may not carry a grade (E_ENUM).
  3. All 12 case IDs must appear exactly once (E_COVERAGE).

Plus the run_id contract: two hosts running the same client must produce
distinct run_ids, or the second one is unpublishable (E_IMMUTABLE). Distinctness
alone is too weak a pin — the id must carry the UTC stamp and the
`client-probe-<subject>` segment, or re-probing the SAME host on a later date
collides on the same key and reopens the bug in a narrower form. One host now
emits one record per probe cell, so the probe segment carries the same burden
one level down.

Plus the case → matrix probe mapping (ProbeMappingTests, ProbeCoverageTests):
PROBE_GROUPS must partition the frozen catalog, name only probes the frozen
matrix declares, and — through the real coverage pipeline — close a cell only
when every case in that cell was actually observed.
"""
import json
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.kinglet_spike.client_results import (
    AGGREGATE_PROBE,
    PLATFORM_PROBES,
    PROBE_GROUPS,
    build_run_id,
    case_probe_map,
    host_slug,
    partition_cases,
    probes_for_os,
    to_evidence_records,
    validate_client_observations,
)
from tools.kinglet_spike.model import Environment, EvidenceError
from tools.kinglet_spike.validate import SAFE_COMPONENT
from tools.kinglet_spike.coverage import evaluate_coverage
from tests.kinglet_spike.client_support import CASES, valid_observations

REPO = Path(__file__).resolve().parents[2]
CASES_PATH = REPO / "spikes/platform/clients/contracts/cases-v1.json"
MATRIX_PATH = REPO / "spikes/platform/contracts/matrix-v1.json"


def _environment(os_name: str, release: str, arch: str) -> Environment:
    return Environment(
        os=os_name,
        release=release,
        arch=arch,
        native=True,
        toolchain=("claude=2.1.206",),
    )


class ClientResultTests(unittest.TestCase):
    def test_native_pass_requires_live_artifact(self):
        value = valid_observations()
        value["cases"][0].update({"grade": "Native", "status": "pass", "artifact_paths": []})
        with self.assertRaisesRegex(EvidenceError, "E_ASSERTION"):
            validate_client_observations(value, CASES)

    def test_inconclusive_cannot_be_promoted(self):
        value = valid_observations()
        value["cases"][0].update({"grade": "Native", "status": "inconclusive"})
        with self.assertRaisesRegex(EvidenceError, "E_ENUM"):
            validate_client_observations(value, CASES)

    def test_all_case_ids_are_required_once(self):
        value = valid_observations()
        value["cases"].pop()
        with self.assertRaisesRegex(EvidenceError, "E_COVERAGE"):
            validate_client_observations(value, CASES)


class ClientRunIdTests(unittest.TestCase):
    """publish.py keys evidence on evidence/<kind>/<id>/<run_id>.json and raises
    E_IMMUTABLE on collision. A run_id derived from the subject alone therefore
    makes the second host record for a client unpublishable."""

    def setUp(self):
        self.observations = validate_client_observations(valid_observations(), CASES)

    def test_run_id_distinguishes_hosts_of_the_same_client(self):
        ids = set()
        for environment in (
            _environment("linux", "ubuntu-24.04", "x64"),
            _environment("macos", "26.0", "arm64"),
            _environment("windows", "11-24H2", "x64"),
        ):
            ids.update(
                record.run_id
                for record in to_evidence_records(self.observations, environment)
            )
        self.assertEqual(
            7,
            len(ids),
            f"records of the same client collided on run_id: {sorted(ids)}",
        )

    def test_run_id_distinguishes_the_probes_of_a_single_host(self):
        # One host now emits one record per probe cell. Environment qualification
        # alone leaves those three sharing a key, so only the first is
        # publishable and the other two die on E_IMMUTABLE — the same bug the
        # host slug fixed, one level down.
        records = to_evidence_records(
            self.observations, _environment("linux", "ubuntu-24.04", "x64")
        )
        ids = {record.run_id for record in records}
        self.assertEqual(
            len(records),
            len(ids),
            f"one host's per-probe records collided on run_id: {sorted(ids)}",
        )
        for record in records:
            self.assertIn(
                record.probe.id,
                record.run_id,
                f"run_id {record.run_id!r} does not carry its probe id "
                f"{record.probe.id!r}",
            )

    def test_run_id_is_environment_qualified(self):
        record = to_evidence_records(
            self.observations, _environment("macos", "26.0", "arm64")
        )[0]
        self.assertNotEqual(record.run_id, "client-probe-claudecode")
        for component in ("macos", "26.0", "arm64"):
            self.assertIn(
                component,
                record.run_id,
                f"run_id {record.run_id!r} does not carry the environment component "
                f"{component!r}",
            )

    def test_run_id_leads_with_the_utc_stamp_and_probe_segment(self):
        # Distinctness across hosts is not enough. Without the timestamp, re-probing
        # the SAME host on a later date regenerates the same key and publish.py
        # raises E_IMMUTABLE — the exact bug the environment qualifier fixed, back
        # again in a narrower form. Pin the runtime shape the module documents:
        # <UTC stamp>-client-probe-<subject>-<host slug>-<probe>-01.
        record = to_evidence_records(
            self.observations, _environment("linux", "ubuntu-24.04", "x64")
        )[0]
        self.assertRegex(
            record.run_id,
            r"^\d{8}T\d{6}Z-client-probe-claudecode-",
            f"run_id {record.run_id!r} does not lead with the UTC stamp and the "
            f"client-probe-<subject> segment",
        )

    def test_run_id_places_the_stamp_subject_and_host_in_order(self):
        # Same host, two different probe dates → two different keys.
        environment = _environment("linux", "ubuntu-24.04", "x64")
        first = build_run_id("claudecode", environment, "2026-07-27T09:58:00Z", "mcp-discovery")
        second = build_run_id("claudecode", environment, "2026-08-14T11:02:31Z", "mcp-discovery")
        self.assertEqual(
            first,
            f"20260727T095800Z-client-probe-claudecode-{host_slug(environment)}"
            f"-mcp-discovery-01",
        )
        self.assertNotEqual(
            first,
            second,
            "re-probing the same host on a later date reuses the run_id, so the "
            "second record is unpublishable (E_IMMUTABLE)",
        )
        self.assertEqual(
            second[:16],
            "20260814T110231Z",
            f"run_id {second!r} does not carry the probe timestamp",
        )
        self.assertTrue(first.endswith("-01") and second.endswith("-01"))

    def test_run_id_is_a_safe_publication_component(self):
        # publish.py rejects a run_id that is not SAFE_COMPONENT, so slugification
        # of the environment fields is load-bearing.
        for record in to_evidence_records(
            self.observations,
            _environment("linux", "Ubuntu 24.04.4 LTS", "x86_64"),
        ):
            self.assertRegex(record.run_id, SAFE_COMPONENT)


class ProbeMappingTests(unittest.TestCase):
    """PROBE_GROUPS is the whole mapping from frozen case to matrix probe cell.

    The bug it replaces: probe.id was the constant "capability-suite", which is
    the *suffix of the windows cell id* and not the `probe` value of any cell on
    any platform. coverage.py matches on `record.probe.id == cell.probe`, so the
    published Claude Code evidence closed nothing, anywhere.

    Everything below is derived — from cases-v1.json, from matrix-v1.json, or
    from PROBE_GROUPS itself. A thirteenth frozen case, a renamed cell, or a case
    quietly deleted from the table is caught without anyone editing this file.
    """

    def setUp(self):
        self.frozen_cases = tuple(
            case["id"]
            for case in json.loads(CASES_PATH.read_text(encoding="utf-8"))["cases"]
        )
        self.matrix_probes = frozenset(
            cell["probe"]
            for cell in json.loads(MATRIX_PATH.read_text(encoding="utf-8"))["cells"]
            if cell["subject"]["kind"] == "client"
        )

    def test_the_table_covers_the_frozen_catalog_exactly(self):
        self.assertTrue(self.frozen_cases, "cases-v1.json parsed to zero cases")
        mapped = case_probe_map()
        missing = sorted(set(self.frozen_cases) - set(mapped))
        self.assertEqual(
            [],
            missing,
            f"frozen case(s) {missing} are in no PROBE_GROUPS row, so their "
            f"evidence would be published under no probe cell at all",
        )
        stray = sorted(set(mapped) - set(self.frozen_cases))
        self.assertEqual(
            [],
            stray,
            f"PROBE_GROUPS maps case id(s) {stray} that cases-v1.json does not "
            f"define",
        )

    def test_no_case_is_claimed_by_two_probes(self):
        # A case in two rows would close two cells off one observation. Counted
        # from the raw table rather than from case_probe_map(), which raises.
        seen: dict[str, str] = {}
        for probe_id, case_ids in PROBE_GROUPS:
            for case_id in case_ids:
                self.assertNotIn(
                    case_id,
                    seen,
                    f"case {case_id!r} is in both {seen.get(case_id)!r} and "
                    f"{probe_id!r}, so one observation would close two cells",
                )
                seen[case_id] = probe_id
        self.assertEqual(len(seen), sum(len(ids) for _, ids in PROBE_GROUPS))

    def test_every_probe_named_by_the_table_exists_in_the_matrix(self):
        self.assertTrue(self.matrix_probes, "matrix-v1.json has no client cells")
        for probe_id, _ in PROBE_GROUPS:
            self.assertIn(
                probe_id,
                self.matrix_probes,
                f"PROBE_GROUPS points at probe {probe_id!r}, which no client "
                f"cell in matrix-v1.json declares — records emitted for it "
                f"would match nothing and close nothing",
            )
        self.assertIn(
            AGGREGATE_PROBE,
            self.matrix_probes,
            f"the aggregate probe {AGGREGATE_PROBE!r} is not a client cell "
            f"probe in matrix-v1.json",
        )

    def test_every_platform_emits_exactly_the_probes_the_matrix_defines(self):
        matrix = json.loads(MATRIX_PATH.read_text(encoding="utf-8"))["cells"]
        for os_name, _ in PLATFORM_PROBES:
            expected = frozenset(
                cell["probe"]
                for cell in matrix
                if cell["subject"]["kind"] == "client" and cell["os"] == os_name
            )
            self.assertTrue(expected, f"matrix defines no client cells for {os_name}")
            self.assertEqual(
                expected,
                frozenset(probes_for_os(os_name)),
                f"the probes emitted on {os_name} are not the cells the frozen "
                f"matrix defines there",
            )

    def test_an_unknown_platform_is_refused_rather_than_defaulted(self):
        with self.assertRaisesRegex(EvidenceError, "E_COVERAGE"):
            probes_for_os("plan9")

    def test_a_case_missing_from_the_table_is_named_not_dropped(self):
        # Derived guard: partition_cases walks the OBSERVED cases, which
        # validate_client_observations has already pinned to cases-v1.json
        # exactly. Deleting a row from PROBE_GROUPS therefore cannot silently
        # shrink the published evidence.
        observations = validate_client_observations(valid_observations(), CASES)
        victim = PROBE_GROUPS[0][1][0]
        thinned = tuple(
            (probe_id, tuple(c for c in case_ids if c != victim))
            for probe_id, case_ids in PROBE_GROUPS
        )
        with patch("tools.kinglet_spike.client_results.PROBE_GROUPS", thinned):
            with self.assertRaises(EvidenceError) as caught:
                partition_cases(observations, "linux")
        self.assertEqual("E_COVERAGE", caught.exception.code)
        self.assertIn(victim, str(caught.exception))


class ProbeCoverageTests(unittest.TestCase):
    """The call site, not the helper.

    "helper covered, call site unprotected" has recurred repeatedly here, so
    these run the real pipeline — to_evidence_records → evaluate_coverage → the
    frozen matrix — and assert on cell states rather than on probe strings.
    """

    ENVIRONMENT = Environment(
        os="linux",
        release="ubuntu-24.04.4-lts",
        arch="x64",
        native=True,
        toolchain=("claude=2.1.206",),
    )
    PREFIX = "client.claude-code.linux-ubuntu-24-04-x64."

    def _states(self, value: dict) -> dict[str, str]:
        observations = validate_client_observations(value, CASES)
        records = to_evidence_records(observations, self.ENVIRONMENT)
        return {
            cell.id[len(self.PREFIX):]: cell.state
            for cell in evaluate_coverage(records, MATRIX_PATH)
            if cell.id.startswith(self.PREFIX)
        }

    def test_an_all_pass_suite_closes_every_split_cell(self):
        states = self._states(valid_observations())
        self.assertEqual(
            {probe_id: "pass" for probe_id, _ in PROBE_GROUPS},
            states,
            "the emitted records do not bind to the three linux cells; probe.id "
            "must equal the matrix cell's `probe` value",
        )

    def test_one_inconclusive_case_leaves_exactly_its_own_cell_open(self):
        # An inconclusive case is unobserved, not observed-good. It must keep its
        # cell open — and it must not drag the other two open with it, which is
        # the whole point of splitting the suite.
        target_probe, case_ids = PROBE_GROUPS[1]
        victim = case_ids[0]
        value = valid_observations()
        for case in value["cases"]:
            if case["id"] == victim:
                case["status"] = "inconclusive"
                case.pop("grade")
        states = self._states(value)
        self.assertNotEqual(
            "pass",
            states[target_probe],
            f"{victim} is inconclusive, yet cell {target_probe!r} closed on it",
        )
        for probe_id, _ in PROBE_GROUPS:
            if probe_id != target_probe:
                self.assertEqual(
                    "pass",
                    states[probe_id],
                    f"one inconclusive case in {target_probe!r} also held "
                    f"{probe_id!r} open; the split is not isolating cells",
                )

    def test_every_case_reaches_exactly_one_published_record(self):
        observations = validate_client_observations(valid_observations(), CASES)
        records = to_evidence_records(observations, self.ENVIRONMENT)
        asserted: list[str] = []
        for record in records:
            asserted.extend(assertion.id for assertion in record.assertions)
        self.assertEqual(
            sorted(asserted),
            sorted(case.id for case in observations.cases),
            "the per-probe records are not a partition of the observed cases: "
            "a case is duplicated across records or dropped from all of them",
        )

    def test_windows_still_emits_one_aggregate_record_for_every_case(self):
        observations = validate_client_observations(valid_observations(), CASES)
        environment = Environment(
            os="windows",
            release="11-25H2",
            arch="x64",
            native=True,
            toolchain=("claude=2.1.206",),
        )
        records = to_evidence_records(observations, environment)
        self.assertEqual(1, len(records))
        self.assertEqual(AGGREGATE_PROBE, records[0].probe.id)
        self.assertEqual(len(observations.cases), len(records[0].assertions))
        states = {
            cell.id: cell.state
            for cell in evaluate_coverage(records, MATRIX_PATH)
            if cell.id == "client.claude-code.windows-11-x64.capability-suite"
        }
        self.assertEqual(
            {"client.claude-code.windows-11-x64.capability-suite": "pass"},
            states,
            "the windows aggregate record does not bind to its own cell; the "
            "matrix `probe` there is 'client-capability-suite', not the "
            "'capability-suite' suffix of the cell id",
        )
