import json
import re
from collections.abc import Mapping
from pathlib import Path, PurePosixPath

from .errors import BuildError
from .model import AdapterProfile, CanonicalGraph, CanonicalUnit


_SCHEMA_VERSION = 1
_CATALOG_NAMES = (
    "capabilities.json",
    "routing.json",
    "support-policy.json",
)
_ID_PATTERN = re.compile(
    r"^(role|workflow|knowledge|rule|hook|template)\.[a-z0-9][a-z0-9-]*$"
)
_DESCRIPTOR_NAMES = {
    kind: f"{kind}.json"
    for kind in ("role", "workflow", "knowledge", "rule", "hook", "template")
}
_WORKFLOW_REFERENCES = (
    ("roles", "role"),
    ("rules", "rule"),
    ("knowledge", "knowledge"),
)
_EXCEPTION_FIELDS = ("reason", "owner", "test")
_WRITE_CAPABILITIES = frozenset({"filesystem.write", "unity.write"})
_ADAPTER_CLIENTS = frozenset({"claude", "codex"})
_AGENT_PROFILE_NAMES = frozenset({"standard", "frontier"})
_REASONING_TIERS = frozenset({"fast", "balanced", "deep"})
_OUTPUT_ROOT_NAMES = {
    "claude": frozenset({"package", "compatibility"}),
    "codex": frozenset({"plugin", "project"}),
}
_ADAPTER_AUTHORITY_SHA256 = {
    "claude": "a6c608aa9b7958afc91d5f4f35febb94a778fcde9cf5402bf09f9c7514a8d8de",
    "codex": "7fdede81497571cd167155a868457bbaeb9dd853c9d90d443964a056f043f214",
}


def _build_error(
    code: str,
    source: Path,
    field: str,
    detail: str,
) -> BuildError:
    return BuildError(code=code, source=source, field=field, detail=detail)


def _unit_source(unit: CanonicalUnit) -> Path:
    id_kind = unit.id.partition(".")[0] if isinstance(unit.id, str) else ""
    descriptor_name = _DESCRIPTOR_NAMES.get(id_kind) or _DESCRIPTOR_NAMES.get(
        unit.kind
    )
    if descriptor_name is None:
        return unit.content_path
    return unit.content_path.parent / descriptor_name


def _sorted_units(graph: CanonicalGraph) -> tuple[tuple[str, CanonicalUnit], ...]:
    return tuple((unit_id, graph.units[unit_id]) for unit_id in sorted(graph.units))


def _validate_catalog_schemas(graph: CanonicalGraph) -> None:
    for catalog_name in _CATALOG_NAMES:
        source = graph.root / "src" / "catalog" / catalog_name
        data = json.loads(source.read_text(encoding="utf-8"))
        if type(data.get("schema_version")) is not int or data["schema_version"] != _SCHEMA_VERSION:
            raise _build_error(
                "invalid-schema-version",
                source,
                "schema_version",
                "catalog schema version must be 1",
            )


def _validate_unit_schemas(
    units: tuple[tuple[str, CanonicalUnit], ...],
) -> None:
    for _, unit in units:
        if type(unit.schema_version) is not int or unit.schema_version != _SCHEMA_VERSION:
            raise _build_error(
                "invalid-schema-version",
                _unit_source(unit),
                "schema_version",
                "canonical unit schema version must be 1",
            )


def _validate_ids_and_kinds(
    units: tuple[tuple[str, CanonicalUnit], ...],
) -> None:
    for graph_id, unit in units:
        identifier = (
            _ID_PATTERN.fullmatch(unit.id) if isinstance(unit.id, str) else None
        )
        if identifier is None or graph_id != unit.id:
            raise _build_error(
                "invalid-id",
                _unit_source(unit),
                "id",
                "ID must match canonical ID syntax and its graph key",
            )
        if unit.kind != identifier.group(1):
            raise _build_error(
                "invalid-kind",
                _unit_source(unit),
                "kind",
                f"unit kind must match the namespace in {unit.id}",
            )


def _validate_capabilities(
    graph: CanonicalGraph,
    units: tuple[tuple[str, CanonicalUnit], ...],
) -> None:
    for _, unit in units:
        for capability in sorted(unit.capabilities):
            if capability not in graph.capabilities:
                raise _build_error(
                    "unknown-capability",
                    _unit_source(unit),
                    "capabilities",
                    f"capability '{capability}' is not declared in capabilities.json",
                )


