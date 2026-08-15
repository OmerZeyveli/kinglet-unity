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
JSON-RPC `-32600` and the error text enumerates **129** methods — every one this
build accepts — which is the negative control the rest of this file relies on:

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
| `skills/list` with `cwd` | `/home/riive/…/kinglet-unity` (**wrong repo**) | 6 skills |
| `skills/list` with `cwds` | `<replica>` | 24 skills |

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

  It reconciles source-side: that class holds **85** `.claude/` references before
  the import, of which **30** are `.claude/rules/`; 84 were rewritten and exactly 1
  `.claude/rules/` reference survived un-rewritten.
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

**Codex presents its tools to hook matchers under Claude Code's tool names.** The
literal `shell` matcher not firing is the discriminating half — it rules out "the
matcher is ignored" and "everything matches everything". Kinglet's shipped matchers
therefore do not need translation. This is a Task 4 result reached early because the
timeout probe had already built the rig; it is recorded here rather than expanded,
and it does **not** settle the block protocol.

**What remains unmeasured, and is handed to Task 4:** whether a hook can actually
*veto* a tool call, and by what protocol. The schema offers the vocabulary —
`HookRunStatus` includes `blocked` and `stopped`, and `HookOutputEntryKind` includes
`stop`, `feedback`, `context`, `warning`, `error` — but nothing here exercised it, so
the block protocol is an open question, not a finding. `HookEventName`'s full enum,
for whoever picks that up: `preToolUse, permissionRequest, postToolUse, preCompact,
postCompact, sessionStart, sessionEnd, userPromptSubmit, subagentStart, subagentStop,
stop`.

Note also that every hook above ran only because `--dangerously-bypass-hook-trust`
was passed; hooks registered as `trustStatus: "untrusted"` and nothing in this
session granted persisted hook trust. How trust is granted normally is unmeasured.

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
`AGENTS.md`), and — measured above — the hooks it writes really do fire with
Kinglet's own matchers. Against that, it silently drops 7 of 9 commands, never
migrates the rules layer at all, rewrites 84 `.claude/` path references to a
non-existent `.Codex/` (29 of them `.Codex/rules/`), and strips every agent's tool
grants — all while reporting 31 successes and zero failures. A Kinglet user who runs
the importer gets a configuration that looks complete and is not. The wave's
remaining tasks stand; what changes is that Tasks 5 and 6 now start from a measured
baseline instead of an open question, and that Kinglet has a positive reason to ship
its own Codex layout rather than tell users to import.
