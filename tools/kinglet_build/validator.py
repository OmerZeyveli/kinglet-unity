import json
import re
from pathlib import Path

from .errors import BuildError
from .model import CanonicalGraph, CanonicalUnit


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


__all__ = ["validate_graph"]
