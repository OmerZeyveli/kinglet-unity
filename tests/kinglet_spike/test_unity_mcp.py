"""test_unity_mcp.py -- Server-vs-Editor readiness and the live-editor-mcp route.

Every guard here is EXECUTED. The client is a seam, so the readiness matrix
runs through the real `list_instances`, `select_instance`, `_evaluate` and
`probe_editor`; the route runs through the real `assert_headless_safe`, the
real `verify_project_editor`, the real `WorkspaceLease` on a real directory,
and the real `mcp.py` pipeline. Only the two subprocess boundaries (the
`unity-mcp` CLI and Unity itself) are doubles.

WHAT IS REAL DATA AND WHAT IS NOT -- stated plainly, because the last four
review rounds on this plan turned on exactly this distinction.

REAL, captured on this host on 2026-07-28 from the pinned server
(CoplayDev/unity-mcp @ 78ee5418, `mcp-for-unity --transport http
--http-host 127.0.0.1 --http-port <ephemeral>`, `DISABLE_TELEMETRY=1`, no
Editor running):

  ZERO_INSTANCES_STDOUT   verbatim stdout of `--format json instances`, exit 0
  NO_INSTANCE_STDERR      verbatim stderr of `--format json raw
                          get_editor_state`, exit 1, stdout EMPTY
  UNREACHABLE_STDERR      verbatim stderr of the same `instances` call against
                          a CLOSED port, exit 1, stdout EMPTY

Those three are the whole point: the first is a SUCCESS response describing a
state in which nothing can run, and the other two are near-identical prose for
two states that must be categorized differently.

NOT captured, and labelled as such wherever it appears: the editor-state
snapshot of a CONNECTED Editor. No Editor ever registered with the bridge on
this host (see the task report for exactly how far the attempt got), so
`snapshot()` below is RECONSTRUCTED field-by-field from the pinned C# source
(`MCPForUnity/Editor/Services/EditorStateCache.cs::BuildSnapshot`). It is not
evidence that a real Editor produces these bytes. What it does test is that
`_evaluate` applies the right rule to each field, and every readiness rule it
encodes is quoted from that file or from
`Server/src/services/resources/editor_state.py`.
"""
from __future__ import annotations

import hashlib
import json
import unittest
from pathlib import Path

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.unity import mcp, routes
from tools.kinglet_spike.unity.model import PROJECT_ID, RECEIPT_SCHEMA
from tools.kinglet_spike.unity.process import CleanupResult
from tools.kinglet_spike.unity.receipt import (
    unity_receipt_from_dict,
    validate_unity_receipt,
)

from .test_unity_routes import (
    EDITOR_VERSION,
    empty_process_table,
    make_project,
    version_stdout,
)

_REPO = Path(__file__).resolve().parents[2]
_CONTRACT = _REPO / "spikes/platform/unity/contracts/routes-v1.json"
_LOCK = _REPO / "spikes/platform/unity/mcp.lock.json"

# --- REAL captured transcripts (see the module docstring) ------------------

ZERO_INSTANCES_STDOUT = '{\n  "success": true,\n  "instances": []\n}\n'

NO_INSTANCE_STDERR = (
    "❌ HTTP error from server: 503 - "
    '{"success":false,"error":"No Unity instances connected. '
    'Make sure Unity is running with MCP plugin."}\n'
)

UNREACHABLE_STDERR = (
    "❌ Cannot connect to Unity MCP server at 127.0.0.1:41351. "
    "Make sure the server is running and Unity is connected.\n"
    "Error: All connection attempts failed\n"
)

NOW_MS = 1_800_000_000_000


# ---------------------------------------------------------------------------
# Client double
# ---------------------------------------------------------------------------

def call_from(stdout: str = "", stderr: str = "", exit_code: int = 0, timed_out: bool = False):
    """Build an McpCall through the REAL stdout parser, not a hand-set payload.

    `_parse_payload` is what turns "the CLI printed something" into "we have a
    JSON object", and it is the function that must keep returning None for the
    two captured error transcripts above. Constructing McpCall with a
    pre-parsed payload would route every test around it.
    """
    return mcp.McpCall(
        argv=("unity-mcp",),
        exit_code=exit_code,
        stdout=stdout,
        stderr=stderr,
        payload=mcp._parse_payload(stdout),
        timed_out=timed_out,
    )


class FakeClient:
    """A scripted `unity-mcp` CLI. Records every call, including `--instance`."""

    def __init__(self, *, instances=None, state=None, script=None):
        self.instances_call = instances
        self.state_call = state
        self.script = dict(script or {})
        self.calls: list[tuple[tuple[str, ...], str | None]] = []

    def call(self, args, *, instance=None, timeout=60.0):
        args = tuple(args)
        self.calls.append((args, instance))
        head = args[0]
        if head == "instances":
            return self._resolve(self.instances_call)
        key = " ".join(args[:2])
        if key in self.script:
            return self._resolve(self.script[key])
        if args[:2] == ("raw", "get_editor_state"):
            return self._resolve(self.state_call)
        return call_from(stdout='{"success": true, "data": {}}')

    def _resolve(self, value):
        if value is None:
            return call_from(stderr=NO_INSTANCE_STDERR, exit_code=1)
        if callable(value):
            return self._resolve(value())
        if isinstance(value, list):
            # A queue: each call pops the next scripted reply, last one repeats.
            item = value.pop(0) if len(value) > 1 else value[0]
            return self._resolve(item)
        return value


def instances_payload(*entries):
    return call_from(stdout=json.dumps({"success": True, "instances": list(entries)}))


def entry_for(project, *, version=EDITOR_VERSION, hash_override=None):
    return {
        "session_id": "sess-1",
        "project": mcp.project_instance_name(project),
        "hash": hash_override or mcp.project_instance_hash(project),
        "unity_version": version,
    }


def snapshot(**overrides):
    """A RECONSTRUCTED editor_state@2 snapshot -- see the module docstring.

    Field names and nesting come from EditorStateCache.BuildSnapshot at the
    pinned commit; `unity.instance_id` and `unity.project_id` are null there
    too, hardcoded, which is why identity never comes from this object.
    """
    data = {
        "schema_version": "unity-mcp/editor_state@2",
        "observed_at_unix_ms": NOW_MS - 100,
        "sequence": 42,
        "unity": {
            "instance_id": None,
            "unity_version": EDITOR_VERSION,
            "project_id": None,
            "platform": "LinuxEditor",
            "is_batch_mode": False,
        },
        "activity": {"phase": "idle", "since_unix_ms": NOW_MS - 5000, "reasons": []},
        "compilation": {
            "is_compiling": False,
            "is_domain_reload_pending": False,
            "last_compile_started_unix_ms": None,
            "last_compile_finished_unix_ms": None,
        },
        "assets": {
            "is_updating": False,
            "refresh": {"is_refresh_in_progress": False},
        },
        "tests": {"is_running": False, "mode": None, "current_job_id": None},
        "transport": {"unity_bridge_connected": True},
    }
    for path, value in overrides.items():
        parts = path.split(".")
        cursor = data
        for part in parts[:-1]:
            cursor = cursor[part]
        if value is _DELETE:
            cursor.pop(parts[-1], None)
        else:
            cursor[parts[-1]] = value
    return data


_DELETE = object()


def state_call(**overrides):
    return call_from(stdout=json.dumps({"success": True, "data": snapshot(**overrides)}))


# ---------------------------------------------------------------------------
# The readiness matrix -- the brief's Step 1, in its order
# ---------------------------------------------------------------------------

