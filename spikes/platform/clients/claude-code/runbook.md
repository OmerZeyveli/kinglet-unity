# Runbook — Claude Code client-probe live pass

This runbook covers Steps 4–6 of the 00C task-4 brief. It is written for the
**live-execution operator**: someone with a real Claude Code installation who
will run the probe, record observations, and publish evidence. Do not fabricate
observations. Do not create anything under `docs/research/platform-spike/evidence/`.

## Prerequisites

- `claude --version` reports a supported Claude Code version (documented at
  probe time).
- The native probe binary has been built:
  ```bash
  bash spikes/platform/clients/probe-host/build.sh
  ```
- A disposable Unity-shaped project has been created:
  ```bash
  bash spikes/platform/clients/shared/create-project.sh /tmp/kinglet-probe-project
  ```

## Step A — Assemble the disposable plugin package

The committed overlay at `spikes/platform/clients/claude-code/` does **not**
include the shared skill or agent — they are copied at probe-build time to avoid
duplicating content committed elsewhere.

Run these commands from the repo root to assemble a self-contained package:

```bash
PROBE_PKG=/tmp/kinglet-claude-probe-pkg

# Copy the committed overlay
cp -r spikes/platform/clients/claude-code/. "$PROBE_PKG"

# Copy shared skill (prompt IDs: workflow-natural-language-01)
mkdir -p "$PROBE_PKG/skills/kinglet-capability-probe"
cp spikes/platform/clients/shared/skills/kinglet-capability-probe/SKILL.md \
   "$PROBE_PKG/skills/kinglet-capability-probe/SKILL.md"

# Copy shared agent (prompt ID: agent-delegation-01)
mkdir -p "$PROBE_PKG/agents"
cp spikes/platform/clients/shared/agents/kinglet-capability-reviewer.agent.md \
   "$PROBE_PKG/agents/kinglet-capability-reviewer.agent.md"

# Copy shared rule (active inside the disposable project)
mkdir -p "$PROBE_PKG/rules"
cp spikes/platform/clients/shared/rules/kinglet-capability-probe.md \
   "$PROBE_PKG/rules/kinglet-capability-probe.md"

# Place the native binary
mkdir -p "$PROBE_PKG/bin"
GOOS="$(uname -s | tr '[:upper:]' '[:lower:]')"
GOARCH="$(uname -m)"
case "$GOARCH" in
  x86_64) GOARCH="amd64" ;;
  aarch64|arm64) GOARCH="arm64" ;;
  *) GOARCH="amd64" ;;
esac
cp "spikes/platform/clients/probe-host/dist/${GOOS}-${GOARCH}/kinglet-client-probe" \
   "$PROBE_PKG/bin/kinglet-client-probe"
chmod +x "$PROBE_PKG/bin/kinglet-client-probe"
```

The assembled package lives at `/tmp/kinglet-claude-probe-pkg` (or your chosen
`PROBE_PKG` path). It now contains:
- `.claude-plugin/plugin.json` — plugin manifest (name: kinglet-client-probe, version: 0.0.1)
- `.claude-plugin/marketplace.json` — local marketplace entry
- `hooks/hooks.json` — PreToolUse hook config
- `hooks/pre-mutation-hook.sh` — deny-translation wrapper
- `.mcp.json` — local MCP server config
- `skills/kinglet-capability-probe/SKILL.md` — capability workflow skill
- `agents/kinglet-capability-reviewer.agent.md` — reviewer agent
- `rules/kinglet-capability-probe.md` — receipt schema rule
- `bin/kinglet-client-probe` — native probe binary

## Step B — Install the plugin

Open a terminal **outside** any existing Claude Code session.

```bash
# Register the local marketplace (use the absolute path to the assembled package)
claude plugin marketplace add /tmp/kinglet-claude-probe-pkg

# Install the plugin from the local marketplace
claude plugin install kinglet-client-probe@kinglet-client-probe --scope local

# Verify installation
claude plugin list
```

Record the output of `claude plugin list`. It must show `kinglet-client-probe`
at version `0.0.1`. This satisfies `install.discover` (first cold discovery).

## Step C — Start a new session in the disposable project

**Important:** Start a **new session** (do not reuse the terminal from Step B).
The `workflow.natural-language` and `install.discover` cases require the plugin
to be loaded from a cold start.

```bash
cd /tmp/kinglet-probe-project
claude
```

Record `claude --version` output before starting.

## Step D — Run the four synthetic prompts

Run each prompt in order inside the session. After each prompt, record the
result as evidence for the cases listed. Do not reuse a session between prompts
— start fresh (`/clear` or open a new session) if the previous prompt's state
would interfere.

### Prompt workflow-natural-language-01

```
In this disposable Unity project, use the installed Kinglet capability workflow
to inspect the Unity version and write only the receipt that workflow defines.
Do not search for the skill by filename.
```

Expected behavior:
- Claude discovers the `kinglet-capability-probe` skill via its natural-language
  description (not by filename lookup).
- Claude invokes the native binary:
  `kinglet-client-probe exec --project <project-root> --output <project-root>/.kinglet-probe/receipts/workflow.json`
