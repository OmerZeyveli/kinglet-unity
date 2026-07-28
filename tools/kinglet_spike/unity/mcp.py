"""mcp.py -- Server-vs-Editor readiness for the `live-editor-mcp` route.

The one sentence this module exists to enforce
----------------------------------------------
**A running MCP server is not an Editor-ready state.** Readiness requires the
EXPECTED project instance, at the EXPECTED Unity version, with compilation
idle and `ready_for_tools` true. A socket that answers is none of those
things, and every measured fact below is a way that a socket answering can
look like success.

MEASURED ON THIS HOST, against the pinned server
------------------------------------------------
(`mcp-for-unity` from CoplayDev/unity-mcp @ 78ee5418, HTTP transport bound to
127.0.0.1, `DISABLE_TELEMETRY=1`, no Unity Editor running anywhere.)

MEASURED FACT 1 -- "no Editor at all" is a SUCCESS response.
    $ unity-mcp --host 127.0.0.1 --port P --format json instances
    {"success": true, "instances": []}          exit 0

  Exit 0, `success: true`, and a well-formed JSON body -- describing a state
  in which nothing can be compiled and no test can be run. This is precisely
  the "server started, therefore ready" mistake, handed to us pre-packaged as
  a success. `select_instance` treats an empty list as NOT ready, and
  `_evaluate` has no branch that can reach ready=True without an instance.

MEASURED FACT 2 -- `--format json` does NOT guarantee JSON, and the error
goes to stderr while stdout stays EMPTY.
    $ unity-mcp ... --format json raw get_editor_state
    (stdout: empty)                             exit 1
    (stderr) ❌ HTTP error from server: 503 - {"success":false,"error":"No
             Unity instances connected. Make sure Unity is running with MCP
             plugin."}

  So a caller that parses stdout gets nothing, and a caller that greps stderr
  is parsing a decorated human string. Neither is a source of truth about
  whether the SERVER is up -- both describe the EDITOR being absent.

MEASURED FACT 3 -- an unreachable server looks almost the same.
    $ unity-mcp --host 127.0.0.1 --port <closed> --format json instances
    (stdout: empty)                             exit 1
    (stderr) ❌ Cannot connect to Unity MCP server at 127.0.0.1:41351. ...
             Error: All connection attempts failed

  Facts 2 and 3 differ only in prose. That is exactly the lossy source Task 3
  was burned on, so this module does not distinguish them by reading either
  message. It distinguishes them by an EXACT signal instead: `/api/instances`
  is a plain REST endpoint that answers whether or not an Editor is connected
  (fact 1 proves it), so **a well-formed `instances` response IS the
  reachability proof**, and nothing else is consulted for that question. See
  `CATEGORY_*` below for why that distinction is load-bearing.

READ FROM THE PINNED SOURCE (not guessed, not assumed from a newer release)
--------------------------------------------------------------------------
SOURCE FACT 4 -- `get_editor_state` cannot say which project it came from.
  `MCPForUnity/Editor/Services/EditorStateCache.cs` builds its snapshot with
  `InstanceId = null` and `ProjectId = null`, hardcoded. The snapshot carries
  `unity.unity_version` and nothing else identifying. So project identity can
  only come from the instance listing, and the state call MUST be routed to a
  named instance (`--instance Name@hash`) or the server picks a session for
  us. `probe_editor` therefore selects the instance FIRST and passes its
  token to every subsequent call.

SOURCE FACT 5 -- the canonical instance identity is a hash of `Application.dataPath`.
  `MCPForUnity/Editor/Helpers/ProjectIdentityUtility.cs`:
  `sha1(utf8(dataPath))` hex, truncated to 16 chars, lowercased -- where
  `dataPath` is `<project>/Assets` with forward slashes on every platform.
  `project_instance_hash()` reproduces it exactly, so matching is an equality
  test on a computed value rather than a name comparison. The listing's
  `project` field is only the directory NAME (`ComputeProjectName`), which two
  different checkouts of the same fixture share -- matching on it would be the
  lossy answer when an exact one exists.

SOURCE FACT 6 -- `ready_for_tools` is computed by the PYTHON server, not by Unity,
and its own computation is permissive-by-construction.
  `Server/src/services/resources/editor_state.py::_enrich_advice_and_staleness`
  adds `advice.ready_for_tools` to the MCP *resource*; the raw `get_editor_state`
  command answered by Unity has no `advice` key at all. Worse, that function
  builds its blocking list with `if compilation.get("is_compiling") is True`,
  so a snapshot in which `is_compiling` is **missing or null** contributes no
  blocking reason and the Editor is declared ready. That is Task 3's defect
  verbatim: the unresolved case falls through to the permissive answer.

  `_evaluate` here inverts it. Every readiness signal must be present and
  EXACTLY `False`; absent, null, or non-boolean yields a `*-unknown` blocking
  reason. `advice.ready_for_tools`, when present, is required to be `True` --
  but it is never sufficient on its own, because the snapshot it summarises is
  checked independently.

SOURCE FACT 7 -- `run_tests` cannot return results, and `--wait` is dropped.
  `Server/src/services/tools/run_tests.py` and
  `MCPForUnity/Editor/Tools/RunTests.cs` both return
  `{job_id, status: "running"}` IMMEDIATELY; `wait_timeout` is a parameter of
  `get_test_job`, not of `run_tests`, and the CLI's `editor tests --wait N`
  path forwards the command straight to the C# handler, which reads only
  `mode`, `includeDetails`, `includeFailedTests` and `initTimeout`. So the
  brief's literal `editor tests --mode EditMode --wait 180 --details` starts a
  job and reports "running" -- it is structurally incapable of returning a
  pass. It is the same shape as Task 5's `-quit` finding: a command whose
  success output is not evidence of the outcome it appears to report.
  `run_tests_via_mcp` therefore starts the job and polls `get_test_job`
  itself, and treats a non-terminal status at the deadline as a refusal.

Why "could not tell" is never ready
-----------------------------------
`_evaluate` returns `(ready, blocking_reasons)` and `ready` is literally
`not blocking_reasons`. There is no branch that clears a reason without
observing the fact that clears it, and every parse failure, missing field,
wrong type, timeout and unreachable call APPENDS a reason. The permissive
answer is unreachable by construction rather than by review.

The two categories, and why they must not merge
-----------------------------------------------
`CATEGORY_SERVER_START_FAILED` means the server never became reachable --
a bug in how we started it. `CATEGORY_EDITOR_NOT_READY` means the server is
demonstrably fine and the EDITOR never arrived, or arrived wrong, or never
went idle. Collapsing them would make "we started a server and called it a
day" indistinguishable from "the Editor we needed never showed up", which is
the exact confusion the plan's global constraint names. `wait_for_editor`
assigns the category from whether the reachability probe EVER succeeded --
an observed fact, not an error-message guess.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import socket
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence

from ..model import EvidenceError
from .process import ManagedProcess

__all__ = (
    "MCP_SERVER_COMMIT",
    "MCP_SERVER_SPEC",
    "MCP_CLI_ENTRYPOINT",
    "MCP_SERVER_ENTRYPOINT",
    "CATEGORY_SERVER_START_FAILED",
    "CATEGORY_EDITOR_NOT_READY",
    "STALENESS_LIMIT_MS",
    "McpCall",
    "McpInstance",
    "McpEditorState",
    "TestJobSummary",
    "SubprocessMcpClient",
    "project_data_path",
    "project_instance_hash",
    "project_instance_name",
    "instance_token",
    "list_instances",
    "select_instance",
    "fetch_editor_state",
    "probe_editor",
    "wait_for_editor",
    "reserve_local_port",
    "mcp_server_argv",
    "mcp_cli_argv",
    "start_mcp",
    "wait_for_server",
    "run_tests_via_mcp",
    "read_console_errors",
    "clear_console",
    "refresh_assets",
    "parse_test_job",
    "InstancesProbe",
    "TERMINAL_JOB_STATUSES",
    "MCP_SERVER_STARTUP_SECONDS",
    "MCP_EDITOR_READY_SECONDS",
    "EDIT_MODE_TESTS_SECONDS",
)

# ---------------------------------------------------------------------------
# The pin. NOT relaxed -- see the standing rulings: the Unity version pin is
# relaxed to any 6000 line, the CoplayDev MCP pin is not.
# ---------------------------------------------------------------------------

MCP_SERVER_COMMIT: str = "78ee5418415953b79c358bfe6355fcc3fde7912b"
MCP_SERVER_SPEC: str = (
    "git+https://github.com/CoplayDev/unity-mcp.git@"
    f"{MCP_SERVER_COMMIT}#subdirectory=Server"
)
MCP_SERVER_ENTRYPOINT: str = "mcp-for-unity"
MCP_CLI_ENTRYPOINT: str = "unity-mcp"

# routes-v1.json timings_seconds.
MCP_SERVER_STARTUP_SECONDS: float = 60.0
MCP_EDITOR_READY_SECONDS: float = 300.0
EDIT_MODE_TESTS_SECONDS: float = 180.0

# The server's own staleness threshold (_enrich_advice_and_staleness). Matched
# deliberately: diverging would make our readiness verdict disagree with the
# `advice` block we also check, and a stricter local number would refuse
# Editors the server itself calls ready without any measured reason to.
STALENESS_LIMIT_MS: int = 2000

CATEGORY_SERVER_START_FAILED: str = "mcp.server-start-failed"
CATEGORY_EDITOR_NOT_READY: str = "mcp.editor-not-ready"

# Blocking-reason vocabulary. Every one of these is appended by an observation
# that FAILED; none is ever appended by an observation that succeeded.
REASON_SERVER_UNREACHABLE = "server-unreachable"
REASON_INSTANCES_MALFORMED = "instances-malformed"
REASON_NO_INSTANCES = "no-instances"
REASON_NO_MATCHING_INSTANCE = "no-matching-instance"
REASON_INSTANCE_VERSION_MISMATCH = "instance-version-mismatch"
REASON_STATE_UNAVAILABLE = "state-unavailable"
REASON_STATE_MALFORMED = "state-malformed"
REASON_STATE_VERSION_MISMATCH = "state-version-mismatch"
REASON_ADVICE_NOT_READY = "advice-not-ready"
REASON_COMPILING = "compiling"
REASON_DOMAIN_RELOAD = "domain-reload"
REASON_RUNNING_TESTS = "running-tests"
REASON_ASSET_REFRESH = "asset-refresh"
REASON_ASSET_IMPORT = "asset-import"
REASON_STALE_STATUS = "stale-status"


# ---------------------------------------------------------------------------
# Project identity -- SOURCE FACT 5
# ---------------------------------------------------------------------------

def project_data_path(project) -> str:
    """Reproduce Unity's `Application.dataPath` for a project on disk.

    Always forward slashes, always absolute, always `<project>/Assets`. Unity
    normalises to forward slashes on every platform including Windows, and the
    hash below is taken over these exact bytes, so a `WindowsPath` rendering
    with backslashes would produce a hash that never matches a real Editor.
    """
    return Path(project).resolve().as_posix().rstrip("/") + "/Assets"


def project_instance_hash(project) -> str:
    """The 16-char SHA-1 prefix a real Editor registers itself under.

    Byte-for-byte the C# in ProjectIdentityUtility.ComputeProjectHash: SHA-1
    over the UTF-8 of `Application.dataPath`, lowercase hex, first 16 chars.
    This is the ONLY identity check that distinguishes the pinned disposable
    copy from another checkout of the same fixture -- the listing's `project`
    field is just the directory name and both copies would share it.
    """
    digest = hashlib.sha1(project_data_path(project).encode("utf-8")).hexdigest()
    return digest[:16].lower()


def project_instance_name(project) -> str:
    """The directory name Unity reports as the project name (ComputeProjectName)."""
    return Path(project).resolve().name or "Unknown"


def instance_token(instance: "McpInstance") -> str:
    """The `Name@hash` form the CLI's `--instance` accepts."""
    return f"{instance.project}@{instance.hash}"


