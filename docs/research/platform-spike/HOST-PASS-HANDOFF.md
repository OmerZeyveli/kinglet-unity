# Native host pass — handoff for the Windows / macOS runner

This document is **tracked on purpose**. The SDD ledgers under `.superpowers/` are gitignored
scratch, so an agent that clones this repo on another machine sees none of them. Everything below
is what such an agent needs and cannot otherwise discover.

Written 2026-07-28, after the Linux slices of 0R, 0C and 0U were completed and published.

---

## 1. What this pass is for

Three gates are open only because no native Windows or macOS host has run yet. Each closes a
different set of cells:

| Gate | Windows cells | Runner | Ready? |
| --- | --- | --- | --- |
| **0R** runtime bake-off | 8 | `spikes/platform/runtime/run-host.ps1` (Windows), `run-host.sh` (macOS) | **4 of 8 done — Windows 10 22H2 x64 ran 2026-07-28 (§9)** |
| **0C** client capability | 1 per client (`capability-suite`) | `spikes/platform/clients/<client>/runbook.md` | Partly — runbooks were written for the Linux run and need adapting |
| **0U** Unity execution | 9 | *none for Windows* | **No — see §6** |

**Start with 0R.** It is fully scripted and it is the only thing standing between the project and
the runtime decision (see §2).

The Windows 10 x64 half of 0R is now done — see **§9** for what it measured and, more importantly,
for the four defects the first real execution exposed. The Windows 11 x64 cells and both macOS
hosts remain open.

## 2. Why 0R first: the runtime decision is gated, not merely waiting

`spikes/platform/runtime/rubric-v1.json` was frozen before any candidate results existed. It says:

> `disqualification` — "Any failed **or open** hard gate disqualifies the candidate from weighted
> scoring. A failed gate is committed evidence, not a low score."

`hard_gates[1] host-probe-all-cases-all-hosts` requires every case to pass on **every required
native host**, and `hard_gates[7] windows-native` requires native Windows execution. While those
are open, **all four candidates are disqualified** — so no runtime can be selected, no matter what
anyone prefers. This is not a formality to route around: changing the rubric after results exist
requires an ADR explaining why the original criterion was invalid **plus a full rerun of every
affected candidate**.

All four candidates already pass black-box conformance 18/18 on Linux at exact pins, as real
self-contained binaries. Indicative Linux figures (single host, **not** a selection):
Rust 1.3 ms / Go 1.8 ms / .NET 23.7 ms / Python 311.7 ms cold start.

## 3. Standing user rulings — these bind. Do not re-litigate them.

1. **Unity version pin is RELAXED.** Plans say `6000.3.11f1` exactly; the user ruled **any Unity
   6000 line** is acceptable. Never hardcode `6000.3.11f1`. **Not relaxed:** a receipt must record
   the EXACT version and revision actually used, and the separate rule *refuse silent project
   upgrade* still binds — it is independent of which version is pinned.
2. **Pop!_OS counts as Ubuntu.** Linux cells are keyed `linux-ubuntu-24.04.4-lts-x64` while
   `environment.toolchain` carries the real host string (`host=Pop!_OS 24.04 (ID=pop;
   ID_LIKE=ubuntu; codename=noble)`) and the kernel. **That disclosure is what makes the deviation
   legitimate rather than a fabricated host pass.** Follow the same pattern on any host whose
   release string does not exactly match its cell id.
3. **The CoplayDev unity-mcp pin is NOT relaxed:** `v9.7.1` @
   `78ee5418415953b79c358bfe6355fcc3fde7912b`.
4. **A failed or inconclusive result stays as visible evidence.** Never retry until something looks
   green, never delete a failing record, never fabricate a host pass. The runner refuses
   non-conforming hosts *by design*; a refusal is a correct outcome, not an obstacle.

## 4. Windows 0R — the actual steps

**Prerequisites (no repo needed for this part):**

| Component | Exact pin |
| --- | --- |
| PowerShell | **7.0+** — the script has `#Requires -Version 7.0`; Windows PowerShell 5.1 will refuse |
| Go | `1.26.5` |
| Rust / Cargo | `1.97.1` |
| .NET SDK | `10.0.302` (runtime `10.0.10`) |
| Python | CPython `3.14.6` + uv `0.11.28` + PyInstaller `6.21.0` + cryptography `49.0.0` |

