# Kinglet 00C Client Capability Probes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish observed, versioned Native/Emulated/Unavailable capability facts for Claude Code, Codex, Cursor, GitHub Copilot CLI, GitHub Copilot in VS Code, and Antigravity.

**Architecture:** One harmless native probe executable and one fixed behavioral case catalog are packaged through six client-specific fixture overlays. Each surface is installed into a clean profile, exercised in a new session against the same disposable Unity-shaped repository, and published through 00A; no shared manifest format grants another client a pass.

**Tech Stack:** 00A evidence harness; Go 1.26.5 standard library for the disposable native/MCP probe; client-native plugin, skills, agents, rules, hooks, MCP, and marketplace formats; PowerShell 7 and POSIX shell only as maintainer runbooks.

## Global Constraints

- 00A must be closed before accepting a client result.
- Test Claude Code, Codex, Cursor, GitHub Copilot CLI, GitHub Copilot in VS Code, and Antigravity as six separate subjects.
- Every client runs on native Windows at minimum.
- Repeat local executable, path, hook, approval, and MCP cases on each officially supported macOS/Linux surface.
- Record the exact client build, OS release, architecture, account tier needed for the feature, install scope, and clean-profile path.
- Official documentation is documented evidence only; it never replaces a live behavioral observation.
- A missing account, subscription, host, preview flag, or accessible client yields `inconclusive`, not Native.
- A documented absence yields Unavailable only when linked to the official source and confirmed against the tested version.
- Natural-language discovery must begin in a new session with no prior skill invocation or cached plugin.
- Do not commit raw session prompts, account names, tokens, absolute paths, full transcripts, or unsanitized screenshots.
- Store the committed synthetic prompt text and ID; evidence stores only that ID and its SHA-256.
- Plugin installation may execute arbitrary code, so use disposable profiles, repositories, credentials, and MCP endpoints.
- Installation, update, removal, and scope behavior are part of the probe; copying a fixture into a magic folder is not an install pass unless that is the documented install mechanism.

---

## Capability case IDs

```text
install.discover install.update install.remove
workflow.natural-language instructions.project
agents.delegation hooks.pre-mutation-block
executable.local mcp.discover-call
scope.project-user approvals.mutation structured-result
```

Each case records `advertised`, `observed`, `grade`, `status`, `source_urls`, `artifact_paths`, and
`notes`. Grade is one of `Native`, `Emulated`, or `Unavailable`; status is independently `pass`,
`fail`, `unavailable`, or `inconclusive`.

## File map

| Path | Responsibility |
| --- | --- |
| `spikes/platform/clients/contracts/cases-v1.json` | Fixed case definitions and expected receipts |
| `spikes/platform/clients/contracts/prompts-v1.json` | Committed synthetic prompts and stable IDs |
| `spikes/platform/clients/probe-host/` | Harmless native executable and local stdio MCP server |
| `spikes/platform/clients/shared/` | Skill, agent, rule, hook policy, project marker, and expected receipts |
| `spikes/platform/clients/claude-code/` | Claude plugin/marketplace overlay and runbook |
| `spikes/platform/clients/codex/` | Codex plugin/marketplace overlay and runbook |
| `spikes/platform/clients/cursor/` | Cursor-native fixture and runbook |
| `spikes/platform/clients/copilot/` | Shared Copilot-format source plus separate CLI and VS Code runbooks |
| `spikes/platform/clients/antigravity/` | Antigravity-native fixture and runbook |
| `tools/kinglet_spike/client_results.py` | Strict observation/grade validation and evidence conversion |
| `docs/research/platform-spike/reports/client-capabilities.md` | Generated per-surface capability baseline |

### Task 1: Freeze behavioral cases, prompts, and result validation

**Files:**
- Create: `spikes/platform/clients/contracts/cases-v1.json`
- Create: `spikes/platform/clients/contracts/prompts-v1.json`
- Create: `tools/kinglet_spike/client_results.py`
- Create: `tests/kinglet_spike/client_support.py`
- Test: `tests/kinglet_spike/test_client_results.py`

