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

### The app-server has two traps, and both return something that looks like an answer

Measured in Task 2 and independently reproduced by its review. Both bite silently.

**1. The parameter is `cwds`, an array — never `cwd`.** `externalAgentConfig/detect` with `cwd`
returns `{"items":[]}` with no error, which reads as *"nothing here"*. `hooks/list` and `skills/list`
are worse: with `cwd` they return a **well-formed answer about the wrong repository**. A reviewer hit
that and got a clean result for a project it was not asking about. **Get every parameter shape from
`codex app-server generate-json-schema`** — not from a field name, not from this ledger.

**2. A bare `printf … | codex app-server` pipeline cannot answer.** Closing stdin races the server's
shutdown and responses are dropped. Measured over 12 naive runs: 6 returned nothing, 6 returned only
the `initialize` reply, and **in 12 of 12 the probed method's result never appeared**. Keep stdin open
until you have read the reply you want.

Ask the server to enumerate its own methods (send a name that cannot exist; the error lists the real
ones — 129 of them). That enumeration doubles as the negative control that separates *"this method
exists"* from *"this server accepts anything"*.

### A field name is not a measurement — the wave's own rule, applied to itself

Task 2 reported that Kinglet's `timeout: 3000` (ms) lands in Codex's `timeoutSec`, therefore fifty
minutes. Its review found that **`HookMetadata.timeoutSec` carries no description in Codex's own
schema**, and that the only documented unit anywhere in the protocol is `timeoutMs`. Nothing had
measured Codex waiting. The unit claim was an inference from a field name — the exact class of claim
this wave exists to eliminate, produced by the task built to eliminate it.

Whatever you are about to conclude from a name, measure it instead. A five-second hook registered
with a one-unit timeout settles this one in a single probe.

### THE CENTRAL FINDING SO FAR: the hooks register, fire, and do nothing

Measured in Task 2's fix loop, discovered by dumping a hook's stdin — the one thing nobody had
looked at.

**Codex's file tool is `apply_patch`, and its `tool_input` carries only
`{"command": "*** Begin Patch…"}`** — for creating a new file and for editing an existing one alike.
There is no `file_path`, no `new_string`, no `old_string`, no `content`. `Edit` and `Write` survive as
matcher **aliases**; the payload vocabulary underneath is Codex's own.

The control, same hook, same edit, same file:

| Payload | Result |
|---|---|
| `block-scene-edit.sh` + a Claude-shaped payload | **exit 2, 412 bytes — blocks** |
| `block-scene-edit.sh` + the real Codex payload | **exit 0, 0 bytes — does nothing** |

Class derived from `.claude/settings.json` × each hook's source: **8 of 9 tool-event hooks match,
run, and are inert.** Only `bash-gate.sh` survives, because it reads `.tool_input.command` — still
blocking, exit 2, 1589 bytes. **No Kinglet hook reads `tool_name`, so the break is entirely in
`tool_input`.**

**Why this is the finding the wave existed to produce.** The import reports **31 successes, 0
failures**. All 12 hooks register with `warnings: []`. The matchers fire — measured, with per-hook
marker files rather than stderr counts, and `shell`/`Shell`/`bash`/`Zzz` correctly never firing.
Every observable signal says the guardrails crossed. Eight of nine do nothing. **A wave that shipped
on the import's own success report would have shipped a toolkit whose enforcement layer is
decoration.**

Two things this does **not** mean, and a reader who takes either has been misled by framing rather
than facts: it does not mean the hooks fail to register, and it does not mean matchers are broken.
Both are now measured false.

### `timeout: 3000` means fifty minutes — measured from both sides