class ReadinessMatrixTests(unittest.TestCase):
    """Six states. Exactly one of them is ready."""

    def setUp(self):
        self.project = Path("/tmp/kinglet-probe-project")

    def probe(self, client):
        return mcp.probe_editor(
            client, project=self.project, unity_version=EDITOR_VERSION, now_ms=NOW_MS
        )

    def test_1_http_port_closed_is_a_server_start_failure(self):
        # REAL captured transcript: exit 1, EMPTY stdout, prose on stderr.
        client = FakeClient(instances=call_from(stderr=UNREACHABLE_STDERR, exit_code=1))
        state = self.probe(client)
        self.assertFalse(state.ready)
        self.assertEqual(mcp.CATEGORY_SERVER_START_FAILED, state.category)
        self.assertEqual((mcp.REASON_SERVER_UNREACHABLE,), state.blocking_reasons)
        self.assertFalse(state.server_reachable)

    def test_2_server_reachable_with_zero_instances_is_not_ready(self):
        # REAL captured transcript, and the crux of the whole task: exit 0,
        # success:true, well-formed JSON -- describing a host on which nothing
        # can compile and no test can run.
        client = FakeClient(instances=call_from(stdout=ZERO_INSTANCES_STDOUT))
        state = self.probe(client)
        self.assertFalse(state.ready)
        self.assertEqual(mcp.CATEGORY_EDITOR_NOT_READY, state.category)
        self.assertIn(mcp.REASON_NO_INSTANCES, state.blocking_reasons)
        # The server itself is fine, and the verdict says so.
        self.assertTrue(state.server_reachable)

    def test_2b_the_captured_zero_instance_body_really_is_a_success_response(self):
        # Guards the fixture itself: if this stopped being a success response
        # the test above would be proving something else.
        payload = json.loads(ZERO_INSTANCES_STDOUT)
        self.assertIs(True, payload["success"])
        self.assertEqual([], payload["instances"])

    def test_3_wrong_project_instance_is_not_ready(self):
        other = instances_payload(entry_for(Path("/tmp/some-other-project")))
        state = self.probe(FakeClient(instances=other, state=state_call()))
        self.assertFalse(state.ready)
        self.assertEqual(mcp.CATEGORY_EDITOR_NOT_READY, state.category)
        self.assertEqual((mcp.REASON_NO_MATCHING_INSTANCE,), state.blocking_reasons)

    def test_3b_wrong_project_instance_is_never_queried_for_state(self):
        client = FakeClient(
            instances=instances_payload(entry_for(Path("/tmp/some-other-project"))),
            state=state_call(),
        )
        self.probe(client)
        self.assertEqual([("instances",)], [args for args, _ in client.calls])

    def test_4_expected_instance_compiling_is_not_ready(self):
        client = FakeClient(
            instances=instances_payload(entry_for(self.project)),
            state=state_call(**{"compilation.is_compiling": True}),
        )
        state = self.probe(client)
        self.assertFalse(state.ready)
        self.assertEqual(mcp.CATEGORY_EDITOR_NOT_READY, state.category)
        self.assertIn(mcp.REASON_COMPILING, state.blocking_reasons)

    def test_5_expected_instance_with_ready_for_tools_false_is_not_ready(self):
        client = FakeClient(
            instances=instances_payload(entry_for(self.project)),
            state=state_call(advice={"ready_for_tools": False, "blocking_reasons": ["compiling"]}),
        )
        state = self.probe(client)
        self.assertFalse(state.ready)
        self.assertIn(mcp.REASON_ADVICE_NOT_READY, state.blocking_reasons)

    def test_6_expected_idle_instance_is_the_only_ready_state(self):
        client = FakeClient(
            instances=instances_payload(entry_for(self.project)),
            state=state_call(advice={"ready_for_tools": True, "blocking_reasons": []}),
        )
        state = self.probe(client)
        self.assertTrue(state.ready)
        self.assertIsNone(state.category)
        self.assertEqual((), state.blocking_reasons)
        self.assertEqual(EDITOR_VERSION, state.unity_version)
        self.assertEqual(mcp.project_instance_hash(self.project), state.instance.hash)

    def test_6b_ready_without_an_advice_block_still_works(self):
        # The RAW `get_editor_state` command carries no `advice` key at all
        # (it is added by the Python resource layer). Absence must not block.
        client = FakeClient(
            instances=instances_payload(entry_for(self.project)),
            state=state_call(),
        )
        self.assertTrue(self.probe(client).ready)

    def test_6c_the_state_call_is_routed_to_the_named_instance(self):
        # get_editor_state cannot identify its own project (both id fields are
        # hardcoded null upstream), so an unrouted call would answer for
        # whichever session the server picked.
        client = FakeClient(
            instances=instances_payload(entry_for(self.project)),
            state=state_call(),
        )
        self.probe(client)
        routed = [instance for args, instance in client.calls if args[0] == "raw"]
        self.assertEqual(
            [f"{mcp.project_instance_name(self.project)}@"
             f"{mcp.project_instance_hash(self.project)}"],
            routed,
        )


