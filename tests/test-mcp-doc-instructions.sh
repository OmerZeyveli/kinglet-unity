#!/usr/bin/env bash
# ============================================================================
# test-mcp-doc-instructions.sh — no instruction in .claude/ OR in the
# repository's own documentation sends a reader back to the file Claude Code
# never reads MCP config from.
#
# Round 3 (2026-07-29, controller sweep after Task 8) found the SAME stale
# claim in six places outside .claude/: CLAUDE.md, CREDITS.md, README.md,
# docs/ARCHITECTURE.md, docs/GETTING-STARTED.md (two spots, one of which
# the sweep itself missed — see the widening note below), and MERGE-NOTES.md.
# All six are fixed in the same commit that widens this guard past .claude/.
# See the "Round 3" section near the end of this file for the widened scan,
# its exclusion list, and why MERGE-NOTES.md is handled separately from it.
#
# Round 4 (2026-07-30, wave-1b1 final review) found a SEVENTH instance the
# Round 3 window missed by six characters: docs/ARCHITECTURE.md's own
# "Settings.json Structure" heading sat 126 characters from the mcpServers key
# in the JSON sample below it — past the 120-character bound. Rather than
# widen the number (the next instance is free to land past whatever it grows
# to), this file now also runs a fenced-code-block scan with no distance bound
# at all: it tracks each block's governing Markdown heading and flags a block
# only when that heading names settings.json (not .mcp.json) AND the block
# itself carries an mcpServers key. See the "Round 4" section for the scan,
# and why docs/ARCHITECTURE.md joins MERGE-NOTES.md as excluded from the
# Round 3 proximity scan (the same reason MERGE-NOTES.md was: the correction
# has to say both words close together to explain itself). The Round 3
# proximity scan and its 120-character window are UNCHANGED and remain in
# place for the prose-level cases it still catches; the fenced-block scan is
# additive, not a replacement.
#
# Task 2 moved MCP server configuration to .mcp.json at the project root,
# because Claude Code silently ignores an mcpServers key inside settings.json.
# Task 8 round 1 found two stale instructions pointing at the dead location:
#   .claude/commands/unity-doctor.md:19  — fixed, same commit as this test.
#   docs/GETTING-STARTED.md:173          — fixed, same commit, but is NOT
#       scanned here: it lives under docs/, and this guard is deliberately
#       scoped to .claude/ — see the scope note below.
# Round 2 (reviewer finding) found a THIRD, in .claude/NOTICE.md:23 — fixed in
# the same commit that widened this test. It read across a line break ("...is
# **not** included here." / "`settings.json` merely points at it..."), which
# the original same-line-only pattern below could not see. That is why the
# scan is now per-FILE with folded whitespace instead of per-LINE — see the
# widening note further down.
#
# Two OTHER references to settings.json + MCP are legitimate and must survive
# any future sweep:
#   scripts/studio-doctor.sh:85 (comment) and MCP-SETUP.md:120 (prose) both
#   EXPLAIN why settings.json is a last-resort / broken fallback — history,
#   not instruction. Neither file lives under .claude/, so this guard's scope
#   already excludes both without needing a named exclusion list. That is not
#   an accident: it is why the guard is scoped to .claude/ rather than the
#   whole repo. A repo-wide version of this same idea would have to carry an
#   exclusion list (naming those two files, by path, with the reason above);
#   scoping to .claude/ makes that unnecessary today. If either explanatory
#   file is ever moved under .claude/, or a NEW explanatory comment about this
#   history is added inside .claude/, it WILL trip this guard — at which point
#   it needs a real by-path exclusion, not a rewrite of the pattern.
#
# --- What the pattern matches, and the widening from round 1 to round 2 ---
#
# Round 1 matched `settings.json` and `mcp` (case-insensitive) on the SAME
# LINE only. That missed .claude/NOTICE.md:23, whose sentence break put
# "settings.json" one line below the "MCP" it referred to. A test that can
# only see same-line references is blind to any reference split across a line
# break — that was a real limitation, not a bug in the regex, and it let a
# genuine instance through.
#
# Round 2 widens the scan to work PER FILE instead of per line: each tracked
# file under .claude/ has its newlines folded to spaces (`tr '\n' ' '`), then
# the same idea — `settings.json` and `mcp` within a bounded distance of each
# other, case-insensitive — is applied to the whole folded file via a bounded
# regex interval (`.{0,120}` either direction) instead of a same-line
# character class. Folding first, rather than trying to match across a
# literal newline, keeps the pattern itself simple (no multiline-mode grep
# flags to get subtly wrong) and keeps the distance bound meaningful in
# characters rather than "lines," which vary wildly in length across prose.
# 120 was picked by measuring the actual distance in NOTICE.md's real
# instance (~94 characters from the nearest "mcp" substring to
# "settings.json") and rounding up for margin, not by guessing.
#
# This still catches the same-line case from round 1 (distance 0 satisfies
# `.{0,120}` trivially) — verified below by the same canary string round 1
# used — so nothing already covered was lost by the widening.
#
# What remains a genuine, stated limitation: two references to settings.json
# and mcp that are BOTH real but separated by more than ~120 characters in
# the same file (e.g. one in an opening paragraph, an explanation many
# paragraphs later) will still slip past this guard. That shape has not been
# seen in this repo in either round of this task; if it appears, the bound
# needs to grow or the approach needs to change again. This comment exists so
# the next person reads a green run as "no same-file, nearby reference
# survives" — not as "the class of defect is closed."
# ============================================================================

