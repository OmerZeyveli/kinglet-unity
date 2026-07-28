import json
import os
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import patch

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.unity import ownership
from tools.kinglet_spike.unity.ownership import (
    ProjectOwner,
    _TruncatedCommand,
    _build_macos_process_table,
    _canonical_or_none,
    _extract_argv0,
    _is_dir_or_unknown,
    _is_unity_editor_argv0,
    _macos_process_table,
    _parse_comm_map,
    _parse_pid_list,
    _parse_procargs2,
    _read_argv_via_sysctl,
    _linux_proc_process_table,
    _mark_truncated,
    _parse_posix_process_table,
    _parse_windows_process_table,
    _posix_process_table,
    _proc_pid_is_alive,
    _project_path_candidates_from_raw,
    _ps_process_table,
    _read_argv_via_proc,
    _read_comm_via_proc,
    _unity_lockfile_present,
    _windows_process_table,
    assert_headless_safe,
    detect_gui_owner,
    find_owning_process,
    resolve_lock_owner,
)

_EDITOR = "/home/user/Unity/Hub/Editor/6000.3.18f1/Editor/Unity"


def _unity_process(pid: int, project_path: str) -> tuple:
    return (pid, f"{_EDITOR} -projectPath {project_path} -logFile -")


def _raw_unity_command(project_value: str, trailing: str = " -logFile -") -> str:
    return f"{_EDITOR} -projectPath {project_value}{trailing}"


