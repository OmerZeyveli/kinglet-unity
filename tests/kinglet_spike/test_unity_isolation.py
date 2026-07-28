"""test_unity_isolation.py -- The isolated-headless route and its copy boundary.

Every guard is EXECUTED here, never asserted as source text. The separateness
proof runs through the real `assert_isolated`; the copy runs through the real
`prepare_isolated_copy` against real directories, real symlinks and a real
fifo; the refusals run through the real `assert_headless_safe` with a
fabricated process table and the real `verify_project_editor` with a
fabricated `-version` stdout; the lease is the real `WorkspaceLease` on a real
directory. Only Unity itself is a double, scripted from artifacts captured
from real Unity runs on this host (see test_unity_routes.py).

Two rules shape this file.

FIRST: a refusal test must not be able to perform the act it forbids. Every
test whose subject is "this refuses" passes `exploding_factory`, which raises
if anything tries to launch. A refusal test that could start Unity has been a
real incident on this plan.

SECOND: the (st_dev, st_ino) branch of `assert_isolated` is the one a test on
an unprivileged host cannot reach with real filesystem objects -- creating a
bind mount needs root, and directories cannot be hardlinked. It is reached
through the `stat_reader` seam instead, so the branch and its refusal both
run rather than being taken on trust.
"""
from __future__ import annotations

import json
import os
import unittest
from dataclasses import replace
from pathlib import Path

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.unity import isolation, routes
from tools.kinglet_spike.unity.isolation import (
    COPIED_TREES,
    GENERATED_TREES,
    ISOLATION_MANIFEST_SCHEMA,
    assert_isolated,
    prepare_isolated_copy,
    verify_manifest,
)
from tools.kinglet_spike.unity.lease import WorkspaceLease, lease_path_for
from tools.kinglet_spike.unity.model import PROJECT_ID, RECEIPT_SCHEMA
from tools.kinglet_spike.unity.receipt import (
    unity_receipt_from_dict,
    validate_unity_receipt,
)

from .test_unity_routes import (
    COMPILE_LOG,
    EDITOR_VERSION,
    FAILED_XML,
    PASSED_XML,
    FakeUnity,
    empty_process_table,
    make_project,
    owning_table,
    version_stdout,
)

_REPO = Path(__file__).resolve().parents[2]
_CONTRACT = _REPO / "spikes/platform/unity/contracts/routes-v1.json"

# The synthetic stand-in for the open Editor's unsaved state. It lives under
# Library/ because that is where an open Editor's uncommitted, generated and
# scratch state actually lives -- an unsaved scene is never in Assets/ at all,
# which is precisely why a disk copy of the committed trees cannot carry it.
UNSAVED_SENTINEL = "KINGLET_UNSAVED_SENTINEL"


def exploding_factory(*args, **kwargs):
    raise AssertionError(
        "this test asserts a refusal; nothing may launch Unity on this path"
    )


def _write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


class _IsolationCase(unittest.TestCase):
    """A source project carrying the generated trees an open Editor leaves."""

    def setUp(self):
        import tempfile

        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)

        self.main = make_project(self.root / "main")
        # Everything an open Editor generates, plus a saved marker that MUST
        # survive the copy and an unsaved sentinel that must never reach it.
        _write(self.main / "Library" / "ArtifactDB", "binary-ish\n")
        _write(self.main / "Library" / "CurrentLayout.dwlt", UNSAVED_SENTINEL + "\n")
        _write(self.main / "Temp" / "UnityLockfile", "")
        _write(self.main / "Logs" / "AssetImportWorker0.log", UNSAVED_SENTINEL + "\n")
        _write(self.main / "obj" / "Debug" / "stale.dll", "build output\n")
        _write(self.main / "UserSettings" / "Layouts" / "default.dwlt", "layout\n")
        _write(self.main / ".kinglet" / "local" / "notes.txt", "host state\n")
        _write(self.main / "Assets" / "SAVED_MARKER.txt", "saved on disk\n")

        self.isolated = self.root / "isolated"
        self.raw = self.root / "raw"
        self.leases = self.root / "leases"
        self.editor = self.root / "Unity"
        self.editor.write_text("#!/bin/sh\n", encoding="utf-8")

    def prepare(self):
        return prepare_isolated_copy(self.main, self.isolated)

    def lease_files(self):
        if not self.leases.is_dir():
            return []
        return sorted(p.name for p in self.leases.glob("*.lease.json"))


# ---------------------------------------------------------------------------
# The copy boundary
# ---------------------------------------------------------------------------

