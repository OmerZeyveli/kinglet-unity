---
name: unity-sessions
description: "List all saved sessions with branch, phase, modified-file count, and timestamp. Sessions are snapshots in .claude/state/sessions/ created by /unity-session-save."
user-invocable: true
args: none
---

# /unity-sessions — List Saved Sessions

Show every saved session snapshot with enough context to decide which to resume.

## Steps

1. Read the directory `.claude/state/sessions/` (create if missing, then report "no sessions saved yet").
2. For each `*.json` file, read:
   - `label` (from filename, stem)
   - `branch`, `workflow_phase`, `saved_at` (ISO8601)
   - `tool_calls`, `warnings_count`
   - `modified_files` length
   - `plan.description` if present
3. Sort by `saved_at` descending.
4. Render a table:

```markdown
## Saved Sessions

| Label | Branch | Phase | Age | Files | Plan |
|---|---|---|---|---|---|
| refactor-hud | feature/hud | Execute | 2h ago | 14 | Rewrite HUD to UI Toolkit |
| perf-spike   | main        | Verify  | 1d ago | 3  | Pool bullet VFX |
| ... | ... | ... | ... | ... | ... |
```

5. Suggest the next command:

> Resume one with `/unity-session-resume <label>` or start fresh — your current session is unaffected until you resume.

## Rules

- **Read-only.** Never delete or modify session files.
- **Handle missing dir gracefully** — say "no sessions saved yet" and point to `/unity-session-save`.
- **Ignore malformed JSON files** — report count of skipped files at the bottom but do not fail.
