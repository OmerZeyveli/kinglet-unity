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
- **Claude-Code-Game-Studios (Donchitos)** — MIT, **adapted** at `984023d`, then **removed 2026-08-03**.
  The design/production layer (8 agents, 9 commands, 5 templates) was cut in the surface-reduction
  wave: a field note measured `docs/design`, `docs/production`, and `docs/adr` used 0 of 3 on a real
  project. `provenance-skip.tsv` records every path as `rule=absent`; `MERGE-NOTES.md` Part 1 keeps
  the adaptation reasoning for history. The 8 agents shipped today are all ECU-origin `unity-*`
  implementers, not this layer.
- **Superpowers (Jesse Vincent)** — MIT, **adapted** at 6.2.0 (`3dcbd5c`) on 2026-08-10. The process
  chain, rewritten for Unity at the expression level, not vendored: `.claude/skills/unity-planning/`
  from `skills/writing-plans/`, `.claude/skills/unity-execution/` from `skills/executing-plans/`
  (both `origin=superpowers`), and `.claude/skills/unity-brainstorming/` from `skills/brainstorming/`
  on top of ECU's `deep-interview` — which is why that one row stays `origin=ecu` with the adaptation
  recorded in its note. It is the newest upstream and the only one whose obligation this repo
  incurred itself rather than inherited: `.claude/NOTICE.md` §3 and `CREDITS.md` §4 discharge it, and
  `.claude/UPSTREAM` carries the pin. **No code path verifies that pin** — every adapted row is
  `status=modified`, so `--online` never reaches it.
- **CoplayDev unity-mcp** — not vendored. `.mcp.json` points at it on `localhost:8080`.

## The provenance contract

`provenance.tsv` has one row per tracked file: origin (`ecu` / `donchitos` / `superpowers` /
`original` — four legal values, as `provenance.tsv`'s own header line and `check-provenance.sh`'s
origin check both state; `superpowers` became legal on 2026-08-10 and this guide went a wave without
saying so, which is how a maintainer ends up writing `original` for a row that has an upstream),
upstream version and path, the upstream checksum, status (`verbatim` / `modified` / `original`), and
a note.

**If you change a vendored file, flip its `status` to `modified` and say why in the `note` column.**
Kinglet's surfaces are no longer vendored copies. `origin` records where a file came from and is a
standing MIT obligation; `status` is now `modified` or `original` for nearly every row, because the
surfaces have been rewritten for an agent reader. `--online` therefore verifies little and the
diff-tractability it once provided has been deliberately traded away. **The offline half is what
matters now**: no rows without files, no files without rows, and every `rule=absent` path stays
absent. That is what keeps a removed surface from silently returning. `scripts/check-provenance.sh`
enforces it:

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
  directory, `description:` must be non-empty (it is the entire selection mechanism). No skill may
  carry `alwaysApply` or `globs` either — both are inert Cursor keys that get read as guarantees —
  but that one is asserted in `tests/test-no-mobile.sh`, by the assertion reading
  *"no skill carries alwaysApply or globs"*, not here; this guide cited the wrong file for it until
  2026-08-11 and then the wrong line in the right file until 2026-08-14, which is why it now names
  the assertion instead of a number.
  Every skill an agent, a command, **or another skill** names by path must exist. The skill→skill
  direction was added 2026-08-11 (section 6 of that test) and it is the one the process chain is
  built out of: during the 2026-08-10 wave three surfaces named each other by path *before the
  targets existed*, across three tasks, and nothing in the suite went red at any point.
