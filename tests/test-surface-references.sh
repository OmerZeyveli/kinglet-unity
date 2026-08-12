#!/usr/bin/env bash
#
# test-surface-references.sh — a surface must not name something that does not exist, and the
# claims this repo makes about its own payload must be falsifiable.
#
# It started as the first of those and has grown into the second. Four kinds of check now live here,
# and a reader looking for one should know the others are present:
#
#   1. REFERENCE INTEGRITY — an agent or command naming a skill, a skill body naming a `/unity-*`
#      command, a chain-table cell naming a surface. The original job; described below.
#   2. STRUCTURAL CLAIMS about a payload file — every agent has a Skills to load block naming
#      `verification-before-completion`; the three skills `using-kinglet` advertises actually carry a
#      red-flag section.
#   3. FROZEN PROSE — named blocks of `unity-brainstorming` and `using-kinglet` are compared WHOLE
#      with `assert_eq`, because `provenance.tsv` and `MERGE-NOTES.md` make claims about them and
#      `check-provenance.sh` never reads a note. These assertions are meant to fail when the prose
#      changes: that is the contract, not a nuisance. Changing the payload means changing the
#      expected block in the same commit. `unity-execution` is guarded differently and more weakly —
#      about twenty `assert_contains` needles fed from the heredoc lists further down, no whole-block
#      comparison — so a rewrite of it that keeps those needles passes. Deliberately no line count
#      here: the first version of this header carried one, it was wrong on the day it was written,
#      and a count is the thing in this file most certain to rot (see the red-flag row's own numbers,
#      which is the same lesson one level down).
#   4. A HOOK IS EXECUTED — `.claude/hooks/session-brief.sh` is run and its output inspected, because
#      what ships into a session is the hook's stdout and not the file on disk.
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

# A skill's body can name a `/unity-*` command (e.g. using-kinglet's chain table, unity-brainstorming's
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

# ============================================================================
# The red-flag section exists in all three skills that are said to carry one.
#
# `using-kinglet` is injected at session start and tells the model that these skills each carry a
# "the thought that means you are about to…" section, to be read when the situation feels like an
# exception. That is a claim about three OTHER files, and on 2026-08-10 it was shipped false: the
# process-chain wave rewrote `unity-brainstorming`, the sentence was updated on the belief that the
# section had been removed with the exemption list, and the payload then steered readers away from
# a section that was sitting at `:183` under a new title the whole time. D2 removed the five-item
# exemption LIST; the red-flag section was retitled, not deleted.
#
# Matched on the stable prefix, not the full heading. The tails differ by design and one of them
# has already been rewritten once — `…about to skip this`, `…about to skip a step`, `…about to
# treat vague as clear`. Pinning the tail would fail on a legitimate retitle, which is the shape
# field note 81 rules against; pinning the prefix fails only when the section actually goes.
RF_PREFIX='## The thought that means you are about to'
RF_MISSING=""
while IFS= read -r rf_name; do
  [ -n "$rf_name" ] || continue
  rf_file="$REPO_DIR/.claude/skills/$rf_name/SKILL.md"
  if [ ! -f "$rf_file" ]; then
    RF_MISSING="${RF_MISSING}${rf_name}: no SKILL.md"$'\n'
  elif ! grep -qF -- "$RF_PREFIX" "$rf_file"; then
    RF_MISSING="${RF_MISSING}${rf_name}: no '${RF_PREFIX}…' section, but using-kinglet tells every session to read one"$'\n'
  fi
done <<'RF_SKILLS'
unity-brainstorming
systematic-debugging
verification-before-completion
RF_SKILLS

if [ -n "$RF_MISSING" ]; then
  printf '%s' "$RF_MISSING"
fi
assert_eq "0" "$(printf '%s' "$RF_MISSING" | grep -c . || true)" \
  "every skill using-kinglet says carries a red-flag section actually carries one"

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
# `.claude/commands/unity-workflow.md`, and transcribed unchanged into this skill. That command was
# deleted on 2026-08-10, so these ARE now the only copies in the repository and nothing else guards
# them — no other test in tests/ names any of these strings. The vendored original is still readable
# at `git show 45eada9:.claude/commands/unity-workflow.md` if a needle here ever needs re-deriving.
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

# The worktree refusal, and the artifact it used to cite.
#
# Until 2026-08-11 this paragraph ended "the refusal is recorded in `provenance-skip.tsv`". That
# file does not ship: `install.sh` copies `scripts/` and deliberately not `tests/`, and the manifest
# and its skip list were dropped from the payload on 2026-08-04. Verified against a fixture install
# on 2026-08-11 — `.claude/` in an installed project contains agents, commands, hooks, rules,
# scripts, skills, state and four files, and no `provenance*` anywhere in the tree. So the sentence
# sent a model reading this skill inside a user's Unity project after a file it cannot open.
#
# What the citation was protecting is the REASON, and the reason is Unity's and travels: no shared
# `Library/`, a full reimport per tree, diverging `.meta` GUIDs. That is asserted here. The
# `assert_not_contains` is the other half — the reason reads perfectly well with the dead pointer
# restored beside it, so a positive needle alone cannot keep it out.
assert_contains "$deslop" \
  'Worktrees do not share `Library/`, so every one triggers a full reimport, and' \
  "unity-execution refuses the worktree with the Unity reason, not a pointer at a file"
assert_not_contains "$deslop" "provenance-skip.tsv" \
  "…and cites no provenance artifact, which does not ship into a user's Unity project"
assert_not_contains "$deslop" "tests/" \
  "…nor a path under tests/, which install.sh deliberately does not copy either"

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
#
# Step 1 was missing from this block until 2026-08-11: it guarded steps 2, 3 and 4 and not the
# `unity-reviewer` invocation, which is the step that makes this a REVIEW loop rather than a
# self-assessment. Delete step 1 and the remaining three still describe something coherent — fix,
# re-check, test — so nothing here would have gone red while the only independent reader in the
# inline branch quietly left. The needle carries the agent name and the read-only qualifier, not the
# bold heading, so a rewrite that keeps "**Review**" and drops the agent fails.
while IFS= read -r needle; do
  [ -n "$needle" ] || continue
  assert_contains "$deslop" "$needle" \
    "unity-execution carries the verify-loop step: $needle"
done <<'UE_VERIFY_LOOP'
**Review** — invoke the `unity-reviewer` agent (read-only) against all changed files
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
# The manifest row and its MERGE-NOTES.md section say the file (a) kept ECU's Ambiguity Score, which
# is the entire basis for `origin=ecu`, and (b) gained a category trigger, an MCP-write HARD-GATE,
# the design half and a closed handoff, adapted from Superpowers. `check-provenance.sh` never reads
# the `note` column, so without assertions here every one of those claims is a sentence nobody can
# falsify.
#
# ROUND 1 REVIEW rebuilt this block. The first version satisfied the letter of that criterion and
# failed it in practice, in three measured ways, each of which the current shape exists to close:
#
#   1. `assert_contains "$UB_ROW" "ecu"` against the whole tab-joined row was VACUOUS: the note
#      inside that row contains the literal `origin=ecu rests on`, so the needle matched the text it
#      existed to guard. Reproduced before fixing — field 2 flipped to `superpowers`, this file
#      sourced through the runner's helpers: 59 assertions ran, 0 failed, and
#      "unity-brainstorming's row still records its ECU lineage (D10)" printed PASS. Field 2 is now
#      extracted and compared on its own.
#
#   2. Single-line needles let whole sections vanish. A reverse sweep deleting one line at a time
#      found 153 of 176 lines leaving the file green, including all of `## Interview Protocol`, all
#      of `## Scoring Examples` and the 0-2 score table — three of the five things MERGE-NOTES.md
#      names as ECU's surviving contribution. Deleting just those two sections drops the survivor
#      count from 33/69 to 14/69 with the suite green. So the four ECU blocks the manifest names are
#      now compared WHOLE, with assert_eq.
#
#   3. A needle satisfied by a duplicate elsewhere in the file cannot detect the loss of either
#      copy. `Propose 2–3 approaches` appears in the checklist and again in its own section;
#      `docs/features/<slug>/design.md` likewise. Both are now anchored to the section that must
#      contain them, which is also what makes deleting `## Checklist` fail.
#
# `assert_eq` rather than `assert_contains` for every block, because `assert_contains` is `grep -F`
# and a multi-line pattern given to `grep -F` is a set of ALTERNATIVES — any one line matching
# satisfies the whole needle. Run, not reasoned; this is the exact transcript:
#
#   $ printf 'no MCP write call is made\n' > g-hay
#   $ printf 'no MCP write call is made\nAND SO IS THIS SECOND LINE\n' > g-needle
#   $ grep -qF -- "$(cat g-needle)" g-hay && echo "MATCHED (only line 1 present)"; echo "exit=$?"
#   MATCHED (only line 1 present)
#   exit=0
#
# The haystack does not contain the second line at all, and the two-line needle still matched.
UB_SKILL="$REPO_DIR/.claude/skills/unity-brainstorming/SKILL.md"
assert_file_exists "$UB_SKILL" \
  "unity-brainstorming exists — the chain has an entry point"

