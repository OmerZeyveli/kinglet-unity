# Process Layer, Second Pass — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the seven MCP agents able to call MCP, give every skill the failure modes it currently omits, and ship the execution loop that found six defects on this repository today.

**Architecture:** Nine tasks. One fixes a live defect and guards it. Two deepen skills that already exist — process first, knowledge second, because the process skills set the pattern the knowledge pass follows. Two build and wire the execution loop. One credits the influence. One runs the loop on a real task, which is the only thing that turns a process document into a process.

**Tech Stack:** Markdown frontmatter, bash 3.2-compatible shell, `tests/run-tests.sh`, `scripts/check-provenance.sh`, `python3 -m tools.kinglet_build baseline-regenerate`.

**Authority:** `docs/superpowers/specs/2026-08-03-process-layer-second-pass-design.md` (commit `9131b04`). Where this plan and the spec disagree, the spec governs and the disagreement is a bug in this plan — report it.

## Global Constraints

- **Bash 3.2 (macOS) compatible.** No `declare -A`. No `grep -oP`, no `grep -qP`, no `mapfile`.
- **Do not pipe into a reader that can exit early** under `set -euo pipefail`. `head` and `grep -q` both exit on first match without draining stdin; the writer takes SIGPIPE, `pipefail` turns 141 into failure, `set -e` kills the script. Use a here-string or `awk`. These pass on small inputs and fail in the field, so a green suite is not evidence you avoided them.
- **Validate an argument before `shift 2`** — `shift` fails under `set -u` before the error message prints.
- **`bash tests/run-tests.sh` must pass at every commit**, with every test file present in its output. Count `--- test-*.sh ---` headers and confirm the count equals `ls tests/test-*.sh | wc -l`. The summary line is not evidence. **The suite takes ~2m30s — use a timeout above 150000ms, redirect to a log, read the log.**
- **`bash scripts/check-provenance.sh` must report `provenance OK`** at every commit.
- **Every `.claude/` file is recorded in two baseline structures**, so one edited file drifts by 2. `--dry-run` first; if the tool disagrees with your prediction, **report its exact output rather than tuning the number** — that refusal has caught three wrong estimates in two waves. `python3 -m tools.kinglet_build.cli` silently no-ops with exit 0; the entry point is the package, `python3 -m tools.kinglet_build`.
- **`migration/baseline-inventory.json` never shares a commit** with the content it records.
- **Append to `provenance.tsv` notes, never replace** — the notes are cumulative history for a future upstream diff. New files need rows (`origin=original`, `status=original`, 7 tab-separated columns).
- **Skills stay flat** at `.claude/skills/<name>/SKILL.md`, `name:` matching the directory, non-empty `description:`, and **no `alwaysApply` or `globs`** — both are inert Cursor keys this repo measured doing nothing.
- **Three guards are live and will catch you.** `tests/test-surface-references.sh` fails on a bare-name skill reference that does not resolve (four reference forms), on a `/unity-*` command named in a skill body with no matching file, and on any untracked file under `.claude/`. `tests/test-skill-discovery.sh` and `tests/test-install-prune.sh` cover the rest.
- **Every claim you write into a skill must be traceable.** The spec's success criterion 5 is that rationalization rows cite incidents, not intuitions. `docs/research/pioneer/field-notes.md` has 87 sections, `docs/research/pioneer/smoke-pass.md` has 11, and `git log` since `0f772a4` has today's. A row you cannot source is a row that does not ship.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `.claude/agents/*.md` (7) | `tools:` glob renamed to the live server | 1 |
| `install.sh`, `MCP-SETUP.md` | Write and document the conceded server name | 1 |
| `tests/test-mcp-naming.sh` | New guard: agent globs must match what a shipped config writes | 1 |
| `.claude/skills/deep-interview/`, `systematic-debugging/`, `verification-before-completion/` | Escape-hatch sections | 2 |
| `.claude/skills/using-kinglet/SKILL.md` | Stays short; gains pointers only | 2 |
| 9 knowledge `SKILL.md` | Rule boundary, pitfalls, staleness marker | 3 |
| `.claude/skills/subagent-driven-implementation/SKILL.md` | The execution loop | 4 |
| `.claude/skills/subagent-driven-implementation/*.md` | Dispatch templates | 4 |
| `.claude/commands/unity-workflow.md` | The post-plan fork | 5 |
| `CREDITS.md`, `.claude/NOTICE.md` | Influence section | 6 |
| `docs/research/pioneer/field-notes.md` | The loop's first real run | 7 |
| `.claude/agents/*.md` (8) | Process-skill wiring, report contract, console + manual-step rules | 8 |
| `.claude/rules/*.md` (6) | Staleness marker; `architecture.md` says it can fail to apply | 9 |