class AmbiguityIsNeverReadyTests(unittest.TestCase):
    """Every "we could not tell" must land on NOT ready.

    The upstream server's own rule is `if value is True: block`, so a snapshot
    with `is_compiling` missing or null contributes no blocking reason and the
    Editor is declared ready. That is the permissive-by-construction defect
    Task 3 was burned on, and these tests are the mutation that catches it: if
    `_require_false` is relaxed back to the upstream rule, they fail.
    """

    def setUp(self):
        self.project = Path("/tmp/kinglet-probe-project")

    def probe(self, **overrides):
        client = FakeClient(
            instances=instances_payload(entry_for(self.project)),
            state=state_call(**overrides),
        )
        return mcp.probe_editor(
            client, project=self.project, unity_version=EDITOR_VERSION, now_ms=NOW_MS
        )

    def test_missing_is_compiling_is_not_ready(self):
        state = self.probe(**{"compilation.is_compiling": _DELETE})
        self.assertFalse(state.ready)
        self.assertIn("compiling-unknown", state.blocking_reasons)

    def test_null_is_compiling_is_not_ready(self):
        state = self.probe(**{"compilation.is_compiling": None})
        self.assertFalse(state.ready)
        self.assertIn("compiling-unknown", state.blocking_reasons)

    def test_non_boolean_is_compiling_is_not_ready(self):
        state = self.probe(**{"compilation.is_compiling": "false"})
        self.assertFalse(state.ready)
        self.assertIn("compiling-unknown", state.blocking_reasons)

    def test_missing_compilation_block_entirely_is_not_ready(self):
        client = FakeClient(
            instances=instances_payload(entry_for(self.project)),
            state=call_from(stdout=json.dumps({
                "success": True,
                "data": {"schema_version": "unity-mcp/editor_state@2"},
            })),
        )
        state = mcp.probe_editor(
            client, project=self.project, unity_version=EDITOR_VERSION, now_ms=NOW_MS
        )
        self.assertFalse(state.ready)
        self.assertIn("compiling-unknown", state.blocking_reasons)

    def test_domain_reload_pending_is_not_ready(self):
        self.assertIn(
            mcp.REASON_DOMAIN_RELOAD,
            self.probe(**{"compilation.is_domain_reload_pending": True}).blocking_reasons,
        )

    def test_tests_already_running_is_not_ready(self):
        self.assertIn(
            mcp.REASON_RUNNING_TESTS,
            self.probe(**{"tests.is_running": True}).blocking_reasons,
        )

    def test_asset_import_in_progress_is_not_ready(self):
        self.assertIn(
            mcp.REASON_ASSET_IMPORT,
            self.probe(**{"assets.is_updating": True}).blocking_reasons,
        )

    def test_stale_snapshot_is_not_ready(self):
        # An unfocused GUI Editor throttles its update loop, so a snapshot
        # minutes old is a real state -- and "not compiling, five minutes ago"
        # is not a statement about now.
        state = self.probe(observed_at_unix_ms=NOW_MS - (mcp.STALENESS_LIMIT_MS + 1))
        self.assertFalse(state.ready)
        self.assertIn(mcp.REASON_STALE_STATUS, state.blocking_reasons)

    def test_a_snapshot_exactly_at_the_limit_is_still_fresh(self):
        state = self.probe(observed_at_unix_ms=NOW_MS - mcp.STALENESS_LIMIT_MS)
        self.assertTrue(state.ready)
        self.assertEqual(mcp.STALENESS_LIMIT_MS, state.age_ms)

    def test_missing_timestamp_is_not_ready(self):
        state = self.probe(observed_at_unix_ms=_DELETE)
        self.assertFalse(state.ready)
        self.assertIn("stale-status-unknown", state.blocking_reasons)

    def test_snapshot_reporting_a_different_unity_version_is_not_ready(self):
        state = self.probe(**{"unity.unity_version": "6000.0.68f1"})
        self.assertFalse(state.ready)
        self.assertIn(mcp.REASON_STATE_VERSION_MISMATCH, state.blocking_reasons)

    def test_state_call_that_returned_nothing_is_not_ready(self):
        # REAL captured transcript: this is exactly what "server up, Editor
        # gone" prints -- empty stdout, a 503 on stderr, exit 1.
        client = FakeClient(
            instances=instances_payload(entry_for(self.project)),
            state=call_from(stderr=NO_INSTANCE_STDERR, exit_code=1),
        )
        state = mcp.probe_editor(
            client, project=self.project, unity_version=EDITOR_VERSION, now_ms=NOW_MS
        )
        self.assertFalse(state.ready)
        self.assertEqual((mcp.REASON_STATE_UNAVAILABLE,), state.blocking_reasons)
        self.assertEqual(mcp.CATEGORY_EDITOR_NOT_READY, state.category)

    def test_state_call_that_timed_out_is_not_ready(self):
        client = FakeClient(
            instances=instances_payload(entry_for(self.project)),
            state=call_from(exit_code=-1, timed_out=True),
        )
        state = mcp.probe_editor(
            client, project=self.project, unity_version=EDITOR_VERSION, now_ms=NOW_MS
        )
        self.assertFalse(state.ready)
        self.assertEqual((mcp.REASON_STATE_UNAVAILABLE,), state.blocking_reasons)
        self.assertIn("timed out", state.detail)

    def test_an_unrecognised_reply_object_is_rejected_whole_not_field_by_field(self):
        # Pins _state_data's conservative fallback, which was unasserted:
        # mutating `if "schema_version" in payload or "compilation" in payload`
        # to a bare `return payload` left the whole suite green, because
        # _evaluate then rejects the dict on every field and the verdict is
        # still not-ready. Benign in effect, but an unasserted guard in a
        # module whose entire claim is that its guards are asserted.
        #
        # The assertion that kills it is EXACTNESS: a payload that is not a
        # snapshot must be rejected as ONE thing -- state-malformed -- not
        # accepted and then picked apart into six field-level reasons.
        self.assertIsNone(mcp._state_data({"success": True, "totally": "unrelated"}))
        client = FakeClient(
            instances=instances_payload(entry_for(self.project)),
            state=call_from(stdout=json.dumps({"success": True, "totally": "unrelated"})),
        )
        state = mcp.probe_editor(
            client, project=self.project, unity_version=EDITOR_VERSION, now_ms=NOW_MS
        )
        self.assertFalse(state.ready)
        self.assertEqual((mcp.REASON_STATE_MALFORMED,), state.blocking_reasons)

    def test_a_snapshot_handed_back_unwrapped_is_still_recognised(self):
        # The other side of that guard: some transports return the snapshot
        # without the {"success", "data"} envelope. It is accepted only
        # because it actually looks like a snapshot, never as a fallback.
        client = FakeClient(
            instances=instances_payload(entry_for(self.project)),
            state=call_from(stdout=json.dumps(snapshot())),
        )
        self.assertTrue(mcp.probe_editor(
            client, project=self.project, unity_version=EDITOR_VERSION, now_ms=NOW_MS
        ).ready)

    def test_state_reply_reporting_failure_is_not_ready(self):
        client = FakeClient(
            instances=instances_payload(entry_for(self.project)),
            state=call_from(stdout=json.dumps({"success": False, "error": "nope"})),
        )
        state = mcp.probe_editor(
            client, project=self.project, unity_version=EDITOR_VERSION, now_ms=NOW_MS
        )
        self.assertFalse(state.ready)
        self.assertIn(mcp.REASON_STATE_MALFORMED, state.blocking_reasons)


class InstanceSelectionTests(unittest.TestCase):
    """Identity is a computed hash, never a name -- two checkouts share a name."""

    def test_hash_reproduces_the_pinned_csharp_algorithm(self):
        project = Path("/tmp/kinglet-probe-project")
        data_path = project.resolve().as_posix() + "/Assets"
        expected = hashlib.sha1(data_path.encode("utf-8")).hexdigest()[:16].lower()
        self.assertEqual(expected, mcp.project_instance_hash(project))
        self.assertEqual(16, len(mcp.project_instance_hash(project)))

    def test_data_path_is_always_forward_slashed_and_ends_in_assets(self):
        # Unity normalises Application.dataPath to forward slashes on every
        # platform. A backslash rendering would hash to something no Editor
        # ever registers under.
        value = mcp.project_data_path(Path("/tmp/kinglet-probe-project"))
        self.assertTrue(value.endswith("/Assets"), value)
        self.assertNotIn("\\", value)

    def test_two_checkouts_of_the_same_fixture_share_a_name_but_not_a_hash(self):
        left = Path("/tmp/a/kinglet-unity-probe")
        right = Path("/tmp/b/kinglet-unity-probe")
        self.assertEqual(
            mcp.project_instance_name(left), mcp.project_instance_name(right)
        )
        self.assertNotEqual(
            mcp.project_instance_hash(left), mcp.project_instance_hash(right)
        )

    def test_matching_project_at_the_wrong_version_is_its_own_reason(self):
        project = Path("/tmp/kinglet-probe-project")
        chosen, reasons = mcp.select_instance(
            [mcp._instance_from_entry(entry_for(project, version="6000.0.68f1"))],
            project=project,
            unity_version=EDITOR_VERSION,
        )
        self.assertIsNone(chosen)
        self.assertEqual((mcp.REASON_INSTANCE_VERSION_MISMATCH,), reasons)

    def test_the_right_instance_is_picked_out_of_several(self):
        project = Path("/tmp/kinglet-probe-project")
        entries = [
            mcp._instance_from_entry(entry_for(Path("/tmp/other-a"))),
            mcp._instance_from_entry(entry_for(project)),
            mcp._instance_from_entry(entry_for(Path("/tmp/other-b"))),
        ]
        chosen, reasons = mcp.select_instance(
            entries, project=project, unity_version=EDITOR_VERSION
        )
        self.assertEqual((), reasons)
        self.assertEqual(mcp.project_instance_hash(project), chosen.hash)

    def test_a_listing_that_is_not_a_list_is_reachable_but_unusable(self):
        client = FakeClient(
            instances=call_from(stdout=json.dumps({"success": True, "instances": "nope"}))
        )
        probe = mcp.list_instances(client)
        self.assertTrue(probe.reachable)
        self.assertEqual((mcp.REASON_INSTANCES_MALFORMED,), probe.reasons)

    def test_an_entry_without_a_hash_is_malformed_not_silently_dropped(self):
        client = FakeClient(instances=call_from(
            stdout=json.dumps({"success": True, "instances": [{"project": "x"}]})
        ))
        probe = mcp.list_instances(client)
        self.assertIn(mcp.REASON_INSTANCES_MALFORMED, probe.reasons)
        self.assertIn(mcp.REASON_NO_INSTANCES, probe.reasons)

    def test_success_false_is_treated_as_unreachable(self):
        client = FakeClient(
            instances=call_from(stdout=json.dumps({"success": False, "error": "x"}))
        )
        self.assertFalse(mcp.list_instances(client).reachable)