brainstorm="$(cat "$UB_SKILL" 2>/dev/null || true)"

# Section extractor: everything strictly between a `## `/`### ` heading and the next heading of the
# same-or-shallower depth. Anchoring each claim to its own section is what makes a deleted heading
# fail — an unanchored needle is satisfied by any surviving copy of the text elsewhere in the file.
ub_section() {
  awk -v want="$1" '
    $0 == want { f = 1; next }
    f && /^#{1,3} / { exit }
    f { print }
  ' "$UB_SKILL" 2>/dev/null || true
}

# Leading- and trailing-blank-line trim, so a block comparison is not hostage to the blank line a
# Markdown heading is always followed by, nor to the spacing before the next one.
ub_trim() {
  awk '
    { lines[NR] = $0 }
    END {
      first = 1; last = NR
      while (first <= last && lines[first] ~ /^[[:space:]]*$/) first++
      while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
      for (i = first; i <= last; i++) print lines[i]
    }'
}

# There was a `ub_first_para` here in round 1, used where a whole-section comparison would have
# bundled two unrelated claims. Round 2 gave the skill a `### Threshold` heading instead, so every
# claimed block owns exactly one section and every comparison below is a whole section — which is
# what makes relocation and insertion detectable, and what a first-paragraph extractor cannot do
# (append a sixth dimension after a blank line and it stops before reaching it).

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
# imported unchanged. The line naming MCP is the one a summariser keeps; the three around it — the
# dispatch ban, the irreversibility reason, and the no-exceptions sentence — are the ones it drops.
UB_GATE_EXPECTED='Until a design has been presented and approved: no implementer agent is dispatched, no `.cs` is
written, and **no MCP write call is made** — scene, prefab and ScriptableObject included. A single
MCP call mutates state that no test can restore. This applies to every request regardless of
perceived simplicity.'
UB_GATE_ACTUAL="$(awk '/^<HARD-GATE>$/ {f=1; next} f && /^<\/HARD-GATE>$/ {exit} f' "$UB_SKILL" 2>/dev/null || true)"
assert_eq "$UB_GATE_EXPECTED" "$UB_GATE_ACTUAL" \
  "unity-brainstorming's HARD-GATE is D3's text, character for character"

# ============================================================================
# The blocks `provenance.tsv:71` and its MERGE-NOTES.md section name by name.
#
# The note says ECU's Ambiguity Score is what survives and that this is what `origin=ecu` rests on;
# MERGE-NOTES.md enumerates the 0-2 scale, the five dimensions, the >= 6 threshold, the interview
# protocol's first three steps and both scoring examples.
#
# ROUND 2: every one of these is now HEADING-anchored — the section is located by its heading and
# compared whole. Round 1 anchored most of them by CONTENT (`/^\| Score \| Meaning \|$/`,
# `/^That line is ECU/`, `/^\*\*Depth scales/`, `/^1\. \*\*Present the current scores\*\*/`), which
# asserts that the text exists SOMEWHERE and says nothing about where. Two measured escapes, both
# green against the round-1 guard:
#
#   - move ECU's 0-2 score table out of `## Ambiguity Score` into an appendix at the end of the file;
#   - append a sixth dimension after a blank line, so "five dimensions survive whole" passes while
#     the file lists six.
#
# The manifest does not claim this text is present. It claims ECU's Ambiguity Score survives — a
# structure, in named sections. A whole-section comparison is the only form that catches all three
# mutations at once: deletion (section missing), relocation (section no longer holds it), and
# insertion (section holds more than it should). The skill gained a `### Threshold` heading in this
# round so that each claimed block owns exactly one section and no comparison bundles two claims.
UB_SCORE_SECTION_EXPECTED='Rate the request across 5 dimensions. Each scores 0–2:

| Score | Meaning |
|-------|---------|
| 0 | Unspecified — no information provided |
| 1 | Partial — vague or implied |
| 2 | Clear — explicitly stated or obvious from context |'
assert_eq "$UB_SCORE_SECTION_EXPECTED" "$(ub_section '## Ambiguity Score' | ub_trim)" \
  "ECU's 0-2 score table survives whole, inside ## Ambiguity Score and nowhere else"

UB_DIMENSIONS_EXPECTED='1. **Scope** — What exactly is being built? What are its boundaries? What is NOT included?
2. **Platform** — Target platform, Unity version, render pipeline, input method?
3. **Performance** — FPS target, memory budget, draw call limits, target device tier?
4. **Integration** — What existing systems does this touch? Dependencies? Data flow?
5. **Acceptance Criteria** — How do we know it'"'"'s done? What should we test? What does success look like?'
assert_eq "$UB_DIMENSIONS_EXPECTED" "$(ub_section '### Dimensions' | ub_trim)" \
  "ECU's five dimensions survive whole — and the section holds five, not six"

# The threshold, plus the sentence reconciling it. ECU wrote ">= 6 ... to proceed", which is verbatim
# the score's OLD gate job; D2 gives the score a new one. Round 1 found all three statements in the
# file disagreeing, so the gloss lives in the same section as the line it glosses and they are
# compared together — losing either puts the contradiction straight back.
UB_THRESHOLD_EXPECTED='**Threshold: total score >= 6 out of 10 to proceed.**

That line is ECU'"'"'s, kept, and "proceed" is now defined: it means **proceed to presenting the
design**, never proceed past it. The threshold divides the same two states it always divided; what
changed is what lies on the far side. Below 6 nothing routes around the round, and at or above 6
nothing skips the artifact.'
assert_eq "$UB_THRESHOLD_EXPECTED" "$(ub_section '### Threshold' | ub_trim)" \
  "ECU's threshold survives with 'proceed' defined beside it, both in ### Threshold"

# D2's two rules about what the score decides. Compared as one section because they are one claim in
# two paragraphs: the score sets depth, and depth never reaches the artifact. Round 1 guarded the
# second and the first deleted green; round 1's fix guarded both but by content, so either could be
# moved out of the section that names them.
UB_SCORE_JOB_EXPECTED='The score sets the depth of the round, not whether the round happens. Below 6, ask up to three
questions and re-score. At or above 6, one confirming round is enough.

**Depth scales the round, never the artifact.** At depth 1 the design may be three sentences, but
`design.md` is still written, still presented, and still approved. "Short design" and "no design"
are different outcomes and only one of them is allowed.'
assert_eq "$UB_SCORE_JOB_EXPECTED" "$(ub_section '### What the score decides' | ub_trim)" \
  "D2's depth rules are stated whole, punchline included, inside ### What the score decides"

# The Interview Protocol. Steps 1-3 are ECU verbatim; step 4 is NOT, and deliberately so — ECU's
# ended with an explicit-opt-out clause that was the `--skip-interview` exemption in other clothes
# and contradicted the Handoff. The whole section is compared, which additionally catches a step 5
# being appended and the "one question per message" reconciliation being dropped.
UB_PROTOCOL_EXPECTED='When the score is below threshold:

1. **Present the current scores** — show the user which dimensions are weak
2. **Ask targeted questions** — max 3 questions per round, focused on the lowest-scoring dimensions
3. **Re-score after each round** — update scores based on answers
4. **Proceed when threshold is met** — to presenting the design. There is no opt-out. "Just do it"
   is answered by the depth-1 round: three sentences, one approval, and the file still written.

**One question per message.** Three per round is the budget, not the message size: a message
carrying three questions gets one answer, usually to the last of them. Prefer multiple choice where
the options are genuinely enumerable, open-ended where they are not.

Question style: be direct and specific, not generic. Instead of "What platform?", ask "Is this keyboard+mouse first or gamepad first — and does it have to hold 60fps on min-spec, or is the target high-end PC only?"'
assert_eq "$UB_PROTOCOL_EXPECTED" "$(ub_section '## Interview Protocol' | ub_trim)" \
  "ECU's protocol steps 1-3 survive whole and step 4 is reconciled, all inside ## Interview Protocol"