class PrepareIsolatedCopyTests(_IsolationCase):

    def test_only_the_three_committed_trees_are_copied(self):
        self.prepare()
        self.assertEqual(
            sorted(p.name for p in self.isolated.iterdir()), sorted(COPIED_TREES)
        )

    def test_no_generated_tree_reaches_the_copy(self):
        self.prepare()
        for name in GENERATED_TREES + ("obj", "UserSettings", ".kinglet"):
            self.assertFalse(
                (self.isolated / name).exists(),
                f"{name} must never be copied into an isolated workspace",
            )

    def test_the_unsaved_sentinel_is_never_imported(self):
        manifest = self.prepare()
        for current, _dirs, files in os.walk(self.isolated):
            for name in files:
                text = (Path(current) / name).read_text(encoding="utf-8", errors="replace")
                self.assertNotIn(UNSAVED_SENTINEL, text)
        self.assertEqual(
            [], [item.path for item in manifest.files if "Library" in item.path]
        )

    def test_the_saved_marker_does_survive_the_copy(self):
        # The negative above is worthless without this: a copy that copied
        # nothing at all would satisfy it.
        manifest = self.prepare()
        self.assertEqual(
            "saved on disk\n",
            (self.isolated / "Assets" / "SAVED_MARKER.txt").read_text(encoding="utf-8"),
        )
        self.assertIn(
            "Assets/SAVED_MARKER.txt", [item.path for item in manifest.files]
        )

    def test_the_copy_has_a_distinct_canonical_path_and_lease_identity(self):
        manifest = self.prepare()
        self.assertNotEqual(
            os.path.realpath(self.main), os.path.realpath(self.isolated)
        )
        self.assertNotEqual(manifest.main_path_hash, manifest.isolated_path_hash)
        self.assertNotEqual(
            lease_path_for(self.main, self.leases),
            lease_path_for(self.isolated, self.leases),
        )

    def test_the_manifest_digests_every_copied_file(self):
        manifest = self.prepare()
        self.assertEqual(ISOLATION_MANIFEST_SCHEMA, manifest.schema)
        on_disk = {
            str(Path(current).relative_to(self.isolated) / name)
            for current, _dirs, files in os.walk(self.isolated)
            for name in files
        }
        self.assertEqual(on_disk, {item.path for item in manifest.files})
        for item in manifest.files:
            self.assertEqual(64, len(item.sha256))
            self.assertEqual((self.isolated / item.path).stat().st_size, item.size)

    def test_the_copy_creates_no_library_temp_or_log_path(self):
        # The route, not this function, decides where the isolated run writes.
        self.prepare()
        for name in ("Library", "Temp", "Logs"):
            self.assertFalse((self.isolated / name).exists())

    def test_a_symlink_escaping_the_source_is_refused(self):
        outside = _write(self.root / "outside" / "secret.cs", "// not ours\n")
        os.symlink(outside, self.main / "Assets" / "escape.cs")
        with self.assertRaises(EvidenceError) as caught:
            self.prepare()
        self.assertEqual("E_UNITY_ISOLATION_SYMLINK", caught.exception.code)
        self.assertFalse((self.isolated / "Assets" / "escape.cs").exists())

    def test_a_symlink_inside_the_source_is_materialized_not_linked(self):
        os.symlink(
            self.main / "Assets" / "SAVED_MARKER.txt",
            self.main / "Assets" / "alias.txt",
        )
        self.prepare()
        copied = self.isolated / "Assets" / "alias.txt"
        self.assertFalse(copied.is_symlink())
        self.assertEqual("saved on disk\n", copied.read_text(encoding="utf-8"))

    def test_the_finished_copy_contains_no_symlink_at_all(self):
        os.symlink(
            self.main / "Assets" / "SAVED_MARKER.txt",
            self.main / "Assets" / "alias.txt",
        )
        self.prepare()
        for current, dirs, files in os.walk(self.isolated):
            for name in dirs + files:
                self.assertFalse((Path(current) / name).is_symlink())

    def test_a_symlink_loop_is_refused_not_followed(self):
        # MEASURED while mutation-testing this file: with the visited-set
        # check removed the copy is STILL refused -- but only at depth 41,
        # where the kernel's own symlink-resolution limit makes the path stop
        # resolving and the link reads as dangling. By then forty levels of
        # `Assets/loop/loop/...` have been created in the destination and the
        # source has been re-read forty times. So the assertion has to be that
        # the loop was detected AS a loop, not merely that something
        # eventually said no; the path in the message is what proves the
        # difference.
        os.symlink(self.main / "Assets", self.main / "Assets" / "loop")
        with self.assertRaises(EvidenceError) as caught:
            self.prepare()
        self.assertEqual("E_UNITY_ISOLATION_SYMLINK", caught.exception.code)
        self.assertIn("already being copied", caught.exception.detail)
        self.assertEqual("Assets/loop", caught.exception.detail.split(" ")[0])

    def test_a_dangling_symlink_pointing_outside_is_refused(self):
        os.symlink(self.root / "nowhere.cs", self.main / "Assets" / "dangling.cs")
        with self.assertRaises(EvidenceError) as caught:
            self.prepare()
        self.assertEqual("E_UNITY_ISOLATION_SYMLINK", caught.exception.code)

    def test_a_dangling_symlink_pointing_inside_is_named_as_dangling(self):
        # This is the case the escape check CANNOT catch -- the target is
        # inside the source, it just is not there. Without its own branch the
        # copier reaches the "neither file nor directory" arm and reports the
        # link as an unsupported special file, which sends a reader looking
        # for a fifo. Asserting the message, not only the code, is what makes
        # the branch load-bearing.
        os.symlink(self.main / "Assets" / "gone.cs", self.main / "Assets" / "stale.cs")
        with self.assertRaises(EvidenceError) as caught:
            self.prepare()
        self.assertEqual("E_UNITY_ISOLATION_SYMLINK", caught.exception.code)
        self.assertIn("dangling", caught.exception.detail)

    def test_a_special_file_is_refused(self):
        os.mkfifo(self.main / "Assets" / "pipe")
        with self.assertRaises(EvidenceError) as caught:
            self.prepare()
        self.assertEqual("E_UNITY_ISOLATION_UNSUPPORTED", caught.exception.code)

    def test_a_destination_inside_the_source_is_refused_without_writing(self):
        nested = self.main / "isolated-copy"
        with self.assertRaises(EvidenceError) as caught:
            prepare_isolated_copy(self.main, nested)
        self.assertEqual("E_UNITY_NOT_ISOLATED", caught.exception.code)
        self.assertFalse(nested.exists(), "the source workspace was written into")

    def test_a_destination_containing_the_source_is_refused(self):
        with self.assertRaises(EvidenceError) as caught:
            prepare_isolated_copy(self.main, self.root)
        self.assertEqual("E_UNITY_NOT_ISOLATED", caught.exception.code)

    def test_copying_a_project_onto_itself_is_refused(self):
        with self.assertRaises(EvidenceError) as caught:
            prepare_isolated_copy(self.main, self.main)
        self.assertEqual("E_UNITY_NOT_ISOLATED", caught.exception.code)

    def test_a_symlinked_alias_of_the_source_is_refused(self):
        alias = self.root / "main-alias"
        os.symlink(self.main, alias)
        with self.assertRaises(EvidenceError) as caught:
            prepare_isolated_copy(self.main, alias)
        self.assertEqual("E_UNITY_NOT_ISOLATED", caught.exception.code)

    def test_a_non_empty_destination_is_refused(self):
        _write(self.isolated / "Library" / "leftover", "from a previous run\n")
        with self.assertRaises(EvidenceError) as caught:
            self.prepare()
        self.assertEqual("E_UNITY_ISOLATION_DESTINATION", caught.exception.code)

    def test_an_empty_destination_directory_is_accepted(self):
        self.isolated.mkdir(parents=True)
        self.assertEqual(3, len(self.prepare().trees))

    def test_a_destination_that_is_a_file_is_refused(self):
        _write(self.isolated, "not a directory\n")
        with self.assertRaises(EvidenceError) as caught:
            self.prepare()
        self.assertEqual("E_UNITY_ISOLATION_DESTINATION", caught.exception.code)

    def test_a_source_missing_a_committed_tree_is_refused(self):
        import shutil

        shutil.rmtree(self.main / "Packages")
        with self.assertRaises(EvidenceError) as caught:
            self.prepare()
        self.assertEqual("E_UNITY_ISOLATION_INCOMPLETE", caught.exception.code)

    def test_a_source_that_is_not_a_directory_is_refused(self):
        with self.assertRaises(EvidenceError) as caught:
            prepare_isolated_copy(self.root / "absent", self.isolated)
        self.assertEqual("E_UNITY_NOT_ISOLATED", caught.exception.code)


