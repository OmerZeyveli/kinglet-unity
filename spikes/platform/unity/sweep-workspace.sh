#!/usr/bin/env bash
# sweep-workspace.sh -- Kill what a Unity probe run left behind, SCOPED.
#
#   bash sweep-workspace.sh <workspace-dir> [<owned-pgids-file>]
#   bash sweep-workspace.sh --check <workspace-dir> [<owned-pgids-file>]
#
# `--check` validates the arguments and exits without listing or signalling
# anything. It exists so the argument guard below can be driven directly: the
# act that guard forbids is selecting PID 1, and a test that had to launch a
# real sweep in order to prove the refusal would be a test that can perform it.
#
# Prints one `swept <pid> <pgid> <reason>` line per process it signalled and
# exits 0 whether or not it found anything. A sweep that cannot list processes
# exits 2 rather than reporting a clean host.
#
# ---------------------------------------------------------------------------
# WHAT AUTHORISES A KILL
# ---------------------------------------------------------------------------
# Exactly two things, and a process must satisfy one of them:
#
#   1. its argv names <workspace-dir> AT A PATH BOUNDARY; or
#   2. its PGID appears in <owned-pgids-file> -- a group this run created --
#      AND it is corroborated as Unity-shaped.
#
# A NAME NEVER AUTHORISES A KILL. It only narrows a set that scope has already
# authorised. That distinction is the whole file. The original inline trap
# TERM-then-KILLed anything whose command line contained "UnityShaderCompiler",
# host-wide, which includes the shader compilers of an Editor the operator has
# open on an unrelated project -- and, matching the whole line rather than
# argv0, any shell whose command string merely NAMES the class. While that
# defect was being reproduced under mutation it killed the shell running the
# mutation, twice.
#
# The two scopes are not redundant. Scope 1 catches the Editor and its
# AssetImportWorkers, whose argv carries -projectPath. It provably cannot catch
# VBCSCompiler or UnityPackageManager: MEASURED on this host, neither carries
# -projectPath at all (the package-manager server names its parent Editor pid,
# `-s <pid>`, and the Roslyn server names only a pipe). Those are reachable
# only through scope 2.
#
# ---------------------------------------------------------------------------
# WHAT SCOPE 2 DOES AND DOES NOT GUARANTEE
# ---------------------------------------------------------------------------
# This header used to claim the PGID scope "is exact because the runner
# recorded the group when it created it". That OVERSTATED it, and the overstated
# version was the code: a PGID is a PID, PIDs are recycled, and bare pgid
# equality authorises killing whatever inherited the number. Demonstrated -- an
# unrelated `innocent-daemon` whose pgid was written into the file was swept.
#
# What is now true: the recorded group is NECESSARY BUT NOT SUFFICIENT. A
# candidate must also be corroborated as Unity-shaped -- argv0 must not be a
# shell or a process tool, and the argv must name one of the classes a Unity
# run actually produces. Corroboration authorises nothing by itself: a process
# merely named `UnityShaderCompiler` outside every owned group is untouched,
# and there is a test that fails if it ever is not. Where corroboration is
# unavailable the answer is to NOT kill, so a recycled PGID resolves to
# sparing -- the direction every other refusal in this plan resolves.
#
# ---------------------------------------------------------------------------
# WHAT THE WORKSPACE ARGUMENT MAY BE
# ---------------------------------------------------------------------------
# It used to be rejected only when empty. `bash sweep-workspace.sh /` therefore
# selected every process on the host INCLUDING PID 1, and `.` did the same --
# from a documented, supported entry point, on the operator's own machine, one
# typo away. The guard below refuses anything that is not an absolute path to
# an existing directory of at least MIN_DEPTH components, and refuses any path
# that IS or CONTAINS the repository or the home directory. Ambiguity resolves
# to refusing to sweep, never to sweeping wider.

set -euo pipefail

# `/a/b/c` is the shallowest thing that can plausibly be a run workspace. The
# filesystem root, the two-component home directory of any user, `/usr` and
# friends all sit above this and are refused before the ancestor rules are even
# consulted. (Spelling a home directory literally here is what the committed
# tree's own sanitization sweep flags -- correctly, and it caught this comment.)
MIN_DEPTH=3

CHECK_ONLY="no"
if [ "${1:-}" = "--check" ]; then
    CHECK_ONLY="yes"
    shift
fi

WORKSPACE="${1:-}"
PGID_FILE="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"

refuse() {
    echo "sweep-workspace.sh: $1" >&2
    exit 2
}

# ---- argument guard -------------------------------------------------------
if [ -z "$WORKSPACE" ]; then
    refuse "a workspace directory is required"
fi

