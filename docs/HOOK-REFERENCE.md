# Hook Reference

Complete catalog of hooks in Kinglet Pioneer.

---

## Overview

Kinglet Pioneer includes 12 hooks that provide safety enforcement, quality warnings and session management. Hooks are bash scripts in `.claude/hooks/` configured in `.claude/settings.json`. 11 of the 12 hooks source a shared library (`_lib.sh`) that provides kill switches, profile filtering, state paths, and utility functions. **`session-brief.sh` sources nothing** — it runs at `SessionStart`, where a library failure is a session that does not start — and carries `DISABLE_UNITY_HOOKS` and `DISABLE_HOOK_SESSION_BRIEF` inline instead. Until 2026-08-14 it carried neither, and was the one hook the kill switch did not reach.

`_lib.sh` is that shared library and not itself a hook, which is why the count is one less than the number of `.sh` files in the directory. Derive it rather than trusting this sentence:

```bash
ls .claude/hooks/*.sh | grep -v '_lib\.sh' | wc -l
```

That number, the blocking count, the three profile tiers and the installed-script count are now
**derived and guarded**: `tests/test-derived-counts.sh` counts them in the tree and fails when this
file, `docs/ARCHITECTURE.md` or `docs/GETTING-STARTED.md` disagrees. It also asserts the set identity
between `.claude/hooks/*.sh` and the registrations in `settings.json`, in both directions — an
unregistered hook and a registration with no file both produce silence rather than an error.

**Fifteen hooks were removed on 2026-08-13**, when the surface criterion the 2026-08-03 cut applied
to agents, commands and skills — *does it do something the model cannot do unaided?* — was applied to
this directory for the first time. Seven had never run (they declared `strict` while nothing sets
`UNITY_HOOK_PROFILE`), four were structurally broken, and four were net-negative: they blocked or
warned about prose describing a mistake while permitting the mistake itself.
`provenance-skip.tsv` records the ground for each, and `scripts/check-provenance.sh` fails if any of
them reappears.

---

## Hook Profiles

| Profile | Level | Active Hooks | Best For |
|---------|-------|-------------|----------|
| `minimal` | 1 | runs 4 of the 12 | Nothing, without reading the next paragraph first |
| `standard` | 2 | all 12 hooks run | Default -- recommended for all work |
| `strict` | 3 | the same 12 hooks as `standard` | Nothing; no hook declares `strict` |

Set via: `UNITY_HOOK_PROFILE=standard` in environment or `settings.local.json`.

### What `minimal` actually costs

**It drops 8 of the 12 hooks, and `bash-gate` is one of them.** O2 kept two hooks on merit —
`bash-gate` and `block-legacy-input` — and `minimal` disarms the first while keeping the second,
which declares `minimal` itself. "Maximum speed, minimal interference" is what this row used to say,
and it was describing the profile by its intent rather than by its effect.

<!-- kinglet:minimal-drops:begin -->
- `bash-gate` — **the gate on destructive Bash commands.** `minimal` turns it off. This is the one
  to know about: the profile reads as a performance setting and is in fact a safety setting.
- `guard-project-config` — blocks weakening analyzer and code-quality configuration
- `session-restore` — no prior-session context at startup
- `session-save` — nothing is persisted for the next session
- `track-edits` — `session-save` then has no list of modified files even if re-enabled
- `warn-filename` — no warning when a C# file name stops matching its type
- `warn-platform-defines` — no warning on a platform `#if` with no `#else`
- `warn-serialization` — **no warning when a `[SerializeField]` rename drops
  `[FormerlySerializedAs]`**, which is the silent-data-loss case `.claude/rules/serialization.md`
  opens with
<!-- kinglet:minimal-drops:end -->

What `minimal` keeps:

<!-- kinglet:minimal-keeps:begin -->
- `block-scene-edit` — blocks Edit/Write on `.unity` / `.prefab` / `.asset`
- `block-meta-edit` — blocks Edit/Write on `.meta`
- `block-legacy-input` — blocks legacy `Input.*` in first-party runtime C#
- `session-brief` — declares no `HOOK_PROFILE_LEVEL`, so every profile runs it
<!-- kinglet:minimal-keeps:end -->

Both the count and the membership of that list are derived and guarded by
`tests/test-derived-counts.sh`, which reads the marked region above and compares it, as a set, with
the levels declared in the hook files themselves.

