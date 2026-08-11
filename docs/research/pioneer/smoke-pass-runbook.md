# Kinglet Pioneer — smoke pass runbook

> **Staleness notice (2026-08-10). Read this before acting on anything below.** This runbook was
> written against the pre-cut surface pool and has **not** been re-derived since. Every count and
> surface name in it records what existed when it was written, not what you are about to test.
> Known wrong today: the counts in "Why it exists" — 36 commands, 28 agents, 39 skills, 25 hooks,
> where the tree now has **9, 8, 16 and 27**; the `serialization-safety` skill in §3, which does not
> exist under that name; and `/unity-workflow` and `/unity-feature`, deleted on 2026-08-10 in favour
> of the skill chain that begins at `unity-brainstorming`. Re-derive against the current tree before
> running a pass.

**For:** the operator running this by hand. Not automated, and not automatable.

**Why it exists.** The test suite proves the installer places correct bytes. It proves nothing about
whether Claude Code then *loads* those bytes — whether 36 commands register, whether 28 agents can be
invoked, whether 39 skills are discoverable, whether 25 hooks fire. That has never been checked. The
repository guide says so directly:

> *"None of this proves the toolkit works in Claude Code — only that the installer places correct
> bytes. Frontmatter validity, command registration, and agent invocation still need one manual pass
> in a real Unity project with the MCP bridge running."*

**What it unblocks.** Wave 1b — the durable-artifact, code-map, surface-description, and
track-connection work — all of which edits command and skill files. Editing the descriptions of
surfaces that turn out not to load would be effort spent against an unmeasured tree.

**Time:** about 45 minutes, most of it Unity opening and the bridge starting.

---

## Rule zero: record what happens, not what should happen

A surface that does not load is the **point** of this exercise, not a problem with it. Do not fix
anything during the pass. Do not retry until green. Write down what you saw, including the parts
that embarrass the toolkit — those are the findings that make Wave 1b worth doing.

If something fails in a way that makes the rest of the pass impossible, record where you stopped and
why, and stop. A partial record is evidence. A repaired record is not.

---

## Prepare

### A scratch Unity project — not your game

First contact goes somewhere you do not mind breaking. Create a new empty Unity 6 project (URP
template) somewhere temporary, e.g. `~/pioneer-smoke/`.

Do not use your game project. Hooks in this payload can block edits, and the point of the pass is to
find out which ones fire and when.

### The MCP bridge

Follow `MCP-SETUP.md`. In short:

1. In the scratch project: **Window → Package Manager → + ▾ → Add package from git URL…** and paste
   `https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main`
2. Run the package's setup wizard and start the server.
3. Confirm it is listening on `http://localhost:8080/mcp`.

Python 3.10+ and `uv` must be on your PATH.

### Install Pioneer

```bash
cd /path/to/kinglet-unity
bash install.sh --project-dir ~/pioneer-smoke --dry-run    # read this output before proceeding
bash install.sh --project-dir ~/pioneer-smoke
```

### Record the versions before anything else

These decide which cells any later evidence belongs to, and one of them settles an open question.

```bash
cd ~/pioneer-smoke
cat ProjectSettings/ProjectVersion.txt
grep -n 'com.coplaydev.unity-mcp' Packages/manifest.json
awk 'NR<=8' .claude/state/install-receipt.tsv
```

**Why the MCP version matters.** The repository currently carries two contradictory pins:
`.claude/UPSTREAM` and `MCP-SETUP.md` say `10.1.0`; the platform spike's `mcp.lock.json` pins
`v9.7.1` at commit `78ee5418415953b79c358bfe6355fcc3fde7912b` and every measured Unity fact in that
spike was taken against 9.7.1. The rule is that **Pioneer pins the version it actually ran against**,
so whatever you record here settles it. Write down the exact resolved version, not the git ref.

Now start Claude Code **in the scratch project directory** — not in the toolkit repo.

---

## Measure

### 1. Commands — do they register?

In Claude Code, type `/` and read the completion list.

Record the **count** of `unity-*` and design commands that appear, and **name every one that is
missing**. The payload ships 36. A command that does not appear usually has malformed frontmatter, so
if any are missing, also record whether they share a pattern (all from one directory, all with one
frontmatter key).

Then invoke two, one from each layer, and record whether the body loaded and made sense:

- `/unity-doctor` — the diagnostic. It should report MCP connectivity and `.claude/` integrity.
- `/scope-check` — a design-layer, read-only command that calls no MCP tools.

### 2. Agents — can they be invoked?

Ask, in plain language and without naming files:

> "Use the unity-scout agent to summarise this project's structure."

Record whether the agent was found and ran. Then repeat for one design agent:

> "Ask the technical-director for a feasibility opinion on adding a save system."

Record for each: found / not found, and whether it behaved as its description claims.

You are not testing output quality here. You are testing **existence and reachability**.

### 3. Skills — are they discoverable?

This is the measurement Wave 1b depends on most, so do it deliberately.

Ask a question whose answer lives in a skill, **without naming the skill**:

> "I need to rename a serialized field on a MonoBehaviour. What do I have to be careful about?"

The correct behaviour is that the `serialization-safety` skill loads and `[FormerlySerializedAs]`
comes up. Record whether the skill was invoked, or whether the answer came from general knowledge or
from the always-on rules instead.

Repeat with a process-shaped request:

> "Let's add a double jump to the player."

Record **which surface, if any, the model selected** — `unity-brainstorming`? `unity-prototyper`?
nothing at all, just starting to write code? (Two commands originally named here were deleted on
2026-08-10; see the staleness notice at the top.) This single observation is the
evidence behind the whole "make the surface machine-selectable" item, so record it exactly, including
if the answer is "it ignored all 75 surfaces and just started coding".

### 4. Hooks — do they fire?

Five hooks are blocking; the rest are advisory. Test two blocking ones, since a hook that does not
fire is invisible and a hook that fires wrongly is worse:

```bash
# Should be BLOCKED — legacy Input API
```
Ask Claude Code to write a script containing `Input.GetKey(KeyCode.Space)` and record whether
`block-legacy-input.sh` stopped it.

Then ask it to edit a `.meta` file directly, and record whether `block-meta-edit.sh` stopped it.

Record any hook that fired **when it should not have** — a false block is a finding, and a more
urgent one than a missed block, because it will fight you every day.

### 5. The stocktake

```
/unity-skill-stocktake
```

Save its full output. It audits all skills and agents for duplicates, stale references, and
never-loaded entries. This is the measurement that decides whether the 75-surface selection pool
needs consolidating — a decision deliberately deferred until this number exists.

### 6. MCP — the honest-failure check

With the bridge **still running**, ask for something that needs it:

> "List the GameObjects in the current scene."

Record whether it worked.

Then **stop the bridge** and ask the same thing again. Record what happened. The required behaviour
is a loud, specific failure naming the unreachable bridge. A silent no-op, or a plausible-looking
answer invented without the bridge, is a serious finding — write it down in full.

---

## Write it up

Create `docs/research/pioneer/smoke-pass.md` in the toolkit repo, with:

```markdown
# Pioneer smoke pass

**Date:** <the date you actually ran it>
**Host:** <OS and kernel>
**Unity:** <exact version from ProjectVersion.txt, including revision>
**MCP package:** <exact resolved version>
**Toolkit version:** <from the receipt>

## Commands
Registered: <n>/36. Missing: <names, or "none">. Pattern among the missing: <...>
/unity-doctor: <what it reported>
/scope-check: <what it did>

## Agents
unity-scout: <found / not found; behaviour>
technical-director: <found / not found; behaviour>

## Skills
Serialization question: <skill invoked? which? or answered from rules/general knowledge>
"Add a double jump": <which surface was selected, or none>

## Hooks
block-legacy-input: <fired / did not fire>
block-meta-edit: <fired / did not fire>
False positives: <any hook that fired wrongly>

## Stocktake
<full output, or a path to it>

## MCP
Bridge up: <worked / did not>
Bridge down: <exact failure text, or "silent" — quote it>

## Where I stopped, if I stopped
<...>
```

Then add a row to `provenance.tsv` (`original` / `original`) so `check-provenance.sh` does not fail
it as an orphan, and commit.

## Afterwards

Two things follow directly from this record and cannot start without it:

1. **The MCP pin is set** to the version you recorded, and the divergence from the spike's `9.7.1` is
   stated rather than quietly reconciled.
2. **Wave 1b is scoped** against what actually loads, and every surface you found missing joins its
   defect list ahead of the improvements.