# ---------------------------------------------------------------------------
# Client seam
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class McpCall:
    """One completed CLI invocation, with NOTHING interpreted yet.

    `payload` is the JSON object parsed from stdout, or None. It is None both
    when stdout was empty (MEASURED FACTS 2 and 3) and when stdout was not
    JSON; callers never infer anything from WHICH of those it was, because the
    two are not distinguishable from a decorated error string.
    """

    argv: tuple[str, ...]
    exit_code: int
    stdout: str
    stderr: str
    payload: object | None
    timed_out: bool = False


def _parse_payload(stdout: str) -> object | None:
    stripped = stdout.strip()
    if not stripped:
        return None
    try:
        return json.loads(stripped)
    except ValueError:
        return None


def mcp_cli_argv(
    *args: str,
    host: str,
    port: int,
    instance: str | None = None,
    uvx: str = "uvx",
) -> list[str]:
    """The exact argv array for one `unity-mcp` CLI call.

    An array, never a string. `--instance` is placed among the GLOBAL options
    (before the subcommand), which is where the pinned CLI reads it -- see
    `Server/src/cli/main.py`.
    """
    argv = [
        uvx, "--from", MCP_SERVER_SPEC, MCP_CLI_ENTRYPOINT,
        "--host", host, "--port", str(port), "--format", "json",
    ]
    if instance is not None:
        argv += ["--instance", instance]
    argv += list(args)
    return argv