Kinglet's hook timeouts are milliseconds. Codex's `timeoutSec` is **seconds**, established by two
independent brackets that solve together to `u ∈ (0.667 s, 1.5 s)` — excluding milliseconds,
deciseconds, two-second ticks and minutes. Six of Kinglet's twelve hooks carry a timeout
(2000 / 3000 / 5000), so the shipped values become 33, 50 and 83 minutes.

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
| 1 | The probe harness | **DONE** | `a5ec1bd..0b58d05` | general-purpose implementer; 1 fix round; all 8 findings ADDRESSED |
| 2 | Does Codex import a `.claude/` configuration? | open | — | *(brief pending)* — must be written after Task 1, because it calls the harness Task 1 produces |
| 3 | Codex's hook mechanism, measured | open | — | *(brief pending)* |
| 4 | Kinglet's 12 hooks under Codex | open | — | *(brief pending)* |
| 5 | Kinglet's 16 skills under Codex | open | — | *(brief pending)* |
| 6 | Rules, `AGENTS.md`, commands and agents | open | — | *(brief pending)* |
| 7 | Layer B — MCP routes against the live bridge | open | — | *(brief pending)* — needs a free Editor |
| 8 | Ship the payload the measurement supports | open | — | *(brief pending)* — ship list decided by Tasks 2–7 |
| 9 | Installer writes and removes the Codex layout | open | — | *(brief pending)* |
| 10 | Findings synthesis, decision, debt | open | — | *(brief pending)* — gained **Step 5a** during the run: re-derive `docs/ANTI-VACUITY.md`'s bash-4 census and put it under a guard |
| 11 | Close the probe harness's residual guard gaps | open | — | **added during the run** by Task 1's completion sweep and re-review. Runs after Task 9, when the harness has stopped changing |

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

## Task 1 — fix round 1 and close

Fix round 1: implementer commit `0b58d05`, status `DONE_WITH_CONCERNS`, 15 mutations. Guard 22 → 35
assertions, nothing weakened. Re-review verdict: **all eight findings ADDRESSED**, 20 mutations,
zero `MUTANT DID NOT APPLY`, no new breakage. Recommendation: accept. **Task 1 closed at
`a5ec1bd..0b58d05`.**

### The entry worth keeping: a reviewer withdrew its own finding, with the confound named

Important 3 (SIGINT leaves the credential-bearing home) was reported as **deterministic 3/3**. The
implementer could not reproduce it and pushed back with numbers — SIGINT 0/70. The re-review settled
it against the reviewer, and the mechanism is the house defect in its purest form:

```bash
setsid bash -c '… exec bash …/codex-probe.sh …' >/dev/null 2>&1 &
PGID=$(ps -o pgid= -p $! | tr -d ' ')
kill -INT -"$PGID" 2>/dev/null
```

`setsid` forked, so `$!` was the wrapper, which had already exited. `ps -o pgid= -p $!` returned
**empty**. `kill -INT -""` therefore sent no signal at all — `rc=1`, and `2>/dev/null` hid the error.
The "orphaned home" was a **live probe's working directory**, which is correct behaviour. The 3/3
determinism was three repetitions of the same non-experiment.

Re-run correctly (`set -m`, pgid verified non-empty, delivery counted): 0 leaks in 46 runs across
INT/TERM/HUP on both harnesses. **SIGKILL leaks 6/6 on both** — no trap can cover it — which is the
half that was right and the half the fix shipped against.

Two things this costs nothing to remember: an error stream silenced by `2>/dev/null` is how a
non-experiment passes for a measurement, and **a repetition count is not evidence of anything except
repetition**.

### Deferred findings, each with an owner that is a task