class VerifyManifestTests(_IsolationCase):

    def test_an_untouched_copy_verifies(self):
        manifest = self.prepare()
        verify_manifest(self.isolated, manifest)  # must not raise

    def test_an_edited_file_is_caught(self):
        manifest = self.prepare()
        (self.isolated / "Assets" / "SAVED_MARKER.txt").write_text("tampered\n", encoding="utf-8")
        with self.assertRaises(EvidenceError) as caught:
            verify_manifest(self.isolated, manifest)
        self.assertEqual("E_UNITY_ISOLATION_MANIFEST", caught.exception.code)
        self.assertIn("Assets/SAVED_MARKER.txt", caught.exception.detail)

    def test_an_added_file_is_caught(self):
        manifest = self.prepare()
        _write(self.isolated / "Assets" / "smuggled.cs", "// extra\n")
        with self.assertRaises(EvidenceError) as caught:
            verify_manifest(self.isolated, manifest)
        self.assertEqual("E_UNITY_ISOLATION_MANIFEST", caught.exception.code)

    def test_a_removed_file_is_caught(self):
        manifest = self.prepare()
        (self.isolated / "Assets" / "SAVED_MARKER.txt").unlink()
        with self.assertRaises(EvidenceError) as caught:
            verify_manifest(self.isolated, manifest)
        self.assertEqual("E_UNITY_ISOLATION_MANIFEST", caught.exception.code)

    def test_the_manifest_records_the_inode_identity_the_decision_rests_on(self):
        # ROUND-1 REVIEW: the manifest published only the two path hashes, and
        # a path hash cannot express the one check `realpath` cannot make. A
        # bind mount yields two DIFFERENT canonical paths -- hence two
        # different path hashes -- for ONE directory, so a manifest carrying
        # only path hashes validates cleanly for exactly the forgery
        # `assert_isolated` step 4 refuses. These two fields close that
        # asymmetry, and they must be the digests of the pairs that were
        # actually compared.
        manifest = self.prepare()
        main_stat = os.stat(self.main)
        iso_stat = os.stat(self.isolated)
        self.assertEqual(
            isolation.workspace_identity(main_stat.st_dev, main_stat.st_ino),
            manifest.main_identity,
        )
        self.assertEqual(
            isolation.workspace_identity(iso_stat.st_dev, iso_stat.st_ino),
            manifest.isolated_identity,
        )
        self.assertNotEqual(manifest.main_identity, manifest.isolated_identity)

    def test_the_identity_digest_is_recomputable_by_a_reader(self):
        # Unsalted and domain-separated on purpose: a reader holding the
        # artifact and the two directories must be able to check it. A random
        # salt would make the field unverifiable, which defeats its purpose.
        first = isolation.workspace_identity(66, 12345)
        self.assertEqual(first, isolation.workspace_identity(66, 12345))
        self.assertNotEqual(first, isolation.workspace_identity(66, 12346))
        self.assertNotEqual(first, isolation.workspace_identity(67, 12345))
        # Domain-separated: it is not a bare digest of the two numbers.
        import hashlib

        self.assertNotEqual(
            hashlib.sha256(b"66\x0012345").hexdigest(), first
        )

    def test_a_bind_mount_forgery_is_refused_by_the_manifest_alone(self):
        # THE case round-1 review named. Two distinct canonical paths, two
        # distinct path hashes, one physical directory. Only the identity
        # fields can see it, so this asserts the refusal comes from THEM: the
        # path hashes in this manifest are genuinely different.
        manifest = self.prepare()
        forged = replace(manifest, isolated_identity=manifest.main_identity)
        self.assertNotEqual(forged.main_path_hash, forged.isolated_path_hash)
        with self.assertRaises(EvidenceError) as caught:
            verify_manifest(self.isolated, forged)
        self.assertEqual("E_UNITY_ISOLATION_MANIFEST", caught.exception.code)
        self.assertIn("same physical directory identity", caught.exception.detail)

    def test_a_manifest_naming_one_workspace_twice_is_refused(self):
        from dataclasses import replace

        manifest = self.prepare()
        forged = replace(manifest, isolated_path_hash=manifest.main_path_hash)
        with self.assertRaises(EvidenceError) as caught:
            verify_manifest(self.isolated, forged)
        self.assertEqual("E_UNITY_ISOLATION_MANIFEST", caught.exception.code)

    # --- FINAL whole-branch review, IMPORTANT 9: verify_manifest walked the
    #     CALLER-SUPPLIED manifest.trees, so a manifest could narrow the
    #     verification of itself. `trees=()` verified nothing and succeeded.

    def test_a_manifest_that_names_no_trees_does_not_verify_by_walking_nothing(self):
        from dataclasses import replace

        manifest = self.prepare()
        forged = replace(manifest, trees=(), files=(), tree_sha256=isolation._tree_digest(()))
        with self.assertRaises(EvidenceError) as caught:
            verify_manifest(self.isolated, forged)
        self.assertEqual("E_UNITY_ISOLATION_MANIFEST", caught.exception.code)

    def test_a_manifest_that_drops_one_tree_cannot_hide_that_trees_content(self):
        # Sharper than trees=(): Assets is verified, Packages is simply not
        # looked at, so a tampered Packages tree passed. The refusal must come
        # from the tree SET, before any digest comparison can be arranged to
        # agree.
        from dataclasses import replace

        manifest = self.prepare()
        kept = tuple(item for item in manifest.files if not item.path.startswith("Packages/"))
        forged = replace(
            manifest,
            trees=("Assets", "ProjectSettings"),
            files=kept,
            tree_sha256=isolation._tree_digest(kept),
        )
        with self.assertRaises(EvidenceError) as caught:
            verify_manifest(self.isolated, forged)
        self.assertEqual("E_UNITY_ISOLATION_MANIFEST", caught.exception.code)
        self.assertIn("narrows its own scope", caught.exception.detail)

    def test_a_manifest_with_a_forged_tree_digest_is_refused(self):
        from dataclasses import replace

        manifest = self.prepare()
        forged = replace(manifest, tree_sha256="0" * 64)
        with self.assertRaises(EvidenceError) as caught:
            verify_manifest(self.isolated, forged)
        self.assertEqual("E_UNITY_ISOLATION_MANIFEST", caught.exception.code)

    def test_a_symlink_planted_after_the_copy_is_caught(self):
        manifest = self.prepare()
        os.symlink(
            self.main / "Library" / "ArtifactDB",
            self.isolated / "Assets" / "backdoor",
        )
        with self.assertRaises(EvidenceError) as caught:
            verify_manifest(self.isolated, manifest)
        self.assertEqual("E_UNITY_ISOLATION_SYMLINK", caught.exception.code)


