#!/usr/bin/env bash
# run-host.sh -- Execute the 00U Unity route probes natively on this host.
#
#   bash spikes/platform/unity/run-host.sh --unity /path/to/Unity [--run-id ID]
#
# Linux and macOS only, and NATIVE only: no WSL, no Git Bash, no container that
# reports a Linux kernel while the Unity install and the process table belong to
# another OS. A probe suite whose whole subject is process containment and file
# identity is worthless run through a translation layer, so the host check is a
# refusal rather than a warning.
#
# The Editor path is REQUIRED and explicit. There is no search of the Unity Hub
# and no "first one found": which Editor ran is part of the evidence, and a
# script that picks one silently makes that fact unrecoverable.
#
# Everything this writes lands under .kinglet/local/spikes/<run-id>/, which is
# gitignored. Raw Unity logs, the NUnit XML, machine paths and the MCP server's
# streams stay there. Only the sanitized JSON summaries staged beneath
# <run-id>/records/*/publish/ are ever candidates for the committed tree, and
# they get there through `tools.kinglet_spike publish`, which re-validates them.
#
# Shell conventions (see CLAUDE.md): bash 3.2 compatible -- no `declare -A`, no
# `grep -oP` -- and nothing is piped into `head` under `set -euo pipefail`.

set -euo pipefail

usage() {
    cat <<'USAGE'
usage: run-host.sh --unity <path to Unity editor binary> [--run-id <id>]
                   [--repo-root <path>] [--publish]

  --unity      REQUIRED. Exact Unity Editor binary. No search, no default.
  --run-id     Raw run directory name. Defaults to a fresh UTC stamp.
  --repo-root  Repository root. Defaults to this script's repository.
  --publish    Also run `tools.kinglet_spike publish` for every staged record.
USAGE
}

UNITY=""
RUN_ID=""
REPO_ROOT=""
PUBLISH="no"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --unity)
            # Validated BEFORE `shift 2`: under `set -u` a missing operand makes
            # `shift 2` fail first, and the user gets a silent exit 1 instead of
            # this message.
            if [ "$#" -lt 2 ]; then
                echo "run-host.sh: --unity requires a path" >&2
                exit 2
            fi
            UNITY="$2"
            shift 2
            ;;
        --run-id)
            if [ "$#" -lt 2 ]; then
                echo "run-host.sh: --run-id requires a value" >&2
                exit 2
            fi
            RUN_ID="$2"
            shift 2
            ;;
        --repo-root)
            if [ "$#" -lt 2 ]; then
                echo "run-host.sh: --repo-root requires a path" >&2
                exit 2
            fi
            REPO_ROOT="$2"
            shift 2
            ;;
        --publish)
            PUBLISH="yes"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "run-host.sh: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ -z "$UNITY" ]; then
    echo "run-host.sh: --unity is required; this script never searches for an Editor" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$REPO_ROOT" ]; then
    REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

# ---- host gate ------------------------------------------------------------
UNAME_S="$(uname -s)"
case "$UNAME_S" in
    Linux|Darwin) ;;
    *)
        echo "run-host.sh: native Linux or macOS only; this host reports '$UNAME_S'" >&2
        exit 2
        ;;
esac

# WSL reports Linux. Its process table, its file identities and its Unity
# install all belong to a Windows host, so every containment and inode fact
# this suite publishes would be about the wrong machine.
if [ -f /proc/sys/kernel/osrelease ]; then
    OSRELEASE="$(cat /proc/sys/kernel/osrelease)"
    case "$OSRELEASE" in
        *icrosoft*|*WSL*)
            echo "run-host.sh: refusing to run under WSL ('$OSRELEASE'); the Windows host must run natively" >&2
            exit 2
            ;;
    esac
fi

# Git Bash / MSYS / Cygwin also answer `uname -s` with something usable.
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        echo "run-host.sh: refusing to run under Git Bash/MSYS/Cygwin" >&2
        exit 2
        ;;
esac
if [ -n "${WSL_DISTRO_NAME:-}" ] || [ -n "${WSLENV:-}" ]; then
    echo "run-host.sh: refusing to run under WSL (WSL environment variables are set)" >&2
    exit 2
fi

if [ ! -x "$UNITY" ]; then
    echo "run-host.sh: not an executable Unity Editor: $UNITY" >&2
    exit 2
fi

if [ ! -d "$REPO_ROOT/spikes/platform/unity/fixture" ]; then
    echo "run-host.sh: pinned fixture missing under $REPO_ROOT" >&2
    exit 2
fi