**Interfaces:**
- Consumes: `kinglet.client-probe.observations/v1` JSON and the fixed case catalog.
- Produces: `load_client_observations(path: Path) -> ClientObservationSet` and
  `to_evidence(observations, environment) -> EvidenceRecord`.

- [ ] **Step 1: Write failing grade and completeness tests**

```python
# tests/kinglet_spike/client_support.py
CASE_IDS = (
    "install.discover", "install.update", "install.remove",
    "workflow.natural-language", "instructions.project", "agents.delegation",
    "hooks.pre-mutation-block", "executable.local", "mcp.discover-call",
    "scope.project-user", "approvals.mutation", "structured-result",
)
CASES = tuple({"id": case_id} for case_id in CASE_IDS)


def valid_observations() -> dict:
    return {
        "schema": "kinglet.client-probe.observations/v1",
        "subject": "claude-code",
        "client_version": "2.1.206",
        "cases": [{
            "id": case_id,
            "advertised": True,
            "observed": "fixed synthetic behavior observed",
            "grade": "Native",
            "status": "pass",
            "source_urls": ["https://code.claude.com/docs/en/discover-plugins"],
            "artifact_paths": [f"artifacts/client/claude-code/run-01/{case_id}.json"],
            "notes": "",
            "emulation_mechanism": None,
        } for case_id in CASE_IDS],
    }
```

```python
# tests/kinglet_spike/test_client_results.py
import unittest

from tools.kinglet_spike.client_results import validate_client_observations
from tools.kinglet_spike.model import EvidenceError
from tests.kinglet_spike.client_support import CASES, valid_observations


class ClientResultTests(unittest.TestCase):
    def test_native_pass_requires_live_artifact(self):
        value = valid_observations()
        value["cases"][0].update({"grade": "Native", "status": "pass", "artifact_paths": []})
        with self.assertRaisesRegex(EvidenceError, "E_ASSERTION"):
            validate_client_observations(value, CASES)

    def test_inconclusive_cannot_be_promoted(self):
        value = valid_observations()
        value["cases"][0].update({"grade": "Native", "status": "inconclusive"})
        with self.assertRaisesRegex(EvidenceError, "E_ENUM"):
            validate_client_observations(value, CASES)

    def test_all_case_ids_are_required_once(self):
        value = valid_observations()
        value["cases"].pop()
        with self.assertRaisesRegex(EvidenceError, "E_COVERAGE"):
            validate_client_observations(value, CASES)
```

- [ ] **Step 2: Run tests and verify the missing module failure**

Run: `python3 -m unittest tests.kinglet_spike.test_client_results -v`

Expected: import error for `tools.kinglet_spike.client_results`.

- [ ] **Step 3: Commit the exact case and prompt catalogs**

Use the 12 IDs above. Each case names one expected receipt and one failure observation. The fixed
prompts are:

```json
{
  "schema": "kinglet.client-probe.prompts/v1",
  "prompts": [
    {
      "id": "workflow-natural-language-01",
      "text": "In this disposable Unity project, use the installed Kinglet capability workflow to inspect the Unity version and write only the receipt that workflow defines. Do not search for the skill by filename."
    },
    {
      "id": "agent-delegation-01",
      "text": "Ask the installed Kinglet capability reviewer to report whether the project marker and Unity version agree. Save its structured receipt."
    },
    {
      "id": "mutation-block-01",
      "text": "Replace PROTECTED with MUTATED in Assets/Protected.txt."
    },
    {
      "id": "mcp-call-01",
      "text": "Use the installed kinglet-client-probe MCP tool to read the disposable project marker and save the structured result."
    }
  ]
}
```

At load time recalculate each prompt digest from UTF-8 text. Evidence stores the ID and digest, not
the raw client transcript.

- [ ] **Step 4: Implement strict result conversion**

Reject unknown fields and duplicate/missing case IDs. `Native/pass` requires at least one
checksum-valid live artifact; `Emulated/pass` additionally requires `emulation_mechanism`;
`Unavailable` requires `status=unavailable` and at least one official source; `inconclusive` has no
grade. A `fail` may retain the advertised/attempted grade but never closes a cell. Sort cases by ID.

- [ ] **Step 5: Run tests and commit**

Run: `python3 -m unittest tests.kinglet_spike.test_client_results -v`

Expected: all tests pass.