# ---------------------------------------------------------------------------
# Separateness
# ---------------------------------------------------------------------------

class AssertIsolatedTests(_IsolationCase):

    def test_two_real_directories_produce_a_boundary(self):
        self.prepare()
        boundary = assert_isolated(self.main, self.isolated)
        self.assertNotEqual(boundary.main_path_hash, boundary.isolated_path_hash)

    def test_one_directory_under_two_canonical_paths_is_not_isolated(self):
        # THE bind-mount shape: distinct canonical paths, distinct names,
        # neither nested in the other -- and one physical directory. No
        # comparison of path strings can see it; (st_dev, st_ino) can.
        self.prepare()
        real = os.stat

        def same_inode(path):
            info = real(path)
            if os.path.realpath(path) in (
                os.path.realpath(self.main), os.path.realpath(self.isolated)
            ):
                return os.stat_result((
                    info.st_mode, 4242, 77, info.st_nlink, info.st_uid,
                    info.st_gid, info.st_size, info.st_atime, info.st_mtime,
                    info.st_ctime,
                ))
            return info

        with self.assertRaises(EvidenceError) as caught:
            assert_isolated(self.main, self.isolated, stat_reader=same_inode)
        self.assertEqual("E_UNITY_NOT_ISOLATED", caught.exception.code)
        self.assertIn("device, inode", caught.exception.detail)

    def test_an_unreadable_workspace_identity_refuses_rather_than_permits(self):
        self.prepare()

        def cannot_stat(path):
            raise PermissionError(13, "Permission denied")

        with self.assertRaises(EvidenceError) as caught:
            assert_isolated(self.main, self.isolated, stat_reader=cannot_stat)
        self.assertEqual("E_UNITY_NOT_ISOLATED", caught.exception.code)
        # The MESSAGE, not only the code: an identity this function could not
        # read must refuse AS an unreadable identity. Any other refusal here
        # would mean the ambiguity branch is dead and something downstream is
        # accidentally covering for it.
        self.assertIn("cannot stat", caught.exception.detail)
        self.assertIn("main", caught.exception.detail)

    def test_a_copy_whose_library_is_the_main_library_is_not_isolated(self):
        self.prepare()
        os.symlink(self.main / "Library", self.isolated / "Library")
        with self.assertRaises(EvidenceError) as caught:
            assert_isolated(self.main, self.isolated)
        self.assertEqual("E_UNITY_NOT_ISOLATED", caught.exception.code)
        self.assertIn("Library", caught.exception.detail)

    def test_a_copy_whose_temp_escapes_the_copy_is_not_isolated(self):
        self.prepare()
        (self.root / "elsewhere").mkdir()
        os.symlink(self.root / "elsewhere", self.isolated / "Temp")
        with self.assertRaises(EvidenceError) as caught:
            assert_isolated(self.main, self.isolated)
        self.assertEqual("E_UNITY_NOT_ISOLATED", caught.exception.code)
        self.assertIn("Temp", caught.exception.detail)

    def test_a_copy_with_its_own_library_stays_isolated(self):
        # The positive control for the two tests above: a real, separate
        # Library must not trip them.
        self.prepare()
        _write(self.isolated / "Library" / "ArtifactDB", "its own\n")
        assert_isolated(self.main, self.isolated)

    def test_a_missing_workspace_is_not_isolated(self):
        with self.assertRaises(EvidenceError) as caught:
            assert_isolated(self.main, self.root / "never-created")
        self.assertEqual("E_UNITY_NOT_ISOLATED", caught.exception.code)

    def test_a_nested_workspace_is_not_isolated(self):
        nested = self.main / "nested"
        nested.mkdir()
        with self.assertRaises(EvidenceError) as caught:
            assert_isolated(self.main, nested)
        self.assertEqual("E_UNITY_NOT_ISOLATED", caught.exception.code)


