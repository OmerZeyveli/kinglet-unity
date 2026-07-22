import json
import re
from collections.abc import Mapping
from pathlib import Path
from types import MappingProxyType
from typing import Any, cast

from .errors import BuildError
from .model import CanonicalGraph, CanonicalUnit, Provenance, SupportDeclaration


_COMMON_FIELDS = frozenset(
    {
        "schema_version",
        "id",
        "kind",
        "name",
        "summary",
        "capabilities",
        "requires",
        "support",
        "provenance",
    }
)

_DESCRIPTOR_TYPES = {
    "role": (
        "src/roles/*/role.json",
        "instructions.md",
        frozenset({"reasoning_tier", "evidence"}),
    ),
    "workflow": (
        "src/workflows/*/workflow.json",
        "instructions.md",
        frozenset(
            {
                "public_name",
                "stages",
                "roles",
                "rules",
                "knowledge",
                "inputs",
                "artifacts",
                "evidence",
                "failure_behavior",
                "mutation",
            }
        ),
    ),
    "knowledge": (
        "src/knowledge/*/knowledge.json",
        "SKILL.md",
        frozenset({"public_name", "category", "references", "scripts"}),
    ),
    "rule": (
        "src/rules/*/rule.json",
        "instructions.md",
        frozenset({"scope", "always_loaded"}),
    ),
    "hook": (
        "src/hooks/*/hook.json",
        "policy.sh",
        frozenset({"events", "priority", "decision", "needs_jq"}),
    ),
    "template": (
        "src/templates/*/template.json",
        "content.md",
        frozenset({"public_name", "output_name", "language"}),
    ),
}

_ID_PATTERN = re.compile(
    r"^(role|workflow|knowledge|rule|hook|template)\.[a-z0-9][a-z0-9-]*$"
)
_REQUIRED_CLIENTS = ("claude", "codex")
_SUPPORT_FIELDS = frozenset({"state", "reason", "owner", "test"})
_SUPPORT_STATES = frozenset({"supported", "unsupported", "exception"})
_PROVENANCE_FIELDS = frozenset(
    {"origin", "upstream_version", "upstream_path", "upstream_sha256"}
)


def _build_error(code: str, source: Path, field: str, detail: str) -> BuildError:
    return BuildError(code=code, source=source, field=field, detail=detail)


def _read_utf8(source: Path, *, field: str) -> str:
    if source.is_symlink():
        raise _build_error(
            "symlink-input",
            source,
            field,
            "canonical input must be a regular file, not a symbolic link",
        )
    if not source.is_file():
        raise _build_error(
            "missing-content",
            source,
            field,
            "required canonical input is missing",
        )
    try:
        return source.read_bytes().decode("utf-8")
    except UnicodeDecodeError as error:
        raise _build_error(
            "invalid-utf8",
            source,
            field,
            f"input is not valid UTF-8 at byte {error.start}",
        ) from error


def _load_json_object(source: Path) -> dict[str, object]:
    text = _read_utf8(source, field="$")
    try:
        value = json.loads(text)
    except json.JSONDecodeError as error:
        raise _build_error(
            "invalid-json",
            source,
            "$",
            f"{error.msg} at line {error.lineno}, column {error.colno}",
        ) from error
    if not isinstance(value, dict):
        raise _build_error(
            "invalid-json",
            source,
            "$",
            "top-level JSON value must be an object",
        )
    return cast(dict[str, object], value)


def _require_integer_schema(data: Mapping[str, object], source: Path) -> int:
    value = data.get("schema_version")
    if type(value) is not int:
        raise _build_error(
            "invalid-schema-version",
            source,
            "schema_version",
            "schema version must be an integer",
        )
    return value


def _require_string(data: Mapping[str, object], source: Path, field: str) -> str:
    value = data.get(field)
    if not isinstance(value, str):
        raise _build_error(
            "invalid-field",
            source,
            field,
            "field must be a string",
        )
    return value