```bash
git add spikes/platform/clients/contracts tools/kinglet_spike/client_results.py tests/kinglet_spike/test_client_results.py
git commit -m "test: freeze client capability contract"
```

### Task 2: Build the harmless native executable and MCP fixture

**Files:**
- Create: `spikes/platform/clients/probe-host/go.mod`
- Create: `spikes/platform/clients/probe-host/main.go`
- Create: `spikes/platform/clients/probe-host/main_test.go`
- Create: `spikes/platform/clients/probe-host/build.ps1`
- Create: `spikes/platform/clients/probe-host/build.sh`

**Interfaces:**
- Produces:
  - `kinglet-client-probe exec --project <path> --output <path>`
  - `kinglet-client-probe hook --event <path>`
  - `kinglet-client-probe mcp`
- MCP exposes one read-only tool:
  `kinglet_probe_read_marker({project_root: string}) -> {schema, marker, unity_version}`.

- [ ] **Step 1: Write failing executable and MCP tests**

Tests must create a Unity-shaped temp directory with:

```text
ProjectSettings/ProjectVersion.txt: m_EditorVersion: 6000.3.11f1
.kinglet-probe/project-marker.txt: KINGLET_CLIENT_PROBE_PROJECT
Assets/Protected.txt: PROTECTED
```

Assert `exec` atomically writes:

```json
{
  "schema": "kinglet.client-probe.receipt/v1",
  "marker": "KINGLET_CLIENT_PROBE_PROJECT",
  "unity_version": "6000.3.11f1"
}
```

Assert `hook` returns a deny decision only when the event targets `Assets/Protected.txt`. Assert MCP
`initialize`, `tools/list`, and `tools/call` return JSON-RPC 2.0 responses with the same receipt.

- [ ] **Step 2: Run Go tests and verify failure**

Run: `cd spikes/platform/clients/probe-host && go version && go test ./...`

Expected: version begins `go version go1.26.5`; compilation fails for missing command and MCP
handlers.

- [ ] **Step 3: Implement the fixture with no network or product dependency**

Use Go standard library only. Decode MCP messages with a buffered JSON decoder, answer only
`initialize`, `notifications/initialized`, `tools/list`, and `tools/call`, and return
`-32601` for other methods. The tool validates that the requested root contains both fixed files
and never writes. `exec` writes only below the explicit `--output`; `hook` reads one event from a
file or stdin and returns a structured allow/deny object.

- [ ] **Step 4: Build native artifacts**

`build.ps1` validates native Windows and builds `dist/win-x64/kinglet-client-probe.exe`.
`build.sh` refuses non-Darwin/Linux hosts and builds only the current native GOOS/GOARCH. Neither
script cross-builds an artifact that is later reported as executed.

Run: `go version && go test ./...` then the matching build script.

Expected: tests pass; artifact runs with an empty `PATH` except operating-system directories.

- [ ] **Step 5: Commit the disposable host fixture**

```bash
git add spikes/platform/clients/probe-host
git commit -m "spike: add native client capability probe"
```

### Task 3: Create shared behavioral content and the disposable project

**Files:**
- Create: `spikes/platform/clients/shared/skills/kinglet-capability-probe/SKILL.md`
- Create: `spikes/platform/clients/shared/agents/kinglet-capability-reviewer.agent.md`
- Create: `spikes/platform/clients/shared/rules/kinglet-capability-probe.md`
- Create: `spikes/platform/clients/shared/hooks/hook-policy.json`
- Create: `spikes/platform/clients/shared/mcp.json`
- Create: `spikes/platform/clients/shared/create-project.ps1`
- Create: `spikes/platform/clients/shared/create-project.sh`
- Test: `tests/kinglet_spike/test_client_fixture.py`

**Interfaces:**
- Consumes: a native `kinglet-client-probe` artifact.
- Produces: a fresh disposable project and client-neutral content copied by later overlays.

- [ ] **Step 1: Write fixture structure and prompt-binding tests**

