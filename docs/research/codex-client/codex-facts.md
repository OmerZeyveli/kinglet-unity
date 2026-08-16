# Codex CLI capabilities, measured

*Every claim here carries the command that established it, and every claim that is
**not** measured says so in those words. Nothing in this file is read out of the
binary's string table; the spec's "inferred, NOT verified" list is what this file
exists to resolve. A field **name** is not a measurement either — see the
`timeoutSec` probe, which exists because an earlier draft of this file read one as
if it were.*

**Measured against `codex-cli 0.145.0` on Pop!_OS 24.4.0 (noble), x86_64.**

**Counting criterion, used for every number in this file.** Counts are
**occurrences** of a literal string — `grep -o … | wc -l`, not matching lines and
not matching files — taken over **the imported tree**, defined as `.agents/`
plus `.codex/` plus `AGENTS.md` in the replica repo after the import in
§"What the import actually writes". Where a count is over files instead of
occurrences, or over a narrower subtree, the sentence says so. Two readers who
agree on a number without agreeing on this criterion have agreed by accident.

`codex --version` → `codex-cli 0.145.0`, binary at
`/home/riive/.nvm/versions/node/v24.14.0/bin/codex`. Every probe below ran under a
disposable `CODEX_HOME` created mode 700 outside `/tmp`, with `~/.codex/auth.json`
copied in at 600 and the home removed afterwards.

**Precisely what "isolated" means here:** with `CODEX_HOME` set, no credential,
config, session, skill or database in the owner's `~/.codex` is read-modified or
written — `auth.json` keeps its mtime and mode 600 throughout. It is *not* true
that nothing under `~/.codex` is ever touched: the `codex --help` / `--version`
calls in the step below run **without** `CODEX_HOME` set, and those create
`~/.codex/tmp/arg0/codex-arg0<rand>/` holding symlinks to the binary and a `.lock`.
That is Codex's own self-managed scratch, left in place. The isolation claim is
about the probes, not about every invocation in this file.

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

**Closing stdin races the server's own shutdown, and the naive pipeline never
works.** The plan's Step 3 pipes three requests into `codex app-server` and closes
stdin. Run 12 consecutive times against this repo:

| Outcome | Runs |
|---|---|
| nothing at all on stdout | 4 |
| 2 lines (`initialize` result + a `remoteControl/status/changed` notification) | 8 |
| **the `detect` result (`"id":2`) present** | **0** |

So this is not a flaky trap that sometimes hides the answer — without holding stdin
open the answer **cannot** arrive, and a third of the time there is nothing on
stdout to even look at. Hold stdin open past the reply; every command in this file
does, via a `{ printf …; sleep 8; }` brace group. A probe that reports "no
response" without holding stdin open has measured nothing.

**A method's existence is decided by calling it.** An unknown method returns
JSON-RPC `-32600` and the error text enumerates every method this build accepts,
which is the negative control the rest of this file relies on:

```bash
… '{"jsonrpc":"2.0","id":3,"method":"externalAgentConfig/thisMethodDoesNotExist","params":{}}'
```

→ `{"error":{"code":-32600,"message":"Invalid request: unknown variant
`externalAgentConfig/thisMethodDoesNotExist`, expected one of `initialize`,
`thread/start`, … `externalAgentConfig/detect`, `externalAgentConfig/import`,
`externalAgentConfig/import/readHistories`, …"},"id":3}`

**Do not quote a method count as a constant, and this file used to.** Three readings
of the same pinned build disagree: the error text was counted at **129** by one agent
and **123** by another, and `ClientRequest.json` from
`codex app-server generate-json-schema` carries **89** request variants (re-derived
2026-08-16, `codex-cli 0.145.0`). The three are not obviously the same population —
the error enumerates what the deserialiser will accept, the schema enumerates what the
protocol documents — and nothing here established which. **Use the enumeration as a
membership test, never as a total**, and prefer the schema bundle when the question is
"does a route for X exist", because it is offline, exhaustive and re-derivable.

## F1 — external agent configuration import

**Verdict:** **confirmed** — with a large caveat that decides how the wave should
use it. All three methods exist and run. The import is a *syntactic* migration:
it relocates and rewrites files, and it does so lossily and silently. It is not a
free port. Concretely: it drops 7 of 9 commands, never migrates `.claude/rules/`
at all, and rewrites 84 `.claude/` path references to a `.Codex/` that does not
exist — **29 of them `.Codex/rules/`** — while reporting 31 successes and 0
failures.

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

**The same trap applies to `hooks/list` and `skills/list`, and there it is worse.**
Both take `cwds` (array) — `HooksListParams` declares exactly one property, `cwds`,
described as *"When empty, defaults to the current session working directory."*
There is no `cwd`. Passing `cwd` does not error and does not return empty; it
silently answers **for the app-server's own working directory**:

```bash
# both requests in one session, CODEX_HOME=$PROBE_HOME, run from the real repo
'{"jsonrpc":"2.0","id":2,"method":"hooks/list","params":{"cwd":["<replica>"]}}'
'{"jsonrpc":"2.0","id":3,"method":"hooks/list","params":{"cwds":["<replica>"]}}'
```

| Call | `cwd` in the response | count |
|---|---|---|
| `hooks/list` with `cwd` | `/home/riive/…/kinglet-unity` (**wrong repo**) | 0 hooks |
| `hooks/list` with `cwds` | `<replica>` | 12 hooks |
| `skills/list` with `cwd` | `/home/riive/…/kinglet-unity` (**wrong repo**) | 6 skills, **0 of them repo-scope** |
| `skills/list` with `cwds` | `<replica>` | 24 skills, **of which 18 repo-scope** |

**Read the repo-scope halves of that last column and ignore the totals.** 24 and 6 are
scope-mixed and neither reproduces across homes — see *"Quote the 18, not the total"*
below, where a second disposable home reported 59. The load-bearing contrast here is
**18 versus 0**: the `cwd` form found none of the replica's skills while reporting a
number that looks like an answer.

A well-formed answer for the wrong repository is worse than an error: the `cwd`
form would let a reader "confirm" every hook finding below against a tree that
contains no `.codex/hooks.json` at all, and read `0 hooks` as a refutation.
**Always check the `cwd` echoed back in the response against the one you meant.**

Attempts recorded, including the ones that failed:

| Params | Result |
|---|---|
| `{"cwd":"<repo>"}` (the shape guessed in the plan) | `{"items":[]}` — **no error**, silently empty |
| `{"cwds":["<repo>"],"includeHome":false}` | the six items above |
| `{"cwds":["<repo>"],"migrationSource":"claude_code"}` | identical to the default |
| `{"cwds":["<repo>"],"migrationSource":"cursor"}` | `{"items":[]}` — recognised source, nothing to migrate here |
| `{"cwds":["<repo>"],"migrationSource":"nonsense-value"}` | falls back to the default source, as the schema documents |
| `{"cwds":["<repo>"],"includeHome":true}` | **8** items — the six below **plus** home-scoped `PLUGINS` (1) and `SESSIONS` (45), both with `cwd: null` |
| `externalAgentConfig/import/readHistories` with `{}` | returns `{"data":[…],"connectors":[…]}`; called after an import in the same home it includes that import's record, and called before any import it is `{"data":[],"connectors":[]}` — either way the method exists |

**Everything else in this file uses `includeHome:false`**, so its scope is
repo-only. A user running the real interactive importer is plausibly in the
`includeHome:true` case, which additionally offers to migrate the home-scoped
plugins and 45 prior Claude Code sessions. Those two item types were not imported
or otherwise exercised here.

