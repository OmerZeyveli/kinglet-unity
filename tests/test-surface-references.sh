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
assert_eq "0" "$(printf '%s' "$BAD_REFS" | grep -c . || true)" \
  "no agent or command names a skill that does not exist"

# A skill's body can name a `/unity-*` command (e.g. using-kinglet's chain table, deep-interview's
# handoff) with nothing checking the name is real. test-skill-discovery.sh only checks the reverse
# direction — a command/agent naming a skill — so a skill naming a deleted command is invisible.
# Same shape, opposite direction: collect every `/unity-*` token in every skill body, report the
# ones with no matching .claude/commands/<name>.md.
#
# Scoped to `.claude/skills/*/SKILL.md` until `subagent-driven-implementation` shipped the first
# skill directory in this repo with siblings beside SKILL.md (its four dispatch templates). Those
# siblings name commands too and nothing was scanning them — the same "scanned set is not the whole
# reality" shape this repo's own final-reviewer-prompt now names as a category worth looking for.
# Widened to every .md under .claude/skills/, not just SKILL.md, so a future skill's sibling files
# are covered without another manual widening.
BAD_CMD_REFS=$(
  for f in "$REPO_DIR"/.claude/skills/*/*.md; do
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
assert_eq "0" "$(printf '%s' "$BAD_CMD_REFS" | grep -c . || true)" \
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
assert_eq "0" "$(printf '%s' "$UNTRACKED_PAYLOAD" | grep -c . || true)" \
  "no untracked file under .claude/ (invisible to provenance and baseline, but live for the model)"

# ============================================================================
# Every implementing agent must be told what counts as done.
#
# `verification-before-completion` is the only skill that is a precondition for *every* agent's
# job rather than for a subsystem: an agent that does not know what counts as evidence reports
# "done" from a compile. The 2026-08-03 second-pass review found no agent naming it, and the fix
# landed on four of eight — `unity-prototyper`, `unity-scene-builder`, `unity-ui-builder` and
# `unity-reviewer` were missed, in the same "applied on one side only" shape as the duplicate
# `## Project Facts` heading.
#
# The block is not decorative. Measured 2026-08-04 across 33 dispatched subagents on a real
# project: all 12 `unity-coder` implementers loaded both skills their block named, and seven of
# them reached past the block for a third. Agents obey this list, so what is on it matters — the
# same run had `unity-reviewer` mandating `object-pooling` and nothing else, and seven reviewers
# dutifully loaded a pooling guide to review save-schema and ScriptableObject code.
MISSING_VERIFY=""
for f in "$REPO_DIR"/.claude/agents/*.md; do
  [ -f "$f" ] || continue
  block=$(awk '/^## Skills to load/,/^The `Skill` tool lists/' "$f")
  if ! grep -qF -- 'verification-before-completion' <<< "$block"; then
    MISSING_VERIFY="${MISSING_VERIFY}${f#$REPO_DIR/} has no verification-before-completion in its Skills to load block"$'\n'
  fi
done

if [ -n "$MISSING_VERIFY" ]; then
  printf '%s' "$MISSING_VERIFY"
fi
assert_eq "0" "$(printf '%s' "$MISSING_VERIFY" | grep -c . || true)" \
  "every agent's Skills to load block names verification-before-completion"

# Anti-vacuity: the awk range above returns empty for a file whose block was renamed, and an empty
# block would then fail loudly rather than silently — but a renamed *trailer* makes every block
# empty at once, which fails eight times and reads as a real regression. Assert the shape holds.
BLOCKLESS=""
for f in "$REPO_DIR"/.claude/agents/*.md; do
  [ -f "$f" ] || continue
  n=$(awk '/^## Skills to load/,/^The `Skill` tool lists/' "$f" | grep -c '^- `' || true)
  [ "$n" -ge 1 ] || BLOCKLESS="${BLOCKLESS}${f#$REPO_DIR/} has no readable Skills to load block"$'\n'
done
if [ -n "$BLOCKLESS" ]; then
  printf '%s' "$BLOCKLESS"
fi
assert_eq "0" "$(printf '%s' "$BLOCKLESS" | grep -c . || true)" \
  "every agent still has a Skills to load block this guard can read"

# ============================================================================
# `unity-execution` holds the last copy of three blocks of vendored ECU v1.5.0 text.
#
# The Deslop Pass, the Final Summary template and the max-3 verify bound were vendored verbatim in
# 45eada9 ("Vendor everything-claude-unity v1.5.0 verbatim") as part of
# `.claude/commands/unity-workflow.md`, and transcribed unchanged into this skill. When that command
# is deleted, these are the ONLY copies in the repository and nothing else guards them — no other
# test in tests/ names any of these strings.
#
# The first version of this block asserted five bare category HEADINGS and two of the five rules.
# That is the silent loss it was written to catch, walking through it: a rewrite that keeps the five
# bold headings and paraphrases every explanation passes green, and the Final Summary could be
# deleted outright without reddening anything. So each category needle now carries its own body, all
# five rules are asserted, and the summary is asserted by its section headings AND two of its body
# lines — headings alone would let the same hollowing-out through one level down.
#
# Each needle below was proved load-bearing by deleting exactly that text from a scratch copy of the
# skill and confirming the assertion fails: none of them is satisfied by any other part of the file.
#
# `assert_file_exists` is the load-bearing half: it turns a missing skill into ONE counted, named
# assertion instead of a raw `cat:` on stderr followed by twenty-three identical "not found"
# failures that say nothing about the actual cause.
#
# `2>/dev/null || true` is belt-and-braces and nothing more. It is NOT required by any shell option
# here — under the flags the runner actually gives a sourced file the assignment happens either way
# and execution continues. Measured rather than reasoned, because two earlier versions of this
# comment asserted a mechanism instead of testing one (first that errexit would abort the file, then
# that nounset needed the guard; both false):
#
#   $ bash -c 'set -uo pipefail; set +e; v="$(cat /nonexistent 2>/dev/null)"; echo "rc=$? len=${#v}"'
#   rc=1 len=0          # ... and the next command still runs, and "$v" still expands under -u
#
# The runner does `set +e` immediately before `( source "$test_file" )`, so errexit is OFF in here
# and only nounset and pipefail are inherited. CLAUDE.md is the canonical record for those
# semantics; if this comment and that file ever disagree, that file wins and this one is the bug.
UE_SKILL="$REPO_DIR/.claude/skills/unity-execution/SKILL.md"
assert_file_exists "$UE_SKILL" \
  "unity-execution exists — the inline branch of the execution fork has a home"

deslop="$(cat "$UE_SKILL" 2>/dev/null || true)"

# Scope sentence first: it is what makes the pass bounded rather than "tidy up the codebase".
assert_contains "$deslop" \
  "perform a targeted code-bloat review on all files created or modified during this workflow" \
  "unity-execution carries the Deslop scope sentence"

# Heading AND body, per category. `${needle%% —*}` recovers the heading for the message.
while IFS= read -r needle; do
  [ -n "$needle" ] || continue
  assert_contains "$deslop" "$needle" \
    "unity-execution carries the Deslop category, body included: ${needle%% —*}"
done <<'UE_DESLOP_CATEGORIES'
**Unnecessary abstractions** — interfaces with one implementation, factory classes that create one type, wrapper classes that add no behavior
**Over-commenting** — comments that restate the code, obvious doc comments, commented-out code blocks
**Redundant error handling** — try/catch that just rethrows, null checks on values that can never be null, defensive code with no plausible failure mode
**Dead code** — unused private methods, unreachable branches, unused parameters
**Over-engineering** — generic solutions for non-generic problems, premature optimization patterns, unnecessary design patterns
UE_DESLOP_CATEGORIES

# All five rules, not just the two restraining ones. Rules 1, 2 and 5 were unguarded and are the
# ones a summariser drops first, being the least quotable.
#
# Capitalisation is load-bearing and was the plan's one defect here: `assert_contains` is `grep -F`
# with no `-i`, so the planned lowercase "do not touch code that existed before" would have failed
# against a faithful transcription and passed only against a paraphrase.
while IFS= read -r needle; do
  [ -n "$needle" ] || continue
  assert_contains "$deslop" "$needle" \
    "unity-execution carries the Deslop rule: $needle"
done <<'UE_DESLOP_RULES'
Only simplify, never add complexity
Preserve all runtime behavior
Do not touch code that existed before this workflow started
If in doubt, leave it alone — false positives are worse than missed bloat
Apply fixes directly, then re-check console via `read_console` to confirm no regressions
UE_DESLOP_RULES

# The verify loop. The bound is the half that earns the surface — an unbounded self-review either
# runs once and declares victory or runs until it gets bored — and nothing else asserted it.
while IFS= read -r needle; do
  [ -n "$needle" ] || continue
  assert_contains "$deslop" "$needle" \
    "unity-execution carries the verify-loop step: $needle"
done <<'UE_VERIFY_LOOP'
**Auto-fix** issues that are safe to fix automatically
**Re-verify** if fixes were applied (max 3 iterations)
**Run tests** via MCP if available
UE_VERIFY_LOOP

# The Final Summary template, which had no assertion at all. Section headings detect its removal;
# the two body lines detect it being hollowed out into headings with nothing under them — the same
# failure the category needles above were widened to catch.
while IFS= read -r needle; do
  [ -n "$needle" ] || continue
  assert_contains "$deslop" "$needle" \
    "unity-execution carries the Final Summary line: $needle"
done <<'UE_FINAL_SUMMARY'
## Workflow Complete
### What was built
### Files created/modified
### Verification results
### Test results
### Manual steps needed
### How to test
- [compilation status, test pass/fail counts]
- [any inspector assignments, scene references, etc.]
UE_FINAL_SUMMARY

# ============================================================================
# `unity-brainstorming` is the chain's entry point, and `provenance.tsv` makes claims about it.
#
# The manifest row says the file (a) kept ECU's Ambiguity Score — which is the entire basis for its
# `origin=ecu` — and (b) gained a category trigger, an MCP-write HARD-GATE, the design half, and a
# closed handoff, adapted from Superpowers. `check-provenance.sh` never reads the `note` column, so
# without assertions here every one of those claims is a sentence nobody can falsify. That is the
# criterion Task 3 derived and this block applies it: whatever the note says the file carries,
# something fails if that content leaves.
#
# Two of the claims are asserted as WHOLE BLOCKS with `assert_eq`, not with `assert_contains`.
# `assert_contains` is `grep -F`, and a multi-line pattern given to `grep -F` is a set of
# alternatives: any ONE line matching satisfies it, so a four-line gate could lose three lines and
# stay green. Run, not reasoned — this is the exact transcript:
#
#   $ printf 'no MCP write call is made\n' > g-hay
#   $ printf 'no MCP write call is made\nAND SO IS THIS SECOND LINE\n' > g-needle
#   $ grep -qF -- "$(cat g-needle)" g-hay && echo "MATCHED (only line 1 present)"; echo "exit=$?"
#   MATCHED (only line 1 present)
#   exit=0
#
# The haystack does not contain the second line at all, and the two-line needle still matched.
# `assert_eq` compares character for character and has no such hole.
UB_SKILL="$REPO_DIR/.claude/skills/unity-brainstorming/SKILL.md"
assert_file_exists "$UB_SKILL" \
  "unity-brainstorming exists — the chain has an entry point"

brainstorm="$(cat "$UB_SKILL" 2>/dev/null || true)"

# --- D2: the trigger is a category of work, not a judgment about the request -----------------
# The description IS the selection mechanism — there is no glob and no always-apply — so this
# string is the single most load-bearing text in the payload. Compared whole: asserting the
# fragment "You MUST use this before building anything" leaves the clause that names the category
# ("a new mechanic, system, component, scene, or UI screen"), the clause that names the forbidden
# actions, and the tweak exclusion all free to be reworded into a judgment again.
UB_DESC_EXPECTED='You MUST use this before building anything in this Unity project — a new mechanic, system, component, scene, or UI screen — and before writing a plan, touching C#, or mutating the scene. Explores intent, constraints and approaches, then writes the design decision to a file. Not for a tweak to something that already works.'
UB_DESC_ACTUAL="$(awk 'NR==1 && /^---$/ {f=1; next}
                      f && /^---$/ {exit}
                      f && /^description:/ {
                        sub(/^description:[[:space:]]*/, "")
                        sub(/^"/, ""); sub(/"$/, "")
                        print; exit
                      }' "$UB_SKILL" 2>/dev/null || true)"
