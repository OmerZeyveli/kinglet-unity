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
   message** — unbound variable, missing `jq`, a `return` nobody checked.
3. **Explicit arms for `TERM`, `INT`, `HUP` and `PIPE`.** This list said "a
   signal" under item 2 and that was **false when written**: the EXIT arm alone
   left a signalled shim at 143/130/129/141 with an *empty* stderr, which is the
   measured silent-allow class. It is reachable by what Kinglet itself emits —
   Codex enforces `timeoutSec` by killing the hook from outside — and by any
   Ctrl-C (`SIGINT`) or closed terminal (`SIGHUP`). Fixed and asserted; see
   "The timeout unit" below for the ordering that keeps it from arising, and
   the residual for what stays uncovered.
4. **Nothing exits 2 without writing a reason**, including on behalf of a wrapped
   hook that refused in silence. Refusals go to a descriptor duplicated from the
   real stderr before any redirection exists to inherit.

**Why 3 and 4 are two defences and not one.** On an *untrapped* fatal signal bash
runs the EXIT trap and then re-raises, discarding the trap's own `exit 2`. The
trap runs — but if the shell was blocked in a **builtin** carrying redirections,
the trap inherits them, because only a builtin's redirection rewires the shell's
own descriptors. The shim blocks in `wait … >/dev/null 2>&1` for essentially its
whole life, so a refusal written to plain `>&2` went to `/dev/null`.

The rule is builtin-versus-external, not "redirected" — an earlier draft of this
paragraph said the latter, which is false for external commands and would mislead
a reader about which constructs are hazardous:

| EXIT arm only, refusal to `>&2`, killed at 0.6 s | message |
|---|---|
| `/bin/sleep 20 >/dev/null 2>&1` — external, redirected | **survives** |
| `/bin/sleep 20 2>./FILE` — external, redirected | **survives** |
| `wait "$p" >/dev/null 2>&1` — builtin, redirected | **lost** |
| `read -r x … 2>/dev/null` — builtin, redirected | **lost** |

| killed during a redirected `wait` | refusal to `>&2` | refusal to `>&9` |
|---|---|---|
| **EXIT arm only** | rc 143, 0 bytes | rc 143, message kept |
| **explicit TERM arm** | rc 2, message kept | rc 2, message kept |

`exec 9>&2` recovers the **message**; the signal arm recovers the **status**, and
recovers the message too, because a *trapped* signal's handler runs in the shell's
normal descriptor context. A status that is not 2 is an allow and a refusal nobody
can read is not a refusal, so both halves are load-bearing.

Every shape below is asserted in `tests/test-codex-shim.sh`, each on **both**
halves of the criterion — status `2` **and** non-empty stderr — because asserting
the status alone would pass a silent refusal, which is an allow. Count them from
the file rather than from a number here:

```bash
/usr/bin/grep -cE '^(refuses |  fail "SIG|  pass "SIG|  pass "refused)' tests/test-codex-shim.sh
```

(The jq-missing and signal rows are hand-rolled rather than `refuses` calls,
because each needs a bespoke environment; counting only `refuses` undercounts the
table it heads, which is how three documents came to quote three different
totals.)

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
| the shim itself killed by `SIGTERM` / `SIGINT` / `SIGHUP` / `SIGPIPE` | refused — was 143/130/129/141 with 0 bytes, a silent allow |
| a path walking out of an exempted directory (`Assets/Extensions/../Scripts/X.cs`) | refused — was rc 0, 0 bytes |
| a header the parser does not recognise, hiding behind a valid file | refused — was rc 0 |
| a header padded with a trailing space or tab | refused — was rc 0; `*.unity ` is not `*.unity` |

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

**And the two ceilings are ORDERED, which the first version got wrong.** The shim
carries its own per-invocation watchdog whose expiry **refuses** — a gate that did
not finish has approved nothing — and `--emit-config` now passes it explicitly:

| | value | why |
|---|---|---|
| shim `--timeout` | `ceil(ms/1000)` | exactly the budget `settings.json` declares |
| Codex `timeout` | `ceil(ms/1000) + 1` | one second of margin, so the shim always reports first |

The margin is added to Codex's number rather than subtracted from the shim's, so a
hook never silently loses budget it was declared with; subtracting would turn
`timeout: 2000` into a one-second hook.

**The ordering is load-bearing, and that is measured rather than argued.** Two live
runs, same never-finishing hook, differing only in which ceiling fires first
(`codex-facts.md`, "A hook Codex times out is a silent ALLOW"):

| Which ceiling stops the hook | `file_change` | the file | model told | `hook:` lines on Codex's stderr |
|---|---|---|---|---|
| the shim's own watchdog — shim **3 s**, Codex **4 s** | **0** | **ABSENT** | verbatim refusal | **1** |
| Codex's `timeoutSec` — shim **60 s**, Codex **4 s** | **1** | **PRESENT** | *nothing* | **0** |

