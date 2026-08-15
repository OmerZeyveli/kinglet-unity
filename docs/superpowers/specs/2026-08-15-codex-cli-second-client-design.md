# Codex CLI as Kinglet's Second Client — Measure, Then Ship the Minimum

*2026-08-15. Branch: `pioneer/codex-second-client`, to be cut from `main` at `9a2ebec`. Scoped by the
owner as "get into the Codex CLI / VS Code business, using Superpowers". The owner holds accounts on
all three vendors, so client access is no longer the constraint it was when the client-probe cells
were opened on 2026-07-27.*

## The problem

Kinglet ships to exactly one client. Every surface it has — 8 agents, 9 commands, 16 skills, 12
hooks, 6 rules — is addressed to Claude Code, and `install.sh` writes exactly one layout. That was a
deliberate narrowing: the 2026-07-23 multi-client platform design was set aside on 2026-07-29 in
favour of making one client actually work, and it did work.

The narrowing left three things behind, and all three are still in the tree:

- **A platform architecture that was designed and then never filled.** `tools/kinglet_build/` is ten
  Python modules with a working CLI; `python3 -m tools.kinglet_build validate` reports
  `Validated 0 canonical units, 0 routes, 2 adapters`. `src/catalog/routing.json` is `{"routes": []}`.
  The machine exists and has never had content put through it.
- **Two adapter profiles with no adapter.** `adapters/claude/profile.json` and
  `adapters/codex/profile.json` describe model tiers, capability-to-tool mappings and output roots
  for a build step that never ran.
- **A client-evidence matrix that is mostly empty.** In
  `docs/research/platform-spike/reports/coverage.md`, every `copilot-vscode`, `copilot-cli`, `cursor`
  and `antigravity` cell is `missing` on every host. `claude-code` and `codex` have a Linux slice
  only, and it is not clean: `codex.linux.mcp-discovery` and `codex.linux.path-semantics` are `fail`,
  as are `claude-code.linux.local-executable` and `claude-code.linux.mcp-discovery`.

Meanwhile the 2026-08-14 live-bridge measurement established the fact that makes a naive port the
wrong move: **prose describing MCP call shapes is close to inert when the bridge is live.** It was
proved three independent ways on that branch. Value concentrated in hooks, scripts and process
surfaces — the executable layer — not in the documents.

So the question this wave answers is not "can we copy the files across." It is: **which of Kinglet's
surface classes survive the crossing to a second client, and what does the crossing actually cost?**

## What was measured, and what was only inferred

This distinction is load-bearing. The branch that closed yesterday recorded the lesson that produced
it: *a server's description of its tool is not evidence about the tool.* The same discipline applies
to a binary's string table.

### Measured by execution on this host, 2026-08-15

- `codex-cli 0.145.0`, installed via npm under nvm node v24.14.0. `codex doctor` reports
  `linux-x86_64`, Pop!_OS 24.4.0 (noble), and notes `0.147.0 available`.
- `~/.codex/config.toml` already carries `[mcp_servers.unityMCP] url = "http://127.0.0.1:8080/mcp"`
  and `[features] rmcp_client = true`. **Codex on this machine is already wired to the live Unity
  bridge.** The bridge answered a plain GET with HTTP 406 — alive, and correctly demanding an
  `Accept` header.
- `codex features list` reports `hooks` as **stable, enabled**; `plugin_hooks` as **removed**;
  `multi_agent`, `plugins`, `plugin_sharing`, `remote_plugin` as stable and enabled.
- `codex exec` accepts `--json` (JSONL event stream), `-o/--output-last-message FILE`, `--cd DIR`,
  `--ephemeral`, `--ignore-user-config`, `--ignore-rules`, `--sandbox <read-only|workspace-write|
  danger-full-access>`, `--output-schema FILE`, and `--dangerously-bypass-hook-trust`.
  `CODEX_HOME` is honoured for auth and config. This is a headless measurement harness with a
  disposable configuration root — the same shape as `claude -p --output-format stream-json`.
- Codex's own skills live at `~/.codex/skills/.system/<name>/SKILL.md` and carry `agents/`,
  `scripts/`, `references/` and `assets/` subdirectories. **The `SKILL.md` container shape is the
  same one Kinglet uses.**
- `~/.codex/rules/default.rules` holds `prefix_rule(pattern=[...], decision="allow")` entries. These
  are **command-approval policy, not model guidance** — the name collides with Kinglet's
  `.claude/rules/`, and the two mean different things. Nothing in Kinglet's rule layer maps here.
