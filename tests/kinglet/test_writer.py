import errno
import importlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

from tools.kinglet_build.renderers import RenderedFile


class WriterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)
        self.destination = self.root / "product"

    def writer(self):
        specification = importlib.util.find_spec("tools.kinglet_build.writer")
        self.assertIsNotNone(
            specification,
            "tools.kinglet_build.writer must implement the write boundary",
        )
        return importlib.import_module("tools.kinglet_build.writer")

    @staticmethod
    def rendered(
        path: str,
        content: bytes,
        *source_ids: str,
    ) -> RenderedFile:
        return RenderedFile(
            path=PurePosixPath(path),
            content=content,
            source_ids=source_ids,
        )

    def snapshot(self, root: Path) -> tuple[tuple[str, bytes, int], ...]:
        if not root.exists():
            return ()
        return tuple(
            (
                path.relative_to(root).as_posix(),
                path.read_bytes(),
                path.stat().st_mode & 0o777,
            )
            for path in sorted(root.rglob("*"), key=lambda item: item.as_posix())
            if path.is_file()
        )

    def test_writes_sorted_files_and_deterministic_source_manifest(self) -> None:
        writer = self.writer()
        files = (
            self.rendered("z-last.md", b"last\n", "rule.z", "role.a"),
            self.rendered("nested/a-first.md", b"first\n", "role.a"),
        )

        result = writer.write_product(files, self.destination, check=False)

        self.assertEqual(
            tuple(sorted(result.changed, key=PurePosixPath.as_posix)),
            result.changed,
        )
        manifest_path = self.destination / ".kinglet-generated.json"
        manifest_bytes = manifest_path.read_bytes()
        self.assertTrue(manifest_bytes.endswith(b"\n"))
        manifest = json.loads(manifest_bytes)
        self.assertEqual(1, manifest["schema_version"])
        self.assertEqual(
            ["nested/a-first.md", "z-last.md"],
            [entry["path"] for entry in manifest["files"]],
        )
        self.assertEqual(
            ["role.a", "rule.z"],
            manifest["files"][1]["source_ids"],
        )

    def test_normalizes_declared_text_to_lf_without_changing_binary_bytes(self) -> None:
        writer = self.writer()
        files = (
            self.rendered("docs/readme.md", b"one\r\ntwo\rthree\n"),
            self.rendered("payload.bin", b"\x00one\r\ntwo\r"),
        )

        writer.write_product(files, self.destination, check=False)

        self.assertEqual(
            b"one\ntwo\nthree\n",
            (self.destination / "docs" / "readme.md").read_bytes(),
        )
        self.assertEqual(
            b"\x00one\r\ntwo\r",
            (self.destination / "payload.bin").read_bytes(),
        )

    def test_shell_files_are_executable_and_other_files_are_not(self) -> None:
        writer = self.writer()
        files = (
            self.rendered("bin/doctor.sh", b"#!/bin/sh\r\nexit 0\r\n"),
            self.rendered("README.md", b"read me\n"),
        )

        writer.write_product(files, self.destination, check=False)

        shell_mode = (self.destination / "bin" / "doctor.sh").stat().st_mode
        markdown_mode = (self.destination / "README.md").stat().st_mode
        self.assertNotEqual(0, shell_mode & 0o111)
        self.assertEqual(0, markdown_mode & 0o111)

    def test_generated_root_and_nested_directories_have_deterministic_modes(self) -> None:
        writer = self.writer()
        previous_umask = os.umask(0o077)
        try:
            writer.write_product(
                (self.rendered("nested/deep/artifact.md", b"body\n"),),
                self.destination,
                check=False,
            )
        finally:
            os.umask(previous_umask)

        for directory in (
            self.destination,
            self.destination / "nested",
            self.destination / "nested" / "deep",
        ):
            with self.subTest(directory=directory):
                self.assertEqual(0o755, directory.stat().st_mode & 0o777)

    def test_check_detects_and_build_repairs_generated_directory_modes(self) -> None:
        writer = self.writer()
        files = (self.rendered("nested/artifact.md", b"body\n"),)
        writer.write_product(files, self.destination, check=False)
        nested = self.destination / "nested"
        self.destination.chmod(0o700)
        nested.chmod(0o700)

        result = writer.write_product(files, self.destination, check=True)

        self.assertIn(PurePosixPath("."), result.changed)
        self.assertIn(PurePosixPath("nested"), result.changed)
        self.assertEqual(0o700, self.destination.stat().st_mode & 0o777)
        self.assertEqual(0o700, nested.stat().st_mode & 0o777)

        writer.write_product(files, self.destination, check=False)

        self.assertEqual(0o755, self.destination.stat().st_mode & 0o777)
        self.assertEqual(0o755, nested.stat().st_mode & 0o777)

    def test_check_compares_bytes_and_modes_without_writing(self) -> None:
        writer = self.writer()
        files = (
            self.rendered("bin/doctor.sh", b"#!/bin/sh\nexit 0\n", "hook.doctor"),
            self.rendered("README.md", b"expected\n", "rule.readme"),
        )
        writer.write_product(files, self.destination, check=False)
        readme = self.destination / "README.md"
        readme.write_bytes(b"different\n")
        shell = self.destination / "bin" / "doctor.sh"
        shell.chmod(0o644)
        before = self.snapshot(self.destination)

        result = writer.write_product(files, self.destination, check=True)

        self.assertEqual(
            (
                PurePosixPath("README.md"),
                PurePosixPath("bin/doctor.sh"),
            ),
            result.changed,
        )
        self.assertEqual((), result.stale)
        self.assertEqual(before, self.snapshot(self.destination))

    def test_check_detects_stale_generated_files_in_sorted_order(self) -> None:
        writer = self.writer()
        initial = (
            self.rendered("z-stale.md", b"z\n"),
            self.rendered("a-stale.md", b"a\n"),
            self.rendered("keep.md", b"keep\n"),
        )
        writer.write_product(initial, self.destination, check=False)

        result = writer.write_product(
            (self.rendered("keep.md", b"keep\n"),),
            self.destination,
            check=True,
        )

        self.assertIn(PurePosixPath(".kinglet-generated.json"), result.changed)
        self.assertEqual(
            (PurePosixPath("a-stale.md"), PurePosixPath("z-stale.md")),
            result.stale,
        )
        self.assertTrue((self.destination / "a-stale.md").exists())

    def test_rejects_parent_traversal_before_touching_destination(self) -> None:
        writer = self.writer()
        unsafe = SimpleNamespace(
            path=PurePosixPath("../escape.md"),
            content=b"escape\n",
            source_ids=(),
        )

        with mock.patch.object(
            writer,
            "_canonical_destination",
            wraps=writer._canonical_destination,
        ) as canonical_destination:
            with self.assertRaises(ValueError):
                writer.write_product((unsafe,), self.destination, check=False)

        canonical_destination.assert_not_called()

        self.assertFalse(self.destination.exists())
        self.assertFalse((self.root / "escape.md").exists())

    def test_rejects_duplicate_paths_before_touching_destination(self) -> None:
        writer = self.writer()
        files = (
            self.rendered("same.md", b"first\n"),
            self.rendered("same.md", b"second\n"),
        )

        with self.assertRaisesRegex(ValueError, "duplicate"):
            writer.write_product(files, self.destination, check=False)

        self.assertFalse(self.destination.exists())

    def test_rejects_paths_beneath_the_reserved_manifest(self) -> None:
        writer = self.writer()
        unsafe = SimpleNamespace(
            path=PurePosixPath(".kinglet-generated.json/payload"),
            content=b"payload\n",
            source_ids=(),
        )

        try:
            writer.write_product((unsafe,), self.destination, check=False)
        except ValueError:
            pass
        except Exception as error:
            self.fail(
                "reserved manifest descendants must be rejected as invalid "
                f"before I/O, not {type(error).__name__}: {error}"
            )
        else:
            self.fail("reserved manifest descendant was accepted")

        self.assertFalse(self.destination.exists())

    def test_rejects_destination_symlink_without_following_it(self) -> None:
        writer = self.writer()
        target = self.root / "outside"
        target.mkdir()
        marker = target / "marker.md"
        marker.write_bytes(b"untouched\n")
        self.destination.symlink_to(target, target_is_directory=True)

        with self.assertRaises(OSError):
            writer.write_product(
                (self.rendered("marker.md", b"changed\n"),),
                self.destination,
                check=False,
            )

        self.assertEqual(b"untouched\n", marker.read_bytes())
        self.assertTrue(self.destination.is_symlink())

    def test_accepts_lexical_ancestor_alias_outside_the_product_leaf(self) -> None:
        writer = self.writer()
        canonical_parent = self.root / "canonical-parent"
        canonical_parent.mkdir()
        alias = self.root / "platform-alias"
        alias.symlink_to(canonical_parent, target_is_directory=True)
        destination = alias / "packages" / "product"

        try:
            writer.write_product(
                (self.rendered("artifact.md", b"body\n"),),
                destination,
                check=False,
            )
        except OSError as error:
            self.fail(f"lexical platform alias was rejected: {error}")

        self.assertEqual(
            b"body\n",
            (
                canonical_parent
                / "packages"
                / "product"
                / "artifact.md"
            ).read_bytes(),
        )
        self.assertTrue(alias.is_symlink())

    def test_rejects_symlink_inside_generated_product_without_following_it(self) -> None:
        writer = self.writer()
        files = (self.rendered("artifact.md", b"body\n"),)
        writer.write_product(files, self.destination, check=False)
        outside = self.root / "outside.md"
        outside.write_bytes(b"outside\n")
        artifact = self.destination / "artifact.md"
        artifact.unlink()
        artifact.symlink_to(outside)

        with self.assertRaises(OSError):
            writer.write_product(files, self.destination, check=True)

        self.assertEqual(b"outside\n", outside.read_bytes())

    def test_staging_failure_leaves_existing_destination_and_no_partial_tree(self) -> None:
        writer = self.writer()
        self.destination.mkdir()
        original = self.destination / "old.md"
        original.write_bytes(b"original\n")
        real_write_file = writer._write_file

        def fail_second_file(path: Path, content: bytes, mode: int) -> None:
            if path.name == "second.md":
                raise OSError("simulated staging failure")
            real_write_file(path, content, mode)

        files = (
            self.rendered("first.md", b"first\n"),
            self.rendered("second.md", b"second\n"),
        )
        with mock.patch.object(writer, "_write_file", side_effect=fail_second_file):
            with self.assertRaisesRegex(OSError, "simulated staging failure"):
                writer.write_product(files, self.destination, check=False)

        self.assertEqual(b"original\n", original.read_bytes())
        self.assertEqual(["product"], sorted(path.name for path in self.root.iterdir()))

    def test_existing_tree_swap_observes_exchange_without_visibility_gap(self) -> None:
        writer = self.writer()
        writer.write_product(
            (self.rendered("artifact.md", b"old\n"),),
            self.destination,
            check=False,
        )
        real_exchange = writer._exchange_paths
        exchange_calls = 0
        destination_visibility: list[bool] = []

        def observe_exchange(left: Path, right: Path) -> None:
            nonlocal exchange_calls
            exchange_calls += 1
            destination_visibility.append(self.destination.is_dir())
            real_exchange(left, right)
            destination_visibility.append(self.destination.is_dir())

        with mock.patch.object(
            writer,
            "_exchange_paths",
            side_effect=observe_exchange,
        ):
            writer.write_product(
                (self.rendered("artifact.md", b"new\n"),),
                self.destination,
                check=False,
            )

        self.assertEqual(1, exchange_calls)
        self.assertEqual([True, True], destination_visibility)
        self.assertEqual(
            b"new\n",
            (self.destination / "artifact.md").read_bytes(),
        )

    def test_post_commit_cleanup_failure_does_not_report_an_ambiguous_failure(self) -> None:
        writer = self.writer()
        writer.write_product(
            (self.rendered("artifact.md", b"old\n"),),
            self.destination,
            check=False,
        )

        with mock.patch.object(
            writer.shutil,
            "rmtree",
            side_effect=OSError("simulated cleanup failure"),
        ):
            try:
                writer.write_product(
                    (self.rendered("artifact.md", b"new\n"),),
                    self.destination,
                    check=False,
                )
            except OSError as error:
                self.fail(f"committed output was reported as failed: {error}")

        self.assertEqual(
            b"new\n",
            (self.destination / "artifact.md").read_bytes(),
        )

    def test_failed_rollback_preserves_the_previous_tree_for_recovery(self) -> None:
        writer = self.writer()
        writer.write_product(
            (self.rendered("artifact.md", b"old\n"),),
            self.destination,
            check=False,
        )
        real_exchange = writer._exchange_paths
        real_fsync_directory = writer._fsync_directory
        exchange_calls = 0

        def fail_rollback(left: Path, right: Path) -> None:
            nonlocal exchange_calls
            exchange_calls += 1
            if exchange_calls == 1:
                real_exchange(left, right)
                return
            raise OSError("simulated rollback exchange failure")

        def fail_commit_sync(path: Path) -> None:
            if path == self.destination.parent:
                raise OSError("simulated parent sync failure")
            real_fsync_directory(path)

        with (
            mock.patch.object(writer, "_exchange_paths", side_effect=fail_rollback),
            mock.patch.object(
                writer,
                "_fsync_directory",
                side_effect=fail_commit_sync,
            ),
        ):
            with self.assertRaises(OSError):
                writer.write_product(
                    (self.rendered("artifact.md", b"new\n"),),
                    self.destination,
                    check=False,
                )

        recovery_trees = sorted(
            self.root.glob(".product.kinglet-stage-*"),
            key=lambda path: path.as_posix(),
        )
        self.assertEqual(1, len(recovery_trees))
        self.assertEqual(
            b"old\n",
            (recovery_trees[0] / "artifact.md").read_bytes(),
        )

    def test_missing_destination_failed_rollback_retains_committed_recovery(self) -> None:
        writer = self.writer()
        real_replace = writer.os.replace
        real_fsync_directory = writer._fsync_directory
        replace_calls = 0

        def fail_rollback(source: Path, target: Path) -> None:
            nonlocal replace_calls
            replace_calls += 1
            if replace_calls == 1:
                real_replace(source, target)
                return
            raise OSError("simulated missing-destination rollback failure")

        def fail_commit_sync(path: Path) -> None:
            if path == self.destination.parent:
                raise OSError("simulated missing-destination commit sync failure")
            real_fsync_directory(path)

        with (
            mock.patch.object(writer.os, "replace", side_effect=fail_rollback),
            mock.patch.object(
                writer,
                "_fsync_directory",
                side_effect=fail_commit_sync,
            ),
        ):
            with self.assertRaisesRegex(
                OSError,
                "committed product retained for recovery",
            ) as raised:
                writer.write_product(
                    (self.rendered("artifact.md", b"new\n"),),
                    self.destination,
                    check=False,
                )

        self.assertIn(
            "simulated missing-destination commit sync failure",
            str(raised.exception),
        )
        self.assertEqual(
            b"new\n",
            (self.destination / "artifact.md").read_bytes(),
        )
        self.assertEqual([], list(self.root.glob(".product.kinglet-stage-*")))

    def test_missing_destination_successful_rollback_resyncs_parent(self) -> None:
        writer = self.writer()
        real_fsync_directory = writer._fsync_directory
        parent_syncs = 0

        def fail_first_parent_sync(path: Path) -> None:
            nonlocal parent_syncs
            if path == self.destination.parent:
                parent_syncs += 1
                if parent_syncs == 1:
                    raise OSError("simulated commit sync failure")
            real_fsync_directory(path)

        with mock.patch.object(
            writer,
            "_fsync_directory",
            side_effect=fail_first_parent_sync,
        ):
            with self.assertRaisesRegex(OSError, "simulated commit sync failure"):
                writer.write_product(
                    (self.rendered("artifact.md", b"new\n"),),
                    self.destination,
                    check=False,
                )

        self.assertEqual(2, parent_syncs)
        self.assertFalse(self.destination.exists())

    def test_new_parent_chain_entries_are_synced_before_product_commit(self) -> None:
        writer = self.writer()
        destination = self.root / "packages" / "nested" / "product"
        real_mkdir = writer.os.mkdir
        real_fsync_directory = writer._fsync_directory
        real_replace_tree = writer._replace_tree
        events: list[tuple[str, Path]] = []

        def record_mkdir(path, mode=0o777, *, dir_fd=None) -> None:
            real_mkdir(path, mode, dir_fd=dir_fd)
            if dir_fd is None:
                events.append(("mkdir", Path(path)))

        def record_fsync(path: Path) -> None:
            events.append(("fsync", path))
            real_fsync_directory(path)

        def record_commit(stage: Path, product: Path) -> None:
            events.append(("commit", product))
            real_replace_tree(stage, product)

        with (
            mock.patch.object(writer.os, "mkdir", side_effect=record_mkdir),
            mock.patch.object(
                writer,
                "_fsync_directory",
                side_effect=record_fsync,
            ),
            mock.patch.object(writer, "_replace_tree", side_effect=record_commit),
        ):
            writer.write_product(
                (self.rendered("artifact.md", b"body\n"),),
                destination,
                check=False,
            )

        commit_index = events.index(("commit", destination))

        def next_index(event: tuple[str, Path], start: int) -> int:
            for index in range(start, len(events)):
                if events[index] == event:
                    return index
            self.fail(f"missing durability event after index {start}: {event}")

        packages_mkdir = next_index(
            ("mkdir", self.root / "packages"),
            0,
        )
        root_sync = next_index(("fsync", self.root), packages_mkdir + 1)
        nested_mkdir = next_index(
            ("mkdir", self.root / "packages" / "nested"),
            root_sync + 1,
        )
        packages_sync = next_index(
            ("fsync", self.root / "packages"),
            nested_mkdir + 1,
        )
        nested_sync = next_index(
            ("fsync", self.root / "packages" / "nested"),
            packages_sync + 1,
        )
        self.assertLess(nested_sync, commit_index)

    def test_raced_parent_creation_is_synced_before_product_commit(self) -> None:
        writer = self.writer()
        packages = self.root / "packages"
        destination = packages / "product"
        real_mkdir = writer.os.mkdir
        real_fsync_directory = writer._fsync_directory
        synced: list[Path] = []
        raced = False

        def race_mkdir(path, mode=0o777, *, dir_fd=None) -> None:
            nonlocal raced
            if dir_fd is None and Path(path) == packages and not raced:
                raced = True
                real_mkdir(path, mode)
                raise FileExistsError(errno.EEXIST, "simulated mkdir race", path)
            real_mkdir(path, mode, dir_fd=dir_fd)

        def record_fsync(path: Path) -> None:
            synced.append(path)
            real_fsync_directory(path)

        with (
            mock.patch.object(writer.os, "mkdir", side_effect=race_mkdir),
            mock.patch.object(
                writer,
                "_fsync_directory",
                side_effect=record_fsync,
            ),
        ):
            writer.write_product(
                (self.rendered("artifact.md", b"body\n"),),
                destination,
                check=False,
            )

        self.assertTrue(raced)
        self.assertIn(self.root, synced)
        self.assertIn(packages, synced)

    def test_check_does_not_follow_destination_substituted_during_scan(self) -> None:
        writer = self.writer()
        files = (self.rendered("artifact.md", b"expected\n"),)
        writer.write_product(files, self.destination, check=False)
        held = self.root / "held-product"
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "artifact.md").write_bytes(b"outside\n")
        real_scandir = writer.os.scandir
        substituted = False

        def substitute_destination(path):
            nonlocal substituted
            if not substituted:
                substituted = True
                self.destination.rename(held)
                self.destination.symlink_to(outside, target_is_directory=True)
            return real_scandir(path)

        with mock.patch.object(
            writer.os,
            "scandir",
            side_effect=substitute_destination,
        ):
            result = writer.write_product(files, self.destination, check=True)

        self.assertEqual((), result.changed)
        self.assertEqual((), result.stale)


if __name__ == "__main__":
    unittest.main()