def _require_string_tuple(
    data: Mapping[str, object], source: Path, field: str
) -> tuple[str, ...]:
    value = data.get(field)
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise _build_error(
            "invalid-field",
            source,
            field,
            "field must be an array of strings",
        )
    return tuple(value)


def _optional_string(
    data: Mapping[str, object],
    source: Path,
    field: str,
    *,
    error_field: str | None = None,
) -> str | None:
    value = data.get(field)
    if value is not None and not isinstance(value, str):
        raise _build_error(
            "invalid-field",
            source,
            error_field or field,
            "field must be a string or null",
        )
    return value


def _freeze(value: Any) -> object:
    if isinstance(value, dict):
        return MappingProxyType({key: _freeze(item) for key, item in value.items()})
    if isinstance(value, list):
        return tuple(_freeze(item) for item in value)
    return value


def _load_support(data: Mapping[str, object], source: Path) -> Mapping[str, SupportDeclaration]:
    raw_support = data.get("support")
    if not isinstance(raw_support, dict):
        raise _build_error(
            "invalid-support",
            source,
            "support",
            "support must be an object",
        )

    support = cast(dict[str, object], raw_support)
    for client in _REQUIRED_CLIENTS:
        if client not in support:
            raise _build_error(
                "missing-support",
                source,
                f"support.{client}",
                f"support declaration for {client} is required",
            )

    declarations: dict[str, SupportDeclaration] = {}
    for client in sorted(support):
        raw_declaration = support[client]
        if not isinstance(raw_declaration, dict):
            raise _build_error(
                "invalid-support",
                source,
                f"support.{client}",
                "support declaration must be an object",
            )
        declaration = cast(dict[str, object], raw_declaration)
        unknown_fields = sorted(set(declaration) - _SUPPORT_FIELDS)
        if unknown_fields:
            field = f"support.{client}.{unknown_fields[0]}"
            raise _build_error(
                "unknown-field",
                source,
                field,
                "field is not allowed in a support declaration",
            )
        state = declaration.get("state")
        if state not in _SUPPORT_STATES:
            raise _build_error(
                "invalid-support",
                source,
                f"support.{client}.state",
                "support state must be supported, unsupported, or exception",
            )
        declarations[client] = SupportDeclaration(
            state=cast(Any, state),
            reason=_optional_string(
                declaration,
                source,
                "reason",
                error_field=f"support.{client}.reason",
            )
            if "reason" in declaration
            else None,
            owner=_optional_string(
                declaration,
                source,
                "owner",
                error_field=f"support.{client}.owner",
            )
            if "owner" in declaration
            else None,
            test=_optional_string(
                declaration,
                source,
                "test",
                error_field=f"support.{client}.test",
            )
            if "test" in declaration
            else None,
        )
    return MappingProxyType(declarations)


def _load_provenance(data: Mapping[str, object], source: Path) -> Provenance:
    raw_provenance = data.get("provenance")
    if not isinstance(raw_provenance, dict):
        raise _build_error(
            "invalid-field",
            source,
            "provenance",
            "provenance must be an object",
        )
    provenance = cast(dict[str, object], raw_provenance)
    unknown_fields = sorted(set(provenance) - _PROVENANCE_FIELDS)
    if unknown_fields:
        field = f"provenance.{unknown_fields[0]}"
        raise _build_error(
            "unknown-field",
            source,
            field,
            "field is not allowed in provenance",
        )
    return Provenance(
        origin=_require_string(provenance, source, "origin"),
        upstream_version=_optional_string(provenance, source, "upstream_version"),
        upstream_path=_optional_string(provenance, source, "upstream_path"),
        upstream_sha256=_optional_string(provenance, source, "upstream_sha256"),
    )


