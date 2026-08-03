# kinglet-unity — repo guide

> This file is for working **on the toolkit**. It is not a game template.
>
> The end-user `CLAUDE.md` — the one with `FILL:` markers for pitch, pillars, and scope — is emitted
> by `scripts/generate-claude-md.sh` into the user's Unity project. It used to live here, which meant
> opening this repo in Claude Code loaded "FILL: Game Title" as instructions for the toolkit itself.

## What this is

A standalone Claude Code toolkit for Unity 6, PC/console only. One repo, one `install.sh`.

It is assembled from other people's work, and that is the central fact about maintaining it:

- **everything-claude-unity (ECU)** — MIT, **vendored** at v1.5.0 (`bb28ccb`). The engineering layer:
  `unity-*` agents and commands, skills, hooks, the five spine rules, `settings.json`, plus the
  repo's `scripts/`, `tests/`, `docs/`, `examples/`, `templates/`.
- **Claude-Code-Game-Studios (Donchitos)** — MIT, **adapted** at `984023d`. The design/production
  layer: 8 agents, 9 commands, 5 templates. Each carries an inline attribution comment.
- **CoplayDev unity-mcp** — not vendored. `.mcp.json` points at it on `localhost:8080`.

## The provenance contract

`provenance.tsv` has one row per tracked file: origin (`ecu` / `donchitos` / `original`), upstream
version and path, the upstream checksum, status (`verbatim` / `modified` / `original`), and a note.

**If you change a vendored file, flip its `status` to `modified` and say why in the `note` column.**
This is not bookkeeping for its own sake — it is the only thing that makes a future diff against a
newer ECU tractable rather than archaeological. `scripts/check-provenance.sh` enforces it:

- no rows without files, no files without rows (a new file with no row fails as an orphan);
- every `status=verbatim` file must still match its recorded `upstream_sha256`;
- every `rule=absent` path in `provenance-skip.tsv` must stay absent;
- `--online` re-fetches the pinned upstream and verifies the recorded checksums themselves.

The manifest rotted the same day it was written — 38 files were edited and left marked `verbatim`
while the check reported OK, because the comparison only ran `--online`. Assume it will rot again if
the check is weakened.

`provenance-skip.tsv` records what was deliberately not vendored. `rule=absent` means the path must
never exist here; `rule=ours-wins` means upstream has the path and we ship our own file there.

## What is enforced, not requested

- **No mobile.** `tests/test-no-mobile.sh`. The rationale used to read "the mobile skill shipped
  `alwaysApply: true` with `globs: ["**/*.cs"]`, so it loaded on every C# file." That is false —
  neither key does anything in Claude Code — and the deletion is right anyway: mobile guidance in a
  PC/console toolkit is wrong guidance however it reaches the model. It is deleted along with the
  mobile genres and examples, at both the upstream and the flat path. Reintroducing any of it fails
  the suite.
- **Compute shaders and VFX Graph are available.** Upstream forbade them (correctly, for mobile GPUs).
  The test asserts nothing in the tree forbids them again.
- **Skills stay flat and stay clean.** `tests/test-skill-discovery.sh`. Every skill sits at
  `.claude/skills/<name>/SKILL.md` — one level, because that is the only depth Claude Code
  discovers. Nesting them under categories, which is how they arrived from ECU and how they sat
  until 2026-08-03, makes all 39 invisible with no error of any kind. `name:` must match the
  directory, `description:` must be non-empty (it is the entire selection mechanism), and no skill
  may carry `alwaysApply` or `globs` — both are inert Cursor keys that get read as guarantees.
  Every skill an agent or command names by path must exist.

## Conventions

Payload files live in `.claude/`. There is no `overlay/` — it was dissolved; provenance replaced
directory-as-provenance.

- **Agents** (`.claude/agents/<name>.md`): frontmatter `name`, `description`, `model`, `color`,
  `tools`. The 8 design agents are a documentation layer — do **not** give them `mcp__unityMCP__*`
  tools or have them write C#. They write to `docs/`.
