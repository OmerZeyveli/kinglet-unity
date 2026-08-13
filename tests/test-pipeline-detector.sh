#!/usr/bin/env bash
# ============================================================================
# test-pipeline-detector.sh — there is ONE render-pipeline detector, every surface that displays a
# pipeline verdict gets it from that detector, and all of them say the same thing.
#
# WHY THIS FILE EXISTS, AND WHY IT IS NOT A PAIRWISE COMPARISON ALONE.
#
# install.sh and scripts/generate-claude-md.sh each carried their own copy of this detection.
# install.sh ran two unconditional greps with HDRP last, so HDRP won; generate-claude-md.sh used
# if/elif with URP first, so URP won. One install of a project carrying both packages printed
# `HDRP` on the console and wrote `URP` into that project's own CLAUDE.md, and routed the
# urp-pipeline skill off the second answer. Neither implementation had a both-present state at all.
#
# The whole suite stayed green through every day of that, and the reason is the point of this file:
# **the two implementations AGREED for as long as they both had three states.** Pairwise comparison
# catches a re-fork that gets it wrong on a case you already thought to build. It does not catch a
# re-fork that is right today and drifts later — which is the failure that actually happened. So the
# first two assertions here are not comparisons at all. They are sweeps that assert the detector is
# the ONLY implementation and that its caller set is CLOSED, so a second implementation is a change
# someone has to argue for rather than a line that quietly passes.
#
# The pairwise half is still here, and it is what catches the other direction — a caller that stops
# routing through the detector and hardcodes a verdict, which names neither needle and so is
# invisible to both sweeps. Neither half is worth much alone.
#
# ── THE THREE PARTS ─────────────────────────────────────────────────────────
#
#   A. SOLE IMPLEMENTATION. The set of files under the roots that name `render-pipelines` equals a
#      two-entry allow-list, by SET EQUALITY in both directions.
#   B. CLOSED CALLER SET. The set of files under the roots that name `detect-pipeline` equals a
#      four-entry allow-list, likewise by set equality.
#   C. THREE SURFACES AGREE, over eight fixtures covering all four tokens: install.sh's console
#      line, the generated CLAUDE.md's Render Pipeline cell, and whether the urp-pipeline skill is
#      suggested — each checked against the DETECTOR'S TOKEN, never against another surface's prose.
#
# SET EQUALITY, NOT "NOTHING OUTSIDE THE ALLOW-LIST", and the difference is the whole guard. A
# subset check passes on EMPTY OUTPUT: rename `scripts/`, delete detect-pipeline.sh, mistype the
# needle, and a one-directional check reports green having read nothing. Both sweeps below therefore
# also fail when an allow-listed path stops matching, which is the same assertion run backwards and
# is what keeps them from decaying into no-ops.
#
# ASSERTED AGAINST THE TOKEN, NEVER AGAINST THE PROSE. Part C maps the detector's token to the set
# of pipeline NAMES each surface must mention — {URP}, {HDRP}, {URP, HDRP}, {Built-in} — and checks
# that set. It does not compare display strings, and it does not compare one surface against
# another. Coupling to prose is precisely what the shared detector removed: generate-claude-md.sh
# used to route the urp-pipeline skill off a `*URP*` glob over its own display string, so rewording
# a sentence silently rerouted a skill. A test written that way would put the coupling back.
#
# ── WHAT THIS FILE CANNOT SEE ───────────────────────────────────────────────
#
# SWEEP A (sole implementation):
#   * A RE-FORK THAT DOES NOT CARRY THE LITERAL. The needle is a package-id fragment, not the
#     concept. A detector that greps for `"universal"` alone, that assembles the package id from
#     concatenated parts, that reads ProjectSettings/GraphicsSettings.asset (the deeper answer the
#     design's D3 deliberately declines), or that simply hardcodes a verdict with no detection at
#     all, is invisible here. Part C is what covers the hardcoded case, and only for the two
#     surfaces it runs.
#   * ANYTHING ADDED INSIDE AN ALLOW-LISTED FILE. The allow-list is by FILE. scripts/
#     detect-pipeline.sh growing a second, contradictory verdict, or urp-pipeline/SKILL.md growing a
#     "here is how to detect your pipeline" snippet an agent would then run, both pass. It is a
#     file-level check, so it counts files and not occurrences: a file going from 4 matches to 40 is
#     the same result.
#   * ANYTHING OUTSIDE THE FOUR ROOTS. tests/ is unswept — including tests/fixtures/mkproject.sh,
#     which the same commit as this file makes match the needle, and which is an INPUT rather than a
#     verdict producer. templates/, tools/, docs/ and every other repo-root file are unswept too.
#   * ANYTHING UNDER .claude/state/, excluded by name. That is machine-local runtime state the
#     installer writes and .gitignore excludes, and it is a live hazard rather than a theoretical
#     one: measured 2026-08-13, the untracked .claude/state/session-edits.txt and session.json on
#     this machine ALREADY match sweep B's needle. Without the exclusion sweep B would be red here
#     and green on a fresh clone — a flake whose obvious "fix" is to widen the allow-list, which
#     would then hide the thing the allow-list exists to surface.
#
# SWEEP B (closed caller set):
#   * A CALLER THAT KEEPS THE NAME AND DROPS THE CALL. A comment or a stale doc line mentioning
#     detect-pipeline.sh keeps a file in the set while its verdict comes from somewhere else. Part C
#     is the behavioural half that catches that, for install.sh and generate-claude-md.sh.
#   * A THIRD SURFACE THAT NAMES NEITHER NEEDLE. A hook that hardcodes "URP" is outside both sweeps.
#
# PART C (three surfaces):
#   * IT ASSERTS INTERNAL AGREEMENT, NOT EXTERNAL CORRECTNESS. Every fixture's ground truth here is
#     which packages the manifest lists. The detector reports package PRESENCE, and this file holds
#     the surfaces to that same standard — so a future detector that read GraphicsSettings.asset and
#     answered "which pipeline is ACTIVE" would go red against these fixtures for being right. That
#     is a deliberate limit, not an oversight: what is asserted is that the toolkit speaks with one
#     voice, and the voice's accuracy is the subject of detect-pipeline.sh's own header.
#   * ONLY THE PIPELINE NAMES ARE READ. A surface could reword its sentence into nonsense and stay
#     green so long as it still names the right pipelines and no others.
#   * IT CANNOT SEE THE ROUTING'S *SOURCE*, ONLY ITS OUTCOME — measured, not assumed. Reverting
#     suggest_skills to the `case "$RENDER_PIPELINE" in *URP*)` prose glob the shared detector
#     removed produces ZERO reds here: against today's four display strings that glob happens to
#     give the same answer as the token for all four tokens, so the coupling is invisible while the
#     prose agrees. It becomes visible the moment the prose diverges — the same mutation plus one
#     innocent rewording of the HDRP string to "…(HDRP), not URP" reddens the hdrp fixture twice,
#     on the cell and on the routing. So this file catches the CONSEQUENCE of prose coupling and not
#     the coupling itself, which is the very "agreement on the easy case is worth nothing" problem
#     it was written about, one level up. Asserting the source would mean asserting the SHAPE of one
#     line of generate-claude-md.sh — a change-detector that reddens on innocent refactors — and the
#     judgement recorded here is that the outcome guard plus that script's own comment is the better
#     trade. It is recorded rather than closed so the next person can retake the decision.
#   * ONLY `--dry-run --yes` IS EXERCISED. No --with-mcp, no --with-input-system, no interactive
#     branch. install.sh computes RENDER_PIPELINE once, before the dry-run block, so the real run
#     reaches the same value — but that is read off the code, not asserted here, and a SECOND
#     verdict computed later in a real run would be unseen.
#   * ONE PROJECT SHAPE PER TOKEN. Eight fixtures, four tokens. A manifest whose pipeline package
#     arrives some other way — a local package under Packages/, a git URL, a scoped registry — is
#     not built by any of them.
#   * THE `bare` AND `builtin` FIXTURES BOTH YIELD `builtin` FOR DIFFERENT REASONS (no manifest at
#     all vs. a manifest naming neither package). That is intentional coverage, but it means the
#     token alone cannot tell those two paths apart in a failure message.
#   * NOTHING HERE PROVES ANYTHING ABOUT BEHAVIOUR INSIDE CLAUDE CODE. It proves that three surfaces
#     of a shell toolkit agree with one detector on a synthetic project directory, and no more.
# ============================================================================
# Self-contained: own set -euo pipefail, own pass/fail, REPO from BASH_SOURCE. The runner's assert_*
# helpers are deliberately NOT used — the runner does `set +e` before sourcing, so an undefined
# helper prints to stderr and contributes no FAIL: token, and this file would report green on the
# defect it exists to catch.
set -euo pipefail

