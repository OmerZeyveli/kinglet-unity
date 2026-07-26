"""kinglet_host_probe.py — bundled-Python Host Probe candidate.

Candidate ID:      python-bundled
Target version:    3.14.6-pyinstaller6.21.0   (packaged identity; see report for unpackaged notes)

Entry point:
    kinglet_host_probe run --contract <path> --workspace <dir> --result <path>

Supporting subcommands:
    kinglet_host_probe child --sentinel <abs-file> --lifetime-ms <n>

Exposed API (imported by test_candidate.py):
    atomic_replace(target: Path, data: bytes) -> None
    verify_ed25519(message_hex: str, public_hex: str, signature_hex: str) -> bool
    Lease
    spawn_tree_and_cancel(exe: Path, workspace: Path, lifetime_ms: int, cancel_ms: int) -> list[int]
    run_contract(contract_path: Path, workspace: Path) -> dict
    main() -> None
"""
from __future__ import annotations

import hashlib
import json
import os
import signal
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# sys.path bootstrap — allow unpackaged execution from any cwd.
# When running as a PyInstaller one-file bundle, sys._MEIPASS is set and the
# tools package is embedded; no path surgery needed.
# ---------------------------------------------------------------------------
if not hasattr(sys, "_MEIPASS"):
    # Script lives at <root>/spikes/platform/runtime/python/kinglet_host_probe.py
    _REPO_ROOT = Path(__file__).resolve().parents[4]
    if str(_REPO_ROOT) not in sys.path:
        sys.path.insert(0, str(_REPO_ROOT))

# ---------------------------------------------------------------------------
# External imports (after sys.path fixup)
# ---------------------------------------------------------------------------
from cryptography.exceptions import InvalidSignature  # noqa: E402
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey  # noqa: E402

from tools.kinglet_build.errors import BuildError  # noqa: E402
from tools.kinglet_build.loader import load_graph  # noqa: E402
from tools.kinglet_spike.runtime_contract import REQUIRED_ASSERTIONS  # noqa: E402

# ---------------------------------------------------------------------------
# Candidate identity
# ---------------------------------------------------------------------------
CANDIDATE_ID = "python-bundled"
CANDIDATE_VERSION = "3.14.6-pyinstaller6.21.0"

# ---------------------------------------------------------------------------
# Crypto
# ---------------------------------------------------------------------------


def verify_ed25519(message_hex: str, public_hex: str, signature_hex: str) -> bool:
    """Return True iff signature is a valid Ed25519 signature over message."""
    try:
        Ed25519PublicKey.from_public_bytes(bytes.fromhex(public_hex)).verify(
            bytes.fromhex(signature_hex), bytes.fromhex(message_hex)
        )
        return True
    except (ValueError, InvalidSignature):
        return False


# ---------------------------------------------------------------------------
# Atomic replace
# ---------------------------------------------------------------------------