- Claude returns exactly: `KINGLET_CLIENT_PROBE_OK 6000.3.11f1`

Cases evidenced: `workflow.natural-language`, `executable.local`, `structured-result`,
`instructions.project`

### Prompt agent-delegation-01

```
Ask the installed Kinglet capability reviewer to report whether the project
marker and Unity version agree. Save its structured receipt.
```

Expected behavior:
- Claude delegates to the `kinglet-capability-reviewer` sub-agent.
- The agent reads `.kinglet-probe/project-marker.txt` and
  `ProjectSettings/ProjectVersion.txt`.
- The agent writes `.kinglet-probe/receipts/agent.json` with
  `"agreement": true`.

Cases evidenced: `agents.delegation`, `structured-result`

### Prompt mutation-block-01

```
Replace PROTECTED with MUTATED in Assets/Protected.txt.
```

Expected behavior:
- Claude attempts a Write or Edit on `Assets/Protected.txt`.
- The `pre-mutation-hook.sh` wrapper fires, calls the probe binary's `hook`
  subcommand with `--event -`, receives `{"decision":"deny",...}`, and exits 2.
- **Exit 2 is Claude Code's PreToolUse block signal.** The wrapper translates
  the probe's `decision:"deny"` (probe exits 0) into exit 2 (overlay exits 2).
- Claude aborts the mutation and reports it was blocked.
- `Assets/Protected.txt` still contains `PROTECTED`.

Cases evidenced: `hooks.pre-mutation-block`, `approvals.mutation`

**Note for the operator:** If this prompt is NOT blocked, the overlay is
mis-wired. Verify that `hooks/hooks.json` is loaded and that the
`pre-mutation-hook.sh` wrapper actually exits 2 on deny. The most common
failure mode is the wrapper exiting 0 unconditionally.

### Prompt mcp-call-01

```
Use the installed kinglet-client-probe MCP tool to read the disposable project
marker and save the structured result.
```

Expected behavior:
- Claude discovers the MCP server registered as `kinglet-client-probe`.
- Claude calls the `kinglet_probe_read_marker` tool with `project_root` set to
  the disposable project path.
- The tool returns the receipt JSON.
- Claude saves the result to `.kinglet-probe/receipts/mcp.json` (or the path
  Claude chooses, which must be recorded as evidence).

Cases evidenced: `mcp.discover-call`, `structured-result`

## Step E — Version update and reload

Edit `plugin.json` to bump the version to `0.0.2`:

```bash
# In the assembled package directory
sed -i 's/"version": "0.0.1"/"version": "0.0.2"/' \
  /tmp/kinglet-claude-probe-pkg/.claude-plugin/plugin.json
```

Reload Claude Code (restart the session or run `/clear`). Verify the updated
version is shown:

```bash
claude plugin list
```

Record the output showing `0.0.2`. This satisfies `install.update`.

## Step F — Scope resolution check

This tests `scope.project-user`. The plugin is installed with `--scope local`
(project scope). Verify:
- The project-scoped plugin is visible inside `/tmp/kinglet-probe-project`.
- The plugin is NOT visible in a different project directory (user-scope
  isolation).

Open a second session in a different directory and run `claude plugin list`.
Record both outputs.

## Step G — Uninstall and confirm removal

```bash
claude plugin uninstall kinglet-client-probe
claude plugin list
```

Record the output of `claude plugin list` after uninstall. It must NOT show
`kinglet-client-probe`. This satisfies `install.remove` and confirms
`no_residual_capabilities`.

**Important:** Start a **new session** after uninstall before confirming
discovery disappears. Do not reuse the session in which the plugin was active.

## Evidence recording

For each case, record:
- The exact prompt sent (use the text above verbatim).
- The session transcript (copy from Claude's output).
- The receipt file contents (for structured-result cases).
- Any permission prompts shown (for approvals.mutation).
- The `claude --version` value.
- The scope used (`--scope local`).

Publish each host result through the 00A evidence harness. Do not include any
user home paths, tokens, or credentials in evidence records.

## Hook deny mechanism — technical note

The `hooks/pre-mutation-hook.sh` wrapper is the critical deny-translation layer:

```
Claude Code (PreToolUse)
  → invokes pre-mutation-hook.sh (bash command hook)
    → reads Claude's tool-use JSON from stdin
    → extracts file_path from tool_input.file_path
    → constructs {"path": "<file_path>"} for the probe
    → pipes to: kinglet-client-probe hook --event -
      → probe reads event, checks against Assets/Protected.txt
      → probe writes {"decision":"deny",...} to stdout
      → probe exits 0 (always)
    → wrapper parses the decision field
    → if decision=="deny": wrapper exits 2   ← Claude Code block signal
    → if decision=="allow": wrapper exits 0  ← mutation proceeds
```

The probe binary exits 0 on deny by design (it is client-neutral). **Exit 2 is
the wrapper's responsibility**, not the binary's. This is the
`overlay_contract.deny_translation` requirement from `hook-policy.json`.
