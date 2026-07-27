#!/usr/bin/env bash
# create-project.sh — Create a disposable Kinglet client-probe project.
#
# Usage:
#   create-project.sh <destination> [executable]
#
# Arguments:
#   destination   Path where the project will be created. Must not already exist.
#   executable    (optional) Absolute path to the kinglet-client-probe binary.
#                 Defaults to the KINGLET_PROBE_EXECUTABLE env var if set, then
#                 to the linux-amd64 binary in probe-host/dist/ relative to this
#                 script (darwin-arm64 on Apple Silicon, linux-amd64 otherwise).
#
# Portable to macOS bash 3.2. Does not use associative arrays or GNU-only flags.
# Does not pipe into head (SIGPIPE combined with pipefail kills scripts on large inputs).
#
# Refuses non-Darwin/Linux hosts and a destination that already exists.
# Never copies a user profile or credentials.
set -euo pipefail

# ---------------------------------------------------------------------------
# Platform guard
# ---------------------------------------------------------------------------
host="$(uname -s)"
case "$host" in
  Darwin|Linux) ;;
  *)
    echo "create-project.sh: unsupported host '$host'; this script runs only on Darwin or Linux" >&2
    echo "create-project.sh: use create-project.ps1 on native Windows" >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Argument handling — validate BEFORE any shift
# ---------------------------------------------------------------------------
if [ "$#" -lt 1 ]; then
  echo "create-project.sh: missing required argument: destination" >&2
  echo "Usage: create-project.sh <destination> [executable]" >&2
  exit 1
fi

dest="$1"
shift

# Optional second positional argument: path to the executable.
# Falls back to env var, then to a default platform-relative path.
if [ "$#" -ge 1 ]; then
  probe_exe="$1"
  shift
elif [ -n "${KINGLET_PROBE_EXECUTABLE:-}" ]; then
  probe_exe="$KINGLET_PROBE_EXECUTABLE"
else
  # Derive a default from the script's own location.
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "$script_dir/../../../.." && pwd)"

  # Platform-specific default: darwin-arm64, darwin-amd64, linux-amd64, etc.
  goos="$(uname -s | tr '[:upper:]' '[:lower:]')"
  goarch="$(uname -m)"
  case "$goarch" in
    x86_64)  goarch="amd64" ;;
    aarch64|arm64) goarch="arm64" ;;
    *)       goarch="amd64" ;;
  esac

  probe_exe="$repo_root/spikes/platform/clients/probe-host/dist/$goos-$goarch/kinglet-client-probe"
fi

# ---------------------------------------------------------------------------
# Destination existence guard
# ---------------------------------------------------------------------------
if [ -e "$dest" ]; then
  echo "create-project.sh: destination already exists: $dest" >&2
  echo "create-project.sh: delete it first or choose a different path" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Executable existence check
# ---------------------------------------------------------------------------
if [ ! -f "$probe_exe" ]; then
  echo "create-project.sh: executable not found: $probe_exe" >&2
  echo "create-project.sh: build it with: bash spikes/platform/clients/probe-host/build.sh" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Shared directory where this script lives (for copying content files)
# ---------------------------------------------------------------------------
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Create the project tree
# ---------------------------------------------------------------------------
echo "create-project.sh: creating project at $dest"

mkdir -p "$dest/ProjectSettings"
mkdir -p "$dest/Assets"
mkdir -p "$dest/.kinglet-probe/receipts"
mkdir -p "$dest/.kinglet-probe/bin"

# ProjectSettings/ProjectVersion.txt — two lines matching Unity 6 format.
# The native exec reads only the m_EditorVersion: line (not the revision line).
cat > "$dest/ProjectSettings/ProjectVersion.txt" <<'EOF'
m_EditorVersion: 6000.3.11f1
m_EditorVersionWithRevision: 6000.3.11f1 (3f0e1d94bd20)
EOF

# .kinglet-probe/project-marker.txt — exact marker string, no trailing newline issues.
printf '%s' 'KINGLET_CLIENT_PROBE_PROJECT' > "$dest/.kinglet-probe/project-marker.txt"

# Assets/Protected.txt — target for the hook mutation-block probe.
printf '%s\n' 'PROTECTED' > "$dest/Assets/Protected.txt"

# ---------------------------------------------------------------------------
# Copy the native executable
# ---------------------------------------------------------------------------
cp "$probe_exe" "$dest/.kinglet-probe/bin/kinglet-client-probe"
chmod +x "$dest/.kinglet-probe/bin/kinglet-client-probe"

# ---------------------------------------------------------------------------
# Compute SHA-256 of the copied executable
# ---------------------------------------------------------------------------
bin_path="$dest/.kinglet-probe/bin/kinglet-client-probe"

# Portable SHA-256: prefer sha256sum (Linux), fall back to shasum -a 256 (macOS).
if command -v sha256sum > /dev/null 2>&1; then
  sha256_line="$(sha256sum "$bin_path")"
  # sha256sum prints "<hash>  <path>" — extract the first field without awk split issues
  sha256="$(printf '%s' "$sha256_line" | awk '{print $1}')"
else
  sha256_line="$(shasum -a 256 "$bin_path")"
  sha256="$(printf '%s' "$sha256_line" | awk '{print $1}')"
fi

# ---------------------------------------------------------------------------
# Write .kinglet-probe/expected.json
# ---------------------------------------------------------------------------
cat > "$dest/.kinglet-probe/expected.json" <<EOF
{
  "schema": "kinglet.client-probe.expected/v1",
  "executable": ".kinglet-probe/bin/kinglet-client-probe",
  "sha256": "$sha256"
}
EOF

# ---------------------------------------------------------------------------
# Install MCP config — replace executable token with the absolute path
# ---------------------------------------------------------------------------
abs_bin_path="$(cd "$(dirname "$bin_path")" && pwd)/$(basename "$bin_path")"

# Read the template, replace the token, write to destination.
# Uses sed with a literal token — no shell interpolation inside the pattern.
sed "s|__KINGLET_PROBE_EXECUTABLE__|$abs_bin_path|g" \
  "$script_dir/mcp.json" > "$dest/.kinglet-probe/mcp.json"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo "create-project.sh: project created"
echo "create-project.sh: executable sha256 = $sha256"
echo "create-project.sh: smoke-test: $dest/.kinglet-probe/bin/kinglet-client-probe exec --project $dest --output $dest/.kinglet-probe/receipts/workflow.json"
