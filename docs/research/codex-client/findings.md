# Kinglet's surfaces under Codex CLI — findings

*Measured against `codex-cli 0.145.0`. Codex's own capabilities are in
`codex-facts.md`; this file is about Kinglet's surfaces running on top of them.*

**Sections are added by the task that measures them.** Task 4 wrote `## Hooks`,
Task 5 `## Skills`, Task 6 `## Rules and AGENTS.md`, `## Commands` and
`## Agents`. Task 7 adds the MCP routes; Task 10 adds the A/B/C architecture
decision and the stranded-machinery debt. A section that is absent has not been
measured, and no section here speaks for another.

**`## Ship list` at the foot of this file is the exception, and it is not a
measurement.** Task 8 wrote it, it decides what Kinglet actually ships, and every
row of it cites the section above that decided the row. `tests/test-codex-surface.sh`
reads it: a Codex payload file the ship list does not name fails, and a ship-list
path that does not exist fails too.

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
   points.** The config `--emit-config` writes carries absolute paths to both the shim
   and the hook — **that is the generator's choice, not Codex's requirement**: a
   relative `command` resolves against the project root and fires (`codex-facts.md`
   §F5, measured 2026-08-16). What the absoluteness buys is independence from whatever
   directory a hook happens to be invoked from; what it costs is that the file cannot
   be shared between machines, which is why it is generated per project.
2. **`.codex/hooks.json` must be generated, not hand-written** — `--emit-config` is
   the ms→s conversion's only home, and a hand-written file reintroduces the
   fifty-minute timeout silently.
3. **Hook trust must be granted at install time**, by appending one
   `[hooks.state."<key>"]` table per entry to the user's `$CODEX_HOME/config.toml`.
   It cannot be precomputed (the trust key embeds the absolute path of `hooks.json`
   itself, whatever the command says) and it cannot ship in the repository (a project
   cannot vouch for itself). Ordering is fixed: write `hooks.json` → query
   `hooks/list` → write trust.

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

# 4. append one table per entry (key and currentHash exactly as step 3 reported them),
#    then run WITHOUT any bypass flag
CODEX_HOME="$PROBE_HOME" codex exec --json --skip-git-repo-check \
  --sandbox workspace-write --cd "$T" -o last.txt \
  'Create Assets/Scripts/ProbeInput.cs — a MonoBehaviour that reads the horizontal axis with Input.GetAxis("Horizontal") in Update and logs it.' \
  < /dev/null