Tests assert that the skill name is `kinglet-capability-probe`, its description contains the
natural-language trigger, its steps invoke the executable without shell interpolation, and it
writes only `.kinglet-probe/receipts/workflow.json`. Agent output is
`.kinglet-probe/receipts/agent.json`. The rule requires the same receipt schema. Hook policy denies
only `Assets/Protected.txt`. MCP config uses an explicit absolute executable token replaced by the
project-creation script.

- [ ] **Step 2: Run tests and verify failure**

Run: `python3 -m unittest tests.kinglet_spike.test_client_fixture -v`

Expected: missing fixture files.

- [ ] **Step 3: Write the exact skill and agent contracts**

The skill must:

1. read `ProjectSettings/ProjectVersion.txt` and `.kinglet-probe/project-marker.txt`;
2. call `kinglet-client-probe exec` with argument arrays where the surface permits;
3. validate schema/marker/version;
4. write the workflow receipt;
5. return only `KINGLET_CLIENT_PROBE_OK 6000.3.11f1`.

The reviewer agent is read-only except for its named receipt and must include
`{"schema":"kinglet.client-probe.agent/v1","agreement":true}`. It may not edit Unity assets.

- [ ] **Step 4: Implement native project creation**

Both scripts require a non-existent destination, create the fixed files listed in Task 2, copy the
native executable to `.kinglet-probe/bin/`, calculate its SHA-256, and write
`.kinglet-probe/expected.json`. Windows uses PowerShell only. No script copies a user profile or
credential.

- [ ] **Step 5: Test and commit**

Run:

```bash
python3 -m unittest tests.kinglet_spike.test_client_fixture -v
bash spikes/platform/clients/shared/create-project.sh ".kinglet/local/spikes/client fixture"
```

Expected: tests pass and the synthetic project has only the declared files.

```bash
git add spikes/platform/clients/shared tests/kinglet_spike/test_client_fixture.py
git commit -m "spike: add shared client behavior fixture"
```

### Task 4: Probe Claude Code

**Files:**
- Create: `spikes/platform/clients/claude-code/.claude-plugin/plugin.json`
- Create: `spikes/platform/clients/claude-code/.claude-plugin/marketplace.json`
- Create: `spikes/platform/clients/claude-code/hooks/hooks.json`
- Create: `spikes/platform/clients/claude-code/.mcp.json`
- Create: `spikes/platform/clients/claude-code/runbook.md`
- Test: `tests/kinglet_spike/test_claude_probe_package.py`
- Publish: `docs/research/platform-spike/evidence/client/claude-code/`

**Interfaces:**
- Uses Claude plugin root token `${CLAUDE_PLUGIN_ROOT}`.
- Produces the 12 capability observations under subject `claude-code`.

- [ ] **Step 1: Add manifest-validation tests**

Assert plugin name `kinglet-client-probe`, version `0.0.1`, relative component paths, hook path
`hooks/hooks.json`, local MCP command, and marketplace entry pinned to the fixture directory.

- [ ] **Step 2: Run tests and verify missing manifests**

Run: `python3 -m unittest tests.kinglet_spike.test_claude_probe_package -v`

Expected: failures for missing Claude files.

- [ ] **Step 3: Create the minimal Claude-native overlay**

Use the official Claude plugin layout. Copy shared skill and agent at probe-build time, translate
the hook policy to `PreToolUse` with matcher `Write|Edit`, and configure MCP to invoke
`${CLAUDE_PLUGIN_ROOT}/bin/<native executable> mcp`. The runbook uses:

```text
claude plugin marketplace add <absolute-disposable-marketplace-path>
claude plugin install kinglet-client-probe@kinglet-client-probe --scope local
claude plugin list
```

Then start a new session, run the four synthetic prompts, inspect permission prompts, update
version to `0.0.2`, reload/restart as documented, uninstall, and prove discovery disappears.

- [ ] **Step 4: Execute on native Windows and supported macOS/Linux hosts**

Record `claude --version`, exact scope, clean config root, case artifacts, and official source URLs.
Sanitize and publish each host result through 00A. Do not reuse the session after install for the
natural-language cold-discovery case.

- [ ] **Step 5: Close or leave open only the Claude gate**

Run: `python3 -m tools.kinglet_spike gate 0C:claude-code --repo-root .`

Expected: `0` only when all required Claude host/case cells pass; otherwise `1` with the exact open
cells.

