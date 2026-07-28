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
from .process import default_pid_is_live

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
        }


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
    return LeaseRecord(
        schema=LEASE_SCHEMA,
        owner=payload["owner"],
        path_hash=payload["path_hash"],
        route=payload["route"],
        pid=payload["pid"],
        acquired_utc=payload["acquired_utc"],
        renewed_utc=payload["renewed_utc"],
        expiry_utc=payload["expiry_utc"],
    )


class WorkspaceLease:
    """An acquired lease on one physical workspace. Release it in `finally`."""

    def __init__(self, *, path: Path, owner: str, record: LeaseRecord,
                 ttl_seconds: float, clock: Callable[[], float]) -> None:
        self.path = path
        self.owner = owner
        self._record = record
        self._ttl = ttl_seconds
        self._clock = clock
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
        )

        if not _create_exclusive(target, record):
            # Someone holds this slot. Decide whether it is reclaimable; every
            # answer other than "provably dead and expired" raises.
            _refuse_or_clear(target, path_hash, now, pid_is_live)
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
    pid_is_live: Callable[[int], "bool | None"],
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

    liveness = pid_is_live(current.pid)
    if liveness is None:
        raise EvidenceError(
            "E_UNITY_LEASE_UNKNOWN",
            f"lease {target.name} expired at {current.expiry_utc}, but whether "
            f"pid {current.pid} is still running could not be determined; "
            "refusing to reclaim a workspace that may still be open",
        )
    if liveness:
        raise EvidenceError(
            "E_UNITY_LEASE_HELD",
            f"lease {target.name} expired at {current.expiry_utc}, but its owning "
            f"pid {current.pid} is still running -- an expired timestamp is not "
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
