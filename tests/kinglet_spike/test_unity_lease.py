"""test_unity_lease.py -- Per-workspace lease keyed by canonical physical path.

Two routes may run at the same time only when they touch different physical
projects. `same-project-headless` and a live GUI Editor are the same physical
project reached two ways; `isolated-headless` is a different physical copy.
So the lease's identity has to be the resolved physical path -- not the string
the caller typed, and not the route -- or the exclusion is decorative.

The asymmetry this module is designed around, stated once so every branch below
can be checked against it: FAILING to take a lease costs a refused run, which
is visible and recoverable. WRONGLY taking one lets two Unity processes open a
single project, which is the corruption the whole plan exists to prevent. So
every case this module cannot resolve -- a malformed lease file, a competitor
whose liveness cannot be determined -- refuses. There is no permissive
fallthrough, and `test_no_unresolved_case_falls_through_to_acquire` pins that.
"""
from __future__ import annotations

import hashlib
import json
import os
import time
import unittest
import uuid
from pathlib import Path
from tempfile import TemporaryDirectory

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.unity import lease as lease_module
from tools.kinglet_spike.unity.lease import (
    LEASE_SCHEMA,
    LeaseRecord,
    WorkspaceLease,
    _holder_liveness,
    default_group_is_live,
    default_process_starttime,
    lease_path_for,
    physical_path_hash,
    read_lease,
)


class _Clock:
    def __init__(self, start: float = 1_700_000_000.0):
        self.now = start

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


class _LeaseCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.project = self.root / "project"
        self.project.mkdir()
        self.leases = self.root / "run" / "leases"
        self.clock = _Clock()

    def acquire(self, project=None, *, route="same-project-headless", ttl=300.0,
                pid=4242, pid_is_live=lambda _pid: False,
                group_is_live=lambda _pgid: False,
                starttime_reader=lambda _pid: None, owner=None):
        return WorkspaceLease.acquire(
            project if project is not None else self.project,
            route=route,
            lease_dir=self.leases,
            ttl_seconds=ttl,
            pid=pid,
            clock=self.clock,
            uuid_factory=(lambda: owner) if owner else (lambda: str(uuid.uuid4())),
            pid_is_live=pid_is_live,
            group_is_live=group_is_live,
            starttime_reader=starttime_reader,
        )


class IdentityTests(_LeaseCase):
    def test_hash_is_sha256_of_the_normalized_physical_path(self):
        expected = hashlib.sha256(
            os.path.normcase(os.path.realpath(self.project)).encode("utf-8")
        ).hexdigest()
        self.assertEqual(expected, physical_path_hash(self.project))

    def test_a_symlink_alias_hashes_to_the_same_physical_path(self):
        alias = self.root / "alias"
        alias.symlink_to(self.project, target_is_directory=True)
        self.assertEqual(physical_path_hash(self.project), physical_path_hash(alias))

    def test_a_relative_and_dot_segment_path_hash_the_same(self):
        noisy = self.project / ".." / "project"
        self.assertEqual(physical_path_hash(self.project), physical_path_hash(noisy))

    def test_a_sibling_with_a_shared_prefix_hashes_differently(self):
        sibling = self.root / "project2"
        sibling.mkdir()
        self.assertNotEqual(physical_path_hash(self.project), physical_path_hash(sibling))

    def test_a_missing_path_is_refused_rather_than_hashed_optimistically(self):
        with self.assertRaises(EvidenceError) as ctx:
            physical_path_hash(self.root / "nope")
        self.assertEqual("E_UNITY_LEASE_PATH", ctx.exception.code)


