import hashlib
import json
import re
from collections.abc import Mapping
from pathlib import Path, PurePosixPath
from types import MappingProxyType
from typing import Any, cast

from .errors import BuildError
from .model import (
    AdapterProfile,
    CanonicalGraph,
    CanonicalUnit,
    Provenance,
    SupportDeclaration,
)
from .validator import validate_adapter_profiles


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
_ADAPTER_FIELDS = frozenset(
    {
        "schema_version",
        "client",
        "default_agent_profile",
        "agent_profiles",
        "capabilities",
        "output_roots",
        "metadata",
    }
)
_AGENT_CONFIGURATION_FIELDS = frozenset(
    {"model", "reasoning_effort", "requires_native_capabilities"}
)
_METADATA_FIELDS = frozenset(
    {
        "frontier_deep_contract",
        "native_config_schema",
        "evaluation_candidates",
    }
)
_EVALUATION_CANDIDATE_FIELDS = frozenset(
    {"role", "model", "reasoning_effort", "shipping", "adoption_gate"}
)
_NATIVE_CONFIG_SCHEMA_FIELDS = frozenset(
    {"reasoning_effort", "requires_native_capabilities"}
)
_REASONING_EFFORT_SCHEMA_FIELDS = frozenset(
    {"presence", "allowed_values"}
)
_NATIVE_CAPABILITY_SCHEMA_FIELDS = frozenset({"allowed_locations"})
_REASONING_TIERS = ("fast", "balanced", "deep")
_WORKFLOW_STAGES = (
    "investigate",
    "clarify",
    "design",
    "plan",
    "implement",
    "verify",
    "report",
)
_HOOK_DECISIONS = ("allow", "warn", "block", "pass")
_TEMPLATE_LANGUAGES = ("markdown", "csharp", "json")


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


def _require_non_empty_string(
    data: Mapping[str, object],
    source: Path,
    field: str,
) -> str:
    value = data.get(field)
    if not isinstance(value, str) or not value.strip():
        raise _build_error(
            "invalid-field",
            source,
            field,
            "field must be a non-empty string",
        )
    return value


def _require_unique_string_tuple(
    data: Mapping[str, object],
    source: Path,
    field: str,
    *,
    required_item: bool,
) -> tuple[str, ...]:
    value = data.get(field)
    if (
        not isinstance(value, list)
        or not all(isinstance(item, str) and item.strip() for item in value)
        or len(set(value)) != len(value)
        or (required_item and not value)
    ):
        requirement = "a non-empty array" if required_item else "an array"
        raise _build_error(
            "invalid-field",
            source,
            field,
            f"field must be {requirement} of unique non-empty strings",
        )
    return tuple(value)


def _require_enum(
    data: Mapping[str, object],
    source: Path,
    field: str,
    allowed_values: tuple[str, ...],
) -> str:
    value = data.get(field)
    if not isinstance(value, str) or not value or value not in allowed_values:
        raise _build_error(
            "invalid-field",
            source,
            field,
            f"field must be one of: {', '.join(allowed_values)}",
        )
    return value


def _require_boolean(
    data: Mapping[str, object],
    source: Path,
    field: str,
) -> bool:
    value = data.get(field)
    if type(value) is not bool:
        raise _build_error(
            "invalid-field",
            source,
            field,
            "field must be a boolean",
        )
    return value


def _require_integer(
    data: Mapping[str, object],
    source: Path,
    field: str,
) -> int:
    value = data.get(field)
    if type(value) is not int:
        raise _build_error(
            "invalid-field",
            source,
            field,
            "field must be an integer",
        )
    return value