The `standard` profile is the default. Each profile includes all hooks from lower levels plus its own.

**`strict` is now empty of its own hooks and therefore equal to `standard`.** Every hook that
declared `strict` was removed on 2026-08-13, on the measured ground that `UNITY_HOOK_PROFILE` is set
nowhere in `settings.json`, `install.sh` or `scripts/` — so `standard` is the only profile that has
ever been active, and those seven hooks exited 0 before their first line on every session this
toolkit has shipped. The tier still doing work is `minimal`, which drops 8 of the 12 hooks — every
hook declaring `standard`, and that is not the same set as "the warning hooks". Three are `warn-*`
and two are `session-*`; the other three are `track-edits` and **both `PreToolUse` guards,
`bash-gate` and `guard-project-config`**. Until 2026-08-14 this sentence read "the four warning and
session hooks", which was wrong in the number (four is the size of the *keeps* list below) and wrong
in the kind. The membership is the marked region above; derive it rather than trusting either:

```bash
grep -l '^HOOK_PROFILE_LEVEL="\(standard\|strict\)"' .claude/hooks/*.sh
```

---

## Kill Switches

| Variable | Effect |
|----------|--------|
| `DISABLE_UNITY_HOOKS=1` | Bypass ALL hooks |
| `DISABLE_HOOK_<NAME>=1` | Bypass specific hook (name uppercased, hyphens to underscores) |
| `UNITY_HOOK_MODE=warn` | Downgrade blocking hooks to warnings |

Examples:
```bash
# Disable all hooks temporarily
DISABLE_UNITY_HOOKS=1

# Disable only the bash-gate hook
DISABLE_HOOK_BASH_GATE=1

# Downgrade blocks to warnings (hooks still run but exit 0)
UNITY_HOOK_MODE=warn
```

Configure overrides in `.claude/settings.local.json` (git-ignored) so they do not affect the team.

---

## Hooks by Event

### PreToolUse -- Edit|Write

These hooks run before any Edit or Write tool invocation. Blocking hooks (exit 2) prevent the operation from executing.

#### block-scene-edit

- **File:** `block-scene-edit.sh`
- **Profile:** minimal
- **Type:** Blocking (exit 2)
- **What it does:** Prevents direct editing of `.unity`, `.prefab`, and `.asset` YAML files. These files contain serialized references that break when text-edited. Use unity-mcp tools (`manage_scene`, `manage_gameobject`, `manage_prefabs`) instead.
- **Environment variables:** None (uses standard `_lib.sh` kill switches)

#### block-meta-edit

- **File:** `block-meta-edit.sh`
- **Profile:** minimal
- **Type:** Blocking (exit 2)
- **What it does:** Prevents editing `.meta` files. Meta files contain GUIDs that Unity uses to reference assets. Editing them breaks every reference to that asset across all scenes, prefabs, and scripts.
- **Environment variables:** None

#### block-legacy-input

- **File:** `block-legacy-input.sh`
- **Profile:** minimal
- **Type:** Blocking (exit 2)
- **What it does:** Blocks the legacy Input Manager API (`Input.GetKey`, `Input.GetAxis`, `Input.GetButton`, `Input.mousePosition`, `Input.touches`) in first-party runtime C#. Three rule files stated that legacy input was "BLOCKED by hooks" before any such hook existed; this is the hook that makes the statement true. Exempt: third-party and vendored code (a hook that fires on files you must never edit trains you to ignore the hook), and `Editor/` and `Tests/` folders, which are not runtime code. It matches the API on a word boundary, so a wrapper whose name merely ends in `Input` — `MyInput.GetKey`, `XRInput.GetAxis` — is not mistaken for it.
- **Environment variables:** None

#### guard-project-config

- **File:** `guard-project-config.sh`
- **Profile:** standard
- **Type:** Blocking (exit 2)
- **What it does:** Prevents modification of project configuration files that enforce code quality rules (`.editorconfig`, `*.ruleset`, `*.globalconfig`, `Directory.Build.props` analyzer sections). Forces the agent to fix code to meet existing rules rather than weakening the rules.
- **Environment variables:** None

### PreToolUse -- Bash

#### bash-gate

