#!/usr/bin/env bash
# run-host.sh — native Linux (ubuntu-noble family) host runner for the 0R runtime bake-off.
#
# For each of the four runtime candidates (python, go, rust, dotnet) it:
#   1. builds the candidate at its pinned toolchain (toolchains on PATH),
#   2. copies ONLY the distributable into a clean exec directory,
#   3. runs the packaged artifact with the toolchain directories REMOVED from the
#      child PATH (proving the artifact is self-contained),
#   4. runs the black-box conformance harness
#      (python3 -m tools.kinglet_spike.runtime_contract) and requires 18/18,
#   5. captures the candidate's own result.json (the raw host-probe result),
#   6. calls measure.sh for cold-start / peak-RSS / artifact-size samples,
#   7. assembles a kinglet.spike.evidence/v1 record, and
#   8. publishes it via python3 -m tools.kinglet_spike publish.
#
# Host acceptance (Option A, user-approved 2026-07-27): Pop!_OS 24.04 is accepted as
# the ubuntu-24.04-noble family. The runner still REFUSES WSL and any non-ubuntu/non-noble host.
#
# --dry-run prints the planned commands and mutates nothing outside .kinglet/local/.
#
# Shell conventions (repo CLAUDE.md): bash, set -euo pipefail, no bash-4 associative
# arrays (macOS bash 3.2), no GNU-only grep perl-regex, and no early-exit pipe under
# set -e (SIGPIPE 141 becomes a failure). See tests for the enforced literals.
set -euo pipefail

# --- Resolve repo root (this script lives at spikes/platform/runtime/) ---
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
cd "$REPO_ROOT"

DRY_RUN=0
if [ "$#" -ge 1 ]; then
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    *)
      echo "run-host.sh: unknown argument: $1" >&2
      echo "usage: run-host.sh [--dry-run]" >&2
      exit 2
      ;;
  esac
fi

log() { printf '[run-host] %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# 1. Host gate — refuse WSL, accept only ubuntu/noble family
# ---------------------------------------------------------------------------

# Refuse WSL: the WSL_DISTRO_NAME env var, or a kernel release naming microsoft/WSL.
if [ -n "${WSL_DISTRO_NAME:-}" ]; then
  echo "run-host.sh: refusing to run under WSL (WSL_DISTRO_NAME=$WSL_DISTRO_NAME)" >&2
  exit 1
fi
KERNEL_RELEASE=$(uname -r)
case "$KERNEL_RELEASE" in
  *microsoft*|*Microsoft*|*WSL*|*wsl*)
    echo "run-host.sh: refusing to run under WSL (kernel: $KERNEL_RELEASE)" >&2
    exit 1
    ;;
esac

# Read os-release.
if [ ! -r /etc/os-release ]; then
  echo "run-host.sh: /etc/os-release is not readable; cannot verify host" >&2
  exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release
OS_ID="${ID:-}"
OS_ID_LIKE="${ID_LIKE:-}"
OS_CODENAME="${VERSION_CODENAME:-}"
OS_PRETTY="${PRETTY_NAME:-unknown}"

# Accept if ID=ubuntu, OR (ID_LIKE contains "ubuntu" AND VERSION_CODENAME=noble).
accepted=0
if [ "$OS_ID" = "ubuntu" ]; then
  accepted=1
elif [ "$OS_CODENAME" = "noble" ]; then
  case " $OS_ID_LIKE " in
    *" ubuntu "*|*ubuntu*)
      accepted=1
      ;;
  esac
fi
if [ "$accepted" -ne 1 ]; then
  echo "run-host.sh: host not accepted (ID=$OS_ID ID_LIKE=\"$OS_ID_LIKE\" codename=$OS_CODENAME)" >&2
  echo "  accept only: ID=ubuntu OR (ID_LIKE contains ubuntu AND VERSION_CODENAME=noble)" >&2
  exit 1
fi

log "host accepted: $OS_PRETTY (ID=$OS_ID; ID_LIKE=$OS_ID_LIKE; codename=$OS_CODENAME; kernel=$KERNEL_RELEASE)"

# ---------------------------------------------------------------------------
# 2. Environment constants
# ---------------------------------------------------------------------------

CONTRACT_DIR="spikes/platform/runtime/contract"
RUNTIME_DIR="spikes/platform/runtime"