Codex's ceiling is held at 4 s in both arms, so the only thing that moves is the
shim's own `--timeout` and therefore which ceiling is lower. The stderr column is
independent corroboration of "silent": Codex printed a hook line for the call its
hook refused and **nothing at all** for the one it timed out.

The watchdog is **armed in both arms** and merely set above Codex's ceiling in the
second, so the shim sits in the same interruptible `wait` either way and the only
difference is which ceiling fires. (The first version of this experiment disabled
the watchdog for the second arm, which also changed the shim's blocking construct
— 1.0 s versus 30.0 s signal response. That confound is removed here and the
result was unchanged.)

A hook Codex stops waiting for is a **silent allow**. So the one second of margin
is not tidiness: it is the whole difference between a hung hook refusing and a hung
hook waving an unchecked edit through.

**The first version emitted the bare conversion and passed no `--timeout` at all**,
leaving the shim on its 15 s default underneath a 2–5 s Codex ceiling. The shim's
watchdog could therefore *never* fire: every hook that outran the budget was killed
from outside by Codex — a signal, which at that point was a silent allow. Two
ceilings that cannot be ordered are one ceiling and a decoration, and the
"independent second mechanism" this paragraph used to claim was unreachable in the
shipped composition. The ordering is now asserted per entry.

**The budget bounds the whole invocation, not each step, and that is what makes
"the shim always reports first" true.** Bounding only the wrapped hook left two
phases free to run past Codex's ceiling with every individual step comfortably
inside its budget:

| phase | measured | budget in force |
|---|---|---|
| the jq normalisation (superlinear in added lines) | 8 000 lines 0.34 s, 20 000 2.05 s, **40 000 8.38 s** | `--timeout 3`, returned **0** |
| the loop, which spawns the hook once per **file** | **200 files 4.24 s** through `block-legacy-input` | emitted Codex ceiling **4 s** |

A signal cannot rescue either, because bash defers a trapped signal until the
current foreground command finishes — SIGTERM delivered 1.0 s into a 40 000-line
parse was answered at **8.55 s**. Both phases are now bounded against one
invocation deadline, and each hook run is given what is *left* rather than the
whole budget again. An envelope too large to check inside its budget is **refused**,
naming how many of its files were checked; that is the fail-closed direction, and
the alternative is Codex timing the hook out, which is a silent allow.

`timeout(1)` is GNU coreutils and absent on a stock macOS host, so the watchdog is
a background killer, which works on bash 3.2. Every child is backgrounded even when
unbounded, because a foreground child makes the shim unable to answer a signal for
as long as it runs — measured 30 s versus 1.0 s. Its `sleep` is given a closed copy of
the refusal descriptor: killing the killer does not kill the `sleep` it is blocked
in, and while that orphan held the descriptor open it held the *caller's* pipe open
for the full timeout on every invocation.

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
  for `#if ENABLE_LEGACY_INPUT_MANAGER` **or** `#if UNITY_EDITOR` — both spellings
  are accepted by its regex — **and** `ENABLE_INPUT_SYSTEM` in the same content. A hunk that edits one line inside an already-guarded block shows neither,
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

**Two named limitations of the generator, before an installer builds on it.**
`--emit-config` single-quotes paths without escaping, so a project path containing
a `'` produces a broken `hooks.json` entry; Codex's own importer has the same shape,
so this is parity rather than regression, but it should be validated or refused
rather than emitted. And a shim killed with `SIGKILL` exits 137 with nothing, which
Codex reads as an allow — nothing in a shell script can defend against that, and it
is named here rather than left implied.

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

---

## Skills

Kinglet ships 16 skills at `.claude/skills/<name>/SKILL.md`, flat. Derive that
rather than trusting this sentence:

```bash
ls -d .claude/skills/*/ | wc -l
```

| Question | Verdict | Evidence |
|---|---|---|
| Discovered once a skill root exists | **yes** — **18 at `scope:"repo"`** after the importer runs, every one `"enabled":true`, `errors: []` | `skills/list` with `cwds` against `skillrig` |
| App-server `skills/list` agrees with the model's self-report | **yes for all 18 repo-scope**, name for name; **no** at system scope — the model omits one built-in | `t5-selfreport` |
| **Invoked when relevant without being named** | **yes** — a *topical* skill was loaded in **5 of 5** relevant probes; in 3 controls, two loaded nothing at all and the third loaded only `using-kinglet` | `t5-unnamed-*`, `t5-chain`, `t5-control*` |
| Second copy needed | **one directory symlink** — `.agents/skills → ../.claude/skills` **discovers all 16**, and **2 of them were invoked** through that rig (`input-system`, `using-kinglet`). Codex reading `.claude/skills/` unaided is **refuted** (0 skills), and so is the `skills` config key. A byte copy is not needed. A further route works — `skills/extraRoots/set` — but is `user`-scoped and does not persist | `skillrig-nolink`, `skillrig-symlink`, `t5-symlink-input`, the config-key and extra-roots tables below |

