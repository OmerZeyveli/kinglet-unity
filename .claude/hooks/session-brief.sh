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

# awk, not a pipeline into an early-exiting reader: nothing downstream here can exit early, and the
# file is small. Strips the YAML frontmatter (the leading `---` ... `---` block) so a session opens
# with the skill's actual content instead of four lines of `name:`/`description:` noise.
awk '
    NR == 1 && $0 == "---" { infm = 1; next }
    infm && $0 == "---" { infm = 0; next }
    infm { next }
    { print }
' "$SKILL_FILE"
