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

### A new file in `scripts/` ships into every user project — discovered by Task 1

`install.sh` copies `scripts/` into each installed project's `.claude/scripts/`. Adding a file there
without excluding it reddens the suite from two directions at once, and neither guard names
`install.sh` in its failure message:

- `tests/test-derived-counts.sh` checks `docs/GETTING-STARTED.md`'s repo-scripts and
  installed-scripts figures against the tree;
- `tests/test-shipped-citations.sh` fails with *"installed script(s) named by no agent, command or
  skill"*.

If your task adds anything to `scripts/`, decide **before** you write it whether it ships. If it does
not, exclude it in `install.sh` in **both** the path enumeration and the write loop — the same shape
`check-provenance.sh` already uses — and update `docs/GETTING-STARTED.md`'s repo figure. Task 1 did
this for `codex-probe.sh`; **Task 9 must know the exclusion exists before it touches the installer.**

There is a trap inside the trap: `test-derived-counts.sh` extracts the skipped names by grepping
`install.sh` for the literal comparison shape, so a *comment* that quotes that shape gets extracted
as a third skipped script. Describe the shape without spelling it.

### Codex prints `Reading additional input from stdin...` on every probe — discovered by Task 1

The plan states that without stdin redirected `codex exec` prints that line **and blocks**. Measured
against the real 0.145.0: `< /dev/null` stops the *block*, not the *message*. Codex prints it
whenever stdin is not a terminal, then reads EOF and proceeds. **It is on the stderr of every probe
and is a warning about nothing.** It is deliberately not filtered, because codex's stderr is the
evidence. Tasks 3–7 grep `NAME.stderr.txt`; do not treat that line as a fault.

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

### From Task 1 — `scripts/codex-probe.sh` *(pending review; treat as provisional until Task 1 closes)*

```bash
bash scripts/codex-probe.sh --name NAME --prompt FILE \
  [--workdir DIR] [--seed DIR] [--sandbox MODE] [--out DIR] [--model MODEL]
```

Writes **four** files into the evidence directory (default
`docs/research/codex-client/evidence`, which is gitignored):

| File | Contents |
|---|---|
| `NAME.jsonl` | the raw event stream |
| `NAME.last.txt` | the final agent message |
| `NAME.stderr.txt` | codex's stderr — where its warnings land |
| `NAME.meta.json` | the exact invocation, `codex --version`, exit code, sandbox, model, workdir, UTC timestamp |

**READ `codex_argv`, NOT `codex_args`.** Fix round 1 replaced the space-joined `codex_args` string
with **`codex_argv`, a JSON array that includes the prompt**. The old key is gone. A space-joined
string could not represent a path containing a space unambiguously, and it omitted the prompt
entirely — so it was not "the exact command" the brief asked it to record, which in a wave whose
deliverable is a recorded verdict is a defect in the evidence rather than in the formatting.

Exits with codex's exit code; usage errors exit **64**.

Two behaviours that differ from the plan's text, both decided by Task 1 and both load-bearing for
later tasks:

- **`NAME.last.txt` is derived from the event stream when codex's `-o` file is absent or empty.**
  `-o` remains authoritative when present. A run that dies before its first turn completes writes no
  `-o` file, so a reader that trusted `-o` alone would read nothing and not know why.
- **`NAME.last.txt` and `NAME.meta.json` are removed before each run.** They are not truncated by a
  redirection the way `.jsonl` and `.stderr.txt` are, and a stale `last.txt` read as this run's
  answer is a silently wrong measurement.

**`--seed` was exercised by the Task 1 reviewer** and works: it copies dotfiles, nested directories
and the executable bit, and a seed carrying its own `auth.json` is correctly overwritten by the real
credential and re-chmodded to 600 — the exact arrangement Task 3 will build. **Task 3 is still the
first real consumer**; report anything wrong there as a harness defect rather than working around it.

The event stream shape, measured against the real binary:

```json
{"type": "thread.started", "thread_id": "…"}
{"type": "turn.started"}
{"type": "item.completed", "item": {"id": "item_0", "type": "agent_message", "text": "…"}}
{"type": "turn.completed", "usage": {"input_tokens": …, "output_tokens": …}}
```

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

## Task 1 — review outcome and finding dispositions

Implementer: **general-purpose**, not `unity-coder`. Task 1 is a bash script and a test file; routing
it to an agent that writes C# and drives the Editor would have measured the dispatch rather than the
task.

Implementer report: `DONE`. Review verdict: **Spec ✅, Quality: Needs work** — no Critical, three
Important, six Minor. Implementer commits `a5ec1bd`, `b955320`.

The review did its own job rather than reading the report's: it reproduced six rows of the
implementer's mutation table independently, and then **found four argv mutations the guard did not
catch at all**. That is the finding that mattered, and no amount of re-reading the diff would have
produced it.

| # | Finding | Disposition |
|---|---|---|
| Important 1 | Four argv facts (`--sandbox`, `--cd`, `--json`, `--skip-git-repo-check`) asserted by nothing; all four mutants stayed 22/22. `meta.json`'s `"sandbox"` reads from the variable, not argv, so the evidence file can record `read-only` for a run that executed at `danger-full-access` | **fix round 1** |
| Important 2 | Two of the credential constraint's three clauses guarded by nothing; widening the copy to `cp -R "$HOME/.codex/."` stays green and would leak `~/.codex/skills/` into **Task 5's skill-discovery measurement** | **fix round 1** |
| Important 3 | A process-group SIGINT (Ctrl-C) skips the EXIT trap and leaves the credential-bearing home; orphans accumulate because the pre-run `rm -rf` only clears the current `$$` | **fix round 1** |
| Minor 6 | The test file dies under `set -e` before its own verdict line, so a truncated section reads like a complete one; report's "every one of the 22 failed" overstates by three | folded into round 1 |
| Minor 7 | `codex_args` is a space-joined string and omits the prompt, so it is not "the exact command"; the comment's stated reason for python3 is not what the code achieves | folded into round 1 |
| Minor 4 | `.gitignore` is the one modified file whose provenance note gained no clause — and it is the change that enforces the credential constraint | folded into round 1 |
| Minor 5 | Five provenance note clauses run into the previous sentence with no separator | folded into round 1 |
| Minor 8 | Two concurrent suites share the fixed `defaultout.*` names in the real evidence directory. Reviewer could not reproduce (six concurrent pairs, 22/22) | **folded into round 1 after an initial decision to defer, and the reversal is the entry worth keeping.** `CLAUDE.md` records that running two suites at once is how a previous flake reproduced *every time*, and that **three implementers hit it, called it a flake, and moved on**. The cost of a known name collision is not its failure rate; it is the next person disbelieving it. One line removes it by construction |
| Minor 9 | A new file entered `docs/ANTI-VACUITY.md`'s `scripts/*.sh` declared scope without the sweep being run | **closed by the review, not deferred.** The reviewer ran C1–C4 over `codex-probe.sh` and found the document's sentence still true — `die()`'s exit 64 is argument validation, not a floor. Nothing to correct |

### ⚠️ Cannot verify — carried, and true for every later task

- **shellcheck is not installed on this host.** CI runs it at warning level over `scripts/**`; neither
  new file could be linted locally. This applies to every task in the plan that adds a script.
- **No macOS pass.** `tests/test-bash32-compat.sh` covers the new files statically and they pass, but
  they have only executed on this Linux host. Consistent with the repository's standing position.

---

## Deferred and parked findings

*(None yet — every Task 1 finding was either fixed in round 1 or closed by the review.)*

---

## Editor / scene state

Task 7 is the only task that touches Unity. Record here whether it left any scene dirty, saved, or
untouched.

*(Not yet reached.)*
