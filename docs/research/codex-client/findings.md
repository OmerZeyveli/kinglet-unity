# Kinglet's surfaces under Codex CLI — findings

*Measured against `codex-cli 0.145.0`. Codex's own capabilities are in
`codex-facts.md`; this file is about Kinglet's surfaces running on top of them.*

**Sections are added by the task that measures them.** Task 4 wrote `## Hooks`.
Tasks 5–7 add skills, rules/`AGENTS.md`, commands, agents and the MCP routes;
Task 10 adds the A/B/C architecture decision and the stranded-machinery debt. A
section that is absent has not been measured, and no section here speaks for
another.

---

## Hooks

Kinglet ships 12 hooks (`.claude/hooks/*.sh` less the shared `_lib.sh`), all 12
registered in `.claude/settings.json`. Derive that set rather than trusting this
sentence:

```bash
ls .claude/hooks/*.sh | /usr/bin/grep -v '_lib\.sh$'
jq -r '.hooks|to_entries[]|.value[]|.hooks[].command' .claude/settings.json
```

**Verdict: hooks port with a named translation.** The translation is
`scripts/codex-hook-shim.sh`, and with it in place every one of the nine
tool-event hooks enforces under Codex — measured per hook against its own paired
control, and end to end against a live Codex session under legitimate hook trust,
with no `--dangerously-bypass-hook-trust` anywhere.

Without it, eight of those nine fire and do nothing.

### What was broken, and what was not

Four independent failure layers were feared. `codex-facts.md` measured all four.
Only one of them was real, and it is the one this task fixed:

| Layer | Status |
|---|---|
| Do the hooks register? | **Not broken.** All 12 register, `warnings: []`, `errors: []`. |
| Do Claude Code's matchers match? | **Not broken.** `Edit\|Write` and `Bash` both fire; a literal `shell` matcher does not, which is what rules out "everything matches everything". |
| Does a hook's refusal actually veto? | **Not broken.** `exit 2` + stderr vetoes on both the shell tool and `apply_patch`, and Kinglet's `unity_hook_block()` already emits exactly that. |
| Can the hooks read the payload? | **BROKEN.** Codex's file tool is `apply_patch` and its `tool_input` carries one key — `command`, a patch envelope. There is no `file_path`, `content`, `new_string` or `old_string`. |

A fifth gate sits above all of them and is not a defect: **hook trust**. A hook
registers `enabled: true` and still does not run until the user's
`$CODEX_HOME/config.toml` carries a `[hooks.state."<key>"]` table with a matching
`trusted_hash`. Granting it is the installer's job (`codex-facts.md` §F5); every
live result below was measured with trust granted that way.

### The translation

`scripts/codex-hook-shim.sh` normalises the patch envelope into the shape the
hooks already read, then runs one hook against it — once per file the patch
touches. **The hooks themselves are unchanged.** `.claude/hooks/*.sh` is a shipped
Claude Code surface with 122 assertions in `tests/test-hook-behaviour.sh` behind
it; one implementation with one test surface is worth more than twelve forks, and
`tests/test-codex-shim.sh` asserts that no file under `.claude/hooks/` so much as
mentions Codex.

| Patch verb | becomes | carrying |
|---|---|---|
| `*** Add File:` | `tool_name: "Write"` | `content` = the added lines |
| `*** Update File:` | `tool_name: "Edit"` | `new_string` = added, `old_string` = removed |
| `*** Delete File:` | `tool_name: "Edit"` | both empty; the path is the signal |
| `*** Move to:` | — | source **and** destination are each checked |

Paths are made absolute against the payload's own `cwd`. That is not cosmetic:
`block-legacy-input.sh` and `warn-platform-defines.sh` anchor their third-party
skips on a leading path segment (`*/Assets/Extensions/*`,
`*/Library/PackageCache/*`) and both record in their own comments that Claude Code
sends absolute paths. Handed Codex's relative `Add File:` path those anchors decide
differently — a vendored file would be gated and a first-party one might not be.
Both directions are asserted in the test.

### It fails closed, and that was the sharpest constraint