UB_EXAMPLES_EXPECTED='**Vague (score 3/10):** "Add multiplayer to my game"
- Scope: 1 (multiplayer is broad — co-op? competitive? matchmaking?)
- Platform: 0 (unspecified)
- Performance: 0 (unspecified)
- Integration: 1 (implies networking but no specifics)
- Acceptance: 1 (implied: "it works")

**Clear enough (score 7/10):** "Add 2-player local co-op split-screen for the existing PlayerController using the new Input System"
- Scope: 2 (2-player local co-op split-screen)
- Platform: 1 (implies desktop from split-screen, but not explicit)
- Performance: 1 (split-screen implies rendering budget concern)
- Integration: 2 (PlayerController, Input System explicitly named)
- Acceptance: 1 (implied: both players can play simultaneously)

Both of these are builds. The second scores 7 and still gets a design — one round, a short file.'
assert_eq "$UB_EXAMPLES_EXPECTED" "$(ub_section '## Scoring Examples' | ub_trim)" \
  "ECU's two scoring examples survive whole, under their own heading"

# --- The checklist, anchored so its deletion is not covered by a duplicate elsewhere -----------
# Every item here restates something the body also says. That is fine for a reader and fatal for an
# unanchored guard: round 1 measured `## Checklist` deleting entirely with the suite green, because
# the checklist's own needles were satisfied by the sections it summarises.
UB_CHECKLIST="$(ub_section '## Checklist')"
while IFS= read -r needle; do
  [ -n "$needle" ] || continue
  assert_contains "$UB_CHECKLIST" "$needle" \
    "the checklist carries its step: ${needle%% —*}"
done <<'UB_CHECKLIST_ITEMS'
You MUST create a task for each of these items and complete them in order
4. **Propose 2–3 approaches**
6. **Write `docs/features/<slug>/design.md`**
9. **Hand off to `unity-planning`**
UB_CHECKLIST_ITEMS

# The depth-1 collapse: two human approvals of the same three sentences is the cost that makes people
# stop running the round, and the sentence that prevents it is one a summariser drops first.
assert_contains "$UB_CHECKLIST" '**At depth 1, items 5 and 8 are one approval, not two.**' \
  "at depth 1 the two approvals collapse into one"

# --- The design half the row claims the file gained, anchored to its own section ---------------
UB_DESIGN="$(ub_section '## What `design.md` carries')"
while IFS= read -r needle; do
  [ -n "$needle" ] || continue
  assert_contains "$UB_DESIGN" "$needle" \
    "the design-content spec carries: $needle"
done <<'UB_DESIGN_HALF'
docs/features/<slug>/design.md
**Approaches considered**
Model/View/System terms
Architecture stack — detected, not assumed
**Acceptance criteria**
**Operator steps**
Never `git add -A`
UB_DESIGN_HALF

# The 2-3 approaches section, anchored, because the checklist carries the same phrase.
assert_contains "$(ub_section '## Exploring approaches')" 'Propose 2–3 approaches with their trade-offs' \
  "the approaches section exists and is not merely the checklist line"

# --- D4: the handoff is closed and names the forbidden alternatives ---------------------------
UB_HANDOFF="$(ub_section '## Handoff')"
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

# --- D7's exemption, which existed in the spec and nowhere in the payload ----------------------
# D7 records /unity-prototype as *deliberately* exempt — it runs its own open-ended Clarify. The
# description's category ("a new mechanic ... scene") covers exactly that command's job and the
# Handoff forbids it, so without this the wave would ship a command whose only route the chain
# closes. Both halves are asserted: the exemption, and the sentence keeping it from becoming an
# escape hatch usable from inside the round.
UB_BOUNDARY="$(ub_section '## The category, and its boundary')"
assert_contains "$UB_BOUNDARY" '**One real exemption, and it is a decision rather than an oversight.**' \
  "D7's /unity-prototype exemption is stated in the payload, not only in the spec"
assert_contains "$UB_BOUNDARY" '/unity-prototype' \
  "and it names the command it routes to"
assert_contains "$UB_HANDOFF" 'cannot be taken from inside it' \
  "the exemption is a pre-round choice, so it cannot be used to escape a round already started"

# --- The exemption list is removed, not reworded ----------------------------------------------
# D2 removes it: a list of exemptions is a list of ways to talk yourself out of the round. Asserted
# by absence because the replacement reads perfectly well beside a surviving exemption section, so a
# positive assertion cannot detect one. The last needle is round 1's finding — ECU's protocol step 4
# carried the `--skip-interview` exemption in prose, and the first three needles did not see it.
while IFS= read -r needle; do
  [ -n "$needle" ] || continue
  assert_not_contains "$brainstorm" "$needle" \
    "the exemption list is gone from unity-brainstorming: $needle"
done <<'UB_GONE'
## When to Activate
## Exemptions
--skip-interview
or when the user explicitly opts out
UB_GONE

# The old name must be gone from the tree, not merely unused. There is no assert_file_absent in the
# runner; this is the file-existence idiom the rest of this file uses, inverted.
UB_OLD_STATE="absent"
if [ -e "$REPO_DIR/.claude/skills/deep-interview/SKILL.md" ]; then UB_OLD_STATE="present"; fi
assert_eq "absent" "$UB_OLD_STATE" \
  "the deep-interview path is gone from the tree, not merely unreferenced"

# ============================================================================
# The manifest row itself.
#
# Field 2 is EXTRACTED and compared, not searched for in the joined row. Searching was round 1's
# vacuity: the note's own text contains `origin=ecu rests on`, so the needle matched the claim
# rather than the field, and flipping field 2 to `superpowers` left 59 assertions passing and 0
# failing. `check-provenance.sh` accepts `superpowers` as an origin too (Task 1 made it legal), so
# nothing else in the repository would have caught it.
UB_ROW="$(awk -F'\t' '$1 == ".claude/skills/unity-brainstorming/SKILL.md"' "$REPO_DIR/provenance.tsv" 2>/dev/null || true)"
UB_ROW_ORIGIN="$(awk -F'\t' '$1 == ".claude/skills/unity-brainstorming/SKILL.md" { print $2 }' "$REPO_DIR/provenance.tsv" 2>/dev/null || true)"
UB_ROW_STATUS="$(awk -F'\t' '$1 == ".claude/skills/unity-brainstorming/SKILL.md" { print $6 }' "$REPO_DIR/provenance.tsv" 2>/dev/null || true)"
assert_eq "ecu" "$UB_ROW_ORIGIN" \
  "unity-brainstorming's row records origin=ecu in FIELD 2 (D10) — not merely somewhere in its note"
# The rationale here read "so no checksum comparison is silently skipped" until 2026-08-11, and it
# had the direction backwards. `check-provenance.sh` gates BOTH of its comparisons on
# `[ "$status" = verbatim ] || continue` — the offline sha256 check at :84 and the --online `cmp` at
# :170 — so `verbatim` is what TRIGGERS a comparison and `modified` is what skips it. Flipping this
# field to `verbatim` runs a check rather than skipping one, and the check fails, because the file
# was rewritten on 2026-08-10 and cannot match ECU's bytes. Measured, offline, no --online needed:
#
#   $ # field 6 of the unity-brainstorming row set to `verbatim`
#   $ bash scripts/check-provenance.sh
#   FAIL status=verbatim but the file differs from its recorded upstream: .claude/skills/unity-brainstorming/SKILL.md
#   provenance check FAILED — 1 problem(s)
#
# So the assertion is right for a different reason than it claimed: the row must not assert a
# byte-identity it does not have. A comment that states a true fact for a false reason survives
# review indefinitely, because the assertion it sits on keeps passing.
assert_eq "modified" "$UB_ROW_STATUS" \
  "and status=modified in field 6 — the file differs from ECU's, so verbatim would be a false claim"

# The note was collapsed to a summary plus a pointer into MERGE-NOTES.md, so the pointer is now
# load-bearing: a renamed section there would silently orphan the file's whole history. Nothing else
# in the suite reads a provenance note, so nothing else could catch it.
UB_MERGE_SECTION='## unity-brainstorming (was deep-interview): the full note history'
assert_contains "$UB_ROW" "$UB_MERGE_SECTION" \
  "the collapsed note points at a MERGE-NOTES.md section by its exact heading"
assert_contains "$(cat "$REPO_DIR/MERGE-NOTES.md" 2>/dev/null || true)" "$UB_MERGE_SECTION" \
  "that MERGE-NOTES.md section exists — the pointer resolves"