def _validate_reference(
    graph: CanonicalGraph,
    unit: CanonicalUnit,
    field: str,
    reference_id: str,
    expected_kind: str | None,
) -> None:
    referenced = graph.units.get(reference_id)
    if referenced is None:
        raise _build_error(
            "unresolved-reference",
            _unit_source(unit),
            field,
            f"reference '{reference_id}' does not resolve to a canonical unit",
        )
    if expected_kind is not None and referenced.kind != expected_kind:
        raise _build_error(
            "invalid-reference-kind",
            _unit_source(unit),
            field,
            f"reference '{reference_id}' must resolve to kind {expected_kind}, "
            f"not {referenced.kind}",
        )


def _validate_references(
    graph: CanonicalGraph,
    units: tuple[tuple[str, CanonicalUnit], ...],
) -> None:
    for _, unit in units:
        references = [
            (reference_id, "requires", None) for reference_id in unit.requires
        ]
        if unit.kind == "workflow":
            for field, expected_kind in _WORKFLOW_REFERENCES:
                references.extend(
                    (reference_id, field, expected_kind)
                    for reference_id in unit.attributes.get(field, ())
                )
        for reference_id, field, expected_kind in sorted(
            references,
            key=lambda reference: (reference[0], reference[1]),
        ):
            _validate_reference(
                graph,
                unit,
                field,
                reference_id,
                expected_kind,
            )


def _validate_support(
    graph: CanonicalGraph,
    units: tuple[tuple[str, CanonicalUnit], ...],
) -> None:
    required_clients = graph.support_policy.get("required_clients", ())
    allowed_states = frozenset(graph.support_policy.get("states", ()))
    for _, unit in units:
        for client in sorted(required_clients):
            if client not in unit.support:
                raise _build_error(
                    "missing-support",
                    _unit_source(unit),
                    f"support.{client}",
                    f"support declaration for {client} is required",
                )
        for client in sorted(unit.support):
            declaration = unit.support[client]
            if declaration.state not in allowed_states:
                raise _build_error(
                    "invalid-support",
                    _unit_source(unit),
                    f"support.{client}.state",
                    "support state must be supported, unsupported, or exception",
                )
            if declaration.state == "exception":
                for field in _EXCEPTION_FIELDS:
                    value = getattr(declaration, field)
                    if not isinstance(value, str) or not value.strip():
                        raise _build_error(
                            "invalid-support",
                            _unit_source(unit),
                            f"support.{client}.{field}",
                            f"exception support requires a non-empty {field}",
                        )
                continue
            exception_only_fields = _EXCEPTION_FIELDS
            if declaration.state == "unsupported":
                if declaration.reason is not None and (
                    not isinstance(declaration.reason, str)
                    or not declaration.reason.strip()
                ):
                    raise _build_error(
                        "invalid-support",
                        _unit_source(unit),
                        f"support.{client}.reason",
                        "unsupported support reason must be non-empty when declared",
                    )
                exception_only_fields = ("owner", "test")
            for field in exception_only_fields:
                if getattr(declaration, field) is not None:
                    raise _build_error(
                        "invalid-support",
                        _unit_source(unit),
                        f"support.{client}.{field}",
                        f"{declaration.state} support may not declare "
                        f"exception-only {field}",
                    )


def _validate_workflow_contract(
    units: tuple[tuple[str, CanonicalUnit], ...],
) -> None:
    for _, unit in units:
        if unit.kind != "workflow":
            continue
        for field, item_name in (
            ("stages", "stage"),
            ("artifacts", "artifact"),
            ("evidence", "evidence"),
        ):
            if not unit.attributes.get(field):
                raise _build_error(
                    "invalid-workflow",
                    _unit_source(unit),
                    field,
                    f"workflow requires at least one {item_name} item",
                )
        if unit.attributes.get("mutation") is True and not (
            _WRITE_CAPABILITIES.intersection(unit.capabilities)
        ):
            raise _build_error(
                "invalid-workflow",
                _unit_source(unit),
                "mutation",
                "mutating workflow requires filesystem.write or unity.write",
            )


