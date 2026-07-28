# Runbook — Codex client-probe live pass

This runbook covers Steps 4–6 of the 00C task-5 brief. It is written for the
**live-execution operator**: someone with a real Codex CLI installation who
will run the probe, record observations, and publish evidence. Do not
fabricate observations. Do not create anything under
`docs/research/platform-spike/evidence/` until the live pass actually ran.

Task 5 (this dispatch) built the committed package and this runbook only. No
`codex plugin marketplace add` / `codex plugin add` was executed, and no
disposable Codex config root was created, while authoring this file — that is
this runbook's job for the next dispatch, not this one's.

## Deviation from the plan's literal wording — the CLI binds, not the GUI

The plan's Step 3 says "install it through the Plugins Directory in a new
ChatGPT desktop/Codex session as required by the tested build." The tested
build, **codex-cli 0.145.0**, ships a full `codex plugin` subcommand tree
(`marketplace add|list|upgrade|remove`, `add|list|remove`), verified with
`--help` on the probe host. That is the documented install mechanism of the
tested build, so this runbook drives the CLI:

```bash
codex plugin marketplace add <disposable-marketplace-root>
codex plugin marketplace list
codex plugin add kinglet-client-probe@kinglet-client-probe
codex plugin list
```

## MCP approval mode — `prompt`, never `approve`

The brief requires the probe MCP be enabled with approval mode `prompt`.
codex-cli 0.145.0's own `RawMcpServerConfig` struct (confirmed via `strings`
over the native binary) carries a `default_tools_approval_mode` field on
each MCP server entry, alongside `enabled_tools`/`disabled_tools`. The
binary's string table shows the value alphabet directly:
`approval_mode` → `prompt` | `writes` | `approve`.

The committed `.mcp.json` sets this explicitly on the `kinglet-client-probe`
server entry:

```json
"default_tools_approval_mode": "prompt"
```

**Never `approve`** — this disposable profile runs an unattended, untrusted
probe binary; `approve` would auto-approve every tool call without a human
in the loop, which is exactly the safety control the plan's disposable-profile
constraint exists to prevent. `writes` (approval only for write-shaped calls)
was considered and rejected too: the brief names `prompt` specifically, and
`prompt` is the only mode that gives an operator a chance to observe and
record `approvals.mutation` at the MCP layer, not just at the hook layer.

**Live pass action:** confirm that `codex plugin add` and `codex plugin
list`/`--json` actually reflect this setting once installed, and that a real
MCP tool call surfaces a prompt rather than auto-proceeding — this manifest
field has not been exercised against a live session yet.

## Validation — codex-cli's own bundled validator, not `codex plugin validate`

There is no `codex plugin validate` subcommand (checked with `--help`; see
below). codex-cli 0.145.0 does, however, ship a validator script inside its
own `plugin-creator` skill (`~/.codex/skills/.system/plugin-creator/scripts/
validate_plugin.py`) that "mirrors the workspace plugin ingestion schema" per
that skill's own `plugin-json-spec.md`. This is the closest thing to a
build-time correctness check the tested build offers, and it is authoritative
about `plugin.json`'s accepted top-level fields — critically, it **rejects**
a `hooks` field outright (`allowed_keys` does not include `hooks`) and
**requires** a full `interface` object (`displayName`, `shortDescription`,
`longDescription`, `developerName`, `category`, `capabilities`, and either
`defaultPrompt` or `default_prompt`).

This is why the committed `.codex-plugin/plugin.json` declares no `hooks`
field at all — `hooks.json` lives at the **plugin root**
(`spikes/platform/clients/codex/hooks.json`, not nested under `hooks/`),
auto-discovered the same way `figma`'s real installed plugin's root-level
`hooks.json` is, with no manifest reference. The wrapper script itself still
lives at `hooks/pre-mutation-hook.sh`; only the hook **manifest** moved.

Run this from the repo root to reproduce:

```bash
python3 ~/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py \
  spikes/platform/clients/codex
```

Expected: `Plugin validation passed: <path>`. This dispatch ran it and pasted
the real output — see the round-1 fix report appended to
`task-5-report.md`. Re-run it any time the manifest changes; it is a static
check with no side effects (it never calls `codex plugin add` and touches no
config root).

## Open question 1 — no documented `${PLUGIN_ROOT}` token was found

The brief asks to resolve the packaged executable with "Codex's documented
`${PLUGIN_ROOT}` token in hook and MCP command fields." That token was
**not found** in codex-cli 0.145.0, checked three independent ways on the
probe host:

1. The plugin-creator skill Codex itself ships (`~/.codex/skills/.system/
   plugin-creator`) documents a `plugin-json-spec.md` field guide for
   `plugin.json`. Its path-conventions section says only: "Path values
   should be relative and begin with `./`." No substitution token is
   mentioned anywhere in that spec.
2. Every real installed/cached plugin's `hooks.json` and `.mcp.json` found in
   `~/.codex/.tmp/plugins/plugins/*` on the probe host uses a **bare relative
   path**, not a token — e.g. `"command": "./scripts/post_write_figma_parity_check.sh"`
   (figma, replayio root-level `hooks.json`) and `"command": "node", "args":
   ["./mcp/server.mjs"], "cwd": "."` (openai-developers `.mcp.json`).
3. `strings` over the codex-cli native binary
   (`@openai/codex-linux-x64/.../bin/codex`) contains no `CODEX_PLUGIN_ROOT`
   string at all. It does contain `CLAUDE_PLUGIN_ROOT` and
   `CLAUDE_PLUGIN_DATA`, but those sit inside an unrelated managed-config
   (MDM) schema string cluster that also references
   `legacy-managed-config.toml` and `managed_config.toml` — an
   enterprise-policy interop concern with Claude Code, not a token Codex
   expands for its own plugins.

**Conclusion for this dispatch:** the committed root-level `hooks.json` and
`.mcp.json` use bare relative paths (`./hooks/pre-mutation-hook.sh`,
`./bin/kinglet-client-probe`), matching every real plugin observed on the
probe host, instead of fabricating a token that no source confirms exists.