def mcp_server_argv(*, host: str, port: int, uvx: str = "uvx") -> list[str]:
    """The exact argv array for the pinned MCP server, bound to LOOPBACK only.

    `host` is passed through rather than hardcoded so a test can prove the
    loopback guard below fires, but `start_mcp` refuses any non-loopback host:
    this server accepts commands that drive a real Editor, so binding it to a
    routable address exposes the developer's project to the network.
    """
    return [
        uvx, "--from", MCP_SERVER_SPEC, MCP_SERVER_ENTRYPOINT,
        "--transport", "http",
        "--http-host", host,
        "--http-port", str(port),
    ]


class SubprocessMcpClient:
    """The real client: shells out to the pinned `unity-mcp` CLI.

    Deliberately dumb. It returns what happened (`McpCall`) and interprets
    nothing, so that every readiness decision is made by `_evaluate`, which the
    tests drive directly. A timeout is a returned `McpCall(timed_out=True)`
    rather than an exception, because a timeout is one of the states that must
    NOT collapse into ready and the evaluator is the only place that decides.
    """

    def __init__(self, *, host: str, port: int, uvx: str = "uvx", env: dict | None = None) -> None:
        self.host = host
        self.port = port
        self.uvx = uvx
        self.env = env

    def _env(self) -> dict:
        base = dict(os.environ) if self.env is None else dict(self.env)
        base.setdefault("DISABLE_TELEMETRY", "1")
        return base

    def call(
        self,
        args: Sequence[str],
        *,
        instance: str | None = None,
        timeout: float = 60.0,
    ) -> McpCall:
        argv = mcp_cli_argv(
            *args, host=self.host, port=self.port, instance=instance, uvx=self.uvx
        )
        try:
            completed = subprocess.run(
                argv,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
                env=self._env(),
            )
        except subprocess.TimeoutExpired as expired:
            return McpCall(
                argv=tuple(argv),
                exit_code=-1,
                stdout=expired.stdout or "" if isinstance(expired.stdout, str) else "",
                stderr=expired.stderr or "" if isinstance(expired.stderr, str) else "",
                payload=None,
                timed_out=True,
            )
        except OSError as error:
            return McpCall(
                argv=tuple(argv), exit_code=-1, stdout="",
                stderr=f"cannot execute {self.uvx}: {error}", payload=None,
            )
        return McpCall(
            argv=tuple(argv),
            exit_code=completed.returncode,
            stdout=completed.stdout,
            stderr=completed.stderr,
            payload=_parse_payload(completed.stdout),
        )


