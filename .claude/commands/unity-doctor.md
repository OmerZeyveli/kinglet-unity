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

Map its output straight through: its `PASS` lines are **PASS**, its `WARN` lines are **WARNING**,
its `FAIL` lines are **ERROR**. It exits 1 when anything FAILed and 0 otherwise. If the script is
missing, that is itself an **ERROR** — the install is incomplete; re-run the Kinglet installer from
the toolkit checkout.

## Check 3: What the doctor script does not read

Check 2 covers the install. These four are outside what it reads, so they are yours — and only
these, so the duplication Check 2 removed does not creep back in:

1. **Hooks on disk that nothing registers.** The script checks `settings.json` → file. Check the
   other direction: for every `.sh` in `.claude/hooks/` except `_lib.sh`, confirm it appears in
   `PreToolUse` or `PostToolUse` in `.claude/settings.json`. Unregistered → **WARNING** (that hook
   never fires).
2. **Executable bit.** Every hook file should be `-x`. Missing → **WARNING**.
3. **Placement.** Blocking hooks (`block-*.sh`) belong in `PreToolUse`; warning hooks (`warn-*.sh`,
   `validate-*.sh`, `suggest-*.sh`) in `PostToolUse`. Misplaced → **WARNING**.
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

MCP Server:        PASS  (Unity 2022.3.20f1, StandaloneWindows64)
Install (script):   PASS  (N file(s) verified against the receipt; N agents, N commands, N skills, N rules — counts reflect the live install, not a fixed number)
Hooks & frontmatter: PASS  (every hook registered, executable and correctly placed)
Project Structure:  WARNING — no test assembly definitions found

Overall: 1 warning, 0 errors
```

For each WARNING or ERROR, include the actionable fix immediately after the line.

## Suggest next

When this command finishes, name the next step and offer it. Do not take it.

If anything is wrong, offer the specific fix. Report; do not change anything on your own.
