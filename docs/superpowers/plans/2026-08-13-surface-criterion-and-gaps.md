# The Surface Criterion, Applied — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `.claude/skills/subagent-driven-implementation/SKILL.md` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Twenty surfaces that fail the criterion leave; the two gates worth keeping stop blocking prose; and every claim the toolkit makes about what it owns, runs, or counts is either derived or guarded.

**Architecture:** Four stages, in dependency order. Stage 1 removes surfaces, so it runs first — everything after it works against the smaller tree. Stage 2 is installer correctness, where the only permanent-damage path lives. Stage 3 is the generated block and the routing that rests on it. Stage 4 is the guards and the claims. **Stage boundaries are the natural stopping points**; the suite is green at each.

**Tech Stack:** bash 3.2-compatible shell, Markdown, TSV. `tests/run-tests.sh`, `scripts/check-provenance.sh`, `tests/fixtures/mkproject.sh`, `python3 -m tools.kinglet_build`.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-08-13-surface-criterion-and-gaps-design.md` at `3845e5a`. **Where this plan and the spec disagree, the spec wins** — report it rather than resolving it silently. The previous wave produced **seven plan bugs and two spec bugs**, every one found by an implementer who checked instead of assuming, and one was a brief whose literal instruction *was* the defect. **Read your brief adversarially.**
- **Branch:** `pioneer/surface-criterion-and-gaps`, cut from `main` at `3e4c6e5`.
- **Gates, both, before any task is reported done:** `bash tests/run-tests.sh` (timeout above **150000 ms**; currently `Total: 1022  Passed: 1022  Failed: 0` over 35 files — re-measure) and `bash scripts/check-provenance.sh`, ending `provenance OK`.
- **Strip ANSI before counting suite headers.** `grep -c '^--- test-.*\.sh ---'` on raw runner output returns **0** on a completely healthy suite — the exact signal of the catastrophe the count detects. Use `sed $'s/\x1b\\[[0-9;]*m//g'` first, then compare against `ls tests/test-*.sh | wc -l`.
- **Interactive `grep` here is a shell function wrapping `ugrep 7.5.0`; `/usr/bin/grep` is GNU 3.11.** An unescaped `$` mid-pattern is a **literal** in GNU BRE and an **anchor** in ugrep, so such a probe silently returns nothing. **Use `/usr/bin/grep` for anything you report as an absence**, and say which you used. This already produced one confident false conclusion.
- **`.claude/hooks/block-projectsettings.sh` will block your commit if the message quotes the string it matches.** Write commit messages to a file and use `git commit -F <file>`. This happened to the controller on the commit that introduced the spec describing the defect.
- **bash 3.2 compatible.** No `declare -A`, no `grep -oP`, no `$'…'` inside a parameter-expansion pattern.
- **Never pipe into a reader that can exit early** under `set -euo pipefail`. `head` and `grep -q` both exit without draining stdin; SIGPIPE + `pipefail` + `set -e` kills the script. It fires on large inputs and hides on small ones. **`grep -q` on a file argument is fine — it is the pipe that kills.**
- **`set -e` does not exempt a function after the final `&&` of an AND-list**, nor a bare `X="$(fn)"` assignment. Measured twice: a non-zero return in the wrong place kills `install.sh` **after the payload is written and before the receipt is**.
- **`[ x = y ] && continue` is a `set -e` trap** as a loop body's last command.
- **New tests are self-contained** — own `set -euo pipefail`, own `pass()`/`fail()`, `REPO` from `${BASH_SOURCE[0]}`. **Do not use the runner's `assert_*` helpers**: the runner does `set +e` before sourcing, so an undefined helper prints to stderr and contributes **no `FAIL:` token** — the test would report green on the defect it exists to catch.
- **Print `PASS:` / `FAIL:`, not `ok:`.** **No needle may carry a literal `FAIL` token** — the runner tallies on it, so one failing assertion counts twice.
- **An unanchored count needle passes for the wrong reason** — `"1 file"` also matches `11 files`.
- **A test must not fabricate its own fixture.** Measured: a state's `printf >>` created a file that was supposed to exist, measured the test's own bytes, and printed `PASS:` — masking a live spec violation. Any step that assumes a file is present must **assert** it; any step that can die must fail as an assertion instead.
- **Cite by content, not by line number**, everywhere. Two `file:line` citations in this repository have already rotted.
- **A check's silence is only as wide as what it read. Say what each probe you write cannot see.**
- **A red-first step that starts green is worse than none.** Observe the *specific* failure named; if it does not fail, **stop and report**.
- **Baseline.** `migration/baseline-inventory.json` covers `.claude/**` and `templates/` only. `.claude/hooks/` **is** under it, so stage 1 produces real drift — `--dry-run` first, **use the tool's number**, and follow **commit → regenerate → commit**. `tests/`, `scripts/` and the repo root are outside it. Entry point is the **package**: `python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift <n>`; `python3 -m tools.kinglet_build.cli` silently no-ops with exit 0.
- **Every new tracked file needs a `provenance.tsv` row** — seven tab-separated columns. **Every removed path needs a `provenance-skip.tsv` `rule=absent` row**; that is how this repository keeps a removed surface from silently returning.
- **Probe on a scratch copy:** `git archive HEAD | tar -x -C "$(mktemp -d)"`. Note `tests/test-help-ranges.sh` cannot run there — it reads `git ls-files`. Task 10 fixes that.

---

# Stage 1 — the cut

## Task 1: Twenty surfaces leave, and the counts that quote them get a guard

**Files:** delete 15 `.claude/hooks/*.sh` and 5 `scripts/*.sh`; modify `.claude/settings.json`, `provenance.tsv`, `provenance-skip.tsv`, `tests/test-derived-counts.sh`, and the five documents quoting a hook count.

**Interfaces:** produces a tree with 12 hooks and 6 repo scripts. Every later task works against it.

- [ ] **Step 1: Establish the cut list yourself, from the criterion**

The spec's **O1** names the three grounds — never runs, structurally broken, net-negative — and gives the measurements. **Re-derive the membership rather than copying a list.** For each of the 27 hooks answer: does it run under the default profile; does it work; and does it do something the model cannot do unaided.

```bash
/usr/bin/grep -rn 'HOOK_PROFILE_LEVEL=' .claude/hooks/*.sh | /usr/bin/grep strict
/usr/bin/grep -rn 'UNITY_HOOK_PROFILE' .claude/settings.json install.sh scripts/
```

The second returns nothing, which is why the first matters. **Note that `_lib.sh` itself matches the first grep** — it defines the constant. Seven hooks are strict-gated, not eight.

**If your derivation disagrees with the spec's on any surface, stop and report.** The spec's count is 15 hooks and 5 scripts; a disagreement is either a spec bug or a misreading, and both need the controller.

- [ ] **Step 2: Check each cut against what still asserts it**

This is the risk the spec names. `unity-specifics.md` states **in bold** that legacy `Input.*` is *"BLOCKED by hooks"* — so cutting `block-legacy-input.sh` would falsify a shipped claim. It is not being cut for exactly that reason; **find the others**:

```bash
for h in <each hook you plan to cut>; do
  /usr/bin/grep -rn "${h%.sh}" .claude/ docs/ README.md tests/ | /usr/bin/grep -v '^\.claude/hooks/'
done
```

Report every hit. A hook named by a shipped surface is a cut that needs a paired documentation change, not a silent deletion.

- [ ] **Step 3: Cut, re-register, record**

Delete the files. Remove their entries from `.claude/settings.json` — **verify the JSON still parses and that the count of registered hooks equals the count on disk**, which is a property nothing asserts today. Add a `rule=absent` row to `provenance-skip.tsv` for every removed path, and remove their `provenance.tsv` rows.

- [ ] **Step 4: Guard the counts before they go stale**

Five documents quote a hook count and **`tests/test-derived-counts.sh` has no hook block** (`/usr/bin/grep -c hook tests/test-derived-counts.sh` → 0). Extend its surface-pool block to hooks and to the installed script count, deriving both:

```bash
ls .claude/hooks/*.sh | /usr/bin/grep -vc '_lib'
```

**This must land in the same commit as the cut**, or the wave ships its own version of the defect it is closing — which this repository has now done three times. Then update the five quoting documents to whatever the derivation says.

- [ ] **Step 5: Gates, baseline, commit**

`.claude/hooks/` is inside the baseline inventory, so **expect real drift**. `--dry-run` first, use the tool's number, and follow commit → regenerate → commit.

---

## Task 2: The two gates block the act and permit the prose

**Files:** `.claude/hooks/bash-gate.sh`, `.claude/hooks/block-legacy-input.sh`, `tests/test-bash-gate-precision.sh`.

- [ ] **Step 1: Reproduce all nine, red**

The spec's **O1** tabulates them. Run each payload through the hook and record the exit status. **`tests/test-bash-gate-precision.sh` exists specifically for this hook and the leaks shipped anyway** — so start by reading what it does assert, and say why it did not catch these.

- [ ] **Step 2: Anchor the patterns**

`bash-gate.sh` already defines `CMD_START` and `SAME_CMD` prefixes for six of its eleven patterns. Five are substring-anywhere. Give them the prefix the file already uses. For `block-legacy-input.sh`: a left `\b` on `Input\.`, and `Editor/` and `Tests/` in the skip list.

**The trap, and it is the mirror of the defect:** an anchor that is slightly wrong turns a false positive into a false **negative**. A gate that stops blocking the act is worse than one that blocks prose.

- [ ] **Step 3: Assert both directions, for every probe**

Every row of O1's table becomes two assertions: the prose **passes**, and the act is **still blocked**. A test that only checks the prose passes would accept a gate that blocks nothing.

Include the shapes the spec measured as *permitted today and wrong*: staging everything at once, and the real editor-namespace build break. Those are `block-projectsettings.sh` and `guard-editor-runtime.sh` — **both on the cut list**, so decide and report whether their true-positive behaviour needs to survive anywhere.

- [ ] **Step 4: Gates, baseline (`.claude/hooks/` drifts), commit**

---

## Task 3: The surviving scripts become reachable

**Amended after Task 1 (2026-08-13).** This section was written before the cut and every figure in it
was pre-cut. The heading said *"The five surviving scripts"*; there are six installed. Its **Files**
line named only the two commands below; Task 1's controller ruling restored
`scripts/detect-missing-refs.sh`, which is referenced by nothing and whose wiring is **this task's**.
The figures below are left as written, marked, because what they were is the point — a plan that
quotes a count is the defect this wave exists to close, and replacing a stale count with a fresher one
repeats it rather than fixing it.

**Files:** `.claude/commands/unity-doctor.md`, `.claude/commands/unity-init.md`, and whichever agent or command should name the rest — **including a home for `detect-missing-refs.sh`**.

- [ ] **Step 1: Derive what is reachable today — do not read the figures below**

```bash
/usr/bin/grep -rn 'scripts/' .claude/
```

~~Three references from shipped surfaces, naming two scripts. **Eight of ten installed scripts are named by nothing that ships.**~~ *(pre-cut, superseded — derive it.)* `studio-doctor.sh` is pointed at humans from four places and reachable from no agent, command or skill — while `/unity-doctor.md` **re-implements its checks by hand**. That much is unchanged by the cut; verify it anyway.

Count the installed set (`.claude/scripts/`, not the repo's `scripts/`), count how many are named by a shipped surface, and state both. Task 1's re-review measured one shipped surface naming one installed script — treat that as a figure to reproduce, not to cite.

- [ ] **Step 2: Wire them, and delete the duplication**

`/unity-doctor` runs `studio-doctor.sh` rather than re-deriving it. Decide where `validate-serialization.sh` and `validate-asmdefs.sh` belong — both do something a model does not do unaided (git-history field-rename diffing; transitive-closure cycle detection) and neither is currently invocable.

**A path that does not resolve in an installed project is the defect the previous wave spent a whole pass on.** These live at `.claude/scripts/<name>` once installed, not at `scripts/<name>`. Verify against a real install, not against the repo.

- [ ] **Step 3: Gates, commit.** `.claude/commands/` is inside the baseline inventory.

---

# Stage 2 — installer correctness

## Task 4: The receipt exists before anything that can abort

**Files:** `install.sh`, `tests/test-install-ownership.sh`.

- [ ] **Step 1: Reproduce the permanent-damage path**

```bash
ln -s /nonexistent "$PROJECT/Packages/manifest.json.bak"
bash install.sh --project-dir "$PROJECT" --with-mcp --yes
```

Expected today: `cp: not writing through dangling symlink`, **rc=1, 86 files under `.claude/`, no receipt**, and `uninstall.sh` printing *"Refusing to guess which files are ours."* `[ -e ]` is false through a dangling link, so D11's guard does not fire.

- [ ] **Step 2: Add the states, red**

| state | expectation |
|---|---|
| dangling symlink at the `.bak` path, `--with-mcp` | the run leaves a receipt; `uninstall.sh` cleans the project |
| `--variant bare`, no `.gitignore` beforehand | `.gitignore` is created **and has a receipt row**; uninstall removes it |
| a receipt row whose origin column is unreadable, for `MCP-SETUP.md`, across an upgrade | the row is **not** dropped |

- [ ] **Step 3: Move the receipt, do not patch the symptom**

The fix is where the receipt is committed, not a `[ -L ]` test bolted onto one `cp`. Write the receipt for what has been installed **before** the step that can abort, or trap and finish it on failure. **Then the two lesser members close for free** — verify that they do rather than assuming it:

- `.gitignore` created-and-unrecorded;
- `MANIFEST_BAK_KEPT` outliving the file it names (the failure arm's `mv` deletes the backup while the flag stays `1`, and `sha_of` inside a `printf` argument — where `set -e` does not reach — writes a row with an **empty checksum**).

Also in scope: `owned_by_installer`'s `$4 == "toolkit"` gate drops a root file's ownership row forever on an unreadable origin column, and `.mcp.json`'s reference copy is a heredoc written to `mktemp`, so **that arm short-circuits every run and the receipt is never consulted for that file**. A constant reference copy can mask a receipt problem indefinitely.

- [ ] **Step 4: Prove it did not become "always write a receipt"**

A `foreign` install — one where the receipt's absence is what defines the mode — must still behave as it does today. Mutation-prove it.

- [ ] **Step 5: Gates, commit.** `install.sh` is outside the baseline inventory; confirm zero drift.

---

## Task 5: A run that abandons work says so, and something asserts it

**Files:** `install.sh`, `tests/test-install-dryrun.sh` or a new guard, plus one shipped document for the exit contract.

- [ ] **Step 1: Reproduce the two that do not reach `Not done:`**

`--variant bare` + `--with-mcp` → `warn No Packages/manifest.json — skipping --with-mcp.` … `Installation complete.`, **rc=0, no `Not done:`**. A manifest with no `"dependencies"` key → `warn Could not edit manifest.json safely` … same. `gitignore_plan`'s `*)` fallback is a third.

- [ ] **Step 2: One recording point for all four**

The `MANIFEST_DECLINED` mechanism already exists. Route the others through it — and note the fallback does not name its consequence (`.claude/settings.local.json` and `.claude/state/*` are then not gitignored).

- [ ] **Step 3: Decide and write down the exit contract**

`/usr/bin/grep -n 'exit status\|exit code' README.md docs/GETTING-STARTED.md MCP-SETUP.md` is **empty**. All four outcomes exit 0, so a scripted `install.sh --with-mcp && start_unity` proceeds as though the package landed.

**The controller is not deciding this for you.** The previous wave measured that a non-zero return from `add_manifest_dependency` kills the installer before the receipt; that is an argument about *where* the status is raised, not about whether the contract should exist. Decide, implement, document it in a shipped file, and **say what a caller can now rely on.**

- [ ] **Step 4: Assert the block**

`/usr/bin/grep -rn 'Not done' tests/` is **empty**. The dry-run guard cannot reach it — all three of its oracles are silent on a run that writes nothing, which is the same blindness D4 was written to correct. Decide where the assertion lives and say why.

- [ ] **Step 5: Gates, commit**

---

## Task 6: A reverted file stops being sticky, and the doctor stops repeating the claim

**Files:** `install.sh`, `scripts/studio-doctor.sh`, `tests/test-install-ownership.sh`.

- [ ] **Step 1: Reproduce the trap and the control**

Install → edit → install → **revert to the toolkit's exact bytes** → install. Expected today: `keeping yours` about a file with no local edits, row still `user-modified` carrying the toolkit's own sha. Then simulate a toolkit v2 by changing the shipped file: the project does **not** receive it; a control project that never touched the file does.

And `studio-doctor.sh` reports `1 file(s) modified since install` about a file byte-identical to the toolkit's — **it classifies by the column alone, never comparing bytes.**

- [ ] **Step 2: Compare against the toolkit's copy, not the recorded sha**

Drop the sticky flag only on an exact match with `$SCRIPT_DIR`'s shipped copy. **This is a different comparison from the one that failed in `c2d27f1f`** — that was against the *recorded* sha, and an edited file never equals the toolkit's bytes.

Root-level rows (`.mcp.json`, `MCP-SETUP.md`, `CLAUDE.md.generated`) have no static reference copy and stay sticky. **Say so in the report** rather than leaving it to be discovered.

- [ ] **Step 3: The regression check that decides it**

Edit, then **three consecutive installs**. The edit must survive all three. If it does not, stop — you have reintroduced `c2d27f1f`.

- [ ] **Step 4: Fix the doctor in the same commit**

`studio-doctor.sh`'s own comments reason at length about its readers agreeing. Shipping an installer that unsticks while the doctor still classifies by column alone recreates exactly the drift those comments were written to prevent.

- [ ] **Step 5: Gates, baseline (`scripts/` is outside it — confirm zero), commit**

---

# Stage 3 — the generated block, and what rests on it

## Task 7: `/unity-init` names the generator, and the markers become a contract

**Files:** `.claude/commands/unity-init.md`, and at least one shipped surface for the marker contract.

- [ ] **Step 1: Establish the gap**

```bash
/usr/bin/grep -n 'generate-claude-md' .claude/commands/unity-init.md
/usr/bin/grep -rn 'generated:begin' .claude/ docs/ README.md
```

The first is empty. The second finds the markers **only in historical plans** — no shipped surface knows they exist. Then count what depends on the region: `/usr/bin/grep -rln 'generated block' .claude/`.

- [ ] **Step 2: Call the generator, state the contract**

`/unity-init` invokes `.claude/scripts/generate-claude-md.sh` rather than re-deriving the block by hand. **Check the invocation resolves in an installed project** — the script lives at `.claude/scripts/` there, and this repository has shipped a path that resolved only in the repo before.

State the contract where a model will read it: the region between the markers is regenerated in place, everything outside is the user's, and a re-install rewrites it.

- [ ] **Step 3: Prove the two producers agree**

Run `/unity-init`'s path and `install.sh`'s path against the same fixture and compare the block byte-for-byte. **Two producers of one region is the defect the previous wave spent a task removing** from `.gitignore`; if they disagree, that is the finding, not a nuisance.

- [ ] **Step 4: Gates, baseline (`.claude/commands/` drifts), commit**

---

## Task 8: `/unity-ui` and `/unity-scene` stop reading as entry points

**Files:** `.claude/skills/using-kinglet/SKILL.md`, `.claude/commands/unity-ui.md`, `.claude/commands/unity-scene.md`, `docs/GETTING-STARTED.md`.

- [ ] **Step 1: Establish the bypass**

`/unity-ui` dispatches `unity-ui-builder`, which holds `mcp__UnityMCP__*`. Check whether either builder agent gates on an approved design:

```bash
/usr/bin/grep -n 'brainstorm\|design.md\|HARD-GATE\|approved' .claude/agents/unity-ui-builder.md .claude/agents/unity-scene-builder.md
```

Expected: no match. So taking row 11 writes C# and makes MCP write calls with no approved design.

- [ ] **Step 2: Reword the row, and make it true where it bites**

Row 11 becomes the *execution step* it actually is — a UI screen or scene **whose design is already approved**. **This adds no exemption**, which matters: `unity-brainstorming` explicitly refuses to keep a list of them.

Then the command-side half: `/unity-ui.md` opens with the precondition, stated as a **precondition** and not a "Suggest next". `/unity-scene.md` already half-has it, as an after-the-fact offer once the scene is built.

- [ ] **Step 3: Fix the document that already ruled, and the table that contradicts it**

`docs/GETTING-STARTED.md` rules that row 2 wins — and two lines above, a Common First Commands table lists `/unity-scene`. Make them agree.

- [ ] **Step 4: Record the second exemption**

Row 4 routes a handed-over plan straight to `unity-planning`, skipping row 2 — a second de-facto exemption, undeclared. **Report it; do not add it to a list.** The skill's refusal-to-list is the reason it is worth naming out loud.

- [ ] **Step 5: Gates, baseline, commit**

---

## Task 9: The Ambiguity Score says what it does not know

**Files:** `.claude/skills/unity-brainstorming/SKILL.md`.

- [ ] **Step 1: Reproduce the leak on the skill's own example**

Score *"Add multiplayer to my game"* by the file's rubric, twice: with and without a generated block that reports a Unity version, URP and a networking package. The file scores it **3/10**. With the block, Platform goes 0 → 2 and Integration 1 → 2: **6/10, exactly the threshold.**

- [ ] **Step 2: Add a new section — and it must be new**

`tests/test-surface-references.sh` freezes **six named sections of this skill character-for-character**, and `ub_section` stops at the next `#{1,3}` heading, so **a new heading is invisible to every frozen comparison; editing an existing one is not.** Confirm that yourself before writing.

The content is one argument: a fact supplied by the generated block is context for *answering* a dimension, never points, because **a constant cannot discriminate between requests**. Restate that the score gates depth, not whether the round happens.

- [ ] **Step 3: Prove you did not disturb the frozen prose**

Run `tests/test-surface-references.sh` and confirm the six comparisons still pass. If one fails, you edited a frozen section — and `provenance.tsv` records this file `origin=ecu` on the specific ground that ECU's score survived, so that is a provenance question, not a formatting one.

- [ ] **Step 4: Gates, baseline, commit**

---

# Stage 4 — guards and claims

## Task 10: Six guards see the class

**Files:** `tests/test-help-ranges.sh`, `tests/test-studio-doctor.sh`, `tests/test-skill-discovery.sh`, `tests/test-surface-references.sh`, `tests/run-tests.sh`.

- [ ] **Step 1: The two that cannot run under the documented probe method**

`tests/test-help-ranges.sh` derives its file set from `git ls-files`, so a `git archive HEAD | tar -x` extraction makes it die `rc=128` asserting nothing. `tests/test-pipeline-detector.sh` faced the same dependency and grew explicit no-index arms — **copy that shape**, and check whether it too still dies.

- [ ] **Step 2: The symmetric fixture, and the unasserted sentences**

`tests/test-studio-doctor.sh`'s long-list fixture makes both counters `1500`, so the block cannot tell its two lists apart — swapping the doctor's counters leaves both assertions green. Make it `N` and `N+k`, and **prove the swap now reddens.**

The doctor's two unreadable-origin continuation `warn` lines are asserted by nothing. Two fix rounds worked to make those sentences true; deleting them is currently invisible.

- [ ] **Step 3: The frontmatter fence and the red-flag bodies**

`tests/test-skill-discovery.sh` reads only a `name:` line and a `description:` line, so **the closing `---` fence is unguarded across all 16 skills** and a skill can carry a third key with the suite green. And the red-flag assertion is existence-only for `systematic-debugging` and `verification-before-completion` — both bodies can be gutted green, and it is their **only** coverage.

- [ ] **Step 4: The runner's python blindness**

1443 python results across two files contribute **1** to the total, and one of the two emits no `PASS` line at all. Give the runner a granularity that distinguishes them. **`CLAUDE.md` forbids hardcoding the expected total**, so the fix is not writing a number down.

- [ ] **Step 5: Mutation-prove each, then gates and commit**

Every guard you touch: break the thing it now claims to check and confirm **that specific assertion** reddens. Report which other assertions reddened — a mutation that reddens everything has isolated nothing.

---

## Task 11: Claims are re-derived or removed

**Files:** `docs/HOOK-REFERENCE.md`, `docs/GETTING-STARTED.md`, `.claude/UPSTREAM`, `.claude/skills/unity-planning/SKILL.md`, `tests/test-derived-counts.sh`, and the citation sites.

- [ ] **Step 1: The citations that have already rotted**

```bash
/usr/bin/grep -rhoE '[A-Za-z0-9_./-]+\.(sh|md|tsv|json):[0-9]+' tests/*.sh docs/*.md | sort -u
```

Fifteen citations; **at least two are wrong** — one cites a line that is now blank, another a line that is now a section banner. Fix them, then **guard the class**: a check that resolves each citation and fails when it does not. Say what that guard cannot see — a rename breaks a content anchor as silently as an insertion breaks a number.

- [ ] **Step 2: `HOOK-REFERENCE.md` states two things that are false**

It says twice that **all hooks source `_lib.sh`** — `session-brief.sh` does not, which makes it the only hook honouring no kill switch. And it says the standard profile includes **18** hooks; the measurement is different. Derive both.

Decide whether `session-brief.sh` should gain the kill switch or the document should record the exception. **It is the hook that seeds `using-kinglet` into every session**, so the answer is not obvious — say which you chose and why.

- [ ] **Step 3: `.claude/UPSTREAM` names four files that do not exist in an installed project**

Verify against a real install, not the repo.

- [ ] **Step 4: `unity-planning` states no threshold**

It owns the execution fork and labels one branch "(recommended)" unconditionally, while `unity-execution` and `subagent-driven-implementation` both carry the same threshold verbatim. Make the three agree.

- [ ] **Step 5: The five derived counts, guarded**

`docs/GETTING-STARTED.md`'s five counts have no guard, and Task 1 added the hook block. Extend the derivation to the rest rather than correcting the numbers by hand.

- [ ] **Step 6: Gates, commit**

---

## Task 12: The early-exit-reader trap leaves the shipped scripts

**Files:** `scripts/generate-claude-md.sh`, `scripts/detect-missing-refs.sh`, `scripts/validate-asmdefs.sh`, `tests/test-bash32-compat.sh`, and the five `stat -c` sites in `install.sh`.

- [ ] **Step 1: Establish which of the survivors carry it**

```bash
/usr/bin/grep -n 'head -1\|| *grep -q' scripts/*.sh
```

`generate-claude-md.sh` has `name=$(sed -n '…' "$asmdef" 2>/dev/null | head -1)` — a bare assignment under `set -euo pipefail` with **no `|| true`**, the exact shape that killed `studio-doctor.sh` at 29 of 30 runs. `validate-architecture.sh`'s many `| head -1` are **safe** — each ends `|| true` inside the substitution. Check each rather than assuming.

- [ ] **Step 2: Fix, and widen the sweep that missed them**

`tests/test-bash32-compat.sh`'s `PIPE_CHECK_DIRS` excludes `scripts/` on a recorded ground that names one of these files as the accepted exception. That judgement was made before the current set of scripts existed and nothing re-runs it. **Bring `scripts/` into the sweep** or record why not, deriving the file set rather than listing it.

- [ ] **Step 3: `stat -c '%a'` at five sites**

GNU-only; on BSD the row records `644` for a `600` file. Nothing reads the mode column, so the consequence is cosmetic — **move all five together** or none, and say which.

- [ ] **Step 4: Gates, commit**

---

## Self-Review

**Spec coverage.** O1 → Task 1. O2 → Task 2. O3 → Task 3. D2 → Task 4. D3 → Task 5. O4 → Task 6. D1 → Task 7. O5 → Task 8. O6 → Task 9. D4 → Task 10. D5 → Tasks 1, 11. D6 → Task 12. Acceptance criteria 1–15 are checked at each stage boundary and re-run whole at the end.

**Placeholder scan.** Five places delegate judgement deliberately and say so: Task 5 Step 3's exit contract, Task 5 Step 4's assertion location, Task 6 Step 2's root-level rows, Task 11 Step 2's kill-switch choice, and Task 12 Step 3's five sites. Each names what the implementer must report.

**Ordering.** Stage 1 first because it shrinks the tree everything else works against; Task 2 after Task 1 because two of its probe subjects are on the cut list; Task 11's count guard depends on Task 1's hook block existing.

**One gap found and closed while reviewing:** Task 2's probes include two hooks that Task 1 deletes, so Step 3 now asks explicitly whether their true-positive behaviour needs to survive anywhere — otherwise the wave cuts a gate and silently drops the protection with it.