assert_eq "$UB_DESC_EXPECTED" "$UB_DESC_ACTUAL" \
  "unity-brainstorming's description is D2's fixed trigger text, character for character"

# --- D3: the gate covers MCP writes, not only code -------------------------------------------
# The Unity-specific half of the adaptation, and the reason the Superpowers text could not be
# imported unchanged. Whole-block again: the line naming MCP is the one a summariser keeps, and
# the three around it — the dispatch ban, the irreversibility reason, and the no-exceptions
# sentence — are the ones it drops.
UB_GATE_EXPECTED='Until a design has been presented and approved: no implementer agent is dispatched, no `.cs` is
written, and **no MCP write call is made** — scene, prefab and ScriptableObject included. A single
MCP call mutates state that no test can restore. This applies to every request regardless of
perceived simplicity.'
UB_GATE_ACTUAL="$(awk '/^<HARD-GATE>$/ {f=1; next} f && /^<\/HARD-GATE>$/ {exit} f' "$UB_SKILL" 2>/dev/null || true)"
assert_eq "$UB_GATE_EXPECTED" "$UB_GATE_ACTUAL" \
  "unity-brainstorming's HARD-GATE is D3's text, character for character"

# --- D4: the handoff is closed and names the forbidden alternatives ---------------------------
# Anchored to the Handoff section. Unanchored against the whole file, `unity-planning` is satisfied
# by any passing mention and the prohibition could be deleted outright with this still green.
UB_HANDOFF="$(awk '/^## Handoff/ {f=1; next} f && /^## / {exit} f' "$UB_SKILL" 2>/dev/null || true)"
assert_contains "$UB_HANDOFF" ".claude/skills/unity-planning/SKILL.md" \
  "the handoff names its terminal state by path"