class AcquireTests(_LeaseCase):
    def test_acquire_writes_the_contracted_fields(self):
        held = self.acquire(route="isolated-headless", pid=777)
        record = read_lease(held.path)
        self.assertEqual(LEASE_SCHEMA, record.schema)
        self.assertEqual(physical_path_hash(self.project), record.path_hash)
        self.assertEqual("isolated-headless", record.route)
        self.assertEqual(777, record.pid)
        self.assertEqual(held.owner, record.owner)
        self.assertTrue(record.acquired_utc.endswith("Z"))
        self.assertTrue(record.renewed_utc.endswith("Z"))
        self.assertTrue(record.expiry_utc.endswith("Z"))
        held.release()

    def test_the_lease_lives_below_the_run_directory_not_inside_the_project(self):
        held = self.acquire()
        self.addCleanup(held.release)
        self.assertTrue(str(held.path).startswith(str(self.leases)))
        self.assertEqual([], list(self.project.rglob("*")))

    def test_lease_file_name_is_the_hash_so_no_machine_path_is_written(self):
        held = self.acquire()
        self.addCleanup(held.release)
        self.assertEqual(lease_path_for(self.project, self.leases), held.path)
        blob = held.path.read_text(encoding="utf-8")
        self.assertNotIn(str(self.project), blob)

    def test_two_owners_of_the_same_canonical_path_conflict(self):
        first = self.acquire()
        self.addCleanup(first.release)
        with self.assertRaises(EvidenceError) as ctx:
            self.acquire()
        self.assertEqual("E_UNITY_LEASE_HELD", ctx.exception.code)

    def test_a_symlink_alias_conflicts_with_the_real_path(self):
        alias = self.root / "alias"
        alias.symlink_to(self.project, target_is_directory=True)
        first = self.acquire()
        self.addCleanup(first.release)
        with self.assertRaises(EvidenceError) as ctx:
            self.acquire(alias)
        self.assertEqual("E_UNITY_LEASE_HELD", ctx.exception.code)

    def test_a_different_physical_path_is_not_blocked(self):
        """isolated-headless works on a physical copy and must not be gated by
        the main project's lease."""
        isolated = self.root / "isolated-copy"
        isolated.mkdir()
        main = self.acquire(route="same-project-headless")
        self.addCleanup(main.release)
        other = self.acquire(isolated, route="isolated-headless")
        self.addCleanup(other.release)
        self.assertNotEqual(main.path, other.path)

    def test_the_same_route_twice_on_different_paths_is_allowed(self):
        isolated = self.root / "copy2"
        isolated.mkdir()
        a = self.acquire(route="isolated-headless")
        self.addCleanup(a.release)
        b = self.acquire(isolated, route="isolated-headless")
        self.addCleanup(b.release)
        self.assertNotEqual(a.owner, b.owner)


