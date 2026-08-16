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

### THE SUITE TAKES 434 SECONDS — re-measured 2026-08-16, and it is still growing

**Use a timeout of at least 600000 ms.** A truncated run reads as red, and a red that is really a
truncation is the most expensive false signal this repository produces.

**This figure has moved twice inside one wave** — 364 s at setup on 2026-08-15, **434 s** today — as
the suite went 3543 → 3865 assertions. The guidance that stood until now was "at least 450000 ms",
which against a 434 s run leaves **sixteen seconds** of headroom. That is not a margin, and a previous
wave already paid for exactly this: it wrote 150000 ms into its constraints against a suite that
really took 191–255 s and dispatched four implementers under a number that manufactured failures.

**Re-measure before quoting.** The number is a moving property of the tree, not a constant.

### A flaky assertion exists in `tests/test-codex-shim.sh` — do not call it a flake and move on

Found during Task 9 and **correctly diagnosed by checking the instrument before the subject**: the
implementer's full-suite run went red on one assertion, and it **reproduces at `b6bc214` with that
task's changes stashed, 3 of 4 runs.** So it is pre-existing, not Task 9's.

It is **fail-closed** — the shim still refuses — but it refuses on a failed staging write rather than
on the budget, so the count is lost.

**THE CAUSE IS UNKNOWN, and an earlier version of this entry said otherwise.** It read that the
shim's own header *"documents a race of exactly this shape and calls it 'currently unreachable… not a
property worth depending on', which the reproduction refutes."* That is wrong on the load-bearing
half. The comment near `shim_watch` describes what would happen **without** the `trap - EXIT TERM INT
HUP PIPE` reset in the killer subshell — and the reset **is there**, kept deliberately, *"verified
equivalent over 70 paired runs"*. So the specific race it names is already defended against and the
reproduction **does not refute that sentence**. Attributing the failure to it would send the next
implementer to a line that is already correct.

That argues **for** routing rather than guessing, so the disposition is unchanged and only the
confidence is: this is an unexplained failure in a fail-closed surface, not a diagnosed one.

**3 of 4 is not a flake rate, it is the majority outcome.** Recording it makes the next red readable;
it does not stop the suite's most likely failure being a known-good surface, which is how a team
learns to skim red. **It needs an owner, and it has one: Task 11.** The expensive half — the
reproduction — is done:

```bash
# From a clean tree at the commit under test:
git stash push install.sh uninstall.sh tests/test-codex-surface.sh   # if Task 9's changes are present
for i in 1 2 3 4; do
  bash tests/test-codex-shim.sh 2>&1 | /usr/bin/grep -cE '^\s*FAIL'
done
# Observed at b6bc214: 1 0 1 1  (3 of 4 red).  Observed on Task 9's tree: 0 1 1  (2 of 3 red).
```

The failing assertion is *"the refusal names how many of the envelope's files were checked"* in the
400-file budget case. The symptom is `<tmpdir>/payload.<N>.json: No such file or directory` on stderr
followed by `BLOCKED: codex-hook-shim: could not stage payload <N>` — i.e. the shim's temp directory
has gone while the staging loop is still running, so it refuses on the staging failure and the
`of 400 file(s)` count never appears. **What removes that directory mid-loop is the open question.**

The controller re-ran the whole suite independently on 2026-08-16 and got **3865 / 0 failed, 434 s** —
**it did not hit.** That is what a race looks like, and it is precisely the shape `CLAUDE.md` warns
about: a real defect that three implementers dismissed as a flake because it did not reproduce for
them. **It is written down here so the next red run is read as this, not as a new break.**

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

### Four silent-failure layers now, and each one reports success

Every layer below is measured. What makes them a set rather than a list is that **each reports
success in its own terms while the layer below it does nothing.**

| # | Layer | What it reports | What actually happens |
|---|---|---|---|
| 1 | The import | **31 successes, 0 failures** | 7 of 9 commands silently dropped; rules never cross |
| 2 | Registration | `registered N, warnings [], errors []`, `enabled: true` | — |
| 3 | **Hook trust** | `enabled: true`, `statusMessage: None` | **Untrusted, the hook fires 0 times. No prompt, no warning, nothing logged.** Solvable — see below |
| 4 | The hook body | matcher fires, process runs | 8 of 9 read fields `apply_patch` does not have, and do nothing |

