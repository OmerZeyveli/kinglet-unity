# The Surface Criterion, Applied — and the Gaps Three Waves Left

*2026-08-13. Branch: `pioneer/surface-criterion-and-gaps`, cut from `main` at `3e4c6e5`. Scoped by the
owner as "close all of it, then try it on a real project". Four decisions that had been parked as the
owner's were put to them with measurements and recommendations, and all four were approved; they are
recorded below as settled rather than argued.*

## The problem, measured

Three waves closed between 2026-08-10 and 2026-08-13 and left **45 distinct open items** across their
three ledgers. An inventory built against the finished tree found that **16 of the recorded items were
already closed** by later tasks without their entries being updated, and **5 were moot** — so the
ledgers, read literally, would have sent an implementer to reopen closed work in twenty-one places.

That is this wave's first fact about itself: **a finding record that is not re-verified against the
tree is a to-do list with a twenty-one-item error rate.**

The 45 survivors are not one defect. They are five shapes plus four decisions:

1. **The installer writes things the receipt does not cover** — and one of them leaves a project
   `uninstall.sh` permanently refuses to touch.
2. **A run ends green about work it abandoned.**
3. **Guards narrower than the thing they certify** — including two that cannot run under the probe
   method this repository documents.
4. **Claims nothing re-derives** — counts, citations, and prose that was true when written.
5. **Portability items** for the planned macOS pass, including the early-exit-reader trap surviving in
   a script that ships.

### The thing that is worse than any of the five

`/unity-init` is the surface whose entire job is producing `CLAUDE.md`'s generated block. **It never
names `scripts/generate-claude-md.sh`.** Its steps tell a model to scan the project over MCP and write
the block by hand.

And **no shipped surface anywhere mentions the `kinglet:generated:begin` / `end` markers** —
`/usr/bin/grep -rn 'generated:begin' .claude/ docs/ README.md` finds them only in historical plans. So a
model running `/unity-init` can silently overwrite a marker-delimited region that **three skills, all
eight agents and eight commands cite by name**, with no marker discipline and no awareness that a
re-install rewrites that region in place.

Sixteen surfaces rest on that block. `architecture.md`'s *"detected, not assumed"* clause rests on it.
The Ambiguity Score reads it. It is the toolkit's single most-cited artifact and the surface that
produces it does not know how it is made.

## The four owner decisions, settled

Each was put to the owner with the measurement, the real options, and a recommendation. All four
recommendations were approved.

### O1 — The surface criterion applies to hooks and `scripts/`, and it removes 20 of 37

The 2026-08-03 cut asked of every agent, command and skill: **"does it do something the model cannot do
unaided?"** Hooks and `scripts/` were out of scope for that wave and every one survived untouched.

Applied now, the criterion is not close on 15 of the 27 hooks and 5 of the 10 installed scripts.

**Seven hooks never run.** `_lib.sh` reads `_ACTIVE_PROFILE="${UNITY_HOOK_PROFILE:-standard}"` and exits
0 when a hook's declared level exceeds it. **`UNITY_HOOK_PROFILE` is set nowhere** — not in
`settings.json`, not in `install.sh`, not in `scripts/`. `HOOK-REFERENCE.md` labels those seven
"Profile: strict" and **never says the default leaves them dead**. Several of them write state files
whose only readers are also strict-gated: a closed loop that does nothing and cannot be observed doing
nothing. One of them, `auto-learn`, writes a log that `session-restore.sh` deletes every session.

**Three are structurally broken**, independent of any style judgement:

- `suggest-verify.sh` uses BSD `stat -f %m`; on GNU that is `--file-system`, so the arithmetic gets a
  filesystem dump and bash dies under `set -u`. Measured: call 1 exits 0, **calls 2 and 3 exit 1 with
  `line 30: File: unbound variable`**. It emits a bash error on every C# edit after the first, on the
  only host `.claude/UPSTREAM` claims the toolkit ships.
- `build-analyze.sh` reads `.tool_output.stdout` — a field that appears nowhere else in the repository
  and does not exist in the event payload. It analyses an empty string, and is strict-gated on top.