def _validate_requires_cycles(
    graph: CanonicalGraph,
    units: tuple[tuple[str, CanonicalUnit], ...],
) -> None:
    state: dict[str, int] = {}
    stack: list[str] = []

    def visit(unit_id: str) -> None:
        state[unit_id] = 1
        stack.append(unit_id)
        unit = graph.units[unit_id]
        for required_id in sorted(unit.requires):
            required_state = state.get(required_id, 0)
            if required_state == 0:
                visit(required_id)
            elif required_state == 1:
                cycle_start = stack.index(required_id)
                cycle = stack[cycle_start:] + [required_id]
                raise _build_error(
                    "dependency-cycle",
                    _unit_source(unit),
                    "requires",
                    f"requires cycle: {' -> '.join(cycle)}",
                )
        stack.pop()
        state[unit_id] = 2

    for unit_id, _ in units:
        if state.get(unit_id, 0) == 0:
            visit(unit_id)


def _validate_generated_path_claims(
    units: tuple[tuple[str, CanonicalUnit], ...],
) -> None:
    claims: dict[tuple[str, str], str] = {}
    for unit_id, unit in units:
        public_name = unit.attributes.get("public_name")
        if not isinstance(public_name, str):
            continue
        claim = (unit.kind, public_name)
        previous_id = claims.get(claim)
        if previous_id is not None:
            raise _build_error(
                "duplicate-generated-path",
                _unit_source(unit),
                "public_name",
                f"{unit_id} duplicates public name '{public_name}' already claimed "
                f"by {previous_id}",
            )
        claims[claim] = unit_id


