# Kinglet Win32 Evidence Publication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the incomplete Windows evidence-publication fallback with a native, immutable, handle-relative implementation that passes real Windows 10 NTFS acceptance tests.

**Architecture:** `publish.py` keeps record orchestration and the accepted POSIX backend. A Windows-only `win32_publish.py` module owns fixed-width `ctypes` ABI definitions, a held `CreateFileW` repository anchor, `NtCreateFile` relative directory/target operations, native writes, exact-handle cleanup, and deterministic handle ownership.

**Tech Stack:** Python 3 standard library, `ctypes`, Win32 `kernel32.dll`, Native API `ntdll.dll`, `unittest`, native PowerShell, NTFS.

## Global Constraints

- Python standard library only; do not add PyWin32 or another dependency.
- Do not import from `tools/kinglet_build` or a product-runtime candidate.
- `publish_record(raw_path, repo_root) -> Path` remains the public interface.
- Windows execution is native PowerShell execution, not WSL or Git Bash.
- Windows 10 x64 is the Task 3 native acceptance host.
- Windows 11 x64 remains a final 00A platform-validation target.
- The accepted POSIX held-directory-descriptor behavior must not change.
- No committed record or artifact may escape `docs/research/platform-spike/`.
- Existing targets are immutable and may never be replaced or deleted.
- Reparse points, alternate data streams, unsafe Windows names, and path traversal fail closed.
- Cleanup may act only on the exact native target handle created by this invocation.
- Never use `DeleteFileW`, `Path.unlink`, or pathname deletion in the Windows backend.
- The evidence-v1 field and diagnostic-code lists remain unchanged.
- A cleanup or target-close failure uses `E_IMMUTABLE` with an uncertain-target detail.
- JSON output remains UTF-8, LF, sorted-key, deterministic, and newline-terminated.
- Portable mocks prove control flow and ABI declarations; only native Windows tests prove Win32 behavior.
- The Bash aggregate remains a Linux gate; native Windows runs every Python suite directly.

---

## File Map

| Path | Responsibility |
| --- | --- |
| `tools/kinglet_spike/win32_publish.py` | Windows name contract, ABI, relative handle walk, target lifecycle |
| `tools/kinglet_spike/publish.py` | Platform-neutral orchestration, POSIX writer, backend selection |
| `tests/kinglet_spike/test_win32_publish.py` | Portable lexical, ABI, ownership, and failure-order tests |
| `tests/kinglet_spike/test_win32_publish_native.py` | Real Windows 10 NTFS acceptance tests |
| `tests/run-win32-publication.ps1` | Native PowerShell baseline and acceptance wrapper |
| `docs/superpowers/runbooks/2026-07-23-win32-publication-handoff.md` | Checkout, execution, evidence, and push procedure |

## Stable Internal Interfaces

```python
# tools/kinglet_spike/win32_publish.py
validate_component: Callable[[str, str], str]

class Win32CreatedTarget(Protocol):
    write: Callable[[bytes], None]
    flush: Callable[[], None]
    commit: Callable[[], None]
    abort: Callable[[BaseException], NoReturn]

create_exclusive_target: Callable[
    [Path, Path, Path, str],
    Win32CreatedTarget,
]
```

`ops` is an injectable internal boundary for portable contract tests and
native failure injection. Production calls omit it and load the real Windows
implementation. Raw native handles never leave `win32_publish.py`.

### Task 1: Freeze the Windows name and ABI contract

**Files:**
- Create: `tools/kinglet_spike/win32_publish.py`
- Create: `tests/kinglet_spike/test_win32_publish.py`

**Interfaces:**
- Consumes: already-safe logical path components from `publish.py`.
- Produces: `validate_component()`, fixed-width native structures, `NativeName`, and constants used by later tasks.

- [ ] **Step 1: Add failing lexical and structure-layout tests**

Create these tests:

```python
# tests/kinglet_spike/test_win32_publish.py
import ctypes
import unittest

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.win32_publish import (
    FILE_DISPOSITION_INFO,
    IO_STATUS_BLOCK,
    OBJECT_ATTRIBUTES,
    UNICODE_STRING,
    NativeName,
    validate_component,
)


class Win32ContractTests(unittest.TestCase):
    def test_accepts_portable_opaque_components(self):
        self.assertEqual("runtime", validate_component("runtime", "component"))
        self.assertEqual("naïve-file.json", validate_component("naïve-file.json", "component"))

    def test_rejects_windows_unsafe_components(self):
        rejected = (
            "", ".", "..", "child/name", r"child\name", "stream:name",
            "trailing.", "trailing ", "NUL", "nul.txt", "COM1", "lpt9.log",
            "control\x1f", "\x00",
        )
        for value in rejected:
            with self.subTest(value=value):
                with self.assertRaisesRegex(EvidenceError, "E_PATH"):
                    validate_component(value, "component")

    def test_x64_abi_layout_is_fixed_width(self):
        if ctypes.sizeof(ctypes.c_void_p) != 8:
            self.skipTest("00A Windows native target is x64")
        self.assertEqual(16, ctypes.sizeof(UNICODE_STRING))
        self.assertEqual(48, ctypes.sizeof(OBJECT_ATTRIBUTES))
        self.assertEqual(16, ctypes.sizeof(IO_STATUS_BLOCK))
        self.assertEqual(1, ctypes.sizeof(FILE_DISPOSITION_INFO))
        self.assertEqual(8, UNICODE_STRING.Buffer.offset)
        self.assertEqual(8, OBJECT_ATTRIBUTES.RootDirectory.offset)
        self.assertEqual(16, OBJECT_ATTRIBUTES.ObjectName.offset)
        self.assertEqual(24, OBJECT_ATTRIBUTES.Attributes.offset)
        self.assertEqual(8, IO_STATUS_BLOCK.Information.offset)

    def test_native_name_uses_utf16_byte_lengths(self):
        name = NativeName("naïve")
        self.assertEqual(len("naïve".encode("utf-16-le")), name.value.Length)
        self.assertEqual(name.value.Length + 2, name.value.MaximumLength)
```

- [ ] **Step 2: Run the tests and verify the missing module**

Run:

```text
python -m unittest tests.kinglet_spike.test_win32_publish.Win32ContractTests -v
```

Expected: import error for `tools.kinglet_spike.win32_publish`.

- [ ] **Step 3: Implement the exact lexical and ABI surface**

Use fixed-width fields, not host-C `long`:

```python
# tools/kinglet_spike/win32_publish.py
from __future__ import annotations

import ctypes
from dataclasses import dataclass
from pathlib import Path
import re
from typing import NoReturn, Protocol

from tools.kinglet_spike.model import EvidenceError


USHORT = ctypes.c_uint16
ULONG = ctypes.c_uint32
NTSTATUS = ctypes.c_int32
ULONG_PTR = ctypes.c_size_t
HANDLE = ctypes.c_void_p
PWSTR16 = ctypes.POINTER(ctypes.c_uint16)

RESERVED_DEVICE = re.compile(
    r"(?i)^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$"
)
CONTROL = re.compile(r"[\x00-\x1f]")


def validate_component(value: str, location: str) -> str:
    if (
        not value
        or value in {".", ".."}
        or any(character in value for character in "/\\:")
        or CONTROL.search(value)
        or value.endswith((" ", "."))
        or RESERVED_DEVICE.fullmatch(value)
        or len(value.encode("utf-8")) > 128
    ):
        raise EvidenceError("E_PATH", f"{location} is not a safe Windows path component")
    return value


class UNICODE_STRING(ctypes.Structure):
    _fields_ = [
        ("Length", USHORT),
        ("MaximumLength", USHORT),
        ("Buffer", PWSTR16),
    ]


class OBJECT_ATTRIBUTES(ctypes.Structure):
    _fields_ = [
        ("Length", ULONG),
        ("RootDirectory", HANDLE),
        ("ObjectName", ctypes.POINTER(UNICODE_STRING)),
        ("Attributes", ULONG),
        ("SecurityDescriptor", ctypes.c_void_p),
        ("SecurityQualityOfService", ctypes.c_void_p),
    ]


class _IO_STATUS_BLOCK_VALUE(ctypes.Union):
    _fields_ = [("Status", NTSTATUS), ("Pointer", ctypes.c_void_p)]


class IO_STATUS_BLOCK(ctypes.Structure):
    _anonymous_ = ("value",)
    _fields_ = [("value", _IO_STATUS_BLOCK_VALUE), ("Information", ULONG_PTR)]


class FILE_DISPOSITION_INFO(ctypes.Structure):
    _fields_ = [("DeleteFile", ctypes.c_ubyte)]


class NativeName:
    def __init__(self, text: str):
        encoded = text.encode("utf-16-le")
        units = len(encoded) // 2
        self._buffer = (ctypes.c_uint16 * (units + 1))()
        ctypes.memmove(self._buffer, encoded, len(encoded))
        self.value = UNICODE_STRING(
            Length=len(encoded),
            MaximumLength=len(encoded) + 2,
            Buffer=ctypes.cast(self._buffer, PWSTR16),
        )
```

Add these fixed-width structures:

```python
class FILETIME(ctypes.Structure):
    _fields_ = [
        ("dwLowDateTime", ULONG),
        ("dwHighDateTime", ULONG),
    ]


class BY_HANDLE_FILE_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("dwFileAttributes", ULONG),
        ("ftCreationTime", FILETIME),
        ("ftLastAccessTime", FILETIME),
        ("ftLastWriteTime", FILETIME),
        ("dwVolumeSerialNumber", ULONG),
        ("nFileSizeHigh", ULONG),
        ("nFileSizeLow", ULONG),
        ("nNumberOfLinks", ULONG),
        ("nFileIndexHigh", ULONG),
        ("nFileIndexLow", ULONG),
    ]
```

Then add the complete constant table from the design:

```python
GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
DELETE = 0x00010000
SYNCHRONIZE = 0x00100000
FILE_READ_ATTRIBUTES = 0x00000080
FILE_SHARE_READ = 0x00000001
FILE_SHARE_WRITE = 0x00000002
OPEN_EXISTING = 3
FILE_FLAG_BACKUP_SEMANTICS = 0x02000000
FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000
FILE_ATTRIBUTE_DIRECTORY = 0x00000010
FILE_ATTRIBUTE_REPARSE_POINT = 0x00000400
FILE_ATTRIBUTE_NORMAL = 0x00000080
FILE_LIST_DIRECTORY = 0x00000001
FILE_ADD_FILE = 0x00000002
FILE_ADD_SUBDIRECTORY = 0x00000004
FILE_TRAVERSE = 0x00000020
OBJ_CASE_INSENSITIVE = 0x00000040
OBJ_DONT_REPARSE = 0x00001000
FILE_CREATE = 2
FILE_OPEN_IF = 3
FILE_DIRECTORY_FILE = 0x00000001
FILE_SYNCHRONOUS_IO_NONALERT = 0x00000020
FILE_NON_DIRECTORY_FILE = 0x00000040
STATUS_OBJECT_NAME_COLLISION = ctypes.c_int32(0xC0000035).value
STATUS_REPARSE_POINT_ENCOUNTERED = ctypes.c_int32(0xC000050B).value
FILE_DISPOSITION_INFORMATION_CLASS = 4
INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value
DIRECTORY_ACCESS = (
    FILE_LIST_DIRECTORY
    | FILE_ADD_FILE
    | FILE_ADD_SUBDIRECTORY
    | FILE_TRAVERSE
    | FILE_READ_ATTRIBUTES
    | SYNCHRONIZE
)
TARGET_ACCESS = GENERIC_WRITE | FILE_READ_ATTRIBUTES | DELETE | SYNCHRONIZE
```

- [ ] **Step 4: Run focused and existing harness tests**

Run:

```text
python -m unittest tests.kinglet_spike.test_win32_publish.Win32ContractTests -v
python -m unittest discover -s tests/kinglet_spike -t . -v
```

Expected: the four new tests pass; the existing 28 harness tests remain green.

- [ ] **Step 5: Commit the contract**

```text
git add tools/kinglet_spike/win32_publish.py tests/kinglet_spike/test_win32_publish.py
git commit -m "test: freeze Win32 publication contract"
```

### Task 2: Bind the native APIs without import-time side effects

**Files:**
- Modify: `tools/kinglet_spike/win32_publish.py`
- Modify: `tests/kinglet_spike/test_win32_publish.py`

**Interfaces:**
- Consumes: fixed ABI types and constants from Task 1.
- Produces: `Win32Ops.load()`, native status conversion, final-path lookup, handle information, write, flush, delete-mark, and close primitives.

- [ ] **Step 1: Add failing DLL-binding and error tests**

Extend the test imports exactly as follows:

```python
import os
from dataclasses import dataclass, field
from pathlib import Path
from unittest import mock

from tools.kinglet_spike.win32_publish import (
    DIRECTORY_ACCESS,
    FILE_CREATE,
    FILE_DIRECTORY_FILE,
    FILE_FLAG_BACKUP_SEMANTICS,
    FILE_FLAG_OPEN_REPARSE_POINT,
    FILE_NON_DIRECTORY_FILE,
    FILE_OPEN_IF,
    FILE_SHARE_READ,
    FILE_SHARE_WRITE,
    FILE_SYNCHRONOUS_IO_NONALERT,
    INVALID_HANDLE_VALUE,
    NativeFileInfo,
    OBJECT_ATTRIBUTES,
    STATUS_OBJECT_NAME_COLLISION,
    STATUS_REPARSE_POINT_ENCOUNTERED,
    TARGET_ACCESS,
    Win32Ops,
)
```

Add a callable fake that records assigned signatures:

```python
class FakeFunction:
    def __init__(self, result=1):
        self.result = result
        self.side_effect = None
        self.calls = []
        self.argtypes = None
        self.restype = None

    def __call__(self, *arguments):
        self.calls.append(arguments)
        if self.side_effect is not None:
            return self.side_effect(*arguments)
        return self.result


class FakeLibrary:
    def __init__(self):
        for name in (
            "CreateFileW", "GetFileInformationByHandle",
            "GetFinalPathNameByHandleW", "CompareStringOrdinal", "WriteFile",
            "FlushFileBuffers", "SetFileInformationByHandle", "CloseHandle",
            "NtCreateFile", "RtlNtStatusToDosError",
        ):
            setattr(self, name, FakeFunction())
        self.NtCreateFile.result = 0


@dataclass
class FakeObject:
    name: str
    path: str
    is_directory: bool
    reparse: bool = False
    content: bytearray = field(default_factory=bytearray)


class FakeWin32Ops:
    def __init__(
        self,
        *,
        reparse_component=None,
        fail_at=None,
        fail_cleanup=False,
        fail_close=False,
        fail_directory_close=False,
        collision=False,
    ):
        self.reparse_component = reparse_component
        self.fail_at = fail_at
        self.fail_cleanup = fail_cleanup
        self.fail_close = fail_close
        self.fail_directory_close = fail_directory_close
        self.collision = collision
        self.objects = {}
        self.paths = {}
        self.closed = []
        self.events = []
        self.directory_calls = []
        self.target_calls = []
        self.created_targets = []
        self.delete_marks = []
        self.flush_count = 0
        self.pathname_delete_called = False
        self._next_handle = 100
        self._all_handles = []

    def _register(self, value):
        handle = self._next_handle
        self._next_handle += 1
        self.objects[handle] = value
        self.paths[value.path.casefold()] = handle
        self._all_handles.append(handle)
        return handle

    def open_repository(self, path):
        text = str(path)
        return self._register(FakeObject("repo", text, True))

    def open_directory(self, parent, component):
        self.directory_calls.append((parent, component))
        parent_object = self.objects[parent]
        path = parent_object.path.rstrip("\\") + "\\" + component
        return self._register(
            FakeObject(
                component,
                path,
                True,
                reparse=component == self.reparse_component,
            )
        )

    def create_target(self, parent, component, immutable_message):
        self.target_calls.append((parent, component))
        if self.collision:
            raise EvidenceError("E_IMMUTABLE", immutable_message)
        parent_object = self.objects[parent]
        value = FakeObject(
            component,
            parent_object.path.rstrip("\\") + "\\" + component,
            False,
        )
        handle = self._register(value)
        self.created_targets.append(handle)
        self.events.append("create-target")
        return handle

    def final_path(self, handle):
        if self.fail_at == "final_path" and not self.objects[handle].is_directory:
            raise OSError("final_path")
        return self.objects[handle].path

    def file_information(self, handle):
        value = self.objects[handle]
        return NativeFileInfo(
            is_directory=value.is_directory,
            is_reparse=value.reparse,
        )

    def write(self, handle, content):
        if self.fail_at == "write":
            raise OSError("write")
        self.objects[handle].content.extend(content)
        self.events.append("write")

    def flush(self, handle):
        if self.fail_at == "flush":
            raise OSError("flush")
        self.flush_count += 1
        self.events.append("flush")

    def mark_delete(self, handle):
        self.events.append("mark-delete")
        if self.fail_cleanup:
            raise OSError("cleanup")
        self.delete_marks.append(handle)

    def close(self, handle):
        value = self.objects[handle]
        self.events.append("close-dir" if value.is_directory else "close-target")
        self.closed.append(handle)
        if self.fail_close and not value.is_directory:
            raise OSError("close")
        if self.fail_directory_close and value.is_directory:
            raise OSError("directory close")

    def ordinal_equal(self, left, right):
        return left.casefold() == right.casefold()

    def replace_pathname(self, path):
        replacement = FakeObject("replacement", path, True)
        return self._register(replacement)

    def handle_for_path(self, path):
        return self.paths[str(path).casefold()]

    @property
    def target_bytes(self):
        return bytes(self.objects[self.created_targets[-1]].content)

    @property
    def attempted_every_close(self):
        return set(self.closed) == set(self._all_handles)

    def all_handles_closed_once(self):
        return (
            len(self.closed) == len(self._all_handles)
            and len(set(self.closed)) == len(self.closed)
        )

class Win32BindingTests(unittest.TestCase):
    def test_binds_every_function_with_explicit_signatures(self):
        kernel32 = FakeLibrary()
        ntdll = FakeLibrary()
        ops = Win32Ops.from_libraries(kernel32, ntdll)
        self.assertIs(ctypes.c_void_p, kernel32.CreateFileW.restype)
        self.assertIs(ctypes.c_int32, ntdll.NtCreateFile.restype)
        self.assertEqual(7, len(kernel32.CreateFileW.argtypes))
        self.assertEqual(11, len(ntdll.NtCreateFile.argtypes))
        for name in ops.bound_function_names:
            function = getattr(
                ntdll if name in {"NtCreateFile", "RtlNtStatusToDosError"} else kernel32,
                name,
            )
            self.assertIsNotNone(function.argtypes)
            self.assertIsNotNone(function.restype)
        self.assertEqual(10, len(ops.bound_function_names))

    def test_repository_open_uses_exact_flags_and_captures_last_error(self):
        kernel32 = FakeLibrary()
        ntdll = FakeLibrary()
        kernel32.CreateFileW.result = INVALID_HANDLE_VALUE
        ops = Win32Ops.from_libraries(kernel32, ntdll)
        with mock.patch("ctypes.get_last_error", return_value=123) as last_error:
            with self.assertRaisesRegex(OSError, "123"):
                ops.open_repository(Path(r"C:\repo"))
        last_error.assert_called_once_with()
        arguments = kernel32.CreateFileW.calls[0]
        self.assertEqual(DIRECTORY_ACCESS, arguments[1])
        self.assertEqual(FILE_SHARE_READ | FILE_SHARE_WRITE, arguments[2])
        self.assertEqual(
            FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
            arguments[5],
        )

    def test_relative_directory_and_target_calls_use_exact_contract(self):
        kernel32 = FakeLibrary()
        ntdll = FakeLibrary()

        def return_handle(*arguments):
            output = ctypes.cast(arguments[0], ctypes.POINTER(ctypes.c_void_p))
            output.contents.value = 77
            return 0

        ntdll.NtCreateFile.side_effect = return_handle
        ops = Win32Ops.from_libraries(kernel32, ntdll)
        self.assertEqual(77, ops.open_directory(41, "research"))
        directory = ntdll.NtCreateFile.calls[-1]
        attributes = ctypes.cast(
            directory[2], ctypes.POINTER(OBJECT_ATTRIBUTES)
        ).contents
        self.assertEqual(41, attributes.RootDirectory)
        self.assertEqual(DIRECTORY_ACCESS, directory[1])
        self.assertEqual(FILE_SHARE_READ | FILE_SHARE_WRITE, directory[6])
        self.assertEqual(FILE_OPEN_IF, directory[7])
        self.assertEqual(
            FILE_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT,
            directory[8],
        )

        self.assertEqual(
            77, ops.create_target(41, "run.json", "already published")
        )
        target = ntdll.NtCreateFile.calls[-1]
        self.assertEqual(TARGET_ACCESS, target[1])
        self.assertEqual(0, target[6])
        self.assertEqual(FILE_CREATE, target[7])
        self.assertEqual(
            FILE_NON_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT,
            target[8],
        )

    def test_path_comparison_is_case_insensitive_and_ordinal(self):
        kernel32 = FakeLibrary()
        ntdll = FakeLibrary()
        kernel32.CompareStringOrdinal.result = 2
        ops = Win32Ops.from_libraries(kernel32, ntdll)
        self.assertTrue(ops.ordinal_equal(r"C:\Repo", r"c:\repo"))
        self.assertEqual(
            (r"C:\Repo", -1, r"c:\repo", -1, 1),
            kernel32.CompareStringOrdinal.calls[-1],
        )

    def test_final_path_resizes_before_returning_unicode(self):
        kernel32 = FakeLibrary()
        ntdll = FakeLibrary()

        def final_path(handle, buffer, size, flags):
            if size == 260:
                return 300
            buffer.value = r"\\?\C:\repo\kanıt"
            return len(buffer.value)

        kernel32.GetFinalPathNameByHandleW.side_effect = final_path
        ops = Win32Ops.from_libraries(kernel32, ntdll)
        self.assertEqual(
            r"\\?\C:\repo\kanıt",
            ops.final_path(77),
        )
        self.assertEqual(2, len(kernel32.GetFinalPathNameByHandleW.calls))

    def test_write_requires_exact_positive_progress(self):
        kernel32 = FakeLibrary()
        ntdll = FakeLibrary()

        def short_write(handle, buffer, size, written, overlapped):
            output = ctypes.cast(written, ctypes.POINTER(ctypes.c_uint32))
            output.contents.value = size - 1
            return 1

        kernel32.WriteFile.side_effect = short_write
        ops = Win32Ops.from_libraries(kernel32, ntdll)
        with self.assertRaisesRegex(OSError, "invalid progress"):
            ops.write(77, b"payload")

    def test_collision_maps_to_immutable(self):
        ops = Win32Ops.from_libraries(FakeLibrary(), FakeLibrary())
        with self.assertRaisesRegex(EvidenceError, "E_IMMUTABLE"):
            ops._raise_ntstatus(
                STATUS_OBJECT_NAME_COLLISION, "already published"
            )

    def test_reparse_status_maps_to_symlink(self):
        ops = Win32Ops.from_libraries(FakeLibrary(), FakeLibrary())
        with self.assertRaisesRegex(EvidenceError, "E_SYMLINK"):
            ops._raise_ntstatus(
                STATUS_REPARSE_POINT_ENCOUNTERED, "directory unavailable"
            )

    def test_non_windows_production_load_fails_closed(self):
        if os.name == "nt":
            self.skipTest("portable fail-closed case")
        with self.assertRaisesRegex(EvidenceError, "E_PATH"):
            Win32Ops.load()
```

