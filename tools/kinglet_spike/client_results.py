"""client_results.py — Load, validate, and convert client probe observations.

Public API
----------
ClientObservationSet    Parsed observation document (dataclass).
load_client_observations(path)      Path → ClientObservationSet
validate_client_observations(value, cases)  dict → ClientObservationSet
to_evidence_records(observations, environment)  → tuple[EvidenceRecord, ...]

Validation rules (kinglet.client-probe.observations/v1)
-------------------------------------------------------
* Unknown fields in a case entry → E_FIELD.
* Missing or duplicate case IDs vs. the frozen case catalog → E_COVERAGE.
* Native/pass  requires ≥1 artifact_path (E_ASSERTION).
* Emulated/pass additionally requires emulation_mechanism (E_ASSERTION).
* Unavailable   requires status=unavailable and ≥1 source_url (E_FIELD).
* inconclusive must have no grade field (grade absent/None); if a grade is
  present, raise E_ENUM.
* A fail may carry a grade but never closes the cell.
* Cases sorted by ID in the resulting ClientObservationSet.

probe.id choice
---------------
`matrix-v1.json` does not define one cell per client. It defines three per
client on linux and macos (`local-executable`, `mcp-discovery`,
`path-semantics`) and one on windows. The old code hardcoded
probe.id="capability-suite", which is the *suffix of the windows cell id* and
not the `probe` value of any cell on any platform — coverage matches on
`record.probe.id == cell.probe`, so that record closed nothing anywhere.

PROBE_GROUPS below is the single reviewable table that partitions the 12 frozen
cases across the three split cells; PLATFORM_PROBES says which cells a platform
has. One record is emitted per cell, carrying only that cell's cases.

record-level `sources`
----------------------
evidence-v1 requires a `pass` record to carry ≥1 source reference, and the
runtime records satisfy it by citing the *provenance of the subject under test*
— ".NET 10.0.10 runtime" → the .NET download page. Client records need the same
thing: where the client binary came from, not what the probe observed.

Case `source_urls` cannot serve that purpose. In this schema a case's
`source_urls` documents an *Unavailable* grade ("the vendor says this does not
exist"); a Native/pass is evidenced by artifacts and carries none. Deriving the
record's sources from the cases therefore produced an empty `sources` on exactly
the record whose cases all passed, and the all-pass cell published as `invalid`.

CLIENT_SOURCES below fixes that at the right level: it is declared once per
client id, alongside the subject, and says nothing about any observation. Case
`source_urls` are still appended (a client with an Unavailable case keeps its
citation), but they are never the only thing there. An unknown client id is an
error, not an empty list — see client_sources().

run_id shape
------------
`<UTC stamp>-client-probe-<subject>-<os>-<release>-<arch>-<probe>-01`, matching
the runtime records (`20260727T051518Z-runtime-python-linux-noble-01`) with a
probe segment added. It must be qualified by BOTH environment and probe:
publish.py keys on `evidence/<kind>/<id>/<run_id>.json` and raises E_IMMUTABLE
on collision, so a subject-only id lets exactly one host per client be published
ever, and a merely environment-qualified id lets exactly one of the three
per-probe records from a single host be published.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Sequence

from .model import (
    Artifact,
    AssertionResult,
    Environment,
    EvidenceError,
    EvidenceRecord,
    Measurement,
    Probe,
    PromptReference,
    SourceReference,
    Subject,
)

# ---------------------------------------------------------------------------
# Schema constants
# ---------------------------------------------------------------------------

OBSERVATIONS_SCHEMA = "kinglet.client-probe.observations/v1"
EVIDENCE_SCHEMA = "kinglet.spike.evidence/v1"

VALID_GRADES = frozenset(("Native", "Emulated", "Unavailable"))
VALID_STATUSES = frozenset(("pass", "fail", "unavailable", "inconclusive"))

# Exact set of allowed fields in a case observation entry.
_CASE_FIELDS = frozenset((
    "id",
    "advertised",
    "observed",
    "grade",
    "status",
    "source_urls",
    "artifact_paths",
    "notes",
    "emulation_mechanism",
))

_PROBE_CONTRACT = "kinglet.client-probe.observations/v1"

# ---------------------------------------------------------------------------
# THE case → matrix probe cell mapping
# ---------------------------------------------------------------------------
# One row per split probe cell. Every case id in the frozen catalog
# (spikes/platform/clients/contracts/cases-v1.json) appears in exactly one row;
# partition_cases() enforces both halves of that against the observations, which
# validate_client_observations() has already pinned to the catalog exactly.
#
# The axis is what each case actually demonstrates, not which words it shares
# with a cell name:
#
#   local-executable  the client locates and operates on something installed on
#                     the local machine — the toolkit install lifecycle
#                     (discover / update / remove) plus the PATH invocation the
#                     cell is named for.
#   mcp-discovery     the client resolves a capability BY NAME and invokes it,
#                     and the structured result that comes back: MCP tools,
#                     sub-agents, the natural-language workflow entry point, and
#                     the receipt those invocations are required to produce.
#   path-semantics    behaviour that turns on WHICH path or scope a rule
#                     resolves against: project-root instructions, project-vs-user
#                     settings stores, and the two guards (hook, approval) that
#                     fire on a path inside the project.
PROBE_GROUPS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("local-executable", (
        "executable.local",
        "install.discover",
        "install.remove",
        "install.update",
    )),
    ("mcp-discovery", (
        "agents.delegation",
        "mcp.discover-call",
        "structured-result",
        "workflow.natural-language",
    )),
    ("path-semantics", (
        "approvals.mutation",
        "hooks.pre-mutation-block",
        "instructions.project",
        "scope.project-user",
    )),
)

# Windows defines a single aggregate cell per client instead of the three-way
# split. Its matrix `probe` value is "client-capability-suite"; the bare
# "capability-suite" is only the suffix of the cell *id*, and using it as the
# probe id is what made the previous record match no cell at all.
AGGREGATE_PROBE = "client-capability-suite"

_SPLIT_PROBES = tuple(probe_id for probe_id, _ in PROBE_GROUPS)

# os → the probe cells matrix-v1.json defines for a client on that platform.
PLATFORM_PROBES: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("linux", _SPLIT_PROBES),
    ("macos", _SPLIT_PROBES),
    ("windows", (AGGREGATE_PROBE,)),
)

# Characters kept verbatim by _slugify; everything else becomes '-'.
_SLUG_ALLOWED = frozenset("abcdefghijklmnopqrstuvwxyz0123456789.-")

# ---------------------------------------------------------------------------
# Per-client provenance of the binary under test
# ---------------------------------------------------------------------------
# One row per client id: (title template, url). `{version}` in the title is
# filled from observations.client_version, so the citation names the exact build
# that was probed — the client analogue of ".NET 10.0.10 runtime".
#
# These document WHERE THE SUBJECT CAME FROM. They are not evidence of anything
# the probe saw, must never be derived from a case's observations, and must be
# real URLs that resolve. A client with no row here cannot publish a record at
# all (client_sources raises), because a pass with no sources is invalid under
# evidence-v1 and quietly emitting one is how a cell ends up `invalid` with no
# explanation.
CLIENT_SOURCES: tuple[tuple[str, tuple[tuple[str, str], ...]], ...] = (
    ("claude-code", (
        # The published release the probed build was installed from; the
        # registry document lists 2.1.220 among its versions.
        ("Claude Code {version} (@anthropic-ai/claude-code)",
         "https://registry.npmjs.org/@anthropic-ai/claude-code"),
        # The vendor documentation for the subject.
        ("Claude Code documentation",
         "https://code.claude.com/docs/en/overview"),
    )),
    ("codex", (
        # The published release the probed build was installed from; the
        # registry document lists 0.145.0 among its versions.
        ("Codex CLI {version} (@openai/codex)",
         "https://registry.npmjs.org/@openai/codex"),
        # The vendor documentation for the subject.
        ("Codex CLI documentation",
         "https://developers.openai.com/codex/cli/"),
    )),
)


# ---------------------------------------------------------------------------
# Dataclasses
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class CaseObservation:
    id: str
    advertised: bool
    observed: str
    grade: str | None          # None for inconclusive
    status: str
    source_urls: tuple[str, ...]
    artifact_paths: tuple[str, ...]
    notes: str
    emulation_mechanism: str | None


@dataclass(frozen=True)
class ClientObservationSet:
    schema: str
    subject: str
    client_version: str
    cases: tuple[CaseObservation, ...]   # sorted by id


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _string(value: Any, path: str) -> str:
    if not isinstance(value, str):
        raise EvidenceError("E_FIELD", f"{path} must be a string")
    return value


def _boolean(value: Any, path: str) -> bool:
    if type(value) is not bool:
        raise EvidenceError("E_FIELD", f"{path} must be a boolean")
    return value


def _strings(value: Any, path: str) -> tuple[str, ...]:
    if not isinstance(value, list):
        raise EvidenceError("E_FIELD", f"{path} must be an array")
    return tuple(_string(item, f"{path}[{i}]") for i, item in enumerate(value))


def _opt_string(value: Any, path: str) -> str | None:
    if value is None:
        return None
    return _string(value, path)


def _parse_case(raw: Any, index: int) -> CaseObservation:
    path = f"cases[{index}]"
    if not isinstance(raw, dict):
        raise EvidenceError("E_FIELD", f"{path} must be an object")

    unknown = sorted(raw.keys() - _CASE_FIELDS)
    if unknown:
        raise EvidenceError("E_FIELD", f"{path}.{unknown[0]} is an unknown field")

    case_id = _string(raw.get("id", ""), f"{path}.id")
    advertised = _boolean(raw.get("advertised", None), f"{path}.advertised")
    observed = _string(raw.get("observed", ""), f"{path}.observed")
    raw_grade = raw.get("grade", None)
    status_raw = raw.get("status", "")

    status = _string(status_raw, f"{path}.status")
    if status not in VALID_STATUSES:
        raise EvidenceError("E_ENUM", f"{path}.status has unsupported value: {status!r}")

    # inconclusive must have no grade
    if status == "inconclusive":
        if raw_grade is not None:
            raise EvidenceError(
                "E_ENUM",
                f"{path}: inconclusive status must not carry a grade; got {raw_grade!r}",
            )
        grade: str | None = None
    else:
        if raw_grade is not None:
            grade = _string(raw_grade, f"{path}.grade")
            if grade not in VALID_GRADES:
                raise EvidenceError("E_ENUM", f"{path}.grade has unsupported value: {grade!r}")
        else:
            grade = None

    source_urls = _strings(raw.get("source_urls", []), f"{path}.source_urls")
    artifact_paths = _strings(raw.get("artifact_paths", []), f"{path}.artifact_paths")
    notes = _string(raw.get("notes", ""), f"{path}.notes")
    emulation_mechanism = _opt_string(raw.get("emulation_mechanism", None), f"{path}.emulation_mechanism")

    # Grade/status specific validation
    if status == "pass":
        if grade == "Native":
            if not artifact_paths:
                raise EvidenceError(
                    "E_ASSERTION",
                    f"{path}: Native/pass requires at least one artifact_path",
                )
        elif grade == "Emulated":
            if not artifact_paths:
                raise EvidenceError(
                    "E_ASSERTION",
                    f"{path}: Emulated/pass requires at least one artifact_path",
                )
            if not emulation_mechanism:
                raise EvidenceError(
                    "E_ASSERTION",
                    f"{path}: Emulated/pass requires a non-null emulation_mechanism",
                )

    if grade == "Unavailable":
        if status != "unavailable":
            raise EvidenceError(
                "E_FIELD",
                f"{path}: Unavailable grade requires status=unavailable",
            )
        if not source_urls:
            raise EvidenceError(
                "E_FIELD",
                f"{path}: Unavailable grade requires at least one source_url",
            )

    return CaseObservation(
        id=case_id,
        advertised=advertised,
        observed=observed,
        grade=grade,
        status=status,
        source_urls=source_urls,
        artifact_paths=artifact_paths,
        notes=notes,
        emulation_mechanism=emulation_mechanism,
    )


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def validate_client_observations(
    value: Any,
    cases: Sequence[dict],
) -> ClientObservationSet:
    """Parse and strictly validate a raw observations dict against the frozen case catalog.

    Args:
        value:  Raw decoded JSON object (dict).
        cases:  The frozen case catalog — a sequence of dicts each with an "id" key.
                Typically CASES from tests.kinglet_spike.client_support or loaded from
                cases-v1.json.

    Returns:
        ClientObservationSet with cases sorted by id.

    Raises:
        EvidenceError with one of:
          E_SCHEMA   — wrong or missing schema string.
          E_FIELD    — wrong type, unknown field, missing required field.
          E_ENUM     — invalid grade/status value, or inconclusive carrying a grade.
          E_ASSERTION— Native/pass missing artifact; Emulated/pass missing artifact or mechanism.
          E_COVERAGE — missing or duplicate case IDs vs. the frozen catalog.
    """
    if not isinstance(value, dict):
        raise EvidenceError("E_SCHEMA", "observations must be a JSON object")

    schema = value.get("schema")
    if schema != OBSERVATIONS_SCHEMA:
        raise EvidenceError("E_SCHEMA", f"unsupported observations schema: {schema!r}")

    subject = _string(value.get("subject", ""), "subject")
    client_version = _string(value.get("client_version", ""), "client_version")

    raw_cases = value.get("cases")
    if not isinstance(raw_cases, list):
        raise EvidenceError("E_FIELD", "cases must be an array")

    parsed: list[CaseObservation] = []
    for index, raw in enumerate(raw_cases):
        parsed.append(_parse_case(raw, index))

    # Coverage check: all required case IDs must appear exactly once.
    required_ids = tuple(c["id"] for c in cases)
    required_set = frozenset(required_ids)
    seen_ids: dict[str, int] = {}
    for obs in parsed:
        if obs.id in seen_ids:
            raise EvidenceError(
                "E_COVERAGE",
                f"duplicate case id: {obs.id!r}",
            )
        seen_ids[obs.id] = 1

    missing = sorted(required_set - seen_ids.keys())
    if missing:
        raise EvidenceError(
            "E_COVERAGE",
            f"missing case ids: {missing}",
        )

    extra = sorted(seen_ids.keys() - required_set)
    if extra:
        raise EvidenceError(
            "E_COVERAGE",
            f"unexpected case ids: {extra}",
        )

    return ClientObservationSet(
        schema=schema,
        subject=subject,
        client_version=client_version,
        cases=tuple(sorted(parsed, key=lambda c: c.id)),
    )


def load_client_observations(path: Path) -> ClientObservationSet:
    """Load a kinglet.client-probe.observations/v1 JSON file from disk.

    The frozen case catalog is loaded from
    spikes/platform/clients/contracts/cases-v1.json (relative to cwd).

    Args:
        path:  Path to the observations JSON file.

    Returns:
        Validated ClientObservationSet.

    Raises:
        EvidenceError (E_JSON) if the file cannot be read or is not valid JSON.
        EvidenceError (other codes) on schema / validation failure.
    """
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError("E_JSON", f"cannot decode {path}: {error}") from error

    cases_path = Path("spikes/platform/clients/contracts/cases-v1.json")
    try:
        cases_raw = json.loads(cases_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError("E_JSON", f"cannot load case catalog: {error}") from error

    cases = cases_raw.get("cases", [])
    return validate_client_observations(value, cases)


def _slugify(value: str) -> str:
    """Lowercase, and every character outside [a-z0-9.-] becomes '-'.

    Mirrors slugify() in spikes/platform/runtime/run-host.sh so client run_ids
    satisfy the publisher's SAFE_COMPONENT the same way runtime ones do.
    """
    lowered = value.lower()
    return "".join(char if char in _SLUG_ALLOWED else "-" for char in lowered)


def host_slug(environment: Environment) -> str:
    """The environment component of a run_id: <os>-<release>-<arch>, slugified."""
    return _slugify(f"{environment.os}-{environment.release}-{environment.arch}")


def build_run_id(
    safe_subject: str,
    environment: Environment,
    timestamp: str,
    probe_id: str,
) -> str:
    """Build an environment- AND probe-qualified run_id.

    Shape follows the runtime records
    (`20260727T051518Z-runtime-python-linux-noble-01`):
    `<UTC stamp>-client-probe-<subject>-<host slug>-<probe>-01`.

    Deriving the id from the subject alone made every Claude Code host record
    collide on `evidence/<kind>/<id>/<run_id>.json`, so the second host could
    never be published (E_IMMUTABLE). Adding the host slug fixed that, but one
    host now emits one record per probe cell, and those three collide with each
    other on the same key for the same reason. `probe_id` is required, not
    defaulted, so a caller cannot reintroduce the collision by omission.
    """
    stamp = timestamp.replace("-", "").replace(":", "")
    return (
        f"{stamp}-client-probe-{safe_subject}-{host_slug(environment)}"
        f"-{_slugify(probe_id)}-01"
    )


def case_probe_map() -> dict[str, str]:
    """Invert PROBE_GROUPS to {case id: probe id}.

    Raises:
        EvidenceError E_COVERAGE if a case id appears in more than one group.
        A case in two groups would otherwise close two cells off one
        observation, which is double-counting evidence.
    """
    mapping: dict[str, str] = {}
    for probe_id, case_ids in PROBE_GROUPS:
        for case_id in case_ids:
            if case_id in mapping:
                raise EvidenceError(
                    "E_COVERAGE",
                    f"case {case_id!r} is mapped to two probes: "
                    f"{mapping[case_id]!r} and {probe_id!r}",
                )
            mapping[case_id] = probe_id
    return mapping


def client_sources(subject: str, version: str) -> tuple[SourceReference, ...]:
    """The declared provenance of `subject`'s binary, at `version`.

    Raises:
        EvidenceError E_COVERAGE if the client has no CLIENT_SOURCES row.
        Returning () instead would let a new client publish an all-pass record
        with no source references, which validate.py marks invalid and coverage
        then reports as an open cell with no stated reason. Failing here says
        what is actually missing.
    """
    for client_id, entries in CLIENT_SOURCES:
        if client_id == subject:
            return tuple(
                SourceReference(title=title.format(version=version), url=url)
                for title, url in entries
            )
    known = ", ".join(client_id for client_id, _ in CLIENT_SOURCES)
    raise EvidenceError(
        "E_COVERAGE",
        f"no CLIENT_SOURCES row declares where client {subject!r} came from "
        f"(known: {known}); a record with no sources cannot pass validation",
    )


def probes_for_os(os_name: str) -> tuple[str, ...]:
    """The matrix probe cells defined for a client on `os_name`.

    Raises:
        EvidenceError E_COVERAGE for an os with no client cells. Failing here
        beats silently defaulting to one platform's cell shape on another.
    """
    for name, probes in PLATFORM_PROBES:
        if name == os_name:
            return probes
    known = ", ".join(name for name, _ in PLATFORM_PROBES)
    raise EvidenceError(
        "E_COVERAGE",
        f"no client probe cells are defined for os {os_name!r} (known: {known})",
    )


def partition_cases(
    observations: ClientObservationSet,
    os_name: str,
) -> tuple[tuple[str, tuple[CaseObservation, ...]], ...]:
    """Split the observed cases across the probe cells `os_name` defines.

    Returns one (probe id, cases) pair per cell, in PLATFORM_PROBES order. On
    windows the single aggregate cell carries every case.

    Raises:
        EvidenceError E_COVERAGE if an observed case is in no group, maps to a
        probe this platform does not define, or if a group ends up empty. Every
        case must land in exactly one cell — a case that quietly vanished from
        the table would otherwise be dropped from the evidence without a word.
    """
    probes = probes_for_os(os_name)
    if probes == (AGGREGATE_PROBE,):
        return ((AGGREGATE_PROBE, observations.cases),)

    mapping = case_probe_map()
    buckets: dict[str, list[CaseObservation]] = {probe: [] for probe in probes}
    for case in observations.cases:
        probe_id = mapping.get(case.id)
        if probe_id is None:
            raise EvidenceError(
                "E_COVERAGE",
                f"case {case.id!r} is in no PROBE_GROUPS row, so its evidence "
                f"would be silently dropped",
            )
        if probe_id not in buckets:
            raise EvidenceError(
                "E_COVERAGE",
                f"case {case.id!r} maps to probe {probe_id!r}, which os "
                f"{os_name!r} does not define",
            )
        buckets[probe_id].append(case)

    empty = tuple(probe for probe in probes if not buckets[probe])
    if empty:
        raise EvidenceError(
            "E_COVERAGE",
            f"probe {empty[0]!r} carries no observed case, so it would publish "
            f"an evidence-free record",
        )
    return tuple((probe, tuple(buckets[probe])) for probe in probes)


def _prompt_digest(text: str) -> str:
    """Return the SHA-256 digest of the UTF-8 encoded prompt text."""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _load_prompts() -> dict[str, str]:
    """Load prompts-v1.json and return {id: sha256_digest} mapping.

    Digests are recomputed from the UTF-8 text at load time.
    """
    prompts_path = Path("spikes/platform/clients/contracts/prompts-v1.json")
    try:
        raw = json.loads(prompts_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvidenceError("E_JSON", f"cannot load prompt catalog: {error}") from error
    return {p["id"]: _prompt_digest(p["text"]) for p in raw.get("prompts", [])}


def _build_record(
    observations: ClientObservationSet,
    environment: Environment,
    probe_id: str,
    cases: Sequence[CaseObservation],
    now: str,
) -> EvidenceRecord:
    """Build one EvidenceRecord for one probe cell from that cell's cases."""
    # Build assertions from cases.
    assertions: list[AssertionResult] = []
    artifacts: list[Artifact] = []
    # The subject's own provenance leads; case source_urls are appended below.
    # This is what stops an all-pass record from publishing with sources=[].
    sources: list[SourceReference] = list(
        client_sources(observations.subject, observations.client_version)
    )
    seen_paths: set[str] = set()
    seen_urls: set[str] = {source.url for source in sources}

    overall_status = "pass"

    for case in cases:
        a_status = "pass" if case.status == "pass" else "fail"
        if case.status != "pass":
            overall_status = "fail"
        assertions.append(AssertionResult(
            id=case.id,
            status=a_status,
            detail=case.observed or case.status,
        ))

        # Collect artifacts from passing Native/Emulated cases.
        if case.status == "pass" and case.grade in ("Native", "Emulated"):
            for ap in case.artifact_paths:
                if ap not in seen_paths:
                    seen_paths.add(ap)
                    artifacts.append(Artifact(
                        path=ap,
                        sha256="0" * 64,   # placeholder — harness verifies real checksum on disk
                        media_type="application/json",
                        required=True,
                    ))

        # Collect source URLs.
        for url in case.source_urls:
            if url not in seen_urls:
                seen_urls.add(url)
                sources.append(SourceReference(
                    title=case.id,
                    url=url,
                ))

    safe_subject = observations.subject.replace("-", "")[:24]
    run_id = build_run_id(safe_subject, environment, now, probe_id)

    return EvidenceRecord(
        schema=EVIDENCE_SCHEMA,
        run_id=run_id,
        subject=Subject(
            kind="client",
            id=observations.subject,
            version=observations.client_version,
        ),
        probe=Probe(
            id=probe_id,
            contract=_PROBE_CONTRACT,
        ),
        environment=environment,
        started_at=now,
        ended_at=now,
        status=overall_status,
        command=(),
        artifacts=tuple(artifacts),
        assertions=tuple(assertions),
        measurements=(),
        sources=tuple(sources),
        prompt=None,
    )


