#!/usr/bin/env bash
# Build the native kinglet-client-probe for THIS host only.
#
# Refuses non-Darwin/Linux hosts. Never cross-builds: the artifact reflects the
# current native GOOS/GOARCH so what is reported as executed is what actually
# ran here. Portable to macOS bash 3.2 (no `declare -A`, no `grep -oP`).
set -euo pipefail

host="$(uname -s)"
case "$host" in
  Darwin|Linux) ;;
  *)
    echo "build.sh: unsupported host '$host'; this script builds only on Darwin or Linux" >&2
    echo "build.sh: use build.ps1 on native Windows" >&2
    exit 1
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pin to the host's own platform; do not honor an inherited cross-target.
goos="$(go env GOHOSTOS)"
goarch="$(go env GOHOSTARCH)"

out_dir="$script_dir/dist/$goos-$goarch"
out_bin="$out_dir/kinglet-client-probe"

mkdir -p "$out_dir"

echo "build.sh: building $goos/$goarch -> $out_bin"
(
  cd "$script_dir"
  GOOS="$goos" GOARCH="$goarch" GOTOOLCHAIN=local \
    go build -trimpath -o "$out_bin" .
)

echo "build.sh: done"
