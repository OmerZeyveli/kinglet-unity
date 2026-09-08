# kinglet-unity — entry document for Codex CLI

**You MUST read `CLAUDE.md` in this directory before answering anything about this repository,
including a clarifying question.** It is the repo guide: what this toolkit is, what is enforced
rather than requested, the provenance contract, the shell conventions, and how the test suite is
run and read. Nothing in it is repeated here.

That instruction is imperative on purpose, and the form was measured. Codex injects `AGENTS.md`
whole and does **not** load `CLAUDE.md` — a sentinel planted in `AGENTS.md` came back with zero
shell commands run, and the same sentinel in `CLAUDE.md` came back only after the model went
looking for it with `rg`. A *declarative* pointer ("the guide lives in `CLAUDE.md`") was read
1 time in 12 under a request that gave no reason to look for it; the imperative form above was
read and obeyed 12 of 12 under that same request. The measurements are in
`docs/research/codex-client/findings.md`, `## Rules and AGENTS.md`.

**If you are Claude Code, this file adds nothing** — `CLAUDE.md` is already loaded for you, and
the two do not disagree. Read on only for the Codex-specific facts below.

## What is different when this repository is opened in Codex

- **No skills are discovered.** This repository's `.claude/skills/` is the source of a *shipped*
  payload; it is not wired to a `.agents/skills/` root here, because the toolkit is developed
  under Claude Code and a second root would be one more thing to keep in sync. `install.sh`
  creates that root in a user's Unity project, not here.
- **No slash commands exist.** `codex-cli 0.145.0` has no command surface at all — 24 subcommands,
  none of them a prompt registry. Where this repository's documents write `/unity-review`, that is
  Claude Code's spelling for a surface Kinglet ships as a converted skill in a user's project.
- **No `.codex/` directory, and that is enforced.** The Codex hook config is generated per project
  by `scripts/codex-hook-shim.sh --emit-config`, because its command strings are absolute paths.
  `provenance-skip.tsv` records `.codex/hooks.json` and `.codex/agents` as `rule=absent`, so
  `scripts/check-provenance.sh` fails if either appears here.
- **The hooks in `.claude/hooks/` are live in this repository under Claude Code.** They are not
  registered for a Codex session opened here, so a Codex session in this tree is unguarded by
  them. Do not read a green `.claude/settings.json` as a gate that is running for you.

## The one rule that is not in `CLAUDE.md`

**Do not write into `docs/research/codex-client/evidence/`, and never point a probe at this
repository.** That directory is gitignored because it holds raw transcripts and disposable
`CODEX_HOME` directories containing a copy of the owner's credential. `scripts/codex-probe.sh`
runs Codex against a *disposable* project; a probe aimed here would write into the tree it is
measuring.