# Toolchain PATH for BUILDS (full toolchains present).
BUILD_PATH="$HOME/sdk/go1.26.5/bin:$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.dotnet:$PATH"

# Toolchain directories to STRIP from the child PATH when running the packaged
# artifact — proving self-containment.
TOOLCHAIN_DIRS="$HOME/sdk/go1.26.5/bin $HOME/.cargo/bin $HOME/.dotnet"

# Build a PATH with the toolchain dirs removed (bash-3.2-safe; simple loop).
_strip_path() {
  # $1 = original PATH; strips every dir in $TOOLCHAIN_DIRS.
  local in="$1"
  local out=""
  local IFS=":"
  local part
  for part in $in; do
    local keep=1
    local tdir
    for tdir in $TOOLCHAIN_DIRS; do
      if [ "$part" = "$tdir" ]; then
        keep=0
        break
      fi
    done
    if [ "$keep" -eq 1 ]; then
      if [ -z "$out" ]; then
        out="$part"
      else
        out="$out:$part"
      fi
    fi
  done
  printf '%s' "$out"
}
RUN_PATH=$(_strip_path "$BUILD_PATH")

DATE_STAMP=$(date -u +%Y%m%dT%H%M%SZ)

# host string embedded in every record's toolchain array.
HOST_TOOLCHAIN_LINE="host=Pop!_OS 24.04 (ID=pop; ID_LIKE=ubuntu; codename=noble)"
KERNEL_TOOLCHAIN_LINE="kernel=$KERNEL_RELEASE"

# ---------------------------------------------------------------------------
# 3. Per-candidate specification (lookup functions; bash-3.2-safe, no assoc arrays)
# ---------------------------------------------------------------------------

CANDIDATES="python go rust dotnet"

# subject.version per candidate
ver_of() {
  case "$1" in
    python) echo "3.14.6" ;;
    go)     echo "1.26.5" ;;
    rust)   echo "1.97.1" ;;
    dotnet) echo "10.0.10" ;;
  esac
}

# dependency_count per candidate (Go=0; Rust=[[package]]-1; .NET=lock entries; Python=[[package]])
depcount_of() {
  case "$1" in
    go)     echo "0" ;;
    rust)   echo "55" ;;
    dotnet) echo "4" ;;
    python) echo "12" ;;
  esac
}

# version invocation argument per candidate
versionarg_of() {
  case "$1" in
    python) echo "version" ;;
    *)      echo "--version" ;;
  esac
}

# built distributable ENTRYPOINT per candidate (the binary that is executed)
dist_of() {
  case "$1" in
    python) echo "$RUNTIME_DIR/python/dist/kinglet-host-probe" ;;
    go)     echo "$RUNTIME_DIR/go/dist/kinglet-host-probe" ;;
    rust)   echo "$RUNTIME_DIR/rust/target/release/kinglet-host-probe" ;;
    dotnet) echo "$RUNTIME_DIR/dotnet/bin/Release/net10.0/linux-x64/publish/kinglet-host-probe" ;;
  esac
}

# Sidecar files that must travel with the entrypoint — one path per line, empty
# for candidates that are genuinely a single file.
#
# FINDING (Task 7 Linux): with a bare `-p:PublishSingleFile=true`, the .NET
# self-contained publish is NOT truly single-file — NSec.Cryptography's native
# `libsodium.so` is emitted as a loose sidecar next to the binary, and copying
# only the binary breaks crypto.ed25519 ("NSec may not be supported on this
# platform"). The fix is to publish with `-p:IncludeNativeLibrariesForSelfExtract=true`
# (see build_candidate dotnet), which embeds libsodium.so into the bundle and
# self-extracts it at runtime. With that flag the .NET distributable is a single
# relocatable binary, so no sidecars are needed here.
sidecars_of() {
  case "$1" in
    *)
      : # no sidecars — all four distributables are single relocatable binaries
      ;;
  esac
}

# sources (title|url) per candidate — one per line
sources_of() {
  case "$1" in
    python)
      printf '%s\n' "Python 3.14.6|https://www.python.org/downloads/release/python-3146/"
      printf '%s\n' "PyInstaller 6.21.0|https://pyinstaller.org/en/stable/CHANGES.html"
      ;;
    go)
      printf '%s\n' "Go 1.26.5|https://go.dev/dl/"
      ;;
    rust)
      printf '%s\n' "Rust 1.97.1|https://forge.rust-lang.org/infra/other-installation-methods.html"
      ;;
    dotnet)
      printf '%s\n' ".NET 10.0.10 runtime|https://dotnet.microsoft.com/en-us/download/dotnet/10.0"
      printf '%s\n' "NSec.Cryptography 26.4.0|https://nsec.rocks/"
      ;;
  esac
}