assert_contains "$UB_HANDOFF" "Invoke no other skill" \
  "the handoff is closed, not merely a recommendation"
while IFS= read -r needle; do
  [ -n "$needle" ] || continue
  assert_contains "$UB_HANDOFF" "$needle" \
    "the handoff names the forbidden alternative this repo actually ships: $needle"
done <<'UB_FORBIDDEN'
/unity-prototype
unity-coder
any MCP agent
UB_FORBIDDEN

# --- D2: depth scales the round, never the artifact -------------------------------------------
# The plan's needle here was the bare `design.md is still written`, which cannot match the plan's own
# fixed body text: that text writes it as `` `design.md` is still written ``, and assert_contains is
# `grep -F` — a literal, so the backticks are two characters that must be there. Caught by running
# the suite against a faithful transcription of the plan's own block. The needle carries the
# backticks; the body text is the plan's, unchanged.
#
# Three needles rather than one, because the claim has three separable halves and losing any of them
# reopens "no design": the bold lead states the rule, the middle clause states what survives depth 1,
# and the last line is the one that names the failure mode by name.
while IFS= read -r needle; do
  [ -n "$needle" ] || continue
  assert_contains "$brainstorm" "$needle" \
    "depth scales the round, never the artifact: $needle"
done <<'UB_DEPTH'
**Depth scales the round, never the artifact.**
`design.md` is still written, still presented, and still approved.
"Short design" and "no design"
UB_DEPTH

