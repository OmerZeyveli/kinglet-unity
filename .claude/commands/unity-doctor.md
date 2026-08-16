---
name: unity-doctor
description: "Use when the user asks whether the setup is correct, reports that Kinglet or the Unity MCP bridge is not working, or wants to check the install before trusting it on a new machine. Reports what is wrong rather than changing anything."
user-invocable: true
---

# /unity-doctor — Diagnostic Health Check

Run a comprehensive diagnostic check on the everything-claude-unity installation and the Unity project. Report each check as **PASS**, **WARNING**, or **ERROR** with actionable fixes.

## Check 1: Unity MCP Server Connectivity

1. **Read the MCP resource `mcpforunity://project/info`.** Use that URI verbatim.

   `project_info` is a **resource, not a tool.** Measured 2026-08-14 against
   `mcp-for-unity-server 3.4.5`: `tools/call project_info` answers
   `Unknown tool: 'project_info'`, while reading the URI above returns `projectRoot`,
   `projectName`, `unityVersion`, `platform` and `assetsPath`. The server's own instructions say
   resource names and URIs are not interchangeable, and that guessing a URI by swapping separators
   404s — so do not derive one from the name. In Claude Code, reach it by listing the server's
   resources and reading that URI, not by calling a tool.
2. If it reads: report the Unity version, platform, and play mode state → **PASS**
3. **If the bridge is genuinely unreachable** — the server does not answer, or the resource read
   itself errors — report the error → **ERROR** with suggestions:
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
- the payload directories — `agents/`, `commands/`, `hooks/`, `rules/`, `skills/` — each present
  **and holding at least one file of its own kind**, reported as a `FAIL` naming the directory, not
  as a count (`hooks/` needs a real hook; `_lib.sh` is a sourced library and does not count)
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
   `PostToolUse`, `SessionStart`, `Stop` — is registered, and registration is all this item asks
   about; do not report it.** Registered under no event at all → **WARNING** (a hook nothing
   registers can never fire; one that is registered may still be gated by its `matcher`, which is
   not this item's question). This is
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

## Check 3b: The second client, and only if the project asked for one

**Skip this whole check unless the project root has a `.codex/` directory *or* an `.agents/skills/`
directory.** A project installed for Claude Code alone has neither, and reporting their absence
would fail every healthy install.

**The gate is a disjunction and that is the whole point of it.** The first version read
*"unless `.codex/` exists"*, which made step 1 below unreachable in the exact case it was written
for: a project with the skills bridge and **no** `.codex/` at all is the advisory-not-enforcing
install, and gating on `.codex/` skips the check precisely when the answer is "the hook layer is
missing". Either directory means someone installed a Codex layer; only running the check tells you
whether they installed all of it.

If either exists, the project has a Codex CLI layer, and that layer has one failure mode worth
checking by hand because it is **silent**: hooks that are registered, listed, and never run.

1. **`.codex/hooks.json` exists.** Absent while `.agents/skills/` is present → **WARNING**: the
   skills bridge was installed and the hook layer was not, so this project is advisory rather than
   enforcing under Codex. Say that in those words.
2. **The shim each entry points at resolves.** Read the paths out of `.codex/hooks.json` itself and
   test *those*, not the relative `.claude/scripts/codex-hook-shim.sh` — the config carries
   **absolute** paths, so a moved or renamed project directory breaks every entry at once while the
   relative path is still perfectly present. Checking the relative one passes in exactly the
   scenario this step exists to catch. Any absolute path in the config that is not an existing file,
   or that points outside the project directory → **ERROR**: under Codex a hook whose command cannot
   run is not an error the user sees, it is an allow. The fix for both is to regenerate, per step 3.
3. **The timeouts are seconds, not milliseconds.** Read `.codex/hooks.json` and check every
   `timeout`. `.claude/settings.json` declares milliseconds; Codex reads seconds. A value in the
   thousands → **ERROR**: that is an unconverted millisecond figure, and a hook that should die in
   three seconds will hold the turn for fifty minutes. The fix is to regenerate rather than edit:

   ```bash
   bash .claude/scripts/codex-hook-shim.sh --emit-config > .codex/hooks.json
   ```

   Report it as **ERROR** rather than **WARNING** even though nothing is broken today, because the
   symptom only appears when a hook hangs — which is exactly when the timeout mattered.

   **Say this whenever you tell the user to regenerate.** The trust hash covers a hook's
   *declaration* — its command string, timeout, matcher and event — not its script, so regenerating
   `.codex/hooks.json` changes every entry's hash and drops each one to *"modified since last
   trusted"*, which Codex treats as untrusted and does not run. Measured. Regenerating by hand
   therefore fixes the timeout and silently removes the enforcement. The command that does both is
   the installer, run from the kinglet-unity checkout:

   ```bash
   ./install.sh --project-dir <this project> --client codex --codex-trust
   ```
4. **The skill root resolves.** `.agents/skills/` should hold one entry per directory in
   `.claude/skills/`, and each entry should resolve to a file. A dangling entry → **WARNING**: Codex
   lists what it can resolve and says nothing about the rest. If commands were converted, each also
   has an entry; regenerate with:

   ```bash
   bash .claude/scripts/codex-command-to-skill.sh
   ```

5. **Hook trust is not in this project and cannot be checked from here.** A registered hook does not
   run until its entry is trusted in the user's own `CODEX_HOME` config, which lives in their home
   directory. Do not read it, do not write it, and do not report its state — say instead that trust
   is granted at install time and that `hooks/list` is where the user verifies it. Reporting a
   green hook layer without it would be the one claim this check exists to avoid making.

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