def _load_unit(
    source: Path,
    expected_kind: str,
    body_name: str,
    kind_fields: frozenset[str],
) -> CanonicalUnit:
    data = _load_json_object(source)
    unknown_fields = sorted(set(data) - _COMMON_FIELDS - kind_fields)
    if unknown_fields:
        field = unknown_fields[0]
        raise _build_error(
            "unknown-field",
            source,
            field,
            f"field is not allowed for {expected_kind} descriptors",
        )
    missing_fields = sorted(_COMMON_FIELDS - set(data))
    if missing_fields:
        field = missing_fields[0]
        raise _build_error(
            "missing-field",
            source,
            field,
            "required descriptor field is missing",
        )

    schema_version = _require_integer_schema(data, source)
    unit_id = _require_string(data, source, "id")
    identifier = _ID_PATTERN.fullmatch(unit_id)
    if identifier is None or identifier.group(1) != expected_kind:
        raise _build_error(
            "invalid-id",
            source,
            "id",
            "ID must match its descriptor kind and canonical ID syntax",
        )
    kind = _require_string(data, source, "kind")
    if kind != expected_kind:
        raise _build_error(
            "invalid-kind",
            source,
            "kind",
            f"descriptor kind must be {expected_kind}",
        )

    content_path = source.parent / body_name
    _read_utf8(content_path, field="content")

    attributes = {
        field: _freeze(data[field]) for field in sorted(kind_fields) if field in data
    }
    return CanonicalUnit(
        schema_version=schema_version,
        id=unit_id,
        kind=kind,
        name=_require_string(data, source, "name"),
        summary=_require_string(data, source, "summary"),
        capabilities=_require_string_tuple(data, source, "capabilities"),
        requires=_require_string_tuple(data, source, "requires"),
        support=_load_support(data, source),
        provenance=_load_provenance(data, source),
        content_path=content_path,
        attributes=MappingProxyType(attributes),
    )


def _load_capabilities(root: Path) -> frozenset[str]:
    source = root / "src" / "catalog" / "capabilities.json"
    data = _load_json_object(source)
    _require_integer_schema(data, source)
    capabilities = data.get("capabilities")
    if not isinstance(capabilities, list) or not all(
        isinstance(capability, str) for capability in capabilities
    ):
        raise _build_error(
            "invalid-field",
            source,
            "capabilities",
            "capabilities must be an array of strings",
        )
    return frozenset(capabilities)


def _load_support_policy(root: Path) -> Mapping[str, object]:
    source = root / "src" / "catalog" / "support-policy.json"
    data = _load_json_object(source)
    _require_integer_schema(data, source)
    return cast(Mapping[str, object], _freeze(data))


def _load_routes(root: Path) -> tuple[Mapping[str, object], ...]:
    source = root / "src" / "catalog" / "routing.json"
    data = _load_json_object(source)
    _require_integer_schema(data, source)
    raw_routes = data.get("routes")
    if not isinstance(raw_routes, list) or not all(
        isinstance(route, dict) for route in raw_routes
    ):
        raise _build_error(
            "invalid-field",
            source,
            "routes",
            "routes must be an array of objects",
        )
    return tuple(cast(Mapping[str, object], _freeze(route)) for route in raw_routes)


def load_graph(repository_root: Path) -> CanonicalGraph:
    root = Path(repository_root)
    capabilities = _load_capabilities(root)
    support_policy = _load_support_policy(root)
    routes = _load_routes(root)

    descriptor_paths: list[tuple[Path, str, str, frozenset[str]]] = []
    for kind, (pattern, body_name, kind_fields) in _DESCRIPTOR_TYPES.items():
        descriptor_paths.extend(
            (source, kind, body_name, kind_fields) for source in root.glob(pattern)
        )
    descriptor_paths.sort(key=lambda descriptor: descriptor[0].as_posix())

    units: dict[str, CanonicalUnit] = {}
    sources: dict[str, Path] = {}
    for source, kind, body_name, kind_fields in descriptor_paths:
        unit = _load_unit(source, kind, body_name, kind_fields)
        if unit.id in units:
            raise _build_error(
                "duplicate-id",
                source,
                "id",
                f"{unit.id} was already declared by {sources[unit.id]}",
            )
        units[unit.id] = unit
        sources[unit.id] = source

    return CanonicalGraph(
        root=root,
        capabilities=capabilities,
        support_policy=support_policy,
        routes=routes,
        units=MappingProxyType(units),
    )


__all__ = ["load_graph"]
