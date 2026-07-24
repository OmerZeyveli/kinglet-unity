#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
python3 -m unittest discover -s tests/kinglet_spike -t . -v
echo "PASS: Kinglet spike harness unit tests"
