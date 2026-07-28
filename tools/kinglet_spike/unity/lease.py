"""lease.py -- Per-workspace lease keyed by canonical physical path.

What the lease is for
---------------------
Plan 00U's four routes are not four different things to a Unity project: they
are four ways of reaching one. `live-editor-mcp` and `same-project-headless`
address the SAME physical project; `isolated-headless` addresses a physical
copy of it. Unity permits exactly one Editor per project directory, so the unit
of exclusion is the physical directory -- not the route, and not the path
string the caller happened to type.

That is why identity here is the SHA-256 of the resolved physical path.
`/x/proj`, `/x/./proj`, `/x/link-to-proj` and `/x/proj/../proj` are one
workspace and conflict; `/x/proj` and `/x/proj2` are two and do not. Prefix or
substring comparison would fuse the last pair -- the same trap ownership.py
documents for `-projectPath` matching.

Where the lease lives, and why not in the project
-------------------------------------------------
Below the RAW RUN directory, never inside the Unity project. Three reasons, all
concrete: a file inside `Assets/` is imported by Unity and becomes a project
asset (and wants a `.meta`); a file elsewhere in the project pollutes the very
tree `isolated-headless` copies, so the copy would inherit a foreign lease; and
a crashed run's leftover lease must be removable without touching a project a
person may be working in. The lease file's NAME is the hash and its CONTENTS
carry no path at all, so nothing under `.kinglet/local/` ever records an
absolute machine path.

The direction of every ambiguous case
-------------------------------------
This module's asymmetry is the opposite of process.py's, and it is stated here
so no branch below has to be reasoned about twice. Failing to acquire a lease
we could have taken costs one refused run: visible, recoverable, loud. Wrongly
taking one from a live owner lets two Unity processes open a single project,
which is the corruption this plan exists to prevent, and it is silent. So every
unresolved state refuses:

* a lease file that will not parse, or whose fields are missing or of the wrong
  type, or whose `path_hash` is not ours -> `E_UNITY_LEASE_MALFORMED`. It is
  never overwritten and never deleted: a corrupt file may still belong to a
  live run, and the recovery action (delete it, under `.kinglet/local/`) should
  be a human's.
* an unexpired lease -> `E_UNITY_LEASE_HELD`, regardless of its pid's state.
  A live owner may simply not have renewed yet.
* an EXPIRED lease whose owning pid is still alive, or whose liveness cannot be
  determined -> `E_UNITY_LEASE_HELD` / `E_UNITY_LEASE_UNKNOWN`. Expiry is a
  hint, not proof of death; a stalled run holding a real Unity process is
  exactly the case that must not be stolen. Replacement requires BOTH an
  elapsed expiry AND a pid proven not to exist.

Task 3's central defect was that its unresolvable cases fell through to the
permissive answer by construction. `test_no_unresolved_case_falls_through_to
_acquire` drives every such state through the real `acquire` and requires a
refusal from each.
"""
from __future__ import annotations

import hashlib
import json
import os
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

from ..model import EvidenceError
from .process import default_group_table, default_pid_is_live

LEASE_SCHEMA: str = "kinglet.unity-probe.lease/v1"

# A run renews while it works, so this only has to outlive the gap between two
# renewals plus a generous stall. It is deliberately NOT derived from the route
# contract's phase budgets: a lease is not a timeout, and binding it to
# routes-v1.json would make an unrelated contract edit silently change when a
# dead run's lease becomes reclaimable.
DEFAULT_TTL_SECONDS: float = 300.0

_REQUIRED_FIELDS: tuple[tuple[str, type], ...] = (
    ("owner", str),
    ("path_hash", str),
    ("route", str),
    ("pid", int),
    ("acquired_utc", str),
    ("renewed_utc", str),
    ("expiry_utc", str),
)

# Present on every record, but nullable: at `acquire()` time the Unity process
# does not exist yet, so the lease can only name the controller. `bind_holder`
# repoints it once there is something better to name. The KEYS are still
# required -- a record missing them is malformed -- so a lease written by an
# older or foreign writer can never be mistaken for an unbound one.
_NULLABLE_FIELDS: tuple[tuple[str, type], ...] = (
    ("pgid", int),
    ("holder_starttime", str),
)


@dataclass(frozen=True)
class LeaseRecord:
    schema: str
    owner: str
    path_hash: str
    route: str
    pid: int
    acquired_utc: str
    renewed_utc: str
    expiry_utc: str
    pgid: int | None = None
    holder_starttime: str | None = None

    def to_dict(self) -> dict:
        return {
            "schema": self.schema,
            "owner": self.owner,
            "path_hash": self.path_hash,
            "route": self.route,
            "pid": self.pid,
            "acquired_utc": self.acquired_utc,
            "renewed_utc": self.renewed_utc,
            "expiry_utc": self.expiry_utc,
            "pgid": self.pgid,
            "holder_starttime": self.holder_starttime,
        }


