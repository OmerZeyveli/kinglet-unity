# Kinglet Win32 Evidence Publication Design

**Date:** 2026-07-23  
**Status:** Approved design; implementation requires native Windows 10 validation  
**Parent:** `2026-07-23-kinglet-platform-spikes-design.md`  
**Extends:** 00A Task 3 in `2026-07-23-kinglet-00a-evidence-harness.md`

## Purpose

Kinglet's 00A harness must publish sanitized evidence immutably on Windows
without allowing path traversal, reparse-point escape, parent replacement, or
cleanup of a file it did not create. The public Python interface remains:

```python
def publish_record(raw_path: Path, repo_root: Path) -> Path: ...
```

This design replaces the incomplete Windows fallback behind that interface.
The accepted POSIX held-directory-descriptor path remains unchanged.

## Constraints

- Python standard library only; native calls use `ctypes`.
- Windows execution is native PowerShell execution, not WSL or Git Bash.
- Windows 10 x64 is the first native acceptance host.
- Windows 11 x64 remains a final 00A platform-validation target.
- No import from `tools/kinglet_build` or a product-runtime candidate.
- A target is created exactly once and an existing target is never replaced.
- No committed record or artifact may escape
  `docs/research/platform-spike/`.
- Reparse points, unsafe names, alternate data streams, and raw absolute paths
  are rejected.
- Cleanup may act only on the exact handle created by this invocation.
- The evidence-v1 diagnostic-code list remains unchanged.
- Existing partial-history semantics remain: a later failure does not remove
  an earlier successfully published immutable artifact.

## Approaches Considered

### 1. Held Win32 anchor plus handle-relative native creation

Open the repository trust anchor with `CreateFileW`, walk or create descendants
relative to held directory handles with `NtCreateFile`, and create the target
relative to its held parent. This prevents a pathname substitution from
redirecting the create operation.

This is the selected approach.

### 2. Absolute `CreateFileW(CREATE_NEW)` plus final-path verification

This is simpler, but target creation still resolves a mutable absolute
pathname. A held root handle and a later path query do not make that separate
resolution atomic. This approach is insufficient for the accepted
parent-replacement requirement.

### 3. Static checks or Windows fail-closed

Static `lstat` or resolved-path checks retain a time-of-check/time-of-use
window. Rejecting all Windows publication is safe but conflicts with native
Windows support. There is no silent fallback to either behavior.

## Component Boundaries

### `tools/kinglet_spike/publish.py`

This module remains the platform-neutral orchestrator and retains the accepted
POSIX implementation. It owns:

- record loading and validation;
- safe logical destination construction;
- publication ordering;
- checksum comparison;
- immutable partial-history policy;
- selection of the POSIX or Windows target backend.

It must not contain Win32 ABI structures or native constants.

### `tools/kinglet_spike/win32_publish.py`

This module is loaded only when the Windows backend is selected. It owns:

- fixed-width `ctypes` ABI definitions;
- DLL loading and exact function signatures;
- repository trust-anchor opening;
- handle-relative directory walking and creation;
- handle-relative exclusive target creation;
- final-handle-path assertions;
- native writes and flushes;
- exact-handle failure cleanup;
- deterministic native error conversion and handle ownership.

It exposes a small internal boundary to `publish.py` rather than exposing raw
handles:

```python
class Win32CreatedTarget:
    def write(self, content: bytes) -> None: ...
    def flush(self) -> None: ...
    def commit(self) -> None: ...
    def abort(self, primary: BaseException) -> NoReturn: ...


def create_exclusive_target(
    repo_root: Path,
    committed_root: Path,
    destination: Path,
    immutable_message: str,
) -> Win32CreatedTarget: ...
```

The exact Python shape may use functions instead of methods if tests show a
clearer ownership boundary, but raw native handles may not escape this module.

## Path and Name Contract

Existing portable path checks remain in force. Before calling a Windows API,
every dynamic component also rejects:

- `/`, `\`, NUL, and `:`;
- ASCII control characters;
- trailing spaces or dots;
- `.` and `..`;
- Windows reserved device basenames, including names with an extension;
- components exceeding the existing UTF-8 boundary;
- absolute, drive-relative, UNC, and alternate-data-stream syntax.

Only UTF-16 `W` APIs are used. The repository's absolute trust-anchor path is
converted to an extended-length DOS or UNC form. Relative native operations
receive one already-validated component at a time.

Microsoft's naming and long-path rules are the authority:

- https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file
- https://learn.microsoft.com/en-us/windows/win32/fileio/file-streams
- https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation

## Native Handle Flow

### 1. Open the repository trust anchor

Open the repository directory with `CreateFileW` using:

- `OPEN_EXISTING`;
- `FILE_FLAG_BACKUP_SEMANTICS`;
- `FILE_FLAG_OPEN_REPARSE_POINT`;
- directory-readable/traversable access;
- read/write sharing but no delete sharing.

Verify with `GetFileInformationByHandle` that the opened object is a directory
and not a reparse point. Keep this handle open until the target and all
descendant handles are closed.

References:

- https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew
- https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfileinformationbyhandle

### 2. Walk and create trusted directories

Walk `docs/research/platform-spike` and the target's remaining parent
components with `NtCreateFile`:

- `RootDirectory` is the held parent handle;
- the object name is one validated `UNICODE_STRING` component;
- attributes include `OBJ_CASE_INSENSITIVE | OBJ_DONT_REPARSE`;
- disposition is `FILE_OPEN_IF`;
- options include
  `FILE_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT`;
- sharing allows read and write but omits delete.

Each returned handle is verified as a non-reparse directory and remains open
while its child is created. An unsupported status fails closed.

References:

- https://learn.microsoft.com/en-us/windows/win32/api/winternl/nf-winternl-ntcreatefile
- https://learn.microsoft.com/en-us/windows/win32/api/ntdef/ns-ntdef-_object_attributes

### 3. Create the immutable target

Create the final target relative to the held immediate-parent handle with one
`NtCreateFile` call:

- access includes file write, read attributes, synchronization, and `DELETE`;
- sharing is `0`;
- disposition is `FILE_CREATE`;
- options include
  `FILE_NON_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT`;
- object attributes include `OBJ_CASE_INSENSITIVE | OBJ_DONT_REPARSE`.

`STATUS_OBJECT_NAME_COLLISION` maps to `E_IMMUTABLE`. Other native failures
are converted with `RtlNtStatusToDosError`; `GetLastError` is not used for an
`NtCreateFile` result.

Reference:

- https://learn.microsoft.com/en-us/windows/win32/api/winternl/nf-winternl-rtlntstatustodoserror

### 4. Verify before writing

Query the repository, committed-root, immediate-parent, and target handles
with `GetFinalPathNameByHandleW` using normalized DOS-volume names.

Normalize extended DOS and UNC prefixes, separators, and dot components.
Verify:

- committed root is the exact expected descendant of the repository;
- immediate parent is the exact expected descendant of the committed root;
- target is the exact expected relative destination;
- comparisons are component-boundary-aware and case-insensitive.

Use ordinal rather than locale-sensitive comparison. These checks are
defense-in-depth assertions; handle-relative creation is the race-prevention
mechanism.

References:

- https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfinalpathnamebyhandlew
- https://learn.microsoft.com/en-us/windows/win32/api/stringapiset/nf-stringapiset-comparestringordinal

### 5. Write, flush, and retain

Write with synchronous `WriteFile` loops. Every successful call must report
positive progress and the exact number of bytes accepted. Call
`FlushFileBuffers` before success.

On success:

1. close the target without a delete disposition;
2. close every directory handle;
3. return only if all required success-path operations completed.

The Windows backend does not convert the native handle to a CRT descriptor.

References:

- https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-writefile
- https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-flushfilebuffers
- https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-closehandle

## Failure and Cleanup Contract

For every failure after target creation:

1. preserve the primary error;
2. call `SetFileInformationByHandle` with
   `FileDispositionInfo` and `FILE_DISPOSITION_INFO{TRUE}`;
3. close the target exactly once;
4. attempt to close every held directory handle;
5. never call `DeleteFileW`, `Path.unlink`, or another pathname-based delete.

The target is created with `DELETE` access. `FILE_DISPOSITION_INFO.DeleteFile`
is modeled as the documented one-byte `BOOLEAN`.

References:

- https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-setfileinformationbyhandle
- https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-file_disposition_info

Deterministic precedence is:

1. delete-mark failure or target-close failure becomes `E_IMMUTABLE` with
   detail that the incomplete target state is uncertain;
2. otherwise the primary validation, write, checksum, or flush error survives;
3. all remaining closes are still attempted;
4. a later directory-close failure cannot mask the higher-priority cleanup
   state;
5. on the success path, target-close failure means publication did not
   succeed;
6. a directory-close failure after a successful target flush is reported, but
   the successfully flushed target is not retroactively deleted.

This retains the exact evidence-v1 diagnostic list while distinguishing an
uncertain immutable destination in the diagnostic detail.

## ABI Boundary

The Windows module needs only:

- `CreateFileW`;
- `GetFileInformationByHandle`;
- `NtCreateFile`;
- `RtlNtStatusToDosError`;
- `GetFinalPathNameByHandleW`;
- `CompareStringOrdinal`;
- `WriteFile`;
- `FlushFileBuffers`;
- `SetFileInformationByHandle`;
- `CloseHandle`.

Required structures are:

- `UNICODE_STRING`;
- `OBJECT_ATTRIBUTES`;
- `IO_STATUS_BLOCK`;
- `FILETIME`;
- `BY_HANDLE_FILE_INFORMATION`;
- `FILE_DISPOSITION_INFO`.

Use fixed-width integer and pointer-sized `ctypes` fields. Do not use
host-C `long` assumptions. `InitializeObjectAttributes` is a macro, so the
module reproduces its documented initialization rather than trying to load a
function export.

References:

- https://learn.microsoft.com/en-us/windows/win32/api/ntdef/ns-ntdef-_unicode_string
- https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/wdm/ns-wdm-_io_status_block

## Testing Strategy

### Portable contract tests

Linux tests may mock only the native API boundary. They verify:

- x64 structure sizes, offsets, and one-byte disposition Boolean;
- exact `argtypes`, `restype`, invalid-handle, and immediate error capture;
- validated one-component native names and rejection of illegal Windows names;
- root-handle propagation through relative directory and target calls;
- exact target access, sharing, disposition, attributes, and options;
- collision mapping without cleanup of a nonexistent target;
- DOS and UNC final-path normalization;
- sibling-prefix and wrong-relative-destination rejection;
- Unicode and long-path inputs;
- delete-before-close ordering for each post-create failure;
- deterministic cleanup and close-error precedence;
- at-most-once closure for every handle;
- absence of pathname deletion;
- success never marks deletion.

Portable tests prove Python control flow and ABI declarations. They may not
claim native Windows correctness.

### Native Windows 10 tests

Run from PowerShell on local NTFS:

- clean first publication and byte-identical artifact copy;
- immutable second publication with unchanged bytes;
- fresh committed-root bootstrap;
- Unicode paths and a destination exceeding 260 characters;
- symlink, junction, and other reparse point rejection in every walked
  component;
- controlled parent rename or substitution after verification that cannot
  redirect creation outside the held parent;
- injected final-path, validation, write, checksum, and flush failures that
  leave no target;
- delete-mark and close failure precedence;
- competing read, write, and delete opens fail while the target is held;
- successful close retains the file and releases handles;
- repeated runs checked with `GetProcessHandleCount` for leaks;
- full existing Kinglet test suite.

Task 3 closes only after these tests and an independent task review pass.

### Windows 11

Windows 11 native verification remains part of final 00A platform validation.
It does not block the first Windows 10 Task 3 implementation handoff.

## Git and Handoff Workflow

The stable checkpoint is `codex/00a-evidence-harness` at `96abd6a`.
Win32 work lives on child branch `codex/00a-win32-publication`.

Before leaving the Linux environment:

1. commit this design;
2. write and commit the TDD implementation plan and PowerShell runbook;
3. push the stable checkpoint and child branch to GitHub.

On the Windows 10 machine:

1. fetch and switch to `codex/00a-win32-publication`;
2. confirm a clean checkout;
3. run the existing suite as a native PowerShell baseline;
4. execute the plan with fresh implementer and reviewer agents;
5. run native Windows 10 acceptance tests;
6. commit the native evidence and review result;
7. push the child branch.

After Task 3 approval, merge the child branch into
`codex/00a-evidence-harness`. Do not merge either branch to `main` as part of
this handoff.

## Acceptance Criteria

- `publish_record()` remains the public boundary.
- POSIX behavior and tests remain unchanged.
- Windows publication uses held handle-relative creation.
- Existing targets are never replaced or deleted.
- No target can escape the committed platform-spike root.
- Reparse points and unsafe Windows names fail closed.
- Every post-create failure uses exact-handle cleanup.
- Cleanup failures are deterministic and never fall back to pathname deletion.
- UTF-16, Unicode, long-path, and immutable retry cases pass on Windows 10.
- Handle ownership and close ordering have no leaks or double closes.
- Full existing tests pass on Linux and native Windows 10.
- Independent review approves both spec compliance and code quality.

## Explicit Non-Goals

- This design does not make committed evidence ACL-immutable after a
  successful close.
- It does not add a third-party Python or native dependency.
- It does not add a general-purpose Windows filesystem abstraction.
- It does not change evidence-v1 fields or diagnostic codes.
- It does not claim Windows 11 validation before that native run occurs.
- It does not change runtime, client, or Unity spike execution.

## Documentation Risk

Microsoft documents the native APIs and structures, but not Python `ctypes`
packing or every filesystem driver's behavior. `NtCreateFile` documentation
also lacks an explicit Windows 10/11 compatibility-contract table. The design
therefore treats native Windows 10 execution as an acceptance gate and fails
closed on unsupported native statuses or unverifiable final paths.