**Verdict: skills port, and of the surface classes measured in this wave so far they
are the only one that needs no translation at all** — `## Hooks` above needed a shim;
rules, commands and agents are Task 6's and unmeasured here. They need a *root* —
`.claude/skills/` is not one — and of the five routes measured below, a symlink is
the cheapest that is both per-project and persistent. The importer's own copy also
works for discovery and invocation, but it arrives with 13 skill→skill path
references rewritten to a directory that does not exist; the symlink route has zero
of those, because it leaves the files untouched.

**Two things this section must not be read as saying.** *Discovery is not
invocation*: 16 or 18 skills are discovered, and the probes below invoked **6
distinct skills in total** across every rig and prompt — 5 of the 18 in `skillrig`,
3 of 18 in `skillrig-noguide`, 2 of 16 in `skillrig-symlink`. Nothing measured here
invoked the rest by any route, and no cell in the table above should be read as
"all 16 work". And *"cheapest route" is scoped to the five routes tried here* —
`.claude/skills/` unaided, the `skills` config key, a directory symlink, the
importer's copy, and `skills/extraRoots/set` — not to everything Codex offers. A route nobody enumerated is not a route that was refuted.

Every measurement below ran under a disposable `CODEX_HOME` (mode 700, outside
`/tmp`, a 600 copy of `~/.codex/auth.json`, removed by an EXIT trap) with
`--ignore-user-config`, so nothing here is a fact about the owner's own skills. The
probe rigs are real fixture Unity projects with Kinglet installed by `install.sh`,
not hand-built directories.

**No project trust was granted anywhere in this section, and skills loaded anyway.**
That is the sharp difference from `## Hooks` above: a hook is registered and silently
skipped until `$CODEX_HOME/config.toml` vouches for it, while a skill in an untrusted
project is listed, injected and read. Codex says so itself in the warning
`codex-facts.md` §F5 records — *"…are disabled in the following folders until the
project is trusted, but skills still load"* — and every probe here is that sentence
measured.

### The 18 is 16 + 2, and the 2 are commands

The repo scope reports **18** while `.claude/skills/` holds **16**. The two extras
are not skills at all: they are the two commands the importer converts *into* skills,
because Codex has no command surface to migrate them to.

```bash
ls .agents/skills | /usr/bin/grep '^source-command-'
# source-command-unity-doctor
# source-command-unity-init
```

Each is a generated `SKILL.md` whose body is the original command file under a
`## Command Template` heading, with the frontmatter `description:` copied from the
command's own — **copied and then substituted, like everything else the importer
touches**. `unity-doctor`'s description is byte-identical to the command's;
`unity-init`'s differs by exactly the substitution this document inventories, *"when
`CLAUDE.md` still has unfilled `FILL:` markers"* becoming *"when `AGENTS.md` still
has…"*. Right for the new layout, and a reminder that no copy here is a clean copy. `externalAgentConfig/detect` reports them under `COMMANDS`, not
`SKILLS` — 16 skills and 2 commands go in, 18 directories come out of one tree — and
`skills/list` cannot tell them apart afterwards, because by then they are just
directories with a `SKILL.md`.

They are the *two* commands that survive the `$ARGUMENTS` drop (`codex-facts.md`
§"Three losses"); the other seven never reach the importer at all. So the 18 is
16 + 2 in this repository and would be 16 + N in a project whose commands differ.
**Quote the repo-scope figure and say it is repo-scope.** The scope-mixed total is
not stable across homes and is not a fact about Kinglet: this run's home saw 24
(18 repo + 6 system built-ins), a home in Task 2 saw 59, the extra 35 fetched over
the network from `plugins/cache/openai-curated-remote/`.

### One skill root is required, and `.claude/skills/` is not it

Three trees, one `skills/list` call, `cwds` as an array:

| Rig | What it has | Repo-scope skills |
|---|---|---|
| `skillrig-nolink` | Kinglet installed, `.claude/skills/` with all 16, nothing else | **0** |
| `skillrig-symlink` | the same, plus `.agents/skills → ../.claude/skills` | **16**, all `enabled:true`, `errors: []` |
| `skillrig` | the same, after `externalAgentConfig/import` | **18**, all `enabled:true`, `errors: []` |

The first row is the one that decides the ship: a project with `.claude/skills/`
sitting right there and no `.agents/skills/` gives Codex **no** Kinglet skills. "No
second copy — Codex reads `.claude/skills/` directly" is refuted, not unmeasured.

The symlink is transparent in the direction that matters and **it is a discovery
device, not a load path**. `skills/list` resolves it and reports the **real** path —
`…/skillrig-symlink/.claude/skills/input-system/SKILL.md`, not the `.agents/` route —
so the model is handed the real path and reads *that* (`t5-symlink-input`). Nothing
measured here loads a skill *through* `.agents/skills`; the symlink's whole job is to
make Codex look at a directory it otherwise ignores. One symlink, 16 skills
discovered, no duplicated bytes and nothing to keep in sync — and 2 of those 16
observed loading, in one probe, which is what "it works" rests on.