```

**The prompt is the experiment, and each row of the table above needs its own.** The
one written out drives `block-legacy-input`; `block-scene-edit` needs an edit to an
existing `.unity` file, `warn-filename` a C# file whose class name does not match it,
and the allow control a file that violates nothing — that control is what makes an
absent file mean *blocked* rather than *the model chose not to write it*. Read the
`file_change` item count in the `.jsonl`, not the model's summary: **0** items is the
veto landing at the router, and a model that declines produces a sentence rather than
a zero. The exact bytes of each live probe's prompt live in the gitignored evidence
directory; what a reproduction needs is the shape.

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

**The enumeration has since been run to closure, and it is stated so the negative
carries its search.** `codex app-server generate-json-schema` was re-run offline
2026-08-16 under a disposable `CODEX_HOME`, and `ClientRequest.json` carries exactly
**three** `skills/*` request variants: `skills/list`, `skills/extraRoots/set`, and
`skills/config/write`. The third is new to this document and it is **not** a fourth
root route — `SkillsConfigWriteParams` is `{enabled, name?, path?}`, an enable/disable
toggle for a skill Codex has already found, which is what the `skill_approval`
configuration key is about. So it neither adds a root nor refutes the two refutations
above; it is recorded because a negative about a tool this size is a claim about a
search, and this is the search.

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

**The `none` cells are per-run facts, not invariants, and one of them has already
drifted.** A clean-slate re-run of `t5-control` loaded `using-kinglet` where the
committed transcript loads nothing. Across every control run now in existence —
five — **four loaded nothing**, and `t5-control-api` loaded nothing with **no shell
command at all** on two independent runs. So the column means *"this run loaded
nothing"*, not *"this prompt cannot load anything"*, and the load-bearing claim is
unaffected: what the controls establish is that loading is **task-driven rather than
unconditional**, and a control that occasionally loads the session-entry skill is
still not a control that loads the *topical* one. `t5-control-addressables` declining
`addressables` is the row that carries that, and it has not drifted.

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

---

## Rules and AGENTS.md

Kinglet ships 6 rules in `.claude/rules/`, pulled into Claude Code by `CLAUDE.md`.
Derive that set rather than trusting this sentence:

```bash
ls .claude/rules/*.md
```

| Question | Verdict | Evidence |
|---|---|---|
| A project `AGENTS.md` reaches the model | **yes — injected.** The sentinel came back with **0** shell commands run in the whole turn | `t6-agentsmd` |
| A project `CLAUDE.md` reaches the model | **not injected.** Same sentinel, same prompt: it came back only *after* the model ran `rg` for it | `t6-claudemd` |
| A file referenced the way Kinglet's `CLAUDE.md` references its rules is followed | **it depends on the request, and that dependence is the finding.** **1 of 12** under a request that gives the model no reason to look for project conventions; **6 of 6** under one that asks for them, against a control at **0 of 6** | `t6-pointer-field-*` vs `t6-pointer-conv-*`, `t6-nopointer-conv-*` |
| A file the entry document **orders** read is followed | **yes** — **12 of 12** opened, **12 of 12** obeyed, under the request shape that leaves the declarative pointer at 1 of 12 | `t6-imperative-field-r{1,2,3}`, ×4 samples |
| Kinglet's 6 rules can ship as pointers | **conditionally, and the condition is a rate rather than a switch.** A declarative pointer is a **map, not an order**: it makes the rules reachable and does not make them read. The request shape sets how often they are | the 2 × 3 table below |

**Verdict: `AGENTS.md` is the only project document whose *body* reaches the model
unasked, and a pointer inside it decides *where* the model looks while the request
mostly decides *how often*.** The word *body* is load-bearing and was missing here
for a round: `## Skills` above measures that every skill's **name and description**
are injected too, with no tool call — `t5-selfreport` lists them off 16 580 input
tokens having run nothing. So the categorical as first written was contradicted one
section up, by this same document. What is unique to `AGENTS.md` is that the whole
file arrives, not merely an index entry for it. (The round that wrote that sentence
was the round correcting two *other* categoricals, which is why the standing method
is now: after rewriting a categorical, sweep for the categorical the rewrite
introduced.) The entry document is injected whole. A file outside it was never
once opened without a pointer — 0 in 24 runs — and *with* a pointer it was opened
between one time in twelve and six times in six, depending on nothing but how the
request was phrased. Where the request does send the model looking, the pointer is
decisive: the control without one looks in the wrong place and reports the wrong
conventions with confidence.

**Two categoricals have been corrected here, both by re-running rather than
re-reading, and the shape of the error was the same twice.** The first version ran
one prompt shape — terse, one line, "no commentary" — measured the pointer at 0 of
6, and generalised to *"the declarative form Kinglet ships today measures dead"*,
building a ship item on it that would have inlined the whole rules layer into
`AGENTS.md`. A counter-experiment in review refuted that. Its replacement then said
*"the prompt supplies the motive and the pointer supplies the destination, and a
read needs both"* — a conjunction, which a fourth sample refuted with a single P1
run that read the rules unprompted. **What survives both corrections is a gradient,
and it is stated as one below.** Neither correction moved the direction of the
result or any ship item; both moved a claim from categorical to conditional.

Every probe below ran under a disposable `CODEX_HOME` (mode 700, outside `/tmp`, a
600 copy of `~/.codex/auth.json`, removed by an EXIT trap) with
`--ignore-user-config` and `--sandbox read-only`, against `codex-cli 0.145.0`. The
rigs are `mkproject.sh` fixture Unity projects with **`install.sh` deliberately not
run**: a rig with Kinglet installed would carry `.agents/skills/`, and Task 5
measured that a topical skill loads unnamed in 5 of 5 relevant probes. A skill
answering the question instead of a rule would confound every row here. Each rig
also sits in **its own parent directory**, so a probe's `..` search cannot reach a
sibling arm — `## Skills` above records sibling-visibility as an isolation it had
by accident, and this closes it by construction.

**Two things about the rigs that bound what these results are about.**

*The `pointer` rig carries a pointer Kinglet does not actually ship.* Its
`AGENTS.md` ends with a "Conventions reminder" heading followed by *"Follow the
rules files above; they bind."* The **real** generated document has the same
heading followed by an **inlined digest of actual rule content** — verify it rather
than trusting this sentence:

```bash
bash tests/fixtures/mkproject.sh /tmp/genfix --variant urp >/dev/null
bash scripts/generate-claude-md.sh /tmp/genfix | awk '/^## Conventions reminder/{p=1} p&&/^## Custom Notes/{exit} p'
# - `[SerializeField] private` for inspector fields; `_lowerCamelCase` privates; `== null` (never `?.`
#   / `is null`) on Unity objects; `[FormerlySerializedAs]` on every renamed serialized field; zero GC
#   allocations in `Update`/`FixedUpdate`/`LateUpdate`; cache `GetComponent` / `Camera.main`.
```

Stripping that is *correct* for isolating the mechanism — leave it in and the
`pointer` arm becomes the `inline` arm. But it means these rigs measure
**pointer-minus-digest**, while Kinglet ships **pointer-plus-digest**, and the
digest already carries the highest-value conventions by the mechanism that scores
best below. Every ship claim here is scoped to the rule content that lives *only*
behind the pointer, never to the rules layer as a whole.

*`nopointer` differs from `pointer` by a substitution, not a deletion.* Where
`pointer` has the rules bullet and the conventions reminder, `nopointer` has
*"## Where things go — **Game code:** `Assets/Scripts/`"*: topic-neutral and
length-matched, so it cannot plausibly manufacture the effect. It is **not** inert,
though, and the counter-experiment below is what showed it — under a
conventions-inviting request the control went straight to `Assets/Scripts/`. So the
contrast is not *pointer versus nothing* but **one destination hint versus
another**, which if anything is the harder test.

### The entry document is injected; `CLAUDE.md` is not

Two rigs, one prompt (*"What is the project sentinel? Reply with it and nothing
else."*), differing only in which file carries the sentinel:

| Rig | Sentinel lives in | Answer | Shell commands run |
|---|---|---|---|
| `t6-agentsmd` | `AGENTS.md` | `KINGLET-SENTINEL-4417` | **0** |
| `t6-claudemd` | `CLAUDE.md`, no `AGENTS.md` present | `KINGLET-SENTINEL-4417` | **1** — `rg -n -i "project sentinel\|sentinel" .` |

**Both answered correctly, and that is why the command count is the measurement
rather than the answer.** Zero commands means the text was in context before the
turn began — the same discriminator `## Skills` uses for its injected skill index.
One `rg` means the model went looking, which any file in the tree would satisfy.
`CLAUDE.md` is therefore *findable*, not *loaded*: a sufficiently determined model
recovers it, and nothing guarantees one will.

So Kinglet must write `AGENTS.md`. Leaving the project's `CLAUDE.md` to be
discovered is a bet on the model searching — and the sections below measure exactly
when it searches and when it does not, which is the one thing that bet depends on.
This row is the only unconditional result in the section.

### Whether a referenced file is followed depends on the request

The retrieval probe cannot decide this on its **answer**. Asked *for* a sentinel,
the model searches the tree and finds it whether or not anything pointed at it:
`t6-pointer-sentinel` and `t6-nopointer-sentinel` both returned
`KINGLET-SENTINEL-4417`, both after an `rg`. A question naming the thing you are
testing for manufactures its own positive.

**Their *commands* are a different matter, and the first version of this section
threw that away.** `t6-pointer-sentinel` grepped and then ran
`sed -n '1,80p' .claude/rules/architecture.md` — it went to the rules file.
`t6-nopointer-sentinel` ran three commands and touched `.claude/rules/` in none of
them. That asymmetry points the same way as everything below, and calling the pair
"decided nothing" was reading only the column that could not decide.

The binding probe asks something the model can answer from general knowledge, and
never mentions rules, files or conventions:

> Write the single C# field declaration for a private serialized float holding a
> move speed. Output only that one line of code, with no commentary and no code
> fence.

The rule under test is deliberately unnatural, so a generic answer and a
rule-following answer cannot be confused. In `.claude/rules/csharp-unity.md`:
*"Private serialized fields in this project are prefixed `kg_`, never `_`."*
Kinglet's real convention is `_lowerCamelCase`, which the model already knows and
would produce unaided — using the real rule would have scored a generic answer as
compliance.

**Prompt P1 — the terse one, and the only one the first version ran.** Four
`AGENTS.md` arms, three runs each. These values are the run on disk; the same four
arms were run three times more — once before it, and twice by independent
clean-slate reproductions of the `### Reproducing` block — for **four samples of
three runs each**. Thirty-five of the thirty-six agreed. The values below are the
on-disk sample; the cross-sample totals are in the 2 × 3 table.

**The one cell that moved is the one that matters most, and it moved against this
document.** In the fourth sample `t6-pointer-field-r3` — the terse prompt, the
`pointer` rig — read both rules files and answered `kg_moveSpeed`. So the
declarative pointer, with no motive-supplying prompt, sufficed **once in twelve**.
Everything the section says about direction survives that; one categorical did not,
and it is corrected below rather than smoothed over.

**Only the last sample is on disk, and that is a defect in the evidence trail
rather than in the result.** The samples reuse the `-r{1,2,3}` filenames, so each
overwrote its predecessor; what survives is one complete 4-arm × 3-run pass, and it
is not the sample that disagrees. Every cross-sample figure here therefore rests
partly on runs whose transcripts no longer exist, two of them other readers'. **Re-derive
with the recipe rather than accepting them** — that is not a formality, since
re-deriving is exactly what produced the correction above.

| Arm | What `AGENTS.md` says | r1 | r2 | r3 | Opened the rules file |
|---|---|---|---|---|---|
| `inline` | carries the rule **itself** | `kg_moveSpeed` | `kg_moveSpeed` | `kg_moveSpeed` | n/a — nothing to open |
| `imperative` | *"you MUST read `.claude/rules/csharp-unity.md` … do not answer a code question without reading it first"* | `kg_moveSpeed` | `kg_moveSpeed` | `kg_moveSpeed` | **3 of 3** |
| `pointer` | *"Rules live in `.claude/rules/` and are binding: `architecture.md` · `csharp-unity.md`"* — **Kinglet's own wording** | `_moveSpeed` | `_moveSpeed` | `_moveSpeed` | **0 of 3** (1 of 12 across samples) |
| `nopointer` | nothing about rules at all | `moveSpeed` | `moveSpeed` | `moveSpeed` | **0 of 3** |

**`inline` and `imperative` are positive controls that fail differently if the
experiment is broken.** `inline` proves the rule is one the model will follow when
it has it — without that, `pointer`'s failure could be a model declining a silly
convention. `imperative` proves the file is readable, at that path, in that
sandbox, and binds once read — without that, `pointer`'s failure could be a
permissions or path artefact. Both are **12 of 12**, so under P1 the `pointer` arm
is failing at the *decision to read* and nowhere else. The `imperative` command is
byte-identical in all twelve runs and reads **both** named files, not only the one
the mandate names:

```
/bin/bash -lc "sed -n '1,240p' .claude/rules/csharp-unity.md && sed -n '1,240p' .claude/rules/architecture.md"
```

**`pointer` and `nopointer` are near-identical on both measured variables and *not*
identical in their answers**, and the first version of this section called them
"indistinguishable", which the transcripts it cited contradict. In three of the four
samples — including the one on disk — `pointer` answered `_moveSpeed` and
`nopointer` answered `moveSpeed`, three for three each. The fourth sample's
`pointer` runs gave `_moveSpeed`, `moveSpeed` **and** `kg_moveSpeed`, so **this is a
tendency and not the perfect split an earlier draft of this paragraph claimed**;
`nopointer` has produced `moveSpeed` in all twelve. The tendency runs *toward*
Kinglet's real `_lowerCamelCase` convention, which is the point: the pointer text is
in context and doing something — naming `csharp-unity.md` and a "conventions
reminder" pulls the answer toward conventional C# without usually causing a read.
That is the first hint of the mechanism the next table measures.

### The same rig, the same rule file, a different request

Nothing changes below but the prompt. Same two rigs, byte-identical, same
`.claude/rules/csharp-unity.md`, same model, same sandbox:

- **P1** — *"Write the single C# field declaration for a private serialized float
  holding a move speed. Output only that one line of code, with no commentary and
  no code fence."*
- **P2** — P1 **plus four words**: *"…, following this project's conventions."*
- **P3** — *"Show me the code for a new MonoBehaviour called PlayerMover for this
  project. It needs a serialized move speed field and should move the transform
  each frame. Follow this project's conventions."*

Totals are across every sample that ran the cell — four for P1, two for P2 and P3:

| Prompt | `pointer` opened rules | `pointer` compliant | `nopointer` opened rules | `nopointer` compliant |
|---|---|---|---|---|
| **P1** — no reason to look | **1 of 12** | 1 of 12 | **0 of 12** | 0 of 12 |
| **P2** — four words appended | **4 of 6** | 4 of 6 | **0 of 6** | 0 of 6 |
| **P3** — asks for conventions | **6 of 6** | **6 of 6** | **0 of 6** | 0 of 6 |

**Read the two `nopointer` columns first.** Without the pointer, `.claude/rules/`
was opened **0 times in 24 runs** spanning all three prompts — including the six
under P3, where the model went looking for the project's conventions and found
something else. That column is the flattest result in this section and it is the one
carrying the ship recommendation.

**P3 is the decisive row and its control is what makes it decisive.** All three
`pointer` runs issued exactly one command and it went straight to the rules:

```
/bin/bash -lc "sed -n '1,240p' .claude/rules/architecture.md && sed -n '1,280p' .claude/rules/csharp-unity.md"
```

Under the **same** prompt the `nopointer` control never touched `.claude/rules/`. It
went to the code instead — `rg --files Assets/Scripts`, then
`sed … Assets/Scripts/GameLifetimeScope.cs && sed … Gameplay.asmdef` — answered
`moveSpeed` in all six runs across the two samples. In the on-disk sample **all
three** additionally asserted that they had followed the project's conventions —
verbatim, and note that each cites a *different* invented convention:

> This follows the project's current convention of sealed component classes without an explicit namespace.
> This follows the project's existing convention of sealed classes, Allman braces, and no explicit namespace.
> This matches the project's current global-namespace and sealed-class conventions.

**That "all three" is a per-sample figure and is not claimed for the other sample**,
where the explicit assertion appears less often; what holds across all six is 0
reads and 0 compliance.

So the failure mode without a pointer is not *no conventions applied*. It is **the
wrong conventions applied, from the wrong file, and — at least often — reported as
the project's own.** The pointer is the only difference between those two outcomes.

**P2 is the single-variable version and it carries a control the review's did not.**
Four appended words move the `pointer` rig from 1 of 12 to **4 of 6**; the same four
words leave the `nopointer` rig at **0 of 6**, and in that arm the model ran **no
command at all** in any of the six runs. So four words that ask for the project's
conventions cause no search when there is nothing pointing anywhere.

**The mechanism is a gradient, not a conjunction, and an earlier version of this
paragraph got that wrong.** It read *"the prompt supplies the motive and the pointer
supplies the destination, and a read needs both"* — a conjunction, refuted by a
single counter-example, which the fourth sample duly supplied: one P1 run read both
rules files with no motive-supplying prompt at all. What the four samples support is
weaker and better shaped:

- **The pointer looks necessary.** 0 reads in 24 runs without it, across all three
  prompts.
- **The pointer is not sufficient.** 1 of 12 with it under P1.
- **The request sets the rate, and it is a rate.** 1 of 12 → 4 of 6 → 6 of 6 as the
  request moves from conventions-blind to conventions-seeking. P2 sitting between
  the ends is the visible middle of that gradient, not a threshold being crossed.

So a declarative pointer **makes the rules reachable and does not make them read**,
and how often they are read is set by something Kinglet does not control — how the
user phrases the request. That is why *"the declarative pointer measures dead"* was
the wrong generalisation of a true measurement, and why *"a read needs both"* was
the wrong repair of it.

(The non-reading runs are recorded rather than rounded away: `pointer` P2 has one
per sample, answering `_moveSpeed`, the same non-compliant answer P1 produces. P2's
whole value is being a minimal perturbation, so its misses matter as much as its
hits.)

**What this is not.** Three runs per cell per sample against a stochastic model, one
model, one unnatural rule, three prompts. It establishes that P1's near-zero is
*prompt-conditional* and that the pointer is *decisive under P3*; it does not
establish where along the gradient a given real request falls, and three points do
not describe a curve. A rule the model
already agrees with will look obeyed whether or not it was read, which is why the
probe uses a convention Kinglet does not have. A future re-run must re-measure
rather than inherit this.

### Codex's `~/.codex/rules/` is a different thing, and it is not a spelling variant

The name collides; the meaning does not. Measured on this host:

```bash
ls ~/.codex/rules              # default.rules
head -1 ~/.codex/rules/default.rules
# prefix_rule(pattern=["env", "UV_CACHE_DIR=/tmp/uv-cache", "uv", "run", …], decision="allow")
```

That is command-approval policy — which shell invocations may run without a
prompt. Nothing in Kinglet's rule layer maps there, and a rules file copied into
it would be a syntax error in an approval store rather than guidance to a model.

The importer agrees by omission: there is no `RULES` item type, the enum being
`AGENTS_MD, CONFIG, SKILLS, PLUGINS, MCP_SERVER_CONFIG, SUBAGENTS, HOOKS,
COMMANDS, MEMORY, SESSIONS` (`codex-facts.md` §"Three losses", loss 2). No
`rules/` directory is created anywhere in the imported tree.

### Where the broken rules references live, source-side

`codex-facts.md` measures **29** `.Codex/rules/` references in the imported tree
and **22** surviving `.claude/` ones, reconciled source-side as `30 = 29 + 1` and
`22 = 1 + 21`. Those numbers are not re-counted here. What Task 8 needs and they
do not give is **which source files to repair**, so this is a decomposition of the
same quantity by the surface that carries it, counted over `.claude/` in this
repository:

| Source class | files carrying a `.claude/rules/` reference | references |
|---|---|---|
| `.claude/skills/` | 13 (12 `SKILL.md` + `subagent-driven-implementation/task-reviewer-prompt.md`) | 16 |
| `.claude/agents/` | 8 — **every one** | 9 |
| `.claude/commands/` | 9 — **every one** | 11 |
| `.claude/hooks/` | 0 | **0** |
| the entry document | 1 | **1** in this repository's own `CLAUDE.md`; **3** in the one `install.sh` generates into a project |

```bash
for d in .claude/agents .claude/skills .claude/commands .claude/hooks; do
  printf '%-20s %s\n' "$d" "$( { /usr/bin/grep -roh '\.claude/rules/' "$d" || true; } | wc -l )"
done
```

**This reconciles with the 29 rather than competing with it**, and the residue is
informative. Of the 16 skill references, 15 are rewritten and 1 — in
`task-reviewer-prompt.md` — survives as literal `.claude/`, which is
`codex-facts.md`'s single surviving Markdown reference. Of the 11 command
references, only the 4 in `unity-doctor` and `unity-init` cross at all; the other
7 leave with the 7 dropped commands. So:

```
15 (skills) + 9 (agents) + 4 (surviving commands) + 1 (repo CLAUDE.md)  =  29
```

and the imported `skillrig` tree — a real installed project rather than
`codex-facts.md`'s replica — carries **31** by the same count, `19 + 9 + 3`,
differing only in the entry document, because `install.sh` generates a project
`CLAUDE.md` with 3 rules references where this repository's own has 1. The 19 in
`.agents/skills/` that `## Skills` reports is itself `15 + 4`: the two
command-derived skills bring their commands' references with them.

**The hooks row is the one to notice.** Zero. The hook layer is the only surface
class that does not depend on the rules layer at all, which is consistent with
`## Hooks` above shipping on a shim and nothing else.

### What this means for the ship

1. **Kinglet must write `AGENTS.md`; it cannot leave `CLAUDE.md` to be found.**
   Measured, and this half is unconditional: `AGENTS.md` is injected
   (`t6-agentsmd`, **0** commands) and `CLAUDE.md` is not (`t6-claudemd`, recovered
   only by an `rg`). Nothing here depends on the prompt — the injection happens
   before the turn.
2. **Keep the declarative pointer. It is doing real work, and the work it does is
   not the work the first version of this section denied.** Measured: under a
   request that asks for the project's conventions, the pointer rig read the rules
   **6 of 6** while the identical rig without a pointer read `Assets/Scripts/` and
   answered wrongly **6 of 6**, often claiming the project's conventions while doing
   it. And without the pointer `.claude/rules/` was never opened at all — **0 of 24**
   across all three prompts. Removing it does not degrade to "no conventions"; it
   degrades to **confidently wrong conventions**, which is worse and harder to
   notice.
3. **Inline what must bind regardless of how the user phrases the request — and
   that is a shortlist, not the rules layer.** Measured: under a request that gives
   no reason to look, the pointer is followed **1 time in 12** while the same rule
   inlined binds **12 of 12**. So a rule that must hold even when the user
   asks a narrow, conventions-blind question has to be *in* `AGENTS.md`. **Kinglet
   already does this** — the generated document's `## Conventions reminder` inlines
   `_lowerCamelCase`, `== null`, `[FormerlySerializedAs]`, zero-alloc `Update` and
   the caching rule, which is the `inline` mechanism applied to exactly the
   highest-value conventions. The open question for Task 8 is therefore **narrow**:
   which spine non-negotiables are *not* in that digest and should be. It is not
   "inline the rules layer into `AGENTS.md`", which is what this list said before
   the counter-experiment and would have been a large generator change bought with
   a one-prompt result.
4. **An imperative pointer is available, and its cost is now legible.** Measured:
   `imperative` **12 of 12** read and **12 of 12** obeyed under the very prompt that
   leaves the declarative form at 1 of 12 — and it reads *every* file it names, not
   only its subject. It is the strongest of the three routes under P1 and the only
   one that survives a conventions-blind request without inlining. What it costs is
   a turn of latency on every task, whether or not the rules are relevant; and it is
   12 of 12, not a guarantee.
5. **Do not let the importer write `AGENTS.md`.** Measured: the imported file
   carries 3 `.Codex/rules/` references (`skillrig`) pointing at a directory that
   exists under no spelling, and the rules it points at never migrate
   (`codex-facts.md` §"Three losses", loss 2). A document that is injected whole is
   the worst file in the tree to let a blind substitution rewrite — and by item 2
   the pointer inside it is load-bearing, so corrupting it is not cosmetic.

Whether Kinglet generates `AGENTS.md` from the same generator as `CLAUDE.md`, which
non-negotiables join the inlined digest, and whether the pointer is upgraded to the
imperative form, are the ship list's decisions and not this section's.

### Reproducing

`evidence/` is gitignored, so this recipe is the only route back to every number
above. It has been extracted from this committed file and run from a clean slate
three times on 2026-08-16 — once here and twice by independent readers, all six rigs
rebuilt from nothing each time.

**Of the 28 cells it drives, 27 reproduced on every run and one did not**, and that
is the section's own best argument for running it rather than reading it: the cell
that moved is `pointer` under P1, which a fourth sample took from 0 of 9 to 1 of 12
and which refuted the mechanism this section had stated a round earlier. Everything
else — `t6-agentsmd`'s 0 commands, `t6-claudemd`'s single `rg`, the byte-identical
`imperative` `sed` pair, `nopointer` never opening `.claude/rules/` under any
prompt — has reproduced every time.

**Extract it by its marker line, not by fence-counting.** The recipe embeds literal
triple-backticks as `printf` payload in four places, so the obvious extractor —
*"find ` ```bash `, then the next ` ``` `"* — terminates ~78 lines early and yields a
fragment that dies in `bash -n` with *"unexpected EOF while looking for matching
quote"*. This file also has three `### Reproducing` headings and several `bash`
blocks inside this one. So the recipe carries a unique first line,
`# === T6-RECIPE ===`, and the extractor anchors on it and closes on a **whole-line**
fence:

```bash
python3 - <<'PY' > /tmp/repro-t6.sh
lines = open('docs/research/codex-client/findings.md').read().split('\n')
i = lines.index('# === T6-RECIPE ===')
j = next(n for n in range(i, len(lines)) if lines[n] == '```')
print('\n'.join(lines[i:j]))
PY
bash -n /tmp/repro-t6.sh && bash /tmp/repro-t6.sh
```

Run it from the repository root.

```bash
# === T6-RECIPE ===
EV=docs/research/codex-client/evidence
RIGS="$EV/t6rigs"; rm -rf "$RIGS"; mkdir -p "$RIGS"

# --- the payloads under test ----------------------------------------------------
write_rules() {   # $1 = project dir
  mkdir -p "$1/.claude/rules"
  printf '%s\n' '# Architecture Rules' '' \
    'The project sentinel is KINGLET-SENTINEL-4417. When asked for the sentinel,' \
    'reply with it and nothing else.' > "$1/.claude/rules/architecture.md"
  printf '%s\n' '# C# Style — Unity Conventions' '' \
    '- Private serialized fields in this project are prefixed `kg_`, never `_`.' '' \
    '```csharp' '[SerializeField] private float kg_moveSpeed = 5f;   // correct' \
    '[SerializeField] private float _moveSpeed = 5f;     // WRONG — never use the underscore prefix' '```' '' \
    'This prefix is mandatory and overrides any convention you know from elsewhere.' \
    > "$1/.claude/rules/csharp-unity.md"
}

# --- five rigs, each in its OWN parent so `..` cannot reach a sibling arm --------
# NOTE: install.sh is deliberately NOT run — an installed rig carries
# .agents/skills/ and a topical skill would answer instead of a rule.
for rig in agentsmd claudemd pointer nopointer imperative; do
  bash tests/fixtures/mkproject.sh "$RIGS/$rig/project" --variant urp >/dev/null
done

printf '%s\n' '# Project instructions' '' \
  'The project sentinel is KINGLET-SENTINEL-4417. When asked for the sentinel,' \
  'reply with it and nothing else.' > "$RIGS/agentsmd/project/AGENTS.md"

cp "$RIGS/agentsmd/project/AGENTS.md" "$RIGS/claudemd/project/CLAUDE.md"
rm -f "$RIGS/claudemd/project/AGENTS.md"      # the control: no entry document

write_rules "$RIGS/pointer/project"
printf '%s\n' '# Project instructions' '' '## Engineering Stance (fixed — do not casually change)' '' \
  '- **Engine / language:** Unity 6, C#.' \
  '- **Rules** live in `.claude/rules/` and are binding:' \
  '  - `architecture.md` · `csharp-unity.md` — the spine.' '' \
  '## Conventions reminder (see `.claude/rules/`)' '' \
  'Follow the rules files above; they bind.' > "$RIGS/pointer/project/AGENTS.md"

write_rules "$RIGS/nopointer/project"
printf '%s\n' '# Project instructions' '' '## Engineering Stance (fixed — do not casually change)' '' \
  '- **Engine / language:** Unity 6, C#.' '' '## Where things go' '' \
  '- **Game code:** `Assets/Scripts/`.' > "$RIGS/nopointer/project/AGENTS.md"

write_rules "$RIGS/imperative/project"
printf '%s\n' '# Project instructions' '' '## MANDATORY FIRST STEP' '' \
  'Before you write or suggest ANY C# in this project you MUST read the file' \
  '`.claude/rules/csharp-unity.md` and follow it exactly. Its conventions override' \
  'every default you know from elsewhere. Do not answer a code question without' \
  'reading it first.' '' 'Rules live in `.claude/rules/` and are binding:' \
  '`architecture.md` · `csharp-unity.md`.' > "$RIGS/imperative/project/AGENTS.md"

# the `inline` rig carries the rule itself and needs no .claude/ at all
bash tests/fixtures/mkproject.sh "$RIGS/inline/project" --variant urp >/dev/null
printf '%s\n' '# Project instructions' '' '## C# Style — Unity Conventions' '' \
  '- Private serialized fields in this project are prefixed `kg_`, never `_`.' '' \
  '```csharp' '[SerializeField] private float kg_moveSpeed = 5f;   // correct' \
  '[SerializeField] private float _moveSpeed = 5f;     // WRONG — never use the underscore prefix' '```' '' \
  'This prefix is mandatory and overrides any convention you know from elsewhere.' \
  > "$RIGS/inline/project/AGENTS.md"

# --- the prompts. P1/P2/P3 differ ONLY as noted; that is the whole experiment ----
printf 'What is the project sentinel? Reply with it and nothing else.\n' \
  > "$EV/prompt-t6-sentinel.txt"
# P1 — gives the model no reason to look for project conventions
printf 'Write the single C# field declaration for a private serialized float holding a move speed. Output only that one line of code, with no commentary and no code fence.\n' \
  > "$EV/prompt-t6-field.txt"
# P2 — P1 plus exactly four words. The minimal perturbation.
printf 'Write the single C# field declaration for a private serialized float holding a move speed. Output only that one line of code, with no commentary and no code fence, following this project'"'"'s conventions.\n' \
  > "$EV/prompt-t6-field-plus4.txt"
# P3 — a request that asks for the project's conventions outright
printf 'Show me the code for a new MonoBehaviour called PlayerMover for this project. It needs a serialized move speed field and should move the transform each frame. Follow this project'"'"'s conventions.\n' \
  > "$EV/prompt-t6-field-conv.txt"

# --- retrieval: is the entry document injected, or merely findable? --------------
for rig in agentsmd claudemd; do
  bash scripts/codex-probe.sh --name "t6-$rig" \
    --prompt "$PWD/$EV/prompt-t6-sentinel.txt" --workdir "$PWD/$RIGS/$rig/project"
done

# --- retrieval against the pointer arms: the probe that CANNOT decide anything ---
#     Both find the sentinel by searching, pointer or no pointer. Kept because a
#     reader who skips it will design exactly this probe and misread its positive.
for rig in pointer nopointer; do
  bash scripts/codex-probe.sh --name "t6-$rig-sentinel" \
    --prompt "$PWD/$EV/prompt-t6-sentinel.txt" --workdir "$PWD/$RIGS/$rig/project"
done

# --- binding under P1: four arms, three runs each --------------------------------
for run in 1 2 3; do
  for arm in inline imperative pointer nopointer; do
    bash scripts/codex-probe.sh --name "t6-$arm-field-r$run" \
      --prompt "$PWD/$EV/prompt-t6-field.txt" --workdir "$PWD/$RIGS/$arm/project"
    printf '%-11s r%s: %s\n' "$arm" "$run" "$(cat "$EV/t6-$arm-field-r$run.last.txt")"
  done
done

# --- the counter-experiment: SAME rigs, P2 and P3, each with its control ---------
#     This is the half the first version of this section did not run, and it is
#     what turns "the pointer measures dead" into "the pointer is a map".
for run in 1 2 3; do
  for arm in pointer nopointer; do
    for p in conv plus4; do
      bash scripts/codex-probe.sh --name "t6-$arm-$p-r$run" \
        --prompt "$PWD/$EV/prompt-t6-field-$p.txt" --workdir "$PWD/$RIGS/$arm/project"
    done
  done
done
# Compliance is `kg_` in the answer; the READ is the `.claude/rules/` path in the
# command census below. Both columns are needed — P2 r2 on `pointer` answered
# non-compliantly having read nothing, which is the row that keeps P2 at 2 of 3.
/usr/bin/grep -c 'kg_' "$EV"/t6-pointer-conv-r?.last.txt "$EV"/t6-nopointer-conv-r?.last.txt \
                      "$EV"/t6-pointer-plus4-r?.last.txt "$EV"/t6-nopointer-plus4-r?.last.txt
```

**Read the answer *and* the command census — the answer alone cannot tell an
injection from a search.** The census is the `command` field of every
`command_execution`, exactly as `## Skills` derives it:

```bash
python3 - "$EV"/t6-*.jsonl <<'PY'
import json, sys
for path in sys.argv[1:]:
    types, cmds = {}, []
    for line in open(path, encoding='utf-8', errors='replace'):
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except ValueError:
            continue
        item = event.get('item') or {}
        t = item.get('type')
        if t:
            types[t] = types.get(t, 0) + 1
        if t == 'command_execution' and event.get('type') == 'item.completed':
            cmds.append((item.get('command') or '').replace('\n', ' ')[:160])
    print('---', path.rsplit('/', 1)[-1], types)
    for c in cmds:
        print('    $', c)
    if not cmds:
        print('    (no shell command at all)')
PY
```

Expected: `t6-agentsmd` and every P1 `inline`/`pointer`/`nopointer` run report *no
shell command at all*; `t6-claudemd` reports one `rg`; every `imperative` run
reports the `sed -n '1,240p' .claude/rules/…` pair; every `t6-pointer-conv-*` run
reports a single `sed … .claude/rules/architecture.md && sed …
.claude/rules/csharp-unity.md`; and every `t6-nopointer-conv-*` run reports
`rg --files Assets/Scripts` followed by a read of `GameLifetimeScope.cs` —
the wrong file, confidently. Raw transcripts land under
`docs/research/codex-client/evidence/`, which `.gitignore` excludes — the verdicts
are here, the credentials never are.

---

## Commands

Kinglet ships 9 commands in `.claude/commands/`. Derive that rather than trusting
this sentence:

```bash
ls .claude/commands/*.md | wc -l
```

**Codex equivalent: none as a command; Codex's own answer is "a command is a
skill".** There is no slash-command surface in `codex-cli 0.145.0`, established
from four directions rather than one absence:

| Probe | Result |
|---|---|
| `codex --help` subcommand list | 24 subcommands, **none** a command or prompt registry: `exec`, `review`, `login`, `logout`, `mcp`, `plugin`, `mcp-server`, `app-server`, `remote-control`, `completion`, `update`, `doctor`, `sandbox`, `debug`, `apply`, `resume`, `archive`, `delete`, `unarchive`, `fork`, `cloud`, `exec-server`, `features`, `help` |
| `ls ~/.codex` | no `prompts/` directory, and none is created by any probe in this wave |
| app-server method list (`ClientRequest.json`) | the only command-shaped methods are `command/exec`, `command/exec/{resize,terminate,write}` and `thread/shellCommand` — shell execution, not a registry |
| the importer's own `COMMANDS` item | *"Migrate commands from `<repo>/.claude/commands` to `<repo>/.agents/skills`"* — Codex converts a command **into a skill** |

The last row is the one that matters: the question "does a command's content have
anywhere to go" is answered affirmatively by Codex itself, in the importer's own
description string.

**Verdict: commands do not cross as commands, 7 of the 9 do not cross at all, and
the 7 are lost silently.** `codex-facts.md` §"Three losses" measures the trigger as
syntactic — `$ARGUMENTS`, or `$` followed by a digit, anywhere in the body — so a
price (`$5`) or a positional reference in prose drops a command with the same
silence. The 7 never appear in `detect`, so `import` reports **31 successes and 0
failures** while they are absent — 31 over `codex-facts.md`'s replica, which has no
`.mcp.json`; the same import over a real installed project reports **32**, per the
reconciliation in `## Skills`. Either way the failure count is **0**. Those numbers
are quoted from `codex-facts.md`, not re-counted here.

The 2 survivors, `unity-doctor` and `unity-init`, become
`.agents/skills/source-command-<name>/SKILL.md` — which is why `## Skills` above
reports 18 at repo scope where `.claude/skills/` holds 16.

### What is actually lost is not routing

The natural reading of "a command routes to an agent, and agents are dead under
Codex, so the command is dead weight" is **wrong**, and it is worth stating because
it is the conclusion this section was expected to reach. Kinglet's command bodies
are **1023** lines (`cat .claude/commands/*.md | wc -l`, re-derived 2026-08-16 — it read
919 until Task 8 added 63 lines to `unity-doctor.md` inside this same wave, then 982, then
1010, then this, as Task 12 and its fix round kept editing that same file: a count written
mid-wave is stale by the next commit, which is why this one is guarded rather than trusted); the routing is a line or two of each.
`unity-fix.md` is 58 lines of
which the `## Agent Routing` section is one bullet — the substance is an ordered
Unity diagnostic (`NullReferenceException` → missing reference, destroyed object,
execution order; Missing Script → file/class name mismatch, asmdef issue;
serialization data loss → field renamed without `FormerlySerializedAs`; …) and a
`read_console` verification step. That is skill-shaped content, and it exists
nowhere else in the toolkit: none of the 9 command names has a same-named skill in
`.claude/skills/`.

```bash
# no command name is also a skill name
for c in .claude/commands/*.md; do
  n="$(basename "$c" .md)"; [ -d ".claude/skills/$n" ] && echo "$n has a skill"
done   # prints nothing
```

Each command body also already carries the degraded-mode paragraph it needs — *"If
the agent cannot be dispatched, do the work inline and say so… Run these steps
yourself"* — which is exactly the situation a Codex session is in permanently.

**Recommendation, with the measurement attached.** Convert the 9 commands to
skills at generation time rather than letting the importer drop 7 of them.
Measured: the trigger is a `$ARGUMENTS` or `$`-digit token in the body
(`codex-facts.md` §"Three losses", the 7-variant fixture table), Kinglet's 7
argument-taking commands all carry `$ARGUMENTS`, and the 2 that carry no `$` token
cross intact and work — `source-command-unity-init` was one of the skills observed
*loading unnamed* in `## Skills` above (`t5-unnamed-save`). So the conversion
target is proven to function; only the `$ARGUMENTS` token blocks the other 7, and
a generator that writes the skill body itself never emits one. **Note what that
costs:** a Codex "command" is a skill the model chooses to load, not a user-typed
`/unity-fix`, and `## Skills` measured only 6 distinct skills ever loading out of
16–18 discovered. A converted command is discoverable, not dispatchable.

---

## Agents

Kinglet ships 8 agents in `.claude/agents/` with `tools:` allowlists. Derive that
rather than trusting this sentence:

```bash
ls .claude/agents/*.md | wc -l
```

**Codex equivalent: `multi_agent` is a stable, enabled feature, and the agent
definition it reads carries no capability at all.**

```bash
codex features list | /usr/bin/grep -i agent
# external_agent_memory_import   under development  false
# multi_agent                    stable             true
# multi_agent_mode               removed            false
# multi_agent_v2                 stable             false
# use_agent_identity             under development  false
```

`multi_agent` is the one that is both stable and **enabled**; `multi_agent_v2` is
stable and off, and the other three are unavailable. So the feature exists — the
question is only what its definition format can carry.

Codex's own agents are skill-local. Each built-in skill carries
`~/.codex/skills/.system/<name>/agents/openai.yaml`, and the whole schema of one is:

```yaml
interface:
  display_name: "Review Agent"
  short_description: "Find actionable bugs in code changes"
  default_prompt: "Use $review-agent to review the requested code changes and return actionable findings."
policy:
  allow_implicit_invocation: false
```

Presentation and an invocation policy. **No tools key, and nowhere for one to go.**

### The tool grants were not dropped in transit — there is no destination

`codex-facts.md` §"Agent conversion drops every tool grant" measures the loss and
closes with *"whether a Codex subagent can be granted MCP tools at all is
unmeasured here"*. That is now measured, and the answer changes what the loss
means.

| Where a per-agent tool grant could live | What is there |
|---|---|
| the converted `.codex/agents/*.toml` | exactly 3 keys, ×8 files: `name`, `description`, `developer_instructions` |
| Codex's own `agents/openai.yaml` | `interface` (`display_name`, `short_description`, `default_prompt`) and `policy` (`allow_implicit_invocation`) — and this holds for **all six** built-ins, not only the one quoted above: `/usr/bin/grep -rl tools ~/.codex/skills/.system/*/agents/` returns nothing |
| the `Config` object's `tools` key | session-scoped only — `ToolsV2` carries one property, `web_search`; `AppToolConfig` is `{approval_mode, enabled}` |
| **the sandbox** | **a real, enforced restriction, and the one this wave measured.** `codex exec --sandbox` takes `read-only`, `workspace-write` or `danger-full-access` **once for the whole run**; every probe in this wave used `read-only`. Over the **app server** it is finer than that — see below — so "session-scoped" describes Kinglet's measured shape, not Codex's limit |

```bash
# the key census over the converted agents — KEYS, not substrings. A bare
# occurrence count is misleading here: `tools` appears 15 times across the 8
# files and `color` 3 times, all of it inside the instructions PROSE, while
# neither is a key anywhere. That is the shape of an over-reading this table
# would otherwise invite.
EV=docs/research/codex-client/evidence     # $EV/skillrig is built by `## Skills`'s recipe
/usr/bin/grep -oh '^[a-z_]* =' "$EV"/skillrig/.codex/agents/*.toml | sort | uniq -c
#   8 description =
#   8 developer_instructions =
#   8 name =
```

So `mcp__UnityMCP` appearing **0** times across the 8 converted files
(`codex-facts.md`, quoted not re-counted) is not an importer bug to be repaired by
writing the grants back in. **Codex 0.145.0 has no per-agent capability
allowlist.** MCP servers are configured for the session — the importer writes
`[mcp_servers.UnityMCP] url = "http://localhost:8080/mcp"` into
`<repo>/.codex/config.toml` — and whatever the session has, every agent has.

**For a Unity toolkit that inverts the usual concern.** Kinglet's `tools:` lines are
*narrowing*, and the narrowing is what has no expression. Derived over all 8 rather
than argued from an example:

```bash
for f in .claude/agents/*.md; do
  printf '%-22s %s\n' "$(basename "$f" .md)" "$(/usr/bin/grep -m1 '^tools:' "$f")"
done
```

| Agent | Narrowing that evaporates under Codex |
|---|---|
| `unity-reviewer` | **no `Write`, no `Edit`, no `Bash`, no MCP** — the only fully read-only agent |
| `unity-scene-builder` | no `Write`, no `Edit`, no `Bash` |
| `unity-optimizer` | no `Bash` |
| `unity-test-runner` | no `Bash` |
| `unity-ui-builder` | no `Bash` |
| `unity-fixer` | no `Agent` |
| `unity-coder`, `unity-prototyper` | none — full set |

**5 of 8 carry a substantive capability narrowing** (6 of 8 if the absent `Agent`
grant counts). Under Codex none of it survives, so a read-only agent is read-only
only because its prose says so.

**`unity-reviewer` is the row that matters most, and it is worse than a lost
attribute.** Its own description says it reports issues and *"does not fix them"*;
under Codex it would run with `Write`, `Edit`, `Bash` **and** MCP. A reviewer that
can repair what it reviews is not a degraded reviewer — it is a different thing, and
this repository's own `subagent-driven-implementation` loop depends on the review
gate being unable to quietly fix what it was meant to report.

That is a real loss of enforcement and it is the opposite of the "capability is
gone" reading: the capability is *ambient*, and the **restriction** is what
evaporated — under `codex exec`, which is the shape this wave measured.

### "No remedy measured" is not "no remedy exists", and this is the second time

An earlier version of the row above called the sandbox *"the only restriction Codex
has"* and said it *"cannot vary per agent within a session"*. Both are false, and
they were found the way the last one was — by reading one entry past where the
search had stopped. Three routes, none of them exercised by this wave:

| Route | What it is |
|---|---|
| `ThreadStartParams.sandbox` | a `SandboxMode` **per thread**, sitting in the same params object as `developerInstructions` — so "this agent body, narrowed to read-only" is one call |
| `TurnStartParams.sandboxPolicy` | a `SandboxPolicy`, documented *"Override the sandbox policy for this turn and subsequent turns"* |
| `permissionProfile/list` | called live under a disposable home: `{"data":[{"id":":read-only","allowed":true},{"id":":workspace","allowed":true},{"id":":danger-full-access","allowed":true}]}` |

```bash
# the two schema facts, offline
codex app-server generate-json-schema --out "$SCH"
python3 -c "import json;d=json.load(open('$SCH/ClientRequest.json'));\
print(d['definitions']['ThreadStartParams']['properties']['sandbox'],\
      d['definitions']['TurnStartParams']['properties']['sandboxPolicy'])"
```

**So "agent body plus a narrowed sandbox" is expressible today over the app server**,
and a per-agent *definition* allowlist is the thing that does not exist. What is
still unmeasured, and is the question Task 8 or a later wave has to answer before
concluding anything: **whether Codex's own `multi_agent` dispatch propagates a
per-thread sandbox to a sub-agent.** That is the difference between *a client could
enforce a read-only reviewer* and *Codex will*. Nothing here dispatched an agent.

**This is the second superlative in this wave that was really a statement about the
routes someone happened to try.** `## Skills` records the first: `skills/extraRoots/set`
was found one schema entry past `skills/list`, after three routes had already been
written up as complete. A negative about a tool this large is a claim about a search,
and the search should be stated with it.

Whether the MCP tools function at all is Task 7's measurement and is not claimed
here.

### The converted bodies instruct the model to use a tool that does not exist

All 8 converted agents tell the model to load skills with the `Skill` tool — 16
occurrences across the 8 files:

```bash
/usr/bin/grep -ohF '`Skill` tool' "$EV"/skillrig/.codex/agents/*.toml | wc -l   # 16
```

`## Skills` above measures that **Codex has no skill tool**: `ThreadItem`'s variant
list carries no skill item, and a skill is loaded by the model reading its
`SKILL.md` with the shell tool. So every converted agent opens with an instruction
whose named mechanism is absent. The same bodies carry 9 `.Codex/rules/` references
(the `.claude/agents/` row of the source table in `## Rules and AGENTS.md`) pointing
at a directory that exists under no spelling.

**Could Kinglet's 8 be expressed in Codex's shape:** the *prose* yes, the
*contract* no. `developer_instructions` will hold any body, and `interface` +
`policy` will present it. What has no expression is the `tools:` allowlist, which
is the half of an agent definition that makes "this agent cannot write files" true
rather than requested.

**Verdict: agents cross as text and not as capability, and the text as converted is
wrong in three independent ways** — a `Skill` tool that does not exist (16
references), a `.Codex/rules/` directory that does not exist (9 references), and a
`tools:` contract with no destination in the target model.

```bash
# the narrowing that has nowhere to go
/usr/bin/grep -H '^tools:' .claude/agents/unity-reviewer.md .claude/agents/unity-scene-builder.md
# unity-reviewer.md:tools: Skill, Read, Glob, Grep
# unity-scene-builder.md:tools: Skill, Read, Glob, Grep, mcp__UnityMCP__*
```

**Recommendation, with the measurement attached.** Do not ship the 8 agents as
`.codex/agents/*.toml`, and do not ship the importer's conversion of them.
Measured: the converted files carry 3 keys and no capability; Codex's own agent
shape has no tools key in any of the 6 built-ins; the only `tools` in the `Config`
schema is session-scoped `web_search`.

**The restriction cannot be preserved by any route measured in this wave, and
re-expressing an agent as a skill does not restore it.** A skill has no `tools`
contract either — by this section's own evidence there is no per-agent capability
surface anywhere in Codex 0.145.0, so the skill route drops the narrowing exactly
as completely as the TOML route does. Anyone reading item 2 below as the remedy for
the enforcement loss has read it wrong: it is the remedy for the *broken file*, and
the enforcement loss has no remedy *among the routes this wave measured*. What
Kinglet has to decide is what a reviewer that can write is worth, and a whole
session at `--sandbox read-only` is the only lever measured that changes the answer.

**Frame that as a decision, not as a dead end.** It is a decision for everything
measured here — and the section above names three unmeasured app-server routes by
which a client could start an agent's thread already narrowed. Task 8 should look
there before concluding the restriction is unrecoverable.

So, two separable decisions:

1. **Do not ship the TOML.** Airtight on the measurement above, and independent of
   anything else.
2. **If an agent's *content* is worth shipping** — `unity-fixer`'s and
   `unity-reviewer`'s bodies are the same skill-shaped material `## Commands`
   describes — a skill is the shape that exists. But state its reach honestly, the
   way `## Commands` does: `## Skills` measured **6 distinct skills ever loading out
   of 16–18 discovered**, so a converted agent is discoverable, not dispatchable,
   and this recommendation must not be read as "the model will find it".

Whatever ships, both body defects have to be fixed before it does, and they are
**not the same kind of defect**. The 9 `.Codex/rules/` references are the blind
substitution's damage and are repaired by not letting it run. The 16 `Skill` tool
references are not corruption at all — they are *correct* in `.claude/agents/`,
because Claude Code has that tool, and false only once the body is read by Codex.
That one cannot be fixed by protecting the file from the importer; it needs the
body written differently for the second client, or written so that it names no
client-specific mechanism. Whichever, it travels with `developer_instructions`
wherever that lands, so it is the ship list's problem and not the importer's.

---

## Ship list

*Written by Task 8 on 2026-08-16, before any payload file was created, from the
verdicts above. Not a measurement — a decision, with the measurement that decided
it attached to every row. `tests/test-codex-surface.sh` guards it in both
directions.*

### Which arrival path this describes

**There are two, they produce different trees, and every row below describes the
first:**

| Path | What it is | Who writes it |
|---|---|---|
| **the Kinglet path** | `install.sh` writes the Codex layout from this repository's payload | Kinglet |
| **the importer path** | the user runs `externalAgentConfig/detect` → `externalAgentConfig/import` | Codex |

The two are not variants of one layout. The importer drops 7 of 9 commands
silently, migrates no rules at all, rewrites 84 `.claude/` references to a
`.Codex/` that exists under no spelling, strips every agent's tool grants, and —
measured — copies `timeout: 3000` into `timeoutSec` **unconverted**, so a user who
arrives that way has hook timeouts of 33 to 83 minutes. It reports **32** successes
and 0 failures while doing all of it — 32 because this sentence's subject is a user
importing their own installed project; 31 is the same import over `codex-facts.md`'s
replica, which has no `.mcp.json`. It read 31 until 2026-08-17, which is the right
number attached to the wrong subject and the same correction already made in
`README.md`. The failure count is **0** for both, and that is the point.

**Kinglet does not write the importer's tree and does not repair it.** The ship
list therefore makes no claim about a project that arrived by import, and the
entry document says so in itself, so that a user who imported does not read
Kinglet's guarantees onto a tree Kinglet never touched.

### Ships

| # | Surface class | What ships, by path | The verdict that decided it |
|---|---|---|---|
| 1 | **Hooks** | `scripts/codex-hook-shim.sh`, now in `install.sh`'s payload → `.claude/scripts/codex-hook-shim.sh`; `.codex/hooks.json` **generated** by `--emit-config` at install time, **after `scripts/` is already in place** — see the ordering note below the table, which is a contract on the installer and not a preference; hook trust granted at install time | `## Hooks`: all nine tool-event hooks enforce through the shim; without it eight of the nine fire and do nothing. The config's top level must be a `hooks` wrapper — a bare event map is rejected with a parse warning. `timeout` is milliseconds in `.claude/settings.json` and **seconds** in Codex, so the generator converts by ceiling division and orders the two ceilings: shim `--timeout ceil(ms/1000)`, Codex `timeout ceil(ms/1000)+1` |
| 2 | **Skills** | `<project>/.agents/skills/` — a real directory holding one symlink per skill, `<name>` → `../../.claude/skills/<name>` | `## Skills`: `.claude/skills/` unaided gives **0**; the `skills` config key gives 0 under two spellings; a symlink root gives 16, enabled, with invocation observed. The root is per-entry rather than the single directory symlink because row 3 needs generated entries beside the symlinked ones — measured 2026-08-16 under this task, see **The mixed root** below |
| 3 | **Commands** | `scripts/codex-command-to-skill.sh`, in the payload → `.claude/scripts/codex-command-to-skill.sh`; it writes `<project>/.agents/skills/<command-name>/SKILL.md`, one per `.claude/commands/*.md` | `## Commands`: 7 of the 9 are dropped silently by the importer on an argument token, the loss is **content and not routing** (1023 lines of Unity diagnostics that exist nowhere else in the toolkit), no command name collides with a skill name, and a converted command was observed loading unnamed. Under the Kinglet path with row 2 alone, 9 of 9 would be lost — worse than the importer |
| 4 | **The entry document** | `scripts/generate-claude-md.sh --client codex` emits it; Task 9 writes it to `<project>/AGENTS.md`. This repository gets its own tracked `AGENTS.md` | `## Rules and AGENTS.md`: `AGENTS.md` is **injected** (sentinel returned with 0 shell commands); `CLAUDE.md` is *findable*, not loaded (same sentinel, recovered only after an `rg`). This half is unconditional — the injection happens before the turn |
| 5 | **Rules** | `.claude/rules/` ships as it already does; the Codex entry document keeps the **declarative pointer** and the existing digest **and adds the four `NON-NEGOTIABLE` sections that are in neither the digest nor a hook**, plus the editor-guard rule. The Claude Code document is byte-identical to base | `## Rules and AGENTS.md`: without the pointer `.claude/rules/` was opened **0 times in 24 runs**, and the failure mode is not "no conventions" but **confidently wrong** ones. The pointer is not sufficient (1 of 12 under a conventions-blind request) while the same rule inlined binds 12 of 12. The membership is derived, not asserted — see **What is and is not inlined** below, which corrects a false claim this row carried for one round |
| 6 | **MCP** | the `mcp_servers.UnityMCP` row for `<project>/.codex/config.toml`, written by Task 9. The entry document names the file and **marks the client-behaviour question open** | `codex-facts.md`: the importer writes exactly that row pointing at the bridge's `localhost:8080/mcp` URL, so the **configuration shape** is measured. **Whether the routes behave is not** — Task 7 has not run. See **Open, not answered** below |
| 7 | **The guard** | `tests/test-codex-surface.sh` | Task 8's own deliverable. Derives both sides from the tree, fails in both directions, carries an anti-vacuity floor |

### The ordering row 1 depends on, and which nothing in the suite can enforce

**Copy `scripts/` into the project before calling `--emit-config`.** The generator picks the shim
path it writes into all twelve command strings by preferring
`<project>/.claude/scripts/codex-hook-shim.sh` and falling back to the toolkit clone it was invoked
from. Emit before copying and every entry points into the clone — a directory the user is under no
obligation to keep, and per `## Hooks` a hook command Codex cannot run is a **silent allow**, not an
error. That is the whole defect shipping the shim closed, reintroduced by sequence alone.

**`tests/test-codex-surface.sh` does not catch this and cannot.** It installs and then emits, so it
exercises the generator's *preference logic*, not an installer's *sequence*; an installer that emits
first reds nothing in the suite. The constraint is recorded here, in the row Task 9's implementer
reads, because a guard the wave does not own is not where it belongs — Task 9 owns guarding its own
ordering.

### Excluded, each with its measurement

| Surface | Excluded | The measurement |
|---|---|---|
| **Agents, as `.codex/agents/` TOML** | wholly | `## Agents`: the converted files carry exactly 3 keys — `name`, `description`, `developer_instructions` — and no capability. Codex's own agent shape has no tools key in any of the 6 built-ins. The only `tools` in the `Config` schema is session-scoped `web_search`. **5 of 8** Kinglet agents carry a narrowing that has no destination, and `unity-reviewer` — deliberately read-only — would gain `Write`, `Edit`, `Bash` **and** MCP |
| **Agents, re-expressed as skills** | wholly, in this wave | `## Agents`: a skill has no tools contract either, so the skill route drops the narrowing exactly as completely. Re-expressing the *content* is possible and is not done here: the two agent bodies worth crossing (`unity-fixer`, `unity-reviewer`) are the same skill-shaped material row 3 carries for commands, and shipping them would double the surface without a measurement that anyone reaches them — `## Skills` observed **6 distinct skills ever loading out of 16–18 discovered** |
| **`.codex/hooks.json` as a tracked file** | wholly | `## Hooks`: it is **derived**, not merely placed — its twelve entries, their matchers, events and **converted** timeouts all come from `.claude/settings.json`, `--emit-config` is the ms-to-s conversion's only home, and the shim's own ceiling has to be ordered one second under Codex's per entry. A tracked copy is a second registration of the same twelve hooks with no guard tying it to the first, and it reintroduces the 33-to-83-minute timeouts the moment either drifts. It also carries the absolute shim path this generator emits — **though that is the generator's choice and not Codex's**: a relative `command` was measured registering and firing (`codex-facts.md` §F5, 2026-08-16), so this row rests on the derivation, not on an impossibility. Recorded in `provenance-skip.tsv` as `rule=absent` so it cannot drift back in |
| **`.codex/agents/` in this repository** | wholly | as above; `rule=absent` |
| **The importer's `AGENTS.md`** | wholly | `## Rules and AGENTS.md`: the imported file carries 3 `.Codex/rules/` references pointing at a directory that exists under no spelling, and the rules it points at never migrate. A document that is injected whole is the worst file in the tree to let a blind substitution rewrite |
| **`skills/extraRoots/set`** | as a ship route | `## Skills`: it works, and it lands at `scope:"user"` — every other project the session touches would get Kinglet's 16 skills — and it does not persist. After the call the home holds no file naming the root |
| **The `skills` configuration key** | — | `## Skills`: refuted under two spellings, each against a control in the same file that took effect |
| **The hook-trust bypass flag** | from everything Kinglet tells a user to run | `## Hooks`: it is a measurement instrument. Nothing in that section needed it, and every live hook result was measured under legitimate trust |
| **An imperative rules pointer in the project entry document** | not adopted | `## Rules and AGENTS.md` item 4: it is **12 of 12** read and obeyed under the very request that leaves the declarative form at 1 of 12, and it reads *every* file it names on every task whether or not the rules are relevant. That cost is paid per turn, the declarative form plus the digest already covers the conventions-blind case for the highest-value rules, and 12 of 12 is not a guarantee. **This repository's own `AGENTS.md` does use the imperative form** — one file, a maintainer reading it, and no per-turn cost in a user's project |

### The mixed root — measured under this task, 2026-08-16

Row 2 changes the skill root's shape from the one `## Skills` measured, so the new
shape was measured rather than assumed. Two rigs, one `skills/list` call, `cwds` as
an array, `forceReload: true`, a disposable `CODEX_HOME` (mode 700, outside `/tmp`,
credential 600, removed as one named path), `codex-cli 0.145.0`:

| Rig | `.agents/skills/` is | Repo-scope skills |
|---|---|---|
| `t8-dirlink` | one directory symlink to `../.claude/skills` (the shape `## Skills` measured) | **16**, all `enabled:true`, `errors: []` |
| `t8-mixedroot` | a **real directory**: 16 per-entry symlinks to `../../.claude/skills/<name>`, plus **one real generated directory** beside them | **17**, all `enabled:true`, `errors: []` |

Both rigs are `mkproject.sh` fixture Unity projects with `install.sh --yes` run
against them, so the only difference is the root's shape. Every symlinked entry's
reported `path` is the **real** `.claude/skills/<name>/SKILL.md` in both rigs — the
same "discovery device, not a load path" behaviour `## Skills` records for the
directory symlink, now confirmed per entry.

**What this does and does not license.** It licenses row 2's layout and row 3's
generated entries sitting in it. It does **not** re-measure invocation: `## Skills`
observed 2 of 16 loading through the directory symlink, and nothing here loaded
anything, because `skills/list` is an app-server call and no model ran. A generated
command-skill is **discoverable**; whether it is reached is the same open question
`## Commands` and `## Agents` both attach to their recommendations.

### What is and is not inlined, and the membership derived rather than asserted

**This section asserted something false for one round and it is worth saying how.**
It read: *"The spine non-negotiables that are not in the digest — no legacy
`Input.*`, no hand-edited `.meta` or scene files, no unguarded `UnityEditor`
reference in runtime code — are the ones a hook enforces."* The third member is
enforced by **nothing**. The only `UNITY_EDITOR` occurrence anywhere in
`.claude/hooks/` is at `block-legacy-input.sh:141`, where it is an **exemption** —
legacy input inside an `#if UNITY_EDITOR` block is excused — not a check. And the
list was not exhaustive. It was the one argument in this document with no
measurement under it, and it was wrong in both directions at once. Derive the
membership rather than trusting the table below:

```bash
/usr/bin/grep -rnE '^#+ .*(NON-NEGOTIABLE|CRITICAL)' .claude/rules/
/usr/bin/grep -rn 'UNITY_EDITOR' .claude/hooks/
```

The five spine rules carry **six** `NON-NEGOTIABLE`/`CRITICAL` sections:

| Section | In the digest? | Hook-enforced? |
|---|---|---|
| `serialization.md` — CRITICAL: `FormerlySerializedAs` | **yes** | yes — `warn-serialization` |
| `unity-specifics.md` — Input System | no | **the legacy-API half only** — `block-legacy-input` |
| `architecture.md` — Input System Architecture | no | **no** (the *pattern* — `InputView` owns `PlayerControls`, Systems input-agnostic — is not what the hook checks) |
| `architecture.md` — NO GameContext / Service Locator | no | **no** |
| `csharp-unity.md` — Encapsulation / minimum visibility | no | **no** |
| `performance.md` — Rendering & Draw Calls | no | **no** |

Plus one that is not headed `NON-NEGOTIABLE` and belongs in the same class:
`unity-specifics.md` § *Editor vs Runtime*, whose own stated failure mode is
*"compiles in Editor, **fails on build** with no warning"*. Neither inlined nor
enforced. That is the member the false sentence named.

**What the digest already carries** — `[SerializeField] private`, `_lowerCamelCase`,
`== null` (never `?.` / `is null`), `[FormerlySerializedAs]`, zero-allocation
`Update`/`FixedUpdate`/`LateUpdate`, and the `GetComponent` / `Camera.main` caching
rule. That is the `inline` mechanism, measured at 12 of 12, applied to the
conventions a conventions-blind request would otherwise miss.

**What row 5 now inlines, for the Codex client only.** The four sections in neither
column, plus the editor-guard rule, are inlined into the Codex entry document as a
`## Non-negotiables not covered by a gate` block. The brief's instruction was
*"inline what the digest lacks"*, scoped to what is not already there; this is that
set, derived rather than guessed.

**Why the Claude Code arm is left byte-identical to base.** Nothing in this wave
measured Claude Code's rule reachability — every pointer rate in `## Rules and
AGENTS.md` was measured under Codex. Changing the shipping client's document on the
strength of a measurement taken against the other one is the substitution this wave
exists to avoid. The asymmetry is therefore recorded as a gap, not as a finding: it
is unknown whether Claude Code needs the same block, and the way to find out is to
run the P1/P2/P3 experiment against it.

**The residual, restated correctly.** The earlier version said the residual was
*"if row 1 is not installed, those rules are neither inlined nor enforced"*. For the
four sections above the residual held **even when row 1 is installed**, because no
hook ever covered them — that is what the inlining now closes for Codex. What
remains, and is not closed by anything:

- **Under Claude Code** those four are pointer-only, as they have always been.
- **Under Codex without row 1**, the two hook-enforced members — legacy `Input.*`
  and hand-edited `.meta`/scene files — are neither inlined nor enforced. The entry
  document states that conditional where it states the enforcement.
- Inlining is prose. It was measured at 12 of 12 against one unnatural rule in one
  probe shape; it is not a gate, and no hook exists for these four.

### Open, not answered

- **MCP client behaviour under Codex is UNMEASURED.** Task 7 has not run. Nothing
  here establishes that the `manage_*` action names resolve, that Codex hits the
  same tool-versus-resource split, that the silent-failure shape (`isError` false
  beside a `success` false payload) appears, or that an inactive tool group is
  diagnosed. Row 6 ships the *configuration*, which is measured, and says the rest
  is unknown. Assuming parity with Claude Code is the move that produced four of
  this wave's **six** silent-failure layers — the six enumerated in one table below.
  This sentence read *five* until 2026-08-17, in the same document whose later
  heading is *"The six silent-failure layers, in one place"*: an ordinal or a total
  written mid-measurement is the same class of stale figure as any other count, and
  the class was already annotated in `codex-facts.md` while two of its three stale
  sites went unswept.
- **Whether `multi_agent` dispatch propagates a per-thread sandbox** to a sub-agent
  is unmeasured (`## Agents`). It is the difference between *a client could enforce
  a read-only reviewer* and *Codex will*. Nothing in this wave dispatched an agent,
  and the exclusion of agents does not depend on the answer.
- **Whether a directory symlink survives on Windows**, and whether Unity's asset
  pipeline objects to one outside `Assets/` (`## Skills`). Row 2 rests on symlinks;
  `.claude/UPSTREAM` claims one shipped host, `linux-x64`.
- **`session-brief`'s firing** (`## Hooks`) — registered, matcher untested against
  Codex's `sessionStart` source string.
- **Whether Codex ever runs a hook from a directory other than the project root.**
  Opened 2026-08-16 by the probe that closed the relative-command question: three
  hooks, one session, all three with `pwd` at the project root. Nothing rests on the
  answer today, because `--emit-config` emits absolute paths and is therefore immune
  to it — but it is the invariant a *tracked* config with relative commands would
  depend on, so it is recorded rather than left implied by a single session.

### The three imported-tree defects, and who owns each

`## Rules and AGENTS.md` and `## Agents` leave three repairs unassigned. They are
not one problem:

| Defect | Owner | Why |
|---|---|---|
| **The 29 `.Codex/rules/` references** and the 22 surviving `.claude/` ones | **the importer's** — Kinglet leaves them alone | They are produced by a blind substitution that runs **only on the importer path**. Kinglet's installer copies no surface body and rewrites nothing, so on the Kinglet path every `.claude/rules/` reference in a skill, command or agent resolves against a `.claude/rules/` that is right there. Repairing files Kinglet does not write is not available to it |
| **The dead pointer wording** in the imported entry document | **the importer's**, and answered by not using it | Row 4 generates the entry document instead. The exclusion above is the repair |
| **The 16 skill-tool references** | **split, and the split is the point** | All 16 are in `.claude/agents/`, where they are **correct** — Claude Code has that tool — and where they are false only once a Codex reader loads the body. Since agents do not ship to Codex at all, Kinglet repairs none of them. What Kinglet *does* own is the one reference of the same kind that **does** cross: the generated entry document's own instruction to load a skill with that tool, which under `--client codex` becomes the measured mechanism — the model reads the `SKILL.md`, because `ThreadItem` carries no skill item and Codex has no skill tool. `.claude/skills/` and `.claude/commands/` carry **0** references of this shape; derive it rather than trusting the sentence |

### Success criterion 1

`## Hooks` measured that the hooks port with a named translation, so the "if hooks
did not port" branch of the plan does not apply: Kinglet on Codex is **enforcing,
not advisory** — provided row 1 and its trust step are installed. The entry
document states that conditional in those terms rather than claiming enforcement
unconditionally, because a user who bridged only the skills has an advisory install
and no way to tell from the inside.

**Scoped 2026-08-16, and this correction is here because `install.sh` names this
section by heading as the thing it scopes.** "No way to tell from the inside" is
true of the case this sentence is about — with only the skills bridged there is no
`.codex/hooks.json`, so `hooks/list` returns no Kinglet entries and there is no
`trustStatus` to read — and it is **not** true as a general claim about hook trust,
which is how it came to be quoted. Two things now say where the line falls, and both
came out of this measurement rather than around it. `trustStatus` is a required field
of every entry `hooks/list` returns, so a *registered*-but-untrusted hook reports
itself and a config edited since it was trusted reports `"modified"`; what stays
invisible is an untrusted **project** (empty list, no entry) and a hook Codex **times
out** (`trusted`, and the allow is silent). And the toolkit now ships a route for the
case in this sentence: `studio-doctor.sh` reports a missing `.codex/hooks.json` by
path. `README.md` § *Hook trust* carries the full boundary; do not re-quote this
sentence without it.

---

## Architecture decision

*Written by Task 10 on 2026-08-16, after Tasks 1–6 and 8–9 shipped. Not a
measurement — a decision, read off what the measurements let ship. Task 7 has not
run; where that limits the decision it is said so in place rather than at the end.*

The spec put three shapes on the table and **expected A**:

- **A — the Superpowers shape.** One shared content tree, a thin per-client
  manifest, `AGENTS.md` as an entry document (a symlink, in the upstream it is drawn
  from), a per-client hook manifest. Its evidence was that it ships to seven clients
  today.
- **B — the 2026-07-23 platform design.** Fill `src/catalog/`, write renderers in
  `tools/kinglet_build/`, generate a product per client.
- **C — installer-only.** Leave the repository shape alone; `install.sh` translates.

### The decision: none of the three, and here is what it actually is

**What shipped is a single shared content tree plus a runtime adapter, with every
client-specific artefact generated on the target machine at install time and none of
it tracked.** Read off the branch rather than off the ship list:

| What shipped | Where |
|---|---|
| the payload, unforked | `.claude/` — `.claude/hooks/` and `.claude/settings.json` are **byte-unchanged since the base commit** |
| the runtime adapter | `scripts/codex-hook-shim.sh`, installed into the project as `.claude/scripts/codex-hook-shim.sh` and executed on **every hook invocation** |
| a generator for the one class with no Codex surface | `scripts/codex-command-to-skill.sh` |
| a second arm on the existing entry-document generator | `scripts/generate-claude-md.sh --client codex` |
| sequencing, consent, receipt, and the home write | `install.sh --client codex [--codex-trust]`, `uninstall.sh` |
| the repository's own entry document | `AGENTS.md`, tracked, 42 lines |
| nothing at all | `src/catalog/`, `tools/kinglet_build/`, `adapters/` — **0 lines changed across the whole branch** |

Against A: **two of A's four members are not merely unused, they are measured
unshippable.** Kinglet ships no per-client manifest, and the reason is trust rather
than paths — a distinction this paragraph got wrong for a round, and one worth
separating because only one half is measured shut:

- **Trust cannot ship in a repository. Measured, and it is the airtight half.** The
  trust key is `<abs>/.codex/hooks.json:<event>:<group>:<index>`, so it embeds the
  absolute path of the config file and cannot be precomputed. A project cannot vouch
  for itself either: `trusted_hash` written inside the matcher group is not rejected,
  it is **silently ignored** — same `currentHash`, `warnings: []`, still untrusted
  (`codex-facts.md` §F5). So an install-time step on the target machine exists no
  matter what else is tracked, and A's manifest would not remove it.
- **A tracked config file is not impossible on path grounds, and the earlier version
  of this paragraph said it was.** That claim rested on *"the command strings carry
  absolute paths"*, which describes what `--emit-config` chooses to build
  (`$root + "/" + $rel`) rather than anything Codex requires. Measured 2026-08-16,
  three `PreToolUse` entries differing only in path form: `'./hookrel.sh'` and
  `'.codex/hooks/hookdir.sh'` both **registered and fired**, alongside the absolute
  control, under legitimate trust with no bypass flag — all three running with `pwd`
  at the project root, which each logged itself. The negative is withdrawn and
  replaced by the measurement; what stays open is a hook invoked from any *other*
  directory, which this probe did not produce and a relative command depends on.

**What actually keeps the config generated is derivation, not impossibility**, and
saying so is the honest form: the twelve entries, their matchers, their events and
their **converted** timeouts all come from `.claude/settings.json`, `--emit-config` is
the only home of the millisecond-to-second conversion, and the two ceilings have to be
ordered per entry (shim `ceil(ms/1000)`, Codex `+1`). A tracked copy would be a second
registration of the same twelve hooks, needing its own identity guard against the
first — a real design argument, and a weaker one than "cannot", which is why it is
written as what it is. `.codex/hooks.json`, `.codex/agents` and `.agents` stay
`rule=absent` in `provenance-skip.tsv` on that ground. And `AGENTS.md` is not a symlink to `CLAUDE.md`: it is
a *different document*, because `## Rules and AGENTS.md` measured that a declarative
pointer is read 1 time in 12 under a conventions-blind request while an imperative one
is read 12 of 12 — so the Codex arm carries an imperative instruction and an inlined
block that the Claude Code arm does not.

Against C: the translation is **not** inside `install.sh`, which was the spec's own
stated objection to C. It is in two standalone scripts with their own test surfaces
(`tests/test-codex-shim.sh`, `tests/test-codex-surface.sh`), and the installer calls
them. What `install.sh` owns is sequence, consent, the receipt, and the write to the
user's home — none of which is translation. The repository shape did change, by three
scripts and one root document.

**And the member none of the three names is the one that decided the wave: a runtime
adapter.** A, B and C are all *layout* answers — where do files live, what renders
them, who copies them. The defect that had to be solved is not a layout defect.

### The measurement that chose it

**Codex's file tool is `apply_patch`, and its `tool_input` carries exactly one key:
`command`, a patch envelope.** No `file_path`, no `content`, no `new_string`, no
`old_string`. Measured by dumping a hook's stdin, and every row of `## Hooks`'s
per-hook table carries the control that makes it mean something: `block-scene-edit`
given a Claude-shaped payload exits 2 with 443 bytes and blocks; given the real Codex
payload for the same edit to the same file it exits 0 with 0 bytes. Eight of the nine
tool-event hooks are inert that way; `bash-gate` survives only because `command` is
the one field Codex does supply. (Byte counts of a refusal are `constant +
len(command)`, so two readers measuring the same hook on different inputs get
different numbers and neither is a property of the hook — quote the row, not a figure
lifted from another rig.)

**No arrangement of files fixes that.** A shared tree does not, a per-client manifest
does not, a renderer does not, and an installer that copies bytes does not — every one
of them would have shipped twelve registered hooks, matching matchers, `warnings: []`,
`errors: []`, and not one file-level rule enforced. The mismatch is in the payload
vocabulary at the moment the hook runs, so the fix has to be at that moment too. That
is what `scripts/codex-hook-shim.sh` is, and it is why the shape that shipped is not
one of the three: **the wave's load-bearing artefact is a process that runs in the
user's project on every tool call, not a file that is placed there.**

Three further measurements each closed off a specific member of A or B, and they are
named separately because any one of them alone would leave the decision arguable:

1. **Hook trust forces generation over tracking.** The hash cannot be precomputed and
   the project cannot vouch for itself, so the ordering is fixed — write
   `hooks.json` → query `hooks/list` → write the user's `$CODEX_HOME/config.toml`.
   That is an install-time sequence, and a tracked manifest has no place in it.
2. **The single shared tree survives, but needs a root the repository cannot hold.**
   `.claude/skills/` unaided gives **0** repo-scope skills; the `skills` configuration
   key gives 0 under two spellings, each against a control in the same file that
   demonstrably took effect. What works is a per-project `.agents/skills/` root of
   symlinks — a thing the installer makes, not a thing the repository ships. So A's
   best idea (one tree, no second copy) is kept, and A's mechanism for exposing it is
   not available.
3. **B builds renderers for the layer that measured least load-bearing.** What crossed
   in this wave is executable — a shim, a converter, a generator arm. What did not
   cross is declarative: the `tools:` allowlist has no destination in Codex's agent
   shape, and commands have no surface at all. `python3 -m tools.kinglet_build
   validate` still reports `Validated 0 canonical units, 0 routes, 2 adapters` against
   `src/catalog/routing.json` = `{"routes": []}`; re-derived 2026-08-16. Filling that
   machine would have produced generated prose for exactly the classes that measured
   dead, and none of the runtime translation that measured decisive.

### What this decision does not rest on

**Task 7 has not run**, so nothing here is informed by how Codex's MCP client behaves
against a live Unity bridge. That does not change the decision — the shim, the skill
root and the entry document are all measured without Unity — but it does bound it: if
Codex's MCP client turns out to need per-route translation, that translation has no
home yet, and the shape above says where it would go (a runtime adapter, not a
renderer) without saying that it is needed.

---

## Excluded, by surface class

Task 8's ship list carries a row-level exclusion table with the measurement behind
each. This section is the **class-level** view, because a class dropped without an
entry is indistinguishable from a class forgotten, and two of these are whole classes
rather than rows.

| Class | Status on Codex | The measurement | Revivable by work, or structurally absent? |
|---|---|---|---|
| **Hooks** | **ships, with a named translation** | 9 of 9 tool-event hooks enforce through the shim; without it 8 of the 9 fire and do nothing | — |
| **Skills** | **ships, no translation at all** | 16 discovered through a symlink root, invocation observed unnamed in 5 of 5 relevant probes | — |
| **Rules** | **ships as pointer + digest + an inlined non-negotiables block** | without the pointer `.claude/rules/` was opened **0 times in 24 runs**; the failure mode is confidently wrong conventions, not absent ones | — |
| **Commands, as a command surface** | **structurally absent** | `codex-cli 0.145.0` has 24 subcommands and none is a prompt registry; no `~/.codex/prompts/`; the only command-shaped app-server methods are shell execution; and Codex's own importer describes migrating commands **into skills** | **Structurally absent.** No work on Kinglet's side creates a `/unity-fix`. The *content* crosses — `scripts/codex-command-to-skill.sh` writes all 9 as skills — and what is lost is dispatch, not substance |
| **Agents, as `.codex/agents/*.toml`** | **excluded wholly** | converted files carry exactly 3 keys (`name`, `description`, `developer_instructions`); none of Codex's 6 built-in agent definitions has a tools key; the only `tools` in the `Config` schema is session-scoped `web_search` (23 keys, re-derived 2026-08-16) | **Structurally absent** for the contract. The prose would carry; the capability contract has nowhere to go |
| **The `tools:` capability narrowing** | **excluded, and this is the loss that matters** | **5 of 8** agents carry a substantive narrowing; `unity-reviewer` is deliberately read-only and under Codex would run with `Write`, `Edit`, `Bash` **and** MCP | **Partly revivable, and unmeasured.** `ThreadStartParams.sandbox`, `TurnStartParams.sandboxPolicy` and `permissionProfile/list` all exist, so *a client* could start a narrowed thread. Whether `multi_agent` dispatch propagates it is unmeasured, and `codex exec` — the shape this wave measured — takes one `--sandbox` for the whole run |
| **Agents re-expressed as skills** | **excluded in this wave** | a skill has no tools contract either, so the skill route drops the narrowing exactly as completely; and `## Skills` observed **6 distinct skills ever loading** out of 16–18 discovered | Revivable — it is a content decision, not a mechanism one. Deferred because it doubles the surface with no measurement that anyone reaches it |
| **MCP client behaviour** | **not excluded — unmeasured** | the configuration row is measured (the importer writes exactly it); nothing establishes that the routes behave | **Unmeasured, and it is Task 7's.** Recorded here so it is not read as an exclusion |
| **The importer path** | **not repaired, deliberately** | the importer drops 7 of 9 commands silently, migrates no rules, rewrites 84 `.claude/` references to a `.Codex/` that exists under no spelling, strips every tool grant, copies `timeout: 3000` into `timeoutSec` unconverted — and reports **32** successes, 0 failures over a real installed project (31 over the `.mcp.json`-less replica) | Not Kinglet's to repair: it rewrites files Kinglet never writes. Kinglet's answer is to write its own layout instead |

**Two classes are dead as classes, and the difference between them is worth keeping.**
Commands are dead because Codex has no such surface — a structural absence, and the
content survives the crossing by changing shape. Agents are dead because Codex has no
*contract* for the half of an agent definition that makes "this agent cannot write
files" true rather than requested — the prose would cross perfectly and the guarantee
would not, which is the worse of the two failures and the reason the whole class is
excluded rather than half-shipped.

---

## The debt this decision strands

The 2026-07-23 platform program built a machine and never put content through it. The
decision above does not use it, does not extend it, and **this wave deliberately does
not retire it.** Naming it is the whole obligation here, because the failure shape
this repository has hunted across four waves is a thing that stops being true while no
document changes.

Counts re-derived 2026-08-16, not copied from the plan:

```bash
ls src/catalog | wc -l                       # 3
find tools/kinglet_build -name '*.py' | wc -l # 10
ls adapters/*/profile.json | wc -l            # 2
```

| Stranded | Size | The measurement that stranded it |
|---|---|---|
| `src/catalog/` | **3** files — `capabilities.json`, `routing.json`, `support-policy.json` | `routing.json` is `{"schema_version": 1, "routes": []}`. The Codex client shipped without one route ever being written |
| `tools/kinglet_build/` | **10** Python modules, one of which is the renderers package's `__init__.py` | `python3 -m tools.kinglet_build validate` reports `Validated 0 canonical units, 0 routes, 2 adapters`. It has a working CLI, 135 passing tests under `tests/kinglet/`, and no content |
| `adapters/claude/profile.json`, `adapters/codex/profile.json` | **2** files | **This is the sharpest one, because the profile is not merely unused — it is contradicted.** `adapters/codex/profile.json` declares `output_roots` of `plugins/kinglet-unity` and `packages/codex-project`; the layout that measured correct is `AGENTS.md`, `.agents/skills/`, `.codex/hooks.json` and `.codex/config.toml`, and neither declared root appears anywhere in Codex. It also maps a `delegate` capability to `agent-delegation` **per adapter**, while `## Agents` measures that Codex 0.145.0 has no per-agent capability surface at all |