def default_process_starttime(pid: int) -> str | None:
    """A pid's start time, as an opaque string, or None where unavailable.

    This is what disambiguates a pid from a RECYCLED pid. Field 22 of Linux's
    /proc/<pid>/stat is the process's start time in clock ticks since boot; two
    processes that share a pid number cannot share it. macOS and Windows return
    None here for now, where the conservative branch (refuse to reclaim)
    applies instead -- see `_holder_liveness`.
    """
    try:
        raw = Path(f"/proc/{pid}/stat").read_bytes()
    except OSError:
        return None
    end = raw.rfind(b")")
    if end == -1:
        return None
    fields = raw[end + 1:].split()
    # After comm: state(3) ... starttime(22) -> index 19 here.
    if len(fields) < 20:
        return None
    return fields[19].decode("ascii", errors="replace")


def default_group_is_live(pgid: int) -> "bool | None":
    """Does ANY process still belong to process group `pgid`?

    The lease's real question is "does something still hold this workspace
    open?", and after a controller crash the answer lives in the contained
    GROUP, not in the controller's pid -- `start_new_session` puts Unity in its
    own session precisely so it survives its launcher. None means the process
    table could not be read, which is ambiguity, never "nothing there".
    """
    try:
        table = default_group_table()
    except EvidenceError:
        return None
    return any(row.pgid == pgid for row in table)


def _holder_liveness(
    record: "LeaseRecord",
    *,
    pid_is_live: Callable[[int], "bool | None"],
    group_is_live: Callable[[int], "bool | None"],
    starttime_reader: Callable[[int], "str | None"],
) -> "bool | None":
    """Is the thing that actually holds this workspace still running?

    Round 1 review found this pointed at the wrong process. The lease recorded
    the CONTROLLER's pid, but `ManagedProcess` launches Unity into its own
    session, so killing the controller leaves the whole Unity group alive
    (measured: "child alive after ManagedProcess dropped without cancel:
    True"). At TTL the lease then read as reclaimable while a live Unity still
    owned the project -- the exact double-open this module exists to prevent.

    So once `bind_holder` has recorded the contained pgid, that group is the
    authority: a live member means the workspace is held, whatever became of
    the controller. Only an unbound lease -- one whose Unity process never
    started -- falls back to the pid.

    Pid recycling is disambiguated on the pid path where the platform offers a
    start time: a pid that exists but was NOT started when we recorded it is a
    different process, so the true holder is dead and the lease is reclaimable.
    Where no start time is available the answer stays True (refuse), which is
    the safe direction and is disclosed in the task report as a wedge.
    """
    if record.pgid is not None:
        return group_is_live(record.pgid)

    live = pid_is_live(record.pid)
    if live is not True:
        return live
    if record.holder_starttime is None:
        return True  # nothing to compare against -- cannot rule out the holder
    current = starttime_reader(record.pid)
    if current is None:
        return True  # could not read it now -- same conservative answer
    return current == record.holder_starttime


def _utc(epoch_seconds: float) -> str:
    """RFC3339 UTC with a literal Z. Sortable as a plain string."""
    return datetime.fromtimestamp(epoch_seconds, tz=timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )


def physical_path_hash(project) -> str:
    """SHA-256 of the normalized PHYSICAL path of `project`.

    `os.path.realpath` resolves symlinks and `..`; `os.path.normcase` folds the
    case and separator conventions that make two spellings of one Windows path
    look different (it is the identity on POSIX). The path must exist: hashing
    a path that is not there would mint an identity for a workspace nobody can
    prove is the one being leased, and `realpath` cannot resolve symlinks it
    cannot follow, so two aliases of a not-yet-created directory could hash
    differently and both "succeed".
    """
    raw = os.fspath(project)
    if not os.path.isdir(raw):
        raise EvidenceError(
            "E_UNITY_LEASE_PATH",
            f"cannot lease {raw!r}: it is not an existing directory, so its "
            "physical identity cannot be resolved",
        )
    canonical = os.path.normcase(os.path.realpath(raw))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def lease_path_for(project, lease_dir) -> Path:
    """The lease file for `project`, below the run directory."""
    return Path(lease_dir) / f"{physical_path_hash(project)}.lease.json"