- `validate-commit.sh` is registered **PostToolUse**, so `git diff --cached` is empty by the time it
  runs; all three of its loops iterate zero times. Its own header says it runs "before git commit".

**And two gates block the discussion while permitting the act.** Measured, payloads run through each
hook, exit 2 = blocked:

| probe | result |
|---|---|
| `echo "never run git reset --hard here"` | **BLOCKED** |
| `git commit -m "docs: warn about git reset --hard"` | **BLOCKED** |
| `grep -rn 'PlayerPrefs.DeleteAll' Assets/` | **BLOCKED** |
| `find Assets -name "*.meta" \| wc -l` | **BLOCKED** as meta-deletion |
| `echo "never git add ProjectSettings/ by hand"` | **BLOCKED** |
| **`git add -A`** — what actually stages it | **allowed** |
| a comment mentioning `using UnityEditor` | **BLOCKED** |
| **the real build break** (`using UnityEditor;` + an unrelated `#if UNITY_EDITOR`) | **allowed** |
| `GetComponent` cached in `Awake` + an `Update` | **WARNS** — the pattern `performance.md` mandates |

The analyst auditing these was itself blocked **twice in one session, unprompted, on read-only
commands**. A gate that fires on a false positive is worse than no gate, because the available
workaround is to reword the prose until the gate stops matching — which teaches quieting a guard by
editing the text around it.

**Ruling: cut the 15 hooks and 5 scripts.** 2765 lines. `provenance-skip.tsv` records every removed
path as `rule=absent`, which is how this repository keeps a removed surface from silently returning.

### O2 — `bash-gate.sh` and `block-legacy-input.sh` are fixed, not cut

Both **mechanisms** pass the criterion cleanly — interposing a hard stop between intent and an
irreversible command is something no rule can do, and `block-legacy-input` is the only thing making
`unity-specifics.md`'s bolded *"legacy `Input.*` is **BLOCKED** by hooks"* true. Their **patterns** do
not pass. Five of `bash-gate`'s eleven are substring-anywhere; the file already defines `CMD_START` and
`SAME_CMD` prefixes for the other six.

`tests/test-bash-gate-precision.sh` exists **specifically** for this hook and the leaks shipped anyway.
The fix is not complete until that file carries the probes above.

### O3 — The five surviving scripts are wired, not deleted

`studio-doctor.sh`, `generate-claude-md.sh`, `detect-pipeline.sh`, `validate-serialization.sh` and
`validate-asmdefs.sh` pass the criterion on merit — the last two do transitive-closure cycle detection
over a JSON graph and diff field names against **git history** to find renames missing
`[FormerlySerializedAs]`, neither of which a model does unaided in the normal course.

But `/usr/bin/grep -rn 'scripts/' .claude/` returns **three references from shipped surfaces**, naming
two scripts. **Eight of ten installed scripts are named by nothing that ships.** `studio-doctor.sh` is
pointed at humans from four places and reachable from **no** agent, command or skill — while
`/unity-doctor.md` re-implements its checks by hand.

That is a wiring defect, not a deletion case.

### O4 — The sticky `user-modified` inference is corrected; the trade is kept

Reproduced end to end: install → edit → install → **revert to the toolkit's exact bytes** → install →
the run still prints `keeping yours` about a file with no local edits, the row stays `user-modified`
carrying the *toolkit's own* sha, and **a toolkit v2 shipping new bytes for that file never reaches the
project** while a control project that never touched it does receive v2.

**And the one diagnostic that should catch it repeats the claim**: `studio-doctor.sh` classifies
`user-modified` rows by the column alone, never comparing bytes, and reports `1 file(s) modified since
install` about a file byte-identical to the toolkit's.

What changes is not the stickiness but the **inference**. Today the installer infers "this file is
yours" from a column when the bytes are available and say otherwise. The fix compares against the
**toolkit's shipped copy** and drops the flag only on an exact match.

**This does not reintroduce `c2d27f1f`**, and that was measured rather than argued: `c2d27f1f`'s defect
was a comparison against the **recorded sha**; this is a comparison against the **toolkit's bytes**, and
an edited file never equals those. Three consecutive installs after an edit keep the edit every time.