class CompetitorTests(_LeaseCase):
    def test_an_unexpired_competitor_is_refused_even_if_its_pid_is_dead(self):
        first = self.acquire(ttl=300.0)
        self.addCleanup(first.release)
        self.clock.advance(10.0)
        with self.assertRaises(EvidenceError) as ctx:
            self.acquire(pid_is_live=lambda _pid: False)
        self.assertEqual("E_UNITY_LEASE_HELD", ctx.exception.code)

    def test_an_expired_competitor_whose_pid_is_dead_is_replaced(self):
        first = self.acquire(ttl=60.0, pid=111, owner="owner-a")
        self.clock.advance(61.0)
        second = self.acquire(pid=222, owner="owner-b", pid_is_live=lambda _pid: False)
        self.addCleanup(second.release)
        self.assertEqual("owner-b", read_lease(second.path).owner)
        self.assertEqual(222, read_lease(second.path).pid)
        # The original holder must discover it lost the lease, not silently
        # keep renewing a file another owner now controls.
        with self.assertRaises(EvidenceError) as ctx:
            first.renew()
        self.assertEqual("E_UNITY_LEASE_LOST", ctx.exception.code)

    def test_an_expired_competitor_whose_pid_is_still_alive_is_refused(self):
        """An expired timestamp is not proof of death -- a stalled run holding
        a real Unity process is exactly the case that must not be stolen."""
        first = self.acquire(ttl=60.0, pid=111)
        self.addCleanup(first.release)
        self.clock.advance(61.0)
        with self.assertRaises(EvidenceError) as ctx:
            self.acquire(pid_is_live=lambda _pid: True)
        self.assertEqual("E_UNITY_LEASE_HELD", ctx.exception.code)

    def test_an_expired_competitor_of_unknown_liveness_is_ambiguous_not_free(self):
        first = self.acquire(ttl=60.0, pid=111)
        self.addCleanup(first.release)
        self.clock.advance(61.0)
        with self.assertRaises(EvidenceError) as ctx:
            self.acquire(pid_is_live=lambda _pid: None)
        self.assertEqual("E_UNITY_LEASE_UNKNOWN", ctx.exception.code)

    def test_malformed_json_is_refused_never_overwritten(self):
        self.leases.mkdir(parents=True, exist_ok=True)
        target = lease_path_for(self.project, self.leases)
        target.write_text("{not json", encoding="utf-8")
        with self.assertRaises(EvidenceError) as ctx:
            self.acquire()
        self.assertEqual("E_UNITY_LEASE_MALFORMED", ctx.exception.code)
        self.assertEqual("{not json", target.read_text(encoding="utf-8"))

    def test_a_wrong_schema_is_refused(self):
        self._write_raw({"schema": "something.else/v9"})
        with self.assertRaises(EvidenceError) as ctx:
            self.acquire()
        self.assertEqual("E_UNITY_LEASE_MALFORMED", ctx.exception.code)

    def test_a_payload_valid_in_every_way_except_its_schema_is_refused(self):
        """The schema check must carry its own weight.

        Without this case the schema guard is masked by the field checks: a
        foreign document usually lacks our fields anyway. A future format that
        happens to share them must still be refused, because the meaning of
        `expiry_utc` in someone else's schema is not ours to assume.
        """
        payload = self._valid_payload()
        payload["schema"] = "kinglet.unity-probe.lease/v2"
        self._write_raw(payload)
        with self.assertRaises(EvidenceError) as ctx:
            self.acquire()
        self.assertEqual("E_UNITY_LEASE_MALFORMED", ctx.exception.code)
        self.assertIn("schema", ctx.exception.detail)

    def test_each_missing_field_is_refused_individually(self):
        base = self._valid_payload()
        for field in ("owner", "path_hash", "route", "pid",
                      "acquired_utc", "renewed_utc", "expiry_utc",
                      "pgid", "holder_starttime"):
            with self.subTest(field=field):
                payload = dict(base)
                del payload[field]
                self._write_raw(payload)
                with self.assertRaises(EvidenceError) as ctx:
                    self.acquire()
                self.assertEqual("E_UNITY_LEASE_MALFORMED", ctx.exception.code)

    def test_a_wrongly_typed_field_is_refused(self):
        payload = self._valid_payload()
        payload["pid"] = "4242"
        self._write_raw(payload)
        with self.assertRaises(EvidenceError) as ctx:
            self.acquire()
        self.assertEqual("E_UNITY_LEASE_MALFORMED", ctx.exception.code)

    def test_a_lease_for_a_different_path_hash_in_our_slot_is_refused(self):
        payload = self._valid_payload()
        payload["path_hash"] = "0" * 64
        self._write_raw(payload)
        with self.assertRaises(EvidenceError) as ctx:
            self.acquire()
        self.assertEqual("E_UNITY_LEASE_MALFORMED", ctx.exception.code)

    def test_a_json_array_at_the_top_level_is_refused(self):
        self.leases.mkdir(parents=True, exist_ok=True)
        lease_path_for(self.project, self.leases).write_text("[]", encoding="utf-8")
        with self.assertRaises(EvidenceError) as ctx:
            self.acquire()
        self.assertEqual("E_UNITY_LEASE_MALFORMED", ctx.exception.code)

    def test_no_unresolved_case_falls_through_to_acquire(self):
        """The Task 3 defect, checked directly: every non-free state refuses."""
        states = (
            ("{not json", lambda _p: False),
            (json.dumps({"schema": "wrong"}), lambda _p: False),
            (json.dumps(self._valid_payload()), lambda _p: True),
            (json.dumps(self._valid_payload()), lambda _p: None),
        )
        self.leases.mkdir(parents=True, exist_ok=True)
        target = lease_path_for(self.project, self.leases)
        # Past the payload's own expiry, so the liveness branches are the ones
        # actually deciding in the last two cases.
        self.clock.now = 1_800_000_000.0
        for blob, liveness in states:
            with self.subTest(blob=blob[:24]):
                target.write_text(blob, encoding="utf-8")
                with self.assertRaises(EvidenceError):
                    self.acquire(pid_is_live=liveness)

    def _valid_payload(self) -> dict:
        return {
            "schema": LEASE_SCHEMA,
            "owner": "competitor-owner",
            "path_hash": physical_path_hash(self.project),
            "route": "same-project-headless",
            "pid": 4242,
            "acquired_utc": "2026-07-28T00:00:00Z",
            "renewed_utc": "2026-07-28T00:00:00Z",
            "expiry_utc": "2026-07-28T00:05:00Z",
            "pgid": None,
            "holder_starttime": None,
        }

    def _write_raw(self, payload: dict) -> None:
        self.leases.mkdir(parents=True, exist_ok=True)
        lease_path_for(self.project, self.leases).write_text(
            json.dumps(payload), encoding="utf-8"
        )