- **The surface pool is closed by a criterion, not by a number.** A surface — agent, command, or
  skill — survives the 2026-08-03 cut only if it does something the model cannot do unaided. That is
  the whole admission test: adding one means answering that question, not filling a quota, and the
  count is whatever the criterion leaves. Derive it, never quote it:

  ```bash
  ls .claude/agents/*.md | wc -l ; ls .claude/commands/*.md | wc -l ; ls -d .claude/skills/*/ | wc -l
  ```

  The user-facing documents *do* quote it, because a reader deciding whether to install needs a size.
  Those quotes are guarded rather than trusted: `tests/test-derived-counts.sh`'s surface-pool block
  runs that derivation and fails when `README.md`, `docs/ARCHITECTURE.md` or `docs/SKILL-CATALOG.md`
  disagrees with the tree. It was written on 2026-08-11 because the 2026-08-10 wave changed the
  pool's *composition* without changing its total — two commands out, two skills in — so every guard
  that watched a total stayed green while four quoted numbers went wrong at once. No total is written
  here; that is the bullet's own ruling applied to the bullet's own explanation.

  This bullet read *"the surface pool is 32 by design"* from the 2026-08-03 cut until 2026-08-11, and
  the tree had moved on without it — a stale count in the file that warns against stale counts, in a
  sentence stating a *number* where the load-bearing content was the *criterion*. The criterion was
  applied to agents, commands, and skills; hooks were out of scope for **that** wave, and every hook
  survived it untouched — they are the `.claude/hooks/*.sh` files less `_lib.sh`, which is a shared
  library and not a hook, and each real one is registered in `.claude/settings.json`. **That question
  is now settled.** `818b2bd` applied the same criterion to this directory on 2026-08-13 and removed
  15 of 27 hooks: seven had never run (they declared `strict` while nothing sets
  `UNITY_HOOK_PROFILE`), four were structurally broken, four were net-negative. `provenance-skip.tsv`
  carries the ground for each as `rule=absent`, so restoring one hits a red gate rather than a silent
  regression. What is **not** settled is the next hook added: nothing forces the criterion to be
  answered for it, which is the residual risk this paragraph now names instead of the closed one it
  named until 2026-08-14. `tests/test-surface-references.sh`
  guards bare-name skill references (a skill named without its `.claude/skills/<name>/SKILL.md`
  path); `tests/test-skill-discovery.sh` only matches path-form references and misses those entirely
  — that gap shipped nine dangling bare-name references on 2026-08-03 before the guard existed.

## Conventions

Payload files live in `.claude/`. There is no `overlay/` — it was dissolved; provenance replaced
directory-as-provenance.

- **Agents** (`.claude/agents/<name>.md`): frontmatter `name`, `description`, `model`, `color`,
  `tools`. All 8 current agents are ECU-origin `unity-*` implementers with `mcp__UnityMCP__*` tools
  that write C# and wire it into the scene — the Donchitos design/production agents that used to be
  documentation-only (no MCP tools, wrote to `docs/` instead) were removed 2026-08-03; see
  `provenance-skip.tsv` and `MERGE-NOTES.md`.
- **Commands** (`.claude/commands/<name>.md`): frontmatter `name`, `description`, `user-invocable`,
  `args`. Model/agent routing goes in the body.
- **Skills** (`.claude/skills/<name>/SKILL.md`): frontmatter `name` and `description`, nothing else.
  Flat — see above. An agent that should use a skill needs `Skill` in its `tools:` *and* a
  **Skills to load** block naming it; neither alone is enough, and nothing loads a skill implicitly.
- **Rules** (`.claude/rules/<name>.md`): plain Markdown, no frontmatter. `.claude/templates/` is not
  a current authoring surface — the design/production layer that populated it was removed
  2026-08-03, and the directory itself no longer exists. The repo-root `templates/` (C# scaffolds:
  `Model.cs.template`, `System.cs.template`, etc.) is unrelated and still present.