The test file imports `os`, `dataclass`, and `field` for this reusable fake.
`NativeFileInfo` comes from the production module. Later tasks extend this one
fake instead of introducing incompatible mock surfaces.

- [ ] **Step 2: Run the binding tests and verify failure**

Run:

```text
python -m unittest tests.kinglet_spike.test_win32_publish.Win32BindingTests -v
```

Expected: failures because `Win32Ops` and native signatures do not exist.

- [ ] **Step 3: Implement lazy native loading and exact signatures**

Implement `Win32Ops.from_libraries()` so it assigns `argtypes` and `restype`
for every function before returning. `load()` must:

```python
@classmethod
def load(cls) -> "Win32Ops":
    if os.name != "nt":
        raise EvidenceError("E_PATH", "native Windows publication is unavailable")
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    ntdll = ctypes.WinDLL("ntdll")
    return cls.from_libraries(kernel32, ntdll)
```

Define `NativeFileInfo` as a frozen dataclass with Boolean
`is_directory` and `is_reparse` fields. The native adapter methods and exact
return types are:

- `open_repository(path: Path) -> int`
- `open_directory(parent: int, component: str) -> int`
- `create_target(parent: int, component: str, immutable_message: str) -> int`
- `final_path(handle: int) -> str`
- `file_information(handle: int) -> NativeFileInfo`
- `write(handle: int, content: bytes) -> None`
- `flush(handle: int) -> None`
- `mark_delete(handle: int) -> None`
- `close(handle: int) -> None`

Add `import os`, then append this concrete adapter. The `FILETIME` and
`BY_HANDLE_FILE_INFORMATION` names are the Task 1 fixed-width structures:

```python
@dataclass(frozen=True)
class NativeFileInfo:
    is_directory: bool
    is_reparse: bool


def _extended_path(path: Path) -> str:
    text = os.path.abspath(str(path))
    if text.startswith("\\\\?\\"):
        return text
    if text.startswith("\\\\"):
        return "\\\\?\\UNC\\" + text[2:]
    return "\\\\?\\" + text


class Win32Ops:
    bound_function_names = (
        "CreateFileW",
        "GetFileInformationByHandle",
        "GetFinalPathNameByHandleW",
        "CompareStringOrdinal",
        "WriteFile",
        "FlushFileBuffers",
        "SetFileInformationByHandle",
        "CloseHandle",
        "NtCreateFile",
        "RtlNtStatusToDosError",
    )

    def __init__(self, kernel32, ntdll):
        self.kernel32 = kernel32
        self.ntdll = ntdll

    @classmethod
    def from_libraries(cls, kernel32, ntdll) -> "Win32Ops":
        kernel32.CreateFileW.argtypes = [
            ctypes.c_wchar_p, ULONG, ULONG, ctypes.c_void_p,
            ULONG, ULONG, HANDLE,
        ]
        kernel32.CreateFileW.restype = HANDLE
        kernel32.GetFileInformationByHandle.argtypes = [
            HANDLE, ctypes.POINTER(BY_HANDLE_FILE_INFORMATION),
        ]
        kernel32.GetFileInformationByHandle.restype = ctypes.c_int
        kernel32.GetFinalPathNameByHandleW.argtypes = [
            HANDLE, ctypes.POINTER(ctypes.c_wchar), ULONG, ULONG,
        ]
        kernel32.GetFinalPathNameByHandleW.restype = ULONG
        kernel32.CompareStringOrdinal.argtypes = [
            ctypes.c_wchar_p, ctypes.c_int, ctypes.c_wchar_p,
            ctypes.c_int, ctypes.c_int,
        ]
        kernel32.CompareStringOrdinal.restype = ctypes.c_int
        kernel32.WriteFile.argtypes = [
            HANDLE, ctypes.c_void_p, ULONG, ctypes.POINTER(ULONG),
            ctypes.c_void_p,
        ]
        kernel32.WriteFile.restype = ctypes.c_int
        kernel32.FlushFileBuffers.argtypes = [HANDLE]
        kernel32.FlushFileBuffers.restype = ctypes.c_int
        kernel32.SetFileInformationByHandle.argtypes = [
            HANDLE, ctypes.c_int, ctypes.c_void_p, ULONG,
        ]
        kernel32.SetFileInformationByHandle.restype = ctypes.c_int
        kernel32.CloseHandle.argtypes = [HANDLE]
        kernel32.CloseHandle.restype = ctypes.c_int
        ntdll.NtCreateFile.argtypes = [
            ctypes.POINTER(HANDLE), ULONG, ctypes.POINTER(OBJECT_ATTRIBUTES),
            ctypes.POINTER(IO_STATUS_BLOCK), ctypes.POINTER(ctypes.c_int64),
            ULONG, ULONG, ULONG, ULONG, ctypes.c_void_p, ULONG,
        ]
        ntdll.NtCreateFile.restype = NTSTATUS
        ntdll.RtlNtStatusToDosError.argtypes = [NTSTATUS]
        ntdll.RtlNtStatusToDosError.restype = ULONG
        return cls(kernel32, ntdll)

    @classmethod
    def load(cls) -> "Win32Ops":
        if os.name != "nt":
            raise EvidenceError(
                "E_PATH", "native Windows publication is unavailable"
            )
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        ntdll = ctypes.WinDLL("ntdll")
        return cls.from_libraries(kernel32, ntdll)

    @staticmethod
    def _handle_value(handle) -> int:
        value = handle if isinstance(handle, int) else handle.value
        if value is None or value == INVALID_HANDLE_VALUE:
            error = ctypes.get_last_error()
            raise OSError(error, f"native handle open failed with error {error}")
        return value

    def _raise_ntstatus(self, status: int, immutable_message: str) -> NoReturn:
        if status == STATUS_OBJECT_NAME_COLLISION:
            raise EvidenceError("E_IMMUTABLE", immutable_message)
        if status == STATUS_REPARSE_POINT_ENCOUNTERED:
            raise EvidenceError(
                "E_SYMLINK", "native path contains a reparse point"
            )
        error = int(self.ntdll.RtlNtStatusToDosError(status))
        raise OSError(error, f"NtCreateFile failed with error {error}")

    def _open_relative(
        self,
        parent: int,
        component: str,
        *,
        access: int,
        share: int,
        disposition: int,
        attributes: int,
        options: int,
        immutable_message: str,
    ) -> int:
        native_name = NativeName(component)
        object_attributes = OBJECT_ATTRIBUTES(
            Length=ctypes.sizeof(OBJECT_ATTRIBUTES),
            RootDirectory=HANDLE(parent),
            ObjectName=ctypes.pointer(native_name.value),
            Attributes=OBJ_CASE_INSENSITIVE | OBJ_DONT_REPARSE,
            SecurityDescriptor=None,
            SecurityQualityOfService=None,
        )
        result = HANDLE()
        status_block = IO_STATUS_BLOCK()
        status = int(
            self.ntdll.NtCreateFile(
                ctypes.byref(result),
                access,
                ctypes.byref(object_attributes),
                ctypes.byref(status_block),
                None,
                attributes,
                share,
                disposition,
                options,
                None,
                0,
            )
        )
        if status < 0:
            self._raise_ntstatus(status, immutable_message)
        return self._handle_value(result)

    def open_repository(self, path: Path) -> int:
        handle = self.kernel32.CreateFileW(
            _extended_path(path),
            DIRECTORY_ACCESS,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            None,
            OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
            None,
        )
        return self._handle_value(handle)

    def open_directory(self, parent: int, component: str) -> int:
        return self._open_relative(
            parent,
            component,
            access=DIRECTORY_ACCESS,
            share=FILE_SHARE_READ | FILE_SHARE_WRITE,
            disposition=FILE_OPEN_IF,
            attributes=FILE_ATTRIBUTE_DIRECTORY,
            options=FILE_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT,
            immutable_message=f"directory is unavailable: {component}",
        )

    def create_target(
        self, parent: int, component: str, immutable_message: str
    ) -> int:
        return self._open_relative(
            parent,
            component,
            access=TARGET_ACCESS,
            share=0,
            disposition=FILE_CREATE,
            attributes=FILE_ATTRIBUTE_NORMAL,
            options=FILE_NON_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT,
            immutable_message=immutable_message,
        )

    def file_information(self, handle: int) -> NativeFileInfo:
        value = BY_HANDLE_FILE_INFORMATION()
        if not self.kernel32.GetFileInformationByHandle(
            HANDLE(handle), ctypes.byref(value)
        ):
            error = ctypes.get_last_error()
            raise OSError(error, f"GetFileInformationByHandle failed: {error}")
        return NativeFileInfo(
            is_directory=bool(value.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY),
            is_reparse=bool(value.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT),
        )

    def final_path(self, handle: int) -> str:
        size = 260
        while True:
            buffer = ctypes.create_unicode_buffer(size)
            length = int(
                self.kernel32.GetFinalPathNameByHandleW(
                    HANDLE(handle), buffer, size, 0
                )
            )
            if length == 0:
                error = ctypes.get_last_error()
                raise OSError(error, f"GetFinalPathNameByHandleW failed: {error}")
            if length < size:
                return buffer.value
            size = length + 1

    def ordinal_equal(self, left: str, right: str) -> bool:
        result = int(
            self.kernel32.CompareStringOrdinal(left, -1, right, -1, 1)
        )
        if result == 0:
            error = ctypes.get_last_error()
            raise OSError(error, f"CompareStringOrdinal failed: {error}")
        return result == 2

    def write(self, handle: int, content: bytes) -> None:
        view = memoryview(content)
        while view:
            chunk = bytes(view[:0xFFFFFFFF])
            buffer = (ctypes.c_ubyte * len(chunk)).from_buffer_copy(chunk)
            written = ULONG()
            if not self.kernel32.WriteFile(
                HANDLE(handle), buffer, len(chunk), ctypes.byref(written), None
            ):
                error = ctypes.get_last_error()
                raise OSError(error, f"WriteFile failed: {error}")
            if written.value == 0 or written.value != len(chunk):
                raise OSError("WriteFile made invalid progress")
            view = view[written.value:]

    def flush(self, handle: int) -> None:
        if not self.kernel32.FlushFileBuffers(HANDLE(handle)):
            error = ctypes.get_last_error()
            raise OSError(error, f"FlushFileBuffers failed: {error}")

    def mark_delete(self, handle: int) -> None:
        disposition = FILE_DISPOSITION_INFO(DeleteFile=1)
        if not self.kernel32.SetFileInformationByHandle(
            HANDLE(handle),
            FILE_DISPOSITION_INFORMATION_CLASS,
            ctypes.byref(disposition),
            ctypes.sizeof(disposition),
        ):
            error = ctypes.get_last_error()
            raise OSError(error, f"SetFileInformationByHandle failed: {error}")

    def close(self, handle: int) -> None:
        if not self.kernel32.CloseHandle(HANDLE(handle)):
            error = ctypes.get_last_error()
            raise OSError(error, f"CloseHandle failed: {error}")
```