Untested, and it matters for a second host: whether a directory symlink survives on
Windows, and whether Unity's asset pipeline objects to one outside `Assets/`
(`.agents/` is outside, so it should not import at all). Neither was measured here.

### The `skills` configuration key — tried under two spellings, refuted

The plan proposed pointing a `skills` configuration key at the repository's
`.claude/skills`. **There is no such key.** A silent negative is worthless without a
control proving the file was read at all, so every attempt carried one: the same
`config.toml` also holds a `[projects."<skillrig>"] trust_level = "trusted"` entry,
whose effect is independently visible in `hooks/list` (`codex-facts.md` §F5 —
untrusted 0 hooks, trusted 12).

| `$CODEX_HOME/config.toml` | `hooks/list` on `skillrig` (the control) | `skills/list` repo-scope on `skillrig-nolink` |
|---|---|---|
| absent | **0** — untrusted, as expected | 0 |
| trust entry + `skills = ["<abs path to .claude/skills>"]` | **12** — the file was read and parsed | **0** |
| trust entry + `[skills]` table with `extra_roots = […]` | **12** | **0** |
| trust entry alone (control) | **12** | 0 |

Both spellings are **silently ignored** — no error on stderr, no `errors[]` entry,
and the trust entry in the same file took effect in all three runs, which is what
rules out "the file was rejected". `forceReload: true` was set on every `skills/list`
call, so a cache is not the explanation either.

The schema agrees, and it is an oracle rather than a measurement: `config/read`'s
`Config` object has **23 keys** and not one of them is a skills root
(`analytics, approval_policy, approvals_reviewer, compact_prompt, desktop,
developer_instructions, forced_chatgpt_workspace_id, forced_login_method,
instructions, model, model_auto_compact_token_limit, …, tools, web_search`). The only
skills-related configuration key anywhere in the schema bundle is `skill_approval`,
which is about approvals, not roots.

### `skills/extraRoots/set` — a route that works and cannot be shipped

`ClientRequest.json` carries `skills/extraRoots/set` one entry after `skills/list`.
It works. Measured before and after in **one** session, so the difference is the call
and nothing else:

| Step | repo | user | system |
|---|---|---|---|
| `skills/list cwds:[skillrig-nolink] forceReload:true` | 0 | 0 | 6 |
| `skills/extraRoots/set extraRoots:["<skillrig-nolink>/.claude/skills"]` → `{}` | | | |
| the same `skills/list` again | 0 | **16** | 6 |

All 16, `enabled:true`, `errors: []`, every `path` the real
`…/skillrig-nolink/.claude/skills/<name>/SKILL.md` — **no symlink and no copy**.

Two measured limitations keep it from displacing the symlink, and they are the
reason this route is recorded rather than recommended:

- **It lands at `scope:"user"`, not `"repo"`.** A per-project toolkit registered
  globally is the wrong shape: every other project the session touches gets Kinglet's
  16 skills too.
- **It does not persist, and no installer can reach it.** After the call the
  disposable home has **no `config.toml`**, and no file under it names the root path
  (`/usr/bin/grep -rl` over the whole home: nothing). It is an app-server request, so
  a client can send it per session — while `install.sh` writes files, and the file
  route is the one refuted directly above.

**What that does not license.** These five routes are the ones tried; they are not an
enumeration of everything Codex offers. `skills/extraRoots/set` was found by reading
one schema file to the end, after the first three routes had already been written up
as complete.

### The detector, and both directions it can be wrong in

Codex has no skill *tool*. `ThreadItem`'s variant list — derived from
`ItemCompletedNotification.json` — carries `commandExecution`, `mcpToolCall`,
`dynamicToolCall` and fifteen others, and **no skill item**. The names and
descriptions are injected into the model's context instead (a bare "list your skills"
prompt is answered with **no tool call at all**, off 16 580 input tokens), and a skill
is *loaded* when the model reads its `SKILL.md` with the shell tool. So the
observable is a `command_execution`:

```bash
/bin/bash -lc "sed -n '1,240p' .agents/skills/using-kinglet/SKILL.md"
```

**Read the `command` field, never the raw transcript.** A loaded skill's body is
echoed into `aggregated_output`, and Kinglet's skill bodies cite each other by path —
which the importer rewrote to `.Codex/skills/<name>/SKILL.md`. Grepping the whole
`.jsonl` therefore scores those citations as loads: on `t5-unnamed-save-noguide` the
loose pattern reports four skills where two were loaded, and on `t5-chain` it reports
**five where two were loaded** — the phantoms are `.Codex/skills/…` paths that exist
under no spelling on disk. The correct derivation:

```bash
python3 - <<'PY'
import json, re, sys
pat = re.compile(r'[A-Za-z0-9_./-]*skills/[a-z0-9-]+/SKILL\.md')
loaded = set()
for line in open(sys.argv[1] if len(sys.argv) > 1 else
                 'docs/research/codex-client/evidence/t5-unnamed-save.jsonl'):
    line = line.strip()
    if not line:
        continue
    try:
        event = json.loads(line)
    except ValueError:
        continue
    item = event.get('item') or {}
    if item.get('type') == 'command_execution':
        loaded.update(pat.findall(item.get('command') or ''))
print(' '.join(sorted(loaded)) or '(none)')
PY
```

A model sentence like *"I'm using the `using-kinglet` skill"* is not evidence either.
It happens to have been true in every probe here, but it is the model's claim about
itself, and the whole point of the `command` field is that it is not.

**And the other direction, which a refinement always owes.** Narrowing from "any
event" to "the `command` field of a `command_execution`" can only under-count if some
*other* item type can read a file. Enumerated across all 11 transcripts, the item
types present are exactly two — `agent_message` (21) and `command_execution` (32) —
inside five event types (`thread.started`, `turn.started`, `item.started`,
`item.completed`, `turn.completed`). There is no `fileChange`, `mcpToolCall` or
`dynamicToolCall` anywhere, so there is nothing for the refinement to have dropped.
One residual stays open by construction: a glob read such as
`cat .agents/skills/*/SKILL.md` would satisfy no per-name pattern and score as zero
loads. **0** commands of that shape occur in these transcripts, and a future probe
must re-check rather than inherit that.

### Invocation, measured against three controls

Eleven probes, one prompt each, `--sandbox read-only`, `codex-cli 0.145.0`, every one
exit 0. `skillrig` is the imported rig; `skillrig-noguide` is that rig with
`AGENTS.md`, `CLAUDE.md`, `.claude/` and `.codex/` **deleted**, leaving
`.agents/skills/` as the only Kinglet text in the tree.

| Probe | Rig | Skill named in the prompt? | Skills loaded | Reads as |
|---|---|---|---|---|
| `t5-selfreport` | `skillrig` | asks for the list | **none** | a self-report is not a load |
| `t5-named` | `skillrig` | yes — `save-system` | `save-system` | **detector positive control**: naming one does load it |
| `t5-unnamed-save` | `skillrig` | no | `using-kinglet`, **`source-command-unity-init`** | routed by the unfilled `FILL:` markers |
| `t5-unnamed-input` | `skillrig` | no | `using-kinglet`, **`input-system`** | domain skill reached |
| `t5-unnamed-input-noguide` | `skillrig-noguide` | no | `using-kinglet`, **`input-system`** | same, with no project guide in the tree |
| `t5-unnamed-save-noguide` | `skillrig-noguide` | no | `using-kinglet`, **`unity-brainstorming`** | the process chain's entry |
| `t5-chain` | `skillrig` | no | `using-kinglet`, **`unity-planning`** | the chain's *next* hop |
| `t5-symlink-input` | `skillrig-symlink` | no | `using-kinglet`, **`input-system`** (via `.claude/skills/`) | the symlink route invokes |
| `t5-control` | `skillrig` | no — nothing relevant | **none** | **control 1**: not everything loads a skill |
| `t5-control-api` | `skillrig` | no — Unity-domain, nothing project-specific | **none**, and **no command at all** | **control 2**: the hard case for `using-kinglet` |
| `t5-control-addressables` | `skillrig` | no — collides with the `addressables` topic | `using-kinglet` **only** | **control 3**: topic collision, and the topical skill was *declined* |

**The bold entry in each unnamed row is where the claim lives.** `using-kinglet` is
one of the two in every one of them, and its description says *"use at the start of
every session"* — so it alone would be consistent with unconditional loading. The
topic-appropriate claim rests entirely on the second entry, and the three controls are
what give that second entry meaning:

- **`t5-control`** — "how many lines in `ProjectVersion.txt`?" The model ran `wc -l`,
  answered `2`, loaded nothing.
- **`t5-control-api`** — "what does `Time.fixedDeltaTime` return?" A *Unity-domain*
  question, which is the hardest case for a skill whose description claims every
  session. Answered correctly from knowledge with **no shell command at all** and no
  skill.
- **`t5-control-addressables`** — "does this project list Addressables in
  `Packages/manifest.json`?" A prompt colliding head-on with the `addressables` skill's
  topic. The model loaded `using-kinglet`, **did not** load `addressables`, read the
  manifest and answered `No.` That is evidence for *task*-driven loading rather than
  topic-keyword matching — the direction a keyword-matching mechanism could not
  produce.

Without these, "the relevant skill loaded" and "a skill always loads" would be the
same observation.

**The `noguide` rows are what rule out the second confound.** The imported `AGENTS.md`
carries a *"Skills matching this project"* block naming `input-system` and
`urp-pipeline`, so the `skillrig` rows alone cannot separate "Codex's skill index
routed the model" from "the project guide told it to". Two things separate them.
First, `AGENTS.md` never names `using-kinglet`, `save-system` or
`source-command-unity-init` — `/usr/bin/grep -c` returns 0 for each — and those are
the skills the unnamed probes loaded. Second, with `AGENTS.md`, `CLAUDE.md`, `.claude/`
and `.codex/` deleted outright, `input-system` and `using-kinglet` were still loaded
unnamed. The routing is Codex's own injected index, not Kinglet's guide.