**`migration/baseline-inventory.json` is NOT stranded, and the spec said it was.**
That is corrected here rather than repeated: it is live and maintained. This wave
updated it — `source_commit` moved to `b3ecfb2` and `.claude/commands/unity-doctor.md`'s
recorded sha256 changed with Task 8's edit — and `tests/kinglet/test_baseline_inventory.py`
verifies it inside the suite through `tests/test-kinglet-build.sh`. It tracks the
`.claude/` payload, not the unbuilt platform, which is why it behaved differently from
its three neighbours in the spec's list.

**Why it is not retired now.** Retiring it means deleting 15 tracked files and most of
the 135 tests that `tests/test-kinglet-build.sh` runs — not all of them, since the
baseline-inventory tests below belong to the live half — and this wave's own evidence
is one client wide: the decision above was chosen
by measurements taken against `codex-cli 0.145.0` on one Linux host, with Task 7 unrun
and no Windows or macOS pass. B's premise — that clients diverge enough to need
generated products — was not *refuted*; it was **not needed for this client**, which
is a weaker result and does not license a deletion. What is now recorded, and was not
before, is that the second client came and went without touching it. A third client is
the evidence that decides whether it is dead or merely early, and `provenance-skip.tsv`
already holds the shape a retirement would take.

---

## The six silent-failure layers, in one place