**`enabled: true` does not mean it will run.** Layer 3 was found by the Task 3 reviewer in one run,
*after* the task had declared F5 undelivered — and it subsumes the others, because every F4 block
result was established behind the bypass flag.

Add to that the shapes that fail open **and log nothing anywhere**, including under `RUST_LOG=debug`:
`exit 2` with no output, `exit 1` with a message, plain text on stdout, malformed JSON, and an empty
`reason`. Hooks run under `set -euo pipefail`, so **any unhandled failure exits non-zero but not 2 —
Claude Code reads that as an error, Codex reads it as an unlogged allow.** Verified with a real
death, not a synthetic `exit 1`. A payload shim that dies on bad JSON fails open.

### The block contract, for Task 4

> **exit 2 with ≥ 1 byte on stderr**, or **exit 0 printing one JSON object with `"decision":"block"`
> and a non-empty `reason`.**

Both work, on the shell tool and on `apply_patch`, each against a deliberate allow control, with the
reason delivered to the model **verbatim** — including Kinglet's own `BLOCKED:` prefix, wrapped as
`Command blocked by PreToolUse hook: <stderr>`. **Kinglet already ships the first form.** Both
results are currently conditional on layer 3 being bypassed.

Two adjacent facts: `.codex/hooks.json` needs a top-level `hooks` wrapper (`description` is
optional), and `UNITY_HOOK_MODE=warn` correctly allows but its 47-byte warning is **shown zero times
anywhere** — under Codex it is not "block downgraded to warning", it is "block downgraded to
nothing".

### Hook trust: an installer can grant it, and here is the whole shape

**This supersedes the sentence that stood here until Task 3's fix round — that both block results
were conditional on the bypass flag. They are not.** Both mechanisms were re-run with trust granted
properly and **no bypass flag in argv** (verified by grepping the constructed argv before running),
and neither result changed.

There is no `hooks/trust` method. **Trust is config.** The installer reads each entry's `key` and
`currentHash` from `hooks/list`, then writes to the **user home's** `config.toml`:

```toml
[hooks.state."<abs>/.codex/hooks.json:pre_tool_use:0:0"]
enabled = true
trusted_hash = "sha256:ab9c…"
```

Three properties Tasks 8 and 9 must design around, all measured:

1. **A project cannot vouch for itself.** `trusted_hash` inside `hooks.json`'s matcher group — the
   shape the binary's string table suggested — is not merely unhonoured, it is **invisible**: same
   `currentHash`, `warnings: []`, still `untrusted`, with the path held constant. So Kinglet cannot
   ship trust in a committed file. **The installer must write the user's `~/.codex/config.toml`**,
   which means consent, a backup, and a receipt entry.
2. **The hash cannot be precomputed** — it is path-dependent by construction, though deterministic
   and home-independent. Install order is fixed: write `hooks.json` → query `hooks/list` → write
   trust.
3. **The hash covers the config entry, not the script.** Editing a hook body changed the script's
   own sha256 and left `currentHash` untouched; changing `timeout` changed it; restoring gave back
   the exact baseline. Trust means *"I vouch for this command line"*, **not** *"I vouch for this
   code"* — and that sentence has to survive into anything user-facing.

**4. The enterprise switch that makes all of this inert.** `allowManagedHooksOnly` exists in Codex's
managed-configuration surface, alongside a `ManagedHooksRequirements` block with `managedDir` /
`windowsManagedDir` and an 11-event map, and a `HookSource` enum carrying **five** routes. **If an
organisation sets it, Kinglet's project hooks may not run at all regardless of trust.** It is
explicitly **unmeasured** — no managed host was available — and it belongs in Tasks 8 and 9's design
constraints, not in a footnote.

### All four Kinglet hook events fire

`PreToolUse`, `PostToolUse` and `Stop` were each observed firing with `fires=1`; `SessionStart` was
observed in Task 2. Payloads differ by event, derived mechanically rather than assumed:
`PostToolUse` carries **`tool_response`**, which `PreToolUse` lacks; `Stop` carries
`last_assistant_message` and `stop_hook_active` and **no tool fields at all** — directly relevant to
`session-save.sh`.