# toolchain lines per candidate (real pins) — one per line; host+kernel appended later
toolchain_of() {
  case "$1" in
    python)
      printf '%s\n' "python=3.14.6"
      printf '%s\n' "pyinstaller=6.21.0"
      ;;
    go)
      printf '%s\n' "go=1.26.5"
      ;;
    rust)
      printf '%s\n' "rustc=1.97.1"
      printf '%s\n' "cargo=1.97.1"
      ;;
    dotnet)
      printf '%s\n' "dotnet-sdk=10.0.302"
      printf '%s\n' "dotnet-runtime=10.0.10"
      printf '%s\n' "nsec.cryptography=26.4.0"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 4. Build step per candidate (toolchains on PATH)
# ---------------------------------------------------------------------------

build_candidate() {
  local cand="$1"
  case "$cand" in
    python)
      # The PyInstaller onefile is already built (Task 2 Step 5). Rebuilding it
      # requires uv + a network fetch of the pinned interpreter; the pinned
      # artifact is reused verbatim.
      log "python: reusing pinned PyInstaller onefile (already built)"
      ;;
    go)
      log "go: go build -trimpath -ldflags=\"-s -w\""
      ( cd "$RUNTIME_DIR/go" \
        && PATH="$BUILD_PATH" GOTOOLCHAIN=local \
           go build -trimpath -ldflags="-s -w" -o dist/kinglet-host-probe . )
      ;;
    rust)
      log "rust: cargo build --locked --release"
      ( cd "$RUNTIME_DIR/rust" \
        && PATH="$BUILD_PATH" cargo build --locked --release )
      ;;
    dotnet)
      # IncludeNativeLibrariesForSelfExtract embeds NSec's libsodium.so into the
      # bundle so the single binary is relocatable (see sidecars_of finding).
      log "dotnet: dotnet publish -r linux-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true"
      ( cd "$RUNTIME_DIR/dotnet" \
        && PATH="$BUILD_PATH" DOTNET_ROOT="$HOME/.dotnet" \
           dotnet publish Kinglet.HostProbe.csproj -c Release -r linux-x64 \
             --self-contained true -p:PublishSingleFile=true \
             -p:IncludeNativeLibrariesForSelfExtract=true -p:RestoreLockedMode=false )
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 5. Main per-candidate driver
# ---------------------------------------------------------------------------

RECORD_BUILDER="$RUNTIME_DIR/build-record.py"