Rules:

- `CreateFileW` opens the repository with `DIRECTORY_ACCESS`,
  `FILE_SHARE_READ | FILE_SHARE_WRITE`, `OPEN_EXISTING`, and
  `FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT`;
- directory `NtCreateFile` calls use `DIRECTORY_ACCESS`,
  `FILE_SHARE_READ | FILE_SHARE_WRITE`, `FILE_OPEN_IF`,
  `FILE_ATTRIBUTE_DIRECTORY`, and
  `FILE_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT`;
- target `NtCreateFile` uses `TARGET_ACCESS`, share `0`, `FILE_CREATE`,
  `FILE_ATTRIBUTE_NORMAL`, and
  `FILE_NON_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT`;
- every native object uses `OBJ_CASE_INSENSITIVE | OBJ_DONT_REPARSE`;
- capture `ctypes.get_last_error()` immediately after a failed Win32 call;
- use the returned `NTSTATUS` directly for `NtCreateFile`;
- convert non-collision status with `RtlNtStatusToDosError`;
- use a resize loop for `GetFinalPathNameByHandleW`;
- keep `NativeName` alive until `NtCreateFile` returns;
- verify exact byte progress for `WriteFile`;
- pass `ctypes.sizeof(FILE_DISPOSITION_INFO) == 1`;
- never call a pathname delete.

- [ ] **Step 4: Run contract, binding, and harness tests**

Run:

```text
python -m unittest tests.kinglet_spike.test_win32_publish -v
python -m unittest discover -s tests/kinglet_spike -t . -v
```

Expected: all portable Win32 and harness tests pass.

- [ ] **Step 5: Commit the native adapter**

```text
git add tools/kinglet_spike/win32_publish.py tests/kinglet_spike/test_win32_publish.py
git commit -m "feat: bind native Windows publication APIs"
```

### Task 3: Hold a trusted handle-relative directory chain

**Files:**
- Modify: `tools/kinglet_spike/win32_publish.py`
- Modify: `tests/kinglet_spike/test_win32_publish.py`

**Interfaces:**
- Consumes: `Win32Ops`, a repository path, and validated destination components.
- Produces: `_DirectoryChain`, exact path assertions, and a held immediate-parent handle.

- [ ] **Step 1: Add failing ownership and substitution tests**

Use an in-memory fake whose handles identify immutable directory objects:

```python
from tools.kinglet_spike.win32_publish import (
    _normalize_final_path,
    _open_parent_chain,
)


class DirectoryChainTests(unittest.TestCase):
    def test_walks_one_component_at_a_time_and_holds_every_handle(self):
        ops = FakeWin32Ops()
        chain = _open_parent_chain(
            ops,
            Path(r"C:\repo"),
            ("docs", "research", "platform-spike", "artifacts", "runtime"),
        )
        self.assertEqual(
            ["repo", "docs", "research", "platform-spike", "artifacts", "runtime"],
            [ops.objects[handle].name for handle in chain.handles],
        )
        self.assertEqual([], ops.closed)
        self.assertEqual(
            [
                (chain.handles[index], name)
                for index, name in enumerate(
                    ("docs", "research", "platform-spike", "artifacts", "runtime")
                )
            ],
            ops.directory_calls,
        )
        original = list(chain.handles)
        chain.close()
        self.assertEqual(list(reversed(original)), ops.closed)

    def test_rejects_reparse_directory_before_child_creation(self):
        ops = FakeWin32Ops(reparse_component="research")
        with self.assertRaisesRegex(EvidenceError, "E_SYMLINK"):
            _open_parent_chain(
                ops, Path(r"C:\repo"), ("docs", "research", "platform-spike")
            )
        self.assertEqual([], ops.created_targets)

    def test_substituted_pathname_cannot_change_held_parent(self):
        ops = FakeWin32Ops()
        chain = _open_parent_chain(
            ops, Path(r"C:\repo"), ("docs", "research", "platform-spike")
        )
        held = chain.parent
        ops.replace_pathname(r"C:\repo\docs\research\platform-spike")
        self.assertEqual(held, chain.parent)
        self.assertNotEqual(held, ops.handle_for_path(r"C:\repo\docs\research\platform-spike"))

    def test_rejects_sibling_prefix_final_path(self):
        ops = FakeWin32Ops()
        real_final_path = ops.final_path

        def sibling_path(handle):
            if ops.objects[handle].name == "research":
                return r"C:\repo-other\docs\research"
            return real_final_path(handle)

        ops.final_path = sibling_path
        with self.assertRaisesRegex(EvidenceError, "E_PATH"):
            _open_parent_chain(
                ops, Path(r"C:\repo"), ("docs", "research", "platform-spike")
            )
        self.assertTrue(ops.all_handles_closed_once())

    def test_normalizes_extended_dos_and_unc_paths(self):
        self.assertEqual(
            r"C:\repo\docs",
            _normalize_final_path(r"\\?\C:\repo\.\docs"),
        )
        self.assertEqual(
            r"\\server\share\repo",
            _normalize_final_path(r"\\?\UNC\server\share\repo"),
        )
```

- [ ] **Step 2: Run the directory tests and verify failure**

Run:

```text
python -m unittest tests.kinglet_spike.test_win32_publish.DirectoryChainTests -v
```

Expected: failures because `_DirectoryChain` and `_open_parent_chain()` do not exist.

- [ ] **Step 3: Implement held ownership and exact path checks**

Implement a chain that owns every handle until transferred or closed:

```python
@dataclass
class _DirectoryChain:
    ops: Win32Ops
    handles: list[int]
    expected_paths: list[str]
    closed: bool = False

    @property
    def parent(self) -> int:
        return self.handles[-1]

    def close(self) -> None:
        errors = []
        while self.handles:
            handle = self.handles.pop()
            try:
                self.ops.close(handle)
            except OSError as error:
                errors.append(error)
        self.closed = True
        if errors:
            raise EvidenceError("E_PATH", "native directory handle close failed") from errors[0]
```