def read_lease(path) -> LeaseRecord:
    """Strict parse. Anything unexpected is MALFORMED, never a default.

    A tolerant reader here would be the permissive fallthrough this module is
    built to avoid: a lease missing its `pid` would read as pid 0, which is
    "alive" to no one and "dead" to a careless liveness check.
    """
    path = Path(path)
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise
    except OSError as error:
        raise EvidenceError(
            "E_UNITY_LEASE_MALFORMED", f"cannot read lease {path.name}: {error}"
        ) from error

    try:
        payload = json.loads(text)
    except ValueError as error:
        raise EvidenceError(
            "E_UNITY_LEASE_MALFORMED", f"lease {path.name} is not valid JSON: {error}"
        ) from error

    if not isinstance(payload, dict):
        raise EvidenceError(
            "E_UNITY_LEASE_MALFORMED",
            f"lease {path.name} is a {type(payload).__name__}, not an object",
        )
    if payload.get("schema") != LEASE_SCHEMA:
        raise EvidenceError(
            "E_UNITY_LEASE_MALFORMED",
            f"lease {path.name} declares schema {payload.get('schema')!r}, "
            f"expected {LEASE_SCHEMA!r}",
        )
    for field, kind in _REQUIRED_FIELDS:
        if field not in payload:
            raise EvidenceError(
                "E_UNITY_LEASE_MALFORMED", f"lease {path.name} has no {field!r} field"
            )
        value = payload[field]
        # bool is an int subclass; a JSON true in `pid` is not a pid.
        if not isinstance(value, kind) or isinstance(value, bool) != (kind is bool):
            raise EvidenceError(
                "E_UNITY_LEASE_MALFORMED",
                f"lease {path.name} field {field!r} is "
                f"{type(value).__name__}, expected {kind.__name__}",
            )
    for field, kind in _NULLABLE_FIELDS:
        if field not in payload:
            raise EvidenceError(
                "E_UNITY_LEASE_MALFORMED", f"lease {path.name} has no {field!r} field"
            )
        value = payload[field]
        if value is None:
            continue
        if not isinstance(value, kind) or isinstance(value, bool):
            raise EvidenceError(
                "E_UNITY_LEASE_MALFORMED",
                f"lease {path.name} field {field!r} is "
                f"{type(value).__name__}, expected {kind.__name__} or null",
            )
    return LeaseRecord(
        schema=LEASE_SCHEMA,
        owner=payload["owner"],
        path_hash=payload["path_hash"],
        route=payload["route"],
        pid=payload["pid"],
        acquired_utc=payload["acquired_utc"],
        renewed_utc=payload["renewed_utc"],
        expiry_utc=payload["expiry_utc"],
        pgid=payload["pgid"],
        holder_starttime=payload["holder_starttime"],
    )


