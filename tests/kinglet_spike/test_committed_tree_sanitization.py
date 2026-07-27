"""test_committed_tree_sanitization.py — Client-agnostic sanitization of committed spike text.

test_claude_code_observations.py covers the claude-code evidence set by name.
That is how the probe scripts came to be unguarded in the first place: a
mutation adding `cp $HOME/.claude/.credentials.json` and an absolute home path
to `claude-code/probe/run.sh` left the whole suite green, because nothing looked
at those files. Naming them fixed claude-code and left the NEXT client — codex,
and whatever follows — with the identical blind spot.

This file removes the "remember to add it" step. It walks
`spikes/platform/clients/**` and the published evidence and artifact trees and
asserts that no committed text file anywhere in them carries an absolute machine
path, a credential-like value, the disposable probe root, or a copy of a
credential file. A new client directory is swept the moment it lands.

The sweep's own vacuity is a first-class failure: a walk that matches nothing
must be an error, not a pass. Every root is asserted non-empty independently,
and the files the previous fix covered by name are asserted to be inside the set
this file walks by shape.
"""
from __future__ import annotations

import unittest

from tests.kinglet_spike.spike_tree import (
    ALLOWED_CREDENTIAL_REFERENCE,
    ARTIFACTS_ROOT,
    CLIENTS_ROOT,
    COPY_VERB,
    CREDENTIAL_FILE,
    EVIDENCE_ROOT,
    PROBE_ROOT,
    REPO,
    committed_text_files,
    files_by_root,
    is_script,
    relative,
)
from tools.kinglet_spike.validate import SECRET_PATTERNS, SENSITIVE_PATH_PATTERNS

# Files that exist today and must be inside the swept set. If a rename or a
# narrowed glob drops one of them, the sweep is quietly scanning less than it
# claims and this list says so. It is not a whitelist — nothing is exempt.
KNOWN_COVERED = (
    "spikes/platform/clients/claude-code/probe/run.sh",
    "spikes/platform/clients/claude-code/probe/run2.sh",
    "spikes/platform/clients/claude-code/observations-linux.json",
    "spikes/platform/clients/claude-code/runbook.md",
    "spikes/platform/clients/claude-code/hooks/pre-mutation-hook.sh",
    "spikes/platform/clients/shared/create-project.sh",
    "spikes/platform/clients/shared/create-project.ps1",
    "docs/research/platform-spike/evidence/client/claude-code/"
    "20260727T095800Z-client-probe-claudecode-linux-ubuntu-24.04.4-lts-x64-01.json",
    "docs/research/platform-spike/artifacts/client/claude-code/"
    "20260727T095800Z-client-probe-claudecode-linux-ubuntu-24.04.4-lts-x64-01/"
    "prompts-used.json",
)


class SweepIsNotVacuousTests(unittest.TestCase):
    """The sweep must fail loudly rather than walk nothing.

    A sanitization test that scans zero files passes forever. Each of these
    assertions exists because the cheapest way to "fix" a failing sweep is to
    point it somewhere emptier.
    """

    def test_every_root_contributes_files(self):
        for root, paths in files_by_root():
            self.assertGreater(
                len(paths), 0, f"sanitization sweep walked zero files under {root}"
            )

    def test_all_three_roots_are_swept(self):
        roots = {root for root, _paths in files_by_root()}
        self.assertEqual(roots, {CLIENTS_ROOT, EVIDENCE_ROOT, ARTIFACTS_ROOT})

    def test_sweep_covers_a_realistic_number_of_files(self):
        # The tree holds ~50 committed text files. A floor well under that still
        # catches a glob that collapses to a handful.
        self.assertGreaterEqual(len(committed_text_files()), 20)

    def test_known_covered_files_are_in_the_swept_set(self):
        swept = {relative(path) for path in committed_text_files()}
        for name in KNOWN_COVERED:
            self.assertTrue(
                (REPO / name).is_file(), f"{name} vanished; update KNOWN_COVERED"
            )
            self.assertIn(
                name, swept, f"{name} is committed but the sanitization sweep misses it"
            )

    def test_every_client_directory_is_swept(self):
        # The point of the change: a new client directory is covered by default.
        # If codex/ lands with zero swept files, that is the old blind spot back.
        swept = {relative(path) for path in committed_text_files()}
        clients = [
            child
            for child in sorted(CLIENTS_ROOT.iterdir())
            if child.is_dir() and not child.name.startswith(".")
        ]
        self.assertTrue(clients, f"no client directories under {CLIENTS_ROOT}")
        for client in clients:
            prefix = relative(client) + "/"
            self.assertTrue(
                any(name.startswith(prefix) for name in swept),
                f"{prefix} contributes no file to the sanitization sweep",
            )


class CommittedTreeSanitizationTests(unittest.TestCase):
    def test_no_committed_file_carries_an_absolute_machine_path(self):
        for path in committed_text_files():
            content = path.read_text(encoding="utf-8")
            for pattern in SENSITIVE_PATH_PATTERNS:
                match = pattern.search(content)
                self.assertIsNone(
                    match,
                    f"{relative(path)} contains an absolute user path: "
                    f"{match.group(0) if match else ''!r}",
                )

    def test_no_committed_file_carries_a_credential_like_value(self):
        for path in committed_text_files():
            content = path.read_text(encoding="utf-8")
            for pattern in SECRET_PATTERNS:
                match = pattern.search(content)
                self.assertIsNone(
                    match,
                    f"{relative(path)} contains a credential-like value: "
                    f"{match.group(0) if match else ''!r}",
                )

    def test_no_committed_file_leaks_the_disposable_probe_root(self):
        for path in committed_text_files():
            self.assertIsNone(
                PROBE_ROOT.search(path.read_text(encoding="utf-8")),
                f"{relative(path)} leaks the disposable probe root",
            )

    def test_no_committed_file_copies_a_credential_file(self):
        # Checking that "$CFG/.credentials.json" EXISTS is allowed — provisioning
        # the disposable root is a manual operator step. Copying, catting, or
        # otherwise moving that file is not, in any client, in any language.
        for path in committed_text_files():
            for number, line in enumerate(
                path.read_text(encoding="utf-8").splitlines(), start=1
            ):
                if not CREDENTIAL_FILE.search(line):
                    continue
                match = COPY_VERB.search(line)
                self.assertIsNone(
                    match,
                    f"{relative(path)}:{number} copies or reads out a credential "
                    f"file: {line.strip()!r}",
                )

    def test_scripts_name_the_credential_file_only_as_a_presence_check(self):
        # Stricter than the copy rule, and applied to everything executable in
        # every client tree: a script may name the credential file ONLY as
        # "$VAR/.credentials.json" inside its disposable config root. Any other
        # spelling — above all one with a path segment before it, like
        # "$HOME/.claude/.credentials.json" — is a leak.
        scripts = [path for path in committed_text_files() if is_script(path)]
        self.assertTrue(scripts, "no committed scripts found to check")
        for path in scripts:
            for number, line in enumerate(
                path.read_text(encoding="utf-8").splitlines(), start=1
            ):
                residue = ALLOWED_CREDENTIAL_REFERENCE.sub("", line)
                self.assertIsNone(
                    CREDENTIAL_FILE.search(residue),
                    f"{relative(path)}:{number} names the credential file outside "
                    f'a "$VAR/.credentials.json" presence check: {line.strip()!r}',
                )


if __name__ == "__main__":
    unittest.main()
