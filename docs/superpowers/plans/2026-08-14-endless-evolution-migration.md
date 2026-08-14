# Endless Evolution Migration — Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `.claude/skills/subagent-driven-implementation/SKILL.md`.

**Goal:** Bring `/home/riive/Documents/GitHub/Endless-Evolution` onto the current toolkit, and in doing
so run the measurement this repository has never run: **what the toolkit does to a real game.**

**Why this matters more than the eight follow-ups it interrupts.** Nothing in this repository has ever
proven the toolkit works *inside Claude Code against a live Unity project*. Every claim about what a
model does with a rewritten surface is a reading of instructions. The fixture is **1 C# file, 0
`.meta` files**; EE carries **923 third-party `.cs` files** and a shipping game.

---

## What the dry run measured, 2026-08-14

`bash install.sh --project-dir /home/riive/Documents/GitHub/Endless-Evolution --dry-run` → rc 0.

**The good result first, because it closes a recorded blocker.** On 2026-08-03 a second install into
EE *"overwrote a customised hook and a `settings.json` key, recovered by hand"*, and the spec recorded
that this **must be fixed before the toolkit is handed to anyone else.** It now reports:

```
keep 3 removed-from-payload file(s) you edited
keep 29 file(s) you modified
CLAUDE.md — refresh the generated section only; your prose untouched
.mcp.json already has a unityMCP/UnityMCP entry — would leave alone
MCP-SETUP.md already exists — its contents are NOT touched
```

**Verified, not taken on trust:** `install.sh` compares against the **receipt's** recorded hash, not
the current payload. `unity-coder.md` in EE hashes `1987ef…`; the receipt says it installed `b8097c…`;
the toolkit now ships `738d3c…`. **59 of 92 receipt rows still match exactly.** The classification is
sound.

### The drift

| | installed in EE | current toolkit |
|---|---|---|
| commands | 11 | 9 |
| skills | 14 | 16 |
| **hooks** | **28** | **13** |
| rules | 6 | 6 |

EE carries **15 hooks the toolkit removed on 2026-08-13**, and the dry run offers to remove 19 stale
files (14 hooks, 4 scripts, 1 skill).

### The actual problem, and it is not a bug

**EE tracks `.claude/` in git — 86 files — and updates it through curated `chore(kinglet):` commits,
not through `install.sh`.** The receipt is **not** tracked (only `.gitkeep`), so it still reflects the
last real install on **2026-08-05**. Two update mechanisms are running against one directory:

- `install.sh` writes files and records hashes in a machine-local receipt.
- EE's git workflow writes the same files and records nothing the installer can read.

So every file EE updated by git looks to the installer like **a file the user edited**, and the
installer correctly refuses to clobber it. **That is why 29 files are frozen: not a defect, a
collision between two mechanisms.** The sampled diffs confirm it — EE's `unity-coder.md` and
`unity-review.md` differ from the toolkit only by content the toolkit *added later* (the
architecture-stack block, the pre-dispatch rename check). They are **stale, not customised.**

---

## The decision this plan needs, and it is the owner's

**Which mechanism owns `.claude/` in EE?** Right now both do, half each, which is the whole problem.

**Option A — `install.sh` owns it.** Remove `.claude/` payload files from EE's git index, add them to
EE's `.gitignore`, and let the installer be the only writer. Updates become `bash install.sh`.
*Cost:* EE loses the ability to review a toolkit change as a diff before accepting it, and a fresh
clone of EE has no toolkit until someone runs the installer.

**Option B — git owns it.** EE keeps `.claude/` tracked and curated; `install.sh` is never run there
again. Updates become a copy-and-review commit. *Cost:* every update is manual, the receipt is dead
weight, and `uninstall.sh` cannot work.

**Option C — install writes, git records.** Run `install.sh`, then commit the result as a normal EE
change. The receipt travels with the machine; the payload travels with the repo. *Cost:* the receipt
must be regenerated on every machine, and two clones can disagree about what was installed.

**Recommendation: C.** It is what EE is already half-doing, it keeps the diff-review property that the
`chore(kinglet):` commits exist for, and it makes the installer's ownership tracking meaningful again
— because after one install-then-commit, receipt and tree agree, and the *next* upgrade's "you
modified" list becomes true information rather than an artefact of the collision.

**Nothing below should be executed until this is answered**, because A, B and C produce different
first steps and the wrong one is expensive to undo in a shipping game's repository.

---

## Task 1: Re-baseline EE onto the current toolkit *(blocked on the decision)*

**Preconditions, all verified 2026-08-14:** EE is on `main`, working tree clean (0 porcelain lines),
Unity 6000.0.68f1 · URP detected, `com.unity.inputsystem` present.

- [ ] **Work on a branch in EE**, never on `main`. The toolkit's own rule.
- [ ] Run the install for real. **Capture the full output** — the `Not done:` accumulator and the
      ownership report are the measurement, not a side effect.
- [ ] **Diff every one of the 29 frozen files against the current toolkit and classify each**:
      *stale* (EE's copy is an older toolkit version — take the toolkit's), or *customised* (EE
      changed it on purpose — keep, and record why in EE's own docs). **The sampled two were both
      stale.** Do not assume the rest are.
- [ ] For each *customised* file, ask the question that makes this migration worth running: **is the
      customisation still needed, or was it a workaround for something the toolkit has since fixed?**
      `architecture.md`'s neutralisation is the known case — EE has **zero VContainer, zero
      MessagePipe, 38 `StartCoroutine` users**, and wrote an `AGENTS.md` section to neutralise a rule
      that read as unconditional. **`generate-claude-md.sh` now emits a detected verdict instead.**
- [ ] Confirm the 19 stale files are actually removed, and that **nothing in EE references them.**

## Task 2: The measurement this whole repository exists to take

**This is the deliverable. The install is only its precondition.**

- [ ] With the MCP bridge running, exercise the surfaces against real code: `/unity-doctor`,
      `/unity-review` on a real changed file, and one `unity-brainstorming` → `unity-planning` round
      on a real feature request.
- [ ] **Record what a model actually does**, not what the surface says it should. Every claim in this
      repository about surface behaviour is currently a reading of instructions.
- [ ] **The three `warn-*` hooks and `bash-gate.sh` now fire against real `.cs` and real `.meta`
      files.** Task 1 of the previous wave proved they act on synthetic payloads. This is the first
      time they meet a project with 923 third-party files.
- [ ] Report false positives as findings against the toolkit, with the file that triggered them.

## Task 3: Whatever Task 2 breaks

Left deliberately unspecified. **A plan that pre-specifies what a first real-world run will find is a
plan that has already decided the answer.**

---

## Global constraints

- **EE is a shipping game. Do not break it.** Branch, never `main`; no force-push; every change
  reviewable as a diff.
- **The toolkit repo and EE are separate repositories.** Toolkit-side fixes land on
  `pioneer/endless-evolution` here; payload changes land in EE. **Say which repo every change is in.**
- Both gates still bind for any toolkit-side change: `bash tests/run-tests.sh` (timeout ≥ 400000 ms,
  ANSI stripped before counting headers) and `bash scripts/check-provenance.sh` == `provenance OK`.
- **`/usr/bin/grep` and `/usr/bin/find`** for absence claims — interactive `grep` is `ugrep 7.5.0`,
  `find` is `bfs 4.1.1`.
- The measurement discipline from the last two waves applies unchanged, above all: **a derivation
  whose scope includes the file recording its result is not a derivation**, and **a probe whose
  passing condition is silence must first prove its own baseline is not silent.**