case "$WORKSPACE" in
    /*) ;;
    *) refuse "workspace must be an absolute path, got: $WORKSPACE" ;;
esac

case "$WORKSPACE" in
    *..*) refuse "workspace must not contain '..', got: $WORKSPACE" ;;
esac

if [ ! -d "$WORKSPACE" ]; then
    refuse "workspace is not an existing directory: $WORKSPACE"
fi

# Resolve symlinks with `cd ... && pwd -P` rather than `realpath`, which is not
# present by default on every macOS this must run on.
if ! WS="$(cd "$WORKSPACE" 2>/dev/null && pwd -P)"; then
    refuse "cannot resolve workspace: $WORKSPACE"
fi

if [ "$WS" = "/" ]; then
    refuse "refusing to sweep the filesystem root"
fi

DEPTH="$(printf '%s\n' "$WS" | awk -F/ '{ print NF - 1 }')"
if [ "$DEPTH" -lt "$MIN_DEPTH" ]; then
    refuse "workspace is too shallow to be a run directory (depth $DEPTH < $MIN_DEPTH): $WS"
fi

# A workspace that IS or CONTAINS the repository or the home directory is not a
# run workspace, and sweeping it would select the operator's whole session.
for guarded in "$REPO_ROOT" "${HOME:-}" "$SCRIPT_DIR"; do
    [ -n "$guarded" ] || continue
    if [ "$guarded" = "$WS" ]; then
        refuse "refusing to sweep a directory that IS the repository or the home directory: $WS"
    fi
    case "$guarded" in
        "$WS"/*)
            refuse "refusing to sweep a directory that contains the repository or the home directory: $WS"
            ;;
    esac
done

if [ "$CHECK_ONLY" = "yes" ]; then
    echo "ok $WS"
    exit 0
fi

# ---- process table --------------------------------------------------------
if ! TABLE="$(ps -eo pid,pgid,args 2>/dev/null)"; then
    refuse "could not list processes; refusing to report a clean host"
fi

OWNED=""
if [ -n "$PGID_FILE" ] && [ -f "$PGID_FILE" ]; then
    # Read with awk, never `| head`: under `set -euo pipefail` an early-exiting
    # reader SIGPIPEs the writer and pipefail turns 141 into a failed script.
    OWNED="$(awk 'NF && $1 ~ /^[0-9]+$/ { print $1 }' "$PGID_FILE" | sort -u)"
fi

SELF_PGID="$(ps -o pgid= -p $$ | tr -d ' ')"

collect() {
    printf '%s\n' "$TABLE" | awk \
        -v ws="$WS" -v owned="$OWNED" -v self="$SELF_PGID" -v self_pid="$$" '
        # Does argv name the workspace AT A PATH BOUNDARY?
        #
        # A plain substring test swept `<ws>2/proj` as though it were
        # `<ws>/proj`. That is the `/x/proj` vs `/x/proj2` prefix case Task 3s
        # ownership detector spent four rounds closing, reintroduced here in
        # awk. A match counts only when the character after the prefix ends the
        # path component: end of string, a separator, a space, or a quote.
        function names_workspace(argv,    rest, p, nextch) {
            rest = argv
            while ((p = index(rest, ws)) > 0) {
                nextch = substr(rest, p + length(ws), 1)
                if (nextch == "" || nextch == "/" || nextch == " " ||
                    nextch == "\"" || nextch == "'"'"'" || nextch == ":") {
                    return 1
                }
                rest = substr(rest, p + 1)
            }
            return 0
        }

        # CORROBORATION ONLY -- never authority. Reached only for a candidate
        # already inside a process group this run created; its job is to spare
        # whatever inherited a recycled PGID.
        function looks_like_unity(argv,    argv0, base, bits) {
            split(argv, bits, " ")
            argv0 = bits[1]
            base = argv0
            sub(/^.*\//, "", base)
            if (base == "bash" || base == "sh" || base == "zsh" ||
                base == "dash" || base == "fish" || base == "grep" ||
                base == "pgrep" || base == "ps" || base == "python" ||
                base == "python3") {
                return 0
            }
            if (index(argv, "Editor/Unity") > 0) { return 1 }
            if (index(argv, "-name AssetImportWorker") > 0) { return 1 }
            if (index(argv, "VBCSCompiler") > 0) { return 1 }
            if (index(argv, "UnityPackageManager") > 0) { return 1 }
            if (index(argv, "UnityShaderCompiler") > 0) { return 1 }
            if (base == "Unity") { return 1 }
            return 0
        }

        function group_is_owned(pgid,    n, groups, g) {
            if (owned == "") { return 0 }
            n = split(owned, groups, "\n")
            for (g = 1; g <= n; g++) {
                if (groups[g] != "" && pgid == groups[g]) { return 1 }
            }
            return 0
        }

        NR == 1 { next }
        {
            pid = $1; pgid = $2
            argv = ""
            for (i = 3; i <= NF; i++) { argv = argv (i > 3 ? " " : "") $i }
            if (pid == self_pid) { next }
            if (pgid == self) { next }              # never signal our own group
            reason = ""
            if (names_workspace(argv)) { reason = "workspace" }
            else if (group_is_owned(pgid) && looks_like_unity(argv)) {
                reason = "owned-pgid"
            }
            if (reason != "") { print pid " " pgid " " reason }
        }
    '
}

TARGETS="$(collect || true)"
if [ -z "$TARGETS" ]; then
    exit 0
fi

PIDS="$(printf '%s\n' "$TARGETS" | awk '{ print $1 }')"

for pid in $PIDS; do
    kill -TERM "$pid" 2>/dev/null || true
done
sleep 5
for pid in $PIDS; do
    kill -KILL "$pid" 2>/dev/null || true
done
sleep 1

printf '%s\n' "$TARGETS" | while read -r pid pgid reason; do
    echo "swept $pid $pgid $reason"
done

exit 0
