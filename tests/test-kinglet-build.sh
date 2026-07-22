#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$REPOSITORY_ROOT"
python3 -m unittest discover -s tests/kinglet -p 'test_*.py' -v
