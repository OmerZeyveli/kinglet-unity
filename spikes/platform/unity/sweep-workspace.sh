#!/usr/bin/env bash
# sweep-workspace.sh -- Kill what a Unity probe run left behind, SCOPED.
#
#   bash sweep-workspace.sh <workspace-dir> [<owned-pgids-file>]
#
# Prints one `swept <pid> <pgid> <reason>` line per process it signalled, and
# exits 0 whether or not it found anything. A sweep that cannot list processes
# exits 2 rather than reporting a clean host.
#
# WHAT IT MAY KILL -- and nothing else:
#
#   1. a process whose argv names <workspace-dir>; and
#   2. a process whose PGID appears in <owned-pgids-file>, which the probe
#      runner writes for every process group IT created.
#
# WHAT IT MAY NOT KILL, ever: a process matched by NAME alone. That rule is
# the whole reason this file exists. The previous inline trap TERM-then-KILLed
# anything whose command line contained "UnityShaderCompiler" host-wide, which
# includes the shader compilers of an Editor the operator has open on an
# unrelated project -- and, since the match was on the whole line rather than
# argv0, a shell whose command string merely NAMES the class. That is the same
# string-vs-argv0 defect `filter_process_rows` exists to eliminate, except that
# here it destroys someone's work instead of miscounting.
#
# Name matching is still how the CLASSES are recognised, but only to explain a
# kill that scope has already authorised -- never to authorise one.
#
# The two scopes are not redundant. The workspace scope catches the Editor and
# its AssetImportWorkers, whose argv carries -projectPath. It provably cannot
# catch VBCSCompiler or UnityPackageManager: MEASURED on this host, neither
# carries -projectPath at all (the package-manager server names its parent
# Editor pid, `-s <pid>`, and the Roslyn server names only a pipe). Those are
# reachable only through the owned-PGID scope, which is exact because the
# runner recorded the group when it created it.

set -euo pipefail

WORKSPACE="${1:-}"
PGID_FILE="${2:-}"

if [ -z "$WORKSPACE" ]; then
    echo "sweep-workspace.sh: a workspace directory is required" >&2
    exit 2
fi

if ! TABLE="$(ps -eo pid,pgid,args 2>/dev/null)"; then
    echo "sweep-workspace.sh: could not list processes; refusing to report a clean host" >&2
    exit 2
fi

OWNED=""
if [ -n "$PGID_FILE" ] && [ -f "$PGID_FILE" ]; then
    # Read with awk, never `| head`: under `set -euo pipefail` an early-exiting
    # reader SIGPIPEs the writer and pipefail turns 141 into a failed script.
    OWNED="$(awk 'NF && $1 ~ /^[0-9]+$/ { print $1 }' "$PGID_FILE" | sort -u)"
fi

SELF_PGID="$(ps -o pgid= -p $$ | tr -d ' ')"

collect() {
    # Emits "<pid> <pgid> <reason>" for every in-scope process.
    printf '%s\n' "$TABLE" | awk -v ws="$WORKSPACE" -v owned="$OWNED" -v self="$SELF_PGID" -v self_pid="$$" '
        NR == 1 { next }
        {
            pid = $1; pgid = $2
            argv = ""
            for (i = 3; i <= NF; i++) { argv = argv (i > 3 ? " " : "") $i }
            if (pid == self_pid) { next }
            if (pgid == self) { next }              # never signal our own group
            reason = ""
            if (index(argv, ws) > 0) { reason = "workspace" }
            else if (owned != "") {
                n = split(owned, groups, "\n")
                for (g = 1; g <= n; g++) {
                    if (groups[g] != "" && pgid == groups[g]) { reason = "owned-pgid"; break }
                }
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