def _load_kind_attributes(
    data: Mapping[str, object],
    source: Path,
    kind: str,
    fields: frozenset[str],
) -> Mapping[str, object]:
    missing_fields = sorted(fields - set(data))
    if missing_fields:
        raise _build_error(
            "missing-field",
            source,
            missing_fields[0],
            "required kind-specific field is missing",
        )

    attributes: dict[str, object]
    if kind == "role":
        attributes = {
            "reasoning_tier": _require_enum(
                data,
                source,
                "reasoning_tier",
                _REASONING_TIERS,
            ),
            "evidence": _require_unique_string_tuple(
                data,
                source,
                "evidence",
                required_item=True,
            ),
        }
    elif kind == "workflow":
        attributes = {
            "public_name": _require_non_empty_string(data, source, "public_name"),
            "stages": _require_unique_string_tuple(
                data,
                source,
                "stages",
                required_item=True,
            ),
            "roles": _require_unique_string_tuple(
                data,
                source,
                "roles",
                required_item=True,
            ),
            "rules": _require_unique_string_tuple(
                data,
                source,
                "rules",
                required_item=False,
            ),
            "knowledge": _require_unique_string_tuple(
                data,
                source,
                "knowledge",
                required_item=False,
            ),
            "inputs": _require_unique_string_tuple(
                data,
                source,
                "inputs",
                required_item=True,
            ),
            "artifacts": _require_unique_string_tuple(
                data,
                source,
                "artifacts",
                required_item=True,
            ),
            "evidence": _require_unique_string_tuple(
                data,
                source,
                "evidence",
                required_item=True,
            ),
            "failure_behavior": _require_non_empty_string(
                data,
                source,
                "failure_behavior",
            ),
            "mutation": _require_boolean(data, source, "mutation"),
        }
        invalid_stages = [
            stage for stage in attributes["stages"] if stage not in _WORKFLOW_STAGES
        ]
        if invalid_stages:
            raise _build_error(
                "invalid-field",
                source,
                "stages",
                f"field must contain only: {', '.join(_WORKFLOW_STAGES)}",
            )
    elif kind == "knowledge":
        attributes = {
            "public_name": _require_non_empty_string(data, source, "public_name"),
            "category": _require_non_empty_string(data, source, "category"),
            "references": _require_unique_string_tuple(
                data,
                source,
                "references",
                required_item=False,
            ),
            "scripts": _require_unique_string_tuple(
                data,
                source,
                "scripts",
                required_item=False,
            ),
        }
    elif kind == "rule":
        attributes = {
            "scope": _require_non_empty_string(data, source, "scope"),
            "always_loaded": _require_boolean(data, source, "always_loaded"),
        }
    elif kind == "hook":
        attributes = {
            "events": _require_unique_string_tuple(
                data,
                source,
                "events",
                required_item=True,
            ),
            "priority": _require_integer(data, source, "priority"),
            "decision": _require_enum(
                data,
                source,
                "decision",
                _HOOK_DECISIONS,
            ),
            "needs_jq": _require_boolean(data, source, "needs_jq"),
        }
    elif kind == "template":
        attributes = {
            "public_name": _require_non_empty_string(data, source, "public_name"),
            "output_name": _require_non_empty_string(data, source, "output_name"),
            "language": _require_enum(
                data,
                source,
                "language",
                _TEMPLATE_LANGUAGES,
            ),
        }
    else:
        raise AssertionError(f"unsupported descriptor kind: {kind}")
    return MappingProxyType(
        {field: attributes[field] for field in sorted(attributes)}
    )


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
        if not isinstance(state, str) or state not in _SUPPORT_STATES:
            raise _build_error(
                "invalid-support",
                source,
                f"support.{client}.state",
                "support state must be supported, unsupported, or exception",
            )
        reason = (
            _optional_string(
                declaration,
                source,
                "reason",
                error_field=f"support.{client}.reason",
            )
            if "reason" in declaration
            else None
        )
        owner = (
            _optional_string(
                declaration,
                source,
                "owner",
                error_field=f"support.{client}.owner",
            )
            if "owner" in declaration
            else None
        )
        test = (
            _optional_string(
                declaration,
                source,
                "test",
                error_field=f"support.{client}.test",
            )
            if "test" in declaration
            else None
        )
        if state == "exception":
            for field, value in (("reason", reason), ("owner", owner), ("test", test)):
                if value is None:
                    raise _build_error(
                        "invalid-support",
                        source,
                        f"support.{client}.{field}",
                        f"exception support requires a non-null {field}",
                    )
        declarations[client] = SupportDeclaration(
            state=cast(Any, state),
            reason=reason,
            owner=owner,
            test=test,
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

    attributes = _load_kind_attributes(
        data,
        source,
        expected_kind,
        kind_fields,
    )
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
        attributes=attributes,
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


def _reject_unknown_fields(
    data: Mapping[str, object],
    allowed_fields: frozenset[str],
    source: Path,
    field_prefix: str = "",
) -> None:
    unknown_fields = sorted(set(data) - allowed_fields)
    if not unknown_fields:
        return
    field = (
        f"{field_prefix}.{unknown_fields[0]}"
        if field_prefix
        else unknown_fields[0]
    )
    raise _build_error(
        "unknown-field",
        source,
        field,
        "field is not allowed in an adapter profile",
    )


def _load_agent_configuration(
    value: object,
    source: Path,
    field: str,
) -> Mapping[str, object]:
    if not isinstance(value, dict):
        raise _build_error(
            "invalid-agent-profile",
            source,
            field,
            "native agent configuration must be an object",
        )
    configuration = cast(dict[str, object], value)
    _reject_unknown_fields(
        configuration,
        _AGENT_CONFIGURATION_FIELDS,
        source,
        field,
    )
    model = configuration.get("model")
    if not isinstance(model, str) or not model:
        raise _build_error(
            "invalid-agent-profile",
            source,
            f"{field}.model",
            "native agent configuration requires a non-empty model",
        )
    effort = configuration.get("reasoning_effort")
    if effort is not None and (not isinstance(effort, str) or not effort):
        raise _build_error(
            "invalid-agent-profile",
            source,
            f"{field}.reasoning_effort",
            "reasoning effort must be a non-empty string",
        )
    requirements = configuration.get("requires_native_capabilities")
    if requirements is not None and (
        not isinstance(requirements, list)
        or not all(isinstance(item, str) and item for item in requirements)
        or len(set(requirements)) != len(requirements)
    ):
        raise _build_error(
            "invalid-native-capability",
            source,
            f"{field}.requires_native_capabilities",
            "native capability requirements must be unique non-empty strings",
        )
    return cast(Mapping[str, object], _freeze(configuration))


def _load_agent_profiles(
    value: object,
    source: Path,
) -> Mapping[str, Mapping[str, Mapping[str, object]]]:
    if not isinstance(value, dict):
        raise _build_error(
            "invalid-agent-profile",
            source,
            "agent_profiles",
            "agent profiles must be an object",
        )
    loaded: dict[str, Mapping[str, Mapping[str, object]]] = {}
    for profile_name, raw_tiers in sorted(value.items()):
        if not isinstance(raw_tiers, dict):
            raise _build_error(
                "invalid-agent-profile",
                source,
                f"agent_profiles.{profile_name}",
                "agent profile must map reasoning tiers to native configuration",
            )
        tiers: dict[str, Mapping[str, object]] = {}
        for tier, raw_configuration in sorted(raw_tiers.items()):
            tiers[tier] = _load_agent_configuration(
                raw_configuration,
                source,
                f"agent_profiles.{profile_name}.{tier}",
            )
        loaded[profile_name] = MappingProxyType(tiers)
    return MappingProxyType(loaded)


def _load_capability_mapping(
    value: object,
    source: Path,
) -> Mapping[str, tuple[str, ...]]:
    if not isinstance(value, dict):
        raise _build_error(
            "invalid-field",
            source,
            "capabilities",
            "capability mapping must be an object",
        )
    capabilities: dict[str, tuple[str, ...]] = {}
    for capability, raw_surfaces in sorted(value.items()):
        if (
            not isinstance(raw_surfaces, list)
            or not raw_surfaces
            or not all(isinstance(surface, str) and surface for surface in raw_surfaces)
            or len(set(raw_surfaces)) != len(raw_surfaces)
        ):
            raise _build_error(
                "invalid-field",
                source,
                f"capabilities.{capability}",
                "native capability surfaces must be unique non-empty strings",
            )
        capabilities[capability] = tuple(raw_surfaces)
    return MappingProxyType(capabilities)


def _load_output_roots(
    value: object,
    source: Path,
) -> Mapping[str, PurePosixPath]:
    if not isinstance(value, dict):
        raise _build_error(
            "invalid-output-root",
            source,
            "output_roots",
            "output roots must be an object",
        )
    output_roots: dict[str, PurePosixPath] = {}
    for name, raw_path in sorted(value.items()):
        if not isinstance(raw_path, str) or not raw_path:
            raise _build_error(
                "invalid-output-root",
                source,
                f"output_roots.{name}",
                "output root must be a non-empty POSIX path string",
            )
        output_roots[name] = PurePosixPath(raw_path)
    return MappingProxyType(output_roots)


def _load_native_config_schema(
    value: object,
    source: Path,
) -> Mapping[str, object]:
    if not isinstance(value, dict):
        raise _build_error(
            "invalid-native-config",
            source,
            "metadata.native_config_schema",
            "native configuration schema must be an object",
        )
    schema = cast(dict[str, object], value)
    _reject_unknown_fields(
        schema,
        _NATIVE_CONFIG_SCHEMA_FIELDS,
        source,
        "metadata.native_config_schema",
    )
    if set(schema) != _NATIVE_CONFIG_SCHEMA_FIELDS:
        missing = sorted(_NATIVE_CONFIG_SCHEMA_FIELDS - set(schema))[0]
        raise _build_error(
            "missing-field",
            source,
            f"metadata.native_config_schema.{missing}",
            "native configuration schema field is required",
        )

    raw_effort = schema["reasoning_effort"]
    if not isinstance(raw_effort, dict):
        raise _build_error(
            "invalid-native-config",
            source,
            "metadata.native_config_schema.reasoning_effort",
            "reasoning effort schema must be an object",
        )
    effort = cast(dict[str, object], raw_effort)
    _reject_unknown_fields(
        effort,
        _REASONING_EFFORT_SCHEMA_FIELDS,
        source,
        "metadata.native_config_schema.reasoning_effort",
    )
    if set(effort) != _REASONING_EFFORT_SCHEMA_FIELDS:
        missing = sorted(_REASONING_EFFORT_SCHEMA_FIELDS - set(effort))[0]
        raise _build_error(
            "missing-field",
            source,
            f"metadata.native_config_schema.reasoning_effort.{missing}",
            "reasoning effort schema field is required",
        )
    presence = effort["presence"]
    allowed_values = effort["allowed_values"]
    if presence not in ("required", "forbidden"):
        raise _build_error(
            "invalid-native-config",
            source,
            "metadata.native_config_schema.reasoning_effort.presence",
            "reasoning effort presence must be required or forbidden",
        )
    if (
        not isinstance(allowed_values, list)
        or not all(isinstance(item, str) and item for item in allowed_values)
        or len(set(allowed_values)) != len(allowed_values)
    ):
        raise _build_error(
            "invalid-native-config",
            source,
            "metadata.native_config_schema.reasoning_effort.allowed_values",
            "allowed reasoning efforts must be unique non-empty strings",
        )
    if (presence == "required") != bool(allowed_values):
        raise _build_error(
            "invalid-native-config",
            source,
            "metadata.native_config_schema.reasoning_effort.allowed_values",
            "required effort needs allowed values and forbidden effort allows none",
        )

    raw_capabilities = schema["requires_native_capabilities"]
    if not isinstance(raw_capabilities, dict):
        raise _build_error(
            "invalid-native-config",
            source,
            "metadata.native_config_schema.requires_native_capabilities",
            "native capability schema must be an object",
        )
    capabilities = cast(dict[str, object], raw_capabilities)
    _reject_unknown_fields(
        capabilities,
        _NATIVE_CAPABILITY_SCHEMA_FIELDS,
        source,
        "metadata.native_config_schema.requires_native_capabilities",
    )
    if set(capabilities) != _NATIVE_CAPABILITY_SCHEMA_FIELDS:
        raise _build_error(
            "missing-field",
            source,
            "metadata.native_config_schema.requires_native_capabilities.allowed_locations",
            "native capability allowed locations are required",
        )
    allowed_locations = capabilities["allowed_locations"]
    if (
        not isinstance(allowed_locations, list)
        or not allowed_locations
        or not all(isinstance(item, str) and item for item in allowed_locations)
        or len(set(allowed_locations)) != len(allowed_locations)
    ):
        raise _build_error(
            "invalid-native-config",
            source,
            "metadata.native_config_schema.requires_native_capabilities.allowed_locations",
            "native capability locations must be unique non-empty strings",
        )
    return cast(Mapping[str, object], _freeze(schema))


def _load_adapter_metadata(
    value: object,
    source: Path,
) -> tuple[
    Mapping[str, object],
    Mapping[str, object],
    Mapping[str, str],
]:
    if not isinstance(value, dict):
        raise _build_error(
            "invalid-field",
            source,
            "metadata",
            "adapter metadata must be an object",
        )
    metadata = cast(dict[str, object], value)
    _reject_unknown_fields(metadata, _METADATA_FIELDS, source, "metadata")
    if set(metadata) != _METADATA_FIELDS:
        missing = sorted(_METADATA_FIELDS - set(metadata))[0]
        raise _build_error(
            "missing-field",
            source,
            f"metadata.{missing}",
            "required adapter metadata is missing",
        )
    contract = _load_agent_configuration(
        metadata["frontier_deep_contract"],
        source,
        "metadata.frontier_deep_contract",
    )
    native_schema = _load_native_config_schema(
        metadata["native_config_schema"],
        source,
    )
    raw_candidates = metadata["evaluation_candidates"]
    if not isinstance(raw_candidates, list):
        raise _build_error(
            "invalid-field",
            source,
            "metadata.evaluation_candidates",
            "evaluation candidates must be an array",
        )
    for index, value in enumerate(raw_candidates):
        field = f"metadata.evaluation_candidates.{index}"
        if not isinstance(value, dict):
            raise _build_error(
                "invalid-field",
                source,
                field,
                "evaluation candidate must be an object",
            )
        candidate = cast(dict[str, object], value)
        _reject_unknown_fields(
            candidate,
            _EVALUATION_CANDIDATE_FIELDS,
            source,
            field,
        )
        if set(candidate) != _EVALUATION_CANDIDATE_FIELDS:
            missing = sorted(_EVALUATION_CANDIDATE_FIELDS - set(candidate))[0]
            raise _build_error(
                "missing-field",
                source,
                f"{field}.{missing}",
                "evaluation candidate field is required",
            )
        for name in ("role", "model", "reasoning_effort", "adoption_gate"):
            if not isinstance(candidate[name], str) or not candidate[name]:
                raise _build_error(
                    "invalid-field",
                    source,
                    f"{field}.{name}",
                    "evaluation candidate value must be a non-empty string",
                )
        if candidate["shipping"] is not False:
            raise _build_error(
                "invalid-field",
                source,
                f"{field}.shipping",
                "evaluation candidates must be explicitly non-shipping",
            )
    fingerprints = {
        field: hashlib.sha256(
            json.dumps(
                metadata[field],
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
        ).hexdigest()
        for field in ("frontier_deep_contract", "native_config_schema")
    }
    return contract, native_schema, MappingProxyType(fingerprints)


def _load_adapter_profile(
    source: Path,
    expected_client: str,
) -> tuple[
    AdapterProfile,
    Mapping[str, object],
    Mapping[str, object],
    Mapping[str, str],
]:
    data = _load_json_object(source)
    _reject_unknown_fields(data, _ADAPTER_FIELDS, source)
    missing_fields = sorted(_ADAPTER_FIELDS - set(data))
    if missing_fields:
        raise _build_error(
            "missing-field",
            source,
            missing_fields[0],
            "required adapter profile field is missing",
        )
    schema_version = _require_integer_schema(data, source)
    if schema_version != 1:
        raise _build_error(
            "invalid-schema-version",
            source,
            "schema_version",
            "adapter profile schema version must be 1",
        )
    client = _require_string(data, source, "client")
    if client != expected_client:
        raise _build_error(
            "invalid-adapter",
            source,
            "client",
            f"adapter directory {expected_client} must declare the same client",
        )
    agent_profiles = _load_agent_profiles(data["agent_profiles"], source)
    contract, native_schema, fingerprint = _load_adapter_metadata(
        data["metadata"],
        source,
    )
    frontier = agent_profiles.get("frontier")
    frontier_deep = frontier.get("deep") if frontier is not None else None
    if frontier_deep != contract:
        raise _build_error(
            "invalid-frontier",
            source,
            "agent_profiles.frontier.deep",
            "frontier deep configuration must match its native contract",
        )
    return (
        AdapterProfile(
            client=client,
            default_agent_profile=_require_string(
                data,
                source,
                "default_agent_profile",
            ),
            agent_profiles=agent_profiles,
            capabilities=_load_capability_mapping(data["capabilities"], source),
            output_roots=_load_output_roots(data["output_roots"], source),
        ),
        contract,
        native_schema,
        fingerprint,
    )


def load_adapter_profiles(repository_root: Path) -> Mapping[str, AdapterProfile]:
    root = Path(repository_root)
    adapters_root = root / "adapters"
    required_clients = frozenset(_REQUIRED_CLIENTS)
    profile_sources = {
        source.parent.name: source
        for source in adapters_root.glob("*/profile.json")
    }
    clients = frozenset(profile_sources)
    missing_clients = sorted(required_clients - clients)
    if missing_clients:
        client = missing_clients[0]
        raise _build_error(
            "missing-adapter",
            adapters_root / client / "profile.json",
            "client",
            f"required adapter profile for {client} is missing",
        )
    extra_clients = sorted(clients - required_clients)
    if extra_clients:
        client = extra_clients[0]
        raise _build_error(
            "extra-adapter",
            profile_sources[client],
            "client",
            f"adapter profile for unsupported client {client} is not allowed",
        )

    profiles: dict[str, AdapterProfile] = {}
    contracts: dict[str, Mapping[str, object]] = {}
    native_schemas: dict[str, Mapping[str, object]] = {}
    authority_fingerprints: dict[str, Mapping[str, str]] = {}
    sources: dict[str, Path] = {}
    for client in sorted(required_clients):
        source = profile_sources[client]
        profile, contract, native_schema, fingerprint = _load_adapter_profile(
            source,
            client,
        )
        profiles[client] = profile
        contracts[client] = contract
        native_schemas[client] = native_schema
        authority_fingerprints[client] = fingerprint
        sources[client] = source

    validate_adapter_profiles(
        profiles,
        logical_capabilities=_load_capabilities(root),
        sources=sources,
        frontier_contracts=contracts,
        native_config_schemas=native_schemas,
        authority_fingerprints=authority_fingerprints,
    )
    return MappingProxyType(profiles)


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


__all__ = ["load_adapter_profiles", "load_graph"]
