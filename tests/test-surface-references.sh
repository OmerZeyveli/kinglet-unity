#!/usr/bin/env bash
#
# test-surface-references.sh — an agent or command must not name a skill that does not exist.
#
# tests/test-skill-discovery.sh already checks PATH-FORM references (`.claude/skills/<name>`).
# It does not catch a bare name in a "Skills to load" list or a `skills:` frontmatter value,
# and on 2026-08-03 nine surviving surfaces carried exactly that after a cut. An agent told to
# load a skill that is not there gets no error of any kind — it just silently loads nothing.
#
# Runner-provided: uses the runner's assert_eq and $REPO_DIR. Run through tests/run-tests.sh.

echo "--- surface references ---"

SKILL_NAMES=$(ls -1 "$REPO_DIR/.claude/skills" 2>/dev/null | sort)

# Collect every bare name that appears either in a `skills:` frontmatter value or as a
# backticked list item in a "Skills to load" block, then report the ones with no directory.
BAD_REFS=$(
  for f in "$REPO_DIR"/.claude/agents/*.md "$REPO_DIR"/.claude/commands/*.md; do
    [ -f "$f" ] || continue
    awk -v file="$f" '
      # `skills: a, b, c` in frontmatter
      /^skills:[[:space:]]/ {
        line = $0
        sub(/^skills:[[:space:]]*/, "", line)
        n = split(line, parts, /[[:space:]]*,[[:space:]]*/)
        for (i = 1; i <= n; i++) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
          if (parts[i] != "") print file "\t" parts[i]
        }
      }
      # a backticked bare name on its own list line: "- `name`"
      /^[[:space:]]*-[[:space:]]*`[A-Za-z0-9_-]+`[[:space:]]*$/ {
        line = $0
        if (match(line, /`[A-Za-z0-9_-]+`/)) {
          name = substr(line, RSTART + 1, RLENGTH - 2)
          if (name != "") print file "\t" name
        }
      }
    ' "$f"
  done | sort -u | while IFS="$(printf '\t')" read -r src name; do
    [ -n "$name" ] || continue
    if [ ! -d "$REPO_DIR/.claude/skills/$name" ]; then
      printf '%s names missing skill: %s\n' "${src#$REPO_DIR/}" "$name"
    fi
  done
)

if [ -n "$BAD_REFS" ]; then
  printf '%s\n' "$BAD_REFS"
fi
assert_eq "$(printf '%s' "$BAD_REFS" | grep -c . || true)" "0" \
  "no agent or command names a skill that does not exist"

# An untracked file under .claude/ is live for Claude Code and invisible to check-provenance.sh
# (git ls-files) and to baseline-regenerate (ls-tree against a commit). Nothing else asserts this.
UNTRACKED_PAYLOAD=$(cd "$REPO_DIR" && git ls-files --others --exclude-standard -- .claude 2>/dev/null || true)

if [ -n "$UNTRACKED_PAYLOAD" ]; then
  printf 'untracked payload file: %s\n' $UNTRACKED_PAYLOAD
fi
assert_eq "$(printf '%s' "$UNTRACKED_PAYLOAD" | grep -c . || true)" "0" \
  "no untracked file under .claude/ (invisible to provenance and baseline, but live for the model)"