Plus `git`, and a `python3` on PATH for `tools.kinglet_spike`.

Verify each: `go version`, `rustc --version`, `dotnet --version`, `python --version`, `uv --version`.
**If a pin is unavailable, STOP and report it** rather than substituting a nearby version — 0R's
whole comparison rests on the pins, and any deviation must be recorded *before* the run, not after.

**Host gate — read before starting.** Only `Microsoft Windows 10` and `Microsoft Windows 11`
captions pass; Server and 8.1 are refused. **Running under WSL is refused** (`$env:WSL_DISTRO_NAME`
set), and Git Bash is not a native run either — the plan's rule is that a native run means a native
process on the target OS. The exact detected build (Version + BuildNumber + UBR) is read from the
live host rather than hardcoded, so you do not need to match `11 25H2`; whatever you are on is
recorded truthfully.

**Steps:**

1. Clone the repo, check out `main`.
2. Install and verify the toolchains above.
3. Dry run first — it prints the planned commands and mutates nothing outside `.kinglet\local\`:
   ```powershell
   pwsh -NoProfile -File .\spikes\platform\runtime\run-host.ps1 -DryRun
   ```
   **Send this output back before the real run.** It confirms the host gate passed and shows the plan.
4. Real run:
   ```powershell
   pwsh -NoProfile -File .\spikes\platform\runtime\run-host.ps1
   ```
   Per candidate it builds, copies **only** the distributable into a clean exec dir, runs it with
   the toolchain directories **removed from the child PATH** (that is the self-contained proof),
   runs the black-box conformance harness requiring **18/18**, measures cold start / peak RSS /
   artifact size, and publishes a `kinglet.spike.evidence/v1` record.
5. Send back: the console output, `git status --short`, and the published evidence records. **Do
   not hand-edit any record.**

This pass also fills the `download_url` / `download_sha256` fields in
`spikes/platform/runtime/toolchains.lock.json`, which currently hold the honest sentinel
`UNVERIFIED-pending-native-host-fetch`. They were deliberately not fabricated.

**`run-host.ps1` has never executed on real Windows.** Two reviews found and fixed real bugs in it
(`Split-Path -LiteralPath … -Parent` is an unresolvable parameter set; `$ErrorActionPreference='Stop'`
made `Write-Error` terminating so the documented exit codes never ran). Expect friction on the first
run — that is what the pass is for. Report failures; do not paper over them.

## 5. macOS

Same shape with `run-host.sh` (it accepts Darwin and Linux) and the same four pinned toolchains.
Unity is **not** needed for 0R.

**Additionally, check this first on macOS** — it is 00U Task 3's macOS exact-argv source and has
never executed on Apple hardware:

```bash
python3 -c "
from tools.kinglet_spike.unity import ownership as o
t = o._posix_process_table()
print('entries:', len(t))
for pid, cmd in t[:20]:
    print(pid, str(cmd)[:120])