class HolderIdentityTests(_LeaseCase):
    """Round 1 review: the lease proved the WRONG process was dead.

    `acquire()` can only name the controller -- Unity does not exist yet. But
    `ManagedProcess` launches Unity with `start_new_session`, so Unity outlives
    its launcher: killing the controller leaves the whole group running. If the
    lease keeps pointing at the controller, then at TTL it reads as reclaimable
    while a live Unity still has the project open, which is the double-open
    this module exists to prevent.
    """

    def test_an_unbound_lease_names_the_controller_and_says_so(self):
        held = self.acquire(pid=4242)
        self.addCleanup(held.release)
        record = read_lease(held.path)
        self.assertIsNone(record.pgid)
        self.assertEqual(4242, record.pid)

    def test_bind_holder_repoints_the_lease_at_the_contained_group(self):
        held = self.acquire(pid=4242)
        self.addCleanup(held.release)
        held.bind_holder(pid=9001, pgid=9001)
        record = read_lease(held.path)
        self.assertEqual(9001, record.pid)
        self.assertEqual(9001, record.pgid)
        self.assertEqual(held.owner, record.owner)

    def test_bind_holder_does_not_move_acquired_or_expiry(self):
        held = self.acquire(ttl=60.0)
        self.addCleanup(held.release)
        before = read_lease(held.path)
        held.bind_holder(pid=9001, pgid=9001)
        after = read_lease(held.path)
        self.assertEqual(before.acquired_utc, after.acquired_utc)
        self.assertEqual(before.expiry_utc, after.expiry_utc)

    def test_bind_holder_of_someone_elses_lease_is_refused(self):
        held = self.acquire(owner="mine")
        payload = json.loads(held.path.read_text(encoding="utf-8"))
        payload["owner"] = "theirs"
        held.path.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaises(EvidenceError) as ctx:
            held.bind_holder(pid=9001, pgid=9001)
        self.assertEqual("E_UNITY_LEASE_LOST", ctx.exception.code)

    def test_renew_preserves_the_bound_holder(self):
        """Otherwise the first renew would silently un-point the lease."""
        held = self.acquire(ttl=60.0)
        self.addCleanup(held.release)
        held.bind_holder(pid=9001, pgid=9001)
        self.clock.advance(10.0)
        held.renew()
        record = read_lease(held.path)
        self.assertEqual(9001, record.pgid)
        self.assertEqual(9001, record.pid)

    def test_a_bound_lease_whose_group_is_alive_is_not_reclaimable(self):
        """The measured failure: controller gone, Unity group still running.

        `pid_is_live` deliberately says the recorded pid is DEAD here -- which
        is exactly what a crashed controller looks like. Before this fix that
        was enough to steal the lease.
        """
        held = self.acquire(ttl=60.0, pid=4242)
        self.addCleanup(held.release)
        held.bind_holder(pid=9001, pgid=9001)
        self.clock.advance(61.0)
        with self.assertRaises(EvidenceError) as ctx:
            self.acquire(pid_is_live=lambda _pid: False,
                         group_is_live=lambda _pgid: True)
        self.assertEqual("E_UNITY_LEASE_HELD", ctx.exception.code)
        self.assertIn("process group 9001", ctx.exception.detail)

    def test_a_bound_lease_whose_group_is_gone_is_reclaimable(self):
        held = self.acquire(ttl=60.0, pid=4242, owner="owner-a")
        held.bind_holder(pid=9001, pgid=9001)
        self.clock.advance(61.0)
        taken = self.acquire(owner="owner-b", pid_is_live=lambda _pid: True,
                             group_is_live=lambda _pgid: False)
        self.addCleanup(taken.release)
        self.assertEqual("owner-b", read_lease(taken.path).owner)

    def test_a_bound_lease_whose_group_cannot_be_enumerated_is_ambiguous(self):
        held = self.acquire(ttl=60.0)
        self.addCleanup(held.release)
        held.bind_holder(pid=9001, pgid=9001)
        self.clock.advance(61.0)
        with self.assertRaises(EvidenceError) as ctx:
            self.acquire(group_is_live=lambda _pgid: None)
        self.assertEqual("E_UNITY_LEASE_UNKNOWN", ctx.exception.code)

    def test_the_group_answer_overrides_the_pid_answer_entirely(self):
        """Once bound, the controller's pid is not consulted at all."""
        consulted = []
        record = LeaseRecord(
            schema=LEASE_SCHEMA, owner="o", path_hash="h", route="r", pid=4242,
            acquired_utc="x", renewed_utc="x", expiry_utc="x",
            pgid=9001, holder_starttime="123",
        )
        self.assertIs(True, _holder_liveness(
            record,
            pid_is_live=lambda pid: consulted.append(pid) or False,
            group_is_live=lambda _pgid: True,
            starttime_reader=lambda _pid: "999",
        ))
        self.assertEqual([], consulted)


