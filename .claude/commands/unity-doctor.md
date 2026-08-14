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
now tolerates a missing directory instead of dying on it. What it prints instead is `rules=0` inside
its `INFO` line, and a reader mapping only PASS/WARN/FAIL still concludes *"no install receipt"*
about a project whose five binding spine rules are gone. **A zero on the `INFO` line is a finding
and the script reports it as neither WARN nor FAIL** — which is Check 3's first item, and the reason
to run that item on every run, not only when the summary line is missing.

If the script is missing altogether, that is an **ERROR** too — the install is incomplete; re-run the
Kinglet installer from the toolkit checkout.

## Check 3: What the doctor script does not read

Check 2 covers the install. These five are outside what it **reports** — and only these, so the
duplication Check 2 removed does not creep back in. *Reports*, not *reads*: item 1 below is falsified
by "outside what it reads", because the script does read those directories — it counts them and
prints the counts as `INFO`, which is not a verdict a reader can act on.

1. **The payload directories exist and are not empty.** `.claude/commands/`, `.claude/agents/`,
   `.claude/hooks/`, `.claude/skills/`, `.claude/rules/`. Any one missing → **ERROR**, naming which.
   **Test contents, not just existence.** An empty-but-present `.claude/agents/` passes a bare
   existence test and passes the doctor script too, which prints `INFO agents=0`, `0 failure(s)` and
   exits 0 — a project with no agents at all reported healthy by both. Any one present and empty →
   **ERROR**, naming which.
   **The script's `INFO` line is not a substitute for this item.** Its count block reads four of
   these five — `agents`, `commands`, `skills`, `rules`, never `hooks` — and prints what it finds,
   absent and empty alike, as `INFO agents=… commands=… skills=… rules=…`. It issues no verdict on
   any of them, so a payload directory that is gone shows up as a zero and never as a `FAIL`. Read
   those four numbers yourself: any zero is this item's **ERROR**, whatever the summary line says.
2. **Hooks on disk that nothing registers.** The script checks `settings.json` → file. Check the
   other direction: for every `.sh` in `.claude/hooks/` except `_lib.sh`, confirm it appears in
   `PreToolUse` or `PostToolUse` in `.claude/settings.json`. Unregistered → **WARNING** (that hook
   never fires).
3. **Executable bit.** Every hook file should be `-x`. Missing → **WARNING**.
4. **Placement.** A hook that can block a tool call belongs in `PreToolUse`; a hook that only warns
   or records belongs in `PostToolUse`. **Classify by what the hook does with its exit status, not
   by its filename** — `block-*.sh` and `warn-*.sh` are the only self-describing prefixes, and
   `bash-gate.sh` and `guard-project-config.sh` (both blocking) and `track-edits.sh` (recording)
   match neither. Misplaced → **WARNING**.
5. **Frontmatter.** Each file in `.claude/commands/` has `name` and `description`; each in
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
Install (script):   PASS  (N file(s) verified against the receipt; N agents, N commands, N skills, N rules)
Payload & hooks:    PASS  (all five directories present; every hook registered, executable and correctly placed)
Project Structure:  WARNING — no test assembly definitions found

Overall: 1 warning, 0 errors
```

For each WARNING or ERROR, include the actionable fix immediately after the line.

## Suggest next

When this command finishes, name the next step and offer it. Do not take it.

If anything is wrong, offer the specific fix. Report; do not change anything on your own.