### O5 — `/unity-ui` and `/unity-scene` are execution steps, not entry points

`using-kinglet`'s chain table routes *"Anything to build"* to `unity-brainstorming` and *"A UI screen,
or a scene to build"* to `/unity-ui` / `/unity-scene`. **A UI screen is both**, and nothing says which
row wins.

The stake is the HARD-GATE. `/unity-ui` dispatches `unity-ui-builder`, which holds
`mcp__UnityMCP__*`, and **neither builder agent gates on an approved design**. `/unity-ui.md` contains
zero references to brainstorming or a design. So taking that row writes C# and makes MCP write calls
with no approved design — straight through the gate `unity-brainstorming` exists to hold.

`docs/GETTING-STARTED.md` already rules that row 2 wins — in a document a model never loads,
contradicted two lines above by a Common First Commands table listing `/unity-scene`, and asserted by
no test.

**The row is not ambiguous because the table is silent on precedence. It is ambiguous because the row is
written as though `/unity-ui` were an entry point, and it is not.** Rewording it adds no exemption,
which matters: `unity-brainstorming` explicitly refuses to keep a *list* of exemptions, and a second
undeclared one has already crept in — row 4 routes a handed-over plan straight to `unity-planning`,
skipping row 2.

**Nine of the twelve rows sit in at least one unresolved double-match cluster.** Only this one has a
consequence beyond a recoverable wrong first step.

### O6 — The Ambiguity Score is left alone, and told what it does not know

The score is five dimensions × 0–2, threshold ≥ 6 — and the skill says outright that it **sets the
depth of the round, not whether the round happens**. The HARD-GATE, the design artifact and the approval
are all unconditional and sit outside it.

But in any `/unity-init`'d project the **Platform** dimension scores 2 for every request, from context,
regardless of what the user said — the generated block answers it in full. The file's own canonical
"too vague to proceed" example scores 3/10 in the file and **6/10 — exactly the threshold — in an
initialised project**. A dimension that scores 2 for every request carries zero discriminating
information while consuming 2 of the 10 points and 2 of the 6 required.

**Calibration would validate the leak rather than close it**, and any threshold it produced would still
be wrong for the other arm. The fix is one new section stating the argument: *a fact supplied by the
generated block is context for answering a dimension, never points, because a constant cannot
discriminate between requests.* That survives any change to the block's content; a tuned number does not.

**Cost note that decides the shape:** `tests/test-surface-references.sh` freezes six named sections of
this skill character-for-character, and `provenance.tsv` records it `origin=ecu` on the specific ground
that ECU's score survived — the scale, the five dimensions, the threshold, the protocol and both
examples. A **new** `###` section is invisible to every frozen comparison; editing an existing one is
not. The recommendation is the cheap shape *and* the right one, which is why it was taken.

## Decisions

### D1 — `/unity-init` names the generator, and the markers become a shipped contract

`/unity-init` calls `scripts/generate-claude-md.sh` (installed at `.claude/scripts/`) rather than
re-deriving the block by hand, and at least one shipped surface states the marker contract: the region
between `kinglet:generated:begin` and `end` is regenerated in place, everything outside it is the
user's, and a re-install rewrites it.

**Rejected: leaving `/unity-init` to derive it by hand and only documenting the markers.** The
generator already exists, already handles the four pipeline states and the `manifest-only` fallback, and
is already what `install.sh` runs. Two producers of one region is the defect this wave's predecessor
spent a task removing from `.gitignore`.

### D2 — The receipt covers everything the installer keeps

Every write passes through one recording point, and **the receipt exists before any step that can
abort**. Today a dangling symlink at `Packages/manifest.json.bak` makes `[ -e ]` false, the D11 guard
does not fire, `cp` dies, and the run ends **rc=1 with 86 files installed and no receipt** — a project
`uninstall.sh` refuses to touch, permanently.