`codex-facts.md` measured **five shapes that allow the call and log nothing
anywhere**, including under `RUST_LOG=debug`: `exit 2` with no output, `exit 1`
with a message, plain text on stdout, malformed JSON, and a `decision:block` with
an empty `reason`. Two of those are what a careless script does by accident.

The one that matters for a shim: hooks run under `set -euo pipefail`, so **any
unhandled failure exits non-zero but not `2`** — Claude Code reads that as an
error, Codex reads it as an unlogged allow. A shim that dies on a malformed patch
envelope fails open, silently, forever.

Three things prevent it, and all three are load-bearing:

1. **`set -e` is deliberately not set** in the shim. Errexit there converts a bug
   into a silent allow.
2. **An EXIT trap converts every status that is neither 0 nor 2 into a 2 with a
   message on stderr** — unbound variable, missing `jq`, a signal, a `return`
   nobody checked.
3. **Nothing exits 2 without writing stderr**, including on behalf of a wrapped
   hook that refused in silence.

Every shape below is asserted in `tests/test-codex-shim.sh`, each on **both**
halves of the criterion — status `2` **and** non-empty stderr — because asserting
the status alone would pass a silent refusal, which is an allow. Count them from
the file rather than from a number here:

```bash
/usr/bin/grep -c '^refuses ' tests/test-codex-shim.sh
```

| Fed to the shim | Result |
|---|---|
| empty stdin; not JSON; truncated JSON; a JSON array; JSON `null` | refused |
| `apply_patch` with no envelope; with no `command`; with `tool_input` a string | refused |
| an envelope naming no file (`*** Begin Patch` … `*** End Patch` with no header) | refused |
| no `--hook`; a `--hook` naming a missing file; `--hook` with no value; an unknown flag; a non-numeric `--timeout` | refused |
| a wrapped hook that exits 1, exits 127, or dies on an unbound variable | refused |
| a wrapped hook that exits 2 **in silence** | refused, with the message the hook did not write |
| a wrapped hook that hangs | refused on the watchdog |
| `jq` absent from `PATH` | refused |
| a wrapped hook blocking via `decision:block` JSON on stdout | refused — Codex's other legal protocol, forwarded rather than collected as advice |
| a `decision:block` with an **empty** `reason` | refused — Codex ignores that shape and says nothing, so forwarding it would be a silent allow |

### The timeout unit — fixed, not merely named

Every one of the 12 entries in `.claude/settings.json` declares its `timeout` in
**milliseconds**. Codex's field is `timeoutSec` and the unit is **seconds** —
measured in `codex-facts.md`, not read off the field name. The external-agent
importer copies the number across untouched. Derived from the settings file:

```bash
jq -r '[.hooks|to_entries[]|.value[]|.hooks[]|.timeout]|group_by(.)|map({v:.[0],n:length})' \
  .claude/settings.json
```

| declared (ms) | hooks | as seconds, unconverted |
|---|---|---|
| 3000 | 6 | 50 minutes |
| 5000 | 5 | 83 minutes |
| 2000 | 1 | 33 minutes |

A hung hook that should die in three seconds would hold the turn for fifty minutes.

**Fixed at the source.** `codex-hook-shim.sh --emit-config` derives
`.codex/hooks.json` from `.claude/settings.json` and converts the unit by ceiling
division — ceiling, because a sub-second value must not round to `0`, which Codex's
schema accepts (`minimum: 0`) and which would kill every hook instantly. The
conversion lives with the shim rather than in an installer so that whatever writes
the Codex layout cannot get it wrong by omission, and `tests/test-codex-shim.sh`
derives the expected seconds from the settings file rather than quoting them.

Confirmed on the live rig — this is Codex's own report of what it registered, not
the generator's claim about itself:

```
registered: 12   trustStatus: {'trusted': 12}   warnings: []   errors: []
events: {'preToolUse': 5, 'postToolUse': 4, 'sessionStart': 2, 'stop': 1}
timeoutSec values: [2, 3, 5]
```

**Fixed a second time, independently, because the shim does not own that file.**
The shim carries its own per-invocation watchdog (default 15 s,
`KINGLET_CODEX_HOOK_TIMEOUT`), and expiry **refuses** — a gate that did not finish
has approved nothing. `timeout(1)` is GNU coreutils and absent on a stock macOS
host, so the watchdog is a background killer, which works on bash 3.2.