class WorkspaceLease:
    """An acquired lease on one physical workspace. Release it in `finally`."""

    def __init__(self, *, path: Path, owner: str, record: LeaseRecord,
                 ttl_seconds: float, clock: Callable[[], float],
                 starttime_reader: Callable[[int], "str | None"] = None) -> None:
        self.path = path
        self.owner = owner
        self._record = record
        self._ttl = ttl_seconds
        self._clock = clock
        self._starttime_reader = starttime_reader or default_process_starttime
        self._released = False

    # -- acquisition ------------------------------------------------------

    @classmethod
    def acquire(
        cls,
        project,
        *,
        route: str,
        lease_dir,
        ttl_seconds: float = DEFAULT_TTL_SECONDS,
        pid: int | None = None,
        clock: Callable[[], float] = None,
        uuid_factory: Callable[[], str] = None,
        pid_is_live: Callable[[int], "bool | None"] = default_pid_is_live,
        group_is_live: Callable[[int], "bool | None"] = default_group_is_live,
        starttime_reader: Callable[[int], "str | None"] = default_process_starttime,
    ) -> "WorkspaceLease":
        import time as _time

        clock = clock or _time.time
        uuid_factory = uuid_factory or (lambda: str(uuid.uuid4()))
        pid = os.getpid() if pid is None else pid

        if ttl_seconds <= 0:
            raise EvidenceError(
                "E_UNITY_LEASE_ARG",
                f"ttl_seconds must be positive, got {ttl_seconds!r}: a lease that "
                "is born expired is indistinguishable from no lease at all",
            )

        path_hash = physical_path_hash(project)
        target = Path(lease_dir) / f"{path_hash}.lease.json"
        target.parent.mkdir(parents=True, exist_ok=True)

        now = clock()
        record = LeaseRecord(
            schema=LEASE_SCHEMA,
            owner=uuid_factory(),
            path_hash=path_hash,
            route=route,
            pid=pid,
            acquired_utc=_utc(now),
            renewed_utc=_utc(now),
            expiry_utc=_utc(now + ttl_seconds),
            # Unity does not exist yet, so the only holder we can name is this
            # controller. `bind_holder` repoints it the moment there is a
            # contained group to name instead.
            pgid=None,
            holder_starttime=starttime_reader(pid),
        )

        if not _create_exclusive(target, record):
            # Someone holds this slot. Decide whether it is reclaimable; every
            # answer other than "provably dead and expired" raises.
            _refuse_or_clear(
                target, path_hash, now,
                pid_is_live=pid_is_live,
                group_is_live=group_is_live,
                starttime_reader=starttime_reader,
            )
            if not _create_exclusive(target, record):
                # Another acquirer won the race between our clear and our
                # create. Refusing is correct: exactly one of us may hold it,
                # and the O_EXCL create is the arbiter, not our own bookkeeping.
                raise EvidenceError(
                    "E_UNITY_LEASE_HELD",
                    f"lease {target.name} was taken by another acquirer while "
                    "this one was reclaiming an expired lease",
                )

        return cls(
            path=target, owner=record.owner, record=record,
            ttl_seconds=ttl_seconds, clock=clock,
            starttime_reader=starttime_reader,
        )

    # -- maintenance ------------------------------------------------------

    def is_held(self) -> bool:
        """True iff the lease file on disk still names us as owner.

        Reads disk rather than local state: the point of a lease is that
        someone else may have reclaimed it.
        """
        try:
            return read_lease(self.path).owner == self.owner
        except FileNotFoundError:
            return False
        except EvidenceError:
            return False

    def bind_holder(self, *, pid: int, pgid: int) -> LeaseRecord:
        """Repoint this lease at the process that actually holds the workspace.

        Call this as soon as `ManagedProcess.start` returns, with that
        object's `pid` and `pgid`. Until it is called, the lease names the
        controller, and a controller crash would make the lease reclaimable at
        TTL while a live Unity still had the project open -- because
        `start_new_session` deliberately puts Unity in its own session, so it
        outlives whatever launched it.

        The pgid is the durable handle: it identifies the contained group even
        after the leader exits and its children are reparented to init, which
        is precisely the state Unity leaves behind. It is also, as a side
        effect, the on-disk handle a later run needs in order to clean up a
        crashed run's leaked group -- without it, a reclaimer inherits the
        workspace with no way to name what is still running in it.
        """
        current = self._read_own_lease()
        bound = LeaseRecord(
            schema=LEASE_SCHEMA,
            owner=current.owner,
            path_hash=current.path_hash,
            route=current.route,
            pid=pid,
            acquired_utc=current.acquired_utc,
            renewed_utc=current.renewed_utc,
            expiry_utc=current.expiry_utc,
            pgid=pgid,
            holder_starttime=self._starttime_reader(pid),
        )
        _write_atomic(self.path, bound)
        self._record = bound
        return bound

    def renew(self, ttl_seconds: float | None = None) -> LeaseRecord:
        """Extend OUR lease. Raises E_UNITY_LEASE_LOST if it is no longer ours."""
        current = self._read_own_lease()
        ttl = self._ttl if ttl_seconds is None else ttl_seconds
        if ttl <= 0:
            raise EvidenceError(
                "E_UNITY_LEASE_ARG", f"ttl_seconds must be positive, got {ttl!r}"
            )
        now = self._clock()
        renewed = LeaseRecord(
            schema=LEASE_SCHEMA,
            owner=current.owner,
            path_hash=current.path_hash,
            route=current.route,
            pid=current.pid,
            acquired_utc=current.acquired_utc,  # never moves
            renewed_utc=_utc(now),
            expiry_utc=_utc(now + ttl),
            pgid=current.pgid,
            holder_starttime=current.holder_starttime,
        )
        _write_atomic(self.path, renewed)
        self._record = renewed
        self._ttl = ttl
        return renewed

    def release(self) -> None:
        """Delete OUR lease. Safe to call twice; never deletes someone else's.

        A crashed-and-restarted run must not be able to release a lease that a
        later run legitimately reclaimed, so ownership is re-checked against
        disk here rather than trusted from memory.
        """
        try:
            current = read_lease(self.path)
        except FileNotFoundError:
            self._released = True
            return
        if current.owner != self.owner:
            raise EvidenceError(
                "E_UNITY_LEASE_LOST",
                f"lease {self.path.name} is now owned by {current.owner}, "
                f"not {self.owner}; refusing to release another owner's lease",
            )
        try:
            self.path.unlink()
        except FileNotFoundError:
            pass
        self._released = True

    # -- context manager --------------------------------------------------

    def __enter__(self) -> "WorkspaceLease":
        return self

    def __exit__(self, exc_type, exc, tb) -> bool:
        self.release()
        return False

    def _read_own_lease(self) -> LeaseRecord:
        try:
            current = read_lease(self.path)
        except FileNotFoundError as error:
            raise EvidenceError(
                "E_UNITY_LEASE_LOST",
                f"lease {self.path.name} no longer exists; it was released or "
                "reclaimed by another run",
            ) from error
        if current.owner != self.owner:
            raise EvidenceError(
                "E_UNITY_LEASE_LOST",
                f"lease {self.path.name} is owned by {current.owner}, not "
                f"{self.owner}",
            )
        return current