- **Commands** (`.claude/commands/<name>.md`): frontmatter `name`, `description`, `user-invocable`,
  `args`. Model/agent routing goes in the body.
- **Skills** (`.claude/skills/<name>/SKILL.md`): frontmatter `name` and `description`, nothing else.
  Flat — see above. An agent that should use a skill needs `Skill` in its `tools:` *and* a
  **Skills to load** block naming it; neither alone is enough, and nothing loads a skill implicitly.
- **Rules** (`.claude/rules/<name>.md`) and **templates** (`.claude/templates/<name>.md`): plain
  Markdown, no frontmatter.
- Donchitos-derived files keep their inline `<!-- Adapted from ... -->` comment.

Precedence: the five spine rules bind. `pc-console.md` adds platform specifics on top; it does not
override them.

## Shell conventions

Everything here is bash. A macOS host pass is planned (`.claude/UPSTREAM` currently claims exactly
one shipped host, `linux-x64`, but macOS compatibility is being kept intact for that future pass).
That rules out `declare -A` (bash 4; macOS ships 3.2) and `grep -oP` (GNU-only).

Under `set -euo pipefail`, **do not pipe into a reader that exits early**. When it exits the writer
gets SIGPIPE, pipefail turns 141 into a failure, and `set -e` kills the script. It fires on large
inputs and hides on small ones, so it will pass your test and break in the field.

`head` is the obvious one. **`grep -q` is the same trap** — it exits the instant it matches, without
draining stdin. `tests/run-tests.sh`'s own assertion helpers did `echo "$haystack" | grep -qF
"$needle"`, and on a haystack over `PIPE_BUF` under CPU contention that reported *assertion failed*
while the needle was present the whole time. Three implementers hit it, called it a flake, and moved
on; it reproduces every time if you run two suites at once. Use a here-string — `grep -qF -- "$needle"
<<< "$haystack"` — or any form with no pipe.

The reader does not have to be `head`. Ask of any pipeline: can the right-hand side stop reading
before the left-hand side stops writing? Read the file with `awk` instead.

Validate an argument before `shift 2` — `shift` fails under `set -u` before your error message can
print, and the user gets a silent exit 1.

## Testing

```bash
bash tests/run-tests.sh                       # 21 files, 209 assertions (counts drift — see below)
bash scripts/check-provenance.sh              # manifest integrity  (--online to verify upstream)
bash tests/fixtures/mkproject.sh /tmp/p       # synthetic Unity project (--variant urp|builtin|bare|dirty)
bash install.sh --project-dir /tmp/p --dry-run
```

This repo is not a Unity project, and `install.sh` gates on `Assets/` + `ProjectSettings/`. The
fixture is how the installer gets exercised — everything it scans is plain text, so a directory with
the right shape covers it. Make fixtures realistic: a one-line `ProjectVersion.txt` hid a real bug,
because Unity writes two lines and both match the version regex.

The runner sources nothing into itself — each file runs in a subshell with stdin at `/dev/null`. It
used to `source` them, and since several end in `exit`, the runner died in the first file and 7 of 8
never ran while reporting green. If you touch the runner, confirm the number of `--- test-*.sh ---`
headers in the output equals `ls tests/test-*.sh | wc -l` (currently 21) — a hardcoded count here
would itself go stale the next time a test file is added or removed, which is exactly the failure
mode this note exists to prevent.

None of this proves the toolkit works *in Claude Code* — only that the installer places correct
bytes. Frontmatter validity, command registration, and agent invocation still need one manual pass in
a real Unity project with the MCP bridge running.

## Where things go

- `install.sh` / `uninstall.sh` — the single installer and its receipt-driven inverse
- `scripts/` — `generate-claude-md.sh` (stdout only; the caller owns the destination),
  `check-provenance.sh`, `studio-doctor.sh`, plus ECU's validators
- `MERGE-NOTES.md` — the build record: what was taken, adapted, fixed, and left out
- `CREDITS.md` / `.claude/NOTICE.md` — the MIT obligations. NOTICE ships into user projects.