# Straight apostrophes. This row was the only one in provenance.tsv using curly ones, which makes it
# unsearchable by the obvious grep and inconsistent with 542 neighbours.
assert_not_contains "$UB_ROW" "’" \
  "the note uses straight apostrophes, like every other row"

# The "thought that means you are about to treat vague as clear" table. MERGE-NOTES.md clause 5 says
# the 2026-08-10 rewrite keeps both rows, and the reverse sweep found both deleting green.
# Heading-anchored and whole, like every other claimed block: the header row and separator are
# included, so a table hollowed out to its header, a third row appended, or the whole table moved to
# an appendix all fail. Round 1 anchored this by the first row's content and caught none of those.
UB_VAGUE_TABLE_EXPECTED='| Thought | Reality | Source |
|---|---|---|
| "They said what they want" | A want is not an acceptance criterion. "Add multiplayer" states a want; it does not say whether success is two players on one screen or matchmaking across regions. | The Ambiguity Score'"'"'s own Acceptance Criteria dimension, and the scoring examples above |
| "The request has a code block, so it is specific" | A code block establishes syntax, not scope. Specificity is about the *outcome* — what done looks like — not about whether the input contains a snippet. | The Ambiguity Score'"'"'s five dimensions, none of which is "contains code" |'
assert_eq "$UB_VAGUE_TABLE_EXPECTED" "$(ub_section '## The thought that means you are about to treat vague as clear' | ub_trim)" \
  "both rows of the vague-as-clear table survive, bodies included, under their own heading"

# ============================================================================
# `using-kinglet` is the injected session brief, and D9 turns it into a mandate.
#
# `.claude/hooks/session-brief.sh` prints this file (minus its frontmatter) at every SessionStart,
# so it is the first text a fresh model reads. The measurement that started the 2026-08-10 wave is
# about exactly this file: across two real runs the chain's behaviour was executed WITHOUT the
# chain's skills ever being loaded, because the table described them well enough to substitute for
# them. D9's repair is three devices — an ordering rule, an announce ritual, and a red-flag table —
# plus a table whose Surface column names surfaces and says nothing about what they contain.
#
# Nothing else in the suite reads this file's content. `test-provenance-origins.sh` scans it for
# three RETIRED names (`unity-workflow`, `unity-feature`, `deep-interview`) and `test-skill-discovery.sh`
# checks its frontmatter; neither can see a mandate softening back into a description.
UK_SKILL="$REPO_DIR/.claude/skills/using-kinglet/SKILL.md"
assert_file_exists "$UK_SKILL" \
  "using-kinglet exists — the SessionStart hook has something to inject"

uk="$(cat "$UK_SKILL" 2>/dev/null || true)"

# Same shape as ub_section above, against a different file. `ub_trim` is file-agnostic (it filters
# stdin), so it is reused rather than duplicated.
uk_section() {
  awk -v want="$1" '
    $0 == want { f = 1; next }
    f && /^#{1,3} / { exit }
    f { print }
  ' "$UK_SKILL" 2>/dev/null || true
}

# --- The frontmatter, which the same insertion sweep found open ---------------------------------
# `test-skill-discovery.sh` checks that `name:` matches the directory and that `description:` is
# non-empty, both by grepping for a line. Neither notices a THIRD line: inserting one after line 1, 2
# or 3 was silent across this whole file's assertions and that file's. The block is two keys and
# stays two keys — an unparseable frontmatter makes a skill invisible to Claude Code with no error,
# and this one is also read by a SessionStart hook that strips whatever sits between the delimiters.
UK_FRONTMATTER_EXPECTED='name: using-kinglet
description: "Use at the start of every session in a Unity project — establishes which Kinglet surface handles which situation, and that a process surface is chosen before code is written."'
assert_eq "$UK_FRONTMATTER_EXPECTED" "$(awk '
    NR == 1 && $0 == "---" { f = 1; next }
    f && $0 == "---" { exit }
    f { print }
' "$UK_SKILL" 2>/dev/null || true)" \
  "the frontmatter is exactly the two keys the convention allows, and the description is unchanged"

# --- The section list, which is also the section BUDGET ----------------------------------------
# Every other assertion in this block compares a section that exists today, and `uk_section` stops at
# the next heading — so a NEW section is invisible to all of them at once. Three insertion points
# were measured, each producing 0 failures against the round-1 guard: a section appended at EOF; a
# section between the intro and `## The rule` (the ordering check only compares Rule against Chain);
# and a paragraph above the table, closed separately below.
#
# The second is the regression this whole wave exists to prevent. A `## What each surface does`
# section containing "`unity-brainstorming` asks, it does not guess" is the summary that made loading
# unnecessary, restored one heading lower than the table it was removed from, injected at every
# session start, and green.
#
# It matches ATX headings only. Setext (`Heading` over `-----`) and raw HTML headings are covered
# not by this assertion but by the tiling of the five whole-block comparisons, which between them
# account for every non-blank line of the file — so relaxing ANY of those five to an `assert_contains`
# silently reopens both. Ruled to the ledger 2026-08-11 as a note rather than a check.
#
# THE BUDGET IS FIVE SECTIONS AND THIS ASSERTION IS WHERE THAT TRADE IS MADE. A sixth requires
# deleting one, here, in the same commit — and the arithmetic has to be argued rather than assumed,
# because this file's whole failure mode is being long enough to substitute for what it points at.
# The round-1 report of this task wrote "I would not add a seventh section without deleting one" and
# that sentence protected nothing: a report is not a constraint. This is.
UK_SECTIONS_EXPECTED='# Using Kinglet
## The rule
## The chain
## The thoughts that mean you are about to skip a surface
## Offer the next step'
assert_eq "$UK_SECTIONS_EXPECTED" "$(awk '/^#+ / { print }' "$UK_SKILL" 2>/dev/null || true)" \
  "the session brief has exactly these five sections, in this order — adding one means removing one"

# --- D9 device 1 and 2: the ordering rule and the announce ritual ------------------------------
# Compared whole. The plan's own guard was three `assert_contains` needles — "before any response or
# action", "Using [skill] to [purpose]" — and each of those is satisfied while the sentence around it
# says the opposite ("...is usually unnecessary before any response or action"). The clause that does
# the work is the last one: it concedes the surface may be wrong and still requires the look. That
# concession is what a rewrite drops, and no single-line needle covers it.
#
# THE LAST TWO SENTENCES ARE THE 2026-08-11 RECONCILIATION AND THEY ARE NOT DECORATION. Until then
# this section ended "you do not have to use it — but you have to have looked", and
# `unity-brainstorming/SKILL.md:113` ended "There is no opt-out." Both ship, both are read at every
# session start, and this one is the LAST text read before the other would load — so the generic
# escape was available to exactly the reader D2 describes, granting the exemption the skill it
# points at refuses. Reconciled in D2's direction, because D2 is the decision: the concession D9
# needs is that a surface can be the wrong one, and the correction for that is to route, never to
# proceed with none.
UK_RULE_EXPECTED='Invoke the surface **before any response or action** — including clarifying questions, reading files,
and exploring the code. Then announce `Using [skill] to [purpose]` and follow it. If it turns out
wrong for the situation, route to the right surface — but you have to have looked, and "wrong
surface" never means "no surface". A surface that states it has no opt-out is not made optional by
this line.'
assert_eq "$UK_RULE_EXPECTED" "$(uk_section '## The rule' | ub_trim)" \
  "the ordering rule and the announce ritual are D9's text, character for character"

# The rule must precede the table it governs. A mandate placed after the routing table is read after
# the reader has already routed — which is the failure being repaired, one level up.
UK_RULE_LINE="$(awk '$0 == "## The rule" { print NR; exit }' "$UK_SKILL" 2>/dev/null || true)"
UK_CHAIN_LINE="$(awk '$0 == "## The chain" { print NR; exit }' "$UK_SKILL" 2>/dev/null || true)"
UK_ORDER="after"
if [ -n "$UK_RULE_LINE" ] && [ -n "$UK_CHAIN_LINE" ] && [ "$UK_RULE_LINE" -lt "$UK_CHAIN_LINE" ]; then
  UK_ORDER="before"
fi
assert_eq "before" "$UK_ORDER" \
  "## The rule sits above ## The chain — the mandate is read before the routing table"