**Do not quote a method count as a constant.** The app-server enumeration returned 129 to one agent
and 123 to another on the same build.

### A negative about a tool this large is a claim about a search — and here is the search

Twice in this wave a superlative over *the routes that happened to be tried* was written as a
superlative over *the routes that exist*, and both times a reviewer found the missing one in the same
place. **The method, which is executable rather than a moral:**

```bash
codex app-server generate-json-schema   # then enumerate the bundle for the capability noun
```

- Task 5's *"the measured minimum is one directory symlink"* → `skills/extraRoots/set` sits at
  `oneOf[22]`, **one entry past `skills/list`**.
- Task 6's *"nothing measured restores the narrowing"* → `ThreadStartParams.sandbox`,
  `TurnStartParams.sandboxPolicy` and `permissionProfile/list`, found by grepping
  `ClientRequest.json`.

**Enumerate the schema bundle for the noun before writing any "there is no…" sentence.** Two for two.

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
| 2 | Does Codex import a `.claude/` configuration? | **DONE** | `1d8e941..89e7552` | general-purpose implementer; 2 fix rounds; F1 = **confirmed, lossy in silence** |
| 3 | Codex's hook mechanism, measured | **DONE** | `1993b1b..952cd7a` | general-purpose implementer; 1 fix round; F4 **and** F5 delivered — my RE-PLANNED header had wrongly dropped F5 |
| 4 | Kinglet's 12 hooks under Codex | **DONE** | `23e2444..53daafb` | general-purpose implementer; **3 fix rounds**, one Critical; the shim ships and all 9 tool-event hooks enforce |
| 5 | Kinglet's 16 skills under Codex | **DONE** | `1bb6135..f4f19c4` | general-purpose implementer; 1 fix round; skills **are** invoked unnamed, and the spec's payload-location proposal was refuted |
| 6 | Rules, `AGENTS.md`, commands and agents | **DONE** | `4898876..56183ef` | general-purpose implementer; 2 fix rounds, one Critical; the pointer verdict was prompt-conditional and became a **positive** ship recommendation |
| 7 | Layer B — MCP routes against the live bridge | **DEFERRED TO LAST** | — | **The owner is using the Editor.** See the ruling below |
| 8 | Ship the payload the measurement supports | **DONE** | `b713f09..993dee2` | general-purpose implementer; 2 fix rounds; the payload ships and its guard is 86 assertions |
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

## Task 2 — close, and the re-plan it forced

Implementer: **general-purpose**. Report `DONE`, then two fix rounds. Review: **Spec ✅**, four
Important; re-review 1: all nine ADDRESSED, one new Important; re-review 2: **both ADDRESSED,
nothing new broke, Task 2 can close.** Range **`1d8e941..89e7552`**.

**F1 = confirmed.** All three `externalAgentConfig/*` methods exist and do real work, with a negative
control enumerating 129 methods. The import writes `.codex/hooks.json`, 13 byte-identical hook
scripts, 8 agents as `.codex/agents/*.toml`, `.agents/skills/` and `AGENTS.md`, reporting **31
successes, 0 failures** — and is lossy in silence, in four ways that the success report cannot show.

### Two methodological entries worth more than the verdict

**The criterion refused to classify against a dead control.** When the reviewer's own
`guard-project-config` control lacked the trigger, the harness printed `CONTROL VACUOUS — cannot
classify` rather than scoring the hook INERT. That is what stops an inertness table from erring
toward alarm — the direction nobody double-checks, because it reads as vigilance.

**A byte count that looked like a disagreement was a property of the input.** Implementer and
reviewer reported 1363 and 1589 bytes for the same hook. Two blocking commands differing by exactly
39 characters produced 1581 → 1620: output is `constant + len(command)`. Neither figure was a
property of the hook, and quoting either as one was the actual defect.

### What Task 2 forced into the plan

| Task | Was | Now |
|---|---|---|
| 3 | measure config location, schema, events, block protocol, trust | **one probe** — block protocol only |
| 4 | measure whether hooks fire | **did not shrink**; the wave's centre of gravity — 8 of 9 enforce nothing and the hook bodies need rewriting against `apply_patch` |
| 5 | measure discovery and invocation | **discovery settled**; invocation only, plus an unreconciled 18-vs-16 skill count |
| 6 | measure four classes | **split** — two settled mechanically, two became design work |