# ---------------------------------------------------------------------------
# wait_for_editor -- the categorization the brief names explicitly
# ---------------------------------------------------------------------------

class WaitCategorizationTests(unittest.TestCase):
    def setUp(self):
        self.project = Path("/tmp/kinglet-probe-project")
        self.slept: list[float] = []
        self.ticks = iter([0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0])

    def clock(self):
        return next(self.ticks)

    def wait(self, client, **kwargs):
        return mcp.wait_for_editor(
            client,
            project=self.project,
            unity_version=EDITOR_VERSION,
            timeout=kwargs.pop("timeout", 4.0),
            poll_interval=0.0,
            clock=self.clock,
            sleep=self.slept.append,
            now_ms=lambda: NOW_MS,
            **kwargs,
        )

    def test_server_only_timeout_is_editor_not_ready_not_server_start_failed(self):
        # THE brief's assertion. A server that answers forever with zero
        # instances is the MEASURED exit-0 success shape; timing out against
        # it is an EDITOR failure, and calling it a server-start failure would
        # point every future debugging session at the wrong process.
        client = FakeClient(instances=call_from(stdout=ZERO_INSTANCES_STDOUT))
        state = self.wait(client)
        self.assertFalse(state.ready)
        self.assertEqual(mcp.CATEGORY_EDITOR_NOT_READY, state.category)
        self.assertNotEqual(mcp.CATEGORY_SERVER_START_FAILED, state.category)
        self.assertIn(mcp.REASON_NO_INSTANCES, state.blocking_reasons)
        self.assertGreaterEqual(state.polls, 2)

    def test_a_server_that_never_answered_is_a_server_start_failure(self):
        client = FakeClient(instances=call_from(stderr=UNREACHABLE_STDERR, exit_code=1))
        state = self.wait(client)
        self.assertEqual(mcp.CATEGORY_SERVER_START_FAILED, state.category)

    def test_a_server_that_answered_once_then_died_is_still_editor_not_ready(self):
        # The category comes from an OBSERVATION -- "did any poll ever get a
        # well-formed listing" -- not from the last error message.
        client = FakeClient(instances=[
            call_from(stdout=ZERO_INSTANCES_STDOUT),
            call_from(stderr=UNREACHABLE_STDERR, exit_code=1),
        ])
        state = self.wait(client)
        self.assertEqual(mcp.CATEGORY_EDITOR_NOT_READY, state.category)

    def test_an_editor_that_arrives_on_a_later_poll_is_ready(self):
        client = FakeClient(
            instances=[
                call_from(stdout=ZERO_INSTANCES_STDOUT),
                instances_payload(entry_for(self.project)),
            ],
            state=state_call(),
        )
        state = self.wait(client)
        self.assertTrue(state.ready)
        self.assertIsNone(state.category)
        self.assertEqual(2, state.polls)

    def test_require_ready_raises_with_the_category_and_the_reasons(self):
        client = FakeClient(instances=call_from(stdout=ZERO_INSTANCES_STDOUT))
        with self.assertRaises(EvidenceError) as caught:
            self.wait(client).require_ready()
        self.assertEqual("E_UNITY_MCP_NOT_READY", caught.exception.code)
        self.assertIn(mcp.CATEGORY_EDITOR_NOT_READY, caught.exception.detail)
        self.assertIn(mcp.REASON_NO_INSTANCES, caught.exception.detail)

    def test_wait_for_server_does_not_wait_for_an_editor(self):
        # Merging the two waits is the conflation this module exists to stop.
        client = FakeClient(instances=call_from(stdout=ZERO_INSTANCES_STDOUT))
        probe = mcp.wait_for_server(
            client, timeout=4.0, poll_interval=0.0,
            clock=self.clock, sleep=self.slept.append,
        )
        self.assertTrue(probe.reachable)
        self.assertEqual((mcp.REASON_NO_INSTANCES,), probe.reasons)

    def test_wait_for_server_reports_an_unreachable_server(self):
        client = FakeClient(instances=call_from(stderr=UNREACHABLE_STDERR, exit_code=1))
        probe = mcp.wait_for_server(
            client, timeout=2.0, poll_interval=0.0,
            clock=self.clock, sleep=self.slept.append,
        )
        self.assertFalse(probe.reachable)


# ---------------------------------------------------------------------------
# The pin, the argv, and the bind refusal
# ---------------------------------------------------------------------------

class PinAndArgvTests(unittest.TestCase):
    def test_the_mcp_commit_is_bound_to_the_lock_file(self):
        # The Unity version pin is relaxed by standing ruling; this one is NOT.
        lock = json.loads(_LOCK.read_text(encoding="utf-8"))
        self.assertEqual(lock["upstream"]["commit"], mcp.MCP_SERVER_COMMIT)
        self.assertIn(mcp.MCP_SERVER_COMMIT, mcp.MCP_SERVER_SPEC)

    def test_the_spec_pins_a_commit_not_a_tag_or_a_branch(self):
        self.assertIn("@" + mcp.MCP_SERVER_COMMIT, mcp.MCP_SERVER_SPEC)
        self.assertIn("#subdirectory=Server", mcp.MCP_SERVER_SPEC)

    def test_server_argv_is_an_array_carrying_the_pin_and_the_port(self):
        argv = mcp.mcp_server_argv(host="127.0.0.1", port=54321)
        self.assertIsInstance(argv, list)
        self.assertIn(mcp.MCP_SERVER_SPEC, argv)
        self.assertEqual("54321", argv[argv.index("--http-port") + 1])
        self.assertEqual("127.0.0.1", argv[argv.index("--http-host") + 1])

    def test_cli_argv_puts_instance_among_the_global_options(self):
        # The pinned CLI reads -i/--instance as a GLOBAL option; after the
        # subcommand it is not accepted, and the call would silently address
        # whichever session the server chose.
        argv = mcp.mcp_cli_argv("raw", "get_editor_state", host="127.0.0.1", port=1, instance="P@abc")
        self.assertLess(argv.index("--instance"), argv.index("raw"))
        self.assertEqual("P@abc", argv[argv.index("--instance") + 1])
        self.assertLess(argv.index("--format"), argv.index("raw"))

    def test_start_mcp_refuses_a_non_loopback_bind(self):
        # `process_factory` is a NO-OP here on purpose, and the assertion below
        # is what makes that necessary rather than tidy. The obvious way to
        # write this test is to call start_mcp with its real default factory
        # and rely on the guard to prevent a launch -- which means the moment
        # anyone mutates the guard to check the test, the test itself spawns a
        # real MCP server on 0.0.0.0. That happened while mutation-testing this
        # module: two servers, network-exposed, from a test asserting they
        # could not exist. A safety test must not depend on the safety it
        # tests, so nothing here can launch anything.
        launched = []

        def never(*args, **kwargs):
            launched.append(args)
            raise AssertionError("start_mcp launched a server for a refused host")

        for host in ("0.0.0.0", "192.168.1.10", "::", "example.com"):
            with self.subTest(host=host):
                with self.assertRaises(EvidenceError) as caught:
                    mcp.start_mcp("/tmp", host=host, port=1234, process_factory=never)
                self.assertEqual("E_UNITY_MCP_BIND", caught.exception.code)
        self.assertEqual([], launched)

    def test_start_mcp_sets_disable_telemetry_and_returns_the_port(self):
        seen = {}

        def factory(argv, *, cwd, env, stdout_path, stderr_path, **kwargs):
            seen["argv"] = list(argv)
            seen["env"] = dict(env)
            return object()

        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            _, port = mcp.start_mcp(
                tmp, port=54321, env={"PATH": "/usr/bin"}, process_factory=factory
            )
        self.assertEqual(54321, port)
        self.assertEqual("1", seen["env"]["DISABLE_TELEMETRY"])
        self.assertIn("--http-host", seen["argv"])

    def test_reserve_local_port_returns_a_usable_loopback_port(self):
        port = mcp.reserve_local_port()
        self.assertGreater(port, 0)
        self.assertLess(port, 65536)