### What the import actually writes

`externalAgentConfig/import` was driven against a **replica** of this repo, never
against the repo itself, because the import writes into the working tree.

**Command.** The whole trick is `migrationItems`: it takes the `items` array from
a `detect` response *verbatim*, so the two calls are chained rather than
hand-written.

```bash
# 1. build the replica the import will write into
REP=/tmp/rep; mkdir -p "$REP"; cp -a .claude "$REP/.claude"; cp -a CLAUDE.md "$REP/"
git -C "$REP" init -q .

# 2. detect against the replica, keep the items array
{ printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"kinglet-probe","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"initialized"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"externalAgentConfig/detect\",\"params\":{\"cwds\":[\"$REP\"],\"includeHome\":false}}"; sleep 8; } \
  | CODEX_HOME="$PROBE_HOME" codex app-server > detect.out

# 3. feed those items straight back as migrationItems
ITEMS=$(python3 -c "import json,sys
for l in open('detect.out'):
    m=json.loads(l)
    if m.get('id')==2: print(json.dumps(m['result']['items']))")

{ printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"kinglet-probe","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"initialized"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"externalAgentConfig/import\",\"params\":{\"migrationItems\":$ITEMS,\"source\":\"kinglet-probe\"}}"; sleep 20; } \
  | CODEX_HOME="$PROBE_HOME" codex app-server
```

It answered `{"importId":"…"}`, streamed `externalAgentConfig/import/progress`
notifications, and finished with `externalAgentConfig/import/completed`.

Reported outcome: **31 successes, 0 failures** — 16 SKILLS, 8 SUBAGENTS, 4 HOOKS,
2 COMMANDS, 1 AGENTS_MD.

Files created in the repo:

| Path | Content |
|---|---|
| `.codex/hooks.json` | Claude Code's `settings.json` `hooks` block, structurally verbatim |
| `.codex/hooks/*.sh` | all 13 files from `.claude/hooks/` (12 hooks + `_lib.sh`), **byte-identical** by sha256 for 13/13, mode `775` both sides. `_lib.sh` is copied but appears **0 times** in `hooks.json` — the importer copies the directory without inventing a hook from the shared library |
| `.codex/agents/<name>.toml` | 8 agents, converted from Markdown to TOML |
| `.agents/skills/<name>/SKILL.md` | 16 skills + 2 commands-as-skills |
| `AGENTS.md` | rewritten copy of `CLAUDE.md` |

**No migrated content** was written to the disposable `CODEX_HOME` — at
`includeHome:false` this migration is entirely repo-scoped, and
`find "$PROBE_HOME" -iname '*unity*' -o -iname '*kinglet*'` returns **0**. The home
is *not* otherwise untouched, and an earlier draft of this file wrongly said it
was: running the app server populates it with Codex's own state — `cache/`,
`plugins/`, `sessions/`, `shell_snapshots/`, `config.toml`, `installation_id`,
`models_cache.json`, four sqlite stores (`goals_1`, `logs_2`, `memories_1`,
`state_5`, each with `-shm`/`-wal`), `tmp/`, and `skills/.system/` holding **six
populated built-in skills** (the same six `skills/list` reports below). That is
app-server startup, not import.

### Three losses, none of them reported as a failure

**1. Seven of nine commands are dropped.** Only `unity-doctor` and `unity-init`
migrate.

**Criterion.** A command is *dropped* iff its name does not appear in the
`COMMANDS` item's `details.commands` of a `detect` run against a repo containing
it.

**Fixture recipe** — one single-command git repo per variant, all detected in one
call, because `cwds` takes an array:

```bash
mk(){ d="$B/$1"; mkdir -p "$d/.claude/commands"; git -C "$d" init -q .
      printf '%s\n' '---' 'name: x' 'description: "d"' '---' "$2" > "$d/.claude/commands/x.md"; }
mk plain     'Do the thing.'
mk arguments 'Do the thing: $ARGUMENTS'
mk notargs   'Do the thing: $NOTARGUMENTS'
mk positional 'Do the thing: $1'
mk price     'Do the thing costing $5.'
mk regex     'Use the pattern s/foo/bar/ and $ anchors.'
mk shellvar  'Run: echo $HOME'
# then one detect with "cwds":["$B/plain","$B/arguments", …]
```

| Body | Detected |
|---|---|
| `Do the thing.` | yes |
| `Do the thing: $ARGUMENTS` | **no** |
| `Do the thing: $NOTARGUMENTS` | yes |
| `Do the thing: $1` | **no** |
| `Do the thing costing $5.` | **no** |
| `Use the pattern s/foo/bar/ and $ anchors.` | yes |
| `Run: echo $HOME` | yes |

**The trigger is syntactic, not semantic: `$ARGUMENTS` or `$` followed by a
digit.** Calling it "an argument placeholder" is too narrow and a future author
will read that as "avoid `$ARGUMENTS`". A price, a `$1` in a shell example, or a
positional reference in prose drops the command with the same silence. A bare `$`
and `$HOME` are both fine.

Kinglet's seven argument-taking commands (`unity-fix`, `unity-optimize`,
`unity-prototype`, `unity-review`, `unity-scene`, `unity-test`, `unity-ui`) all
contain `$ARGUMENTS`; the two that migrate contain no `$`-token of either form.
They never appear in `detect`, so `import` reports success while they are absent —
there is no failure entry to notice.

Stripping the `args:` frontmatter key does **not** help; emptying the body does.
`args:` is irrelevant to the importer, and `$ARGUMENTS` in the frontmatter
`description:` does not drop a command either — the scan is body-scoped.

**2. `.claude/rules/` is not migrated at all.** There is no `RULES` item type —
the enum is `AGENTS_MD, CONFIG, SKILLS, PLUGINS, MCP_SERVER_CONFIG, SUBAGENTS,
HOOKS, COMMANDS, MEMORY, SESSIONS`. No `rules/` directory is created anywhere. The
five binding spine rules plus `pc-console.md` do not cross, while the migrated
payload keeps referring to them.

**3. A blind `Claude` → `Codex` string substitution corrupts the payload.** It is
applied to migrated Markdown and TOML (not to the copied `.sh` files) and it does
not distinguish a path from a product name:

- **84 `.claude/` path references are rewritten to `.Codex/`, of which 29 are
  `.Codex/rules/`.** Note the capital `C`: this is not even Codex's own directory
  (`.codex`), and for `rules/` the target does not exist under *either* spelling
  (see loss 2).

  The 84 is a superset spanning several different repairs, so do not scope a fix
  off it. Counted by occurrence over the imported tree, split by what follows the
  prefix:

  | Rewritten to | Occurrences |
  |---|---|
  | `.Codex/rules/` | **29** |
  | `.Codex/skills/` | 23 |
  | `.Codex/scripts/` | 9 |
  | `.Codex/NOTICE.md` | 4 |
  | bare `.Codex/` | 4 |
  | `.Codex/settings.json` | 3 |
  | `.Codex/commands/` | 3 |
  | `.Codex/agents/` | 3 |
  | `.Codex/UPSTREAM` | 2 |
  | `.Codex/hooks/` | 2 |
  | `.Codex/templates/` | 1 |
  | `.Codex/state/` | 1 |
  | **total** | **84** |

  ```bash
  # the derivation, over the imported tree (.agents/ + .codex/ + AGENTS.md)
  { grep -roh '\.Codex/[A-Za-z0-9_.-]*' .agents .codex; grep -oh '\.Codex/[A-Za-z0-9_.-]*' AGENTS.md; } \
    | sort | uniq -c | sort -rn
  ```

  By file rather than occurrence: **26 of the 31 rewritten files** contain some
  `.Codex/` reference and **23 of 31** contain `.Codex/rules/` specifically, where
  the rewritten class is the 30 Markdown/TOML files under `.agents/` and `.codex/`
  plus `AGENTS.md`.

  **The ledger.** Each figure is labelled with the side it is counted on —
  *source* means the `.claude/` files before the import, *output* means the imported
  tree after it. That labelling is what would have prevented the misattribution
  above.

  ```
  source  85 refs in the md/toml class  =  output 84 rewritten to .Codex/  +  output  1 surviving .claude/
  source  30 of those are rules refs    =  output 29 rewritten             +  output  1 surviving
                                           output 22 survivors total       =  that 1  +  21 in the .sh copies
  ```

  `84 + 22 = 106` only *looks* impossible against a source of 85: **21 of the 22
  survivors live in a different file class** — the 13 copied hook scripts, which the
  substitution never touches (`.Codex/` occurs in them **0** times). Those 21 were
  never inside the 85.
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