---

## Task 3 — close

Implementer: **general-purpose**. Report `DONE`, one fix round. Review: **Spec ✅ with one declared
exception, Quality Approved**, one new Important — F5 undelivered, and the contradiction that let it
slip was **mine**, in the RE-PLANNED header I wrote. Re-review: **all five verified, nothing new
broke.** Range **`1993b1b..952cd7a`**.

The reviewer built a rig deliberately unlike the implementer's — one variant per directory, one
literal hook body, no `basename` dispatch — and ran 19 independent probes. That difference in shape
is what makes the agreement mean something.

### The entry worth keeping: a fall-through that exits 0 is indistinguishable from a measured allow

The implementer **discarded one of its own `apply_patch` runs as invalid** and said so. Its probe
dispatched on its own `basename`; one variant matched no `case` branch, fell through, and exited 0 —
producing a clean-looking *"the block does not work on the file tool"*, which is the most
consequential wrong answer available in this task. It was caught only because the hook logged which
variant it had resolved.

This is the same shape as the `setsid` confound the same reviewer found in its own Task 1 work: **a
control that silently did nothing looks exactly like a subject that legitimately did nothing.** Two
independent instances in one wave. The defence in both cases was the same — make the instrument log
what it actually did, not what it was asked to do.

### Deferred, with owners

| Finding | Ruling | Owner |
|---|---|---|
| `codex-facts.md` records `stop` as not measured. It **fires** — the re-review observed `Stop fires=1` with a distinct payload (`last_assistant_message`, `stop_hook_active`, no tool fields) | Safe: the document understates rather than overstates, which is the harmless direction. Folding it in completes F3 — all four Kinglet hook events now observed firing | **Task 10 Step 5**, which already re-derives both research documents |
| The enterprise switch `allowManagedHooksOnly` is missing from `codex-facts.md`'s "three properties Task 8/9 must design around" — and it is the one condition that makes the whole hook feature inert regardless of trust. Its "what it would take" also names two managed routes where the enum carries five | **Not safe to leave only in a document Task 8 might not re-read.** Carried into this ledger's Standing facts as property 4, which every Task 8/9 dispatch copies verbatim | **Task 8 and Task 9** via Standing facts, plus **Task 10 Step 5** for the document |

---

## Task 4 — close, and the five silent-failure layers

Implementer: **general-purpose**. `DONE`, then **three fix rounds** — the longest loop of the wave and
the only one that opened with a **Critical**. Range **`23e2444..53daafb`**. Suite 3578 → **3727**;
`tests/test-codex-shim.sh` 100 → **149** assertions.

**What shipped:** `scripts/codex-hook-shim.sh`, a payload shim that normalises Codex's `apply_patch`
envelope into the shape Kinglet's hooks already read. **`.claude/hooks/` and `.claude/settings.json`
are byte-unchanged since the base commit `9a2ebec`** — verified independently by the controller, not
taken from the report. All nine tool-event hooks now enforce under Codex.

### The fifth layer, and the one-second margin that is the whole design

| Ceiling that fires | `file_change` | file | Codex's stderr |
|---|---|---|---|
| the shim's watchdog | **0** | **ABSENT** | 1 `hook:` line — verbatim refusal |
| Codex's `timeoutSec` | **1** | **PRESENT** | **0 mentions of `hook`, `block` or `timeout`** |

**A `PreToolUse` hook that Codex times out is a silent allow.** Measured twice — the first table was
confounded (disabling the watchdog also changed how the shim blocks), and the re-run keeps the
watchdog armed in both arms so only the firing ceiling differs. That is why `--emit-config` emits the
shim's budget one second **under** Codex's ceiling: it is the difference between a hung hook refusing
and one waving an unchecked edit through.

### Three lessons this loop paid for

