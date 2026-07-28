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
| **0R** runtime bake-off | 8 | `spikes/platform/runtime/run-host.ps1` (Windows), `run-host.sh` (macOS) | **Yes** |
| **0C** client capability | 1 per client (`capability-suite`) | `spikes/platform/clients/<client>/runbook.md` | Partly — runbooks were written for the Linux run and need adapting |
| **0U** Unity execution | 9 | *none for Windows* | **No — see §6** |

**Start with 0R.** It is fully scripted and it is the only thing standing between the project and
the runtime decision (see §2).

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