### Per-hook verdict

**The columns are not the plan's sketch, and the difference is deliberate.** That
sketch had a `Blocks` column; forcing a yes/no there is how an advisory hook gets
scored as broken for correctly declining to block. What each hook is *for* differs,
so what counts as acting differs, and the criterion is stated per row.

Two measurements stand behind every row:

- **Offline, per hook, four runs with its own paired controls** — the
  `CODEX-SHIM-PROBE` records emitted by `tests/test-codex-shim.sh`: `control`
  (Claude-shaped payload straight into the hook — what "acting" means for it),
  `raw` (real Codex payload straight in), `shim` (real Codex payload normalised),
  `negative` (a Codex payload with the trigger removed). A control that does not
  act **fails the file loudly** rather than scoring the case; that branch fired
  during development, on `warn-filename`, whose first trigger omitted the
  `: MonoBehaviour` base the hook actually keys on.
- **Live, end to end**, under real Codex with legitimate hook trust.

`rcN/NNNB/NL` = exit code / bytes of output / lines added to the edit-tracking
state file.

| Hook | Event | What "acting" is | control | raw Codex payload | through shim | negative | Live |
|---|---|---|---|---|---|---|---|
| `block-scene-edit` | PreToolUse | refuses: exit 2 + reason | rc2/443B | **inert** — rc0, 0B | **rc2/443B** | no action | **blocked** — `Main.unity` still reads `placeholder`, **0** `file_change` items, model quoted the refusal |
| `block-meta-edit` | PreToolUse | refuses: exit 2 + reason | rc2/399B | **inert** | **rc2/399B** | no action | not driven live — see below |
| `block-legacy-input` | PreToolUse | refuses: exit 2 + reason | rc2/806B | **inert** | **rc2/806B** | no action | **blocked** — `ProbeInput.cs` absent, **0** `file_change` items, model quoted the refusal |
| `guard-project-config` | PreToolUse | refuses: exit 2 + reason | rc2/308B | **inert** | **rc2/308B** | no action | not driven live — see below |
| `warn-serialization` | PostToolUse | warns: exit 0 + text | rc0/428B | **inert** | **rc0/541B** | no action | not driven live — see below |
| `warn-filename` | PostToolUse | warns: exit 0 + text | rc0/332B | **inert** | **rc0/438B** | no action | **warned** — model quoted `WARNING: File name 'Foo.cs' does not match class name 'Bar'.` verbatim |
| `warn-platform-defines` | PostToolUse | warns: exit 0 + text | rc0/469B | **inert** | **rc0/582B** | no action | not driven live — see below |
| `track-edits` | PostToolUse | writes a state line | rc0/0B/**1L** | **inert** — file not created | **rc0/0B/1L** | no action | **tracked** — `session-edits.txt` holds the created file's path |
| `bash-gate` | PreToolUse | refuses: exit 2 + reason | rc2/1233B | **acts** — rc2/1233B | rc2/1233B | no action | not driven live — it never needed the shim |
| `session-restore` | SessionStart | writes session state | — | not a tool event | passthrough, unwrapped | — | **fired** — wrote `session-start-time` |
| `session-brief` | SessionStart | prints a brief | — | not a tool event | passthrough, unwrapped | — | **registered, firing not established** — see below |
| `session-save` | Stop | writes `session.json` | — | not a tool event | passthrough, unwrapped | — | **fired** — wrote `session.json`, `modified_files` populated |

**`bash-gate`'s row asserts the opposite of the other eight, and that is what shows
the harness is not simply reporting "inert" for everything.** It survives unaided
because `command` is the one field Codex supplies. Its four runs also have to be
made independent by hand: it deliberately blocks the *first* attempt at a command
it cannot classify, records the hash, and allows the byte-identical retry. Left
alone, the control blocks and the three runs after it sail through, and the file
reports the shim as broken for the one hook that never needed it.

**`session-save` firing is new, and it corrects a gap rather than a claim.**
`codex-facts.md` records `stop` as *registered but never observed firing*, in those
words, because no probe had driven it. One did here: `session.json` was written,
carrying a `session_duration` computed against the `session-start-time` that
`session-restore` had written at `sessionStart`. So both ends of Kinglet's session
loop ran, in order, in one Codex session — and `modified_files` was populated from
the file `track-edits` recorded through the shim, which is the tracker's only
consumer.

**Why four hooks were not driven live, stated rather than implied.** Each live probe
is a model call, and what a live run adds over the offline pair is the *composition*
— Codex → shim → hook → veto → model — not the per-hook decision, which the offline
pair measures directly and which does not vary by hook. Four were chosen to cover
every distinct composition: a `PreToolUse` refusal on file *creation*
(`block-legacy-input`), a `PreToolUse` refusal on file *modification*
(`block-scene-edit`), a `PostToolUse` advisory delivery (`warn-filename`), and a
`PostToolUse` state write (`track-edits`) — plus the allow control below. The five
undriven tool-event rows are each the same composition as one that was driven. That
reasoning is written down so it can be rejected; the rows say "not driven live"
rather than borrowing a sibling's result.

**The allow control, which is what makes the blocks mean something.** A file that is
absent because the model chose not to write it is not a block. Same rig, same prompt
shape, same session, a file that violates nothing:

| Live probe | file | `file_change` items | model said |
|---|---|---|---|
| `block-legacy-input` violation | `ProbeInput.cs` **absent** | **0** | quoted the refusal |
| **allow control** | `ProbeClean.cs` **present** | **1** | "created successfully; no error or refusal text was shown" |

Zero `file_change` items on the blocked runs is the discriminator: the veto lands at
the router *before* the tool runs, rather than being the model declining.

**`session-brief` is the one hook whose firing is not established.** Its matcher is
`startup|clear|compact` — a session *source*, not a tool name. Codex was measured
translating Claude Code's tool-name matchers, and nothing here measured which source
string it sends on `sessionStart`. Its sibling `session-restore`, registered on the
empty matcher, did fire. So the open question is the matcher, not the event. It is
also the hook with the least to lose: it prints a brief, and under Codex a hook that
exits 0 has its stderr discarded.

### What Codex gained that Claude Code never needed

Three of Kinglet's hooks are advisory: they exit 0 and write their warning to
stderr. Under Claude Code that is surfaced. **Under Codex the stderr of a hook that
exits 0 is discarded, and so is plain text on stdout** — stdout is read as JSON
only. Left alone, the three `warn-*` hooks would fire, act, and tell nobody: the
same defect as the payload problem, one layer further along.

The shim re-emits their text as `hookSpecificOutput.additionalContext`, the one
route `codex-facts.md` measured reaching the model. **Confirmed live, and this closes
a question `codex-facts.md` left open** — that route was measured on `PreToolUse`
only, while all three `warn-*` hooks are `PostToolUse`. The model's own words,
unprompted beyond being asked whether it received a note:

```
Yes, it succeeded.

I received this warning alongside the tool call:

> WARNING: File name 'Foo.cs' does not match class name 'Bar'.
>   ...
>   Fix: Rename the file to 'Bar.cs' or rename the class to 'Foo'.
```

The same route repairs `UNITY_HOOK_MODE=warn`, which `codex-facts.md` measured as
*"block downgraded to nothing"* under Codex — the downgraded warning reached neither
the model nor Codex's stderr. Through the shim it is delivered as context. The kill
switches themselves (`DISABLE_UNITY_HOOKS`, `DISABLE_HOOK_<NAME>`,
`UNITY_HOOK_MODE=warn`) all still reach the hook through the wrapper; a gate a user
cannot switch off is worse than one that misfires, and `warn` is exactly the switch
reached for when a gate is wrong.

### Known false positives, in the fail-closed direction

A patch hunk shows only the changed lines, where Claude Code's `Write` carries the
whole file. Three hooks reason over content and can therefore see less than they
would under Claude Code:

- **`block-legacy-input`** exempts legacy input that is properly guarded, by looking
  for `#if ENABLE_LEGACY_INPUT_MANAGER` **and** `ENABLE_INPUT_SYSTEM` in the same
  content. A hunk that edits one line inside an already-guarded block shows neither,
  so the edit is refused. The user retries with more context, or switches the hook
  off for that call.
- **`warn-platform-defines`** counts `#if` against `#else` in the content. A hunk
  carrying the `#if` and not its `#else` warns spuriously.
- **`warn-filename`** wants the content to declare a type matching the file name. A
  fragment usually will not — **but this is unchanged from Claude Code**, where an
  `Edit`'s `new_string` is equally a fragment. Parity, not a new defect.

All three err towards acting. That is the correct direction for a gate whose
alternative failure is being silently dead, and it is the same tie-break
`block-legacy-input.sh`'s own comments record for its path anchors.

### What this means for the ship

**The hook layer is shippable, and it needs three things shipped with it, not one.**
Shipping `.codex/hooks.json` alone reproduces the measured failure exactly:
registered hooks, matching matchers, and not a single file-level rule enforced.

1. **`scripts/codex-hook-shim.sh` must be installed wherever `.codex/hooks.json`
   points.** The config's command strings carry absolute paths to both the shim and
   the hook.
2. **`.codex/hooks.json` must be generated, not hand-written** — `--emit-config` is
   the ms→s conversion's only home, and a hand-written file reintroduces the
   fifty-minute timeout silently.
3. **Hook trust must be granted at install time**, by appending one
   `[hooks.state."<key>"]` table per entry to the user's `$CODEX_HOME/config.toml`.
   It cannot be precomputed (the hash embeds the absolute path of `hooks.json`) and
   it cannot ship in the repository (a project cannot vouch for itself). Ordering is
   fixed: write `hooks.json` → query `hooks/list` → write trust.

`--dangerously-bypass-hook-trust` is a measurement instrument and must never appear
in anything Kinglet tells a user to run. Nothing in this section needed it.

**The honest residual:** step 3 writes the user's home directory, which Kinglet has
never done. That needs consent, a backup, and a receipt entry — it is named here
because it is this section's finding, and owned by the tasks that build the
installer.

Kinglet does not currently install `codex-hook-shim.sh` into a project: `install.sh`
skips it alongside `check-provenance.sh` and `codex-probe.sh`, because under Claude
Code it has nothing to do. Which layer ships the Codex configuration, and therefore
where the shim lands at install time, is the ship list's decision and not this
section's.

### Reproducing

The offline half, per hook, with its paired controls:

```bash
bash tests/test-codex-shim.sh
bash tests/run-tests.sh 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g' | /usr/bin/grep '^CODEX-SHIM-PROBE'
```

The live half needs a disposable `CODEX_HOME` (mode 700, outside `/tmp`, holding a
600 copy of `~/.codex/auth.json`, removed by an EXIT trap) and a disposable project
— never this repository, because the probe writes into it. In outline:

```bash
# 1. a project with Kinglet's .claude/ and the shim beside it, then:
bash "$T/.claude/scripts/codex-hook-shim.sh" --emit-config --project-dir "$T" > "$T/.codex/hooks.json"

# 2. project trust, in the DISPOSABLE home
printf '[projects."%s"]\ntrust_level = "trusted"\n' "$T" > "$PROBE_HOME/config.toml"

# 3. read the keys and hashes Codex computed — `cwds` is an ARRAY, and results come
#    back nested under result.data[].hooks; with `cwd` the server answers about the
#    wrong repository. Hold stdin open past the reply or the answer cannot arrive.
{ printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"kinglet","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"initialized"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"hooks/list\",\"params\":{\"cwds\":[\"$T\"]}}"; sleep 10; } \
  | CODEX_HOME="$PROBE_HOME" codex app-server

# 4. append one table per entry, then run WITHOUT any bypass flag
#    [hooks.state."<key>"]  enabled = true  trusted_hash = "<currentHash>"
CODEX_HOME="$PROBE_HOME" codex exec --json --skip-git-repo-check \
  --sandbox workspace-write --cd "$T" -o last.txt '<prompt>' < /dev/null
```

Raw transcripts land under `docs/research/codex-client/evidence/`, which
`.gitignore` excludes — the verdicts are here, the credentials never are.