- **File:** `bash-gate.sh`
- **Profile:** standard
- **Type:** Blocking (exit 2)
- **What it does:** Destructive Bash gate. The first attempt at a destructive command is denied with an impact list and a demand for a rollback plan; a second attempt proceeds, on the basis that the agent has acknowledged the consequences. Covers Unity-specific danger patterns: `rm -rf Library/|Temp/|Logs/|obj/|Build/` (full reimport, GUID corruption risk), mass `.meta` deletion or rename (breaks every asset reference), `Packages/manifest.json` removal, `ProjectSettings/` wipes, `git reset --hard` / `git clean -fdx`, force-pushes to main/master, and PlayerPrefs CLI wipes.
- **Environment variables:** None

---

### PostToolUse -- Edit|Write

These hooks run after every Edit or Write tool invocation. They warn but do not block.

#### warn-serialization

- **File:** `warn-serialization.sh`
- **Profile:** standard
- **Type:** Advisory (exit 0)
- **What it does:** Detects when a `[SerializeField]` field is renamed without `[FormerlySerializedAs]`. This causes silent data loss -- every configured value in every scene and prefab resets to default.
- **Environment variables:** None

#### warn-filename

- **File:** `warn-filename.sh`
- **Profile:** standard
- **Type:** Advisory (exit 0)
- **What it does:** Checks that C# file name matches the primary class/struct name. Unity requires MonoBehaviour/ScriptableObject file name to equal the class name, otherwise the script cannot be attached to GameObjects.
- **Environment variables:** None

#### warn-platform-defines

- **File:** `warn-platform-defines.sh`
- **Profile:** standard
- **Type:** Advisory (exit 0)
- **What it does:** Checks for `#if UNITY_PS5` / `UNITY_GAMECORE` / `UNITY_STANDALONE_*` etc. without `#else` fallback. Code inside platform defines is silently excluded on other platforms -- a block guarded for console vanishes in the Standalone build and vice versa. Exempt since 2026-08-15: third-party and vendored code, the same skip list `block-legacy-input` has always carried. On a shipping project of 1417 C# files this hook fired 4 times and every one was under `Assets/Extensions/Feel/`, a vendored asset -- and a hook that fires on files you must never edit trains you to ignore the hook.
- **Environment variables:** None

#### track-edits

- **File:** `track-edits.sh`
- **Profile:** standard
- **Type:** Advisory (exit 0)
- **What it does:** Records files that have been edited during the session. Read by `session-save.sh` for the `modified_files` field of the session state.
- **Environment variables:** Writes to `UNITY_EDITS_FILE`

### SessionStart

#### session-restore

- **File:** `session-restore.sh`
- **Profile:** standard
- **Type:** Advisory (exit 0)
- **What it does:** Restores prior session state on conversation start. **What it actually prints today:** branch context and previously modified files. It also reads `workflow_phase`, `plan.description`, `plan.steps`, `verification.last_iteration` and `agent_context.last_agent`, and each print is guarded on the value being non-empty — so with `session-save.sh` emitting those five empty (see its entry above), none of those lines is ever printed. Clears stale tracking files from previous sessions. Respects a configurable TTL for session expiry.
- **Environment variables:** `UNITY_SESSION_TTL_HOURS` (default: 4) -- sessions older than this are discarded

#### session-brief

- **File:** `session-brief.sh`
- **Matcher:** `startup|clear|compact` (the only hook in this file with a SessionStart matcher — the others run on every SessionStart)
- **Profile:** always (declares no `HOOK_PROFILE_LEVEL`, so every profile runs it)
- **Type:** Advisory (exit 0)
- **What it does:** Injects the `using-kinglet` skill into the session at start, with its YAML frontmatter stripped, so a fresh session opens knowing which surface handles which situation. Prints nothing and exits 0 when the skill file is absent — a session must never fail to start because a brief is missing.
- **Environment variables:** Reads `CLAUDE_PROJECT_DIR` to locate the skill; falls back to the working directory

---

### Stop

These hooks run when the agent stops (conversation ends or user exits).

#### session-save