# ---------------------------------------------------------------------------
# Test jobs -- SOURCE FACT 7
# ---------------------------------------------------------------------------

def job(status="succeeded", **summary):
    counts = {"total": 1, "passed": 1, "failed": 0, "skipped": 0, "resultState": "Passed"}
    counts.update(summary)
    return {
        "success": True,
        "data": {
            "job_id": "job-1",
            "status": status,
            "result": {"mode": "EditMode", "summary": counts},
        },
    }


class TestJobTests(unittest.TestCase):
    def test_a_still_running_job_is_refused_not_summarised(self):
        # The MCP analogue of Task 5's missing results.xml: a zeroed summary
        # would read as a clean empty pass.
        payload = {"success": True, "data": {"job_id": "j", "status": "running"}}
        with self.assertRaises(EvidenceError) as caught:
            mcp.parse_test_job(payload)
        self.assertEqual("E_UNITY_MCP_RESULTS_MISSING", caught.exception.code)

    def test_a_running_job_carrying_partial_counts_is_still_refused(self):
        # The sharper form of the test above: a running job that ALREADY has a
        # summary attached is the shape that tempts a reader into reporting
        # it. Without the terminal-status gate this payload parses cleanly into
        # "1 passed" for a run that has not finished.
        payload = job(status="running")
        with self.assertRaises(EvidenceError) as caught:
            mcp.parse_test_job(payload)
        self.assertEqual("E_UNITY_MCP_RESULTS_MISSING", caught.exception.code)
        self.assertIn("running", caught.exception.detail)

    def test_a_finished_job_with_no_result_object_is_refused(self):
        payload = {"success": True, "data": {"job_id": "j", "status": "succeeded"}}
        with self.assertRaises(EvidenceError) as caught:
            mcp.parse_test_job(payload)
        self.assertEqual("E_UNITY_MCP_RESULTS_MISSING", caught.exception.code)

    def test_counts_that_do_not_add_up_are_malformed(self):
        with self.assertRaises(EvidenceError) as caught:
            mcp.parse_test_job(job(total=5))
        self.assertEqual("E_UNITY_MCP_RESULTS_MALFORMED", caught.exception.code)

    def test_a_non_integer_count_is_malformed(self):
        with self.assertRaises(EvidenceError) as caught:
            mcp.parse_test_job(job(passed="1"))
        self.assertEqual("E_UNITY_MCP_RESULTS_MALFORMED", caught.exception.code)

    def test_a_boolean_count_is_not_an_integer(self):
        with self.assertRaises(EvidenceError):
            mcp.parse_test_job(job(passed=True, total=True))

    def test_one_passing_test_is_a_pass(self):
        summary = mcp.parse_test_job(job())
        result = routes._tests_from_job(summary)
        self.assertEqual("pass", result.status)
        self.assertEqual(1, result.passed)

    def test_a_failure_is_a_fail(self):
        summary = mcp.parse_test_job(
            job(status="failed", total=1, passed=0, failed=1, resultState="Failed")
        )
        self.assertEqual("fail", routes._tests_from_job(summary).status)

    def test_an_entirely_skipped_run_is_neither(self):
        # Same rule as the headless route's _tests_from_summary: the contract
        # requires skipped=0 for a pass, so a skipped run cannot round toward
        # either claim.
        summary = mcp.parse_test_job(
            job(total=1, passed=0, skipped=1, resultState="Skipped")
        )
        with self.assertRaises(EvidenceError) as caught:
            routes._tests_from_job(summary)
        self.assertEqual("E_UNITY_RESULTS_UNRESOLVED", caught.exception.code)

    def test_a_cancelled_job_is_not_a_pass(self):
        summary = mcp.parse_test_job(job(status="cancelled"))
        with self.assertRaises(EvidenceError):
            routes._tests_from_job(summary)

    def test_run_tests_polls_the_job_to_a_terminal_state(self):
        client = FakeClient(
            script={
                "editor tests": call_from(
                    stdout=json.dumps({
                        "success": True,
                        "data": {"job_id": "job-1", "status": "running"},
                    })
                ),
                "raw get_test_job": [
                    call_from(stdout=json.dumps(
                        {"success": True, "data": {"job_id": "job-1", "status": "running"}}
                    )),
                    call_from(stdout=json.dumps(job())),
                ],
            }
        )
        ticks = iter([0.0, 1.0, 2.0, 3.0, 4.0])
        summary = mcp.run_tests_via_mcp(
            client,
            instance=mcp.McpInstance("s", "P", "abc", EDITOR_VERSION),
            timeout=10.0,
            poll_interval=0.0,
            clock=lambda: next(ticks),
            sleep=lambda _: None,
        )
        self.assertEqual(1, summary.passed)
        # `--async` is what makes the job id the contract; the single-call
        # `--wait` form the brief listed cannot return a summary at all.
        started = [args for args, _ in client.calls if args[:2] == ("editor", "tests")]
        self.assertIn("--async", started[0])

    def test_a_job_that_never_finishes_before_the_deadline_is_refused(self):
        running = call_from(stdout=json.dumps(
            {"success": True, "data": {"job_id": "job-1", "status": "running"}}
        ))
        client = FakeClient(script={"editor tests": running, "raw get_test_job": running})
        ticks = iter([0.0, 1.0, 2.0, 3.0, 4.0, 5.0])
        with self.assertRaises(EvidenceError) as caught:
            mcp.run_tests_via_mcp(
                client,
                instance=mcp.McpInstance("s", "P", "abc", EDITOR_VERSION),
                timeout=2.0, poll_interval=0.0,
                clock=lambda: next(ticks), sleep=lambda _: None,
            )
        self.assertEqual("E_UNITY_MCP_RESULTS_MISSING", caught.exception.code)

    def test_a_start_that_returns_no_job_id_is_refused(self):
        client = FakeClient(script={
            "editor tests": call_from(stdout=json.dumps({"success": True, "data": {}}))
        })
        with self.assertRaises(EvidenceError) as caught:
            mcp.run_tests_via_mcp(
                client, instance=mcp.McpInstance("s", "P", "abc", EDITOR_VERSION)
            )
        self.assertEqual("E_UNITY_MCP_TESTS_START", caught.exception.code)

    def test_a_start_that_returned_no_json_is_refused(self):
        client = FakeClient(script={
            "editor tests": call_from(stderr=NO_INSTANCE_STDERR, exit_code=1)
        })
        with self.assertRaises(EvidenceError) as caught:
            mcp.run_tests_via_mcp(
                client, instance=mcp.McpInstance("s", "P", "abc", EDITOR_VERSION)
            )
        self.assertEqual("E_UNITY_MCP_TESTS_START", caught.exception.code)