# ${BASH_SOURCE[0]}, not $0: the runner does `( source "$test_file" )`, and inside a sourced file $0
# is the *sourcing* shell's $0.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

# PASS/FAIL, not ok/FAIL: run-tests.sh aggregates by grepping each file's output for those tokens.
# No message below may contain a bare `FAIL` token of its own — the runner tallies on it, and a
# failure message echoing its own needle would be counted twice.
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'PASS: %s\n' "$1"; }

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# ── Parts A and B: the sweeps ────────────────────────────────────────────────
#
# THE ROOTS. Four, and they are the surfaces that could COMPUTE or ASSERT a pipeline verdict:
# install.sh, uninstall.sh, everything in scripts/ (which ships into .claude/scripts/), and the
# whole payload under .claude/ — agents, commands, skills, hooks and rules alike, because a skill
# that tells an agent how to detect the pipeline is a second implementation in this toolkit's terms
# even though it is prose. uninstall.sh is here beyond what the plan named: it is a shipped
# top-level script that could grow detection, it costs nothing today, and leaving it out would have
# made "the detector is the only implementation" a claim about three files out of four.
#
# `grep`, not `/usr/bin/grep`. The ugrep-wrapping shell FUNCTION that makes an unescaped `$`
# mid-pattern behave differently is an INTERACTIVE-shell thing; run-tests.sh sources this file into
# a subshell of a non-interactive `bash tests/run-tests.sh`, which loads no rc file, so `grep` here
# is the binary. -F besides, so the needle is a literal and no regex dialect can differ over it.
SWEEP_ERR="$SCRATCH/sweep.err"
SWEEP_OUT=""
SWEEP_RC=0
sweep() {
  SWEEP_RC=0
  # `cd "$REPO" && grep … | sort` parses as `cd && (grep | sort)`: `|` binds tighter than `&&`.
  # `sort` drains its input to the end, so it cannot SIGPIPE the grep under pipefail.
  SWEEP_OUT="$(cd "$REPO" && grep -rlF --exclude-dir=state -- "$1" \
      .claude/ scripts/ install.sh uninstall.sh 2>"$SWEEP_ERR" | LC_ALL=C sort)" || SWEEP_RC=$?
}