# ── The three sweeps in this file must have swept something ─────────────────
#
# All three scans here (`TMDI_TRACKED`, `TMDI3_TRACKED`, `TMDI4_ALL_TRACKED`) index by
# `git ls-files`. With no git index every one of them yields the empty string, every `while` loop
# reads a single blank line and `continue`s, every HITS variable stays empty, and every
# `assert_eq "" "$HITS"` passes. Measured 2026-08-14 against a `git archive HEAD | tar -x`
# extraction — this repository's documented probe method — this file reported **23 passed, 0
# failed**, identical in every respect to a healthy run, having opened no file at all.
#
# The canaries further down do NOT cover this, and that distinction is the whole point. They prove
# the PATTERN still catches a reconstructed offender, by running it against a string built inside
# this file; they say nothing about whether the pattern was ever run over the repository. A pattern
# that binds perfectly, applied to nothing, is the shape being closed here.
#
# One guard for all three, because all three read the same index: if `.claude/` is listable and
# populated, `*.md` and `docs/` are being listed by the same machinery. The floor is 30 against 62
# tracked paths under `.claude/` today — below any plausible surface removal, far enough above zero
# that a pathspec which stops matching is caught rather than rounded off.
TMDI_INDEX_ERR="$(mktemp "${TMPDIR:-/tmp}/tmdi-index-err.XXXXXX")"
TMDI_INDEX_RC=0
TMDI_TRACKED=$( ( cd "$REPO_DIR" && git ls-files -- .claude/ ) 2>"$TMDI_INDEX_ERR" ) || TMDI_INDEX_RC=$?
TMDI_INDEX_N=$(printf '%s' "$TMDI_TRACKED" | grep -c . || true)
TMDI_INDEX_STATE="ok"
if [ "$TMDI_INDEX_RC" -ne 0 ]; then
    TMDI_INDEX_STATE="git could not list .claude/ (exit $TMDI_INDEX_RC): $(tr '\n' ' ' < "$TMDI_INDEX_ERR")"
elif [ "$TMDI_INDEX_N" -lt 30 ]; then
    TMDI_INDEX_STATE="only $TMDI_INDEX_N tracked path(s) under .claude/, which is fewer than this payload can have"
fi
rm -f "$TMDI_INDEX_ERR"
assert_eq "ok" "$TMDI_INDEX_STATE" \
    "the sweeps in this file have files to read — an unreadable index must not certify the same green as a clean payload"

TMDI_HITS=""
while IFS= read -r tmdi_relpath; do
    [ -z "$tmdi_relpath" ] && continue
    tmdi_abspath="${REPO_DIR}/${tmdi_relpath}"
    [ -f "$tmdi_abspath" ] || continue
    tmdi_match=$(tr '\n' ' ' < "$tmdi_abspath" \
        | grep -ioE 'settings\.json.{0,120}mcp|mcp.{0,120}settings\.json' || true)
    if [ -n "$tmdi_match" ]; then
        TMDI_HITS="${TMDI_HITS}${tmdi_relpath}: ${tmdi_match}
