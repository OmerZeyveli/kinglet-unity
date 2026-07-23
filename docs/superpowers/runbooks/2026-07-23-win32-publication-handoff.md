# Win32 Publication Windows 10 Handoff

This runbook resumes Kinglet 00A Task 3 on a native Windows 10 x64 machine.
Use PowerShell. Do not use WSL or Git Bash.

## Branches

- Stable checkpoint: `codex/00a-evidence-harness`
- Windows child: `codex/00a-win32-publication`
- Child base: `96abd6a`
- Design commit: `396cc9f`
- Test-split clarification: `c746d97`

The child branch may merge into the stable checkpoint only after native
Windows 10 acceptance and independent review. Neither branch merges to
`main` during this handoff.

## Clean Checkout

```powershell
git clone https://github.com/OmerZeyveli/kinglet-unity.git kinglet-unity
Set-Location .\kinglet-unity
git fetch origin
git switch --track origin/codex/00a-win32-publication
git status --short
```

If the repository already exists:

```powershell
git fetch origin
git switch codex/00a-win32-publication
git pull --ff-only origin codex/00a-win32-publication
git status --short
```

`git status --short` must emit no output. Do not delete or overwrite local
work to force a clean state.

## Environment Check

```powershell
if ($env:OS -ne "Windows_NT") { throw "Native Windows required" }
if ($env:WSL_DISTRO_NAME) { throw "WSL is not allowed" }
python -c "import os, platform, sys; print(sys.version); print(platform.platform()); assert os.name == 'nt'; assert platform.machine().lower() in ('amd64', 'x86_64')"
```

Use a local NTFS checkout. The native test verifies the filesystem before
accepting the run.

## Baseline Before Implementation

```powershell
python -m unittest discover -s tests/kinglet_spike -t . -v
python -m unittest discover -s tests/kinglet -p "test_*.py" -v
git diff --check
```

The native test module does not exist until Task 6. Existing Python suites
must pass before implementation begins.

## Execute the Plan

Plan:

```text
docs/superpowers/plans/2026-07-23-kinglet-win32-publication.md
```

Use subagent-driven development:

1. fresh implementer for one task;
2. focused RED and GREEN evidence;
3. one task commit;
4. independent spec-and-quality reviewer;
5. fix and re-review every Critical or Important finding;
6. update the ignored SDD ledger;
7. move to the next task only after approval.

Do not dispatch two implementation agents concurrently in the same checkout.

## Native Acceptance

After Task 6 creates the wrapper:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\tests\run-win32-publication.ps1
```

The wrapper must:

- reject WSL;
- run portable and native Win32 tests;
- run every spike-harness Python test;
- run every existing build Python test;
- return a nonzero result as a hard failure;
- print its final PASS line.

The Bash aggregate is a Linux gate and is intentionally not invoked from
Windows.

After committing Task 6, enforce that the test run itself leaves no changes:

```powershell
.\tests\run-win32-publication.ps1 -RequireClean
```

## Evidence Hygiene

Keep the raw PowerShell transcript outside the repository. In the committed
task report record only:

- Windows 10 edition/build without user or machine name;
- Python version and architecture;
- NTFS confirmation;
- commands run;
- pass/fail counts;
- sanitized failure details;
- commit SHA.

Do not commit:

- absolute Windows user-profile paths;
- account, machine, or organization identifiers;
- credentials or tokens;
- raw prompts;
- unsanitized environment or process listings.

## Push

After task review and native acceptance:

```powershell
git status --short
git log --oneline --decorate -12
git push origin codex/00a-win32-publication
```

Do not force-push.

## Linux Return Verification

Back on Linux:

```bash
git fetch origin
git switch codex/00a-win32-publication
git pull --ff-only origin codex/00a-win32-publication
python3 -m unittest discover -s tests/kinglet_spike -t . -v
bash tests/run-tests.sh
git diff --check
```

Only after Linux verification and final Task 3 review may the child branch
merge into `codex/00a-evidence-harness`.

Windows 11 native validation remains open for final 00A.
