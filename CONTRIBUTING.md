# Contributing to cloud-nine-unity

Thanks for your interest! This is a small, **low-support** project — issues and PRs are welcome,
but responses may be slow. To keep the overlay coherent, please follow a few conventions.

## What this project is (and isn't)

cloud-nine-unity is an **overlay on top of [everything-claude-unity (ECU)](https://github.com/XeldarAlz/everything-claude-unity)**.
It adds a PC/console-focused **design & production** layer. It is **not** a standalone toolkit and
it does **not** fork or vendor ECU. Contributions should keep that boundary intact:

- **Don't copy ECU files into this repo.** The overlay only adds *new* agents/commands/rules/
  templates that sit alongside ECU's.
- **Don't add anything mobile-specific.** This overlay is PC/console only.
- **Don't add a second MCP.** It's CoplayDev-only by design (with a migration note in MCP-SETUP.md).
- **Keep the opinionated stack:** Unity 6 / C#, VContainer + MessagePipe + UniTask. Defer to ECU's
  rules for architecture/performance/serialization — ECU wins on any conflict.

## Good areas to contribute

- **PC/console design agents or commands** — new design/production disciplines that fit a solo or
  small-team, medium-weight process.
- **Production commands** — planning, estimation, retrospective, and review helpers.
- **Templates** — design/production document templates (keep them Unity 6 / PC-console framed, with
  placeholders, no game-specific content).
- **Setup/automation** — `install.sh`, `uninstall.sh`, `scripts/studio-doctor.sh` robustness.
- **Docs** — clarity fixes to README / MCP-SETUP / CLAUDE.md template.

## Format conventions (match ECU)

New payload files go under `overlay/` and must match ECU's frontmatter exactly:

- **Agents** (`overlay/agents/<name>.md`): frontmatter `name`, `description`, `model`, `color`,
  `tools`. Design/production agents are a documentation layer — **do not** give them
  `mcp__unityMCP__*` tools or have them write C#.
- **Commands** (`overlay/commands/<name>.md`): frontmatter `name`, `description`, `user-invocable`,
  `args`. Put model/agent routing in the body (like ECU's `unity-review`).
- **Rules** (`overlay/rules/<name>.md`): plain Markdown, **no frontmatter**.
- **Templates** (`overlay/templates/<name>.md`): plain Markdown; use bracketed `[placeholders]`.
- Adapted-from-Donchitos files keep their inline `<!-- Adapted from … -->` provenance comment.
- Write outputs to the project's `docs/` tree (`docs/design`, `docs/adr`, `docs/production`).

## Before opening a PR

- Confirm your files **load** in Claude Code (appear in `/help` for commands; invocable for agents)
  — valid YAML alone isn't enough.
- Run `scripts/studio-doctor.sh --project-dir <a-test-unity-project>` if you touched automation.
- Note in the PR which ECU version you tested against (the overlay is pinned to ECU v1.5.0).
- Update `MERGE-NOTES.md` / `CREDITS.md` if you add or adapt third-party material.