"
    fi
done <<< "$TMDI_TRACKED"

if [ -n "$TMDI_HITS" ]; then
    echo "--- offending file(s) in .claude/ still tie settings.json to MCP config ---"
    echo "$TMDI_HITS"
    echo "--- end offenders ---"
fi
assert_eq "" "$TMDI_HITS" \
    "no file under .claude/ ties settings.json to MCP config within ~120 characters"

# --- Guard: the pattern still binds (proves it isn't accidentally matching
# nothing forevermore). Two canaries: the round-1 same-line wording, and the
# round-2 cross-line wording that NOTICE.md actually carried.
TMDI_CANARY_SAMELINE='Check `.claude/settings.json` -> `mcpServers.unityMCP.url`'
TMDI_CANARY_CROSSLINE='The Unity MCP bridge is not included here.
`settings.json` merely points at it on localhost.'

TMDI_SAMELINE_CAUGHT="missed"
if printf '%s' "$TMDI_CANARY_SAMELINE" | tr '\n' ' ' \
        | grep -ioE 'settings\.json.{0,120}mcp|mcp.{0,120}settings\.json' > /dev/null; then
    TMDI_SAMELINE_CAUGHT="caught"
fi
assert_eq "caught" "$TMDI_SAMELINE_CAUGHT" \
    "the pattern still catches the round-1 same-line stale instruction"

TMDI_CROSSLINE_CAUGHT="missed"
if printf '%s' "$TMDI_CANARY_CROSSLINE" | tr '\n' ' ' \
        | grep -ioE 'settings\.json.{0,120}mcp|mcp.{0,120}settings\.json' > /dev/null; then
    TMDI_CROSSLINE_CAUGHT="caught"
fi
assert_eq "caught" "$TMDI_CROSSLINE_CAUGHT" \
    "the pattern now catches a reference split across a line break, like NOTICE.md's was"

# --- Positive controls: the fixed instructions now name the real location ---
#
# The expected server spelling is derived from install.sh's own heredoc, never hardcoded — the
# same reasoning tests/test-mcp-naming.sh already applies. A hardcoded literal here would itself be
# a stale-casing incident waiting to happen: finding 4 of the 2026-08-03 second-pass review was
# exactly this guard holding the old lowercase "unityMCP" in place as a positive control, so fixing
# unity-doctor.md's casing made the assertion's input empty and failed the test.
TMDI_SHIPPED_SERVER=$(awk -F'"' '/^ *"[A-Za-z]*MCP": \{/ {print $2; exit}' "$REPO_DIR/install.sh")
assert_eq "1" "$([ -n "$TMDI_SHIPPED_SERVER" ] && echo 1 || echo 0)" \
    "the MCP server name derivation from install.sh still yields a non-empty string"

TMDI_DOCTOR_LINE=$(grep -n "mcpServers\.${TMDI_SHIPPED_SERVER}\.url" "${REPO_DIR}/.claude/commands/unity-doctor.md" || true)
assert_contains "$TMDI_DOCTOR_LINE" ".mcp.json" \
    "unity-doctor.md's MCP connectivity check now names .mcp.json, not settings.json"

TMDI_NOTICE=$(cat "${REPO_DIR}/.claude/NOTICE.md")
assert_contains "$TMDI_NOTICE" "\`.mcp.json\` merely points at it" \
    "NOTICE.md's MCP-bridge sentence now names .mcp.json, not settings.json"