# ---------------------------------------------------------------------------
# File-level primitives
# ---------------------------------------------------------------------------

def _serialize(record: LeaseRecord) -> bytes:
    return (json.dumps(record.to_dict(), indent=2, sort_keys=True) + "\n").encode("utf-8")


def _create_exclusive(target: Path, record: LeaseRecord) -> bool:
    """O_CREAT|O_EXCL create -- the only mutual exclusion this module trusts.

    Returns False (never raises) when the file already exists, so the caller
    can inspect the competitor. Everything else is a real error.
    """
    try:
        fd = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
    except FileExistsError:
        return False
    except OSError as error:
        raise EvidenceError(
            "E_UNITY_LEASE_PATH", f"cannot create lease {target}: {error}"
        ) from error
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(_serialize(record))
            handle.flush()
            os.fsync(handle.fileno())
    except BaseException:
        try:
            target.unlink()
        except OSError:
            pass
        raise
    return True


def _write_atomic(target: Path, record: LeaseRecord) -> None:
    temp = target.with_name(target.name + ".partial")
    with open(temp, "wb") as handle:
        handle.write(_serialize(record))
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp, target)


def _refuse_or_clear(
    target: Path,
    path_hash: str,
    now: float,
    *,
    pid_is_live: Callable[[int], "bool | None"],
    group_is_live: Callable[[int], "bool | None"],
    starttime_reader: Callable[[int], "str | None"],
) -> None:
    """Either raise, or remove a lease PROVEN to be abandoned. Never anything else.

    The residual race: between the `unlink` here and the caller's O_EXCL
    create, another acquirer can win. That is handled, not ignored -- the
    caller's second create failing means it lost, and it refuses. The O_EXCL
    create is the mutual exclusion; this function only ever removes an obstacle
    it has proven is rubble.
    """
    try:
        current = read_lease(target)
    except FileNotFoundError:
        return  # vanished between our create and our read; caller retries

    if current.path_hash != path_hash:
        raise EvidenceError(
            "E_UNITY_LEASE_MALFORMED",
            f"lease {target.name} records path_hash {current.path_hash[:12]}..., "
            f"but this slot belongs to {path_hash[:12]}...; refusing to touch a "
            "lease whose identity does not match its own file name",
        )

    expiry = _parse_utc(current.expiry_utc, target.name)
    if expiry > now:
        raise EvidenceError(
            "E_UNITY_LEASE_HELD",
            f"workspace is leased by {current.owner} (route {current.route}, "
            f"pid {current.pid}) until {current.expiry_utc}",
        )

    liveness = _holder_liveness(
        current,
        pid_is_live=pid_is_live,
        group_is_live=group_is_live,
        starttime_reader=starttime_reader,
    )
    holder = (
        f"process group {current.pgid}" if current.pgid is not None
        else f"pid {current.pid}"
    )
    if liveness is None:
        raise EvidenceError(
            "E_UNITY_LEASE_UNKNOWN",
            f"lease {target.name} expired at {current.expiry_utc}, but whether "
            f"{holder} is still running could not be determined; "
            "refusing to reclaim a workspace that may still be open",
        )
    if liveness:
        raise EvidenceError(
            "E_UNITY_LEASE_HELD",
            f"lease {target.name} expired at {current.expiry_utc}, but its owning "
            f"{holder} is still running -- an expired timestamp is not "
            "proof of death",
        )

    try:
        target.unlink()
    except FileNotFoundError:
        pass


def _parse_utc(value: str, name: str) -> float:
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as error:
        raise EvidenceError(
            "E_UNITY_LEASE_MALFORMED",
            f"lease {name} timestamp {value!r} is not RFC3339 UTC: {error}",
        ) from error
    return parsed.replace(tzinfo=timezone.utc).timestamp()