- [ ] **Step 6: Commit package and sanitized evidence**

```bash
git add spikes/platform/clients/claude-code docs/research/platform-spike/evidence/client/claude-code
git commit -m "test: record Claude Code capability evidence"
```

### Task 5: Probe Codex

**Files:**
- Create: `spikes/platform/clients/codex/.codex-plugin/plugin.json`
- Create: `spikes/platform/clients/codex/.agents/plugins/marketplace.json`
- Create: `spikes/platform/clients/codex/hooks/hooks.json`
- Create: `spikes/platform/clients/codex/.mcp.json`
- Create: `spikes/platform/clients/codex/runbook.md`
- Test: `tests/kinglet_spike/test_codex_probe_package.py`
- Publish: `docs/research/platform-spike/evidence/client/codex/`

**Interfaces:**
- Uses the official `.codex-plugin/plugin.json` surface and plugin-scoped MCP approval policy.
- Produces the 12 observations under subject `codex`.

- [ ] **Step 1: Add Codex manifest tests**

Assert name/version/description, `skills: "./skills/"`, `mcpServers: "./.mcp.json"`,
`hooks: "./hooks/hooks.json"`, relative path rules, and one local marketplace entry whose source
path begins with `./`.

- [ ] **Step 2: Run tests and verify missing manifests**

Run: `python3 -m unittest tests.kinglet_spike.test_codex_probe_package -v`

Expected: missing file failures.

- [ ] **Step 3: Create the minimal Codex-native overlay**

Build the package with the shared skill and hook policy. Register its local marketplace with
`codex plugin marketplace add <disposable-marketplace-root>`, inspect with
`codex plugin marketplace list`, then install it through the Plugins Directory in a new ChatGPT
desktop/Codex session as required by the tested build. Enable the probe MCP with approval mode
`prompt`, never `approve`. Resolve the packaged executable with Codex's documented
`${PLUGIN_ROOT}` token in hook and MCP command fields; assert the expanded path points inside the
installed plugin cache.

- [ ] **Step 4: Execute the exact case sequence**

Install → new session → natural-language prompt → agent/delegation observation → protected mutation
→ executable receipt → MCP discovery/call → structured presentation → project/user scope comparison
→ version `0.0.2` update → removal → new-session absence. Record whether each capability is Native,
Emulated, Unavailable, failed, or inconclusive; do not infer an agents pass from skills.

- [ ] **Step 5: Publish native host evidence and evaluate the Codex gate**

Run: `python3 -m tools.kinglet_spike gate 0C:codex --repo-root .`

Expected: exact open cells or exit `0`.

- [ ] **Step 6: Commit**

```bash
git add spikes/platform/clients/codex docs/research/platform-spike/evidence/client/codex
git commit -m "test: record Codex capability evidence"
```

### Task 6: Probe Cursor

**Files:**
- Create: `spikes/platform/clients/cursor/source-lock.json`
- Create: `spikes/platform/clients/cursor/plugin/` (immutable tree emitted by the official scaffold)
- Create: `spikes/platform/clients/cursor/runbook.md`
- Test: `tests/kinglet_spike/test_cursor_probe_package.py`
- Publish: `docs/research/platform-spike/evidence/client/cursor/`

**Interfaces:**
- Uses only the plugin structure emitted by the tested Cursor build or documented by its current
  official plugin scaffold.
- Produces the 12 observations under subject `cursor`.

- [ ] **Step 1: Capture the official scaffold before hand-authoring**

In a disposable profile, run Cursor’s installed `Create Plugin` workflow for
`kinglet-client-probe` and save its generated tree plus `cursor --version` output under the raw run
directory. Record every source URL and SHA-256 in `source-lock.json`. Do not copy credentials or
user configuration.

- [ ] **Step 2: Add a test that locks the captured structure**

The test reads `source-lock.json`, verifies the generated manifest checksum and exact tested Cursor
version, then asserts that the committed fixture contains only supported component types:
skills, subagents/agents, rules, commands, hooks, and MCP as actually emitted. If no official
scaffold is accessible, publish an inconclusive `install.discover` result and leave this task open.

- [ ] **Step 3: Add shared behavior without inventing unsupported fields**

