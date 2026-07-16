---
name: unity-session-resume
description: "Restore a named session snapshot into the live .claude/state/session.json so the next SessionStart picks it up."
user-invocable: true
args: label
---

# /unity-session-resume — Resume a Saved Session

Restore a snapshot created with `/unity-session-save` so the next session restore reads this state: **$ARGUMENTS**

## Steps

1. Parse label from `$ARGUMENTS`. If missing, run `/unity-sessions` and tell the user to pick one.
2. Confirm `.claude/state/sessions/<label>.json` exists. If not:
   - Look for fuzzy matches (prefix, substring).
   - If multiple matches, show them and stop.
   - If one match, confirm before using it.
3. Warn the user if the current `.claude/state/session.json` has `saved_at` within the last 30 minutes AND has modified files — they may be about to overwrite live work. Offer to auto-save the current state first via `/unity-session-save current-<timestamp>`.
4. Copy `sessions/<label>.json` over `session.json`.
5. Report what was restored:

```markdown
Session **<label>** restored.

**Branch (snapshot):** <branch>
**Current branch:** <current>
**Workflow phase:** <workflow_phase>
**Plan:** <plan.description>
**Modified files at save:** <count>
**Saved:** <ISO timestamp>

⚠ Branch mismatch — run `git checkout <branch>` before resuming edits.
```

6. Remind the user that in-memory conversation context is not restored — only the state file. A new conversation must be started for the SessionStart hook to fire and inject the restored context.

## Rules

- **Branch mismatch warning** — if `.branch` in snapshot != current branch, highlight it and suggest checkout.
- **TTL respect** — if snapshot is older than `UNITY_SESSION_TTL_HOURS` (default 4), warn but allow.
- **Atomic** — write to `session.json.tmp` then `mv` so a crash doesn't leave a half-written file.
- **Never prompt for silent overwrite** — always show what's being replaced.