**A trap that runs is not a trap that speaks.** Bash *does* run an EXIT trap on a fatal signal, then
re-raises and discards `exit 2`. What is lost is the **message**: the trap executes with the
descriptors of the command it interrupted, and the discriminator is **builtin versus external** —
only a builtin's redirection rewires the shell's own descriptors, so `wait >/dev/null 2>&1` loses the
refusal while `sleep 30 >/dev/null 2>&1` keeps it. `scripts/codex-probe.sh` never lost anything
because its handler only does `rm -rf`: it has nothing to say. Two defences, and the 2×2 separates
them — `exec 9>&2` recovers the **message**, the signal arm recovers the **status**.

**Bash defers a trapped signal until the current foreground command finishes.** 1.0 s inside an async
`wait`, **20.0 s** inside a foreground external. Which is why the fix is one **invocation deadline**
checked before every step, with every child backgrounded even when unbounded — a foreground child
cannot be interrupted.

**An overloaded sentinel needs two mutations to expose.** `0` meant *expired* to one function and
*unbounded* to another. Neither `S2` (delete the check) nor `T1` (initialise to `-1`) is observable
alone — both give 4.08 s, identical to baseline. **Together they give 12.1 s**, which is the defect.
The one-line fix both the controller and the reviewer proposed was half a fix, and only the
combination showed it.

### Three parties were wrong once each, and each was corrected by measurement

- **The controller and the reviewer** both proposed the same one-line sentinel fix. It was insufficient.
- **The implementer** wrote a guard that sampled the verdict; the whole-second mutation survived it.
  It found this itself, and its diagnosis corrected its own assumption — the truncation bites in a few
  percent of runs, not the ~50 % it expected. The reviewer's independent figure (39/40 surviving)
  agrees. **It would otherwise have shipped exactly the intermittent assertion `CLAUDE.md` warns about.**
- **The controller relayed a wrong correction.** I passed on the reviewer's claim that a "6 s" figure
  transcribed the `postToolUse` ceiling. The implementer refuted it: no surviving capture is
  identifiable as that arm's, the file having been overwritten. The reviewer then withdrew its own
  finding and named the flaw precisely — its inference rested on an unstated assumption, and the error
  was **stating it as a defect in a specification document**. The implementer adopted the underlying
  point anyway and re-ran with the confound removed.

### Deferred, with owners

| Finding | Ruling | Owner |
|---|---|---|
| `shim_ms_to_sleep` emits `3.000` rather than `3`. On a `%N`-less BSD host **every** value takes that form, so if any BSD `sleep` rejects a fractional argument the killer never fires | Safe on this host — GNU `sleep` accepts it and the suite is green. Unverifiable without a macOS box, and the mitigation is one character | **The planned macOS host pass.** Named here because it is the first Codex-side item that pass inherits |
| `T5` is classified as a floor, but the reviewer judges the label **generous**: it is unobservable alone *and* combined, 0/60 in a race probe. The sentinel split converted its defect into a no-op | Safe: it is "equivalent given the fix", not an independent layer, and saying so is more honest than leaving it counted as a guard | **Task 11**, which is already the harness-and-guard-gaps task |
| A reviewer cleaned up with `rm -rf /tmp/kinglet-codex-shim.*` — a glob delete in shared `/tmp`. Nothing was damaged; the controller verified the repository, the scratchpad and other agents' directories | Dropped as an incident, kept as a rule: **remove named directories you created, or work under one `mktemp -d` root and remove that single path.** Both agents adopted it for the remaining rounds | — |

---

## Task 5 — close, and the spec proposal that measurement refuted

Implementer: **general-purpose**. `DONE`, one fix round. Review: **Spec ✅ with one deviation, Quality
Needs work** — no Critical, four Important, **all four in the framing rather than the facts**; all four
load-bearing claims reproduced exactly under independent re-derivation. Re-review: **clean**. Range
**`1bb6135..f4f19c4`**.

### Skills are invoked without being named — with a control, and then four

Five of five relevant unnamed probes loaded a skill. Kinglet-shaped guidance *without* a load was
never observed. Controls went from one to five across the loop; **four of five loaded nothing**,
including a Unity-domain question about `Time.fixedDeltaTime`, and one collision case loaded
`using-kinglet` while **declining** `addressables`.

**Routing comes from Codex's injected index, not from any project document.** In a rig with
`AGENTS.md`, `CLAUDE.md`, `.claude/` and `.codex/` deleted, the model *tried* `sed AGENTS.md`
(exit 2) and `rg` (exit 1, empty), then went **straight to the exact skill path with no prior
discovery**.