run_candidate_cell() {
  local cand="$1"
  local ver depcount versionarg dist run_id run_root exec_dir workspace result_file record_file
  ver=$(ver_of "$cand")
  depcount=$(depcount_of "$cand")
  versionarg=$(versionarg_of "$cand")
  dist=$(dist_of "$cand")
  run_id="${DATE_STAMP}-runtime-${cand}-linux-noble-01"

  # Empty run dir under .kinglet/local/ per run (required to be empty; create it).
  run_root=".kinglet/local/spikes/$run_id"
  exec_dir="$run_root/exec"
  workspace="$run_root/workspace"
  # Artifact must land under publish/artifacts/... for the publisher.
  local artifact_rel="artifacts/runtime/$cand/$run_id/result.json"
  result_file="$run_root/publish/$artifact_rel"
  record_file="$run_root/record.json"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN $cand:"
    log "  build: build_candidate $cand (PATH=$BUILD_PATH)"
    log "  mkdir empty run dir: $run_root"
    log "  copy distributable: $dist -> $exec_dir/kinglet-host-probe"
    log "  run packaged (PATH without toolchains): $exec_dir/kinglet-host-probe run --contract $CONTRACT_DIR/host-probe-v1.json --workspace $workspace --result <result>"
    log "  conformance: PATH=<stripped> python3 -m tools.kinglet_spike.runtime_contract --executable $exec_dir/kinglet-host-probe --contract-dir $CONTRACT_DIR"
    log "  measure: bash $RUNTIME_DIR/measure.sh $exec_dir/kinglet-host-probe $depcount $versionarg"
    log "  assemble record -> $record_file (run_id=$run_id)"
    log "  publish: python3 -m tools.kinglet_spike publish $record_file --repo-root ."
    return 0
  fi

  log "=== candidate: $cand (run_id=$run_id) ==="

  # Build.
  build_candidate "$cand"
  if [ ! -e "$dist" ]; then
    echo "run-host.sh: $cand distributable missing after build: $dist" >&2
    exit 1
  fi

  # Require an empty run dir (fail if it already has content).
  if [ -e "$run_root" ]; then
    if [ -n "$(ls -A "$run_root" 2>/dev/null)" ]; then
      echo "run-host.sh: run dir is not empty: $run_root" >&2
      exit 1
    fi
  fi
  mkdir -p "$exec_dir" "$workspace" "$(dirname "$result_file")"

  # Copy ONLY the distributable (entrypoint + any required sidecars) into the
  # clean exec dir. No toolchain, no source, no build tree.
  cp "$dist" "$exec_dir/kinglet-host-probe"
  chmod +x "$exec_dir/kinglet-host-probe"
  local sidecar
  while IFS= read -r sidecar; do
    if [ -n "$sidecar" ]; then
      if [ ! -e "$sidecar" ]; then
        echo "run-host.sh: $cand sidecar missing: $sidecar" >&2
        exit 1
      fi
      cp "$sidecar" "$exec_dir/"
    fi
  done <<EOF
$(sidecars_of "$cand")
EOF
  local exe="$exec_dir/kinglet-host-probe"
  local started_at
  started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # (a) Run the packaged artifact directly to capture its own result.json,
  #     with the toolchain dirs REMOVED from the child PATH (self-contained proof).
  log "$cand: running packaged artifact with toolchain-stripped PATH"
  env -i HOME="$HOME" PATH="$RUN_PATH" \
    "$exe" run \
      --contract "$REPO_ROOT/$CONTRACT_DIR/host-probe-v1.json" \
      --workspace "$REPO_ROOT/$workspace" \
      --result "$REPO_ROOT/$result_file"
  if [ ! -f "$result_file" ]; then
    echo "run-host.sh: $cand did not write result.json: $result_file" >&2
    exit 1
  fi

  # (b) Independent black-box conformance verification (18/18), also with a
  #     toolchain-stripped PATH so the harness launches a self-contained artifact.
  log "$cand: black-box conformance (runtime_contract)"
  PATH="$RUN_PATH" python3 -m tools.kinglet_spike.runtime_contract \
    --executable "$exe" \
    --contract-dir "$CONTRACT_DIR"

  # (c) Measure.
  log "$cand: measuring cold-start / peak-rss / artifact-size"
  local measure_json
  measure_json=$(bash "$RUNTIME_DIR/measure.sh" "$exe" "$depcount" "$versionarg")

  local ended_at
  ended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # (d) Assemble the evidence record. Relative paths only in the command array.
  local sources_data toolchain_data
  sources_data=$(sources_of "$cand")
  toolchain_data=$(toolchain_of "$cand")

  # The command array documents build + run with RELATIVE paths (no /home/...).
  # Newline-delimited; the builder splits on newlines.
  local command_data
  command_data=$(cat <<EOF
$RUNTIME_DIR/measure.sh
$exe
run
--contract
$CONTRACT_DIR/host-probe-v1.json
--workspace
<clean-workspace>
--result
<result.json>
EOF
)

  log "$cand: assembling record"
  python3 "$RECORD_BUILDER" \
    --candidate "$cand" \
    --version "$ver" \
    --run-id "$run_id" \
    --started-at "$started_at" \
    --ended-at "$ended_at" \
    --artifact-rel "$artifact_rel" \
    --result-file "$result_file" \
    --measure-json "$measure_json" \
    --host-line "$HOST_TOOLCHAIN_LINE" \
    --kernel-line "$KERNEL_TOOLCHAIN_LINE" \
    --toolchain-data "$toolchain_data" \
    --sources-data "$sources_data" \
    --command-data "$command_data" \
    --out "$record_file"

  # (e) Publish.
  log "$cand: publishing"
  python3 -m tools.kinglet_spike publish "$record_file" --repo-root .
  log "$cand: published OK"
}

for cand in $CANDIDATES; do
  run_candidate_cell "$cand"
done

if [ "$DRY_RUN" -eq 1 ]; then
  log "dry-run complete; nothing published"
else
  log "all four candidates published"
fi