**Command** — note `cwds`, per the trap above; without it these answer for the
wrong repository:

```bash
{ printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"kinglet-probe","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"initialized"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"skills/list\",\"params\":{\"cwds\":[\"$REP\"]}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"hooks/list\",\"params\":{\"cwds\":[\"$REP\"]}}"; sleep 8; } \
  | CODEX_HOME="$PROBE_HOME" codex app-server
```

Measured with `skills/list` and `hooks/list` against the imported replica:

- **Skills load: 18 at `scope:"repo"`** — Kinglet's 16 plus the 2 migrated commands,
  every one `"enabled":true`. **Quote the 18, not the total.** The total is not
  stable and must not be relied on: this run saw 24 (18 repo + 6 built-ins named
  `imagegen`, `openai-docs`, `plugin-creator`, `review-agent`, `skill-creator`,
  `skill-installer`), while a second measurement on another disposable home saw 59,
  the extra 35 being `user`-scope skills the app server fetched over the network
  into a home that started empty. Only the repo-scope 18 is a fact about Kinglet.
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

  **These are registration counts, not firing counts, and the distinction is the
  whole of F3.** Registering is what `hooks/list` reports; firing is what a marker
  file proves. Measured firing, per event:

  | Event | Registered | Observed firing | Where |
  |---|---|---|---|
  | `preToolUse` | 5 | **yes** | F4's whole rig |
  | `sessionStart` | 2 | **yes** | the `timeoutSec` probe |
  | `postToolUse` | 4 | **yes** | F5, `v-allow` on `PostToolUse` — fired once, `marker PRESENT` |
  | `stop` | 1 | **yes** | Task 3's re-review, `fires=1`; and end to end in `findings.md` `## Hooks`, where `session-save.sh` wrote `session.json` |

  **All four of the events Kinglet registers are now observed firing.** `stop` was
  the last one, and it read *"not measured — no probe has driven it"* here until
  2026-08-16. It fires, and its payload is the distinct one: `last_assistant_message`
  and `stop_hook_active`, and **no tool fields at all** — no `tool_name`, no
  `tool_input`, no `tool_response`. That is the shape `session-save.sh` is handed.

  `postToolUse` fires with `hook_event_name: "PostToolUse"`, `tool_name: "Bash"`, the
  same single-key `tool_input`, **plus a `tool_response`** (a string for the shell
  tool) that `preToolUse` does not have. That matters because 4 of Kinglet's 12
  hooks are `PostToolUse` (`warn-serialization`, `warn-filename`,
  `warn-platform-defines`, `track-edits` — derived from `.claude/settings.json`).
- **Matchers are carried across verbatim** — `Edit|Write`, `Bash`,
  `startup|clear|compact` — i.e. Claude Code's tool names, untranslated. Whether
  they nevertheless *match* is measured below, and the answer is yes.
- **The command string is single-quoted** into the JSON:
  `"command": "'/abs/path/.codex/hooks/block-scene-edit.sh'"`.
- **`timeout` is copied unchanged, and the field is seconds — measured, see next
  section.** Kinglet's `.claude/settings.json` values are copied into
  `.codex/hooks.json` untouched and re-reported by `hooks/list` as `timeoutSec`.
  The distribution across the 12 is **`3000` ×6, `5000` ×5, `2000` ×1** — not
  uniform — so as seconds they are 50, 83 and 33 minutes respectively.

Registering is not firing, and the two are measured separately below.

### The `timeoutSec` unit, measured rather than read off the field name

This section exists because an earlier draft asserted "Codex reads seconds" on the
strength of the field being *named* `timeoutSec`. That is the same class of error
this whole task exists to eliminate — a name read as a contract — and Codex's own
schema does not support it: `HookMetadata.timeoutSec` in `v2/HooksListResponse.json`
is `{"type":"integer","format":"uint64","minimum":0}` with **no description**, while
the only unit documented anywhere in the protocol is `timeoutMs`, *milliseconds*,
on the MCP request pair.

**Probe.** A single `sessionStart` hook that sleeps 2 s and then touches a marker
file, run twice with only the timeout changed. If the unit is seconds, `5` outlives
a 2 s sleep and `1` does not; if it is milliseconds, both kill it.

```bash
# .codex/hooks.json: one SessionStart command hook -> hooks/slow.sh, "timeout": N
# hooks/slow.sh:  sleep 2; touch ../../MARKER_COMPLETED
printf '[projects."%s"]\ntrust_level = "trusted"\n' "$T" > "$PROBE_HOME/config.toml"
CODEX_HOME="$PROBE_HOME" codex exec --dangerously-bypass-hook-trust \
  --sandbox read-only -C "$T" "reply with the single word ok" < /dev/null
```

| `timeout` | stderr | marker written |
|---|---|---|
| `5` | `hook: SessionStart Completed` | **yes** |
| `1` | `hook: SessionStart Failed` | **no** |

**Verdict: the unit is seconds, and the timeout is enforced.** `1` cuts off a 2 s
hook; `5` does not. Milliseconds is refuted — under that reading both runs would
have been killed at 5 ms and 1 ms. The control matters: without the `timeout: 1`
run, "completed" would equally support "the timeout is ignored entirely".

So Kinglet's `timeout: 3000`, meaning milliseconds in `.claude/settings.json`,
really does become a 50-minute timeout under Codex, and the two other values become
83 and 33 minutes. Benign until a hook hangs, at which point it hangs the session.

### Hooks do fire, and Claude Code's tool-name matchers do match

Also measured with the rig above, and it **refutes** what an earlier draft of this
file flagged as the sharpest risk for Task 4. Four `preToolUse` hooks were
registered at once, each tagged so the fired ones could be told apart, and the model
was asked to create a file:

```bash
# four preToolUse entries, matchers: "Edit|Write", "Bash", "shell", ""
CODEX_HOME="$PROBE_HOME" codex exec --dangerously-bypass-hook-trust \
  --sandbox workspace-write -C "$T" \
  "Create a file named probe.txt containing the word hello. Then stop." < /dev/null
```

| Matcher | Fired |
|---|---|
| `Edit\|Write` | **yes**, once |
| `Bash` | **yes**, once |
| `""` (empty) | yes, twice — once per tool call |
| `shell` | **no** |

stderr showed `hook: PreToolUse` ×4 and `hook: PreToolUse Completed` ×4, and
`probe.txt` was created. Two tool calls occurred: a file write, which matched
`Edit|Write` and the empty matcher, and a shell command, which matched `Bash` and
the empty matcher.