# ---------------------------------------------------------------------------
# Instance listing and selection
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class McpInstance:
    """One connected Editor, exactly as `/api/instances` describes it."""

    session_id: str
    project: str
    hash: str
    unity_version: str


@dataclass(frozen=True)
class InstancesProbe:
    """The outcome of one `instances` call.

    `reachable` is the ONLY reachability verdict in this module, and it is an
    observation: a JSON object on stdout carrying `success: true` and a list.
    MEASURED FACT 1 is what makes this exact -- the endpoint answers with a
    well-formed body whether or not any Editor is connected, so a well-formed
    body proves the server and says nothing about the Editor.
    """

    reachable: bool
    instances: tuple[McpInstance, ...]
    reasons: tuple[str, ...]
    call: McpCall | None = None


def _instance_from_entry(entry: object) -> McpInstance | None:
    if not isinstance(entry, dict):
        return None
    project = entry.get("project")
    project_hash = entry.get("hash")
    version = entry.get("unity_version")
    session = entry.get("session_id")
    if not isinstance(project_hash, str) or not project_hash:
        return None
    return McpInstance(
        session_id=session if isinstance(session, str) else "",
        project=project if isinstance(project, str) else "",
        hash=project_hash,
        unity_version=version if isinstance(version, str) else "",
    )


def list_instances(client, *, timeout: float = 60.0) -> InstancesProbe:
    """Ask the server which Editors are connected, and decide nothing else."""
    call = client.call(("instances",), timeout=timeout)
    payload = call.payload
    if not isinstance(payload, dict):
        # Empty stdout (server down, MEASURED FACT 3) or non-JSON noise. Both
        # mean we have no usable answer, which is not the same as "no Editor".
        return InstancesProbe(False, (), (REASON_SERVER_UNREACHABLE,), call)
    if payload.get("success") is not True:
        return InstancesProbe(False, (), (REASON_SERVER_UNREACHABLE,), call)
    raw = payload.get("instances")
    if not isinstance(raw, list):
        # The server answered, so it IS up; its answer is just unusable.
        return InstancesProbe(True, (), (REASON_INSTANCES_MALFORMED,), call)

    parsed: list[McpInstance] = []
    malformed = False
    for entry in raw:
        instance = _instance_from_entry(entry)
        if instance is None:
            malformed = True
            continue
        parsed.append(instance)

    reasons: list[str] = []
    if malformed:
        reasons.append(REASON_INSTANCES_MALFORMED)
    if not parsed:
        reasons.append(REASON_NO_INSTANCES)
    return InstancesProbe(True, tuple(parsed), tuple(reasons), call)


def select_instance(
    instances: Sequence[McpInstance],
    *,
    project,
    unity_version: str,
) -> tuple[McpInstance | None, tuple[str, ...]]:
    """Pick the ONE instance that is the expected project at the expected version.

    Matching is on `project_instance_hash(project)` (SOURCE FACT 5) -- an
    exact equality test on a value we compute the same way Unity does. A
    version mismatch on an otherwise-matching instance is reported as its own
    reason rather than as "not found", because "the right project opened in
    the wrong Editor" is a different and more alarming fact than "the project
    is not open".
    """
    expected_hash = project_instance_hash(project)
    matches = [item for item in instances if item.hash == expected_hash]
    if not matches:
        return None, (REASON_NO_MATCHING_INSTANCE,)
    for candidate in matches:
        if candidate.unity_version == unity_version:
            return candidate, ()
    return None, (REASON_INSTANCE_VERSION_MISMATCH,)


# ---------------------------------------------------------------------------
# Editor state
# ---------------------------------------------------------------------------

def fetch_editor_state(client, *, instance: McpInstance, timeout: float = 60.0) -> McpCall:
    """Ask one NAMED instance for its readiness snapshot.

    Routed with `--instance` always: SOURCE FACT 4 means the reply cannot
    identify itself, so an unrouted call against a host with two Editors open
    would answer for whichever session the server picked.
    """
    return client.call(("raw", "get_editor_state"), instance=instance_token(instance), timeout=timeout)


def _state_data(payload: object) -> dict | None:
    """Unwrap `{"success": true, "data": {...}}` down to the v2 snapshot."""
    if not isinstance(payload, dict):
        return None
    if payload.get("success") is False:
        return None
    data = payload.get("data")
    if isinstance(data, dict):
        return data
    # Some transports hand back the snapshot unwrapped; accept it only when it
    # actually looks like one, never as a fallback for an unrecognised shape.
    if "schema_version" in payload or "compilation" in payload:
        return payload
    return None