def validate_adapter_profiles(
    profiles: Mapping[str, AdapterProfile],
    *,
    logical_capabilities: frozenset[str],
    sources: Mapping[str, Path],
    frontier_contracts: Mapping[str, Mapping[str, object]],
    native_config_schemas: Mapping[str, Mapping[str, object]],
    authority_fingerprints: Mapping[str, str],
) -> None:
    clients = frozenset(profiles)
    missing_clients = sorted(_ADAPTER_CLIENTS - clients)
    extra_clients = sorted(clients - _ADAPTER_CLIENTS)
    if missing_clients or extra_clients:
        client = (missing_clients or extra_clients)[0]
        raise _build_error(
            "invalid-adapter",
            sources.get(client, Path("adapters") / client / "profile.json"),
            "client",
            "adapter profiles must contain exactly the supported clients",
        )

    root_claims: list[tuple[PurePosixPath, str, str, Path]] = []
    for client in sorted(profiles):
        profile = profiles[client]
        source = sources[client]
        if profile.client != client:
            raise _build_error(
                "invalid-adapter",
                source,
                "client",
                "adapter profile key must match its declared client",
            )
        if profile.default_agent_profile != "standard":
            raise _build_error(
                "invalid-agent-profile",
                source,
                "default_agent_profile",
                "the default agent profile must be standard",
            )
        if frozenset(profile.agent_profiles) != _AGENT_PROFILE_NAMES:
            raise _build_error(
                "invalid-agent-profile",
                source,
                "agent_profiles",
                "agent profiles must contain exactly standard and frontier",
            )
        for profile_name in sorted(profile.agent_profiles):
            tiers = profile.agent_profiles[profile_name]
            if frozenset(tiers) != _REASONING_TIERS:
                raise _build_error(
                    "invalid-agent-profile",
                    source,
                    f"agent_profiles.{profile_name}",
                    "agent profile must contain exactly fast, balanced, and deep",
                )
        standard = profile.agent_profiles["standard"]
        frontier = profile.agent_profiles["frontier"]
        contract = frontier_contracts[client]
        native_schema = native_config_schemas[client]
        effort_schema = native_schema["reasoning_effort"]
        capability_schema = native_schema["requires_native_capabilities"]
        if not isinstance(effort_schema, Mapping) or not isinstance(
            capability_schema,
            Mapping,
        ):
            raise _build_error(
                "invalid-native-config",
                source,
                "metadata.native_config_schema",
                "native configuration schema must contain object policies",
            )
        effort_presence = effort_schema["presence"]
        allowed_efforts = frozenset(effort_schema["allowed_values"])
        allowed_capability_locations = frozenset(
            capability_schema["allowed_locations"]
        )
        for profile_name in sorted(profile.agent_profiles):
            for tier in sorted(profile.agent_profiles[profile_name]):
                configuration = profile.agent_profiles[profile_name][tier]
                effort_present = "reasoning_effort" in configuration
                effort_field = (
                    f"agent_profiles.{profile_name}.{tier}.reasoning_effort"
                )
                if effort_presence == "required" and not effort_present:
                    raise _build_error(
                        "invalid-native-config",
                        source,
                        effort_field,
                        "client-native agent configuration requires reasoning effort",
                    )
                if effort_presence == "forbidden" and effort_present:
                    raise _build_error(
                        "invalid-native-config",
                        source,
                        effort_field,
                        "client-native agent configuration forbids reasoning effort",
                    )
                if (
                    effort_present
                    and configuration["reasoning_effort"] not in allowed_efforts
                ):
                    raise _build_error(
                        "invalid-native-config",
                        source,
                        effort_field,
                        "reasoning effort is not allowed by the client-native schema",
                    )
                if "requires_native_capabilities" in configuration:
                    location = f"{profile_name}.{tier}"
                    if location not in allowed_capability_locations:
                        raise _build_error(
                            "invalid-native-config",
                            source,
                            "agent_profiles."
                            f"{profile_name}.{tier}.requires_native_capabilities",
                            "native capability requirements are not allowed here",
                        )

        for tier in ("fast", "balanced"):
            if frontier[tier] != standard[tier]:
                raise _build_error(
                    "invalid-frontier",
                    source,
                    f"agent_profiles.frontier.{tier}",
                    "frontier may not change fast or balanced configuration",
                )

        if authority_fingerprints[client] != _ADAPTER_AUTHORITY_SHA256[client]:
            raise _build_error(
                "invalid-frontier",
                source,
                "metadata.frontier_deep_contract",
                "native frontier contract failed independent authority validation",
            )

        contract_effort = contract.get("reasoning_effort")
        contract_requirements = frozenset(
            contract.get("requires_native_capabilities", ())
        )
        if contract_effort is not None and contract_requirements:
            for profile_name in sorted(profile.agent_profiles):
                for tier in sorted(profile.agent_profiles[profile_name]):
                    configuration = profile.agent_profiles[profile_name][tier]
                    if configuration.get("reasoning_effort") != contract_effort:
                        continue
                    requirements = frozenset(
                        configuration.get("requires_native_capabilities", ())
                    )
                    if not contract_requirements.issubset(requirements):
                        raise _build_error(
                            "invalid-native-capability",
                            source,
                            f"agent_profiles.{profile_name}.{tier}",
                            "frontier-level effort requires the native frontier capability",
                        )

        if frozenset(profile.capabilities) != logical_capabilities:
            raise _build_error(
                "unknown-capability",
                source,
                "capabilities",
                "adapter capabilities must exactly match the canonical catalog",
            )
        expected_root_names = _OUTPUT_ROOT_NAMES[client]
        if frozenset(profile.output_roots) != expected_root_names:
            raise _build_error(
                "invalid-output-root",
                source,
                "output_roots",
                "adapter must declare exactly its product output roots",
            )
        for name in sorted(profile.output_roots):
            path = profile.output_roots[name]
            if path.is_absolute() or not path.parts or ".." in path.parts:
                raise _build_error(
                    "invalid-output-root",
                    source,
                    f"output_roots.{name}",
                    "output root must be a non-empty relative path without parent traversal",
                )
            root_claims.append((path, client, name, source))

    root_claims.sort(key=lambda claim: (claim[0].as_posix(), claim[1], claim[2]))
    for index, (path, _client, name, source) in enumerate(root_claims):
        for other_path, other_client, other_name, _ in root_claims[:index]:
            if (
                path == other_path
                or path in other_path.parents
                or other_path in path.parents
            ):
                raise _build_error(
                    "overlapping-output-root",
                    source,
                    f"output_roots.{name}",
                    f"output root overlaps {other_client}.{other_name}",
                )


def validate_graph(graph: CanonicalGraph) -> None:
    """Raise the first deterministic BuildError after sorting units by ID."""
    units = _sorted_units(graph)
    _validate_catalog_schemas(graph)
    _validate_unit_schemas(units)
    _validate_ids_and_kinds(units)
    _validate_capabilities(graph, units)
    _validate_references(graph, units)
    _validate_support(graph, units)
    _validate_workflow_contract(units)
    _validate_requires_cycles(graph, units)
    _validate_generated_path_claims(units)


__all__ = ["validate_adapter_profiles", "validate_graph"]