**Codex accepts Claude Code's tool names as matcher aliases.** The literal `shell`
matcher not firing is the discriminating half — it rules out "the matcher is
ignored" and "everything matches everything". Kinglet ships exactly two tool-name
matchers, `Edit|Write` and `Bash` (derived from `.claude/settings.json`, covering 9
of its 12 hook entries), and both are in the fired set, so **matchers need no
translation**.

**That is true of matching and it is not the whole story. Read the next section
before drawing any conclusion about Kinglet's hooks** — the tool *name* a matcher
sees and the tool *payload* a hook parses are two different vocabularies, and only
the first one is Claude Code's.

### Codex's file tool is `apply_patch`, and its `tool_input` is a patch envelope

The matcher aliases hide a different payload underneath. An empty-matcher
`preToolUse` hook that dumps its stdin was registered, and the model was driven
through three kinds of turn.

```bash
# .codex/hooks.json: one PreToolUse entry, matcher "", command -> dump.sh
# dump.sh:  cat > "dumps/payload-$(date +%s%N).json"
CODEX_HOME="$PROBE_HOME" codex exec --dangerously-bypass-hook-trust \
  --sandbox workspace-write -C "$T" \
  "Edit the existing file Assets/Scenes/Main.unity: change the m_Name value to Controlled." < /dev/null
```

Captured, for **editing an existing file**:

```json
{ "hook_event_name": "PreToolUse",
  "tool_name": "apply_patch",
  "tool_input": { "command": "*** Begin Patch\n*** Update File: Assets/Scenes/Main.unity\n@@\n-  m_Name: Main\n+  m_Name: Controlled\n*** End Patch" },
  "cwd": "…", "session_id": "…", "tool_use_id": "…", "turn_id": "…",
  "model": "…", "permission_mode": "…", "transcript_path": "…" }
```

and for **creating a new file**, the same single-key shape with a different verb:

```
"command": "*** Begin Patch\n*** Add File: Assets/Scenes/Second.unity\n+m_Name: Second\n*** End Patch"
```

For a **shell** turn the payload is Claude Code's shape exactly —
`"tool_name": "Bash"`, `"tool_input": {"command": "…"}`.

So `tool_input` for the file tool carries **one key, `command`**, holding a patch
envelope. There is **no `file_path`, no `new_string`, no `old_string`, no
`content`.** (Incidentally the path form is not even consistent between the two
verbs: `Update File:` carried an absolute path in one capture and a relative one in
another, while `Add File:` was relative.)

**The control that makes the negative mean something.** The same hook, the same
edit to the same file, run twice with only the payload *shape* changed:

```bash
bash .claude/hooks/block-scene-edit.sh < claude-shape-payload.json
bash .claude/hooks/block-scene-edit.sh < real-codex-payload.json   # captured above
```

| stdin | exit | bytes |
|---|---|---|
| Claude Code shape (`tool_input.file_path = Assets/Scenes/Main.unity`) | **2** | **412** — blocks, as designed |
| real Codex `apply_patch` payload, same edit, same file | **0** | **0** — does nothing |

The hook is not broken; the payload is different.

**Criterion for the class below.** A tool-event hook is *inert under Codex* iff,
given a real `apply_patch` payload for an edit that makes its Claude-shaped control
act, it takes no action — where "action" is non-zero exit, any output, or any state
written. Applied to every tool-event entry in `.claude/settings.json`, each hook
paired against its own control:

| Hook | Claude-shape control | real Codex payload | |
|---|---|---|---|
| `block-scene-edit` | exit 2, 412 B | exit 0, 0 B | INERT |
| `block-meta-edit` | exit 2, 360 B | exit 0, 0 B | INERT |
| `block-legacy-input` | exit 2, 769 B | exit 0, 0 B | INERT |
| `guard-project-config` | exit 2, 267 B | exit 0, 0 B | INERT |
| `warn-serialization` | exit 0, 392 B | exit 0, 0 B | INERT |
| `warn-filename` | exit 0, 309 B | exit 0, 0 B | INERT |
| `warn-platform-defines` | exit 0, 430 B | exit 0, 0 B | INERT |
| `track-edits` | writes `session-edits.txt`, 1 line | **file not created** | INERT |
| `bash-gate` | — reads `.tool_input.command` — | exit 2, 1363 B | **survives** |

**8 of the 9 tool-event hooks match, run, and do nothing.** `track-edits` needed its
state file measured rather than its stdout, since it writes no output either way.
`bash-gate` survives because `command` is the one field Codex supplies, and it is
live rather than vacuously passing: fed a real captured Codex `Bash` envelope it
exits 0 on a benign read command and exits 2 with 1363 bytes when the command is one
it targets.

The remaining 3 of Kinglet's 12 hooks (`session-restore`, `session-brief`,
`session-save`) are not tool events and are untouched by this.

The break is entirely in `tool_input`: **no Kinglet hook reads `tool_name` at all**
— it appears once in the whole hook directory, in a comment in `block-scene-edit.sh`.

**What this does and does not mean.** It does **not** mean the hooks fail to
register — all 12 register, `warnings: []`. It does **not** mean matchers are broken
— they match, measured above. It means the payload schema is where the port breaks,
one level below where a matcher test looks. A reader who takes either of the first
two away from this section has been misled by framing rather than by facts.

### What Task 2 left open, and where it was closed

Whether a hook can actually *veto* a tool call, and by what protocol. Task 2
exercised none of it and recorded it as an open question. **It is now closed: see
`## F4` below**, which measures two independent block mechanisms and the five
near-miss shapes that fail open. This paragraph is kept rather than deleted
because the section above is written as Task 2's hand-off and a reader arriving
at it should not have to guess whether the hand-off was ever taken up.

The vocabulary Task 2 pointed at, for orientation: `HookRunStatus` includes
`blocked` and `stopped`, and `HookOutputEntryKind` includes `stop`, `feedback`,
`context`, `warning`, `error`. **None of those enum values is what a hook emits** —
they are app-server reporting types, and F4 measures the emission side, which is a
different vocabulary. `HookEventName`'s full enum, unchanged: `preToolUse,
permissionRequest, postToolUse, preCompact, postCompact, sessionStart, sessionEnd,
userPromptSubmit, subagentStart, subagentStop, stop`.

Note also that every hook above ran only because `--dangerously-bypass-hook-trust`
was passed; hooks registered as `trustStatus: "untrusted"` and nothing in this
session granted persisted hook trust. **How trust is granted normally was unmeasured
when this paragraph was written and is measured now — `## F5` below.** It is config,
not a method: one `[hooks.state."<key>"]` table per entry in the *user home's*
`config.toml`, carrying the `currentHash` that `hooks/list` reports. Both block
mechanisms were then re-run under legitimate trust with no bypass flag in argv, and
neither result changed.

### Where the MCP server row came from

`MCP_SERVER_CONFIG` reports `UnityMCP`, but this repo contains no `.mcp.json`.
The source is the per-project `mcpServers` entry under
`~/.claude.json` → `projects["/home/riive/Documents/Github/kinglet-unity"]`. So an
item can be *scoped* to a repo while being *read* from the user's home file — a
detection against a copy of the repo at a different path does not reproduce it,
which is why the replica used above produced 5 items rather than 6.

### Agent conversion drops every tool grant

