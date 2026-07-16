# Contributing to cloud-nine-unity

Thanks for your interest! This is a small, **low-support** project — issues and PRs are welcome,
but responses may be slow. To keep the toolkit coherent, please follow a few conventions.

## What this project is (and isn't)

cloud-nine-unity is a **standalone Unity 6 toolkit for Claude Code**. It vendors
[everything-claude-unity (ECU)](https://github.com/XeldarAlz/everything-claude-unity) as its
engineering layer and adapts [Claude-Code-Game-Studios
(Donchitos)](https://github.com/Donchitos/Claude-Code-Game-Studios) for its design/production layer.
Both are MIT. There is **no ECU prerequisite** and **no second install step** — one repo, one
`install.sh`.

That makes us a **redistributor**, not an add-on, and it is the source of every rule below.

- **Vendored files are tracked, not free-floating.** `provenance.tsv` has one row per tracked file:
  `path`, `origin` (`ecu`/`donchitos`/`original`), `upstream_version`, `upstream_path`,
  `upstream_sha256`, `status` (`verbatim`/`modified`/`original`), `note`.
- **If you change an ECU-origin file, flip its `status` to `modified` and say why in `note`.**
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

- **PC/console design agents or commands** — new design/production disciplines that fit a solo or
  small-team, medium-weight process.
- **Production commands** — planning, estimation, retrospective, and review helpers.
- **Templates** — design/production document templates (keep them Unity 6 / PC-console framed, with
  placeholders, no game-specific content).
- **Setup/automation** — `install.sh`, `uninstall.sh`, `scripts/studio-doctor.sh`,
  `scripts/check-provenance.sh` robustness.
- **Upstream defect fixes** — see MERGE-NOTES.md for the ones already found. If you fix another,
  mark the file `modified` and record it there.
- **Docs** — clarity fixes to README / MCP-SETUP / CLAUDE.md template.

## Format conventions

Payload files live under `.claude/` and install to `<project>/.claude/`. There is no `overlay/`
directory — that separation is gone; `provenance.tsv` tracks origin now, not the directory layout.
Match the existing frontmatter exactly:

- **Agents** (`.claude/agents/<name>.md`): frontmatter `name`, `description`, `model`, `color`,
  `tools`. Design/production agents are a documentation layer — **do not** give them
  `mcp__unityMCP__*` tools or have them write C#. That's the `unity-*` agents' job.
- **Commands** (`.claude/commands/<name>.md`): frontmatter `name`, `description`, `user-invocable`,
  `args`. Put model/agent routing in the body (like `unity-review`).
- **Skills** (`.claude/skills/<category>/<name>/SKILL.md`): frontmatter `name`, `description`, and
  glob/`alwaysApply` triggers. Only `core/` skills may set `alwaysApply: true` — a non-core skill
  that always applies loads on every C# file regardless of relevance, which is exactly the upstream
  bug the mobile strip fixed. `tests/test-no-mobile.sh` asserts this.
- **Rules** (`.claude/rules/<name>.md`): plain Markdown, **no frontmatter**.
- **Templates** (`.claude/templates/<name>.md`): plain Markdown; use bracketed `[placeholders]`.
  (Repo-root `templates/` is a different thing — C# code templates the agents scaffold from.)
- Adapted-from-Donchitos files keep their inline `<!-- Adapted from … -->` provenance comment.
- Write outputs to the project's `docs/` tree (`docs/design`, `docs/adr`, `docs/production`).

## Before opening a PR

- Run **`tests/run-tests.sh`** (the suites also run standalone — `bash tests/test-no-mobile.sh`).
- Run **`scripts/check-provenance.sh`**. If you touched a vendored file, run it with `--online` too;
  that's the only mode that verifies `verbatim` really means verbatim.
- Confirm your files **load** in Claude Code (appear in `/help` for commands; invocable for agents)
  — valid YAML alone isn't enough.
- Run `scripts/studio-doctor.sh --project-dir <a-test-unity-project>` if you touched automation.
- If you bumped a pin, update `.claude/UPSTREAM` (it holds the ECU / Donchitos / unity-mcp versions
  and commits) and note in the PR what you tested against.
- Update `MERGE-NOTES.md` / `CREDITS.md` / `.claude/NOTICE.md` if you add or adapt third-party
  material. NOTICE.md ships into user projects and is how the MIT attribution obligation is met — it
  is not optional paperwork.