class PidRecyclingTests(_LeaseCase):
    """An unbound lease's pid may have been handed to an unrelated process."""

    def test_a_recycled_pid_does_not_wedge_the_workspace(self):
        record = LeaseRecord(
            schema=LEASE_SCHEMA, owner="o", path_hash="h", route="r", pid=4242,
            acquired_utc="x", renewed_utc="x", expiry_utc="x",
            pgid=None, holder_starttime="111",
        )
        # The pid exists, but it started at a different time -- so it is a
        # different process, and the real holder is gone.
        self.assertIs(False, _holder_liveness(
            record,
            pid_is_live=lambda _pid: True,
            group_is_live=lambda _pgid: True,
            starttime_reader=lambda _pid: "222",
        ))

    def test_the_same_pid_with_the_same_start_time_is_the_same_holder(self):
        record = LeaseRecord(
            schema=LEASE_SCHEMA, owner="o", path_hash="h", route="r", pid=4242,
            acquired_utc="x", renewed_utc="x", expiry_utc="x",
            pgid=None, holder_starttime="111",
        )
        self.assertIs(True, _holder_liveness(
            record,
            pid_is_live=lambda _pid: True,
            group_is_live=lambda _pgid: False,
            starttime_reader=lambda _pid: "111",
        ))

    def test_without_a_recorded_start_time_the_answer_stays_conservative(self):
        record = LeaseRecord(
            schema=LEASE_SCHEMA, owner="o", path_hash="h", route="r", pid=4242,
            acquired_utc="x", renewed_utc="x", expiry_utc="x",
            pgid=None, holder_starttime=None,
        )
        self.assertIs(True, _holder_liveness(
            record,
            pid_is_live=lambda _pid: True,
            group_is_live=lambda _pgid: False,
            starttime_reader=lambda _pid: "222",
        ))

    def test_an_unreadable_current_start_time_stays_conservative(self):
        record = LeaseRecord(
            schema=LEASE_SCHEMA, owner="o", path_hash="h", route="r", pid=4242,
            acquired_utc="x", renewed_utc="x", expiry_utc="x",
            pgid=None, holder_starttime="111",
        )
        self.assertIs(True, _holder_liveness(
            record,
            pid_is_live=lambda _pid: True,
            group_is_live=lambda _pgid: False,
            starttime_reader=lambda _pid: None,
        ))

    def test_a_dead_pid_is_dead_without_consulting_start_time(self):
        record = LeaseRecord(
            schema=LEASE_SCHEMA, owner="o", path_hash="h", route="r", pid=4242,
            acquired_utc="x", renewed_utc="x", expiry_utc="x",
            pgid=None, holder_starttime="111",
        )
        self.assertIs(False, _holder_liveness(
            record,
            pid_is_live=lambda _pid: False,
            group_is_live=lambda _pgid: True,
            starttime_reader=lambda _pid: "111",
        ))