Closing that structurally closes the two lesser members: `.gitignore` created-and-unrecorded, and
`MANIFEST_BAK_KEPT` outliving the file it names (the failure arm deletes the backup while the flag stays
`1`, and `sha_of` inside a `printf` argument — where `set -e` does not reach — writes a row with an
empty checksum).

Also in this decision: `owned_by_installer`'s `$4 == "toolkit"` gate drops a root file's ownership row
forever on an unreadable origin column, and `.mcp.json`'s reference copy is a heredoc written to
`mktemp`, so that arm short-circuits on every run and **the receipt is never consulted for that file**.
A constant reference copy can mask a receipt problem indefinitely.

### D3 — A run that abandons work says so where the run ends, and something asserts it

All four flag-abandonment outcomes route through one recording point. Two of them — `No
Packages/manifest.json — skipping` and `Could not edit manifest.json safely` — currently print a `warn` a
dozen lines above the green banner and produce **no `Not done:` block**. `gitignore_plan`'s fallback is a
third, and it does not name its consequence (`.claude/settings.local.json` and `.claude/state/*` are then
not gitignored).

**The exit contract is decided and written down.** All four outcomes exit 0 today and **no document
states any exit contract** — `/usr/bin/grep -n 'exit status\|exit code' README.md docs/GETTING-STARTED.md
MCP-SETUP.md` is empty. A scripted `install.sh --with-mcp && start_unity` proceeds as though the package
landed.

**And `Not done:` gains an assertion.** `/usr/bin/grep -rn 'Not done' tests/` is empty. It is the newest
user-facing output the previous wave produced and the dry-run guard is structurally blind to it — all
three of its oracles are silent on a run that writes nothing.

### D4 — Guards see the class, not the symptom

Six guards are narrower than their subject in ways that were measured, not supposed:

- **Two cannot run under this repository's own documented probe method.** `tests/test-help-ranges.sh`
  derives its file set from `git ls-files`, so a `git archive HEAD | tar -x` extraction — the method
  `CLAUDE.md` and every dispatch prescribe — makes it die `rc=128` asserting nothing.
  `tests/test-pipeline-detector.sh` faced the same dependency and grew explicit no-index arms; this one
  did not.
- **The `studio-doctor` long-list fixture is symmetric**, so the block cannot tell its two lists apart —
  swapping the doctor's counters leaves both assertions green.
- **The doctor's two unreadable-origin continuation lines are asserted by nothing**, so deleting the
  sentences two fix rounds worked to make true is invisible.
- **The closing `---` frontmatter fence is unguarded across all 16 skills**, and `test-skill-discovery.sh`
  reads only a `name:` line and a `description:` line — a skill can carry a third key or an unparseable
  block with the suite green.
- **The red-flag assertion is existence-only** for `systematic-debugging` and
  `verification-before-completion`; both bodies can be gutted green, and it is their only coverage.
- **The runner is blind to python results in both directions.** 1443 python results across two files
  contribute **1** to the total, and one of the two files emits no `PASS` line at all.

### D5 — Claims are re-derived or removed

**Two `file:line` citations have already rotted** — one cites a line that is now blank, another a line
that is now a section banner. Fifteen such citations exist across `tests/` and `docs/` and nothing
resolves any of them.

Five derived counts in `docs/GETTING-STARTED.md` and the "27 hooks" figure in five places are unguarded
prose, and **`tests/test-derived-counts.sh` has no hook block at all** — which is how the previous wave's
own lesson (a pool whose *composition* changed while its total did not) applies here.

`HOOK-REFERENCE.md` states twice that **all hooks source `_lib.sh`**; `session-brief.sh` does not, which
makes it the only hook that honours no kill switch. The same document says the standard profile includes
18 hooks; the measurement is 20.

`.claude/UPSTREAM` ships and names four files that do not exist in an installed project.

`unity-planning` — the surface that owns the execution fork — states no threshold and labels one branch
"(recommended)" unconditionally, while both other skills in the chain carry the same threshold verbatim.

### D6 — The early-exit-reader trap leaves the shipped scripts