def _require_false(container: object, key: str, *, reason: str, unknown_suffix: str = "-unknown") -> list[str]:
    """`False` clears; `True` blocks; ANYTHING ELSE blocks as unknown.

    This is the inversion of SOURCE FACT 6. The server's own rule is
    `if value is True: block`, which lets null and missing through as ready.
    Here only an explicit boolean `False` is an observation that the Editor is
    idle in this respect; null, missing, a string, or a number means nobody
    established it, and nobody establishing it is not readiness.
    """
    value = container.get(key) if isinstance(container, dict) else None
    if value is False:
        return []
    if value is True:
        return [reason]
    return [reason + unknown_suffix]


def _evaluate(
    data: object,
    *,
    unity_version: str,
    now_ms: int,
) -> tuple[bool, tuple[str, ...], int | None]:
    """Turn a raw editor-state snapshot into (ready, blocking_reasons, age_ms).

    `ready` is `not blocking_reasons`, computed at the end and nowhere else.
    Every check below can only ever APPEND, so there is no path that reaches
    ready=True without every signal having been observed.
    """
    reasons: list[str] = []
    snapshot = _state_data(data)
    if snapshot is None:
        return False, (REASON_STATE_MALFORMED,), None

    # The Editor's own version, cross-checked against the version the instance
    # listing registered. Two independent reports of the same fact; a
    # disagreement means one of them is not describing the Editor we think.
    unity_block = snapshot.get("unity")
    reported = unity_block.get("unity_version") if isinstance(unity_block, dict) else None
    if not isinstance(reported, str) or reported != unity_version:
        reasons.append(REASON_STATE_VERSION_MISMATCH)

    compilation = snapshot.get("compilation")
    reasons += _require_false(compilation, "is_compiling", reason=REASON_COMPILING)
    reasons += _require_false(
        compilation, "is_domain_reload_pending", reason=REASON_DOMAIN_RELOAD
    )

    tests = snapshot.get("tests")
    reasons += _require_false(tests, "is_running", reason=REASON_RUNNING_TESTS)

    assets = snapshot.get("assets")
    reasons += _require_false(assets, "is_updating", reason=REASON_ASSET_IMPORT)
    refresh = assets.get("refresh") if isinstance(assets, dict) else None
    reasons += _require_false(refresh, "is_refresh_in_progress", reason=REASON_ASSET_REFRESH)

    # Staleness. An unfocused GUI Editor throttles EditorApplication.update, so
    # a snapshot minutes old is a real and common state -- and a stale snapshot
    # saying "not compiling" is a statement about the past, not about now.
    observed = snapshot.get("observed_at_unix_ms")
    age_ms: int | None = None
    if isinstance(observed, bool) or not isinstance(observed, int):
        reasons.append(REASON_STALE_STATUS + "-unknown")
    else:
        age_ms = max(0, now_ms - observed)
        if age_ms > STALENESS_LIMIT_MS:
            reasons.append(REASON_STALE_STATUS)

    # `advice` is only present when the snapshot came through the Python MCP
    # resource rather than the raw command (SOURCE FACT 6). When it IS there it
    # must agree; it is never trusted alone, and its absence is not a reason.
    advice = snapshot.get("advice")
    if isinstance(advice, dict) and advice.get("ready_for_tools") is not True:
        reasons.append(REASON_ADVICE_NOT_READY)

    # Stable order, no duplicates -- reasons are compared in tests and written
    # into raw evidence.
    unique = tuple(sorted(set(reasons)))
    return (not unique), unique, age_ms


@dataclass(frozen=True)
class McpEditorState:
    """The verdict. `ready` is true ONLY for the expected, idle, matching Editor."""

    ready: bool
    category: str | None
    blocking_reasons: tuple[str, ...]
    instance: McpInstance | None = None
    unity_version: str | None = None
    age_ms: int | None = None
    polls: int = 0
    server_reachable: bool = False
    detail: str = ""

    def require_ready(self) -> "McpEditorState":
        if not self.ready:
            raise EvidenceError(
                "E_UNITY_MCP_NOT_READY",
                f"{self.category}: {', '.join(self.blocking_reasons) or 'unknown'}"
                + (f" ({self.detail})" if self.detail else ""),
            )
        return self