- **File:** `session-save.sh`
- **Profile:** standard
- **Type:** Advisory (exit 0)
- **What it does:** Saves session state when the agent stops so subsequent conversations can resume context. **What it actually captures today:** branch, modified files (from `track-edits.sh`), recent commits, session duration, warning count, and a `saved_at` timestamp. It also emits `workflow_phase`, `tool_calls`, `plan`, `verification` and `agent_context` — and **all five are permanently empty**, because nothing writes the files they read. `workflow_phase` lost its only writer (`pre-compact.sh`) in the 2026-08-13 cut; `tool_calls` reads `session-cost.jsonl`, whose writer (`cost-tracker.sh`) declared `strict` and therefore never ran even before the cut; `plan`, `verification` and `agent_context` had no writer at any point in this toolkit's history. The schema keeps them so a future writer needs no consumer change; the reader should expect `""`, `0` and `{}`.
- **Environment variables:** Reads `UNITY_EDITS_FILE`, `UNITY_COST_FILE`, `UNITY_WARNINGS_FILE`. Writes `UNITY_SESSION_FILE`

## Summary Table

| Hook | Event | Matcher | Profile | Type | Purpose |
|------|-------|---------|---------|------|---------|
| block-scene-edit | PreToolUse | Edit\|Write | minimal | Blocking | Block .unity/.prefab/.asset edits |
| block-meta-edit | PreToolUse | Edit\|Write | minimal | Blocking | Block .meta edits |
| block-legacy-input | PreToolUse | Edit\|Write | minimal | Blocking | Block legacy Input.* in first-party runtime C# |
| guard-project-config | PreToolUse | Edit\|Write | standard | Blocking | Block quality config weakening |
| bash-gate | PreToolUse | Bash | standard | Blocking | Gate destructive Bash commands |
| warn-serialization | PostToolUse | Edit\|Write | standard | Advisory | Warn on renamed SerializeField |
| warn-filename | PostToolUse | Edit\|Write | standard | Advisory | Warn on file/class name mismatch |
| warn-platform-defines | PostToolUse | Edit\|Write | standard | Advisory | Warn on platform #if without #else |
| track-edits | PostToolUse | Edit\|Write | standard | Advisory | Track edited files for session |
| session-restore | SessionStart | (all) | standard | Advisory | Restore session state |
| session-brief | SessionStart | startup\|clear\|compact | always | Advisory | Inject using-kinglet at session start |
| session-save | Stop | (all) | standard | Advisory | Persist session state |

---

## Shared Library: _lib.sh

11 of the 12 hooks source `.claude/hooks/_lib.sh` after setting `HOOK_PROFILE_LEVEL`;
`session-brief.sh` is the exception described in the Overview. Which hooks source it is derived and
asserted by `tests/test-derived-counts.sh`, in both directions, so this sentence cannot go stale
silently the way it did between 2026-08-13 and 2026-08-14 — the Overview above was corrected and this
one was not, in the same file. The library provides:

- **Profile filtering** -- compares the hook's declared level against the active profile and exits silently if the hook should not run
- **Kill switch checks** -- `DISABLE_UNITY_HOOKS` and per-hook `DISABLE_HOOK_<NAME>`
- **State directory resolution** -- finds `.claude/state/` or falls back to `/tmp/unity-claude-hooks`
- **Shared file paths** -- `UNITY_SESSION_FILE`, `UNITY_READS_FILE`, `UNITY_EDITS_FILE`, `UNITY_COST_FILE`, `UNITY_LEARNING_FILE`, `UNITY_WARNINGS_FILE`
- **`unity_hook_block()`** -- replaces direct `exit 2` in blocking hooks; respects `UNITY_HOOK_MODE=warn`
- **`unity_track_edit()`** -- append an edited path to the edit-tracking file; `track-edits.sh` calls it
- **`unity_track_warning()`** -- record a hook warning for session analytics; `bash-gate.sh` is its only caller
- **`advisory_exit_guard()`** -- for hooks whose contract is "advisory, exit 0 always"

**Defined but dead**, and listed here so this section is not read as a menu of live services.
None of the six has a caller anywhere in the tree; `_lib.sh` states the reason at the definitions and
carries the command to re-derive the set:

- **`unity_track_read()`** -- its caller was `track-reads.sh`, removed 2026-08-13
- **`unity_was_read()`** -- its caller was `gateguard.sh`, removed 2026-08-13
- **`unity_state_read()`** / **`unity_state_write()`** -- read/write keys in `session.json`
- **`unity_project_hash()`**, **`unity_state_plan_update()`**

Until 2026-08-14 the first four sat in the live list above, and `unity_was_read()` was credited to
`GateGuard` in the present tense — a hook this toolkit deleted. The lowercase spelling had already
been scrubbed from this file; the capitalised one survived because the sweep was keyed on the
filename.
