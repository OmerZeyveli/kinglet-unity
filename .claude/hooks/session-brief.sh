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
#
# KILL SWITCHES, INLINE, AND SOURCING _lib.sh INSTEAD WOULD BE THE WRONG TRADE. Every other hook gets
# `DISABLE_UNITY_HOOKS` and `DISABLE_HOOK_<NAME>` by sourcing `_lib.sh`. This one runs at
# SessionStart, and `_lib.sh` resolves a state directory (`git rev-parse`, `mkdir -p`) before it
# returns — under `set -euo pipefail` that is failure surface on the one path where failing means the
# session does not start, which the contract above exists to prevent. So the two switches are
# implemented here, in five lines, with no dependency.
#
# The alternative was to document the exception instead, and it was rejected on blast radius: five
# shipped places tell a user that `DISABLE_UNITY_HOOKS=1` bypasses ALL hooks: `_lib.sh`'s own header,
# `.claude/settings.local.json.template`, and the getting-started, architecture and hook-reference
# documents in the repository (which do not install). Correcting five of them to carve out the one
# hook that injects a whole
# skill into every session is a worse answer than making the sentence true. Until 2026-08-14 this
# hook honoured neither switch, and it is the loudest hook in the toolkit by volume of injected text
# — the most likely reason someone reaches for the switch in the first place.
#
# `tests/test-hooks.sh` asserts the behaviour for EVERY hook in the directory rather than for this
# implementation, so the inline copy cannot drift from `_lib.sh`'s without something going red.
set -euo pipefail

if [ "${DISABLE_UNITY_HOOKS:-}" = "1" ]; then
    exit 0
fi

# Same derivation as _lib.sh's: basename, uppercased, hyphens to underscores.
_HOOK_ENV_NAME="DISABLE_HOOK_$(basename "${BASH_SOURCE[0]}" .sh | tr '[:lower:]-' '[:upper:]_')"
if [ "${!_HOOK_ENV_NAME:-}" = "1" ]; then
    exit 0
fi

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
