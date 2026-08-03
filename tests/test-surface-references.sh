#!/usr/bin/env bash
#
# test-surface-references.sh — an agent or command must not name a skill that does not exist.
#
# tests/test-skill-discovery.sh already checks PATH-FORM references (`.claude/skills/<name>`).
# It does not catch a bare name in a "Skills to load" list or a `skills:` frontmatter value,
# and on 2026-08-03 nine surviving surfaces carried exactly that after a cut. An agent told to
# load a skill that is not there gets no error of any kind — it just silently loads nothing.
#
# Both reference forms are scoped to the section that actually means "load a skill":
#   - the YAML frontmatter `skills:` key (inline `skills: a, b` or a block sequence with
#     `skills:` alone on its line followed by indented `- name` items), matched only between
#     the file's opening `---` and closing `---`;
#   - a list item under a "## Skills to load" body heading, backticked or bare, matched only
#     between that heading and the next `##` heading.
# Scoping both rules this way means a stray `- ` list item elsewhere in the file (a tools list,
# a prose example, a fenced code block) can never be mistaken for a skill reference, and a bare
# (unbackticked) name is caught rather than silently passed — nothing in this repo enforces the
# backtick convention, so a check that only matched backticked names was a style assumption
# dressed up as coverage.
#
# Runner-provided: uses the runner's assert_eq and $REPO_DIR. Run through tests/run-tests.sh.

echo "--- surface references ---"

# Collect every bare name that appears either in a `skills:` frontmatter value (inline or YAML
# block sequence) or as a list item — backticked or bare — inside a "Skills to load" body block,
# then report the ones with no matching skill directory.
BAD_REFS=$(
  for f in "$REPO_DIR"/.claude/agents/*.md "$REPO_DIR"/.claude/commands/*.md; do
    [ -f "$f" ] || continue
    awk -v file="$f" '
      BEGIN { in_front = 0; in_seq = 0; in_load = 0 }

      NR == 1 && $0 == "---" { in_front = 1; next }
      in_front && $0 == "---" { in_front = 0; in_seq = 0; next }

      in_front {
        # inline form: `skills: a, b, c` — a value on the same line
        if ($0 ~ /^skills:[[:space:]]*[^[:space:]]/) {
          in_seq = 0
          line = $0
          sub(/^skills:[[:space:]]*/, "", line)
          n = split(line, parts, /[[:space:]]*,[[:space:]]*/)
          for (i = 1; i <= n; i++) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
            if (parts[i] != "") print file "\t" parts[i]
          }
          next
        }
        # YAML block-sequence form: bare `skills:` opens a run of indented `- name` items
        if ($0 ~ /^skills:[[:space:]]*$/) {
          in_seq = 1
          next
        }
        if (in_seq) {
          if ($0 ~ /^[[:space:]]+-[[:space:]]*/) {
            line = $0
            sub(/^[[:space:]]+-[[:space:]]*/, "", line)
            gsub(/^["\x27]|["\x27][[:space:]]*$/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (line != "") print file "\t" line
            next
          }
          in_seq = 0
        }
        next
      }

      # body: only inside the "Skills to load" section
      /^## Skills to load/ { in_load = 1; next }
      in_load && /^##/ { in_load = 0 }
      in_load && match($0, /^[[:space:]]*-[[:space:]]*`?[A-Za-z0-9_-]+`?[[:space:]]*$/) {
        line = $0
        sub(/^[[:space:]]*-[[:space:]]*/, "", line)
        gsub(/[[:space:]]+$/, "", line)
        gsub(/`/, "", line)
        if (line != "") print file "\t" line
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

# A skill's body can name a `/unity-*` command (e.g. using-kinglet's chain table, deep-interview's
# handoff) with nothing checking the name is real. test-skill-discovery.sh only checks the reverse
# direction — a command/agent naming a skill — so a skill naming a deleted command is invisible.
# Same shape, opposite direction: collect every `/unity-*` token in every skill body, report the
# ones with no matching .claude/commands/<name>.md.
BAD_CMD_REFS=$(
  for f in "$REPO_DIR"/.claude/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    # A command reference is `/unity-x`. A PATH containing the same characters is not — and
    # `.claude/rules/unity-specifics.md` contains `/unity-specifics`, so naming a rule file in prose
    # used to fail this check. `.claude/skills/unity-mcp-patterns/` had the same latent trap.
    #
    # Third instance in this wave of one shape: a substring match that fires on a mention. Field
    # note 81 rules on the class — a guard that blocks legitimate writing is mis-specified, not
    # strict. So require the slash to begin a token: preceded by start-of-line or by something that
    # is not a path character, then strip that guard character back off.
    grep -oE '(^|[^A-Za-z0-9_/.-])/unity-[A-Za-z0-9_-]+' "$f" \
      | sed 's|^[^/]*||' | sort -u | while IFS= read -r cmd; do
      [ -n "$cmd" ] || continue
      name="${cmd#/}"
      if [ ! -f "$REPO_DIR/.claude/commands/$name.md" ]; then
        printf '%s names missing command: %s\n' "${f#$REPO_DIR/}" "$cmd"
      fi
    done
  done | sort -u
)

if [ -n "$BAD_CMD_REFS" ]; then
  printf '%s\n' "$BAD_CMD_REFS"
fi
assert_eq "$(printf '%s' "$BAD_CMD_REFS" | grep -c . || true)" "0" \
  "no skill body names a /unity-* command that does not exist"

# An untracked file under .claude/ is live for Claude Code and invisible to check-provenance.sh
# (git ls-files) and to baseline-regenerate (ls-tree against a commit). Nothing else asserts this.
UNTRACKED_PAYLOAD=$(cd "$REPO_DIR" && git ls-files --others --exclude-standard -- .claude 2>/dev/null || true)

if [ -n "$UNTRACKED_PAYLOAD" ]; then
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    printf 'untracked payload file: %s\n' "$path"
  done <<< "$UNTRACKED_PAYLOAD"
fi
assert_eq "$(printf '%s' "$UNTRACKED_PAYLOAD" | grep -c . || true)" "0" \
  "no untracked file under .claude/ (invisible to provenance and baseline, but live for the model)"