**Live pass action:** Step 4's first observation must confirm how Codex
resolves these relative paths at hook/MCP invocation time — specifically,
whether the working directory Codex launches them from is the *installed
plugin cache* directory (as the brief's "assert the expanded path points
inside the installed plugin cache" implies) or the *disposable project*
directory. `hooks/pre-mutation-hook.sh` self-locates via `${BASH_SOURCE[0]}`
precisely because this was unconfirmed — record what actually happens.

## Update mechanism — documented, not guessed (corrected in fix round 1)

codex-cli 0.145.0's `plugin` subcommand tree has no `update` verb
(subcommands are exactly `add`, `list`, `marketplace`, `remove` — verified
with `--help`), and `codex plugin marketplace upgrade` only refreshes **Git**
marketplace snapshots; our marketplace source is `local`, read live off disk.

An earlier draft of this runbook read that absence as "no documented update
mechanism exists" and proposed re-running `codex plugin add` after a plain
numeric version bump (0.0.1 → 0.0.2), falling back to `remove`+`add`. That
was inference presented as fact: codex-cli 0.145.0 ships a **sibling
reference file** to the `plugin-json-spec.md` this package's schema is built
from — `~/.codex/skills/.system/plugin-creator/references/
installing-and-updating.md` — that documents the local-plugin update loop
end to end, verbatim:

> "Do not keep incrementing numeric version components just to trigger
> reinstall behavior."

The documented loop is a **cachebuster suffix**, not a version bump:

```text
<base-version>+codex.<token>
```

e.g. `0.0.1` → `0.0.1+codex.local-20260519-184516`. The reference ships a
helper for this: `scripts/update_plugin_cachebuster.py <plugin-path>`
(defaults to a UTC-timestamp token; only override with `--cachebuster` when a
workflow depends on a specific string). Reinstall is then just:

```bash
codex plugin add kinglet-client-probe@kinglet-client-probe
```

**Deviation from the brief's literal wording, recorded here:** the brief's
Step 4 sequence names the update target as version `0.0.2`. The documented
Codex-native mechanism does not bump the semver component at all — it
appends/replaces a `+codex.<token>` build-metadata suffix on the existing
`0.0.1` base. The live pass should use the **cachebuster form** (this is
what the tested build's own reference instructs, and semver build metadata
after `+` is not part of precedence, so `0.0.1+codex.<token>` is a strictly
correct evolution of `0.0.1`, not a regression of the brief's "0.0.2"
intent). Record the exact string codex-cli reports for the version field
after the update as the `install.update` evidence, whatever it reads.

## The hook block mechanism — confirmed, not assumed

`codex plugin add --help` and friends say nothing about hook semantics, but
the codex-cli binary's own embedded diagnostic strings do. `strings` over the
binary surfaces (verbatim):

```
PreToolUse hook exited with code 2 but did not write a blocking reason to stderr
```

This confirms, directly from the tested build, that:
- `PreToolUse` is a real, supported hook event name (not assumed by analogy
  with Claude Code).
- **Exit code 2 is the block signal** — the same convention Claude Code uses.
- Codex additionally expects the reason on **stderr** when blocking, exactly
  like Claude Code's contract.

`hooks/pre-mutation-hook.sh` implements this: it always exits 0 on
`decision=="allow"`, and exits 2 with a stderr message on
`decision=="deny"`. The probe binary itself always exits 0 (see
`shared/hooks/hook-policy.json` `overlay_contract`); the wrapper is the
translation layer.

One real plugin observed on the probe host (`figma/hooks.json`) uses
`matcher: "Write|Edit"` for a `PostToolUse` hook — the **same tool-name
vocabulary Claude Code uses** — which is why this package's `PreToolUse`
matcher is also `Write|Edit` rather than a guessed Codex-native tool name
(e.g. `apply_patch`/`shell`). This still needs Step 4 confirmation: it is
possible Codex's own file-edit tool surfaces under a different name at
runtime even though the matcher vocabulary in shipped manifests reads the
same as Claude's.

## Prerequisites

- `codex --version` reports a supported Codex CLI version (documented at
  probe time; this dispatch observed `codex-cli 0.145.0`).
- `jq --version` succeeds — the pre-mutation hook requires `jq` at runtime.
- The native probe binary has been built:
  ```bash
  bash spikes/platform/clients/probe-host/build.sh
  ```
- A disposable Unity-shaped project has been created:
  ```bash
  bash spikes/platform/clients/shared/create-project.sh /tmp/kinglet-probe-project
  ```
  `create-project.sh` writes a project-level instructions file to the
  project root. For `instructions.project`, confirm during the live pass
  which filename Codex actually loads automatically (Claude Code loads
  `CLAUDE.md`; Codex's equivalent project-instructions filename — likely
  `AGENTS.md`, observed at `~/.codex/AGENTS.md` on the probe host as a
  *personal*-scope file — must be confirmed for *project* scope during Step
  4, not assumed here).

## Step A — Assemble the disposable plugin package

The committed overlay at `spikes/platform/clients/codex/` does **not**
include the shared skill or agent — they are copied at probe-build time to
avoid duplicating content committed elsewhere, exactly as the Claude Code
overlay does.

Run these commands from the repo root to assemble a self-contained package:

```bash
PROBE_PKG=/tmp/kinglet-codex-probe-pkg

# Copy the committed overlay
cp -r spikes/platform/clients/codex/. "$PROBE_PKG"

# Copy shared skill (prompt IDs: workflow-natural-language-01)
mkdir -p "$PROBE_PKG/skills/kinglet-capability-probe"
cp spikes/platform/clients/shared/skills/kinglet-capability-probe/SKILL.md \
   "$PROBE_PKG/skills/kinglet-capability-probe/SKILL.md"

# Copy shared agent (prompt ID: agent-delegation-01)
mkdir -p "$PROBE_PKG/agents"
cp spikes/platform/clients/shared/agents/kinglet-capability-reviewer.agent.md \
   "$PROBE_PKG/agents/kinglet-capability-reviewer.agent.md"

# Copy shared rule into package (for reference — see note below on instructions.project)
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

The assembled package lives at `/tmp/kinglet-codex-probe-pkg` (or your chosen
`PROBE_PKG` path). It now contains:
- `.codex-plugin/plugin.json` — plugin manifest (name: kinglet-client-probe,
  version: 0.0.1, full `interface` block, no `hooks` field — see "Validation"
  above)
- `.agents/plugins/marketplace.json` — local marketplace entry (source path `./`)
- `hooks.json` — PreToolUse hook config, at plugin **root** (auto-discovered;
  not referenced from `plugin.json`)
- `hooks/pre-mutation-hook.sh` — deny-translation wrapper
- `.mcp.json` — local MCP server config (`mcpServers` wrapper key, matching
  the schema of every real `.mcp.json` observed on the probe host;
  `default_tools_approval_mode: "prompt"` set on the server entry)
- `skills/kinglet-capability-probe/SKILL.md` — capability workflow skill
- `agents/kinglet-capability-reviewer.agent.md` — reviewer agent
- `rules/kinglet-capability-probe.md` — receipt schema rule (reference copy)
- `bin/kinglet-client-probe` — native probe binary

**Note on `instructions.project`:** as with Claude Code, the actual mechanism
for this case is whatever project-instructions file Codex loads
automatically from the project root. `create-project.sh` writes the shared
rule content there; the live pass must confirm the filename Codex expects at
*project* scope and adjust `create-project.sh`'s output name if it differs
from what the script currently writes.

## Step B — Register the marketplace and install the plugin

Provision a disposable Codex config root first. `CODEX_HOME` is Codex's
config-root override (analogous to Claude Code's `CLAUDE_CONFIG_DIR`), and is
already in the sanitization sweep's `DISPOSABLE_CONFIG_VARS` allowlist:

```bash
export KINGLET_LIVE_BASE=/some/disposable/dir     # required — no default
export CODEX_HOME="$KINGLET_LIVE_BASE/cfg"
mkdir -p "$CODEX_HOME"
```

Confirm `$CODEX_HOME` resolves outside the operator's real `~/.codex` before
running anything — never point this at a real config root. Then:

```bash
# Register the local marketplace (use the absolute path to the assembled package)
codex plugin marketplace add /tmp/kinglet-codex-probe-pkg

# Verify registration
codex plugin marketplace list

# Install the plugin from the local marketplace
codex plugin add kinglet-client-probe@kinglet-client-probe

# Verify installation
codex plugin list
```

Record the output of `codex plugin list`. It must show `kinglet-client-probe`
at version `0.0.1`. This satisfies `install.discover` (first cold discovery).

**If `codex plugin add` fails or the plugin does not appear in `codex plugin
list`, stop.** No case observation gathered under a non-loading plugin is
valid — mirror the same discipline Claude Code's runbook applies to `claude
plugin list` reporting `failed to load`.

## Step C — Start a new session in the disposable project

**Important:** Start a **new session** (do not reuse the terminal from Step
B). The `workflow.natural-language` and `install.discover` cases require the
plugin to be loaded from a cold start.

```bash
cd /tmp/kinglet-probe-project
codex
```

Record `codex --version` output before starting.

## Step D — Run the four synthetic prompts

Run each prompt in order inside the session. After each prompt, record the
result as evidence for the cases listed. Do not reuse a session between
prompts — start fresh if the previous prompt's state would interfere.

### Prompt workflow-natural-language-01

```
In this disposable Unity project, use the installed Kinglet capability workflow
to inspect the Unity version and write only the receipt that workflow defines.
Do not search for the skill by filename.
```

Expected behavior:
- Codex discovers the `kinglet-capability-probe` skill via its
  natural-language description (not by filename lookup).
- Codex invokes the native binary:
  `kinglet-client-probe exec --project <project-root> --output <project-root>/.kinglet-probe/receipts/workflow.json`
- Codex returns exactly: `KINGLET_CLIENT_PROBE_OK 6000.3.11f1`

Cases evidenced: `workflow.natural-language`, `executable.local`, `structured-result`,
`instructions.project`

### Prompt agent-delegation-01

```
Ask the installed Kinglet capability reviewer to report whether the project
marker and Unity version agree. Save its structured receipt.
```

Expected behavior:
- Codex delegates to the `kinglet-capability-reviewer` sub-agent.
- The agent reads `.kinglet-probe/project-marker.txt` and
  `ProjectSettings/ProjectVersion.txt`.
- The agent writes `.kinglet-probe/receipts/agent.json` with
  `"agreement": true`.

Cases evidenced: `agents.delegation`, `structured-result`

**Do not infer an agents pass from skills.** If Codex only ran the skill
workflow and never actually delegated to a distinct sub-agent context, record
`agents.delegation` as failed or inconclusive — a skill invocation is not a
delegation.

### Prompt mutation-block-01

```
Replace PROTECTED with MUTATED in Assets/Protected.txt.
```

Expected behavior:
- Codex attempts a Write or Edit on `Assets/Protected.txt`.
- The `pre-mutation-hook.sh` wrapper fires, calls the probe binary's `hook`
  subcommand with `--event -`, receives `{"decision":"deny",...}`, and exits 2.
- **Exit 2 is Codex's PreToolUse block signal** (confirmed from the binary's
  own diagnostic strings — see above).
- Codex aborts the mutation and reports it was blocked.
- `Assets/Protected.txt` still contains `PROTECTED`.

Cases evidenced: `hooks.pre-mutation-block`, `approvals.mutation`

**A file that stayed `PROTECTED` is NOT by itself evidence for
`hooks.pre-mutation-block`,** exactly as on Claude Code: Codex may read a
project instructions file, conclude the file is protected, and never call
Write/Edit at all — so the hook never fires. To score this case you must find
the hook's own deny in the transcript (a `PreToolUse` block on a Write/Edit
whose path ends in `Assets/Protected.txt`), not merely an unchanged file. A
refusal that cites project instructions is evidence for `instructions.project`
instead — record it there.

### Prompt mcp-call-01

```
Use the installed kinglet-client-probe MCP tool to read the disposable project
marker and save the structured result.
```

Expected behavior:
- Codex discovers the MCP server registered as `kinglet-client-probe`.
- Codex calls the `kinglet_probe_read_marker` tool with `project_root` set to
  the disposable project path.
- The tool returns the receipt JSON.
- Codex saves the result to `.kinglet-probe/receipts/mcp.json` (or the path
  Codex chooses, which must be recorded as evidence).

Cases evidenced: `mcp.discover-call`, `structured-result`

## Step E — Update via the documented cachebuster loop

Per "Update mechanism — documented, not guessed" above, this is the
tested build's own reference procedure
(`~/.codex/skills/.system/plugin-creator/references/installing-and-updating.md`),
not a version-number bump:

```bash
python3 ~/.codex/skills/.system/plugin-creator/scripts/update_plugin_cachebuster.py \
  /tmp/kinglet-codex-probe-pkg
```

Omit `--cachebuster` to let the helper default to a UTC-timestamp token —
the reference's recommended path for routine local iteration. This rewrites
the `version` field of `/tmp/kinglet-codex-probe-pkg/.codex-plugin/plugin.json`
to `0.0.1+codex.<token>` in place (preserving the `0.0.1` prefix — the
reference's "Cachebuster Policy" is explicit that the prefix is everything
before `+`, and to replace rather than append a second `+codex.` suffix on
repeat runs).

The reference's Update Loop step 2-3 reads the marketplace name from the
**personal** marketplace file (`~/.agents/plugins/marketplace.json`) via
`scripts/read_marketplace_name.py`. This package was registered as a
**local, non-personal** marketplace in Step B
(`spikes/platform/clients/codex/.agents/plugins/marketplace.json`, added via
`codex plugin marketplace add`, not the implicit personal-marketplace path),
so the reference's own fallback applies instead: "If the plugin is not using
the personal marketplace file... reinstall from that marketplace name".
Reinstall from the marketplace name already known from Step B:

```bash
codex plugin add kinglet-client-probe@kinglet-client-probe
codex plugin list
```

Record the version string `codex plugin list` reports after this — it
should read `0.0.1+codex.<token>`, not `0.0.2`. If it does not update at
all, that is itself the `install.update` observation (failed, not
inconclusive — the documented mechanism was followed exactly). Per the
reference's closing step, start a **new thread** afterward before testing
the updated plugin, so Codex picks up the new skills/tools.

This satisfies `install.update`.

## Step F — Scope resolution check

This tests `scope.project-user`. Codex's plugin scope model (personal vs.
repo/team, per the `plugin-json-spec.md` marketplace guidance: `~/.agents/
plugins/marketplace.json` for personal, `<repo-root>/.agents/plugins/
marketplace.json` for repo/team) has not been exercised live yet. Record:
- Whether the plugin installed via the local marketplace in Step B is visible
  from a different project directory (this determines whether the install
  behaved as personal-scope or project-scope).
- The exact scope flag or config surface, if any, that Codex's `plugin add`
  exposes for choosing project vs. personal scope (`--help` output for
  `codex plugin add` at capture time showed no `--scope` flag, unlike
  `claude plugin install --scope local`; confirm whether scope is instead
  implied by which marketplace config file — personal `~/.agents/plugins/
  marketplace.json` vs. repo `<repo-root>/.agents/plugins/marketplace.json`
  — was registered in Step B).

Open a second session in a different directory and run `codex plugin list`.
Record both outputs.

## Step G — Uninstall and confirm removal

```bash
codex plugin remove kinglet-client-probe
codex plugin list
```

Record the output of `codex plugin list` after removal. It must NOT show
`kinglet-client-probe`. This satisfies `install.remove` and confirms
`no_residual_capabilities`.

**Important:** Start a **new session** after removal before confirming
discovery disappears. Do not reuse the session in which the plugin was
active.

## Evidence recording

For each case, record:
- The exact prompt sent (use the text above verbatim — sourced from
  `spikes/platform/clients/contracts/prompts-v1.json`).
- The session transcript (copy from Codex's output).
- The receipt file contents (for structured-result cases).
- Any permission prompts shown (for `approvals.mutation`).
- The `codex --version` value.
- The scope actually observed in Step F.

Publish each host result through the 00A evidence harness. Do not include any
user home paths, tokens, or credentials in evidence records. `$CODEX_HOME`
is the sanctioned way to name the disposable profile — never write an
absolute home path.

## Twelve capability cases

`agents.delegation`, `approvals.mutation`, `executable.local`,
`hooks.pre-mutation-block`, `install.discover`, `install.remove`,
`install.update`, `instructions.project`, `mcp.discover-call`,
`scope.project-user`, `structured-result`, `workflow.natural-language`.

Grade each as Native, Emulated, Unavailable, failed, or inconclusive per
`spikes/platform/clients/contracts/cases-v1.json`. Do not infer an agents
pass from skills.