| Finding | Ruling | Owner |
|---|---|---|
| The sweep's liveness check is unguarded — deleting `kill -0` is 35/35 green, and a live probe's home and credential are then deleted mid-run (2/2 deterministic) | Safe to carry: the check is present and correct today, and the failure needs someone to delete it. It is a silent-regression gap, not a live defect | **Task 11 Step 1** (added to the plan in this edit) |
| Deleting all three signal arms is 35/35 green. The arms are correct in isolation (right cleanup, right `128+signo`), but on bash 5.2.21 the EXIT trap already covers those signals, so a behavioural assertion would pass either way | Safe: correct code, and Task 1's decision to leave it unasserted rather than assert it green was right. What is missing is a *structural* check, labelled as standing in for an unobservable behaviour | **Task 11 Step 2** |
| `HOME_ENTRIES` is a top-level `ls -A`, so a leak nested inside a directory the seed already creates is invisible | Safe for now — the realistic wholesale widening is caught. But **Task 5 measures skill discovery**, and a leaked `~/.codex/skills/` is exactly what would corrupt it with a green suite | **Task 11 Step 3** |
| `docs/ANTI-VACUITY.md`'s bash-4 census reads `13 + 7 + 42 + 1 + 1 = 64`; the tree now derives **13 + 8 + 43 + 1 + 1 = 66**. Found by the controller's completion sweep, not by any review — it is in no diff | **Deliberately not corrected now.** Tasks 8, 9 and 11 each add a test file, so any figure written today is wrong by construction before the wave ends. Correcting it now would be the fourth recorded rot of this number, twice inside the document whose subject is numbers that rot. `tests/*.sh` is not `tests/test-*.sh` — it counts `run-tests.sh` — which is how it was mis-stated before | **Task 10 Step 5a** (added to the plan in this edit), which both corrects it **and puts it under a guard**, because the number is not the deliverable |
| `docs/research/codex-client/evidence/livesmoke.meta.json` was written under the old `codex_args` schema | **Dropped, not deferred.** It is untracked, gitignored, and regenerable by re-running one probe; Task 2 produces fresh evidence under the new schema inside this same wave. Recording it as dropped so the next reader is deciding whether to agree rather than waiting for a pass nobody scheduled | — |
| The plan's Task 1 code listing still wrote `"codex_args"` | Closed by the controller in this edit: the listing carries a **SUPERSEDED IN PART** header naming both changes. The listing is kept as the brief that was given, not as a description of what shipped | — |

### Corrections to the record

- Task 1's first report claimed the red-first state was "every one of the 22 failed". It was 19, with
  the last three assertions never reached and **no verdict line at all**. Now fixed: the guard reports
  a clean `0/35` with its verdict line present when the harness is absent.
- `provenance.tsv`'s `fix-round-1:` clause appears on six rows, but **four of those are from an
  earlier, unrelated wave** (`unity-optimizer.md`, `unity-reviewer.md`, `unity-optimize.md`,
  `unity-scene.md`). A future sweep keyed on that marker will over-collect.

---

## Deferred and parked findings

### From Task 1

See the Task 1 table above. Nothing is parked at a fix-loop cap; that loop closed at round 1.

### From Task 2's re-review — deferred, with owners

| Finding | Ruling | Owner |
|---|---|---|
| **`skills/list` totals are not stable.** Task 2's home reported 24; the reviewer's reported **59** — 18 repo, 35 user, 6 system — with the 35 fetched over the network into the disposable home from `plugins/cache/openai-curated-remote/`. The **18 repo skills reproduce exactly** | Safe: the load-bearing figure is the repo count, and it is stable. A total that varies with what a home has cached is not a fact about Kinglet. **Any skills figure quoted anywhere in this wave must be the 18 repo skills, and must say so** | **Task 5**, whose entire subject is skill discovery, and **Task 10 Step 5** when it re-derives the research documents' numbers |
| **`bash-gate.sh` blocks read-only commands as `meta-mutation`.** It blocked three of the reviewer's read-only commands, one of them because the string `.meta` appeared as JSON **test data**. There are no `.meta` files in this repository at all | Safe to carry: it fails closed, which is the correct direction for a guard, and the cost is a retry with a clearer command. But it is a false positive on a substring, and this repository has hunted unanchored substring matches on a path four times already | **Task 11**, which is already the "close the harness's residual guard gaps" task and is the only remaining task that touches guard behaviour rather than measurement. Add it there when Task 11's brief is written |

**A note on the second one, since it recurred inside its own review:** the reviewer hit it while
verifying someone else's work, which is the position with no stake in the answer — the same
circumstance that made the `MUTANT DID NOT APPLY` lesson stick. A guard that costs a reviewer three
retries costs every implementer the same, silently, forever.

---

## Editor / scene state

Task 7 is the only task that touches Unity. Record here whether it left any scene dirty, saved, or
untouched.

*(Not yet reached.)*