**But the reach is narrower than the listing.** Across all rigs only **6 distinct skills were ever
observed loading** — 5 of 18, 3 of 18, 2 of 16 by rig, denominators taken from the rigs themselves.
The other twelve are **discoverable, not reachable**, and no measurement says otherwise.

### The spec's payload-location proposal is refuted; its first fallback wins

The spec proposed *"no second copy: Codex reads `.claude/skills/` directly"*, with a symlink and then
an install-time copy as ordered fallbacks. Measured: `.claude/skills/` alone gives **0** repo skills.
**The proposal is dead and the first fallback is selected** — which is the structure working, not a
defect in it.

| route | result |
|---|---|
| `.claude/skills/` alone | **0** skills |
| `skills` config key, two spellings | **0** — and controlled: the same `config.toml` carried a trust entry and `hooks/list` went **0 → 12**, so the file was read while the key did nothing |
| directory symlink `.agents/skills → ../.claude/skills` | **16**, enabled, invocation observed |
| the importer's copy | works, but carries **50** `.Codex/` rewrites over 17 of 18 skills, including **13 skill→skill references over 8 targets, 0 resolving** while all 8 exist one directory away |
| `skills/extraRoots/set` | **16**, enabled, no symlink and no copy — but `scope:"user"` and **non-persisting** |

**A correction Task 8 must build on: the symlink is a discovery device, not a load path.**
`skills/list` hands the model the real `.claude/skills/…` path, and every `command_execution` reads
that path. **Nothing traverses `.agents/skills` at load time.** A ship design assuming loads flow
through `.agents/` would be designing for a path nothing uses.

### Two methodological entries

**An instrument that reads its own output.** A skill load appears as a `command_execution` reading
the `SKILL.md`, so the detector must read **only the `command` field** — a loaded skill body echoes
its own `.Codex/skills/…` citations into the *output*, and a naive grep scored **4 loads where 2
happened** (worse elsewhere: 5 versus 2).

**A silent negative needs proof the mechanism was live.** "The `skills` key did nothing" and "the
file was never read" are the same observation until something else in the same file demonstrably
works. The trust entry going 0 → 12 is what makes the refutation mean anything.

### Deferred, with owners

| Finding | Ruling | Owner |
|---|---|---|
| **The importer writes `timeoutSec: 3000` un-converted.** Task 4 fixed the units at the source via `--emit-config`, but a user who reaches Codex through `externalAgentConfig/import` rather than through Kinglet's installer still gets the millisecond value read as seconds | **Not safe to leave implicit.** It is the gap between what Kinglet installs and what Codex's own importer produces, and a reader who used the import would have 33-to-83-minute hook timeouts with nothing saying so | **Task 8** (ship list must state which path a user is on) and **Task 9** (the installer must not assume the import ran) |
| A control drifted on a clean-slate re-run: a fresh `t5-control` loaded `using-kinglet` where the committed one loaded nothing | Safe: of five control runs now in existence four loaded nothing, and `t5-control-api` loaded nothing with **no shell command at all** on two independent runs. The section already discloses `n = 1` | **Task 10 Step 5**, to record that the `none` cells are per-run facts rather than invariants |
| The `### Reproducing` recipe leaves three gitignored `repro-*.out` files behind | Dropped: they are evidence, the directory is gitignored, and removing them would remove the only artefacts a re-runner produces | — |

---

## Task 6 — close, and the finding that inverted twice

Implementer: **general-purpose**. `DONE`, two fix rounds. Review: **Spec ✅, Quality Needs work — 1
Critical, 6 Important, 4 Minor**; re-review 1 closed all seven and raised two; re-review 2 **clean**.
Range **`4898876..56183ef`**.

### `AGENTS.md` is injected; `CLAUDE.md` is only findable

The sentinel came back with **zero `command_execution` items**. The same sentinel in `CLAUDE.md` also
came back — **but only after an `rg`.** Under Codex, `CLAUDE.md` is a file the model can locate, not a
document it is given.

### The rules pointer: three statements, each truer than the last

This is the wave's best example of a finding improving under adversarial review rather than surviving
it.

1. **"The pointer is ignored"** — the implementer's first measurement, Kinglet's own wording read
   **0 of 6** and obeyed 0 of 6, indistinguishable from a control.