# ---------------------------------------------------------------------------
# Console
# ---------------------------------------------------------------------------

def console(*messages):
    return call_from(stdout=json.dumps({
        "success": True,
        "data": {"messages": [{"message": text} for text in messages]},
    }))


class ConsoleTests(unittest.TestCase):
    instance = mcp.McpInstance("s", "P", "abc", EDITOR_VERSION)

    def test_distinct_diagnostics_are_counted_once_each(self):
        client = FakeClient(script={"raw read_console": console(
            "Assets/KingletSpike/Editor/Broken.cs(1,102): error CS1002: ; expected",
            "Assets/KingletSpike/Editor/Broken.cs(1,102): error CS1002: ; expected",
            "error CS8034: assembly-level diagnostic",
        )})
        count, messages = mcp.read_console_errors(client, instance=self.instance)
        self.assertEqual(2, count)
        self.assertEqual(2, len(messages))

    def test_prose_that_merely_mentions_a_diagnostic_is_not_a_compile_error(self):
        # A PASSING run echoes test names and assertion messages into the
        # console. An unanchored `error CS` search would turn one of those into
        # a compile failure over a healthy project.
        client = FakeClient(script={"raw read_console": console(
            "Test Handles_error_CS1002_Gracefully passed",
            "Expected: error CS1002: ; expected",
        )})
        count, _ = mcp.read_console_errors(client, instance=self.instance)
        self.assertEqual(0, count)

    def test_a_clean_console_reports_zero(self):
        client = FakeClient(script={"raw read_console": console("Hello")})
        self.assertEqual(0, mcp.read_console_errors(client, instance=self.instance)[0])

    def test_an_unreadable_console_raises_rather_than_reporting_zero(self):
        # "We could not read it" and "it is clean" are the same value under a
        # permissive reading, and only one of them supports compile=pass.
        client = FakeClient(script={
            "raw read_console": call_from(stderr=NO_INSTANCE_STDERR, exit_code=1)
        })
        with self.assertRaises(EvidenceError) as caught:
            mcp.read_console_errors(client, instance=self.instance)
        self.assertEqual("E_UNITY_MCP_CONSOLE", caught.exception.code)

    def test_a_bare_list_payload_is_accepted(self):
        # The shape the pinned ReadConsole.cs returns when paging is OFF -- our
        # request sets neither `cursor` nor `pageSize`, so this is today's path.
        client = FakeClient(script={"raw read_console": call_from(stdout=json.dumps({
            "success": True,
            "data": [{"message": "error CS0103: name not found"}],
        }))})
        self.assertEqual(1, mcp.read_console_errors(client, instance=self.instance)[0])

    # -- shapes that must be READ, or REFUSED -- never silently "clean" -------
    #
    # Every test below failed against the first version of read_console_errors,
    # which fell through to `entries = []` and reported (0, ()) -- i.e. "the
    # console is clean" for a console it had not read. Downstream that becomes
    # `compile=pass, errors=0` in a published receipt (routes.py), and the
    # post-test re-read reports zero too, so E_UNITY_RESULTS_CONFLICT never
    # fires either. It is the exact defect class this task exists to remove,
    # on the one field the plan requires MCP and headless to publish alike.

    def test_the_paging_shape_is_read_not_reported_clean(self):
        # `MCPForUnity/Editor/Tools/ReadConsole.cs` returns
        # {cursor, pageSize, nextCursor, truncated, total, items} whenever
        # `usePaging = pageSize.HasValue || cursor.HasValue`. One added
        # parameter -- ours or a future default -- moves us onto this shape.
        client = FakeClient(script={"raw read_console": call_from(stdout=json.dumps({
            "success": True,
            "data": {
                "cursor": 0, "pageSize": 50, "nextCursor": None,
                "truncated": False, "total": 1,
                "items": [{"message": "Assets/A.cs(1,1): error CS1002: ; expected"}],
            },
        }))})
        count, messages = mcp.read_console_errors(client, instance=self.instance)
        self.assertEqual(1, count)
        self.assertEqual(1, len(messages))

    def test_an_empty_page_is_a_read_console_and_reports_zero(self):
        # The other half of the pair: `items: []` is a console we DID read and
        # that really is clean. It must not be swept up by the refusal.
        client = FakeClient(script={"raw read_console": call_from(stdout=json.dumps({
            "success": True,
            "data": {"cursor": 0, "pageSize": 50, "truncated": False,
                     "total": 0, "items": []},
        }))})
        self.assertEqual(0, mcp.read_console_errors(client, instance=self.instance)[0])

    def test_a_dict_with_no_recognised_entry_key_is_refused(self):
        # Errors are RIGHT THERE and the old code reported the console clean.
        client = FakeClient(script={"raw read_console": call_from(stdout=json.dumps({
            "success": True,
            "data": {"count": 2, "lines": ["Assets/A.cs(1,1): error CS1002: ; expected"]},
        }))})
        with self.assertRaises(EvidenceError) as caught:
            mcp.read_console_errors(client, instance=self.instance)
        self.assertEqual("E_UNITY_MCP_CONSOLE", caught.exception.code)

    def test_a_reply_with_no_data_key_at_all_is_refused(self):
        client = FakeClient(script={
            "raw read_console": call_from(stdout=json.dumps({"success": True}))
        })
        with self.assertRaises(EvidenceError) as caught:
            mcp.read_console_errors(client, instance=self.instance)
        self.assertEqual("E_UNITY_MCP_CONSOLE", caught.exception.code)

    def test_a_null_data_payload_is_refused(self):
        client = FakeClient(script={
            "raw read_console": call_from(stdout=json.dumps({"success": True, "data": None}))
        })
        with self.assertRaises(EvidenceError) as caught:
            mcp.read_console_errors(client, instance=self.instance)
        self.assertEqual("E_UNITY_MCP_CONSOLE", caught.exception.code)

    def test_a_scalar_data_payload_is_refused(self):
        client = FakeClient(script={
            "raw read_console": call_from(stdout=json.dumps({"success": True, "data": 7}))
        })
        with self.assertRaises(EvidenceError) as caught:
            mcp.read_console_errors(client, instance=self.instance)
        self.assertEqual("E_UNITY_MCP_CONSOLE", caught.exception.code)

    def test_a_recognised_key_holding_a_non_list_is_refused(self):
        # `items` present but not a list is not a console we read either.
        client = FakeClient(script={"raw read_console": call_from(stdout=json.dumps({
            "success": True, "data": {"items": "error CS1002: ; expected"},
        }))})
        with self.assertRaises(EvidenceError):
            mcp.read_console_errors(client, instance=self.instance)



# ---------------------------------------------------------------------------
# The route
# ---------------------------------------------------------------------------