def probe_editor(
    client,
    *,
    project,
    unity_version: str,
    now_ms: int | None = None,
    call_timeout: float = 60.0,
) -> McpEditorState:
    """One full readiness observation: server -> instance -> snapshot.

    Short-circuits downward, never upward: an unreachable server never reaches
    the instance check, and a missing instance never reaches the snapshot
    check, so a later step can never clear an earlier step's reason.
    """
    listing = list_instances(client, timeout=call_timeout)
    if not listing.reachable:
        return McpEditorState(
            ready=False,
            category=CATEGORY_SERVER_START_FAILED,
            blocking_reasons=listing.reasons,
            server_reachable=False,
        )
    if listing.reasons:
        return McpEditorState(
            ready=False,
            category=CATEGORY_EDITOR_NOT_READY,
            blocking_reasons=listing.reasons,
            server_reachable=True,
        )

    instance, reasons = select_instance(
        listing.instances, project=project, unity_version=unity_version
    )
    if instance is None:
        return McpEditorState(
            ready=False,
            category=CATEGORY_EDITOR_NOT_READY,
            blocking_reasons=reasons,
            server_reachable=True,
        )

    call = fetch_editor_state(client, instance=instance, timeout=call_timeout)
    if call.payload is None:
        # MEASURED FACT 2: this is what "server up, Editor gone" looks like --
        # empty stdout and a 503 on stderr. Also what a timeout looks like.
        return McpEditorState(
            ready=False,
            category=CATEGORY_EDITOR_NOT_READY,
            blocking_reasons=(REASON_STATE_UNAVAILABLE,),
            instance=instance,
            unity_version=instance.unity_version,
            server_reachable=True,
            detail="timed out" if call.timed_out else "no JSON on stdout",
        )

    stamp = int(time.time() * 1000) if now_ms is None else now_ms
    ready, blocking, age_ms = _evaluate(
        call.payload, unity_version=unity_version, now_ms=stamp
    )
    return McpEditorState(
        ready=ready,
        category=None if ready else CATEGORY_EDITOR_NOT_READY,
        blocking_reasons=blocking,
        instance=instance,
        unity_version=instance.unity_version,
        age_ms=age_ms,
        server_reachable=True,
    )


def wait_for_editor(
    client,
    *,
    project,
    unity_version: str,
    timeout: float = MCP_EDITOR_READY_SECONDS,
    poll_interval: float = 2.0,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
    now_ms: Callable[[], int] | None = None,
    call_timeout: float = 60.0,
) -> McpEditorState:
    """Poll until the EXPECTED Editor is ready, or until the deadline.

    Returns the last observation rather than raising, so a caller can record
    exactly why it gave up; `require_ready()` is the raising form.

    The category on timeout is decided by an OBSERVATION: if any poll ever
    produced a well-formed `instances` response, the server was demonstrably
    up and the failure is `mcp.editor-not-ready`. Only a run in which the
    server never once answered is `mcp.server-start-failed`. This is the
    brief's "server-only timeout is categorized mcp.editor-not-ready" -- and
    the "server-only" case (server answering, zero instances, forever) is
    MEASURED FACT 1, which returns exit 0 and would otherwise read as success.
    """
    deadline = clock() + timeout
    polls = 0
    ever_reachable = False
    state = McpEditorState(
        ready=False,
        category=CATEGORY_SERVER_START_FAILED,
        blocking_reasons=(REASON_SERVER_UNREACHABLE,),
        detail="no poll completed before the deadline",
    )
    while True:
        polls += 1
        state = probe_editor(
            client,
            project=project,
            unity_version=unity_version,
            now_ms=None if now_ms is None else now_ms(),
            call_timeout=call_timeout,
        )
        ever_reachable = ever_reachable or state.server_reachable
        if state.ready:
            return McpEditorState(
                ready=True, category=None, blocking_reasons=(),
                instance=state.instance, unity_version=state.unity_version,
                age_ms=state.age_ms, polls=polls, server_reachable=True,
            )
        if clock() >= deadline:
            break
        sleep(poll_interval)

    category = CATEGORY_EDITOR_NOT_READY if ever_reachable else CATEGORY_SERVER_START_FAILED
    return McpEditorState(
        ready=False,
        category=category,
        blocking_reasons=state.blocking_reasons,
        instance=state.instance,
        unity_version=state.unity_version,
        age_ms=state.age_ms,
        polls=polls,
        server_reachable=ever_reachable,
        detail=state.detail,
    )


# ---------------------------------------------------------------------------
# Server process
# ---------------------------------------------------------------------------

_LOOPBACK_HOSTS = frozenset(("127.0.0.1", "::1", "localhost"))


def reserve_local_port() -> int:
    """Pick a free loopback port by binding it and letting go.

    Inherently a hint rather than a reservation -- the port can be taken
    between the close and the server's bind. That race is not closed here
    because the failure mode is loud (the server refuses to bind and
    `wait_for_server` reports server-start-failed), not silent.
    """
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as handle:
        handle.bind(("127.0.0.1", 0))
        return int(handle.getsockname()[1])