All 8 `.claude/agents/*.md` carry `name`, `description`, `model`, `color`, `tools`.
All 8 produced `.codex/agents/*.toml` carry exactly `name`, `description`,
`developer_instructions` — nothing else. Across the 8 files, the keys `model`,
`color` and `tools` each appear **0** times, and the string `mcp__UnityMCP` appears
**0** times. Every MCP grant Kinglet's agents depend on is gone, and the
`developer_instructions` body carries the `.Codex/rules/` corruption inside it.
Whether a Codex subagent can be granted MCP tools at all is unmeasured here.

**What this means for the wave:** the importer is real and worth shipping *toward*,
but it cannot be the port. It carries skills and agents across usefully, it
produces the `.codex/hooks.json` that Task 3 was to discover, it proves the target
layout (`.agents/skills/`, `.codex/agents/*.toml`, `.codex/hooks.json`,
`AGENTS.md`), and — measured above — the hooks it writes register and fire with
Kinglet's own matchers untranslated.

Against that: it silently drops 7 of 9 commands, never migrates the rules layer at
all, rewrites 84 `.claude/` path references to a non-existent `.Codex/` (29 of them
`.Codex/rules/`), strips every agent's tool grants, and — the one that survives all
the way to runtime — hands the hooks a `tool_input` none of them can read, so 8 of 9
tool-event hooks fire and do nothing. All of it while reporting 31 successes and
zero failures.

A Kinglet user who runs the importer gets a configuration that looks complete, and
whose hooks look live in `hooks/list`, and which does not enforce a single one of
the file-level rules those hooks exist to enforce. That is the strongest argument in
this document for Kinglet shipping its own Codex layout rather than telling users to
import. The wave's remaining tasks stand; what changes is that Tasks 5 and 6 start
from a measured baseline, and that Task 4's real work is rewriting hook bodies
against the `apply_patch` envelope, not translating matchers.

## F4 — the block protocol

*Where the other numbers live: the plan assigns F2 (config location), F3 (event
names) and F5 (hash trust) to this task too, but Task 2 measured all three as a
side effect of driving the importer, and they are recorded above rather than
renumbered here — F2 under "What the import actually writes", F3 under "Event
names are accepted in Claude Code's spelling and normalised", F5 under "The
registered hooks are individually untrusted". F4 is the one that was still open.*

**Verdict: confirmed, and there are two protocols, not one.** A `preToolUse` hook
stops a tool call under Codex by **either** of these, independently:

1. **exit `2` with a non-empty message on `stderr`** — what Kinglet ships today
   through `unity_hook_block()`;
2. **`{"decision":"block","reason":"<non-empty>"}` on `stdout`** — what the string
   table suggested.

Both prevent the call outright, and both hand the model the reason **verbatim**.
**Kinglet's existing refusal path works unchanged.** The feared third failure layer
— hooks that still would not block even after the `apply_patch` payload problem is
fixed — **does not exist**.

Against that: **five near-miss shapes fail open, silently**, including two that a
reasonable implementer would expect to block.

> **Every run in this section passed `--dangerously-bypass-hook-trust`, which is
> explicitly not a shipping answer.** That flag is a measurement instrument, and
> F5 below measures what it was standing in for. **The two headline results were
> re-verified without it**, under trust granted the way a non-interactive installer
> would grant it — see F5's "F4 re-verified under legitimate trust". Neither result
> changed. The rest of this section's rows were not re-run un-bypassed, because
> hook trust gates *whether the hook runs at all* and not *what its output means*:
> once a hook runs, the protocol is the protocol. That reasoning is stated so a
> reader can reject it; the two rows that carry the wave were measured both ways
> rather than argued.

### The rig

The block *protocol* is measured in isolation from the `apply_patch` *payload*
problem above by using a probe hook that **refuses unconditionally** — it parses
nothing out of the payload, so nothing it does can depend on a field Codex does
not supply. Every run is paired against a hook that unconditionally allows, which
is what separates "the call was prevented" from "the model chose not to make it".

```bash
T=<disposable git repo>            # NOT this repository: the probe writes into it
PROBE_HOME=<mode 700 dir outside /tmp, holding a 600 copy of ~/.codex/auth.json>
printf '[projects."%s"]\ntrust_level = "trusted"\n' "$T" > "$PROBE_HOME/config.toml"

# $T/.codex/hooks.json — see the shape correction below
# $T/.codex/hooks/<variant>.sh — cats stdin to a log, then emits the variant's shape

CODEX_HOME="$PROBE_HOME" codex exec --json --skip-git-repo-check \
  --dangerously-bypass-hook-trust --sandbox workspace-write --cd "$T" \
  -o "$T/last.txt" \
  'Run exactly this one shell command and nothing else: touch codex-marker.txt
Then, in one short sentence, tell me whether it succeeded, and quote verbatim any
error or refusal text you were shown. Do not retry, do not use another method, do
not create the file any other way.' < /dev/null
```

**The top-level shape of `.codex/hooks.json` is not the event map.** Writing
Claude Code's `hooks` block at the top level is rejected, and `hooks/list` says so
rather than failing silently:

```
"warnings": ["failed to parse hooks config …/.codex/hooks.json: unknown field
`PreToolUse`, expected `description` or `hooks` at line 2 column 14"]
```