class FakeUnityLaunch:
    """One scripted Unity launch, standing in for ManagedProcess."""

    def __init__(self, owner, argv, *, exit_code=0, survivors=()):
        self.owner = owner
        self.argv = list(argv)
        self.exit_code = exit_code
        self.survivors = survivors
        self.pid = 4242
        self.pgid = 4242
        self.cancelled = False

    def wait(self, timeout_seconds):
        return self.exit_code

    def cancel(self, deadline_seconds):
        self.cancelled = True
        self.owner.cancelled.append(self.argv)
        return CleanupResult(
            signalled=False, escalated=False,
            survivors=self.survivors, exit_code=self.exit_code,
        )


class UnityFleet:
    """Records every launch this route makes and scripts each one's outcome."""

    def __init__(self, *, configure_exit=0, write_backup=True, survivors=()):
        self.configure_exit = configure_exit
        self.write_backup = write_backup
        self.survivors = survivors
        self.launches: list[list[str]] = []
        self.cancelled: list[list[str]] = []

    def factory(self, argv, *, cwd, env, stdout_path, stderr_path, **kwargs):
        argv = list(argv)
        self.launches.append(argv)
        Path(stdout_path).write_text("", encoding="utf-8")
        Path(stderr_path).write_text("", encoding="utf-8")
        if "-executeMethod" in argv:
            method = argv[argv.index("-executeMethod") + 1]
            if method == routes.CONFIGURE_METHOD:
                if self.write_backup:
                    Path(env["KINGLET_MCP_PREFS_BACKUP"]).write_text(
                        json.dumps({"autoStartPresent": False}), encoding="utf-8"
                    )
                return FakeUnityLaunch(self, argv, exit_code=self.configure_exit)
            return FakeUnityLaunch(self, argv)
        if argv[0].endswith("uvx") or "mcp-for-unity" in argv:
            return FakeUnityLaunch(self, argv)
        return FakeUnityLaunch(self, argv, survivors=self.survivors)

    @property
    def methods(self):
        return [
            a[a.index("-executeMethod") + 1] for a in self.launches if "-executeMethod" in a
        ]

    def launched_gui(self):
        return any(
            "-batchmode" not in a and "-projectPath" in a and "-executeMethod" not in a
            for a in self.launches
        )