# --- The provenance claim that `origin=ecu` rests on ------------------------------------------
# D10 rules that this file stays `origin=ecu` because ECU's Ambiguity Score survives the rewrite.
# That is a claim about file content, made in a column no checker reads. If the score is ever
# summarised away, the row becomes a falsehood and — without these — nothing says so.
while IFS= read -r needle; do
  [ -n "$needle" ] || continue
  assert_contains "$brainstorm" "$needle" \
    "unity-brainstorming keeps ECU's Ambiguity Score: ${needle%% —*}"
done <<'UB_AMBIGUITY_SCORE'
## Ambiguity Score
Rate the request across 5 dimensions. Each scores 0–2:
1. **Scope** — What exactly is being built? What are its boundaries? What is NOT included?
2. **Platform** — Target platform, Unity version, render pipeline, input method?
3. **Performance** — FPS target, memory budget, draw call limits, target device tier?
4. **Integration** — What existing systems does this touch? Dependencies? Data flow?
5. **Acceptance Criteria** — How do we know it's done? What should we test? What does success look like?
**Threshold: total score >= 6 out of 10 to proceed.**
UB_AMBIGUITY_SCORE

# --- The design half the row claims the file gained -------------------------------------------
while IFS= read -r needle; do
  [ -n "$needle" ] || continue
  assert_contains "$brainstorm" "$needle" \
    "unity-brainstorming carries the design half: $needle"
