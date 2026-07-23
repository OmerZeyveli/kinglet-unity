#!/usr/bin/env python3
"""Recompute the independent adapter metadata authority fingerprints."""

import hashlib
import json
from pathlib import Path


AUTHORITY_FIELDS = ("frontier_deep_contract", "native_config_schema")


def main() -> int:
    repository_root = Path(__file__).resolve().parents[1]
    fingerprints: dict[str, dict[str, str]] = {}
    for source in sorted((repository_root / "adapters").glob("*/profile.json")):
        profile = json.loads(source.read_text(encoding="utf-8"))
        metadata = profile["metadata"]
        fingerprints[source.parent.name] = {
            field: hashlib.sha256(
                json.dumps(
                    metadata[field],
                    sort_keys=True,
                    separators=(",", ":"),
                ).encode("utf-8")
            ).hexdigest()
            for field in AUTHORITY_FIELDS
        }
    print(json.dumps(fingerprints, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