class RealHolderProbeTests(_LeaseCase):
    """The default seams, driven against this host rather than stubs."""

    def test_real_start_time_is_stable_for_one_process(self):
        if not os.path.exists("/proc/self/stat"):
            self.skipTest("linux-only source")
        first = default_process_starttime(os.getpid())
        self.assertIsNotNone(first)
        self.assertEqual(first, default_process_starttime(os.getpid()))

    def test_real_start_time_differs_between_two_processes(self):
        if not os.path.exists("/proc/self/stat"):
            self.skipTest("linux-only source")
        import subprocess, sys
        child = subprocess.Popen([sys.executable, "-c", "import time;time.sleep(5)"])
        try:
            self.assertNotEqual(
                default_process_starttime(os.getpid()),
                default_process_starttime(child.pid),
            )
        finally:
            child.kill()
            child.wait()

    def test_real_start_time_of_an_absent_pid_is_none(self):
        self.assertIsNone(default_process_starttime(1 << 30))

    def test_real_group_probe_sees_our_own_group_and_not_a_bogus_one(self):
        self.assertIs(True, default_group_is_live(os.getpgrp()))
        self.assertIs(False, default_group_is_live(1 << 30))

    def test_default_seams_bind_and_reject_a_live_real_group(self):
        """End to end through the real defaults: no stubbed liveness at all."""
        held = WorkspaceLease.acquire(
            self.project, route="same-project-headless", lease_dir=self.leases,
            ttl_seconds=0.001,
        )
        try:
            held.bind_holder(pid=os.getpid(), pgid=os.getpgrp())
            time.sleep(0.01)
            with self.assertRaises(EvidenceError) as ctx:
                WorkspaceLease.acquire(
                    self.project, route="isolated-headless", lease_dir=self.leases
                )
            self.assertEqual("E_UNITY_LEASE_HELD", ctx.exception.code)
        finally:
            held.release()


