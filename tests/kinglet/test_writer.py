import importlib
import importlib.util
import json
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

        with self.assertRaises(ValueError):
            writer.write_product((unsafe,), self.destination, check=False)

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

    def test_existing_tree_swap_has_no_ordinary_rename_visibility_gap(self) -> None:
        writer = self.writer()
        writer.write_product(
            (self.rendered("artifact.md", b"old\n"),),
            self.destination,
            check=False,
        )
        real_replace = writer.os.replace
        destination_visibility: list[bool] = []

        def observe_replace(source, target) -> None:
            real_replace(source, target)
            destination_visibility.append(self.destination.is_dir())

        with mock.patch.object(writer.os, "replace", side_effect=observe_replace):
            writer.write_product(
                (self.rendered("artifact.md", b"new\n"),),
                self.destination,
                check=False,
            )

        self.assertNotIn(False, destination_visibility)
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