# ============================================================================
# Round 3 — widen past .claude/ to the repository's own documentation.
#
# The .claude/ scan above is unchanged: it is the payload a user's project
# receives, and the reasoning above it still holds. This section is a
# SEPARATE scan over root-level and docs/ Markdown, because a controller
# sweep after Task 8 found the identical stale claim ("settings.json holds
# MCP config") in six places no .claude/-scoped guard could ever see.
#
# --- Scope: every tracked root-level *.md, plus every tracked docs/**/*.md ---
#
# This is deliberately a moving target, not a fixed file list: a new doc added
# under docs/ tomorrow is in scope automatically. Only paths named below are
# excluded, each for a stated reason — a new file is never exempt by default.
#
# --- Excluded, by exact path/prefix, each because it EXPLAINS the mistake
# rather than repeating it (deleting the words would delete the evidence) ---
#
#   MCP-SETUP.md                        — the whole document's job is to record
#                                          why settings.json is the WRONG place;
#                                          the brief names lines 5, 101, 120
#                                          specifically, but the surrounding
#                                          prose repeats the same juxtaposition
#                                          deliberately, so the exclusion is the
#                                          whole file, not three lines.
#   docs/research/pioneer/smoke-pass.md — the investigative record of the exact
#                                          finding that motivated this whole
#                                          guard (Task 8's origin).
#   docs/superpowers/plans/*            — frozen plan documents; historical
#                                          record of what was planned, not a
#                                          claim about current behavior.
#   docs/superpowers/specs/*            — frozen spec documents; same reasoning.
#
# MERGE-NOTES.md is tracked docs but is EXCLUDED from this proximity scan and
# checked separately below (see "MERGE-NOTES.md" section) — it is a historical
# build record whose OTHER entries legitimately place "settings.json" and
# "mcp" near each other while describing what was true when it was written
# (e.g. "Part 1 did not ship a settings.json ... We ship .claude/settings.json
# now"). A same-file proximity match cannot distinguish past tense from
# present tense; a human already made that call for this file (the same
# treatment MERGE-NOTES.md's own repo-name entry received during the product
# rename, tense-fixing "was originally ... later renamed" rather than
# rewriting the history) and it is not something a regex should re-decide.
#
# docs/ARCHITECTURE.md is EXCLUDED here for the same class of reason, added in
# the fix for the reviewer's six-characters-past-the-window finding: its
# "Settings.json Structure" section corrects a stale mcpServers example, and
# the correction sentence necessarily explains the settings.json/MCP
# relationship — it says both words within 120 characters BECAUSE it is
# telling the truth about them, not because it repeats the error. It is
# checked narrowly instead, below (see "docs/ARCHITECTURE.md: the corrected
# Settings.json Structure section"), and by the fenced-code-block scan further
# down, which is a permanent, structural replacement for this file's slice of
# the proximity heuristic (see that scan's header for why it does not have
# this same false-positive problem).
#
# scripts/studio-doctor.sh's explanatory comment needs no exclusion entry:
# it is a .sh file, not a root *.md or docs/**/*.md, so this scan's scope
# never reaches it — the same reason it never needed one in the .claude/-only
# scan above.
#
# --- What this does NOT solve, stated plainly ---
#
# This is a proximity heuristic, not a grammar checker. It cannot tell "X used
# to be true" from "X is true" within a single juxtaposition — that is exactly
# why MERGE-NOTES.md and docs/ARCHITECTURE.md both needed a human call instead
# of being folded into this scan. If a future doc mixes historical and current
# claims about settings.json/MCP the same way, it will need the same judgment
# call and the same kind of narrow, line-anchored check below instead of being
# added to this proximity scan. The fenced-code-block scan further down closes
# the specific defect class that motivated this file (a code sample shown as
# settings.json content that actually carries an mcpServers key) without this
# limitation — see its header for why.

tmdi3_is_excluded() {
    case "$1" in
        MCP-SETUP.md) return 0 ;;
        MERGE-NOTES.md) return 0 ;;
        docs/ARCHITECTURE.md) return 0 ;;
        docs/research/pioneer/smoke-pass.md) return 0 ;;
        docs/superpowers/plans/*) return 0 ;;
        docs/superpowers/specs/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Classifier self-check: proves the exclusion list is a named allowlist of
# exceptions, not a stand-in for "skip everything" — including a check that a
# BRAND NEW, never-seen doc path is still classified as in-scope.
TMDI3_CLASSIFY_FAILURES=""
for tmdi3_case in \
    "MCP-SETUP.md:excluded" \
    "MERGE-NOTES.md:excluded" \
    "docs/ARCHITECTURE.md:excluded" \
    "docs/research/pioneer/smoke-pass.md:excluded" \
    "docs/superpowers/plans/2026-07-22-kinglet-01-identity-foundation.md:excluded" \
    "docs/superpowers/specs/2026-07-22-kinglet-for-unity-design.md:excluded" \
    "CLAUDE.md:included" \
    "README.md:included" \
    "docs/GETTING-STARTED.md:included" \
    "docs/some-brand-new-doc-nobody-has-written-yet.md:included" \
; do
    tmdi3_path="${tmdi3_case%%:*}"
    tmdi3_expected="${tmdi3_case##*:}"
    if tmdi3_is_excluded "$tmdi3_path"; then
        tmdi3_actual="excluded"
    else
        tmdi3_actual="included"
    fi
    if [ "$tmdi3_actual" != "$tmdi3_expected" ]; then
        TMDI3_CLASSIFY_FAILURES="${TMDI3_CLASSIFY_FAILURES}${tmdi3_path}: expected ${tmdi3_expected}, got ${tmdi3_actual}
"
    fi
done
assert_eq "" "$TMDI3_CLASSIFY_FAILURES" \
    "the exclusion classifier only exempts the named paths -- a brand-new doc is scanned by default"

# --- The scan itself: root *.md (non-recursive) + every docs/**/*.md ---
TMDI3_ROOT_MD=$(cd "$REPO_DIR" && git ls-files -- '*.md' | grep -v '/' || true)
TMDI3_DOCS_MD=$(cd "$REPO_DIR" && git ls-files -- 'docs/' | grep '\.md$' || true)
TMDI3_TRACKED=$(printf '%s\n%s\n' "$TMDI3_ROOT_MD" "$TMDI3_DOCS_MD")