2. **"The pointer is prompt-conditional"** — the reviewer's counter-experiment on byte-identical rigs,
   changing *only* the prompt: **3 of 3** under a request that says "follow this project's
   conventions", against **0 of 3** for the same prompt with the pointer removed.
3. **"Removing the pointer produces confidently wrong conventions"** — the implementer's own
   counter-experiment, which it ran rather than re-scoping on the reviewer's numbers. All three
   control runs asserted *"This follows the project's current convention…"* while sourcing the answer
   from `GameLifetimeScope.cs`, with the real rule sitting unread.

**The verdict is a gradient, not a conjunction.** The pointer is **necessary** — `nopointer` opened
`.claude/rules/` **0 times in 24 runs** across all three prompt shapes, and the reviewer derived 18 of
those 24 itself. It is **not sufficient** — 1 of 12 under a terse prompt. And **the request sets the
rate**: 1/12 → 4/6 → 6/6.

So the finding ended as a **positive ship recommendation — keep the declarative pointer** — where it
began as a retraction.

### The restriction that has no destination

Agent tool grants were not dropped in transit: **there is no destination.** Codex's own agent
definitions carry no tools key, and all six of its `openai.yaml` files agree. So capability is
**ambient** under Codex, and what evaporated is the **restriction** — **5 of 8** Kinglet agents carry
a narrowing that vanishes. `unity-reviewer` gains `Write`, `Edit`, `Bash` **and** MCP.

A read-only reviewer that can write is not a degraded reviewer; **this wave's own loop depends on a
reviewer being unable to repair what it reviews.** Neither the TOML route nor the skill route restores
the narrowing — a skill has no tools contract either. Per-thread sandbox routes *do* exist (see the
schema-enumeration rule above), so the honest statement is that **Kinglet's measured shape**
(`codex exec`, one `--sandbox` per run) has no remedy, not that Codex has none.

### Deferred, with owners

| Finding | Ruling | Owner |
|---|---|---|
| The round that fixed categoricals **introduced a new one**: *"`AGENTS.md` is the only document that reaches the model unasked"*, contradicted one section up by `## Skills`, where names and descriptions are injected with no tool call | Safe: it does not change Task 8's action either way, since the skills injection is frontmatter-only and Task 5 covers it. The repair is one word — *"the only project document whose **body** reaches the model unasked"* | **Task 10 Step 5**, which re-derives both research documents |
| The `### Reproducing` sweep has now found something **three times out of three** — and the third instance was introduced by the round doing the sweeping | Recorded as method, not as an incident: **after any round that rewrites categoricals, sweep for categoricals the rewrite introduced** | Standing method; applied by every remaining task |

---

## Task 8 — close: the payload ships

Implementer: **general-purpose**. `DONE`, two fix rounds. Review: **Spec ✅** (eight steps discharged,
two exceeded), **Quality Needs work — six Important, nothing shipped broken**; the reviewer ran every
shipped entry point end to end on a real `install.sh --yes` fixture. Re-review 2: **approved**. Range
**`b713f09..993dee2`**. Suite 3727 → **3817**; `tests/test-codex-surface.sh` at **86** assertions.

**Ships:** the hook shim, `scripts/codex-command-to-skill.sh`, `generate-claude-md.sh --client codex`,
the skills bridge, `AGENTS.md`, and an MCP configuration row with client behaviour **marked open**.
Rules ship unchanged with the declarative pointer kept. **`.claude/hooks/` and `.claude/settings.json`
remain byte-unchanged since the base commit** — verified by the controller over the whole range.

**Excluded in writing, each with its measurement:** agents in both shapes, `.codex/` as tracked
content (recorded `rule=absent`, and the reviewer proved the red gate fires by planting both paths),
the importer's entry document, and two refuted skill-root routes.

### The finding that unblocked Task 4's leftover

The shim had been withheld because shipping it reddened a guard. The real reason surfaced here:
`--emit-config` writes an **absolute** path, so **a shim outside the project is nine registered hooks
enforcing nothing.** Shipping it fixes that rather than moving it — and the guard's mutation now trips
**three** assertions at once, because excluding the shim from the payload *is* what makes the emitted
config point outside the project. Two defects found separately were one defect.

