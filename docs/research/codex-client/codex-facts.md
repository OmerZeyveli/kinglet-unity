# Codex CLI capabilities, measured

*Every claim here carries the command that established it. Nothing in this file
is read out of the binary's string table; the spec's "inferred, NOT verified"
list is what this file exists to resolve.*

**Measured against `codex-cli 0.145.0` on Pop!_OS 24.4.0 (noble), x86_64.**

`codex --version` → `codex-cli 0.145.0`, binary at
`/home/riive/.nvm/versions/node/v24.14.0/bin/codex`. Every probe below ran under a
disposable `CODEX_HOME` created mode 700 outside `/tmp`, with `~/.codex/auth.json`
copied in at 600 and the home removed afterwards. The owner's real `~/.codex` was
read but never written.

## How to drive the app server

`codex app-server` speaks newline-delimited JSON-RPC over stdio (`--listen
stdio://` is its default). This was established before any method was called, and
it is a precondition for everything below:

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"kinglet-probe","version":"1"}}}' \
  | CODEX_HOME="$PROBE_HOME" codex app-server
```

→ `{"id":1,"result":{"userAgent":"kinglet-probe/0.145.0 (Pop!_OS 24.4.0; x86_64) …","codexHome":"…","platformFamily":"unix","platformOs":"linux"}}`

`codex debug app-server` is a different thing — a `send-message-v2` helper, not a
server — so `codex app-server` is the entry point, and `--listen`/`--stdio` are
what select the transport.

**Closing stdin races the server's own shutdown.** A bare
`printf … | codex app-server` drops responses non-deterministically: the same
three-request pipeline printed the `initialize` result on one run and *nothing at
all* on the next. Hold stdin open past the reply — every command in this file
does, via a `{ printf …; sleep 8; }` brace group. A probe that reports "no
response" without holding stdin open has measured nothing.

**A method's existence is decided by calling it.** An unknown method returns
JSON-RPC `-32600` and the error text enumerates every method the build accepts,
which is the negative control the rest of this file relies on:

```bash
… '{"jsonrpc":"2.0","id":3,"method":"externalAgentConfig/thisMethodDoesNotExist","params":{}}'
```

→ `{"error":{"code":-32600,"message":"Invalid request: unknown variant
`externalAgentConfig/thisMethodDoesNotExist`, expected one of `initialize`,
`thread/start`, … `externalAgentConfig/detect`, `externalAgentConfig/import`,
`externalAgentConfig/import/readHistories`, …"},"id":3}`

## F1 — external agent configuration import

**Verdict:** **confirmed** — with a large caveat that decides how the wave should
use it. All three methods exist and run. The import is a *syntactic* migration:
it relocates and rewrites files, and it does so lossily and silently. It is not a
free port.

**Command:**

```bash
PROBE_HOME="$(mktemp -d "$PWD/docs/research/codex-client/evidence/.home-f1.XXXXXX")"
chmod 700 "$PROBE_HOME"
cp ~/.codex/auth.json "$PROBE_HOME/auth.json" && chmod 600 "$PROBE_HOME/auth.json"

{ printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"kinglet-probe","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"externalAgentConfig/detect","params":{"cwds":["/home/riive/Documents/Github/kinglet-unity"],"includeHome":false}}'; sleep 8; } \
  | CODEX_HOME="$PROBE_HOME" codex app-server

rm -rf "$PROBE_HOME"   # it holds a copied credential
```

**Observed** (the `id:2` result, pretty-printed from its single line; detail keys
whose value was `[]` are elided, nothing else is changed):

```json
{
  "items": [
    {
      "itemType": "MCP_SERVER_CONFIG",
      "description": "Migrate MCP servers from <repo> into <repo>/.codex/config.toml",
      "cwd": "<repo>",
      "details": { "mcpServers": [ { "name": "UnityMCP" } ] }
    },
    {
      "itemType": "HOOKS",
      "description": "Migrate hooks from <repo>/.claude to <repo>/.codex/hooks.json",
      "cwd": "<repo>",
      "details": { "hooks": [ {"name":"PreToolUse"}, {"name":"PostToolUse"},
                              {"name":"SessionStart"}, {"name":"Stop"} ] }
    },
    {
      "itemType": "SKILLS",
      "description": "Migrate skills from <repo>/.claude/skills to <repo>/.agents/skills",
      "cwd": "<repo>",
      "details": { "skills": [ {"name":"addressables"}, {"name":"assembly-definitions"},
        {"name":"input-system"}, {"name":"object-pooling"}, {"name":"physics"},
        {"name":"save-system"}, {"name":"state-machine"},
        {"name":"subagent-driven-implementation"}, {"name":"systematic-debugging"},
        {"name":"unity-brainstorming"}, {"name":"unity-execution"},
        {"name":"unity-mcp-patterns"}, {"name":"unity-planning"}, {"name":"urp-pipeline"},
        {"name":"using-kinglet"}, {"name":"verification-before-completion"} ] }
    },
    {
      "itemType": "COMMANDS",
      "description": "Migrate commands from <repo>/.claude/commands to <repo>/.agents/skills",
      "cwd": "<repo>",
      "details": { "commands": [ {"name":"source-command-unity-doctor"},
                                 {"name":"source-command-unity-init"} ] }
    },
    {
      "itemType": "SUBAGENTS",
      "description": "Migrate subagents from <repo>/.claude/agents to <repo>/.codex/agents",
      "cwd": "<repo>",
      "details": { "subagents": [ {"name":"unity-coder"}, {"name":"unity-fixer"},
        {"name":"unity-optimizer"}, {"name":"unity-prototyper"}, {"name":"unity-reviewer"},
        {"name":"unity-scene-builder"}, {"name":"unity-test-runner"},
        {"name":"unity-ui-builder"} ] }
    },
    {
      "itemType": "AGENTS_MD",
      "description": "Migrate <repo>/CLAUDE.md to <repo>/AGENTS.md",
      "cwd": "<repo>",
      "details": null
    }
  ]
}
```

`<repo>` is `/home/riive/Documents/Github/kinglet-unity`, written out in full in
the real output.

### The parameter that silently returns nothing

**`cwd` is not the parameter name; `cwds` is, and it takes an array.** Called with
`{"cwd":"…"}` the method does not error — it returns `{"items":[]}`, because the
unknown key is ignored and `cwds` defaults to empty. An implementer who reads that
empty result as "Codex has no importer" records the exact opposite of the truth.
The authoritative shape comes from the binary itself:

```bash
codex app-server generate-json-schema --out <dir>
# <dir>/v2/ExternalAgentConfigDetectParams.json, ExternalAgentConfigDetectResponse.json, …
```

`ExternalAgentConfigDetectParams`: `cwds` (array of string, nullable),
`includeHome` (boolean), `migrationSource` (string, nullable), and a deprecated
`source` that is documented as ignored.

Attempts recorded, including the ones that failed:

| Params | Result |
|---|---|
| `{"cwd":"<repo>"}` (the shape guessed in the plan) | `{"items":[]}` — **no error**, silently empty |
| `{"cwds":["<repo>"],"includeHome":false}` | the six items above |
| `{"cwds":["<repo>"],"migrationSource":"claude_code"}` | identical to the default |
| `{"cwds":["<repo>"],"migrationSource":"cursor"}` | `{"items":[]}` — recognised source, nothing to migrate here |
| `{"cwds":["<repo>"],"migrationSource":"nonsense-value"}` | falls back to the default source, as the schema documents |
| `externalAgentConfig/import/readHistories` with `{}` | returns `{"data":[…],"connectors":[…]}`, including this session's own import record — the method exists |

### What the import actually writes

`externalAgentConfig/import` was driven with the detect items against a **replica**
of this repo (`.claude/` + `CLAUDE.md` copied into a scratch git repo), never
against the repo itself, because the import writes into the working tree. It
answered `{"importId":"…"}`, streamed `externalAgentConfig/import/progress`
notifications, and finished with `externalAgentConfig/import/completed`.

Reported outcome: **31 successes, 0 failures** — 16 SKILLS, 8 SUBAGENTS, 4 HOOKS,
2 COMMANDS, 1 AGENTS_MD.

Files created in the repo:

| Path | Content |
|---|---|
| `.codex/hooks.json` | Claude Code's `settings.json` `hooks` block, structurally verbatim |
| `.codex/hooks/*.sh` | all 13 files from `.claude/hooks/` (12 hooks + `_lib.sh`), **byte-identical**, executable bit preserved |
| `.codex/agents/<name>.toml` | 8 agents, converted from Markdown to TOML |
| `.agents/skills/<name>/SKILL.md` | 16 skills + 2 commands-as-skills |
| `AGENTS.md` | rewritten copy of `CLAUDE.md` |

Nothing was written to the disposable `CODEX_HOME` except an empty `skills/.system`
directory: at `includeHome:false` this migration is entirely repo-scoped.

### Three losses, none of them reported as a failure

**1. Seven of nine commands are dropped.** Only `unity-doctor` and `unity-init`
migrate. The discriminator is not frontmatter and not file size — it is an
argument placeholder in the body. Bisected one command per fixture repo, then
confirmed causally on four minimal fixtures:

| Body | Detected |
|---|---|
| `Do the thing.` | yes |
| `Do the thing: $ARGUMENTS` | **no** |
| `Do the thing: $NOTARGUMENTS` | yes |
| `Do the thing: $1` | **no** |

Kinglet's seven argument-taking commands (`unity-fix`, `unity-optimize`,
`unity-prototype`, `unity-review`, `unity-scene`, `unity-test`, `unity-ui`) all
contain `$ARGUMENTS`; the two that migrate contain none. They never appear in
`detect`, so `import` reports success while they are absent — there is no failure
entry to notice.

Stripping the `args:` frontmatter key does **not** help; emptying the body does.
`args:` is irrelevant to the importer.

**2. `.claude/rules/` is not migrated at all.** There is no `RULES` item type —
the enum is `AGENTS_MD, CONFIG, SKILLS, PLUGINS, MCP_SERVER_CONFIG, SUBAGENTS,
HOOKS, COMMANDS, MEMORY, SESSIONS`. No `rules/` directory is created anywhere. The
five binding spine rules plus `pc-console.md` do not cross, while the migrated
payload keeps referring to them.

**3. A blind `Claude` → `Codex` string substitution corrupts the payload.** It is
applied to migrated Markdown and TOML (not to the copied `.sh` files) and it does
not distinguish a path from a product name:

- `.claude/rules/` → `.Codex/rules/` — **84 occurrences in 26 of the 31 rewritten
  files** (30 Markdown/TOML under `.agents/` and `.codex/`, plus `AGENTS.md`; 64
  occurrences in the former, 20 in the latter). Note the capital `C`: this is not
  even Codex's own directory, and the target does not exist for either spelling
  (see loss 2).
- `everything-claude-unity` → `everything-Codex-unity`, `Claude-Code-Game-Studios`
  → `Codex-Game-Studios` — upstream project names, now wrong.
- `scripts/generate-claude-md.sh` → `scripts/generate-Codex-md.sh` — a real script
  path in this repo, now broken.
- `CLAUDE.md` → `AGENTS.md` in prose, which is right for the new layout and wrong
  wherever the sentence was *about* Claude Code.

The substitution is also incomplete: 22 literal `.claude/` references survive — 1
in `.agents/skills/subagent-driven-implementation/task-reviewer-prompt.md`, and 21
in the copied hook scripts, which are exempt from the rewrite entirely (`.Codex/`
appears in them 0 times). The result is a payload that points at two different
non-existent directories.

### What Codex then loads from it

Measured with `skills/list` and `hooks/list` against the imported replica:

- **Skills load.** `skills/list` returns 24: Kinglet's 16, the 2 migrated commands,
  and 6 Codex built-ins (`imagegen`, `openai-docs`, `plugin-creator`,
  `review-agent`, `skill-creator`, `skill-installer`). Each Kinglet entry is
  `"scope":"repo","enabled":true`.
- **Hooks load only after the project is trusted.** Before trust, `hooks/list`
  returns `{"hooks":[],"warnings":[],"errors":[]}` and stderr says: *"Project-local
  config, hooks, and exec policies are disabled in the following folders until the
  project is trusted, but skills still load."* Writing
  `[projects."<repo>"]\ntrust_level = "trusted"` into `$CODEX_HOME/config.toml`
  makes all 12 register, `warnings: []`, `errors: []`.
- **The registered hooks are individually untrusted.** Each carries
  `"currentHash":"sha256:…"` and `"trustStatus":"untrusted"`. `codex --help`
  documents `--dangerously-bypass-hook-trust` ("Run enabled hooks without requiring
  persisted hook trust for this invocation"), which is consistent with a per-hook
  hash-trust gate on top of the project trust gate.
- **Event names are accepted in Claude Code's spelling and normalised.**
  `PreToolUse` in the file is reported as `eventName: "preToolUse"`. Registered:
  5 `preToolUse`, 4 `postToolUse`, 2 `sessionStart`, 1 `stop`.
- **Matchers are carried across verbatim** — `Edit|Write`, `Bash`,
  `startup|clear|compact` — i.e. Claude Code's tool names, untranslated.
- **The command string is single-quoted** into the JSON:
  `"command": "'/abs/path/.codex/hooks/block-scene-edit.sh'"`.
- **`timeout` is copied unchanged into a seconds field.** Kinglet writes
  `timeout: 3000` meaning milliseconds; `hooks/list` reports
  `"timeoutSec": 3000`. Every migrated hook therefore carries a ~50-minute timeout.

Registering is not firing. Whether these hooks execute, whether a `Edit|Write`
matcher ever matches a Codex tool name, and what the block protocol is, are not
settled by this section.

### Where the MCP server row came from

`MCP_SERVER_CONFIG` reports `UnityMCP`, but this repo contains no `.mcp.json`.
The source is the per-project `mcpServers` entry under
`~/.claude.json` → `projects["/home/riive/Documents/Github/kinglet-unity"]`. So an
item can be *scoped* to a repo while being *read* from the user's home file — a
detection against a copy of the repo at a different path does not reproduce it.

**What this means for the wave:** the importer is real and worth shipping *toward*,
but it cannot be the port. It carries skills and agents across usefully, it
produces the `.codex/hooks.json` that Task 3 was to discover, and it proves the
target layout (`.agents/skills/`, `.codex/agents/*.toml`, `.codex/hooks.json`,
`AGENTS.md`). Against that, it silently drops 78% of the commands, never migrates
the rules layer at all, and rewrites 84 path references to a directory that does
not exist — all while reporting zero failures. A Kinglet user who runs the
importer gets a configuration that looks complete and is not. The wave's remaining
tasks stand; what changes is that Tasks 5 and 6 now start from a measured baseline
instead of an open question, and that Kinglet has a positive reason to ship its own
Codex layout rather than tell users to import.