# $1 = human label, $2 = needle, $3 = newline-separated allow-list.
assert_sweep() {
  local label="$1" needle="$2" allow="$3" want got
  sweep "$needle"
  # rc 0 = matched, 1 = matched nothing, 2+ = the sweep itself broke (a renamed root, an
  # --exclude-dir this grep does not support, no grep at all). A broken sweep must be loud: silently
  # treating it as "no matches" is how a guard becomes a no-op that reports green.
  if [ "$SWEEP_RC" -ge 2 ]; then
    fail "$label: the sweep for '$needle' exited $SWEEP_RC instead of searching — it read nothing, so its silence means nothing: $(tr '\n' ' ' < "$SWEEP_ERR")"
    return 0
  fi
  want="$(printf '%s\n' "$allow" | LC_ALL=C sort)"
  got="$SWEEP_OUT"
  if [ "$got" = "$want" ]; then
    pass "$label: exactly the allow-listed path(s) name '$needle' under the four roots — $(printf '%s' "$got" | tr '\n' ' ')"
  else
    fail "$label: the set of files naming '$needle' is not the allow-list. Expected [$(printf '%s' "$want" | tr '\n' ' ')] and observed [$(printf '%s' "$got" | tr '\n' ' ')]. A path that appeared is a second implementation or a new caller and needs a decision; a path that vanished means this guard just stopped reading what it claims to."
  fi
}

# ALLOW-LIST A — who may name the package id.
#   scripts/detect-pipeline.sh          the implementation itself. This is the point.
#   .claude/skills/urp-pipeline/SKILL.md a skill ABOUT URP. Its four matches are HLSL #include paths
#                                       (Packages/com.unity.render-pipelines.universal/ShaderLibrary/…)
#                                       in shader examples — the package id used as a FILE PATH, not
#                                       as a detection probe. Legitimate, and not detection.
assert_sweep 'sole implementation' 'render-pipelines' '.claude/skills/urp-pipeline/SKILL.md
scripts/detect-pipeline.sh'