TMDI3_HITS=""
while IFS= read -r tmdi3_relpath; do
    [ -z "$tmdi3_relpath" ] && continue
    tmdi3_is_excluded "$tmdi3_relpath" && continue
    tmdi3_abspath="${REPO_DIR}/${tmdi3_relpath}"
    [ -f "$tmdi3_abspath" ] || continue
    tmdi3_match=$(tr '\n' ' ' < "$tmdi3_abspath" \
        | grep -ioE 'settings\.json.{0,120}mcp|mcp.{0,120}settings\.json' || true)
    if [ -n "$tmdi3_match" ]; then
        TMDI3_HITS="${TMDI3_HITS}${tmdi3_relpath}: ${tmdi3_match}
"
    fi
done <<< "$TMDI3_TRACKED"

if [ -n "$TMDI3_HITS" ]; then
    echo "--- offending repository doc(s) still tie settings.json to MCP config ---"
    echo "$TMDI3_HITS"
    echo "--- end offenders ---"
fi
assert_eq "" "$TMDI3_HITS" \
    "no non-excluded repository doc ties settings.json to MCP config within ~120 characters"

# --- Positive controls: the six corrected locations now name .mcp.json ---
TMDI3_CLAUDE_MD=$(cat "${REPO_DIR}/CLAUDE.md")
assert_contains "$TMDI3_CLAUDE_MD" "\`.mcp.json\` points at it on \`localhost:8080\`" \
    "CLAUDE.md's unity-mcp bullet now names .mcp.json, not settings.json"

TMDI3_CREDITS_MD=$(cat "${REPO_DIR}/CREDITS.md")
assert_contains "$TMDI3_CREDITS_MD" "Our \`.mcp.json\` points at it on \`http://localhost:8080/mcp\`" \
    "CREDITS.md's MCP bridge paragraph now names .mcp.json, not settings.json"

TMDI3_README_MD=$(cat "${REPO_DIR}/README.md")
assert_contains "$TMDI3_README_MD" "preconfigured in \`.mcp.json\`" \
    "README.md's One MCP bullet now names .mcp.json, not settings.json"

TMDI3_ARCH_MD=$(cat "${REPO_DIR}/docs/ARCHITECTURE.md")
assert_not_contains "$TMDI3_ARCH_MD" "settings.json      Configuration: permissions, MCP servers" \
    "docs/ARCHITECTURE.md's component tree no longer credits settings.json with MCP servers"

TMDI3_GETTING_STARTED_MD=$(cat "${REPO_DIR}/docs/GETTING-STARTED.md")
assert_not_contains "$TMDI3_GETTING_STARTED_MD" "settings.json    Permissions, MCP server config" \
    "docs/GETTING-STARTED.md's directory tree no longer credits settings.json with MCP server config"
assert_contains "$TMDI3_GETTING_STARTED_MD" "The \`.mcp.json\` is already configured to connect" \
    "docs/GETTING-STARTED.md's setup step 4 now names .mcp.json, not settings.json"

