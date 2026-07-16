---
name: unity-instincts
description: "Manage the project's instinct library — view, promote, evolve, export, or import atomic learned behaviors captured automatically by PostToolUse observations."
user-invocable: true
args: subcommand
---

# /unity-instincts — Instinct Library

Manage atomic Unity-specific learnings: **$ARGUMENTS**

Instincts are atomic learned behaviors captured by `instinct-capture.sh` (PostToolUse) and distilled by `instinct-distill.sh` (Stop). Each instinct has: a trigger, an action, a confidence score (0.3–0.9), an evidence count, and a scope (project or global).

Storage:
- Project instincts: `.claude/state/instincts/project/<project-hash>/*.json`
- Global instincts:  `.claude/state/instincts/global/*.json`
- Raw observations:  `.claude/state/instincts/observations.jsonl`

## Subcommands

### `status` (default)

Show a dashboard of the instinct library for the current project.

1. Compute project hash: `git config --get remote.origin.url | shasum | head -c 12` (or fallback to `git rev-parse --show-toplevel`).
2. List files under `.claude/state/instincts/project/<hash>/` and `.claude/state/instincts/global/`.
3. For each instinct, read JSON fields and render:

```markdown
## Instinct Library

**Project:** <project-hash>
**Project instincts:** <count> (<count-above-0.7> high-confidence)
**Global instincts:** <count>
**Raw observations:** <count> (this session: <count>)

### High confidence (>= 0.7) — project
| Trigger | Action | Confidence | Evidence |
|---|---|---|---|
| before editing *View.cs | expect quality-gate warnings; read Model first | 0.8 | 12 |
| ... | ... | ... | ... |

### Medium (0.5–0.69) — project
...

### Low (0.3–0.49) — project
...

### Global (all scopes)
...
```

Sort within each band by `evidence_count` desc.

### `list [--domain <d>] [--min-confidence <n>]`

Filter and list instincts. Useful when the library grows:

```bash
/unity-instincts list --domain mvs
/unity-instincts list --min-confidence 0.7
```

Read JSON files, filter, output the same table format as `status` but limited to the filtered set.

### `evolve [--min-confidence 0.8]`

Graduate high-confidence instincts into draft skill files.

1. Collect instincts from project and global scopes with `confidence >= N` (default 0.8) AND `evidence_count >= 5`.
2. Group by `domain`.
3. For each domain cluster, draft a SKILL.md:

```yaml
---
name: learned-<domain>-patterns
description: "Patterns auto-learned from Unity sessions in this project"
alwaysApply: false
globs: ["Assets/Scripts/**/*.cs"]
---

# Learned <Domain> Patterns

## Trigger
<trigger from highest-confidence instinct>

## Patterns
- <trigger>: <action> (seen <n> times)
- ...

## Source
Evolved from instincts: <list of instinct ids>
```

4. Output the draft to stdout; do NOT write it. Tell the user:
   > Draft skill at `.claude/skills/core/learned-<domain>-patterns/SKILL.md` — review before installing.

### `promote <instinct-id> [--force]`

Move a project instinct to the global scope. Normally only done when the same trigger/action has been seen in 2+ projects, but `--force` bypasses the check.

1. Read `.claude/state/instincts/project/<project-hash>/<instinct-id>.json`.
2. Without `--force`: look for an identical trigger in any OTHER project hash. If none found, refuse and say so.
3. Rewrite `scope: "global"`, drop `project_id`, write to `.claude/state/instincts/global/<instinct-id>.json`.
4. Delete the project copy.

### `demote <instinct-id>`

Inverse of promote. Moves a global instinct back to the current project, typically when it turned out to be project-specific.

### `export [--out <file>]`

Export all instincts (project + global) as a single JSON file. Default output: `.claude/state/instincts/export-<date>.json`.

### `import <file>`

Import instincts from a file produced by `export`. Duplicate IDs are merged: `evidence_count` sums, `confidence` is the max, `last_seen` is the max.

### `clear [--project | --global | --observations | --all]`

Delete state. Requires explicit flag — no accidental wipes.

- `--project`: remove only the current project's instincts
- `--global`: remove global instincts
- `--observations`: remove raw observations.jsonl
- `--all`: all of the above

Ask for confirmation before running.

## Rules

- **Read-only by default** — `status`, `list`, `evolve`, `export` never modify instinct files.
- **`evolve` outputs but does not save** — drafts go to stdout; the user installs them.
- **Promote is cross-project-aware** — refuses to promote without evidence from multiple projects unless `--force`.
- **Observations are raw** — they are the source of truth for the distiller; do not edit manually.
- **Privacy** — instincts are project-local by default and never leave the machine.

## When to use

- Periodically (`status`) to see what the toolkit has learned about your Unity workflow.
- After a long session (`evolve`) to see whether the learnings have crystallized into something worth encoding as a rule or skill.
- Across projects (`promote`) when you notice the same pattern working everywhere.
