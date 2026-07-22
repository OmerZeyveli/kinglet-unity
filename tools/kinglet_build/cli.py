import argparse
from collections.abc import Mapping, Sequence
from pathlib import Path, PurePosixPath
import sys

from .errors import BuildError
from .loader import load_adapter_profiles, load_graph
from .model import AdapterProfile, CanonicalGraph
from .renderers import RenderedFile, renderer_registry
from .validator import validate_graph
from .writer import WriteResult, write_product


_EXIT_VALIDATION = 2
_EXIT_DRIFT = 3
_EXIT_USAGE = 64
_EXIT_IO = 74


class _UsageError(ValueError):
    pass


class _ArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise _UsageError(message)


def _parser() -> _ArgumentParser:
    parser = _ArgumentParser(
        prog="python3 -m tools.kinglet_build",
        description="Validate and render Kinglet for Unity products.",
        allow_abbrev=False,
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser(
        "validate",
        help="validate canonical sources and adapter profiles",
        allow_abbrev=False,
    )
    build = commands.add_parser(
        "build",
        help="render generated products",
        allow_abbrev=False,
    )
    targets = build.add_mutually_exclusive_group(required=True)
    targets.add_argument(
        "--all",
        action="store_const",
        const=("claude", "codex"),
        dest="clients",
        help="build every client product",
    )
    targets.add_argument(
        "--claude",
        action="store_const",
        const=("claude",),
        dest="clients",
        help="build Claude products",
    )
    targets.add_argument(
        "--codex",
        action="store_const",
        const=("codex",),
        dest="clients",
        help="build Codex products",
    )
    build.add_argument(
        "--check",
        action="store_true",
        help="compare generated products without writing",
    )
    return parser


def _load_validated(
    repository_root: Path,
) -> tuple[CanonicalGraph, Mapping[str, AdapterProfile]]:
    graph = load_graph(repository_root)
    profiles = load_adapter_profiles(repository_root)
    validate_graph(graph)
    return graph, profiles


def _rendered_file_summary(action: str, count: int) -> str:
    noun = "file" if count == 1 else "files"
    return f"{action} {count} rendered {noun}."


def _repository_relative(
    repository_root: Path,
    destination: Path,
    path: PurePosixPath,
) -> str:
    absolute = destination.joinpath(*path.parts)
    try:
        return absolute.relative_to(repository_root).as_posix()
    except ValueError:
        return absolute.as_posix()


def _build(
    repository_root: Path,
    graph: CanonicalGraph,
    profiles: Mapping[str, AdapterProfile],
    clients: tuple[str, ...],
    *,
    check: bool,
) -> int:
    registry = renderer_registry()
    rendered_by_client: dict[str, tuple[RenderedFile, ...]] = {}
    rendered_count = 0

    for client in sorted(clients):
        renderer = registry.get(client)
        if renderer is None:
            continue
        if renderer.client != client:
            raise ValueError(
                f"renderer registry key {client!r} does not match "
                f"client {renderer.client!r}"
            )
        rendered = renderer.render(graph, profiles[client])
        if not isinstance(rendered, tuple) or not all(
            isinstance(item, RenderedFile) for item in rendered
        ):
            raise TypeError(f"renderer for {client} must return RenderedFile tuples")
        rendered_by_client[client] = rendered
        rendered_count += len(rendered)

    drift: list[tuple[str, str]] = []
    for client in sorted(rendered_by_client):
        rendered = rendered_by_client[client]
        for root_name in sorted(profiles[client].output_roots):
            relative_root = profiles[client].output_roots[root_name]
            destination = repository_root.joinpath(*relative_root.parts)
            result = write_product(rendered, destination, check=check)
            if check:
                drift.extend(
                    (
                        _repository_relative(repository_root, destination, path),
                        "changed",
                    )
                    for path in result.changed
                )
                drift.extend(
                    (
                        _repository_relative(repository_root, destination, path),
                        "stale",
                    )
                    for path in result.stale
                )

    action = "Checked" if check else "Built"
    print(_rendered_file_summary(action, rendered_count))
    if drift:
        for path, state in sorted(drift):
            print(f"generated drift: {path} ({state})", file=sys.stderr)
        return _EXIT_DRIFT
    return 0


def main(
    argv: Sequence[str] | None = None,
    *,
    repository_root: Path | None = None,
) -> int:
    parser = _parser()
    try:
        arguments = parser.parse_args(argv)
    except _UsageError as error:
        print(f"usage error: {error}", file=sys.stderr)
        return _EXIT_USAGE
    except SystemExit as error:
        return int(error.code)

    root = (
        Path(repository_root)
        if repository_root is not None
        else Path(__file__).parents[2]
    )
    try:
        graph, profiles = _load_validated(root)
        if arguments.command == "validate":
            print(
                f"Validated {len(graph.units)} canonical units, "
                f"{len(graph.routes)} routes, {len(profiles)} adapters."
            )
            return 0
        return _build(
            root,
            graph,
            profiles,
            arguments.clients,
            check=arguments.check,
        )
    except BuildError as error:
        print(f"validation error: {error}", file=sys.stderr)
        return _EXIT_VALIDATION
    except OSError as error:
        print(f"I/O error: {error}", file=sys.stderr)
        return _EXIT_IO
    except (TypeError, ValueError) as error:
        print(f"build error: {error}", file=sys.stderr)
        return _EXIT_VALIDATION


__all__ = ["main"]