- No file in the current tree carries a Donchitos `<!-- Adapted from ... -->` comment; that layer
  is gone (see `provenance-skip.tsv`). If one is reintroduced, keep the comment convention.

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
bash tests/run-tests.sh                       # file/assertion counts drift — don't hardcode them here
bash scripts/check-provenance.sh              # manifest integrity  (--online to verify upstream)
bash tests/fixtures/mkproject.sh /tmp/p       # synthetic Unity project (--variant urp|builtin|bare|dirty)
bash install.sh --project-dir /tmp/p --dry-run
```

This repo is not a Unity project, and `install.sh` gates on `Assets/` + `ProjectSettings/`. The
fixture is how the installer gets exercised — everything it scans is plain text, so a directory with
the right shape covers it. Make fixtures realistic: a one-line `ProjectVersion.txt` hid a real bug,
because Unity writes two lines and both match the version regex.

The runner sources nothing into itself — each file runs in a subshell with stdin at `/dev/null`. It
used to `source` them into the runner process, and since several end in `exit`, the runner died in
the first file and 7 of 8 never ran while reporting green.

**The runner now checks its own discovery.** It counts the files the loop actually ran and compares
that against `find tests -maxdepth 1 -name 'test-*.sh'`, and it fails on a shortfall or an empty
discovery instead of printing a green zero. Until 2026-08-11 it did not: `nullglob` was unset, so an
unmatched glob left the pattern itself in the array, `${#test_files[@]}` was 1 rather than 0, and the
`-eq 0` guard with its `No test files found.` message was unreachable code. Measured on a copy of the
runner alone in an empty directory: `Total: 0  Passed: 0  Failed: 0`, **exit 0** — a strictly worse
version of the failure this paragraph opens with, because that one at least ran one file.

The by-eye version below is still worth knowing, since it is how you read a suite log rather than a
suite exit code — **and you must strip the ANSI escapes before counting**:

```bash
bash tests/run-tests.sh 2>&1 | tee /tmp/suite.log
sed $'s/\x1b\\[[0-9;]*m//g' /tmp/suite.log | grep -c '^--- test-.*\.sh ---'
ls tests/test-*.sh | wc -l
```

The runner **colours** that header, so the escape sequence sits between the line start and the text —
the line begins `ESC [ 0 ; 3 6 m - - -`, which `od -c` will show you. An anchored `grep -c` on raw
output therefore returns **0** on a completely healthy suite, and 0 is indistinguishable from the
catastrophe this count exists to detect. Unstripped, the instruction does not merely fail to check:
it reports that catastrophe on every single run, so anyone following it literally either panics or
"fixes" something that was never wrong. Measured 2026-08-11 against a green suite: raw **0**,
stripped and `ls` in agreement. (`$'…'` is bash ANSI-C quoting, so the pattern carries a literal ESC
byte rather than relying on `sed` to interpret `\x1b`.) **Do not write the expected number down
here** — a hardcoded count goes stale the next time a test file is added or removed, which is exactly
the failure mode this note exists to prevent, and it had gone stale twice by 2026-08-03.

**It still sources — into the subshell.** `( source "$test_file" )` is what actually runs, so a test
file inherits the runner's assertion helpers (`assert_contains`, `assert_eq`, `assert_file_exists`)
and `$REPO_DIR`. Two idioms therefore coexist, and mixing them fails silently:

- **Self-contained** — defines its own helpers and sets `set -euo pipefail`. `bash tests/<file>.sh`
  is a valid way to run it. `tests/test-templates.sh`, `tests/test-rule-applicability.sh`.
- **Runner-provided** — uses the runner's helpers and `$REPO_DIR`, defines neither. `bash
  tests/<file>.sh` **exits 0 having asserted nothing**: the helpers are undefined, `$REPO_DIR` is
  empty, and the file sets no `-e`. `tests/test-studio-doctor.sh`.

Run a runner-provided file through the runner and read its section, never standalone. A plan written
on 2026-08-03 told an implementer to verify a new check with `bash tests/test-studio-doctor.sh` and
expect a failure; it would have reported a pass in both directions.

None of this proves the toolkit works *in Claude Code* — only that the installer places correct
bytes. Frontmatter validity, command registration, and agent invocation still need one manual pass in
a real Unity project with the MCP bridge running.

## Where things go

- `install.sh` / `uninstall.sh` — the single installer and its receipt-driven inverse
- `scripts/` — `generate-claude-md.sh` (stdout only; the caller owns the destination),
  `check-provenance.sh`, `studio-doctor.sh`, plus ECU's validators
- `MERGE-NOTES.md` — the build record: what was taken, adapted, fixed, and left out
- `CREDITS.md` / `.claude/NOTICE.md` — the MIT obligations. NOTICE ships into user projects.