# --- MERGE-NOTES.md: the judgment call. Not scanned by the proximity check
# above (see the exclusion rationale). Checked narrowly instead: the specific
# table row is anchored by stable surrounding text (the package name), then
# asserted to have the tense-honest wording and NOT the flatly-present-tense
# stale wording it used to carry. Its other entries (Part 1/Part 2 history)
# are untouched and are not re-checked here -- they were never wrong.
TMDI3_MERGE_ROW=$(grep "com.coplaydev.unity-mcp" "${REPO_DIR}/MERGE-NOTES.md" | grep "not vendored" || true)
assert_contains "$TMDI3_MERGE_ROW" "used to point at it on localhost" \
    "MERGE-NOTES.md's unity-mcp row now states the settings.json claim in the past tense"
assert_contains "$TMDI3_MERGE_ROW" "\`.mcp.json\`" \
    "MERGE-NOTES.md's unity-mcp row now names where MCP config actually lives"
assert_not_contains "$TMDI3_MERGE_ROW" "\`settings.json\` points at it on localhost." \
    "MERGE-NOTES.md's unity-mcp row no longer states the stale claim as a present-tense fact"

# --- docs/ARCHITECTURE.md: the corrected Settings.json Structure section. ---
# The judgment call above (excluded from the proximity scan). Checked narrowly instead: the
# section's JSON code sample must no longer carry an mcpServers key (the actual finding — a reader
# copying that code block would reproduce the dead configuration), and the corrective prose that
# replaced it must state where MCP config actually lives.
TMDI3_ARCH_SETTINGS_SECTION=$(awk '
    /^## Settings\.json Structure/ { p = 1; print; next }
    p && /^## / { exit }
    p { print }
' "${REPO_DIR}/docs/ARCHITECTURE.md")
# The code sample only, not the whole section — the corrective prose right below it legitimately
# says "mcpServers" (that is the word it is correcting the record about), so checking the whole
# section for absence of the word would fail on the fix itself.
TMDI3_ARCH_SETTINGS_CODE=$(awk '
    /^## Settings\.json Structure/ { p = 1; next }
    p && /^## / { exit }
    p && /^```/ { inblock = !inblock; next }
    p && inblock { print }
' "${REPO_DIR}/docs/ARCHITECTURE.md")
assert_not_contains "$TMDI3_ARCH_SETTINGS_CODE" "mcpServers" \
    "docs/ARCHITECTURE.md's Settings.json Structure code sample no longer shows an mcpServers key"
assert_contains "$TMDI3_ARCH_SETTINGS_SECTION" "has no \`mcpServers\` key, and never has" \
    "docs/ARCHITECTURE.md's Settings.json Structure section now states settings.json carries no mcpServers key"
assert_contains "$TMDI3_ARCH_SETTINGS_SECTION" "\`.mcp.json\` at the project root" \
    "docs/ARCHITECTURE.md's Settings.json Structure section now names where the MCP entry actually lives"

# ============================================================================
# Round 4 — fenced-code-block scan: the durable replacement for this file's
# specific defect class, not just a wider window.
#
# The reviewer's finding was a code sample: a "Settings.json Structure" heading
# followed by a fenced JSON block that carried an mcpServers key 126 characters
# past this test's 120-character window — a gap of exactly six characters. A
# wider window buys margin, not closure: whatever number replaces 120, the
# next stale example is free to sit one character past it. And the window's
# actual failure mode cuts the other way too — MERGE-NOTES.md and
# docs/ARCHITECTURE.md both have to be EXCLUDED from the proximity scan
# because correcting the claim in prose necessarily says "settings.json" and
# "mcp" close together. A single distance bound cannot both catch the code
# sample and ignore the correction that mentions the same two words to explain
# it: it has no way to tell which juxtaposition it is looking at.
#
# A code sample does not have that ambiguity. It is not prose explaining
# history — it is something a reader will copy verbatim, and its "topic" is
# unambiguous: the heading immediately governing it. So this scan is per
# FENCED BLOCK, not per file: track the nearest preceding Markdown heading as
# each block is read, and flag a block only when BOTH hold:
#   1. its governing heading mentions settings.json (and not .mcp.json — a
#      block correctly documenting .mcp.json's own structure, which legitimately
#      contains mcpServers, is introduced by a heading naming .mcp.json instead);
#   2. the block's own content contains the mcpServers key.
#
# This has no distance bound to outgrow, and does not need docs/ARCHITECTURE.md
# or MERGE-NOTES.md excluded from it — a hit here is the actual defect, not a
# proximity coincidence, and (as confirmed below) it finds zero matches across
# every currently-tracked file, including the ones the proximity scan cannot
# safely look at.
tmdi4_fenced_block_hits() {
    local file="$1"
    awk '
        BEGIN { heading = ""; inblock = 0; sawmcp = 0; bstart = 0 }
        /^```/ {
            if (inblock == 0) {
                inblock = 1
                sawmcp = 0
                bstart = NR
            } else {
                inblock = 0
                h = tolower(heading)
                if (sawmcp && h ~ /settings\.json/ && h !~ /\.mcp\.json/) {
                    print FILENAME ":" bstart "-" NR ": heading=[" heading "]"
                }
            }
            next
        }
        /^#+[ \t]/ { heading = $0 }
        {
            if (inblock == 1 && tolower($0) ~ /mcpservers/) { sawmcp = 1 }
        }
    ' "$file"
}

TMDI4_HITS=""
TMDI4_ALL_TRACKED=$(cd "$REPO_DIR" && git ls-files -- .claude/ '*.md' 'docs/')
while IFS= read -r tmdi4_relpath; do
    [ -z "$tmdi4_relpath" ] && continue
    case "$tmdi4_relpath" in
        *.md) ;;
        *) continue ;;
    esac
    tmdi4_abspath="${REPO_DIR}/${tmdi4_relpath}"
    [ -f "$tmdi4_abspath" ] || continue
    tmdi4_match=$(tmdi4_fenced_block_hits "$tmdi4_abspath")
    if [ -n "$tmdi4_match" ]; then
        TMDI4_HITS="${TMDI4_HITS}${tmdi4_relpath}: ${tmdi4_match}
