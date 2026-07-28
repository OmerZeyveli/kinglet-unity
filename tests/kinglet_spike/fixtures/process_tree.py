"""process_tree.py -- A real, self-orphaning process tree for containment tests.

Run as a module, never imported for symbols:

    python3 -m tests.kinglet_spike.fixtures.process_tree parent  --report <path>
    python3 -m tests.kinglet_spike.fixtures.process_tree orphan  --report <path>
    python3 -m tests.kinglet_spike.fixtures.process_tree child

Why this fixture exists at all
------------------------------
The measured behaviour this task must contain is Unity's, and it was measured
on this host: after a CLEAN batchmode exit (exit code 0), two
``dotnet exec .../DotNetSdkRoslyn/VBCSCompiler.dll`` processes were still
running with **PPID = 1** -- reparented to init -- while no ``Editor/Unity``
process remained at all. So the leak that has to be closed is specifically a
process that OUTLIVES its launcher and is no longer anywhere in its tree by
the time the launcher's exit is observed.

A mock cannot reproduce that: reparenting is done by the kernel, and the whole
question is whether the containment mechanism survives it. Hence a real tree.

Modes
-----
``parent``
    Launches ``child`` as an ordinary subprocess (inheriting this process's
    process group -- exactly how Unity launches VBCSCompiler), writes
    ``{"parent_pid": ..., "child_pid": ...}`` to ``--report`` and then sleeps
    for 30 seconds. This is the "still running when we cancel it" shape: the
    cancellation, timeout and competitor tests all interrupt it mid-sleep.

``orphan``
    Same launch, same report, but the parent EXITS IMMEDIATELY with code 0
    while the child keeps sleeping. This is the measured Unity shape --
    clean exit, live orphan -- and it is the mode that makes the naive
    "after the launcher exits, walk its children and kill them" strategy
    demonstrably useless: by the time the parent's exit is observed the child's
    PPID is 1 and there is no tree left to walk.

``child``
    Sleeps for 30 seconds. Long enough that no test can pass by accident
    through the child simply having finished on its own; every test that
    asserts zero survivors is asserting that something killed it.

The report file is written and flushed and fsynced BEFORE the parent does
anything else, because in ``orphan`` mode the parent may be gone before the
test gets to read it. Report writing is atomic (write to a sibling temp path,
then ``os.replace``) so a test can never read a half-written JSON object and
mistake a truncated file for a missing child.

Nothing here uses ``setsid``/``start_new_session``: the fixture must inherit
whatever process group its launcher put it in, since that inheritance is
precisely the property ``ManagedProcess`` relies on.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

# Long enough that a survivor is unambiguously a survivor. No test waits for
# this to elapse; every test kills the tree and then asserts nothing is left.
SLEEP_SECONDS = 30.0


def _write_report(report: Path, payload: dict) -> None:
    """Atomically write payload as JSON to report."""
    temp = report.with_name(report.name + ".partial")
    with open(temp, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp, report)


def _spawn_child() -> subprocess.Popen:
    """Launch the child in the CALLER's process group -- no new session.

    This mirrors how Unity launches its Roslyn compiler server: an ordinary
    child, inheriting the launcher's session and process group. The child is
    what survives; the group membership is what makes it findable afterwards.
    """
    return subprocess.Popen(
        [sys.executable, "-m", __spec__.name, "child"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="process_tree")
    parser.add_argument("mode", choices=("parent", "orphan", "child"))
    parser.add_argument("--report", default=None)
    args = parser.parse_args(argv)

    if args.mode == "child":
        time.sleep(SLEEP_SECONDS)
        return 0

    if args.report is None:
        parser.error("--report is required for parent and orphan modes")

    child = _spawn_child()
    _write_report(
        Path(args.report),
        {"mode": args.mode, "parent_pid": os.getpid(), "child_pid": child.pid},
    )

    if args.mode == "orphan":
        # Exit cleanly and immediately, leaving the child running. Do NOT
        # wait for it: the point is that it is reparented to init.
        return 0

    time.sleep(SLEEP_SECONDS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
