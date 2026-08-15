docs/superpowers/plans/2026-08-15-codex-cli-second-client.md
**Execution mode:** subagent-driven

**Spec:** `docs/superpowers/specs/2026-08-15-codex-cli-second-client-design.md`
**Branch:** `pioneer/codex-second-client`
**Base commit (whole-branch review diffs from here):** `9a2ebec` (main)
**Branch HEAD at setup:** `20a1716`

---

## Standing facts for every dispatch

Copy this section into every dispatch. A fresh subagent inherits none of the controller's reading of
the project.

### Gates — both, after every task

```bash
bash tests/run-tests.sh                       # must report `Failed: 0`
bash scripts/check-provenance.sh              # must print exactly `provenance OK`
```

Header count must equal file count, **with ANSI escapes stripped first**:

```bash
bash tests/run-tests.sh 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g' | /usr/bin/grep -c '^--- test-.*\.sh ---'
ls tests/test-*.sh | wc -l
```

The runner colours its headers, so an anchored `grep -c` on raw output returns **0** on a completely
healthy suite — indistinguishable from the catastrophe the count exists to detect.

### THE SUITE TAKES 364 SECONDS — measured 2026-08-15 on this host

Any timeout below ~450 s truncates the run, and a truncated run reads as red. **Do not set a timeout
under 450000 ms.** A previous wave wrote 150000 ms into its own constraints against a suite that
really took 191–255 s, and dispatched four implementers under a constraint that manufactured
failures. The suite has grown since; 364 s is today's measurement, not a ceiling.

### Provenance

Every newly tracked file needs a `provenance.tsv` row or the orphan check fails. Tab-separated:
`path`, `origin`, `upstream_version`, `upstream_path`, `upstream_sha256`, `status`, `note`.
Legal origins: `ecu|donchitos|superpowers|original`. Legal statuses: `verbatim|modified|original`.
For an original file the middle three columns are each a single `-`.

**Anything adapted from Superpowers is `origin=superpowers`, never `origin=original`.** Writing
`original` for a row that has an upstream is a documented way this manifest rots.

### This is the toolkit repository, not a Unity project

There is no Unity and no MCP in any task except Task 7. `install.sh` gates on `Assets/` +
`ProjectSettings/`, so the installer is exercised against a synthetic fixture:

```bash
bash tests/fixtures/mkproject.sh /tmp/p    # --variant urp|builtin|bare|dirty
bash install.sh --project-dir /tmp/p --dry-run
```

### Task 7 only: one implementer against one Unity Editor, absolutely

The Editor is a single process holding a single asset database. Two agents driving it over MCP
concurrently corrupt shared state as a broken scene, not as a merge conflict — there is no diff to
review. Confirm with the controller that nobody else holds the Editor before Task 7 starts.

### Shell conventions this repository enforces

- bash 3.2 compatible: no `declare -A`, no `grep -oP`.
- Under `set -euo pipefail`, **never pipe into a reader that exits early**. `head` and `grep -q` both
  do. Use a here-string: `grep -qF -- "$needle" <<< "$haystack"`.
- Validate an argument **before** `shift 2`; under `set -u` the shift fails before your error message
  prints and the caller gets a silent exit 1.
- Interactive `grep` on this host is ugrep and `find` is bfs. Use `/usr/bin/grep` in scripts and
  wherever a negative result is load-bearing — absence probes can return empty silently.

### New test files are self-contained

Define your own assertion helpers and set `set -euo pipefail`, so `bash tests/<file>.sh` is a valid
way to run one. A runner-provided file exits 0 having asserted nothing when run standalone, which is
how a plan once told an implementer to expect a failure from a file that would report a pass in both
directions.

### The wave's own discipline — this is not boilerplate

**Tasks 2–7 are measurements. A measurement task's deliverable is a recorded verdict, not a
particular verdict.** "Codex ignores Kinglet's hooks" is a successful Task 4 if it is measured and
recorded. **An implementer who edits Kinglet to make a probe come out green has destroyed the thing
the wave exists to produce.**

**Nothing in the spec's "inferred, NOT verified" list may be used as a premise.** That list:
hook event names, the filename `hooks.json`, the `decision:block` protocol, `trusted_hash`,
`MatcherGroup`, the external-agent config importer, and the `.codex`/`.agents`/`.claude`/`.cursor`
string adjacency. All of it came from a binary's string table, where symbols sit next to each other
because of how the linker packed them. If a dispatch hands you one of these as a fact, **that
dispatch is wrong — report `NEEDS_CONTEXT` rather than proceeding.**

### Codex is pinned at 0.145.0 for this wave

`0.147.0` is available. Do not upgrade. Record `codex --version` in every probe's metadata; a
hook-schema change between versions invalidates the evidence, and the pin is what makes that
detectable rather than silent.

### Never commit a credential

Probing requires copying `~/.codex/auth.json` into a disposable `CODEX_HOME`. That home is mode 700,
the copy is mode 600, and it is removed by an EXIT trap. The evidence directory is gitignored.

---

## Interfaces produced so far

*(Populated as tasks complete. A brief written before a task ran guesses; this section is what
really happened.)*

Nothing yet — Task 1 is the first dispatch.

---

## Task items

| # | Task | Status | Commit range | Notes |
|---|---|---|---|---|
| 1 | The probe harness | **open** | — | brief = plan §Task 1 |
| 2 | Does Codex import a `.claude/` configuration? | open | — | *(brief pending)* — must be written after Task 1, because it calls the harness Task 1 produces |
| 3 | Codex's hook mechanism, measured | open | — | *(brief pending)* |
| 4 | Kinglet's 12 hooks under Codex | open | — | *(brief pending)* |
| 5 | Kinglet's 16 skills under Codex | open | — | *(brief pending)* |
| 6 | Rules, `AGENTS.md`, commands and agents | open | — | *(brief pending)* |
| 7 | Layer B — MCP routes against the live bridge | open | — | *(brief pending)* — needs a free Editor |
| 8 | Ship the payload the measurement supports | open | — | *(brief pending)* — ship list decided by Tasks 2–7 |
| 9 | Installer writes and removes the Codex layout | open | — | *(brief pending)* |
| 10 | Findings synthesis, decision, debt | open | — | *(brief pending)* |

**Re-planning is expected, not a failure.** If Task 2 measures that Codex imports a `.claude/`
configuration natively, Tasks 3–6 shrink and Task 8's ship list changes. Re-plan rather than
executing the remaining tasks as written.

---

## Deferred and parked findings

*(None yet.)*

---

## Editor / scene state

Task 7 is the only task that touches Unity. Record here whether it left any scene dirty, saved, or
untouched.

*(Not yet reached.)*