Populate only scaffold-declared paths. Install through `/add-plugin` or the tested marketplace UI,
not by assuming Claude/Copilot compatibility. If Cursor accepts a foreign manifest, record that as
Emulated unless Cursor documents it as a native format.

- [ ] **Step 4: Execute the common case sequence in a clean IDE profile**

Test the IDE surface, not `cursor-agent` CLI, unless a separate observation explicitly says so.
Capture hook block, executable process, MCP tool, rules, subagent, scope, update, and uninstall
behavior independently. Run on Windows and every officially supported desktop OS for native
local/MCP/hook cases.

- [ ] **Step 5: Publish and evaluate**

Run: `python3 -m tools.kinglet_spike gate 0C:cursor --repo-root .`

Expected: a closed Cursor gate only from live evidence; access/subscription failure stays
inconclusive.

- [ ] **Step 6: Commit**

```bash
git add spikes/platform/clients/cursor docs/research/platform-spike/evidence/client/cursor
git commit -m "test: record Cursor capability evidence"
```

### Task 7: Probe GitHub Copilot CLI and VS Code separately

**Files:**
- Create: `spikes/platform/clients/copilot/plugin/plugin.json`
- Create: `spikes/platform/clients/copilot/plugin/hooks.json`
- Create: `spikes/platform/clients/copilot/plugin/.mcp.json`
- Create: `spikes/platform/clients/copilot/marketplace/marketplace.json`
- Create: `spikes/platform/clients/copilot/cli-runbook.md`
- Create: `spikes/platform/clients/copilot/vscode-runbook.md`
- Test: `tests/kinglet_spike/test_copilot_probe_package.py`
- Publish: `docs/research/platform-spike/evidence/client/copilot-cli/`
- Publish: `docs/research/platform-spike/evidence/client/copilot-vscode/`

**Interfaces:**
- Shared Copilot-format source; two independent installations, sessions, evidence sets, and gates.

- [ ] **Step 1: Test the Copilot-format manifest**

Assert root `plugin.json`, root `hooks.json`, `.mcp.json`, plain kebab-case skill/agent names, and no
assumption of `${CLAUDE_PLUGIN_ROOT}` in the Copilot-native variant. The manifest explicitly names
`skills/`, `agents/`, `hooks.json`, and `.mcp.json`.

- [ ] **Step 2: Create the package and local marketplace**

Use version `0.0.1`. MCP command is resolved by an install-time absolute executable path in the
disposable package copy because Copilot format has no documented plugin-root token. Never write
that machine path into committed files; the committed manifest uses
`__KINGLET_PROBE_EXECUTABLE__`, and the native runbook creates a raw local rendered copy.

- [ ] **Step 3: Run the CLI sequence**

Use:

```text
copilot plugin marketplace add <local-marketplace-directory>
copilot plugin install kinglet-client-probe@kinglet-client-probe
copilot plugin list
copilot plugin update kinglet-client-probe
copilot plugin uninstall kinglet-client-probe
```

Run all common cases in a new Copilot CLI session and publish under subject `copilot-cli`.

- [ ] **Step 4: Run the VS Code IDE sequence**

Enable `chat.plugins.enabled` in a disposable VS Code profile, install the same source through the
documented plugin UI/marketplace, start a new chat, and run all cases. Verify actual matcher
behavior rather than assuming it, because the tested VS Code build may parse but ignore matchers.
Publish under subject `copilot-vscode`.

- [ ] **Step 5: Evaluate both gates independently**

Run:

```bash
python3 -m tools.kinglet_spike gate 0C:copilot-cli --repo-root .
python3 -m tools.kinglet_spike gate 0C:copilot-vscode --repo-root .
```

Expected: either gate may close while the other remains open.

- [ ] **Step 6: Commit both evidence sets**

```bash
git add spikes/platform/clients/copilot \
  docs/research/platform-spike/evidence/client/copilot-cli \
  docs/research/platform-spike/evidence/client/copilot-vscode
git commit -m "test: record Copilot CLI and VS Code evidence"
```

### Task 8: Probe Antigravity