def atomic_replace(target: Path, data: bytes) -> None:
    """Write *data* to *target* atomically (write → fsync → os.replace).

    A unique sibling temp file is created with O_CREAT|O_EXCL so two concurrent
    callers cannot step on each other.  The containing directory is fsynced
    after the rename where the platform supports it.
    """
    target = Path(target)
    parent = target.parent
    parent.mkdir(parents=True, exist_ok=True)

    # Unique sibling — O_CREAT|O_EXCL prevents overwriting another temp file.
    tmp_suffix = f".{uuid.uuid4().hex}.tmp"
    tmp_path = target.with_name(target.name + tmp_suffix)

    fd = os.open(
        str(tmp_path),
        os.O_WRONLY | os.O_CREAT | os.O_EXCL,
        0o600,
    )
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
    except BaseException:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise

    os.replace(tmp_path, target)

    # Fsync the directory so the rename is durable (best-effort; not all FS support it).
    try:
        dir_fd = os.open(str(parent), os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Lease
# ---------------------------------------------------------------------------


class Lease:
    """Exclusive advisory lease backed by a JSON file.

    The file stores {"owner": <uuid-str>, "expires_utc": <iso-str>}.
    Acquire: O_CREAT|O_EXCL exclusive create.
    Renew:   only by the owner recorded in the file (malformed → treat as busy).
    Release: only removes the file when it still belongs to this instance's owner.
    """

    def __init__(self, path: Path, ttl_ms: int) -> None:
        self._path = Path(path)
        self._ttl_ms = ttl_ms
        self._owner: str | None = None

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _now_utc(self) -> datetime:
        return datetime.now(tz=timezone.utc)

    def _expiry_utc(self) -> datetime:
        return datetime.fromtimestamp(
            time.time() + self._ttl_ms / 1000.0,
            tz=timezone.utc,
        )

    def _encode(self) -> bytes:
        payload = {
            "owner": self._owner,
            "expires_utc": self._expiry_utc().isoformat(),
        }
        return json.dumps(payload, separators=(",", ":")).encode("utf-8")

    def _read_lease(self) -> dict[str, Any] | None:
        """Read lease file; return None if absent, {} if malformed."""
        try:
            raw = self._path.read_text(encoding="utf-8")
            data = json.loads(raw)
            if isinstance(data, dict) and "owner" in data and "expires_utc" in data:
                return data
            return {}  # malformed → treat as busy
        except FileNotFoundError:
            return None
        except (json.JSONDecodeError, UnicodeDecodeError, OSError):
            return {}  # malformed → treat as busy

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    @property
    def owner(self) -> str | None:
        return self._owner

    def acquire(self) -> bool:
        """Try to acquire the lease.  Returns True on success, False if busy."""
        self._path.parent.mkdir(parents=True, exist_ok=True)
        owner = str(uuid.uuid4())
        expiry = self._expiry_utc().isoformat()
        payload = json.dumps(
            {"owner": owner, "expires_utc": expiry}, separators=(",", ":")
        ).encode("utf-8")
        try:
            fd = os.open(
                str(self._path),
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                0o600,
            )
        except FileExistsError:
            # Check if the existing lease has expired
            data = self._read_lease()
            if data is None:
                # File disappeared between our attempt and now — retry once
                return self.acquire()
            if not data:
                # Malformed → busy
                return False
            try:
                exp = datetime.fromisoformat(data["expires_utc"])
                if self._now_utc() > exp:
                    # Expired — try to steal it
                    try:
                        self._path.unlink()
                    except OSError:
                        pass
                    return self.acquire()
            except (KeyError, ValueError):
                return False
            return False

        with os.fdopen(fd, "wb") as fh:
            fh.write(payload)
            fh.flush()
            os.fsync(fh.fileno())
        self._owner = owner
        return True

    def renew(self) -> bool:
        """Renew the lease.  Only succeeds if this instance currently owns it."""
        if self._owner is None:
            return False
        data = self._read_lease()
        if not data or data.get("owner") != self._owner:
            return False
        atomic_replace(self._path, self._encode())
        return True

    def release(self) -> bool:
        """Release the lease.  Only removes the file when we own it."""
        if self._owner is None:
            return False
        data = self._read_lease()
        if data and data.get("owner") == self._owner:
            try:
                self._path.unlink()
            except OSError:
                pass
            self._owner = None
            return True
        self._owner = None
        return False

    def is_held_by_me(self) -> bool:
        """True when the lease file exists and records our owner UUID."""
        if self._owner is None:
            return False
        data = self._read_lease()
        return bool(data and data.get("owner") == self._owner)

    def is_active(self) -> bool:
        """True when a lease file exists (regardless of owner)."""
        return self._path.exists()


# ---------------------------------------------------------------------------
# Process tree helpers
# ---------------------------------------------------------------------------

_EXE = Path(__file__).resolve()


def _is_pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        # Process exists but we can't signal it — still alive
        return True


def spawn_tree_and_cancel(
    exe: Path,
    workspace: Path,
    lifetime_ms: int,
    cancel_ms: int,
) -> tuple[list[int], bool]:
    """Spawn a parent child process, let it spawn a grandchild, then kill the group.

    Returns a tuple of (recorded PIDs, killed): the parent + grandchild PIDs
    recorded in the sentinel file (all must be gone by the time this returns),
    and killed=True iff killpg cancelled a live process group.

    The parent process is this executable with 'child' subcommand, started in a
    new session (start_new_session=True) so its pgid == proc.pid.  After
    cancel_ms the whole process group is killed and we verify every recorded PID
    is gone.
    """
    workspace = Path(workspace)
    sentinel = workspace / "tree-sentinel.json"
    sentinel.parent.mkdir(parents=True, exist_ok=True)
    if sentinel.exists():
        sentinel.unlink()

    cmd = [
        sys.executable if not hasattr(sys, "_MEIPASS") else str(exe),
        str(exe) if not hasattr(sys, "_MEIPASS") else "",
        "child",
        "--sentinel", str(sentinel),
        "--lifetime-ms", str(lifetime_ms),
    ]
    # Remove empty args when bundled
    cmd = [c for c in cmd if c]

    proc = subprocess.Popen(
        cmd,
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    pgid = proc.pid

    # Wait for sentinel to appear (the child writes PIDs once grandchild is up)
    deadline = time.monotonic() + cancel_ms / 1000.0
    pids: list[int] = []
    while time.monotonic() < deadline:
        if sentinel.exists():
            try:
                pids = json.loads(sentinel.read_text(encoding="utf-8"))
                if isinstance(pids, list) and len(pids) >= 2:
                    break
            except (json.JSONDecodeError, OSError):
                pass
        time.sleep(0.05)

    # Cancel: kill the process group. Capture whether the kill actually
    # cancelled a live group so process.cancel can assert it (parity with the
    # Go/Rust/.NET candidates; independent of the liveness poll below).
    try:
        os.killpg(pgid, signal.SIGKILL)
        killed = True
    except ProcessLookupError:
        killed = False

    # Wait for the main child to reap
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass

    # Give OS a moment to reap all
    time.sleep(0.1)

    # Verify all recorded PIDs are dead
    deadline2 = time.monotonic() + 5.0
    while time.monotonic() < deadline2:
        if all(not _is_pid_alive(p) for p in pids):
            break
        time.sleep(0.1)

    return pids, killed


def _run_child(sentinel_path: Path, lifetime_ms: int) -> None:
    """Child subcommand: spawn one grandchild, write PIDs, then sleep.

    The grandchild is also this executable with 'child', pointing at the same
    sentinel but with a very long lifetime (it'll be killed by the parent).
    """
    sentinel_path.parent.mkdir(parents=True, exist_ok=True)

    # Spawn the grandchild
    grandchild_sentinel = sentinel_path.parent / "gc-sentinel.json"
    gc_cmd = [
        sys.executable if not hasattr(sys, "_MEIPASS") else str(_EXE),
        str(_EXE) if not hasattr(sys, "_MEIPASS") else "",
        "child",
        "--sentinel", str(grandchild_sentinel),
        "--lifetime-ms", "60000",
    ]
    gc_cmd = [c for c in gc_cmd if c]

    gc_proc = subprocess.Popen(
        gc_cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    # Give the grandchild a moment to start
    time.sleep(0.1)

    # Write [child_pid, grandchild_pid] to the sentinel
    pids = [os.getpid(), gc_proc.pid]
    sentinel_path.write_text(json.dumps(pids), encoding="utf-8")

    # Sleep for lifetime_ms then exit
    time.sleep(lifetime_ms / 1000.0)


# ---------------------------------------------------------------------------
# Contract runner
# ---------------------------------------------------------------------------

_RESULT_SCHEMA = "kinglet.host-probe.result/v1"


def _pass(assertion_id: str) -> dict[str, str]:
    return {"id": assertion_id, "status": "pass"}


def _fail(assertion_id: str, reason: str) -> dict[str, str]:
    return {"id": assertion_id, "status": "fail", "reason": reason}


def run_contract(contract_path: Path, workspace: Path) -> dict[str, Any]:
    """Run all host probe assertions and return the result dict.

    The workspace may contain spaces and non-ASCII characters — that is by
    design (path.unicode-space assertion).
    """
    contract_path = Path(contract_path).resolve()
    workspace = Path(workspace).resolve()
    workspace.mkdir(parents=True, exist_ok=True)

    contract_dir = contract_path.parent
    contract = json.loads(contract_path.read_text(encoding="utf-8"))

    timings = contract.get("timings_ms", {})
    lease_ttl_ms: int = timings.get("lease_ttl", 1200)
    lease_renewal_ms: int = timings.get("lease_renewal", 400)
    lease_competitor_ms: int = timings.get("lease_competitor_attempt", 600)
    child_lifetime_ms: int = timings.get("child_lifetime", 30000)
    cancel_deadline_ms: int = timings.get("cancel_deadline", 5000)

    assertions: list[dict[str, str]] = []
    errors: list[str] = []
    descendant_pids: list[int] = []
    active_lease = False

    # ------------------------------------------------------------------
    # manifest.accept-valid
    # ------------------------------------------------------------------
    try:
        valid_dir = (contract_dir / contract.get("canonical_valid", "canonical-valid/")).resolve()
        load_graph(valid_dir)
        assertions.append(_pass("manifest.accept-valid"))
    except Exception as exc:
        assertions.append(_fail("manifest.accept-valid", str(exc)))
        errors.append(f"manifest.accept-valid: {exc}")

    # ------------------------------------------------------------------
    # manifest.reject-unknown
    # ------------------------------------------------------------------
    try:
        invalid_dir = (contract_dir / contract.get("canonical_invalid", "canonical-invalid/")).resolve()
        try:
            load_graph(invalid_dir)
            assertions.append(_fail("manifest.reject-unknown", "load_graph did not raise on invalid fixture"))
            errors.append("manifest.reject-unknown: load_graph should have raised BuildError")
        except BuildError:
            assertions.append(_pass("manifest.reject-unknown"))
        except Exception as exc:
            assertions.append(_fail("manifest.reject-unknown", f"unexpected exception: {exc}"))
            errors.append(f"manifest.reject-unknown: {exc}")
    except Exception as exc:
        assertions.append(_fail("manifest.reject-unknown", str(exc)))
        errors.append(f"manifest.reject-unknown: {exc}")

    # ------------------------------------------------------------------
    # path.unicode-space — workspace itself has unicode and space
    # ------------------------------------------------------------------
    try:
        unicode_file = workspace / "ünïcödé spàce.txt"
        unicode_file.write_text("ok", encoding="utf-8")
        content = unicode_file.read_text(encoding="utf-8")
        if content == "ok":
            assertions.append(_pass("path.unicode-space"))
        else:
            assertions.append(_fail("path.unicode-space", f"read back unexpected content: {content!r}"))
            errors.append("path.unicode-space: content mismatch")
    except Exception as exc:
        assertions.append(_fail("path.unicode-space", str(exc)))
        errors.append(f"path.unicode-space: {exc}")

    # ------------------------------------------------------------------
    # filesystem.atomic-replace
    # ------------------------------------------------------------------
    try:
        atomic_target = workspace / "atomic-state.json"
        atomic_replace(atomic_target, b'{"initial": true}\n')
        atomic_replace(atomic_target, b'{"replaced": true}\n')
        data = json.loads(atomic_target.read_bytes())
        leftovers = list(workspace.glob("*.tmp"))
        if data.get("replaced") is True and not leftovers:
            assertions.append(_pass("filesystem.atomic-replace"))
        else:
            msg = f"data={data!r} leftovers={leftovers}"
            assertions.append(_fail("filesystem.atomic-replace", msg))
            errors.append(f"filesystem.atomic-replace: {msg}")
    except Exception as exc:
        assertions.append(_fail("filesystem.atomic-replace", str(exc)))
        errors.append(f"filesystem.atomic-replace: {exc}")

    # ------------------------------------------------------------------
    # Lease scenarios
    # ------------------------------------------------------------------
    lease_path = workspace / ".lease" / "kinglet.lease"

    # lease.acquire
    lease_a = Lease(lease_path, lease_ttl_ms)
    lease_cleanup_needed = False
    try:
        ok = lease_a.acquire()
        if ok and lease_a.owner is not None:
            assertions.append(_pass("lease.acquire"))
            lease_cleanup_needed = True
        else:
            assertions.append(_fail("lease.acquire", "acquire returned False"))
            errors.append("lease.acquire: returned False")
    except Exception as exc:
        assertions.append(_fail("lease.acquire", str(exc)))
        errors.append(f"lease.acquire: {exc}")

    # lease.renew — wait until lease_renewal_ms before renewing (contract timing)
    try:
        time.sleep(lease_renewal_ms / 1000.0)
        ok = lease_a.renew()
        if ok:
            assertions.append(_pass("lease.renew"))
        else:
            assertions.append(_fail("lease.renew", "renew returned False"))
            errors.append("lease.renew: returned False")
    except Exception as exc:
        assertions.append(_fail("lease.renew", str(exc)))
        errors.append(f"lease.renew: {exc}")

    # lease.reject-competitor — wait until lease_competitor_ms before attempting
    # (contract timing); the additional wait after renew still keeps us well within ttl.
    try:
        extra_wait = max(0, (lease_competitor_ms - lease_renewal_ms)) / 1000.0
        time.sleep(extra_wait)
        lease_b = Lease(lease_path, lease_ttl_ms)
        ok_b = lease_b.acquire()
        if not ok_b:
            assertions.append(_pass("lease.reject-competitor"))
        else:
            assertions.append(_fail("lease.reject-competitor", "competitor was granted the lease"))
            errors.append("lease.reject-competitor: competitor acquired active lease")
            lease_b.release()
    except Exception as exc:
        assertions.append(_fail("lease.reject-competitor", str(exc)))
        errors.append(f"lease.reject-competitor: {exc}")

    # lease.expire — create a lease with a very short TTL and wait for it to expire,
    # then verify a new lease can be acquired.
    try:
        short_path = workspace / ".lease" / "short.lease"
        lease_short = Lease(short_path, 100)  # 100 ms TTL
        lease_short.acquire()
        time.sleep(0.3)  # wait well past TTL
        lease_new = Lease(short_path, lease_ttl_ms)
        ok_new = lease_new.acquire()
        if ok_new:
            assertions.append(_pass("lease.expire"))
            lease_new.release()
        else:
            assertions.append(_fail("lease.expire", "could not acquire after expired lease"))
            errors.append("lease.expire: could not re-acquire after TTL")
    except Exception as exc:
        assertions.append(_fail("lease.expire", str(exc)))
        errors.append(f"lease.expire: {exc}")

    # lease.release
    try:
        released = lease_a.release()
        still_exists = lease_path.exists()
        if released and not still_exists:
            assertions.append(_pass("lease.release"))
            lease_cleanup_needed = False
        else:
            assertions.append(_fail("lease.release", f"released={released} file_exists={still_exists}"))
            errors.append(f"lease.release: released={released} file_exists={still_exists}")
    except Exception as exc:
        assertions.append(_fail("lease.release", str(exc)))
        errors.append(f"lease.release: {exc}")
    finally:
        if lease_cleanup_needed:
            lease_a.release()

    # ------------------------------------------------------------------
    # Process tree
    # ------------------------------------------------------------------

    # process.child-grandchild / process.cancel / process.no-descendants —
    # delegate entirely to spawn_tree_and_cancel (the single real implementation).
    recorded_pids: list[int] = []
    try:
        recorded_pids, killed = spawn_tree_and_cancel(
            _EXE,
            workspace,
            child_lifetime_ms,
            cancel_deadline_ms,
        )

        if len(recorded_pids) >= 2:
            assertions.append(_pass("process.child-grandchild"))
        else:
            assertions.append(_fail("process.child-grandchild", f"sentinel had only {len(recorded_pids)} pids"))
            errors.append("process.child-grandchild: sentinel not ready in time")

        # process.cancel — pass only if killpg cancelled a live group (parity
        # with Go/Rust/.NET; independent of the no-descendants liveness poll).
        if recorded_pids and killed:
            assertions.append(_pass("process.cancel"))
        elif not killed:
            assertions.append(_fail("process.cancel", "killpg did not cancel a live process group"))
        else:
            assertions.append(_fail("process.cancel", "no pids recorded — see process.child-grandchild"))

        # process.no-descendants — every recorded PID must be gone.
        if recorded_pids and all(not _is_pid_alive(p) for p in recorded_pids):
            assertions.append(_pass("process.no-descendants"))
        else:
            alive = [p for p in recorded_pids if _is_pid_alive(p)]
            if not recorded_pids:
                assertions.append(_fail("process.no-descendants", "no pids recorded"))
            else:
                assertions.append(_fail("process.no-descendants", f"pids still alive: {alive}"))
                descendant_pids = alive
                errors.append(f"process.no-descendants: pids still alive: {alive}")

    except Exception as exc:
        assertions.append(_fail("process.child-grandchild", str(exc)))
        assertions.append(_fail("process.cancel", str(exc)))
        assertions.append(_fail("process.no-descendants", str(exc)))
        errors.append(f"process: {exc}")

    # ------------------------------------------------------------------
    # Crypto
    # ------------------------------------------------------------------

    # crypto.sha256
    try:
        digest = hashlib.sha256(b"").hexdigest()
        expected = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        if digest == expected:
            assertions.append(_pass("crypto.sha256"))
        else:
            assertions.append(_fail("crypto.sha256", f"got {digest}"))
            errors.append(f"crypto.sha256: got {digest}")
    except Exception as exc:
        assertions.append(_fail("crypto.sha256", str(exc)))
        errors.append(f"crypto.sha256: {exc}")

    # crypto.ed25519 — load vectors from contract
    try:
        vectors_path = contract_dir / contract.get("crypto_vectors", "ed25519-rfc8032.json")
        vectors = json.loads(vectors_path.read_text(encoding="utf-8"))
        msg_hex = vectors["message"]
        pub_hex = vectors["public_key"]
        sig_hex = vectors["signature"]
        ok = verify_ed25519(msg_hex, pub_hex, sig_hex)
        if ok:
            assertions.append(_pass("crypto.ed25519"))
        else:
            assertions.append(_fail("crypto.ed25519", "RFC 8032 vector 1 failed"))
            errors.append("crypto.ed25519: RFC 8032 vector 1 failed")
    except Exception as exc:
        assertions.append(_fail("crypto.ed25519", str(exc)))
        errors.append(f"crypto.ed25519: {exc}")

    # ------------------------------------------------------------------
    # Cleanup scenarios — wrap four scenarios in try/finally
    # Each scenario is: do something that might fail, then always clean up.
    # We record whether cleanup happened cleanly.
    # ------------------------------------------------------------------

    # cleanup.success — a normal run; verify the workspace is writable and
    # resources created during the run are released.  Since all our per-assertion
    # resources above were cleaned up in their own blocks, we verify a new lease
    # can be acquired and released cleanly.
    # FIX A: initialize cl and tmp before try so finally block never sees NameError
    # if cl.acquire() or atomic_replace raises before they are assigned.
    cl_path = workspace / ".cleanup" / "success.lease"
    cl: Lease | None = None
    tmp: Path | None = None
    try:
        try:
            cl = Lease(cl_path, lease_ttl_ms)
            cl.acquire()
            tmp = workspace / "cleanup-success.tmp"
            atomic_replace(tmp, b"ok")
        finally:
            if cl is not None:
                cl.release()
            if tmp is not None:
                try:
                    tmp.unlink(missing_ok=True)
                except OSError:
                    pass
        assertions.append(_pass("cleanup.success"))
    except Exception as exc:
        assertions.append(_fail("cleanup.success", str(exc)))
        errors.append(f"cleanup.success: {exc}")

    # cleanup.crash — simulate a crash (exception inside the body), verify
    # that the finally block still cleans up.
    cl_crash_path = workspace / ".cleanup" / "crash.lease"
    cl_crash = Lease(cl_crash_path, lease_ttl_ms)
    crash_cleanup_ok = False
    try:
        try:
            cl_crash.acquire()
            raise RuntimeError("simulated crash")
        finally:
            cl_crash.release()
            crash_cleanup_ok = True
    except RuntimeError:
        pass
    except Exception as exc:
        errors.append(f"cleanup.crash: {exc}")

    if crash_cleanup_ok:
        assertions.append(_pass("cleanup.crash"))
    else:
        assertions.append(_fail("cleanup.crash", "finally block did not run after simulated crash"))
        errors.append("cleanup.crash: finally block failed")

    # cleanup.timeout — simulate a timeout (alarm or deadline exceeded), verify
    # finally block cleans up.
    cl_timeout_path = workspace / ".cleanup" / "timeout.lease"
    cl_timeout = Lease(cl_timeout_path, lease_ttl_ms)
    timeout_cleanup_ok = False
    try:
        try:
            cl_timeout.acquire()
            # Simulate timeout condition without actually waiting
            raise TimeoutError("simulated timeout")
        finally:
            cl_timeout.release()
            timeout_cleanup_ok = True
    except TimeoutError:
        pass
    except Exception as exc:
        errors.append(f"cleanup.timeout: {exc}")

    if timeout_cleanup_ok:
        assertions.append(_pass("cleanup.timeout"))
    else:
        assertions.append(_fail("cleanup.timeout", "finally block did not run after timeout"))
        errors.append("cleanup.timeout: finally block failed")

    # cleanup.cancel — simulate cancellation (KeyboardInterrupt or signal), verify
    # finally block cleans up.
    cl_cancel_path = workspace / ".cleanup" / "cancel.lease"
    cl_cancel = Lease(cl_cancel_path, lease_ttl_ms)
    cancel_cleanup_ok = False
    try:
        try:
            cl_cancel.acquire()
            raise KeyboardInterrupt("simulated cancel")
        finally:
            cl_cancel.release()
            cancel_cleanup_ok = True
    except KeyboardInterrupt:
        pass
    except Exception as exc:
        errors.append(f"cleanup.cancel: {exc}")

    if cancel_cleanup_ok:
        assertions.append(_pass("cleanup.cancel"))
    else:
        assertions.append(_fail("cleanup.cancel", "finally block did not run after cancel"))
        errors.append("cleanup.cancel: finally block failed")

    # ------------------------------------------------------------------
    # Final active-lease check
    # ------------------------------------------------------------------
    # All leases should have been released by now (including cleanup.success).
    active_lease = any(
        p.exists()
        for p in [lease_path, cl_path, cl_crash_path, cl_timeout_path, cl_cancel_path]
    )

    # ------------------------------------------------------------------
    # Build result
    # ------------------------------------------------------------------
    # Make sure we have exactly the required assertion IDs (no more, no less).
    # Map to a dict for fast lookup so we can reorder/fill any gaps.
    seen_ids = {a["id"] for a in assertions}
    for required_id in REQUIRED_ASSERTIONS:
        if required_id not in seen_ids:
            assertions.append(_fail(required_id, "assertion not reached"))
            errors.append(f"{required_id}: not reached")

    # Filter to only required assertions (in contract order) with no duplicates
    assertion_map: dict[str, dict[str, str]] = {}
    for a in assertions:
        if a["id"] in set(REQUIRED_ASSERTIONS) and a["id"] not in assertion_map:
            assertion_map[a["id"]] = a
    ordered_assertions = [assertion_map[aid] for aid in REQUIRED_ASSERTIONS if aid in assertion_map]

    all_pass = all(a["status"] == "pass" for a in ordered_assertions) and not descendant_pids and not active_lease
    status = "pass" if all_pass else "fail"

    return {
        "schema": _RESULT_SCHEMA,
        "candidate": {
            "id": CANDIDATE_ID,
            "version": CANDIDATE_VERSION,
        },
        "status": status,
        "errors": errors,
        "assertions": [{"id": a["id"], "status": a["status"]} for a in ordered_assertions],
        "descendant_pids": descendant_pids,
        "active_lease": active_lease,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(prog="kinglet_host_probe")
    sub = parser.add_subparsers(dest="command")

    run_p = sub.add_parser("run", help="Run the full host probe contract")
    run_p.add_argument("--contract", required=True, type=Path)
    run_p.add_argument("--workspace", required=True, type=Path)
    run_p.add_argument("--result", required=True, type=Path)

    child_p = sub.add_parser("child", help="Internal: child process for process-tree test")
    child_p.add_argument("--sentinel", required=True, type=Path)
    child_p.add_argument("--lifetime-ms", required=True, type=int)

    ver_p = sub.add_parser("version", help="Print candidate version string")

    args = parser.parse_args()

    if args.command == "run":
        result = run_contract(args.contract, args.workspace)
        result_bytes = json.dumps(result, indent=2, ensure_ascii=False).encode("utf-8")
        # Write result to file
        atomic_replace(Path(args.result), result_bytes)
        # Also emit to stdout for the black-box launcher
        sys.stdout.buffer.write(result_bytes)
        sys.stdout.buffer.write(b"\n")
        sys.stdout.buffer.flush()
        sys.exit(0 if result["status"] == "pass" else 1)

    elif args.command == "child":
        _run_child(args.sentinel, args.lifetime_ms)
        sys.exit(0)

    elif args.command == "version":
        print(f"{CANDIDATE_ID} {CANDIDATE_VERSION}")
        sys.exit(0)

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
