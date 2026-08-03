#!/usr/bin/env bash
#
# session-brief.sh — inject the using-kinglet skill at session start.
#
# Carries the chain and the proactive posture, NOT surface selection: selection comes from each
# surface's own description frontmatter. This is the mechanism Superpowers uses, run from the
# project's own .claude/settings.json rather than from a plugin.
#
# Prints nothing and exits 0 when the skill is absent — a session must never fail to start because
# a brief is missing.
set -euo pipefail

SKILL_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/skills/using-kinglet/SKILL.md"

[ -f "$SKILL_FILE" ] || exit 0

# cat, not a pipeline: nothing downstream here can exit early, and the file is small.
cat "$SKILL_FILE"