def start_mcp(
    raw_dir,
    *,
    host: str = "127.0.0.1",
    port: int | None = None,
    uvx: str = "uvx",
    env: dict | None = None,
    process_factory: Callable[..., ManagedProcess] = ManagedProcess.start,
) -> tuple[ManagedProcess, int]:
    """Start the PINNED MCP server, contained, on loopback only.

    Returns the contained process and the port it was told to bind, so the
    caller can build a client for exactly that server rather than discovering
    one it did not start. `DISABLE_TELEMETRY=1` is set unconditionally.

    Refuses a non-loopback host outright: this server relays commands into a
    live Editor, and `--http-host 0.0.0.0` would put a developer's project on
    the network. `0.0.0.0` is the value a helpful default would reach for,
    which is precisely why it is rejected rather than normalised.
    """
    if host not in _LOOPBACK_HOSTS:
        raise EvidenceError(
            "E_UNITY_MCP_BIND",
            f"refusing to bind the MCP server to {host!r}; this server drives a "
            "live Unity Editor and may only listen on loopback",
        )
    raw_dir = Path(raw_dir)
    raw_dir.mkdir(parents=True, exist_ok=True)
    resolved_port = reserve_local_port() if port is None else int(port)

    process_env = dict(os.environ) if env is None else dict(env)
    process_env["DISABLE_TELEMETRY"] = "1"

    process = process_factory(
        mcp_server_argv(host=host, port=resolved_port, uvx=uvx),
        cwd=raw_dir,
        env=process_env,
        stdout_path=raw_dir / "mcp-server.stdout",
        stderr_path=raw_dir / "mcp-server.stderr",
    )
    return process, resolved_port