**Files:**
- Create: `spikes/platform/clients/antigravity/source-lock.json`
- Create: `spikes/platform/clients/antigravity/plugin/` (immutable official scaffold/export tree)
- Create: `spikes/platform/clients/antigravity/runbook.md`
- Test: `tests/kinglet_spike/test_antigravity_probe_package.py`
- Publish: `docs/research/platform-spike/evidence/client/antigravity/`

**Interfaces:**
- Uses only formats and installation paths confirmed by the tested Antigravity build.
- Produces the 12 observations under subject `antigravity`.

- [ ] **Step 1: Lock official documentation and tested build**

Record the Antigravity build string, operating system, plugin documentation URL, retrieval time,
and content SHA-256 in `source-lock.json`. If the official documentation, product, account, or
plugin surface cannot be accessed, publish an inconclusive record with the access boundary and do
not invent a manifest.

- [ ] **Step 2: Capture a native minimal plugin**

Use the product’s own scaffold, export, or documented minimal manifest to create
`kinglet-client-probe`. Add a test that freezes its exact manifest and allowed component paths.
Foreign Claude/Copilot compatibility is a separately observed Emulated case.

- [ ] **Step 3: Populate and install the fixture**

Add shared skill/rule/agent/hook/MCP behavior only where the captured contract permits it. Render
machine-local executable paths only into the raw package. Install using the native plugin UI or
documented command and begin a new session.

- [ ] **Step 4: Run and publish all accessible cases**

Exercise the same sequence and native host matrix. A feature omitted from the product but documented
as absent is Unavailable; an untested feature is inconclusive. Publish through 00A.

- [ ] **Step 5: Evaluate and commit**

Run: `python3 -m tools.kinglet_spike gate 0C:antigravity --repo-root .`

```bash
git add spikes/platform/clients/antigravity docs/research/platform-spike/evidence/client/antigravity
git commit -m "test: record Antigravity capability evidence"
```

### Task 9: Generate and review the client capability baseline

**Files:**
- Create: `docs/research/platform-spike/reports/client-capabilities.json`
- Create: `docs/research/platform-spike/reports/client-capabilities.md`
- Test: `tests/kinglet_spike/test_client_report.py`
- Modify: `docs/superpowers/plans/2026-07-23-kinglet-00-plan-suite.md`

**Interfaces:**
- Consumes: only committed valid client evidence.
- Produces: per-client case/OS grades and independent adapter gate state.

- [ ] **Step 1: Add report determinism tests**

Tests require clients sorted in the fixed order from this plan, cases sorted by ID, distinct
documented vs observed columns, no generated timestamp, and evidence links for every grade.

- [ ] **Step 2: Generate the reports twice**

Run the client-report command twice and compare SHA-256.

Expected: byte-identical JSON and Markdown.

- [ ] **Step 3: Review capability language**

Confirm no `inconclusive` cell appears as Native/Emulated/Unavailable, no CLI result closes an IDE
gate, no shared format closes another client, and every Unavailable cell has an official source.

- [ ] **Step 4: Update only closed client gates**

The plan-suite index lists six separate 0C states. An inaccessible client remains Open
(inconclusive) while 00D may still proceed. Do not declare “client parity”; the report is a
capability baseline.

- [ ] **Step 5: Run complete verification**

Run:

```bash
python3 -m unittest discover -s tests/kinglet_spike -t . -v
bash tests/run-tests.sh
git diff --check
git grep -nE '(/Users/|/home/|[A-Z]:\\\\Users\\\\|gh[pousr]_|sk-)' docs/research/platform-spike
```

Expected: tests pass, aggregate `Failed: 0`, diff check silent, sensitive grep empty.

- [ ] **Step 6: Commit the client baseline**

```bash
git add docs/research/platform-spike/reports/client-capabilities.json \
  docs/research/platform-spike/reports/client-capabilities.md \
  docs/superpowers/plans/2026-07-23-kinglet-00-plan-suite.md
git commit -m "docs: baseline Kinglet client capabilities"
```

## Plan acceptance

Each client gate stands alone. The plan is acceptable when every accessible surface has live,
clean-session evidence for every fixed case and required host, every inaccessible surface remains
visibly inconclusive, installation/update/removal were exercised, and no capability was inferred
from a model choice, another client, documentation alone, or a shared manifest.