**The injected index is measured, not inferred, and the stripped rig is the stronger
leg.** Two independent observations carry it. `t5-selfreport` produces a correct
23-name list with **zero** tool calls, so the names were already in context. And in
`t5-unnamed-input-noguide` the model's **first** shell command goes straight to
`.agents/skills/input-system/SKILL.md` — no `ls`, no `find`, no `rg` beforehand, in a
tree where nothing else names that path. It looked for the guide only *afterwards*,
and failed: command 4 is `sed -n '1,260p' AGENTS.md` at **exit 2** ("No such file or
directory"), command 5 an `rg --files -g 'AGENTS.md' … ..` at **exit 1** with no
output. A path known before any search is a path that was handed over.

**The answers are Kinglet-shaped, not generic Unity advice**, which is the second half
of the distinction the brief demanded. `t5-unnamed-input-noguide`, with no rules file
anywhere in the tree, answered: *"The project's `InputView` should own
`PlayerControls`, enable it in `OnEnable`, disable it in `OnDisable` … pass that value
to the movement system through `SetMoveInput(Vector2)`; don't use the legacy `Input`
API"* — `InputView`, `SetMoveInput`, one owner of `PlayerControls`, all of it
`architecture.md`'s Input System section restated after reading
`.agents/skills/input-system/SKILL.md`. Generic advice here is `Input.GetAxis`, and
none of the five probes produced it.

**The three outcomes, kept separate as required:**

- **loaded** — 5 of 5 relevant unnamed probes, observable in the `command` field.
- **Kinglet-shaped guidance produced *without* loading** — **not observed**, in any
  probe. Every Kinglet-shaped answer here followed a read of the skill that carries it.
- **neither** — 2 of 3 controls loaded nothing at all; the third loaded only the
  session-entry skill and declined the topical one. All three are the correct outcome
  for their prompt.

**What this is not.** Each probe is n = 1 against a stochastic model. The verdict is
"a relevant skill is reached for", not "a relevant skill is reached for every time",
and no probe here measured *which* skill is chosen when several are relevant. What the
controls establish is that loading is task-driven rather than unconditional. **Nor is
this a claim about the library**: 6 distinct skills were ever observed loading — 5 of
`skillrig`'s 18, 3 of `skillrig-noguide`'s 18, 2 of `skillrig-symlink`'s 16 — and the
other twelve have been measured as *discoverable*, not as reachable.

### What the model claims, and what the harness loaded

`t5-selfreport` asked the model to list its skills; `skills/list` was asked the same
question about the same tree.

- **All 18 repo-scope skills agree, name for name.** The set difference is empty in
  that direction.
- **They disagree by one at system scope**: the app server reports six built-ins, the
  model lists five, omitting `review-agent`. The app server wins — it is reading the
  disk, the model is reporting its own context.

The disagreement is small and it is in the harmless direction for Kinglet (nothing of
Kinglet's is missing), but it is recorded because the rule that produced it is the
load-bearing one: **a model's self-report is not evidence of what the harness loaded.**
Both figures are scope-mixed totals; neither reproduces across homes, and neither
should be quoted as a fact about anything.

### What the importer's copy costs, and the symlink does not

The skills that arrive via `externalAgentConfig/import` carry the blind
`Claude` → `Codex` substitution `codex-facts.md` measured tree-wide. Scoped to
`.agents/skills/` in `skillrig`:

| Rewritten to | Occurrences |
|---|---|
| `.Codex/rules/…` | 19 |
| `.Codex/skills/…` | 13 |
| `.Codex/scripts/…` | 7 |
| everything else (`.Codex/`, `settings.json`, `NOTICE.md`, `state`, `hooks`, `commands`, `agents`) | 11 |

**17 of the 18 skill directories carry at least one** — `verification-before-completion`
is the only clean one. Two of those groups matter here:

- **The 19 `.Codex/rules/` references point at rules that never migrate at all** —
  there is no `RULES` item type. A skill that says *"where this skill and the rule
  disagree, the rule wins"* now cites a path that exists under no spelling.
- **The 13 `.Codex/skills/…/SKILL.md` references are the process chain's own wiring**,
  spanning 8 distinct targets. **0 of the 8 resolve. All 8 exist**, one directory
  over, at `.agents/skills/<name>/SKILL.md`. The rewrite broke every skill→skill hop
  in the library and reported **32 successes, 0 failures**.

**That 32 is not the 31 in `codex-facts.md`, and both are right — the subjects
differ.** 32 is counted over a **real installed Unity project** (`skillrig`:
`mkproject.sh` + `install.sh --yes`), which has a `.mcp.json`, so `detect` returns a
sixth item type: 16 SKILLS + 8 SUBAGENTS + 4 HOOKS + 2 COMMANDS + 1 AGENTS_MD +
**1 MCP_SERVER_CONFIG**. `codex-facts.md`'s 31 is counted over a **replica of this
repository** that copied only `.claude/` and `CLAUDE.md`, so it has no `.mcp.json` and
no MCP row. Same importer, different tree.

The same references in the untouched tree — the symlink route — resolve 8 of 8.

**The chain still worked in the probe, and that is not a licence to leave the paths
broken.** `t5-chain` loaded `using-kinglet` and then `unity-planning` by its real
path, never attempting the dead `.Codex/` one: the model routes by *name* from the
injected index and constructs the path itself, so a dead path in the body is text it
can work around. It worked around it in 5 of 5 probes here. That is one model, at
n = 1 per probe, and the failure mode when it does not work around it is a silent
`No such file or directory` mid-turn.

### What this means for the ship

Three things, and none of them is code:

1. **A skill root must exist.** `install.sh` writes `.claude/skills/`; Codex reads
   `.agents/skills/`. Something has to bridge them. Of the five routes measured here,
   two are refuted (`.claude/skills/` unaided, the `skills` config key), one works but
   is `user`-scoped and unpersisted (`skills/extraRoots/set`), and two work and
   persist: a directory symlink and the importer's copy. **The symlink is the cheapest
   of those five, which is not the same as the cheapest that exists** — the fifth was
   found by reading one more schema entry after the first three were written up.
2. **Prefer the symlink to the importer's copy.** Same discovery (16 versus 18, the
   difference being the two command-derived skills), invocation observed on both
   routes, zero rewritten paths, zero duplicated bytes, nothing to re-sync when a skill
   is edited — against a copy in which 17 of the 18 skills point at directories that do
   not exist. The trade is that the symlink route brings no `source-command-*` skills,
   so the two commands that do cross under the importer do not cross under it.
3. **Skills need no trust step.** Unlike hooks, nothing must be written to the user's
   `$CODEX_HOME` for a skill to load. Whatever the hook layer's consent story becomes,
   the skill layer does not share it.

Which layer performs the bridge, and whether the two command-derived skills are worth
generating separately, are the ship list's decisions and not this section's.

### Two things this section does not guard, deliberately

**The counts here are not test-guarded, and that is a choice.**
`tests/test-derived-counts.sh` guards `README.md`, `docs/ARCHITECTURE.md` and
`docs/SKILL-CATALOG.md` against the tree moving underneath them; nothing in `tests/`
references this file. That is correct for a *dated measurement record* — the 16, the
18 and the 50 are what was true against `codex-cli 0.145.0` on 2026-08-16, and a guard
that silently updated them would destroy the record rather than protect it. The
opening paragraph tells the reader to derive the 16 instead of trusting it, which is
the right protection for a document like this. Recorded so the decision is visible
rather than accidental.

**The `noguide` rigs are isolated by accident, not by design.** They sit as siblings
of the guide-carrying rigs inside `evidence/`, and under `--sandbox read-only` the
parent directory is readable: `t5-unnamed-input-noguide`'s own `rg --files -g
'AGENTS.md' … ..` searched exactly that parent. It returned exit 1 with no output, so
**nothing leaked in this run** and the confound is closed as claimed — but a future
re-run whose search differs could read a sibling rig's `AGENTS.md` and quietly break
the isolation. A `noguide` rig sited outside `evidence/` would close it by
construction.

### Reproducing

`evidence/` is gitignored, so this recipe is the only route back to every number
above. It was run from a clean slate on 2026-08-16 — all four rigs rebuilt from
nothing — and it reproduced `repo=18 / 0 / 16` and every offline count in this
section. Run it from the repository root, and give it a `bash` that has not set
`errexit` on your behalf.

```bash
EV=docs/research/codex-client/evidence

# --- the disposable home: 700, outside /tmp, credential 600, one path to remove ---
PROBE_HOME="$(mktemp -d "$PWD/$EV/.home-repro.XXXXXX")"
chmod 700 "$PROBE_HOME"
cp "$HOME/.codex/auth.json" "$PROBE_HOME/auth.json"
chmod 600 "$PROBE_HOME/auth.json"
trap 'rm -rf "$PROBE_HOME"' EXIT

# --- 1. three rigs from one recipe: fixture Unity project + a real install --------
for rig in skillrig skillrig-nolink skillrig-symlink; do
  bash tests/fixtures/mkproject.sh "$EV/$rig" --variant urp
  ( cd "$EV/$rig" && git init -q . )
  bash install.sh --project-dir "$PWD/$EV/$rig" --yes
done

# --- 2. skillrig-symlink: one directory symlink, no copy -------------------------
mkdir -p "$EV/skillrig-symlink/.agents"
ln -s ../.claude/skills "$EV/skillrig-symlink/.agents/skills"

# --- 3. skillrig: detect chained into import, per codex-facts.md -----------------
#     `migrationItems` takes the detect response's items array VERBATIM.
{ printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"kinglet","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"initialized"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"externalAgentConfig/detect\",\"params\":{\"cwds\":[\"$PWD/$EV/skillrig\"],\"includeHome\":false}}"; sleep 10; } \
  | CODEX_HOME="$PROBE_HOME" codex app-server > "$EV/repro-detect.out"

ITEMS="$(PROBE_DETECT="$EV/repro-detect.out" python3 -c '
import json, os
for line in open(os.environ["PROBE_DETECT"]):
    line = line.strip()
    if not line:
        continue
    try:
        msg = json.loads(line)
    except ValueError:
        continue
    if msg.get("id") == 2:
        print(json.dumps(msg["result"]["items"]))')"

{ printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"kinglet","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"initialized"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"externalAgentConfig/import\",\"params\":{\"migrationItems\":$ITEMS,\"source\":\"kinglet\"}}"; sleep 25; } \
  | CODEX_HOME="$PROBE_HOME" codex app-server > "$EV/repro-import.out"

# --- 4. skillrig-noguide: the stripped copy the confound rows ran in --------------
rm -rf "$EV/skillrig-noguide"
cp -a "$EV/skillrig" "$EV/skillrig-noguide"
rm -rf "$EV/skillrig-noguide/AGENTS.md" "$EV/skillrig-noguide/CLAUDE.md" \
       "$EV/skillrig-noguide/.claude" "$EV/skillrig-noguide/.codex" \
       "$EV/skillrig-noguide/.mcp.json" "$EV/skillrig-noguide/MCP-SETUP.md"

# --- 5. discovery: `cwds` is an ARRAY, stdin held open past the reply -------------
{ printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"kinglet","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"initialized"}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"skills/list\",\"params\":{\"cwds\":[\"$PWD/$EV/skillrig\",\"$PWD/$EV/skillrig-nolink\",\"$PWD/$EV/skillrig-symlink\"],\"forceReload\":true}}"; sleep 10; } \
  | CODEX_HOME="$PROBE_HOME" codex app-server > "$EV/repro-skills.out"
#     count only scope=="repo" per entry, and check each echoed cwd:
#     skillrig repo=18   skillrig-nolink repo=0   skillrig-symlink repo=16

# --- 6. the prompts, one printf each (they live in gitignored evidence/) ---------
printf 'List every skill you have available, one per line, with no commentary.\n' \
  > "$EV/prompt-t5-selfreport.txt"
printf 'Use your save-system skill. Reply with the first concrete step it tells you to take, and nothing else.\n' \
  > "$EV/prompt-t5-named.txt"
printf 'I want to add a save system to this Unity project. What is the first thing you do?\n' \
  > "$EV/prompt-t5-unnamed-save.txt"
printf 'How should a script in this project read the left gamepad stick to move the player? Answer in three sentences.\n' \
  > "$EV/prompt-t5-unnamed-input.txt"
printf 'The save-system design is approved and written down. What do you do next? Answer in two sentences; write no files.\n' \
  > "$EV/prompt-t5-chain.txt"
printf 'How many lines are in ProjectSettings/ProjectVersion.txt? Reply with the number only.\n' \
  > "$EV/prompt-t5-control.txt"
printf 'In Unity, what does `Time.fixedDeltaTime` return? Answer in one sentence. Do not read any files.\n' \
  > "$EV/prompt-t5-control-api.txt"
printf 'Does this project list the Addressables package in `Packages/manifest.json`? Reply yes or no.\n' \
  > "$EV/prompt-t5-control-addressables.txt"

# --- 7. invocation: one prompt per probe, controls included ----------------------
bash scripts/codex-probe.sh --name t5-unnamed-save \
  --prompt "$EV/prompt-t5-unnamed-save.txt"        --workdir "$PWD/$EV/skillrig"
bash scripts/codex-probe.sh --name t5-control \
  --prompt "$EV/prompt-t5-control.txt"             --workdir "$PWD/$EV/skillrig"
bash scripts/codex-probe.sh --name t5-control-addressables \
  --prompt "$EV/prompt-t5-control-addressables.txt" --workdir "$PWD/$EV/skillrig"
bash scripts/codex-probe.sh --name t5-unnamed-input-noguide \
  --prompt "$EV/prompt-t5-unnamed-input.txt"       --workdir "$PWD/$EV/skillrig-noguide"
#     then the detector above over each NAME.jsonl — the `command` field, not the file
```

The four probes in step 7 are the load-bearing ones; the remaining prompts written in
step 6 drive the other rows of the table the same way, with `--workdir` set to the rig
named in that row. The config-key and extra-roots tables use the same `PROBE_HOME`
pattern — a seeded `config.toml` for the first, a `skills/extraRoots/set` call before
a second `skills/list` for the second. Raw
transcripts land under `docs/research/codex-client/evidence/`, which `.gitignore`
excludes — the verdicts are here, the credentials never are.