class FindOwningProcessTests(unittest.TestCase):
    def test_matching_project_path_is_owned(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [_unity_process(4242, str(project))]
            owner = find_owning_process(table, project)
            self.assertIsNotNone(owner)
            self.assertTrue(owner.confirmed)
            self.assertEqual(4242, owner.pid)
            self.assertEqual("process", owner.source)

    def test_similarly_prefixed_sibling_path_does_not_match(self):
        # The whole point of canonicalized-path equality over substring
        # matching: "proj" must not match a process reporting "proj-other".
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            sibling = Path(tmp) / "proj-other"
            sibling.mkdir()
            table = [_unity_process(4242, str(sibling))]
            self.assertIsNone(find_owning_process(table, project))

    def test_symlink_alias_canonicalizes_to_owned_project(self):
        with TemporaryDirectory() as tmp:
            real_project = Path(tmp) / "real-proj"
            real_project.mkdir()
            alias = Path(tmp) / "alias-proj"
            os.symlink(real_project, alias, target_is_directory=True)

            # Process reports the symlink path; caller requests the real path.
            table = [_unity_process(9001, str(alias))]
            owner = find_owning_process(table, real_project)
            self.assertIsNotNone(owner)
            self.assertTrue(owner.confirmed)

            # And the reverse: process reports the real path, caller
            # requests through the symlink.
            table_reversed = [_unity_process(9002, str(real_project))]
            owner_reversed = find_owning_process(table_reversed, alias)
            self.assertIsNotNone(owner_reversed)
            self.assertTrue(owner_reversed.confirmed)

    def test_self_match_trap_ignores_non_unity_argv0(self):
        # Observed live on this host: a loose substring match on the
        # command line finds this very controller's own shell command
        # (which can legitimately contain the text "Editor/Unity"), or an
        # unrelated grep/ps invocation. Only an exact argv[0] basename of
        # "Unity"/"Unity.exe" counts as a candidate Editor.
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [
                (555, f"/bin/bash -c grep -af 'Editor/Unity' -projectPath {project}"),
                (556, f"python3 my_controller.py -projectPath {project}"),
            ]
            self.assertIsNone(find_owning_process(table, project))

    def test_orphaned_compiler_helper_is_not_an_owner(self):
        # Observed live: two `dotnet exec .../DotNetSdkRoslyn/VBCSCompiler.dll`
        # processes survived a clean Unity batchmode exit, reparented to
        # init (PPID=1). argv[0] basename is "dotnet", never "Unity" --
        # this must never be mistaken for a live Editor.
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [
                (
                    777,
                    "/usr/share/dotnet/dotnet exec "
                    "/home/user/.local/share/unity3d/DotNetSdkRoslyn/VBCSCompiler.dll "
                    f"-projectPath {project}",
                ),
            ]
            self.assertIsNone(find_owning_process(table, project))

    def test_process_with_no_projectpath_argument_is_ignored(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [(1, "/opt/Unity/Editor/Unity -batchmode -quit")]
            self.assertIsNone(find_owning_process(table, project))

    # --- CRITICAL 1 (round 1) fix: a single space must not defeat the match ---

    def test_space_in_project_path_still_matches(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "My Project"
            project.mkdir()
            table = [_unity_process(4242, str(project))]
            owner = find_owning_process(table, project)
            self.assertIsNotNone(owner)
            self.assertTrue(owner.confirmed)

    def test_space_in_project_path_distinguishes_a_true_sibling(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "My Project"
            project.mkdir()
            other = Path(tmp) / "My Project 2"
            other.mkdir()
            table = [_unity_process(4242, str(other))]
            self.assertIsNone(find_owning_process(table, project))

    def test_windows_quoted_space_in_project_path_matches(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "My Project"
            project.mkdir()
            command = (
                '"C:\\Program Files\\Unity\\Editor\\Unity.exe" '
                f'-projectPath "{project}" -logFile -'
            )
            owner = find_owning_process([(1, command)], project, windows=True)
            self.assertIsNotNone(owner)
            self.assertTrue(owner.confirmed)

    def test_windows_unquoted_backslash_path_still_matches(self):
        # The exposure round 2 flagged alongside CRITICAL 1: an UNQUOTED
        # Windows command line still has to resolve correctly.
        with TemporaryDirectory() as tmp:
            project_value = f"{tmp}\\proj"
            command = f"C:\\Unity\\Editor\\Unity.exe -projectPath {project_value} -logFile -"
            owner = find_owning_process(
                [(1, command)], Path(project_value), windows=True
            )
            self.assertIsNotNone(owner)
            self.assertTrue(owner.confirmed)

    def test_trailing_slash_in_reported_path_still_matches(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [_unity_process(1, str(project) + "/")]
            owner = find_owning_process(table, project)
            self.assertIsNotNone(owner)
            self.assertTrue(owner.confirmed)

    def test_cwd_relative_reported_path_still_matches(self):
        with TemporaryDirectory() as tmp:
            (Path(tmp) / "proj").mkdir()
            original_cwd = os.getcwd()
            os.chdir(tmp)
            try:
                table = [_unity_process(1, "proj")]
                owner = find_owning_process(table, Path("proj"))
                self.assertIsNotNone(owner)
                self.assertTrue(owner.confirmed)
            finally:
                os.chdir(original_cwd)

    # --- IMPORTANT 2 fix: a discriminating test for the argv0 guard ---

    def test_argv0_containing_unity_but_not_equal_is_not_a_match(self):
        # UnityShaderCompiler and unityhub are real Unity-shipped binaries
        # whose path contains "Unity" but are not the Editor. Mutating
        # _is_unity_editor_argv0 to `"Unity" in token` must make this fail.
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [
                (10, f"/opt/Unity/Editor/Data/Tools/UnityShaderCompiler -projectPath {project}"),
                (11, f"/usr/bin/unityhub -projectPath {project}"),
            ]
            self.assertIsNone(find_owning_process(table, project))

    # --- IMPORTANT 3 fix: a discriminating test for path equality ---

    def test_prefix_without_separator_does_not_match(self):
        # "proj2" starts with "proj" as a bare string -- a startswith()
        # comparison (in either direction) would incorrectly match this.
        # Only whole-path equality may pass.
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            sibling = Path(tmp) / "proj2"
            sibling.mkdir()
            table = [_unity_process(4242, str(sibling))]
            self.assertIsNone(find_owning_process(table, project))


class CriticalSpaceAmbiguityRegressionTests(unittest.TestCase):
    """Round 2 CRITICAL 1: eight concrete false-SAFE reproductions the
    re-reviewer demonstrated against round 1's "stop at the first
    flag-shaped token" heuristic -- a live `Unity -projectPath <dir>`
    command line, directory exists, no lockfile yet (the real ~2s startup
    window), each of these read SAFE under the old code. None may ever
    read SAFE again.
    """

    def _assert_owned(self, dir_name: str, trailing: str = " -logFile -"):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / dir_name
            project.mkdir()
            table = [(1, _raw_unity_command(str(project), trailing))]
            owner = find_owning_process(table, project)
            self.assertIsNotNone(owner, f"{dir_name!r} must be detected as owned")
            self.assertTrue(owner.confirmed)

    def test_windows_style_copy_suffix(self):
        # "Kinglet - Copy" is literally what Windows names a duplicated folder.
        self._assert_owned("Kinglet - Copy")

    def test_version_suffix(self):
        self._assert_owned("Kinglet - v2")

    def test_double_dash_word(self):
        self._assert_owned("proj -- old")

    def test_dash_letter_lookalike_flag(self):
        # "-Project" looks exactly like a real flag token to any
        # first-flag-stops-here heuristic.
        self._assert_owned("My -Project")

    def test_embedded_real_flag_name(self):
        # The folder name itself contains the literal text "-logFile",
        # which is ALSO the real trailing flag in this command.
        self._assert_owned("My -logFile Project")

    def test_double_space(self):
        # str.split()-based tokenization collapses this to one space and
        # can never reconstruct it -- this is why round 2 slices the
        # original string instead of tokenizing and rejoining.
        self._assert_owned("My  Project")

    def test_tab_in_name(self):
        self._assert_owned("My\tProject")

    def test_newline_in_name(self):
        self._assert_owned("My\nProject")

    def test_last_argument_with_no_trailing_flags(self):
        # -projectPath is the very last token -- the untruncated-remainder
        # candidate must still recover it.
        self._assert_owned("Kinglet - Copy", trailing="")


class CriticalAmbiguityMustRefuseTests(unittest.TestCase):
    """Round 3 CRITICAL 1: the re-reviewer's finding was structural, not a
    missed case -- there was NO branch in the lossy path that could ever
    produce E_UNITY_OWNER_UNKNOWN, so anything the slicer couldn't resolve
    fell through to SAFE by construction. None of these may ever read as
    SAFE (None) again; each must come back as an unconfirmed
    (confirmed=False) ProjectOwner instead.
    """

    def _assert_ambiguous(self, dir_name: str, trailing: str, *, windows: bool = False):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / dir_name
            project.mkdir()
            table = [(1, _raw_unity_command(str(project), trailing))]
            owner = find_owning_process(table, project, windows=windows)
            self.assertIsNotNone(owner, "must not read SAFE")
            self.assertFalse(owner.confirmed)
            self.assertEqual("process-ambiguous", owner.source)

    def test_next_argument_not_flag_shaped(self):
        self._assert_ambiguous("proj", " extraarg")

    def test_next_argument_bare_dash(self):
        self._assert_ambiguous("proj", " -")

    def test_next_argument_double_dashed(self):
        self._assert_ambiguous("proj", " --quit")

    def test_windows_unquoted_slash_style_flag(self):
        with TemporaryDirectory() as tmp:
            project_value = f"{tmp}\\proj"
            command = f"Unity.exe -projectPath {project_value} /quit"
            owner = find_owning_process(
                [(1, command)], Path(project_value), windows=True
            )
            self.assertIsNotNone(owner, "must not read SAFE")
            self.assertFalse(owner.confirmed)
            self.assertEqual("process-ambiguous", owner.source)

    def test_windows_unquoted_next_argument_not_flag_shaped(self):
        with TemporaryDirectory() as tmp:
            project_value = f"{tmp}\\proj"
            command = f"Unity.exe -projectPath {project_value} extraarg"
            owner = find_owning_process(
                [(1, command)], Path(project_value), windows=True
            )
            self.assertIsNotNone(owner, "must not read SAFE")
            self.assertFalse(owner.confirmed)
            self.assertEqual("process-ambiguous", owner.source)

    def test_multiple_distinct_existing_candidates_is_ambiguous(self):
        # Two DIFFERENT real directories both appear as candidates and
        # neither is the target -- we cannot tell which one is true, so
        # this must refuse rather than confidently pick the "not owned"
        # answer for a process we cannot actually rule out.
        with TemporaryDirectory() as tmp:
            target = Path(tmp) / "target"
            target.mkdir()
            command = _raw_unity_command(f"{tmp}/decoy", " -logFile -")
            # _project_path_candidates_from_raw(command) produces exactly
            # two candidates for this shape: the flag-truncated
            # ".../decoy" and the untruncated remainder
            # ".../decoy -logFile -" (trailing " -" included). Create BOTH
            # as real directories so neither can be ruled out by
            # existence, and neither is the target.
            candidates = _project_path_candidates_from_raw(command, windows=False)
            self.assertEqual(2, len(candidates), candidates)
            for candidate in candidates:
                Path(candidate).mkdir()

            owner = find_owning_process([(1, command)], target)
            self.assertIsNotNone(owner, "must not read SAFE")
            self.assertFalse(owner.confirmed)
            self.assertEqual("process-ambiguous", owner.source)


class RealPosixParserNewlineTests(unittest.TestCase):
    """Round 3 CRITICAL 1's sixth reproduction: a newline in the reported
    path breaks the REAL ps-output pipeline, not just a fabricated single
    string -- the fabricated form was shown to pass while the real reader
    (which splits stdout on '\\n' first) failed, so this drives the
    scenario through _parse_posix_process_table itself.
    """

    def test_newline_in_reported_path_is_ambiguous_via_real_parser(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "My\nProject"
            project.mkdir()
            # This is what real `ps -axo pid=,command=` output looks like
            # when an argv element contains a literal newline: ps prints
            # it verbatim, so the captured text has an extra visual line.
            stdout = f"  4242 {_EDITOR} -projectPath {project} -logFile -\n"
            table = _parse_posix_process_table(stdout)
            owner = find_owning_process(table, project)
            self.assertIsNotNone(owner, "must not read SAFE")
            self.assertFalse(owner.confirmed)
            self.assertEqual("process-ambiguous", owner.source)

    def test_unparseable_line_with_no_preceding_entry_is_dropped_not_crashed(self):
        # Defensive: an unparseable line with nothing before it to
        # attribute it to must not raise or fabricate an entry.
        stdout = "garbage line with no pid\n"
        self.assertEqual((), _parse_posix_process_table(stdout))


class MarkTruncatedTests(unittest.TestCase):
    def test_string_command_keeps_its_argv0(self):
        marked = _mark_truncated(f"{_EDITOR} -projectPath /home/u/My")
        self.assertIsInstance(marked, _TruncatedCommand)
        self.assertEqual(_EDITOR, marked.argv0)

    def test_already_truncated_is_idempotent(self):
        original = _TruncatedCommand(argv0=_EDITOR)
        self.assertIs(original, _mark_truncated(original))

    def test_exact_argv_tuple_keeps_its_argv0(self):
        marked = _mark_truncated((_EDITOR, "-projectPath", "/home/u/My"))
        self.assertIsInstance(marked, _TruncatedCommand)
        self.assertEqual(_EDITOR, marked.argv0)


class ExactArgvProcessTableTests(unittest.TestCase):
    """Entries carrying an EXACT argv tuple (what /proc/<pid>/cmdline gives
    us) need no ambiguity-resolving heuristic at all -- the value right
    after -projectPath IS the path, verbatim."""

    def test_exact_argv_tuple_with_space_in_path_needs_no_heuristic(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "Kinglet - Copy"
            project.mkdir()
            argv = (_EDITOR, "-projectPath", str(project), "-logFile", "-")
            owner = find_owning_process([(4242, argv)], project)
            self.assertIsNotNone(owner)
            self.assertTrue(owner.confirmed)
            self.assertEqual("process-exact-argv", owner.source)

    def test_exact_argv_sibling_does_not_match(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            sibling = Path(tmp) / "proj2"
            sibling.mkdir()
            argv = ("/opt/Unity/Editor/Unity", "-projectPath", str(sibling))
            self.assertIsNone(find_owning_process([(1, argv)], project))

    def test_exact_argv_non_unity_argv0_is_ignored(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            argv = ("/usr/bin/unityhub", "-projectPath", str(project))
            self.assertIsNone(find_owning_process([(1, argv)], project))


class ResolveLockOwnerTests(unittest.TestCase):
    def test_stale_lock_with_no_corroborating_process_is_unconfirmed(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            owner = resolve_lock_owner(
                (), project, lockfile_exists=True, instance_pid=None
            )
            self.assertIsNotNone(owner)
            self.assertFalse(owner.confirmed)
            self.assertEqual("lockfile", owner.source)

    def test_instance_pid_matching_live_unity_process_is_confirmed(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            # The pid is live and is a genuine Unity Editor process, but its
            # -projectPath could not be parsed directly (e.g. a truncated
            # ps line) -- EditorInstance.json's pid still corroborates it.
            table = [(1234, "/opt/Unity/Editor/Unity -batchmode")]
            owner = resolve_lock_owner(
                table, project, lockfile_exists=True, instance_pid=1234
            )
            self.assertIsNotNone(owner)
            self.assertTrue(owner.confirmed)
            self.assertEqual("lockfile+process", owner.source)

    def test_instance_pid_not_live_stays_unconfirmed(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [(9999, "/usr/share/dotnet/dotnet exec VBCSCompiler.dll")]
            owner = resolve_lock_owner(
                table, project, lockfile_exists=False, instance_pid=4242
            )
            self.assertIsNotNone(owner)
            self.assertFalse(owner.confirmed)

    def test_no_lock_artifacts_and_no_process_is_safe(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            owner = resolve_lock_owner(
                (), project, lockfile_exists=False, instance_pid=None
            )
            self.assertIsNone(owner)


class DetectGuiOwnerAndAssertHeadlessSafeTests(unittest.TestCase):
    def test_live_process_match_confirms_owner_and_refuses_headless(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [_unity_process(321, str(project))]

            owner = detect_gui_owner(project, process_table_provider=lambda: table)
            self.assertIsInstance(owner, ProjectOwner)
            self.assertTrue(owner.confirmed)

            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=lambda: table)
            self.assertEqual("E_UNITY_OWNED", ctx.exception.code)

    def test_stale_real_lockfile_refuses_headless_as_unknown(self):
        # Real temp lock files on disk, per the brief -- not just the pure
        # resolve_lock_owner() path.
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            (project / "Temp").mkdir(parents=True)
            (project / "Temp" / "UnityLockfile").write_text("", encoding="utf-8")

            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=lambda: ())
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_stale_real_editor_instance_json_refuses_headless_as_unknown(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            (project / "Library").mkdir(parents=True)
            instance = {
                "process_id": 5150,
                "version": "6000.3.18f1",
                "app_path": "/opt/Unity/Editor/Unity",
            }
            (project / "Library" / "EditorInstance.json").write_text(
                json.dumps(instance), encoding="utf-8"
            )

            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=lambda: ())
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_editor_instance_json_pid_alive_confirms_ownership(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            (project / "Library").mkdir(parents=True)
            instance = {"process_id": 6161, "version": "6000.3.18f1"}
            (project / "Library" / "EditorInstance.json").write_text(
                json.dumps(instance), encoding="utf-8"
            )
            table = [(6161, "/opt/Unity/Editor/Unity -batchmode")]

            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=lambda: table)
            self.assertEqual("E_UNITY_OWNED", ctx.exception.code)

    def test_no_owner_and_no_lock_is_headless_safe(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            # Must not raise.
            self.assertIsNone(
                assert_headless_safe(project, process_table_provider=lambda: ())
            )

    def test_sibling_project_with_owner_elsewhere_is_headless_safe(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            sibling = Path(tmp) / "proj-sibling"
            sibling.mkdir()
            table = [_unity_process(4242, str(sibling))]
            self.assertIsNone(
                assert_headless_safe(project, process_table_provider=lambda: table)
            )

    def test_owned_error_message_does_not_overclaim_gui(self):
        # M5: the detector cannot distinguish a GUI Editor from a
        # concurrent headless run holding the same lock/process signals --
        # the raised message must not assert "GUI" specifically.
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = [_unity_process(1, str(project))]
            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=lambda: table)
            self.assertNotIn("GUI", str(ctx.exception))


class ExtractArgv0Tests(unittest.TestCase):
    def test_posix_first_whitespace_token(self):
        self.assertEqual(
            "/opt/Unity/Editor/Unity",
            _extract_argv0("/opt/Unity/Editor/Unity -projectPath /x", windows=False),
        )

    def test_windows_quoted_argv0_with_space(self):
        self.assertEqual(
            "C:\\Program Files\\Unity\\Editor\\Unity.exe",
            _extract_argv0(
                '"C:\\Program Files\\Unity\\Editor\\Unity.exe" -projectPath C:\\x',
                windows=True,
            ),
        )

    def test_windows_backslashes_never_treated_as_escapes(self):
        self.assertEqual(
            "C:\\Unity\\Editor\\Unity.exe",
            _extract_argv0("C:\\Unity\\Editor\\Unity.exe -projectPath C:\\x", windows=True),
        )

    def test_empty_command_returns_none(self):
        self.assertIsNone(_extract_argv0("   ", windows=False))


class ProjectPathCandidatesFromRawTests(unittest.TestCase):
    def test_no_projectpath_flag_yields_no_candidates(self):
        self.assertEqual([], _project_path_candidates_from_raw("Unity -batchmode", windows=False))

    def test_simple_path_is_the_only_candidate(self):
        candidates = _project_path_candidates_from_raw(
            "Unity -projectPath /home/u/proj -logFile -", windows=False
        )
        self.assertIn("/home/u/proj", candidates)

    def test_double_space_is_preserved_verbatim(self):
        candidates = _project_path_candidates_from_raw(
            "Unity -projectPath /home/u/My  Project -logFile -", windows=False
        )
        self.assertIn("/home/u/My  Project", candidates)

    # --- FINAL whole-branch review, IMPORTANT 8: the flag regex and the value
    #     extractor were two guards with two different whitespace alphabets,
    #     and their disagreement returned [] -- which reads as "no -projectPath
    #     here", a POSITIVE ruling-out. Same shape as 6257de1's credential rule.

    def test_every_separator_the_flag_regex_accepts_the_extractor_also_accepts(self):
        # Drives the alphabet character by character rather than asserting on
        # one lucky example, so narrowing EITHER guard fails this test.
        for char in ownership._SEPARATOR_CHARS:
            with self.subTest(char=repr(char)):
                command = f"Unity -projectPath{char}/home/u/proj"
                self.assertIsNotNone(
                    ownership._PROJECT_PATH_FLAG_RE.search(command),
                    "the flag regex must match this separator",
                )
                self.assertIn(
                    "/home/u/proj",
                    _project_path_candidates_from_raw(command, windows=False),
                    "a separator the regex accepts must not yield an empty "
                    "candidate list, which the caller reads as 'ruled out'",
                )

    def test_newline_separated_projectpath_is_not_silently_ruled_out(self):
        # The concrete instance: a `ps`-rendered line whose separator is a
        # newline. Previously matched the regex, then failed
        # `rest[0] not in (" ", "\t")`, and returned [].
        candidates = _project_path_candidates_from_raw(
            "Unity -projectPath\n/home/u/proj -logFile -", windows=False
        )
        self.assertIn("/home/u/proj", candidates)

    def test_a_separator_preceding_the_flag_is_the_same_alphabet(self):
        for char in ownership._SEPARATOR_CHARS:
            with self.subTest(char=repr(char)):
                command = f"Unity{char}-projectPath /home/u/proj"
                self.assertIn(
                    "/home/u/proj",
                    _project_path_candidates_from_raw(command, windows=False),
                )

    def test_windows_quoted_value_is_the_sole_candidate(self):
        candidates = _project_path_candidates_from_raw(
            'Unity.exe -projectPath "C:\\proj\\My Game" -logFile -', windows=True
        )
        self.assertEqual(["C:\\proj\\My Game"], candidates)


class ParsePosixProcessTableTests(unittest.TestCase):
    def test_parses_pid_and_command(self):
        stdout = "  1234 /opt/Unity/Editor/Unity -batchmode\n  5678 /bin/bash\n"
        table = _parse_posix_process_table(stdout)
        self.assertEqual(
            ((1234, "/opt/Unity/Editor/Unity -batchmode"), (5678, "/bin/bash")),
            table,
        )

    def test_blank_lines_and_bad_pids_are_skipped(self):
        stdout = "\n   \nnot-a-pid something\n42 ok\n"
        self.assertEqual(((42, "ok"),), _parse_posix_process_table(stdout))


class ParseWindowsProcessTableTests(unittest.TestCase):
    def test_parses_pid_tab_name_tab_commandline_lines(self):
        stdout = (
            "1234\tUnity.exe\tC:\\Unity\\Editor\\Unity.exe -projectPath C:\\proj\\game\n"
            "5678\texplorer.exe\tC:\\Windows\\explorer.exe\n"
        )
        table = _parse_windows_process_table(stdout)
        self.assertEqual(
            (
                (1234, "C:\\Unity\\Editor\\Unity.exe -projectPath C:\\proj\\game"),
                (5678, "C:\\Windows\\explorer.exe"),
            ),
            table,
        )

    def test_tab_is_the_separator_not_generic_whitespace(self):
        # Minor (round 2): mutating split("\t", 2) to split(None, 2)
        # survived the round-1 fixture because in that data the only
        # whitespace before the command was the tab itself, so both split
        # styles happened to agree. A space embedded INSIDE the pid field,
        # before the real tab, breaks that coincidence: a generic-
        # whitespace split misreads "90 01" as pid=90 plus a spurious
        # command fragment "01\t...". The correct behavior is to treat this
        # line as unparseable (bad pid), producing an empty table.
        stdout = (
            "90 01\tUnity.exe\t"
            "C:\\Unity\\Editor\\Unity.exe -projectPath C:\\proj\\game\n"
        )
        self.assertEqual((), _parse_windows_process_table(stdout))

    # --- FINAL whole-branch review, CRITICAL 2: the Windows parser had no
    #     "I could not tell" branch. Both of these FAIL against the previous
    #     parser, which dropped the tail line and dropped the $null command.

    def test_newline_in_a_path_marks_the_split_entry_ambiguous_not_clean(self):
        # A project directory whose name contains a newline makes PowerShell
        # print ONE process as TWO lines. The old parser dropped the tail
        # (`if "\t" not in line: continue`) and left the Editor's entry
        # looking like a clean, complete command line ending at the truncated
        # prefix -- which then failed to match the real project and read as
        # NOT the owner. Identical shape to the POSIX side's fix.
        stdout = (
            "1234\tUnity.exe\t"
            "C:\\Unity\\Editor\\Unity.exe -projectPath C:\\proj\\ga\n"
            "me\n"
            "5678\texplorer.exe\tC:\\Windows\\explorer.exe\n"
        )
        table = _parse_windows_process_table(stdout)
        self.assertEqual(2, len(table))
        pid, command = table[0]
        self.assertEqual(1234, pid)
        self.assertIsInstance(command, _TruncatedCommand)
        # argv0 must be parsed with WINDOWS separators, or the entry reads as
        # not-Unity one layer down and is ignored again.
        self.assertTrue(_is_unity_editor_argv0(command.argv0, windows=True))
        self.assertEqual((5678, "C:\\Windows\\explorer.exe"), table[1])

    def test_null_commandline_for_a_unity_process_is_kept_as_ambiguous(self):
        # Win32_Process.CommandLine is $null -- rendered as an empty field --
        # for a process the caller cannot inspect, INCLUDING an elevated
        # Editor. The old parser dropped the pid, so no owner was found and
        # assert_headless_safe cleared over a live Editor.
        stdout = "1234\tUnity.exe\t\n5678\tservices.exe\t\n"
        table = _parse_windows_process_table(stdout)
        self.assertEqual(1, len(table), "the non-Unity $null pid stays dropped")
        pid, command = table[0]
        self.assertEqual(1234, pid)
        self.assertIsInstance(command, _TruncatedCommand)
        self.assertEqual("Unity.exe", command.argv0)

    def test_a_null_commandline_editor_is_reported_as_an_unconfirmed_owner(self):
        # Driven through the real public entry point, not just the parser:
        # the whole point is that assert_headless_safe must NOT clear.
        stdout = "1234\tUnity.exe\t\n"

        def provider():
            return _parse_windows_process_table(stdout)

        owner = detect_gui_owner(
            Path("C:/proj/game"), process_table_provider=provider, windows=True
        )
        self.assertIsNotNone(owner, "an unreadable Editor must not read as SAFE")
        self.assertFalse(owner.confirmed)
        with self.assertRaises(EvidenceError) as caught:
            assert_headless_safe(
                Path("C:/proj/game"),
                process_table_provider=provider,
                windows=True,
            )
        self.assertEqual("E_UNITY_OWNER_UNKNOWN", caught.exception.code)


class UnityLockfilePresentTests(unittest.TestCase):
    def test_missing_file_is_false(self):
        with TemporaryDirectory() as tmp:
            self.assertFalse(_unity_lockfile_present(Path(tmp)))

    def test_existing_file_is_true(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "Temp").mkdir()
            (project / "Temp" / "UnityLockfile").write_text("", encoding="utf-8")
            self.assertTrue(_unity_lockfile_present(project))

    def test_unreadable_temp_dir_reads_as_present_not_absent(self):
        # Path.exists() swallows every OSError, including a permission
        # error, and reports it identically to "file genuinely absent".
        # An unreadable Temp/ must be treated as a signal, not silent safety.
        with TemporaryDirectory() as tmp:
            project = Path(tmp)
            with patch(
                "tools.kinglet_spike.unity.ownership.Path.stat",
                side_effect=PermissionError("denied"),
            ):
                self.assertTrue(_unity_lockfile_present(project))


class ProcessTableProviderFailureTests(unittest.TestCase):
    # IMPORTANT 4: a provider that cannot obtain a listing must raise
    # E_UNITY_OWNER_UNKNOWN, never silently return an empty table that
    # detect_gui_owner/assert_headless_safe would then read as "safe".
    # These target _ps_process_table directly (the function that actually
    # calls subprocess.run) -- _posix_process_table() prefers /proc on
    # Linux and would never reach the mocked subprocess at all.

    def test_ps_provider_raises_on_oserror(self):
        with patch(
            "tools.kinglet_spike.unity.ownership.subprocess.run",
            side_effect=OSError("no ps"),
        ):
            with self.assertRaises(EvidenceError) as ctx:
                _ps_process_table()
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_ps_provider_raises_on_timeout(self):
        with patch(
            "tools.kinglet_spike.unity.ownership.subprocess.run",
            side_effect=subprocess.TimeoutExpired(cmd="ps", timeout=10),
        ):
            with self.assertRaises(EvidenceError) as ctx:
                _ps_process_table()
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_ps_provider_raises_on_nonzero_exit(self):
        fake_result = SimpleNamespace(returncode=1, stdout="", stderr="permission denied")
        with patch(
            "tools.kinglet_spike.unity.ownership.subprocess.run",
            return_value=fake_result,
        ):
            with self.assertRaises(EvidenceError) as ctx:
                _ps_process_table()
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_windows_provider_raises_on_oserror(self):
        with patch(
            "tools.kinglet_spike.unity.ownership.subprocess.run",
            side_effect=OSError("no powershell"),
        ):
            with self.assertRaises(EvidenceError) as ctx:
                _windows_process_table()
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_windows_provider_raises_on_nonzero_exit(self):
        fake_result = SimpleNamespace(returncode=1, stdout="", stderr="access denied")
        with patch(
            "tools.kinglet_spike.unity.ownership.subprocess.run",
            return_value=fake_result,
        ):
            with self.assertRaises(EvidenceError) as ctx:
                _windows_process_table()
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_assert_headless_safe_propagates_provider_failure_rather_than_safe(self):
        def _boom():
            raise EvidenceError("E_UNITY_OWNER_UNKNOWN", "cannot list processes")

        with TemporaryDirectory() as tmp:
            project = Path(tmp)
            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=_boom)
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_posix_process_table_prefers_proc_when_available(self):
        fabricated = ((999, ("Unity", "-projectPath", "/x")),)
        with patch(
            "tools.kinglet_spike.unity.ownership._linux_proc_process_table",
            return_value=fabricated,
        ):
            self.assertEqual(fabricated, _posix_process_table())

    def test_posix_process_table_falls_back_to_ps_when_proc_unavailable(self):
        with patch(
            "tools.kinglet_spike.unity.ownership._linux_proc_process_table",
            return_value=None,
        ), patch(
            "tools.kinglet_spike.unity.ownership._ps_process_table",
            return_value=((1, "fallback"),),
        ) as mock_ps:
            result = _posix_process_table()
            mock_ps.assert_called_once()
            self.assertEqual(((1, "fallback"),), result)


@unittest.skipUnless(Path("/proc").is_dir(), "requires /proc (Linux)")
class LinuxProcProcessTableTests(unittest.TestCase):
    """Grounds the "read exact argv where the OS gives it to you" claim in
    an actual /proc read on this real Linux host, not just trust in the
    fallback wiring."""

    def test_own_pid_appears_with_exact_argv_tuple(self):
        table = dict(_posix_process_table())
        self.assertIn(os.getpid(), table)
        command = table[os.getpid()]
        self.assertIsInstance(command, tuple)
        self.assertGreaterEqual(len(command), 1)

    def test_read_argv_via_proc_matches_own_cmdline(self):
        argv = _read_argv_via_proc(os.getpid())
        self.assertIsNotNone(argv)
        self.assertGreaterEqual(len(argv), 1)

    def test_nonexistent_pid_returns_none(self):
        # A pid that (almost certainly) doesn't exist -- /proc/<pid>/cmdline
        # missing must degrade to None, not raise.
        self.assertIsNone(_read_argv_via_proc(2**30))

    def test_own_comm_is_readable(self):
        comm = _read_comm_via_proc(os.getpid())
        self.assertIsNotNone(comm)

    def test_own_pid_reports_alive(self):
        self.assertTrue(_proc_pid_is_alive(os.getpid()))

    def test_nonexistent_pid_reports_not_alive(self):
        self.assertFalse(_proc_pid_is_alive(2**30))


class LinuxProcPerPidFailureTests(unittest.TestCase):
    """NEW BREAKAGE (round 3): round 2's _linux_proc_process_table dropped
    any pid whose cmdline read failed, silently, with no fallback and no
    signal -- a live Editor could vanish from the table (hidepid, a
    pid-namespace boundary, a permission denial, a decode fault) and read
    as SAFE. It must now fall back to /proc/<pid>/comm and, if that
    confirms the process is Unity-shaped, keep the pid as an
    unconditionally-ambiguous _TruncatedCommand rather than dropping it.
    """

    def test_cmdline_failure_with_unity_comm_is_kept_as_ambiguous(self):
        with patch(
            "tools.kinglet_spike.unity.ownership.os.listdir",
            return_value=["4242"],
        ), patch(
            "tools.kinglet_spike.unity.ownership._read_argv_via_proc",
            return_value=None,
        ), patch(
            "tools.kinglet_spike.unity.ownership._proc_pid_is_alive",
            return_value=True,
        ), patch(
            "tools.kinglet_spike.unity.ownership._read_comm_via_proc",
            return_value="Unity",
        ):
            table = _linux_proc_process_table()
        self.assertEqual(1, len(table))
        pid, command = table[0]
        self.assertEqual(4242, pid)
        self.assertIsInstance(command, _TruncatedCommand)
        self.assertEqual("Unity", command.argv0)

    def test_cmdline_failure_then_ambiguous_entry_refuses_headless(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            table = ((4242, _TruncatedCommand(argv0="Unity")),)
            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=lambda: table)
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_cmdline_failure_with_non_unity_comm_is_dropped_not_ambiguous(self):
        # A permission-denied kernel thread or another user's unrelated
        # process must not force perpetual ambiguity -- only a
        # Unity-shaped comm is kept.
        with patch(
            "tools.kinglet_spike.unity.ownership.os.listdir",
            return_value=["9999"],
        ), patch(
            "tools.kinglet_spike.unity.ownership._read_argv_via_proc",
            return_value=None,
        ), patch(
            "tools.kinglet_spike.unity.ownership._proc_pid_is_alive",
            return_value=True,
        ), patch(
            "tools.kinglet_spike.unity.ownership._read_comm_via_proc",
            return_value="sshd",
        ):
            table = _linux_proc_process_table()
        self.assertEqual((), table)

    def test_cmdline_failure_with_dead_pid_is_dropped(self):
        with patch(
            "tools.kinglet_spike.unity.ownership.os.listdir",
            return_value=["1234"],
        ), patch(
            "tools.kinglet_spike.unity.ownership._read_argv_via_proc",
            return_value=None,
        ), patch(
            "tools.kinglet_spike.unity.ownership._proc_pid_is_alive",
            return_value=False,
        ):
            table = _linux_proc_process_table()
        self.assertEqual((), table)

    def test_cmdline_failure_with_unreadable_comm_is_dropped(self):
        with patch(
            "tools.kinglet_spike.unity.ownership.os.listdir",
            return_value=["4242"],
        ), patch(
            "tools.kinglet_spike.unity.ownership._read_argv_via_proc",
            return_value=None,
        ), patch(
            "tools.kinglet_spike.unity.ownership._proc_pid_is_alive",
            return_value=True,
        ), patch(
            "tools.kinglet_spike.unity.ownership._read_comm_via_proc",
            return_value=None,
        ):
            table = _linux_proc_process_table()
        self.assertEqual((), table)


def _procargs2(argv, *, exec_path="/Applications/Unity/Unity.app/Contents/MacOS/Unity",
               env=("PATH=/usr/bin",), pad=8, argc=None):
    """Build a representative KERN_PROCARGS2 buffer, byte for byte.

    Layout: native-endian int argc | NUL-terminated exec path | NUL
    alignment padding | argc NUL-terminated argv strings | environment.
    """
    count = len(argv) if argc is None else argc
    raw = count.to_bytes(4, sys.byteorder, signed=True)
    raw += exec_path.encode() + b"\x00" + b"\x00" * pad
    for arg in argv:
        raw += arg.encode() + b"\x00"
    for item in env:
        raw += item.encode() + b"\x00"
    return raw


class ParseProcargs2Tests(unittest.TestCase):
    """Round 4 OPEN 1: macOS's exact-argv source, the analogue of Linux's
    /proc/<pid>/cmdline. Parsed here from representative NUL-separated
    bytes so the parser is exercised on this Linux host rather than merely
    reviewed as source text -- the sysctl call itself cannot be run here.
    """

    def test_exact_argv_roundtrip(self):
        argv = (_EDITOR, "-projectPath", "/Users/u/Kinglet", "-logFile", "-")
        self.assertEqual(argv, _parse_procargs2(_procargs2(argv)))

    def test_newline_in_project_path_survives_verbatim(self):
        # The whole point: the kernel delimits with NUL, so the argument
        # that defeats every ps-string reader passes through untouched.
        argv = (_EDITOR, "-projectPath", "/Users/u/proj\n999 Editor")
        self.assertEqual(argv, _parse_procargs2(_procargs2(argv)))

    def test_spaces_and_tabs_survive_verbatim(self):
        argv = (_EDITOR, "-projectPath", "/Users/u/Kinglet - Copy\tX", "-batchmode")
        self.assertEqual(argv, _parse_procargs2(_procargs2(argv)))

    def test_environment_after_argv_is_not_included(self):
        argv = (_EDITOR, "-projectPath", "/Users/u/K")
        parsed = _parse_procargs2(_procargs2(argv, env=("A=1", "B=2")))
        self.assertEqual(argv, parsed)

    def test_zero_padding_length_still_parses(self):
        argv = (_EDITOR, "-quit")
        self.assertEqual(argv, _parse_procargs2(_procargs2(argv, pad=0)))

    def test_truncated_buffer_is_none_not_a_guess(self):
        argv = (_EDITOR, "-projectPath", "/Users/u/K")
        raw = _procargs2(argv)
        self.assertIsNone(_parse_procargs2(raw[: len(raw) - 30]))

    def test_argc_larger_than_available_arguments_is_none(self):
        raw = _procargs2((_EDITOR,), env=(), argc=4)
        self.assertIsNone(_parse_procargs2(raw))

    def test_zero_or_short_buffers_are_none(self):
        self.assertIsNone(_parse_procargs2(b""))
        self.assertIsNone(_parse_procargs2(b"\x00\x01"))
        self.assertIsNone(_parse_procargs2((0).to_bytes(4, sys.byteorder) + b"x\x00"))

    def test_undecodable_bytes_do_not_raise(self):
        raw = (2).to_bytes(4, sys.byteorder) + b"/x\x00" + b"/opt/Unity\x00\xff\xfe\x00"
        parsed = _parse_procargs2(raw)
        self.assertIsNotNone(parsed)
        self.assertEqual(2, len(parsed))

    def test_sysctl_reader_is_none_off_darwin(self):
        # This host is not darwin: the reader must degrade to None (the
        # caller then falls back), never raise.
        if sys.platform != "darwin":
            self.assertIsNone(_read_argv_via_sysctl(os.getpid()))


class MacosProcessTableTests(unittest.TestCase):
    """Round 4 OPEN 1: the macOS table is assembled exactly like the Linux
    /proc one -- exact argv per pid, and a pid whose argv is unreadable is
    held ambiguous (never dropped) when its command name says Unity."""

    def test_exact_argv_entries_are_used_verbatim(self):
        argv = (_EDITOR, "-projectPath", "/Users/u/K")
        table = _build_macos_process_table(
            [7], argv_reader=lambda pid: argv, comm_reader=lambda pid: None
        )
        self.assertEqual(((7, argv),), table)

    def test_unreadable_argv_with_unity_comm_is_kept_ambiguous(self):
        table = _build_macos_process_table(
            [7], argv_reader=lambda pid: None, comm_reader=lambda pid: _EDITOR
        )
        self.assertEqual(1, len(table))
        self.assertIsInstance(table[0][1], _TruncatedCommand)

    def test_unreadable_argv_with_non_unity_comm_is_dropped(self):
        table = _build_macos_process_table(
            [7],
            argv_reader=lambda pid: None,
            comm_reader=lambda pid: "/usr/bin/unityhub",
        )
        self.assertEqual((), table)

    def test_unreadable_argv_and_unreadable_comm_is_dropped(self):
        table = _build_macos_process_table(
            [7], argv_reader=lambda pid: None, comm_reader=lambda pid: None
        )
        self.assertEqual((), table)

    def test_newline_project_path_is_detected_as_owned_end_to_end(self):
        # The durable fix for OPEN 1: the same directory name that reads
        # SAFE through any ps-string pipeline is confirmed OWNED when argv
        # comes from the kernel.
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj\n999 Editor"
            project.mkdir()
            (Path(tmp) / "proj").mkdir()
            argv = _parse_procargs2(
                _procargs2((_EDITOR, "-projectPath", str(project), "-logFile", "-"))
            )
            table = _build_macos_process_table(
                [4242], argv_reader=lambda pid: argv, comm_reader=lambda pid: None
            )
            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=lambda: table)
            self.assertEqual("E_UNITY_OWNED", ctx.exception.code)

    def test_pid_list_parser_takes_only_integer_lines(self):
        self.assertEqual((1, 4242), _parse_pid_list("    1\n  4242\n999 Editor\n\n"))

    def test_pid_list_parser_deduplicates(self):
        self.assertEqual((5,), _parse_pid_list("5\n5\n"))

    def test_comm_map_parser(self):
        mapping = _parse_comm_map(f"  1 /sbin/launchd\n 4242 {_EDITOR}\nbad line\n")
        self.assertEqual({1: "/sbin/launchd", 4242: _EDITOR}, mapping)

    def test_macos_table_wires_ps_enumeration_to_kernel_argv(self):
        argv = (_EDITOR, "-projectPath", "/Users/u/K")
        with patch(
            "tools.kinglet_spike.unity.ownership._run_ps",
            side_effect=["  4242\n", f"  4242 {_EDITOR}\n"],
        ), patch(
            "tools.kinglet_spike.unity.ownership._read_argv_via_sysctl",
            return_value=argv,
        ):
            self.assertEqual(((4242, argv),), _macos_process_table())

    def test_macos_table_propagates_enumeration_failure_rather_than_empty(self):
        with patch(
            "tools.kinglet_spike.unity.ownership._run_ps",
            side_effect=EvidenceError("E_UNITY_OWNER_UNKNOWN", "no ps"),
        ):
            with self.assertRaises(EvidenceError):
                _macos_process_table()

    # --- FINAL whole-branch review, IMPORTANT 7: `except EvidenceError:
    #     comm_map = {}` disabled the ambiguity fallback for EVERY pid at
    #     once, turning "I could not look" into "nothing to see".

    def test_comm_listing_failure_does_not_silently_empty_the_fallback(self):
        # ps enumerates one pid; the argv read fails (an elevated / other-user
        # Editor); the comm listing then fails too. With the swallow in place
        # this returned an EMPTY table -- a live Editor vanished and the host
        # read as SAFE. The honest answer is E_UNITY_OWNER_UNKNOWN.
        with patch(
            "tools.kinglet_spike.unity.ownership._run_ps",
            side_effect=["  4242\n", EvidenceError("E_UNITY_OWNER_UNKNOWN", "no ps")],
        ), patch(
            "tools.kinglet_spike.unity.ownership._read_argv_via_sysctl",
            return_value=None,
        ):
            with self.assertRaises(EvidenceError) as caught:
                _macos_process_table()
        self.assertEqual("E_UNITY_OWNER_UNKNOWN", caught.exception.code)

    def test_sysctl_reader_survives_a_ctypes_argument_error(self):
        # ctypes.ArgumentError derives from Exception, not from OSError /
        # ValueError / AttributeError / MemoryError, so a pid that does not
        # fit c_int escaped the handler entirely and broke the module's
        # "every route yields E_UNITY_OWNER_UNKNOWN" guarantee on macOS.
        import ctypes as _ctypes

        class _Libc:
            def __getattr__(self, name):
                raise _ctypes.ArgumentError("argument 3: int too long to convert")

        with patch("tools.kinglet_spike.unity.ownership.sys.platform", "darwin"), patch(
            "ctypes.CDLL", side_effect=_ctypes.ArgumentError("boom")
        ):
            self.assertIsNone(ownership._read_procargs2_bytes(2**63))

    def test_posix_dispatch_uses_macos_table_on_darwin(self):
        fabricated = ((9, ("Unity", "-projectPath", "/x")),)
        with patch("tools.kinglet_spike.unity.ownership.sys.platform", "darwin"), patch(
            "tools.kinglet_spike.unity.ownership._macos_process_table",
            return_value=fabricated,
        ):
            self.assertEqual(fabricated, _posix_process_table())


class PsFallbackFailsClosedTests(unittest.TestCase):
    """Round 4 OPEN 1, the class rather than the instance: `ps -axo
    command=` cannot be trusted at the LINE level either. A project
    directory named `proj\n999 Editor` makes ps emit a tail line that
    parses cleanly as `<pid> <command>`, so nothing fails to parse, the
    round-3 truncation detector never fires, and the Editor's own entry
    reads as a complete command line ending at `.../proj` -- which exists,
    so the slicer confidently rules the real owner out. Reproduced against
    the pre-fix code as SAFE TO LAUNCH. `ps` is now last-resort only and
    fails closed for Unity-shaped entries.
    """

    def _newline_stdout(self, project: Path) -> str:
        # Byte-for-byte what real `ps -axo pid=,command=` prints for this
        # argv: the newline inside the path is emitted verbatim.
        return f"  4242 {_EDITOR} -projectPath {project} -logFile -\n"

    def test_parseable_tail_via_real_parser_must_not_read_safe(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj\n999 Editor"
            project.mkdir()
            (Path(tmp) / "proj").mkdir()  # the truncated prefix EXISTS
            table = _parse_posix_process_table(
                self._newline_stdout(project), fail_closed_unity=True
            )
            # Sanity: the tail really does parse as its own clean entry.
            self.assertEqual(2, len(table))
            self.assertIn(999, [pid for pid, _ in table])
            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=lambda: table)
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_ps_process_table_marks_unity_entries_ambiguous(self):
        with TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj\n999 Editor"
            project.mkdir()
            (Path(tmp) / "proj").mkdir()
            fake = SimpleNamespace(
                returncode=0, stdout=self._newline_stdout(project), stderr=""
            )
            with patch(
                "tools.kinglet_spike.unity.ownership.subprocess.run", return_value=fake
            ):
                table = _ps_process_table()
            unity_entries = [c for _pid, c in table if isinstance(c, _TruncatedCommand)]
            self.assertEqual(1, len(unity_entries))
            self.assertEqual(_EDITOR, unity_entries[0].argv0)
            with self.assertRaises(EvidenceError) as ctx:
                assert_headless_safe(project, process_table_provider=lambda: table)
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_ps_fallback_leaves_non_unity_entries_alone(self):
        stdout = "  1 /sbin/launchd\n  2 /usr/bin/unityhub --gpu\n"
        table = _parse_posix_process_table(stdout, fail_closed_unity=True)
        self.assertEqual(
            (
                (1, "/sbin/launchd"),
                (2, "/usr/bin/unityhub --gpu"),
            ),
            table,
        )

    def test_ps_parser_default_is_unchanged(self):
        # The pure parser keeps its old behaviour by default; only the
        # last-resort provider opts into failing closed.
        table = _parse_posix_process_table(f"  4242 {_EDITOR} -projectPath /x\n")
        self.assertEqual(((4242, f"{_EDITOR} -projectPath /x"),), table)


class UnreadableCandidateParentTests(unittest.TestCase):
    """Round 4 OPEN 2: a candidate under an unreadable parent makes the
    existence probe raise PermissionError on Python 3.13 and read as
    "absent" on <=3.12. Both are wrong: a raw OSError escapes this
    module's EvidenceError contract entirely, and "absent" is a RESOLVED
    answer we are not entitled to. Pinned here to ONE behaviour on every
    interpreter -- ambiguity, therefore E_UNITY_OWNER_UNKNOWN.
    """

    def _locked_tree(self, tmp: str):
        parent = Path(tmp) / "locked"
        parent.mkdir()
        (parent / "proj").mkdir()
        os.chmod(parent, 0o000)
        return parent

    @unittest.skipIf(os.geteuid() == 0, "root bypasses directory permissions")
    def test_unreadable_candidate_parent_refuses_rather_than_raising(self):
        with TemporaryDirectory() as tmp:
            parent = self._locked_tree(tmp)
            target = Path(tmp) / "other"
            target.mkdir()
            table = [(1, _raw_unity_command(str(parent / "proj"), " extraarg"))]
            try:
                with self.assertRaises(EvidenceError) as ctx:
                    assert_headless_safe(
                        target, process_table_provider=lambda: table
                    )
                self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)
                owner = find_owning_process(table, target)
                self.assertIsNotNone(owner, "unknown must never read SAFE")
                self.assertFalse(owner.confirmed)
                self.assertEqual("process-ambiguous", owner.source)
            finally:
                os.chmod(parent, 0o700)

    @unittest.skipIf(os.geteuid() == 0, "root bypasses directory permissions")
    def test_probe_helpers_report_unknown_not_absent(self):
        with TemporaryDirectory() as tmp:
            parent = self._locked_tree(tmp)
            try:
                candidate = parent / "proj"
                resolved = _canonical_or_none(candidate)
                if resolved is not None:
                    self.assertIsNot(False, _is_dir_or_unknown(resolved))
                    self.assertIsNone(_is_dir_or_unknown(resolved))
            finally:
                os.chmod(parent, 0o700)

    def test_uncanonicalizable_candidate_is_ambiguous_not_a_non_match(self):
        # Pinned independently of interpreter version and of which call
        # (resolve vs is_dir) happens to raise on a given Python: a
        # candidate we cannot canonicalize is UNKNOWN, and unknown must
        # never quietly read as "a different path, therefore safe".
        real = ownership._canonical

        def _raising(path):
            if "locked" in str(path):
                raise PermissionError(13, "Permission denied")
            return real(path)

        with TemporaryDirectory() as tmp:
            target = Path(tmp) / "Kinglet"
            target.mkdir()
            table = [(1, _raw_unity_command("/nowhere/locked/proj", " -logFile -"))]
            with patch.object(ownership, "_canonical", side_effect=_raising):
                owner = find_owning_process(table, target)
            self.assertIsNotNone(owner, "unknown must never read SAFE")
            self.assertFalse(owner.confirmed)
            self.assertEqual("process-ambiguous", owner.source)

    def test_one_existing_candidate_plus_one_unknown_is_still_ambiguous(self):
        # The disambiguation shortcut ("exactly one candidate is a real
        # directory, so this process's true path is established") is only
        # valid when every OTHER candidate was actually PROBED. If one of
        # them could not be probed at all, the shortcut is a guess.
        real = ownership._canonical

        def _raising(path):
            if "-logFile" in str(path):
                raise PermissionError(13, "Permission denied")
            return real(path)

        with TemporaryDirectory() as tmp:
            open_project = Path(tmp) / "OtherGame"
            open_project.mkdir()
            target = Path(tmp) / "Kinglet"
            target.mkdir()
            table = [(1, _raw_unity_command(str(open_project), " -logFile -"))]
            with patch.object(ownership, "_canonical", side_effect=_raising):
                owner = find_owning_process(table, target)
            self.assertIsNotNone(owner, "an unprobed candidate must not read SAFE")
            self.assertFalse(owner.confirmed)
            self.assertEqual("process-ambiguous", owner.source)

    def test_exact_argv_candidate_that_cannot_be_canonicalized_is_ambiguous(self):
        # An exact-argv non-match is normally definitive -- but only if the
        # comparison actually happened. A value we could not canonicalize
        # was never compared.
        real = ownership._canonical

        def _raising(path):
            if "locked" in str(path):
                raise PermissionError(13, "Permission denied")
            return real(path)

        with TemporaryDirectory() as tmp:
            target = Path(tmp) / "Kinglet"
            target.mkdir()
            argv = (_EDITOR, "-projectPath", "/nowhere/locked/proj")
            with patch.object(ownership, "_canonical", side_effect=_raising):
                owner = find_owning_process([(1, argv)], target)
            self.assertIsNotNone(owner, "unknown must never read SAFE")
            self.assertFalse(owner.confirmed)
            self.assertEqual("process-ambiguous", owner.source)

    def test_uncanonicalizable_target_raises_evidence_error_not_oserror(self):
        with TemporaryDirectory() as tmp:
            with patch.object(
                ownership, "_canonical", side_effect=PermissionError(13, "denied")
            ):
                with self.assertRaises(EvidenceError) as ctx:
                    find_owning_process([], Path(tmp))
            self.assertEqual("E_UNITY_OWNER_UNKNOWN", ctx.exception.code)

    def test_unprobeable_directory_check_is_ambiguous_not_absent(self):
        # Same shortcut as above, but with the failure arising from the
        # is_dir() probe itself (Python 3.13's behaviour) rather than from
        # canonicalization -- pinned so the outcome does not depend on
        # which call the running interpreter raises in.
        real_is_dir = Path.is_dir

        def _raising(self, *args, **kwargs):
            if "-logFile" in str(self):
                raise PermissionError(13, "Permission denied")
            return real_is_dir(self, *args, **kwargs)

        with TemporaryDirectory() as tmp:
            open_project = Path(tmp) / "OtherGame"
            open_project.mkdir()
            target = Path(tmp) / "Kinglet"
            target.mkdir()
            table = [(1, _raw_unity_command(str(open_project), " -logFile -"))]
            with patch.object(Path, "is_dir", _raising):
                owner = find_owning_process(table, target)
            self.assertIsNotNone(owner, "an unprobeable candidate must not read SAFE")
            self.assertFalse(owner.confirmed)
            self.assertEqual("process-ambiguous", owner.source)

    def test_unprobeable_proc_pid_counts_as_alive_not_gone(self):
        # A pid we cannot probe must not be treated as "already exited" --
        # that is how a live Editor vanishes from the table.
        with patch.object(ownership, "_is_dir_or_unknown", return_value=None):
            self.assertTrue(_proc_pid_is_alive(1234))

    def test_helpers_are_total_on_ordinary_paths(self):
        with TemporaryDirectory() as tmp:
            self.assertEqual(Path(tmp).resolve(), _canonical_or_none(tmp))
            self.assertTrue(_is_dir_or_unknown(Path(tmp)))
            self.assertFalse(_is_dir_or_unknown(Path(tmp) / "nope"))


class UsabilityMustNotOverRefuseTests(unittest.TestCase):
    """A module that always refuses is safe but useless. These are the four
    real macOS command-line shapes a reviewer confirmed must keep letting
    an UNRELATED run proceed: the open project's true path is the first
    flag-boundary slice, it exists on disk, longer slices do not, so
    exactly one candidate resolves and the process is positively ruled out.
    """

    def _assert_unrelated_run_proceeds(self, trailing: str):
        with TemporaryDirectory() as tmp:
            open_project = Path(tmp) / "OtherGame"
            open_project.mkdir()
            target = Path(tmp) / "Kinglet"
            target.mkdir()
            table = [(4242, _raw_unity_command(str(open_project), trailing))]
            self.assertIsNone(
                find_owning_process(table, target),
                f"trailing {trailing!r} must not block an unrelated launch",
            )
            assert_headless_safe(target, process_table_provider=lambda: table)

    def test_project_path_is_last_argument(self):
        self._assert_unrelated_run_proceeds("")

    def test_hub_style_tail(self):
        self._assert_unrelated_run_proceeds(
            " -useHub -hubIPC -cloudEnvironment production "
            "-licensingIpc LicenseClient-u -hubSessionId abc -accessToken tok123"
        )

    def test_logfile_dash_tail(self):
        self._assert_unrelated_run_proceeds(" -logFile -")

    def test_positional_tail(self):
        self._assert_unrelated_run_proceeds(" -openfile /Users/u/OtherGame/x.unity")


if __name__ == "__main__":
    unittest.main()
