---
name: unity-session-save
description: "Save the current session state as a labeled snapshot to .claude/state/sessions/<label>.json for later /unity-session-resume."
user-invocable: true
args: label
---

# /unity-session-save — Snapshot Current Session

Save the live session state (`.claude/state/session.json`) as a named snapshot: **$ARGUMENTS**

Unlike the automatic Stop-hook save (which overwrites `session.json`), this creates a named copy the user can return to later.

## Steps

1. Resolve the label from `$ARGUMENTS`.
   - If empty: default to `auto-<YYYYMMDD-HHMM>`.
   - Sanitize to `[a-z0-9-]+`; reject anything with slashes or spaces.
2. Check that `.claude/state/session.json` exists. If not, ask the user whether to save the in-memory context (in which case trigger a Stop-hook-equivalent save first, or tell them to wait until at least one Edit/Read has happened).
3. Ensure `.claude/state/sessions/` exists.
4. Read `session.json`; inject a top-level `label` field and a `source: "manual-save"` field into a copy.
5. Write to `.claude/state/sessions/<label>.json`.
6. If a file with the same label already exists, ask before overwriting. Default to append a numeric suffix (`<label>-2.json`) if the user says no.
7. Report:

```markdown
Session saved as **<label>**.
Branch: <branch>
Phase: <workflow_phase>
Modified files: <count>
Use `/unity-session-resume <label>` to restore.
```

## Rules

- **Label sanitization** — reject `..`, leading `-`, paths — accept only `[a-z0-9-]+`.
- **Never overwrite silently** — always prompt, always offer a safe fallback.
- **Idempotent** — saving the same label twice with user approval replaces cleanly.
- **Does not mutate the live session** — `session.json` is unchanged.