`scripts/generate-claude-md.sh` carries `name=$(sed -n '…' "$asmdef" 2>/dev/null | head -1)` — a bare
assignment under `set -euo pipefail` with **no `|| true`** — the exact shape that killed
`studio-doctor.sh` at 29 of 30 runs. `detect-missing-refs.sh` and `validate-asmdefs.sh` carry several
`echo "$x" | grep -q …`. All three install into `.claude/scripts/`.

`stat -c '%a'` is GNU-only at five sites. Nothing reads the mode column, so the consequence is cosmetic —
but the macOS pass is planned and the five sites should move together.

## Acceptance criteria

1. `bash tests/run-tests.sh` green, ANSI-stripped header count equal to `ls tests/test-*.sh | wc -l`.
2. `bash scripts/check-provenance.sh` ends `provenance OK`, with a row for every added file and a
   `rule=absent` entry in `provenance-skip.tsv` for every removed one.
3. **Every removed surface stays removed** — proven by the offline half of the provenance check, not by
   inspection.
4. **`bash-gate.sh` blocks the act and permits the prose**, proven on all nine probes tabulated in O1,
   with `tests/test-bash-gate-precision.sh` carrying them. Same for `block-legacy-input.sh` on its four.
5. **A `--with-mcp` install over a dangling symlink at `Packages/manifest.json.bak` leaves a receipt**,
   and `uninstall.sh` cleans the project.
6. **`.gitignore`, when the installer creates it, has a receipt row** and `uninstall.sh` removes it.
7. **A reverted file loses its `user-modified` marking**, receives a toolkit v2, and `studio-doctor.sh`
   stops reporting it as modified — while an **edited** file survives three consecutive installs.
8. **All four flag-abandonment outcomes reach `Not done:`**, an assertion covers that block, and the exit
   contract is stated in a shipped document.
9. **`/unity-init` names the generator**, and the marker contract is stated on a shipped surface.
10. **`tests/test-help-ranges.sh` asserts under `git archive` extraction** or fails loudly by name.
11. **The closing `---` fence and both red-flag bodies are asserted** across all skills.
12. **The runner reports python results** with a granularity that distinguishes 1443 from 1.
13. **Every `file:line` citation in `tests/` and `docs/` resolves**, guarded.
14. **Every derived count is derived or guarded** — including hooks, which have no block today.
15. **No pipe into an early-exiting reader survives in a shipped script**, proven by the bash-3.2 sweep
    covering `scripts/`.

## Out of scope, recorded

- **The macOS host pass itself.** `stat -c` and the awk interval move together here; the pass is separate.
- **The remaining eight double-match clusters** in `using-kinglet`'s table. Only O5's has a consequence
  beyond a recoverable wrong first step; the rest are recorded for a table restructure that is its own
  piece of work.
- **Restructuring the chain table** (the analyst's option C) — best long-term shape, largest single edit,
  and it still needs O5's command-side change to make the gate real.
- **`tests/` as a sweep root** for the pipeline detector. A future test computing its expected verdict by
  grepping the manifest would be a second implementation in a directory nothing sweeps; today's avoidance
  is a convention.
- **Whether the toolkit behaves correctly inside Claude Code.** Nothing in this wave touches that. It is
  the next thing after it, on a real project.

## Risks

**The cut is the risk.** Twenty surfaces leave, and the argument for each is that it is dead, broken, or
net-negative — measured. Three failure modes to guard specifically:

- **A cut hook was load-bearing for a claim elsewhere.** `block-legacy-input` is the worked example of
  why: `unity-specifics.md` states in bold that legacy input is *blocked by hooks*. Every cut must be
  checked against what still asserts it, and `provenance-skip.tsv` is where the ruling is recorded.
- **The five quoted "27 hooks" go stale silently.** No test derives a hook count. Extending
  `tests/test-derived-counts.sh` to hooks belongs in the **same** wave as the cut, or the wave ships its
  own version of the defect it is closing — which this repository has now done three times.
- **A gate fix makes the gate permissive.** `bash-gate`'s patterns are being anchored, and an anchor that
  is slightly wrong turns a false positive into a false negative. Every probe in O1's table must be
  asserted in both directions: the prose passes **and** the act is still blocked.