The accepted top level is `{"hooks": {…}}` — this is what Task 4 must write:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "",
        "hooks": [ { "type": "command", "command": "'/abs/path/hook.sh'", "timeout": 20 } ] }
    ]
  }
}
```

**`description` is optional**, measured: a `{"hooks": {…}}` file with no
`description` key at all registers clean at `warnings: [], errors: []`, and the
importer itself writes the no-`description` form. An earlier draft of this section
showed the config *with* `description` under "what Task 4 must write", which reads
as though both keys are required; they are not.

Registered clean at `warnings: []`, `errors: []`, `enabled: true`,
`trustStatus: "untrusted"`. Every run below used the **empty matcher**, so the hook
fires on whichever tool the model reaches for; across all **17** runs it fired
**exactly once** each — derived, not assumed:

```bash
ls <evidence>/block/*.fired.log | wc -l                                           # -> 17
for f in <evidence>/block/*.fired.log; do grep -c '^FIRED ' "$f"; done | sort -u   # -> 1
```

The table below lists 12 of those 17. The other five are the same variants driven
against the file tool (`v-allow-patch`, `v-exit2-stderr-patch`, `v-json-block-patch`
— see the `apply_patch` table), the `RUST_LOG=debug` re-run
(`v-json-empty-reason-v`), and `v-kinglet-lib-default`, which is the `unset` arm of
the `UNITY_HOOK_MODE` table below.

**One run had to be thrown away, and the way it failed is the trap to avoid.** The
probe script selects its behaviour from its own `basename`, and the first
`apply_patch` attempt was installed as `v-exit2-stderr-patch.sh` — which matches no
branch of that `case`, so it fell through to the default and **exited 0**. The run
completed, the file was created, and it looked exactly like *"the block does not
work on the file tool"* — a false negative that would have been the single most
consequential wrong answer available in this section. It was caught because the
hook logs the variant name it resolved. The measurement was re-run after the
dispatch was fixed to strip the suffix, and both mechanisms then blocked. The
discarded run is not in the table; its accidental allow is, however, exactly the
control the `apply_patch` block needed, and it was re-run deliberately as
`v-allow-patch` rather than relied on in that form.

### What was measured

`marker` is the filesystem — did `touch codex-marker.txt` actually happen. `cmd
item` is the count of `command_execution` items in the `--json` event stream: the
allowed runs carry one with `"exit_code": 0`, and **the blocked runs carry none at
all**, so the block happens at the router before the tool runs rather than being
the model declining.

| Variant | hook emits | exit | marker | cmd item | model told |
|---|---|---|---|---|---|
| `v-allow` | *nothing* | 0 | **PRESENT** | 1 | — (control) |
| `v-exit2-stderr` | `BLOCKED: …` on **stderr** | **2** | **ABSENT** | **0** | **verbatim** |
| `v-json-block` | `{"decision":"block","reason":"…"}` on **stdout** | 0 | **ABSENT** | **0** | **verbatim** |
| `v-kinglet-lib` | real `unity_hook_block()` | **2** | **ABSENT** | **0** | **verbatim** |
| `v-json-block-exit2` | both at once | 2 | **ABSENT** | **0** | verbatim, **stderr text wins** |
| `v-exit2-silent` | *nothing* | **2** | PRESENT | 1 | nothing |
| `v-exit1-stderr` | `BLOCKED: …` on stderr | **1** | PRESENT | 1 | nothing |
| `v-exit2-stdout` | `BLOCKED: …` on **stdout**, not JSON | 2 | PRESENT | 1 | nothing |
| `v-json-malformed` | unterminated JSON on stdout | 0 | PRESENT | 1 | nothing |
| `v-json-empty-reason` | `{"decision":"block","reason":""}` | 0 | PRESENT | 1 | nothing |
| `v-json-context` | `{"hookSpecificOutput":{…,"additionalContext":"…"}}` | 0 | PRESENT | 1 | **sentinel delivered** |
| `v-kinglet-lib-warn` | `UNITY_HOOK_MODE=warn` → stderr warning | 0 | PRESENT | 1 | nothing |

**Observed, verbatim.** Codex's stderr on a block, which confirms the string table's
`Command blocked by PreToolUse hook:` as real text rather than a guess:

```
ERROR codex_core::tools::router: error=Command blocked by PreToolUse hook: BLOCKED: kinglet probe refuses this call on purpose (exit2-stderr). Command: touch codex-marker.txt
```

and the model's own final message for the same run:

```
It failed: "Command blocked by PreToolUse hook: BLOCKED: kinglet probe refuses this call on purpose (exit2-stderr). Command: touch codex-marker.txt"
```

For the JSON mechanism the same two lines carry the `reason` field instead, with no
`BLOCKED:` prefix because nothing put one there:

```
ERROR codex_core::tools::router: error=Command blocked by PreToolUse hook: kinglet probe: refused via decision-block JSON on purpose. Command: touch codex-marker.txt
```

### The three questions, answered separately per mechanism

They are reported separately because they can differ, and merging them is the
failure mode this section was written to avoid. Here they happen to agree.

| | exit 2 + stderr | `decision:block` JSON |
|---|---|---|
| **1. Was the call actually prevented?** | **Yes.** No `command_execution` item; `codex-marker.txt` absent. For the file tool, no `file_change` item and `ProbeFile.cs` absent. | **Yes**, identically, on both tools. |
| **2. Did the model learn why?** | **Yes, verbatim** — the *entire* stderr, including Kinglet's own `BLOCKED: ` prefix, is interpolated into `Command blocked by PreToolUse hook: <stderr>. Command: <cmd>`. | **Yes, verbatim** — the `reason` string, same wrapper. |
| **3. What must the hook emit?** | Exit status exactly `2`, **and** at least one byte on stderr. Both are load-bearing; see the fail-open table. | Exit `0` (or 2), and a single JSON object on stdout with `decision` = `"block"` and a **non-empty** `reason`. |

**Both mechanisms were confirmed against both tools.** The table above drives the
shell tool; the file tool was driven separately with *"Create a new file named
ProbeFile.cs … use the file-editing tool, not the shell"*, whose payload the hook
logged as `tool_name: apply_patch`, `tool_input` keys `['command']` — the same
single-key envelope Task 2 measured:

| apply_patch run | `file_change` item | `ProbeFile.cs` |
|---|---|---|
| allowing hook (control) | present, `kind: "add"` | **PRESENT** |
| `exit 2` + stderr | none | **ABSENT** |
| `decision:block` JSON | none | **ABSENT** |

This matters more than it looks. The `apply_patch` envelope is why 8 of 9 Kinglet
hooks are inert, and it would have been reasonable to fear the veto was broken on
that tool too. It is not: **the payload is unreadable, the veto is not.**

### The fail-open class — five shapes that block nothing and say nothing

Every one of these produced a completely silent allow: nothing on Codex's stderr,
nothing in the event stream, nothing to the model. There is no failure to notice.

- **`exit 2` with no output at all.** The single most likely way to write a
  blocking hook, and it does nothing. The message is not decoration — it is the
  block.
- **`exit 1` with a message on stderr.** The block is keyed on status **2**
  specifically, not on "non-zero". A hook that dies under `set -e`, or exits 1 on
  its own error path, **fails open**. (Codes other than 0, 1 and 2 were not tested.)
- **A plain-text message on stdout with `exit 2`.** stdout is read *as JSON only*.
- **Malformed JSON on stdout.** Discarded without complaint.
- **`{"decision":"block","reason":""}`** — a block with an empty reason. The
  string table's `hook returned decision:block without a non-empty reason` suggested
  Codex has an opinion here, and **the measured opinion is to ignore the block
  entirely and say nothing about it**. Re-run under `RUST_LOG=debug`, that string
  does not appear anywhere in 30 KB of stderr, and neither does any `codex_core`
  hook module. So the near-miss is not merely unlogged at the default level; it is
  not logged at all.

**The positive control that makes those negatives mean something.** Without it,
"malformed JSON was ignored" is indistinguishable from "stdout is never read".
`v-json-context` emitted well-formed JSON that is not a block —
`{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"KINGLET-CONTEXT-SENTINEL-9471"}}`
— and the sentinel reached the model, which quoted it back.

**This control needs its own prompt, and the rig's prompt will not surface it.**
The rig above asks the model to quote *"any error or refusal text"*; `additionalContext`
is neither, so the model answers the question it was asked and never mentions the
sentinel — on that evidence the control looks like it failed, and a re-runner
following the rig block literally will conclude exactly that. It is the one row in
this section that is not driven by the standard prompt. Use:

```
Run exactly this one shell command and nothing else: touch codex-marker.txt
Then tell me: did it succeed, and did you receive any additional context, note, or
sentinel string alongside that tool call? If you saw any string of the form
KINGLET-CONTEXT-SENTINEL-NNNN, quote it exactly.
```

With that prompt the final message is:

```
Yes, it succeeded (exit code 0). I received this additional sentinel string alongside the tool call:

`KINGLET-CONTEXT-SENTINEL-9471`
```

So stdout **is** parsed, Claude Code's `hookSpecificOutput` / `additionalContext`
container **is** honoured, and the five shapes above are rejected rather than
unread. This also settles, for free, that Kinglet's three advisory hooks have a
working delivery route under Codex — though they do not currently use it, since
they write plain text rather than JSON, and plain text on stdout is discarded.

### A hook Codex times out is a silent ALLOW — measured 2026-08-16

Left open by this section's first round, and reasoned about rather than measured
("given the measured contract, a hook Codex stopped waiting for cannot have
produced exit 2 + stderr"). The reasoning was right and it is now a measurement.

Two live runs, same rig, same never-finishing `PreToolUse` hook (`sleep 600`),
differing **only** in which ceiling is allowed to fire first:

| Which ceiling stops the hook | `file_change` items | the file | model told | `hook:` lines on Codex's stderr |
|---|---|---|---|---|
| the wrapper's own watchdog — shim **3 s**, Codex **4 s** | **0** | **ABSENT** | verbatim: `BLOCKED: … was killed by a signal (status 143) …` | **1** |
| **Codex's `timeoutSec`** — shim **60 s**, Codex **4 s** | **1** | **PRESENT** | *nothing* | **0** |

**Only ONE knob moves between the arms: the wrapper's own `--timeout`.** Codex's
ceiling is held at 4 s in both, so the arms differ in the *ordering* of the two
ceilings and in nothing else. An earlier version of this row read "Codex 6 s" for
the first arm; that figure was real — reconstructing that config and re-reading
`hooks/list` returns `preToolUse timeoutSec=6` — but it moved a second knob for no
reason, so the first arm was re-run with Codex held at 4.

**The `hook:` column is independent corroboration of "silent".** Codex printed a
hook line for the call its own hook refused and **nothing at all** for the one it
timed out — not a refusal, not a warning, not a failure. Grepping that arm's
stderr for `hook`, `block` or `timeout` in any case returns **0**.

**The first version of this experiment was also confounded, and the numbers above are
the re-run.** It disabled the wrapper's watchdog for the second arm, which also
changed the construct the wrapper was blocked in — a foreground hook instead of a
backgrounded one — so the two arms differed in the ceiling *and* in whether the
wrapper could answer a signal at all (measured 1.0 s versus 30.0 s). Here the
watchdog is **armed in both arms** and merely set above Codex's ceiling in the
second, so both sit in the same interruptible `wait` and only the firing ceiling
differs. The result did not change.

So `timeoutSec` expiry is not a refusal and is not reported: the tool call
proceeds and the model is told nothing at all, which puts it in the same
silent-allow class as the five near-miss shapes above. Nothing appeared on
Codex's stderr for the timed-out run.

**The consequence for anything wrapping a hook:** the wrapper's own ceiling must
be strictly below Codex's, or the wrapper cannot be the thing that refuses. A
wrapper whose ceiling is above `timeoutSec` never fires at all — it is killed
from outside, and being killed from outside is an allow.

### Precedence when both mechanisms fire

A hook that emits the JSON block **and** exits 2 with stderr blocks once, and the
reason the model receives is the **stderr** text. The JSON `reason` does not
appear. Emitting both is therefore safe but pointless; the stderr wins.

### `UNITY_HOOK_MODE=warn` behaves as an allow

Cheap probe run on the same rig, using Kinglet's real `_lib.sh` rather than a
re-implementation, so what is measured is the shipped code path. The hook logged
the variable it saw (`UNITY_HOOK_MODE=[warn]`), confirming Codex passes its own
environment through to hooks.

| `UNITY_HOOK_MODE` | `unity_hook_block()` does | marker | verdict |
|---|---|---|---|
| unset | stderr + `exit 2` | **ABSENT** | blocks, as designed |
| `warn` | stderr warning + `exit 0` | **PRESENT** | **allows, as required** |

The kill switch is correct under Codex. One asymmetry worth knowing: the
downgraded `WARNING (downgraded from BLOCKED): …` text is **silently swallowed** —
it reaches neither the model nor Codex's stderr, because a hook that exits 0 has
its stderr discarded. Under Claude Code that warning is surfaced. So `warn` mode
under Codex is not "block downgraded to warning", it is "block downgraded to
nothing". Converting it to a real warning means emitting `additionalContext` JSON
on stdout, per the control above.

**What this means for the wave.** Task 4 does **not** need a block-protocol
translation layer, and the wave is one failure layer shorter than feared. The exact
requirement for Task 4 to implement against:

> **To refuse a tool call under Codex, a hook must exit with status `2` and write
> at least one byte to stderr; that stderr is shown to the model verbatim.
> Equivalently it may exit `0` printing one JSON object on stdout with
> `"decision":"block"` and a non-empty `"reason"`. Anything else — exit 2 in
> silence, exit 1 with a message, plain text on stdout, malformed JSON, or a block
> with an empty reason — allows the call and reports nothing.**

Kinglet's `unity_hook_block()` already satisfies the first form exactly, on both
the shell tool and the `apply_patch` file tool. What remains broken for Kinglet's
hooks is only what Task 2 measured: they cannot read the `apply_patch` payload, so
8 of 9 never reach their refusal. Fix the payload and the refusal lands.

The `exit 1` result is the one to carry into Task 4's design. Kinglet's hooks run
under `set -euo pipefail`, and any unhandled failure inside one exits non-zero but
**not** `2` — under Claude Code that is read as an error, under Codex it is an
unlogged allow. A payload shim that dies on malformed JSON therefore fails open
silently, which is the worst available direction for a gate.

## F5 — hook trust

**Verdict: a trust step is required, and a non-interactive installer can satisfy it —
but only by writing the user's `$CODEX_HOME/config.toml`, never by shipping a file in
the repository.** Trust is per-hook-entry, keyed by a string that embeds the absolute
path of `hooks.json`, and it is granted by copying a hash that Codex computes and
`hooks/list` reports. `--dangerously-bypass-hook-trust` is not needed and is not
recommended.

### The baseline: registered, `enabled: true`, and silently not run

With the project already trusted (`trust_level = "trusted"`) but **no** hook trust and
**no** bypass flag:

```
hook fired:  0
marker:      PRESENT        (the call went through)
Codex stderr: no prompt, no warning, nothing
model said:  "The command succeeded."
```

while `hooks/list` for that same directory, at that same moment, reported
`registered 1, warnings [], errors [], enabled=True, trustStatus=untrusted,
statusMessage=None`.

**`enabled: true` does not mean it will run**, and `statusMessage` — the one field
whose name suggests it would explain this — is `null`. This is another
silent-failure layer, on top of the payload problem, the exit-code problem and the
matcher question, and it gates all of them: a user who installs Kinglet's hooks
correctly gets nothing, with no diagnostic, until trust is granted. (This paragraph
called it *"a fourth"*, which was true when it was written and is not a total: the
wave ended with **six**, and they are enumerated in one table in `findings.md`,
*"The six silent-failure layers, in one place"*. An ordinal written mid-measurement
is the same class of stale figure as a count.)

### The trust store: `hooks.state` in the home's `config.toml`

There is **no `hooks/trust` app-server method** — the enumeration returned by an
unknown-method error contains exactly two hook methods, `hooks/list` and the bogus one
used to trigger the list, and `ClientRequest.json` agrees: `hooks/list` is the only
`hooks/*` variant in the schema bundle. (The enumeration's *length* is not quoted
here; see "Do not quote a method count as a constant" above.) Trust is written as *config*: the binary carries
`config/batchWrite failed while updating hook trust in TUI` and a
`hooks.state."` config-path prefix, alongside a `HookStateToml { enabled, trusted_hash }`.

**The recipe, measured end to end.** Two steps, both scriptable:

```bash
# 1. read the key and the hash Codex computed — cwds, an array, per the trap above
{ printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"kinglet","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"initialized"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"hooks/list\",\"params\":{\"cwds\":[\"$T\"]}}"; sleep 8; } \
  | CODEX_HOME="$CODEX_HOME" codex app-server
# -> each hook: {"key": "<abs>/.codex/hooks.json:pre_tool_use:0:0",
#                "currentHash": "sha256:ab9c…", "trustStatus": "untrusted"}

# 2. write it back, verbatim, into the HOME's config.toml (one table per hook entry)
cat >> "$CODEX_HOME/config.toml" <<EOF
[hooks.state."<key>"]
enabled = true
trusted_hash = "<currentHash>"
EOF
```

`hooks/list` then reports `trustStatus: "trusted"`, and — the assertion that matters —
running **without** `--dangerously-bypass-hook-trust`:

```
=== v-exit2-stderr, NO bypass flag: fires=1 marker=ABSENT ===
model: It failed: "BLOCKED: kinglet probe refuses this call on purpose (exit2-stderr). Command: touch codex-marker.txt"
```

The hook fired, blocked the call, and the model was told why — with no dangerous flag
anywhere. **A non-interactive installer can do this.**

### F4 re-verified under legitimate trust

Both block mechanisms were re-run with trust granted as above and the bypass flag
removed. Neither result changed:

| Mechanism | fires | marker | model told |
|---|---|---|---|
| exit 2 + stderr | 1 | **ABSENT** | verbatim |
| `decision:block` JSON | 1 | **ABSENT** | verbatim |

So F4's contract for Task 4 stands as written; trust decides *whether* a hook runs,
not *what its output means*.

### Near-miss trust shapes, and what they report

`hooks/list`'s `trustStatus` is a free oracle — no model call — so these were
separated cheaply:

| `hooks.state."<key>"` contains | `trustStatus` |
|---|---|
| `enabled = true` + `trusted_hash` exactly matching `currentHash` | **`trusted`** |
| `enabled = true` + the hash with the `sha256:` prefix stripped | **`modified`** |
| `enabled = true` only, no `trusted_hash` | `untrusted` |
| nothing (no table at all) | `untrusted` |

The `sha256:` prefix is part of the stored value. A wrong hash reads as **`modified`**
— "modified since last trusted" — not as untrusted, which is a useful distinction for
an installer diagnosing its own output.

**Trust cannot ship in the repository.** Putting `trusted_hash` inside the matcher
group in `.codex/hooks.json` — the shape the string table's
`MatcherGroup { matcher, hooks, trusted_hash }` suggests — is **silently ignored**:
accepted with `warnings: []`, `trustStatus` still `untrusted`, and `currentHash`
unchanged. The app-server's own `ConfiguredHookMatcherGroup` schema has exactly two
properties, `matcher` and `hooks`, and no `trusted_hash`. So trust is **per user
home**, and a project cannot vouch for itself — which is the entire point of the gate,
and also the reason Kinglet cannot solve this by committing a file.

### What the hash actually covers — the config entry, not the script

This is the finding with the sharpest consequences, and it is the opposite of what
"trusting a hook" sounds like. Measured by mutating one thing at a time and re-reading
`currentHash`:

| Step | `currentHash` | sha256 of the script file |
|---|---|---|
| A. baseline | `sha256:da8eea…` | `sha256:fb99ea…` |
| B. **script body edited** | `sha256:da8eea…` — **unchanged** | `sha256:fccf5e…` — changed |
| C. config `timeout` 20 → 25 | `sha256:b64731…` — **changed** | — |
| D. `timeout` restored to 20 | `sha256:da8eea…` — back to baseline | — |

**Rewriting the hook script does not disturb its trust.** The hash is over the hook's
*declaration* — command string, timeout, matcher, event — not its *contents*, and it
is not the sha256 of the script by any reading (A's two columns differ). Adding an
unknown key to the matcher group left it unchanged too, so it covers specific fields
rather than the raw file bytes.

Two consequences, pulling in opposite directions:

- **Operationally good for Kinglet.** Updating a hook's body — which is what a toolkit
  upgrade does — does not invalidate trust and does not send the user back through a
  review prompt. Only changing the *registration* does.
- **A real security caveat, and it should be stated to users rather than buried.**
  Once a hook entry is trusted, anything that can write the script file can change
  what runs, with no re-review and no notification. Trust here means "I vouch for this
  command line", not "I vouch for this code".

Step D also establishes the hash is **deterministic**, not a nonce: restoring the
config restores the exact hash. It is **home-independent** — the same config read from
two different disposable `CODEX_HOME`s produced the identical hash — and
**path-dependent by construction**, since the hashed command string embeds the
absolute hook path. So it **cannot be precomputed and shipped**; it must be read from
`hooks/list` on the target machine at install time, which is why the recipe above is
two steps rather than one.

### The interactive path, for `docs/` to describe

Codex's TUI carries a startup hook review (`tui/src/startup_hooks_review.rs`). Its
strings, read from the binary rather than guessed:

```
Hooks need review
1 hook is new or changed.
Hooks can run outside the sandbox after you trust them.
Trusting hooks...
[Trust all and continue]  [Continue without trusting (hooks won't run)]
```

and per-hook status text: `New hook - review required`, `Trusted`,
`Modified since last trusted - review required`, plus `Managed hooks are always on`.

So a human running interactive `codex` in a Kinglet project is prompted once, sees the
hooks, and chooses. **This was read from the binary's strings, not exercised** — no
interactive TUI session was driven in this wave, and the exact keybindings and screen
layout are therefore unmeasured.

### `allow_managed_hooks_only` — the enterprise switch, unmeasured

`ConfigRequirements.allowManagedHooksOnly` (boolean, nullable) exists in the
app-server schema, beside `ManagedHooksRequirements` with its `managedDir` /
`windowsManagedDir` and a full event map. In the binary the key sits in the
managed-config cluster next to `allowed_sandbox_modes`, `allow_remote_control`,
`guardian_policy_config` and `enforce_residency` — i.e. the MDM surface, not the user
one. The TUI string `Managed hooks are always on` is consistent with managed hooks
bypassing the review entirely.

**This is unmeasured, in those words.** Nothing here set the switch or supplied a
managed config. What it would take: a managed-config source Codex reads (the
`legacyManagedConfigFile` / `legacyManagedConfigMdm` values in `HookSource` name two
routes), `allow_managed_hooks_only = true`, and a hook placed in `managedDir` — then
re-run the F5 baseline and see whether a project hook still registers and whether the
managed one runs untrusted. The reason it matters to Kinglet: if an organisation sets
it, Kinglet's project-scoped hooks may not run **at all**, and no amount of
`hooks.state` trust would change that.

### What this means for the wave

**F5's answer is the good one: a trust step exists, and a non-interactive installer
can satisfy it** — Task 9's installer reads `hooks/list` and appends one
`[hooks.state."<key>"]` table per hook to `$CODEX_HOME/config.toml`. That is a real
obligation and it has three properties Task 8/9 must design around:

1. **It writes the user's Codex home**, not the project. Kinglet has so far only ever
   written inside the project. An installer that edits `~/.codex/config.toml` needs
   consent, a backup, and an uninstall path — and `uninstall.sh` is receipt-driven, so
   the receipt must record the exact tables added.
2. **It needs Codex running to compute the hashes**, because they cannot be
   precomputed. Install-time ordering therefore is: write `hooks.json`, then query
   `hooks/list`, then write trust.
3. **Re-registration invalidates it.** Changing a hook's timeout or command path
   changes the hash and drops it back to `modified`; changing the script body does not.

And the honest framing for the ship: until this is implemented, everything F4 proves is
proved behind a flag Kinglet must not tell users to pass. With it implemented, Kinglet's
hooks run legitimately — and are then still inert against the `apply_patch` payload
until Task 4 fixes that. **The layers are independent, and every one of them has to be
right** — Task 4 shipped the shim and the ordered timeout ceilings, Task 9 shipped the
trust grant and found a sixth layer beneath all of them (an untrusted *project*
registers no hooks at all and says nothing). The full set is enumerated once, in
`findings.md`, rather than counted again here.
