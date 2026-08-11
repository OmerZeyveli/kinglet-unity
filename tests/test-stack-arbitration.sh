#!/usr/bin/env bash
# ============================================================================
# test-stack-arbitration.sh — a surface that names the architecture stack must say
# where to find out whether that stack binds.
#
# `.claude/rules/architecture.md` mandates Model-View-System with VContainer, MessagePipe and
# UniTask. Which of that binds in a given project is detected at install time and written into
# `CLAUDE.md`'s generated block — the rules layer was taught this on 2026-08-03. The command,
# agent and skill layers were not.
#
# Measured 2026-08-04 on a real project with 0 VContainer files: the model read the generated
# block, correctly concluded the stack does not bind, and then ruled out `/unity-workflow` and
# `/unity-feature` on the grounds that they "generate code with MVS/VContainer assumptions".
# `/unity-feature` named none of the four; `/unity-workflow` named VContainer once, in a
# sentence about when to escalate. Neither claim was checked against the files.
#
# Both commands were deleted on 2026-08-10 — they only sequenced other surfaces, which is a second
# definition of the chain (D7). That removes the two files the refusal landed on and NOT the
# regression: the loop below is driven by globs, so it never named those two, and the stack-naming
# prose that provoked the refusal lives on in `.claude/agents/unity-coder.md` and the surviving
# commands, which the same globs still reach. Measured across the deletion: 23 surfaces examined
# before, 21 after — the coverage moved by exactly the two files that stopped existing.
#
# What the refusal actually cost, measured the next day rather than predicted: nothing. The
# same session went on to dispatch `unity-coder` twelve times and `unity-reviewer` seventeen
# through `subagent-driven-implementation`, which reaches the agents without going through a
# command at all. The MCP capability was never lost. An earlier draft of this comment asserted
# it was — a prediction stated as a consequence, which is the error class this file exists to
# catch, committed inside the file that catches it.
#
# The guard is still right, and for the reason that survives: a surface was ruled out on a
# belief about its contents that reading it would have refuted, and nothing in the surface
# pointed at the block that adjudicates the question. Next time the fallback path may not exist.
#
# The fix is not "name the stack less". It is that every surface which names it also names the
# block that adjudicates it, so a reader who is about to refuse has somewhere to look first.
#
# Runner-provided: uses the runner's assert_eq and $REPO_DIR, defines neither, sets no `-e`,
# and contains no `exit`. Run it through tests/run-tests.sh and read this section; standalone
# it exits 0 having asserted nothing.
# ============================================================================

echo "--- stack arbitration ---"

# The four names that only mean something inside the toolkit's default stack. `Model-View-System`
# is deliberately absent: `architecture.md` uses it as a layering principle that survives without
# the container, and requiring the pointer wherever those words appear would flag prose that is
# stack-independent.
SA_STACK_RE='VContainer|MessagePipe|LifetimeScope|UniTask'

# The pointer. Matched on the phrase rather than the whole paragraph so the wording can be
# improved without the guard going red — the phrase is what a reader greps for.
SA_POINTER='generated block'

SA_MISSING=""
SA_CHECKED=0
for sa_f in "$REPO_DIR"/.claude/commands/*.md "$REPO_DIR"/.claude/agents/*.md \
            "$REPO_DIR"/.claude/skills/*/SKILL.md; do
  [ -f "$sa_f" ] || continue
  grep -qE -- "$SA_STACK_RE" "$sa_f" || continue
  SA_CHECKED=$((SA_CHECKED + 1))
  if ! grep -qF -- "$SA_POINTER" "$sa_f"; then
    SA_MISSING="${SA_MISSING}${sa_f#$REPO_DIR/} names the architecture stack and does not point at CLAUDE.md's generated block"$'\n'
  fi
done

if [ -n "$SA_MISSING" ]; then
  printf '%s' "$SA_MISSING"
fi
assert_eq "0" "$(printf '%s' "$SA_MISSING" | grep -c . || true)" \
  "every surface naming the architecture stack points at the generated block"

# Anti-vacuity. If the stack names ever disappear from every surface, the loop above examines
# nothing and reports success — the same shape as finding 8 of the 2026-08-03 second-pass review.
# The stack is named in a dozen places by design; zero means the regex broke, not that the
# coupling was solved.
assert_eq "yes" "$([ "$SA_CHECKED" -ge 10 ] && echo yes || echo "no ($SA_CHECKED)")" \
  "the guard examined a plausible number of stack-naming surfaces"

# The block is worth nothing if the generator stops emitting the thing it points at.
#
# Asserted as presence, not as a count. The first draft of this line asserted `== 1` and failed on
# its own first run: the generator names the heading twice — once in the comment explaining why the
# section exists, once in the `echo` that writes it — and a count couples the guard to how the
# generator is commented. What matters is that the heading is still emitted.
assert_eq "yes" \
  "$(grep -q 'Architecture stack — detected, not assumed' "$REPO_DIR/scripts/generate-claude-md.sh" \
     && echo yes || echo no)" \
  "the generator still emits the block every surface now points at"