- `codex plugin` exposes `marketplace add|list|upgrade|remove` and `add|list|remove`.
- Superpowers 6.2.0, read at `.research/superpowers/`: one shared `skills/` tree (14 skills) and one
  shared `hooks/` directory serve seven clients. Each client gets a thin manifest —
  `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `.cursor-plugin/plugin.json`,
  `.kimi-plugin/plugin.json`, `gemini-extension.json`, `.opencode/plugins/superpowers.js`,
  `.pi/extensions/superpowers.ts`, `.agents/plugins/marketplace.json`. `AGENTS.md` is a **symlink to
  `CLAUDE.md`**. `hooks/run-hook.cmd` is a polyglot parsed by both `cmd.exe` and `bash`. There is no
  build step and no canonical core. Notably, `.codex-plugin/plugin.json` declares `"hooks": {}` —
  Superpowers ships **no** hooks to Codex, consistent with `plugin_hooks` being removed.

### Inferred from the binary's string table — NOT yet verified by execution

Every item here is a hypothesis the measurement must confirm or kill. String-table adjacency is
especially weak: symbols land next to each other because of how the linker packed them, not because
they are related at runtime.

- Hook event names: `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`,
  `SessionStart`, `SessionEnd`, `SubagentStart`, `SubagentStop`. (`user_prompt_submit` also appears
  in the snake_case list; the TOML-facing enum does not obviously include it, and one string reads
  `prompt hooks are not supported yet`.)
- Config filename `hooks.json`; structures `HookEventsToml`, `MatcherGroup { matcher, hooks,
  trusted_hash }`, `HookHandlerConfig { description, hooks, matcher }`; telemetry keys
  `hook.event_name`, `hook.handler_type`, `hook.execution_mode`, `hook.scope`, `hook.source`;
  a command runner at `hooks/src/engine/command_runner.rs` invoking `$SHELL -lc`.
- The blocking protocol: `Command blocked by PreToolUse hook:` and
  `hook returned decision:block without a non-empty reason`. If real, this is **byte-for-byte the
  contract Kinglet's 12 hooks already implement** — `decision: block` plus a non-empty `reason`.
- An external-agent configuration importer: app-server methods `externalAgentConfig/detect`,
  `externalAgentConfig/import`, `externalAgentConfig/import/readHistories`, with fields
  `migration_type`, `agents_md`, `plugins`, `mcp_server_config`, `subagents`, `hooks`, `memory`,
  `skills_count`, and a source file `external-agent-migration/src/hooks_common.rs`.
- One string blob places `hooks.json` adjacent to `.codex`, `.agents`, `.claude` and `.cursor`.
  **This is the weakest inference in the document** and is written down only because, if it turns out
  to describe a search path, it collapses most of this wave's work into a configuration line.

## Scope, as the owner set it

Three scope questions were put to the owner as explicit choices with measurements and options, and
answered. The fourth was proposed in the presented design and approved with it, which is a weaker
form of assent and is marked as such:

1. **Codex CLI first, measured** — not all four consumption paths at once, and not the 2026-07-23
   program. The measurement decides what an adapter must contain.
2. **Two-layer measurement target** — Layer A needs no Unity and runs in this repository; Layer B
   needs Unity and waits for a free Editor. The largest unknown (hook registration) is resolved in
   Layer A, so the wave is never blocked on Editor availability.
3. **Measure and ship the minimum** — not measurement alone, and not a full port. Whatever Layer A
   proves works gets shipped in this wave; whatever measures dead is excluded in writing.
4. **VS Code (Copilot and the Claude extension) is out of scope** for this wave, and named as such
   rather than left ambiguous. *(Proposed in the design, approved with it — not chosen against
   alternatives. If it turns out the owner wanted a VS Code path in this wave, this is the item to
   re-open, because it is the one that was never offered as a choice.)*

## Architecture — three parts, in sequence

### Part 1 — Layer A: does Codex honour the surface at all?

Kinglet's payload is installed into a **disposable Codex configuration root**
(`CODEX_HOME=<tmpdir>`, `codex exec --ignore-user-config`), inside this repository. Nothing touches
the owner's real `~/.codex`. A fixed task set is then run **identically under Claude Code and under
Codex**, so the output is a comparison rather than an impression. The task shapes are reused from the
2026-08-14 live-bridge measurement, whose harness already exists.

Per surface class, the question measured:

| Surface class | Kinglet ships | Codex target | Question |
|---|---|---|---|
| hooks | 12 bash scripts plus the shared `_lib.sh`, all 12 registered in `.claude/settings.json` | `hooks.json`, matcher groups, hash trust | Does a `PreToolUse` hook actually block a write? Does `decision: block` with a `reason` reach the model? |
| skills | 16 flat `.claude/skills/<name>/SKILL.md` | the `skills` config key / `~/.codex/skills/` | Are they discovered? Are they invoked when relevant, or only when named? |
| rules | 6 files in `.claude/rules/`, loaded through `CLAUDE.md` | `AGENTS.md` / `model_instructions_file` | Do they load at all, and does the generated-block contract survive? |
| commands | 9 files in `.claude/commands/` | no known equivalent | Is there any equivalent, or is this class dead on Codex? |
| agents | 8 files in `.claude/agents/` with `tools:` frontmatter | `multi_agent`, skill-local `agents/` | Is there any equivalent, or is this class dead on Codex? |
| MCP | `.mcp.json` | `[mcp_servers.unityMCP]` in `config.toml` | Already proven live on this host. |

**Ordering constraint.** `externalAgentConfig/detect` is probed **first**, before any porting work.
If Codex natively detects and imports a `.claude/` configuration, most of the rest of this wave
collapses, and discovering that after building a port would be the expensive way to learn it.

**A hook probe must key on execution, not on presence.** Confirming that `hooks.json` exists proves
nothing; this repository has been burned by presence-keyed checks repeatedly. The probe writes a file
Kinglet's hooks are known to reject — a legacy `Input.GetKey` call for `block-legacy-input.sh` — and
asserts on the observable outcome: the write did not land, and the model saw the reason string.

### Part 2 — Layer B: MCP route behaviour

The same harness, pointed at a real Unity project when one is free — Endless Evolution by preference,
`spikes/platform/unity/fixture/` as the fallback. The fixture is a fallback and not the target
because it holds two `.cs` files against EE's 1418, and the live-bridge measurement produced what it
produced *because* it ran against a shipping game.

Layer B measures only what Layer A cannot:

- Does Codex hit the same tool-versus-resource split (reads are `mcpforunity://…` resources, writes
  are tools)?
