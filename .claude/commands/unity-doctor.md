---
name: unity-doctor
description: "Use when the user asks whether the setup is correct, reports that Kinglet or the Unity MCP bridge is not working, or wants to check the install before trusting it on a new machine. Reports what is wrong rather than changing anything."
user-invocable: true
---

# /unity-doctor — Diagnostic Health Check

Run a comprehensive diagnostic check on the everything-claude-unity installation and the Unity project. Report each check as **PASS**, **WARNING**, or **ERROR** with actionable fixes.

## Check 1: Unity MCP Server Connectivity

1. Attempt to call `project_info` via MCP to get Unity version and project state.
2. If it succeeds: report Unity version, platform, and play mode state → **PASS**
3. If it fails: report the error → **ERROR** with suggestions:
   - Is the unity-mcp package installed in Unity?
   - Is the Unity Editor running and the project open?
   - Is the MCP server running on the expected port?
   - Check `.mcp.json` (project root) → `mcpServers.UnityMCP.url`

## Check 2: The install itself — run the doctor script, do not re-derive it

From the project root (the directory holding `Assets/`), run:

```bash
bash .claude/scripts/studio-doctor.sh
```

This is Kinglet's own health check — it ships with the payload, and the installer points at it in
its closing "Next steps". **Run it; do not re-implement its checks by hand.** It verifies the
install against `.claude/state/install-receipt.tsv` — what was actually written, what has gone
missing, what you have edited — which is a comparison this command cannot make from the file tree
alone, because the tree does not record what the installer put there. It covers, and you therefore
do not re-check:

- Python 3.10+ and `uv`, which the MCP bridge needs
- the bridge itself, by speaking JSON-RPC to the URL the project configures, rather than accepting
  any HTTP answer
- `.mcp.json` parsed (not grepped) for `mcpServers.UnityMCP.url`
- `com.unity.inputsystem` in `Packages/manifest.json`
- install integrity against the receipt: files missing, files you modified, receipt rows whose
  origin it cannot read
- `.claude/NOTICE.md` present
- every hook `settings.json` references existing on disk
- the five payload directories — `agents/`, `commands/`, `hooks/`, `rules/`, `skills/` — each
  present **and holding at least one file of its own kind**, reported as a `FAIL` naming the
  directory, not as a count
- live counts of agents, commands, skills and rules
- the process provider `CLAUDE.md` declares still being installed for this user

Map its output straight through: its `PASS` lines are **PASS**, its `WARN` lines are **WARNING**, its
`FAIL` lines are **ERROR**, and its single `INFO agents=… commands=… skills=… rules=…` line is where
the counts in the report below come from — do not re-derive those either.

**Read the last line first.** A run that finished always ends with a summary of the form
`N passed · N warning(s) · N failure(s)`. Three states, and the exit status alone does not separate
them:

| what you see | what it means |
|---|---|
| summary line, exit 0 | every check ran; nothing failed |
| summary line, exit 1 | every check ran; at least one FAILed |
| **no summary line, any exit status** | **the script aborted part-way through** |

**An aborted run is an ERROR in its own right, and it is not the same finding as the last warning it
printed.** Report it as such: *the health check aborted after `<the last line it printed>`; every
check after that point did not run.* Do not treat what it never reached as passing, and do not offer
its final warning as the diagnosis.

The third row is why you read the last line rather than the exit status — but **no known input
produces it today**, so do not go looking for one. The case that used to, an otherwise healthy
install with `.claude/rules/` deleted and the receipt absent, no longer does: measured 2026-08-14,
that run **exits 0, prints a full summary, and reaches every later check**, because the count block
now tolerates a missing directory instead of dying on it. For a while it then said nothing else
about it either — `rules=0` inside the `INFO` line and no verdict — so a reader mapping only
PASS/WARN/FAIL concluded *"no install receipt"* about a project whose five binding spine rules were
gone, and Check 3 carried a hand-written compensation telling you to read those numbers yourself.
**The script issues that verdict itself now:** measured 2026-08-14 on the same fixture,
`FAIL Payload directory .claude/rules/ is missing`, `1 failure(s)`, exit 1. The compensation is
deleted rather than kept beside it. The `INFO` line is still counts and only counts — take the
report's numbers from it, never a verdict.