---

### Task 1: Make the seven MCP agents able to call MCP

The cut kept seven agents because they drive the Unity Editor over MCP. All seven declare
`tools: mcp__unityMCP__*`. The server actually registered is **`UnityMCP`** — capital U — written by
CoplayDev's Auto-Setup into `~/.claude.json`. Tool permissions match by name, so the glob matches
nothing and **all seven are silently MCP-less.**

`MCP-SETUP.md:99-115` recorded the collision on 2026-07-30 and advised removing the wizard's copy.
A real project shows the opposite outcome, four days later, unreported. The toolkit works only in the
configuration our own setup document does not produce.

**Files:**
- Modify: `.claude/agents/unity-coder.md`, `unity-fixer.md`, `unity-optimizer.md`, `unity-prototyper.md`, `unity-scene-builder.md`, `unity-test-runner.md`, `unity-ui-builder.md`
- Modify: `.claude/skills/systematic-debugging/SKILL.md`, `verification-before-completion/SKILL.md`, `unity-mcp-patterns/SKILL.md` (prose stops naming the prefix)
- Modify: `install.sh`, `MCP-SETUP.md`
- Create: `tests/test-mcp-naming.sh`
- Modify: `provenance.tsv`; separate commit: `migration/baseline-inventory.json`

**Interfaces:**
- Produces: `mcp__UnityMCP__*` as the single spelling in every `tools:` glob, and `"UnityMCP"` as what `install.sh` writes into `.mcp.json`. Tasks 2-7 consume this.

- [ ] **Step 1: Confirm the defect before fixing it.** Do not take this plan's word for it.

```bash
cd "$(git rev-parse --show-toplevel)"
grep -rho 'mcp__[A-Za-z]*MCP__' .claude/ scripts/ install.sh | sort | uniq -c
python3 -c "
import json; d=json.load(open('$HOME/.claude.json'))
for k,v in d.get('projects',{}).items():
    s=v.get('mcpServers') or {}
    if s: print(k, '->', list(s.keys()))"
```

Expected: every payload reference is `mcp__unityMCP__`, and the live registration is `UnityMCP`. **If the live registration is lowercase on your machine, stop and report it** — the fix direction depends on this and the plan must not be applied against a machine that contradicts it.

- [ ] **Step 2: Rename the seven `tools:` globs** to `mcp__UnityMCP__*`. Frontmatter only. Preserve every other key.

- [ ] **Step 3: Take the prefix out of prose.** In `systematic-debugging`, `verification-before-completion` and `unity-mcp-patterns`, a sentence naming `mcp__unityMCP__read_console` becomes "the unity-mcp `read_console` tool". The exact string is load-bearing only in a `tools:` glob; anywhere else it couples instruction to a deployment detail that upstream controls.

- [ ] **Step 4: Change what `install.sh` writes.** The heredoc near `install.sh:625` writes `"unityMCP"`; it becomes `"UnityMCP"`. The presence check near `:302` currently greps for `'"unityMCP"'` — it must accept **either** spelling, so an existing project configured the old way is not told it has no entry and offered a duplicate.

- [ ] **Step 5: Rewrite `MCP-SETUP.md`'s collision section.** It currently tells the user to run `claude mcp remove UnityMCP -s local` and keep ours. That advice produces the broken configuration. Replace it with what is now true: Auto-Setup's registration is the one the toolkit targets, running Auto-Setup is the supported path, and a project that already has a lowercase `unityMCP` entry keeps working because the agents' globs and the installer both name the wizard's spelling now. Say plainly that the toolkit conceded the name and why, so the next person does not "fix" it back.

- [ ] **Step 6: Write the guard, and watch it fail.**