# ---------------------------------------------------------------------------
# The route
# ---------------------------------------------------------------------------

class IsolatedHeadlessRouteTests(_IsolationCase):

    def setUp(self):
        super().setUp()
        self.manifest = self.prepare()

    def run_route(self, fake, **overrides):
        kwargs = dict(
            manifest=self.manifest,
            process_table_provider=empty_process_table,
            windows=False,
            run_version_flag=version_stdout(),
            process_factory=fake.factory if hasattr(fake, "factory") else fake,
            env={"PATH": "/usr/bin"},
            lease_dir=self.leases,
        )
        kwargs.update(overrides)
        return routes.run_isolated_headless(
            self.editor, self.main, self.isolated, self.raw, **kwargs
        )

    # -- the passing run ---------------------------------------------------

    def test_a_passing_isolated_run_produces_a_valid_receipt(self):
        receipt = self.run_route(FakeUnity(exit_code=0, results_text=PASSED_XML))
        self.assertEqual(routes.ISOLATED_HEADLESS_ROUTE, receipt.route)
        self.assertEqual(RECEIPT_SCHEMA, receipt.schema)
        self.assertEqual(PROJECT_ID, receipt.project_id)
        self.assertEqual(EDITOR_VERSION, receipt.unity_version)
        self.assertEqual("pass", receipt.compile.status)
        self.assertEqual("pass", receipt.tests.status)
        self.assertEqual(1, receipt.tests.passed)
        self.assertFalse(receipt.ready)
        self.assertFalse(receipt.collision_refused)
        self.assertFalse(receipt.active_lease)
        self.assertEqual((), receipt.descendant_pids)
        self.assertEqual((), validate_unity_receipt(receipt))

    def test_the_receipt_round_trips_through_the_frozen_parser(self):
        receipt = self.run_route(FakeUnity())
        again = unity_receipt_from_dict(routes.receipt_to_dict(receipt))
        self.assertEqual(receipt, again)
        self.assertEqual((), validate_unity_receipt(again))

    def test_the_receipt_cites_the_isolation_manifest(self):
        receipt = self.run_route(FakeUnity())
        self.assertEqual(
            (
                f"{routes.ARTIFACT_PREFIX}/{routes.ISOLATED_SUMMARY_NAME}",
                f"{routes.ARTIFACT_PREFIX}/{routes.ISOLATED_MANIFEST_NAME}",
            ),
            receipt.artifacts,
        )
        payload = json.loads((self.raw / routes.ISOLATED_MANIFEST_NAME).read_text())
        self.assertEqual(ISOLATION_MANIFEST_SCHEMA, payload["schema"])
        self.assertNotEqual(payload["main_path_hash"], payload["isolated_path_hash"])
        self.assertIn(
            "Assets/SAVED_MARKER.txt", [item["path"] for item in payload["files"]]
        )
        # The PUBLISHED artifact must carry the inode identities, not only the
        # lease keys -- a reader checking the file is the whole point of it.
        main_stat = os.stat(self.main)
        iso_stat = os.stat(self.isolated)
        self.assertEqual(
            isolation.workspace_identity(main_stat.st_dev, main_stat.st_ino),
            payload["main_identity"],
        )
        self.assertEqual(
            isolation.workspace_identity(iso_stat.st_dev, iso_stat.st_ino),
            payload["isolated_identity"],
        )
        self.assertNotEqual(payload["main_identity"], payload["isolated_identity"])

    def test_the_summary_publishes_the_inode_identities_too(self):
        self.run_route(FakeUnity())
        summary = json.loads((self.raw / routes.ISOLATED_SUMMARY_NAME).read_text())
        self.assertEqual(self.manifest.main_identity, summary["main_identity"])
        self.assertEqual(self.manifest.isolated_identity, summary["isolated_identity"])
        self.assertNotEqual(summary["main_identity"], summary["isolated_identity"])

    def test_a_manifest_whose_identities_do_not_match_the_boundary_is_refused(self):
        # Path hashes matching is not enough: a workspace swapped between the
        # copy and the run keeps its path and changes its inode.
        forged = replace(self.manifest, isolated_identity="e" * 64)
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(exploding_factory, manifest=forged)
        self.assertEqual("E_UNITY_ISOLATION_MANIFEST", caught.exception.code)

    def test_the_manifest_artifact_carries_no_machine_path(self):
        # It is published beside a receipt, so it must carry identities, not
        # anybody's home directory.
        self.run_route(FakeUnity())
        text = (self.raw / routes.ISOLATED_MANIFEST_NAME).read_text(encoding="utf-8")
        self.assertNotIn(str(self.main), text)
        self.assertNotIn(str(self.isolated), text)

    def test_unity_is_pointed_at_the_copy_and_writes_outside_both_workspaces(self):
        fake = FakeUnity()
        self.run_route(fake)
        argv = fake.argv
        self.assertEqual(
            str(self.isolated.resolve()), argv[argv.index("-projectPath") + 1]
        )
        self.assertIn("-runTests", argv)
        self.assertNotIn("-quit", argv)
        for flag in ("-testResults", "-logFile"):
            target = Path(argv[argv.index(flag) + 1])
            self.assertFalse(target.is_relative_to(self.main))
            self.assertFalse(target.is_relative_to(self.isolated))
        self.assertEqual(self.isolated.resolve(), Path(fake.cwd))

    def test_the_summary_records_the_two_workspace_identities_and_main_owner(self):
        self.run_route(FakeUnity(), process_table_provider=owning_table(self.main))
        summary = json.loads((self.raw / routes.ISOLATED_SUMMARY_NAME).read_text())
        self.assertEqual(routes.ISOLATED_HEADLESS_ROUTE, summary["route"])
        self.assertEqual("confirmed", summary["main_owner"])
        self.assertNotEqual(summary["main_path_hash"], summary["isolated_path_hash"])
        self.assertEqual(self.manifest.tree_sha256, summary["isolated_tree_sha256"])

    # -- the lease ---------------------------------------------------------

    def test_only_the_isolated_workspace_is_leased(self):
        seen = {}

        class Watcher(FakeUnity):
            def wait(inner, timeout_seconds):
                seen["files"] = sorted(p.name for p in self.leases.glob("*.lease.json"))
                return super().wait(timeout_seconds)

        self.run_route(Watcher())
        self.assertEqual([lease_path_for(self.isolated, self.leases).name], seen["files"])
        self.assertNotIn(lease_path_for(self.main, self.leases).name, seen["files"])

    def test_a_lease_held_on_main_does_not_block_the_isolated_run(self):
        # The plan's second constraint, executed: one lease per PHYSICAL
        # workspace, and a lease on main is not a lease on the copy.
        held = WorkspaceLease.acquire(
            self.main, route="same-project-headless", lease_dir=self.leases
        )
        try:
            receipt = self.run_route(FakeUnity())
            self.assertEqual("pass", receipt.tests.status)
            self.assertTrue(held.is_held())
        finally:
            held.release()

    def test_the_isolated_lease_is_released_on_every_path(self):
        self.run_route(FakeUnity())
        self.assertEqual([], self.lease_files())
        with self.assertRaises(EvidenceError):
            self.run_route(FakeUnity(exit_code=0, results_text=None))
        self.assertEqual([], self.lease_files())

    # -- separate outputs --------------------------------------------------

    def test_a_run_directory_beneath_main_is_refused_and_launches_nothing(self):
        with self.assertRaises(EvidenceError) as caught:
            routes.run_isolated_headless(
                self.editor, self.main, self.isolated,
                self.main / "raw",
                manifest=self.manifest,
                process_table_provider=empty_process_table, windows=False,
                run_version_flag=version_stdout(),
                process_factory=exploding_factory,
                env={"PATH": "/usr/bin"}, lease_dir=self.leases,
            )
        self.assertEqual("E_UNITY_ISOLATION_BREACH", caught.exception.code)
        self.assertEqual([], self.lease_files())

    def test_a_run_directory_beneath_the_copy_is_refused(self):
        with self.assertRaises(EvidenceError) as caught:
            routes.run_isolated_headless(
                self.editor, self.main, self.isolated,
                self.isolated / "Assets" / "raw",
                manifest=self.manifest,
                process_table_provider=empty_process_table, windows=False,
                run_version_flag=version_stdout(),
                process_factory=exploding_factory,
                env={"PATH": "/usr/bin"}, lease_dir=self.leases,
            )
        self.assertEqual("E_UNITY_ISOLATION_BREACH", caught.exception.code)

    def test_a_lease_directory_beneath_main_is_refused(self):
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(
                exploding_factory, lease_dir=self.main / "Library" / "leases"
            )
        self.assertEqual("E_UNITY_ISOLATION_BREACH", caught.exception.code)

    # -- refusals ----------------------------------------------------------

    def test_an_owned_copy_raises_and_never_launches(self):
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(
                exploding_factory, process_table_provider=owning_table(self.isolated)
            )
        self.assertEqual("E_UNITY_OWNED", caught.exception.code)
        self.assertEqual([], self.lease_files())

    def test_an_unresolved_copy_ownership_raises_and_never_launches(self):
        _write(self.isolated / "Temp" / "UnityLockfile", "")
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(exploding_factory)
        self.assertEqual("E_UNITY_OWNER_UNKNOWN", caught.exception.code)

    def test_this_route_never_emits_a_collision_refusal_receipt(self):
        # collision_refused is same-project-headless's probe; routes-v1.json
        # rejects it here, so an ownership refusal has no honest receipt.
        for provider in (owning_table(self.isolated),):
            with self.assertRaises(EvidenceError):
                self.run_route(exploding_factory, process_table_provider=provider)
        self.assertFalse((self.raw / routes.ISOLATED_SUMMARY_NAME).exists())

    def test_an_editor_that_does_not_match_the_copy_is_refused(self):
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(
                exploding_factory, run_version_flag=version_stdout("6000.0.68f1")
            )
        self.assertEqual("E_UNITY_VERSION", caught.exception.code)

    def test_a_manifest_that_does_not_match_the_copy_is_refused(self):
        _write(self.isolated / "Assets" / "smuggled.cs", "// added later\n")
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(exploding_factory)
        self.assertEqual("E_UNITY_ISOLATION_MANIFEST", caught.exception.code)

    def test_a_manifest_describing_other_workspaces_is_refused(self):
        from dataclasses import replace

        forged = replace(self.manifest, main_path_hash="f" * 64)
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(exploding_factory, manifest=forged)
        self.assertEqual("E_UNITY_ISOLATION_MANIFEST", caught.exception.code)

    def test_a_copy_wired_back_into_main_is_refused_before_launch(self):
        os.symlink(self.main / "Library", self.isolated / "Library")
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(exploding_factory)
        self.assertEqual("E_UNITY_NOT_ISOLATED", caught.exception.code)

    def test_running_against_main_itself_is_refused(self):
        with self.assertRaises(EvidenceError) as caught:
            routes.run_isolated_headless(
                self.editor, self.main, self.main, self.raw,
                process_table_provider=empty_process_table, windows=False,
                run_version_flag=version_stdout(),
                process_factory=exploding_factory,
                env={"PATH": "/usr/bin"}, lease_dir=self.leases,
            )
        self.assertEqual("E_UNITY_NOT_ISOLATED", caught.exception.code)

    # -- concurrency with the main workspace -------------------------------

    def test_an_open_main_workspace_does_not_block_the_isolated_run(self):
        receipt = self.run_route(
            FakeUnity(), process_table_provider=owning_table(self.main)
        )
        self.assertEqual("pass", receipt.tests.status)

    def test_requiring_an_open_main_refuses_when_nothing_holds_it(self):
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(exploding_factory, require_main_owner=True)
        self.assertEqual("E_UNITY_MAIN_NOT_OPEN", caught.exception.code)
        self.assertEqual([], self.lease_files())

    def test_requiring_an_open_main_is_satisfied_by_a_confirmed_owner(self):
        receipt = self.run_route(
            FakeUnity(),
            require_main_owner=True,
            process_table_provider=owning_table(self.main),
        )
        self.assertEqual("pass", receipt.tests.status)

    def test_requiring_an_open_main_refuses_an_unresolved_owner(self):
        _write(self.main / "Temp" / "UnityLockfile", "")
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(exploding_factory, require_main_owner=True)
        self.assertEqual("E_UNITY_MAIN_NOT_OPEN", caught.exception.code)

    # -- the main workspace is left alone ----------------------------------

    def test_a_run_that_writes_into_main_is_refused_even_when_tests_pass(self):
        class Vandal(FakeUnity):
            def factory(inner, argv, **kwargs):
                started = super().factory(argv, **kwargs)
                _write(self.main / "Assets" / "INJECTED.cs", "// from the copy\n")
                return started

        with self.assertRaises(EvidenceError) as caught:
            self.run_route(Vandal())
        self.assertEqual("E_UNITY_ISOLATION_BREACH", caught.exception.code)
        self.assertEqual([], self.lease_files())

    def test_a_silent_upgrade_of_the_main_pinned_version_is_refused(self):
        class Upgrader(FakeUnity):
            def factory(inner, argv, **kwargs):
                started = super().factory(argv, **kwargs)
                _write(
                    self.main / "ProjectSettings" / "ProjectVersion.txt",
                    "m_EditorVersion: 6000.0.68f1\n"
                    "m_EditorVersionWithRevision: 6000.0.68f1 (deadbeef)\n",
                )
                return started

        with self.assertRaises(EvidenceError) as caught:
            self.run_route(Upgrader())
        self.assertEqual("E_UNITY_ISOLATION_BREACH", caught.exception.code)

    def test_generated_state_under_main_does_not_trip_the_guard(self):
        # The positive control: an open main Editor churns its own Library and
        # Temp constantly, and that must not be read as a breach.
        class Churner(FakeUnity):
            def factory(inner, argv, **kwargs):
                started = super().factory(argv, **kwargs)
                _write(self.main / "Library" / "ArtifactDB", "rewritten\n")
                _write(self.main / "Temp" / "scratch", "busy\n")
                _write(self.main / "Logs" / "shader.log", "compiling\n")
                return started

        self.assertEqual("pass", self.run_route(Churner()).tests.status)

    # -- cleanup and the disjoint exit codes -------------------------------

    def test_cleanup_runs_on_a_passing_run(self):
        fake = FakeUnity()
        self.run_route(fake)
        self.assertEqual(["start", "wait", "cancel"], fake.recorder)

    def test_cleanup_runs_when_the_outcome_cannot_be_established(self):
        fake = FakeUnity(exit_code=0, results_text=None)
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(fake)
        self.assertEqual("E_UNITY_RESULTS_MISSING", caught.exception.code)
        self.assertIn("cancel", fake.recorder)
        self.assertEqual([], self.lease_files())

    def test_cleanup_runs_on_a_timeout(self):
        fake = FakeUnity(exit_code=None, results_text=None)
        with self.assertRaises(EvidenceError):
            self.run_route(fake)
        self.assertEqual(["start", "wait", "cancel"], fake.recorder)

    def test_a_surviving_process_is_reported_not_swallowed(self):
        # An isolated copy has a COLD Library by construction, which is the
        # measured condition under which Unity orphans a Roslyn server and a
        # package-manager server. This route is the likeliest to leak, so a
        # survivor must reach the receipt and fail validation there.
        receipt = self.run_route(FakeUnity(survivors=(31337,)))
        self.assertEqual((31337,), receipt.descendant_pids)
        locations = [d.location for d in validate_unity_receipt(receipt)]
        self.assertIn("descendant_pids", locations)

    def test_a_compile_failure_in_the_copy_reads_as_a_compile_failure(self):
        receipt = self.run_route(
            FakeUnity(exit_code=1, results_text=None, log_text=COMPILE_LOG)
        )
        self.assertEqual("fail", receipt.compile.status)
        self.assertGreaterEqual(receipt.compile.errors, 1)
        self.assertEqual("not-run", receipt.tests.status)
        self.assertEqual((), validate_unity_receipt(receipt))

    def test_a_test_failure_in_the_copy_reads_as_a_test_failure(self):
        receipt = self.run_route(FakeUnity(exit_code=2, results_text=FAILED_XML))
        self.assertEqual("pass", receipt.compile.status)
        self.assertEqual("fail", receipt.tests.status)
        self.assertEqual((), validate_unity_receipt(receipt))

    def test_a_stale_lockfile_in_the_copy_blocks_a_passing_claim(self):
        with self.assertRaises(EvidenceError) as caught:
            self.run_route(FakeUnity(leaves_lockfile=self.isolated))
        self.assertEqual("E_UNITY_STALE_LOCK", caught.exception.code)

    def test_the_launch_path_binds_the_lease_to_what_it_launched(self):
        from tools.kinglet_spike.unity.lease import read_lease

        bound = {}

        class Binder(FakeUnity):
            def wait(inner, timeout_seconds):
                record = read_lease(lease_path_for(self.isolated, self.leases))
                bound["pid"] = record.pid
                bound["pgid"] = record.pgid
                return super().wait(timeout_seconds)

        self.run_route(Binder(pid=5150, pgid=5150))
        self.assertEqual(5150, bound["pid"])
        self.assertEqual(5150, bound["pgid"])