If the script is missing altogether, that is an **ERROR** too — the install is incomplete; re-run the
Kinglet installer from the toolkit checkout.

## Check 3: What the doctor script does not read

Check 2 covers the install. These four are outside what it **reports** — and only these, so the
duplication Check 2 removed does not creep back in. The list was five until 2026-08-14: the
payload-directory item is gone because the script issues that verdict itself now, and that is the
direction to take every time one of these becomes something the script reports — delete the item,
do not keep both.

1. **Hooks on disk that nothing registers.** The script checks `settings.json` → file. Check the
   other direction: for every `.sh` in `.claude/hooks/` except `_lib.sh`, confirm it appears in
   `.claude/settings.json` under **some** event. **A hook registered on any event — `PreToolUse`,
   `PostToolUse`, `SessionStart`, `Stop` — fires on that event and is registered by definition; do
   not report it.** Registered under no event at all → **WARNING** (that hook never fires). This is
   the same axis the **Placement** item below draws its line on, and for the same reason: the
   session hooks this toolkit ships sit on `SessionStart` and `Stop`, so a rule keyed on
   `PreToolUse`/`PostToolUse` alone reports every one of them on a completely healthy install.
2. **Executable bit.** Every hook file should be `-x`. Missing → **WARNING**.
3. **Placement.** This rule covers only the hooks registered on `PreToolUse` and `PostToolUse`. **A
   hook registered on any other event — `SessionStart`, `Stop` — is correctly placed by definition;
   do not report it.** (The registration item above draws the same line on the same axis. Change one
   and change the other; they were four lines apart and disagreeing until 2026-08-14.) Among the
   tool-event hooks: one that can block a tool call belongs in `PreToolUse`; one that only warns or
   records belongs in `PostToolUse`. **Classify by what the hook does with its exit status, not by
   its filename** — `block-*.sh` and `warn-*.sh` are the only self-describing prefixes, and
   `bash-gate.sh` and `guard-project-config.sh` (both blocking) and `track-edits.sh` (recording)
   match neither. Misplaced → **WARNING**.
4. **Frontmatter.** Each file in `.claude/commands/` has `name` and `description`; each in
   `.claude/agents/` has `name`, `description`, `model` and `tools`. Invalid → **WARNING**.

## Check 4: Unity Project Structure

1. Check for `Assets/` directory → **ERROR** if missing
2. Check for `ProjectSettings/` directory → **ERROR** if missing
3. Check for `CLAUDE.md` in project root → **WARNING** if missing, suggest `/unity-init`
   (`Packages/manifest.json` is Check 2's — the doctor script reports it)
4. Search for `.asmdef` files in `Assets/` → **WARNING** if none found
5. Search for test assembly definitions (`*Tests*.asmdef`) → **WARNING** if none, suggest `/unity-test`
6. If any `.asmdef` was found, run the assembly-definition graph checker:

   ```bash
   bash .claude/scripts/validate-asmdefs.sh
   ```

   It walks the reference graph and reports circular references, Editor assemblies referencing
   runtime assemblies wrongly, test assemblies missing `testOnly`, and C# files no assembly
   definition covers. A cycle is a transitive-closure property of the whole graph — reading the
   `.asmdef` files one at a time does not surface it, which is why this is a script and not a
   check you perform by eye. Its `[ERROR]` lines are **ERROR**, its `[WARN]` lines are **WARNING**;
   it exits 1 only on errors. It needs `jq`: if `jq` is absent the script says so and exits 1
   without checking anything — report that as **WARNING** (check skipped), not as a graph error.

7. All present → **PASS**

## Output Format

Present a summary report:

```
=== Unity Doctor Report ===

MCP Server:         PASS  (Unity 2022.3.20f1, StandaloneWindows64)
Install (script):   PASS  (N file(s) verified against the receipt; payload complete; N agents, N commands, N skills, N rules)
Hooks & metadata:   PASS  (every hook registered, executable and correctly placed; frontmatter valid)
Project Structure:  WARNING — no test assembly definitions found

Overall: 1 warning, 0 errors
```

For each WARNING or ERROR, include the actionable fix immediately after the line.

## Suggest next

When this command finishes, name the next step and offer it. Do not take it.

If anything is wrong, offer the specific fix. Report; do not change anything on your own.