`tests/test-mcp-naming.sh`, runner-provided (uses the runner's `assert_eq` and `$REPO_DIR`, defines neither, sets no `-e`, contains no `exit`). It asserts that **every distinct `mcp__<server>__` spelling appearing in any `tools:` frontmatter glob is one that a shipped configuration actually writes** — derived from `install.sh`'s heredoc, not hardcoded, so the two cannot drift apart again.

```bash
echo "--- mcp naming ---"

# The server name install.sh writes into a fresh .mcp.json. Derived, never typed: the whole defect
# this guards was two files disagreeing about one string.
SHIPPED_SERVER=$(awk -F'"' '/^ *"[A-Za-z]*MCP": \{/ {print $2; exit}' "$REPO_DIR/install.sh")

BAD=$(
  for f in "$REPO_DIR"/.claude/agents/*.md; do
    [ -f "$f" ] || continue
    awk -v file="$f" -v want="$SHIPPED_SERVER" '
      /^---/ { n++ }
      n == 1 && /^tools:/ {
        while (match($0, /mcp__[A-Za-z0-9_]+__/)) {
          tok = substr($0, RSTART + 5, RLENGTH - 7)
          if (tok != want) print file "\t" tok
          $0 = substr($0, RSTART + RLENGTH)
        }
      }
    ' "$f"
  done | sort -u
)

if [ -n "$BAD" ]; then
  printf '%s\n' "$BAD" | while IFS="$(printf '\t')" read -r src tok; do
    printf '%s declares mcp__%s__ but install.sh writes %s\n' "${src#$REPO_DIR/}" "$tok" "$SHIPPED_SERVER"
  done
fi
assert_eq "$(printf '%s' "$BAD" | grep -c . || true)" "0" \
  "every agent's MCP tool glob names the server install.sh writes"

assert_eq "$([ -n "$SHIPPED_SERVER" ] && echo found || echo missing)" "found" \
  "install.sh's .mcp.json heredoc still declares a server name this test can read"
```

The second assertion matters as much as the first: if the heredoc is reformatted so the `awk` stops finding it, `SHIPPED_SERVER` goes empty and the first assertion passes vacuously against every agent. That is the failure this repo has shipped before.

**Watch it fail** in a scratch worktree: revert one agent's glob to `mcp__unityMCP__*`, confirm the guard names that file, then `git worktree remove --force`. Do not create probe files in the main working tree.

- [ ] **Step 7: Suite, provenance, commit, baseline** — in that order, baseline in its own commit.

---

### Task 2: Give the process skills their escape hatches

The four process skills state what to do. None states what it looks like when you are about to not do
it. That is the half that makes the upstream versions work, and it is missing here.

**Files:**
- Modify: `.claude/skills/deep-interview/SKILL.md`, `systematic-debugging/SKILL.md`, `verification-before-completion/SKILL.md`
- Modify: `.claude/skills/using-kinglet/SKILL.md` (pointers only — it is injected every session and §87 governs its length)
- Modify: `provenance.tsv`; separate commit: `migration/baseline-inventory.json`

**Interfaces:**
- Consumes: Task 1's prose changes to two of these files.
- Produces: the pattern Task 3 follows for the knowledge skills.

**Every row must cite a real incident.** Sources, all in this repository:
`docs/research/pioneer/field-notes.md` (87 sections), `docs/research/pioneer/smoke-pass.md` (11),
`MERGE-NOTES.md`, and `git log 0f772a4..HEAD` for today's. **A row you cannot source does not ship** —
the spec's criterion 5 is a spot-check that every row is traceable, and a table of plausible-sounding
inventions is the known failure mode of this task.

- [ ] **Step 1: `verification-before-completion` — this is where the incidents concentrate.** Add a rationalization table. Rows available from measured events, each with its source:

| Thought | Reality | Source |
|---|---|---|
| "The suite passed before I made this change" | A green run only proves the tree it ran on. | The merged-result rule, and `2b543f2`, a commit that did not pass its own suite |
| "It compiles, so it works" | Compilation is not behaviour. Unity also writes files that fail to compile without failing the write. | `unity-specifics.md`'s editor/runtime guard |
| "I described the manual Editor step, so it is handled" | A described step nobody performed is a step that did not happen. | `performance.md`'s Developer Action Items |
| "The test is green, so the test is real" | A test that asserts nothing passes. Watch a new test fail first. | `tests/test-surface-references.sh`, seen to fail before being trusted; and the runner-provided file that "exits 0 having asserted nothing" |
| "The check reported no problems" | Ask what set the check ran over. A check that scans one directory of a class reads as though it covers the class. | `tests/test-bash32-compat.sh` excluded `install.sh`, which then shipped the SIGPIPE bug it exists to catch |
| "The reviewer confirmed it" | Confirm what it verified against. A review that validates against the repo's own convention can bless a string the live system does not accept. | The `mcp__UnityMCP__` casing, blessed by a whole-branch review and wrong |

- [ ] **Step 2: `systematic-debugging` — the ways a cause gets skipped.** Rows: "the error message names the file, so I know the cause" (it names where it surfaced); "I can see the bug in the code" (then reproduce it, or you are fixing a different one); "reading the console needs the Editor running and it is not" (then say so and stop — a fix from memory is a guess with a confident tone); "I changed two things and it works now" (you learned nothing and one of them may be masking the other). Keep the existing Unity-specific cause list; it is the strongest part of the file.

- [ ] **Step 3: `deep-interview` — the ways a vague request gets treated as clear.** Rows: "they said what they want" (a want is not an acceptance criterion); "I can infer which file" (inferring is guessing with extra steps — name it and let them correct you); "asking is slower than doing" (it is slower than doing it right once and faster than doing it twice, and this project has the second case on record); "the request has a code block, so it is specific" (specificity is about the *outcome*, not the input).

- [ ] **Step 4: `using-kinglet` gains pointers only.** One line per process skill telling the reader those files carry a "when you are about to skip this" section. It is injected every session; §87 measured that one precedence sentence naming a file changed all twelve runs while bulk changed none. **Do not add a table here.**

- [ ] **Step 5: Verify every row is sourced.** For each row you wrote, name the file or commit it came from, in your report. Rows without a source get cut before commit, not defended.

- [ ] **Step 6: Suite, provenance, commit, baseline.**

---

### Task 3: The nine knowledge skills

Measured: they are not thin — 128 to 724 lines, 10 to 32 code blocks each. Three real gaps, none of
which is length.

**Files:**
- Modify: `.claude/skills/addressables/`, `assembly-definitions/`, `input-system/`, `object-pooling/`, `physics/`, `save-system/`, `state-machine/`, `unity-mcp-patterns/`, `urp-pipeline/` (`SKILL.md` each)
- Modify: `provenance.tsv`; separate commit: `migration/baseline-inventory.json`

**Interfaces:**
- Consumes: Task 2's pattern.

- [ ] **Step 1: Say which part is the rule's.** This is the sharpest gap and the one with a precedent. The cut removed `serialization-safety` **because** it duplicated `.claude/rules/serialization.md`, and the survivors were kept because the rules cover them only partly. None of them says which part. The rules **bind**; a skill that silently restates one can drift into contradicting it, and the reader has no way to know which wins.

Add a short block near the top of each overlapping skill naming the rule and the boundary:

- `object-pooling` → `performance.md` binds "pool frequently instantiated objects" and the zero-allocation rule; the skill carries the implementations.
- `physics` → `performance.md` binds non-allocating queries and FixedUpdate placement; the skill carries the API detail.
- `input-system` → `unity-specifics.md` binds the New Input System as mandatory and the enable/disable lifecycle; `architecture.md` binds the InputView pattern; the skill carries action maps, rebinding and device switching.
- `assembly-definitions` → `architecture.md` binds dependency direction; the skill carries asmdef mechanics.
- `save-system` → `serialization.md` binds `[FormerlySerializedAs]` and the `== null` check; the skill carries save-file format and migration.
- `urp-pipeline` → `pc-console.md` binds what is affordable on PC/console; the skill carries URP asset and renderer-feature configuration.
- `state-machine`, `addressables`, `unity-mcp-patterns` → no rule covers these. Say so explicitly; "no rule binds this, it is yours to judge" is information.

**End each block with the precedence sentence: where the skill and the rule disagree, the rule wins and the skill is what is out of date.**

- [ ] **Step 2: Add pitfalls to the four that have none.** Measured: `input-system` (414 lines), `object-pooling`, `physics`, `urp-pipeline` contain no warning, gotcha or "do not" section at all. Each gets one, in the same shape as Task 2's — the mistake, why it is tempting, what it costs. Unity-specific and concrete: for `input-system`, an action map enabled in `Awake` instead of `OnEnable` receives nothing after the first disable; for `object-pooling`, an object returned to the pool without resetting its state carries it into the next spawn; for `physics`, a `RaycastNonAlloc` buffer that fills silently truncates rather than growing; for `urp-pipeline`, a renderer feature added to the wrong renderer asset applies to no camera.

**Verify each against the Unity documentation or this repository's own field notes before writing it.** An invented pitfall in a knowledge skill is worse than none — it is a confident wrong answer with a heading.

- [ ] **Step 3: Date the content.** One line per skill: the Unity version its API surface was written against (`6000.0` unless the file says otherwise) and the date. Nothing here says when it goes stale, and Unity APIs move. This is metadata in the body, **not** frontmatter — `test-skill-discovery.sh` allows only `name` and `description`.

- [ ] **Step 4: Do not restructure what already works.** `save-system` and `state-machine` are 692 and 724 lines of working reference. This task adds boundaries, pitfalls and a date. It does not rewrite them, and it does not "tighten" prose that is carrying examples.

- [ ] **Step 5: Suite, provenance, commit, baseline.** Nine edited files predicts a drift of 18 — `--dry-run` first.

---

### Task 4: The execution loop

**Files:**
- Create: `.claude/skills/subagent-driven-implementation/SKILL.md`
- Create: `.claude/skills/subagent-driven-implementation/implementer-prompt.md`
- Create: `.claude/skills/subagent-driven-implementation/task-reviewer-prompt.md`
- Create: `.claude/skills/subagent-driven-implementation/re-review-prompt.md`
- Create: `.claude/skills/subagent-driven-implementation/final-reviewer-prompt.md`
- Modify: `provenance.tsv`; separate commit: `migration/baseline-inventory.json`

**Interfaces:**
- Consumes: the surviving surfaces — `unity-coder`, `unity-reviewer`, `unity-fixer`, `unity-test-runner`, and the skills `systematic-debugging` and `verification-before-completion`.
- Produces: the skill Task 5 wires into `/unity-workflow`, and the process Task 7 runs.

**A skill directory with more than `SKILL.md` in it is new for this repo.** `test-skill-discovery.sh`
requires `SKILL.md` at exactly one level and forbids nesting; sibling files at the same level are not
nesting. **Confirm the guard accepts sibling files before writing four of them** — if it does not,
report that rather than working around it, because the alternative is inlining four templates into one
file and that is what makes upstream's version hard to read.

- [ ] **Step 1: Write `SKILL.md` — the loop.** Its shape, in order: setup (ledger, base commit, one todo per task); per task — dispatch implementer, handle the report, review, fix loop, complete; then the final whole-branch review; then finish. Carry these rules, each of which was learned here today:

- **One implementer at a time. Never two against one Unity project.** The Editor is a single process with a single asset database; two agents driving it over MCP corrupt each other's state in ways no diff shows. The generic version of this rule is about merge conflicts. Here it is about a database.
- **The ledger is the recovery map.** Conversation memory does not survive compaction; a controller that lost its place re-dispatches completed work. Record the plan path on line one, one line per task completion with its commit range, every deferred minor, and every parked finding with its ruling.
- **Never fix findings in the controller session.** It pollutes the context that holds the plan, and a controller fix skips review. Resume the implementer.
- **Do not pre-judge findings for the reviewer.** If a dispatch prompt contains "do not flag" or "at most Minor", the loop has already failed. Let the finding be raised and adjudicate it.
- **The task review gates on spec compliance AND quality.** Either alone passes work that should not ship.
- **The fix loop is bounded at five rounds.** Rounds 1-3 resume the original implementer, whose context is intact. Rounds 4-5 dispatch a fresh one on a more capable model — a loop surviving three resumes usually means the implementer cannot see its own problem.
- **At the cap, adjudicate; do not keep dispatching.** Park with a ruling, or stop on anything load-bearing.
- **A task is not complete until the console is clean.** `read_console` after the last write. A file that does not compile was still written successfully.
- **Manual Editor steps are a task outcome, not a footnote.** If the work needs a sprite atlas, a lightmap bake or an import setting an agent cannot create, the task ends by naming it and blocking dependent work.
- **Record scene and prefab state in the ledger.** A task that leaves an unsaved scene changed nothing on disk, and the next task inherits an Editor that disagrees with git.

- [ ] **Step 2: Write `implementer-prompt.md`.** What a dispatch must contain: one line on where the task fits; the brief path introduced as "read this first — your requirements, exact values verbatim"; interfaces from earlier tasks the brief cannot know; the controller's resolution of any ambiguity it noticed; the report-file path and the report contract. What it must **not** contain: accumulated prior-task history. State the four report statuses — DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, BLOCKED — and what the controller does with each.

- [ ] **Step 3: Write `task-reviewer-prompt.md`.** Three inputs by path — brief, report, diff — plus the binding constraints copied verbatim as the reviewer's attention lens. The verdict format: spec ✅/❌ with specifics, quality Approved/Needs work with findings classified Critical/Important/Minor at `file:line`, and `⚠️ Cannot verify from diff` for anything living in unchanged code. **Say that the diff arrives as a file**, never pasted, and that the reviewer is told what the controller has already verified so it does not re-run a 2-minute suite to learn what is in the report.

- [ ] **Step 4: Write `re-review-prompt.md`.** Scoped: verdict each open finding ADDRESSED or NOT ADDRESSED with evidence, flag new breakage in the fix diff only, and send out-of-scope observations to the ledger rather than extending the loop. **Include the instruction that made the difference today: where a fix claims a guard now works, prove it by experiment rather than by reading — and use a probe shape the implementer did not use, because repeating their probe proves only that their probe passes.**

- [ ] **Step 5: Write `final-reviewer-prompt.md`.** The whole-branch review, on the most capable model. Its three jobs: triage the ledger's deferred and parked findings for merge; find what per-task reviews structurally could not see, because each saw one brief and one diff and cross-task properties were nobody's job; and judge shipped content as product, not just as correct. **Name the categories that paid off today**: files nothing references any more, a check whose scanned set is not the whole reality, documentation asserting what the code no longer does, and a number typed into prose that a later commit invalidated.

- [ ] **Step 6: Confirm the guards accept the directory shape**, then suite, provenance, commit, baseline.

---

### Task 5: Wire the loop into `/unity-workflow`

**Files:**
- Modify: `.claude/commands/unity-workflow.md`
- Modify: `.claude/skills/using-kinglet/SKILL.md` (one table row)
- Modify: `provenance.tsv`; separate commit: `migration/baseline-inventory.json`

- [ ] **Step 1: Add the fork at the end of Phase 2.** When a plan exists, offer both paths and make the trade-off legible rather than recommending blindly:

```markdown
Plan complete. Two ways to execute it:

1. **Subagent-driven** — a fresh implementer per task, a review after each, a bounded fix loop, and
   one whole-branch review at the end. Slower per task and it catches what a single pass does not:
   run on this toolkit's own repository, the reviews found six defects the implementing task could
   not see, including an installer that overwrote user files.
2. **Inline** — execute here, in this session, with checkpoints. Fewer moving parts, no dispatch
   overhead, and the same context that wrote the plan writes the code. Right for a small plan or one
   task.

Which?
```

- [ ] **Step 2: Route option 1 to the skill** and keep Phase 3's existing inline behaviour as option 2. Do not delete Phase 3 — a small plan should not pay for the loop.

- [ ] **Step 3: One row in `using-kinglet`'s table** — "A written plan to execute, task by task, with review between" → `subagent-driven-implementation`.

- [ ] **Step 4: Suite, provenance, commit, baseline.** `test-surface-references.sh` checks that a `/unity-*` named in a skill body exists — the new row names a skill, not a command, so confirm the guard is satisfied either way.

---

### Task 6: Credit the influence

**Files:**
- Modify: `CREDITS.md`, `.claude/NOTICE.md`
- Modify: `provenance.tsv`; separate commit: `migration/baseline-inventory.json` (`NOTICE.md` is under `.claude/`)

- [ ] **Step 1: Add one section to each.** State what was taken and what was not, with the measured numbers so the claim is checkable: the chain design, the execution loop, and two skill names (`systematic-debugging`, `verification-before-completion`) came from Superpowers; the text did not — similarity 0.120, 0.183 and 0.156 against its counterparts, with nothing shared beyond YAML frontmatter and one heading.

- [ ] **Step 2: Say what this is and is not.** It is not a license obligation: MIT covers expression, the expression is ours, and `provenance.tsv`'s `origin=original` on those files is correct and does not change. It is here because `CREDITS.md` opens with *"nothing here is asserted on trust"*, and a credits file that names the project whose architecture we adopted only as the thing we beat is incomplete by that standard.

- [ ] **Step 3: Do not add a license block.** Nothing is vendored, nothing is derived at the expression level, and reproducing a license for code we do not ship would make the file *less* accurate, not more.

- [ ] **Step 4: Suite, provenance, commit, baseline.**

---

### Task 7: Run the loop on a real task

Everything above is a document until this runs. The spec's criterion 4 is deliberately scoped to one
task, because the loop's Unity-specific rules are reasoned rather than measured and one honest run
tells more than a plan section claiming they work.

**Files:**
- Modify: `docs/research/pioneer/field-notes.md` (append a dated section)
- Whatever the chosen task touches

- [ ] **Step 1: Pick the task from what this wave already owes.** A candidate with real substance and a clear acceptance test: **`.claude/hooks/block-legacy-input.sh:69` prints `(see skills/systems/input-system)`** — the pre-flattening nested path, which has not resolved since skills were flattened, printed to the user on every block. It is small, it is shipped, it has an obvious correct answer, and fixing it exercises implementer → review → complete. If a better candidate exists in the ledger's carried list, use that instead and say why.

- [ ] **Step 2: Run the loop as written.** Ledger, brief, dispatch, review, fix if needed, complete. **Follow the skill, do not improvise around it** — the point is to find out where the written process is wrong, and a run that quietly deviates measures nothing.

- [ ] **Step 3: Record what the process got wrong.** Append a dated section to `field-notes.md`: what the loop cost in wall-clock and dispatches for one small task, what the review caught that the implementer did not, and every place the skill's own instructions were unclear, unnecessary, or missing. **Write the negative findings first.** A first run that reports only success has not been read carefully.

- [ ] **Step 4: Fix the skill from what the run found**, in a separate commit, so the correction is traceable to the run that motivated it.

- [ ] **Step 5: Suite, provenance, final commit, baseline.**

---

### Task 8: The eight agents — wire them to the chain and give them a report contract

Measured: all eight already carry limits ("do not", "never") and a **Skills to load** block, so the
gap here is not the one Tasks 2 and 3 close. It is narrower and it was found by today's final review:

> *"No agent's `Skills to load` block names `systematic-debugging` or `verification-before-completion`.
> The chain works user-first (measured), but `unity-fixer` invoked directly — which its own
> description explicitly invites — skips the method entirely, and `unity-coder` never sees the
> verification rule."*

So the chain holds only when a human enters through a command. A dispatching model that selects an
agent directly — the path §1 of the trigger rules exists to support — gets an implementer with no
method and no definition of done.

**Files:**
- Modify: all eight `.claude/agents/*.md`
- Modify: `provenance.tsv`; separate commit: `migration/baseline-inventory.json`

**Interfaces:**
- Consumes: Tasks 1, 2 and 4. The skills must carry their new sections before agents point at them, and the `tools:` globs must already be correct.

- [ ] **Step 1: Wire the process skills into the blocks that need them.** Not all eight need both — a skill named but never useful is noise, and this repo cut 74 surfaces for exactly that.

| Agent | Add | Why |
|---|---|---|
| `unity-fixer` | `systematic-debugging`, `verification-before-completion` | Its whole job is the method; today it has none when dispatched directly |
| `unity-coder` | `verification-before-completion` | Writes code and has no stated definition of done |
| `unity-test-runner` | `verification-before-completion` | Owns the evidence half of that skill |
| `unity-optimizer` | `verification-before-completion` | "It is faster" is the claim most often made without before/after frames |
| `unity-prototyper`, `unity-scene-builder`, `unity-ui-builder` | — | They build throwaway or visual output; the verification skill's evidence table does not fit and forcing it would be padding |
| `unity-reviewer` | — | It *is* the review; loading a review skill is circular |

Say why in your report if you deviate.

- [ ] **Step 2: Give each agent a report contract.** Every one of them is dispatched by a command or by another agent, and none states what it returns. Today the caller gets whatever prose the agent chose. Add a short **What you return** section to each: status, what changed with paths, what was verified and how, and what still needs a human. Four lines, not a form.

This is the single highest-value thing borrowed from the upstream loop's dispatch discipline — a subagent whose final text *is* the return value produces structured data instead of a chat message, and the caller stops parsing prose.

- [ ] **Step 3: Add the console rule to the five agents that write C# or drive the Editor** (`unity-coder`, `unity-fixer`, `unity-prototyper`, `unity-scene-builder`, `unity-ui-builder`): a file that fails to compile is still written successfully, so `read_console` after the last write is part of finishing, not an optional check. This is Task 4's loop rule, stated where an agent dispatched *outside* the loop will still see it.

- [ ] **Step 4: Add the manual-Editor-step rule to the same five.** `performance.md` already binds it for the architect; the agents that hit it are these. An agent that cannot create a sprite atlas, a lightmap bake or an import setting says so and blocks dependent work rather than writing code that assumes the asset exists.

- [ ] **Step 5: Confirm the guard is satisfied.** `tests/test-surface-references.sh` fails when an agent names a skill that does not exist, in any of four forms — the new entries are bare names in a "Skills to load" block, which is one of the four. Run the suite and read that section rather than assuming.

- [ ] **Step 6: Suite, provenance, commit, baseline.** Eight edited files predicts a drift of 16 — `--dry-run` first.

---

### Task 9: The six rules — a staleness marker and one honest boundary

The rules are the layer that measurably works: they auto-load, they bind, and a probe answered a
serialization question from `serialization.md` with zero tool calls. This task does not rewrite them.
It closes the two gaps the wave exposed.

**Files:**
- Modify: `.claude/rules/architecture.md`, `pc-console.md` (and the other four only for Step 2)
- Modify: `provenance.tsv`; separate commit: `migration/baseline-inventory.json`

- [ ] **Step 1: `architecture.md` must say that it can fail to apply.** Endless Evolution has zero VContainer files, zero MessagePipe files and 38 `StartCoroutine` users, and had to write a section in its own `AGENTS.md` to neutralise this file. `generate-claude-md.sh` now detects that and emits a verdict, but **the rule itself still reads as unconditional** — and a reader who opens `architecture.md` directly, which every non-Claude-Code client does, never sees the generated block.

Add a short opening note: this file assumes the VContainer + MessagePipe + UniTask stack; whether it binds in a given project is detected at install time and stated in that project's `CLAUDE.md` generated block; where the two disagree, the generated block is newer. **Do not weaken the rules themselves** — an unconditional rule that says where to check its own applicability is stronger than a hedged one.

- [ ] **Step 2: Date all six.** One line each: the Unity version the guidance targets and the date last reviewed. Same reason as Task 3 Step 3 — nothing currently says when a rule goes stale, and these bind.

- [ ] **Step 3: `pc-console.md` — remove the last self-contradiction.** It says *"If you find guidance in this repo saying otherwise, it is a leftover from the mobile-targeted upstream — treat it as a bug and report it."* The mobile content was removed and `tests/test-no-mobile.sh` keeps it out, so this sentence points at a hazard that no longer exists. Replace it with what is true: the mobile guidance is gone and a test keeps it gone; if you find any, that test has regressed.

- [ ] **Step 4: Suite, provenance, commit, baseline.**

---

## What this plan does not do

| Deferred | Why |
|---|---|
| Headless Unity as an MCP alternative | Covers builds, tests and batch asset work; does not cover live Editor state, which is what `read_console` and the profiler are for. Complementary. Separate evaluation. |
| Case-insensitive MCP server matching | Not expressible in a `tools:` glob; needs Claude Code support. |
| Re-enabling Superpowers in Endless Evolution | The operator's environment and their call. |
| Git worktrees in the loop | Unity projects do not tolerate two checkouts sharing a `Library/`. |
| Parallel implementer dispatch | Same reason, and worse: one Editor, one asset database. |

## Self-review

**Spec coverage.** Decision 1 → Task 1. Decision 2 → Task 2. Decision 3 → Tasks 4 and 5. Decision 4 → Task 6. Tasks 3, 8 and 9 extend Decision 2's pattern to the knowledge skills, the agents and the rules at the operator's request — the spec's table covers only the four process skills. **That is a gap in the spec, not in this plan: amend the spec's Decision 2 table to name all four layers before executing.** Criterion 1 → per-task gates. Criterion 2 → Task 1 Step 6. Criterion 3 → Task 1 Step 1, which verifies against the live registration before changing anything. Criterion 4 → Task 7. Criterion 5 → Task 2 Step 5 and Task 3 Step 2. 

**Placeholder scan.** No TBD. The guard script, the fork text and every rationalization row are written out. The one deliberately unfixed value is each task's baseline drift, which `--dry-run` establishes; predictions are given where the file count is known.

**Type consistency.** `mcp__UnityMCP__` is the target spelling in Tasks 1, 4 and 7. The four dispatch templates are named identically in Task 4's file list, its steps, and Task 5's routing. `subagent-driven-implementation` is the skill's name everywhere.