`_open_parent_chain()` must:

1. open the repository with `CreateFileW`;
2. reject a non-directory or reparse repository object;
3. validate each component again;
4. call `open_directory(previous_handle, component)` exactly once per component;
5. reject a non-directory or reparse child;
6. compare every handle's normalized final path with its exact expected path;
7. close every acquired handle in reverse order on failure;
8. keep all handles open on success.

Use component-aware, case-insensitive DOS/UNC normalization. A sibling prefix
such as `C:\repo-other` must not satisfy `C:\repo`.

Add `import ntpath`, then append this exact implementation:

```python
def _normalize_final_path(value: str) -> str:
    text = value.replace("/", "\\")
    if text.casefold().startswith("\\\\?\\unc\\"):
        text = "\\\\" + text[8:]
    elif text.casefold().startswith("\\\\?\\"):
        text = text[4:]
    return ntpath.normpath(text)


def _relative_components(ancestor: Path, descendant: Path) -> tuple[str, ...]:
    root = ntpath.normpath(str(ancestor))
    child = ntpath.normpath(str(descendant))
    try:
        common = ntpath.commonpath((root, child))
    except ValueError as error:
        raise EvidenceError(
            "E_PATH",
            f"destination escapes platform-spike evidence: {descendant}",
        ) from error
    if common.casefold() != root.casefold():
        raise EvidenceError(
            "E_PATH",
            f"destination escapes platform-spike evidence: {descendant}",
        )
    relative = ntpath.relpath(child, root)
    return () if relative == "." else tuple(relative.split("\\"))


def _same_final_path(ops: Win32Ops, left: str, right: str) -> bool:
    return ops.ordinal_equal(
        _normalize_final_path(left),
        _normalize_final_path(right),
    )


def _require_native_directory(
    ops: Win32Ops, handle: int, display: str
) -> None:
    information = ops.file_information(handle)
    if information.is_reparse:
        raise EvidenceError(
            "E_SYMLINK", f"path contains a reparse point: {display}"
        )
    if not information.is_directory:
        raise EvidenceError("E_PATH", f"path is not a directory: {display}")


def _open_parent_chain(
    ops: Win32Ops,
    repo_root: Path,
    components: tuple[str, ...],
) -> _DirectoryChain:
    handles: list[int] = []
    expected_paths: list[str] = []
    try:
        repository = ops.open_repository(repo_root)
        handles.append(repository)
        _require_native_directory(ops, repository, str(repo_root))
        expected = _normalize_final_path(ops.final_path(repository))
        expected_paths.append(expected)

        for component in components:
            validate_component(component, "destination component")
            child = ops.open_directory(handles[-1], component)
            handles.append(child)
            _require_native_directory(ops, child, component)
            expected = _normalize_final_path(ntpath.join(expected, component))
            if not _same_final_path(ops, ops.final_path(child), expected):
                raise EvidenceError(
                    "E_PATH",
                    f"native directory resolved unexpectedly: {component}",
                )
            expected_paths.append(expected)
        return _DirectoryChain(ops, handles, expected_paths)
    except BaseException:
        chain = _DirectoryChain(ops, handles, expected_paths)
        try:
            chain.close()
        except BaseException:
            pass
        raise
```

- [ ] **Step 4: Run focused and complete portable tests**

Run:

```text
python -m unittest tests.kinglet_spike.test_win32_publish.DirectoryChainTests -v
python -m unittest tests.kinglet_spike.test_win32_publish -v
```

Expected: all tests pass and the fake reports no leaked or double-closed handle.

- [ ] **Step 5: Commit the trusted chain**

```text
git add tools/kinglet_spike/win32_publish.py tests/kinglet_spike/test_win32_publish.py
git commit -m "feat: hold trusted Win32 publication paths"
```

### Task 4: Create, write, commit, and abort one native target

**Files:**
- Modify: `tools/kinglet_spike/win32_publish.py`
- Modify: `tests/kinglet_spike/test_win32_publish.py`

**Interfaces:**
- Consumes: held immediate-parent chain and one validated target name.
- Produces: `Win32CreatedTarget` and `create_exclusive_target()`.

- [ ] **Step 1: Add failing lifecycle and cleanup-order tests**

Add table-driven failure tests:

```python
class CreatedTargetTests(unittest.TestCase):
    def test_success_writes_flushes_and_never_marks_delete(self):
        ops = FakeWin32Ops()
        target = create_exclusive_target(
            Path(r"C:\repo"),
            Path(r"C:\repo\docs\research\platform-spike"),
            Path(r"C:\repo\docs\research\platform-spike\evidence\runtime\run.json"),
            "already published",
            ops=ops,
        )
        target.write(b"payload")
        target.flush()
        target.commit()
        self.assertEqual(b"payload", ops.target_bytes)
        self.assertEqual(1, ops.flush_count)
        self.assertEqual([], ops.delete_marks)
        self.assertTrue(ops.all_handles_closed_once())

    def test_successful_flush_is_retained_when_directory_close_fails(self):
        ops = FakeWin32Ops(fail_directory_close=True)
        target = create_exclusive_target(
            Path(r"C:\repo"),
            Path(r"C:\repo\docs\research\platform-spike"),
            Path(r"C:\repo\docs\research\platform-spike\evidence\run.json"),
            "already published",
            ops=ops,
        )
        target.write(b"payload")
        target.flush()
        with self.assertRaisesRegex(EvidenceError, "E_PATH"):
            target.commit()
        self.assertEqual(b"payload", ops.target_bytes)
        self.assertEqual([], ops.delete_marks)
        self.assertTrue(ops.attempted_every_close)

    def test_success_path_target_close_failure_is_uncertain(self):
        ops = FakeWin32Ops(fail_close=True)
        target = create_exclusive_target(
            Path(r"C:\repo"),
            Path(r"C:\repo\docs\research\platform-spike"),
            Path(r"C:\repo\docs\research\platform-spike\evidence\run.json"),
            "already published",
            ops=ops,
        )
        target.write(b"payload")
        target.flush()
        with self.assertRaisesRegex(
            EvidenceError, "E_IMMUTABLE.*uncertain"
        ):
            target.commit()
        self.assertEqual([], ops.delete_marks)
        self.assertTrue(ops.attempted_every_close)

    def test_every_post_create_failure_marks_delete_before_close(self):
        for operation in ("final_path", "write", "flush"):
            with self.subTest(operation=operation):
                ops = FakeWin32Ops(fail_at=operation)
                if operation == "final_path":
                    with self.assertRaisesRegex(Exception, operation):
                        create_exclusive_target(
                            Path(r"C:\repo"),
                            Path(r"C:\repo\docs\research\platform-spike"),
                            Path(r"C:\repo\docs\research\platform-spike\evidence\run.json"),
                            "already published",
                            ops=ops,
                        )
                else:
                    target = create_exclusive_target(
                        Path(r"C:\repo"),
                        Path(r"C:\repo\docs\research\platform-spike"),
                        Path(r"C:\repo\docs\research\platform-spike\evidence\run.json"),
                        "already published",
                        ops=ops,
                    )
                    try:
                        if operation == "write":
                            target.write(b"payload")
                        else:
                            target.flush()
                    except BaseException as primary:
                        with self.assertRaisesRegex(Exception, operation):
                            target.abort(primary)
                self.assertLess(ops.events.index("mark-delete"), ops.events.index("close-target"))
                self.assertFalse(ops.pathname_delete_called)

    def test_cleanup_failure_has_stable_immutable_precedence(self):
        ops = FakeWin32Ops(fail_at="write", fail_cleanup=True, fail_close=True)
        target = create_exclusive_target(
            Path(r"C:\repo"),
            Path(r"C:\repo\docs\research\platform-spike"),
            Path(r"C:\repo\docs\research\platform-spike\evidence\run.json"),
            "already published",
            ops=ops,
        )
        with self.assertRaisesRegex(EvidenceError, "E_IMMUTABLE.*uncertain"):
            try:
                target.write(b"payload")
            except BaseException as primary:
                target.abort(primary)
        self.assertTrue(ops.attempted_every_close)

    def test_collision_does_not_clean_up_nonexistent_target(self):
        ops = FakeWin32Ops(collision=True)
        with self.assertRaisesRegex(EvidenceError, "E_IMMUTABLE"):
            create_exclusive_target(
                Path(r"C:\repo"),
                Path(r"C:\repo\docs\research\platform-spike"),
                Path(r"C:\repo\docs\research\platform-spike\evidence\run.json"),
                "already published",
                ops=ops,
            )
        self.assertEqual([], ops.delete_marks)

    def test_rejects_destination_outside_committed_root_before_create(self):
        ops = FakeWin32Ops()
        with self.assertRaisesRegex(EvidenceError, "E_PATH"):
            create_exclusive_target(
                Path(r"C:\repo"),
                Path(r"C:\repo\docs\research\platform-spike"),
                Path(r"C:\repo-other\evidence\run.json"),
                "already published",
                ops=ops,
            )
        self.assertEqual([], ops.created_targets)
```

- [ ] **Step 2: Run lifecycle tests and verify failure**

Run:

```text
python -m unittest tests.kinglet_spike.test_win32_publish.CreatedTargetTests -v
```

Expected: failures because the lifecycle state machine is absent.

- [ ] **Step 3: Implement the target ownership state machine**

Use explicit states and at-most-once close:

```python
class Win32CreatedTarget:
    def __init__(
        self,
        ops: Win32Ops,
        chain: _DirectoryChain,
        handle: int,
        immutable_message: str,
    ):
        self._ops = ops
        self._chain = chain
        self._handle = handle
        self._immutable_message = immutable_message
        self._state = "open"

    def write(self, content: bytes) -> None:
        if self._state != "open":
            raise RuntimeError("target is not open")
        self._ops.write(self._handle, content)

    def flush(self) -> None:
        if self._state != "open":
            raise RuntimeError("target is not open")
        self._ops.flush(self._handle)

    def commit(self) -> None:
        if self._state != "open":
            raise RuntimeError("target is not open")
        target_error = None
        try:
            self._ops.close(self._handle)
        except BaseException as error:
            target_error = error
        finally:
            self._handle = None

        chain_error = None
        try:
            self._chain.close()
        except BaseException as error:
            chain_error = error

        if target_error is not None:
            self._state = "uncertain"
            raise EvidenceError(
                "E_IMMUTABLE",
                f"{self._immutable_message}; incomplete target state is uncertain",
            ) from target_error
        if chain_error is not None:
            self._state = "committed"
            raise chain_error
        self._state = "committed"

    def abort(self, primary: BaseException) -> NoReturn:
        if self._state != "open":
            raise RuntimeError("target is not open")
        cleanup_error = None
        close_error = None
        try:
            self._ops.mark_delete(self._handle)
        except BaseException as error:
            cleanup_error = error
        try:
            self._ops.close(self._handle)
        except BaseException as error:
            close_error = error
        finally:
            self._handle = None
        try:
            self._chain.close()
        except BaseException:
            pass

        if cleanup_error is not None or close_error is not None:
            self._state = "uncertain"
            cause = cleanup_error if cleanup_error is not None else close_error
            raise EvidenceError(
                "E_IMMUTABLE",
                f"{self._immutable_message}; incomplete target state is uncertain",
            ) from cause
        self._state = "aborted"
        raise primary


def create_exclusive_target(
    repo_root: Path,
    committed_root: Path,
    destination: Path,
    immutable_message: str,
    *,
    ops: Win32Ops | None = None,
) -> Win32CreatedTarget:
    native = Win32Ops.load() if ops is None else ops
    for label, value in (
        ("repository root", repo_root),
        ("committed root", committed_root),
        ("destination", destination),
    ):
        if not ntpath.isabs(str(value)):
            raise EvidenceError("E_PATH", f"{label} must be absolute")
    destination_text = ntpath.normpath(str(destination))
    destination_parent = Path(ntpath.dirname(destination_text))
    committed_components = _relative_components(repo_root, committed_root)
    parent_components = _relative_components(repo_root, destination_parent)
    _relative_components(committed_root, destination_parent)
    target_name = validate_component(
        ntpath.basename(destination_text), "destination name"
    )

    chain = _open_parent_chain(native, repo_root, parent_components)
    try:
        handle = native.create_target(
            chain.parent, target_name, immutable_message
        )
    except BaseException:
        try:
            chain.close()
        except BaseException:
            pass
        raise

    target = Win32CreatedTarget(
        native, chain, handle, immutable_message
    )
    try:
        target_information = native.file_information(handle)
        if target_information.is_directory or target_information.is_reparse:
            raise EvidenceError(
                "E_PATH", f"native target is not a regular file: {destination}"
            )

        committed_index = len(committed_components)
        committed_actual = native.final_path(chain.handles[committed_index])
        committed_expected = chain.expected_paths[committed_index]
        parent_actual = native.final_path(chain.parent)
        parent_expected = chain.expected_paths[-1]
        target_actual = native.final_path(handle)
        target_expected = _normalize_final_path(
            ntpath.join(parent_expected, target_name)
        )
        for actual, expected, label in (
            (committed_actual, committed_expected, "committed root"),
            (parent_actual, parent_expected, "destination parent"),
            (target_actual, target_expected, "destination target"),
        ):
            if not _same_final_path(native, actual, expected):
                raise EvidenceError(
                    "E_PATH", f"native {label} resolved unexpectedly"
                )
    except BaseException as primary:
        target.abort(primary)
    return target
```

This is the only post-create cleanup path. It never performs a pathname
delete, and it retains the chain through all final-path assertions.

- [ ] **Step 4: Run portable lifecycle and harness tests**

Run:

```text
python -m unittest tests.kinglet_spike.test_win32_publish.CreatedTargetTests -v
python -m unittest tests.kinglet_spike.test_win32_publish -v
python -m unittest discover -s tests/kinglet_spike -t . -v
```

Expected: lifecycle tests, all portable Win32 tests, and all harness tests pass.

- [ ] **Step 5: Commit the lifecycle**

```text
git add tools/kinglet_spike/win32_publish.py tests/kinglet_spike/test_win32_publish.py
git commit -m "feat: publish through owned Win32 handles"
```

### Task 5: Integrate the Windows writer without changing POSIX behavior

**Files:**
- Modify: `tools/kinglet_spike/publish.py`
- Modify: `tests/kinglet_spike/test_publish.py`
- Modify: `tests/kinglet_spike/test_win32_publish.py`

**Interfaces:**
- Consumes: `create_exclusive_target()` and the current publisher's safe logical destinations.
- Produces: one writer interface used by artifact copy and record publication on both platforms.

- [ ] **Step 1: Add failing dispatch and parity tests**

Extend the `test_publish.py` import to include `_open_target_writer`, then add
this reusable writer and the tests that force only the backend-selection seam:

```python
from tools.kinglet_spike.publish import (
    _copy_exclusive,
    _open_target_writer,
    publish_record,
)


class RecordingWriter:
    def __init__(self, fail_write=False):
        self.fail_write = fail_write
        self.content = bytearray()
        self.events = []
        self.abort_count = 0

    def write(self, content):
        self.events.append("write")
        if self.fail_write:
            raise OSError("injected writer failure")
        self.content.extend(content)

    def flush(self):
        self.events.append("flush")

    def commit(self):
        self.events.append("commit")

    def abort(self, primary):
        self.events.append("abort")
        self.abort_count += 1
        raise primary


class PublishBackendTests(unittest.TestCase):
    def test_windows_dispatch_is_lazy_and_receives_exact_roots(self):
        with mock.patch("tools.kinglet_spike.publish.os.name", "nt"):
            with mock.patch(
                "tools.kinglet_spike.win32_publish.create_exclusive_target"
            ) as create:
                writer = mock.Mock()
                create.return_value = writer
                result = _open_target_writer(
                    Path(r"C:\repo"),
                    Path(r"C:\repo\docs\research\platform-spike"),
                    Path(r"C:\repo\docs\research\platform-spike\evidence\run.json"),
                    "already published",
                )
        self.assertIs(writer, result)
        create.assert_called_once()

    def test_artifact_and_record_use_writer_lifecycle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = PublishTests()._raw_record(root)
            artifact_writer = RecordingWriter()
            record_writer = RecordingWriter()
            with mock.patch(
                "tools.kinglet_spike.publish._open_target_writer",
                side_effect=(artifact_writer, record_writer),
            ):
                publish_record(raw, root)
        self.assertEqual(["write", "flush", "commit"], artifact_writer.events)
        self.assertEqual(["write", "flush", "commit"], record_writer.events)
        self.assertEqual(b'{"ok":true}\n', bytes(artifact_writer.content))
        self.assertTrue(bytes(record_writer.content).endswith(b"\n"))

    def test_write_and_checksum_failures_abort_once(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.json"
            source.write_bytes(b'{"ok":true}\n')
            destination = Path(directory) / "target.json"
            cases = (
                (RecordingWriter(fail_write=True), "0" * 64, "writer failure"),
                (
                    RecordingWriter(),
                    "0" * 64,
                    "E_CHECKSUM",
                ),
            )
            for writer, expected, message in cases:
                with self.subTest(message=message):
                    with mock.patch(
                        "tools.kinglet_spike.publish._open_target_writer",
                        return_value=writer,
                    ):
                        with self.assertRaisesRegex(Exception, message):
                            _copy_exclusive(source, destination, expected)
                    self.assertEqual(1, writer.abort_count)
                    self.assertNotIn("commit", writer.events)
```

Keep the existing
`test_copy_keeps_creation_in_verified_parent_after_parent_replacement`
unchanged; it is the POSIX parity regression and runs beside this new dispatch
test.

- [ ] **Step 2: Run focused tests and verify missing writer seam**

Run:

```text
python -m unittest tests.kinglet_spike.test_publish.PublishBackendTests -v
```

Expected: failure because `_open_target_writer()` does not exist.

- [ ] **Step 3: Introduce one platform-neutral writer boundary**

Add `Callable`, `NoReturn`, and `Protocol` to the `typing` imports. Delete
`_windows_final_path()`, `_windows_is_relative_to()`,
`_windows_mark_delete()`, and `_open_windows_exclusive()`. Replace
`_open_exclusive_target()` with this POSIX-only function and writer boundary:

```python
class _TargetWriter(Protocol):
    write: Callable[[bytes], None]
    flush: Callable[[], None]
    commit: Callable[[], None]
    abort: Callable[[BaseException], NoReturn]


def _open_posix_exclusive_target(
    repo_root: Path,
    committed_root: Path,
    destination: Path,
    immutable_message: str,
) -> _CreatedTarget:
    if not _directory_fd_supported():
        raise EvidenceError(
            "E_PATH",
            "safe descriptor-relative publication is unavailable on this platform",
        )
    parent_descriptor = _open_verified_parent(
        repo_root, committed_root, destination
    )
    flags = (
        os.O_WRONLY
        | os.O_CREAT
        | os.O_EXCL
        | getattr(os, "O_BINARY", 0)
        | getattr(os, "O_NOFOLLOW", 0)
    )
    try:
        descriptor = os.open(
            destination.name, flags, 0o644, dir_fd=parent_descriptor
        )
    except FileExistsError as error:
        os.close(parent_descriptor)
        raise EvidenceError("E_IMMUTABLE", immutable_message) from error
    except OSError as error:
        os.close(parent_descriptor)
        if error.errno == errno.ELOOP:
            _raise_symlink(destination)
        raise EvidenceError(
            "E_PATH", f"destination is unavailable: {destination}"
        ) from error
    return _CreatedTarget(
        descriptor=descriptor,
        destination=destination,
        identity=_identity(os.fstat(descriptor)),
        parent_descriptor=parent_descriptor,
        name=destination.name,
    )


class _PosixTargetWriter:
    def __init__(self, created: _CreatedTarget):
        self._created = created
        self._state = "open"

    def write(self, content: bytes) -> None:
        if self._state != "open":
            raise RuntimeError("target is not open")
        _write_all(self._created.descriptor, content)

    def flush(self) -> None:
        if self._state != "open":
            raise RuntimeError("target is not open")
        os.fsync(self._created.descriptor)

    def commit(self) -> None:
        if self._state != "open":
            raise RuntimeError("target is not open")
        try:
            _close_created(self._created)
        finally:
            self._state = "committed"

    def abort(self, primary: BaseException) -> NoReturn:
        if self._state != "open":
            raise RuntimeError("target is not open")
        try:
            _cleanup_created(self._created)
        finally:
            try:
                _close_created(self._created)
            finally:
                self._state = "aborted"
        raise primary


def _open_posix_target_writer(
    repo_root: Path,
    committed_root: Path,
    destination: Path,
    immutable_message: str,
) -> _TargetWriter:
    return _PosixTargetWriter(
        _open_posix_exclusive_target(
            repo_root, committed_root, destination, immutable_message
        )
    )


def _open_target_writer(
    repo_root: Path,
    committed_root: Path,
    destination: Path,
    immutable_message: str,
) -> _TargetWriter:
    if os.name == "nt":
        from tools.kinglet_spike.win32_publish import create_exclusive_target

        return create_exclusive_target(
            repo_root, committed_root, destination, immutable_message
        )
    return _open_posix_target_writer(
        repo_root, committed_root, destination, immutable_message
    )
```