- Do the `manage_*` action names in Kinglet's surfaces resolve under Codex's MCP client?
- Does the silent-failure shape — MCP `isError: false` carrying `"success": false` in the body —
  appear under Codex too, or does its client surface it differently?

**The one-implementer rule governs Layer B absolutely.** The Unity Editor is one process holding one
asset database; two agents driving it concurrently corrupt shared state as a broken scene, not as a
merge conflict. Layer B runs only when no other agent holds the Editor.

### Part 3 — Ship the minimum Layer A proved

The expected shape is hooks, skills and an `AGENTS.md` entry document. **That is an expectation, not
a plan input** — the ship list is whatever Layer A returns green, and the plan is written against the
measurement rather than against this paragraph.

Every surface class that measures dead is **named as excluded, in writing, with its measurement**. A
class dropped silently is indistinguishable from a class forgotten, and this repository has shipped
that failure before.

**If hooks do not port, the wave still ships and its verdict changes.** The whole ship leans on the
hook layer, because that is where the 2026-08-14 measurement found the value; so the case where
Layer A returns "Codex will not run Kinglet's hooks" has to be answered here rather than discovered
during execution. In that case: the minimum ship becomes skills plus `AGENTS.md`, success criterion 1
is recorded as **not met** with the evidence, and the findings document states plainly that Kinglet
on Codex is advisory rather than enforcing. That is a legitimate outcome to ship — an honest,
measured "the guardrails do not cross" is worth more than a port that looks complete and enforces
nothing. What is not legitimate is shipping the skills and letting a reader assume the hooks came
with them.

## The architecture decision this wave makes

Three shapes are live, and the measurement chooses between them. The choice is recorded in the
findings document with its evidence.

**A — the Superpowers shape.** One shared content tree, a thin per-client manifest, `AGENTS.md` as a
symlink, a per-client hook manifest, and a polyglot wrapper for the eventual Windows pass. Its
evidence is that it ships to seven clients today. Its risk is that Kinglet's surfaces are far more
divergent than Superpowers' are: Superpowers is skills-and-one-hook, while Kinglet adds 9 commands
and 8 agents that have no evident Codex counterpart, and a symlink does not resolve them.

**B — the 2026-07-23 platform design.** Fill the canonical core, write renderers, generate a product
per client. Its strength is that it genuinely models divergence. Its risks are that the machine has
never been filled, its 01–06 plans are frozen as superseded, and the most expensive layer it builds
produces generated prose — which the live-bridge measurement showed is the least load-bearing output
there is.

**C — installer-only.** Leave the repository shape alone and teach `install.sh` to write a Codex
layout from the existing `.claude/` payload. Fastest, zero structural churn; but it puts the
translation layer inside a 2197-line bash file that already owns the receipt, the detection and the
generated block.