class ContractBindingTests(unittest.TestCase):
    """The route name is not a literal this module gets to choose alone."""

    def test_the_route_name_matches_the_frozen_contract(self):
        contract = json.loads(_CONTRACT.read_text(encoding="utf-8"))
        self.assertIn(routes.ISOLATED_HEADLESS_ROUTE, contract["routes"])
        self.assertIn(routes.ISOLATED_HEADLESS_ROUTE, contract["executing_routes"])

    def test_the_route_name_matches_the_frozen_model(self):
        from tools.kinglet_spike.unity.model import EXECUTING_ROUTES, ROUTES

        self.assertIn(routes.ISOLATED_HEADLESS_ROUTE, ROUTES)
        self.assertIn(routes.ISOLATED_HEADLESS_ROUTE, EXECUTING_ROUTES)

    def test_the_isolated_argv_differs_from_the_same_project_argv_only_in_paths(self):
        # "the same batchmode command and test parser against the isolated
        # path" -- so the two argvs must be the same shape, not merely similar.
        editor = Path("/e/Unity")
        same = routes._headless_argv(
            editor, Path("/p"), Path("/r/results.xml"), Path("/r/log.txt")
        )
        isolated = routes._isolated_argv(
            editor, Path("/p"), Path("/r/results.xml"), Path("/r/log.txt")
        )
        self.assertEqual(same, isolated)

    def test_the_isolation_module_names_only_committed_trees(self):
        self.assertEqual(("Assets", "Packages", "ProjectSettings"), COPIED_TREES)
        for name in GENERATED_TREES:
            self.assertNotIn(name, COPIED_TREES)
        self.assertIsNot(isolation.prepare_isolated_copy, None)


if __name__ == "__main__":
    unittest.main()