class RenewReleaseTests(_LeaseCase):
    def test_renew_moves_expiry_and_renewed_but_not_acquired(self):
        held = self.acquire(ttl=60.0)
        self.addCleanup(held.release)
        before = read_lease(held.path)
        self.clock.advance(30.0)
        held.renew()
        after = read_lease(held.path)
        self.assertEqual(before.acquired_utc, after.acquired_utc)
        self.assertNotEqual(before.renewed_utc, after.renewed_utc)
        self.assertNotEqual(before.expiry_utc, after.expiry_utc)
        self.assertEqual(before.owner, after.owner)

    def test_renew_after_release_reports_the_lease_was_lost(self):
        held = self.acquire()
        held.release()
        with self.assertRaises(EvidenceError) as ctx:
            held.renew()
        self.assertEqual("E_UNITY_LEASE_LOST", ctx.exception.code)

    def test_renew_of_someone_elses_lease_is_refused_and_does_not_overwrite(self):
        held = self.acquire(owner="mine")
        payload = json.loads(held.path.read_text(encoding="utf-8"))
        payload["owner"] = "theirs"
        held.path.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaises(EvidenceError) as ctx:
            held.renew()
        self.assertEqual("E_UNITY_LEASE_LOST", ctx.exception.code)
        self.assertEqual("theirs", read_lease(held.path).owner)

    def test_release_does_not_delete_a_lease_we_no_longer_own(self):
        held = self.acquire(owner="mine")
        payload = json.loads(held.path.read_text(encoding="utf-8"))
        payload["owner"] = "theirs"
        held.path.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaises(EvidenceError) as ctx:
            held.release()
        self.assertEqual("E_UNITY_LEASE_LOST", ctx.exception.code)
        self.assertTrue(held.path.exists())

    def test_release_removes_our_own_lease(self):
        held = self.acquire()
        self.assertTrue(held.path.exists())
        held.release()
        self.assertFalse(held.path.exists())

    def test_release_is_idempotent(self):
        held = self.acquire()
        held.release()
        held.release()
        self.assertFalse(held.path.exists())

    def test_release_of_a_malformed_file_refuses_rather_than_deleting_it(self):
        held = self.acquire()
        held.path.write_text("{corrupted", encoding="utf-8")
        with self.assertRaises(EvidenceError) as ctx:
            held.release()
        self.assertEqual("E_UNITY_LEASE_MALFORMED", ctx.exception.code)
        self.assertTrue(held.path.exists())

    def test_context_manager_releases_when_the_body_raises(self):
        path_holder: list[Path] = []
        with self.assertRaises(RuntimeError):
            with self.acquire() as held:
                path_holder.append(held.path)
                self.assertTrue(held.path.exists())
                raise RuntimeError("boom")
        self.assertFalse(path_holder[0].exists())
        # And the slot is genuinely free afterwards.
        again = self.acquire()
        self.addCleanup(again.release)

    def test_context_manager_releases_on_a_clean_exit(self):
        with self.acquire() as held:
            path = held.path
        self.assertFalse(path.exists())

    def test_is_held_reflects_reality_not_local_state(self):
        held = self.acquire(owner="mine")
        self.assertTrue(held.is_held())
        held.path.unlink()
        self.assertFalse(held.is_held())


class DefaultsTests(_LeaseCase):
    def test_default_seams_produce_a_usable_real_lease(self):
        """No injected clock/uuid/pid seams: the real defaults must work."""
        held = WorkspaceLease.acquire(
            self.project, route="isolated-headless", lease_dir=self.leases
        )
        try:
            record = read_lease(held.path)
            self.assertEqual(os.getpid(), record.pid)
            self.assertEqual(36, len(record.owner))  # a real uuid4 string
            self.assertLess(record.acquired_utc, record.expiry_utc)
            held.renew()
        finally:
            held.release()
        self.assertFalse(held.path.exists())

    def test_default_ttl_is_positive_and_exposed(self):
        self.assertGreater(lease_module.DEFAULT_TTL_SECONDS, 0)

    def test_a_non_positive_ttl_is_refused(self):
        for bad in (0.0, -5.0):
            with self.subTest(ttl=bad):
                with self.assertRaises(EvidenceError) as ctx:
                    self.acquire(ttl=bad)
                self.assertEqual("E_UNITY_LEASE_ARG", ctx.exception.code)


if __name__ == "__main__":
    unittest.main()
