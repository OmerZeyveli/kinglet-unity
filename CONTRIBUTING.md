# Contributing to Kinglet Pioneer

Thanks for your interest! This is a small, **low-support** project — issues and PRs are welcome,
but responses may be slow. To keep the toolkit coherent, please follow a few conventions.

## What this project is (and isn't)

Kinglet Pioneer is a **standalone Unity 6 toolkit for Claude Code**. It vendors
[everything-claude-unity (ECU)](https://github.com/XeldarAlz/everything-claude-unity) as its
engineering layer and adapts the process chain from
[Superpowers](https://github.com/obra/superpowers). Both are MIT. A design/production layer adapted
from [Claude-Code-Game-Studios (Donchitos)](https://github.com/Donchitos/Claude-Code-Game-Studios)
shipped earlier and was **removed on 2026-08-03**; zero files from it remain. There is **no ECU
prerequisite** and **no second install step** — one repo, one `install.sh`.

That makes us a **redistributor**, not an add-on, and it is the source of every rule below.
`CLAUDE.md`'s "What this is" and "The provenance contract" sections are the maintained statement of
all of it; this file points at them rather than keeping a second copy, because the second copy is
what went wrong. Until 2026-08-11 the conventions below described a nested skill layout, frontmatter
keys that do nothing, and agents that no longer exist — every one of them a failure the test suite
now rejects, sitting in the file a first-time contributor opens first.

- **Vendored files are tracked, not free-floating.** `provenance.tsv` has one row per tracked file:
  `path`, `origin` (`ecu`/`donchitos`/`superpowers`/`original` — four legal values),
  `upstream_version`, `upstream_path`, `upstream_sha256`, `status`
  (`verbatim`/`modified`/`original`), `note`.
- **If you change any vendored file (`origin` other than `original`), flip its `status` to
  `modified` and say why in `note`.**
  A file marked `verbatim` is a claim that it is byte-identical to upstream, and
  `scripts/check-provenance.sh --online` re-fetches the pinned commit and checks that claim with
  `cmp`. Silent edits to `verbatim` rows are how a manifest rots.
- **New files need a row too.** `check-provenance.sh` is bidirectional — a tracked file with no row
  is an orphan and fails the check, just like a row with no file.
- **Don't add anything mobile-specific.** PC/console only. This is enforced by
  `tests/test-no-mobile.sh`, not merely requested: mobile skills, mobile genres, touch framing, and
  "compute shaders don't work on mobile"-style guidance are removed from the vendored tree, and the
  test fails if any of it returns. `provenance-skip.tsv` records the deliberately-omitted paths with
  `rule=absent`, and `check-provenance.sh` fails if one reappears.
- **Don't add a second MCP.** It's CoplayDev-only by design (with a migration note in
  `MCP-SETUP.md`).
- **Keep the opinionated stack:** Unity 6 / C#, VContainer + MessagePipe + UniTask.

### Rule precedence (internal, not upstream)

ECU is no longer a separate thing to defer to — its rules are our rules. The five vendored rules
(`architecture.md`, `csharp-unity.md`, `performance.md`, `serialization.md`, `unity-specifics.md`)
are the **binding spine**. `pc-console.md` adds platform specifics **on top of** them; it does not
override them. If a change would make `pc-console.md` contradict a spine rule, the spine rule wins —
fix `pc-console.md` instead.

## Good areas to contribute

**The admission test for any new surface** — agent, command, or skill — is the one the 2026-08-03
cut applied: *does this do something the model cannot do unaided?* A surface that restates what the
model already knows makes the real ones harder to select. Adding one means answering that question,
not filling a quota. See `CLAUDE.md`, "What is enforced, not requested".

- **Engineering agents and commands** — work that drives the Unity Editor over MCP, or that encodes
  a Unity-specific trap the model gets wrong unaided. (Documentation-only agents that just write to
  `docs/` were the removed Donchitos layer; a new one would have to argue against that measurement.)
- **Setup/automation** — `install.sh`, `uninstall.sh`, `scripts/studio-doctor.sh`,
  `scripts/check-provenance.sh` robustness.
- **Guards for numbers and references that drift** — `tests/test-derived-counts.sh` and
  `tests/test-surface-references.sh` exist because a warning in prose is not a guard. If you find a
  claim in this repo that nothing checks, the fix is an assertion, not a note asking people to be
  careful.
- **Upstream defect fixes** — see MERGE-NOTES.md for the ones already found. If you fix another,
  mark the file `modified` and record it there.
- **Docs** — clarity fixes to README, MCP-SETUP, or the end-user `CLAUDE.md` that
  `scripts/generate-claude-md.sh` emits (that generator, not the repo-root `CLAUDE.md`, is where the
  `FILL:` markers live).

## Format conventions

**`CLAUDE.md`'s "Conventions" section is the specification.** Read it before adding a file of any
kind; what follows is the short version plus the two things that will actually bite you.

Payload files live under `.claude/` and install to `<project>/.claude/`. There is no `overlay/`
directory — that separation is gone; `provenance.tsv` tracks origin now, not the directory layout.

- **Skills are flat: `.claude/skills/<name>/SKILL.md`, one level.** That is the only depth Claude
  Code discovers. Nested under category directories — which is how they arrived from ECU, and how
  they sat until 2026-08-03 — **all 39 were invisible, with no error of any kind**, and the `Skill`
  tool could not invoke one of them. This file told contributors to nest them for eight days after
  that was fixed. `tests/test-skill-discovery.sh` §1 rejects it now.
- **Frontmatter is `name` and `description`, nothing else.** `alwaysApply` and `globs` are **Cursor**
  rule keys. Nothing in Claude Code has ever read either one; they were stripped from every skill on
  2026-08-03 and `tests/test-no-mobile.sh:96` fails if one returns. This file used to say only
  `core/` skills may set `alwaysApply: true` and cite that same test as *asserting* the permission —
  it asserts the prohibition. A key that reads as a control but controls nothing is worse than no
  key, because it gets believed. `description` is the entire selection mechanism: write it as the
  trigger condition, not as a title.
- **Agents** (`.claude/agents/<name>.md`): frontmatter `name`, `description`, `model`, `color`,
  `tools`. All eight shipping agents are `unity-*` implementers with `mcp__UnityMCP__*` tools. An
  agent that should use a skill needs `Skill` in `tools:` **and** a **Skills to load** block naming
  it — neither alone works, and nothing loads a skill implicitly.
- **Commands** (`.claude/commands/<name>.md`): frontmatter `name`, `description`, `user-invocable`,
  `args`. Put model/agent routing in the body (like `unity-review`).
- **Rules** (`.claude/rules/<name>.md`): plain Markdown, **no frontmatter**.
- `.claude/templates/` is not a current authoring surface — the directory does not exist. Repo-root
  `templates/` is a different thing — C# code templates the agents scaffold from — and is unaffected.
- **Do not invent output directories.** `docs/design`, `docs/adr` and `docs/production` belonged to
  the removed Donchitos layer and a field note measured them used 0 of 3 on a real project; nothing
  writes there. The process chain writes its design decision, plan and ledger under
  `docs/features/<slug>/`, and the skills that write them say so themselves.
- No file in the tree carries a Donchitos `<!-- Adapted from … -->` comment; that layer is gone. If
  one is ever reintroduced, keep the comment convention.

## Before opening a PR

- Run **`bash tests/run-tests.sh`**, and read its exit code rather than its Total. **Do not run a
  test file standalone unless you have checked which idiom it uses** — most of them borrow the
  runner's assertion helpers, and run on their own they exit 0 having asserted nothing at all.
  `CLAUDE.md`'s "Testing" section tells the two apart and is the only place that rule is maintained.
- Run **`scripts/check-provenance.sh`**. If you touched a vendored file, run it with `--online` too;
  that is the only mode that verifies `verbatim` really means verbatim — and note that it now
  verifies very little, because nearly every surface is `modified`. The offline half (no rows
  without files, no files without rows, every `rule=absent` path still absent) is what carries the
  weight; `CLAUDE.md`'s provenance section explains why.
- Confirm your files **load** in Claude Code (appear in `/help` for commands; invocable for agents)
  — valid YAML alone isn't enough.
- Run `scripts/studio-doctor.sh --project-dir <a-test-unity-project>` if you touched automation.
- If you bumped a pin, update `.claude/UPSTREAM` (it holds the ECU, Superpowers and unity-mcp
  versions and commits, and it ships into user projects) and note in the PR what you tested against.
  Editing anything under `.claude/` also drifts `migration/baseline-inventory.json` — regenerate it
  with `python3 -m tools.kinglet_build baseline-regenerate` **in its own commit**, after the content
  commit.
- Update `MERGE-NOTES.md` / `CREDITS.md` / `.claude/NOTICE.md` if you add or adapt third-party
  material. NOTICE.md ships into user projects and is how the MIT attribution obligation is met — it
  is not optional paperwork.