if [ -z "$RUN_ID" ]; then
    RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-unity-host"
fi

# RUN_ID is concatenated into RAW_ROOT, which becomes the SWEEP'S WORKSPACE
# ARGUMENT. It was accepted unvalidated, so `--run-id ../../..` walked the raw
# root out of `.kinglet/local/` entirely, and `--run-id ''`-shaped values (a
# lone `.`, a trailing `/..`) collapsed it further -- handing the sweep a
# directory nobody intended it to have. sweep-workspace.sh's own guard refuses
# the worst of those, but a value that reaches a guard already meaning
# something else is the defect; it is refused HERE, where it is still the
# operator's literal input.
#
# A single conservative alphabet: letters, digits, dot, dash, underscore. It
# admits every id this script generates and every id an operator would type,
# and it excludes `/`, `..` as a whole component, and every shell and control
# character at once.
case "$RUN_ID" in
    *[!A-Za-z0-9._-]*)
        echo "run-host.sh: --run-id may contain only letters, digits, '.', '-' and '_', got: $RUN_ID" >&2
        exit 2
        ;;
esac
case "$RUN_ID" in
    ""|.|..|.*)
        echo "run-host.sh: --run-id must not be empty and must not begin with '.', got: $RUN_ID" >&2
        exit 2
        ;;
esac

RAW_ROOT="$REPO_ROOT/.kinglet/local/spikes/$RUN_ID"
if [ -e "$RAW_ROOT" ]; then
    # A fresh raw run ID every time. Reusing one would let a previous run's log,
    # results file or lease be read as this run's evidence.
    echo "run-host.sh: raw run directory already exists: $RAW_ROOT" >&2
    exit 2
fi
mkdir -p "$RAW_ROOT"

# ---- cleanup trap ---------------------------------------------------------
# A timeout, a failure or a Ctrl-C must still leave the host clean. The Python
# probes contain their own launches by process group; this is the outer net for
# whatever outlived them.
#
# The sweep itself lives in sweep-workspace.sh so it can be TESTED against real
# processes rather than asserted as source text, and so its scoping rule is
# stated in exactly one place. It kills only what names this run's workspace or
# belongs to a process group this run created -- the probe runner records every
# such group in OWNED_PGIDS, which is the only way to reach VBCSCompiler and
# UnityPackageManager, neither of which carries -projectPath in its argv. It
# never kills by a host-wide name match; see that file's header for why that
# rule is not negotiable.
OWNED_PGIDS="$RAW_ROOT/owned-pgids.txt"
export KINGLET_UNITY_OWNED_PGIDS="$OWNED_PGIDS"

cleanup() {
    status="$?"
    if [ -d "$RAW_ROOT/workspace" ]; then
        # NOT `|| true`. The sweep exits 2 when it REFUSES -- an unusable
        # workspace, or a process table it could not read -- and `|| true`
        # discarded that refusal entirely: the operator saw a clean exit while
        # a live Editor and its orphans were still on the host. "I could not
        # sweep" is not "nothing was left behind", and the difference has to
        # reach the exit status or nobody will ever act on it.
        #
        # A refusal during cleanup does not overwrite a real failure status
        # from the run itself; it only turns a success into a failure.
        if ! bash "$SCRIPT_DIR/sweep-workspace.sh" "$RAW_ROOT/workspace" "$OWNED_PGIDS"; then
            echo "run-host.sh: THE SWEEP REFUSED; this host may still be running Unity processes from this run" >&2
            if [ "$status" -eq 0 ]; then
                status=1
            fi
        fi
    fi
    exit "$status"
}
trap cleanup EXIT INT TERM

echo "run-host.sh: host=$UNAME_S editor=$UNITY run=$RUN_ID"

cd "$REPO_ROOT"
python3 -m tools.kinglet_spike.unity.host_probes "$REPO_ROOT" "$UNITY" "$RAW_ROOT"

echo "run-host.sh: observations at $RAW_ROOT/observations.json"
echo "run-host.sh: staged records:"
for record in "$RAW_ROOT"/records/*/record.json; do
    [ -f "$record" ] || continue
    echo "  $record"
done

if [ "$PUBLISH" = "yes" ]; then
    for record in "$RAW_ROOT"/records/*/record.json; do
        [ -f "$record" ] || continue
        python3 -m tools.kinglet_spike publish "$record" --repo-root "$REPO_ROOT"
    done
    python3 -m tools.kinglet_spike report --repo-root "$REPO_ROOT" \
        --matrix spikes/platform/contracts/matrix-v1.json
fi