# ALLOW-LIST B — who may name the detector.
#   scripts/detect-pipeline.sh          its own header and usage text.
#   install.sh                          caller 1, for the console line.
#   scripts/generate-claude-md.sh       caller 2, for the CLAUDE.md facts block and skill routing.
#   .claude/commands/unity-init.md      PROSE, not a caller: it tells the agent which script is the
#                                       one detector and what its fourth state means. Allow-listed
#                                       rather than excluded because a command that starts telling
#                                       the agent to detect the pipeline some other way is exactly
#                                       the change this sweep should make someone argue for.
assert_sweep 'closed caller set' 'detect-pipeline' '.claude/commands/unity-init.md
install.sh
scripts/detect-pipeline.sh
scripts/generate-claude-md.sh'

# ── Part C: three surfaces, one token ────────────────────────────────────────

# Substring test in pure bash — no pipe, no subshell, nothing that can exit early.
contains() { case "$2" in *"$1"*) return 0 ;; *) return 1 ;; esac; }

# Strip ANSI. install.sh colours only when stdout is a tty and this captures it, so this is belt and
# braces — but a guard whose needle silently fails to match a coloured line is the exact shape of the
# suite-header miscount this repository documents at length.
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# $1 fixture label, $2 surface label, $3 the text, $4/$5/$6 = want URP / HDRP / Built-in named.
assert_names() {
  local fx="$1" surface="$2" text="$3" wu="$4" wh="$5" wb="$6"
  local gu=0 gh=0 gb=0
  # "URP" is not a substring of "HDRP" (H-D-R-P has no U), so these three tests are independent.
  if contains 'URP' "$text";      then gu=1; fi
  if contains 'HDRP' "$text";     then gh=1; fi
  if contains 'Built-in' "$text"; then gb=1; fi
  if [ "$gu" = "$wu" ] && [ "$gh" = "$wh" ] && [ "$gb" = "$wb" ]; then
    pass "$fx: $surface names exactly the pipeline(s) the token implies — \"$text\""
  else
    fail "$fx: $surface names the wrong pipeline set. Wanted URP=$wu HDRP=$wh Built-in=$wb, observed URP=$gu HDRP=$gh Built-in=$gb, in \"$text\""
  fi
}

# Pointed at a path that does not exist so install.sh's provider detection takes the same branch on
# every machine, matching tests/test-install-dryrun.sh.
ABSENT_SETTINGS="$SCRATCH/absent-user-settings.json"

# Every token the fixture set actually produced, so the set can be checked for discrimination at the
# end. This is the assertion the pre-2026-08-13 suite was missing: two implementations disagreed for
# weeks and nothing went red, because every fixture in the tree produced one of two tokens and the
# two implementations only differ on the third and fourth.
SEEN_TOKENS=""

for fx in urp builtin bare dirty legacy async-mixed hdrp both; do
  d="$SCRATCH/$fx"

  # mkproject.sh runs under its own `set -euo pipefail` and one uncaught failure inside it would
  # otherwise leave a half-built or absent directory that every assertion below silently describes.
  mk_rc=0
  bash "$REPO/tests/fixtures/mkproject.sh" "$d" --variant "$fx" >/dev/null 2>"$SCRATCH/$fx.mkerr" || mk_rc=$?
  if [ "$mk_rc" -ne 0 ] || [ ! -d "$d/Assets" ] || [ ! -d "$d/ProjectSettings" ]; then
    fail "$fx: mkproject.sh exited $mk_rc without producing Assets/ + ProjectSettings/ — every assertion for this fixture would describe a project that was never built: $(tr '\n' ' ' < "$SCRATCH/$fx.mkerr")"
    continue
  fi

  # ── Surface 0: the detector. The source of truth every other assertion is measured against.
  det_rc=0
  token="$(bash "$REPO/scripts/detect-pipeline.sh" "$d" 2>"$SCRATCH/$fx.deterr")" || det_rc=$?
  if [ "$det_rc" -ne 0 ]; then
    fail "$fx: detect-pipeline.sh exited $det_rc — there is no token to hold the other surfaces to: $(tr '\n' ' ' < "$SCRATCH/$fx.deterr")"
    continue
  fi

  case "$token" in
    builtin)  wu=0; wh=0; wb=1; want_skill=0 ;;
    urp)      wu=1; wh=0; wb=0; want_skill=1 ;;
    hdrp)     wu=0; wh=1; wb=0; want_skill=0 ;;
    # urp+hdrp suggests urp-pipeline deliberately: the URP package IS present, the block is a
    # suggestion about relevant knowledge rather than a verdict about what renders, and there is no
    # hdrp-pipeline skill to balance it against. generate-claude-md.sh states the same reasoning at
    # the case it routes from; this is the assertion that the reasoning stays applied.
    urp+hdrp) wu=1; wh=1; wb=0; want_skill=1 ;;
    *)
      fail "$fx: detect-pipeline.sh printed '$token', which is not one of the four documented tokens — its callers' case statements each have a catch-all, so this would surface as prose rather than as an error"
      continue
      ;;
  esac
  SEEN_TOKENS="$SEEN_TOKENS$token