class LiveRouteTests(unittest.TestCase):
    def setUp(self):
        import tempfile
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.project = make_project(self.root / "project")
        self.raw = self.root / "raw"
        self.editor = self.root / "Unity"
        self.editor.write_text("#!/bin/sh\n", encoding="utf-8")
        self.fleet = UnityFleet()

    def lease_dir(self):
        return self.root / "leases"

    def lease_files(self):
        directory = self.lease_dir()
        if not directory.is_dir():
            return []
        return sorted(p.name for p in directory.glob("*.lease.json"))

    def client_factory(self, *, ready=True, console_messages=(), job_payload=None, **_):
        project = self.project
        state = state_call() if ready else state_call(**{"compilation.is_compiling": True})
        script = {
            "raw read_console": console(*console_messages),
            "editor refresh": call_from(stdout='{"success": true}'),
            "editor tests": call_from(stdout=json.dumps(
                {"success": True, "data": {"job_id": "job-1", "status": "running"}}
            )),
            "raw get_test_job": call_from(
                stdout=json.dumps(job_payload if job_payload is not None else job())
            ),
        }
        client = FakeClient(
            instances=lambda: instances_payload(entry_for(project)),
            state=state,
            script=script,
        )
        self.client = client
        return lambda **kwargs: client

    def run_route(self, *, client_factory=None, **overrides):
        kwargs = dict(
            process_table_provider=empty_process_table,
            windows=False,
            run_version_flag=version_stdout(),
            process_factory=self.fleet.factory,
            client_factory=client_factory or self.client_factory(),
            env={"PATH": "/usr/bin"},
            port=54321,
            lease_dir=self.lease_dir(),
            editor_ready_timeout=0.0,
            server_ready_timeout=0.0,
            tests_timeout=0.0,
        )
        kwargs.update(overrides)
        return routes.run_live_editor_mcp(self.editor, self.project, self.raw, **kwargs)

    # -- happy path ---------------------------------------------------------

    def test_a_ready_editor_produces_a_valid_passing_receipt(self):
        receipt = self.run_route()
        self.assertEqual(routes.LIVE_EDITOR_MCP_ROUTE, receipt.route)
        self.assertEqual(RECEIPT_SCHEMA, receipt.schema)
        self.assertEqual(PROJECT_ID, receipt.project_id)
        self.assertEqual(EDITOR_VERSION, receipt.unity_version)
        self.assertEqual("pass", receipt.compile.status)
        self.assertEqual("pass", receipt.tests.status)
        self.assertEqual((1, 0, 0), (receipt.tests.passed, receipt.tests.failed, receipt.tests.skipped))
        self.assertTrue(receipt.ready)
        self.assertFalse(receipt.collision_refused)
        self.assertFalse(receipt.active_lease)
        self.assertEqual((), receipt.descendant_pids)
        self.assertEqual((), validate_unity_receipt(receipt))

    def test_the_receipt_round_trips_through_the_frozen_parser(self):
        receipt = self.run_route()
        again = unity_receipt_from_dict(routes.receipt_to_dict(receipt))
        self.assertEqual(receipt, again)
        self.assertEqual((), validate_unity_receipt(again))

    def test_the_full_launch_order_is_configure_then_gui_then_restore(self):
        self.run_route()
        self.assertEqual(
            [routes.CONFIGURE_METHOD, routes.RESTORE_METHOD], self.fleet.methods
        )
        self.assertTrue(self.fleet.launched_gui())

    def test_the_gui_editor_is_not_launched_in_batchmode(self):
        self.run_route()
        gui = [a for a in self.fleet.launches
               if "-projectPath" in a and "-executeMethod" not in a and "--http-port" not in a]
        self.assertEqual(1, len(gui))
        self.assertNotIn("-batchmode", gui[0])
        self.assertIn("-logFile", gui[0])

    def test_the_prefs_passes_use_quit_because_they_do_not_run_tests(self):
        self.run_route()
        for argv in self.fleet.launches:
            if "-executeMethod" in argv:
                self.assertIn("-quit", argv)
                self.assertNotIn("-runTests", argv)

    def test_every_launch_is_cancelled_and_the_lease_is_released(self):
        self.run_route()
        self.assertEqual([], self.lease_files())
        # Configure pass, MCP server, GUI Editor, restore pass.
        self.assertEqual(len(self.fleet.launches), len(self.fleet.cancelled))

    def test_a_summary_artifact_is_written_and_named_in_the_receipt(self):
        receipt = self.run_route()
        summary = self.raw / routes.LIVE_MCP_SUMMARY_NAME
        self.assertTrue(summary.is_file())
        body = json.loads(summary.read_text(encoding="utf-8"))
        self.assertEqual(mcp.MCP_SERVER_COMMIT, body["mcp_commit"])
        self.assertTrue(body["ready"])
        self.assertIn(
            f"{routes.ARTIFACT_PREFIX}/{routes.LIVE_MCP_SUMMARY_NAME}", receipt.artifacts
        )

    def test_survivors_are_recorded_rather_than_swallowed(self):
        self.fleet.survivors = (777,)
        receipt = self.run_route()
        self.assertIn(777, receipt.descendant_pids)
        # And the validator turns that receipt into a failure: a leak is
        # evidence, not an exception to be lost.
        self.assertTrue(validate_unity_receipt(receipt))

    # -- refusals -----------------------------------------------------------

    def test_an_owned_project_raises_and_never_emits_a_collision_receipt(self):
        # collision_refused is same-project-headless's probe; the contract and
        # validate_unity_receipt both reject it on this route, so there is no
        # honest receipt to return here.
        table = lambda: ((99001, (str(self.editor), "-projectPath", str(self.project))),)
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(process_table_provider=table)
        self.assertIn(caught.exception.code, ("E_UNITY_OWNED", "E_UNITY_OWNER_UNKNOWN"))
        self.assertEqual([], self.fleet.launches)
        self.assertEqual([], self.lease_files())

    def test_a_version_mismatch_refuses_before_anything_launches(self):
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(run_version_flag=version_stdout("6000.0.68f1"))
        self.assertEqual("E_UNITY_VERSION", caught.exception.code)
        self.assertEqual([], self.fleet.launches)

    def test_a_configure_pass_that_failed_stops_the_route(self):
        self.fleet.configure_exit = 1
        with self.assertRaises(EvidenceError) as caught:
            self.run_route()
        self.assertEqual("E_UNITY_MCP_CONFIGURE", caught.exception.code)
        self.assertFalse(self.fleet.launched_gui())
        self.assertEqual([], self.lease_files())

    def test_a_configure_pass_that_wrote_no_backup_stops_the_route(self):
        # Without a backup the developer's EditorPrefs cannot be put back, so
        # the route refuses to change anything further.
        self.fleet.write_backup = False
        with self.assertRaises(EvidenceError) as caught:
            self.run_route()
        self.assertEqual("E_UNITY_MCP_CONFIGURE", caught.exception.code)
        self.assertFalse(self.fleet.launched_gui())

    def test_an_unreachable_server_never_launches_the_editor(self):
        unreachable = FakeClient(instances=call_from(stderr=UNREACHABLE_STDERR, exit_code=1))
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(client_factory=lambda **kwargs: unreachable)
        self.assertEqual("E_UNITY_MCP_NOT_READY", caught.exception.code)
        self.assertIn(mcp.CATEGORY_SERVER_START_FAILED, caught.exception.detail)
        self.assertFalse(self.fleet.launched_gui())
        self.assertEqual([], self.lease_files())

    def test_an_editor_that_never_gets_ready_refuses_and_still_restores_prefs(self):
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(client_factory=self.client_factory(ready=False))
        self.assertEqual("E_UNITY_MCP_NOT_READY", caught.exception.code)
        self.assertIn(mcp.CATEGORY_EDITOR_NOT_READY, caught.exception.detail)
        # The GUI went up, so the finally has real work to do -- and does it.
        self.assertTrue(self.fleet.launched_gui())
        self.assertIn(routes.RESTORE_METHOD, self.fleet.methods)
        self.assertEqual([], self.lease_files())

    def test_a_server_with_zero_instances_forever_is_an_editor_failure(self):
        # The MEASURED exit-0 success shape, driven through the whole route.
        zero = FakeClient(instances=call_from(stdout=ZERO_INSTANCES_STDOUT))
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(client_factory=lambda **kwargs: zero)
        self.assertIn(mcp.CATEGORY_EDITOR_NOT_READY, caught.exception.detail)
        self.assertNotIn(mcp.CATEGORY_SERVER_START_FAILED, caught.exception.detail)

    def test_compile_errors_produce_a_failing_compile_and_no_test_claim(self):
        factory = self.client_factory(
            console_messages=("Assets/A.cs(1,1): error CS1002: ; expected",)
        )
        receipt = self.run_route(client_factory=factory)
        self.assertEqual("fail", receipt.compile.status)
        self.assertEqual(1, receipt.compile.errors)
        self.assertEqual("not-run", receipt.tests.status)
        self.assertEqual((), validate_unity_receipt(receipt))
        # No test job was ever started over a broken compile.
        self.assertEqual(
            [], [a for a, _ in self.client.calls if a[:2] == ("editor", "tests")]
        )

    def test_an_unread_console_never_reaches_a_compile_pass_receipt(self):
        # The failure scenario end to end. If read_console_errors reports
        # (0, ()) for a shape it never parsed, this route writes
        # compile=pass/errors=0 -- and the post-test re-read reports zero too,
        # so E_UNITY_RESULTS_CONFLICT never fires to catch it. The receipt
        # then publishes a passing compile over a console nobody read.
        factory = self.client_factory()
        self.client.script["raw read_console"] = call_from(stdout=json.dumps({
            "success": True,
            "data": {"count": 1, "lines": ["Assets/A.cs(1,1): error CS1002: ; expected"]},
        }))
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(client_factory=factory)
        self.assertEqual("E_UNITY_MCP_CONSOLE", caught.exception.code)
        self.assertEqual([], self.lease_files())
        self.assertIn(routes.RESTORE_METHOD, self.fleet.methods)

    def test_a_skipped_only_run_is_refused_rather_than_reported(self):
        factory = self.client_factory(
            job_payload=job(total=1, passed=0, skipped=1, resultState="Skipped")
        )
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(client_factory=factory)
        self.assertEqual("E_UNITY_RESULTS_UNRESOLVED", caught.exception.code)
        self.assertEqual([], self.lease_files())

    def test_the_lease_is_released_on_every_path(self):
        for scenario in ("ok", "not-ready", "no-backup"):
            with self.subTest(scenario=scenario):
                self.setUp()
                if scenario == "ok":
                    self.run_route()
                elif scenario == "not-ready":
                    with self.assertRaises(EvidenceError):
                        self.run_route(client_factory=self.client_factory(ready=False))
                else:
                    self.fleet.write_backup = False
                    with self.assertRaises(EvidenceError):
                        self.run_route()
                self.assertEqual([], self.lease_files())


# ---------------------------------------------------------------------------
# Contract binding
# ---------------------------------------------------------------------------

class LiveContractBindingTests(unittest.TestCase):
    def setUp(self):
        self.contract = json.loads(_CONTRACT.read_text(encoding="utf-8"))

    def test_the_route_name_is_the_contract_name(self):
        self.assertIn(routes.LIVE_EDITOR_MCP_ROUTE, self.contract["routes"])
        self.assertIn(routes.LIVE_EDITOR_MCP_ROUTE, self.contract["executing_routes"])

    def test_the_live_timeout_is_the_sum_of_its_contract_phases(self):
        timings = self.contract["timings_seconds"]
        expected = sum(timings[phase] for phase in routes.LIVE_MCP_TIMEOUT_PHASES)
        self.assertEqual(float(expected), routes.LIVE_MCP_TIMEOUT_SECONDS)

    def test_the_mcp_phase_budgets_are_the_contract_values(self):
        timings = self.contract["timings_seconds"]
        self.assertEqual(float(timings["mcp_server_startup"]), mcp.MCP_SERVER_STARTUP_SECONDS)
        self.assertEqual(float(timings["mcp_editor_ready"]), mcp.MCP_EDITOR_READY_SECONDS)
        self.assertEqual(float(timings["edit_mode_tests"]), mcp.EDIT_MODE_TESTS_SECONDS)

    def test_only_this_route_may_claim_ready(self):
        # Restates the frozen rule this whole module serves, executed rather
        # than quoted: a passing claim from this route requires ready=true.
        from .unity_support import passing_receipt

        value = passing_receipt(routes.LIVE_EDITOR_MCP_ROUTE)
        value["ready"] = False
        diagnostics = validate_unity_receipt(unity_receipt_from_dict(value))
        self.assertTrue(any(d.location == "ready" for d in diagnostics))


if __name__ == "__main__":
    unittest.main()