done <<'UB_DESIGN_HALF'
docs/features/<slug>/design.md
Propose 2–3 approaches
Operator steps
Never `git add -A`
UB_DESIGN_HALF

# --- The exemption list is removed, not reworded ----------------------------------------------
# D2 removes it: a list of exemptions is a list of ways to talk yourself out of the round. Asserted
# by absence because the replacement (a category trigger plus a build/tweak pair) reads perfectly
# well beside a surviving exemption section, so a positive assertion cannot detect one.
while IFS= read -r needle; do
  [ -n "$needle" ] || continue
  assert_not_contains "$brainstorm" "$needle" \
    "the exemption list is gone from unity-brainstorming: $needle"
done <<'UB_GONE'
## When to Activate
## Exemptions
--skip-interview
UB_GONE

# The old name must be gone from the tree, not merely unused. There is no assert_file_absent in the
# runner; this is the file-existence idiom the rest of this file uses, inverted.
UB_OLD_STATE="absent"
if [ -e "$REPO_DIR/.claude/skills/deep-interview/SKILL.md" ]; then UB_OLD_STATE="present"; fi
assert_eq "absent" "$UB_OLD_STATE" \
  "the deep-interview path is gone from the tree, not merely unreferenced"

# --- The manifest row itself ------------------------------------------------------------------
# The note was collapsed to a summary plus a pointer into MERGE-NOTES.md, so the pointer is now
# load-bearing: a renamed section there would silently orphan the file's whole history. Nothing
# else in the suite reads a provenance note, so nothing else could catch it.
UB_ROW="$(awk -F'\t' '$1 == ".claude/skills/unity-brainstorming/SKILL.md"' "$REPO_DIR/provenance.tsv" 2>/dev/null || true)"
UB_MERGE_SECTION='## unity-brainstorming (was deep-interview): the full note history'
assert_contains "$UB_ROW" "ecu" \
  "unity-brainstorming's row still records its ECU lineage (D10)"
assert_contains "$UB_ROW" "$UB_MERGE_SECTION" \
  "the collapsed note points at a MERGE-NOTES.md section by its exact heading"
assert_contains "$(cat "$REPO_DIR/MERGE-NOTES.md" 2>/dev/null || true)" "$UB_MERGE_SECTION" \
  "that MERGE-NOTES.md section exists — the pointer resolves"