"
```

Run it with one Unity project open in the Editor. What matters is whether the Editor's entry carries
a real `-projectPath` argument (meaning `sysctl KERN_PROCARGS2` bound and works) or arrives
truncated/ambiguous (meaning it did not bind, and the module will then refuse every run while any
Editor is open — safe but useless). The failure mode is conservative by design, so the risk is
over-refusal, never project corruption.

## 6. Windows 0U is not runnable — and that was deliberate

There is **no** `run-host.ps1` for the Unity routes. It was deliberately not written: its author
could not execute PowerShell, and an unrun script whose job is launching Unity and killing process
trees on someone else's machine is a liability, not an asset. Two rounds of review found exactly
that class of defect in the sweep script that *was* written in a language its author could run.

If you want the Windows Unity slice, write that runner **on the Windows host, running it as you
go** — not blind from Linux.

## 7. Safety rules that apply to any host

- **Never point Unity at a project a GUI Editor owns.** Use disposable copies under
  `.kinglet/local/` (gitignored) or a scratch directory.
- **`spikes/platform/unity/sweep-workspace.sh` kills processes.** It now refuses non-absolute
  paths, `..`, paths shallower than 3 components, `/`, and anything that is or contains the repo or
  `$HOME`, and it authorises kills only by workspace match or by a pgid the run recorded. Do not
  weaken any of that. Earlier versions killed by a host-wide process-name match and would have
  destroyed an unrelated Editor's helpers.
- **Sweep for all four orphan classes, not one pattern** — see the measured facts document.
- Raw logs, machine paths and license data stay under `.kinglet/local/`, never committed.
- Every new tracked file needs a `provenance.tsv` row; that file has a comment block and a
  tab-separated header — append surgically, never rewrite it wholesale.
- Shell must be bash 3.2 compatible (macOS ships 3.2): no `declare -A`, no `grep -oP`, never pipe
  into `head` under `set -euo pipefail`, validate an argument before `shift 2`.

## 8. The four defect classes this project keeps re-learning

Every one of these was fixed repeatedly during the Linux work — **fixed where found, not everywhere
it existed.** A whole-branch review then found a surviving instance of each. Do not add a fifth.

1. **Unanchored substring matching over paths.** `/x/proj` matching `/x/proj2`; a path that merely
   *ends with* the target; `pgrep` matching the searching command's own argv.
2. **Whitespace or a newline defeating a guard.** A newline in a path split a `ps` row and made a
   truncated command look complete; a multi-line value made `[ "$D" -lt 3 ]` error inside an `if`,
   where `set -e` does not fire, so it fell through to the permissive branch.
3. **A safety check with no explicit "I could not tell" branch.** Unresolved cases fall through to
   the permissive answer *by construction*. Every guard needs a third outcome.
4. **A test satisfied by a comment, a stub, or a fixture that bypasses the real reader.** Assertions
   were satisfied by a code comment; a fabricated fixture passed while the real parser failed.

Two derived rules: **a refusal test must not be able to perform the act it forbids**, and **report
exactly what you did, never what you intended** — several reports on this project claimed
verification that had not happened, and every one was caught.

---

## 9. The Windows 10 22H2 x64 0R pass — executed 2026-07-28

Host: `Microsoft Windows 10 Pro for Workstations`, version 10.0.19045, build 19045.7548, x64,
PowerShell 7.6.4. Recorded under matrix cell `windows-10-x64` with the **full caption in
`environment.toolchain`** — the edition string is not `Microsoft Windows 10` exactly, so this
follows the Pop!_OS precedent in §3.2: the deviation is disclosed in the record, which is what makes
it legitimate.

Run stamp `20260728T170051Z`. Four cells published, `run-host.ps1` exited 1 because one failed.

| Candidate | Status | Cold start median | Peak RSS | Artifact |
| --- | --- | --- | --- | --- |
| rust | **pass** 18/18 | 16 ms | 2 940 KB | 0.61 MB |
| go | **pass** 18/18 | 21 ms | 6 056 KB | 2.66 MB |
| dotnet | **pass** 18/18 | 83 ms | 20 856 KB | 70.72 MB |
| python | **FAIL** 15/18 | 2 116 ms | 7 204 KB | 12.17 MB |

**Windows cold start is nothing like Linux.** Linux measured Rust 1.3 / Go 1.8 / .NET 23.7 /
Python 311.7 ms. Every candidate is roughly an order of magnitude slower here (Python ~7x). Windows
process creation plus on-access AV scanning of a freshly written binary dominates. **Do not compare a
Windows column against a Linux column as if they were the same measurement.**

### Why python failed — read this before concluding anything about Python

`process.child-grandchild`, `process.cancel` and `process.no-descendants` all fail with
`module 'os' has no attribute 'killpg'`. `kinglet_host_probe.py` spawns with
`start_new_session=True` and reaps with `os.killpg(pgid, SIGKILL)` — both POSIX-only.

**This is a probe omission, not a Python limitation.** Go, Rust and .NET each ship an explicit
Windows process-tree implementation (`go/process_windows.go`, Job Objects in `rust/src/process.rs`,
`dotnet/ProcessTree.cs`); the Python probe has no Windows path at all. Python could implement the
same thing via Job Objects. Until someone writes that, the published `fail` record says the
candidate as-built does not satisfy the contract on Windows — which is true, and is what a reader
should take from it. It does **not** license the conclusion "Python cannot do this on Windows".

Note also that the probe leaves live `kinglet-host-probe` descendants behind while it runs (nine
were observed mid-run, all under the run's own exec dir). They did exit on their own — this was
**not** a hang, and the pass completed unaided.

### Four defects the first real execution exposed

All four had survived because no Windows host had ever run this, and three of them are instances of
the defect classes in §8.

1. **`build-record.py` could not express a failure.** It hardcoded `"status": "pass"` and
   `SystemExit`-ed on any non-pass assertion — while `rubric-v1.json` is built entirely around
   failures being committed evidence and `load.py`'s `RECORD_STATUSES` has always accepted `fail`.
   The tooling whose job is producing records could not produce the record this run needed. Status
   is now derived from the assertions, and a probe whose own `status` contradicts its assertions is
   refused outright rather than coerced (§8.3).
2. **`run-host.ps1` aborted the whole bake-off at the first failure.** Because python runs first,
   go/rust/dotnet were never built, never measured and never published, and the failure itself was
   not recorded either. A candidate failure is now recorded and the pass continues; the run still
   exits non-zero, and it distinguishes "recorded a fail" from "produced no record at all".
3. **`.gitattributes` silently invalidated the entire evidence chain on Windows.** `* text=auto`
   with `core.autocrlf=true` rewrites every committed evidence artifact to CRLF on checkout, so no
   recorded `artifacts[].sha256` matches any more. Measured: the Linux go artifact hashed to
   `292f7b63…` on disk against a recorded `e080b332…`, and normalising CRLF back to LF reproduced
   `e080b332…` exactly. The failure was silent and destructive — `report` reclassified every
   previously passing Linux runtime, unity and client cell as `invalid` and rewrote the committed
   `reports/coverage.md` to say so. Fixed by marking the two hashed trees `-text`. **Scope it by
   tree, not by extension** — a first attempt using `**/*.json` fixed the runtime cells and left the
   client cells broken, because those artifacts are `.txt` and `.jsonl` (§8.1).
4. **PyInstaller's work dir landed at the repo root.** The runner passed `--distpath` but not
   `--workpath`, and cwd is the repo root, so each run left an untracked `build/`. `.gitignore`
   already anticipated it at `spikes/platform/runtime/python/build/`. The Linux runner never hit it
   because it reused a prebuilt onefile and never invoked PyInstaller at all.

5. **The fix for (2) silently blanked every build log.** Found on the Linux review pass, not on the
   Windows host. Re-expressing `Invoke-Native` as a wrapper over the new
   `Invoke-NativeAllowFailure` wrote it as `$null = Invoke-NativeAllowFailure …`. A native command
   writes to the PowerShell **pipeline**, and an assigned pipeline never reaches the host, so `uv
   sync`, PyInstaller, `cargo build`, `go build`, `dotnet publish` and the `publish` call all
   produced no console output at all. stderr still surfaced — which is why the Windows run still
   looked normal and why nothing failed. `Invoke-NativeAllowFailure`'s own doc-block asserted the
   opposite ("the child's output must keep flowing to the console exactly as before"): a comment
   describing an invariant the code next to it broke. Fixed by dropping the assignment, with
   `InvokeNativeOutputTests` executing the real function under `pwsh`; re-adding `$null =` fails it.

Also observed, **not fixed** — decide these before the next Windows run:

- **`scripts/check-provenance.sh` cannot pass on a Windows checkout, for the same CRLF reason.** It
  hashes the working-tree file against a recorded *upstream* digest computed over LF bytes, so all
  76 `status=verbatim` rows fail. Verified: `templates/Model.cs.template` hashes to `aa51b6af…` on
  disk against a recorded `62d735ed…`, and LF-normalising reproduces `62d735ed…` exactly. It is
  **pre-existing and unrelated to this pass** — none of the 76 files were touched here, and the
  structural checks (no orphan rows, no missing rows, field sanity, `rule=absent`, `rule=ours-wins`)
  all pass. Fixing it properly means either normalising line endings before hashing in the script,
  or widening the `-text` policy beyond the evidence trees. Both are judgement calls with real
  trade-offs, so neither was made unattended. **Until then, run `check-provenance.sh` on Linux or
  macOS**, and do not read a Windows failure as manifest rot.
- **`dotnet publish` rewrites `dotnet/packages.lock.json`**, flipping the RID section
  (`net10.0/linux-x64` → `net10.0/win-x64`). It is a tracked file, so every host swap dirties it. It
  needs a lock covering all RIDs, or exclusion from the run.
- **The Python probe needs a Windows process-tree implementation** before
  `runtime.python.windows-*.host-probe` can mean anything about Python rather than about the probe.

### Environment notes for whoever repeats this

- Toolchains were installed per-user, at the exact pins: Go 1.26.5 (`~/.kinglet-toolchains/go`),
  Rust 1.97.1 MSVC (`~/.cargo`), .NET SDK 10.0.302 (`~/.dotnet`), uv 0.11.28, CPython 3.14.6
  fetched by uv. **Rust needs the MSVC linker** — `link.exe` ships only with Visual Studio Build
  Tools (VS Code is not sufficient), and installing it needs one interactive UAC approval.
- The system-wide .NET 8 SDK was dropped from `PATH` for the run. `run-host.ps1` strips the single
  directory `Get-Command dotnet` resolves to; a second `dotnet` behind it would weaken the
  toolchain-stripped-PATH proof.
- `TEMP`/`TMP` were pointed at a volume with free space. The conformance harness writes its
  workspaces under `TEMP` and the first attempt died with a genuine `ERROR_DISK_FULL`.
- The suite's POSIX tests (`run-host.sh`, `measure.sh`) cannot pass on Windows even with Git Bash —
  they need `/bin/true`, `/usr/bin/time` and `uname`/`sw_vers` PATH shims. Baseline at `f36aeda` on
  this host: 13 failed. Judge a Windows run against that baseline, not against zero.

---

## 10. The host inventory does not cover the matrix — an open plan-level decision

Established 2026-07-29, on the Linux review pass of §9. **0R cannot close on the hardware that
exists**, and this is worth stating plainly before anyone spends another hour installing toolchains:

| Matrix host | Hardware | Status |
| --- | --- | --- |
| `linux-ubuntu-24-04-x64` | Pop!_OS dev box | done, 4/4 pass |
| `windows-10-x64` | Windows 10 Pro for Workstations box | done, 3 pass + 1 fail (§9) |
| `macos-26-arm64` | Mac mini, Apple Silicon | **available, not yet run** |
| `windows-11-x64` | none owned — a friend's machine, deferred until the project justifies asking | **blocked, deferred** |
| `macos-26-x64` | **none, and none expected** | **unreachable** |

`macos-26-x64` has no path to closure. That is not a scheduling problem, it is a permanent gap in a
frozen matrix, and it means the `host-probe-all-cases-all-hosts` hard gate can never be satisfied as
written. There are exactly three honest responses and **none of them has been chosen**:

1. Amend the matrix to drop `macos-26-x64` (and possibly demote `windows-11-x64`), with the
   reasoning recorded — Apple has shipped no Intel Mac since 2023 and macOS 26 is the last release
   to support any of them, so "we do not test Intel Macs" is a defensible product decision, not a
   dodge.
2. Amend `rubric-v1.json` to define "every required native host" as a named subset rather than
   every cell in the matrix.
3. Leave both open and accept that 0R never closes, taking the runtime decision another way — which
   contradicts §2 and should be chosen deliberately if at all.

**Do not silently edit the matrix into agreement with the hardware.** The matrix was frozen before
results existed precisely so it could not be moved to fit them; moving it now needs the amendment
written down as an amendment. Until one of the three is chosen, `gate 0R` exits 1 and that is the
correct answer.

The interim position the user has taken: **the Windows 10 cells stand in for Windows**, and the
Windows 11 pass waits until the project is far enough along to be worth asking a friend for their
machine.

### The macOS release pin is exact — check it before installing anything

Coverage matches a record to a cell by **exact string equality** on `os`/`release`/`arch`
(`coverage.py`: `record.environment.release == cell.release`). The macOS cells are pinned to
`release = "26.5.2"` — the full patch version, not a `26` bucket. And `run-host.sh` sets
`RECORD_RELEASE="$MACOS_PRODUCT_VERSION"` straight from `sw_vers -productVersion`.

So a Mac mini on 26.5.1, or 26.6.0, or anything but exactly **26.5.2**, publishes four perfectly
valid records that match **no cell at all**. The run reports success, `gate 0R` does not move, and
the hour of toolchain installs buys nothing. Windows did not expose this because
`Get-WindowsRelease` composes a coarse bucket (`10-22H2`) from the caption and DisplayVersion; the
macOS path has no such widening.

**First command on the Mac mini, before anything else:**

```bash
sw_vers -productVersion
```

If it does not print `26.5.2` exactly, stop and decide — update/hold the Mac, or amend that cell's
release the same way §10 requires for the others. Do not run the pass and hope.