**Expected outcome: A.** It is overturned only if commands and agents measure as requiring real
translation rather than exclusion — that is, if Codex has counterparts that a shared tree would
misrepresent.

### Explicit deferral, recorded as debt

If A holds, then `src/catalog/` (3 files), `tools/kinglet_build/` (10 Python modules, one of which is
the renderer package's `__init__.py`), `adapters/*/profile.json` (2 files) and
`migration/baseline-inventory.json` become dead weight. **They are not retired in this wave.** The findings document records them by name as debt
with the measurement that made them dead, and a later wave adjudicates them.

This is written down because the alternative — noticing they are dead and saying nothing — is the
exact defect shape this repository has hunted across three waves: a thing that stops being true and
no document changes.

## Where the payload lives

Superpowers avoids duplication by having one `skills/` tree that every client points at. Codex
exposes a `skills` configuration key, which suggests the same is possible here.

**The proposal is that there is no second copy: Codex reads `.claude/skills/` directly.** This is
measured in Layer A. The fallbacks, in order, are a symlink, and then an install-time copy. Only the
install-time copy pulls in the provenance contract — a second tracked tree needs a `provenance.tsv`
row per file — which is why it is last.

## Gates and testing

The gates are the repository's existing two, unchanged:

```bash
bash tests/run-tests.sh          # header count must equal `ls tests/test-*.sh | wc -l`
bash scripts/check-provenance.sh # must print exactly "provenance OK"
```

**The constraint most likely to bite is provenance.** Every newly tracked file needs a row, or the
orphan check fails. Anything adapted from Superpowers is `origin=superpowers`, not `origin=original`
— `provenance.tsv`'s header names four legal origins, and writing `original` for a row that has an
upstream is a documented way this manifest rots.

The new guard follows the shape of `tests/test-shipped-citations.sh`: derive the Codex surface list
from the tree, and fail when a shipped Codex file has no counterpart, or when a counterpart has no
shipped file. It carries an anti-vacuity floor, because an identity over two empty sets passes at
`0 == 0` — the failure mode `docs/ANTI-VACUITY.md` exists to prevent.

Hook behaviour is tested the way `tests/test-hook-behaviour.sh` already tests it: feed the hook a
payload and assert on the exit code and the emitted reason, rather than on the file's existence.

## Risks

1. **Hash trust may require a human.** `MatcherGroup` carries a `trusted_hash` field and
   `--dangerously-bypass-hook-trust` exists as an escape. If registering a hook needs interactive
   approval, the owner's "can the AI do the install itself" question returns with a concrete answer,
   and that answer belongs in the findings. The bypass flag is a measurement tool, **not a shipping
   answer** — shipping a toolkit that tells users to disable hook trust is worse than shipping no
   hooks.
2. **Version drift.** Codex is 0.145.0 here with 0.147.0 released. The findings pin the measured
   version; a hook-schema change between versions invalidates the evidence, and the pin is what makes
   that detectable rather than silent.
3. **The importer may make most of this moot.** Mitigated by probing it first.
4. **Editor contention** governs Layer B, per the one-implementer rule.
5. **Weak inference treated as fact.** Everything in the inferred list above is a hypothesis. The
   plan must not contain a task whose brief asserts one of them as a premise — a false premise passes
   review and ships, which is why the loop's rule is to stop and re-brief rather than review it.

## Out of scope

- VS Code: GitHub Copilot and the Claude extension. Named, deferred to a later wave.
- Cursor, Antigravity, Kimi, Gemini, opencode, Pi.
- Windows and macOS host passes. Superpowers' `run-hook.cmd` polyglot is noted for that pass.
- Retiring `tools/kinglet_build/`, `src/catalog/`, `adapters/*/profile.json`.
- Closing the `00C` client-probe gate. This wave's evidence may feed those cells later, but the
  spike's evidence-harness ceremony is not this wave's deliverable.

## Success criteria

1. `codex` runs in a Unity project with Kinglet installed, and at least one Kinglet hook **blocks a
   real violation**, demonstrated by an execution-keyed probe rather than by file presence.
2. A findings document records, per surface class, whether Codex honours it — with the command that
   produced each verdict, so a reader can re-run it.
3. The architecture decision (A, B or C) is recorded with the measurement that chose it.
4. Everything excluded is named in writing, with its measurement.
5. Both gates green: `tests/run-tests.sh` with header count equal to file count, and
   `check-provenance.sh` printing `provenance OK`.
6. The debt paragraph exists: whichever of `kinglet_build`, `src/catalog` and `adapters/` the
   decision strands is named as stranded.