"
    fi
done <<< "$TMDI4_ALL_TRACKED"

if [ -n "$TMDI4_HITS" ]; then
    echo "--- fenced code block(s) shown under a settings.json heading still carry mcpServers ---"
    echo "$TMDI4_HITS"
    echo "--- end offenders ---"
fi
assert_eq "" "$TMDI4_HITS" \
    "no fenced code block under a settings.json heading (in any tracked .md, including excluded-from-proximity-scan files) carries an mcpServers key"

# Canary: the scan still binds. Reconstruct the reviewer's exact original finding as a fixture and
# confirm this scan catches it — proving a green result above means "found nothing," not "checked
# nothing."
TMDI4_FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/tmdi4-fixture.XXXXXX")/bad.md"
cat > "$TMDI4_FIXTURE" <<'TMDI4EOF'
## Settings.json Structure

```json
{
  "permissions": {},
  "mcpServers": {
    "unityMCP": { "url": "http://localhost:8080/mcp" }
  }
}
```
TMDI4EOF
TMDI4_CANARY=$(tmdi4_fenced_block_hits "$TMDI4_FIXTURE")
rm -rf "$(dirname "$TMDI4_FIXTURE")"
assert_contains "$TMDI4_CANARY" "Settings.json Structure" \
    "the fenced-code-block scan still catches the reviewer's exact original finding, reconstructed"

# Canary: a block correctly documenting .mcp.json's OWN structure (which legitimately contains
# mcpServers) must NOT be flagged just because it mentions settings.json somewhere else in the
# file's other headings.
TMDI4_GOOD_FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/tmdi4-good-fixture.XXXXXX")/good.md"
cat > "$TMDI4_GOOD_FIXTURE" <<'TMDI4EOF'
## Settings.json Structure

```json
{
  "permissions": {},
  "hooks": {}
}
```

## .mcp.json Structure

```json
{
  "mcpServers": {
    "unityMCP": { "url": "http://localhost:8080/mcp" }
  }
}
```
TMDI4EOF
TMDI4_GOOD_CANARY=$(tmdi4_fenced_block_hits "$TMDI4_GOOD_FIXTURE")
rm -rf "$(dirname "$TMDI4_GOOD_FIXTURE")"
assert_eq "" "$TMDI4_GOOD_CANARY" \
    "the fenced-code-block scan does not flag a block correctly documenting .mcp.json's own mcpServers structure"
