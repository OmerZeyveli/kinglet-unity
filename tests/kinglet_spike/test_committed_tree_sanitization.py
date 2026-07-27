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

import subprocess
import tempfile
import unittest
from pathlib import Path

from tests.kinglet_spike import spike_tree
from tests.kinglet_spike.spike_tree import (
    ALLOWED_CREDENTIAL_REFERENCE,
    ARTIFACTS_ROOT,
    CLIENTS_ROOT,
    CREDENTIAL_FILE,
    EVIDENCE_ROOT,
    PROBE_ROOT,
    REPO,
    SKIP_DIR_NAMES,
    SKIP_RELATIVE_DIRS,
    SWEPT_ROOTS,
    committed_text_files,
    credential_copy_violations,
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

    # There was a `>= 20` file-count floor here. It was deleted: every truncation
    # it could catch is already caught by test_known_covered_files_are_in_the_
    # swept_set with a named path, the number needed bumping by hand forever, and
    # a floor that never fires reads as coverage it does not provide.

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

    def test_no_build_output_directory_is_skipped_by_name(self):
        # `bin`, `dist`, `obj` and `target` were skipped by NAME at any depth,
        # which gave every client a no-scan zone: `clients/<any>/bin/leak.sh` was
        # green here and invisible to the CI grep. Build output is skipped by
        # anchored path now; reintroducing a name reopens the hole for every
        # client at once, including ones that do not exist yet.
        for name in ("bin", "dist", "obj", "target", "build", "out", "vendor"):
            self.assertNotIn(
                name,
                SKIP_DIR_NAMES,
                f"{name!r} is skipped by directory name at any depth, so "
                f"clients/<any>/{name}/ is a silent no-scan zone",
            )

    def test_skipped_relative_directories_are_anchored(self):
        # A skip must name one exact place. A bare directory name would be back
        # to matching at any depth under every client, which is the hole above.
        roots = tuple(relative(root) + "/" for root in SWEPT_ROOTS)
        for rel in SKIP_RELATIVE_DIRS:
            self.assertFalse(rel.startswith("/"), f"{rel!r} is not repo-relative")
            self.assertIn("/", rel, f"{rel!r} is a bare name, not an anchored path")
            self.assertTrue(
                rel.startswith(roots),
                f"{rel} is skipped but lies outside every swept root, so the skip "
                f"is either dead or the roots moved: {roots}",
            )

    def test_no_tracked_file_hides_in_a_skipped_directory(self):
        # Skipping is only safe while nothing tracked lives behind it. This is the
        # assertion that lets the tool-cache names stay name-matched.
        try:
            listed = subprocess.run(
                ["git", "ls-files", "-z", "--", *[relative(r) for r in SWEPT_ROOTS]],
                cwd=REPO,
                capture_output=True,
                text=True,
                check=True,
            ).stdout
        except (OSError, subprocess.CalledProcessError) as error:  # pragma: no cover
            self.skipTest(f"git unavailable: {error}")
        tracked = [name for name in listed.split("\0") if name]
        self.assertTrue(tracked, "git listed no tracked files under the swept roots")
        for name in tracked:
            parts = name.split("/")[:-1]
            hidden = [part for part in parts if part in SKIP_DIR_NAMES]
            self.assertFalse(
                hidden,
                f"{name} is tracked but sits under skipped directory {hidden}",
            )
            for rel in SKIP_RELATIVE_DIRS:
                self.assertFalse(
                    name.startswith(rel + "/"),
                    f"{name} is tracked but sits under skipped path {rel}",
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
        #
        # This follows the credential across assignments rather than requiring the
        # filename and the copy verb on ONE line. Same-line-only was defeated by
        # splitting the two, and it was the only credential rule applied to
        # non-scripts — so a multi-line copy recipe in a client's runbook.md
        # passed, unexecuted but ready to paste.
        for path in committed_text_files():
            for number, line, reason in credential_copy_violations(
                path.read_text(encoding="utf-8")
            ):
                self.fail(f"{relative(path)}:{number} {reason}: {line.strip()!r}")

    def test_the_sweep_refuses_to_skip_a_file_it_cannot_decode(self):
        # `_walk` used to `continue` past UnicodeDecodeError. A committed
        # `leak.bin.txt` — a token, an absolute home path, a few stray \xff bytes
        # — was therefore green here AND invisible to the CI grep, which calls it
        # binary. Every file in the swept roots must now be either a declared
        # binary suffix or decodable; there is no third, silent category.
        #
        # The real tree exercises this by construction — committed_text_files()
        # raises if any file is undecodable — so the behaviour itself is pinned
        # here against a scratch directory, naming the path in the message.
        for path in committed_text_files():
            path.read_text(encoding="utf-8")

        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            (root / "ordinary.txt").write_text("fine\n", encoding="utf-8")
            # A leak-shaped payload, spelled so this file stays clean under the
            # repo's own grep: the bytes are what matter, not the wording.
            (root / "leak.bin.txt").write_bytes(
                b"token=gh" + b"p_x \xff\xfe home=" + b"/ho" + b"me/x\n"
            )
            with self.assertRaises(AssertionError) as raised:
                spike_tree._walk(root)
            self.assertIn("leak.bin.txt", str(raised.exception))

    def test_scripts_name_the_credential_file_only_as_a_presence_check(self):
        # Stricter than the copy rule, and applied to everything executable in
        # every client tree: a script may name the credential file ONLY as
        # "$CFG/.credentials.json" inside a KNOWN disposable config root. Any
        # other spelling — a path segment before it like
        # "$HOME/.claude/.credentials.json", or an unknown variable like
        # "$H/.credentials.json" where $H is the operator's real config — is a
        # leak.
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
                    f'a "$CFG/.credentials.json" presence check: {line.strip()!r}',
                )


class CredentialRuleBehaviourTests(unittest.TestCase):
    """The two credential rules, exercised against the shapes that defeated them.

    These run on strings, not on the tree, so they stay RED for the bypass even
    after someone deletes the offending file — the point is the rule, not the
    corpus.
    """

    # The three-line bypass, verbatim: a real-config directory in one variable,
    # the credential path built from it in a second, the copy naming neither.
    INDIRECTED_COPY = '\n'.join(
        (
            'H="$HOME/.claude"',
            'F="$H/.credentials.json"',
            'cp "$F" ./stolen.json',
        )
    )

    def test_variable_indirected_copy_is_caught(self):
        violations = credential_copy_violations(self.INDIRECTED_COPY)
        self.assertTrue(violations, "the three-line indirected copy passed")
        self.assertEqual(violations[-1][0], 3, "the copy line is not the one named")

    def test_indirection_through_several_hops_is_caught(self):
        text = '\n'.join(
            (
                'A="$HOME/.claude/.credentials.json"',
                'B="$A"',
                'C="$B"',
                'base64 "$C" > payload.txt',
            )
        )
        self.assertTrue(credential_copy_violations(text))

    def test_a_multi_line_prose_recipe_is_caught(self):
        # F18's shape: a runbook, not a script, so the strict script rule never
        # applies and the same-line rule was the only thing looking.
        text = '\n'.join(
            (
                "## Collecting the config",
                "",
                "1. Point a variable at the client config:",
                "",
                '       CRED="$HOME/.claude/.credentials.json"',
                "",
                "2. Keep a copy for the run:",
                "",
                '       cp "$CRED" ./saved.json',
            )
        )
        self.assertTrue(credential_copy_violations(text))

    def test_the_allowed_presence_check_is_still_allowed(self):
        text = '\n'.join(
            (
                'CFG="$BASE/cfg"',
                'if [ ! -f "$CFG/.credentials.json" ]; then',
                '  echo "provision it first" >&2',
                "fi",
            )
        )
        self.assertEqual(credential_copy_violations(text), ())

    def test_an_unknown_variable_is_not_a_presence_check(self):
        # The generic rule used to accept ANY variable, which is what made
        # `F="$H/.credentials.json"` look like provisioning.
        residue = ALLOWED_CREDENTIAL_REFERENCE.sub("", 'F="$H/.credentials.json"')
        self.assertIsNotNone(CREDENTIAL_FILE.search(residue))


if __name__ == "__main__":
    unittest.main()