### The guard could not see the fix its own task shipped

The sharpest review finding of the wave. `tests/test-codex-surface.sh` generated **against this
repository, which has no `.claude/scripts/`**, so the in-project preference branch was never executed
and the assertion checked a substring **both** branches satisfy. Forcing an out-of-project shim path
left it green at 72/72. It now builds a real fixture install and generates twice — the second time in
Task 9's shape — asserting every quoted path resolves under the project root.

Two more mutants survived that green guard: hook coverage collapsing **12 → 5**, and the converter's
default `--out` root. The 12 → 5 case is the instructive one — the same file already enforced the
right identity for commands one section away, so the guard was inconsistent **with itself**.

### The one argument with no measurement under it was wrong

The ship list claimed the spine non-negotiables missing from the generated digest are the ones a hook
enforces. **They are not.** The only `UNITY_EDITOR` in the hooks is an *exemption*, not a check, and
of six `NON-NEGOTIABLE` sections **one is in the digest, one is half hook-covered, and four are in
neither**. The old residual read *"if row 1 is not installed"* when for those four it held **even when
installed**. The four were then inlined, Codex arm only; the Claude document stayed byte-identical at
4870 bytes.

This is why that argument was flagged to the reviewer before it read the diff: it was the single piece
of reasoning in the ship list with nothing measured beneath it.

### Deferred, with an owner

| Finding | Ruling | Owner |
|---|---|---|
| The conjunction branch in `tests/test-codex-surface.sh` § 8 matches `and` **anywhere** on the gate line and runs regardless of `gate_or`, so a **correct** disjunction whose sentence happens to contain an ordinary "and" is failed and told it is "worse than the original defect" | Safe: it **cannot let a real conjunction through**, and it fails loudly rather than silently. But wrong advice on correct work is the shape that costs an afternoon here — `CLAUDE.md` records three implementers dismissing a real defect as a flake. The fix is a three-line branch reorder, already dry-run against four shapes without re-opening the mutation it exists for | **Task 11**, which is already the guard-gaps task and will be editing these files |
| The `HookEventName` enum check stays undone. The decline is right; its stated dichotomy was false and is now corrected — the suite **already skips with a stated reason**, so deriving the enum only when `codex` is on `PATH` would add no dependency and hardcode nothing | Recorded rather than closed, with the reason restated as *"the residual is one reviewed edit wide"* rather than *"it is unavailable"* | **Task 11**, same file, same visit |

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

## Editor / scene state, and why Task 7 moved to last

Task 7 is the only task that touches Unity. **It was deferred to the end of the plan on 2026-08-16,
before being dispatched**, because the preflight found the owner working in the Editor.

Measured, not assumed:

```
ps            -projectPath /home/riive/Documents/GitHub/Endless-Evolution
              Unity/Hub/Editor/6000.0.68f1/Editor/Unity
ss -tlnp      127.0.0.1:8080  LISTEN  users:(("python",pid=2050426))
initialize    serverInfo: mcp-for-unity-server 3.4.5
EE branch     feat/skin-system, clean tree
```

The bridge is live and it is **the owner's Editor, holding the owner's project**, on a branch that
moved since this wave started. **The one-implementer rule is absolute and it is not about files:**
the Editor is a single process holding a single asset database, and two agents driving it over MCP
concurrently corrupt that state as a broken `.unity` file, not as a merge conflict — with no diff to
review and no record of which call did it.

**Ruling: reorder, do not wait and do not proceed.** Tasks 8 through 11 touch no Unity and no MCP, so
the wave loses nothing by running them first. Task 7 runs when the Editor is free.

**What Task 8 must therefore assume:** the MCP client questions are **unmeasured** — whether Codex
hits the same tool-versus-resource split, whether `manage_*` action names resolve under its client,
whether the `isError: false` + `"success": false` silent-failure shape appears, and whether it
diagnoses an inactive tool group. Task 8 may ship an MCP configuration translation if the rest of the
evidence supports it, but **must mark the client-behaviour question as open rather than assuming
parity with Claude Code.** Assuming parity is exactly the move that produced four of this wave's five
silent-failure layers.

*(No scene has been touched. Nothing to record yet.)*