"
  pass "$fx: the detector answers '$token'"

  # ── Surface 1: install.sh's console line.
  inst_rc=0
  inst_out="$(KINGLET_USER_SETTINGS="$ABSENT_SETTINGS" bash "$REPO/install.sh" \
      --project-dir "$d" --dry-run --yes 2>&1 | strip_ansi)" || inst_rc=$?
  if [ "$inst_rc" -ne 0 ]; then
    fail "$fx: install.sh --dry-run exited $inst_rc, so its pipeline line was never printed"
  else
    # Here-string, not a pipe: awk here reads to EOF anyway, but the whole file keeps to forms that
    # cannot SIGPIPE a writer under pipefail.
    inst_line="$(awk '/ Unity [0-9]/ && !s { line = $0; s = 1 } END { print line }' <<< "$inst_out")"
    if [ -z "$inst_line" ]; then
      fail "$fx: install.sh --dry-run printed no 'Unity <version>' line at all — the console surface this test compares does not exist in that run"
    else
      # Everything after the separator, so the Unity version cannot contribute to the name test.
      assert_names "$fx" "install.sh's console line" "${inst_line#* · }" "$wu" "$wh" "$wb"
    fi
  fi

  # ── Surfaces 2 and 3: the generated CLAUDE.md.
  gen_rc=0
  gen_out="$(bash "$REPO/scripts/generate-claude-md.sh" "$d" 2>"$SCRATCH/$fx.generr")" || gen_rc=$?
  if [ "$gen_rc" -ne 0 ]; then
    fail "$fx: generate-claude-md.sh exited $gen_rc, so neither the Render Pipeline cell nor the skill list exists to check: $(tr '\n' ' ' < "$SCRATCH/$fx.generr")"
  else
    # `| **Render Pipeline** | <cell> |` split on `|` gives the cell as field 3.
    gen_cell="$(awk -F'|' '/\*\*Render Pipeline\*\*/ && !s { c = $3; s = 1 } END { print c }' <<< "$gen_out")"
    if [ -z "$gen_cell" ]; then
      fail "$fx: the generated document has no '| **Render Pipeline** |' row — the cell this test compares does not exist"
    else
      assert_names "$fx" "the generated CLAUDE.md's Render Pipeline cell" "$gen_cell" "$wu" "$wh" "$wb"
    fi

    # grep -q on a HERE-STRING, not on a pipe. -q exits on first match without draining stdin, and
    # a pipe writer would take SIGPIPE, pipefail would promote 141 and set -e would end the file.
    got_skill=0
    if grep -qxF -- '- `urp-pipeline`' <<< "$gen_out"; then got_skill=1; fi
    if [ "$got_skill" = "$want_skill" ]; then
      pass "$fx: urp-pipeline suggested=$got_skill, which is what the token '$token' calls for"
    else
      fail "$fx: the urp-pipeline skill routing disagrees with the detector — token '$token' calls for suggested=$want_skill and the document has suggested=$got_skill. The routing must follow the token, never a display string."
    fi
  fi
done

# ── The fixture set must discriminate ────────────────────────────────────────
# Without this, a mkproject.sh regression that quietly stopped building the hdrp and both manifests
# would leave every assertion above green while covering only the two tokens on which the two old
# implementations already agreed. That is not a hypothetical failure mode — it is the one that let
# the original defect live in a fully green tree.
observed="$(printf '%s' "$SEEN_TOKENS" | LC_ALL=C sort -u | tr '\n' ' ')"
if [ "$observed" = "builtin hdrp urp urp+hdrp " ]; then
  pass "the fixture set produces all four detector tokens — $observed"
else
  fail "the fixture set does not cover all four tokens. Expected 'builtin hdrp urp urp+hdrp ' and observed '$observed'. A token nobody builds is a branch nothing above tested, and the two implementations this detector replaced agreed on every token they shared."
fi

if [ "$FAILURES" -eq 0 ]; then
  echo "all pipeline-detector assertions passed"
else
  echo "pipeline-detector assertions with problems: $FAILURES"
  exit 1
fi