Each layer reports success in its own terms while the layer under it does nothing.
They are collected here because they were measured one per task and no single section
holds them all — and because the last one is the likeliest a real user meets.

| # | Layer | What it reports | What actually happens | Where |
|---|---|---|---|---|
| 1 | Codex's own importer | **32 successes, 0 failures** over a real installed project; **31** over the replica with no `.mcp.json` | 7 of 9 commands dropped, rules never migrate, 84 path references rewritten to a directory that does not exist, every tool grant stripped, `timeout` copied ms-into-seconds | `codex-facts.md` §F1 |
| 2 | Hook registration | `registered 12, warnings: [], errors: []`, `enabled: true` | nothing yet — but every signal a reader would check is now green | `codex-facts.md` §F1 |
| 3 | Per-hook trust | `enabled: true`, `trustStatus: untrusted`, `statusMessage: null` | the hook fires **0** times. No prompt, no warning, nothing logged | `codex-facts.md` §F5 |
| 4 | The hook body | the matcher fires, the process runs | 8 of 9 read fields `apply_patch` does not have, and exit 0 with 0 bytes | `codex-facts.md`, `## Hooks` |
| 5 | The hook's own ceiling | Codex's `timeoutSec` expires | a `PreToolUse` hook Codex times out is a **silent allow** — the edit lands, the model is told nothing, and Codex's stderr carries **0** `hook:` lines | `## Hooks`, "the two ceilings are ORDERED" |
| 6 | **Project trust** | `hooks: [], warnings: [], errors: []` | against a project Codex has not been told to trust, the hooks are **not reported as untrusted — they are not registered at all**, and nothing says so | Task 9, `install.sh` |

**Layer 6 is the one to state to users.** The other five are reached by installing
something; layer 6 is reached by installing *correctly* and then opening the project.
A reader who checks the one diagnostic that exists — `hooks/list` — is handed three
empty arrays and no error, which is indistinguishable from a project with no hooks in
it. `install.sh` names this case with the commands that fix it, and `README.md` says
it in plain words, because a user who installs expecting guardrails and gets none has
been misled by an omission.

Layers 4 and 5 are closed by the shim, layer 3 by `--codex-trust`, and layer 6 by
granting project trust once. Layer 1 is closed only by not using the importer. Layer 2
was never a defect — it is in the list because it is the signal a reader would trust.