# --- D9's central claim: the Surface column names a surface and does not summarise it -----------
# Asserted STRUCTURALLY, not as a frozen copy of today's table. A frozen table would catch the three
# parentheticals this task removed and nothing else; a future row arriving with a fresh summary is
# the same defect and is what actually has to be prevented.
#
# The rule: strip every backticked span from the Surface cell, then every routing connective. What
# remains must be nothing. Routing is allowed because it is the table's job — `systematic-debugging`,
# then `/unity-fix` tells the reader which surface comes NEXT. A summary tells the reader what the
# surface CONTAINS, which is what let two real runs execute the chain without opening it.
#
# Measured against the three cells this task removed, before removing them:
#
#   `unity-brainstorming` — ask, do not guess                     -> residue: — ask, do not guess
#   `unity-brainstorming`, then `unity-planning`. Depth scales…   -> residue: . Depth scales the round…
#   `unity-planning` first — it adopts the plan and records how…  -> residue: — it adopts the plan…
#
# and against all eleven surviving cells, whose residue is empty.
#
# LEADING WHITESPACE IS PART OF THE PATTERN, in both places below. Markdown accepts up to three
# spaces of indent on a table row and still renders it as a row. Measured against the first version
# of this block, which anchored on a bare `^\|`: a twelfth row inserted mid-table with two spaces of
# indent —
#
#     | A tweak to something that already works | `unity-execution` — it skips the round entirely |
#
# — produced 0 failures and 93 green assertions, and rendered. The row-count anti-vacuity did not
# see it either, so the count was the thing being evaded rather than the thing catching it. The
# identical row unindented fails two assertions. `[[:space:]]*` rather than ` \{0,3\}` because a tab
# indents too and an over-indented row is not a thing this guard should be lenient about.
#
# THE HEADER AND DELIMITER ARE ANCHORED BY POSITION, NOT EXCLUDED BY SHAPE. The first version of
# this collector skipped them with `$0 !~ /^[[:space:]]*\|-/ && $2 !~ /^ *Situation *$/`, and both
# exclusions were escape hatches a twelfth row could simply wear. Measured at 0 failures, rendering,
# and shipped by the hook:
#
#     | Situation | `unity-brainstorming` asks, it does not guess — the file is only needed when you doubt it |
#
# It is a pipe line, so the contiguity check above sees a table row; it matches an exclusion, so the
# count, the residue rule and the existence rule never see it at all. A row beginning `|-` wore the
# other costume with the same result. Worse, inserting either at table position 1 or 2 DISPLACES the
# real header or delimiter: line 2 stops being a delimiter row, the block stops being a table in GFM
# altogether, and a `assert_contains` for `| Situation | Surface |` still finds its needle while the
# count still reads eleven. That is the indent hole one layer down — the eleven-row count is again
# the thing being evaded rather than the thing catching it.
#
# Pre-existing rather than introduced: replayed against 6542d99, also 0 failures.
#
# So: take the table lines in order, assert what lines 1 and 2 ARE, and treat every line after them
# as a row with no exemption of any kind. A costume now makes a twelfth row instead of a hidden one,
# and a displacement fails on the line it displaced.
UK_CHAIN="$(uk_section '## The chain')"
UK_TABLE_LINES="$(awk '/^[[:space:]]*\|/ { print }' <<< "$UK_CHAIN")"

assert_eq '| Situation | Surface |' "$(awk 'NR == 1' <<< "$UK_TABLE_LINES")" \
  "the chain table's FIRST line is its header — not merely a line somewhere that looks like one"
assert_eq '|---|---|' "$(awk 'NR == 2' <<< "$UK_TABLE_LINES")" \
  "…and its SECOND is the delimiter, without which GFM renders no table at all"

UK_ROWS="$(awk 'NR > 2' <<< "$UK_TABLE_LINES")"

# Anti-vacuity: an emptied or renamed table makes every row check below pass on zero rows.
assert_eq "12" "$(printf '%s\n' "$UK_ROWS" | grep -c '^[[:space:]]*|' || true)" \
  "the chain table still has its twelve routing rows for this guard to read"

# The tweak row, added 2026-08-11, and the count above is not what protects it — a count catches a
# deletion and blesses a substitution, and the whole point of this row is WHICH surface it names.
#
# The hole it closes: the escape clause below says "a request to build, change, or fix something is
# work, and work always selects a surface", and until this row existed "make the jump 20% higher" —
# the commonest request a Unity developer makes — matched no row at all. The reader was left to
# force it into `unity-brainstorming`, whose own `description:` ends "Not for a tweak to something
# that already works", or to break the mandate it had just read. Both are worse than a stated route.
#
# Anchored to $UK_ROWS rather than to the file: the rows are what survive the positional header and
# delimiter assertions above, so this cannot be satisfied by the same text written as prose, nor by
# a line smuggled above the real header where the block stops being a table.
assert_contains "$UK_ROWS" \
  '| A tweak — a named field or value in something that already works | `verification-before-completion` |' \
  "a tweak has a row, and it routes to verification rather than to the round that excludes it"

# Nothing but the table may sit between the heading and the first row. `UK_TAIL` below rebuilds its
# buffer at every table row, so anything written ABOVE the table is discarded before it is compared
# — measured: a paragraph inserted between `## The chain` and the header row produced 0 failures.
# The section-list assertion further down cannot see it either, because a paragraph is not a heading.
assert_eq "" "$(awk '/^[[:space:]]*\|/ { exit } { print }' <<< "$UK_CHAIN" | ub_trim)" \
  "the chain section opens with its table — no prose is smuggled in above the first row"

# …and the table is CONTIGUOUS. Same hole one place over, found by inserting a line at each of the
# 65 positions in the file and counting failures: a non-table line between two rows is discarded by
# `UK_TAIL` (which rebuilds its buffer at the next row), leaves the row count at eleven, and sits
# above the preamble check's exit. Twelve positions, lines 23 through 34, were silent. In Markdown
# such a line also ends the table, so every row below it stops being a row.
UK_TABLE_BREAKS="$(awk '
  /^[[:space:]]*\|/ { last = NR; if (!first) first = NR; next }
  { text[NR] = $0 }
  END { for (n = first; n <= last; n++) if (n in text) print "line " n " breaks the table: " text[n] }
' <<< "$UK_CHAIN")"
if [ -n "$UK_TABLE_BREAKS" ]; then
  printf '%s\n' "$UK_TABLE_BREAKS"
fi
assert_eq "0" "$(printf '%s' "$UK_TABLE_BREAKS" | grep -c . || true)" \
  "the chain table is one contiguous block — nothing is written between two rows"