Replace `_copy_exclusive()` and `_write_record_exclusive()` with the following.
The source descriptor is closed before commit; on failure its close cannot
mask the target cleanup result:

```python
def _copy_exclusive(
    source: Path,
    destination: Path,
    expected_sha256: str,
    *,
    repo_root: Path | None = None,
    committed_root: Path | None = None,
) -> None:
    if (repo_root is None) != (committed_root is None):
        raise ValueError("repo_root and committed_root must be supplied together")
    source_descriptor = _open_regular_source(source)
    writer = None
    try:
        actual_repo = destination.parent if repo_root is None else repo_root
        actual_committed = (
            destination.parent if committed_root is None else committed_root
        )
        writer = _open_target_writer(
            actual_repo,
            actual_committed,
            destination,
            f"artifact already published: {destination}",
        )
        digest = hashlib.sha256()
        while True:
            block = os.read(source_descriptor, 65536)
            if not block:
                break
            digest.update(block)
            writer.write(block)
        if digest.hexdigest() != expected_sha256:
            raise EvidenceError(
                "E_CHECKSUM",
                f"published artifact checksum changed: {source}",
            )
        writer.flush()
    except BaseException as primary:
        descriptor = source_descriptor
        source_descriptor = None
        try:
            os.close(descriptor)
        except BaseException:
            pass
        if writer is None:
            raise
        writer.abort(primary)

    descriptor = source_descriptor
    source_descriptor = None
    try:
        os.close(descriptor)
    except BaseException as primary:
        writer.abort(primary)
    writer.commit()


def _write_record_exclusive(
    target: Path,
    payload: bytes,
    run_id: str,
    repo_root: Path,
    committed_root: Path,
) -> None:
    writer = _open_target_writer(
        repo_root,
        committed_root,
        target,
        f"run already published: {run_id}",
    )
    try:
        writer.write(payload)
        writer.flush()
    except BaseException as primary:
        writer.abort(primary)
    writer.commit()
```

- [ ] **Step 4: Run focused, harness, and Linux aggregate verification**

Run on Linux:

```text
python -m unittest tests.kinglet_spike.test_publish tests.kinglet_spike.test_win32_publish -v
python -m unittest discover -s tests/kinglet_spike -t . -v
bash tests/run-tests.sh
git diff --check
```

Expected:

- publication and Win32 portable tests pass;
- all harness tests pass;
- aggregate result reports `Failed: 0`;
- `git diff --check` emits no output.

- [ ] **Step 5: Commit the integration**

```text
git add tools/kinglet_spike/publish.py tools/kinglet_spike/win32_publish.py tests/kinglet_spike/test_publish.py tests/kinglet_spike/test_win32_publish.py
git commit -m "feat: integrate native Windows publication"
```

### Task 6: Prove the backend on native Windows 10 NTFS

**Files:**
- Create: `tests/kinglet_spike/test_win32_publish_native.py`
- Create: `tests/run-win32-publication.ps1`
- Modify: `docs/superpowers/runbooks/2026-07-23-win32-publication-handoff.md`

**Interfaces:**
- Consumes: the real Windows backend and existing `publish_record()`.
- Produces: a native PowerShell gate with recorded Windows 10 evidence and no Bash dependency.

- [ ] **Step 1: Add native-only acceptance tests**

Use this concrete module; its import guard makes the whole module skip on
non-Windows hosts:

```python
import ctypes
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

if os.name != "nt":
    raise unittest.SkipTest("native Win32 publication tests require Windows")

from tools.kinglet_spike.model import EvidenceError
from tools.kinglet_spike.publish import _copy_exclusive, publish_record
from tools.kinglet_spike.win32_publish import (
    NativeFileInfo,
    Win32Ops,
    _open_parent_chain,
    create_exclusive_target,
)
from tests.kinglet_spike.support import valid_record, write_record


def _raw_record(root: Path) -> Path:
    raw = root / ".kinglet/local/spikes/run-01"
    artifact = (
        raw / "publish/artifacts/runtime/python"
        / "20260723T120000Z-runtime-python-windows11-x64-01/result.json"
    )
    artifact.parent.mkdir(parents=True)
    artifact.write_bytes(b'{"ok":true}\n')
    return write_record(raw, valid_record())


def _filesystem_name(path: Path) -> str:
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    function = kernel32.GetVolumeInformationW
    function.argtypes = [
        ctypes.c_wchar_p, ctypes.c_wchar_p, ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_uint32),
        ctypes.POINTER(ctypes.c_uint32), ctypes.c_wchar_p, ctypes.c_uint32,
    ]
    function.restype = ctypes.c_int
    name = ctypes.create_unicode_buffer(32)
    root = Path(path.anchor)
    if not function(str(root), None, 0, None, None, None, name, len(name)):
        raise ctypes.WinError(ctypes.get_last_error())
    return name.value


def _process_handle_count() -> int:
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    current = kernel32.GetCurrentProcess
    current.restype = ctypes.c_void_p
    count = ctypes.c_uint32()
    function = kernel32.GetProcessHandleCount
    function.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
    function.restype = ctypes.c_int
    if not function(current(), ctypes.byref(count)):
        raise ctypes.WinError(ctypes.get_last_error())
    return count.value


def _make_junction(link: Path, target: Path) -> None:
    subprocess.run(
        ["cmd.exe", "/d", "/c", "mklink", "/J", str(link), str(target)],
        check=True,
        capture_output=True,
        text=True,
    )


class FaultOps:
    def __init__(
        self,
        delegate,
        fail_at,
        cleanup_failure=False,
        close_failure=False,
    ):
        self.delegate = delegate
        self.fail_at = fail_at
        self.cleanup_failure = cleanup_failure
        self.close_failure = close_failure
        self.target_handle = None

    def __getattr__(self, name):
        return getattr(self.delegate, name)

    def create_target(self, parent, component, immutable_message):
        self.target_handle = self.delegate.create_target(
            parent, component, immutable_message
        )
        return self.target_handle

    def final_path(self, handle):
        if self.fail_at == "final_path" and handle == self.target_handle:
            raise OSError("injected final-path failure")
        return self.delegate.final_path(handle)

    def file_information(self, handle):
        if self.fail_at == "validation" and handle == self.target_handle:
            return NativeFileInfo(is_directory=True, is_reparse=False)
        return self.delegate.file_information(handle)

    def write(self, handle, content):
        if self.fail_at == "write" and handle == self.target_handle:
            raise OSError("injected write failure")
        return self.delegate.write(handle, content)

    def flush(self, handle):
        if self.fail_at == "flush" and handle == self.target_handle:
            raise OSError("injected flush failure")
        return self.delegate.flush(handle)

    def mark_delete(self, handle):
        if self.cleanup_failure and handle == self.target_handle:
            raise OSError("injected cleanup failure")
        return self.delegate.mark_delete(handle)

    def close(self, handle):
        result = self.delegate.close(handle)
        if self.close_failure and handle == self.target_handle:
            raise OSError("injected close failure")
        return result


class NativeWin32PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kinglet-win32-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.assertEqual("NTFS", _filesystem_name(self.root).upper())

    def _destination(self, name):
        return (
            self.root / "docs/research/platform-spike/evidence/runtime"
            / f"{name}.json"
        )

    def _create_target(self, name, ops=None):
        destination = self._destination(name)
        target = create_exclusive_target(
            self.root,
            self.root / "docs/research/platform-spike",
            destination,
            f"already published: {name}",
            ops=ops,
        )
        return destination, target

    def test_first_publish_and_immutable_retry(self):
        committed = self.root / "docs/research/platform-spike"
        self.assertFalse(committed.exists())
        raw = _raw_record(self.root)
        target = publish_record(raw, self.root)
        original = target.read_bytes()
        artifact = (
            committed / "artifacts/runtime/python"
            / "20260723T120000Z-runtime-python-windows11-x64-01/result.json"
        )
        self.assertEqual(b'{"ok":true}\n', artifact.read_bytes())
        with self.assertRaisesRegex(EvidenceError, "E_IMMUTABLE"):
            publish_record(raw, self.root)
        self.assertEqual(original, target.read_bytes())

    def test_unicode_and_long_path_publish(self):
        long_root = self.root / "kanıt"
        for index in range(18):
            long_root /= f"segment-{index:02d}-abcdefgh"
        long_root.mkdir(parents=True)
        raw = _raw_record(long_root)
        target = publish_record(raw, long_root)
        self.assertGreater(len(str(target)), 260)
        self.assertTrue(target.is_file())

    def test_rejects_junction_in_destination_chain(self):
        components = ("docs", "research", "platform-spike", "artifacts", "runtime")
        for index, component in enumerate(components):
            with self.subTest(component=component):
                with tempfile.TemporaryDirectory(
                    prefix="kinglet-junction-", dir=self.root
                ) as directory:
                    root = Path(directory)
                    outside = root / "outside"
                    outside.mkdir()
                    parent = root.joinpath(*components[:index])
                    parent.mkdir(parents=True, exist_ok=True)
                    junction = parent / component
                    _make_junction(junction, outside)
                    try:
                        raw = _raw_record(root)
                        with self.assertRaisesRegex(
                            EvidenceError, "E_SYMLINK"
                        ):
                            publish_record(raw, root)
                        self.assertEqual((), tuple(outside.iterdir()))
                    finally:
                        if junction.exists():
                            junction.rmdir()

    def test_rejects_repository_anchor_junction(self):
        outside = self.root / "repository-target"
        outside.mkdir()
        junction = self.root / "repository-junction"
        _make_junction(junction, outside)
        try:
            raw = _raw_record(junction)
            with self.assertRaisesRegex(EvidenceError, "E_SYMLINK"):
                publish_record(raw, junction)
            self.assertFalse((outside / "docs").exists())
        finally:
            if junction.exists():
                junction.rmdir()

    def test_rejects_directory_symlink_when_available(self):
        platform = self.root / "docs/research/platform-spike"
        outside = self.root / "symlink-target"
        platform.mkdir(parents=True)
        outside.mkdir()
        link = platform / "artifacts"
        try:
            link.symlink_to(outside, target_is_directory=True)
        except OSError as error:
            self.skipTest(f"directory symlink privilege unavailable: {error}")
        raw = _raw_record(self.root)
        with self.assertRaisesRegex(EvidenceError, "E_SYMLINK"):
            publish_record(raw, self.root)
        self.assertEqual((), tuple(outside.iterdir()))

    def test_held_parent_denies_rename_until_close(self):
        platform = self.root / "docs/research/platform-spike"
        platform.mkdir(parents=True)
        moved = platform.with_name("platform-spike-moved")
        chain = _open_parent_chain(
            Win32Ops.load(),
            self.root,
            ("docs", "research", "platform-spike"),
        )
        try:
            with self.assertRaises(OSError):
                platform.rename(moved)
        finally:
            chain.close()
        platform.rename(moved)
        moved.rename(platform)

    def test_native_failures_delete_created_target(self):
        for failure in ("final_path", "validation", "write", "flush"):
            with self.subTest(failure=failure):
                name = f"failure-{failure}"
                ops = FaultOps(Win32Ops.load(), failure)
                destination = self._destination(name)
                if failure in {"final_path", "validation"}:
                    message = "final-path" if failure == "final_path" else "E_PATH"
                    with self.assertRaisesRegex(Exception, message):
                        self._create_target(name, ops)
                else:
                    destination, target = self._create_target(name, ops)
                    try:
                        target.write(b"payload")
                        target.flush()
                    except BaseException as primary:
                        with self.assertRaisesRegex(OSError, failure):
                            target.abort(primary)
                self.assertFalse(destination.exists())

    def test_checksum_failure_deletes_created_target(self):
        source = self.root / "source.json"
        source.write_bytes(b'{"ok":true}\n')
        destination = self._destination("checksum")
        with self.assertRaisesRegex(EvidenceError, "E_CHECKSUM"):
            _copy_exclusive(
                source,
                destination,
                "0" * 64,
                repo_root=self.root,
                committed_root=self.root / "docs/research/platform-spike",
            )
        self.assertFalse(destination.exists())

    def test_target_is_exclusive_until_successful_close(self):
        destination, target = self._create_target("exclusive")
        target.write(b"payload")
        for operation in ("read", "write", "delete"):
            with self.subTest(operation=operation):
                with self.assertRaises(OSError):
                    if operation == "read":
                        with destination.open("rb"):
                            pass
                    elif operation == "write":
                        with destination.open("r+b"):
                            pass
                    else:
                        destination.unlink()
        target.flush()
        target.commit()
        self.assertEqual(b"payload", destination.read_bytes())
        destination.unlink()

    def test_cleanup_failure_has_stable_immutable_diagnostic(self):
        ops = FaultOps(Win32Ops.load(), "write", cleanup_failure=True)
        destination, target = self._create_target("cleanup-failure", ops)
        try:
            target.write(b"payload")
        except BaseException as primary:
            with self.assertRaisesRegex(
                EvidenceError, "E_IMMUTABLE.*uncertain"
            ):
                target.abort(primary)
        self.assertTrue(destination.exists())

    def test_close_failure_has_stable_immutable_diagnostic(self):
        ops = FaultOps(
            Win32Ops.load(), "write", close_failure=True
        )
        destination, target = self._create_target("close-failure", ops)
        try:
            target.write(b"payload")
        except BaseException as primary:
            with self.assertRaisesRegex(
                EvidenceError, "E_IMMUTABLE.*uncertain"
            ):
                target.abort(primary)
        self.assertFalse(destination.exists())

    def test_success_path_close_failure_is_uncertain_but_retains_file(self):
        ops = FaultOps(
            Win32Ops.load(), None, close_failure=True
        )
        destination, target = self._create_target("commit-close-failure", ops)
        target.write(b"payload")
        target.flush()
        with self.assertRaisesRegex(
            EvidenceError, "E_IMMUTABLE.*uncertain"
        ):
            target.commit()
        self.assertEqual(b"payload", destination.read_bytes())

    def test_repeated_abort_has_no_handle_leak(self):
        before = _process_handle_count()
        for index in range(100):
            destination, target = self._create_target(f"leak-{index:03d}")
            with self.assertRaisesRegex(RuntimeError, "injected abort"):
                target.abort(RuntimeError("injected abort"))
            self.assertFalse(destination.exists())
        after = _process_handle_count()
        self.assertLessEqual(after, before + 2)
```

The controlled rename test exercises the real no-delete-sharing behavior.
Portable fake tests remain responsible for exact call ordering; the native
tests prove the handles and flags work on Windows 10.

- [ ] **Step 2: Add the native PowerShell wrapper**

Create `tests/run-win32-publication.ps1`:

```powershell
param(
    [switch]$RequireClean
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($env:OS -ne "Windows_NT") {
    throw "Native Windows is required"
}
if ($env:WSL_DISTRO_NAME) {
    throw "WSL is not allowed for Win32 publication acceptance"
}

$Repo = Split-Path -Parent $PSScriptRoot
Set-Location $Repo

$Python = (Get-Command python -ErrorAction Stop).Source
function Invoke-Python {
    param([string[]]$Arguments)
    & $Python @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed with exit code $LASTEXITCODE"
    }
}

Invoke-Python -Arguments @("-c", "import os, platform; assert os.name == 'nt'; assert platform.machine().lower() in ('amd64', 'x86_64')")
Invoke-Python -Arguments @("-m", "unittest", "tests.kinglet_spike.test_win32_publish", "-v")
Invoke-Python -Arguments @("-m", "unittest", "tests.kinglet_spike.test_win32_publish_native", "-v")
Invoke-Python -Arguments @("-m", "unittest", "discover", "-s", "tests/kinglet_spike", "-t", ".", "-v")
Invoke-Python -Arguments @("-m", "unittest", "discover", "-s", "tests/kinglet", "-p", "test_*.py", "-v")

& git diff --check
if ($LASTEXITCODE -ne 0) {
    throw "git diff --check failed with exit code $LASTEXITCODE"
}
if ($RequireClean -and (git status --porcelain)) {
    throw "Native test run left the worktree dirty"
}

Write-Host "PASS: native Windows 10 Win32 publication acceptance"
```

- [ ] **Step 3: Run the portable test and confirm native tests skip on Linux**

Run on Linux:

```text
python -m unittest tests.kinglet_spike.test_win32_publish_native -v
```

Expected: the module is skipped with the exact native-Windows message.

- [ ] **Step 4: Run the native Windows 10 gate**

Run from PowerShell, not WSL or Git Bash:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\tests\run-win32-publication.ps1
```

Expected:

- portable Win32 tests pass;
- native NTFS tests pass;
- every spike-harness Python test passes;
- all existing `tests/kinglet` Python tests pass;
- the wrapper prints the final PASS line.

Save the console transcript outside the repository first. Add only a
sanitized, path-free summary to the Task 3 implementer report and commit
message; do not commit account names, absolute paths, or raw console
environment data.

- [ ] **Step 5: Commit the native acceptance gate**

```text
git add tests/kinglet_spike/test_win32_publish_native.py tests/run-win32-publication.ps1
git commit -m "test: prove native Windows evidence publication"
```

- [ ] **Step 6: Re-run the committed native gate with cleanliness enforced**

Run:

```powershell
.\tests\run-win32-publication.ps1 -RequireClean
```

Expected: all native and Python tests pass, `git status --porcelain` is empty,
and the wrapper prints its final PASS line.

- [ ] **Step 7: Push the reviewed native branch without rewriting history**

Run:

```powershell
git push origin codex/00a-win32-publication
```

Expected: a normal fast-forward push succeeds. Do not force-push.

- [ ] **Step 8: Run final Linux regression after the Windows commit is pushed**

Run on Linux:

```text
git fetch origin
git switch codex/00a-win32-publication
git pull --ff-only origin codex/00a-win32-publication
python -m unittest discover -s tests/kinglet_spike -t . -v
bash tests/run-tests.sh
git diff --check
```

Expected: native-only tests skip; every portable test passes; aggregate
reports `Failed: 0`; diff check is clean.

## Plan Acceptance

Before Task 3 can close:

- all six task commits have an implementer report with real RED and GREEN evidence;
- each task has an independent spec-and-quality approval;
- the final whole-Task-3 reviewer approves the complete range from `96abd6a`;
- native Windows 10 PowerShell acceptance passes on local NTFS;
- no native test uses WSL or Git Bash;
- Linux full aggregate reports zero failures after the Windows branch is pushed;
- no path, account identifier, credential, or raw environment transcript is committed;
- `git grep -nE '(/Users/|/home/|[A-Z]:\\\\Users\\\\|gh[pousr]_|sk-)' docs/research/platform-spike docs/superpowers/runbooks`
  finds no sensitive match;
- the child branch is merged only into `codex/00a-evidence-harness`, not `main`;
- Windows 11 native validation remains explicitly open for final 00A.