def wait_for_server(
    client,
    *,
    timeout: float = MCP_SERVER_STARTUP_SECONDS,
    poll_interval: float = 1.0,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> InstancesProbe:
    """Wait until `instances` answers -- which is reachability and nothing more.

    Deliberately does NOT wait for an instance to appear. Merging the two
    waits is exactly the conflation this module exists to prevent: the caller
    must then wait for the Editor separately, and the failure of each wait is
    reported under its own category.
    """
    deadline = clock() + timeout
    probe = InstancesProbe(False, (), (REASON_SERVER_UNREACHABLE,))
    while True:
        probe = list_instances(client)
        if probe.reachable:
            return probe
        if clock() >= deadline:
            return probe
        sleep(poll_interval)


# ---------------------------------------------------------------------------
# Tests through the bridge -- SOURCE FACT 7
# ---------------------------------------------------------------------------

TERMINAL_JOB_STATUSES: frozenset[str] = frozenset(("succeeded", "failed", "cancelled"))


@dataclass(frozen=True)
class TestJobSummary:
    """A COMPLETED test job's counts, normalized onto the receipt vocabulary."""

    status: str
    total: int
    passed: int
    failed: int
    skipped: int
    result_state: str
    job_id: str = ""


def _int_field(container: dict, key: str) -> int:
    value = container.get(key)
    if isinstance(value, bool) or not isinstance(value, int):
        raise EvidenceError(
            "E_UNITY_MCP_RESULTS_MALFORMED",
            f"test summary field {key!r} is not an integer: {value!r}",
        )
    if value < 0:
        raise EvidenceError(
            "E_UNITY_MCP_RESULTS_MALFORMED",
            f"test summary field {key!r} is negative: {value}",
        )
    return value


def parse_test_job(payload: object) -> TestJobSummary:
    """Read a `get_test_job` reply, or refuse.

    Refuses -- rather than reporting zeroes -- on every shape that is not a
    finished job carrying a summary. A job still `running` at the deadline is
    the MCP analogue of Task 5's missing `results.xml`: nothing establishes
    that any test ran, and a zeroed summary would read as a clean empty pass.
    """
    if not isinstance(payload, dict) or payload.get("success") is False:
        raise EvidenceError(
            "E_UNITY_MCP_RESULTS_MALFORMED",
            f"test job reply is not a successful MCP response: {payload!r}",
        )
    data = payload.get("data")
    if not isinstance(data, dict):
        raise EvidenceError(
            "E_UNITY_MCP_RESULTS_MALFORMED", "test job reply carries no data object"
        )
    status = data.get("status")
    if not isinstance(status, str) or not status:
        raise EvidenceError(
            "E_UNITY_MCP_RESULTS_MALFORMED", "test job reply carries no status"
        )
    job_id = data.get("job_id") if isinstance(data.get("job_id"), str) else ""
    if status not in TERMINAL_JOB_STATUSES:
        raise EvidenceError(
            "E_UNITY_MCP_RESULTS_MISSING",
            f"test job {job_id or '?'} is still {status!r}; nothing establishes "
            "that any test ran, and this route does not report a job it never "
            "saw finish",
        )
    result = data.get("result")
    if not isinstance(result, dict):
        raise EvidenceError(
            "E_UNITY_MCP_RESULTS_MISSING",
            f"test job {job_id or '?'} finished as {status!r} but carries no "
            "result object; there are no counts to report",
        )
    summary = result.get("summary")
    if not isinstance(summary, dict):
        raise EvidenceError(
            "E_UNITY_MCP_RESULTS_MALFORMED",
            f"test job {job_id or '?'} result carries no summary object",
        )
    parsed = TestJobSummary(
        status=status,
        total=_int_field(summary, "total"),
        passed=_int_field(summary, "passed"),
        failed=_int_field(summary, "failed"),
        skipped=_int_field(summary, "skipped"),
        result_state=str(summary.get("resultState", "")),
        job_id=job_id,
    )
    counted = parsed.passed + parsed.failed + parsed.skipped
    if counted != parsed.total:
        raise EvidenceError(
            "E_UNITY_MCP_RESULTS_MALFORMED",
            f"test summary counts do not add up: passed+failed+skipped={counted} "
            f"but total={parsed.total}",
        )
    return parsed


def run_tests_via_mcp(
    client,
    *,
    instance: McpInstance,
    mode: str = "EditMode",
    timeout: float = EDIT_MODE_TESTS_SECONDS,
    poll_interval: float = 2.0,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
    call_timeout: float = 60.0,
) -> TestJobSummary:
    """Start an EditMode run through the bridge and poll it to a terminal state.

    SOURCE FACT 7 is why this is two calls and a loop rather than the brief's
    single `editor tests --wait 180`: `run_tests` returns a job id immediately
    and drops `wait_timeout` on the floor, so the single-call form reports
    `status: "running"` and could never back a passing claim. Polling
    `get_test_job` ourselves also means the deadline is ours, and a job that
    has not finished when it expires is refused rather than summarised.
    """
    token = instance_token(instance)
    start = client.call(
        ("editor", "tests", "--mode", mode, "--async", "--details"),
        instance=token,
        timeout=call_timeout,
    )
    payload = start.payload
    if not isinstance(payload, dict) or payload.get("success") is False:
        raise EvidenceError(
            "E_UNITY_MCP_TESTS_START",
            f"could not start an {mode} run through MCP; the bridge returned "
            f"exit {start.exit_code} with no usable JSON",
        )
    data = payload.get("data")
    job_id = data.get("job_id") if isinstance(data, dict) else None
    if not isinstance(job_id, str) or not job_id:
        raise EvidenceError(
            "E_UNITY_MCP_TESTS_START",
            f"the bridge accepted the {mode} run but returned no job id: {payload!r}",
        )

    deadline = clock() + timeout
    last: object | None = None
    while True:
        poll = client.call(
            ("raw", "get_test_job", json.dumps({"job_id": job_id, "includeDetails": True})),
            instance=token,
            timeout=call_timeout,
        )
        last = poll.payload
        if isinstance(last, dict):
            data = last.get("data")
            status = data.get("status") if isinstance(data, dict) else None
            if isinstance(status, str) and status in TERMINAL_JOB_STATUSES:
                return parse_test_job(last)
        if clock() >= deadline:
            break
        sleep(poll_interval)

    if isinstance(last, dict):
        # Raises E_UNITY_MCP_RESULTS_MISSING with the job's own last status.
        return parse_test_job(last)
    raise EvidenceError(
        "E_UNITY_MCP_RESULTS_MISSING",
        f"test job {job_id} never reported a readable status before the "
        f"{timeout}s deadline",
    )


# Unity writes `error CS####:` either at the start of a line or after a
# `(line,col):` file position. Same anchored shape routes.py uses -- an
# unanchored `error CS` also matches prose in a test name or an assertion
# message, which a PASSING run can put in the console.
_CONSOLE_COMPILE_ERROR_RE = re.compile(
    r"^(?:error CS\d+:|.*\(\d+,\d+\):\s*error CS\d+:)"
)


def read_console_errors(client, *, instance: McpInstance, timeout: float = 60.0) -> tuple[int, tuple[str, ...]]:
    """Count DISTINCT compile diagnostics in the Editor console, or refuse.

    Returns `(count, messages)`. An unreadable console raises rather than
    returning zero: "we could not read the console" and "the console is clean"
    are the same value under a permissive reading, and only one of them
    supports a `compile=pass` claim.
    """
    call = client.call(
        ("raw", "read_console", json.dumps({"action": "get", "types": ["error"], "count": 200})),
        instance=instance_token(instance),
        timeout=timeout,
    )
    payload = call.payload
    if not isinstance(payload, dict) or payload.get("success") is False:
        raise EvidenceError(
            "E_UNITY_MCP_CONSOLE",
            f"could not read the Unity console through MCP (exit {call.exit_code}); "
            "a compile claim cannot be made over an unread console",
        )
    data = payload.get("data")
    entries: list = []
    if isinstance(data, list):
        entries = data
    elif isinstance(data, dict):
        for key in ("messages", "logs", "entries"):
            if isinstance(data.get(key), list):
                entries = data[key]
                break
    elif data is not None:
        raise EvidenceError(
            "E_UNITY_MCP_CONSOLE",
            f"the console reply carried an unrecognised data shape: {type(data).__name__}",
        )

    seen: set[str] = set()
    for entry in entries:
        if isinstance(entry, dict):
            text = entry.get("message") or entry.get("text") or ""
        else:
            text = str(entry)
        for line in str(text).splitlines():
            stripped = line.strip()
            if _CONSOLE_COMPILE_ERROR_RE.match(stripped):
                seen.add(stripped)
    return len(seen), tuple(sorted(seen))


def clear_console(client, *, instance: McpInstance, timeout: float = 60.0) -> McpCall:
    """Clear the Editor console so the next read describes THIS run only."""
    return client.call(
        ("raw", "read_console", json.dumps({"action": "clear"})),
        instance=instance_token(instance),
        timeout=timeout,
    )


def refresh_assets(client, *, instance: McpInstance, timeout: float = 60.0) -> McpCall:
    """Ask the Editor to reimport and recompile before we judge it."""
    return client.call(
        ("editor", "refresh"), instance=instance_token(instance), timeout=timeout
    )