def to_evidence_records(
    observations: ClientObservationSet,
    environment: Environment,
) -> tuple[EvidenceRecord, ...]:
    """Convert a validated ClientObservationSet to one record per probe cell.

    Three records on linux/macos (`local-executable`, `mcp-discovery`,
    `path-semantics`), one on windows (`client-capability-suite`). Each record
    uses subject.kind="client" and carries only its cell's cases — every case
    lands in exactly one record, enforced by partition_cases().

    Passing cases contribute AssertionResult entries (status="pass").
    Failing/inconclusive cases contribute AssertionResult entries (status="fail"),
    which also drops the record's own status off "pass". Coverage keys a cell's
    state on record.status, so a cell with any unobserved case stays open.

    Artifacts are synthesised from artifact_paths on passing Native/Emulated cases.
    The prompt field is omitted (None) since the probe set covers multiple prompts.

    Args:
        observations:   Validated ClientObservationSet.
        environment:    Environment dataclass (os, release, arch, native, toolchain).

    Returns:
        Tuple of EvidenceRecord with schema="kinglet.spike.evidence/v1", in
        PLATFORM_PROBES order.
    """
    import datetime

    now = datetime.datetime.now(tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return tuple(
        _build_record(observations, environment, probe_id, cases, now)
        for probe_id, cases in partition_cases(observations, environment.os)
    )