UK_SUMMARIES=""
UK_MISSING_SURFACE=""
while IFS= read -r uk_row; do
  [ -n "$uk_row" ] || continue
  uk_surface="$(awk -F'|' '{ print $3 }' <<< "$uk_row")"
  uk_situation="$(awk -F'|' '{ print $2 }' <<< "$uk_row")"

  # Residue after removing backticked surface names and the routing connectives.
  #
  # Split by `tr` into one word per line and read, not by an unquoted command substitution. The
  # substitution form word-splits (which is wanted) and then PATHNAME-EXPANDS (which is not). Run,
  # not reasoned — from `.claude/skills/`, on a cell whose residue is a single `*`:
  #
  #   $ for w in $stripped; do echo "  [$w]"; done
  #     [addressables]
  #     [assembly-definitions]
  #     [input-system]
  #     ...  16 words seen
  #   $ while IFS= read -r w; do echo "  [$w]"; done <<< "$(tr -s '[:space:]' '\n' <<< "$stripped")"
  #     [*]              1 word seen
  #
  # Sixteen skill directories, none of them in the file. No current cell contains a `*`, which is
  # exactly the shape of latent trap this repo's shell conventions are written unconditionally to
  # prevent — and the residue rule would then have reported a directory listing as the summary.
  uk_residue=""
  while IFS= read -r uk_word; do
    [ -n "$uk_word" ] || continue
    case "$uk_word" in ,|then|or|first) continue ;; esac
    uk_residue="${uk_residue}${uk_word} "
  done <<< "$(sed 's/`[^`]*`//g' <<< "$uk_surface" | tr -s '[:space:]' '\n')"
  if [ -n "$uk_residue" ]; then
    UK_SUMMARIES="${UK_SUMMARIES}Surface column summarises instead of naming: ${uk_residue}"$'\n'
  fi

  # Every backticked token in the Surface column must be a surface that exists.
  #
  # A `/unity-*` token is a command and is covered by the BAD_CMD_REFS block near the top of this
  # file. ANY OTHER slash token is covered by nothing, and the first version of this loop exempted
  # every one of them with a bare `/*) continue`. That was a real hole and not a theoretical one:
  #
  #     | A written plan handed over | `unity-planning` first `/it-adopts-the-plan-and-records-how-it-runs` |
  #
  # gave 0 failures. The span is stripped by the residue rule (it is backticked) and skipped by the
  # existence rule (it starts with a slash), so a summary in that costume passed both halves of the
  # check written to stop summaries. The exemption is now `/unity-*` only.
  #
  # Read line-by-line and QUOTED, for the pathname-expansion reason above and for one more: the
  # unquoted form also word-split the token, so a multi-word backticked span was tested as several
  # separate directory names. It failed — three times, with three confusing messages — rather than
  # once naming the span. Quoted, a `` `unity-brainstorming — ask, do not guess` `` span is one
  # token, fails once, and prints the thing that is wrong.
  while IFS= read -r uk_tok; do
    [ -n "$uk_tok" ] || continue
    case "$uk_tok" in
      /unity-*) continue ;;
      /*)
        UK_MISSING_SURFACE="${UK_MISSING_SURFACE}chain table names a slash token that is no Kinglet command: ${uk_tok}"$'\n'
        continue
        ;;
    esac
    [ -d "$REPO_DIR/.claude/skills/$uk_tok" ] || \
      UK_MISSING_SURFACE="${UK_MISSING_SURFACE}chain table names missing skill: ${uk_tok}"$'\n'
  done <<< "$(grep -o '`[^`]*`' <<< "$uk_surface" | tr -d '`')"

  # The pre-D2 vagueness gate, asserted by absence and by shape. D2 replaced "the request is vague"
  # with an unconditional category of work; the row carrying the old trigger survived the rename and
  # sat ABOVE its replacement until 2026-08-10. A literal-string check would only catch that exact
  # row returning, so the Situation column is also checked for the vocabulary any rewrite of it would
  # use. Scoped to the column: the body legitimately says "about to treat vague as clear".
  for uk_judgment in vague unclear ambiguous; do
    if grep -qF -- "$uk_judgment" <<< "$uk_situation"; then
      UK_SUMMARIES="${UK_SUMMARIES}Situation column judges the request's clarity ('${uk_judgment}') instead of naming a category of work: ${uk_situation}"$'\n'
    fi
  done
done <<< "$UK_ROWS"

if [ -n "$UK_SUMMARIES" ]; then
  printf '%s' "$UK_SUMMARIES"
fi
assert_eq "0" "$(printf '%s' "$UK_SUMMARIES" | grep -c . || true)" \
  "every chain row names surfaces and routes between them — no cell describes what a surface contains"

if [ -n "$UK_MISSING_SURFACE" ]; then
  printf '%s' "$UK_MISSING_SURFACE"
fi
assert_eq "0" "$(printf '%s' "$UK_MISSING_SURFACE" | grep -c . || true)" \
  "every skill the chain table names exists — nothing else checks a skill named inside a skill"

# The four process-chain surfaces are actually routed to. The structural check above passes on a
# table that names only commands, which is what the chain looked like before this wave.
UK_SURFACE_COL="$(awk -F'|' '{ print $3 }' <<< "$UK_ROWS")"
while IFS= read -r uk_needed; do
  [ -n "$uk_needed" ] || continue
  assert_contains "$UK_SURFACE_COL" "\`$uk_needed\`" \
    "the chain routes to the process surface: $uk_needed"
done <<'UK_CHAIN_SURFACES'
unity-brainstorming
unity-planning
subagent-driven-implementation
unity-execution
UK_CHAIN_SURFACES

# --- D9's rewritten escape clause, and the tail it shares with the red-flag pointer -------------
# Rewritten, NOT deleted: the 2026-08-03 wave measured a serialization question correctly selecting
# nothing, and its note records that "a selection here is a regression". What closed is the
# generalisation from "the rules answer this" to "I feel I can answer this". Compared whole, because
# the halves fail differently — drop the first sentence and every rules question drags in a surface;
# drop the second and the file is back to licensing a feeling.
UK_TAIL="$(awk '/^[[:space:]]*\|/ { buf = ""; next } { buf = buf $0 "\n" } END { printf "%s", buf }' <<< "$UK_CHAIN" | ub_trim)"

UK_ESCAPE_EXPECTED='A question about what the rules already state is answered from the rules — that is not work, and it
selects no surface. A request to build, change, or fix something is work, and work always selects a
surface.'
assert_eq "$UK_ESCAPE_EXPECTED" "$(awk 'NF == 0 { exit } { print }' <<< "$UK_TAIL")" \
  "the escape clause draws the line at work versus question, not at confidence (D9)"

# The rest of the chain's tail: the pointer at the three skills' own red-flag sections, and the one
# real exemption. Verified clause by clause against all three skills on 2026-08-10 after a shipped
# false version of it, and compared whole here so that (a) it cannot rot again unnoticed and (b)
# nothing can be inserted between it and the escape clause above.
UK_POINTER_EXPECTED='`unity-brainstorming`, `systematic-debugging` and `verification-before-completion` each carry a "the
thought that means you are about to…" section — read it when the situation feels like an exception,
because that feeling is what it names. `unity-brainstorming`'"'"'s is titled for its own failure mode:
**the thought that means you are about to treat vague as clear**.

What `unity-brainstorming` does not keep is a *list* of exemptions. It has exactly one — a throwaway
scene built to try an idea goes to `/unity-prototype` — and that choice is made before a round
starts, never from inside one.'
assert_eq "$UK_POINTER_EXPECTED" "$(awk 'f { print } NF == 0 { f = 1 }' <<< "$UK_TAIL" | ub_trim)" \
  "the red-flag pointer and the one real exemption follow the escape clause, with nothing between"

# --- D9 device 3: the red-flag table ------------------------------------------------------------
# Five rows of measured rationalizations from THIS toolkit, not Superpowers' generic list. Compared
# whole and heading-anchored: the reality half is the entire value, so a table hollowed out to its
# thoughts, a sixth row appended, or the table relocated to the end of the file all fail.
#
# ROW 4 CARRIES NO NUMBERS, DELIBERATELY. The design spec wrote it as "The block is 41 lines; the
# skill is over 110" — measured when this file was exactly 41 lines. The rewrite that turned it into
# a mandate made the first number wrong (60 injected lines), and measurement made the second
# INVERTED: `systematic-debugging` is 44 lines and `verification-before-completion` is 52, two of the
# three skills this file's own pointer paragraph names. For most of what the chain routes to the
# skill is SHORTER than the block, so a length argument does not merely drift, it argues the wrong
# way. What survives is a claim about exposure rather than size: this block is read at every session
# start and the skill is not. Keeping the row inside this frozen block is the mechanism — the
# numbers rotted unnoticed precisely because nothing had to be edited alongside them.
UK_REDFLAGS_EXPECTED='| Thought | Reality |
|---|---|
| "This request is already clear" | That judgment is made by a model that has just read six rule files and a generated block. It is exactly the one miss that was measured. |
| "The table already tells me what to do" | The table names the file. It is not the file. Twice, the chain was executed without ever loading it. |
| "I am resuming from a ledger, the decision is made" | A ledger records the **mode**. It does not record the design of a new task. |
| "I remember this skill" | You have read this block at the start of every session, and the skill perhaps once. Confidence that strong is evidence of the block, not of the skill. |
| "Let me look at the code first" | The surface is the thing that tells you how to look at it. |'
assert_eq "$UK_REDFLAGS_EXPECTED" \
  "$(uk_section '## The thoughts that mean you are about to skip a surface' | ub_trim)" \
  "the red-flag table carries D9's five measured rationalizations, bodies included"

# --- The two sections a reverse sweep found deleting green ---------------------------------------
# Every line of this file above was proved load-bearing by deleting it and watching an assertion
# fail. A line-by-line sweep of the WHOLE file then found what that proof cannot: two sections with
# no needle pointing at them at all. Both are injected at every session start and both carry
# behaviour, so both are now compared whole.
UK_RULES_EXPECTED='Kinglet is a Unity 6 PC/console toolkit. Five rules in `.claude/rules/` load automatically and
bind: `architecture.md`, `csharp-unity.md`, `performance.md`, `serialization.md`,
`unity-specifics.md`. `pc-console.md` adds platform specifics on top; it does not override them.

**Which of those rules apply to this project is stated in `CLAUDE.md`'"'"'s generated block.** It is
detected from the project'"'"'s own code, not assumed. Read it before asserting that a rule binds.'
assert_eq "$UK_RULES_EXPECTED" "$(uk_section '# Using Kinglet' | ub_trim)" \
  "the session brief still names the five binding rules and points at the generated block"

UK_OFFER_EXPECTED='When a unit of work finishes, name what would sensibly come next and offer it — a review after an
implementation, a test after a fix, a profile after an optimisation. **Offer; do not act.** Starting
a review nobody asked for is worse than waiting to be asked.'
assert_eq "$UK_OFFER_EXPECTED" "$(uk_section '## Offer the next step' | ub_trim)" \
  "the proactive posture is offer-then-wait, not act — restraint stated, not implied"

# --- The manifest row -----------------------------------------------------------------------------
# `check-provenance.sh` never reads the free-text note, so the note's claims about this file are
# guarded here or nowhere. Every clause the row asserts about the 2026-08-10 mandate rewrite — the
# ordering rule, the announce ritual, the red-flag table, the removed vagueness row, and a Surface
# column that names rather than summarises — is an assertion above. Fields 2 and 6 are extracted and
# compared on their own rather than searched for in the joined row, which is how the neighbouring
# unity-brainstorming block was measured vacuous in round 1 of this wave.
UK_ROW_ORIGIN="$(awk -F'\t' '$1 == ".claude/skills/using-kinglet/SKILL.md" { print $2 }' "$REPO_DIR/provenance.tsv" 2>/dev/null || true)"
UK_ROW_STATUS="$(awk -F'\t' '$1 == ".claude/skills/using-kinglet/SKILL.md" { print $6 }' "$REPO_DIR/provenance.tsv" 2>/dev/null || true)"
assert_eq "original" "$UK_ROW_ORIGIN" \
  "using-kinglet's row records origin=original in FIELD 2 — this file was never vendored"
# Same correction as the unity-brainstorming block above, where the wrong rationale was written
# first and then copied here during this wave. `original` does not skip a checksum comparison —
# `verbatim` is the only status --online compares at all, and there is no upstream file to compare
# this one against in any case. What the assertion actually protects: a file written here from
# scratch must not acquire a status that claims an upstream relationship it never had.
assert_eq "original" "$UK_ROW_STATUS" \
  "and status=original in field 6 — nothing upstream to compare it to, and none claimed"

# --- The bytes that actually reach a session -----------------------------------------------------
# Everything above reads the FILE. What ships is the HOOK's output, and nothing in tests/ ran
# `.claude/hooks/session-brief.sh` at all before this block. The gap is not theoretical: the hook
# strips frontmatter with `NR==1 && $0=="---"` … `infm && $0=="---"`, so deleting the CLOSING `---`
# leaves `infm` set for the rest of the file and the hook prints NOTHING and exits 0 — a session
# that opens with no brief at all, silently. Measured: with line 4 removed, every assertion above
# still passed and `test-skill-discovery.sh` passed too.
#
#   $ awk -v skip=4 'NR != skip' SKILL.md > SKILL.md.broken   # closing --- gone
#   deleted line 1 -> FAIL count: 0
#   deleted line 4 -> FAIL count: 0
#
# Deleting the OPENING `---` fails the other way: the hook then prints `name:` and `description:`
# into the session as if they were guidance. The first-line assertion catches both directions at
# once — empty output has no first line, and unstripped output's first line is the `name:` key.
UK_INJECTED="$(CLAUDE_PROJECT_DIR="$REPO_DIR" bash "$REPO_DIR/.claude/hooks/session-brief.sh" 2>/dev/null || true)"

# First NON-BLANK line: the hook strips the frontmatter delimiters but not the blank line that
# followed the closing `---`, so the injected text genuinely begins with an empty line. Measured
# rather than assumed — the first version of this assertion compared line 1 and failed against a
# perfectly healthy file:
#
#   $ CLAUDE_PROJECT_DIR=. bash .claude/hooks/session-brief.sh | head -3 | cat -A
#   $
#   # Using Kinglet$
#   $
assert_eq "# Using Kinglet" "$(awk 'NF { print; exit }' <<< "$UK_INJECTED")" \
  "the SessionStart hook injects the body — not nothing, and not the frontmatter keys"

# And the whole body, not a prefix of it: a hook that truncated or reordered would still open with
# the right heading.
# The whole body, not a prefix of it — and be exact about what this can detect. It re-implements the
# hook's own awk and runs it against the same file, so it is a check on the hook's SCRIPT, not an
# independent reading of its output: it fires when the hook starts filtering, truncating or
# reordering, and it cannot fire on a content divergence, because there is no second source of truth
# for the content to diverge from. Measured, with the closing `---` deleted: both sides are empty and
# this assertion PASSES. The first-non-blank-line assertion above is the one that caught it.
UK_BODY_EXPECTED="$(awk '
    NR == 1 && $0 == "---" { infm = 1; next }
    infm && $0 == "---" { infm = 0; next }
    infm { next }
    { print }
' "$UK_SKILL" 2>/dev/null || true)"
assert_eq "$UK_BODY_EXPECTED" "$UK_INJECTED" \
  "the hook still ships the whole body rather than filtering, truncating or reordering it"

# The mandate itself survives the trip. Redundant while the two assertions above hold, and the one
# that stays meaningful if the hook is ever rewritten to assemble the brief from parts.
assert_contains "$UK_INJECTED" 'Invoke the surface **before any response or action**' \
  "the ordering rule is in the text a fresh session actually reads"

# The chain table's header and delimiter were asserted here, by `assert_contains` against the whole
# section. That form is deleted rather than moved: it answers "does a line like this exist anywhere",
# which stays true when a twelfth row is inserted ABOVE the real header and the block stops being a
# table. Both are now positional `assert_eq`s beside the row collector, where the answer is "is this
# the first line of the table" — see the header-and-delimiter block above.

# --- The execution fork states one threshold, and both branches state the same one ---------------
# `unity-execution` and `subagent-driven-implementation` are the two branches `unity-planning` forks
# to, and a reader picks between them by reading their `description:` fields — that field is the
# entire selection mechanism, and nothing else is consulted at the moment of choosing. So the
# boundary has to appear in both descriptions, and it has to be the same boundary in both.
#
# It was not. The inline branch said prefer the loop above "more than one *substantial* task"; the
# loop said prefer itself above the same phrase with the qualifier dropped. A plan of two trivial
# tasks matched both descriptions at once, and the unqualified form routed it to the branch that
# spends a fresh implementer and a review gate per task — against the exact reason the inline branch
# exists. The qualified phrase survives; the unqualified one is gone.
#
# THE NEGATIVE HALF IS NOT SATISFIED BY THE POSITIVE ONE. The surviving phrase does not contain the
# retired phrase as a substring — the qualifier sits between "one" and "task" — so a file carrying
# only the survivor passes both halves, and a file that regains the looser form fails the second
# while still passing the first. Verified rather than assumed:
#
#   $ grep -qF -- 'more than one task' <<< 'more than one substantial task'; echo $?
#   1
#
# THE TWO HALVES ARE SCOPED DIFFERENTLY, AND THE ASYMMETRY IS THE POINT. They ask different
# questions, so they read different amounts of the file:
#
#   - the POSITIVE reads the FRONTMATTER ONLY, because it asks "does the field a reader selects on
#     say the right thing". Widen it to the body and a paragraph of prose stands in for the
#     description, which is the one thing selection actually reads;
#   - the NEGATIVE reads EVERY `.md` UNDER `.claude/`, because it asks "does anything the payload
#     ships say the wrong thing". Ambiguity returns from wherever it is written, and
#     `unity-execution`'s BODY states this same boundary a third time — at :10-11, wrapped, `:10`
#     ending "…has more than one" and `:11` opening "substantial task, or when…". Neither the spec
#     nor the plan for this wave knew that third statement existed; a frontmatter-scoped absence
#     check cannot see it at all.
#
# THE NEGATIVE'S SCOPE WAS THOSE TWO SKILL.md FILES UNTIL 2026-08-12, WHICH IS A DEFECT THIS FILE
# HAD ALREADY FIXED ONCE, HIGHER UP. The command-reference check above widened from
# `.claude/skills/*/SKILL.md` to `.claude/skills/*/*.md` for exactly the four dispatch templates
# `subagent-driven-implementation` ships beside its SKILL.md — see the "scanned set is not the whole
# reality" note beside it. This block then reinstated the narrow scope a thousand lines below that
# paragraph, under an acceptance criterion reading "no surface **anywhere** carries the retired
# looser form". Two files is not anywhere. Unread by the old scope, and read now: `unity-planning`
# (the surface that OWNS the fork and hands to these two), `using-kinglet` (injected at every session
# start, so a looser threshold there reaches every session), every agent, command and rule, and those
# same four siblings — `implementer-prompt.md`, `task-reviewer-prompt.md`, `re-review-prompt.md`,
# `final-reviewer-prompt.md` — which are the dispatch text the loop branch actually sends.
#
# Both directions are measured, not argued. Rewriting only the BODY sentence to the looser form
# leaves the positive green and turns the negative red; deleting the qualified phrase from only the
# DESCRIPTION, leaving the body intact, turns the positive red and leaves the negative green.
#
# FLATTENING, AND EXACTLY WHAT IT NORMALISES. `grep` is line-oriented and prose is not: a phrase
# split across a wrap cannot be read by any single-line pattern, and an absence check that cannot
# read the text reports absence for the wrong reason — which is worse than no check. The first
# version of this block joined lines with a single appended space and nothing else, and that reads
# exactly ONE wrap shape: the unindented one this file happens to have today. Measured against six,
# it caught one and missed five (indented, blockquoted, trailing-space-before-the-wrap, indented
# YAML continuation, and a double space on a single line). So the normaliser now (a) strips leading
# blockquote markers per line, to any depth, and (b) collapses every whitespace run in the joined
# buffer to one space. Re-measured across ten shapes afterwards: all ten caught, including nested
# blockquotes, tab indentation, a blank line mid-sentence and a list-item continuation.
#
# STATED GAPS — WHAT THIS CANNOT SEE, IN PHRASING AND IN SCOPE. Both halves, because a reader who
# knows only the phrasing limits will over-trust the coverage.
#
# PHRASING. It stays a check for the exact retired phrase returning, NOT for the ambiguity returning
# in new words: `More than one task` capitalised differently, or "more than a single task", both
# pass. That is an accepted limit and it is recorded here rather than papered over. Near-misses were
# probed for false positives in the same pass — "more than one. Task ownership…" and a
# `| more than one | task |` table row both stay correctly silent, because collapsing whitespace
# cannot delete a `.` or a `|`.
#
# SCOPE. The negative half covers every `.md` under `.claude/` — the whole shipped Markdown payload,
# SKILL.md files and their siblings alike, found by `find` rather than by a list, so a new skill or a
# new sibling is in scope the moment it lands. It does NOT cover: anything outside `.claude/` (this
# repo's own `README.md`, `docs/`, `MERGE-NOTES.md` — none of which a user's project receives, so a
# looser threshold there misroutes a maintainer rather than a session); `.claude/settings.json` and
# the hook scripts, which are not Markdown; and `.claude/state/`, which is excluded from the payload
# by install.sh and would be scanned here only if a stray `.md` were left in it. It also reports the
# offending FILE and not a line — the haystack is the file flattened to one buffer, so there is no
# line to report; `grep -n` for the phrase's words to find it.
#
# The positive half is deliberately NOT widened with it. It reads the two branch descriptions only,
# because the question it asks — "does the field a reader selects on say the right thing" — has
# exactly two files that can answer it, and that asymmetry was measured in both directions above.
FORK_NORMALIZE='{ line = $0
    while (line ~ /^[[:space:]]*>/) { sub(/^[[:space:]]*>[[:space:]]?/, "", line) }
    buf = buf " " line }'
FORK_COLLAPSE='END { gsub(/[[:space:]]+/, " ", buf); printf "%s", buf }'

# Built by concatenation from the one normaliser above rather than written out twice — two copies of
# a whitespace rule is precisely how the frontmatter half and the whole-file half would come to
# disagree about what "flattened" means. Single-quoted segments throughout, so awk's `$0` reaches
# awk instead of being expanded by the shell.
FORK_WHOLE_AWK="$FORK_NORMALIZE
$FORK_COLLAPSE"
FORK_FRONTMATTER_AWK='NR == 1 && $0 == "---" { f = 1; next }
f && $0 == "---" { exit }
f '"$FORK_NORMALIZE
$FORK_COLLAPSE"

# Takes a PATH now, not a skill name: the negative half reads files that are not SKILL.md and are
# not under `.claude/skills/` at all, so a helper that rebuilds the path from a skill name cannot
# express its scope.
fork_flatten() {
  awk "$2" "$1" 2>/dev/null || true
}

# The surviving phrase and the retired one, named once. The survivor does NOT contain the retired
# form as a substring — the qualifier sits between "one" and "task" — which is what lets the survivor
# serve as this block's positive control without being its own needle.
FORK_SURVIVOR='more than one substantial task'
FORK_RETIRED='more than one task'

# --- The positive half: the two descriptions a reader picks between -------------------------------
for fork_branch in unity-execution subagent-driven-implementation; do
  fork_front="$(fork_flatten "$REPO_DIR/.claude/skills/$fork_branch/SKILL.md" "$FORK_FRONTMATTER_AWK")"

  # An empty haystack fails a positive assertion and PASSES a negative one — a green that means "the
  # file was never read". This is what keeps the assertion below honest. Measured: emptying either
  # file produces 2 named failures, deleting it produces 2, and breaking the frontmatter fence
  # produces 2 — none of them silent.
  assert_contains "$fork_front" "description:" \
    "$fork_branch's frontmatter was read at all, so the assertion below is about its text"

  assert_contains "$fork_front" "$FORK_SURVIVOR" \
    "$fork_branch states the fork's threshold, in its description, with the qualifier intact"
done

# --- The negative half: every .md the payload ships -----------------------------------------------
# `find`, not a list: a new skill, or a new sibling beside an existing SKILL.md, is in scope the
# moment it lands rather than at the next manual widening. Read into a variable first and fed to the
# loop by here-string, so the counters below live in THIS shell — `find | while read` puts the loop
# in a subshell and every count comes back zero, which is the green-that-means-nothing this block
# spends three assertions guarding against.
FORK_MD_LIST="$(find "$REPO_DIR/.claude" -type f -name '*.md' | sort)"

fork_scanned=0
fork_unread=0
fork_survivor_files=0
fork_loose=""
while IFS= read -r fork_md; do
  [ -n "$fork_md" ] || continue
  fork_scanned=$((fork_scanned + 1))
  fork_flat="$(fork_flatten "$fork_md" "$FORK_WHOLE_AWK")"
  if [ -z "$fork_flat" ]; then fork_unread=$((fork_unread + 1)); fi
  # `case`, not `grep`: no pipe and no subprocess per file, so no SIGPIPE-under-pipefail hazard on a
  # buffer this size. Neither needle carries a glob metacharacter, so `*"$needle"*` is a plain
  # substring test — the same question `grep -F` asks.
  case "$fork_flat" in *"$FORK_SURVIVOR"*) fork_survivor_files=$((fork_survivor_files + 1)) ;; esac
  case "$fork_flat" in *"$FORK_RETIRED"*) fork_loose="$fork_loose${fork_md#"$REPO_DIR"/}"$'\n' ;; esac
done <<< "$FORK_MD_LIST"

# Coverage floor. 44 shipped .md files on 2026-08-12; 35 is that with headroom, matching the floor
# test-shipped-citations.sh sets over the same set. Raise it when the tree grows; never lower one to
# make a run pass. `if/then` rather than `[ … ] && x=yes`, which returns 1 when false and would kill
# this file under the `set -e` it inherits from the runner.
fork_floor_ok=no
if [ "$fork_scanned" -ge 35 ]; then fork_floor_ok=yes; fi
assert_eq "yes" "$fork_floor_ok" \
  "the absence check read $fork_scanned .md files under .claude/ (floor 35)"

# A file that flattens to nothing passes a negative assertion silently. None may.
assert_eq "0" "$fork_unread" \
  "every .md the absence check opened flattened to something it could read"

# Positive control on the SAME machinery the negative uses — awk normaliser, whole-file buffer, `case`
# match — with a needle that is present. Without it, a normaliser that silently produced garbage would
# report "the retired phrase is absent" from every file and read as a clean pass. Floor 2: both fork
# branches state the surviving phrase.
fork_survivor_ok=no
if [ "$fork_survivor_files" -ge 2 ]; then fork_survivor_ok=yes; fi
assert_eq "yes" "$fork_survivor_ok" \
  "the same scan finds the surviving phrase in $fork_survivor_files file(s) (floor 2)"

if [ -n "$fork_loose" ]; then
  printf '%s' "$fork_loose" | sed 's|^|       carries the retired threshold: |'
fi
assert_eq "0" "$(printf '%s' "$fork_loose" | grep -c . || true)" \
  "no surface anywhere under .claude/ states the looser threshold with the qualifier dropped"
